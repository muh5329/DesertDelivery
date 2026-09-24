extends Node
## REVIEW PROBE (adversarial QA): is every navigation road physically drivable?
## Walks every road in Terrain.road_samples (core + outer) every 1 m at three lateral offsets,
## raycasts the collided world (layer 1) and reports holes, steps, overhangs, sunk/floating
## ribbons, grades and cross-slopes, plus the core-exit -> outer-spoke seams.
## Run: godot --headless --path . -- --test=review_roads [--only=outer|core]

var game: Game
var outer: OuterWorld
var focus: Node3D
var space: PhysicsDirectSpaceState3D


func _ready() -> void:
	game = Game.current
	outer = game.world.outer
	focus = Node3D.new(); add_child(focus)
	outer.focus = focus
	game.bike.set_physics_process(false)
	await get_tree().physics_frame
	space = get_viewport().get_world_3d().direct_space_state
	await _run()
	get_tree().quit(0)


func _ray(p: Vector3, up: float, down: float) -> Variant:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * up, p - Vector3.UP * down, 1)
	var h := space.intersect_ray(q)
	if h.is_empty(): return null
	return h


func _move_focus(p: Vector3, chunks := false) -> void:
	focus.global_position = p
	outer.refresh_collision()
	if chunks:
		game.world.streamer.focus = focus
		game.world.streamer.load_all_pending()


func _run() -> void:
	var t: Terrain = game.world.terrain
	var only := game.cli.get_string("only", "")
	var nav_first: int = outer.roads.nav_first
	var names := {}
	for e in outer.roads.roads:
		if int(e.nav) >= 0: names[int(e.nav)] = String(e.id)
	var bridge_idx := {}
	for b in t.bridges:
		if not bridge_idx.has(b.road): bridge_idx[b.road] = []
		bridge_idx[b.road].append(Vector2i(b.from, b.to))
	var summary: Array = []
	var t0 := Time.get_ticks_msec()
	var total_m := 0.0
	var worst_list: Array = []
	for ri in range(t.road_samples.size()):
		var is_outer := ri >= nav_first
		if only == "outer" and not is_outer: continue
		if only == "core" and is_outer: continue
		var pts: PackedVector3Array = t.road_samples[ri]
		if pts.size() < 2: continue
		var name: String = names.get(ri, "core#%d" % ri)
		var width := 11.0
		for e in outer.roads.roads:
			if int(e.nav) == ri: width = float(e.width)
		if not is_outer: width = 5.0
		var holes := 0; var steps := 0; var over := 0; var sunk := 0; var floaty := 0
		var max_grade := 0.0; var grade_bad := 0; var max_cross := 0.0; var cross_bad := 0
		var max_step := 0.0
		var worst_step_at := Vector3.ZERO
		var prev_h := [INF, INF, INF]
		var seg_len := 0.0
		var last_focus := Vector3(INF, 0, INF)
		var dcount := 0
		var grade_at := Vector3.ZERO
		var along := 0.0
		for k in range(pts.size() - 1):
			var a := pts[k]; var b := pts[k + 1]
			var flat := Vector2(b.x - a.x, b.z - a.z).length()
			if flat > 0.5:
				var g := absf(b.y - a.y) / flat
				# grade over ~12 m (samples are ~4 m) to ignore tiny noise
				var k2 := mini(k + 3, pts.size() - 1)
				var f2 := Vector2(pts[k2].x - a.x, pts[k2].z - a.z).length()
				if f2 > 6.0:
					var g2 := absf(pts[k2].y - a.y) / f2
					if g2 > max_grade: grade_at = a
					max_grade = maxf(max_grade, g2)
					if g2 > 0.16: grade_bad += 1
			var tan := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
			var right := Vector3(-tan.z, 0, tan.x)
			var n := maxi(int(ceil(a.distance_to(b))), 1)
			for s in range(n):
				var p := a.lerp(b, float(s) / n)
				along += 1.0
				var want_chunks := (not is_outer) or along < 400.0 or name.begins_with("street.")
				if Vector2(p.x - last_focus.x, p.z - last_focus.z).length() > (40.0 if want_chunks else 150.0):
					_move_focus(p, want_chunks); last_focus = p
				total_m += 1.0
				var hs := [0.0, 0.0, 0.0]
				var offs := [-width * 0.38, 0.0, width * 0.38]
				for li in range(3):
					var q: Vector3 = p + right * float(offs[li])
					var hit = _ray(Vector3(q.x, p.y, q.z), 4.0, 12.0)
					if hit == null:
						holes += 1; hs[li] = INF; prev_h[li] = INF
						if dcount < 10: dcount += 1; worst_list.append("HOLE %s k=%d at (%.1f, %.1f, %.1f) lat %.1f" % [name, k, q.x, p.y, q.z, offs[li]])
						continue
					var hy: float = hit.position.y
					hs[li] = hy
					var dy := hy - p.y
					if dy > 0.9:
						over += 1
						if dcount < 10 and over <= 3: dcount += 1; worst_list.append("OVERHANG/OBSTACLE %s k=%d at (%.1f, %.1f, %.1f) lat %.1f: hit %.2f m above road (%s)" % [name, k, q.x, p.y, q.z, offs[li], dy, hit.collider.name if hit.collider else "?"])
					elif li == 1 and dy < -0.6:
						sunk += 1
						if dcount < 10 and sunk <= 3: dcount += 1; worst_list.append("GROUND BELOW ROAD PROFILE %s k=%d at (%.1f, %.1f, %.1f): %.2f m" % [name, k, p.x, p.y, p.z, dy])
					elif li == 1 and dy > 0.35:
						floaty += 1
						if dcount < 10 and floaty <= 3: dcount += 1; worst_list.append("GROUND ABOVE ROAD PROFILE (ribbon buried) %s k=%d at (%.1f, %.1f, %.1f): +%.2f m" % [name, k, p.x, p.y, p.z, dy])
					if prev_h[li] != INF:
						var st := absf(hy - float(prev_h[li]))
						if st > max_step: max_step = st; worst_step_at = q
						if st > 0.4:
							steps += 1
							if dcount < 10 and steps <= 4: dcount += 1; worst_list.append("STEP %s k=%d at (%.1f, %.1f, %.1f) lat %.1f: %.2f m in 1 m (%s)" % [name, k, q.x, hy, q.z, offs[li], st, hit.collider.name if hit.collider else "?"])
					prev_h[li] = hy
				if hs[0] != INF and hs[2] != INF:
					var cs := absf(float(hs[0]) - float(hs[2])) / (width * 0.76)
					max_cross = maxf(max_cross, cs)
					if cs > 0.12: cross_bad += 1
			seg_len += a.distance_to(b)
		summary.append([name, seg_len, holes, steps, over, sunk, floaty, max_grade, grade_bad, max_cross, cross_bad, max_step, worst_step_at])
		if grade_bad > 0: worst_list.append("GRADE %s max %.1f%% over 12 m at %s" % [name, max_grade * 100.0, grade_at])
		if Time.get_ticks_msec() - t0 > 1500000: break
	print("ROADPROBE: %.0f m walked in %d s" % [total_m, (Time.get_ticks_msec() - t0) / 1000])
	print("ROADPROBE columns: road, length m, holes, steps>0.4m, obstacles>0.9m above, ground<-0.6 (profile over air), ground>+0.35 (buried), max grade(12m), #grade>16%, max cross-slope, #cross>12%, max 1m step, at")
	for s in summary:
		var flag: bool = s[2] > 0 or s[3] > 0 or s[4] > 0 or s[5] > 0 or s[6] > 0 or s[8] > 0 or s[10] > 0
		print("ROADPROBE %s %-40s %7.0f m  holes %d  steps %d  obst %d  air %d  buried %d  grade %.1f%% (%d)  cross %.1f%% (%d)  maxstep %.2f @ %s" % ["!!" if flag else "ok", s[0], s[1], s[2], s[3], s[4], s[5], s[6], s[7] * 100.0, s[8], s[9] * 100.0, s[10], s[11], str(s[12])])
	for w in worst_list: print("ROADPROBE-DETAIL ", w)
	# ---------------------------------------------------------------- core exit seams
	var plan := outer.ground.plan
	for r in plan.roads:
		if not String(r.id).begins_with("spoke."): continue
		var p0 := Vector3(r.points[0][0], r.points[0][1], r.points[0][2])
		var best := INF; var best_p := Vector3.ZERO; var best_r := -1
		for ri in range(nav_first):
			var pts: PackedVector3Array = t.road_samples[ri]
			for q in [pts[0], pts[pts.size() - 1]]:
				var d: float = (q as Vector3).distance_to(p0)
				if d < best: best = d; best_p = q; best_r = ri
		_move_focus(p0)
		await get_tree().physics_frame
		# the seam: the ground either side of the core square boundary along the road
		var dir := (Vector3(r.points[3][0], r.points[3][1], r.points[3][2]) - p0).normalized()
		var line := ""
		var prev := INF
		var worst := 0.0
		for i in range(-40, 41):
			var q := p0 + dir * float(i) * 0.5
			var hit = _ray(q, 5.0, 15.0)
			var hy: float = hit.position.y if hit else INF
			if hit and prev != INF: worst = maxf(worst, absf(hy - prev))
			prev = hy
			if i % 8 == 0: line += " %.2f" % hy if hit else " HOLE"
		print("SEAM %s: core road #%d end %s vs spoke start %s: gap %.2f m; 0.5 m steps across the seam max %.2f m; heights%s" % [r.id, best_r, best_p, p0, best, worst, line])
