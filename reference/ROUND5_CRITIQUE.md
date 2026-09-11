# Round 5 critique — r4 merged renders vs `ref_cliff_coast.png` / `ref_villa_vineyard.png`

Judged: `/root/rounds/r4/cliff_coast.png` (0.617, r3 0.590), `cliff_coast_b.png` (**0.560, r3 0.576 — regressed**),
`cliff_arch.png` (0.601, r3 0.574), `villa.png` (0.604, r3 0.579). Numbers are PIL medians of 16–24 px patches
(sRGB, H/S/V) or "region" stats (median, luminance p10/p50/p90, std, FIND_EDGES energy) on the 1600×900 renders;
the reference is resampled to 1600×900 so coordinates are comparable. Bins are % of a region's pixels.
Lanes: **LOOK** (`world_kit.gd` `Atmosphere` / `_build_environment` / `_build_sea`, `sky.gdshader`,
`sea.gdshader`), **ROCKS** (`rock_gen.gd`, `rock.gdshader`, `_cliff_wall` / `_cliff_pillar` / `_sea_arch` /
`_sea_stack` / `_islet` / `_boulder_apron`, `_gen_sea_cliffs`), **GROUND** (`terrain.gd`, `foliage.py` /
`textures.py`, `leaf.gdshader` / `TREE_LOOK`, scatters and halos in `island.gd`, delivery beacon).

Generation on `master`: **8.2 s** in the view harness (`[game] world generated in 8198 ms`), 7.7–8.0 s headless.
Budget stays **< 18 s**; each lane may spend ≤ 2 s. Tests (`architecture_tests`, `feature_tests`, `edge_tests`)
must stay green; props ≥ 6 m from road centrelines and off delivery rings.

## Three scratch experiments (calibration only; `/tmp/c5/exp{1,2,3}`, not committed)

| | cliff_coast | coast_b | arch | villa | frame p50 | ref-shade bin* | rock band warm / cool / grey |
|---|---|---|---|---|---|---|---|
| ref | — | — | — | — | 0.36 | 13.7 % | 8 / 74 / 12 % (warm S0.20 V0.62, cool S0.26 V0.44) |
| r4 master | 0.617 | 0.560 | 0.601 | 0.604 | 0.40 | 8.5 % | 38 / 33 / 25 % (warm S0.15 **V0.70**, cool S0.32 V0.41) |
| exp1: ROCKS `shade_fill 0.80→0.30`, `sky_fill 0.75→0.50`, `sun_gain 0.13→0.35` | 0.613 | 0.561 | — | — | 0.38 | 8.6 % | arch front got *brighter* (V0.84): it is sun-square, not shaded |
| exp2: exp1 + `sun_yaw_deg −150→+65` (sun straight ahead) | 0.574 | 0.563 | 0.526 | 0.602 | 0.31 | 13.3 % | 2 / 68 / 27 % — everything shaded, grey, no lit face |
| **exp3: exp1 + `sun_yaw_deg −150→−40`** (sun 75° right of the view axis, ahead-right) | **0.633** | 0.547 | **0.631** | — | **0.35** | 11.9 % | 11 / 61 / 24 % (warm S0.18 V0.67, cool S0.22 V0.36) |

\* frame share of H210–240 S0.17–0.33 V0.33–0.67 (the reference's sky-lit shade mass).
exp3 is the best `cliff_coast` / `cliff_arch` this project has produced and its rock histogram is within a few
points of the reference on every bin. Its cost is `coast_b` (−0.013), which looks north while `cliff_coast` looks
ESE (130° apart): no single sun side-lights both. The brief makes `cliff_coast` the target — take the sun that
serves it and fix `coast_b` through its own faults (items 2, 4, 6).

---

## Ranked gaps

### 1. The sun stands BEHIND the `cliff_coast` camera: the r4 "sun ahead" move went the wrong way — **LOOK**
- **Evidence:** `Basis.from_euler((−36°, −150°, 0))` gives a light direction of (0.40, −0.59, 0.70), i.e. the sun
  sits at (−0.40, 0.59, **−0.70**). The camera looks along (0.52, 0.86): dot −0.81, the sun is 144° off the view
  axis, behind-left. The comment in `world_kit.gd` (`(-sin(-yaw)*cos el, sin el, -cos(-yaw)*cos el)`) has the sign
  of z wrong. Result: the arch front (facing the camera) is the *lit* face — 700,330 `#b3a19a` V0.70 and with
  more sun (exp1) V0.84 — while the reference arch front is sky-lit shade `#525c72` V0.45 (620,260 `#6e758b`
  V0.55, 830,240 V0.45, 960,300 V0.41); the reference's lit faces are the *left* cliff (280,240 `#9f8a7a` H25
  S0.23 V0.62) and the tops; shadows fall toward the camera, boulder camera-sides are dark (`#675554` V0.40).
  Ours: hero wall (faces east) in shade `#6d5f5b` V0.43, arch front lit, shadows fall away from the camera.
- **exp3 (`sun_yaw_deg −40`, el 36):** arch face 700,330 `#565861` H229 V0.38 (shade), hero wall 120,650 `#917966`
  H25 S0.30 V0.57 (lit, ref `#9f8a7a`), near stack lit side `#917b6e` S0.24 V0.57 / shade side `#605e60` V0.38
  (ratio 1.5, ref 1.5–2.2), 250 m stack `#646874` V0.45 under a V0.66 sky (was `#bba9a3` V0.73 *above* the sky),
  frame p50 0.35 (ref 0.36), p10 0.11.
- **Fix:** `sun_yaw_deg −150 → −40` (try −35…−50; −60 is the r2 sun, never re-tested since the RockGen normals
  were fixed in r3), keep `sun_elevation_deg 36`, `sun_color #ffe2c6`; fix the comment. Do this **first** and
  announce it; ROCKS and GROUND tune under it. Because the sun now faces the camera, `sea.gdshader` `sparkle 0.5`
  and `sun_energy` will draw a glitter path — cap it (`sparkle 0.35`) if the surf zone laces up.
- **Verify:** arch face 700,330 in H205–235 S0.15–0.30 V0.38–0.50; hero wall 120,650 H20–30 S0.22–0.32 V0.52–0.62;
  ref-shade bin ≥ 11 %; `cliff_coast` ≥ 0.63, `cliff_arch` ≥ 0.62; `villa` ≥ 0.60 (villa forward (−0.53,−0.85):
  the sun lands behind-right, the house front is lit as in the villa reference).

### 2. Rock is lit by its own emission, not by the sun: chalk-white, flat, no lit/shade — **ROCKS**
- **Evidence:** `rock.gdshader` `EMISSION = alb × (sky_fill_color × sky_w × 0.75 + shade_fill_color × side_w × 0.80)`;
  on a vertical face that is alb × (0.59, 0.65, 0.82) while the sun term is at most alb × 1.4 × `sun_gain 0.13`
  = 0.18 × alb. Lit:shade ≈ 1.2 (ref 1.5–2.2) and the emission ignores cast shadows. Measured: arch block region
  (560–980 × 250–620) `#9b8a82` **S0.15 V0.61**, p10/50/90 0.29/**0.56**/0.74 (ref arch block `#525a6c` S0.25
  V0.42, 0.29/0.35/0.65); rock band V > 0.6 share **42 %** (ref 24 %); warm rock S0.15 (ref S0.20–0.23); the
  arch front reads pink-chalk (H13–17) because the grade's `lift_white #f5e9ea` is the only tint left.
  `coast_b` centre wall (600–1200 × 360–720): lumstd 0.147 → **0.095**, edge 0.083 → **0.047** — the blocks
  became paper cut-outs, this is the biggest single cause of the coast_b texture regression (0.499 → 0.449).
- **Fix (`rock.gdshader`):** `shade_fill 0.80 → 0.35`, `shade_fill_color (0.52,0.58,0.76) → (0.50,0.58,0.78)`
  (`#7f94c7`, the shade must keep S ≥ 0.2 — exp3 shade faces were S0.09–0.16, too grey); `sky_fill 0.75 → 0.60`
  but only on tops: `sky_w = mix(0.35, 1.0, up_w) → mix(0.12, 1.0, up_w)` (exp3's 0.50 dropped ledge tops to
  V0.36 — tops must stay the palest rock); `sun_gain 0.13 → 0.35` with `sun_wrap 0.15 → 0.10`; put the warmth
  back in the albedo, not the sun: `LIMESTONE_TINT (0.57,0.53,0.47) → (0.60,0.55,0.47)` (`world_kit.gd:473`),
  `tex_saturation 0.45 → 0.55`. Retune `_rock_alt` / talus siblings with the same deltas.
- **Verify (under the item-1 sun):** lit face S0.20–0.26 V0.58–0.68; shade face H210–235 S0.20–0.30 V0.40–0.48;
  ledge top 560,500 ≥ 1.2 × the face under it; rock band V > 0.6 share 20–28 %; `coast_b` centre-wall lumstd
  ≥ 0.13 and edge ≥ 0.07; whole-frame tan bin ≤ 1 %.

### 3. The foreground tree in `cliff_coast` is a black silhouette over 1/6 of the frame — **GROUND**
- **Evidence:** top-left 500 × 500 region `#101f16` p50 **0.10**, **49 % of its pixels V < 0.12** (ref 1 %,
  region p50 0.34); canopy patches `#0c1412` V0.08, `#0c0d12` V0.07, `#142512` V0.15. Ref foreground foliage:
  `#3a3d25` V0.25, `#212c36` V0.21, canopies never below V0.18. Texture cell (0,0) is +140 ×10⁻³ (a hard rim
  round a black blob), layout row 0 is our worst row. In r3 this tree was not in the frame (the r4 crest-scatter
  position hash moved it in). It is `TREE_LOOK["umbrella"]` `#242e1c` with `leaf.gdshader`
  `ambient_light_disabled` and the sun behind it (backlit) → `col_dark × shade_warm` and nothing else.
- **Fix:** (a) `leaf.gdshader` a value floor: `ambient_floor` for the umbrella material ≥ (0.40, 0.42, 0.26) and
  `col_dark #242e1c → #2e3a22` (rendered V ≥ 0.18 on the shade side); the cypress/vine materials already carry a
  floor. (b) Either exclude the 40 m radius in front of `cliff_coast` / `cliff_arch` from the crest tree scatter
  (`island.gd` `_umbrella_variants(0.62, "umbrella")` call at ~593, a `Rect2` guard like the sea-cliff rect) or
  scale that tree to 0.6 so its crown clears the top of the frame. The reference does have a dark tree at the
  top-left — keep one, at V0.2, covering ≤ 8 % of the frame.
- **Verify:** top-left 500 × 500: V < 0.12 share ≤ 5 %, p50 ≥ 0.25; no canopy patch below V0.16; cell (0,0)
  within +40 ×10⁻³ of the ref.

### 4. The sky is one flat grey-lavender field; the reference is a graded lilac-to-blue sky with a *cooler, more saturated* horizon — **LOOK**
- **Evidence (right sky column x1250–1600, y 5→285):** ours hue **216→219** (constant), S 0.15→0.26, V 0.68→0.66;
  region L std **0.030**, hue p10/p90 216/223. Ref: hue **257→210**, S 0.13→0.30, V 0.69→0.71 then 0.63 at the
  far headland; L std 0.095, hue p10/p90 209/254; pale-blue bin (H190–215 S0.17–0.35) **35 %** of the sky box
  (ours 7 %), pink bin (H250–330) 13 % (ours 5.6 %). My first impression "warm graded horizon" is **refuted**:
  the ref's warmth is at the *top* (lilac `#a29bb0` H257 and the pink cloud bank), the band above the horizon is
  the bluest, most saturated part (`#7a95b1` H210 S0.30). The clouds are the only pink: in `coast_b` the cloud
  bank is `#c9c1cd` **V0.80–0.85 S0.06** over a `#c3c8d9` V0.85 sky (ref sky V0.72–0.75) — a bright pink-grey
  slab across the top third; coast_b layout rows 0–2 went 16/19/19 → 19/22/25 ×10⁻², the water under it went
  `#59616f` V0.44 S0.22 (r3 `#3c4a5c` V0.36 S0.38, ref S0.54) by reflecting it.
- **Fix (`Atmosphere` / `sky.gdshader`):** `sky_top #96b3ce → #aaa6c2` (H250 S0.14: the lilac zenith),
  `sky_horizon #7790b2 → #6a8db8` (S0.42 → rendered ~S0.30 at H212), `sky_curve 0.35 → 0.5` so the blue band
  sits low; `sky_glow_wide_color_mul 0.28 → 0.20` and move the pink into the clouds: `cloud_mul_core (1.08,0.97,
  0.95) → (1.02,0.95,0.97)`, `cloud_mul_edge → (1.04,1.00,1.00)`, `cloud_base (0.78,0.71,0.75) → (0.74,0.69,0.75)`,
  `cloud_cover 0.7 → 0.5` (the coast_b slab). `sea.gdshader` `reflect_amount 0.28 → 0.20` and `sky_zenith` toward
  the new lilac so `coast_b` water returns to S ≥ 0.35.
- **Verify:** right sky column hue at y=5 ≥ 240 and at y=240 ≤ 215; S at y=240 ≥ 0.26; sky box L std 0.06–0.10;
  pale-blue bin ≥ 20 %; `coast_b` sky p98 ≤ 0.78, cloud patch 700,60 lighter than the sky beside it by 0.01–0.04
  V, never > 0.80; coast_b water 200,650 S ≥ 0.35 V 0.34–0.40.

### 5. Villa ground: orange soil, chalk-white gravel, vine rows brighter than their soil — **GROUND**
- **Evidence (lower frame, y 300–864):** orange bin (H5–28 S > 0.45 V0.35–0.7) **8.3 %** (ref 1.3 %); pale bin
  (V > 0.6 S < 0.3) **13.2 %** (ref 4.4 %); straw bin (H30–60 S0.3–0.7) **7.1 %** (ref **39 %**). Soil patch
  950,720 `#895130` H21 S0.65 V0.54 (ref vine soil `#724d2d` H27 S0.60 V0.45 — same hue, ours is 0.1 V brighter
  and it covers whole slopes instead of 1 m strips); ground 1000,600 `#b79c89` V0.72 S0.24, disc `#bba18b` V0.73
  (ref lane `#a37948` **S0.55** V0.64 — the brightest ground in the ref is *saturated* straw-gold, never grey-white).
  Vineyard region (0–450 × 250–560): H25–70 20 % (ref 71 %), H170–260 23 % (ref 1 %); rows `#726946` V0.47 sit
  *above* their soil `#5e5b3d` V0.40 — the ref is the inverse (rows `#333415` V0.20 dark olive on soil V0.45–0.53).
- **Fix (`terrain.gd` `_build_texture_assets`, vineyard bands, `island.gd` vines):** `Soil` tint `(0.92,0.70,0.36)
  → (0.80,0.62,0.36)` and confine it to the row strips (bands 1/2 back to straw `Grass`, the r4 "brown-straw"
  bands are the orange slopes); `Gravel (0.88,0.80,0.66) → (0.86,0.74,0.50)` and `Dirt (1.0,0.93,0.80) → (0.98,
  0.86,0.62)` (lane S ≥ 0.40); disc stamp at `#a3844f`; the villa colour-map "white" patches (the `Scrub` /
  `Sand` islands round the hub) → `Grass` at `(1.0,0.90,0.55)`. Vines: card tint `(1.0,0.97,0.66) → (0.80,0.78,
  0.42)`, `ambient_floor (0.62,0.58,0.28) → (0.40,0.38,0.18)`, `shade_warm → (0.55,0.52,0.26)`; rows must render
  V0.25–0.35 on soil V0.42–0.50.
- **Verify:** lower-frame orange bin ≤ 3 %, pale bin ≤ 6 %, straw bin ≥ 25 %; vineyard region H25–70 ≥ 45 %,
  H170–260 ≤ 8 %; row patch 150,430 V ≤ 0.36 and ≥ 0.08 below the soil patch 120,530; lane 700,640 S ≥ 0.40.

### 6. `cliff_coast_b` regression (0.576 → 0.560): what did it — **ROCKS + LOOK**
- Texture-energy 0.499 → 0.449 and layout 0.850 → 0.826, colour +0.012. Per-cell (512 × 288 grid, vs ref
  ×10⁻³): rows 2–4 cols 3–5 (the centre wall and apron) went **+59/+17/−37 → −11/−66/−85** and **−6/−37/−3 →
  −29/−85/−35**. Causes, in order: (a) item 2 — the rock pieces lost their lit/shade and joint contrast
  (centre-wall lumstd 0.147 → 0.095); (b) the sun move — the Terrain3D steep-slope wall behind the blocks faced
  the r3 sun (`#62595b` lumstd 0.154) and now faces away (`#454953` H222 lumstd 0.092, V0.30 flat); with
  exp3's sun it is `#a58f7f` V0.65 lumstd 0.161 — lit, but then *everything* in coast_b is lit (frame p50 0.60,
  ref 0.36) because that camera has the sun behind it; (c) item 4 — the bright cloud slab and the washed
  water. Under exp3 the coast_b texture term recovers to 0.477; colour drops.
- **Fix:** items 1, 2, 4; then (ROCKS) the `coast_b` massif needs shade of its own: cast shadows are the only
  thing that can give it — `shadow_max_distance 260` reaches it (camera 180–260 m), so keep `directional_shadow`
  on the rock pieces and make sure the stacked block pieces (`_cliff_wall` "blocks", 480–760 × 300–700) do not
  have `cast_shadow` off; the terrain wall's `Cliff` texture `(1.0,0.97,0.90)` → `(0.95,0.90,0.82)` so a fully
  lit terrain face lands V ≤ 0.62.
- **Verify:** `coast_b` ≥ 0.565; centre-wall lumstd 0.13–0.17; frame p50 0.45–0.55; block face 1050,650
  distinct from the terrain wall behind it by ≥ 0.08 V.

### 7. Villa background outcrops are dark mid-grey cubes under a pale sky — **ROCKS + LOOK (sun)**
- **Evidence:** region 900–1600 × 0–200 `#5c626b` H222 S0.17 **V0.43**, V > 0.55 share **10 %** (ref bg region
  `#8eadc7` V0.78, V > 0.55 share 91 %); patches 1200,80 `#5e616f` V0.44, 1400,100 `#3f4a5a` V0.35. They are
  250–400 m away; the fog reaches the villa sea at 600 m (V0.56), so the albedo under it is dark shade rock
  facing away from the −150 sun. Exp2/exp3 not rendered for villa — with the sun at −40 (position (−0.52, ·,
  +0.62)) the south faces the villa camera sees are lit: re-measure first.
- **Fix:** after item 1, if still < V0.55: `fog_color #7d94b0 → #8398b3` and `fog_density 0.0030 → 0.0033`
  (LOOK); on the outcrop pieces (`_gen_*` for the massif behind the villa) `sky_fill` per material 0.6 → 0.7
  for pieces > 200 m from any spot (ROCKS).
- **Verify:** villa 1200,80 and 1000,120 V ≥ 0.55, S 0.15–0.30, H 205–225; region V > 0.55 share ≥ 60 %.

### 8. Aerial perspective: mid-distance rock is brighter than the sky, far rock is neutral grey — **LOOK (+ item 2)**
- **Evidence:** 250 m stack 1100,450 `#bba9a3` **V0.73 above the sky's 0.66**; far stacks 1160,250 V0.65 S0.05,
  1560,300 V0.61 S0.05, far-right islet 1550,320 `#9f9699` H336 S0.05 (a pink-grey blot). Ref: far rock is
  always *under* the sky and *blue*: 1520,320 `#67809c` S0.33 V0.61 under sky 0.71, far headland `#425a7e` S0.47
  V0.49, far arch `#626b7c` S0.21 V0.49. exp3 already fixes the value (stack250 V0.45, far islet `#686e7d`
  S0.17 V0.49); the residual is saturation.
- **Fix:** `fog_color #7d94b0 → #7591b5` (S0.35, H213) with `fog_energy 1.22 → 1.18`; keep `fog_density 0.0030`;
  `fog_sun_scatter 0.22 → 0.15` (with the sun ahead of the camera the scatter term will bleach the far stacks
  toward the sun colour).
- **Verify:** 1100,450 V ≤ 0.55 and ≤ sky − 0.10; far islets 1160,250 / 1560,300 S 0.20–0.35, H 205–225,
  V 0.50–0.62; the near wall 120,650 unchanged within 0.03 V.

### 9. Stratification reads as brush smears on chalk, not fracture planes — **ROCKS**
- **Evidence:** left arch pillar (620–700 × 280–520) row-profile band amplitude p90 **0.078**, std 0.057;
  column-profile std 0.070. Ref pillar face (560–760 × 150–420): **0.009** / 0.029 / 0.027; ref left cliff
  0.008 / 0.028 / 0.039. The ref's beds are nearly invisible in value; its structure is 3–8 m fracture *planes*
  with ±0.05 steps and 1–2 px joint shadows. Ours: the 1 m facet chamfers (`facet_blend` ≥ 1.6 cells, crease AO
  0.65) render as diagonal dark smears 20–60 px long over a uniform pale base (arch crop at 2×: no plane, no
  course, smears). The far-LOD joints on the 250 m stacks are gone (good).
- **Fix (`rock_gen.gd` / `_cliff_pillar` / `_sea_arch` params):** crease AO on hero / arch pieces `0.65 → 0.40`
  and its width `facet_blend` 1.6 → 1.0 cells (a soft 0.6 m chamfer, not a 1 m smear); facets bigger and fewer:
  hero `facet_amp` 0.8–1.2 m @ 8–12 m → 0.6–0.9 m @ 12–18 m; the planes must differ by a *value step*, not a
  shadow: per-facet `COLOR.g` jitter ±0.05 (seeded per Worley cell); `bed_band 0.04 → 0.03`, keep
  `bed_line_strength 0.35`. With item 2's real sun the facets will also separate by lighting.
- **Verify:** pillar row-profile p90 ≤ 0.03, column-profile std ≤ 0.04; arch face region (620–900 × 280–420)
  lumstd 0.06–0.10; at 2× the arch crop shows ≥ 4 distinct planes per pillar and no diagonal smear > 30 px.

### 10. Foam is bright blobs; the reference's is grey lace and streaks — **LOOK (`sea.gdshader`)**
- **Evidence (surf zone):** bright foam (V > 0.78, S < 0.15) **0.56 %** of the zone (ref **0.11 %**); the
  collars at 440–560 × 700–900 and the `cliff_arch` apron are 10–25 px discs of `#e7ddd8`-class; the ref's foam
  is 1–3 px lines at V0.55–0.75 with 5–15 m streaks (its bright-foam bin is ~0). r3 had 3.5 % — r4 halved it,
  the remaining blobs are the `foam_depth 0.6` ring with `foam_emission 0.8`.
- **Fix:** `foam_color (0.95,0.94,0.90) → (0.88,0.87,0.84)`, `foam_emission 0.8 → 0.5`, `foam_opacity 0.85 →
  0.7`, ring `foam_depth 0.6 → 0.4` and clump threshold 0.6 → 0.68 (¾ of the ring open); streak term
  `foam_streak_metres 16 → 22` at ×1.2 so the trails carry the foam; `whitecap_threshold 0.94 → 0.95`.
- **Verify:** bright-foam bin 0.10–0.25 %; no foam blob wider than 8 px at 1600 × 900; foam median V ≤ 0.78;
  ≥ 3 streaks ≥ 40 px long visible in the surf zone.

### 11. Water: teal skirt still twice the reference's share; `cliff_arch` open water too dark — **LOOK**
- **Evidence:** teal (H170–205) share of the water in the surf zone **27 %** (ref 13 %; r3 46 %); `cliff_coast`
  open water `#2d3f56` V0.34 S0.49 (ref `#2a3a5c` V0.36 S0.54 — fine); `cliff_arch` water median V **0.28**
  (camera at 15 m, the same water) — the fresnel bias at the low camera drops the reflection.
- **Fix:** `teal_metres 9 → 6`, `teal_amount 0.75 → 0.6`; `fresnel_bias 0.04 → 0.07` (low-camera water keeps
  V ≥ 0.32); item 4's `reflect_amount 0.20` is the counterweight — measure both spots.
- **Verify:** surf-zone teal share 10–16 % with median V 0.32–0.38; `cliff_arch` water region V 0.31–0.36;
  `cliff_coast` 1200,700 `#2a3d5e` ± 0.03.

### 12. The bench under the arch is streaked brown dirt, not the pale road with ruts — **GROUND**
- **Evidence:** arch floor region (600–900 × 520–610) `#9f8878` H21 S0.20 V0.62, p10 **0.42**, lumstd 0.114,
  with dark chocolate streaks (`#877065` V0.53 at 700,560) running downslope — the `Dirt` / `Soil` blend on the
  bench under the arch reads as a wet mud fan; `cliff_arch` floor p10 0.33. Ref road `#988478` S0.20 V0.60 with
  p10 0.33 only at the rut *lines*, crown `#c4ad8f` V0.77; the ref bench is the brightest ground in the frame,
  with two 0.5 m ruts, a margin and 1–2 m scrub tufts. Not done for two rounds.
- **Fix (`terrain.gd` road / bench paint at the sea-cliff rect):** bench crown `Dirt` at `(1.0,0.90,0.70)` with
  the colour map at `#c4ad8f`, two `#9a8468` rut stripes ±0.9 m (0.5 m wide), a `#8f7658` margin 1 m each side;
  no `Soil` under the arch; tufts 8 / 100 m² of 0.8–1.5 m scrub × 0.7 tint inside `road_clear + 8`.
- **Verify:** floor region p10 ≥ 0.50, lumstd 0.06–0.09 outside the rut lines; ≥ 2 rut lines at 2×; no pixel run
  > 10 px of H15–25 S > 0.35 V < 0.5 on the bench.

### 13. Villa hub: still no walls, fences, shed; the lane is grey-cream — **GROUND (`island.gd` hub builder)**
- **Evidence:** ref frame std 0.204 / p1 0.08 with dry-stone walls (`#726a29` lit / `#201f13` shade) along
  every lane, a shed, pergola, van; ours std 0.150, p1 0.11; lane 700,640 `#ae9b8b` V0.68 **S0.20** (ref lane
  `#a37948` S0.55 V0.64); house wall 660,350 `#5c5d62` V0.38 S0.06 (grey — a shade wall under the −150 sun; ref
  walls are warm cream `#c9b48c`-class). Fifth round on the list.
- **Fix:** `_wall` segments 1 m × 60 m each side of the two lanes (limestone `#b3a38a` material, talus sibling),
  a 6 × 4 m shed and a pergola from the house kit, 2 cypresses at the gate, ≤ 0.2 s; lane colour map → `#c9a878`
  (item 5's `Dirt` tint). The house walls will warm up with item 1 (measure after).
- **Verify:** ≥ 40 m of wall visible in `villa`; frame std ≥ 0.18; lane S ≥ 0.40; house wall 660,350 V ≥ 0.55
  H 25–45.

### 14. Ledge tops and boulder tops must survive the emission cut — **ROCKS**
- **Evidence:** exp3 (sky_fill 0.50, sky_w floor 0.35) put the `cliff_coast` ledge top 560,500 at `#4f535d`
  **V0.36**, darker than the arch face beside it (V0.38) — the ref's tops are its palest rock (`#aeb3c6` V0.78
  cliff-top wall, ref far arch top `#8ca8c1` V0.76). r4 master has the top at V0.42 under a V0.70 face (ratio
  0.6; ref ≥ 1.3). `cliff_arch` boulder 620,690 / 620,730 in exp3: top V0.42 / flank V0.51 (r4 1.5 — lost).
- **Fix:** with item 2: `sky_fill 0.60` weighted to `up_w` (`mix(0.12, 1.0, up_w)`), `sky_fill_color #a9b6cf →
  #b5bccb` (S0.10: tops cream-grey); `top_cut` boulders keep `bevel_top 0.3`; at el 36 a horizontal top gets
  sin 36 = 0.59 of the sun — with `sun_gain 0.35` that is the brightest term, as it should be.
- **Verify:** 560,500 ≥ 1.2 × the face at 560,540; `cliff_arch` boulder top ≥ 1.15 × flank; `coast_b` stack
  ledge 1048,588 ≥ 1.2 × the block face under it.

### 15. The far treeline / stack-top pines are fine now — keep them; the villa cypress silhouettes are pale — **GROUND (small)**
- **Evidence (keep):** `cliff_coast` treeline band p50 0.28 (target ≤ 0.30 ✓), far pines `#66798f` H215 (hazed,
  like the ref's `#4a5667`); villa broadleaf `#4b5c39` S0.33 V0.36 (ref `#646e39` S0.48 V0.44 — a touch dark /
  grey but acceptable). **Gap:** villa cypress columns render `#9d8a6a`-class where the card is thin (the
  ground shows through at 40 m) — the ref cypress is a solid `#2a2a0f`–`#3a3d25` column.
- **Fix:** cypress `alpha_cut 0.38 → 0.30` on the `cypress_clump` material only, card coverage in `foliage.py`
  cypress ×1.2; `col_lit` for "shade" trees `#7c9540 → #86a044` (S back toward 0.5).
- **Verify:** cypress patch 320,600 V ≤ 0.30 H 50–90; villa tree lit S 0.42–0.55.

---

## Regressions vs round 3 (`/root/rounds/r3`)

- **`cliff_coast_b` 0.576 → 0.560** (item 6): texture 0.499 → 0.449 (rock emission flattening + sun off the
  terrain wall), layout 0.850 → 0.826 (bright cloud slab, washed water V0.36 → 0.44).
- **Foreground tree black** (item 3): top-left region p50 0.33 → 0.10, V < 0.12 share 0 → 49 %.
- **Rock saturation over-corrected**: lit S 0.36 → **0.15** (ref 0.20–0.25); the lit:shade ratio collapsed
  (arch front V0.70 vs its reveal V0.50 in the *wrong* direction — the reveal should be lit or the front shaded).
- **Ledge tops** darker than faces (0.42 vs 0.70; r3 0.68 vs 0.72).
- **Villa soil** went from navy/maroon blotches to orange slopes (H0–25 23 % → 46 % of the ground region).
- **Sky/clouds** in `coast_b`: sky V0.76 → 0.78–0.85 with the pink slab (r3's clouds were invisible — both wrong).
- **Improved, keep:** tan bin 6.0 % → 0.1 %; ref-shade bin 1.7 % → 8.5 %; open water `#203550` → `#2d3f56`
  (ref `#2a3a5c`); the dark-green moat gone (teal share 46 % → 27 %); foam 3.5 % → 0.6 %; far islets under the
  sky; staircases gone; hero-region lumstd 0.173 → 0.171 with p10 0.06 (the darks are back — the ref's are 0.14,
  that is the tree); treeline p50 0.45 → 0.28; villa sea `#b0abb6` → `#6d798f` under the sky; villa vineyard
  H25–70 7 % → 20 %; generation 10.0 → 8.2 s.

## Per-lane summary

- **LOOK (do item 1 first, commit it alone, announce):** 1 sun yaw −40 (fix the comment), 4 sky gradient +
  clouds + `reflect_amount`, 8 fog colour/scatter, 10 foam, 11 teal/fresnel, 7-fog half. Acceptance: arch face
  700,330 shaded H205–235 V0.38–0.50 with hero wall lit V0.52–0.62; sky hue gradient ≥ 25° top-to-horizon with
  the horizon S ≥ 0.26; coast_b sky p98 ≤ 0.78; bright foam 0.10–0.25 %; `cliff_coast` ≥ 0.63.
- **ROCKS (tune under yaw −40 — set it locally, do not commit the env lines):** 2 emission → sun (shade_fill 0.35,
  sky_fill 0.60 on tops, sun_gain 0.35, tint warmer), 14 tops, 9 planes not smears, 6-blocks/terrain-wall
  contrast, 7-outcrop half. Acceptance: lit S0.20–0.26 V0.58–0.68; shade H210–235 S0.20–0.30 V0.40–0.48; tops
  ≥ 1.2 × faces; coast_b centre-wall lumstd ≥ 0.13; pillar row-profile p90 ≤ 0.03.
- **GROUND (tune under yaw −40 too):** 3 black tree (floor + scatter guard), 5 villa ground/soil/vines, 12 bench
  paint, 13 hub walls/shed/lane, 15 cypress. Acceptance: top-left V < 0.12 share ≤ 5 %; villa orange bin ≤ 3 %,
  straw ≥ 25 %, vineyard H25–70 ≥ 45 %; bench p10 ≥ 0.50; ≥ 40 m wall; lane S ≥ 0.40.
- **All lanes:** generation < 18 s (8.2 s today — ≤ 2 s each), `architecture_tests` / `feature_tests` /
  `edge_tests` green, props ≥ 6 m from road centrelines and off delivery rings, run `godot --headless --path .
  --import` after touching any PNG; render `cliff_coast,cliff_coast_b` at least twice and look at the crops.
- **Spots:** keep the four judged spots + `islet_far`; GROUND adds `villa_gate` (from `[-330,12,40]` at
  `[-326,6,3]`) for the wall / shed work.
