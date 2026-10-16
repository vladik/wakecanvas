# ADR-0001: Plugin-oriented Phoenix modular monolith

- Status: accepted
- Date: 2026-10-16

## Decision

Build WakeCanvas as one Phoenix/Elixir release rather than microservices or a Mix
umbrella. Independently deployable Experiences are standalone Mix OTP applications
loaded through a versioned SDK and package boundary.

## Consequences

The kiosk has one service, endpoint, database technology, logging system, and
operational lifecycle. Experiences remain independently buildable, but native code
shares the BEAM VM and therefore must be trusted and version-compatible.
