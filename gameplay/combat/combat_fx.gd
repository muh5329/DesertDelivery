class_name CombatFx
extends Node3D
## The look of a gunfight, shared by the courier's Garand and every bandit's gun: muzzle flash
## (a star of hot quads + a short light), drifting smoke, a tracer streak that travels the shot's
## path, and an impact per surface — dust off the ground, chips off stone, splinters off wood,
## sparks off metal, a puff of cloth off a coat. Tasteful: nothing red, nothing lingers.
##
##   muzzle(xform)                       flash + smoke at a muzzle, -Z forward
##   tracer(from, to, width)             a streak along the shot
##   impact(pos, normal, surface)        surface: &"dust" &"stone" &"wood" &"metal" &"cloth"
##   surface_of(collider) -> StringName  classify whatever a ray hit

static var _mats: Dictionary = {}
static var _meshes: Dictionary = {}
var _live: Array = []          # [node, t, life, kind, data]
var impacts := 0               # counters for tests / the debug overlay
var time_scale := 1.0          # render tools freeze the effects (0) to photograph them
var tracers := 0
var last_surface := &""


func _ready() -> void:
	if _mats.is_empty(): _build_assets()


static func _build_assets() -> void:
	# mixed, not added: an additive flash vanishes against a sunlit desert
	var flash := StandardMaterial3D.new()
	flash.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash.cull_mode = BaseMaterial3D.CULL_DISABLED
	flash.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	flash.vertex_color_use_as_albedo = true
	flash.no_depth_test = false
	_mats.flash = flash
	var tracer := StandardMaterial3D.new()
	tracer.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tracer.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tracer.albedo_color = Color(1.0, 0.9, 0.55, 0.85)
	tracer.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats.tracer = tracer
	for k in [["smoke", Color(0.86, 0.85, 0.82, 0.55)], ["dust", Color(0.93, 0.86, 0.72, 0.8)], ["stone", Color(0.80, 0.79, 0.76, 0.75)],
			["wood", Color(0.70, 0.55, 0.38, 0.6)], ["cloth", Color(0.70, 0.66, 0.60, 0.55)], ["metal", Color(0.6, 0.6, 0.6, 0.3)]]:
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = k[1]
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.albedo_texture = _soft_dot()
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mats[k[0]] = m
	var chip := StandardMaterial3D.new(); chip.albedo_color = Color(0.50, 0.48, 0.45); chip.roughness = 0.9
	_mats.chip = chip
	var dirt := chip.duplicate(); dirt.albedo_color = Color(0.55, 0.43, 0.30)
	_mats.dirt = dirt
	var wood_bit := chip.duplicate(); wood_bit.albedo_color = Color(0.74, 0.57, 0.37)
	_mats.splinter = wood_bit
	var spark := StandardMaterial3D.new()
	spark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark.albedo_color = Color(1.0, 0.8, 0.35)
	spark.emission_enabled = true; spark.emission = Color(1.0, 0.65, 0.2); spark.emission_energy_multiplier = 4.0
	_mats.spark = spark
	# a flash star: three crossed quads along the bore + a disc facing forward
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for a in [0.0, PI / 3.0, 2.0 * PI / 3.0]:
		var side := Vector3(cos(a), sin(a), 0.0)
		var q := [side * -0.09, side * 0.09, side * 0.025 + Vector3(0, 0, -0.46), side * -0.025 + Vector3(0, 0, -0.46)]
		for i in [0, 1, 2, 0, 2, 3]:
			st.set_color(Color(1, 0.97, 0.75, 1) if i < 2 else Color(1, 0.5, 0.12, 0.15))
			st.add_vertex(q[i])
	for i in range(10):
		var a0 := TAU * i / 10.0; var a1 := TAU * (i + 1) / 10.0
		var r0 := 0.16 if i % 2 == 0 else 0.10
		st.set_color(Color(1, 1, 0.85, 1)); st.add_vertex(Vector3(0, 0, -0.03))
		st.set_color(Color(1, 0.6, 0.18, 0.2)); st.add_vertex(Vector3(cos(a0), sin(a0), 0) * r0)
		st.set_color(Color(1, 0.6, 0.18, 0.2)); st.add_vertex(Vector3(cos(a1), sin(a1), 0) * r0)
	_meshes.flash = st.commit()
	var q := QuadMesh.new(); q.size = Vector2(0.5, 0.5)
	_meshes.puff = q
	var bm := BoxMesh.new(); bm.size = Vector3(0.04, 0.025, 0.035)
	_meshes.chip = bm
	var sp := BoxMesh.new(); sp.size = Vector3(0.012, 0.12, 0.012)
	_meshes.spark = sp
	var splinter := BoxMesh.new(); splinter.size = Vector3(0.012, 0.01, 0.09)
	_meshes.splinter = splinter
	var cm := CylinderMesh.new(); cm.top_radius = 0.006; cm.bottom_radius = 0.006; cm.height = 1.0; cm.radial_segments = 4; cm.rings = 1
	_meshes.tracer = cm


# ------------------------------------------------------------------------------ muzzle
func muzzle(xform: Transform3D, scale: float = 1.0) -> void:
	var f := MeshInstance3D.new()
	f.mesh = _meshes.flash
	f.material_override = _mats.flash
	f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(f)
	f.global_transform = xform.scaled_local(Vector3.ONE * scale * randf_range(0.85, 1.2)).rotated_local(Vector3(0, 0, 1), randf() * TAU)
	_track(f, 0.05, &"flash")
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.75, 0.4)
	light.light_energy = 3.0 * scale
	light.omni_range = 5.0
	light.shadow_enabled = false
	add_child(light)
	light.global_position = xform.origin
	_track(light, 0.06, &"light")
	smoke(xform.origin + xform.basis.z * -0.1, -xform.basis.z, 4, scale)


func smoke(pos: Vector3, dir: Vector3, count: int, scale: float = 1.0) -> void:
	_burst(pos, _mats.smoke, _meshes.puff, count, 1.5, dir.normalized() * 0.9 + Vector3.UP * 0.25, 0.9, 0.35, Vector3(0, 0.3, 0), 0.3 * scale, 0.6 * scale, 2.6, false)


# ------------------------------------------------------------------------------ tracer
func tracer(from: Vector3, to: Vector3, width: float = 1.0) -> void:
	var d := to - from
	var len := d.length()
	if len < 0.6: return
	tracers += 1
	var streak := minf(len * 0.5, 7.0)
	var tr := MeshInstance3D.new()
	tr.mesh = _meshes.tracer
	tr.material_override = _mats.tracer
	tr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(tr)
	var y := d / len
	var x := (Vector3.RIGHT if absf(y.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD).cross(y).normalized()
	var z := x.cross(y).normalized()
	var basis := Basis(x * width, y * streak, z * width)
	tr.global_transform = Transform3D(basis, from + y * streak * 0.5)
	# the streak travels the path at ~900 m/s
	_track(tr, maxf(len / 900.0, 0.03) + 0.04, &"tracer", {"from": from, "dir": y, "len": len, "streak": streak, "basis": basis})


# ------------------------------------------------------------------------------ impacts
func impact(pos: Vector3, normal: Vector3, surface: StringName) -> void:
	impacts += 1
	last_surface = surface
	var n := normal.normalized() if normal.length_squared() > 0.01 else Vector3.UP
	match surface:
		&"stone":
			_burst(pos + n * 0.08, _mats.stone, _meshes.puff, 6, 1.0, n, 1.4, 0.6, Vector3(0, -1.0, 0), 0.35, 0.8, 2.0, false)
			_burst(pos + n * 0.02, _mats.chip, _meshes.chip, 7, 0.9, n, 4.5, 0.7, Vector3(0, -9.8, 0), 0.7, 1.3, 1.0, true)
		&"wood":
			_burst(pos + n * 0.03, _mats.wood, _meshes.puff, 3, 0.7, n, 0.8, 0.6, Vector3(0, -0.6, 0), 0.2, 0.4, 2.0, false)
			_burst(pos + n * 0.02, _mats.splinter, _meshes.splinter, 6, 1.0, n, 3.2, 0.8, Vector3(0, -9.8, 0), 0.8, 1.3, 1.0, true)
		&"metal":
			_burst(pos + n * 0.02, _mats.spark, _meshes.spark, 10, 0.25, n, 7.0, 0.9, Vector3(0, -9.8, 0), 0.6, 1.2, 1.0, true, true)
			var light := OmniLight3D.new(); light.light_color = Color(1, 0.7, 0.3); light.light_energy = 1.5; light.omni_range = 2.0
			add_child(light); light.global_position = pos + n * 0.1
			_track(light, 0.05, &"light")
		&"cloth":
			_burst(pos, _mats.cloth, _meshes.puff, 4, 0.5, n, 0.7, 0.7, Vector3(0, 0.3, 0), 0.15, 0.3, 1.8, false)
		_:
			_burst(pos + n * 0.15, _mats.dust, _meshes.puff, 9, 1.4, n + Vector3.UP * 0.5, 1.8, 0.55, Vector3(0, -0.6, 0), 0.5, 1.1, 2.4, false)
			_burst(pos + n * 0.02, _mats.dirt, _meshes.chip, 5, 0.6, n + Vector3.UP, 3.0, 0.8, Vector3(0, -9.8, 0), 0.7, 1.2, 1.0, true)


## Classify a ray's collider: explicit `surface` meta first (camp props, enemies), then the kind
## of node (ground, vehicles, cans), then names from the world kit; stone is the default for
## anything static and built.
static func surface_of(collider: Object) -> StringName:
	if collider == null: return &"dust"
	if collider is Node:
		var node := collider as Node
		if node.has_meta("surface"): return node.get_meta("surface")
		if node.get_parent() and node.get_parent().has_meta("surface"): return node.get_parent().get_meta("surface")
		if node is Vehicle or node is RigidBody3D or node is VehicleBody3D: return &"metal"
		if node is CharacterBody3D: return &"cloth"
		if node is Area3D: return &"metal"
		var n := String(node.name).to_lower()
		if node.get_class() == "Terrain3D" or n.begins_with("ground_") or n.contains("terrain") or n.contains("road"): return &"dust"
		for w in ["tree", "palm", "wood", "crate", "fence", "cart", "plank", "pine", "olive", "cypress", "log"]:
			if n.contains(w): return &"wood"
		for m in ["lamp", "sign", "rail", "barrel_steel"]:
			if n.contains(m): return &"metal"
		if node is StaticBody3D:
			for c in node.get_children():
				if c is CollisionShape3D and c.shape is HeightMapShape3D: return &"dust"
			return &"stone"
	return &"dust"


# ------------------------------------------------------------------------------ internals
## A handful of sprites or chips flung from `pos` along `dir` (within `spread` rad), falling
## with `gravity`, each growing to `grow` times its size and fading over `life`. Simulated
## here (not CPUParticles), so render tools can freeze them with `time_scale`.
func _burst(pos: Vector3, mat: Material, mesh: Mesh, count: int, life: float, dir: Vector3, speed: float, spread: float,
		gravity: Vector3, size_min: float, size_max: float, grow: float, solid: bool, align: bool = false) -> void:
	var d := dir.normalized() if dir.length_squared() > 0.0001 else Vector3.UP
	var side := d.cross(Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT).normalized()
	var up := side.cross(d).normalized()
	for i in range(count):
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		var a := randf() * TAU
		var r := spread * sqrt(randf())
		var v := (d + (side * cos(a) + up * sin(a)) * tan(r)).normalized() * speed * randf_range(0.45, 1.0)
		var size := randf_range(size_min, size_max)
		mi.global_position = pos + v * 0.01
		mi.scale = Vector3.ONE * size
		if solid: mi.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		_track(mi, life * randf_range(0.7, 1.0), &"bit", {"v": v, "g": gravity, "size": size, "grow": grow, "solid": solid,
			"align": align, "spin": Vector3(randf_range(-12, 12), randf_range(-12, 12), randf_range(-12, 12)) if solid and not align else Vector3.ZERO})


static func _soft_dot() -> GradientTexture2D:
	if _meshes.has("dot"): return _meshes.dot
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.add_point(0.45, Color(1, 1, 1, 0.8))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64; t.height = 64
	_meshes.dot = t
	return t


func _track(node: Node, life: float, kind: StringName, data: Dictionary = {}) -> void:
	_live.append([node, 0.0, life, kind, data])


func _process(delta: float) -> void:
	delta *= time_scale
	for i in range(_live.size() - 1, -1, -1):
		var e: Array = _live[i]
		var node: Node = e[0]
		e[1] += delta
		if not is_instance_valid(node):
			_live.remove_at(i); continue
		var k: float = e[1] / e[2]
		match e[3]:
			&"flash":
				(node as MeshInstance3D).transparency = clampf(k, 0.0, 1.0)
			&"light":
				(node as OmniLight3D).light_energy *= 0.6
			&"bit":
				var b: Dictionary = e[4]
				var mi := node as MeshInstance3D
				var v: Vector3 = b.v
				v += (b.g as Vector3) * delta
				v *= 1.0 - minf(delta * (1.5 if b.solid else 2.5), 0.5)
				b.v = v
				mi.global_position += v * delta
				if b.solid:
					if b.align and v.length_squared() > 0.01:
						mi.look_at(mi.global_position + v, Vector3.UP if absf(v.normalized().y) < 0.95 else Vector3.RIGHT)
						mi.rotate_object_local(Vector3.RIGHT, PI * 0.5)
					else:
						mi.rotation += (b.spin as Vector3) * delta
				else:
					mi.scale = Vector3.ONE * float(b.size) * lerpf(1.0, float(b.grow), clampf(k, 0.0, 1.0))
				mi.transparency = clampf((k - 0.35) / 0.65, 0.0, 1.0) if not b.solid else clampf((k - 0.7) / 0.3, 0.0, 1.0)
			&"tracer":
				var d: Dictionary = e[4]
				var travel: float = minf(e[1] * 900.0, d.len - d.streak * 0.5)
				var mi := node as MeshInstance3D
				mi.global_transform = Transform3D(d.basis, d.from + d.dir * (d.streak * 0.5 + maxf(travel, 0.0)))
				mi.transparency = clampf((k - 0.6) / 0.4, 0.0, 1.0)
		if e[1] >= e[2]:
			node.queue_free()
			_live.remove_at(i)
