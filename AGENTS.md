# WakeCanvas repository guidance

## Product invariant

WakeCanvas is offline-first software for unattended participatory installations.
Do not introduce a required cloud service, external database, Redis, separate
WebSocket server, or Node.js production runtime.

## Architecture boundaries

- `platform/` is one Phoenix/Elixir release and owns the endpoint, stable routes,
  operator access, package lifecycle, active instance lifecycle, platform data,
  diagnostics, and kiosk operation.
- `experiences/sdk/` is the only supported contract between the platform and an
  independently developed Experience.
- Every Experience is a standalone Mix OTP application, not an umbrella child.
- Experiences must not depend on platform internals.
- Zero or more Experience packages may be installed and each package may have zero
  or more configured instances; exactly zero or one instance may be active.
- Installed Experience code is trusted native code, not sandboxed code.
- Package installation and upgrades are staged and activated on restart. Do not
  add production hot code replacement.
- The platform owns stable HTTP routes. Experiences contribute declared LiveViews,
  renderer assets, callbacks, configuration metadata, and supervised runtime code.
- The platform database and each Experience instance database are separate SQLite
  files. Platform code must not query an instance database directly.
- An instance may write persistent data only below its assigned instance data
  directory. Deleting an instance removes that complete directory and its platform
  configuration; do not leave Experience-owned data elsewhere.
- Package uninstall is blocked while instances reference it unless the operator
  explicitly confirms a cascading delete of those instances.

## Repository practices

- Preserve independence of the three Mix projects. Run formatting and tests in
  each affected project.
- Record durable architectural decisions under `docs/adr/`.
- Keep runtime package formats deterministic and checksummed.
- Prefer explicit, bounded SDK contracts over calls into internal modules.
- Every Experience owns, compiles, and packages its browser assets. It may use
  Tailwind, DaisyUI, PixiJS, p5.js, or other build-time dependencies, but it must
  not rely on the platform's compiled CSS or JavaScript containing its classes.
- Production packages contain browser-ready CSS and JavaScript. Node.js and
  frontend build tools must not be required on the kiosk.
- Native helpers belong to their Experience package and run through a supervised
  Port unless a documented ADR chooses another boundary.
- Keep kiosk failure modes visible: a broken Experience must not prevent the
  management UI from starting.

## Verification

Run `scripts/test.ps1` on Windows or `scripts/test.sh` on Unix. When only one Mix
project changes, its local `mix precommit` or format/compile/test sequence is also
acceptable during iteration.
