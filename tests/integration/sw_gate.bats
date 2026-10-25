#!/usr/bin/env bats
# Integration: the decisions of bin/sw-gate against the mock Cezar/GitHub API
# (table-driven states of issues and tasks).

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
  export CEZ_RUN_ID=me
  unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN ANTHROPIC_BASE_URL \
        CLAUDE_CODE_USE_BEDROCK CLAUDE_CODE_USE_VERTEX CLAUDE_CODE_USE_FOUNDRY
}

teardown() {
  kill "$MOCK_PID" 2>/dev/null || true
  rm -rf "$WORK"
}

control() { curl -fsS -X POST -d "$1" "$SW_CEZAR_URL/__control" >/dev/null; }

# issue <number> <meta-json> <label>... — JSON of one sw-pomysl issue.
issue() {
  local number="$1" meta="$2"; shift 2
  jq -nc --argjson n "$number" --arg meta "$meta" --args \
    '{number: $n, state: "open", body: ("karta\n<!-- sw:meta " + $meta + " -->"),
      labels: ([$ARGS.positional[], "sw-pomysl"] | map({name: .}))}' "$@"
}

state() { control "$(jq -nc --argjson i "$1" --argjson r "${2:-[]}" --argjson f "${3:-[]}" \
  '{issues: $i, runs: $r, repo_files: $f}')"; }

decision() { run "$ROOT/bin/sw-gate"; echo "$output" | grep '^URUCHOM:'; }

@test "no active project gives GENERATOR" {
  state '[]'
  [ "$(decision)" = "URUCHOM: GENERATOR" ]
}

@test "closed or finished ideas are not an active project" {
  closed="$(issue 1 '{}' sw-w-ocenie | jq -c '.state = "closed"')"
  state "[$closed, $(issue 2 '{}' sw-stan-wdrozony), $(issue 3 '{}' sw-stan-wstrzymany), $(issue 4 '{}' sw-odrzucony)]"
  [ "$(decision)" = "URUCHOM: GENERATOR" ]
}

@test "each active state blocks the generator" {
  for label in sw-zatwierdzony sw-stan-specyfikacja sw-stan-architektura sw-stan-implementacja \
               sw-stan-integracja sw-stan-przeglad sw-stan-wdrazanie; do
    state "[$(issue 1 '{}' "$label")]"
    [ "$(decision)" = "URUCHOM: NIC" ]
  done
}

@test "idea under evaluation with a live task gives NIC" {
  for st in waiting running queued; do
    state "[$(issue 7 '{"evalRunId":"r1"}' sw-w-ocenie)]" "[{\"id\":\"r1\",\"workflow\":\"sw-ocena\",\"status\":\"$st\"}]"
    [ "$(decision)" = "URUCHOM: NIC" ]
  done
}

@test "idea under evaluation with a lost task gives OCENA" {
  for st in done failed cancelled review; do
    state "[$(issue 7 '{"evalRunId":"r1"}' sw-w-ocenie)]" "[{\"id\":\"r1\",\"workflow\":\"sw-ocena\",\"status\":\"$st\"}]"
    [ "$(decision)" = "URUCHOM: OCENA 7" ]
  done
}

@test "evaluation task unknown to Cezar or missing from metadata gives OCENA" {
  state "[$(issue 7 '{"evalRunId":"gone"}' sw-w-ocenie)]"
  [ "$(decision)" = "URUCHOM: OCENA 7" ]
  state "[$(issue 8 '{}' sw-w-ocenie)]"
  [ "$(decision)" = "URUCHOM: OCENA 8" ]
}

@test "another sw-sweep queued or running gives NIC even without a project" {
  for st in queued running; do
    state '[]' "[{\"id\":\"other\",\"workflow\":\"sw-sweep\",\"status\":\"$st\"}]"
    [ "$(decision)" = "URUCHOM: NIC" ]
  done
}

@test "own task, finished sweeps and other workflows do not block" {
  state '[]' '[{"id":"me","workflow":"sw-sweep","status":"running"},
               {"id":"o1","workflow":"sw-sweep","status":"done"},
               {"id":"o2","workflow":"sw-ocena","status":"running"}]'
  [ "$(decision)" = "URUCHOM: GENERATOR" ]
}

@test "a project on the sh-* chain takes no action" {
  state "[$(issue 5 '{"repo":"cieyhomelab/app"}' sw-stan-specyfikacja)]" '[]' \
    '["cieyhomelab/app/.ai/cezar/workflows/sh-delivery.yml"]'
  [ "$(decision)" = "URUCHOM: GENERATOR" ]
  state "[$(issue 6 '{"repo":"cieyhomelab/app"}' sw-w-ocenie)]" '[]' \
    '["cieyhomelab/app/.ai/cezar/workflows/sh-delivery.yml"]'
  [ "$(decision)" = "URUCHOM: GENERATOR" ]
}

@test "a project repository without the sh-* workflow stays active" {
  state "[$(issue 5 '{"repo":"cieyhomelab/app"}' sw-stan-specyfikacja)]"
  [ "$(decision)" = "URUCHOM: NIC" ]
}

@test "unreadable task list gives NIC instead of a generator" {
  state '[]'
  control '{"runs": "oops"}'
  [ "$(decision)" = "URUCHOM: NIC" ]
}
