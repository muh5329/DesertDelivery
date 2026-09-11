# r2_look — round-2 LOOK lane (critique items 3-horizon, 5-ambient, 7, 10, 11)

## What changed
- **`world/kit/sky.gdshader` (new)** — a ProceduralSkyMaterial clone (same gradient / sun-halo maths) so
  the built-in cover could be replaced: clouds now **multiply** the sky and converge on a flat stratus
  colour (`cloud_base`, lobe cores darkened by a second half-wavelength noise stored in the cover's red
  channel), and a warm sun-side glow (narrow lobe on the sun + wide azimuth lobe near the horizon,
  `#c4b0bb`). The ground half runs at the sky's energy (the sea plane ends ~0.5 deg under the true
  horizon; the darker ground half drew a 4-px strip there).
- **`world/kit/world_kit.gd` `Atmosphere`** — sun 1.25 -> **1.6**; ambient `#8a87a0` x0.34 / sky 0.5 ->
  **`#95968d` x0.25 / sky 0.25** (the sky's linear blue is ~3x the fill; at 0.5 it out-voted every green);
  fog `#6b84a0` x1.05 / 0.003 -> **`#6a8bb6` x1.15 / 0.0026**; cloud tunables replaced by
  `cloud_mul_edge/core`, `cloud_base`, `cloud_flat`, `sky_glow_*`; `SEA_NAVY` x0.7 (the stronger sun).
  `_cloud_cover_texture` writes lobe detail into R. `_build_sea` passes fog, sky-horizon and glow
  values to the sea so it can rebuild the rendered horizon colour itself.
- **`world/kit/sea.gdshader`**
  - **Horizon (item 3):** the sea writes its own `FOG`: the engine's exponential fog with the engine
    colour near, sliding (250-1400 m) to the *rendered* sky-horizon colour. Finding: in Compatibility the
    sky shader applies its energy in sRGB *before* linearising, so the rendered horizon is
    lin(sRGB x 1.4) ~ 2.1x the linear colour while fog is lin(colour) x energy — "fog = sky horizon" is
    not one setting, and lifting the geometry fog to it (pass 1) flattened every pillar at 200 m
    (std 0.162 -> 0.140). The shader rebuilds the horizon exactly that way (sRGB x energy + glow lobes,
    pow 2.2, then `fog_sky_affect`), so sea and sky meet at any azimuth.
  - **Turquoise from distance to rock (item 7a):** `rock_proximity()` probes the depth buffer in a
    screen-space neighbourhood sized for 15 m at the fragment's depth (12 directions x 6 radii),
    reconstructs each hit's world position and keeps only above-water hits by 3-D distance (a face
    20 m up a pillar contributes nothing). Per-direction nearest hit -> smoothstep weight, averaged over
    directions so the halo is round, not a 12-gon; broken by the 11 m noise. `col_teal (0.10,0.30,0.32)`.
  - **Foam (item 7c/d):** the ring is the inner part of the same proximity field (prox > 0.5, ~3-5 m),
    ~half of it opened by the 1.5 m clump noise; streaks reach ~12 m from rock; whitecaps rebuilt on the
    4-11 m noises, threshold 0.9, gated by a 40 m patch mask and faded past 110-220 m (the first attempt
    laced the whole 3-5 m shelf with dashes); `foam_color (0.97,0.96,0.92)`, `foam_emission 1.0`.
  - `depth_fallback_start 350 -> 300`, `col_mid/col_navy` x0.7.
- `tests/view.gd`: the `--plain` debug flag sets the sky's ground colours through
  `set_shader_parameter` when the sky is a ShaderMaterial (it is now).
- `project.godot`: unchanged (2048 shadow map / soft-high PCF / MSAA 2x already right).

## Measured (PIL; `cliff_coast` water region = x 900-1600, y 480-860; sky rows 230-340 at x 1400)
| | r1 (baseline here) | r2_look | acceptance |
|---|---|---|---|
| horizon: max one-row V step | 14.0 pts (17 in the critique) | **3.6 pts**, 10 pts spread over 70 px | <= 6 over >= 40 px |
| water teal (H165-205, S>0.3) | 0.42 % | **3.0 %** (`#3e677f` H202 vs ref `#345365`) | >= 2.5 % |
| water foam (V>0.72, S<0.25) | 0.32 % | **0.52 %**, foam pixel `#e7d8d2` V0.91 (was `#5a5557`) | >= 1.2 % (open) |
| clouds vs sky (`cliff_coast_b`) | `#b7b7d3` V82 on V80 sky (lighter) | **`#a3a5ba` V73 on `#9cabc6` V78** (ref `#a4a8bc` on `#a0adc5`) | darker + pinker |
| cliff_coast p1 / p50 / std / S | 0.100 / 0.332 / 0.163 / 0.316 | **0.111 / 0.331 / 0.175 / 0.325** | within 0.03 |
| cliff_coast_b p1 / p50 / std | 0.200 / 0.443 / 0.162 | 0.204 / 0.464 / 0.162 | |
| villa p1 / std / S | 0.140 / 0.112 / 0.294 | 0.152 / 0.121 / 0.300 | |
| compare.py cliff_coast / _b / arch / villa | 0.587 / 0.533 / 0.576 / 0.565 | **0.570 / 0.559 / 0.582 / 0.552** | |
- World gen 9.6-11.7 s; architecture / feature / edge tests pass.
- Canopy in shade: `cliff_coast` big tree `#463d3d` -> `#3c373b` (neutral, no longer teal H198); the
  darkest 1 % is that canopy interior — with the leaf albedo still V 0.18-0.29 it is ambient-only, so it
  goes grey rather than green until GROUND lands its 2x albedo (which will lift p1 slightly).

## Still missing / open
- **Lit/shade (item 10) could not be verified on rock:** the critique's `cliff_coast_b` patches
  (1400,520 vs 1200,520) are two different rock *materials* here (brown wall `#5e5252` vs pale limestone
  `#474b5c`), both facing the camera; boulder top vs side (760,690 / 760,730) reads 0.35 / 0.39 because
  the tops still carry moss. Sun 1.6 / ambient 0.25 is in place; the ratio needs ROCKS' tint/moss change
  to show. Re-measure after the merge.
- Foam area in the `cliff_coast` region is 0.5 % vs the 1.2 % target: the region holds four boulders,
  the reference's holds ~thirty in surf (ROCKS item 6, "60 % of the apron on the beach"); per-rock the
  ring/streaks are now comparable in size.
- The far coast at 400-500 m still reads flat grey-blue haze over pale geometry; the sea's own far fog
  converges on the sky but the engine fog for rock cannot vary with distance the same way.
- The rock-proximity probe costs 72 depth taps per sea fragment; fine on a GPU, but it is the reason the
  llvmpipe render is slower than r1. It reads the opaque depth buffer only, so foliage cards and
  transparent props do not make foam.
