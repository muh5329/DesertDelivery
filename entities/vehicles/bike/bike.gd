class_name Bike
extends Vehicle
## The red courier motorbike. Ground driving is the shared GroundDrive (data/vehicles/bike.tres);
## what is genuinely the bike's own is up here: the wings, arcade flight, and the performance
## profile that turns cargo, fuel and engine level into how it drives this tick.

signal crashed
signal landed(impact: float)
signal transformed(wings_out: bool)
signal took_off
signal landed_plane
signal hard_landing(sink: float)
signal denied(text: String)
signal fell_in_sea

var lean := 0.0                 # visual lean angle (rad)
var wings_out := false          # wings deployed (T)
var airborne := false           # actually flying
var flight_pitch := 0.0         # rad, + nose up
var flight_roll := 0.0          # rad, NEGATIVE = right wing down (steer right)
var altitude := 0.0
var ceiling := 5000.0           # metres above sea level; overridable by flight fixtures
var sea_resets := 0

var _pitch_in := 0.0            # flight pitch input (+ nose up)
var _air_power := 1.0
var _boost := false
var _dust: CPUParticles3D

# Tunables belong to the definition; these are windows onto it, not a second authority.
var max_speed: float:
	get: return definition.max_speed if definition else 0.0
var takeoff_speed: float:
	get: return definition.takeoff_speed if definition else 0.0
var flight_max_speed: float:
	get: return definition.flight_max_speed if definition else 0.0
var flight_thrust: float:
	get: return definition.flight_thrust if definition else 0.0
var gravity: float:
	get: return definition.gravity if definition else 22.0


func apply_definition(d: VehicleDefinition) -> void:
	super.apply_definition(d)
	ceiling = d.ceiling


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | 16
	var cs := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.42
	shape.height = 2.1
	cs.shape = shape
	cs.rotation_degrees = Vector3(90, 0, 0)
	cs.position = Vector3(0, 0.55, 0)
	add_child(cs)
	floor_max_angle = deg_to_rad(60)
	floor_snap_length = 0.0 if definition.suspension_enabled else 0.6
	safe_margin = 0.012

	var wb: float = definition.wheelbase if definition else 1.5
	_build_drive([Vector3(0, 0.8, -wb * 0.5), Vector3(0, 0.8, wb * 0.5)], 2.4)

	visual = load("res://entities/vehicles/bike/bike_visual.gd").new()
	add_child(visual)
	_build_dust()


func _build_dust() -> void:
	_dust = CPUParticles3D.new()
	_dust.amount = 48
	_dust.lifetime = 1.3
	_dust.emitting = false
	_dust.local_coords = false
	_dust.position = Vector3(0, 0.1, 0.9)
	_dust.direction = Vector3(0, 0.6, 1)
	_dust.spread = 35
	_dust.initial_velocity_min = 1.5
	_dust.initial_velocity_max = 3.5
	_dust.gravity = Vector3(0, 0.6, 0)
	_dust.scale_amount_min = 0.5
	_dust.scale_amount_max = 1.1
	_dust.damping_min = 1.0
	_dust.damping_max = 2.0
	var dm := QuadMesh.new()
	dm.size = Vector2(.8, .8)
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color(0.72, 0.66, 0.53, 0.25)
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dmat.vertex_color_use_as_albedo = true
	var soft := GradientTexture2D.new(); soft.width = 64; soft.height = 64
	soft.fill = GradientTexture2D.FILL_RADIAL; soft.fill_from = Vector2(.5, .5); soft.fill_to = Vector2(1, .5)
	soft.gradient = Gradient.new(); soft.gradient.set_color(0, Color.WHITE); soft.gradient.set_color(1, Color(1, 1, 1, 0))
	dmat.albedo_texture = soft
	dm.material = dmat
	_dust.mesh = dm
	_dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_dust.scale_amount_curve = Curve.new()
	_dust.scale_amount_curve.add_point(Vector2(0, 0.4))
	_dust.scale_amount_curve.add_point(Vector2(0.6, 1.4))
	_dust.scale_amount_curve.add_point(Vector2(1, 1.8))
	_dust.color_ramp = Gradient.new()
	_dust.color_ramp.set_color(0, Color(1, 1, 1, 0.7))
	_dust.color_ramp.set_color(1, Color(1, 1, 1, 0.0))
	add_child(_dust)


func place(pos: Vector3, forward: Vector3) -> void:
	place_on_road(pos, forward)


func place_on_road(pos: Vector3, forward: Vector3) -> void:
	drive.place(pos, forward)
	airborne = false
	flight_pitch = 0.0
	flight_roll = 0.0
	lean = 0.0


func forward_dir() -> Vector3:
	return -global_transform.basis.z


func save_state() -> Dictionary:
	var d := super.save_state()
	d["wings_out"] = wings_out
	return d


func load_state(d: Dictionary) -> void:
	super.load_state(d)
	if bool(d.get("wings_out", false)) != wings_out:
		toggle_wings()


func status_line() -> String:
	return "Plane" if wings_out else "Bike"


## Out of fuel the engine limps on the last of the float bowl and the reserve line: 25 km/h,
## slow to pick up, so the nearest pump (never more than ~2.6 km along a highway) is a few
## minutes away rather than an hour's push.
const LIMP_SPEED := 7.0
const LIMP_ACCEL := 2.0


## Journey owns persisted cargo, upgrades and fuel. Reading metadata keeps vehicle tuning
## independent of the delivery UI and economy manager.
func performance_profile() -> Dictionary:
	var mass := clampf(float(get_meta("cargo_mass_kg", 0.0)), 0, 80)
	var engine := clampi(int(get_meta("engine_level", 0)), 0, 3)
	var fuel := clampf(float(get_meta("fuel_ratio", 1.0)), 0, 1)
	var power := 1.0 + float(engine) * .12
	return {"mass_kg": mass, "engine_level": engine, "fuel_ratio": fuel,
		"power_factor": power, "acceleration_factor": power / (1.0 + mass / 140.0),
		"handling_factor": 1.0 / (1.0 + mass / 200.0), "braking_factor": 1.0 / sqrt(1.0 + mass / 200.0),
		"takeoff_speed": takeoff_speed * sqrt(1.0 + mass / 200.0),
		"ground_speed_limit": LIMP_SPEED if fuel <= .001 else max_speed * (1.0 + float(engine) * .025)}


## In the air the bike runs to flight speeds, so the camera's speed factor scales to those.
func camera_top_speed() -> float:
	return 40.0 if airborne else super()


func at_takeoff_speed() -> bool:
	var performance := performance_profile()
	return wings_out and performance.fuel_ratio > .001 and speed >= float(performance.takeoff_speed) - 2.0


func _drive_mods() -> GroundDrive.Mods:
	var p := performance_profile()
	var m := GroundDrive.Mods.new()
	m.top_speed = max_speed
	m.motor_accel = LIMP_ACCEL if p.fuel_ratio <= .001 else definition.accel * float(p.acceleration_factor)
	m.brake_scale = float(p.braking_factor)
	m.handling = float(p.handling_factor)
	m.soft_limit = float(p.ground_speed_limit)
	m.reverse_limit = minf(definition.reverse_speed, float(p.ground_speed_limit))
	return m


## Flight-stick convention: with the wings out, pull back (S) raises the nose and push
## forward (W) lowers it — so S stops being a brake exactly when the bike stops being a bike.
class BikeScheme:
	extends Vehicle.GroundScheme
	func map(r: Controls.Reading, i: Controls.Intent) -> void:
		super.map(r, i)
		if r.just(&"transform"): i.press(Controls.WINGS)
		var bike: Bike = vehicle
		if not bike.wings_out: return
		i.handbrake = false                       # Space is unused with the wings out
		if bike.airborne:
			i.pitch = r.back - r.forward
			i.brake = 0.0
		elif bike.at_takeoff_speed():
			i.pitch = r.back                      # on the takeoff roll S rotates, it never brakes
			i.brake = 0.0


func _make_scheme() -> Controls.Scheme:
	return BikeScheme.new(self)


func toggle_wings() -> void:
	if airborne:
		denied.emit("Land first — the wings can't fold in the air.")
		return
	wings_out = not wings_out
	transformed.emit(wings_out)


func _physics_process(delta: float) -> void:
	if parked:
		# rider is off the bike: it just sits there under gravity
		drive.idle(delta)
		if visual: visual.update_visual(self, delta)
		_dust.emitting = false
		return
	drive.mods = _drive_mods()
	drive.read_intent(delta)
	drive.handbrake = drive.handbrake and not wings_out
	_pitch_in = drive.intent.pitch
	_boost = drive.intent.boost
	if wings_out and airborne:
		_flight(delta)
		return
	var p := performance_profile()
	if wings_out and not airborne and speed >= float(p.takeoff_speed) and float(p.fuel_ratio) > .001 and _pitch_in > 0.3:
		airborne = true
		grounded = false
		flight_pitch = deg_to_rad(12.0)
		took_off.emit()
		_flight(delta)
		return

	var tick := drive.step(delta)
	if tick.landed_impact >= 0.0: landed.emit(tick.landed_impact)
	if tick.crashed: crashed.emit()
	var target_lean := clampf(-atan2(speed * drive.yaw_input, gravity * .78), -deg_to_rad(34.0), deg_to_rad(34.0))
	if speed < 0.5: target_lean = 0.0
	lean = lerpf(lean, target_lean, clampf(7.0 * delta, 0, 1))
	if tick.in_sea:
		sea_resets += 1
		fell_in_sea.emit()
		reset_to_road(true)
	if visual: visual.update_visual(self, delta)
	var paved: bool = terrain and terrain.biome_at(global_position.x, global_position.z) == Terrain.Biome.TOWN \
		and terrain.road_dist_at(global_position.x, global_position.z) < 5.5
	_dust.emitting = grounded and absf(speed) > definition.dust_min_speed and (not paved or slip > .25)
	_dust.speed_scale = 1.0 + slip
	_dust.initial_velocity_max = 2.5 + slip * 4.0


## Arcade flight: thrust along the nose, bank to turn, climb/dive with the pitch input.
func _flight(delta: float) -> void:
	var performance := performance_profile()
	var lift_speed: float = performance.takeoff_speed
	var available := lerpf(.22, 1.0, smoothstep(0, .08, float(performance.fuel_ratio)))
	_air_power = move_toward(_air_power, available, delta * .65)
	var climb := _pitch_in
	# pitch / roll targets from input; a stall (too slow) forces the nose down
	var lift_now := clampf((speed - 6.0) / (lift_speed - 6.0), 0.0, 1.0)
	var pitch_t := climb * deg_to_rad(26.0)
	if performance.fuel_ratio <= .001:
		# Reserve power and a shallow descent give the courier time to land.
		pitch_t = minf(pitch_t, deg_to_rad(-6.0))
	if lift_now < 0.35:
		pitch_t = minf(pitch_t, deg_to_rad(-36.0) * (1.0 - lift_now / 0.35))
	var roll_t := -drive.steer * deg_to_rad(48.0)
	flight_pitch = lerpf(flight_pitch, pitch_t, clampf(3.0 * delta, 0, 1))
	flight_roll = lerpf(flight_roll, roll_t, clampf(3.5 * float(performance.handling_factor) * delta, 0, 1))
	# banking turns the nose
	drive.yaw += sin(flight_roll) * 1.1 * delta * clampf(speed / 20.0, 0.3, 1.2)
	# thrust & drag: automatic cruise power in the air, boost gives full power (W/S are pitch here)
	var power := 1.0 if _boost else maxf(0.65, drive.throttle)
	var thrust: float = power * flight_thrust * float(performance.acceleration_factor) * _air_power
	speed += (thrust - 0.02 * speed * speed / 6.0 - 0.8) * delta
	speed -= sin(flight_pitch) * 6.0 * delta      # climbing bleeds speed, diving gains it
	speed = clampf(speed, 0.0, flight_max_speed)
	# stall: too slow -> nose drops
	var lift := clampf((speed - 6.0) / (lift_speed - 6.0), 0.0, 1.0)
	var fwd := flat_forward()
	var nose := (fwd * cos(flight_pitch) + Vector3.UP * sin(flight_pitch)).normalized()
	var vel := nose * speed
	vel.y -= (1.0 - lift) * gravity * 0.6
	# ground effect: the last few metres cushion the sink so a gentle glide lands softly
	var agl := global_position.y - (terrain.height_at(global_position.x, global_position.z) if terrain else 0.0)
	if agl < 4.0 and vel.y < 0.0:
		vel.y *= lerpf(0.35, 1.0, clampf(agl / 4.0, 0.0, 1.0))
	if vel.y > 0.0:
		# Limit ascent, never teleport a loaded/spawned bike downward through terrain.
		vel.y = minf(vel.y, maxf(0.0, ceiling - global_position.y) / maxf(delta, .000001))
		if global_position.y >= ceiling:
			flight_pitch = minf(flight_pitch, 0.0)
	velocity = vel
	var sink_before := -vel.y
	move_and_slide()
	# turn back at the edge of the world
	var edge := Terrain.SIZE * 0.5 - 30.0
	if absf(global_position.x) > edge or absf(global_position.z) > edge:
		var to_centre := Vector3(-global_position.x, 0, -global_position.z).normalized()
		var want_yaw := atan2(-to_centre.x, -to_centre.z)
		drive.yaw = lerp_angle(drive.yaw, want_yaw, clampf(2.5 * delta, 0, 1))
	altitude = global_position.y - (terrain.height_at(global_position.x, global_position.z) if terrain else 0.0)
	for i in range(get_slide_collision_count()):
		var n := get_slide_collision(i).get_normal()
		if n.y < 0.6 and absf(speed) > 6.0:
			speed *= 0.4
			crashed.emit()
	# touchdown
	drive.force_wheel_update()
	var wheel_h := drive.wheel_ground_height()
	# Wing flight hands over only when the extended tires actually reach the
	# surface; the former .35m threshold produced a second, spring-solver landing.
	var touchdown_height := maxf(.08, definition.suspension_rest_height) if definition.suspension_enabled else .35
	var ground_close := (not is_nan(wheel_h) and global_position.y - wheel_h < touchdown_height) or is_on_floor()
	if ground_close and velocity.y <= 0.5:
		airborne = false
		grounded = true
		drive.capture_velocity(velocity)
		flight_pitch = 0.0
		var sink := maxf(sink_before, -velocity.y)
		var hard := absf(flight_roll) > 0.6 or speed > 32.0 or sink > 8.0
		flight_roll = 0.0
		if hard:
			speed *= 0.4
			crashed.emit()
			hard_landing.emit(sink)
		landed_plane.emit()
		landed.emit(maxf(4.0, sink))
	rotation = Vector3(0, drive.yaw, 0)
	rotate_object_local(Vector3.RIGHT, flight_pitch)
	lean = lerpf(lean, flight_roll * 0.9, clampf(6.0 * delta, 0, 1))
	odometer += speed * delta
	if terrain and global_position.y < Terrain.SEA_LEVEL - 0.35:
		sea_resets += 1
		airborne = false
		fell_in_sea.emit()
		reset_to_road(true)
	if visual: visual.update_visual(self, delta)
	_dust.emitting = false
