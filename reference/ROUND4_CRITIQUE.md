# Round 4 critique — r3 merged renders vs `ref_cliff_coast.png` / `ref_villa_vineyard.png`

Judged: `/root/rounds/r3/cliff_coast.png` (0.590), `cliff_coast_b.png` (0.576), `cliff_arch.png` (0.574),
`villa.png` (0.579) against `/root/rounds/r2/` and the references. Colours are PIL medians of 16–36 px
patches (sRGB) unless marked "region" (median + luminance std / p10 / p50 / p90 of a rectangle; hue
shares are % of the region's pixels in a hue band). Reference cliff 2554×1428, villa ref 1622×914,
ours 1600×900. Lanes: **LOOK** (`world_kit.gd` `Atmosphere` / `_build_environment` / `_build_sea`,
`sky.gdshader`, `sea.gdshader`), **ROCKS** (`rock_gen.gd`, `rock.gdshader`, `_cliff_wall` /
`_cliff_pillar` / `_sea_arch` / `_sea_stack` / `_islet` / `_boulder_apron` / `_scree`,
`_gen_sea_cliffs`), **GROUND** (`terrain.gd` maps / textures / cover, `foliage.py`, `trees.py`,
`leaf.gdshader`, scatters in `island.gd`).

Generation time on `master`: **10.0 s headless** (`[terrain] build stages: heightfield 2471,
t3d_setup 517, t3d_maps 2861, t3d_import 138, ground_cover 1305 (150 299)`), 10.5 s in the view
harness. That is ~8 s under the 18 s budget: each lane may spend ≤ 2 s this round, no more.

## Why the merge scored 0.590 when r3_look alone scored 0.625

Re-rendered `f5d323a` (r3_look on the r2 rocks/ground) in a scratch clone: **0.625** (colour 0.501,
texture-energy 0.627, layout 0.900). Merge: 0.590 (colour 0.487, texture **0.549**, layout 0.893).

1. **The rock lost its cool, sky-lit mass.** In r3_look-alone the RockGen normals were still inverted,
   so every face the `cliff_coast` camera looks at got ambient only and rendered grey-cream
   (`#85776b` H27 S0.20, `#9d8573` S0.27). That accidentally matched the reference, whose dominant
   rock bin is *shade*: H210–240 S0.17–0.33 V0.33–0.67 is **14.0 %** of the ref frame (the arch block
   and both walls are sky-lit, the sun is ahead-left of the camera). r3_rocks fixed the normals and
   retuned `base_tint` / `sun_gain` / `tex_saturation 0.7` / `macro_grey` under the r2 sun (yaw −62,
   broad faces at 0.27 of the sun); r3_look moved the sun to yaw −120 where those same faces get 0.96.
   Merged, every camera-facing face is sun-square and warm: that bin is **1.8 %** of our frame
   (r3_look-alone 7.9 %), while H0–30 S0.33–0.50 V0.67–0.83 (tan) is 5.7 % vs the ref's 0.7 %.
2. **Texture energy went the wrong way in five cells.** The bottom-left 3×2 cells (hero wall end,
   surf) went from −32/−28/−9/−2/+12/+26 ×10⁻³ (look-only, vs ref) to **+42/+41/+18/+41/+25/+65**:
   the hero facets, the 0.8 m fine normal octave, crack scrub and the collapsed corner are busier
   than the reference's smooth 2–4 m planes. The top-left cells (the big tree and canopy line) went
   −39/−59 → **−74/−70**: the mip-biased alpha turned the leafy silhouettes into smooth opaque blobs.
   The arch cells (+46/+38 → **+63/+51/+67**) are the staircase scribbles and joint lines (item 4).

Neither lane was wrong in isolation; the tint and the sun were tuned against each other. Round 4
must tune the rock **under the merged sun** and treat "cool sky-lit shade mass" as the target.

Two scratch experiments on `master` (not committed; numbers for calibration only):
- **exp1 (ROCKS palette only):** `LIMESTONE_TINT (0.57,0.52,0.45) → (0.55,0.53,0.49)`,
  `tex_saturation 0.7 → 0.45`, macro tint mix 0.5 → 0.25, `shade_fill 0.08 → 0.30` with
  `shade_fill_color (0.56,0.60,0.74)`, `sun_gain 0.16 → 0.13`, `sun_color #ffd6b0 → #ffe2c6`: lit
  faces `#af9e96` H19 S0.14 V0.69, `#a99489` S0.19; stack "shade" `#ac9683` S0.24 (was `#c2926c`
  S0.44); by eye it is limestone again. Score 0.580 (colour 0.473): the histogram wants the *shade*
  bin, not paler lit faces — the palette alone is necessary, not sufficient.
- **exp2 (exp1 + LOOK `sun_yaw −120 → −160`, `sun_elevation 32 → 36`):** cool-shade share of the
  rock band 0.07 → **0.18**, frame p50 0.414 → **0.347** (ref 0.354), p1 0.118; `cliff_coast` 0.596
  (layout 0.907), villa 0.587 — but `cliff_coast_b` 0.526 (its wall goes into shadow, lit face
  V0.28) and the shade faces sit at `#334157` V0.34 S0.41 (ref shade `#535d73` V0.45 S0.27):
  the sun placement works for the primary spot only together with a brighter, greyer shade fill
  (items 2–3).

---

## Ranked gaps

### 1. Rock is tan/orange: lit limestone S0.29–0.46 against the reference's S0.20–0.25 — **ROCKS (+ LOOK sun colour)**
- **Reference:** pale rock (V > 0.55, S < 0.35) is 22 % of the rock band, median **H31 S0.21 V0.68**;
  the brightest rock (V > 0.75) is *cool* (H219 S0.17: sky-lit tops). Lit warm faces `#988374`
  (H25 S0.24 V0.60), `#b79c7f` (S0.31, only in the near foreground), `#917d6f` S0.23.
- **Ours (`cliff_coast`):** pale warm rock 33 % of the band at **H25 S0.34 V0.71**; arch face
  `#c19e89` S0.29, left pillar `#ba9177` S0.36, hero face `#976f51` **S0.46**, near stack `#d6a77b`
  S0.43 V0.84, surf boulder `#c59d80` S0.35, bench `#ba9274` S0.38. `cliff_arch` pillar `#a57859`
  S0.46. r2 was S0.18 — this is a regression in hue, even though the value is now right.
- **Why:** `LIMESTONE_TINT (0.57,0.52,0.45)` is H25 S0.21 in linear, then ×`sun_color #ffd6b0`
  (S0.31), ×`macro_rust #c49a6a` at 50 % mix, ×`sand_color (0.60,0.53,0.42)` at the foot,
  `tex_saturation 0.7`, and the grade (`contrast 1.28`, `lift_white #f5e9ea`) multiplies saturation
  again. With the sun square on the face there is no cool sky term to cancel the warm sun.
- **Fix (ROCKS, `rock.gdshader` / `world_kit.gd`):** `LIMESTONE_TINT → (0.55, 0.53, 0.49)` (sRGB
  `#c3bfb5`), `tex_saturation 0.7 → 0.45`, the macro tint mix `mix(vec3(1.0), macro_tint, 0.5) →
  0.25`, `macro_rust #c49a6a → #b8a184`, `sand_color → (0.58, 0.53, 0.45)`, `fracture_color` stays
  (the ref's undersides *are* orange `#a08060`). **(LOOK)** `sun_color #ffd6b0 → #ffe2c6` (S0.22 —
  the ref's lit faces are warm because of the *ratio* to blue shade, not because the sun is orange).
- **Verify:** `cliff_coast` patches 700,330 / 650,500 / 120,650 all at S 0.14–0.25, H 18–30,
  V 0.60–0.72 (exp1 measured `#af9e96` S0.14 / `#a99489` S0.19 / `#816f60` S0.26); no rock pixel
  with S > 0.35 outside fracture undersides.

### 2. No sky-lit shade mass: the sun is square on every face the camera sees — **LOOK (sun) + ROCKS (shade fill)**
- **Reference:** the arch block and the two big walls are *in shade*, lit by the sky: `#5b6984`,
  `#606d85`, `#4f596f` (H215–221 S0.28–0.32 V0.40–0.53); the arch interior `#6c7586` V0.53. Only
  the left cliff, tops and the boulder tops carry warm sun. The sun is ahead-left of the camera
  (pink glow upper right, shadows toward the camera, boulder camera-sides dark `#51464c`).
- **Ours:** rock band region `#817063` H25 S0.23 V0.51 (ref `#565c6a` H221 S0.19 V0.42); cool-shade
  share 7 % (ref rock band ~45 % of its pixels are H200–240). With `sun_yaw −120` the camera at
  `cliff_coast` (looking toward yaw 149°) has the sun 90° off its axis; NW faces get 0.96 sun.
  The only shade is the arch soffit `#33464c` and the interior `#354357` — V0.30–0.34, S0.34–0.39,
  i.e. darker and bluer than the ref's shade by a full stop.
- **Fix (LOOK):** move the sun ahead of the primary camera: `sun_yaw_deg −120 → −150…−160`,
  `sun_elevation_deg 32 → 36` (exp2: cool-shade share 0.18, p50 0.347). Because that puts
  `cliff_coast_b`'s wall in shadow (0.526), compensate in the *shade*, not the sun: `ambient_energy
  0.3 → 0.4` with `ambient_sky_contribution 0.25 → 0.4` and `ambient_color #95968d → #a3a6b2`
  (cool-neutral), so shaded faces land at V0.45 (the foliage teal risk is gone now that
  `leaf.gdshader` has `ambient_light_disabled`). If coast_b must stay ≥ 0.55, stop at −140.
  **(ROCKS)** `shade_fill 0.08 → 0.30`, `shade_fill_color (0.62,0.60,0.74) → (0.56,0.60,0.74)`
  (`#8f99bd`), and let `sky_fill` reach side faces at 30 % (`up_w → mix(0.3, 1.0, up_w)`), so a
  face out of the sun is `#535d73`-class, never navy.
- **Verify:** `cliff_coast` arch face 700,330 in the H205–225 S0.20–0.32 V0.42–0.58 box; arch
  interior 790,470 V ≥ 0.42; rock band region p50 0.33–0.40; ref-bin share (H210–240 S0.17–0.33
  V0.33–0.67) ≥ 8 % of the frame (today 1.8 %); `cliff_coast_b` lit face 1230,700 ≥ V0.55.

### 3. Shade rock is navy and too dark everywhere (villa background, stacks, ledge tops) — **ROCKS + LOOK**
- **Reference:** shade rock `#535d73` V0.45 S0.27; villa background cliffs `#d2cbc8` V0.82 S0.05
  (pale, sky-lit, hazed); ledge tops the palest rock.
- **Ours:** villa background outcrops `#455061` / `#424f65` (H217 S0.29–0.35 **V0.38–0.40**) —
  navy stepped blocks under a pale sky; `cliff_coast_b` stack `#2f3c52` S0.43 V0.32, boulder
  `#3b3e4a` V0.29, steep terrain `#3a414f` V0.31; `cliff_coast` ledge top 560,500 `#af978a` V0.69
  but `cliff_coast_b` ledge top 1048,588 `#8e7268` **V0.56 under a face of V0.57** (ratio 1.0; ref
  1.5–2.2). `sky_fill 0.55` is not enough at `exposure 0.57` (it was tuned at 0.68).
- **Fix (ROCKS):** `sky_fill 0.55 → 0.75` (the uniform's range is 0–0.8), `sky_fill_color #9cb2d8 →
  #a9b6cf` (less blue: tops must be cream-grey, not blue), `ao_min 0.28 → 0.24` so contacts still
  hold the darks. **(LOOK)** the shade colour: `lift_black #0a0c12` is fine, but `fog_color #7190b2`
  on 200–400 m rock adds S0.3 blue — `fog_color → #7d94b0` (S0.29) for the villa background;
  villa outcrops are 250–400 m away and should fog toward `#8d94a6`, not sit under it.
- **Verify:** villa 1200,80 / 1000,120 ≥ V0.55 and S ≤ 0.20; `cliff_coast_b` ledge top ≥ 1.2× the
  face under it; `cliff_coast_b` stack shade 430,620 ≥ V0.40.

### 4. Stratification reads as scribbled cracks and a dotted staircase, not soft beds — **ROCKS**
- **Reference (arch block, 1050–1750 × 150–750):** 3–8 m fracture planes with ±0.05 value steps,
  2–3 soft horizontal beds per 20 m (≤ 4 % darker, 1–2 m tall, no hard line), vertical cracks as
  2–5 m long soft shadows. Region lumstd 0.11 on a face of V0.5.
- **Ours (`cliff_coast` 580–980 × 250–620 at 2×):** the arch face carries (a) two diagonal dotted
  staircases (the `top_steps` riser/tread rows drawn on the *front* face: 8–10 equal 6-px steps at
  620–760 × 290–360 and 820–880 × 300–360), (b) 3–4 px dark vertical joint lines through all courses
  at ~50 px spacing, (c) a 0.3 m bed line that vanishes at 150 m, (d) no bed *bands*. The texture
  cells over the arch are +63/+51/+67 ×10⁻³ above the ref. `cliff_arch` shows the same staircases
  on the hero column at 100–200 × 350–520.
- **Fix (`rock_gen.gd`):** the step cut must not draw its riser on the front face — collapse the
  side rows *behind* the tread (push the cut vertices −0.3 m along the face normal) or restrict
  `top_steps` to the top 15 % of the piece; joint groove width 1.6 cells → 1.0 cell and depth
  0.5 → 0.25 m for anything beyond 60 m (`far` LOD). Beds: replace the 0.3 m cavity-line-only
  bake with a *band*: `COLOR.g` = 1 − 0.04 over a 1.0–1.5 m soft course every 4–7 m (ramp 0.4 m),
  plus the existing line at `bed_line_strength 0.5 → 0.35`. `bed_darken 0.05` stays.
- **Verify:** no run of ≥ 4 equal diagonal steps on the arch crop; arch-face region (620–900 ×
  280–420) lumstd ≤ 0.09 with ≥ 2 horizontal bands visible at 2×; the arch texture cells within
  +30 ×10⁻³ of the ref.

### 5. The foreground hero wall and surf are over-busy; canopies went smooth — **ROCKS + GROUND (texture energy)**
- **Reference:** foreground cliff 0–440 × 250–900 region lumstd **0.152**, p10 0.19; big planes,
  2–4 m blocks with deep shadow between; canopies leafy with 1–3 px holes at the silhouette.
- **Ours:** hero region (0–250 × 350–900) lumstd **0.224** (r2 0.101): 0.5–1 m facets, pitting
  from the 0.8 m normal octave, crack scrub at every joint, a 3-px dark outline on every facet —
  fine noise, not big shadow. Texture cells bottom-left +41…+65. Meanwhile the big tree at
  0–500 × 0–500 lost its edge energy (cells −74/−70): a filled silhouette with a 1-px hard rim.
- **Fix (ROCKS):** `fine_normal 0.4 → 0.15`, fade it `30–70 m → 12–30 m`; hero `facet_amp
  1.2–1.8 → 0.8–1.2 m at 8–12 m` (fewer, larger planes); crack scrub `~0.08/m → 0.03/m`;
  crease AO 0.8 → 0.65 on hero pieces. **(GROUND, `leaf.gdshader`)** the mip bias `ALPHA = a *
  (1 + mip * 0.45) → 0.2`, `alpha_cut 0.3 → 0.38`, and bake 2–4 px gaps between leaf lobes on the
  tree cards (`foliage.py` clump alpha erode 1 px) so the silhouette breaks up again.
- **Verify:** hero region lumstd 0.13–0.17 with p10 ≤ 0.20; top-left cells within −45 ×10⁻³ of the
  ref (r2 level); `cliff_coast` texture-energy term ≥ 0.60 (look-only reached 0.627).

### 6. Water: the dark-green skirt overshot; open water a touch dark; no turquoise band — **LOOK (`sea.gdshader`)**
- **Reference (1400–2000 × 850–1250 shallows):** teal H170–205 is 8.8 % at **S0.37–0.43 V0.35–0.37**
  (`#3b5d5e`, `#324c58`) — the *same value* as open water, greener and less saturated; open water
  `#28395a` H220 S0.55 V0.35 (whole water region p10/p50/p90 0.18/0.26/0.47 — the p90 is sky
  reflection and whitecaps, std 0.125).
- **Ours (`cliff_coast` surf zone 450–1000 × 600–900):** H170–205 is 25 % at `#1d383a`/`#1a323c`
  **V0.23–0.24** S0.50–0.57 — a black-green moat around every rock foot (hist bin H150–180
  S0.33–0.50 V0.17–0.33: 3.6 % vs ref 0.0 %); open water `#243955` V0.31–0.33 (hist bin H210–240
  S0.50–0.67 V0.17–0.33 **+7 %** over the ref: too dark by ~0.04). Foam 1.9 % (ref 0.9 %) as
  uniform white collars.
- **Fix:** `col_teal (0.06,0.13,0.025) → (0.05,0.12,0.11)` and `col_turquoise → (0.06,0.14,0.13)`
  (blue back in: target rendered `#3a595a`–`#334e59`), `teal_amount 0.9 → 0.6`, `teal_metres 15 →
  8`, `alpha_shallow 0.75 → 0.6`; `SEA_NAVY × 1.15 → × 1.3` (open water to V0.35); `foam_opacity
  0.9 → 0.7` and the ring to lace: `foam_depth 0.9 → 0.6` with the clump `smoothstep(0.5, 0.85,…)
  → (0.55, 0.9,…)`. Keep the swell bands.
- **Verify:** surf-zone H170–205 share 5–10 % with median V 0.32–0.38; open water 1200,700
  `#2a3d5e` ± 0.03; foam 0.8–1.4 %; no pixel run > 12 px of V < 0.2 adjacent to a rock foot.

### 7. Crest trees are bright lime blobs; the cliff top has no straw ground — **GROUND**
- **Reference:** treeline top region (0–700 × 0–150) `#323a44` p50 **0.22**; arch-top trees
  `#4a5667` (hazed, H215); cliff-top ground between scrub `#685a40`–`#b4986d` straw (H36–38
  S0.38, V0.41–0.71), scrub `#6a5743`; the ground is visible between every bush.
- **Ours:** treeline region (500–950 × 130–270) `#527053` p50 **0.39**, p90 0.71; crest trees
  `#3a5943`–`#6e8c49` (H97–137 V0.35–0.55), the cliff top is a solid canopy with no ground; villa
  trees `#6c7e25` **S0.71** (ref `#707f37` S0.57); cypress `#344537` H130 V0.27 (ref `#2a2a0f`
  H60 V0.16 — near black-olive).
- **Fix (`TREE_LOOK`, `leaf.gdshader`, scatter):** umbrella / pine `col_lit` × 0.75 and the "far"
  tint (item 6 of round 3, still not done): beyond 120 m multiply the canopy by `(0.70, 0.78,
  0.85)` in the leaf shader (fog factor already computed there); cypress `#2e3a22 / #55663a`;
  villa broadleaf `col_lit #86a444 → #7c9540`; crest tree density in the sea-cliff region
  (`_gen_sea_cliffs` crest scatter / `crest_cells`) ×0.5 with 1.5–3 m straw gaps
  (`Terrain` colour map `#b09a6c` on the crest 6 m band, `Grass`/`Dry` texture, not the rock lip).
- **Verify:** treeline region p50 ≤ 0.30; villa tree lit S 0.45–0.60; cypress V ≤ 0.22 H 55–90;
  ≥ 25 % of the cliff-top band (500–950 × 230–270) at H 30–50 (ground).

### 8. Villa: vineyard rows still navy-shaded, ground has maroon blotches — **GROUND (+ LOOK shadow colour)**
- **Reference (0–450 × 250–560):** mean `#574d2a` H46 **S0.51**; hue mass H25–70 **70 %**,
  H170–260 2 %; humus / shadow `#201f13` H55 V0.13 (warm black), road shade `#7c6043` (same hue
  as the lit road `#c19b64`, 0.63×).
- **Ours:** vineyard region `#4b594b` H120 S0.29, hue mass H170–260 **30 %** (r2 27 %), H25–70
  9 %; ground region (600–1300 × 600–900) has 13 % at H170–260 S0.57 V0.16 (navy shadow) and
  23 % at H0–25 (`#43292a` H357 S0.38 V0.26 — the new warm halo `#6b5947` under the blue shadow
  and the canopy darkening lands *maroon*). The disc `#b0927e` V0.69 is still the brightest ground.
- **Fix (GROUND):** halo colour `#6b5947 → #5a5238` (olive-brown, H45) and cap the halo+canopy
  darkening at 0.3; vine shade: the card's shade side uses `shade_warm` — set the vine material's
  `shade_warm` floor to `#4a4a24` and instance tint `(0.95,1.0,0.78) → (1.0,0.92,0.62)` (the
  ref's rows are yellow-olive H45–70, S0.58, not mid-green); soil strip `(0.82,0.68,0.44)` is
  right — make it 60 % of the row pitch (today ~35 %). Disc → `Gravel` stamp at `#8f7a5c`
  (V0.55). **(LOOK)** shadow colour: `ambient_color #95968d → #a3a6b2` is item 2; add
  `lift_black #0a0c12 → #0e0d0c` (neutral, not blue) so cast shadows on warm ground stay warm.
- **Verify:** vineyard region S ≥ 0.40, H170–260 ≤ 8 %; ground region H170–260 ≤ 5 %; no 6 m run of
  H340–20 on flat ground; disc patch 780,500 V ≤ 0.58.

### 9. Villa hub: pole, no walls / fences / shed (fourth round) — **GROUND with the hub builder (`island.gd _build_villa_hub`)**
- **Reference:** dry-stone walls `#726a29` lit / `#201f13` shade along every lane, fence lines,
  a shed, pergola, van; frame std **0.205**, p1 0.08.
- **Ours:** std 0.159 (r2 0.131), p1 0.095; the 60 m beacon (`delivery_system.gd`, alpha 0.16)
  through the frame centre; no wall, fence or shed; lane `#917e6e` V0.57 (ref road V0.76, the
  brightest ground).
- **Fix:** hide the beacon in the view harness (`tests/view.gd`: `DeliverySystem.beacon.visible =
  false` while capturing, or beacon alpha 0.16 → 0.06); `_wall` segments 1 m × 60 m each side of
  the lane (`#b3a38a` limestone material, talus sibling), a 6×4 m shed and a pergola from the
  existing house kit, 2 cypresses at the gate; lane colour-map `(1.0,0.95,0.85)` → `#c9a878`
  crown. Budget: ≤ 0.2 s.
- **Verify:** ≥ 40 m of wall visible in `villa`; frame std ≥ 0.18; no vertical line through the
  frame; lane patch 700,640 V ≥ 0.62.

### 10. Boulder tops darker than their flanks; surf boulders read as muffins again — **ROCKS**
- **Reference:** boulder top `#8c715a` V0.55 / camera side `#51464c` **V0.32** / lit side
  `#75615b` V0.46 (top brightest, the side toward the camera dark).
- **Ours (`cliff_coast`):** boulder top 760,640 `#a18173` **V0.63 under a flank of V0.71**
  (`#b49889`); surf boulder `#c59d80` V0.77 all round; `cliff_arch` boulder top `#c5997a` V0.77
  vs side `#b18f81` V0.69 (OK there). With the sun square on the flank (item 2) the flank wins;
  with the sun ahead (exp2) the flank drops to `#756d6e` V0.46 and the top stays — item 2's sun
  placement fixes half of this. The rest: apron boulders are still `_add_rock` "rounded" pieces
  with `top_amp` 0 (smooth domes, 1 in 3 with the sibling texture) — the ref's surf boulders are
  split blocks with one flat top.
- **Fix:** `_boulder_apron` pieces: 50 % `block` library piece (facets, `bevel_top 0.3`) instead of
  the rounded boulder; rounded ones get `top_amp 0.15` and one flat facet on top; `sky_fill` item 3.
- **Verify:** top ≥ 1.15× flank on the three boulders at 760,640 / 680,860 / 620,690 (`cliff_arch`);
  ≤ 30 % of the apron pieces with a circular silhouette at 4× zoom.

### 11. Clouds: the reference's cloud bank is *lighter* and pinker than the sky; ours are dark smears — **LOOK (`sky.gdshader`)**
- **Reference:** the sky median matches now (`#a1a6bc` H228 S0.14 V0.74 vs ours `#a6aabf` H226
  S0.13 V0.75 — item closed), but the cloud bank top-left is `#b1a7ba` / `#b5aec1` (V0.76–0.78,
  H265–290) over a zenith of `#9ba5bf` V0.75: **lighter and pinker** by ΔV +0.02 and ΔH +40°, with
  lobes 150–300 px across; the pale-blue high sky H190–210 S0.17–0.33 is 2.7 % of the ref frame
  (ours 0.0 %). Top-row texture cells −74/−70 (part of it is the tree, part the clouds).
- **Ours:** `cloud_mul_edge (1.04,0.96,0.935)`, `cloud_mul_core (1.0,0.885,0.86)` *darken*;
  the smears at 300–1100 × 20–120 are `#a9aec2`-on-`#aaafc4` (invisible), the two pink patches
  at 1000–1200 × 120–180 are 1–2 % darker than the sky.
- **Fix:** `cloud_mul_edge → (1.07, 1.01, 1.00)`, `cloud_mul_core → (1.03, 0.96, 0.97)`,
  `cloud_base (0.67,0.655,0.745) → (0.74, 0.70, 0.76)` with `cloud_flat 0.7 → 0.5` and
  `cloud_cover 0.5 → 0.6`; `sky_top #a6b0c8 → #9fb0c9` (H210, S0.21) so the zenith carries the
  ref's pale blue while the wide glow lobe keeps the pink low.
- **Verify:** a cloud patch at 400,60 lighter than the sky at 400,150 by 0.01–0.04 V and H ≥ 250;
  H190–210 S0.17–0.33 ≥ 1.5 % of the frame; sky region S still ≤ 0.17.

### 12. Aerial perspective on the 150–400 m rock is blue haze on tan, not pale grey dissolving — **LOOK + ROCKS**
- **Reference:** far stack `#6f87a4` (H212 S0.32 V0.64), far headland `#5d6e86`, both *darker* than
  the sky beside them (V0.69–0.75) and desaturated toward the sky hue; the near-to-far ramp on the
  wall runs `#988374` (S0.24) → `#627288` (S0.28) — the hue crosses from warm to cool at ~200 m.
- **Ours:** the far islet is right now (`#89838b` V0.55 < sky 0.69, S0.06); but the 150–250 m arch
  and stacks are still tan (`#ba9177` S0.36 at 200 m; `cliff_coast_b` face 1400,650 `#a98f7d`
  S0.26 at 180 m): the fog (32 % at 150 m) cannot desaturate an S0.4 albedo to the ref's S0.25.
  Item 1 fixes the albedo; what remains is the hue crossover.
- **Fix (LOOK):** `fog_density 0.0026 → 0.0030` (37 % at 150 m, 70 % at 400 m — the ref's ratio),
  `fog_color #7190b2 → #7d94b0`; `fog_height 9 → 12`, `fog_height_density 0.022 → 0.028` (sea-level
  haze under the stacks). **(ROCKS)** nothing beyond item 1.
- **Verify:** `cliff_coast` 1100,450 (stack at 250 m) H ≥ 200 S ≤ 0.25; 1400,320 (far stack) ≤ V0.65;
  the near wall (120,650) unchanged within 0.03 V.

### 13. Bench and road through the arch: tan plaster, no ruts, no margin — **GROUND (+ ROCKS scree)**
- **Reference:** road crown `#c4ad8f` V0.77 S0.27, margin `#978178`, two 0.5 m ruts, the road is the
  brightest ground; the bench carries 1–2 m scrub tufts and a car for scale.
- **Ours:** bench 800,560 `#ba9274` H25 **S0.38** V0.73 (the pale crown under the warm sun and the
  rock's `sand_color`); 6 lime discs in the opening (`#5a7a3a`-class, brighter than the canopy);
  no rut, no margin, `cliff_coast` 700–1150 × 480–600 region lumstd 0.09 (ref 0.16).
- **Fix (GROUND):** bench colour-map tint `(0.90,0.80,0.64) → #c4ad8f` with two `#9a8468` rut stripes
  at ±0.9 m (0.5 m wide) and a `#8f7658` margin 1 m each side; tufts: 8/100 m² of 0.8–1.5 m scrub
  with tint × 0.7 in the opening (`road_clear + 8` stays). **(ROCKS)** the 3–4 bench boulders exist —
  give them the talus sibling (`ao_min 0.20`) so they sit in a contact shadow.
- **Verify:** bench patch H 25–35 S 0.22–0.30 V 0.60–0.72; ≥ 2 rut lines visible at 2× in the opening;
  no bush in the opening brighter than V0.45.

### 14. Foam collars are uniform white paint; the reference is lace + streaks — **LOOK (`sea.gdshader`)**
- **Reference:** foam 0.9 % of the water: 1–3 px lace lines along the rock feet with 5–15 m streaks
  trailing along the swell, `#79655d`–`#e0d8d0` (it is often *grey*, V0.47–0.85), never a filled disc.
- **Ours:** 1.9 %: 20–40 px solid white collars (`#e7d8d2`-class V ≥ 0.85) around every apron
  boulder and along the arch foot (`cliff_coast` 440–560 × 700–900; `cliff_arch` 560–660 × 640–700).
- **Fix:** `foam_color (0.97,0.96,0.92) → (0.86,0.84,0.80)` with `foam_emission 1.0 → 0.6` (foam
  takes the shade of the rock it hugs), ring width `foam_depth 0.9 → 0.6`, `foam_clump_metres 3.5 →
  2.0` at a 0.65 threshold (50 % of the collar open), streaks at `prox > 0.25` × 1.0 (they were
  halved) so the trails carry the foam instead of the collar.
- **Verify:** foam share 0.8–1.4 %; no foam blob wider than 12 px at 1600×900; foam median V ≤ 0.80.

### 15. Villa: the sea and sky behind the villa are one flat lavender slab — **LOOK**
- **Reference:** the villa ref has no sea; but the coast ref's far sea under the horizon is
  `#7992ae`–`#6a7b91` (V0.60–0.68, S0.30) — visibly darker than the sky above it.
- **Ours (`villa` 0–500 × 80–200):** sea `#b0abb6` **V0.71 S0.06** — the fogged sea at 600 m has
  converged on the *sky* colour and reads as a wall of mist; the horizon is a hard edge at y ≈ 80.
- **Fix:** `sea.gdshader` `horizon_fade_start 250 → 400`, `horizon_fade_end 1400 → 2000`, and the
  rebuilt horizon colour × `horizon_gain 1.0 → 0.92` so the far sea sits 0.05 V under the sky; the
  `fog_sky_affect 0.15` stays.
- **Verify:** villa 200,120 (sea) V 0.60–0.66 and ≥ 0.04 below the sky at 200,40; no one-row step
  > 0.02 at the horizon.

---

## Regressions vs round 2 (`/root/rounds/r2`)

- **Rock hue:** lit rock S 0.18 → **0.34** (item 1); r2's stack "shade" sides `#696467` V0.41 are now
  `#c2926c` V0.76 — the shade side is the brightest tan in the frame (item 2).
- **Villa ground:** new maroon blotches `#43292a` (H357) where r2 had `#232338` navy — the warm halo
  under a blue shadow (item 8); vineyard navy share 27 % → 30 %.
- **Villa trees:** S 0.29 → **0.71** (overshoot; target 0.57), cypress teal (item 7).
- **Canopy silhouettes:** top-left texture cells −39/−59 → −74/−70 (item 5).
- **Water:** the near-rock cyan glow (r2 `#30586e` V0.43) is now a black-green moat (`#1d383a`
  V0.23) — over-corrected (item 6).
- **Improved, keep:** whole-frame p1 0.171 → 0.123, p50 0.402 → 0.414 (ref 0.10/0.35 — still
  0.06 high in the rock band); `cliff_coast_b` p50 0.57 → 0.47; sky S 0.23 → 0.13 and the horizon
  step 0.05 → 0.01; islets `#f2e6d7` → `#89838b` under the sky; ledge tops on `cliff_coast` pale;
  the arch bench lit; canopies green (H 97–137) not teal; generation 17.7 → **10.0 s**.

## Per-lane summary

- **ROCKS:** 1 (palette under the merged sun — do this first, then re-measure), 2-shade fill,
  3 (sky_fill, tops), 4 (staircase / joints / bed bands), 5 (hero busy-ness, fine octave), 10
  (boulder tops / block aprons), 13-talus. Acceptance: lit S 0.14–0.25; shade faces H205–225
  V ≥ 0.42; ledge top ≥ 1.2× face; arch-face lumstd ≤ 0.09; hero lumstd 0.13–0.17.
- **LOOK:** 2 (sun ahead of the camera *with* the ambient lift — measure `cliff_coast_b` before
  committing), 3-fog colour, 6 (sea skirt / navy), 8-`lift_black`, 11 (clouds lighter), 12 (fog
  density / height), 14 (foam), 15 (villa horizon). Acceptance: ref-bin share ≥ 8 %; frame p50
  0.34–0.38 with p1 ≤ 0.12; surf-zone teal V 0.32–0.38; foam ≤ 1.4 %; cloud lighter than sky.
- **GROUND:** 5 (leaf alpha / lobes), 7 (crest tree value, far tint, straw cliff top), 8 (halo
  colour, vine shade / tint), 9 (hub dressing: beacon, walls, shed, lane colour), 13 (bench paint).
  Acceptance: treeline p50 ≤ 0.30; vineyard S ≥ 0.40 with ≤ 8 % navy; villa std ≥ 0.18; ≥ 40 m of
  wall; bench S 0.22–0.30.
- **Tests / time:** architecture, feature, edge must stay green; `[game] world generated` ≤ 12 s
  headless on each branch (10.0 s today; ≤ 2 s per lane); the long autotest at the merge only.
- **Spots:** keep the four judged spots + `islet_far`; add `villa_gate` (from `[-330,12,40]` at
  `[-326,6,3]`) so the wall / shed work is judged at 20 m.
