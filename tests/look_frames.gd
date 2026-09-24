extends Node
## m-5 probe: where the slow frames go while streaming. The review_stream flight (70 m/s, 60 m up,
## the core -> Campo Real -> Puerto Alto -> sea -> core), and for every frame over --slow ms (33):
## the engine's process / physics times, the node count change (a chunk freed at once shows as a
## big negative), chunks loaded / unloaded that frame, the streamer's build time, the outer roads'
## and flora's last tile builds, BuildingKit's last group. Then the frame-time percentiles.
## Run: godot --headless --fixed-fps 60 --path . -- --test=look_frames [--speed=70] [--slow=33]

var game: Game
var speed := 70.0
var slow := 33.0
var route: Array[Vector3] = []
var seg := 0
var frames: Array = []
var rows: Array = []
var _last := 0
var _nodes := 0
var _loaded := 0
var _unloaded := 0
var _warm := 30


func _ready() -> void:
	game = Game.current
	speed = game.cli.get_float("speed", 70.0)
	slow = game.cli.get_float("slow", 33.0)
	var outer: OuterWorld = game.world.outer
	outer.view.set_process(true); outer.roads.set_process(true); outer.flora.set_process(true)
	game.use_scripted_controls()
	game.encounters.ambush_enabled = false
	game.bike.set_physics_process(false)
	var db := game.world.database
	var start := game.bike.global_position
	for p in [start, Vector3(1500, 0, -300), db.location_pos(&"campo_real"), db.location_pos(&"puerto_alto"), Vector3(5000, 0, 3500), Vector3(1200, 0, 1200), start]:
		route.append(Vector3(p.x, 0, p.z))
	Events.chunk_loaded.connect(func(_c): _loaded += 1)
	Events.chunk_unloaded.connect(func(_c): _unloaded += 1)
	_nodes = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)


func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	var ms := (now - _last) / 1000.0 if _last > 0 else 0.0
	_last = now
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	if _warm > 0:
		_warm -= 1
	elif ms > 0.0:
		frames.append(ms)
		if ms > slow:
			var s := game.world.streamer
			var o: OuterWorld = game.world.outer
			var p := game.bike.global_position
			rows.append([ms, "%.0f ms at (%.0f, %.0f): process %.1f, physics %.1f, nodes %+d, chunks +%d -%d, streamer %.1f ms, roads last %.1f, flora last %.1f, kit last %.1f" % [ms, p.x, p.z,
				Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
				nodes - _nodes, _loaded, _unloaded, s.last_build_usec / 1000.0, o.roads.get("last_build_ms") if o.roads.get("last_build_ms") != null else -1.0,
				o.flora.get("last_build_ms") if o.flora.get("last_build_ms") != null else -1.0, BuildingKit.last_ms]])
	_nodes = nodes; _loaded = 0; _unloaded = 0
	_fly(delta)


func _fly(delta: float) -> void:
	if seg >= route.size() - 1:
		frames.sort()
		var n := frames.size()
		print("[frames] %d frames at %.0f m/s: median %.1f ms, p95 %.1f, p99 %.1f, p99.9 %.1f, max %.1f; > 33 ms: %d, > 50 ms: %d, > 100 ms: %d" % [n, speed,
			frames[n / 2], frames[int(n * 0.95)], frames[int(n * 0.99)], frames[int(n * 0.999)], frames[n - 1],
			frames.filter(func(x): return x > 33.0).size(), frames.filter(func(x): return x > 50.0).size(), frames.filter(func(x): return x > 100.0).size()])
		rows.sort_custom(func(a, b): return a[0] > b[0])
		for r in rows.slice(0, 25): print("[frames]   ", r[1])
		var s := game.world.streamer
		print("[frames] streamer max frame %.1f ms, worst recipe %.1f ms at %s; roads max tile %.1f ms, flora max tile %.1f ms" % [s.max_build_usec / 1000.0,
			s.max_recipe_usec / 1000.0, s.worst_recipe, game.world.outer.roads.max_build_ms, game.world.outer.flora.max_build_ms])
		get_tree().quit(0)
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
