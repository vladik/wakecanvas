# Experience package format

This document describes the accepted archive contract. The SDK builds this archive
deterministically, and the platform management view validates and stages it for
activation on restart. One previous archive is retained for rollback, and packages
without any referencing instances can be permanently uninstalled.

An Experience is distributed as a target-specific `.wakecanvas` ZIP archive:

```text
wakecanvas-experience.json
CHECKSUMS
SIGNATURE                         # optional
lib/living_gallery-0.1.0/
|-- ebin/*.beam
`-- priv/
    |-- static/
    |   |-- experience.css
    |   |-- variants/*.js
    |   |-- chunks/*.js
    |   `-- media/*.js
    |-- repo/migrations/*.exs
    `-- native/<target>/*
```

The manifest identifies:

- stable Experience ID, name, and semantic version;
- OTP application and SDK entry module;
- WakeCanvas SDK, platform, Elixir, and OTP requirements;
- operating system, CPU architecture, and native ABI when applicable;
- browser surfaces, relative paths, roles, and LiveView modules;
- display variants, entry points, capabilities, and fallbacks;
- stylesheet and optional media-worker assets;
- frontend profile and compiled asset requirements;
- required capabilities such as camera, microphone, touch, or native Port; and
- package format version.

`target` is either `any` for a package with no target-specific native code, or the
platform target name such as `windows-x86_64`, `linux-x86_64`, or `linux-aarch64`.
Production release pipelines should still build and test pure BEAM packages against
every advertised target.

Packages contain no source code or build caches. Every regular file is covered by
`CHECKSUMS` except `CHECKSUMS` itself and the optional detached `SIGNATURE`.
Checksum records are sorted and use lower-case SHA-256 followed by two spaces and
the normalized archive path. Validation rejects traversal, absolute paths, links, duplicate
normalized paths, unexpected top-level files, incompatible targets, oversize
content, checksum mismatches, and module collisions before code is activated.

Validation also verifies the OTP `.app` identity/version, every BEAM container and
its filename/module identity, the entry module, every declared surface module,
surface ID/path/role uniqueness, renderer entry points, stylesheet and thumbnail
assets, default/fallback variant references, and the rule that target-neutral
packages cannot contain native binaries. On restart, the compiled SDK definition is
compared with the manifest before registration.

The SDK writes stored ZIP entries with fixed metadata so identical compiled inputs
produce byte-for-byte identical archives and the same archive digest. Run:

```text
mix assets.deploy
mix wakecanvas.package --output path/to/experience.wakecanvas
```

Before distributing an archive, smoke-load it with the platform version and target
release that will run it:

```text
mix wakecanvas.package.verify path/to/experience.wakecanvas
```

This performs archive validation in addition to loading the OTP application spec,
checking that its declared runtime applications are available, loading every
packaged BEAM module, and comparing the compiled entry definition with the
manifest. It does not install or start the Experience. Run it in a clean release
process so already-loaded development modules cannot hide a missing dependency.

Validated archives are extracted to
`<data-root>/packages/cache/sha256-<archive-digest>/`. The catalog records the
digest and `pending_restart` state. Package code is never loaded in the upload
request; Registry considers it only during the next application startup.

The kiosk never rebuilds a package. `priv/static/experience.css` contains the
Experience's Tailwind, DaisyUI, and custom rules. Each display variant points to a
separate ESM entry containing its browser dependencies. Optional image processors
are Experience-owned worker and adapter assets. Node.js remains a developer/CI
dependency only.

## Upgrade, rollback, and uninstall

Uploading a different archive with the same Experience ID stages an upgrade and
keeps the last installed digest and manifest as its rollback point. Replacing one
pending upgrade with another does not discard that installed rollback point.
Rollback swaps the selected and retained artifacts and requires a restart; it does
not roll back instance databases or media.

Uninstall requires typing the exact package name and is blocked while any active or
archived instance references the package. After the catalog record is removed,
unreferenced current and rollback cache directories are deleted. Source-linked
development packages are not uninstallable through Management.

Initial targets are Windows x64, Linux x64, and Linux ARM64. Pure BEAM Experiences
still use the target build matrix so deployed artifacts are tested against the same
platform runtime.
