# Experience authoring

An Experience is an ordinary, independent Mix OTP application. It may live in this
repository or in a completely separate repository.

## Naming

First-party packages use the singular `WakeCanvas.Experience.<Name>` module
namespace, an OTP application such as `:wake_canvas_experience_<name>`, and a
reverse-domain package ID such as `org.wakecanvas.experience.<name>`. This keeps
package code visibly distinct from the platform-owned `WakeCanvas.Experiences`
catalog and lifecycle context.

External authors retain their own module and reverse-domain namespaces, for example
`ArtistStudio.Experience.SoundGarden` and
`com.artiststudio.experience.sound-garden`. They must not place their code under the
`WakeCanvas` module namespace.

It depends on the versioned WakeCanvas Experience SDK, never on platform internals.
Its package may contain:

- an OTP supervision tree;
- display, intake, and operator LiveViews;
- a compiled JavaScript renderer and scoped CSS;
- images, fonts, sound, and other static assets;
- Experience-owned SQLite migrations; and
- target-specific native helpers supervised through Elixir Ports.

An Experience declares as many browser surfaces as its interaction requires. The
platform mounts relative paths below `/i/:instance_id/`; Experiences never add
top-level Phoenix routes. Mark one surface as `display` for the `/display` alias and
optionally one as `primary_intake` for `/intake`. Additional participant and
operator surfaces use their declared paths.

An Experience can declare stable display variants with an ID, operator-facing
label, and description, plus one package default. Store the selected default in the
instance configuration. The platform validates temporary `?variant=` overrides and
passes the resolved variant to the display surface. Different variants share the
same instance data and may run simultaneously in separate browser sessions.

Operator settings belong to the Experience and are stored in the instance `config`
map. A trusted operator surface can persist a validated patch through the SDK
`ConfigAPI` supplied by the platform in its surface session. Experiences must define
defaults so instances created by older package versions remain valid.

## Frontend assets

Every Experience has an independent frontend build. Authors may use Tailwind and
DaisyUI normally for LiveView views and controls. The Experience compiles and ships
its own `experience.css`; it must not assume that a class is present in the
platform stylesheet. The SDK's frontend profile pins the recommended compatible
versions and publishes shared theme variables and root-element conventions.

Visualization code is also Experience-owned. Choose PixiJS, p5.js, Three.js, or
plain JavaScript according to the artwork, bundle it into `experience.js`, and do
not add it to the platform. Custom CSS should be scoped below
`[data-wakecanvas-experience="<experience-id>"]` to avoid affecting the stable
platform shell.

The standard asset flow is:

1. edit source files under `assets/`;
2. run `mix assets.build` while developing;
3. run `mix assets.deploy` when creating a package; and
4. package browser-ready files from `priv/static/`.

Frontend tooling is required only on the developer or CI machine. It is never
installed or executed on a production kiosk.

The OTP application should be dormant until selected. Starting it acquires required
hardware and starts runtime workers; stopping it must release them cleanly.

Use LiveView and the platform endpoint for networking. A renderer such as PixiJS
runs in a LiveView hook and exchanges bounded events with the server. Raw audio or
video frames should not be pushed through LiveView; analyze them near the device and
send only the data the experience needs.

An Experience must support:

1. deterministic metadata discovery without starting hardware;
2. configuration validation;
3. clean OTP start and stop;
4. operation without internet access;
5. bounded disk, memory, process, and log usage; and
6. package smoke testing on every advertised OS/architecture target.
