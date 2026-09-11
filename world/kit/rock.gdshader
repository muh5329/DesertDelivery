// Stratified limestone rock — Godot 4.7 GL Compatibility (from RESEARCH_tech.md §2, adapted).
// Triplanar albedo + normal in world space (no tangents needed on generated meshes), bedding
// darkening baked by RockGen into COLOR.g (so cached pieces can be reused with any scale/rotation),
// vertex AO in COLOR.r (0 occluded .. 1 open), height-above-ground in COLOR.b (sand dusting at the
// foot), weathered top rim in COLOR.a (darkened: a rim must never read as a bright outline), moss
// only in crevices, macro colour variation from world-space value noise.
// Meshes without a colour array (COLOR = white) simply render as plain, un-occluded rock.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tex_metres = 3.0;            // one texture tile covers this many metres
uniform float normal_strength : hint_range(0.0, 2.0) = 0.8;
uniform float fine_metres = 0.8;          // second normal octave: tile size (m) ...
uniform float fine_normal : hint_range(0.0, 1.0) = 0.15;  // ... and strength, near faces only (r4: 0.4 -> 0.15, the hero wall read as pitting, not planes)
uniform vec3 base_tint : source_color = vec3(0.788, 0.749, 0.682);   // #c9bfae: the mean colour in flat light
uniform float albedo_tex_mean = 0.71;     // mean sRGB value of albedo_tex (Rock019 = 0.71, Rock021 = 0.66); the texture is normalised by it
uniform float triplanar_sharpness : hint_range(1.0, 16.0) = 6.0;

// bedding shade comes baked in COLOR.g; this scales how strong it shows
uniform float bed_strength : hint_range(0.0, 1.5) = 1.0;

// cavity / AO from vertex colour: at COLOR.r == 0 the albedo becomes base_tint * cavity_mul
uniform float ao_min : hint_range(0.0, 1.0) = 0.24;   // r4: 0.28 -> 0.24, the contacts hold the darks now that the sky fill lifts everything else
uniform vec3 ao_warm_tint : source_color = vec3(0.50, 0.46, 0.46); // contacts land near #5c4c4b: cool-neutral, not warm (r2's #6f6659 was too pale and orange)

// hemisphere sky fill on rock only: the reference sky is a huge soft source and every top is the
// palest rock; the global ambient cannot be raised that far (it turned the foliage teal), so the
// rock adds its own upward-weighted sky term as emission (albedo x zenith colour x AO).
uniform vec3 sky_fill_color : source_color = vec3(0.710, 0.737, 0.796);   // #b5bccb S0.10 (r5: tops are cream-grey, the palest rock; r4 #a9b6cf)
uniform float sky_fill : hint_range(0.0, 1.2) = 0.70;   // r5: 0.75 -> 0.85 but weighted to the tops only (sky_w floor 0.35 -> 0.12): the r4 side faces were lit by their own emission (~0.65 x albedo against <= 0.18 x albedo of sun); at el 36 a top gets 0.59 of the sun against a square face's 0.81, so the sky must carry the tops above the lit faces
// the shade side takes a cooler grey-lavender cast (the reference's shade is H221 S0.27): a small
// side-facing lavender term so vertical faces out of the sun are not the flat warm ambient
uniform vec3 shade_fill_color : source_color = vec3(0.42, 0.53, 0.82);   // #6b87d1 (r5: the warm ambient dilutes it, so the fill itself is bluer than the target; the ref shade is #535d73 H215 S0.27 V0.45, v1 at #7f94c7 x 0.35 measured S0.10)
// r4: 0.08 -> 0.30. With the sun ahead of the primary camera (LOOK, yaw -150) the broad faces it sees
// are out of the sun: they must land in the #535d73 class (V 0.42-0.58, S 0.2-0.3), never navy
uniform float shade_fill : hint_range(0.0, 1.0) = 0.50;   // r6: 0.56 -> 0.50 and gated by the sun (item 2, `sun_dir` below): a sun-square face got the full blue fill on top of the direct term and read V0.83 S0.15, chalky. r5: 0.80 -> 0.56: the sun (sun_gain below) carries lit:shade now, the fill only keeps the shade blue and off navy (0.35 left the shade faces at V0.36 S0.10; target V0.40-0.48 S0.2-0.3)

// sand dusting at the foot (COLOR.b = 0 at the ground)
uniform vec3 sand_color : source_color = vec3(0.58, 0.53, 0.45);   // r4: greyer   // the bench sand, in the same key as the rock (0.8/0.7/0.54 clipped on lit boulder feet)
uniform float sand_amount : hint_range(0.0, 1.0) = 0.25;

// moss / scrub on up-facing surfaces
uniform vec3 moss_color : source_color = vec3(0.23, 0.29, 0.21);   // #3b4a35
uniform float moss_amount : hint_range(0.0, 1.0) = 0.10;   // crevices only (ao < 0.5): the tops stay the palest rock
uniform float moss_slope_start = 0.55;     // world normal.y where moss starts
uniform float moss_slope_full = 0.9;

// macro variation
uniform float macro_metres = 16.0;         // wavelength of the patchiness
uniform float macro_value : hint_range(0.0, 0.5) = 0.10;         // +/- luminance
// water streaks: vertical dark runs down side faces
uniform float streak_amount : hint_range(0.0, 1.0) = 0.08;   // narrow runs under the bedding planes, not paint over every face
uniform vec3 macro_rust : source_color = vec3(0.72, 0.63, 0.52);  // #b8a184 warm patches (r4: was #c49a6a, which with the macro mix at 0.5 put S +0.1 on every lit face)
uniform vec3 macro_grey : source_color = vec3(0.69, 0.66, 0.60);  // #b0a89a warm-grey patches (r2 #a8a399 pulled the lit faces grey)
uniform float tex_saturation : hint_range(0.0, 1.0) = 0.45;   // r5: back to 0.45 (with the warmer tint and the real sun, 0.55 put the lit hero wall at S0.36; target 0.20-0.26)
uniform float tex_contrast : hint_range(0.0, 1.5) = 0.42;         // the texture's own light/dark grain, damped       // the texture's own colour, damped: limestone is nearly grey
// fresh-fracture undersides (overhang ceilings, the vault of an arch) are orange, never weathered grey
uniform vec3 fracture_color : source_color = vec3(0.79, 0.60, 0.37);   // #c99a5e
uniform float fracture_amount : hint_range(0.0, 1.0) = 0.4;
uniform float rim_darken : hint_range(0.0, 0.5) = 0.15;    // the weathered top rim (COLOR.a) is this much darker than the fresh face

// rock-only sun response (custom light()): a face square to the 1.6-energy sun clipped to V 0.96
// at any albedo that still left the shade side readable (the environment's lit:shade is ~4:1 in
// linear light, the reference's is 1.6:1 in sRGB), so the direct term is compressed to `sun_gain`
// and wrapped a little (`sun_wrap`), a soft terminator like the reference's. The sky fill above
// then puts the tops within reach of the lit faces.
// (LIGHT_COLOR in light() is not divided by PI as the built-in Lambert is: 0.16 here ~ 0.5 of it)
uniform float sun_gain : hint_range(0.0, 1.5) = 0.14;   // r6: 0.32 -> 0.14 with the knee below: a square face sat at ~2.0 scene-linear (V0.83 through the filmic shoulder), the ref never lights rock above V0.65. r5: 0.13 -> 0.35 under the yaw -40 / el 36 sun: the sun is the main light again (lit:shade target 1.5-2.2, r4 was 1.2)
uniform float sun_wrap : hint_range(0.0, 0.5) = 0.25;
// r6: a knee on the direct term, d * (1 + k) / (d + k): square faces x1.0, the 75-deg-off hero wall
// x1.83, wrap-only shade x2.6 - the gain cut above comes off the top, not off the grazing walls
uniform float sun_knee : hint_range(0.05, 2.0) = 0.3;
// world-space direction TOWARD the sun (set by WorldKit.rock_material from Atmosphere): the shade
// fill is an emission term, so fragment() needs the sun to gate it; default = yaw -40 / el 36
uniform vec3 sun_dir = vec3(-0.520, 0.588, 0.620);   // r5: the grazing hero wall (sun 75 deg off its normal) must still read lit (V >= 0.55)

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
	// r4: the 3 m relief fades to half beyond 40-120 m: the ref's far planes are smooth, ours were grain
	float dist_cam = length(wpos - CAMERA_POSITION_WORLD);
	float ns = normal_strength * (1.0 - 0.5 * smoothstep(40.0, 120.0, dist_cam));
	tn_x.xy *= ns; tn_y.xy *= ns; tn_z.xy *= ns;
	// a second, finer normal octave (0.8 m tiles at 0.4): at 15 m the 3 m grain read as stripes,
	// this makes it pitting; it fades out beyond ~60 m so far faces keep the coarse relief
	float fine_w = fine_normal * (1.0 - smoothstep(12.0, 30.0, dist_cam));   // r4: fades 12-30 m (was 30-70): only the nearest faces carry pitting
	if (fine_w > 0.001) {
		vec3 uvf = wpos / fine_metres;
		tn_x.xy += (texture(normal_tex, uvf.zy + 0.29).xy * 2.0 - 1.0) * fine_w;
		tn_y.xy += (texture(normal_tex, uvf.xz + 0.61).xy * 2.0 - 1.0) * fine_w;
		tn_z.xy += (texture(normal_tex, uvf.xy + 0.83).xy * 2.0 - 1.0) * fine_w;
	}
	// UDN blend: each projection's tangent-space xy perturbs the world normal along the world axes
	// its UVs came from (x-proj uv = zy, y-proj uv = xz, z-proj uv = xy); UVs are straight world
	// coordinates so no sign flips are needed for back-facing sides.
	vec3 wn = normalize(n + vec3(0.0, tn_x.y, tn_x.x) * bw.x
						  + vec3(tn_y.x, 0.0, tn_y.y) * bw.y
						  + vec3(tn_z.x, tn_z.y, 0.0) * bw.z);
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);

	// ---------- bedding (baked per vertex by RockGen) ----------
	float band = 1.0 - (1.0 - COLOR.g) * bed_strength;

	// ---------- macro variation ----------
	float m1 = fbm3(wpos / macro_metres);
	float m2 = vnoise3(wpos / (macro_metres * 0.55) + 41.0);
	vec3 macro_tint = mix(macro_rust, macro_grey, m2) / vec3(0.675, 0.625, 0.565); // normalise so mean ~1
	float macro_lum = 1.0 + (m1 - 0.5) * 2.0 * macro_value;
	// normalise the texture around 1.0 so base_tint is the colour you get, whatever texture is plugged in
	float mean_lin = pow(albedo_tex_mean, 2.2);
	alb = mix(vec3(dot(alb, vec3(0.3, 0.59, 0.11))), alb, tex_saturation);
	// the texture's grain runs 0.5-1.8x its mean in linear light: at that contrast the bright
	// grains of a lit face clip (V > 0.85) while its median sits at V 0.75, so the grain is
	// compressed toward the mean before the tint
	vec3 tn = alb / mean_lin;
	tn = 1.0 + (tn - 1.0) * tex_contrast;
	alb = tn * base_tint * macro_lum * mix(vec3(1.0), macro_tint, 0.25);   // r4: macro tint mix 0.5 -> 0.25
	// streaks: noise stretched 12:1 vertically, only on side faces, darker and slightly cooler
	// 1-2 m wide runs (a high threshold on the stretched noise), and mostly under a bedding plane /
	// ledge (COLOR.g carries the dark bedding line), where water actually drips
	float streak = vnoise3(vec3(wpos.x * 0.6, wpos.y * 0.05, wpos.z * 0.6) + 7.0) * 0.7
				 + vnoise3(vec3(wpos.x * 1.4, wpos.y * 0.09, wpos.z * 1.4) + 19.0) * 0.3;
	float under_ledge = 0.35 + 0.65 * (1.0 - smoothstep(0.8, 1.0, COLOR.g));
	float streak_m = smoothstep(0.62, 0.8, streak) * (1.0 - smoothstep(0.3, 0.7, abs(n.y))) * streak_amount * under_ledge;
	alb *= mix(vec3(1.0), vec3(0.62, 0.64, 0.68), streak_m);

	// ---------- fresh fracture on the undersides (world normal pointing down) ----------
	// (only well above the ground line: a boulder's lower flank is weathered, not a fresh break)
	float under = smoothstep(-0.4, -0.75, n.y) * smoothstep(0.3, 0.9, COLOR.b) * fracture_amount * (0.7 + 0.6 * m2);
	alb = mix(alb, fracture_color * (0.85 + 0.3 * m1), under);

	// ---------- sand dusting at the foot ----------
	float foot = (1.0 - smoothstep(0.0, 1.0, COLOR.b)) * sand_amount;
	alb = mix(alb, sand_color, foot);

	// ---------- vertex AO ----------
	float ao = COLOR.r;
	vec3 ao_mul = mix(ao_warm_tint * ao_min / 0.6, vec3(1.0), ao); // deep AO goes warm, not black
	alb *= ao_mul;
	alb *= band;
	// the weathered rim is darker than the face it caps, never a bright fillet
	alb *= 1.0 - COLOR.a * rim_darken;

	// ---------- moss: only in ledges and cracks (occluded, up-facing), never on open tops ----------
	float up = smoothstep(moss_slope_start, moss_slope_full, wn.y);
	float moss_n = smoothstep(0.35, 0.75, fbm3(wpos * 0.9 + 100.0));
	float crevice = 1.0 - smoothstep(0.35, 0.6, ao);
	float moss = up * moss_n * moss_amount * crevice * 1.5;
	moss = clamp(moss, 0.0, 1.0);
	alb = mix(alb, moss_color * (0.8 + 0.4 * m1), moss);

	// ---------- sky fill (see the uniforms): tops brightest, shade sides cool ----------
	float up_w = clamp(wn.y, 0.0, 1.0);
	// undersides (the arch soffit) keep 40 % of the side term: the ref vault is #6c7586, not black
	float side_w = 1.0 - abs(wn.y) * (wn.y > 0.0 ? 1.0 : 0.6);
	// (alb already carries the AO multiplier; a second, softer AO gate keeps cavities from glowing)
	// r4: the sky reaches side faces at 30 % of the top term (the ref's big walls are sky-lit, not
	// black under a pale sky); undersides get none of it
	// r5: side faces get 12 % of the top term (was 35 %): the side fill is the shade term below
	float sky_w = mix(0.12, 1.0, up_w) * smoothstep(-0.6, 0.0, wn.y);
	// r6: the shade fill is a SHADE term: full on faces out of the sun, 40 % on a sun-square face
	// (moving it into light() instead measured ~2x the emission strength in the GL renderer)
	float sun_f = clamp(dot(wn, normalize(sun_dir)), 0.0, 1.0);
	EMISSION = alb * mix(0.5, 1.0, ao) * (sky_fill_color * sky_w * sky_fill + shade_fill_color * side_w * shade_fill * (1.0 - 0.6 * sun_f));

	if (debug_mode == 1) { alb = vec3(COLOR.r); }
	if (debug_mode == 2) { alb = base_tint; NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz); }
	if (debug_mode == 3) { alb = wn * 0.5 + 0.5; }
	ALBEDO = alb;
	ROUGHNESS = roughness_value;
	SPECULAR = specular_value;
	METALLIC = 0.0;
}


void light() {
	float ndl = dot(NORMAL, LIGHT);
	float d = clamp((ndl + sun_wrap) / (1.0 + sun_wrap), 0.0, 1.0);
	d = d * (1.0 + sun_knee) / (d + sun_knee);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * ALBEDO * d * sun_gain;
	// a little sheen on the grazing sun side (the reference's lit rims), no full GGX lobe
	vec3 h = normalize(VIEW + LIGHT);
	float ndh = max(dot(NORMAL, h), 0.0);
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * pow(ndh, 8.0) * specular_value * 0.3 * d;
}
