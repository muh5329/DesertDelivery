class_name GroundDrive
extends RefCounted
## Driving a wheeled thing over the island: one ControlIntent in, one tick of kinematics out.
##
## This is the whole of what the Bike and the Truck used to have in common — throttle and brake,
## the reverse latch, drag and slope, steering and drift, wheel rays, ground contact, wall scrubs,
## landings, and getting back on a road after a swim. Both of them had their own copy of it, and
## the copies had drifted. Now there is one implementation and two `.tres` files.
##
## Interface:
##   GroundDrive.new(body, definition)   the body it moves; the tunables it moves by
##   add_wheel_rays(offsets)             wheel contact points, in body space
##   intent                              this tick's ControlIntent (set it before step)
##   mods                                this tick's Mods — cargo, fuel, upgrades (set before step)
##   step(delta) -> Tick                 one physics tick; Tick reports what the owner must react to
##   place(pos, forward)                 teleport, upright and stationary
##   recover_to_road(away_from_sea)      nearest road point, facing sensibly
##   speed / yaw / pitch / grounded / ground_normal / slip / air_time / odometer / steer / …
##
## The owner decides what a Tick *means*: the Bike emits `landed`, the Truck turns a hard landing
## into `crashed`. The drive itself has no signals and knows nothing about wings, cargo or winches.


## Per-tick performance modifiers. The owner recomputes these from whatever it cares about —
## the Bike from its fuel, engine level and cargo mass, the Truck from how full the rack is —
## so the drive never learns about the economy.
class Mods extends RefCounted:
	var top_speed := 27.0          ## forward ceiling this tick (m/s), before `overspeed`
	var motor_accel := 9.5         ## absolute forward acceleration (m/s²)
	var brake_scale := 1.0
	var handling := 1.0            ## 1 = nimble, < 1 = heavy: steering rate and steer smoothing
	var soft_limit := INF          ## speed the drive rolls back down to if exceeded (a spent tank)
	var reverse_limit := 5.0


## What one tick did that the owner may need to react to. Everything else stays inside the drive.
class Tick extends RefCounted:
	var landed_impact := -1.0      ## >= 0 on the tick the wheels touched down; the sink speed
	var crashed := false           ## a square hit at speed
	var in_sea := false            ## below the waterline; the owner usually calls recover_to_road


var speed := 0.0
var yaw := 0.0
var pitch := 0.0
var grounded := true
var ground_normal := Vector3.UP
var slip := 0.0                    ## lateral slide, for drift dust
var yaw_input := 0.0               ## yaw applied this tick (rad/s), for visual lean
var vertical_vel := 0.0
var air_time := 0.0
var odometer := 0.0
## Wheel travel relative to the authored chassis (positive is compression).
var front_suspension := 0.0
var rear_suspension := 0.0
var suspension_load := 0.0
var _planar_velocity := Vector3.ZERO
var _contact_force := 0.0

var steer := 0.0                   ## smoothed steer input (-1..1)
var throttle := 0.0
var brake := 0.0
var handbrake := false

var intent: Controls.Intent = Controls.Intent.new()
var mods := Mods.new()
var terrain: Terrain

## Set by the owner before step() for one tick of external help — the Truck's winch cable.
var extra_velocity := Vector3.ZERO
## While true, a wall hit pushes the body up instead of scrubbing speed (winching up a face).
var climbing := false
## Floor under this tick's vertical velocity, so a high winch anchor can lift the body.
var min_vertical := -INF

var _body: CharacterBody3D
var _def: VehicleDefinition
var _rays: Array[RayCast3D] = []
var _front_rays: Array[RayCast3D] = []
var _rear_rays: Array[RayCast3D] = []
var _rev_hold := 0.0
var _brake_repressed := true       ## reverse needs a fresh brake press once the vehicle has stopped
var _was_grounded := true
var _last_vertical := 0.0


func _init(body: CharacterBody3D, definition: VehicleDefinition) -> void:
	_body = body
	_def = definition
	mods.top_speed = definition.max_speed
	mods.motor_accel = definition.accel
	mods.reverse_limit = definition.reverse_speed


## Wheel contact rays, in body space. Anything with z < 0 counts as a front wheel for pitch.
func add_wheel_rays(offsets: Array, length: float = 2.4, mask: int = 1) -> void:
	for o in offsets:
		var ray := RayCast3D.new()
		ray.position = o
		ray.target_position = Vector3(0, -length, 0)
		ray.collision_mask = mask
		_body.add_child(ray)
		_rays.append(ray)
		if o.z < 0.0: _front_rays.append(ray)
		else: _rear_rays.append(ray)


## Tests step physics by hand; the rays need telling that the body moved.
func force_wheel_update() -> void:
	for r in _rays: r.force_raycast_update()


func flat_forward() -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw)).normalized()


func place(pos: Vector3, forward: Vector3) -> void:
	_body.global_position = pos + Vector3(0, 0.08, 0)
	yaw = atan2(-forward.x, -forward.z)
	_body.rotation = Vector3(0, yaw, 0)
	speed = 0.0
	vertical_vel = 0.0
	_body.velocity = Vector3.ZERO
	grounded = true
	steer = 0.0; throttle = 0.0; brake = 0.0; pitch = 0.0
	ground_normal = Vector3.UP
	_rev_hold = 0.0
	_brake_repressed = true
	intent = Controls.Intent.new()
	extra_velocity = Vector3.ZERO
	min_vertical = -INF
	climbing = false
	slip = 0.0
	yaw_input = 0.0
	air_time = 0.0
	_last_vertical = 0.0
	_was_grounded = true
	_planar_velocity = Vector3.ZERO
	front_suspension = 0.0
	rear_suspension = 0.0
	suspension_load = 0.0
	_contact_force = 0.0


## Put the vehicle back on the nearest road point. `away_from_sea` faces it inland, which is what
## you want after a swim; otherwise it keeps whichever way along the road it was already going.
func recover_to_road(away_from_sea: bool = false) -> void:
	if terrain == null: return
	var road := terrain.nearest_road(_body.global_position)
	var p: Vector3 = road.point
	var t: Vector3 = road.tangent
	if away_from_sea:
		if t.dot(-Vector3(p.x, 0, p.z).normalized()) < 0.0: t = -t
	elif t.dot(flat_forward()) < 0.0:
		t = -t
	# the road sample's own height: on a bridge deck the heightfield underneath is the water
	place(Vector3(p.x, maxf(p.y, terrain.height_at(p.x, p.z)), p.z), t)


## While parked the vehicle is not driven: it just sits there under gravity.
func idle(delta: float) -> void:
	if _def.suspension_enabled:
		_planar_velocity = Vector3.ZERO
		_move_suspended(delta, flat_forward(), Tick.new())
		refresh_wheel_travel()
		return
	_body.velocity = Vector3(0, _body.velocity.y - _def.gravity * delta, 0) if not _body.is_on_floor() else Vector3(0, -1.0, 0)
	_body.move_and_slide()
	grounded = _body.is_on_floor()


func read_intent(delta: float) -> void:
	var pedal := clampf(intent.throttle, 0.0, 1.0)
	var pedal_rate := _def.throttle_response if pedal > throttle else _def.throttle_release
	throttle = move_toward(throttle, pedal, delta * pedal_rate)
	brake = clampf(intent.brake, 0.0, 1.0)
	handbrake = intent.handbrake
	var wanted := clampf(intent.steer, -1.0, 1.0)
	wanted = lerpf(wanted, wanted * wanted * wanted, _def.steering_precision)
	var speed_fraction := clampf(absf(speed) / maxf(mods.top_speed, 0.1), 0.0, 1.0)
	var rate: float = (_def.steer_smooth_hold if absf(wanted) > 0.05 else _def.steer_smooth_free) * lerpf(0.82, 1.0, mods.handling)
	if absf(wanted) > 0.05:
		rate *= lerpf(1.0, _def.cruise_steer_response, speed_fraction)
	steer = move_toward(steer, wanted, rate * delta)


## One physics tick of ground driving.
func step(delta: float) -> Tick:
	var tick := Tick.new()
	var sf := clampf(absf(speed) / maxf(mods.top_speed, 0.1), 0.0, 1.0)

	# --- Longitudinal
	if grounded:
		# The forward pedal brakes reverse travel before it drives forward.
		if throttle > 0.0 and speed < -0.1:
			speed = move_toward(speed, 0.0, throttle * _def.brake_decel * mods.brake_scale * delta)
		if throttle > 0.0 and speed >= -0.1 and speed < mods.soft_limit:
			# torque curve: strong at low speed, tapering toward the top
			speed += throttle * mods.motor_accel * (1.15 - 0.55 * sf) * delta
		if brake > 0.0:
			if speed > 0.2:
				speed = maxf(speed - brake * _def.brake_decel * mods.brake_scale * delta, 0.0)
				_rev_hold = 0.0
			else:
				# reverse only after the brake has been held for a beat at standstill, so braking
				# into a delivery ring never flips into reverse by accident
				_rev_hold += delta
				if _rev_hold > _def.reverse_delay and _brake_repressed and throttle < 0.05:
					speed -= brake * mods.motor_accel * _def.reverse_accel_scale * delta
					speed = maxf(speed, -mods.reverse_limit)
		else:
			_rev_hold = 0.0
			_brake_repressed = true          # brake released: the next press can reverse
		if speed > 0.5:
			_brake_repressed = false         # a brake-to-stop never rolls straight into reverse
		if handbrake:
			speed = move_toward(speed, 0.0, _def.handbrake_decel * delta)
		# drag, which also handles engine braking while coasting
		var d := _def.drag + _def.drag_quad * absf(speed)
		if throttle < 0.05 and brake < 0.05:
			d += _def.coast_drag
		speed = move_toward(speed, 0.0, d * delta)
		# the surface normal leans away from the uphill direction, so dot < 0 when climbing
		speed += ground_normal.dot(flat_forward()) * _def.slope_gain * delta
		# holding the brake (or handbrake) at standstill stops the vehicle rolling on a slope,
		# but never while reverse is engaging
		if (brake > 0.0 and _rev_hold <= _def.reverse_delay) or handbrake:
			if absf(speed) < 0.6 and throttle < 0.05:
				speed = 0.0
	# a spent tank does not snap velocity to zero; it rolls down to the push pace
	if absf(speed) > mods.soft_limit * 1.03:
		speed = move_toward(speed, signf(speed) * mods.soft_limit, delta * 3.0)
	speed = clampf(speed, -mods.reverse_limit, mods.top_speed * _def.overspeed)

	# --- Steering
	var sr: float = lerpf(_def.steer_rate_low, _def.steer_rate_high, sf) * mods.handling
	var yaw_in := steer * sr * clampf(absf(speed) / _def.yaw_speed_ref, 0.0, 1.0)
	if speed < 0.0: yaw_in = -yaw_in
	if handbrake and speed > 4.0: yaw_in *= _def.handbrake_yaw_gain
	if not grounded: yaw_in *= _def.air_yaw_scale
	yaw_input = yaw_in
	yaw -= yaw_in * delta
	# lateral slip during hard turns at speed -> drift dust and a slight speed scrub
	slip = clampf(absf(steer) * sf * (_def.drift_handbrake_gain if handbrake else _def.drift_gain), 0.0, 1.0)
	if grounded and slip > 0.5:
		speed -= (slip - 0.5) * _def.drift_scrub * delta

	# --- Vertical and ground contact
	var fwd := flat_forward()
	if _def.suspension_enabled:
		_move_suspended(delta, fwd, tick)
	else:
		if grounded: vertical_vel = 0.0
		else: vertical_vel -= _def.gravity * delta
		var vel := fwd * speed
		if grounded:
			# hug the slope so we don't launch off every bump
			vel = (fwd - ground_normal * ground_normal.dot(fwd)).normalized() * speed
			vel.y -= _def.ground_snap
		else:
			vel.y = vertical_vel
		vel += extra_velocity
		if min_vertical > -INF: vel.y = maxf(vel.y, min_vertical)
		_body.velocity = vel
		_body.move_and_slide()

		_was_grounded = grounded
		grounded = _body.is_on_floor()
		if _def.ray_ground_assist and not grounded and _body.velocity.y <= 0.0:
			var gh := wheel_ground_height()
			if not is_nan(gh) and _body.global_position.y - gh < 0.25:
				grounded = true
		if grounded:
			if not _was_grounded:
				var impact := absf(_last_vertical)
				tick.landed_impact = impact
				if impact > _def.hard_landing_impact:
					speed *= _def.hard_landing_scale
			air_time = 0.0
			vertical_vel = 0.0
		else:
			air_time += delta
			_last_vertical = _body.velocity.y
			vertical_vel = _body.velocity.y
	# --- Wall and obstacle hits
	for i in range(_body.get_slide_collision_count()):
		var n := _body.get_slide_collision(i).get_normal()
		if n.y >= 0.5: continue
		var head_on := -n.dot(fwd * (-1.0 if speed < 0.0 else 1.0))
		if climbing:
			vertical_vel = maxf(vertical_vel, 3.0)
		elif head_on > 0.4 and absf(speed) > _def.scrub_min_speed:
			var impact_speed := absf(speed)
			speed *= clampf(1.0 - head_on * _def.scrub_factor, 0.05, 1.0)
			if head_on > 0.8 and impact_speed > _def.crash_min_speed:
				tick.crashed = true
		elif head_on > 0.0:
			speed *= _def.graze_scrub

	# --- Ground normal and pitch from the wheel rays
	_settle_attitude(delta)
	_body.rotation = Vector3(0, yaw, 0)
	_body.rotate_object_local(Vector3.RIGHT, pitch)
	if _def.suspension_enabled: refresh_wheel_travel()

	odometer += absf(speed) * delta
	if terrain != null and terrain.vehicle_submerged(_body.global_position):
		tick.in_sea = true         # the sea, the mountain lake or a river too deep to ford

	extra_velocity = Vector3.ZERO
	min_vertical = -INF
	return tick


## Average wheel-ray contact height, or NAN when no wheel is touching anything.
func wheel_ground_height() -> float:
	var total := 0.0
	var n := 0
	for r in _rays:
		if r.is_colliding():
			total += r.get_collision_point().y
			n += 1
	return total / float(n) if n > 0 else NAN


func _settle_attitude(delta: float) -> void:
	var normals := Vector3.ZERO
	var front := 0.0; var front_n := 0
	var rear := 0.0; var rear_n := 0
	for r in _front_rays:
		if r.is_colliding():
			normals += r.get_collision_normal(); front += r.get_collision_point().y; front_n += 1
	for r in _rear_rays:
		if r.is_colliding():
			normals += r.get_collision_normal(); rear += r.get_collision_point().y; rear_n += 1
	var have_both := front_n > 0 and rear_n > 0
	# A relaxing vehicle (the bike) falls back to level whenever it loses wheel contact; a heavy
	# one (the truck) holds the last attitude it measured.
	var n_target := Vector3.UP if _def.attitude_relaxes else ground_normal
	var pitch_target := 0.0 if _def.attitude_relaxes else pitch
	if _def.suspension_enabled and not grounded: have_both = false
	if have_both:
		pitch_target = atan2(front / float(front_n) - rear / float(rear_n), _def.wheelbase)
	if normals.length_squared() > 0.01 and (have_both or not _def.attitude_relaxes):
		n_target = normals.normalized()
	if not have_both and not grounded:
		pitch_target = clampf(vertical_vel * _def.air_pitch_gain, _def.air_pitch_min, _def.air_pitch_max)
	ground_normal = ground_normal.lerp(n_target, clampf(_def.normal_ease * delta, 0.0, 1.0)).normalized()
	pitch = lerpf(pitch, pitch_target, clampf(_def.pitch_ease * delta, 0.0, 1.0))


## Unilateral spring support: wheels can push up, never pull the bike down.
## Damping is relative to the terrain's slope velocity. At a crest that support
## becomes zero and existing vertical/horizontal momentum continues ballistically.
func _move_suspended(delta: float, fwd: Vector3, tick: Tick) -> void:
	force_wheel_update()
	var force := 0.0
	var front_offset := 0.0
	var rear_offset := 0.0
	var fronts := 0
	var rears := 0
	for ray in _rays:
		var offset := -_def.suspension_travel * .5
		if ray.is_colliding():
			var normal := ray.get_collision_normal()
			var hit := ray.get_collision_point()
			if normal.y > cos(_body.floor_max_angle):
				var dx := _body.global_position.x - hit.x
				var dz := _body.global_position.z - hit.z
				var surface_y := hit.y - (normal.x * dx + normal.z * dz) / normal.y
				var clearance := _body.global_position.y - surface_y
				var wheel_zero := _body.to_global(Vector3(ray.position.x, 0, ray.position.z))
				offset = clampf((hit - wheel_zero).dot(_body.global_basis.y), -_def.suspension_travel, _def.suspension_travel)
				if clearance < _def.suspension_rest_height + _def.suspension_travel:
					var surface_velocity := -(normal.x * fwd.x + normal.z * fwd.z) * speed / normal.y
					var spring := (_def.suspension_rest_height - clearance) * _def.suspension_spring
					var damper := (surface_velocity - vertical_vel) * _def.suspension_damping
					force += clampf(_def.gravity + spring + damper, 0, _def.suspension_max_force)
		if ray.position.z < 0:
			front_offset += offset
			fronts += 1
		else:
			rear_offset += offset
			rears += 1
	_contact_force = force / maxf(_rays.size(), 1)
	front_suspension = front_offset / maxf(fronts, 1)
	rear_suspension = rear_offset / maxf(rears, 1)
	suspension_load = _contact_force / _def.gravity
	var supported := _contact_force > _def.gravity * .08
	var was_grounded := grounded
	if supported:
		var wanted := fwd * speed
		var grip := _def.tire_slide_grip if handbrake else _def.tire_grip
		# Acceleration is already in speed; this limits lateral changes only.
		var lateral := _planar_velocity - fwd * _planar_velocity.dot(fwd)
		_planar_velocity = wanted + lateral.move_toward(Vector3.ZERO, grip * delta)
	elif was_grounded:
		# Preserve externally assigned speed on the first unsupported tick.
		if _planar_velocity.length_squared() < .01: _planar_velocity = fwd * speed
	vertical_vel += (_contact_force - _def.gravity) * delta
	var before_contact := vertical_vel
	_body.velocity = _planar_velocity + Vector3.UP * vertical_vel + extra_velocity
	if min_vertical > -INF: _body.velocity.y = maxf(_body.velocity.y, min_vertical)
	_body.move_and_slide()
	grounded = supported or _body.is_on_floor()
	if grounded:
		if not was_grounded and air_time > .06:
			var impact := maxf(0, -_last_vertical)
			tick.landed_impact = impact
			if impact > _def.hard_landing_impact: speed *= _def.hard_landing_scale
		air_time = 0.0
	else:
		air_time += delta
	# A hull impact can stop a bottomed-out spring; ordinary airborne travel keeps
	# the integrator's velocity rather than resetting it whenever a ray sees ground.
	vertical_vel = _body.get_real_velocity().y if _body.is_on_floor() else _body.velocity.y
	_last_vertical = before_contact
	_planar_velocity = Vector3(_body.velocity.x, 0, _body.velocity.z)


## Transfer momentum when returning from the separate wing-flight solver.
func capture_velocity(value: Vector3) -> void:
	_planar_velocity = Vector3(value.x, 0, value.z)
	vertical_vel = value.y
	_last_vertical = value.y


## Unsprung wheels follow the contact plane immediately, after chassis motion
## and pitch have changed. Smoothing an old ray sample lets tires enter the road
## on the first landing frame even when the spring solver is correct.
func refresh_wheel_travel() -> void:
	force_wheel_update()
	front_suspension = _travel_for(_front_rays, true)
	rear_suspension = _travel_for(_rear_rays, false)


func _travel_for(rays: Array[RayCast3D], front: bool) -> float:
	if rays.is_empty(): return 0.0
	var sum := 0.0
	for ray in rays:
		var travel := -_def.suspension_travel
		if ray.is_colliding():
			var normal := ray.get_collision_normal()
			if normal.y > cos(_body.floor_max_angle):
				# Front telescopes along its authored rake, rear uses vertical travel
				# as the input to its swingarm arc in the renderer.
				var axis := _body.global_basis * Vector3(0, 1, .24 / .73 if front else 0.0)
				var center := _body.to_global(Vector3(ray.position.x, _def.wheel_radius, ray.position.z))
				var projection := normal.dot(axis)
				if projection > .1:
					travel = clampf((_def.wheel_radius - normal.dot(center - ray.get_collision_point())) / projection,
						-_def.suspension_travel, _def.suspension_travel)
		sum += travel
	return sum / rays.size()
