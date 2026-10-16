# ADR-0005: Instance deletion and package uninstall

- Status: accepted
- Date: 2026-10-16

## Decision

Use reversible archive as the normal operator action. Archive preserves the
instance record and complete data directory and supports restoration with the same
stable ID. Individual Experience media is also soft-deleted: it is excluded from
displays while its row and file remain restorable.

Reserve permanent purge for a separately named maintenance action with stronger
confirmation. Make the SDK-provided instance directory the complete persistent-data
ownership and purge boundary. Purging an instance stops it, removes its platform
configuration, and removes its SQLite database, media, generated files, caches,
temporary files, and platform-managed automatic backups.

Block package uninstall while instances reference it. Cascading instance deletion
is allowed only as a separately presented and explicitly confirmed destructive
operation.

Use a staged, restart-safe deletion state so interruption cannot leave an instance
available with only part of its data. A minimal non-content tombstone may be kept
for diagnostics.

## Consequences

Experience authors must never store persistent instance data outside the assigned
directory. The platform can remove an instance without understanding its private
schema. Exported backups outside WakeCanvas-managed storage remain the operator's
responsibility. Cleanup failures remain visible and retryable instead of being
reported as successful deletion.
