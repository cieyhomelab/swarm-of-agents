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

@test "code mode is not implemented in stage 1" {
  run bash -c "echo '{\"mode\":\"kod\"}' | python3 '$ROOT/bin/lib/sw_merge.py'"
  [ "$output" = "tryb-kod" ]
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
