#!/bin/sh
set -eu

PORT=${PORT:-4000}
MANAGEMENT_URL="http://localhost:$PORT/manage"

if command -v xdg-open >/dev/null 2>&1; then
  xdg-open "$MANAGEMENT_URL" >/dev/null 2>&1 &
else
  echo "Open $MANAGEMENT_URL in a browser."
fi
