#!/usr/bin/env python3
"""Merge conditions of sw-merge (spec section S4/S8), pure logic without I/O.

Input (JSON on stdin):
  {"mode": "spec", "sha": "<reviewed sha>", "headSha": "<current PR head>",
   "verdicts": [{"role": "recenzent", "result": "zatwierdzona", "model": "sonnet"}, ...],
   "authorModel": "opus"}
Output: one line per unmet condition on stdout (empty = merge allowed).
"""
import json
import sys

# role -> accepted result, per mode. Mode "kod" is stage 2 and not implemented here.
REQUIRED = {
    "spec": {"recenzent": "zatwierdzona", "bezpieczenstwo": "pass"},
}


def unmet_conditions(request):
    mode = request.get("mode")
    if mode not in REQUIRED:
        return ["tryb-" + str(mode)]
    unmet = []
    sha = request.get("sha") or ""
    if not sha or sha != request.get("headSha"):
        unmet.append("sha")
    author = (request.get("authorModel") or "").strip().lower()
    if not author:
        unmet.append("model-autor")
    verdicts = {v.get("role"): v for v in request.get("verdicts", [])}
    for role, accepted in REQUIRED[mode].items():
        verdict = verdicts.get(role)
        if verdict is None or verdict.get("result") != accepted:
            unmet.append("werdykt-" + role)
            continue
        model = (verdict.get("model") or "").strip().lower()
        # A reviewer on the author's model, or one whose model is unknown, does not count.
        if not model or not author or model == author:
            unmet.append("model-" + role)
    return unmet


def main():
    for item in unmet_conditions(json.load(sys.stdin)):
        print(item)


if __name__ == "__main__":
    main()
