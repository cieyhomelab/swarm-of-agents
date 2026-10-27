#!/usr/bin/env bats
# Integration: bin/sw-spec-stop against the mock Cezar, GitHub and cezar-push APIs.
# A stopped sw-spec task is retried up to retriesPerTask times, then the project is paused.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  WORK="$(mktemp -d)"
  python3 "$ROOT/tests/tools/mock_api.py" --port 0 --port-file "$WORK/port" &
  MOCK_PID=$!
  for _ in $(seq 1 50); do [ -s "$WORK/port" ] && break; sleep 0.1; done
  PORT="$(cat "$WORK/port")"
  MOCK="http://127.0.0.1:$PORT"
  export SW_CEZAR_URL="$MOCK" FAKE_GH_API_URL="$MOCK" SW_PUSH_URL="$MOCK"
  export SW_PUSH_TOKEN_FILE="$WORK/token"; echo test-token > "$SW_PUSH_TOKEN_FILE"
  export PATH="$ROOT/tests/fakes:$PATH"
  export CEZ_PROJECT_ID=proj-app CEZ_RUN_ID=run-me
  cd "$WORK" || return 1
  printf 'x\nhttps://github.com/cieyhomelab/sw-control/issues/5\n' > README.md
}

teardown() { cd / && kill "$MOCK_PID" 2>/dev/null || true; rm -rf "$WORK"; }

state() { curl -fsS -X POST -d '{}' "$MOCK/__control"; }
task='Specyfikacja aplikacji: cieyhomelab/sw-control#5'
run_rec() { # run_rec <id> <status>
  jq -nc --arg id "$1" --arg st "$2" --arg t "$task" '{id: $id, project: "proj-app", workflow: "sw-spec", task: $t, status: $st, autonomous: true,
    steps: [{id: "sec-ustalenia", status: "done"}, {id: "analyst", status: "failed"}, {id: "commit", status: "pending"}]}'
}
seed() { # seed <earlier-run-json>...
  local runs; runs="$(jq -sc '.' <<<"$(run_rec run-me running; for r in "$@"; do echo "$r"; done)")"
  curl -fsS -X POST "$MOCK/__control" -d "$(jq -nc --argjson r "$runs" '{runs: $r, issues: [
    {number: 1, state: "open", title: "sw-dziennik", labels: [{name: "sw-dziennik"}]},
    {number: 5, state: "open", title: "Planer", labels: [{name: "sw-pomysl"}, {name: "sw-stan-specyfikacja"}],
     body: "karta\n\n<!-- sw:meta {\"repo\":\"cieyhomelab/app\"} -->"}]}')" >/dev/null
}

@test "the first stop starts a new sw-spec task and writes the journal" {
  seed
  run "$ROOT/bin/sw-spec-stop"
  [ "$status" -eq 0 ]
  [[ "$output" == "WYNIK: PONOWIENIE run-"* ]]
  [ "$(state | jq --arg t "$task" '[.runs[] | select(.workflow == "sw-spec" and .task == $t and .autonomous == true)] | length')" -eq 2 ]
  [[ "$(state | jq -r '.comments["1"][0].body')" == "ponowienie: sw-spec w projekcie proj-app (1/2), zatrzymane na kroku analyst (failed)"* ]]
  [ "$(state | jq -c '[.issues[] | select(.number == 5) | .labels[].name]')" = '["sw-pomysl","sw-stan-specyfikacja"]' ]
}

@test "after retriesPerTask earlier tasks the project is paused with the step and one notification" {
  seed "$(run_rec run-a done)" "$(run_rec run-b done)"
  run "$ROOT/bin/sw-spec-stop"
  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = "WYNIK: WSTRZYMANY" ]
  issue="$(state | jq -c '.issues[] | select(.number == 5)')"
  [ "$(jq -r .state <<<"$issue")" = closed ]
  [[ "$(jq -c '[.labels[].name]' <<<"$issue")" == *"sw-stan-wstrzymany"* ]]
  [[ "$(jq -r .body <<<"$issue")" == *"specyfikacja zatrzymana na kroku analyst (failed) po 3 probach"* ]]
  [ "$(curl -fsS "$MOCK/__requests" | jq '[.[] | select(.path == "/m/push/gate")] | length')" -eq 1 ]
}

@test "another live sw-spec task means nothing is started" {
  seed "$(run_rec run-a running)"
  run "$ROOT/bin/sw-spec-stop"
  [ "$status" -eq 0 ]
  [ "$output" = "WYNIK: POMINIETO trwa inne zadanie sw-spec" ]
  [ "$(state | jq '.runs | length')" -eq 2 ]
}

@test "without the Cezar context the script fails instead of guessing" {
  seed
  CEZ_RUN_ID="" run "$ROOT/bin/sw-spec-stop"
  [ "$status" -eq 1 ]
  [[ "$output" == "STAN: BLAD brak CEZ_PROJECT_ID albo CEZ_RUN_ID" ]]
}
