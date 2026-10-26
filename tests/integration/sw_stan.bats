#!/usr/bin/env bats
# Integration: bin/sw-stan (the state transitions of the build task) against the mock GitHub API.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  WORK="$(mktemp -d)"
  python3 "$ROOT/tests/tools/mock_api.py" --port 0 --port-file "$WORK/port" &
  MOCK_PID=$!
  for _ in $(seq 1 50); do [ -s "$WORK/port" ] && break; sleep 0.1; done
  PORT="$(cat "$WORK/port")"
  export SW_CEZAR_URL="http://127.0.0.1:$PORT" FAKE_GH_API_URL="http://127.0.0.1:$PORT"
  export PATH="$ROOT/tests/fakes:$PATH"
  cd "$WORK" || return 1
  printf '# Planer\n\nPomysł i jego ocena: https://github.com/cieyhomelab/sw-control/issues/7\n' > README.md
}

teardown() {
  kill "$MOCK_PID" 2>/dev/null || true
  rm -rf "$WORK"
}

control() { curl -fsS -X POST -d "$1" "$SW_CEZAR_URL/__control" >/dev/null; }
labels() { curl -fsS -X POST -d '{}' "$SW_CEZAR_URL/__control" | jq -c '.issues[] | select(.number == 7) | [.labels[].name]'; }
idea() {
  control "{\"issues\": [{\"number\": 1, \"state\": \"open\", \"title\": \"sw-dziennik\", \"labels\": [{\"name\": \"sw-dziennik\"}]},
    {\"number\": 7, \"state\": \"${2:-open}\", \"title\": \"Planer\", \"labels\": $1, \"body\": \"x\"}]}"
}

@test "S7 moves the project one state forward and keeps the other labels" {
  idea '[{"name":"sw-pomysl"},{"name":"sw-stan-architektura"},{"name":"sw-czeka-na-limit"}]'
  run "$ROOT/bin/sw-stan" architektura implementacja
  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = "WYNIK: STAN implementacja" ]
  [ "$(labels)" = '["sw-czeka-na-limit","sw-pomysl","sw-stan-implementacja"]' ]
}

@test "S7 a repeated transition is skipped, a paused or closed project too" {
  idea '[{"name":"sw-pomysl"},{"name":"sw-stan-integracja"}]'
  run "$ROOT/bin/sw-stan" architektura implementacja
  [ "$status" -eq 0 ]
  [[ "${lines[-1]}" == "WYNIK: POMINIETO"* ]]
  [ "$(labels)" = '["sw-pomysl","sw-stan-integracja"]' ]
  idea '[{"name":"sw-pomysl"},{"name":"sw-stan-wstrzymany"}]' closed
  run "$ROOT/bin/sw-stan" integracja przeglad
  [[ "${lines[-1]}" == "WYNIK: POMINIETO"* ]]
  [ "$(labels)" = '["sw-pomysl","sw-stan-wstrzymany"]' ]
}

@test "S7 rejects a transition that is not one step forward and a README without the idea link" {
  idea '[{"name":"sw-pomysl"},{"name":"sw-stan-architektura"}]'
  run "$ROOT/bin/sw-stan" architektura przeglad
  [ "$status" -eq 1 ]
  run "$ROOT/bin/sw-stan" przeglad architektura
  [ "$status" -eq 1 ]
  echo "# bez linku" > README.md
  run "$ROOT/bin/sw-stan" architektura implementacja
  [ "$status" -eq 1 ]
  [[ "$output" == *"STAN: BLAD"* ]]
  [ "$(labels)" = '["sw-pomysl","sw-stan-architektura"]' ]
}
