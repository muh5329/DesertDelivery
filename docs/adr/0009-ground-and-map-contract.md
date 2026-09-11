# 0009 — Two named ground queries, and a checked map contract

**Status:** accepted · September 2026

## Context

`Terrain.height_at` silently changed meaning halfway through generation. `_t3d_data` is assigned
deep inside `_build_terrain3d()`, which `build()` calls last, so every Road, ramp and Pad was cut
against the 3 m bilinear field and every prop was placed against Terrain3D's 1.5 m resample. They
agreed only because of a per-pixel clamp and a road mask, both invisible from the caller's side.

Separately, the Map contract — grid, cell size, height encoding, biome order — was restated by
hand in `extract.py`, `expand.py` and `terrain.gd`, and nothing checked it. The only enforcement
was an image-width check that degraded to a flat sea behind one `push_error`, and it fired for
real: `extract.py` wrote its 241 px result straight to the 417 px runtime path, so running stage
one on its own produced a world of open water.

## Decision

Two named questions. `heightfield_at(x, z)` is the 3 m field the build cuts and every build stage
asks; `height_at(x, z)` is the ground as drawn and collided. `heightfield_drift()` measures how far
apart they are, and a test holds it down.

`expand.py` writes `data/island_map.json` describing what the map claims to be, and
`Terrain.map_contract_error()` validates it field by field with a named mismatch.
`extract.py` writes `world/mapgen/island_map_720.png` — its actual product — so the two stages
cannot be run out of order into a broken world.

Also recorded here: `Bridge` answers `deck_span(ground)` for the deck the courier really rides,
ramps included. That rule (0.25 m rise, 80 samples, 3 of margin) was copied into the aqueduct
builder and the pedestrian router. And the terrain no longer knows where the Town Square is —
the Island hands it `keep_clear` regions.

## Consequences

- Running the mapgen out of order fails loudly instead of producing a flat sea.
- Python and GDScript still restate the constants; that duplication is inherent without a
  generator step. The *check* is the part that earns its keep, not the unification.

## Reopen if

The map gains a fourth channel or the pipeline gains a stage. Extend the sidecar; do not add a
second undeclared convention.
