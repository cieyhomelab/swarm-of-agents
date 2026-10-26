#!/usr/bin/env bats
# Unit tests for tests/tools/validate_workflows.py.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  TMP="$(mktemp -d)"
}

teardown() { rm -rf "$TMP"; }

write() { cat > "$TMP/$1"; }

@test "repository workflows are valid" {
  run python3 "$ROOT/tests/tools/validate_workflows.py" "$ROOT"/workflows/*.yml
  [ "$status" -eq 0 ]
}

@test "workflow without sw- prefix is rejected" {
  write sh-x.yml <<'EOF'
version: 2
name: sh-x
nodes:
  - { id: start, type: start }
  - { id: done, type: end, status: success }
edges:
  - { from: start, to: done }
EOF
  run python3 "$ROOT/tests/tools/validate_workflows.py" "$TMP/sh-x.yml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"must start with sw-"* ]]
}

@test "edge from a port the node does not have is rejected" {
  write sw-x.yml <<'EOF'
version: 2
name: sw-x
nodes:
  - { id: start, type: start }
  - { id: gate, type: check, command: "true" }
  - { id: done, type: end, status: success }
edges:
  - { from: start, to: gate }
  - { from: gate.green, to: done }
EOF
  run python3 "$ROOT/tests/tools/validate_workflows.py" "$TMP/sw-x.yml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"has no port 'green'"* ]]
}

@test "agent verdicts become valid ports" {
  write sw-y.yml <<'EOF'
version: 2
name: sw-y
nodes:
  - { id: start, type: start }
  - { id: review, type: agent, runner: claude, model: sonnet, prompt: "review", verdicts: [zatwierdzona, uwagi] }
  - { id: done, type: end, status: success }
  - { id: fix, type: end, status: failed }
edges:
  - { from: start, to: review }
  - { from: review.zatwierdzona, to: done }
  - { from: review.uwagi, to: fix }
EOF
  run python3 "$ROOT/tests/tools/validate_workflows.py" "$TMP/sw-y.yml"
  [ "$status" -eq 0 ]
}

@test "agent node without runner claude or model is rejected" {
  write sw-z.yml <<'YAML'
version: 2
name: sw-z
nodes:
  - { id: start, type: start }
  - { id: work, type: agent, runner: codex, prompt: "x" }
  - { id: done, type: end, status: success }
edges:
  - { from: start, to: work }
  - { from: work.done, to: done }
YAML
  run python3 "$ROOT/tests/tools/validate_workflows.py" "$TMP/sw-z.yml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"must set runner: claude"* ]]
  [[ "$output" == *"explicit model"* ]]
}

@test "timeout port needs timeoutMs" {
  write sw-t.yml <<'YAML'
version: 2
name: sw-t
nodes:
  - { id: start, type: start }
  - { id: ask, type: ask-user, question: "ok?" }
  - { id: done, type: end, status: success }
edges:
  - { from: start, to: ask }
  - { from: ask.answered, to: done }
  - { from: ask.timeout, to: done }
YAML
  run python3 "$ROOT/tests/tools/validate_workflows.py" "$TMP/sw-t.yml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"has no port 'timeout'"* ]]
}

@test "cycle without a loop node and unreachable node are rejected" {
  write sw-c.yml <<'YAML'
version: 2
name: sw-c
nodes:
  - { id: start, type: start }
  - { id: a, type: check, command: "true" }
  - { id: b, type: check, command: "true" }
  - { id: lost, type: end, status: success }
edges:
  - { from: start, to: a }
  - { from: a.pass, to: b }
  - { from: b.pass, to: a }
YAML
  run python3 "$ROOT/tests/tools/validate_workflows.py" "$TMP/sw-c.yml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cycle without a loop node"* ]]
  [[ "$output" == *"'lost' is unreachable"* ]]
}

@test "cycle through a loop node is accepted" {
  write sw-l.yml <<'YAML'
version: 2
name: sw-l
nodes:
  - { id: start, type: start }
  - { id: rounds, type: loop, max: 2 }
  - { id: a, type: check, command: "true" }
  - { id: done, type: end, status: success }
  - { id: out, type: end, status: failed }
edges:
  - { from: start, to: rounds }
  - { from: rounds.repeat, to: a }
  - { from: rounds.exhausted, to: out }
  - { from: a.pass, to: done }
  - { from: a.fail, to: rounds }
YAML
  run python3 "$ROOT/tests/tools/validate_workflows.py" "$TMP/sw-l.yml"
  [ "$status" -eq 0 ]
}

@test "the attempt loop of sw-sweep equals ideaAttemptsPerCycle" {
  max="$(python3 -c 'import yaml,sys; d=yaml.safe_load(open(sys.argv[1])); print([n["max"] for n in d["nodes"] if n["id"]=="attempts"][0])' "$ROOT/workflows/sw-sweep.yml")"
  [ "$max" = "$(jq -r .ideaAttemptsPerCycle "$ROOT/config/sw.json")" ]
}
