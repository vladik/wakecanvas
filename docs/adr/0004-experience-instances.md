# ADR-0004: Separate Experience packages from instances

- Status: accepted
- Date: 2026-10-16

## Decision

Treat an installed Experience package as reusable code and an Experience instance
as an operator-created configuration of that code. Allow many instances per
package, give every instance isolated configuration, SQLite, and media storage, and
permit zero or one active instance per kiosk.

Activating another instance always performs a controlled stop/start transition,
even when both instances use the same package.

## Consequences

Morning and evening workshops can use one installed Living Gallery package without
sharing content. Package upgrades can affect several instances, so compatibility,
migration, backup, and rollback checks operate per instance. The management UI must
present package installation, instance configuration, and instance activation as
three distinct operations. Deletion and uninstall behavior is defined separately in
ADR-0005.
