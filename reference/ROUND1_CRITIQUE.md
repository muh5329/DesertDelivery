# Round 1 critique — r0 renders vs `ref_cliff_coast.png` / `ref_villa_vineyard.png`

Renders judged: `/root/rounds/r0/cliff_coast.png` (0.52), `cliff_coast_b.png` (0.47), `cliff_arch.png`
(0.51), `villa.png`. Colours below are 36×36 px patch medians (PIL) unless marked "mean". The
reference is 2554×1428; ours 1600×900. Lanes: **LOOK** (`world_kit.gd` env/sky/fog/grade + `sea.gdshader`),
**ROCKS** (`rock_gen.gd`, `rock.gdshader`, `_cliff_wall/_sea_arch/_sea_stack/_boulder_apron`,
`island.gd _gen_sea_cliffs`), **GROUND** (`terrain.gd` control/colour maps, foliage, scatters).

## Whole-frame numbers first (these frame everything below)

| | ref cliff | cliff_coast | cliff_coast_b | cliff_arch | ref villa | villa |
|---|---|---|---|---|---|---|
| mean RGB | `#616267` | `#7a7f85` | `#828d9d` | `#768090` | `#666351` | `#767a7d` |
| mean HSV saturation | **0.29** | 0.19 | 0.20 | 0.20 | **0.35** | 0.19 |
| luminance p1 (darkest 1 %) | **0.11** | 0.20 | **0.33** | **0.33** | 0.08 | 0.25 |
| luminance p50 | 0.35 | 0.55 | 0.57 | 0.49 | 0.36 | 0.48 |
| luminance p99 | 0.71 | 0.74 | 0.76 | 0.73 | 0.80 | 0.71 |
| luminance std (contrast) | **0.17** | 0.16 | **0.11** | **0.12** | 0.21 | 0.11 |
| bottom 30 % rows mean | `#4a4747`-`#574b49` | `#767575`-`#8f8986` | `#5b6879`-`#7e828c` | `#475a71`-`#637387` | `#544a34`-`#6d5f42` | `#6d6a63`-`#76746e` |

Read that as: **our frames have no darks at all** (the darkest 1 % of `cliff_coast_b` is brighter than
the reference's *median*), they are ~1.6 stops too bright in the bottom half, and they are *less*
saturated than the reference, not more — the round-0 desaturation + fog overshot. The reference is
a dark, contrasty, warm image with a pale sky; ours is a pale, flat, blue-grey image with a pale sky.
Every lane inherits this, but the master control is LOOK.

---

## Ranked list (biggest difference first)

### 1. Rock has no lit/shadow separation and is neutral grey — **ROCKS + LOOK**
- **Reference:** sunlit limestone `#ae9985` (H29 S24 V68), same wall in shadow `#5a5d6d` (H231 S17
  V43): a 1.6:1 value ratio *and* a hue swing from warm to blue. Fresh-fracture undersides are
  orange `#c99a5e`. Every block has a lit face, a half-lit face and a shadow face.
- **Ours:** `cliff_coast_b` wall lit face `#96969b` (S3 V61), "shadow" face `#a39b9e` (S5 V64) — the
  shadow side is *brighter* than the lit side. `cliff_arch` lit top `#75757d`, face `#93949a`,
  dark band `#808189`: all S 3–7. `cliff_coast` rock `#848486` / `#858283`. The rock is a
  monochrome grey with 5 % contrast; the only modelling comes from the baked bed bands.
- **Fix:** (LOOK) sun currently `sun_yaw_deg -48` is broadside to every west-facing wall in
  `cliff_coast_b`/`cliff_arch`, so all faces get the same irradiance; swing the yaw so the light
  rakes *along* the west wall at ~30–40° off its face (for the new camera below: sun from the
  SW-W, i.e. behind-right of camera), keep elevation 22–26°. `ambient_energy 0.7 → 0.45`,
  `ambient_sky_contribution 0.7 → 0.5` so shadow faces fall to ~65 % of lit. (ROCKS)
  `rock.gdshader`: `tex_saturation 0.5 → 0.8`, `base_tint #c9bfae → #c2ab90` (it has to survive
  saturation 0.85 + blue fog and still read warm), `macro_value 0.13 → 0.18`, `macro_rust` toward
  `#c49a6a`; add the orange fresh-fracture tint to faces with `normal.y < -0.2` (undersides) at
  ~40 %. Also check `_soft_bed_material` is not lighter than the base (the soft courses in
  `cliff_coast_b` read *lighter*, `#a1a0a2`, when they should be darker/greyer `#9a9089`).

### 2. Fog + exposure flatten everything past 100 m and lift all blacks — **LOOK**
- **Reference:** stack at ~400 m `#5f6f86` (V53); islet at ~800 m `#69839e` (V62); wall at 150 m
  still shows `#4d576c` shadows (V42). Fog is ~30 % at 150 m, ~70 % at 400 m, and the fog *colour*
  is darker than the sky (`#6c86a2`-ish); darkest things in frame (scrub, boulder contacts) are V 10–19.
- **Ours:** `cliff_coast_b` stack at ~200 m `#74798d` (V55, already lighter than the reference's
  400 m stack); `cliff_arch` boulders at 150 m `#85858c` (V55); nothing below V 32 anywhere;
  `fog_color #6688b4 × fog_energy 1.18` ≈ `#78a0d4` — brighter and bluer than the horizon sky
  it is supposed to match. `fog_height 6 / fog_height_density 0.035` puts a second haze layer over
  exactly the rocks/water/boulders that should be the darkest plane.
- **Fix:** `fog_density 0.0034 → 0.0022`, `fog_energy 1.18 → 0.95`, `fog_color → #6b84a0`,
  `fog_height_density 0.035 → 0.012`, `fog_height → 2.0`. `exposure 0.82 → 0.72`, `contrast 1.0 →
  1.12`, `saturation 0.85 → 1.0` (the *reference* is S 0.29 mean; we are at 0.19 — stop desaturating
  and let fog do it with distance), `lift_black #15171d → #0e1016`. Target: p1 luminance ≤ 0.14,
  std ≥ 0.16, mean S ≈ 0.27 on `cliff_coast_b`.

### 3. The wall is a stack of pillows/bricks, not a fractured monolith — **ROCKS**
- **Reference (see crop of the arch block):** one 50 m mass. The dominant lines are *vertical*
  fracture faces 15–30 m tall and 8–20 m wide, planar, crisp 90° corners with ≤ 0.5 m rounding;
  bedding is a secondary cue — subtle 3–8 m ledges, uneven, some beds pinching out. The skyline is
  stepped, with pines/scrub on every step.
- **Ours:** `_cliff_wall` builds every course (4–7 m) as its *own* row of separately bevelled
  rounded boxes (bevel 0.5–1.6 m on every edge, plus `noise_amp`) with a recessed, differently
  coloured soft course between: ten identical loaves per column, no face taller than one course,
  every block edge rounded like a cushion, tops perfectly flat. `cliff_arch` reads as a quarry
  bench / stacked luggage; `cliff_coast_b` as a brick wall. The vertical joints exist in the data
  (`joint_spacing` 6–14 m) but are invisible because each course's block has its own rounded
  silhouette, so the horizontal seams win.
- **Fix:** invert the hierarchy. In `_cliff_wall`, make the primary piece a **pillar spanning 2–4
  courses** (12–25 m tall, 6–14 m wide, one bay), with beds expressed *inside* the pillar by
  `rock_gen` (`bed_inset` 0.15–0.35 m, `bed_darken` 0.15, bed_height varying 3–8 m per pillar, tilt
  0.03–0.08), `bevel 0.15–0.25` on vertical edges, larger (0.8–1.5) only on the top face.
  Neighbouring pillars offset in depth ±0.5–2 m so the joints read as shadow lines; one pillar in
  six pushed forward 3–5 m as a buttress, one in eight a chimney 2–4 m back. Keep the soft-course
  recess only as a 1–2 m *band* every 2–3 courses (undercut), not every other course. Drop the
  separate `_soft_bed_material` in favour of the shader's band function. Top course: keep the
  crenellation but add `top_amp` 1.5–2.5 so skylines are jagged, and spawn scrub/pines on top.

### 4. `cliff_coast` camera is blocked by the headland — **spots.json**
- The current `from [-462,44,-130] → at [-520,8,-300]` sits on the south limestone block (ground
  22–31 m at X -460, Z -130) and looks NW straight into its own 40–49 m summit (Z -290..-150), so
  the frame is a chalk mound with a house on it; no sea, no wall, no arch. Compare score 0.52 is
  pure luck of tone.
- **Which spot matches the reference best today:** `cliff_coast_b` (wall on one side, sea, stacks,
  far coast) — but it is mirrored (land right, sea left) and has nothing in the foreground.
- **Proposed `cliff_coast`:**
  ```
  "cliff_coast": {"from": [-592, 38, -322], "at": [-522, 5, -200], "ground_relative": false}
  ```
  Rationale (heightmap `data/island_map.png`, `_gen_sea_cliffs` coordinates): camera hangs over
  the inlet mouth (sea, ground -3) just seaward of the 46 m north wall (line Z -310..-317, west end
  at -568,-310 — it lands at the extreme left edge of a ~70° horizontal FOV, exactly like the
  reference's foreground cliff on the left). Facing SE (+Z), land is on the **left**, sea on the
  **right** as in the reference. The arch (-531,-305 → -517,-283) sits 60 m ahead, lower-left of
  centre; the west wall (Z -272..-152) runs away diagonally from lower-left to upper-centre; the
  stacks at (-571,-268) and (-577,-192) sit in the water on the right third; the far coast at
  Z -140..-100 closes the frame in haze. Pitch ≈ 14.5°, horizon at ~40 % from top. It is
  unverified — render it once and nudge; if the north-wall end intrudes more than ~15 % of the
  width, move `from` to `[-598, 38, -326]`. The foreground will be water/stacks rather than the
  reference's boulder beach until item 5 exists.

### 5. No bench, no coast road, no arch-over-road — **ROCKS (island.gd) + GROUND**
- **Reference:** a 10–20 m dirt bench 3–6 m above the sea between wall and boulder apron, with the
  road on it and tunnelling *through* the arch; cars for scale under the arch. That bench is the
  entire middle wedge of the composition.
- **Ours:** `_gen_sea_cliffs` says it — "the mountain loop road runs 60–100 m inland and is never
  touched". The terrain goes from -2 to 25–45 m within 10–20 m of the water everywhere along
  Z -290..-150; there is no place to stand. `_sea_arch` stands in open water with nothing under it.
- **Fix:** in `terrain.gd`/`island.gd`, carve a 14 m wide bench at y ≈ 4 along the west wall's
  foot (X ≈ -556..-542, Z -280..-150) and along the south side of the inlet, then `add_road` a
  spur along it that passes under the arch (move the arch onto the bench line: e.g. pillars at
  (-547,-286) and (-534,-274) so the opening spans the road). Boulder apron seaward of the bench
  (item 10). This is the single change that would make the target composition *possible*.

### 6. No vegetation lines on ledges / crests — **ROCKS (emit) + GROUND (assets)**
- **Reference:** every bedding ledge > 1 m carries a line of dark scrub `#222b1f`–`#2c3728`; every
  block top has 2–4 m bushes and 8–12 m umbrella pines; the greens are the darkest things in the
  frame (V 10–22) and they *trace the strata*.
- **Ours:** `cliff_coast_b` has a scatter of pale-green discs on the plateau and none on the wall;
  `cliff_arch` has ~6 bushes on 200 m of cliff. `_cliff_wall` only emits a bush when
  `front - below > 1.0` with p 0.7, and the loaves rarely leave a ledge because courses jut ≤ 2 m.
- **Fix:** guarantee ledges: every 2–3 courses force a 1.5–3 m setback and emit bushes at 0.4/m
  along it (scale 1–2.5 m), colour `#2e3a2c` base with the instance tint; top course: 0.15/m²
  bushes + one pine per 40 m² of top area, 1–3 m back from the edge. Bush cards need a dark
  interior (baked top-lit gradient 1.0 → 0.55) — today they are flat `#52637a`-ish discs.

### 7. Water: no turquoise band, no foam, no glints, far too bright — **LOOK (sea.gdshader)**
- **Reference:** deep `#2a3959` (V35), 20–60 m band `#425973`, shallows over sand `#577179`
  (H194, teal), foam bright cream `#e6e2d7` in 1–3 m rings and streaks around every rock, whitecaps
  in open water, small glints breaking the reflection.
- **Ours:** `cliff_arch` open water `#485972` (V45) → `#596d87` mid-distance (V53) — a flat
  gradient toward the sky; no teal hue anywhere (H 213–216 everywhere); the "foam" at rock feet
  samples `#778f9b`, a thin uniform 1-px grey-blue halo ("bathtub ring"), never white, never
  streaked; no visible wave normal breakup or sun glint in any of the three shots.
- **Fix:** (a) `col_navy` darker (`#20304d` lit), `band_navy 3.8 → 9`, `band_mid 1.6 → 4` so the
  teal band is 10–25 m wide on the 1:6 sea floor; (b) foam: `foam_depth 0.9 → 1.6`, multiply by a
  second, 1.5 m noise so it breaks into clumps, add the trailing-streak term along `wave_a_dir`,
  and drive brightness so it *clips* to `foam_color` (it is currently being multiplied by the
  water colour); add whitecaps `step(0.93, noise)` at ~1/200 m²; (c) `wave_strength 0.35 → 0.6`,
  `sparkle 0.4 → 0.9`, roughness 0.16 → 0.10 so the sun makes glints; (d) **bug**: `_build_sea`
  sets `world_size 1000` but `expand.py` writes `sea_depth.png` for `SEA_SIZE = 1733` — the
  fallback depth map (used beyond 350 m) is scaled 0.58× toward the origin, so far water/foam is
  read from the wrong place. Set the uniform from `island_meta.json.sea_size`.

### 8. Ground is chalk-white, textureless, scrub-less; road invisible — **GROUND**
- **Reference:** bench earth `#ac8a71`–`#847760` (S 26–34), dark scrub thickets every 3–8 m with
  `#5a4a3a` halos, straw grass in patches, road `#c9a77a` crown with dark ruts, pebbles.
- **Ours:** `cliff_coast` headland `#bbaa9b` (S17 V73) — the brightest large area in any frame,
  brighter than the sky's mean — with a sprinkle of straw tufts and *zero* bushes; the smooth
  pinkish putty slope in `cliff_coast_b` (`#9c9290`, right side) is the Terrain3D slope texture
  with no macro variation and no rock detail. Roads: not visible in any of the four renders
  (villa: a faint lighter smear).
- **Fix:** control-map slope/cliff texture darker and warmer (`albedo_color` toward `#a08a72`),
  `enable_macro_variation` on with `#c8b9a2` / `#7f7a76` at 50 m; colour-map darkening under
  every bush/tree (r 1.5 m, `#6a5a48` at 50 %); scrub thickets on the headland at 0.1/m² in
  12 m clusters (currently the `cliff_coast` headland has none); road colour map: two `#8f7658`
  ruts ±0.9 m + `#7a6a55` margin bleed 1.5 m — the road must be *visible* from 150 m.

### 9. The sea arch is a post-and-lintel doorway — **ROCKS**
- **Reference:** the hole is eroded through a 50 m block: the lintel above the opening is ~15 m
  thick and ~as wide as the pillars, the opening is a rounded/irregular ~20×25 m void with an
  orange undercut ceiling, and the block's outer faces are continuous with the pillars.
- **Ours (`cliff_arch` centre):** two 12 m pillars, a thin flat beam (`lintel_h = height × 0.45` on a
  30 m arch = 13 m — but visually a slab because it spans `span + pw` with a straight underside),
  rectangular opening, bevelled beam edges; reads as a dolmen/quarry gantry.
- **Fix:** `_sea_arch`: build the whole thing as ONE `rock_gen` piece with a subtractive hole
  (or: two pillars whose tops flare outward + a lintel `pd × 1.6` deep and `height × 0.55` tall,
  with `bevel` on the *underside* edges 2–3 m so the opening is rounded), `height 30 → 42`,
  pillar width 8–10 m, `top_amp 3`; orange `ao_warm_tint` on downward faces (item 1).

### 10. Boulders: dark neutral clay lumps, floating, no apron — **ROCKS**
- **Reference:** talus of rounded warm boulders `#a38973` lit / `#62514d` shadow, 1–8 m, in a
  continuous 20–40 m apron half-buried in sand, darkest contact shadows `#40373e` where they touch.
- **Ours:** `cliff_arch` boulders `#85858c` (S5) with a *lighter* cap and a dark flank (reads as
  wet clay), each sitting as an isolated blob on a glassy plane with a pale ring; `cliff_coast_b`
  blocks in the water sample `#566a84` — bluer than the sea beside them because the water shader's
  fresnel is stronger than the rock's albedo. No apron continuity, no overlap, nothing buried.
- **Fix:** `_boulder_apron` density 0.05 → 0.12 in the 2–12 m band, allow overlap (no rejection),
  sink 30–45 % (`_boulder_y` on land `g - 0.18 s → g - 0.35 s`), sizes bias to 2–5 m, and use the
  warm rock tint of item 1 with `ao_min 0.45 → 0.35` so the contact ring is dark, not pale.

### 11. Clouds are cauliflower blobs; sky is uniform — **LOOK**
- **Reference:** sky is a smooth pale gradient `#949fb8` zenith → `#7b95b0` horizon with broad,
  soft pink-mauve smears `#b4abbe` (stratus/cirrus) mostly on the right; edges fade over 100s of px.
- **Ours:** `cliff_coast_b` top-left: a single hard-edged noise blob `#b9b8cc` 400 px wide with
  visible fractal lobes; `cliff_arch` a similar blob at top-centre; `cliff_coast` blobs on the
  right. Sky gradient itself is fine (`#93aabf` → `#8197ad`).
- **Fix:** `sky_cover` texture: lower-frequency noise (2 octaves, ~4× the wavelength), stretched
  4:1 horizontally, threshold `cloud_cover 0.35 → 0.5` with a *soft* ramp (smoothstep width
  0.3 not 0.05), `cloud_tint` slightly lower (0.22, 0.12, 0.18). One ridge-shaped band, not blobs.

### 12. Trees: blue-teal, chequerboard trunk, stacked-disc conifers, villa cypress monoculture — **GROUND**
- **Reference:** canopies `#262e30`–`#283330` (H160–190, dark green-teal), umbrella pines with bare
  trunks and flat 10 m crowns, round shade trees along roads; villa: mixed pines, cypresses (few),
  olives, vineyard rows as *rows*, flowering shrubs.
- **Ours:** `cliff_coast` canopy `#283440` (H210 — bluer than the sea); the big tree's trunk is a
  black/white **chequerboard** (broken UV/texture on the trunk mesh — see crop at 930,780); the
  villa scene is 60 % cypress spires + stacked-disc firs (alpine, not Mediterranean), vineyards are
  dotted noise not rows, one white cube house, a 60 m grey pole. Villa frame mean S 0.19 vs ref 0.35.
- **Fix:** fix the trunk material (UV/texture scale); shift foliage hue −20° (toward green) and
  V ×0.9 in `foliage.py`; cap cypress at ~10 % of the villa scatter, replace disc-firs with the
  umbrella-pine tier; vineyard rows as MultiMesh lines on a 2.5 m pitch with a bare-earth strip
  painted in the colour map; give the villa a dry-stone wall + 2–3 outbuildings.

---

## Quick per-lane summary

- **LOOK (does first — everything else is judged through it):** items 2, 7, 11, plus the sun yaw
  half of 1. Targets on `cliff_coast_b`: p1 lum ≤ 0.14, std ≥ 0.16, mean S ≈ 0.27, stacks at
  200 m no lighter than `#68788e`.
- **ROCKS:** items 3, 9, 10, 5 (bench + arch on road), rock-material half of 1, ledge emission of 6.
  Target: on a lit/shadow pair of one pillar, V ratio ≥ 1.5 and hue swing warm → blue; no face
  in `cliff_arch` shorter than 10 m except the top course.
- **GROUND:** items 8, 12, assets half of 6. Target: headland median ≤ `#a08a74`, visible road
  at 150 m, ≥ 1 bush per 10 m² on the bench/headland.
- **Camera:** adopt the `cliff_coast` proposal in item 4 and re-render before the next round; keep
  `cliff_coast_b` and `cliff_arch` as they are for regression.
