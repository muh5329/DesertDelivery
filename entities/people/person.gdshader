shader_type spatial;
// One material for every townsperson: skin, hair, eyes, fabrics and leather are chosen per
// vertex (CharacterMesh), so a whole person is one draw call. Fabric patterns are procedural
// in fabric-space metres and box-filtered, so stripes and checks settle to their average
// colour at a distance instead of shimmering.
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform sampler2D paper : filter_linear_mipmap, repeat_enable;
uniform float paper_strength = 0.9;

varying flat int mat_id;
varying flat int pat_id;
varying vec3 second;
varying vec3 view_tangent;

const int SKIN = 0;
const int HAIR = 1;
const int COTTON = 2;
const int LINEN = 3;
const int WOOL = 4;
const int DENIM = 5;
const int LEATHER = 6;
const int EYE = 7;
const int METAL = 8;
const int STRAW = 9;
const int KNIT = 10;
const int RUBBER = 11;

vec3 to_linear(vec3 c) { return c * (c * (c * 0.305306 + 0.682171) + 0.012523); }

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
// Box-filtered pulse train: 1 inside [0, d) of every unit cycle.
float pulse_int(float x, float d) { return floor(x) * d + min(fract(x), d); }
float stripe(float x, float d) {
	float w = max(fwidth(x), 1e-4);
	return clamp((pulse_int(x + 0.5 * w, d) - pulse_int(x - 0.5 * w, d)) / w, 0.0, 1.0);
}
// Fades a fine texture out once it is smaller than a pixel.
float detail_fade(vec2 uv, float scale) { return clamp(1.2 - length(fwidth(uv * scale)) * 1.4, 0.0, 1.0); }

void vertex() {
	int code = int(round(CUSTOM0.a * 255.0));
	mat_id = code / 16;
	pat_id = code - mat_id * 16;
	second = CUSTOM0.rgb;
	view_tangent = normalize((MODELVIEW_MATRIX * vec4(TANGENT, 0.0)).xyz);
}

void fragment() {
	vec3 base = to_linear(COLOR.rgb);
	vec3 sec = to_linear(second);
	vec2 uv = UV;
	float m = 0.0;
	float shade = 1.0;
	if (pat_id == 1) { m = stripe(uv.y / 0.034 + 0.5, 0.36); }
	else if (pat_id == 2) { m = stripe(uv.x / 0.014, 0.14); }
	else if (pat_id == 3) { m = 0.5 * (stripe(uv.x / 0.026, 0.5) + stripe(uv.y / 0.026, 0.5)); }
	else if (pat_id == 4) {
		float a = stripe(uv.x / 0.075, 0.32) + 0.6 * stripe(uv.x / 0.075 + 0.55, 0.07);
		float b = stripe(uv.y / 0.075, 0.32) + 0.6 * stripe(uv.y / 0.075 + 0.55, 0.07);
		m = clamp(0.42 * (a + b), 0.0, 1.0);
	}
	else if (pat_id == 5) { shade = 0.86 + 0.14 * stripe(uv.x / 0.007, 0.5); }
	else if (pat_id == 6) {
		float rib = stripe(uv.x / 0.045, 0.22);
		float twist = stripe(uv.y / 0.028 + abs(fract(uv.x / 0.045) - 0.5) * 1.2, 0.5);
		shade = 0.80 + 0.12 * rib + 0.10 * twist * (1.0 - rib);
	}
	else if (pat_id == 7) { shade = 0.84 + 0.16 * stripe((uv.x + uv.y) / 0.009, 0.5) * stripe((uv.x - uv.y) / 0.009, 0.5); }
	else if (pat_id == 8) {
		vec2 cell = fract(uv / 0.036) - 0.5;
		float fw = length(fwidth(uv / 0.036));
		m = (1.0 - smoothstep(0.17 - fw, 0.17 + fw, length(cell))) * clamp(1.4 - fw * 2.0, 0.0, 1.0);
		m = mix(m, 0.1, clamp(fw * 2.0 - 0.4, 0.0, 1.0));
	}
	else if (pat_id == 9) {
		float zig = abs(fract(uv.x / 0.012) - 0.5);
		shade = 0.88 + 0.12 * stripe(uv.y / 0.01 + zig * 1.6 * (step(0.5, fract(uv.x / 0.024)) * 2.0 - 1.0), 0.5);
	}
	else if (pat_id == 10) { m = stripe(uv.y / 0.16 + 0.1, 0.16); }
	vec3 albedo = mix(base, sec, m) * mix(1.0, shade, detail_fade(uv, 60.0));
	if (pat_id == 11) {
		// Eye lens: UV is the offset from the iris centre in metres. Sclera, a fibrous iris
		// with a dark limbal ring, the pupil, and the shadow of the upper lid.
		float d = length(uv);
		float fw = fwidth(d) * 1.2 + 1e-5;
		float iris = 1.0 - smoothstep(0.0064 - fw, 0.0064 + fw, d);
		float pupil = 1.0 - smoothstep(0.0025 - fw, 0.0025 + fw, d);
		float ang = atan(uv.y, uv.x);
		float fibres = 0.8 + 0.4 * vnoise(vec2(ang * 9.0, d * 700.0));
		vec3 irisc = base * fibres * mix(1.25, 0.45, smoothstep(0.0038, 0.0064, d));
		vec3 sclera = sec * mix(1.0, 0.78, smoothstep(0.006, 0.013, abs(uv.x)));
		albedo = mix(sclera, irisc, iris);
		albedo = mix(albedo, vec3(0.012), pupil);
		albedo *= 1.0 - 0.5 * smoothstep(0.0, 0.0065, uv.y + 0.0009);
	}
	float rough = 0.86;
	float spec = 0.35;
	float metal = 0.0;
	float fine = detail_fade(uv, 200.0);
	if (mat_id == SKIN) {
		float pores = vnoise(uv * 90.0);
		float blotch = vnoise(uv * 11.0 + 3.1);
		albedo *= 0.96 + 0.07 * blotch;
		rough = 0.50 + 0.16 * pores * fine + 0.08 * blotch;
		spec = 0.42;
	} else if (mat_id == HAIR) {
		float strands = vnoise(vec2(uv.x * 420.0, uv.y * 9.0));
		float clumps = vnoise(vec2(uv.x * 55.0, uv.y * 3.0));
		albedo *= mix(1.0, 0.72 + 0.38 * strands, fine) * (0.86 + 0.24 * clumps);
		rough = 0.48;
		spec = 0.30;
	} else if (mat_id == LINEN) {
		float slub = vnoise(uv * vec2(38.0, 420.0)) * 0.5 + vnoise(uv * vec2(420.0, 38.0)) * 0.5;
		albedo *= mix(1.0, 0.93 + 0.12 * slub, fine);
		rough = 0.92;
		spec = 0.25;
	} else if (mat_id == WOOL || mat_id == KNIT) {
		albedo *= mix(1.0, 0.88 + 0.2 * vnoise(uv * 160.0), fine);
		rough = 0.97;
		spec = 0.18;
	} else if (mat_id == DENIM) {
		float twill = stripe((uv.x + uv.y) / 0.0035, 0.5);
		float fade = vnoise(uv * 7.0);
		albedo *= mix(1.0, 0.86 + 0.2 * twill, fine) * (0.9 + 0.2 * fade);
		rough = 0.88;
	} else if (mat_id == LEATHER) {
		albedo *= 0.9 + 0.18 * vnoise(uv * 26.0);
		rough = 0.46 + 0.14 * vnoise(uv * 70.0);
		spec = 0.45;
	} else if (mat_id == EYE) {
		rough = 0.10;
		spec = 0.65;
	} else if (mat_id == METAL) {
		rough = 0.32;
		metal = 0.85;
	} else if (mat_id == STRAW) {
		albedo *= mix(1.0, 0.82 + 0.3 * stripe((uv.x + uv.y) / 0.008, 0.5) * stripe((uv.x - uv.y) / 0.008, 0.5), fine);
		rough = 0.9;
	} else if (mat_id == RUBBER) {
		rough = 0.7;
	} else {
		albedo *= mix(1.0, 0.95 + 0.08 * vnoise(uv * 140.0), fine);
	}
	if (mat_id != EYE && mat_id != METAL) {
		// The world's gouache surface, so people sit in the same painted light as the town.
		albedo *= mix(1.0, texture(paper, uv * 1.7).r / 0.949, paper_strength);
	}
	ALBEDO = albedo;
	ROUGHNESS = rough;
	SPECULAR = spec;
	METALLIC = metal;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float wrap = mat_id == SKIN ? 0.45 : (mat_id == HAIR ? 0.32 : 0.24);
	float diff = clamp((ndl + wrap) / ((1.0 + wrap) * (1.0 + wrap)) * (1.0 + wrap), 0.0, 1.0);
	vec3 scatter = vec3(1.0);
	if (mat_id == SKIN) {
		// Light bleeding through skin reddens the terminator instead of greying it.
		float t = clamp(ndl * 1.7 + 0.25, 0.0, 1.0);
		scatter = mix(vec3(1.0, 0.46, 0.34), vec3(1.0), t);
	}
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * diff * scatter / PI;
	float ndv = clamp(dot(NORMAL, VIEW), 1e-3, 1.0);
	float nl = clamp(ndl, 0.0, 1.0);
	vec3 h = normalize(VIEW + LIGHT);
	float s = 0.0;
	if (mat_id == HAIR) {
		// Kajiya-Kay: a band of sheen across the strands, plus a softer tinted lobe.
		float th = dot(normalize(view_tangent), h);
		float sn = sqrt(max(1.0 - th * th, 0.0));
		s = (0.20 * pow(sn, 80.0) + 0.06 * pow(sn, 10.0)) * smoothstep(-0.1, 0.4, ndl);
		SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * s * mix(vec3(1.0), ALBEDO * 2.0, 0.4);
	} else {
		float a = max(ROUGHNESS * ROUGHNESS, 0.02);
		float a2 = a * a;
		float ndh = clamp(dot(NORMAL, h), 0.0, 1.0);
		float dd = ndh * ndh * (a2 - 1.0) + 1.0;
		float d = a2 / (PI * dd * dd);
		float k = a * 0.5;
		float g = 1.0 / ((ndv * (1.0 - k) + k) * (nl * (1.0 - k) + k));
		float f0 = mat_id == EYE ? 0.06 : (mat_id == SKIN ? 0.035 : 0.03);
		float f = f0 + (1.0 - f0) * pow(1.0 - clamp(dot(VIEW, h), 0.0, 1.0), 5.0);
		s = d * g * f * 0.25 * nl;
		vec3 tint = mix(vec3(1.0), ALBEDO, METALLIC);
		SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * s * tint;
	}
	// The storybook rim the rest of the world uses (Storybook.finish: rim .12).
	float rim = pow(1.0 - ndv, 4.0) * (mat_id == WOOL || mat_id == KNIT ? 0.30 : 0.14) * clamp(ndl + 0.6, 0.0, 1.0);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * rim / PI;
}
