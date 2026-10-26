#!/usr/bin/env bats
# Integration: bin/sw-spec-pause against the mock GitHub and cezar-push APIs.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  WORK="$(mktemp -d)"
  python3 "$ROOT/tests/tools/mock_api.py" --port 0 --port-file "$WORK/port" &
  MOCK_PID=$!
  for _ in $(seq 1 50); do [ -s "$WORK/port" ] && break; sleep 0.1; done
  PORT="$(cat "$WORK/port")"
  export FAKE_GH_API_URL="http://127.0.0.1:$PORT" SW_PUSH_URL="http://127.0.0.1:$PORT"
  export SW_PUSH_TOKEN_FILE="$WORK/token"; echo test-token > "$SW_PUSH_TOKEN_FILE"
  export PATH="$ROOT/tests/fakes:$PATH"
  MOCK="http://127.0.0.1:$PORT"
  curl -fsS -X POST "$MOCK/__control" -d '{"issues": [
    {"number": 1, "state": "open", "title": "sw-dziennik", "labels": [{"name": "sw-dziennik"}]},
    {"number": 5, "state": "open", "title": "Planer", "labels": [{"name": "sw-pomysl"}, {"name": "sw-stan-specyfikacja"}, {"name": "sw-spec-gotowa"}],
     "body": "karta\n\n<!-- sw:meta {\"repo\":\"cieyhomelab/app\"} -->"}]}' >/dev/null
  cd "$WORK" || return 1
}

teardown() { cd / && kill "$MOCK_PID" 2>/dev/null || true; rm -rf "$WORK"; }

state() { curl -fsS -X POST -d '{}' "$MOCK/__control"; }
pushes() { curl -fsS "$MOCK/__requests" | jq -c '[.[] | select(.path == "/m/push/gate")]'; }

@test "the idea is taken from the README link; label, pauseReason, closing, journal and one notification" {
  printf 'x\nhttps://github.com/cieyhomelab/sw-control/issues/5\n' > README.md
  run "$ROOT/bin/sw-spec-pause" "uwagi po 2 rundach" --pr https://github.com/cieyhomelab/app/pull/3
  [ "$status" -eq 0 ]
  [ "$output" = "WYNIK: WSTRZYMANY" ]
  issue="$(state | jq -c '.issues[] | select(.number == 5)')"
  [ "$(jq -c '[.labels[].name]' <<<"$issue")" = '["sw-pomysl","sw-spec-gotowa","sw-stan-wstrzymany"]' ]
  [ "$(jq -r .state <<<"$issue")" = "closed" ]
  [ "$(jq -r .body <<<"$issue" | sed -n 's/.*<!-- sw:meta \(.*\) -->/\1/p' | jq -cS .)" \
    = '{"pauseReason":"uwagi po 2 rundach (PR https://github.com/cieyhomelab/app/pull/3)","repo":"cieyhomelab/app"}' ]
  [[ "$(state | jq -r '.comments["1"][0].body')" == "wstrzymanie: pomysł #5: uwagi po 2 rundach"* ]]
  [ "$(pushes | jq -c '.[0].body | {gate, number, title}')" = '{"gate":"blocked","number":5,"title":"Projekt wstrzymany: uwagi po 2 rundach · 0% bez interwencji"}' ]
}

@test "personal data in the reason is masked" {
  run "$ROOT/bin/sw-spec-pause" "uwagi od jan@example.org" --idea cieyhomelab/sw-control#5
  [ "$status" -eq 0 ]
  [[ "$(state | jq -r '.issues[] | select(.number == 5) | .body')" != *"jan@example.org"* ]]
  [[ "$(pushes | jq -r '.[0].body.title')" != *"jan@example.org"* ]]
}

@test "an idea that is already paused or closed is left alone" {
  run "$ROOT/bin/sw-spec-pause" "a" --idea cieyhomelab/sw-control#5
  run "$ROOT/bin/sw-spec-pause" "b" --idea cieyhomelab/sw-control#5
  [ "$status" -eq 0 ]
  [[ "$output" == "WYNIK: POMINIETO"* ]]
  [ "$(pushes | jq length)" -eq 1 ]
}

@test "a missing link or a foreign repository is an error" {
  run "$ROOT/bin/sw-spec-pause" "a"
  [ "$status" -eq 1 ]
  [[ "$output" == "STAN: BLAD"* ]]
  run "$ROOT/bin/sw-spec-pause" "a" --idea other/repo#5
  [ "$status" -eq 1 ]
  [ "$(state | jq -r '.issues[] | select(.number == 5) | .state')" = "open" ]
}
