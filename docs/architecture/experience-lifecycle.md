# Experience lifecycle

## Installation

An operator uploads an Experience package in the management view or places it in
the configured package directory. The platform stages uploads outside the active
directory, validates them, and marks them pending. Newly installed or upgraded code
is activated only during a controlled platform restart.

At startup the platform:

1. Discovers candidate packages.
2. Validates archive paths, size limits, manifest, checksums, target, and version
   compatibility before executing package code.
3. Extracts each package into a content-addressed immutable cache.
4. Adds verified BEAM paths and loads application metadata and modules.
5. Validates the declared SDK callbacks and UI modules.
6. Registers valid Experiences and records safe diagnostics for rejected packages.
7. Resolves the selected instance and starts only its Experience runtime.

## Instance creation

Installing a package makes an Experience type available; it does not create or
start a workshop. An operator creates an instance by choosing an installed package,
giving the instance a human-friendly name, and completing the Experience-defined
configuration form. The platform assigns an immutable, non-reused positive integer
instance ID and isolated database and media paths.

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
files, caches, temporary files, and platform-managed automatic backups. The initial
vertical implements archive and restore; permanent purge is intentionally deferred.

## Package uninstall

Uninstall is blocked while any instance references the package. The management UI
may offer an explicit “delete all instances and uninstall” operation; it must list
the affected instances and require separate destructive confirmation. After all
instances are deleted, the platform removes package code, compiled browser assets,
native helpers, manifests, and unreferenced extraction caches.

Deleting one instance never removes shared package files or another instance's
data. Removing a package with no instances never affects other packages.

## Upgrade and rollback

Only one installed version of an Experience ID is active. An upgrade retains the
previous package until the replacement has passed restart and smoke checks. Rollback
restores the exact previous version and checksum, then restarts the platform.

Experience-owned database migrations run separately for every affected instance
and must be forward-safe and backed up before a breaking upgrade. Package rollback
and data rollback are different operations and must never be presented as
equivalent.
