#!/usr/bin/env python3
"""Mock of the external APIs used by swarm-of-agents scripts in tests.

Routes:
  GET  /api/v1/health             Cezar health (healthResponseSchema subset)
  GET  /api/v1/workspace/config   Cezar workspace config (resources.maxParallel)
  POST /api/v1/projects/create    Cezar project + private repository {name, github:{owner}}; a name in state
                                  "create_fail" ({name: 409|500}) fails with that status, a name already in
                                  state "projects" or "repos" gives 409; a name in state "create_race" ({name: 409|500}) registers a foreign
                                  repository of that name and then fails with that status; registers the repository in "repos"
  POST /api/v1/projects/checkout  register an existing repository {url} as a Cezar project (state "projects")
  PATCH /api/v1/projects/<id>     {maxParallel}: stored on the project in state "projects"
  GET  /github/repos/<o>/<r>[/contents/<path>]   (state "repo_fail" {"o/r": status} fails it with that status) other repositories, state "repos" ("o/r" -> {private, topics,
                                  files: {path: {sha, content}}}); PUT /contents/<path> creates a file (201;
                                  409 when it exists without its sha), PUT /topics {names} replaces the topics
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
  POST /api/v1/p/<project>/runs/<id>/cancel   cancel a live task (status "cancelled"): {cancelled: bool}
  POST /api/v1/p/<project>/runs   create a task {task, autonomous, workflow?}: appended to state "runs"
                                  (state "run_create_fail" = a status code makes it fail with that status)
                                  as {id "run-N", project, task, workflow, autonomous, status "waiting"}
  GET  /api/v1/p/<project>/runs/<id>/history  task messages, state "histories" (run id -> list of
                                              {role: "user"|"assistant", text}); 404 for an unknown run
  GET  /github/repos/<control>/issues/<n>   one issue of the control repository
  PATCH /github/repos/<control>/issues/<n>  body / labels (list of names) / state of that issue
  GET/PATCH /github/repos/<o>/<r>/pulls/<n>   PR from state "pulls" ("<o>/<r>#<n>" -> {head_sha, body, merged, draft})
  GET  /github/repos/<o>/<r>/pulls?[head=<o>:<branch>&]state=open|closed|all   open (not merged) PRs, closed (= merged) ones or
                                  both; with head only those whose state entry has that "branch":
                                  [{number, html_url, head: {sha}, merged_at}]
  POST /github/repos/<o>/<r>/pulls/<n>/ready  takes the PR out of draft (gh pr ready)
  PUT  /github/repos/<o>/<r>/pulls/<n>/merge  405 while the PR is a draft, 409 unless body.sha equals the head sha
  GET  /github/repos/<o>/<r>/commits/<sha>/check-runs  {check_runs: [...]} from state "check_runs" ("<o>/<r>@<sha>" -> list
                                  of {name, status, conclusion}); empty for an unknown SHA
  GET  /github/repos/<o>/<r>/commits?sha=<branch>&per_page=1  [{commit: {committer: {date}}}] from state "commits"
                                  ("<o>/<r>@<branch>" -> ISO time of the last commit); empty for an unknown branch
  GET/POST /github/repos/<o>/<r>/labels, /issues[?labels=&state=]  labels and issues of any repository other than
                                  the control one (state "app_labels", "app_issues": "<o>/<r>" -> list)
  POST /__control                 change state, e.g. {"health_status": 503}
  GET  /__requests                requests received so far (JSON list)

State keys: health_status, github_user (null = logged out), control_repo,
control_private (null = repository missing), max_parallel, labels, issues,
histories, contents, repos, projects, create_fail, repo_files (other repositories: "owner/name/path" entries), runs, automations (starts with automations of another agent chain, which
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
    "app_labels": {},
    "app_issues": {},
    "contents": {},
    "pulls": {},
    "check_runs": {},
    "commits": {},
    "repo_files": [],
    "runs": [],
    "repos": {},
    "projects": [],
    "create_fail": {},
    "repo_fail": {},
    "cancel_fail": None,
    "run_create_fail": None,
    "create_race": {},
    "histories": {},
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
            projects += [{"id": p["id"], "name": p["name"]} for p in STATE["projects"]]
            return self._send(200, {"version": "0.0.0-mock", "projects": projects, "bootProject": "mock"})
        if self.path == "/api/v1/workspace/config":
            return self._send(200, {"resources": {"maxParallel": STATE["max_parallel"]}})
        listing = re.fullmatch(r"/github/repos/([^/]+/[^/]+)/pulls\?(.*)", self.path)
        if listing:
            query = parse_qs(listing[2])
            branch = query.get("head", [""])[0].partition(":")[2]
            wanted = query.get("state", ["open"])[0]
            found = []
            for key, item in STATE["pulls"].items():
                repo, _, number = key.partition("#")
                merged = item.get("merged", False)
                if repo == listing[1] and (not branch or item.get("branch") == branch) \
                        and (wanted == "all" or (merged if wanted == "closed" else not merged)):
                    found.append({"number": int(number), "html_url": f"https://github.com/{repo}/pull/{number}",
                                  "draft": item.get("draft", False), "head": {"sha": item["head_sha"]},
                                  "merged_at": "2026-10-26T00:00:00Z" if merged else None})
            return self._send(200, found)
        pull = re.fullmatch(r"/github/repos/([^/]+/[^/]+)/pulls/(\d+)", self.path)
        if pull:
            item = STATE["pulls"].get(f"{pull[1]}#{pull[2]}")
            if item is None:
                return self._send(404, {"message": "Not Found"})
            return self._send(200, {"number": int(pull[2]), "body": item.get("body", ""),
                                    "merged": item.get("merged", False), "draft": item.get("draft", False), "head": {"sha": item["head_sha"]}})
        checks = re.fullmatch(r"/github/repos/([^/]+/[^/]+)/commits/([^/?]+)/check-runs(?:\?.*)?", self.path)
        if checks:
            runs = STATE["check_runs"].get(f"{checks[1]}@{checks[2]}", [])
            return self._send(200, {"total_count": len(runs), "check_runs": runs})
        commits = re.fullmatch(r"/github/repos/([^/]+/[^/]+)/commits\?(.*)", self.path)
        if commits:
            when = STATE["commits"].get(f"{commits[1]}@{parse_qs(commits[2]).get('sha', [''])[0]}")
            return self._send(200, [{"commit": {"committer": {"date": when}}}] if when else [])
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
        history = re.fullmatch(r"/api/v1/p/([^/]+)/runs/([^/]+)/history", self.path)
        if history:
            messages = STATE["histories"].get(history[2])
            return self._send(200, messages) if messages is not None else self._send(404, {"message": "Not Found"})
        run = re.fullmatch(r"/api/v1/p/([^/]+)/runs(?:/([^/]+))?", self.path)
        if run:
            runs = STATE["runs"]
            if isinstance(runs, list):
                runs = [r for r in runs if r.get("project", run[1]) == run[1]]
            if run[2] is None:
                return self._send(200, runs)
            found = [r for r in runs if r["id"] == run[2]]
            return self._send(200, found[0]) if found else self._send(404, {"message": "Not Found"})
        other = re.fullmatch(r"/github/repos/([^/]+/[^/]+)(?:/contents/(.+))?", self.path)
        if other and other[1] in STATE["repo_fail"]:
            return self._send(STATE["repo_fail"][other[1]], {"message": "Server Error"})
        if other and other[1] in STATE["repos"]:
            repo = STATE["repos"][other[1]]
            if other[2] is None:
                return self._send(200, {"full_name": other[1], "private": repo["private"], "topics": repo["topics"]})
            entry = repo["files"].get(other[2])
            if entry is None:
                return self._send(404, {"message": "Not Found"})
            return self._send(200, {"sha": entry["sha"], "content": entry["content"]})
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
            single = re.fullmatch(r"issues/(\d+)", rest)
            if single:
                found = [i for i in STATE["issues"] if i["number"] == int(single[1])]
                return self._send(200, found[0]) if found else self._send(404, {"message": "Not Found"})
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
        if self._app_repo("GET", url, b""):
            return
        return self._send(404, {"message": "Not Found"})

    def _app_repo(self, method, url, raw):
        """Labels and issues of an application repository; True when the request was answered."""
        match = re.fullmatch(r"/github/repos/([^/]+/[^/]+)/(labels|issues)", url.path)
        if not match or match[1] == STATE["control_repo"]:
            return False
        repo, kind = match[1], match[2]
        if kind == "labels":
            labels = STATE["app_labels"].setdefault(repo, [])
            if method == "GET":
                self._send(200, labels)
            else:
                labels.append({"name": json.loads(raw)["name"]})
                self._send(201, labels[-1])
            return True
        issues = STATE["app_issues"].setdefault(repo, [])
        if method == "GET":
            wanted = parse_qs(url.query).get("labels", [None])[0]
            state = parse_qs(url.query).get("state", ["open"])[0]
            self._send(200, [i for i in issues if (wanted is None or wanted in [lb["name"] for lb in i["labels"]])
                             and (state == "all" or i.get("state", "open") == state)])
        else:
            body = json.loads(raw)
            issues.append({"number": len(issues) + 1, "title": body["title"], "body": body.get("body", ""),
                           "state": "open", "labels": [{"name": n} for n in body.get("labels", [])]})
            self._send(201, issues[-1])
        return True

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
        ready = re.fullmatch(r"/github/repos/([^/]+/[^/]+)/pulls/(\d+)/ready", self.path)
        if ready:
            item = STATE["pulls"].get(f"{ready[1]}#{ready[2]}")
            if item is None:
                return self._send(404, {"message": "Not Found"})
            item["draft"] = False
            return self._send(200, {"draft": False})
        if self.path == "/api/v1/projects/create":
            body = json.loads(raw)
            full = f"{body.get('github', {}).get('owner', '')}/{body['name']}"
            race = STATE["create_race"].get(body["name"])
            if race:  # the name is taken by somebody else between the check and the POST
                STATE["repos"][full] = {"private": True, "topics": [], "files": {}}
                return self._send(race, {"error": "folder_exists" if race == 409 else "github_create"})
            failure = STATE["create_fail"].get(body["name"])
            if failure:
                return self._send(failure, {"error": "folder_exists" if failure == 409 else "github_create"})
            if full != STATE["control_repo"]:
                if full in STATE["repos"] or any(p["name"] == body["name"] for p in STATE["projects"]):
                    return self._send(409, {"error": "folder_exists"})
                STATE["repos"][full] = {"private": True, "topics": [], "files": {}}
                STATE["projects"].append({"id": "proj-" + body["name"], "name": body["name"]})
            else:
                STATE["control_private"] = True
            return self._send(200, {"id": "proj-" + body["name"], "name": body["name"]})
        if self.path == "/api/v1/projects/checkout":
            name = json.loads(raw)["url"].rstrip("/").split("/")[-1]
            project = {"id": "proj-" + name, "name": name}
            STATE["projects"].append(project)
            return self._send(200, project)
        if self.path == "/m/push/gate":
            return self._push_gate(raw)
        cancel = re.fullmatch(r"/api/v1/p/([^/]+)/runs/([^/]+)/cancel", self.path)
        if cancel and STATE["cancel_fail"]:
            return self._send(STATE["cancel_fail"], {"message": "Server Error"})
        if cancel and isinstance(STATE["runs"], list):
            found = [r for r in STATE["runs"] if r["id"] == cancel[2] and r.get("project", cancel[1]) == cancel[1]]
            if not found:
                return self._send(404, {"message": "Not Found"})
            live = found[0].get("status") in ("queued", "running", "waiting")
            if live:
                found[0]["status"] = "cancelled"
            return self._send(200, {"cancelled": live})
        started = re.fullmatch(r"/api/v1/p/([^/]+)/runs", self.path)
        if started:
            body = json.loads(raw or b"{}")
            if not isinstance(body.get("task"), str) or not isinstance(body.get("autonomous"), bool) \
                    or not isinstance(body.get("workflow", ""), str):
                return self._send(400, {"error": "task and autonomous are required, workflow is optional"})
            if STATE["run_create_fail"]:
                return self._send(STATE["run_create_fail"], {"message": "Server Error"})
            if not isinstance(STATE["runs"], list):
                return self._send(500, {"error": "state runs is not a list"})
            run = {"id": f"run-{len(STATE['runs']) + 1}", "project": started[1], "task": body["task"],
                   "workflow": body.get("workflow", ""), "autonomous": body["autonomous"], "status": "waiting"}
            if body.get("model"):
                run["model"] = body["model"]
            STATE["runs"].append(run)
            return self._send(201, {"id": run["id"]})
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
        if self._app_repo("POST", urlsplit(self.path), raw):
            return
        return self._send(404, {"message": "Not Found"})

    def do_PATCH(self):
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b"{}"
        self._record("PATCH", raw)
        issue = re.fullmatch(rf"/github/repos/{re.escape(STATE['control_repo'])}/issues/(\d+)", self.path)
        if issue:
            found = [i for i in STATE["issues"] if i["number"] == int(issue[1])]
            if not found:
                return self._send(404, {"message": "Not Found"})
            update = json.loads(raw or b"{}")
            if "body" in update:
                found[0]["body"] = update["body"]
            if "labels" in update:
                found[0]["labels"] = [{"name": n} for n in update["labels"]]
            if "state" in update:
                found[0]["state"] = update["state"]
            return self._send(200, found[0])
        project = re.fullmatch(r"/api/v1/projects/([^/]+)", self.path)
        if project:
            found = [p for p in STATE["projects"] if p["id"] == project[1]]
            if not found:
                return self._send(404, {"message": "Not Found"})
            found[0]["maxParallel"] = json.loads(raw or b"{}").get("maxParallel")
            return self._send(200, found[0])
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
            if item.get("draft"):
                return self._send(405, {"message": "Pull Request is still a draft"})
            if json.loads(raw).get("sha") != item["head_sha"]:
                return self._send(409, {"message": "Head branch was modified"})
            item["merged"] = True
            return self._send(200, {"merged": True})
        other = re.fullmatch(r"/github/repos/([^/]+/[^/]+)/(?:contents/(.+)|topics)", self.path)
        if other and other[1] in STATE["repos"]:
            repo = STATE["repos"][other[1]]
            body = json.loads(raw or b"{}")
            if other[2] is None:
                repo["topics"] = body["names"]
                return self._send(200, {"names": repo["topics"]})
            current = repo["files"].get(other[2])
            if current is not None and body.get("sha") != current["sha"]:
                return self._send(409, {"message": "sha mismatch"})
            base64.b64decode(body["content"])
            sha = f"sha{len(REQUESTS)}"
            repo["files"][other[2]] = {"sha": sha, "content": body["content"]}
            return self._send(201, {"content": {"sha": sha}})
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
