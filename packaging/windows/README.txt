WakeCanvas for Windows
======================

Manual presentation
-------------------

1. Extract the complete ZIP into a permanent writable folder.
2. Double-click "start-wakecanvas.cmd".
3. On first start, choose the six-digit management code if the presenter did
   not provide one.
4. The active display opens in the normal browser.
5. Double-click "stop-wakecanvas.cmd" when finished.

Double-click "open-management.cmd" to configure the installation. A prepared
demo ZIP imports its Experience instance, media, settings, and active variant
automatically on first start. Starting it again does not duplicate or overwrite
that instance.

Kiosk operation
---------------

"start-kiosk-mode.cmd" opens the active display fullscreen and monitors both
the WakeCanvas process and browser. An operator can use the clearly separated
"admin-tools" folder to install or remove automatic startup.

The release includes Erlang/OTP and Elixir. Node.js, a database server, and an
internet connection are not required. Persistent state is stored in the data
folder beside this file. Back up that folder. Other devices can use the kiosk's
LAN address in kiosk mode.

The commands under "admin-tools" are for operators and recovery only.
Normal users should use the named commands in this folder.
