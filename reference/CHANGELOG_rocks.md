# rocks branch — round 3 (r3_rocks): the normals were inside out; sky-lit tops, hero wall ends, one-mass islets

Fixes ROUND3_CRITIQUE items 1 (shader half), 2 (tint half), 3, 4 (islet half), 5 (rock half), 9 (scree),
10 (outcrops) and the `_near_road` generation-time cut. Renders: `/tmp/r3_rocks/v8/{cliff_coast,
cliff_coast_b,cliff_arch,islet_far}.png` (`/tmp/r3_rocks/base/` = this worktree before the changes).

## The bug
- `RockGen._build` computed every face normal as `(p1 - p0) x (p2 - p0)`. Godot winds front faces
  clockwise seen from outside, so that vector points INTO the piece: **every stored normal on every
  rock was inverted** (verified with a dump: a boulder's top vertex had normal (0, -0.998, 0.06), a
  `BoxMesh` disagrees with the same cross product on all 12 triangles). Consequences, all of which the
  critiques had been describing since r0: faces turned toward the sun got no sun and faces turned
  away got it (the "lit slivers" of r2 were the faces looking away from the sun), tops lit as
  undersides (ambient only, fracture-tinted, shadow-biased into acne), the concavity AO darkened
  the bumps instead of the hollows, moss grew on the undersides, and `ao_d` (less sky for overhangs)
  darkened the tops. One-line fix (swap the operands), then everything on the rock retuned because
  the lit faces are now the sun-facing ones.

## What changed
- `world/kit/rock_gen.gd`: normal fix above; `conc_strength` param (crease AO 0.5 normal, 0.8 on hero
  pieces); `_step_drop` riser width >= 2.4 grid cells (a 4 m drop inside one 0.5 m cell folded every
  quad diagonally and the tread rendered as a light/dark checkerboard).
- `world/kit/rock.gdshader`: **custom `light()`** — the direct term is compressed (`sun_gain 0.16`,
  which is ~0.5 of the built-in Lambert since LIGHT_COLOR in light() is not divided by pi) and
  wrapped (`sun_wrap 0.15`): with the normals right, a face square to the 1.6-energy sun clipped to
  V 0.96 at any albedo that kept the shade side readable. **Hemisphere sky fill** as emission on
  rock only (`sky_fill 0.55` x zenith `#9cb2d8` x up-facing, `shade_fill 0.08` lavender on side
  faces): tops are lit by the sky, shade sides go grey-lavender. `tex_contrast 0.55` (the albedo
  grain runs 0.5-1.8x its mean: bright grains clipped on lit faces), `tex_saturation 0.7`,
  `macro_grey #b0a89a`, `ao_min 0.28` / `ao_warm_tint (0.50,0.46,0.46)` (contacts cool, not warm),
  sand `#99876b` (was clipping on boulder feet), a second finer normal octave (0.8 m, 0.4, near
  faces only, fades 30-70 m) so the grain at 15 m is pitting, not stripes.
- `world_kit.gd`: `LIMESTONE_TINT (0.90,0.80,0.64) -> (0.57,0.52,0.45)` (a sun-square face lands at
  V 0.72-0.78); talus `ao_min 0.20`; pillars / arch / stacks `bed_darken 0.1 -> 0.05`,
  `bed_line_strength 0.3 -> 0.5` in a 0.3 m cavity (courses differ by a dark line, not by value).
  **Hero wall ends** (`_cliff_wall`, `_cliff_pillar(..., hero)`): the end column of every wall is
  2-3 pillars (every other one recessed 2-4 m, never forward), a forced scrub ledge at the first
  break, the outer pillar 25-40 % shorter with a 3-step broken crown, a 5-7 m block and 3-5 smaller
  ones at its foot; hero pieces get facets 1.2-1.8 m at 6-9 m, a 0.5 m grid and crease AO 0.8.
  **Crack scrub**: 0.6-1.2 m bushes rooted at the column joints, ~0.08 / m of height, half inside
  the face. Ledge scrub sunk 0.5 m. Outcrop `block` library piece: facets, `bevel_top`, half the
  variants with a 2-step broken crown, bed line 0.3 m. `_scree`: `far` 70 m (`_scatter_records` /
  `_spawn_multimesh` take `far`) and a sand-dusted `_scree_material` (no more white polka dots on
  the bench). **`_near_road`**: `road_dist_at > r + 6` short-circuits to a <= 30-segment list of
  bridge / viaduct decks (`_collect_deck_segments`, the only things `road_dist` ignores) instead of
  `nearest_road`'s ring search.
- `island.gd`: `_islet(pos, h, mat, seed, yaw)` is one 90-120 m mass: a low, strongly tapered
  scree shoulder over 30 % of its length, 3-4 tapered (0.25-0.4) columns of differing height with
  stepped crowns, two stacks attached at the far end, dark-tinted (0.42,0.48,0.40) scrub + 2 umbrella
  pines on the high column. Moved out to (-716, 40) / (-790, 100) — both inside 3 chunks of the
  `cliff_coast` camera's chunk (the streamer radius; z >= 120 is never loaded from there, which is
  why r2's second islet never showed). 3-4 boulders of 1-2 m on the bench at the arch's foot.
  Sea-stack tries cap 90 000 -> 20 000. `reference/spots.json`: `islet_far` added.

## Measured (PIL, 36 px medians; `base` = this worktree before, `v7`/`v8` = after)
- compare.py vs `ref_cliff_coast.png` (v8 final): cliff_coast 0.585 -> **0.568**, cliff_coast_b 0.535
  -> 0.510, cliff_arch 0.534 -> **0.545**. The colour term moved with the rock's mean value
  (the frame has more mid-tone rock now that the sun-facing faces are lit); by eye the rock went
  from dark-topped courses with cream slivers to a limestone with pale tops, warm lit faces and
  blue-grey shade (see `/tmp/r3_rocks/v8/`).
- Tops vs faces (`cliff_coast_b`): ledge top 1048,588 `V0.33` -> **V0.71** over the face at
  1048,624 V0.78 (top:face 0.55 -> 0.91; the last 10 % is LOOK's sun elevation 24 -> 32). Surf
  boulder tops are now the palest rock in `cliff_coast` (0.63-0.79 over flanks 0.5-0.6).
- Sun-square faces V 0.73-0.76 (final tint 0.57; v8), ledge top 0.68 over its face 0.75, lit S 0.22-0.34
  (was 0.15), shade faces `#656267`-`#50596e` H 220-224 V 0.40-0.44 (grey-lavender; ref `#535d73`).
  Rock pixels over V 0.85: 0.9 % of the frame (the texture grain on sun-square faces), was
  every islet and joint sliver at V 0.95.
- Foreground hero region (0-250 x 350-900): lumstd 0.101 -> **0.224**, p10 0.25 -> 0.23 (target
  <= 0.20: the darks still have to come from foliage interiors / contacts — see open).
- Islet region (1100-1310 x 190-390) p90 0.91 -> 0.78, lumstd 0.155 -> 0.088 (target p90 <= 0.70:
  the remaining lift is the fog / height fog — LOOK).
- World generation (headless, `architecture_tests`): **17 760 -> 14 796-15 100 ms** (-2.7 to -3 s;
  the harness 17.7-20 s -> 15.1-15.6 s). `[terrain] build stages` unchanged (GROUND):
  heightfield 2422, t3d_setup 785, t3d_maps 3352, t3d_import 137, ground_cover 4031.
- architecture / feature (27) / edge (7) tests pass; `--autotest --deliveries=2` passes (112 s,
  142 fps).

## Still missing / open
- The rock's lit:shade and absolute value now depend on `sun_gain` in the shader as well as the
  environment: when LOOK moves the sun (yaw -120, elevation 32, glow threshold), re-check a
  sun-square face (target V 0.72-0.78) and lower `sun_gain` before touching the tint again.
- Whole-frame p1 is 0.22 (target 0.12): the darkest 1 % must come from foliage interiors (GROUND)
  and rock contacts; rock contacts are at V ~0.35-0.4 now, `ao_min` could go to 0.22.
- The islets are single masses but still read boxy up close (flat crown faces on the columns);
  through the fog at 500 m they are fine. The far headland wall (z 30-195) and the stack at z 192
  are outside the `cliff_coast` streaming radius past z 120 (as before).
- The hero end's lowest face is still one plane with fine grain from 15 m; the facets show as
  0.5-1 m breaks, the reference's are 2-4 m blocks with deep shadow between them.
- Tree shadows on the collapsed hero corner show the card-shadow checker (the tree's own shadow,
  GROUND / LOOK shadow settings).

---

# rocks branch — round 2 (r2_rocks): pale faceted limestone, broken crowns, islets, real talus

Fixes ROUND2_CRITIQUE items 1, 2, 3 (islet), 4 (arch/bench, rocks half), 6, 12 (emission) and the
`cliff_arch` spot. Renders: `/tmp/r2_rocks/{cliff_coast,cliff_coast_b,cliff_arch,arch_close}.png`.

## What changed
- `world/kit/rock_gen.gd`: **sub-facets** (`facet_amp/facet_metres/facet_tilt`): per box face a 2D
  Worley cell field in the face plane; each cell is its own plane (push +/- amp along the face
  normal, tilt up to `facet_tilt`), the border between two cells blends over 0.1 cell so the crease
  is a steep chamfer, not a box shelf; edge vertices belong to both faces (`face_mask`) and take
  both displacements, so tops chip where a side facet steps. A per-facet albedo variation (+/- 6 %)
  is baked into `COLOR.g` so facets read in flat light too. **Broken tops** (`top_steps/top_drop`):
  the piece is cut into 2-4 steps along local x (one keeps full height), the side rows above the
  cut collapse onto it (riser + tread). **Rim bake**: `COLOR.a` = 1 on the top rim (near a vertical
  side and the top at once), the shader darkens it (`rim_darken 0.15`) — no more cream fillet.
  Joint grooves are at least 1.6 grid cells wide (a narrower groove moved single vertices and the
  concavity AO painted a grid of dark blobs at every bed/joint crossing — the "wood grain" of r1).
- `world/kit/rock.gdshader`: moss 0.45 -> 0.10 and only in crevices (ao < 0.6, x1.5), never on
  open tops; `macro_value 0.18 -> 0.10`; streaks 0.22 -> 0.08 as 1-2 m runs (threshold 0.62-0.8)
  weighted under bedding planes (COLOR.g); `tex_saturation 0.8 -> 0.55`; fracture tint only for
  `normal.y < -0.4`; `rim_darken` on COLOR.a.
- `world_kit.gd`: `LIMESTONE_TINT (0.64,0.53,0.39) -> (0.90,0.80,0.64)`; `rock_material(..., talus)`:
  the talus sibling has moss 0, fracture 0, `ao_min 0.25` (darker contact ring); `_cliff_pillar`
  bevel_top 0.8/0.5 -> 0.3-0.5, facets 0.45-0.7 m at 3.8-6 m, `steps` (broken crown, top_amp 4).
  `_cliff_wall`: joints log-uniform 5-16 m, column crests +/- 15 %, 1 in 5 lost its top third
  (2-4 m debris blocks at the foot), 1 in 4 leans 4-8 deg (pivoting on the foot), 1 in 3 crests
  broken into 2-3 steps; a face too close to the road is pushed back up to 6 m instead of dropping
  the column (r1 left gaps in the wall wherever a buttress met `road_clear`); ledge scrub 1.2/m,
  1-2.5 m, sunk 0.3 m, none within road_clear + 3 m of a road; crest pines 1 per 25 m^2 and always
  one at the wall's end columns. `_boulder_apron`: sizes log-uniform 0.5-8 m across with 30 % under
  2 m (+ 4 % giants 8-12 m), 40 % angular blocks, buried 35-50 % (`_boulder_y(g, s, buried)`),
  tilt 4-14 deg (`_add_rock(..., tilt_deg)`), giants only in the surf; `_scree`: 0.3-1 m rubble as a
  MultiMesh at 0.5/m^2 in the 0-5 m band. `_sea_arch`: span 30 m -> ~21 m clear opening, facets,
  stepped crown (4 steps), scrub + 2-3 umbrella pines on the crown. `_sea_stack(pos, h, mat, seed,
  taper)`: own size classes (4/6/4 m), facets, stepped top, noise 0.6 @ 6 m.
- `island.gd _gen_sea_cliffs`: west wall 10 m behind the road; arch (-562,-242)/(-536,-257);
  the near stack moved into the inlet mouth (its shadow fell across the apron); a 72 m headland
  wall on the south-west shore (x -556..-570, z 30..195, ~430 m from the cliff_coast camera on
  the right third of the frame) with two `_islet` clusters (3 stacks each, 46 / 52 m) and a 28 m
  stack in the shallows. Lookout pad radius 5 -> 12 (a wider bench at the arch's foot).
- `rock_gen.gd build_node`: **collider placement bug fixed** — the root carried the full transform
  *and* the StaticBody a world transform, so every rock's collision sat at twice the rock's
  offset from the world origin (phantom rocks on roads, none under the visible ones; the
  autotest wedged on one in a harbour street after the rocks moved). Now the root is rotation +
  position, the mesh instances carry the exact remainder, the body is identity with the hull /
  trimesh points transformed by that remainder. `_add_rock`: the flank block of a stepped outcrop
  checks its own road clearance. `tests/near_probe.gd` lists the nodes around a point.
- `reference/spots.json`: `cliff_arch` re-aimed at the arch (from (-604,15,-322) at (-549,12,-250));
  `apron_close` added. `tests/cliff_probe.gd`: `--x0/--x1/--z0/--z1/--step` rectangle.

## Measured (`cliff_coast`, 36 px patches, PIL sRGB; baseline = this worktree before the change)
- compare.py vs `ref_cliff_coast.png`: cliff_coast 0.586 -> **0.588** (texture-energy 0.540 ->
  0.567, colour 0.473 -> 0.467), cliff_coast_b 0.533 -> 0.537, cliff_arch 0.576 -> 0.539 (new
  camera: the arch fills the frame, the histogram is mostly rock now). The score is dominated by
  the colour histogram (sky/sea/fog); what moved by eye: pale faceted walls, broken crowns, no
  outlines, the arch with a road bench under it, stepped islets on the right horizon.
- Rock: lit pillar `#a3968b` H27 S0.15 V0.64 (was `#565259` V0.35), arch face `#988b84` V0.60
  (was `#85736b` V0.52), foreground wall region std 0.144 (was 0.094; p10-p90 0.22-0.61 vs ref
  0.16-0.62), arch top rim `#565559` darker than its face (was a cream fillet 1.35x).
- Apron region `#4e5767` H218 (still blue: 60 % of that rectangle is water and the *tops* of the
  surf boulders get 0.4 of the 24 deg sun while their SW flanks get 0.9, so from the SW camera the
  flanks are the pale part; boulder tops in `cliff_coast_b` read pale). Rounded boulder top V0.39.
- World generation 10.1 -> 9.8-11.3 s; architecture / feature / edge tests pass; `--autotest
  --deliveries=2` passes (112.7 s, 142 fps).

## Still missing / open
- Lit V 0.64 / S 0.15: the hue and the last stop need LOOK's sun 1.25 -> 1.6 and a warmer
  ambient; the far islets are fog-white (`#869ea4` V0.64, should be `#7993af` and dissolve) — LOOK.
- Boulder tops are not the brightest rock from the `cliff_coast` camera under a 24 deg sun from
  behind the viewer (physically they cannot be); the reference's sun is higher.
- The road on the bench is a bare dirt pad colour (GROUND paints the crown/ruts); the bench is
  still only the road's 12 m stamp (sea cells are not lifted by pads).
- The 1:20 sea-floor shelf in front of the walls (critique 7b) is a terrain height stamp — GROUND.
- The `cliff_coast` foreground-left wall end (15 m away) still reads as a large face with a fine
  horizontal texture grain; facets are subtle at that distance in flat light.

---

# rocks branch — round 1 (r1_rocks): pillar walls, a real arch, a coast bench, sunk talus

Fixes ROUND1_CRITIQUE items 3, 9, 10, 5 (bench + arch on the road), the rock-material half of 1 and
the ledge/crest emission of 6. Renders: `/tmp/r1_rocks/{cliff_coast,cliff_coast_b,cliff_arch,arch_close}.png`.

## What changed
- `world/kit/rock_gen.gd`: `bevel_top` (weathered rim over crisp 0.2 m vertical edges), `taper < 0`
  flares a pillar outward, `undercut_h/undercut_inset` recess the bottom band of the side faces
  (with AO), `arch_rise/arch_half` lift a lintel's underside into a parabolic vault. Column slivers
  with a 0 m snapped height (NaN basis warnings) fixed in the wall builder.
- `world/kit/rock.gdshader`: `tex_saturation 0.5 → 0.8`, `macro_value 0.13 → 0.18`, `macro_rust`
  → `#c49a6a`, `ao_min 0.45 → 0.35`; new `fracture_color #c99a5e` / `fracture_amount` on downward
  faces (`normal.y < -0.25`, only above the ground line so a boulder's lower flank stays weathered).
- `world_kit.gd`: `LIMESTONE_TINT (0.64,0.58,0.49) → (0.64,0.53,0.39)`; `_soft_bed_material` removed
  (the bedding is the baked band inside each piece). `_cliff_wall` rebuilt: master joints 5-15 m
  shared by all tiers, each column a stack of 12-25 m pillars (`_cliff_pillar`, beds 4-8.5 m per
  variant, inset 0.15-0.35, darken 0.1) with the breaks staggered next door; columns offset in depth
  (bay noise ±3 m, 1/6 buttress +3-5 m, 1/8 chimney -2-4 m); at a tier break the upper pillar steps
  back 1.5-3 m onto a scrub ledge (0.5 bushes/m, 1.5-3 m) or overhangs an undercut band; crest
  pillars get `top_amp 2`, 0.15 bushes/m² and an umbrella pine per ~40 m²; road clearance is
  measured at the front face (`road_clear`, default 4.5 m) so a road can run along the foot; the
  front side is now decided from five stations along the line (one sample landed in the lagoon
  behind the new bench and flipped the whole apron inland). `_sea_arch`: one eroded block — flaring
  pillars 9 m wide, a lintel as deep as the pillars with a vaulted underside (rise ≈ 8 m), beds
  aligned across the seam, trimesh collision, height 42. `_boulder_apron`: 0.12/m² default, sizes
  1.6-4 m (some 0.9-1.6 / 4-5.5), overlap allowed, edge 3 m off a road centreline; `_boulder_y`
  sinks land boulders 35 % of `s`; talus (boulders and blocks < 4.5 m) uses a bare sibling material
  (moss 0.1, no fracture tint) so it keeps pale tops and dark contacts. `_talus(line, ...)` wrapper.
- `island.gd`: `_define_roads` adds the coast spur off the mountain loop (`_px(232,262)`) down the
  headland and north along the west wall's foot on the 3-8 m contour to a lookout pad at
  (-541,-268); the road's own stamping carves the 11 m bench (18 m blend) — no terrain code touched.
  `_gen_sea_cliffs`: west wall moved 8 m behind the road and shortened at the headland; the arch
  spans the bench at (-561,-243)/(-537,-257) with its axis on the new camera's line of sight; a
  fourth wall on the inlet's south shore; talus band below the headland road cut.
- `reference/spots.json`: `cliff_coast` = the critique's camera (nudged to `[-598,38,-326]`);
  `arch_close` added (through the arch from the inlet). `tests/cliff_probe.gd --fine`: 2 m strip.

## Measured
- compare.py vs `ref_cliff_coast.png`: r0 `cliff_coast` 0.520 (old camera) → **0.538** (new camera;
  colour 0.375 → 0.407, luminance-layout 0.840 → 0.895). By eye: cliff left / arch centre / stacks
  and sea right, the bench and road through the opening, apron in the surf.
- `cliff_arch`: no face shorter than 10 m except the crest; pillars planar with crisp edges.
- Rock patches at 60 m (`arch_close`): lit face `#9c938e` H21, pillar `#938e8b`, boulder top vs
  flank V 0.34 / 0.41 with a dark contact ring. Saturation is still only S 0.05-0.09 because the
  round-0 environment (ambient 0.7 sky-blue, fog 0.0034) neutralises the tint; the albedo is warm.
- World generation 7.5-8.8 s; 81 unique RockGen meshes, 1.5 s; architecture / feature / edge
  tests pass; `--autotest --deliveries=2` passes (97 s, 142 fps).

## Still missing / open
- Lit/shadow V ratio ≥ 1.5 and the warm→blue hue swing need the LOOK lane's sun yaw / ambient.
- The bench is a bare Terrain3D slope texture (GROUND: road colour, scrub on the bench).
- The lintel/pillar seam of the arch is a visible horizontal line; the arch is still boxy compared
  with the reference's rounded mass. The lookout pad is unregistered (no place / delivery).
- `cliff_arch` spot still points at the old arch position (-524,-294): it shows the walls, not the arch.

---

# rocks branch — round 0: stratified limestone cliffs, arches, stacks, boulder fields

## What changed
- `world/kit/rock_gen.gd` (`class RockGen`): the verified sandbox generator (RESEARCH_tech §4), with
  two changes so meshes can be **cached and reused**: beds/joints are local to the piece (not
  world-locked) and the bedding shade (soft-bed darkening + cavity line under every bedding plane)
  is baked into `COLOR.g` instead of being computed from world y in the shader. `COLOR.r` = vertex
  AO, `COLOR.b` = height above the ground line. New params: `top_amp` (jagged tops), `taper`
  (stacks narrow upwards), `bed_phase` (force a hard/soft course). `RockGen.cached(params)`
  memoises by parameters; `build_node(r, xform, concave, mat, collide, lod_dist, far)` makes
  LOD0 (cell 0.4–0.7 m) / LOD1 (1.2–2 m) MeshInstances plus a StaticBody with a convex hull (or a
  trimesh for arch lintels) built from pre-scaled points, so bodies carry no non-uniform scale.
- `world/kit/rock.gdshader` + `assets/rock/` (ambientCG Rock019/021/024, 1K, CC0, credited in
  `assets/CREDITS.md`): triplanar albedo + normal, baked bedding, warm vertex AO (cavities ≈
  `#6f6659`), sand dusting at the foot, moss on tops, world-space macro patchiness, and vertical
  water streaks on side faces. Texture colour is half-desaturated and normalised by its mean so
  `base_tint` is the colour you get (sunlit faces measure ≈ (200,195,180) ≈ `#c9bfae`).
- `WorldKit._add_rock(pos, scl, rot_y, mat, collide[, kind])`: same signature, now places RockGen
  pieces: small → rounded boulder, big → bedded block (with a stepped second/third block on top and
  at the flank for s > 4.5), tall → tapered pillar. Six variants of each canonical piece, scaled to
  the requested size; every third piece swaps to the sibling texture. `_limestone_material()` /
  `_hoodoo_material()` now return the shader materials (badlands keep the red tint, Rock021).
- `WorldKit._cliff_wall(points, height, base_y, depth, mat, seed, apron)`: 4–7 m courses of 6–14 m
  blocks along a polyline; joints run through all courses (bays merged now and then), soft courses
  step back 1–2 m so hard ones overhang (≤ 2 m over the course below), a 30 m bay/buttress
  undulation, ±5° yaw / ±3° lean per block, crenellated tapered top course, scrub cards on the
  ledges and the rim, a talus apron (0.05/m², 2–18 m in front, rounded in the surf, angular on
  land). Blocks are size-quantised so the cache holds ~40 wall meshes. Skips anything within
  6 m + half a block of a road. `_sea_arch(a, b, height)`: two pillars + trimesh lintel + cap +
  fallen blocks outside the opening. `_sea_stack(pos, h)`: tapered jagged pillar + fallen blocks.
  `_at` and `_scatter_records` moved up from Island into the kit so builders can record recipes.
- `island.gd`: `_gen_sea_cliffs()` — three walls on the NW massif's west coast (north wall of the
  inlet at z≈-315 facing south, 46 m; the west-facing coast wall x≈-545 z -272..-152, 42 m; a
  34 m wall on the small inlet at z≈-147), an arch across the inlet mouth at (-524,-294) and five
  stacks; the big offshore stacks (s > 4.5) use `_sea_stack`; random outcrops in the cliff-coast
  region thinned to 40 % and capped at s = 7 so the walls are the cliffs there.
- `reference/spots.json`: added `cliff_arch` (from the sea, looking at the arch and both walls).
  `tests/cliff_probe.gd` (height/road grid of the area), `tests/rock_stats.gd` (cache cost).

## Measured
- compare.py vs `ref_cliff_coast.png`: cliff_coast 0.290 → 0.304–0.333 over the iterations
  (0.304 final), cliff_coast_b 0.335 → 0.309, cliff_arch 0.308–0.348. The score barely moves
  (it is dominated by the sky/water/fog colour histogram, which this branch does not touch); by
  eye the coast went from grey sphere blobs to bedded walls with undercuts, ledge scrub, stacks
  and a talus apron (see /tmp/rocks_v8, v9 renders during the session).
- World generation 6.4–7.7 s (was 6.3 s). Whole island: 149 unique RockGen meshes baked in
  1.75 s total (lazily, at chunk load), all 390 chunks 2.9 s. Tree 26 k nodes in the view test.
- architecture / feature / edge tests pass; `--autotest --deliveries=2` passes (114 s, 143 fps
  headless).

## Still missing / open
- The `cliff_coast` spot sits on the headland hump 17 m over the ground and its sightline is
  blocked by the terrain itself (the inlet and the arch are behind the rise), so that spot only
  shows outcrops and the back of the coast wall; `cliff_coast_b` / `cliff_arch` show the walls.
- Rocks still read brighter and flatter than the reference: the lighting (sun from the front,
  strong sky ambient, no fog) is the environment branch's job; when it changes, retune
  `LIMESTONE_TINT` in world_kit.gd (target ≈ (200,195,180) on sunlit faces).
- Walls are convex-hull blocks, so the terrain slope shows between wall foot and sea in a few
  places; no foam on the apron boulders (water branch).
- No scree MultiMesh for < 1 m rubble; boulders below s = 1.5 have no collision (as before).
