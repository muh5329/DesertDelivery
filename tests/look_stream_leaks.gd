extends Node
## m-4 probe: where do nodes / objects accumulate over a tour of the country? Teleports round the
## 25 km world (the review_stream spots: the five towns and 15 random points), back to the start,
## lets everything settle, and prints the node count of every subtree (depth <= 4) that grew,
## plus the caches' sizes. --soak=N repeats the tour N times (default 1) and reports each lap, so a
## bounded cache shows as growth on lap 1 only.
## Run: godot --headless --fixed-fps 60 --path . -- --test=look_stream_leaks [--soak=3]

var game: Game
var before: Dictionary = {}


func _ready() -> void:
	game = Game.current
	var outer: OuterWorld = game.world.outer
	outer.view.set_process(true); outer.roads.set_process(true); outer.flora.set_process(true)
	game.use_scripted_controls()
	game.encounters.ambush_enabled = false
	game.bike.set_physics_process(false)
	_run()


func _counts(n: Node, path: String, depth: int, out: Dictionary) -> int:
	var total := 1
	for c in n.get_children():
		var key := path + "/" + _label(c)
		total += _counts(c, key, depth + 1, out)
	if depth <= 4: out[path] = int(out.get(path, 0)) + total
	return total


## Streamed children are named per chunk / tile: fold the numbers so a subtree compares by kind.
func _label(n: Node) -> String:
	var s := String(n.name)
	var re := RegEx.new(); re.compile("[-0-9@]+")
	return re.sub(s, "#", true)


func _snapshot() -> Dictionary:
	var out := {}
	_counts(game, "Game", 0, out)
	return out


func _mem(label: String) -> void:
	print("[leaks] %s: nodes %d, objects %d, resources %d, static %.0f MB, chunks %d, orphans %d" % [label,
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_COUNT),
		Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT), Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		game.world.streamer.loaded.size(), Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)])


func _settle(frames: int) -> void:
	for i in range(frames): await get_tree().process_frame


func _run() -> void:
	var start := game.bike.global_position
	await _settle(120)
	_mem("boot")
	before = _snapshot()
	var laps := game.cli.get_int("soak", 1)
	var rng := RandomNumberGenerator.new(); rng.seed = 7
	var db := game.world.database
	var spots: Array[Vector3] = []
	for id in [&"puerto_alto", &"sarmada", &"valdoro", &"isola_serena", &"campo_real"]: spots.append(db.location_pos(id))
	for i in range(15): spots.append(Vector3(rng.randf_range(-11000, 11000), 0, rng.randf_range(-11000, 11000)))
	for lap in range(laps):
		for p in spots:
			game.bike.global_position = Vector3(p.x, maxf(game.world.terrain.height_at(p.x, p.z), 0.0) + 2.0, p.z)
			game.world.set_focus(game.bike)
			game.world.outer.refresh_collision()
			var frames := 0
			while frames < 3000:
				await get_tree().process_frame
				frames += 1
				var s := game.world.streamer
				if frames > 30 and s._pending.is_empty() and s._building.is_empty() and game.world.outer.roads.pending.is_empty() and game.world.outer.flora.pending.is_empty(): break
		game.bike.global_position = Vector3(start.x, game.world.terrain.height_at(start.x, start.z) + 2.0, start.z)
		game.world.set_focus(game.bike)
		await _settle(900)
		_mem("lap %d back at the start" % (lap + 1))
	var after := _snapshot()
	var rows: Array = []
	for k in after:
		var d := int(after[k]) - int(before.get(k, 0))
		if absi(d) >= 20: rows.append([d, k, int(before.get(k, 0)), int(after[k])])
	rows.sort_custom(func(a, b): return absi(a[0]) > absi(b[0]))
	for r in rows.slice(0, 40): print("[leaks] %+6d  %s  (%d -> %d)" % [r[0], r[1], r[2], r[3]])
	var outer: OuterWorld = game.world.outer
	print("[leaks] outer: road tiles %d, flora %s, collision tiles %d" % [outer.roads.loaded.size(), outer.flora.stats(), outer.loaded.size()])
	get_tree().quit(0)
