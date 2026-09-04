class_name ChaseCamera
extends Camera3D
## Third-person camera. Two behaviours behind one small interface:
##   * chase (bike / plane): sits low and close behind the target, eases toward its heading,
##     pulls back and widens at speed, never clips through terrain or props;
##   * orbit (on foot / swimming): the view direction IS (yaw, pitch), so whatever the crosshair
##     covers is exactly what `view_ray()` hits — aiming is exact by construction.
##
## Interface:
##   follow(target, framing)   what to look at and how (Framing table below)
##   look(delta)               free-look input this tick (radians: x yaw +right, y pitch +down)
##   set_aiming(bool)          over-the-shoulder aim framing while held
##   set_look_back(bool)       chase: swing round to look behind
##   view_ray() -> {origin, direction}   the ray through the crosshair
##   pitch() -> float          current orbit pitch (for the aim pose)
##   set_look(yaw, pitch)      set the orbit directly (aim assists, tests)
##   snap_to_target()          cut instead of blend (spawn, teleports)
##   shake(amount)

enum Framing { BIKE, FOOT, SWIM, PLANE }

## distance, height, look_height, look_ahead, fov, orbit
const FRAMINGS := {
	Framing.BIKE:  {"distance": 3.9, "height": 1.3, "look_height": 0.95, "look_ahead": 2.0, "fov": 56.0, "orbit": false},
	Framing.FOOT:  {"distance": 3.2, "height": 1.7, "look_height": 1.25, "look_ahead": 1.2, "fov": 58.0, "orbit": true},
	Framing.SWIM:  {"distance": 3.6, "height": 1.9, "look_height": 0.5,  "look_ahead": 1.0, "fov": 58.0, "orbit": true},
	Framing.PLANE: {"distance": 7.5, "height": 2.6, "look_height": 1.1,  "look_ahead": 3.0, "fov": 64.0, "orbit": false},
}
const PITCH_MIN := -35.0 * PI / 180.0
const PITCH_MAX := 55.0 * PI / 180.0

@export var pos_smooth := 6.0
@export var rot_smooth := 8.0

var target: Node3D
var framing: int = Framing.BIKE
var terrain: Terrain
var _f: Dictionary = FRAMINGS[Framing.BIKE]
var _orbit := false
var _aiming := false
var _look_back := false
var _orbit_pitch := 0.0
var _yaw := 0.0
var _cur_pos: Vector3
var _cur_look: Vector3
var _initialized := false
var _shake := 0.0
var _last_look_t := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	near = 0.15
	far = 1600.0
	current = true
	fov = _f.fov


# ---------------------------------------------------------------- interface
func follow(p_target: Node3D, p_framing: int) -> void:
	var retarget := p_target != target
	target = p_target
	framing = p_framing
	_f = FRAMINGS[p_framing]
	var was_orbit := _orbit
	_orbit = _f.orbit
	if not _orbit:
		_orbit_pitch = 0.0
	if retarget and not _initialized:
		snap_to_target()
	elif _orbit and not was_orbit:
		_yaw = target.rotation.y


func look(delta: Vector2) -> void:
	if not _orbit or delta == Vector2.ZERO: return
	_yaw -= delta.x
	_orbit_pitch = clampf(_orbit_pitch + delta.y, PITCH_MIN, PITCH_MAX)
	_last_look_t = Time.get_ticks_msec() * 0.001


func set_aiming(v: bool) -> void:
	_aiming = v


func set_look_back(v: bool) -> void:
	_look_back = v


func pitch() -> float:
	return _orbit_pitch


func set_look(yaw: float, p_pitch: float) -> void:
	_yaw = yaw
	_orbit_pitch = clampf(p_pitch, PITCH_MIN, PITCH_MAX)
	_last_look_t = Time.get_ticks_msec() * 0.001


## The ray through the centre of the screen.
func view_ray() -> Dictionary:
	return {"origin": global_position, "direction": -global_transform.basis.z}


func snap_to_target() -> void:
	if not target: return
	_yaw = target.rotation.y
	var f := Vector3(-sin(_yaw), 0, -cos(_yaw))
	_cur_pos = target.global_position - f * _f.distance + Vector3(0, _f.height, 0)
	_cur_look = target.global_position + f * _f.look_ahead + Vector3(0, _f.look_height, 0)
	global_position = _cur_pos
	look_at(_cur_look, Vector3.UP)
	_initialized = true


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


# ---------------------------------------------------------------- implementation
func _physics_process(delta: float) -> void:
	if not target: return
	if not _initialized:
		snap_to_target()
	if _orbit:
		_orbit_update(delta)
	else:
		_chase_update(delta)


func _target_speed() -> float:
	if target is Bike: return target.speed
	if target.has_method("speed"): return target.speed()
	return 0.0


func _chase_update(delta: float) -> void:
	var bike := target as Bike
	var speed := _target_speed()
	var sf := clampf(absf(speed) / (40.0 if (bike and bike.airborne) else 27.0), 0.0, 1.0)
	var target_yaw: float = target.rotation.y + (PI if _look_back else 0.0)
	var yaw_rate := rot_smooth * (0.55 + sf * 0.6)
	_yaw = lerp_angle(_yaw, target_yaw, clampf(yaw_rate * delta, 0.0, 1.0))
	var f := Vector3(-sin(_yaw), 0, -cos(_yaw))
	var dist: float = _f.distance + sf * 1.1
	var h: float = _f.height + sf * 0.25
	var desired := target.global_position - f * dist + Vector3(0, h, 0)
	if bike and bike.airborne:
		desired += Vector3(0, 0.6, 0)
	if terrain:
		desired.y = maxf(desired.y, terrain.height_at(desired.x, desired.z) + 0.9)
	var from := target.global_position + Vector3(0, _f.look_height, 0)
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, desired, 1)
	var hit := space.intersect_ray(q)
	if hit:
		desired = hit.position + (from - desired).normalized() * 0.35
	_cur_pos = _cur_pos.lerp(desired, clampf(pos_smooth * delta, 0.0, 1.0))
	var look_pt: Vector3 = target.global_position + f * _f.look_ahead + Vector3(0, _f.look_height, 0)
	_cur_look = _cur_look.lerp(look_pt, clampf(rot_smooth * 1.4 * delta, 0.0, 1.0))
	global_position = _shaken(_cur_pos, delta)
	look_at(_cur_look, Vector3.UP)
	fov = lerpf(fov, _f.fov + sf * 7.0, clampf(3.0 * delta, 0.0, 1.0))


func _orbit_update(delta: float) -> void:
	var speed := _target_speed()
	# after a few seconds without look input, drift back behind the walking direction
	var idle := Time.get_ticks_msec() * 0.001 - _last_look_t
	if idle > 3.0 and absf(speed) > 0.5 and not _aiming:
		_yaw = lerp_angle(_yaw, target.rotation.y, clampf(1.2 * delta, 0.0, 1.0))
	var f := Vector3(-sin(_yaw), 0, -cos(_yaw))
	var pr := clampf(_orbit_pitch, PITCH_MIN, PITCH_MAX)
	var dir := Vector3(-sin(_yaw) * cos(pr), -sin(pr), -cos(_yaw) * cos(pr))   # + pitch looks down
	var side := Vector3(-f.z, 0, f.x)
	var pivot := target.global_position + Vector3(0, _f.look_height, 0)
	var dist: float = _f.distance
	if _aiming:
		dist = 1.7
		pivot += side * 0.55 + Vector3(0, 0.25, 0)
	var desired := pivot - dir * dist
	if terrain:
		desired.y = maxf(desired.y, terrain.height_at(desired.x, desired.z) + 0.5)
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(pivot, desired, 1 | 2)
	q.exclude = [target.get_rid()] if target is CollisionObject3D else []
	var hit := space.intersect_ray(q)
	if hit:
		desired = hit.position + (pivot - desired).normalized() * 0.3
	_cur_pos = _cur_pos.lerp(desired, clampf((pos_smooth * 2.0 if _aiming else pos_smooth) * delta, 0.0, 1.0))
	var pos := _shaken(_cur_pos, delta)
	global_position = pos
	look_at(pos + dir, Vector3.UP)
	_cur_look = pos + dir * 5.0
	fov = lerpf(fov, (_f.fov - 10.0) if _aiming else _f.fov, clampf(6.0 * delta, 0.0, 1.0))


func _shaken(pos: Vector3, delta: float) -> Vector3:
	if _shake > 0.001:
		pos += Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), 0) * _shake * 0.08
		_shake = move_toward(_shake, 0.0, delta * 3.0)
	return pos
