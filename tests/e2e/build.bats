#!/usr/bin/env bats
# E2E (S5 one module, S6, S7, S8): the sw-build workflow of an application repository, walked by
# tests/tools/run_workflow.py with a mock agent, against the mocked Cezar, GitHub and
# cezar-push APIs. The scripts run exactly as on the VPS (sw-limits, sw-architektura-check,
# sw-spec-pr -> sw-merge kod, sw-pause). What the agents write is not tested here
# (AGENTS.md); the tests pin the wiring and the checks of the scripts.

setup() {
  : "${MOCK_URL:?run through scripts/test-e2e.sh}"
  curl -fsS -X POST -d '{"reset": true}' "$MOCK_URL/__control" >/dev/null
  home="${SW_HOME:-/work}"
  WORK="$(mktemp -d)"
  cd "$WORK" || return 1
  mkdir -p .ai/specs .ai/sw-run
  export SW_PUSH_URL="$MOCK_URL"
  SW_PUSH_TOKEN_FILE="$WORK/token"; echo test-token > "$SW_PUSH_TOKEN_FILE"; export SW_PUSH_TOKEN_FILE
  export CEZ_PROJECT_ID=proj SW_SPEC_REPO=cieyhomelab/app SW_SPEC_BRANCH=build
  export FAKE_GH_API_URL="$MOCK_URL" CALLS="$WORK/calls" REVIEWS="$WORK/reviews" CIS="$WORK/cis" BREAK="$WORK/break"
  export BREAKE2E="$WORK/breake2e" FAILE2E="$WORK/faile2e" TESTERS="$WORK/testers" MOCK_URL
  : > "$CALLS"; : > "$CIS"; : > "$BREAK"; : > "$BREAKE2E"; : > "$FAILE2E"; echo pass > "$TESTERS"
  printf '# Planer\n\nPomysł i jego ocena: https://github.com/cieyhomelab/sw-control/issues/7\n' > README.md
  printf '# Planer\n\n### S1: Menu\n- Zakładając tydzień, wtedy lista zakupów.\n\n### S2: Lista\n- Zakładając menu, wtedy lista.\n\n## Założenia\n- Język polski.\n' > .ai/specs/spec.md
  curl -fsS -X POST "$MOCK_URL/__control" -d '{
    "issues": [{"number": 1, "state": "open", "title": "sw-dziennik", "labels": [{"name": "sw-dziennik"}]},
               {"number": 7, "state": "open", "title": "Planer posiłków", "labels": [{"name": "sw-pomysl"}, {"name": "sw-stan-architektura"}],
                "body": "## Problem i dla kogo\nx\n\n<!-- sw:meta {\"repo\":\"cieyhomelab/app\",\"projectId\":\"proj\"} -->"}],
    "pulls": {"cieyhomelab/app#3": {"head_sha": "abc1234", "branch": "build", "draft": true, "body": "Architektura"}},
    "check_runs": {"cieyhomelab/app@abc1234": [{"name":"checks","status":"completed","conclusion":"success"},
                                                {"name":"e2e","status":"completed","conclusion":"success"}]},
    "runs": [{"project": "proj", "id": "architect", "modelIdentity": "anthropic/opus[1m]"},
             {"project": "proj", "id": "review", "modelIdentity": "anthropic/sonnet[1m]"},
             {"project": "proj", "id": "security", "modelIdentity": "anthropic/haiku[1m]"},
             {"project": "proj", "id": "engineer", "modelIdentity": "anthropic/opus[1m]"},
             {"project": "proj", "id": "review-mod", "modelIdentity": "anthropic/sonnet[1m]"},
             {"project": "proj", "id": "security-mod", "modelIdentity": "anthropic/haiku[1m]"}]}' >/dev/null
  export MOCK_AGENT="$WORK/agent" MOCK_CI="$WORK/ci" PATH="$home/tests/fakes:$PATH"
  cat > "$MOCK_AGENT" <<'AGENT'
#!/usr/bin/env bash
# Mock agents of sw-build. architect and fix write a complete architecture (a line in
# $BREAK makes the architect leave scenario S2 unassigned once); review takes its
# verdicts one by one from $REVIEWS.
set -euo pipefail
echo "$1" >> "$CALLS"
case "$1" in
  architect | fix)
    mkdir -p docs/kontrakty .github/workflows
    scenarios="S1, S2"
    if [ "$1" = architect ] && [ -s "$BREAK" ]; then scenarios="S1"; fi
    printf '# planer\n\n## Udostępnia\n- ekran menu\n\n## Wymaga\nbrak\n\n## Forma\nczęść aplikacji\nJedna aplikacja.\n\n## Scenariusze\n%s\n' "$scenarios" > docs/kontrakty/planer.md
    printf 'name: CI\non:\n  pull_request:\njobs:\n  checks:\n    runs-on: ubuntu-latest\n    steps: [{run: "true"}]\n  e2e:\n    runs-on: ubuntu-latest\n    steps: [{run: "true"}]\n' > .github/workflows/ci.yml
    echo gotowa ;;
  engineer | fix-mod | fix-test)
    # the module: a test for every "udostępnia" item and an E2E test for every scenario
    # ($BREAKE2E leaves S2 out of the first implementation, $FAILE2E makes the E2E fail until fix-test)
    mkdir -p src tests/unit tests/e2e scripts
    echo 'echo menu' > src/menu.sh
    echo '@test "ekran menu" { true; }' > tests/unit/menu.bats
    sed -i '/^## Pokrycie/,$d' docs/kontrakty/planer.md
    printf '\n## Pokrycie\n- ekran menu => tests/unit/menu.bats\n' >> docs/kontrakty/planer.md
    echo '@test "S1: menu tygodnia" { true; }' > tests/e2e/app.bats
    if [ "$1" != engineer ] || [ ! -s "$BREAKE2E" ]; then echo '@test "S2: lista zakupów" { true; }' >> tests/e2e/app.bats; fi
    if [ "$1" = fix-test ]; then : > "$FAILE2E"; fi
    printf '#!/usr/bin/env bash\n[ ! -s "%s" ]\n' "$FAILE2E" > scripts/test-e2e.sh
    echo "$1 $(date +%N)" > "src/rev-$1"
    echo gotowa ;;
  tester)
    verdict="$(head -1 "$TESTERS")"; sed -i 1d "$TESTERS"
    [ "$verdict" = fail ] && echo "1. S2: test nie sprawdza skutku." > .ai/sw-run/uwagi.md
    echo "$verdict" ;;
  review | review-mod)
    verdict="$(head -1 "$REVIEWS")"; sed -i 1d "$REVIEWS"
    [ "$verdict" = changes ] && echo "1. Kontrakt jest niejasny." > .ai/sw-run/uwagi.md
    echo "$verdict" ;;
  security | security-mod)
    if grep -rqE '[A-Za-z0-9._-]+@[A-Za-z0-9.-]+\.[a-z]+' docs .github; then echo fail; else echo pass; fi ;;
esac
AGENT
  chmod +x "$MOCK_AGENT"
  printf '#!/usr/bin/env bash\necho "ci-$2" >> "$CALLS"\nhead -1 "$CIS" | grep . || echo green\nsed -i 1d "$CIS"\n' > "$MOCK_CI"; chmod +x "$MOCK_CI"
  export MOCK_GIT="$WORK/git"
  # the module PR is a new PR of the branch: after the merge of the architecture the mock PR is open again
  printf '#!/usr/bin/env bash\necho "$1" >> "$CALLS"\n[ "$1" != pr-mod ] || curl -fsS -X POST "$MOCK_URL/__control" -d %s >/dev/null\n' \
    "'{\"pulls\": {\"cieyhomelab/app#3\": {\"head_sha\": \"abc1234\", \"branch\": \"build\", \"draft\": true, \"body\": \"Modul\"}}}'" > "$MOCK_GIT"; chmod +x "$MOCK_GIT"
}

teardown() { cd / && rm -rf "$WORK"; }

state() { curl -fsS -X POST -d '{}' "$MOCK_URL/__control"; }
pr() { curl -fsS "$MOCK_URL/github/repos/cieyhomelab/app/pulls/3"; }
pushes() { curl -fsS "$MOCK_URL/__requests" | jq -c '[.[] | select(.method == "POST" and .path == "/m/push/gate")]'; }
build() { run python3 "$home/tests/tools/run_workflow.py" "$home/workflows/sw-build.yml"; }
reviews() { printf '%s\n' "$@" > "$REVIEWS"; }
cis() { printf '%s\n' "$@" > "$CIS"; }
called() { grep -c "^$1\$" "$CALLS" || true; }
idea() { state | jq -c '.issues[] | select(.number == 7)'; }

@test "S5 an approved review, a green CI and passed security merge the architecture PR with sw-merge kod" {
  reviews approve approve
  build
  [ "$status" -eq 0 ]
  [[ "$output" == *"END done success"* ]]
  [ "$(pr | jq .merged)" = "true" ]
  [ "$(pr | jq .draft)" = "false" ]
  # S5/S8: every step starts with sw-limits; the architect is the first agent
  [[ "$output" == *"TRACE limits-architect pass"* ]]
  [ "$(sed -n 1p "$CALLS")" = architect ]
  [[ "$output" == *"TRACE limits-review pass"* && "$output" == *"TRACE limits-merge pass"* ]]
}

@test "S5 the architecture check runs on the PR: contract, assigned scenarios, CI jobs" {
  reviews approve approve
  build
  [ "$status" -eq 0 ]
  [[ "$output" == *"TRACE arch-check pass"* ]]
  grep -q '^## Forma' docs/kontrakty/planer.md
  [ "$(grep -c 'S[12]' docs/kontrakty/planer.md)" -ge 1 ]
  grep -q 'pull_request' .github/workflows/ci.yml
}

@test "S5 a scenario left unassigned starts a fix round before the review" {
  echo broken > "$BREAK"
  reviews approve approve
  build
  [ "$status" -eq 0 ]
  [[ "$output" == *"TRACE arch-check fail"* ]]
  [[ "$output" == *"TRACE rounds repeat"* ]]
  [[ "$output" == *"END done success"* ]]
  [ "$(called fix)" -eq 1 ]
  [ "$(called review)" -eq 1 ]
  [ "$(pr | jq .merged)" = "true" ]
}

@test "S8 remarks of the reviewer start a fix round and a repeated review" {
  reviews changes approve approve
  build
  [ "$status" -eq 0 ]
  [[ "$output" == *"TRACE review changes"* ]]
  [ "$(called fix)" -eq 1 ]
  [ "$(called review)" -eq 2 ]
  [ "$(called security)" -eq 1 ]
  [ "$(pr | jq .merged)" = "true" ]
}

@test "S8 a red CI starts a fix round, a green one lets the PR merge" {
  reviews approve approve approve
  cis red green
  build
  [ "$status" -eq 0 ]
  [[ "$output" == *"TRACE ci red"* ]]
  [ "$(called fix)" -eq 1 ]
  [ "$(pr | jq .merged)" = "true" ]
}

@test "S8 a required check-run missing for the reviewed SHA blocks the merge" {
  curl -fsS -X POST "$MOCK_URL/__control" -d '{"check_runs": {"cieyhomelab/app@abc1234": [{"name":"checks","status":"completed","conclusion":"success"}]}}' >/dev/null
  reviews approve
  build
  [ "$status" -eq 0 ]
  [[ "$output" == *"TRACE merge fail"* ]]
  [[ "$output" == *"END stopped success"* ]]
  [ "$(pr | jq .merged)" = "false" ]
}

@test "S8 fixRoundsPerPr rounds of remarks pause the project and notify the owner once" {
  rounds="$(jq -r .fixRoundsPerPr "$home/config/sw.json")"
  reviews changes changes changes changes changes
  build
  [ "$status" -eq 0 ]
  [[ "$output" == *"TRACE rounds exhausted"* && "$output" == *"TRACE pause-rounds pass"* ]]
  [[ "$output" == *"END stopped success"* ]]
  [ "$(called fix)" -eq "$rounds" ]
  [ "$(called security)" -eq 0 ]
  [ "$(pr | jq .merged)" = "false" ]
  [ "$(idea | jq -c '[.labels[].name]')" = '["sw-pomysl","sw-stan-wstrzymany"]' ]
  [ "$(pushes | jq length)" -eq 1 ]
  [ "$(pushes | jq -r '.[0].body.gate')" = blocked ]
}

@test "S8 a failed security review pauses the project and leaves the PR unmerged" {
  reviews approve
  # an e-mail address in the contract stands in for personal data
  printf '#!/usr/bin/env bash\nsed -i "s/^brak$/jan@example.com/" docs/kontrakty/planer.md\n' > "$WORK/leak"; chmod +x "$WORK/leak"
  curl -fsS -X POST "$MOCK_URL/__control" -d '{}' >/dev/null
  MOCK_GIT="$WORK/leak" build
  [ "$status" -eq 0 ]
  [[ "$output" == *"TRACE security fail"* && "$output" == *"TRACE pause-security pass"* ]]
  [ "$(pr | jq .merged)" = "false" ]
  [ "$(idea | jq -c '[.labels[].name]')" = '["sw-pomysl","sw-stan-wstrzymany"]' ]
}

@test "S12 every step starts with sw-limits: over the usage limit the task stops before the architect" {
  jq '.projectUsageLimitUsd = 1' "$home/config/sw.json" > "$WORK/sw.json"
  curl -fsS -X POST "$MOCK_URL/__control" -d '{"runs": [{"project": "proj", "id": "old", "costUsd": 5}]}' >/dev/null
  SW_CONFIG="$WORK/sw.json" build
  [ "$status" -eq 0 ]
  [[ "$output" == *"TRACE limits-architect fail"* ]]
  [[ "$output" == *"END stopped success"* ]]
  [ "$(called architect)" -eq 0 ]
  [ "$(idea | jq -c '[.labels[].name]')" = '["sw-pomysl","sw-stan-wstrzymany"]' ]
}

@test "S6 the module goes through its own PR: engineer, test for every item, review, CI, security, sw-merge kod" {
  reviews approve approve
  build
  [ "$status" -eq 0 ]
  [[ "$output" == *"TRACE state-impl pass"* && "$output" == *"TRACE limits-engineer pass"* ]]
  [[ "$output" == *"TRACE mod-check pass"* && "$output" == *"TRACE merge-mod pass"* ]]
  [[ "$output" == *"TRACE limits-review-mod pass"* && "$output" == *"TRACE limits-merge-mod pass"* ]]
  [ "$(called engineer)" -eq 1 ]
  [ "$(called review-mod)" -eq 1 ]
  [ "$(called security-mod)" -eq 1 ]
  grep -q '^- ekran menu => tests/unit/menu.bats$' docs/kontrakty/planer.md
  [ "$(pr | jq .merged)" = "true" ]
}

@test "S6 an item of 'udostępnia' without a test starts a fix round before the review" {
  # the engineer names a missing test file once: the check fails, the fix round repairs it
  printf '#!/usr/bin/env bash\n[ "$1" != pr-mod ] || [ -e .ai/sw-run/seen ] || { touch .ai/sw-run/seen; rm tests/unit/menu.bats; }\n[ "$1" != pr-mod ] || curl -fsS -X POST "$MOCK_URL/__control" -d %s >/dev/null\necho "$1" >> "$CALLS"\n' \
    "'{\"pulls\": {\"cieyhomelab/app#3\": {\"head_sha\": \"abc1234\", \"branch\": \"build\", \"draft\": true, \"body\": \"Modul\"}}}'" > "$WORK/nottest"
  chmod +x "$WORK/nottest"
  reviews approve approve
  MOCK_GIT="$WORK/nottest" build
  [ "$status" -eq 0 ]
  [[ "$output" == *"TRACE mod-check fail"* && "$output" == *"TRACE rounds-mod repeat"* ]]
  [[ "$output" == *"TRACE mod-check-fix pass"* ]]
  [ "$(called fix-mod)" -eq 1 ]
  [ "$(pr | jq .merged)" = "true" ]
}

@test "S8 remarks on the module PR start a fix round of the engineer and a repeated review" {
  reviews approve changes approve
  build
  [ "$status" -eq 0 ]
  [[ "$output" == *"TRACE review-mod changes"* ]]
  [ "$(called fix-mod)" -eq 1 ]
  [ "$(called review-mod)" -eq 2 ]
  [ "$(called security-mod)" -eq 1 ]
  [ "$(pr | jq .merged)" = "true" ]
}

@test "S8 fixRoundsPerPr rounds of remarks on the module PR pause the project" {
  rounds="$(jq -r .fixRoundsPerPr "$home/config/sw.json")"
  reviews approve changes changes changes changes changes
  build
  [ "$status" -eq 0 ]
  [[ "$output" == *"TRACE rounds-mod exhausted"* && "$output" == *"TRACE pause-rounds-mod pass"* ]]
  [ "$(called fix-mod)" -eq "$rounds" ]
  [ "$(called security-mod)" -eq 0 ]
  [ "$(idea | jq -c '[.labels[].name]')" = '["sw-pomysl","sw-stan-wstrzymany"]' ]
  [ "$(pushes | jq length)" -eq 1 ]
}

@test "S7 a green E2E and the verdict pass of the tester move the project to sw-stan-przeglad" {
  reviews approve approve
  build
  [ "$status" -eq 0 ]
  [[ "$output" == *"TRACE e2e-check pass"* && "$output" == *"TRACE e2e-run pass"* && "$output" == *"TRACE tester pass"* ]]
  [[ "$output" == *"END done success"* ]]
  [ "$(called tester)" -eq 1 ]
  [ "$(idea | jq -c '[.labels[].name]')" = '["sw-pomysl","sw-stan-przeglad"]' ]
  # every scenario of the specification has an E2E test
  grep -q 'S1' tests/e2e/app.bats && grep -q 'S2' tests/e2e/app.bats
}

@test "S7 a scenario without an E2E test starts a fix round, the project waits in sw-stan-integracja" {
  echo broken > "$BREAKE2E"
  reviews approve approve approve
  build
  [ "$status" -eq 0 ]
  [[ "$output" == *"TRACE e2e-check fail"* && "$output" == *"TRACE rounds-test repeat"* ]]
  [ "$(called fix-test)" -eq 1 ]
  # the fix goes through a new PR: a second review and a second security review
  [ "$(called review-mod)" -eq 2 ]
  [ "$(called security-mod)" -eq 2 ]
  [[ "$output" == *"TRACE tester pass"* && "$output" == *"END done success"* ]]
  [ "$(idea | jq -c '[.labels[].name]')" = '["sw-pomysl","sw-stan-przeglad"]' ]
}

@test "S7 a failing E2E run of the whole application sends the engineer a fix round" {
  echo broken > "$FAILE2E"
  reviews approve approve approve
  build
  [ "$status" -eq 0 ]
  [[ "$output" == *"TRACE e2e-run fail"* && "$output" == *"TRACE rounds-test repeat"* ]]
  [ "$(called fix-test)" -eq 1 ]
  [ "$(called tester)" -eq 1 ]
  [[ "$output" == *"END done success"* ]]
}

@test "S7 remarks of the tester start a fix round and the project does not reach sw-stan-przeglad before it passes" {
  printf 'fail\npass\n' > "$TESTERS"
  reviews approve approve approve
  build
  [ "$status" -eq 0 ]
  [[ "$output" == *"TRACE tester fail"* && "$output" == *"TRACE rounds-test repeat"* ]]
  [ "$(called tester)" -eq 2 ]
  [ "$(called fix-test)" -eq 1 ]
  [ "$(idea | jq -c '[.labels[].name]')" = '["sw-pomysl","sw-stan-przeglad"]' ]
}

@test "S8 fixRoundsPerPr rounds after failed tests pause the project even with no open PR" {
  rounds="$(jq -r .fixRoundsPerPr "$home/config/sw.json")"
  printf 'fail\nfail\nfail\nfail\nfail\n' > "$TESTERS"
  reviews approve approve approve approve approve
  build
  [ "$status" -eq 0 ]
  [[ "$output" == *"TRACE rounds-test exhausted"* && "$output" == *"TRACE pause-rounds-test pass"* ]]
  [[ "$output" == *"END stopped success"* ]]
  [ "$(called fix-test)" -eq "$rounds" ]
  [ "$(idea | jq -c '[.labels[].name]')" = '["sw-pomysl","sw-stan-wstrzymany"]' ]
  [ "$(pushes | jq length)" -eq 1 ]
}

@test "S5 stage 2: the last node of sw-spec starts sw-build instead of the handover" {
  curl -fsS -X POST "$MOCK_URL/__control" -d '{"issues": [{"number": 7, "state": "open", "title": "Planer posiłków", "labels": [{"name": "sw-pomysl"}, {"name": "sw-stan-specyfikacja"}],
    "body": "## Problem i dla kogo\nx\n\n<!-- sw:meta {\"repo\":\"cieyhomelab/app\",\"projectId\":\"proj\"} -->"}],
    "pulls": {"cieyhomelab/app#3": {"head_sha": "abc1234", "branch": "build", "merged": true}}, "runs": []}' >/dev/null
  cmd="$(python3 -c 'import sys, yaml
doc = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
print(next(n for n in doc["nodes"] if n["id"] == "handover")["command"])' "$home/workflows/sw-spec.yml")"
  jq '.stage = 2' "$home/config/sw.json" > "$WORK/sw.json"
  SW_CONFIG="$WORK/sw.json" SW_HOME="$home" run bash -c "$cmd"
  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = "WYNIK: BUDOWA run-1" ]
  [ "$(state | jq -r '.runs[0].workflow')" = sw-build ]
  [ "$(idea | jq -c '[.labels[].name]')" = '["sw-pomysl","sw-stan-architektura"]' ]
}
