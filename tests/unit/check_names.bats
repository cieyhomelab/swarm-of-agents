#!/usr/bin/env bats
# Unit tests for tests/tools/check-names.sh (coexistence naming rule).

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  FAKE="$(mktemp -d)"
  mkdir -p "$FAKE/skills" "$FAKE/workflows" "$FAKE/bin" "$FAKE/config/automations"
}

teardown() { rm -rf "$FAKE"; }

check() { SW_CHECK_ROOT="$FAKE" run bash "$ROOT/tests/tools/check-names.sh"; }

@test "this repository follows the naming rule" {
  run bash "$ROOT/tests/tools/check-names.sh"
  [ "$status" -eq 0 ]
}

@test "skill directory with sh- prefix fails" {
  mkdir -p "$FAKE/skills/sh-analityk"
  printf -- '---\nname: sh-analityk\n---\n' > "$FAKE/skills/sh-analityk/SKILL.md"
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"must start with sw-"* ]]
}

@test "skill name field must match its directory" {
  mkdir -p "$FAKE/skills/sw-analityk"
  printf -- '---\nname: sh-analityk\n---\n' > "$FAKE/skills/sw-analityk/SKILL.md"
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"declares name 'sh-analityk'"* ]]
}

@test "automation named 'sh: ...' fails" {
  echo '{"name":"sh: realizacja"}' > "$FAKE/config/automations/a.json"
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"must start with 'sw: '"* ]]
}

@test "script and workflow without sw- prefix fail" {
  touch "$FAKE/bin/sh-notify" "$FAKE/workflows/sh-sweep.yml"
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"bin/sh-notify"* ]]
  [[ "$output" == *"sh-sweep.yml"* ]]
}

@test "system label without sw- prefix fails" {
  echo '{"system":["sw-pomysl","sh-architekt"]}' > "$FAKE/config/labels.json"
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"'sh-architekt'"* ]]
}

@test "reference to an sh- element inside a workflow or script fails" {
  printf 'nodes:\n  - { id: x, type: agent, skill: sh-inzynier }\n' > "$FAKE/workflows/sw-a.yml"
  printf '#!/usr/bin/env bash\n~/sh-skills/bin/sh-notify spec\n' > "$FAKE/bin/sw-b"
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"workflows/sw-a.yml"* ]]
  [[ "$output" == *"bin/sw-b"* ]]
}

@test "the etap-1 handover script may reference sh-start" {
  printf '#!/usr/bin/env bash\n# starts sh-start\n' > "$FAKE/bin/sw-handover-sh"
  check
  [ "$status" -eq 0 ]
}
