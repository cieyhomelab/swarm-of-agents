#!/usr/bin/env bash
# Build: assemble the release bundle installed on the VPS and verify it.
# Output: dist/swarm-of-agents.tar.gz (skills, workflows, bin, config, install).
set -euo pipefail
cd "$(dirname "$0")/.."

out=dist
bundle="$out/swarm-of-agents.tar.gz"
rm -rf "$out"
mkdir -p "$out"

tar -czf "$bundle" bin config skills workflows scripts/install.sh

# Verify: the bundle unpacks, its scripts run, and install works in isolation.
check="$(mktemp -d)"
trap 'rm -rf "$check"' EXIT
tar -xzf "$bundle" -C "$check"
for f in "$check"/bin/sw-*; do
  [ -x "$f" ] || { echo "build: not executable: ${f#"$check"/}" >&2; exit 1; }
done
SW_INSTALL_ROOT="$check" bash "$check/scripts/install.sh" --skills-dir "$check/skills-target" --dry-run >/dev/null

echo "build: $bundle"
