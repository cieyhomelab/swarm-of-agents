#!/usr/bin/env python3
"""Mock of the external APIs used by swarm-of-agents scripts in tests.

Routes:
  GET  /api/v1/health             Cezar health (healthResponseSchema subset)
  GET  /api/v1/workspace/config   Cezar workspace config (resources.maxParallel)
  GET  /github/<path>             GitHub REST, from the in-memory state
  POST /__control                 change state, e.g. {"health_status": 503}
  GET  /__requests                requests received so far (JSON list)

State keys: health_status, github_user (null = logged out), control_repo,
control_private (null = repository missing), max_parallel.

Usage: mock_api.py [--port N] [--port-file FILE]   (port 0 = random)
"""
import argparse
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

DEFAULTS = {
    "health_status": 200,
    "github_user": "cieyhomelab",
    "control_repo": "cieyhomelab/sw-control",
    "control_private": True,
    "max_parallel": 3,
}
STATE = dict(DEFAULTS)
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
        return self._send(404, {"message": "Not Found"})

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b"{}"
        REQUESTS.append({"method": "POST", "path": self.path})
        if self.path == "/__control":
            update = json.loads(raw or b"{}")
            if update.get("reset"):
                STATE.clear()
                STATE.update(DEFAULTS)
                REQUESTS.clear()
            STATE.update({k: v for k, v in update.items() if k != "reset"})
            return self._send(200, STATE)
        return self._send(404, {"message": "Not Found"})


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
