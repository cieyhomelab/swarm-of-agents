#!/usr/bin/env bats
# Unit tests for the scripts/test-e2e.sh contract with a fake docker binary.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  STUBS="$(mktemp -d)"
  export DOCKER_LOG="$STUBS/docker.log"
  # Fake docker: logs every call; `run` fails or hangs on request.
  cat > "$STUBS/docker" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$DOCKER_LOG"
case "$*" in
  *" run "*)
    [ "${FAKE_DOCKER_RUN:-ok}" = fail ] && exit 1
    [ "${FAKE_DOCKER_RUN:-ok}" = hang ] && { sleep 30 & wait; }
    ;;
esac
exit 0
EOF
  chmod +x "$STUBS/docker"
  export PATH="$STUBS:$PATH"
  export SH_SECRETS_DIR="$STUBS/no-secrets"
}

teardown() { rm -rf "$STUBS"; }

@test "random project name when E2E_RUN_ID is unset" {
  unset E2E_RUN_ID
  E2E_PRINT_PROJECT=1 run bash "$ROOT/scripts/test-e2e.sh"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^e2e-[0-9a-f]{8}$ ]]
}

@test "two unset runs get different project names" {
  unset E2E_RUN_ID
  a="$(E2E_PRINT_PROJECT=1 bash "$ROOT/scripts/test-e2e.sh")"
  b="$(E2E_PRINT_PROJECT=1 bash "$ROOT/scripts/test-e2e.sh")"
  [ "$a" != "$b" ]
}

@test "project name uses E2E_RUN_ID when set" {
  E2E_RUN_ID=abc E2E_PRINT_PROJECT=1 run bash "$ROOT/scripts/test-e2e.sh"
  [ "$status" -eq 0 ]
  [ "$output" = "e2e-abc" ]
}

@test "invalid E2E_RUN_ID is refused before docker runs" {
  E2E_RUN_ID="Bad Id" run bash "$ROOT/scripts/test-e2e.sh"
  [ "$status" -eq 2 ]
  [ ! -s "$DOCKER_LOG" ]
}

@test "success builds, runs and cleans up with volumes and local images" {
  E2E_RUN_ID=ok run bash "$ROOT/scripts/test-e2e.sh"
  [ "$status" -eq 0 ]
  grep -q -- "-p e2e-ok -f compose.yml build" "$DOCKER_LOG"
  grep -q -- "-p e2e-ok -f compose.yml run --rm runner bats tests/e2e" "$DOCKER_LOG"
  grep -q -- "-p e2e-ok -f compose.yml down -v --remove-orphans --rmi local" "$DOCKER_LOG"
}

@test "failing tests still clean up and fail" {
  E2E_RUN_ID=bad FAKE_DOCKER_RUN=fail run bash "$ROOT/scripts/test-e2e.sh"
  [ "$status" -ne 0 ]
  grep -q -- "-p e2e-bad -f compose.yml down -v" "$DOCKER_LOG"
}

@test "SIGTERM stops the run quickly and cleans up" {
  E2E_RUN_ID=term FAKE_DOCKER_RUN=hang bash "$ROOT/scripts/test-e2e.sh" &
  pid=$!
  for _ in $(seq 1 50); do grep -q " run " "$DOCKER_LOG" 2>/dev/null && break; sleep 0.1; done
  start=$SECONDS
  kill -TERM "$pid"
  wait "$pid" || true
  [ $((SECONDS - start)) -lt 10 ]
  grep -q -- "-p e2e-term -f compose.yml down -v" "$DOCKER_LOG"
}

@test "subset of test files is passed to bats" {
  E2E_RUN_ID=sub run bash "$ROOT/scripts/test-e2e.sh" tests/e2e/sweep.bats
  [ "$status" -eq 0 ]
  grep -q -- "run --rm runner bats tests/e2e/sweep.bats" "$DOCKER_LOG"
}
