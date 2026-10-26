#!/usr/bin/env bats
# Integration: bin/sw-create-repo against the mock Cezar/GitHub API over real HTTP.

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

# idea <nr> <title> [meta-json] [labels-json] — an approved idea card.
idea() {
  jq -nc --argjson n "$1" --arg t "$2" --arg m "${3:-{\}}" --argjson l "${4:-[\"sw-pomysl\",\"sw-zatwierdzony\"]}" '
    {number: $n, state: "open", title: $t, labels: ($l | map({name: .})),
     body: ("## Problem i dla kogo\nx\n\n<!-- sw:meta " + $m + " -->")}'
}

# seeded <name> <issue-nr> [topics-json] — an existing repository with a README linking the idea.
seeded() {
  local url="https://github.com/cieyhomelab/sw-control/issues/$2"
  jq -nc --arg c "$(printf '# x\n%s\n' "$url" | base64 -w0)" --argjson t "${3:-[\"sw-projekt\"]}" \
    '{private: true, topics: $t, files: {"README.md": {sha: "s1", content: $c}}}' \
    | jq -c --arg n "cieyhomelab/$1" '{($n): .}'
}

readme() { jq -r --arg r "$1" '.repos[$r].files["README.md"].content' <<<"$(state)" | base64 -d; }

@test "creates a private repository named after the title and configures everything" {
  control "{\"issues\": [$(idea 7 'Planer posiłków — łódzki Żółw')]}"
  run "$ROOT/bin/sw-create-repo" 7
  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = "WYNIK: REPO cieyhomelab/planer-posilkow-lodzki-zolw proj-planer-posilkow-lodzki-zolw" ]
  s="$(state)"
  r='.repos["cieyhomelab/planer-posilkow-lodzki-zolw"]'
  [ "$(jq -c "$r.topics" <<<"$s")" = '["sw-projekt"]' ]
  [ "$(jq "$r.private" <<<"$s")" = true ]
  [[ "$(readme cieyhomelab/planer-posilkow-lodzki-zolw)" == *"https://github.com/cieyhomelab/sw-control/issues/7"* ]]
  [ "$(jq '.projects[0].maxParallel' <<<"$s")" = 3 ]
  [ "$(jq -c '[.issues[0].labels[].name]' <<<"$s")" = '["sw-pomysl","sw-stan-specyfikacja"]' ]
  body="$(jq -r '.issues[0].body' <<<"$s")"
  [[ "$body" == "## Problem i dla kogo"* ]]
  [ "$(printf '%s' "$body" | sed -n 's/.*<!-- sw:meta \(.*\) -->/\1/p' | jq -cS .)" \
    = '{"projectId":"proj-planer-posilkow-lodzki-zolw","repo":"cieyhomelab/planer-posilkow-lodzki-zolw"}' ]
}

@test "maxParallel comes from the configuration" {
  conf="$WORK/sw.json"
  jq '.maxParallelAgents = 5' "$ROOT/config/sw.json" > "$conf"
  control "{\"issues\": [$(idea 7 'Planer')]}"
  SW_CONFIG="$conf" run "$ROOT/bin/sw-create-repo" 7
  [ "$status" -eq 0 ]
  [ "$(state | jq '.projects[0].maxParallel')" = 5 ]
}

@test "a taken name gets the first free suffix" {
  control "{\"issues\": [$(idea 7 'Planer')], \"repos\": $(seeded planer 3 '[]' | jq -c '. + '"$(seeded planer-2 9 '["sw-projekt"]')")}"
  run "$ROOT/bin/sw-create-repo" 7
  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = "WYNIK: REPO cieyhomelab/planer-3 proj-planer-3" ]
}

@test "409 folder_exists moves on to the next suffix and a bare 500 is an error" {
  control "{\"issues\": [$(idea 7 'Planer')], \"create_fail\": {\"planer\": 409}}"
  run "$ROOT/bin/sw-create-repo" 7
  [ "${lines[-1]}" = "WYNIK: REPO cieyhomelab/planer-2 proj-planer-2" ]
  control "{\"issues\": [$(idea 7 'Planer')], \"repos\": {}, \"projects\": [], \"create_fail\": {\"planer\": 500}}"
  run "$ROOT/bin/sw-create-repo" 7
  [ "$status" -eq 1 ]
  [[ "$output" == "STAN: BLAD "* ]]
}

@test "a repository left by an interrupted run for the same issue is adopted, not duplicated" {
  control "{\"issues\": [$(idea 7 'Planer')], \"repos\": $(seeded planer 7)}"
  run "$ROOT/bin/sw-create-repo" 7
  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = "WYNIK: REPO cieyhomelab/planer proj-planer" ]
  s="$(state)"
  [ "$(jq '[.projects[]] | length' <<<"$s")" -eq 1 ]
  [ "$(curl -fsS "$SW_CEZAR_URL/__requests" | jq '[.[] | select(.path == "/api/v1/projects/create")] | length')" -eq 0 ]
  [ "$(curl -fsS "$SW_CEZAR_URL/__requests" | jq '[.[] | select(.path == "/api/v1/projects/checkout")] | length')" -eq 1 ]
  [ "$(jq '.projects[0].maxParallel' <<<"$s")" = 3 ]
}

@test "a repository claimed in the issue meta is adopted although it has neither topic nor README" {
  empty='{"cieyhomelab/planer": {"private": true, "topics": [], "files": {}}}'
  control "{\"issues\": [$(idea 7 'Planer' '{"pendingRepo":"planer"}')], \"repos\": $empty}"
  run "$ROOT/bin/sw-create-repo" 7
  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = "WYNIK: REPO cieyhomelab/planer proj-planer" ]
  s="$(state)"
  [ "$(jq '[.projects[]] | length' <<<"$s")" -eq 1 ]
  [ "$(curl -fsS "$SW_CEZAR_URL/__requests" | jq '[.[] | select(.path == "/api/v1/projects/create")] | length')" -eq 0 ]
  [ "$(jq -c '.repos["cieyhomelab/planer"].topics' <<<"$s")" = '["sw-projekt"]' ]
  [[ "$(readme cieyhomelab/planer)" == *"issues/7"* ]]
  meta="$(jq -r '.issues[0].body' <<<"$s" | sed -n 's/.*<!-- sw:meta \(.*\) -->/\1/p')"
  [ "$(jq -cS . <<<"$meta")" = '{"projectId":"proj-planer","repo":"cieyhomelab/planer"}' ]
}

@test "a name written before POST create is adopted by the next run (issue #37)" {
  control "{\"issues\": [$(idea 7 'Planer')], \"create_fail\": {\"planer\": 500}}"
  run "$ROOT/bin/sw-create-repo" 7
  [ "$status" -eq 1 ]
  [[ "$output" == "STAN: BLAD "* ]]
  meta="$(state | jq -r '.issues[0].body' | sed -n 's/.*<!-- sw:meta \(.*\) -->/\1/p')"
  [ "$(jq -r '.pendingRepo' <<<"$meta")" = planer ]
  # Cezar created the repository, but the run stopped before the topic was set
  empty='{"cieyhomelab/planer": {"private": true, "topics": [], "files": {}}}'
  control "{\"repos\": $empty, \"create_fail\": {}}"
  run "$ROOT/bin/sw-create-repo" 7
  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = "WYNIK: REPO cieyhomelab/planer proj-planer" ]
  s="$(state)"
  [ "$(jq -c '[.repos | keys[]]' <<<"$s")" = '["cieyhomelab/planer"]' ]
  meta="$(jq -r '.issues[0].body' <<<"$s" | sed -n 's/.*<!-- sw:meta \(.*\) -->/\1/p')"
  [ "$(jq -cS . <<<"$meta")" = '{"projectId":"proj-planer","repo":"cieyhomelab/planer"}' ]
}

@test "a name taken by somebody else is not left claimed after 409 (issue #39)" {
  control "{\"issues\": [$(idea 7 'Planer')], \"create_fail\": {\"planer\": 409}, \"repo_fail\": {\"cieyhomelab/planer-2\": 503}}"
  run "$ROOT/bin/sw-create-repo" 7
  [ "$status" -eq 1 ]
  meta="$(state | jq -r '.issues[0].body' | sed -n 's/.*<!-- sw:meta \(.*\) -->/\1/p')"
  [ "$(jq -r '.pendingRepo // empty' <<<"$meta")" = "" ]
  # somebody else's repository with that name exists now; the next run must leave it alone
  foreign='{"cieyhomelab/planer": {"private": true, "topics": [], "files": {}}}'
  control "{\"repos\": $foreign, \"create_fail\": {}, \"repo_fail\": {}}"
  run "$ROOT/bin/sw-create-repo" 7
  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = "WYNIK: REPO cieyhomelab/planer-2 proj-planer-2" ]
  [ "$(state | jq -c '.repos["cieyhomelab/planer"].topics')" = '[]' ]
}

@test "a name taken by somebody else is not left claimed after 500 (issue #39)" {
  control "{\"issues\": [$(idea 7 'Planer')], \"create_race\": {\"planer\": 500}, \"repo_fail\": {\"cieyhomelab/planer-2\": 503}}"
  run "$ROOT/bin/sw-create-repo" 7
  [ "$status" -eq 1 ]
  meta="$(state | jq -r '.issues[0].body' | sed -n 's/.*<!-- sw:meta \(.*\) -->/\1/p')"
  [ "$(jq -r '.pendingRepo // empty' <<<"$meta")" = "" ]
  control '{"create_race": {}, "repo_fail": {}}'
  run "$ROOT/bin/sw-create-repo" 7
  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = "WYNIK: REPO cieyhomelab/planer-2 proj-planer-2" ]
  [ "$(state | jq -c '.repos["cieyhomelab/planer"].topics')" = '[]' ]
}

@test "a claimed name that does not exist on GitHub is ignored and a new repository is created" {
  control "{\"issues\": [$(idea 7 'Planer' '{"pendingRepo":"planer"}')]}"
  run "$ROOT/bin/sw-create-repo" 7
  [ "${lines[-1]}" = "WYNIK: REPO cieyhomelab/planer proj-planer" ]
  [ "$(curl -fsS "$SW_CEZAR_URL/__requests" | jq '[.[] | select(.path == "/api/v1/projects/create")] | length')" -eq 1 ]
}

@test "a repository with the topic but a link to another issue is not adopted" {
  control "{\"issues\": [$(idea 7 'Planer')], \"repos\": $(seeded planer 70)}"
  run "$ROOT/bin/sw-create-repo" 7
  [ "${lines[-1]}" = "WYNIK: REPO cieyhomelab/planer-2 proj-planer-2" ]
}

@test "an adopted repository known to Cezar is not checked out again" {
  control "{\"issues\": [$(idea 7 'Planer')], \"repos\": $(seeded planer 7), \"projects\": [{\"id\": \"p9\", \"name\": \"planer\"}]}"
  run "$ROOT/bin/sw-create-repo" 7
  [ "${lines[-1]}" = "WYNIK: REPO cieyhomelab/planer p9" ]
  [ "$(curl -fsS "$SW_CEZAR_URL/__requests" | jq '[.[] | select(.path == "/api/v1/projects/checkout")] | length')" -eq 0 ]
}

@test "a repeated run after success does nothing" {
  control "{\"issues\": [$(idea 7 'Planer')]}"
  "$ROOT/bin/sw-create-repo" 7
  run "$ROOT/bin/sw-create-repo" 7
  [ "$status" -eq 0 ]
  [[ "$output" == "WYNIK: POMINIETO"* ]]
  [ "$(state | jq '.projects | length')" -eq 1 ]
}

@test "ideas that are not approved, already have a repository or are missing are skipped" {
  control "{\"issues\": [$(idea 1 'A' '{}' '["sw-pomysl","sw-w-ocenie"]'), $(idea 2 'B' '{"repo":"cieyhomelab/b"}')]}"
  for n in 1 2; do
    run "$ROOT/bin/sw-create-repo" "$n"
    [ "$status" -eq 0 ]
    [[ "$output" == "WYNIK: POMINIETO"* ]]
  done
  [ "$(state | jq '.projects | length')" -eq 0 ]
  run "$ROOT/bin/sw-create-repo" 99
  [ "$status" -eq 1 ]
  [[ "$output" == "STAN: BLAD "* ]]
}

@test "a title without letters falls back to a fixed name" {
  control "{\"issues\": [$(idea 7 '!!!')]}"
  run "$ROOT/bin/sw-create-repo" 7
  [ "${lines[-1]}" = "WYNIK: REPO cieyhomelab/aplikacja proj-aplikacja" ]
}
