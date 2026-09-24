class_name OuterBoats
extends Node3D
## Fishing boats off the outer ports: each harbour (Puerto Alto, Sarmada, Isola Serena, and a
## coastal hamlet with water close by) keeps a few boats that lie at their moorings off the quay,
## sail out to a fishing ground, work it (slow circles, a fisher at the stern), and come home.
## A boat's position is a pure function of the clock (like IslandWildlife's sailing launches), so
## nothing ticks far away; routes are string-pulled A* over a local 20 m water grid (a cell is
## water when the ground under it is below WATER_Y at its centre and corners), built on a worker
## thread when the viewer comes within PREPARE of the harbour, and every point of a route is
## checked below -2 m before a boat may use it. Views (fishing_boat.glb) only within VIEW_RADIUS.

const PREPARE := 3200.0
const VIEW_RADIUS := 1600.0
const FISHER_RADIUS := 220.0
const GRID := 15.0
const HALF := 1500.0                # the local water grid: 3 km square round the harbour
const WATER_Y := -2.25
const SPEED := 4.2                  # m/s under way
const PER_PORT := {"puerto_alto": 6, "sarmada": 4, "isola_serena": 5}

var world: WorldManager
var entities: EntityManager
var life: IslandLife
var harbours: Array = []            # {id, style, centre, slots: [Vector3], ready, task, boats}
var boats: Array = []               # {harbour, index, route: PackedVector3Array, cum, ground: Vector3, phase, period, node, fisher}
var _height: Callable
var _pool: Array = []
var _tick := 0.0
var elapsed := 0.0


func setup(p_world: WorldManager, p_entities: EntityManager, p_life: IslandLife) -> void:
	world = p_world; entities = p_entities; life = p_life
	name = "OuterBoats"
	var outer: OuterWorld = world.outer
	_height = func(x: float, z: float) -> float: return outer.height_at(x, z)
	for t: Dictionary in outer.plan().get("towns", []):
		if PER_PORT.has(String(t.id)):
			harbours.append(_harbour(t, int(PER_PORT[t.id])))
	for t: Dictionary in outer.plan().get("hamlets", []):
		if String(t.style) == "isola":
			harbours.append(_harbour(t, 2))
	for h: Dictionary in harbours:
		for i in int(h.count):
			boats.append({"harbour": h, "index": i, "route": PackedVector3Array(), "cum": PackedFloat32Array(), "node": null, "fisher": null,
				"phase": float(hash([h.id, i]) % 1000) / 1000.0})


func _harbour(t: Dictionary, n: int) -> Dictionary:
	var pz: Array = t.plaza if t.get("plaza") != null else [t.center[0], 0.0, t.center[1]]
	var berth := Vector3.INF
	if t.get("port") != null:
		var b: Array = t.port.berth
		berth = Vector3(b[0], 0.0, b[2])
	return {"id": String(t.id), "style": StringName(t.style), "centre": Vector3(pz[0], 0.0, pz[2]), "edges": t.get("quay_edges", []),
		"berth": berth, "count": n, "ready": false, "task": -1, "slots": [], "routes": [], "grid_ms": 0.0, "route_ms": 0.0, "tries": 0}


func wait() -> void:
	for h in harbours:
		if int(h.task) >= 0:
			WorkerThreadPool.wait_for_task_completion(h.task); h.task = -1


func _exit_tree() -> void:
	wait()


func h(x: float, z: float) -> float:
	return float(_height.call(x, z))


# ---------------------------------------------------------------- planning (worker thread)
## Moorings off the quay (or the nearest water), fishing grounds out at sea, and a checked route
## out to each. Pure data.
func plan_harbour(hb: Dictionary) -> void:
	var c: Vector3 = hb.centre
	var slots: Array = []
	var berth: Vector3 = hb.berth
	for edge: Array in hb.edges:
		var acc := 999.0
		for k in range(1, edge.size()):
			var a := Vector2(edge[k - 1][0], edge[k - 1][1]); var b := Vector2(edge[k][0], edge[k][1])
			acc += a.distance_to(b)
			if acc < 16.0: continue
			acc = 0.0
			var tan := (b - a).normalized(); var nrm := Vector2(-tan.y, tan.x)
			for sgn in [1.0, -1.0]:
				var q: Vector2 = b + nrm * float(sgn) * 9.0
				if h(q.x, q.y) < WATER_Y - 0.5 and (berth == Vector3.INF or Vector2(berth.x, berth.z).distance_to(q) > 70.0):
					slots.append(Vector3(q.x, 0.0, q.y)); break
	if slots.is_empty():
		for r in range(60, 420, 20):
			for i in 24:
				var q := Vector2(c.x, c.z) + Vector2.from_angle(TAU * i / 24.0) * r
				if h(q.x, q.y) < WATER_Y - 0.6: slots.append(Vector3(q.x, 0.0, q.y))
			if slots.size() >= 4: break
	# spread the moorings out: every other one, at most 2 x the boats
	var picked: Array = []
	var stride := maxi(1, slots.size() / maxi(1, int(hb.count) * 2))
	for i in range(0, slots.size(), stride):
		picked.append(slots[i])
	hb.slots = picked
	if picked.is_empty(): hb.ready = true; return
	# the local water grid: corner heights sampled once, a cell is water when its centre and
	# corners are
	var grid := AStarGrid2D.new()
	var n := int(HALF * 2.0 / GRID)
	grid.region = Rect2i(0, 0, n, n)
	grid.cell_size = Vector2(1, 1)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	var ox := c.x - HALF; var oz := c.z - HALF
	var t0 := Time.get_ticks_usec()
	var corner := PackedFloat32Array(); corner.resize((n + 1) * (n + 1))
	for j in n + 1:
		for i in n + 1:
			corner[j * (n + 1) + i] = h(ox + i * GRID, oz + j * GRID)
	var wet_cells := PackedByteArray(); wet_cells.resize(n * n)
	for j in n:
		for i in n:
			var k0 := j * (n + 1) + i
			var wet := corner[k0] < -2.05 and corner[k0 + 1] < -2.05 and corner[k0 + n + 1] < -2.05 and corner[k0 + n + 2] < -2.05
			if wet: wet = h(ox + (i + 0.5) * GRID, oz + (j + 0.5) * GRID) < WATER_Y
			wet_cells[j * n + i] = 1 if wet else 0
			if not wet: grid.set_point_solid(Vector2i(i, j), true)
	var wet_grid := {"cells": wet_cells, "n": n, "o": Vector2(ox, oz)}
	hb.grid_ms = (Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	var tries := 0
	var routes: Array = []
	for b in int(hb.count):
		var route := PackedVector3Array()
		var rng := RandomNumberGenerator.new(); rng.seed = hash([hb.id, b, "ground"])
		for s_try in picked.size():
			var home: Vector3 = picked[(b * 2 + s_try) % picked.size()]
			var hc := Vector2i(floori((home.x - ox) / GRID), floori((home.z - oz) / GRID))
			if not grid.is_in_boundsv(hc) or grid.is_point_solid(hc):
				hc = _nearest_open(grid, hc, n)
			if hc == Vector2i(-1, -1): continue
			var unreachable := 0
			for attempt in 30:
				var ang := rng.randf() * TAU
				var dist := rng.randf_range(260.0, HALF - 140.0)
				var g := Vector2(c.x, c.z) + Vector2.from_angle(ang) * dist
				if h(g.x, g.y) > -5.0: continue
				var gc := Vector2i(floori((g.x - ox) / GRID), floori((g.y - oz) / GRID))
				if not grid.is_in_boundsv(gc) or grid.is_point_solid(gc): continue
				tries += 1
				var cells := grid.get_id_path(hc, gc)
				if cells.size() < 4:
					unreachable += 1
					if unreachable > 6: break          # this mooring is a closed basin
					continue
				var pts := PackedVector3Array([home])
				for cell in cells: pts.append(Vector3(ox + (cell.x + 0.5) * GRID, 0.0, oz + (cell.y + 0.5) * GRID))
				if not _water_line(pts[0], pts[1]): pts.remove_at(0)       # moor at the first open cell
				route = _pull(pts, wet_grid)
				if route_on_water(route): break
				route = PackedVector3Array()
			if not route.is_empty(): break
		routes.append(route)
	hb.routes = routes
	hb.route_ms = (Time.get_ticks_usec() - t0) / 1000.0
	hb.tries = tries
	hb.ready = true


func _nearest_open(grid: AStarGrid2D, c: Vector2i, n: int) -> Vector2i:
	for r in range(1, 12):
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				var q := c + Vector2i(dx, dz)
				if grid.is_in_boundsv(q) and not grid.is_point_solid(q): return q
	return Vector2i(-1, -1)


## Is the straight line a -> b over water cells of the grid being planned (a cheap check; the
## finished route is checked on the ground itself by route_on_water)?
func _wet_line(a: Vector3, b: Vector3, wg: Dictionary) -> bool:
	var cells: PackedByteArray = wg.cells
	var n: int = wg.n
	var o: Vector2 = wg.o
	var d := Vector2(b.x - a.x, b.z - a.z)
	var steps := maxi(1, ceili(d.length() / (GRID * 0.5)))
	for k in range(steps + 1):
		var q := Vector2(a.x, a.z) + d * (float(k) / steps)
		var i := floori((q.x - o.x) / GRID); var j := floori((q.y - o.y) / GRID)
		if i < 0 or j < 0 or i >= n or j >= n or cells[j * n + i] == 0: return false
	return true


## String-pull a cell path: skip ahead while the straight line stays on water.
func _pull(pts: PackedVector3Array, wg: Dictionary) -> PackedVector3Array:
	var out := PackedVector3Array([pts[0]])
	var i := 0
	while i < pts.size() - 1:
		var j := i + 1
		while j + 1 < pts.size() and _wet_line(pts[i], pts[j + 1], wg): j += 1
		out.append(pts[j]); i = j
	# round the corners a little (quarter points), then keep only what stays on water
	var soft := PackedVector3Array([out[0]])
	for k in range(1, out.size() - 1):
		var a := out[k].lerp(out[k - 1], minf(0.25, 30.0 / maxf(out[k].distance_to(out[k - 1]), 1.0)))
		var b := out[k].lerp(out[k + 1], minf(0.25, 30.0 / maxf(out[k].distance_to(out[k + 1]), 1.0)))
		soft.append(a); soft.append(b)
	soft.append(out[out.size() - 1])
	return soft if route_on_water(soft) else out


func _water_line(a: Vector3, b: Vector3) -> bool:
	var d := Vector2(b.x - a.x, b.z - a.z)
	var nrm := Vector2(-d.y, d.x).normalized() * 4.0
	var n := maxi(1, ceili(d.length() / 6.0))
	for k in range(n + 1):
		var q := a.lerp(b, float(k) / n)
		for s in [Vector2.ZERO, nrm, -nrm]:
			if h(q.x + s.x, q.z + s.y) >= -2.05: return false
	return true


## Every point of the route, sampled each 5 m, lies on water deeper than 2 m.
func route_on_water(route: PackedVector3Array) -> bool:
	if route.size() < 2: return false
	for k in range(1, route.size()):
		var a := route[k - 1]; var b := route[k]
		var n := maxi(1, ceili(Vector2(b.x - a.x, b.z - a.z).length() / 5.0))
		for s in range(n + 1):
			var q := a.lerp(b, float(s) / n)
			if h(q.x, q.z) >= -2.0: return false
	return true


# ---------------------------------------------------------------- the clock
## Where boat `b` is at time `t` (seconds): [position, forward, fishing?]. Moored ~90 s, out,
## ~150 s working the ground in slow circles, back.
func pose_at(b: Dictionary, t: float) -> Array:
	var route: PackedVector3Array = b.route
	var cum: PackedFloat32Array = b.cum
	var length := cum[cum.size() - 1]
	var leg := length / SPEED
	var moor := 90.0; var fish := 150.0
	var period := moor + leg + fish + leg
	var u := fposmod(t + float(b.phase) * period, period)
	if u < moor:
		var f := (route[1] - route[0]); f.y = 0.0
		return [route[0], f.normalized(), false]
	u -= moor
	if u < leg: return _along(route, cum, u * SPEED, false)
	u -= leg
	if u < fish:
		var g := route[route.size() - 1]
		var ang := u / fish * TAU
		var r := 26.0
		var into := (route[route.size() - 1] - route[route.size() - 2]).normalized()
		var centre := g + into * r
		var p := centre + Vector3(-into.x, 0, -into.z).rotated(Vector3.UP, ang) * r
		if h(p.x, p.z) >= -2.0: p = g
		var fwd := Vector3(-into.x, 0, -into.z).rotated(Vector3.UP, ang + PI * 0.5)
		return [p, fwd, true]
	u -= fish
	var back := _along(route, cum, length - u * SPEED, true)
	return back


static func _along(route: PackedVector3Array, cum: PackedFloat32Array, s: float, reverse: bool) -> Array:
	s = clampf(s, 0.0, cum[cum.size() - 1])
	var i := clampi(cum.bsearch(s, true) - 1, 0, route.size() - 2)
	var f := (s - cum[i]) / maxf(cum[i + 1] - cum[i], 0.001)
	var d := (route[i + 1] - route[i]); d.y = 0.0
	d = d.normalized()
	return [route[i].lerp(route[i + 1], f), -d if reverse else d, false]


func _process(delta: float) -> void:
	if harbours.is_empty(): return
	elapsed = (life.total_minutes / maxf(life.minutes_per_second, 0.0001)) if life else elapsed + delta
	var viewer := _viewer()
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.5
		for hb in harbours:
			var d := Vector2(hb.centre.x - viewer.x, hb.centre.z - viewer.z).length()
			if int(hb.task) < 0 and not hb.ready and d < PREPARE:
				hb.task = WorkerThreadPool.add_task(plan_harbour.bind(hb), false, "harbour boats")
			elif int(hb.task) >= 0 and WorkerThreadPool.is_task_completed(hb.task):
				WorkerThreadPool.wait_for_task_completion(hb.task); hb.task = -1
				_adopt(hb)
	for b in boats:
		if (b.route as PackedVector3Array).size() < 2 or int((b.harbour as Dictionary).task) >= 0:
			_hide(b); continue
		var pose := pose_at(b, elapsed)
		var p: Vector3 = pose[0]
		var near := p.distance_to(viewer) < VIEW_RADIUS
		if not near:
			_hide(b); continue
		var node: Node3D = b.node
		if node == null:
			node = _pool.pop_back() if not _pool.is_empty() else _make_boat()
			node.visible = true
			b.node = node
		var fwd: Vector3 = pose[1]
		var ph := float(b.phase) * 11.0
		node.position = p + Vector3(0, sin(elapsed * 1.5 + ph) * 0.08, 0)
		node.rotation = Vector3(sin(elapsed * 0.8 + ph) * 0.025, atan2(-fwd.x, -fwd.z), sin(elapsed * 1.1 + ph) * 0.06)
		_fisher(b, node, p.distance_to(viewer) < FISHER_RADIUS, bool(pose[2]))


## Hand a planned harbour's routes to its boats.
func _adopt(hb: Dictionary) -> void:
	for b in boats:
		if is_same(b.harbour, hb) and int(b.index) < (hb.routes as Array).size():
			b.route = hb.routes[b.index]
			var cum := PackedFloat32Array(); var total := 0.0
			for k in (b.route as PackedVector3Array).size():
				if k > 0: total += (b.route[k] as Vector3).distance_to(b.route[k - 1])
				cum.append(total)
			b.cum = cum


## Plan a harbour now (tests, tools).
func prepare_now(id: String) -> Dictionary:
	for hb in harbours:
		if hb.id != id: continue
		if int(hb.task) >= 0:
			WorkerThreadPool.wait_for_task_completion(hb.task); hb.task = -1
		if not hb.ready: plan_harbour(hb)
		_adopt(hb)
		return hb
	return {}


func _viewer() -> Vector3:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam: return cam.global_position
	return entities.focus.global_position if entities.focus else Vector3.ZERO


func _make_boat() -> Node3D:
	var boat := IslandArt.instantiate("fishing_boat")
	boat.name = "FishingBoat%d" % get_child_count()
	add_child(boat)
	return boat


func _hide(b: Dictionary) -> void:
	var node: Node3D = b.node
	if node == null: return
	node.visible = false
	var fisher: Node3D = node.get_node_or_null("Fisher")
	if fisher: fisher.visible = false
	_pool.append(node)
	b.node = null


## A fisher standing in the boat (a far mesh), hauling a line while the boat works the ground.
func _fisher(b: Dictionary, node: Node3D, show: bool, working: bool) -> void:
	var m: RiderModel = node.get_node_or_null("Fisher")
	if not show:
		if m: m.visible = false
		return
	var hb: Dictionary = b.harbour
	var look := CharacterLook.from_seed(hash([hb.id, b.index, "boat"]), hb.style, "fisher")
	if m == null:
		m = RiderModel.new(); m.name = "Fisher"
		m.manual_meshes = true
		m.look = look
		node.add_child(m)
		m.enable_resident_lod()
		m.position = Vector3(0.0, 0.45, 1.3)
	elif m.look.get("key", "") != look.key:
		m.set_look(look)
	var mesh := PersonBuilder.part(look, false)
	if mesh == null:
		PersonBuilder.request_part(look, false)
		m.visible = false
		return
	if m.person_meshes()[1] != mesh:
		m.set_person_meshes(null, mesh)
		m.show_person_level(false)
	m.visible = true
	m.animate("idle", 0.0, 0.1)
	if working:
		m.torso.rotation.x = -0.25
		m.arm_r.rotation.x = 0.9 + sin(elapsed * 1.7) * 0.35
		m.arm_l.rotation.x = 0.8 + sin(elapsed * 1.7 + 1.4) * 0.3
	else:
		m.arm_r.rotation.x = 0.5; m.arm_l.rotation.x = 0.2
	m.sync_resident_pose()
