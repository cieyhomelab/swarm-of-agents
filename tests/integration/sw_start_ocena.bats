#!/usr/bin/env bats
# Integration: bin/sw-start-ocena against the mock Cezar/GitHub API over real HTTP.

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
}

teardown() {
  kill "$MOCK_PID" 2>/dev/null || true
  rm -rf "$WORK"
}

control() { curl -fsS -X POST -d "$1" "$SW_CEZAR_URL/__control" >/dev/null; }
state() { curl -fsS -X POST -d '{}' "$SW_CEZAR_URL/__control"; }

# card <nr> <labels-json> [meta-json] — an idea card issue.
card() {
  jq -nc --argjson n "$1" --argjson l "$2" --arg m "${3:-{\}}" '
    {number: $n, state: "open", title: "Planer posiłków", labels: ($l | map({name: .})),
     body: ("## Problem i dla kogo\nx\n\n## Rekomendacja\nrekomenduję: ok\n\n<!-- sw:meta " + $m + " -->")}'
}

@test "a card in review gets a non-autonomous sw-ocena task and its id in the metadata" {
  control "{\"issues\": [$(card 3 '["sw-pomysl","sw-w-ocenie"]')]}"
  run "$ROOT/bin/sw-start-ocena" 3
  [ "$status" -eq 0 ]
  [ "$output" = "WYNIK: ZADANIE run-1" ]
  s="$(state)"
  [ "$(jq -c '.runs[0] | {workflow, autonomous, project}' <<<"$s")" = '{"workflow":"sw-ocena","autonomous":false,"project":"proj-sw-control"}' ]
  [[ "$(jq -r '.runs[0].task' <<<"$s")" == *"cieyhomelab/sw-control#3"* ]]
  body="$(jq -r '.issues[0].body' <<<"$s")"
  [[ "$body" == *'<!-- sw:meta {"evalRunId":"run-1"} -->' ]]
  [[ "$body" == "## Problem i dla kogo"* ]]
  [ "$(jq -c '[.issues[0].labels[].name]' <<<"$s")" = '["sw-pomysl","sw-w-ocenie"]' ]
}

@test "without a number the only idea under evaluation is taken" {
  control "{\"issues\": [$(card 1 '["sw-dziennik"]'), $(card 4 '["sw-pomysl","sw-w-ocenie"]')]}"
  run "$ROOT/bin/sw-start-ocena"
  [ "$status" -eq 0 ]
  [ "$output" = "WYNIK: ZADANIE run-1" ]
  [[ "$(state | jq -r '.issues[1].body')" == *'"evalRunId":"run-1"'* ]]
}

@test "other metadata survives and a lost task id is replaced" {
  control "{\"issues\": [$(card 3 '["sw-pomysl","sw-w-ocenie"]' '{"evalRunId":"old","pauseReason":"x"}')]}"
  run "$ROOT/bin/sw-start-ocena" 3
  [ "$status" -eq 0 ]
  body="$(state | jq -r '.issues[0].body')"
  [ "$(printf '%s' "$body" | sed -n 's/.*<!-- sw:meta \(.*\) -->/\1/p' | jq -cS .)" = '{"evalRunId":"run-1","pauseReason":"x"}' ]
}

@test "an issue that is not under evaluation gets no task" {
  control "{\"issues\": [$(card 3 '["sw-pomysl","sw-zatwierdzony"]')]}"
  run "$ROOT/bin/sw-start-ocena" 3
  [ "$status" -eq 0 ]
  [[ "$output" == "WYNIK: POMINIETO"* ]]
  [ "$(state | jq '.runs | length')" -eq 0 ]
}

@test "no idea under evaluation gives no task" {
  control "{\"issues\": [$(card 1 '["sw-dziennik"]')]}"
  run "$ROOT/bin/sw-start-ocena"
  [ "$status" -eq 0 ]
  [[ "$output" == "WYNIK: POMINIETO"* ]]
  [ "$(state | jq '.runs | length')" -eq 0 ]
}

@test "a missing Cezar project is a STAN: BLAD with exit 1 and no task" {
  control "{\"hide_project\": true, \"issues\": [$(card 3 '["sw-pomysl","sw-w-ocenie"]')]}"
  run "$ROOT/bin/sw-start-ocena" 3
  [ "$status" -eq 1 ]
  [[ "$output" == "STAN: BLAD "* ]]
  [ "$(state | jq '.runs | length')" -eq 0 ]
}
