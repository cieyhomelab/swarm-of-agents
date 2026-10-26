#!/usr/bin/env bats
# Integration: bin/sw-limits and bin/sw-pause against the mock Cezar, GitHub and cezar-push APIs.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  WORK="$(mktemp -d)"
  python3 "$ROOT/tests/tools/mock_api.py" --port 0 --port-file "$WORK/port" &
  MOCK_PID=$!
  for _ in $(seq 1 50); do [ -s "$WORK/port" ] && break; sleep 0.1; done
  PORT="$(cat "$WORK/port")"
  MOCK="http://127.0.0.1:$PORT"
  export FAKE_GH_API_URL="$MOCK" SW_PUSH_URL="$MOCK" SW_CEZAR_URL="$MOCK"
  export SW_PUSH_TOKEN_FILE="$WORK/token"; echo test-token > "$SW_PUSH_TOKEN_FILE"
  export PATH="$ROOT/tests/fakes:$PATH"
  export SW_NOW=2026-10-20T12:00:00Z
}

teardown() { kill "$MOCK_PID" 2>/dev/null || true; rm -rf "$WORK"; }

state() { curl -fsS -X POST -d '{}' "$MOCK/__control"; }
pushes() { curl -fsS "$MOCK/__requests" | jq -c '[.[] | select(.path == "/m/push/gate")]'; }

# project <approvedAt> [label] [costs-json] — one approved project with tasks costing <costs>.
project() {
  local meta
  meta="$(jq -nc --arg a "$1" '{approvedAt: $a, repo: "cieyhomelab/app", projectId: "proj-app"}')"
  curl -fsS -X POST "$MOCK/__control" -d "$(jq -nc --arg meta "$meta" --arg l "${2:-sw-stan-specyfikacja}" --argjson c "${3:-[]}" '
    {issues: [{number: 1, state: "open", title: "sw-dziennik", labels: [{name: "sw-dziennik"}]},
              {number: 5, state: "open", title: "Planer", labels: [{name: "sw-pomysl"}, {name: $l}],
               body: ("karta\n\n<!-- sw:meta " + $meta + " -->")}],
     runs: [$c[] | {project: "proj-app", id: ("r" + (. | tostring)), costUsd: .}]}')" >/dev/null
}

paused() {
  [ "$(state | jq -r '.issues[] | select(.number == 5) | .state')" = closed ] \
    && [ "$(state | jq -c '[.issues[] | select(.number == 5) | .labels[].name]')" = '["sw-pomysl","sw-stan-wstrzymany"]' ]
}

@test "approved 7 x 24 h ago: paused with the reason 'limit czasu', one notification, journal entry" {
  project 2026-10-13T12:00:00Z
  run "$ROOT/bin/sw-limits" 5
  [ "$status" -eq 0 ]
  [[ "$output" == "WYNIK: WSTRZYMANY limit czasu"* ]]
  paused
  [[ "$(state | jq -r '.issues[] | select(.number == 5) | .body')" == *'"pauseReason":"limit czasu'* ]]
  [ "$(pushes | jq length)" -eq 1 ]
  [[ "$(pushes | jq -r '.[0].body.title')" == "Projekt wstrzymany: limit czasu"* ]]
  [[ "$(state | jq -r '.comments["1"][0].body')" == "wstrzymanie: pomysł #5: limit czasu"* ]]
}

@test "approved 6 days and 23 hours ago: not paused" {
  project 2026-10-13T13:00:00Z
  run "$ROOT/bin/sw-limits" 5
  [ "$status" -eq 0 ]
  [ "$output" = "WYNIK: OK" ]
  [ "$(state | jq -r '.issues[] | select(.number == 5) | .state')" = open ]
  [ "$(pushes | jq length)" -eq 0 ]
}

@test "usage above projectUsageLimitUsd: paused with the reason 'limit zużycia'" {
  project 2026-10-19T12:00:00Z sw-stan-implementacja '[60, 60.5, 30]'
  run "$ROOT/bin/sw-limits" 5
  [ "$status" -eq 0 ]
  [[ "$output" == "WYNIK: WSTRZYMANY limit zużycia"* ]]
  paused
  [[ "$(pushes | jq -r '.[0].body.title')" == "Projekt wstrzymany: limit zużycia"* ]]
}

@test "usage at the limit is not paused; tasks of other projects are not counted" {
  project 2026-10-19T12:00:00Z sw-stan-implementacja '[75, 75]'
  curl -fsS -X POST "$MOCK/__control" -d "$(state | jq -c '{runs: (.runs + [{project: "other", id: "x", costUsd: 500}])}')" >/dev/null
  run "$ROOT/bin/sw-limits" 5
  [ "$output" = "WYNIK: OK" ]
}

@test "an idea that is not an active project is skipped" {
  project 2026-10-01T00:00:00Z sw-stan-wdrozony
  run "$ROOT/bin/sw-limits" 5
  [ "$status" -eq 0 ]
  [[ "$output" == "WYNIK: POMINIETO"* ]]
  [ "$(pushes | jq length)" -eq 0 ]
}

@test "an unreadable task list is an error and nothing is paused" {
  project 2026-10-01T00:00:00Z
  run env SW_CEZAR_URL=http://127.0.0.1:1 "$ROOT/bin/sw-limits" 5
  [ "$status" -eq 1 ]
  [[ "$output" == "STAN: BLAD"* ]]
  [ "$(state | jq -r '.issues[] | select(.number == 5) | .state')" = open ]
}

@test "sw-pause drops the 'sw-czeka-na-limit' label and does not pause twice" {
  project 2026-10-19T12:00:00Z sw-stan-implementacja
  curl -fsS -X POST "$MOCK/__control" -d "$(state | jq -c '.issues[1].labels += [{name: "sw-czeka-na-limit"}] | {issues}')" >/dev/null
  run "$ROOT/bin/sw-pause" 5 "reczne wstrzymanie"
  [ "$output" = "WYNIK: WSTRZYMANY" ]
  paused
  run "$ROOT/bin/sw-pause" 5 "jeszcze raz"
  [[ "$output" == "WYNIK: POMINIETO"* ]]
  [ "$(pushes | jq length)" -eq 1 ]
}

@test "the gate pauses a project over its limit and starts the generator in the same cycle" {
  project 2026-10-13T12:00:00Z
  curl -fsS -X POST "$MOCK/__control" -d '{"projects": [{"id": "proj-sw-control", "name": "sw-control"}]}' >/dev/null
  cd "$WORK"
  run "$ROOT/bin/sw-gate"
  [[ "$output" == *"URUCHOM: GENERATOR"* ]]
  paused
}

@test "the gate leaves a project within its limits alone" {
  project 2026-10-19T12:00:00Z
  cd "$WORK"
  run "$ROOT/bin/sw-gate"
  [[ "$output" == *"URUCHOM: NIC"* ]]
  [ "$(state | jq -r '.issues[] | select(.number == 5) | .state')" = open ]
}
