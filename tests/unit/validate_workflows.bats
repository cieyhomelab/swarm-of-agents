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
  - { id: review, type: agent, prompt: "review", verdicts: [zatwierdzona, uwagi] }
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
