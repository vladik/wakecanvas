#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
INSTALL_ROOT=$SCRIPT_DIR
RELEASE="$INSTALL_ROOT/bin/wake_canvas"
INITIALIZER="$INSTALL_ROOT/initialize-wakecanvas.sh"
DATA_ROOT=${WAKECANVAS_DATA_ROOT:-"$INSTALL_ROOT/data"}
PORT=${PORT:-4000}
STARTUP_DELAY=${WAKECANVAS_BROWSER_DELAY:-3}
NO_BROWSER=0
ONCE=0
SERVER_PID=""
BROWSER_PID=""

# Runtime configuration, SQLite files, cookies, and uploaded media belong only to
# the dedicated kiosk user unless the operator explicitly changes permissions.
umask 077

usage() {
  echo "Usage: $0 [--port PORT] [--no-browser] [--once]"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --port)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      PORT=$2
      shift 2
      ;;
    --no-browser) NO_BROWSER=1; shift ;;
    --once) ONCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

[ -x "$RELEASE" ] || { echo "WakeCanvas release executable not found: $RELEASE" >&2; exit 1; }
[ -f "$DATA_ROOT/config/management_code" ] || "$INITIALIZER" --non-interactive

export PHX_SERVER=true
export PORT
export PHX_HOST=${PHX_HOST:-localhost}
export PHX_SCHEME=${PHX_SCHEME:-http}
export PHX_URL_PORT=${PHX_URL_PORT:-$PORT}
export WAKECANVAS_BIND_IP=${WAKECANVAS_BIND_IP:-0.0.0.0}
export WAKECANVAS_DATA_ROOT=$DATA_ROOT

HEALTH_URL="http://127.0.0.1:$PORT/health"
DISPLAY_URL="http://127.0.0.1:$PORT/display"

is_reachable() {
  curl --silent --output /dev/null --max-time 3 "$HEALTH_URL"
}

start_server() {
  if is_reachable; then return 0; fi
  "$RELEASE" start &
  SERVER_PID=$!

  attempts=0
  while [ "$attempts" -lt 45 ]; do
    if is_reachable; then return 0; fi
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
      wait "$SERVER_PID" || status=$?
      echo "WakeCanvas exited during startup (${status:-unknown})." >&2
      exit 1
    fi
    attempts=$((attempts + 1))
    sleep 1
  done
  echo "WakeCanvas did not become reachable at $HEALTH_URL" >&2
  exit 1
}

stop_server() {
  if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
    kill -TERM "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  SERVER_PID=""
}

find_browser() {
  for candidate in chromium chromium-browser google-chrome-stable google-chrome; do
    if command -v "$candidate" >/dev/null 2>&1; then
      command -v "$candidate"
      return 0
    fi
  done
  return 1
}

start_browser() {
  [ "$NO_BROWSER" -eq 0 ] || return 0
  if BROWSER=$(find_browser); then
    mkdir -p "$DATA_ROOT/browser-profile"
    "$BROWSER" \
      --kiosk "$DISPLAY_URL" \
      --no-first-run \
      --disable-session-crashed-bubble \
      --autoplay-policy=no-user-gesture-required \
      --ozone-platform-hint=auto \
      --user-data-dir="$DATA_ROOT/browser-profile" &
    BROWSER_PID=$!
  else
    echo "Chromium or Google Chrome was not found; the display was not opened." >&2
    BROWSER_PID=""
  fi
}

cleanup() {
  if [ -n "$BROWSER_PID" ] && kill -0 "$BROWSER_PID" 2>/dev/null; then
    kill -TERM "$BROWSER_PID" 2>/dev/null || true
    wait "$BROWSER_PID" 2>/dev/null || true
  fi
  stop_server
}

shutdown() {
  trap - INT TERM EXIT
  cleanup
  exit 0
}

trap cleanup EXIT
trap shutdown INT TERM

start_server
sleep "$STARTUP_DELAY"
start_browser

echo "WakeCanvas display: $DISPLAY_URL"
echo "WakeCanvas management: http://127.0.0.1:$PORT/manage"
if command -v hostname >/dev/null 2>&1; then
  for address in $(hostname -I 2>/dev/null || true); do
    case "$address" in
      *:*) ;;
      *) echo "LAN management: http://$address:$PORT/manage" ;;
    esac
  done
fi

if [ "$ONCE" -eq 1 ]; then
  trap - INT TERM EXIT
  exit 0
fi

failures=0
while :; do
  sleep 5
  if is_reachable; then
    failures=0
  else
    failures=$((failures + 1))
    if [ "$failures" -ge 3 ]; then
      echo "WakeCanvas stopped responding; exiting for service restart." >&2
      exit 1
    fi
  fi

  if [ "$NO_BROWSER" -eq 0 ] && [ -n "$BROWSER_PID" ] && ! kill -0 "$BROWSER_PID" 2>/dev/null; then
    wait "$BROWSER_PID" 2>/dev/null || true
    echo "The kiosk browser closed; reopening it." >&2
    start_browser
  fi
done
