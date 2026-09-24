extends Node
## REVIEW PROBE (adversarial QA): streaming stress on the CPU side (headless: no GPU, but every
## mesh / collision / BuildingKit / flora / road ribbon build still happens; the outer terrain view,
## roads and flora are switched back on). Two parts:
##  1  a fast low flight (the focus moved kinematically at --speed m/s, 60 m above the ground) from
##     the core over Campo Real and Puerto Alto and back over the sea: per-frame wall times, the
##     worst frames and what was streaming, how far behind the chunk streamer falls;
##  2  twenty teleports round the 25 km world (F6-style): the stall on arrival, frames until the
##     streamer is idle, and node / object / memory counts back at the start (leaks).
## Run: godot --headless --fixed-fps 60 --path . -- --test=review_stream [--speed=70]

var game: Game
var focus: Node3D
var speed := 70.0
var route: Array[Vector3] = []
var seg := 0
var frame_ms: Array = []
var worst: Array = []
var _last := 0
var phase := 0
var lag_max := 0
var t := 0.0


func _ready() -> void:
	game = Game.current
	speed = game.cli.get_float("speed", 70.0)
	var outer: OuterWorld = game.world.outer
	outer.view.set_process(true); outer.roads.set_process(true); outer.flora.set_process(true)
	game.use_scripted_controls()
	game.encounters.ambush_enabled = false
	game.bike.set_physics_process(false)
	var db := game.world.database
	var start := game.bike.global_position
	for p in [start, Vector3(1500, 0, -300), db.location_pos(&"campo_real"), db.location_pos(&"puerto_alto"), Vector3(5000, 0, 3500), Vector3(1200, 0, 1200), start]:
		route.append(Vector3(p.x, 0, p.z))
	_mem("boot")


func _mem(label: String) -> void:
	print("[stream] MEM %s: static %.0f MB, objects %d, nodes %d, resources %d, orphan nodes %d, chunks %d" % [label,
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, Performance.get_monitor(Performance.OBJECT_COUNT),
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
		Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT), game.world.streamer.loaded.size()])


func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	var ms := (now - _last) / 1000.0 if _last > 0 else 0.0
	_last = now
	var s := game.world.streamer
	if phase == 0:
		if ms > 0.0:
			frame_ms.append(ms)
			if ms > 50.0:
				var p := game.bike.global_position
				worst.append("%.0f ms at (%.0f, %.0f) chunks loaded %d pending %d building %d, streamer %.1f ms, roads max %.1f, flora max %.1f" % [ms, p.x, p.z, s.loaded.size(), s._pending.size(), s._building.size(), s.last_build_usec / 1000.0, game.world.outer.roads.max_build_ms, game.world.outer.flora.max_build_ms])
		lag_max = maxi(lag_max, s._pending.size() + s._building.size())
		_fly(delta)
	elif phase == 1:
		phase = 2
		_teleports()


func _fly(delta: float) -> void:
	t += delta
	if seg >= route.size() - 1:
		frame_ms.sort()
		var n := frame_ms.size()
		print("[stream] FLIGHT at %.0f m/s: %d frames, median %.1f ms, p95 %.1f, p99 %.1f, max %.1f ms; frames > 33 ms: %d, > 100 ms: %d; streamer backlog max %d chunks; max streamer frame %.1f ms, worst recipe %.1f ms at %s %s" % [speed, n, frame_ms[n / 2], frame_ms[int(n * 0.95)], frame_ms[int(n * 0.99)], frame_ms[n - 1],
			frame_ms.filter(func(x): return x > 33.0).size(), frame_ms.filter(func(x): return x > 100.0).size(), lag_max,
			game.world.streamer.max_build_usec / 1000.0, game.world.streamer.max_recipe_usec / 1000.0, game.world.streamer.worst_recipe, game.world.streamer.worst_recipe_attribution])
		worst.sort()
		for w in worst.slice(maxi(worst.size() - 12, 0)): print("[stream]   slow frame: ", w)
		_mem("after flight")
		phase = 1
		return
	var a := route[seg]; var b := route[seg + 1]
	var p := game.bike.global_position
	var flat := Vector3(p.x, 0, p.z)
	var dir := (b - flat); dir.y = 0.0
	if dir.length() < speed * delta * 1.5:
		seg += 1; return
	var np := flat + dir.normalized() * speed * delta
	np.y = maxf(game.world.terrain.height_at(np.x, np.z), 0.0) + 60.0
	game.bike.global_position = np
	game.bike.look_at(np + dir.normalized(), Vector3.UP)
	game.world.set_focus(game.bike)


func _teleports() -> void:
	var rng := RandomNumberGenerator.new(); rng.seed = 7
	var db := game.world.database
	var spots: Array[Vector3] = []
	for id in [&"puerto_alto", &"sarmada", &"valdoro", &"isola_serena", &"campo_real"]: spots.append(db.location_pos(id))
	for i in range(15): spots.append(Vector3(rng.randf_range(-11000, 11000), 0, rng.randf_range(-11000, 11000)))
	var start := route[0]
	for p in spots:
		var t0 := Time.get_ticks_usec()
		var q := Vector3(p.x, maxf(game.world.terrain.height_at(p.x, p.z), 0.0) + 2.0, p.z)
		game.bike.global_position = q
		game.world.set_focus(game.bike)
		game.world.outer.refresh_collision()
		var sync_ms := (Time.get_ticks_usec() - t0) / 1000.0
		var frames := 0
		var worst_f := 0.0
		var last := Time.get_ticks_usec()
		while frames < 3000:
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			worst_f = maxf(worst_f, (now - last) / 1000.0); last = now
			frames += 1
			var s := game.world.streamer
			if frames > 3 and s._pending.is_empty() and s._building.is_empty() and game.world.outer.roads.pending.is_empty() and game.world.outer.flora.pending.is_empty(): break
		print("[stream] TELEPORT to (%.0f, %.0f): collision refresh %.0f ms, %d frames (%.1f s at 60 fps) until the streamer is idle, worst frame %.0f ms, chunks %d" % [p.x, p.z, sync_ms, frames, frames / 60.0, worst_f, game.world.streamer.loaded.size()])
	game.bike.global_position = Vector3(start.x, game.world.terrain.height_at(start.x, start.z) + 2.0, start.z)
	game.world.set_focus(game.bike)
	for i in range(600): await get_tree().process_frame
	_mem("back at the start after 20 teleports")
	get_tree().quit(0)
