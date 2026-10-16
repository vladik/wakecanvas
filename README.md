# WakeCanvas

WakeCanvas is an offline platform for participatory installations where artists
create the experience and communities bring it to life.

The platform runs as one Elixir/Phoenix release on a kiosk computer. Independently
built Experience packages can be installed from local storage or the management
view. An operator creates configured instances from those packages—for example,
separate morning and evening workshops using Living Gallery. An installation may
contain any number of packages and instances, but only one instance is active at a
time.

## Repository layout

- `platform/` — Phoenix, LiveView, SQLite, package management, and kiosk runtime.
- `experiences/sdk/` — the public contract used by independently built Experiences.
- `experiences/living_gallery/` — the first reference Experience.
- `docs/` — product, architecture, development, and decision records.
- `scripts/` — repository-level development and packaging automation.
- `packaging/` — OS-specific release packaging.

These projects deliberately do not form a Mix umbrella. Experiences are standalone
OTP applications that build and ship independently from the platform.

## Current status

The first development verticals are implemented: SQLite-backed Experience packages
and instances, one-active-instance switching, a DaisyUI management screen,
instance-scoped surface dispatch, and a source-linked Living Gallery. Living Gallery
now has isolated per-instance SQLite/media storage, artwork and Workshop Moments
uploads, independent auto-publishing policy, publish/unpublish moderation, recoverable
media removal, PubSub wall refresh, visual display variants, and recoverable instance
archiving. Package archives, permanent purge, management access control, production
kiosk operation, and the final PixiJS renderer remain to be implemented.

## Development

The generated projects require Elixir 1.20 and OTP 29.

```powershell
.\scripts\dev.ps1
```

Then open `http://localhost:4000/manage`. The initial vertical slice includes a
source-linked Living Gallery package, two isolated workshop instances, activation
switching, and an animated display preview.

Run the independent project tests with:

```powershell
.\scripts\test.ps1
```

See [development setup](docs/development/setup.md) and the
[architecture overview](docs/architecture/overview.md) before implementing a new
subsystem.
