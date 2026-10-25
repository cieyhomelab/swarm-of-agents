#!/usr/bin/env bash
# Unit tests (bats). Optional: pass test files to run a subset.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ $# -gt 0 ]; then
  bats "$@"
else
  bats tests/unit
fi
