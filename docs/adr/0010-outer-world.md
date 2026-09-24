# 0010 — The outer world is generated offline and answered by one lattice

**Status:** accepted · September 2026

## Context

Outside the hand-built 1248 m core, the 25 km world was a 62.5 m noise heightfield drawn as one
static mesh, collided with 62.5 m triangles, dressed with sphere trees and crossed by one straight
viaduct. The brief asked for five towns, a 150-250 km road and sea network and real landforms,
while boot stays under ~20 s and nothing costs O(world) per frame.

Towns, routed roads with grade-limited profiles, cut/fill, bridges, sea lanes and eroded terrain
are far too slow for GDScript at boot, and whatever draws the ground, collides it and answers
`height_at` must agree to centimetres or the bike floats and roads sink.

## Decision

**Offline generator, data in `data/outer`.** `world/mapgen/outer.py` (numpy/scipy/numba) builds
the landforms (domain-warped fBm, ridged mountains, particle + thermal erosion, the estuary, the
strait, the lake), lays out the towns and hamlets (streets, then plots along them), routes every
road with A* on a 25 m grid, smooths and resamples it every 4 m, solves a grade-limited profile
(Lipschitz envelopes with pinned junctions and deck clearances), finds bridges, carves the
corridors, routes the sea lanes, paints the material maps and writes `plan.json`. The runtime only
loads: `FileAccess.get_buffer` for the heights, PNG decodes for the maps, one JSON parse (~0.8 s).

**One surface definition.** The ground is triangles on a 6.25 m lattice: each lattice point is the
bilinear data height plus micro relief x (1 - flatten), each cell split on the same diagonal. The
CDLOD vertex shader, the streamed ConcavePolygon collision tiles, `OuterGround.height_at` and the
generator's `surface_at` all evaluate exactly that, so plot pads and road samples are written at
the height the runtime will report, and physics rays match `height_at` to < 1 mm.

**Roads join the existing graph.** Every plan road is appended to `Terrain.road_samples` /
`roads` / `bridges`; a branch starts exactly on a parent sample whose index is a multiple of 3 (or
its last), so `RoadNavigation`'s 3.8 m junction rule links it. Town main streets are roads from the
ring's gate sample to the plaza, so the delivery rings on the plazas are reachable.

**Towns are recipes.** Plots are the contract with the architecture kit (`BuildingKit.build_group`
when it exists, a placeholder otherwise), filed per 60 m chunk in groups of six with a declared
extent (ADR 0007). A resident silhouette per chunk hides while that chunk is loaded.

## Consequences

- Changing the world means re-running `outer.py` (~1 min; stages are cached in `/tmp/outer_cache`).
- The core exits are core roads (`Island._define_roads`, appended last); the generator reads their
  final samples from `world/mapgen/core_exits.json` (`tests/dump_core_exits.gd`). Adding them
  re-rolled the core's scatter, which put the Harbour lamp post on the Harbour Cafe ring; the lamp
  moved.
- 12.5 m data cannot hold a 1 m kerb: plot pads are flat to within the lattice (plots carry
  `ground_min` for a plinth), road beds are flattened 7 m either side of the carriageway.
- Python and GDScript both restate the lattice rule; `outer_world_tests` checks they agree.

## Reopen if

The world needs editing by hand (a painter's tool over `data/outer`), streaming of the height data
itself (a bigger world), or finer road beds than 12.5 m can carry.
