#!/usr/bin/env python3
"""Check of the architecture of an application checkout (spec S5), used by bin/sw-architektura-check.

Usage: sw_architektura.py <checkout> <requiredChecks-json>
Prints one problem per line (nothing when the architecture is complete):
  - every docs/kontrakty/*.md has "## Udostępnia", "## Wymaga" and "## Forma" (its first
    line "część aplikacji" or "osobna usługa") and a "## Scenariusze" section;
  - every scenario "### S<n>" of the newest .ai/specs/*.md is named in some contract;
  - with two or more modules (docs/kontrakty/README.md is not a contract): every line of
    "## Wymaga" is "brak" or "- <modul>: <pozycja>" naming another module and one of its
    "Udostępnia" items, the requirements have no cycle, and "## Testy kontraktu" lists
    "- <ścieżka>" of existing, non-empty contract tests (spec S5, many modules);
  - .github/workflows/ci.yml runs on pull_request and has a job for every required check.
"""
import glob
import json
import os
import re
import sys

import yaml

FORMS = ("część aplikacji", "osobna usługa")


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


def many_modules(root, parsed):
    """Problems specific to an application of several modules: dependencies and contract tests."""
    problems, requires = [], {}
    for name, secs in parsed.items():
        module = os.path.splitext(os.path.basename(name))[0]
        requires[module] = set()
        for item in bullets(secs.get("Wymaga", [])):
            target, _, wanted = item.partition(":")
            target, wanted = target.strip(), wanted.strip()
            if target not in parsed_modules(parsed) or target == module:
                problems.append(f"{name}: 'Wymaga' wskazuje '{target}', a to nie jest inny moduł z docs/kontrakty")
            elif wanted not in bullets(parsed_modules(parsed)[target].get("Udostępnia", [])):
                problems.append(f"{name}: 'Wymaga' chce '{wanted}', a moduł {target} tego nie udostępnia")
            else:
                requires[module].add(target)
        plain = [l.strip() for l in secs.get("Wymaga", []) if l.strip() and not re.match(r"^[-*]\s", l.strip())]
        for line in plain:
            if line.rstrip(".").lower() != "brak":
                problems.append(f"{name}: 'Wymaga' to 'brak' albo lista '- <moduł>: <pozycja>', nie '{line}'")
        tests = bullets(secs.get("Testy kontraktu", []))
        if not tests:
            problems.append(f"{name}: brak testów kontraktu (sekcja '## Testy kontraktu' z listą '- <ścieżka>')")
        for path in tests:
            full = os.path.join(root, path)
            if not (os.path.isfile(full) and os.path.getsize(full) > 0):
                problems.append(f"{name}: test kontraktu '{path}' nie istnieje albo jest pusty")
    # a requirement cycle makes the modules impossible to build in an order
    state = {}

    def visit(module, trail):
        if state.get(module) == 1:
            return trail[trail.index(module):] + [module]
        if state.get(module) == 2:
            return None
        state[module] = 1
        for dep in sorted(requires.get(module, ())):
            cycle = visit(dep, trail + [module])
            if cycle:
                return cycle
        state[module] = 2
        return None

    for module in sorted(requires):
        cycle = visit(module, [])
        if cycle:
            problems.append("moduły wymagają siebie nawzajem: " + " -> ".join(cycle))
            break
    return problems


def parsed_modules(parsed):
    return {os.path.splitext(os.path.basename(n))[0]: s for n, s in parsed.items()}


def main(root, required):
    problems = []
    contracts = sorted(c for c in glob.glob(os.path.join(root, "docs", "kontrakty", "*.md"))
                       if os.path.basename(c).lower() != "readme.md")
    parsed = {}
    if not contracts:
        problems.append("brak kontraktu modułu docs/kontrakty/<modul>.md")
    assigned = set()
    for path in contracts:
        name = os.path.relpath(path, root)
        secs = sections(open(path, encoding="utf-8").read())
        parsed[name] = secs
        for heading in ("Udostępnia", "Wymaga", "Forma", "Scenariusze"):
            if heading not in secs:
                problems.append(f"{name}: brak sekcji '## {heading}'")
        form = next((l.strip() for l in secs.get("Forma", []) if l.strip()), "")
        if "Forma" in secs and not form.startswith(FORMS):
            problems.append(f"{name}: sekcja Forma musi zaczynać się od 'część aplikacji' albo 'osobna usługa'")
        assigned |= set(re.findall(r"\bS[0-9]+\b", "\n".join(secs.get("Scenariusze", []))))

    if len(parsed) >= 2:
        problems += many_modules(root, parsed)

    specs = glob.glob(os.path.join(root, ".ai", "specs", "*.md"))
    if not specs:
        problems.append("brak specyfikacji w .ai/specs")
    else:
        newest = max(specs, key=os.path.getmtime)
        wanted = re.findall(r"^###\s+(S[0-9]+)\b", open(newest, encoding="utf-8").read(), flags=re.M)
        for scenario in wanted:
            if scenario not in assigned:
                problems.append(f"scenariusz {scenario} nie jest przypisany do żadnego modułu")

    ci = os.path.join(root, ".github", "workflows", "ci.yml")
    if not os.path.isfile(ci):
        problems.append("brak .github/workflows/ci.yml")
    else:
        doc = yaml.safe_load(open(ci, encoding="utf-8")) or {}
        triggers = doc.get("on", doc.get(True, {}))
        names = triggers if isinstance(triggers, (list, dict)) else [triggers]
        if "pull_request" not in names:
            problems.append("ci.yml nie uruchamia się na pull_request")
        jobs = doc.get("jobs") or {}
        have = {(job or {}).get("name", key) for key, job in jobs.items()}
        for check in required:
            if check not in have:
                problems.append(f"ci.yml nie ma zadania o nazwie '{check}' (requiredChecks)")
    for problem in problems:
        print(problem)


if __name__ == "__main__":
    main(sys.argv[1], json.loads(sys.argv[2]))
