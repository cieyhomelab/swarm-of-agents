#!/usr/bin/env bats
# Integration: bin/sw-idea-card and the generator.json written by bin/sw-gate,
# against the mock GitHub API.

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
  export SW_RUN_DIR="$WORK/run"
  mkdir -p "$SW_RUN_DIR"
  curl -fsS -X POST "$SW_CEZAR_URL/__control" -d '{
    "issues": [{"number": 1, "state": "open", "title": "sw-dziennik", "labels": [{"name": "sw-dziennik"}]}]}' >/dev/null
}

teardown() {
  kill "$MOCK_PID" 2>/dev/null || true
  rm -rf "$WORK"
}

state() { curl -fsS -X POST -d '{}' "$SW_CEZAR_URL/__control"; }
journal() { state | jq -c '[.comments["1"][]?.body]'; }
cards() { state | jq -c '[.issues[] | select(.labels | map(.name) | index("sw-w-ocenie"))]'; }

# proba [jq-filter] — writes a valid card as the agent would, modified by the filter.
proba() {
  jq -n '{tytul: "Planer posiłków", problem: "Trudno zaplanować zakupy na tydzień",
          dla_kogo: "rodziny z dziećmi", co_robi: "Układa menu i listę zakupów.",
          sprawdzenie: {podsumowanie: "Badanie potwierdza problem; brak bezpłatnego narzędzia.",
                        zrodla: ["https://example.org/a", "https://example.org/b"]},
          oceny: {wplyw: 4, wykonalnosc: 5, ryzyko: 2},
          rekomendacja: "rekomenduję", uzasadnienie: "Prosta i użyteczna."}
         | '"${1:-.}" > "$SW_RUN_DIR/proba.json"
}

rejected() { # rejected <nr> <tytul> <problem+dla kogo>
  jq -nc --argjson n "$1" --arg t "$2" --arg p "$3" '
    {number: $n, state: "closed", title: $t, labels: [{name: "sw-pomysl"}, {name: "sw-odrzucony"}],
     body: ("## Problem i dla kogo\n" + $p + "\n\n## Co robi aplikacja\nx\n\n<!-- sw:meta {} -->")}'
}

@test "a valid card becomes an issue in review with all fields" {
  proba
  run "$ROOT/bin/sw-idea-card" karta
  [ "$status" -eq 0 ]
  [[ "$output" == "WYNIK: KARTA "* ]]
  [ "$(cards | jq length)" -eq 1 ]
  [ "$(cards | jq -r '.[0].labels | map(.name) | sort | join(",")')" = "sw-pomysl,sw-w-ocenie" ]
  [ "$(cards | jq -r '.[0].title')" = "Planer posiłków" ]
  body="$(cards | jq -r '.[0].body')"
  for part in "## Problem i dla kogo" "rodziny z dziećmi" "## Co robi aplikacja" "## Sprawdzenie w sieci" \
              "https://example.org/a" "https://example.org/b" "## Ocena" "4/5" "5/5" "2/5" \
              "## Rekomendacja" "rekomenduję: Prosta i użyteczna." "<!-- sw:meta {} -->"; do
    [[ "$body" == *"$part"* ]] || { echo "missing: $part"; return 1; }
  done
  [ "$(journal)" = "[]" ]
  [ ! -e "$SW_RUN_DIR/proba.json" ]
}

@test "an incomplete card is a failed attempt with the missing fields" {
  proba 'del(.co_robi) | .oceny.ryzyko = 7'
  run "$ROOT/bin/sw-idea-card" karta
  [ "$status" -eq 0 ]
  [[ "$output" == "WYNIK: NIEUDANA niepelna karta: co_robi, oceny.ryzyko" ]]
  [ "$(cards)" = "[]" ]
  [ "$(journal | jq -r '.[0]')" = "odrzucona próba: niepelna karta: co_robi, oceny.ryzyko" ]
}

@test "a card without a source is a failed attempt" {
  proba '.sprawdzenie.zrodla = ["nie-adres"]'
  run "$ROOT/bin/sw-idea-card" karta
  [[ "$output" == "WYNIK: NIEUDANA brak źródła"* ]]
  [ "$(cards)" = "[]" ]
  [[ "$(journal | jq -r '.[0]')" == "odrzucona próba: brak źródła"* ]]
}

@test "a missing proba.json is a failed attempt, not a card" {
  run "$ROOT/bin/sw-idea-card" karta
  [ "$status" -eq 0 ]
  [[ "$output" == "WYNIK: NIEUDANA niepelna karta"* ]]
  [ "$(cards)" = "[]" ]
}

@test "nieudana logs the reason of the agent and removes the file" {
  jq -n '{przyczyna: "kategoria wykluczona: kalkulator dawki insuliny"}' > "$SW_RUN_DIR/proba.json"
  run "$ROOT/bin/sw-idea-card" nieudana
  [ "$status" -eq 0 ]
  [ "$output" = "WYNIK: NIEUDANA kategoria wykluczona: kalkulator dawki insuliny" ]
  [ "$(journal | jq -r '.[0]')" = "odrzucona próba: kategoria wykluczona: kalkulator dawki insuliny" ]
  [ ! -e "$SW_RUN_DIR/proba.json" ]
}

@test "nieudana without a file still leaves a journal entry" {
  run "$ROOT/bin/sw-idea-card" nieudana
  [ "$status" -eq 0 ]
  [ "$(journal | jq -r '.[0]')" = "odrzucona próba: agent nie podal przyczyny" ]
}

@test "a card with the title of a rejected idea is a duplicate" {
  curl -fsS -X POST "$SW_CEZAR_URL/__control" -d "$(jq -nc --argjson r "$(rejected 2 'planer  POSIŁKÓW!' 'Inny problem dla innych')" \
    '{issues: [{number: 1, state: "open", title: "sw-dziennik", labels: [{name: "sw-dziennik"}]}, $r]}')" >/dev/null
  # Different punctuation, spacing and case still match.
  proba '.tytul = "planer posiłków!"'
  run "$ROOT/bin/sw-idea-card" karta
  [ "$output" = "WYNIK: NIEUDANA duplikat odrzuconego pomysłu" ]
  [ "$(cards)" = "[]" ]
  [ "$(journal | jq -r '.[0]')" = "odrzucona próba: duplikat odrzuconego pomysłu" ]
}

@test "the same problem for the same group is a duplicate under another title" {
  curl -fsS -X POST "$SW_CEZAR_URL/__control" -d "$(jq -nc \
    --argjson r "$(rejected 2 'Zupełnie inna nazwa' $'Trudno zaplanować zakupy na tydzień\n\nDla kogo: Rodziny z dziećmi')" \
    '{issues: [{number: 1, state: "open", title: "sw-dziennik", labels: [{name: "sw-dziennik"}]}, $r]}')" >/dev/null
  proba '.tytul = "Menu na tydzień"'
  run "$ROOT/bin/sw-idea-card" karta
  [ "$output" = "WYNIK: NIEUDANA duplikat odrzuconego pomysłu" ]
  [ "$(cards)" = "[]" ]
}

@test "the same problem for another group is not a duplicate" {
  curl -fsS -X POST "$SW_CEZAR_URL/__control" -d "$(jq -nc \
    --argjson r "$(rejected 2 'Zupełnie inna nazwa' $'Trudno zaplanować zakupy na tydzień\n\nDla kogo: seniorzy')" \
    '{issues: [{number: 1, state: "open", title: "sw-dziennik", labels: [{name: "sw-dziennik"}]}, $r]}')" >/dev/null
  proba
  run "$ROOT/bin/sw-idea-card" karta
  [[ "$output" == "WYNIK: KARTA "* ]]
}

@test "no second card while an idea is under evaluation" {
  curl -fsS -X POST "$SW_CEZAR_URL/__control" -d '{
    "issues": [{"number": 1, "state": "open", "title": "sw-dziennik", "labels": [{"name": "sw-dziennik"}]},
               {"number": 4, "state": "open", "title": "x", "labels": [{"name": "sw-pomysl"}, {"name": "sw-w-ocenie"}]}]}' >/dev/null
  proba
  run "$ROOT/bin/sw-idea-card" karta
  [ "$status" -eq 0 ]
  [[ "$output" == "WYNIK: POMINIETO"* ]]
  [ "$(cards | jq length)" -eq 1 ]
}

@test "the gate writes rejected ideas and redacted hints to generator.json" {
  curl -fsS -X POST "$SW_CEZAR_URL/__control" -d "$(jq -nc --argjson r "$(rejected 2 'Budżet domowy' $'Brak kontroli wydatków\n\nDla kogo: single')" \
    '{issues: [{number: 1, state: "open", title: "sw-dziennik", labels: [{name: "sw-dziennik"}]}, $r],
      comments: {"2": [{body: "<!-- sw:odrzucenie -->\nza podobne do istniejących budżetów, pisz na ja@example.org", created_at: "2026-01-01T00:00:00Z"},
                       {body: "zwykły komentarz", created_at: "2026-01-01T00:00:00Z"}]}}')" >/dev/null
  CEZ_RUN_ID=me run "$ROOT/bin/sw-gate"
  [[ "$output" == *"URUCHOM: GENERATOR"* ]]
  [ "$(jq -r '.odrzucone | length' "$SW_RUN_DIR/generator.json")" -eq 1 ]
  [ "$(jq -r '.odrzucone[0].tytul' "$SW_RUN_DIR/generator.json")" = "Budżet domowy" ]
  [ "$(jq -r '.odrzucone[0].problem' "$SW_RUN_DIR/generator.json")" = $'Brak kontroli wydatków\n\nDla kogo: single' ]
  # the owner's reasons, with or without the sw:odrzucenie marker, scrubbed
  [ "$(jq -c '.odrzucone[0].wskazowki' "$SW_RUN_DIR/generator.json")" = '["za podobne do istniejących budżetów, pisz na [email]","zwykły komentarz"]' ]
}

@test "the gate writes no generator.json while a project is active" {
  curl -fsS -X POST "$SW_CEZAR_URL/__control" -d '{
    "issues": [{"number": 5, "state": "open", "body": "x", "labels": [{"name": "sw-pomysl"}, {"name": "sw-stan-specyfikacja"}]}]}' >/dev/null
  CEZ_RUN_ID=me run "$ROOT/bin/sw-gate"
  [[ "$output" == *"URUCHOM: NIC"* ]]
  [ ! -e "$SW_RUN_DIR/generator.json" ]
}
