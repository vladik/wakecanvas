WakeCanvas for Windows
======================

1. Extract the complete ZIP into a permanent writable folder.
2. Run Initialize-WakeCanvas.ps1 and choose a six-digit management code.
3. Run Start-WakeCanvas.ps1.
4. Open http://localhost:4000/manage from the kiosk or another device on the LAN.
5. Optionally run Install-Autostart.ps1 once to start the kiosk after sign-in.

The release includes Erlang/OTP and Elixir. Node.js, a database server, and an
internet connection are not required. Persistent state is stored in the data
folder beside this file. Back up that folder. Moving the installation preserves
its identity, settings, packages, instances, and media.

The packages folder contains optional Experience archives. Install one through
the management view, restart WakeCanvas when prompted, then create an instance.

To stop the release manually:

    .\bin\wake_canvas.bat stop

If port 4000 is already occupied, start with another port:

    .\Start-WakeCanvas.ps1 -Port 4100
