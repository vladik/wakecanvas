# Windows kiosk release

WakeCanvas ships as a self-contained Windows x64 ZIP. It includes ERTS, the
Phoenix release, database migrations, static assets, kiosk scripts, and an
installable Living Gallery package. The target machine does not need Elixir,
Erlang, Node.js, SQLite, or internet access.

## Build and verify

Build on Windows x64 because Mix releases include the host ERTS and native SQLite
library. The build machine needs the documented Elixir/Erlang toolchain and Node.js
for compiling Experience browser assets; the resulting kiosk does not:

```powershell
.\scripts\build-windows-release.ps1 -Force
.\scripts\smoke-windows-release.ps1 `
  -Archive .\dist\wakecanvas-0.1.0-windows-x64.zip
```

The smoke test extracts into a unique temporary directory, initializes a new data
root, runs all migrations, checks the health endpoint, stops and restarts the
release, verifies durable database/secret files, then removes the test directory.
A diagnostic HTTP 503 is accepted as a reachable endpoint because the build
machine may legitimately report low disk space; it is not treated as a dead VM.

## Install and run

1. Extract the ZIP into a permanent folder writable by the kiosk user.
2. Run `Initialize-WakeCanvas.ps1` and enter a six-digit management code.
3. Run `Start-WakeCanvas.ps1`.
4. Open `http://localhost:4000/manage` to install the bundled Experience package
   and create an instance.
5. Run `Install-Autostart.ps1` once if WakeCanvas should start at user sign-in.

The launcher waits for Phoenix before opening Edge or Chrome in fullscreen kiosk
mode. It checks reachability every five seconds, restarts the release after three
failed checks, and reopens a closed browser. Task Scheduler also restarts the
launcher if the launcher itself fails. Stopping the launcher gracefully stops the
release; `Uninstall-Autostart.ps1` removes only the scheduled task and never data.

## Persistent data and configuration

All mutable state lives under `data/` beside the release:

```text
data/
├── config/
│   ├── management_code
│   └── secret_key_base
├── instances/
├── packages/
└── wake_canvas.sqlite3
```

The cookie secret is generated at first release start and then reused. Back up the
entire data directory. Replacing application files while retaining `data/`
preserves packages, workshop instances, media, settings, sessions, and identity.

The management code is intentionally simple local-installation configuration, not
a user-account system. `Initialize-WakeCanvas.ps1 -Force -ManagementCode 654321`
changes it; restart the release afterward. `-OpenManagement` explicitly stores an
empty code and leaves management open.

## Local network

The release listens on all IPv4 interfaces by default. Other devices on the same
trusted workshop network use the kiosk address, for example
`http://192.168.1.25:4000`. Windows Firewall may ask for permission on first run;
allow access only on private networks. The kiosk itself always opens through
localhost.

Useful overrides are:

- `WAKECANVAS_DATA_ROOT` — persistent data location;
- `WAKECANVAS_BIND_IP` — bind address, default `0.0.0.0`;
- `PORT` — listening port, default `4000`;
- `WAKECANVAS_MANAGEMENT_CODE` — process-level management-code override;
- `DATABASE_PATH` and `SECRET_KEY_BASE` — explicit hosted/managed overrides;
- `PHX_HOST`, `PHX_SCHEME`, and `PHX_URL_PORT` — externally visible URL.

Do not expose the plain HTTP kiosk profile directly to the public internet. A
hosted deployment must terminate HTTPS at its reverse proxy and set the public URL
overrides.
