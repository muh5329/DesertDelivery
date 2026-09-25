extends Node
## m-5 probe: the slowest single recipes. Builds every recipe of the chunks round --at=x,z (default
## the review's worst, 300,-245; --r=chunks radius, default 2) into a scratch node, times each,
## prints the slowest with the nodes they made. --all times every core chunk instead.
## Run: godot --headless --path . -- --test=look_recipes [--at=300,-245] [--r=2] [--all]

var game: Game


func _ready() -> void:
	game = Game.current
	var db := game.world.database
	var kit: WorldKit = game.world.island
	var at := game.cli.get_string("at", "300,-245").split(",")
	var c0 := db.chunk_of(float(at[0]), float(at[1]))
	var r := game.cli.get_int("r", 2)
	var coords: Array = []
	if "--all" in OS.get_cmdline_user_args():
		coords = db.chunks()
	else:
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1): coords.append(c0 + Vector2i(dx, dz))
	var rows: Array = []
	var sink := Node3D.new(); add_child(sink)
	for c: Vector2i in coords:
		for rec in db.records_in(c):
			var keep := kit.sink
			kit.sink = sink
			var n0 := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
			var t0 := Time.get_ticks_usec()
			rec.builder.call()
			var ms := (Time.get_ticks_usec() - t0) / 1000.0
			var made := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT) - n0)
			kit.sink = keep
			var names := []
			for ch in sink.get_children():
				if names.size() < 4: names.append(String(ch.name))
				ch.free()
			rows.append([ms, "%.1f ms  at (%.0f, %.0f) chunk %s: %d nodes %s  %s" % [ms, rec.pos.x, rec.pos.y, c, made, names, rec.builder.get_method()]])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	var total := 0.0
	for rr in rows: total += rr[0]
	print("[recipes] %d recipes, %.0f ms total" % [rows.size(), total])
	for rr in rows.slice(0, 25): print("[recipes] ", rr[1])
	get_tree().quit(0)
