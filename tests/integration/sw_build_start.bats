#!/usr/bin/env bats
# Integration: bin/sw-build-start (the stage switch after the merged specification)
# against the mock Cezar/GitHub API over real HTTP.

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
  stage() { jq --argjson s "$1" '.stage = $s' "$ROOT/config/sw.json" > "$WORK/sw.json"; export SW_CONFIG="$WORK/sw.json"; }
}

teardown() {
  kill "$MOCK_PID" 2>/dev/null || true
  rm -rf "$WORK"
}

control() { curl -fsS -X POST -d "$1" "$SW_CEZAR_URL/__control" >/dev/null; }
state() { curl -fsS -X POST -d '{}' "$SW_CEZAR_URL/__control"; }
idea() {
  jq -nc --argjson n "$1" --argjson l "${2:-[\"sw-pomysl\",\"sw-stan-specyfikacja\"]}" '
    {number: $n, state: "open", title: "Planer", labels: ($l | map({name: .})),
     body: "## Problem i dla kogo\nx\n\n<!-- sw:meta {\"repo\":\"cieyhomelab/app\",\"projectId\":\"proj-app\"} -->"}'
}
journal='{"number": 1, "state": "open", "title": "sw-dziennik", "labels": [{"name": "sw-dziennik"}]}'
merged='"pulls": {"cieyhomelab/app#3": {"head_sha": "abc", "branch": "spec", "merged": true}}'

@test "S5 stage 2: starts the sw-build task and moves the idea to sw-stan-architektura (open)" {
  stage 2
  control "{\"issues\": [$journal, $(idea 2)], $merged}"
  run "$ROOT/bin/sw-build-start" 2
  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = "WYNIK: BUDOWA run-1" ]
  s="$(state)"
  [ "$(jq -r '.runs[0].project' <<<"$s")" = proj-app ]
  [ "$(jq -r '.runs[0].workflow' <<<"$s")" = sw-build ]
  [ "$(jq -r '.runs[0].autonomous' <<<"$s")" = true ]
  [ "$(jq -r '.runs[0].task' <<<"$s")" = "Budowa aplikacji: cieyhomelab/sw-control#2" ]
  issue="$(jq -c '.issues[] | select(.number == 2)' <<<"$s")"
  [ "$(jq -c '[.labels[].name]' <<<"$issue")" = '["sw-pomysl","sw-stan-architektura"]' ]
  [ "$(jq -r .state <<<"$issue")" = open ]
  meta="$(jq -r .body <<<"$issue" | sed -n 's/.*<!-- sw:meta \(.*\) -->/\1/p')"
  [ "$(jq -r .buildRunId <<<"$meta")" = run-1 ]
  [ "$(jq -r .repo <<<"$meta")" = cieyhomelab/app ]
}

@test "S5 stage 2 never starts the sh-* chain" {
  stage 2
  control "{\"issues\": [$journal, $(idea 2)], $merged}"
  run "$ROOT/bin/sw-build-start" 2
  [ "$status" -eq 0 ]
  [[ "$(state | jq -r '.runs[].task')" != *"sh-start"* ]]
  [[ "$(state | jq -c '.issues[] | select(.number == 2) | [.labels[].name]')" != *"sw-spec-gotowa"* ]]
}

@test "stage 1 (the default) keeps the handover to the sh-* chain" {
  stage 1
  control "{\"issues\": [$journal, $(idea 2)], $merged}"
  run "$ROOT/bin/sw-build-start" 2
  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = "WYNIK: PRZEKAZANY run-1" ]
  [[ "$(state | jq -r '.runs[0].task')" == *"sh-start"* ]]
  [ "$(state | jq -r '.runs[0].workflow')" = "" ]
}

@test "a missing stage field means stage 1" {
  jq 'del(.stage)' "$ROOT/config/sw.json" > "$WORK/sw.json"; export SW_CONFIG="$WORK/sw.json"
  control "{\"issues\": [$journal, $(idea 2)], $merged}"
  run "$ROOT/bin/sw-build-start" 2
  [ "${lines[-1]}" = "WYNIK: PRZEKAZANY run-1" ]
}

@test "stage 2: an unmerged specification is skipped and nothing changes" {
  stage 2
  control "{\"issues\": [$journal, $(idea 2)], \"pulls\": {\"cieyhomelab/app#3\": {\"head_sha\": \"abc\", \"branch\": \"spec\"}}}"
  run "$ROOT/bin/sw-build-start" 2
  [ "$status" -eq 0 ]
  [[ "${lines[-1]}" == "WYNIK: POMINIETO "* ]]
  [ "$(state | jq '.runs | length')" = 0 ]
  [ "$(state | jq -c '.issues[] | select(.number == 2) | [.labels[].name]')" = '["sw-pomysl","sw-stan-specyfikacja"]' ]
}

@test "stage 2: a repeated run after the label moved is skipped, no second task" {
  stage 2
  control "{\"issues\": [$journal, $(idea 2)], $merged}"
  "$ROOT/bin/sw-build-start" 2
  run "$ROOT/bin/sw-build-start" 2
  [ "$status" -eq 0 ]
  [[ "${lines[-1]}" == "WYNIK: POMINIETO "* ]]
  [ "$(state | jq '.runs | length')" = 1 ]
}

@test "stage 2: a live sw-build task left by an interrupted run is reused" {
  stage 2
  control "{\"issues\": [$journal, $(idea 2)], $merged, \"runs\": [{\"project\": \"proj-app\", \"id\": \"live\", \"workflow\": \"sw-build\", \"task\": \"Budowa aplikacji: cieyhomelab/sw-control#2\", \"status\": \"running\"}]}"
  run "$ROOT/bin/sw-build-start" 2
  [ "${lines[-1]}" = "WYNIK: BUDOWA live" ]
  [ "$(state | jq '.runs | length')" = 1 ]
}

@test "stage 2: without a number the idea comes from the README link" {
  stage 2
  control "{\"issues\": [$journal, $(idea 2)], $merged}"
  cd "$WORK"
  printf '# x\nhttps://github.com/cieyhomelab/sw-control/issues/2\n' > README.md
  run "$ROOT/bin/sw-build-start"
  [ "${lines[-1]}" = "WYNIK: BUDOWA run-1" ]
}
