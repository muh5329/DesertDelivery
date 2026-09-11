# Round 3 critique — r2 renders vs `ref_cliff_coast.png` / `ref_villa_vineyard.png`

Judged: `/root/rounds/r2/cliff_coast.png` (0.585), `cliff_coast_b.png` (0.535), `cliff_arch.png` (0.538),
`villa.png` (0.566), against `/root/rounds/r1/`, `/root/rounds/r0/` and the references. Colours are
36 px patch medians (PIL, sRGB) unless marked "region" (median + luminance std / p10 / p50 / p90 of
a rectangle). Reference cliff 2554×1428, villa reference 1622×914, ours 1600×900. Lanes as before:
**LOOK** (`world_kit.gd` `Atmosphere` / `_build_environment` / `sky.gdshader` / `sea.gdshader`),
**ROCKS** (`rock_gen.gd`, `rock.gdshader`, `_cliff_wall` / `_cliff_pillar` / `_sea_arch` /
`_sea_stack` / `_islet` / `_boulder_apron` / `_scree`, `_gen_sea_cliffs`, `_gen_coast_and_islets`),
**GROUND** (`terrain.gd` maps / textures / ground cover / halos, `foliage.py`, `trees.py`,
`leaf.gdshader`, tree / scrub / vine scatters, `_villa_trees`; coordinate hub props with `island.gd`).

## Verdict

**Improved (real, by eye and by patch):**

- The rock is limestone now. Lit pillar face `#a3968b`–`#b7a798` (H27–29, S0.16, V0.64–0.72), arch
  face `#a29386` V0.64 — r1 was `#6a5b54` V0.41 chocolate. Facets, broken crowns, leaning columns and
  the stepped arch crown read in `cliff_arch`; the cream top-rim fillet is gone (arch rim `#565559`,
  darker than its face). The arch has a ~21 m opening with a bench under it; stacks and islets close
  the right third; the near stack sits in the inlet.
- Boulders are no longer uniform muffins: `cliff_coast` foam crop shows 0.5–8 m blocks and rounded
  boulders, tilted, half in the surf, with a scree band. Foam is clumps and streaks, not a 1-px rim
  (foam pixel `#e7d8d2` V0.91).
- Horizon: max one-row step at x 1400 is 0.05 (was 0.17); the sea fogs onto the sky.
- Canopies are green, not teal, where the sun reaches them (`cliff_coast` big tree lit `#34513c` H136;
  villa shade tree `#818a62` H73 — r1 was H189–210). Vine rows lost the grey-green H136.
- Villa: no stacked-disc conifers left in the frame; three shade trees exist; roads faintly read.
- Sky gradient and cloud value are right (clouds `#a4aac3` on a `#96a7c3` zenith, ref `#a9a8bd` on
  `#a0a5bb`).

**Regressed / overshot:**

1. **The whole frame lifted.** `cliff_coast` p1 / p50: r1 0.10 / 0.33 → r2 **0.18 / 0.41** (ref
   0.10 / 0.36); `cliff_coast_b` p50 **0.57**, `cliff_arch` 0.48. The score's colour term fell
   (0.474 → 0.444; arch 0.502 → 0.420) while texture-energy rose — the pale rock arrived and nothing
   dark replaced the chocolate: the darkest 1 % is no longer scrub interiors and rock contacts but mid
   shadow. Every fix below must again be *redistributive*: darks back into foliage interiors, joints,
   contacts and the shade faces; no exposure change.
2. **Tops became the darkest rock.** Ledge top `#363f54` V0.33 (H221) over a face of V0.53; surf
   boulder top `#2c3952` V0.32 vs flank V0.41; ref boulder top `#cbb292` **V0.80** vs side V0.36. This
   is the "stacked bricks with dark mortar" the reviewer sees: every horizontal surface is a dark
   navy band between pale courses (item 1).
3. **Sun-facing faces and joint slivers blow out** (`#dccfca` V0.86 at 700,650; islet `#f2e6d7`
   V0.95), so the outline moved from the top rims (r1) to the vertical edges (r2): pale piping down
   the left edge of every pillar, while the broad camera-facing faces sit at 0.27 of the sun and read
   flat grey (item 2).
4. **Foliage is now lime-yellow and flat** (villa tree region S0.23 / p10 0.26 vs ref S0.40 / p10
   0.19); canopies have no dark interior; crest pines are pale spheres. Vineyards dither
   orange-brown speckle over navy shade (item 6–7).
5. Villa halos merged into chocolate/navy swamps under tree groups (`#232338`, `#303c4d`); the pole,
   the concrete disc (`#b5a299` V0.71, brightest thing in the frame) and the missing walls are
   unchanged for the third round (item 10).
6. World generation: 17.7 s headless on the merge (`[game] world generated in 17653 ms`), 20.5 s in
   the view harness — over the 20 s budget. Profile and cuts in the last section.

---

## Ranked top-12 remaining gaps

### 1. Horizontal surfaces are the darkest rock → courses read as bricks with dark mortar — **ROCKS (shader) + LOOK (sun)**
- **Reference:** boulder top `#cbb292` V0.80 / lit side `#a87a57` V0.66 / shade side `#725f57`
  V0.45 / contact `#5c4c4b` V0.36. Ledge tops on the arch block are its palest pixels
  (`#a5adc2` at 2050,300 over a face `#71808a` V0.54). Bedding shows as *lines* (0.3–1 m dark
  cavity under each ledge) between faces of nearly equal value.
- **Ours:** `cliff_coast_b` ledge tops `#363f54` V0.33 / `#5e585e` V0.37 over faces `#877b74` V0.53
  / `#a79281` V0.65 — top:face **0.55** (ref 1.5–2.2). `cliff_coast` surf boulder top `#2c3952`
  H219 S0.46 V0.32 vs flank `#696467` V0.41; `cliff_arch` boulder `#444148` V0.28 vs `#5d524e`
  V0.36. On the arch pillar (x 650, y 380–560) the beds are 8-px bands at **V0.41–0.45** every
  ~60 px on faces of V0.62–0.69 — a 1.6× step at every course. The tops are as dark and as blue as
  a shaded joint (`#4d555d` V0.36), i.e. they are lit by ambient only.
- **Why:** the sun is at 24° elevation, so a horizontal face receives sin 24° = 0.41 of the sun while
  a face turned to the sun receives 0.9; `ambient_energy 0.25 × sky 0.25` gives the tops almost no
  sky fill (the reference sky is a huge soft source that lights every top). Measured tops are ~2.5×
  darker than even that predicts, so something else is shadowing them — most likely shadow-map
  self-shadowing on grazing faces smeared flat by the soft-high PCF (check by rendering `cliff_coast_b`
  once with `sun.shadow_enabled = false` and once with `rock.gdshader debug_mode 2`; if the tops come
  back pale in the first, raise `shadow_normal_bias 2.0 → 3.0` and `shadow_bias 0.08 → 0.12`).
- **Fix (ROCKS, `rock.gdshader`):** add a hemisphere sky fill on rock only, so tops get sky light
  without raising the global ambient that turned foliage teal: `EMISSION = alb * sky_fill_color *
  clamp(wn.y, 0.0, 1.0) * sky_fill (0.18) * ao` with `sky_fill_color` = the zenith at linear
  (`#9cb2d8`); tops must land at V ≥ 0.60 in `cliff_coast_b` and never below the face under them.
  Keep the bedding *line* (COLOR.g cavity, ≤ 0.5 m tall) but make the *soft-bed* face darkening
  ≤ 5 % (`bed_darken 0.10–0.15 → 0.05`): the ref's courses differ by texture, not by value.
  **(LOOK)** `sun_elevation_deg 24 → 32` (top gets 0.53 of the sun, faces still 0.85; ref shadows
  are long but its tops are the brightest surface, which needs ≥ 30°). Acceptance: `cliff_coast_b`
  ledge top at 1048,588 ≥ V0.60 and ≥ the face at 1048,624; surf boulder top ≥ its flank.

### 2. The sun rakes along the wall: broad faces flat grey, edges and islets blown — **LOOK (yaw) + ROCKS (tint)**
- **Reference:** the broad faces that face the camera are the lit, bone-white ones (`#b5997a` V0.70,
  `#b5a28c` at 600,300), joint faces are half-lit, S/E faces and the arch interior are shade
  `#535d73` (H221 S0.27 V0.45). Lit:shade 1.6, max rock V ≈ 0.80, lit S ≈ 0.25–0.32.
- **Ours:** with `sun_yaw −62` the light travels ENE: a west face gets 0.88, a north joint face
  −0.47 (shade), and the NW-facing broad faces the `cliff_coast` camera looks at get **0.27**. So the
  wall we see is ambient-flat (`#9d8f84`–`#a3968b` V0.62, S0.15) while every west-facing sliver is
  `#dccfca` V0.86–0.95 (S0.08–0.12) — a bright piping down the left edge of each pillar (700,650;
  505,450 vs 650,420) and 2–3 blown white islets (1130,250 `#f2e6d7`). Lit rock is also under-
  saturated: S0.15–0.20 vs ref 0.25–0.32 — `LIMESTONE_TINT (0.90,0.80,0.64)` is right in hue but
  the graded result is greyer than the ref because `tex_saturation 0.55` and `macro_grey` pull it.
- **Fix (LOOK):** `sun_yaw_deg −62 → −120` (sun in the WNW, light toward ESE): a NW-facing face gets
  0.96, W 0.87, N joint 0.5, S/E faces and the arch interior shade — the reference's distribution
  (lit broad faces, half-lit joints, shaded right-facing walls). Together with elevation 32° (item 1)
  no face exceeds cos 32° × 1.6. Check the villa (camera looks NW → sun front-left at 45°, long
  shadows toward the camera, as in `ref_villa_vineyard`) and `harbour` once; if the glitter path
  intrudes bottom-right in `cliff_coast`, cap `sparkle 0.9 → 0.5`. `glow_hdr_threshold 0.9 → 1.3`
  (lit limestone at ~1.1 linear is blooming: the islets' soft white edges). **(ROCKS)**
  `LIMESTONE_TINT → (0.84, 0.76, 0.62)` so a fully lit face lands at V0.72–0.78, not 0.95;
  `tex_saturation 0.55 → 0.7`, `macro_grey → #b0a89a` (warmer). Acceptance: no rock pixel over V0.85
  outside foam; lit face S ≥ 0.22; lit:shade 1.5–1.7 on `cliff_coast_b` (1230,700 vs 1010,700).

### 3. The foreground wall (left 16 % of `cliff_coast`) is still one smooth slab — **ROCKS**
- **Reference (0–440 × 250–900 region):** `#7f695b`, lumstd **0.152**, p10–p90 0.19–0.60: the near
  cliff is 4–6 pillars of different depth with a collapsed corner, a scrub ledge at a third of its
  height, boulders at its foot and a 5–10 % lean.
- **Ours (0–250 × 350–900):** `#605951`, lumstd **0.101**, p10–p90 0.25–0.52; the column down x 120
  is one smooth gradient (`#877764` V0.53 at y 400 → `#5c534b` V0.36 → `#5c544d`) with a fine
  horizontal wood-grain (the triplanar texture at 3 m tiles seen from 15 m) and *no* facet or shadow
  breaks over 550 px. It is the north wall's end column at 15 m: facets of 0.45–0.7 m at 3.8–6 m are
  invisible on a face that gets 0.27 sun and casts nothing on itself.
- **Fix:** treat the last 2–3 columns of every wall end (and any column within 40 m of a camera
  spot) as a **hero end**: split it into 3–4 pillars offset 2–4 m in depth with a 1.5 m ledge between
  them (scrub on it), lop the outer corner (a 6–10 m diagonal collapse with 3–5 debris blocks 2–4 m
  at the foot), give facets `facet_amp 1.2–1.8 m at 6–9 m` on those pieces, and bake a stronger
  crease AO (concavity `conc * 0.5 → 0.8` on hero pieces). Near-range detail: a second, finer
  triplanar octave (`tex_metres 3 → 0.8` for the normal map only, strength 0.4) so the grain is
  pitting, not stripes. Also the arch crown: the stepped lintel shows as a **diagonal dotted
  staircase** on the lintel's front face (c. 850,300 in `cliff_coast`, 8 equal risers) — steps must
  be 2–4 uneven blocks with the side rows collapsed, not a stair. Acceptance: foreground region
  lumstd ≥ 0.14 with p10 ≤ 0.20; no straight run of equal steps on the arch.

### 4. Far islets are white cubes with lime pom-poms, not a hazed mountain — **LOOK + ROCKS**
- **Reference (2200–2500 × 400–700):** islet `#6f88a5` (H212 S0.33 V0.65), region lumstd **0.054**,
  p90 0.61 — darker than the sky beside it (`#8b96af` V0.69 / `#a9a3b7` V0.72), a single 200 m
  mass with a soft green cap, dissolving upward into the pink haze.
- **Ours (1100–1310 × 190–390):** lit faces `#f2e6d7` **V0.95**, `#ede0ce` V0.93; region p90 0.91,
  lumstd 0.155; brighter than the sky (`#93a6c2` V0.76). The headland wall at the same 380–430 m
  reads correctly fogged (`#6d8b8f`–`#7d9197` V0.56–0.59), so it is not the fog density: it is the
  sun-facing (W) faces at 1.6 × 0.88 with albedo 0.9 plus glow — 1.1 linear survives 63 % fog. The
  islets are three separate vertical prisms with flat tops carrying a 12 m lime sphere; they read as
  sugar cubes 100 m away.
- **Fix (LOOK):** items 1–2 (yaw, tint, glow threshold) take the islet faces to ~V0.75 pre-fog;
  additionally raise `fog_height_density 0.012 → 0.03` with `fog_height 2 → 12` so the sea-level
  haze is denser at the islets' feet than at their crowns (ref: bases hazier than tops); confirm on a
  patch at 1130,250 ≤ V0.72 and ≤ the sky beside it. **(ROCKS, `_islet`):** make each islet one
  mass — a 90–120 m long, 50–70 m tall stratified block (`_cliff_wall`-style, 3–4 columns of
  differing height, 30 % of the top a sloped scree shoulder) with its stacks *attached* at one end,
  and move the pair 120 m further out (x −720…−690) so the fog does the dissolving; the crown gets
  dark scrub + 2 umbrella pines with `far` LOD tints (`#3a4a3a`), never a bright sphere.
  Acceptance: islet region p90 ≤ 0.70, lumstd ≤ 0.09.

### 5. The darks are gone: the frame's histogram floated up — **all three lanes, redistributive**
- **Reference:** p1 0.10, p50 0.36, std 0.17; the darkest 1 % is scrub interior (`#1a2221`), boulder
  contacts (`#5c4c4b` → `#3a3033`), joint cavities and the arch's shaded interior.
- **Ours:** `cliff_coast` p1 **0.18**, p50 0.41 (r1: 0.10 / 0.33); `cliff_coast_b` p50 0.57,
  `cliff_arch` p1 0.17. Our darkest pixels are canopy shade (`#1c283e` H218 — navy, not green) and
  water; rock contacts `#696467` V0.41, joint `#4d555d` V0.36, bush interior `#3c575f` V0.37.
- **Fix:** LOOK keeps exposure / contrast / ambient where they are (the *lit* values are now right).
  **ROCKS:** `ao_min 0.35 → 0.28` and `ao_warm_tint → (0.50, 0.46, 0.46)` (contacts to V ≈ 0.30,
  cool not warm — ref contacts are `#5c4c4b`/`#55474a`); joint groove floor `bed_line_strength
  0.3 → 0.5` limited to the 0.5 m cavity; talus `ao_min 0.25 → 0.20`. **GROUND:** the baked card
  interior 0.5–0.7 → **0.30–0.45** of the rim (ref bush core `#31341a`, tree core `#1a2221`), tree
  canopy shade floor `shade_warm` at V ≤ 0.22 and H 70–110 (not blue: 200,250 `#1c283e` must become
  `#25301c`-class). Acceptance: `cliff_coast` p1 ≤ 0.12 with p50 0.34–0.38; the darkest 1 % must be
  foliage interiors and rock contacts (inspect a `lum < p1` mask), not sky-lit canopy.

### 6. Trees are lime-yellow flat blobs; crest pines are pale spheres — **GROUND**
- **Reference:** villa shade tree region (470–720 × 60–300) `#5b673e` H77 **S0.40** V0.40, lumstd
  0.160, p10 0.19 — a lit crown `#707f37` (S0.57) over a shade core `#4b481c` V0.29; coast trees
  in shade `#263030`/`#293139`; the brightest foliage is darker than the rock in shadow. Canopies
  have soft internal lobes and an opaque silhouette.
- **Ours:** villa tree region `#707359` H66 **S0.23** V0.45, p10 0.26 (lit `#818a62` S0.29, shade
  `#655b49` H39 — a *brown* shade side); `cliff_coast` big tree lit `#34513c` OK but its sky-facing
  edge `#42645b` H164 and shade `#1c283e` H218 are still teal/navy where the sky is behind them
  (8.3 % of the canopy area is H165–230). Every canopy is the same pale grey-green sphere with
  1-px confetti edges (alpha-scissor at 0.45 on 4× minified cards); umbrella pines on the crest
  `#708d71` V0.55 — brighter than the rock they stand on.
- **Fix (`leaf.gdshader`, `foliage.py`, `TREE_LOOK`):** saturation up, value down: `col_lit
  #9aa86a → #8a9a4e`, `col_dark #4a5a38 → #3d4a28`; pine `#3e5232/#8aa058 → #33452a/#6d8446`,
  umbrella `#425a38/#96a860 → #384a2c/#7a9250`, olive `#5c6a48/#a4b078 → #55613e/#98a468`;
  `shade_warm` floor `→ #2c3a20` (olive, never the ambient blue); wrap 0.55 → 0.4 so the shade
  side is actually darker; kill the confetti with `alpha_scissor 0.45 → 0.3` + `alpha_antialiasing`
  or a mip-biased alpha (`texture(…, uv, -1.0)`), and bake bigger leaf clusters (cards with 3–4
  lobes and a 0.35 interior). Crest pines: `far` tint × 0.7. Acceptance: villa tree region S ≥ 0.35,
  p10 ≤ 0.20; canopy H 70–140 on ≥ 97 % of canopy pixels in `cliff_coast`; crest pine V ≤ 0.45.

### 7. Vineyards are orange speckle over navy — **GROUND**
- **Reference (0–450 × 250–560 of the villa ref):** region mean `#594d2b` H44 **S0.52**; hue mass
  70 % in H25–70 (`#795730` earth / `#535023` vine), 1 % blue.
- **Ours (0–500 × 300–560):** mean `#62665e` H91 **S0.08**; hue mass: 21 % H170–260 (`#3b485b`
  navy shade), 13 % H110–170 grey-green, 10 % H0–45 (`#886456`/`#927957` orange-brown lit cards).
  The eye fuses orange lit cards + navy shade into "orange rows on mud".
- **Fix:** vine card (`foliage.py` broadleaf/vine) lit `#6d7a36` H70 S0.55 / shade `#3f4420`;
  instance tint `(1.0, 0.94, 0.72) → (0.95, 1.0, 0.75)`; use the same `shade_warm` olive floor as
  item 6 (no navy under the rows); the soil strip `Soil (0.78, 0.68, 0.50)` is fine but the farm
  band 0 `(0.66, 0.56, 0.38)` must not darken under the halo pass (exclude vines from `_halo_bushes`).
  Acceptance: vineyard region mean S ≥ 0.35, H 35–70; < 4 % of its pixels H > 170.

### 8. Water: cyan where the reference is dark green; surf lace; no swell tone — **LOOK (`sea.gdshader`)**
- **Reference (1500–2554 × 800–1400):** teal 5.2 %, green skirt (H120–170) **0.83 %** median
  `#385d51` H160 S0.40 **V0.36** (darker than open water `#2e3e5e` V0.37, greener); foam 1.44 % as
  ragged clumps at rock feet; open water HF std 0.0087 with broad swell bands (region lum std
  **0.067**) and 2–6 m whitecap streaks ~1 per 200 m².
- **Ours (900–1600 × 480–860):** teal 1.8 %, green 0.04 %; the near-rock colour `#30586e` H201
  S0.56 **V0.43** is *lighter and bluer* than open water (`#2c415f`), so the halo reads as a cyan
  glow, not a shallow; surf zone (450–1000 × 600–900) foam **6.9 %** as uniform white dashes
  (HF std 0.064 — 7× the ref's) — the shelf is laced like TV static in `cliff_arch`; open water is
  flat (region std 0.034, no swell bands). Open water itself matches (`#2c415f` vs `#2e3e5e`).
- **Fix:** `col_teal (0.10,0.30,0.32) → (0.05,0.15,0.13)` linear (target `#385d51`) and blend it
  *multiplicatively* toward dark green with `prox`, not additively; add a sand-lit skirt only where
  depth < 1.2 m (`#6f7e6a`-class, 0.5 m wide). Foam: keep the ring/streaks but raise the clump
  threshold so ≤ 35 % of the ring is solid, kill the dashes in the 3–12 m band (`whitecap` gate
  `prox < 0.2` only, threshold 0.9 → 0.96, patch mask 40 m → 25 m at 30 % cover). Swell: a 12–20 m
  noise (0.4 m amplitude on the normal) that modulates the Fresnel sky term ±25 % so the open sea
  shows light/dark bands. Acceptance: green (H120–170, S > 0.3) ≥ 0.5 % and foam 1–2 % of the
  water region; surf-zone HF std ≤ 0.03; open-water region std ≥ 0.05.

### 9. Bench under the arch: pink plaster with white polka dots, in a black wedge — **ROCKS + GROUND**
- **Reference:** the arch frames the road (`#c4ad8f` crown V0.77, `#978178` V0.59 margin) with a
  car; the bench is pale earth `#a28d7f` with scrub tufts, lit.
- **Ours (`cliff_coast` 700–1150 × 380–620):** bench `#bda7a3` H9 S0.14 V0.74 (pinkish plaster —
  the road crown `(1.0,0.95,0.85)` under the split-tone), speckled with ~60 bright 2–4 px dots
  (the 0.3–1 m scree drawn in the pale rock material at 150 m: `#baa7a2`), a black-navy wedge
  `#3a4964` V0.39 at the arch foot (the bench in the arch's own shadow), and six lime discs in the
  opening; no ruts, no margin, no car-scale cue.
- **Fix (ROCKS):** scree beyond 60 m must not draw as dots — `_scree` `far` LOD 500 → 60 m, and the
  scree material a sand-dusted talus (`sand_amount 0.6`) so it reads as gravel; keep the opening
  bush-free (`road_clear + 8`). With yaw −120 the bench is lit (verify: patch at 740,520 ≥ V0.5).
  **(GROUND):** bench tint `#b09776` (H30 S0.33) not `(1.0,0.95,0.85)` — target crown `#c4ad8f`,
  margin `#8f7658`; ruts as two 0.5 m colour-map stripes at ±0.9 m; and dress the bench with 6–10
  1–2 m scrub tufts per 100 m² and 3–4 boulders 1–2 m (ROCKS) so it has scale. Acceptance: bench
  patch V 0.55–0.7, H 20–35, S ≥ 0.25; ≤ 5 bright dots in the crop.

### 10. Villa: pole, disc, no walls, mud swamps under trees — **GROUND (halos, scatter) + hub builder**
- **Reference:** frame std **0.204**, p1 0.08; dry-stone walls `#b3a38a`/`#363430` along every
  lane, fences, shed, pergola, van; earth `#a78d69`, road `#a77e4b`, dark humus only in 1–1.5 m
  contact rings.
- **Ours:** frame std 0.130 (r1 0.113); a 60 m pole (`#7d8171`) through the centre, a 40 m concrete
  disc `#b5a299` V0.71 (the brightest surface, with a tree shadow across it), no wall / fence /
  shed; under every tree group a 10–20 m chocolate-navy blotch (`#232338`, `#303c4d`, `#3a573b`:
  halo 2.6 m × 0.45 at 3 m/px + the tree's own shadow + the canopy-density darkening, all stacked);
  background outcrops are navy-teal stepped blocks (`#3f5d69` H197) with cream tops.
- **Fix (GROUND):** `paint_halos` tree radius 2.6 → 1.8 m, strength 0.45 → 0.25, colour → warm
  `#6a5a48`; cap the *sum* of halo + canopy-density darkening at 35 %; skip halos for trees whose
  shadow already covers the spot is impossible — so instead lighten `_grid_field_map` canopy
  darkening 50 % → 25 % where tree density > 0.5. Vine/olive rows off the halo list (item 7).
  **(hub builder, `island.gd _build_villa_hub`, coordinate with GROUND):** delete the pole; the disc
  → a 14 m gravel court (`Gravel` control-map stamp, kerb of 0.5 m blocks); dry-stone wall
  segments (`_wall`, 1 m high, `#b3a38a`) along the lane ±2 m for 60 m each side, a 6×4 m shed and
  a pergola at the house, 2 cypresses at the gate. **(ROCKS):** highland outcrops in the villa
  background are r0-style bedded blocks with dark tops (item 1 fixes the tops; give them
  `steps`/facets like the coast pieces). Acceptance: villa std ≥ 0.17; no pixel run > 6 m of
  `V < 0.25` on flat ground outside a cast shadow; ≥ 40 m of wall visible.

### 11. Terrain steep faces are still a striated wax curtain — **GROUND (+ ROCKS veneer)**
- **Reference:** slopes above the walls are blocky rock with scrub lines (`#8f817d`–`#b5997a`).
- **Ours (`cliff_coast_b` 650–950 × 420–650 region `#ad968c` H18 S0.19 V0.68):** pale pink with 2–3 px
  **vertical streaks** across the whole face (Terrain3D's planar UV stretched down a 60° slope; the
  r2 50/50 fine/coarse patching only made two streak frequencies), one orange drip, and embedded
  rounded boulders with dark tops. Reads as melted wax, not rock; it is the biggest single surface
  in that frame.
- **Fix (GROUND):** Terrain3D 1.0's material has no per-texture triplanar; use the two knobs it has:
  `world_space_normal_blend` on and **`dual_scaling`** (`dual_scale_texture` = CLIFF, `dual_scale_far
  /near`, `tri_scale_reduction`) so the steep faces sample a 0.25× scale of the same texture, which
  hides the stretch; and paint a 25 % `#7f7a76` macro on `sl > 0.5` only. If the streaks survive,
  hand faces steeper than 55° in the massif to ROCKS as a **veneer**: `_cliff_wall` along the
  contour at 40 % scale (columns 4–8 m, 8–14 m tall) so the terrain face is hidden behind bedded
  blocks — that is what the reference's slopes actually are. Acceptance: the 650–950 × 420–650 crop
  of `cliff_coast_b` at 3× shows no run of parallel streaks longer than 40 px (today they span the
  whole face), and the region (`#ad968c` H18 V0.68 today, p10–p90 0.46–0.70) gains real darks:
  p10 ≤ 0.35 from ledge shadows and scrub lines, not from streaks.

### 12. Sky: too blue, no pink glow upper-right, faint dark line at the horizon — **LOOK**
- **Reference:** sky region (900–2554 × 0–300) `#a0a5bb` H228 **S0.14**; upper-right `#a09eb5`
  H245 S0.13 (pink-lilac), clouds `#a9a8bd`; the horizon dissolves over ~100 px.
- **Ours:** sky region `#93a5c0` H216 **S0.23**; upper-right `#93a0b8` S0.20 (no warm lobe reaches
  the frame — the glow sits on the sun, which is behind the camera); a 3–4 px darker line at the
  horizon (`#7b95b5` V0.71 between V0.75 above and V0.72 below at y 285, x 1400).
- **Fix:** `sky_top #9cb2d8 → #a3aecb`, `sky_horizon #6a8bb6 → #7d93b4` (S 0.23 → 0.15), and make
  the wide glow lobe azimuth-independent above 10° elevation (`glow_wide 0.14 → 0.35`, colour
  `#c4b0bb` × 0.4) so the upper sky warms to `#a5a3b8`-class on the sun side of the frame; the
  horizon line is the sea's last rows (`sea_horizon_gain 0.97 → 1.0`) or the sky's ground half
  (`ground_energy`): check x 1400 rows 280–290 for a monotonic ramp. Acceptance: sky S ≤ 0.17,
  upper-right H ≥ 235, no row dip > 0.02.

---

## Minor (fix if free)
- Ledge scrub discs still float / stand proud on the arch's ledges (756,404); bushes in the arch
  opening are the brightest greens in the frame — ROCKS sink 0.3 → 0.5 m, GROUND card tint × 0.8 on
  ledge emission.
- `cliff_coast_b` water near the wall: hard 1-px foam line along the whole shore at 700–1000 × 690.
- The villa's roads are lighter than the ground (`#8f746b` V0.56) but their margins are missing on
  the far lanes; the reference's road is *the* brightest ground (`#a77e4b` V0.65).
- Sea-cliff faces above the water line in the `villa` background carry the r0 navy tint (`#3f5d69`).

---

## Generation time: 17.7 s headless on the merge (20.5 s in the harness) — where it goes

Measured on a throwaway copy of `master` with per-pass timers (`architecture_tests`, one run; the
`[terrain] build stages` line is the project's own):

| pass | ms | lane |
|---|---|---|
| `terrain.build()` heightfield | 2 650 (of which the `base_height` N² loop 1 160) | GROUND |
| `t3d_setup` | 530 | GROUND |
| `_build_t3d_maps` (1024² per-pixel GDScript loop) | 3 610 | GROUND |
| `t3d_import` | 150 | GROUND |
| `plant_ground_cover` (316 792 instances) | 4 210 | GROUND |
| `_gen_coast_and_islets` excluding sea cliffs (160 stacks / 700 shore boulders by rejection sampling) | ~1 100 | ROCKS |
| `_gen_sea_cliffs` (walls, arch, aprons, scree, islets) | 1 220 | ROCKS |
| `_scatter_slope_breaks` massif (3 m grid, 724×575) | 920 | GROUND |
| `_scatter_slope_breaks` world (4.5 m grid) | 1 320 | GROUND |
| `paint_halos` (26 743 points) | 80 | GROUND |
| forest / badlands / farmland / town / highlands / south shore | ~1 800 | misc |
| **total** | **18 680** (instrumented) | |

The rock mesh bake is *not* in this number (it is lazy, at chunk build: ~1.5–2 s across the island).

**ROCKS must cut ≥ 2 s** — all of it is in one call: `_near_road()` → `terrain.nearest_road()` is an
expanding ring search (up to 60 rings ≈ 14 k cell lookups) and it is called for every candidate
*after* the O(1) `road_dist_at` test passes — i.e. `road_dist_at(x,z) < r or _near_road(x,z,r)`
calls the expensive one exactly when the cheap one says "far". The sea-stack loop (up to 90 000
tries, offshore points are the worst case for the ring search), the 700 shore boulders, every
apron boulder, every scree pebble (`_boulder_apron`, `_scree`, `_cliff_wall` column push, ledge
scrub) go through it. Fix: guard it — `if terrain.road_dist_at(x, z) > r + 6.0: return false`
inside `_near_road` (`road_dist` is a 3 m grid capped at 40 m; the only reason `_near_road` exists
is bridges/viaducts, which `road_dist` ignores — add a separate small list of bridge/viaduct
segments to test directly, ≤ 20 segments). Expected: `_gen_coast_and_islets` 1.1 → 0.2 s,
`_gen_sea_cliffs` 1.2 → 0.5 s. Also drop the sea-stack tries cap 90 000 → 20 000 (160 stacks are
found long before) and pre-filter the shore loop by `is_land`.

**GROUND must cut ≥ 2 s** — pick two of:
1. **Delete both `_scatter_slope_breaks` walks (2.2 s):** `_build_t3d_maps` already classifies
   every 1.5 m cell as crest (flat over steep) or foot (flat under steep) for the crest rock lip and
   the cliff-foot darkening; push those cells into two `PackedVector2Array`s during that loop (free)
   and have `island.gd` draw the crest/foot bushes from the lists (subsample 1 in 3 on the massif,
   1 in 6 elsewhere). Same result, 0 s.
2. **`plant_ground_cover` (4.2 s):** 317 k instances at full density is also wrong for the look
   (RESEARCH §3.4: patches at ~45 % coverage, never a lawn). Mask with a 15 m noise at 45 %
   coverage (−55 % instances, ≈ −2.2 s) and replace the per-instance `height_at()` (a GDScript
   bilinear) with `heights[id] + slope-based offset` (another −0.5 s).
3. **`_build_t3d_maps` (3.6 s):** 34 % of the 1024² map is the sea rim outside ±624 m and ~30 % of
   the rest is sea floor: `continue` on those before any noise sample (≈ −1.2 s).
4. **`base_height` (1.2 s):** the three FastNoiseLite layers can be fetched as images
   (`get_image(N, N)`, native) and composed per cell (≈ −0.8 s).

Acceptance for round 3: `[game] world generated` ≤ 16 s headless on the merged branch **and**
≤ 18 s in the view harness; report the `[terrain] build stages` line and the per-pass numbers
above in each CHANGELOG.

---

## Per-lane summary

- **ROCKS:** 1 (shader sky fill, bed_darken), 2 (tint/saturation), 3 (hero wall ends, arch stair),
  4-islet mass, 5 (contacts/joints), 9 (scree LOD/material, bench dressing), 10-outcrops, 11-veneer
  if GROUND cannot kill the streaks; **≥ 2 s** via `_near_road`. Acceptance: tops ≥ faces on
  `cliff_coast_b` ledges and surf boulders; no rock pixel > V0.85; foreground region lumstd ≥ 0.14;
  islet region p90 ≤ 0.70; contacts V ≤ 0.32.
- **LOOK:** 1-elevation, 2-yaw/glow, 4-height fog, 8 (sea), 12 (sky). Acceptance: lit:shade 1.5–1.7
  on rock with the *broad* faces lit; whole-frame p1 back to ≤ 0.12 without touching exposure (that
  is items 5–6's job — LOOK must not compensate for them); green skirt ≥ 0.5 %, foam 1–2 %,
  surf HF ≤ 0.03; sky S ≤ 0.17.
- **GROUND:** 5-interiors, 6 (leaf shader / cards), 7 (vines), 9-bench paint, 10 (halos, hub
  dressing with the hub builder), 11 (Terrain3D dual scaling); **≥ 2 s** via slope-break lists and
  ground-cover masking. Acceptance: villa tree region S ≥ 0.35 / p10 ≤ 0.20; canopy H 70–140 on
  ≥ 97 % of canopy pixels; vineyard region S ≥ 0.35; villa frame std ≥ 0.17; no navy blotches on
  flat ground; steep-face streak ratio ≤ 1.3.
- **Spots:** keep all four; add `islet_far` (from `[-598,38,-326]` at `[-640,20,60]`) so the islet
  work is judged at its real distance.
