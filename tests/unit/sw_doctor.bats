#!/usr/bin/env bats
# Unit tests for bin/sw-doctor and bin/sw-gate with stubbed gh and curl.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  STUBS="$(mktemp -d)"
  # gh: `api user` -> login, `api repos/...` -> private flag ($STUB_PRIVATE).
  cat > "$STUBS/gh" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *"api user"*) echo cieyhomelab ;;
  *"api repos/"*) [ "${STUB_PRIVATE:-true}" = missing ] && exit 1; echo "${STUB_PRIVATE:-true}" ;;
  *) exit 2 ;;
esac
EOF
  # curl: health and workspace config JSON.
  cat > "$STUBS/curl" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *workspace/config*) echo "{\"resources\":{\"maxParallel\":${STUB_MAX_PARALLEL:-3}}}" ;;
  *health*) echo '{"version":"1.0.0","projects":[]}' ;;
  *) exit 22 ;;
esac
EOF
  chmod +x "$STUBS/gh" "$STUBS/curl"
  export PATH="$STUBS:$PATH"
  unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN ANTHROPIC_BASE_URL \
        CLAUDE_CODE_USE_BEDROCK CLAUDE_CODE_USE_VERTEX CLAUDE_CODE_USE_FOUNDRY
}

teardown() { rm -rf "$STUBS"; }

@test "healthy runtime prints STAN: OK" {
  run "$ROOT/bin/sw-doctor"
  [ "$status" -eq 0 ]
  [ "$output" = "STAN: OK" ]
}

@test "API key in the environment is a failure" {
  ANTHROPIC_API_KEY=sk-test run "$ROOT/bin/sw-doctor"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ANTHROPIC_API_KEY"* ]]
}

@test "gateway and cloud provider variables are failures" {
  for var in ANTHROPIC_AUTH_TOKEN ANTHROPIC_BASE_URL CLAUDE_CODE_USE_BEDROCK CLAUDE_CODE_USE_VERTEX CLAUDE_CODE_USE_FOUNDRY; do
    run env "$var=1" "$ROOT/bin/sw-doctor"
    [ "$status" -eq 1 ]
    [[ "$output" == *"$var"* ]]
  done
}

@test "logged-out gh is reported" {
  printf '#!/usr/bin/env bash\nexit 1\n' > "$STUBS/gh"
  run "$ROOT/bin/sw-doctor"
  [ "$status" -eq 1 ]
  [[ "$output" == *"gh nie jest zalogowany"* ]]
}

@test "public control repository is a failure" {
  STUB_PRIVATE=false run "$ROOT/bin/sw-doctor"
  [ "$status" -eq 1 ]
  [[ "$output" == *"nie jest prywatne"* ]]
}

@test "missing control repository is only a warning" {
  STUB_PRIVATE=missing run "$ROOT/bin/sw-doctor"
  [ "$status" -eq 0 ]
  [[ "$output" == *"STAN: OK"* ]]
  [[ "$output" == *"UWAGA: repozytorium sterujace"* ]]
}

@test "workspace parallelism below the configured limit is a warning" {
  STUB_MAX_PARALLEL=2 run "$ROOT/bin/sw-doctor"
  [ "$status" -eq 0 ]
  [[ "$output" == *"UWAGA: resources.maxParallel"* ]]
}

@test "unreachable Cezar is reported" {
  printf '#!/usr/bin/env bash\nexit 7\n' > "$STUBS/curl"
  run "$ROOT/bin/sw-doctor"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Cezar niedostepny"* ]]
}

@test "a non-Cezar answer on the health address is reported" {
  printf '#!/usr/bin/env bash\necho "<html>spa</html>"\n' > "$STUBS/curl"
  run "$ROOT/bin/sw-doctor"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Cezar niedostepny"* ]]
}

@test "invalid configuration is reported" {
  bad="$(mktemp)"; echo 'not json' > "$bad"
  SW_CONFIG="$bad" run "$ROOT/bin/sw-doctor"
  rm -f "$bad"
  [ "$status" -eq 1 ]
  [[ "$output" == *"niepoprawna konfiguracja"* ]]
}

@test "sw-gate decides nothing on a healthy runtime" {
  run "$ROOT/bin/sw-gate"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "STAN: OK" ]
  [ "${lines[1]}" = "URUCHOM: NIC" ]
}

@test "sw-gate fails but still prints a decision on a broken runtime" {
  printf '#!/usr/bin/env bash\nexit 7\n' > "$STUBS/curl"
  run "$ROOT/bin/sw-gate"
  [ "$status" -eq 1 ]
  [[ "$output" == *"URUCHOM: NIC"* ]]
}

@test "empty answer from Cezar is reported (jq 1.6 empty-input behaviour)" {
  printf '#!/usr/bin/env bash\nexit 0\n' > "$STUBS/curl"
  run "$ROOT/bin/sw-doctor"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Cezar niedostepny"* ]]
}
