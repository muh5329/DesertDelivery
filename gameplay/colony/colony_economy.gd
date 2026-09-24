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
## Urgent supply runs posted by short colonies (optional courier jobs).
var urgent := UrgentSupply.new()
## Carters' wagons between colonies by road (inland Valdoro and Campo Real trade this way).
var roads := RoadHaulage.new()
## What the last load had to repair or drop (the Mayor view and the load message show it).
var load_warnings: Array[String] = []
var _start: Dictionary = {}            # colony id -> its start record (a town missing from a save)
var _site_cache: Dictionary = {}       # "cid|type|x|z|yaw" -> check_site verdict (Build ghost)
var _hall_jobs: Dictionary = {}        # colony id -> charter in progress {r, k, best...}


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
	roads.towns = func(cid: String) -> ColonyTown: return town(cid)
	_remember_start()


func _remember_start() -> void:
	for cid in towns: _start[cid] = town(cid).to_dict()


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
	_remember_start()
	views = ColonyViews.new(); views.name = "ColonyViews"; add_child(views)
	views.setup(self)
	urgent.setup(self)
	if Events.has_signal("camp_cleared"): Events.camp_cleared.connect(func(_id): shipping.pirates_changed(); changed.emit())


func _exit_tree() -> void:
	shipping.wait()          # never leave the sea-grid task running past the tree


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
## Synchronous (tools, tests); the Mayor view uses `begin_found`, which surveys over frames.
func found(cid: String, force := false) -> String:
	var why := _charter_blocked(cid, force)
	if why != "": return why
	var site: Variant = find_hall_site(cid)
	if site == null: return "No clear ground for a colony hall near %s." % town(cid).display_name
	return _raise_hall(cid, site)


## Start a charter whose hall site is surveyed a few milliseconds a frame (no frame stalls).
## "" when the survey started (`chartering(cid)` is true until it ends), else why not.
func begin_found(cid: String) -> String:
	if _hall_jobs.has(cid): return ""
	var why := _charter_blocked(cid, false)
	if why != "": return why
	_hall_jobs[cid] = {"i": 0, "centre": _hall_centre(cid)}
	return ""


func chartering(cid: String) -> bool:
	return _hall_jobs.has(cid)


func _charter_blocked(cid: String, force: bool) -> String:
	var t := town(cid)
	if t == null: return "No such town."
	if t.founded: return "%s is already a colony." % t.display_name
	if not t.discovered and not force: return "Visit %s first." % t.display_name
	if coins() < charter_cost(cid): return "A charter costs %d coins (you have %d)." % [charter_cost(cid), coins()]
	return ""


func _raise_hall(cid: String, site: Dictionary) -> String:
	var t := town(cid)
	if coins() < charter_cost(cid): return "A charter costs %d coins (you have %d)." % [charter_cost(cid), coins()]
	spend(charter_cost(cid))
	t.discovered = true; t.founded = true
	t.hall = site.pos
	var hall := t.add_building("colony_hall", site.pos, site.yaw, true)
	hall["ground"] = ground_min(site.pos, "colony_hall", site.yaw)
	for item in EconomyCatalog.CHARTER_STOCK: t.stock[item] = int(EconomyCatalog.CHARTER_STOCK[item])
	var staple := String(EconomyCatalog.COLONIES.get(cid, {}).get("staple", ""))
	if staple != "": t.stock[staple] = int(t.stock.get(staple, 0)) + EconomyCatalog.STAPLE_STOCK
	for i in range(EconomyCatalog.CHARTER_SETTLERS): t.add_colonist(hash([cid, i, SETTLER_SEED]))
	t.assign()
	_site_cache.clear()
	_notify(cid, "%s is chartered: a colony hall, %d settlers and a starter stock." % [t.display_name, EconomyCatalog.CHARTER_SETTLERS], true)
	changed.emit()
	return ""


## Where the hall search starts: the town's plaza (the hall belongs in the town, with the build
## area on land round it — not out on a mole by the berth).
func _hall_centre(cid: String) -> Vector3:
	var t := town(cid)
	if _town_plan.has(cid) and cid != "core":
		var pz: Array = _town_plan[cid].plaza
		return Vector3(pz[0], pz[1], pz[2])
	return t.hall


## The i-th candidate of the survey: rings every 15 m from 30 m out, 25 m apart round each ring.
## Returns null past the last ring.
static func _hall_candidate(centre: Vector3, i: int) -> Variant:
	var r := 30.0
	while r <= 1000.0:
		var n := maxi(12, int(TAU * r / 25.0))
		if i < n:
			var a := TAU * i / n
			return Vector3(centre.x + cos(a) * r, 0, centre.z + sin(a) * r)
		i -= n
		r += 15.0
	return null


func _try_hall(cid: String, centre: Vector3, p: Vector3) -> Variant:
	var yaw := snappedf(atan2(centre.x - p.x, centre.z - p.z), PI * 0.5)   # the front faces the plaza
	if check_site(cid, "colony_hall", p, yaw, true) != "": return null
	if _land_share(p, 150.0) < 0.6: return null     # the build area round the hall is mostly land
	p.y = _pad(p, "colony_hall", yaw)
	return {"pos": p, "yaw": yaw}


func _land_share(at: Vector3, radius: float) -> float:
	var dry := 0
	for k in range(16):
		var a := TAU * k / 16.0
		if _height(at.x + cos(a) * radius, at.z + sin(a) * radius) > 0.6: dry += 1
	return dry / 16.0


## The nearest clear site to the plaza for the colony hall (synchronous).
func find_hall_site(cid: String) -> Variant:
	var centre := _hall_centre(cid)
	var i := 0
	while true:
		var p: Variant = _hall_candidate(centre, i)
		if p == null: return null
		var site: Variant = _try_hall(cid, centre, p)
		if site != null: return site
		i += 1
	return null


## Charters in progress: survey candidates for HALL_BUDGET_US a frame.
const HALL_BUDGET_US := 3000
func _survey_halls() -> void:
	for cid in _hall_jobs.keys():
		var job: Dictionary = _hall_jobs[cid]
		var t0 := Time.get_ticks_usec()
		while Time.get_ticks_usec() - t0 < HALL_BUDGET_US:
			var p: Variant = _hall_candidate(job.centre, int(job.i))
			job.i = int(job.i) + 1
			if p == null:
				_hall_jobs.erase(cid)
				_notify(cid, "No clear ground for a colony hall near %s." % town(cid).display_name, true)
				changed.emit()
				break
			var site: Variant = _try_hall(cid, job.centre, p)
			if site != null:
				_hall_jobs.erase(cid)
				var err := _raise_hall(cid, site)
				if err != "": _notify(cid, err, true)
				break
		return      # one charter a frame


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
	# the cheap tests first: plots, streets and landmarks from the town's grid
	var hit := _obstacle_hit(cid, Vector2(at.x, at.z), reach)
	if hit != "": return hit
	if game != null:
		var n := game.world.terrain.normal_at(at.x, at.z)
		if n.y < 0.9: return "Too steep."
		for p in pts:
			if game.world.terrain.road_dist_at(p.x, p.y) < 5.5: return "On a road."
		if _road_within(Vector2(at.x, at.z), reach + 6.0): return "Too close to a road."
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


## check_site for the Build ghost: the verdict for a 1 m / 15 degree cell is kept until the
## colonies change, so sweeping the pointer over a site costs the physics query once.
func check_site_cached(cid: String, type: String, at: Vector3, yaw: float) -> String:
	var key := "%s|%s|%d|%d|%d" % [cid, type, roundi(at.x), roundi(at.z), roundi(rad_to_deg(yaw) / 15.0)]
	if _site_cache.has(key): return _site_cache[key]
	if _site_cache.size() > 4096: _site_cache.clear()
	var why := check_site(cid, type, at, yaw)
	_site_cache[key] = why
	return why


## Is any road sample within `radius` of `p`? A bounded look at the Terrain's 8 m road grid
## (nearest_road searches outward up to ~500 m and then the whole country: 5-30 ms far from
## roads, which is most of a mountain or farm colony's build area).
func _road_within(p: Vector2, radius: float) -> bool:
	var terrain: Terrain = game.world.terrain
	if terrain._road_grid.is_empty(): terrain.nearest_road(Vector3(p.x, 0, p.y))   # builds the grid
	var cell := Terrain.ROAD_CELL
	var c0 := Vector2i(floori((p.x - radius) / cell), floori((p.y - radius) / cell))
	var c1 := Vector2i(floori((p.x + radius) / cell), floori((p.y + radius) / cell))
	var r2 := radius * radius
	for cj in range(c0.y, c1.y + 1):
		for ci in range(c0.x, c1.x + 1):
			var list: Variant = terrain._road_grid.get(Vector2i(ci, cj))
			if list == null: continue
			for e in list:
				var q: Vector3 = terrain.road_samples[e[0]][e[1]]
				if (q.x - p.x) * (q.x - p.x) + (q.z - p.y) * (q.z - p.y) < r2: return true
	return false


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
	_site_cache.clear()


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
	_site_cache.clear()
	_notify(cid, "%s: %s started." % [t.display_name, def.name], false)
	changed.emit()
	return ""


func remove(cid: String, bid: String) -> bool:
	var t := town(cid)
	if t == null or not t.remove_building(bid): return false
	_site_cache.clear()
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


## A mended record of a chartered colony keeps a colony hall (a damaged hall record is replaced
## by the start one, or a fresh hall where the colony's hall stood).
func _keep_hall(cid: String, rec: Dictionary) -> Dictionary:
	if not rec.founded: return rec
	for b in rec.buildings:
		if b.type == "colony_hall": return rec
	var hall: Dictionary = {}
	for b in _start.get(cid, {}).get("buildings", []):
		if b.type == "colony_hall": hall = b.duplicate(true)
	if hall.is_empty():
		hall = {"id": "%s.b%d" % [cid, int(rec.next_id)], "type": "colony_hall", "x": float(rec.hall[0]), "y": float(rec.hall[1]), "z": float(rec.hall[2]),
			"yaw": 0.0, "built": true, "progress": 1.0, "cycle": 0.0, "inbuf": {}, "outbuf": {}, "paused": false, "produced": 0, "carry": {}}
		rec.next_id = int(rec.next_id) + 1
	rec.buildings.push_front(hall)
	return rec


## Hire a carter between two chartered colonies (any two: the wagons go by road). The wagon
## and its team cost COINS and COST's planks at `from`. Returns "" or why not.
func add_road_route(from_id: String, to_id: String, out: Dictionary, back: Dictionary) -> String:
	var a := town(from_id); var b := town(to_id)
	if a == null or b == null or not a.founded or not b.founded: return "Both ends must be chartered colonies."
	if from_id == to_id: return "Pick two different colonies."
	if out.is_empty() and back.is_empty(): return "Give the wagon at least one cargo rule."
	if roads.routes.size() >= RoadHaulage.MAX_ROUTES: return "Every carter is already hired."
	if not a.can_afford(RoadHaulage.COST): return "A wagon needs %s at %s." % [EconomyCatalog.describe_cost(RoadHaulage.COST, 0), a.display_name]
	if coins() < RoadHaulage.COINS: return "A carter costs %d coins (you have %d)." % [RoadHaulage.COINS, coins()]
	var r := roads.add_route(from_id, to_id, out, back)
	if r.is_empty(): return "No road between those colonies."
	spend(RoadHaulage.COINS); a.pay(RoadHaulage.COST)
	_notify(from_id, "A carter now runs %s (%.1f km by road)." % [roads.title(r), float(r.m) / 1000.0], false)
	changed.emit()
	return ""


# ------------------------------------------------------------------ the tick
func _process(delta: float) -> void:
	if game == null: return          # unit tests tick by hand
	if not ports_ready: _register_ports()
	_discover_t += delta
	if _discover_t >= DISCOVER_EVERY:
		_discover_t = 0.0
		_check_discovery()
	urgent.update(delta)
	if not _hall_jobs.is_empty(): _survey_halls()
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
	roads.tick(dt)
	for text in roads.messages: _notify("", text, false)
	roads.messages.clear()
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
	return {"towns": out, "shipping": shipping.save_state(), "roads": roads.save_state(), "time_scale": time_scale}


func valid(d: Variant) -> bool:
	if not d is Dictionary or not d.get("towns") is Dictionary or d.towns.size() != towns.size(): return false
	if not ColonyTown._num(d.get("time_scale"), 0.0, 8.0): return false
	for cid in towns:
		if not ColonyTown.valid(d.towns.get(cid), cid): return false
	return ShippingNetwork.valid(d.get("shipping"), ["core", "puerto_alto", "sarmada", "isola_serena"])


func load_state(d: Dictionary) -> void:
	load_partial(d)


## Load what is usable of a saved economy, town by town and lane by lane: a valid record loads
## as it is, a damaged one is mended (numbers clamped, a broken building or colonist dropped),
## one beyond repair — or missing from the save — goes back to its start state. Returns what
## had to change (empty for a clean save); also kept in `load_warnings`.
func load_partial(d: Variant) -> Array[String]:
	var warn: Array[String] = []
	if not d is Dictionary:
		warn.append("the colony economy was missing from the save; the colonies were kept as they were")
		load_warnings = warn
		return warn
	var saved: Dictionary = d.get("towns") if d.get("towns") is Dictionary else {}
	for cid in saved:
		if not towns.has(cid): warn.append("an unknown colony '%s' in the save was ignored" % str(cid))
	for cid in towns:
		var t := town(cid)
		var rec: Variant = saved.get(cid)
		var name := t.display_name.get_slice(" (", 0)
		if rec == null:
			warn.append("%s was not in the save: it starts afresh" % name)
			rec = _start.get(cid, ColonyTown.new(cid).to_dict())
		elif not ColonyTown.valid(rec, cid):
			var fixed := ColonyTown.repair(rec, cid)
			if (fixed.data as Dictionary).is_empty():
				warn.append("%s's record could not be read: it starts afresh" % name)
				rec = _start.get(cid, ColonyTown.new(cid).to_dict())
			else:
				warn.append("%s's record was repaired (%s)" % [name, ", ".join(PackedStringArray(fixed.fixes.slice(0, 4)))])
				rec = _keep_hall(cid, fixed.data)
		t.apply_dict(rec)
		if cid == "core" and system != null: t.stock = system.warehouse
	var ports := ["core", "puerto_alto", "sarmada", "isola_serena"]
	var sh: Variant = d.get("shipping")
	if ShippingNetwork.valid(sh, ports):
		shipping.load_state(sh)
	else:
		var fixed := ShippingNetwork.repair(sh, ports)
		shipping.load_state(fixed.data)
		if not (fixed.dropped as Array).is_empty():
			warn.append("the fleet lost %s (damaged in the save)" % ", ".join(PackedStringArray(fixed.dropped.slice(0, 4))))
	var dropped := roads.load_state(d.get("roads", {"next_id": 1, "routes": []}), towns.keys())
	if dropped > 0: warn.append("%d carter route%s could not be read" % [dropped, "" if dropped == 1 else "s"])
	var ts: Variant = d.get("time_scale", 1.0)
	time_scale = clampf(float(ts), 0.0, 8.0) if (ts is float or ts is int) and is_finite(float(ts)) else 1.0
	_obstacles.clear()
	_site_cache.clear()
	if views != null: views.reset()
	changed.emit()
	load_warnings = warn
	return warn
