#!/usr/bin/env python3
"""Structural validator for Cezar version-2 workflows of swarm-of-agents.

Mirrors the node types and ports of Cezar's graph schema
(open-mercato/cezar packages/cezar/src/workflows/graph.ts, NODE_PORTS) and the
naming rules of the spec (prefix sw-). Exit code 1 on any problem.
"""
import re
import sys

import yaml

NODE_PORTS = {
    "start": {"next"},
    "end": set(),
    "loop": {"repeat", "exhausted"},
    "agent": {"done", "failed"},  # plus one port per declared verdict
    "check": {"pass", "fail"},
    "gate.human": {"approve", "reject"},  # plus "timeout" with timeoutMs
    "ask-user": {"answered"},  # plus "timeout" with timeoutMs
    "dispatch": {"done", "failed"},
    "workflow": {"done", "failed"},
    "fork": {"1", "2", "3", "4"},
    "join": {"done", "failed"},
    "if": {"true", "false"},
    "git.commit": {"done", "nothing", "failed"},
    "git.push": {"done", "failed"},
    "git.sync-base": {"done", "conflict", "failed"},
    "github.draft-pr": {"created", "failed"},
    "github.wait-ci": {"green", "red", "timeout", "failed"},
    "github.pr-comment": {"done", "failed"},
    "github.pr-update": {"done", "failed"},
    "github.issue-comment": {"done", "failed"},
    "notify.webhook": {"done", "failed"},
}
NODE_ID = re.compile(r"^[A-Za-z0-9_-]+$")


def validate(path):
    errors = []
    with open(path, encoding="utf-8") as fh:
        doc = yaml.safe_load(fh)
    if not isinstance(doc, dict):
        return [f"{path}: not a mapping"]
    if str(doc.get("version")) != "2":
        errors.append(f"{path}: version must be 2")
    name = doc.get("name", "")
    if not str(name).startswith("sw-"):
        errors.append(f"{path}: name '{name}' must start with sw-")
    stem = path.rsplit("/", 1)[-1].rsplit(".", 1)[0]
    if stem != name:
        errors.append(f"{path}: file name must match workflow name '{name}'")

    nodes = {}
    for node in doc.get("nodes") or []:
        nid, ntype = node.get("id"), node.get("type")
        if not nid or not NODE_ID.match(str(nid)):
            errors.append(f"{path}: invalid node id '{nid}'")
            continue
        if nid in nodes:
            errors.append(f"{path}: duplicate node id '{nid}'")
        if ntype not in NODE_PORTS:
            errors.append(f"{path}: node '{nid}' has unknown type '{ntype}'")
            continue
        ports = set(NODE_PORTS[ntype])
        if ntype in ("gate.human", "ask-user") and node.get("timeoutMs"):
            ports.add("timeout")
        if ntype == "agent":
            ports |= set(node.get("verdicts") or [])
            # Spec: Claude Max only, explicit model from config/sw.json.
            if node.get("runner") != "claude":
                errors.append(f"{path}: agent node '{nid}' must set runner: claude")
            if not node.get("model"):
                errors.append(f"{path}: agent node '{nid}' must set an explicit model")
            # Cezar turns each entry into the claude prefix rule Bash(<entry>:*):
            # a glob such as "gh issue view *" would only allow that literal text.
            for entry in node.get("bashAllowlist") or []:
                if "*" in str(entry):
                    errors.append(f"{path}: agent node '{nid}' bashAllowlist entry '{entry}' must be a "
                                  "plain command prefix without '*'")
        if ntype == "check" and not node.get("command"):
            errors.append(f"{path}: check node '{nid}' needs a command")
        nodes[nid] = ports

    starts = [n for n in doc.get("nodes") or [] if n.get("type") == "start"]
    if len(starts) != 1:
        errors.append(f"{path}: exactly one start node required")

    types = {n.get("id"): n.get("type") for n in doc.get("nodes") or []}
    graph = {nid: [] for nid in nodes}
    for edge in doc.get("edges") or []:
        src, dst = str(edge.get("from", "")), str(edge.get("to", ""))
        src_node, _, port = src.partition(".")
        if src_node not in nodes:
            errors.append(f"{path}: edge from unknown node '{src_node}'")
        elif port and port not in nodes[src_node]:
            errors.append(f"{path}: node '{src_node}' has no port '{port}'")
        if dst not in nodes:
            errors.append(f"{path}: edge to unknown node '{dst}'")
        elif src_node in nodes:
            graph[src_node].append(dst)

    errors += reachability_and_cycles(path, graph, types)
    return errors


def reachability_and_cycles(path, graph, types):
    """Every node reachable from start; every cycle passes through a loop node."""
    errors = []
    start = [n for n, t in types.items() if t == "start"]
    seen, stack = set(), list(start)
    while stack:
        cur = stack.pop()
        if cur in seen:
            continue
        seen.add(cur)
        stack.extend(graph.get(cur, []))
    for nid in graph:
        if nid not in seen:
            errors.append(f"{path}: node '{nid}' is unreachable from start")
    # Cezar: every cycle must pass through a loop node.
    sub = {n: [d for d in ds if types.get(d) != "loop"]
           for n, ds in graph.items() if types.get(n) != "loop"}
    state = {}

    def visit(n):
        state[n] = 1
        for d in sub.get(n, []):
            if state.get(d) == 1:
                return True
            if d in sub and state.get(d) is None and visit(d):
                return True
        state[n] = 2
        return False

    for n in sub:
        if state.get(n) is None and visit(n):
            errors.append(f"{path}: cycle without a loop node")
            break
    return errors


def main(paths):
    if not paths:
        print("validate_workflows: no workflow files given", file=sys.stderr)
        return 1
    problems = [err for p in paths for err in validate(p)]
    for err in problems:
        print(err, file=sys.stderr)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
