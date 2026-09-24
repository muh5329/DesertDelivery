extends Node
## Renders of the outer towns' life (townsfolk, traffic, boats, the new-look bandits):
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --audio-driver Dummy --rendering-driver vulkan \
##     -- --facet --test=town_life_view --out=/tmp/life [--only=puerto_main,isola_harbour] [--settle=40]
## Each scene places the camera AND the focus in town, generates the town and runs its routines
## for an hour before the shot (so people are mid-walk as in play), waits for every body's
## meshes, then lets it settle. It prints draw calls and frame time per shot; the busy Puerto
## Alto street is shot twice (life off / on) for the before / after numbers.

var out := "/tmp/life"
var game: Game
var cam: Camera3D
var settle := 36
var scenes: Array = []
var idx := 0
var frame := 0
var _t_last := 0
var _t_acc := 0.0
var _t_n := 0
var _prep_done := false


func _ready() -> void:
	game = Game.current
	out = game.cli.get_string("out", out)
	settle = game.cli.get_int("settle", settle)
	DirAccess.make_dir_recursive_absolute(out)
	game.hud.visible = false
	var ui := game.get_node_or_null("UI")
	if ui:
		for c in ui.get_children():
			if c is CanvasLayer or c is Control: c.visible = false
	game.bike.visible = false; game.player.visible = false; game.truck.visible = false
	cam = Camera3D.new(); cam.fov = game.cli.get_float("fov", 58.0); cam.far = 30000; cam.near = 0.1
	add_child(cam); cam.current = true
	game.world.terrain.set_view_camera(cam)
	var t: Terrain = game.world.terrain
	var plan: Dictionary = game.world.outer.plan()
	var towns := {}
	for tt in plan.towns: towns[tt.id] = tt
	var main_pts: Array = _street(towns.puerto_alto, "main").points
	var a: Array = main_pts[14]; var b: Array = main_pts[4]
	scenes = [
		{"name": "puerto_main_off", "town": "puerto_alto", "from": _v(t, a[0], "g1.75", a[2]), "at": _v(t, b[0], "g1.4", b[2]), "life": false},
		{"name": "puerto_main", "town": "puerto_alto", "from": _v(t, a[0], "g1.75", a[2]), "at": _v(t, b[0], "g1.4", b[2])},
		{"name": "puerto_plaza", "town": "puerto_alto", "from": _v(t, 7752.0, "g2.2", 1622.0), "at": _v(t, 7790.0, "g1.0", 1596.0)},
		{"name": "sarmada_souk", "town": "sarmada", "from": _v(t, 2706.5, "g1.75", 8569.0), "at": _v(t, 2720.0, "g1.1", 8584.0)},
		{"name": "isola_harbour", "town": "isola_serena", "from": _v(t, -8648.0, "g2.6", 2273.0), "at": _v(t, -8716.0, "0.8", 2300.0), "boats": "isola_serena"},
		{"name": "campo_plaza", "town": "campo_real", "from": _v(t, 5617.0, "g1.75", -2241.0), "at": _v(t, 5600.0, "g1.0", -2229.0)},
		{"name": "valdoro_plaza", "town": "valdoro", "from": _v(t, -1566.0, "g2.2", -5226.0), "at": _v(t, -1600.0, "g1.0", -5232.0)},
		{"name": "highway", "traffic": Vector3(5099.95, 52.66, -344.88), "from": Vector3.ZERO, "at": Vector3.ZERO},
		{"name": "bandit_camp", "camp": &"camp.bandit.0", "from": Vector3.ZERO, "at": Vector3.ZERO},
		{"name": "pirate_cove", "camp": &"camp.pirate.0", "from": Vector3.ZERO, "at": Vector3.ZERO},
		{"name": "bandit_close", "camp": &"camp.bandit.0", "close": true, "from": Vector3.ZERO, "at": Vector3.ZERO},
		{"name": "pirate_close", "camp": &"camp.pirate.0", "close": true, "from": Vector3.ZERO, "at": Vector3.ZERO},
		{"name": "lineup", "lineup": 7.5, "from": Vector3.ZERO, "at": Vector3.ZERO},
		{"name": "lineup_50m", "lineup": 50.0, "from": Vector3.ZERO, "at": Vector3.ZERO},
	]
	var only := game.cli.get_string("only", "")
	if only != "":
		var keep := only.split(",")
		scenes = scenes.filter(func(s): return String(s.name) in keep)
	if scenes.is_empty(): get_tree().quit(); return
	_place()


func _street(t: Dictionary, kind: String) -> Dictionary:
	for s in t.streets:
		if s.kind == kind: return s
	return {}


func _v(t: Terrain, x: float, ys: String, z: float) -> Vector3:
	var y := t.height_at(x, z) + float(ys.substr(1)) if ys.begins_with("g") else float(ys)
	return Vector3(x, y, z)


func _place() -> void:
	var s: Dictionary = scenes[idx]
	var life: IslandLife = game.life
	var tf: TownFolk = life.outer.towns
	frame = 0; _prep_done = false
	tf.enabled = s.get("life", true)
	if not tf.enabled:
		for b: TownBody in tf.bodies: b.release()
	if s.has("traffic"):
		_traffic_scene(s)
	elif s.has("camp"):
		_camp_scene(s)
	elif s.has("lineup"):
		_lineup_scene(s)
	cam.look_at_from_position(s.from, s.at, Vector3.UP)
	cam.fov = float(s.get("fov", game.cli.get_float("fov", 58.0)))
	_pin_focus()
	game.world.streamer.load_all_pending()
	var outer: OuterWorld = game.world.outer
	outer.view.update_selection(s.from, (s.at - s.from).normalized())
	outer.roads.flush(); outer.flora.flush()
	outer.focus = game.bike
	outer.refresh_collision()
	if s.has("town") and tf.enabled:
		tf.prepare_now(s.town)
		var now := floorf(life.total_minutes / 1440.0) * 1440.0 + 630.0     # 10:30
		tf.simulate(s.town, now - 70.0, now)
		tf._viewer = s.from
		for pass_ in 30:
			tf._select_views()
			if not tf._pending_views: break
		tf._select_views()
		PersonBuilder.wait_parts(); PersonBuilder.poll_parts()
		print("  town %s: %d people, %d bodies (%d near-eligible), active %s" % [s.town, (tf.towns[s.town] as TownPopulation).people.size(),
			tf.bodies_in_use(), mini(tf.viewed.size(), TownFolk.MAX_NEAR), tf.active_ids()])
	if s.has("boats"):
		var hb := life.outer.boats.prepare_now(s.boats)
		print("  harbour %s: %d moorings, routes %s" % [s.boats, (hb.get("slots", []) as Array).size(), (hb.get("routes", []) as Array).map(func(r): return (r as PackedVector3Array).size())])


func _pin_focus() -> void:
	var s: Dictionary = scenes[idx]
	var focus: Vector3 = s.get("pin", (s.from as Vector3).lerp(s.at, 0.35))
	game.bike.global_position = Vector3(focus.x, game.world.terrain.height_at(focus.x, focus.z) + 40.0, focus.z)
	game.world.set_focus(game.bike)


func _traffic_scene(s: Dictionary) -> void:
	var tr: OuterTraffic = game.life.outer.traffic
	var c: Vector3 = s.traffic
	var nodes := tr.nodes_near(c, 0.0, 260.0).filter(func(n): return tr.class_of(n) == "highway")
	nodes.sort_custom(func(a, b): return tr.nav.graph.get_point_position(a).distance_to(c) < tr.nav.graph.get_point_position(b).distance_to(c))
	var centre: Vector3 = tr.nav.graph.get_point_position(nodes[0]) if not nodes.is_empty() else c
	var kinds := ["car", "lorry", "car", "bus", "car", "car", "lorry", "car"]
	var k := 0
	for n in nodes:
		if k >= kinds.size(): break
		if tr._free_at(tr.nav.graph.get_point_position(n), 28.0):
			var rec := tr.spawn_one(n, kinds[k], k % tr.dests.size())
			if not rec.is_empty(): k += 1
	var rural := tr.nodes_near(c, 0.0, 900.0).filter(func(n): return tr.class_of(n) in ["road", "track"])
	for i in mini(3, rural.size()):
		tr.spawn_one(rural[i * 7 % rural.size()], ["tractor", "cart", "car"][i], -1)
	var side := Vector3(1, 0, 0)
	if nodes.size() > 2:
		var d := tr.nav.graph.get_point_position(nodes[2]) - tr.nav.graph.get_point_position(nodes[0]); d.y = 0
		side = d.normalized().cross(Vector3.UP)
	s.from = centre + side * 15.0 + Vector3(0, 4.5, 0) - (side.cross(Vector3.UP)) * 24.0
	s.at = centre + Vector3(0, 1.0, 0) + (side.cross(Vector3.UP)) * 10.0
	print("  traffic: %d vehicles spawned" % tr.count())
	tr.set_physics_process(false)          # frozen while the frame settles (software rendering is slow)


func _camp_scene(s: Dictionary) -> void:
	var enc: EncounterDirector = game.encounters
	var c: Dictionary = enc.camp(s.camp)
	if c.is_empty():
		for id in enc.camps:
			if String(id).begins_with(String(s.camp).get_slice(".", 0) + "." + String(s.camp).get_slice(".", 1)): c = enc.camps[id]; s.camp = id; break
	var pos: Vector3 = c.pos
	enc.spawn_camp(s.camp)
	var facing: Vector3 = c.get("facing", Vector3.FORWARD)
	s.from = pos + facing.normalized() * 15.0 + facing.normalized().cross(Vector3.UP) * 4.0 + Vector3(0, 3.6, 0)
	s.at = pos + Vector3(0, 0.8, 0)
	# the courier far behind the camera, out of their sight (the camp stays: it is within 320 m)
	s.pin = pos + facing.normalized() * 200.0
	var men: Array = enc.enemies_of(s.camp)
	if s.get("close", false) and not men.is_empty():
		# up close, from wherever a man can be seen clearly: faces, hats, bandanas, headscarves
		var space := get_viewport().world_3d.direct_space_state
		var found := false
		for e: Node3D in men:
			var f := -e.global_basis.z; f.y = 0; f = f.normalized()
			for turn in [0.0, 0.5, -0.5, 1.0, -1.0, 1.6, -1.6]:
				var d := f.rotated(Vector3.UP, turn)
				var head := e.global_position + Vector3(0, 1.45, 0)
				var eye := e.global_position + d * 2.7 + Vector3(0, 1.6, 0)
				var q := PhysicsRayQueryParameters3D.create(eye, head, 1)
				var q2 := PhysicsRayQueryParameters3D.create(eye, e.global_position + Vector3(0, 0.5, 0), 1)
				if space.intersect_ray(q).is_empty() and space.intersect_ray(q2).is_empty():
					s.from = eye; s.at = e.global_position + Vector3(0, 1.2, 0); found = true; break
			if found: break
	elif s.has("far") and not men.is_empty():
		# at range, from the first direction with a clear line to the camp
		var space := get_viewport().world_3d.direct_space_state
		s.from = pos + facing.normalized() * float(s.far) + Vector3(0, 1.8, 0)
		s.at = pos + Vector3(0, 1.0, 0)
		for k in 16:
			var d := facing.normalized().rotated(Vector3.UP, TAU * k / 16.0)
			var eye := pos + d * float(s.far)
			eye.y = game.world.terrain.height_at(eye.x, eye.z) + 1.8
			var q := PhysicsRayQueryParameters3D.create(eye, pos + Vector3(0, 1.2, 0), 1)
			if space.intersect_ray(q).is_empty() and game.world.terrain.height_at(eye.x, eye.z) > 0.5:
				s.from = eye; break
	if not s.get("close", false):
		for e in men:
			if e.has_method("set_physics_process"): e.set_physics_process(false)
	print("  camp %s: %d men" % [s.camp, men.size()])


## Bandits and pirates side by side on the open salt flats (combat_view's squad lineup), seen
## from `lineup` metres: outfits and guns up close, readable silhouettes at range.
func _lineup_scene(s: Dictionary) -> void:
	var enc: EncounterDirector = game.encounters
	var t: Terrain = game.world.terrain
	var s0: Vector3 = game.world.database.location_pos(&"salinas") + Vector3(40, 0, -30)
	for id in [&"camp.view.bandits", &"camp.view.pirates"]:
		if enc.camps.has(id): enc.remove_camp(id)
	enc.add_camp(&"camp.view.bandits", &"bandit", Vector3(s0.x - 3.2, t.height_at(s0.x - 3.2, s0.z), s0.z), Vector3(0, 0, 1), 4, &"squad")
	enc.add_camp(&"camp.view.pirates", &"pirate", Vector3(s0.x + 6.2, t.height_at(s0.x + 6.2, s0.z), s0.z), Vector3(0, 0, 1), 4, &"squad")
	enc.spawn_camp(&"camp.view.bandits"); enc.spawn_camp(&"camp.view.pirates")
	var c := Vector3(s0.x + 1.5, t.height_at(s0.x + 1.5, s0.z), s0.z)
	var d := float(s.lineup)
	s.from = Vector3(c.x, t.height_at(c.x, c.z + d) + 1.6, c.z + d)
	s.at = c + Vector3(0, 1.0 if d < 20.0 else 0.9, 0)
	if d >= 20.0:
		# the first bearing (they face +z) from which the ground does not hide them
		for k in 12:
			var dir := Vector3(0, 0, 1).rotated(Vector3.UP, (k / 2 + 1) * 0.35 * (1 if k % 2 == 0 else -1) if k > 0 else 0.0)
			var eye := c + dir * d
			eye.y = t.height_at(eye.x, eye.z) + 1.7
			var clear := true
			for j in range(1, 20):
				var q: Vector3 = eye.lerp(s.at, j / 20.0)
				if t.height_at(q.x, q.z) > q.y - 0.4: clear = false; break
			if clear: s.from = eye; break
	s.pin = c + Vector3(0, 0, 110.0)
	s.fov = 50.0 if d < 20.0 else 58.0


func _process(_d: float) -> void:
	frame += 1
	var now := Time.get_ticks_usec()
	if frame > settle - 8 and _t_last > 0:
		_t_acc += (now - _t_last) / 1000.0; _t_n += 1
	_t_last = now
	_pin_focus()
	if frame == 3:
		var s: Dictionary = scenes[idx]
		if s.has("camp") and not s.get("close", false):
			for e in game.encounters.enemies_of(s.camp): e.set_physics_process(true)
	if frame == settle - 5:
		# the last frames drive (wheels turn); the drivers' and fishers' meshes are in
		PersonBuilder.wait_parts(); PersonBuilder.poll_parts()
		game.life.outer.traffic.set_physics_process(true)
	if frame >= settle:
		var s: Dictionary = scenes[idx]
		var img := get_tree().root.get_texture().get_image()
		var p := "%s/%s.png" % [out, s.name]
		img.save_png(p)
		var tf: TownFolk = game.life.outer.towns
		print("saved %s  draw calls %d, objects %d, primitives %d, frame %.0f ms, townfolk %d bodies (%d near) %.2f ms (max %.2f), traffic %d (%.2f ms)" % [p,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), _t_acc / maxf(_t_n, 1), tf.bodies_in_use(), tf.near_in_use(),
			tf.frame_us / 1000.0, tf.frame_us_max / 1000.0, game.life.outer.traffic.count(), game.life.outer.traffic.frame_us / 1000.0])
		_t_acc = 0.0; _t_n = 0
		tf.frame_us_max = 0
		idx += 1
		if idx >= scenes.size():
			get_tree().quit(); return
		_place()
