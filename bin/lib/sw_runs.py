#!/usr/bin/env python3
"""Run supervision of sw-limits (spec S11, S12): plan limit, retries, no progress.

Reads one JSON object on stdin:
  runs            Cezar task records of the project (status, autoResumeAt, autoResumes, step,
                  updatedAt, branch, task, workflow, model)
  now             ISO 8601 time
  stalledAfterHours, retriesPerTask, autoResumeLimit   numbers from the configuration
  progress        {runId: ISO time of the last commit on the run's branch}
  stoppedByLimits ids of tasks sw-limits itself was about to cancel (written before the cancel call);
                  a "cancelled" task not on the list was stopped by hand and is left alone
Prints one JSON object: {"planWait": bool, "actions": [...]}. An action is
  {"kind": "retry"|"resume", "run", "task", "workflow", "model", "reason", "stop"} (a new task to start; a "cancelled" task stopped by sw-limits without a successor is treated like a failed one;
  "stop" is true when the old task is still active and must be cancelled before the new one starts) or
  {"kind": "exhausted", "run", "reason"} (the project is to be paused).
While any task waits for the plan limit ("autoResumeAt") nothing is retried or counted
(S12: the suspension does not use retries). A task is handled once: a later task whose text
carries "zastępuje <id>" / "od <id>" marks it. Retries consumed travel in the marker
"[ponowienie <n>; zastępuje <id>]"; a resume after Cezar's automatic resumes ran out keeps <n>.
"""
import json
import re
import sys
from datetime import datetime, timezone

MARKER = re.compile(r"\n*\[(?:ponowienie|wznowienie) (\d+); [^\]]*\]")
ACTIVE = ("running", "waiting", "queued")


def parse(text):
    parsed = datetime.fromisoformat(str(text).replace("Z", "+00:00"))
    return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)


def used_retries(task):
    found = MARKER.findall(task or "")
    return int(found[-1]) if found else 0


def base_task(task):
    return MARKER.sub("", task or "").rstrip()


def last_progress(run, commits):
    times = []
    for value in (run.get("updatedAt"), commits.get(run["id"])):
        try:
            times.append(parse(value))
        except (TypeError, ValueError):
            pass
    return max(times) if times else None


def plan(data):
    runs = data.get("runs") or []
    now = parse(data["now"])
    plan_wait = any(r.get("autoResumeAt") and r.get("status") in ACTIVE for r in runs)
    if plan_wait:
        return {"planWait": True, "actions": []}
    texts = " ".join(r.get("task") or "" for r in runs)
    actions = []
    for run in runs:
        rid = run["id"]
        if re.search(rf"(?:zastępuje|od) {re.escape(rid)}\]", texts):
            continue
        status = run.get("status")
        n = used_retries(run.get("task"))
        step = run.get("step") or "-"
        if status == "failed" and int(run.get("autoResumes") or 0) >= data["autoResumeLimit"]:
            actions.append({"kind": "resume", "run": rid, "workflow": run.get("workflow", ""),
                            "model": run.get("model", ""),
                            "reason": f"wyczerpane {data['autoResumeLimit']} wznowień Cezara, krok {step}",
                            "task": f"{base_task(run.get('task'))}\n\n[wznowienie {n}; od {rid}] "
                                    f"Kontynuuj od przerwanego kroku: {step}"})
            continue
        if status == "failed":
            cause = "zadanie nieudane"
        elif status == "cancelled":
            # sw-limits cancels a stalled task before it creates the retry; when that creation
            # failed the cancelled task is the only trace, so it counts as failed (a task nobody
            # replaced is retried in the next cycle). A task cancelled by hand is not on the list.
            if rid not in (data.get("stoppedByLimits") or []):
                continue
            cause = "zadanie zatrzymane bez następcy"
        elif status in ("running", "waiting"):
            progress = last_progress(run, data.get("progress") or {})
            if progress is None or (now - progress).total_seconds() / 3600 < data["stalledAfterHours"]:
                continue
            cause = f"brak commitu i zmiany stanu od {data['stalledAfterHours']:g} h"
        else:
            continue
        active = status in ("running", "waiting")
        if n >= data["retriesPerTask"]:
            actions.append({"kind": "exhausted", "run": rid,
                            "reason": f"wyczerpane ponowienia ({n}/{data['retriesPerTask']}); ostatni stan: {status}, "
                                      f"krok {step}; przyczyna: {cause}"})
            continue
        actions.append({"kind": "retry", "run": rid, "workflow": run.get("workflow", ""),
                        "model": run.get("model", ""), "stop": active,
                        "reason": f"zadanie {rid}: {cause}, krok {step}; ponowienie {n + 1}/{data['retriesPerTask']}",
                        "task": f"{base_task(run.get('task'))}\n\n[ponowienie {n + 1}; zastępuje {rid}]"})
    return {"planWait": False, "actions": actions}


if __name__ == "__main__":
    print(json.dumps(plan(json.load(sys.stdin)), ensure_ascii=False))
