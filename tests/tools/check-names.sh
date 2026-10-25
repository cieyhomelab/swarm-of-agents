#!/usr/bin/env bash
# check-names.sh — coexistence rule of the spec: nothing in this repository is
# named with the sh- / "sh:" prefix of sh-skills. Skills, workflows, scripts,
# Cezar automations and system labels must use the sw prefix.
set -uo pipefail

root="${SW_CHECK_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$root" || exit 1
fail=0
err() { echo "check-names: $*" >&2; fail=1; }

shopt -s nullglob

for dir in skills/*/; do
  name="$(basename "$dir")"
  [[ "$name" == sw-* ]] || err "skill directory '$name' must start with sw-"
  file="$dir/SKILL.md"
  if [ ! -f "$file" ]; then
    err "skill '$name' has no SKILL.md"
    continue
  fi
  declared="$(sed -n 's/^name:[[:space:]]*//p' "$file" | head -1)"
  [ "$declared" = "$name" ] || err "skill '$name' declares name '$declared'"
done

for file in workflows/*; do
  base="$(basename "$file")"
  [[ "$base" == sw-*.yml ]] || err "workflow file '$base' must be sw-*.yml"
done

for file in bin/*; do
  [ -d "$file" ] && continue
  base="$(basename "$file")"
  [[ "$base" == sw-* ]] || err "script 'bin/$base' must start with sw-"
done

# Cezar automation definitions kept in the repository.
for file in config/automations/*.json; do
  name="$(jq -r '.name // empty' "$file")"
  [[ "$name" == "sw: "* ]] || err "automation '$file' name must start with 'sw: '"
done

# System labels declared in configuration.
if [ -f config/labels.json ]; then
  while IFS= read -r label; do
    [[ "$label" == sw-* ]] || err "system label '$label' must start with sw-"
  done < <(jq -r '.system[]?' config/labels.json)
fi

# References to sh-skills elements inside product code. Only the etap-1
# handover script may name sh-* (it starts sh-start in an app project).
allow_ref='^bin/sw-handover-sh:'
while IFS= read -r hit; do
  [[ "$hit" =~ $allow_ref ]] && continue
  err "reference to sh-skills in $hit"
done < <(grep -rnE '(^|[^a-z0-9_-])sh-[a-z]|"sh: |sh-skills' workflows bin config skills 2>/dev/null \
         | grep -v '^skills/README.md:' || true)

exit "$fail"
