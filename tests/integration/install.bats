#!/usr/bin/env bats
# Integration: scripts/install.sh next to an existing sh-skills installation.
# Spec, "Współistnienie z sh-skills": installing sw-* leaves sh-* untouched.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  WORK="$(mktemp -d)"
  SKILLS="$WORK/home/.claude/skills"
  OLD="$WORK/sh-skills/skills"
  NEW="$WORK/swarm"
  mkdir -p "$SKILLS" "$OLD/sh-analityk" "$OLD/sh-kierownik" "$NEW/skills/sw-analityk" "$NEW/skills/sw-generator"
  echo old > "$OLD/sh-analityk/SKILL.md"
  ln -s "$OLD/sh-analityk" "$SKILLS/sh-analityk"
  ln -s "$OLD/sh-kierownik" "$SKILLS/sh-kierownik"
  mkdir -p "$SKILLS/om-dev-status"
  echo om > "$SKILLS/om-dev-status/SKILL.md"
  snapshot_before="$(snapshot)"
}

teardown() { rm -rf "$WORK"; }

# Everything that is not sw-*: names, link targets and file contents.
snapshot() {
  (cd "$SKILLS" && find . -mindepth 1 -not -path './sw-*' -printf '%p %l\n' | sort
   find -L . -mindepth 2 -type f -not -path './sw-*' -exec sha256sum {} + | sort)
}

install() { SW_INSTALL_ROOT="$NEW" run bash "$ROOT/scripts/install.sh" --skills-dir "$SKILLS" "$@"; }

@test "sw-* skills are linked next to sh-* and others" {
  install
  [ "$status" -eq 0 ]
  [ "$(readlink "$SKILLS/sw-analityk")" = "$NEW/skills/sw-analityk" ]
  [ "$(readlink "$SKILLS/sw-generator")" = "$NEW/skills/sw-generator" ]
  [ "$(readlink "$SKILLS/sh-analityk")" = "$OLD/sh-analityk" ]
  [ "$(readlink "$SKILLS/sh-kierownik")" = "$OLD/sh-kierownik" ]
  [ "$(cat "$SKILLS/sh-analityk/SKILL.md")" = "old" ]
  [ "$(snapshot)" = "$snapshot_before" ]
}

@test "reinstall is idempotent" {
  install
  install
  [ "$status" -eq 0 ]
  [ "$(ls "$SKILLS" | grep -c '^sw-')" -eq 2 ]
}

@test "a skill without sw- prefix is refused and not linked" {
  mkdir -p "$NEW/skills/sh-analityk"
  install
  [ "$status" -eq 1 ]
  [[ "$output" == *"refusing skill without sw- prefix: sh-analityk"* ]]
  [ "$(readlink "$SKILLS/sh-analityk")" = "$OLD/sh-analityk" ]
}

@test "an existing non-symlink sw-* entry is not replaced" {
  mkdir -p "$SKILLS/sw-analityk"
  echo mine > "$SKILLS/sw-analityk/SKILL.md"
  install
  [ "$status" -eq 1 ]
  [ "$(cat "$SKILLS/sw-analityk/SKILL.md")" = "mine" ]
}

@test "dry run changes nothing" {
  install --dry-run
  [ "$status" -eq 0 ]
  [ ! -e "$SKILLS/sw-analityk" ]
  [[ "$output" == *"would link"* ]]
}
