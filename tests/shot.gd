extends Node
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


func _ready() -> void:
	game = Game.current
	out = game.cli.get_string("out", out)
	settle = game.cli.get_int("settle", 24)
	DirAccess.make_dir_recursive_absolute(out)
	if not "--hud" in OS.get_cmdline_user_args(): game.hud.visible = false
	if not "--player" in OS.get_cmdline_user_args():
		game.bike.visible = false; game.player.visible = false; game.truck.visible = false
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
	frame = 0


func _process(_d: float) -> void:
	frame += 1
	# keep the focus pinned (the bike would otherwise fall)
	var from: Vector3 = cams[idx][1]; var at: Vector3 = cams[idx][2]
	var focus := from.lerp(at, 0.35)
	game.bike.global_position = Vector3(focus.x, game.world.terrain.height_at(focus.x, focus.z) + 40.0, focus.z)
	if frame >= settle:
		var img := get_tree().root.get_texture().get_image()
		var p := "%s/%s.png" % [out, cams[idx][0]]
		img.save_png(p)
		print("saved ", p)
		idx += 1
		if idx >= cams.size():
			get_tree().quit(); return
		_place()
