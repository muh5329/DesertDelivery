# Technical research — verified recipes for Godot 4.7 GL Compatibility

Scope: the *how* behind `RESEARCH_art.md` (sky/fog/grade, rock shader, water shader, procedural
rock meshes, imported trees, performance rules). Everything below was **run in the sandbox project
`/root/t3dtest`** on Godot `4.7.stable.official.5b4e0cb0f` with `--rendering-driver opengl3` under
`xvfb-run` (llvmpipe), and screenshots were inspected. Nothing in `/root/dd` was touched except
this file. All sandbox files are under `/root/t3dtest/tech/` and are meant to be copied into the
project as-is (paths listed in §0).

Source-of-truth checks were made against the 4.7 branch of the engine itself (the Compatibility
renderer is `drivers/gles3/`), not just the docs, because the docs are partly stale for
Compatibility (see §1.1 — e.g. Compatibility *does* use reverse-Z in 4.7, and `fog_aerial_perspective`
is a no-op on geometry).

## 0. TL;DR + sandbox map

| Sandbox file | What it is | Status |
|---|---|---|
| `/root/t3dtest/tech/rock.gdshader` | stratified-limestone spatial shader (§2) | compiles, renders, screenshot |
| `/root/t3dtest/tech/water.gdshader` | sea shader with depth-texture bands + foam + fresnel (§3) | compiles, renders, depth verified with a debug view |
| `/root/t3dtest/tech/leaf.gdshader` | leaf-card shader for imported Quaternius trees (§5) | compiles, renders |
| `/root/t3dtest/tech/rockgen.gd` | `class_name RockGen` procedural block/boulder generator with LOD + collision + vertex AO (§4) | 21 rocks ≈ 130–190 ms total in GDScript |
| `/root/t3dtest/tech/tech_test.gd` + `tech.tscn` | the verification scene: environment recipe, rocks, water, MultiMesh scree, GLTF trees, screenshot | prints tri counts / timings, saves PNG |
| `/root/t3dtest/tech/shots/*.png` | renders referenced below | |
| `/root/t3dtest/tech/tex/rock019_*.jpg`, `rock021_*.jpg` | ambientCG Rock019/021 (copied from `/root/assets_pool/ambientcg`) | |
| `/root/t3dtest/tech/models/*.gltf` + png | Quaternius TwistedTree_1 / Pine_1 + their textures | |

Exact commands that were run (all from `/root/t3dtest`):

```
godot --headless --path . --import                       # one-off: imports textures + gltf (creates .godot/imported)
godot --headless --path . tech/tech.tscn -- --rocks=30   # generation timing only, no rendering
xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 --resolution 1280x720 \
    tech/tech.tscn -- --shot=/tmp/tech6.png --rocks=14   # ~100 s on llvmpipe (4 frames + screenshot)
# variants: --waterdebug (water outputs vertical depth/10), --sky=1 (sky_cover clouds), --sky=2 (PhysicalSkyMaterial)
```

Log of the final run (`tech/shots/last_run.log`), no `SHADER ERROR` / `ERROR` lines apart from the
container's ALSA/V-Sync noise:

```
OpenGL API 4.5 (Core Profile) Mesa 25.2.8 - Compatibility - Using Device: Mesa - llvmpipe
[tech] rocks: 21 pieces, LOD0 27152 tris, LOD1 4112 tris, generated in 188 ms (9.0 ms/rock)
[tech] tree via load(): TwistedTree_1 9564 tris ["Bark_TwistedTree:StandardMaterial3D", ":ShaderMaterial"]
[tech] tree via GLTFDocument: Pine_1 3947 tris ["Bark_NormalTree:StandardMaterial3D", ":ShaderMaterial"]
[tech] screenshot saved /tmp/tech6.png (1280, 720)
```

Headless timing run with `--rocks=30`: `36 pieces, LOD0 41448 tris, LOD1 6984 tris, generated in 210 ms (5.8 ms/rock)`.

The headline findings that change what the art research assumed:

1. **`fog_aerial_perspective` does nothing to geometry in Compatibility 4.7** — the block is
   commented out in `drivers/gles3/shaders/scene.glsl` (`fog_process`). It only affects the *sky*
   (`sky.glsl` still mixes fog colour toward the sky colour). So the "far things become sky-coloured"
   effect has to come from choosing `fog_light_color` ≈ the horizon sky colour and using
   `fog_sky_affect` to pull the sky toward the fog. Exponential depth fog, height fog and
   `fog_sun_scatter` **do** work (verified in source and in the renders).
2. **`Light3D.shadow_blur` is ignored by the Compatibility renderer** (never read in
   `rasterizer_scene_gles3.cpp`; the GLES3 light storage just stores the default). Shadow softness
   comes only from the project setting
   `rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality`
   (≥ Soft Low = 5-tap PCF, ≥ Soft High = 13-tap PCF spread ±2 texels) and from the shadow-map
   texel size (`directional_shadow/size` ÷ covered distance). PCSS (`light_angular_distance`) is
   Forward+ only.
3. **`hint_depth_texture` works in Compatibility** (docs table + source: the opaque depth is blitted
   to a backbuffer texture right before the transparent pass, `rasterizer_scene_gles3.cpp` ≈ l.2881).
   Compatibility in 4.7 uses **reverse-Z with OpenGL −1..1 NDC** (`set_depth_correction(flip, reverse_z=true,
   remap_z=false)`, depth cleared to 0, `GL_GEQUAL`), so the reconstruction is
   `ndc = vec3(SCREEN_UV*2-1, depth*2-1); v = INV_PROJECTION_MATRIX*vec4(ndc,1); linear = -v.z/v.w`.
   Verified by a debug render (`tech/shots/water_depth_debug.png`: depth 0 at the shoreline and around
   every rock, growing seaward). Any material that reads it is forced into the transparent pass.
4. **Glow/adjustments/tonemap all work** in Compatibility, but glow is a simplified single-pass
   implementation: `glow_levels/*`, `glow_strength`, `glow_blend_mode` (always SCREEN), `glow_mix`,
   `glow_map`, `glow_normalized` have no effect. Enabling glow, adjustments or SSAO switches the
   renderer to "tonemap in post" (extra fullscreen pass, 10-bit intermediate with a 0.25 luminance
   scale for fake HDR); otherwise tonemapping happens inside the scene shader.
5. **Compatibility 4.6+ has a simplified SSAO** (docs + source: `ssao_enabled` supported, only
   `ssao_radius` and `ssao_intensity` are honoured). The brief says "no SSAO", and on llvmpipe it is a
   full-screen depth pass we cannot afford, but it exists if a real GPU target ever wants it.
6. `Image.load_from_file()` prints *"this will not work on export"* — for shipping, textures must go
   through the importer (`load("res://x.jpg")` → `CompressedTexture2D`), which is what the final
   sandbox run uses. Runtime GLTF loading via `GLTFDocument` needs no import and works in exports.

---

## 1. Environment: sky, fog, tonemap, grade, sun, ambient

### 1.1 What actually works in Compatibility (4.7)

Cross-checked against `doc/classes/Environment.xml` (4.7 branch), `tutorials/rendering/renderers.rst`
feature table, and `drivers/gles3/` sources.

| Feature | Compatibility | Evidence |
|---|---|---|
| Sky: `ProceduralSkyMaterial`, `PhysicalSkyMaterial`, `PanoramaSkyMaterial`, custom sky shader | ✔ | rendered both (`shots/sky_cover_vs_physical.png`) |
| `ProceduralSkyMaterial.sky_cover` + `sky_cover_modulate` (cloud texture) | ✔ | rendered (`--sky=1`) |
| Ambient from sky (`AMBIENT_SOURCE_SKY`, `ambient_light_sky_contribution`) | ✔ | rendered |
| Reflections from sky radiance (`REFLECTION_SOURCE_SKY`, 2 ReflectionProbes per mesh max) | ✔ | rendered (water specular) |
| Exponential depth fog (`FOG_MODE_EXPONENTIAL`, `fog_density`) | ✔ | `scene.glsl` `fog_process` |
| Depth fog with begin/end/curve (`FOG_MODE_DEPTH`) | ✔ | `USE_DEPTH_FOG` in `scene.glsl` |
| Height fog (`fog_height`, `fog_height_density`) | ✔ | `scene.glsl` (`vfog_amount`, takes `max()` with depth fog) |
| `fog_sun_scatter` | ✔ | `USE_SUN_SCATTER` in `scene.glsl` and `sky.glsl` |
| `fog_sky_affect` | ✔ (sky only, by definition) | `sky.glsl` uniform |
| `fog_aerial_perspective` | ✘ on geometry (commented out), ✔ on the sky | `scene.glsl` `fog_process`, `sky.glsl` |
| Volumetric fog / FogVolume | ✘ | docs + stubbed `fog_volume_instance_*` |
| Tonemap Linear/Reinhard/Filmic/ACES/AgX, `tonemap_exposure`, `tonemap_white` | ✔ | rendered (Filmic) |
| `adjustment_*` (brightness/contrast/saturation) | ✔ | rendered |
| `adjustment_color_correction` with `GradientTexture1D` | ✔ | rendered (split-tone gradient) |
| `adjustment_color_correction` with `Texture3D` LUT | ✔ per docs, **not tested here** | — |
| Glow (`glow_intensity`, `glow_bloom`, `glow_hdr_threshold`, `glow_hdr_scale`, `glow_hdr_luminance_cap`) | ✔ simplified | rendered; `glow_levels/*`, `glow_strength`, `glow_blend_mode`, `glow_mix`, `glow_map`, `glow_normalized` ignored |
| SSAO | ✔ simplified (radius + intensity only, 4.6+) | docs; not used (cost) |
| SSR, SSIL, SDFGI, VoxelGI, auto-exposure, DOF, debanding, TAA/FXAA/SMAA, decals, `light_angular_distance`/`light_size` PCSS, `shadow_blur` | ✘ | docs + source |
| MSAA 3D, SSAA (`scaling_3d_scale` > 1) | ✔ | docs (not tested with the depth texture — see §3.4) |
| Colour precision | RGBA8 (RGB10A2 when glow is on) — low dynamic range | `renderers.rst`, `rasterizer_scene_gles3.cpp` `luminance_multiplier` |

Consequences for the look: because the framebuffer is 8-bit LDR, keep `tonemap_white` modest
(2–4) and light energies ≈ 1–1.5 so the sky and foam do not clip *before* the tonemapper; there is no
real HDR headroom to recover.

### 1.2 The recipe (verified, `tech_test.gd::_build_environment`)

Sky choice: **`ProceduralSkyMaterial` with `sky_cover` clouds** (left half of
`shots/sky_cover_vs_physical.png`) is the right tool — it gives direct control of the four colours
the art research measured and cheap soft cloud blobs. `PhysicalSkyMaterial` (right half) can be
made hazy (`mie_coefficient` 0.02, `turbidity` 12, `mie_color` pink) but its zenith stays a grey-blue
that is hard to push toward the reference's lilac, it darkens ambient a lot, and it is slower on a
shader basis (per-pixel scattering). Use it only if a dynamic sun is ever needed.

```gdscript
func _build_environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color("8ea5be")
	sm.sky_horizon_color = Color("c4b0bb")
	sm.sky_curve = 0.12
	sm.sky_energy_multiplier = 1.0
	sm.ground_horizon_color = Color("b3a8b4")
	sm.ground_bottom_color = Color("6f7a86")
	sm.ground_curve = 0.02
	sm.sun_angle_max = 40.0
	sm.sun_curve = 0.08
	sm.use_debanding = false
	if sky_mode == 1:
		# soft pink-mauve cloud blobs: a seamless noise panorama as sky_cover, tinted by sky_cover_modulate
		var cov := NoiseTexture2D.new()
		cov.width = 512; cov.height = 256
		cov.seamless = true
		var cn := FastNoiseLite.new(); cn.seed = 5; cn.frequency = 0.012; cn.fractal_octaves = 4
		cov.noise = cn
		cov.color_ramp = Gradient.new()
		cov.color_ramp.set_offset(0, 0.45); cov.color_ramp.set_color(0, Color(0, 0, 0, 0))
		cov.color_ramp.set_offset(1, 0.75); cov.color_ramp.set_color(1, Color(1, 1, 1, 1))
		sm.sky_cover = cov
		sm.sky_cover_modulate = Color("c2b0bd")
	sky.sky_material = sm
	if sky_mode == 2:
		var pm := PhysicalSkyMaterial.new()
		pm.rayleigh_coefficient = 1.6
		pm.rayleigh_color = Color(0.40, 0.44, 0.62)   # desaturated, lifted toward lilac
		pm.mie_coefficient = 0.02                      # heavy haze -> broad warm glow round the low sun
		pm.mie_eccentricity = 0.7
		pm.mie_color = Color(0.86, 0.72, 0.74)         # pink-ish haze
		pm.turbidity = 12.0
		pm.sun_disk_scale = 2.0
		pm.ground_color = Color(0.35, 0.34, 0.36)
		pm.energy_multiplier = 1.0
		pm.use_debanding = false
		sky.sky_material = pm
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.7
	env.ambient_light_color = Color("8f8aa0")     # lilac fill for the 30 % that is not sky
	env.ambient_light_energy = 0.9
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.tonemap_white = 4.0
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color("9aa6bf")
	env.fog_light_energy = 1.0
	env.fog_density = 0.0035
	env.fog_sun_scatter = 0.25
	env.fog_sky_affect = 0.35
	env.fog_aerial_perspective = 0.0    # NO-OP on geometry in Compatibility (see notes); only affects the sky
	env.fog_height = 0.0
	env.fog_height_density = 0.06
	env.glow_enabled = true
	env.glow_intensity = 0.3
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 0.9
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.82
	env.adjustment_contrast = 0.97
	env.adjustment_brightness = 1.02
	var grad := Gradient.new()
	grad.set_color(0, Color("1a1c22"))
	grad.set_color(1, Color("f3e6e8"))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	gt.width = 256
	env.adjustment_color_correction = gt
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.light_color = Color("ffd8b4")
	sun.light_energy = 1.3
	sun.rotation_degrees = Vector3(-22.0, 35.0, 0.0)   # 22 deg elevation; light travels (-0.53,-0.37,-0.76): from camera-right, behind (camera looks along -z)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_split_1 = 0.15
	sun.directional_shadow_max_distance = 250.0
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_fade_start = 0.8
	sun.shadow_blur = 2.5
	sun.shadow_bias = 0.08
	sun.shadow_normal_bias = 2.0
	add_child(sun)
```

Notes on the numbers:

- `fog_density 0.0035` → 30 % fog at 100 m, 50 % at 200 m, 75 % at 400 m — matching the reference's
  "30 % contrast lost at 150 m, ~75 % at 400 m". Height fog with `fog_height = 0` (sea level) and
  `fog_height_density 0.06` adds `1-exp(-0.06·depth_below_0)` — i.e. it only *adds* fog below sea
  level here (the formula takes `max(height_fog, depth_fog)`), so raise `fog_height` to ~15 m if the
  bases of far stacks should be hazier than their tops (the reference cue). Height fog is *not*
  distance-scaled in Compatibility — anything below `fog_height` gets it even at 1 m, so keep
  `fog_height` ≤ camera height, or the near ground fogs up.
- `fog_light_color` should equal the sky's horizon colour (`#9aa6bf`-ish) because aerial perspective
  is unavailable on geometry; `fog_sky_affect 0.35` pulls the sky's lower half toward that colour so
  the sea horizon dissolves. `fog_sun_scatter 0.25` puts the warm glow on the sun side of the haze.
- The sun's `rotation_degrees.y` picks the side; for a camera looking down −Z the light direction is
  `(-0.93·sin(yaw), -0.37, -0.93·cos(yaw))` at 22° elevation, so **yaw +35..+45 = light from
  camera-right/behind, yaw −35..−45 = from camera-left/behind**. In the `cliff_coast` spot pick the
  yaw so the light comes from the *sea* side, otherwise the cliff wall shadows the whole bench (that
  is exactly what happened in the first sandbox render).
- Shadows: `SHADOW_PARALLEL_2_SPLITS`, `directional_shadow_max_distance 250`, `split_1 0.15`,
  `blend_splits true`, `shadow_bias 0.08`, `shadow_normal_bias 2.0`. `shadow_blur` is set for
  Forward+ parity but **does nothing here** — softness is set in `project.godot`:

```
[rendering]
lights_and_shadows/directional_shadow/soft_shadow_filter_quality=3   ; Soft High = 13-tap PCF (±2 texels)
lights_and_shadows/directional_shadow/size=2048                      ; coarser texels = wider penumbra (and cheaper)
lights_and_shadows/directional_shadow/16_bits=true                   ; default; fine with the biases above
```

  With 2 splits over 250 m and a 2048 map, the far split's texel is ≈ 10 cm, the 13-tap kernel
  ≈ ±20 cm → a 40–60 cm penumbra on the cliff, which is the reference's "blurry blobs, not
  cut-outs". If tree shadows still look razor-edged at 20 m, drop to `size=1024` before touching
  anything else. Sandbox `project.godot` uses the defaults (quality 2 = Soft Low, 4096) and the
  boulder shadows in `shots/tech_final_1280.png` are already soft-edged.
- Ambient: `AMBIENT_SOURCE_SKY` with `sky_contribution 0.7` + a lilac `ambient_light_color #8f8aa0`
  at `energy 0.9` gives the blue-lilac shadow fill (`#7d7885` in the reference). The whole 30 %
  non-sky part is the knob for "how coloured are shadows".
- Post: `TONE_MAPPER_FILMIC`, `exposure 1.0`, `white 4.0`; adjustments `saturation 0.82`,
  `contrast 0.97`, `brightness 1.02`; `adjustment_color_correction` = a 256-px `GradientTexture1D`
  black→`#1a1c22`, white→`#f3e6e8` (lifted blacks, warm-pink highlights). Glow `intensity 0.3`,
  `bloom 0.05`, `hdr_threshold 0.9`. All of these are visible in the final render; the frame has
  the lifted, pink-hazed, low-saturation quality of the reference.
- Vignette: not available; a `CanvasLayer` + `ColorRect` with a radial-gradient canvas shader (not
  tested, trivial).

---

## 2. Rock shader (`/root/t3dtest/tech/rock.gdshader`)

What it does, in order: triplanar albedo (3 samples) → triplanar normal via UDN blend, written to
`NORMAL` in view space (no tangents needed, so it works on generated meshes) → world-space bedding:
alternate beds darkened, a dark "cavity" line of `bed_line_width` at every bedding plane on
non-up-facing surfaces, with a shared `bed_origin_y`/`bed_tilt` so the lines carry across pieces →
macro variation (3-octave world-space value noise, ±10 % value and a rust↔grey tint over 22 m) →
vertex AO from `COLOR.r` (deep AO goes *warm* via `ao_warm_tint`, never black) → moss/scrub tint on
up-facing surfaces gated by noise and slightly favouring cavities → `ROUGHNESS 0.95`, `SPECULAR 0.1`.

Important detail found while tuning: the albedo texture is **normalised by its mean**
(`albedo_tex_mean`, Rock019 = 0.71 sRGB, Rock021 = 0.64) so `base_tint` is the actual colour the
rock ends up with in flat light. Without this the first render came out charcoal-grey
(texture mean 0.71 × tint 0.84 × AO 0.6 × band 0.85 ≈ 0.18 linear). `shots/rock_debug_row.png`
shows the four `debug_mode` views (full / AO only / flat tint + geometry normal / world normal) that
were used to prove each stage works.

```glsl
// Stratified limestone rock — Godot 4.7 GL Compatibility.
// Triplanar albedo + normal (world space), world-space bedding bands with a dark cavity line at
// every bedding plane, vertex-colour AO (COLOR.r = 0 occluded .. 1 open), moss/scrub tint on
// up-facing surfaces, macro colour variation from world-space 3D value noise.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tex_metres = 3.0;            // one texture tile covers this many metres
uniform float normal_strength : hint_range(0.0, 2.0) = 0.8;
uniform vec3 base_tint : source_color = vec3(0.80, 0.75, 0.66);   // #ccbfa8: the *mean* colour the rock should have in flat light
uniform float albedo_tex_mean = 0.71;     // mean sRGB value of albedo_tex (Rock019 = 0.71, Rock021 = 0.64); the texture is normalised by it
uniform float triplanar_sharpness : hint_range(1.0, 16.0) = 6.0;

// bedding (strata) — all in world space so lines carry across neighbouring pieces
uniform float bed_height = 4.0;            // metres between bedding planes
uniform float bed_tilt = 0.08;             // dy per metre of x (5-10 degrees)
uniform float bed_origin_y = 0.0;          // shared "strata origin" for the whole cliff
uniform float soft_bed_darken : hint_range(0.0, 1.0) = 0.15;   // alternate beds are this much darker
uniform float bed_line_width = 0.5;        // dark cavity line half-width at each bedding plane (m)
uniform float bed_line_strength : hint_range(0.0, 1.0) = 0.55;

// cavity / AO from vertex colour
uniform float ao_min : hint_range(0.0, 1.0) = 0.55;              // albedo multiplier at COLOR.r == 0
uniform vec3 ao_warm_tint : source_color = vec3(0.70, 0.60, 0.49); // sand-bounce tint in the deepest AO

// moss / scrub on up-facing surfaces
uniform vec3 moss_color : source_color = vec3(0.23, 0.29, 0.21);   // #3b4a35
uniform float moss_amount : hint_range(0.0, 1.0) = 0.6;
uniform float moss_slope_start = 0.55;     // world normal.y where moss starts
uniform float moss_slope_full = 0.9;

// macro variation
uniform float macro_metres = 22.0;         // wavelength of the patchiness
uniform float macro_value : hint_range(0.0, 0.5) = 0.10;         // +/- luminance
uniform vec3 macro_rust : source_color = vec3(0.70, 0.60, 0.49);  // #b39a7c warm patches
uniform vec3 macro_grey : source_color = vec3(0.65, 0.65, 0.64);  // #a7a5a4 cool patches

uniform float roughness_value : hint_range(0.0, 1.0) = 0.95;
uniform float specular_value : hint_range(0.0, 1.0) = 0.1;
uniform int debug_mode = 0;   // 1 = show vertex AO, 2 = no AO/normal map, 3 = world normal

varying vec3 wpos;
varying vec3 wnrm;

// ---- cheap 3D value noise (world space) ----
float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
float vnoise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash3(i + vec3(0, 0, 0)), hash3(i + vec3(1, 0, 0)), f.x),
			mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x),
			mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
float fbm3(vec3 p) {
	return vnoise3(p) * 0.6 + vnoise3(p * 2.03 + 11.0) * 0.28 + vnoise3(p * 4.1 + 23.0) * 0.12;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// ---------- triplanar weights ----------
	vec3 n = normalize(wnrm);
	vec3 bw = pow(abs(n), vec3(triplanar_sharpness));
	bw /= (bw.x + bw.y + bw.z);
	vec3 uvp = wpos / tex_metres;
	// offset each projection so the three don't line up
	vec2 uv_x = uvp.zy + vec2(0.37, 0.11);
	vec2 uv_y = uvp.xz + vec2(0.71, 0.53);
	vec2 uv_z = uvp.xy + vec2(0.13, 0.89);

	vec3 alb = texture(albedo_tex, uv_x).rgb * bw.x
			 + texture(albedo_tex, uv_y).rgb * bw.y
			 + texture(albedo_tex, uv_z).rgb * bw.z;

	// ---------- triplanar normal (UDN-style blend, world space) ----------
	vec3 tn_x = texture(normal_tex, uv_x).xyz * 2.0 - 1.0;
	vec3 tn_y = texture(normal_tex, uv_y).xyz * 2.0 - 1.0;
	vec3 tn_z = texture(normal_tex, uv_z).xyz * 2.0 - 1.0;
	tn_x.xy *= normal_strength; tn_y.xy *= normal_strength; tn_z.xy *= normal_strength;
	// UDN blend: each projection's tangent-space xy perturbs the world normal along the world axes
	// that its UVs were derived from (x-proj uv = zy, y-proj uv = xz, z-proj uv = xy). Because the
	// UVs come straight from world coordinates, no sign flips are needed for back-facing sides.
	vec3 wn = normalize(n + vec3(0.0, tn_x.y, tn_x.x) * bw.x
						  + vec3(tn_y.x, 0.0, tn_y.y) * bw.y
						  + vec3(tn_z.x, tn_z.y, 0.0) * bw.z);
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);

	// ---------- bedding bands ----------
	float yb = wpos.y - bed_origin_y + wpos.x * bed_tilt;
	float bed_f = yb / bed_height;
	float bed_i = floor(bed_f);
	float in_bed = fract(bed_f);                          // 0 at the bottom of a bed, 1 at the top
	float soft = step(0.5, fract(bed_i * 0.5 + hash3(vec3(bed_i, 3.0, 7.0)) * 0.3)); // alternate, jittered
	float band = 1.0 - soft * soft_bed_darken;
	// dark cavity line at each bedding plane, mostly on side faces (up-facing ledges stay bright)
	float dist_plane = min(in_bed, 1.0 - in_bed) * bed_height;      // metres to nearest plane
	float line_m = 1.0 - smoothstep(0.0, bed_line_width, dist_plane);
	line_m *= 1.0 - smoothstep(0.35, 0.8, n.y);
	band *= 1.0 - line_m * bed_line_strength;

	// ---------- macro variation ----------
	float m1 = fbm3(wpos / macro_metres);
	float m2 = vnoise3(wpos / (macro_metres * 0.55) + 41.0);
	vec3 macro_tint = mix(macro_rust, macro_grey, m2) / vec3(0.675, 0.625, 0.565); // normalise so mean ~1
	float macro_lum = 1.0 + (m1 - 0.5) * 2.0 * macro_value;
	// normalise the texture around 1.0 so base_tint is the colour you get, whatever texture is plugged in
	float mean_lin = pow(albedo_tex_mean, 2.2);
	alb = (alb / mean_lin) * base_tint * macro_lum * mix(vec3(1.0), macro_tint, 0.5);

	// ---------- vertex AO ----------
	float ao = COLOR.r;
	vec3 ao_mul = mix(ao_warm_tint * ao_min / 0.6, vec3(1.0), ao); // deep AO goes warm, not black
	alb *= ao_mul;
	alb *= band;

	// ---------- moss on up-facing, in crevices and with noise ----------
	float up = smoothstep(moss_slope_start, moss_slope_full, wn.y);
	float moss_n = smoothstep(0.35, 0.75, fbm3(wpos * 0.9 + 100.0));
	float moss = up * moss_n * moss_amount * mix(1.3, 0.7, ao);   // slightly more in cavities
	moss = clamp(moss, 0.0, 1.0);
	alb = mix(alb, moss_color * (0.8 + 0.4 * m1), moss);

	if (debug_mode == 1) { alb = vec3(COLOR.r); }
	if (debug_mode == 2) { alb = base_tint; NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz); }
	if (debug_mode == 3) { alb = wn * 0.5 + 0.5; }
	ALBEDO = alb;
	ROUGHNESS = roughness_value;
	SPECULAR = specular_value;
	METALLIC = 0.0;
}
```

Hooking it up (from `tech_test.gd`):

```gdscript
var rock_mat := ShaderMaterial.new()
rock_mat.shader = load("res://tech/rock.gdshader")
rock_mat.set_shader_parameter("albedo_tex", load("res://tech/tex/rock019_alb.jpg"))   # CompressedTexture2D
rock_mat.set_shader_parameter("normal_tex", load("res://tech/tex/rock019_nrm.jpg"))
rock_mat.set_shader_parameter("bed_height", 3.5)    # must match RockGen params
rock_mat.set_shader_parameter("bed_tilt", 0.06)
rock_mat.set_shader_parameter("bed_origin_y", 0.5)
```

Texture import: put the ambientCG JPGs under `res://assets/...` and let the editor/`--import` create
the `.import` files; add `compress/normal_map=1` to the normal map's `.import` (or name it
`*_normal.jpg` so the importer detects it) for better RGTC quality. Both maps are 1K and seamless;
`tex_metres 3.0` gives the 2–5 cm grain the reference has; use Rock021 as `albedo_tex` on every third
piece for extra macro variety.

The shader is one material for all rocks (MultiMesh-friendly: `COLOR` is per-vertex on generated
meshes and per-instance on MultiMesh via `use_colors`, and both feed `COLOR.r`).

---

## 3. Water shader (`/root/t3dtest/tech/water.gdshader`)

### 3.1 Depth texture availability — confirmed

- `renderers.rst` feature table: *Depth texture: Supported* for Compatibility.
- `rasterizer_scene_gles3.cpp`: after the opaque pass and sky, if any visible surface has
  `FLAG_USES_DEPTH_TEXTURE`, the opaque depth/stencil is blitted into `backbuffer_depth` and bound
  to texunit −7; then the transparent pass runs. Materials using it are treated as alpha
  (`has_read_screen_alpha`), i.e. always drawn in the transparent pass and **do not write depth
  unless `depth_draw_always`**. Only *opaque* geometry is in the depth texture (the sea floor,
  rocks, terrain) — transparent grass cards are not, which is what we want.
- Reconstruction (Compatibility 4.7 = reverse-Z, OpenGL NDC): see the shader's
  `linear_depth_from_buffer()`. The `#if CURRENT_RENDERER == RENDERER_COMPATIBILITY` branch is
  the one that ran; the `#else` branch is the RD (Forward+/Mobile) formula from the docs.
- Verified visually: `shots/water_depth_debug.png` (`--waterdebug`, water outputs `vdepth/10`):
  black at the shoreline and in a ring around every submerged boulder, white beyond ~10 m depth.

### 3.2 What the shader does

`thick = scene_linear_depth − fragment_linear_depth` (metres of water along the view ray) →
`vdepth = thick · |view·up|` (vertical depth for a flat sea, so bands don't slide with view
angle) → four colour bands (`col_shallow` sand → `col_turquoise` at 5 m → `col_teal` at 20 m →
`col_navy` at 60 m; all from the art research) → two scrolling normal maps (0.9 m and 6.5 m tiles,
different directions) blended in tangent space and written to `NORMAL` → Fresnel
(`bias 0.03`, `pow 5`) mixes toward a two-colour sky (`sky_zenith`/`sky_horizon`, pass the same
colours as the ProceduralSkyMaterial) using the reflected direction's `y` — this is the "no SSR"
reflection; the sun glint comes from the engine's specular with `ROUGHNESS 0.18` → foam: a
`shore` mask from `vdepth < foam_depth` broken by two scrolling noise reads (solid only in the last
~30 cm, lace further out) plus sparse whitecaps in water deeper than 3 m → `ALPHA` from
`alpha_shallow 0.35` at the shoreline to 1 at 6 m, plus foam.

```glsl
// Sea surface — Godot 4.7 GL Compatibility.
// Depth-based colour bands from the depth buffer (hint_depth_texture works in Compatibility: the
// opaque depth is blitted to a backbuffer before the transparent pass), shoreline foam from
// depth + scrolling noise, two scrolling normal maps, sky reflection by Fresnel (no SSR).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D depth_tex : hint_depth_texture, filter_linear;
uniform sampler2D normal_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D foam_noise : filter_linear_mipmap, repeat_enable;

uniform vec3 col_shallow : source_color = vec3(0.69, 0.61, 0.53);   // #b09c87 sand-tinted
uniform vec3 col_turquoise : source_color = vec3(0.24, 0.55, 0.56); // #3d8b8f
uniform vec3 col_teal : source_color = vec3(0.18, 0.42, 0.48);      // #2e6b7b
uniform vec3 col_navy : source_color = vec3(0.15, 0.20, 0.31);      // #25344f
uniform float band_turquoise = 5.0;   // vertical depth (m) where shallow -> turquoise completes
uniform float band_teal = 20.0;
uniform float band_navy = 60.0;

uniform vec3 sky_zenith : source_color = vec3(0.56, 0.65, 0.75);    // #8ea5be
uniform vec3 sky_horizon : source_color = vec3(0.73, 0.68, 0.75);   // #b9aebf pink haze
uniform float reflect_amount : hint_range(0.0, 1.0) = 0.8;
uniform float fresnel_power = 5.0;
uniform float fresnel_bias : hint_range(0.0, 0.2) = 0.03;

uniform float wave_a_metres = 0.9;
uniform float wave_b_metres = 6.5;
uniform vec2 wave_a_dir = vec2(1.0, 0.3);
uniform vec2 wave_b_dir = vec2(-0.4, 1.0);
uniform float wave_speed = 0.06;
uniform float wave_strength : hint_range(0.0, 1.0) = 0.35;

uniform vec3 foam_color : source_color = vec3(0.90, 0.89, 0.84);    // #e6e2d7
uniform float foam_depth = 1.3;        // foam where vertical depth < this (m)
uniform float foam_noise_metres = 4.0;
uniform float foam_opacity : hint_range(0.0, 1.0) = 0.75;
uniform float whitecap_threshold : hint_range(0.5, 1.0) = 0.94;

uniform float alpha_shallow : hint_range(0.0, 1.0) = 0.35;
uniform float alpha_deep_depth = 6.0;  // fully opaque beyond this vertical depth
uniform float roughness_value : hint_range(0.0, 1.0) = 0.18;
uniform int debug_depth = 0;   // 1 = output vertical depth / 10 as greyscale

varying vec3 wpos;

float linear_depth_from_buffer(vec2 suv, mat4 inv_proj) {
	float d = texture(depth_tex, suv).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(suv * 2.0 - 1.0, d * 2.0 - 1.0);    // OpenGL: depth 0..1 -> NDC -1..1, no reverse-Z
#else
	vec3 ndc = vec3(suv * 2.0 - 1.0, d);                // Vulkan/D3D/Metal: reverse-Z, NDC z 0..1
#endif
	vec4 v = inv_proj * vec4(ndc, 1.0);
	return -v.z / v.w;                                    // metres in front of the camera
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// ---------- water thickness along the view ray, then vertical depth ----------
	float scene_d = linear_depth_from_buffer(SCREEN_UV, INV_PROJECTION_MATRIX);
	float surf_d = -VERTEX.z;                             // this fragment's linear depth
	float thick = max(scene_d - surf_d, 0.0);             // metres of water along the ray
	vec3 up_view = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	float cos_v = abs(dot(normalize(VERTEX), up_view));   // ray steepness
	float vdepth = thick * max(cos_v, 0.08);              // approx vertical depth for a flat sea

	// ---------- moving normals ----------
	vec2 ta = wpos.xz / wave_a_metres + normalize(wave_a_dir) * TIME * wave_speed * 4.0;
	vec2 tb = wpos.xz / wave_b_metres + normalize(wave_b_dir) * TIME * wave_speed;
	vec3 na = texture(normal_a, ta).xyz * 2.0 - 1.0;
	vec3 nb = texture(normal_b, tb).xyz * 2.0 - 1.0;
	vec3 tn = normalize(vec3((na.xy + nb.xy) * wave_strength, 1.0));  // tangent space, z up
	vec3 wn = normalize(vec3(tn.x, tn.z, tn.y));          // plane's up is world +y
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);

	// ---------- depth colour bands ----------
	vec3 col = mix(col_shallow, col_turquoise, smoothstep(0.0, band_turquoise, vdepth));
	col = mix(col, col_teal, smoothstep(band_turquoise, band_teal, vdepth));
	col = mix(col, col_navy, smoothstep(band_teal, band_navy, vdepth));

	// ---------- fresnel sky reflection (no SSR): reflect the view ray off the perturbed normal ----------
	vec3 view_w = normalize((INV_VIEW_MATRIX * vec4(normalize(VERTEX), 0.0)).xyz);
	vec3 refl = reflect(view_w, wn);
	vec3 sky = mix(sky_horizon, sky_zenith, smoothstep(0.0, 0.5, refl.y));
	float ndv = clamp(dot(NORMAL, normalize(-VERTEX)), 0.0, 1.0);
	float fres = fresnel_bias + (1.0 - fresnel_bias) * pow(1.0 - ndv, fresnel_power);
	col = mix(col, sky, fres * reflect_amount);

	// ---------- foam: shoreline ring from depth + scrolling noise, plus sparse whitecaps ----------
	float fn = texture(foam_noise, wpos.xz / foam_noise_metres + vec2(TIME * 0.03, -TIME * 0.02)).r;
	float fn2 = texture(foam_noise, wpos.xz / (foam_noise_metres * 2.7) + vec2(-TIME * 0.015, TIME * 0.01)).r;
	float shore = 1.0 - smoothstep(0.0, foam_depth, vdepth);
	// noise-broken ring: solid only in the last ~30 cm, lace-like further out
	float foam = smoothstep(0.62, 0.85, shore * 0.45 + fn * 0.45 + fn2 * 0.25) * shore;
	float caps = smoothstep(whitecap_threshold, 1.0, fn2 * 0.6 + fn * 0.5) * smoothstep(3.0, 12.0, vdepth);
	foam = clamp(foam + caps * 0.7, 0.0, 1.0) * foam_opacity;
	col = mix(col, foam_color, foam);

	if (debug_depth == 1) { col = vec3(vdepth / 10.0); }
	ALBEDO = col;
	ALPHA = clamp(mix(alpha_shallow, 1.0, smoothstep(0.0, alpha_deep_depth, vdepth)) + foam, 0.0, 1.0);
	ROUGHNESS = mix(roughness_value, 0.9, foam);
	SPECULAR = 0.5;
	METALLIC = 0.0;
}
```

Setup (from `tech_test.gd::_build_water`): the normal maps and the foam noise are generated at
runtime with `NoiseTexture2D` (`seamless = true`, `as_normal_map = true`, `bump_strength` 4–6,
256²) — no asset needed, and they generate on a thread (first frame or two the water is flat; in
the sandbox 4 frames were enough). The sea is one `PlaneMesh` 2000×2000 at `y = 0`,
`cast_shadow OFF`.

```gdscript
func _build_water() -> void:
	var sh := load("res://tech/water.gdshader") as Shader
	var mat := ShaderMaterial.new()
	mat.shader = sh
	var na := NoiseTexture2D.new()
	na.width = 256; na.height = 256
	na.seamless = true
	na.as_normal_map = true
	na.bump_strength = 6.0
	var fa := FastNoiseLite.new(); fa.seed = 3; fa.frequency = 0.02
	fa.fractal_octaves = 4
	na.noise = fa
	var nb := NoiseTexture2D.new()
	nb.width = 256; nb.height = 256
	nb.seamless = true
	nb.as_normal_map = true
	nb.bump_strength = 4.0
	var fb := FastNoiseLite.new(); fb.seed = 9; fb.frequency = 0.012
	fb.fractal_octaves = 3
	nb.noise = fb
	var fo := NoiseTexture2D.new()
	fo.width = 256; fo.height = 256
	fo.seamless = true
	var fc := FastNoiseLite.new(); fc.seed = 17; fc.frequency = 0.03
	fc.fractal_octaves = 4
	fo.noise = fc
	mat.set_shader_parameter("normal_a", na)
	mat.set_shader_parameter("normal_b", nb)
	mat.set_shader_parameter("foam_noise", fo)
	mat.set_shader_parameter("debug_depth", water_debug)
	var pm := PlaneMesh.new()
	pm.size = Vector2(2000, 2000)
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.material_override = mat
	mi.position = Vector3(0.0, 0.0, 0.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
```

### 3.3 Combining with the project's height-map approach

`world_kit._build_sea` currently samples `sea_depth.png`. Both can coexist: use the depth texture
for everything within ~300 m (foam hugs placed rocks automatically — that is the big win, no
obstacle textures or uniform arrays needed) and fall back to the height-map depth when
`scene_d` hits the far plane (sky) or beyond the Terrain3D draw distance. Cheapest way: keep the
height-map uniform and `vdepth = min(vdepth_from_depth, vdepth_from_heightmap)` — untested but a
one-line change.

### 3.4 Caveats

- MSAA + depth texture in Compatibility: the depth blit comes from the resolved FBO; it should work
  but was **not tested** (sandbox has `msaa_3d = 0`). If the project enables MSAA, re-run the
  `--waterdebug` render first.
- The reconstruction assumes a perspective camera; orthographic needs the `#else`-style handling.
- Everything under the water plane that is *not* opaque (transparent grass cards, glow) is invisible
  to the depth test → keep shoreline grass out of the water.
- Each frame with a depth-texture user costs one full-resolution depth blit; that is fine, but
  don't give a dozen materials `hint_depth_texture` — the blit happens once regardless, the point
  is the forced transparent pass and lost early-Z for each such material.

---

## 4. Procedural stratified rock meshes (`/root/t3dtest/tech/rockgen.gd`)

### 4.1 Approach chosen (and why not marching cubes)

Displaced **rounded box**: a 6-face grid (cell 0.6 m at LOD0, 1.8 m at LOD1) is mapped onto a
rounded box (bevel radius `r` via the SDF trick `q = clamp(p, -(h-r), h-r); p' = q + r·normalize(p-q)`),
then each vertex is pushed along its *box-face* normal by:

1. **bedding recess** — in world space (`bed_origin_y`, `bed_tilt`, `bed_height`), every other bed
   is inset by `bed_inset` on side faces, with the top 35 % of the soft bed curling in further so the
   hard bed above overhangs it (undercut shadow band);
2. **joints** — grooves `joint_depth` deep at world `x`/`z` multiples of `joint_spacing` (so joints
   also line up across neighbouring pieces, and cracks run over the top face);
3. **noise** — `FastNoiseLite` simplex-smooth, form (`noise_metres 6`, ±0.35 m) + detail
   (`1.2 m`, ±0.08 m), *sampled in world space* so LOD0/LOD1 and adjacent blocks agree.

Then **crease-angle normals**: per corner, average the area-weighted face normals of the adjacent
triangles whose normal is within `crease_deg` (28°) of the corner's own face — smooth across the
bevels and noise, crisp at bedding steps and joint edges. And **vertex AO** (see 4.2). Output is an
unindexed `ArrayMesh` with `ARRAY_VERTEX/NORMAL/COLOR`.

Marching cubes / voxels were rejected: for 6–15 m blocks with 0.5 m features you need a 30³+ field
per piece plus a mesher — far slower in GDScript and it produces the blobby silhouettes the art
research complains about. The box keeps the stepped skyline. `boulder = true` switches to a big bevel
(45 % of the smallest extent) and no beds/joints → rounded talus boulders from the same code.

Arches and overhangs are compositions: pillar + pillar + lintel (three `make_rock` calls with the
same `bed_origin_y`), the lintel with `concave = true` collision (trimesh) since the road goes
through it.

### 4.2 Vertex-colour cavity/AO (cheap, no rays)

Per unique vertex, product of four heuristics, written to `COLOR.r` (1 = open):

- (a) **concavity** — `dot(mean(neighbour triangle centroids) − p, n) / (0.35·cell)`, clamped; a
  vertex whose neighbours sit above its tangent plane is in a hollow → up to −50 %;
- (b) **contact** — `lerp(0.5, 1, smoothstep(0, 1 m, y − ground_y))` when `ground_y` is given;
- (c) **undersides** — `lerp(0.5, 1, smoothstep(−1, 0.3, n.y))`, overhang ceilings get less sky;
- (d) **under-bed** — top 0.6 m of a recessed soft bed → 0.65.

`COLOR.g` = ledge mask (up-facing vertex at the top of a hard bed with a recessed bed above — the
places to emit scrub cards; the local positions are also returned as `ledge_points`),
`COLOR.b` = height-above-ground 0..1 (for a sand-tint blend in the shader if wanted).
A hemisphere-ray self-occlusion pass was tried on paper and dropped: (a)+(d) already darken every
joint and undercut, and the reference's strongest darkening is the contact one (b).

### 4.3 LOD and collision

`build_node()` returns `Node3D` → `MeshInstance3D` LOD0 (`visibility_range_end = 90 m`, fade
**disabled** — fade puts the mesh into the alpha pass in Compatibility), `MeshInstance3D` LOD1
(`visibility_range_begin = 90 m`), `StaticBody3D` with either a `ConvexPolygonShape3D` built from
LOD1's unique vertices (boulders, slabs; Godot computes the hull) or `mesh_lod1.create_trimesh_shape()`
for concave pieces you drive under. LOD1 is 6–7× fewer triangles (27 152 → 4 112 for the 21-piece
test set).

### 4.4 Measured

| Run | Pieces | LOD0 tris | LOD1 tris | Time |
|---|---|---|---|---|
| `--rocks=30` headless | 36 (6 wall slabs + 30 boulders) | 41 448 | 6 984 | 210 ms (5.8 ms/rock) |
| `--rocks=14` GL | 21 | 27 152 | 4 112 | 131–188 ms |

A 14×7×6 m slab at cell 0.6 = ~2 600 tris; a 3 m boulder at cell 0.4 = ~1 200 tris. Budget:
~1 000 hero pieces → ~2.5 M tris LOD0 total, of which the LOD ranges keep < 300 k on screen. If the
generator has to run inside the 20 s world budget for hundreds of pieces, it is ~6 s per 1 000 at
this size — do it per streamed chunk (as props already are) or in a `WorkerThreadPool` task
(everything in `RockGen` is pure data; only `add_child` must happen on the main thread).

```gdscript
## Procedural stratified limestone blocks (Godot 4.7, pure GDScript, no editor needed).
##
## Shape recipe: a subdivided box -> rounded-box (bevel) mapping -> bedding recess on alternate beds
## (world-space strata origin so beds carry across pieces) -> vertical joint grooves -> two-octave
## FastNoiseLite displacement along the box-face normal. Then crease-angle normals (smooth inside the
## angle, crisp across it) and a per-vertex cavity/AO bake into COLOR (r = AO 0..1, g = ledge mask,
## b = height-above-ground 0..1) for the rock shader.
##
## Usage:
##   var r := RockGen.make_rock({"size": Vector3(8,4,3), "seed": 7, "origin": Vector3(x,y,z)})
##   r.mesh (ArrayMesh, LOD0)  r.mesh_lod1 (ArrayMesh)  r.tris  r.tris_lod1  r.hull (PackedVector3Array)
##   var node := RockGen.build_node(r, Vector3(x,y,z), Basis(), false)   # adds LODs + collision
class_name RockGen
extends RefCounted

const DEFAULTS := {
	"size": Vector3(8.0, 4.0, 3.0),   # full extents (m)
	"seed": 1,
	"origin": Vector3.ZERO,           # world position of the rock centre (for strata / joints / ground)
	"cell": 0.6,                      # target grid cell size at LOD0 (m)
	"cell_lod1": 1.8,
	"bevel": 0.5,                     # edge rounding radius (m)
	"bed_height": 4.0,                # metres between bedding planes (match shader bed_height)
	"bed_tilt": 0.08,                 # dy per metre of x (match shader bed_tilt)
	"bed_origin_y": 0.0,              # world y of a bedding plane (match shader bed_origin_y)
	"bed_inset": 0.6,                 # soft beds recessed by this much (m)
	"joint_spacing": 6.0,             # vertical joints every N metres (world x and z)
	"joint_depth": 0.3,
	"joint_width": 0.5,
	"noise_amp": 0.35,                # low-frequency form noise (m)
	"noise_metres": 6.0,
	"detail_amp": 0.08,               # high-frequency surface noise (m)
	"detail_metres": 1.2,
	"crease_deg": 28.0,               # normals are smoothed only across edges flatter than this
	"ground_y": -1000.0,              # world y of the ground under the rock (contact AO); -1000 = none
	"boulder": false,                 # true = rounded talus boulder: big bevel, no beds/joints
}


static func make_rock(p_in: Dictionary) -> Dictionary:
	var p := DEFAULTS.duplicate()
	for k in p_in:
		p[k] = p_in[k]
	if p.boulder:
		p.bevel = min(p.size.x, p.size.y, p.size.z) * 0.45
		p.bed_inset = 0.0
		p.joint_depth = 0.0
	var t0 := Time.get_ticks_usec()
	var lod0 := _build(p, float(p.cell))
	var lod1 := _build(p, float(p.cell_lod1))
	return {
		"mesh": lod0.mesh, "tris": lod0.tris,
		"mesh_lod1": lod1.mesh, "tris_lod1": lod1.tris,
		"hull": lod1.unique_positions,
		"ledge_points": lod0.ledge_points,     # local-space up-facing bedding-step vertices (for scrub)
		"usec": Time.get_ticks_usec() - t0,
	}


## Wraps the result in a Node3D: LOD0 (0..lod_dist), LOD1 (lod_dist..far), StaticBody3D collision.
## concave=true builds a trimesh from LOD1 (needed for arches / overhangs you drive under),
## otherwise a convex hull of LOD1 (cheap, fine for boulders and slabs).
static func build_node(r: Dictionary, pos: Vector3, basis: Basis, concave: bool, mat: Material = null,
		lod_dist: float = 90.0, far: float = 0.0) -> Node3D:
	var root := Node3D.new()
	root.transform = Transform3D(basis, pos)
	var m0 := MeshInstance3D.new()
	m0.mesh = r.mesh
	m0.visibility_range_end = lod_dist
	m0.visibility_range_end_margin = 6.0
	m0.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED  # fade costs an alpha pass in Compat
	var m1 := MeshInstance3D.new()
	m1.mesh = r.mesh_lod1
	m1.visibility_range_begin = lod_dist
	m1.visibility_range_begin_margin = 6.0
	m1.visibility_range_end = far
	if mat:
		m0.material_override = mat
		m1.material_override = mat
	root.add_child(m0)
	root.add_child(m1)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	if concave:
		cs.shape = r.mesh_lod1.create_trimesh_shape()
	else:
		var hull := ConvexPolygonShape3D.new()
		hull.points = r.hull
		cs.shape = hull
	body.add_child(cs)
	root.add_child(body)
	return root


# ---------------------------------------------------------------------------------------------
static func _build(p: Dictionary, cell: float) -> Dictionary:
	var h: Vector3 = p.size * 0.5
	var origin: Vector3 = p.origin
	var bevel: float = p.bevel
	var bed_height: float = p.bed_height
	var bed_tilt: float = p.bed_tilt
	var bed_origin_y: float = p.bed_origin_y
	var bed_inset: float = p.bed_inset
	var joint_spacing: float = p.joint_spacing
	var joint_depth: float = p.joint_depth
	var joint_width: float = p.joint_width
	var noise_amp: float = p.noise_amp
	var detail_amp: float = p.detail_amp
	var ground_y: float = p.ground_y
	var noise := FastNoiseLite.new()
	noise.seed = p.seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 1.0 / p.noise_metres
	var detail := FastNoiseLite.new()
	detail.seed = p.seed + 1
	detail.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	detail.frequency = 1.0 / p.detail_metres
	var rng := RandomNumberGenerator.new()
	rng.seed = p.seed
	var bed_phase: int = rng.randi() % 2   # which beds are the soft (recessed) ones

	# ---- 1. grid on 6 faces, welded by position ----
	var positions := PackedVector3Array()
	var box_normals := PackedVector3Array()   # unbeveled face normal per unique vertex (for displacement)
	var index_of := {}                        # quantised position -> unique index
	var tris := PackedInt32Array()
	var axes := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	for a in 3:
		var n_axis: Vector3 = axes[a]
		var u_axis: Vector3 = axes[(a + 1) % 3]
		var v_axis: Vector3 = axes[(a + 2) % 3]
		var nu := maxi(2, int(ceil(2.0 * h.dot(u_axis) / cell)))
		var nv := maxi(2, int(ceil(2.0 * h.dot(v_axis) / cell)))
		for side in [1.0, -1.0]:
			var face_n: Vector3 = n_axis * side
			var grid := PackedInt32Array()
			grid.resize((nu + 1) * (nv + 1))
			for j in nv + 1:
				for i in nu + 1:
					var fu := (float(i) / nu) * 2.0 - 1.0
					var fv := (float(j) / nv) * 2.0 - 1.0
					var cube: Vector3 = face_n + u_axis * fu + v_axis * fv          # point on the unit cube
					var pt := _rounded_box(cube * h, h, bevel)
					var key := Vector3i((pt * 200.0).round())
					var idx: int
					if index_of.has(key):
						idx = index_of[key]
					else:
						idx = positions.size()
						index_of[key] = idx
						positions.push_back(pt)
						box_normals.push_back(face_n)
					grid[j * (nu + 1) + i] = idx
			for j in nv:
				for i in nu:
					var a0 := grid[j * (nu + 1) + i]
					var a1 := grid[j * (nu + 1) + i + 1]
					var a2 := grid[(j + 1) * (nu + 1) + i + 1]
					var a3 := grid[(j + 1) * (nu + 1) + i]
					if side > 0.0:
						tris.append_array([a0, a2, a1, a0, a3, a2])
					else:
						tris.append_array([a0, a1, a2, a0, a2, a3])

	# ---- 2. displace: bedding recess, joints, noise ----
	var soft_flags := PackedByteArray()
	soft_flags.resize(positions.size())
	for i in positions.size():
		var lp := positions[i]
		var wp := lp + origin
		var bn := box_normals[i]
		var horiz := Vector3(bn.x, 0.0, bn.z)
		var d := 0.0
		# bedding: alternate beds recessed inward on side faces
		var yb: float = (wp.y - bed_origin_y + wp.x * bed_tilt) / bed_height
		var bed_i := int(floor(yb))
		var soft := (posmod(bed_i + bed_phase, 2) == 0)
		soft_flags[i] = 1 if soft else 0
		if soft and bed_inset > 0.0 and horiz.length() > 0.5:
			var fr: float = yb - floor(yb)
			# soft bed recessed, with its top rounding into the hard bed above (undercut look)
			d -= bed_inset * (0.6 + 0.4 * smoothstep(0.0, 0.35, fr))
		# vertical joints (grooves) at world x / z multiples of joint_spacing
		if joint_depth > 0.0:
			var jx := absf(fposmod(wp.x + joint_spacing * 0.5, joint_spacing) - joint_spacing * 0.5)
			var jz := absf(fposmod(wp.z + joint_spacing * 0.5, joint_spacing) - joint_spacing * 0.5)
			var g := maxf(1.0 - smoothstep(0.0, joint_width, jx), 1.0 - smoothstep(0.0, joint_width, jz))
			d -= joint_depth * g
		# form + detail noise (world-space, so LODs and neighbours agree)
		d += noise.get_noise_3dv(wp) * noise_amp
		d += detail.get_noise_3dv(wp) * detail_amp
		positions[i] = lp + bn * d

	# ---- 3. face normals, adjacency ----
	var ntri := tris.size() / 3
	var fnorm := PackedVector3Array()
	fnorm.resize(ntri)
	var farea := PackedFloat32Array()
	farea.resize(ntri)
	var adj := []                              # per vertex: PackedInt32Array of triangle ids
	adj.resize(positions.size())
	for i in positions.size():
		adj[i] = PackedInt32Array()
	for t in ntri:
		var i0 := tris[t * 3]; var i1 := tris[t * 3 + 1]; var i2 := tris[t * 3 + 2]
		var c := (positions[i1] - positions[i0]).cross(positions[i2] - positions[i0])
		var l := c.length()
		fnorm[t] = c / l if l > 1e-9 else Vector3.UP
		farea[t] = l
		adj[i0].push_back(t); adj[i1].push_back(t); adj[i2].push_back(t)

	# ---- 4. smooth normals (all-adjacent, used by the AO bake) + AO per unique vertex ----
	var snorm := PackedVector3Array()
	snorm.resize(positions.size())
	var ao := PackedFloat32Array()
	ao.resize(positions.size())
	var ledge := PackedFloat32Array()
	ledge.resize(positions.size())
	var ledge_points := PackedVector3Array()
	var cos_crease := cos(deg_to_rad(p.crease_deg))
	for i in positions.size():
		var nsum := Vector3.ZERO
		var csum := Vector3.ZERO
		var cnt := 0
		for t in adj[i]:
			nsum += fnorm[t] * farea[t]
			# neighbour centroid (concavity probe)
			csum += (positions[tris[t * 3]] + positions[tris[t * 3 + 1]] + positions[tris[t * 3 + 2]]) / 3.0
			cnt += 1
		var sn := nsum.normalized() if nsum.length() > 1e-9 else box_normals[i]
		snorm[i] = sn
		var wp := positions[i] + origin
		# (a) concavity: neighbours sitting "above" the tangent plane => this vertex is in a hollow
		var conc := 0.0
		if cnt > 0:
			conc = clampf(((csum / cnt) - positions[i]).dot(sn) / (cell * 0.35), 0.0, 1.0)
		var ao_c := 1.0 - conc * 0.5
		# (b) height above ground: contact shadow, 0.5 at the ground, full at 1 m
		var ao_h := 1.0
		if ground_y > -999.0:
			ao_h = lerpf(0.5, 1.0, smoothstep(0.0, 1.0, wp.y - ground_y))
		# (c) undersides (overhangs) get less sky
		var ao_d := lerpf(0.5, 1.0, smoothstep(-1.0, 0.3, sn.y))
		# (d) just under a hard bed (top 0.6 m of a recessed soft bed)
		var ao_b := 1.0
		if soft_flags[i] == 1 and bed_inset > 0.0:
			var yb: float = (wp.y - bed_origin_y + wp.x * bed_tilt)
			var to_top: float = bed_height - fposmod(yb, bed_height)
			ao_b = lerpf(0.65, 1.0, smoothstep(0.0, 0.6, to_top))
		ao[i] = clampf(ao_c * ao_h * ao_d * ao_b, 0.0, 1.0)
		# ledge mask: up-facing vertex that belongs to the top of a hard bed with a recessed soft bed above
		var is_ledge := 0.0
		if sn.y > 0.6 and soft_flags[i] == 0 and bed_inset > 0.0:
			var yb2: float = (wp.y - bed_origin_y + wp.x * bed_tilt)
			if bed_height - fposmod(yb2, bed_height) < cell * 1.5:
				is_ledge = 1.0
		ledge[i] = is_ledge
		if is_ledge > 0.5:
			ledge_points.push_back(positions[i])

	# ---- 5. crease-angle corner normals, unindexed output ----
	var out_v := PackedVector3Array()
	var out_n := PackedVector3Array()
	var out_c := PackedColorArray()
	out_v.resize(ntri * 3); out_n.resize(ntri * 3); out_c.resize(ntri * 3)
	for t in ntri:
		var fn := fnorm[t]
		for k in 3:
			var vi := tris[t * 3 + k]
			var nsum := Vector3.ZERO
			for t2 in adj[vi]:
				if fnorm[t2].dot(fn) >= cos_crease:
					nsum += fnorm[t2] * farea[t2]
			var o := t * 3 + k
			out_v[o] = positions[vi]
			out_n[o] = nsum.normalized() if nsum.length() > 1e-9 else fn
			var hgt := 1.0
			if ground_y > -999.0:
				hgt = clampf((positions[vi].y + origin.y - ground_y) / 1.5, 0.0, 1.0)
			out_c[o] = Color(ao[vi], ledge[vi], hgt, 1.0)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = out_v
	arrays[Mesh.ARRAY_NORMAL] = out_n
	arrays[Mesh.ARRAY_COLOR] = out_c
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return {"mesh": mesh, "tris": ntri, "unique_positions": positions, "ledge_points": ledge_points}


## Maps a point on the surface of box `h` (half extents) to the surface of the same box with
## edges/corners rounded by radius r. Flat interiors are unchanged.
static func _rounded_box(pt: Vector3, h: Vector3, r: float) -> Vector3:
	r = minf(r, minf(h.x, minf(h.y, h.z)) * 0.95)
	var inner := h - Vector3(r, r, r)
	var q := pt.clamp(-inner, inner)
	var d := pt - q
	if d.length() < 1e-6:
		return pt
	return q + d.normalized() * r
```

Usage as run in the sandbox (`tech_test.gd::_build_rocks`, abbreviated):

```gdscript
var r := RockGen.make_rock({
	"size": Vector3(14, 8, 7), "seed": 100, "origin": pos,
	"bed_height": 3.5, "bed_tilt": 0.06, "bed_origin_y": 0.5, "bed_inset": 0.7,
	"joint_spacing": 5.5, "joint_depth": 0.35, "bevel": 0.6,
	"ground_y": terrain.height_at(pos.x, pos.z),
})
add_child(RockGen.build_node(r, pos, Basis(), false, rock_mat))       # convex collision
# boulders:
RockGen.make_rock({"size": Vector3(3.2, 2.1, 2.8), "seed": k, "origin": pos, "boulder": true,
	"cell": 0.4, "cell_lod1": 1.0, "noise_amp": 0.25, "noise_metres": 2.5, "ground_y": gy})
```

---

## 5. Importing the Quaternius trees and recolouring the leaves

### 5.1 Two ways to load, both verified

**(a) Editor import, `load()`** — copy `TwistedTree_1.gltf` + `.bin` + the three PNGs it
references (`Bark_TwistedTree.png`, `Bark_TwistedTree_Normal.png`, `Leaves_TwistedTree_C.png`)
into `res://assets/models/`, run `godot --headless --path . --import` once (or open the editor).
Then `load("res://assets/models/TwistedTree_1.gltf")` returns a `PackedScene`. This is what
exports use (the exporter ships the imported `.scn` and remaps the path). The `.gltf` files use
*separate* `.bin`/PNG files, so all of them must be copied together; the pack has no `.glb`.

**(b) Runtime `GLTFDocument`** — no import step, works from `res://`, `user://` or an absolute
path, works in exports (the gltf module is always compiled in):

```gdscript
var doc := GLTFDocument.new()
var state := GLTFState.new()
if doc.append_from_file("res://assets/models/Pine_1.gltf", state) == OK:
	var tree := doc.generate_scene(state)     # Node3D with MeshInstance3D children
```

Runtime loading is slower (parses, builds materials, uploads textures on the main thread — the
9.5 k-tri TwistedTree took well under a frame in the sandbox, not measured precisely) and produces
`StandardMaterial3D`s exactly like the importer. Use (a) for the kit, (b) only if trees must come from
outside the pack.

Both give: `TwistedTree_1` = 1 `MeshInstance3D`, 2 surfaces (bark 21 636 idx / 7 212 tris + leaves
7 056 idx / 2 352 tris — 9 564 tris total), materials named `Bark_TwistedTree` and
`Leaves_TwistedTree` (`alphaMode MASK`, cutoff 0.2, double-sided → the importer sets
`transparency = ALPHA_SCISSOR`). `Pine_1` = 3 947 tris, materials `Bark_NormalTree` / `Leaves_Pine`.

### 5.2 Recolouring the leaves

The leaf atlases are **flat single-colour silhouettes** with alpha (measured: every opaque texel of
`Leaves_TwistedTree_C.png` is `#a71717`, of `Leaf_Pine_C.png` `#335800`; ~29 % coverage). So
`albedo_color` multiplication cannot turn red into green — replace the material. The verified way is
a small leaf `ShaderMaterial` that uses only the atlas alpha and paints the colour from an
object-space top-lit gradient (this is also the "baked gradient instead of lighting" the art
research asks for):

```glsl
// Leaf cards for imported Quaternius trees — Compatibility. Uses the atlas alpha only and paints the
// colour from a baked top-lit gradient (object-space height) so the flat red/green atlas colours are
// ignored. Alpha scissor = one opaque pass, no sorting (cheapest transparency in Compat).
shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;

uniform sampler2D leaf_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 col_dark : source_color = vec3(0.18, 0.24, 0.20);   // #2f3d33 canopy underside
uniform vec3 col_lit : source_color = vec3(0.35, 0.42, 0.29);    // #5a6b4a lit top
uniform float y_bottom = 2.0;
uniform float y_top = 16.0;
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.35;
uniform float hue_jitter : hint_range(0.0, 0.2) = 0.05;

varying float grad;
varying float jit;

void vertex() {
	grad = clamp((VERTEX.y - y_bottom) / max(y_top - y_bottom, 0.01), 0.0, 1.0);
	// per-instance jitter from the world position (MultiMesh / duplicated trees differ)
	vec3 wp = MODEL_MATRIX[3].xyz;
	jit = fract(sin(dot(wp.xz, vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
}

void fragment() {
	vec4 t = texture(leaf_tex, UV);
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	vec3 c = mix(col_dark, col_lit, grad * grad);
	c *= 1.0 + jit * 0.3;
	c.r += jit * hue_jitter; c.b -= jit * hue_jitter * 0.5;
	ALBEDO = max(c, vec3(0.0));
	ROUGHNESS = 1.0;
}
```

```gdscript
func _build_trees() -> void:
	# (a) editor-imported scene: works after `godot --headless --import` (or opening the project once)
	var ps := load("res://tech/models/TwistedTree_1.gltf")
	if ps is PackedScene:
		var t := (ps as PackedScene).instantiate()
		t.position = Vector3(-8.0, _ground_y(-8.0), 10.0)
		t.scale = Vector3(0.6, 0.6, 0.6)
		add_child(t)
		_recolour_leaves(t, "Leaves_TwistedTree")
		print("[tech] tree via load(): ", _describe(t))
	else:
		print("[tech] tree via load() FAILED (not imported?)")
	# (b) runtime GLTF loading — no import step, works in exports and from user:// paths
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file("res://tech/models/Pine_1.gltf", state)
	if err == OK:
		var t2 := doc.generate_scene(state)
		t2.position = Vector3(2.0, _ground_y(2.0), 12.0)
		add_child(t2)
		_recolour_leaves(t2, "Leaves_Pine")
		print("[tech] tree via GLTFDocument: ", _describe(t2))
	else:
		print("[tech] GLTFDocument FAILED: ", err)


func _describe(n: Node) -> String:
	var out := []
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m: Mesh = mi.mesh
		var tris := 0
		for s in m.get_surface_count():
			var arr := m.surface_get_arrays(s)
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			tris += (idx.size() if idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
		var mats := []
		for s in m.get_surface_count():
			var mat: Material = mi.get_active_material(s)
			mats.append("%s:%s" % [mat.resource_name if mat else "-", mat.get_class() if mat else "-"])
		out.append("%s %d tris %s" % [mi.name, tris, mats])
	return ", ".join(out)


## Replace the named leaf material with an umbrella-pine leaf shader (dark, desaturated, top-lit).
func _recolour_leaves(root: Node, mat_name: String) -> void:
	var sh := load("res://tech/leaf.gdshader") as Shader
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m: Mesh = mi.mesh
		for s in m.get_surface_count():
			var mat: Material = mi.get_active_material(s)
			if mat == null or mat.resource_name != mat_name:
				continue
			var leaf := ShaderMaterial.new()
			leaf.shader = sh
			var src := mat as BaseMaterial3D
			leaf.set_shader_parameter("leaf_tex", src.albedo_texture)   # keep the atlas alpha
			leaf.set_shader_parameter("col_dark", Color("2f3d33"))
			leaf.set_shader_parameter("col_lit", Color("5a6b4a"))
			var aabb := m.get_aabb()
			leaf.set_shader_parameter("y_bottom", aabb.position.y)
			leaf.set_shader_parameter("y_top", aabb.end.y)
			mi.set_surface_override_material(s, leaf)
```

Result in `shots/tech_final_1280.png`: both trees dark, desaturated green with a lit top and
dark underside; the bark keeps the imported PBR material. For a flatter umbrella-pine silhouette use
`TwistedTree_*` scaled 0.6 and set `y_bottom` to ~40 % of the AABB so the whole lower crown reads as
shadow; or prune leaf cards by y in the imported mesh (`surface_get_arrays`, filter triangles,
`add_surface_from_arrays`) — not done here.

Alternative without a shader (untested but straightforward): build a recoloured atlas once at
startup with `Image` — since the RGB is flat, `img.convert(FORMAT_RGBA8)` then
`img.adjust_bcs()`/`Image.fill`-style tricks don't preserve alpha; you would loop pixels in GDScript
(1 M texels ≈ seconds) — hence the shader.

---

## 6. Performance rules for Compatibility (what the source and docs actually say)

Limits, from `ProjectSettings.xml` (4.7) and `renderers.rst`:

- `rendering/limits/opengl/max_renderable_elements = 65536` **surfaces per frame** (not meshes;
  a rock with LOD0+LOD1 visible during the margin = 2). `max_renderable_lights = 32` positional
  lights per frame, `max_lights_per_object = 8` omni + 8 spot per surface. Only 1 directional light
  with shadows is sane: *"lights with shadows use a multi-pass approach"* — every shadowed light is
  an additional pass over all lit geometry. ReflectionProbes: 2 per mesh.
- **MultiMesh** works (verified: 150 scree stones, `use_colors = true`, per-instance transform +
  colour read by the rock shader as `COLOR`). Rules: a MultiMesh is *one* object — no per-instance
  frustum culling, one `visibility_range`, the 8-light limit applies to the whole thing, and
  `Mesh` LODs are not used by MultiMeshes. So keep one MultiMesh per 60 m chunk per mesh type (which
  the streamed-chunk design already does), and cap instances per chunk rather than per island.
  `visible_instance_count` can shrink the draw without rebuilding. Terrain3D's instancer is a
  MultiMesh per region per asset — same rules.
- **Alpha scissor vs blend** (from `_geometry_instance_add_surface_with_material`): a material with
  `ALPHA_SCISSOR_THRESHOLD` (or `alpha_scissor` in StandardMaterial) is `uses_alpha_clip` → stays in
  the **opaque pass, writes depth, casts shadows, no sorting**. Any `ALPHA` write without scissor,
  `blend_*`, `depth_draw_never`, `hint_screen/depth_texture`, or *visibility range fade* → **alpha
  pass**: sorted back-to-front, no depth write (unless `depth_draw_always`), **no shadow casting**
  (`FLAG_PASS_SHADOW` is only set for opaque and `depth_prepass_alpha` materials). `depth_prepass_alpha`
  gets you shadows + a depth write but the surface is then drawn twice. The cost of scissor cards is
  overdraw + `discard` disabling early-Z; mitigations that matter in Compat: keep card quads tight
  around the silhouette (~30 % coverage atlases like Quaternius' waste 70 % of the fill), use 2–3
  crossed cards not 6, and lean on `rendering/driver/depth_prepass/enable` (default **true** on
  desktop, auto-disabled for PowerVR/Mali/Adreno/Apple) which makes the opaque colour pass skip
  hidden fragments — grass behind a boulder costs almost nothing.
- **Shadow atlas**: directional shadow map is a single texture `directional_shadow/size` (4096
  default, rounded to a power of two) split into 1/2/4 quadrants for PSSM; positional lights share
  `positional_shadow/atlas_size` (4096) with the usual quadrant subdivision settings — the island has
  none at day, keep it that way (each shadowed omni = 6 cubemap passes). Softness = filter quality
  project setting (5/13-tap PCF), not `shadow_blur` (§1.2). Use `16_bits = true` (default) — it is
  faster, the biases above handle acne; `directional_shadow_max_distance` 250–300 m with `fade_start
  0.8`; nothing beyond that needs a shadow because fog has eaten the contrast anyway.
- **Post**: glow/adjustments/SSAO each force the "tonemap in post" path (one extra fullscreen pass +
  the 10-bit intermediate). Glow's own cost is a few downsample/blur passes at reduced resolution —
  cheap on a GPU, ~10 % extra on llvmpipe. SSAO is a full-res depth-based pass; leave it off.
- **Vertex lighting**: `rendering/shading/overrides/force_vertex_shading` (or per-material
  `vertex_lighting` render mode) is honoured by Compatibility and is the single biggest fill-rate
  saver for the far LOD of rocks/terrain if ever needed; it breaks the per-pixel normal map, so
  only for LOD1.
- **Fog** is computed in the scene shader per fragment (`fog_process`) — free. The sky's fog pass
  is likewise in the sky shader.
- **Depth texture** (§3.4): one blit per frame when any user is visible; users go to the alpha pass.
- **Materials**: one `ShaderMaterial` shared by all rocks (parameters via uniforms, variation via
  world-space noise and `COLOR`) keeps the shader-variant count and material switches low; each
  distinct shader in Compatibility compiles several GL programs (spec-constant variants: shadows
  yes/no, PCF mode, lightmap, etc.) — the first frame after a new material appears stutters
  (`ubershader` isn't a thing in GLES3), so warm up by drawing every material once at load.
- **MSAA/SSAA**: MSAA 3D works; on llvmpipe both are unaffordable; on a real GPU 2× MSAA is the right
  AA (no FXAA/TAA in Compat).

---

## 7. Open items / not verified

- `Texture3D` LUT colour correction in Compatibility (docs say supported; the 1D gradient path was
  verified instead).
- MSAA + `hint_depth_texture` interaction (§3.4).
- Exact export packaging of the `.gltf` (the sandbox was only run from the project, never exported);
  the importer path is the documented one, so risk is low.
- `WorkerThreadPool` generation of `RockGen` meshes (pure data, should be safe; not exercised).
- The height-map ∧ depth-texture fallback for far water (§3.3), a one-liner, untested.
