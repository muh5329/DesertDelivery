class_name RoadServices
extends Node3D
## Fuel stations and the coach & ferry offices of the country: data first, drawn near the viewer.
##
## Stations are placed at boot from the world as it is (the outer roads' samples, the towns'
## plots, props and rivers) — nothing is added to the generator's plan:
##   * a **town station** at the edge of each of the five towns, on the highway that runs into
##     its gate (pumps, a canopy, a shop that is also the coach & ferry ticket office);
##   * **highway service stops** along the ring and the spokes, so no stretch of highway is
##     longer than MAX_GAP between two pumps;
##   * the courier counters (DeliverySystem job hubs) sell fuel too, and count as stations.
## A station is a record {id, name, kind, pos, forward, out, road, k, town, coach}; the node is
## built within DRAW_RADIUS of the viewer (one a frame) and freed beyond FREE_RADIUS.
##
## Interface (JourneySystem, the HUD, tests):
##   stations: Array[Dictionary]      nearby(pos) -> station within USE_RADIUS or {}
##   nearest_fuel(pos) -> {station, distance, bearing}      gaps() -> per-road pump spacing
##   destinations(from) -> [{id, name, pos, km, minutes, price, open, reason}]
##   travel(from_station_or_counter_id, to_id) -> "" | reason

const USE_RADIUS := 16.0           # courier within this of the station's apron centre
const MAX_GAP := 5200.0            # highway metres between two pumps, at most
const DRAW_RADIUS := 1100.0
const FREE_RADIUS := 1400.0
const APRON_LENGTH := 34.0
const APRON_DEPTH := 14.0
const COACH_KMH := 55.0            # the coach's average speed (game time a trip takes)
const TICKET_BASE := 10
const TICKET_PER_KM := 1.5          # riding costs ~1 coin a km in fuel: the coach is the dear way
const PREFIX := {"puerto": "Posto", "valdoro": "Stazione", "sarmada": "Mahatta", "isola": "Stazione", "campo": "Estacion"}
const TOWN_NAMES := {"core": "Villa Rosa"}

var game: Game
var terrain: Terrain
var stations: Array[Dictionary] = []
var by_id: Dictionary = {}
var _nodes: Dictionary = {}         # station id -> Node3D
var _check_t := 0.0
var _plots: Array = []              # [Vector2 centre, radius] of every plan plot and prop
var _rivers: Array = []             # [Vector2 point, half width]
var _mats: Dictionary = {}
var build_ms := 0


func setup(p_game: Game) -> void:
	game = p_game
	name = "RoadServices"
	terrain = game.world.terrain
	var t0 := Time.get_ticks_msec()
	var outer: OuterWorld = game.world.outer
	if outer != null and outer.ok and outer.roads != null:
		_index_obstacles(outer.plan())
		_place_town_stations(outer)
		_place_highway_stops(outer)
	_add_counters()
	var seen := {}
	for s in stations:
		# two stops named after the same hamlet: the second says which road it serves
		if seen.has(s.name) and s.kind == "highway": s.name = "%s (%s)" % [s.name, _road_label(String(s.road))]
		seen[s.name] = true
		by_id[s.id] = s
	build_ms = Time.get_ticks_msec() - t0
	print("[services] %d stations (%d town, %d highway, %d counters) in %d ms" % [stations.size(),
		stations.filter(func(s): return s.kind == "town").size(), stations.filter(func(s): return s.kind == "highway").size(),
		stations.filter(func(s): return s.kind == "counter").size(), build_ms])


# ============================================================================ placement
func _index_obstacles(plan: Dictionary) -> void:
	for group in ["towns", "hamlets"]:
		for t: Dictionary in plan.get(group, []):
			for pl: Dictionary in t.get("plots", []):
				_plots.append([Vector2(pl.x, pl.z), 0.5 * Vector2(pl.w, pl.d).length() + 3.0])
			for pr: Array in t.get("props", []):
				_plots.append([Vector2(pr[1], pr[3]), 3.0])
	for r: Dictionary in plan.get("rivers", []):
		var pts: Array = r.get("points", [])
		for i in range(0, pts.size(), 3):
			_rivers.append([Vector2(pts[i][0], pts[i][2]), float(pts[i][3]) * 0.5])


## Each town's station: on a highway that ends at the town, 150-900 m out from the gate.
func _place_town_stations(outer: OuterWorld) -> void:
	var plan := outer.plan()
	for t: Dictionary in plan.get("towns", []):
		var site: Dictionary = {}
		for r: Dictionary in outer.roads.roads:
			if r.cls != "highway": continue
			var n: int = (r.pts as PackedVector3Array).size()
			if r.to == t.id:
				site = _search(r, n - 1 - 60, n - 1 - 225, n - 1 - 38)
			elif r.from == t.id:
				site = _search(r, 60, 225, 38)
			if not site.is_empty(): break
		if site.is_empty():
			# no highway room: the main street, past the gate
			var ri: int = outer.roads.by_id.get("street.%s.main" % t.id, -1)
			if ri >= 0:
				var st: Dictionary = outer.roads.roads[ri]
				site = _search(st, 6, mini(80, (st.pts as PackedVector3Array).size() - 10), 4)
		if site.is_empty():
			push_warning("[services] no station site for %s" % t.id)
			continue
		site.id = "station.%s" % t.id
		site.kind = "town"
		site.town = String(t.id)
		site.coach = true
		site.name = "%s %s" % [PREFIX.get(t.style, "Station"), t.name]
		stations.append(site)


## Highway service stops: split each ring leg and spoke so no pump-to-pump stretch is longer
## than MAX_GAP (the town stations and the core's counters are the legs' ends).
func _place_highway_stops(outer: OuterWorld) -> void:
	for r: Dictionary in outer.roads.roads:
		if r.cls != "highway": continue
		var pts: PackedVector3Array = r.pts
		var n := pts.size()
		var length := (n - 1) * 4.0
		# the town station stands ~0.4 km in from a town end; a core exit has counters within ~1 km
		var head := 400.0 if _is_town(r.from) else 1000.0
		var tail := 400.0 if _is_town(r.to) else 1000.0
		var span := length - head - tail
		var count := maxi(0, ceili((span + head + tail) / MAX_GAP) - 1)
		for i in range(count):
			var at := length * float(i + 1) / float(count + 1)
			var k := clampi(int(at / 4.0), 40, n - 41)
			var win := int(minf(700.0, MAX_GAP * 0.18) / 4.0)
			var site := _search(r, k - win, k + win, k)
			if site.is_empty():
				push_warning("[services] no service stop site on %s near k %d" % [r.id, k])
				continue
			site.id = "station.%s.%d" % [r.id, i]
			site.kind = "highway"
			site.town = ""
			site.coach = false
			site.name = _stop_name(site.pos, r)
			stations.append(site)
	# the Isola junction, where three highways and the causeway meet, gets a stop of its own
	for r: Dictionary in outer.roads.roads:
		if r.cls != "highway" or String(r.to) != "isola_junction": continue
		var n: int = (r.pts as PackedVector3Array).size()
		var site := _search(r, n - 1 - 40, n - 1 - 220, n - 1 - 50)
		if site.is_empty(): continue
		site.id = "station.%s.junction" % r.id
		site.kind = "highway"; site.town = ""; site.coach = false
		site.name = _stop_name(site.pos, r)
		stations.append(site)
		break


func _road_label(road_id: String) -> String:
	var parts := road_id.split(".")
	if parts.size() >= 3 and parts[0] == "ring": return "%s-%s" % [_town_name(parts[1]).get_slice(" ", 0), _town_name(parts[2]).get_slice(" ", 0)]
	if parts.size() >= 2 and parts[0] == "spoke": return "%s spoke" % parts[1]
	return road_id


func _is_town(id: Variant) -> bool:
	return String(id) in ["puerto_alto", "valdoro", "sarmada", "isola_serena", "campo_real"]


func _stop_name(p: Vector3, r: Dictionary) -> String:
	var plan: Dictionary = game.world.outer.plan()
	var best := ""
	var best_d := 3500.0
	var style := "campo"
	var style_d := INF
	for group in ["hamlets", "towns"]:
		for t: Dictionary in plan.get(group, []):
			var c: Array = t.center
			var d := Vector2(p.x - c[0], p.z - c[1]).length()
			if d < style_d: style_d = d; style = String(t.style)
			if group == "hamlets" and d < best_d: best_d = d; best = String(t.name)
	if best != "": return "%s %s" % [PREFIX.get(style, "Station"), best]
	var km := 0
	var pts: PackedVector3Array = r.pts
	var best_k := 0
	var bk := INF
	for k in range(0, pts.size(), 10):
		var d := Vector2(pts[k].x - p.x, pts[k].z - p.z).length()
		if d < bk: bk = d; best_k = k
	km = roundi(best_k * 4.0 / 1000.0)
	return "%s km %d" % [PREFIX.get(style, "Station"), km]


## Walk k from `prefer` outwards in 20 m steps inside [a, b] (either order) and both sides of
## the road; the first good apron wins.
func _search(r: Dictionary, a: int, b: int, prefer: int) -> Dictionary:
	var lo := mini(a, b)
	var hi := maxi(a, b)
	var n: int = (r.pts as PackedVector3Array).size()
	lo = clampi(lo, 10, n - 11)
	hi = clampi(hi, 10, n - 11)
	if hi <= lo: return {}
	prefer = clampi(prefer, lo, hi)
	for strict in [true, false]:
		for step in range(0, hi - lo + 1, 5):
			for dk in ([step] if step == 0 else [step, -step]):
				var k: int = prefer + dk
				if k < lo or k > hi: continue
				for side in [1.0, -1.0]:
					var s := _site(r, k, side, strict)
					if not s.is_empty(): return s
	return {}


func _site(r: Dictionary, k: int, side: float, strict: bool) -> Dictionary:
	var pts: PackedVector3Array = r.pts
	var br: PackedByteArray = r.bridge
	var n := pts.size()
	if k < 10 or k > n - 11: return {}
	for j in range(k - 12, k + 13):
		if j >= 0 and j < n and br[j] != 0: return {}
	var p := pts[k]
	var t := pts[k + 3] - pts[k - 3]
	t.y = 0.0
	if t.length_squared() < 0.01: return {}
	t = t.normalized()
	if absf(pts[k + 5].y - pts[k - 5].y) / 40.0 > 0.06: return {}
	# not on a bend: the apron runs straight along the road
	var t2 := pts[mini(k + 8, n - 1)] - pts[maxi(k - 8, 0)]
	t2.y = 0.0
	if t2.normalized().dot(t) < 0.985: return {}
	var out := Vector3(-t.z, 0.0, t.x) * side
	var half := float(r.width) * 0.5
	var tol := 0.9 if strict else 1.6
	var lo_h := INF
	var samples: Array = []
	for a: float in [-APRON_LENGTH * 0.5, -APRON_LENGTH * 0.25, 0.0, APRON_LENGTH * 0.25, APRON_LENGTH * 0.5]:
		for c: float in [half + 1.0, half + APRON_DEPTH * 0.5, half + APRON_DEPTH + 1.0]:
			var q := p + t * a + out * c
			var h := terrain.height_at(q.x, q.z)
			if absf(h - p.y) > tol: return {}
			if h < Terrain.SEA_LEVEL + 1.5: return {}
			lo_h = minf(lo_h, h)
			samples.append([q, c])
	# no other road closer than ours (the far corners and the middle are enough)
	for e: Array in samples:
		if float(e[1]) < half + APRON_DEPTH * 0.5: continue
		var q: Vector3 = e[0]
		var np: Vector3 = terrain.nearest_road(q).point
		if Vector2(np.x - q.x, np.z - q.z).length() < float(e[1]) - 2.5: return {}
	var centre := p + out * (half + 0.5 + APRON_DEPTH * 0.5)
	var c2 := Vector2(centre.x, centre.z)
	var reach := 0.5 * Vector2(APRON_LENGTH, APRON_DEPTH).length()
	for o: Array in _plots:
		if (o[0] as Vector2).distance_to(c2) < reach + float(o[1]): return {}
	for o: Array in _rivers:
		if (o[0] as Vector2).distance_to(c2) < reach + float(o[1]) + 12.0: return {}
	centre.y = p.y
	return {"pos": centre, "road_pos": p, "forward": t, "out": out, "road": String(r.id), "k": k, "low": lo_h}


## The courier counters sell fuel as well (the job hubs of the DeliverySystem).
func _add_counters() -> void:
	var seen := {}
	for job in game.gm.jobs:
		var id: StringName = job.from_location
		if seen.has(id) or not game.world.database.locations.has(id): continue
		seen[id] = true
		var p: Vector3 = game.world.database.location_pos(id)
		var town := ""
		if _is_town(String(id)): town = String(id)
		elif Vector2(p.x, p.z).length() < 900.0: town = "core"
		stations.append({"id": "counter.%s" % id, "kind": "counter", "name": "%s counter" % game.world.database.location_name(id),
			"pos": p, "forward": Vector3.FORWARD, "out": Vector3.RIGHT, "road": "", "k": 0, "town": town, "coach": (town == "core" and id == &"villa_rosa_office") or _is_town(town), "hub": id})


# ============================================================================ queries
## The station whose apron the courier stands on (counters are the JourneySystem's own).
func nearby(pos: Vector3) -> Dictionary:
	for s in stations:
		if s.kind == "counter": continue
		var d := Vector2(pos.x - s.pos.x, pos.z - s.pos.z).length()
		if d < USE_RADIUS and absf(pos.y - s.pos.y) < 5.0: return s
	return {}


## The nearest place that sells fuel: {station, distance (m, straight), bearing (radians, world
## atan2(x, -z) like the HUD compass)} or {} when there is none.
func nearest_fuel(pos: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF
	for s in stations:
		var d := Vector2(pos.x - s.pos.x, pos.z - s.pos.z).length()
		if d < best_d: best_d = d; best = s
	if best.is_empty(): return {}
	var to: Vector3 = best.pos - pos
	return {"station": best, "distance": best_d, "bearing": atan2(to.x, -to.z)}


static func compass_word(bearing: float) -> String:
	var names := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	return names[posmod(roundi(bearing / (TAU / 8.0)), 8)]


## Along each highway: the metres between consecutive pumps (town stations and counters at the
## ends count). Tests and the tuning note read this. [{road, gaps: [m...], worst}]
func gaps() -> Array:
	var out: Array = []
	var outer: OuterWorld = game.world.outer
	if outer == null or not outer.ok: return out
	for r: Dictionary in outer.roads.roads:
		if r.cls != "highway": continue
		var pts: PackedVector3Array = r.pts
		var n := pts.size()
		var marks: Array[float] = []
		for s in stations:
			var k := _project(pts, s.pos, 60.0 if s.kind != "counter" else 0.0)
			if k >= 0: marks.append(k * 4.0)
		# road ends: a town station or a counter reached off the end of this road
		marks.append(-_end_distance(pts[0], String(r.from)))
		marks.append((n - 1) * 4.0 + _end_distance(pts[n - 1], String(r.to)))
		marks.sort()
		var g: Array[float] = []
		for i in range(marks.size() - 1):
			g.append(marks[i + 1] - marks[i])
		var worst := 0.0
		for x in g: worst = maxf(worst, x)
		out.append({"road": String(r.id), "length": (n - 1) * 4.0, "gaps": g, "worst": worst})
	return out


## The index of the road sample nearest `p` when `p` lies within `reach` of the road, else -1.
func _project(pts: PackedVector3Array, p: Vector3, reach: float) -> int:
	if reach <= 0.0: return -1
	var best := -1
	var bd := reach * reach
	for k in range(0, pts.size(), 2):
		var d := Vector2(pts[k].x - p.x, pts[k].z - p.z).length_squared()
		if d < bd: bd = d; best = k
	return best


## From a road's end to the nearest fuel off that end: the end's own town station (its gate is
## the road's end), a counter on the core, or (a junction) the nearest station anywhere by air
## times 1.3 for the road — never zero.
func _end_distance(end: Vector3, node: String) -> float:
	var best := INF
	for s in stations:
		var d := Vector2(end.x - s.pos.x, end.z - s.pos.z).length()
		if s.kind == "town" and s.town == node: return 0.0 if d < 1200.0 else d * 1.3
		if s.kind == "counter": best = minf(best, d * 1.3)
	for s in stations:
		if s.kind == "highway":
			best = minf(best, Vector2(end.x - s.pos.x, end.z - s.pos.z).length() * 1.3)
	return best if best < INF else 0.0


# ============================================================================ travel
## Where a ticket from this station (or counter) goes: every town discovered on the ride, and
## the core. Price and time follow the distance by road (1.3 x straight).
func destinations(from_id: String) -> Array:
	var from: Dictionary = by_id.get(from_id, {})
	var here := String(from.get("town", ""))
	var out: Array = []
	for cid in ["core", "campo_real", "puerto_alto", "valdoro", "sarmada", "isola_serena"]:
		if cid == here: continue
		var arrive := _arrival(cid)
		if arrive.is_empty(): continue
		var km := Vector2(arrive.pos.x - from.pos.x, arrive.pos.z - from.pos.z).length() * 1.3 / 1000.0 if not from.is_empty() else 0.0
		var open := _discovered(cid)
		out.append({"id": cid, "name": _town_name(cid), "pos": arrive.pos, "km": km, "minutes": roundi(km / COACH_KMH * 60.0 + 10.0),
			"price": TICKET_BASE + ceili(km * TICKET_PER_KM), "open": open, "ferry": _port(here) and _port(cid),
			"reason": "" if open else "Visit %s by road first" % _town_name(cid)})
	return out


func _port(cid: String) -> bool:
	return cid in ["core", "puerto_alto", "sarmada", "isola_serena"]


func _discovered(cid: String) -> bool:
	if cid == "core": return true
	if game.colony == null or game.colony.economy == null: return true
	var t: ColonyTown = game.colony.economy.town(cid)
	return t == null or t.discovered


func _town_name(cid: String) -> String:
	if TOWN_NAMES.has(cid): return TOWN_NAMES[cid]
	return String(EconomyCatalog.COLONIES.get(cid, {}).get("name", cid.capitalize()))


## Where a coach drops the courier in a town: its station (the core: the Villa Rosa counter).
func _arrival(cid: String) -> Dictionary:
	if cid == "core": return by_id.get("counter.villa_rosa_office", {})
	return by_id.get("station.%s" % cid, {})


## Ride the coach (a ferry between ports) with the bike on the roof rack: pay, the clock moves
## on, the courier and his bike are set down at the destination. "" on success, else why not.
## Why a ticket from `from_id` to `to_cid` cannot be bought now, or "" (nothing is spent).
func travel_check(from_id: String, to_cid: String) -> String:
	return _travel(from_id, to_cid, true)


func travel(from_id: String, to_cid: String) -> String:
	return _travel(from_id, to_cid, false)


func _travel(from_id: String, to_cid: String, dry: bool) -> String:
	var from: Dictionary = by_id.get(from_id, {})
	if from.is_empty() or not from.get("coach", false): return "No coach stops here."
	var dest: Dictionary = {}
	for d in destinations(from_id):
		if d.id == to_cid: dest = d
	if dest.is_empty(): return "No coach to there."
	if not dest.open: return "%s." % dest.reason
	var rider: Rider = game.rider
	if rider.vehicle != game.bike: return "The coach takes your bike, not the jeep: fetch the bike first."
	if game.bike.is_towing(): return "Unhitch the cart first: it can't ride the coach."
	if game.gm.carrying and DeliverySystem.needs_cargo_vehicle(game.gm.current_job()):
		return "Cargo freight can't ride the coach."
	var bike_d := game.bike.global_position.distance_to(rider.courier().global_position)
	if not rider.is_riding() and bike_d > 40.0: return "Bring your bike to the station: it rides on the roof rack."
	if dry: return "" if game.gm.coins >= int(dest.price) else "A ticket to %s costs %d coins." % [dest.name, dest.price]
	if not game.gm.spend_coins(int(dest.price)): return "A ticket to %s costs %d coins." % [dest.name, dest.price]
	var arrive := _arrival(to_cid)
	var at: Vector3 = arrive.pos
	var fwd: Vector3 = arrive.forward
	if arrive.kind == "counter":
		var sp: Dictionary = game.world.road_spawn(at + Vector3(6, 0, 0), at)
		at = sp.pos; fwd = sp.forward
	else:
		at = arrive.pos - (arrive.out as Vector3) * 2.0     # on the apron by the pumps
	rider.respawn_at(at, fwd)
	game.world.set_focus(rider.courier())
	if game.world.outer != null and game.world.outer.ok: game.world.outer.refresh_collision()
	game.world.streamer.load_all_pending()
	game.cam.snap_to_target()
	if game.life: game.life.advance_to(game.life.total_minutes + float(dest.minutes))
	_check_t = 0.0
	Events.message.emit("%s to %s · %d coins · %d min. Your bike is off the roof rack." % ["Ferry" if dest.ferry else "Coach", dest.name, dest.price, dest.minutes], 4.0)
	return ""


# ============================================================================ drawing
func _process(delta: float) -> void:
	_check_t -= delta
	if _check_t > 0.0: return
	_check_t = 0.25
	var cam := get_viewport().get_camera_3d()
	var v: Vector3 = cam.global_position if cam else (game.rider.courier().global_position if game and game.rider else Vector3.ZERO)
	var built := false
	for s in stations:
		if s.kind == "counter": continue
		var d := Vector2(v.x - s.pos.x, v.z - s.pos.z).length()
		var node: Node3D = _nodes.get(s.id)
		if node == null and d < DRAW_RADIUS and not built:
			_nodes[s.id] = _build(s)
			built = true            # one a pass
		elif node != null and d > FREE_RADIUS:
			node.queue_free()
			_nodes.erase(s.id)


func is_built(id: String) -> bool:
	return _nodes.has(id)


func _mat(key: String, c: Color, rough := 0.8, metal := 0.0, emit := Color.BLACK) -> Material:
	if not _mats.has(key): _mats[key] = Mats.solid(c, rough, metal, emit)
	return _mats[key]


## A station in its local frame: +X along the road, +Z away from it, origin = apron centre at
## road height. Solid parts on layer 1 so the bike rides the apron and stops at a pump.
func _build(s: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = String(s.id).replace(".", "_")
	var out: Vector3 = s.out
	var along := Vector3(out.z, 0.0, -out.x)          # right-handed with (up, out) on either side
	root.transform = Transform3D(Basis(along, Vector3.UP, out), s.pos)
	add_child(root)
	var body := StaticBody3D.new(); body.collision_layer = 1; body.collision_mask = 0
	body.set_meta("surface", &"stone")
	root.add_child(body)
	var depth: float = maxf(0.6, float(s.pos.y) - float(s.get("low", s.pos.y)) + 0.6)
	var top := 0.03
	_box(root, body, Vector3(APRON_LENGTH, depth, APRON_DEPTH), Vector3(0, top - depth * 0.5, 0), _mat("apron", Color(0.5, 0.49, 0.46), 0.9))
	# kerb along the far side and painted bay lines
	_box(root, null, Vector3(APRON_LENGTH, 0.16, 0.3), Vector3(0, top + 0.08, APRON_DEPTH * 0.5 - 0.15), _mat("kerb", Color(0.78, 0.76, 0.7)))
	for x in [-9.0, -3.0, 3.0, 9.0]:
		_box(root, null, Vector3(0.12, 0.01, 4.0), Vector3(x, top + 0.006, 1.5), _mat("paint", Color(0.92, 0.9, 0.82), 0.7))
	# pump islands under the canopy
	for x in [-4.0, 4.0]:
		_box(root, body, Vector3(1.1, 0.22, 3.4), Vector3(x, top + 0.11, 0.2), _mat("kerb", Color(0.78, 0.76, 0.7)))
		for z in [-0.6, 1.0]:
			_box(root, body, Vector3(0.62, 1.55, 0.46), Vector3(x, top + 0.22 + 0.78, z), _mat("pump", Color(0.72, 0.12, 0.1), 0.5))
			_box(root, null, Vector3(0.64, 0.34, 0.48), Vector3(x, top + 0.22 + 1.72, z), _mat("pumptop", Color(0.95, 0.93, 0.88), 0.4, 0.0, Color(0.35, 0.33, 0.28)))
			_box(root, null, Vector3(0.5, 0.26, 0.02), Vector3(x, top + 0.22 + 1.15, z - 0.24), _mat("dial", Color(0.9, 0.88, 0.75), 0.3, 0.0, Color(0.25, 0.24, 0.18)))
			root.add_child(Mats.cylinder(0.025, 1.1, _mat("hose", Color(0.08, 0.08, 0.08), 0.6), Vector3(x + 0.33, top + 0.9, z), Vector3(0, 0, 8), 6))
	# the canopy: four columns, a white roof with a red fascia
	for x in [-7.5, 7.5]:
		for z in [-2.6, 3.0]:
			var col := Mats.cylinder(0.16, 4.8, _mat("column", Color(0.9, 0.9, 0.88), 0.5), Vector3(x, top + 2.4, z), Vector3.ZERO, 10)
			root.add_child(col)
			_shape(body, Vector3(0.34, 4.8, 0.34), Vector3(x, top + 2.4, z))
	_box(root, null, Vector3(18.5, 0.45, 8.4), Vector3(0, top + 5.0, 0.2), _mat("roof", Color(0.94, 0.94, 0.92), 0.6))
	_box(root, null, Vector3(18.7, 0.5, 8.6), Vector3(0, top + 4.62, 0.2), _mat("fascia", Color(0.75, 0.13, 0.1), 0.55))
	for i in range(3):
		_box(root, null, Vector3(1.2, 0.05, 1.2), Vector3(-5.0 + i * 5.0, top + 4.35, 0.2), _mat("lamp", Color(1, 0.97, 0.88), 0.3, 0.0, Color(0.9, 0.85, 0.7)))
	# the shop (in a town, the coach & ferry ticket office too)
	var shop_x := 13.0
	_box(root, body, Vector3(7.0, 3.3, 5.2), Vector3(shop_x, top + 1.65, 3.6), _mat("shopwall", Color(0.93, 0.88, 0.76), 0.85))
	_box(root, null, Vector3(7.4, 0.3, 5.6), Vector3(shop_x, top + 3.45, 3.6), _mat("fascia", Color(0.75, 0.13, 0.1), 0.55))
	_box(root, null, Vector3(4.2, 1.5, 0.06), Vector3(shop_x + 0.6, top + 1.7, 0.98), _mat("glass", Color(0.25, 0.32, 0.36), 0.15, 0.3))
	_box(root, null, Vector3(1.1, 2.2, 0.06), Vector3(shop_x - 2.4, top + 1.1, 0.98), _mat("door", Color(0.3, 0.22, 0.15), 0.7))
	var shop_sign := _label(root, "COACH & FERRY" if s.coach else "SHOP", Vector3(shop_x, top + 3.45, 0.77), 0.006, Color(1, 0.96, 0.88), true)
	shop_sign.rotation.y = PI
	# the tall sign by the road, readable from a few hundred metres
	var pole := Vector3(-15.0, 0.0, -APRON_DEPTH * 0.5 + 1.6)
	root.add_child(Mats.cylinder(0.14, 7.0, _mat("pole", Color(0.55, 0.56, 0.58), 0.4, 0.6), pole + Vector3(0, top + 3.5, 0), Vector3.ZERO, 8))
	_shape(body, Vector3(0.3, 7.0, 0.3), pole + Vector3(0, top + 3.5, 0))
	_box(root, null, Vector3(0.3, 2.4, 3.6), pole + Vector3(0, top + 7.7, 0), _mat("sign", Color(0.75, 0.13, 0.1), 0.5, 0.0, Color(0.25, 0.03, 0.02)))
	for face in [-1.0, 1.0]:
		var big := _label(root, "FUEL", pole + Vector3(0.16 * face, top + 8.2, 0), 0.013, Color(1, 0.96, 0.86), true)
		big.rotation.y = PI * 0.5 * face
		var small := _label(root, String(s.name).to_upper(), pole + Vector3(0.16 * face, top + 7.1, 0), 0.0042, Color(1, 0.96, 0.86), true)
		small.rotation.y = PI * 0.5 * face
	if s.coach:
		# a coach shelter at the road side of the apron
		var sx := -12.0
		_box(root, body, Vector3(4.0, 0.12, 1.8), Vector3(sx, top + 2.6, 5.3), _mat("roof", Color(0.94, 0.94, 0.92), 0.6))
		_box(root, body, Vector3(4.0, 2.5, 0.08), Vector3(sx, top + 1.3, 6.1), _mat("glass", Color(0.25, 0.32, 0.36), 0.15, 0.3))
		_box(root, null, Vector3(3.0, 0.1, 0.45), Vector3(sx, top + 0.5, 5.7), _mat("bench", Color(0.45, 0.3, 0.18), 0.8))
		_box(root, null, Vector3(0.9, 0.6, 0.06), Vector3(sx + 1.3, top + 2.1, 6.0), _mat("coachsign", Color(0.1, 0.3, 0.55), 0.5, 0.0, Color(0.03, 0.08, 0.16)))
	return root


func _box(root: Node3D, body: StaticBody3D, size: Vector3, at: Vector3, mat: Material) -> void:
	root.add_child(Mats.box(size, mat, at))
	if body != null: _shape(body, size, at)


func _shape(body: StaticBody3D, size: Vector3, at: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new(); sh.size = size
	cs.shape = sh; cs.position = at
	body.add_child(cs)


func _label(root: Node3D, text: String, at: Vector3, px: float, col: Color, both: bool) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.pixel_size = px
	l.font_size = 64
	l.outline_size = 8
	l.modulate = col
	l.outline_modulate = Color(0.1, 0.05, 0.03)
	l.position = at
	l.double_sided = not both
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(l)
	return l
