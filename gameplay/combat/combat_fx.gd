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
var tracers := 0
var last_surface := &""


func _ready() -> void:
	if _mats.is_empty(): _build_assets()


static func _build_assets() -> void:
	var flash := StandardMaterial3D.new()
	flash.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flash.cull_mode = BaseMaterial3D.CULL_DISABLED
	flash.albedo_color = Color(1.0, 0.72, 0.32, 1.0)
	flash.vertex_color_use_as_albedo = true
	_mats.flash = flash
	var tracer := flash.duplicate()
	tracer.albedo_color = Color(1.0, 0.85, 0.55, 0.9)
	_mats.tracer = tracer
	for k in [["smoke", Color(0.82, 0.80, 0.76, 0.45)], ["dust", Color(0.80, 0.70, 0.52, 0.6)], ["stone", Color(0.70, 0.68, 0.64, 0.6)],
			["wood", Color(0.62, 0.48, 0.33, 0.5)], ["cloth", Color(0.62, 0.58, 0.52, 0.45)], ["metal", Color(0.6, 0.6, 0.6, 0.3)]]:
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = k[1]
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.vertex_color_use_as_albedo = true
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mats[k[0]] = m
	var chip := StandardMaterial3D.new(); chip.albedo_color = Color(0.62, 0.60, 0.56); chip.roughness = 0.9
	chip.vertex_color_use_as_albedo = true
	_mats.chip = chip
	var spark := StandardMaterial3D.new()
	spark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark.albedo_color = Color(1.0, 0.8, 0.35)
	spark.emission_enabled = true; spark.emission = Color(1.0, 0.65, 0.2); spark.emission_energy_multiplier = 4.0
	spark.vertex_color_use_as_albedo = true
	_mats.spark = spark
	# a flash star: three crossed quads along the bore + a disc facing forward
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for a in [0.0, PI / 3.0, 2.0 * PI / 3.0]:
		var side := Vector3(cos(a), sin(a), 0.0)
		var q := [side * -0.07, side * 0.07, side * 0.02 + Vector3(0, 0, -0.34), side * -0.02 + Vector3(0, 0, -0.34)]
		for i in [0, 1, 2, 0, 2, 3]:
			st.set_color(Color(1, 1, 1, 1) if i < 2 else Color(1, 0.6, 0.2, 0.0))
			st.add_vertex(q[i])
	for i in range(8):
		var a0 := TAU * i / 8.0; var a1 := TAU * (i + 1) / 8.0
		st.set_color(Color(1, 1, 0.9, 1)); st.add_vertex(Vector3(0, 0, -0.02))
		st.set_color(Color(1, 0.7, 0.3, 0)); st.add_vertex(Vector3(cos(a0), sin(a0), 0) * 0.11)
		st.set_color(Color(1, 0.7, 0.3, 0)); st.add_vertex(Vector3(cos(a1), sin(a1), 0) * 0.11)
	_meshes.flash = st.commit()
	var q := QuadMesh.new(); q.size = Vector2(0.5, 0.5)
	_meshes.puff = q
	var bm := BoxMesh.new(); bm.size = Vector3(0.02, 0.012, 0.018)
	_meshes.chip = bm
	var sp := BoxMesh.new(); sp.size = Vector3(0.006, 0.006, 0.07)
	_meshes.spark = sp
	var splinter := BoxMesh.new(); splinter.size = Vector3(0.008, 0.006, 0.06)
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
	var p := _burst(pos, _mats.smoke, _meshes.puff, count, 1.4, dir.normalized() * 0.9 + Vector3.UP * 0.25, 0.5, 0.35, Vector3(0, 0.25, 0))
	p.scale_amount_min = 0.25 * scale
	p.scale_amount_max = 0.55 * scale
	p.scale_amount_curve = _grow_curve()
	p.color_ramp = _fade_ramp(0.45)


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
			var d := _burst(pos + n * 0.03, _mats.stone, _meshes.puff, 5, 0.9, n, 1.2, 0.6, Vector3(0, -1.0, 0))
			d.scale_amount_min = 0.2; d.scale_amount_max = 0.45; d.color_ramp = _fade_ramp(0.6)
			var c := _burst(pos + n * 0.02, _mats.chip, _meshes.chip, 7, 0.9, n, 4.5, 0.7, Vector3(0, -9.8, 0))
			c.scale_amount_min = 0.6; c.scale_amount_max = 1.3
			c.angular_velocity_min = -720; c.angular_velocity_max = 720
		&"wood":
			var d := _burst(pos + n * 0.03, _mats.wood, _meshes.puff, 3, 0.7, n, 0.8, 0.6, Vector3(0, -0.6, 0))
			d.scale_amount_min = 0.15; d.scale_amount_max = 0.3; d.color_ramp = _fade_ramp(0.5)
			var s := _burst(pos + n * 0.02, _mats.chip, _meshes.splinter, 6, 1.0, n, 3.2, 0.8, Vector3(0, -9.8, 0))
			s.color = Color(0.72, 0.55, 0.36)
			s.angular_velocity_min = -900; s.angular_velocity_max = 900
		&"metal":
			var s := _burst(pos + n * 0.02, _mats.spark, _meshes.spark, 10, 0.25, n, 7.0, 0.9, Vector3(0, -9.8, 0))
			s.particle_flag_align_y = true
			s.scale_amount_min = 0.5; s.scale_amount_max = 1.2
			var light := OmniLight3D.new(); light.light_color = Color(1, 0.7, 0.3); light.light_energy = 1.5; light.omni_range = 2.0
			add_child(light); light.global_position = pos + n * 0.1
			_track(light, 0.05, &"light")
		&"cloth":
			var d := _burst(pos, _mats.cloth, _meshes.puff, 4, 0.5, n, 0.7, 0.7, Vector3(0, 0.3, 0))
			d.scale_amount_min = 0.12; d.scale_amount_max = 0.28; d.color_ramp = _fade_ramp(0.45)
		_:
			var d := _burst(pos + n * 0.05, _mats.dust, _meshes.puff, 7, 1.3, n + Vector3.UP * 0.4, 1.4, 0.55, Vector3(0, -0.8, 0))
			d.scale_amount_min = 0.3; d.scale_amount_max = 0.7; d.scale_amount_curve = _grow_curve(); d.color_ramp = _fade_ramp(0.6)
			var g := _burst(pos + n * 0.02, _mats.chip, _meshes.chip, 5, 0.6, n + Vector3.UP, 3.0, 0.8, Vector3(0, -9.8, 0))
			g.color = Color(0.66, 0.55, 0.40)


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
func _burst(pos: Vector3, mat: Material, mesh: Mesh, count: int, life: float, dir: Vector3, speed: float, spread: float, gravity: Vector3) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.92
	p.amount = count
	p.lifetime = life
	p.local_coords = false
	p.mesh = mesh
	p.material_override = mat
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.direction = dir.normalized() if dir.length_squared() > 0.0001 else Vector3.UP
	p.spread = rad_to_deg(spread) * 0.9
	p.initial_velocity_min = speed * 0.45
	p.initial_velocity_max = speed
	p.gravity = gravity
	p.damping_min = 0.5; p.damping_max = 1.5
	add_child(p)
	p.global_position = pos
	p.emitting = true
	_track(p, life + 0.2, &"burst")
	return p


func _fade_ramp(alpha: float) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, alpha))
	g.set_color(1, Color(1, 1, 1, 0.0))
	return g


func _grow_curve() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0, 0.4)); c.add_point(Vector2(1, 1.0))
	return c


func _track(node: Node, life: float, kind: StringName, data: Dictionary = {}) -> void:
	_live.append([node, 0.0, life, kind, data])


func _process(delta: float) -> void:
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
			&"tracer":
				var d: Dictionary = e[4]
				var travel: float = minf(e[1] * 900.0, d.len - d.streak * 0.5)
				var mi := node as MeshInstance3D
				mi.global_transform = Transform3D(d.basis, d.from + d.dir * (d.streak * 0.5 + maxf(travel, 0.0)))
				mi.transparency = clampf((k - 0.6) / 0.4, 0.0, 1.0)
		if e[1] >= e[2]:
			node.queue_free()
			_live.remove_at(i)
