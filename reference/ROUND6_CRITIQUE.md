# Round 6 critique (FINAL) — r5 merged renders vs `ref_cliff_coast.png` / `ref_villa_vineyard.png`

Judged: `/root/rounds/r5/cliff_coast.png` (**0.637**, r4 0.617), `cliff_coast_b.png` (**0.520**, r4 0.560, r3 0.576 —
regressed again), `cliff_arch.png` (0.614, r4 0.601), `villa.png` (0.637, r4 0.604). Numbers are PIL medians of
16–24 px patches (sRGB, H/S/V) or region stats (median, luminance p10/p50/p90, std, FIND_EDGES energy) on the
1600×900 renders; the reference is resampled to 1600×900 so coordinates are comparable. Bins are % of a region.
Lanes as before: **LOOK** (`world_kit.gd` `Atmosphere` / `_build_environment` / `_build_sea`, `sky.gdshader`,
`sea.gdshader`), **ROCKS** (`rock.gdshader`, `rock_material`, `_cliff_pillar` / `_cliff_wall` / `_sea_*`,
`rock_gen.gd`), **GROUND** (`terrain.gd`, `island.gd` scatters / hub, `leaf.gdshader` materials, `TREE_LOOK`).

This is the last round: every item below is a parameter or a one-line guard, no new geometry, no new systems.
Each lane commits its items separately and re-renders all four spots; anything that drops `cliff_coast` or
`villa` by more than 0.005 is reverted. Budget: generation stays < 18 s (8 s now), tests green.

## Where the score went r4 → r5 (compare.py components)

| spot | r4 | r5 | colour | texture | layout |
|---|---|---|---|---|---|
| cliff_coast | 0.617 | **0.637** | 0.539 → 0.591 | 0.561 → 0.547 | 0.888 → 0.899 |
| cliff_coast_b | 0.560 | **0.520** | 0.527 → **0.418** | 0.449 → 0.476 | 0.826 → 0.826 |
| cliff_arch | 0.601 | 0.614 | 0.522 → 0.534 | 0.543 → 0.566 | 0.878 → 0.881 |
| villa | 0.604 | 0.637 | 0.382 → 0.457 | 0.740 → 0.727 | 0.867 → 0.884 |

`coast_b` lost 0.11 of colour and nothing else: its histogram excess vs the ref is (H210–240 S<0.17 V0.67–0.83)
**+13.4 %** (a flat pale lilac-grey sky over 45 % of that frame), (H0–30 S0.17–0.33 V0.5–0.67) **+7.3 %** (sun-square
lit rock) and a **−8.5 %** deficit in the ref's shade-rock bin (H210–240 S0.17–0.33 V0.33–0.5). Its rock region
(480–1600 × 300–860) went `#484f58` V0.36 → `#938176` **V0.58 p50 0.52 p90 0.69** (ref rock p50 0.38, p90 0.64); the
stacks facing the sun are `#d3beaf` **V0.83 S0.17** and `#d7c2b8` V0.84 (the ref never lights rock above V0.65).
The sun at −40 is the right sun for `cliff_coast` (kept, see do-not-touch); `coast_b` is fixed through items 1, 2, 5.

---

## Ranked items

### 1. The horizon: a cyan line, a sky that is 0.07 too bright at the horizon, and a sea that converges on it instead of sitting under it — **LOOK**
- **Evidence (row means, `coast_b` x100–400):** rows 400–407 sky `#80a7cc` H208 S0.37 **V0.80**; rows **408–411
  `#74a4cb` H206 S0.42** (a 4-px line, bluer and more saturated than both neighbours); rows 412–419 far sea `#80a7cb`
  V0.80 (= the sky, no step); rows 420–444 a 25-px slide down to `#5c7697` V0.60. Same line in `cliff_arch` (rows
  425–426, S0.39 vs 0.34) and `villa` (rows 72–77, `#6c98bb` S0.42 vs 0.36); in `cliff_coast` the sea rows 298–311
  slide 0.79 → 0.67 with no step at all. Reference (x1500): sky at the horizon `#7d98b4` **V0.71** S0.31, then an
  8-px step to sea `#6c85a1` **V0.63** S0.33 — the sea sits 0.08 *under* the sky and never converges on it.
- **Cause (code):** (a) the sky's ground half is `Atmosphere.ground_horizon = #68a0da` while `sky_horizon` was moved
  to `#70a0d8` in r5 — the comment says "= sky_horizon" but the value was not updated; the sea plane (`_build_sea`
  `pm.size 16000` → ±8000 m) ends 0.2–0.5° below the true horizon with the 20000 m camera far, and that strip shows
  the ground colour (3–5 px at fov 62). (b) `sky_horizon #70a0d8` is V0.85 in — *brighter* than `sky_top #c6b2c0`
  V0.78 — so the lowest sky renders V0.78–0.80 against the ref's 0.71–0.73 (every spot: `cliff_coast` y270 V0.76 vs
  ref 0.73, `cliff_arch` y360 V0.81, `villa` y60 V0.73). (c) `sea_horizon_gain 1.0`: `sea.gdshader` slides the far
  sea onto the *rendered sky horizon* (`horizon_lin`) at 400–2000 m, so at > 2000 m the sea equals the sky.
- **Fix:** in `_build_environment` set `ground_horizon_color` from `A.sky_horizon` (delete the separate
  `ground_horizon` entry, or set it to the same string); `sky_horizon #70a0d8 → #6892c6` (V0.78, S0.47 in: renders
  ~V0.72 S0.32 at H210, the r5 pale-blue bin keeps its hue); `sea_horizon_gain 1.0 → 0.82` (the far sea lands ~0.07
  under the sky, `horizon_fade_end 2000` unchanged). Optional belt-and-braces: `pm.size 16000 → 40000` in
  `_build_sea` so the plane always reaches the far plane (also covers the game camera), no cost.
- **Verify:** `coast_b` rows 395–450 at x100–400: no row whose S exceeds both neighbours by > 0.02; sky row just
  above the horizon V 0.70–0.74; first sea row below it V 0.61–0.66 (step ≥ 0.05); `cliff_coast` y270 V ≤ 0.74;
  `cliff_arch` y360 V ≤ 0.76; `villa` rows 60–90 monotone. `coast_b` colour term ≥ 0.45.

### 2. Sun-square rock is blown and chalky because the blue *shade* fill is added on lit faces too — **ROCKS**
- **Evidence:** `coast_b` stack 1150,780 `#d3beaf` H23 **S0.17 V0.83**, far stack 350,560 `#d7c2b8` V0.84, block
  face 850,560 `#ad9788` V0.68; `coast_b` rock region p90 0.69, frame p50 **0.61** (ref 0.36); lit S 0.15–0.17
  everywhere the sun is square (ref lit `#9d8879` H25 **S0.23** V0.62, `#76625a` S0.22). `cliff_coast` near boulders
  650,660 `#9c8f8b` S0.13 V0.61, rock-band V>0.8 S<0.25 share **1.1 %** (ref 0.18 %), concentrated in x395–742
  (the water-line boulders and the near stack). Meanwhile the shade side is right: arch face 700,330 `#4f5868`
  H220 S0.24 V0.41 (ref `#565966` H226 S0.18 V0.40), hero wall 120,650 `#806f64` H21 S0.22 V0.50 (ref lit cliff
  V0.46–0.62). So lit:shade is ~1.2 where the sun grazes and ~2.0 where it is square, with the square faces 0.2 V
  over the ref.
- **Cause (`rock.gdshader`):** `EMISSION = alb × (sky_fill_color × sky_w × 0.70 + shade_fill_color × side_w ×
  0.56)` — `side_w` depends only on `wn.y`, so a vertical face gets the full blue shade fill (≈ 0.34 × alb linear)
  whether or not it faces the sun. On a sun-square face that is added to the direct term (1.4 × `sun_gain 0.32` =
  0.45 × alb) and the ambient (~0.2): ≈ 1.0 × alb → V0.83 after the grade, and the blue fill on a warm lit face is
  exactly what pulls its S from 0.23 to 0.15.
- **Fix (`rock.gdshader`, `light()` + one varying):** move the shade fill into `light()` so it can see the sun:
  `varying float v_side_w;` set in `fragment()` (`v_side_w = side_w × mix(0.5, 1.0, ao)`), drop the shade term from
  `EMISSION` (keep the sky term), and in `light()`:
  `float sf = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);`
  `DIFFUSE_LIGHT += ALBEDO * shade_fill_color * shade_fill * v_side_w * (1.0 - 0.6 * sf);`
  (one directional light, so it runs once; not multiplied by ATTENUATION — cast-shadowed faces keep the fill, as
  now). Then compress the direct term with a knee instead of a gain cut: `d = d * (1.0 + sun_knee) / (d + sun_knee)`
  with `uniform float sun_knee = 0.5` (square faces ×1.0, the 75°-off hero wall ×1.65, wrap-only shade ×2.1), and
  `sun_gain 0.32 → 0.24`, `shade_fill 0.56 → 0.45`. Net (linear, ×alb): square lit 1.0 → ~0.72, hero wall 0.73 →
  ~0.71, shade 0.69 → ~0.63. The blue leaves the lit faces, so their S returns to the albedo's (`LIMESTONE_TINT`
  stays); if lit S still < 0.20, `macro tint mix 0.25 → 0.35` (line `mix(vec3(1.0), macro_tint, 0.25)`), nothing
  else.
- **Verify:** `coast_b` 1150,780 and 350,560 V 0.62–0.70, S ≥ 0.20; `coast_b` rock region p50 ≤ 0.50, p90 ≤ 0.64,
  frame p50 ≤ 0.55; `cliff_coast` hero wall 120,650 V 0.47–0.53, S ≥ 0.20; arch face 700,330 H210–235 S ≥ 0.18
  V 0.38–0.44 (unchanged within 0.03); `cliff_coast` rock-band V>0.8 S<0.25 share ≤ 0.5 %; `coast_b` ≥ 0.55,
  `cliff_coast` ≥ 0.635.

### 3. The hero wall (and every fourth wall piece / stack) is marble: the `rock019` sibling — **ROCKS**
- **Evidence:** the near-left cliff of `cliff_coast` (0–420 × 480–900) at 2× is a smooth face crossed by tan
  diagonal *veins* at ~1.5 m spacing — no plane breaks, no joints, no course lines; the same veins run diagonally
  across the `coast_b` stacks at 1150,780 and 400,700. Band-pass stats are in the ref's range (hero wall fine/mid/
  coarse std 0.035/0.045/0.053 vs ref lit cliff 0.043/0.048/0.061) — the *amount* of structure is right, the *kind*
  is wrong: the ref's is 3–8 m fracture planes with 1–2 px joint shadows, ours is the texture's marbling.
- **Cause (code):** `_limestone_material()` registers `rock019` (a veined quartzite, `assets/rock/rock019_alb.jpg`:
  cream with tan diagonal veins) as the `_rock_alt` sibling; `_cliff_wall` line 830 gives it to one pillar in four
  (`r.randi() % 4 == 0`) and `_add_rock` to one piece in three (`rng.randi() % 3`), hero pieces included. At
  `tex_metres 3` and 30 m the veins are the only structure the eye reads.
- **Fix (one line, no rng change):** `_rock_alt[m] = rock_material("rock024", LIMESTONE_TINT * Color(1.0, 0.98,
  0.95), 0.10, 0.5)` — the same texture at a hair cooler tint and half the normal strength; the cache key includes
  the tint so it stays a distinct material and the `randi()` calls stay where they are. Keep `rock019` for the
  hoodoo alt (it is red there and 300 m from any spot). If the rocks lane prefers to keep some veining: only
  `and not hero` on line 830 — but the stacks would keep it, so swap the sibling.
- **Verify:** hero wall crop (0–420 × 480–900) at 2×: no diagonal vein longer than 30 px; hero-wall region
  (20–300 × 560–880) row-profile p90 ≤ 0.015 and edge energy 0.035–0.05 (now 0.041); `coast_b` stack 1150,780
  region std within ±0.02 of today.

### 4. Foam is gone from the rock feet; the r5 "thin lace" target was wrong — **LOOK (`sea.gdshader`)**
- **Evidence:** ref surf zone (880–1300 × 660–900) at 2×: a *solid* pale collar 3–6 px wide (1–2 m) round every
  boulder foot, median `#bfbdb3` **V0.75 S0.06**, **1.46 %** of the zone at V>0.72 S<0.2, plus two or three white
  streaks on the open water; the ref's *bright* bin (V>0.78 S<0.15) is ~0 only because the collar is V0.75 — it is
  not thin, it is grey-white. Ours: `cliff_coast` rock feet 700,720 `#264656`, 560,800 `#1e3854` — no collar; a
  1-px cyan-white line under some boulders (470,690); `cliff_arch` boulders sit in water with no foot line at all.
  r4 had 0.56 % bright foam, r5 halved it again and the eye lost the water line.
- **Fix:** `foam_color (0.88,0.87,0.84) → (0.82,0.81,0.77)` with `foam_emission 0.5 → 0.7` (renders ~V0.75 grey-
  white, never clips); `foam_opacity 0.7 → 0.9`; the solid foot line back: `ring += smoothstep(0.85, 1.0, shore) *
  0.35 → 0.7` and `foam_depth 0.4 → 0.7` (a 1–2 m collar, the lace threshold 0.68 stays so the ring beyond it is
  still open); `whitecap_threshold 0.95 → 0.93` (3–6 caps per 100 m, the ref shows them). Skirt hue: the ref's
  skirt is *green* `#2d4e42` H155 S0.43 V0.31, ours is teal-blue H200 (green H120–175 share of the surf zone
  **0.02 %** vs ref 2.2 %, teal H175–205 10 % vs ref ~2 %): `col_teal (0.07,0.20,0.16) → (0.06,0.19,0.12)`,
  `teal_amount 0.5 → 0.6`, `teal_metres 6` unchanged (the r3 moat was 9 m at 0.75 and V0.23 — this is a hue move
  on a 6 m skirt, not a width move).
- **Verify:** surf zone (420–900 × 600–900): V0.65–0.82 S<0.2 share 0.8–1.8 % (inside water: count pixels
  4-adjacent to a H170–210 S>0.3 pixel); no foam pixel V > 0.85; every water-line boulder in the `cliff_coast`
  crop shows a ≥ 2-px pale line at its foot; green (H120–175 S>0.35) 1–3 % of the zone, teal ≤ 6 %; open water
  1200,700 `#2b405c` ± 0.03 unchanged.

### 5. `coast_b` / `cliff_arch` sky: a flat lilac-grey sheet above 13°, clouds brighter than the sky — **LOOK**
- **Evidence:** `coast_b` sky (0–1600 × 0–400) `#a3a9bf` H229 **S0.13** V0.75, p98 0.76; column x200: y5–180
  H229–243 S0.11–0.13 V0.70–0.74 (lilac-grey, the zenith stop), only y300+ reaches the ref's blue (S0.19 at y300,
  0.31 at y360); cloud 1000,150 `#b7b6cd` **V0.80** on sky `#b7b7ce` V0.81. `cliff_arch` sky (1000–1600 × 0–400)
  p98 0.75, y120–180 H250–268 S0.09–0.10 (pink-grey). Ref sky box: S p50 0.16, hue p10/p90 209/254, **p98 0.68**,
  cloud `#aca9bc` V0.74 on sky V0.75 (clouds a hair *darker*), pale-blue bin 33 %. `cliff_coast`'s column is right
  (H240→210, S0.10→0.33, pale-blue 28 %) — this is about the 13–29° band those two cameras see.
- **Fix (`Atmosphere`):** `sky_zenith #8fa8cc → #7f9fd0` (S0.39 in, ~S0.20 out at H215: the upper sky stays in
  the ref's H210–240 S0.17–0.33 bin instead of S<0.17), `sky_band_deg 13 → 11`, `sky_zenith_deg 28 → 24`;
  `sky_energy 1.45 → 1.38` (with item 1's darker horizon the whole sky lands V0.68–0.73); clouds never lighter
  than the sky: `cloud_mul_edge (1.04,1.0,1.0) → (0.99,0.97,0.99)`, `cloud_base (0.78,0.77,0.85) → (0.72,0.70,
  0.80)`. Leave `cloud_cover 0.35`, the seed and the glow lobes alone.
- **Verify:** `coast_b` sky region S p50 ≥ 0.17, p98 ≤ 0.73, cloud 1000,150 V ≤ sky beside it + 0.01;
  `cliff_arch` sky p98 ≤ 0.74, H250–300 share ≤ 6 %; `cliff_coast` right column keeps hue ≥ 235 at y5 and ≤ 215 at
  y240, pale-blue bin ≥ 25 %; `coast_b` histogram excess in (H210–240 S<0.17 V0.67–0.83) ≤ +6 %.

### 6. Villa vine rows are grey-teal, not dark olive: the leaf shader's far tint — **GROUND**
- **Evidence:** rows 1000,380 `#394949` **H185** S0.35 V0.29, 250,400 `#424a4b` H198 S0.24 V0.33, lit rows 1350,470
  `#666d49` H75 S0.36; ref rows `#2a2911` H59 **S0.60** V0.17 / `#514c29` H51 S0.53 V0.35. Villa lower frame
  olive-dark bin (H40–90 S>0.4 V<0.35) **1.1 %** vs ref **12.9 %** — the single biggest villa histogram gap left.
- **Cause (code):** `leaf.gdshader` `far_tint (0.64,0.70,0.72)` from `far_start 100` to `far_end 220` m — a *cooler*
  multiplier meant for the crest pines — is on the vine material too (`_gen_farmland` `vmat`); the villa rows are
  120–320 m from the camera, so every row is multiplied by a blue-grey and then fogged.
- **Fix (`island.gd` `_gen_farmland`, on `vmat` only):** `far_tint (0.62, 0.60, 0.40)` (darker *and warmer* with
  distance), `far_start 150`, `far_end 400`; `card_tint (0.78,0.72,0.28) → (0.66,0.64,0.22)` (the lit rows were
  tan `#806853` at 900,330); keep `ambient_floor (0.40,0.36,0.12)` and `shade_warm`. Same `far_tint` on the
  olive/"shade" tree materials is *not* wanted (their hazed look is right).
- **Verify:** rows 1000,380 and 250,400 H 40–90, S ≥ 0.40, V 0.22–0.35; lit rows 1350,470 S ≥ 0.45; villa lower
  frame olive-dark bin ≥ 5 %, H170–260 share of the vineyard region (800–1400 × 280–450) ≤ 12 %; `villa` ≥ 0.635.

### 7. The villa lane is dark mud between two concrete kerbs; ground shadows are navy — **GROUND**
- **Evidence:** lane 1100,520 `#826853` H27 **S0.36 V0.51**, 900,470 `#756053` V0.46, 700,500 `#8e7253` V0.56 —
  *darker* than the straw beside it (600,650 `#917550` V0.57); ref lanes `#a47b49` H31 **S0.55 V0.64** and
  `#b29775` V0.70 — the brightest ground in the frame. Ground in tree shadow 400,700 `#413c3e` **H214** S0.23
  V0.26, 950,700 `#36373d` H223; ref shade ground `#47481f` H58 S0.54 V0.29 / `#7b5731` H30. Villa lower frame
  cool-shadow bin (H190–250 S>0.15 V<0.4) **10.7 %** vs ref **3.1 %**; warm-shadow (H15–60 S>0.3 V<0.4) 3.6 % vs
  **17.6 %**. Walls 1100,560 `#735d4e` / 1300,600 `#806250`: flat pale boxes (`STONE_DARK (0.70,0.63,0.50)`, no
  texture); ref walls `#1f221b`–`#726a29`, dark dry-stone with a lit cap.
- **Fix (`terrain.gd` road paint, hub walls):** `rut_col (0.62,0.52,0.40) → (0.82,0.68,0.44)` and `margin_col
  (0.42,0.37,0.29) → (0.62,0.52,0.32)` (the 3 m grid makes the ruts/margin most of a 4 m lane — they must stay
  straw-gold, only ~0.15 V under the crown); `road_col (1.0,0.93,0.76)` stays. Shadows: `Atmosphere.ambient_color
  #a3a6b2 → #aca9a8` (S0.05 → 0.02, the blue in the shade rock now comes from `shade_fill_color`, item 2, not from
  the ambient) — LOOK owns that line, GROUND asks for it, and it is reverted if the arch face S drops below 0.18.
  Walls: `_villa_lane_walls` → the talus rock material (`_rock_bare` of `_limestone_material()`) with tint
  `Color(0.42, 0.40, 0.30)` instead of `Mats.solid(STONE_DARK)`; 0 s cost, no geometry change.
- **Verify:** lane 1100,520 and 900,470 V ≥ 0.60, S ≥ 0.45, H 28–40; lane brighter than the straw at 600,650 by
  ≥ 0.05 V; cool-shadow bin ≤ 7 %, warm-shadow ≥ 8 %; wall 1300,600 V 0.30–0.45 with visible grain (region std
  ≥ 0.03); arch face 700,330 S ≥ 0.18 after the ambient change.

### 8. Aerial perspective: far rock is 0.1 V too dark under a sky that is 0.07 too bright — **LOOK**
- **Evidence:** `cliff_coast` 250 m stack 1130,420 `#596478` V0.47 / 1180,300 V0.56, far islet 1550,320 `#606b81`
  **S0.26 V0.51**, treeline 1050,300 V0.55 — under a horizon sky V0.78: far-rock/sky ratio **0.65**. Ref: far stack
  1520,320 `#67809c` **V0.61** S0.33, headland `#667e9a` V0.60, mid arch 1250,400 `#4c5d68` V0.41, under sky V0.71:
  ratio **0.85**, and the steps near → mid → far are 0.40 → 0.41 → 0.61 (ours 0.43 → 0.49 → 0.51: the far step is
  missing). `villa` background outcrops (900–1600 × 0–200) `#767777` **V0.50**, 1400,100 `#33455a` V0.35 navy; ref
  `#8fafc9` V0.79 S0.29. The hue is right now (H215–219, S0.25 — r5 fixed the grey), the *energy* is short.
- **Fix:** `fog_energy 1.18 → 1.27` at the same `fog_color #7591b5` (the r5 c5 test that went cyan changed the
  colour to S0.43 *and* the energy; keep the colour); `fog_density 0.0030` unchanged; item 1 brings the sky down
  to meet it. If the villa's middle distance (200–400 m) picks up cyan (H180–210 bins +3 % or more), back off to
  1.23.
- **Verify:** far islet 1550,320 V 0.56–0.64, S 0.22–0.35; far-rock/sky ratio 0.78–0.88; 250 m stack ≤ sky − 0.10;
  villa bg region V ≥ 0.58, 1400,100 V ≥ 0.50; near hero wall 120,650 unchanged within 0.02; `villa` ≥ 0.635.

### 9. The crest pine over the `cliff_coast` camera covers 11.5 % of the frame — **GROUND (+ROCKS)**
- **Evidence:** green (H60–160 S>0.25) share of the top-left 600 × 560 box **49 %** = 11.5 % of the frame (ref box
  4 %, ~1 % of the frame, hazed `#313544`); it is no longer black (V<0.12 share 1.0 %, canopy `#283d18` V0.24 —
  keep those floors) but it hides the top of the hero wall and the crest, and its hard leaf polygons at 32 m are
  the crispest thing in the frame. It is a `_cliff_wall` crest pine 32 m from the camera (`CHANGELOG_r5_ground`).
- **Fix:** `world_kit.gd` `CAMERA_CLEAR 12.0 → 36.0` (`_scatter_records` already drops any imported-tree instance
  within that radius of every `SPOT_CAMERAS` entry, wall crest pines included). The other spots lose nothing the
  eye wants: `villa` is 34 m above its ground, `cliff_arch` / `apron_close` see rock, the hub cypresses at the
  villa gate are > 36 m from (−290, 60). Do not touch the tree colours.
- **Verify:** green share of the top-left 600 × 560 ≤ 15 % (frame ≤ 4 %); a tree may still show at the top-left
  edge; the hero-wall crest at 150–330 × 480–560 visible; `cliff_coast` ≥ 0.635, `villa` cypress count unchanged.

### 10. Talus / water-line boulders are pink chalk with no top/side step — **ROCKS**
- **Evidence:** `cliff_coast` boulders (500–760 × 620–760) `#707075` p90 **0.70**, lit 650,660 `#9c8f8b` H24
  **S0.13** V0.61, shade side 560,720 `#958781` S0.13 V0.58 (top:side 1.05); `cliff_arch` boulders 400,650 `#827a7d`
  H222 S0.12 V0.51. Ref boulders (720–1000 × 780–880) `#57494b` p50 0.30 p90 0.43, lit top `#584c50` /
  side `#524649`, and the water-line rocks `#9e8a7a` S0.23 with a dark contact ring. The talus variant is
  `_rock_bare` (`ao_min 0.20`, no fracture, `sand_amount 0.25` at `sand_color (0.58,0.53,0.45)` grey) — the sand
  dusting and the top-weighted sky fill make every small rock a pale grey-pink lump.
- **Fix (`rock_material` talus branch):** `sand_amount 0.25 → 0.12` and `sand_color → (0.62, 0.54, 0.42)` (warm,
  S0.32) on the talus variant only; `sky_fill 0.70 → 0.60` on talus (tops of 1–3 m rocks are sun-lit anyway);
  item 2 removes the blue fill from their lit flanks. No change to `top_cut`, `bevel_top`, sizes.
- **Verify:** 650,660 S ≥ 0.20, V 0.52–0.62; boulders region p90 ≤ 0.64, p50 0.40–0.48; contact ring under a
  water-line boulder ≥ 0.10 V darker than its flank; `cliff_arch` 400,650 S ≥ 0.18.

### 11. The bench and the road under the arch are pink-brown, the ref's are straw sand — **GROUND**
- **Evidence:** `cliff_coast` bench 850,510 `#9b8174` **H20** S0.24 V0.61, `cliff_arch` bench 820,480 `#927c74` H11
  S0.16 (pink); ref bench sand 1100,690 `#978d7c` **H51** S0.20 V0.60, ref road `#988478` H30 with rut lines. Ours
  is the right value now (r5 shingle + `bench_col`), the hue is 20–30° too red.
- **Fix (`terrain.gd`):** `bench_col (0.90,0.80,0.64) → (0.88,0.82,0.62)` (H40 in) and the rut/margin change of
  item 7 applies here too; `sand_color` of item 10 matches. No geometry.
- **Verify:** 850,510 H 32–48, S 0.18–0.28, V 0.58–0.66; `cliff_arch` 820,480 H ≥ 30; bench region (700–900 ×
  480–560) p10 ≥ 0.45.

### 12. Small LOOK leftovers, all one-liners
- **Sea glints:** the open water of `cliff_coast` (900–1600 × 500–700) already has **0.29 %** of its pixels at
  V > 0.85 (max 0.94) — a glitter path the ref does not have (its open water tops out at the whitecaps, V0.75–0.8);
  `sparkle 0.35 → 0.22` (verify: V > 0.85 share ≤ 0.08 %).
- **Vignette:** `vignette 0.16` darkens the top corners of the sky spots: `coast_b` 40,40 `#9c9cb0` **V0.69** against
  V0.78 on the same row at x800 (a 0.09 fall-off the ref sky never shows; the ref's corners are dark only where
  there is a tree) — `0.16 → 0.10` (verify: `coast_b` corner ≥ centre-row − 0.06).
- **Height fog:** `fog_height_density 0.028` puts 24 % haze on the stack feet; with `fog_energy 1.27` (item 8) it
  will read as a pale skirt on the near stacks — `0.028 → 0.022` (verify near stack foot 760,830 V ≤ face + 0.04).

---

## Do NOT touch (working, measured)

- **Sun:** `sun_yaw_deg −40`, `sun_elevation_deg 36`, `sun_color #ffe2c6`, `sun_energy 1.4`, shadow settings.
  Arch face shade `#4f5868` H220 S0.24 V0.41 vs ref `#565966` H226 S0.18 V0.40; hero wall lit `#806f64` H21 S0.22
  V0.50; `cliff_coast` frame p10/p50/p90 **0.17/0.36/0.69** vs ref 0.19/0.36/0.65; ref-shade bin in the rock band
  15.8 % (ref 13.0 %).
- **Shade rock colour** (`shade_fill_color #6b87d1`, `sky_fill_color #b5bccb`, `LIMESTONE_TINT`, `tex_saturation
  0.45`, `ao_min`, `rim_darken`) — item 2 only *gates* the shade term on lit faces and adds a knee.
- **r5 rock geometry** (`facet_amp` / `facet_metres` / `facet_tilt`, `bed_tilt`, `facet_blend 1.0`, `bed_band 0.03`,
  crease AO 0.40/0.45, the shingle bench): pillar row-profile p90 0.034, column std 0.008 (ref 0.014 / 0.006);
  no staircases, no smears once item 3 removes the veined texture.
- **`cliff_coast` sky gradient** (`sky_top #c6b2c0`, `sky_curve 0.22`, glow lobes, `cloud_cover 0.35`, cloud seed):
  right column H240 → H210, S0.10 → 0.33, pale-blue bin 28 % (ref 33 %), pink bin fine. Item 5 touches only the
  zenith stop, the cloud brightness and the energy; item 1 the horizon.
- **Open water** `#2b405c`-class S0.53 V0.36 (ref `#2a3a5c`); `coast_b` water 200,650 S0.42 (was 0.27); `SEA_NAVY`,
  the band depths, `reflect_amount 0.15`, `fresnel_bias 0.07`, `swell_amount 0.3`.
- **Fog colour** `#7591b5` / density 0.0030 (far islets H219 S0.26 — the hue and saturation are right; item 8 is
  energy only).
- **Tree floors** (`TREE_LOOK` 4th entry, umbrella `#2e3a22`), the 12 m camera guard mechanism (item 9 only widens
  the radius), the far-tree haze on pines (`far_tint` on crest / coast pines: treeline 1050,300 `#5d7a8b` vs ref
  `#5d6d84` — leave it; item 6 changes the *vine* material only).
- **Villa ground:** straw bin 31 % (ref 39 %), orange 1.1 % (ref 1.3 %), pale 2.4 % (ref 4.4 %); parcel-only soil,
  `farm_strips`, meadow tints, the 7 m flagstone disc, the shed, the hub layout; road clearance guards (no prop
  sits on the lane strip in `villa`; the ring at 930,460 is the delivery ring by design).
- **Generation** 8 s, tests green, instancer counts.

## Per-lane summary

- **LOOK (commit item 1 first, alone, and announce):** 1 horizon (ground_horizon = sky_horizon, `sky_horizon
  #6892c6`, `sea_horizon_gain 0.82`), 4 foam collar + green skirt, 5 zenith stop / cloud brightness / energy,
  8 `fog_energy 1.27`, 7's `ambient_color` line on GROUND's request, 12. Acceptance: no cyan row at any horizon;
  sky-above-horizon V 0.70–0.74 with the sea ≥ 0.05 under it; foam 0.8–1.8 % of the surf zone at V0.65–0.82; far
  islet V 0.56–0.64; `coast_b` sky S p50 ≥ 0.17; `cliff_coast` ≥ 0.64, `coast_b` ≥ 0.55.
- **ROCKS:** 2 shade fill gated by the sun + knee (`sun_gain 0.24`, `sun_knee 0.5`, `shade_fill 0.45`), 3 swap the
  `rock019` sibling for a `rock024` variant, 10 talus sand / sky fill. Acceptance: `coast_b` sun-square faces V
  0.62–0.70 S ≥ 0.20, rock region p50 ≤ 0.50; hero wall and arch face within 0.03 V of today; no diagonal veins;
  `cliff_coast` rock-band V>0.8 share ≤ 0.5 %.
- **GROUND:** 6 vine `far_tint` / `card_tint`, 7 lane rut/margin colours + wall material, 9 `CAMERA_CLEAR 36`,
  11 bench hue. Acceptance: rows H40–90 S ≥ 0.40 V ≤ 0.35; lane V ≥ 0.60 S ≥ 0.45; olive-dark bin ≥ 5 %; top-left
  green ≤ 15 % of the box; `villa` ≥ 0.635.
- **All lanes:** render all four spots twice, look at the crops listed in each item (hero wall 0–420 × 480–900,
  arch 560–980 × 250–620, surf 420–900 × 600–900, `coast_b` horizon rows 395–450, villa lane 600–1400 × 400–700);
  `architecture_tests` / `feature_tests` / `edge_tests` green; props ≥ 6 m from road centrelines; generation
  < 18 s; any item that costs `cliff_coast` or `villa` > 0.005 is reverted, not tuned further — this is the last
  round.
