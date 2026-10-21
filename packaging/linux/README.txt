WakeCanvas for Linux
====================

Normal use
----------

1. Extract the WakeCanvas archive into a permanent folder.
2. Run ./start-wakecanvas.sh.
3. On the first run, choose a six-digit management code when prompted.
4. Use ./open-management.sh to open the management view later.
5. Use ./stop-wakecanvas.sh to stop WakeCanvas.

The stop command also stops the installation-owned launcher, kiosk service, and
kiosk browser. After it finishes, the extracted WakeCanvas folder can be moved or
deleted safely.

For a fullscreen installation, run ./start-kiosk-mode.sh. WakeCanvas will start
the display in Chromium or Google Chrome when one is installed.

The first start creates the data directory automatically. There is no separate
initialization step for normal users.

Admin tools
-----------

Service installation, management-code replacement, and advanced launcher options
are deliberately kept in ./admin-tools so they are not confused with everyday
commands. See ./admin-tools/README.txt before using them.

WakeCanvas works without an internet connection. Other devices on the trusted
workshop network can use the LAN address printed by kiosk mode.
