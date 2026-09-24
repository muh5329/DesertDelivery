// Rivers of the outer world (outer_rivers.gd ribbons). UV.x runs across the channel (0..1), UV.y
// along it in metres, downstream. COLOR.r = the local drop (rapids), COLOR.g = width / 40.
//
// M-11: the water is coloured by what lies under it, not painted: the bed (the opaque pass behind
// the ribbon, a little refracted) seen through the water column along the view ray, absorbed
// channel by channel (red first: clear shallows over the gravel, green-brown then dark water in the
// pools), the sky's zenith-to-horizon colours in a Fresnel reflection, a sun glint from the scene's
// own lights (light(): no engine sky specular, which turned the river into a pale slab). The ribbon
// fades out where the water gets thin (vertical depth from the depth buffer), so the waterline is
// soft where the flat surface meets the bank, never the lattice's straight edges. Ripples are long
// streaks aligned with the flow, scrolled downstream, calmer far away; white water only on the rapids.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley;

uniform sampler2D depth_tex : hint_depth_texture, filter_linear;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
// absorption per metre of water (r, g, b) and the colour the water scatters toward in depth
uniform vec3 absorb = vec3(0.55, 0.22, 0.30);
uniform vec3 deep : source_color = vec3(0.045, 0.12, 0.11);
uniform vec3 silt : source_color = vec3(0.30, 0.33, 0.24);
uniform float silt_amount : hint_range(0.0, 1.0) = 0.18;
uniform vec3 sky_zenith : source_color = vec3(0.30, 0.52, 0.86);
uniform vec3 sky_horizon : source_color = vec3(0.70, 0.74, 0.82);
uniform float reflect_amount : hint_range(0.0, 1.0) = 0.55;
uniform float daylight : hint_range(0.0, 1.0) = 1.0;     // night: the sky reflection dims with the sky
uniform vec3 foam_col : source_color = vec3(0.88, 0.89, 0.86);
uniform float speed = 0.9;

varying vec3 wpos;
varying vec2 flow_uv;
varying float drop;
varying float width_m;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	flow_uv = UV;
	drop = COLOR.r;
	width_m = COLOR.g * 40.0;
}

vec3 view_pos(vec2 suv, mat4 inv_proj) {
	float d = texture(depth_tex, suv).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(suv * 2.0 - 1.0, d * 2.0 - 1.0);
#else
	vec3 ndc = vec3(suv * 2.0 - 1.0, d);
#endif
	vec4 v = inv_proj * vec4(ndc, 1.0);
	return v.xyz / v.w;
}

float streaks(vec2 p) {
	// flow-aligned: long along the channel, fine across it
	return texture(noise_tex, p).r;
}

void fragment() {
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	float across_m = (flow_uv.x - 0.5) * max(width_m, 1.0);
	float sp = speed * (1.0 + drop * 2.5);
	// two streak layers scrolled downstream at different speeds, their difference drives the normal
	vec2 f1 = vec2(across_m / 2.3, flow_uv.y / 9.0 - TIME * sp * 0.21);
	vec2 f2 = vec2(across_m / 1.1 + 0.37, flow_uv.y / 3.7 - TIME * sp * 0.47);
	float e = 0.015;
	float a = streaks(f1); float b = streaks(f2);
	float ax = streaks(f1 + vec2(e, 0.0)) - a; float ay = streaks(f1 + vec2(0.0, e)) - a;
	float bx = streaks(f2 + vec2(e, 0.0)) - b; float by = streaks(f2 + vec2(0.0, e)) - b;
	float amp = (0.35 + drop * 1.1) * (1.0 - smoothstep(60.0, 500.0, dist) * 0.85);
	// (across, along) -> world: the ribbon's tangent frame is not known here; the ripples are small
	// enough for an isotropic tilt in xz
	vec3 n = normalize(vec3((ax * 0.6 + bx * 0.4) * amp * 5.0, 1.0, (ay * 0.6 + by * 0.4) * amp * 5.0));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	// the water column under this pixel: its vertical depth (for the edge) and the view path (colour)
	vec3 vp = view_pos(SCREEN_UV, INV_PROJECTION_MATRIX);
	vec3 scene_w = (INV_VIEW_MATRIX * vec4(vp, 1.0)).xyz;
	float vdepth = max(wpos.y - scene_w.y, 0.0);
	float path = max(length(vp) - length(VERTEX), 0.0);
	path = min(path, vdepth * 6.0 + 0.5);           // grazing views over shallows don't go black
	// the bed through the water, refracted a touch by the ripples
	vec2 ruv = SCREEN_UV + n.xz * 0.012 * clamp(vdepth, 0.0, 1.0);
	float ref_ok = step(0.0, wpos.y - (INV_VIEW_MATRIX * vec4(view_pos(ruv, INV_PROJECTION_MATRIX), 1.0)).y);
	vec3 bed = texture(screen_tex, mix(SCREEN_UV, ruv, ref_ok)).rgb;
	vec3 trans = exp(-absorb * path);
	// the sky in the surface
	vec3 vdir = normalize(wpos - CAMERA_POSITION_WORLD);
	vec3 r = reflect(vdir, n);
	vec3 skyc = mix(sky_horizon, sky_zenith, smoothstep(0.0, 0.6, r.y)) * daylight;
	float ndv = clamp(dot(n, -vdir), 0.0, 1.0);
	float fres = 0.02 + 0.98 * pow(1.0 - ndv, 5.0);
	float refl = clamp(fres * reflect_amount, 0.0, 1.0);
	// white water on the rapids (both streak layers peaking), a thin wet line at the banks
	float froth = smoothstep(0.62, 0.8, a * 0.55 + b * 0.55) * smoothstep(0.45, 1.0, drop);
	float lip = (1.0 - smoothstep(0.02, 0.12, vdepth)) * smoothstep(0.55, 0.75, b) * 0.35;
	float foam = clamp(froth * 0.85 + lip, 0.0, 1.0) * (1.0 - smoothstep(250.0, 800.0, dist));
	// what the water scatters toward the eye is lit like any surface (ALBEDO); the bed seen through
	// it and the sky mirrored in it are already light (EMISSION)
	vec3 scatter = deep * (1.0 - trans) + silt * silt_amount * smoothstep(0.2, 1.5, vdepth) * (1.0 - trans);
	ALBEDO = mix(scatter * (1.0 - refl), foam_col, foam);
	EMISSION = (bed * trans * (1.0 - refl) + skyc * refl) * (1.0 - foam);
	ROUGHNESS = mix(0.08, 0.6, foam);
	// the waterline: the surface thins out over the last few centimetres of depth (soft, follows the
	// bank's real shape), far away a touch sooner so it doesn't shimmer
	ALPHA = smoothstep(0.0, 0.10 + dist * 0.0004, vdepth);
}

void light() {
	DIFFUSE_LIGHT += clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION * LIGHT_COLOR / PI;
	vec3 H = normalize(VIEW + LIGHT);
	float s = pow(clamp(dot(NORMAL, H), 0.0, 1.0), 220.0);
	SPECULAR_LIGHT += s * ATTENUATION * LIGHT_COLOR * 0.8;
}
