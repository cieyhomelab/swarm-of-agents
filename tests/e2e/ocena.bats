#!/usr/bin/env bats
# E2E: the evaluation of an idea (S2, S3). The sw-sweep branches that start the
# sw-ocena task (after a new card; for a lost task) and the sw-ocena workflow
# itself are walked by tests/tools/run_workflow.py with a mock agent, exactly as
# the workflows call the gate and the scripts on the VPS, against mocked APIs.

setup() {
  : "${MOCK_URL:?run through scripts/test-e2e.sh}"
  curl -fsS -X POST -d '{"reset": true}' "$MOCK_URL/__control" >/dev/null
  export SW_PUSH_URL="$MOCK_URL"
  home="${SW_HOME:-/work}"
  WORK="$(mktemp -d)"
  cd "$WORK" || return 1
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
  jq -nc --argjson n "$1" --arg m "$2" '{number: $n, state: "open", title: "Planer",
    labels: [{name: "sw-pomysl"}, {name: "sw-w-ocenie"}],
    body: ("## Problem i dla kogo\nx\n\n<!-- sw:meta " + $m + " -->")}'
}

@test "S2 a new card starts a non-autonomous sw-ocena task and stores its id in the metadata" {
  control "{\"issues\": [$(base_issues)]}"
  sweep
  [ "$status" -eq 0 ]
  [[ "$output" == *"TRACE start-ocena pass"* ]]
  [[ "$output" == *"END done success"* ]]
  [ "$(evals | jq length)" -eq 1 ]
  [ "$(evals | jq -c '.[0] | {autonomous, project}')" = '{"autonomous":false,"project":"proj-sw-control"}' ]
  card="$(state | jq -c '.issues[] | select(.labels | map(.name) | index("sw-w-ocenie"))')"
  [ "$(jq -r '.number' <<<"$card")" -eq 2 ]
  [[ "$(jq -r '.body' <<<"$card")" == *"<!-- sw:meta {\"evalRunId\":\"$(evals | jq -r '.[0].id')\"} -->" ]]
  [[ "$(evals | jq -r '.[0].task')" == *"#2"* ]]
}

@test "S2 a failed attempt starts no evaluation task" {
  control "{\"issues\": [$(base_issues)]}"
  cat > "$MOCK_AGENT" <<'AGENT'
#!/usr/bin/env bash
echo '{"przyczyna": "brak źródła"}' > .ai/sw-run/proba.json
echo nieudana
AGENT
  sweep
  [ "$status" -eq 0 ]
  [ "$(evals)" = "[]" ]
}

@test "S2 an evaluation that is still running gets no second task" {
  control "{\"issues\": [$(base_issues), $(idea 2 '{"evalRunId":"r1"}')],
            \"runs\": [{\"id\": \"r1\", \"workflow\": \"sw-ocena\", \"status\": \"waiting\"}]}"
  sweep
  [ "$status" -eq 0 ]
  [[ "$output" != *"TRACE start-ocena"* ]]
  [ "$(state | jq '.runs | length')" -eq 1 ]
}

@test "S2 URUCHOM: OCENA for a lost task creates a new evaluation task for that issue" {
  control "{\"issues\": [$(base_issues), $(idea 2 '{"evalRunId":"gone"}')], \"runs\": []}"
  sweep
  [ "$status" -eq 0 ]
  [[ "$output" == *"TRACE is-ocena true"* ]]
  [[ "$output" == *"TRACE start-ocena pass"* ]]
  [ "$(evals | jq length)" -eq 1 ]
  [[ "$(evals | jq -r '.[0].task')" == *"#2"* ]]
  body="$(state | jq -r '.issues[] | select(.number == 2) | .body')"
  [[ "$body" == *"<!-- sw:meta {\"evalRunId\":\"$(evals | jq -r '.[0].id')\"} -->" ]]
  # the next cycle sees a live task and leaves it alone
  sweep
  [ "$(evals | jq length)" -eq 1 ]
}

@test "S2 an agent that writes sw:ustalenia leaves the labels and the metadata alone" {
  control "{\"issues\": [$(base_issues), $(idea 2 '{"evalRunId":"r1"}')]}"
  DECISION="Zatwierdź" IDEA=2 run python3 "$home/tests/tools/run_workflow.py" "$home/workflows/sw-ocena.yml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"TRACE analyst done"* ]]
  [[ "$output" == *"END done success"* ]]
  s="$(state)"
  [ "$(jq -r '.comments["2"][0].body' <<<"$s" | head -1)" = "<!-- sw:ustalenia -->" ]
  issue="$(jq -c '.issues[] | select(.number == 2)' <<<"$s")"
  [ "$(jq -c '[.labels[].name]' <<<"$issue")" = '["sw-pomysl","sw-w-ocenie"]' ]
  [[ "$(jq -r .body <<<"$issue")" == *'<!-- sw:meta {"evalRunId":"r1"} -->' ]]
}

@test "S2 a rejection leaves a sw:odrzucenie comment and the same labels" {
  control "{\"issues\": [$(base_issues), $(idea 2 '{"evalRunId":"r1"}')]}"
  DECISION="Odrzuć" IDEA=2 run python3 "$home/tests/tools/run_workflow.py" "$home/workflows/sw-ocena.yml"
  [ "$status" -eq 0 ]
  s="$(state)"
  [ "$(jq -r '.comments["2"][0].body' <<<"$s" | head -1)" = "<!-- sw:odrzucenie -->" ]
  [ "$(jq -c '[.issues[] | select(.number == 2) | .labels[].name]' <<<"$s")" = '["sw-pomysl","sw-w-ocenie"]' ]
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
