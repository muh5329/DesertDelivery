# rocks branch — round 5 (r5_rocks): the sun lights the rock again, blue shade, planes not smears, shingle bench

Fixes ROUND5_CRITIQUE ROCKS items 2 (emission vs sun), 14 (tops), 9 (facet smears / bedding), 6's rock
half (coast_b block contrast) and the bench under the arch (item 12's rock half, as shingle). Everything
was tuned under LOOK's announced sun (`sun_yaw_deg -40`, elevation 36, `#ffe2c6`) set locally in
`Atmosphere` — NOT committed here. Renders: `/tmp/r5_rocks/{base,v1..v4}/` (`base` = r4 rock under the
new sun, `v4` = final). Measurements: PIL medians of 16-24 px patches / region stats on 1600x900.

## What changed
- `world/kit/rock.gdshader`: the r4 rock lit itself — `shade_fill 0.80` + `sky_fill 0.75` on side faces
  gave ~0.65 x albedo of emission against <= 0.18 x albedo of sun. Now `sun_gain 0.13 -> 0.32`,
  `sun_wrap 0.15 -> 0.25` (the hero wall is 75 deg off the sun and must still read lit), `shade_fill
  0.80 -> 0.56` with a bluer `#6b87d1` (the warm ambient dilutes it: `#7f94c7` x 0.35 measured S0.10 on
  shade faces), `sky_fill 0.75 -> 0.70` weighted to the tops only (`sky_w = mix(0.12, 1, up)`, was 0.35 on
  side faces), `sky_fill_color #a9b6cf -> #b5bccb` (tops cream-grey). `tex_saturation` stays 0.45 (0.55
  put the lit hero wall at S0.36).
- `world/kit/world_kit.gd` (rock hunks): `LIMESTONE_TINT (0.57,0.53,0.47) -> (0.585,0.555,0.50)`; hero
  pillars: facets `0.8-1.2 m @ 8-12 m -> 0.6-0.9 m @ 12-18 m`, `facet_tilt 0.16 -> 0.08`, crease AO
  `0.65 -> 0.40` (0.5 -> 0.45 elsewhere), `bed_tilt 0.03-0.075 -> 0.012-0.036` (beds nearly horizontal);
  arch pillars / lintel: facets `4-4.5 m -> 6.5-7 m`, tilt 0.05, crease AO 0.30, `bed_line_strength 0.35
  -> 0.25`; stacks: facets 5 m, tilt 0.10. New `_shingle()`: a pavement of flat pale slabs (0.4-1.4 m,
  1.6 / m^2, no collision, 4 m off the road centreline, bench heights 0.3-6 m only, 90 m draw range)
  from the talus material without sand dusting.
- `world/kit/rock_gen.gd`: `facet_blend 1.6 -> 1.0` grid cells (the 1 m chamfer was the 20-60 px
  diagonal smear; one cell still covers the grid diagonal, so no staircases), `bed_band 0.04 -> 0.03`.
- `world/island/island.gd`: `_shingle((-546,-256), 26 m)` on the bench under and around the arch.

## Measured (`v4` vs `base` = r4 rock under the same -40 sun; ref = ref_cliff_coast resampled)
- compare.py: cliff_coast **0.620 -> 0.632** (r4 master under -150: 0.617), cliff_arch **0.606 -> 0.612**
  (v1/v2 0.624/0.622 with the greyer shade — the colour term prefers grey, the eye does not), cliff_coast_b
  0.549 -> **0.544** (its frame is p50 0.60 against the ref's 0.36 with the sun behind that camera; the
  rock terms below are met, the rest is LOOK's sky / water and GROUND's terrain wall).
- Arch face 700,330: `#666873` H234 **S0.10** V0.45 -> `#555a67` H223 **S0.18 V0.40** (target H205-235
  S0.15-0.30 V0.38-0.50 ✓). Hero wall 120,650: `#8a7870` S0.19 V0.54 -> `#867265` H23 **S0.24 V0.53**
  (target S0.22-0.32 V0.52-0.62 ✓). Lit:shade 1.33 in V (block face vs arch face; ref 1.5-2.2 — see open).
- Whole frame: ref-shade bin **10.6 % -> 14.2 %** (ref 13.7 %); rock band cool / warm 66 / 10 % -> **75 / 12 %**
  (ref 74 / 8 %); rock band V > 0.6 share 11.1 -> 13.1 % (ref 16 % in this measure; the critique's 42 % was
  under the -150 sun); tan bin 0.01 %; frame p10/50/90 0.12/0.37/0.70 (ref 0.19/0.36/0.65).
- coast_b centre wall (600-1200 x 360-720): lumstd **0.166**, edge 0.103 (targets >= 0.13 / >= 0.07 ✓;
  r4 master 0.095 / 0.047); block face 1050,650 V0.55 against the blocks region V0.68 — the pieces cast and
  receive shadow again. Lit rock S0.18-0.22 (ref 0.20-0.25).
- Facets: left pillar row-profile p90 0.043 -> **0.039** (target <= 0.03), column-profile std 0.026
  (target <= 0.04 ✓), arch face region lumstd 0.086 -> **0.080** (target 0.06-0.10 ✓); at 2x the arch crop
  shows plane breaks and no diagonal smear longer than ~20 px.
- cliff_arch boulder 620,690 / 620,730: top `#686b75` V0.46 sky-grey against a lit flank V0.53 — the flank
  is sun-square (cos 36 = 0.81 of the sun) and the top gets sin 36 = 0.59: physically right, the ratio
  target of 1.15 is not met by the sun alone (see open).
- World generation 7.4-9.5 s in the harness (6.4 s headless); architecture / feature / edge tests pass.

## Still missing / open
- Tops: the ref's tops are its palest rock; ours are pale on the arch crown and the stacks but a flat
  boulder top under this sun sits at ~0.87 of its lit flank. More `sky_fill` (0.85 tried) blew the crown
  white without lifting the boulder tops much; the rest is LOOK's ambient sky contribution.
- Lit:shade 1.3-1.5 in V (ref 1.5-2.2): more `sun_gain` blows the sun-square coast_b faces (V0.68 already).
- Row-profile p90 0.039 vs the 0.03 target: the residual bands are the bed lines + the joint grooves of
  the arch pillars at 5 m spacing.
- The road strip itself under the arch (within 4 m of the centreline) is still the terrain's dirt: the
  shingle stops at the shoulder (item 12, GROUND's bench paint).
