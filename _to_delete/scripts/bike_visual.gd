extends Node3D
## Procedural bike + rider visual, built from primitives to match the reference sheets:
## red fairing with a cream nose cone & round headlight, riveted cream windscreen frame,
## tan seat, chrome rack + twin exhausts, knobby wheels, red swingarm; the rider is a boy
## with orange hair, blue shirt, coral neckerchief, tan trousers, suspenders and brown boots.

const RED := Color(0.86, 0.23, 0.17)
const CREAM := Color(0.94, 0.89, 0.79)
const TAN := Color(0.80, 0.62, 0.40)
const RUBBER := Color(0.13, 0.12, 0.11)
const DARK := Color(0.22, 0.22, 0.24)
const SKIN := Color(0.96, 0.82, 0.68)
const HAIR := Color(0.80, 0.45, 0.16)
const SHIRT := Color(0.55, 0.59, 0.80)
const SCARF := Color(0.90, 0.42, 0.34)
const TROUSER := Color(0.87, 0.76, 0.52)
const BOOT := Color(0.40, 0.25, 0.16)
const STRAP := Color(0.93, 0.85, 0.58)

const WHEEL_R := 0.32

var lean_pivot: Node3D
var fork_pivot: Node3D
var front_wheel: Node3D
var rear_wheel: Node3D
var rider: Node3D
var head: Node3D
var package: Node3D
var wings: Node3D
var _wing_open := 0.0
var _prop: Node3D
var headlight_mat: StandardMaterial3D
var _wheel_spin := 0.0


func _ready() -> void:
	lean_pivot = Node3D.new()
	lean_pivot.name = "LeanPivot"
	add_child(lean_pivot)
	_build_bike(lean_pivot)
	_build_rider(lean_pivot)
	_build_package(lean_pivot)
	_build_wings(lean_pivot)


func _chrome() -> StandardMaterial3D:
	return Mats.solid(Color(0.86, 0.87, 0.90), 0.38, 0.45)


func _build_bike(p: Node3D) -> void:
	var red := Mats.solid(RED, 0.45)
	var cream := Mats.solid(CREAM, 0.5)
	var chrome := _chrome()
	var rubber := Mats.solid(RUBBER, 0.95)
	var dark := Mats.solid(DARK, 0.7)
	var tan := Mats.solid(TAN, 0.8)

	# Rear wheel + swingarm
	rear_wheel = _make_wheel(rubber, chrome)
	rear_wheel.position = Vector3(0, WHEEL_R, 0.70)
	p.add_child(rear_wheel)
	p.add_child(Mats.box(Vector3(0.09, 0.09, 0.62), red, Vector3(0.16, WHEEL_R, 0.42)))
	p.add_child(Mats.box(Vector3(0.09, 0.09, 0.62), red, Vector3(-0.16, WHEEL_R, 0.42)))
	# rear shock
	p.add_child(Mats.limb(Vector3(0.2, 0.38, 0.62), Vector3(0.2, 0.92, 0.42), 0.045, chrome))
	p.add_child(Mats.limb(Vector3(0.2, 0.42, 0.60), Vector3(0.2, 0.7, 0.51), 0.07, chrome))

	# Engine block (mostly hidden by the fairing)
	p.add_child(Mats.box(Vector3(0.40, 0.36, 0.5), dark, Vector3(0, 0.48, 0.05)))
	# Fairing / body shell
	p.add_child(Mats.capsule(0.30, 1.35, red, Vector3(0, 0.74, -0.15), Vector3(90, 0, 0), Vector3(1.05, 1.0, 1.0)))
	# belly panel with the logo
	p.add_child(Mats.capsule(0.30, 0.95, red, Vector3(0, 0.56, 0.05), Vector3(90, 0, 0), Vector3(1.25, 0.95, 1.0)))
	# tank
	p.add_child(Mats.sphere(0.3, red, Vector3(0, 0.95, -0.05), Vector3(0.95, 0.65, 1.35)))
	# Nose cone + headlight
	p.add_child(Mats.sphere(0.27, cream, Vector3(0, 0.83, -0.92), Vector3(0.92, 0.9, 1.15)))
	headlight_mat = Mats.solid(Color(1.0, 0.97, 0.85), 0.2, 0.1, Color(1.0, 0.9, 0.6))
	p.add_child(Mats.cylinder(0.13, 0.05, headlight_mat, Vector3(0, 0.84, -1.20), Vector3(90, 0, 0)))
	p.add_child(Mats.torus(0.12, 0.15, chrome, Vector3(0, 0.84, -1.19), Vector3(90, 0, 0)))
	# vents on the fairing sides
	for i in range(4):
		p.add_child(Mats.box(Vector3(0.02, 0.05, 0.09), dark, Vector3(0.31, 0.95, -0.72 + i * 0.12), Vector3(0, 0, 0)))
		p.add_child(Mats.box(Vector3(0.02, 0.05, 0.09), dark, Vector3(-0.31, 0.95, -0.72 + i * 0.12), Vector3(0, 0, 0)))
	# small side indicator bars
	p.add_child(Mats.capsule(0.03, 0.14, cream, Vector3(0.33, 0.78, -0.55), Vector3(90, 0, 0)))
	p.add_child(Mats.capsule(0.03, 0.14, cream, Vector3(-0.33, 0.78, -0.55), Vector3(90, 0, 0)))
	# Windscreen + cream riveted frame
	var ws := Node3D.new()
	ws.position = Vector3(0, 1.30, -0.62)
	ws.rotation_degrees = Vector3(-24, 0, 0)
	ws.add_child(Mats.sphere(0.30, Mats.glass(Color(0.80, 0.90, 1.0, 0.22)), Vector3(0, 0.08, 0), Vector3(0.85, 1.25, 0.12)))
	ws.add_child(Mats.torus(0.27, 0.305, cream, Vector3(0, 0.08, 0), Vector3(90, 0, 0), Vector3(0.85, 1.25, 1.0)))
	# rivets around the frame
	var rivet := Mats.solid(Color(0.6, 0.6, 0.62), 0.4, 0.5)
	for i in range(10):
		var a := PI * 0.1 + PI * 0.8 * i / 9.0
		ws.add_child(Mats.sphere(0.014, rivet, Vector3(cos(a) * 0.29 * 0.85, 0.08 + sin(a) * 0.29 * 1.25, -0.03), Vector3.ONE, 6))
	p.add_child(ws)
	# Seat
	p.add_child(Mats.capsule(0.15, 0.95, tan, Vector3(0, 0.99, 0.52), Vector3(90, 0, 0), Vector3(1.25, 0.6, 1.0)))
	# Rear rack (chrome loop)
	p.add_child(Mats.box(Vector3(0.05, 0.05, 0.5), chrome, Vector3(0.22, 0.98, 1.08)))
	p.add_child(Mats.box(Vector3(0.05, 0.05, 0.5), chrome, Vector3(-0.22, 0.98, 1.08)))
	p.add_child(Mats.box(Vector3(0.49, 0.05, 0.05), chrome, Vector3(0, 0.98, 1.32)))
	p.add_child(Mats.box(Vector3(0.49, 0.05, 0.05), chrome, Vector3(0, 0.98, 0.84)))
	p.add_child(Mats.box(Vector3(0.44, 0.02, 0.45), red, Vector3(0, 0.95, 1.08)))
	# rack support struts
	p.add_child(Mats.limb(Vector3(0.22, 0.96, 1.3), Vector3(0.2, 0.55, 0.85), 0.02, chrome))
	p.add_child(Mats.limb(Vector3(-0.22, 0.96, 1.3), Vector3(-0.2, 0.55, 0.85), 0.02, chrome))
	# twin exhausts
	for sx in [-0.17, 0.17]:
		p.add_child(Mats.cylinder(0.055, 0.42, chrome, Vector3(sx, 0.74, 0.98), Vector3(90, 0, 0)))
		p.add_child(Mats.cylinder(0.03, 0.45, chrome, Vector3(sx, 0.64, 0.62), Vector3(75, 0, 0)))
	# tail light
	p.add_child(Mats.cylinder(0.07, 0.03, Mats.solid(Color(0.95, 0.35, 0.15), 0.3, 0, Color(0.9, 0.2, 0.05)), Vector3(0, 0.86, 1.33), Vector3(90, 0, 0)))
	# foot pegs
	p.add_child(Mats.cylinder(0.02, 0.9, chrome, Vector3(0, 0.38, 0.22), Vector3(0, 0, 90)))
	# logo decals
	var decal := Mats.decal_material(Mats.logo_texture())
	var q := QuadMesh.new()
	q.size = Vector2(0.44, 0.44)
	p.add_child(Mats.mesh_node(q, decal, Vector3(0.395, 0.56, 0.12), Vector3(0, 90, 0)))
	p.add_child(Mats.mesh_node(q, decal, Vector3(-0.395, 0.56, 0.12), Vector3(0, -90, 0), Vector3(-1, 1, 1)))

	# Front fork assembly (steers)
	fork_pivot = Node3D.new()
	fork_pivot.position = Vector3(0, 1.05, -0.52)
	fork_pivot.rotation_degrees = Vector3(22, 0, 0)  # rake: axle lands ~0.3 m ahead of the steering head
	p.add_child(fork_pivot)
	for sx in [-0.13, 0.13]:
		fork_pivot.add_child(Mats.cylinder(0.035, 0.85, chrome, Vector3(sx, -0.45, 0)))
		fork_pivot.add_child(Mats.cylinder(0.045, 0.3, red, Vector3(sx, -0.25, 0)))
	front_wheel = _make_wheel(rubber, chrome)
	front_wheel.position = Vector3(0, -0.79, 0.0)
	fork_pivot.add_child(front_wheel)
	# handlebars
	fork_pivot.add_child(Mats.cylinder(0.022, 0.72, chrome, Vector3(0, 0.08, 0.05), Vector3(0, 0, 90)))
	fork_pivot.add_child(Mats.cylinder(0.03, 0.14, rubber, Vector3(0.33, 0.08, 0.05), Vector3(0, 0, 90)))
	fork_pivot.add_child(Mats.cylinder(0.03, 0.14, rubber, Vector3(-0.33, 0.08, 0.05), Vector3(0, 0, 90)))
	# mirrors
	for sx in [-0.28, 0.28]:
		fork_pivot.add_child(Mats.limb(Vector3(sx, 0.09, 0.05), Vector3(sx * 1.35, 0.32, 0.02), 0.012, chrome))
		fork_pivot.add_child(Mats.sphere(0.055, chrome, Vector3(sx * 1.35, 0.34, 0.02), Vector3(1, 1, 0.4)))
	# front mudguard
	fork_pivot.add_child(Mats.torus(0.33, 0.39, red, Vector3(0, -0.76, 0), Vector3(0, 0, 90), Vector3(0.55, 1, 0.55)))


func _make_wheel(rubber: Material, chrome: Material) -> Node3D:
	var w := Node3D.new()
	w.add_child(Mats.torus(0.20, WHEEL_R, rubber, Vector3.ZERO, Vector3(0, 0, 90), Vector3(1, 1.0, 1)))
	# tread knobs
	var knob := Mats.solid(RUBBER.lightened(0.05), 0.95)
	for i in range(14):
		var a := TAU * i / 14.0
		var k := Mats.box(Vector3(0.16, 0.05, 0.06), knob, Vector3(0, cos(a) * (WHEEL_R - 0.005), sin(a) * (WHEEL_R - 0.005)), Vector3(-rad_to_deg(a), 0, 0))
		w.add_child(k)
	# rim + spokes disc
	var spoke := StandardMaterial3D.new()
	spoke.albedo_color = Color(0.85, 0.86, 0.88, 0.55)
	spoke.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spoke.metallic = 0.7
	spoke.roughness = 0.4
	spoke.cull_mode = BaseMaterial3D.CULL_DISABLED
	w.add_child(Mats.cylinder(0.21, 0.02, spoke, Vector3.ZERO, Vector3(0, 0, 90), 20))
	w.add_child(Mats.torus(0.19, 0.215, chrome, Vector3.ZERO, Vector3(0, 0, 90)))
	w.add_child(Mats.cylinder(0.075, 0.12, chrome, Vector3.ZERO, Vector3(0, 0, 90)))
	# actual spokes: 8 thin cylinders
	for i in range(8):
		var a := PI * i / 8.0
		w.add_child(Mats.cylinder(0.006, 0.4, chrome, Vector3.ZERO, Vector3(rad_to_deg(a) + 90, 0, 0), 4))
	return w


func _build_rider(p: Node3D) -> void:
	rider = Node3D.new()
	rider.name = "Rider"
	p.add_child(rider)
	var skin := Mats.solid(SKIN, 0.8)
	var hair := Mats.solid(HAIR, 0.75)
	var shirt := Mats.solid(SHIRT, 0.85)
	var scarf := Mats.solid(SCARF, 0.8)
	var trouser := Mats.solid(TROUSER, 0.9)
	var boot := Mats.solid(BOOT, 0.8)
	var strap := Mats.solid(STRAP, 0.9)
	var hip := Vector3(0, 1.08, 0.38)
	# hips / seat contact
	rider.add_child(Mats.sphere(0.15, trouser, hip + Vector3(0, 0.02, 0.02), Vector3(1.2, 0.7, 1.05)))
	# torso (leaning forward toward the bars)
	var torso := Mats.capsule(0.145, 0.44, shirt, hip + Vector3(0, 0.37, -0.07), Vector3(-11, 0, 0), Vector3(1.15, 1.0, 0.75))
	rider.add_child(torso)
	# suspenders
	for sx in [-0.07, 0.07]:
		rider.add_child(Mats.box(Vector3(0.035, 0.42, 0.012), strap, hip + Vector3(sx, 0.37, -0.215), Vector3(-11, 0, 0)))
	# neck + scarf
	rider.add_child(Mats.cylinder(0.05, 0.1, skin, hip + Vector3(0, 0.66, -0.20)))
	rider.add_child(Mats.sphere(0.09, scarf, hip + Vector3(0, 0.63, -0.20), Vector3(1.4, 0.55, 1.2)))
	# head
	head = Node3D.new()
	head.position = hip + Vector3(0, 0.84, -0.16)
	rider.add_child(head)
	head.add_child(Mats.sphere(0.155, skin, Vector3.ZERO, Vector3(0.95, 1.05, 0.95)))
	head.add_child(Mats.sphere(0.17, hair, Vector3(0, 0.055, 0.02), Vector3(1.0, 0.85, 1.0)))
	head.add_child(Mats.sphere(0.09, hair, Vector3(0.0, 0.15, -0.02), Vector3(1.4, 0.7, 1.2)))
	head.add_child(Mats.sphere(0.06, hair, Vector3(0.09, 0.14, -0.05), Vector3(1.0, 1.3, 1.0)))
	head.add_child(Mats.sphere(0.06, hair, Vector3(-0.08, 0.15, -0.03), Vector3(1.0, 1.3, 1.0)))
	# eyes (tiny)
	var eye := Mats.solid(Color(0.25, 0.16, 0.1), 0.4)
	head.add_child(Mats.sphere(0.018, eye, Vector3(0.05, 0.01, -0.13)))
	head.add_child(Mats.sphere(0.018, eye, Vector3(-0.05, 0.01, -0.13)))
	# arms to the handlebars
	for sx in [-1.0, 1.0]:
		var shoulder := hip + Vector3(sx * 0.19, 0.58, -0.16)
		var elbow := hip + Vector3(sx * 0.27, 0.35, -0.55)
		var hand := Vector3(sx * 0.33, 1.13, -0.60)
		rider.add_child(Mats.limb(shoulder, elbow, 0.06, shirt))
		rider.add_child(Mats.limb(elbow, hand, 0.05, skin))
		rider.add_child(Mats.sphere(0.055, boot, hand, Vector3(1, 0.8, 1.2)))
		# legs: thigh forward and down, shin down to the peg
		var knee := hip + Vector3(sx * 0.30, -0.08, -0.30)
		var foot := Vector3(sx * 0.36, 0.43, 0.24)
		rider.add_child(Mats.limb(hip + Vector3(sx * 0.1, 0, 0), knee, 0.068, trouser))
		rider.add_child(Mats.limb(knee, foot, 0.052, trouser))
		rider.add_child(Mats.box(Vector3(0.12, 0.11, 0.27), boot, foot + Vector3(0, -0.03, -0.04)))


func _build_package(p: Node3D) -> void:
	package = Node3D.new()
	package.name = "Package"
	package.position = Vector3(0, 0.99, 1.08)
	var crate := Mats.solid(Color(0.55, 0.36, 0.22), 0.85)
	var brass := Mats.solid(Color(0.85, 0.72, 0.35), 0.4, 0.6)
	var paper := Mats.solid(Color(0.74, 0.80, 0.62), 0.9)
	var paper2 := Mats.solid(Color(0.90, 0.85, 0.70), 0.9)
	var twine := Mats.solid(Color(0.85, 0.75, 0.5), 0.9)
	package.add_child(Mats.box(Vector3(0.46, 0.3, 0.44), crate, Vector3(0, 0.16, 0)))
	for sx in [-0.23, 0.23]:
		for sz in [-0.22, 0.22]:
			package.add_child(Mats.box(Vector3(0.05, 0.31, 0.05), brass, Vector3(sx, 0.16, sz)))
	package.add_child(Mats.box(Vector3(0.36, 0.2, 0.28), paper, Vector3(0.04, 0.42, 0.02)))
	package.add_child(Mats.box(Vector3(0.38, 0.03, 0.03), twine, Vector3(0.04, 0.53, 0.02)))
	package.add_child(Mats.box(Vector3(0.03, 0.03, 0.30), twine, Vector3(0.04, 0.53, 0.02)))
	package.add_child(Mats.box(Vector3(0.2, 0.14, 0.18), paper2, Vector3(-0.1, 0.59, -0.05)))
	package.visible = false
	p.add_child(package)


func _build_wings(p: Node3D) -> void:
	# Fold-out wings like the reference flight shot: thick tapered red wings with cream tips and
	# the courier logo, hinged at the rear frame just above the rack, wire-braced to the tail;
	# twin cream tail fins on a short boom. Folded, they lie swept back along the bike.
	wings = Node3D.new()
	wings.name = "Wings"
	wings.position = Vector3(0, 0.88, 0.55)
	p.add_child(wings)
	var red := Mats.solid(RED, 0.5)
	var cream := Mats.solid(CREAM, 0.5)
	var chrome := _chrome()
	var decal := Mats.decal_material(Mats.logo_texture())
	for side in [-1.0, 1.0]:
		var hinge := Node3D.new()
		hinge.name = "WingL" if side < 0 else "WingR"
		hinge.position = Vector3(side * 0.28, 0, 0)
		wings.add_child(hinge)
		var w := Node3D.new()
		w.name = "Blade"
		hinge.add_child(w)
		# root section: thick aerofoil (box + rounded leading edge), tapering outboard
		w.add_child(Mats.box(Vector3(1.5, 0.16, 0.95), red, Vector3(side * 0.75, 0, 0.0), Vector3(0, side * -8.0, 0)))
		w.add_child(Mats.cylinder(0.085, 1.5, red, Vector3(side * 0.75, 0, -0.42), Vector3(0, 0, 90), 10))
		w.add_child(Mats.box(Vector3(1.4, 0.10, 0.72), red, Vector3(side * 2.15, 0.02, 0.12), Vector3(0, side * -12.0, 0)))
		w.add_child(Mats.cylinder(0.055, 1.4, red, Vector3(side * 2.15, 0.02, -0.22), Vector3(0, 0, 90), 8))
		w.add_child(Mats.box(Vector3(0.5, 0.09, 0.62), cream, Vector3(side * 3.05, 0.03, 0.22), Vector3(0, side * -12.0, 0)))
		w.add_child(Mats.sphere(0.2, cream, Vector3(side * 3.28, 0.03, 0.25), Vector3(0.7, 0.3, 1.3)))
		var q := QuadMesh.new(); q.size = Vector2(0.55, 0.55)
		w.add_child(Mats.mesh_node(q, decal, Vector3(side * 2.1, 0.08, 0.1), Vector3(-90, 0, 0)))
		# bracing: strut down to the swingarm pivot, wires to the tail
		w.add_child(Mats.limb(Vector3(0, -0.5, 0.15), Vector3(side * 1.7, -0.04, 0.05), 0.02, chrome))
		w.add_child(Mats.limb(Vector3(side * 2.9, 0.0, 0.2), Vector3(side * 0.1, 0.05, 1.3), 0.006, chrome))
	# tail boom with twin cream fins and a small elevator
	var tail := Node3D.new()
	tail.name = "Tail"
	tail.position = Vector3(0, 0.05, 0.75)
	wings.add_child(tail)
	tail.add_child(Mats.cylinder(0.035, 1.1, chrome, Vector3(0, 0, 0.55), Vector3(90, 0, 0), 8))
	tail.add_child(Mats.box(Vector3(1.5, 0.06, 0.42), red, Vector3(0, 0.02, 1.05)))
	for side in [-0.62, 0.62]:
		tail.add_child(Mats.box(Vector3(0.05, 0.42, 0.42), cream, Vector3(side, 0.24, 1.05)))
		tail.add_child(Mats.box(Vector3(0.06, 0.16, 0.44), red, Vector3(side, 0.45, 1.05)))
	# pusher propeller behind the seat
	_prop = Node3D.new()
	_prop.position = Vector3(0, 0.12, 0.62)
	tail.add_child(_prop)
	_prop.add_child(Mats.box(Vector3(1.0, 0.09, 0.02), Mats.solid(Color(0.3, 0.2, 0.12), 0.7), Vector3.ZERO))
	_prop.add_child(Mats.box(Vector3(0.09, 1.0, 0.02), Mats.solid(Color(0.3, 0.2, 0.12), 0.7), Vector3.ZERO))
	_prop.add_child(Mats.sphere(0.07, chrome, Vector3.ZERO))
	wings.visible = false


func set_rider_visible(v: bool) -> void:
	if rider: rider.visible = v


func set_package_visible(v: bool) -> void:
	package.visible = v


func update_visual(bike: Node, delta: float) -> void:
	lean_pivot.rotation.z = bike.lean
	# wings fold in / out: each wing swings on its hinge from swept-back-and-up to spread with a
	# little dihedral; the tail boom telescopes out behind the seat
	var target := 1.0 if bike.wings_out else 0.0
	_wing_open = move_toward(_wing_open, target, delta * 1.1)
	if wings:
		wings.visible = _wing_open > 0.01
		var e := _wing_open * _wing_open * (3.0 - 2.0 * _wing_open)
		for side in [-1.0, 1.0]:
			var hinge: Node3D = wings.get_node("WingL" if side < 0 else "WingR")
			# folded: rotated back 80° about Y and tucked up 40°; open: 4° dihedral
			hinge.rotation_degrees = Vector3(0, lerpf(side * 80.0, 0.0, e), lerpf(side * 40.0, side * 4.0, e))
			hinge.scale = Vector3(lerpf(0.55, 1.0, e), 1, 1)
		var tail: Node3D = wings.get_node("Tail")
		tail.scale = Vector3(lerpf(0.3, 1.0, e), lerpf(0.3, 1.0, e), lerpf(0.15, 1.0, e))
		if _prop and bike.wings_out:
			_prop.rotation.z += delta * (6.0 + bike.speed * 1.2)
	# rider leans into the bank and tucks in when flying fast
	if rider and bike.airborne:
		rider.rotation.z = lerpf(rider.rotation.z, -bike.flight_roll * 0.25, clampf(delta * 4.0, 0, 1))
		rider.rotation.x = lerpf(rider.rotation.x, clampf(bike.speed / bike.flight_max_speed, 0.0, 1.0) * 0.25, clampf(delta * 4.0, 0, 1))
	elif rider:
		rider.rotation.z = lerpf(rider.rotation.z, 0.0, clampf(delta * 4.0, 0, 1))
		rider.rotation.x = lerpf(rider.rotation.x, 0.0, clampf(delta * 4.0, 0, 1))
	_wheel_spin += bike.speed / WHEEL_R * delta
	rear_wheel.rotation.x = -_wheel_spin
	front_wheel.rotation.x = -_wheel_spin
	fork_pivot.rotation.y = -bike.steer * deg_to_rad(22.0)
	if head:
		head.rotation.y = -bike.steer * deg_to_rad(18.0)
		head.rotation.x = clampf(-bike.speed * 0.006, -0.18, 0.0)
	# small bob at speed
	var t := Time.get_ticks_msec() * 0.001
	var sf := clampf(bike.speed / bike.max_speed, 0.0, 1.0)
	rider.position.y = sin(t * 14.0) * 0.008 * sf
