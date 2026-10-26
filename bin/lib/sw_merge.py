#!/usr/bin/env python3
"""Merge conditions of sw-merge (spec section S4/S8), pure logic without I/O.

Input (JSON on stdin):
  {"mode": "spec", "sha": "<reviewed sha>", "headSha": "<current PR head>",
   "verdicts": [{"role": "recenzent", "result": "zatwierdzona", "model": "anthropic/sonnet[1m]"}, ...],
   "authorModel": "opus"}
Mode "kod" also takes "requiredChecks" (names) and "checkRuns" ([{name, status, conclusion}]
of the reviewed SHA); every required name needs at least one run and all its runs must be
completed with conclusion "success", else "check-<name>" is unmet (no names configured:
"check-brak-konfiguracji").
Models are normalized identities (modelIdentity of the Cezar run record).
Output: one line per unmet condition on stdout (empty = merge allowed).
"""
import json
import re
import sys

# role -> accepted result, per mode.
REQUIRED = {
    "spec": {"recenzent": "zatwierdzona", "bezpieczenstwo": "pass"},
    "kod": {"recenzent": "approve", "bezpieczenstwo": "pass"},
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


def unmet_checks(request):
    """Required check-runs of the reviewed SHA that are missing or not green."""
    names = [n for n in request.get("requiredChecks") or [] if n]
    if not names:
        return ["check-brak-konfiguracji"]
    runs = request.get("checkRuns") or []
    unmet = []
    for name in names:
        named = [r for r in runs if r.get("name") == name]
        if not named or any(r.get("status") != "completed" or r.get("conclusion") != "success" for r in named):
            unmet.append("check-" + name)
    return unmet


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
    if mode == "kod":
        unmet += unmet_checks(request)
    return unmet


def main():
    for item in unmet_conditions(json.load(sys.stdin)):
        print(item)


if __name__ == "__main__":
    main()
