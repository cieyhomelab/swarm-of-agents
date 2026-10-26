#!/usr/bin/env bats
# E2E (S4, steps 3-4; S8 verdict rules): sw-pr-body and sw-merge spec as the
# sw-spec workflow runs them, in a VPS-like environment against the mock APIs.

setup() {
  : "${MOCK_URL:?run through scripts/test-e2e.sh}"
  curl -fsS -X POST -d '{"reset": true}' "$MOCK_URL/__control" >/dev/null
  curl -fsS -X POST "$MOCK_URL/__control" -d '{
    "pulls": {"cieyhomelab/app#3": {"head_sha": "abc123", "body": "Specyfikacja"}},
    "runs": [{"project": "proj", "id": "analityk", "modelIdentity": "anthropic/opus[1m]"}, {"project": "proj", "id": "recenzent", "modelIdentity": "anthropic/sonnet[1m]"},
             {"project": "proj", "id": "recenzent-opus", "modelIdentity": "anthropic/opus[1m]"}, {"project": "proj", "id": "bezp", "modelIdentity": "anthropic/haiku[1m]"}]}' >/dev/null
  BIN="${SW_HOME:-/work}/bin"
  WORK="$(mktemp -d)"
}

teardown() { rm -rf "$WORK"; }

pr() { curl -fsS "$MOCK_URL/github/repos/cieyhomelab/app/pulls/3"; }

merge() {
  run "$BIN/sw-merge" cieyhomelab/app 3 spec --projekt proj --sha "$sha" \
    --werdykt autor=gotowa@analityk --werdykt recenzent="$1"@"$2" --werdykt bezpieczenstwo="$3"@bezp
}

@test "S4: PR description gets the review verdict and the assumptions" {
  printf -- '- Założenie: język polski\n' > "$WORK/zalozenia.md"
  run "$BIN/sw-pr-body" cieyhomelab/app 3 "$WORK/zalozenia.md" \
    --werdykt recenzent=zatwierdzona@recenzent --werdykt bezpieczenstwo=pass@bezp
  [ "$status" -eq 0 ]
  [ "$output" = "WYNIK: ZAPISANO" ]
  body="$(pr | jq -r .body)"
  [[ "$body" == *"recenzent: zatwierdzona"* ]]
  [[ "$body" == *"Założenie: język polski"* ]]
}

@test "S4: approved review and passed security on other models merge the PR" {
  sha=abc123
  merge zatwierdzona recenzent pass
  [ "$status" -eq 0 ]
  [ "$output" = "WYNIK: ZMERGOWANY" ]
  [ "$(pr | jq .merged)" = "true" ]
}

@test "S4: review with remarks leaves the PR unmerged" {
  sha=abc123
  merge uwagi recenzent pass
  [ "$status" -eq 1 ]
  [ "${lines[-1]}" = "WYNIK: WARUNKI_NIESPELNIONE werdykt-recenzent" ]
  [ "$(pr | jq .merged)" = "false" ]
}

@test "S8: a review by the author's own model is not an approval" {
  sha=abc123
  merge zatwierdzona recenzent-opus pass
  [ "$status" -eq 1 ]
  [ "${lines[-1]}" = "WYNIK: WARUNKI_NIESPELNIONE model-recenzent" ]
  [ "$(pr | jq .merged)" = "false" ]
}

@test "S4: a push after the verdicts (other head SHA) blocks the merge" {
  sha=abc123
  curl -fsS -X POST "$MOCK_URL/__control" -d '{"pulls": {"cieyhomelab/app#3": {"head_sha": "def456", "body": "x"}}}' >/dev/null
  merge zatwierdzona recenzent pass
  [ "$status" -eq 1 ]
  [ "${lines[-1]}" = "WYNIK: WARUNKI_NIESPELNIONE sha" ]
  [ "$(pr | jq .merged)" = "false" ]
}

kod() {
  run "$BIN/sw-merge" cieyhomelab/app 3 kod --projekt proj --sha abc123 \
    --werdykt autor=gotowa@analityk --werdykt recenzent="$1"@"$2" --werdykt bezpieczenstwo="$3"@bezp
}
checks() { curl -fsS -X POST "$MOCK_URL/__control" -d "{\"check_runs\": {\"cieyhomelab/app@abc123\": $1}}" >/dev/null; }
GREEN='[{"name":"checks","status":"completed","conclusion":"success"},{"name":"e2e","status":"completed","conclusion":"success"}]'

@test "S8: approve, pass and green required check-runs merge a code PR" {
  checks "$GREEN"
  kod approve recenzent pass
  [ "$status" -eq 0 ]
  [ "$output" = "WYNIK: ZMERGOWANY" ]
  [ "$(pr | jq .merged)" = "true" ]
}

@test "S8: an unmet condition leaves the code PR unmerged" {
  checks "$GREEN"
  kod changes recenzent pass
  [ "$status" -eq 1 ]
  [ "${lines[-1]}" = "WYNIK: WARUNKI_NIESPELNIONE werdykt-recenzent" ]
  kod approve recenzent fail
  [ "$status" -eq 1 ]
  [ "$(pr | jq .merged)" = "false" ]
}

@test "S8: a code review by the author's own model is not an approval" {
  checks "$GREEN"
  kod approve recenzent-opus pass
  [ "$status" -eq 1 ]
  [ "${lines[-1]}" = "WYNIK: WARUNKI_NIESPELNIONE model-recenzent" ]
  [ "$(pr | jq .merged)" = "false" ]
}

@test "S8: a missing named check-run blocks the code PR" {
  checks '[{"name":"checks","status":"completed","conclusion":"success"}]'
  kod approve recenzent pass
  [ "$status" -eq 1 ]
  [ "${lines[-1]}" = "WYNIK: WARUNKI_NIESPELNIONE check-e2e" ]
  [ "$(pr | jq .merged)" = "false" ]
}

@test "S8: a repository without CI workflow is not merged" {
  kod approve recenzent pass
  [ "$status" -eq 1 ]
  [ "${lines[-1]}" = "WYNIK: WARUNKI_NIESPELNIONE check-checks,check-e2e" ]
  [ "$(pr | jq .merged)" = "false" ]
}
