extends Node
## The Jeep, end to end (it replaced the cargo truck, and this suite replaced truck_tests): it is
## data-defined and parked by the start, E mounts it, it drives, boosts and climbs a ramp, the
## winch hooks an obstacle and pulls it up a wall, it burns its own tank, it drives down a beach
## into the sea, planes (slower than on land) and drives back out, its bed carries goods, and
## save / load — an old save's `truck` block included — puts it back.
## Run: godot --headless --path . -- --test=jeep_tests

var game: Game
var sc: Controls.Scripted
var fails := 0
var platform: StaticBody3D
const BeachFinder = preload("res://tests/beach_finder.gd")
const PAD := Vector3(0, 420, 0)      # a test deck high over the island, clear of everything


func _ready() -> void:
	game = Game.current
	sc = game.use_scripted_controls()
	game.encounters.ambush_enabled = false
	game.vitals.health.invulnerable = 1e9
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	print(("  PASS " if ok else "  FAIL ") + label)
	if not ok: fails += 1


func frames(n: int) -> void:
	for i in n: await get_tree().physics_frame


## Physics runs at 120 Hz here: wait `s` seconds of it.
func secs(s: float) -> void:
	await frames(roundi(s * Engine.physics_ticks_per_second))


func _release() -> void:
	sc.intent = Controls.Intent.new()


func _run() -> void:
	await frames(20)
	var jeep: Jeep = game.jeep
	var t: Terrain = game.world.terrain
	# --- parked at the start
	check(jeep.definition.id == &"vehicle.jeep" and jeep.definition.amphibious, "the jeep is a data-defined amphibious vehicle (data/vehicles/jeep.tres)")
	check(game.entities.has_entity(&"vehicle.jeep") and jeep.parked, "the jeep is registered and starts parked")
	check(not game.entities.has_entity(&"vehicle.truck") and game.get("truck") == null, "the old cargo truck is gone")
	var d := jeep.global_position.distance_to(game.bike.global_position)
	check(d > 5.0 and d < 25.0, "it waits a short walk behind the starting bike (%.1f m)" % d)
	var g: float = t.probe(jeep.global_position + Vector3.UP).height
	check(absf(jeep.global_position.y - g) < 0.35 and jeep.grounded, "its wheels stand on the road (%.2f m)" % (jeep.global_position.y - g))
	var vis: JeepVisual = jeep.visual
	check(vis.wheels.size() == 4 and vis.wheel_spins.size() == 4 and vis.pontoons.size() == 2 and vis.propellers.size() == 2,
		"the LegendOfJeep model brings its wheel, pontoon and propeller pivots")
	# --- mount with E
	game.rider.request_dismount()
	await frames(5)
	game.player.place(jeep.global_position + jeep.global_transform.basis.x.normalized() * 1.9, jeep.flat_forward())
	await frames(10)
	sc.press("interact")
	await frames(3)
	check(game.rider.mode == Rider.Mode.DRIVING and game.rider.vehicle == jeep and not jeep.parked, "E beside the jeep gets the courier behind the wheel")
	check(game.cam.target == jeep and game.cam.framing == ChaseCamera.Framing.JEEP and game.gm.vehicle == jeep, "camera, deliveries and controls follow the jeep")
	check(jeep.control_scheme() is Jeep.JeepScheme, "the jeep brings its own control scheme")
	await _pad_tests(jeep)
	await _water_tests(jeep)
	await _save_tests(jeep)
	print("JEEP TESTS: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)


func _make_pad() -> void:
	platform = StaticBody3D.new(); platform.name = "JeepTestPad"; platform.collision_layer = 1; platform.collision_mask = 0
	var cs := CollisionShape3D.new(); var box := BoxShape3D.new(); box.size = Vector3(260, 2, 260)
	cs.shape = box; cs.position = Vector3(0, -1, 0); platform.add_child(cs)
	game.add_child(platform); platform.global_position = PAD


func _box(size: Vector3, at: Vector3, rot_x := 0.0) -> StaticBody3D:
	var b := StaticBody3D.new(); b.collision_layer = 1; b.collision_mask = 0
	var cs := CollisionShape3D.new(); var shape := BoxShape3D.new(); shape.size = size; cs.shape = shape
	b.add_child(cs); game.add_child(b)
	b.global_position = at; b.rotation.x = rot_x
	return b


func _place(v: Vehicle, at: Vector3, fwd: Vector3) -> void:
	v.place(at, fwd)
	game.world.set_focus(v)
	await frames(15)


func _pad_tests(jeep: Jeep) -> void:
	_make_pad()
	# --- drive
	await _place(jeep, PAD + Vector3(0, 0.1, 100), Vector3.FORWARD)
	var start := jeep.global_position
	game.journey.jeep_fuel = 1.0
	var bike_fuel := game.journey.fuel_ratio
	sc.intent.throttle = 1.0
	await secs(2.0)
	var plain := jeep.speed
	check(plain > 9.0 and jeep.global_position.distance_to(start) > 8.0, "full throttle drives it away (%.1f m/s after 2 s)" % plain)
	_release(); sc.intent.brake = 1.0
	await secs(2.0)
	check(absf(jeep.speed) < 0.3, "the brakes stop it")
	check(game.journey.jeep_fuel < 1.0 and is_equal_approx(game.journey.fuel_ratio, bike_fuel), "driving burns the jeep's tank, not the bike's (%.4f)" % game.journey.jeep_fuel)
	# --- boost (Shift): a burst on top of the same throttle
	_release()
	await _place(jeep, PAD + Vector3(0, 0.1, 100), Vector3.FORWARD)
	jeep.boost_left = jeep.definition.boost_seconds
	sc.intent.throttle = 1.0; sc.intent.boost = true
	await secs(2.0)
	check(jeep.speed > plain + 1.0 and jeep.boost_left < jeep.definition.boost_seconds, "Shift boosts it past the plain run (%.1f vs %.1f m/s)" % [jeep.speed, plain])
	_release(); sc.intent.brake = 1.0
	await secs(2.0)
	_release()
	# --- climb a ramp
	await _place(jeep, PAD + Vector3(40, 0.1, 60), Vector3.FORWARD)
	var ramp := _box(Vector3(8, 1, 40), PAD + Vector3(40, 4.2, 25), deg_to_rad(14.0))
	var y0 := jeep.global_position.y
	sc.intent.throttle = 1.0
	var top := y0
	for i in 5 * 120:
		await get_tree().physics_frame
		top = maxf(top, jeep.global_position.y)
	check(top > y0 + 3.0, "it climbs a 14 degree ramp (%.1f m up)" % (top - y0))
	_release(); ramp.queue_free()
	# --- winch: hook an obstacle ahead and pull up its face (the truck's check, now the jeep's)
	await _place(jeep, PAD + Vector3(-40, 0.1, 60), Vector3.FORWARD)
	var anchor := _box(Vector3(3, 8, 1.2), PAD + Vector3(-40, 3.2, 60 - 14))
	await frames(3)
	var wstart := jeep.global_position
	sc.press("winch")
	await frames(12)
	check(jeep.winch_attached, "Q raycasts and hooks a solid obstacle ahead")
	var d0 := jeep.winch_distance
	var hi := wstart.y
	for i in 220:
		await get_tree().physics_frame
		hi = maxf(hi, jeep.global_position.y)
	check(jeep.global_position.distance_to(wstart) > 1.5, "the taut cable pulls the jeep")
	check(jeep.winch_distance < d0 or not jeep.winch_attached, "the winch reels it toward the anchor")
	check(hi > wstart.y + 0.5, "a high anchor lifts it up the wall face")
	jeep.detach_winch(); anchor.queue_free()
	# --- the bed: goods ride in it and slow it a little
	jeep.bed.clear()
	check(jeep.bed.add("planks", 30) and not jeep.bed.add("blocks", 30), "the bed takes 60 kg of planks and refuses 90 kg of blocks on top (120 kg)")
	await frames(2)
	check(jeep.visual.load_view.used_slots > 0 and jeep.visual.load_view.shown.has("planks"), "the planks show on the bed")
	check(jeep._drive_mods().top_speed < jeep.definition.max_speed, "a loaded bed trims the top speed")
	check(game.journey._burn_per_m_for(jeep, false) > (1.0 / jeep.definition.tank_range_m), "a loaded bed burns more fuel")
	jeep.bed.clear()
	platform.queue_free()


## A beach on the core island's shore with a clear run into the sea (tests/beach_finder.gd).
func _find_beach() -> Dictionary:
	return await BeachFinder.find(game, game.jeep)


func _water_tests(jeep: Jeep) -> void:
	var beach := await _find_beach()
	check(not beach.is_empty(), "a beach on the island's shore to drive into the sea from")
	if beach.is_empty(): return
	print("    beach at %s (bearing %d)" % [beach.land, beach.angle])
	var t: Terrain = game.world.terrain
	jeep.set_towing(null)
	game.journey.jeep_fuel = 1.0
	await _place(jeep, beach.land, beach.dir)
	game.world.streamer.load_all_pending()
	await frames(20)
	var entered := [false]
	jeep.water_entered.connect(func(): entered[0] = true, CONNECT_ONE_SHOT)
	sc.intent.throttle = 1.0
	for i in 120 * 14:
		await get_tree().physics_frame
		if i % 60 == 0:
			var p := jeep.global_position
			print("    t=%.1f pos (%.1f, %.2f, %.1f) v %.1f grounded %s afloat %s water %s probe %.2f" % [i / 120.0, p.x, p.y, p.z, jeep.speed,
				jeep.grounded, jeep.afloat, jeep.water.water_at(p), t.probe(p + Vector3.UP * 2.0).height])
		if jeep.afloat: break
	check(jeep.afloat and entered[0], "driven down the beach it floats and the pontoons come down (afloat after the shore)")
	var top := 0.0
	var worst_y := 0.0
	for i in 120 * 6:
		await get_tree().physics_frame
		if i < 180: continue          # (the splash settles)
		top = maxf(top, jeep.speed)
		var wl := t.water_level_at(jeep.global_position.x, jeep.global_position.z)
		worst_y = maxf(worst_y, absf(jeep.global_position.y - (wl - jeep.definition.draught)))
	check(jeep.afloat and top > 4.0 and top <= jeep.definition.water_max_speed * 1.1 and top < jeep.definition.max_speed * 0.6,
		"it planes across the water, slower than on land (%.1f m/s)" % top)
	check(worst_y < 0.35, "the hull rides the surface (within %.2f m of its draught)" % worst_y)
	check(jeep.visual.amphibious_blend > 0.9, "the transformation is complete (pontoons down, propellers out)")
	var fuel := game.journey.jeep_fuel
	await frames(60)
	check(jeep.afloat and game.journey.jeep_fuel < fuel, "planing burns fuel")
	sc.press("interact")
	await frames(3)
	check(game.rider.mode == Rider.Mode.DRIVING, "the courier cannot step out onto the water")
	# turn back for the shore and drive out
	sc.intent.throttle = 0.8; sc.intent.steer = 1.0
	for i in 120 * 8:
		await get_tree().physics_frame
		if jeep.flat_forward().dot(-beach.dir) > 0.9: break
	sc.intent.steer = 0.0; sc.intent.throttle = 1.0
	var out := false
	for i in 120 * 30:
		await get_tree().physics_frame
		# steer for the beach point
		var to: Vector3 = beach.land - jeep.global_position; to.y = 0
		sc.intent.steer = clampf(-jeep.flat_forward().signed_angle_to(to.normalized(), Vector3.UP) * 1.5, -1, 1)
		if not jeep.afloat and jeep.grounded:
			var wl := t.water_level_at(jeep.global_position.x, jeep.global_position.z)
			if jeep.global_position.y > wl - 0.2:
				out = true
				break
	check(out, "it drives back out of the sea onto the beach")
	for i in 160: await get_tree().physics_frame
	check(jeep.visual.amphibious_blend < 0.1, "on land the pontoons fold away again")
	_release()


func _save_tests(jeep: Jeep) -> void:
	_release(); sc.intent.brake = 1.0
	await frames(60)
	_release()
	var spot := game.world.road_spawn(game.bike.global_position + Vector3(30, 0, 30), game.bike.global_position)
	await _place(jeep, spot.pos, spot.forward)
	if game.rider.vehicle != jeep or not game.rider.is_riding():
		game.rider._set_vehicle(jeep); game.rider._set_mode(Rider.Mode.DRIVING)
	jeep.bed.clear(); jeep.bed.add("fuel_can", 2)
	game.journey.jeep_fuel = 0.4
	var at := jeep.global_position
	check(Saves.save_game("jeep_tests"), "saved")
	jeep.bed.clear(); game.journey.jeep_fuel = 1.0
	await _place(jeep, at + Vector3(20, 0, 0), Vector3.FORWARD)
	check(Saves.load_game("jeep_tests"), "loaded")
	await frames(5)
	check(jeep.global_position.distance_to(at) < 1.5 and jeep.bed.count("fuel_can") == 2 and absf(game.journey.jeep_fuel - 0.4) < 0.01,
		"save / load keeps the jeep's place, its bed and its tank")
	check(game.rider.vehicle == jeep and game.rider.mode == Rider.Mode.DRIVING, "the courier is back at the wheel")
	# an old save: a `truck` block and a rider in the truck
	var old_at := at + Vector3(0, 0, 12)
	var data := {"version": 1, "systems": {
		"truck": {"pos": {"__v3": [old_at.x, old_at.y, old_at.z]}, "forward": {"__v3": [0, 0, -1]}, "odometer": 1234.0,
			"cargo": {"placed": [{"shape": 4, "rotation": 0, "origin": {"__v2i": [0, 0]}}], "next_shape": 1}},
		"rider": {"mode": Rider.Mode.DRIVING, "vehicle": "truck"},
		"delivery": {"version": 2, "job_index": 0, "stage": 0, "coins": 7, "urgent": {"id": "job.urgent.isola_serena.bread.20",
			"from": "campo_real", "to": "isola_serena", "item": "20 bread (urgent)", "reward": 50, "mass_kg": 20.0, "kind": "heavy", "vehicle": "truck"}}}}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://saves"))
	var f := FileAccess.open(Saves.path_for("old_truck"), FileAccess.WRITE)
	f.store_string(JSON.stringify(data)); f.close()
	check(Saves.load_game("old_truck"), "an old save with a truck loads")
	await frames(5)
	check(jeep.global_position.distance_to(old_at) < 1.5 and absf(jeep.odometer - 1234.0) < 0.1, "its truck block moves the jeep to where the truck was")
	check(game.rider.vehicle == jeep and game.rider.mode == Rider.Mode.DRIVING, "a courier saved in the truck is in the jeep")
	var job := game.gm.current_job()
	check(job != null and job.vehicle == "cargo", "an urgent run saved for the truck is a jeep-or-cart run")
	check(not game.hitch.tow_vehicle() and game.cart.inventory.is_empty(), "a save from before the cart finds it parked and empty")
