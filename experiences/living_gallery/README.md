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
and its own JavaScript renderers. PixiJS, Three.js, GSAP, p5.js, and Matter.js are bundled
here and are not platform dependencies. The Three.js `gallery-orbit` entry point
is presented as **Living Spiral**: workshop photographs form its outer memory
helix while artwork travels on a brighter inner orbit and periodically enters an
automatic, hands-free hero sequence.

The PixiJS `living-collage` entry point is presented as **Living Film Collage**.
Workshop moments continuously develop and travel through layered film ribbons,
while background-removed artwork floats freely above them. Every ten seconds one
artwork moves into a large central focus with optional attribution. GSAP
choreographs focus changes, new arrivals, and periodic whole-collage recomposition;
the wall requires no pointer or scroll input.

Both WebGL renderers reconcile live snapshots incrementally. Publishing or removing
one item does not rebuild the scene, reset the camera, restart the film ribbons, or
restart the feature sequence. Presentation clocks pause while their browser tab is
hidden and resume without replaying accumulated transitions.

The p5.js **Growing Canvas** turns every artwork into a plant and luminous blossom,
with workshop moments forming atmospheric memory layers and optional microphone
level acting as wind. The HTML/SVG **Community Tapestry** stitches artwork,
photographs, and testimonials into one connected wall and is the low-power fallback.
The DOM/CSS **Living Light** renderer uses prismatic echoes, moving light, aperture
reveals, and slow memory dissolves to create a cinematic museum-style presentation.
The PixiJS/Matter.js **Living Balance** creates an endless one-at-a-time artwork
rain over suspended workshop-memory platforms, rotates the memories shown on those
platforms, and spotlights each creation in turn. Optional sound gently disturbs the
shared balance.

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
