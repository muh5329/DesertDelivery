extends Node
## FIXPLAY RENDER TOOL: the UI at a given window size (Forward+, --facet) after the fixplay pass.
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --audio-driver Dummy --rendering-driver vulkan \
##     -- --facet --test=fixplay_ui --out=DIR --size=1280x720
## Captures: the HUD in a fight, riding on a low tank past a highway service stop (fuel gauge,
## warning, nearest pump), a town station's fuel & ticket window, the courier counter, the Mayor
## view's Colony / Build / Trade pages (road haulage, named coves), and the journal.

var game: Game
var econ: ColonyEconomy
var out := "/tmp/fixplay_ui"
var tag := ""
var parts := ""


## --parts=fight,counter,fuel,station,mayor,journal (default: all). Each area costs llvmpipe
## memory, so the shots can be taken in a few runs.
func _want(part: String) -> bool:
	return parts == "" or part in parts.split(",")


func _ready() -> void:
	game = Game.current
	out = game.cli.get_string("out", out)
	DirAccess.make_dir_recursive_absolute(out)
	parts = game.cli.get_string("parts", "")
	var sz := game.cli.get_string("size", "1600x900")
	tag = sz
	var wh := sz.split("x")
	get_window().size = Vector2i(int(wh[0]), int(wh[1]))
	call_deferred("run")


func _snap(name: String, frames := 20) -> void:
	for i in range(frames): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var p := "%s/%s_%s.png" % [out, name, tag]
	img.save_png(p)
	print("saved ", p, " ", img.get_size())


func run() -> void:
	econ = game.colony.economy
	var sc := game.use_scripted_controls()
	game.hud._title_t = 0.0
	game.hud._title.hide()
	econ.ensure_shipping()
	econ.shipping.wait()
	game.gm.coins = 5000
	var sv: RoadServices = game.journey.services
	var t := econ.town("puerto_alto")
	# ---------------------------------------------------------------- the HUD in a fight
	if _want("fight"):
		game.rider.request_dismount()
		var s: Vector3 = game.world.database.location_pos(&"salinas")
		var at := Vector3(s.x + 30.0, 0, s.z - 25.0); at.y = game.world.terrain.height_at(at.x, at.z) + 0.1
		game.player.place(at, Vector3(0, 0, -1))
		game.world.set_focus(game.player)
		game.cam.snap_to_target()
		game.world.streamer.load_all_pending()
		var cpos := Vector3(at.x + 6.0, 0, at.z - 45.0); cpos.y = game.world.terrain.height_at(cpos.x, cpos.z)
		game.encounters.ambush_enabled = false
		game.encounters.add_camp(&"camp.review.ui", &"bandit", cpos, Vector3(0, 0, 1), 5, &"")
		game.encounters.spawn_camp(&"camp.review.ui")
		sc.intent.aim = true
		for i in range(40): await get_tree().physics_frame
		var d: Vector3 = cpos + Vector3(0, 1.4, 0) - game.cam.global_position
		game.cam.set_look(atan2(-d.x, -d.z), -atan2(d.y, Vector2(d.x, d.z).length()))
		game.vitals.hit(35.0, at + Vector3(-20, 1, -10), &"test")
		game.vitals.hit(40.0, at + Vector3(15, 1, 5), &"test")
		game.gun.ammo = 3
		sc.press("fire")
		await _snap("hud_fight", 12)
		sc.intent.aim = false
		game.encounters.remove_camp(&"camp.review.ui")
		game.vitals.health.reset()
	# ---------------------------------------------------------------- the courier counter
	if _want("counter"):
		var home := game.world.database.location_pos(&"villa_rosa_office")
		game.bike.place(home + Vector3(3, 0.3, 0), Vector3.FORWARD)
		game.player.place(home + Vector3(0, 0.3, 1.5), Vector3.FORWARD)
		game.world.set_focus(game.player)
		game.world.streamer.load_all_pending()
		game.cam.snap_to_target()
		for i in range(40): await get_tree().physics_frame
		game.journey.open_counter()
		await _snap("counter", 20)
		game.journey.close_counter()
		for i in range(5): await get_tree().process_frame
	# ---------------------------------------------------------------- riding on a low tank
	if _want("fuel"):
		# one area at a time (llvmpipe keeps every texture it has seen): the stop on the ring road
		# into Puerto Alto, the town's own station, then the Mayor view over Puerto Alto
		var stop: Dictionary = sv.by_id.get("station.ring.campo_real.puerto_alto.0", {})
		if stop.is_empty():
			for st in sv.stations:
				if st.kind == "highway": stop = st; break
		var road_pts: PackedVector3Array = game.world.outer.roads.roads[game.world.outer.roads.by_id[stop.road]].pts
		var k0: int = maxi(0, int(stop.k) - 45)
		var p0: Vector3 = road_pts[k0]
		var fwd0: Vector3 = (road_pts[k0 + 3] - p0); fwd0.y = 0.0; fwd0 = fwd0.normalized()
		game.rider.request_mount()
		for i in range(10): await get_tree().physics_frame
		game.rider.respawn_at(p0, fwd0)
		game.world.set_focus(game.rider.courier())
		game.world.outer.refresh_collision()
		game.world.streamer.load_all_pending()
		game.journey.fuel_ratio = 0.08
		game.journey._warned = -1
		for i in range(90): await get_tree().physics_frame
		game.bike.odometer += 5.0
		await _snap("hud_low_fuel", 40)
	# ---------------------------------------------------------------- a town station
	if _want("station"):
		var vs: Dictionary = sv.by_id["station.puerto_alto"]
		game.rider.respawn_at(vs.pos - (vs.out as Vector3) * 2.0, vs.forward)
		game.world.set_focus(game.rider.courier())
		game.world.outer.refresh_collision()
		game.world.streamer.load_all_pending()
		for i in range(90): await get_tree().physics_frame
		game.journey.fuel_ratio = 0.35
		await _snap("station_outside", 30)
		game.journey.open_counter()
		await _snap("station_window", 20)
		game.journey.station_panel.close_panel()
		for i in range(5): await get_tree().process_frame
	# ---------------------------------------------------------------- a colony to look at
	if _want("mayor"):
		game.rider.request_dismount()
		for i in range(10): await get_tree().physics_frame
		var pz := game.world.database.location_pos(&"puerto_alto")
		game.bike.global_position = Vector3(pz.x, game.world.terrain.height_at(pz.x, pz.z) + 40.0, pz.z)
		game.world.set_focus(game.bike)
		game.world.streamer.load_all_pending()
		for i in range(2): await get_tree().physics_frame
		econ.discover("puerto_alto")
		print("found: ", econ.found("puerto_alto"))
		for item in EconomyCatalog.ITEMS: t.stock[item] = 60
		t.stock["planks"] = 200; t.stock["blocks"] = 90; t.stock["tools"] = 30
		for type in ["fishing_hut", "salt_pans", "smokehouse", "cottage", "cottage", "warehouse", "shipyard"]:
			var site: Variant = _site("puerto_alto", type, t.hall)
			if site != null: print(type, ": ", econ.place("puerto_alto", type, site[0], site[1]))
		for b in t.buildings: b.built = true; b.progress = 1.0
		for i in range(10): t.add_colonist(7000 + i)
		t.assign()
		for i in range(400): econ.tick(0.25)
		var lane := econ.add_lane("core", "puerto_alto", {"olive": 40}, {"fish": 30})
		var ship := econ.shipping.add_ship("coaster", "puerto_alto")
		if not ship.is_empty() and not lane.is_empty(): econ.shipping.assign(ship.id, lane.id)
		for i in range(200): econ.tick(0.5)
		econ.discover("valdoro")
		var err_v := econ.found("valdoro")
		print("valdoro: ", err_v)
		econ.town("valdoro").stock["planks"] = 40; econ.town("valdoro").stock["ore"] = 40
		print("carter: ", econ.add_road_route("valdoro", "puerto_alto", {"ore": 20}, {"fish": 20}))
		for i in range(60): econ.tick(0.5)
	# ---------------------------------------------------------------- the Mayor view
	if _want("mayor"):
		game.rider._set_mode(Rider.Mode.ON_FOOT)
		game.player.place(t.hall + Vector3(0, 1, 0), Vector3.FORWARD)
		game.world.set_focus(game.player)
		game.world.outer.refresh_collision()
		for i in range(60): await get_tree().physics_frame
		game.mayor.set_active(true)
		game.mayor.select_colony("puerto_alto", false)
		game.mayor.current_page = "Colony"; game.mayor.build_page()
		game.mayor.center = t.hall; game.mayor.zoom = 300.0; game.mayor.update_camera()
		await _snap("mayor_colony", 40)
		game.mayor.current_page = "Build"; game.mayor.build_page()
		game.mayor.set_tool("place:smokehouse")
		var gs: Variant = _site("puerto_alto", "smokehouse", t.hall)
		if gs != null: game.mayor._update_ghost(gs[0])
		await _snap("mayor_build", 30)
		game.mayor.set_tool("Select")
		game.mayor.current_page = "Trade"; game.mayor.build_page()
		if t.buildings.size() > 1: game.mayor.inspect(t.buildings[1].id)
		game.mayor.center = t.hall.lerp(Vector3(3000, 0, 700), 0.5); game.mayor.zoom = 3000.0; game.mayor.update_camera()
		await _snap("mayor_trade", 40)
		game.mayor.set_active(false)
		for i in range(5): await get_tree().process_frame
	# ---------------------------------------------------------------- the journal
	if _want("journal"):
		game.catalogue.toggle()
		await _snap("journal", 20)
		game.catalogue.toggle()
	print("FIXPLAY UI DONE")
	get_tree().quit()


func _site(cid: String, type: String, near: Vector3) -> Variant:
	for r in range(16, 320, 8):
		for k in range(32):
			var a := TAU * k / 32.0
			var p := near + Vector3(cos(a) * r, 0, sin(a) * r)
			var y: float = snappedf(atan2(near.x - p.x, near.z - p.z), PI * 0.5)
			if econ.check_site(cid, type, p, y) == "": return [p, y]
	return null
