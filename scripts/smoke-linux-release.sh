#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
ARCHIVE=""
PORT=4410
SERVER_PID=""

usage() {
  echo "Usage: $0 --archive FILE [--port PORT]"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --archive)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      ARCHIVE=$2
      shift 2
      ;;
    --port)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      PORT=$2
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

[ -n "$ARCHIVE" ] || { usage >&2; exit 2; }
ARCHIVE=$(CDPATH= cd -- "$(dirname -- "$ARCHIVE")" && pwd)/$(basename -- "$ARCHIVE")
[ -f "$ARCHIVE" ] || { echo "Release archive not found: $ARCHIVE" >&2; exit 1; }

mkdir -p "$REPO_ROOT/.tmp"
TEST_ROOT=$(mktemp -d "$REPO_ROOT/.tmp/linux-smoke.XXXXXX")
INSTALL_ROOT="$TEST_ROOT/WakeCanvas"
LOG_PATH="$TEST_ROOT/wakecanvas.log"

stop_server() {
  if [ -x "$INSTALL_ROOT/stop-wakecanvas.sh" ]; then
    WAKECANVAS_DATA_ROOT="$INSTALL_ROOT/data" PORT="$PORT" \
      "$INSTALL_ROOT/stop-wakecanvas.sh" >/dev/null 2>&1 || true
  fi
  if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
    kill -TERM "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  SERVER_PID=""
}

stop_and_wait() {
  "$INSTALL_ROOT/stop-wakecanvas.sh"
  SERVER_PID=""
  attempts=0
  while [ "$attempts" -lt 20 ]; do
    if ! curl --silent --output /dev/null --max-time 1 "$HEALTH_URL"; then return 0; fi
    attempts=$((attempts + 1))
    sleep 1
  done
  echo "WakeCanvas remained reachable after the packaged stop command." >&2
  exit 1
}

cleanup() {
  stop_server
  case "$TEST_ROOT" in
    "$REPO_ROOT/.tmp/"linux-smoke.*) rm -rf -- "$TEST_ROOT" ;;
    *) echo "Refusing unsafe smoke cleanup: $TEST_ROOT" >&2 ;;
  esac
}

shutdown() {
  trap - EXIT INT TERM
  cleanup
  exit 130
}

trap cleanup EXIT
trap shutdown INT TERM

tar -C "$TEST_ROOT" -xzf "$ARCHIVE"

for command in start-wakecanvas.sh stop-wakecanvas.sh start-kiosk-mode.sh open-management.sh; do
  [ -x "$INSTALL_ROOT/$command" ] || {
    echo "Missing public Linux command: $command" >&2
    exit 1
  }
done

for command in initialize-wakecanvas.sh install-autostart.sh uninstall-autostart.sh; do
  [ ! -e "$INSTALL_ROOT/$command" ] || {
    echo "Administrative command leaked into the release root: $command" >&2
    exit 1
  }
done

for command in initialize-wakecanvas.sh run-wakecanvas.sh stop-wakecanvas.sh install-autostart.sh uninstall-autostart.sh; do
  [ -x "$INSTALL_ROOT/admin-tools/$command" ] || {
    echo "Missing Linux admin tool: $command" >&2
    exit 1
  }
done

"$INSTALL_ROOT/admin-tools/initialize-wakecanvas.sh" --management-code 123456

export PHX_SERVER=true
export PORT
export PHX_HOST=localhost
export PHX_SCHEME=http
export PHX_URL_PORT=$PORT
export WAKECANVAS_BIND_IP=127.0.0.1
export WAKECANVAS_DATA_ROOT="$INSTALL_ROOT/data"
HEALTH_URL="http://127.0.0.1:$PORT/health"

start_and_wait() {
  "$INSTALL_ROOT/bin/wake_canvas" start >"$LOG_PATH" 2>&1 &
  SERVER_PID=$!
  attempts=0
  while [ "$attempts" -lt 45 ]; do
    if curl --silent --output /dev/null --max-time 3 "$HEALTH_URL"; then return 0; fi
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
      cat "$LOG_PATH" >&2
      echo "WakeCanvas exited during smoke-test startup." >&2
      exit 1
    fi
    attempts=$((attempts + 1))
    sleep 1
  done
  cat "$LOG_PATH" >&2
  echo "WakeCanvas did not become reachable at $HEALTH_URL" >&2
  exit 1
}

start_and_wait
[ -f "$INSTALL_ROOT/data/wake_canvas.sqlite3" ] || { echo "Platform database was not created." >&2; exit 1; }
[ -f "$INSTALL_ROOT/data/config/secret_key_base" ] || { echo "Cookie secret was not created." >&2; exit 1; }
SECRET_BEFORE=$(cat "$INSTALL_ROOT/data/config/secret_key_base")
stop_and_wait

start_and_wait
SECRET_AFTER=$(cat "$INSTALL_ROOT/data/config/secret_key_base")
[ "$SECRET_BEFORE" = "$SECRET_AFTER" ] || { echo "Cookie secret changed after restart." >&2; exit 1; }
stop_and_wait

echo "Linux release smoke test passed on $(uname -m)."
