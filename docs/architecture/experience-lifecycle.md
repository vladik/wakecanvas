# Experience lifecycle

## Installation

An operator uploads an Experience package in the management view or places it in
the configured package directory. The platform stages uploads outside the active
directory, validates them, and marks them pending. Newly installed or upgraded code
is activated only during a controlled platform restart.

At startup the platform:

1. Reads staged package records from the platform catalog.
2. Resolves their previously validated content-addressed cache directories.
3. Adds verified BEAM paths and loads application metadata and entry modules.
4. Validates the declared SDK definition.
5. Compares compiled identity, surfaces, variants, capabilities, and browser assets
   with the staged manifest.
6. Registers valid Experiences and marks packages installed; packages that cannot
   load are marked rejected with a bounded Management diagnostic without preventing
   the platform from starting.
7. Resolves the selected instance and starts only its Experience runtime.

Archive path, size, manifest, checksum, target, version, and module-collision checks
happen before staging, during the management upload. No package code executes in
that request.

## Instance creation

Installing a package makes an Experience type available; it does not create or
start a workshop. An operator creates an instance by choosing an installed package,
giving the instance a human-friendly name, and completing the Experience-defined
configuration form. The platform assigns an immutable UUID and isolated database
and media paths derived from that UUID. An optional slug is only a mutable URL
alias.

Multiple instances may reference the same installed Experience package. Their
configuration and content never share storage unless a future explicit sharing
feature is designed.

## Activation

Selecting an Experience instance is a controlled state transition:

1. Resolve its installed package and validate saved configuration and hardware
   requirements.
2. Stop display sessions belonging to the previous instance.
3. Stop the previous instance's Experience runtime and release its resources.
4. Pass the selected instance context—ID, configuration, database path, and data
   directory—to its Experience and verify readiness.
5. Commit the active selection and reload connected displays.

If startup fails, WakeCanvas records the error and either restores the previous
instance or enters a safe management-only state.

## Instance archive and purge

Archiving is the normal reversible operator action. It uses a platform-owned
confirmation modal, makes the instance unavailable, and preserves its configuration,
database, and files. An archived instance can be restored with the same stable ID.

Permanent purge is a separately named maintenance action for an already archived
instance and requires stronger explicit confirmation. The platform then closes its
database, stages and removes its complete data directory, and removes its platform
configuration. Cleanup must remain restart-safe and retryable.

The purge boundary includes the instance SQLite database, uploaded media, generated
files, caches, temporary files, and platform-managed automatic backups. The current
management view implements archive, restore, and archived-only purge. Purge requires
typing the exact instance name, stages the directory outside the live namespace,
deletes the catalog row, and retries leftover staged-directory cleanup at startup.

## Instance export and import

Only archived instances can be exported. This is the consistency boundary: the
platform copies the Experience-owned SQLite database and files as opaque bytes only
after its runtime has stopped. The resulting `.wakecanvas-instance` ZIP contains
the complete instance directory, portable metadata, and SHA-256 checksums.

Management imports validate paths, entry types, size limits, metadata, and every
checksum before moving any files into the live instance namespace. The matching
Experience package and exact exported version must already be installed. An import
always arrives archived and inactive so the operator can inspect it before restore.

UUID collision behavior is explicit:

- **Stop and report** preserves the UUID and refuses an existing identity.
- **Create a copy** assigns a new UUID, drops the optional slug, and preserves the
  Experience database, media, settings, and participant-code configuration.
- **Replace archived** replaces only the matching archived UUID and requires the
  exact existing instance name. A live instance cannot be replaced.

Filesystem moves are staged. A failed catalog insert/update removes the incoming
directory and restores the previous archived directory where applicable.

## Package uninstall

Uninstall is blocked while any instance references the package. The management UI
may offer an explicit “delete all instances and uninstall” operation; it must list
the affected instances and require separate destructive confirmation. After all
instances are deleted, the platform removes package code, compiled browser assets,
native helpers, manifests, and unreferenced extraction caches.

Deleting one instance never removes shared package files or another instance's
data. Removing a package with no instances never affects other packages.

The current management implementation disables uninstall while references exist,
requires exact-name confirmation, deletes the catalog record, and removes current
and retained cache directories only when no package still references their digest.

## Upgrade and rollback

Only one installed version of an Experience ID is active. An upgrade retains the
previous package until the replacement has passed restart and smoke checks. Rollback
restores the exact previous version and checksum, then restarts the platform.

Experience-owned database migrations run separately for every affected instance
and must be forward-safe and backed up before a breaking upgrade. Package rollback
and data rollback are different operations and must never be presented as
equivalent.

The current catalog retains one previous archive and manifest. Selecting Rollback
swaps current and previous artifacts, marks the package `pending_restart`, and does
not modify any instance directory.
