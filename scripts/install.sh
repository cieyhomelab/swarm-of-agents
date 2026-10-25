#!/usr/bin/env bash
# install.sh — link the sw-* skills of this checkout into the global skills
# directory Cezar reads (~/.claude/skills), side by side with sh-* skills.
#
# Guarantees (spec, "Współistnienie z sh-skills"):
#   - only entries named sw-* are created or replaced;
#   - an existing sw-* entry is replaced only when it is a symlink;
#   - nothing else in the skills directory is read, changed or removed.
#
# Usage: scripts/install.sh [--skills-dir DIR] [--dry-run]
set -euo pipefail

root="${SW_INSTALL_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
skills_dir="${HOME}/.claude/skills"
dry_run=0

while [ $# -gt 0 ]; do
  case "$1" in
    --skills-dir) skills_dir="$2"; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "install: unknown argument: $1" >&2; exit 2 ;;
  esac
done

shopt -s nullglob
sources=("$root"/skills/*/)
status=0

[ "$dry_run" -eq 1 ] || mkdir -p "$skills_dir"

for src in "${sources[@]}"; do
  name="$(basename "$src")"
  case "$name" in
    sw-*) ;;
    *) echo "install: refusing skill without sw- prefix: $name" >&2; status=1; continue ;;
  esac

  target="$skills_dir/$name"
  if [ -e "$target" ] && [ ! -L "$target" ]; then
    echo "install: refusing to replace non-symlink $target" >&2
    status=1
    continue
  fi

  if [ "$dry_run" -eq 1 ]; then
    echo "would link $target -> ${src%/}"
  else
    ln -sfn "${src%/}" "$target"
    echo "linked $target -> ${src%/}"
  fi
done

[ "${#sources[@]}" -gt 0 ] || echo "install: no skills to link"
exit "$status"
