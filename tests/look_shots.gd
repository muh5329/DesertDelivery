extends Node
## Render tool for the lighting work (M-12, m-6, m-7): review_shots with the hour per view and a
## parked bike. One boot renders every view.
## Usage:
##   godot --path . -- --facet --test=look_shots --out=DIR --size=1280x720 --cams="name@hour:fx,fy,fz:ax,ay,az[:bike];..."
##   A coordinate prefixed with "g" is ground relative ("g2" = 2 m above the ground). "@hour" pins
##   the clock for that view (DayNight.pin_hour); ":bike" parks the courier's bike, rider on, on the
##   road nearest the camera's target, facing away from the camera (its headlight shows at night);
##   ":traffic" (or ":bike+traffic") puts outer traffic on the roads in front of the camera a few
##   frames before the shot; ":focusat" streams the world round the target instead of 35 % of the
##   way to it (the same view with the detailed and the far buildings swapped, m-6).
##   --settle=N frames per view (default 40), --quality=low|medium|high|ultra.

var out := "/tmp/shots"
var frame := 0
var cams: Array = []
var idx := 0
var cam: Camera3D
var settle := 40
var game: Game


func _ready() -> void:
	game = Game.current
	out = game.cli.get_string("out", out)
	var sz := game.cli.get_string("size", "")
	if sz != "":
		var wh := sz.split("x")
		get_window().size = Vector2i(int(wh[0]), int(wh[1]))
	settle = game.cli.get_int("settle", 40)
	if game.cli.get_string("lod-window-gain", "") != "":
		ArchMaterials.lod().set_shader_parameter("window_gain", game.cli.get_float("lod-window-gain", 1.0))
	DirAccess.make_dir_recursive_absolute(out)
	game.hud.visible = false
	var ui := game.get_node_or_null("UI")
	if ui:
		for c in ui.get_children():
			if c is CanvasLayer or c is Control: c.visible = false
	game.player.visible = false; game.jeep.visible = false; game.cart.visible = false
	game.encounters.ambush_enabled = false
	game.use_scripted_controls()
	var t: Terrain = game.world.terrain
	for entry in game.cli.get_string("cams", "").split(";", false):
		var parts := entry.split(":")
		if parts.size() < 3: push_error("bad cam " + entry); continue
		var nm := parts[0]; var hour := -1.0
		if "@" in nm:
			hour = float(nm.get_slice("@", 1)); nm = nm.get_slice("@", 0)
		var flags: PackedStringArray = parts[3].split("+") if parts.size() > 3 else PackedStringArray()
		cams.append([nm, _vec(parts[1], t), _vec(parts[2], t), hour, "bike" in flags, "traffic" in flags, 1.0 if "focusat" in flags else 0.35])
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
	var hour: float = cams[idx][3]
	if hour >= 0.0 and game.world.day_night: game.world.day_night.pin_hour(hour)
	cam.look_at_from_position(from, at, Vector3.UP)
	var with_bike: bool = cams[idx][4]
	game.bike.visible = with_bike
	if with_bike:
		var road := game.world.terrain.nearest_road(at)
		var fwd: Vector3 = road.tangent; fwd.y = 0.0; fwd = fwd.normalized()
		if fwd.dot(at - from) < 0.0: fwd = -fwd
		game.bike.place(road.point + Vector3(0, 0.2, 0), fwd)
	else:
		var focus := from.lerp(at, cams[idx][6])
		game.bike.place(Vector3(focus.x, game.world.terrain.height_at(focus.x, focus.z) + 40.0, focus.z), Vector3(0, 0, -1))
	game.bike.set_physics_process(false)
	game.world.set_focus(game.bike)
	game.world.streamer.load_all_pending()
	var outer: OuterWorld = game.world.outer
	if outer and outer.ok:
		outer.view.update_selection(from, (at - from).normalized())
		outer.roads.flush()
		outer.flora.flush()
	frame = 0


func _process(_d: float) -> void:
	frame += 1
	var from: Vector3 = cams[idx][1]; var at: Vector3 = cams[idx][2]
	if not cams[idx][4]:
		var focus := from.lerp(at, cams[idx][6])
		game.bike.global_position = Vector3(focus.x, game.world.terrain.height_at(focus.x, focus.z) + 40.0, focus.z)
	if cams[idx][5] and frame == maxi(settle - 4, 1): _spawn_traffic(from, at)
	if frame >= settle:
		var img := get_tree().root.get_texture().get_image()
		var p := "%s/%s.png" % [out, cams[idx][0]]
		img.save_png(p)
		var dn := game.world.day_night
		print("saved ", p, "  hour %.2f sun %.1f deg, night %.2f, lamps %.2f, lamp lights %d, draw calls %d" % [dn.hour, dn.sun_elevation, dn.night, dn.lamps,
			dn.lights.active(), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
		idx += 1
		if idx >= cams.size():
			get_tree().quit(); return
		_place()


## A few vehicles on the outer roads between 25 and 160 m in front of the camera.
func _spawn_traffic(from: Vector3, at: Vector3) -> void:
	var traffic := game.world.get_node_or_null("IslandLife/OuterLife/OuterTraffic")
	if traffic == null: return
	var dir := (at - from); dir.y = 0.0; dir = dir.normalized()
	var used := {}
	var n := 0
	for dist: float in [28.0, 45.0, 65.0, 90.0, 120.0, 160.0]:
		var p := from + dir * dist
		var ids: Array = traffic.nodes_near(p, 0.0, 30.0)
		for id: int in ids:
			if used.has(id): continue
			used[id] = true
			var rec: Dictionary = traffic.spawn_one(id)
			if not rec.is_empty(): n += 1
			break
	print("traffic: spawned %d in view" % n)
