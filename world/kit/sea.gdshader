// Sea and lake surface — Godot 4.7 GL Compatibility (recipe verified in RESEARCH_tech.md §3).
//
// Depth comes from the opaque depth buffer (hint_depth_texture is blitted before the transparent
// pass in Compatibility), so colour bands and foam hug every rock, stack and shoreline without any
// obstacle textures. Beyond `depth_fallback_start` metres, or wherever the depth buffer holds the
// far plane (sky / past the terrain draw distance), the island height map takes over so the far
// shelf keeps its bands. Sky reflection is a Fresnel mix toward the sky/fog colours (no SSR) so
// the far sea converges on the horizon haze; the seabed is refracted through the screen texture.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D depth_tex : hint_depth_texture, filter_linear;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform sampler2D normal_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D foam_noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D height_map : filter_linear;            // sea_depth.png: r * 90 - 10 = ground height (m)
uniform float world_size = 1000.0;                       // height_map covers -world_size/2 .. +world_size/2
uniform sampler2D outer_height : filter_linear;          // the outer world's heightfield (RF, 2001^2 over 25 km)
uniform bool outer_enabled = false;
uniform float water_level = 0.0;                         // the lake reuses this shader at its own level
uniform float depth_fallback_start = 300.0;              // metres from camera where the height map takes over
uniform float depth_fallback_end = 600.0;

// colour bands by vertical depth (albedo; the environment's sun/ambient/ACES darken them ~0.6x)
// r3: the near-rock water is the reference's DARK GREEN skirt (#385d51 H160 V0.36, darker than the
// open water beside it), not a lit cyan: turquoise / teal sit at ~linear (0.04,0.12,0.05) — blue kept
// LOW on purpose because at 150 m the (blue) fog is ~2/3 of the rendered water and adds it back —
// and only the last 0.5 m against sand lifts to a sand-lit #6f7e6a-class
uniform vec3 col_shallow : source_color = vec3(0.38, 0.65, 0.53);   // sand-lit skirt, depth < ~0.5 m only
uniform vec3 col_turquoise : source_color = vec3(0.11, 0.52, 0.49);  // r4: blue back in (ref shallows #3b5d5e / #324c58 — teal, the SAME value as the open water, not a black-green moat)
uniform vec3 col_mid : source_color = vec3(0.065, 0.34, 0.46);     // lit -> ~#425973 band (r2: x0.7, the sun went 1.25 -> 1.6 and the fog lifted)
uniform vec3 col_navy : source_color = vec3(0.08, 0.29, 0.42);   // lit -> ~#2a3d5e (ref deep #2a3959 shade / #3d567a sun); r2 x0.7 for the stronger sun
// the seabed off the coast falls ~1:6, so deep band edges make a 10-25 m wide teal band (ref #425973 / #577179)
uniform float band_turquoise = 0.5;    // vertical depth (m) where shallow -> turquoise completes
uniform float band_mid = 2.5;
uniform float band_navy = 6.0;   // the coastal shelf here is only 2-6 m deep, so 6 m keeps the open water navy

uniform vec3 sky_zenith : source_color = vec3(0.30, 0.52, 0.86);
uniform vec3 sky_horizon : source_color = vec3(0.70, 0.74, 0.82);   // = fog colour so far sea dissolves
uniform float reflect_amount : hint_range(0.0, 1.0) = 0.15;   // r4: 0.22 -> 0.28 for the open water's bright tail; r5: 0.28 -> 0.20, coast_b water reflected the cloud slab and went S0.22 (ref 0.54)
uniform float fresnel_power = 5.0;
uniform float fresnel_bias : hint_range(0.0, 0.2) = 0.07;   // r5: 0.04 -> 0.07, cliff_arch (15 m camera) water fell to V0.28 with the low fresnel

uniform float wave_a_metres = 0.9;
uniform float wave_b_metres = 7.0;
uniform vec2 wave_a_dir = vec2(1.0, 0.3);
uniform vec2 wave_b_dir = vec2(-0.4, 1.0);
uniform float wave_speed = 0.06;
uniform float wave_strength : hint_range(0.0, 1.0) = 0.36;
uniform float sparkle : hint_range(0.0, 2.0) = 0.22;   // r6 (item 12): open water had 0.29 % at V>0.85, a glitter path the ref lacks   // r3: 0.9 -> 0.5, the glitter path laced the surf zone with dashes; r5: 0.35, the sun now faces the camera
uniform vec3 sun_dir = vec3(0.0, 0.5, -0.8);              // world-space direction TOWARD the sun (set by _build_sea)
uniform vec3 sun_color : source_color = vec3(1.0, 0.84, 0.69);
uniform float sun_energy = 1.6;
uniform float refract_strength : hint_range(0.0, 0.1) = 0.02;

// r2: the foam must read cream (#e8e4dc) after fog + grade, not the #5a5557 a 1-px rim averaged to
// r4: (0.97,0.96,0.92) -> (0.86,0.84,0.80) and emission 1.0 -> 0.6: the ref's foam is often GREY (V0.47-0.85), it takes the shade of the rock it hugs
// (c1 at (0.86,0.84,0.80) x 0.6 read as grey wisps: the surf LINE in the ref is white, only the trails grey)
uniform vec3 foam_color : source_color = vec3(0.96, 0.96, 0.87);   // r6 (item 4): grey-white, renders ~V0.75 (ref collar #bfbdb3) and never clips   // r5: bright-foam bin was 5x the ref (0.56 % vs 0.11 %), the ref surf is V0.55-0.75 lace
uniform float foam_depth = 0.7;        // r6: 0.4 -> 0.7, a solid 1-2 m collar at every rock foot (the r5 lace lost the water line)        // r4: 0.9 -> 0.6, r5: 0.4, thinner collar        // shoreline / rock ring: foam where vertical depth < this (m); r3 1.6 -> 0.9: 1.6 laced the whole 2 m shelf and drew a hard line along every shore
// r3: lower frequencies and wider ramps — the r2 1.5 m clumps and 4 m lace at 100-150 m read as
// TV static (surf-zone HF std 0.064, 7x the reference); the reference's foam is a few soft clumps
uniform float foam_noise_metres = 6.5;
uniform float foam_clump_metres = 2.0;  // second noise that breaks the ring into clumps (r4: 3.5 -> 2.0, lace not discs)
uniform float foam_streak_metres = 22.0; // r5: 16 -> 22, longer trails carry the foam instead of the collar // trailing streaks along wave_a_dir behind every rock
uniform float foam_opacity : hint_range(0.0, 1.0) = 0.9;   // r6: 0.7 -> 0.9   // r5: 0.85 -> 0.7
uniform float foam_emission = 0.7;      // r6: 0.5 -> 0.7      // r5: 0.8 -> 0.5      // foam clips toward foam_color regardless of the sun/ambient
uniform float whitecap_threshold : hint_range(0.5, 1.0) = 0.93;   // r6: 3-6 caps per 100 m
uniform float whitecap_fade_metres = 220.0;   // whitecaps are sub-pixel past this, so fade them

// r2: turquoise from DISTANCE TO ROCK, not depth alone — the seabed drops ~6:1 at every wall so a
// depth band is a 1-px ring. The depth buffer is probed in a screen-space neighbourhood: any hit
// above the waterline (rock, stack, beach) within `teal_metres` (3-D distance) pulls the colour
// toward `col_teal` (ref #345365 hugging every rock for 5-20 m) and feeds the foam ring.
// r4: the r3 skirt overshot to a black-green moat (#1d383a V0.23 S0.55, 25 % of the surf zone): blue back
// in, a narrower and weaker halo — target rendered #3a595a..#334e59 (V0.32-0.38), 5-10 % of the surf zone
// (c1 at (0.05,0.12,0.11) x 0.6 over 8 m vanished under the fog: the ref's shallows are a VISIBLE green)
uniform vec3 col_teal : source_color = vec3(0.12, 0.43, 0.33);   // r6 (item 4): GREEN skirt (ref #2d4e42 H155 S0.43), not teal-blue
uniform float teal_metres = 6.0;   // r5: 9 -> 6, the skirt was 27 % of the surf zone (ref 13 %)
uniform float teal_amount : hint_range(0.0, 1.0) = 0.6;   // r6: 0.5 -> 0.6 (hue move on the 6 m skirt, not a width move)
// r3: open-water swell: a 16 m noise that modulates the Fresnel sky term (+-25 %) and the albedo a
// touch, so the open sea shows broad light/dark bands (ref open-water region lum std 0.067, ours 0.034)
uniform float swell_metres = 16.0;
uniform float swell_amount : hint_range(0.0, 1.0) = 0.18;   // r4: 0.4 -> 0.3, the bands read as camouflage blotches on the open water


// r2: the sea writes its own FOG (replacing the engine's): the engine's exponential fog with the
// engine's colour for the first `horizon_fade_start` metres, then the fog colour slides to the
// RENDERED sky-horizon colour (world_kit `_sky_horizon_linear`) so the far sea meets the sky with no
// value step. Both colours are LINEAR light (FOG.rgb is mixed post-lighting), set by _build_sea.
uniform vec3 fog_color_lin = vec3(0.16, 0.25, 0.40);
uniform float fog_density = 0.0028;
uniform float fog_sun_scatter = 0.22;
uniform float fog_sky_affect = 0.15;
uniform float horizon_fade_start = 400.0;   // r4: 250 / 1400 -> 400 / 2000: the sea behind the villa (600 m) had converged on the sky and read as a wall of mist
uniform float horizon_fade_end = 2000.0;
// the rendered sky horizon is rebuilt here the way sky.gdshader + the Compatibility sky template
// make it: sRGB colour x sky energy (+ the sun-side glow lobes), THEN linearised, then the engine's
// fog_sky_affect mix. All sRGB inputs below are the raw Atmosphere values (no source_color hint).
uniform vec3 sky_horizon_srgb = vec3(0.42, 0.55, 0.71);
uniform float sky_energy_mul = 1.4;
uniform vec3 sky_glow_srgb = vec3(0.83, 0.72, 0.66);        // sky.gdshader glow_color (narrow lobe)
uniform vec3 sky_glow_wide_srgb = vec3(0.77, 0.69, 0.73);   // sky.gdshader glow_wide_color
uniform float sky_glow_amount = 0.35;
uniform float sky_glow_power = 4.0;
uniform float sky_glow_wide = 0.35;
uniform float sky_glow_wide_mul = 0.4;   // sky.gdshader glow_wide_color_mul (at the horizon the wide lobe = az^1.5 x wide x mul)
uniform float horizon_gain = 1.0;

uniform float alpha_shallow : hint_range(0.0, 1.0) = 0.6;   // r4: 0.75 -> 0.6, a little seabed through the skirt   // r3: the pale seabed showing through 0-1.8 m lit the whole shelf cyan-grey
uniform float alpha_deep_depth = 1.2;  // fully opaque beyond this vertical depth
uniform float roughness_value : hint_range(0.0, 1.0) = 0.10;
uniform int debug_depth = 0;           // 1 = vertical depth / 10, 2 = screen texture, 3 = buffer depth / 10, 4 = fallback weight

varying vec3 wpos;

float linear_depth_from_buffer(vec2 suv, mat4 inv_proj) {
	float d = texture(depth_tex, suv).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(suv * 2.0 - 1.0, d * 2.0 - 1.0);    // OpenGL NDC -1..1 (4.7 Compat is reverse-Z, no remap)
#else
	vec3 ndc = vec3(suv * 2.0 - 1.0, d);                // Vulkan/D3D/Metal: reverse-Z, NDC z 0..1
#endif
	vec4 v = inv_proj * vec4(ndc, 1.0);
	return -v.z / v.w;                                    // metres in front of the camera
}

// view-space position of whatever the opaque pass drew at `suv` (far plane -> z far beyond -4000)
vec3 view_pos_from_buffer(vec2 suv, mat4 inv_proj) {
	float d = texture(depth_tex, suv).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(suv * 2.0 - 1.0, d * 2.0 - 1.0);
#else
	vec3 ndc = vec3(suv * 2.0 - 1.0, d);
#endif
	vec4 v = inv_proj * vec4(ndc, 1.0);
	return v.xyz / v.w;
}

// Rock proximity 0..1 for this water fragment: the depth buffer is probed in a screen-space
// neighbourhood sized for `radius_m` metres at this fragment's depth, 12 directions x 6 radii.
// Per direction the nearest above-water hit gives smoothstep(radius, near, 3-D distance); the 12
// directional weights are averaged (x gain) so the field falls off smoothly instead of drawing a
// 12-gon around every rock. A rock face 20 m up a pillar is 20 m away in 3-D and contributes
// nothing, so only feet, boulders and shorelines count — where the turquoise and the foam belong.
float rock_proximity(vec2 suv, float surf_d, float radius_m, float near_m, float gain, float sea_y, vec3 frag_w, mat4 inv_proj, mat4 inv_view) {
	float f_y = 1.0 / max(abs(inv_proj[1][1]), 1e-4);     // = P[1][1]
	float f_x = 1.0 / max(abs(inv_proj[0][0]), 1e-4);     // = P[0][0]
	vec2 r_uv = radius_m * 0.5 / surf_d * vec2(f_x, f_y);
	float acc = 0.0;
	for (int i = 0; i < 12; i++) {
		float ang = float(i) * (2.0 * PI / 12.0) + 0.13;
		vec2 dir = vec2(cos(ang), sin(ang));
		float best = radius_m;
		for (int j = 1; j <= 6; j++) {
			vec2 uv = suv + dir * r_uv * (float(j) / 6.0);
			if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) { continue; }
			vec3 vp3 = view_pos_from_buffer(uv, inv_proj);
			if (-vp3.z > 4000.0) { continue; }                       // sky
			vec3 w = (inv_view * vec4(vp3, 1.0)).xyz;
			if (w.y < sea_y + 0.15) { continue; }                    // under water: seabed, not rock
			best = min(best, distance(w, frag_w));
		}
		acc += smoothstep(radius_m, near_m, best);
	}
	return clamp(acc / 12.0 * gain, 0.0, 1.0);
}

// vertical water depth from the island height map (the far-distance fallback)
float heightmap_depth(vec2 xz) {
	vec2 uv = xz / world_size + 0.5;
	float h = -12.0;
	bool core = abs(xz.x) < 624.0 && abs(xz.y) < 624.0;
	if (outer_enabled && !core) {
		// the outer world: its own heightfield out to +-12.5 km, the deep sea beyond
		vec2 ouv = (xz + 12500.0 + 6.25) / 25012.5;
		h = -40.0;
		if (ouv.x > 0.0 && ouv.x < 1.0 && ouv.y > 0.0 && ouv.y < 1.0) { h = texture(outer_height, ouv).r; }
	} else if (uv.x > 0.0 && uv.x < 1.0 && uv.y > 0.0 && uv.y < 1.0) { h = texture(height_map, uv).r * 90.0 - 10.0; }
	return max(water_level - h, 0.0);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// ---------- water thickness along the view ray, then vertical depth ----------
	float surf_d = -VERTEX.z;                             // this fragment's linear depth
	float scene_d = linear_depth_from_buffer(SCREEN_UV, INV_PROJECTION_MATRIX);
	float thick = max(scene_d - surf_d, 0.0);             // metres of water along the ray
	vec3 up_view = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	float cos_v = abs(dot(normalize(VERTEX), up_view));   // ray steepness
	float vdepth_buf = thick * max(cos_v, 0.08);          // approx vertical depth for a flat sea
	float vdepth_map = heightmap_depth(wpos.xz);
	// fallback: far away, or where the buffer holds the far plane / nothing opaque under the water
	float far_w = smoothstep(depth_fallback_start, depth_fallback_end, surf_d);
	if (scene_d > 4000.0) { far_w = 1.0; }
	// The depth buffer is only trusted for shallow water (shorelines, rock feet, boats): the
	// Terrain3D seabed steps from the island's -5 m shelf to its -10.5 m sea rim at x/z = +-624 and
	// the -14 m abyss floor lies past +-768, and both steps drew straight seams in the sea. The
	// height map (the same shelf, sloping smoothly out to +-866 m) is the honest depth out there.
	// (`far_w` stays distance-only: it also fades foam, glints and roughness, and a depth-driven
	// jump in those redraws the very seam this removes)
	float map_w = max(far_w, smoothstep(4.0, 7.0, vdepth_buf));
	float vdepth = mix(vdepth_buf, vdepth_map, map_w);

	// ---------- moving normals: small chop + long swell ----------
	vec2 ta = wpos.xz / wave_a_metres + normalize(wave_a_dir) * TIME * wave_speed * 4.0;
	vec2 tb = wpos.xz / wave_b_metres + normalize(wave_b_dir) * TIME * wave_speed;
	vec3 na = texture(normal_a, ta).xyz * 2.0 - 1.0;
	vec3 nb = texture(normal_b, tb).xyz * 2.0 - 1.0;
	// flatten the chop with distance so the far sea does not turn into noise
	float dist_fade = 1.0 - smoothstep(60.0, 500.0, surf_d) * 0.7;
	vec3 tn = normalize(vec3((na.xy + nb.xy) * wave_strength * dist_fade, 1.0));  // tangent space, z up
	vec3 wn = normalize(vec3(tn.x, tn.z, tn.y));          // plane's up is world +y
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);

	// ---------- depth colour bands ----------
	vec3 col = mix(col_shallow, col_turquoise, smoothstep(0.0, band_turquoise, vdepth));
	col = mix(col, col_mid, smoothstep(band_turquoise, band_mid, vdepth));
	col = mix(col, col_navy, smoothstep(band_mid, band_navy, vdepth));

	// ---------- turquoise from distance to rock (see rock_distance); skipped in the far fallback ----------
	float prox = 0.0;
	if (far_w < 1.0) {
		prox = rock_proximity(SCREEN_UV, surf_d, teal_metres, 2.0, 1.6, MODEL_MATRIX[3].y, wpos, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX);
	}
	prox *= 1.0 - far_w;
	// broken up by the 11 m foam noise so the halo is patchy (sand, weed) rather than a smooth glow
	float fn_teal = texture(foam_noise, wpos.xz / (foam_noise_metres * 2.7) + vec2(-TIME * 0.015, TIME * 0.01)).r;
	// prox ~0.5 at 5 m from a wall, ~0.2 at 10 m, ~0.4 at 2 m from a lone boulder: all of those are green.
	// r3: the noise no longer opens holes in the skirt (that let the lit cyan through); it varies the
	// skirt's own darkness (weed / sand) so the whole halo stays darker than the open water
	float teal_w = smoothstep(0.04, 0.55, prox);
	col = mix(col, col_teal * (0.7 + 0.8 * fn_teal), teal_w * teal_amount);

	// ---------- refracted seabed: offset the screen sample by the wave normal, only where the
	// offset pixel is still under water (otherwise rocks above the surface would smear in) ----------
	float depth_alpha = mix(alpha_shallow, 1.0, smoothstep(0.0, alpha_deep_depth, vdepth));
	vec2 ruv = SCREEN_UV + tn.xy * refract_strength * clamp(thick, 0.0, 1.0);
	float rd = linear_depth_from_buffer(ruv, INV_PROJECTION_MATRIX);
	if (rd < surf_d) { ruv = SCREEN_UV; }
	vec3 bed = texture(screen_tex, ruv).rgb;
	// blend the bed in ourselves so the water stays a single opaque-looking layer
	col = mix(bed, col, depth_alpha);

	// ---------- fresnel sky reflection (no SSR): reflect the view ray off the perturbed normal ----------
	vec3 view_w = normalize((INV_VIEW_MATRIX * vec4(normalize(VERTEX), 0.0)).xyz);
	vec3 refl = reflect(view_w, wn);
	vec3 sky = mix(sky_horizon, sky_zenith, smoothstep(0.0, 0.5, refl.y));
	float ndv = clamp(dot(NORMAL, normalize(-VERTEX)), 0.0, 1.0);
	float fres = fresnel_bias + (1.0 - fresnel_bias) * pow(1.0 - ndv, fresnel_power);
	// swell bands: a slow 16 m noise, -1..1, scales the sky reflection and nudges the albedo
	// (stretched 2.5:1 across the long-swell direction so they are bands, not blotches)
	vec2 bd = normalize(wave_b_dir);
	vec2 sw_uv = vec2(dot(wpos.xz, bd) / swell_metres, dot(wpos.xz, vec2(-bd.y, bd.x)) / (swell_metres * 2.5));
	float swell = (texture(foam_noise, sw_uv + vec2(TIME * 0.006, -TIME * 0.004)).r - 0.5) * 5.0;
	swell = clamp(swell, -1.0, 1.0) * (1.0 - far_w * 0.6);
	col *= 1.0 + swell * swell_amount * 0.5;
	// the skirt reflects less sky: the reference's green is darker than the open water beside it
	col = mix(col, sky, fres * reflect_amount * (1.0 + swell * swell_amount) * (1.0 - teal_w * 0.5));

	// ---------- foam: shoreline / rock ring from depth + scrolling noise, broken into clumps by a
	// second 1.5 m noise, trailing streaks along the chop direction, plus sparse whitecaps ----------
	vec2 ad = normalize(wave_a_dir);
	float fn = texture(foam_noise, wpos.xz / foam_noise_metres + vec2(TIME * 0.03, -TIME * 0.02)).r;
	float fn2 = texture(foam_noise, wpos.xz / (foam_noise_metres * 2.7) + vec2(-TIME * 0.015, TIME * 0.01)).r;
	float clump = texture(foam_noise, wpos.xz / foam_clump_metres + vec2(TIME * 0.05, TIME * 0.04)).r;
	// streaks: the same noise squeezed 1:6 along the chop direction, so it reads as lines trailing off
	vec2 sc = vec2(dot(wpos.xz, ad), dot(wpos.xz, vec2(-ad.y, ad.x)));
	float streak_n = texture(foam_noise, vec2(sc.x / foam_streak_metres, sc.y / (foam_streak_metres * 0.16)) + vec2(TIME * 0.02, 0.0)).r;
	// shore term: the depth ring OR the rock-proximity ring (the seabed drops so fast that depth
	// alone gave a 1-px rim; the proximity ring is 3-5 m wide in metres, ragged by the noise below)
	// the foam ring is the inner part of the same proximity field: beside a wall prox ~0.8 at 2 m,
	// ~0.5 at 5 m, ~0.2 at 10 m (gain 1.6, half the directions on rock)
	float prox_ring = smoothstep(0.5, 0.85, prox);
	prox_ring *= prox_ring;                                            // dense at the foot, thin at the ring's edge
	float shore = max(1.0 - smoothstep(0.0, foam_depth, vdepth), prox_ring);
	// ring: solid against the rock, lace-like further out; ~40 % of the ring stays solid cream
	// r3: one soft clump field (3.5 m clumps inside the 6.5 m lace) with wide ramps: soft-edged blobs
	// at the rock feet, ~35 % of the collar solid, no 1-px lace
	// r4: threshold 0.5 -> 0.6: ~50 % of the collar open (lace), the streaks carry the foam instead
	// r5: 0.6 -> 0.68, ~3/4 of the ring open: the remaining 10-25 px discs were this ring at foam_depth 0.6
	float ring = smoothstep(0.68, 0.92, shore * 0.35 + fn * 0.3 + clump * 0.35) * shore;
	ring += smoothstep(0.85, 1.0, shore) * 0.7;                        // r6: 0.35 -> 0.7, the solid foot line back                       // but solid in the last ~0.3 m against the rock
	// streaks reach 2-3x further out than the ring and follow the chop
	float streak_zone = max(1.0 - smoothstep(0.0, foam_depth * 2.5, vdepth), smoothstep(0.25, 0.8, prox));
	streak_zone *= streak_zone * streak_zone;   // cubic: dense at the rock foot, gone over the 3 m shelf
	// (FastNoiseLite images sit in ~0.3..0.7, so the thresholds below live in that range)
	float streak = smoothstep(0.55, 0.75, streak_n * 0.6 + clump * 0.4) * streak_zone * 1.2;   // r5: x1.2, the trails carry the foam, the collar is lace
	float caps_n = clamp((fn2 * 0.6 + fn * 0.4 - 0.3) / 0.4, 0.0, 1.0);   // 4-11 m scales: crests, not a 1.5 m sprinkle
	// sparse whitecaps on open water (~1 % of pixels clip to foam), gone where they would be sub-pixel
	float caps = smoothstep(whitecap_threshold, whitecap_threshold + 0.06, caps_n) * smoothstep(3.0, 12.0, vdepth);
	caps *= 1.0 - smoothstep(whitecap_fade_metres * 0.5, whitecap_fade_metres, surf_d);
	caps *= 1.0 - smoothstep(0.1, 0.25, prox);                          // r3: open water only, never in the 3-12 m band
	// in patches (a 25 m mask at ~30 % cover), not an even sprinkle: the reference shows a few streaks per 100 m
	caps *= smoothstep(0.6, 0.74, texture(foam_noise, wpos.xz / 25.0 + vec2(TIME * 0.004, 0.0)).r);
	float foam = clamp(ring + streak + caps, 0.0, 1.0) * foam_opacity * (1.0 - far_w);
	col = mix(col, foam_color, foam);

	// ---------- sun glints: the chop normal reflecting the sun, only where the normal actually faces
	// halfway between sun and eye (Blinn), broken up by the foam noise so it sparkles, not shines ----------
	vec3 hv = normalize(sun_dir - view_w);
	float glint = pow(clamp(dot(wn, hv), 0.0, 1.0), 180.0) * smoothstep(0.35, 0.7, fn2 + clump * 0.4);
	col += sun_color * glint * sparkle * (1.0 - far_w) * 2.0;

	if (debug_depth == 1) { col = vec3(vdepth / 10.0); }
	if (debug_depth == 2) { col = bed; }
	if (debug_depth == 3) { col = vec3(vdepth_buf / 10.0); }
	if (debug_depth == 4) { col = vec3(far_w, thick / 100.0, map_w); }
	ALBEDO = col;
	ALPHA = 1.0;
	// own fog (see fog_color_lin): engine formula near, sliding to the rendered sky horizon far out
	{
		float fog_amt = 1.0 - exp(-surf_d * fog_density);
		// the sky's colour at the horizon in THIS azimuth (see sky.gdshader: narrow + wide glow lobes)
		vec3 hz_dir = normalize(vec3(view_w.x, 0.0, view_w.z));
		float gd = max(dot(hz_dir, sun_dir), 0.0);
		float gaz = max(dot(normalize(hz_dir.xz), normalize(sun_dir.xz)), 0.0);
		vec3 glow = sky_glow_srgb * pow(gd, sky_glow_power) * sky_glow_amount + sky_glow_wide_srgb * pow(gaz, 1.5) * sky_glow_wide * sky_glow_wide_mul;
		// no upper clamp: the sky shader hands values > 1 to the tonemapper (a clamp here dropped the
		// blue channel of the far rows and drew a warm band under the sky on the sun side, r3)
		vec3 hz_srgb = max((sky_horizon_srgb + glow) * sky_energy_mul, 0.0);
		vec3 horizon_lin = mix(pow(hz_srgb, vec3(2.2)), fog_color_lin, fog_sky_affect) * horizon_gain;
		float hz_w = smoothstep(horizon_fade_start, horizon_fade_end, surf_d);
		vec3 fog_col = mix(fog_color_lin, horizon_lin, hz_w);
		// the engine's sun-side scatter, so the near sea fogs exactly like the rock beside it; faded
		// out with the horizon slide (the sky has no such term, so at the horizon it drew a warm band)
		vec3 sun_lin = pow(sun_color, vec3(2.2));
		fog_col += sun_lin * pow(clamp(dot(view_w, sun_dir), 0.0, 1.0), 8.0) * fog_sun_scatter * sun_energy * (1.0 - hz_w);
		FOG = vec4(fog_col, fog_amt);
	}
	EMISSION = foam_color * foam * foam_emission;   // cream foam must clip, not get lit by the water's sun/ambient
	// the engine's own sky-radiance specular is the second reflection; keep it modest and let the
	// far sea go rougher so the horizon does not turn into a sky-coloured mirror
	ROUGHNESS = mix(mix(roughness_value, 0.4, far_w), 0.9, foam);
	SPECULAR = 0.3;
	METALLIC = 0.0;
}
