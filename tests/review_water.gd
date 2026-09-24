extends Node
## REVIEW PROBE (adversarial QA): the outer world's inland water and edges.
##  1  the courier on foot in the middle of the mountain lake (level ~744 m): does he swim?
##  2  the bike driven into the mountain lake: splash / reset, or does it ride the lake bed?
##  3  the courier on foot in the widest river: swim or walk on the bed under the water?
##  4  the bike at the world edge over the sea
## Run: godot --headless --path . -- --test=review_water

var game: Game


func _ready() -> void:
	game = Game.current
	call_deferred("_run")


func _secs(s: float) -> void:
	var t := 0.0
	while t < s:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()


func _run() -> void:
	game.use_scripted_controls()
	game.encounters.ambush_enabled = false
	var outer: OuterWorld = game.world.outer
	var plan := outer.plan()
	var lk: Dictionary = plan.lake
	var level := float(lk.level)
	# a point in the lake: the lowest ground inside the polygon
	var poly := PackedVector2Array()
	for q in lk.polygon: poly.append(Vector2(q[0], q[1]))
	var best := Vector3.ZERO; var lo := INF
	for i in range(400):
		var p := Vector2(lk.x + randf_range(-lk.radius, lk.radius), lk.z + randf_range(-lk.radius, lk.radius))
		if not Geometry2D.is_point_in_polygon(p, poly): continue
		var h := outer.height_at(p.x, p.y)
		if h < lo: lo = h; best = Vector3(p.x, h, p.y)
	print("[water] lake level %.1f, deepest sampled bed %.1f at %s (%.1f m of water)" % [level, lo, best, level - lo])
	# 1 on foot
	game.rider.request_dismount()
	await _secs(0.3)
	game.player.place(best + Vector3.UP * 0.3, Vector3.FORWARD)
	game.world.set_focus(game.player)
	outer.refresh_collision()
	await _secs(2.0)
	var pp := game.player.global_position
	print("[water] 1 on foot in the lake: swimming=%s, feet at %.1f, surface %.1f -> %s" % [game.player.swimming, pp.y, level, "UNDER WATER, walking on the bed" if pp.y < level - 1.0 and not game.player.swimming else "ok"])
	# 2 the bike
	var shore := best
	game.bike.place(best + Vector3.UP * 0.5, Vector3.FORWARD)
	game.player.place(best + Vector3(1.2, 0.3, 0), Vector3.FORWARD)
	await _secs(0.2)
	print("[water] mount: ", game.rider.request_mount(), " mode ", game.rider.mode)
	game.world.set_focus(game.bike)
	var splashed := [false]
	game.bike.fell_in_sea.connect(func(): splashed[0] = true)
	await _secs(2.0)
	var bp := game.bike.global_position
	print("[water] 2 bike in the lake: fell_in_sea=%s, bike at %.1f, surface %.1f -> %s" % [splashed[0], bp.y, level, "RIDES THE LAKE BED under %.1f m of water" % (level - bp.y) if bp.y < level - 1.0 and not splashed[0] else "ok"])
	# 3 the widest river
	var rbest: Array = []; var w := 0.0
	for r in plan.rivers:
		var pts: Array = r.points
		for k in range(0, pts.size(), 25):
			var q: Array = pts[k]
			if float(q[3]) > w and float(q[1]) > 5.0:
				var bed := outer.height_at(q[0], q[2])
				if float(q[1]) - bed > 1.2: w = float(q[3]); rbest = q
	if not rbest.is_empty():
		var rp := Vector3(rbest[0], outer.height_at(rbest[0], rbest[2]), rbest[2])
		game.rider.request_dismount()
		await _secs(0.3)
		game.player.place(rp + Vector3.UP * 0.3, Vector3.FORWARD)
		game.world.set_focus(game.player)
		outer.refresh_collision()
		await _secs(2.0)
		var p3 := game.player.global_position
		print("[water] 3 on foot in a river %.0f m wide, water level %.1f, bed %.1f: swimming=%s, feet at %.1f -> %s" % [w, float(rbest[1]), rp.y, game.player.swimming, p3.y, "UNDER WATER, walking on the bed" if p3.y < float(rbest[1]) - 0.8 and not game.player.swimming else "ok"])
	get_tree().quit(0)
