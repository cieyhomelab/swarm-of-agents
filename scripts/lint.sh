#!/usr/bin/env bash
# Lint: shellcheck, workflow validation, coexistence naming rule, config JSON.
set -euo pipefail
cd "$(dirname "$0")/.."

shopt -s nullglob
shell_files=(bin/sw-* bin/lib/*.sh scripts/*.sh tests/tools/*.sh tests/fakes/*)
shellcheck -x -P SCRIPTDIR "${shell_files[@]}"

python3 tests/tools/validate_workflows.py workflows/*.yml
bash tests/tools/check-names.sh

for f in config/*.json config/automations/*.json; do
  jq -e . "$f" >/dev/null || { echo "lint: invalid JSON $f" >&2; exit 1; }
done

echo "lint: ok"
