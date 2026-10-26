#!/usr/bin/env bats
# E2E: the GENERATOR branch of workflows/sw-sweep.yml (S1, S3) walked by
# tests/tools/run_workflow.py with a mock agent, exactly as the workflow calls
# the gate and the scripts on the VPS, against mocked Cezar and GitHub APIs.

setup() {
  : "${MOCK_URL:?run through scripts/test-e2e.sh}"
  curl -fsS -X POST -d '{"reset": true}' "$MOCK_URL/__control" >/dev/null
  export SW_PUSH_URL="$MOCK_URL"
  home="${SW_HOME:-/work}"
  WORK="$(mktemp -d)"
  cd "$WORK" || return 1
  export MOCK_AGENT="$WORK/agent"
  export PLAN="$WORK/plan"
  cat > "$MOCK_AGENT" <<'AGENT'
#!/usr/bin/env bash
# Mock sw-generator: attempt N does what line N of $PLAN says
#   karta <tytul>            a complete card with that title
#   nieudana <przyczyna>     a failed attempt
# and, like the real agent, writes .ai/sw-run/proba.json and prints its verdict.
set -euo pipefail
line="$(sed -n "${2}p" "$PLAN")"
kind="${line%% *}"
arg="${line#* }"
test -s .ai/sw-run/generator.json   # the gate has prepared the input
case "$kind" in
  karta)
    jq -n --arg t "$arg" '{tytul: $t, problem: "Trudno zaplanować zakupy na tydzień", dla_kogo: "rodziny z dziećmi",
        co_robi: "Układa menu i listę zakupów.",
        sprawdzenie: {podsumowanie: "Problem potwierdzony.", zrodla: ["https://example.org/a"]},
        oceny: {wplyw: 4, wykonalnosc: 5, ryzyko: 2}, rekomendacja: "rekomenduję", uzasadnienie: "Proste."}' \
      > .ai/sw-run/proba.json
    echo karta ;;
  *)
    jq -n --arg r "$arg" '{przyczyna: $r}' > .ai/sw-run/proba.json
    echo nieudana ;;
esac
AGENT
  chmod +x "$MOCK_AGENT"
}

teardown() { cd / && rm -rf "$WORK"; }

state() { curl -fsS -X POST -d '{}' "$MOCK_URL/__control"; }
control() { curl -fsS -X POST "$MOCK_URL/__control" -d "$1" >/dev/null; }
pushes() { curl -fsS "$MOCK_URL/__requests" | jq -c '[.[] | select(.method == "POST" and .path == "/m/push/gate")]'; }
journal() { state | jq -c '[.comments["1"][]?.body]'; }
cards() { state | jq -c '[.issues[] | select(.labels | map(.name) | index("sw-w-ocenie"))]'; }
sweep() { run python3 "$home/tests/tools/run_workflow.py" "$home/workflows/sw-sweep.yml"; }
base_issues() { echo '{"number": 1, "state": "open", "title": "sw-dziennik", "labels": [{"name": "sw-dziennik"}]}'; }

@test "S1 without an active project a successful attempt creates the card in review" {
  control "{\"issues\": [$(base_issues)]}"
  echo "karta Planer posiłków" > "$PLAN"
  sweep
  [ "$status" -eq 0 ]
  [[ "$output" == *"END done success"* ]]
  [ "$(cards | jq length)" -eq 1 ]
  [ "$(cards | jq -r '.[0].labels | map(.name) | sort | join(",")')" = "sw-pomysl,sw-w-ocenie" ]
  body="$(cards | jq -r '.[0].body')"
  for part in "## Problem i dla kogo" "## Co robi aplikacja" "## Sprawdzenie w sieci" "https://example.org/a" \
              "## Ocena" "## Rekomendacja"; do
    [[ "$body" == *"$part"* ]] || { echo "missing: $part"; return 1; }
  done
  [ "$(journal)" = "[]" ]
}

@test "S1 five failed attempts give five journal entries, no card and no notification" {
  control "{\"issues\": [$(base_issues)]}"
  for reason in "kategoria wykluczona: dawki" "istnieje bezpłatne narzędzie: X" "brak źródła" "duplikat" "kategoria wykluczona: handel"; do
    echo "nieudana $reason"
  done > "$PLAN"
  sweep
  [ "$status" -eq 0 ]
  [ "$(cards)" = "[]" ]
  [ "$(journal | jq '[.[] | select(startswith("odrzucona próba: "))] | length')" -eq 5 ]
  [ "$(journal | jq -r '.[0]')" = "odrzucona próba: kategoria wykluczona: dawki" ]
  [ "$(journal | jq -r '.[5]')" = "brak pomysłu" ]
  [ "$(journal | jq length)" -eq 6 ]
  [ "$(pushes)" = "[]" ]
}

@test "S1 the loop stops at the first card" {
  control "{\"issues\": [$(base_issues)]}"
  printf 'nieudana brak źródła\nkarta Planer\nkarta Drugi\n' > "$PLAN"
  sweep
  [ "$status" -eq 0 ]
  [ "$(cards | jq length)" -eq 1 ]
  [ "$(cards | jq -r '.[0].title')" = "Planer" ]
  [ "$(journal | jq length)" -eq 1 ]
}

@test "S1 an excluded category never reaches the owner and the journal says why" {
  control "{\"issues\": [$(base_issues)]}"
  printf 'nieudana kategoria wykluczona: kalkulator dawki insuliny\nnieudana kategoria wykluczona: portfel\nnieudana kategoria wykluczona: x\nnieudana kategoria wykluczona: y\nnieudana kategoria wykluczona: z\n' > "$PLAN"
  sweep
  [ "$(cards)" = "[]" ]
  [ "$(journal | jq '[.[] | select(contains("kategoria wykluczona"))] | length')" -eq 5 ]
  [ "$(pushes)" = "[]" ]
}

@test "S1 S3 a duplicate of a rejected idea never reaches the owner" {
  rejected='{"number": 2, "state": "closed", "title": "Planer posiłków", "labels": [{"name": "sw-pomysl"}, {"name": "sw-odrzucony"}],
             "body": "## Problem i dla kogo\nBrak kontroli nad wydatkami\n\n## Co robi aplikacja\nx\n\n<!-- sw:meta {} -->"}'
  control "{\"issues\": [$(base_issues), $rejected]}"
  printf 'karta planer POSIŁKÓW\nkarta Planer posiłków!\nkarta  Planer   posiłków\nkarta planer posiłków.\nkarta PLANER POSIŁKÓW\n' > "$PLAN"
  sweep
  [ "$status" -eq 0 ]
  [ "$(cards)" = "[]" ]
  [ "$(journal | jq '[.[] | select(. == "odrzucona próba: duplikat odrzuconego pomysłu")] | length')" -eq 5 ]
  [ "$(pushes)" = "[]" ]
}

@test "S3 the hint of a rejection reaches the generator in generator.json" {
  rejected='{"number": 2, "state": "closed", "title": "Budżet domowy", "labels": [{"name": "sw-pomysl"}, {"name": "sw-odrzucony"}],
             "body": "## Problem i dla kogo\nBrak kontroli wydatków\n\nDla kogo: single\n\n## Co robi aplikacja\nx\n\n<!-- sw:meta {} -->"}'
  control "{\"issues\": [$(base_issues), $rejected],
            \"comments\": {\"2\": [{\"body\": \"<!-- sw:odrzucenie -->\\nza podobne do istniejących budżetów domowych\", \"created_at\": \"2026-01-01T00:00:00Z\"}]}}"
  echo "karta Planer posiłków" > "$PLAN"
  sweep
  [ "$status" -eq 0 ]
  [ "$(jq -r '.odrzucone[0].tytul' .ai/sw-run/generator.json)" = "Budżet domowy" ]
  [ "$(jq -c '.odrzucone[0].wskazowki' .ai/sw-run/generator.json)" = '["za podobne do istniejących budżetów domowych"]' ]
  [ "$(cards | jq length)" -eq 1 ]
}

@test "S1 an active project starts no attempt" {
  control '{"issues": [{"number": 5, "state": "open", "body": "x", "labels": [{"name": "sw-pomysl"}, {"name": "sw-stan-specyfikacja"}]}]}'
  echo "karta Planer" > "$PLAN"
  sweep
  [ "$status" -eq 0 ]
  [[ "$output" != *"TRACE generator"* ]]
  [ "$(cards)" = "[]" ]
}
