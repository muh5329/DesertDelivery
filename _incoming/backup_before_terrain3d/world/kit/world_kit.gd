class_name WorldKit
extends Node
## The building blocks every world is made of: sky/light/fog, the sea, rocks, vegetation kits,
## MultiMesh scatter, houses, walls, lamp posts, signposts, props. Nothing here knows the layout
## of a particular island; `Island` extends this and decides where things go.
##
## Every builder puts its nodes under `sink` (a Chunk while streaming, the Environment node for
## the resident parts). Generators capture builder calls as Callables in the WorldDatabase and a
## Chunk runs them when it loads, so this file is used at generation time AND at load time.

var terrain: Terrain
var db: WorldDatabase
var sink: Node3D
var rng := RandomNumberGenerator.new()
var sun: DirectionalLight3D
var _rock_meshes: Array[ArrayMesh] = []

const ROCK := Color(0.58, 0.50, 0.39)
const STONE := Color(0.84, 0.77, 0.63)
const STONE_DARK := Color(0.70, 0.63, 0.50)
const TERRACOTTA := Color(0.72, 0.40, 0.28)
const WOOD := Color(0.48, 0.33, 0.20)
const CYPRESS := Color(0.12, 0.24, 0.11)
const OLIVE := Color(0.36, 0.44, 0.23)
const SCRUB := Color(0.33, 0.41, 0.20)
const DRY := Color(0.58, 0.52, 0.28)
const PINE := Color(0.14, 0.30, 0.16)
const HOODOO := Color(0.78, 0.46, 0.26)
const LIMESTONE := Color(0.86, 0.84, 0.76)


## Overridden by the island: id -> [centre: Vector2, pad radius].
func hub_table() -> Dictionary:
	return {}


func _build_environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.30, 0.52, 0.86)
	sm.sky_horizon_color = Color(0.78, 0.84, 0.92)
	sm.sky_curve = 0.09
	sm.ground_bottom_color = Color(0.30, 0.42, 0.52)
	sm.ground_horizon_color = Color(0.66, 0.74, 0.82)
	sm.sun_angle_max = 22.0
	sm.sun_curve = 0.15
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.82
	env.tonemap_white = 4.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.70, 0.74, 0.82)
	env.fog_light_energy = 1.0
	env.fog_density = 0.0005
	env.fog_sky_affect = 0.15
	env.fog_aerial_perspective = 0.3
	env.glow_enabled = true
	env.glow_intensity = 0.25
	env.glow_bloom = 0.03
	env.glow_hdr_threshold = 1.2
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15
	env.adjustment_contrast = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	sink.add_child(we)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.94, 0.84)
	sun.light_energy = 0.95
	sun.rotation_degrees = Vector3(-46, 38, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 220.0
	sun.directional_shadow_split_1 = 0.08
	sun.directional_shadow_split_2 = 0.22
	sun.directional_shadow_split_3 = 0.5
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_fade_start = 0.85
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.5
	sink.add_child(sun)


func _ground(x: float, z: float) -> float:
	return terrain.height_at(x, z)


func _register(id: StringName, display_name: String, x: float, z: float, facing: Vector3) -> void:
	db.add_location(id, Vector3(x, _ground(x, z), z), facing, display_name)


func _build_sea() -> void:
	# One big plane with a depth-banded shader: it samples the island height map by world position,
	# so shallows are turquoise and translucent, the shelf mid-blue, and the deep sea opaque navy.
	var pm := PlaneMesh.new()
	pm.size = Vector2(16000, 16000)
	pm.subdivide_depth = 8
	pm.subdivide_width = 8
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_disabled, shadows_disabled, specular_schlick_ggx;
uniform sampler2D height_map : filter_linear;
uniform float world_size = 720.0;
uniform vec3 shallow_col : source_color = vec3(0.30, 0.74, 0.70);
uniform vec3 mid_col : source_color = vec3(0.07, 0.38, 0.60);
uniform vec3 deep_col : source_color = vec3(0.03, 0.08, 0.26);
varying vec3 wpos;
float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1, 0)), f.x), mix(hash2(i + vec2(0, 1)), hash2(i + vec2(1, 1)), f.x), f.y);
}
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 uv = wpos.xz / world_size + 0.5;
	float h = -12.0;
	if (uv.x > 0.0 && uv.x < 1.0 && uv.y > 0.0 && uv.y < 1.0) { h = texture(height_map, uv).r * 90.0 - 10.0; }
	// the band edges meander: a low-frequency wobble on the depth breaks the 3 m grid staircase
	float wob = (vnoise(wpos.xz * 0.06) - 0.5) * 2.2 + (vnoise(wpos.xz * 0.21 + 7.0) - 0.5) * 0.9;
	float d = -h + wob * clamp(-h * 0.5, 0.0, 1.0);
	vec3 col = mix(shallow_col, mid_col, smoothstep(2.0, 3.6, d));
	col = mix(col, deep_col, smoothstep(4.0, 9.6, d));
	ALBEDO = col;
	ALPHA = mix(0.42, 1.0, smoothstep(0.8, 6.5, d));
	ROUGHNESS = 0.18;
	METALLIC = 0.15;
	SPECULAR = 0.3;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	var img := Image.new()
	if img.load("res://data/sea_depth.png") == OK:
		mat.set_shader_parameter("height_map", ImageTexture.create_from_image(img))
	mat.set_shader_parameter("world_size", 1000.0)
	var sea := Mats.mesh_node(pm, mat, Vector3(0, Terrain.SEA_LEVEL, 0))
	sea.name = "Sea"
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sink.add_child(sea)
	# the abyss: an opaque navy floor far below so nothing ever shows through the deep
	var pm3 := PlaneMesh.new(); pm3.size = Vector2(16000, 16000)
	var abyss := Mats.mesh_node(pm3, Mats.solid(Color(0.03, 0.08, 0.26), 1.0), Vector3(0, -12.0, 0))
	abyss.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sink.add_child(abyss)


func _rock_mesh(seed_v: int, roughness: float = 0.35) -> ArrayMesh:
	var sph := SphereMesh.new()
	sph.radius = 1.0; sph.height = 2.0
	sph.radial_segments = 18; sph.rings = 10
	var arrays := sph.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.frequency = 0.9
	var out := PackedVector3Array()
	out.resize(verts.size())
	for i in range(verts.size()):
		var v := verts[i]
		var d := 1.0 + roughness * n.get_noise_3d(v.x * 2.0, v.y * 2.0, v.z * 2.0) + roughness * 0.6 * n.get_noise_3d(v.x * 5.0 + 9.0, v.y * 5.0, v.z * 5.0) + roughness * 0.3 * n.get_noise_3d(v.x * 11.0 + 40.0, v.y * 11.0, v.z * 11.0)
		# flatten the bottom so rocks sit in the ground and slightly squash
		var vv := v * d
		vv.y = vv.y * 0.85
		out[i] = vv
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cn := FastNoiseLite.new(); cn.seed = seed_v + 7; cn.frequency = 1.6
	for t in range(0, idx.size(), 3):
		var a := out[idx[t]]; var b := out[idx[t + 1]]; var c := out[idx[t + 2]]
		var nn := (c - a).cross(b - a).normalized()
		var centre := (a + b + c) / 3.0
		# banded strata + darker crevices, lighter sun-bleached tops
		var band := 0.5 + 0.5 * sin(centre.y * 9.0 + cn.get_noise_3d(centre.x * 3.0, centre.y * 3.0, centre.z * 3.0) * 4.0)
		var shade := 0.78 + 0.22 * band + 0.10 * cn.get_noise_3d(centre.x * 6.0, centre.y * 6.0, centre.z * 6.0)
		shade *= 0.9 + 0.12 * clampf(nn.y, 0.0, 1.0)
		var col := Color(shade, shade * 0.97, shade * 0.92)
		st.set_color(col); st.set_normal(nn); st.set_uv(Vector2(a.x, a.z)); st.add_vertex(a)
		st.set_color(col); st.set_normal(nn); st.set_uv(Vector2(b.x, b.z)); st.add_vertex(b)
		st.set_color(col); st.set_normal(nn); st.set_uv(Vector2(c.x, c.z)); st.add_vertex(c)
	return st.commit()


func _rock_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = ROCK
	mat.roughness = 0.95
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	var noise_tex := NoiseTexture2D.new()
	var nn := FastNoiseLite.new()
	nn.seed = 12; nn.frequency = 0.05; nn.fractal_octaves = 3
	noise_tex.noise = nn
	noise_tex.width = 128; noise_tex.height = 128
	noise_tex.seamless = true
	noise_tex.color_ramp = Gradient.new()
	noise_tex.color_ramp.set_color(0, Color(0.70, 0.70, 0.70))
	noise_tex.color_ramp.set_color(1, Color(1.0, 1.0, 1.0))
	mat.albedo_texture = noise_tex
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3(0.12, 0.12, 0.12)
	return mat


func _add_rock(pos: Vector3, scl: Vector3, rot_y: float, mat: Material, collide: bool = true) -> void:
	if _rock_meshes.is_empty():
		for k in range(5):
			_rock_meshes.append(_rock_mesh(100 + k, 0.3 + k * 0.05))
	var mesh := _rock_meshes[rng.randi_range(0, _rock_meshes.size() - 1)]
	var mi := Mats.mesh_node(mesh, mat, pos, Vector3(0, rot_y, 0), scl)
	sink.add_child(mi)
	if collide:
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		var cs := CollisionShape3D.new()
		var sh := SphereShape3D.new()
		sh.radius = 0.85
		cs.shape = sh
		cs.scale = scl * Vector3(1, 0.85, 1)
		sb.add_child(cs)
		sb.position = pos
		sb.rotation_degrees = Vector3(0, rot_y, 0)
		sink.add_child(sb)


## True within `r` metres of any road sample (bridges and viaducts included, unlike road_dist_at).
func _near_road(x: float, z: float, r: float) -> bool:
	var n := terrain.nearest_road(Vector3(x, 0, z))
	return Vector2(n.point.x - x, n.point.z - z).length() < r


func _near_location(x: float, z: float, r: float) -> bool:
	for k in db.locations.keys():
		var p: Vector3 = db.locations[k].pos
		if Vector2(p.x - x, p.z - z).length() < r:
			return true
	for name in hub_table().keys():
		if hub_table()[name][0].distance_to(Vector2(x, z)) < r:
			return true
	return false


class PropPart:
	var mesh: Mesh
	var mat: Material
	var xform: Transform3D
	func _init(m: Mesh, mt: Material, x: Transform3D) -> void:
		mesh = m; mat = mt; xform = x


func _cypress_parts() -> Array[PropPart]:
	var parts: Array[PropPart] = []
	var trunk := CylinderMesh.new(); trunk.top_radius = 0.10; trunk.bottom_radius = 0.16; trunk.height = 1.4; trunk.radial_segments = 6
	parts.append(PropPart.new(trunk, Mats.solid(WOOD, 0.9), Transform3D(Basis(), Vector3(0, 0.7, 0))))
	var fol_mat := StandardMaterial3D.new()
	fol_mat.albedo_color = CYPRESS
	fol_mat.roughness = 0.95
	fol_mat.vertex_color_use_as_albedo = true
	var c1 := CylinderMesh.new(); c1.top_radius = 0.45; c1.bottom_radius = 0.75; c1.height = 2.6; c1.radial_segments = 8
	var c2 := CylinderMesh.new(); c2.top_radius = 0.25; c2.bottom_radius = 0.62; c2.height = 2.8; c2.radial_segments = 8
	var c3 := CylinderMesh.new(); c3.top_radius = 0.0; c3.bottom_radius = 0.4; c3.height = 2.6; c3.radial_segments = 8
	parts.append(PropPart.new(c1, fol_mat, Transform3D(Basis(), Vector3(0, 2.2, 0))))
	parts.append(PropPart.new(c2, fol_mat, Transform3D(Basis(), Vector3(0, 4.6, 0))))
	parts.append(PropPart.new(c3, fol_mat, Transform3D(Basis(), Vector3(0, 7.1, 0))))
	return parts


func _olive_parts() -> Array[PropPart]:
	var parts: Array[PropPart] = []
	var trunk := CylinderMesh.new(); trunk.top_radius = 0.14; trunk.bottom_radius = 0.28; trunk.height = 2.0; trunk.radial_segments = 6
	parts.append(PropPart.new(trunk, Mats.solid(WOOD.darkened(0.15), 0.9), Transform3D(Basis(), Vector3(0, 1.0, 0))))
	var fol_mat := StandardMaterial3D.new()
	fol_mat.albedo_color = OLIVE
	fol_mat.roughness = 0.95
	fol_mat.vertex_color_use_as_albedo = true
	for i in range(4):
		var s := SphereMesh.new(); s.radius = 1.5; s.height = 2.2; s.radial_segments = 8; s.rings = 4
		var a := TAU * i / 4.0
		var off := Vector3(cos(a) * 0.9, 2.6 + (i % 2) * 0.5, sin(a) * 0.9)
		parts.append(PropPart.new(s, fol_mat, Transform3D(Basis(), off)))
	return parts


func _bush_parts() -> Array[PropPart]:
	var parts: Array[PropPart] = []
	var fol_mat := StandardMaterial3D.new()
	fol_mat.albedo_color = SCRUB
	fol_mat.roughness = 0.95
	fol_mat.vertex_color_use_as_albedo = true
	var s := SphereMesh.new(); s.radius = 1.0; s.height = 1.2; s.radial_segments = 7; s.rings = 4
	parts.append(PropPart.new(s, fol_mat, Transform3D(Basis(), Vector3(0, 0.35, 0))))
	var s2 := SphereMesh.new(); s2.radius = 0.7; s2.height = 0.9; s2.radial_segments = 7; s2.rings = 4
	parts.append(PropPart.new(s2, fol_mat, Transform3D(Basis(), Vector3(0.6, 0.45, 0.3))))
	return parts


func _grass_parts() -> Array[PropPart]:
	var parts: Array[PropPart] = []
	var mat := StandardMaterial3D.new()
	mat.albedo_color = DRY
	mat.roughness = 1.0
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var q := CylinderMesh.new(); q.top_radius = 0.0; q.bottom_radius = 0.42; q.height = 0.34; q.radial_segments = 5
	parts.append(PropPart.new(q, mat, Transform3D(Basis(), Vector3(0, 0.15, 0))))
	return parts


func _flower_parts(col: Color) -> Array[PropPart]:
	var parts: Array[PropPart] = []
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 1.0
	mat.vertex_color_use_as_albedo = true
	var q := SphereMesh.new(); q.radius = 0.28; q.height = 0.25; q.radial_segments = 6; q.rings = 3
	parts.append(PropPart.new(q, mat, Transform3D(Basis(), Vector3(0, 0.12, 0))))
	return parts


func _spawn_multimesh(parts: Array[PropPart], xforms: Array[Transform3D], colors: Array[Color], collide_radius: float = 0.0, shadows: bool = true) -> void:
	if xforms.is_empty(): return
	for part in parts:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = part.mesh
		mm.instance_count = xforms.size()
		for i in range(xforms.size()):
			mm.set_instance_transform(i, xforms[i] * part.xform)
			mm.set_instance_color(i, colors[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = part.mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sink.add_child(mmi)
	if collide_radius > 0.0:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		for x in xforms:
			var cs := CollisionShape3D.new()
			var sh := CylinderShape3D.new()
			sh.radius = collide_radius * x.basis.get_scale().x
			sh.height = 4.0
			cs.shape = sh
			cs.transform = Transform3D(Basis(), x.origin + Vector3(0, 2.0, 0))
			body.add_child(cs)
		sink.add_child(body)


func _scatter(count: int, min_road: float, min_h: float, max_h: float, max_slope: float, scale_range: Vector2, tint: Color, spread: float, region: Rect2 = Rect2(-Terrain.SIZE * 0.5, -Terrain.SIZE * 0.5, Terrain.SIZE, Terrain.SIZE), hub_clear: float = 26.0) -> Array:
	var xforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	var tries := 0
	while xforms.size() < count and tries < count * 40:
		tries += 1
		var x := rng.randf_range(region.position.x, region.end.x)
		var z := rng.randf_range(region.position.y, region.end.y)
		var h := _ground(x, z)
		if h < min_h or h > max_h: continue
		if terrain.road_dist_at(x, z) < min_road: continue
		if terrain.normal_at(x, z).y < 1.0 - max_slope: continue
		if hub_clear > 0.0 and _near_location(x, z, hub_clear): continue
		var s := rng.randf_range(scale_range.x, scale_range.y)
		var b := Basis(Vector3.UP, rng.randf_range(0, TAU)).scaled(Vector3(s, s * rng.randf_range(0.9, 1.15), s))
		xforms.append(Transform3D(b, Vector3(x, h - 0.05, z)))
		var v := rng.randf_range(-spread, spread)
		colors.append(Color(tint.r + v, tint.g + v * 0.8, tint.b + v * 0.5))
	return [xforms, colors]


func _static_box(parent: Node3D, size: Vector3, mat: Material, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO, collide: bool = true) -> MeshInstance3D:
	var mi := Mats.box(size, mat, pos, rot_deg)
	parent.add_child(mi)
	if collide:
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		sb.add_child(cs)
		sb.position = pos
		sb.rotation_degrees = rot_deg
		parent.add_child(sb)
	return mi


func _add_cylinder_body(parent: Node3D, radius: float, height: float, pos: Vector3) -> void:
	var sb := StaticBody3D.new(); sb.collision_layer = 1
	var cs := CollisionShape3D.new(); var sh := CylinderShape3D.new(); sh.radius = radius; sh.height = height
	cs.shape = sh; cs.position = Vector3(0, height * 0.5, 0); sb.add_child(cs); sb.position = pos; parent.add_child(sb)


func _house(parent: Node3D, pos: Vector3, rot_y: float, w: float, d: float, floors: int, wall: Color = STONE, roof_col: Color = TERRACOTTA) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation_degrees = Vector3(0, rot_y, 0)
	parent.add_child(n)
	var fh := 3.1
	var h := fh * floors
	var wall_mat := Mats.solid(wall, 0.9)
	_static_box(n, Vector3(w, h + 3.0, d), wall_mat, Vector3(0, (h - 3.0) * 0.5, 0))
	# roof
	var roof := Mats.prism(Vector3(w + 0.9, 1.6 + w * 0.12, d + 0.9), Mats.solid(roof_col, 0.85), Vector3(0, h + (1.6 + w * 0.12) * 0.5, 0))
	n.add_child(roof)
	var rb := StaticBody3D.new(); rb.collision_layer = 1
	var rcs := CollisionShape3D.new()
	rcs.shape = (roof.mesh as PrismMesh).create_convex_shape()
	rb.add_child(rcs)
	rb.position = roof.position
	n.add_child(rb)
	# eave band
	n.add_child(Mats.box(Vector3(w + 0.9, 0.18, d + 0.9), Mats.solid(STONE_DARK, 0.9), Vector3(0, h + 0.05, 0)))
	# windows + shutters (front & back)
	var win := Mats.solid(Color(0.16, 0.19, 0.24), 0.3, 0.2)
	var shutter := Mats.solid(Color(0.30, 0.42, 0.32), 0.8)
	for f in range(floors):
		var y := fh * f + 1.75
		var count := maxi(int(w / 2.6), 1)
		for i in range(count):
			var x := -w * 0.5 + (i + 0.5) * (w / count)
			for side in [-1.0, 1.0]:
				n.add_child(Mats.box(Vector3(0.9, 1.1, 0.08), win, Vector3(x, y, side * (d * 0.5 + 0.02))))
				n.add_child(Mats.box(Vector3(0.3, 1.15, 0.06), shutter, Vector3(x - 0.62, y, side * (d * 0.5 + 0.03))))
				n.add_child(Mats.box(Vector3(0.3, 1.15, 0.06), shutter, Vector3(x + 0.62, y, side * (d * 0.5 + 0.03))))
	# door on the front (-Z)
	n.add_child(Mats.box(Vector3(1.1, 2.1, 0.1), Mats.solid(WOOD, 0.8), Vector3(0, 1.05, -(d * 0.5 + 0.03))))
	return n


func _lamp_post(parent: Node3D, pos: Vector3) -> void:
	var n := Node3D.new(); n.position = pos; parent.add_child(n)
	var iron := Mats.solid(Color(0.15, 0.15, 0.16), 0.6, 0.3)
	n.add_child(Mats.cylinder(0.06, 3.4, iron, Vector3(0, 1.7, 0)))
	n.add_child(Mats.cylinder(0.18, 0.15, iron, Vector3(0, 0.07, 0)))
	n.add_child(Mats.box(Vector3(0.36, 0.42, 0.36), Mats.solid(Color(1.0, 0.9, 0.6), 0.3, 0, Color(1.0, 0.8, 0.4)), Vector3(0, 3.55, 0)))
	n.add_child(Mats.cone(0.3, 0.25, iron, Vector3(0, 3.88, 0)))
	_add_cylinder_body(n, 0.12, 3.4, Vector3.ZERO)


func _signpost(parent: Node3D, pos: Vector3, rot_y: float, labels: Array) -> void:
	var n := Node3D.new(); n.position = pos; n.rotation_degrees = Vector3(0, rot_y, 0); parent.add_child(n)
	n.add_child(Mats.cylinder(0.07, 2.6, Mats.solid(WOOD, 0.9), Vector3(0, 1.3, 0)))
	var board := Mats.solid(Color(0.16, 0.22, 0.16), 0.8)
	var y := 2.3
	for l in labels:
		var dir_sign: float = l[1]
		var b := Mats.box(Vector3(1.4, 0.28, 0.05), board, Vector3(dir_sign * 0.65, y, 0))
		n.add_child(b)
		n.add_child(Mats.prism(Vector3(0.28, 0.28, 0.05), board, Vector3(dir_sign * 1.45, y, 0), Vector3(0, 0, dir_sign * -90.0)))
		var lbl := Label3D.new()
		lbl.text = l[0]
		lbl.font_size = 48
		lbl.pixel_size = 0.005
		lbl.modulate = Color(0.95, 0.92, 0.75)
		lbl.position = Vector3(dir_sign * 0.65, y, 0.04)
		lbl.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		lbl.double_sided = true
		n.add_child(lbl)
		y -= 0.36
	var sb := StaticBody3D.new(); sb.collision_layer = 1
	var cs := CollisionShape3D.new(); var sh := CylinderShape3D.new(); sh.radius = 0.12; sh.height = 2.6; cs.shape = sh
	cs.position = Vector3(0, 1.3, 0); sb.add_child(cs); n.add_child(sb)


func _stone_wall(parent: Node3D, a: Vector2, b: Vector2, height: float = 1.0, h: Hub = null) -> void:
	if h: h.add_wall(a, b, height)
	var seg := b - a
	var len := seg.length()
	var steps := int(ceil(len / 4.0))
	var mat := Mats.solid(STONE_DARK, 0.95)
	for i in range(steps):
		var t0 := float(i) / steps; var t1 := float(i + 1) / steps
		var p0 := a.lerp(b, t0); var p1 := a.lerp(b, t1)
		var mid := (p0 + p1) * 0.5
		var y := _ground(mid.x, mid.y)
		var l := p0.distance_to(p1)
		var yaw := rad_to_deg(atan2(-(p1.y - p0.y), p1.x - p0.x))
		_static_box(parent, Vector3(l + 0.1, height, 0.55), mat, Vector3(mid.x, y + height * 0.5 - 0.1, mid.y), Vector3(0, yaw, 0))


func _pot_plant(parent: Node3D, pos: Vector3, s: float = 1.0) -> void:
	var n := Node3D.new(); n.position = pos; n.scale = Vector3(s, s, s); parent.add_child(n)
	n.add_child(Mats.cylinder(0.32, 0.5, Mats.solid(TERRACOTTA.lightened(0.1), 0.9), Vector3(0, 0.25, 0), Vector3.ZERO, 10, 0.4))
	n.add_child(Mats.sphere(0.45, Mats.solid(SCRUB.lightened(0.1), 0.95), Vector3(0, 0.75, 0), Vector3(1, 0.8, 1), 8))
	n.add_child(Mats.sphere(0.12, Mats.solid(Color(0.85, 0.35, 0.45), 0.9), Vector3(0.2, 1.0, 0.1), Vector3.ONE, 6))
	n.add_child(Mats.sphere(0.12, Mats.solid(Color(0.85, 0.35, 0.45), 0.9), Vector3(-0.2, 0.95, -0.15), Vector3.ONE, 6))
	_add_cylinder_body(n, 0.4, 1.0, Vector3.ZERO)


func _awning(parent: Node3D, pos: Vector3, rot_y: float, w: float, col: Color) -> void:
	var n := Node3D.new(); n.position = pos; n.rotation_degrees = Vector3(0, rot_y, 0); parent.add_child(n)
	var mat := Mats.solid(col, 0.9)
	var stripe := Mats.solid(Color(0.95, 0.93, 0.88), 0.9)
	n.add_child(Mats.box(Vector3(w, 0.08, 1.5), mat, Vector3(0, 0, -0.75), Vector3(14, 0, 0)))
	var stripes := int(w / 0.8)
	for i in range(stripes):
		if i % 2 == 0: continue
		var x := -w * 0.5 + (i + 0.5) * 0.8
		n.add_child(Mats.box(Vector3(0.38, 0.09, 1.5), stripe, Vector3(x, 0.005, -0.75), Vector3(14, 0, 0)))
	for sx in [-w * 0.5 + 0.1, w * 0.5 - 0.1]:
		n.add_child(Mats.cylinder(0.03, 2.4, Mats.solid(Color(0.2, 0.2, 0.2), 0.5, 0.4), Vector3(sx, -1.25, -1.45)))


func _place_prop(parts: Array[PropPart], pos: Vector3, scl: float = 1.0, yaw_deg: float = 0.0, tint: Color = Color(1, 1, 1), collide: bool = true) -> void:
	if collide and terrain and terrain.road_dist_at(pos.x, pos.z) < 4.2:
		return   # never plant a solid prop on a road
	var n := Node3D.new()
	n.position = pos
	n.rotation_degrees = Vector3(0, yaw_deg, 0)
	n.scale = Vector3(scl, scl, scl)
	for part in parts:
		var mi := MeshInstance3D.new()
		mi.mesh = part.mesh
		var m := part.mat
		if tint != Color(1, 1, 1) and m is StandardMaterial3D:
			m = m.duplicate()
			m.albedo_color = m.albedo_color * tint
		mi.material_override = m
		mi.transform = part.xform
		n.add_child(mi)
	sink.add_child(n)
	if not collide:
		return
	var sb := StaticBody3D.new(); sb.collision_layer = 1
	var cs := CollisionShape3D.new(); var sh := CylinderShape3D.new(); sh.radius = 0.45 * scl; sh.height = 4.0
	cs.shape = sh; cs.position = Vector3(0, 2, 0); sb.add_child(cs); n.add_child(sb)


func _flagstones(parent: Node3D, cx: float, cz: float, radius: float, tint: Color = Color(0.64, 0.60, 0.52)) -> void:
	# a slightly raised disc of pale flagstones with darker joints (stylised paving, like the town squares)
	var g := _ground(cx, cz)
	var disc := Mats.cylinder(radius, 0.12, Mats.solid(tint, 0.95), Vector3(cx, g + 0.05, cz), Vector3.ZERO, 40)
	parent.add_child(disc)
	var joint := Mats.solid(tint.darkened(0.25), 0.95)
	var n := int(radius * 2.2)
	for i in range(n):
		var a := rng.randf_range(0, TAU)
		var r := rng.randf_range(0, radius - 1.5)
		var pos := Vector3(cx + cos(a) * r, g + 0.115, cz + sin(a) * r)
		var stone := Mats.cylinder(rng.randf_range(0.7, 1.3), 0.02, Mats.solid(tint.lightened(rng.randf_range(0.0, 0.12)), 0.95), pos, Vector3.ZERO, 7)
		stone.rotation_degrees.y = rng.randf_range(0, 360)
		parent.add_child(stone)
	parent.add_child(Mats.torus(radius - 0.25, radius, joint, Vector3(cx, g + 0.06, cz), Vector3.ZERO, Vector3(1, 0.3, 1)))


func _cow(parent: Node3D, pos: Vector3, yaw: float) -> void:
	var n := Node3D.new(); n.position = pos; n.rotation_degrees = Vector3(0, yaw, 0); parent.add_child(n)
	var white := Mats.solid(Color(0.92, 0.90, 0.86), 0.9)
	var black := Mats.solid(Color(0.15, 0.13, 0.12), 0.9)
	n.add_child(Mats.capsule(0.42, 1.0, white, Vector3(0, 1.0, 0), Vector3(90, 0, 0), Vector3(1.0, 0.9, 1.0)))
	n.add_child(Mats.sphere(0.3, black, Vector3(0.15, 1.05, 0.3), Vector3(1.2, 0.8, 1.0), 8))
	n.add_child(Mats.sphere(0.25, black, Vector3(-0.2, 1.0, -0.4), Vector3(1.0, 0.9, 1.2), 8))
	n.add_child(Mats.box(Vector3(0.36, 0.34, 0.5), white, Vector3(0, 1.05, -0.95), Vector3(-10, 0, 0)))
	n.add_child(Mats.box(Vector3(0.3, 0.16, 0.16), Mats.solid(Color(0.85, 0.6, 0.6), 0.9), Vector3(0, 0.95, -1.22)))
	for sx in [-0.2, 0.2]:
		for sz in [-0.45, 0.4]:
			n.add_child(Mats.cylinder(0.07, 0.75, black, Vector3(sx, 0.38, sz)))
	_add_cylinder_body(n, 0.6, 1.5, Vector3.ZERO)


func _build_boundaries() -> void:
	var body := StaticBody3D.new()
	body.name = "Boundaries"
	body.collision_layer = 1
	var half := Terrain.SIZE * 0.5 - 10.0
	for side in [Vector3(half, 0, 0), Vector3(-half, 0, 0), Vector3(0, 0, half), Vector3(0, 0, -half)]:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		var along_x := absf(side.x) > 0.0
		sh.size = Vector3(2, 700, Terrain.SIZE) if along_x else Vector3(Terrain.SIZE, 700, 2)
		cs.shape = sh
		cs.position = side
		body.add_child(cs)
	sink.add_child(body)



# ---------------------------------------------------------------- island kits
## Tall dark conifer: trunk + three stacked cones (the forests of the interior).
func _pine_parts() -> Array[PropPart]:
	var parts: Array[PropPart] = []
	var trunk := CylinderMesh.new(); trunk.top_radius = 0.12; trunk.bottom_radius = 0.22; trunk.height = 3.0; trunk.radial_segments = 6
	parts.append(PropPart.new(trunk, Mats.solid(WOOD.darkened(0.25), 0.9), Transform3D(Basis(), Vector3(0, 1.5, 0))))
	var fol := StandardMaterial3D.new()
	fol.albedo_color = PINE
	fol.roughness = 0.95
	fol.vertex_color_use_as_albedo = true
	var c1 := CylinderMesh.new(); c1.top_radius = 0.6; c1.bottom_radius = 2.2; c1.height = 3.2; c1.radial_segments = 8
	var c2 := CylinderMesh.new(); c2.top_radius = 0.3; c2.bottom_radius = 1.7; c2.height = 3.0; c2.radial_segments = 8
	var c3 := CylinderMesh.new(); c3.top_radius = 0.0; c3.bottom_radius = 1.1; c3.height = 3.0; c3.radial_segments = 8
	parts.append(PropPart.new(c1, fol, Transform3D(Basis(), Vector3(0, 3.6, 0))))
	parts.append(PropPart.new(c2, fol, Transform3D(Basis(), Vector3(0, 5.9, 0))))
	parts.append(PropPart.new(c3, fol, Transform3D(Basis(), Vector3(0, 8.2, 0))))
	return parts


## A badlands hoodoo: stacked, slightly offset tapered drums in alternating light / dark ochre
## strata, with a pointed cap. Widths and heights vary per seed.
func _hoodoo_parts(seed_v: int) -> Array[PropPart]:
	var parts: Array[PropPart] = []
	var ochres: Array[StandardMaterial3D] = []
	for c in [Color(0.80, 0.52, 0.30), Color(0.73, 0.46, 0.26), Color(0.67, 0.41, 0.23)]:
		var m := StandardMaterial3D.new(); m.albedo_color = c; m.roughness = 0.98; m.vertex_color_use_as_albedo = true
		ochres.append(m)
	var r := RandomNumberGenerator.new(); r.seed = seed_v
	var y := 0.0
	var radius := r.randf_range(1.1, 1.8)
	var n := 3 + r.randi_range(0, 2)
	for i in range(n):
		var h := r.randf_range(1.2, 2.4)
		var top := radius * r.randf_range(0.7, 0.92)
		var c := CylinderMesh.new(); c.top_radius = top; c.bottom_radius = radius; c.height = h; c.radial_segments = 7
		var off := Vector3(r.randf_range(-0.15, 0.15), y + h * 0.5, r.randf_range(-0.15, 0.15))
		parts.append(PropPart.new(c, ochres[r.randi_range(0, 2)], Transform3D(Basis(Vector3.UP, r.randf_range(0, TAU)), off)))
		y += h - 0.05
		radius = top * r.randf_range(0.95, 1.12)
	if seed_v % 3 == 0:
		# a third of the spires carry a flat capstone: the classic mushroom hoodoo
		var cap := CylinderMesh.new(); cap.top_radius = radius * 1.35; cap.bottom_radius = radius * 1.55; cap.height = radius * 0.7; cap.radial_segments = 7
		parts.append(PropPart.new(cap, ochres[2], Transform3D(Basis(), Vector3(0, y + cap.height * 0.5, 0))))
		var nub := CylinderMesh.new(); nub.top_radius = radius * 0.5; nub.bottom_radius = radius * 1.1; nub.height = radius * 0.6; nub.radial_segments = 7
		parts.append(PropPart.new(nub, ochres[0], Transform3D(Basis(), Vector3(0, y + cap.height + nub.height * 0.5, 0))))
	else:
		var cap := CylinderMesh.new(); cap.top_radius = 0.0; cap.bottom_radius = radius * 1.05; cap.height = radius * r.randf_range(1.4, 2.4); cap.radial_segments = 7
		parts.append(PropPart.new(cap, ochres[r.randi_range(0, 2)], Transform3D(Basis(), Vector3(0, y + cap.height * 0.5, 0))))
	return parts


func _hoodoo_material() -> StandardMaterial3D:
	var mat := _rock_material()
	mat.albedo_color = HOODOO
	mat.uv1_scale = Vector3(0.25, 0.25, 0.25)
	return mat


func _limestone_material() -> StandardMaterial3D:
	var mat := _rock_material()
	mat.albedo_color = Color(0.70, 0.66, 0.60)
	mat.albedo_texture.color_ramp.set_color(0, Color(0.74, 0.72, 0.68))
	return mat


## Small fishing boat: hull, deck, a mast; a sail on some.
func _boat(parent: Node3D, pos: Vector3, yaw: float, hull: Color, sail: bool = false) -> void:
	var boat := Node3D.new(); boat.position = pos; boat.rotation_degrees = Vector3(0, yaw, 0); parent.add_child(boat)
	boat.add_child(Mats.sphere(1.0, Mats.solid(hull, 0.7), Vector3(0, -0.05, 0), Vector3(1.3, 0.55, 3.0), 10))
	boat.add_child(Mats.sphere(0.9, Mats.solid(Color(0.78, 0.66, 0.42), 0.8), Vector3(0, 0.30, 0), Vector3(1.1, 0.12, 2.7), 10))
	boat.add_child(Mats.box(Vector3(0.9, 0.5, 0.9), Mats.solid(Color(0.92, 0.90, 0.84), 0.8), Vector3(0, 0.55, -0.6)))
	boat.add_child(Mats.cylinder(0.05, 2.6, Mats.solid(WOOD, 0.9), Vector3(0, 1.4, 0.3)))
	if sail:
		boat.add_child(Mats.box(Vector3(0.05, 1.5, 1.1), Mats.solid(Color(0.95, 0.93, 0.85), 0.9), Vector3(0.05, 1.8, 0.85)))


## Wooden pier from the shore out over the water. `length` along -Z of the yaw.
func _pier(parent: Node3D, pos: Vector3, yaw: float, length: float, width: float = 3.5) -> void:
	var pier := Node3D.new(); pier.position = pos; pier.rotation_degrees = Vector3(0, yaw, 0); parent.add_child(pier)
	_static_box(pier, Vector3(width, 0.3, length), Mats.solid(WOOD, 0.9), Vector3(0, 0, -length * 0.5))
	var posts := int(length / 6.0)
	for i in range(posts + 1):
		for sx in [-width * 0.45, width * 0.45]:
			pier.add_child(Mats.cylinder(0.18, 3.0, Mats.solid(WOOD.darkened(0.2), 0.9), Vector3(sx, -1.3, -i * 6.0)))
	for i in range(posts):
		pier.add_child(Mats.cylinder(0.08, 1.0, Mats.solid(WOOD.darkened(0.2), 0.9), Vector3(width * 0.45, 0.6, -i * 6.0 - 3.0)))


## Square bell tower with an open belfry and a small pyramid roof.
func _tower(parent: Node3D, pos: Vector3, side: float, height: float, wall: Color = STONE, roof: Color = TERRACOTTA) -> void:
	var t := Node3D.new(); t.position = pos; parent.add_child(t)
	_static_box(t, Vector3(side, height + 3.0, side), Mats.solid(wall, 0.9), Vector3(0, (height - 3.0) * 0.5, 0))
	var dark := Mats.solid(Color(0.16, 0.19, 0.24), 0.3, 0.2)
	for a in range(4):
		var rot := a * 90.0
		var off := Vector3(cos(deg_to_rad(rot)), 0, sin(deg_to_rad(rot))) * (side * 0.5 + 0.02)
		t.add_child(Mats.box(Vector3(0.08 if a % 2 == 0 else side * 0.4, side * 0.6, side * 0.4 if a % 2 == 0 else 0.08), dark, Vector3(off.x, height - side * 0.5, off.z)))
	t.add_child(Mats.box(Vector3(side + 0.5, 0.3, side + 0.5), Mats.solid(STONE_DARK, 0.9), Vector3(0, height + 0.1, 0)))
	t.add_child(Mats.cone(side * 0.85, side * 0.9, Mats.solid(roof, 0.85), Vector3(0, height + 0.25 + side * 0.45, 0), 4))


## Round lighthouse: white tower, red band, glass lantern room.
func _lighthouse(parent: Node3D, pos: Vector3) -> void:
	var l := Node3D.new(); l.position = pos; parent.add_child(l)
	var white := Mats.solid(Color(0.95, 0.94, 0.90), 0.8)
	var red := Mats.solid(Color(0.80, 0.22, 0.18), 0.8)
	_static_box(l, Vector3(7, 4.2, 6), Mats.solid(STONE, 0.9), Vector3(4.5, 0.6, 0))
	l.add_child(Mats.prism(Vector3(7.9, 1.8, 6.9), Mats.solid(TERRACOTTA, 0.85), Vector3(4.5, 3.6, 0)))
	l.add_child(Mats.cylinder(2.2, 1.0, Mats.solid(STONE_DARK, 0.9), Vector3(0, -0.5, 0), Vector3.ZERO, 16, 2.4))
	l.add_child(Mats.cylinder(1.5, 18.0, white, Vector3(0, 9.0, 0), Vector3.ZERO, 16, 1.9))
	l.add_child(Mats.cylinder(1.72, 2.4, red, Vector3(0, 6.0, 0), Vector3.ZERO, 16, 1.8))
	l.add_child(Mats.cylinder(1.72, 2.4, red, Vector3(0, 12.0, 0), Vector3.ZERO, 16, 1.6))
	l.add_child(Mats.cylinder(2.0, 0.5, Mats.solid(Color(0.25, 0.25, 0.28), 0.6), Vector3(0, 18.2, 0), Vector3.ZERO, 16))
	l.add_child(Mats.cylinder(1.3, 2.4, Mats.solid(Color(1.0, 0.92, 0.6), 0.2, 0.0, Color(1.0, 0.85, 0.4)), Vector3(0, 19.6, 0), Vector3.ZERO, 12))
	l.add_child(Mats.cone(1.6, 1.4, red, Vector3(0, 21.5, 0), 12))
	_add_cylinder_body(l, 1.9, 21.0, Vector3.ZERO)


## Water tower: four legs, a round tank, a conical lid.
func _water_tower(parent: Node3D, pos: Vector3) -> void:
	var t := Node3D.new(); t.position = pos; parent.add_child(t)
	var iron := Mats.solid(Color(0.30, 0.28, 0.26), 0.6, 0.3)
	for sx in [-1.6, 1.6]:
		for sz in [-1.6, 1.6]:
			t.add_child(Mats.cylinder(0.12, 9.0, iron, Vector3(sx * 0.8, 4.5, sz * 0.8), Vector3(sz * 6.0, 0, -sx * 6.0)))
			_add_cylinder_body(t, 0.15, 9.0, Vector3(sx, 0, sz))
	t.add_child(Mats.box(Vector3(3.6, 0.2, 3.6), iron, Vector3(0, 8.9, 0)))
	t.add_child(Mats.cylinder(2.2, 3.0, Mats.solid(Color(0.55, 0.52, 0.46), 0.9), Vector3(0, 10.5, 0), Vector3.ZERO, 14))
	t.add_child(Mats.cone(2.5, 1.2, Mats.solid(TERRACOTTA.darkened(0.2), 0.85), Vector3(0, 12.6, 0), 14))
	var sb := StaticBody3D.new(); sb.collision_layer = 1
	var cs := CollisionShape3D.new(); var sh := CylinderShape3D.new(); sh.radius = 2.3; sh.height = 4.5; cs.shape = sh
	cs.position = Vector3(0, 11.0, 0); sb.add_child(cs); t.add_child(sb)


## Arched stone aqueduct along a polyline of road samples (world space, y = deck level; the end
## points may ramp down onto the banks). Under the elevated part: a repeating arcade of piers and
## semicircular arches, built from boxes. The deck is a slab with a low stone rail.
func _arcade(parent: Node3D, pts: PackedVector3Array, deck_y: float, stone: Material) -> void:
	if pts.size() < 2: return
	var span := 5.5
	var pier_w := 1.3
	var dark := Mats.solid(Color(0.72, 0.66, 0.54), 0.95)
	# walk the elevated stretch and drop a pier every `span` metres; the arch spans between piers
	var acc := span
	var last: Vector3 = pts[0]
	var prev_pier: Vector3 = Vector3.INF
	for k in range(1, pts.size()):
		var p: Vector3 = pts[k]
		var elevated := absf(p.y - deck_y) < 0.3
		acc += last.distance_to(p)
		if elevated and acc >= span:
			acc = 0.0
			var base_y := _ground(p.x, p.z) - 2.0
			if base_y < Terrain.SEA_LEVEL - 4.0: base_y = -6.0
			var h := deck_y - 0.9 - base_y
			if h > 1.5:
				_static_box(parent, Vector3(pier_w, h, 3.2), stone, Vector3(p.x, base_y + h * 0.5, p.z))
				if prev_pier != Vector3.INF:
					var dir := (p - prev_pier); dir.y = 0.0
					var L := dir.length(); dir = dir.normalized()
					var yaw := rad_to_deg(atan2(-dir.z, dir.x))
					var radius := (L - pier_w) * 0.5
					var centre := (p + prev_pier) * 0.5
					var spring := deck_y - 0.9 - radius - 1.0   # arch springs from a little below the deck
					# semicircular arch: 9 short boxes tracing the curve, thick enough to read as voussoirs
					var segs := 9
					for si in range(segs):
						var a0 := PI * si / segs; var a1 := PI * (si + 1) / segs
						var m := (a0 + a1) * 0.5
						var cx := cos(m) * (radius + 0.5); var cy := sin(m) * (radius + 0.5)
						var seg_len := radius * PI / segs + 0.3
						var pos := Vector3(centre.x, spring + cy, centre.z) + dir * cx
						_static_box(parent, Vector3(seg_len, 1.1, 3.2), dark, pos, Vector3(0, yaw, rad_to_deg(m) + 90.0), false)
					# spandrel: the wall above the arch up to the deck, on both sides of the crown
					var sp_h := (deck_y - 0.9) - (spring + radius)
					if sp_h > 0.2:
						parent.add_child(Mats.box(Vector3(L, sp_h, 3.0), stone, Vector3(centre.x, spring + radius + sp_h * 0.5, centre.z), Vector3(0, yaw, 0)))
					# haunches: fill the corners between the arch and the piers
					for side in [-1.0, 1.0]:
						var hp: Vector3 = centre + dir * (side * (radius * 0.72))
						parent.add_child(Mats.box(Vector3(radius * 0.55, radius * 0.6, 3.0), stone, Vector3(hp.x, spring + radius * 0.35, hp.z), Vector3(0, yaw, 0)))
				prev_pier = p
		last = p
	# deck as short straight slabs following the polyline (and its ramps), with a low stone rail
	var prev: Vector3 = pts[0]
	for k in range(1, pts.size()):
		var p: Vector3 = pts[k]
		var seg := p - prev
		if seg.length() < 0.5: continue
		var mid := (prev + p) * 0.5
		var flat := Vector3(seg.x, 0, seg.z)
		var yaw := rad_to_deg(atan2(-seg.z, seg.x))
		var pitch := rad_to_deg(atan2(seg.y, flat.length()))
		var rot := Vector3(0, yaw, pitch)
		_static_box(parent, Vector3(seg.length() + 0.4, 0.9, 5.2), stone, Vector3(mid.x, mid.y - 0.45, mid.z), rot)
		var side := Vector3(-seg.z, 0, seg.x).normalized()
		for s in [-1.0, 1.0]:
			var q: Vector3 = mid + side * (2.5 * s)
			_static_box(parent, Vector3(seg.length() + 0.4, 0.6, 0.3), dark, Vector3(q.x, mid.y + 0.3, q.z), rot)
		prev = p
