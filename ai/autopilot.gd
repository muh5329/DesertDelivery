class_name Autopilot
extends Node
## Drives the bike along the road network to the game manager's current target.
## Used by the automated verifier (--autotest) and the screenshot tour (--shots).

var bike: Bike
var gm: DeliverySystem
var terrain: Terrain
var controls: Controls.Scripted
var path: PackedVector3Array = PackedVector3Array()
var path_i := 0
var _last_target := Vector3(INF, INF, INF)
var _stuck_t := 0.0
var _pinned_t := 0.0          # time without real progress; a long pin means wedged -> reset to the road
var _pin_pos := Vector3.ZERO
var _reverse_t := 0.0
var log_enabled := true
var _log_t := 0.0
var _progress_index := -1
var _best_waypoint_distance := INF
var _no_progress_time := 0.0


func setup(p_bike: Bike, p_gm: DeliverySystem, p_terrain: Terrain, p_controls: Controls.Scripted) -> void:
	bike = p_bike; gm = p_gm; terrain = p_terrain; controls = p_controls
	_build_graph()


var navigation := RoadNavigation.new()

func _build_graph() -> void:
	navigation.build(terrain)

func _plan(from: Vector3, to: Vector3) -> void:
	# Reuse the same grade-aware AStar network as island traffic. Disconnected
	# roads must never produce a fictitious straight-line route across the sea.
	path = navigation.path(from, to, 0.0, terrain)
	if not path.is_empty() and path[-1].distance_to(to) > .1:
		path.append(to)
	path_i = 0
	_progress_index=-1; _best_waypoint_distance=INF; _no_progress_time=0


func _physics_process(delta: float) -> void:
	if gm == null or bike == null or controls == null: return
	if gm.stage == DeliverySystem.Stage.DONE:
		controls.intent.throttle = 0.0; controls.intent.brake = 1.0; controls.intent.steer = 0.0
		return
	var target := gm.target_position()
	if target.distance_to(_last_target) > 0.5:
		_last_target = target
		_plan(bike.global_position, target)
	if path.is_empty():
		controls.intent.throttle=0.0; controls.intent.brake=1.0; controls.intent.steer=0.0
		return
	var pos := bike.global_position
	# advance along the path
	while path_i < path.size() - 1 and Vector2(path[path_i].x - pos.x, path[path_i].z - pos.z).length() < 7.0:
		path_i += 1
	var look := path[mini(path_i, path.size() - 1)]
	var to_target := Vector2(target.x - pos.x, target.z - pos.z).length()
	if to_target < 14.0:
		look = target
	var fwd := bike.flat_forward()
	var to := look - pos; to.y = 0.0
	var ang := fwd.signed_angle_to(to.normalized(), Vector3.UP)
	var steer := clampf(-ang * 1.6, -1.0, 1.0)
	var throttle := 1.0
	var brake := 0.0
	var sp := bike.speed
	if absf(ang) > 0.5:
		throttle = 0.35
		if sp > 9.0: brake = 0.6
	elif absf(ang) > 0.25 and sp > 16.0:
		throttle = 0.2
	# arrival: slow down and stop inside the zone
	if to_target < 30.0:
		var want := clampf(to_target * 0.5, 0.0, 12.0)
		if to_target < 4.0: want = 0.0
		if sp > want + 0.5:
			throttle = 0.0; brake = 1.0
		elif sp < want - 1.0:
			throttle = 0.6
		else:
			throttle = 0.0
	# stuck handling
	if absf(sp) < 0.6 and to_target > 6.0 and _reverse_t <= 0.0:
		_stuck_t += delta
	else:
		_stuck_t = 0.0
	if _stuck_t > 2.5:
		_reverse_t = 1.6; _stuck_t = 0.0
	if _reverse_t > 0.0:
		_reverse_t -= delta
		throttle = 0.0; brake = 1.0; steer = -steer
	# wedged against something for a long time (no progress despite trying): use the reset key
	if pos.distance_to(_pin_pos) > 2.0:
		_pin_pos = pos; _pinned_t = 0.0
	elif to_target > 6.0:
		_pinned_t += delta
		if _pinned_t > 12.0:
			_pinned_t = 0.0
			controls.press("reset")
			if log_enabled: print("[autopilot] wedged at %s -> reset to road" % str(pos))
	# Driving circles or bouncing down a bank is motion, but not route progress.
	# Keep the existing recovery available in those cases too.
	var waypoint_distance:=Vector2(look.x-pos.x,look.z-pos.z).length()
	if path_i!=_progress_index or waypoint_distance<_best_waypoint_distance-1.0:
		_progress_index=path_i; _best_waypoint_distance=waypoint_distance; _no_progress_time=0
	else: _no_progress_time+=delta
	if _no_progress_time>18.0 and to_target>6.0:
		controls.press("reset")
		_plan(pos,target)
		if log_enabled: print("[autopilot] no route progress at %s -> reset and replan"%pos)
	controls.intent.throttle = throttle
	controls.intent.brake = brake
	controls.intent.steer = steer
	if log_enabled:
		_log_t += delta
		if _log_t > 3.0:
			_log_t = 0.0
			print("[autopilot] pos=(%.1f, %.1f, %.1f) speed=%.1f m/s target=%s dist=%.1f grounded=%s" % [pos.x, pos.y, pos.z, sp, gm.target_name(), to_target, bike.grounded])
