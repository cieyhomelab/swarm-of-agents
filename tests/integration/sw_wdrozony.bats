#!/usr/bin/env bats
# Integration: bin/sw-wdrozony (S10) — the state "wdrozony", the closing of the idea and the
# notification with the address — against the mock GitHub and cezar-push APIs.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  WORK="$(mktemp -d)"
  python3 "$ROOT/tests/tools/mock_api.py" --port 0 --port-file "$WORK/port" &
  MOCK_PID=$!
  for _ in $(seq 1 50); do [ -s "$WORK/port" ] && break; sleep 0.1; done
  PORT="$(cat "$WORK/port")"
  export SW_CEZAR_URL="http://127.0.0.1:$PORT" FAKE_GH_API_URL="http://127.0.0.1:$PORT" SW_PUSH_URL="http://127.0.0.1:$PORT"
  export SW_PUSH_TOKEN_FILE="$WORK/token"; echo test-token > "$SW_PUSH_TOKEN_FILE"
  export PATH="$ROOT/tests/fakes:$PATH"
  cd "$WORK" || return 1
  mkdir -p .ai/sw-run
  printf '# Planer\n\nPomysł i jego ocena: https://github.com/cieyhomelab/sw-control/issues/7\n' > README.md
  echo '{"url":"http://127.0.0.1:18100","nazwa":"planer"}' > .ai/sw-run/wdrozenie.json
}

teardown() {
  kill "$MOCK_PID" 2>/dev/null || true
  rm -rf "$WORK"
}

control() { curl -fsS -X POST -d "$1" "$SW_CEZAR_URL/__control" >/dev/null; }
state() { curl -fsS -X POST -d '{}' "$SW_CEZAR_URL/__control"; }
idea() { state | jq -c '.issues[] | select(.number == 7)'; }
pushes() { curl -fsS "$SW_CEZAR_URL/__requests" | jq -c '[.[] | select(.method == "POST" and .path == "/m/push/gate")]'; }
project() {
  control "{\"issues\": [{\"number\": 1, \"state\": \"open\", \"title\": \"sw-dziennik\", \"labels\": [{\"name\": \"sw-dziennik\"}]},
    {\"number\": 7, \"state\": \"${2:-open}\", \"title\": \"Planer\", \"labels\": $1,
     \"body\": \"## Problem i dla kogo\\nx\\n\\n<!-- sw:meta {\\\"repo\\\":\\\"cieyhomelab/app\\\"} -->\"}]}"
}

@test "S10 the project becomes wdrozony, the idea is closed and the owner is notified with the title and the address" {
  project '[{"name":"sw-pomysl"},{"name":"sw-stan-wdrazanie"}]'
  run "$ROOT/bin/sw-wdrozony"
  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = "WYNIK: WDROZONY http://127.0.0.1:18100" ]
  [ "$(idea | jq -c '[.labels[].name]')" = '["sw-bez-interwencji","sw-pomysl","sw-stan-wdrozony"]' ]
  [ "$(idea | jq -r .state)" = closed ]
  # the address is kept in the metadata, the other fields stay
  meta="$(idea | jq -r .body | grep -o '<!-- sw:meta .* -->' | sed -E 's/<!-- sw:meta (.*) -->/\1/')"
  [ "$(jq -r .deployUrl <<<"$meta")" = http://127.0.0.1:18100 ]
  [ "$(jq -r .repo <<<"$meta")" = cieyhomelab/app ]
  # one notification: the address and the name in the title, a GitHub link as the url
  [ "$(pushes | jq length)" -eq 1 ]
  req="$(pushes | jq -c '.[0].body')"
  [[ "$(jq -r .title <<<"$req")" == "Wdrożono: http://127.0.0.1:18100 (planer) · 100% bez interwencji" ]]
  [ "$(jq -r .url <<<"$req")" = https://github.com/cieyhomelab/sw-control/issues/7 ]
}

@test "S10 a repeated run changes nothing and does not notify twice" {
  project '[{"name":"sw-pomysl"},{"name":"sw-stan-wdrazanie"}]'
  run "$ROOT/bin/sw-wdrozony"; [ "$status" -eq 0 ]
  run "$ROOT/bin/sw-wdrozony"
  [ "$status" -eq 0 ]
  [[ "${lines[-1]}" == "WYNIK: POMINIETO"* ]]
  [ "$(pushes | jq length)" -eq 1 ]
}

@test "S10 a project in another state or a paused one is not marked as deployed" {
  project '[{"name":"sw-pomysl"},{"name":"sw-stan-przeglad"}]'
  run "$ROOT/bin/sw-wdrozony"
  [[ "${lines[-1]}" == "WYNIK: POMINIETO"* ]]
  project '[{"name":"sw-pomysl"},{"name":"sw-stan-wstrzymany"}]' closed
  run "$ROOT/bin/sw-wdrozony"
  [[ "${lines[-1]}" == "WYNIK: POMINIETO"* ]]
  [ "$(idea | jq -c '[.labels[].name]')" = '["sw-pomysl","sw-stan-wstrzymany"]' ]
  [ "$(pushes | jq length)" -eq 0 ]
}

@test "S10 a missing result of sw-deploy or a README without the idea link is an error" {
  project '[{"name":"sw-pomysl"},{"name":"sw-stan-wdrazanie"}]'
  rm .ai/sw-run/wdrozenie.json
  run "$ROOT/bin/sw-wdrozony"
  [ "$status" -eq 1 ]; [[ "$output" == *"STAN: BLAD"* ]]
  echo '{"url":"http://127.0.0.1:18100"}' > .ai/sw-run/wdrozenie.json
  echo "# bez linku" > README.md
  run "$ROOT/bin/sw-wdrozony"
  [ "$status" -eq 1 ]; [[ "$output" == *"STAN: BLAD"* ]]
  [ "$(idea | jq -c '[.labels[].name]')" = '["sw-pomysl","sw-stan-wdrazanie"]' ]
}

@test "S10 a refused notification does not undo the state" {
  project '[{"name":"sw-pomysl"},{"name":"sw-stan-wdrazanie"}]'
  control '{"push_token": "other"}'
  run "$ROOT/bin/sw-wdrozony"
  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = "WYNIK: WDROZONY http://127.0.0.1:18100" ]
  [ "$(idea | jq -c '[.labels[].name]')" = '["sw-bez-interwencji","sw-pomysl","sw-stan-wdrozony"]' ]
}
