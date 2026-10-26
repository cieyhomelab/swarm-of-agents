#!/usr/bin/env bats
# E2E (S4, "Przekazanie łańcuchowi sh-*", stage 1 step 7): sw-handover-sh as the sw-spec
# workflow runs it, then the gate of the next cycle, in a VPS-like environment against
# the mock APIs.

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
project() { # project <nr> — an idea in sw-stan-specyfikacja with a repository
  jq -nc --argjson n "$1" '{number: $n, state: "open", title: "Planer",
    labels: [{name: "sw-pomysl"}, {name: "sw-stan-specyfikacja"}],
    body: "## Problem i dla kogo\nx\n\n<!-- sw:meta {\"repo\":\"cieyhomelab/app\",\"projectId\":\"proj-app\"} -->"}'
}
merged_spec() { echo '"pulls": {"cieyhomelab/app#3": {"head_sha": "abc", "branch": "spec", "merged": true}}'; }
gate() { run bash "$home/bin/sw-gate"; echo "$output" | grep '^URUCHOM:'; }
handover() { run bash "$home/bin/sw-handover-sh" "$1"; }

@test "S4 a merged specification starts the sh-start task and prints WYNIK: PRZEKAZANY" {
  control "{\"issues\": [$(journal), $(project 2)], $(merged_spec)}"
  handover 2
  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = "WYNIK: PRZEKAZANY run-1" ]
  run1="$(state | jq -c '.runs[0]')"
  [ "$(jq -r .project <<<"$run1")" = proj-app ]
  [[ "$(jq -r .task <<<"$run1")" == *"skill sh-start"* ]]
  [ "$(jq -r .autonomous <<<"$run1")" = true ]
}

@test "S4 the idea gets sw-spec-gotowa and is closed, the next cycle returns GENERATOR" {
  control "{\"issues\": [$(journal), $(project 2)], $(merged_spec)}"
  [ "$(gate)" = "URUCHOM: NIC" ]
  handover 2
  [ "$status" -eq 0 ]
  issue="$(state | jq -c '.issues[] | select(.number == 2)')"
  [ "$(jq -r .state <<<"$issue")" = closed ]
  jq -e '[.labels[].name] | index("sw-spec-gotowa")' <<<"$issue" >/dev/null
  [ "$(gate)" = "URUCHOM: GENERATOR" ]
}

@test "S4 an unmerged specification is not handed over" {
  control "{\"issues\": [$(journal), $(project 2)], \"pulls\": {\"cieyhomelab/app#3\": {\"head_sha\": \"abc\", \"branch\": \"spec\"}}}"
  handover 2
  [[ "${lines[-1]}" == "WYNIK: POMINIETO "* ]]
  [ "$(state | jq '.runs | length')" = 0 ]
  [ "$(gate)" = "URUCHOM: NIC" ]
}

@test "S4 the gate skips a repository that has the delivery workflow of the other chain" {
  control "{\"issues\": [$(journal), $(project 2)], \"repo_files\": [\"cieyhomelab/app/.ai/cezar/workflows/sh-delivery.yml\"]}"
  [ "$(gate)" = "URUCHOM: GENERATOR" ]
}

@test "S4 only the handover script (and the gate that recognises the chain) names sh-*" {
  run bash "$home/tests/tools/check-names.sh"
  [ "$status" -eq 0 ]
  grep -q 'sh-start' "$home/bin/sw-handover-sh"
  run grep -rlE 'sh-start' "$home/bin" "$home/workflows" "$home/skills" "$home/config"
  [ "$output" = "$home/bin/sw-handover-sh" ]
}
