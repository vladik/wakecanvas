# Experience package format

This document is the initial contract direction. The build task and final manifest
schema have not yet been implemented.

An Experience is distributed as a target-specific `.wakecanvas` archive containing
one precompiled OTP application and its browser/native assets:

```text
wakecanvas-experience.json
CHECKSUMS
SIGNATURE                    # optional
lib/living_gallery-0.1.0/
├── ebin/*.beam
└── priv/
    ├── static/
    │   ├── experience.js
    │   └── experience.css
    ├── repo/migrations/*.exs
    └── native/<target>/*
```

The manifest will identify:

- stable Experience ID, name, and semantic version;
- OTP application and SDK entry module;
- WakeCanvas SDK, platform, Elixir, and OTP requirements;
- operating system, CPU architecture, and native ABI when applicable;
- declared browser surfaces, relative paths, roles, and LiveView modules;
- renderer and stylesheet entry points;
- frontend profile and compiled asset requirements;
- required capabilities such as camera, microphone, touch, or native Port; and
- package format version.

Packages contain no source code or build caches. Every regular file is covered by
`CHECKSUMS`. Archive traversal, absolute paths, links, duplicate normalized paths,
unexpected top-level files, incompatible targets, and module collisions are
rejected before activation.

The platform does not rebuild an installed package. `priv/static/experience.css`
contains every Tailwind utility, DaisyUI component, and custom rule used by the
Experience. `priv/static/experience.js` contains its renderer and browser-side
dependencies, such as PixiJS or p5.js. Source maps are optional development
artifacts and are excluded from production packages unless a future package
version explicitly supports them.

Initial targets are expected to include Windows x64, Linux x64, and Linux ARM64.
Pure BEAM Experiences still use the same target build matrix so that deployed
artifacts are tested against the exact platform runtime.
