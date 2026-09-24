class_name RoadHaulage
extends RefCounted
## Goods by road: carters' wagons between any two chartered colonies (ADR 0011 "reopen if goods
## should move by road"). A route is a record like a sea lane — two colonies, an outbound and a
## return cargo rule — served by one wagon. The wagon is a distance along the road (the straight
## line x ROAD_FACTOR; the country is compressed the same way the sea lanes are), so it runs
## by the clock whether anything is drawn or not. Inland Valdoro and Campo Real trade this way.
##
##   add_route(from, to, out, back) -> {} | route      remove_route(id)
##   tick(dt)     save_state() / valid(d, colony ids) / load_state(d)
##   routes: Array[{id, from, to, out, back, km, state, leg, s, timer, cargo, trips, log}]

const SPEED := 7.0                # m/s: an ox-drawn wagon, on the compressed map
const CAPACITY := 30
const LOAD_TIME := 10.0
const ROAD_FACTOR := 1.35
const MAX_ROUTES := 10
const COST := {"planks": 6}
const COINS := 60

var routes: Array = []
var next_id := 1
var messages: Array = []
var towns: Callable                  # (colony id) -> ColonyTown


func route(rid: String) -> Dictionary:
	for r in routes:
		if r.id == rid: return r
	return {}


## The road distance between two colonies' halls, in metres.
func distance(from_id: String, to_id: String) -> float:
	var a: ColonyTown = towns.call(from_id) if towns.is_valid() else null
	var b: ColonyTown = towns.call(to_id) if towns.is_valid() else null
	if a == null or b == null: return 0.0
	return Vector2(a.hall.x - b.hall.x, a.hall.z - b.hall.z).length() * ROAD_FACTOR


func add_route(from_id: String, to_id: String, out: Dictionary, back: Dictionary) -> Dictionary:
	if routes.size() >= MAX_ROUTES or from_id == to_id: return {}
	var d := distance(from_id, to_id)
	if d <= 0.0: return {}
	var r := {"id": "road.%d" % next_id, "from": from_id, "to": to_id, "out": ShippingNetwork._clean_rule(out),
		"back": ShippingNetwork._clean_rule(back), "m": d, "state": "loading", "leg": 0, "s": 0.0, "timer": 0.0,
		"cargo": {}, "trips": 0, "log": []}
	next_id += 1
	routes.append(r)
	_load(r, 0)
	return r


func remove_route(rid: String) -> bool:
	for i in range(routes.size()):
		if routes[i].id == rid:
			# what is aboard goes back to the town it left
			var r: Dictionary = routes[i]
			var home: ColonyTown = towns.call(r.from if int(r.leg) == 0 else r.to) if towns.is_valid() else null
			if home != null:
				for item in r.cargo: home.add(item, int(r.cargo[item]))
			routes.remove_at(i)
			return true
	return false


func tick(dt: float) -> void:
	for r in routes:
		match String(r.state):
			"loading":
				r.timer = float(r.timer) - dt
				if float(r.timer) <= 0.0:
					r.state = "road"; r.s = 0.0
			"road":
				r.s = float(r.s) + SPEED * dt
				if float(r.s) >= float(r.m): _arrive(r)


func _arrive(r: Dictionary) -> void:
	var dest: String = r.to if int(r.leg) == 0 else r.from
	var town: ColonyTown = towns.call(dest) if towns.is_valid() else null
	var unloaded := PackedStringArray()
	if town != null and town.founded:
		for item in r.cargo.keys():
			var n := int(r.cargo[item]); var put := town.add(item, n)
			if put > 0: unloaded.append("%d %s" % [put, EconomyCatalog.item_name(item).to_lower()])
			if put >= n: r.cargo.erase(item)
			else: r.cargo[item] = n - put
	r.trips = int(r.trips) + 1
	var next_leg := 1 if int(r.leg) == 0 else 0
	var loaded := _load(r, next_leg)
	if not unloaded.is_empty() or not loaded.is_empty():
		_log(r, "Wagon at %s: %s%s" % [_name(dest), ("unloaded " + ", ".join(unloaded)) if not unloaded.is_empty() else "",
			((" · " if not unloaded.is_empty() else "") + "loaded " + ", ".join(loaded)) if not loaded.is_empty() else ""])


## Load by the rule of the leg about to start (at `from` for leg 0, `to` for leg 1).
func _load(r: Dictionary, leg: int) -> PackedStringArray:
	var here: String = r.from if leg == 0 else r.to
	var town: ColonyTown = towns.call(here) if towns.is_valid() else null
	var loaded := PackedStringArray()
	var moved := 0
	if town != null and town.founded:
		var rule: Dictionary = r.out if leg == 0 else r.back
		for item in rule:
			var room := CAPACITY - units(r)
			if room <= 0: break
			var have := int(r.cargo.get(item, 0))
			var want := mini(int(rule[item]) - have, room)
			if want <= 0: continue
			var got := town.take(item, want)
			if got > 0:
				r.cargo[item] = have + got; moved += got
				loaded.append("%d %s" % [got, EconomyCatalog.item_name(item).to_lower()])
	r.leg = leg; r.state = "loading"; r.s = 0.0
	r.timer = LOAD_TIME + moved * 0.2
	return loaded


static func units(r: Dictionary) -> int:
	var n := 0
	for item in r.cargo: n += int(r.cargo[item])
	return n


func title(r: Dictionary) -> String:
	return "%s - %s" % [_name(r.from), _name(r.to)]


func status(r: Dictionary) -> String:
	var cargo := PackedStringArray()
	for item in r.cargo: cargo.append("%d %s" % [int(r.cargo[item]), EconomyCatalog.item_name(item).to_lower()])
	var load := ("carrying " + ", ".join(cargo)) if not cargo.is_empty() else "empty"
	var dest: String = r.to if int(r.leg) == 0 else r.from
	var here: String = r.from if int(r.leg) == 0 else r.to
	if r.state == "loading": return "Loading at %s · %s" % [_name(here), load]
	return "On the road to %s (%d%%) · %s" % [_name(dest), int(float(r.s) / maxf(float(r.m), 1.0) * 100.0), load]


func _name(cid: String) -> String:
	return String(EconomyCatalog.COLONIES.get(cid, {}).get("name", cid)).get_slice(" (", 0)


func _log(r: Dictionary, text: String) -> void:
	r.log.append(text)
	if r.log.size() > 12: r.log.pop_front()


# ------------------------------------------------------------------ persistence
func save_state() -> Dictionary:
	return {"next_id": next_id, "routes": routes.duplicate(true)}


## Keep every valid route, drop (and report) the broken ones. Returns the dropped count.
func load_state(d: Variant, colony_ids: Array) -> int:
	routes = []
	var dropped := 0
	if not d is Dictionary:
		return 0
	next_id = int(d.get("next_id", 1)) if ColonyTown._num(d.get("next_id"), 1, 1e7) else 1
	var seen := {}
	for r in d.get("routes", []):
		if not _valid_route(r, colony_ids) or seen.has(r.id):
			dropped += 1
			continue
		seen[r.id] = true
		var c: Dictionary = r.duplicate(true)
		c.out = ColonyTown._ints(c.out); c.back = ColonyTown._ints(c.back); c.cargo = ColonyTown._ints(c.cargo)
		c.leg = int(c.leg); c.trips = int(c.trips); c.m = float(c.m); c.s = clampf(float(c.s), 0.0, float(c.m))
		routes.append(c)
		if routes.size() >= MAX_ROUTES: break
	for r in routes:
		next_id = maxi(next_id, int(String(r.id).get_slice(".", 1)) + 1)
	return dropped


static func _valid_route(r: Variant, colony_ids: Array) -> bool:
	if not r is Dictionary or not r.get("id") is String: return false
	if not r.get("from") in colony_ids or not r.get("to") in colony_ids or r.from == r.to: return false
	if not ShippingNetwork._rule(r.get("out")) or not ShippingNetwork._rule(r.get("back")): return false
	if not r.get("state") in ["loading", "road"] or not int(r.get("leg", -1)) in [0, 1]: return false
	if not ColonyTown._num(r.get("m"), 1.0, 1e6) or not ColonyTown._num(r.get("s"), 0.0, 1e6) or not ColonyTown._num(r.get("timer"), -1e3, 1e6): return false
	if not ColonyTown._inventory(r.get("cargo")) or units(r) > CAPACITY: return false
	if not ColonyTown._num(r.get("trips"), 0, 1e9) or not r.get("log") is Array: return false
	return true
