extends Node
## Measured riding checks on a physical flat test pad. The production Bike,
## wheel rays, inputs and collision motion run normally; economy stays external.
const DT:=1.0/120.0
const CAMERA_DT:=1.0/60.0
var failures:=0
var probe: Bike
var pad: StaticBody3D

func _check(ok: bool, label: String) -> void:
	print(("  PASS " if ok else "  FAIL ")+label)
	if not ok: failures+=1

func _ready() -> void:
	call_deferred("_run")

func _reset(mass: float=0, engine: int=0, fuel: float=1) -> void:
	probe.set_meta("cargo_mass_kg",mass); probe.set_meta("engine_level",engine); probe.set_meta("fuel_ratio",fuel)
	probe.wings_out=false; probe.parked=false; probe._air_power=1.0
	probe.place(Vector3(0,220,0),Vector3.FORWARD)
	probe.apply(Controls.Intent.new())

func _step(count: int, intent: Controls.Intent) -> void:
	probe.apply(intent)
	for i in count:
		await get_tree().physics_frame
		probe.drive.force_wheel_update()
		probe._physics_process(DT)

func _accelerate(mass: float, engine: int, fuel: float, seconds: float=3) -> Dictionary:
	_reset(mass,engine,fuel)
	await _step(20,Controls.Intent.new())
	var start:=probe.global_position
	var input:=Controls.Intent.new(); input.throttle=1
	await _step(roundi(seconds/DT),input)
	return {"distance":Vector2(probe.global_position.x-start.x,probe.global_position.z-start.z).length(),"speed":probe.speed}

func _turn(mass: float) -> float:
	_reset(mass)
	await _step(20,Controls.Intent.new())
	var input:=Controls.Intent.new(); input.steer=.75; input.throttle=.5
	probe.apply(input)
	for i in 120:
		await get_tree().physics_frame
		probe.speed=18.0
		probe.drive.force_wheel_update()
		probe._physics_process(DT)
	return absf(probe.heading())

func _run() -> void:
	pad=StaticBody3D.new(); pad.collision_layer=1
	var shape:=CollisionShape3D.new(); var box:=BoxShape3D.new(); box.size=Vector3(950,2,950)
	shape.shape=box; pad.add_child(shape); pad.position.y=219; add_child(pad)
	probe=Bike.new(); probe.apply_definition(load("res://data/vehicles/bike.tres")); probe.ceiling=450
	add_child(probe); probe.set_physics_process(false); probe.terrain=null
	await get_tree().physics_frame
	var empty:=await _accelerate(0,0,1)
	var heavy:=await _accelerate(80,0,1)
	var upgraded:=await _accelerate(80,3,1)
	print("[ride] 3s empty=",empty," heavy=",heavy," heavy+engine3=",upgraded)
	_check(empty.distance>28 and empty.speed>19,"responsive unloaded launch covers %.1fm in3s at %.1fm/s"%[empty.distance,empty.speed])
	_check(heavy.distance<empty.distance*.8 and heavy.distance>empty.distance*.5,"80kg cargo measurably slows acceleration (%.1fm vs %.1fm)"%[heavy.distance,empty.distance])
	_check(upgraded.distance>heavy.distance*1.2,"engine upgrades restore loaded acceleration (%.1fm vs %.1fm)"%[upgraded.distance,heavy.distance])
	var limp:=await _accelerate(80,0,0,6)
	_check(limp.speed>1.5 and limp.speed<2.4 and limp.distance>5,"empty tank still travels at push pace (%.2fm/s, %.1fm)"%[limp.speed,limp.distance])
	_reset(); await _step(20,Controls.Intent.new())
	probe.speed=20; var start:=probe.global_position
	var brake_input:=Controls.Intent.new(); brake_input.brake=1
	await _step(200,brake_input)
	var stopping:=probe.global_position.distance_to(start)
	_check(absf(probe.speed)<.1 and stopping>7 and stopping<15,"braking stops from20m/s in %.1fm without reversing"%stopping)
	var light_turn:=await _turn(0)
	var loaded_turn:=await _turn(80)
	_check(loaded_turn<light_turn*.9 and loaded_turn>light_turn*.5,"cargo increases turning effort (%.2frad vs %.2frad in1s)"%[loaded_turn,light_turn])
	_check(absf(probe.lean)<=deg_to_rad(34.1),"rider lean remains bounded under sustained turning")
	await _step(40,Controls.Intent.new())
	_check(absf(probe.steer)<.001,"steering recentres cleanly after release")
	_reset(); await _step(20,Controls.Intent.new())
	probe.wings_out=true; probe.speed=16
	var fly_input:=Controls.Intent.new(); fly_input.throttle=1; fly_input.pitch=1
	await _step(1,fly_input)
	_check(probe.airborne,"unladen wings lift off at16m/s")
	_reset(80); await _step(20,Controls.Intent.new()); probe.wings_out=true; probe.speed=16
	await _step(1,fly_input)
	_check(not probe.airborne,"80kg cargo requires more runway speed than16m/s")
	probe.speed=19
	await _step(1,fly_input)
	_check(probe.airborne,"loaded bike still takes off after reaching19m/s")
	probe.global_position=Vector3(0,240,0); probe.speed=24; probe.flight_pitch=0; probe._air_power=1
	probe.set_meta("fuel_ratio",0.0)
	var initial_speed:=probe.speed; var initial_y:=probe.global_position.y
	await _step(1,fly_input)
	_check(probe.airborne and absf(probe.speed-initial_speed)<.5 and absf(probe.global_position.y-initial_y)<.2,"fuel depletion preserves continuous airborne motion")
	await _step(240,fly_input)
	_check(probe.speed>8 and probe.global_position.y<initial_y-.5,"empty tank settles into a controllable descending glide")
	probe.set_meta("cargo_mass_kg",999); probe.set_meta("engine_level",99); probe.set_meta("fuel_ratio",-2)
	var profile:=probe.performance_profile()
	_check(profile.mass_kg==80 and profile.engine_level==3 and profile.fuel_ratio==0,"performance metadata is clamped safely")
	await _drive_table()
	await _camera_checks()
	print("RIDING FEEL TESTS: %s (%d failures)"%["PASS" if failures==0 else "FAIL",failures])
	get_tree().quit(0 if failures==0 else 1)

## Every chase Framing goes through the same three checks. Before the framings became a real
## data table these could only be written for BIKE, because every other framing was defined by
## the `else` half of seven branches inside _chase_update.
func _camera_checks() -> void:
	for framing in [ChaseCamera.Framing.BIKE, ChaseCamera.Framing.PLANE, ChaseCamera.Framing.TRUCK]:
		var label: String = ChaseCamera.Framing.keys()[framing]
		_reset(); probe.speed = 18
		var camera := ChaseCamera.new(); add_child(camera); camera.set_physics_process(false)
		camera.follow(probe, framing); camera.snap_to_target()
		var fov_start := camera.fov
		probe.rotation.y = PI * .5
		camera._chase_update(CAMERA_DT)
		_check(absf(camera._yaw) > .005 and absf(camera._yaw) < .30,
			"%s: camera eases into turns instead of snapping to rider yaw (%.3frad)" % [label, camera._yaw])
		for i in 59: camera._chase_update(CAMERA_DT)
		var yaw60 := camera._yaw; var fov60 := camera.fov
		probe.rotation.y = 0; camera.snap_to_target(); camera.fov = fov_start
		probe.rotation.y = PI * .5
		for i in 120: camera._chase_update(CAMERA_DT * .5)
		_check(absf(camera._yaw - yaw60) < .002 and absf(camera.fov - fov60) < .002,
			"%s: camera yaw and FOV smoothing are stable across60/120Hz" % label)
		probe.rotation.y = 0; camera.snap_to_target()
		var wall := StaticBody3D.new(); wall.collision_layer = 1
		var collision := CollisionShape3D.new(); var box := BoxShape3D.new(); box.size = Vector3(8, 4, .3)
		collision.shape = box; wall.add_child(collision); add_child(wall)
		wall.global_position = probe.global_position + Vector3(0, 1, 2)
		await get_tree().physics_frame
		await get_tree().physics_frame
		camera._chase_update(CAMERA_DT)
		_check(camera.global_position.z < wall.global_position.z - .2,
			"%s: camera retracts in front of a newly encountered wall immediately" % label)
		wall.queue_free(); camera.queue_free()
		await get_tree().physics_frame


## The same table of driving feel, run against every vehicle in data/vehicles. Before the
## GroundDrive was extracted this could only be written once per vehicle, so the truck had none.
func _drive_table() -> void:
	for path in ["res://data/vehicles/bike.tres", "res://data/vehicles/truck.tres"]:
		var definition: VehicleDefinition = load(path)
		var v: Vehicle = (Bike.new() if definition.can_fly else Truck.new())
		v.apply_definition(definition)
		add_child(v)
		v.set_physics_process(false)
		v.terrain = null
		await get_tree().physics_frame
		v.place(Vector3(0, 220, 0), Vector3.FORWARD)
		var name_of: String = definition.display_name
		# accelerates from rest
		await _drive_steps(v, 30, Controls.Intent.new())
		var go := Controls.Intent.new(); go.throttle = 1
		await _drive_steps(v, roundi(2.0 / DT), go)
		_check(v.speed > definition.max_speed * .35, "%s: full throttle reaches %.1fm/s in 2s" % [name_of, v.speed])
		# coasting bleeds speed
		var coast_from := v.speed
		await _drive_steps(v, roundi(1.0 / DT), Controls.Intent.new())
		_check(v.speed < coast_from - .5, "%s: coasting bleeds speed (%.1f -> %.1f)" % [name_of, coast_from, v.speed])
		# braking stops without rolling into reverse
		v.speed = definition.max_speed * .6
		var stop := Controls.Intent.new(); stop.brake = 1
		await _drive_steps(v, roundi(4.0 / DT), stop)
		_check(v.speed >= -0.001, "%s: braking to a stop never rolls into reverse (%.3fm/s)" % [name_of, v.speed])
		# reverse engages after releasing and re-pressing the brake
		await _drive_steps(v, 10, Controls.Intent.new())
		await _drive_steps(v, roundi(1.5 / DT), stop)
		_check(v.speed < -0.2, "%s: a fresh brake press reverses (%.2fm/s)" % [name_of, v.speed])
		# the handbrake brings it back to a stop
		v.speed = definition.max_speed * .4
		var hb := Controls.Intent.new(); hb.handbrake = true
		await _drive_steps(v, roundi(4.0 / DT), hb)
		_check(absf(v.speed) < .2, "%s: handbrake stops it (%.2fm/s)" % [name_of, v.speed])
		v.queue_free()
		await get_tree().physics_frame


func _drive_steps(v: Vehicle, count: int, intent: Controls.Intent) -> void:
	v.apply(intent)
	for i in count:
		await get_tree().physics_frame
		v.drive.force_wheel_update()
		v._physics_process(DT)
