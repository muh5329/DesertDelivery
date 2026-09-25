extends Node
## The colony findings of the September review (fixplay):
##   M-3  a freshly chartered colony left alone for an hour stabilises; every town can feed
##        itself from its own land; goods move by road between colonies
##   M-4  a damaged save keeps every valid colony, mends or drops only the bad record, and says so
##   M-8  chartering is surveyed over frames (no stall); the Build ghost's verdicts are cached
##   m-3  the colony hall stands in its town, with land round it
##   m-12 a lane's raid risk names the cove and where it is
##   m-15 a chartered colony has a far silhouette
## Run: godot --headless --path . -- --test=fixplay_colony_tests

var game: Game
var econ: ColonyEconomy
var fails := 0
var checks := 0
const TOWNS := ["puerto_alto", "valdoro", "sarmada", "isola_serena", "campo_real"]


func _ready() -> void:
	game = Game.current
	call_deferred("_run")


func _check(cond: bool, label: String) -> void:
	checks += 1
	print(("  PASS " if cond else "  FAIL ") + label)
	if not cond: fails += 1


func _focus(p: Vector3) -> void:
	game.bike.global_position = p + Vector3(0, 40, 0)
	game.world.set_focus(game.bike)
	game.world.streamer.load_all_pending()
	if game.world.outer: game.world.outer.refresh_collision()


func _run() -> void:
	game.use_scripted_controls()
	game.life.set_physics_process(false)
	econ = game.colony.economy
	econ.ensure_shipping()
	for i in range(3): await get_tree().physics_frame
	left_alone()
	self_sufficient()
	road_haulage()
	await charters()
	await partial_saves()
	risk_names()
	print("FIXPLAY COLONY %d checks / %d failures" % [checks, fails])
	get_tree().quit(1 if fails else 0)


## A detached colony as a charter makes it (hall, settlers, starter stock) - pure rules.
func _chartered(cid: String) -> ColonyTown:
	var t := ColonyTown.new(cid)
	t.founded = true; t.discovered = true
	t.add_building("colony_hall", Vector3.ZERO, 0.0, true)
	for item in EconomyCatalog.CHARTER_STOCK: t.stock[item] = int(EconomyCatalog.CHARTER_STOCK[item])
	var staple := String(EconomyCatalog.COLONIES[cid].get("staple", ""))
	if staple != "": t.stock[staple] = int(t.stock.get(staple, 0)) + EconomyCatalog.STAPLE_STOCK
	for i in range(EconomyCatalog.CHARTER_SETTLERS): t.add_colonist(hash([cid, i]))
	t.assign()
	return t


# -------------------------------------------------------------------------- M-3
func left_alone() -> void:
	for cid in TOWNS:
		var t := _chartered(cid)
		var trace := PackedStringArray()
		var min_pop := t.colonists.size()
		for minute in range(61):
			if minute % 10 == 0: trace.append("[%dmin pop %d hap %.0f food %.2f stock food %d]" % [minute, t.colonists.size(), t.happiness, t.needs.food, _food(t)])
			for i in range(240): t.tick(0.25)
			min_pop = mini(min_pop, t.colonists.size())
		print("  %s left alone: %s" % [cid, " ".join(trace)])
		_check(min_pop >= EconomyCatalog.CHARTER_SETTLERS and t.needs.food >= 0.9 and t.happiness >= 50.0,
			"M-3: %s, chartered and left alone for an hour, stabilises (pop never below %d, food %.2f, happiness %.0f)" % [cid, min_pop, t.needs.food, t.happiness])


func _food(t: ColonyTown) -> int:
	var n := 0
	for f in EconomyCatalog.FOODS: n += t.count(f)
	return n


func self_sufficient() -> void:
	for cid in TOWNS:
		var foods := EconomyCatalog.local_foods(cid)
		_check(not foods.is_empty(), "M-3: %s can grow its own food (%s)" % [cid, ", ".join(PackedStringArray(foods))])
		# a grown colony: 20 people, houses, one building per local food, no starter food at all
		var t := _chartered(cid)
		t.stock = {"planks": 10}
		for i in range(4): t.add_building("townhouse", Vector3(30 + i * 20, 0, 0), 0.0, true)
		var n := 0
		for type in EconomyCatalog.BUILDINGS:
			var def: Dictionary = EconomyCatalog.BUILDINGS[type]
			if def.has("raw") and String(def.raw) in foods and EconomyCatalog.buildable_in(cid, type):
				t.add_building(type, Vector3(-30 - n * 20, 0, 20), 0.0, true); n += 1
		while t.colonists.size() < 20: t.add_colonist(hash([cid, "grown", t.colonists.size()]))
		t.assign()
		for i in range(240 * 45): t.tick(0.25)
		var make := t.food_output_per_minute()
		var eat := t.colonists.size() * ColonyTown.FOOD_RATE * 60.0
		print("  %s: %d people, food made %.1f/min, eaten %.1f/min, needs %s, stock food %d" % [cid, t.colonists.size(), make, eat, t.needs, _food(t)])
		_check(t.needs.food >= 0.9 and t.colonists.size() >= 20 and make >= eat, "M-3: %s feeds 20+ people from its local chain (%.1f made vs %.1f eaten a minute)" % [cid, make, eat])


func road_haulage() -> void:
	# two colonies without a port between them: Valdoro sends potatoes to Campo Real by wagon
	var saved := econ.save_state()
	for cid in ["valdoro", "campo_real"]:
		var t := econ.town(cid)
		t.founded = true; t.discovered = true
		if t.building_of_type("colony_hall").is_empty(): t.add_building("colony_hall", t.hall, 0.0, true)
	econ.town("valdoro").stock = {"planks": 20, "potatoes": 60}
	econ.town("campo_real").stock = {"grain": 40}
	game.gm.coins = 500
	var err := econ.add_road_route("valdoro", "campo_real", {"potatoes": 30}, {"grain": 20})
	_check(err == "", "M-3: a carter can be hired between Valdoro and Campo Real (%s)" % err)
	var r: Dictionary = econ.roads.routes[0] if not econ.roads.routes.is_empty() else {}
	var km := float(r.get("m", 0.0)) / 1000.0
	for i in range(int(float(r.get("m", 0.0)) * 2.2 / RoadHaulage.SPEED / 0.25) + 400): econ.roads.tick(0.25)
	var got_p := econ.town("campo_real").count("potatoes")
	var got_g := econ.town("valdoro").count("grain")
	print("  road haulage: %.1f km, trips %d, campo potatoes %d, valdoro grain %d" % [km, int(r.get("trips", 0)), got_p, got_g])
	_check(got_p >= 30 and got_g >= 20, "M-3: goods move by road both ways (potatoes %d, grain %d)" % [got_p, got_g])
	var round_trip := econ.save_state()
	econ.load_state(round_trip)
	_check(econ.roads.routes.size() == 1, "M-3: carter routes survive save/load")
	econ.load_state(saved)


# -------------------------------------------------------------------------- M-8, m-3, m-15
func charters() -> void:
	game.gm.coins = 5000
	for cid in TOWNS:
		var t := econ.town(cid)
		t.discovered = true
		var pz: Array = econ._town_plan[cid].plaza
		var plaza := Vector3(pz[0], pz[1], pz[2])
		_focus(plaza)
		for i in range(5): await get_tree().physics_frame
		var err := econ.begin_found(cid)
		var worst := 0.0
		var frames := 0
		while econ.chartering(cid) and frames < 3000:
			var t0 := Time.get_ticks_usec()
			econ._survey_halls()
			worst = maxf(worst, (Time.get_ticks_usec() - t0) / 1000.0)
			frames += 1
			await get_tree().process_frame
		var d := Vector2(t.hall.x - plaza.x, t.hall.z - plaza.z).length()
		var land := econ._land_share(t.hall, 150.0)
		print("  %s: charter surveyed over %d frames, worst %.1f ms; hall %.0f m from the plaza, land round it %.0f%%" % [cid, frames, worst, d, land * 100.0])
		_check(err == "" and t.founded and worst < 8.0, "M-8: chartering %s never stalls a frame (worst %.1f ms)" % [cid, worst])
		_check(d < 450.0 and land >= 0.6, "m-3: %s's hall stands by its town (%.0f m from the plaza) with land round it (%.0f%%)" % [cid, d, land * 100.0])
	# the Build ghost: a second look at the same spot is free
	var cid := "campo_real"
	var t := econ.town(cid)
	var at := t.hall + Vector3(60, 0, 40)
	var t0 := Time.get_ticks_usec()
	var a := econ.check_site_cached(cid, "cottage", at, 0.0)
	var first := (Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	for i in range(50): econ.check_site_cached(cid, "cottage", at + Vector3(0.2, 0, 0.2), 0.0)
	var again := (Time.get_ticks_usec() - t0) / 1000.0 / 50.0
	print("  ghost: first check %.2f ms, cached %.3f ms (%s)" % [first, again, a])
	_check(again < 0.2, "M-8: the Build ghost's verdict is cached per metre (%.3f ms)" % again)
	# m-15: the far silhouette of a colony with a finished building
	t.add_building("cottage", t.hall + Vector3(40, 0, 30), 0.0, true)
	econ.views._sync_far()
	_check(econ.views.has_far(cid), "m-15: a chartered colony with buildings has a far silhouette")
	var mi: MeshInstance3D = econ.views._far[cid].node
	_check(mi.visibility_range_begin >= ColonyViews.BUILDING_RADIUS and mi.mesh != null and mi.mesh.get_surface_count() > 0, "m-15: drawn from where the detailed buildings end (%.0f m)" % mi.visibility_range_begin)


# -------------------------------------------------------------------------- M-4
func partial_saves() -> void:
	var colony := game.colony
	var pa := econ.town("puerto_alto")
	pa.stock["fish"] = 777
	var good := colony.save_state()
	pa.stock["fish"] = 5
	# one float just outside its range in one town, a broken building in another
	var bad: Dictionary = good.duplicate(true)
	bad.economy.towns.valdoro.happiness = 100.5
	var sb: Array = bad.economy.towns.sarmada.buildings
	sb.append({"id": "sarmada.b999", "type": "no_such_building", "x": 0.0})
	var ok := colony.load_state(bad)
	var warn := colony.load_report()
	print("  M-4: load returned %s, report %s" % [ok, warn])
	_check(ok and pa.count("fish") == 777, "M-4: a save with one bad value still loads every valid colony (fish %d)" % pa.count("fish"))
	_check(is_equal_approx(econ.town("valdoro").happiness, 100.0), "M-4: the bad value is clamped, not the colony dropped (happiness %.1f)" % econ.town("valdoro").happiness)
	_check(econ.town("sarmada").building("sarmada.b999").is_empty() and econ.town("sarmada").founded, "M-4: only the broken building is dropped")
	_check(warn.size() >= 2, "M-4: the load reports what it repaired (%d notes)" % warn.size())
	# a whole town record gone: that colony starts afresh, the rest load
	pa.stock["fish"] = 5
	var missing: Dictionary = good.duplicate(true)
	missing.economy.towns.erase("isola_serena")
	colony.load_state(missing)
	_check(pa.count("fish") == 777 and colony.load_report().size() >= 1, "M-4: a colony missing from the save starts afresh; the others load")
	# through the save file: the message reaches the player
	var msgs: Array = []
	var cb := func(t, _d): msgs.append(t)
	Events.message.connect(cb)
	var path := Saves.path_for("fixplay_bad")
	Saves.save_game("fixplay_bad")
	var f := FileAccess.open(path, FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text()); f.close()
	data.systems.colony.economy.towns.valdoro.happiness = 100.5
	f = FileAccess.open(path, FileAccess.WRITE); f.store_string(JSON.stringify(data)); f.close()
	var loaded := Saves.load_game("fixplay_bad")
	Events.message.disconnect(cb)
	_check(loaded and not Saves.last_report.is_empty() and msgs.any(func(m): return String(m).begins_with("Loaded with problems")), "M-4: the player is told what the load repaired (%s)" % [Saves.last_report])
	_check(not FileAccess.file_exists(path + ".tmp"), "M-4: saves are written atomically (no temp file left)")


# -------------------------------------------------------------------------- m-12
func risk_names() -> void:
	var sh := econ.shipping
	var rr := sh.route_risk("core", "puerto_alto")
	var named: bool = true
	for c in rr.threats:
		if ShippingNetwork.cove_name(String(c.id)) == "": named = false
	print("  core <-> Puerto Alto: risk %.0f%%, coves %s" % [float(rr.risk) * 100.0, (rr.threats as Array).map(func(c): return ShippingNetwork.cove_name(String(c.id)))])
	_check(float(rr.risk) == 0.0 or (not (rr.threats as Array).is_empty() and named), "m-12: a risky route names the cove that raids it")
