class_name ColonyEconomy
extends Node3D
## The colony-sim layer over the courier game: every town can be a colony (ColonyTown), sea
## lanes carry goods between the port colonies (ShippingNetwork), and the near part of it is drawn
## (ColonyViews: buildings, porters, ships, the Mayor map overlay).
##
## The rule of the codebase holds: nothing here cares whether a town is loaded. The whole economy
## ticks at TICK_HZ by rates; the views read the same records.
##
## Interface (ColonySystem owns one; the Mayor view and the tests talk to it):
##   town(id) -> ColonyTown                 towns: Dictionary
##   discover(id) / found(id) -> ""|error   charter_cost(id)
##   check_site(id, type, pos, yaw) -> ""|reason   place(id, type, pos, yaw) -> ""|error
##   remove(id, building id)                toggle_pause(id, building id)
##   shipping: ShippingNetwork              build_ship(id, type) / add_lane(...) (costs checked here)
##   tick(dt)                               save_state() / valid(d) / load_state(d)

signal changed
signal notified(text: String)

const TICK_HZ := 4.0
const DISCOVER_EVERY := 1.0
const SETTLER_SEED := 7919

var system: ColonySystem
var game: Game
var towns: Dictionary = {}
var shipping := ShippingNetwork.new()
var views: ColonyViews
var time_scale := 1.0
var notifications: Array = []          # [{colony, text}] newest last
var tick_us := 0                       # the last economy tick
var tick_us_max := 0
var ticks := 0
var ports_ready := false
var _pending: Dictionary = {}          # colony id -> seconds owed (scaled)
var _ship_pending := 0.0
var _rr := 0
var _discover_t := 0.0
var _obstacles: Dictionary = {}        # colony id -> {cell: Array of [Vector2, r]}
var _town_plan: Dictionary = {}        # colony id -> plan.json town record
var _coins_local := 500                # the wallet when there is no courier (unit tests)


## Data only (no world): the core colony round `hall`.
func setup_core(p_system: ColonySystem, hall: Vector3) -> void:
	system = p_system
	for cid in EconomyCatalog.COLONIES:
		var t := ColonyTown.new(cid)
		towns[cid] = t
	var core: ColonyTown = towns.core
	core.founded = true; core.discovered = true
	core.hall = hall
	var h := core.add_building("colony_hall", hall, 0.0, true)
	h["virtual"] = true      # the core's hall is the original colony warehouse
	core.stock = system.warehouse
	for i in range(4): core.add_colonist(SETTLER_SEED * (i + 1))
	core.assign()
	shipping.towns = func(cid: String) -> ColonyTown: return town(cid)


## The world: town records, ports, the sea grid (built on a worker thread), the views.
func setup_world(p_game: Game) -> void:
	game = p_game
	var outer: OuterWorld = game.world.outer
	if outer != null and outer.ok:
		var plan := outer.plan()
		for t in plan.get("towns", []):
			if towns.has(t.id):
				_town_plan[t.id] = t
				var pz: Array = t.plaza
				(towns[t.id] as ColonyTown).hall = Vector3(pz[0], pz[1], pz[2])
		shipping.plan_lanes = plan.get("sea_lanes", [])
		shipping.ground = func(x: float, z: float) -> float: return game.world.terrain.height_at(x, z)
		shipping.pirates = _pirate_camps
		shipping.start_async(outer.ground, func(x: float, z: float) -> float: return game.world.terrain.height_at(x, z))
	views = ColonyViews.new(); views.name = "ColonyViews"; add_child(views)
	views.setup(self)
	if Events.has_signal("camp_cleared"): Events.camp_cleared.connect(func(_id): shipping.pirates_changed(); changed.emit())


func _pirate_camps() -> Array:
	var out: Array = []
	if game == null or game.encounters == null: return out
	for id in game.encounters.camps:
		var c: Dictionary = game.encounters.camps[id]
		if c.kind == &"pirate" and not c.get("transient", false) and not game.encounters.is_cleared(id):
			out.append({"id": String(id), "pos": c.pos})
	return out


## Block until the sea grid is built and the ports are registered (tests, the Trade panel).
func ensure_shipping() -> bool:
	if ports_ready: return true
	if game == null: return false
	shipping.wait()
	return _register_ports()


func _register_ports() -> bool:
	if not shipping.poll(): return false
	var plan: Dictionary = game.world.outer.plan()
	for p in plan.get("ports", []):
		var cid := String(p.town)
		if towns.has(cid):
			var b: Array = p.berth
			var quay: Array = _town_plan[cid].get("quay_edges", []) if _town_plan.has(cid) else []
			if not shipping.add_port(cid, Vector3(b[0], b[1], b[2]), float(p.heading_deg), quay):
				push_warning("[colony] port %s has no water approach" % cid)
	ports_ready = true
	return true


func town(cid: String) -> ColonyTown:
	var t: ColonyTown = towns.get(cid)
	if t != null and cid == "core" and system != null: t.stock = system.warehouse
	return t


func has_port(cid: String) -> bool:
	return shipping.ports.has(cid) if ports_ready else cid in ["core", "puerto_alto", "sarmada", "isola_serena"]


# ------------------------------------------------------------------ the wallet
func coins() -> int:
	return game.gm.coins if game != null else _coins_local


func spend(n: int) -> bool:
	if n <= 0: return true
	if game != null: return game.gm.spend_coins(n)
	if _coins_local < n: return false
	_coins_local -= n
	return true


func earn(n: int) -> void:
	if n <= 0: return
	if game != null:
		game.gm.coins += n
		game.gm.wallet_changed.emit(game.gm.coins)
	else: _coins_local += n


# ------------------------------------------------------------------ discovery and charters
func charter_cost(cid: String) -> int:
	return int(EconomyCatalog.COLONIES.get(cid, {}).get("charter", 0))


func discover(cid: String) -> void:
	var t := town(cid)
	if t == null or t.discovered: return
	t.discovered = true
	_notify(cid, "%s discovered - a colony charter costs %d coins (Mayor view, F4)." % [t.display_name, charter_cost(cid)], true)
	changed.emit()


## Found the colony: pay the charter, raise the hall on a clear site, bring the settlers.
func found(cid: String, force := false) -> String:
	var t := town(cid)
	if t == null: return "No such town."
	if t.founded: return "%s is already a colony." % t.display_name
	if not t.discovered and not force: return "Visit %s first." % t.display_name
	var site: Variant = find_hall_site(cid)
	if site == null: return "No clear ground for a colony hall near %s." % t.display_name
	if coins() < charter_cost(cid): return "A charter costs %d coins (you have %d)." % [charter_cost(cid), coins()]
	spend(charter_cost(cid))
	t.discovered = true; t.founded = true
	t.hall = site.pos
	var hall := t.add_building("colony_hall", site.pos, site.yaw, true)
	hall["ground"] = ground_min(site.pos, "colony_hall", site.yaw)
	for item in EconomyCatalog.CHARTER_STOCK: t.stock[item] = int(EconomyCatalog.CHARTER_STOCK[item])
	for i in range(EconomyCatalog.CHARTER_SETTLERS): t.add_colonist(hash([cid, i, SETTLER_SEED]))
	t.assign()
	_notify(cid, "%s is chartered: a colony hall, %d settlers and a starter stock." % [t.display_name, EconomyCatalog.CHARTER_SETTLERS], true)
	changed.emit()
	return ""


## The nearest clear site to the port (or the plaza) for the colony hall.
func find_hall_site(cid: String) -> Variant:
	var t := town(cid)
	var centre := t.hall
	if shipping.ports.has(cid):
		var berth: Vector3 = shipping.ports[cid].berth
		centre = berth
	elif _town_plan.has(cid) and cid != "core":
		var pz: Array = _town_plan[cid].plaza
		centre = Vector3(pz[0], pz[1], pz[2])
	for r in range(40, 1000, 20):
		var n := maxi(12, int(TAU * r / 30.0))
		for k in range(n):
			var a := TAU * k / n
			var p := Vector3(centre.x + cos(a) * r, 0, centre.z + sin(a) * r)
			var yaw := atan2(centre.x - p.x, centre.z - p.z)   # the front faces the port / plaza
			if check_site(cid, "colony_hall", p, yaw, true) == "":
				p.y = _pad(p, "colony_hall", yaw)
				return {"pos": p, "yaw": yaw}
	return null


# ------------------------------------------------------------------ placement
## The site's footprint: [half width, half depth] (the building plus its yard).
static func footprint(type: String) -> Vector2:
	var def := EconomyCatalog.building(type)
	var yard := ColonyProps.yard_width(String(def.get("prop", "")))
	return Vector2((float(def.w) + yard) * 0.5 + 0.6, float(def.d) * 0.5 + 1.5)


static func site_points(type: String, at: Vector3, yaw: float) -> PackedVector2Array:
	var f := footprint(type)
	var basis := Basis(Vector3.UP, yaw)
	var pts := PackedVector2Array()
	for sx in [-1.0, 0.0, 1.0]:
		for sz in [-1.0, 0.0, 1.0]:
			var v := basis * Vector3(sx * f.x, 0, sz * f.y)
			pts.append(Vector2(at.x + v.x, at.z + v.z))
	for sx in [-0.5, 0.5]:
		for sz in [-1.0, 1.0]:
			var v := basis * Vector3(sx * f.x, 0, sz * f.y)
			pts.append(Vector2(at.x + v.x, at.z + v.z))
	return pts


func _height(x: float, z: float) -> float:
	if system != null and system._test_height.is_valid(): return float(system._test_height.call(Vector2(x, z)))
	if game != null: return game.world.terrain.height_at(x, z)
	return 2.0


## The pad a site stands on: the highest ground under the building.
func _pad(at: Vector3, type: String, yaw: float) -> float:
	var hi := -INF
	for p in site_points(type, at, yaw): hi = maxf(hi, _height(p.x, p.y))
	return hi


func ground_min(at: Vector3, type: String, yaw: float) -> float:
	var lo := INF
	for p in site_points(type, at, yaw): lo = minf(lo, _height(p.x, p.y))
	return lo


## Why a building cannot stand here ("" when it can): colony, region, build area, dry flat
## ground, clear of roads, streets, plots, landmarks, locations and other colony buildings, by
## the water for coast buildings, near the berth for the shipyard, and (when the world is
## loaded there) clear of anything solid.
func check_site(cid: String, type: String, at: Vector3, yaw: float, founding := false) -> String:
	var t := town(cid)
	var def := EconomyCatalog.building(type)
	if t == null or def.is_empty(): return "Unknown building."
	if not founding:
		if not t.founded: return "Found the colony first."
		if not EconomyCatalog.buildable_in(cid, type):
			return "%s needs %s, which %s does not have." % [def.name, EconomyCatalog.item_name(String(def.get("raw", ""))).to_lower(), t.display_name] if def.has("raw") else "Cannot be built."
		if Vector2(at.x - t.hall.x, at.z - t.hall.z).length() > EconomyCatalog.build_radius(cid): return "Outside the colony's build area (%d m round the hall)." % int(EconomyCatalog.build_radius(cid))
		if t.buildings.size() >= ColonyTown.MAX_BUILDINGS: return "The colony has reached its building limit."
	if not at.is_finite() or maxf(absf(at.x), absf(at.z)) > 12400.0: return "Outside the country."
	var pts := site_points(type, at, yaw)
	var lo := INF; var hi := -INF
	for p in pts:
		var h := _height(p.x, p.y)
		lo = minf(lo, h); hi = maxf(hi, h)
	if lo < 0.6: return "Needs dry ground (water or shore here)."
	if hi - lo > 1.8: return "Too steep: needs flat ground (%.1f m of slope)." % (hi - lo)
	var f := footprint(type)
	var reach := f.length()
	if game != null:
		var n := game.world.terrain.normal_at(at.x, at.z)
		if n.y < 0.9: return "Too steep."
		var road := game.world.terrain.nearest_road(Vector3(at.x, 0, at.z))
		var rp: Vector3 = road.point
		if Vector2(rp.x - at.x, rp.z - at.z).length() < reach + 6.0: return "Too close to a road."
		for p in pts:
			if game.world.terrain.road_dist_at(p.x, p.y) < 5.5: return "On a road."
	var hit := _obstacle_hit(cid, Vector2(at.x, at.z), reach)
	if hit != "": return hit
	for other_id in towns:
		for b in (towns[other_id] as ColonyTown).buildings:
			if b.get("virtual", false): continue
			var r := footprint(b.type).length()
			if Vector2(float(b.x) - at.x, float(b.z) - at.z).length() < r + reach + 1.0: return "Overlaps %s." % EconomyCatalog.building(b.type).name
	if def.get("coast", false) and not _near_water(at, 70.0): return "Must stand by the water (within 70 m)."
	if def.get("port", false):
		if not shipping.ports.has(cid): return "%s has no harbour." % t.display_name
		var berth: Vector3 = shipping.ports[cid].berth
		if Vector2(berth.x - at.x, berth.z - at.z).length() > 350.0: return "A shipyard must be within 350 m of the berth."
	if def.get("unique", false) and not founding and t.has_built(type): return "Only one per colony."
	if game != null and is_inside_tree() and not _physics_clear(at, yaw, f, (lo + hi) * 0.5): return "Something is in the way."
	return ""


func _near_water(at: Vector3, radius: float) -> bool:
	for r in [15.0, 30.0, 45.0, 60.0, radius]:
		for k in range(16):
			var a := TAU * k / 16.0
			if _height(at.x + cos(a) * r, at.z + sin(a) * r) < -0.3: return true
	return false


func _physics_clear(at: Vector3, yaw: float, f: Vector2, y: float) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	var shape := BoxShape3D.new(); shape.size = Vector3(f.x * 2.0, 4.0, f.y * 2.0)
	q.shape = shape
	q.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(at.x, y + 2.6, at.z))
	q.collision_mask = 1 | 2
	# the courier and the ground tiles are not "in the way"
	var hits := get_world_3d().direct_space_state.intersect_shape(q, 8)
	for h in hits:
		var body: Object = h.collider
		if body is StaticBody3D and String((body as Node).name).begins_with("Ground_"): continue
		if body is Player or body is Vehicle: continue
		if views != null and views.owns(body): continue
		return false
	return true


func _obstacle_hit(cid: String, p: Vector2, reach: float) -> String:
	if not _obstacles.has(cid): _build_obstacles(cid)
	var grid: Dictionary = _obstacles[cid]
	var c := Vector2i(floori(p.x / 32.0), floori(p.y / 32.0))
	var span := ceili((reach + 24.0) / 32.0)
	for dj in range(-span, span + 1):
		for di in range(-span, span + 1):
			for e in grid.get(c + Vector2i(di, dj), []):
				if p.distance_to(e[0]) < reach + float(e[1]): return String(e[2])
	return ""


## Everything already standing in and round a town: plots, streets, landmarks, locations.
func _build_obstacles(cid: String) -> void:
	var grid := {}
	var add := func(p: Vector2, r: float, what: String) -> void:
		var c := Vector2i(floori(p.x / 32.0), floori(p.y / 32.0))
		if not grid.has(c): grid[c] = []
		grid[c].append([p, r, what])
	var t := town(cid)
	var centre := Vector2(t.hall.x, t.hall.z)
	if game != null:
		var outer: OuterWorld = game.world.outer
		if outer != null and outer.ok:
			var plan := outer.plan()
			for group in ["towns", "hamlets"]:
				for tw in plan.get(group, []):
					if Vector2(tw.center[0], tw.center[1]).distance_to(centre) > float(tw.radius) + EconomyCatalog.build_radius(cid) + 1200.0: continue
					for pl in tw.plots:
						add.call(Vector2(pl.x, pl.z), 0.5 * Vector2(float(pl.w), float(pl.d)).length() + 1.0, "On a building plot.")
					for s in tw.get("streets", []):
						for q in s.points:
							add.call(Vector2(q[0], q[2]), float(s.get("width", 6.0)) * 0.5 + 1.0, "On a street.")
			for lm in plan.get("landmarks", []):
				add.call(Vector2(lm.pos[0], lm.pos[2]), 12.0, "Too close to a landmark.")
		for id in game.world.database.locations:
			var lp: Vector3 = game.world.database.locations[id].pos
			if Vector2(lp.x, lp.z).distance_to(centre) < 2500.0: add.call(Vector2(lp.x, lp.z), 16.0, "Too close to %s." % game.world.database.location_name(id))
	if system != null:
		add.call(Vector2(system.warehouse_position.x, system.warehouse_position.z), 8.0, "Too close to the colony warehouse.")
		for s in system.sources(): add.call(Vector2(s.position.x, s.position.z), 5.0, "On a resource.")
		for site: ColonySite in system.sites.values(): add.call(Vector2(site.position.x, site.position.z - 4.0), 7.0, "On a workplace.")
	_obstacles[cid] = grid


func invalidate_obstacles() -> void:
	_obstacles.clear()


## Place a building: checks the site, pays the coins and the materials, starts construction.
func place(cid: String, type: String, at: Vector3, yaw: float) -> String:
	var why := check_site(cid, type, at, yaw)
	if why != "": return why
	var def := EconomyCatalog.building(type)
	var t := town(cid)
	if not t.can_afford(def.cost): return "Not enough materials: %s." % EconomyCatalog.describe_cost(def.cost, 0)
	if coins() < int(def.coins): return "Needs %d coins (you have %d)." % [int(def.coins), coins()]
	spend(int(def.coins))
	t.pay(def.cost)
	var p := Vector3(at.x, _pad(at, type, yaw), at.z)
	var b := t.add_building(type, p, yaw)
	b["ground"] = ground_min(p, type, yaw)
	_notify(cid, "%s: %s started." % [t.display_name, def.name], false)
	changed.emit()
	return ""


func remove(cid: String, bid: String) -> bool:
	var t := town(cid)
	if t == null or not t.remove_building(bid): return false
	t.assign()
	changed.emit()
	return true


func toggle_pause(cid: String, bid: String) -> void:
	var t := town(cid)
	var b := t.building(bid)
	if b.is_empty(): return
	b.paused = not b.paused
	t.assign()
	changed.emit()


# ------------------------------------------------------------------ ships and lanes
func can_build_ship(cid: String, type: String) -> String:
	var t := town(cid)
	if t == null or not t.founded: return "Found the colony first."
	if not t.has_built("shipyard"): return "Build a shipyard at %s first." % t.display_name
	if not has_port(cid): return "%s has no harbour." % t.display_name
	var def: Dictionary = EconomyCatalog.SHIPS[type]
	if not t.can_afford(def.cost): return "Needs %s." % EconomyCatalog.describe_cost(def.cost, 0)
	if coins() < int(def.coins): return "Needs %d coins (you have %d)." % [int(def.coins), coins()]
	return ""


func build_ship(cid: String, type: String) -> String:
	if not ensure_shipping(): return "The sea charts are not ready."
	var why := can_build_ship(cid, type)
	if why != "": return why
	var def: Dictionary = EconomyCatalog.SHIPS[type]
	var s := shipping.add_ship(type, cid)
	if s.is_empty(): return "The fleet is full."
	spend(int(def.coins)); town(cid).pay(def.cost)
	_notify(cid, "%s laid down the %s %s." % [town(cid).display_name, def.name.to_lower(), s.name], false)
	changed.emit()
	return ""


func add_lane(from_id: String, to_id: String, out: Dictionary, back: Dictionary) -> Dictionary:
	if not ensure_shipping(): return {}
	for cid in [from_id, to_id]:
		var t := town(cid)
		if t == null or not t.founded: return {}
	var l := shipping.add_lane(from_id, to_id, out, back)
	if not l.is_empty(): changed.emit()
	return l


# ------------------------------------------------------------------ the tick
func _process(delta: float) -> void:
	if game == null: return          # unit tests tick by hand
	if not ports_ready: _register_ports()
	_discover_t += delta
	if _discover_t >= DISCOVER_EVERY:
		_discover_t = 0.0
		_check_discovery()
	if system != null and system.paused: return
	# every town and the fleet owe time; at most one town is ticked a frame (round robin), each
	# at TICK_HZ, so a frame never pays for the whole country
	var scaled := delta * time_scale
	var cap := 8.0 / TICK_HZ * maxf(time_scale, 1.0)
	_ship_pending = minf(_ship_pending + scaled, cap)
	var keys := towns.keys()
	for cid in keys: _pending[cid] = minf(float(_pending.get(cid, 0.0)) + scaled, cap)
	var step := 1.0 / TICK_HZ
	var t0 := Time.get_ticks_usec()
	for n in range(keys.size()):
		var cid: String = keys[(_rr + n) % keys.size()]
		if float(_pending[cid]) >= step:
			_rr = (_rr + n + 1) % keys.size()
			var dt := float(_pending[cid]); _pending[cid] = 0.0
			_tick_town(cid, dt)
			break
	if _ship_pending >= step:
		_tick_ships(_ship_pending); _ship_pending = 0.0
	_frame_us(Time.get_ticks_usec() - t0)


## Time a town / the fleet owes (already scaled): the views ease positions by it.
func pending(cid: String) -> float:
	return float(_pending.get(cid, 0.0))


func ship_pending() -> float:
	return _ship_pending


func _frame_us(us: int) -> void:
	tick_us = us
	tick_us_max = maxi(tick_us_max, us)
	ticks += 1


## Everything by `dt` at once (tests, tools).
func tick(dt: float) -> void:
	var t0 := Time.get_ticks_usec()
	for cid in towns: _tick_town(cid, dt)
	_tick_ships(dt)
	_frame_us(Time.get_ticks_usec() - t0)


func _tick_town(cid: String, dt: float) -> void:
	var t := town(cid)
	var notes := t.tick(dt)
	for text in notes: _notify(cid, text, text.contains("short of food") or text.contains("left"))
	if t.coins_due >= 1.0:
		var n := floori(t.coins_due)
		t.coins_due -= n
		earn(n)
	if not notes.is_empty(): changed.emit()


func _tick_ships(dt: float) -> void:
	if not ports_ready and game != null: return
	shipping.tick(dt)
	for text in shipping.messages: _notify("", text, true)
	if not shipping.messages.is_empty(): changed.emit()
	shipping.messages.clear()


func _check_discovery() -> void:
	var f := game.rider.courier().global_position if game.rider != null else Vector3.ZERO
	for cid in _town_plan:
		var t := town(cid)
		if t.discovered: continue
		var pz: Array = _town_plan[cid].plaza
		if Vector2(pz[0] - f.x, pz[2] - f.z).length() < minf(float(_town_plan[cid].radius), 400.0):
			discover(cid)


func _notify(cid: String, text: String, loud: bool) -> void:
	notifications.append({"colony": cid, "text": text})
	if notifications.size() > 40: notifications.pop_front()
	notified.emit(text)
	if system != null: system.message.emit(text)
	if loud and game != null: Events.message.emit(text, 4.0)


# ------------------------------------------------------------------ persistence
func save_state() -> Dictionary:
	var out := {}
	for cid in towns:
		var d := town(cid).to_dict()
		if cid == "core": d.stock = {}        # the core stock is the colony warehouse (v1 field)
		out[cid] = d
	return {"towns": out, "shipping": shipping.save_state(), "time_scale": time_scale}


func valid(d: Variant) -> bool:
	if not d is Dictionary or not d.get("towns") is Dictionary or d.towns.size() != towns.size(): return false
	if not ColonyTown._num(d.get("time_scale"), 0.0, 8.0): return false
	for cid in towns:
		if not ColonyTown.valid(d.towns.get(cid), cid): return false
	return ShippingNetwork.valid(d.get("shipping"), ["core", "puerto_alto", "sarmada", "isola_serena"])


func load_state(d: Dictionary) -> void:
	for cid in towns:
		var t := town(cid)
		t.apply_dict(d.towns[cid])
		if cid == "core": t.stock = system.warehouse
	shipping.load_state(d.shipping)
	time_scale = float(d.time_scale)
	_obstacles.clear()
	if views != null: views.reset()
	changed.emit()
