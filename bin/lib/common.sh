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

# Push gate of the cezar-push sidecar (loopback); the token file holds the secret.
SW_PUSH_URL="${SW_PUSH_URL:-http://127.0.0.1:4330}"
export SW_PUSH_URL

# sw_scrub — filter stdin: mask e-mail addresses and token-like strings, so that
# neither the journal nor notifications carry personal data or secrets.
sw_scrub() {
  sed -E \
    -e 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/[email]/g' \
    -e 's/(gh[pousr]_|github_pat_)[A-Za-z0-9_]+/[token]/g' \
    -e 's/[Bb]earer +[A-Za-z0-9._~+\/=-]+/Bearer [token]/g' \
    -e 's/(X-Cezar-Push-Token|[Tt]oken)([:=] *)[^ ]+/\1\2[token]/g'
}

# sw_journal_issue — number of the "sw-dziennik" issue in the control repository
# (empty when it does not exist). Status 1 when GitHub cannot be read.
sw_journal_issue() {
  local control
  control="$(jq -er '.controlRepo // empty' "$SW_CONFIG")" || return 1
  gh api "repos/$control/issues?labels=sw-dziennik&state=all&per_page=1" \
    --jq '.[0].number // empty' 2>/dev/null
}

# sw_journal_comments <issue> — all journal comments as one JSON array [{body, created_at}].
sw_journal_comments() {
  local control
  control="$(jq -er '.controlRepo // empty' "$SW_CONFIG")" || return 1
  gh api --paginate "repos/$control/issues/$1/comments?per_page=100" 2>/dev/null \
    | jq -sc '[.[] | (if type == "array" then .[] else . end) | {body: (.body // ""), created_at: (.created_at // "")}]'
}
