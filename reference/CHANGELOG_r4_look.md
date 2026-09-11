# r4_look — round-4 LOOK lane (critique items 2-sun/ambient, 3-fog colour, 6-sea skirt, 8-lift_black, 11-clouds, 12-fog, 14-foam, 15-villa horizon)

Files: `world/kit/world_kit.gd` (`Atmosphere`, `_build_environment`, `_cloud_cover_texture`, `_build_sea`,
`SEA_NAVY`), `world/kit/sky.gdshader`, `world/kit/sea.gdshader`. Rock / terrain / foliage / island files
untouched (the rock shader's `shade_fill` / `sky_fill` are ROCKS' — see "for the other lanes").

## What changed
- **Sun (fixed for the round, commit `7de60dd`)**: `sun_yaw_deg -120 -> -150`, `sun_elevation_deg 32 -> 36`,
  `sun_color #ffd6b0 -> #ffe2c6` (S 0.31 -> 0.22). The sun stands ahead-left of the `cliff_coast` camera,
  shadows fall toward it, the boulder flanks toward the camera go dark (760,640 top V0.70 over a flank of
  V0.41 — item 10's half). ROCKS tunes the palette against this sun.
- **Ambient / shade**: `ambient_energy 0.3 -> 0.4`, `ambient_sky_contribution 0.25 -> 0.4`, `ambient_color
  #95968d -> #a3a6b2`. `lift_black #0a0c12 -> #0e0d0c` (neutral: villa shadows no longer navy / maroon).
  `exposure 0.57 -> 0.55` (the ambient lift floated the frame).
- **Fog / aerial perspective**: `fog_color #7190b2 -> #7d94b0`, `fog_density 0.0026 -> 0.0030`,
  `fog_energy 1.15 -> 1.22`, `fog_height 9 -> 12`, `fog_height_density 0.022 -> 0.028`. Far stack 1400,320
  `#667e9c` S0.35 -> `#6b7c95` S0.28 V0.58 under a V0.68 sky; the 250 m stack lost its blue cast
  (`#977e7d` -> `#b1968b`; it stays tan because its albedo is tan — ROCKS item 1).
- **Sky** (`sky.gdshader`): the glow is now two colours — the narrow lobe toward the sun is PEACH
  (`sky_glow_color #d4b8a8`, `glow_power 4 -> 2.5` so it reaches 60 deg off the sun), the wide
  azimuth-independent cast stays lilac (`sky_glow_wide_color #c4b0bb`, `mul 0.35 -> 0.28`). `sky_top
  #a6b0c8 -> #96b3ce` (pale blue high). The sea shader's rebuilt horizon carries both lobes
  (`sky_glow_wide_srgb`, `sky_glow_power`), so the far sea still meets the sky with no step.
- **Clouds**: they were multipliers < 1 (invisible dark smears). Now `cloud_mul_edge (1.12,1.03,0.98)`,
  `cloud_mul_core (1.08,0.97,0.95)`, `cloud_base (0.78,0.71,0.75)`, `cloud_flat 0.7`, `cloud_cover 0.7`,
  and the cover ramp in `_cloud_cover_texture` 0.30 -> 0.22 wide so the bank has a solid pink core. The
  bank at 400-1000 x 20-120 is now visibly lighter and pinker than the sky beside it.
- **Sea** (`sea.gdshader`, `SEA_NAVY`): skirt `col_teal (0.06,0.13,0.025) -> (0.07,0.20,0.16)`,
  `col_turquoise -> (0.08,0.20,0.17)` (blue back in), `teal_metres 15 -> 9`, `teal_amount 0.9 -> 0.75`,
  `alpha_shallow 0.75 -> 0.6`; `SEA_NAVY x 1.43` total (open water 1200,700 `#203550` V0.31 -> `#2e415b`
  V0.36, ref `#2a3d5e`); `reflect_amount 0.22 -> 0.28`; `swell_amount 0.4 -> 0.3` (the bands read as
  camouflage). Foam: `foam_depth 0.9 -> 0.6`, `foam_clump_metres 3.5 -> 2.0`, ring threshold 0.5 -> 0.6
  (half the collar open), streaks back to x1.0, `foam_color (0.95,0.94,0.90)`, `foam_emission 0.8`,
  `foam_opacity 0.85` — lace lines along the rock feet with trails, not discs. (First try at
  `(0.86,0.84,0.80) x 0.6` was grey wisps: the ref's surf LINE is white, only the trails are grey.)
- **Villa horizon**: `horizon_fade_start / end 250 / 1400 -> 400 / 2000`, `sea_horizon_gain 1.0` — the sea
  behind the villa is `#6d798f` V0.56 under a `#9aa1b3` V0.70 sky (was `#b0abb6` V0.71, one slab with it).

## Measured (compare.py; PIL medians / regions on the 1600x900 renders; ref = `ref_cliff_coast.png`)
| | r3 merge (before) | c1 (sun + first pass) | **c4 (final)** | target |
|---|---|---|---|---|
| cliff_coast / _b / arch / villa | 0.590 / 0.576 / 0.574 / 0.579 | 0.620 / 0.545 / 0.608 / 0.602 | **0.619 / 0.567 / 0.609 / 0.598** | >= 0.62 / >= 0.56 |
| (c3, `sky_top #9ab2cf`, fog_energy 1.15, SEA_NAVY x1.3, reflect 0.22) | | | 0.622 / 0.559 / 0.599 / 0.603 | either is within the run-to-run noise (foam / swell TIME) |
| cliff_coast frame p1 / p50 | 0.123 / 0.414 | 0.150 / 0.399 | 0.150 / 0.400 | 0.10 / 0.35 |
| ref-shade bin H210-240 S.17-.33 V.33-.67 (frame) | 1.6 % | 7.2 % | 7.3 % | >= 8 % |
| tan bin H0-30 S.33-.5 V.67-.83 | 6.2 % | 1.4 % | 1.2 % | 0.7 % |
| rock band cool-shade share H200-240 | 34 % | 35 % | 34 % | ~45 % |
| arch interior 790,470 | `#334157` V0.34 S0.41 | `#454b58` V0.35 S0.22 | `#474e5c` V0.36 S0.23 | V >= 0.42 (needs shade_fill, ROCKS) |
| cliff_coast_b lit face 1230,700 / stack shade 430,620 | V0.68 / `#374255` V0.33 | V0.71 / `#4a4e58` V0.35 | V0.70 / V0.36 | >= 0.55 / >= 0.40 |
| villa bg outcrops 1200,80 | `#445061` S0.30 V0.38 | `#5f6169` S0.10 V0.41 | S0.10 V0.40 | S <= 0.20 (ok), V >= 0.55 (ROCKS shade fill) |
| far stack 1400,320 | `#667e9c` S0.35 V0.61 | `#687892` V0.57 | `#6b7c95` S0.28 V0.58 | <= 0.65, under the sky |
| open water 1200,700 / region p10/50/90 | `#203550` V0.31 / .14/.18/.24 | V0.35 / .17/.22/.28 | `#2e415b` V0.36 / .18/.22/.28 | V0.35 / .18/.26/.47 |
| surf-zone teal H170-205 share / median V | 25 % / 0.23 (`#1d383a`) | 7.3 % / 0.31 | 15 % / 0.32 | 5-10 % / 0.32-0.38 |
| dark-green moat bin H150-180 S.33-.5 V.17-.33 | 4.3 % | 0.0 % | 0.2 % | 0 |
| foam-ish (V>.72 S<.25, surf zone; includes lit rock) | 4.5 % | 2.1 % | 2.4 % | ~1.6 % (ref, same measure) |
| sky region S / V | 0.14 / 0.75 | 0.13 / 0.75 | 0.14 / 0.73 | <= 0.17 / 0.73 |
| pale-blue sky bin H190-210 S.17-.33 | 0.3 % | 0.9 % | 0.9 % | >= 1.5 % (not reached: the lilac cast holds the hue at 217-221) |
| villa sea 200,120 vs sky 200,40 | V0.71 vs 0.75 | V0.55 vs 0.70 | V0.56 vs 0.70 | 0.60-0.66, >= 0.04 under |
| coast_b horizon max one-row step (x 200) | — | 0.014 | — | <= 0.02 |
- World gen 7.7-7.8 s headless (11-16 s in the view harness on the loaded box); architecture / feature /
  edge tests pass (0 FAIL).

## For the other lanes / still missing
- **Shade rock is still V0.35 and the arch face still lit tan (ROCKS).** The rock shader compresses the
  sun to `sun_gain 0.16`, so a face out of the sun is albedo x (ambient + `shade_fill 0.08`): the
  environment's ambient lift moved the arch interior from V0.34 to 0.36 only. `shade_fill 0.08 -> 0.30`
  with `shade_fill_color #8f99bd`, `sky_fill 0.55 -> 0.75 / #a9b6cf`, and the item-1 palette are what put
  the shade mass at `#535d73` V0.45 and take the tan out of 700,330 / 1100,450. Ref-shade bin 7.3 % -> the
  8 % target needs that.
- The pale-blue high-sky bin stays at 0.9 % (target 1.5 %): the wide lilac lobe (0.28 x 0.35) holds the
  zenith hue at ~218. A lower `sky_glow_wide_color_mul` (0.2) reaches it at the cost of the pink that
  the sky region's histogram wants — left at the histogram-preferred balance.
- Surf-zone teal share is 15 % (ref 8.8 %): the 9 m halo is on the wide side, but at 7 % (c1, 8 m x 0.6)
  the skirt vanished under the fog by eye. Judged by the crop, not the share.
- Villa sea V0.56 (target 0.60-0.66): `fog_energy 1.3` got it to 0.56 too and cost the villa / arch colour
  terms; it needs a brighter fog *colour* only for the sea, i.e. a sea-only `horizon_gain > 1` — not done.
- cliff_coast p1 0.15 (ref 0.10): the darkest pixels are the water; with the water lifted to the ref's
  open-water value the frame's p1 cannot reach 0.10 without darkening the rock contacts (ROCKS `ao_min`).
