#!/usr/bin/env bats
# Integration: bin/sw-doctor and bin/sw-gate against the mock Cezar/GitHub API
# over real HTTP (curl) and the fake gh CLI.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  WORK="$(mktemp -d)"
  python3 "$ROOT/tests/tools/mock_api.py" --port 0 --port-file "$WORK/port" &
  MOCK_PID=$!
  for _ in $(seq 1 50); do [ -s "$WORK/port" ] && break; sleep 0.1; done
  PORT="$(cat "$WORK/port")"
  export SW_CEZAR_URL="http://127.0.0.1:$PORT"
  export FAKE_GH_API_URL="http://127.0.0.1:$PORT"
  export PATH="$ROOT/tests/fakes:$PATH"
  unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN ANTHROPIC_BASE_URL \
        CLAUDE_CODE_USE_BEDROCK CLAUDE_CODE_USE_VERTEX CLAUDE_CODE_USE_FOUNDRY
}

teardown() {
  kill "$MOCK_PID" 2>/dev/null || true
  rm -rf "$WORK"
}

control() { curl -fsS -X POST -d "$1" "$SW_CEZAR_URL/__control" >/dev/null; }

@test "healthy services give STAN: OK and, without a project, URUCHOM: GENERATOR" {
  run "$ROOT/bin/sw-gate"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "STAN: OK" ]
  [ "${lines[1]}" = "URUCHOM: GENERATOR" ]
}

@test "Cezar health failure is detected" {
  control '{"health_status": 503}'
  run "$ROOT/bin/sw-doctor"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Cezar niedostepny"* ]]
}

@test "GitHub authentication failure is detected" {
  control '{"github_user": null}'
  run "$ROOT/bin/sw-doctor"
  [ "$status" -eq 1 ]
  [[ "$output" == *"gh nie jest zalogowany"* ]]
}

@test "public control repository is detected" {
  control '{"control_private": false}'
  run "$ROOT/bin/sw-doctor"
  [ "$status" -eq 1 ]
  [[ "$output" == *"nie jest prywatne"* ]]
}

@test "the gate is read-only: only GET requests reach the APIs" {
  run "$ROOT/bin/sw-gate"
  requests="$(curl -fsS "$SW_CEZAR_URL/__requests")"
  [ "$(printf '%s' "$requests" | jq '[.[] | select(.method != "GET" and .path != "/__control")] | length')" -eq 0 ]
}
