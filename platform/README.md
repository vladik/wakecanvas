# WakeCanvas Platform

The platform is the single Phoenix/LiveView host installed on a kiosk computer. It
owns Experience installation, activation, stable routes, platform storage,
local-network management, diagnostics, and unattended operation.

This project may depend on the public Experience SDK but never on a concrete
Experience implementation.

```powershell
mix setup
mix phx.server
```

See the repository-level [architecture overview](../docs/architecture/overview.md)
and [platform guidance](AGENTS.md) before implementation.
