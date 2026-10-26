#!/usr/bin/env bats
# Integration: bin/sw-integracja (the gates of the integration of the modules, S7 stage 3) against the mock GitHub API.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  WORK="$(mktemp -d)"
  python3 "$ROOT/tests/tools/mock_api.py" --port 0 --port-file "$WORK/port" &
  MOCK_PID=$!
  for _ in $(seq 1 50); do [ -s "$WORK/port" ] && break; sleep 0.1; done
  PORT="$(cat "$WORK/port")"
  export SW_CEZAR_URL="http://127.0.0.1:$PORT" FAKE_GH_API_URL="http://127.0.0.1:$PORT" SW_SPEC_REPO=cieyhomelab/app
  export PATH="$ROOT/tests/fakes:$PATH"
  unset CEZ_PROJECT_ID
  mkdir -p "$WORK/repo/docs/kontrakty"
  cd "$WORK/repo" || return 1
  printf '# a\n\n## Udostępnia\n- poz-a\n\n## Wymaga\nbrak\n\n## Forma\nczęść aplikacji\nx\n' > docs/kontrakty/a.md
  printf '# b\n\n## Udostępnia\n- poz-b\n\n## Wymaga\n- a: poz-a\n\n## Forma\nczęść aplikacji\nx\n' > docs/kontrakty/b.md
  "$ROOT/bin/sw-moduly" zaloz >/dev/null
}

teardown() {
  kill "$MOCK_PID" 2>/dev/null || true
  rm -rf "$WORK"
}

merge_all() { for m in "$@"; do "$ROOT/bin/sw-kierownik" przydziel >/dev/null; "$ROOT/bin/sw-kierownik" zmergowany "$m" >/dev/null; done; }

@test "S7 modules waiting or in work do not create the integration task" {
  run "$ROOT/bin/sw-integracja" gotowe
  [ "$status" -eq 1 ]
  [[ "$output" == *"STAN: BLAD moduly nie sa zmergowane (do-zrobienia 2"* ]]
  "$ROOT/bin/sw-kierownik" przydziel >/dev/null
  merge_all a
  run "$ROOT/bin/sw-integracja" gotowe
  [ "$status" -eq 1 ]
  [[ "$output" == *"zmergowany 1"* ]]
}

@test "S7 every module merged: the integration task is created" {
  merge_all a b
  run "$ROOT/bin/sw-integracja" gotowe
  [ "$status" -eq 0 ]
  [ "$output" = "WYNIK: GOTOWE 2" ]
}

@test "S7 consistent contracts and no conflict markers pass the coherence check" {
  run "$ROOT/bin/sw-integracja" spojnosc
  [ "$status" -eq 0 ]
  [ "$output" = "WYNIK: OK" ]
}

@test "S7 merge-conflict markers fail the coherence check and go to the fix round remarks" {
  mkdir -p src
  printf '<<<<<<< HEAD\nx\n=======\ny\n>>>>>>> zakupy\n' > src/a.txt
  run "$ROOT/bin/sw-integracja" spojnosc
  [ "$status" -eq 1 ]
  [[ "$output" == *"STAN: BLAD konflikt modulow"* && "$output" == *"src/a.txt"* ]]
  grep -q 'Konflikt modułów' .ai/sw-run/uwagi.md
}

@test "S7 a required item that the other module does not provide fails the coherence check" {
  sed -i 's/- poz-a/- inna/' docs/kontrakty/a.md
  run "$ROOT/bin/sw-integracja" spojnosc
  [ "$status" -eq 1 ]
  [[ "$output" == *'Moduł b wymaga "poz-a" od modułu a'* ]]
}
