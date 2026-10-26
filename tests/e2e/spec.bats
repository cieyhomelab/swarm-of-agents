#!/usr/bin/env bats
# E2E (S4, steps 2-5): the sw-spec workflow of an application repository, walked by
# tests/tools/run_workflow.py with a mock agent, against the mocked Cezar, GitHub and
# cezar-push APIs. The scripts run exactly as on the VPS (bin/sw-spec-pr -> sw-pr-body,
# sw-merge, sw-notify). What the agents write is not tested here (AGENTS.md); the
# tests pin the wiring: the order of the nodes, the rounds, what reaches the scripts.

setup() {
  : "${MOCK_URL:?run through scripts/test-e2e.sh}"
  curl -fsS -X POST -d '{"reset": true}' "$MOCK_URL/__control" >/dev/null
  home="${SW_HOME:-/work}"
  WORK="$(mktemp -d)"
  cd "$WORK" || return 1
  mkdir -p .ai/specs .ai/sw-run
  export SW_PUSH_URL="$MOCK_URL"
  SW_PUSH_TOKEN_FILE="$WORK/token"; echo test-token > "$SW_PUSH_TOKEN_FILE"; export SW_PUSH_TOKEN_FILE
  export CEZ_PROJECT_ID=proj SW_SPEC_REPO=cieyhomelab/app SW_SPEC_BRANCH=spec
  export FAKE_GH_API_URL="$MOCK_URL" IDEA=7 CALLS="$WORK/calls" REVIEWS="$WORK/reviews"
  : > "$CALLS"
  printf '# Planer\n\nPomysł i jego ocena: https://github.com/cieyhomelab/sw-control/issues/7\n' > README.md
  curl -fsS -X POST "$MOCK_URL/__control" -d '{
    "issues": [{"number": 1, "state": "open", "title": "sw-dziennik", "labels": [{"name": "sw-dziennik"}]},
               {"number": 7, "state": "open", "title": "Planer posiłków", "labels": [{"name": "sw-pomysl"}, {"name": "sw-stan-specyfikacja"}],
                "body": "## Problem i dla kogo\nx\n\n<!-- sw:meta {\"repo\":\"cieyhomelab/app\",\"projectId\":\"proj\"} -->"}],
    "pulls": {"cieyhomelab/app#3": {"head_sha": "abc1234", "branch": "spec", "draft": true, "body": "Specyfikacja"}},
    "runs": [{"project": "proj", "id": "analyst", "modelIdentity": "anthropic/opus[1m]"},
             {"project": "proj", "id": "review", "modelIdentity": "anthropic/sonnet[1m]"},
             {"project": "proj", "id": "security", "modelIdentity": "anthropic/haiku[1m]"}],
    "comments": {"7": [{"body": "<!-- sw:ustalenia -->\nWymagania bez danych osobowych.", "created_at": "2026-10-26T00:00:00Z"}]}}' >/dev/null
  export MOCK_AGENT="$WORK/agent" PATH="$home/tests/fakes:$PATH"
  cat > "$MOCK_AGENT" <<'AGENT'
#!/usr/bin/env bash
# Mock agents of sw-spec. sec-ustalenia and security fail on an e-mail address (stand-in
# for personal data); review takes its verdicts one by one from $REVIEWS.
set -euo pipefail
echo "$1" >> "$CALLS"
spec=.ai/specs/2026-10-26-planer.md
case "$1" in
  sec-ustalenia)
    gh api "repos/cieyhomelab/sw-control/issues/$IDEA/comments" --jq '.[].body' | grep -q '@' && echo fail || echo pass ;;
  analyst)
    printf '# Planer\n\n## Zakres\n\n### S1: Menu\n- Zakładając tydzień, wtedy lista zakupów.\n\n## Założenia\n- Język polski.\n- Jedno gospodarstwo.\n\n## Inne\nx\n' > "$spec"
    echo gotowa ;;
  fix)
    echo "- Poprawka po uwagach." >> "$spec"
    echo gotowa ;;
  review)
    verdict="$(head -1 "$REVIEWS")"; sed -i 1d "$REVIEWS"
    [ "$verdict" = uwagi ] && echo "1. Kryterium S1 nie jest sprawdzalne." > .ai/sw-run/uwagi.md
    echo "$verdict" ;;
  security)
    if [ -n "${PUSH_AFTER_VERDICT:-}" ]; then
      curl -fsS -X POST "$MOCK_URL/__control" -d '{"pulls": {"cieyhomelab/app#3": {"head_sha": "def4567", "branch": "spec", "draft": true, "body": "x"}}}' >/dev/null
    fi
    grep -q '@' "$spec" && echo fail || echo pass ;;
esac
AGENT
  chmod +x "$MOCK_AGENT"
  export MOCK_GIT="$WORK/git"
  printf '#!/usr/bin/env bash\necho "$1" >> "$CALLS"\n' > "$MOCK_GIT"; chmod +x "$MOCK_GIT"
}

teardown() { cd / && rm -rf "$WORK"; }

state() { curl -fsS -X POST -d '{}' "$MOCK_URL/__control"; }
pr() { curl -fsS "$MOCK_URL/github/repos/cieyhomelab/app/pulls/3"; }
pushes() { curl -fsS "$MOCK_URL/__requests" | jq -c '[.[] | select(.method == "POST" and .path == "/m/push/gate")]'; }
spec() { run python3 "$home/tests/tools/run_workflow.py" "$home/workflows/sw-spec.yml"; }
reviews() { printf '%s\n' "$@" > "$REVIEWS"; }
called() { grep -c "^$1\$" "$CALLS" || true; }

@test "S4 an approved review and a passed security review merge the PR and notify the owner" {
  reviews zatwierdzona
  spec
  [ "$status" -eq 0 ]
  [[ "$output" == *"END done success"* ]]
  [ "$(pr | jq .merged)" = "true" ]
  # the draft PR was taken out of draft before the merge (GitHub refuses to merge a draft)
  [ "$(pr | jq .draft)" = "false" ]
  # the order of the work: commented requirements are checked before the analyst writes
  [ "$(sed -n 1,2p "$CALLS" | paste -sd,)" = "sec-ustalenia,analyst" ]
  [ "$(pushes | jq length)" -eq 1 ]
  [ "$(pushes | jq -c '.[0].body | {gate, repo, number, url}')" \
    = '{"gate":"spec","repo":"cieyhomelab/app","number":3,"url":"https://github.com/cieyhomelab/app/pull/3"}' ]
}

@test "S4 the PR description gets the review verdict and the assumptions of the specification" {
  reviews zatwierdzona
  spec
  [ "$status" -eq 0 ]
  body="$(pr | jq -r .body)"
  [[ "$body" == *"recenzent: zatwierdzona (zadanie review)"* ]]
  [[ "$body" == *"bezpieczenstwo: pass (zadanie security)"* ]]
  [[ "$body" == *"- Język polski."* ]]
  [[ "$body" == *"- Jedno gospodarstwo."* ]]
  [[ "$body" != *"## Inne"* ]]
}

@test "S4 remarks start a fix round of the analyst and a repeated review" {
  reviews uwagi zatwierdzona
  spec
  [ "$status" -eq 0 ]
  [[ "$output" == *"TRACE review uwagi"* ]]
  [[ "$output" == *"TRACE rounds repeat"* ]]
  [[ "$output" == *"END done success"* ]]
  [ "$(called fix)" -eq 1 ]
  [ "$(called review)" -eq 2 ]
  [ "$(pr | jq .merged)" = "true" ]
}

idea() { state | jq -c '.issues[] | select(.number == 7)'; }
paused() { # the idea is paused: label, pauseReason in the metadata, closed
  [ "$(idea | jq -c '[.labels[].name]')" = '["sw-pomysl","sw-stan-wstrzymany"]' ]
  [ "$(idea | jq -r .state)" = "closed" ]
  meta="$(idea | jq -r .body | sed -n 's/.*<!-- sw:meta \(.*\) -->/\1/p')"
  [ "$(jq -r .repo <<<"$meta")" = "cieyhomelab/app" ]
  [[ "$(jq -r .pauseReason <<<"$meta")" == *"$1"*"https://github.com/cieyhomelab/app/pull/3"* ]]
}

@test "S4 remarks after specFixRounds rounds pause the project and notify the owner once" {
  rounds="$(jq -r .specFixRounds "$home/config/sw.json")"
  reviews uwagi uwagi uwagi uwagi
  spec
  [ "$status" -eq 0 ]
  [[ "$output" == *"TRACE rounds exhausted"* ]]
  [[ "$output" == *"TRACE pause-rounds pass"* ]]
  [[ "$output" == *"END stopped success"* ]]
  [ "$(called fix)" -eq "$rounds" ]
  [ "$(called review)" -eq $((rounds + 1)) ]
  [ "$(called security)" -eq 0 ]
  [ "$(pr | jq .merged)" = "false" ]
  [ "$(pr | jq .draft)" = "true" ]
  paused "uwagi do specyfikacji po wyczerpaniu rund"
  # the owner gets one "blocked" notification: the reason, a link to the idea, no questions
  [ "$(pushes | jq length)" -eq 1 ]
  [ "$(pushes | jq -c '.[0].body | {gate, repo, number, url}')" \
    = '{"gate":"blocked","repo":"cieyhomelab/sw-control","number":7,"url":"https://github.com/cieyhomelab/sw-control/issues/7"}' ]
  [[ "$(pushes | jq -r '.[0].body.title')" == "Projekt wstrzymany: "*"uwagi"* ]]
  [[ "$(state | jq -r '.comments["1"][]?.body')" == *"wstrzymanie: pomysł #7"* ]]
}

@test "S4 after the pause the next cycle returns GENERATOR and the agents do not work in the project" {
  reviews uwagi uwagi uwagi uwagi
  spec
  [ "$status" -eq 0 ]
  paused "uwagi"
  fixes="$(called fix)"
  run env SW_CEZAR_URL="$MOCK_URL" CEZ_PROJECT_ID=proj bash "$home/bin/sw-gate"
  [[ "$output" == *"URUCHOM: GENERATOR"* ]]
  # a repeated pause changes nothing and sends no second notification
  run bash "$home/bin/sw-spec-pause" "uwagi"
  [ "$output" = "WYNIK: POMINIETO issue 7 nie jest aktywnym pomyslem" ]
  [ "$(pushes | jq length)" -eq 1 ]
  [ "$(called fix)" -eq "$fixes" ]
}

@test "S4 a failed security review of the specification blocks the merge" {
  reviews zatwierdzona
  cat > "$WORK/agent2" <<'AGENT'
#!/usr/bin/env bash
if [ "$1" = analyst ]; then
  "$(dirname "$0")/agent" "$@" >/dev/null
  echo 'Kontakt: jan.kowalski@example.org' >> .ai/specs/2026-10-26-planer.md
  echo gotowa
else
  exec "$(dirname "$0")/agent" "$@"
fi
AGENT
  chmod +x "$WORK/agent2"; MOCK_AGENT="$WORK/agent2" spec
  [ "$status" -eq 0 ]
  [[ "$output" == *"TRACE security fail"* ]]
  [[ "$output" == *"TRACE pause-security pass"* ]]
  [[ "$output" == *"END stopped success"* ]]
  [ "$(pr | jq .merged)" = "false" ]
  [ "$(pr | jq .draft)" = "true" ]
  paused "przegląd bezpieczeństwa"
  [ "$(pushes | jq length)" -eq 1 ]
  [ "$(pushes | jq -r '.[0].body.gate')" = "blocked" ]
}

@test "S4 a push after the verdicts (another head SHA) blocks the merge" {
  reviews zatwierdzona
  PUSH_AFTER_VERDICT=1 spec
  [ "$status" -eq 0 ]
  [[ "$output" == *"TRACE merge fail"* ]]
  [[ "$output" == *"END stopped success"* ]]
  [ "$(pr | jq .merged)" = "false" ]
  [ "$(pr | jq .draft)" = "true" ]
  [ "$(pushes)" = "[]" ]
}

@test "S4 a review on the model of the author does not merge" {
  reviews zatwierdzona
  curl -fsS -X POST "$MOCK_URL/__control" -d '{"runs": [
    {"project": "proj", "id": "analyst", "modelIdentity": "anthropic/sonnet[1m]"},
    {"project": "proj", "id": "review", "modelIdentity": "anthropic/sonnet[1m]"},
    {"project": "proj", "id": "security", "modelIdentity": "anthropic/haiku[1m]"}]}' >/dev/null
  spec
  [ "$status" -eq 0 ]
  [[ "$output" == *"TRACE merge fail"* ]]
  [ "$(pr | jq .merged)" = "false" ]
  [ "$(pr | jq .draft)" = "true" ]
}

@test "S4 sw:ustalenia with personal data ends the task before the analyst uses it" {
  reviews zatwierdzona
  curl -fsS -X POST "$MOCK_URL/__control" -d '{"comments": {"7": [{"body": "<!-- sw:ustalenia -->\nKontakt: jan.kowalski@example.org", "created_at": "2026-10-26T00:00:00Z"}]}}' >/dev/null
  spec
  [ "$status" -eq 0 ]
  [[ "$output" == *"TRACE sec-ustalenia fail"* ]]
  [[ "$output" == *"END stopped success"* ]]
  [ "$(cat "$CALLS")" = "sec-ustalenia" ]
  [ "$(pr | jq .merged)" = "false" ]
  [ "$(pr | jq .draft)" = "true" ]
}
