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

- `RendererDisplayLive` hosts any declared browser renderer and receives bounded
  snapshots from the server.
- `ArtworkIntakeLive` prepares images in a browser Web Worker, offers controlled
  background removal and preview, and uploads artwork or created objects. A creator name or title is
  optional and displayed only with explicit `show_attribution` consent.
- `MomentsUploadLive` lets a designated workshop photographer upload live workshop
  photographs periodically from a phone or tablet.
- `ReviewLive` edits titles and creator attribution, publishes, unpublishes, and
  soft-deletes both content types. Removed images remain recoverable.
- `SettingsLive` manages per-instance publishing policy, presentation label,
  public name and description, and the active visual variant. These wall-facing
  fields are independent of the platform's internal instance name.

For instance UUID `550e8400-e29b-41d4-a716-446655440000`, these surfaces are
mounted below `/i/550e8400-e29b-41d4-a716-446655440000/`, for example `display`,
`artwork`, `moments`, `review`, and `settings`.

The platform supplies the endpoint and stable routes; these modules supply the
Experience-specific UI behind them.

## Display variants

Living Gallery declares seven presentations over the same content: PixiJS/GSAP
`living-collage` (presented as **Living Film Collage**), DOM/CSS `quiet-spotlight`
(presented as **Living Light**),
Three.js/GSAP `gallery-orbit` (presented as **Living Spiral**), its frameless
`gallery-orbit-focus` companion (presented as **Living Spiral — Focus**), p5.js
`growing-canvas`, HTML/SVG `community-tapestry`, and PixiJS/Matter.js
`gravity-playground`. The Settings surface shows
every declared variant and stores one as the instance default. `/i/:uuid/display`
uses that default after restart, while `/i/:uuid/display/:variant_id` previews any
variant without changing saved configuration. Renderers declare capability needs;
GPU variants fall back to Community Tapestry when WebGL support is unavailable.

Display variants share storage, moderation, and PubSub state. They differ only in
their Experience-owned rendering code.

## Publishing policy

Each instance independently configures automatic publishing for artwork and
Workshop Moments. The defaults match the common workshop flow: participant artwork
publishes immediately, while Workshop Moments wait for operator review. An operator
can publish or unpublish any retained image regardless of the upload policy.

Publishing controls wall visibility. Soft deletion is separate: it hides the image
and moves it into a recoverable removed-items area without deleting its row or file.
From that area, a separate confirmation modal can permanently purge the database
record, prepared display file, and retained original.

## Storage

The instance database records media metadata, content role (`artwork` or
`workshop_moment`), moderation state, optional title and creator name,
`show_attribution` consent, display order, timestamps, and the optional original
filename/type. Prepared display files live in `media/`; retained camera originals
live separately in private `originals/` storage and are not exposed by the public
media route. Workshops therefore cannot mix content, and an operator can disable
original retention per instance for privacy or constrained storage.

Images are resized to a bounded dimension once on the intake device. Artwork may
also use edge-connected chroma removal with tolerance, mask dilation, feathering,
and despill before upload. The display renderer uses bounded dimensions and bounded
item sets rather than repeatedly decoding original camera files.

## Visual direction

The default Living Film Collage renderer sends framed workshop moments through
independently moving film ribbons while colourful, background-removed artwork
floats freely in the foreground. New moments visually develop into their frames;
new artwork expands into the shared composition; and slow periodic recomposition
keeps a long-running wall from becoming static. A ten-second feature cycle moves
each artwork into a large central focus with optional attribution. Living Spiral uses a broad, muted
helix for framed workshop memories and a brighter inner orbit for transparent artwork.
GSAP automatically brings one artwork into a central hero position while Three.js
continues the camera journey, depth treatment, atmosphere, and live scene updates;
no mouse or scroll input is required. Living Spiral — Focus retains the same
hands-free journey while removing renderer-added frames and translucent backing,
enlarging featured artwork to fill roughly 80–90% of the available stage, and
showing title followed by optional creator attribution. Its editable presentation
label and description are stored in the instance configuration. Growing Canvas turns artwork into luminous
plants, uses workshop memories as atmospheric layers, and can treat microphone
level as wind. Community Tapestry connects artwork, memories, and messages with
animated SVG thread while remaining a low-power accessible fallback. Gravity
Playground lets artwork fall, collide, and settle on workshop-memory platforms;
sound can gently disturb the shared composition.

Living Film Collage and Living Spiral preserve renderer state across PubSub
snapshots. They reconcile additions, removals, and metadata changes into existing
scene objects instead of clearing and rebuilding the scene. Their local animation
clocks are bounded and feature timers pause in hidden browser tabs, preventing a
background display from replaying accumulated transitions when it becomes visible.

Filters and masks are deliberately limited for Raspberry Pi and mini-PC performance.
The initial visual recipe uses colour adjustment for the ambient layer, one shared
shadow treatment for artwork, and temporary blur only during a featured transition.

## Failure behavior

An invalid image is rejected without interrupting the display. A disconnected intake
device can retry safely. A display reconnect receives a complete current snapshot
before incremental PubSub events. Disk and retained-media limits must be configurable
before unattended deployment.
