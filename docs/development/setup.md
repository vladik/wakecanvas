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

Set the optional installation-wide six-digit management code before starting if
you want management and operator pages protected during development:

```powershell
$env:WAKECANVAS_MANAGEMENT_CODE = "123456"
.\scripts\dev.ps1
```

With no management code configured, those pages are intentionally open for local
development. Each instance's optional participant code is configured in `/manage`.

From an instance card, open **Artwork intake** or **Moments**, upload an image, then
open **Review** and approve it. The connected display refreshes through PubSub and
shows the approved image. Development media is stored below `platform/data/`.

The individual platform commands remain:

```powershell
cd platform
mix setup
mix phx.server
```

The generated platform uses SQLite. Instance databases and media are stored below
the configured data root under `instances/<uuid>/`.

## Independent projects

```powershell
cd experiences\sdk
mix test

cd ..\living_gallery
mix test
```

Use `scripts/test.ps1` or `scripts/test.sh` to check every project.

## Intended Experience development loop

Link one separately checked-out Experience directly into the development host:

```powershell
.\scripts\dev-experience.ps1 `
  -ExperiencePath C:\Repos\sound-garden `
  -App sound_garden `
  -EntryModule ArtistStudio.SoundGarden
```

The script compiles the external OTP application, registers its `ebin` path for
development, and starts the normal WakeCanvas host. Its compiled definition is
added to the local package catalog automatically, so the operator can create and
run instances without repeatedly packaging and uploading the Experience. Rebuild
the Experience's browser assets in its own project; files copied into its `priv/`
directory are served directly by the development host.

This source link is deliberately limited to development. Before sharing or
releasing an Experience, build its deterministic `.wakecanvas` archive and run the
platform smoke verifier in a clean target environment:

```powershell
cd C:\Repos\wakecanvas\platform
mix wakecanvas.package.verify C:\path\to\sound_garden-0.1.0.wakecanvas
```

Production-like testing must install that compiled artifact into a clean temporary
data directory and restart the host.
