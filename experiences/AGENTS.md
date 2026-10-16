# Experience project guidance

Every child project in this directory is an independently buildable Mix project. Do not convert this directory into an umbrella.

- Depend only on the public Experience SDK and explicitly approved shared runtime libraries.
- Do not import or call modules from `platform/`.
- Put browser source under `assets/`, compiled output under `priv/static/`, and
  package only the compiled browser output.
- Treat Tailwind and DaisyUI as Experience build dependencies. Do not depend on
  classes happening to exist in the platform's compiled stylesheet.
- Scope custom CSS to the Experience root. Bundle renderer libraries such as
  PixiJS or p5.js with the Experience that uses them.
- Own schemas and migrations for the Experience's isolated per-instance SQLite
  databases.
- Store all persistent files below the SDK-provided instance data directory so the
  platform can delete an instance completely. Do not persist instance data in the
  package directory or another instance's directory.
- Start hardware and runtime workers only when an instance of the Experience is
  activated; release all resources when it stops.
- Prefer browser-local analysis for latency-sensitive audio or visual rendering.
- Supervise required native helpers as Ports and package one build per supported OS/architecture target.
- Tests must cover configuration validation and clean application startup/shutdown.
