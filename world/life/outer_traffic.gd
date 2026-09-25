class_name OuterTraffic
extends Node3D
## Traffic on the outer roads, only round the viewer: cars, lorries and buses on the highways,
## cars, lorries, tractors and donkey carts on the country roads and tracks. A vehicle is spawned
## on a road SPAWN_MIN..SPAWN_MAX from the viewer (never in plain sight close by), is given a
## town or hamlet to drive to and follows a RoadNavigation route there in its lane (right-hand
## traffic, lane offset per road class), at its road's speed limit, slowing for bends, keeping
## its distance to the vehicle ahead, yielding at junctions (the first to reach the conflict area
## goes; ties by id) and stopping for the courier. Beyond DESPAWN it is gone: far away the
## roads are abstract. Vehicles are kinematic bodies on layer 16 (the courier's vehicles and body
## collide with them as they do with the island's drivers).
##
## Interface: setup(world, entities, life); vehicles (records); count(); wait(); stats.

const SPAWN_MIN := 300.0
const SPAWN_MAX := 600.0
const DESPAWN := 900.0
const MAX_VEHICLES := 24
## per road class: speed limit (m/s), lane offset from the centre line, vehicles per km (both ways)
const LIMITS := {"highway": 22.0, "road": 15.0, "track": 9.0, "street": 7.5, "core": 9.0}
const LANES := {"highway": 2.7, "road": 1.75, "track": 1.15, "street": 1.9, "core": 1.05}
const DENSITY := {"highway": 6.0, "road": 3.0, "track": 1.0, "street": 1.5, "core": 0.0}
## closer than SPAWN_MIN only out of sight: behind the camera
const SPAWN_BEHIND := 150.0
## kind -> [length, width, height, top speed, weight by class {highway, road, track}]
const KINDS := {
	"car": [4.2, 1.7, 1.5, 24.0, {"highway": 6, "road": 6, "track": 3, "street": 6}],
	"lorry": [5.6, 2.1, 2.5, 19.0, {"highway": 3, "road": 2, "track": 0, "street": 1}],
	"bus": [9.0, 2.5, 3.1, 20.0, {"highway": 1.3, "road": 0.6, "track": 0, "street": 0.3}],
	"tractor": [3.6, 1.9, 2.4, 8.5, {"highway": 0, "road": 0.9, "track": 2, "street": 0.4}],
	"cart": [3.9, 1.4, 1.9, 4.2, {"highway": 0, "road": 0.4, "track": 2.2, "street": 0.4}],
}
const CAR_COLORS := [Color("8fb8b0"), Color("c9563f"), Color("e8d9b8"), Color("3f5a7a"), Color("d9a441"), Color("5d7a44"), Color("f2efe6"), Color("7a2e35"), Color("2f2f33")]
const ACCEL := 2.4
const BRAKE := 5.5

var world: WorldManager
var entities: EntityManager
var life: IslandLife
var nav: RoadNavigation
var terrain: Terrain
var road_cls: Dictionary = {}           # terrain road index -> class
var dests: Array = []                   # [id, Vector3, style]
var vehicles: Array = []                # records
var spawned := 0
var despawned := 0
var paths_ms := 0.0
var frame_us := 0
var physics_us := 0
var _cells: Dictionary = {}             # Vector2i (100 m) -> [nav node ids] (outer roads only)
var _pool: Dictionary = {}              # kind -> [views]
const POOL_KEEP := 2                    # parked views kept per kind (m-4)
var _clock := 0.0                       # game seconds (the pool's idle timer)
const POOL_IDLE_S := 30.0               # a parked view unused this long is freed (m-4: none left once the roads are quiet)
var _rng := RandomNumberGenerator.new()
var _spawn_t := 0.0
var _target_t := 0.0
var _target := 0
var _gap_t := 0.0
var _next_id := 0
var _viewer := Vector3.ZERO

const CELL := 100.0


func setup(p_world: WorldManager, p_entities: EntityManager, p_life: IslandLife) -> void:
	world = p_world; entities = p_entities; life = p_life
	name = "OuterTraffic"
	nav = life.navigation
	terrain = world.terrain
	_rng.seed = 60613
	var outer: OuterWorld = world.outer
	for e: Dictionary in outer.roads.roads:
		if int(e.nav) >= 0: road_cls[int(e.nav)] = String(e.cls)
	for id in nav.road_ids:
		var ri: int = nav.road_ids[id]
		if not road_cls.has(ri): continue
		var p := nav.graph.get_point_position(id)
		var k := Vector2i(floori(p.x / CELL), floori(p.z / CELL))
		if not _cells.has(k): _cells[k] = []
		_cells[k].append(id)
	# destinations: each town's and hamlet's gate (where its main street leaves the country road),
	# so through traffic keeps out of the streets and plazas the townsfolk walk
	for group in ["towns", "hamlets"]:
		for t: Dictionary in outer.plan().get(group, []):
			var gate: Vector3 = world.database.location_pos(StringName(t.id))
			for st: Dictionary in t.streets:
				if st.kind != "main" or (st.points as Array).size() < 2: continue
				var a: Array = st.points[0]; var b: Array = st.points[(st.points as Array).size() - 1]
				var pa := Vector3(a[0], a[1], a[2]); var pb := Vector3(b[0], b[1], b[2])
				gate = pa if pa.distance_to(gate) > pb.distance_to(gate) else pb
			dests.append([String(t.id), gate, StringName(t.style)])


func road_count() -> int:
	var seen := {}
	for ri in road_cls: seen[ri] = true
	return seen.size()


func count() -> int:
	return vehicles.size()


func wait() -> void:
	pass


func class_of(node_id: int) -> String:
	return road_cls.get(nav.road_ids.get(node_id, -1), "core")


# ---------------------------------------------------------------- spawning
func _viewer_pos() -> Vector3:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if entities.focus and cam and cam.global_position.distance_to(entities.focus.global_position) > 400.0:
		return cam.global_position                     # a camera tool far from the courier
	if entities.focus: return entities.focus.global_position
	return cam.global_position if cam else Vector3.ZERO


## Road nodes (outer) within [r0, r1] of `p`, with their class.
func nodes_near(p: Vector3, r0: float, r1: float) -> Array:
	var out: Array = []
	var r := ceili(r1 / CELL)
	var k := Vector2i(floori(p.x / CELL), floori(p.z / CELL))
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			for id: int in _cells.get(k + Vector2i(dx, dz), []):
				var d := Vector2(nav.graph.get_point_position(id).x - p.x, nav.graph.get_point_position(id).z - p.z).length()
				if d >= r0 and d <= r1: out.append(id)
	return out


## How many vehicles the roads round `p` should carry.
func target_count(p: Vector3) -> int:
	var km := 0.0
	var per := 0.0
	for id in nodes_near(p, 0.0, SPAWN_MAX):
		var cls := class_of(id)
		per += float(DENSITY.get(cls, 0.0)) * 0.012
		km += 0.012
	return mini(MAX_VEHICLES, roundi(per))


func _process(delta: float) -> void:
	if world == null or _cells.is_empty(): return
	var t0 := Time.get_ticks_usec()
	_clock += delta
	_viewer = _viewer_pos()
	_spawn_t -= delta
	_target_t -= delta
	if _target_t <= 0.0:
		_target_t = 2.0
		_target = target_count(_viewer)
	if _spawn_t <= 0.0:
		_spawn_t = 0.35
		_despawn_far()
		_trim_pool()
		if vehicles.size() < _target: spawn_one()
	frame_us = Time.get_ticks_usec() - t0


func _despawn_far() -> void:
	for v in vehicles.duplicate():
		var d := (v.pos as Vector3).distance_to(_viewer)
		if d > DESPAWN or (v.done and v.wait > 20.0 and d > 250.0):
			_remove(v)
		elif v.done and v.wait > 6.0:
			# parked at a dead end: off again somewhere else
			v.wait = 0.0
			var di := _rng.randi() % dests.size()
			if _route(v, nav.nearest(v.pos), dests[di][1]): v.dest = di


## Spawn a vehicle on a road near the viewer; returns the record or {}.
func spawn_one(at_node: int = -1, kind := "", dest_index := -1) -> Dictionary:
	var node := at_node
	if node < 0:
		var cands := nodes_near(_viewer, SPAWN_BEHIND, SPAWN_MAX)
		if cands.is_empty(): return {}
		var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
		var look_dir := -cam.global_basis.z if cam else Vector3.ZERO
		for attempt in 8:
			var c: int = cands[_rng.randi() % cands.size()]
			var q := nav.graph.get_point_position(c)
			var off := q - _viewer
			if off.length() < SPAWN_MIN and (look_dir == Vector3.ZERO or off.normalized().dot(look_dir) > -0.25): continue
			if _free_at(q, 25.0): node = c; break
		if node < 0: return {}
	var cls := class_of(node)
	if kind == "":
		var weights := {}
		for k in KINDS: weights[k] = float(KINDS[k][4].get(cls, 0.0))
		kind = _pick(weights)
	var at := nav.graph.get_point_position(node)
	var di := dest_index
	if di < 0:
		for attempt in 8:
			di = _rng.randi() % dests.size()
			if (dests[di][1] as Vector3).distance_to(at) > 400.0: break
	var rec := {"id": "traffic.%d" % _next_id, "kind": kind, "dest": di, "s": 0.0, "v": 0.0, "limit": 0.0, "done": false, "wait": 0.0,
		"pos": at, "fwd": Vector3.FORWARD, "view": null, "top": float(KINDS[kind][3]), "len": float(KINDS[kind][0]), "hold": 0.0}
	_next_id += 1
	if not _route(rec, node, dests[di][1]): return {}
	rec.v = minf(float(rec.top), _limit_at(rec, 0.0)) * 0.8
	_place(rec)
	vehicles.append(rec)
	spawned += 1
	_attach_view(rec, dests[di][2])
	return rec


func _pick(weights: Dictionary) -> String:
	var total := 0.0
	for k in weights: total += float(weights[k])
	var r := _rng.randf() * total
	for k in weights:
		r -= float(weights[k])
		if r <= 0.0: return k
	return "car"


func _free_at(p: Vector3, reach: float) -> bool:
	for v in vehicles:
		if (v.pos as Vector3).distance_to(p) < reach: return false
	return true


## The lane-offset route from a graph node to the destination: points, cumulative lengths,
## per-point speed limits (road class), heights on the ground or a bridge deck.
func _route(rec: Dictionary, from_node: int, to: Vector3) -> bool:
	var t0 := Time.get_ticks_usec()
	var ids := nav.graph.get_id_path(from_node, nav.nearest(to))
	if ids.size() < 3:
		paths_ms += float(Time.get_ticks_usec() - t0) / 1000.0
		return false
	rec.ids = ids; rec.next = 0
	rec.path = PackedVector3Array(); rec.cum = PackedFloat32Array(); rec.lim = PackedFloat32Array()
	rec.s = 0.0; rec.done = false; rec.wait = 0.0
	_extend(rec)
	paths_ms += float(Time.get_ticks_usec() - t0) / 1000.0
	return (rec.path as PackedVector3Array).size() >= 3


## Lay the lane BUILD_AHEAD further along the route (a route may be 20 km; a vehicle lives for
## the kilometre or two near the viewer). Heights are the road's own samples (decks included).
const BUILD_AHEAD := 1200.0

func _extend(rec: Dictionary) -> void:
	var ids: PackedInt64Array = rec.ids
	var pts: PackedVector3Array = rec.path
	var cum: PackedFloat32Array = rec.cum
	var lim: PackedFloat32Array = rec.lim
	var i: int = rec.next
	var first := pts.size()
	var total := cum[cum.size() - 1] if cum.size() > 0 else 0.0
	while i < ids.size() and total < float(rec.s) + BUILD_AHEAD:
		var c := nav.graph.get_point_position(ids[i])
		var tan := nav.graph.get_point_position(ids[mini(i + 1, ids.size() - 1)]) - nav.graph.get_point_position(ids[maxi(i - 1, 0)])
		tan.y = 0.0
		i += 1
		if tan.length_squared() < 0.01: continue
		var cls := class_of(ids[i - 1])
		var q := c + tan.normalized().cross(Vector3.UP) * float(LANES.get(cls, 1.2))
		if not pts.is_empty():
			var step := Vector2(q.x - pts[pts.size() - 1].x, q.z - pts[pts.size() - 1].z).length()
			if step < 0.5: continue
			total += step
		pts.append(q); cum.append(total); lim.append(float(LIMITS.get(cls, 9.0)))
	rec.next = i
	# bends: the speed a car can hold through the turn at each point
	for k in range(maxi(1, first - 1), pts.size() - 1):
		var a := pts[k] - pts[k - 1]; var b := pts[k + 1] - pts[k]
		a.y = 0; b.y = 0
		var turn := a.normalized().angle_to(b.normalized())
		var span := (a.length() + b.length()) * 0.5
		if turn > 0.02: lim[k] = minf(lim[k], sqrt(3.2 * span / turn))
	rec.path = pts; rec.cum = cum; rec.lim = lim


func _complete(rec: Dictionary) -> bool:
	return int(rec.get("next", 0)) >= (rec.get("ids", PackedInt64Array()) as PackedInt64Array).size()


func _limit_at(rec: Dictionary, s: float) -> float:
	var cum: PackedFloat32Array = rec.cum
	var lim: PackedFloat32Array = rec.lim
	var i := cum.bsearch(s)
	var best := 99.0
	# the lowest limit in the next ~50 m, eased by the braking distance to it
	var j := clampi(i - 1, 0, cum.size() - 1)
	while j < cum.size() and cum[j] < s + 55.0:
		var ahead := maxf(0.0, cum[j] - s)
		best = minf(best, sqrt(lim[j] * lim[j] + 2.0 * BRAKE * 0.6 * ahead))
		j += 1
	return minf(best, float(rec.top))


func _sample(rec: Dictionary, s: float) -> Array:
	var pts: PackedVector3Array = rec.path
	var cum: PackedFloat32Array = rec.cum
	var n := pts.size()
	if s >= cum[n - 1]: return [pts[n - 1], (pts[n - 1] - pts[n - 2]).normalized()]
	var i := maxi(cum.bsearch(s, true) - 1, 0)
	i = mini(i, n - 2)
	var f := (s - cum[i]) / maxf(cum[i + 1] - cum[i], 0.001)
	var p := pts[i].lerp(pts[i + 1], f)
	# heading eased across the corner so a vehicle turns instead of snapping
	var d0 := (pts[i + 1] - pts[i]); d0.y = 0
	var d1 := (pts[mini(i + 2, n - 1)] - pts[i + 1]); d1.y = 0
	var dir := d0.normalized().slerp(d1.normalized() if d1.length() > 0.01 else d0.normalized(), smoothstep(0.55, 1.0, f) * 0.5)
	return [p, dir]


func _place(rec: Dictionary) -> void:
	var smp := _sample(rec, float(rec.s))
	rec.pos = smp[0]
	var f: Vector3 = smp[1]
	if f.length_squared() > 0.001: rec.fwd = f.normalized()


# ---------------------------------------------------------------- driving
func _physics_process(delta: float) -> void:
	if vehicles.is_empty(): return
	var t0 := Time.get_ticks_usec()
	_gap_t -= delta
	if _gap_t <= 0.0:
		_gap_t = 0.1
		for v in vehicles: v.limit = _gap_limit(v)
	for v in vehicles:
		if v.done:
			v.wait += delta
			v.v = move_toward(float(v.v), 0.0, BRAKE * delta)
			continue
		var end := float((v.cum as PackedFloat32Array)[(v.cum as PackedFloat32Array).size() - 1])
		if end - float(v.s) < 400.0 and not _complete(v):
			_extend(v)
			end = float((v.cum as PackedFloat32Array)[(v.cum as PackedFloat32Array).size() - 1])
		var want := minf(_limit_at(v, float(v.s)), float(v.limit))
		if _complete(v): want = minf(want, sqrt(maxf(0.0, 2.0 * BRAKE * 0.5 * (end - float(v.s)))))
		# harder braking when something turns up close (up to ~1 g)
		var brake := BRAKE if float(v.v) < want + 3.0 else BRAKE * 1.8
		v.v = move_toward(float(v.v), want, (ACCEL if want > float(v.v) else brake) * delta)
		v.s = float(v.s) + float(v.v) * delta
		if float(v.s) >= end - 0.5 and _complete(v):
			v.s = end; v.done = true; v.wait = 0.0
			# a new destination from here (the town it reached is behind it)
			var here: Vector3 = v.pos
			for attempt in 4:
				var di := _rng.randi() % dests.size()
				if (dests[di][1] as Vector3).distance_to(here) > 400.0 and _route(v, nav.nearest(here), dests[di][1]):
					v.dest = di
					break
		_place(v)
		_move_view(v, delta)
	physics_us = Time.get_ticks_usec() - t0


## The speed allowed by what is ahead: a vehicle in the same lane, a crossing at a junction, the
## courier (on foot, on the bike, in the truck).
func _gap_limit(v: Dictionary) -> float:
	var pos: Vector3 = v.pos; var fwd: Vector3 = v.fwd
	var limit := 99.0
	var reach := 12.0 + float(v.v) * float(v.v) / (2.0 * BRAKE) + 20.0
	for o in vehicles:
		if o == v: continue
		var off: Vector3 = (o.pos as Vector3) - pos
		if absf(off.y) > 3.0: continue
		var ahead := off.dot(fwd)
		if ahead <= 0.0 or ahead > reach + 30.0: continue
		var side := absf(off.cross(fwd).y)
		var ofwd: Vector3 = o.fwd
		var gap := ahead - (float(v.len) + float(o.len)) * 0.5 - 3.0
		if side < 1.7 and fwd.dot(ofwd) > 0.2:
			# follow: never closer than the gap, matching its speed
			limit = minf(limit, maxf(0.0, sqrt(maxf(0.0, 2.0 * BRAKE * 0.7 * gap)) + minf(float(o.v), 0.0)))
			if gap < 2.0: limit = 0.0
		elif absf(fwd.dot(ofwd)) < 0.7 and ahead < 30.0 and side < 30.0:
			var stop := _junction_stop(v, o)
			if stop < INF: limit = minf(limit, sqrt(maxf(0.0, 2.0 * BRAKE * 0.7 * stop)))
	for body in _couriers():
		var off: Vector3 = body.global_position - pos
		var ahead := off.dot(fwd)
		if ahead > 0.0 and ahead < reach and absf(off.cross(fwd).y) < 2.2 and absf(off.y) < 3.0:
			limit = minf(limit, sqrt(maxf(0.0, 2.0 * BRAKE * (ahead - float(v.len) * 0.5 - 3.5))))
	return limit


## Two crossing trajectories: the one further from the conflict area waits (ties by id).
func _junction_stop(v: Dictionary, o: Dictionary) -> float:
	var u := Vector2((v.fwd as Vector3).x, (v.fwd as Vector3).z)
	var w := Vector2((o.fwd as Vector3).x, (o.fwd as Vector3).z)
	var den := u.cross(w)
	if absf(den) < 0.1: return INF
	var off := Vector2((o.pos as Vector3).x - (v.pos as Vector3).x, (o.pos as Vector3).z - (v.pos as Vector3).z)
	var d_me := off.cross(w) / den
	var d_o := off.cross(u) / den
	if d_me < -4.0 or d_o < -4.0 or d_me > 26.0 or d_o > 26.0: return INF
	var mine := String(v.id) < String(o.id)
	if d_me < 5.0 and d_o >= 5.0: mine = true
	elif d_o < 5.0 and d_me >= 5.0: mine = false
	elif absf(d_me - d_o) > 4.0: mine = d_me < d_o
	if mine: return INF
	return maxf(0.0, d_me - 6.0)


func _couriers() -> Array:
	var out: Array = []
	var g := Game.current
	if g == null: return out
	for n in [g.bike, g.jeep, g.cart, g.player]:
		if n != null and is_instance_valid(n) and n.is_inside_tree(): out.append(n)
	return out


func _remove(v: Dictionary) -> void:
	vehicles.erase(v)
	despawned += 1
	var view: Node3D = v.view
	if view:
		view.visible = false
		(view.get_meta("body") as AnimatableBody3D).collision_layer = 0
		if not _pool.has(v.kind): _pool[v.kind] = []
		# m-4: a small reserve per kind is kept for reuse; the rest are freed, so the views made
		# for a busy highway do not stay in the tree for the rest of the session
		if (_pool[v.kind] as Array).size() >= POOL_KEEP: view.queue_free()
		else:
			view.set_meta("parked_at", _clock)
			_pool[v.kind].append(view)


## Parked views nobody took for POOL_IDLE_S are freed, one per call (the spawn tick).
func _trim_pool() -> void:
	for k in _pool:
		var list: Array = _pool[k]
		if not list.is_empty() and _clock - float((list[0] as Node).get_meta("parked_at", _clock)) > POOL_IDLE_S:
			(list.pop_front() as Node).queue_free()
			return


# ---------------------------------------------------------------- views
func _attach_view(v: Dictionary, style: StringName) -> void:
	var list: Array = _pool.get(v.kind, [])
	var view: Node3D = list.pop_back() if not list.is_empty() else TrafficModels.build(v.kind)
	if view.get_parent() == null: add_child(view)
	view.visible = true
	TrafficModels.paint(view, v.kind, CAR_COLORS[_rng.randi() % CAR_COLORS.size()])
	TrafficModels.set_driver(view, v.kind, hash([v.id, "driver"]), style)
	(view.get_meta("body") as AnimatableBody3D).collision_layer = 16
	v.view = view
	view.global_position = v.pos
	view.rotation.y = atan2(-(v.fwd as Vector3).x, -(v.fwd as Vector3).z)
	view.set_meta("roll", 0.0)


func _move_view(v: Dictionary, delta: float) -> void:
	var view: Node3D = v.view
	if view == null: return
	var fwd: Vector3 = v.fwd
	var yaw := atan2(-fwd.x, -fwd.z)
	var pts: PackedVector3Array = v.path
	var ahead := _sample(v, float(v.s) + float(v.len) * 0.5)[0] as Vector3
	var behind := _sample(v, maxf(0.0, float(v.s) - float(v.len) * 0.5))[0] as Vector3
	var pitch := atan2(ahead.y - behind.y, maxf(Vector2(ahead.x - behind.x, ahead.z - behind.z).length(), 0.5))
	view.global_transform = Transform3D(Basis.from_euler(Vector3(pitch, yaw, 0.0), EULER_ORDER_YXZ), v.pos)
	TrafficModels.animate(view, v.kind, float(v.v), delta, pts.size())
