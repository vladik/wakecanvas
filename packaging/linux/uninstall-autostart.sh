#!/bin/sh
set -eu

SERVICE_DIR=${XDG_CONFIG_HOME:-"$HOME/.config"}/systemd/user
SERVICE_PATH="$SERVICE_DIR/wakecanvas-kiosk.service"

systemctl --user disable --now wakecanvas-kiosk.service 2>/dev/null || true
rm -f -- "$SERVICE_PATH"
systemctl --user daemon-reload
echo "WakeCanvas autostart removed. Installation data was not deleted."
