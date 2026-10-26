#!/usr/bin/env bats
# Integration: bin/sw-przeglad — the verdict of the security review of the whole application (S9)
# and the report docs/security/<date>-raport.md (files only, no network).

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  WORK="$(mktemp -d)"
  cd "$WORK" || return 1
  mkdir -p .ai/sw-run src
  export SW_DATE=2026-10-26
}

teardown() { cd / && rm -rf "$WORK"; }

points() { # points <wynik1> <wynik2> <wynik3> <wynik4>
  jq -n --args '{punkty: [$ARGS.positional | to_entries[] | {punkt: (.key + 1), wynik: .value, uzasadnienie: "powód \(.key + 1) | z kreską"}]}' "$@" > .ai/sw-run/przeglad.json
}

@test "four passing points and the verdict pass write the report with the result of each point" {
  points pass pass pass pass
  run "$ROOT/bin/sw-przeglad" pass
  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = "WYNIK: OK docs/security/2026-10-26-raport.md" ]
  for n in 1 2 3 4; do grep -qF -- "| pass | powód $n \\| z kreską |" docs/security/2026-10-26-raport.md; done
  [ ! -e .ai/sw-run/uwagi.md ]
}

@test "a failing point stops the review, names the point in the remarks and writes no report" {
  points pass pass fail pass
  run "$ROOT/bin/sw-przeglad" pass
  [ "$status" -eq 1 ]
  [[ "$output" == *"STAN: BLAD"* ]]
  grep -q '^1\. Punkt 3 (każdy adres aplikacji wymaga uwierzytelnienia)' .ai/sw-run/uwagi.md
  [ ! -e docs/security ]
}

@test "the verdict fail stops the review even when every point says pass" {
  points pass pass pass pass
  run "$ROOT/bin/sw-przeglad" fail
  [ "$status" -eq 1 ]
  [ ! -e docs/security ]
}

@test "a missing or incomplete result file stops the review" {
  run "$ROOT/bin/sw-przeglad" pass
  [ "$status" -eq 1 ]
  jq -n '{punkty: [{punkt: 1, wynik: "pass"}, {punkt: 2, wynik: "pass"}]}' > .ai/sw-run/przeglad.json
  run "$ROOT/bin/sw-przeglad" pass
  [ "$status" -eq 1 ]
  grep -q 'Punkt 3' .ai/sw-run/uwagi.md && grep -q 'Punkt 4' .ai/sw-run/uwagi.md
  [ ! -e docs/security ]
}

@test "a secret in the repository fails point 2 whatever the agent said, without echoing the secret" {
  points pass pass pass pass
  printf 'KEY=ghp_%s\n' "$(printf 'b%.0s' $(seq 36))" > src/config.env
  run "$ROOT/bin/sw-przeglad" pass
  [ "$status" -eq 1 ]
  grep -q 'Punkt 2' .ai/sw-run/uwagi.md
  grep -q 'src/config.env' .ai/sw-run/uwagi.md
  ! grep -q 'ghp_' .ai/sw-run/uwagi.md
  [[ "$output" != *"ghp_"* ]]
  [ ! -e docs/security ]
}

@test "a secret in a git-ignored file does not stop the review, the same secret in a tracked file does" {
  points pass pass pass pass
  git init -q . && printf '.venv/\n' > .gitignore
  mkdir -p .venv/lib
  printf 'KEY=AKIAIOSFODNN7EXAMPLE\n' > .venv/lib/docs.py
  git add .gitignore && git add -f src 2>/dev/null || true
  run "$ROOT/bin/sw-przeglad" pass
  [ "$status" -eq 0 ]
  printf 'KEY=AKIAIOSFODNN7EXAMPLE\n' > src/config.env
  git add src/config.env
  run "$ROOT/bin/sw-przeglad" pass
  [ "$status" -eq 1 ]
  grep -q 'src/config.env' .ai/sw-run/uwagi.md
  ! grep -q '.venv' .ai/sw-run/uwagi.md
}

@test "an e-mail address in a justification is masked in the report" {
  jq -n '{punkty: [range(1;5) | {punkt: ., wynik: "pass", uzasadnienie: "kontakt jan@example.com"}]}' > .ai/sw-run/przeglad.json
  run "$ROOT/bin/sw-przeglad" pass
  [ "$status" -eq 0 ]
  ! grep -q 'jan@example.com' docs/security/2026-10-26-raport.md
}
