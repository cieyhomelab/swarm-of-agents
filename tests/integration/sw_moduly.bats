#!/usr/bin/env bats
# Integration: bin/sw-moduly (issues of the modules, S5) against the mock GitHub API.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  WORK="$(mktemp -d)"
  python3 "$ROOT/tests/tools/mock_api.py" --port 0 --port-file "$WORK/port" &
  MOCK_PID=$!
  for _ in $(seq 1 50); do [ -s "$WORK/port" ] && break; sleep 0.1; done
  PORT="$(cat "$WORK/port")"
  export SW_CEZAR_URL="http://127.0.0.1:$PORT" FAKE_GH_API_URL="http://127.0.0.1:$PORT" SW_SPEC_REPO=cieyhomelab/app
  export PATH="$ROOT/tests/fakes:$PATH"
  cd "$WORK" || return 1
  mkdir -p docs/kontrakty
  printf '# planer\n\n## Udostępnia\n- ekran menu\n\n## Wymaga\n- zakupy: lista\n\n## Forma\nczęść aplikacji\nx\n' > docs/kontrakty/planer.md
  printf '# zakupy\n\n## Udostępnia\n- lista\n\n## Wymaga\nbrak\n\n## Forma\nosobna usługa\nx\n' > docs/kontrakty/zakupy.md
  echo '# Moduły' > docs/kontrakty/README.md
}

teardown() {
  kill "$MOCK_PID" 2>/dev/null || true
  rm -rf "$WORK"
}

app() { curl -fsS -X POST -d '{}' "$SW_CEZAR_URL/__control" | jq -c "$1"; }

@test "S5 every contract gets an issue sw-modul in the state sw-modul-do-zrobienia, the README none" {
  run "$ROOT/bin/sw-moduly" zaloz
  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = "WYNIK: MODULY 2 (nowych 2)" ]
  [ "$(app '.app_issues["cieyhomelab/app"] | map(.title)')" = '["Moduł: planer","Moduł: zakupy"]' ]
  [ "$(app '.app_issues["cieyhomelab/app"] | map([.labels[].name] | sort) | unique')" = '[["sw-modul","sw-modul-do-zrobienia"]]' ]
  [ "$(app '.app_issues["cieyhomelab/app"][0].body | contains("- zakupy: lista")')" = true ]
  [ "$(app '.app_labels["cieyhomelab/app"] | map(.name)')" = '["sw-modul","sw-modul-do-zrobienia","sw-modul-w-pracy","sw-modul-zmergowany"]' ]
}

@test "S5 a repeated run creates no second issue and no second label" {
  "$ROOT/bin/sw-moduly" zaloz
  run "$ROOT/bin/sw-moduly" zaloz
  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = "WYNIK: MODULY 2 (nowych 0)" ]
  [ "$(app '.app_issues["cieyhomelab/app"] | length')" = 2 ]
  [ "$(app '.app_labels["cieyhomelab/app"] | length')" = 4 ]
}

@test "S5 a module added later gets its issue, the closed issue of another is not reopened as a duplicate" {
  "$ROOT/bin/sw-moduly" zaloz
  curl -fsS -X POST "$SW_CEZAR_URL/__control" -d "$(curl -fsS -X POST -d '{}' "$SW_CEZAR_URL/__control" \
    | jq -c '{app_issues: (.app_issues | .["cieyhomelab/app"][0].state = "closed")}')" >/dev/null
  printf '# kalendarz\n\n## Udostępnia\n- widok\n\n## Wymaga\nbrak\n\n## Forma\nczęść aplikacji\nx\n' > docs/kontrakty/kalendarz.md
  run "$ROOT/bin/sw-moduly" zaloz
  [ "${lines[-1]}" = "WYNIK: MODULY 3 (nowych 1)" ]
  [ "$(app '.app_issues["cieyhomelab/app"] | map(.title)')" = '["Moduł: planer","Moduł: zakupy","Moduł: kalendarz"]' ]
}

@test "S5 without contracts the script stops with STAN: BLAD" {
  rm docs/kontrakty/planer.md docs/kontrakty/zakupy.md
  run "$ROOT/bin/sw-moduly" zaloz
  [ "$status" -eq 1 ]
  [[ "$output" == *"STAN: BLAD brak kontraktow"* ]]
}
