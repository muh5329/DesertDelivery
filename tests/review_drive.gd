extends Node
## REVIEW PROBE (adversarial QA): ride the real bike along the RoadNavigation path to a town.
## A copy of the Autopilot's steering WITHOUT its silent reset crutch: every wedge / crash /
## splash / big air is logged with its position so we can see whether the route is drivable.
## Also logs per-frame wall time (outer terrain / roads / flora streaming switched on headless).
## Run: godot --headless --fixed-fps 60 --path . -- --test=review_drive --route=start:campo_real,campo_real:start
##   --maxtime=900 (game seconds per leg)

var game: Game
var sc: Controls.Scripted
var nav := RoadNavigation.new()
var bike: Bike
var t: Terrain
var legs: Array = []
var leg := -1
var path := PackedVector3Array()
var pi := 0
var leg_t := 0.0
var target := Vector3.ZERO
var start_pos := Vector3.ZERO
var stuck_t := 0.0
var rev_t := 0.0
var events: Array = []
var air_t := 0.0
var air_y0 := 0.0
var max_air := 0.0
var resets := 0
var crashes := 0
var splashes := 0
var frame_ms: Array = []
var _last_us := 0
var log_t := 0.0
var maxtime := 900.0
var min_prog_d := INF
var prog_t := 0.0
var dist_ridden := 0.0
var _prev := Vector3.ZERO
var speeds: Array = []
var _stuck_from := Vector3.ZERO
var _wall0 := 0


func _ready() -> void:
	game = Game.current
	bike = game.bike
	t = game.world.terrain
	maxtime = game.cli.get_float("maxtime", 900.0)
	anticipate = "--anticipate" in OS.get_cmdline_user_args()
	for spec in game.cli.get_string("route", "start:campo_real").split(",", false):
		var ab := spec.split(":")
		legs.append([ab[0], ab[1]])
	start_pos = bike.global_position
	var first: String = legs[0][0]
	if first.begins_with("exit_"):
		var ep := _exit_point(first.substr(5))
		bike.place(ep[0], ep[1])
		start_pos = ep[0]
		game.world.set_focus(bike)
		game.world.outer.refresh_collision()
		game.world.streamer.load_all_pending()
	elif first != "start":
		var sp: Dictionary = game.world.road_spawn(_pos(first), _pos(legs[0][1]))
		bike.place(sp.pos + Vector3.UP * 0.4, sp.forward)
		start_pos = sp.pos
		game.world.set_focus(bike)
		game.world.outer.refresh_collision()
		game.world.streamer.load_all_pending()
	var outer: OuterWorld = game.world.outer
	outer.view.set_process(true); outer.roads.set_process(true); outer.flora.set_process(true)
	bike.crashed.connect(func(): crashes += 1; _event("CRASH"))
	bike.fell_in_sea.connect(func(): splashes += 1; _event("FELL IN SEA"))
	nav.build(t)
	_wall0 = Time.get_ticks_msec()
	if game.cli.get_string("traffic", "on") == "off":
		bike.collision_mask &= ~16          # (traffic colliders: the probe does not brake for traffic)
	sc = game.use_scripted_controls()
	game.encounters.ambush_enabled = false
	game.vitals.health.invulnerable = 1e9
	_next_leg()


func _pos(name: String) -> Vector3:
	if name == "start": return start_pos
	if name.begins_with("exit_"):
		return _exit_point(name.substr(5))[0]
	return game.world.database.location_pos(StringName(name))


## A point 60 m inside the core on the core exit road that joins spoke.<dir>, and the outward heading.
func _exit_point(dir: String) -> Array:
	var outer: OuterWorld = game.world.outer
	var e: Dictionary = outer.roads.roads[outer.roads.by_id["spoke." + dir]]
	var p0: Vector3 = (e.pts as PackedVector3Array)[0]
	for ri in range(outer.roads.nav_first):
		var pts: PackedVector3Array = t.road_samples[ri]
		if pts[pts.size() - 1].distance_to(p0) < 0.5:
			var k := maxi(pts.size() - 16, 0)
			var fwd := pts[mini(k + 2, pts.size() - 1)] - pts[k]; fwd.y = 0.0
			return [pts[k] + Vector3.UP * 0.4, fwd.normalized()]
	return [p0, Vector3.FORWARD]


func _event(what: String) -> void:
	var p := bike.global_position
	var e := "[drive] leg %d t=%.1f %s at (%.1f, %.1f, %.1f) speed %.1f ground %.2f" % [leg, leg_t, what, p.x, p.y, p.z, bike.speed, t.height_at(p.x, p.z)]
	if what == "CRASH":
		for i in range(bike.get_slide_collision_count()):
			var o := bike.get_slide_collision(i).get_collider() as Node
			if o: e += " hit %s/%s" % [o.get_parent().name if o.get_parent() else "", o.name]
	events.append(e); print(e)


func _next_leg() -> void:
	if leg >= 0: _report()
	leg += 1
	if leg >= legs.size():
		_final(); return
	var from := bike.global_position
	target = _pos(legs[leg][1])
	path = nav.path(from, target, 0.0, t)
	pi = 0; leg_t = 0.0; stuck_t = 0.0; min_prog_d = INF; prog_t = 0.0; dist_ridden = 0.0; _prev = from
	resets = 0; crashes = 0; splashes = 0; max_air = 0.0; speeds.clear(); max_off = 0.0; off_road_t = 0.0; max_off_road = 0.0
	var plen := 0.0
	for k in range(1, path.size()): plen += path[k].distance_to(path[k - 1])
	print("[drive] leg %d: %s -> %s, %d path points, %.0f m" % [leg, legs[leg][0], legs[leg][1], path.size(), plen])
	if path.is_empty(): _event("NO PATH"); _next_leg()


func _report() -> void:
	var d := Vector2(bike.global_position.x - target.x, bike.global_position.z - target.z).length()
	var avg := 0.0
	for s in speeds: avg += s
	avg /= maxf(speeds.size(), 1)
	print("[drive] LEG %d %s -> %s: %s after %.0f s, %.0f m ridden, %.0f m from target, avg %.1f m/s, resets %d, crashes %d, splashes %d, max air %.1f s, fuel left %.0f %%, max off-line %.1f m at (%.0f, %.0f), off the road (> 1 m past its edge) %.1f s, worst %.1f m past the edge at (%.0f, %.0f)" % [leg, legs[leg][0], legs[leg][1], "ARRIVED" if d < 40.0 else "FAILED", leg_t, dist_ridden, d, avg, resets, crashes, splashes, max_air, game.journey.fuel_ratio * 100.0, max_off, max_off_at.x, max_off_at.z, off_road_t, max_off_road, max_off_road_at.x, max_off_road_at.z])


func _final() -> void:
	frame_ms.sort()
	var n := frame_ms.size()
	if n > 0:
		print("[drive] frames %d: median %.1f ms, p99 %.1f ms, max %.1f ms; top: %s" % [n, frame_ms[n / 2], frame_ms[int(n * 0.99)], frame_ms[n - 1], str(frame_ms.slice(maxi(n - 8, 0))).substr(0, 200)])
	var outer: OuterWorld = game.world.outer
	print("[drive] outer roads max build %.1f ms, flora max build %.1f ms, streamer %s" % [outer.roads.max_build_ms, outer.flora.max_build_ms, _streamer_stats()])
	print("[drive] static memory %.0f MB" % (OS.get_static_memory_usage() / 1048576.0))
	get_tree().quit(0)


func _streamer_stats() -> String:
	var s = game.world.streamer
	var out := ""
	for k in ["max_build_ms", "last_build_ms", "loaded"]:
		if k in s: out += "%s=%s " % [k, str(s.get(k)) if not (s.get(k) is Dictionary) else str((s.get(k) as Dictionary).size())]
	return out


func _process(_d: float) -> void:
	var now := Time.get_ticks_usec()
	if _last_us > 0:
		var fm := (now - _last_us) / 1000.0
		frame_ms.append(fm)
		if fm > 150.0 and leg >= 0 and leg < legs.size(): _event("SLOW FRAME %.0f ms" % fm)
	_last_us = now


func _physics_process(delta: float) -> void:
	if leg < 0 or leg >= legs.size() or path.is_empty(): return
	leg_t += delta
	var pos := bike.global_position
	dist_ridden += Vector2(pos.x - _prev.x, pos.z - _prev.z).length(); _prev = pos
	speeds.append(absf(bike.speed))
	# airborne episodes
	if not bike.grounded:
		if air_t == 0.0: air_y0 = pos.y
		air_t += delta
	else:
		if air_t > 0.6: _event("LANDED after %.1f s airborne (took off at y %.1f)" % [air_t, air_y0])
		max_air = maxf(max_air, air_t)
		air_t = 0.0
	if game.rider.mode != Rider.Mode.RIDING:
		_event("RIDER MODE %d" % game.rider.mode)
		leg = legs.size(); _final(); return
	if game.journey.fuel_ratio < 0.01:
		_event("OUT OF FUEL after %.0f m ridden this leg (refilled by the probe to keep testing the road)" % dist_ridden)
		game.journey.fuel_ratio = 1.0
	var to_target := Vector2(target.x - pos.x, target.z - pos.z).length()
	if to_target < 25.0 or leg_t > maxtime:
		sc.intent.throttle = 0.0; sc.intent.brake = 1.0
		_next_leg(); return
	while pi < path.size() - 1 and Vector2(path[pi].x - pos.x, path[pi].z - pos.z).length() < 7.0: pi += 1
	var look := path[mini(pi, path.size() - 1)]
	var fwd := bike.flat_forward()
	var to := look - pos; to.y = 0.0
	var ang := fwd.signed_angle_to(to.normalized(), Vector3.UP)
	var steer := clampf(-ang * 1.6, -1.0, 1.0)
	var throttle := 1.0; var brake := 0.0
	var sp := bike.speed
	if absf(ang) > 0.5:
		throttle = 0.35
		if sp > 9.0: brake = 0.6
	elif absf(ang) > 0.25 and sp > 16.0: throttle = 0.2
	if anticipate:
		# (--anticipate: a rider who slows for the corner ahead: the heading change over the next
		# braking distance caps the speed; the plain probe is the Autopilot's steering)
		var turn := _turn_ahead(maxf(24.0, sp * sp / 8.0))
		var cap := 60.0 if turn < 0.35 else (16.0 if turn < 0.7 else (11.0 if turn < 1.2 else 8.0))
		if sp > cap + 1.0: throttle = 0.0; brake = maxf(brake, 0.8)
	# progress along the path
	var wd := Vector2(look.x - pos.x, look.z - pos.z).length()
	if wd < min_prog_d - 1.0 or pi != int(prog_t * 0) and false: pass
	if rev_t <= 0.0: stuck_t += delta
	if pos.distance_to(_stuck_from) > 2.0:
		_stuck_from = pos; stuck_t = 0.0
	if stuck_t > 4.0:
		_event("WEDGED (moved < 2 m in 4 s) waypoint %d/%d %.1f m ahead" % [pi, path.size(), wd])
		rev_t = 1.6; stuck_t = 0.0
		if resets < 50 and _wedges_here() >= 2:
			resets += 1
			_event("RESET to road (wedged twice here)")
			sc.press("reset")
	if rev_t > 0.0:
		rev_t -= delta; throttle = 0.0; brake = 1.0; steer = -steer
	# off the route
	var off := _off_route(pos)
	var offl := _off_line(pos)
	if offl > max_off: max_off = offl; max_off_at = pos
	_or_t -= delta
	if _or_t <= 0.0 and to_target > 60.0:
		_or_t = 0.1
		var orr := _off_road(pos)
		if orr > max_off_road: max_off_road = orr; max_off_road_at = pos
		if orr > 1.0: off_road_t += 0.1
	if off > 25.0 and fmod(leg_t, 2.0) < delta: _event("OFF ROUTE by %.0f m" % off)
	sc.intent.throttle = throttle; sc.intent.brake = brake; sc.intent.steer = steer
	log_t += delta
	if log_t > 10.0:
		log_t = 0.0
		print("[drive] wall %ds leg %d t=%.0f pos (%.0f, %.1f, %.0f) speed %.1f wp %d/%d to target %.0f m" % [(Time.get_ticks_msec() - _wall0) / 1000, leg, leg_t, pos.x, pos.y, pos.z, sp, pi, path.size(), to_target])


var max_off := 0.0
var max_off_at := Vector3.ZERO
var anticipate := false


## The largest heading change of the path within `dist` metres ahead of the current waypoint.
func _turn_ahead(dist: float) -> float:
	if pi < 1 or pi >= path.size() - 1: return 0.0
	var d0 := Vector2(path[pi].x - path[pi - 1].x, path[pi].z - path[pi - 1].z).normalized()
	var acc := 0.0; var worst := 0.0
	for k in range(pi, path.size() - 1):
		var seg := Vector2(path[k + 1].x - path[k].x, path[k + 1].z - path[k].z)
		if seg.length() < 0.5: continue
		worst = maxf(worst, absf(d0.angle_to(seg.normalized())))
		acc += seg.length()
		if acc > dist: break
	return worst
var off_road_t := 0.0                 # seconds with the bike beyond a road's edge (+1 m)
var max_off_road := 0.0
var max_off_road_at := Vector3.ZERO
var _half_w: Dictionary = {}          # road_samples index -> half width
var _or_t := 0.0


## How far past the nearest road's edge the bike is (<= 0: on the carriageway).
func _off_road(p: Vector3) -> float:
	if _half_w.is_empty():
		for e in game.world.outer.roads.roads:
			if int(e.nav) >= 0: _half_w[int(e.nav)] = float(e.width) * 0.5
	if t._road_grid.is_empty(): t.nearest_road(p)
	var best := INF
	var c := Vector2i(floori(p.x / Terrain.ROAD_CELL), floori(p.z / Terrain.ROAD_CELL))
	for dj in range(-2, 3):
		for di in range(-2, 3):
			for e in t._road_grid.get(Vector2i(c.x + di, c.y + dj), []):
				var pts: PackedVector3Array = t.road_samples[e[0]]
				var k: int = e[1]
				var hw: float = _half_w.get(int(e[0]), 2.5)
				for kk in [k - 1, k]:
					if kk < 0 or kk >= pts.size() - 1: continue
					var q := Geometry2D.get_closest_point_to_segment(Vector2(p.x, p.z), Vector2(pts[kk].x, pts[kk].z), Vector2(pts[kk + 1].x, pts[kk + 1].z))
					best = minf(best, q.distance_to(Vector2(p.x, p.z)) - hw)
	return best


## Distance from the path polyline (segments round the current waypoint): how far off the road.
func _off_line(p: Vector3) -> float:
	var best := INF
	for k in range(maxi(pi - 4, 1), mini(pi + 3, path.size())):
		var a := Vector2(path[k - 1].x, path[k - 1].z); var b := Vector2(path[k].x, path[k].z)
		best = minf(best, Geometry2D.get_closest_point_to_segment(Vector2(p.x, p.z), a, b).distance_to(Vector2(p.x, p.z)))
	return best if best != INF else 0.0


var _wedge_spots: Array = []
func _wedges_here() -> int:
	var p := bike.global_position
	_wedge_spots.append(p)
	var n := 0
	for q in _wedge_spots:
		if (q as Vector3).distance_to(p) < 12.0: n += 1
	return n


func _off_route(p: Vector3) -> float:
	var best := INF
	for k in range(maxi(pi - 3, 0), mini(pi + 3, path.size())):
		best = minf(best, Vector2(path[k].x - p.x, path[k].z - p.z).length())
	return best
