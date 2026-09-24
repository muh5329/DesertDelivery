class_name WeaponMats
extends RefCounted
## The handful of materials every procedural firearm shares: oiled walnut with a real grain
## (object-space, so it runs along the stock whatever the mesh), parkerised grey-green steel,
## blued steel, brass, copper jackets and leather. Built once, shared by every instance.

static var _cache: Dictionary = {}

const WOOD_SHADER := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec3 base_col : source_color = vec3(0.42, 0.21, 0.09);
uniform vec3 dark_col : source_color = vec3(0.17, 0.075, 0.03);
uniform float ring_scale = 330.0;
uniform float roughness_base = 0.40;
varying vec3 lp;
// integer hash (m-16: a sin() hash of 1e5-scale arguments has no precision left on a GPU)
float h21(vec2 p) {
	uvec2 q = uvec2(ivec2(floor(p)) + ivec2(1 << 20));
	uint h = q.x * 374761393u + q.y * 668265263u;
	h = (h ^ (h >> 13u)) * 1274126177u;
	return float((h ^ (h >> 16u)) & 0xffffu) / 65535.0;
}
float vn(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}
void vertex() { lp = VERTEX; }
void fragment() {
	// growth rings cut across the height of the stock, wandering slowly along its length
	float warp = vn(vec2(lp.z * 7.0, lp.y * 30.0)) * 2.0 + vn(vec2(lp.z * 26.0, lp.x * 40.0)) * 0.6;
	float rings = sin(lp.y * ring_scale + lp.x * 90.0 + warp * 6.0);
	float band = smoothstep(0.35, 1.0, rings * 0.5 + 0.5);
	// fine pores stretched along the grain
	vec2 pp = vec2(lp.z * 260.0, lp.y * 1400.0 + lp.x * 900.0);
	// sub-pixel pores would sparkle as the rifle moves: fade them to their mean once a cell is < ~1 px
	float pores = mix(vn(pp), 0.5, smoothstep(0.5, 1.5, max(fwidth(pp.x), fwidth(pp.y))));
	float figure = vn(vec2(lp.z * 2.0 + 3.0, lp.y * 6.0));
	vec3 c = mix(base_col, dark_col, band * 0.32 + pores * 0.2 + figure * 0.18);
	ALBEDO = c;
	ROUGHNESS = roughness_base + band * 0.14 + pores * 0.08;
	SPECULAR = 0.5;
	CLEARCOAT = 0.25;
	CLEARCOAT_ROUGHNESS = 0.35;
}
"""

const PARK_SHADER := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec3 base_col : source_color = vec3(0.30, 0.31, 0.28);
uniform float metal = 0.55;
uniform float rough = 0.62;
uniform float speckle = 0.10;
varying vec3 lp;
float h31(vec3 p) {
	uvec3 q = uvec3(ivec3(p) + ivec3(1 << 20));
	uint h = q.x * 374761393u + q.y * 668265263u + q.z * 2246822519u;
	h = (h ^ (h >> 13u)) * 1274126177u;
	return float((h ^ (h >> 16u)) & 0xffffu) / 65535.0;
}
void vertex() { lp = VERTEX; }
void fragment() {
	// phosphate finish: a fine crystalline speckle and a faint grey-green mottle
	vec3 sp = lp * 1400.0;
	float s = mix(h31(floor(sp)), 0.5, smoothstep(0.5, 1.5, length(fwidth(sp))));   // no sub-pixel sparkle
	float m = h31(floor(lp * 60.0));
	ALBEDO = base_col * (1.0 - speckle + s * speckle * 2.0) * (0.94 + m * 0.1);
	METALLIC = metal;
	ROUGHNESS = rough + (s - 0.5) * 0.12;
}
"""


static func _shader_mat(key: String, code: String, params: Dictionary) -> ShaderMaterial:
	if _cache.has(key): return _cache[key]
	var sh := Shader.new()
	sh.code = code
	var m := ShaderMaterial.new()
	m.shader = sh
	for k in params: m.set_shader_parameter(k, params[k])
	_cache[key] = m
	return m


## Oiled walnut (the Garand), or `tone` for other guns' stocks (lighter maple, dark ebonised).
static func wood(tone: Color = Color(0.33, 0.155, 0.07)) -> ShaderMaterial:
	return _shader_mat("wood_%s" % tone.to_html(), WOOD_SHADER, {"base_col": tone, "dark_col": tone.darkened(0.55)})


static func parkerised() -> ShaderMaterial:
	return _shader_mat("park", PARK_SHADER, {"base_col": Color(0.30, 0.315, 0.285)})


static func blued() -> ShaderMaterial:
	return _shader_mat("blued", PARK_SHADER, {"base_col": Color(0.13, 0.14, 0.16), "metal": 0.75, "rough": 0.38, "speckle": 0.05})


static func dark_steel() -> StandardMaterial3D:
	return _std("dark", Color(0.17, 0.17, 0.17), 0.45, 0.75)


static func brass() -> StandardMaterial3D:
	return _std("brass", Color(0.82, 0.63, 0.30), 0.3, 0.9)


static func copper() -> StandardMaterial3D:
	return _std("copper", Color(0.74, 0.43, 0.26), 0.35, 0.85)


static func leather(tone: Color = Color(0.40, 0.23, 0.11)) -> StandardMaterial3D:
	return _std("leather_%s" % tone.to_html(), tone, 0.78, 0.0)


static func bore() -> StandardMaterial3D:
	return _std("bore", Color(0.02, 0.02, 0.02), 0.9, 0.0)


static func _std(key: String, c: Color, rough: float, metal: float) -> StandardMaterial3D:
	if _cache.has(key): return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	_cache[key] = m
	return m
