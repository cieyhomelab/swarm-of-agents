#!/usr/bin/env bats
# Integration: sw-log, sw-notify and the cycle counters of sw-gate against the
# mock Cezar/GitHub/cezar-push API over real HTTP.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  WORK="$(mktemp -d)"
  python3 "$ROOT/tests/tools/mock_api.py" --port 0 --port-file "$WORK/port" &
  MOCK_PID=$!
  for _ in $(seq 1 50); do [ -s "$WORK/port" ] && break; sleep 0.1; done
  PORT="$(cat "$WORK/port")"
  export SW_CEZAR_URL="http://127.0.0.1:$PORT"
  export SW_PUSH_URL="http://127.0.0.1:$PORT"
  export FAKE_GH_API_URL="http://127.0.0.1:$PORT"
  export PATH="$ROOT/tests/fakes:$PATH"
  export CEZ_RUN_ID=me
  printf 'test-token\n' > "$WORK/token"
  export SW_PUSH_TOKEN_FILE="$WORK/token"
  unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN ANTHROPIC_BASE_URL \
        CLAUDE_CODE_USE_BEDROCK CLAUDE_CODE_USE_VERTEX CLAUDE_CODE_USE_FOUNDRY
}

teardown() {
  kill "$MOCK_PID" 2>/dev/null || true
  rm -rf "$WORK"
}

control() { curl -fsS -X POST -d "$1" "$SW_CEZAR_URL/__control" >/dev/null; }
state() { curl -fsS -X POST -d '{}' "$SW_CEZAR_URL/__control"; }
pushes() { curl -fsS "$SW_CEZAR_URL/__requests" | jq -c '[.[] | select(.method == "POST" and .path == "/m/push/gate")]'; }
journal_bodies() { state | jq -c '[.comments["1"][]?.body]'; }

# journal <body> <count> — the journal issue (#1) with <count> comments of <body>.
journal() {
  control "$(jq -nc --arg b "$1" --argjson n "$2" '
    {issues: [{number: 1, state: "open", title: "sw-dziennik", labels: [{name: "sw-dziennik"}]}],
     comments: {"1": [range(0; $n) | {body: $b, created_at: "2026-01-01T00:00:00Z"}]}}')"
}

@test "sw-log writes exactly one journal comment and prints ZAPISANO" {
  journal x 0
  run "$ROOT/bin/sw-log" "odrzucona próba: duplikat"
  [ "$status" -eq 0 ]
  [ "$output" = "WYNIK: ZAPISANO" ]
  [ "$(journal_bodies)" = '["odrzucona próba: duplikat"]' ]
}

@test "sw-log masks e-mail addresses and tokens" {
  journal x 0
  run "$ROOT/bin/sw-log" "wlasciciel jan@example.com token ghp_abcDEF123 Bearer abc.def-1"
  [ "$status" -eq 0 ]
  body="$(state | jq -r '.comments["1"][0].body')"
  [[ "$body" != *"jan@example.com"* ]]
  [[ "$body" != *"ghp_abcDEF123"* ]]
  [[ "$body" != *"abc.def-1"* ]]
}

@test "sw-log fails without a journal issue and without text" {
  run "$ROOT/bin/sw-log" "wpis"
  [ "$status" -eq 1 ]
  [[ "$output" != *"WYNIK: ZAPISANO"* ]]
  journal x 0
  run "$ROOT/bin/sw-log"
  [ "$status" -ne 0 ]
}

@test "sw-notify sends only the five fields with the token header and no Origin" {
  long="$(printf 'x%.0s' $(seq 1 150))"
  run "$ROOT/bin/sw-notify" blocked cieyhomelab/sw-control 1 "$long" https://github.com/cieyhomelab/sw-control/issues/1
  [ "$status" -eq 0 ]
  [ "$output" = "WYNIK: WYSLANO" ]
  req="$(pushes | jq -c '.[0]')"
  [ "$(jq -c '.body | keys' <<<"$req")" = '["gate","number","repo","title","url"]' ]
  [ "$(jq -r '.body.gate' <<<"$req")" = blocked ]
  [ "$(jq -r '.body.number' <<<"$req")" = 1 ]
  [ "$(jq -r '.body.title | length' <<<"$req")" -eq 100 ]
  [ "$(jq -r '.headers["x-cezar-push-token"]' <<<"$req")" = test-token ]
  [ "$(jq '.headers | has("origin") or has("x-forwarded-for")' <<<"$req")" = false ]
  [[ "$(jq -c '.body' <<<"$req")" != *"test-token"* ]]
}

@test "sw-notify spec is accepted and a missing token file is skipped" {
  run "$ROOT/bin/sw-notify" spec cieyhomelab/app 4 "Specyfikacja gotowa" https://github.com/cieyhomelab/app/pull/4
  [ "$output" = "WYNIK: WYSLANO" ]
  SW_PUSH_TOKEN_FILE="$WORK/none" run "$ROOT/bin/sw-notify" spec cieyhomelab/app 4 t https://github.com/cieyhomelab/app/pull/4
  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = "WYNIK: POMINIETO" ]
  [ "$(pushes | jq length)" -eq 1 ]
}

@test "sw-notify reports a refused notification and rejects bad arguments" {
  control '{"push_token": "other"}'
  run "$ROOT/bin/sw-notify" blocked cieyhomelab/app 4 t https://github.com/cieyhomelab/app/pull/4
  [ "$status" -eq 1 ]
  [ "${lines[-1]}" = "WYNIK: POMINIETO" ]
  [[ "$output" != *"test-token"* ]]
  run "$ROOT/bin/sw-notify" deployed cieyhomelab/app 4 t https://github.com/cieyhomelab/app/pull/4
  [ "$status" -ne 0 ]
  run "$ROOT/bin/sw-notify" blocked cieyhomelab/app 4 t http://evil.example/x
  [ "$status" -ne 0 ]
  run "$ROOT/bin/sw-notify" blocked cieyhomelab/app abc t https://github.com/cieyhomelab/app/pull/4
  [ "$status" -ne 0 ]
}

@test "24 consecutive 'brak pomysłu' entries give exactly one blocked notification" {
  journal "brak pomysłu" 23
  run "$ROOT/bin/sw-gate"
  [[ "$output" == *"URUCHOM: GENERATOR"* ]]
  [ "$(pushes | jq length)" -eq 0 ]
  journal "brak pomysłu" 24
  run "$ROOT/bin/sw-gate"
  [[ "$output" == *"URUCHOM: GENERATOR"* ]]
  [ "$(pushes | jq length)" -eq 1 ]
  [ "$(pushes | jq -r '.[0].body.gate')" = blocked ]
  [ "$(pushes | jq -r '.[0].body.url')" = "https://github.com/cieyhomelab/sw-control/issues/1" ]
  [ "$(journal_bodies | jq -r '.[-1]')" = "powiadomienie: brak pomysłu" ]
  # the 25th cycle and a repeated gate run stay silent
  run "$ROOT/bin/sw-log" "brak pomysłu"
  run "$ROOT/bin/sw-gate"
  run "$ROOT/bin/sw-gate"
  [ "$(pushes | jq length)" -eq 1 ]
}

@test "entries from before the newest card do not count" {
  journal "brak pomysłu" 30
  control '{"issues": [
    {"number": 1, "state": "open", "title": "sw-dziennik", "labels": [{"name": "sw-dziennik"}]},
    {"number": 2, "state": "closed", "created_at": "2026-02-01T00:00:00Z", "labels": [{"name": "sw-pomysl"}, {"name": "sw-odrzucony"}]}]}'
  run "$ROOT/bin/sw-gate"
  [[ "$output" == *"URUCHOM: GENERATOR"* ]]
  [ "$(pushes | jq length)" -eq 0 ]
}

@test "no notification while a project is active" {
  journal "brak pomysłu" 30
  control '{"issues": [
    {"number": 1, "state": "open", "title": "sw-dziennik", "labels": [{"name": "sw-dziennik"}]},
    {"number": 2, "state": "open", "body": "karta", "labels": [{"name": "sw-pomysl"}, {"name": "sw-stan-implementacja"}]}]}'
  run "$ROOT/bin/sw-gate"
  [[ "$output" == *"URUCHOM: NIC"* ]]
  [ "$(pushes | jq length)" -eq 0 ]
}

@test "the gate works without a journal issue" {
  run "$ROOT/bin/sw-gate"
  [ "$status" -eq 0 ]
  [[ "$output" == *"URUCHOM: GENERATOR"* ]]
}

@test "24 consecutive STAN: BLAD cycles give one blocked notification" {
  journal "STAN: BLAD brak Cezara" 22
  control '{"health_status": 503}'
  run "$ROOT/bin/sw-gate"
  [ "$status" -eq 1 ]
  [[ "$output" == *"URUCHOM: NIC"* ]]
  [[ "$(journal_bodies | jq -r '.[22]')" == "STAN: BLAD"* ]]
  [ "$(state | jq '.comments["1"] | length')" -eq 23 ]
  [ "$(pushes | jq length)" -eq 0 ]
  run "$ROOT/bin/sw-gate"
  [ "$(pushes | jq length)" -eq 1 ]
  [ "$(pushes | jq -r '.[0].body.gate')" = blocked ]
  [ "$(pushes | jq -r '.[0].body.url')" = "https://github.com/cieyhomelab/sw-control/issues/1" ]
  run "$ROOT/bin/sw-gate"
  run "$ROOT/bin/sw-gate"
  [ "$(pushes | jq length)" -eq 1 ]
}

@test "a healthy cycle ends the failure streak" {
  journal "STAN: BLAD brak Cezara" 23
  run "$ROOT/bin/sw-gate"
  [ "$status" -eq 0 ]
  [ "$(journal_bodies | jq -r '.[-1]')" = "STAN: OK" ]
  control '{"health_status": 503}'
  run "$ROOT/bin/sw-gate"
  [ "$(pushes | jq length)" -eq 0 ]
}

@test "nothing written to the journal or sent as a notification carries a token" {
  journal "brak pomysłu" 24
  run "$ROOT/bin/sw-gate"
  [ "$(pushes | jq length)" -eq 1 ]
  [[ "$(pushes | jq -c '.[0].body')" != *"test-token"* ]]
  [[ "$(journal_bodies)" != *"test-token"* ]]
}
