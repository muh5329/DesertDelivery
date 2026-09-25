extends Node
## FIXPLAY DIAGNOSTIC (m-2): a camp sniped from 190 m near the salt flats, at a spot with a clear
## line of sight (review_snipe's and review_combat B's spot has a ridge in the way); logs every
## man's state, sub-state, sight, distance and facing error every 2 s, then a summary (enemy shots,
## hits, damage taken). With the m-2 fix: the camp fights within ~2 s, the long guns fire
## suppressively from ~185 m and the rest bound forward (54 shots, 6 hits in one 83 s run).
##   godot --headless --path . -- --test=fixplay_snipe_diag

var game: Game


func _ready() -> void:
	game = Game.current
	call_deferred("_run")


func _secs(s: float) -> void:
	var t := 0.0
	while t < s:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()


func _ground(x: float, z: float) -> Vector3:
	return Vector3(x, game.world.terrain.height_at(x, z) + 0.08, z)


func _aim_at(p: Vector3) -> void:
	var d: Vector3 = p - game.cam.global_position
	game.cam.set_look(atan2(-d.x, -d.z), -atan2(d.y, Vector2(d.x, d.z).length()))


func _run() -> void:
	var sc := game.use_scripted_controls()
	var dir: EncounterDirector = game.encounters
	dir.ambush_enabled = false
	game.rider.request_dismount()
	await _secs(0.5)
	var s: Vector3 = game.world.database.location_pos(&"salinas")
	var at := _ground(s.x + 30.0, s.z - 25.0)
	var bpos := _ground(at.x, at.z - 190.0)
	# a spot with a clear line of sight over 190 m (the terrain 2 m under the line everywhere)
	var found := false
	for r in range(0, 900, 60):
		for k in range(12):
			var a := TAU * k / 12.0
			var c := _ground(s.x + cos(a) * r, s.z + sin(a) * r)
			if c.y < 2.0: continue
			for kk in range(8):
				var b2 := TAU * kk / 8.0
				var e := _ground(c.x + cos(b2) * 190.0, c.z + sin(b2) * 190.0)
				if e.y < 2.0: continue
				var clear := true
				for i in range(1, 38):
					var p := c.lerp(e, i / 38.0) + Vector3(0, 1.3, 0)
					if game.world.terrain.height_at(p.x, p.z) > p.y - 1.0: clear = false; break
				if clear: at = c; bpos = e; found = true; break
			if found: break
		if found: break
	print("spot found %s: courier %s camp %s" % [found, at, bpos])
	var fdir := (bpos - at); fdir.y = 0; fdir = fdir.normalized()
	game.player.place(at, fdir)
	game.world.set_focus(game.player)
	game.cam.snap_to_target()
	await _secs(0.5)
	game.vitals.health.invulnerable = 0.0
	game.gun.reserve_clips = 12; game.gun.ammo = 8
	game.world.streamer.load_all_pending()
	await _secs(0.5)
	dir.add_camp(&"camp.diag", &"bandit", bpos, -fdir, 5, &"")
	dir.spawn_camp(&"camp.diag")
	var men: Array = dir.enemies_of(&"camp.diag")
	sc.intent.aim = true
	await _secs(1.0)
	var t := 0.0
	var next_fire := 0.0
	var next_log := 0.0
	var min_h := 100.0
	var kills := 0
	while t < 90.0:
		min_h = minf(min_h, game.vitals.health.current)
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		var alive: Array = men.filter(func(e): return is_instance_valid(e) and not e.is_dead())
		if alive.is_empty(): break
		_aim_at(alive[0].global_position + Vector3(0, 1.0, 0))
		if t > next_fire and not game.gun.reloading and game.gun.ammo > 0 and game.gun.ads_blend > 0.95:
			sc.press("fire"); next_fire = t + 1.2
		if t > next_log:
			next_log = t + 2.0
			for e in men:
				if not is_instance_valid(e): continue
				var en: Enemy = e
				var cp: Vector3 = game.player.global_position
				var want := atan2(-(en.target_pos.x - en.global_position.x), -(en.target_pos.z - en.global_position.z))
				var eye := en.global_position + Vector3(0, Enemy.EYE, 0)
				var q := PhysicsRayQueryParameters3D.create(eye, cp + Vector3(0, 1.2, 0), Enemy.SIGHT_MASK)
				q.exclude = [en.get_rid(), game.player.get_rid()]
				var h := en.get_world_3d().direct_space_state.intersect_ray(q)
				print("t %.0f %s %s st %s sub %s sees %s d %.0f tier %d face_err %.2f tgt_err %.0f shots %d los %s" % [t, en.enemy_id, en.weapon, Enemy.State.keys()[en.state], Enemy.Sub.keys()[en.sub], en.sees_target, en.global_position.distance_to(cp), en._tier, absf(wrapf(en.rotation.y - want, -PI, PI)), en.target_pos.distance_to(cp), en.shots, ("clear" if h.is_empty() else "%s at %s" % [h.collider, h.position])])
	var shots := 0
	for e in men:
		if is_instance_valid(e): shots += e.shots; kills += 1 if e.is_dead() else 0
	print("DIAG SUMMARY: %.0f s, dead %d, enemy shots %d, enemy hits %d, courier took %.0f (grace on: damage counted from hits)" % [t, kills, shots, men.reduce(func(acc, e): return acc + (e.hits if is_instance_valid(e) else 0), 0), 100.0 - min_h])
	print("DIAG DONE")
	get_tree().quit()
