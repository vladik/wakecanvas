#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
INSTALL_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
DATA_ROOT=${WAKECANVAS_DATA_ROOT:-"$INSTALL_ROOT/data"}
CODE_PATH="$DATA_ROOT/config/management_code"
MANAGEMENT_CODE=""
OPEN_MANAGEMENT=0
NON_INTERACTIVE=0
FORCE=0

usage() {
  echo "Usage: initialize-wakecanvas.sh [--management-code 123456 | --open-management] [--non-interactive] [--force]"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --management-code)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      MANAGEMENT_CODE=$2
      shift 2
      ;;
    --open-management) OPEN_MANAGEMENT=1; shift ;;
    --non-interactive) NON_INTERACTIVE=1; shift ;;
    --force) FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

mkdir -p "$DATA_ROOT/config" "$DATA_ROOT/instances" "$DATA_ROOT/packages"

if [ -f "$CODE_PATH" ] && [ "$FORCE" -ne 1 ]; then
  echo "WakeCanvas is already initialized at $DATA_ROOT"
  echo "Use --force to replace the management-code configuration."
  exit 0
fi

if [ "$OPEN_MANAGEMENT" -eq 1 ]; then
  MANAGEMENT_CODE=""
elif [ -n "$MANAGEMENT_CODE" ]; then
  :
elif [ "$NON_INTERACTIVE" -eq 1 ]; then
  RANDOM_NUMBER=$(od -An -N4 -tu4 /dev/urandom | tr -d ' ')
  MANAGEMENT_CODE=$(printf '%06d' "$((RANDOM_NUMBER % 1000000))")
else
  while :; do
    printf 'Choose a 6-digit management code: '
    IFS= read -r MANAGEMENT_CODE
    case "$MANAGEMENT_CODE" in
      [0-9][0-9][0-9][0-9][0-9][0-9]) break ;;
      *) echo "The code must contain exactly six digits." >&2 ;;
    esac
  done
fi

case "$MANAGEMENT_CODE" in
  ""|[0-9][0-9][0-9][0-9][0-9][0-9]) ;;
  *) echo "The management code must contain exactly six digits." >&2; exit 2 ;;
esac

umask 077
printf '%s\n' "$MANAGEMENT_CODE" > "$CODE_PATH"

echo "WakeCanvas data directory: $DATA_ROOT"
if [ -n "$MANAGEMENT_CODE" ]; then
  echo "Management code: $MANAGEMENT_CODE"
  echo "Keep this code available to workshop operators."
else
  echo "WARNING: management views are open because no code was configured." >&2
fi
