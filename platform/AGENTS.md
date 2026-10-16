# Platform guidance

This directory is the WakeCanvas host application.

- Keep one Phoenix endpoint and stable platform-owned routes.
- Platform modules may depend on `WakeCanvas.ExperienceSDK`; they must not depend on concrete Experience modules.
- Discover Experience modules through validated package metadata and the runtime registry.
- The management UI must start with zero Experiences and when every installed package is rejected.
- Keep the platform SQLite schema limited to platform concerns. Never query an Experience-owned database.
- Uploads are staged and validated before entering the active package directory.
- Do not execute package code during initial archive validation.
- Treat the configured management code as lightweight local access control, not as a security sandbox.
- Any new background process must have a clear owner, bounded resource usage, and a supervised failure policy.
