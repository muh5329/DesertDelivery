# rocks branch — round 4 (r4_rocks): limestone again under the new sun, sky-lit shade, no staircases

Fixes ROUND4_CRITIQUE items 1 (palette), 2 (shade fill half), 3 (sky fill / tops), 4 (staircases,
far joints, bed bands), 5 (rock half: hero busy-ness) and 10 (boulder tops / block aprons); 13's rock
half was already true (the bench boulders take the talus sibling in `_add_rock`). Everything was
tuned and measured under the LOOK lane's announced sun (`sun_yaw -150`, elevation 36, `#ffe2c6`) set
locally in `Atmosphere` — NOT committed here; the environment lines are LOOK's. Renders:
`/tmp/r4_rocks/{base,v2..v6}/`, `base` = the first render of this branch (palette only).

## What changed
- `world/kit/rock.gdshader`: `tex_saturation 0.7 -> 0.45`, macro tint mix `0.5 -> 0.25`,
  `macro_rust #c49a6a -> #b8a184`, `sand_color (0.58,0.53,0.45)`, `tex_contrast 0.55 -> 0.42`,
  `sun_gain 0.16 -> 0.13`. **Sky fill** `0.55 -> 0.75`, colour `#9cb2d8 -> #a9b6cf` and it reaches
  side faces at 35 % (`sky_w = mix(0.35, 1, up) x not-underside`); **shade fill** `0.08 -> 0.80` with
  `#859abf` (the ref's shade is `#535d73` H215 S0.27 V0.45: a paler fill at this strength lifted V but
  washed S to 0.08, `#8f99bd` at 0.7 went navy), undersides keep 40 % of it (the vault). `ao_min 0.28 ->
  0.24`. `fine_normal 0.4 -> 0.15`, fading 12-30 m (was 30-70); the 3 m relief fades to half beyond
  40-120 m (far planes smooth, not grain).
- `world/kit/rock_gen.gd`: **the dotted staircases** were not the step risers — they are the Worley
  facet borders: the crease blend (0.12 cell = 0.54 m) was narrower than the 0.6 m grid, so every
  vertex fell wholly into one facet and each diagonal border aliased into one-cell steps. The blend is
  now >= 1.6 grid cells (`facet_blend`), a ~1 m chamfer that reads as a soft fracture shadow. The step
  cut itself no longer collapses rows either: each column of grid rows is SQUASHED so its top lands on
  the step line (no fans of sliver triangles, no riser on the front face). Far LOD (cell >= 1 m):
  joint grooves 1.0 cell wide (was 1.6 -> 3.2 m trenches), half depth, crease AO x0.6. **Bed bands**:
  `bed_band 0.04` / `bed_band_h 1.2` — one soft 1.2 m course per bed with 0.4 m ramps baked into
  `COLOR.g`, the line at `bed_line_strength 0.35` (was 0.5) only marks the plane. `top_cut`: a boulder's
  top is sliced flat (tilted up to 0.12) after the noise, vertices above drop onto the plane.
- `world/kit/world_kit.gd` (rock hunks only): `LIMESTONE_TINT (0.57,0.52,0.45) -> (0.57,0.53,0.47)`;
  hero pillars facets `1.2-1.8 m @ 6-9 m -> 0.8-1.2 m @ 8-12 m`, crease AO `0.8 -> 0.65`; crack scrub
  `0.08 -> 0.03 / m`; `bed_line_strength 0.35` on pillars / arch / stacks / blocks; boulder library
  piece: `top_cut 0.78-0.90` on 5 of 6 variants + `top_amp 0.15`; `_boulder_apron` 50 % blocks (was 40).

## Measured (PIL medians, 36 px; `r3` = /root/rounds/r3 under the r3 sun, `v6` = final)
- compare.py vs `ref_cliff_coast.png`: cliff_coast r3 0.590 -> base 0.572 -> v3 0.587 -> **v6 0.578**;
  cliff_coast_b 0.576 -> 0.554 -> 0.550 -> **0.553**; cliff_arch 0.574 -> 0.558 -> 0.580 -> **0.568**. Under the new
  sun the score is dominated by the frame histogram (LOOK's fog / sea / grade); the rock terms:
- **Tan gone**: tan bin (H0-30 S0.33-0.50 V0.67-0.83) 6.1 % of the cliff_coast frame -> **0.1 %**; lit
  faces `#c0aba0`-`#ae9d95` H15-20 **S0.13-0.17** V0.66-0.75 (r3 `#c3987c` S0.36, `#966f52` S0.46;
  ref S0.20-0.25 — a hair grey now, but no rock pixel over S0.35 outside fracture undersides).
- **Shade**: faces out of the sun `#62626b`-`#6d6f78` H229-240 V0.42-0.48 (r3 `#334157` V0.34 S0.41
  navy); cool-shade ref bin share of the cliff_coast_b frame 5.2 % -> 8-11 %, cliff_coast 1.6 % ->
  2-3.8 % (the ref's 13 % needs LOOK's ambient lift as well). Hero wall region p50 0.40 -> 0.28-0.32
  (it is now fully in shade with the sun ahead of the camera; ref fg cliff p50 0.40).
- **Tops**: boulder top / flank (cliff_arch 620,690 / 620,730) `V0.75 / V0.44-0.51` = **1.5-1.7**
  (r3 1.1); apron boulders are split blocks with one flat pale top. Stack ledge tops in cliff_coast_b
  are the palest rock on the shaded stack (see the crop); the 1048,588 patch of the critique now
  lands on a shaded block face in the recomposed frame and is not a top any more.
- **Staircases**: none on the arch crop at 2x (v3+); facet borders are ~1 m soft chamfers.
- **Hero region** (0-250 x 350-900) lumstd 0.224 -> **0.13-0.15**, p10 0.10 (target 0.13-0.17 / <= 0.20);
  cliff_arch hero column lumstd 0.19 -> 0.10.
- Arch-face region (620-900 x 280-420) lumstd 0.144 -> 0.150-0.158 (target <= 0.09 not reached: the
  region spans the joint shadows and skyline; the face itself is smooth now).
- World generation (headless, architecture_tests): **7 959 ms** (`[game] world generated`), harness
  8.4-8.6 s (master 10.0 s). architecture / feature / edge tests pass.

## Still missing / open
- Lit S 0.13-0.17 vs ref 0.20-0.25: the warmth must come from the sun colour ratio (LOOK); pushing
  the tint warmer brings the tan back on sun-square faces.
- The shade faces are still ~0.05 V under the ref's `#535d73` and less blue (S0.15); the whole-frame
  p50 sits at 0.36-0.38 (ref 0.354), so the rest of the lift should be LOOK's ambient / fog, not more
  rock emission (0.8 of the shade fill is already the ceiling before shade goes pale).
- The arch interior patch (790,470) stays `#384358` V0.35: that is the shaded cliff behind the opening,
  not the soffit.
- The arch-face region lumstd target 0.09 would need the far-LOD joints removed altogether.
