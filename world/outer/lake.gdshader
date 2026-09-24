// The mountain lake: a still, deep alpine blue with a Fresnel sky reflection, depth-tinted
// shallows from the depth buffer and a slow ripple normal.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;

uniform sampler2D depth_tex : hint_depth_texture, filter_linear;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform vec3 deep : source_color = vec3(0.03, 0.17, 0.24);
uniform vec3 shallow : source_color = vec3(0.12, 0.32, 0.30);
uniform vec3 sky : source_color = vec3(0.62, 0.74, 0.86);

varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

float wave(vec2 p) { return sin(p.x * 0.9 + TIME * 0.6) * 0.5 + sin(p.y * 1.3 - TIME * 0.45) * 0.5 + sin((p.x + p.y) * 2.1 + TIME) * 0.25; }

void fragment() {
	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	float scene = -v.z / v.w;
	float thick = max(scene - (-VERTEX.z), 0.0);
	float t = smoothstep(0.0, 6.0, thick);
	vec3 bed = texture(screen_tex, SCREEN_UV).rgb;
	vec3 col = mix(mix(bed, shallow, 0.6), deep, t);
	vec2 p = wpos.xz * 0.35;
	float e = 0.05;
	vec3 n = normalize(vec3(wave(p) - wave(p + vec2(e, 0.0)), 1.0 / 0.08, wave(p) - wave(p + vec2(0.0, e))));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	float fres = 0.05 + 0.95 * pow(1.0 - clamp(dot(NORMAL, normalize(-VERTEX)), 0.0, 1.0), 5.0);
	ALBEDO = mix(col, sky, fres * 0.5);
	ROUGHNESS = 0.06;
	SPECULAR = 0.5;
}
