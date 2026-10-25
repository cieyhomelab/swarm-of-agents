#!/usr/bin/env bats
# E2E: the sw-sweep gate command exactly as the workflow runs it, inside an
# environment like the VPS, against mocked Cezar and GitHub APIs.

setup() {
  : "${MOCK_URL:?run through scripts/test-e2e.sh}"
  curl -fsS -X POST -d '{"health_status": 200, "github_user": "cieyhomelab"}' "$MOCK_URL/__control" >/dev/null
}

gate_command() {
  # The command of the "gate" node in workflows/sw-sweep.yml.
  python3 -c 'import yaml,sys; d=yaml.safe_load(open(sys.argv[1])); print([n["command"] for n in d["nodes"] if n["id"]=="gate"][0])' \
    "${SW_HOME:-/work}"/workflows/sw-sweep.yml 2>/dev/null \
    || sed -n 's/^ *command: //p' "${SW_HOME:-/work}"/workflows/sw-sweep.yml | head -1
}

@test "sweep gate command from the workflow passes on a healthy VPS" {
  cmd="$(gate_command)"
  run bash -c "$cmd"
  [ "$status" -eq 0 ]
  [[ "$output" == *"STAN: OK"* ]]
  [[ "$output" == *"URUCHOM: NIC"* ]]
}

@test "sweep gate fails when Cezar is down" {
  curl -fsS -X POST -d '{"health_status": 503}' "$MOCK_URL/__control" >/dev/null
  run bash -c "$(gate_command)"
  [ "$status" -eq 1 ]
  [[ "$output" == *"STAN: BLAD"* ]]
}

@test "install next to sh-skills leaves them untouched" {
  skills="$HOME/.claude/skills"
  mkdir -p "$skills" "$HOME/sh-skills/skills/sh-analityk"
  echo old > "$HOME/sh-skills/skills/sh-analityk/SKILL.md"
  ln -sfn "$HOME/sh-skills/skills/sh-analityk" "$skills/sh-analityk"
  run bash "${SW_HOME:-/work}"/scripts/install.sh
  [ "$status" -eq 0 ]
  [ "$(readlink "$skills/sh-analityk")" = "$HOME/sh-skills/skills/sh-analityk" ]
  [ "$(cat "$skills/sh-analityk/SKILL.md")" = "old" ]
  [ -z "$(find "$skills" -mindepth 1 -maxdepth 1 -name 'sw-*' ! -type l)" ]
}
