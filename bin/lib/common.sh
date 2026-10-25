#!/usr/bin/env bash
# Shared helpers for swarm-of-agents scripts. Source it; do not execute it.
# shellcheck shell=bash

# Root of the swarm-of-agents checkout (directory containing bin/).
SW_ROOT="${SW_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
export SW_ROOT

# Cezar HTTP API on the VPS loopback (port 4321, verified on the VPS 2026-10-25;
# docs/CEZAR_API.md in cezar-pwa still names 4322). Overridable for tests.
SW_CEZAR_URL="${SW_CEZAR_URL:-http://127.0.0.1:4321}"
export SW_CEZAR_URL

# Runtime configuration (limits, retries, models).
SW_CONFIG="${SW_CONFIG:-$SW_ROOT/config/sw.json}"
export SW_CONFIG

sw_log() {
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2
}

sw_die() {
  printf 'sw: %s\n' "$*" >&2
  exit 1
}

# sw_config <jq-path> — print a value from the runtime configuration.
sw_config() {
  jq -er "$1" "$SW_CONFIG"
}

# sw_require <command>... — fail when a required command is missing.
sw_require() {
  local cmd
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || sw_die "missing required command: $cmd"
  done
}
