# Development setup

## Requirements

- Elixir 1.20
- Erlang/OTP 29
- Git
- A modern Chromium browser

Native helper toolchains are Experience-specific and are not platform prerequisites.

## Platform

For the current source-linked vertical slice, run from the repository root:

```powershell
.\scripts\dev.ps1
```

This compiles Living Gallery independently, migrates and seeds the platform SQLite
database, and starts WakeCanvas at `http://localhost:4000`. Open `/manage` for the
control room or `/display` for the active instance.

From an instance card, open **Artwork intake** or **Moments**, upload an image, then
open **Review** and approve it. The connected display refreshes through PubSub and
shows the approved image. Development media is stored below `platform/data/`.

The individual platform commands remain:

```powershell
cd platform
mix setup
mix phx.server
```

The generated platform uses SQLite. Development and test databases remain inside
the platform project until the runtime data-directory abstraction is implemented.

## Independent projects

```powershell
cd experiences\sdk
mix test

cd ..\living_gallery
mix test
```

Use `scripts/test.ps1` or `scripts/test.sh` to check every project.

## Intended Experience development loop

During development, WakeCanvas will support linking one Experience source checkout
into a development host for LiveView and asset iteration. Production-like testing
must always install the compiled `.wakecanvas` artifact into a clean temporary data
directory and restart the host.
