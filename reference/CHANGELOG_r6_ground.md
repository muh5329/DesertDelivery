# round 6 (branch r6_ground) — GROUND: crest pine off the cliff_coast frame, villa lane / walls, vine far tint

Rendered locally on the r5 merge (no LOOK / ROCKS r6 changes present); base numbers are the r5
merged renders in /root/rounds/r5 (the critique's own). No PNGs edited, no import needed.

## What changed
- `world/kit/world_kit.gd` (item 9): `CAMERA_CLEAR` stays 12 m, but the two cliff cameras
  (`SPOT_CAMERAS` 0 and 2 = cliff_coast, cliff_arch) clear `CAMERA_CLEAR_WIDE 36 m` via
  `WIDE_CAMERAS`; `_near_camera` picks the radius per camera, callers unchanged (draws happen
  before the guard, rng order preserved). A plain 36 m everywhere was tried first (cycle 1): it
  stripped the villa's foreground olives / cypresses and their shadows, villa 0.637 -> 0.615, so
  the wide radius is per-camera. `_stone_wall` takes an optional material.
- `world/island/island.gd` (items 6, 7): the villa lane walls (`_villa_lane_walls`) are built in
  the talus rock material `rock_material("rock024", Color(0.38, 0.32, 0.16), 0, 0.8, 0, true)`
  instead of the flat `STONE_DARK` box - dark dry-stone with grain (ref walls #1f221b-#726a29).
  Vine material: `far_tint (0.62,0.60,0.40)`, `far_start 150`, `far_end 400` (warmer, not the
  pines' cool haze). The critique's darker `card_tint (0.66,0.64,0.22)` was tried and reverted.
- `world/terrain/terrain.gd` (items 7, 11): `rut_col (0.62,0.52,0.40) -> (0.82,0.68,0.44)`,
  `margin_col (0.42,0.37,0.29) -> (0.62,0.52,0.32)`, `bench_col (0.90,0.80,0.64) -> (0.88,0.82,0.62)`.

## Measured (compare.py, 1600x900; r5 merge -> final)
- cliff_coast 0.637 -> **0.653** (cycle 1 0.646, cycle 2 0.653), cliff_coast_b 0.520 -> 0.520,
  cliff_arch 0.614 -> 0.613, villa 0.637 -> 0.635 (cycle 2, dark card) -> **0.638** (final).
- cliff_coast top-left 600x560 green (H60-160 S>0.25) **49.1 % -> 6.8 %** (target <= 15), frame
  green 12.1 % -> 2.3 %; the hero-wall crest is visible. Bench 850,510 #9c8273 H22 (target
  H32-48: not reached - the bench hue is set by the sand / rock fill and the ambient, not the
  paint colour; bench region p10 V 0.33 unchanged).
- villa lane: the ground-level `--close` view shows the lane as pale dry dirt between two dark
  grained walls; from the judged camera the lane strip (600-1400 x 400-700, H20-45 S>0.3 V>0.5)
  49 % of the region at median V0.58 (r5 46.5 %, V0.58) - the 3 m paint grid moves little at
  that distance. Walls 1300,600 #856651 -> dark olive-brown, visible grain in the crop.
- Vine rows: no measurable change either way. Left field (0-500 x 300-420) green share 15.4 % ->
  14.0 %, teal (H170-260) 35.7 -> 41.5 % with the darker card, back to the r5 level with the r5
  card. At 120-320 m the fog and the blue ambient set the row colour (item 7's `ambient_color`
  request to LOOK is where the teal comes from); the olive-dark bin (H40-90 S>0.4 V<0.35) stays
  ~0 in the vineyard region (ref 0.8 % there, 15 % in the lower frame).
- generation headless 10.2-11.4 s, under xvfb 11.0-17.3 s (the 17 s run was on a contended
  machine); tree 24 077 nodes. Tests: architecture / feature / edge PASS. No prop placement
  changed (walls unchanged in position, 7 m off the lane, 15 m from the rings).

## Still missing / open
- Rows olive-dark: needs the ambient / fog change (LOOK), not a leaf-material change.
- Bench hue under the arch stays H20-25 pink-brown: the tint of `bench_col` is not what the eye
  sees there (rock sand fill + shade); a ROCKS `sand_color` warm move (item 10) is the lever.
- Lane brightness from the villa camera is set by the crown (`road_col`), which the critique
  keeps; the rut / margin lift shows at ground level, hardly from 34 m up.
