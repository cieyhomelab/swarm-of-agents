#!/usr/bin/env bats
# Unit: the sw-build workflow (S5 one module, S8), the sw-architekt skill and the stage switch.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  WF="$ROOT/workflows/sw-build.yml"
  WORK="$(mktemp -d)"
}

teardown() { rm -rf "$WORK"; }

@test "the workflow is valid, its loop equals fixRoundsPerPr and agents have explicit models" {
  run python3 "$ROOT/tests/tools/validate_workflows.py" "$WF"
  [ "$status" -eq 0 ]
  run python3 - "$WF" "$ROOT/config/sw.json" <<'PY'
import json, sys, yaml
doc = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
cfg = json.load(open(sys.argv[2]))
nodes = {n["id"]: n for n in doc["nodes"]}
assert nodes["rounds"]["max"] == cfg["fixRoundsPerPr"]
models = cfg["models"]
assert nodes["architect"]["model"] == models["architect"] == nodes["fix"]["model"]
assert nodes["review"]["model"] == models["reviewer"]
assert nodes["security"]["model"] == models["security"]
assert nodes["review"]["model"] != nodes["architect"]["model"]
for n in nodes.values():
    if n["type"] == "agent":
        allow = n.get("bashAllowlist")
        assert allow, n["id"]
        assert not any(a.startswith(("gh pr merge", "git push", "gh label")) for a in allow), n["id"]
print("ok")
PY
  [ "$status" -eq 0 ]
}

@test "S5/S8 every step starts with sw-limits and the merge goes through sw-merge kod" {
  run python3 - "$WF" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
nodes = {n["id"]: n for n in doc["nodes"]}
edges = {(e["from"], e["to"]) for e in doc["edges"]}
assert ("start", "limits-architect") in edges and ("limits-architect.pass", "architect") in edges
assert ("sha.pass", "limits-review") in edges and ("limits-review.pass", "review") in edges
assert ("rounds.repeat", "limits-fix") in edges and ("limits-fix.pass", "fix") in edges
assert ("security.pass", "limits-merge") in edges and ("limits-merge.pass", "merge") in edges
for n in ("limits-architect", "limits-review", "limits-fix", "limits-merge"):
    assert "bin/sw-limits" in nodes[n]["command"] and ("%s.fail" % n, "stopped") in edges, n
# review, CI and security all precede the merge; a red CI and remarks start a fix round
assert ("review.approve", "ci") in edges and ("ci.green", "security") in edges
assert ("review.changes", "rounds") in edges and ("ci.red", "rounds") in edges
assert ("rounds.exhausted", "pause-rounds") in edges and ("security.fail", "pause-security") in edges
assert ("arch-check.pass", "sha") in edges and ("arch-check.fail", "rounds") in edges
assert ("arch-check-fix.pass", "commit-fix") in edges and ("push-fix.done", "sha") in edges
cmd = nodes["merge"]["command"]
assert "merge-kod" in cmd and "{{nodes.sha.output}}" in cmd
for role, node in (("autor", "architect"), ("recenzent", "review"), ("bezpieczenstwo", "security")):
    assert f"{role}={{{{nodes.{node}.verdict}}}}@{{{{nodes.{node}.runId}}}}" in cmd, role
print("ok")
PY
  [ "$status" -eq 0 ]
}

@test "S5 the sw-architekt skill describes the contract sections, the form decision and requiredChecks" {
  f="$ROOT/skills/sw-architekt/SKILL.md"
  [ "$(sed -n 's/^name:[[:space:]]*//p' "$f" | head -1)" = sw-architekt ]
  for s in '## Udostępnia' '## Wymaga' '## Forma' 'część aplikacji' 'osobna usługa' 'docs/kontrakty/<modul>.md' 'requiredChecks' '`gotowa`'; do
    grep -qF -- "$s" "$f" || { echo "missing: $s"; return 1; }
  done
}

@test "the stage switch defaults to 1 and sw-create-repo seeds the sw-build workflow" {
  [ "$(jq -r .stage "$ROOT/config/sw.json")" = 1 ]
  [ -f "$ROOT/workflows/sw-build.yml" ]
  grep -q 'workflows/sw-build.yml' "$ROOT/bin/sw-create-repo"
}

arch() { # arch <requiredChecks-json> — runs the check in $WORK
  cd "$WORK" || return 1
  conf="$WORK/sw.json"; jq --argjson r "$1" '.requiredChecks = $r' "$ROOT/config/sw.json" > "$conf"
  SW_CONFIG="$conf" run "$ROOT/bin/sw-architektura-check"
}

complete_arch() {
  mkdir -p "$WORK/docs/kontrakty" "$WORK/.ai/specs" "$WORK/.github/workflows"
  printf '# Spec\n\n### S1: Menu\nx\n\n### S2: Lista\ny\n' > "$WORK/.ai/specs/spec.md"
  printf '# planer\n\n## Udostępnia\n- ekran menu\n\n## Wymaga\nbrak\n\n## Forma\nczęść aplikacji\nJedna aplikacja.\n\n## Scenariusze\nS1, S2\n' > "$WORK/docs/kontrakty/planer.md"
  printf 'name: CI\non:\n  pull_request:\n  push:\n    branches: [main]\njobs:\n  checks:\n    runs-on: ubuntu-latest\n    steps: [{run: "true"}]\n  e2e:\n    name: e2e\n    runs-on: ubuntu-latest\n    steps: [{run: "true"}]\n' > "$WORK/.github/workflows/ci.yml"
}

@test "S5 a complete architecture passes the check" {
  complete_arch
  arch '["checks","e2e"]'
  [ "$status" -eq 0 ]
  [ "$output" = "WYNIK: OK" ]
}

@test "S5 a scenario assigned to no module fails the check and lands in uwagi.md" {
  complete_arch
  sed -i 's/^S1, S2$/S1/' "$WORK/docs/kontrakty/planer.md"
  arch '["checks","e2e"]'
  [ "$status" -eq 1 ]
  [[ "$output" == *"scenariusz S2 nie jest przypisany"* ]]
  grep -q 'S2' "$WORK/.ai/sw-run/uwagi.md"
}

@test "S5 a contract without the form decision fails the check" {
  complete_arch
  sed -i 's/^część aplikacji$/nie wiem/' "$WORK/docs/kontrakty/planer.md"
  arch '["checks","e2e"]'
  [ "$status" -eq 1 ]
  [[ "$output" == *"sekcja Forma"* ]]
}

@test "S5 a CI job missing from requiredChecks fails the check" {
  complete_arch
  arch '["checks","e2e","security"]'
  [ "$status" -eq 1 ]
  [[ "$output" == *"nie ma zadania o nazwie 'security'"* ]]
}

@test "S5 a CI workflow that does not run on pull_request fails the check" {
  complete_arch
  sed -i '/^  pull_request:$/d' "$WORK/.github/workflows/ci.yml"
  arch '["checks","e2e"]'
  [ "$status" -eq 1 ]
  [[ "$output" == *"pull_request"* ]]
}

@test "S5 a missing contract fails the check" {
  complete_arch
  rm "$WORK/docs/kontrakty/planer.md"
  arch '["checks","e2e"]'
  [ "$status" -eq 1 ]
  [[ "$output" == *"brak kontraktu modułu"* ]]
}
