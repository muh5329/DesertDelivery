class_name PlaningDrive
extends RefCounted
## Afloat: an amphibious vehicle on water too deep to ford. LegendOfJeep planes across its sea
## with buoyancy points, thrust and a torque on a RigidBody; here the same behaviour is kinematic,
## like the GroundDrive it takes over from (ADR 0001: "a boat ... give it its own drive rather
## than growing this one a mode flag").
##
## It drives the GroundDrive's own state — speed, yaw, the smoothed pedals and steer — so
## `vehicle.speed`, the HUD, the camera and the odometer never learn which drive is in charge.
##
## Interface:
##   PlaningDrive.new(body, definition, ground_drive)
##   should_float(pos) -> bool     is the water under `pos` deep enough to lift the hull?
##   step(delta, top_scale) -> bool   one tick afloat; true when the wheels have found the bed
##                                    again (a beach, a slipway, a ford) and the ground drive
##                                    should take back over
##   pitch / roll / bob             the hull's attitude, for the visual
##   water_level                    the surface under the body this tick

var pitch := 0.0
var roll := 0.0
var bob := 0.0
var water_level := 0.0
var wake := 0.0              ## 0..1 bow wave / spray strength

var terrain: Terrain
var _body: CharacterBody3D
var _def: VehicleDefinition
var _g: GroundDrive
var _t := 0.0
var _beach_t := 0.0

## Exit hysteresis (LegendOfJeep: enter once the hull reaches the surface with the wheels off
## the bed, leave only once the wheels have found shallow ground again).
const EXIT_DEPTH := 0.62
const LEAVE_HOLD := 0.12     ## seconds of shallow bed under the front wheels before it drives out


func _init(body: CharacterBody3D, definition: VehicleDefinition, ground: GroundDrive) -> void:
	_body = body
	_def = definition
	_g = ground


## The surface and the bed at a point: {level, depth}. Without a terrain (unit fixtures) there
## is no water anywhere.
func water_at(p: Vector3) -> Dictionary:
	if terrain == null: return {"level": -INF, "depth": 0.0}
	var wl := terrain.water_level_at(p.x, p.z)
	return {"level": wl, "depth": wl - terrain.height_at(p.x, p.z)}


## Deep water under the body, and the body down at (or in) it: time to float.
func should_float(p: Vector3) -> bool:
	var w := water_at(p)
	return w.depth > _def.float_depth and p.y < float(w.level) + 0.25


## One tick afloat. Returns true when the vehicle should drive out.
func step(delta: float, top_scale: float = 1.0, boost := false) -> bool:
	_t += delta
	var fwd := _g.flat_forward()
	var here := water_at(_body.global_position)
	water_level = here.level
	var top := _def.water_max_speed * top_scale * (1.2 if boost else 1.0)
	# --- thrust: the propellers push hardest from rest and fade toward the planing top speed
	var throttle := _g.throttle
	if throttle > 0.0 and _g.speed < top:
		_g.speed += throttle * _def.water_accel * (1.0 - clampf(_g.speed / maxf(top, 0.1), 0.0, 1.0)) * delta
	if _g.brake > 0.0:
		if _g.speed > 0.2:
			_g.speed = maxf(0.0, _g.speed - _g.brake * _def.water_accel * 1.6 * delta)
		else:
			_g.speed = maxf(_g.speed - _g.brake * _def.water_accel * 0.5 * delta, -top * 0.3)
	# water drag: the hull settles off the plane quickly when the throttle is closed
	var drag := 0.25 + 0.035 * absf(_g.speed) + (0.6 if throttle < 0.05 and _g.brake < 0.05 else 0.0)
	_g.speed = move_toward(_g.speed, 0.0, drag * delta)
	if _g.speed > top * 1.05: _g.speed = move_toward(_g.speed, top, delta * 4.0)
	# --- turning: a rudder needs water flowing past it
	var authority := clampf(absf(_g.speed) / 6.0, 0.15, 1.0)
	var yaw_in := _g.steer * _def.water_turn_rate * authority * (-1.0 if _g.speed < -0.1 else 1.0)
	_g.yaw_input = yaw_in
	_g.yaw -= yaw_in * delta
	fwd = _g.flat_forward()
	# --- float: the body origin rides `draught` under the surface, on a slow swell
	bob = sin(_t * 1.7) * 0.05 + sin(_t * 0.9 + 1.3) * 0.04
	var target_y: float = here.level - _def.draught + bob
	var vel := fwd * _g.speed
	vel.y = clampf((target_y - _body.global_position.y) * 5.0, -6.0, 3.5)
	vel += _g.extra_velocity
	_body.velocity = _g.apply_tether(vel, delta)
	_body.move_and_slide()
	# quay walls, moles, boats: a square hit stops the hull, a glancing one slides along
	for i in range(_body.get_slide_collision_count()):
		var n := _body.get_slide_collision(i).get_normal()
		if n.y >= 0.5: continue
		var head_on := -n.dot(fwd * (-1.0 if _g.speed < 0.0 else 1.0))
		if head_on > 0.4: _g.speed *= clampf(1.0 - head_on * 0.7, 0.1, 1.0)
	# --- attitude: the bow lifts onto the plane, the hull leans out of a turn and rocks
	var sf := clampf(absf(_g.speed) / maxf(_def.water_max_speed, 0.1), 0.0, 1.0)
	var pitch_t := 0.06 * sf * (1.0 - sf * 0.4) + sin(_t * 1.3) * 0.015     # + nose up
	var roll_t := clampf(yaw_in * _g.speed * 0.02, -0.12, 0.12) + sin(_t * 1.1 + 0.4) * 0.02
	pitch = lerpf(pitch, pitch_t, clampf(delta * 3.0, 0.0, 1.0))
	roll = lerpf(roll, roll_t, clampf(delta * 3.0, 0.0, 1.0))
	_g.pitch = pitch
	_body.rotation = Vector3(0, _g.yaw, 0)
	_body.rotate_object_local(Vector3.RIGHT, pitch)
	_body.rotate_object_local(Vector3.BACK, roll)
	_g.odometer += absf(_g.speed) * delta
	wake = clampf(absf(_g.speed) / 6.0, 0.0, 1.0)
	_g.extra_velocity = Vector3.ZERO
	_g.min_vertical = -INF
	# --- the bed: shallow under the front wheels for a moment, and the wheels take over
	var probe := _body.global_position + fwd * (_def.wheelbase * 0.5 + 0.3) * (1.0 if _g.speed >= 0.0 else -1.0)
	var ahead := water_at(probe)
	var under := water_at(_body.global_position)
	if float(ahead.depth) < EXIT_DEPTH or float(under.depth) < EXIT_DEPTH - 0.1:
		_beach_t += delta
	else:
		_beach_t = 0.0
	if _beach_t >= LEAVE_HOLD:
		_beach_t = 0.0
		return true
	return false


func reset() -> void:
	pitch = 0.0; roll = 0.0; bob = 0.0; wake = 0.0; _beach_t = 0.0
