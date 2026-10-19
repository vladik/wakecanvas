# Architecture overview

WakeCanvas is a plugin-oriented modular monolith. It is deployed as one Phoenix
release and one operating-system service, but it can load independently compiled,
trusted OTP Experience applications.

```text
Kiosk computer
└── WakeCanvas release
    ├── Phoenix endpoint and LiveView
    ├── platform SQLite database
    ├── package loader and Experience registry
    ├── active instance manager
    ├── PubSub and stable local-network routes
    └── installed Experience packages
        ├── Living Gallery OTP application
        └── future OTP applications
```

## Ownership

The platform owns package installation, compatibility checks, configured instance
records, the HTTP endpoint, stable routes, management access, hardware inventory,
active selection, kiosk startup, and failure diagnostics.

An Experience package owns its interaction model, declared LiveViews, browser
renderer, assets, supervised processes, schemas, and migrations. Each configured
instance receives isolated configuration, storage paths, and a SQLite database. The
Experience calls the platform only through the versioned Experience SDK.

## Packages and instances

An installed Experience package is reusable code, such as Living Gallery 1.0. An
Experience instance is an operator-created installation of that code with its own
identity, name, configuration, database, and media directory. A kiosk can therefore
have “Morning Workshop” and “Evening Workshop” instances backed by the same Living
Gallery package without mixing their content.

The operator activates an instance, not a package. At most one instance runs at a
time. Switching between two instances of the same package follows the same clean
stop/start lifecycle as switching between different Experiences; this keeps
hardware and state ownership predictable.

`ActiveInstanceManager` coordinates the catalog selection with an
`ActiveInstanceSupervisor`. An Experience may supply an instance child spec; a
generic runtime is used otherwise. The old runtime stops before its replacement
starts, and a failed switch restores the prior runtime when possible.

## Runtime invariants

- An installation may have zero or more registered Experience packages and
  configured instances.
- At most one Experience instance and its OTP runtime are active.
- Installed packages are inspected and registered at platform startup.
- Inactive instances do not hold cameras, microphones, timers, or workers.
- The management UI remains available when no Experience can start.
- Phoenix routes remain in the platform. Experience modules are resolved through
  the registry behind stable display, intake, and operator routes.
- The platform loads browser assets only for the active instance's Experience.
- Every Experience compiles and packages its own CSS and JavaScript. It may use
  Tailwind and DaisyUI for LiveView UI and may bundle PixiJS, p5.js, or another
  renderer. It never relies on the platform build discovering its CSS classes.
- The kiosk serves browser-ready assets and does not run Node.js, Tailwind, or
  another frontend build tool.

## Browser asset boundary

The platform and each Experience have separate frontend builds. The platform's
Tailwind and DaisyUI output styles the management shell. An Experience uses the
SDK's supported frontend profile during development, compiles its own stylesheet,
and ships that stylesheet in its package. This makes a package buildable in a
separate repository and installable after the platform itself was compiled.

The SDK defines integration conventions such as the Experience root attribute,
asset entry points, theme variables, and compatible frontend profile. It does not
provide runtime CSS or JavaScript. Custom CSS must be scoped below the Experience
root. Renderer libraries and their versions belong to the Experience bundle.

The shared `@wakecanvas/media` source package is a build-time option, not a global
browser runtime. A consuming Experience compiles the worker and adapter into its
own assets. Experiences that do not use it download nothing.

Optional camera, microphone, and sensor inputs remain browser- or
Experience-runtime concerns. For example, Growing Canvas requests microphone
permission only after a visitor/operator gesture, converts audio to a local level,
and releases its stream and audio graph in `destroy()`. Raw audio is neither sent
to Phoenix nor persisted. Denial degrades to the deterministic silent renderer.

## Browser surfaces and routes

An Experience declares any number of named browser surfaces. Each surface supplies
a relative path, LiveView module, label, and role such as display, primary intake,
participant, or operator. The platform owns the router and mounts these surfaces
below the instance's immutable UUID:

```text
/i/550e8400-e29b-41d4-a716-446655440000/display
/i/550e8400-e29b-41d4-a716-446655440000/artwork
/i/550e8400-e29b-41d4-a716-446655440000/moments
/i/550e8400-e29b-41d4-a716-446655440000/review
```

Instance names such as “Morning Workshop” are editable labels and never identify
records. An optional installation-local unique slug can provide a convenient route
alias, but canonical links, storage, and exports always use the UUID. The platform
may expose `/display` and `/intake` as convenience aliases for the active instance's
display and primary-intake surfaces. Experience packages cannot claim arbitrary
top-level routes.

## Storage

The platform uses `platform.sqlite` for package inventory, instance records, active
selection, platform configuration, and hardware configuration. Each instance has a
separate database at `data/instances/<instance-uuid>/experience.sqlite`; its
Experience package owns that database's schemas and migrations.

All SQLite connections use WAL and a ten-second busy timeout. Write transactions
remain short so bursts of local-network uploads wait rather than surfacing ordinary
lock contention to visitors.

Media files live outside SQLite under the same instance-specific data directory.
The instance database stores their metadata and relative paths.

Management and operator surfaces require the installation-wide six-digit code when
configured. Participant surfaces may use a separate six-digit code per instance;
an empty participant code intentionally leaves that workshop open. Successful code
entry creates a signed session, and rotating a participant code invalidates that
instance's earlier sessions.

The instance directory is also the deletion boundary. Experiences must place all
persistent instance-owned files below it. Deleting an instance removes that entire
directory plus its configuration from `platform.sqlite`; deleting one instance
does not affect its package or sibling instances.

## Trust boundary

An OTP Experience executes inside the platform VM and is trusted native code. A
package checksum proves identity and integrity, not safety. Package installation
must therefore be restricted to trusted packages and operators. Supporting
untrusted public code would require a separate isolation architecture.
