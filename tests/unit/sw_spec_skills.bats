#!/usr/bin/env bats
# Unit: structure of the skills and of the sw-spec workflow (spec S4). The behaviour
# of the agents is not tested in CI (AGENTS.md); these tests pin the contract the
# other parts rely on: verdict names, models, rounds, the order of the nodes and the
# missing right of the agents to change state.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  WF="$ROOT/workflows/sw-spec.yml"
}

skill_name() { sed -n 's/^name:[[:space:]]*//p' "$ROOT/skills/$1/SKILL.md" | head -1; }

@test "the new skills have a valid header and the right model" {
  [ "$(skill_name sw-recenzent)" = "sw-recenzent" ]
  [ "$(skill_name sw-bezpieczenstwo)" = "sw-bezpieczenstwo" ]
  grep -q 'modelu `reviewer`' "$ROOT/skills/sw-recenzent/SKILL.md"
  grep -q 'modelu `security`' "$ROOT/skills/sw-bezpieczenstwo/SKILL.md"
}

@test "the skills name the verdicts the workflow branches on" {
  grep -q '`zatwierdzona`' "$ROOT/skills/sw-recenzent/SKILL.md"
  grep -q '`uwagi`' "$ROOT/skills/sw-recenzent/SKILL.md"
  grep -q '`pass`' "$ROOT/skills/sw-bezpieczenstwo/SKILL.md"
  grep -q '`fail`' "$ROOT/skills/sw-bezpieczenstwo/SKILL.md"
  grep -q '`gotowa`' "$ROOT/skills/sw-analityk/SKILL.md"
}

@test "the analyst skill has an autonomous spec mode with the assumptions section and no personal data" {
  skill="$ROOT/skills/sw-analityk/SKILL.md"
  grep -q '^# Tryb spec' "$skill"
  grep -q '## Założenia' "$skill"
  grep -qi 'najprostszą, odwracalną opcją' "$skill"
  grep -qi 'Bez danych osobowych' "$skill"
  # spec mode never asks the owner
  section="$(sed -n '/^# Tryb spec/,$p' "$skill")"
  [[ "$section" != *"CEZ:ASK {"* ]]
  [[ "$section" == *"nie zadajesz pytań"* ]]
}

@test "the security skill checks sw:ustalenia and the excluded categories" {
  skill="$ROOT/skills/sw-bezpieczenstwo/SKILL.md"
  grep -qF '<!-- sw:ustalenia -->' "$skill"
  grep -qF 'kategorie-wykluczone.md' "$skill"
  grep -qi 'dane osobowe' "$skill"
  grep -qi 'sekret' "$skill"
}

@test "the reviewer is independent and checks that criteria are testable end to end" {
  skill="$ROOT/skills/sw-recenzent/SKILL.md"
  grep -qi 'test E2E' "$skill"
  grep -qi 'rozumowania analityka' "$skill"
}

@test "the agents of sw-spec use the models of config/sw.json and the reviewers differ from the author" {
  run python3 - "$WF" "$ROOT/config/sw.json" <<'PY'
import json, sys, yaml
doc = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
models = json.load(open(sys.argv[2], encoding="utf-8"))["models"]
nodes = {n["id"]: n for n in doc["nodes"]}
role = {"analyst": "analyst", "fix": "analyst", "review": "reviewer", "security": "security", "sec-ustalenia": "security"}
for node_id, key in role.items():
    n = nodes[node_id]
    assert n["type"] == "agent" and n["runner"] == "claude", node_id
    assert n["model"] == models[key], (node_id, n["model"], models[key])
assert nodes["review"]["model"] != nodes["analyst"]["model"]
assert nodes["security"]["model"] != nodes["analyst"]["model"]
print("ok")
PY
  [ "$status" -eq 0 ]
}

@test "the fix loop equals specFixRounds" {
  run python3 - "$WF" "$ROOT/config/sw.json" <<'PY'
import json, sys, yaml
doc = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
rounds = json.load(open(sys.argv[2], encoding="utf-8"))["specFixRounds"]
loop = [n for n in doc["nodes"] if n["type"] == "loop"]
assert len(loop) == 1 and loop[0]["max"] == rounds, loop
print("ok")
PY
  [ "$status" -eq 0 ]
}

@test "the agents of sw-spec cannot change labels, issues or pull requests" {
  run python3 - "$WF" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
for n in doc["nodes"]:
    if n["type"] != "agent":
        continue
    allow = n["bashAllowlist"]
    assert allow, n["id"]
    for entry in allow:
        assert entry.split()[0] in ("gh", "git", "ls", "cat"), (n["id"], entry)
        if entry.startswith("gh "):
            assert entry == "gh issue view *", (n["id"], entry)
        if entry.startswith("git "):
            assert entry == "git diff *", (n["id"], entry)
    assert "Bash" not in n["allowedTools"] or allow
print("ok")
PY
  [ "$status" -eq 0 ]
}

@test "the workflow checks sw:ustalenia before the analyst and merges only after both reviews" {
  run python3 - "$WF" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
nodes = {n["id"]: n for n in doc["nodes"]}
edges = {(e["from"], e["to"]) for e in doc["edges"]}
assert ("start", "sec-ustalenia") in edges
assert ("sec-ustalenia.pass", "analyst") in edges and ("sec-ustalenia.fail", "stopped") in edges
assert ("review.zatwierdzona", "security") in edges and ("review.uwagi", "rounds") in edges
assert ("rounds.exhausted", "pause-rounds") in edges and ("pause-rounds.pass", "stopped") in edges
assert ("security.pass", "pr-body") in edges and ("pr-body.pass", "merge") in edges
assert ("merge.pass", "notify") in edges and ("security.fail", "pause-security") in edges and ("pause-security.pass", "stopped") in edges
# the merge gets every verdict and run id from node outputs, never from comments
cmd = nodes["merge"]["command"]
for role, node in (("autor", "analyst"), ("recenzent", "review"), ("bezpieczenstwo", "security")):
    assert f"{role}={{{{nodes.{node}.verdict}}}}@{{{{nodes.{node}.runId}}}}" in cmd, role
assert "{{nodes.sha.output}}" in cmd
# the commit that the reviewers judge is captured after every push
assert ("draft-pr.created", "sha") in edges and ("push-fix.done", "sha") in edges and ("sha.pass", "review") in edges
print("ok")
PY
  [ "$status" -eq 0 ]
}

@test "sw-create-repo seeds the sw-spec workflow that exists in the repository" {
  [ -f "$ROOT/workflows/sw-spec.yml" ]
  grep -q 'workflows/sw-spec.yml' "$ROOT/bin/sw-create-repo"
}
