class_name ShippingNetwork
extends RefCounted
## Sea routes, shipping lanes and ships. Pure simulation: a ship is a record whose position is a
## distance along its route, so every ship sails whether or not anything near it is loaded;
## ColonyEconomy gives the near ones a ShipModel.
##
## Water grid: 500 x 500 cells of 50 m over the 25 km country. A cell is navigable when the
## highest ground anywhere in it (the 12.5 m outer data, or the core's Terrain inside the core
## square) is at least MIN_DEPTH under the sea and no neighbour holds land (>= 50 m of coast
## clearance). The plan's sea lanes lower the cost of their cells, the coast raises it. AStarGrid2D
## finds the path; string-pulling over navigable cells and a check against the real ground make
## the route. Each port joins the grid by a straight, checked approach from its berth.
##
## Lanes: {id, from, to (colony ids with ports), out {item: n} loaded at `from`, back {item: n}
## loaded at `to`, ships [], trips, log}. Ships: {id, type, name, home, lane, state (building /
## docked / sailing), leg (0: from -> to, 1: back), s (m along the leg), timer, cargo, trips,
## raids}. Pirates: a lane passing an uncleared pirate cove risks a raid per leg.

const CELL := 50.0
const N := 500
const ORIGIN := -12500.0
const MIN_DEPTH := 2.0
const CORE_REACH := 720.0
const RAID_RADIUS := 2200.0
const RAID_MAX := 0.45
const PORT_TIME := 8.0
const SHIP_BUILD_TIME := 45.0
const MAX_SHIPS := 24
const MAX_LANES := 16
const COAST_RING1: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]
const COAST_RING2: Array[Vector2i] = [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2), Vector2i(2, 2), Vector2i(-2, -2), Vector2i(2, -2), Vector2i(-2, 2)]

var nav := PackedByteArray()          # 0 land / shallow, 1 navigable
var cell_max := PackedFloat32Array()  # highest ground in each cell
var ready := false
var build_ms := 0.0
var ports: Dictionary = {}            # colony id -> {id, berth: Vector3, heading (rad), approach: Vector2}
var plan_lanes: Array = []            # plan.json sea_lanes (seeds)
var lanes: Array = []
var ships: Array = []
var next_id := 1
var messages: Array = []              # notifications for the economy to publish
var pirates: Callable                 # () -> Array of {id, pos: Vector3} for uncleared pirate coves
var towns: Callable                   # (colony id) -> ColonyTown
var ground: Callable                  # (x, z) -> ground height (the real surface, for checks)
var _astar: AStarGrid2D
var _routes: Dictionary = {}          # "a|b" -> {points: PackedVector2Array, cum: PackedFloat32Array, length}
var _risk_cache: Dictionary = {}      # lane id -> risk (cleared when coves change)
var _thread_task := -1


# ------------------------------------------------------------------ the water grid
## Build the grid now. `outer` is the OuterGround (heights at 12.5 m, minmax leaves);
## `core_height` answers inside the core square (main thread only: Terrain3D data).
func build_grid(outer: OuterGround, core_height: Callable) -> void:
	start_async(outer, core_height, false)


## The core cells on this thread, the outer data and the A* grid on a worker (~1 s of GDScript
## at boot); `wait()` blocks for it. Routes are asked for only once the grid is ready.
func start_async(outer: OuterGround, core_height: Callable, threaded := true) -> void:
	var t0 := Time.get_ticks_usec()
	nav.resize(N * N); cell_max.resize(N * N)
	if core_height.is_valid(): _fill_core(core_height)
	if threaded:
		_thread_task = WorkerThreadPool.add_task(_build_outer.bind(outer, t0), false, "sea grid")
	else:
		_build_outer(outer, t0)


func wait() -> void:
	if _thread_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_thread_task)
		_thread_task = -1


## Poll from the main thread: true once the grid is usable.
func poll() -> bool:
	if _thread_task >= 0 and WorkerThreadPool.is_task_completed(_thread_task): wait()
	return ready and _thread_task < 0


func _build_outer(outer: OuterGround, t0: int) -> void:
	var H := outer.heights
	var DN := OuterGround.N
	var mm := outer.minmax
	var have_mm := mm.size() == 128 * 128 * 2
	for cj in range(N):
		var z0 := ORIGIN + cj * CELL
		var lj := floori((z0 + 12800.0) / 200.0)
		for ci in range(N):
			var x0 := ORIGIN + ci * CELL
			var k := cj * N + ci
			if absf(x0 + CELL * 0.5) < CORE_REACH and absf(z0 + CELL * 0.5) < CORE_REACH: continue
			if have_mm:
				var li := floori((x0 + 12800.0) / 200.0)
				var lk := (lj * 128 + li) * 2
				if mm[lk + 1] < -MIN_DEPTH - 1.0:
					cell_max[k] = mm[lk + 1]; continue
				if mm[lk] > 1.0:
					cell_max[k] = mm[lk]; continue
			var hi := -INF
			var di0 := ci * 4; var dj0 := cj * 4
			for dj in range(5):
				var row := mini(dj0 + dj, DN - 1) * DN
				for di in range(5):
					var h := H[row + mini(di0 + di, DN - 1)]
					if h > hi: hi = h
			cell_max[k] = hi + 0.45   # the lattice's micro relief
	_finish_grid()
	build_ms = (Time.get_ticks_usec() - t0) / 1000.0


func _fill_core(core_height: Callable) -> void:
	for cj in range(N):
		var z0 := ORIGIN + cj * CELL
		if absf(z0 + CELL * 0.5) >= CORE_REACH: continue
		for ci in range(N):
			var x0 := ORIGIN + ci * CELL
			if absf(x0 + CELL * 0.5) >= CORE_REACH: continue
			var hi := -INF
			for sj in range(5):
				for si in range(5):
					hi = maxf(hi, float(core_height.call(x0 + si * 12.5, z0 + sj * 12.5)))
			cell_max[cj * N + ci] = hi + 0.3


func _finish_grid() -> void:
	# navigable: the highest ground anywhere in the cell (every 12.5 m sample on and inside its
	# edges, plus the micro relief) is MIN_DEPTH under the sea - no land in it at all. The coast
	# is kept at a distance by cost (below), not by closing the estuary's narrows.
	for k in range(N * N): nav[k] = 0
	for cj in range(1, N - 1):
		for ci in range(1, N - 1):
			var k := cj * N + ci
			if cell_max[k] <= -MIN_DEPTH: nav[k] = 1
	_astar = AStarGrid2D.new()
	_astar.region = Rect2i(0, 0, N, N)
	_astar.cell_size = Vector2(CELL, CELL)
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.update()
	for cj in range(N):
		for ci in range(N):
			var k := cj * N + ci
			if nav[k] == 0:
				_astar.set_point_solid(Vector2i(ci, cj), true)
				continue
			# the coast costs more: ships keep to open water
			var weight := 1.0
			for d: Vector2i in COAST_RING1:
				var c := Vector2i(ci, cj) + d
				if c.x < 0 or c.y < 0 or c.x >= N or c.y >= N or nav[c.y * N + c.x] == 0: weight = 3.0; break
			if weight == 1.0:
				for d: Vector2i in COAST_RING2:
					var c := Vector2i(ci, cj) + d
					if c.x < 0 or c.y < 0 or c.x >= N or c.y >= N or nav[c.y * N + c.x] == 0: weight = 1.6; break
			_astar.set_point_weight_scale(Vector2i(ci, cj), weight)
	# the plan's sea lanes are the charted channels
	for lane in plan_lanes:
		for p in lane.get("points", []):
			var c := cell_of(Vector2(p[0], p[1]))
			for dj in range(-1, 2):
				for di in range(-1, 2):
					var q := c + Vector2i(di, dj)
					if _in(q) and nav[q.y * N + q.x] == 1: _astar.set_point_weight_scale(q, 0.55)
	ready = true
	_routes.clear()


func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(clampi(floori((p.x - ORIGIN) / CELL), 0, N - 1), clampi(floori((p.y - ORIGIN) / CELL), 0, N - 1))


func cell_centre(c: Vector2i) -> Vector2:
	return Vector2(ORIGIN + (c.x + 0.5) * CELL, ORIGIN + (c.y + 0.5) * CELL)


func _in(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < N and c.y < N


func navigable(p: Vector2) -> bool:
	var c := cell_of(p)
	return nav[c.y * N + c.x] == 1


# ------------------------------------------------------------------ ports and routes
## Register a plan port: where a ship lies alongside (the mooring: the nearest water off the
## quay edge - or the berth - deep enough along a hull's length, the hull parallel to the quay),
## and the way out of the harbour: a breadth-first search over a 12 m grid of real water from the
## mooring to the first navigable sea cell, pulled straight where the water allows.
func add_port(colony_id: String, berth: Vector3, heading_deg: float, quay_edges: Array = []) -> bool:
	var b := Vector2(berth.x, berth.z)
	var axis := Vector2(sin(deg_to_rad(heading_deg)), cos(deg_to_rad(heading_deg)))
	var anchor := b
	var best_q := INF
	for edge in quay_edges:
		for k in range(edge.size() - 1):
			var p0 := Vector2(edge[k][0], edge[k][1]); var p1 := Vector2(edge[k + 1][0], edge[k + 1][1])
			var q := Geometry2D.get_closest_point_to_segment(b, p0, p1)
			if q.distance_to(b) < best_q and q.distance_to(b) < 250.0:
				best_q = q.distance_to(b); anchor = q; axis = (p1 - p0).normalized()
	var moor := Vector2.INF
	for r in range(0, 240, 3):
		var n := maxi(8, int(TAU * r / 6.0))
		for k in range(n):
			var p := anchor + Vector2.from_angle(TAU * k / n) * r
			if _hull_fits(p, axis): moor = p; break
			if r == 0: break
		if moor != Vector2.INF: break
	if moor == Vector2.INF: return false
	var path := _harbour_path(moor)
	if path.is_empty(): return false
	# the shore behind the mooring (where a jetty out to the ship starts), walking back to the berth
	var shore := moor
	if ground.is_valid() and moor.distance_to(b) > 1.0:
		var back := (b - moor).normalized()
		for k in range(0, int(moor.distance_to(b)) + 40, 2):
			var q := moor + back * k
			if float(ground.call(q.x, q.y)) > 0.3: shore = q; break
	ports[colony_id] = {"id": colony_id, "berth": berth, "heading": deg_to_rad(heading_deg), "moor": moor, "along": axis, "shore": shore,
		"approach": path[path.size() - 1], "approach_path": path}
	_routes.clear()
	return true


## A hull (34 m x 7 m) lying along `axis` at `p` floats in >= 1.2 m of water.
func _hull_fits(p: Vector2, axis: Vector2) -> bool:
	if not ground.is_valid(): return true
	var side := axis.orthogonal()
	for q in [p, p + axis * 16.0, p - axis * 16.0, p + side * 4.0, p - side * 4.0, p + axis * 8.0 + side * 3.5, p - axis * 8.0 - side * 3.5]:
		if float(ground.call(q.x, q.y)) > -1.2: return false
	return true


func _wet(q: Vector2) -> bool:
	if float(ground.call(q.x, q.y)) > -1.2: return false
	for d in [Vector2(6, 0), Vector2(-6, 0), Vector2(0, 6), Vector2(0, -6)]:
		if float(ground.call(q.x + d.x, q.y + d.y)) > -0.6: return false
	return true


## Moor -> the first navigable sea cell, over water only (12 m BFS, then pulled straight).
func _harbour_path(moor: Vector2) -> PackedVector2Array:
	if navigable(moor): return PackedVector2Array([moor])
	if not ground.is_valid(): return PackedVector2Array()
	const S := 12.0
	const R := 110
	var queue: Array[Vector2i] = [Vector2i.ZERO]
	var parent := {Vector2i.ZERO: Vector2i.ZERO}
	var head := 0
	var found := Vector2i(1 << 20, 0)
	while head < queue.size() and head < 40000:
		var c: Vector2i = queue[head]; head += 1
		var p := moor + Vector2(c) * S
		if c != Vector2i.ZERO and navigable(p) and navigable(p + Vector2(S, 0)) and navigable(p - Vector2(S, 0)) and navigable(p + Vector2(0, S)) and navigable(p - Vector2(0, S)):
			found = c; break
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
			var nc: Vector2i = c + d
			if parent.has(nc) or absi(nc.x) > R or absi(nc.y) > R: continue
			parent[nc] = c
			if _wet(moor + Vector2(nc) * S): queue.append(nc)
	if found.x == 1 << 20: return PackedVector2Array()
	var cells: Array[Vector2i] = []
	var c := found
	while c != Vector2i.ZERO:
		cells.append(c); c = parent[c]
	cells.append(Vector2i.ZERO)
	cells.reverse()
	var raw := PackedVector2Array()
	for q in cells: raw.append(moor + Vector2(q) * S)
	var pulled := PackedVector2Array([raw[0]])
	var i := 0
	while i < raw.size() - 1:
		var j := raw.size() - 1
		while j > i + 1 and not _segment_wet(raw[i], raw[j], -0.8): j -= 1
		pulled.append(raw[j]); i = j
	return pulled


## The heading of a ship lying alongside at a port (along the quay).
func moor_dir(colony_id: String) -> Vector2:
	return ports[colony_id].along if ports.has(colony_id) else Vector2(0, 1)


## A straight segment over water: every 6 m of it lower than `limit` (the real ground).
func _segment_wet(a: Vector2, b: Vector2, limit: float) -> bool:
	if not ground.is_valid(): return true
	var n := maxi(1, ceili(a.distance_to(b) / 6.0))
	for i in range(n + 1):
		var p := a.lerp(b, float(i) / n)
		if float(ground.call(p.x, p.y)) >= limit: return false
	return true


## Every cell the segment a-b touches is navigable (an exact grid traversal, so a pulled or
## rounded route cannot clip the corner of a cell with land in it).
func _line_nav(a: Vector2, b: Vector2) -> bool:
	var ga := (a - Vector2(ORIGIN, ORIGIN)) / CELL; var gb := (b - Vector2(ORIGIN, ORIGIN)) / CELL
	var c := Vector2i(floori(ga.x), floori(ga.y)); var end := Vector2i(floori(gb.x), floori(gb.y))
	var d := gb - ga
	var step := Vector2i(signi(int(signf(d.x))), signi(int(signf(d.y))))
	var t_max := Vector2(INF, INF); var t_delta := Vector2(INF, INF)
	if d.x != 0.0:
		t_delta.x = absf(1.0 / d.x)
		t_max.x = ((c.x + (1 if d.x > 0.0 else 0)) - ga.x) / d.x
	if d.y != 0.0:
		t_delta.y = absf(1.0 / d.y)
		t_max.y = ((c.y + (1 if d.y > 0.0 else 0)) - ga.y) / d.y
	for guard in range(4 * N):
		if not _in(c) or nav[c.y * N + c.x] == 0: return false
		if c == end: return true
		if absf(t_max.x - t_max.y) < 1e-9:
			# through a corner: both side cells count
			if not _in(c + Vector2i(step.x, 0)) or nav[c.y * N + c.x + step.x] == 0: return false
			if not _in(c + Vector2i(0, step.y)) or nav[(c.y + step.y) * N + c.x] == 0: return false
			c += step; t_max += t_delta
		elif t_max.x < t_max.y:
			c.x += step.x; t_max.x += t_delta.x
		else:
			c.y += step.y; t_max.y += t_delta.y
	return false


## The route between two ports (cached): a PackedVector2Array from berth to berth.
func route(from_id: String, to_id: String) -> Dictionary:
	var key := from_id + "|" + to_id
	if _routes.has(key): return _routes[key]
	var back := to_id + "|" + from_id
	if _routes.has(back):
		var r: Dictionary = _routes[back]
		var pts: PackedVector2Array = (r.points as PackedVector2Array).duplicate(); pts.reverse()
		_routes[key] = _measure(pts)
		return _routes[key]
	if not ready or not ports.has(from_id) or not ports.has(to_id): return {}
	var a: Dictionary = ports[from_id]; var b: Dictionary = ports[to_id]
	var ids := _astar.get_id_path(cell_of(a.approach), cell_of(b.approach))
	if ids.is_empty(): return {}
	var cells := PackedVector2Array()
	for c in ids: cells.append(cell_centre(c))
	# string-pull: the furthest cell still in navigable line of sight
	var pulled := PackedVector2Array([cells[0]])
	var i := 0
	while i < cells.size() - 1:
		var j := cells.size() - 1
		while j > i + 1 and not _line_nav(cells[i], cells[j]): j -= 1
		pulled.append(cells[j]); i = j
	var pts := PackedVector2Array(a.approach_path)
	pts.append_array(pulled)
	var tail := PackedVector2Array(b.approach_path); tail.reverse()
	pts.append_array(tail)
	pts = _shortcut(pts)
	pts = _smooth(pts)
	_routes[key] = _measure(pts)
	return _routes[key]


## Straighten over real water: from each point, jump to the furthest of the next few within
## 2.5 km that a straight line over water reaches (removes the dog-legs where a harbour approach
## meets the sea grid).
func _shortcut(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array([pts[0]])
	var i := 0
	while i < pts.size() - 1:
		var best := i + 1
		for j in range(mini(pts.size() - 1, i + 8), i + 1, -1):
			if pts[i].distance_to(pts[j]) > 2500.0: continue
			if _line_nav(pts[i], pts[j]) or _segment_wet(pts[i], pts[j], -1.2):
				best = j; break
		out.append(pts[best]); i = best
	return out


## Round the corners: each interior vertex becomes two points `cut` metres back along its edges
## when the chord between them stays in navigable water (berths and approaches stay fixed).
func _smooth(pts: PackedVector2Array) -> PackedVector2Array:
	for pass_i in range(3):
		if pts.size() < 5: break
		var out := PackedVector2Array([pts[0], pts[1]])
		for k in range(2, pts.size() - 2):
			var v := pts[k]; var prev := pts[k - 1]; var next := pts[k + 1]
			var cut := minf(minf(v.distance_to(prev), v.distance_to(next)) * 0.3, 350.0)
			var a := v + (prev - v).normalized() * cut
			var b := v + (next - v).normalized() * cut
			if cut > 5.0 and _line_nav(a, b):
				out.append(a); out.append(b)
			else:
				out.append(v)
		out.append(pts[pts.size() - 2]); out.append(pts[pts.size() - 1])
		pts = out
	var clean := PackedVector2Array([pts[0]])
	for p in pts:
		if p.distance_to(clean[clean.size() - 1]) > 1.0: clean.append(p)
	return clean


func _measure(pts: PackedVector2Array) -> Dictionary:
	var cum := PackedFloat32Array([0.0])
	for k in range(1, pts.size()): cum.append(cum[k - 1] + pts[k].distance_to(pts[k - 1]))
	return {"points": pts, "cum": cum, "length": cum[cum.size() - 1]}


## Position and heading `s` metres along a route.
static func point_at(r: Dictionary, s: float) -> Array:
	var pts: PackedVector2Array = r.points; var cum: PackedFloat32Array = r.cum
	s = clampf(s, 0.0, float(r.length))
	var lo := 0; var hi := cum.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if cum[mid] <= s: lo = mid
		else: hi = mid
	var seg := maxf(cum[hi] - cum[lo], 0.001)
	var p := pts[lo].lerp(pts[hi], (s - cum[lo]) / seg)
	var dir := (pts[hi] - pts[lo]).normalized()
	# look a little ahead so the bow eases into the turns
	var ahead := mini(hi + 1, pts.size() - 1)
	if ahead != hi and s > cum[hi] - 30.0: dir = dir.lerp((pts[ahead] - pts[hi]).normalized(), clampf((s - (cum[hi] - 30.0)) / 60.0, 0.0, 0.5)).normalized()
	return [p, dir]


# ------------------------------------------------------------------ lanes and ships
func lane(lid: String) -> Dictionary:
	for l in lanes:
		if l.id == lid: return l
	return {}


func ship(sid: String) -> Dictionary:
	for s in ships:
		if s.id == sid: return s
	return {}


func add_lane(from_id: String, to_id: String, out: Dictionary, back: Dictionary) -> Dictionary:
	if lanes.size() >= MAX_LANES or from_id == to_id or not ports.has(from_id) or not ports.has(to_id): return {}
	if route(from_id, to_id).is_empty(): return {}
	var l := {"id": "lane.%d" % next_id, "from": from_id, "to": to_id, "out": _clean_rule(out), "back": _clean_rule(back),
		"ships": [], "trips": 0, "log": []}
	next_id += 1
	lanes.append(l)
	_risk_cache.erase(l.id)
	return l


func remove_lane(lid: String) -> bool:
	for i in range(lanes.size()):
		if lanes[i].id == lid:
			for sid in lanes[i].ships:
				var s := ship(sid)
				if not s.is_empty(): s.lane = ""
			lanes.remove_at(i)
			return true
	return false


static func _clean_rule(rule: Dictionary) -> Dictionary:
	var out := {}
	for item in rule:
		if EconomyCatalog.ITEMS.has(item) and int(rule[item]) > 0: out[String(item)] = clampi(int(rule[item]), 1, 200)
	return out


## A ship on the stocks at `home` (the shipyard's colony). Costs are paid by the caller.
func add_ship(type: String, home: String) -> Dictionary:
	if ships.size() >= MAX_SHIPS or not EconomyCatalog.SHIPS.has(type) or not ports.has(home): return {}
	var s := {"id": "ship.%d" % next_id, "type": type, "name": EconomyCatalog.SHIP_NAMES[(next_id - 1) % EconomyCatalog.SHIP_NAMES.size()],
		"home": home, "port": home, "lane": "", "state": "building", "leg": 0, "s": 0.0, "timer": SHIP_BUILD_TIME,
		"cargo": {}, "trips": 0, "raids": 0}
	next_id += 1
	ships.append(s)
	return s


## Put a ship on a lane. It sails (empty if need be) to the lane's first port and starts there.
func assign(sid: String, lid: String) -> bool:
	var s := ship(sid); var l := lane(lid)
	if s.is_empty() or (lid != "" and l.is_empty()): return false
	if s.lane != "":
		var old := lane(s.lane)
		if not old.is_empty(): old.ships.erase(sid)
	s.lane = lid
	if lid == "": return true
	l.ships.append(sid)
	if s.state == "docked":
		if s.port == l.from: _begin_port(s, l, 0)
		elif s.port == l.to: _begin_port(s, l, 1)
		else: _reposition(s, l)
	return true


func _reposition(s: Dictionary, l: Dictionary) -> void:
	# a short positioning voyage from wherever it lies to the lane's first port
	if route(s.port, l.from).is_empty(): return
	s.state = "sailing"; s.leg = 2; s.s = 0.0; s.timer = 0.0
	s["reposition"] = [s.port, l.from]


func capacity(s: Dictionary) -> int:
	return int(EconomyCatalog.SHIPS[s.type].capacity)


func speed(s: Dictionary) -> float:
	return float(EconomyCatalog.SHIPS[s.type].speed)


func cargo_units(s: Dictionary) -> int:
	var n := 0
	for item in s.cargo: n += int(s.cargo[item])
	return n


## The route a ship is sailing now.
func current_route(s: Dictionary) -> Dictionary:
	if s.state != "sailing": return {}
	if int(s.leg) == 2:
		var rp: Array = s.get("reposition", [])
		return route(rp[0], rp[1]) if rp.size() == 2 else {}
	var l := lane(s.lane)
	if l.is_empty(): return {}
	return route(l.from, l.to) if int(s.leg) == 0 else route(l.to, l.from)


## Where a ship is: [Vector2 position, Vector2 heading, docked].
func ship_pose(s: Dictionary) -> Array:
	if s.state == "sailing":
		var r := current_route(s)
		if not r.is_empty():
			var at := point_at(r, float(s.s))
			return [at[0], at[1], false]
	var p: Dictionary = ports.get(s.port, {})
	if p.is_empty(): return [Vector2.ZERO, Vector2(0, 1), true]
	# ships in port lie in a line along the quay, the first at the jetty
	var k := 0
	for o in ships:
		if o.id == s.id: break
		if o.port == s.port and o.state == "docked": k += 1
	if k == 0: return [p.moor, p.along, true]
	var slot := (k + 1) / 2 * (1 if k % 2 == 1 else -1)
	var at: Vector2 = p.moor + (p.along as Vector2) * 38.0 * slot
	if ground.is_valid() and not _hull_fits(at, p.along): at = p.moor + (p.moor - p.get("shore", p.moor)).normalized() * 14.0 * k
	return [at, p.along, true]


func tick(dt: float) -> void:
	for s in ships: _tick_ship(s, dt)


func _tick_ship(s: Dictionary, dt: float) -> void:
	match String(s.state):
		"building":
			s.timer = float(s.timer) - dt
			if float(s.timer) <= 0.0:
				s.state = "docked"; s.timer = 0.0
				_say("%s (%s) is launched at %s." % [s.name, EconomyCatalog.SHIPS[s.type].name, _town_name(s.home)])
				if s.lane != "":
					var l := lane(s.lane)
					if not l.is_empty():
						if s.port == l.from: _begin_port(s, l, 0)
						elif s.port == l.to: _begin_port(s, l, 1)
						else: _reposition(s, l)
		"docked":
			if s.lane == "": return
			s.timer = float(s.timer) - dt
			if float(s.timer) > 0.0: return
			var l := lane(s.lane)
			if l.is_empty(): s.lane = ""; return
			var leg := 0 if s.port == l.from else 1
			if route(l.from, l.to).is_empty(): return
			s.state = "sailing"; s.leg = leg; s.s = 0.0
		"sailing":
			var r := current_route(s)
			if r.is_empty():
				s.state = "docked"; return
			s.s = float(s.s) + speed(s) * dt
			if float(s.s) < float(r.length): return
			_arrive(s)


func _arrive(s: Dictionary) -> void:
	var l := lane(s.lane)
	if int(s.leg) == 2:
		var rp: Array = s.get("reposition", [s.port, s.port])
		s.port = rp[1]; s.erase("reposition")
		s.state = "docked"; s.s = 0.0
		if not l.is_empty(): _begin_port(s, l, 0 if s.port == l.from else 1)
		return
	if l.is_empty():
		s.state = "docked"; s.s = 0.0; return
	var dest: String = l.to if int(s.leg) == 0 else l.from
	s.port = dest; s.state = "docked"; s.s = 0.0
	# pirates
	var risk := lane_risk(l)
	if risk > 0.0 and cargo_units(s) > 0:
		var roll := float(absi(hash([s.id, int(s.trips), l.id])) % 10000) / 10000.0
		if roll < risk:
			var lost := {}
			for item in s.cargo:
				var n := int(s.cargo[item]); var gone := ceili(n * 0.4)
				lost[item] = gone; s.cargo[item] = n - gone
			s.raids = int(s.raids) + 1
			var what := PackedStringArray()
			for item in lost: what.append("%d %s" % [lost[item], EconomyCatalog.item_name(item).to_lower()])
			var text := "Pirates raided %s on the %s lane: lost %s." % [s.name, lane_title(l), ", ".join(what)]
			_say(text); _lane_log(l, text)
	s.trips = int(s.trips) + 1
	l.trips = int(l.trips) + 1
	_begin_port(s, l, 1 if dest == l.to else 0)


## At a lane port: unload everything aboard, then load by the rule of the next leg.
func _begin_port(s: Dictionary, l: Dictionary, next_leg: int) -> void:
	var here: String = l.from if next_leg == 0 else l.to
	var town: ColonyTown = towns.call(here) if towns.is_valid() else null
	var moved := 0
	var unloaded := PackedStringArray(); var loaded := PackedStringArray()
	if town != null and town.founded:
		for item in s.cargo.keys():
			var n := int(s.cargo[item]); var put := town.add(item, n)
			if put > 0: unloaded.append("%d %s" % [put, EconomyCatalog.item_name(item).to_lower()])
			moved += put
			if put >= n: s.cargo.erase(item)
			else: s.cargo[item] = n - put
		var rule: Dictionary = l.out if next_leg == 0 else l.back
		for item in rule:
			var room := capacity(s) - cargo_units(s)
			if room <= 0: break
			var have := int(s.cargo.get(item, 0))
			var want := mini(int(rule[item]) - have, room)
			if want <= 0: continue
			var got := town.take(item, want)
			if got > 0:
				s.cargo[item] = have + got; moved += got
				loaded.append("%d %s" % [got, EconomyCatalog.item_name(item).to_lower()])
	s.port = here; s.state = "docked"; s.leg = next_leg
	s.timer = PORT_TIME + moved * float(EconomyCatalog.SHIPS[s.type].load_s)
	if not unloaded.is_empty() or not loaded.is_empty():
		_lane_log(l, "%s at %s: %s%s" % [s.name, _town_name(here),
			("unloaded " + ", ".join(unloaded)) if not unloaded.is_empty() else "",
			((" · " if not unloaded.is_empty() else "") + "loaded " + ", ".join(loaded)) if not loaded.is_empty() else ""])


func _lane_log(l: Dictionary, text: String) -> void:
	l.log.append(text)
	if l.log.size() > 12: l.log.pop_front()


func _say(text: String) -> void:
	messages.append(text)


func _town_name(cid: String) -> String:
	return String(EconomyCatalog.COLONIES.get(cid, {}).get("name", cid)).get_slice(" (", 0)


func lane_title(l: Dictionary) -> String:
	return "%s - %s" % [_town_name(l.from), _town_name(l.to)]


# ------------------------------------------------------------------ pirates
## Raid chance per leg: the nearest uncleared pirate cove's distance to the route.
func lane_risk(l: Dictionary) -> float:
	if _risk_cache.has(l.id): return _risk_cache[l.id]
	var r := route(l.from, l.to)
	var risk := 0.0
	if not r.is_empty() and pirates.is_valid():
		for camp in pirates.call():
			var d := route_distance(r, Vector2(camp.pos.x, camp.pos.z))
			if d < RAID_RADIUS: risk = maxf(risk, RAID_MAX * clampf(1.0 - (d - 300.0) / (RAID_RADIUS - 300.0), 0.0, 1.0))
	_risk_cache[l.id] = risk
	return risk


## The coves that threaten a lane (for the Trade panel).
func lane_threats(l: Dictionary) -> Array:
	var out: Array = []
	var r := route(l.from, l.to)
	if r.is_empty() or not pirates.is_valid(): return out
	for camp in pirates.call():
		if route_distance(r, Vector2(camp.pos.x, camp.pos.z)) < RAID_RADIUS: out.append(camp.id)
	return out


static func route_distance(r: Dictionary, p: Vector2) -> float:
	var pts: PackedVector2Array = r.points
	var best := INF
	for k in range(pts.size() - 1):
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, pts[k], pts[k + 1])))
	return best


func pirates_changed() -> void:
	_risk_cache.clear()


# ------------------------------------------------------------------ persistence
func save_state() -> Dictionary:
	return {"next_id": next_id, "lanes": lanes.duplicate(true), "ships": ships.duplicate(true)}


static func valid(d: Variant, port_ids: Array) -> bool:
	if not d is Dictionary or not ColonyTown._num(d.get("next_id"), 1, 1e7): return false
	if not d.get("lanes") is Array or d.lanes.size() > MAX_LANES or not d.get("ships") is Array or d.ships.size() > MAX_SHIPS: return false
	var lids := {}
	for l in d.lanes:
		if not l is Dictionary or not l.get("id") is String or lids.has(l.id): return false
		if not l.get("from") in port_ids or not l.get("to") in port_ids or l.from == l.to: return false
		if not _rule(l.get("out")) or not _rule(l.get("back")) or not l.get("ships") is Array or not l.get("log") is Array or not ColonyTown._num(l.get("trips"), 0, 1e9): return false
		lids[l.id] = true
	var sids := {}
	for s in d.ships:
		if not s is Dictionary or not s.get("id") is String or sids.has(s.id) or not EconomyCatalog.SHIPS.has(s.get("type")) or not s.get("name") is String: return false
		if not s.get("home") in port_ids or not s.get("port") in port_ids or not s.get("state") in ["building", "docked", "sailing"]: return false
		if not s.get("lane") is String or (s.lane != "" and not lids.has(s.lane)) or not int(s.get("leg", -1)) in [0, 1, 2]: return false
		if not ColonyTown._num(s.get("s"), 0.0, 1e6) or not ColonyTown._num(s.get("timer"), -1e3, 1e6) or not ColonyTown._inventory(s.get("cargo")): return false
		if not ColonyTown._num(s.get("trips"), 0, 1e9) or not ColonyTown._num(s.get("raids"), 0, 1e9): return false
		var units := 0
		for item in s.cargo: units += int(s.cargo[item])
		if units > int(EconomyCatalog.SHIPS[s.type].capacity): return false
		if int(s.leg) == 2 and (not s.get("reposition") is Array or s.reposition.size() != 2 or not s.reposition[0] in port_ids or not s.reposition[1] in port_ids): return false
		sids[s.id] = true
	for l in d.lanes:
		for sid in l.ships:
			if not sids.has(sid): return false
	return true


static func _rule(v: Variant) -> bool:
	if not ColonyTown._inventory(v): return false
	for item in v:
		if int(v[item]) < 1 or int(v[item]) > 200: return false
	return true


func load_state(d: Dictionary) -> void:
	next_id = int(d.next_id)
	lanes = []
	for l in d.lanes:
		var r: Dictionary = l.duplicate(true)
		r.out = ColonyTown._ints(r.out); r.back = ColonyTown._ints(r.back); r.trips = int(r.trips)
		lanes.append(r)
	ships = []
	for s in d.ships:
		var r: Dictionary = s.duplicate(true)
		r.cargo = ColonyTown._ints(r.cargo); r.leg = int(r.leg); r.trips = int(r.trips); r.raids = int(r.raids)
		ships.append(r)
	_risk_cache.clear()
