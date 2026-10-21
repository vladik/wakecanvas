# Unified deployment implementation plan

WakeCanvas uses one application release and one startup contract across manual,
kiosk, and hosted deployments. A deployment profile changes how the release is
launched; it does not create a separate application or data format.

## Implementation status

- Shared package/instance bootstrap: implemented and covered by automated tests.
- Windows manual and kiosk launchers: implemented.
- Optional prepared-instance inputs on the Windows and Linux builders: implemented.
- Seeded Windows build/start/restart/display smoke test: passed.
- Hosted Docker image build and packaged-module loading check: passed.
- Linux scripts: syntax-checked; native x64/ARM64 release CI and physical kiosk
  validation remain the platform-specific acceptance gates.

## Outcomes

- A Windows user can extract one ZIP and double-click `start-wakecanvas.cmd`.
- The same Windows ZIP can later be configured for unattended kiosk startup.
- A demo ZIP can contain a portable instance archive and activate it once on
  first startup, including its media and settings.
- Linux and Docker use the same release bootstrap and environment variables.
- Repeated startup never duplicates or replaces an existing instance.
- Node.js, Elixir, Erlang, and an internet connection are not required on the
  target computer.

## Shared startup contract

Every profile follows the same ordered startup path:

1. Resolve the writable data directory and persistent secrets.
2. Run platform database migrations.
3. discover and install bundled Experience packages;
4. discover and import bundled instance archives;
5. optionally restore and activate the first bundled instance when no instance
   is already active;
6. start the selected Experience runtime and Phoenix endpoint.

Bundled instance import is UUID-idempotent. Auto-activation occurs only for a
new import. If an instance with that UUID is
already known, startup leaves its database, files, configuration, publication
state, activation choice, and other operator changes untouched.

## Runtime profiles

| Profile | Bind default | Browser | Process supervision |
| --- | --- | --- | --- |
| `manual` | localhost | normal browser | release stays running until stopped |
| `kiosk` | local network | fullscreen display | launcher monitors and restarts |
| `hosted` | all interfaces | none | Docker/Fly supervises the release |

Profiles use the same release artifact for a given operating system and CPU.
Different OS/CPU artifacts are unavoidable because Erlang/OTP releases contain
native runtime files, but they are produced from the same build and startup
contract.

## Configuration contract

- `WAKECANVAS_PROFILE`: `manual`, `kiosk`, or `hosted`.
- `WAKECANVAS_DATA_ROOT`: writable persistent data directory.
- `WAKECANVAS_BUNDLED_PACKAGES`: optional directory of `.wakecanvas` packages.
- `WAKECANVAS_BUNDLED_INSTANCES`: optional directory of
  `.wakecanvas-instance` archives.
- `WAKECANVAS_AUTO_ACTIVATE_SEED`: activate a bundled seed only when no active
  instance exists.
- `WAKECANVAS_BIND_IP`: explicit network binding override.

## Implementation phases

### Phase 1 — shared bootstrap

- Add an OTP bootstrap worker after package discovery and the Experience
  registry, but before the HTTP endpoint.
- Validate and import bundled instance archives through the existing portable
  archive API.
- Restore and activate a seed only when requested and safe.
- Log imported, skipped, activated, and rejected archives.
- Cover first import, repeat startup, and non-destructive activation with tests.

### Phase 2 — Windows artist package

- Keep the internal `run-wakecanvas` launcher profile-aware.
- Add double-click start, stop, management, and kiosk launchers.
- Keep raw PowerShell and recovery operations in a separate `admin-tools`
  directory; the release root exposes only safe user-facing commands.
- Add a human-readable `START HERE.html` and concise text instructions.
- Extend the existing Windows release builder with optional instance archive
  and management-code parameters; do not create a second build pipeline.
- A seeded build detects its `seeds` folder and enables one-time activation.

### Phase 3 — hosted and Linux alignment

- Document and expose the same seed-directory variables in Docker/Compose.
- Reuse the same profile and bootstrap in Linux launch/service scripts.
- Keep setup, service, recovery, and advanced shell scripts under `admin-tools`;
  the Linux release root exposes only safe user-facing commands.
- Keep persistent state in one mounted or backed-up data directory.

### Phase 4 — release validation

- Build and smoke-test an ordinary Windows ZIP.
- Build a seeded demo ZIP, start it twice, and verify there is exactly one
  imported instance and that the selected display opens.
- Verify stop/start persistence, management access, LAN kiosk access, and a
  Docker restart with a persistent volume.

## Acceptance criteria

The implementation is complete when an artist can extract a seeded Windows ZIP,
double-click start, and see the prepared display without installing tools or
importing content; an operator can use the same folder in kiosk mode; and the
same seed/package/data contract works in the hosted image without a separate
application architecture.
