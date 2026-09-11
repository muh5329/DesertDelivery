# r3_look — round-3 LOOK lane (critique items 1-elevation, 2-yaw/glow, 4-height fog, 5-tone, 8-sea, 12-sky)

Files: `world/kit/world_kit.gd` (`Atmosphere`, `_build_environment`, `_build_sea`, `SEA_NAVY`),
`world/kit/sky.gdshader`, `world/kit/sea.gdshader`. `project.godot` unchanged (2048 shadow map /
soft-high PCF / MSAA 2x still right). Rock / terrain / foliage / island files untouched.

## What changed
- **Sun** `sun_elevation_deg 24 -> 32`, `sun_yaw_deg -62 -> -120` (sun in the WNW, light toward ESE):
  the broad NW-facing faces the `cliff_coast` camera looks at are now the lit ones (face at 650,420
  `#95867e` V0.58 S0.15 -> `#928172` V0.57 **S0.22**, warm), the arch interior and right-facing walls
  shade; the villa gets long shadows toward the camera (sun front-left, as `ref_villa_vineyard`).
  `sun_energy 1.6 -> 1.4`, `ambient_energy 0.25 -> 0.3`: with the sun on the broad faces the lit
  limestone hit V0.96 (blown) and lit:shade was 2.0; the swap keeps the frame median. Rock pixels
  over V0.85 in the `cliff_coast` rock band: 3.7 % -> **1.7 %** (the rest is the r2 `LIMESTONE_TINT`
  0.9 albedo — ROCKS item 2, not changed here). `shadow_bias 0.08 -> 0.12`, `shadow_normal_bias 2 -> 3`
  (harmless; see the ledge-top finding below).
- **Tone** `exposure 0.68 -> 0.57`, `contrast 1.22 -> 1.28`, `lift_black #0e1016 -> #0a0c12` (floor still
  above 0, nothing clips). `glow_hdr_threshold 0.9 -> 1.3` (lit limestone at ~1.1 linear no longer blooms:
  the islets' soft white edges are gone).
- **Height fog** `fog_height 2 -> 9 m`, `fog_height_density 0.012 -> 0.022` (~18 % at sea level, 0 above
  9 m; not distance-scaled, so kept under 20 %; the sea fogs itself and ignores it). Islet feet dissolve
  before their crowns. `fog_color #6a8bb6 -> #7190b2` (S 0.42 -> 0.37, the haze a hair less blue).
- **Sky** (`sky.gdshader`, `Atmosphere`): `sky_top #9cb2d8 -> #a6b0c8`, `sky_horizon #6a8bb6 -> #7790b2`
  (`ground_horizon` follows). The wide glow lobe is now **azimuth-independent above ~10 deg**
  (`glow_wide 0.14 -> 0.35 x glow_wide_color_mul 0.35`, colour `#c4b0bb`): the upper sky warms to a
  pink-lilac on both sides of the frame even with the sun behind the camera; at the horizon it still
  follows the sun's azimuth (numerically the old 0.14 x az^1.5). The ground half of the sky gets the same
  glow so the rows under the sea plane match. First attempt (`#a8b0c8 / #8494ae`, mul 0.4) gave a flat
  pink-grey slab at S 0.09 — pulled back to S 0.13-0.15.
- **Horizon** (`sea.gdshader`): the far sea's rebuilt sky-horizon colour was clamped to 1.0 per channel
  before linearising while the sky shader hands > 1 to the tonemapper — with the new (brighter) horizon
  colour the blue channel clipped and a warm 16-px band appeared under the sky on the sun side of
  `cliff_coast_b`. Clamp removed; the engine-style sun scatter in the sea fog now fades out with the
  horizon slide (the sky has no such term); `sea_horizon_gain 0.97 -> 1.0`. `cliff_coast` x 1400 rows
  270-300: 0.56 .. 0.55 .. 0.57 (max one-row step 0.01; was a 0.05 dip).
- **Sea colour** (`sea.gdshader`): `col_teal (0.10,0.30,0.32) -> (0.06,0.13,0.025)`, `col_turquoise
  (0.13,0.31,0.34) -> (0.06,0.13,0.025)`, `col_shallow -> (0.14,0.18,0.11)` (sand-lit skirt, depth
  < 0.5 m only), `teal_amount 0.75 -> 0.9`. Finding: at 150 m the (blue) fog is ~2/3 of the rendered
  water, so the skirt albedo carries almost no blue on purpose and the fog adds it back; the 11 m noise
  now varies the skirt's darkness instead of opening holes that let the lit cyan through; the Fresnel
  sky term is halved inside the skirt; `alpha_shallow 0.5 -> 0.75`, `alpha_deep_depth 1.8 -> 1.2` (the
  pale seabed showing through 0-1.8 m lit the whole shelf cyan-grey). `SEA_NAVY x 1.15` for the lower
  exposure (open water `#223651` vs ref `#2e3e5e`).
- **Swell** : a 16 m noise stretched 2.5:1 across `wave_b_dir` scales the Fresnel sky term (+-40 %) and
  the albedo (+-20 %) -> broad light/dark bands in the open water (visible in every coast render).
- **Foam**: `foam_noise_metres 4 -> 6.5`, `foam_clump_metres 1.5 -> 3.5`, `foam_streak_metres 10 -> 16`,
  one soft clump field with wide ramps (`smoothstep(0.5, 0.85, shore*0.35 + fn*0.3 + clump*0.35)`, ~half
  the collar open), streaks x0.5 and only at `prox > 0.25`, `foam_depth 1.6 -> 0.9` (the hard 1-px line
  along every shore), whitecaps `threshold 0.9 -> 0.94`, gated off where `prox > 0.1-0.25`, patch mask
  40 m -> 25 m, `sparkle 0.9 -> 0.5`.

## Measured (PIL, 36 px medians / regions; ref = `ref_cliff_coast.png`)
| | r2 (base here) | r3_look | target |
|---|---|---|---|
| compare.py cliff_coast / _b / arch / villa | 0.585 / 0.535 / 0.534 / 0.566 | **0.625 / 0.563 / 0.579 / 0.585** | |
| cliff_coast p1 / p50 / std | 0.171 / 0.402 / 0.171 | **0.128 / 0.370** / 0.184 | 0.10 / 0.36 / 0.17 |
| cliff_coast_b p1 / p50 ; arch p1 / p50 ; villa p1 | 0.19 / 0.57 ; 0.16 / 0.46 ; 0.13 | 0.15 / 0.50 ; 0.12 / 0.42 ; 0.11 | |
| sky region 560-1600 x 0-180 | `#94a6c1` H216 **S0.23** | `#a6aabf` H230 **S0.13** | S <= 0.17 |
| sky upper-right 1500,60 | `#93a0b7` H218 S0.20 | `#969cb1` H226 S0.15 | H >= 235 (not reached) |
| islet region 1100-1310 x 190-390 p90 / lumstd | 0.91 / 0.154 | **0.66** / 0.115 | <= 0.70 / <= 0.09 |
| islet patch 1130,250 vs sky beside | `#f2e4d5` V0.95 vs V0.78 | `#82828d` **V0.55** vs V0.78 | <= 0.72, <= sky |
| broad face 650,420 / lit face 505,450 | V0.58 S0.15 / V0.67 S0.23 | V0.57 **S0.22** / V0.67 **S0.30** | lit S >= 0.22 |
| rock V > 0.85 (300-1300 x 300-700) | 3.7 % | 1.7 % | 0 (ROCKS tint) |
| cliff_coast_b lit 1230,700 : shade 1010,700 | 0.62 : 0.36 = 1.7 | 0.66 : 0.35 = 1.9 | 1.5-1.7 |
| bench 740,520 | `#3d4b63` V0.39 (shadow) | `#7b6862` V0.48 (lit) | >= 0.5 |
| near-rock water (520,640) | `#30586e`-class H201 V0.43 | `#28434b` **H193 V0.29** (darker than open `#223651`) | `#385d51` H160 V0.36 |
| water green H120-170 S>0.3, surf zone | 0.00 % | 1.5 % (whole region 0 %: skirt sits at H190-196) | >= 0.5 % |
| surf-zone foam (V>0.72,S<0.25 — includes lit rock) / HF std | 7.1 % / 0.064 | 4.6 % / 0.053 | 1-2 % / <= 0.03 |
| horizon max one-row step, x 1400 | 0.05 dip | 0.01 | <= 0.02 |
- World gen 17.8-18.3 s headless in the view harness (unchanged by this lane; the 22.8 s outlier was a
  loaded machine). `[terrain] build stages ms: heightfield 2510, t3d_setup 928, t3d_maps 3316,
  t3d_import 144, ground_cover 4078 (316 792)`. architecture / feature / edge tests pass.

## Findings for the other lanes
- **Ledge tops are dark because their normals point DOWN, not because of the sun or shadows (ROCKS).**
  `cliff_coast_b` ledge top 1048,588 = `#242f41` H217 V0.25 (ambient-only navy) over a face of V0.53 at
  elevation 32, and it did not move with `shadow_enabled = false` (still `#1f2b43`) nor with the bias
  change. A `rock.gdshader debug_mode 3` render (world normal as colour) shows those tops **magenta**
  (`wn.y ~ -1`) while the pale tops are yellow-green (`wn.y ~ +1`): the horizontal step / ledge faces of
  the stepped pillars (`_cliff_pillar steps`, RockGen) are wound inside-out or have flipped normals, so
  they get no sun at all. Nothing in LOOK can lift them; fix the winding / normals in `rock_gen.gd`, and
  the critique's item-1 sky-fill will then land on real up-facing normals.
- Lit limestone still reaches V0.9 on narrow west slivers (islets 1250,320; pillar 700,650 V0.84):
  `LIMESTONE_TINT 0.9` albedo under a 1.4 sun — ROCKS item 2 (`-> (0.84,0.76,0.62)`).
- The green skirt is H193 rather than the ref's H160: at 150 m the fog is ~2/3 of the rendered water,
  and the fog is blue; a warmer fog would move it but flattens the pillars (r2 finding). It is now
  darker than the open water beside it (V0.29 vs 0.32), which is the read that mattered.
- Surf-zone HF std (0.053) is dominated by the lit rock edges in that rectangle, not foam (foam alone is
  soft clumps now — look at the 450-1250 x 560-900 crop).
- The sky's upper-right sits at H226 (target >= 235): the pink lobe is `#c4b0bb` x 0.12 over a blue-grey
  base; a pinker `sky_glow_color` (`#c9adb8`) or mul 0.45 would reach it, at the cost of the S 0.13 we
  have now. Left where the region S / V match.
