extends Node
## Shipping lanes in the booted game: the water grid, a route from the core harbour to every
## port that never touches land (sampled against Terrain.height_at every 5 m) and passes the
## estuary, a ship's round trip moving cargo between colony stockpiles, far ships sailing with
## no body, bodies only near the viewer, pirate raid risk tied to the coves' cleared state,
## save/load of ships and lanes, and the tick budget with a busy fleet.
var failures := 0
var checks := 0
var game: Game
var econ: ColonyEconomy
var sh: ShippingNetwork


func check(value: bool, label: String) -> void:
	checks += 1
	print(("PASS " if value else "FAIL ") + label)
	if not value: failures += 1


func _ready() -> void: call_deferred("run")


func run() -> void:
	game = Game.current
	game.use_scripted_controls()
	game.life.set_physics_process(false)
	game.colony.set_physics_process(false)
	econ = game.colony.economy
	econ.set_process(false)
	sh = econ.shipping
	var t0 := Time.get_ticks_msec()
	check(econ.ensure_shipping(), "Sea grid built and ports registered")
	print("  grid: %.0f ms on the worker (waited %d ms here), %d navigable cells" % [sh.build_ms, Time.get_ticks_msec() - t0, _count_nav()])
	routes()
	await round_trip()
	pirates()
	await bodies()
	persistence()
	perf()
	print("SHIPPING %d checks / %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)


func _count_nav() -> int:
	var n := 0
	for k in range(sh.nav.size()): n += sh.nav[k]
	return n


## The highest ground along a route, sampled every 5 m.
func _worst(r: Dictionary) -> Array:
	var pts: PackedVector2Array = r.points
	var worst := -INF; var at := Vector2.ZERO
	for k in range(pts.size() - 1):
		var n := maxi(1, ceili(pts[k].distance_to(pts[k + 1]) / 5.0))
		for i in range(n + 1):
			var p := pts[k].lerp(pts[k + 1], float(i) / n)
			var h := game.world.terrain.height_at(p.x, p.y)
			if h > worst: worst = h; at = p
	return [worst, at]


func routes() -> void:
	for cid in ["core", "puerto_alto", "sarmada", "isola_serena"]:
		check(sh.ports.has(cid), "Port registered: %s (moored at %s)" % [cid, sh.ports.get(cid, {}).get("moor", "-")])
	for to in ["puerto_alto", "sarmada", "isola_serena"]:
		var r := sh.route("core", to)
		check(not r.is_empty(), "Route core harbour -> %s exists (%.1f km, %d points)" % [to, float(r.get("length", 0)) / 1000.0, r.get("points", []).size()])
		if r.is_empty(): continue
		var w := _worst(r)
		check(float(w[0]) < -0.5, "core -> %s never crosses land (highest ground %.2f m at %s)" % [to, w[0], w[1]])
		# the lagoon's only way out is the estuary to the east
		var estuary := false
		for p in r.points:
			if p.x > 2000.0 and p.x < 5500.0 and p.y > -300.0 and p.y < 1300.0: estuary = true
		check(estuary, "core -> %s leaves the lagoon through the estuary" % to)
	for pair in [["puerto_alto", "sarmada"], ["sarmada", "isola_serena"], ["puerto_alto", "isola_serena"]]:
		var r := sh.route(pair[0], pair[1])
		var w := _worst(r) if not r.is_empty() else [INF, Vector2.ZERO]
		check(not r.is_empty() and float(w[0]) < -0.5, "Route %s -> %s over water (%.1f km, highest %.2f m)" % [pair[0], pair[1], float(r.get("length", 0)) / 1000.0, w[0]])
	var back := sh.route("isola_serena", "core")
	check(not back.is_empty() and is_equal_approx(float(back.length), float(sh.route("core", "isola_serena").length)), "Return routes are the same water reversed")


func _clear_all_coves(value: bool) -> void:
	for id in game.encounters.camps:
		if game.encounters.camps[id].kind == &"pirate":
			if value: game.encounters.cleared[id] = true
			else: game.encounters.cleared.erase(id)
	sh.pirates_changed()


func _sail(s: Dictionary, legs: int, limit: float) -> float:
	var trips := int(s.trips)
	var t := 0.0
	while int(s.trips) < trips + legs and t < limit:
		econ.tick(0.5); t += 0.5
	# and let it finish loading at the far end
	return t


func round_trip() -> void:
	_clear_all_coves(true)
	var pa := econ.town("puerto_alto")
	if not pa.founded:
		game.gm.coins = 1000
		econ.discover("puerto_alto")
		check(econ.found("puerto_alto") == "", "Puerto Alto chartered for the lane")
	var core := econ.town("core")
	# stone and salt: nobody eats them, so every unit is accounted for
	core.stock["stone"] = 80; pa.stock["salt"] = 70; pa.stock["stone"] = 0; core.stock["salt"] = 0
	var lane := econ.add_lane("core", "puerto_alto", {"stone": 40}, {"salt": 30})
	check(not lane.is_empty(), "Lane core -> Puerto Alto: 40 stone out, 30 salt back")
	# a coaster from the shipyard (the yard itself is a building like any other)
	check(econ.build_ship("core", "coaster").contains("shipyard"), "Ships need a shipyard")
	var s := sh.add_ship("coaster", "core")
	s.timer = 0.0
	econ.tick(0.1)
	check(s.state == "docked", "The coaster is launched at the core harbour")
	check(sh.assign(s.id, lane.id), "Coaster assigned to the lane")
	check(int(s.cargo.get("stone", 0)) == 40 and core.count("stone") == 40, "Loaded 40 stone at the core harbour")
	var r := sh.route("core", "puerto_alto")
	var t := _sail(s, 1, 4000.0)
	print("  outbound leg: %.0f s for %.1f km at %.1f m/s" % [t, float(r.length) / 1000.0, sh.speed(s)])
	check(s.port == "puerto_alto" and pa.count("stone") == 40, "Stone unloaded into Puerto Alto's stockpile")
	check(int(s.cargo.get("salt", 0)) == 30 and pa.count("salt") == 40, "Salt loaded for the return")
	t = _sail(s, 1, 4000.0)
	check(s.port == "core" and core.count("salt") == 30 and not s.cargo.has("salt"), "Round trip complete: salt in the core stockpile")
	check(int(s.cargo.get("stone", 0)) == 40 and core.count("stone") == 0, "And it loops: loaded stone again")
	check(int(lane.trips) == 2 and lane.log.size() >= 2, "Lane counts trips and logs them")


func pirates() -> void:
	_clear_all_coves(false)
	var risky := {}
	for pair in [["core", "puerto_alto"], ["core", "sarmada"], ["sarmada", "isola_serena"], ["core", "isola_serena"], ["puerto_alto", "sarmada"]]:
		var l := {"id": "probe.%s.%s" % pair, "from": pair[0], "to": pair[1]}
		var risk := sh.lane_risk(l)
		print("  raid risk %s -> %s: %d%% %s" % [pair[0], pair[1], int(risk * 100), sh.lane_threats(l)])
		if risk > 0.0: risky[l.id] = l
	check(not risky.is_empty(), "Some lanes pass an uncleared pirate cove")
	var threats_of := {}
	for lid in risky: threats_of[lid] = sh.lane_threats(risky[lid])
	for lid in risky:
		var l: Dictionary = risky[lid]
		var threats: Array = threats_of[lid]
		for cid in threats:
			# what the combat system does when the last pirate falls
			game.encounters.cleared[StringName(cid)] = true
			Events.camp_cleared.emit(StringName(cid))
		check(sh.lane_risk(l) == 0.0, "Clearing %s makes %s -> %s safe" % [threats, l.from, l.to])
	_clear_all_coves(false)
	# a raid: with the coves back, sail a lane until one happens (deterministic per trip)
	var lane: Dictionary = sh.lanes[0]
	var s := sh.ship(lane.ships[0])
	var risk := sh.lane_risk(lane)
	var raids := int(s.raids)
	var legs := 0
	econ.town("core").stock["stone"] = 250; econ.town("puerto_alto").stock["salt"] = 250
	while int(s.raids) == raids and legs < 60 and risk > 0.0:
		_sail(s, 1, 4000.0); legs += 1
	check(risk == 0.0 or int(s.raids) > raids, "Pirates raid a risky lane now and then (%d%% risk, raid after %d legs)" % [int(risk * 100), legs])
	check(risk == 0.0 or econ.notifications.any(func(n): return String(n.text).begins_with("Pirates raided")), "A raid is reported to the player")


func _focus(p: Vector3) -> void:
	game.bike.global_position = p + Vector3(0, 40, 0)
	game.world.set_focus(game.bike)


func bodies() -> void:
	var v := econ.views
	var s := sh.ship(sh.lanes[0].ships[0])
	# the viewer far from every ship: none drawn, the ship still sails
	_focus(Vector3(-6000, 0, -9000))
	for f in range(10): await get_tree().process_frame
	check(v.ships.is_empty(), "No ship bodies far from the viewer")
	while s.state != "sailing": econ.tick(0.5)
	var before := float(s.s)
	for i in range(40): econ.tick(0.5)
	check(float(s.s) > before + 100.0, "Far ships sail by the clock (%.0f m -> %.0f m)" % [before, float(s.s)])
	# more ships than the cap, all near one port
	for i in range(8):
		var extra := sh.add_ship("schooner" if i % 2 else "coaster", "core")
		extra.timer = 0.0
	econ.tick(0.1)
	_focus(Vector3(262, 0, -40))
	for f in range(10): await get_tree().process_frame
	check(v.ships.size() > 0 and v.ships.size() <= ColonyViews.MAX_SHIPS, "Ships near the viewer get bodies, capped (%d of %d)" % [v.ships.size(), sh.ships.size()])
	var any: ShipModel = v.ships.values()[0] if not v.ships.is_empty() else null
	check(any != null and any.hull.mesh != null and any.hull.mesh.get_faces().size() > 300, "A ship body is a modelled hull")
	for i in range(8): sh.ships.pop_back()


func persistence() -> void:
	var colony := game.colony
	var s: Dictionary = sh.ship(sh.lanes[0].ships[0])
	while s.state != "sailing": econ.tick(0.5)
	for i in range(10): econ.tick(0.5)
	var snap: Dictionary = JSON.parse_string(JSON.stringify(colony.save_state()))
	var at := float(s.s); var cargo: Dictionary = s.cargo.duplicate()
	for i in range(30): econ.tick(0.5)
	check(colony.load_state(snap), "Colony with ships and lanes loads")
	var s2 := sh.ship(s.id)
	check(not s2.is_empty() and s2.state == "sailing" and is_equal_approx(float(s2.s), at) and JSON.stringify(s2.cargo) == JSON.stringify(cargo), "Ship position along its route and cargo survive save/load")
	check(sh.lanes.size() == snap.economy.shipping.lanes.size() and sh.lane(s2.lane).out.has("stone"), "Lanes and cargo rules survive save/load")
	var bad: Dictionary = snap.duplicate(true)
	bad.economy.shipping.ships[0].cargo = {"stone": 900}
	check(not colony.accepts(bad), "An overloaded ship in a save is refused")


func perf() -> void:
	for i in range(12):
		var s := sh.add_ship("coaster", ["core", "puerto_alto"][i % 2])
		s.timer = 0.0
		if i < sh.lanes.size() * 12: sh.assign(s.id, sh.lanes[0].id)
	var total := 0; var worst := 0
	for i in range(1200):
		var a := Time.get_ticks_usec()
		econ._process(1.0 / 60.0)
		var d := Time.get_ticks_usec() - a
		total += d; worst = maxi(worst, d)
	print("  economy + %d ships, %d lanes: per frame avg %.3f ms, worst %.3f ms" % [sh.ships.size(), sh.lanes.size(), total / 1200000.0, worst / 1000.0])
	check(worst < 1000, "Economy + shipping under 1 ms in any frame (worst %.3f ms)" % (worst / 1000.0))
