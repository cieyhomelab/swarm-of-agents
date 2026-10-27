#!/usr/bin/env bats
# E2E: the evaluation of an idea (S2, S3). The owner evaluates a card on GitHub by
# its label; the sweep only notifies and later reacts to the label. The optional
# sw-ocena workflow (a conversation, not started by the sweep) is walked by tests/tools/run_workflow.py with a mock agent, exactly as
# the workflows call the gate and the scripts on the VPS, against mocked APIs.

setup() {
  : "${MOCK_URL:?run through scripts/test-e2e.sh}"
  curl -fsS -X POST -d '{"reset": true}' "$MOCK_URL/__control" >/dev/null
  export SW_PUSH_URL="$MOCK_URL"
  home="${SW_HOME:-/work}"
  WORK="$(mktemp -d)"
  cd "$WORK" || return 1
  SW_PUSH_TOKEN_FILE="$WORK/token"; echo test-token > "$SW_PUSH_TOKEN_FILE"; export SW_PUSH_TOKEN_FILE
  export MOCK_AGENT="$WORK/agent"
  export PLAN="$WORK/plan"
  cat > "$MOCK_AGENT" <<'AGENT'
#!/usr/bin/env bash
# Mock agents. generator: always a complete card. analyst: the owner decided as
# $DECISION says, so it writes the matching comment (only a comment, like the
# real skill) and ends.
set -euo pipefail
case "$1" in
  generator)
    jq -n '{tytul: "Planer posiłków", problem: "Trudno zaplanować zakupy na tydzień", dla_kogo: "rodziny z dziećmi",
        co_robi: "Układa menu i listę zakupów.",
        sprawdzenie: {podsumowanie: "Problem potwierdzony.", zrodla: ["https://example.org/a"]},
        oceny: {wplyw: 4, wykonalnosc: 5, ryzyko: 2}, rekomendacja: "rekomenduję", uzasadnienie: "Proste."}' \
      > .ai/sw-run/proba.json
    echo karta ;;
  analyst)
    marker="sw:ustalenia"; [ "${DECISION:-Zatwierdź}" = "Zatwierdź" ] || marker="sw:odrzucenie"
    jq -n --arg b "<!-- $marker -->
Wymagania bez danych osobowych." '{body: $b}' \
      | gh api -X POST "repos/cieyhomelab/sw-control/issues/${IDEA:-2}/comments" --input - >/dev/null
    echo done ;;
esac
AGENT
  chmod +x "$MOCK_AGENT"
}

teardown() { cd / && rm -rf "$WORK"; }

state() { curl -fsS -X POST -d '{}' "$MOCK_URL/__control"; }
control() { curl -fsS -X POST "$MOCK_URL/__control" -d "$1" >/dev/null; }
sweep() { run python3 "$home/tests/tools/run_workflow.py" "$home/workflows/sw-sweep.yml"; }
base_issues() { echo '{"number": 1, "state": "open", "title": "sw-dziennik", "labels": [{"name": "sw-dziennik"}]}'; }
evals() { state | jq -c '[.runs[] | select(.workflow == "sw-ocena")]'; }
idea() { # idea <nr> <meta-json>
  jq -nc --argjson n "$1" --arg m "$2" '{number: $n, state: "open", title: "Planer posiłków",
    labels: [{name: "sw-pomysl"}, {name: "sw-w-ocenie"}],
    body: ("## Problem i dla kogo\nx\n\n<!-- sw:meta " + $m + " -->")}'
}

pushes() { curl -fsS "$MOCK_URL/__requests" | jq -c '[.[] | select(.method == "POST" and .path == "/m/push/gate")]'; }
label() { # label <nr> <label>... — the owner relabels the idea on GitHub
  local n="$1"; shift
  control "$(state | jq -c --argjson n "$n" --args '{issues: [.issues[] | if .number == $n
    then .labels = ([.labels[].name | select(. != "sw-w-ocenie")] + $ARGS.positional | map({name: .})) else . end]}' "$@")"
}

@test "S1 S2 a new card waits on GitHub and the owner gets a push linking the issue, no task is started" {
  control "{\"issues\": [$(base_issues)]}"
  sweep
  [ "$status" -eq 0 ]
  [[ "$output" == *"TRACE idea-notify pass"* ]]
  [[ "$output" == *"END done success"* ]]
  [ "$(evals)" = "[]" ]
  card="$(state | jq -c '.issues[] | select(.labels | map(.name) | index("sw-w-ocenie"))')"
  [ "$(jq -r '.number' <<<"$card")" -eq 2 ]
  [ "$(pushes | jq length)" -eq 1 ]
  [ "$(pushes | jq -r '.[0].body.gate')" = spec ]
  [ "$(pushes | jq -r '.[0].body.url')" = "https://github.com/cieyhomelab/sw-control/issues/2" ]
  [[ "$(pushes | jq -r '.[0].body.title')" == "Nowy pomysł: "* ]]
}

@test "S1 a failed attempt sends no notification and starts no task" {
  control "{\"issues\": [$(base_issues)]}"
  cat > "$MOCK_AGENT" <<'AGENT'
#!/usr/bin/env bash
echo '{"przyczyna": "brak źródła"}' > .ai/sw-run/proba.json
echo nieudana
AGENT
  sweep
  [ "$status" -eq 0 ]
  [ "$(evals)" = "[]" ]
  [ "$(pushes)" = "[]" ]
}

@test "S2 an idea waiting for the owner's label gets no task and no new idea" {
  control "{\"issues\": [$(base_issues), $(idea 2 '{}')], \"runs\": []}"
  sweep
  [ "$status" -eq 0 ]
  [[ "$output" == *"TRACE is-spec false"* ]]
  [ "$(state | jq '.runs | length')" -eq 0 ]
  [ "$(state | jq '[.issues[] | select(.labels | map(.name) | index("sw-pomysl"))] | length')" -eq 1 ]
}

@test "S2 the owner's sw-zatwierdzony label starts the repository and the spec in the next cycle" {
  control "{\"issues\": [$(base_issues), $(idea 2 '{}')]}"
  label 2 sw-zatwierdzony
  sweep
  [ "$status" -eq 0 ]
  [[ "$output" == *"TRACE create-repo pass"* ]]
  [ "$(state | jq -c '[.issues[] | select(.number == 2) | .labels[].name]')" = '["sw-pomysl","sw-stan-specyfikacja"]' ]
  [ "$(state | jq '[.runs[] | select(.workflow == "sw-spec")] | length')" -eq 1 ]
}

@test "S3 the owner's sw-odrzucony label lets the next cycle generate a new idea" {
  control "{\"issues\": [$(base_issues), $(idea 2 '{}')]}"
  label 2 sw-odrzucony
  sweep
  [ "$status" -eq 0 ]
  [[ "$output" == *"TRACE is-generator true"* ]]
  [[ "$output" == *"TRACE attempts repeat"* ]]
  [ "$(state | jq -c '[.issues[] | select(.number == 2) | .labels[].name] | sort')" = '["sw-odrzucony","sw-pomysl"]' ]
}

evaluate() { # evaluate <history-json> — the sw-ocena workflow for idea 2 with that task history
  control "{\"issues\": [$(base_issues), $(idea 2 '{"evalRunId":"r1"}')], \"histories\": {\"r1\": $1}}"
  IDEA=2 run python3 "$home/tests/tools/run_workflow.py" "$home/workflows/sw-ocena.yml"
}
idea_state() { state | jq -c '.issues[] | select(.number == 2)'; }
approved='[{"role": "assistant", "text": "Karta"}, {"role": "user", "text": "Decyzja: Zatwierdź"}]'
rejected='[{"role": "assistant", "text": "Karta"}, {"role": "user", "text": "Decyzja: Odrzuć"}]'

@test "S2 Decyzja: Zatwierdź sets sw-zatwierdzony and approvedAt; the summary stays the input for the spec" {
  DECISION="Zatwierdź" evaluate "$approved"
  [ "$status" -eq 0 ]
  [[ "$output" == *"TRACE analyst done"* ]]
  [[ "$output" == *"TRACE result pass"* ]]
  [[ "$output" == *"END done success"* ]]
  issue="$(idea_state)"
  [ "$(jq -c '[.labels[].name]' <<<"$issue")" = '["sw-pomysl","sw-zatwierdzony"]' ]
  [ "$(jq -r .state <<<"$issue")" = "open" ]
  meta="$(jq -r .body <<<"$issue" | sed -n 's/.*<!-- sw:meta \(.*\) -->/\1/p')"
  [ "$(jq -r .evalRunId <<<"$meta")" = "r1" ]
  [ -n "$(jq -r '.approvedAt // empty' <<<"$meta")" ]
  [ "$(state | jq -r '.comments["2"][0].body' | head -1)" = "<!-- sw:ustalenia -->" ]
}

@test "S3 Decyzja: Odrzuć closes the idea and the next cycle returns GENERATOR without the owner" {
  DECISION="Odrzuć" evaluate "$rejected"
  [ "$status" -eq 0 ]
  [[ "$output" == *"TRACE result pass"* ]]
  issue="$(idea_state)"
  [ "$(jq -c '[.labels[].name]' <<<"$issue")" = '["sw-odrzucony","sw-pomysl"]' ]
  [ "$(jq -r .state <<<"$issue")" = "closed" ]
  [ "$(state | jq -r '.comments["2"][0].body' | head -1)" = "<!-- sw:odrzucenie -->" ]
  run bash "$home/bin/sw-gate"
  [ "$status" -eq 0 ]
  [[ "$output" == *"URUCHOM: GENERATOR"* ]]
  [ "$(jq -r '.odrzucone[0].tytul' .ai/sw-run/generator.json)" = "Planer posiłków" ]
}

@test "S3 a later card never repeats the title of a rejected idea" {
  DECISION="Odrzuć" evaluate "$rejected"
  sweep
  [ "$status" -eq 0 ]
  [[ "$output" == *"TRACE gate pass"* ]]
  [[ "$output" != *"TRACE start-ocena"* ]]
  [ "$(state | jq '[.issues[] | select(.labels | map(.name) | index("sw-w-ocenie"))] | length')" -eq 0 ]
  [ "$(evals)" = "[]" ]
}

@test "S2 the same text from the assistant changes nothing" {
  DECISION="Zatwierdź" evaluate '[{"role": "assistant", "text": "Decyzja: Zatwierdź"}]'
  [ "$status" -eq 0 ]
  [ "$(idea_state | jq -c '[.labels[].name]')" = '["sw-pomysl","sw-w-ocenie"]' ]
  [ "$(idea_state | jq -r .state)" = "open" ]
}

@test "S2 no decision keeps sw-w-ocenie and leaves a journal entry; the script prints BRAK_DECYZJI" {
  DECISION="Zatwierdź" evaluate '[{"role": "user", "text": "Jeszcze się zastanawiam"}]'
  [ "$status" -eq 0 ]
  [ "$(idea_state | jq -c '[.labels[].name]')" = '["sw-pomysl","sw-w-ocenie"]' ]
  [[ "$(state | jq -r '.comments["1"][]?.body')" == *"ocena pomysłu #2: brak decyzji"* ]]
  run bash "$home/bin/sw-ocena-wynik"
  [ "$output" = "WYNIK: BRAK_DECYZJI" ]
}

@test "S2 a decision without the agent comment keeps sw-w-ocenie" {
  control "{\"issues\": [$(base_issues), $(idea 2 '{"evalRunId":"r1"}')], \"histories\": {\"r1\": $approved}}"
  run bash "$home/bin/sw-ocena-wynik"
  [ "$output" = "WYNIK: BRAK_DECYZJI" ]
  [ "$(idea_state | jq -c '[.labels[].name]')" = '["sw-pomysl","sw-w-ocenie"]' ]
}

@test "S2 a failed agent turn still ends the evaluation task with success" {
  cat > "$MOCK_AGENT" <<'AGENT'
#!/usr/bin/env bash
exit 1
AGENT
  run python3 "$home/tests/tools/run_workflow.py" "$home/workflows/sw-ocena.yml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"TRACE analyst failed"* ]]
  [[ "$output" == *"END degraded success"* ]]
}
