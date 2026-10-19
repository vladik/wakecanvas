# WakeCanvas

WakeCanvas is an offline platform for participatory installations where artists
create the experience and communities bring it to life.

It runs as one Elixir/Phoenix release on a kiosk computer. Independently built
Experience packages are reusable software; operators create isolated workshop
instances from them and run zero or one instance at a time.

## Repository layout

- `platform/` - Phoenix, LiveView, SQLite, package management, and kiosk runtime.
- `experiences/sdk/` - the public contract used by independent Experiences.
- `experiences/living_gallery/` - the first reference Experience.
- `packages/media/` - optional browser image processing shared at build time.
- `docs/` - product, architecture, development, and decision records.
- `scripts/` - repository-level development automation.
- `packaging/` - OS-specific release packaging.

These projects deliberately do not form a Mix umbrella. Experiences are standalone
OTP applications that build and ship independently from the platform.

## Current status

The working vertical has UUID instances and aliases, isolated SQLite/media storage,
WAL plus bounded busy handling, global management and per-instance participant
codes, supervised active-instance switching, archive/restore, and strongly
confirmed permanent purge. Archived workshops can be exported as validated,
checksummed `.wakecanvas-instance` files and imported on a compatible kiosk while
preserving their UUID, or explicitly cloned/replaced when that UUID already exists.
Management also reports kiosk health for the platform database, writable data
directory, disk capacity, package catalog, active OTP runtime, and bounded instance
storage. Display clients report bounded renderer heartbeats, variant fallback,
viewport, FPS, and WebGL failures. A privacy-limited `/health` JSON endpoint is
available for supervision.

Living Gallery provides artwork, Workshop Moments, and testimonial intake,
independent publishing policies, moderation, live PubSub updates, and five lazy-loaded display variants
using PixiJS, Three.js, p5.js, and HTML/SVG. Artwork intake can resize and remove a
controlled background in a browser worker before upload. Growing Canvas can react
to microphone level after an explicit local permission gesture.

The SDK now creates deterministic `.wakecanvas` archives. Management can upload,
validate, checksum, compatibility-check, and stage an external package in a
content-addressed cache for activation on restart. One-version package rollback and
reference-safe confirmed uninstall are also available. The SDK can generate a
standalone external Experience project. A self-contained Windows x64 ZIP now has
first-run initialization, a durable adjacent data root, generated cookie secret,
fullscreen browser launch, current-user autostart, process recovery, and a
cold-start/restart smoke test. Linux x64 and ARM64 now have native build, smoke,
systemd, and Chromium kiosk workflows. Both Linux release archives build from a
clean source copy and pass their packaged runtime smoke tests in matching-architecture
Linux containers. The same release now has a smoke-testable Docker image and a
single-machine Fly.io profile with persistent storage. Physical-hardware kiosk,
autostart, power-loss, and long-duration soak testing remain release-candidate work.

## Development

The generated projects require Elixir 1.20 and OTP 29.

```powershell
.\scripts\dev.ps1
```

Then open `http://localhost:4000/manage`. Run all independent project tests with:

```powershell
.\scripts\test.ps1
```

See the [development setup](docs/development/setup.md),
[architecture overview](docs/architecture/overview.md), and phased
[implementation plan](docs/development/implementation-plan.md).

Develop a standalone Experience against the real host without packaging it first:

```powershell
.\scripts\dev-experience.ps1 -ExperiencePath C:\Repos\my-experience
```

Build and validate the Windows kiosk ZIP with:

```powershell
.\scripts\build-windows-release.ps1 -Force
.\scripts\smoke-windows-release.ps1 `
  -Archive .\dist\wakecanvas-0.1.0-windows-x64.zip
```

See the [Windows kiosk guide](docs/operations/windows-kiosk.md) for installation,
autostart, storage, LAN, and runtime configuration details.

Linux x64 and ARM64 builders use the same application and package:

```sh
sh ./scripts/build-linux-release.sh --force
```

See the [Linux kiosk guide](docs/operations/linux-kiosk.md) for release validation,
systemd user autostart, Chromium, and Raspberry Pi considerations.

Build the optional hosted profile with:

```sh
docker build -t wakecanvas:local .
```

See the [hosted deployment guide](docs/operations/hosted.md) for Docker Compose,
Fly.io, persistent-volume, HTTPS, health-check, and backup guidance.
