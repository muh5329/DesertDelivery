extends Node
## C-1 probe: ride the real bike over every bridge of the outer network, both ways, at speed.
## For each span: start 120 m before it on the road's own samples, follow them (pure pursuit, the
## Autopilot's steering) to 60 m past it, and log the longest airborne spell, splashes, crashes,
## the worst gap between the bike and the road profile, and whether it stayed on the carriageway.
## Also rides the four core-exit seams (the core exit's last 150 m and the spoke's first 150 m).
## Run: godot --headless --fixed-fps 60 --path . -- --test=bridge_drive [--speed=22] [--only=spoke.east]

var game: Game
var sc: Controls.Scripted
var bike: Bike
var t: Terrain
var outer: OuterWorld
var runs: Array = []           # [{name, pts}]
var cur := -1
var path := PackedVector3Array()
var pi := 0
var run_t := 0.0
var air_t := 0.0
var max_air := 0.0
var air_at := Vector3.ZERO
var max_air_at := Vector3.ZERO
var splashes := 0
var crashes := 0
var off_max := 0.0
var gap_max := 0.0
var vmax := 22.0
var fails := 0
var results: Array = []


func _ready() -> void:
	game = Game.current
	bike = game.bike
	t = game.world.terrain
	outer = game.world.outer
	vmax = game.cli.get_float("speed", 22.0)
	only = game.cli.get_string("only", "").split(",", false)
	trace = "--trace" in OS.get_cmdline_user_args()
	for e in outer.roads.roads:
		if e.nav < 0 and not e.get("seam", false): continue
		if not _want(String(e.id)): continue
		var P: PackedVector3Array = e.pts
		if e.get("seam", false): continue
		for span in e.bridges:
			var a := maxi(int(span[0]) - 30, 0); var b := mini(int(span[1]) + 15, P.size() - 1)
			if b - a < 8: continue
			var fw := P.slice(a, b + 1)
			var v: float = {"highway": vmax, "road": vmax * 0.8, "track": vmax * 0.55}.get(e.cls, vmax * 0.8)
			runs.append({"name": "%s [%d..%d] out" % [e.id, span[0], span[1]], "pts": fw, "v": v})
			var bw := PackedVector3Array()
			var a2 := maxi(int(span[0]) - 15, 0); var b2 := mini(int(span[1]) + 30, P.size() - 1)
			for k in range(b2, a2 - 1, -1): bw.append(P[k])
			runs.append({"name": "%s [%d..%d] back" % [e.id, span[0], span[1]], "pts": bw, "v": v})
	# the core seams: the core exit's last samples then the spoke's first
	for s in outer.roads.seams:
		var spoke: Dictionary = outer.roads.roads[outer.roads.by_id[String(s.id).substr(5)]]
		var cs: PackedVector3Array = t.road_samples[int(s.road)]
		var P := PackedVector3Array()
		for k in range(maxi(int(s.from) - 40, 0), cs.size() - 1, 4): P.append(cs[k])
		var SP: PackedVector3Array = spoke.pts
		for k in range(0, mini(60, SP.size())): P.append(SP[k])
		if not _want(String(s.id)): continue
		runs.append({"name": "%s out of the core" % s.id, "pts": P, "v": vmax * 0.8})
		var R := PackedVector3Array()
		for k in range(P.size() - 1, -1, -1): R.append(P[k])
		runs.append({"name": "%s into the core" % s.id, "pts": R, "v": vmax * 0.8})
	if trace:
		for sm in outer.roads.seams:
			var sp: PackedVector3Array = sm.pts
			var line := ""
			for q in sp: line += " (%.1f,%.2f,%.1f|g%.2f)" % [q.x, q.y, q.z, t.height_at(q.x, q.z)]
			print("[trace] %s from core sample %d:%s" % [sm.id, sm.from, line])
	print("[bridges] %d runs" % runs.size())
	bike.crashed.connect(func(): crashes += 1; _event("CRASH"))
	bike.fell_in_sea.connect(func(): splashes += 1; _event("SPLASH"))
	if game.cli.get_string("traffic", "on") == "off":
		bike.collision_mask &= ~16          # (traffic colliders: the probe does not brake for traffic)
	sc = game.use_scripted_controls()
	game.encounters.ambush_enabled = false
	game.vitals.health.invulnerable = 1e9
	_next()


var events: Array = []
var speed_cap := 22.0
var only: PackedStringArray
var trace := false


## --only=a,b: runs whose road id starts with one of the prefixes (seams: "seam.")
func _want(id: String) -> bool:
	if only.is_empty(): return true
	for o in only:
		if id.begins_with(o): return true
	return false


func _event(what: String) -> void:
	var p := bike.global_position
	var hit := ""
	for i in range(bike.get_slide_collision_count()):
		var c := bike.get_slide_collision(i)
		var o := c.get_collider() as Node
		hit += " %s%s n=(%.2f,%.2f,%.2f) at (%.1f,%.1f,%.1f)" % [o.name if o else "?", ("/" + String(o.get_parent().name)) if o and o.get_parent() else "", c.get_normal().x, c.get_normal().y, c.get_normal().z, c.get_position().x, c.get_position().y, c.get_position().z]
	events.append("[bridges]     %s at (%.1f, %.1f, %.1f) speed %.1f, path %d/%d, hit:%s" % [what, p.x, p.y, p.z, bike.speed, pi, path.size(), hit])


func _next() -> void:
	if cur >= 0: _report()
	cur += 1
	if cur >= runs.size():
		print("[bridges] %d runs, %d failed" % [runs.size(), fails])
		for r in results: print(r)
		print("BRIDGE DRIVE: %d runs, %d failed" % [runs.size(), fails])
		get_tree().quit(1 if fails > 0 else 0)
		return
	path = runs[cur].pts
	speed_cap = float(runs[cur].get("v", vmax))
	var fwd := path[3] - path[0]; fwd.y = 0.0
	bike.place(path[0] + Vector3.UP * 0.5, fwd.normalized())
	game.world.set_focus(bike)
	outer.refresh_collision()
	game.world.streamer.load_all_pending()          # landmarks (the dam), town dressing
	bike.speed = speed_cap * 0.8
	pi = 1; run_t = 0.0; air_t = 0.0; max_air = 0.0; splashes = 0; crashes = 0; off_max = 0.0; gap_max = 0.0
	game.journey.fuel_ratio = 1.0


func _report() -> void:
	var ok := max_air <= 0.3 and splashes == 0 and crashes == 0 and off_max < 4.0 and pi >= path.size() - 2
	if not ok: fails += 1
	results.append("[bridges] %s %-52s air %.2f s (at %.0f, %.0f), splashes %d, crashes %d, off-line %.1f m, profile gap %.2f m, %s" % [
		"ok" if ok else "FAIL", runs[cur].name, max_air, max_air_at.x, max_air_at.z, splashes, crashes, off_max, gap_max,
		"done" if pi >= path.size() - 2 else "stopped at %d/%d" % [pi, path.size()]])
	results.append_array(events)
	events.clear()


func _physics_process(delta: float) -> void:
	if cur < 0 or cur >= runs.size(): return
	run_t += delta
	var pos := bike.global_position
	if trace:
		var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP, pos + Vector3.DOWN * 3.0, 1)
		q.exclude = [bike.get_rid()]
		var h := get_viewport().get_world_3d().direct_space_state.intersect_ray(q)
		print("[trace] %s t=%.2f pos (%.1f, %.2f, %.1f) v %.1f vy %.2f grounded %s under %s %.2f" % [runs[cur].name, run_t, pos.x, pos.y, pos.z, bike.speed, bike.velocity.y, bike.grounded,
			(h.collider as Node).name if not h.is_empty() else "-", h.position.y if not h.is_empty() else 0.0])
	# (the first second: the bike was placed 0.5 m up and drops onto the road)
	if not bike.grounded and run_t > 1.0:
		if air_t == 0.0: air_at = pos
		air_t += delta
	elif bike.grounded:
		if air_t > max_air: max_air = air_t; max_air_at = air_at
		air_t = 0.0
	if game.rider.mode != Rider.Mode.RIDING:
		print("[bridges] rider mode %d on %s" % [game.rider.mode, runs[cur].name])
		crashes += 1
	while pi < path.size() - 1 and Vector2(path[pi].x - pos.x, path[pi].z - pos.z).length() < 9.0: pi += 1
	# distance to the path polyline and the profile there
	var best := INF; var gy := 0.0
	for k in range(maxi(pi - 3, 1), mini(pi + 2, path.size())):
		var a := path[k - 1]; var b := path[k]
		var ab := Vector2(b.x - a.x, b.z - a.z); var ap := Vector2(pos.x - a.x, pos.z - a.z)
		var u := clampf(ap.dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
		var d := (ap - ab * u).length()
		if d < best: best = d; gy = lerpf(a.y, b.y, u)
	off_max = maxf(off_max, best)
	if bike.grounded: gap_max = maxf(gap_max, absf(pos.y - gy))
	if pi >= path.size() - 2 or run_t > 90.0 or splashes > 0:
		max_air = maxf(max_air, air_t)
		_next(); return
	var look := path[mini(pi, path.size() - 1)]
	var fwd := bike.flat_forward()
	var to := look - pos; to.y = 0.0
	var ang := fwd.signed_angle_to(to.normalized(), Vector3.UP)
	sc.intent.steer = clampf(-ang * 1.6, -1.0, 1.0)
	sc.intent.throttle = 1.0 if bike.speed < speed_cap else 0.0
	sc.intent.brake = 0.4 if bike.speed > speed_cap + 2.0 else 0.0
