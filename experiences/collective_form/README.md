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

The optional **Growing Mycelium — Pareidolia** variant asks an interpreter to
find recognizable forms in bounded subsets of the real network. Its request,
candidate sheet, and validated response stay below the instance data directory.
Development can use a manual Codex interpretation; a future local service uses
the same provider-neutral contract. See `docs/pareidolia.md`.

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

## Startup maintenance

Before its first evolution tick, an active instance checks its own SQLite data.
When retired history exceeds 2,000 rows or live database pages exceed 25 MB, it
keeps the newest retired route per node pair and removes older duplicates. It also
retains the 10 newest completed cycles. Active routes, contributions, and the
current cycle are never removed. SQLite reuses freed pages; startup maintenance
does not run `VACUUM` or interrupt a running workshop.

## Development

```powershell
mix deps.get
mix test
mix wakecanvas.package
```

Upload the resulting archive from `_build/wakecanvas/` in WakeCanvas Management,
then restart the platform. Replace the path-based SDK dependency with your chosen
Git or Hex source before sharing this project with another developer.
