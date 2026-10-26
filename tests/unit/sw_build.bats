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

@test "S6/S7 the module phase: every agent follows sw-limits, rounds equal fixRoundsPerPr, models differ from the author" {
  run python3 - "$WF" "$ROOT/config/sw.json" <<'PY'
import json, sys, yaml
doc = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
cfg = json.load(open(sys.argv[2]))
nodes = {n["id"]: n for n in doc["nodes"]}
edges = {(e["from"], e["to"]) for e in doc["edges"]}
for loop in ("rounds", "rounds-mod", "rounds-test"):
    assert nodes[loop]["max"] == cfg["fixRoundsPerPr"], loop
for limits, agent in (("limits-engineer", "engineer"), ("limits-review-mod", "review-mod"), ("limits-fix-mod", "fix-mod"),
                      ("limits-tester", "tester"), ("limits-fix-test", "fix-test")):
    assert "bin/sw-limits" in nodes[limits]["command"] and (f"{limits}.pass", agent) in edges and (f"{limits}.fail", "stopped") in edges, limits
for limits in ("limits-merge-mod", "limits-test"):
    assert "bin/sw-limits" in nodes[limits]["command"] and (f"{limits}.fail", "stopped") in edges, limits
models = cfg["models"]
for n in ("engineer", "fix-mod", "fix-test"):
    assert nodes[n]["model"] == models["engineer"] and nodes[n]["skill"] == "sw-inzynier", n
assert nodes["tester"]["model"] == models["reviewer"] and nodes["tester"]["skill"] == "sw-tester"
assert nodes["review-mod"]["model"] == models["reviewer"] != nodes["engineer"]["model"]
assert nodes["security-mod"]["model"] == models["security"]
# the architecture merge leads to the module, the module PR to the tests, only a pass to the review state
assert ("merge.pass", "state-impl") in edges and ("report-merged.fail", "state-integ") in edges and ("merge-mod.pass", "report-merged") in edges
assert ("tester.pass", "state-review") in edges and ("state-review.pass", "limits-app") in edges
assert ("e2e-check.pass", "e2e-run") in edges and ("e2e-run.pass", "limits-tester") in edges
for failing in ("e2e-check.fail", "e2e-run.fail", "tester.fail"):
    assert (failing, "rounds-test") in edges, failing
assert ("rounds-test.exhausted", "pause-rounds-test") in edges and ("rounds-mod.exhausted", "pause-rounds-mod") in edges
assert ("security-mod.fail", "pause-security-mod") in edges
# the review chain of the module PR precedes the merge; remarks and a red CI start a fix round
assert ("review-mod.approve", "ci-mod") in edges and ("ci-mod.green", "security-mod") in edges
assert ("review-mod.changes", "rounds-mod") in edges and ("ci-mod.red", "rounds-mod") in edges
assert ("mod-check.fail", "rounds-mod") in edges and ("push-fix-mod.done", "sha-mod") in edges
cmd = nodes["merge-mod"]["command"]
assert "merge-kod" in cmd and "{{nodes.sha-mod.output}}" in cmd
for role, node in (("autor", "engineer"), ("recenzent", "review-mod"), ("bezpieczenstwo", "security-mod")):
    assert f"{role}={{{{nodes.{node}.verdict}}}}@{{{{nodes.{node}.runId}}}}" in cmd, role
for agent in ("engineer", "fix-mod", "fix-test", "review-mod", "security-mod", "tester"):
    assert nodes[agent]["bashAllowlist"] and not any(a.startswith(("gh pr merge", "git push", "gh label")) for a in nodes[agent]["bashAllowlist"])
print("ok")
PY
  [ "$status" -eq 0 ]
}

@test "S6/S7 the sw-inzynier and sw-tester skills describe coverage, E2E tests and verdicts" {
  f="$ROOT/skills/sw-inzynier/SKILL.md"
  [ "$(sed -n 's/^name:[[:space:]]*//p' "$f" | head -1)" = sw-inzynier ]
  for s in '## Udostępnia' '## Pokrycie' '=>' 'S<n>' 'tests/e2e/' '`gotowa`' 'skip' 'engineer'; do
    grep -qF -- "$s" "$f" || { echo "missing: $s"; return 1; }
  done
  f="$ROOT/skills/sw-tester/SKILL.md"
  [ "$(sed -n 's/^name:[[:space:]]*//p' "$f" | head -1)" = sw-tester ]
  for s in 'scripts/test-e2e.sh' 'S<n>' '`pass`' '`fail`' 'reviewer' '.ai/sw-run/uwagi.md'; do
    grep -qF -- "$s" "$f" || { echo "missing: $s"; return 1; }
  done
}

pokrycie() { # pokrycie <modul|e2e> — runs the check in $WORK
  cd "$WORK" || return 1
  run "$ROOT/bin/sw-pokrycie-check" "$1"
}

complete_impl() {
  mkdir -p "$WORK/docs/kontrakty" "$WORK/.ai/specs" "$WORK/tests/unit" "$WORK/tests/e2e"
  printf '# Spec\n\n### S1: Menu\nx\n\n### S2: Lista\ny\n' > "$WORK/.ai/specs/spec.md"
  printf '# planer\n\n## Udostępnia\n- ekran menu\n- lista zakupów\n\n## Wymaga\nbrak\n\n## Forma\nczęść aplikacji\nx\n\n## Scenariusze\nS1, S2\n\n## Pokrycie\n- ekran menu => tests/unit/menu.bats\n- lista zakupów => tests/unit/lista.bats\n' > "$WORK/docs/kontrakty/planer.md"
  echo 'ok' > "$WORK/tests/unit/menu.bats"; echo 'ok' > "$WORK/tests/unit/lista.bats"
  printf '@test "S1: menu" { true; }\n@test "S2: lista" { true; }\n' > "$WORK/tests/e2e/app.bats"
}

@test "S6 every 'udostępnia' item with a test passes the module check" {
  complete_impl
  pokrycie modul
  [ "$status" -eq 0 ]
  [ "$output" = "WYNIK: OK" ]
}

@test "S6 an item without a line in Pokrycie fails the module check and lands in uwagi.md" {
  complete_impl
  sed -i '/lista zakupów => /d' "$WORK/docs/kontrakty/planer.md"
  pokrycie modul
  [ "$status" -eq 1 ]
  [[ "$output" == *"pozycja 'lista zakupów' nie ma testu"* ]]
  grep -q 'lista zakupów' "$WORK/.ai/sw-run/uwagi.md"
}

@test "S6 a missing, empty or escaping test file fails the module check" {
  complete_impl
  rm "$WORK/tests/unit/menu.bats"; : > "$WORK/tests/unit/lista.bats"
  pokrycie modul
  [ "$status" -eq 1 ]
  [ "$(grep -c 'nie istnieje albo jest pusty' <<<"$output")" -eq 2 ]
  complete_impl
  sed -i 's#tests/unit/menu.bats#../../etc/passwd#' "$WORK/docs/kontrakty/planer.md"
  pokrycie modul
  [ "$status" -eq 1 ]
  [[ "$output" == *"nie istnieje albo jest pusty"* ]]
}

@test "S7 every scenario named in an E2E test passes the e2e check" {
  complete_impl
  pokrycie e2e
  [ "$status" -eq 0 ]
  [ "$output" = "WYNIK: OK" ]
}

@test "S7 a scenario without an E2E test fails the e2e check" {
  complete_impl
  sed -i '/S2/d' "$WORK/tests/e2e/app.bats"
  pokrycie e2e
  [ "$status" -eq 1 ]
  [[ "$output" == *"scenariusz S2 nie ma testu E2E"* ]]
}

@test "S7 a skipped or pending E2E test fails the e2e check" {
  complete_impl
  printf '@test "S2: lista" {\n  skip "later"\n}\n' >> "$WORK/tests/e2e/app.bats"
  pokrycie e2e
  [ "$status" -eq 1 ]
  [[ "$output" == *"test E2E pominięty albo oczekujący"* ]]
}

@test "S7 the words skip and pending in names, assertions and comments do not fail the e2e check" {
  complete_impl
  printf '@test "S1: nowe zamówienie ma status pending" {\n  # skip nothing, xfail nothing\n  [ "$(status)" = pending ]\n}\n' >> "$WORK/tests/e2e/app.bats"
  printf 'it("S2 skip link", () => { expect(order.status).toBe("pending"); });\n' > "$WORK/tests/e2e/app.spec.ts"
  pokrycie e2e
  [ "$status" -eq 0 ]
  [ "$output" = "WYNIK: OK" ]
}

@test "S7 framework skip constructs fail the e2e check" {
  complete_impl
  printf 'test.skip("S1 x", () => {});\n' > "$WORK/tests/e2e/a.spec.ts"
  printf '@pytest.mark.skip(reason="x")\nxit("y", () => {});\n' > "$WORK/tests/e2e/b.py"
  pokrycie e2e
  [ "$status" -eq 1 ]
  [[ "$output" == *"a.spec.ts:1: test E2E pominięty"* ]]
  [[ "$output" == *"b.py:1: test E2E pominięty"* ]]
  [[ "$output" == *"b.py:2: test E2E pominięty"* ]]
}

@test "S7 Go, Mocha, Jest each and unittest skip constructs fail the e2e check" {
  complete_impl
  printf 'func TestS1(t *testing.T) {\n\tt.Skip("later")\n\tt.Skipf("x %%d", 1)\n\tt.SkipNow()\n}\n' > "$WORK/tests/e2e/a_test.go"
  printf 'it("S1 x", function () { this.skip(); });\nit.skip.each([1])("a", () => {});\n' > "$WORK/tests/e2e/b.spec.ts"
  printf 'def test_s1(self):\n    self.skipTest("x")\n    pytest.importorskip("m")\n' > "$WORK/tests/e2e/c.py"
  pokrycie e2e
  [ "$status" -eq 1 ]
  for m in a_test.go:2 a_test.go:3 a_test.go:4 b.spec.ts:1 b.spec.ts:2 c.py:2 c.py:3; do
    [[ "$output" == *"$m: test E2E pominięty"* ]]
  done
}

@test "S7 skip-like words in Go, Mocha and unittest names do not fail the e2e check" {
  complete_impl
  printf 'func TestS1(t *testing.T) {\n\tt.Run("S1 skip", nil)\n\tlist.skip(1)\n}\n' > "$WORK/tests/e2e/a_test.go"
  printf 'def test_s2(self):\n    self.assertTrue(skipTest_ok)\n' > "$WORK/tests/e2e/c.py"
  pokrycie e2e
  [ "$status" -eq 0 ]
}

@test "S7 S1 does not satisfy S10 (identifiers are compared whole)" {
  complete_impl
  printf '\n### S10: Eksport\nz\n' >> "$WORK/.ai/specs/spec.md"
  pokrycie e2e
  [ "$status" -eq 1 ]
  [[ "$output" == *"scenariusz S10"* ]]
}

@test "S9 the security review of the whole application: nodes, loop equals fixRoundsPerPr, report only through the PR pipeline" {
  run python3 - "$WF" "$ROOT/config/sw.json" <<'PY'
import json, sys, yaml
doc = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
cfg = json.load(open(sys.argv[2]))
nodes = {n["id"]: n for n in doc["nodes"]}
edges = {(e["from"], e["to"]) for e in doc["edges"]}
assert nodes["rounds-app"]["max"] == cfg["fixRoundsPerPr"]
sec = nodes["security-app"]
assert sec["skill"] == "sw-bezpieczenstwo" and sec["model"] == cfg["models"]["security"] and sec["verdicts"] == ["pass", "fail"]
assert nodes["fix-app"]["model"] == cfg["models"]["engineer"] != sec["model"]
# the review follows the green tests and the stage "przeglad", the verdict is judged by the script
assert ("state-review.pass", "limits-app") in edges and ("limits-app.pass", "security-app") in edges
assert "bin/sw-limits" in nodes["limits-app"]["command"]
assert "bin/sw-przeglad" in nodes["app-check"]["command"] and "{{nodes.security-app.verdict}}" in nodes["app-check"]["command"]
assert ("security-app.pass", "app-check") in edges and ("security-app.fail", "app-check") in edges
# a failing review starts a fix round whose fix goes through a new PR; exhausted rounds pause
assert ("app-check.fail", "rounds-app") in edges and ("rounds-app.repeat", "limits-fix-app") in edges
assert ("fix-app.gotowa", "commit-mod") in edges and ("rounds-app.exhausted", "pause-rounds-app") in edges
# the report is committed and goes through the review, CI, security and merge of the module PR; only then the task ends
assert ("app-check.pass", "once-report") in edges and ("commit-report.done", "push-mod") in edges
assert ("merge-mod.pass", "report-merged") in edges and ("report-merged.pass", "state-deploy") in edges
assert ("state-review.pass", "done") not in edges and ("report-merged.pass", "done") not in edges
print("ok")
PY
  [ "$status" -eq 0 ]
}

@test "S9 the sw-bezpieczenstwo skill describes the mode aplikacja: four points, przeglad.json and the verdict" {
  f="$ROOT/skills/sw-bezpieczenstwo/SKILL.md"
  for s in '## Tryb aplikacja' 'kategorii wykluczonych' 'sekretów' 'uwierzytelnienia' 'Jedno konto właściciela' '.ai/sw-run/przeglad.json' 'docs/security/<data>-raport.md'; do
    grep -qF -- "$s" "$f" || { echo "missing: $s"; return 1; }
  done
}

@test "S10 the deployment: wdrazanie, limits, sw-deploy, retries equal retriesPerTask, wdrozony only after a deployment, pause when exhausted" {
  run python3 - "$WF" "$ROOT/config/sw.json" <<'PY'
import json, sys, yaml
doc = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
cfg = json.load(open(sys.argv[2]))
nodes = {n["id"]: n for n in doc["nodes"]}
edges = {(e["from"], e["to"]) for e in doc["edges"]}
assert nodes["rounds-deploy"]["max"] == cfg["retriesPerTask"]
assert "bin/sw-stan\" przeglad wdrazanie" in nodes["state-deploy"]["command"]
assert "bin/sw-limits" in nodes["limits-deploy"]["command"]
assert "bin/sw-deploy" in nodes["deploy"]["command"] and "bin/sw-wdrozony" in nodes["finish"]["command"]
# the order: the merged report, the state, the limits, the deployment, then the state "wdrozony" and the end
for a, b in [("state-deploy.pass", "limits-deploy"), ("limits-deploy.pass", "deploy"), ("deploy.pass", "finish"), ("finish.pass", "done")]:
    assert (a, b) in edges, (a, b)
# only a deployment leads to "done"
assert {e["from"] for e in doc["edges"] if e["to"] == "done"} == {"finish.pass"}
# a failure retries; exhausted retries pause the project
assert ("deploy.fail", "rounds-deploy") in edges and ("finish.fail", "rounds-deploy") in edges
assert ("rounds-deploy.repeat", "limits-deploy") in edges and ("rounds-deploy.exhausted", "pause-deploy") in edges
assert "sw-spec-pr\" pause" in nodes["pause-deploy"]["command"]
print("ok")
PY
  [ "$status" -eq 0 ]
}
