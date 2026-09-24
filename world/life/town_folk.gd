class_name TownFolk
extends Node3D
## The people of the outer towns and hamlets (TownPopulation per plan town): hundreds of cheap
## records, bodies only near the viewer.
##
## Tiers, by the viewer's distance to a town:
##   far (beyond radius + PREPARE)   nothing: not even generated, costs nothing
##   prepare                         the population is generated on a worker thread
##   active (within radius + ACTIVE) everybody is placed where their routine says, and the
##                                   routines run: a person due somewhere asks for a route (a
##                                   worker computes it) and walks it along the streets
## Bodies: the MAX_BODIES people nearest the viewer (within VIEW_RADIUS) get a pooled TownBody;
## the MAX_NEAR nearest of those may show their detailed mesh. Meshes are PersonBuilder parts
## built on worker threads, nearest first; a body shows nothing until its far mesh is there.
## Pose updates are throttled by distance; far, still people are not touched between updates.
##
## Interface: setup(world, entities, life); towns (id -> TownPopulation); active_ids();
## bodies_in_use(); counts(); wait() (shutdown); stats (ms per frame, bodies).

const PREPARE := 1600.0
const ACTIVE := 520.0
const RELEASE := 760.0
const VIEW_RADIUS := 150.0
const MAX_BODIES := 160
const MAX_NEAR := 40
const FREE_KEEP := 24                # idle bodies kept while a town is active (none once the courier has left every town, m-4)
const FREE_TRIM_PER_PASS := 6
const NEAR_MESH := 24.0            # show the detailed mesh inside this (hysteresis +3 m)
const TICK_SLICE := 0.5            # every person is re-evaluated this often (s)
const CARRY_PAUSE := 3.5
const PLACE_PER_FRAME := 60
const ASSIGN_PER_PASS := 10        # new bodies handed out per view pass (nearest first)
const CREATE_PER_PASS := 4         # new pooled bodies built per view pass
const UNPLACED := -2

var world: WorldManager
var entities: EntityManager
var life: IslandLife
var towns: Dictionary = {}         # id -> TownPopulation
var order: Array = []              # ids, plan order
var active: Dictionary = {}        # id -> true
var bodies: Array = []             # TownBody pool
var viewed: Array = []             # Townsperson with a body, nearest first
var enabled := true
var frame_us := 0                  # the last frame's cost (records + views)
var frame_us_max := 0
## Running totals (µs) of the three parts, for benchmarks: the routines, choosing who gets a
## body, and moving / posing the bodies.
var tick_us_total := 0
var select_us_total := 0
var bodies_us_total := 0
var _activating: Dictionary = {}   # town id -> next person to place
var _pending_views := false
var _gen_task := -1
var _gen_town := ""
var _tick_cursor: Dictionary = {}  # town id -> next person index
var _tick_acc := 0.0
var _view_acc := 0.0
var _viewer := Vector3.ZERO
var _clock := 0.0


func setup(p_world: WorldManager, p_entities: EntityManager, p_life: IslandLife) -> void:
	world = p_world; entities = p_entities; life = p_life
	name = "TownFolk"
	var outer: OuterWorld = world.outer
	if outer == null or not outer.ok: return
	var height := func(x: float, z: float) -> float: return outer.height_at(x, z)
	for group in ["towns", "hamlets"]:
		for t: Dictionary in outer.plan().get(group, []):
			var pop := TownPopulation.new(t, height)
			towns[pop.id] = pop
			order.append(pop.id)


func minute() -> float:
	return life.minute_of_day() if life else 570.0


func now() -> float:
	return life.total_minutes if life else 570.0


func mps() -> float:
	return maxf(life.minutes_per_second if life else 0.5, 0.0001)


func viewer() -> Vector3:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam: return cam.global_position
	return entities.focus.global_position if entities and entities.focus else Vector3.ZERO


## Generate a town now (tests, tools); normally a worker does it as the viewer approaches.
func prepare_now(id: String) -> void:
	var pop: TownPopulation = towns[id]
	if pop.ready: return
	if _gen_task >= 0 and _gen_town == id:
		WorkerThreadPool.wait_for_task_completion(_gen_task); _gen_task = -1; _gen_town = ""
		return
	pop.generate()


## Tools and tests: run a town's routines from `from_min` to `to_min` (absolute game minutes) in
## `step` minute steps, computing routes synchronously, so a snapshot has people mid-walk as the
## steady state would. Leaves the clock at `to_min`.
func simulate(id: String, from_min: float, to_min: float, step := 2.0) -> void:
	var pop: TownPopulation = towns[id]
	life.total_minutes = from_min
	activate(id, true)
	var t := from_min
	while t < to_min:
		t = minf(t + step, to_min)
		life.total_minutes = t
		var m := minute()
		for p: Townsperson in pop.people: _step(pop, p, m, t)
		var guard := 0
		while pop.busy() and guard < 1000:
			pop.pump(); pop.wait(); guard += 1
		for p: Townsperson in pop.people: _step(pop, p, m, t)


## The clock jumped (a save loaded, a night slept away): re-place the active towns by the routine.
func reset() -> void:
	for id in active.keys():
		for p: Townsperson in (towns[id] as TownPopulation).people:
			if p.body: (p.body as TownBody).release()
		activate(id)
	viewed.clear()


func active_ids() -> Array:
	return active.keys()


func wait() -> void:
	if _gen_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_gen_task); _gen_task = -1
	for id in towns: (towns[id] as TownPopulation).wait()


func _exit_tree() -> void:
	wait()


# ---------------------------------------------------------------- the frame
func _process(delta: float) -> void:
	if towns.is_empty() or not enabled: return
	var t0 := Time.get_ticks_usec()
	_clock += delta
	_viewer = viewer()
	_manage_towns()
	for id in _activating.keys(): _place_some(id, PLACE_PER_FRAME)
	PersonBuilder.poll_parts()
	for id in active:
		(towns[id] as TownPopulation).pump()
	var t1 := Time.get_ticks_usec()
	_tick(delta)
	var t2 := Time.get_ticks_usec()
	_view_acc += delta
	if _view_acc >= (0.1 if _pending_views else 0.2):
		_view_acc = 0.0
		_select_views()
	var t3 := Time.get_ticks_usec()
	_update_bodies(delta)
	tick_us_total += t2 - t1
	select_us_total += t3 - t2
	bodies_us_total += Time.get_ticks_usec() - t3
	frame_us = Time.get_ticks_usec() - t0
	frame_us_max = maxi(frame_us_max, frame_us)


func _manage_towns() -> void:
	if _gen_task >= 0 and WorkerThreadPool.is_task_completed(_gen_task):
		WorkerThreadPool.wait_for_task_completion(_gen_task)
		_gen_task = -1; _gen_town = ""
	for id in order:
		var pop: TownPopulation = towns[id]
		var d := Vector2(pop.centre.x - _viewer.x, pop.centre.z - _viewer.z).length() - pop.radius
		if not pop.ready:
			if d < PREPARE and _gen_task < 0:
				_gen_town = id
				_gen_task = WorkerThreadPool.add_task(pop.generate, false, "town population")
			continue
		if d < ACTIVE and not active.has(id): activate(id)
		elif d > RELEASE and active.has(id): deactivate(id)


## Place everybody where the routine says right now (no walking yet: the next routine step starts
## the walks). Spread over frames (PLACE_PER_FRAME) unless `immediate`: entering a town never
## pays for the whole population in one frame.
func activate(id: String, immediate := false) -> void:
	var pop: TownPopulation = towns[id]
	if not pop.ready: prepare_now(id)
	active[id] = true
	pop.occupant.fill(-1)
	for p: Townsperson in pop.people:
		p.state = Townsperson.State.INDOORS
		p.entry = UNPLACED
	_activating[id] = 0
	_tick_cursor[id] = 0
	if immediate: _place_some(id, pop.people.size())


func _place_some(id: String, n: int) -> void:
	var pop: TownPopulation = towns[id]
	var i: int = _activating.get(id, 0)
	var m := minute()
	var end := mini(i + n, pop.people.size())
	while i < end:
		var p: Townsperson = pop.people[i]
		p.entry = p.entry_at(m)
		p.waiting = false; p.hold = 0.0
		p.set_path(PackedVector3Array())
		var e: Array = p.routine[p.entry]
		p.activity = e[2]
		p.spot = _reserve(pop, p, int(e[1]))
		_arrive(pop, p)
		i += 1
	if i >= pop.people.size(): _activating.erase(id)
	else: _activating[id] = i


func deactivate(id: String) -> void:
	active.erase(id)
	_activating.erase(id)
	for p: Townsperson in (towns[id] as TownPopulation).people:
		if p.body: (p.body as TownBody).release()
	viewed = viewed.filter(func(p: Townsperson) -> bool: return p.body != null)


## A seat / chat spot / stall front holds one person; a taken one sends him to the nearest
## free spot of the same kind (or, failing that, home).
func _reserve(pop: TownPopulation, p: Townsperson, want: int) -> int:
	if want < 0: return p.home
	var k: String = pop.spots[want].k
	if k in ["door"]: return want
	if k == "window": k = "browse"
	if pop.occupant[want] < 0 or pop.occupant[want] == p.index:
		pop.occupant[want] = p.index
		return want
	var kinds: Array = [k]
	if k == "chat": kinds = ["chat", "seat"]
	elif k == "browse": kinds = ["browse", "window"]
	for alt: int in pop.spots_near(pop.spots[want].p, kinds, 60.0):
		if pop.occupant[alt] < 0:
			pop.occupant[alt] = p.index
			return alt
	return p.home if k in ["seat", "chat", "browse", "window"] else want


func _release_spot(pop: TownPopulation, p: Townsperson) -> void:
	if p.spot >= 0 and p.spot < pop.occupant.size() and pop.occupant[p.spot] == p.index:
		pop.occupant[p.spot] = -1


func _arrive(pop: TownPopulation, p: Townsperson) -> void:
	var s: Dictionary = pop.spots[p.spot]
	p.position = s.p
	p.forward = s.f
	if p.activity == "home" or (p.spot == p.home and s.k == "door"):
		p.state = Townsperson.State.INDOORS
	else:
		p.state = Townsperson.State.AT_SPOT
	p.set_path(PackedVector3Array())


## A slice of every active town's people each frame: whoever's routine has moved on asks for
## his route, and sets off when it is there.
func _tick(delta: float) -> void:
	var m := minute()
	var tnow := now()
	for id in active:
		var pop: TownPopulation = towns[id]
		var n := pop.people.size()
		if n == 0: continue
		var per_frame := maxi(1, ceili(n * delta / TICK_SLICE))
		var c: int = _tick_cursor.get(id, 0)
		for k in mini(per_frame, n):
			var p: Townsperson = pop.people[(c + k) % n]
			_step(pop, p, m, tnow)
		_tick_cursor[id] = (c + per_frame) % n


func _step(pop: TownPopulation, p: Townsperson, m: float, tnow: float) -> void:
	if p.entry == UNPLACED: return
	if p.state == Townsperson.State.WALKING:
		if _walked(p, tnow) >= p.path_length():
			_arrive(pop, p)
		return
	if p.waiting:
		var ready: Variant = pop.route_ready(p.spot, p.target)
		if ready == null: return
		_depart(pop, p, ready, tnow)
		return
	var e := p.entry_at(m)
	if e == p.entry: return
	p.entry = e
	var entry: Array = p.routine[e]
	var to := int(entry[1])
	var activity: String = entry[2]
	_release_spot(pop, p)
	var target := _reserve(pop, p, to)
	p.activity = "home" if target == p.home and to != p.home else activity
	if target == p.spot:
		_arrive(pop, p)
		return
	p.target = target
	var ready: Variant = pop.route_ready(p.spot, target)
	if ready == null:
		pop.queue_route(p.spot, target)
		p.waiting = true
		return
	_depart(pop, p, ready, tnow)


func _depart(pop: TownPopulation, p: Townsperson, route: PackedVector3Array, tnow: float) -> void:
	p.waiting = false
	var to := p.target
	if route.size() < 2:
		# not connected: he stays where he is (indoors if that is home)
		_arrive(pop, p)
		return
	# his own lane: a small sideways offset, so a crowd spreads over the street
	var laned := PackedVector3Array()
	for i in route.size():
		var q := route[i]
		if i > 0 and i < route.size() - 1:
			var d := route[i + 1] - route[i - 1]; d.y = 0.0
			if d.length_squared() > 0.01:
				var side := Vector3(-d.z, 0, d.x).normalized() * p.lane
				if pop.clear(q.x + side.x, q.z + side.z, 0.25): q += side
		laned.append(q)
	p.spot = to
	p.set_path(laned)
	p.depart = tnow
	p.hold = 0.0
	p.state = Townsperson.State.WALKING


func _walked(p: Townsperson, tnow: float) -> float:
	return maxf(0.0, (tnow - p.depart) / mps() - p.hold) * p.speed


# ---------------------------------------------------------------- views
func _select_views() -> void:
	# distance bands instead of a sort: O(n), nearest band first
	const BANDS := 15
	var bins: Array = []
	for i in BANDS: bins.append([])
	var tnow := now()
	for id in active:
		var pop: TownPopulation = towns[id]
		if pop.centre.distance_to(_viewer) > pop.radius + VIEW_RADIUS + 60.0: continue
		for p: Townsperson in pop.people:
			if p.state == Townsperson.State.INDOORS: continue
			var pos := p.position
			if p.state == Townsperson.State.WALKING: pos = p.sample(_walked(p, tnow))[0]
			var d := pos.distance_to(_viewer)
			if d < VIEW_RADIUS: bins[mini(int(d / VIEW_RADIUS * BANDS), BANDS - 1)].append([d, p, pop])
	var cands: Array = []
	for b: Array in bins:
		if cands.size() >= MAX_BODIES: break
		if b.size() > 1 and cands.size() < MAX_NEAR + 8: b.sort_custom(func(x, y): return x[0] < y[0])
		cands.append_array(b)
	if cands.size() > MAX_BODIES: cands.resize(MAX_BODIES)
	var keep := {}
	for c in cands: keep[c[1]] = true
	for p: Townsperson in viewed:
		if not keep.has(p) and p.body: (p.body as TownBody).release()
	var free: Array = []
	for b: TownBody in bodies:
		if b.person == null: free.append(b)
	# m-4: bodies left over when the courier leaves a town are freed a few per pass (a whole pool of
	# 160 rigged bodies stayed in the tree for the rest of the session), keeping a reserve
	var keep_free := FREE_KEEP if not active.is_empty() else 0
	if free.size() > keep_free and cands.size() < bodies.size() - keep_free:
		for k in range(mini(FREE_TRIM_PER_PASS, free.size() - keep_free)):
			var extra: TownBody = free.pop_back()
			bodies.erase(extra)
			extra.queue_free()
	viewed.clear()
	var assigned := 0; var created := 0
	_pending_views = false
	for i in cands.size():
		var p: Townsperson = cands[i][1]
		var pop: TownPopulation = cands[i][2]
		p.view_distance = float(cands[i][0])
		if p.body == null:
			if assigned >= ASSIGN_PER_PASS or (free.is_empty() and created >= CREATE_PER_PASS):
				_pending_views = true
				continue
			var b: TownBody
			if free.is_empty():
				b = TownBody.new(); b.name = "Townsperson%d" % bodies.size()
				bodies.append(b)
				add_child(b)
				created += 1
			else: b = free.pop_back()
			b.assign(p, p.look(pop.style))
			b.pop = pop
			assigned += 1
		var body: TownBody = p.body
		body.near = i < MAX_NEAR
		viewed.append(p)
		var meshes := body.model.person_meshes()
		if meshes[1] == null or (body.near and meshes[0] == null and p.view_distance < NEAR_MESH + 8.0):
			var look := p.look(pop.style)
			if meshes[1] == null: PersonBuilder.request_part(look, false, i < 24)
			if body.near and meshes[0] == null and p.view_distance < NEAR_MESH + 8.0:
				PersonBuilder.request_part(look, true, true)


func _update_bodies(delta: float) -> void:
	var tnow := now()
	var clock := tnow / mps()
	for p: Townsperson in viewed:
		var b: TownBody = p.body
		if b == null: continue
		var pop: TownPopulation = b.pop
		var walking := p.state == Townsperson.State.WALKING
		var pos := p.position
		var face := p.forward
		var carrying := false
		var spot: Dictionary = pop.spots[p.spot] if p.spot >= 0 else {}
		var pose: String = spot.get("pose", "chat") if p.activity != "home" else "chat"
		if walking:
			# the courier in the way holds him (a pedestrian never walks through the boy)
			var s := p.sample(_walked(p, tnow))
			pos = s[0]; face = s[1]
			if entities.focus and p.view_distance < 30.0:
				var off: Vector3 = entities.focus.global_position - pos
				if absf(off.y) < 2.0 and off.dot(face) > 0.0 and off.dot(face) < 1.6 and absf(off.cross(face).y) < 0.8:
					p.hold += delta
		elif pose == "carry" and spot.has("b"):
			var r := _carry(p, spot, clock)
			pos = r[0]; face = r[1]; walking = r[2]; carrying = r[3]
		elif pose == "sit":
			pos = spot.p
		var d := pos.distance_to(_viewer)
		p.view_distance = d
		# far walkers move 10-20 times a second, not every frame; still people not at all
		b.move_t += delta
		if pos != b.last_pos and (d < 40.0 or b.move_t > (0.05 if d < 80.0 else 0.1)):
			b.move_t = 0.0
			b.last_pos = pos
			b.global_position = pos
			var yaw := atan2(-face.x, -face.z)
			b.rotation.y = lerp_angle(b.rotation.y, yaw, clampf(delta * 8.0, 0.0, 1.0)) if walking and d < 40.0 else yaw
		elif not walking and absf(wrapf(b.rotation.y - atan2(-face.x, -face.z), -PI, PI)) > 0.01:
			b.rotation.y = atan2(-face.x, -face.z)
		# meshes, collider and shadows: checked a few times a second
		b.check_t -= delta
		if b.check_t <= 0.0:
			b.check_t = 0.12 + float(p.index % 5) * 0.02
			var want_near := b.near and d < (NEAR_MESH + (3.0 if b.showing_near else 0.0))
			b.visible = b.refresh_meshes(p.look(pop.style), want_near)
			b.set_collision(d < 25.0 and b.visible)
			b.set_shadows(d < 45.0)
		var has_mesh := b.visible
		# pose updates by distance: every frame up close and walking, rarer further away
		var interval := 0.0
		if d > 70.0: interval = 0.25 if walking else 1.2
		elif d > 30.0: interval = 0.1 if walking else 0.5
		elif d > 12.0: interval = 1.0 / 30.0 if walking else 0.1
		elif not walking: interval = 1.0 / 15.0
		b.anim_t += delta
		if has_mesh and (b.anim_t >= interval or b.pose == ""):
			b.animate(walking, carrying, pose, float(spot.get("seat", 0.46)), b.anim_t, clock)
			b.anim_t = 0.0


## A dockworker's loop between his spot and the other end: pick up, carry, put down, walk back.
func _carry(p: Townsperson, spot: Dictionary, clock: float) -> Array:
	var a: Vector3 = spot.p; var b: Vector3 = spot.b
	var dist := maxf(Vector2(b.x - a.x, b.z - a.z).length(), 0.5)
	var leg := dist / p.speed
	var period := 2.0 * (leg + CARRY_PAUSE)
	var t := fposmod(clock + float(p.seed % 1000) * 0.13, period)
	var fwd := (b - a); fwd.y = 0.0; fwd = fwd.normalized()
	var ys: PackedFloat32Array = spot.get("ys", PackedFloat32Array())
	if t < CARRY_PAUSE: return [a, -fwd if fwd.length() > 0 else p.forward, false, t > CARRY_PAUSE * 0.6]
	t -= CARRY_PAUSE
	if t < leg: return [_on_ground(a, b, t / leg, ys), fwd, true, true]
	t -= leg
	if t < CARRY_PAUSE: return [b, fwd, false, t < CARRY_PAUSE * 0.4]
	t -= CARRY_PAUSE
	return [_on_ground(a, b, 1.0 - clampf(t / leg, 0.0, 1.0), ys), -fwd, true, false]


static func _on_ground(a: Vector3, b: Vector3, f: float, ys: PackedFloat32Array) -> Vector3:
	var q := a.lerp(b, f)
	if ys.size() >= 2:
		var u := clampf(f, 0.0, 1.0) * (ys.size() - 1)
		var i := mini(floori(u), ys.size() - 2)
		q.y = lerpf(ys[i], ys[i + 1], u - i)
	return q


# ---------------------------------------------------------------- reporting
func bodies_in_use() -> int:
	var n := 0
	for b: TownBody in bodies:
		if b.person != null: n += 1
	return n


func near_in_use() -> int:
	var n := 0
	for b: TownBody in bodies:
		if b.person != null and b.showing_near: n += 1
	return n


func population() -> Dictionary:
	var out := {}
	for id in order: out[id] = TownPopulation.population_for((towns[id] as TownPopulation)._plan)
	return out
