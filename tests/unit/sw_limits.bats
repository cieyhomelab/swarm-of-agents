#!/usr/bin/env bats
# Unit: the limit decision of bin/lib/sw_limits.py (table of time and usage boundaries).

setup() { LIB="$BATS_TEST_DIRNAME/../../bin/lib/sw_limits.py"; }

# decide <approvedAt> <now> <hours> <usage> <limit>
decide() { python3 "$LIB" "$@"; }

@test "approved exactly 7 x 24 h ago: time limit" {
  run decide 2026-10-01T00:00:00Z 2026-10-08T00:00:00Z 168 0 150
  [ "$status" -eq 0 ]
  [[ "$output" == "limit czasu"* ]]
}

@test "approved 6 days and 23 hours ago: no time limit" {
  run decide 2026-10-01T00:00:00Z 2026-10-07T23:00:00Z 168 0 150
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "one second before and after the time boundary" {
  run decide 2026-10-01T00:00:00Z 2026-10-07T23:59:59Z 168 0 150
  [ -z "$output" ]
  run decide 2026-10-01T00:00:00Z 2026-10-08T00:00:01Z 168 0 150
  [[ "$output" == "limit czasu"* ]]
}

@test "a custom limit and a UTC offset are honoured" {
  run decide 2026-10-01T02:00:00+02:00 2026-10-01T10:00:00Z 10 0 150
  [ -z "$output" ]
  run decide 2026-10-01T02:00:00+02:00 2026-10-01T10:00:00Z 8 0 150
  [[ "$output" == "limit czasu"* ]]
}

@test "usage: at the limit is fine, above it is the usage limit" {
  run decide - 2026-10-08T00:00:00Z 168 150 150
  [ -z "$output" ]
  run decide - 2026-10-08T00:00:00Z 168 150.01 150
  [[ "$output" == "limit zużycia"* ]]
}

@test "a missing or unreadable approval date skips the time check" {
  run decide - 2030-01-01T00:00:00Z 168 0 150
  [ -z "$output" ]
  run decide nonsense 2030-01-01T00:00:00Z 168 0 150
  [ -z "$output" ]
}

@test "both limits exceeded: time is reported first" {
  run decide 2026-10-01T00:00:00Z 2026-10-09T00:00:00Z 168 999 150
  [[ "$output" == "limit czasu"* ]]
}

@test "wrong number of arguments is an error" {
  run decide a b
  [ "$status" -eq 2 ]
}
