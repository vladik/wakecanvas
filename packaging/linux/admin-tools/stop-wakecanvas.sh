#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
INSTALL_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
RELEASE="$INSTALL_ROOT/bin/wake_canvas"
DATA_ROOT=${WAKECANVAS_DATA_ROOT:-"$INSTALL_ROOT/data"}
PORT=${PORT:-4000}
LAUNCHER_PID_FILE="$DATA_ROOT/run/wakecanvas-launcher.pid"
BROWSER_PROFILE="$DATA_ROOT/browser-profile"

[ -x "$RELEASE" ] || {
  echo "WakeCanvas release executable not found: $RELEASE" >&2
  exit 1
}

export WAKECANVAS_DATA_ROOT=$DATA_ROOT
export PORT

# An explicitly stopped systemd unit is not restarted, even when the installed
# unit is configured to recover from unexpected failures.
if command -v systemctl >/dev/null 2>&1 && systemctl --user is-active --quiet wakecanvas-kiosk.service 2>/dev/null; then
  systemctl --user stop wakecanvas-kiosk.service || true
fi

if [ -f "$LAUNCHER_PID_FILE" ]; then
  LAUNCHER_PID=$(cat "$LAUNCHER_PID_FILE" 2>/dev/null || true)
  case "$LAUNCHER_PID" in
    ''|*[!0-9]*) ;;
    *)
      if kill -0 "$LAUNCHER_PID" 2>/dev/null; then
        COMMAND_LINE=""
        if [ -r "/proc/$LAUNCHER_PID/cmdline" ]; then
          COMMAND_LINE=$(tr '\000' ' ' < "/proc/$LAUNCHER_PID/cmdline")
        fi
        case "$COMMAND_LINE" in
          *"$INSTALL_ROOT"*run-wakecanvas.sh*) kill -TERM "$LAUNCHER_PID" 2>/dev/null || true ;;
          *) echo "Ignoring stale launcher PID $LAUNCHER_PID because it does not belong to this installation." >&2 ;;
        esac
      fi
      ;;
  esac
fi

"$RELEASE" stop >/dev/null 2>&1 || true

# Close only kiosk browsers that use this installation's dedicated profile.
for PROCESS_PATH in /proc/[0-9]*; do
  [ -r "$PROCESS_PATH/cmdline" ] || continue
  COMMAND_LINE=$(tr '\000' ' ' < "$PROCESS_PATH/cmdline")
  case "$COMMAND_LINE" in
    *"--user-data-dir=$BROWSER_PROFILE"*)
      PROCESS_PID=${PROCESS_PATH##*/}
      kill -TERM "$PROCESS_PID" 2>/dev/null || true
      ;;
  esac
done

rm -f -- "$LAUNCHER_PID_FILE"
echo "WakeCanvas and its installation-owned launcher and kiosk browser are stopped."
