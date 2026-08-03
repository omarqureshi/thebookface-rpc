#!/usr/bin/env bash
# Runs the cucumber suite against a real browser.
#
# Two servers are needed: the Rack API and the Vite dev server that serves the
# SPA and proxies /rpc to it. This starts both, waits for them, runs the suite
# and tears them down.
#
#   script/cucumber.sh                 # everything
#   script/cucumber.sh features/comments.feature
set -uo pipefail
cd "$(dirname "$0")/.."

export DYNAMODB_ENDPOINT=${DYNAMODB_ENDPOINT:-http://localhost:8000}
API_LOG=/tmp/bookface-cuke-api.log
UI_LOG=/tmp/bookface-cuke-ui.log

port_pid() { ss -lptnH "sport = :$1" 2>/dev/null | grep -oP 'pid=\K[0-9]+' | head -1; }
stop() { local p; p=$(port_pid "$1"); [ -n "$p" ] && kill "$p" 2>/dev/null; }

cleanup() { stop 9292; stop 5173; }
trap cleanup EXIT

docker compose up -d >/dev/null 2>&1
for _ in $(seq 1 20); do curl -s -o /dev/null http://localhost:8000 && break; sleep 0.5; done
bundle exec ruby script/create_tables.rb >/dev/null 2>&1

stop 9292; stop 5173
bundle exec rackup -p 9292 -q >"$API_LOG" 2>&1 &
(cd web && npm run dev >"$UI_LOG" 2>&1 &)

wait_for() {
  for _ in $(seq 1 60); do curl -sf "$1" >/dev/null 2>&1 && return 0; sleep 0.5; done
  echo "timed out waiting for $1"; tail -20 "$2"; return 1
}
wait_for http://localhost:9292/up "$API_LOG" || exit 1
wait_for http://localhost:5173/ "$UI_LOG" || exit 1

bundle exec cucumber "$@"
