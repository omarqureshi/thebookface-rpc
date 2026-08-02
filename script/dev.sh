#!/usr/bin/env bash
# Local dev loop. Every service in one process against DynamoDB Local.
#
#   script/dev.sh up       start dynamodb + create tables + serve
#   script/dev.sh serve    (re)start the server only
#   script/dev.sh stop     stop the server
#   script/dev.sh smoke    run a request smoke test
set -uo pipefail
cd "$(dirname "$0")/.."

PORT=${PORT:-9292}
export DYNAMODB_ENDPOINT=${DYNAMODB_ENDPOINT:-http://localhost:8000}
LOG=${LOG:-/tmp/bookface-rpc.log}
B="http://localhost:${PORT}/rpc"

server_pid() { ss -lptnH "sport = :${PORT}" 2>/dev/null | grep -oP 'pid=\K[0-9]+' | head -1; }

stop() {
  local pid; pid=$(server_pid)
  if [ -n "$pid" ]; then kill "$pid" 2>/dev/null; sleep 1; echo "stopped ($pid)"; else echo "not running"; fi
}

serve() {
  stop >/dev/null
  bundle exec rackup -p "$PORT" -q >"$LOG" 2>&1 &
  for _ in $(seq 1 40); do
    curl -sf "http://localhost:${PORT}/up" >/dev/null 2>&1 && { echo "serving on :${PORT}"; return 0; }
    sleep 0.5
  done
  echo "failed to start — see $LOG"; tail -20 "$LOG"; return 1
}

# Extract just the useful line from a Rack dev-error HTML page.
err() { grep -aE '^(TypeError|NoMethodError|ArgumentError|NameError|RuntimeError)' "$LOG" | tail -1; }

call() { # call <procedure> <json> [anon]
  local out code
  if [ "${3:-}" = "anon" ]; then
    out=$(curl -s -w '\n%{http_code}' -X POST "$B/$1" -H 'Content-Type: application/json' -d "$2")
  else
    out=$(curl -s -w '\n%{http_code}' -X POST "$B/$1" \
      -H 'Content-Type: application/json' \
      -H "X-Dev-Sub: ${DEV_SUB:-user-alice}" -H "X-Dev-Name: ${DEV_NAME:-Alice}" -d "$2")
  fi
  code=$(tail -1 <<<"$out"); body=$(sed '$d' <<<"$out")
  # Rack's error page is HTML; surface the exception instead of 80KB of markup.
  [[ "$body" == *"<!DOCTYPE"* ]] && body="500 $(err)"
  printf "  %-22s %-4s %s\n" "$1" "$code" "${body:0:150}"
}

case "${1:-up}" in
  up)
    docker compose up -d >/dev/null 2>&1 && echo "dynamodb-local up"
    for _ in $(seq 1 20); do curl -s -o /dev/null http://localhost:8000 && break; sleep 0.5; done
    bundle exec ruby script/create_tables.rb 2>/dev/null | grep -E 'created|exists'
    serve
    ;;
  serve) serve ;;
  stop)  stop ;;
  smoke)
    echo "--- writes"
    call posts/create '{"body":"Hello from a procedure."}'
    echo "--- contract errors"
    call posts/create '{"body":"nope"}' anon
    call posts/create '{"body":42}'
    call posts/create '{}'
    call posts/get    '{"id":"nope"}'
    echo "--- reads"
    printf "  %-22s %-4s %s\n" "posts.feed" "$(curl -s -o /dev/null -w '%{http_code}' "$B/posts/feed?input=%7B%7D")" \
      "$(curl -s "$B/posts/feed?input=%7B%7D" | head -c 150)"
    ;;
  *) echo "usage: $0 {up|serve|stop|smoke}"; exit 1 ;;
esac
