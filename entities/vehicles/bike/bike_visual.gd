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
var _front_rest := Vector3.ZERO
var _rear_rest := Vector3.ZERO
var _front_travel := 0.0
var _rear_travel := 0.0
var _front_suspension: Node3D
var _rear_swingarm: Node3D
var _stanchions: Array[Node3D] = []
var _shocks: Array[Node3D] = []


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


const BIKE_MODEL = preload("res://assets/models/courier_bike.glb")

func _build_bike(p: Node3D) -> void:
	var model: Node3D = BIKE_MODEL.instantiate()
	p.add_child(model)
	Storybook.apply(model)
	VehicleLights.dress(model, true)     # headlamp + tail glass, the headlight at night (world/sky)
	fork_pivot = model.find_child("ForkPivot", true, false)
	front_wheel = model.find_child("FrontWheel", true, false)
	rear_wheel = model.find_child("RearWheel", true, false)
	_front_rest = front_wheel.position
	_rear_rest = rear_wheel.position
	_front_suspension = model.find_child("FrontSuspension", true, false)
	_rear_swingarm = model.find_child("RearSwingarm", true, false)
	for suffix in ["L", "R"]:
		_stanchions.append(model.find_child("ForkStanchion" + suffix, true, false))
		_shocks.append(model.find_child("RearShock" + suffix, true, false))


func _build_rider(p: Node3D) -> void:
	var model := RiderModel.new()
	model.name = "Rider"
	p.add_child(model)
	model.pose_riding(true)
	rider = model
	head = model.head


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
	# tractor propeller on the nose, just ahead of the headlight (bike -Z is forward; the wings
	# node sits at (0, 0.88, 0.55), so the nose is at wings-local z = -1.9)
	_prop = Node3D.new()
	_prop.position = Vector3(0, -0.04, -1.92)
	wings.add_child(_prop)
	var blade := Mats.solid(Color(0.3, 0.2, 0.12), 0.7)
	_prop.add_child(Mats.box(Vector3(1.05, 0.10, 0.025), blade, Vector3.ZERO, Vector3(0, 0, 0)))
	_prop.add_child(Mats.box(Vector3(0.10, 1.05, 0.025), blade, Vector3.ZERO, Vector3(0, 0, 0)))
	_prop.add_child(Mats.cylinder(0.075, 0.12, chrome, Vector3(0, 0, 0.02), Vector3(90, 0, 0), 10, 0.045))
	# a short shaft back to the nose cone so it does not float
	wings.add_child(Mats.cylinder(0.03, 0.14, chrome, Vector3(0, -0.04, -1.84), Vector3(90, 0, 0), 8))
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
		head.rotation.x = .45 + clampf(-bike.speed * 0.006, -0.18, 0.0)
	# Actual wheel support drives suspension travel; no time-based road vibration.
	var response := 1.0 - exp(-18.0 * delta)
	var front_target: float = bike.drive.front_suspension if not bike.airborne else -.08
	var rear_target: float = bike.drive.rear_suspension if not bike.airborne else -.08
	_front_travel = front_target
	_rear_travel = rear_target
	if _front_suspension and _rear_swingarm:
		_front_suspension.position = Vector3(0, -.73 + _front_travel, -.24 + _front_travel * .24 / .73)
		var swing_length := Vector2(.05, .54).length()
		_rear_swingarm.rotation.x = atan2(-.05, .54) - asin(clampf((-.05 + _rear_travel) / swing_length, -.95, .95))
		for index in 2:
			var side := -1.0 if index == 0 else 1.0
			var lower := Vector3(side * .12, _front_suspension.position.y, _front_suspension.position.z)
			_pose_segment(_stanchions[index], Vector3(side * .12, 0, 0), lower, Vector2(.73, .24).length())
			var wheel_center := _rear_swingarm.transform * _rear_rest
			var shock_bottom := wheel_center + Vector3(side * .21, .02, 0)
			_pose_segment(_shocks[index], shock_bottom, Vector3(side * .21, .89, .40), Vector2(.55, .30).length())
	else:
		# Legacy asset fallback while an editor is still importing the new pivots.
		front_wheel.position = _front_rest + Vector3.UP * _front_travel
		rear_wheel.position = _rear_rest + Vector3.UP * _rear_travel
	if rider:
		var compression := clampf(bike.drive.suspension_load - 1.0, -.5, 2.0) if not bike.airborne else 0.0
		rider.position.y = lerpf(rider.position.y, -.012 * compression, response)


func _pose_segment(pivot: Node3D, a: Vector3, b: Vector3, rest_length: float) -> void:
	if pivot == null: return
	var span := b - a
	pivot.position = (a + b) * .5
	pivot.basis = Basis(Quaternion(Vector3.UP, span.normalized()))
	pivot.scale.y = span.length() / rest_length
