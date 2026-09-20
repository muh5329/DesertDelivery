extends SceneTree
## Production wing solver at mountain height, high altitude and the flight ceiling.
var failures := 0
var bike: Bike
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures += 1
func start_at(height: float) -> void:
	bike.place(Vector3(4000, height, -6000), Vector3.FORWARD)
	bike.global_position.y = height # place() adds ground clearance; this fixture starts in flight.
	bike.wings_out = true; bike.airborne = true; bike.grounded = false
	bike.speed = 36.0; bike.flight_pitch = deg_to_rad(26)
	bike._pitch_in = 1.0
func run() -> void:
	Engine.physics_ticks_per_second = 120
	bike = Bike.new(); bike.apply_definition(load("res://data/vehicles/bike.tres"))
	root.add_child(bike); bike.set_physics_process(false)
	check(bike.ceiling == 5000.0, "production ceiling is 5 km above sea level")
	for height in [650.0, 3000.0]:
		start_at(height)
		for frame in 120:
			await physics_frame; bike._flight(1.0 / 120.0)
		check(bike.global_position.y > height + 10.0 and bike.airborne,
			"continues climbing above outer mountains at %.0f m" % height)
	start_at(bike.ceiling - .02)
	await physics_frame; bike._flight(1.0 / 120.0)
	check(absf(bike.global_position.y - bike.ceiling) < .01, "ascent stops at ceiling without overshoot")
	start_at(bike.ceiling + 200.0)
	await physics_frame; bike._flight(1.0 / 120.0)
	check(bike.global_position.y >= bike.ceiling + 199.9, "above-ceiling spawn is not snapped downward")
	bike._pitch_in = -1.0; bike.flight_pitch = deg_to_rad(-20)
	var previous := bike.global_position.y
	await physics_frame; bike._flight(1.0 / 120.0)
	check(bike.global_position.y < previous, "pilot can descend from above ceiling")
	bike.free()
	print("FLIGHT ALTITUDE failures: ", failures)
	quit(1 if failures else 0)
