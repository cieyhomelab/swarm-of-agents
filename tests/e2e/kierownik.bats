#!/usr/bin/env bats
# E2E (S6): the manager assigns five modules to the limit of agents. The agents are mocks: a module
# "in work" counts as one working agent until the mock merges it (bin/sw-kierownik zmergowany). The
# script runs exactly as on the VPS against the mocked GitHub and Cezar APIs.

setup() {
  : "${MOCK_URL:?run through scripts/test-e2e.sh}"
  curl -fsS -X POST -d '{"reset": true}' "$MOCK_URL/__control" >/dev/null
  home="${SW_HOME:-/work}"
  WORK="$(mktemp -d)"
  cd "$WORK" || return 1
  export CEZ_PROJECT_ID=proj SW_SPEC_REPO=cieyhomelab/app FAKE_GH_API_URL="$MOCK_URL" SW_CEZAR_URL="$MOCK_URL"
  export PATH="$home/tests/fakes:$PATH"
  jq '.maxParallelAgents = 3' "$home/config/sw.json" > "$WORK/sw.json"; export SW_CONFIG="$WORK/sw.json"
  curl -fsS -X POST "$MOCK_URL/__control" -d '{"projects": [{"id": "proj", "name": "app"}]}' >/dev/null
  mkdir -p docs/kontrakty
  for m in a b c d e; do
    printf '# %s\n\n## Udostępnia\n- poz-%s\n\n## Wymaga\nbrak\n\n## Forma\nczęść aplikacji\nx\n' "$m" "$m" > "docs/kontrakty/$m.md"
  done
  "$home/bin/sw-moduly" zaloz >/dev/null 2>&1
}

teardown() { cd / && rm -rf "$WORK"; }

kierownik() { bash "${SW_HOME:-/work}/bin/sw-kierownik" "$@" 2>/dev/null; }
working() { kierownik stan | sed -E 's/.* w-pracy ([0-9]+) .*/\1/'; }

@test "S6 five modules, limit 3: never more than 3 agents work, all five get merged" {
  merged=0 peak=0
  for _ in 1 2 3 4 5 6 7 8; do
    out="$(kierownik przydziel)"
    now="$(working)"
    [ "$now" -gt "$peak" ] && peak="$now"
    [ "$now" -le 3 ]
    # the mock agents finish: the first module in work is merged
    first="$(grep -m1 '^URUCHOM:' <<<"$out" | sed 's/^URUCHOM: //' || true)"
    [ -n "$first" ] || first="$(curl -fsS -X POST -d '{}' "$MOCK_URL/__control" | jq -r '.app_issues["cieyhomelab/app"][] | select(any(.labels[]; .name == "sw-modul-w-pracy")) | .title' | head -1 | sed 's/^Moduł: //')"
    [ -z "$first" ] || { kierownik zmergowany "$first" >/dev/null; merged=$((merged + 1)); }
  done
  [ "$peak" -eq 3 ]
  [ "$merged" -eq 5 ]
  [ "$(kierownik stan)" = "WYNIK: STAN do-zrobienia 0 w-pracy 0 zmergowany 5" ]
}

@test "S6 a changed limit holds from the next assignment" {
  out="$(kierownik przydziel)"
  [ "$(grep -c '^URUCHOM:' <<<"$out")" -eq 3 ]
  jq '.maxParallelAgents = 5' "$SW_CONFIG" > "$WORK/sw2.json" && mv "$WORK/sw2.json" "$SW_CONFIG"
  out="$(kierownik przydziel)"
  [ "$(grep -c '^URUCHOM:' <<<"$out")" -eq 2 ]
  [ "$(working)" -eq 5 ]
  [ "$(curl -fsS -X POST -d '{}' "$MOCK_URL/__control" | jq '.projects[0].maxParallel')" = 5 ]
}
