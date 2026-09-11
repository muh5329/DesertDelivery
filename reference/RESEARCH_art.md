# Art research — why `ref_cliff_coast.png` looks the way it does, and what `cliff_coast*.png` is missing

Scope: element-by-element comparison of the primary reference (`ref_cliff_coast.png`, with
`ref_villa_vineyard.png` / `ref_courtyard_closeup.png` as secondary evidence) against our current
renders `/tmp/x/cliff_coast.png`, `/tmp/x/cliff_coast_b.png` and the rider's-eye shots
`/tmp/close/view_0..2.png`. Every item ends with an implementation direction that works in Godot 4.7
**GL Compatibility** + Terrain3D 1.0.2 (no SSAO / SDFGI / volumetric fog / SSR), a payoff estimate
and an effort estimate. Colours are approximate sRGB hex sampled from the images (the reference has
a light pink haze over everything, so its "local" colours are estimated by un-hazing mentally).
Sizes are inferred from the reference by using the car (~4 m) and the umbrella pine (~10 m) as
scale bars.

## 0. One-paragraph diagnosis

The reference is a **big, blocky, stratified limestone wall** (30–60 m tall) with **vegetation
tucked into its ledges**, seen through **warm, pink-tinted haze** under a **low sun from screen-left**.
Almost nothing in it is saturated: the whole frame lives in a narrow band of desaturated warm greys,
olive greens and slate blues, and the single high-chroma accent is the turquoise water and its foam.
Our render is the opposite on every axis: small (5–15 m) **convex low-poly blobs** instead of a wall,
**no haze** (pure `#5a96df` sky, `#0a2a8a` sea), **high-noon sun** with hard black shadows,
**oversaturated ground** (`#dcc04b` grass, `#c29d61` road) and **flat, unshaded, uniformly bright
rock** (`#d6cbbc` lit vs `#9ba691`… i.e. barely any lit/shadow separation on the rock itself, while the
trees cast hard black shadows). The four things that would move the needle most, in order: rock *form*
(stratified wall, not blobs), atmosphere (pink haze + fog gradient + low warm sun), rock *material*
(cavity darkening + strata banding + vertex-colour AO), and the palette/post (desaturate, warm
tonemap, contact-darken the ground under vegetation).

---

## 1. Cliff / rock forms

### What the reference does
- **Scale.** The main wall is ~40–60 m tall from the beach; the car in the arch tunnel is ~4 m and
  fits ~10× vertically under the arch. Individual blocks in the wall are 6–15 m; boulders on the
  beach are 2–8 m (car sized to house sized). Distant stacks on the right are 30–50 m tall,
  15–25 m wide, standing in the water 50–150 m offshore.
- **Stratification.** Horizontal bedding planes every 3–8 m (visible as slight ledges, darker
  shadow lines and a change in weathering). Beds are sub-horizontal with a gentle 5–10° tilt.
- **Blocky vertical jointing.** Near-vertical joints every 5–15 m break the wall into
  rectangular pillars; corners are crisp, ~90°, slightly rounded by weathering (0.3–1 m radius).
  Silhouette against sky is a stepped skyline, not bumpy.
- **Overhangs and arches.** The centre wall has a true arch (span ~20 m, height ~25 m) with the road
  passing under it; several 2–5 m overhangs where a hard bed sticks out over a softer eroded bed
  (undercut ~2–4 m deep, forms a dark horizontal shadow band).
- **Stacks / islets.** Free-standing pillars (right side) that continue the bedding of the main wall
  — they read as "the same rock, detached" because strata lines carry across.
- **Talus / boulder field.** At the base, a 20–40 m wide apron of rounded boulders, 1–8 m, lying on
  sand; the largest ones sit half in the water. Boulders are the same pale stone, rounded on top,
  fracture-faced on the sides.
- **Road relation.** The road runs on a 10–20 m wide bench between the wall and the boulder apron,
  ~3–6 m above sea level, and tunnels *through* the rock at the arch. The wall towers 8–10× the
  road width.

### What ours does
- `cliff_coast_b.png`: rocks are **convex icosphere-ish blobs 4–15 m**, no bedding, no vertical
  jointing, no negative space (overhangs/arches). Every rock is the same shape at a different
  scale. Boulders float in water as separate blobs rather than forming an apron. The Terrain3D
  slope surface underneath (`#a39c7b`) actually reads *better* than the placed rocks.
- `cliff_coast.png`: the blobs are stacked into a lumpy mound; house scale vs rock scale is fine,
  but there is no "wall".
- Faceted flat-shaded normals reveal the low tri count directly (the brief says not low-poly).

### Direction (Godot GL Compat + Terrain3D)
1. **Replace blob rocks with a small kit of "block" meshes** (6–8 pieces): stratified slab (box
   ~8×4×3 m with 2–3 bedding notches), pillar (4×12×4 m), overhang slab (10×3×6 m), arch piece (two
   pillars + lintel, 20 m span), rounded talus boulder (3 sizes). Generate procedurally in
   `_add_rock` from a box primitive: displace with low-frequency noise (amplitude 0.3–0.6 m, 1
   octave ~6 m wavelength) + a **bedding function** (`y` quantised to 3–6 m steps, offset inward
   0.3–1 m on alternate beds) + a **joint function** (x/z quantised to 5–10 m, 0.2–0.5 m grooves).
   Smooth-shade with a 20–30° crease angle so the faces are smooth but edges stay crisp.
   Payoff: **high**. Effort: **medium** (2–3 days).
2. **Cliff wall as a heightfield + placed blocks.** Keep Terrain3D for the general slope (raise
   cliff height in `terrain.gd` so coast cliffs are 30–60 m, slope ≥ 70°), then stack 3–6 block
   pieces along the cliff crest and face on a per-chunk recipe, aligned to a shared "strata origin"
   (`y0 + n*bed_height`) so bedding lines carry across neighbouring pieces and across stacks.
   Payoff: **high**. Effort: **medium**.
3. **One or two hero arches/stacks** hand-placed at named coast places (the `cliff_coast` spot),
   road routed through the arch. Payoff: **high** for the target shot, **low** elsewhere.
   Effort: **low–medium** once the kit exists.
4. **Boulder apron:** at the cliff toe, scatter rounded boulders 1–8 m at ~0.05/m² for 20–40 m
   seaward, decreasing to 0.01/m² in shallow water; sink them 20–40 % into sand. Payoff: **med**.
   Effort: **low**.

---

## 2. Rock material

### Reference
- **Base colour** (un-hazed): pale warm limestone `#b8a891`–`#c9bba6` in sun, `#7d7885`–`#8d8590`
  in shadow (the shadow side is *bluish*, from sky fill). Haze pushes distant faces toward
  `#7693ae`.
- **Macro variation.** Patches 10–30 m across that shift ±8 % luminance and ±5° hue (warmer rust
  patches `#b39a7c`, cooler grey patches `#a7a5a4`). No visible texture tiling.
- **Strata banding.** Alternating beds are slightly different tone: hard beds lighter/warmer,
  soft beds darker/greyer (`#9a9089`), and every bedding plane has a 0.3–1 m dark line
  (`#6c6660`) — that's cavity/AO, not paint.
- **Cavity darkening.** Every joint, undercut and boulder contact has a strong dark occlusion
  gradient over 0.5–2 m. Boulder–sand contacts are the darkest thing on the beach (`#5e493d`).
- **Micro detail.** Fine speckle/grain at ~2–5 cm scale, low contrast; some vertical water
  streaks (darker `#8a8078`, 0.5 m wide, 5–15 m long) below ledges.
- **Vegetation on ledges.** Every bedding ledge wider than ~1 m carries a line of dark-green
  scrub (`#3b4a35`) and every cliff-top is capped with 2–4 m bushes and umbrella pines. The
  green reads as horizontal *lines* that trace the strata — this is the single strongest cue
  that the rock is layered.
- **Roughness:** matte; no specular highlight, no rim.

### Ours
- Uniform `#d6cbbc` with faint albedo texture; lit/shadow contrast on rock only ~15 %; no cavity
  darkening at all; no strata; no macro variation; no plants on rock. `cliff_coast.png` rock
  shadows are cool-grey but the *sunlit* side is the same value as the shadowed side.
- Terrain3D rock slope texture is fine-grain but too pale and greenish (`#a39c7b`).

### Direction
1. **Vertex-colour AO baked at generation** for kit rocks: darken vertices by
   (a) local concavity (dot of vertex normal vs. neighbour average), (b) height above local
   ground (0 at contact → 1 at 1.5 m), (c) "under-bed" flag for vertices just under a bedding
   step. Multiply albedo by 0.45–1.0. Store in `COLOR`, read in the rock shader. Payoff: **high**
   (this is the AO the brief says to fake). Effort: **low–medium**.
2. **Rock shader** (StandardMaterial-derived spatial shader): triplanar albedo (grain texture,
   uv 0.5 m) × strata band function `mix(0.85, 1.0, step(fract(world_y/bed_h), 0.8))` × dark line
   at bed boundaries × macro noise (world-space 3D noise, 20 m wavelength, ±10 % value, ±0.03
   hue toward rust) × vertex AO. Roughness 0.95, specular 0.1. Payoff: **high**. Effort: **low**.
3. **Terrain3D rock texture**: swap albedo_color toward `#bfb09a`, `ao_strength` up, enable
   `enable_macro_variation` with `macro_variation1 = #c8b9a2`, `macro_variation2 = #8f8a86`,
   `noise1_scale` ≈ 0.02 (50 m). Payoff: **med**. Effort: **low** (parameters only).
4. **Ledge vegetation**: for each kit rock, emit bush cards at bedding-step vertices whose upward
   face is ≥ 1 m wide (density ~0.4/m along the ledge, bush 1–2.5 m), and cap the top faces with
   0.15/m² bushes + one pine per 40 m². Payoff: **high** (sells stratification). Effort: **low–medium**.
5. Vertical drip streaks: a second triplanar mask, world-y stretched (uv 1×8 m), 20 % darken,
   only on faces with |normal.y| < 0.3 and only below a bedding step. Payoff: **low**. Effort: **low**.

---

## 3. Ground / road

### Reference
- **Road:** 4–5 m wide dirt track, two 0.4 m wide compacted ruts (`#a58868`) with a lighter
  loose-gravel crown between them (`#c2a988`) and dusty margins that bleed 1–2 m into the
  surroundings. Slight sheen only in the ruts. Road edges are ragged, never a clean line.
- **Ground:** sandy beach `#c3a682` next to the water, pale dry earth `#b09776` on the bench, dark
  compost/humus `#5a4a3a` under every bush (a 1–1.5 m dark halo). Scattered pebbles 5–30 cm,
  ~1/m² near boulders.
- **Dry grass:** straw-yellow `#a89660`, sparse (30–60 % coverage) in patches 5–20 m across, never
  a continuous lawn.
- Low contrast between road and ground: road is maybe 10 % lighter and 5 % warmer than the
  surrounding earth.

### Ours (`view_0/1.png`, `cliff_coast.png`)
- Road is a flat saturated orange `#c29d61`–`#d09a4c` fill 8–12 m wide with a hard edge; no ruts,
  no crown, no gravel, no margin blending. Grass is a neon `#dcc04b` / `#9ac83a` continuous
  carpet with high-contrast grass cards. No dark halo under bushes; no pebbles. Control-map
  blend edge is visible as a straight seam.

### Direction
1. **Road texture with baked ruts**: a 512 px albedo/normal pair, uv_scale = 4 m across so the two
   ruts line up with the road's width; paint the road onto the control map with a *directional*
   UV (Terrain3D has no per-texture UV rotation, so instead: use the *colour map* to paint the rut
   pair — two 0.4 m dark stripes at ±0.9 m from the centreline, `#9d8368` at 60 % blend — and keep
   the texture itself an isotropic gravel). Payoff: **med–high** (ruts are in the brief).
   Effort: **low**.
2. **Desaturate and darken the road**: control-map dirt texture `albedo_color ≈ #b59a78`; blend
   sharpness lower (`blend_sharpness` 0.7 → 0.4) and dither the road edge in the heightfield →
   control map pass with 1–2 m noise so the edge is ragged. Payoff: **med**. Effort: **low**.
3. **Bush halos**: when placing any bush/tree prop, paint a dark spot into the Terrain3D colour
   map (radius 1–2 m, `#6a5a48` at 50 %). This is the cheapest contact-AO available and the
   reference relies on it heavily. Payoff: **high** for close views. Effort: **low**.
4. **Grass**: instancer density down 50–70 %, card colour to `#9a8f5a`–`#b6a565`, add 20 %
   variation via instance colours, and mask grass to patches with a 15 m noise (coverage ~45 %).
   Payoff: **med**. Effort: **low**.

---

## 4. Vegetation

### Reference
- **Species:** (a) umbrella/stone pines — 8–14 m, flat-topped dark canopy 8–12 m wide on a 4–6 m
  bare trunk, canopy `#2f3d33` / lit `#5a6b4a`; (b) evergreen scrub (mastic/kermes oak/rosemary
  type) — 1–2.5 m rounded domes, `#3b4a35` shadow / `#6b7a4f` lit; (c) small deciduous shade trees
  along the road — 6–8 m round canopies `#4e6a3d`; (d) cypress spires in the villa shot (not the
  coast); (e) a few flowering pink/purple shrubs (villa shot only).
- **Density:** scrub ~0.08–0.15/m² on the bench, clustering into thickets 5–15 m across with bare
  earth between; pines 1 per 150–300 m² along the cliff top; ledge lines as in §2.
- **Colour:** all greens are **dark and desaturated** (S ≈ 25–35 %, V ≈ 25–45 % in sun); the
  brightest foliage in the frame is darker than the rock in shadow. Canopy shading is a soft
  top-lit gradient, no hard card silhouettes.
- **How it clings:** bushes sit *in* cracks and on ledges with their base hidden; tree roots are
  buried; nothing floats.

### Ours
- Trees are bright saturated `#1f6b2a`–`#2fa040` sphere/cone stacks with visible ring structure
  (`cliff_coast.png` pines look like stacked discs); cypresses in `view_0` are a monoculture
  fence. Bushes are neon lime discs. Everything is ~40 % too bright and ~2× too saturated.
  Vegetation sits on grass, never on rock. No umbrella-pine silhouette (flat top + bare trunk).

### Direction
1. **Recolour foliage cards** in `foliage.py`: canopy base `#3a4a36`, lit `#6e7d52`, add per-card
   0.7–1.0 value multiplier and ±0.05 hue jitter through instance colour. Material: `roughness 1`,
   no specular, `backlight` off; use a *baked* top-lit gradient in the card texture (top 1.0 → base
   0.6) rather than relying on lighting. Payoff: **high** (cheap, touches every frame).
   Effort: **low**.
2. **Umbrella pine tier**: trunk 4–6 m bare (`#4a3b31`), canopy a flattened ellipsoid 10×4 m,
   built from 3–5 large crossed cards rather than stacked discs; slight downward droop of the
   canopy edge. Payoff: **med–high**. Effort: **low–medium**.
3. **Ledge and crest placement** (see §2.4). Payoff: **high**. Effort: **low–medium**.
4. **Clustering**: scatter scrub with a 12 m clustered noise mask (coverage 40 %), density inside
   clusters 0.25/m², zero outside; that gives thickets with bare ground between.
   Payoff: **med**. Effort: **low**.

---

## 5. Water

### Reference
- **Colour bands** from shore outward: sand-tinted shallows `#b09c87`→`#7c9a9a` (0–5 m), turquoise
  `#3d8b8f` (5–20 m), teal `#2e6b7b` (20–60 m), navy `#25344f`–`#40587b` beyond 60 m, with the
  horizon lifted toward `#7a93aa` by haze. The transition follows *depth*, so it hugs every
  boulder.
- **Foam:** white/cream `#e6e2d7` at 60–80 % opacity in a 1–3 m ring around every rock touching
  water, with a 3–5 m trailing streak in the swell direction; a continuous foam line along the
  beach edge ~1 m wide; scattered foam streaks/whitecaps 2–6 m long, ~1 per 200 m² in open water.
- **Wave breakup:** small-scale (0.5–2 m) normal ripples that break the reflection into
  glints; larger 10–20 m swell bands faintly visible as tone variation. No hard specular disc.
- **Reflection:** sky colour dominates the far water (blue-grey), with the pink haze reflected
  at the horizon; near water shows the cliff's warm colour faintly. Fresnel: near-perpendicular
  view shows deep colour, grazing shows sky.

### Ours
- Flat saturated ultramarine `#0a2a8a`–`#02237d` everywhere, no depth bands (except a hard
  horizon fade to white), no foam, no ripple breakup, mirror-flat. `cliff_coast_b` water reads as
  a blue plastic sheet.

### Direction (all in `_build_sea`'s shader — GL Compat can't read the depth buffer reliably for
transparent passes, so use the *heightfield* instead)
1. **Depth from terrain**: pass the sea plane a sampler of the island height map (already
   available from `terrain.gd`, 3 m cells) + world→uv transform; `depth = sea_y - height`.
   Colour = `mix(shallow #7c9a9a, turquoise #3d8b8f, smoothstep(0,6,depth))`
   → `mix(…, navy #25344f, smoothstep(6,60,depth))`. Payoff: **high**. Effort: **low–medium**.
2. **Foam from the same depth**: `foam = smoothstep(1.5,0,depth) * noise(uv*0.5 + t*0.05)` plus
   a second term for placed rocks: write rock footprints into a small "obstacle" texture (or just
   pass up to N rock positions/radii as a uniform array, N ≤ 64 per chunk) and add
   `smoothstep(r+2, r, dist)`. Add whitecap sparkles: `step(0.93, noise(uv*0.05 + t*0.02))`.
   Foam colour `#e6e2d7`, `alpha 0.7`. Payoff: **high** (foam on rocks is in the brief).
   Effort: **medium**.
3. **Normal breakup + fake reflection**: two scrolling normal maps (0.8 m and 6 m scale), and
   reflect the *sky* via a Fresnel-weighted sample of the sky gradient colour (pass the sky's
   horizon/zenith uniforms) rather than SSR; add a weak sun glint (Blinn, roughness 0.15, ×0.4).
   Payoff: **med**. Effort: **low**.
4. **Horizon**: the sea's far colour must match the fog colour so it dissolves into the haze
   (see §6). Payoff: **med** (fixes the current hard white band). Effort: **low**.

---

## 6. Sky / atmosphere

### Reference
- **Sky:** pale blue-grey zenith `#8ea5be`, going to a lilac-pink haze `#a9aabf`–`#c4b0bb` in the
  upper-right (cloud-lit), horizon band `#7f9cb7`. Cloud shapes are soft pink-mauve blobs
  (`#b8a6b4`), no hard edges. There is very little pure blue anywhere; max sky saturation ≈ 25 %.
- **Sun:** low, ~20–25° elevation, from screen-left and slightly behind camera (cliff faces on
  the left of the arch are lit, the arch interior and right-facing walls are in shadow). Warm
  colour, roughly `#ffd9b0`.
- **Aerial perspective:** very strong. At ~150 m the cliff has lost ~30 % contrast and shifted
  toward `#7693ae`; at 400 m (far stacks) it's `#8fa3bb`, ~75 % toward sky; at the horizon
  everything is sky colour. Fog is *coloured* (blue-lavender), not white, and it is denser near
  sea level (the far stacks' bases are hazier than their tops).
- **Fog gradient:** height-dependent: dense at 0–20 m ASL, thinning above; plus a faint
  sun-side warm tint.

### Ours
- Pure saturated gradient sky `#5a96df`→white; sun near zenith (shadows straight down, tiny);
  no fog at all in `cliff_coast`; `cliff_coast_b` shows only a hard white horizon band. Zero
  aerial perspective — the far village is as contrasty as the foreground.

### Direction (all in `_build_environment`, GL Compat supports all of this)
1. **Sun**: `DirectionalLight3D` elevation 22°, azimuth so it comes from camera-left in the
   `cliff_coast` spot; colour `#ffd8b4`, energy ~1.3; `shadow_blur` 2–3 (see §7).
   Payoff: **high**. Effort: **trivial**.
2. **Sky**: `ProceduralSkyMaterial` with `sky_top_color #8ea5be`, `sky_horizon_color #b9aebf`,
   `ground_horizon_color #a9a4b0`, `ground_bottom_color #6f7a86`, `sky_curve 0.15`, sun angle max
   ~30° with `sun_curve 0.1` to spread a warm-pink glow; or a custom sky shader that adds a
   pink band `mix(sky, #c8aab8, pow(1-|dir.y|, 3) * 0.6)` + a few soft noise "clouds" tinted
   `#c2b0bd`. Payoff: **high**. Effort: **low**.
3. **Fog**: `Environment.fog_enabled`, `fog_light_color #9aa6bf`, `fog_density` ≈ 0.0035
   (so ~30 % at 150 m, ~70 % at 400 m — match the reference numbers above), `fog_height` = sea
   level, `fog_height_density` ≈ 0.08 (dense below 20 m, thinning above), `fog_sun_scatter` 0.3
   for the warm sun-side tint, `fog_aerial_perspective` 0.7 (blends fog toward sky colour with
   distance — this is what keeps far things *sky-coloured* rather than grey). Payoff: **very
   high** — this single change is most of "the reference look". Effort: **trivial**.
4. **Ambient**: `ambient_light_source = SKY`, `ambient_light_sky_contribution 1.0`,
   `ambient_light_energy 0.6`, and tint reflected sky slightly lilac so shadows go `#7d7885`
   rather than neutral grey. Payoff: **med–high**. Effort: **trivial**.

---

## 7. Lighting

### Reference
- **Contrast:** sunlit rock ≈ V 0.75, shadowed rock ≈ V 0.50; i.e. lit/shadow ratio ~1.5:1 —
  soft. Darkest values in frame (under boulders, inside scrub) ≈ V 0.15; brightest (foam) ≈ 0.9.
  No clipped blacks, no clipped whites.
- **Shadow softness:** penumbra ~0.5–1 m at 20 m from the caster (trees cast blurry blobs, not
  cut-outs). Cast shadows are *coloured* — blue-lilac `#7d7885` on rock, `#5a4a3a` on sand.
- **Ambient colour:** cool sky fill from above (shadow tops bluer) plus a hint of warm bounce
  from the sand on undersides.
- **Directionality:** clear — every block has a lit face, a half-lit face and a shadow face,
  which is what makes the jointing legible.

### Ours
- Sun near zenith: rock faces get almost identical light, so blocks read as one tone; tree
  shadows are pure black `#001a09` and razor-edged (`cliff_coast.png`). Ambient is white-neutral,
  so shadows are grey and the whole frame looks like a bleached noon.

### Direction
1. Low warm sun (§6.1) + `directional_shadow_mode ORTHOGONAL` or 2-split PSSM, `shadow_blur` 2–3,
   `shadow_normal_bias` 2 to avoid acne on the terrain. Payoff: **high**. Effort: **trivial**.
2. Sky-coloured ambient (§6.4) with energy so shadows land at ~65 % of lit value. Payoff: **high**.
   Effort: **trivial**.
3. Vertex AO on rocks and colour-map halos on ground (§2.1, §3.3) provide the contact darkening
   that SSAO would otherwise give. Payoff: **high**. Effort: **low–medium**.
4. Fake bounce: give the sun a slightly warmer colour and the ambient a slightly cooler one; add
   a tiny `light_indirect_energy`… (not available in Compat) → instead bake a warm tint into the
   *bottom* of vertex AO on rocks (`mix(#b39a7c, albedo, ao)`) so undersides look sand-lit.
   Payoff: **low**. Effort: **low**.

---

## 8. Post / grade

### Reference
- **Saturation:** overall ~0.7× of "natural"; greens and browns especially muted; only water
  and pink sky reach S ≈ 45 %. Whites are warm-grey, blacks are lifted (~`#1a1c22`).
- **Tonemap:** filmic-looking roll-off; highlights (foam, lit rock top) never clip; mid-tones
  slightly lifted; overall gamma ~1.1.
- **Colour cast:** whole frame has a lilac-pink haze in the highlights and a blue-grey tint in
  the shadows (a split-tone).
- **Vignette:** mild (~15 % darkening at the corners) — present but not obvious.
- **Sharpness:** soft; no visible sharpening halos; slight bloom on the foam and sky.

### Ours
- Full-saturation linear look, clipped shadows, no bloom, no cast, no vignette.

### Direction (Compat supports tonemap + adjustments + glow; no colour-correction LUT, but
`Environment.adjustment_color_correction` *does* work in Compat with a 1D gradient)
1. `tonemap_mode = FILMIC` or `ACES`, `tonemap_exposure 1.1`, `tonemap_white 1.0` (the default
   white point is what's clipping foam). Payoff: **med**. Effort: **trivial**.
2. `adjustment_enabled`, `adjustment_saturation 0.8`, `adjustment_contrast 0.95`,
   `adjustment_brightness 1.02`; `adjustment_color_correction` = a 256×1 gradient texture that
   lifts blacks to `#1a1c22` and tints highlights toward `#f3e6e8` (split-tone). Payoff: **med–high**
   for the "painterly" feel. Effort: **low**.
3. `glow_enabled`, `glow_intensity 0.25`, `glow_bloom 0.05`, `glow_hdr_threshold 0.9`, blend mode
   SOFTLIGHT — only foam and sky should bloom. Payoff: **low–med**. Effort: **trivial**.
4. Vignette: a full-screen `CanvasLayer` `ColorRect` with a radial-gradient shader at 15 %
   (Compat has no built-in vignette). Payoff: **low**. Effort: **trivial**.

---

## 9. Composition / camera

### Reference
- Camera ~25–35 m above the beach, ~40 m back from the boulder apron, pitched down ~15–20°,
  horizon at ~40 % from the top (sky gets 40 % of the frame, ground/water 60 %).
- Horizontal FOV ≈ 70–75° (vertical ~45° at 16:9): the near boulders are large in frame but the
  60 m wall still fits.
- The cliff wall runs *diagonally* from bottom-left toward the upper-centre and the coastline
  runs the opposite diagonal, so the frame is split into three wedges: cliff, bench/road, sea.
  The arch sits on the upper-right third-line; the shade tree on the lower-left third-line.
- Depth is staged in four planes: foreground boulders (0–40 m), bench + road (40–120 m), wall +
  arch (120–250 m), stacks and far coast (300–800 m) — each plane one haze step lighter.

### Ours
- `cliff_coast` is pitched too steeply and too close: the mound fills the frame, no sea, no far
  plane, horizon at ~35 % but only sky above it. `cliff_coast_b` is further out but sees the
  cliff *from* the water (nothing in the foreground), FOV looks ~60°.
- Rider's-eye `view_*` at ~1.2 m look correct for FOV but everything nearby is grass/road; with
  the road narrowed and rocks/bushes brought in they will improve automatically.

### Direction
1. Move `cliff_coast` in `spots.json` to ~30 m ASL, on the bench behind boulders, looking along
   the coast (not at it) so the wall is on one side and the sea on the other; vertical FOV 45°.
   Payoff: **med** (comparison score only, but it makes the other work visible). Effort: **trivial**.
2. Make sure the level actually offers that shot: road bench between wall and sea for ≥ 200 m of
   coastline near the spot, arch on the road, 2 stacks offshore. Payoff: **high**
   (it is the target). Effort: part of §1.

---

## 10. Secondary references (what they add)

- `ref_villa_vineyard.png`: same pale blocky cliff far behind (again with vegetation on every
  ledge and a strongly hazed `#a5b2c0` tone); dirt road with **two ruts and a grass median**;
  vineyard rows on a 2.5 m pitch; cypresses 8–12 m; dry-stone walls `#b3a38a`; dust/pollen haze in
  the air; long soft shadows from a low sun (~25°). Confirms §3, §6, §7.
- `ref_courtyard_closeup.png`: at 1–3 m the ground is flagstones (0.6–1 m slabs, `#b3a99a`) with
  dark mortar and 5–10 cm pebbles at ~20/m²; deep, coloured AO under every pot and plant; grass
  is sparse tufts (`#8c8a55`) not a carpet; foliage cards have soft baked gradients and dark
  interiors. Confirms §3.3, §4.1 and the need for close-range contact darkening.

---

## Top-10 by (payoff ÷ effort), for the `cliff_coast` target

| # | Item | Payoff | Effort | Notes |
|---|------|--------|--------|-------|
| 1 | **Fog + aerial perspective** (§6.3): `fog_light_color #9aa6bf`, density 0.0035, height fog at sea level, aerial_perspective 0.7 | very high | trivial | Biggest single change; fixes far plane, horizon, sea edge. |
| 2 | **Low warm sun + soft shadows + sky ambient** (§6.1, §6.4, §7.1) | high | trivial | Gives blocks lit/half/shadow faces; kills black shadows. |
| 3 | **Pink-haze sky** (§6.2) | high | low | Sky is 40 % of the frame. |
| 4 | **Block rock kit with strata + joints** (§1.1) | high | medium | The core geometric difference. |
| 5 | **Vertex-colour AO + rock shader** (§2.1, §2.2) | high | low–medium | Cavity darkening, bedding lines, macro variation. |
| 6 | **Cliff wall 30–60 m + hero arch/stacks at the spot** (§1.2, §1.3) | high | medium | Makes the target composition possible. |
| 7 | **Foliage recolour + baked gradient + umbrella pines** (§4.1, §4.2) | high | low | Kills the neon greens in every frame. |
| 8 | **Water depth bands + foam** (§5.1, §5.2) | high | medium | Turquoise→navy and foam on rocks are explicit brief items. |
| 9 | **Ledge/crest vegetation + bush halos in colour map** (§2.4, §3.3) | high | low–medium | Sells stratification and fakes contact AO. |
| 10 | **Road: narrower, desaturated, ruts via colour map, ragged edge** (§3.1, §3.2) | med–high | low | Plus grade: filmic tonemap, saturation 0.8, split-tone (§8). |

Suggested order of attack: 1–3 first (an afternoon, immediately changes every render), then 7 and
10 (parameter-level, cheap), then 4–6 together (the rock work), then 8, then 9, then §8 post as
the final polish. Re-render `cliff_coast` after 1–3 and after 4–6; other spots only at the end.
