#!/usr/bin/env python3
"""Minimal interpreter of Cezar version-2 workflows for E2E tests.

Walks the graph of one workflow file the way Cezar does for the node types used
by sw-sweep: start, end, check (bash command, ports pass/fail), if (condition
`output` + `contains`), loop (ports repeat/exhausted, `max` iterations) and agent
(replaced by the executable in $MOCK_AGENT, called with the node id and the loop
iteration; its last stdout line is the verdict, a non-zero exit is port `failed`).

Usage: run_workflow.py <workflow.yml>
Prints "TRACE <node> <port>" per step and "END <node> <status>" at the end.
Exit code 0 when an end node was reached.
"""
import os
import subprocess
import sys

import yaml


def main(path):
    doc = yaml.safe_load(open(path, encoding="utf-8"))
    nodes = {n["id"]: n for n in doc["nodes"]}
    edges = {}
    for edge in doc["edges"]:
        edges[edge["from"]] = edge["to"]
    outputs, loops = {}, {}
    current = next(n["id"] for n in doc["nodes"] if n["type"] == "start")
    port = "next"
    for _ in range(1000):
        node = nodes[current]
        kind = node["type"]
        if kind == "end":
            print(f"END {current} {node.get('status', 'success')}")
            return 0
        if kind == "start":
            port = "next"
        elif kind == "check":
            result = subprocess.run(["bash", "-c", node["command"]], capture_output=True, text=True)
            outputs[current] = result.stdout
            sys.stderr.write(result.stderr)
            port = "pass" if result.returncode == 0 else "fail"
        elif kind == "if":
            cond = node["condition"]
            assert cond["kind"] == "output" and cond["op"] == "contains", cond
            ref = cond["ref"].split(".")[0]
            port = "true" if cond["value"] in outputs.get(ref, "") else "false"
        elif kind == "loop":
            loops[current] = loops.get(current, 0) + 1
            port = "repeat" if loops[current] <= node["max"] else "exhausted"
        elif kind == "agent":
            result = subprocess.run([os.environ["MOCK_AGENT"], current, str(loops.get("attempts", 0))],
                                    capture_output=True, text=True)
            lines = result.stdout.strip().splitlines()
            port = "failed" if result.returncode != 0 or not lines else lines[-1]
            assert port == "failed" or port in node.get("verdicts", []), port
        else:
            raise SystemExit(f"run_workflow: unsupported node type {kind}")
        print(f"TRACE {current} {port}")
        current = edges[f"{current}.{port}"] if f"{current}.{port}" in edges else edges[current]
    raise SystemExit("run_workflow: step limit exceeded")


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
