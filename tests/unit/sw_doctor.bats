#!/usr/bin/env bats
# Unit tests for bin/sw-doctor with stubbed gh and curl.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  STUBS="$(mktemp -d)"
  printf '#!/usr/bin/env bash\necho cieyhomelab\n' > "$STUBS/gh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$STUBS/curl"
  chmod +x "$STUBS/gh" "$STUBS/curl"
  export PATH="$STUBS:$PATH"
  unset ANTHROPIC_API_KEY
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

@test "logged-out gh is reported" {
  printf '#!/usr/bin/env bash\nexit 1\n' > "$STUBS/gh"
  run "$ROOT/bin/sw-doctor"
  [ "$status" -eq 1 ]
  [[ "$output" == *"gh nie jest zalogowany"* ]]
}

@test "unreachable Cezar is reported" {
  printf '#!/usr/bin/env bash\nexit 7\n' > "$STUBS/curl"
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
