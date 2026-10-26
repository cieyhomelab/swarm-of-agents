#!/usr/bin/env python3
"""Coverage checks of the implementation of an application checkout (spec S6, S7), used by bin/sw-pokrycie-check.

Usage: sw_pokrycie.py modul|e2e <checkout>
Prints one problem per line (nothing when the coverage is complete):
  - modul: every item of "## Udostępnia" of each docs/kontrakty/*.md has a line
    "- <pozycja> => <ścieżka testu>" in "## Pokrycie" of the same contract, and that test file
    exists and is not empty (the item and the path are compared literally);
  - e2e: every scenario "### S<n>" of the newest .ai/specs/*.md is named in some file of
    tests/e2e, and no test there is skipped or pending.
"""
import glob
import os
import re
import sys

# Constructs that skip a test, not the bare words (a domain may use "pending" in an assertion or a name):
# bats `skip` as a command, `test.skip(` / `it.skip(` / `describe.skip(`, `xit(` / `xdescribe(` / `xtest(`,
# pytest `@pytest.mark.skip|xfail` and `pytest.skip(` / `pytest.xfail(`, `@unittest.skip`, `it.todo(`, `pending(`.
SKIPPED = re.compile(
    r"^\s*skip(\s|$)"
    r"|\b(test|it|describe)\.(skip|todo|fixme)\s*\("
    r"|(^|[^\w.\"'])(xit|xdescribe|xtest|pending)\s*\("
    r"|@pytest\.mark\.(skip|skipif|xfail)\b"
    r"|\bpytest\.(skip|xfail)\s*\("
    r"|@unittest\.skip"
)


def sections(text):
    """Map of "## heading" -> body lines."""
    out, current = {}, None
    for line in text.splitlines():
        match = re.match(r"^##\s+(.+?)\s*$", line)
        if match:
            current = match[1]
            out[current] = []
        elif current is not None:
            out[current].append(line)
    return out


def bullets(lines):
    return [m[1].strip() for m in (re.match(r"^\s*[-*]\s+(.+?)\s*$", l) for l in lines) if m]


def modul(root):
    problems = []
    contracts = sorted(glob.glob(os.path.join(root, "docs", "kontrakty", "*.md")))
    if not contracts:
        problems.append("brak kontraktu modułu docs/kontrakty/<modul>.md")
    for path in contracts:
        name = os.path.relpath(path, root)
        secs = sections(open(path, encoding="utf-8").read())
        covered = {}
        for item in bullets(secs.get("Pokrycie", [])):
            if "=>" in item:
                left, right = item.split("=>", 1)
                covered[left.strip()] = right.strip()
        for item in bullets(secs.get("Udostępnia", [])):
            test = covered.get(item)
            if test is None:
                problems.append(f"{name}: pozycja '{item}' nie ma testu w sekcji '## Pokrycie'")
                continue
            target = os.path.abspath(os.path.join(root, test))
            if not target.startswith(os.path.abspath(root) + os.sep) or not os.path.isfile(target) or os.path.getsize(target) == 0:
                problems.append(f"{name}: test '{test}' pozycji '{item}' nie istnieje albo jest pusty")
    return problems


def e2e(root):
    problems = []
    specs = glob.glob(os.path.join(root, ".ai", "specs", "*.md"))
    if not specs:
        return ["brak specyfikacji w .ai/specs"]
    newest = max(specs, key=os.path.getmtime)
    wanted = re.findall(r"^###\s+(S[0-9]+)\b", open(newest, encoding="utf-8").read(), flags=re.M)
    text = ""
    for base, _, files in os.walk(os.path.join(root, "tests", "e2e")):
        for name in files:
            try:
                body = open(os.path.join(base, name), encoding="utf-8").read()
            except (OSError, UnicodeDecodeError):
                continue
            text += body + "\n"
            for number, line in enumerate(body.splitlines(), 1):
                if SKIPPED.search(line):
                    problems.append(f"{os.path.relpath(os.path.join(base, name), root)}:{number}: test E2E pominięty albo oczekujący")
    for scenario in wanted:
        if not re.search(r"\b%s\b" % scenario, text):
            problems.append(f"scenariusz {scenario} nie ma testu E2E w tests/e2e")
    return problems


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[1] not in ("modul", "e2e"):
        sys.exit("uzycie: sw_pokrycie.py modul|e2e <checkout>")
    for problem in (modul if sys.argv[1] == "modul" else e2e)(sys.argv[2]):
        print(problem)
