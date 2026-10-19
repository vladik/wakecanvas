# Kiosk diagnostics

WakeCanvas Management includes a manually refreshable **Kiosk health** panel. It
keeps failures visible without requiring internet access or a separate monitoring
service.

The current report checks:

- the platform SQLite database with `PRAGMA quick_check`;
- creation and removal of a temporary marker in the configured data directory;
- capacity of the operating-system volume containing that directory;
- installed, restart-pending, and rejected Experience packages;
- consistency between the selected instance and its supervised OTP runtime;
- display heartbeat, requested and active variant, fallback use, viewport, browser
  visibility, WebGL 2 support, frame rate, renderer failures, and context loss; and
- aggregate instance file count and size without opening Experience databases.

Checks are classified as `ok`, `warning`, or `error`. The overall report uses the
most severe result. Disk capacity warns at 85% used or 2 GB free and becomes an
error at 95% used or 512 MB free. The instance storage walk stops after 100,000
files and reports a warning instead of performing an unbounded scan.

## Machine-readable health

`GET /health` is intentionally available without the management code so a local
service manager, container runtime, or hosted load balancer can verify the kiosk.
It returns HTTP 200 for `ok` and `warning`, and HTTP 503 when any check is in an
`error` state.

The public response includes only the platform version, uptime, generated time,
and each check's ID, status, and operator-safe message. It excludes access codes,
participant-code digests, instance configuration, diagnostic detail maps, and
filesystem paths.

Example:

```json
{
  "status": "warning",
  "platform_version": "0.1.0",
  "uptime_seconds": 7200,
  "checks": [
    {"id": "disk_capacity", "status": "warning", "message": "88% used; 4.2 GB free."}
  ]
}
```

The platform `ExperienceRenderer` hook sends a heartbeat every 15 seconds. Reports
expire after 45 seconds, so closing a tab or losing its network connection does not
leave a permanently healthy display record. Payload values and strings are bounded,
the monitor retains at most 200 browser clients, and reports live only in memory.
Diagnostics never block rendering: an absent monitor or rejected report is ignored.

An active instance with no recent display heartbeat produces a warning. Renderer
load failures and WebGL context loss produce errors. Capability fallback or a
visible frame rate below 20 FPS produces a warning so an operator can choose a
lighter variant.
