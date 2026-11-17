# Collective Form

An offline-first participatory spatial Experience. Visitors add physical forms and
the projection turns their individual contributions into one evolving composition.

The first display variant is **Growing Mycelium**. An operator initially places and
moves contributions on a virtual table. A future camera adapter will feed the same
accepted table-state model, so display variants do not depend on how positions were
observed.

The optional **Growing Mycelium — Creature Reveals** variant shares the same
accepted table state and renderer core. It periodically performs reversible animal
transformations without changing the stored network. A future local-AI service can
replace its deterministic creature selection; the original variant remains
available without reveals.

Creature SVGs, feature landmarks, lightweight rigs, and reusable animation logic
belong to the Collective Form Experience under `assets/js/creatures/` and
`assets/svg/creatures/`. Variants opt into that Experience-level subsystem; the
Platform and Experience SDK do not own or serve a shared creature runtime.

## Operator model

- **Placement source — Operator placement:** the operator adds, positions, moves,
  and removes contributions on the Table Console.
- **Placement source — Camera detection:** the console monitors detected objects
  and provides calibration, pause, rejection, correction, and position-lock tools.
- The artwork renders the accepted installation state, never an unfiltered camera
  frame. Temporary hands, shadows, and unstable detections therefore cannot
  immediately damage the composition.

Photographs are optional. Position, approximate size, and optional colour are
enough for the table projection; photographs can later support the wall display
and cycle archive.

## Development

```powershell
mix deps.get
mix test
mix wakecanvas.package
```

Upload the resulting archive from `_build/wakecanvas/` in WakeCanvas Management,
then restart the platform. Replace the path-based SDK dependency with your chosen
Git or Hex source before sharing this project with another developer.
