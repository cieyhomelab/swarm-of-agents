#!/usr/bin/env bats
# Integration: bin/sw-handover-sh against the mock Cezar/GitHub API over real HTTP.

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

# idea <nr> [labels-json] [meta-json] — a project card waiting for the handover.
idea() {
  jq -nc --argjson n "$1" --argjson l "${2:-[\"sw-pomysl\",\"sw-stan-specyfikacja\"]}" \
    --arg m "${3:-{\"repo\":\"cieyhomelab/app\",\"projectId\":\"proj-app\"\}}" '
    {number: $n, state: "open", title: "Planer", labels: ($l | map({name: .})),
     body: ("## Problem i dla kogo\nx\n\n<!-- sw:meta " + $m + " -->")}'
}
journal='{"number": 1, "state": "open", "title": "sw-dziennik", "labels": [{"name": "sw-dziennik"}]}'
merged='"pulls": {"cieyhomelab/app#3": {"head_sha": "abc", "branch": "spec", "merged": true}}'

@test "starts the sh-start task in the application project and closes the idea with sw-spec-gotowa" {
  control "{\"issues\": [$journal, $(idea 2)], $merged}"
  run "$ROOT/bin/sw-handover-sh" 2
  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = "WYNIK: PRZEKAZANY run-1" ]
  s="$(state)"
  [ "$(jq -r '.runs[0].project' <<<"$s")" = proj-app ]
  [ "$(jq -r '.runs[0].autonomous' <<<"$s")" = true ]
  [[ "$(jq -r '.runs[0].task' <<<"$s")" == *"sh-start"* ]]
  issue="$(jq -c '.issues[] | select(.number == 2)' <<<"$s")"
  [ "$(jq -c '[.labels[].name]' <<<"$issue")" = '["sw-pomysl","sw-spec-gotowa","sw-stan-specyfikacja"]' ]
  [ "$(jq -r .state <<<"$issue")" = closed ]
  meta="$(jq -r .body <<<"$issue" | sed -n 's/.*<!-- sw:meta \(.*\) -->/\1/p')"
  [ "$(jq -r .handoverRunId <<<"$meta")" = run-1 ]
  [ "$(jq -r .repo <<<"$meta")" = cieyhomelab/app ]
  [[ "$(jq -r '.comments["1"][0].body' <<<"$s")" == *"przekazanie"* ]]
}

@test "without a number the idea comes from the README link" {
  control "{\"issues\": [$journal, $(idea 2)], $merged}"
  cd "$WORK"
  printf '# x\nhttps://github.com/cieyhomelab/sw-control/issues/2\n' > README.md
  run "$ROOT/bin/sw-handover-sh"
  [ "${lines[-1]}" = "WYNIK: PRZEKAZANY run-1" ]
}

@test "an unmerged specification is skipped and nothing changes" {
  control "{\"issues\": [$journal, $(idea 2)], \"pulls\": {\"cieyhomelab/app#3\": {\"head_sha\": \"abc\", \"branch\": \"spec\"}}}"
  run "$ROOT/bin/sw-handover-sh" 2
  [ "$status" -eq 0 ]
  [[ "${lines[-1]}" == "WYNIK: POMINIETO "* ]]
  [ "$(state | jq '.runs | length')" = 0 ]
  [ "$(state | jq -r '.issues[1].state')" = open ]
}

@test "a repeated run does nothing once the idea is handed over" {
  control "{\"issues\": [$journal, $(idea 2 '["sw-pomysl","sw-stan-specyfikacja","sw-spec-gotowa"]')], $merged}"
  run "$ROOT/bin/sw-handover-sh" 2
  [[ "${lines[-1]}" == "WYNIK: POMINIETO "* ]]
  [ "$(state | jq '.runs | length')" = 0 ]
}

@test "a live sh-start task left by an interrupted run is reused" {
  control "{\"issues\": [$journal, $(idea 2)], $merged, \"runs\": [{\"project\": \"proj-app\", \"id\": \"old\", \"status\": \"running\",
    \"task\": \"Wczytaj skill sh-start i skonfiguruj repozytorium cieyhomelab/app.\"}]}"
  run "$ROOT/bin/sw-handover-sh" 2
  [ "${lines[-1]}" = "WYNIK: PRZEKAZANY old" ]
  [ "$(state | jq '.runs | length')" = 1 ]
}

@test "an idea without repo and projectId in the meta is skipped" {
  control "{\"issues\": [$journal, $(idea 2 '["sw-pomysl","sw-stan-specyfikacja"]' '{}')], $merged}"
  run "$ROOT/bin/sw-handover-sh" 2
  [[ "${lines[-1]}" == "WYNIK: POMINIETO "* ]]
}

@test "a Cezar failure is STAN: BLAD and leaves the idea open" {
  control "{\"issues\": [$journal, $(idea 2)], $merged, \"runs\": \"broken\"}"
  run "$ROOT/bin/sw-handover-sh" 2
  [ "$status" -eq 1 ]
  [[ "$output" == *"STAN: BLAD"* ]]
  [ "$(state | jq -r '.issues[1].state')" = open ]
}
