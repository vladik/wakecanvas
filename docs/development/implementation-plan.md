# WakeCanvas implementation plan

Status: active implementation roadmap  
Last updated: 2026-10-19

Implemented in the current vertical:

- Phase 1 UUID identity, slug aliases, canonical variant routes, WAL, ten-second
  busy timeout, bounded retry/serialization, upload limits, and ten-writer test;
- Phase 2 management/participant codes, scoped signed sessions, attempt limiting,
  archive/restore, and name-confirmed staged permanent instance purge;
- Phase 3 supervised active-instance start/stop, startup restoration, and rollback;
- Phase 5 ESM renderer lifecycle, separate lazy-loaded entries, capability fallback,
  saved selection, and explicit simultaneous preview URLs;
- the initial Phase 6 `@wakecanvas/media` package and artwork intake integration;
- Phase 7 original-file retention policy, legacy instance-schema migration, and
  confirmed permanent media purge;
- Phase 8 working PixiJS, Three.js, microphone-reactive p5.js, DOM, and HTML/SVG
  demonstrations over the same Living Gallery snapshots and PubSub updates; and
- the Phase 4 package lifecycle foundation: deterministic SDK archive creation, bounded
  path/checksum/compatibility/module validation, content-addressed staging,
  management upload, pending-restart catalog state, restart discovery, one-version
  rollback, reference-blocked confirmed uninstall, cache cleanup, and a generated
  standalone Experience starter validated outside the repository projects.

Repository-level roadmap work is complete: media golden fixtures, local QR
presentation, the optional sound-input proof, and Docker/Fly.io deployment are
implemented. Windows x64 has a self-contained, smoke-tested ZIP. Linux x64 and ARM64
have self-contained archives that pass their runtime smoke tests in
matching-architecture Linux containers; graphical kiosk and systemd behavior still
await representative physical machines. Power-loss, full-disk, and long-duration
soak tests also require target hardware. A manually dispatched or version-tagged CI
matrix builds, smoke-tests, and uploads all three release targets.

This plan turns the accepted WakeCanvas architecture into independently testable
vertical slices. It builds on the existing Living Gallery vertical rather than
replacing it. Each phase must leave the kiosk runnable and must satisfy its exit
criteria before work that depends on it begins.

## Product outcome

WakeCanvas is one offline-first Phoenix release that can discover independently
built Experience packages, create multiple isolated instances, and run zero or one
instance at a time. An operator can install, configure, preview, activate, archive,
export, and remove Experiences without editing configuration files. The active
instance and its selected visual variant recover automatically after a reboot.

The same release can run locally on a kiosk or, as an optional deployment profile,
inside one Docker/Fly.io machine with persistent storage. Cloud services are never
required for local operation.

## Accepted decisions

- The platform is an Elixir/Phoenix/LiveView modular monolith.
- Every Experience is an independently buildable, trusted OTP application using
  only the versioned Experience SDK contract.
- Experience packages ship compiled BEAM code and browser-ready assets. Node.js is
  a build-time tool only and is not installed on production kiosks.
- Every Experience compiles and ships its own JavaScript and CSS bundle, including
  Tailwind, DaisyUI, PixiJS, Three.js, p5.js, or other dependencies it chooses.
- The platform owns the endpoint and stable `/i/:instance_id/...` route prefix.
  Experiences declare surfaces below that prefix.
- An instance UUID is its sole durable database identity. Existing integer instance
  IDs will be replaced while the project is still in development.
- Instance storage is derived as `data/instances/<uuid>/`; absolute machine paths
  are not persisted in the database.
- A human-friendly, installation-local unique slug may be stored as a mutable URL
  alias, but it is not identity. Canonical routes, internal references, exports,
  and storage use the UUID, so renaming a slug cannot invalidate the stable URL.
- The platform has one SQLite database. Every Experience instance has a separate
  Experience-owned SQLite database and media directory.
- SQLite uses WAL, a busy timeout, short transactions, and bounded/retried writes so
  upload bursts wait normally instead of exposing lock errors to visitors.
- The kiosk has many installed packages and configured instances, but zero or one
  active instance. Activation starts a supervised instance runtime; deactivation
  stops it and releases hardware and background work.
- Normal removal is reversible archive/soft deletion. Explicit permanent purge is
  a separate, strongly confirmed, restart-safe operation.
- Package uninstall is blocked while instances reference the package unless the
  operator separately confirms a cascading purge.
- Security uses two code classes: one global management code and one optional
  per-instance participant code. Empty participant code means open access. Codes
  create signed, scoped sessions; no user-account system is required.
- An Experience may declare multiple display variants over the same content. One
  variant is selected for automatic display, while explicit variant URLs allow
  simultaneous previews without changing the saved selection.
- Shared image processing is an optional browser-side TypeScript package compiled
  into each consuming Experience. Processing happens in a Web Worker and uploads
  through LiveView; no Node.js runtime or required server image service is added.
- Rust/WASM, native Ports, OpenCV, and AI background removal remain optional future
  backends justified by profiling or real image failures, not initial dependencies.

## Current baseline

The repository already demonstrates:

- source-linked Experience registration;
- package and instance records;
- multiple Living Gallery instances with isolated SQLite and media;
- supervised one-active-instance switching;
- stable platform-owned Experience surface dispatch;
- artwork and Workshop Moments upload flows;
- independent auto-publish settings;
- publish, unpublish, soft-delete, and restore behavior;
- recoverable instance archive and restore;
- five declared display variants with selection, preview, and capability fallback;
- PubSub refresh of the wall.

The following phases harden that vertical into the intended product.

## Phase 1: durable instance identity and local storage reliability

Replace development-era integer instance identity before more contracts depend on
it, then make local writes safe under realistic workshop concurrency.

### Work

- Change the platform instance schema and primary key to Ecto `:binary_id` UUIDs.
- Update foreign references, route parsing, LiveView events, seeds, fixtures, tests,
  and instance-path derivation.
- Recreate development data rather than maintaining unnecessary integer-ID
  compatibility. Document a one-time migration only if retained test data matters.
- Keep UUIDs unchanged during export/import. Define collision handling as explicit
  `skip`, `replace`, or `clone with new UUID`; never silently merge instances.
- Add an optional installation-local unique slug that resolves as a convenient URL
  alias. UUID routes remain canonical and continue working after a slug rename.
- Configure WAL and a non-zero busy timeout for the platform repository and every
  instance repository.
- Keep database transactions short. Add bounded retry/backoff for transient busy
  errors at the storage boundary.
- Add upload and decoded-image size limits before allocating or writing media.
- Update ADR-0003, ADR-0004, architecture documents, and examples that still state
  that instance identity is an integer.

### Exit criteria

- Every newly created instance has one UUID identity and a matching data directory.
- Renaming an instance does not move its data or break its canonical URL.
- Two instances of the same Experience cannot read or write each other's database
  or media.
- A test burst of at least ten concurrent media submissions completes or returns a
  controlled retryable error; visitors never see an unhandled SQLite busy error.
- Restarting during a write leaves both platform and instance databases valid.

## Phase 2: access control and operator-safe destructive actions

Protect management and workshop intake without introducing accounts or an external
identity service.

### Work

- Add a configurable six-digit global management code.
- Protect management, review, settings, package, diagnostics, and destructive
  routes with a friendly LiveView code screen and signed session.
- Add an optional six-digit participant code to each instance. Scope its signed
  session to that instance and support empty-code open access.
- Store code verifiers rather than plaintext where practical. Support code rotation
  and session invalidation.
- Add bounded attempt throttling suitable for a local network.
- Replace remaining browser confirmation dialogs with DaisyUI/LiveView modals.
- Implement permanent instance purge as a separately named, archived-only,
  restart-safe operation with typed/name confirmation.
- Block package uninstall while any live or archived instance references it.

### Exit criteria

- An unauthenticated visitor cannot reach management or review functions.
- A participant session for instance A does not authorize instance B.
- An open instance requires no code.
- Cancelling any archive, purge, or uninstall modal makes no state change.
- Interrupted purge resumes or reports a visible retryable failure without exposing
  a partially deleted instance as usable.

## Phase 3: real active-instance OTP lifecycle

Turn activation from a database flag into a supervised runtime transition.

### Work

- Add a platform-owned active-instance manager and dynamic supervisor.
- Define SDK callbacks/context for instance start, readiness, stop, health, and
  assigned database/data paths.
- Start only the selected instance runtime; stop it before activating another.
- Release cameras, microphones, Ports, timers, subscriptions, and workers on stop.
- Commit active selection only after readiness, with rollback to the previous
  instance or management-only safe mode after failure.
- Restore the selected instance after application or machine restart.
- Expose runtime state and safe diagnostics in management UI.

### Exit criteria

- Switching instances demonstrably stops the old supervised runtime before the new
  one becomes active.
- A failing Experience cannot prevent the management UI from starting.
- Restart restores the previously selected instance and display variant.
- Runtime crashes are supervised, visible, and bounded rather than causing an
  uncontrolled restart loop.

## Phase 4: installable Experience package contract

Replace source-link assumptions with deterministic packages that can be produced in
separate repositories and installed by an operator.

### Work

- Finalize the `.wakecanvas` manifest, checksum file, compatibility fields, target
  triple, declared surfaces, variants, capabilities, migrations, and asset entries.
- Implement deterministic package creation in the SDK/template.
- Stage and validate local file/UI uploads before installation: normalized paths,
  size limits, checksums, target compatibility, SDK version, module collisions,
  and expected files.
- Extract verified packages into an immutable content-addressed cache.
- Activate new or upgraded package code only after a controlled restart.
- Preserve the previous package for smoke-tested rollback; distinguish package
  rollback from instance-data rollback.
- Implement the management catalog for install, pending restart, rejected package,
  version, upgrade, rollback, and uninstall status.
- Create a standalone Experience starter and authoring walkthrough.

### Exit criteria

- An Experience built outside the platform repository can be packaged, installed
  from the management UI, discovered after restart, instantiated, and run.
- A malformed, incompatible, path-traversing, or checksum-invalid package is
  rejected before code is loaded.
- A broken package leaves management and other packages available.
- Production installation requires no Node.js or frontend compilation.

## Phase 5: finalize the display-variant contract

Make variants renderer-independent and safe to preview or switch for unattended
operation.

### Work

- Extend variant descriptors with stable ID, label, description, preview image,
  compiled entry point, capability requirements, and optional fallback.
- Use `/i/:uuid/display` for the saved active variant and
  `/i/:uuid/display/:variant_id` for an explicit preview. Keep any legacy query
  parameter only temporarily during development.
- Define the browser renderer lifecycle: `mount`, snapshot/event update, `resize`,
  and `destroy`.
- Require cleanup of animation frames, WebGL contexts/resources, audio nodes,
  observers, and DOM listeners.
- Build each renderer as its own local chunk or entry point so selecting one does
  not load every rendering library.
- Show visual cards in settings with Preview, Set active, and Open active display.
- Detect required browser/hardware capabilities and use the declared fallback.
- Add a development diagnostics overlay for renderer name, resolution, FPS, texture
  count, connection state, and last event; keep it disabled in presentation mode.

### Exit criteria

- Two tabs can display different variants of the same instance and receive the same
  content updates without changing the saved variant.
- Reload and machine restart open the saved variant.
- Repeated variant switching does not accumulate animation loops or resources.
- Unsupported rendering capability produces a fallback or an actionable operator
  message rather than a blank wall.

### Early visual proof checkpoint

Before starting the complete media package, build deliberately small renderer
proofs for PixiJS, Three.js, p5.js, and HTML/SVG. Each proof uses the same fixture
snapshot and one simulated `item_published` event, and each must mount, resize, and
destroy through the common contract. These are disposable visual proofs rather
than the final art direction. They validate library packaging, lazy loading,
surface routing, cleanup, and target-device capability early enough to change the
contract cheaply.

## Phase 6: reusable browser media package

Extract and improve the proven Wall2Wonder image flow as an optional Experience
dependency.

### Package boundary

Create a separately testable TypeScript package, provisionally
`@wakecanvas/media`, with four layers:

- pure RGBA transforms: background classification, connected mask, morphology,
  feathering, despill, and compositing;
- browser adapters: `createImageBitmap`, Canvas/OffscreenCanvas resize, encode, and
  orientation handling;
- Web Worker protocol: progress, cancellation, limits, and errors; and
- LiveView integration: preview and upload of the resulting `File`/`Blob`.

The package is a build-time dependency. Each consuming Experience embeds its chosen
version in its own compiled bundle.

### Work

- Decode camera-supported input in the browser, resize once to bounded dimensions,
  process RGBA once, and encode once as transparent PNG or WebP.
- Run expensive pixel work in a Web Worker with an OffscreenCanvas path and a
  tested fallback.
- Port the existing edge-connected chroma algorithm.
- Replace single-value sampling with robust corner-patch and border sampling,
  saturation-weighted circular hue, brightness statistics, and outlier rejection.
- Use one consistent background-distance rule for seeding and propagation.
- Rename the existing mask `erode` operation to background-mask dilation.
- Add configurable tolerance, edge stop, dilation, feather, and despill.
- Clear RGB as well as alpha for fully transparent pixels and handle alpha correctly
  during resizing/compositing to prevent coloured fringes.
- Reduce peak allocations by combining mask/visited state where practical.
- Provide automatic preview plus tolerance/background controls and a retake path.
- Retain original and processed files by default; make original retention
  configurable for privacy/storage-sensitive installations.
- Add visual golden fixtures covering green, blue, white, shadowed, textured,
  edge-touching, translucent, and failure cases.

### Exit criteria

- A phone or intake station can process, preview, and upload a typical photograph
  without freezing its UI or consuming image-processing CPU on the Phoenix server.
- Ten clients can process concurrently because work remains on their devices; the
  server receives bounded finished uploads.
- Output has no obvious green transparent-pixel fringe at display scale.
- Failure leaves the original available for retake/reprocessing and produces a
  friendly actionable message.
- Experiences that do not use media processing do not download its code.

## Phase 7: Living Gallery production vertical

Apply the hardened contracts to the first real workshop Experience.

### Work

- Keep artwork and Workshop Moments as separate content roles in one instance.
- Preserve independent auto-publish settings; default artwork to automatic and
  moments to review.
- Complete original/processed media metadata, attribution consent, ordering,
  publication state, soft deletion, restoration, and purge behavior.
- Integrate the browser media package into artwork intake with optional background
  removal and preview controls.
- Keep Moments upload simple and capable of accepting normal photographs without
  background removal.
- Send display clients an initial bounded snapshot followed by idempotent events.
- Add reconnect, retry, disk-limit, corrupt-image, and storage-low behavior.
- Add configurable retained-media limits suitable for unattended operation.

### Exit criteria

- The complete morning/evening workshop scenario works with isolated instances.
- Artwork can appear immediately while moments wait for approval.
- Publish, unpublish, soft-delete, restore, archive, reboot, and reconnect all
  preserve the expected visible wall.
- A bad upload or disconnected participant does not interrupt the display.

## Phase 8: renderer demonstration suite

Turn the four early renderer proofs into deliberate Living Gallery presentations
over the real content and event stream. These validate the SDK and provide the
artistic demonstration suite; they are not four separate Experiences.

### 8.1 Living Film Collage (`living-collage`) — PixiJS + GSAP

- Move workshop moments through multiple framed film ribbons with different
  directions, speeds, depth, and tilt.
- Present background-removed artwork as colourful, free-floating foreground objects.
- Use a photographic developing effect for new moments and an elastic entrance for
  new artwork, followed by slow periodic whole-collage recomposition.
- Move each artwork into a large central focus for a ten-second feature cycle with
  optional creator attribution.
- Keep continuous motion in the PixiJS ticker and use GSAP for meaningful transitions.
- Add bounded parallax, colour treatment, blur, shadows, masks, and texture limits.
- This is the practical default and Raspberry Pi performance baseline.

### 8.2 Living Spiral (`gallery-orbit`) — Three.js + GSAP

- Place framed, muted workshop moments on a broad outer memory helix.
- Place transparent artwork on a brighter inner orbit and keep it facing the camera.
- Use an autonomous GSAP sequence to bring artwork into a central hero position,
  show optional attribution, and return it to the orbit without mouse or scroll input.
- Give newly published artwork priority in the next hero sequence.
- Add slow camera movement, fog, particles, lighting, depth fades, vignette, and
  restrained film grain while keeping all animation teardown explicit.
- Start with WebGL and declare a fallback when required capability is unavailable.

### 8.3 Growing Canvas — p5.js

- Treat every artwork as a seed for evolving generative lines, plants, waves, or
  colour fields.
- Blend moments into the environment as translucent textures.
- Optionally map microphone level/frequency data to wind, movement, density, or
  colour while preserving a deterministic no-audio mode.

### 8.4 Community Tapestry — HTML/SVG

- Compose artwork, names, and moderated testimonials into a readable growing tapestry.
- Use SVG relationships and CSS transitions without WebGL.
- Serve as the low-power/accessibility fallback and prove the variant API does not
  require a canvas library.

### Deferred optional variant

`Gravity Playground` may later combine PixiJS with a small 2D physics engine for
falling, colliding, and sound-disturbed artwork. It is deferred until the four core
renderers validate lifecycle and performance boundaries.

### Exit criteria

- All four variants consume the same persisted content and live events.
- Their rendering libraries are locally packaged and loaded only by the requested
  variant.
- Each passes repeated mount/destroy, reconnect, 24-hour soak, and target-hardware
  frame/memory checks.
- Sound permission denial or absent microphone does not break Growing Canvas.

## Phase 9: kiosk packaging and unattended operation

### Work

- [Implemented] Produce and smoke-test self-contained releases for Windows x64,
  Linux x64, and Linux ARM64. The ARM64 test runs in an emulated Linux ARM64
  container; representative Raspberry Pi verification remains below.
- [Implemented; physical validation pending] Add service startup, crash
  restart, delayed browser launch, fullscreen kiosk URL, and graceful shutdown
  behavior for each target.
- [Implemented] Add first-run data-directory
  initialization and management-code setup.
- [Implemented] Build, smoke-test, and upload Windows x64, Linux x64, and native
  Linux ARM64 artifacts from the GitHub Actions release matrix on manual dispatch
  or a `v*` version tag.
- [Implemented] Provide local hostname/IP links and locally generated QR codes for
  participant surfaces without an internet service.
- [Implemented] Add health, disk usage, database integrity, package, active runtime,
  and renderer diagnostics, including bounded display heartbeats and `/health`.
- [Implemented] Add checksummed export and validated restore/import for complete
  UUID instance directories. Export requires archive; imports arrive archived and
  support preserve, clone, or exact-name-confirmed replacement on UUID collision.
- Run power-loss, restart, disconnected-network, full-disk, corrupt-package, and
  long-running soak tests on representative mini-PC and Raspberry Pi hardware.

### Exit criteria

- A clean machine can unpack/install WakeCanvas and reach management without a
  development toolchain.
- Reboot returns to the configured active display without human intervention.
- An operator can move an exported instance to another compatible kiosk while
  retaining its UUID, database, media, settings, and selected variant.
- A recoverable failure is visible in management and does not leave a blank kiosk.

## Phase 10: optional hosted deployment

This phase begins only after local access control, storage, and backup behavior are
proven.

### Work

- [Implemented] Build the same release as a multi-stage Docker image.
- [Implemented] Run one application instance with one persistent volume initially.
- [Implemented] Configure proxy URL settings, management secrets, backup guidance,
  health checks, and Fly.io Machine restart behavior. Fly terminates HTTPS.
- [Implemented] Keep SQLite and instance directories on the persistent volume.
- [Implemented] Document the limitations of single-node SQLite deployment and avoid introducing
  distributed coordination until a real hosted requirement demands it.

### Exit criteria

- A workshop can use a hosted URL without changing Experience code or content
  semantics.
- Restart/redeploy preserves all platform and instance data.
- Local ZIP/release deployment remains fully functional without cloud configuration.

## Cross-cutting verification gates

Every phase must maintain:

- formatting and tests for each affected independent Mix project;
- SDK contract tests for Experience/platform boundaries;
- no required network access during kiosk runtime;
- no Node.js requirement in a production release;
- management availability when no Experience is installed or runnable;
- bounded file, image, database, and event inputs;
- visible operator diagnostics without exposing access codes or sensitive paths;
- accessibility and touch usability for management/intake views; and
- documentation updates in the same change as contract or behavior changes.

Before a release candidate, run:

- clean-install test on every supported target;
- upgrade and rollback test;
- archive, restore, export, import, purge, and uninstall test;
- ten-client upload burst test;
- display reconnect test;
- active-instance crash recovery test;
- 24-hour renderer soak test for every bundled variant; and
- offline reboot test with the network and internet unavailable.

## Explicitly deferred

- untrusted third-party code sandboxing;
- multiple simultaneously active Experience instances on one kiosk;
- distributed/multi-node SQLite writes;
- accounts, roles, OAuth, and cloud identity;
- mandatory cloud licensing or telemetry;
- production hot code replacement;
- ML background removal as the default;
- Rust Ports or WASM without a measured JavaScript bottleneck;
- shared global Experience CSS/JS bundles; and
- Unity or a separate native rendering application.

## Delivery rule

Implement phases as small end-to-end changes, not as parallel infrastructure
projects. A phase may be split into pull requests, but each merged change should
leave a demonstrable user path working. Do not begin all four renderer variants
until the UUID, runtime, package, variant, and media contracts they consume are
stable.
