# Hosted Docker and Fly.io deployment

Hosted WakeCanvas uses the same Phoenix release and Experience package format as
the offline kiosk. It is an optional single-machine profile, not a separate cloud
architecture. Keep exactly one application instance attached to one persistent
volume; SQLite does not support multiple machines writing the same volume.

## Local Docker smoke run

Build the image from the repository root:

```sh
docker build -t wakecanvas:local .
docker volume create wakecanvas-data
docker run --rm --name wakecanvas \
  -p 4000:4000 \
  -e WAKECANVAS_PROFILE=hosted \
  -e PHX_HOST=localhost \
  -e WAKECANVAS_MANAGEMENT_CODE=123456 \
  -v wakecanvas-data:/data \
  wakecanvas:local
```

Open `http://localhost:4000/manage`. The release automatically validates and
installs its bundled Living Gallery package on first start. All mutable state is
below `/data`; replacing the image does not replace the database or instance
media. `compose.yaml` provides the same setup and requires
`WAKECANVAS_MANAGEMENT_CODE` in the shell or `.env` file.

The production image contains the release and browser assets, but no Node.js,
npm, Mix, or source tree. `/health` is used by the image health check.

A hosted demo can use the same portable seed bootstrap as the Windows ZIP. Copy
or mount one or more `.wakecanvas-instance` files into `/app/seeds` and set
`WAKECANVAS_AUTO_ACTIVATE_SEED=true`. Existing UUIDs and an already-active
instance are always preserved. The seed is application input; mutable data still
belongs on `/data`.

## Fly.io

1. Copy `fly.toml.example` to `fly.toml`, choose a unique app name, and update
   `PHX_HOST` to `<app-name>.fly.dev`.
2. Create the app and volume in the selected region:

   ```sh
   fly apps create <app-name>
   fly volumes create wakecanvas_data --region yyz --size 3
   fly secrets set WAKECANVAS_MANAGEMENT_CODE=123456
   fly deploy
   ```

Fly terminates HTTPS and forwards HTTP to port 4000. The template sets the public
URL scheme and port accordingly, keeps one Machine running, mounts `/data`, and
checks `/health`. Do not scale it above one Machine while using SQLite.

## Backup and restore

Use WakeCanvas instance export for portable workshop backups. Also snapshot or
copy the whole persistent volume before platform upgrades; it contains the
platform database, package cache, instance databases, original and processed
media, and the generated cookie-signing secret. Restore the volume to a single
stopped Machine before restarting it.

Hosted microphone/camera access requires HTTPS, which Fly provides. Participant
and management codes are convenience access control for short workshops, not an
account system; choose non-obvious codes and rotate them between public events.
