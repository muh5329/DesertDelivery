class_name TruckVisual
extends Node3D
## Compact, slightly battered red delivery truck built from primitives. The tall rear rack and
## visible Tetris cargo echo the supplied reference while keeping the project's handmade style.

const RED := Color(0.72, 0.12, 0.10)
const RED_DARK := Color(0.42, 0.08, 0.07)
const CREAM := Color(0.91, 0.84, 0.70)
const RUBBER := Color(0.10, 0.09, 0.08)
const TRUCK_CARGO_SCRIPT = preload("res://entities/vehicles/truck/truck_cargo.gd")

var cargo
var driver: Node3D
var wheels: Array[Node3D] = []
var front_wheels: Array[Node3D] = []
var _rope: MeshInstance3D
var _rope_mesh: CylinderMesh
var _wheel_spin := 0.0


func _ready() -> void:
	_build_truck()
	_build_driver()
	cargo = TRUCK_CARGO_SCRIPT.new(); cargo.name = "CargoGrid"; cargo.position = Vector3(0, 1.16, 0.93); add_child(cargo)
	_build_rope()


func _build_truck() -> void:
	var red := Mats.solid(RED, 0.55)
	var red_dark := Mats.solid(RED_DARK, 0.66)
	var cream := Mats.solid(CREAM, 0.62)
	var metal := Mats.solid(Color(0.72, 0.73, 0.70), 0.45, 0.45)
	var dark := Mats.solid(Color(0.15, 0.14, 0.13), 0.75)
	var glass := Mats.glass(Color(0.53, 0.72, 0.78, 0.40))
	# Chassis and narrow pickup bed.
	add_child(Mats.box(Vector3(1.72, 0.24, 3.65), red_dark, Vector3(0, 0.54, 0.05)))
	add_child(Mats.box(Vector3(1.76, 0.16, 1.83), dark, Vector3(0, 0.82, 0.92)))
	add_child(Mats.box(Vector3(0.10, 0.54, 1.90), red, Vector3(-0.83, 0.93, 0.92)))
	add_child(Mats.box(Vector3(0.10, 0.54, 1.90), red, Vector3(0.83, 0.93, 0.92)))
	add_child(Mats.box(Vector3(1.76, 0.54, 0.10), red, Vector3(0, 0.93, 1.84)))
	# Cab: blunt little nose, upright windscreen, pale roof.
	add_child(Mats.box(Vector3(1.70, 1.18, 1.48), red, Vector3(0, 1.20, -0.82)))
	add_child(Mats.box(Vector3(1.64, 0.13, 1.55), cream, Vector3(0, 1.85, -0.78)))
	add_child(Mats.box(Vector3(1.42, 0.59, 0.035), glass, Vector3(0, 1.47, -1.58), Vector3(-4, 0, 0)))
	for sx in [-0.84, 0.84]:
		add_child(Mats.box(Vector3(0.035, 0.54, 0.70), glass, Vector3(sx, 1.47, -0.92)))
		add_child(Mats.cylinder(0.055, 0.10, metal, Vector3(sx * 1.08, 1.43, -1.22), Vector3(0, 0, 90), 10))
	# Bumpers, grille, lamps, handles.
	add_child(Mats.box(Vector3(1.88, 0.12, 0.16), metal, Vector3(0, 0.53, -1.73)))
	add_child(Mats.box(Vector3(1.82, 0.11, 0.16), metal, Vector3(0, 0.55, 1.90)))
	add_child(Mats.box(Vector3(0.78, 0.28, 0.04), dark, Vector3(0, 0.91, -1.575)))
	for sx in [-0.58, 0.58]:
		add_child(Mats.cylinder(0.13, 0.055, Mats.solid(Color(1.0, 0.91, 0.63), 0.25, 0, Color(1.0, 0.78, 0.40)), Vector3(sx, 1.04, -1.62), Vector3(90, 0, 0), 12))
		add_child(Mats.box(Vector3(0.22, 0.045, 0.035), metal, Vector3(sx, 1.38, -1.604), Vector3(0, 0, -18)))
	# Four chunky wheels with cream hubs.
	for z in [-1.10, 1.18]:
		for sx in [-0.86, 0.86]:
			var wheel := Node3D.new(); wheel.position = Vector3(sx, 0.48, z); add_child(wheel)
			wheel.add_child(Mats.torus(0.25, 0.39, Mats.solid(RUBBER, 0.95), Vector3.ZERO, Vector3(0, 0, 90), Vector3(1.2, 1, 1)))
			wheel.add_child(Mats.cylinder(0.17, 0.13, cream, Vector3.ZERO, Vector3(0, 0, 90), 12))
			wheels.append(wheel)
			if z < 0: front_wheels.append(wheel)
	# Upright rack protects a tall load; crossbars visually lock the pieces to the bed.
	for sx in [-0.89, 0.89]:
		add_child(Mats.box(Vector3(0.07, 3.15, 0.07), metal, Vector3(sx, 2.20, 1.58)))
	add_child(Mats.box(Vector3(1.85, 0.07, 0.07), metal, Vector3(0, 3.76, 1.58)))
	add_child(Mats.box(Vector3(1.78, 0.045, 0.045), metal, Vector3(0, 2.18, 1.60)))
	# Front-mounted winch drum and fairlead.
	add_child(Mats.cylinder(0.18, 0.62, dark, Vector3(0, 0.66, -1.86), Vector3(0, 0, 90), 12))
	add_child(Mats.torus(0.10, 0.16, metal, Vector3(0, 0.66, -1.93), Vector3(90, 0, 0)))


func _build_driver() -> void:
	var model := RiderModel.new()
	model.name = "Driver"
	model.position = Vector3(.30,.02,-1.02)
	model.scale = Vector3.ONE * .75
	add_child(model)
	model.pose_riding()
	driver = model
	add_child(Mats.torus(.14,.17,Mats.solid(Color(.12,.11,.10),.8),Vector3(.30,1.10,-1.35),Vector3(90,0,0)))


func _build_rope() -> void:
	_rope_mesh = CylinderMesh.new(); _rope_mesh.top_radius = 0.023; _rope_mesh.bottom_radius = 0.023; _rope_mesh.height = 1.0; _rope_mesh.radial_segments = 6
	_rope = MeshInstance3D.new(); _rope.name = "WinchCable"; _rope.mesh = _rope_mesh
	_rope.material_override = Mats.solid(Color(0.12, 0.10, 0.08), 0.55, 0.25)
	_rope.visible = false; add_child(_rope)


func set_rider_visible(v: bool) -> void:
	if driver: driver.visible = v


func set_package_visible(v: bool) -> void:
	if cargo: cargo.set_package_visible(v)


func update_visual(truck, delta: float) -> void:
	_wheel_spin += truck.speed / 0.39 * delta
	for wheel in wheels: wheel.rotation.x = -_wheel_spin
	for wheel in front_wheels: wheel.rotation.y = -truck.steer * deg_to_rad(24.0)
	if driver: driver.rotation.z = lerpf(driver.rotation.z, -truck.steer * 0.08, clampf(delta * 4.0, 0, 1))
	if truck.winch_attached:
		_update_rope(truck.winch_anchor_world())
	else:
		_rope.visible = false


func _update_rope(world_anchor: Vector3) -> void:
	var a := Vector3(0, 0.69, -1.96)
	var b := to_local(world_anchor)
	var d := b - a
	var length := d.length()
	if length < 0.05: _rope.visible = false; return
	_rope.visible = true
	_rope_mesh.height = length
	var y := d / length
	var helper := Vector3.RIGHT if absf(y.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var x := helper.cross(y).normalized()
	var z := x.cross(y).normalized()
	_rope.transform = Transform3D(Basis(x, y, z), (a + b) * 0.5)
