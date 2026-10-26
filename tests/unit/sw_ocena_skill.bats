#!/usr/bin/env bats
# Unit: structure of the sw-analityk skill and the sw-ocena workflow (spec S2, S3).
# The behaviour of the agent itself is not tested in CI (AGENTS.md); these tests
# pin the contract the other parts rely on: the decision card, the summary
# before the decision, the comment markers and the missing right to change labels.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SKILL="$ROOT/skills/sw-analityk/SKILL.md"
  WF="$ROOT/workflows/sw-ocena.yml"
}

@test "the skill carries the decision card exactly as in the spec" {
  grep -qxF 'CEZ:ASK {"questions":[{"header":"Decyzja","question":"Co robimy z tym pomysłem?","options":[{"label":"Zatwierdź"},{"label":"Odrzuć"}]}]}' "$SKILL"
  line="$(grep -F 'CEZ:ASK {' "$SKILL" | head -1)"
  printf '%s' "${line#CEZ:ASK }" | jq -e '.questions[0].options | map(.label) == ["Zatwierdź", "Odrzuć"]'
}

@test "the skill sets the task title and requires a summary before the decision" {
  grep -q 'CEZ:TITLE=Pomysł: ' "$SKILL"
  grep -qi 'podsumowanie ustaleń' "$SKILL"
  summary_line="$(grep -n 'Podsumowanie przed decyzją' "$SKILL" | head -1 | cut -d: -f1)"
  ask_line="$(grep -n 'Karta decyzji' "$SKILL" | head -1 | cut -d: -f1)"
  [ "$summary_line" -lt "$ask_line" ]
}

@test "the skill writes the sw:ustalenia and sw:odrzucenie comments without personal data" {
  grep -qF '<!-- sw:ustalenia -->' "$SKILL"
  grep -qF '<!-- sw:odrzucenie -->' "$SKILL"
  grep -qi 'Bez danych osobowych' "$SKILL"
  grep -qF 'Decyzja: Zatwierdź' "$SKILL"
}

@test "the skill header is valid and names the analyst model" {
  [ "$(sed -n 1p "$SKILL")" = "---" ]
  [ "$(sed -n 's/^name:[[:space:]]*//p' "$SKILL" | head -1)" = "sw-analityk" ]
  grep -q 'analyst' "$SKILL"
}

@test "the sw-ocena agent cannot change labels or issue state" {
  run python3 - "$WF" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
agents = [n for n in doc["nodes"] if n["type"] == "agent"]
assert len(agents) == 1, agents
a = agents[0]
assert a["skill"] == "sw-analityk" and a["runner"] == "claude" and a["model"] == "opus"
allow = a["bashAllowlist"]
assert allow, "bashAllowlist must be explicit"
for entry in allow:
    assert "issue edit" not in entry and "api" not in entry.split()[:2], entry
    assert entry.split()[0] in ("gh", "mktemp"), entry
assert "gh issue comment *" in allow
assert "Edit" not in a["allowedTools"]
# the skill writes the comment body with Write to a mktemp file, so both must be allowed
assert "Write" in a["allowedTools"] and "mktemp" in allow and "mktemp *" in allow
print("ok")
PY
  [ "$status" -eq 0 ]
}

@test "the model of the analyst agent matches config/sw.json" {
  model="$(jq -r '.models.analyst' "$ROOT/config/sw.json")"
  run grep -E "^    model: $model\$" "$WF"
  [ "$status" -eq 0 ]
}
