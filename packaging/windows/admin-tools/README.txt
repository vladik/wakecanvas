WakeCanvas admin tools
======================

These commands are for an operator, technician, or recovery workflow. Normal
users should return to the parent folder and use its clearly named commands.

- initialize-wakecanvas.cmd creates or replaces local configuration.
- install-autostart.cmd enables fullscreen kiosk startup after Windows sign-in.
- uninstall-autostart.cmd removes kiosk autostart without deleting any data.
- run-wakecanvas.cmd exposes advanced launch options.
- stop-wakecanvas.cmd stops a running WakeCanvas release.

Windows accepts the same lowercase kebab-case options documented for Linux, for
example:

  initialize-wakecanvas.cmd --force --management-code 654321
  run-wakecanvas.cmd --profile manual --port 4100

The PowerShell files in internal are implementation details.
