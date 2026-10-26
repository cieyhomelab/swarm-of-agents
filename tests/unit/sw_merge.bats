#!/usr/bin/env bats
# Unit: table of merge conditions in bin/lib/sw_merge.py (spec mode).

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

# check <recenzent-wynik> <recenzent-model> <bezp-wynik> <bezp-model> <author> <sha> <head>
check() {
  jq -nc --arg rr "$1" --arg rm "$2" --arg br "$3" --arg bm "$4" --arg a "$5" --arg s "$6" --arg h "$7" \
    '{mode: "spec", sha: $s, headSha: $h, authorModel: $a,
      verdicts: [{role: "recenzent", result: $rr, model: $rm}, {role: "bezpieczenstwo", result: $br, model: $bm}]}' \
    | python3 "$ROOT/bin/lib/sw_merge.py" | paste -sd, -
}

@test "all conditions met: nothing unmet" {
  [ -z "$(check zatwierdzona sonnet pass haiku opus abc abc)" ]
}

@test "review verdict uwagi blocks" {
  [ "$(check uwagi sonnet pass haiku opus abc abc)" = "werdykt-recenzent" ]
}

@test "security verdict fail blocks" {
  [ "$(check zatwierdzona sonnet fail haiku opus abc abc)" = "werdykt-bezpieczenstwo" ]
}

@test "reviewer on the author's model does not count" {
  [ "$(check zatwierdzona opus pass haiku opus abc abc)" = "model-recenzent" ]
}

@test "security review on the author's model does not count" {
  [ "$(check zatwierdzona sonnet pass OPUS opus abc abc)" = "model-bezpieczenstwo" ]
}

@test "unknown model of a reviewer does not count" {
  [ "$(check zatwierdzona '' pass haiku opus abc abc)" = "model-recenzent" ]
}

@test "unknown author model blocks" {
  [ "$(check zatwierdzona sonnet pass haiku '' abc abc)" = "model-autor,model-recenzent,model-bezpieczenstwo" ]
}

@test "head moved after the verdicts blocks" {
  [ "$(check zatwierdzona sonnet pass haiku opus abc def)" = "sha" ]
}

@test "missing verdict blocks" {
  run bash -c "echo '{\"mode\":\"spec\",\"sha\":\"a\",\"headSha\":\"a\",\"authorModel\":\"opus\",\"verdicts\":[]}' | python3 '$ROOT/bin/lib/sw_merge.py' | paste -sd, -"
  [ "$output" = "werdykt-recenzent,werdykt-bezpieczenstwo" ]
}

@test "unknown mode blocks" {
  run bash -c "echo '{\"mode\":\"xyz\"}' | python3 '$ROOT/bin/lib/sw_merge.py'"
  [ "$output" = "tryb-xyz" ]
}

# kod <recenzent-wynik> <bezp-wynik> <requiredChecks-json> <checkRuns-json> [recenzent-model]
kod() {
  jq -nc --arg rr "$1" --arg br "$2" --arg rm "${5:-sonnet}" --argjson req "$3" --argjson runs "$4" \
    '{mode: "kod", sha: "abc", headSha: "abc", authorModel: "opus", requiredChecks: $req, checkRuns: $runs,
      verdicts: [{role: "recenzent", result: $rr, model: $rm}, {role: "bezpieczenstwo", result: $br, model: "haiku"}]}' \
    | python3 "$ROOT/bin/lib/sw_merge.py" | paste -sd, -
}
GREEN='[{"name":"checks","status":"completed","conclusion":"success"},{"name":"e2e","status":"completed","conclusion":"success"}]'
REQ='["checks","e2e"]'

@test "code mode: approve, pass and green required checks leave nothing unmet" {
  [ -z "$(kod approve pass "$REQ" "$GREEN")" ]
}

@test "code mode: the spec verdict word zatwierdzona is not an approve" {
  [ "$(kod zatwierdzona pass "$REQ" "$GREEN")" = "werdykt-recenzent" ]
}

@test "code mode: review changes blocks" {
  [ "$(kod changes pass "$REQ" "$GREEN")" = "werdykt-recenzent" ]
}

@test "code mode: security fail blocks" {
  [ "$(kod approve fail "$REQ" "$GREEN")" = "werdykt-bezpieczenstwo" ]
}

@test "code mode: reviewer on the author's model does not count" {
  [ "$(kod approve pass "$REQ" "$GREEN" opus)" = "model-recenzent" ]
}

@test "code mode: a failed required check blocks" {
  runs='[{"name":"checks","status":"completed","conclusion":"failure"},{"name":"e2e","status":"completed","conclusion":"success"}]'
  [ "$(kod approve pass "$REQ" "$runs")" = "check-checks" ]
}

@test "code mode: a check still running blocks" {
  runs='[{"name":"checks","status":"completed","conclusion":"success"},{"name":"e2e","status":"in_progress","conclusion":null}]'
  [ "$(kod approve pass "$REQ" "$runs")" = "check-e2e" ]
}

@test "code mode: neutral and skipped conclusions are not green" {
  runs='[{"name":"checks","status":"completed","conclusion":"neutral"},{"name":"e2e","status":"completed","conclusion":"skipped"}]'
  [ "$(kod approve pass "$REQ" "$runs")" = "check-checks,check-e2e" ]
}

@test "code mode: a missing named check-run blocks" {
  runs='[{"name":"checks","status":"completed","conclusion":"success"}]'
  [ "$(kod approve pass "$REQ" "$runs")" = "check-e2e" ]
}

@test "code mode: a repository without any check-run blocks" {
  [ "$(kod approve pass "$REQ" '[]')" = "check-checks,check-e2e" ]
}

@test "code mode: a differently named green check does not stand in for a required one" {
  runs='[{"name":"lint","status":"completed","conclusion":"success"},{"name":"e2e","status":"completed","conclusion":"success"}]'
  [ "$(kod approve pass "$REQ" "$runs")" = "check-checks" ]
}

@test "code mode: every run of a required name must be green" {
  runs='[{"name":"checks","status":"completed","conclusion":"success"},{"name":"checks","status":"completed","conclusion":"failure"},{"name":"e2e","status":"completed","conclusion":"success"}]'
  [ "$(kod approve pass "$REQ" "$runs")" = "check-checks" ]
}

@test "code mode: no configured required checks blocks" {
  [ "$(kod approve pass '[]' "$GREEN")" = "check-brak-konfiguracji" ]
}

@test "spec mode ignores check-runs" {
  [ -z "$(check zatwierdzona sonnet pass haiku opus abc abc)" ]
}

@test "the same model under different spellings is one model" {
  for spelling in opus 'opus[1m]' 'anthropic/opus[1m]' claude-opus-4-5 'Anthropic/Claude-Opus-4-5[1m]'; do
    [ "$(check zatwierdzona "$spelling" pass haiku opus abc abc)" = "model-recenzent" ]
    [ "$(check zatwierdzona sonnet pass "$spelling" 'anthropic/opus' abc abc)" = "model-bezpieczenstwo" ]
  done
}

@test "different families under different spellings are different models" {
  [ -z "$(check zatwierdzona 'anthropic/sonnet[1m]' pass claude-haiku-4-5 claude-opus-4-5 abc abc)" ]
}
