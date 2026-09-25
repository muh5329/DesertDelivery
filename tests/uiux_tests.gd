extends Node
## The loading screen and the map (M), end to end: the boot runs in stages whose progress only
## grows and finishes; the loading screen covers a long move and lifts once the world round the
## courier is built; the baked minimap covers the whole 25 km world the right way up (sea at the
## edge, the core harbour, every town centre on a town, the highways on road pixels); the markers
## follow the courier and the job; the waypoint sets, saves and clears; the zoom cycles; the full
## map opens and closes like any panel and the minimap steps back with the HUD.
## Run: godot --headless --path . -- --test=uiux_tests

var game: Game
var fails := 0


func _ready() -> void:
	game = Game.current
	game.encounters.ambush_enabled = false
	game.vitals.health.invulnerable = 1e9
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	print(("  PASS " if ok else "  FAIL ") + label)
	if not ok: fails += 1


func frames(n: int) -> void:
	for i in n: await get_tree().process_frame


func secs(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _run() -> void:
	await frames(3)
	_boot_checks()
	_texture_checks()
	await _marker_checks()
	await _waypoint_checks()
	await _zoom_checks()
	await _full_map_checks()
	await _loading_checks()
	print("UIUX TESTS: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails > 0 else 0)


# ------------------------------------------------------------------ boot
func _boot_checks() -> void:
	var log: Array = game.loading.stage_log
	var ids: Array = log.map(func(e): return e.id)
	check(log.size() >= 12, "the boot ran in %d reported stages" % log.size())
	var mono := true
	for k in range(1, log.size()):
		if float(log[k].progress) < float(log[k - 1].progress): mono = false
	check(mono, "the boot's progress only grows (%s)" % ", ".join(log.map(func(e): return "%s %.2f" % [e.id, e.progress])))
	check(float(log[0].progress) == 0.0 and ids[0] == &"terrain", "it starts at 0 with the terrain")
	for want in [&"terrain", &"ground", &"core", &"outer_data", &"outer_roads", &"outer_towns", &"outer_wild", &"textures", &"vehicles", &"life", &"colony", &"ui", &"streaming", &"settle"]:
		if not ids.has(want): check(false, "stage %s reported" % want)
	check(ids[-1] == &"settle" and absf(float(log[-1].progress) - Game.BOOT_SHARE) < 0.001, "the last stage is the settling, at the end of the boot's share")
	check(game.booted and game.boot_ms.size() == log.size() - 1, "every stage ran and was timed (%d)" % game.boot_ms.size())
	check(game.boot_frames <= log.size() + 2, "the staging cost %d frames for %d stages (one each)" % [game.boot_frames, log.size() - 1])
	check(not game.loading.enabled and not game.loading.showing(), "a test run never keeps the loading screen up")
	check(not get_tree().paused, "the tree is running again after the boot")


# ------------------------------------------------------------------ the baked map
func _px(img: Image, x: float, z: float) -> Color:
	var uv := game.map.uv_of(x, z)
	return img.get_pixel(clampi(int(uv.x * img.get_width()), 0, img.get_width() - 1), clampi(int(uv.y * img.get_height()), 0, img.get_height() - 1))


func _is_water(c: Color) -> bool:
	return c.b > c.r + 0.08 and c.b > 0.35


func _near(img: Image, cx: int, cy: int, r: int, want: Array, tol := 0.13) -> bool:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var x := clampi(cx + dx, 0, img.get_width() - 1); var y := clampi(cy + dy, 0, img.get_height() - 1)
			var c := img.get_pixel(x, y)
			for w: Color in want:
				if absf(c.r - w.r) < tol and absf(c.g - w.g) < tol and absf(c.b - w.b) < tol: return true
	return false


func _texture_checks() -> void:
	var map: WorldMap = game.map
	check(map.ready() and map.meta.world[2] == 25000.0, "map.json describes the 25 km world")
	var img := WorldMap.load_image("overview")
	var det := WorldMap.load_image("detail")
	check(img != null and img.get_width() == 4096 and img.get_height() == 4096, "the overview is 4096 x 4096 (6.1 m a pixel)")
	check(det != null, "the detail atlas loads")
	if img == null or det == null: return
	check(map.uv_of(-12500, -12500).is_equal_approx(Vector2.ZERO) and map.uv_of(12500, 12500).is_equal_approx(Vector2.ONE), "the map spans the world corner to corner")
	var corners := [Vector2(-12400, -12400), Vector2(12400, -12400), Vector2(-12400, 12400), Vector2(12400, 12400)]
	check(corners.all(func(p): return _is_water(_px(img, p.x, p.y))), "sea at every edge of the world")
	# orientation: the mountain lake is up in the north (-z), Sarmada down in the desert south
	var plan: Dictionary = game.world.outer.plan()
	var lk: Dictionary = plan.lake
	check(_is_water(_px(img, lk.x, lk.z)) and float(lk.z) < 0.0, "the mountain lake lands on water, in the north (north is up)")
	var mirrored := _px(img, lk.x, -float(lk.z))
	check(not _is_water(mirrored), "and its mirror image in the south is land (the map is not flipped)")
	# the core: its harbour on water beside the villa's land
	var berth: Array = plan.ports[0].berth
	var uv := map.uv_of(berth[0], berth[2])
	var bx := int(uv.x * 4096); var by := int(uv.y * 4096)
	var water_near := false
	for dy in range(-6, 7):
		for dx in range(-6, 7):
			if _is_water(img.get_pixel(bx + dx, by + dy)): water_near = true
	check(water_near, "the core harbour's berth is at the water")
	check(not _is_water(_px(img, -326.0, 3.0)), "the villa square is land")
	# every town and hamlet centre on a town (roofs, streets or paving) - overview and inset
	var town_cols := [Color8(192, 104, 78), Color8(116, 118, 122), Color8(228, 212, 184), Color8(226, 176, 150), Color8(200, 150, 96),
		Color8(238, 230, 210), Color8(224, 214, 192), Color8(128, 116, 98)]
	var bad: Array = []
	var bad_inset: Array = []
	var insets := {}
	for r in map.meta.detail.insets: insets[r.id] = r
	for t in plan.towns + plan.hamlets:
		# the town's centre: its square (the plan's nominal centre can be open ground)
		var cx: float = t.plaza[0] if t.get("plaza") is Array else t.center[0]
		var cz: float = t.plaza[2] if t.get("plaza") is Array else t.center[1]
		var tu := map.uv_of(cx, cz)
		if not _near(img, int(tu.x * 4096), int(tu.y * 4096), 2, town_cols, 0.09): bad.append(t.name)
		var r: Dictionary = insets.get(t.id, {})
		if r.is_empty(): bad_inset.append(t.name); continue
		var fx: float = (cx - r.world[0]) / r.world[2]; var fz: float = (cz - r.world[1]) / r.world[3]
		if fx < 0 or fz < 0 or fx > 1 or fz > 1 or not _near(det, int(r.px[0] + fx * r.px[2]), int(r.px[1] + fz * r.px[3]), 3, town_cols, 0.09): bad_inset.append(t.name)
	check(bad.is_empty(), "every town and hamlet centre lands on a town pixel of the overview %s" % [bad])
	check(bad_inset.is_empty(), "and on a town pixel of its 1.5 m inset %s" % [bad_inset])
	# the highways on highway pixels
	var hw_fill := [Color8(238, 170, 70)]
	var n := 0; var ok := 0
	for road in plan.roads:
		if road.class != "highway": continue
		var pts: Array = road.points
		for k in range(pts.size() / 7, pts.size(), maxi(1, pts.size() / 6)):
			var q: Array = pts[k]
			if absf(q[0]) < 700 and absf(q[2]) < 700: continue
			var hu := map.uv_of(q[0], q[2])
			n += 1
			if _near(img, int(hu.x * 4096), int(hu.y * 4096), 1, hw_fill, 0.16): ok += 1
	check(n > 20 and ok >= n * 0.9, "highway samples land on highway pixels (%d of %d)" % [ok, n])


# ------------------------------------------------------------------ markers
func _marker_checks() -> void:
	var mm: Minimap = game.minimap
	var map: WorldMap = game.map
	check(mm != null and mm.get_parent() == game.hud.get_child(0), "the minimap lives in the HUD's root")
	await frames(3)
	var cp := game.rider.courier().global_position
	check(mm.center.distance_to(Vector2(cp.x, cp.z)) < 1.0, "the minimap is centred on the courier")
	var p := mm.center + Vector2(130, -70)
	check(mm.to_world(mm.to_screen(p)).distance_to(p) < 0.01, "screen and world points map both ways")
	map.rotate = true
	await frames(2)
	var f := -game.cam.global_transform.basis.z
	var ahead := mm.to_screen(mm.center + Vector2(f.x, f.z).normalized() * mm.radius_m * 0.5)
	check(absf(ahead.x - Minimap.DIAMETER * 0.5) < 1.5 and ahead.y < Minimap.DIAMETER * 0.5, "heading-up: what the camera faces is up on the minimap")
	map.rotate = false
	await frames(2)
	var north := mm.to_screen(mm.center + Vector2(0, -100))
	check(absf(north.x - Minimap.DIAMETER * 0.5) < 0.5 and north.y < Minimap.DIAMETER * 0.5, "north-up: -z is up")
	map.rotate = true
	# the job's pickup and drop-off
	var gm := game.gm
	var ms := map.markers(mm.center, 500.0)
	var job := gm.current_job()
	var pick := ms.filter(func(m): return m.kind == &"pickup")
	var drop := ms.filter(func(m): return m.kind == &"dropoff")
	var tp := gm.target_position()
	check(pick.size() == 1 and (pick[0].pos as Vector2).distance_to(Vector2(tp.x, tp.z)) < 0.1 and pick[0].target, "the pickup marker sits on the delivery target")
	var dp := gm.db.location_pos(job.to_location)
	check(drop.size() == 1 and (drop[0].pos as Vector2).distance_to(Vector2(dp.x, dp.z)) < 0.1, "the drop-off is marked too")
	check(ms.any(func(m): return m.kind == &"fuel" or m.kind == &"counter"), "stations and counters are on the map")
	var t0 := Time.get_ticks_usec()
	for i in range(50): map.markers(mm.center, 1300.0)
	var per := (Time.get_ticks_usec() - t0) / 50.0
	check(per < 1500.0, "gathering the markers costs %.0f us (10 times a second)" % per)
	# on foot, the bike and the jeep are markers; move the courier and the view follows
	var colonies := map.markers(Vector2.ZERO, 30000.0).filter(func(m): return m.kind == &"colony")
	check(colonies.size() >= 1, "colony halls are marked (%d)" % colonies.size())
	var far := Vector3(7480.0, 0.0, 1650.0)
	var sp := game.world.road_spawn(far, far + Vector3(0, 0, 10))
	game.rider.respawn_at(sp.pos, sp.forward)
	await frames(3)
	var cp2 := game.rider.courier().global_position
	check(mm.center.distance_to(Vector2(cp2.x, cp2.z)) < 1.0, "the minimap follows the courier across the country")
	var near_port := map.markers(mm.center, 2000.0)
	check(near_port.any(func(m): return m.kind == &"lane") == (game.colony.economy.shipping.lanes.size() > 0), "near a port the sea lanes show (%d lanes)" % game.colony.economy.shipping.lanes.size())
	# discovered camps: none known at first, one once the courier has been near
	var enc := game.encounters
	var cid: StringName = enc.camps.keys().filter(func(k): return not String(k).begins_with("ambush"))[0]
	check(not map.discovered.has(cid) or enc.is_cleared(cid), "an unvisited camp is not on the map")
	var cpos: Vector3 = enc.camps[cid].pos
	var sp2 := game.world.road_spawn(cpos + Vector3(60, 0, 0), cpos)
	game.rider.respawn_at(sp2.pos, sp2.forward)
	await secs(1.2)
	check(map.discovered.has(cid), "a camp comes onto the map once the courier has been near")
	var home := game.world.road_spawn(game.world.database.location_pos(&"villa_square") + Vector3(46, 0, 0), game.world.database.location_pos(&"villa_rosa_office"))
	game.rider.respawn_at(home.pos, home.forward)
	await frames(3)


# ------------------------------------------------------------------ waypoint
func _waypoint_checks() -> void:
	var map: WorldMap = game.map
	var mm: Minimap = game.minimap
	var target := Vector3(900.0, 0.0, -900.0)
	map.set_waypoint(target)
	check(map.has_waypoint and absf(map.waypoint.y - game.world.terrain.height_at(900, -900)) < 0.1, "a waypoint is set on the ground")
	var ws := map.markers(mm.center, 100.0).filter(func(m): return m.kind == &"waypoint")
	check(ws.size() == 1 and ws[0].target, "it is a marker even beyond the view (pinned to the rim)")
	var saved := map.save_state()
	map.clear_waypoint()
	check(not map.has_waypoint and map.markers(mm.center, 5000.0).all(func(m): return m.kind != &"waypoint"), "clearing removes it")
	map.load_state(saved)
	check(map.has_waypoint and map.waypoint.distance_to(Vector3(900, map.waypoint.y, -900)) < 0.01, "it is saved and loaded")
	# reaching it clears it
	var cp := game.rider.courier().global_position
	map.set_waypoint(cp + Vector3(5, 0, 0))
	await secs(0.4)
	check(not map.has_waypoint, "riding up to the waypoint clears it")


# ------------------------------------------------------------------ zoom
func _key(action: StringName, shift := false) -> void:
	var e := InputEventAction.new(); e.action = action; e.pressed = true
	Input.parse_input_event(e)
	var up := InputEventAction.new(); up.action = action; up.pressed = false
	Input.parse_input_event(up)


func _zoom_checks() -> void:
	var map: WorldMap = game.map
	var mm: Minimap = game.minimap
	var radii: Array = []
	for i in range(3):
		map.zoom_level = i
		radii.append(mm.target_radius())
	check(radii[0] < radii[1] and radii[1] < radii[2], "three zoom levels, close to far (%s m)" % [radii])
	map.zoom_level = 0
	var levels: Array = []
	for i in range(3):
		_key(&"map_zoom")
		await frames(2)
		levels.append(map.zoom_level)
	check(levels == [1, 2, 0], "Z cycles the zoom (%s)" % [levels])
	map.zoom_level = 1
	mm.snap()
	await frames(2)
	check(absf(mm.radius_m - mm.target_radius()) < 1.0, "the minimap shows the level's radius (%.0f m)" % mm.radius_m)


# ------------------------------------------------------------------ the full map
func _full_map_checks() -> void:
	var fm: FullMap = game.full_map
	var mm: Minimap = game.minimap
	_key(&"map_open")
	await frames(3)
	check(fm.is_open() and game.panels.is_open(fm), "M opens the full map as a panel")
	check(not mm.shown(), "the minimap steps back with the HUD")
	check(game.player_controls.blocked, "the controls are blocked while the map is open")
	var q := Vector2(300, 200)
	check(fm.to_screen(fm.to_world(q)).distance_to(q) < 0.01, "the full map's screen and world points map both ways")
	var before := fm.to_world(q)
	fm.zoom_at(q, 0.5)
	check(fm.to_world(q).distance_to(before) < 0.01, "zooming keeps the point under the cursor")
	fm._set_waypoint(fm.to_world(q))
	check(game.map.has_waypoint and Vector2(game.map.waypoint.x, game.map.waypoint.z).distance_to(fm.to_world(q)) < 0.01, "a click sets the waypoint there")
	fm.close_panel()
	await frames(4)
	check(not fm.is_open() and not game.panels.any_open(), "M / Esc closes it")
	check(mm.shown(), "and the minimap is back")
	game.map.clear_waypoint()
	# the journal and the Mayor view hide it too
	game.catalogue.toggle()
	await frames(2)
	check(not mm.shown(), "the journal hides the minimap")
	game.catalogue.toggle()
	await frames(4)
	if not game.rider.is_on_foot(): game.rider.request_dismount()
	await secs(1.5)
	game.mayor.toggle()
	await frames(2)
	check(game.mayor.active, "the Mayor view opens (on foot)")
	check(not mm.shown(), "the Mayor view hides the minimap")
	game.mayor.toggle()
	await frames(4)
	check(mm.shown(), "the minimap returns after the panels")


# ------------------------------------------------------------------ the loading screen on a long move
func _loading_checks() -> void:
	var ls: LoadingScreen = game.loading
	ls.enabled = true
	var dest := Vector3(-1575.0, 0.0, -5150.0)       # Valdoro, far from the villa
	var sp := game.world.road_spawn(dest, dest + Vector3(0, 0, 10))
	var moved := [false]
	game.relocate("Coach to Valdoro", func():
		game.rider.respawn_at(sp.pos, sp.forward)
		moved[0] = true)
	check(ls.showing() and not moved[0], "the loading screen is up before a long move runs")
	await frames(2)
	check(moved[0], "the move runs once the screen has been drawn")
	var up_unsettled := false
	var t := 0
	while ls.showing() and t < 3000:
		if not game.world.settled(): up_unsettled = up_unsettled or ls.showing()
		await get_tree().process_frame
		t += 1
		if not ls.waiting() and ls.showing() and not game.world.settled(): check(false, "it began fading before the world was built")
	check(up_unsettled, "it stays up while the world round the courier is still building")
	check(not ls.showing() and game.world.settled(), "it lifts once the world is built (%d frames)" % t)
	check(not game.panels.is_open(ls) and not game.panels.any_open(), "and hands the controls back")
	check(ls.progress >= 0.999, "its bar ended full")
	# a short hop is not covered
	var here := game.rider.courier().global_position
	game.rider.respawn_at(here + Vector3(30, 0, 0), Vector3.FORWARD)
	game.cover_move(here, "Hop")
	check(not ls.showing(), "a short move is not covered")
	ls.enabled = false
