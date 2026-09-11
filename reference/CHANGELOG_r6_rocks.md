# rocks branch — round 6 (r6_rocks, final): sun-gated shade fill, no marble sibling, warmer talus sand

ROUND6_CRITIQUE ROCKS items 2 (blown sun-square rock), 3 (the veined rock019 sibling) and 10 (talus
tint). Only `world/kit/rock.gdshader` and the rock hunks of `world/kit/world_kit.gd` changed; nothing
in env / sky / sea (LOOK) or terrain / scatter (GROUND). Item 11 (bench hue) lives in `terrain.gd`
`bench_col` — GROUND's file, not touched here. The `_cliff_wall` crest pines already go through
`_scatter_records`' `CAMERA_CLEAR` guard (item 9's radius change is GROUND's line).
Renders: `/tmp/r6_rocks/{base,v1..v6}/` (`base` = master, `v6` = final). Measurements: PIL medians of
20 px patches / region stats on the 1600x900 renders (`/tmp/r6_rocks/measure.py`).

## What changed
- `rock.gdshader` (item 2): the blue shade fill stays an emission term but is gated by the sun:
  `uniform vec3 sun_dir` (world, toward the sun; set by `rock_material` from `Atmosphere`, default =
  yaw -40 / el 36) and `shade_fill_color * side_w * shade_fill * (1 - 0.6 * dot(wn, sun_dir))` — a
  sun-square face gets 40 % of the fill, a shade face all of it. `shade_fill 0.56 -> 0.50`. The
  direct term gets the knee `d = d (1 + k) / (d + k)`, `sun_knee 0.3` (square x1.0, the 75-deg-off hero
  wall x1.83, wrap-only shade x2.6) and `sun_gain 0.32 -> 0.14`.
  Why not in `light()` as the critique sketched: v1/v3 put the fill in `light()` (with and without
  the knee) and the shade faces went V0.40 -> 0.50 S0.25 -> 0.11 — the GL renderer's DIFFUSE_LIGHT
  path measured ~2x the emission strength for the same numbers, so the fill went back to EMISSION
  with the sun passed in as a uniform (known scale, r5 tuning kept).
- `world_kit.gd` `_limestone_material()` (item 3): the `_rock_alt` sibling is `rock_material("rock024",
  LIMESTONE_TINT * Color(0.90, 0.89, 0.87), 0.10, 0.5)` (was the veined rock019). The rng sequence is
  unchanged (same `randi()` calls). rock019 rendered a third darker than its declared mean: with the
  sibling at `LIMESTONE_TINT * (1, 0.98, 0.95)` the hero-wall region went p50 0.45 -> 0.60 (v4), so the
  sibling keeps its role as the darker bed at x0.90 (x0.80 put the hero piece at V0.42).
- `world_kit.gd` `rock_material()` talus branch (item 10): `sand_amount 0.20` (0.25), `sand_color
  (0.56, 0.50, 0.40)` (warmer, S0.29, and darker than the grey (0.58,0.53,0.45)), `sky_fill 0.60`
  (0.70). The critique's `sand_amount 0.12 / (0.62,0.54,0.42)` brightened the boulders (p90 0.76 ->
  0.84, v4): the grey sand was darkening them, so the dusting stays and only its hue moves.
- `rock_material()` sets `sun_dir` on every rock material (static, from `Atmosphere.sun_yaw_deg /
  sun_elevation_deg`, the same Euler the sun node uses).

## Measured (v6 vs base = master; ref = ref_cliff_coast resampled)
- compare.py: cliff_coast **0.636 -> 0.634** (>= 0.63, within the 0.005 rule), cliff_coast_b **0.519 ->
  0.522**, cliff_arch **0.614 -> 0.616**.
- coast_b sun-square stacks 1150,780 `#d3beb0` V0.83 S0.17 -> `#bea99a` **V0.75 S0.19**; 350,560 V0.84 ->
  0.75; stack 400,700 V0.76 -> 0.67; stack region (1100-1200 x 730-830) blown share (V>0.8 S<0.25)
  **21.8 % -> 3.4 %**, p50 0.69 -> 0.64; rock region p50 0.58 -> 0.57, p90 0.75 -> 0.72.
- cliff_coast rock band V>0.8 S<0.25 share **1.14 % -> 0.33 %** (target <= 0.5 %); hero wall 120,650
  `#827066` V0.51 S0.22 -> `#7a6a5f` **V0.48 S0.22** (target 0.47-0.53); hero-wall region p50 0.45 ->
  0.46, no diagonal veins (see `/tmp/r6_rocks/hero_cmp.png`); arch face 700,330 `#4d5567` H222 S0.25
  V0.40 -> `#4d5365` H225 S0.24 V0.40 (unchanged); frame p10/50/90 0.23/0.43/0.78 -> 0.23/0.42/0.78.
- Boulders (500-760 x 620-760): p90 0.76 -> 0.74, blown 6.5 % -> 2.9 %, lit 650,660 V0.60 -> 0.58.
- Generation 11.0 s in the render harness (shader recompile included), tests architecture / feature /
  edge pass.

## Still missing / open
- Square faces sit at V0.75, not the 0.62-0.70 target: with the direct term at `sun_gain 0.14` the
  remaining ~0.9 scene-linear on a sun-square face is the environment ambient + sky fill, which the
  rock shader cannot take away without also darkening every shade face (LOOK's `ambient_energy`).
  The same goes for the big terrain cliff face on the right of coast_b (`#ae9888` V0.68, GROUND's
  terrain material, not a rock piece).
- Talus lit flanks are still grey (650,660 S0.09; ref S0.23): the sand tint move did not reach them;
  it is the `ao_warm_tint` / `tex_saturation 0.45` of the bare variant, left alone (do-not-touch list).
- The rock024 hero wall shows the RockGen facet grid as a soft 2 m quilt now that the veins are gone
  (visible in v4-v6 at 2x); a geometry item, out of scope for the final round.
