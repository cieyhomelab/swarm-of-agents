#!/usr/bin/env bats
# E2E: sw-log, sw-notify and the cycle counters of sw-gate exactly as the
# workflow calls them on the VPS, against mocked Cezar, GitHub and cezar-push.

setup() {
  : "${MOCK_URL:?run through scripts/test-e2e.sh}"
  curl -fsS -X POST -d '{"reset": true}' "$MOCK_URL/__control" >/dev/null
  export SW_PUSH_URL="$MOCK_URL"
  SW_PUSH_TOKEN_FILE="$(mktemp)"
  export SW_PUSH_TOKEN_FILE
  printf 'test-token\n' > "$SW_PUSH_TOKEN_FILE"
  bin="${SW_HOME:-/work}/bin"
}

teardown() { rm -f "$SW_PUSH_TOKEN_FILE"; }

state() { curl -fsS -X POST -d '{}' "$MOCK_URL/__control"; }
pushes() { curl -fsS "$MOCK_URL/__requests" | jq -c '[.[] | select(.method == "POST" and .path == "/m/push/gate")]'; }

journal() {
  curl -fsS -X POST "$MOCK_URL/__control" -d "$(jq -nc --arg b "$1" --argjson n "$2" '
    {issues: [{number: 1, state: "open", title: "sw-dziennik", labels: [{name: "sw-dziennik"}]}],
     comments: {"1": [range(0; $n) | {body: $b, created_at: "2026-01-01T00:00:00Z"}]}}')" >/dev/null
}

@test "S1 sw-log adds one journal comment" {
  journal x 0
  run "$bin/sw-log" "brak pomysłu"
  [ "$status" -eq 0 ]
  [ "$output" = "WYNIK: ZAPISANO" ]
  [ "$(state | jq -c '[.comments["1"][].body]')" = '["brak pomysłu"]' ]
}

@test "S1 sw-notify blocked sends only the allowed fields with the token header" {
  run "$bin/sw-notify" blocked cieyhomelab/sw-control 1 "Brak pomysłów" https://github.com/cieyhomelab/sw-control/issues/1
  [ "$output" = "WYNIK: WYSLANO" ]
  req="$(pushes | jq -c '.[0]')"
  [ "$(jq -c '.body | keys' <<<"$req")" = '["gate","number","repo","title","url"]' ]
  [ "$(jq -r '.headers["x-cezar-push-token"]' <<<"$req")" = test-token ]
  [ "$(jq '.headers | has("origin") or has("x-forwarded-for")' <<<"$req")" = false ]
}

@test "S1 24 cycles without an idea give one notification and the 25th none" {
  journal "brak pomysłu" 24
  run "$bin/sw-gate"
  [ "$status" -eq 0 ]
  [[ "$output" == *"URUCHOM: GENERATOR"* ]]
  [ "$(pushes | jq length)" -eq 1 ]
  [ "$(pushes | jq -r '.[0].body.url')" = "https://github.com/cieyhomelab/sw-control/issues/1" ]
  "$bin/sw-log" "brak pomysłu" >/dev/null
  run "$bin/sw-gate"
  [[ "$output" == *"URUCHOM: GENERATOR"* ]]
  [ "$(pushes | jq length)" -eq 1 ]
}

@test "S1 24 cycles with STAN: BLAD give one notification" {
  journal "STAN: BLAD brak Cezara" 23
  curl -fsS -X POST -d '{"health_status": 503}' "$MOCK_URL/__control" >/dev/null
  run "$bin/sw-gate"
  [ "$status" -eq 1 ]
  [[ "$output" == *"STAN: BLAD"* ]]
  [ "$(pushes | jq length)" -eq 1 ]
  run "$bin/sw-gate"
  [ "$(pushes | jq length)" -eq 1 ]
}

@test "S1 journal entries and notifications carry no personal data or tokens" {
  journal x 0
  "$bin/sw-log" "wlasciciel jan@example.com ghp_secret123" >/dev/null
  "$bin/sw-notify" blocked cieyhomelab/sw-control 1 "kontakt jan@example.com" https://github.com/cieyhomelab/sw-control/issues/1 >/dev/null
  [[ "$(state | jq -c '.comments')" != *"jan@example.com"* ]]
  [[ "$(state | jq -c '.comments')" != *"ghp_secret123"* ]]
  [[ "$(pushes | jq -c '.[0].body')" != *"jan@example.com"* ]]
  [[ "$(pushes | jq -c '.[0].body')" != *"test-token"* ]]
}
