class_name CampfireGlow
extends Node3D
## A burning campfire (M-12): flame cards animated on the GPU, an ember bed, and a flickering
## OmniLight that throws a wide warm pool once the sun is down (by day it is a small fire in
## sunlight). One per camp, only while the camp is loaded.
##
## CampfireGlow.attach(parent, pos) -> CampfireGlow

static var _flame_mat: ShaderMaterial
static var _flame_mesh: ArrayMesh
static var _ember_mat: ShaderMaterial

var light: OmniLight3D
var _seed := 0.0
var _t := 0.0


static func attach(parent: Node3D, pos: Vector3, scale_v := 1.0) -> CampfireGlow:
	var g := CampfireGlow.new()
	g.name = "Campfire"
	g.position = pos
	g.scale = Vector3.ONE * scale_v
	g._seed = fmod(absf(pos.x * 0.37 + pos.z * 0.71), 50.0)
	var flame := MeshInstance3D.new(); flame.name = "Flame"
	flame.mesh = _mesh(); flame.material_override = _flame_material()
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flame.set_instance_shader_parameter("seed", g._seed)
	g.add_child(flame)
	var embers := MeshInstance3D.new(); embers.name = "Embers"
	var sm := SphereMesh.new(); sm.radius = 0.32; sm.height = 0.18; sm.radial_segments = 10; sm.rings = 4
	embers.mesh = sm; embers.material_override = _embers(); embers.position = Vector3(0, 0.06, 0)
	embers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.add_child(embers)
	g.light = OmniLight3D.new()
	g.light.light_color = Color(1.0, 0.58, 0.26)
	g.light.position = Vector3(0, 0.9, 0)
	g.light.omni_attenuation = 1.3
	g.light.light_volumetric_fog_energy = 0.4
	g.light.distance_fade_enabled = true
	g.light.distance_fade_begin = 90.0; g.light.distance_fade_length = 30.0
	g.add_child(g.light)
	parent.add_child(g)
	return g


func _process(delta: float) -> void:
	_t += delta
	var dn := DayNight.now
	var night := dn.night if dn else 0.0
	# two incommensurate flickers and a slow breath; wider and brighter after dark
	var f := 0.82 + 0.1 * sin(_t * 13.1 + _seed) + 0.07 * sin(_t * 23.7 + _seed * 2.0) + 0.06 * sin(_t * 2.3 + _seed)
	light.light_energy = lerpf(1.2, 3.4, night) * f
	light.omni_range = lerpf(6.5, 13.0, night)
	light.position.y = 0.9 + 0.05 * sin(_t * 9.0 + _seed)


static func _mesh() -> ArrayMesh:
	if _flame_mesh: return _flame_mesh
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# three crossed cards, 0.9 m wide, 1.2 m tall
	for k in range(3):
		var a := PI * k / 3.0
		var r := Vector3(cos(a), 0, sin(a)) * 0.45
		var q := [[-r, Vector2(0, 1)], [r, Vector2(1, 1)], [r + Vector3(0, 1.2, 0), Vector2(1, 0)], [-r + Vector3(0, 1.2, 0), Vector2(0, 0)]]
		for i in [0, 1, 2, 0, 2, 3]:
			st.set_uv(q[i][1]); st.set_normal(Vector3(-sin(a), 0, cos(a))); st.add_vertex(q[i][0] + Vector3(0, 0.05, 0))
	_flame_mesh = st.commit()
	return _flame_mesh


static func _flame_material() -> ShaderMaterial:
	if _flame_mat: return _flame_mat
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
instance uniform float seed = 0.0;
float h(vec2 p) { return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453); }
float n(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1.0, 0.0)), f.x), mix(h(i + vec2(0.0, 1.0)), h(i + vec2(1.0, 1.0)), f.x), f.y); }
void fragment() {
	vec2 uv = UV;
	float t = TIME * 2.2 + seed;
	float y = 1.0 - uv.y;                                   // 0 at the logs, 1 at the top
	float x = (uv.x - 0.5) * 2.0;
	float turb = n(vec2(x * 2.5, y * 3.0 - t * 1.7)) * 0.6 + n(vec2(x * 5.0 + 3.0, y * 6.0 - t * 2.9)) * 0.4;
	float width = (1.0 - y) * 0.75 + 0.05;
	float shape = 1.0 - smoothstep(width * 0.55, width, abs(x + (turb - 0.5) * 0.5 * y));
	shape *= smoothstep(0.0, 0.08, y) * (1.0 - smoothstep(0.35 + turb * 0.45, 0.95, y));
	vec3 col = mix(vec3(1.0, 0.85, 0.45), vec3(1.0, 0.32, 0.06), smoothstep(0.1, 0.7, y));
	ALBEDO = col * shape * 2.2;
	// the cards fade edge-on (no hard lines through the fire)
	ALBEDO *= abs(dot(normalize(NORMAL), normalize(VIEW)));
}
"""
	_flame_mat = ShaderMaterial.new(); _flame_mat.shader = sh
	return _flame_mat


static func _embers() -> ShaderMaterial:
	if _ember_mat: return _ember_mat
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
varying vec3 lp;
void vertex() { lp = VERTEX; }
float h(vec3 p) { return fract(sin(dot(p, vec3(41.3, 289.1, 97.7))) * 43758.5453); }
void fragment() {
	float g = h(floor(lp * 18.0 + floor(TIME * 3.0) * 0.0));
	float pulse = 0.7 + 0.3 * sin(TIME * 3.0 + g * 20.0);
	ALBEDO = vec3(0.08, 0.05, 0.04);
	ROUGHNESS = 1.0;
	EMISSION = vec3(1.0, 0.3, 0.05) * smoothstep(0.35, 0.9, g) * pulse * 3.0;
}
"""
	_ember_mat = ShaderMaterial.new(); _ember_mat.shader = sh
	return _ember_mat
