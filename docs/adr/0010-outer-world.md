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

## Addendum — the polish pass (September 2026)

- `outer_water.py` runs after the terrain stage (cached as `landscape`): priority-flood drainage,
  rivers (the biggest channels on the green land, carved; their level is monotone downstream and a
  run is split where an embankment or a town pad buries it), wadis and the Rambla (dry beds), the
  erg (a basin raised into transverse dunes) and the oases. Roads treat river cells as water to
  cross and bridge them (deck 3.4 m over the level); the road carve's blend is undone in the channel.
  At runtime `OuterRivers` is built before the flora and stamps a 4 m cell mask of the channels
  (`in_channel`) so no tree or grass card stands in the water.
- Profiles are biased to cuts (`CUT_BIAS`), and fills up to 14-15 m are embankments, so land
  viaducts only remain where a valley really needs one; mountain roads into Valdoro and the dam
  road have their own grade limits (`ROAD_GMAX`). The north spoke joins the ring below Valdoro, the
  causeway leaves the ring at the head of the valley down to the strait, the west-coast road that
  ended in the sea is gone.
- Town dressing and quays are data (`props`, `terraces`, dredged berths in front of `quay_edges`),
  placed with the plots and streets in hand so nothing lands on a building or a navigation road.
- New data: `feat.png` (+1.8 MB), `rivers` / `estuary` / town `props` / `terraces` in plan.json;
  data/outer stays ~23 MB.

## Addendum — the review fixes (September 2026, branch `fixworld`)

- **Profiles and the carve agree (C-1, M-6, M-9).** `stage_carve` runs the carve and a profile
  refit in turns (`RELAX_PASSES`): after each carve every road's profile is refitted, within its
  grade limit, to the surface the 12.5 m grid now holds, so where two roads (a junction, a crossing,
  a parallel pair, the legs of a hairpin) ask the grid for different heights they converge on one.
  The exact zone of the carve is `CARVE_EXACT` = 9 m past the carriageway (the runtime surface mixes
  data nodes up to ~18 m away). Paths are kept apart where they double back (`separate_legs`: the
  legs of a switchback at least width + 26 m apart; `remove_cusps`: no spur where a route overshot
  its lead-in); roads are routed between their lead-in points. The west spoke joins the ring north of
  the Isola junction and the causeway leaves the ring where it turns away from the strait, instead
  of four highways running side by side into one point.
- **Bridge ends (C-1).** The ground under a deck is cut `BRIDGE_CLEAR` below it only past
  `BRIDGE_ABUT` from the abutments, ramping in at `BRIDGE_RAMP` / m, and only in cells nearer the deck
  than any carved road; the old 3 x 3-cell cut dug the approach samples 4 m down (a cliff at every
  bridge end). River bridges start `RIVER_ABUT` = 14 m back from the banks and the river recut never
  lowers a road's own bed.
- **Towns keep off the roads (C-3).** Routing treats every plot (+14 m), every town wall and the
  walled precinct as off limits (`set_hard_forbid`, only the gates stay open);
  `clear_plots_off_roads` drops whatever still reaches into a navigation road's ribbon (carriageway +
  shoulder + 1 m; a town street + 0.25 m). Hamlet lanes are laid out as wide as their road's ribbon.
  Town walls (`wall_line`) open where a street crosses them, flanked by two bastions: the kit's
  arched gate is 4.4 m wide, too narrow for an 8-12 m street. `outer_world_tests` checks every plot
  and prop of every town and hamlet against every navigation road.
- **Valdoro (m-17).** Its main street is one long diagonal leg per terrace joined by filleted
  hairpins (`fillet_path`, r <= 13 m) with a 2.2 m margin and an open turning place round each bend.
- **Sarmada (M-10).** Floors by quarter (3-4 round the souk, 1-2 by the walls), set-backs, minarets,
  sabats (the kit's gate over a derb) — plot data only; the kit is unchanged.
- **Core seams (C-4).** While the outer world is up, Island skips the core exits' stone arcades
  and `OuterRoads._core_seams` builds the spoke's concrete deck back over the core exit's bridge,
  its width growing from 6.5 m at the core bridgehead to the highway's; the core exit stays the
  navigation road.
- **Inland water (M-5).** `Terrain.water_level_at(x, z)` answers the sea level, the lake's level
  inside its shore polygon, a river's level inside its channel (OuterRivers' 4 m cell index keeps the
  level); `Terrain.vehicle_submerged(p)` is the vehicles' splash rule (the sea as before; inland
  water deeper than `FORD_DEPTH` = 0.8 m). Swimming, the bike, the truck and the plane, and the
  respawn "dry" check use them.
