extends Node
## REVIEW copy of tests/shot.gd with --size=WxH and --hour=H (island clock) added.
## Render tool: arbitrary cameras, streamed around each subject.
## Usage:
##   godot --path . -- --test=shot --out=/tmp/shots --cams="name:fx,fy,fz:ax,ay,az;name2:..."
##   A coordinate prefixed with "g" is ground relative, e.g. "gy5" (5 m above the ground).
##   --settle=N frames per view (default 24), --player to keep the rider and bike visible,
##   --hud to keep the HUD, --fov=62, --size=1600x900 (window size).

var out := "/tmp/shots"
var frame := 0
var cams: Array = []
var idx := 0
var cam: Camera3D
var settle := 24
var game: Game
var _t_last := 0
var _t_acc := 0.0
var _t_n := 0


func _ready() -> void:
	game = Game.current
	out = game.cli.get_string("out", out)
	var sz := game.cli.get_string("size", "")
	if sz != "":
		var wh := sz.split("x")
		get_window().size = Vector2i(int(wh[0]), int(wh[1]))
	var hour := game.cli.get_float("hour", -1.0)
	if hour >= 0.0 and game.life:
		var day := floorf(game.life.total_minutes / 1440.0)
		game.life.advance_to((day + (1.0 if hour * 60.0 < fmod(game.life.total_minutes, 1440.0) else 0.0)) * 1440.0 + hour * 60.0)
	settle = game.cli.get_int("settle", 24)
	DirAccess.make_dir_recursive_absolute(out)
	if not "--hud" in OS.get_cmdline_user_args():
		game.hud.visible = false
		var ui := game.get_node_or_null("UI")
		if ui:
			for c in ui.get_children():
				if c is CanvasLayer or c is Control: c.visible = false
	if not "--player" in OS.get_cmdline_user_args():
		game.bike.visible = false; game.player.visible = false; game.jeep.visible = false; game.cart.visible = false
	var t: Terrain = game.world.terrain
	for entry in game.cli.get_string("cams", "").split(";", false):
		var parts := entry.split(":")
		if parts.size() != 3: push_error("bad cam " + entry); continue
		cams.append([parts[0], _vec(parts[1], t), _vec(parts[2], t)])
	cam = Camera3D.new(); cam.fov = game.cli.get_float("fov", 62.0); cam.far = 30000; cam.near = 0.1
	add_child(cam); cam.current = true
	t.set_view_camera(cam)
	if cams.is_empty(): get_tree().quit(); return
	_place()


func _vec(s: String, t: Terrain) -> Vector3:
	var c := s.split(",")
	var x := float(c[0]); var z := float(c[2])
	var ys: String = c[1]
	var y := 0.0
	if ys.begins_with("g"): y = t.height_at(x, z) + float(ys.substr(1))
	else: y = float(ys)
	return Vector3(x, y, z)


func _place() -> void:
	var from: Vector3 = cams[idx][1]; var at: Vector3 = cams[idx][2]
	cam.look_at_from_position(from, at, Vector3.UP)
	var focus := from.lerp(at, 0.35)
	game.bike.place(Vector3(focus.x, game.world.terrain.height_at(focus.x, focus.z) + 40.0, focus.z), Vector3(0, 0, -1))
	game.world.set_focus(game.bike)
	game.world.streamer.load_all_pending()
	# the outer world streams round the camera: build its ribbons and wilderness now
	var outer: OuterWorld = game.world.outer
	if outer and outer.ok:
		outer.view.update_selection(from, (at - from).normalized())
		outer.roads.flush()
		outer.flora.flush()
	frame = 0


func _process(_d: float) -> void:
	frame += 1
	# frame time over the last 8 settle frames (wall clock between process calls)
	var now := Time.get_ticks_usec()
	if frame > settle - 8 and _t_last > 0:
		_t_acc += (now - _t_last) / 1000.0; _t_n += 1
	_t_last = now
	# keep the focus pinned (the bike would otherwise fall)
	var from: Vector3 = cams[idx][1]; var at: Vector3 = cams[idx][2]
	var focus := from.lerp(at, 0.35)
	game.bike.global_position = Vector3(focus.x, game.world.terrain.height_at(focus.x, focus.z) + 40.0, focus.z)
	if frame >= settle:
		var img := get_tree().root.get_texture().get_image()
		var p := "%s/%s.png" % [out, cams[idx][0]]
		img.save_png(p)
		print("saved ", p, "  draw calls %d, objects %d, primitives %d, frame %.0f ms" % [Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			_t_acc / maxf(_t_n, 1)])
		_t_acc = 0.0; _t_n = 0
		var outer: OuterWorld = game.world.outer
		if outer and outer.ok:
			print("  outer: terrain nodes %d, road tiles %d (max build %.1f ms), flora %s (max build %.1f ms)" % [outer.view.selected,
				outer.roads.loaded.size(), outer.roads.max_build_ms, outer.flora.stats(), outer.flora.max_build_ms])
		idx += 1
		if idx >= cams.size():
			get_tree().quit(); return
		_place()
