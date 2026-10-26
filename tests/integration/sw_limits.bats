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

# runs <json> — the tasks of the Cezar project "proj-app".
runs() {
  curl -fsS -X POST "$MOCK/__control" -d "$(jq -nc --argjson r "$1" '{runs: ($r | map(. + {project: "proj-app"}))}')" >/dev/null
}
labels() { state | jq -c '[.issues[] | select(.number == 5) | .labels[].name]'; }
app_runs() { state | jq -c '[.runs[] | select(.project == "proj-app")]'; }
journal_text() { state | jq -r '[.comments["1"][]?.body] | join("\n")'; }

@test "S12 plan limit: label, retries unchanged, no new task; the label goes when the limit renews" {
  project 2026-10-19T12:00:00Z sw-stan-implementacja
  runs '[{"id":"a","status":"waiting","autoResumeAt":"2026-10-20T15:00:00Z","updatedAt":"2026-10-20T08:00:00Z","task":"t\n\n[ponowienie 1; zastępuje z]"},
         {"id":"b","status":"failed","task":"u"}]'
  run "$ROOT/bin/sw-limits" 5
  [ "$output" = "WYNIK: CZEKA-NA-LIMIT" ]
  [[ "$(labels)" == *sw-czeka-na-limit* ]]
  [ "$(app_runs | jq length)" -eq 2 ]
  run "$ROOT/bin/sw-limits" 5
  [ "$output" = "WYNIK: CZEKA-NA-LIMIT" ]
  [ "$(labels | jq '[.[] | select(. == "sw-czeka-na-limit")] | length')" -eq 1 ]
  runs '[{"id":"a","status":"running","updatedAt":"2026-10-20T11:30:00Z","task":"t\n\n[ponowienie 1; zastępuje z]"}]'
  run "$ROOT/bin/sw-limits" 5
  [ "$output" = "WYNIK: OK" ]
  [[ "$(labels)" != *sw-czeka-na-limit* ]]
  [ "$(app_runs | jq length)" -eq 1 ]
}

@test "S12 12 exhausted automatic resumes: a new task from the interrupted step, once, retries not used" {
  project 2026-10-19T12:00:00Z sw-stan-implementacja
  runs '[{"id":"a","status":"failed","autoResumes":12,"step":"testy","workflow":"sw-build","task":"Zrob X\n\n[ponowienie 1; zastępuje z]"}]'
  run "$ROOT/bin/sw-limits" 5
  [ "$output" = "WYNIK: OK" ]
  [ "$(app_runs | jq length)" -eq 2 ]
  [[ "$(app_runs | jq -r '.[1].task')" == *"[wznowienie 1; od a]"*"testy" ]]
  [ "$(app_runs | jq -r '.[1].workflow')" = sw-build ]
  [[ "$(journal_text)" == *"wznowienie: pomysł #5"* ]]
  run "$ROOT/bin/sw-limits" 5
  [ "$(app_runs | jq length)" -eq 2 ]
}

@test "S11 a task without a commit and a state change for 3 hours is retried without the owner" {
  project 2026-10-19T12:00:00Z sw-stan-implementacja
  runs '[{"id":"a","status":"running","updatedAt":"2026-10-20T08:30:00Z","branch":"feat/x","task":"Zrob X"}]'
  curl -fsS -X POST "$MOCK/__control" -d '{"commits": {"cieyhomelab/app@feat/x": "2026-10-20T08:45:00Z"}}' >/dev/null
  run "$ROOT/bin/sw-limits" 5
  [ "$output" = "WYNIK: OK" ]
  [[ "$(app_runs | jq -r '.[1].task')" == *"[ponowienie 1; zastępuje a]" ]]
  [[ "$(journal_text)" == *"ponowienie: pomysł #5"*"brak commitu"* ]]
}

@test "S11 a commit within 3 hours is progress: nothing is retried" {
  project 2026-10-19T12:00:00Z sw-stan-implementacja
  runs '[{"id":"a","status":"running","updatedAt":"2026-10-20T01:00:00Z","branch":"feat/x","task":"Zrob X"}]'
  curl -fsS -X POST "$MOCK/__control" -d '{"commits": {"cieyhomelab/app@feat/x": "2026-10-20T10:00:00Z"}}' >/dev/null
  run "$ROOT/bin/sw-limits" 5
  [ "$output" = "WYNIK: OK" ]
  [ "$(app_runs | jq length)" -eq 1 ]
}

@test "S11 retries used up: the project is paused with the cause and the last state in the notification" {
  project 2026-10-19T12:00:00Z sw-stan-implementacja
  runs '[{"id":"c","status":"failed","step":"testy","task":"Zrob X\n\n[ponowienie 2; zastępuje b]"}]'
  run "$ROOT/bin/sw-limits" 5
  [[ "$output" == "WYNIK: WSTRZYMANY wyczerpane ponowienia (2/2)"* ]]
  paused
  [ "$(pushes | jq length)" -eq 1 ]
  [[ "$(pushes | jq -r '.[0].body.title')" == *"ostatni stan: failed, krok testy"* ]]
}

@test "S12 a variable billed outside the plan: no task starts, the journal has an entry" {
  project 2026-10-19T12:00:00Z sw-stan-implementacja
  runs '[{"id":"a","status":"failed","task":"Zrob X"}]'
  run env ANTHROPIC_API_KEY=sk-x "$ROOT/bin/sw-limits" 5
  [ "$status" -eq 0 ]
  [[ "$output" == "WYNIK: ZABLOKOWANY"*ANTHROPIC_API_KEY* ]]
  [ "$(app_runs | jq length)" -eq 1 ]
  [[ "$(journal_text)" == *"zadanie nie wystartowało"*ANTHROPIC_API_KEY* ]]
  [[ "$(journal_text)" != *sk-x* ]]
}
