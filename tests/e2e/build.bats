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
  export BREAKE2E="$WORK/breake2e" FAILE2E="$WORK/faile2e" TESTERS="$WORK/testers" LEAK="$WORK/leak" STUCK="$WORK/stuck" MOCK_URL
  : > "$CALLS"; : > "$CIS"; : > "$BREAK"; : > "$BREAKE2E"; : > "$FAILE2E"; : > "$LEAK"; : > "$STUCK"; echo pass > "$TESTERS"
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
  # S10 the deployment: the real bin/sw-deploy against the fake Docker (tests/fakes/docker) with a real listener
  export FAKE_DOCKER_DIR="$WORK/docker" FAKE_DOCKER_LOGIN="wlasciciel:sekretne-haslo" SW_DEPLOY_DIR="$WORK/deploy" SW_DEPLOY_NAME=planer SW_DEPLOY_POLL=0.1
  export SW_DEPLOY_LOGIN_FILE="$WORK/login"; printf '%s\n' "$FAKE_DOCKER_LOGIN" > "$SW_DEPLOY_LOGIN_FILE"; chmod 600 "$SW_DEPLOY_LOGIN_FILE"
  printf 'FROM scratch\nEXPOSE 3000\n' > Dockerfile
  jq '.deploy.readySeconds = 1' "$home/config/sw.json" > "$WORK/sw.json"; export SW_CONFIG="$WORK/sw.json"
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
  engineer | fix-mod | fix-test | fix-app)
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
    # the application features the security review judges (S9): $LEAK holds one of them
    if [ "$1" = engineer ] && [ -s "$LEAK" ]; then
      case "$(cat "$LEAK")" in
        secret) printf 'KEY=ghp_%s\n' "$(printf 'a%.0s' $(seq 36))" > src/secret.env ;;
        feature) echo 'echo daj poradę inwestycyjną' > src/porady.sh ;;
        open) echo 'GET /lista bez logowania' > src/trasy.txt ;;
        signup) echo 'POST /rejestracja' > src/trasy.txt ;;
      esac
    fi
    if [ "$1" = fix-app ] && [ ! -s "$STUCK" ]; then rm -f src/secret.env src/porady.sh src/trasy.txt; fi
    echo gotowa ;;
  security-app)
    # the review of the whole application: the mock judges what the mock engineer plants (see
    # $LEAK); a secret it deliberately does NOT see, bin/sw-przeglad has to catch it
    mkdir -p .ai/sw-run
    bad=0
    if [ -e src/porady.sh ]; then bad=1; elif [ -e src/trasy.txt ] && grep -q 'bez logowania' src/trasy.txt; then bad=3
    elif [ -e src/trasy.txt ] && grep -q 'rejestracja' src/trasy.txt; then bad=4; fi
    jq -n --argjson bad "$bad" '{punkty: [range(1; 5) | {punkt: ., wynik: (if . == $bad then "fail" else "pass" end), uzasadnienie: "sprawdzono punkt \(.)"}]}' > .ai/sw-run/przeglad.json
    if [ "$bad" -eq 0 ]; then echo pass; else echo fail; fi ;;
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

teardown() {
  for f in "$FAKE_DOCKER_DIR"/pid-*; do [ ! -e "$f" ] || kill "$(cat "$f")" 2>/dev/null || true; done
  cd / && rm -rf "$WORK"
}

state() { curl -fsS -X POST -d '{}' "$MOCK_URL/__control"; }
pr() { curl -fsS "$MOCK_URL/github/repos/cieyhomelab/app/pulls/3"; }
pushes() { curl -fsS "$MOCK_URL/__requests" | jq -c '[.[] | select(.method == "POST" and .path == "/m/push/gate")]'; }
build() { run python3 "$home/tests/tools/run_workflow.py" "$home/workflows/sw-build.yml"; }
# two approvals are appended: the PR with the report of the security review (S9) is reviewed too
reviews() { printf '%s\n' "$@" approve approve > "$REVIEWS"; }
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
  # the module PR and the PR with the report of the security review (S9)
  [ "$(called review-mod)" -eq 2 ]
  [ "$(called security-mod)" -eq 2 ]
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
  [ "$(called review-mod)" -eq 3 ]
  [ "$(called security-mod)" -eq 2 ]
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
  [ "$(idea | jq -c '[.labels[].name]')" = '["sw-bez-interwencji","sw-pomysl","sw-stan-wdrozony"]' ]
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
  # the fix goes through a new PR: a second review and a second security review (plus the report PR)
  [ "$(called review-mod)" -eq 3 ]
  [ "$(called security-mod)" -eq 3 ]
  [[ "$output" == *"TRACE tester pass"* && "$output" == *"END done success"* ]]
  [ "$(idea | jq -c '[.labels[].name]')" = '["sw-bez-interwencji","sw-pomysl","sw-stan-wdrozony"]' ]
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
  [ "$(idea | jq -c '[.labels[].name]')" = '["sw-bez-interwencji","sw-pomysl","sw-stan-wdrozony"]' ]
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

# S9: the security review of the whole application before the deployment
report() { ls docs/security/*-raport.md; }

@test "S9 a positive review leaves docs/security/<date>-raport.md with the result of each of the four points in the merged code" {
  reviews approve approve
  build
  [ "$status" -eq 0 ]
  [[ "$output" == *"TRACE security-app pass"* && "$output" == *"TRACE app-check pass"* ]]
  [[ "$output" == *"TRACE report-merged pass"* && "$output" == *"END done success"* ]]
  [ "$(called security-app)" -eq 1 ]
  [ "$(called fix-app)" -eq 0 ]
  run report
  [[ "$output" =~ ^docs/security/[0-9]{4}-[0-9]{2}-[0-9]{2}-raport\.md$ ]]
  for n in 1 2 3 4; do grep -qE "^\| $n\. .* \| pass \|" docs/security/*-raport.md; done
  [ "$(pr | jq .merged)" = "true" ]
  [ "$(idea | jq -c '[.labels[].name]')" = '["sw-bez-interwencji","sw-pomysl","sw-stan-wdrozony"]' ]
}

@test "S9 a function of an excluded category stops the deployment and starts a fix task of the engineer" {
  echo feature > "$LEAK"
  printf 'pass\npass\n' > "$TESTERS"
  reviews approve approve approve
  build
  [ "$status" -eq 0 ]
  [[ "$output" == *"TRACE security-app fail"* && "$output" == *"TRACE app-check fail"* ]]
  [[ "$output" == *"TRACE rounds-app repeat"* && "$output" == *"TRACE fix-app gotowa"* ]]
  [ "$(called fix-app)" -eq 1 ]
  # the fix goes through a new PR, the tests and the review run again, then the report appears
  [ "$(called security-app)" -eq 2 ]
  [ ! -e src/porady.sh ]
  [[ "$output" == *"END done success"* ]]
  report
}

@test "S9 a secret in the repository stops the deployment even when the agent does not see it" {
  echo secret > "$LEAK"
  printf 'pass\npass\n' > "$TESTERS"
  reviews approve approve approve
  build
  [ "$status" -eq 0 ]
  # the mock agent says "pass" for it: the script bin/sw-przeglad scans the files itself
  [[ "$output" == *"TRACE security-app pass"* && "$output" == *"TRACE app-check fail"* ]]
  [ "$(called fix-app)" -eq 1 ]
  [ ! -e src/secret.env ]
  [[ "$output" == *"END done success"* ]]
  report
}

@test "S9 an address available without authentication stops the deployment" {
  echo open > "$LEAK"
  printf 'pass\npass\n' > "$TESTERS"
  reviews approve approve approve
  build
  [ "$status" -eq 0 ]
  [[ "$output" == *"TRACE security-app fail"* && "$output" == *"TRACE app-check fail"* ]]
  [ "$(called fix-app)" -eq 1 ]
  [[ "$output" == *"END done success"* ]]
}

@test "S9 a registration of new accounts stops the deployment" {
  echo signup > "$LEAK"
  printf 'pass\npass\n' > "$TESTERS"
  reviews approve approve approve
  build
  [ "$status" -eq 0 ]
  [[ "$output" == *"TRACE security-app fail"* && "$output" == *"TRACE app-check fail"* ]]
  [ "$(called fix-app)" -eq 1 ]
  [[ "$output" == *"END done success"* ]]
}

@test "S9 fixRoundsPerPr rounds of a failing review pause the project, nothing is reported as passed" {
  rounds="$(jq -r .fixRoundsPerPr "$home/config/sw.json")"
  echo feature > "$LEAK"; echo stuck > "$STUCK"
  printf 'pass\n%.0s' 1 2 3 4 5 > "$TESTERS"
  reviews approve approve approve approve approve
  build
  [ "$status" -eq 0 ]
  [[ "$output" == *"TRACE rounds-app exhausted"* && "$output" == *"TRACE pause-rounds-app pass"* ]]
  [[ "$output" == *"END stopped success"* ]]
  [ "$(called fix-app)" -eq "$rounds" ]
  ! ls docs/security/*-raport.md 2>/dev/null
  [ "$(idea | jq -c '[.labels[].name]')" = '["sw-pomysl","sw-stan-wstrzymany"]' ]
  [ "$(pushes | jq length)" -eq 1 ]
}

# S10: the deployment and the notification of the owner
deployed() { curl -s -o /dev/null -w '%{http_code}' --max-time 5 ${2:+-u "$2"} "$1/" || true; }
addr=http://127.0.0.1:18100

@test "S10 after the green tests and the positive review the application is deployed: a request without the login is refused, the owner sees the application" {
  reviews approve approve
  build
  [ "$status" -eq 0 ]
  [[ "$output" == *"TRACE report-merged pass"* && "$output" == *"TRACE state-deploy pass"* && "$output" == *"TRACE deploy pass"* ]]
  [[ "$output" == *"TRACE finish pass"* && "$output" == *"END done success"* ]]
  [ "$(deployed $addr)" = 401 ]
  [ "$(deployed $addr "$FAKE_DOCKER_LOGIN")" = 200 ]
  [ "$(deployed $addr wlasciciel:zle)" = 401 ]
  # the application container publishes nothing; the proxy is the only published port, on the private address
  [ "$(grep '^run ' "$FAKE_DOCKER_DIR/calls" | grep -c -- ' -p ')" -eq 0 ]
  [ "$(grep '^create ' "$FAKE_DOCKER_DIR/calls" | grep -c -- '-p 127.0.0.1:18100:8080')" -eq 1 ]
}

@test "S10 a deployment gives the owner one notification with the title and the address, and the project is wdrozony" {
  reviews approve approve
  build
  [ "$status" -eq 0 ]
  [ "$(idea | jq -c '[.labels[].name]')" = '["sw-bez-interwencji","sw-pomysl","sw-stan-wdrozony"]' ]
  [ "$(idea | jq -r .state)" = closed ]
  [ "$(idea | jq -r .body | grep -c "$addr")" -ge 1 ]
  [ "$(pushes | jq length)" -eq 1 ]
  [ "$(pushes | jq -r '.[0].body.title')" = "Wdrożono: $addr (planer) · 100% bez interwencji" ]
  [ "$(pushes | jq -r '.[0].body.url')" = https://github.com/cieyhomelab/sw-control/issues/7 ]
}

@test "S13 from the architecture to the deployment the owner gets no message besides the deployment notification, which shows the share" {
  reviews approve approve
  build
  [ "$status" -eq 0 ]
  [ "$(pushes | jq length)" -eq 1 ]
  [[ "$(pushes | jq -r '.[0].body.title')" == "Wdrożono: "*" · 100% bez interwencji" ]]
  [ "$(idea | jq -c '.labels | map(.name) | index("sw-bez-interwencji") != null')" = true ]
}

@test "S10 a deployed project is no longer active: the next cycle starts the generator" {
  reviews approve approve
  build
  [ "$status" -eq 0 ]
  run "$home/bin/sw-gate"
  [[ "$output" == *"URUCHOM: GENERATOR"* ]]
}

@test "S10 a failed deployment is retried retriesPerTask times, leaves nothing reachable and pauses the project" {
  retries="$(jq -r .retriesPerTask "$home/config/sw.json")"
  export FAKE_DOCKER_MODE=dead
  reviews approve approve
  build
  [ "$status" -eq 0 ]
  [ "$(grep -c "^TRACE deploy fail" <<<"$output")" -eq $((retries + 1)) ]
  [[ "$output" == *"TRACE rounds-deploy exhausted"* && "$output" == *"TRACE pause-deploy pass"* && "$output" == *"END stopped success"* ]]
  [ "$(deployed $addr)" = 000 ]
  [ "$(deployed $addr "$FAKE_DOCKER_LOGIN")" = 000 ]
  [ "$(idea | jq -c '[.labels[].name]')" = '["sw-pomysl","sw-stan-wstrzymany"]' ]
  [ "$(pushes | jq length)" -eq 1 ]
  [[ "$(pushes | jq -r '.[0].body.title')" == "Projekt wstrzymany: wdrożenie"* ]]
}

@test "S10 a proxy that would serve the application without the login fails the deployment, nothing is reachable and no notification says deployed" {
  export FAKE_DOCKER_MODE=open
  reviews approve approve
  build
  [ "$status" -eq 0 ]
  [[ "$output" == *"TRACE deploy fail"* && "$output" == *"TRACE pause-deploy pass"* ]]
  [[ "$output" != *"TRACE finish"* ]]
  [ "$(deployed $addr)" = 000 ]
  [ "$(idea | jq -c '[.labels[].name]')" = '["sw-pomysl","sw-stan-wstrzymany"]' ]
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
