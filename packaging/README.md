# Packaging

This directory will contain operating-system packaging around the compiled
WakeCanvas release. The release artifact must bundle ERTS and require no system
Elixir, Erlang, Node.js, or external database installation.

Target matrix:

- Windows x64 — self-contained ZIP built and smoke-tested on Windows
- Linux x64 — self-contained archive built and runtime-smoke-tested on Linux x64
- Linux ARM64, including supported Raspberry Pi systems — self-contained archive
  built and runtime-smoke-tested on Linux ARM64 under emulation

Release jobs must smoke-test startup, SQLite migration, management readiness,
Experience discovery, clean shutdown, restart, and preservation of the configured
data directory. Target support is not considered implemented until that packaged
artifact passes its own runner smoke test.

All three target artifacts satisfy that release-level gate. Linux graphical kiosk,
systemd user-session, and long-running behavior still need representative physical
mini-PC and Raspberry Pi validation.

The GitHub Actions `releases` matrix runs on manual dispatch and `v*` version tags.
It builds each archive on its matching native architecture, runs the corresponding
smoke test, and uploads only the resulting smoke-tested artifact.

## Windows x64

Build on a Windows x64 machine so the bundled ERTS and native SQLite library match
the target:

```powershell
.\scripts\build-windows-release.ps1 -Force
.\scripts\smoke-windows-release.ps1 -Archive .\dist\wakecanvas-0.1.0-windows-x64.zip
```

The ZIP is a portable installation. Its root contains initialization, launcher,
and current-user autostart scripts. Runtime data is deliberately stored in the
adjacent `data/` directory and is not part of a newly built archive. The bundled
Living Gallery `.wakecanvas` file is an optional installable package; it is not
silently installed or given instances by the release.

The launcher binds the Phoenix endpoint to all IPv4 interfaces so devices on the
workshop LAN can connect, while it opens the display through localhost. Windows
Task Scheduler restarts the launcher after a process failure, and the launcher
monitors both the endpoint and fullscreen browser.

## Linux x64 and ARM64

Build and test on the target architecture:

```sh
sh ./scripts/build-linux-release.sh --force
sh ./scripts/smoke-linux-release.sh --archive ./dist/wakecanvas-0.1.0-linux-x64.tar.gz
```

The build script maps `x86_64` to `linux-x64` and `aarch64` to `linux-arm64` and
refuses other hosts. It does not pretend that an ERTS/native-library bundle built
on one architecture is portable to another. Extracted releases use a single
systemd user service for the Phoenix VM, health supervision, and graphical browser.
See the [Linux kiosk guide](../docs/operations/linux-kiosk.md).
