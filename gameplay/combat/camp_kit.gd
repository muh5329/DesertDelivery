class_name CampKit
extends RefCounted
## Builds the props of an encounter and says where the fighting happens. Layouts:
##   &"bandit"     tents, a campfire, crate stacks, sandbag walls, a lookout tower, an ammo crate
##   &"pirate"     a rowboat beached on the shore, barrels, a sail-cloth lean-to, a campfire,
##                 crates and a pennant on a pole, an ammo crate
##   &"roadblock"  a cart slewed across the road with barrels and a log (road ambushes)
##   &"squad"      no props: men in a loose line (a patrol party; test ranges)
## Everything solid is a StaticBody3D on layer 1 carrying a `surface` meta for bullet impacts.
## Returns {node, cover: Array[Vector3], slots: Array[{pos, role, facing}], ammo: Vector3}.
## A camp's local frame: -Z faces `facing` (the road it watches, the sea it came from).

const WOOD := Color(0.55, 0.40, 0.25)
const DARK_WOOD := Color(0.36, 0.25, 0.15)
const CANVAS := Color(0.86, 0.80, 0.66)
const SAILCLOTH := Color(0.78, 0.74, 0.64)
const SAND := Color(0.80, 0.72, 0.52)
const IRON := Color(0.25, 0.25, 0.26)

var root: Node3D
var cover: Array[Vector3] = []
var slots: Array = []
var ammo := Vector3.ZERO
var _origin: Vector3
var _basis: Basis
var _terrain: Terrain
var _rng := RandomNumberGenerator.new()


static func build(kind: StringName, layout: StringName, origin: Vector3, facing: Vector3, size: int, terrain: Terrain, seed_value: int) -> Dictionary:
	var k := CampKit.new()
	k._origin = origin
	var f := Vector3(facing.x, 0, facing.z)
	if f.length_squared() < 0.01: f = Vector3.FORWARD
	k._basis = Basis(Vector3.UP, atan2(-f.x, -f.z))
	k._terrain = terrain
	k._rng.seed = seed_value
	k.root = Node3D.new()
	k.root.name = "CampProps"
	match layout:
		&"roadblock": k._roadblock(size)
		&"squad": k._squad(size)
		_:
			if kind == &"pirate": k._pirate(size)
			else: k._bandit(size)
	return {"node": k.root, "cover": k.cover, "slots": k.slots, "ammo": k.ammo}


## Local camp coordinates (x right, z back from the facing) -> world, on the ground.
func _w(x: float, z: float, lift: float = 0.0) -> Vector3:
	var p := _origin + _basis * Vector3(x, 0, z)
	p.y = (_terrain.height_at(p.x, p.z) if _terrain else _origin.y) + lift
	return p


func _yaw(local_deg: float) -> float:
	return _basis.get_euler().y + deg_to_rad(local_deg)


func _slot(x: float, z: float, role: StringName, face_x: float = 0.0, face_z: float = -1.0, lift: float = 0.0) -> void:
	slots.append({"pos": _w(x, z, lift), "role": role, "facing": _basis * Vector3(face_x, 0, face_z)})


# ------------------------------------------------------------------------------ layouts
func _bandit(size: int) -> void:
	_campfire(0, 0)
	_tent(-7.0, 5.0, 20.0)
	_tent(6.5, 6.0, -15.0)
	if size >= 5: _tent(0.0, 10.0, 0.0)
	_crates(-4.5, -3.0, 25.0, 3)
	_crates(4.5, -2.5, -10.0, 2)
	_crates(1.0, -7.0, 5.0, 2)
	_sandbags(-9.0, -5.0, 35.0, 4.0)
	_sandbags(9.5, 2.0, -70.0, 3.5)
	_barrel(-6.0, 1.0); _barrel(-6.6, 1.8)
	ammo = _w(-2.2, 3.2)
	var top := 0.0
	if size >= 4:
		top = _tower(8.5, -6.5)
		_slot(8.5, -6.5, &"lookout", 0, -1, top)
	_slot(-1.5, 1.2, &"sitter", 0.8, -0.6)
	_slot(1.6, 1.0, &"sitter", -0.8, -0.6)
	_slot(-3.0, -5.5, &"guard", -0.2, -1)
	_slot(3.5, -5.0, &"patrol", 0.3, -1)
	_slot(-7.5, -2.0, &"guard", -0.6, -1)
	_slot(5.5, 3.5, &"patrol", 0.6, -1)
	_trim_slots(size)


func _pirate(size: int) -> void:
	_campfire(0, 1.0)
	_rowboat(0.5, -8.5, 12.0)
	_lean_to(-6.0, 5.0, 15.0)
	_barrel(-4.0, -2.0); _barrel(-4.8, -1.4); _barrel(-4.3, -3.0)
	_barrel(3.8, 1.2); _barrel(4.4, 2.0)
	_crates(4.5, -3.5, 15.0, 2)
	_crates(-2.5, 6.5, -20.0, 2)
	_pennant(6.0, 5.5)
	ammo = _w(1.8, 4.0)
	_slot(-1.4, 2.4, &"sitter", 0.7, -0.7)
	_slot(1.5, 2.2, &"sitter", -0.7, -0.7)
	_slot(-1.5, -6.5, &"guard", 0, -1)
	_slot(3.0, -5.5, &"patrol", 0.3, -1)
	_slot(-5.5, 0.5, &"guard", -0.5, -1)
	_slot(5.5, 4.0, &"patrol", 0.5, 0.5)
	_trim_slots(size)


func _roadblock(size: int) -> void:
	# the cart across the road, barrels and a log closing the gap
	_cart(0.0, 0.0, 78.0)
	_barrel(3.2, 0.6); _barrel(3.8, -0.2)
	_log(-3.8, 0.4, 95.0)
	_crates(5.5, 1.5, 10.0, 1)
	ammo = _w(0.0, 2.2)
	_slot(0.5, 1.8, &"guard", 0, -1)
	_slot(-2.6, 2.2, &"guard", -0.3, -1)
	_slot(4.0, 2.0, &"guard", 0.3, -1)
	_slot(-7.0, 5.0, &"patrol", -0.5, -1)
	_trim_slots(size)


func _squad(size: int) -> void:
	ammo = _w(0.0, 3.0)
	for i in range(size):
		_slot((i - (size - 1) * 0.5) * 3.0, 0.0, &"guard", 0, -1)


func _trim_slots(size: int) -> void:
	# the lookout (if any) stays; the rest fill up in order
	var keep: Array = []
	for s in slots:
		if s.role == &"lookout": keep.append(s)
	for s in slots:
		if keep.size() >= size: break
		if s.role != &"lookout": keep.append(s)
	slots = keep


# ------------------------------------------------------------------------------ props
func _body(pos: Vector3, yaw: float, surface: StringName) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	b.collision_mask = 0
	b.set_meta("surface", surface)
	b.position = pos
	b.rotation.y = yaw
	root.add_child(b)
	return b


func _box_shape(b: StaticBody3D, size: Vector3, at: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new(); sh.size = size
	cs.shape = sh; cs.position = at
	b.add_child(cs)


func _cover_round(centre: Vector3, radius: float, n: int = 4) -> void:
	for i in range(n):
		var a := TAU * i / n + 0.4
		var p := centre + Vector3(cos(a), 0, sin(a)) * radius
		p.y = _terrain.height_at(p.x, p.z) if _terrain else centre.y
		cover.append(p)


func _campfire(x: float, z: float) -> void:
	var p := _w(x, z)
	var n := Node3D.new(); n.position = p; root.add_child(n)
	var stone := Mats.solid(Color(0.52, 0.49, 0.45), 0.95)
	for i in range(9):
		var a := TAU * i / 9.0
		n.add_child(Mats.sphere(0.13, stone, Vector3(cos(a) * 0.55, 0.05, sin(a) * 0.55), Vector3(1.2, 0.7, 1.0), 8))
	var charred := Mats.solid(Color(0.16, 0.12, 0.10), 0.9)
	for i in range(3):
		n.add_child(Mats.cylinder(0.055, 0.8, charred, Vector3(0, 0.12, 0), Vector3(80, i * 60.0, 0), 6))
	# flames, embers and a flickering light that carries the camp at night (world/sky, M-12)
	CampfireGlow.attach(n, Vector3.ZERO, 0.8)
	# logs to sit on
	for side in [-1.0, 1.0]:
		var lp := _w(x + side * 1.9, z + 0.4)
		var b := _body(lp, _yaw(90.0 + side * 12.0), &"wood")
		b.add_child(Mats.cylinder(0.17, 1.5, Mats.solid(DARK_WOOD, 0.9), Vector3(0, 0.16, 0), Vector3(0, 0, 90), 8))
		_box_shape(b, Vector3(1.5, 0.32, 0.32), Vector3(0, 0.16, 0))


func _tent(x: float, z: float, yaw_deg: float) -> void:
	var p := _w(x, z)
	var b := _body(p, _yaw(yaw_deg), &"cloth")
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := 1.4; var h := 1.7; var l := 2.6
	var ridge_a := Vector3(0, h, -l * 0.5); var ridge_b := Vector3(0, h, l * 0.5)
	for side in [-1.0, 1.0]:
		var ga := Vector3(side * w, 0.02, -l * 0.5); var gb := Vector3(side * w, 0.02, l * 0.5)
		for v in [ridge_a, ga, gb, ridge_a, gb, ridge_b]: st.add_vertex(v)
	# back wall closed, front flap half open
	for v in [ridge_b, Vector3(-w, 0.02, l * 0.5), Vector3(w, 0.02, l * 0.5)]: st.add_vertex(v)
	for v in [ridge_a, Vector3(-w, 0.02, -l * 0.5), Vector3(-w * 0.2, 0.02, -l * 0.5 - 0.15)]: st.add_vertex(v)
	st.generate_normals()
	var mi := MeshInstance3D.new(); mi.mesh = st.commit()
	var canvas := Mats.solid(CANVAS.darkened(_rng.randf_range(0.0, 0.15)), 0.95).duplicate()
	canvas.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = canvas
	b.add_child(mi)
	var pole := Mats.solid(DARK_WOOD, 0.9)
	for zz in [-l * 0.5 - 0.05, l * 0.5 + 0.05]:
		b.add_child(Mats.cylinder(0.035, h + 0.2, pole, Vector3(0, (h + 0.2) * 0.5, zz), Vector3.ZERO, 6))
	b.add_child(Mats.cylinder(0.025, l + 0.3, pole, Vector3(0, h + 0.02, 0), Vector3(90, 0, 0), 6))
	_box_shape(b, Vector3(w * 1.6, h * 0.7, l), Vector3(0, h * 0.35, 0))
	_cover_round(p, 2.2, 4)


func _lean_to(x: float, z: float, yaw_deg: float) -> void:
	var p := _w(x, z)
	var b := _body(p, _yaw(yaw_deg), &"cloth")
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a := Vector3(-1.8, 2.0, -1.0); var bb := Vector3(1.8, 2.0, -1.0)
	var c := Vector3(1.8, 0.05, 1.3); var d := Vector3(-1.8, 0.05, 1.3)
	for v in [a, bb, c, a, c, d]: st.add_vertex(v)
	st.generate_normals()
	var mi := MeshInstance3D.new(); mi.mesh = st.commit()
	var sail := Mats.solid(SAILCLOTH, 0.95).duplicate(); sail.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = sail
	b.add_child(mi)
	var pole := Mats.solid(Color(0.62, 0.55, 0.45), 0.95)
	for px in [-1.8, 1.8]:
		b.add_child(Mats.cylinder(0.05, 2.1, pole, Vector3(px, 1.05, -1.0), Vector3.ZERO, 6))
	b.add_child(Mats.cylinder(0.04, 3.8, pole, Vector3(0, 2.0, -1.0), Vector3(0, 0, 90), 6))
	_box_shape(b, Vector3(3.6, 1.0, 1.6), Vector3(0, 0.5, 0.4))
	_cover_round(p, 2.4, 3)


func _crates(x: float, z: float, yaw_deg: float, count: int) -> void:
	var p := _w(x, z)
	var b := _body(p, _yaw(yaw_deg), &"wood")
	var wood := Mats.solid(WOOD.darkened(_rng.randf_range(0.0, 0.2)), 0.9)
	var slat := Mats.solid(DARK_WOOD, 0.9)
	var positions := [Vector3(0, 0.4, 0), Vector3(0.85, 0.4, 0.1), Vector3(0.4, 1.2, 0.05), Vector3(-0.85, 0.4, -0.05)]
	for i in range(mini(count + 1, positions.size())):
		var c: Vector3 = positions[i]
		var s := 0.8 if i != 2 else 0.7
		b.add_child(Mats.box(Vector3(s, s, s), wood, c, Vector3(0, _rng.randf_range(-8, 8), 0)))
		for edge in [-1.0, 1.0]:
			b.add_child(Mats.box(Vector3(s + 0.02, 0.08, 0.08), slat, c + Vector3(0, edge * (s * 0.5 - 0.04), s * 0.5)))
		_box_shape(b, Vector3(s, s, s), c)
	_cover_round(p, 1.5, 4)


func _barrel(x: float, z: float) -> void:
	var p := _w(x, z)
	var b := _body(p, _yaw(_rng.randf() * 360.0), &"wood")
	var staves := Mats.solid(Color(0.45, 0.30, 0.18).darkened(_rng.randf_range(0.0, 0.2)), 0.9)
	var hoop := Mats.solid(IRON, 0.5, 0.6)
	b.add_child(Mats.cylinder(0.30, 0.9, staves, Vector3(0, 0.45, 0), Vector3.ZERO, 14))
	b.add_child(Mats.sphere(0.33, staves, Vector3(0, 0.45, 0), Vector3(1, 1.25, 1), 14))
	for hy in [0.12, 0.45, 0.78]:
		b.add_child(Mats.torus(0.30, 0.34, hoop, Vector3(0, hy, 0), Vector3.ZERO, Vector3(1, 0.4, 1)))
	var cs := CollisionShape3D.new(); var sh := CylinderShape3D.new(); sh.radius = 0.33; sh.height = 0.9
	cs.shape = sh; cs.position = Vector3(0, 0.45, 0); b.add_child(cs)
	_cover_round(p, 0.9, 3)


func _sandbags(x: float, z: float, yaw_deg: float, length: float) -> void:
	var p := _w(x, z)
	var b := _body(p, _yaw(yaw_deg), &"dust")
	var bag := Mats.solid(SAND, 0.98)
	var n := int(length / 0.55)
	for row in range(3):
		for i in range(n - (row % 2)):
			var bx := -length * 0.5 + 0.3 + i * 0.55 + (0.27 if row % 2 == 1 else 0.0)
			b.add_child(Mats.capsule(0.15, 0.55, bag, Vector3(bx, 0.14 + row * 0.25, 0), Vector3(0, 0, 90), Vector3(1, 0.75, 1.1)))
	_box_shape(b, Vector3(length, 0.9, 0.5), Vector3(0, 0.45, 0))
	var wall := Basis(Vector3.UP, b.rotation.y)
	for i in range(3):
		for side in [-1.0, 1.0]:
			var q := p + wall * Vector3(-length * 0.35 + i * length * 0.35, 0, side * 0.8)
			q.y = _terrain.height_at(q.x, q.z) if _terrain else p.y
			cover.append(q)


## A four-post lookout with a railed platform; returns the platform height.
func _tower(x: float, z: float) -> float:
	var p := _w(x, z)
	var h := 3.2
	var b := _body(p, _yaw(0.0), &"wood")
	var post := Mats.solid(DARK_WOOD, 0.9)
	var plank := Mats.solid(WOOD, 0.9)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			b.add_child(Mats.cylinder(0.08, h + 1.1, post, Vector3(sx * 1.0, (h + 1.1) * 0.5, sz * 1.0), Vector3.ZERO, 6))
			var cs := CollisionShape3D.new(); var sh := CylinderShape3D.new(); sh.radius = 0.09; sh.height = h
			cs.shape = sh; cs.position = Vector3(sx * 1.0, h * 0.5, sz * 1.0); b.add_child(cs)
	# cross braces
	for sx in [-1.0, 1.0]:
		b.add_child(Mats.box(Vector3(0.06, 0.08, 2.9), post, Vector3(sx, h * 0.45, 0), Vector3(48, 0, 0)))
	b.add_child(Mats.box(Vector3(2.3, 0.12, 2.3), plank, Vector3(0, h, 0)))
	_box_shape(b, Vector3(2.3, 0.12, 2.3), Vector3(0, h, 0))
	# rails: the lookout crouches behind them
	for r in [[Vector3(0, h + 0.5, -1.1), Vector3(2.2, 0.9, 0.06)], [Vector3(-1.1, h + 0.5, 0), Vector3(0.06, 0.9, 2.2)], [Vector3(1.1, h + 0.5, 0), Vector3(0.06, 0.9, 2.2)]]:
		b.add_child(Mats.box(r[1], plank, r[0]))
		_box_shape(b, r[1], r[0])
	# roof
	b.add_child(Mats.box(Vector3(2.5, 0.06, 2.5), Mats.solid(CANVAS.darkened(0.2), 0.95), Vector3(0, h + 1.12, 0), Vector3(6, 0, 0)))
	# ladder on the back
	for lx in [-0.25, 0.25]:
		b.add_child(Mats.box(Vector3(0.05, h + 0.2, 0.05), post, Vector3(lx, h * 0.5, 1.25), Vector3(-8, 0, 0)))
	for i in range(8):
		b.add_child(Mats.box(Vector3(0.55, 0.04, 0.05), post, Vector3(0, 0.35 + i * 0.4, 1.2 + i * 0.4 * 0.14 - 0.25)))
	return h + 0.06


func _rowboat(x: float, z: float, yaw_deg: float) -> void:
	var p := _w(x, z)
	var b := _body(p, _yaw(yaw_deg), &"wood")
	b.rotation.z = deg_to_rad(8.0)
	var k := MeshKit.new()
	k.loft(MeshKit.sections([[1.9, 0.62, 0.30, 0.05, 2.0], [1.6, 0.70, 0.05, 0.45, 2.2], [0.6, 0.72, 0.0, 0.75, 2.4], [-0.6, 0.72, 0.0, 0.78, 2.4],
		[-1.5, 0.70, 0.05, 0.62, 2.4], [-1.9, 0.66, 0.12, 0.40, 2.6]], 3, 24))
	var mi := MeshInstance3D.new(); mi.mesh = k.commit(null, Mats.solid(Color(0.36, 0.44, 0.50), 0.9))
	b.add_child(mi)
	# the inside: a darker floor and thwarts, a pair of oars
	var inner := Mats.solid(Color(0.40, 0.30, 0.20), 0.9)
	b.add_child(Mats.box(Vector3(1.1, 0.02, 2.5), inner, Vector3(0, 0.725, -0.1)))
	for tz in [-0.8, 0.3]:
		b.add_child(Mats.box(Vector3(1.35, 0.05, 0.2), Mats.solid(WOOD, 0.9), Vector3(0, 0.75, tz)))
	for side in [-1.0, 1.0]:
		b.add_child(Mats.cylinder(0.03, 2.4, Mats.solid(Color(0.7, 0.6, 0.45), 0.9), Vector3(side * 0.45, 0.72, 0.2), Vector3(90, side * 10.0, 0), 6))
	_box_shape(b, Vector3(1.5, 0.75, 3.6), Vector3(0, 0.37, 0))
	_cover_round(p, 2.3, 5)


func _pennant(x: float, z: float) -> void:
	var p := _w(x, z)
	var n := Node3D.new(); n.position = p; root.add_child(n)
	n.add_child(Mats.cylinder(0.05, 4.5, Mats.solid(DARK_WOOD, 0.9), Vector3(0, 2.25, 0), Vector3.ZERO, 6))
	var flag := Mats.solid(Color(0.1, 0.1, 0.1), 0.95).duplicate(); flag.cull_mode = BaseMaterial3D.CULL_DISABLED
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in [Vector3(0, 4.4, 0), Vector3(1.4, 4.1, 0.1), Vector3(0, 3.6, 0)]: st.add_vertex(v)
	st.generate_normals()
	var mi := MeshInstance3D.new(); mi.mesh = st.commit(); mi.material_override = flag; n.add_child(mi)
	n.add_child(Mats.box(Vector3(0.9, 0.08, 0.02), Mats.solid(Color(0.7, 0.12, 0.1), 0.9), Vector3(0.45, 4.1, 0.02), Vector3(0, 0, -12)))


func _cart(x: float, z: float, yaw_deg: float) -> void:
	var p := _w(x, z)
	var b := _body(p, _yaw(yaw_deg), &"wood")
	b.rotation.z = deg_to_rad(4.0)
	var wood := Mats.solid(WOOD, 0.9)
	var dark := Mats.solid(DARK_WOOD, 0.9)
	b.add_child(Mats.box(Vector3(1.6, 0.12, 3.0), wood, Vector3(0, 0.75, 0)))
	for side in [-1.0, 1.0]:
		b.add_child(Mats.box(Vector3(0.08, 0.5, 3.0), wood, Vector3(side * 0.78, 1.05, 0)))
		b.add_child(Mats.torus(0.42, 0.52, dark, Vector3(side * 0.9, 0.52, 0.2), Vector3(0, 0, 90)))
		for i in range(6):
			b.add_child(Mats.box(Vector3(0.05, 0.9, 0.05), dark, Vector3(side * 0.9, 0.52, 0.2), Vector3(i * 30.0, 0, 0)))
		b.add_child(Mats.box(Vector3(0.07, 0.07, 2.2), dark, Vector3(side * 0.35, 0.55, -2.4), Vector3(-14, 0, 0)))
	b.add_child(Mats.box(Vector3(0.1, 0.5, 3.0), wood, Vector3(0, 1.05, 1.5), Vector3(0, 90, 0)))
	# a tarp over sacks
	b.add_child(Mats.sphere(0.7, Mats.solid(CANVAS.darkened(0.15), 0.95), Vector3(0, 1.0, 0.2), Vector3(1.0, 0.55, 1.8), 12))
	_box_shape(b, Vector3(1.7, 1.2, 3.1), Vector3(0, 0.75, 0))
	_cover_round(p, 2.2, 6)


func _log(x: float, z: float, yaw_deg: float) -> void:
	var p := _w(x, z)
	var b := _body(p, _yaw(yaw_deg), &"wood")
	b.add_child(Mats.cylinder(0.32, 4.0, Mats.solid(Color(0.42, 0.33, 0.24), 0.95), Vector3(0, 0.3, 0), Vector3(0, 0, 90), 10))
	_box_shape(b, Vector3(4.0, 0.62, 0.62), Vector3(0, 0.3, 0))
	_cover_round(p, 1.2, 4)
