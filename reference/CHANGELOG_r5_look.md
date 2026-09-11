# r5_look — round-5 LOOK lane (critique items 1-sun, 4-sky/clouds, 8-fog, 10-foam, 11-teal/fresnel)

Files: `world/kit/world_kit.gd` (`Atmosphere`, `_build_environment`, `_cloud_cover_texture`, `_build_sea`,
`SEA_NAVY`), `world/kit/sky.gdshader`, `world/kit/sea.gdshader`. Rock / terrain / foliage / island files
untouched.

## What changed
- **Sun (item 1, committed first as `e4c8c68`)**: `sun_yaw_deg -150 -> -40`, elevation 36, `#ffe2c6` kept.
  The comment formula had z's sign wrong: with `rotation_degrees (-el, yaw, 0)` (YXZ) the sun stands at
  `(sin(yaw)*cos el, sin el, cos(yaw)*cos el)`; -150 put it at (-0.40, 0.59, -0.70), 144 deg BEHIND the
  cliff_coast view axis. -40 puts it at (-0.52, 0.59, 0.62), 75 deg ahead-right. Arch face 700,330 now
  `#626674` H226 S0.15 V0.45 (shade; was `#b3a19a` V0.70 lit), hero wall 120,650 `#897872` V0.54 (lit),
  frame p10/p50 0.10/0.37 (ref 0.19/0.36), ref-shade bin 7-11 % (was 8.5 %, ref 13.7 %).
- **Sky gradient (item 4, `sky.gdshader` + `Atmosphere`)**: the r4 sky was one veil because `cloud_cover 0.7`
  with a 0.22-wide ramp put 30-50 % of the lilac cloud base on every pixel. Now: `sky_top #96b3ce -> #c6b2c0`
  (the lilac is the TOP colour, the frame only spans elevations 0-18 deg), `sky_horizon #7790b2 -> #70a0d8`
  (a real blue band), `sky_curve 0.35 -> 0.22`, `sky_energy 1.4 -> 1.45`, and a **third stop**
  (`sky_zenith_color #8fa8cc`, `sky_band_deg 13`, `sky_zenith_deg 28`): the lilac is a haze band, above
  ~25 deg the sky returns to blue-grey (cliff_arch / coast_b frame up to 29 deg and were a pink sheet
  without it — the colour-correction ramp turns any low-saturation bright sky pink-grey, so the zenith has
  to be a saturated blue on input). Glow: `sky_glow_amount 0.35 -> 0.10`, `power 2.5 -> 4` (the narrow
  peach lobe now lands in the frame with the sun ahead-right), `sky_glow_wide_color_mul 0.28 -> 0.05`.
  Tuned with a numpy copy of the pipeline (`lin(sRGB) x energy -> fog_sky_affect -> filmic -> contrast ->
  ramp`; the r2 note that Compatibility applies the sky energy pre-linearise is wrong for 4.7 — c1 confirmed
  linear).
- **Clouds (item 4)**: `cloud_cover 0.7 -> 0.35`, ramp width 0.22 -> 0.14 (banks with edges, clear sky
  between), `cloud_base (0.78,0.71,0.75) -> (0.78,0.77,0.85)` (lilac-grey, the pink is the edge not the
  mass), `cloud_flat 0.7 -> 0.4`, `cloud_mul_edge (1.04,1,1)`, `cloud_mul_core (1.02,0.95,0.97)`.
- **Fog (item 8)**: `fog_color #7d94b0 -> #7591b5` (S0.35 H213), `fog_energy 1.22 -> 1.18`,
  `fog_sun_scatter 0.22 -> 0.15`. Tried `#6f9ac4 x 1.32` for the ref's brighter far haze: the villa's whole
  middle distance went cyan (H180-210 bins +8 %) and cliff_coast lost 0.02 — reverted.
- **Sea (`sea.gdshader`)**: foam `foam_color (0.88,0.87,0.84)`, `foam_emission 0.8 -> 0.5`, `foam_opacity
  0.85 -> 0.7`, `foam_depth 0.6 -> 0.4`, ring threshold 0.6 -> 0.68, `foam_streak_metres 16 -> 22` at x1.2,
  `whitecap_threshold 0.95`; `teal_metres 9 -> 6`, `teal_amount 0.75 -> 0.5`; `fresnel_bias 0.04 -> 0.07`,
  `reflect_amount 0.28 -> 0.15`, `sparkle 0.5 -> 0.35`; the reflected zenith is now the blue band
  (`sky_horizon.lerp(fog, 0.3)`), not the lilac top (it reflected as a grey-mauve sheet in cliff_arch).
  `SEA_NAVY` tried x1.1 / bluer: open water hit the ref's S0.55 but the dark-water bins doubled — kept r4.

## Measured (compare.py, PIL on 1600x900; ref = `ref_cliff_coast.png` unless villa)
| | r4 master | c0 (sun only) | **c9 (final)** | target |
|---|---|---|---|---|
| cliff_coast / _b / arch / villa | 0.617 / 0.560 / 0.601 / 0.604 | 0.620 / 0.549 / 0.607 / 0.610 | **0.605 / 0.522 / 0.586 / 0.612** | >= 0.64 / 0.565 / 0.62 / 0.60 |
| right sky column hue y5 -> y240 | 216 -> 219 | 244 -> 229 | **243 -> 212** | >= 240 -> <= 215 |
| sky S at y240 / L std | 0.26 / 0.030 | 0.12 / 0.033 | 0.27 / 0.033 | >= 0.26 / 0.06-0.10 |
| pale-blue bin (H190-215 S.17-.35) / pink bin | 7 % / 5.6 % | 0 % / 7.8 % | **26 %** / 0.6 % (arch 11 %, coast_b 10 %) | >= 20 % / ~13 % |
| coast_b sky p98 / cloud 700,60 | 0.85 slab | 0.69 | 0.82 (cores) / V0.77 | <= 0.78 / < 0.80 |
| coast_b water 200,650 | S0.22 V0.44 | S0.35 V0.44 | S0.40 V0.44 | S >= 0.35, V 0.34-0.40 |
| bright foam (V>.78 S<.15, surf zone) | 0.56 % | 0.49 % | **0.17-0.31 %** | 0.10-0.25 % (ref 0.08 %) |
| surf-zone teal share | 27 % | 8.0 % | 6.1 % | ref (same box) 6.4 % |
| far islet 1550,320 | `#9f9699` S0.05 | S0.15 V0.51 | `#646f83` **S0.24** V0.51 | S0.20-0.35, V0.50-0.62 |
| 250 m stack 1100,450 vs sky | V0.73 > sky 0.66 | V0.56 | V0.56 under sky 0.72 | <= 0.55, <= sky-0.10 |
| open water 1200,700 | `#2d3f56` | `#374860` S0.42 | `#2b405c` S0.53 V0.36 | `#2a3d5e` +- 0.03 |
| cliff_arch water V p50 | 0.28 | — | 0.32 | 0.31-0.36 |
| arch face 700,330 / hero wall 120,650 | V0.70 lit / V0.43 | `#676873` V0.45 / V0.55 | `#626674` H226 V0.45 / `#897872` V0.54 | shade V0.38-0.50 / lit V0.52-0.62 |
- World gen 7.5-9.6 s; architecture / feature / edge tests pass (0 failures).

## Still missing / for the other lanes
- **The compare.py score did not follow the per-item metrics**: every sky / fog / foam / water verify in the
  critique is met or within a few points, but cliff_coast sits at 0.605 (sun-only c0 0.620). The
  histogram term is composition-bound: our frame is ~35 % water and the ref ~12 %, so any water colour
  lands in an over-full bin, and the r4 flat pale sky happened to pile into the ref's biggest sky bin
  (H210-240 S<0.17 V.67-.83, ref 4.8 %, ours then 13.5 %) which the graded sky spreads over four bins as
  the ref does. The critique's exp3 (0.633) had the ROCKS emission changes (shade_fill 0.30, sun_gain
  0.35) on top of this sun — that is where the remaining cliff_coast gain is.
- Sky-box L std 0.033 (target 0.06-0.10): the ref's std comes from cloud banks and the far headland inside
  the box; ours has a clear column there. coast_b sky p98 0.82: the brightest cloud cores.
- Shade rock is still grey (arch face S0.15, ref 0.33; stack 1100,450 S0.14): a bluer `ambient_color`
  (#9ca3b9) only deepened the darkest 5 % (shadow bins doubled) — the saturation must come from
  `rock.gdshader` `shade_fill_color` (ROCKS item 2). Hero wall H16 S0.16 (ref H25-31 S0.30): albedo (ROCKS).
- coast_b water V0.44 (target <= 0.40): the north-facing sea under the sun-behind camera; the value is the
  sun on the chop, not the sky.
- Villa background outcrops 1200,80 V0.49 S0.09 (target V >= 0.55): shade faces at 250-400 m; the fog
  energy that lifts them (1.32) costs the villa colour term 0.05, so this stays with ROCKS' `sky_fill`.
