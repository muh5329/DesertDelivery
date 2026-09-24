shader_type spatial;
// Skin for authored (textured) characters such as the courier: the same wrapped,
// terminator-warmed lighting and varying roughness as the townsfolk (person.gdshader),
// keeping the model's own albedo colour and painted face texture.
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, hint_default_white;
uniform float roughness = 0.55;

varying vec3 local_pos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec3 a = albedo_color.rgb * texture(albedo_texture, UV).rgb;
	float blotch = vnoise(local_pos.xy * 14.0 + local_pos.z * 5.0);
	float pores = vnoise(local_pos.xy * 110.0 + local_pos.z * 41.0);
	ALBEDO = a * (0.97 + 0.06 * blotch);
	ROUGHNESS = roughness + 0.14 * pores - 0.06 * blotch;
	SPECULAR = 0.42;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float wrap = 0.45;
	float diff = clamp((ndl + wrap) / (1.0 + wrap), 0.0, 1.0);
	float t = clamp(ndl * 1.7 + 0.25, 0.0, 1.0);
	vec3 scatter = mix(vec3(1.0, 0.46, 0.34), vec3(1.0), t);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * diff * scatter / PI;
	float ndv = clamp(dot(NORMAL, VIEW), 1e-3, 1.0);
	float nl = clamp(ndl, 0.0, 1.0);
	vec3 h = normalize(VIEW + LIGHT);
	float a = max(ROUGHNESS * ROUGHNESS, 0.02);
	float a2 = a * a;
	float ndh = clamp(dot(NORMAL, h), 0.0, 1.0);
	float dd = ndh * ndh * (a2 - 1.0) + 1.0;
	float d = a2 / (PI * dd * dd);
	float k = a * 0.5;
	float g = 1.0 / ((ndv * (1.0 - k) + k) * (nl * (1.0 - k) + k));
	float f = 0.035 + 0.965 * pow(1.0 - clamp(dot(VIEW, h), 0.0, 1.0), 5.0);
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * d * g * f * 0.25 * nl;
	float rim = pow(1.0 - ndv, 4.0) * 0.14 * clamp(ndl + 0.6, 0.0, 1.0);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * rim / PI;
}
