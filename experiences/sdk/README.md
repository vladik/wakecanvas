# WakeCanvas Experience SDK

This independent Mix project defines the stable contracts shared by the WakeCanvas
platform and installable Experience OTP applications.

It also defines the instance context passed when the platform activates one
operator-configured instance. Packages are reusable; instance configuration,
SQLite, and media paths are isolated.

It intentionally contains no platform implementation. The contract includes
declarative Experience definitions, configuration validation, runtime lifecycle
callbacks, the optional renderer diagnostics service, and deterministic package
creation.

From an Experience project that depends on this SDK, build production assets and
then create its archive:

```text
mix assets.deploy
mix wakecanvas.package
```

`mix wakecanvas.package` reads `wakecanvas-experience.json`, packages the compiled
application from `Mix.Project.app_path/0`, writes a complete `CHECKSUMS` file, and
emits a deterministic `.wakecanvas` ZIP under `_build/wakecanvas/`. Use `--manifest`
or `--output` to override those paths. Jason is a build-time dependency of this
command; it is not required as a separate production service or Node.js runtime.

Generate a standalone project from the SDK directory:

```powershell
mix wakecanvas.new C:\Repos\my-experience `
  --module ArtistStudio.SoundGarden `
  --app sound_garden `
  --id com.artiststudio.experience.sound-garden `
  --name "Sound Garden"
```

The generator refuses to overwrite a non-empty directory and creates an independent
Mix application with a manifest, OTP application, LiveView display, scoped CSS,
separately loaded ESM renderer, contract test, and package command. Its generated
display forwards the platform hook's bounded heartbeat through
`RendererDiagnosticsAPI`. Its generated SDK dependency initially points at this
local SDK checkout; replace it with the
published Git or Hex source when distributing the project.
