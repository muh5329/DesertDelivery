class_name Truck
extends Vehicle
## A compact arcade cargo truck. Ground driving is the shared GroundDrive
## (data/vehicles/truck.tres); what is the truck's own is the Tetris cargo rack and the front
## winch that grabs world collision, pulls the truck through rough ground, and gives it enough
## upward force to scramble over steep faces.

signal crashed
signal denied(text: String)
signal winch_changed(attached: bool, distance: float)
signal fell_in_sea

const TRUCK_VISUAL_SCRIPT = preload("res://entities/vehicles/truck/truck_visual.gd")

var cargo_build_mode := false
var winch_attached := false
var winch_range := 38.0
var winch_pull_speed := 10.5
var winch_distance := 0.0

var _dust: CPUParticles3D
var _anchor_node: Node3D
var _anchor_local := Vector3.ZERO
var _anchor_static := Vector3.ZERO
var _cargo_intent := Controls.Intent.new()   # what the drive sees while packing: nothing


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | 16
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new(); shape.size = Vector3(1.72, 1.45, 3.55)
	cs.shape = shape; cs.position = Vector3(0, 0.88, 0.02); add_child(cs)
	var rack_cs := CollisionShape3D.new()
	var rack_shape := BoxShape3D.new(); rack_shape.size = Vector3(1.76, 2.65, 1.78)
	rack_cs.shape = rack_shape; rack_cs.position = Vector3(0, 2.20, 0.93); add_child(rack_cs)
	floor_max_angle = deg_to_rad(62.0)
	floor_snap_length = 0.72
	safe_margin = 0.035
	var wb: float = definition.wheelbase if definition else 2.5
	var offsets: Array = []
	for x in [-0.60, 0.60]:
		for z in [-wb * 0.5, wb * 0.5]:
			offsets.append(Vector3(x, 1.0, z))
	_build_drive(offsets, 2.8)
	visual = TRUCK_VISUAL_SCRIPT.new(); visual.name = "TruckVisual"; add_child(visual)
	_build_dust()


func _build_dust() -> void:
	_dust = CPUParticles3D.new(); _dust.amount = 64; _dust.lifetime = 1.5
	_dust.position = Vector3(0, 0.18, 1.55); _dust.direction = Vector3(0, 0.45, 1)
	_dust.spread = 38; _dust.initial_velocity_min = 1.2; _dust.initial_velocity_max = 3.2
	_dust.gravity = Vector3(0, 0.5, 0); _dust.damping_min = 1.0; _dust.damping_max = 2.0
	var mesh := SphereMesh.new(); mesh.radius = 0.38; mesh.height = 0.76; mesh.radial_segments = 7; mesh.rings = 4
	var mat := StandardMaterial3D.new(); mat.albedo_color = Color(0.84, 0.72, 0.52, 0.28)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mat; _dust.mesh = mesh; _dust.emitting = false; add_child(_dust)


## While the rack is open the driving keys become cursor keys: the meaning of WASD and Space
## belongs to the truck, not to the keyboard reader.
class TruckScheme:
	extends Vehicle.GroundScheme
	func map(r: Controls.Reading, i: Controls.Intent) -> void:
		var truck: Truck = vehicle
		if r.just(&"winch"): i.press(Controls.WINCH)
		if r.just(&"cargo_mode"): i.press(Controls.CARGO_MODE)
		if not truck.cargo_build_mode:
			super.map(r, i)
			return
		i.cargo_move = Vector2i(
			int(r.just(&"steer_right")) - int(r.just(&"steer_left")),
			int(r.just(&"accelerate")) - int(r.just(&"brake")))
		if r.just(&"handbrake"): i.press(Controls.CARGO_PLACE)
		if r.just(&"cargo_rotate"): i.press(Controls.CARGO_ROTATE)
		if r.just(&"cargo_remove"): i.press(Controls.CARGO_REMOVE)


func _make_scheme() -> Controls.Scheme:
	return TruckScheme.new(self)


func apply(intent: Controls.Intent) -> void:
	super.apply(intent)
	if intent.pressed(Controls.CARGO_MODE): toggle_cargo_build()
	if intent.pressed(Controls.WINCH): toggle_winch()
	if cargo_build_mode:
		if intent.cargo_move != Vector2i.ZERO: visual.cargo.move_cursor(intent.cargo_move)
		if intent.pressed(Controls.CARGO_ROTATE): visual.cargo.rotate_piece()
		if intent.pressed(Controls.CARGO_PLACE):
			if not visual.cargo.place_piece(): denied.emit("That piece needs clear space and support.")
		if intent.pressed(Controls.CARGO_REMOVE):
			if not visual.cargo.remove_last(): denied.emit("The cargo bed is already empty.")


func set_parked(v: bool) -> void:
	super.set_parked(v)
	if v and cargo_build_mode: set_cargo_build(false)


func place(pos: Vector3, forward: Vector3) -> void:
	super.place(pos, forward)
	detach_winch()


func status_line() -> String:
	if cargo_build_mode: return "Truck · packing"
	if winch_attached: return "Truck · winch %.0fm" % winch_distance
	return "Truck · %d crates" % cargo_blocks()


## What the rack looks like, in words. The HUD asks the Truck; it never walks into the renderer.
func cargo_status() -> String:
	return visual.cargo.status_text() if visual and visual.cargo else ""


func cargo_blocks() -> int:
	return visual.cargo.block_count() if visual and visual.cargo else 0


func cargo_fill() -> float:
	return visual.cargo.fill_ratio() if visual and visual.cargo else 0.0


func toggle_cargo_build() -> void:
	if cargo_build_mode:
		set_cargo_build(false)
		return
	if absf(speed) > 0.6 or winch_attached:
		denied.emit("Stop and detach the winch before packing cargo.")
		return
	set_cargo_build(true)


func set_cargo_build(v: bool) -> void:
	if v == cargo_build_mode: return
	cargo_build_mode = v
	if v: speed = 0.0
	if visual and visual.cargo: visual.cargo.set_build_mode(v)
	denied.emit("Cargo mode: WASD move · Z rotate · Space place · X undo · G finish." if v else "Cargo secured. Ready to drive.")


func toggle_winch() -> void:
	if winch_attached:
		detach_winch()
		return
	if cargo_build_mode:
		denied.emit("Finish packing the cargo before firing the winch.")
		return
	_fire_winch()


func _fire_winch() -> bool:
	var space := get_world_3d().direct_space_state
	var origin := global_position + flat_forward() * 1.94 + Vector3(0, 0.72, 0)
	# The higher casts make walls and tree trunks useful climbing anchors; the shallow cast catches
	# low rocks and roadside obstacles. Closest successful cast wins.
	var best: Dictionary = {}
	var best_distance := INF
	for rise in [0.30, 0.17, 0.06]:
		var direction: Vector3 = (flat_forward() + Vector3.UP * float(rise)).normalized()
		var q := PhysicsRayQueryParameters3D.create(origin, origin + direction * winch_range, 1)
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		if hit and origin.distance_to(hit.position) < best_distance:
			best = hit; best_distance = origin.distance_to(hit.position)
	if best.is_empty():
		denied.emit("No tree or obstacle in winch range.")
		return false
	_anchor_static = best.position
	_anchor_node = best.collider as Node3D
	if _anchor_node: _anchor_local = _anchor_node.to_local(best.position)
	winch_attached = true; winch_distance = best_distance
	winch_changed.emit(true, best_distance)
	return true


func attach_winch_for_test(world_point: Vector3) -> void:
	_anchor_node = null; _anchor_static = world_point
	winch_attached = true; winch_distance = global_position.distance_to(world_point)
	winch_changed.emit(true, winch_distance)


func detach_winch() -> void:
	if not winch_attached: return
	winch_attached = false; winch_distance = 0.0; _anchor_node = null
	winch_changed.emit(false, 0.0)


func winch_anchor_world() -> Vector3:
	if _anchor_node and is_instance_valid(_anchor_node): return _anchor_node.to_global(_anchor_local)
	return _anchor_static


## A full rack costs top speed. Everything else the truck drives on comes from its .tres.
func _drive_mods() -> GroundDrive.Mods:
	var m := super._drive_mods()
	m.top_speed = definition.max_speed * (1.0 - cargo_fill() * 0.20)
	return m


func _physics_process(delta: float) -> void:
	if parked:
		drive.idle(delta)
		if visual: visual.update_visual(self, delta)
		_dust.emitting = false
		return
	drive.mods = _drive_mods()
	if cargo_build_mode:
		# Packing is a full stop: the drive sees a stationary courier, not the cargo keys.
		_cargo_intent.clear_edges(); _cargo_intent.throttle = 0.0; _cargo_intent.steer = 0.0
		_cargo_intent.brake = 1.0; _cargo_intent.handbrake = true
		var real := drive.intent
		drive.intent = _cargo_intent
		drive.read_intent(delta)
		drive.intent = real
	else:
		drive.read_intent(delta)
	# A taut cable reels in the drivetrain, so the winch can pull even with no throttle.
	var anchor_dir := Vector3.ZERO
	if winch_attached:
		var anchor := winch_anchor_world()
		var hook := global_position + flat_forward() * 1.75 + Vector3(0, 0.68, 0)
		var cable := anchor - hook
		winch_distance = cable.length()
		if winch_distance < 1.45:
			detach_winch()
		else:
			anchor_dir = cable / winch_distance
			speed += anchor_dir.dot(flat_forward()) * 8.5 * delta
			var reel_speed := minf(winch_pull_speed, maxf(3.0, (winch_distance - 1.4) * 1.5))
			drive.extra_velocity = anchor_dir * reel_speed
			# A cable fixed above the bumper gives deliberate wall-climbing lift instead of
			# pinning the truck endlessly against the first vertical face it touches.
			if anchor_dir.y > 0.04:
				drive.min_vertical = anchor_dir.y * reel_speed + 1.4
				drive.climbing = true
	var tick := drive.step(delta)
	drive.climbing = false
	if tick.crashed: crashed.emit()
	if tick.landed_impact > definition.hard_landing_impact: crashed.emit()
	if tick.in_sea:
		fell_in_sea.emit()
		reset_to_road(true)
	if visual: visual.update_visual(self, delta)
	_dust.emitting = grounded and absf(speed) > definition.dust_min_speed


func reset_to_road(away_from_sea: bool = false) -> void:
	detach_winch(); set_cargo_build(false)
	super.reset_to_road(away_from_sea)


func save_state() -> Dictionary:
	var data := super.save_state()
	data["cargo"] = visual.cargo.save_state() if visual and visual.cargo else {}
	return data


func load_state(data: Dictionary) -> void:
	super.load_state(data)
	if visual and visual.cargo: visual.cargo.load_state(data.get("cargo", {}))
