# Collective Form creature system

This directory is an Experience-owned browser subsystem. Display variants may
opt into it without adding creature rendering to the WakeCanvas Platform or SDK.

`svg-creatures.js` owns the creature catalog, SVG parsing, interior sampling,
feature landmarks, lightweight rig regions, mycelium body construction, masks,
and animation. A variant remains responsible for reveal timing, selection, text,
and transitions into or out of the normal Collective Form composition.

Creature assets live under `assets/svg/creatures/` and are bundled by esbuild.
They do not require network access or a Node.js runtime on the kiosk.
