# ADR-0006: UUID Experience instance identity

- Status: accepted
- Date: 2026-10-19

## Decision

Use one UUID as the sole durable identity and database primary key for every
Experience instance. Use the same UUID in canonical instance routes, SDK contexts,
exports, and the derived `data/instances/<uuid>/` directory.

Allow an optional installation-local unique slug as a mutable convenience URL
alias. A slug is not an additional identity: changing it does not move storage,
change relationships, or invalidate the canonical UUID URL.

Convert existing development integer IDs once and move their instance directories
to the generated UUID paths. Do not retain an integer compatibility key.

## Consequences

An exported instance can retain its identity when copied to another kiosk without
coordinating database sequences. Imports must explicitly skip, replace, or clone
when a UUID already exists and must never silently merge data.

UUID URLs are longer than local integers but remain stable across renames and
transfers. Optional slugs provide readable local aliases without becoming storage
keys. Existing development bookmarks using integer routes change during the
one-time migration.
