extends Node
## Render tool for the colony sim and the shipping lanes (Forward+, --facet):
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --audio-driver Dummy --rendering-driver vulkan \
##     -- --facet --test=colony_shots --out=/tmp/colony [--only=mayor,docked,estuary,district,construction]
## Builds a demo state - Puerto Alto chartered with a working fish/salt district, a shipyard, houses
## and a building under construction; a lane from the core harbour with a schooner docked at Puerto
## Alto and a coaster in the estuary - then captures the Mayor view (trade panel, lane drawn), the
## docked ship, the ship in the estuary and the production district with its porters.

var game: Game
var econ: ColonyEconomy
var out := "/tmp/colony_shots"
var cam: Camera3D
var only: PackedStringArray


func _ready() -> void:
	game = Game.current
	out = game.cli.get_string("out", out)
	only = game.cli.get_string("only", "").split(",", false)
	DirAccess.make_dir_recursive_absolute(out)
	get_window().size = Vector2i(1280, 720)
	call_deferred("run")


func want(name: String) -> bool:
	return only.is_empty() or name in only


func run() -> void:
	econ = game.colony.economy
	game.use_scripted_controls()
	game.hud._title_t = 0.0
	game.hud._title.hide()
	econ.ensure_shipping()
	game.gm.coins = 5000
	await _setup_colony()
	_setup_ships()
	cam = Camera3D.new(); cam.fov = 60.0; cam.far = 30000; cam.near = 0.1
	add_child(cam)
	_hide_ui(true)
	game.bike.visible = false; game.player.visible = false; game.truck.visible = false
	if want("district"): await shot_district()
	if want("docked"): await shot_docked()
	if want("estuary"): await shot_estuary()
	if want("mayor"):
		_hide_ui(false)
		await shot_mayor()
	print("COLONY SHOTS DONE")
	get_tree().quit()


func _hide_ui(hide: bool) -> void:
	game.hud.visible = not hide
	var ui := game.get_node_or_null("UI")
	if ui:
		for c in ui.get_children():
			if c is CanvasLayer and c != game.mayor: c.visible = not hide
	game.mayor.entry.visible = false


func _focus(p: Vector3) -> void:
	game.bike.global_position = Vector3(p.x, game.world.terrain.height_at(p.x, p.z) + 40.0, p.z)
	game.world.set_focus(game.bike)
	game.world.streamer.load_all_pending()


func _site(cid: String, type: String, near: Vector3, from: float, to: float) -> Variant:
	for r in range(int(from), int(to), 8):
		for k in range(32):
			var a := TAU * k / 32.0
			var p := near + Vector3(cos(a) * r, 0, sin(a) * r)
			var y: float = snappedf(atan2(near.x - p.x, near.z - p.z), PI * 0.5)
			if econ.check_site(cid, type, p, y) == "": return [p, y]
	return null


func _setup_colony() -> void:
	var t := econ.town("puerto_alto")
	var pz := game.world.database.location_pos(&"puerto_alto")
	_focus(pz)
	for i in range(2): await get_tree().physics_frame
	econ.discover("puerto_alto")
	var err := econ.found("puerto_alto")
	print("found: ", err if err != "" else "ok", " hall ", t.hall)
	for item in EconomyCatalog.ITEMS: t.stock[item] = 60
	t.stock["planks"] = 200; t.stock["blocks"] = 90; t.stock["tools"] = 30
	_focus(t.hall)
	for i in range(2): await get_tree().physics_frame
	var plan := ["fishing_hut", "smokehouse", "salt_pans", "warehouse", "cottage", "cottage", "quarry", "mason", "shipyard", "townhouse", "fishing_hut"]
	for type in plan:
		var s: Variant = _site("puerto_alto", type, t.hall, 16.0, 300.0)
		if s == null:
			print("no site for ", type); continue
		var e := econ.place("puerto_alto", type, s[0], s[1])
		print("placed %s at %s: %s" % [type, s[0], e if e != "" else "ok"])
	# all but the last finished; the last stays a scaffold
	for i in range(t.buildings.size() - 1):
		t.buildings[i].built = true; t.buildings[i].progress = 1.0
	if t.buildings.size() > 1: t.buildings[-1].progress = 0.62
	for i in range(14): t.add_colonist(5000 + i)
	t.assign()
	for i in range(900): econ.tick(0.25)
	for i in range(40): econ.tick(0.25)


var lane: Dictionary
var docked: Dictionary
var sailing: Dictionary


func _setup_ships() -> void:
	var sh := econ.shipping
	lane = econ.add_lane("core", "puerto_alto", {"olive": 40, "wine": 10}, {"fish": 30, "preserved_fish": 20})
	docked = sh.add_ship("schooner", "puerto_alto")
	docked.state = "docked"; docked.port = "puerto_alto"; docked.lane = lane.id; docked.timer = 1e5
	docked.cargo = {"fish": 30, "preserved_fish": 20}
	lane.ships.append(docked.id)
	sailing = sh.add_ship("coaster", "core")
	sailing.state = "sailing"; sailing.lane = lane.id; sailing.leg = 0; sailing.port = "core"
	sailing.cargo = {"olive": 40}
	lane.ships.append(sailing.id)
	var r := sh.route("core", "puerto_alto")
	var pts: PackedVector2Array = r.points
	for k in range(pts.size()):
		if pts[k].x > 3200.0:
			sailing.s = float(r.cum[k]); break
	econ.set_process(false)          # hold the scene still between shots


## Settle: at least `frames` frames, and until the colony's buildings and people are built.
func _capture(name: String, frames := 30) -> void:
	# software rendering runs seconds a frame: build what the views would build over many frames now
	var v := econ.views
	var at := v.viewer()
	v._sync_buildings(at)
	while not v._queue.is_empty(): v._build_next()
	v._plan_people(at); v._sync_ships(at)
	for i in range(mini(frames, 8)): await get_tree().process_frame
	for i in range(240):
		var pending := not v._queue.is_empty()
		for id in v.people:
			var m: RiderModel = v.people[id].model
			if m.is_person() and m.is_processing(): pending = true
		if not pending: break
		await get_tree().process_frame
	for i in range(6): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [out, name])
	print("saved %s/%s.png  draw calls %d" % [out, name, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])


func _look(from: Vector3, at: Vector3) -> void:
	cam.current = true
	game.world.terrain.set_view_camera(cam)
	cam.look_at_from_position(from, at, Vector3.UP)
	var outer: OuterWorld = game.world.outer
	if outer and outer.ok:
		outer.view.update_selection(from, (at - from).normalized())
		outer.roads.flush()
		outer.flora.flush()


func shot_mayor() -> void:
	var t := econ.town("puerto_alto")
	game.rider._set_mode(Rider.Mode.ON_FOOT)
	var p := t.hall + Vector3(0, 1, 0)
	game.player.place(p, Vector3.FORWARD)
	game.world.set_focus(game.player)
	game.world.outer.refresh_collision()
	for i in range(24): await get_tree().physics_frame
	game.mayor.set_active(true)
	if not game.mayor.active:
		push_error("mayor view did not open"); return
	game.mayor.select_colony("puerto_alto", true)
	game.mayor.current_page = "Trade"; game.mayor.build_page()
	game.mayor.inspect(t.buildings[1].id)
	game.mayor.center = t.hall.lerp(Vector3(6400, 0, 1150), 0.45)
	game.mayor.zoom = 2200.0
	game.mayor.yaw = -0.35
	game.mayor.update_camera()
	game.mayor.show_note("Lane Villa Rosa - Puerto Alto created. Assign a ship in the fleet list.")
	await _capture("mayor_trade", 40)
	game.mayor.current_page = "Colony"; game.mayor.build_page()
	game.mayor.center = t.hall; game.mayor.zoom = 260.0; game.mayor.update_camera()
	await _capture("mayor_colony", 40)
	game.mayor.current_page = "Build"; game.mayor.build_page()
	game.mayor.set_tool("place:smokehouse")
	var s: Variant = _site("puerto_alto", "smokehouse", t.hall, 30.0, 300.0)
	if s != null: game.mayor._update_ghost(s[0])
	await _capture("mayor_build", 30)
	game.mayor.set_tool("Select")
	game.mayor.set_active(false)
	for i in range(5): await get_tree().process_frame


func shot_docked() -> void:
	var sh := econ.shipping
	var port: Dictionary = sh.ports.puerto_alto
	var moor: Vector2 = port.moor; var along: Vector2 = port.along
	var out_dir := Vector2(sin(port.heading), cos(port.heading))
	var at := Vector3(moor.x, 3.0, moor.y)
	_focus(at)
	var from := at + Vector3(along.x, 0, along.y) * 34.0 + Vector3(out_dir.x, 0, out_dir.y) * 30.0 + Vector3(0, 11, 0)
	_look(from, at + Vector3(0, 3, 0))
	await _capture("ship_docked_puerto_alto")
	# the other side, the schooner against the town
	var from2 := at - Vector3(along.x, 0, along.y) * 30.0 + Vector3(out_dir.x, 0, out_dir.y) * 26.0 + Vector3(0, 8, 0)
	_look(from2, at + Vector3(0, 5, 0))
	await _capture("ship_docked_puerto_alto_2")


func shot_estuary() -> void:
	var v := econ.views
	var xf := v.ship_transform(sailing)
	var p: Vector3 = xf[0]
	var yaw: float = xf[1]
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var side := fwd.cross(Vector3.UP)
	_focus(p)
	var from := p + side * 55.0 - fwd * 45.0 + Vector3(0, 16, 0)
	_look(from, p + fwd * 10.0 + Vector3(0, 4, 0))
	await _capture("ship_estuary", 30)
	var high := p + side * 260.0 - fwd * 300.0 + Vector3(0, 170, 0)
	_look(high, p + fwd * 200.0)
	await _capture("ship_estuary_wide", 30)


func shot_district() -> void:
	var t := econ.town("puerto_alto")
	var centre := Vector3.ZERO; var n := 0
	for b in t.buildings:
		centre += Vector3(float(b.x), float(b.y), float(b.z)); n += 1
	centre /= maxf(n, 1)
	var hut := t.building_of_type("smokehouse")
	var target: Vector3 = Vector3(float(hut.x), float(hut.y), float(hut.z)) if not hut.is_empty() else centre
	_focus(target)
	econ.set_process(true)
	for i in range(4): await get_tree().process_frame
	var dir := (centre - target); dir.y = 0
	dir = dir.normalized() if dir.length() > 1.0 else Vector3(1, 0, 0)
	var from := target - dir * 34.0 + dir.cross(Vector3.UP) * 18.0 + Vector3(0, 13, 0)
	_look(from, target + dir * 12.0)
	await _capture("colony_district", 40)
	var high := centre + Vector3(70, 90, 90)
	_look(high, centre)
	await _capture("colony_district_aerial", 30)
	# the scaffold
	var last: Dictionary = t.buildings[-1]
	if not last.built:
		var bp := Vector3(float(last.x), float(last.y), float(last.z))
		_look(bp + Vector3(20, 10, 18), bp + Vector3(0, 3, 0))
		await _capture("colony_construction", 30)
