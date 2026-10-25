#!/usr/bin/env python3
"""Merge conditions of sw-merge (spec section S4/S8), pure logic without I/O.

Input (JSON on stdin):
  {"mode": "spec", "sha": "<reviewed sha>", "headSha": "<current PR head>",
   "verdicts": [{"role": "recenzent", "result": "zatwierdzona", "model": "anthropic/sonnet[1m]"}, ...],
   "authorModel": "opus"}
Models are normalized identities (modelIdentity of the Cezar run record).
Output: one line per unmet condition on stdout (empty = merge allowed).
"""
import json
import re
import sys

# role -> accepted result, per mode. Mode "kod" is stage 2 and not implemented here.
REQUIRED = {
    "spec": {"recenzent": "zatwierdzona", "bezpieczenstwo": "pass"},
}


FAMILIES = ("opus", "sonnet", "haiku")


def model_family(identity):
    """Normalizes a model identity: "anthropic/opus[1m]", "claude-opus-4-5" -> "opus".

    Drops the provider prefix and the "[...]" suffix; maps Claude model ids to their
    family. Other models compare by the cleaned name. Empty means unknown."""
    name = (identity or "").strip().lower().rsplit("/", 1)[-1]
    name = re.sub(r"\[[^\]]*\]", "", name).strip()
    for family in FAMILIES:
        if re.search(r"(^|[^a-z])" + family + r"([^a-z]|$)", name):
            return family
    return name


def unmet_conditions(request):
    mode = request.get("mode")
    if mode not in REQUIRED:
        return ["tryb-" + str(mode)]
    unmet = []
    sha = request.get("sha") or ""
    if not sha or sha != request.get("headSha"):
        unmet.append("sha")
    author = model_family(request.get("authorModel"))
    if not author:
        unmet.append("model-autor")
    verdicts = {v.get("role"): v for v in request.get("verdicts", [])}
    for role, accepted in REQUIRED[mode].items():
        verdict = verdicts.get(role)
        if verdict is None or verdict.get("result") != accepted:
            unmet.append("werdykt-" + role)
            continue
        model = model_family(verdict.get("model"))
        # A reviewer on the author's model, or one whose model is unknown, does not count.
        if not model or not author or model == author:
            unmet.append("model-" + role)
    return unmet


def main():
    for item in unmet_conditions(json.load(sys.stdin)):
        print(item)


if __name__ == "__main__":
    main()
