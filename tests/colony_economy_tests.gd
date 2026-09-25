extends Node
## The colony economy in the booted game: production chains conserve goods over time, needs drive
## happiness, growth and decline, placement rules, founding an outer colony, construction stages
## and their models, porters as townsfolk near the viewer, far colonies ticking by rates, the
## tick budget, and the v2 save (and the v1 migration).
var failures := 0
var checks := 0
var game: Game
var econ: ColonyEconomy


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
	for i in range(3): await get_tree().physics_frame
	chains()
	needs()
	await placement()
	await founding()
	await views()
	perf()
	persistence()
	print("COLONY ECONOMY %d checks / %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)


## A detached town (pure rules) round a hall at the origin.
func _town(cid: String, pop: int) -> ColonyTown:
	var t := ColonyTown.new(cid)
	t.founded = true
	t.add_building("colony_hall", Vector3.ZERO, 0.0, true)
	for i in range(pop): t.add_colonist(1000 + i)
	return t


static func _total(t: ColonyTown, item: String) -> int:
	var n := t.count(item)
	for b in t.buildings:
		n += int(b.inbuf.get(item, 0)) + int(b.outbuf.get(item, 0))
		if not b.carry.is_empty(): n += int(b.carry.load.get(item, 0))
	return n


func chains() -> void:
	# sawmill: 2 timber -> 2 planks; nothing made or lost on the way
	var t := _town("valdoro", 2)
	t.stock = {"wood": 20, "bread": 200}
	var mill := t.add_building("sawmill", Vector3(40, 0, 0), 0.0, true)
	t.assign()
	check(t.workers_at(mill.id) == 2, "Colonists take the sawmill's two jobs")
	var start_wood := _total(t, "wood")
	for i in range(1200): t.tick(0.25)
	var planks := _total(t, "planks")
	var in_cycle := 2 if float(mill.cycle) > 0.0 else 0
	print("  sawmill: wood %d -> %d, planks %d, stock %s" % [start_wood, _total(t, "wood"), planks, t.stock])
	check(planks >= 8 and t.count("planks") > 0, "Sawmill turns timber into planks over time (%d planks in 300 s)" % planks)
	check(_total(t, "wood") + planks + in_cycle == start_wood, "Timber in = planks out (porters carry both ways, nothing lost)")
	# grain -> flour -> bread from nothing but a farm
	var c := _town("campo_real", 6)
	c.stock = {"bread": 100}
	for type in ["grain_farm", "flour_mill", "bakery"]:
		c.add_building(type, Vector3(30 + c.buildings.size() * 20, 0, 0), 0.0, true)
	c.assign()
	var bread0 := c.count("bread")
	for i in range(2400): c.tick(0.25)
	var bakery := c.building_of_type("bakery")
	print("  campo chain: grain %d flour %d bread made %d" % [_total(c, "grain"), _total(c, "flour"), int(bakery.produced)])
	check(int(bakery.produced) > 0, "Grain farm -> flour mill -> bakery makes bread in 10 minutes (%d)" % int(bakery.produced))
	check(int(c.building_of_type("flour_mill").produced) > 0, "The mill ground the farm's grain")
	# smithy needs two inputs from two chains
	var s := _town("valdoro", 2)
	s.stock = {"ore": 10, "planks": 10, "bread": 50}
	var smithy := s.add_building("smithy", Vector3(25, 0, 0), 0.0, true)
	s.assign()
	for i in range(1200): s.tick(0.25)
	check(int(smithy.produced) >= 2 and _total(s, "ore") + int(smithy.produced) * 2 + (2 if float(smithy.cycle) > 0.0 else 0) == 10, "Smithy uses ore and planks for tools (%d tools)" % int(smithy.produced))
	# a building with no inputs waits, and says so
	var w := _town("valdoro", 2)
	w.stock = {"bread": 50}
	var idle := w.add_building("mason", Vector3(20, 0, 0), 0.0, true)
	w.assign()
	for i in range(200): w.tick(0.25)
	check(int(idle.produced) == 0 and w.status(idle).begins_with("Waiting for stone"), "Mason's yard without stone waits (%s)" % w.status(idle))
	# raw producers are regional
	check(EconomyCatalog.buildable_in("valdoro", "woodcutter") and not EconomyCatalog.buildable_in("sarmada", "woodcutter"), "Timber only where there is forest (Valdoro yes, Sarmada no)")
	check(EconomyCatalog.buildable_in("sarmada", "cotton_field") and not EconomyCatalog.buildable_in("valdoro", "cotton_field"), "Cotton only at the Sarmada oasis")


func needs() -> void:
	# well fed, housed, with goods: happy, and it grows
	var t := _town("isola_serena", 6)
	t.stock = {"bread": 200, "fish": 200, "preserved_fish": 100, "olive": 100, "cloth": 40, "tools": 40, "oil": 40, "wine": 40}
	for i in range(3): t.add_building("cottage", Vector3(30 + i * 20, 0, 0), 0.0, true)
	t.assign()
	var pop := t.colonists.size()
	for i in range(1600): t.tick(0.25)
	print("  thriving: happiness %.0f needs %s pop %d -> %d" % [t.happiness, t.needs, pop, t.colonists.size()])
	check(t.needs.food > 0.95 and t.needs.variety > 0.9 and t.needs.goods > 0.9, "Food, variety and goods needs met from the stockpile")
	check(t.happiness > 80.0, "Happiness follows the needs (%.0f)" % t.happiness)
	check(t.colonists.size() > pop, "Happy, housed colonies grow (%d -> %d)" % [pop, t.colonists.size()])
	check(t.count("bread") < 200 and t.count("preserved_fish") < 100 and t.count("wine") < 40, "Colonists eat and use goods")
	var grown: Dictionary = t.colonists[t.colonists.size() - 1]
	check(CharacterLook.from_seed(int(grown.seed), t.style, "porter").style == &"isola", "New colonists are townsfolk in the town's style")
	# no food, no houses: unhappy, and people leave
	var s := _town("sarmada", 8)
	s.stock = {}
	s.building_of_type("colony_hall").paused = true     # no kitchen garden either
	s.assign()
	var pop_s := s.colonists.size()
	for i in range(2400): s.tick(0.25)
	print("  starving: happiness %.0f pop %d -> %d" % [s.happiness, pop_s, s.colonists.size()])
	check(s.happiness < 30.0 and s.needs.food < 0.1, "Hunger makes a colony unhappy (%.0f)" % s.happiness)
	check(s.colonists.size() < pop_s and s.colonists.size() >= 2, "Unhappy colonies decline (%d -> %d)" % [pop_s, s.colonists.size()])
	# taxes from a happy colony reach the courier's wallet
	var coins := game.gm.coins
	var core := econ.town("core")
	core.coins_due = 3.4
	econ.tick(0.01)
	check(game.gm.coins == coins + 3, "Colony taxes are paid into the courier's wallet")


func _find_site(cid: String, type: String, near: Vector3, from: float, to: float) -> Variant:
	for r in range(int(from), int(to), 12):
		for k in range(24):
			var a := TAU * k / 24.0
			var p := near + Vector3(cos(a) * r, 0, sin(a) * r)
			var y: float = atan2(near.x - p.x, near.z - p.z)
			if econ.check_site(cid, type, p, y) == "": return [p, y]
	return null


func _focus(p: Vector3) -> void:
	game.bike.global_position = p + Vector3(0, 40, 0)
	game.world.set_focus(game.bike)
	game.world.streamer.load_all_pending()


func placement() -> void:
	var core := econ.town("core")
	_focus(core.hall)
	for i in range(10): await get_tree().physics_frame
	var road: Vector3 = game.world.terrain.nearest_road(core.hall + Vector3(40, 0, 0)).point
	check(econ.check_site("core", "cottage", road, 0.0).contains("road"), "No building on a road (%s)" % econ.check_site("core", "cottage", road, 0.0))
	var sea := Vector3(262, 0, -40)
	check(econ.check_site("core", "cottage", sea, 0.0).contains("dry"), "No building in the water (%s)" % econ.check_site("core", "cottage", sea, 0.0))
	check(econ.check_site("core", "cottage", core.hall + Vector3(800, 0, 0), 0.0).contains("build area"), "No building outside the build area")
	check(econ.check_site("sarmada", "cottage", Vector3(2700, 0, 8600), 0.0).contains("Found"), "No building before the charter")
	check(econ.check_site("core", "cotton_field", core.hall + Vector3(60, 0, 60), 0.0).contains("cotton"), "No cotton field where there is no cotton")
	var site: Variant = _find_site("core", "cottage", core.hall, 30.0, 300.0)
	check(site != null, "A clear, flat, dry site exists round the villa")
	if site == null: return
	var coins := game.gm.coins
	game.gm.coins = 500
	var planks := core.count("planks")
	check(econ.place("core", "cottage", site[0], site[1]) == "", "Cottage placed")
	var b: Dictionary = core.buildings[core.buildings.size() - 1]
	check(game.gm.coins == 500 - 20 and core.count("planks") == planks - 6, "The cottage cost 20 coins and 6 planks")
	check(econ.check_site("core", "cottage", site[0], site[1]).begins_with("Overlaps"), "Buildings cannot overlap")
	# a steep site somewhere round the core is refused for its slope
	var steep := false
	for k in range(400):
		var p := core.hall + Vector3(cos(k * 2.4) * (40 + k), 0, sin(k * 2.4) * (40 + k))
		if econ.check_site("core", "cottage", p, 0.0).begins_with("Too steep"): steep = true; break
	check(steep, "Steep ground is refused")
	# construction: foundation, scaffold, then built
	check(not b.built and ColonyViews.stage_key(b) == "found", "New building starts as a staked foundation")
	var stages := {}
	for i in range(120):
		econ.tick(0.25)
		stages[ColonyViews.stage_key(b)] = true
	check(b.built and stages.has("found") and stages.keys().any(func(k): return String(k).begins_with("scaffold")), "Foundation -> scaffold -> built (%s)" % [str(stages.keys())])
	game.gm.coins = coins


func founding() -> void:
	var t := econ.town("puerto_alto")
	check(not t.founded and econ.found("puerto_alto") != "", "A town must be visited before its charter")
	# ride there: discovery happens by visiting
	var pz: Vector3 = econ.game.world.database.location_pos(&"puerto_alto")
	game.player.global_position = pz
	game.rider._set_mode(Rider.Mode.ON_FOOT)
	_focus(pz)
	for i in range(10): await get_tree().physics_frame
	econ._check_discovery()
	check(t.discovered, "Visiting Puerto Alto discovers it")
	game.gm.coins = 50
	check(econ.found("puerto_alto").contains("coins"), "A charter needs its coins")
	game.gm.coins = 500
	econ.ensure_shipping()
	var err := econ.found("puerto_alto")
	check(err == "" and t.founded, "Puerto Alto founded (%s)" % err)
	check(game.gm.coins == 500 - econ.charter_cost("puerto_alto"), "The charter cost %d coins" % econ.charter_cost("puerto_alto"))
	var hall := t.building_of_type("colony_hall")
	check(not hall.is_empty() and hall.built, "The charter raised a colony hall and warehouse")
	check(t.colonists.size() == EconomyCatalog.CHARTER_SETTLERS and t.count("planks") == 30, "Settlers and a starter stock arrived")
	var berth: Vector3 = econ.shipping.ports.puerto_alto.berth
	print("  Puerto Alto hall at %s, %.0f m from the berth" % [t.hall, Vector2(t.hall.x - berth.x, t.hall.z - berth.z).length()])
	check(Vector2(t.hall.x - berth.x, t.hall.z - berth.z).length() < 700.0, "The hall stands near the port")
	check(econ._obstacle_hit("puerto_alto", Vector2(t.hall.x, t.hall.z), 1.0) == "", "The hall is clear of plots, streets and landmarks")
	# a site in town (on the plots) is refused
	var plaza: Vector3 = pz
	check(econ.check_site("puerto_alto", "cottage", plaza, 0.0) != "", "No building on the plaza (%s)" % econ.check_site("puerto_alto", "cottage", plaza, 0.0))


func views() -> void:
	var t := econ.town("puerto_alto")
	var yard: Variant = _find_site("puerto_alto", "fishing_hut", t.hall, 20.0, 320.0)
	check(yard != null, "A fishing hut site by the water in Puerto Alto")
	if yard == null: return
	check(econ.place("puerto_alto", "fishing_hut", yard[0], yard[1]) == "", "Fishing hut placed")
	var hut: Dictionary = t.buildings[t.buildings.size() - 1]
	for i in range(200): econ.tick(0.25)
	check(hut.built, "Fishing hut built")
	for i in range(200): econ.tick(0.25)
	_focus(Vector3(float(hut.x), 0, float(hut.z)))
	var v := econ.views
	for f in range(40):
		await get_tree().process_frame
		if v.buildings.has(hut.id) and v.buildings[hut.id].key == "built": break
	check(v.buildings.has(hut.id), "The built fishing hut has a model near the viewer")
	if v.buildings.has(hut.id):
		var node: Node3D = v.buildings[hut.id].node
		var meshes := node.find_children("*", "MeshInstance3D", true, false).size() + node.find_children("*", "MultiMeshInstance3D", true, false).size()
		check(meshes >= 2 and node.find_children("*", "StaticBody3D", true, false).size() >= 1, "Building = BuildingKit plot + yard props + collision (%d meshes)" % meshes)
	# porters and workers: townsfolk near the viewer, capped
	for f in range(30): await get_tree().process_frame
	print("  people near Puerto Alto: %d" % v.people.size())
	check(v.people.size() > 0 and v.people.size() <= ColonyViews.MAX_PEOPLE, "Colonists walk and work near the viewer (%d, cap %d)" % [v.people.size(), ColonyViews.MAX_PEOPLE])
	var styled := true
	for id in v.people:
		var m: RiderModel = v.people[id].model
		if m.look.get("style") != &"puerto": styled = false
	check(styled, "Colonists wear Puerto Alto's style")
	# far away: no bodies, no buildings drawn, but production goes on
	_focus(Vector3(-8000, 0, -8000))
	for f in range(20): await get_tree().process_frame
	check(v.people.is_empty() and not v.buildings.has(hut.id), "Far colonies have no bodies or models")
	var made := int(hut.produced)
	for i in range(400): econ.tick(0.25)
	check(int(hut.produced) > made, "Far colonies keep producing by rates (%d -> %d fish)" % [made, int(hut.produced)])


func perf() -> void:
	# every town a busy colony: the whole economy ticks in well under a millisecond
	var saved := econ.save_state()
	for cid in econ.towns:
		var t := econ.town(cid)
		if not t.founded:
			t.founded = true; t.discovered = true
			t.add_building("colony_hall", t.hall, 0.0, true)
		for i in range(24): t.add_colonist(i * 31 + 7)
		for type in ["sawmill", "mason", "bakery", "flour_mill", "grain_farm", "smithy", "weaver", "smokehouse", "fishing_hut", "cottage", "cottage", "townhouse", "warehouse", "olive_press", "winery"]:
			t.add_building(type, t.hall + Vector3(30 + t.buildings.size() * 3, 0, 20), 0.0, true)
		for item in EconomyCatalog.ITEMS: t.stock[item] = 40
		t.assign()
	# a whole-country tick at once (what tests and tools do)
	var total := 0
	for i in range(100):
		var a := Time.get_ticks_usec()
		econ.tick(0.25)
		total += Time.get_ticks_usec() - a
	var whole := total / 100.0 / 1000.0
	# the game's frames: one town at a time, round robin, each at 4 Hz
	var times: Array[int] = []
	total = 0
	for i in range(1200):
		var a := Time.get_ticks_usec()
		econ._process(1.0 / 60.0)
		var d := Time.get_ticks_usec() - a
		total += d; times.append(d)
	times.sort()
	var p99: int = times[int(times.size() * 0.995)]
	print("  economy (6 colonies, %d buildings, %d colonists): whole-country tick %.3f ms; per frame avg %.3f ms, 99.5th percentile %.3f ms, worst %.3f ms" % [econ.towns.size() * 16, econ.towns.size() * 24, whole, total / 1200000.0, p99 / 1000.0, times[-1] / 1000.0])
	check(p99 < 1000 and times[-1] < 2000, "Economy costs under 1 ms a frame (99.5th percentile %.3f ms, avg %.3f ms)" % [p99 / 1000.0, total / 1200000.0])
	econ.load_state(JSON.parse_string(JSON.stringify(saved)))


func persistence() -> void:
	var colony := game.colony
	var before := colony.save_state()
	var json: Dictionary = JSON.parse_string(JSON.stringify(before))
	check(int(json.version) == ColonySystem.SAVE_VERSION and json.has("economy"), "Colony save is version %d with the economy" % ColonySystem.SAVE_VERSION)
	check(colony.accepts(json), "Saved colony validates after JSON")
	var t := econ.town("puerto_alto")
	var stock := t.stock.duplicate(); var pop := t.colonists.size(); var nb := t.buildings.size()
	t.stock = {}; t.colonists.clear()
	check(colony.load_state(json), "Colony + economy load")
	t = econ.town("puerto_alto")
	check(t.founded and t.colonists.size() == pop and t.buildings.size() == nb and JSON.stringify(t.stock) == JSON.stringify(stock), "Colonies, buildings, stocks and colonists survive save/load")
	check(JSON.stringify(colony.save_state().economy) == JSON.stringify(before.economy), "Economy round trip is exact")
	# a broken record is mended, not the whole economy thrown away (review M-4): the bad
	# building goes, the colony keeps its hall, every other colony loads, and the load says so
	var bad: Dictionary = json.duplicate(true)
	bad.economy.towns.core.buildings[0].type = "castle"
	check(colony.load_state(bad) and econ.town("puerto_alto").founded and not econ.town("core").building_of_type("colony_hall").is_empty() and not colony.load_report().is_empty(),
		"A damaged economy record is mended and reported; the rest loads (%s)" % [colony.load_report()])
	# v1 -> v2: an old save loads, the economy starts fresh round its warehouse
	var v1: Dictionary = json.duplicate(true)
	v1.erase("economy"); v1.version = 1
	v1.warehouse = {"wood": 33, "berry": 2, "stone": 0, "ore": 0, "olive": 5}
	check(colony.load_state(v1), "A v1 colony save still loads")
	check(int(colony.warehouse.wood) == 33 and econ.town("core").count("wood") == 33, "The v1 warehouse becomes the core colony's stockpile")
	check(not econ.town("puerto_alto").founded and econ.town("core").founded, "v1 migration: the economy starts at its beginning")
	check(colony.load_state(json) and econ.town("puerto_alto").founded, "Back to the v2 save")
	# through the real save file
	check(Saves.save_game("colony_economy_test"), "Saved through the Saves provider")
	econ.town("puerto_alto").stock = {}
	check(Saves.load_game("colony_economy_test") and JSON.stringify(econ.town("puerto_alto").stock) == JSON.stringify(stock), "Loaded through the Saves provider")
