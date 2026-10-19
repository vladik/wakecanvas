WakeCanvas for Linux
====================

1. Extract the complete tar.gz into a permanent writable directory.
2. Run ./initialize-wakecanvas.sh and choose a six-digit management code.
3. Run ./start-wakecanvas.sh.
4. Open http://localhost:4000/manage and install an Experience package.
5. Optionally run ./install-autostart.sh as the graphical kiosk user.

The release includes Erlang/OTP and Elixir. It needs no production Node.js,
database server, or internet connection. Persistent state is in ./data; back up
that complete directory.

A fullscreen display requires Chromium or Google Chrome and a graphical session.
For unattended operation, configure the kiosk operating system to log this user
into its desktop automatically. The systemd user service restarts WakeCanvas after
a process failure.

Run on another port with:

    ./start-wakecanvas.sh --port 4100

Run the server without opening a browser with:

    ./start-wakecanvas.sh --no-browser
