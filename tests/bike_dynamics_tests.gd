extends SceneTree
## Real collision/raycast fixtures: flat stability, ramp takeoff, ballistic steering,
## landing/recovery, parked suspension and wing-flight continuity.
const DT := 1.0 / 120.0
var failures := 0
var bike: Bike
var ramps: StaticBody3D
var landings: Array[float] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures += 1

func step(count: int, input: Controls.Intent) -> void:
	bike.apply(input)
	for index in count:
		await physics_frame
		bike._physics_process(DT)

func run() -> void:
	var floor := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new(); box.size = Vector3(400, 2, 400)
	collider.shape = box; floor.add_child(collider); root.add_child(floor)
	floor.position.y = 219
	bike = Bike.new(); bike.apply_definition(load("res://data/vehicles/bike.tres"))
	root.add_child(bike); bike.set_physics_process(false); bike.ceiling = 450
	bike.landed.connect(func(impact: float): landings.append(impact))
	await physics_frame; await physics_frame
	bike.place(Vector3(40, 220, 20), Vector3.FORWARD)
	await step(180, Controls.Intent.new())
	check(bike.grounded and absf(bike.global_position.y - 220.04) < .035,
		"spring supports chassis at rest without floor adhesion (y=%.3f)" % bike.global_position.y)
	var settled_y := bike.global_position.y
	var min_y := settled_y; var max_y := settled_y; var airborne_ticks := 0
	var go := Controls.Intent.new(); go.throttle = 1
	bike.apply(go)
	for index in 360:
		await physics_frame; bike._physics_process(DT)
		min_y = minf(min_y, bike.global_position.y); max_y = maxf(max_y, bike.global_position.y)
		if not bike.grounded: airborne_ticks += 1
	check(max_y - min_y < .035 and airborne_ticks == 0,
		"flat acceleration stays settled without artificial hopping (range=%.4f, air=%d)" % [max_y-min_y, airborne_ticks])
	check(bike.speed > 19, "suspension retains responsive acceleration")
	check(absf(bike.visual.front_wheel.global_position.y - 220.32) < .035,
		"visible wheel travel keeps front tire at ground level")
	bike.set_parked(true); await step(120, Controls.Intent.new())
	check(absf(bike.global_position.y - settled_y) < .035, "parking retains suspension height instead of sinking chassis")
	bike.set_parked(false)

	ramps = StaticBody3D.new()
	var ramp_shape := CollisionShape3D.new()
	var mesh := ConcavePolygonShape3D.new()
	var a := Vector3(-8, 220, 20); var b := Vector3(8, 220, 20)
	var c := Vector3(-8, 223, 0); var d := Vector3(8, 223, 0)
	var e := Vector3(-8, 220, -20); var f := Vector3(8, 220, -20)
	mesh.set_faces(PackedVector3Array([a,c,b,b,c,d,c,e,d,d,e,f]))
	ramp_shape.shape = mesh; ramps.add_child(ramp_shape); root.add_child(ramps)
	await physics_frame; await physics_frame
	bike.place(Vector3(0, 220.30, 18), Vector3.FORWARD)
	await step(120, Controls.Intent.new())
	bike.speed = 20
	go.throttle = .6; bike.apply(go); landings.clear()
	var peak := bike.global_position.y; var launch_up := 0.0; var max_air := 0.0
	var observed_launch := false; var landed_after_launch := false
	for index in 480:
		await physics_frame; bike._physics_process(DT)
		peak = maxf(peak, bike.global_position.y)
		max_air = maxf(max_air, bike.air_time)
		if not bike.grounded and bike.air_time > .03 and bike.global_position.z < 1:
			observed_launch = true
			launch_up = maxf(launch_up, bike.vertical_vel)
		if observed_launch and bike.grounded: landed_after_launch = true
	print("RAMP peak=",peak," upward=",launch_up," air=",max_air," impacts=",landings)
	check(observed_launch and launch_up > .6 and peak > 223.12,
		"ramp preserves upward momentum and launches naturally")
	check(max_air > .35 and landed_after_launch and not bike.airborne,
		"ordinary bike jump has airtime and lands without entering wing flight")
	check(landings.size() == 1 and landings[0] > 3,
		"landing emits one measured impact, not repeated contact chatter")
	check(bike.grounded and absf(bike.vertical_vel) < .2, "suspension settles after landing")

	# Repeat the same crest at 60 Hz: spring integration must remain stable.
	bike.place(Vector3(0, 220.30, 18), Vector3.FORWARD)
	await step(120, Controls.Intent.new())
	Engine.physics_ticks_per_second = 60
	bike.speed = 20; bike.apply(go)
	var peak60 := bike.global_position.y; var air60 := 0.0
	for index in 240:
		await physics_frame; bike._physics_process(1.0 / 60.0)
		peak60 = maxf(peak60, bike.global_position.y); air60 = maxf(air60, bike.air_time)
	check(absf(peak60 - peak) < .12 and absf(air60 - max_air) < .12,
		"crest trajectory remains comparable at 60/120 Hz (peak %.3f/%.3f, air %.3f/%.3f)" % [peak60, peak, air60, max_air])
	Engine.physics_ticks_per_second = 120
	bike.place(Vector3(0, 222.40, 4), Vector3.FORWARD)
	await step(120, Controls.Intent.new())
	var crawl_air := 0.0
	bike.apply(Controls.Intent.new())
	for index in 600:
		await physics_frame; bike.speed = 2; bike._physics_process(DT)
		crawl_air = maxf(crawl_air, bike.air_time)
	check(crawl_air < .12 and bike.global_position.z < -4,
		"slow crest crossing stays planted without prolonged hopping (air=%.3f)" % crawl_air)

	bike.place(Vector3(40, 228, 0), Vector3.FORWARD)
	bike.grounded = false; bike.speed = 18; bike.drive.capture_velocity(Vector3(0, 2, -18))
	var air_steer := Controls.Intent.new(); air_steer.steer = 1
	await step(40, air_steer)
	check(absf(bike.global_position.x - 40) < .05 and absf(bike.heading()) > .015,
		"airborne steering adjusts attitude without magically redirecting travel")
	check(bike.vertical_vel < -3.5, "airborne vertical momentum follows gravity")
	bike.place(Vector3(40, 220, 0), Vector3.FORWARD)
	await step(120, Controls.Intent.new())
	bike.wings_out = true; bike.speed = 18
	var flight := Controls.Intent.new(); flight.throttle = 1; flight.pitch = 1
	await step(30, flight)
	check(bike.airborne and not bike.grounded and bike.global_position.y > 220.2,
		"wing takeoff still exits spring solver cleanly")
	# A shallow wing landing must not declare touchdown while still too high for
	# the suspension, then emit a second ordinary-bike landing a few ticks later.
	landings.clear()
	bike.global_position = Vector3(40, 220.6, -40)
	bike.flight_pitch = -.025; bike.speed = 20
	flight.pitch = -.055; flight.throttle = .3
	await step(240, flight)
	check(not bike.airborne and bike.grounded and landings.size() == 1,
		"shallow wing landing hands momentum to suspension with one touchdown (events=%d)" % landings.size())

	bike.queue_free(); floor.queue_free(); ramps.queue_free(); await process_frame
	print("BIKE DYNAMICS: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
