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
platform mounts relative paths below `/i/:instance_uuid/`; Experiences never add
top-level Phoenix routes. Mark one surface as `display` for the `/display` alias and
optionally one as `primary_intake` for `/intake`. Additional participant and
operator surfaces use their declared paths.

An Experience can declare stable display variants with an ID, operator-facing
label, description, ESM entry point, capability requirements, and fallback, plus
one package default. Store the selected default in the
instance configuration. The platform validates explicit
`/i/:instance_uuid/display/:variant_id` previews and passes the resolved variant to
the display surface. Different variants share the same instance data and may run
simultaneously in separate browser sessions.

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
plain JavaScript according to the artwork, bundle each variant as a separate ESM
entry point, and do
not add it to the platform. Custom CSS should be scoped below
`[data-wakecanvas-experience="<experience-id>"]` to avoid affecting the stable
platform shell.

The standard asset flow is:

1. edit source files under `assets/`;
2. run `mix assets.build` while developing;
3. run `mix assets.deploy` when creating a package; and
4. run `mix wakecanvas.package` to package the compiled OTP application and
   browser-ready files from `priv/static/`.

The package task reads `wakecanvas-experience.json` in the project root and writes
the default archive below `_build/wakecanvas/`. A typical release build is:

```powershell
mix deps.get
mix assets.deploy
mix wakecanvas.package --output dist/my-experience-0.1.0.wakecanvas
```

Upload the result from WakeCanvas Management. The platform checks archive paths,
size limits, every SHA-256 checksum, manifest identifiers, SDK/platform/Elixir/OTP
requirements, target compatibility, required BEAM files, and module ownership. A
successful upload is staged and visibly marked **Restart required**; it cannot run
code inside the upload request.

Frontend tooling is required only on the developer or CI machine. It is never
installed or executed on a production kiosk.

The OTP application should be dormant until selected. Starting it acquires required
hardware and starts runtime workers; stopping it must release them cleanly.

An Experience that owns persistent schema implements the optional
`migrate_instance/1` callback. WakeCanvas calls it with the assigned SDK instance
context before starting that instance's supervised runtime. The callback must be
idempotent, may access only the assigned `database_path` and `data_dir`, and returns
`:ok` or `{:error, reason}`. A migration failure prevents activation and leaves the
previous active instance running.

Use LiveView and the platform endpoint for networking. A renderer such as PixiJS
runs in a LiveView hook and exchanges bounded events with the server. Raw audio or
video frames should not be pushed through LiveView; analyze them near the device and
send only the data the experience needs.

Renderer modules export `mount(container, initialSnapshot)` and return an object
that may implement `update(snapshot)`, `resize()`, and `destroy()`. `destroy` must
release animation loops, observers, event handlers, media nodes, textures, and WebGL
resources. The platform imports only the resolved variant and uses its declared
fallback when required browser capabilities are absent.

Display LiveViews using the platform `ExperienceRenderer` hook must forward its
bounded `renderer:diagnostic` event through the optional API supplied in the
surface session. Generated projects include this handler:

```elixir
def handle_event("renderer:diagnostic", payload, socket) do
  case socket.assigns.renderer_diagnostics_api do
    api when is_atom(api) ->
      if function_exported?(api, :report, 2),
        do: api.report(socket.assigns.instance_id, payload)

    _ ->
      :ok
  end

  {:noreply, socket}
end
```

The service implements `WakeCanvas.ExperienceSDK.RendererDiagnosticsAPI`. Reporting
is optional and advisory; the Experience must continue rendering if it is absent.

Experiences that prepare photographs may import `packages/media` (or a published
`@wakecanvas/media` equivalent) during their frontend build. Its worker keeps
decode, resize, connected-background masking, despill, and encoding on the intake
device. The result remains subject to the server upload-size limit.

An Experience must support:

1. deterministic metadata discovery without starting hardware;
2. configuration validation;
3. clean OTP start and stop;
4. operation without internet access;
5. bounded disk, memory, process, and log usage; and
6. package smoke testing on every advertised OS/architecture target; and
7. forwarding the optional bounded renderer diagnostic event.

## Generate an external project

The SDK includes a minimal standalone starter generator. From `experiences/sdk`:

```powershell
mix wakecanvas.new C:\Repos\sound-garden `
  --module ArtistStudio.SoundGarden `
  --app sound_garden `
  --id com.artiststudio.experience.sound-garden `
  --name "Sound Garden"
```

Then work entirely in the generated project:

```powershell
mix deps.get
mix test
mix wakecanvas.package
```

The generated renderer is intentionally small but implements `mount`, `update`,
`resize`, and `destroy`. Upload its archive through WakeCanvas Management and
restart the host to test it with real instance routing. For a source-linked loop,
use `scripts/dev-experience.ps1`; it compiles the external project and registers it
with the platform without packaging/installing it first.

From the WakeCanvas repository:

```powershell
.\scripts\dev-experience.ps1 -ExperiencePath C:\Repos\sound-garden
```

The command reads `otpApplication` and `entryModule` from the Experience manifest,
runs its optional `assets.build` task, compiles the OTP application, and starts the
normal WakeCanvas development host with the compiled application on its code path.
This uses the same instance routes, configuration, database paths, renderer hook,
and management UI as an installed package. Restart the command after changing
compiled Experience modules or browser assets.
