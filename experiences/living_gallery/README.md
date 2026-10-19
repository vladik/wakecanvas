# Living Gallery

Living Gallery is the first WakeCanvas reference Experience. It supports a workshop
where general event photographs form an ambient projected collage and photographs
of participant artwork appear in a distinct featured gallery.

Implemented surfaces:

- a full-screen display with independently loaded PixiJS, Three.js, p5.js, and
  HTML/SVG variants;
- an artwork/object camera intake station with optional attribution;
- a Workshop Moments uploader for real-time workshop photography;
- operator review and settings views;
- Experience-owned SQLite metadata and local media storage; and
- PubSub-driven updates from intake to display.

## Independent frontend build

Living Gallery compiles and packages its own Tailwind 4 and DaisyUI 5 stylesheet
and its own JavaScript renderers. PixiJS, Three.js, and p5.js are bundled here and
are not platform dependencies.

```powershell
mix setup
mix assets.build
mix assets.deploy
```

Compiled package assets are written to `priv/static/`. These commands run on a
developer or CI machine; the installed kiosk only serves the resulting files.

The current vertical includes independently compiled display, artwork intake,
Workshop Moments upload, and review LiveViews. Each platform instance receives a
separate Experience SQLite database and media directory. Approving a submission
broadcasts through PubSub and refreshes connected walls.

The renderer contract and platform asset serving are implemented. Every variant is
a separate ESM entry point under `priv/static/variants`, so a wall downloads only
the selected renderer and its chunks. Capability declarations can select an
HTML/SVG fallback. Browser-side image normalization, optional retained originals,
moderation and permanent media purge, and the installable `.wakecanvas` build and
validation workflow are also implemented.
