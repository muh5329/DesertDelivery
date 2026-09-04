class_name Bike
extends CharacterBody3D
## Arcade motorbike controller (rider + bike). Kinematic, terrain-aligned.
## Tuned to feel like the reference: quick to get going, wide easy drifts on dirt,
## a little air off crests, forgiving collisions.

signal crashed
signal landed(impact: float)

@export var max_speed := 27.0          # m/s (~97 km/h)
@export var reverse_speed := 5.0
@export var accel := 9.5
@export var brake_decel := 16.0
@export var drag := 0.55               # linear
@export var drag_quad := 0.012         # quadratic
@export var steer_rate_low := 1.9      # rad/s at standstill
@export var steer_rate_high := 0.75    # rad/s at max speed
@export var gravity := 22.0
@export var wheelbase := 1.5

var speed := 0.0            # signed forward speed
var steer := 0.0            # smoothed steer input (-1..1)
var throttle := 0.0
var brake := 0.0
var handbrake := false
var grounded := true
var air_time := 0.0
var lean := 0.0             # visual lean angle (rad)
var vertical_vel := 0.0
var ground_normal := Vector3.UP
var slip := 0.0             # lateral slide amount for dust / drift
var odometer := 0.0
var _intent: Controls.Intent = Controls.Intent.new()   # what the rider asked for this tick
var _pitch_in := 0.0        # flight pitch input (+ nose up)
var _boost := false

var visual: Node3D
var terrain: Terrain
var _ray_front: RayCast3D
var _ray_rear: RayCast3D
var _yaw := 0.0
var _pitch := 0.0
var _was_grounded := true
var _last_vertical := 0.0
var _dust: CPUParticles3D
# --- plane mode
signal transformed(wings_out: bool)
signal took_off
signal landed_plane
signal hard_landing(sink: float)
signal denied(text: String)
var wings_out := false          # wings deployed (T)
var airborne := false           # actually flying
var flight_pitch := 0.0         # rad, + nose up
var flight_roll := 0.0          # rad, NEGATIVE = right wing down (steer right)
var altitude := 0.0
var parked := false             # rider dismounted; set only by the Rider module (set_parked)
@export var takeoff_speed := 15.0
@export var flight_max_speed := 46.0
@export var flight_thrust := 11.0
var _rev_hold := 0.0        # seconds the brake has been held at standstill (reverse engages after a beat)
var _brake_repressed := true # reverse needs a fresh brake press once the bike has stopped
var sea_resets := 0
signal fell_in_sea


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	var cs := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.42
	shape.height = 2.1
	cs.shape = shape
	cs.rotation_degrees = Vector3(90, 0, 0)
	cs.position = Vector3(0, 0.55, 0)
	add_child(cs)
	floor_max_angle = deg_to_rad(60)
	floor_snap_length = 0.6
	safe_margin = 0.03

	_ray_front = RayCast3D.new()
	_ray_front.position = Vector3(0, 0.8, -wheelbase * 0.5)
	_ray_front.target_position = Vector3(0, -2.4, 0)
	_ray_front.collision_mask = 1
	add_child(_ray_front)
	_ray_rear = RayCast3D.new()
	_ray_rear.position = Vector3(0, 0.8, wheelbase * 0.5)
	_ray_rear.target_position = Vector3(0, -2.4, 0)
	_ray_rear.collision_mask = 1
	add_child(_ray_rear)

	visual = load("res://scripts/bike_visual.gd").new()
	add_child(visual)

	_dust = CPUParticles3D.new()
	_dust.amount = 48
	_dust.lifetime = 1.3
	_dust.emitting = false
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
	var dm := SphereMesh.new()
	dm.radius = 0.35; dm.height = 0.7
	dm.radial_segments = 8; dm.rings = 4
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color(0.84, 0.74, 0.56, 0.30)
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.material = dmat
	_dust.mesh = dm
	_dust.scale_amount_curve = Curve.new()
	_dust.scale_amount_curve.add_point(Vector2(0, 0.4))
	_dust.scale_amount_curve.add_point(Vector2(0.6, 1.4))
	_dust.scale_amount_curve.add_point(Vector2(1, 1.8))
	_dust.color_ramp = Gradient.new()
	_dust.color_ramp.set_color(0, Color(1, 1, 1, 0.7))
	_dust.color_ramp.set_color(1, Color(1, 1, 1, 0.0))
	add_child(_dust)


func place_on_road(pos: Vector3, forward: Vector3) -> void:
	global_position = pos + Vector3(0, 0.08, 0)
	_yaw = atan2(-forward.x, -forward.z)
	rotation = Vector3(0, _yaw, 0)
	speed = 0.0
	vertical_vel = 0.0
	velocity = Vector3.ZERO
	grounded = true
	airborne = false
	flight_pitch = 0.0
	flight_roll = 0.0


func forward_dir() -> Vector3:
	return -global_transform.basis.z


func flat_forward() -> Vector3:
	var f := Vector3(-sin(_yaw), 0, -cos(_yaw))
	return f.normalized()


## The Rider hands the bike its ControlIntent once per physics tick, before the bike steps.
func apply(intent: Controls.Intent) -> void:
	_intent = intent


func set_parked(v: bool) -> void:
	parked = v
	if v:
		speed = 0.0


func heading() -> float:
	return _yaw


func at_takeoff_speed() -> bool:
	return wings_out and speed >= takeoff_speed - 2.0


func _read_intent() -> void:
	throttle = _intent.throttle
	brake = _intent.brake
	handbrake = _intent.handbrake and not wings_out
	_pitch_in = _intent.pitch
	_boost = _intent.boost
	var rate := 5.0 if absf(_intent.steer) > 0.05 else 8.0
	steer = move_toward(steer, _intent.steer, rate * get_physics_process_delta_time())


func toggle_wings() -> void:
	if airborne:
		denied.emit("Land first — the wings can't fold in the air.")
		return
	wings_out = not wings_out
	transformed.emit(wings_out)


## Arcade flight: thrust along the nose, bank to turn, climb/dive with the pitch input.
func _flight(delta: float) -> void:
	var climb := _pitch_in
	# pitch / roll targets from input; a stall (too slow) forces the nose down
	var lift_now := clampf((speed - 6.0) / (takeoff_speed - 6.0), 0.0, 1.0)
	var pitch_t := climb * deg_to_rad(26.0)
	if lift_now < 0.35:
		pitch_t = minf(pitch_t, deg_to_rad(-36.0) * (1.0 - lift_now / 0.35))
	var roll_t := -steer * deg_to_rad(48.0)
	flight_pitch = lerpf(flight_pitch, pitch_t, clampf(3.0 * delta, 0, 1))
	flight_roll = lerpf(flight_roll, roll_t, clampf(3.5 * delta, 0, 1))
	# banking turns the nose
	_yaw += sin(flight_roll) * 1.1 * delta * clampf(speed / 20.0, 0.3, 1.2)   # bank right -> turn right
	# thrust & drag: automatic cruise power in the air, boost gives full power (W/S are pitch here)
	var power := 1.0 if _boost else maxf(0.65, throttle)
	var thrust := power * flight_thrust
	speed += (thrust - 0.02 * speed * speed / 6.0 - 0.8) * delta
	speed -= sin(flight_pitch) * 6.0 * delta      # climbing bleeds speed, diving gains it
	speed = clampf(speed, 0.0, flight_max_speed)
	# stall: too slow -> nose drops
	var lift := clampf((speed - 6.0) / (takeoff_speed - 6.0), 0.0, 1.0)
	var fwd := flat_forward()
	var nose := (fwd * cos(flight_pitch) + Vector3.UP * sin(flight_pitch)).normalized()
	var vel := nose * speed
	vel.y -= (1.0 - lift) * gravity * 0.6
	# ground effect: the last few metres cushion the sink so a gentle glide lands softly
	var agl := global_position.y - (terrain.height_at(global_position.x, global_position.z) if terrain else 0.0)
	if agl < 4.0 and vel.y < 0.0:
		vel.y *= lerpf(0.35, 1.0, clampf(agl / 4.0, 0.0, 1.0))
	# ceiling: the bike simply can't climb past it
	if global_position.y > 170.0 and vel.y > 0.0:
		vel.y = 0.0
		flight_pitch = minf(flight_pitch, 0.0)
	velocity = vel
	var sink_before := -vel.y
	move_and_slide()
	if global_position.y > 171.0:
		global_position.y = 171.0
	# turn back at the edge of the world
	var edge := 330.0
	if absf(global_position.x) > edge or absf(global_position.z) > edge:
		var to_centre := Vector3(-global_position.x, 0, -global_position.z).normalized()
		var want_yaw := atan2(-to_centre.x, -to_centre.z)
		_yaw = lerp_angle(_yaw, want_yaw, clampf(2.5 * delta, 0, 1))
	altitude = global_position.y - (terrain.height_at(global_position.x, global_position.z) if terrain else 0.0)
	# collisions with cliffs / props
	for i in range(get_slide_collision_count()):
		var c := get_slide_collision(i)
		var n := c.get_normal()
		if n.y < 0.6 and absf(speed) > 6.0:
			speed *= 0.4
			crashed.emit()
	# touchdown
	var ground_close := (_ray_rear.is_colliding() and global_position.y - _ray_rear.get_collision_point().y < 0.35) or is_on_floor()
	if ground_close and velocity.y <= 0.5:
		airborne = false
		grounded = true
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
	rotation = Vector3(0, _yaw, 0)
	rotate_object_local(Vector3.RIGHT, flight_pitch)
	lean = lerpf(lean, flight_roll * 0.9, clampf(6.0 * delta, 0, 1))
	odometer += speed * delta
	if terrain and global_position.y < Terrain.SEA_LEVEL - 0.35:
		sea_resets += 1
		airborne = false
		fell_in_sea.emit()
		reset_to_road(true)
	if visual:
		visual.update_visual(self, delta)
	_dust.emitting = false


func _physics_process(delta: float) -> void:
	if parked:
		# rider is off the bike: it just sits there under gravity
		velocity = Vector3(0, velocity.y - gravity * delta, 0) if not is_on_floor() else Vector3(0, -1.0, 0)
		move_and_slide()
		if visual: visual.update_visual(self, delta)
		_dust.emitting = false
		return
	_read_intent()
	if wings_out and airborne:
		_flight(delta)
		return
	if wings_out and not airborne and speed >= takeoff_speed and _pitch_in > 0.3:
		airborne = true
		grounded = false
		flight_pitch = deg_to_rad(12.0)
		took_off.emit()
		_flight(delta)
		return

	# --- Longitudinal
	var sf := clampf(absf(speed) / max_speed, 0.0, 1.0)
	if grounded:
		if throttle > 0.0 and speed >= -0.1:
			# torque curve: strong at low speed, tapering toward max
			speed += throttle * accel * (1.15 - 0.55 * sf) * delta
		if brake > 0.0:
			if speed > 0.2:
				speed -= brake * brake_decel * delta
				speed = maxf(speed, 0.0)
				_rev_hold = 0.0
			else:
				# reverse only after the brake has been held for a beat at standstill,
				# so braking into a delivery ring never flips into reverse by accident
				_rev_hold += delta
				if _rev_hold > 0.35 and _brake_repressed:
					speed -= brake * accel * 0.5 * delta
					speed = maxf(speed, -reverse_speed)
		else:
			_rev_hold = 0.0
			_brake_repressed = true          # brake released: the next press can reverse
		if speed > 0.5:
			_brake_repressed = false         # a brake-to-stop never rolls straight into reverse
		if handbrake and speed > 0.0:
			speed -= 11.0 * delta
			speed = maxf(speed, 0.0)
		# drag (also handles engine braking when coasting)
		var d := drag + drag_quad * absf(speed)
		if throttle < 0.05 and brake < 0.05:
			d += 1.2
		speed = move_toward(speed, 0.0, d * delta)
		# the surface normal leans away from the uphill direction, so dot < 0 when climbing
		var terrain_slope := ground_normal.dot(flat_forward())
		speed += terrain_slope * 5.5 * delta
		# holding the brake (or handbrake) at standstill keeps the bike from rolling on slopes
		if (brake > 0.0 and _rev_hold <= 0.35) or handbrake:
			if absf(speed) < 0.6 and throttle < 0.05:
				speed = 0.0
	speed = clampf(speed, -reverse_speed, max_speed * 1.08)

	# --- Steering (yaw). Reduced when airborne.
	var sr := lerpf(steer_rate_low, steer_rate_high, sf)
	var yaw_in := steer * sr * clampf(absf(speed) / 1.5, 0.0, 1.0)
	if speed < 0.0: yaw_in = -yaw_in
	if handbrake and speed > 4.0:
		yaw_in *= 1.6
	if not grounded:
		yaw_in *= 0.25
	_yaw -= yaw_in * delta
	# lateral slip during hard turns at speed -> drift dust & slight speed scrub
	slip = clampf(absf(steer) * sf * (1.6 if handbrake else 0.9), 0.0, 1.0)
	if grounded and slip > 0.5:
		speed -= (slip - 0.5) * 6.0 * delta

	# --- Vertical / ground contact
	var fwd := flat_forward()
	if grounded:
		vertical_vel = 0.0
	else:
		vertical_vel -= gravity * delta
	var vel := fwd * speed
	# hug the slope while grounded so we don't launch off every bump
	if grounded:
		var along := ground_normal
		var f_on_slope := (fwd - along * along.dot(fwd)).normalized()
		vel = f_on_slope * speed
		vel.y -= 2.0  # extra snap
	else:
		vel.y = vertical_vel
	velocity = vel
	move_and_slide()

	# Update grounded state from the body + rays.
	_was_grounded = grounded
	grounded = is_on_floor()
	if not grounded and velocity.y <= 0.0 and (_ray_front.is_colliding() or _ray_rear.is_colliding()):
		var gh := _ray_rear.get_collision_point().y if _ray_rear.is_colliding() else _ray_front.get_collision_point().y
		if global_position.y - gh < 0.25:
			grounded = true
	if grounded:
		if not _was_grounded:
			var impact := absf(_last_vertical)
			landed.emit(impact)
			if impact > 9.0:
				speed *= 0.7
		air_time = 0.0
		vertical_vel = 0.0
	else:
		air_time += delta
		_last_vertical = velocity.y
		vertical_vel = velocity.y

	# Wall / obstacle hits: scrub speed.
	for i in range(get_slide_collision_count()):
		var c := get_slide_collision(i)
		var n := c.get_normal()
		if n.y < 0.5:
			var head_on := -n.dot(fwd)
			if head_on > 0.4 and absf(speed) > 3.0:
				speed *= clampf(1.0 - head_on * 0.85, 0.05, 1.0)
				if head_on > 0.8 and absf(speed) > 8.0:
					crashed.emit()
			elif head_on > 0.0:
				speed *= 0.985

	# --- Ground normal & pitch from wheel rays
	var n_target := Vector3.UP
	var pitch_target := 0.0
	if _ray_front.is_colliding() and _ray_rear.is_colliding():
		var pf := _ray_front.get_collision_point()
		var pr := _ray_rear.get_collision_point()
		var dy := pf.y - pr.y
		pitch_target = atan2(dy, wheelbase)
		n_target = (_ray_front.get_collision_normal() + _ray_rear.get_collision_normal()).normalized()
	elif not grounded:
		pitch_target = clampf(vertical_vel * 0.05, -0.5, 0.35)
	ground_normal = ground_normal.lerp(n_target, clampf(10.0 * delta, 0, 1)).normalized()
	_pitch = lerpf(_pitch, pitch_target, clampf(9.0 * delta, 0, 1))
	var target_lean := -steer * clampf(sf * 1.4, 0.0, 1.0) * deg_to_rad(34.0)
	if speed < 0.5: target_lean = 0.0
	lean = lerpf(lean, target_lean, clampf(7.0 * delta, 0, 1))
	rotation = Vector3(0, _yaw, 0)
	rotate_object_local(Vector3.RIGHT, _pitch)

	odometer += absf(speed) * delta
	# fell into the sea -> put the rider back on the nearest road
	if terrain and global_position.y < Terrain.SEA_LEVEL - 0.35:
		sea_resets += 1
		fell_in_sea.emit()
		reset_to_road(true)
	if visual:
		visual.update_visual(self, delta)
	_dust.emitting = grounded and absf(speed) > 3.0
	_dust.speed_scale = 1.0 + slip
	_dust.initial_velocity_max = 2.5 + slip * 4.0


func reset_to_road(away_from_sea: bool = false) -> void:
	airborne = false
	var road := terrain.nearest_road(global_position)
	var p: Vector3 = road.point
	var t: Vector3 = road.tangent
	if away_from_sea:
		# point the bike away from the water: whichever way along the road leads inland (towards the island centre)
		if t.dot(-Vector3(p.x, 0, p.z).normalized()) < 0.0: t = -t
	elif t.dot(flat_forward()) < 0.0:
		t = -t
	place_on_road(Vector3(p.x, maxf(p.y, terrain.height_at(p.x, p.z)), p.z), t)   # road sample height: on a bridge deck the heightfield is the water below


func speed_kmh() -> float:
	return absf(speed) * 3.6
