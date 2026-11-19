# Pareidolia interpretation contract

The `growing-mycelium-pareidolia` variant reveals recognizable forms that an
interpreter finds in real Collective Form connections. Interpretation is
offline-first and provider-neutral.

## Development workflow

1. Select **Growing Mycelium — Pareidolia** for the instance.
2. Open **Table Console** and select **Prepare current network**.
3. The Experience writes these files below the instance data directory:
   `pareidolia/request.json`, `pareidolia/candidate-sheet.svg`, and
   `pareidolia/response.example.json`. Medium and large networks add numbered
   candidate sheets; `request.json` lists every sheet in order.
4. Ask Codex to interpret the latest Pareidolia request. Codex inspects the
   candidate sheet and writes `pareidolia/response.json` using the example's
   schema.
5. The display validates the analysis ID, network fingerprint, candidate IDs,
   titles, confidence values, and optional normalized contour strokes. It then
   cycles through the accepted forms, retaining real-route highlights while a
   contour makes the reading visually recognizable.

Preparing the network again replaces the request and removes the old response,
so a stale interpretation cannot be presented as if it belonged to new data.

## Provider boundary

A future local model or optional external provider should read the same request
and produce the same response. Provider-specific code must stay outside the
renderer. The renderer only receives validated interpretations and the
persisted geometry captured with the request.

Each interpretation may include up to eight `contours`. A contour contains a
`closed` boolean and 2–64 `[x, y]` points normalized to the projection surface.
Coordinates are validated to the inclusive `0..1` range. This bounded geometry
keeps provider output deterministic and inexpensive for PixiJS to animate.

Candidate discovery samples seed connections across the full projection area,
then grows connected subgraphs using local, branching, and long-reaching modes
at several scales. A Jaccard-overlap filter removes near-duplicates. Candidate
and interpretation limits scale from 16/4 for a small network to 64/12 for a
large network, while each SVG sheet remains capped at 16 candidates.
