# round 4 (branch r4_ground) — GROUND: crest trees, canopy silhouettes, vineyard, cliff-top straw

Rendered locally under LOOK's proposed sun (`sun_yaw -150`, `elevation 36`, `sun_color #ffe2c6`,
`ambient #a3a6b2` 0.4 / sky 0.4) — those env lines are NOT committed here. NOTE for anyone
re-rendering: the game does not re-import changed PNGs; run `godot --headless --path . --import`
after `foliage.py` / `leaf_erode.py` (cycles 1-2 of this round rendered stale textures).

## What changed
- `assets/trees/leaf.gdshader`: mip-bias `ALPHA = a * (1 + mip * 0.45)` -> `0.2`, `alpha_cut`
  0.3 -> 0.38 (default and `_leaf_material`). New distance tint: `far_tint (0.64,0.70,0.72)`
  blended in over `far_start 100` -> `far_end 220` m of view distance (the r3 "far tint" item).
- `world/mapgen/leaf_erode.py` (new) + `assets/trees/Leaves_TwistedTree_C.png` / `Leaf_Pine_C.png`:
  the pack's smooth lobe atlases get a ragged 2-22 px rim and 3-8 px holes (coverage 0.29 -> 0.18 /
  0.24). Untouched sources in `world/mapgen/leafsrc/` (`.gdignore`).
- `world/mapgen/foliage.py`: `clump(gap=1.0)` clears a 1 px rim round every second leaf (olive,
  scrub, broadleaf: 1-2 px gaps between lobes, coverage 0.66 -> 0.59); scrub card x0.8; cypress
  card #3a4a1e-class (was #52622a) ; vine card (`broadleaf_clump`) yellow-olive H60 and brighter
  (interior 0.7): at 250 m a V0.3 row took half its colour from the fog and went teal whatever its
  hue.
- `world/kit/world_kit.gd` (`TREE_LOOK`, `_leaf_material`, `_cypress_parts` material only):
  `pine` x0.75 (#50682d); `umbrella` is now the dark coast palette #242e1c / #5c7234 (used by the
  limestone scatter, the islets, and the rock builders' crest / arch-crown pines — those call
  sites were not edited); new `shade` #3a4a28 / #7c9540 for the villa and lane trees (the r3
  umbrella at #86a444 was S 0.71); `olive` x0.85. Cypress material gets a warm `ambient_floor`.
- `world/island/island.gd`: `_umbrella_variants(scale, kind = "shade")`; coast crest trees halved
  (position hash in the sea-cliff rect, rng sequence untouched); coast thicket bushes -35 % and
  coast crest-line bushes -40 % with a `(0.74,0.68,0.58)` cast; vines: along-row card 2.3 -> 2.8 m
  (a hedge on the 2.4 m pitch), tint `(1.0,0.97,0.66)`, `shade_warm (0.70,0.66,0.32)`, `wrap 0.8`,
  `ambient_floor (0.62,0.58,0.28)`, and the rows cast no shadows (they shaded the whole strip into
  the blue ambient); halos `#6b5947 x0.25/0.3` -> `(0.36,0.33,0.22) x0.2/0.22`.
- `world/terrain/terrain.gd`: sea-cliff tops (SEA biome above 1.5 m, and LIMESTONE in the coast
  rect) get the `Grass` (straw) base on flat cells with a `(0.90,0.78,0.58)-(0.76,0.66,0.48)` tint
  fading out above slope 0.28-0.42; SEA cover 0 -> 1.2 dry tufts per cell (+88 instances: the 3 m
  map has few flat SEA cells above 1.2 m); canopy/foot darkening cap 0.4 -> 0.3 toward an olive
  humus `(0.42,0.38,0.26)`; vineyard soil strip 6/24 -> 11/24 of the period, `Soil` albedo
  `(0.92,0.70,0.36)`, farm bands 0/1 brown-straw.
- `gameplay/delivery/delivery_system.gd`: the 50 m x 0.7 m beacon beam -> a 14 m tapering post,
  alpha 0.16 -> 0.12 (ring + package icon unchanged).

## Measured (compare.py; ours 1600x900)
- Under LOOK's proposed sun, base (r3 merge + that sun) -> final: cliff_coast 0.602 -> **0.605**,
  cliff_coast_b 0.562 -> **0.564**, villa 0.593 -> **0.600**. Under the committed r3 sun vs
  `/root/rounds/r3`: 0.590 -> 0.586, 0.576 -> 0.571, 0.579 -> **0.591**.
- cliff_coast: big-tree region (0-500 x 0-500) p10 0.18 -> 0.12, edge energy 0.065 -> 0.068 (ref
  0.069); treeline band (500-950 x 130-270, sky included) med #527353 -> #304b54, p50 0.45 -> 0.34;
  cliff-top band 30-50 H share stays ~0 % (that band is the ROCKS arch crown, not terrain).
- villa: vineyard rows now H25-70 16 % (was 8 %), rows read yellow-olive hedges; H170-260 in the
  vineyard region 31 -> 36 % — the mask shows it is the cypress columns and the trees' cast
  shadows on the ground (blue ambient), not the rows; ground region H340-360 5 -> 6 %, H0-25 32 ->
  46 % (soil strips are warmer, the maroon halo is gone).
- generation: headless `[game] world generated` **7.7 s** (base 7.7 s on the same quiet machine);
  harness 8.0-8.4 s. Instancer 150 299 -> 150 387. Tests: architecture / feature / edge PASS.

## Still missing / open
- Cast shadows on the villa ground and under the rows are still navy: that is the ambient / fog
  colour (LOOK); GROUND can only warm the albedo under them.
- Straw ground shows on the terrain cliff tops left of the arch; the arch / wall crowns are rock
  pieces with the rock builders' own scrub + `umbrella` pines (now dark) and no ground layer.
- Bench ruts / margin (item 13), villa walls / shed (item 9) not done.
- Under the r3 sun the darker coast trees cost ~0.005 on the two coast spots; tuned for -150.
