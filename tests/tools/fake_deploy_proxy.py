#!/usr/bin/env python3
"""Stand-in for the nginx proxy that sw-deploy starts (used by tests/fakes/docker).

Usage: fake_deploy_proxy.py <bind> <port> <mode> <login>
  mode "ok":   401 without the login or with a wrong one, 200 "aplikacja" with it (like the real proxy);
  mode "open": 200 for everybody (a proxy that forgot the authentication: the denial test must catch it);
  mode "dead": 401 as in "ok", but 502 after the login (the application does not answer).
login is "user:password".
"""
import base64
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

bind, port, mode, login = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
expected = "Basic " + base64.b64encode(login.encode()).decode()


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        authed = mode == "open" or self.headers.get("Authorization") == expected
        if not authed:
            self.send_response(401)
            self.send_header("WWW-Authenticate", 'Basic realm="swarm-of-agents"')
            body = b"login required"
        elif mode == "dead":
            self.send_response(502)
            body = b"bad gateway"
        else:
            self.send_response(200)
            body = b"aplikacja"
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


HTTPServer((bind, port), Handler).serve_forever()
