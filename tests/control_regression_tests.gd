extends Node
## Behavioral regressions for analogue walking, jump grace and drivetrain direction changes.
const DT := 1.0 / 60.0
var failures := 0

func _ready() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	print(("  PASS " if ok else "  FAIL ") + label)
	if not ok: failures += 1

func _run() -> void:
	var pad := StaticBody3D.new()
	pad.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 2, 200)
	shape.shape = box
	pad.add_child(shape)
	pad.position.y = 219
	add_child(pad)
	var player := Player.new()
	add_child(player)
	player.set_physics_process(false)
	var camera := Camera3D.new()
	add_child(camera)
	player.camera = camera
	player.place(Vector3(0, 220.05, 0), Vector3.FORWARD)
	await get_tree().physics_frame
	var half := Controls.Intent.new()
	half.move = Vector2(0, 0.5)
	for step in 60:
		await get_tree().physics_frame
		player.apply(half)
		player._physics_process(DT)
	_check(absf(player.speed() - player.walk_speed * 0.5) < 0.1, "half stick produces half walking speed, not quarter speed")
	var backward := Controls.Intent.new()
	backward.move = Vector2(0, -1)
	var before := player.velocity.z
	player.apply(backward)
	player._physics_process(DT)
	_check(absf(player.velocity.z - before) <= player.ground_acceleration * DT + 0.01, "direction reversal respects acceleration")
	var jump := Controls.Intent.new()
	jump.press(Controls.JUMP)
	player.apply(jump)
	player._physics_process(DT)
	_check(player.velocity.y > 5.0, "grounded jump launches")
	_check(not jump.pressed(Controls.JUMP), "jump edge consumed once even if intent is retained")
	player.place(Vector3(0, 221, 0), Vector3.FORWARD)
	_check(player.speed() == 0 and player._jump_buffer_left == 0, "teleport clears locomotion momentum and buffered jump")
	# Establish real floor contact, then walk over the edge of the physical pad.
	player.place(Vector3(99.7, 220.05, 0), Vector3.FORWARD)
	var right := Controls.Intent.new(); right.move = Vector2.RIGHT
	var was_grounded := false
	var walked_off := false
	for step in 90:
		await get_tree().physics_frame
		player.apply(right)
		player._physics_process(DT)
		if was_grounded and not player.is_on_floor():
			walked_off = true
			break
		was_grounded = player.is_on_floor()
	jump = Controls.Intent.new(); jump.press(Controls.JUMP)
	player.apply(jump)
	player._physics_process(DT)
	_check(walked_off and player.velocity.y > 5.0, "coyote jump launches after walking off a physical ledge")
	player.place(Vector3(0, 220.10, 0), Vector3.FORWARD)
	player.apply(Controls.Intent.new())
	await get_tree().physics_frame
	player._physics_process(DT)
	jump = Controls.Intent.new(); jump.press(Controls.JUMP)
	var buffered_launch := false
	for step in 12:
		await get_tree().physics_frame
		player.apply(jump if step == 0 else Controls.Intent.new())
		player._physics_process(DT)
		if player.velocity.y > 5.0: buffered_launch = true; break
	_check(buffered_launch, "jump pressed before landing launches from buffered input")
	player.queue_free()
	_check(Controls.radial_deadzone(Vector2(0.1, 0)) == Vector2.ZERO, "controller drift is filtered")
	_check(Controls.radial_deadzone(Vector2(0.181, 0)).length() < 0.01, "controller aim starts continuously at the deadzone")
	_check(is_finite(Controls.radial_deadzone(Vector2.ONE, 1.0).x), "deadzone endpoint remains finite")
	for path in ["res://data/vehicles/bike.tres", "res://data/vehicles/truck.tres"]:
		var definition: VehicleDefinition = load(path)
		var vehicle: Vehicle = Bike.new() if definition.can_fly else Truck.new()
		vehicle.apply_definition(definition)
		add_child(vehicle)
		vehicle.set_physics_process(false)
		vehicle.place(Vector3(0, 220.05, 0), Vector3.FORWARD)
		await get_tree().physics_frame
		var forward := Controls.Intent.new()
		forward.throttle = 1.0
		vehicle.speed = -3.0
		for step in 90:
			await get_tree().physics_frame
			vehicle.apply(forward)
			vehicle.drive.force_wheel_update()
			vehicle._physics_process(DT)
		_check(vehicle.speed > 0.5, "%s: throttle brakes reverse and then drives forward" % definition.display_name)
		var both := Controls.Intent.new(); both.throttle = 1.0; both.brake = 1.0
		vehicle.place(Vector3(0, 220.05, 0), Vector3.FORWARD)
		for step in 60:
			await get_tree().physics_frame
			vehicle.apply(both)
			vehicle.drive.force_wheel_update()
			vehicle._physics_process(DT)
		_check(vehicle.speed >= -0.001, "%s: simultaneous pedals cannot engage reverse" % definition.display_name)
		var turn := Controls.Intent.new(); turn.steer = 1.0
		vehicle.drive.intent = turn
		vehicle.drive.steer = 0.0; vehicle.speed = 0.0
		vehicle.drive.read_intent(DT)
		var low_response := vehicle.steer
		vehicle.drive.steer = 0.0; vehicle.speed = definition.max_speed
		vehicle.drive.read_intent(DT)
		_check(vehicle.steer < low_response, "%s: cruise steering is calmer than parking steering" % definition.display_name)
		vehicle.set_parked(true)
		_check(vehicle.throttle == 0 and vehicle.drive.intent.throttle == 0, "%s: parking clears stale pedal input" % definition.display_name)
		vehicle.drive.extra_velocity = Vector3(10, 10, 10)
		vehicle.place(Vector3(0, 220.05, 0), Vector3.FORWARD)
		_check(vehicle.drive.extra_velocity == Vector3.ZERO, "%s: recovery clears external pull" % definition.display_name)
		vehicle.queue_free()
	await get_tree().process_frame
	print("[controls] failures=", failures)
	get_tree().quit(1 if failures else 0)
