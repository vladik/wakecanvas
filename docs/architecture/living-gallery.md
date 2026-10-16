# Living Gallery reference Experience

Living Gallery is the first production Experience planned for WakeCanvas. Each
configured Living Gallery instance represents one art workshop with one projected
wall and one or more local-network intake or operator devices. Morning and evening
workshops can be separate instances of the same installed package.

## Experience

The wall combines two visually distinct content roles:

- **Workshop moments** form a quiet, slowly moving ambient collage.
- **Participant artwork** appears larger in a foreground gallery and receives a
  temporary featured introduction when submitted.

These are two content types inside one Experience, not two active Experiences.

```text
operator uploads workshop photographs ──┐
                                         ├── Living Gallery SQLite/media store
intake station photographs artwork ─────┘                 │
                                                          │ PubSub
                                                          ▼
                                                projected PixiJS wall
```

## Surfaces

- `DisplayLive` hosts a full-screen PixiJS renderer and receives bounded update
  events from the server.
- `ArtworkIntakeLive` uses the browser camera and Canvas APIs to capture, crop,
  rotate, preview, and upload artwork or created objects. A creator name or title is
  optional and displayed only with explicit `show_attribution` consent.
- `MomentsUploadLive` lets a designated workshop photographer upload live workshop
  photographs periodically from a phone or tablet.
- `ReviewLive` publishes, unpublishes, and soft-deletes both content types. Removed
  images remain recoverable.
- `SettingsLive` manages per-instance publishing policy and later visual options.

For instance `12`, these surfaces are mounted at `/i/12/display`,
`/i/12/artwork`, `/i/12/moments`, `/i/12/review`, and `/i/12/settings`.

The platform supplies the endpoint and stable routes; these modules supply the
Experience-specific UI behind them.

## Display variants

Living Gallery declares `living-collage` and `quiet-spotlight` as two presentations
of the same instance content. The Settings surface shows visual cards for every
declared variant and stores one as the instance default. `/i/:id/display` uses that
default after restart, while `?variant=quiet-spotlight` provides a validated preview
or an alternate simultaneous display without changing saved configuration.

Display variants share storage, moderation, and PubSub state. They differ only in
their Experience-owned rendering code.

## Publishing policy

Each instance independently configures automatic publishing for artwork and
Workshop Moments. The defaults match the common workshop flow: participant artwork
publishes immediately, while Workshop Moments wait for operator review. An operator
can publish or unpublish any retained image regardless of the upload policy.

Publishing controls wall visibility. Soft deletion is separate: it hides the image
and moves it into a recoverable removed-items area without deleting its row or file.

## Storage

The instance database records media metadata, content role (`artwork` or
`workshop_moment`), moderation state, optional title and creator name,
`show_attribution` consent, display order, and timestamps. Original and
display-sized media files live in that instance's private data directory, so
workshops cannot mix content.

Images are normalized once at intake. The display renderer uses bounded dimensions
and a bounded texture set rather than repeatedly decoding original camera files.

## Visual direction

The initial renderer uses PixiJS with three layers: a neutral background, an ambient
workshop collage, and a foreground artwork gallery. A newly approved artwork dims
the collage, enters centrally, remains featured, then moves into the gallery.

Filters and masks are deliberately limited for Raspberry Pi and mini-PC performance.
The initial visual recipe uses colour adjustment for the ambient layer, one shared
shadow treatment for artwork, and temporary blur only during a featured transition.

## Failure behavior

An invalid image is rejected without interrupting the display. A disconnected intake
device can retry safely. A display reconnect receives a complete current snapshot
before incremental PubSub events. Disk and retained-media limits must be configurable
before unattended deployment.
