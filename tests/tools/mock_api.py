#!/usr/bin/env python3
"""Mock of the external APIs used by swarm-of-agents scripts in tests.

Routes:
  GET  /api/v1/health             Cezar health (healthResponseSchema subset)
  GET  /api/v1/workspace/config   Cezar workspace config (resources.maxParallel)
  POST /api/v1/projects/create    Cezar project + private repository {name, github:{owner}}
  GET  /cez/p/<project>/automations           automations of one project (what `cez automation list` reads)
  POST /cez/p/<project>/automations[/<id>]    create / update an automation definition in that project
  GET  /github/<path>             GitHub REST, from the in-memory state
  POST /github/<path>             GitHub REST writes: labels, issues (create)
  PUT  /github/<path>             GitHub REST writes: repository contents
  GET/POST /github/repos/<control>/issues/<n>/comments   issue comments, state "comments" ("<n>" -> list of {body, created_at})
  POST /m/push/gate               cezar-push gate: 401 without the token (state "push_token", default "test-token"),
                                  400 for Origin/X-Forwarded-For or a body other than {gate, repo, number, title<=100, url}; else 202
  GET  /api/v1/p/<project>/runs[/<id>]        Cezar tasks of one project, from state "runs"
                                              (list of records; a record with "project" is visible only there)
  GET/PATCH /github/repos/<o>/<r>/pulls/<n>   PR from state "pulls" ("<o>/<r>#<n>" -> {head_sha, body, merged})
  PUT  /github/repos/<o>/<r>/pulls/<n>/merge  409 unless body.sha equals the head sha
  POST /__control                 change state, e.g. {"health_status": 503}
  GET  /__requests                requests received so far (JSON list)

State keys: health_status, github_user (null = logged out), control_repo,
control_private (null = repository missing), max_parallel, labels, issues,
contents, repo_files (other repositories: "owner/name/path" entries), runs, automations (starts with automations of another agent chain, which
must stay untouched).

Usage: mock_api.py [--port N] [--port-file FILE]   (port 0 = random)
"""
import argparse
import base64
import copy
import datetime
import json
import re
from urllib.parse import parse_qs, urlsplit
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

DEFAULTS = {
    "health_status": 200,
    "github_user": "cieyhomelab",
    "control_repo": "cieyhomelab/sw-control",
    "control_private": True,
    "max_parallel": 3,
    "hide_project": False,
    "labels": [],
    "issues": [],
    "contents": {},
    "pulls": {},
    "repo_files": [],
    "runs": [],
    "comments": {},
    "push_token": "test-token",
    "automations": [
        {"id": "a1b2c3d4-0001", "name": "sh: architekt", "enabled": True, "project": "swarm-of-agents"},
        {"id": "a1b2c3d4-0002", "name": "sh: realizacja", "enabled": True, "project": "swarm-of-agents"},
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
            projects = [{"id": "swarm-of-agents", "name": "swarm-of-agents"}]
            if STATE["control_private"] is not None and not STATE["hide_project"]:
                projects.append({"id": "proj-sw-control", "name": STATE["control_repo"].split("/")[1]})
            return self._send(200, {"version": "0.0.0-mock", "projects": projects, "bootProject": "mock"})
        if self.path == "/api/v1/workspace/config":
            return self._send(200, {"resources": {"maxParallel": STATE["max_parallel"]}})
        pull = re.fullmatch(r"/github/repos/([^/]+/[^/]+)/pulls/(\d+)", self.path)
        if pull:
            item = STATE["pulls"].get(f"{pull[1]}#{pull[2]}")
            if item is None:
                return self._send(404, {"message": "Not Found"})
            return self._send(200, {"number": int(pull[2]), "body": item.get("body", ""),
                                    "merged": item.get("merged", False), "head": {"sha": item["head_sha"]}})
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
        run = re.fullmatch(r"/api/v1/p/([^/]+)/runs(?:/([^/]+))?", self.path)
        if run:
            runs = STATE["runs"]
            if isinstance(runs, list):
                runs = [r for r in runs if r.get("project", run[1]) == run[1]]
            if run[2] is None:
                return self._send(200, runs)
            found = [r for r in runs if r["id"] == run[2]]
            return self._send(200, found[0]) if found else self._send(404, {"message": "Not Found"})
        github_file = re.fullmatch(r"/github/repos/([^/]+/[^/]+)/contents/(.+)", self.path)
        if github_file and f"{github_file[1]}/{github_file[2]}" in STATE["repo_files"]:
            return self._send(200, {"sha": "sha0", "content": ""})
        automations = re.fullmatch(r"/cez/p/([^/]+)/automations", self.path)
        if automations:
            return self._send(200, [a for a in STATE["automations"] if a.get("project") == automations[1]])
        url = urlsplit(self.path)
        repo_prefix = f"/github/repos/{STATE['control_repo']}/"
        if url.path.startswith(repo_prefix) and STATE["control_private"] is not None:
            rest = url.path[len(repo_prefix):]
            if rest == "labels":
                return self._send(200, STATE["labels"])
            comments = re.fullmatch(r"issues/(\d+)/comments", rest)
            if comments:
                return self._send(200, STATE["comments"].get(comments[1], []))
            if rest == "issues":
                wanted = parse_qs(url.query).get("labels", [None])[0]
                state = parse_qs(url.query).get("state", ["open"])[0]
                found = [i for i in STATE["issues"]
                         if (wanted is None or wanted in [lb["name"] for lb in i["labels"]])
                         and (state == "all" or i.get("state", "open") == state)]
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
            return self._send(200, {"id": "proj-" + body["name"], "name": body["name"]})
        if self.path == "/m/push/gate":
            return self._push_gate(raw)
        created = re.fullmatch(r"/cez/p/([^/]+)/automations", self.path)
        if created:
            definition = json.loads(raw)
            definition["project"] = created[1]
            definition["id"] = f"auto-{len(STATE['automations']) + 1:04d}"
            STATE["automations"].append(definition)
            return self._send(200, {"id": definition["id"]})
        changed = re.fullmatch(r"/cez/p/([^/]+)/automations/([^/]+)", self.path)
        if changed:
            auto_id = changed[2]
            for index, item in enumerate(STATE["automations"]):
                if item["id"] == auto_id and item.get("project") == changed[1]:
                    updated = json.loads(raw)
                    updated.update({"id": auto_id, "enabled": item.get("enabled", False), "project": changed[1]})
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
            comments = re.fullmatch(r"issues/(\d+)/comments", rest)
            if comments:
                now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
                comment = {"body": body["body"], "created_at": now}
                STATE["comments"].setdefault(comments[1], []).append(comment)
                return self._send(201, comment)
            if rest == "issues":
                issue = {"number": len(STATE["issues"]) + 1, "title": body["title"],
                         "body": body.get("body", ""), "state": "open",
                         "labels": [{"name": n} for n in body.get("labels", [])]}
                STATE["issues"].append(issue)
                return self._send(201, issue)
        return self._send(404, {"message": "Not Found"})

    def do_PATCH(self):
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b"{}"
        self._record("PATCH", raw)
        pull = re.fullmatch(r"/github/repos/([^/]+/[^/]+)/pulls/(\d+)", self.path)
        item = STATE["pulls"].get(f"{pull[1]}#{pull[2]}") if pull else None
        if item is None:
            return self._send(404, {"message": "Not Found"})
        item["body"] = json.loads(raw).get("body", item.get("body", ""))
        return self._send(200, {"number": int(pull[2])})

    def do_PUT(self):
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b"{}"
        self._record("PUT", raw)
        merge = re.fullmatch(r"/github/repos/([^/]+/[^/]+)/pulls/(\d+)/merge", self.path)
        if merge:
            item = STATE["pulls"].get(f"{merge[1]}#{merge[2]}")
            if item is None:
                return self._send(404, {"message": "Not Found"})
            if json.loads(raw).get("sha") != item["head_sha"]:
                return self._send(409, {"message": "Head branch was modified"})
            item["merged"] = True
            return self._send(200, {"merged": True})
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

    def _push_gate(self, raw):
        if self.headers.get("X-Cezar-Push-Token") != STATE["push_token"]:
            return self._send(401, {"error": "unauthorized"})
        if self.headers.get("Origin") is not None or self.headers.get("X-Forwarded-For") is not None:
            return self._send(400, {"error": "forbidden header"})
        try:
            body = json.loads(raw)
        except ValueError:
            return self._send(400, {"error": "invalid json"})
        valid = (
            isinstance(body, dict)
            and set(body) == {"gate", "repo", "number", "title", "url"}
            and body["gate"] in ("spec", "merge", "blocked")
            and isinstance(body["number"], int)
            and isinstance(body["title"], str) and len(body["title"]) <= 100
            and isinstance(body["url"], str) and body["url"].startswith("https://github.com/")
        )
        if not valid:
            return self._send(400, {"error": "invalid body"})
        return self._send(202, {"accepted": True})

    def _record(self, method, raw):
        entry = {"method": method, "path": self.path}
        if self.path == "/m/push/gate":
            entry["headers"] = {k.lower(): v for k, v in self.headers.items()}
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
