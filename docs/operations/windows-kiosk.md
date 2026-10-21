# Windows manual and kiosk release

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

## Build a prepared artist demo

Export the prepared instance from WakeCanvas, then pass that portable archive to
the same release builder:

```powershell
.\scripts\build-windows-release.ps1 `
  -InstanceArchive .\path\living-gallery-demo.wakecanvas-instance `
  -ManagementCode 246810 `
  -ArtifactSuffix artist-demo `
  -Force
```

The resulting ZIP contains the Experience package and the complete instance,
including media and settings. On first start, the instance is imported and made
active. Its UUID makes this idempotent: later starts do not duplicate it or
replace changes made by the artist. Omit `-InstanceArchive` and
`-ManagementCode` to build an unseeded general-purpose release.

## Manual presentation

1. Extract the ZIP into a permanent folder writable by the kiosk user.
2. Double-click `start-wakecanvas.cmd`.
3. Choose a six-digit management code if one was not included by the builder.
4. Use `open-management.cmd` when configuration is needed.
5. Double-click `stop-wakecanvas.cmd` when the presentation is finished.

The stop command also closes the kiosk browser and cleans up only Erlang/EPMD
helper processes associated with that exact extracted WakeCanvas folder. After it
returns, the portable installation folder can be moved or deleted.

The command interface uses the same lowercase kebab-case options as Linux. For
example, if port 4000 is already occupied:

```bat
start-wakecanvas.cmd --port 4100
open-management.cmd --port 4100
```

Manual mode binds to localhost and opens a normal browser. It does not require
administrator access or a Windows installation step.

## Kiosk operation

Double-click `start-kiosk-mode.cmd` for fullscreen, LAN-accessible operation.
An operator can run `admin-tools\install-autostart.cmd` once if WakeCanvas
should start at user sign-in.

The launcher waits for Phoenix before opening Edge or Chrome in fullscreen kiosk
mode. It checks reachability every five seconds, restarts the release after three
failed checks, and reopens a closed browser. Task Scheduler also restarts the
launcher if the launcher itself fails. Stopping the launcher gracefully stops the
release; `admin-tools\uninstall-autostart.cmd` removes only the scheduled task
and never data.

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
a user-account system.
`admin-tools\initialize-wakecanvas.cmd --force --management-code 654321`
changes it; restart the release afterward. `--open-management` explicitly stores an
empty code and leaves management open.

## Local network

Kiosk mode listens on all IPv4 interfaces. Manual mode listens only on localhost.
Other devices on the same trusted workshop network use the kiosk address, for example
`http://192.168.1.25:4000`. Windows Firewall may ask for permission on first run;
allow access only on private networks. The kiosk itself always opens through
localhost.

Local manual and kiosk profiles accept LiveView connections through `localhost`,
`127.0.0.1`, or the kiosk's current private-LAN address. Hosted deployments keep
strict origin validation against `PHX_HOST`.

Useful overrides are:

- `WAKECANVAS_PROFILE` — `manual`, `kiosk`, or `hosted`;
- `WAKECANVAS_BUNDLED_INSTANCES` — directory containing portable seed archives;
- `WAKECANVAS_AUTO_ACTIVATE_SEED` — activate a seed only when nothing is active;

- `WAKECANVAS_DATA_ROOT` — persistent data location;
- `WAKECANVAS_BIND_IP` — bind address, default `0.0.0.0`;
- `PORT` — listening port, default `4000`;
- `WAKECANVAS_MANAGEMENT_CODE` — process-level management-code override;
- `DATABASE_PATH` and `SECRET_KEY_BASE` — explicit hosted/managed overrides;
- `PHX_HOST`, `PHX_SCHEME`, and `PHX_URL_PORT` — externally visible URL.

Do not expose the plain HTTP kiosk profile directly to the public internet. A
hosted deployment must terminate HTTPS at its reverse proxy and set the public URL
overrides.
