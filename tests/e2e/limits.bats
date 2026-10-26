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
  SW_RUN_DIR="$(mktemp -d)"; export SW_RUN_DIR SW_STATE_DIR="$SW_RUN_DIR/state"
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

runs() {
  curl -fsS -X POST "$MOCK_URL/__control" -d "$(jq -nc --argjson r "$1" '{runs: ($r | map(. + {project: "proj-app"}))}')" >/dev/null
}
app_runs() { state | jq -c '[.runs[] | select(.project == "proj-app")]'; }

@test "S12 plan limit: 'sw-czeka-na-limit', no retry used, resumed without the owner after the renewal" {
  project 2026-10-19T12:00:00Z '[]'
  runs '[{"id":"a","status":"waiting","autoResumeAt":"2026-10-20T15:00:00Z","task":"t"},{"id":"b","status":"failed","task":"u"}]'
  run "$bin/sw-gate"
  [[ "$output" == *"URUCHOM: NIC"* ]]
  [[ "$(idea | jq -c '[.labels[].name]')" == *sw-czeka-na-limit* ]]
  [ "$(app_runs | jq length)" -eq 2 ]
  runs '[{"id":"a","status":"running","updatedAt":"2026-10-20T11:50:00Z","task":"t"}]'
  "$bin/sw-gate" >/dev/null
  [[ "$(idea | jq -c '[.labels[].name]')" != *sw-czeka-na-limit* ]]
  [ "$(idea | jq -r .state)" = open ]
}

@test "S12 12 automatic resumes used up: a new task from the interrupted step" {
  project 2026-10-19T12:00:00Z '[]'
  runs '[{"id":"a","status":"failed","autoResumes":12,"step":"testy","task":"Zrob X"}]'
  "$bin/sw-gate" >/dev/null
  [ "$(app_runs | jq length)" -eq 2 ]
  [[ "$(app_runs | jq -r '.[1].task')" == *"[wznowienie 0; od a]"*"testy" ]]
}

@test "S11 three hours without a commit or a state change: retried; retries used up: paused with a notification" {
  project 2026-10-19T12:00:00Z '[]'
  runs '[{"id":"a","status":"running","updatedAt":"2026-10-20T08:00:00Z","task":"Zrob X"}]'
  "$bin/sw-gate" >/dev/null
  [[ "$(app_runs | jq -r '.[1].task')" == *"[ponowienie 1; zastępuje a]" ]]
  [ "$(app_runs | jq -r '.[0].status')" = cancelled ]
  runs '[{"id":"c","status":"failed","step":"testy","task":"Zrob X\n\n[ponowienie 2; zastępuje b]"}]'
  run "$bin/sw-gate"
  [[ "$output" == *"URUCHOM: GENERATOR"* ]]
  [ "$(idea | jq -c '[.labels[].name]')" = '["sw-pomysl","sw-stan-wstrzymany"]' ]
  [[ "$(pushes | jq -r '.[0].body.title')" == *"ostatni stan: failed, krok te"* ]]
}

@test "S12 a variable billed outside the plan: no task starts and the journal has an entry without the value" {
  project 2026-10-19T12:00:00Z '[]'
  runs '[{"id":"a","status":"failed","task":"Zrob X"}]'
  run env ANTHROPIC_API_KEY=sk-x "$bin/sw-limits" 5
  [ "$status" -eq 0 ]
  [[ "$output" == "WYNIK: ZABLOKOWANY"*ANTHROPIC_API_KEY* ]]
  [ "$(app_runs | jq length)" -eq 1 ]
  [[ "$(state | jq -r '.comments["1"][0].body')" == *"zadanie nie wystartowało"*ANTHROPIC_API_KEY* ]]
  [[ "$(state | jq -r '.comments["1"][0].body')" != *sk-x* ]]
}
