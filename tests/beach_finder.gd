extends RefCounted
## A beach for the Jeep to drive into the sea from (jeep_tests, vehicle_shots): land running
## down into water at least 2 m deep within ~60 m, on the core island or the mainland across
## the lagoon, the gentlest first. Each candidate's chunks are streamed and the collision
## surface along three lanes of the run is checked against the ground height, so nothing (a
## rock, a wall, a jetty) stands in the way.
## `await BeachFinder.find(game, jeep)` -> {land, dir, shore, angle} or {}.


static func candidates(game: Game) -> Array:
	var t: Terrain = game.world.terrain
	var out: Array = []
	for a in range(0, 360, 3):
		var dir := Vector3(cos(deg_to_rad(a)), 0, sin(deg_to_rad(a)))
		var last_land := -1.0
		var r := 150.0
		while r < 1900.0:
			var p := dir * r
			var h := t.height_at(p.x, p.z)
			var wl := t.water_level_at(p.x, p.z)
			if h > wl + 0.2:
				last_land = r
			elif last_land > 0.0 and h < wl - 2.0:
				if r - last_land <= 60.0:
					var c := _score(t, dir, last_land, r)
					c.angle = a
					if c.ok: out.append(c)
				last_land = -1.0
			r += 2.0
	out.sort_custom(func(x, y): return x.steep < y.steep)
	# spread them round the country
	var spread: Array = []
	for c in out:
		var near := false
		for s in spread:
			if (s.dir * s.shore).distance_to(c.dir * c.shore) < 150.0: near = true
		if not near: spread.append(c)
	return spread


static func _score(t: Terrain, dir: Vector3, shore: float, deep: float) -> Dictionary:
	var wl := t.water_level_at(dir.x * shore, dir.z * shore)
	var steep := 0.0
	var ok := true
	var prev := t.height_at(dir.x * (shore - 30.0), dir.z * (shore - 30.0))
	var k := shore - 28.0
	while k <= deep:
		var q := dir * k
		var hq := t.height_at(q.x, q.z)
		steep = maxf(steep, absf(hq - prev))
		if k < shore and (hq > wl + 8.0 or hq < wl - 0.3 or t.biome_at(q.x, q.z) == Terrain.Biome.TOWN): ok = false
		prev = hq
		k += 2.0
	for m in range(0, 50, 5):
		var q := dir * (deep + float(m))
		if t.height_at(q.x, q.z) > wl - 1.5: ok = false
	return {"dir": dir, "shore": shore, "deep": deep, "steep": steep, "ok": ok and steep < 1.5}


static func find(game: Game, jeep: Vehicle) -> Dictionary:
	var t: Terrain = game.world.terrain
	var cands := candidates(game)
	print("    beach candidates: %d" % cands.size())
	for c in cands.slice(0, 12):
		var dir: Vector3 = c.dir
		var land := dir * (float(c.shore) - 16.0)
		land.y = t.height_at(land.x, land.z) + 0.3
		jeep.place(land + Vector3.UP * 30.0, dir)          # held up out of the way while we look
		game.world.set_focus(jeep)
		if game.world.outer and game.world.outer.ok: game.world.outer.refresh_collision()
		game.world.streamer.load_all_pending()
		for i in 3: await game.get_tree().physics_frame
		var space := jeep.get_world_3d().direct_space_state
		var clear := true
		var side := dir.cross(Vector3.UP).normalized()
		for s in range(-2, int(float(c.deep) - float(c.shore)) + 36, 2):
			for lane in [-1.1, 0.0, 1.1]:
				var p := dir * (float(c.shore) - 16.0 + float(s)) + side * float(lane)
				var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 60.0, p.z), Vector3(p.x, -40.0, p.z), 1)
				q.exclude = [jeep.get_rid()]
				var hit := space.intersect_ray(q)
				var g := t.height_at(p.x, p.z)
				if hit.is_empty() or float((hit.position as Vector3).y) > g + 0.45:
					print("    beach at bearing %d (%.0f m) blocked %d m along: %s (ground %.2f)" % [c.angle, c.shore, s,
						"no collision" if hit.is_empty() else "%s at %.2f" % [(hit.collider as Node).name, (hit.position as Vector3).y], g])
					clear = false; break
			if not clear: break
		if not clear: continue
		print("    beach at bearing %d, %.0f m out (steepest step %.2f m)" % [c.angle, c.shore, c.steep])
		return {"land": land, "dir": dir, "shore": c.shore, "angle": c.angle}
	return {}
