#!/usr/bin/env bats
# E2E: the application repository of an approved idea (S4, steps 1 and 5). The
# gate decides "URUCHOM: SPEC <nr>", sw-create-repo does the rest, exactly as
# the VPS calls them, against mocked Cezar and GitHub APIs.

setup() {
  : "${MOCK_URL:?run through scripts/test-e2e.sh}"
  curl -fsS -X POST -d '{"reset": true}' "$MOCK_URL/__control" >/dev/null
  export SW_PUSH_URL="$MOCK_URL"
  home="${SW_HOME:-/work}"
  WORK="$(mktemp -d)"
  cd "$WORK" || return 1
}

teardown() { cd / && rm -rf "$WORK"; }

state() { curl -fsS -X POST -d '{}' "$MOCK_URL/__control"; }
control() { curl -fsS -X POST "$MOCK_URL/__control" -d "$1" >/dev/null; }
journal() { echo '{"number": 1, "state": "open", "title": "sw-dziennik", "labels": [{"name": "sw-dziennik"}]}'; }
approved() { # approved <nr> <title> [meta-json]
  jq -nc --argjson n "$1" --arg t "$2" --arg m "${3:-{\}}" '{number: $n, state: "open", title: $t,
    labels: [{name: "sw-pomysl"}, {name: "sw-zatwierdzony"}],
    body: ("## Problem i dla kogo\nx\n\n<!-- sw:meta " + $m + " -->")}'
}
gate() { run bash "$home/bin/sw-gate"; echo "$output" | grep '^URUCHOM:'; }
create() { run bash "$home/bin/sw-create-repo" "$1"; }

@test "S4 an approved idea without a repository gets URUCHOM: SPEC" {
  control "{\"issues\": [$(journal), $(approved 2 'Planer posiłków')]}"
  [ "$(gate)" = "URUCHOM: SPEC 2" ]
}

@test "S4 the repository is private, has a README with the link, the topic and maxParallel" {
  control "{\"issues\": [$(journal), $(approved 2 'Planer posiłków')]}"
  create 2
  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = "WYNIK: REPO cieyhomelab/planer-posilkow proj-planer-posilkow" ]
  s="$(state)"
  r='.repos["cieyhomelab/planer-posilkow"]'
  [ "$(jq "$r.private" <<<"$s")" = true ]
  [ "$(jq -c "$r.topics" <<<"$s")" = '["sw-projekt"]' ]
  [[ "$(jq -r "$r.files[\"README.md\"].content" <<<"$s" | base64 -d)" == *"https://github.com/cieyhomelab/sw-control/issues/2"* ]]
  [ "$(jq '.projects[0].maxParallel' <<<"$s")" = "$(jq .maxParallelAgents "$home/config/sw.json")" ]
}

@test "S4 the issue moves to sw-stan-specyfikacja with repo and projectId, and the gate stops asking" {
  control "{\"issues\": [$(journal), $(approved 2 'Planer posiłków' '{"approvedAt":"2026-10-26T00:00:00Z"}')]}"
  create 2
  [ "$status" -eq 0 ]
  issue="$(state | jq -c '.issues[] | select(.number == 2)')"
  [ "$(jq -c '[.labels[].name]' <<<"$issue")" = '["sw-pomysl","sw-stan-specyfikacja"]' ]
  meta="$(jq -r .body <<<"$issue" | sed -n 's/.*<!-- sw:meta \(.*\) -->/\1/p')"
  [ "$(jq -r .repo <<<"$meta")" = "cieyhomelab/planer-posilkow" ]
  [ "$(jq -r .projectId <<<"$meta")" = "proj-planer-posilkow" ]
  [ "$(jq -r .approvedAt <<<"$meta")" = "2026-10-26T00:00:00Z" ]
  [ "$(gate)" = "URUCHOM: NIC" ]
}

@test "S4 a taken repository name gets the suffix -2, then -3" {
  control "{\"issues\": [$(journal), $(approved 2 'Planer posiłków')]}"
  create 2
  [ "${lines[-1]}" = "WYNIK: REPO cieyhomelab/planer-posilkow proj-planer-posilkow" ]
  control "{\"issues\": [$(journal), $(approved 3 'Planer posiłków')]}"
  create 3
  [ "${lines[-1]}" = "WYNIK: REPO cieyhomelab/planer-posilkow-2 proj-planer-posilkow-2" ]
  control "{\"issues\": [$(journal), $(approved 4 'Planer posiłków')]}"
  create 4
  [ "${lines[-1]}" = "WYNIK: REPO cieyhomelab/planer-posilkow-3 proj-planer-posilkow-3" ]
}

@test "S4 a repository left by an interrupted run is adopted, not duplicated" {
  control "{\"issues\": [$(journal), $(approved 2 'Planer posiłków')]}"
  create 2
  # the run was interrupted before the issue was updated
  control "{\"issues\": [$(journal), $(approved 2 'Planer posiłków')]}"
  [ "$(gate)" = "URUCHOM: SPEC 2" ]
  create 2
  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = "WYNIK: REPO cieyhomelab/planer-posilkow proj-planer-posilkow" ]
  [ "$(state | jq '.repos | length')" -eq 1 ]
  [ "$(state | jq '.projects | length')" -eq 1 ]
}

@test "S4 the new project gets the sw-spec workflow and an autonomous sw-spec task for the idea" {
  control "{\"issues\": [$(journal), $(approved 2 'Planer posiłków')]}"
  create 2
  [ "$status" -eq 0 ]
  s="$(state)"
  [ "$(jq -c '[.runs[] | select(.workflow == "sw-spec") | {project, autonomous, task}]' <<<"$s")" \
    = '[{"project":"proj-planer-posilkow","autonomous":true,"task":"Specyfikacja aplikacji: cieyhomelab/sw-control#2"}]' ]
  [ "$(jq -r '.repos["cieyhomelab/planer-posilkow"].files[".ai/cezar/workflows/sw-spec.yml"].content' <<<"$s" | base64 -d)" \
    = "$(cat "$home/workflows/sw-spec.yml")" ]
  [ "$(jq -r '.repos["cieyhomelab/planer-posilkow"].files[".gitignore"].content' <<<"$s" | base64 -d)" = ".ai/sw-run/" ]
}

@test "S4 a repeated run does not start a second sw-spec task while the first one is alive" {
  control "{\"issues\": [$(journal), $(approved 2 'Planer posiłków')]}"
  create 2
  [ "$status" -eq 0 ]
  # the idea is back in the state of an interrupted run: approved, repository known to GitHub
  curl -fsS -X POST "$MOCK_URL/__control" -d "{\"issues\": [$(journal), $(approved 2 'Planer posiłków')]}" >/dev/null
  create 2
  [ "$status" -eq 0 ]
  [ "$(state | jq '[.runs[] | select(.workflow == "sw-spec")] | length')" -eq 1 ]
}

# The whole hourly cycle, as Cezar walks workflows/sw-sweep.yml: an approved idea must
# not stop at the gate decision (regression: "URUCHOM: SPEC" had no branch and the
# sweep ended in "done", so no repository and no sw-spec task were ever created).
sweep() { run python3 "$home/tests/tools/run_workflow.py" "$home/workflows/sw-sweep.yml"; }

@test "S4 the hourly sweep turns an approved idea into a repository and a sw-spec task" {
  control "{\"issues\": [$(journal), $(approved 2 'Planer posiłków')]}"
  sweep
  [ "$status" -eq 0 ]
  [[ "$output" == *"TRACE create-repo pass"* ]]
  [[ "$output" == *"END done success"* ]]
  s="$(state)"
  [ "$(jq '.repos["cieyhomelab/planer-posilkow"].private' <<<"$s")" = true ]
  [ "$(jq -c '[.issues[] | select(.number == 2) | .labels[].name]' <<<"$s")" = '["sw-pomysl","sw-stan-specyfikacja"]' ]
  [ "$(jq '[.runs[] | select(.workflow == "sw-spec" and .autonomous == true)] | length' <<<"$s")" -eq 1 ]
}

@test "S4 sw-create-repo without a number takes the approved idea the gate named" {
  control "{\"issues\": [$(journal), $(approved 3 'Drugi pomysł'), $(approved 2 'Planer posiłków')]}"
  [ "$(gate)" = "URUCHOM: SPEC 2" ]
  run bash "$home/bin/sw-create-repo"
  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = "WYNIK: REPO cieyhomelab/planer-posilkow proj-planer-posilkow" ]
}

@test "S4 sw-create-repo without a number and without an approved idea does nothing" {
  control "{\"issues\": [$(journal)]}"
  run bash "$home/bin/sw-create-repo"
  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = "WYNIK: POMINIETO brak zatwierdzonego pomyslu bez repozytorium" ]
}
