#!/usr/bin/env bats
# Integration: bin/sw-deploy (S10) with the fake Docker (tests/fakes/docker): the container of the
# application on an internal network, the proxy with a login as the only entry, the denial test,
# and the guarantee that a failed deployment leaves nothing reachable. The listener of the fake
# proxy is real, so curl in sw-deploy talks to it exactly as on the VPS.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  WORK="$(mktemp -d)"
  export PATH="$ROOT/tests/fakes:$PATH"
  export FAKE_DOCKER_DIR="$WORK/docker" FAKE_DOCKER_LOGIN="wlasciciel:sekretne-haslo"
  export SW_DEPLOY_DIR="$WORK/state" SW_DEPLOY_NAME=Planer-Posilkow SW_DEPLOY_POLL=0.1
  export SW_DEPLOY_LOGIN_FILE="$WORK/login"
  printf '%s\n' "$FAKE_DOCKER_LOGIN" > "$SW_DEPLOY_LOGIN_FILE"; chmod 600 "$SW_DEPLOY_LOGIN_FILE"
  # a port range of its own, so that parallel runs of other tests do not collide
  jq '.deploy.portRangeStart = 18700 | .deploy.portRangeEnd = 18709 | .deploy.readySeconds = 2' "$ROOT/config/sw.json" > "$WORK/sw.json"
  export SW_CONFIG="$WORK/sw.json"
  mkdir -p "$WORK/app"; cd "$WORK/app" || return 1
  printf 'FROM scratch\nEXPOSE 3000\n' > Dockerfile
}

teardown() {
  for f in "$FAKE_DOCKER_DIR"/pid-*; do [ ! -e "$f" ] || kill "$(cat "$f")" 2>/dev/null || true; done
  cd / && rm -rf "$WORK"
}

calls() { cat "$FAKE_DOCKER_DIR/calls"; }
# the HTTP code of the deployed address without / with a login
anon() { curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$1/" || true; }
authed() { curl -s -o /dev/null -w '%{http_code}' --max-time 5 -u "$FAKE_DOCKER_LOGIN" "$1/" || true; }

@test "S10 the deployment answers 401 without the login and shows the application to the logged-in owner" {
  run "$ROOT/bin/sw-deploy"
  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = "WYNIK: WDROZONO http://127.0.0.1:18700" ]
  [ "$(anon http://127.0.0.1:18700)" = 401 ]
  [ "$(authed http://127.0.0.1:18700)" = 200 ]
  [ "$(jq -r .url .ai/sw-run/wdrozenie.json)" = http://127.0.0.1:18700 ]
  [ "$(jq -r .nazwa .ai/sw-run/wdrozenie.json)" = Planer-Posilkow ]
}

@test "S10 the application sits on an internal network and publishes no port; only the proxy is published, on the private address" {
  run "$ROOT/bin/sw-deploy"
  [ "$status" -eq 0 ]
  grep -q -- 'network create --internal sw-net-planer-posilkow' <(calls)
  # the application container: no -p, the proxy: one -p on the bind address
  [ "$(calls | grep '^run ' | grep -c -- ' -p ')" -eq 0 ]
  [ "$(calls | grep '^create ' | grep -c -- '-p 127.0.0.1:18700:8080')" -eq 1 ]
  # the proxy joins the application network before it starts and nginx points at the EXPOSEd port
  [ "$(calls | grep -n 'network connect' | cut -d: -f1)" -lt "$(calls | grep -n '^start' | cut -d: -f1)" ]
  grep -q 'proxy_pass http://app:3000;' "$SW_DEPLOY_DIR/planer-posilkow/nginx.conf"
  grep -q 'auth_basic_user_file' "$SW_DEPLOY_DIR/planer-posilkow/nginx.conf"
  # the password is not in the proxy files in the clear
  ! grep -rq 'sekretne-haslo' "$SW_DEPLOY_DIR"
  [[ "$output" != *"sekretne-haslo"* ]]
  [ "$(stat -c %a "$SW_DEPLOY_DIR/planer-posilkow/htpasswd")" = 600 ]
}

@test "S10 a redeployment replaces the previous containers and keeps the port" {
  run "$ROOT/bin/sw-deploy"; [ "$status" -eq 0 ]
  run "$ROOT/bin/sw-deploy"
  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = "WYNIK: WDROZONO http://127.0.0.1:18700" ]
  [ "$(authed http://127.0.0.1:18700)" = 200 ]
}

@test "S10 a proxy without authentication fails the denial test and nothing stays reachable" {
  FAKE_DOCKER_MODE=open run "$ROOT/bin/sw-deploy"
  [ "$status" -eq 1 ]
  [[ "$output" == *"STAN: BLAD"* && "$output" == *"zamiast odmowy"* ]]
  [ "$(anon http://127.0.0.1:18700)" = 000 ]
  [ ! -e .ai/sw-run/wdrozenie.json ]
  # the cleanup removed the containers and the network
  grep -q '^rm -f sw-proxy-planer-posilkow sw-app-planer-posilkow' <(calls)
  grep -q '^network rm sw-net-planer-posilkow' <(calls)
}

@test "S10 an application that does not answer after the login fails the deployment and nothing stays reachable" {
  FAKE_DOCKER_MODE=dead run "$ROOT/bin/sw-deploy"
  [ "$status" -eq 1 ]
  [[ "$output" == *"STAN: BLAD aplikacja nie odpowiada"* ]]
  [ "$(anon http://127.0.0.1:18700)" = 000 ]
  [ "$(authed http://127.0.0.1:18700)" = 000 ]
}

@test "S10 a failed build starts nothing and the application is not reachable" {
  FAKE_DOCKER_MODE=build-fail run "$ROOT/bin/sw-deploy"
  [ "$status" -eq 1 ]
  [[ "$output" == *"STAN: BLAD nie mozna zbudowac obrazu"* ]]
  ! calls | grep -q '^run '
  [ "$(anon http://127.0.0.1:18700)" = 000 ]
}

@test "S10 an application container that publishes a port fails the deployment" {
  FAKE_DOCKER_MODE=published run "$ROOT/bin/sw-deploy"
  [ "$status" -eq 1 ]
  [[ "$output" == *"STAN: BLAD kontener aplikacji publikuje port"* ]]
  [ "$(anon http://127.0.0.1:18700)" = 000 ]
}

@test "S10 a missing Dockerfile, a missing or too open login file and a wildcard address stop before anything starts" {
  rm Dockerfile
  run "$ROOT/bin/sw-deploy"
  [ "$status" -eq 1 ]; [[ "$output" == *"STAN: BLAD brak Dockerfile"* ]]
  printf 'FROM scratch\n' > Dockerfile
  chmod 644 "$SW_DEPLOY_LOGIN_FILE"
  run "$ROOT/bin/sw-deploy"
  [ "$status" -eq 1 ]; [[ "$output" == *"za szerokie uprawnienia"* ]]
  rm "$SW_DEPLOY_LOGIN_FILE"
  run "$ROOT/bin/sw-deploy"
  [ "$status" -eq 1 ]; [[ "$output" == *"brak pliku z loginem"* ]]
  printf '%s\n' "$FAKE_DOCKER_LOGIN" > "$SW_DEPLOY_LOGIN_FILE"; chmod 600 "$SW_DEPLOY_LOGIN_FILE"
  jq '.deploy.bindAddress = "0.0.0.0"' "$SW_CONFIG" > "$WORK/wild.json"
  SW_CONFIG="$WORK/wild.json" run "$ROOT/bin/sw-deploy"
  [ "$status" -eq 1 ]; [[ "$output" == *"nie 0.0.0.0"* ]]
  [ ! -e "$FAKE_DOCKER_DIR/calls" ]
}

@test "S10 a busy port is skipped and an exhausted range is reported" {
  python3 -c 'import socket,time; s=socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); s.bind(("127.0.0.1",18700)); s.listen(50); time.sleep(30)' &
  holder=$!
  for _ in $(seq 1 50); do (exec 3<>/dev/tcp/127.0.0.1/18700) 2>/dev/null && break; sleep 0.1; done
  run "$ROOT/bin/sw-deploy"
  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = "WYNIK: WDROZONO http://127.0.0.1:18701" ]
  jq '.deploy.portRangeEnd = 18700' "$SW_CONFIG" > "$WORK/one.json"
  SW_CONFIG="$WORK/one.json" run "$ROOT/bin/sw-deploy"
  kill "$holder" 2>/dev/null || true
  [ "$status" -eq 1 ]; [[ "$output" == *"brak wolnego portu"* ]]
}
