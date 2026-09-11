# ground branch — Terrain3D ground (textures, control map, colour map)

## What changed
- `world/mapgen/textures.py`: now also packs ambientCG sets (Color x AO^0.6 -> albedo, Displacement -> A;
  NormalGL + Roughness), with per-set desaturation / contrast flattening / gamma lift so the photos read
  painterly. Sets: Rock019 (rock overlay), Rock021 (cliff patches), Ground004 (road dirt), Ground015
  (dry straw grass), Ground024 (stony plateau scrub), Rocks002 (rubble), Gravel009 (shoulders). Sand,
  clay, soil, salt still procedural, retinted (soil is now pale vineyard earth, not dark brown).
  Old Ground037 / Rock023 / dirt files removed; `assets/CREDITS.md` added. assets/terrain = 13 MB.
- `world/terrain/terrain.gd`:
  - `Tex` gains CLIFF, RUBBLE, GRAVEL; `_build_texture_assets` uses the new sets; `albedo_color` is set
    to each texture's brightest use so the RGBA8 colour map only ever darkens.
  - `_build_t3d_maps` rewritten on packed arrays (no per-pixel set_pixel) with:
    - `_fine_road_dist()`: exact 1.5 m distance-to-road-sample field (the 3 m grid smeared the road).
      Road = 4.5 m dirt with a noise-ragged edge, gravel shoulder to ~4.5 m out, courtyard pads keep
      the old grid-distance dirt. Colour map: lighter crown, two darker ruts at 0.5..1.6 m, dusty margin.
    - rock overlay sharper (smoothstep 0.24..0.40 of slope + 5 m edge noise); faces steeper than 0.5
      are rock base with Rock021 slab patches by macro noise; flat cells below steep neighbourhoods get
      rubble (talus).
    - `_grid_field_map()`: neighbourhood mean height (~15 m) and mean slope (~9 m) via trilinear
      shrink; colour map darkens cliff feet (flat + steep neighbours + below mean), gullies (below
      mean) and the ground under the painted canopy (density map) toward #665c57, up to 50 %.
    - palette: meadow dry olive/straw (#8f8f57..#b3a468 on the straw texture), limestone pale bone,
      steep faces cooler grey, farm strips desaturated, sea-cliff faces above the water line get bone
      instead of the turquoise sea tint (was leaking green onto coast cliffs).
  - macro variation: two patch noises (~80 m warm-dark, ~35 m cool-grey), blend_sharpness 0.72.

## Measured
- compare.py cliff_coast: 0.290 -> 0.280 (score is dominated by sky/sea/rock-kit which are not on
  this branch; the visible terrain change there is the cliff face losing its green sea tint).
- compare.py villa vs ref_villa_vineyard: 0.412 -> 0.447 (colour 0.275 -> 0.332).
- t3d_maps loop: 1391 ms -> ~2020 ms (fine road field + two neighbourhood fields + more per-pixel
  work, offset by the packed arrays); world generated 8.7-8.9 s. Tests: architecture / feature / edge PASS.

## Still missing / open
- Ruts are at the 1.5 m colour-map Nyquist limit: they read on the villa shot but alias into a
  darker band with a lighter centre where the road runs off-axis. A real fix needs the ruts in the
  road texture with a directional UV (not available in Terrain3D 1.0.2) or a decal along the roads.
- Per-bush contact halos need the prop positions (island.gd, not this branch); only the painted
  canopy density is used. A `paint_halo()` on the colour map after generation would do it.
- Everything is still lit by the noon sun + no tonemap: the ground reads brighter and whiter than
  the reference until the environment branch lands; albedos were set to the reference's *local*
  colours, not compensated for the current light.
- Ground cover (instancer grass) tints/density untouched (vegetation scope) — still yellow-green cards.

# round 1 (branch r1_ground) — critique items 8, 12 and the GROUND half of 6

## What changed
- `world/terrain/terrain.gd`
  - Texture tints: Scrub (ground024) 1.3 -> (1.08, 0.98, 0.84), Rock/Cliff/Rubble/Gravel warmed toward
    #a08a72, Grass golden (1.10, 1.00, 0.58), Dirt a pale #c9a77a crown. Colour map: limestone
    #e0cc a8 -> (0.88, 0.80, 0.66)..(0.72, 0.66, 0.56), forest/town/farm strips golden-olive, sea-cliff
    "bone" warmed, steep faces no longer pushed blue-grey. Macro variation #c8b9a2 / #7f7a76 at ~50 m.
  - Road: pale crown, ruts (0.58, 0.48, 0.36) at +-0.9 m, and a NEW dark trodden margin (0.50, 0.44, 0.35)
    bleeding 1.5 m past the crown - the margin is what makes the road read at 150 m (villa, view_2).
  - `paint_halos(points, radius, col, strength)`: post-import contact darkening of the Terrain3D colour
    map (edits the region colour images, one `update_maps`) under every scattered tree (r 2.6) and bush
    (r 1.6). The region colour map is 256 px (3 m) so a bush halo is ~1 px; still reads at distance.
  - `plant_ground_cover`: crest cells (flat cell, steep lower neighbour) get +3 dry tufts; SEA-coded
    coast cliffs above 1.2 m allowed for those tufts; limestone tufts 1.0 -> 1.6 / cell; warmer tints.
- `world/island/island.gd` (scatters only)
  - `_slope_break` / `_scatter_slope_breaks`: grid walk, bush on every crest (p 0.55) and ledge foot
    (p 0.30) where a flat sample has a steep neighbour 4.5 m away that is >1.5 m lower / higher. Run
    over the massif + coast (3 m grid) and the rest of the island (4.5 m).
  - Scrub: massif clusters 420 -> 640 (open chance 0.30); NEW dense coast scatter (420 clusters,
    open 0.75, Rect -620..-420 x -350..-120, SEA biome allowed above 1.5 m); world scrub 240 -> 340.
  - Forest: conifers only where painted density > 0.45 (85 %); the rest 55/45 umbrella pines / olives.
    Farm: cypress kept at 22 % near lanes / 4 % elsewhere (was 100 % / 45 %), the freed lane trees become
    round shade trees (TwistedTree "umbrella" 0.5), olives 700 -> 1100.
  - `_halo_trees` / `_halo_bushes` collected from every scatter, painted at the end of `_gen_ground_cover`.
- `world/mapgen/trees.py` + `assets/trees`: the trunk chequerboard was collapsed sliver triangles
  (zero area in space or UV -> NaN tangents -> the bark normal map exploded) and seam vertices
  inheriting a UV from metres up the trunk. Fix: nearest-original UV per decimated vertex, drop
  zero-area triangles, no normal map on the decimated bark, TwistedTree target 2200 -> 3000 tris agg 5.
- `world/mapgen/foliage.py` + `assets/foliage`: every green leans yellow (R >= 1.6 B) so it survives the
  blue fog; pine #344c28-#6f8a4a, scrub #2e3a2c base, olive cards darker (#707c54), base ramp 0.55.
- `assets/trees/leaf.gdshader`: hue jitter only ever warms. `world/kit/world_kit.gd` TREE_LOOK only:
  pine #2c4228/#6a8446, umbrella #2f4a2c/#6f8a4a, olive #4a5a3c/#7e8e5c.
- `reference/spots.json`: `cliff_coast` = the critic's camera (-598, 38, -326 -> -522, 5, -200);
  `plateau` (the old cliff_coast camera, shows the headland ground) and `tree_close` added.

## Measured (compare.py, base -> r1_ground)
- cliff_coast (new camera) 0.520 -> 0.525, cliff_coast_b 0.472 -> 0.489, villa 0.477 -> 0.458 (colour
  0.145 -> 0.136 with the heavy fog; texture-energy 0.69 -> 0.64 because the cypress spires are gone -
  the critic asked for that). By eye (plateau, cliff_coast_b): the chalk mound is warm tan with dark scrub
  thickets, crest bush lines along the lips, dark halos, visible pale roads with dark margins; the villa
  is mixed olives / shade trees / a few cypress on golden ground; the trunk foot is clean at 9 m.
- world generated 7.6 s -> 10.0 s (slope-break walks + halos + more scatter). Tests: architecture /
  feature / edge PASS.

## Still missing / open
- The region colour map is 3 m/px: halos and ruts are at their resolution limit; a decal or a
  1.5 m colour map would do better.
- Roads are lighter than the ground (as in both references, and the critic's #c9a77a) rather than
  "slightly darker"; the darkness is in the margins and ruts. Flip `road_col` if darker is wanted.
- Everything is still judged through the r0 fog/exposure (LOOK lane); the ground values here were set
  to read warm and dark enough under it, they may want +5 % once the exposure drops.
- The villa hub's 9 cypress sentinels (`_build_villa_hub`, hubs - not this lane) are unchanged.

# round 2 (branch r2_ground) — critique items 5, 8, 4-bench, 9 (scatter side), 12 (terrain side)

## What changed
- `assets/trees/leaf.gdshader`: albedo defaults 2x (#4a5a38 / #9aa86a), normal dome 0.45 -> 0.25,
  `shadows_disabled` (the canopy self-shadowed its whole shade side to the blue ambient) and a custom
  `light()`: two-sided half-lambert wrap (`wrap` 0.55) with a warm olive `shade_warm` floor, so the sun
  and not the sky ambient lights the shade side. New `use_tex` / `card_tint` mode: the baked foliage
  cards (bushes, olives, cypress, vines, grass tufts, flowers) now use the same shader via
  `_leaf_material` (world_kit.gd, returns a ShaderMaterial) instead of StandardMaterial3D.
- `world/kit/world_kit.gd`: TREE_LOOK pine #3e5232/#8aa058, umbrella #425a38/#96a860, olive
  #5c6a48/#a4b078. `_pine_parts` (card conifer fallback): two overlapping crossed-card tiers, no flat
  discs (the stacked-plate silhouettes).
- `world/mapgen/foliage.py` + assets/foliage: every clump ~2x brighter (sunlit ~#6f8a4a class), base
  ramp 0.62, `interior` bakes a dark heart (rim 1.0 -> centre 0.5-0.7) so bushes are a lit shell round
  a shadow, not dark all over; broadleaf (vine) card retinted yellow-olive H49; cypress brighter.
- `world/terrain/terrain.gd`: Cliff texture = Rock019 tiled 2.6x finer (uv 0.13) instead of the streaked
  Rock021; steep faces (sl > 0.45) mix coarse/fine limestone 50/50 by macro noise; Rock/Cliff/Rubble
  albedo tints pale (#bfb09a-class); steep colour-map tint toward #c9bfae (0.92,0.88,0.82 at 0.7);
  macro_variation2 #7f7a76 -> #a29e9a (25 %). Talus widened (nsl > 0.18, cav > 0.1, SEA above 0.5 m
  allowed). NEW crest rock lip (flat cell above steep neighbours -> Rock overlay) so crest bushes sit on
  stone. Bench (coast road on SEA/coast-LIMESTONE ground, h 0.3-12, < 12 m of the road): dirt overlay
  to ~10 m, tint toward #b09776, and the cliff-foot/gully darkening is now zero within 3.5 m of any
  road (that darkening is exactly what turned the bench rock-brown). Road crown (1.0,0.95,0.85), margin
  (0.42,0.37,0.29), Dirt tint (1.0,0.93,0.80) -> a #c2ae8c-class road. Vineyard: Soil tint
  (0.78,0.68,0.50), soil strip blend 0.85, farm band 0 = dark earth (0.66,0.56,0.38).
- `world/island/island.gd` (scatters only): `_villa_trees()` — one 16 m TwistedTree shade tree SW of the
  square over the lane, a 12 m one by the office, a 10 m one behind the house, 22 olives in the 26-52 m
  ring the farm scatter keeps clear; private rng so nothing else moves. Forest: conifers only where
  density > 0.6 and never within 160 m of the villa (demoted stands split umbrella/olive by position so
  the r1 rng draws are preserved — a shifted draw put a tree collider in the farm's shooting lane and
  failed feature_tests). Slope-break bushes: crest bushes pushed 1-2 m back from the lip, foot bushes
  into the ledge, sunk 0.3 x scale. Vine card tint warm (1.0,0.94,0.72), field cast milder.

## Measured (compare.py, base b9ef3dd -> r2_ground, same camera / LOOK / ROCKS)
- cliff_coast 0.586 -> 0.586, cliff_coast_b 0.533 -> 0.535, villa 0.565 -> 0.591 (colour 0.299 -> 0.354).
- Canopy patches (cliff_coast): big tree lit #1d3332 H177 -> #315032 H122 V0.31; shade #202d26 H148 ->
  #213226 H138; far tree H192 -> H141; wall bush H106 -> H129. villa: shade tree #2f4144 H189 -> #6a754f
  H77 V0.46, cypress H194 -> H107, olive H148 -> H36, vine rows H136 (r1) -> H28-60 V0.37-0.39.
- cliff_coast_b terrain slope right: #6d605a-class -> #917b6e V0.57 / bench_slope #544f51 -> #88796f V0.53;
  no visible streak stretching (plateau spot: pale bone ground, dark halos, crest scrub on rock).
- world generated 16.5-17.6 s (view) / 15.8-16.9 s (headless tests), base 18.2 s. Tests: architecture /
  feature / edge PASS.

## Still missing / open
- The bench road under the arch (cliff_coast 700-1150 x 380-620, arch_close) lies in the arch's own
  shadow: bench patch stays #736866 (V0.45, ambient-lit). The road/bench are painted pale (visible in the
  lit parts of the spur), but from these cameras the ROCKS arch shades it; needs the arch yaw / sun.
- Canopy V is at the low end of the target (lit 0.31-0.46, shade 0.20-0.24): a warmer `ambient_color`
  (LOOK) would lift the shade side without more albedo.
- Slope bushes still float where the 1.5 m Terrain3D mesh differs from the 3 m grid `_ground`.
- Vineyard field cast varies H28-60; the vine rows read a little orange at the left of the villa frame.
