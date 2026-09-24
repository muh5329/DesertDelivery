extends Node
class Stamp extends Node:
	var t := 0
	func _process(_d: float) -> void: t = Time.get_ticks_usec()

## Frame cost in a busy Puerto Alto street, with the outer life and without (--no-outer-life):
##   godot --headless --path . -- --test=town_life_bench [--no-outer-life]
## Prints the boot time (engine start -> test ready), then the process / physics time per frame
## over 600 frames with the camera on the main street.
var game: Game


func _ready() -> void:
	game = Game.current
	print("BENCH boot: ready %d ms after engine start" % Time.get_ticks_msec())
	call_deferred("_run")


func _run() -> void:
	var plan: Dictionary = game.world.outer.plan()
	var main: Array = []
	for t in plan.towns:
		if t.id == "puerto_alto":
			for st in t.streets:
				if st.kind == "main": main = st.points
	var a: Array = main[14]; var b: Array = main[4]
	var from := Vector3(a[0], game.world.terrain.height_at(a[0], a[2]) + 1.75, a[2])
	var at := Vector3(b[0], game.world.terrain.height_at(b[0], b[2]) + 1.4, b[2])
	var cam := Camera3D.new(); add_child(cam); cam.current = true
	cam.look_at_from_position(from, at, Vector3.UP)
	game.bike.global_position = from + Vector3(0, 40, 0)
	game.world.set_focus(game.bike)
	game.world.streamer.load_all_pending()
	var outer_life: OuterLife = game.life.outer
	var tf: TownFolk = outer_life.towns if outer_life else null
	if tf:
		tf.prepare_now("puerto_alto")
		var now := floorf(game.life.total_minutes / 1440.0) * 1440.0 + 630.0
		tf.simulate("puerto_alto", now - 70.0, now)
	for i in 240:
		await get_tree().process_frame
		game.bike.global_position = from + Vector3(0, 40, 0)
	PersonBuilder.wait_parts()
	var mode := game.cli.get_string("bench-mode", "")
	if tf and mode == "frozen": tf.enabled = false                  # bodies stay, nothing updates them
	if tf and mode == "released":
		tf.enabled = false
		for body: TownBody in tf.bodies: body.release()
	if tf and mode == "hidden":
		tf.enabled = false
		for body: TownBody in tf.bodies: body.visible = false
	print("BENCH mode '%s'" % mode)
	# all _process callbacks of the frame: from the first (priority -10000) to the last (+10000)
	var first := Stamp.new(); first.process_priority = -10000; get_tree().root.add_child(first)
	var last := Stamp.new(); last.process_priority = 10000; get_tree().root.add_child(last)
	var scripts := 0.0; var scripts_worst := 0.0
	var wall := 0.0
	var proc := 0.0; var phys := 0.0; var tfus := 0; var worst := 0.0; var n := 600
	var trus := 0; var bous := 0
	var tw := Time.get_ticks_usec()
	var parts := [tf.tick_us_total, tf.select_us_total, tf.bodies_us_total] if tf else [0, 0, 0]
	for i in n:
		await get_tree().process_frame
		var now_us := Time.get_ticks_usec(); wall += (now_us - tw) / 1000.0; tw = now_us
		var sc := (last.t - first.t) / 1000.0
		scripts += sc; scripts_worst = maxf(scripts_worst, sc)
		game.bike.global_position = from + Vector3(0, 40, 0)
		var p := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		proc += p; worst = maxf(worst, p)
		phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		if tf:
			tfus += tf.frame_us
			trus += outer_life.traffic.frame_us + outer_life.traffic.physics_us
			bous += outer_life.boats.frame_us
	print("BENCH %s: process %.2f ms/frame (worst %.2f), physics %.2f ms/tick, townsfolk %.3f ms/frame, bodies %d (%d near), people walking %d" % [
		"outer life ON" if tf else "outer life OFF", proc / n, worst, phys / n, tfus / 1000.0 / n,
		tf.bodies_in_use() if tf else 0, tf.near_in_use() if tf else 0, _walking(tf)])
	if tf: print("BENCH townsfolk parts: routines %.3f, choosing bodies %.3f, moving/posing bodies %.3f ms/frame" % [
		(tf.tick_us_total - parts[0]) / 1000.0 / n, (tf.select_us_total - parts[1]) / 1000.0 / n, (tf.bodies_us_total - parts[2]) / 1000.0 / n])
	print("BENCH all _process callbacks %.2f ms/frame (worst %.2f)" % [scripts / n, scripts_worst])
	print("BENCH wall %.2f ms/frame, nodes %d, objects %d" % [wall / n, Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_COUNT)])
	if tf: print("BENCH traffic %.3f ms/frame (%d vehicles, %d spawned, paths %.1f ms total), boats %.3f ms/frame" % [trus / 1000.0 / n,
		outer_life.traffic.count(), outer_life.traffic.spawned, outer_life.traffic.paths_ms, bous / 1000.0 / n])
	get_tree().quit()


func _walking(tf: TownFolk) -> int:
	if tf == null: return 0
	var n := 0
	for p: Townsperson in (tf.towns.puerto_alto as TownPopulation).people:
		if p.state == Townsperson.State.WALKING: n += 1
	return n
