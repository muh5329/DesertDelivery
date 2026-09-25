extends Node
## C-2: fuel and getting round the country (fixplay).
##   * stations: one at every town, highway service stops, counters; every one on dry, level
##     ground beside its road
##   * reach: along every ring leg and spoke, the longest pump-to-pump stretch is well inside a
##     full tank, even with heavy freight (and the whole job chain's longest leg too)
##   * burn: flight burns more per metre; an empty tank limps on; warnings with the nearest pump
##   * a highway stop fills the tank with B; a town station sells coach tickets; fast travel
##     takes the courier and his bike to a visited town for coins and game time
## Run: godot --headless --path . -- --test=fixplay_journey_tests

var game: Game
var fails := 0
var checks := 0
var messages: Array[String] = []


func _ready() -> void:
	game = Game.current
	Events.message.connect(func(t, _d): messages.append(t))
	call_deferred("_run")


func _check(cond: bool, label: String) -> void:
	checks += 1
	print(("  PASS " if cond else "  FAIL ") + label)
	if not cond: fails += 1


func _secs(s: float) -> void:
	var t := 0.0
	while t < s:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()


func _run() -> void:
	game.use_scripted_controls()
	var j: JourneySystem = game.journey
	var sv: RoadServices = j.services
	# ------------------------------------------------------------------ the stations
	var towns := ["puerto_alto", "valdoro", "sarmada", "isola_serena", "campo_real"]
	for cid in towns:
		_check(sv.by_id.has("station.%s" % cid), "C-2: %s has a fuel station (coach & ferry office too)" % cid)
	var hw := sv.stations.filter(func(s): return s.kind == "highway")
	print("  stations: %d (%d highway service stops) placed in %d ms" % [sv.stations.size(), hw.size(), sv.build_ms])
	_check(hw.size() >= 8, "C-2: highway service stops along the ring and the spokes (%d)" % hw.size())
	var bad: Array = []
	for s in sv.stations:
		if s.kind == "counter": continue
		var p: Vector3 = s.pos
		var g := game.world.terrain.height_at(p.x, p.z)
		if g < Terrain.SEA_LEVEL + 1.0 or absf(g - p.y) > 1.7: bad.append("%s (ground %.1f, apron %.1f)" % [s.id, g, p.y])
	_check(bad.is_empty(), "C-2: every station stands on dry ground level with its road %s" % [bad])
	# ------------------------------------------------------------------ reach on every leg
	var tank_heavy := JourneySystem.TANK_RANGE_M / (1.0 + 55.0 / JourneySystem.CARGO_KG_PER_EXTRA_TANK)
	var worst := 0.0
	var worst_road := ""
	for g in sv.gaps():
		print("    %s: %.1f km, pump gaps %s km" % [g.road, g.length / 1000.0, (g.gaps as Array).map(func(x): return snappedf(x / 1000.0, 0.1))])
		if g.worst > worst: worst = g.worst; worst_road = g.road
	print("  C-2: longest pump-to-pump stretch %.1f km (%s); full tank %.1f km, %.1f km with heavy freight" % [worst / 1000.0, worst_road, JourneySystem.TANK_RANGE_M / 1000.0, tank_heavy / 1000.0])
	_check(worst > 0.0 and worst < tank_heavy * 0.5, "C-2: every ring leg and spoke is under half a heavy-freight tank between pumps (%.1f km < %.1f km)" % [worst / 1000.0, tank_heavy * 0.5 / 1000.0])
	# the job chain: from a station/counter at the pickup to the drop-off, on one tank with room
	var longest := 0.0
	for job in game.gm.jobs:
		var a: Vector3 = game.world.database.location_pos(job.from_location)
		var b: Vector3 = game.world.database.location_pos(job.to_location)
		longest = maxf(longest, Vector2(a.x - b.x, a.z - b.z).length() * 1.35)
	_check(longest < tank_heavy * 0.9, "C-2: the longest job (~%.1f km by road) fits one heavy-freight tank (%.1f km)" % [longest / 1000.0, tank_heavy / 1000.0])
	# ------------------------------------------------------------------ burn, limp, warnings
	j.fuel_ratio = 1.0; j._odometer = game.bike.odometer
	game.bike.odometer += 1000.0; j._process(0.1)
	var ground_burn := 1.0 - j.fuel_ratio
	game.bike.airborne = true
	j.fuel_ratio = 1.0; j._odometer = game.bike.odometer
	game.bike.odometer += 1000.0; j._process(0.1)
	var air_burn := 1.0 - j.fuel_ratio
	game.bike.airborne = false
	_check(air_burn > ground_burn * 1.4, "C-2: flying burns more per metre than riding (%.4f vs %.4f per km)" % [air_burn, ground_burn])
	var prof: Dictionary = game.bike.performance_profile()
	game.bike.set_meta("fuel_ratio", 0.0)
	var empty: Dictionary = game.bike.performance_profile()
	game.bike.set_meta("fuel_ratio", 1.0)
	_check(float(empty.ground_speed_limit) >= 6.0 and float(empty.ground_speed_limit) < float(prof.ground_speed_limit) * 0.4, "C-2: an empty tank limps on at %.0f km/h" % (float(empty.ground_speed_limit) * 3.6))
	messages.clear()
	j.fuel_ratio = 0.26; j._warned = -1; j._odometer = game.bike.odometer
	game.bike.odometer += 800.0; j._process(0.1)
	var warned := messages.filter(func(m): return m.begins_with("Fuel low")).size() > 0
	var names_pump := messages.any(func(m): return m.contains("Nearest pump"))
	_check(warned and names_pump, "C-2: a low tank is announced with the nearest pump (%s)" % [messages])
	_check(j.low_fuel_hint().contains("km"), "C-2: the HUD hint names the nearest pump and its distance (%s)" % j.low_fuel_hint())
	# ------------------------------------------------------------------ a highway stop
	var stop: Dictionary = hw[0]
	var fwd: Vector3 = stop.forward
	var at: Vector3 = stop.pos - (stop.out as Vector3) * 2.0
	game.rider.respawn_at(at, fwd)
	game.world.set_focus(game.rider.courier())
	game.world.outer.refresh_collision()
	game.world.streamer.load_all_pending()
	await _secs(1.5)
	_check(sv.is_built(stop.id), "C-2: the stop is drawn when the courier is there")
	var bp := game.bike.global_position
	_check(absf(bp.y - float(stop.pos.y)) < 1.2 and game.bike.grounded, "C-2: the bike stands on the apron (y %.1f vs %.1f)" % [bp.y, stop.pos.y])
	j.fuel_ratio = 0.3
	game.gm.coins = 200
	for i in range(3): await get_tree().process_frame
	var hud_hint: Label = game.hud._service_hint
	print("  HUD hint '%s' visible %s rect %s" % [hud_hint.text, hud_hint.is_visible_in_tree(), hud_hint.get_global_rect()])
	_check(hud_hint.text.contains("Fill up") and hud_hint.is_visible_in_tree() and get_viewport().get_visible_rect().encloses(hud_hint.get_global_rect()), "C-2: the HUD tells the courier he can fill up here (%s)" % hud_hint.text)
	var hint := j.interaction_hint()
	var ok := j.open_counter()
	_check(hint.contains("Fill up") and ok and is_equal_approx(j.fuel_ratio, 1.0) and game.gm.coins < 200, "C-2: B at a service stop fills the tank for coins (%s; coins %d)" % [hint, game.gm.coins])
	# ------------------------------------------------------------------ coach & ferry
	var econ: ColonyEconomy = game.colony.economy
	for cid in towns: econ.town(cid).discovered = false
	econ.town("valdoro").discovered = true
	var home: Dictionary = sv.by_id["counter.villa_rosa_office"]
	var dests: Array = sv.destinations(home.id)
	var val: Dictionary = {}
	var sar: Dictionary = {}
	for d in dests:
		if d.id == "valdoro": val = d
		if d.id == "sarmada": sar = d
	_check(not val.is_empty() and val.open and not sar.is_empty() and not sar.open, "C-2: tickets go to visited towns only (Valdoro open, Sarmada '%s')" % sar.get("reason", ""))
	game.rider.respawn_at(game.world.road_spawn(home.pos + Vector3(6, 0, 0), home.pos).pos, Vector3.FORWARD)
	game.world.set_focus(game.rider.courier())
	game.world.streamer.load_all_pending()
	await _secs(0.8)
	_check(sv.travel(home.id, "sarmada") != "", "C-2: no ticket to a town not yet visited")
	var coins0 := game.gm.coins
	var t0: float = game.life.total_minutes
	var why := sv.travel(home.id, "valdoro")
	await _secs(1.5)
	var vs: Dictionary = sv.by_id["station.valdoro"]
	var cp: Vector3 = game.rider.courier().global_position
	_check(why == "" and Vector2(cp.x - vs.pos.x, cp.z - vs.pos.z).length() < 30.0, "C-2: the coach sets the courier down at Valdoro's station (%s, %.0f m away)" % [why, Vector2(cp.x - vs.pos.x, cp.z - vs.pos.z).length()])
	_check(game.bike.global_position.distance_to(cp) < 6.0 and game.bike.grounded, "C-2: ... with his bike, on its wheels")
	_check(game.gm.coins == coins0 - int(val.price) and game.life.total_minutes >= t0 + float(val.minutes) - 0.5, "C-2: a ticket costs %d coins and %d game minutes" % [val.price, val.minutes])
	# a town station's window opens with B
	var near := j.nearby_station()
	_check(near.get("id", "") == "station.valdoro", "C-2: the courier is on Valdoro's station apron")
	j.open_counter()
	_check(j.station_panel.is_open(), "C-2: B at a town station opens the fuel & ticket window")
	j.station_panel.close_panel()
	for cid in towns: econ.town(cid).discovered = true
	print("FIXPLAY JOURNEY %d checks / %d failures" % [checks, fails])
	get_tree().quit(1 if fails else 0)
