# ADR-0003: Offline-first SQLite storage

- Status: accepted
- Date: 2026-10-16

## Decision

Use one platform-owned SQLite database and one isolated SQLite database per
Experience instance. Store large media in instance-specific filesystem directories.
Use WAL and a ten-second busy timeout for platform and instance connections. Keep
transactions short and treat any remaining busy response as bounded, retryable
contention rather than an unhandled visitor-facing error.

## Consequences

WakeCanvas requires no external database and Experience schemas cannot collide.
Each Experience owns its migrations and data compatibility, while separate
instances of the same Experience cannot mix workshop data. The platform must back
up and report these databases but must not query their private schemas.
