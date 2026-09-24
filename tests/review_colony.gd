extends Node
## REVIEW PROBE (adversarial QA): the colony sim and shipping lanes, played through their interfaces.
##  A  charter every town: time spent in found() (hitch), where the hall lands
##  B  how much of each colony's build area can actually take a cottage
##  C  a freshly chartered colony left alone: does it thrive, starve or shrink?
##  D  a lane with a ship mid-voyage: save, keep playing, load -> is the voyage restored?
##  E  save-format fragility: one out-of-range field in one town
##  F  the Mayor view readouts at 1280x720 vs 1600x900 are checked by the render tool, not here
## Run: godot --headless --path . -- --test=review_colony

var game: Game
var econ: ColonyEconomy
var fails := 0


func _ready() -> void:
	game = Game.current
	call_deferred("_run")


func _say(s: String) -> void:
	print("[review] ", s)


func _flag(cond: bool, label: String) -> void:
	print(("  OK   " if cond else "  BUG  ") + label)
	if not cond: fails += 1


func _frames(n: int) -> void:
	for i in n: await get_tree().physics_frame


func _focus(p: Vector3) -> void:
	game.bike.global_position = Vector3(p.x, game.world.terrain.height_at(p.x, p.z) + 40.0, p.z)
	game.world.set_focus(game.bike)
	game.world.outer.refresh_collision()
	game.world.streamer.load_all_pending()


func _run() -> void:
	econ = game.colony.economy
	game.use_scripted_controls()
	econ.ensure_shipping()
	econ.shipping.wait()
	await _frames(5)
	game.gm.coins = 100000
	var towns := ["puerto_alto", "valdoro", "sarmada", "isola_serena", "campo_real"]
	# ------------------------------------------------------------------ A: charters
	for cid in towns:
		var t := econ.town(cid)
		var pz: Vector3 = game.world.database.location_pos(StringName(cid))
		_focus(pz)
		await _frames(3)
		econ.discover(cid)
		var t0 := Time.get_ticks_usec()
		var err := econ.found(cid)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		var d := Vector2(t.hall.x - pz.x, t.hall.z - pz.z).length()
		_say("A: charter %s: %s in %.0f ms; hall at %s, %.0f m from the plaza ring" % [cid, err if err != "" else "ok", ms, t.hall, d])
		_flag(ms < 50.0, "A: chartering %s does not hitch (%.0f ms in one frame)" % [cid, ms])
		_flag(d < 450.0, "A: %s's colony hall is in or next to the town (%.0f m from the plaza)" % [cid, d])
	# ------------------------------------------------------------------ B: usable build area
	for cid in towns:
		var t := econ.town(cid)
		_focus(t.hall)
		await _frames(3)
		var r := EconomyCatalog.build_radius(cid)
		var ok := 0; var n := 0
		var why := {}
		var t0 := Time.get_ticks_usec()
		var worst := 0.0
		var x := -r
		while x <= r:
			var z := -r
			while z <= r:
				if Vector2(x, z).length() <= r:
					var p := t.hall + Vector3(x, 0, z)
					var c0 := Time.get_ticks_usec()
					var w := econ.check_site(cid, "cottage", p, 0.0)
					worst = maxf(worst, (Time.get_ticks_usec() - c0) / 1000.0)
					n += 1
					if w == "": ok += 1
					else:
						var k := w.split(":")[0].split("(")[0]
						why[k] = int(why.get(k, 0)) + 1
				z += 20.0
			x += 20.0
		_say("B: %s build area %d m: %d of %d cottage sites valid (%.0f %%); worst check_site %.2f ms; avg %.2f ms; reasons %s" % [cid, int(r), ok, n, 100.0 * ok / maxf(n, 1), worst, (Time.get_ticks_usec() - t0) / 1000.0 / maxf(n, 1), why])
	# ------------------------------------------------------------------ C: left alone
	for cid in ["puerto_alto", "valdoro", "sarmada"]:
		var t := econ.town(cid)
		var line := ""
		for m in range(0, 61):
			if m % 10 == 0: line += " [%dmin pop %d hap %.0f food %.2f stock food %d]" % [m, t.colonists.size(), t.happiness, t.needs.food, _food(t)]
			for i in range(240): t.tick(0.25)
		_say("C: %s left alone for 60 game minutes after the charter:%s" % [cid, line])
	# ------------------------------------------------------------------ D: a voyage across save/load
	var sh := econ.shipping
	var pa := econ.town("puerto_alto")
	pa.stock["planks"] = 200; pa.stock["blocks"] = 100; pa.stock["tools"] = 30; pa.stock["fish"] = 200
	var lane := econ.add_lane("core", "puerto_alto", {"olive": 20}, {"fish": 30})
	var ship := sh.add_ship("coaster", "puerto_alto")
	_flag(not lane.is_empty() and not ship.is_empty(), "D: a lane core <-> Puerto Alto and a coaster")
	if not lane.is_empty() and not ship.is_empty():
		sh.assign(ship.id, lane.id)
		econ.town("core").stock["olive"] = 100
		var seen_sail := false
		for i in range(2400):
			econ.tick(0.5)
			if ship.state == "sailing" and float(ship.s) > 400.0: seen_sail = true; break
		var snap := {"state": ship.state, "leg": ship.leg, "s": ship.s, "cargo": (ship.cargo as Dictionary).duplicate(), "pa_fish": pa.count("fish"), "core_olive": econ.town("core").count("olive"), "bpa": pa.buildings.size(), "pop": pa.colonists.size()}
		_say("D: before save: %s" % snap)
		Saves.save_game("review_colony")
		for i in range(400): econ.tick(0.5)
		pa.stock["fish"] = 3
		_say("D: 200 s later: state %s leg %s s %.0f" % [ship.state, ship.leg, float(ship.s)])
		var loaded := Saves.load_game("review_colony")
		await _frames(2)
		var s2: Dictionary = sh.ship(ship.id)
		var after := {"state": s2.get("state"), "leg": s2.get("leg"), "s": s2.get("s"), "cargo": s2.get("cargo"), "pa_fish": pa.count("fish") if econ.town("puerto_alto") == pa else econ.town("puerto_alto").count("fish"), "core_olive": econ.town("core").count("olive"), "bpa": econ.town("puerto_alto").buildings.size(), "pop": econ.town("puerto_alto").colonists.size()}
		_say("D: after load (%s): %s" % [loaded, after])
		_flag(seen_sail and str(after.state) == str(snap.state) and absf(float(after.s) - float(snap.s)) < 1.0 and int(after.pa_fish) == int(snap.pa_fish), "D: the voyage, cargo and stock come back from the save")
		# ------------------------------------------------------------------ E: fragility
		var path := Saves.path_for("review_colony")
		var txt := FileAccess.get_file_as_string(path)
		var data: Dictionary = JSON.parse_string(txt)
		var colony: Dictionary = data.systems.colony
		colony.economy.towns.valdoro.happiness = 100.5     # one float just outside its range, in one town
		var f := FileAccess.open(Saves.path_for("review_colony_bad"), FileAccess.WRITE)
		f.store_string(JSON.stringify(data)); f.close()
		# change the live state so we can see whether anything loads
		var before_b := econ.town("puerto_alto").buildings.size()
		econ.town("puerto_alto").stock["fish"] = 777
		var ok := Saves.load_game("review_colony_bad")
		await _frames(2)
		_say("E: load of a save with valdoro.happiness = 100.5 returned %s; puerto_alto fish now %d (777 = the colony section was silently ignored), buildings %d" % [ok, econ.town("puerto_alto").count("fish"), econ.town("puerto_alto").buildings.size()])
		_flag(econ.town("puerto_alto").count("fish") != 777, "E: one bad field in one town does not silently discard every colony (fish %d)" % econ.town("puerto_alto").count("fish"))
	print("REVIEW COLONY: %d findings" % fails)
	get_tree().quit(0)


func _food(t: ColonyTown) -> int:
	var n := 0
	for f in EconomyCatalog.FOODS: n += t.count(f)
	return n
