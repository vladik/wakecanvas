# Living Gallery

Living Gallery is the first WakeCanvas reference Experience. It supports a workshop
where general event photographs form an ambient projected collage and photographs
of participant artwork appear in a distinct featured gallery.

Planned surfaces:

- a full-screen PixiJS display;
- an artwork/object camera intake station with optional attribution;
- a Workshop Moments uploader for real-time workshop photography;
- operator review and settings views;
- Experience-owned SQLite metadata and local media storage; and
- PubSub-driven updates from intake to display.

## Independent frontend build

Living Gallery compiles and packages its own Tailwind 4 and DaisyUI 5 stylesheet
and its own JavaScript renderer. A future PixiJS dependency will be bundled here,
not added to the WakeCanvas platform.

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

The temporary embedded prototype CSS will move into the packaged Experience
stylesheet when platform asset serving is implemented. The final PixiJS renderer,
settings UI, image normalization, and `.wakecanvas` package build task remain to be
implemented.
