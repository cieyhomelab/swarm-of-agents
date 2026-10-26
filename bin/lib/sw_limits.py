#!/usr/bin/env python3
"""Limit decision of sw-limits (spec S12): time since approval and usage of a project.

Usage: sw_limits.py <approvedAt|-> <now> <timeLimitHours> <usageUsd> <usageLimitUsd>
Times are ISO 8601 (UTC, "Z" or an offset). Prints nothing while both limits hold,
otherwise one reason line starting with "limit czasu" or "limit zużycia". The time
limit is reached at exactly approvedAt + timeLimitHours; the usage limit is exceeded
only strictly above usageLimitUsd. Time is checked first. A missing approvedAt ("-")
or an unreadable one skips the time check (the project was not approved yet).
"""
import sys
from datetime import datetime, timezone


def parse(text):
    parsed = datetime.fromisoformat(text.replace("Z", "+00:00"))
    return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)


def decide(approved_at, now, time_limit_hours, usage_usd, usage_limit_usd):
    if approved_at not in ("", "-"):
        try:
            elapsed_hours = (parse(now) - parse(approved_at)).total_seconds() / 3600
        except ValueError:
            elapsed_hours = None
        if elapsed_hours is not None and elapsed_hours >= time_limit_hours:
            return f"limit czasu: {int(elapsed_hours)} h od zatwierdzenia, limit {time_limit_hours:g} h"
    if usage_usd > usage_limit_usd:
        return f"limit zużycia: {usage_usd:.2f} USD, limit {usage_limit_usd:g} USD"
    return ""


def main(argv):
    if len(argv) != 5:
        print("usage: sw_limits.py <approvedAt|-> <now> <hours> <usageUsd> <limitUsd>", file=sys.stderr)
        return 2
    print(decide(argv[0], argv[1], float(argv[2]), float(argv[3]), float(argv[4])))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
