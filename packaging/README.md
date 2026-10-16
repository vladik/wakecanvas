# Packaging

This directory will contain operating-system packaging around the compiled
WakeCanvas release. The release artifact must bundle ERTS and require no system
Elixir, Erlang, Node.js, or external database installation.

Planned targets:

- Windows x64
- Linux x64
- Linux ARM64, including supported Raspberry Pi systems

Release jobs must smoke-test startup, SQLite migration, management readiness,
Experience discovery, clean shutdown, restart, and preservation of the configured
data directory. Target support is not considered implemented until that packaged
artifact passes its own runner smoke test.
