#!/usr/bin/env bats
# Every decision bin/sw-gate can print ("URUCHOM: X", except NIC) has its own branch
# in workflows/sw-sweep.yml. Regression: "URUCHOM: SPEC" was decided by the gate but
# the sweep had no branch for it, so approved ideas never got a repository.

setup() { ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"; }

@test "the sweep has an if-branch for every gate decision" {
  decisions="$(grep -oE 'echo "URUCHOM: [A-Z]+' "$ROOT/bin/sw-gate" | sed 's/echo "//' | sort -u | grep -v 'URUCHOM: NIC')"
  [ -n "$decisions" ]
  branches="$(python3 -c '
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
for n in d["nodes"]:
    c = n.get("condition") or {}
    if n.get("type") == "if" and c.get("ref") == "gate.output":
        print(c["value"])
' "$ROOT/workflows/sw-sweep.yml" | sort -u)"
  missing="$(comm -23 <(echo "$decisions") <(echo "$branches"))"
  [ -z "$missing" ] || { echo "no sweep branch for: $missing"; return 1; }
}
