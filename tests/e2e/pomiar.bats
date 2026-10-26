#!/usr/bin/env bats
# E2E (S13, measuring effectiveness; one active project to the end): the share of projects
# finished "bez interwencji" in the deployment and pause notifications, the label
# sw-bez-interwencji and the active-project rule of sw-gate. Exactly as on the VPS, against the
# mocked GitHub, Cezar and cezar-push. The whole build flow (one notification between the
# approval and the deployment) is in build.bats.

setup() {
  : "${MOCK_URL:?run through scripts/test-e2e.sh}"
  curl -fsS -X POST -d '{"reset": true}' "$MOCK_URL/__control" >/dev/null
  export SW_PUSH_URL="$MOCK_URL" FAKE_GH_API_URL="$MOCK_URL" CEZ_PROJECT_ID=proj
  WORK="$(mktemp -d)"; cd "$WORK" || return 1
  SW_PUSH_TOKEN_FILE="$WORK/token"; echo test-token > "$SW_PUSH_TOKEN_FILE"; export SW_PUSH_TOKEN_FILE
  export SW_RUN_DIR="$WORK/run" SW_STATE_DIR="$WORK/state"
  mkdir -p .ai/sw-run
  printf '# Planer\n\nPomysł i jego ocena: https://github.com/cieyhomelab/sw-control/issues/7\n' > README.md
  echo '{"url":"http://127.0.0.1:18100","nazwa":"planer"}' > .ai/sw-run/wdrozenie.json
  PATH="${SW_HOME:-/work}/tests/fakes:$PATH"
  bin="${SW_HOME:-/work}/bin"
}

teardown() { rm -rf "$WORK"; }

state() { curl -fsS -X POST -d '{}' "$MOCK_URL/__control"; }
idea() { state | jq -c --argjson n "$1" '.issues[] | select(.number == $n)'; }
pushes() { curl -fsS "$MOCK_URL/__requests" | jq -c '[.[] | select(.method == "POST" and .path == "/m/push/gate")]'; }

# issues <json-array> — the journal plus the given idea issues.
issues() {
  curl -fsS -X POST "$MOCK_URL/__control" -d "$(jq -nc --argjson i "$1" \
    '{issues: ([{number: 1, state: "open", title: "sw-dziennik", labels: [{name: "sw-dziennik"}]}] + $i)}')" >/dev/null
}
# idea <number> <state> <label>... — one idea issue
card() {
  local n="$1" st="$2"; shift 2
  jq -nc --argjson n "$n" --arg st "$st" --args '{number: $n, state: $st, title: "Pomysl", body: "karta\n\n<!-- sw:meta {\"repo\":\"cieyhomelab/app\"} -->",
    labels: ([$ARGS.positional[], "sw-pomysl"] | map({name: .}))}' "$@"
}

@test "S13 3 finished projects, 2 of them deployed without a pause: the deployment notification shows 67%" {
  issues "[$(card 3 closed sw-stan-wdrozony sw-bez-interwencji), $(card 4 closed sw-stan-wstrzymany),
            $(card 7 open sw-stan-wdrazanie)]"
  run "$bin/sw-wdrozony"
  [ "$status" -eq 0 ]
  [ "$(pushes | jq length)" -eq 1 ]
  [[ "$(pushes | jq -r '.[0].body.title')" == "Wdrożono: http://127.0.0.1:18100 (planer) · 67% bez interwencji" ]]
}

@test "S13 3 finished projects, 2 deployed without a pause: the pause notification shows 67% too" {
  issues "[$(card 3 closed sw-stan-wdrozony sw-bez-interwencji), $(card 4 closed sw-stan-wdrozony sw-bez-interwencji),
            $(card 7 open sw-stan-implementacja)]"
  run "$bin/sw-pause" 7 "limit czasu"
  [ "$status" -eq 0 ]
  [ "$(pushes | jq length)" -eq 1 ]
  [ "$(pushes | jq -r '.[0].body.gate')" = blocked ]
  [[ "$(pushes | jq -r '.[0].body.title')" == "Projekt wstrzymany: limit czasu · 67% bez interwencji" ]]
}

@test "S13 a deployment without an earlier sw-stan-wstrzymany gets sw-bez-interwencji" {
  issues "[$(card 7 open sw-stan-wdrazanie)]"
  run "$bin/sw-wdrozony"
  [ "$status" -eq 0 ]
  [ "$(idea 7 | jq -c '[.labels[].name]')" = '["sw-bez-interwencji","sw-pomysl","sw-stan-wdrozony"]' ]
}

@test "S13 a paused project never gets sw-bez-interwencji" {
  issues "[$(card 7 open sw-stan-implementacja)]"
  run "$bin/sw-pause" 7 "limit zużycia"
  [ "$status" -eq 0 ]
  [ "$(idea 7 | jq -c '[.labels[].name]')" = '["sw-pomysl","sw-stan-wstrzymany"]' ]
}

@test "S13 a project in any state from specyfikacja to wdrazanie keeps the gate from returning GENERATOR" {
  for label in sw-stan-specyfikacja sw-stan-architektura sw-stan-implementacja \
               sw-stan-integracja sw-stan-przeglad sw-stan-wdrazanie; do
    issues "[$(card 7 open "$label")]"
    run "$bin/sw-gate"
    [[ "$output" == *"URUCHOM: NIC"* ]]
    [[ "$output" != *"URUCHOM: GENERATOR"* ]]
  done
}
