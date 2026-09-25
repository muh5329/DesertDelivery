// The far silhouettes of the architecture kit (BuildingKit.build_lod, ArchSpecial.lod): boxes and
// roofs whose vertex colour is the detailed building's mean albedo in LINEAR light (m-6), lit like
// arch.gdshader lights its walls (the same specular, a roughness near the maps' mean, the same
// soft sky fill on up-facing surfaces, which follows the hour: DayNight's dn_fill). By night a share
// of their windows is lit (dn_windows), as a window grid close up that averages to a glow far out,
// so a town seen from the hills at night is a scatter of lights, not a dark block.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

global uniform vec3 dn_fill;
global uniform float dn_night;
global uniform float dn_windows;
uniform vec3 sky_fill_color : source_color = vec3(0.70, 0.74, 0.82);
uniform float sky_fill = 0.10;
uniform float window_gain = 1.0;          // the lit windows' emission (tools: 0 shows the walls alone)

varying vec3 wpos;
varying vec3 wnrm;

float lod_hash(vec3 p) {
	uvec3 q = uvec3(ivec3(floor(p)) + ivec3(1048576));
	uint h = q.x * 374761393u + q.y * 668265263u + q.z * 2246822519u;
	h = (h ^ (h >> 13u)) * 1274126177u;
	return float((h ^ (h >> 16u)) & 0xffffu) / 65535.0;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 alb = COLOR.rgb;
	ALBEDO = alb;
	bool roof = wnrm.y > 0.3;
	ROUGHNESS = roof ? 0.82 : 0.86;
	SPECULAR = 0.35;
	float up = clamp(wnrm.y * 0.5 + 0.5, 0.0, 1.0);
	EMISSION = alb * sky_fill_color * sky_fill * up * dn_fill;
	if (dn_night * dn_windows > 0.001 && abs(wnrm.y) < 0.3) {
		vec2 t = normalize(vec2(-wnrm.z, wnrm.x));
		vec2 cell = vec2(dot(wpos.xz, t) / 3.2, (wpos.y - 0.8) / 3.1);
		vec2 f = fract(cell);
		vec3 id = vec3(floor(cell), floor(dot(wpos.xz, vec2(-t.y, t.x)) * 0.25));
		float h = lod_hash(id);
		float pane = step(0.32, f.x) * step(f.x, 0.68) * step(0.28, f.y) * step(f.y, 0.72);
		vec3 room = mix(vec3(1.0, 0.56, 0.24), vec3(1.0, 0.76, 0.46), fract(h * 7.13));
		vec3 near_e = room * pane * step(h, dn_windows) * (0.6 + 0.8 * fract(h * 3.7));
		// sub-pixel windows shimmer: blend to a glow as a cell shrinks under ~2 px. Not their energy
		// average (0.13 x dn_windows): the detailed buildings' windows at that range are a few
		// saturated pixels, so the average spread over every wall pixel read as moonlit plaster -
		// far rows glowing cream next to dark detailed rows at night. A quarter of it matches them.
		vec2 fw = fwidth(cell);
		float far_w = smoothstep(0.2, 0.55, max(fw.x, fw.y));
		vec3 far_e = vec3(1.0, 0.64, 0.33) * dn_windows * 0.032;
		EMISSION += mix(near_e, far_e, far_w) * dn_night * 1.7 * window_gain;
	}
}
