#!/usr/bin/env bats
# E2E (S12, time and usage limits): sw-gate runs sw-limits before it decides; a project over
# its limit is paused (sw-pause) with a notification and a journal entry, and the generator
# starts in the same cycle. Exactly as on the VPS, against mocked Cezar, GitHub and cezar-push.

setup() {
  : "${MOCK_URL:?run through scripts/test-e2e.sh}"
  curl -fsS -X POST -d '{"reset": true}' "$MOCK_URL/__control" >/dev/null
  export SW_PUSH_URL="$MOCK_URL" SW_NOW=2026-10-20T12:00:00Z
  SW_PUSH_TOKEN_FILE="$(mktemp)"; export SW_PUSH_TOKEN_FILE
  printf 'test-token\n' > "$SW_PUSH_TOKEN_FILE"
  SW_RUN_DIR="$(mktemp -d)"; export SW_RUN_DIR
  bin="${SW_HOME:-/work}/bin"
}

teardown() { rm -rf "$SW_PUSH_TOKEN_FILE" "$SW_RUN_DIR"; }

state() { curl -fsS -X POST -d '{}' "$MOCK_URL/__control"; }
pushes() { curl -fsS "$MOCK_URL/__requests" | jq -c '[.[] | select(.method == "POST" and .path == "/m/push/gate")]'; }
idea() { state | jq -c '.issues[] | select(.number == 5)'; }

# project <approvedAt> <costs-json> — an approved project in implementation with tasks of those costs.
project() {
  local meta
  meta="$(jq -nc --arg a "$1" '{approvedAt: $a, repo: "cieyhomelab/app", projectId: "proj-app"}')"
  curl -fsS -X POST "$MOCK_URL/__control" -d "$(jq -nc --arg meta "$meta" --argjson c "$2" '
    {issues: [{number: 1, state: "open", title: "sw-dziennik", labels: [{name: "sw-dziennik"}]},
              {number: 5, state: "open", title: "Planer", labels: [{name: "sw-pomysl"}, {name: "sw-stan-implementacja"}],
               body: ("karta\n\n<!-- sw:meta " + $meta + " -->")}],
     runs: [$c[] | {project: "proj-app", id: ("r" + (. | tostring)), costUsd: .}]}')" >/dev/null
}

@test "S12 approved 7 x 24 h ago: paused with the reason 'limit czasu', the next decision is GENERATOR" {
  project 2026-10-13T12:00:00Z '[]'
  run "$bin/sw-gate"
  [ "$status" -eq 0 ]
  [[ "$output" == *"URUCHOM: GENERATOR"* ]]
  [ "$(idea | jq -r .state)" = closed ]
  [ "$(idea | jq -c '[.labels[].name]')" = '["sw-pomysl","sw-stan-wstrzymany"]' ]
  [ "$(pushes | jq length)" -eq 1 ]
  [[ "$(pushes | jq -r '.[0].body.title')" == "Projekt wstrzymany: limit czasu"* ]]
  [[ "$(idea | jq -r .body)" == *'"pauseReason":"limit czasu'* ]]
  [[ "$(state | jq -r '.comments["1"][0].body')" == "wstrzymanie: pomysł #5: limit czasu"* ]]
  run "$bin/sw-gate"
  [[ "$output" == *"URUCHOM: GENERATOR"* ]]
  [ "$(pushes | jq length)" -eq 1 ]
}

@test "S12 approved 6 days and 23 hours ago: not paused for time" {
  project 2026-10-13T13:00:00Z '[]'
  run "$bin/sw-gate"
  [[ "$output" == *"URUCHOM: NIC"* ]]
  [ "$(idea | jq -r .state)" = open ]
  [ "$(pushes | jq length)" -eq 0 ]
}

@test "S12 usage above projectUsageLimitUsd: paused with the reason 'limit zużycia'" {
  project 2026-10-19T12:00:00Z '[80, 71.25]'
  run "$bin/sw-gate"
  [[ "$output" == *"URUCHOM: GENERATOR"* ]]
  [ "$(idea | jq -c '[.labels[].name]')" = '["sw-pomysl","sw-stan-wstrzymany"]' ]
  [[ "$(pushes | jq -r '.[0].body.title')" == "Projekt wstrzymany: limit zużycia"* ]]
}

@test "S12 a paused project gets no questions: one notification, no second pause" {
  project 2026-10-13T12:00:00Z '[]'
  "$bin/sw-gate" >/dev/null
  run "$bin/sw-limits" 5
  [[ "$output" == "WYNIK: POMINIETO"* ]]
  [ "$(pushes | jq length)" -eq 1 ]
}
