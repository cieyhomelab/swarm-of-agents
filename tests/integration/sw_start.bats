#!/usr/bin/env bats
# Integration: bin/sw-start against the mock Cezar/GitHub API over real HTTP,
# with the fake gh and fake cez CLIs.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  WORK="$(mktemp -d)"
  python3 "$ROOT/tests/tools/mock_api.py" --port 0 --port-file "$WORK/port" &
  MOCK_PID=$!
  for _ in $(seq 1 50); do [ -s "$WORK/port" ] && break; sleep 0.1; done
  PORT="$(cat "$WORK/port")"
  export SW_CEZAR_URL="http://127.0.0.1:$PORT"
  export FAKE_GH_API_URL="http://127.0.0.1:$PORT"
  export SW_CEZ="$ROOT/tests/fakes/cez"
  export PATH="$ROOT/tests/fakes:$PATH"
}

teardown() {
  kill "$MOCK_PID" 2>/dev/null || true
  rm -rf "$WORK"
}

control() { curl -fsS -X POST -d "$1" "$SW_CEZAR_URL/__control" >/dev/null; }
requests() { curl -fsS "$SW_CEZAR_URL/__requests"; }
state() { curl -fsS -X POST -d '{}' "$SW_CEZAR_URL/__control"; }

@test "missing sw-control is created private with labels, workflow and journal issue" {
  control '{"control_private": null}'
  run "$ROOT/bin/sw-start"
  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = "STAN: OK" ]
  s="$(state)"
  [ "$(jq '.control_private' <<<"$s")" = "true" ]
  expected="$(jq '.system | sort' "$ROOT/config/labels.json")"
  [ "$(jq '[.labels[].name] | sort' <<<"$s")" = "$expected" ]
  [ "$(jq -r '.contents[".ai/cezar/workflows/sw-sweep.yml"].content' <<<"$s" | base64 -d)" = "$(cat "$ROOT/workflows/sw-sweep.yml")" ]
  [ "$(jq -r '.contents[".ai/cezar/workflows/sw-ocena.yml"].content' <<<"$s" | base64 -d)" = "$(cat "$ROOT/workflows/sw-ocena.yml")" ]
  [ "$(jq '[.issues[] | select(.title == "sw-dziennik")] | length' <<<"$s")" -eq 1 ]
  [ "$(jq '[.automations[] | select(.name == "sw: przegląd co godzinę" and .enabled)] | length' <<<"$s")" -eq 1 ]
}

@test "second run duplicates nothing and updates the automation by name" {
  control '{"control_private": null}'
  run "$ROOT/bin/sw-start"
  [ "$status" -eq 0 ]
  before="$(state)"
  run "$ROOT/bin/sw-start"
  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = "STAN: OK" ]
  after="$(state)"
  [ "$(jq '.labels | length' <<<"$after")" = "$(jq '.labels | length' <<<"$before")" ]
  [ "$(jq '.issues | length' <<<"$after")" -eq 1 ]
  [ "$(jq '[.automations[] | select(.name == "sw: przegląd co godzinę")] | length' <<<"$after")" -eq 1 ]
  [ "$(jq '.automations | length' <<<"$after")" = "$(jq '.automations | length' <<<"$before")" ]
  # No repository creation, no file write the second time (the first run wrote two workflow copies).
  second="$(requests | jq '[.[] | select(.path == "/api/v1/projects/create")] | length')"
  [ "$second" -eq 1 ]
  [ "$(requests | jq '[.[] | select(.method == "PUT")] | length')" -eq 2 ]
}

@test "existing sw-control is not recreated" {
  run "$ROOT/bin/sw-start"
  [ "$status" -eq 0 ]
  [ "$(requests | jq '[.[] | select(.path == "/api/v1/projects/create")] | length')" -eq 0 ]
}

@test "automations of the other agent chain get no create or update" {
  run "$ROOT/bin/sw-start"
  [ "$status" -eq 0 ]
  ids="$(state | jq -r '.automations[] | select(.name | startswith("sh: ")) | .id')"
  [ -n "$ids" ]
  writes="$(requests | jq -r '.[] | select(.method == "POST" and (.path | startswith("/cez/automations"))) | "\(.path) \(.body.name // "")"')"
  for id in $ids; do
    [[ "$writes" != *"/cez/automations/$id"* ]]
  done
  [[ "$writes" != *"sh: "* ]]
  [ "$(state | jq '[.automations[] | select(.name | startswith("sh: "))] | length')" -eq 2 ]
}

@test "public sw-control stops the setup" {
  control '{"control_private": false}'
  run "$ROOT/bin/sw-start"
  [ "$status" -eq 1 ]
  [[ "$output" == *"STAN: BLAD"*"nie jest prywatne"* ]]
}

@test "logged-out gh stops the setup" {
  control '{"github_user": null}'
  run "$ROOT/bin/sw-start"
  [ "$status" -eq 1 ]
  [[ "$output" == *"gh nie jest zalogowany"* ]]
}

@test "automation is installed in the sw-control project, not in the caller's" {
  export CEZ_PROJECT_ID=swarm-of-agents
  control '{"control_private": null}'
  run "$ROOT/bin/sw-start"
  [ "$status" -eq 0 ]
  s="$(state)"
  [ "$(jq -r '.automations[] | select(.name == "sw: przegląd co godzinę") | .project' <<<"$s")" = "proj-sw-control" ]
  [ "$(jq '[.automations[] | select(.project == "swarm-of-agents")] | length' <<<"$s")" -eq 2 ]
  [ "$(requests | jq '[.[] | select(.path | startswith("/cez/p/swarm-of-agents/")) | select(.method == "POST")] | length')" -eq 0 ]
}

@test "unregistered sw-control project stops the setup" {
  control '{"hide_project": true}'
  run "$ROOT/bin/sw-start"
  [ "$status" -eq 1 ]
  [[ "$output" == *"STAN: BLAD"*"nie jest zarejestrowany"* ]]
}
