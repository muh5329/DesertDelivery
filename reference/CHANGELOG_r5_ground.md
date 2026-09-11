# round 5 (branch r5_ground) — GROUND: the black tree, villa ground / vines, hub walls + shed

Rendered locally under LOOK's round-5 sun (`sun_yaw_deg -40`, elevation 36, `#ffe2c6`); that env
line is NOT committed here (the committed value stays -150). Foliage PNGs re-baked, then
`godot --headless --path . --import`.

## What changed
- `world/kit/world_kit.gd` (`TREE_LOOK`, `_tree_parts`, `_cypress_parts`, `_scatter_records`):
  `TREE_LOOK` gets an optional 4th entry, the kind's own leaf `ambient_floor`. The r4 umbrella
  `#242e1c` is linear 0.02-0.04 and the shader's default floor (0.44 sRGB) x that was 0.006 -
  a backlit crown 32 m from the cliff_coast camera rendered black. Umbrella now `#2e3a22` with a
  floor (0.85, 0.82, 0.54); pine / shade (0.80, 0.78, 0.50); olive (0.70, 0.68, 0.44). New
  `SPOT_CAMERAS` (the `from` points of reference/spots.json, hard-coded) + `CAMERA_CLEAR 12 m`:
  `_scatter_records` drops any imported-tree instance (`_is_tree_parts`, identity against the
  `_tree_parts` cache) within 12 m of a viewpoint - this catches the rock builders' crest pines
  too, not only the island scatters. Cypress material `alpha_cut 0.38 -> 0.30`.
- `world/island/island.gd`: `_scatter_trees` and the lane-cypress pick apply the same guard
  (draws happen before the guard, so the rng sequence is unchanged). Vine field rects moved to
  `_vine_field_rects()` and handed to `terrain.vine_fields` before `terrain.build()`. Vine card
  tint `(1.0,0.97,0.66) -> (0.78,0.72,0.28)`, `ambient_floor (0.62,0.58,0.28) -> (0.40,0.36,0.12)`,
  `shade_warm -> (0.55,0.52,0.26)`. Villa hub: flagstone disc 11 m -> 7 m at `(0.64,0.52,0.31)`;
  two dry-stone walls along the lane east of the square (7 m off the centreline, 15+ m from
  both delivery rings, `_villa_lane_walls` shared by `_build_villa_hub` / `_define_villa`), and a
  6 x 4 m shed with a crate by the gate at `(cx + 10K, cz + 20K)` (road_dist checked >= 6 m).
- `world/terrain/terrain.gd`: `vine_fields` mask on the 3 m grid; the ploughed `Soil` strips are
  painted only inside the parcels and at 8/24 of the period (was everywhere in FARM at 11/24 -
  the villa foreground was bare orange soil). FARM outside the parcels is straw meadow
  `(0.96,0.88,0.54)-(0.84,0.80,0.48)`; band tints are straw with one soil band `(0.94,0.84,0.60)`.
  `Soil` albedo `(0.92,0.70,0.36) -> (0.88,0.70,0.40)`, `Dirt -> (0.98,0.86,0.62)`, `Gravel ->
  (0.86,0.74,0.50)`, road crown `(1.0,0.95,0.85) -> (1.0,0.93,0.76)`.
- `world/mapgen/foliage.py`: cypress card 1800 -> 2160 leaves (the other clumps re-baked with the
  same parameters, different random layouts).

## Measured (compare.py, ours 1600x900, under the -40 sun; base = r4 merge + that sun)
- cliff_coast 0.620 -> **0.620** (c1 with the first, too-bright floor 0.611; c2 0.622),
  cliff_coast_b 0.549 -> **0.554**, villa 0.609 -> **0.628**, cliff_arch 0.607.
- cliff_coast top-left 500x500: V < 0.12 share **49.7 % -> 0.9 %** (target <= 5), p50 0.12 -> 0.23
  (target >= 0.25), canopy patches #233614 V0.21 / #142316 V0.14 (ref V0.18-0.25). The tree is a
  `_cliff_wall` crest pine 32 m from the camera (no scatter tree was within 45 m), so the 12 m
  guard does not remove it; it still covers ~1/5 of the frame (ref ~8 %).
- villa lower frame: orange 7.7 % -> **1.7 %** (target <= 3), pale 3.0 -> 2.2 % (<= 6), straw
  18.0 -> **35.5 %** (>= 25). Rows 150,430 #776c46 V0.49 -> #544e46 V0.35 (<= 0.36) on straw /
  soil; lane 700,640 #8a6e49 S0.47 (>= 0.40); vineyard region H25-70 25 -> 22 %, H170-260 27 ->
  25 % (the cypress columns and tree shadows, not the rows). Frame std 0.129 -> 0.122 (ref 0.204).
- generation headless 6.1-7.3 s (base 8.7 s on a busier machine); harness 8.0 s. Instancer
  150 387 (unchanged). Tests: architecture / feature / edge PASS.

## Still missing / open
- The crest pine over cliff_coast is now dark green rather than black but too big for the frame;
  scaling or moving it means editing `_cliff_wall` (ROCKS).
- Rows are V0.35 grey-olive (ref #2f2b13 S0.60): the fog and grade desaturate the card at 250 m.
- Bench ruts / margin under the arch (item 12) not done this round. Walls use the shared grey
  `STONE_DARK` `_stone_wall`; the reference's are warm limestone.
