#!/usr/bin/env bats
# Integration: bin/sw-kierownik (assignment of the modules to the agent limit, S6) against the mock GitHub and Cezar APIs.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  WORK="$(mktemp -d)"
  python3 "$ROOT/tests/tools/mock_api.py" --port 0 --port-file "$WORK/port" &
  MOCK_PID=$!
  for _ in $(seq 1 50); do [ -s "$WORK/port" ] && break; sleep 0.1; done
  PORT="$(cat "$WORK/port")"
  export SW_CEZAR_URL="http://127.0.0.1:$PORT" FAKE_GH_API_URL="http://127.0.0.1:$PORT" SW_SPEC_REPO=cieyhomelab/app
  export CEZ_PROJECT_ID=proj
  export PATH="$ROOT/tests/fakes:$PATH"
  jq '.maxParallelAgents = 3' "$ROOT/config/sw.json" > "$WORK/sw.json"; export SW_CONFIG="$WORK/sw.json"
  curl -fsS -X POST "$SW_CEZAR_URL/__control" -d '{"projects": [{"id": "proj", "name": "app"}]}' >/dev/null
  mkdir -p "$WORK/repo/docs/kontrakty"
  cd "$WORK/repo" || return 1
  for m in a b c d; do
    printf '# %s\n\n## Udostępnia\n- poz-%s\n\n## Wymaga\nbrak\n\n## Forma\nczęść aplikacji\nx\n' "$m" "$m" > "docs/kontrakty/$m.md"
  done
  printf '# e\n\n## Udostępnia\n- poz-e\n\n## Wymaga\n- a: poz-a\n- b: poz-b\n\n## Forma\nczęść aplikacji\nx\n' > docs/kontrakty/e.md
  "$ROOT/bin/sw-moduly" zaloz >/dev/null
}

teardown() {
  kill "$MOCK_PID" 2>/dev/null || true
  rm -rf "$WORK"
}

app() { curl -fsS -X POST -d '{}' "$SW_CEZAR_URL/__control" | jq -c "$1"; }
states() { app '.app_issues["cieyhomelab/app"] | map(.title + "=" + ([.labels[].name | select(startswith("sw-modul-"))] | join(",")))'; }
project_limit() { app '.projects[0].maxParallel'; }

@test "S6 limit 3 and 5 ready modules: at most 3 are assigned at once" {
  run "$ROOT/bin/sw-kierownik" przydziel
  [ "$status" -eq 0 ]
  [ "$(grep -c '^URUCHOM:' <<<"$output")" -eq 3 ]
  [[ "$output" == *"URUCHOM: a"* && "$output" == *"URUCHOM: b"* && "$output" == *"URUCHOM: c"* ]]
  [ "${lines[-1]}" = "WYNIK: PRZYDZIELONO 3 (w pracy 3 z limitu 3, gotowych bez miejsca 2, czeka na kontrakt 0)" ]
  [ "$(app '[.app_issues["cieyhomelab/app"][] | select(any(.labels[]; .name == "sw-modul-w-pracy"))] | length')" = 3 ]
}

@test "S6 a repeated assignment does not exceed the limit" {
  "$ROOT/bin/sw-kierownik" przydziel >/dev/null
  run "$ROOT/bin/sw-kierownik" przydziel
  [ "$status" -eq 0 ]
  [[ "$output" != *"URUCHOM:"* ]]
  [ "${lines[-1]}" = "WYNIK: PRZYDZIELONO 0 (w pracy 3 z limitu 3, gotowych bez miejsca 2, czeka na kontrakt 0)" ]
}

@test "S6 a merged module frees a slot, the next module is assigned" {
  "$ROOT/bin/sw-kierownik" przydziel >/dev/null
  run "$ROOT/bin/sw-kierownik" zmergowany a
  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = "WYNIK: ZMERGOWANY a" ]
  [ "$(app '.app_issues["cieyhomelab/app"][0] | [.state, ([.labels[].name] | sort)]')" = '["closed",["sw-modul","sw-modul-zmergowany"]]' ]
  run "$ROOT/bin/sw-kierownik" przydziel
  [[ "$output" == *"URUCHOM: d"* ]]
  [ "$(grep -c '^URUCHOM:' <<<"$output")" -eq 1 ]
}

@test "S6 a changed limit holds from the next assignment and is set on the Cezar project" {
  "$ROOT/bin/sw-kierownik" przydziel >/dev/null
  [ "$(project_limit)" = 3 ]
  jq '.maxParallelAgents = 4' "$SW_CONFIG" > "$WORK/sw2.json" && mv "$WORK/sw2.json" "$SW_CONFIG"
  run "$ROOT/bin/sw-kierownik" przydziel
  [ "$(project_limit)" = 4 ]
  [ "$(grep -c '^URUCHOM:' <<<"$output")" -eq 1 ]
  [ "${lines[-1]}" = "WYNIK: PRZYDZIELONO 1 (w pracy 4 z limitu 4, gotowych bez miejsca 1, czeka na kontrakt 0)" ]
}

@test "S6 limit 1 assigns one module at a time" {
  jq '.maxParallelAgents = 1' "$SW_CONFIG" > "$WORK/sw2.json" && mv "$WORK/sw2.json" "$SW_CONFIG"
  run "$ROOT/bin/sw-kierownik" przydziel
  [ "$(grep -c '^URUCHOM:' <<<"$output")" -eq 1 ]
  [ "$(project_limit)" = 1 ]
}

@test "S6 the state of a module goes do-zrobienia -> w-pracy -> zmergowany" {
  [ "$(states | jq -c '.[0]')" = '"Moduł: a=sw-modul-do-zrobienia"' ]
  "$ROOT/bin/sw-kierownik" przydziel >/dev/null
  [ "$(states | jq -c '.[0]')" = '"Moduł: a=sw-modul-w-pracy"' ]
  "$ROOT/bin/sw-kierownik" zmergowany a >/dev/null
  [ "$(states | jq -c '.[0]')" = '"Moduł: a=sw-modul-zmergowany"' ]
  run "$ROOT/bin/sw-kierownik" stan
  [ "${lines[-1]}" = "WYNIK: STAN do-zrobienia 2 w-pracy 2 zmergowany 1" ]
}

@test "S6 a module requiring a module without a contract waits" {
  printf '# f\n\n## Udostępnia\n- poz-f\n\n## Wymaga\n- nieistniejacy: x\n\n## Forma\nczęść aplikacji\nx\n' > docs/kontrakty/f.md
  "$ROOT/bin/sw-moduly" zaloz >/dev/null
  jq '.maxParallelAgents = 10' "$SW_CONFIG" > "$WORK/sw2.json" && mv "$WORK/sw2.json" "$SW_CONFIG"
  run "$ROOT/bin/sw-kierownik" przydziel
  [[ "$output" != *"URUCHOM: f"* && "$output" == *"URUCHOM: e"* ]]
  [ "${lines[-1]}" = "WYNIK: PRZYDZIELONO 5 (w pracy 5 z limitu 10, gotowych bez miejsca 0, czeka na kontrakt 1)" ]
}

@test "S6 a module requiring others is ready on their contracts, before they are merged" {
  jq '.maxParallelAgents = 5' "$SW_CONFIG" > "$WORK/sw2.json" && mv "$WORK/sw2.json" "$SW_CONFIG"
  run "$ROOT/bin/sw-kierownik" przydziel
  [[ "$output" == *"URUCHOM: e"* ]]
}

@test "S6 a merge of a module that is not in work is skipped" {
  run "$ROOT/bin/sw-kierownik" zmergowany a
  [ "$status" -eq 0 ]
  [[ "${lines[-1]}" == "WYNIK: POMINIETO"* ]]
}

@test "S6 an invalid limit stops with STAN: BLAD" {
  jq '.maxParallelAgents = 0' "$SW_CONFIG" > "$WORK/sw2.json" && mv "$WORK/sw2.json" "$SW_CONFIG"
  run "$ROOT/bin/sw-kierownik" przydziel
  [ "$status" -eq 1 ]
  [[ "$output" == *"STAN: BLAD niepoprawny maxParallelAgents"* ]]
}
