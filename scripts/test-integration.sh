#!/usr/bin/env bash
# Integration tests (bats): real filesystem and HTTP against the local mock API.
# Optional: pass test files to run a subset.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ $# -gt 0 ]; then
  bats "$@"
else
  bats tests/integration
fi
