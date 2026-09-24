class_name TownPopulation
extends RefCounted
## The ambient people of one outer town or hamlet, decided from its plan.json record (ADR 0010):
##   - spots: where people can be — home doors, market stalls (vendor behind, shoppers in
##     front), shop doors, bench seats and cafe chairs, net racks, quay edges and crates for
##     fishers and dockworkers, gardens and barn doors for farmers, chat spots round fountains
##     and on the plaza;
##   - a walking graph on the streets (sidewalk lanes on streets, a grid over plazas and quays),
##     with every node clear of the plots and the props, so a route never goes through a
##     building, a fountain or a stall;
##   - the people: a count scaled by the plots, each with a seed, an occupation fitting the place
##     and the spot it works at, a home, and a daily routine (home -> work -> lunch -> work ->
##     the plaza -> home).
## `generate()` is pure data from the plan and a height function (safe on a worker thread) and is
## deterministic: the same plan gives the same people. Live state (who sits where right now) is
## `occupant`, reset whenever the town is activated.

const STEP := 4.5                  # graph spacing along a street
const GRID := 4.5                  # grid spacing over plazas and wide quays
const LINK := 4.2                  # street-to-street junction reach
const MARGIN := 0.45               # clearance round plots and props
const CELL := 12.0                 # obstacle / spot bucket size
const RESIDENTIAL := ["house", "rowhouse", "palazzo", "tower", "shop"]
const NEAR_REACH := 150.0          # how far from home / work people spend their day

## per style: occupations for people without a work spot (weights), and who works what
const IDLE_JOBS := {
	&"puerto": {"": 6, "teacher": 1, "courier": 1, "cook": 1, "merchant": 1, "porter": 1},
	&"valdoro": {"": 6, "shepherd": 2, "woodcutter": 1, "teacher": 1},
	&"sarmada": {"": 6, "weaver": 2, "porter": 2, "merchant": 1},
	&"isola": {"": 6, "fisher": 2, "gardener": 1, "cook": 1},
	&"campo": {"": 6, "farmer": 3, "baker": 1, "teacher": 1},
}

var id := ""
var display_name := ""
var style: StringName = &"island"
var kind := "town"
var centre := Vector3.ZERO
var radius := 200.0
var ready := false

var graph := AStar3D.new()
var node_street: PackedInt32Array = PackedInt32Array()
var spots: Array = []              # {k, p, f, pose, node, seat, b, prop}
var occupant := PackedInt32Array() # spot -> person index, -1 free (live)
var people: Array = []             # Townsperson
var homes: Array = []              # spot indices of doors
var counts := {}                   # occupation -> n (reporting)

var _height: Callable
var _rects: Dictionary = {}        # Vector2i -> [[cx, cz, tx, tz, hw, hd], ...]
var _node_cells: Dictionary = {}   # Vector2i -> [node ids]
var _spot_cells: Dictionary = {}   # Vector2i -> [spot ids]
var _paths: Dictionary = {}        # "a>b" -> PackedVector3Array (without lane offsets)
var _plan: Dictionary = {}
var generate_ms := 0.0


func _init(plan_record: Dictionary, height: Callable) -> void:
	_plan = plan_record
	_height = height
	id = String(plan_record.id)
	display_name = String(plan_record.get("name", id))
	style = StringName(plan_record.get("style", "campo"))
	kind = String(plan_record.get("kind", "town"))
	var pz: Array = plan_record.plaza if plan_record.get("plaza") != null else [plan_record.center[0], 0.0, plan_record.center[1]]
	centre = Vector3(pz[0], pz[1], pz[2])
	radius = float(plan_record.get("radius", 150.0))


## How many people live here: ~0.6 a plot (Puerto Alto ~400, a hamlet a handful).
static func population_for(plan_record: Dictionary) -> int:
	return clampi(roundi((plan_record.plots as Array).size() * 0.7) + 2, 3, 480)


func generate() -> void:
	var t0 := Time.get_ticks_usec()
	_obstacles()
	_streets()
	_spots()
	_people()
	occupant = PackedInt32Array(); occupant.resize(spots.size()); occupant.fill(-1)
	generate_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	ready = true


func h(x: float, z: float) -> float:
	return float(_height.call(x, z))


# ---------------------------------------------------------------- obstacles
func _add_rect(cx: float, cz: float, yaw: float, hw: float, hd: float) -> void:
	var f := Vector2(sin(yaw), cos(yaw)); var t := Vector2(f.y, -f.x)
	var r := [cx, cz, t.x, t.y, hw, hd]
	var reach := sqrt(hw * hw + hd * hd) + MARGIN
	for x in range(floori((cx - reach) / CELL), floori((cx + reach) / CELL) + 1):
		for z in range(floori((cz - reach) / CELL), floori((cz + reach) / CELL) + 1):
			var k := Vector2i(x, z)
			if not _rects.has(k): _rects[k] = []
			_rects[k].append(r)


func _obstacles() -> void:
	for p: Dictionary in _plan.plots:
		if p.kind == "gate": continue
		_add_rect(float(p.x), float(p.z), deg_to_rad(float(p.yaw)), float(p.w) * 0.5, float(p.d) * 0.5)
	for rec: Array in _plan.get("props", []):
		var k := String(rec[0])
		if k.begins_with("tree:"):
			_add_rect(float(rec[1]), float(rec[3]), 0.0, 0.55, 0.55)
			continue
		if k in ["washing", "jetty", "boat_fishing", "boat_small", "dinghy"]: continue
		var fp := ArchProps.footprint(k)
		if fp == Vector3.ZERO: continue
		_add_rect(float(rec[1]), float(rec[3]), deg_to_rad(float(rec[4])), fp.x, fp.z)


## Is the ground point clear of every plot and prop (with `margin`)?
func clear(x: float, z: float, margin: float = MARGIN) -> bool:
	for r in _rects.get(Vector2i(floori(x / CELL), floori(z / CELL)), []):
		var dx: float = x - r[0]; var dz: float = z - r[1]
		var a: float = dx * r[2] + dz * r[3]
		var b: float = dx * r[3] - dz * r[2]
		if absf(a) < r[4] + margin and absf(b) < r[5] + margin: return false
	return true


func segment_clear(a: Vector3, b: Vector3, margin: float = 0.25) -> bool:
	var d := Vector2(b.x - a.x, b.z - a.z).length()
	var n := maxi(1, ceili(d / 0.8))
	for i in range(1, n):
		var q := a.lerp(b, float(i) / n)
		if not clear(q.x, q.z, margin): return false
	return true


# ---------------------------------------------------------------- the walking graph
func _node(p: Vector2, street: int) -> int:
	var nid := graph.get_available_point_id()
	graph.add_point(nid, Vector3(p.x, h(p.x, p.y), p.y))
	node_street.append(street)
	var k := Vector2i(floori(p.x / CELL), floori(p.y / CELL))
	if not _node_cells.has(k): _node_cells[k] = []
	_node_cells[k].append(nid)
	return nid


func _link(a: int, b: int) -> void:
	if a < 0 or b < 0 or a == b: return
	var pa := graph.get_point_position(a); var pb := graph.get_point_position(b)
	if absf(pa.y - pb.y) > 2.2: return
	var mid := (pa + pb) * 0.5
	if not clear(mid.x, mid.z, 0.3): return
	graph.connect_points(a, b)


static func _resample(pts: Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if pts.is_empty(): return out
	out.append(Vector2(pts[0][0], pts[0][2]))
	var carry := 0.0
	for i in range(1, pts.size()):
		var a := Vector2(pts[i - 1][0], pts[i - 1][2]); var b := Vector2(pts[i][0], pts[i][2])
		var seg := a.distance_to(b)
		var d := step - carry
		while d <= seg:
			out.append(a.lerp(b, d / maxf(seg, 0.0001)))
			d += step
		carry = seg - (d - step)
	var last := Vector2(pts[pts.size() - 1][0], pts[pts.size() - 1][2])
	if out[out.size() - 1].distance_to(last) > step * 0.4: out.append(last)
	return out


func _streets() -> void:
	var streets: Array = _plan.streets
	for si in streets.size():
		var st: Dictionary = streets[si]
		var w := float(st.width)
		var line := _resample(st.points, STEP if w < 14.0 else GRID)
		if line.size() < 2: continue
		var lanes: Array = []
		if w >= 14.0:
			var n := maxi(1, floori((w - 2.0) / GRID))
			for j in range(n + 1): lanes.append(-(w * 0.5 - 1.0) + (w - 2.0) * j / n)
		elif st.kind == "main":
			lanes = [-(w * 0.5 - 1.0), w * 0.5 - 1.0]      # the carriageway is the traffic's
		elif w >= 5.0:
			lanes = [-(w * 0.5 - 1.1), 0.0, w * 0.5 - 1.1]
		else:
			lanes = [0.0]
		var ids: Array = []                                   # [row][lane] -> node id or -1
		for i in line.size():
			var tan := (line[mini(i + 1, line.size() - 1)] - line[maxi(i - 1, 0)]).normalized()
			var nrm := Vector2(-tan.y, tan.x)
			var row: Array = []
			for off in lanes:
				var q: Vector2 = line[i] + nrm * float(off)
				row.append(_node(q, si) if clear(q.x, q.y) else -1)
			ids.append(row)
		for i in line.size():
			for j in lanes.size():
				var a: int = ids[i][j]
				if a < 0: continue
				if i + 1 < line.size(): _link(a, ids[i + 1][j])
				if j + 1 < lanes.size() and (st.kind != "main" or i % 6 == 0): _link(a, ids[i][j + 1])
				if w >= 14.0 and i + 1 < line.size():
					if j + 1 < lanes.size(): _link(a, ids[i + 1][j + 1])
					if j > 0: _link(a, ids[i + 1][j - 1])
	# junctions: nodes of different streets close together
	for k: Vector2i in _node_cells:
		for a: int in _node_cells[k]:
			var pa := graph.get_point_position(a)
			for dx in range(-1, 2):
				for dz in range(-1, 2):
					for b: int in _node_cells.get(k + Vector2i(dx, dz), []):
						if b <= a or node_street[a] == node_street[b]: continue
						if pa.distance_to(graph.get_point_position(b)) < LINK: _link(a, b)


## The nearest graph node with a clear straight walk to `p`, or -1.
func attach(p: Vector3, reach: float = 22.0) -> int:
	var best := -1; var best_d := reach
	var r := ceili(reach / CELL)
	var k := Vector2i(floori(p.x / CELL), floori(p.z / CELL))
	var cands: Array = []
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			for nid: int in _node_cells.get(k + Vector2i(dx, dz), []):
				var q := graph.get_point_position(nid)
				var d := Vector2(q.x - p.x, q.z - p.z).length()
				if d < best_d and graph.get_point_connections(nid).size() > 0: cands.append([d, nid])
	cands.sort_custom(func(a, b): return a[0] < b[0])
	for c in cands:
		if segment_clear(p, graph.get_point_position(c[1]), 0.2): return c[1]
	return best


# ---------------------------------------------------------------- spots
func _add_spot(k: String, p: Vector3, f: Vector3, pose: String, extra: Dictionary = {}) -> int:
	p.y = h(p.x, p.z)
	var nid := attach(p)
	if nid < 0: return -1
	var s := {"k": k, "p": p, "f": Vector3(f.x, 0, f.z).normalized(), "pose": pose, "node": nid}
	s.merge(extra)
	spots.append(s)
	var i := spots.size() - 1
	var c := Vector2i(floori(p.x / CELL), floori(p.z / CELL))
	if not _spot_cells.has(c): _spot_cells[c] = []
	_spot_cells[c].append(i)
	return i


func _water_side(p: Vector3) -> Vector3:
	var best := Vector3.ZERO; var best_h := INF
	for i in 12:
		var d := Vector3(sin(i * TAU / 12.0), 0, cos(i * TAU / 12.0))
		var y := 0.0
		for r in [2.5, 4.5, 7.0]:
			var q: Vector3 = p + d * float(r)
			y += h(q.x, q.z)
		if y < best_h: best_h = y; best = d
	return best if best_h < -1.5 else Vector3.ZERO


func _spots() -> void:
	# props first (the order is the plan's: deterministic)
	for rec: Array in _plan.get("props", []):
		var k := String(rec[0])
		var pos := Vector3(float(rec[1]), float(rec[2]), float(rec[3]))
		var yaw := deg_to_rad(float(rec[4]))
		var B := Basis(Vector3.UP, yaw)
		var front := B * Vector3(0, 0, 1)
		match k:
			"stall":
				_add_spot("vend", pos + B * Vector3(0, 0, -1.05), front, "vend")
				for sx in [-0.7, 0.7]:
					_add_spot("browse", pos + B * Vector3(sx, 0, 1.35), -front, "browse")
			"cafe":
				var n := 2 if int(rec[5]) % 2 == 0 else 4
				for c in n:
					var a := TAU * c / n + 0.4
					var d := B * Vector3(sin(a), 0, cos(a))
					_add_spot("seat", pos + d * 0.78, -d, "sit", {"seat": 0.47, "a": pos + d * 0.78 + d.rotated(Vector3.UP, PI * 0.5) * 0.6})
			"bench":
				var seat_h := 0.46 if int(rec[5]) % 2 == 0 else 0.5
				for sx in [-0.45, 0.45]:
					var sp := pos + B * Vector3(sx, 0, -0.02)
					_add_spot("seat", sp, front, "sit", {"seat": seat_h, "a": sp + front * 0.75})
			"net_rack", "lobster_pots":
				for sx in ([-0.7, 0.7] if k == "net_rack" else [0.0]):
					_add_spot("mend", pos + B * Vector3(sx, 0, 0.8), -front, "mend")
			"crates", "crane_port":
				var reach := 1.6 if k == "crates" else 4.0
				var sp := pos + front * reach
				var other := Vector3.INF
				for turn in [0.0, 0.8, -0.8, 1.6, -1.6, PI]:
					var q := sp + front.rotated(Vector3.UP, turn) * 11.0
					q.y = h(q.x, q.z)
					if q.y > 0.4 and clear(q.x, q.z) and segment_clear(sp, q):
						other = q; break
				if other != Vector3.INF:
					_add_spot("dock", sp, -front, "carry", {"b": other, "ys": _heights(sp, other)})
			"quay_bollard":
				var water := _water_side(pos)
				if water != Vector3.ZERO:
					var side := water.cross(Vector3.UP)
					_add_spot("fish", pos - water * 0.9 + side * 0.8, water, "fish")
			"garden":
				for g in [Vector3(-1.6, 0, -2.4), Vector3(1.6, 0, 2.2)]:
					_add_spot("field", pos + B * g, (B * Vector3(0, 0, 1)).rotated(Vector3.UP, g.x), "hoe")
			"cart":
				_add_spot("yard", pos + B * Vector3(1.4, 0, 0.3), -(B * Vector3(1, 0, 0)), "work")
			"well", "fountain_grand", "fountain_basin", "fountain_moorish", "fountain_trough":
				var fp := ArchProps.footprint(k)
				var r := maxf(fp.x, fp.z) + 0.75
				for c in (5 if r > 3.0 else 3):
					var a := yaw + TAU * c / (5.0 if r > 3.0 else 3.0) + 0.3
					var d := Vector3(sin(a), 0, cos(a))
					_add_spot("chat", pos + d * r, (-d).rotated(Vector3.UP, 0.5), "chat")
	# plots: doors, shop doors, barns, boathouses, the souk
	for p: Dictionary in _plan.plots:
		var yaw := deg_to_rad(float(p.yaw))
		var f := Vector3(sin(yaw), 0, cos(yaw)); var t := Vector3(f.z, 0, -f.x)
		var c := Vector3(float(p.x), float(p.y), float(p.z))
		var hd := float(p.d) * 0.5; var hw := float(p.w) * 0.5
		var kind_: String = p.kind
		if kind_ in RESIDENTIAL:
			var door := _add_spot("door", c + f * (hd + 0.7), f, "stand")
			if door >= 0: homes.append(door)
		if kind_ == "shop" or "shopfront" in p.get("tags", []):
			_add_spot("shop", c + f * (hd + 1.0) + t * (hw * 0.45), f, "shopkeep")
			# window shopping in front of the shop
			_add_spot("window", c + f * (hd + 1.5) - t * (hw * 0.3), -f, "browse")
		if kind_ in ["barn", "granary", "windmill"]:
			_add_spot("barn", c + f * (hd + 1.4) + t * (hw * 0.3), -f, "work")
		if kind_ in ["boathouse", "warehouse"]:
			var sp := c + f * (hd + 1.5)
			var q := sp + t * 10.0
			if clear(q.x, q.z) and segment_clear(sp, q):
				q.y = h(q.x, q.z)
				_add_spot("dock", sp, t, "carry", {"b": q, "ys": _heights(sp, q)})
		if kind_ == "market_hall":
			for j in 4:
				_add_spot("vend", c + f * (hd + 1.2) + t * (-hw * 0.6 + hw * 0.4 * j), f, "vend")
	# chat clusters on plazas, quays and the main street's sidewalks: pairs facing each other
	for st: Dictionary in _plan.streets:
		if not st.kind in ["plaza", "quay", "main"]: continue
		var w := float(st.width)
		var line := _resample(st.points, 9.0 if st.kind == "plaza" else (23.0 if st.kind == "quay" else 26.0))
		if st.kind == "main":
			for i in line.size():
				var tan := (line[mini(i + 1, line.size() - 1)] - line[maxi(i - 1, 0)]).normalized()
				var nrm := Vector2(-tan.y, tan.x) * (1.0 if i % 2 == 0 else -1.0)
				var q2: Vector2 = line[i] + nrm * (w * 0.5 - 1.1)
				var d := Vector3(tan.x, 0, tan.y)
				var q := Vector3(q2.x, 0, q2.y)
				if clear(q.x - d.x * 0.6, q.z - d.z * 0.6, 0.4) and clear(q.x + d.x * 0.6, q.z + d.z * 0.6, 0.4):
					_add_spot("chat", q - d * 0.55, d, "chat")
					_add_spot("chat", q + d * 0.55, -d, "chat")
			continue
		for i in line.size():
			var tan := (line[mini(i + 1, line.size() - 1)] - line[maxi(i - 1, 0)]).normalized()
			var nrm := Vector2(-tan.y, tan.x)
			var offs: Array = [0.0] if w < 14.0 else [-(w * 0.25), w * 0.25]
			for o in offs:
				var q2: Vector2 = line[i] + nrm * float(o)
				var q := Vector3(q2.x, 0, q2.y)
				var a := float(hash([id, i, o]) % 628) / 100.0
				var d := Vector3(sin(a), 0, cos(a))
				if clear(q.x - d.x * 0.6, q.z - d.z * 0.6, 0.6) and clear(q.x + d.x * 0.6, q.z + d.z * 0.6, 0.6):
					_add_spot("chat", q - d * 0.6, d, "chat")
					_add_spot("chat", q + d * 0.6, -d, "chat")


## Ground heights at 16 steps along a straight carry (a dockworker's loop).
func _heights(a: Vector3, b: Vector3) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in 17:
		var q := a.lerp(b, i / 16.0)
		out.append(h(q.x, q.z))
	return out


## Spots of `kinds` within `reach` of `p`, nearest first.
func spots_near(p: Vector3, kinds: Array, reach: float) -> Array:
	var out: Array = []
	var r := ceili(reach / CELL)
	var k := Vector2i(floori(p.x / CELL), floori(p.z / CELL))
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			for i: int in _spot_cells.get(k + Vector2i(dx, dz), []):
				if not spots[i].k in kinds: continue
				var d := Vector2(spots[i].p.x - p.x, spots[i].p.z - p.z).length()
				if d < reach: out.append([d, i])
	out.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	var ids: Array = []
	for e in out: ids.append(e[1])
	return ids


# ---------------------------------------------------------------- people
static func _work_job(spot_kind: String, st: StringName, rng: RandomNumberGenerator) -> String:
	match spot_kind:
		"vend": return "vendor" if rng.randf() < 0.7 else "merchant"
		"shop": return "baker" if st == &"campo" and rng.randf() < 0.25 else "merchant"
		"mend", "fish": return "fisher"
		"dock": return "porter" if st == &"sarmada" and rng.randf() < 0.5 else "dockworker"
		"field": return "gardener" if st in [&"isola", &"puerto", &"sarmada"] else "farmer"
		"barn": return ("shepherd" if rng.randf() < 0.5 else "woodcutter") if st == &"valdoro" else "farmer"
		"yard": return "farmer" if st != &"sarmada" else "porter"
	return ""


func _pick(rng: RandomNumberGenerator, weights: Dictionary) -> String:
	var total := 0.0
	for k in weights: total += float(weights[k])
	var r := rng.randf() * total
	for k in weights:
		r -= float(weights[k])
		if r <= 0.0: return k
	return weights.keys()[0]


func _people() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(["townfolk", id])
	var n := population_for(_plan)
	if homes.is_empty():
		var door := _add_spot("door", centre + Vector3(3, 0, 3), Vector3.FORWARD, "stand")
		if door >= 0: homes.append(door)
		if homes.is_empty(): return
	# the work spots, shuffled deterministically; about 55 % of the town has one
	var work_spots: Array = []
	for i in spots.size():
		if spots[i].k in ["vend", "shop", "mend", "fish", "dock", "field", "barn", "yard"]: work_spots.append(i)
	for i in range(work_spots.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var tmp = work_spots[i]; work_spots[i] = work_spots[j]; work_spots[j] = tmp
	# the trades the place is known for first (stalls, quays, nets, fields, barns), then shops,
	# at most a fifth of the town keeping one
	var first: Array = []; var shops: Array = []
	for i in work_spots:
		if spots[i].k == "shop": shops.append(i)
		else: first.append(i)
	work_spots = first + shops.slice(0, maxi(2, roundi(n * 0.2)))
	var workers := mini(work_spots.size(), roundi(n * 0.58))
	var home_load := {}
	for i in n:
		var person := Townsperson.new()
		person.index = i
		person.id = "townsperson.%s.%d" % [id, i]
		person.seed = hash([id, i, 7121])
		person.sex = "f" if rng.randf() < 0.5 else "m"
		person.speed = rng.randf_range(1.12, 1.45)
		person.lane = rng.randf_range(-0.45, 0.45)
		var anchor := centre
		if i < workers:
			person.work = work_spots[i]
			person.occupation = _work_job(spots[person.work].k, style, rng)
			anchor = spots[person.work].p
		else:
			person.occupation = _pick(rng, IDLE_JOBS.get(style, {"": 1}))
			anchor = spots[homes[rng.randi() % homes.size()]].p
		# a home near the anchor, at most four to a door
		var near_homes: Array = []
		for hi: int in homes:
			if int(home_load.get(hi, 0)) >= 4: continue
			near_homes.append([spots[hi].p.distance_squared_to(anchor), hi])
		if near_homes.is_empty(): person.home = homes[rng.randi() % homes.size()]
		else:
			near_homes.sort_custom(func(a, b): return a[0] < b[0])
			person.home = near_homes[mini(rng.randi() % 3, near_homes.size() - 1)][1]
		home_load[person.home] = int(home_load.get(person.home, 0)) + 1
		_routine(person, rng)
		person.look(style)          # decided here, on the worker thread, not when he comes into view
		counts[person.occupation if person.occupation != "" else "townsfolk"] = int(counts.get(person.occupation if person.occupation != "" else "townsfolk", 0)) + 1
		people.append(person)


## A leisure spot near `p`: a seat or a chat spot (or a stall to browse when `shopping`). A third
## of the time the plaza instead: the market and the benches are where a town meets.
func _leisure(p: Vector3, rng: RandomNumberGenerator, shopping := false) -> int:
	if rng.randf() < 0.33: p = centre
	var kinds := ["browse", "window"] if shopping else (["seat", "chat"] if rng.randf() < 0.75 else ["chat"])
	var near := spots_near(p, kinds, NEAR_REACH)
	if near.is_empty(): near = spots_near(p, ["seat", "chat", "browse", "window"], NEAR_REACH * 2.0)
	if near.is_empty(): return -1
	return near[mini(rng.randi() % 6, near.size() - 1)]


func _routine(person: Townsperson, rng: RandomNumberGenerator) -> void:
	var r: Array = [[0.0, person.home, "home"]]
	var home_p: Vector3 = spots[person.home].p
	if person.work >= 0:
		var work_p: Vector3 = spots[person.work].p
		var wake := rng.randf_range(390.0, 500.0)
		var lunch := rng.randf_range(700.0, 790.0)
		var back := lunch + rng.randf_range(45.0, 80.0)
		var off := rng.randf_range(1040.0, 1150.0)
		r.append([wake, person.work, "work"])
		if rng.randf() < 0.18: r.append([lunch, person.home, "home"])
		else: r.append([lunch, _leisure(work_p, rng), "rest"])
		r.append([back, person.work, "work"])
		# an errand in the afternoon for a third of them
		if rng.randf() < 0.33:
			var errand := back + rng.randf_range(90.0, 180.0)
			r.append([errand, _leisure(work_p, rng, true), "shop"])
			r.append([errand + rng.randf_range(15.0, 30.0), person.work, "work"])
		r.append([off, _leisure(home_p.lerp(work_p, 0.5), rng), "rest"])
		r.append([off + rng.randf_range(40.0, 80.0), _leisure(home_p, rng), "rest"])
		r.append([rng.randf_range(1230.0, 1330.0), person.home, "home"])
	else:
		var t := rng.randf_range(440.0, 600.0)
		while t < 1260.0:
			var roll := rng.randf()
			if roll < 0.4: r.append([t, _leisure(home_p, rng, true), "shop"])
			elif roll < 0.88: r.append([t, _leisure(home_p, rng), "rest"])
			else: r.append([t, person.home, "home"])
			t += rng.randf_range(30.0, 90.0)
		r.append([rng.randf_range(1260.0, 1340.0), person.home, "home"])
	# no leisure spot found -> stay home
	for e in r:
		if int(e[1]) < 0: e[1] = person.home; e[2] = "home"
	r.sort_custom(func(a, b): return a[0] < b[0])
	person.routine = r


# ---------------------------------------------------------------- routes
## Routes are computed off the main thread: TownFolk asks with `route_ready(a, b)` (the cached
## walk, or null), `queue_route(a, b)`, and `pump()` once a frame starts a batch task for the
## queue. One task at a time per town, so the graph is only ever searched by one thread.
var _mutex := Mutex.new()
var _queue: Array = []
var _task := -1


func route_ready(a: int, b: int) -> Variant:
	var key := "%d>%d" % [a, b]
	_mutex.lock()
	var got: Variant = _paths.get(key)
	_mutex.unlock()
	return got


func queue_route(a: int, b: int) -> void:
	var pair := Vector2i(a, b)
	if not pair in _queue: _queue.append(pair)


func pump() -> void:
	if _task >= 0:
		if not WorkerThreadPool.is_task_completed(_task): return
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	if _queue.is_empty(): return
	var batch := _queue.duplicate()
	_queue.clear()
	_task = WorkerThreadPool.add_task(_route_batch.bind(batch), false, "town routes")


func busy() -> bool:
	return _task >= 0 or not _queue.is_empty()


func wait() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


func _route_batch(batch: Array) -> void:
	for pair: Vector2i in batch:
		var key := "%d>%d" % [pair.x, pair.y]
		_mutex.lock()
		var have := _paths.has(key)
		_mutex.unlock()
		if have: continue
		var path := route(pair.x, pair.y)
		_mutex.lock()
		if _paths.size() > 4000: _paths.clear()
		_paths[key] = path
		_mutex.unlock()


## The walk from spot `a` to spot `b` along the streets (graph nodes), ends included; heights
## from the ground. Empty when the two are not connected. (Worker thread; see route_ready.)
func route(a: int, b: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	var sa: Dictionary = spots[a]; var sb: Dictionary = spots[b]
	var start: Vector3 = sa.p
	var goal: Vector3 = sb.get("a", sb.p)
	var ids := graph.get_id_path(int(sa.node), int(sb.node))
	if ids.is_empty() and int(sa.node) != int(sb.node): return out
	out.append(start)
	for nid in ids: out.append(graph.get_point_position(nid))
	out.append(goal)
	return _smooth(out)


## Drop needless zig-zags (a later point in clear sight), then densify to <= 2.5 m with ground
## heights, so a walker follows the ground without per-frame queries.
func _smooth(pts: PackedVector3Array) -> PackedVector3Array:
	var keep := PackedVector3Array([pts[0]])
	var i := 0
	while i < pts.size() - 1:
		var j := mini(i + 4, pts.size() - 1)
		while j > i + 1 and not segment_clear(pts[i], pts[j], 0.3): j -= 1
		keep.append(pts[j]); i = j
	var out := PackedVector3Array()
	for k in keep.size():
		if k == 0: out.append(keep[0]); continue
		var a := keep[k - 1]; var b := keep[k]
		var n := maxi(1, ceili(Vector2(b.x - a.x, b.z - a.z).length() / 2.5))
		for s in range(1, n + 1):
			var q := a.lerp(b, float(s) / n)
			q.y = h(q.x, q.z)
			out.append(q)
	return out


func node_count() -> int:
	return graph.get_point_count()
