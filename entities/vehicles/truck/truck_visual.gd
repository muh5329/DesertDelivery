class_name TruckVisual
extends Node3D
## Rounded Blender-authored courier truck, with animated wheel pivots, seated driver,
## and a playable cargo rack mounted on the wooden bed.

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
	cargo = TRUCK_CARGO_SCRIPT.new(); cargo.name = "CargoGrid"; cargo.position = Vector3(0, 0.95, 0.93); add_child(cargo)
	_build_rope()


func _build_truck() -> void:
	var model := IslandArt.instantiate("courier_truck")
	add_child(model)
	for id in ["FL", "FR", "RL", "RR"]:
		wheels.append(model.find_child("Wheel" + id, true, false))
		if id.begins_with("F"):
			front_wheels.append(model.find_child("Steering" + id, true, false))


func _build_driver() -> void:
	var model := RiderModel.new()
	model.name = "Driver"
	model.position = Vector3(.30,.07,-1.02)
	model.scale = Vector3.ONE * .82
	add_child(model)
	model.pose_riding()
	driver = model
	var upholstery := Mats.solid(Color(.24,.29,.22),.92)
	add_child(Mats.box(Vector3(.47,.10,.48),upholstery,Vector3(.30,.90,-.79)))
	add_child(Mats.box(Vector3(.47,.42,.10),upholstery,Vector3(.30,1.08,-.51)))
	add_child(Mats.torus(.14,.17,Mats.solid(Color(.12,.11,.10),.8),Vector3(.30,1.31,-1.35),Vector3(90,0,0)))


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
