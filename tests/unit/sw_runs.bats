#!/usr/bin/env bats
# Unit: the run supervision of bin/lib/sw_runs.py (plan limit, retries, no progress; S11, S12).

setup() { LIB="$BATS_TEST_DIRNAME/../../bin/lib/sw_runs.py"; }

# plan <runs-json> [progress-json] — the decision at 2026-10-20T12:00:00Z with the default limits.
plan() {
  jq -nc --argjson r "$1" --argjson p "${2:-{\}}" \
    '{runs: $r, now: "2026-10-20T12:00:00Z", stalledAfterHours: 3, retriesPerTask: 2, autoResumeLimit: 12, progress: $p}' \
    | python3 "$LIB"
}

@test "a task waiting for the plan limit: plan wait, no actions, even next to a failed task" {
  run plan '[{"id":"a","status":"waiting","autoResumeAt":"2026-10-20T15:00:00Z","updatedAt":"2026-10-20T01:00:00Z"},
             {"id":"b","status":"failed","task":"t"}]'
  [ "$(jq -r .planWait <<<"$output")" = true ]
  [ "$(jq '.actions | length' <<<"$output")" -eq 0 ]
}

@test "no waiting task: no plan wait" {
  run plan '[{"id":"a","status":"done"}]'
  [ "$(jq -r .planWait <<<"$output")" = false ]
}

@test "12 exhausted automatic resumes: a new task from the interrupted step, retries unchanged" {
  run plan '[{"id":"a","status":"failed","autoResumes":12,"step":"implementacja","task":"Zrob X\n\n[ponowienie 1; zastępuje z]","workflow":"sw-build"}]'
  [ "$(jq -r '.actions[0].kind' <<<"$output")" = resume ]
  [[ "$(jq -r '.actions[0].task' <<<"$output")" == *"[wznowienie 1; od a]"*"implementacja" ]]
  [ "$(jq -r '.actions[0].workflow' <<<"$output")" = sw-build ]
}

@test "a failed task with fewer than 12 resumes is a retry that uses one" {
  run plan '[{"id":"a","status":"failed","autoResumes":3,"task":"Zrob X"}]'
  [ "$(jq -r '.actions[0].kind' <<<"$output")" = retry ]
  [[ "$(jq -r '.actions[0].task' <<<"$output")" == "Zrob X"*"[ponowienie 1; zastępuje a]" ]]
}

@test "a retried task is handled once" {
  run plan '[{"id":"a","status":"failed","task":"Zrob X"},{"id":"b","status":"running","updatedAt":"2026-10-20T11:59:00Z","task":"Zrob X\n\n[ponowienie 1; zastępuje a]"}]'
  [ "$(jq '.actions | length' <<<"$output")" -eq 0 ]
}

@test "retries used up: exhausted with the cause and the last state" {
  run plan '[{"id":"c","status":"failed","step":"testy","task":"Zrob X\n\n[ponowienie 2; zastępuje b]"}]'
  [ "$(jq -r '.actions[0].kind' <<<"$output")" = exhausted ]
  [[ "$(jq -r '.actions[0].reason' <<<"$output")" == *"wyczerpane ponowienia (2/2)"*"ostatni stan: failed, krok testy"* ]]
}

@test "no commit and no state change for 3 hours counts as failed; 2 h 59 min does not" {
  run plan '[{"id":"a","status":"running","updatedAt":"2026-10-20T09:00:00Z","task":"t"}]'
  [ "$(jq -r '.actions[0].kind' <<<"$output")" = retry ]
  run plan '[{"id":"a","status":"running","updatedAt":"2026-10-20T09:01:00Z","task":"t"}]'
  [ "$(jq '.actions | length' <<<"$output")" -eq 0 ]
}

@test "a recent commit on the branch is progress even when the state is old" {
  run plan '[{"id":"a","status":"running","updatedAt":"2026-10-20T01:00:00Z","task":"t"}]' '{"a":"2026-10-20T11:00:00Z"}'
  [ "$(jq '.actions | length' <<<"$output")" -eq 0 ]
}

@test "finished and cancelled tasks are left alone" {
  run plan '[{"id":"a","status":"done","updatedAt":"2026-10-01T00:00:00Z"},{"id":"b","status":"cancelled"}]'
  [ "$(jq '.actions | length' <<<"$output")" -eq 0 ]
}
