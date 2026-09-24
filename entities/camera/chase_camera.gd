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
##   kick(pitch, yaw)          recoil: the view jumps up (rad) and recovers on its own

enum Framing { BIKE, FOOT, SWIM, PLANE, TRUCK }

## One row per Framing. Everything the chase update needs is a column here — the eases, the
## speed gains and the airborne lift used to be `if framing == BIKE` branches inside
## _chase_update, which meant TRUCK silently inherited whatever the bike was *not*.
##
##   distance/height/look_height/look_ahead/fov  where the camera sits and what it looks at
##   orbit          the view direction IS (yaw, pitch) — on foot and swimming
##   yaw_base/gain  how fast the camera swings to the target's heading (+ speed factor)
##   dist_gain      extra pull-back at top speed          fov_gain   extra FOV at top speed
##   pos_ease       how fast the body of the camera tracks its desired point
##   height_ease    vertical tracking, when it should be softer than pos_ease (0 = same)
##   look_ease      how fast the look point tracks       fov_ease   how fast FOV settles
##   air_lift       extra height while flying
const FRAMINGS := {
	Framing.BIKE:  {"distance": 4.5, "height": 1.55, "look_height": 1.05, "look_ahead": 2.7, "fov": 58.0, "orbit": false,
		"yaw_base": 0.44, "yaw_gain": 0.23, "dist_gain": 0.7, "fov_gain": 4.5,
		"pos_ease": 8.0, "height_ease": 4.2, "look_ease": 7.0, "fov_ease": 1.8, "air_lift": 0.0},
	Framing.FOOT:  {"distance": 6.2, "height": 1.7, "look_height": 1.65, "look_ahead": 1.2, "fov": 64.0, "orbit": true,
		"yaw_base": 0.55, "yaw_gain": 0.6, "dist_gain": 1.1, "fov_gain": 7.0,
		"pos_ease": 6.0, "height_ease": 0.0, "look_ease": 11.2, "fov_ease": 3.0, "air_lift": 0.0},
	Framing.SWIM:  {"distance": 3.6, "height": 1.9, "look_height": 0.5,  "look_ahead": 1.0, "fov": 58.0, "orbit": true,
		"yaw_base": 0.55, "yaw_gain": 0.6, "dist_gain": 1.1, "fov_gain": 7.0,
		"pos_ease": 6.0, "height_ease": 0.0, "look_ease": 11.2, "fov_ease": 3.0, "air_lift": 0.0},
	Framing.PLANE: {"distance": 7.5, "height": 2.6, "look_height": 1.1,  "look_ahead": 3.0, "fov": 64.0, "orbit": false,
		"yaw_base": 0.55, "yaw_gain": 0.6, "dist_gain": 1.1, "fov_gain": 7.0,
		"pos_ease": 6.0, "height_ease": 0.0, "look_ease": 11.2, "fov_ease": 3.0, "air_lift": 0.6},
	Framing.TRUCK: {"distance": 6.4, "height": 2.8, "look_height": 1.35, "look_ahead": 2.8, "fov": 60.0, "orbit": false,
		"yaw_base": 0.5, "yaw_gain": 0.35, "dist_gain": 0.9, "fov_gain": 5.5,
		"pos_ease": 7.0, "height_ease": 5.0, "look_ease": 8.5, "fov_ease": 2.2, "air_lift": 0.0},
}
## Looking back is a deliberate swing, not the framing's own easing.
const LOOK_BACK_YAW := {"base": 0.55, "gain": 0.6}
const PITCH_MIN := -0.35
const PITCH_MAX := 1.1

@export var pos_smooth := 6.0
@export var rot_smooth := 8.0
@export var orbit_recenter := false
@export var collision_radius := .22
@export var orbit_recovery_speed := 9.0
## Red Sea Baron orbit framing/zoom, adapted to this camera's +down pitch.
@export var orbit_distance := 6.2

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
var _orbit_pivot := Vector3.ZERO
var _boom_distance := 3.4
var _collision_sphere := SphereShape3D.new()
var _recoil := Vector2.ZERO          # (yaw, pitch-up) offset in radians, decays back to zero
## Aiming down the sights: a tight over-the-shoulder boom and a narrower view.
@export var aim_distance := 1.7
@export var aim_side := 0.58
@export var aim_up := 0.16
@export var aim_fov_drop := 22.0


func _ready() -> void:
	process_physics_priority = 40
	near = 0.10
	far = 30000.0
	current = true
	fov = _f.fov


# ---------------------------------------------------------------- interface
func follow(p_target: Node3D, p_framing: int) -> void:
	var retarget := p_target != target
	if retarget and is_instance_valid(target) and target.has_method("set_camera_distance"):
		target.set_camera_distance(INF)
	target = p_target
	framing = p_framing
	_f = FRAMINGS[p_framing]
	var was_orbit := _orbit
	_orbit = _f.orbit
	if not _orbit:
		_orbit_pitch = 0.0
	if _orbit and not was_orbit: _orbit_pitch = .27
	if retarget and not _initialized:
		snap_to_target()
	elif _orbit and not was_orbit:
		_yaw = target.rotation.y
		_orbit_pitch = .27
		_orbit_pivot = target.global_position + Vector3.UP * float(_f.look_height)
		_boom_distance = float(_f.distance)


func look(delta: Vector2) -> void:
	if not _orbit or delta == Vector2.ZERO: return
	_yaw -= delta.x
	_orbit_pitch = clampf(_orbit_pitch + delta.y, PITCH_MIN, PITCH_MAX)
	_last_look_t = Time.get_ticks_msec() * 0.001
	if _orbit: _orient_orbit()


## Positive notches zoom outward, as in the source OrbitCamera wheel handler.
func zoom(notches: float) -> void:
	if framing != Framing.FOOT: return
	orbit_distance = clampf(orbit_distance + notches * .5, 3.0, 9.0)


func control_yaw() -> float:
	return _yaw if _orbit else global_rotation.y


func _orbit_direction() -> Vector3:
	var y := _yaw - _recoil.x
	var p := _orbit_pitch - _recoil.y
	return Vector3(-sin(y) * cos(p), -sin(p), -cos(y) * cos(p))


func _orient_orbit() -> void:
	# Keep the crosshair ray current even when a look and fire share a tick.
	look_at(global_position + _orbit_direction(), Vector3.UP)


func set_aiming(v: bool) -> void:
	_aiming = v


func set_look_back(v: bool) -> void:
	_look_back = v


func pitch() -> float:
	return _orbit_pitch - _recoil.y


func kick(pitch_up: float, yaw: float = 0.0) -> void:
	_recoil += Vector2(yaw, pitch_up)
	_recoil.y = minf(_recoil.y, 0.2)
	if _orbit: _orient_orbit()


func is_aiming() -> bool:
	return _aiming


func set_look(yaw: float, p_pitch: float) -> void:
	_yaw = yaw
	_orbit_pitch = clampf(p_pitch, PITCH_MIN, PITCH_MAX)
	_last_look_t = Time.get_ticks_msec() * 0.001
	if _orbit: _orient_orbit()


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
	_orbit_pivot = target.global_position + Vector3.UP * float(_f.look_height)
	_boom_distance = float(_f.distance)
	if _orbit:
		_orbit_update(0.0)
	reset_physics_interpolation()


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


# ---------------------------------------------------------------- implementation
func _physics_process(delta: float) -> void:
	# recoil recovers: fast at first, then settles back onto the original aim
	_recoil = _recoil.lerp(Vector2.ZERO, 1.0 - exp(-9.0 * delta))
	if not target: return
	if not _initialized:
		snap_to_target()
	if _orbit:
		_orbit_update(delta)
	else:
		_chase_update(delta)


## The camera asks its target two questions and nothing else — no `as Bike`, no duck-typing on
## whether speed is a field or a method.
func _target_speed() -> float:
	return target.camera_speed() if target and target.has_method("camera_speed") else 0.0


func _target_top_speed() -> float:
	return target.camera_top_speed() if target and target.has_method("camera_top_speed") else 27.0


func _chase_update(delta: float) -> void:
	var sf := clampf(absf(_target_speed()) / maxf(_target_top_speed(), 0.1), 0.0, 1.0)
	var target_yaw: float = target.rotation.y + (PI if _look_back else 0.0)
	var yaw_ease: Dictionary = LOOK_BACK_YAW if _look_back else {"base": _f.yaw_base, "gain": _f.yaw_gain}
	var yaw_rate: float = rot_smooth * (float(yaw_ease.base) + sf * float(yaw_ease.gain))
	_yaw = lerp_angle(_yaw, target_yaw, 1.0 - exp(-yaw_rate * delta))
	var f := Vector3(-sin(_yaw), 0, -cos(_yaw))
	var dist: float = _f.distance + sf * float(_f.dist_gain)
	var h: float = _f.height + sf * 0.25 + float(_f.air_lift)
	var desired := target.global_position - f * dist + Vector3(0, h, 0)
	if terrain:
		desired.y = maxf(desired.y, terrain.height_at(desired.x, desired.z) + 0.9)
	var from := target.global_position + Vector3(0, _f.look_height, 0)
	var space := get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, desired, 1))
	if hit:
		desired = hit.position + (from - desired).normalized() * 0.35
	var filtered := _cur_pos.lerp(desired, 1.0 - exp(-float(_f.pos_ease) * delta))
	if float(_f.height_ease) > 0.0:
		# Soften wheel-height chatter independently of horizontal tracking.
		filtered.y = lerpf(_cur_pos.y, desired.y, 1.0 - exp(-float(_f.height_ease) * delta))
	# A new wall must retract the camera immediately. Filtering only the desired endpoint can
	# otherwise leave the actual camera behind a wall.
	var safety_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, filtered, 1))
	if safety_hit: filtered = safety_hit.position + (from - filtered).normalized() * .35
	_cur_pos = filtered
	var look_pt: Vector3 = target.global_position + f * _f.look_ahead + Vector3(0, _f.look_height, 0)
	_cur_look = _cur_look.lerp(look_pt, 1.0 - exp(-float(_f.look_ease) * delta))
	global_position = _shaken(_cur_pos, delta)
	look_at(_cur_look, Vector3.UP)
	fov = lerpf(fov, _f.fov + sf * float(_f.fov_gain), 1.0 - exp(-float(_f.fov_ease) * delta))


func _camera_clearance(from: Vector3, to: Vector3) -> Vector3:
	var travel := to - from
	if travel.length_squared() < .000001: return from
	_collision_sphere.radius = collision_radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _collision_sphere
	query.transform = Transform3D(Basis.IDENTITY, from)
	query.motion = travel
	query.margin = .025
	query.collision_mask = 1 | 2 | 16
	if target is CollisionObject3D: query.exclude = [target.get_rid()]
	var space := get_world_3d().direct_space_state
	# Sweeps deliberately ignore shapes already overlapping their starting
	# sphere. Resolve those contacts first (for example an aim shoulder beside
	# a wall), including parallel walls that a center ray cannot detect.
	var start := from
	query.motion = Vector3.ZERO
	for attempt in range(4):
		query.transform.origin = start
		var overlap := space.get_rest_info(query)
		if overlap.is_empty(): break
		start = overlap.point + overlap.normal * (collision_radius + query.margin + .01)
	query.transform.origin = start
	travel = to - start
	if travel.length_squared() < .000001: return start
	query.motion = travel
	var fractions := space.cast_motion(query)
	var fraction := fractions[0] if fractions.size() > 0 else 1.0
	# A center ray also catches thin surfaces if the sweep starts overlapping.
	var ray := PhysicsRayQueryParameters3D.create(start, to, query.collision_mask)
	ray.exclude = query.exclude
	var hit := space.intersect_ray(ray)
	if hit:
		fraction = minf(fraction, maxf(0.0, start.distance_to(hit.position) - collision_radius) / travel.length())
	return start + travel * clampf(fraction, 0.0, 1.0)


func _orbit_update(delta: float) -> void:
	var speed := _target_speed()
	var idle := Time.get_ticks_msec() * 0.001 - _last_look_t
	# Manual orbit stays where the player put it; optional recenter is explicit.
	if orbit_recenter and idle > 3.0 and absf(speed) > 0.5 and not _aiming:
		_yaw = lerp_angle(_yaw, target.rotation.y, 1.0 - exp(-1.2 * delta))
	var dir := _orbit_direction()
	var side := Vector3(cos(_yaw), 0, -sin(_yaw))
	var anchor := target.global_position + Vector3(0, _f.look_height, 0)
	if _orbit_pivot.distance_squared_to(anchor) > 36.0 or delta <= 0.0:
		_orbit_pivot = anchor
	else:
		# Source orbit follows at exponential response 18; keep the existing
		# overlap-aware sweep to prevent smoothing the pivot through cover.
		_orbit_pivot = _camera_clearance(anchor, _orbit_pivot.lerp(anchor, 1.0 - exp(-18.0 * delta)))
	var pivot := _orbit_pivot
	var distance: float = orbit_distance if framing == Framing.FOOT else float(_f.distance)
	if _aiming:
		distance = aim_distance
		pivot = _camera_clearance(pivot, pivot + side * aim_side + Vector3.UP * aim_up)
	var desired := pivot - dir * distance
	if terrain:
		desired.y = maxf(desired.y, terrain.height_at(desired.x, desired.z) + collision_radius + .08)
	var safe := _camera_clearance(pivot, desired)
	var allowed := pivot.distance_to(safe)
	# Retract immediately, recover softly. A smoothed world-space endpoint can
	# remain behind a newly encountered wall or cut through a corner on orbit.
	_boom_distance = minf(_boom_distance, allowed)
	_boom_distance = lerpf(_boom_distance, allowed, 1.0 - exp(-orbit_recovery_speed * delta))
	if delta <= 0.0: _boom_distance = allowed
	_cur_pos = pivot + (safe - pivot).normalized() * _boom_distance
	global_position = _camera_clearance(pivot, _shaken(_cur_pos, delta))
	if target.has_method("set_camera_distance"):
		target.set_camera_distance(global_position.distance_to(anchor))
	_orient_orbit()
	_cur_look = global_position + dir * 5.0
	fov = lerpf(fov, (_f.fov - aim_fov_drop) if _aiming else _f.fov, 1.0 - exp(-10.0 * delta))


func _shaken(pos: Vector3, delta: float) -> Vector3:
	if _shake > 0.001:
		pos += Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), 0) * _shake * 0.08
		_shake = move_toward(_shake, 0.0, delta * 3.0)
	return pos
