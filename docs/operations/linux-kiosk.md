# Linux kiosk releases

WakeCanvas uses the same native release layout on Linux x64 mini PCs and Linux
ARM64 devices such as a 64-bit Raspberry Pi. A release includes ERTS, Phoenix,
database migrations, static assets, kiosk scripts, and an installable Living
Gallery package. The kiosk requires no system Elixir, Erlang, Node.js, SQLite
server, or internet connection.

## Native target builds

Build on the same operating-system architecture that will run the artifact. Mix
releases include the host ERTS and native SQLite library; WakeCanvas does not label
a cross-built archive as target-compatible.

On an x64 or ARM64 Linux build machine:

```sh
sh ./scripts/build-linux-release.sh --force
sh ./scripts/smoke-linux-release.sh \
  --archive ./dist/wakecanvas-0.1.0-linux-x64.tar.gz
```

On ARM64, the builder automatically names the artifact
`wakecanvas-0.1.0-linux-arm64.tar.gz`. The native smoke test extracts a clean
installation, initializes its data directory, runs migrations, verifies database
and cookie-secret creation, stops and restarts the VM, and confirms that its secret
survives the restart.

The build workstation needs the documented Elixir/Erlang, Node.js/npm, and frontend build
toolchain. The resulting kiosk artifact does not.

The Linux builder accepts the same prepared-demo inputs as Windows:

```sh
sh ./scripts/build-linux-release.sh \
  --instance-archive ./living-gallery-demo.wakecanvas-instance \
  --management-code 246810 \
  --artifact-suffix artist-demo \
  --force
```

This uses the shared UUID-idempotent seed bootstrap. It is an option on the same
release pipeline, not a separate release strategy.

## Validation status

The x64 and ARM64 archives have each been built from a clean source copy in a
matching-architecture Linux container and passed `smoke-linux-release.sh`. That
validates the bundled ERTS/native SQLite architecture, release startup, migrations,
database and secret creation, shutdown, restart, and persistent data root.

Container smoke does not validate a real graphical login session, Chromium kiosk
launch, systemd user autostart, GPU drivers, projector behavior, or long-running
thermal stability. Test those on each representative mini PC and Raspberry Pi
model before calling that hardware production-ready.

## Install and run

```sh
tar -xzf wakecanvas-0.1.0-linux-x64.tar.gz
cd WakeCanvas
./start-wakecanvas.sh
```

On first start the launcher creates the data directory and asks for a six-digit
management code. Open `http://localhost:4000/manage`. The bundled package is installed on first
start; an unseeded release then lets the operator create an instance. The launcher prints management URLs
for the kiosk's IPv4 LAN addresses so operator and intake devices can connect.

The endpoint listens on all IPv4 interfaces while the projected display uses
localhost. Permit TCP port 4000 only on the trusted workshop network. Use
`./start-wakecanvas.sh --port 4100` to select another port, or `--no-browser` for a
headless/operator-only machine.

Local manual and kiosk profiles accept LiveView connections through `localhost`,
`127.0.0.1`, or the kiosk's current private-LAN address. Hosted deployments keep
strict origin validation against `PHX_HOST`.

For the fullscreen public display, use `./start-kiosk-mode.sh`. To stop a manually
started installation, use `./stop-wakecanvas.sh`. That command also stops this
installation's launcher, user-level kiosk service, and dedicated kiosk browser.
After it finishes, the installation directory can be moved or deleted safely.
The service remains enabled and will start again at the next login or reboot unless
it is disabled or uninstalled. The release root intentionally
contains only these safe day-to-day commands plus `./open-management.sh`.

## Fullscreen browser and autostart

Install Chromium or Google Chrome using the operating system. WakeCanvas discovers
common executable names and starts the browser with an isolated profile, fullscreen
kiosk mode, autoplay support, and crash-bubble suppression.

Run this as the graphical kiosk user:

```sh
./admin-tools/install-autostart.sh
```

It creates one user-level systemd service. The service starts the Phoenix release
and browser together, restarts after failure, and sends a graceful termination
signal to both. Configure the Linux desktop to log this kiosk user in automatically;
the installer deliberately does not modify distribution-specific login-manager
configuration or require root access.

Inspect or stop it with:

```sh
systemctl --user status wakecanvas-kiosk.service
systemctl --user stop wakecanvas-kiosk.service
```

`./admin-tools/uninstall-autostart.sh` removes the service but never deletes
installation data. Initialization, service setup, and the advanced launcher are
kept under `admin-tools/` so normal users do not run operational scripts by
mistake.

## Storage and configuration

Mutable data is stored under `data/` beside the release, using the same layout and
environment overrides as the Windows release. Back up that complete directory.
The generated cookie secret persists across upgrades and reboots. The management
code remains simple installation configuration and can be changed with:

```sh
./admin-tools/initialize-wakecanvas.sh --force --management-code 654321
```

Restart WakeCanvas after changing it. Use `--open-management` only when intentionally
running without management protection.

Hosted deployments are a separate profile: do not expose the kiosk's plain HTTP
listener directly to the public internet.
