#!/usr/bin/env bash
# End-to-end tests in a throwaway Docker Compose instance.
#
# Contract (see AGENTS.md):
#   - project name e2e-${E2E_RUN_ID}; a random id when the variable is unset;
#   - no host ports are published; tests run inside the Compose network;
#   - always cleans up (down -v, local images), also on error and interruption;
#   - loads ${SH_SECRETS_DIR:-$HOME/.sh-secrets}/swarm-of-agents.env when present;
#   - needs no secrets: external services are mocks.
# Optional arguments: bats test files under tests/e2e/ to run a subset.
set -euo pipefail
cd "$(dirname "$0")/.."

# od reads a fixed number of bytes, so no pipe is cut short (SIGPIPE + pipefail).
run_id="${E2E_RUN_ID:-$(od -An -N4 -tx4 /dev/urandom | tr -d ' \n')}"
if [[ ! "$run_id" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
  echo "test-e2e: E2E_RUN_ID must match ^[a-z0-9][a-z0-9_-]*\$, got '$run_id'" >&2
  exit 2
fi
project="e2e-${run_id}"

# E2E_PRINT_PROJECT=1: print the Compose project name and exit (used by tests).
if [ "${E2E_PRINT_PROJECT:-0}" = "1" ]; then
  echo "$project"
  exit 0
fi

secrets="${SH_SECRETS_DIR:-$HOME/.sh-secrets}/swarm-of-agents.env"
if [ -f "$secrets" ]; then
  set -a
  # shellcheck disable=SC1090
  . "$secrets"
  set +a
fi

compose=(docker compose -p "$project" -f compose.yml)
child=""

cleanup() {
  "${compose[@]}" down -v --remove-orphans --rmi local >/dev/null 2>&1 || true
}
on_signal() {
  # Stop the running compose command first so cleanup does not wait for it.
  [ -n "$child" ] && kill "$child" 2>/dev/null
  exit 130
}
trap cleanup EXIT
trap on_signal INT TERM

tests=("$@")
[ "${#tests[@]}" -gt 0 ] || tests=(tests/e2e)

"${compose[@]}" build --quiet &
child=$!
wait "$child"

"${compose[@]}" run --rm runner bats "${tests[@]}" &
child=$!
wait "$child"
