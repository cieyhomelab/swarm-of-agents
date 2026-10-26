#!/usr/bin/env bats
# E2E: sw-start exactly as the owner runs it on the VPS (fresh install, then a
# repeat), against mocked Cezar and GitHub APIs.

setup() {
  : "${MOCK_URL:?run through scripts/test-e2e.sh}"
  curl -fsS -X POST -d '{"reset": true}' "$MOCK_URL/__control" >/dev/null
  export SW_CEZ="${SW_HOME:-/work}/tests/fakes/cez"
}

state() { curl -fsS -X POST -d '{}' "$MOCK_URL/__control"; }

@test "S1 fresh start creates the private control repository fully configured" {
  curl -fsS -X POST -d '{"control_private": null}' "$MOCK_URL/__control" >/dev/null
  run "${SW_HOME:-/work}"/bin/sw-start
  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = "STAN: OK" ]
  s="$(state)"
  [ "$(jq '.control_private' <<<"$s")" = "true" ]
  [ "$(jq '.labels | length' <<<"$s")" = "$(jq '.system | length' "${SW_HOME:-/work}"/config/labels.json)" ]
  [ "$(jq '.contents | has(".ai/cezar/workflows/sw-sweep.yml")' <<<"$s")" = "true" ]
  [ "$(jq '.contents | has(".ai/cezar/workflows/sw-ocena.yml")' <<<"$s")" = "true" ]
  [ "$(jq '[.issues[] | select(.title == "sw-dziennik")] | length' <<<"$s")" -eq 1 ]
}

@test "S1 repeated start duplicates nothing and leaves the other chain's automations alone" {
  run "${SW_HOME:-/work}"/bin/sw-start
  [ "$status" -eq 0 ]
  first="$(state)"
  run "${SW_HOME:-/work}"/bin/sw-start
  [ "$status" -eq 0 ]
  second="$(state)"
  [ "$(jq -c '[.labels, .issues]' <<<"$first")" = "$(jq -c '[.labels, .issues]' <<<"$second")" ]
  [ "$(jq '[.automations[] | select(.name == "sw: przegląd co godzinę")] | length' <<<"$second")" -eq 1 ]
  [ "$(jq -c '[.automations[] | select(.name | startswith("sh: "))]' <<<"$first")" = "$(jq -c '[.automations[] | select(.name | startswith("sh: "))]' <<<"$second")" ]
}
