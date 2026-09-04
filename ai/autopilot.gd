class_name Autopilot
extends Node
## Drives the bike along the road network to the game manager's current target.
## Used by the automated verifier (--autotest) and the screenshot tour (--shots).

var bike: Bike
var gm: DeliverySystem
var terrain: Terrain
var controls: Controls.Scripted
var nodes: PackedVector3Array = PackedVector3Array()
var adj: Array = []              # Array[PackedInt32Array]
var path: PackedVector3Array = PackedVector3Array()
var path_i := 0
var _last_target := Vector3(INF, INF, INF)
var _stuck_t := 0.0
var _pinned_t := 0.0          # time without real progress; a long pin means wedged -> reset to the road
var _pin_pos := Vector3.ZERO
var _reverse_t := 0.0
var log_enabled := true
var _log_t := 0.0


func setup(p_bike: Bike, p_gm: DeliverySystem, p_terrain: Terrain, p_controls: Controls.Scripted) -> void:
	bike = p_bike; gm = p_gm; terrain = p_terrain; controls = p_controls
	_build_graph()


func _build_graph() -> void:
	var step := 3
	var road_starts: Array[int] = []
	for pts in terrain.road_samples:
		road_starts.append(nodes.size())
		var k := 0
		while k < pts.size():
			nodes.append(pts[k])
			k += step
		if (pts.size() - 1) % step != 0:
			nodes.append(pts[pts.size() - 1])
	adj.resize(nodes.size())
	for i in range(nodes.size()):
		adj[i] = PackedInt32Array()
	# consecutive links within each road
	var idx := 0
	for r in range(terrain.road_samples.size()):
		var start := road_starts[r]
		var end := (road_starts[r + 1] if r + 1 < road_starts.size() else nodes.size())
		for i in range(start, end - 1):
			_link(i, i + 1)
	# junction links: nodes from different roads that are close together
	for i in range(nodes.size()):
		for j in range(i + 1, nodes.size()):
			if absi(i - j) <= 1: continue
			if nodes[i].distance_to(nodes[j]) < 4.5:
				_link(i, j)


func _link(a: int, b: int) -> void:
	var pa: PackedInt32Array = adj[a]; pa.append(b); adj[a] = pa
	var pb: PackedInt32Array = adj[b]; pb.append(a); adj[b] = pb


func _nearest(p: Vector3) -> int:
	var best := 0; var bd := INF
	for i in range(nodes.size()):
		var d := Vector2(nodes[i].x - p.x, nodes[i].z - p.z).length_squared()
		if d < bd: bd = d; best = i
	return best


func _plan(from: Vector3, to: Vector3) -> void:
	var s := _nearest(from); var g := _nearest(to)
	# Dijkstra
	var dist := PackedFloat32Array(); dist.resize(nodes.size()); dist.fill(INF)
	var prev := PackedInt32Array(); prev.resize(nodes.size()); prev.fill(-1)
	var visited := PackedByteArray(); visited.resize(nodes.size()); visited.fill(0)
	dist[s] = 0.0
	for _it in range(nodes.size()):
		var u := -1; var ud := INF
		for i in range(nodes.size()):
			if visited[i] == 0 and dist[i] < ud:
				ud = dist[i]; u = i
		if u == -1 or u == g: break
		visited[u] = 1
		for v in adj[u]:
			var nd := ud + nodes[u].distance_to(nodes[v])
			if nd < dist[v]:
				dist[v] = nd; prev[v] = u
	path = PackedVector3Array()
	var cur := g
	while cur != -1:
		path.append(nodes[cur])
		cur = prev[cur]
	path.reverse()
	path.append(to)
	path_i = 0


func _physics_process(delta: float) -> void:
	if gm.stage == DeliverySystem.Stage.DONE:
		controls.intent.throttle = 0.0; controls.intent.brake = 1.0; controls.intent.steer = 0.0
		return
	var target := gm.target_position()
	if target.distance_to(_last_target) > 0.5:
		_last_target = target
		_plan(bike.global_position, target)
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
	controls.intent.throttle = throttle
	controls.intent.brake = brake
	controls.intent.steer = steer
	if log_enabled:
		_log_t += delta
		if _log_t > 3.0:
			_log_t = 0.0
			print("[autopilot] pos=(%.1f, %.1f, %.1f) speed=%.1f m/s target=%s dist=%.1f grounded=%s" % [pos.x, pos.y, pos.z, sp, gm.target_name(), to_target, bike.grounded])
