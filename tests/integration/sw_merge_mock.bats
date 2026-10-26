#!/usr/bin/env bats
# Integration: bin/sw-merge and bin/sw-pr-body against the mock Cezar/GitHub API.

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
  control '{"pulls": {"o/app#7": {"head_sha": "sha1", "body": "Opis PR"}},
            "runs": [{"project": "p1", "id": "author", "modelIdentity": "anthropic/opus[1m]"}, {"project": "p1", "id": "rev", "modelIdentity": "anthropic/sonnet[1m]"},
                     {"project": "p1", "id": "sec", "modelIdentity": "anthropic/haiku[1m]"}, {"project": "p1", "id": "revopus", "modelIdentity": "claude-opus-4-5"}, {"project": "p1", "id": "steprev", "steps": [{"modelIdentity": "anthropic/sonnet"}]}, {"project": "p1", "id": "oldfield", "model": "sonnet"}]}'
}

teardown() {
  kill "$MOCK_PID" 2>/dev/null || true
  rm -rf "$WORK"
}

control() { curl -fsS -X POST -d "$1" "$SW_CEZAR_URL/__control" >/dev/null; }
pull_state() { curl -fsS "$SW_CEZAR_URL/github/repos/o/app/pulls/7"; }
merge() {
  run "$ROOT/bin/sw-merge" o/app 7 spec --projekt p1 "$@"
}

@test "approved review and passed security on other models merge the PR" {
  merge --sha sha1 --werdykt autor=gotowa@author --werdykt recenzent=zatwierdzona@rev --werdykt bezpieczenstwo=pass@sec
  [ "$status" -eq 0 ]
  [ "$output" = "WYNIK: ZMERGOWANY" ]
  [ "$(pull_state | jq .merged)" = "true" ]
}

@test "verdict uwagi: not merged" {
  merge --sha sha1 --werdykt autor=gotowa@author --werdykt recenzent=uwagi@rev --werdykt bezpieczenstwo=pass@sec
  [ "$status" -eq 1 ]
  [ "${lines[-1]}" = "WYNIK: WARUNKI_NIESPELNIONE werdykt-recenzent" ]
  [ "$(pull_state | jq .merged)" = "false" ]
}

@test "security fail: not merged" {
  merge --sha sha1 --werdykt autor=gotowa@author --werdykt recenzent=zatwierdzona@rev --werdykt bezpieczenstwo=fail@sec
  [ "$status" -eq 1 ]
  [ "${lines[-1]}" = "WYNIK: WARUNKI_NIESPELNIONE werdykt-bezpieczenstwo" ]
}

@test "reviewer on the author's model: not merged" {
  merge --sha sha1 --werdykt autor=gotowa@author --werdykt recenzent=zatwierdzona@revopus --werdykt bezpieczenstwo=pass@sec
  [ "$status" -eq 1 ]
  [ "${lines[-1]}" = "WYNIK: WARUNKI_NIESPELNIONE model-recenzent" ]
  [ "$(pull_state | jq .merged)" = "false" ]
}

@test "model identity taken from the step when the record lacks it" {
  merge --sha sha1 --werdykt autor=gotowa@author --werdykt recenzent=zatwierdzona@steprev --werdykt bezpieczenstwo=pass@sec
  [ "$status" -eq 0 ]
}

@test "raw model field without modelIdentity: model unknown, not merged" {
  merge --sha sha1 --werdykt autor=gotowa@author --werdykt recenzent=zatwierdzona@oldfield --werdykt bezpieczenstwo=pass@sec
  [ "$status" -eq 1 ]
  [ "${lines[-1]}" = "WYNIK: WARUNKI_NIESPELNIONE model-recenzent" ]
}

@test "run record missing in Cezar: model unknown, not merged" {
  merge --sha sha1 --werdykt autor=gotowa@author --werdykt recenzent=zatwierdzona@nope --werdykt bezpieczenstwo=pass@sec
  [ "$status" -eq 1 ]
  [ "${lines[-1]}" = "WYNIK: WARUNKI_NIESPELNIONE model-recenzent" ]
}

@test "push after the verdicts (other head SHA): merge blocked" {
  control '{"pulls": {"o/app#7": {"head_sha": "sha2", "body": "x"}}}'
  merge --sha sha1 --werdykt autor=gotowa@author --werdykt recenzent=zatwierdzona@rev --werdykt bezpieczenstwo=pass@sec
  [ "$status" -eq 1 ]
  [ "${lines[-1]}" = "WYNIK: WARUNKI_NIESPELNIONE sha" ]
  [ "$(pull_state | jq .merged)" = "false" ]
}

@test "a blocked merge never sends the merge request" {
  merge --sha sha1 --werdykt autor=gotowa@author --werdykt recenzent=uwagi@rev --werdykt bezpieczenstwo=pass@sec
  [ "$(curl -fsS "$SW_CEZAR_URL/__requests" | jq '[.[] | select(.method == "PUT")] | length')" -eq 0 ]
}

kod() { run "$ROOT/bin/sw-merge" o/app 7 kod --projekt p1 "$@"; }
green() {
  control '{"check_runs": {"o/app@sha1": [{"name": "checks", "status": "completed", "conclusion": "success"},
                                         {"name": "e2e", "status": "completed", "conclusion": "success"}]}}'
}
APPROVED=(--sha sha1 --werdykt autor=gotowa@author --werdykt recenzent=approve@rev --werdykt bezpieczenstwo=pass@sec)

@test "kod: approve, pass and green required check-runs merge the PR" {
  green
  kod "${APPROVED[@]}"
  [ "$status" -eq 0 ]
  [ "$output" = "WYNIK: ZMERGOWANY" ]
  [ "$(pull_state | jq .merged)" = "true" ]
  [ "$(curl -fsS "$SW_CEZAR_URL/__requests" | jq '[.[] | select(.path | test("/commits/sha1/check-runs"))] | length')" -ge 1 ]
}

@test "kod: a missing named check-run blocks the merge" {
  control '{"check_runs": {"o/app@sha1": [{"name": "checks", "status": "completed", "conclusion": "success"}]}}'
  kod "${APPROVED[@]}"
  [ "$status" -eq 1 ]
  [ "${lines[-1]}" = "WYNIK: WARUNKI_NIESPELNIONE check-e2e" ]
  [ "$(pull_state | jq .merged)" = "false" ]
}

@test "kod: a failed check-run blocks the merge" {
  control '{"check_runs": {"o/app@sha1": [{"name": "checks", "status": "completed", "conclusion": "failure"},
                                         {"name": "e2e", "status": "completed", "conclusion": "success"}]}}'
  kod "${APPROVED[@]}"
  [ "$status" -eq 1 ]
  [ "${lines[-1]}" = "WYNIK: WARUNKI_NIESPELNIONE check-checks" ]
}

@test "kod: a repository without CI (no check-runs) is not merged" {
  kod "${APPROVED[@]}"
  [ "$status" -eq 1 ]
  [ "${lines[-1]}" = "WYNIK: WARUNKI_NIESPELNIONE check-checks,check-e2e" ]
  [ "$(curl -fsS "$SW_CEZAR_URL/__requests" | jq '[.[] | select(.method == "PUT")] | length')" -eq 0 ]
}

@test "kod: check-runs of another SHA do not count" {
  control '{"check_runs": {"o/app@old": [{"name": "checks", "status": "completed", "conclusion": "success"},
                                        {"name": "e2e", "status": "completed", "conclusion": "success"}]}}'
  kod "${APPROVED[@]}"
  [ "$status" -eq 1 ]
}

@test "kod: reviewer on the author's model is not merged even with green checks" {
  green
  kod --sha sha1 --werdykt autor=gotowa@author --werdykt recenzent=approve@revopus --werdykt bezpieczenstwo=pass@sec
  [ "$status" -eq 1 ]
  [ "${lines[-1]}" = "WYNIK: WARUNKI_NIESPELNIONE model-recenzent" ]
}

@test "kod: a push after the verdicts blocks the merge" {
  green
  control '{"pulls": {"o/app#7": {"head_sha": "sha2", "body": "x"}}}'
  kod "${APPROVED[@]}"
  [ "$status" -eq 1 ]
  [ "${lines[-1]}" = "WYNIK: WARUNKI_NIESPELNIONE sha" ]
}

@test "sw-pr-body writes verdicts and assumptions, idempotently" {
  printf -- '- Założenie A\n- Założenie B\n' > "$WORK/zalozenia.md"
  for _ in 1 2; do
    run "$ROOT/bin/sw-pr-body" o/app 7 "$WORK/zalozenia.md" --werdykt recenzent=zatwierdzona@rev --werdykt bezpieczenstwo=pass@sec
    [ "$status" -eq 0 ]
    [ "$output" = "WYNIK: ZAPISANO" ]
  done
  body="$(pull_state | jq -r .body)"
  [[ "$body" == "Opis PR"* ]]
  [[ "$body" == *"recenzent: zatwierdzona"* ]]
  [[ "$body" == *"bezpieczenstwo: pass"* ]]
  [[ "$body" == *"Założenie B"* ]]
  [ "$(grep -c 'sw-werdykty -->' <<<"$body")" -eq 2 ]
}

@test "sw-pr-body fails without the assumptions file" {
  run "$ROOT/bin/sw-pr-body" o/app 7 "$WORK/brak.md" --werdykt recenzent=zatwierdzona@rev
  [ "$status" -eq 1 ]
  [[ "$output" == *"STAN: BLAD"* ]]
}
