#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SERVICE_DIR=${XDG_CONFIG_HOME:-"$HOME/.config"}/systemd/user
SERVICE_PATH="$SERVICE_DIR/wakecanvas-kiosk.service"

command -v systemctl >/dev/null 2>&1 || {
  echo "systemd is required for this autostart installer." >&2
  exit 1
}

mkdir -p "$SERVICE_DIR"
ESCAPED_SCRIPT=$(printf '%s' "$SCRIPT_DIR/start-wakecanvas.sh" | sed 's/%/%%/g; s/\\/\\\\/g; s/"/\\"/g')

cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=WakeCanvas kiosk
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart="$ESCAPED_SCRIPT"
Restart=always
RestartSec=5
TimeoutStopSec=20

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now wakecanvas-kiosk.service

echo "WakeCanvas autostart installed for user $(id -un)."
echo "Configure this kiosk user for graphical automatic login to start after reboot."
