# round 3 (branch r3_ground) — GROUND: canopies, vineyards, villa court, generation time

## What changed
- `assets/trees/leaf.gdshader` (trees + every baked foliage card):
  - `render_mode ambient_light_disabled` + `EMISSION = ALBEDO * ambient_floor` (#6f6b38-class linear
    0.44/0.42/0.22): the environment's blue sky ambient was the teal on the sky-facing edges; the
    canopy now gets a flat olive floor of its own. Sun wrap 0.55 -> 0.5, shade floor
    `shade_warm` (0.62,0.56,0.38 brown) -> (0.56,0.62,0.38 olive), shade mix 0.35 -> 0.55.
  - mip-biased coverage: `ALPHA = a * (1 + mip * 0.45)` (mip from `dFdx/dFdy(UV) * textureSize`)
    and `alpha_cut` 0.45 -> 0.3 on the cards: a 4x minified card stays an opaque silhouette instead
    of the 1-px confetti round the scissor threshold.
  - defaults `col_lit` #9aa86a -> #86a444, `col_dark` #4a5a38 -> #3a4a28.
- `world/kit/world_kit.gd` (TREE_LOOK / `_leaf_material` only): pine #32452a/#6a8a3c, umbrella
  #3a4a28/#86a444, olive #52613e/#94a85c. NOTE: a true-green albedo (H95) rendered teal H170 — the
  blue fog + the grade's blue black-lift pull every canopy ~30 deg toward cyan, so the albedos are
  yellow-olive (H 75-80) and land on the reference's green after the grade.
- `world/mapgen/foliage.py` + `assets/foliage/*_clump.png`: every clump darker and more saturated
  (pine #546830-class, scrub #64783a), baked interior 0.5-0.7 -> **0.35-0.45** of the rim (ref bush
  core #31341a). Vine card (`broadleaf_clump`) yellow-olive H50 -> mid-green H78 (#707e36 / #5e6a2e).
- `world/island/island.gd` (scatters / hub dressing):
  - vines: card tint (1.0,0.94,0.72) -> (0.95,1.0,0.78), the per-field cast (1.15,1.08,0.72) orange
    -> (0.86,0.94,0.70) a lighter/darker green only: the rows are one hue on dark soil.
  - `_scatter_slope_lists` replaces `_scatter_slope_breaks` (+ `_slope_break`, `HALO_STEPS`): the
    crest / ledge bush lines are drawn from `Terrain.crest_cells` / `foot_cells` (every other 1.5 m
    map pixel that the control map already classified as crest lip / talus foot; subsampled 1 in 2
    on the massif, 1 in 4 elsewhere, same p / scale / push-uphill / sink as before). 570 bushes
    before, ~520 now; the two grid walks (2.2 s) are gone.
  - halos: tree 2.6 m x 0.45 -> 1.8 m x 0.25, bush 1.6 x 0.5 -> 1.4 x 0.3, colour (0.44,0.40,0.28)
    -> #6b5947 warm humus.
  - villa court: `_flagstones` tint (0.64,0.60,0.52) pale concrete -> (0.58,0.50,0.38) packed
    earth/gravel (the disc was the brightest surface in the frame; the pole is the delivery beacon
    `gameplay/delivery/delivery_system.gd`, not hub geometry — see open issues).
  - mountain-house scatter clearance 34 -> 48 m from locations: the rng shift of the slope-list
    rewrite put a house in the hilltop farm's shooting lane (feature test "pops the aimed tin can").
- `world/terrain/terrain.gd`:
  - `crest_cells` / `foot_cells` gathered in `_build_t3d_maps` (crest: `sl < 0.3, nsl > 0.22,
    cav < -0.6`; foot: `nsl > 0.2, cav > 0.5`; both `h > 1.2`, `rd > 4`, every other pixel): 1870 /
    2348 cells, ~0 ms.
  - open-sea fast path in `_build_t3d_maps`: SEA pixels with all four grid corners < -1.2 m and no
    road within 8 m write sand + depth tint and skip the slope / road / shading work (~30 % of
    the land rows).
  - `plant_ground_cover`: 15 m patch mask (`FastNoiseLite.get_image(N,N)`, threshold
    `COVER_MASK_THR` 126 ≈ 55 % of cells, thinned to 0.55 at the patch edge), relaxed 34 levels in
    a 220 m square round the `COVER_HERO` spots (coast bench, villa); crest tufts never masked.
    316 792 -> 150 299 instances (47 %).
  - painted-canopy darkening 0.28 -> 0.14, the whole ground darkening capped 0.5 -> 0.4 and its
    colour (0.40,0.36,0.34) -> (0.44,0.38,0.32) warm; `paint_halos` scales the halo by how far the
    pixel still is above the halo colour (the sum of halo + canopy darkening no longer stacks).
  - vineyard: Soil tint (0.78,0.68,0.50) grey-brown -> (0.82,0.68,0.44) warm; farm band 0
    (0.66,0.56,0.38) -> (0.70,0.58,0.36).
  - steep faces: `enable_projection` on with `projection_threshold` 0.85 (textures projected along
    the face), the CLIFF/ROCK patch blend uses the 80 m macro noise only (+0.1 of the 5 m edge
    noise) and the slope tint is 90 % flat: per-texel variation stretched into vertical streaks.
  - road / bench colours untouched (crown (1.0,0.95,0.85), bench (0.90,0.80,0.64): the coast bench
    road stays pale).

## Measured (compare.py, same LOOK / ROCKS, base 21f679b -> r3_ground)
- final: cliff_coast 0.585 -> **0.595** (colour 0.445 -> 0.469), cliff_coast_b 0.535 -> **0.545**,
  villa 0.566 -> **0.562** (colour 0.299 -> 0.306). Across the cycles: 0.592-0.603 / 0.540-0.550 /
  0.555-0.565 — the villa score trades the pale disc + lime canopies for green rows on darker soil.
- cliff_coast big tree: lit crown #4b6641 H104 S0.36 -> #3c5b36-#485b36 H91-110 S0.41 (97 % of the
  crown pixels H70-140, teal 2 %); shade side #284839 H152 -> #203935 H170 V0.22 (the reference's
  own coast shade trees are #263030 H180 — the far side is fog-lit). Canopy interiors are the
  darkest 1 % of the frame with the rock contacts.
- villa shade tree (780-900 x 540-720) #6d6a4d H54 S0.29 -> #65663b H61 S0.42 V0.40, p10 0.31 ->
  0.25; orange pixels in the vineyard region 10 % -> 6-9 %, teal 23 % -> 29 % (the shade side of
  the rows and the lane shadows; the rows themselves read green on red-brown soil).
- generation: harness `[game] world generated` **20 160 ms -> 12 591 ms** (13 300-13 500 in the
  earlier cycles); headless tests 17.6 s -> 12.0-12.8 s. `[terrain] build stages` (harness):
  heightfield 2537 -> 2536, t3d_setup 1441 -> 858, t3d_maps 3462 -> 2848, t3d_import 178 -> 142,
  ground_cover 5191 -> 1337 (316 792 -> 150 299 instances), slope-break walks ~2240 -> ~0.
- Tests: architecture / feature / edge PASS.

## Still missing / open
- The 60 m "pole" through the villa is the delivery beacon (`delivery_system.gd`, a 0.16-alpha
  cylinder): not GROUND's; the gravel court / dry-stone walls / shed / pergola of item 10 need the
  hub builder.
- Near trees (no fog) read yellow-olive H55-65 while trees 100 m out read green H90-110: the
  albedo is tuned for the graded, fogged mid-distance. A distance-aware hue (fog factor in the
  leaf shader) would fix both ends.
- Steep faces (`cliff_coast_b` 650-950 x 420-650): the fine vertical streaks are unchanged by
  the flat slope tint, the macro-only patch blend AND `enable_projection` (cycle-6 crop identical
  to cycle 5, region #ae978c p10 0.46 as before): they are not the colour map and not the planar
  uv. The lower two thirds of that crop is a ROCKS `_cliff_wall` veneer with ledges; the streaks
  run through it too, so the rock shader / its texture at 150 m is the next suspect (ROCKS).
- Vineyard region mean S stays ~0.25 (shadow + shade sides); the critique's S >= 0.35 needs the
  LOOK grade or a lighter sun angle on the rows.
- Crest pines "far tint x 0.7" (item 6) not done.
