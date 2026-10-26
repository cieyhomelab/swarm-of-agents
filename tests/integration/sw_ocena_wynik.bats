#!/usr/bin/env bats
# Integration: bin/sw-ocena-wynik against the mock Cezar/GitHub API over real HTTP.

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
journal() { state | jq -c '[.comments["1"][]?.body]'; }

journal_issue() { echo '{"number": 1, "state": "open", "title": "sw-dziennik", "labels": [{"name": "sw-dziennik"}]}'; }
# card <nr> [meta-json] — an idea under evaluation with extra labels kept.
card() {
  jq -nc --argjson n "$1" --arg m "${2:-{\"evalRunId\":\"r1\"\}}" '
    {number: $n, state: "open", title: "Planer posiłków", labels: [{name: "sw-pomysl"}, {name: "sw-w-ocenie"}, {name: "extra"}],
     body: ("## Problem i dla kogo\nx\n\n<!-- sw:meta " + $m + " -->")}'
}
# setup_idea <history-json> [comment-body] — the idea 2, its task history and the agent comment.
setup_idea() {
  local comments='{}'
  [ -z "${2:-}" ] || comments="$(jq -nc --arg b "$2" '{"2": [{body: $b, created_at: "2026-10-26T10:00:00Z"}]}')"
  control "{\"issues\": [$(journal_issue), $(card 2)], \"histories\": {\"r1\": $1}, \"comments\": $comments}"
}
user() { jq -nc --arg t "$1" '{role: "user", text: $t}'; }
assistant() { jq -nc --arg t "$1" '{role: "assistant", text: $t}'; }
labels() { state | jq -c '[.issues[] | select(.number == 2) | .labels[].name] | sort'; }

@test "Decyzja: Zatwierdź sets sw-zatwierdzony and approvedAt and keeps the rest" {
  setup_idea "[$(assistant 'Karta?'), $(user 'Decyzja: Zatwierdź')]" $'<!-- sw:ustalenia -->\nWymagania.'
  run "$ROOT/bin/sw-ocena-wynik" 2
  [ "$status" -eq 0 ]
  [ "$output" = "WYNIK: ZATWIERDZONY" ]
  [ "$(labels)" = '["extra","sw-pomysl","sw-zatwierdzony"]' ]
  issue="$(state | jq -c '.issues[] | select(.number == 2)')"
  [ "$(jq -r .state <<<"$issue")" = "open" ]
  meta="$(jq -r .body <<<"$issue" | sed -n 's/.*<!-- sw:meta \(.*\) -->/\1/p')"
  [ "$(jq -r .evalRunId <<<"$meta")" = "r1" ]
  [[ "$(jq -r .approvedAt <<<"$meta")" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$ ]]
  [[ "$(jq -r .body <<<"$issue")" == "## Problem i dla kogo"* ]]
}

@test "Decyzja: Odrzuć sets sw-odrzucony and closes the issue without approvedAt" {
  setup_idea "[$(user 'Decyzja: Odrzuć')]" $'<!-- sw:odrzucenie -->\nZa podobne.'
  run "$ROOT/bin/sw-ocena-wynik" 2
  [ "$status" -eq 0 ]
  [ "$output" = "WYNIK: ODRZUCONY" ]
  [ "$(labels)" = '["extra","sw-odrzucony","sw-pomysl"]' ]
  [ "$(state | jq -r '.issues[] | select(.number == 2) | .state')" = "closed" ]
  [[ "$(state | jq -r '.issues[] | select(.number == 2) | .body')" != *approvedAt* ]]
}

@test "without a number the only idea under evaluation is taken" {
  setup_idea "[$(user 'Decyzja: Zatwierdź')]" $'<!-- sw:ustalenia -->\nx'
  run "$ROOT/bin/sw-ocena-wynik"
  [ "$output" = "WYNIK: ZATWIERDZONY" ]
}

@test "the last decision of the user wins" {
  setup_idea "[$(user 'Decyzja: Odrzuć'), $(user 'Decyzja: Zatwierdź')]" $'<!-- sw:ustalenia -->\nx'
  run "$ROOT/bin/sw-ocena-wynik" 2
  [ "$output" = "WYNIK: ZATWIERDZONY" ]
}

@test "the same text from the assistant changes nothing" {
  setup_idea "[$(assistant 'Decyzja: Zatwierdź')]" $'<!-- sw:ustalenia -->\nx'
  control '{"comments": {"1": [], "2": [{"body": "<!-- sw:ustalenia -->\nx", "created_at": "2026-10-26T10:00:00Z"}]}}'
  run "$ROOT/bin/sw-ocena-wynik" 2
  [ "$status" -eq 0 ]
  [ "$output" = "WYNIK: BRAK_DECYZJI" ]
  [ "$(labels)" = '["extra","sw-pomysl","sw-w-ocenie"]' ]
}

@test "a sentence about approval or a decision with extra text is not a decision" {
  setup_idea "[$(user 'Zatwierdzam ten pomysł'), $(user 'Decyzja: Zatwierdź, ale później')]" $'<!-- sw:ustalenia -->\nx'
  run "$ROOT/bin/sw-ocena-wynik" 2
  [ "$output" = "WYNIK: BRAK_DECYZJI" ]
  [ "$(labels)" = '["extra","sw-pomysl","sw-w-ocenie"]' ]
}

@test "no decision leaves sw-w-ocenie and writes a journal entry" {
  setup_idea "[$(user 'Mam pytanie')]"
  run "$ROOT/bin/sw-ocena-wynik" 2
  [ "$status" -eq 0 ]
  [ "$output" = "WYNIK: BRAK_DECYZJI" ]
  [ "$(labels)" = '["extra","sw-pomysl","sw-w-ocenie"]' ]
  [[ "$(journal)" == *"ocena pomysłu #2: brak decyzji"* ]]
}

@test "a decision without the matching agent comment is not applied" {
  setup_idea "[$(user 'Decyzja: Zatwierdź')]" $'<!-- sw:odrzucenie -->\nx'
  run "$ROOT/bin/sw-ocena-wynik" 2
  [ "$output" = "WYNIK: BRAK_DECYZJI" ]
  [ "$(labels)" = '["extra","sw-pomysl","sw-w-ocenie"]' ]
  [[ "$(journal)" == *"brak komentarza agenta"* ]]
}

@test "a lost task history or missing evalRunId means no decision" {
  control "{\"issues\": [$(journal_issue), $(card 2)]}"
  run "$ROOT/bin/sw-ocena-wynik" 2
  [ "$output" = "WYNIK: BRAK_DECYZJI" ]
  control "{\"issues\": [$(journal_issue), $(card 2 '{}')]}"
  run "$ROOT/bin/sw-ocena-wynik" 2
  [ "$output" = "WYNIK: BRAK_DECYZJI" ]
}

@test "an issue that is not under evaluation is skipped and stays untouched" {
  control "{\"issues\": [$(journal_issue)]}"
  run "$ROOT/bin/sw-ocena-wynik"
  [ "$status" -eq 0 ]
  [[ "$output" == "WYNIK: POMINIETO"* ]]
  setup_idea "[$(user 'Decyzja: Zatwierdź')]" $'<!-- sw:ustalenia -->\nx'
  "$ROOT/bin/sw-ocena-wynik" 2
  run "$ROOT/bin/sw-ocena-wynik" 2
  [[ "$output" == "WYNIK: POMINIETO"* ]]
}

@test "an unreachable Cezar is an error, not a decision" {
  setup_idea "[$(user 'Decyzja: Zatwierdź')]" $'<!-- sw:ustalenia -->\nx'
  SW_CEZAR_URL="http://127.0.0.1:1" CEZ_PROJECT_ID=proj-sw-control run "$ROOT/bin/sw-ocena-wynik" 2
  [ "$status" -eq 1 ]
  [[ "$output" == "STAN: BLAD"* ]]
  [ "$(labels)" = '["extra","sw-pomysl","sw-w-ocenie"]' ]
}
