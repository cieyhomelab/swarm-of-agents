#!/usr/bin/env python3
"""Mock of the external APIs used by swarm-of-agents scripts in tests.

Routes:
  GET  /api/v1/health             Cezar health (healthResponseSchema subset)
  GET  /api/v1/workspace/config   Cezar workspace config (resources.maxParallel)
  POST /api/v1/projects/create    Cezar project + private repository {name, github:{owner}}
  GET  /cez/automations           Cezar automations (what `cez automation list` reads)
  POST /cez/automations[/<id>]    create / update an automation definition
  GET  /github/<path>             GitHub REST, from the in-memory state
  POST /github/<path>             GitHub REST writes: labels, issues (create)
  PUT  /github/<path>             GitHub REST writes: repository contents
  POST /__control                 change state, e.g. {"health_status": 503}
  GET  /__requests                requests received so far (JSON list)

State keys: health_status, github_user (null = logged out), control_repo,
control_private (null = repository missing), max_parallel, labels, issues,
contents, automations (starts with automations of another agent chain, which
must stay untouched).

Usage: mock_api.py [--port N] [--port-file FILE]   (port 0 = random)
"""
import argparse
import base64
import copy
import json
from urllib.parse import parse_qs, urlsplit
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

DEFAULTS = {
    "health_status": 200,
    "github_user": "cieyhomelab",
    "control_repo": "cieyhomelab/sw-control",
    "control_private": True,
    "max_parallel": 3,
    "labels": [],
    "issues": [],
    "contents": {},
    "automations": [
        {"id": "a1b2c3d4-0001", "name": "sh: architekt", "enabled": True},
        {"id": "a1b2c3d4-0002", "name": "sh: realizacja", "enabled": True},
    ],
}
STATE = copy.deepcopy(DEFAULTS)
REQUESTS = []


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def _send(self, status, payload):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        REQUESTS.append({"method": "GET", "path": self.path})
        if self.path == "/api/v1/health":
            status = STATE["health_status"]
            if status != 200:
                return self._send(status, {"error": "unavailable"})
            return self._send(200, {"version": "0.0.0-mock", "projects": [], "bootProject": "mock"})
        if self.path == "/api/v1/workspace/config":
            return self._send(200, {"resources": {"maxParallel": STATE["max_parallel"]}})
        if self.path == "/__requests":
            return self._send(200, REQUESTS)
        if self.path == "/github/user":
            if STATE["github_user"] is None:
                return self._send(401, {"message": "Bad credentials"})
            return self._send(200, {"login": STATE["github_user"]})
        if self.path == f"/github/repos/{STATE['control_repo']}":
            if STATE["control_private"] is None:
                return self._send(404, {"message": "Not Found"})
            return self._send(200, {"full_name": STATE["control_repo"], "private": STATE["control_private"]})
        if self.path == "/cez/automations":
            return self._send(200, STATE["automations"])
        url = urlsplit(self.path)
        repo_prefix = f"/github/repos/{STATE['control_repo']}/"
        if url.path.startswith(repo_prefix) and STATE["control_private"] is not None:
            rest = url.path[len(repo_prefix):]
            if rest == "labels":
                return self._send(200, STATE["labels"])
            if rest == "issues":
                wanted = parse_qs(url.query).get("labels", [None])[0]
                found = [i for i in STATE["issues"]
                         if wanted is None or wanted in [lb["name"] for lb in i["labels"]]]
                return self._send(200, found)
            if rest.startswith("contents/") and rest[9:] in STATE["contents"]:
                entry = STATE["contents"][rest[9:]]
                return self._send(200, {"sha": entry["sha"], "content": entry["content"]})
        return self._send(404, {"message": "Not Found"})

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b"{}"
        self._record("POST", raw)
        if self.path == "/__control":
            update = json.loads(raw or b"{}")
            if update.get("reset"):
                STATE.clear()
                STATE.update(copy.deepcopy(DEFAULTS))
                REQUESTS.clear()
            STATE.update({k: v for k, v in update.items() if k != "reset"})
            return self._send(200, STATE)
        if self.path == "/api/v1/projects/create":
            body = json.loads(raw)
            STATE["control_private"] = True
            return self._send(200, {"id": body["name"], "name": body["name"]})
        if self.path == "/cez/automations":
            definition = json.loads(raw)
            definition["id"] = f"auto-{len(STATE['automations']) + 1:04d}"
            STATE["automations"].append(definition)
            return self._send(200, {"id": definition["id"]})
        if self.path.startswith("/cez/automations/"):
            auto_id = self.path.rsplit("/", 1)[1]
            for index, item in enumerate(STATE["automations"]):
                if item["id"] == auto_id:
                    updated = json.loads(raw)
                    updated.update({"id": auto_id, "enabled": item.get("enabled", False)})
                    STATE["automations"][index] = updated
                    return self._send(200, {"id": auto_id})
            return self._send(404, {"message": "Not Found"})
        repo_prefix = f"/github/repos/{STATE['control_repo']}/"
        if self.path.startswith(repo_prefix) and STATE["control_private"] is not None:
            rest = self.path[len(repo_prefix):]
            body = json.loads(raw or b"{}")
            if rest == "labels":
                STATE["labels"].append({"name": body["name"]})
                return self._send(201, body)
            if rest == "issues":
                issue = {"number": len(STATE["issues"]) + 1, "title": body["title"],
                         "labels": [{"name": n} for n in body.get("labels", [])]}
                STATE["issues"].append(issue)
                return self._send(201, issue)
        return self._send(404, {"message": "Not Found"})

    def do_PUT(self):
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b"{}"
        self._record("PUT", raw)
        repo_prefix = f"/github/repos/{STATE['control_repo']}/contents/"
        if self.path.startswith(repo_prefix) and STATE["control_private"] is not None:
            path = self.path[len(repo_prefix):]
            body = json.loads(raw)
            current = STATE["contents"].get(path)
            if current is not None and body.get("sha") != current["sha"]:
                return self._send(409, {"message": "sha mismatch"})
            base64.b64decode(body["content"])
            sha = f"sha{len(REQUESTS)}"
            STATE["contents"][path] = {"sha": sha, "content": body["content"]}
            return self._send(201, {"content": {"sha": sha}})
        return self._send(404, {"message": "Not Found"})

    def _record(self, method, raw):
        entry = {"method": method, "path": self.path}
        if raw and raw != b"{}":
            try:
                entry["body"] = json.loads(raw)
            except ValueError:
                pass
        REQUESTS.append(entry)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=0)
    parser.add_argument("--port-file")
    args = parser.parse_args()
    server = ThreadingHTTPServer(("0.0.0.0", args.port), Handler)
    if args.port_file:
        with open(args.port_file, "w", encoding="utf-8") as fh:
            fh.write(str(server.server_address[1]))
    server.serve_forever()


if __name__ == "__main__":
    main()
