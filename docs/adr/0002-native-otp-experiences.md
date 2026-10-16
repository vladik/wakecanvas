# ADR-0002: Trusted native OTP Experience packages

- Status: accepted
- Date: 2026-10-16

## Decision

Distribute Experiences as checksummed, precompiled, target-specific OTP application
packages. Discover them at startup, register all valid packages, and start only the
Experience runtime required by the selected instance. Installation and upgrades
require a controlled restart.

## Consequences

Creators may include LiveViews, browser assets, supervised processes, and native
Ports without running a second application stack. Packages are not a sandbox;
operators must trust their publishers. Hot code loading is intentionally excluded.
