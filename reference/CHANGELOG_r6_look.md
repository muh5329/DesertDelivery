# r6_look — round-6 (final) LOOK lane (critique items 1, 4, 5, 8, 12)

Files: `world/kit/world_kit.gd` (`Atmosphere`, `_build_environment`, `_build_sea`), `world/kit/sea.gdshader`.
Rock / terrain / foliage / island files untouched. Sun unchanged (yaw -40, el 36, `#ffe2c6`, 1.4).
Two render cycles (c1, c2) on cliff_coast / cliff_coast_b / cliff_arch / villa; c2 is what is committed.

## What changed
- **Item 1, horizon:** `ground_horizon_color` now comes from `A.sky_horizon` (the separate `ground_horizon`
  entry is gone — it had drifted to `#68a0da` under a `#70a0d8` sky and drew the 4-px cyan line);
  `sky_horizon #70a0d8 -> #6898c6` (same hue in as r5 but V0.78 instead of 0.85, the r5 value was brighter
  than `sky_top`); `sea_horizon_gain 1.0 -> 0.82`; sea plane `16000 -> 40000 m` so it always reaches the
  20000 m far plane (no z-fighting seen: the abyss plane stays 16000 and sits 14 m under).
  c1 used `#6892c6` (H213 in): the rendered sky moved from H210 to H213 and fell out of the ref's
  H180-210 pale-blue score bin (cliff_coast pale-blue 21 % -> 12 %); `#6898c6` is H209 in and it came back (26 %).
- **Item 4, foam collar + green skirt (`sea.gdshader`):** `foam_color (0.82,0.81,0.77)`, `foam_emission
  0.5 -> 0.7`, `foam_opacity 0.7 -> 0.9`, `foam_depth 0.4 -> 0.7`, solid-ring term `0.35 -> 0.7`,
  `whitecap_threshold 0.95 -> 0.93`; `col_teal (0.07,0.20,0.16) -> (0.06,0.19,0.12)`, `teal_amount 0.5 -> 0.6`.
- **Item 5, upper sky / clouds:** `sky_zenith #8fa8cc -> #84a4d0` (c1 tried `#7f9fd0`, H216: same bin-edge
  problem as above), `sky_band_deg 13 -> 11`, `sky_zenith_deg 28 -> 24`, `sky_energy 1.45 -> 1.38`,
  `cloud_mul_edge (0.99,0.97,0.99)`, `cloud_base (0.72,0.70,0.80)`.
- **Item 8, fog energy:** `1.18 -> 1.22` (c1 at 1.27 cost villa 0.018 and cliff_coast 0.014 — the H210-240
  S0.5-0.67 V0.33-0.5 water bin grew 3.5 % and the villa lost its H180-210 far bin; 1.22 keeps villa flat).
- **Item 12:** `sparkle 0.35 -> 0.22`, `vignette 0.16 -> 0.10`, `fog_height_density 0.028 -> 0.022`.
- Not done: item 7's `ambient_color` request (GROUND's call, no cycles left to verify the arch face S >= 0.18).

## Measured (compare.py; PIL on 1600x900)
| | r5 base | c1 | **c2 (committed)** | target |
|---|---|---|---|---|
| cliff_coast / coast_b / arch / villa | 0.636 / 0.519 / 0.614 / 0.636 | 0.622 / 0.528 / 0.595 / 0.618 | **0.629 / 0.528 / 0.602 / 0.635** | >= 0.64 / 0.55 / — / >= 0.635 |
| coast_b rows 395-450: S bump row | rows 408-411 S0.42 (line) | none | **none**, sky V0.76 -> sea V0.71 step 0.05 at row 411 | no bump, step >= 0.05 |
| cliff_coast y270 sky V / arch y360 V | 0.75 / 0.76 | 0.72 / 0.73 | **0.71 / 0.73** | <= 0.74 / <= 0.76 |
| coast_b sky S p50 / p98 / H250-300 | 0.13 / 0.83 / 9.2 % | 0.20 / 0.80 / 3.5 % | **0.19 / 0.79 / 1.7 %** | >= 0.17 / <= 0.73 / — |
| coast_b lilac bin (H210-240 S<.17 V.67-.83) | 34 % | 22 % | **26 %** | ref 4.8 % |
| coast_b cloud 1000,150 vs sky beside | V0.80 vs 0.77 | 0.79 vs 0.75 | 0.79 vs 0.75 (cloud is bluer, not lighter in the mass) | cloud <= sky + 0.01 |
| coast_b corner 40,40 vs 800,40 | 0.69 vs 0.78 | 0.72 vs 0.78 | **0.72 vs 0.78** | >= centre - 0.06 |
| far islet 1550,320 | `#606c81` V0.51 | V0.55 | **`#65728a` S0.27 V0.54** | V0.56-0.64 |
| right sky column y5 -> y240 hue | 240 -> 210 | 240 -> 213 | **233 -> 209** | >= 235 -> <= 215 |
| cliff_coast pale-blue bin (H190-215 S.17-.35) | 21 % | 12 % | **26 %** | >= 25 % |
| open water 1200,700 / V>0.85 share | `#283d59` / 0.31 % | `#29405e` / 0.26 % | **`#263d5a` / 0.27 %** | +-0.03 / <= 0.08 % |
| hero wall 120,650 / arch face 700,330 | `#837167` / `#4b5465` S0.25 | — | **`#88766b` V0.53 / `#4a5365` S0.27 V0.40** | within 0.02 / S >= 0.18 |
| villa bg outcrops V p50 / mid cyan | 0.49 / 6.3 % | 0.52 / 6.6 % | **0.52 / 6.4 %** | >= 0.58 / no +3 % |
- Surf crop (420-900 x 560-900) at 2x: a continuous 2-4 px grey-white line at every water-line boulder
  foot and a green (not teal) skirt round the stacks; coast_b horizon crop: one clean step, no cyan row.
- World gen 10-12 s (20.5 s on the first run after the shader edit = shader compile, 6.6 s r5 base);
  architecture / feature / edge tests PASS (0 failures).

## Still missing
- **cliff_coast 0.629 (-0.007)**: the remaining cost is the H210-240 S0.5-0.67 V0.33-0.5 water bin (+2.6 %):
  the far sea now sits under the sky as item 1 asks, and our frame is ~35 % water against the ref's 12 %,
  so the darker far sea lands in an already over-full bin. It is the intended look; reverting
  `sea_horizon_gain` to 1.0 would buy the points back and the cyan convergence with them.
- The open-water glitter share (0.27 %) barely moved at `sparkle 0.22` — the V>0.85 pixels are the
  whitecaps at 0.93 as much as the glints; `whitecap_threshold 0.95` restores the r5 share if wanted.
- Far islet V0.54 (target 0.56-0.64) at fog_energy 1.22; 1.27 reaches it but costs villa 0.018.
- coast_b sky p98 0.79 (target 0.73): the brightest cloud cores; `cloud_flat` / the core multiplier next.
- The foam-share metric in the critique (water-adjacent V0.65-0.82 S<0.2) was not re-measured
  numerically this round (the crop was judged by eye); the r5 bright-foam bin method is in CHANGELOG_r5_look.
