# Round 2 critique — r1 renders vs `ref_cliff_coast.png` / `ref_villa_vineyard.png`

Judged: `/root/rounds/r1/cliff_coast.png` (0.585), `cliff_coast_b.png` (0.53), `cliff_arch.png` (0.58),
`villa.png` (0.565), each against `/root/rounds/r0/` and the references. Colours are 36×36 px patch
medians unless marked "region" (region = median of a rectangle) — PIL, sRGB. Reference cliff is
2554×1428, villa reference 1622×914, ours 1600×900. Lanes as round 1: **LOOK** (`world_kit.gd`
environment / sky / fog / grade + `sea.gdshader`), **ROCKS** (`rock_gen.gd`, `rock.gdshader`,
`_cliff_wall` / `_cliff_pillar` / `_sea_arch` / `_sea_stack` / `_boulder_apron`, `_gen_sea_cliffs`),
**GROUND** (`terrain.gd` maps/textures, `foliage.py`, `trees.py`, `leaf.gdshader`, tree/scrub scatter).

## Verdict: what improved, what regressed

**Improved (real, measured):**

| whole frame (96 % crop) | ref cliff | r0 cliff_coast | **r1 cliff_coast** | r0 cliff_b | **r1 cliff_b** | ref villa | r0 villa | **r1 villa** |
|---|---|---|---|---|---|---|---|---|
| mean HSV S | 0.29 | 0.20 | **0.32** | 0.19 | **0.26** | 0.35 | 0.19 | **0.30** |
| lum p1 | 0.11 | 0.20 | **0.10** | 0.34 | **0.20** | 0.09 | 0.25 | **0.14** |
| lum p50 | 0.36 | 0.55 | **0.33** | 0.58 | **0.44** | 0.36 | 0.48 | **0.34** |
| lum std | 0.16 | 0.17 | **0.16** | 0.11 | **0.16** | 0.20 | 0.11 | 0.11 |
| bottom-30 % mean | `#4d4848` | `#837f7d` | **`#3c4656`** | `#6e7785` | **`#51565f`** | `#5d523a` | `#73716a` | **`#564c3f`** |

The global tone problem of round 1 is solved: `cliff_coast` now sits on the reference's histogram
(p1, p50, std, S all within 0.03). Sky gradient is a match (zenith `#aab0cd` vs ref `#a0adc5`,
horizon `#829dbd` vs `#819fba`); clouds are soft smears, not cauliflowers; the far-water seam is
gone; deep water value is right (water V p50 0.37 vs ref 0.35, H 214 vs 218). `cliff_coast` now has
the right layout: land left, sea right, an arch on the centre-left third, stacks in the right third.
Pillars are tall (no face < 10 m), vertical joints read, the arch is one mass with a vaulted opening.
Trunk chequerboard is gone; the villa cypress monoculture is gone; roads faintly read in the villa;
halos under trees exist.

**Regressed / overshot:**
1. **Rock hue overshot from neutral grey to dark chocolate.** r0 lit wall `#96969b` (S3 V61) → r1
   `#6a5b54` (H18 S21 V41); the reference lit wall is `#b5997a` (V70). Tone stats match *because the
   rock became as dark as the reference's shadows*, not because lit rock is pale and shade is dark.
2. **Boulder tops went blue-grey** (moss + sky ambient): `cliff_coast` boulder top `#373b4a` (H227),
   apron region median `#384760` H217 — bluer than the sea beside them (r0 was `#85858c`). The
   reference's boulder tops are the *brightest* rock in the frame, `#bb9f7c` (V73).
3. **The foreground wall is now a 25 m featureless slab** occupying the left 35 % of `cliff_coast`
   with region std 0.046 (ref foreground cliff 0.175) — flatter than r0's loaves.
4. **Terrain slope in `cliff_coast_b` went from pale putty to smeared brown mud** (`#544f51`, right
   side) with stretched texture; it now matches the rock's wrong colour instead of the reference.
5. Villa contrast did not move (std 0.11 vs ref 0.20); `cliff_arch` spot still aims at the old arch
   position (-524,-294) and shows walls, not the arch (noted in the rocks changelog, still open).

Important framing for round 2: **the whole-frame histogram is now at target, so every fix below must
be redistributive, not global** — rock lit faces up ~1 stop, foliage/shadow/contact areas down —
or the score will fall back. Do not touch exposure/contrast globally to fix a single lane's colour.

---

## Ranked top-12 remaining gaps

### 1. Rock is dark brown, not pale warm limestone; tops are the darkest part — **ROCKS** (+ LOOK check)
- **Reference:** lit faces `#b5997a` (H31 S32 V70), boulder top `#bb9f7c` (V73), boulder face `#917661`
  (V56); shade faces `#535d73` (H221 S27 V45), `#4c5364` (V39). Lit:shade V ratio 1.6, hue swings
  warm→blue. Whole arch block region (mostly shade) `#51586b` H223.
- **Ours:** `cliff_coast` arch face `#766862` (H17 S16 V46), pillar `#70625f` (V43), foreground wall
  *lit* `#463a36` (V27); `cliff_coast_b` lit `#6a5b54` V41 / shade `#4d4c55` V33 (ratio 1.25);
  `cliff_arch` lit vault `#8d7a6e` V55 is the brightest rock anywhere. Arch block region `#726562`
  H11 — same value as the reference's *shadow* block but brown instead of blue-grey. Boulder top
  `#373b4a` (H227 V29) vs flank `#4d494f` — the top is darker than the side.
- **Why:** `LIMESTONE_TINT (0.64,0.53,0.39)` = `#a3875f`, an ochre, further multiplied by
  `macro_value 0.18`, `streak_amount 0.22`, `tex_saturation 0.8` and — the killer — `moss_amount 0.45`
  on every up-facing surface (`moss_color #3b4a35`), so tops go dark green-grey and the sky
  ambient turns that blue. Under exposure 0.68 nothing reaches V > 0.55.
- **Fix (ROCKS):** `LIMESTONE_TINT → (0.80, 0.75, 0.66)` (`#ccbfa8`, target sunlit `#b8a58a`–`#c4b094`
  after grade); `moss_amount 0.45 → 0.08` and restrict it to `ao < 0.5` crevices (tops must stay the
  lightest surface); `macro_value 0.18 → 0.10`; `streak_amount 0.22 → 0.08` and make streaks 1–2 m
  wide runs under ledges only (today they read as running paint on every face); `tex_saturation 0.8
  → 0.55`; keep `fracture_color` but only where `normal.y < -0.4` (it currently bleeds onto near-
  vertical faces and is part of the brown). Talus material: same tint, no moss. Target patches after
  the change: lit face V 0.60–0.70 H 25–35, shade face V 0.38–0.45 H 210–230, boulder top V ≥ 0.65.
- **LOOK check:** do not raise exposure; if the lit face lands under V 0.58 with the new tint, raise
  `sun_energy 1.25 → 1.6` (this also fixes item 10) and compensate with `ambient_energy 0.34 → 0.30`.

### 2. Rock faces are single flat slabs with a cream outline — no sub-facets, no broken tops — **ROCKS**
- **Reference (arch crop, left crop):** every 15–30 m face is broken into 2–6 m sub-facets at
  slightly different angles, with 0.3–1 m ledges, chipped corners, and tops that are broken and
  leaning (the arch's crown steps down in 4 blocks; the left pillars lean 5–10° outward). Region
  std on the foreground cliff 0.175, p10–p90 0.16–0.62. Edges are *soft*, never outlined.
- **Ours:** foreground wall region std **0.046** (p10–p90 0.20–0.30): a single planar face 25 m tall
  with a horizontal wood-grain texture. Every pillar is a vertical prism of constant width with a
  dead-flat top and one bevel; widths are uniform (~9–12 m) in `cliff_coast`, `cliff_arch` and
  `cliff_coast_b`. `bevel_top` catches the 24° sun as a **bright cream fillet outlining every
  block**: foreground wall top rim lum 0.61 (`#bf9569`) on a face of 0.22 (2.8×); right pillar rim
  `#f4cea7` lum 0.83 on a face of 0.47; the arch's left vertical edge is 35 % brighter than its
  face. It reads as a cel outline / stacked luggage with piping.
- **Fix:** in `rock_gen.gd` add a **facet displacement**: cellular (Worley) noise at 3–6 m in the
  face plane, each cell offset ±0.3–0.8 m along the normal with a hard edge (F2−F1 < 0.05 → crease),
  plus 1 octave of 1.5 m noise ±0.15 m; recompute normals with a 25° crease. `bevel_top 0.8–1.5 →
  0.3–0.5` with noise so it is not a continuous fillet, and multiply the rim's albedo by 0.85 (a
  weathered rim is *darker* than the fresh face, not lighter). Pillar variety in `_cliff_wall`:
  widths 5–16 m log-uniform, 1 in 4 leaning ±4–8° (top offset outward), 1 in 3 with a **broken top**
  (top face split into 2–3 steps of 1.5–4 m drop, `top_amp 2 → 4` on those), 1 in 5 missing its top
  third with the debris as 2–4 m blocks at its foot. Stagger pillar heights ±15 % so the skyline is
  stepped, not a parapet.

### 3. The right half of `cliff_coast` is empty sea with a hard horizon — **LOOK (spot + sea) + ROCKS (islet)**
- **Reference:** water is ~20 % of the frame (bottom-right); the right third is closed by a second
  headland/arch at ~300 m (`#66758a` V54, region) and a 200 m mountain islet at ~800 m (`#7993af`
  V68) — four depth planes.
- **Ours:** water is ~48 % of the frame (x > 900, y > 290 is all sea); the stacks are 20–30 px tall
  pips at 1300,520 (`#5b5a62`, V38 — *darker* than the reference's 300 m stack, so they read as
  near, small rocks rather than distant 50 m ones); the far coast is a thin strip at y 290–380; the
  sea/sky horizon is a **17-point value step in one row** (`#7893b3` → `#5b6e86` at y 285; the
  reference dissolves over ~100 px: `#677e9b` → `#4c678b`).
- **Fix (ROCKS, `_gen_sea_cliffs`):** add a hero islet/headland 350–500 m out on the camera's right
  third — from `[-598,38,-326]` looking at `[-522,5,-200]`, that is roughly (-720..-680, -60..-20):
  a 70–90 m tall, 120 m long stratified mass with its own stacks, plus scale the two existing
  offshore stacks to h 45–55 (taller than wide, `taper` 0.15). **(LOOK, `sea.gdshader`):** the far
  colour must converge on the *rendered* sky-horizon colour, not `fog_color × energy` — sample the
  actual horizon (`#7893b3`) or set `sky_horizon = fog_color.lerp(sky_horizon_color, 0.6)` and start
  the far blend at 300 m (currently the sea at 800 m is still V53). **(spots)** if the islet cannot
  land this round, pitch the camera 3° lower and yaw 6° left (`at → [-530, 2, -205]`) so the water
  drops to ~35 % of the frame.

### 4. Bench and road are invisible; the arch opening is stuffed with bushes — **ROCKS + GROUND**
- **Reference:** the arch frames a 5 m road with a car; the bench below the wall is pale earth
  `#a28d7f` (V63) with the road `#d2c0a8` crown / `#6c4b34` ruts running across the middle wedge.
- **Ours (`cliff_coast` bench crop 700–1150 × 380–620):** the bench sample is `#7d706f` (H4 S11 V49)
  — the same brown as the rock, so wall, bench and boulders fuse into one mass; **no road pixels can
  be found on it** (no lighter crown, no ruts, no margin); the arch's opening (750–830 × 400–500)
  shows six flat green bush discs and a rock face, not a road and not sky/sea. The changelog says
  the spur runs "along the west wall's foot on the 3–8 m contour" and the arch spans it — from this
  camera it is not visible, either because the arch axis is not on the sightline after the nudge to
  `[-598,38,-326]`, or because the bench colour map makes it invisible.
- **Fix (ROCKS):** render `arch_close` and confirm the road passes *through* the opening; yaw the
  arch so its axis is within ±10° of the `cliff_coast` sightline and widen the opening to ≥ 14 m ×
  18 m; stop `_cliff_wall` / `_scatter_slope_breaks` bushes inside the opening (`road_clear 4.5 → 8`
  around the arch). **(GROUND)** the bench must be *lighter and warmer than the rock*: road crown
  `#c9a77a`-class must survive the grade at ≥ V 0.55 (today's road colour lands near V 0.43 in the
  villa, `#6f5b53`); paint the bench surface as sand/earth (`#b09776` at 1.0) not the cliff/scrub
  texture, with ruts `#8f7658` and a 1.5 m dark margin — visible from 150 m is the test.

### 5. All foliage renders blue-teal — **GROUND (leaf shader) + LOOK (ambient)**
- **Reference:** shade tree `#313e33` (H129), scrub `#31341a` (H66) / `#1a2221`, villa shade tree
  `#555f3c` (H77), cypress `#3f3e17` (H58). Greens are yellow-olive, the darkest things in frame.
- **Ours:** `cliff_coast` big tree `#18282f` (**H198** S48), tree top `#101c27` (H208), wall bush
  `#415655` (H177); `cliff_coast_b` tree `#324659` (H209); `cliff_arch` bush `#22323f` (H206); villa
  cypress `#1b2b3b` (H210), olive `#32404d` (H208), pine `#4e6161` (H180). Every canopy is bluer than
  the sea. The *textures* are fine (`pine_clump.png` H94, `scrub_clump.png` H85, `broadleaf` H86) and
  so are the shader constants (`col_dark #2f4a2c`, `TREE_LOOK pine #2c4228`) — the problem is that
  the leaf albedo is V 0.18–0.29, so with sun at 24° on a domed normal the *sky ambient* (blue,
  `ambient_color #8a87a0`, sky contribution 0.5) supplies most of the light and the green cannot
  compete. r1's "lean yellow" edit worked on the texture, which the leaf shader does not even read
  for colour.
- **Fix (GROUND):** raise leaf albedo 2×: `col_dark → #4a5a38`, `col_lit → #9aa86a`,
  `TREE_LOOK` pine `#3e5232 / #8aa058`, umbrella `#425a38 / #96a860`, olive `#5c6a48 / #a4b078`, and
  stop the `NORMAL` dome mixing at 0.45 → 0.25 so side leaves still see the sun; the same for the
  scrub cards' material (bush instance tint ≥ `#6a7a4a`). Bushes need a baked dark *interior* not a
  dark *whole*. **(LOOK):** `ambient_color #8a87a0 → #9a9298` (a touch warmer/neutral, still cooler
  than the sun) so that shadow-side greens go grey-olive, not teal. Target: canopy H 70–140, V 0.20–
  0.35 in shade, 0.40–0.55 lit.

### 6. Boulders: uniform 8–12 m muffins, blue-grey, floating — **ROCKS**
- **Reference beach region:** median `#5c5149` (H25 S20 V36), p10–p90 0.16–0.59: 1–8 m rounded
  blocks, pale warm tops, half buried in sand, dark contact shadows `#55474a`, continuous apron.
- **Ours:** `cliff_coast` apron region `#384760` (**H217** S41 V37), p10–p90 0.24–0.44;
  `cliff_coast_b` apron `#545465` (H240). Every boulder in the foam crop is the same 8–12 m loaf
  with a flat sheared top and a neat white rim; there is nothing under 4 m, nothing angular, nothing
  buried — they sit *on* the water like bread rolls. Shadows under them are hard grey rectangles.
- **Fix:** size distribution log-uniform 0.8–6 m with 30 % under 2 m (a scree MultiMesh for 0.3–1 m
  rubble, ≥ 0.5/m² at the wall foot); 40 % angular (block variant) not rounded; sink 35–50 % and
  tilt ±25°; drop moss on talus (item 1); place 60 % of the apron *on the bench/beach* above the
  waterline and only the largest in the surf; darken the contact ring via `ao_min 0.35 → 0.25` on
  talus only.

### 7. Water: no turquoise band, foam is a 1-px rim — **LOOK (`sea.gdshader`)**
- **Reference bottom-right water region:** teal (H 185–205, S > 0.3) pixels 3.6 %, foam-bright
  (V > 0.72, S < 0.25) 1.6 %; turquoise `#345365` hugs every rock for 5–20 m; foam is ragged
  clumps and 3–5 m streaks.
- **Ours:** `cliff_coast` water region teal **0.6 %**, foam **0.4 %**; water next to rocks `#2d4664`
  (H212) is identical to open water `#304863` — the `band_mid/navy` change is not visible from this
  camera because the sea floor drops at 1:6 right at the wall (depth 10 m at 2 m out). `cliff_arch`
  does show a shallow `#44617a` H207 but no true teal. Foam is a uniform 1-px white outline on each
  boulder; no whitecaps visible in any of the three frames.
- **Fix:** (a) turquoise must come from *distance to rock*, not depth alone: the foam/obstacle term
  already knows the rock foot — add `teal = smoothstep(18, 2, dist_to_rock)` and mix toward
  `#3d8b8f`-class (`(0.10,0.30,0.32)` linear) at 0.6; (b) also flatten the sea floor to a 1:20
  shelf for 15 m in front of every wall/apron in `_gen_sea_cliffs` (ROCKS, one line in the height
  stamp) so depth-based teal exists; (c) foam: ring width 1.5 → 3 m, clump noise threshold lower so
  ≥ 40 % of the ring is solid cream, streak length 4–6 m, whitecap density so ~1 % of open-water
  pixels clip to `foam_color`; (d) foam brightness must clip at V ≥ 0.8 (`#5a5557` measured at a
  "foam" pixel in `cliff_coast` — it is being fogged/graded down).

### 8. Terrain slope between and above the pillars is smeared brown mud — **GROUND**
- **Reference:** slopes above the cliffs are pale limestone with scrub lines (`#8f817d`–`#b5997a`).
- **Ours (`cliff_coast_b` right side, 1100–1600 × 380–700):** region `#6d605a` (H18 S17 V42) with
  visibly stretched texture (2–3 px streaks running diagonally) and no macro structure; `bench_slope`
  patch `#544f51` V32. It is the same chocolate as the rock kit and reads as a melted heightfield.
- **Fix:** the cliff/slope texture set (`Rock021` patches / `Rock` base) is now too dark and too
  warm after the r1 "warm toward `#a08a72`" push: pull albedo tints back to `#bfb09a` (rock) /
  `#b3a48e` (cliff) with the *colour map* doing local darkening; enable Terrain3D's texture
  `uv_scale` anisotropy fix for steep faces (use the triplanar path on Tex CLIFF, `world_space_normal
  _blend` up) so the stretching disappears; keep the r1 `#7f7a76` macro but at 25 % not 50 %.

### 9. Villa: no big shade tree, no walls, no dressing; alpine firs persist — **GROUND (+ hub builders)**
- **Reference:** a 12 m round shade tree over the house, dry-stone walls `#736344` along every road,
  fences, a shed, a well/pergola, a van, pots, pink flowering shrubs; cypresses 3–4; pines are
  umbrella pines; vineyard rows `#443a25` (H41) on `#494625` earth.
- **Ours:** house = two beige boxes with a pink roof; a 60 m grey pole (`#766d69`) through the
  middle; a 40 m pale concrete disc (`#b6a398`, V71 — the brightest area in the frame); vineyards
  `#48534b` (**H136** grey-green vs H41); background trees are still stacked-disc conifers
  (`villa` bg crop: layered cone silhouettes at 450–800 × 120–260); no wall, no fence, no shade
  tree, no outbuilding; frame std 0.11 vs 0.20.
- **Fix:** vineyard MultiMesh colour `#4d5a2a`-class (yellow-olive) on a `#7a6a4a` earth strip; drop
  the disc pad to a dirt/gravel court with a 1 m dry-stone kerb; replace the pole with a 12 m
  cypress pair or remove it from this hub; dry-stone wall segments (`_wall` builder) along the lane
  ±2 m for 60 m, one shed and one pergola; one 12–14 m `umbrella 0.5` shade tree within 6 m of the
  house; cap the "forest conifer" tier at painted density > 0.6 and swap the rest to umbrella pines
  (the r1 threshold 0.45 still leaves the hillside a fir plantation). The hub builders live in
  `island.gd _build_villa_hub`; GROUND owns the scatter/vineyard/pad texture, coordinate the props.

### 10. Lit/shadow separation on rock is still 1.25:1 — **LOOK**
- **Reference:** lit `#b5997a` V70 / shade `#535d73` V45 → 1.6; boulder top V73 / side V33 → 2.2.
- **Ours:** `cliff_coast_b` lit V41 / shade V33 → 1.25; `cliff_arch` right block lit V38 vs face V47
  (the *top* is darker than the face — moss again); `cliff_coast` foreground wall lit V27 vs its
  lower part V18.
- **Fix:** `sun_energy 1.25 → 1.6`, `ambient_energy 0.34 → 0.30`; keep `sun_yaw -62`. This only
  works together with item 1 (a pale albedo makes the sun's contribution visible); measure the
  ratio on the `cliff_coast_b` pillar at 1400,520 vs 1200,520 after both land.

### 11. Clouds lighter than the sky and structureless; no pink glow upper-right — **LOOK**
- **Reference:** clouds `#a4a8bc` / `#a8a9bf` (V73–74, *slightly darker and pinker* than the zenith
  `#a0adc5` V77), soft masses 300–800 px with internal lobes; the upper-right sky warms to
  `#c4b0bb`.
- **Ours:** clouds `#b7b7d3` (V82, lighter than the sky `#aab0cd` V80), two parallel horizontal
  streaks with no internal structure in every frame (`cliff_coast` 700–1300 × 20–70,
  `cliff_coast_b` 0–800 × 20–200); no warm bias anywhere in the sky.
- **Fix:** `cloud_tint` value ≤ sky value (multiply, not add: `(0.96, 0.90, 0.94)` on the sky colour),
  add a second 2-octave layer at half the wavelength inside the smear for lobes, and a sun-side
  `pow(max(dot(dir, sun_dir),0), 4) * #c4b0bb * 0.35` glow in the sky shader.

### 12. Ledge/crest vegetation is discs, not lines — **ROCKS (emit) + GROUND (cards)**
- **Reference:** unbroken lines of scrub along every ledge, 8–12 m pines on every crest step.
- **Ours:** `cliff_coast` arch crop shows ~10 isolated 2–3 m flat green discs (`#415655`) on the
  ledges and *zero* pines on the arch crest; `cliff_coast_b` crest has pines only where the forest
  scatter reaches the edge; discs float 0.5 m above their ledge (visible at 740,430 and 320,500).
- **Fix (ROCKS):** ledge emission 0.5/m → 1.2/m with 1–2.5 m scale jitter and a 0.3 m sink into the
  ledge; crest pines 1 per 40 m² → 1 per 25 m² and *always* one within 4 m of an outer corner.
  **(GROUND):** scrub card with a dark interior and a ragged top (baked gradient 1.0 → 0.5 from
  edge to centre), instance tint per item 5.

---

## Per-lane summary

- **ROCKS (biggest lever this round):** 1, 2, 6, 3-islet, 4-arch, 7b, 12. Acceptance: lit face
  V ≥ 0.60 H 25–35, boulder top the brightest rock (V ≥ 0.65), foreground cliff region std ≥ 0.12,
  no rim brighter than its face, ≥ 3 pillar width classes visible in `cliff_arch`, road visible
  through the arch from `cliff_coast`.
- **LOOK:** 3-horizon, 5-ambient, 7, 10, 11. Acceptance: horizon step ≤ 6 value points over ≥ 40 px,
  teal ≥ 2.5 % / foam ≥ 1.2 % of the `cliff_coast` water region, lit/shade ≥ 1.5 on
  `cliff_coast_b`; whole-frame p1/std/S must stay within 0.03 of today.
- **GROUND:** 4-bench, 5-leaf shader, 8, 9, 12-cards. Acceptance: canopy H 70–140 everywhere, bench
  region ≥ V 0.55 and warmer than the rock, road crown visible at 150 m in `cliff_coast`, no
  stacked-disc conifers in the `villa` frame, vineyard H 35–60.
- **Spots:** re-aim `cliff_arch` at the new arch (-549,-250) — the regression spot has shown the
  wrong subject for two rounds.
