#!/usr/bin/env bats
# Unit tests for the project naming part of the scripts/test-e2e.sh contract.

setup() { ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"; }

@test "random project name when E2E_RUN_ID is unset" {
  unset E2E_RUN_ID
  E2E_PRINT_PROJECT=1 run bash "$ROOT/scripts/test-e2e.sh"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^e2e-[0-9a-f]{8}$ ]]
}

@test "two unset runs get different project names" {
  unset E2E_RUN_ID
  a="$(E2E_PRINT_PROJECT=1 bash "$ROOT/scripts/test-e2e.sh")"
  b="$(E2E_PRINT_PROJECT=1 bash "$ROOT/scripts/test-e2e.sh")"
  [ "$a" != "$b" ]
}

@test "project name uses E2E_RUN_ID when set" {
  E2E_RUN_ID=abc E2E_PRINT_PROJECT=1 run bash "$ROOT/scripts/test-e2e.sh"
  [ "$status" -eq 0 ]
  [ "$output" = "e2e-abc" ]
}
