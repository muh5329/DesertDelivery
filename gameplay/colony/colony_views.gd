class_name ColonyViews
extends Node3D
## What the colony economy looks like near the viewer (the courier, or the Mayor map's focus):
##   - buildings: BuildingKit plots in the colony's town style with a yard of props, staked
##     foundations and scaffolds while under construction; built one per frame, freed when far;
##   - people: colonists as townsfolk (CharacterLook, the colony's style and the job's clothes) -
##     porters walking each building's real trip with a crate, workers in the yards, idle
##     colonists by the hall; at most MAX_PEOPLE, nearest first, only round near colonies;
##   - ships: a ShipModel for each ship within SHIP_RADIUS (at most MAX_SHIPS);
##   - the Mayor map overlay: colony names, the build area, footprints, lanes, ships, coves.
## Everything is read from the economy's records every frame; nothing here is saved.

const BUILDING_RADIUS := 1300.0
const PEOPLE_RADIUS := 230.0
const MAX_PEOPLE := 24
const SHIP_RADIUS := 2200.0
const MAX_SHIPS := 6
const KIT_STYLE := {"island": "core", "puerto": "puerto", "valdoro": "valdoro", "sarmada": "sarmada", "isola": "isola", "campo": "campo"}
const WALL := {"island": Color("efe8da"), "puerto": Color("e8d9b8"), "valdoro": Color("a39f95"), "sarmada": Color("f2ede2"), "isola": Color("f0b9b0"), "campo": Color("e9dcc0")}
const LANE_COLORS := [Color("e8b04a"), Color("5fb3c9"), Color("d9735b"), Color("9fc76a"), Color("c792d8"), Color("f0e08a")]

var econ: ColonyEconomy
var buildings: Dictionary = {}     # building id -> {node, key}
var people: Dictionary = {}        # colonist id -> {node, model, crate}
var ships: Dictionary = {}         # ship id -> ShipModel
var jetties: Dictionary = {}       # colony id -> Node3D (the timber jetty at a port's mooring)
var map_root: Node3D
var map_active := false
var map_colony := ""
var map_zoom := 100.0
var build_count := 0               # BuildingKit builds done (perf tools)
var _queue: Array = []
var _paths: Dictionary = {}        # building id -> PackedVector3Array (door to storage)
var _bodies: Dictionary = {}
var _route_budget := 1
var _t := 0.0
var _people_plan: Array = []
var _yard_mat: StandardMaterial3D
var _map_lanes_zoom := -1.0
var _map_dirty := true
var _ship_markers: MultiMeshInstance3D
var _lane_meshes: Node3D
var _static_overlay: Node3D
var _labels: Node3D
var _buoys: MultiMeshInstance3D
var _buoy_points: Array = []       # [Vector3 position, bool starboard] along every lane
var _buoy_key := ""
const BUOY_SPACING := 320.0
const BUOY_RADIUS := 1600.0
const MAX_BUOYS := 64


func setup(p_econ: ColonyEconomy) -> void:
	econ = p_econ
	_yard_mat = StandardMaterial3D.new(); _yard_mat.vertex_color_use_as_albedo = true; _yard_mat.vertex_color_is_srgb = true; _yard_mat.roughness = 0.92
	map_root = Node3D.new(); map_root.name = "ColonyMap"; add_child(map_root); map_root.visible = false
	_lane_meshes = Node3D.new(); map_root.add_child(_lane_meshes)
	_static_overlay = Node3D.new(); map_root.add_child(_static_overlay)
	_labels = Node3D.new(); map_root.add_child(_labels)
	_ship_markers = MultiMeshInstance3D.new()
	var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D; mm.use_colors = true
	mm.mesh = _arrow_mesh(); mm.instance_count = ShippingNetwork.MAX_SHIPS; mm.visible_instance_count = 0
	_ship_markers.multimesh = mm
	_ship_markers.material_override = _overlay_mat(Color.WHITE, true)
	_ship_markers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	map_root.add_child(_ship_markers)
	econ.changed.connect(func(): _map_dirty = true)
	_buoys = MultiMeshInstance3D.new(); _buoys.name = "LaneBuoys"
	var bm := MultiMesh.new(); bm.transform_format = MultiMesh.TRANSFORM_3D; bm.use_colors = true
	bm.mesh = _buoy_mesh(); bm.instance_count = MAX_BUOYS; bm.visible_instance_count = 0
	_buoys.multimesh = bm
	var buoy_mat := StandardMaterial3D.new(); buoy_mat.vertex_color_use_as_albedo = true; buoy_mat.vertex_color_is_srgb = true; buoy_mat.roughness = 0.6
	_buoys.material_override = buoy_mat
	add_child(_buoys)


func reset() -> void:
	for bid in buildings.keys(): _free_building(bid)
	for cid in people.keys():
		people[cid].node.queue_free()
	people.clear()
	for sid in ships.keys(): ships[sid].queue_free()
	ships.clear()
	_paths.clear(); _queue.clear()
	_map_dirty = true


func owns(body: Object) -> bool:
	return _bodies.has(body.get_instance_id())


func viewer() -> Vector3:
	if econ.game == null: return Vector3.ZERO
	var f: Node3D = econ.game.world.streamer.focus
	return f.global_position if f != null else Vector3.ZERO


func _process(delta: float) -> void:
	if econ == null or econ.game == null: return
	_t += delta
	var v := viewer()
	if _t >= 0.25:
		_t = 0.0
		_sync_buildings(v)
		_sync_far()
		_plan_people(v)
		_sync_ships(v)
	_sync_buoys(v)
	if not _queue.is_empty(): _build_next()
	_route_budget = 1
	_update_people(v, delta)
	_update_ships(delta)
	if map_active: _update_map()


# ------------------------------------------------------------------ buildings
static func stage_key(b: Dictionary) -> String:
	if b.built: return "built"
	if float(b.progress) < 0.3: return "found"
	return "scaffold%d" % int(float(b.progress) * 5.0)


func _sync_buildings(v: Vector3) -> void:
	var alive := {}
	for cid in econ.towns:
		var t: ColonyTown = econ.towns[cid]
		if not t.founded: continue
		var near := Vector2(t.hall.x - v.x, t.hall.z - v.z).length() < BUILDING_RADIUS + EconomyCatalog.build_radius(cid)
		for b in t.buildings:
			if b.get("virtual", false): continue
			alive[b.id] = true
			var d := Vector2(float(b.x) - v.x, float(b.z) - v.z).length()
			if near and d < BUILDING_RADIUS:
				var key := stage_key(b)
				if not buildings.has(b.id) or buildings[b.id].key != key:
					if not b.id in _queue: _queue.append(b.id)
			elif buildings.has(b.id) and d > BUILDING_RADIUS + 200.0:
				_free_building(b.id)
	for bid in buildings.keys():
		if not alive.has(bid): _free_building(bid)


## Far colonies: one BuildingKit silhouette mesh per colony (the same plan as the detailed
## buildings), drawn from where the detailed ones are freed out to the horizon, rebuilt when a
## building is completed or removed.
const FAR_BEGIN := BUILDING_RADIUS + 150.0
const FAR_END := 9000.0
var _far: Dictionary = {}          # colony id -> {node, sig}


func _sync_far() -> void:
	for cid in econ.towns:
		var t: ColonyTown = econ.towns[cid]
		var plots: Array = []
		var sig := ""
		if t.founded:
			for b in t.buildings:
				if b.get("virtual", false) or not b.built: continue
				sig += String(b.id) + ";"
				plots.append(far_plot(t, b))
		var have: Dictionary = _far.get(cid, {})
		if have.get("sig", "") == sig: continue
		if have.has("node") and is_instance_valid(have.node): (have.node as Node).queue_free()
		_far.erase(cid)
		if plots.is_empty(): continue
		var mi := MeshInstance3D.new()
		mi.name = "ColonyFar_" + cid
		mi.mesh = BuildingKit.build_lod(plots)
		mi.visibility_range_begin = FAR_BEGIN
		mi.visibility_range_begin_margin = 60.0
		mi.visibility_range_end = FAR_END
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add_child(mi)
		mi.global_position = t.hall
		_far[cid] = {"node": mi, "sig": sig}


## The silhouette plot of a built colony building, relative to its colony's hall.
func far_plot(t: ColonyTown, b: Dictionary) -> Dictionary:
	var def := EconomyCatalog.building(b.type)
	var yard := ColonyProps.yard_width(String(def.get("prop", "")))
	var at := Vector3(float(b.x), float(b.y), float(b.z)) + Basis(Vector3.UP, float(b.yaw)) * Vector3(-yard * 0.5, 0, 0) - t.hall
	return {"id": b.id, "style": KIT_STYLE.get(String(t.style), "core"), "kind": def.kind, "x": at.x, "y": at.y, "z": at.z,
		"yaw": rad_to_deg(float(b.yaw)), "w": float(def.w), "d": float(def.d), "floors": int(def.floors),
		"seed": absi(String(b.id).hash()), "tags": [], "ground_min": float(b.get("ground", b.y)) - t.hall.y, "party": [false, false]}


func has_far(cid: String) -> bool:
	return _far.has(cid)


func _free_building(bid: String) -> void:
	if not buildings.has(bid): return
	var node: Node3D = buildings[bid].node
	for body in node.find_children("*", "StaticBody3D", true, false): _bodies.erase(body.get_instance_id())
	node.queue_free()
	buildings.erase(bid)
	_paths.erase(bid)


func _find(bid: String) -> Array:
	for cid in econ.towns:
		var t: ColonyTown = econ.towns[cid]
		var b := t.building(bid)
		if not b.is_empty(): return [t, b]
	return []


func _build_next() -> void:
	var bid: String = _queue.pop_front()
	var found := _find(bid)
	if found.is_empty(): return
	var t: ColonyTown = found[0]; var b: Dictionary = found[1]
	var key := stage_key(b)
	if buildings.has(bid):
		if buildings[bid].key == key: return
		_free_building(bid)
	var node := build_node(t, b)
	add_child(node)
	node.global_position = Vector3(float(b.x), float(b.y), float(b.z))
	for body in node.find_children("*", "StaticBody3D", true, false): _bodies[body.get_instance_id()] = true
	buildings[bid] = {"node": node, "key": key}
	build_count += 1
	_paths.erase(bid)


## One colony building (in its own frame: origin on the pad, front along +z).
func build_node(t: ColonyTown, b: Dictionary) -> Node3D:
	var def := EconomyCatalog.building(b.type)
	var prop := String(def.get("prop", ""))
	var w := float(def.w); var d := float(def.d)
	var yard := ColonyProps.yard_width(prop)
	var node := Node3D.new()
	node.name = "ColonyBuilding_" + String(b.id).replace(".", "_")
	node.rotation.y = float(b.yaw)
	var drop := float(b.y) - float(b.get("ground", b.y))
	var seed := absi(String(b.id).hash())
	if drop > 0.12:
		var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
		MeshBits.box(st, Transform3D(Basis(), Vector3(0, -(drop + 0.5) * 0.5 + 0.02, 0)), Vector3(w + yard + 0.6, drop + 0.5, d + 2.2), Color("7d6f58"))
		st.generate_normals()
		var terrace := MeshInstance3D.new(); terrace.name = "Terrace"; terrace.mesh = st.commit(); terrace.material_override = _yard_mat
		node.add_child(terrace)
	if b.built:
		var holder := Node3D.new(); holder.name = "Building"; holder.position.x = -yard * 0.5
		node.add_child(holder)
		var plot := {"id": b.id, "style": KIT_STYLE.get(String(t.style), "core"), "kind": def.kind, "x": 0.0, "y": 0.0, "z": 0.0,
			"yaw": 0.0, "w": w, "d": d, "floors": int(def.floors), "seed": seed, "tags": ["shopfront"] if def.kind == "shop" else [],
			"ground_min": -drop, "party": [false, false]}
		BuildingKit.build_local(holder, plot, true)
		if prop != "":
			var ym := MeshInstance3D.new(); ym.name = "Yard"; ym.mesh = ColonyProps.yard(prop, w, d, seed); ym.material_override = _yard_mat
			node.add_child(ym)
		var sign := Label3D.new(); sign.name = "Sign"; sign.text = def.name
		sign.position = Vector3(-yard * 0.5, 0.2 + 3.1 * int(def.floors) + 1.4, d * 0.5 + 0.5)
		sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED; sign.font_size = 34; sign.pixel_size = 0.012
		sign.outline_size = 8; sign.modulate = Color("f7ecd0"); sign.visibility_range_end = 60.0
		node.add_child(sign)
	else:
		var cm := MeshInstance3D.new(); cm.name = "Construction"; cm.position.x = -yard * 0.5
		cm.mesh = ColonyProps.construction(w, d, float(b.progress), WALL.get(String(t.style), Color.WHITE))
		cm.material_override = _yard_mat
		node.add_child(cm)
	return node


## The door of a building (world): in front of the building part of the site.
func door(t: ColonyTown, b: Dictionary) -> Vector3:
	if b.get("virtual", false): return t.hall
	var def := EconomyCatalog.building(b.type)
	var yard := ColonyProps.yard_width(String(def.get("prop", "")))
	var local := Vector3(-yard * 0.5, 0, float(def.d) * 0.5 + 1.2)
	var p := Vector3(float(b.x), 0, float(b.z)) + Basis(Vector3.UP, float(b.yaw)) * local
	p.y = econ._height(p.x, p.z)
	return p


func yard_spot(t: ColonyTown, b: Dictionary, k: int) -> Vector3:
	var def := EconomyCatalog.building(b.type)
	var local := Vector3(float(def.w) * 0.5 + 0.5, 0, -1.0 + k * 2.0)
	var p := Vector3(float(b.x), 0, float(b.z)) + Basis(Vector3.UP, float(b.yaw)) * local
	p.y = float(b.y)
	return p


# ------------------------------------------------------------------ people
func _plan_people(v: Vector3) -> void:
	var plan: Array = []
	for cid in econ.towns:
		var t: ColonyTown = econ.towns[cid]
		if not t.founded or Vector2(t.hall.x - v.x, t.hall.z - v.z).length() > PEOPLE_RADIUS + EconomyCatalog.build_radius(cid): continue
		var by_job := {}
		var idle: Array = []
		for c in t.colonists:
			if c.job == "": idle.append(c)
			else:
				if not by_job.has(c.job): by_job[c.job] = []
				by_job[c.job].append(c)
		for b in t.buildings:
			var crew: Array = by_job.get(b.id, [])
			if crew.is_empty(): continue
			var k := 0
			if not b.carry.is_empty():
				plan.append({"c": crew[0], "t": t, "b": b, "role": "porter", "at": door(t, b)})
				k = 1
			for i in range(k, mini(crew.size(), k + 2)):
				plan.append({"c": crew[i], "t": t, "b": b, "role": "worker", "at": yard_spot(t, b, i - k)})
		for i in range(mini(idle.size(), 4)):
			var a := TAU * i / 4.0
			var hb: Dictionary = t.buildings[0] if not t.buildings.is_empty() else {}
			var base := door(t, hb) if not hb.is_empty() else t.hall
			plan.append({"c": idle[i], "t": t, "b": {}, "role": "idle", "at": base + Vector3(cos(a) * 2.2 + 3.0, 0, sin(a) * 2.2)})
	plan = plan.filter(func(e): return v.distance_to(e.at) < PEOPLE_RADIUS)
	plan.sort_custom(func(a, b): return v.distance_squared_to(a.at) < v.distance_squared_to(b.at))
	if plan.size() > MAX_PEOPLE: plan.resize(MAX_PEOPLE)
	_people_plan = plan
	var want := {}
	for e in plan: want[e.c.id] = e
	for id in people.keys():
		if not want.has(id):
			people[id].node.queue_free(); people.erase(id)
	for id in want:
		if not people.has(id): people[id] = _spawn_person(want[id])
		people[id].plan = want[id]


func _spawn_person(e: Dictionary) -> Dictionary:
	var t: ColonyTown = e.t
	var occupation := EconomyCatalog.occupation(e.b.type) if not e.b.is_empty() else "porter"
	var node := Node3D.new(); node.name = "Colonist_" + String(e.c.id).replace(".", "_")
	add_child(node)
	node.global_position = e.at
	var model := RiderModel.new()
	model.look = CharacterLook.from_seed(int(e.c.seed), t.style, occupation, String(e.c.get("sex", "")))
	model.async_build = true
	node.add_child(model)
	model.enable_resident_lod()
	var crate := MeshInstance3D.new(); crate.name = "Crate"
	var bm := BoxMesh.new(); bm.size = Vector3(0.46, 0.34, 0.36); crate.mesh = bm
	crate.material_override = Mats.solid(Color("9a7448"), 0.85)
	crate.position = Vector3(0, 1.08, -0.34)
	node.add_child(crate)
	return {"node": node, "model": model, "crate": crate, "plan": e, "yaw": 0.0}


## Where a porter is on its trip: the building's carry record, eased between economy ticks.
func _porter_pose(e: Dictionary) -> Array:
	var t: ColonyTown = e.t; var b: Dictionary = e.b
	var carry: Dictionary = b.carry
	if carry.is_empty(): return [door(t, b), Vector3.FORWARD, false, false]
	var path := _path_for(t, b)
	var dur := float(carry.dur)
	var tt := clampf(float(carry.t) + econ.pending(t.id), 0.0, dur)
	var walk := clampf((tt - 1.0) / maxf(dur - 2.0, 0.1), 0.0, 1.0)
	if int(carry.phase) == 1: walk = 1.0 - walk
	var at := _along(path, walk)
	var ahead := _along(path, clampf(walk + (0.02 if int(carry.phase) == 0 else -0.02), 0.0, 1.0))
	var dir := ahead - at; dir.y = 0.0
	var moving := tt > 1.0 and tt < dur - 1.0
	return [at, dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD, moving, not (carry.load as Dictionary).is_empty()]


## The porter's walk from its door to the storage door: the colony's own route finder (roads and
## paths preferred, round obstacles), at most one new route a frame; a straight, grounded line
## meanwhile or where no route is found.
func _path_for(t: ColonyTown, b: Dictionary) -> PackedVector3Array:
	if _paths.has(b.id): return _paths[b.id]
	var a := door(t, b)
	var s := t.storage_for(b)
	var z := door(t, s) if not s.is_empty() else t.hall
	var path := PackedVector3Array()
	var solve := _route_budget > 0
	if solve and econ.system != null and econ.system.roads != null and a.distance_to(z) < 240.0:
		_route_budget -= 1
		path = econ.system.roads.route(a, z)
	if path.size() < 2:
		path = PackedVector3Array()
		var n := maxi(2, ceili(a.distance_to(z) / 3.0))
		for i in range(n + 1):
			var p := a.lerp(z, float(i) / n)
			p.y = econ._height(p.x, p.z)
			path.append(p)
	else:
		path.insert(0, a)
	if solve: _paths[b.id] = path
	return path


static func _along(path: PackedVector3Array, f: float) -> Vector3:
	if path.size() == 1: return path[0]
	var total := 0.0
	for i in range(path.size() - 1): total += path[i].distance_to(path[i + 1])
	var want := total * f
	for i in range(path.size() - 1):
		var seg := path[i].distance_to(path[i + 1])
		if want <= seg: return path[i].lerp(path[i + 1], want / maxf(seg, 0.001))
		want -= seg
	return path[path.size() - 1]


func _update_people(v: Vector3, delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var clock := Time.get_ticks_msec() * 0.001
	for id in people:
		var p: Dictionary = people[id]
		var e: Dictionary = p.plan
		var node: Node3D = p.node; var model: RiderModel = p.model
		var target: Vector3 = e.at; var dir := Vector3.ZERO; var moving := false; var carrying := false
		if e.role == "porter":
			var pose := _porter_pose(e)
			target = pose[0]; dir = pose[1]; moving = pose[2]; carrying = pose[3]
			node.global_position = target
		else:
			node.global_position = node.global_position.lerp(target, minf(1.0, delta * 3.0))
			var face: Vector3 = (Vector3(float(e.b.x), 0, float(e.b.z)) if not e.b.is_empty() else (e.t as ColonyTown).hall) - target
			if e.role == "idle": face = (target - (e.t as ColonyTown).hall).rotated(Vector3.UP, PI * 0.5)
			face.y = 0.0
			dir = face.normalized() if face.length() > 0.1 else Vector3.FORWARD
		var yaw := atan2(-dir.x, -dir.z)
		p.yaw = lerp_angle(float(p.yaw), yaw, minf(1.0, delta * 8.0))
		node.rotation.y = p.yaw
		if cam: model.set_resident_lod_distance(cam.global_position.distance_to(node.global_position))
		model.animate("walk" if moving else "idle", ColonyTown.WALK_SPEED if moving else 0.0, delta)
		if carrying:
			model.arm_l.rotation.x = 1.05; model.arm_r.rotation.x = 1.05
			model.arm_l.rotation.z = -0.25; model.arm_r.rotation.z = 0.25
		elif e.role == "worker" and not moving:
			model.arm_r.rotation.x = 0.55 + sin(clock * 2.0 + float(e.c.seed % 7)) * 0.3
			model.arm_l.rotation.x = 0.35
			model.torso.rotation.x = -0.14
		elif e.role == "idle":
			model.arm_r.rotation.x = 0.25 + maxf(0.0, sin(clock + float(e.c.seed % 5))) * 0.5
		(p.crate as Node3D).visible = carrying
		model.sync_resident_pose()


# ------------------------------------------------------------------ ships
func _sync_ships(v: Vector3) -> void:
	var sh := econ.shipping
	for cid in sh.ports:
		var port: Dictionary = sh.ports[cid]
		var m: Vector2 = port.moor
		var near := Vector2(v.x, v.z).distance_to(m) < SHIP_RADIUS
		if near and not jetties.has(cid):
			var j := jetty(port)
			if j != null: add_child(j); jetties[cid] = j
			else: jetties[cid] = null
		elif not near and jetties.has(cid):
			if jetties[cid] != null:
				for body in (jetties[cid] as Node3D).find_children("*", "StaticBody3D", true, false): _bodies.erase(body.get_instance_id())
				jetties[cid].queue_free()
			jetties.erase(cid)
	var cand: Array = []
	for s in sh.ships:
		if s.state == "building" or not sh.ports.has(s.port): continue
		var pose := sh.ship_pose(s)
		var p: Vector2 = pose[0]
		var d := Vector2(v.x, v.z).distance_to(p)
		if d < SHIP_RADIUS: cand.append([d, s])
	cand.sort_custom(func(a, b): return a[0] < b[0])
	var want := {}
	for i in range(mini(cand.size(), MAX_SHIPS)): want[cand[i][1].id] = cand[i][1]
	for sid in ships.keys():
		if not want.has(sid):
			ships[sid].queue_free(); ships.erase(sid)
	for sid in want:
		if not ships.has(sid):
			var m := ShipModel.new(); m.name = "Ship_" + String(sid).replace(".", "_")
			m.build(String(want[sid].type), absi(String(sid).hash()))
			add_child(m)
			ships[sid] = m


## A ship's pose in the world: along its route, easing its heading into and out of the berth.
func ship_transform(s: Dictionary) -> Array:
	var sh := econ.shipping
	var ahead := econ.ship_pending() * (sh.speed(s) if s.state == "sailing" else 0.0)
	var pos: Vector2; var dir: Vector2; var docked: bool = s.state != "sailing" or sh.current_route(s).is_empty()
	if docked:
		var pose := sh.ship_pose(s)
		pos = pose[0]; dir = pose[1]
	else:
		var r := sh.current_route(s)
		var at := ShippingNetwork.point_at(r, float(s.s) + ahead)
		pos = at[0]; dir = at[1]
		# the first and last 60 m: turn from / to lying alongside
		var from_port: String = s.port
		var l := sh.lane(s.lane)
		var to_port: String = (l.to if int(s.leg) == 0 else l.from) if not l.is_empty() else s.port
		if int(s.leg) == 2: to_port = s.get("reposition", [s.port, s.port])[1]
		var along := float(s.s) + ahead
		var left := float(r.length) - along
		if along < 60.0 and sh.ports.has(from_port):
			dir = sh.moor_dir(from_port).slerp(dir, clampf(along / 60.0, 0.0, 1.0))
		elif left < 60.0 and sh.ports.has(to_port):
			dir = sh.moor_dir(to_port).slerp(dir, clampf(left / 60.0, 0.0, 1.0))
	return [Vector3(pos.x, 0.0, pos.y), atan2(-dir.x, -dir.y), docked]


func _update_ships(_delta: float) -> void:
	for sid in ships:
		var s := econ.shipping.ship(sid)
		if s.is_empty(): continue
		var m: ShipModel = ships[sid]
		var xf := ship_transform(s)
		var p: Vector3 = xf[0]
		m.position.x = p.x; m.position.z = p.z
		m.rotation.y = lerp_angle(m.rotation.y, float(xf[1]), 0.2)
		m.docked = xf[2]
		m.speed = 0.0 if m.docked else econ.shipping.speed(s)
		m.set_cargo(econ.shipping.cargo_units(s), econ.shipping.capacity(s))


## A timber jetty from the shore to a T-head alongside the mooring, on piles, with bollards; the
## courier can walk it. None where the mooring is at an existing quay (the core harbour).
func jetty(port: Dictionary) -> Node3D:
	var moor: Vector2 = port.moor; var shore: Vector2 = port.get("shore", moor); var along: Vector2 = port.along
	if moor.distance_to(shore) < 7.0: return null
	var out := (moor - shore).normalized()
	var deck := 1.25
	var head := moor - out * 5.9
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wood := Color("7a5a3a"); var plank := Color("a5825a"); var dark := Color("4a3a2a")
	var body := StaticBody3D.new(); body.name = "JettyBody"; body.collision_layer = 1; body.collision_mask = 0
	var node := Node3D.new(); node.name = "Jetty_" + String(port.id)
	var add_deck := func(c: Vector2, dir: Vector2, length: float, width: float) -> void:
		var yaw := atan2(dir.x, dir.y)
		var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(c.x, deck - 0.15, c.y))
		MeshBits.box(st, xf, Vector3(width, 0.3, length), plank)
		var cs := CollisionShape3D.new(); var shape := BoxShape3D.new(); shape.size = Vector3(width, 0.3, length)
		cs.shape = shape; cs.transform = xf; body.add_child(cs)
		# piles every 4 m down both edges
		var side := dir.orthogonal()
		var k := -length * 0.5
		while k <= length * 0.5 + 0.01:
			for sgn in [-1.0, 1.0]:
				var p: Vector2 = c + dir * k + side * sgn * (width * 0.5 - 0.15)
				MeshBits.cyl(st, Transform3D(Basis(), Vector3(p.x, deck - 2.9, p.y)), 0.16, 5.4, wood, 6)
			k += 4.0
	# the walk from the shore to the head, and the head alongside the ship
	var walk_len := shore.distance_to(head)
	add_deck.call((shore + head) * 0.5 - out * 1.0, out, walk_len + 2.0, 2.8)
	add_deck.call(head, along, 26.0, 4.2)
	# bollards and a rail on the seaward edge's ends
	for t in [-11.0, -4.0, 4.0, 11.0]:
		var p: Vector2 = head + along * t + out * 1.7
		MeshBits.cyl(st, Transform3D(Basis(), Vector3(p.x, deck + 0.3, p.y)), 0.18, 0.6, dark, 8)
	st.generate_normals()
	var mi := MeshInstance3D.new(); mi.name = "Deck"; mi.mesh = st.commit(); mi.material_override = _yard_mat
	node.add_child(mi); node.add_child(body)
	_bodies[body.get_instance_id()] = true
	return node


# ------------------------------------------------------------------ buoys
## Channel buoys along the lanes near the viewer: red to port, green to starboard, in pairs every
## BUOY_SPACING metres, bobbing in place.
func _sync_buoys(v: Vector3) -> void:
	var sh := econ.shipping
	var key := ""
	for l in sh.lanes: key += String(l.id) + String(l.from) + String(l.to)
	if key != _buoy_key:
		_buoy_key = key
		_buoy_points.clear()
		var seen := {}
		for l in sh.lanes:
			var pair := [String(l.from), String(l.to)]; pair.sort()
			if seen.has(str(pair)): continue
			seen[str(pair)] = true
			var r := sh.route(l.from, l.to)
			if r.is_empty(): continue
			var s := BUOY_SPACING * 0.5
			while s < float(r.length) - 150.0:
				var at := ShippingNetwork.point_at(r, s)
				var p: Vector2 = at[0]; var d: Vector2 = at[1]
				var side := d.orthogonal() * 22.0
				for k in [1.0, -1.0]:
					var q: Vector2 = p + side * k
					if sh.navigable(q): _buoy_points.append([Vector3(q.x, 0.0, q.y), k > 0.0])
				s += BUOY_SPACING
	var mm := _buoys.multimesh
	var n := 0
	var clock := Time.get_ticks_msec() * 0.001
	for e in _buoy_points:
		if n >= MAX_BUOYS: break
		var p: Vector3 = e[0]
		if Vector2(p.x - v.x, p.z - v.z).length() > BUOY_RADIUS: continue
		var tilt := Basis(Vector3.RIGHT, sin(clock * 1.3 + p.x) * 0.06) * Basis(Vector3.FORWARD, sin(clock * 1.1 + p.z) * 0.06)
		mm.set_instance_transform(n, Transform3D(tilt, p + Vector3(0, sin(clock * 1.7 + p.x * 0.1) * 0.12 - 0.3, 0)))
		mm.set_instance_color(n, Color("2f8a4a") if e[1] else Color("b8322a"))
		n += 1
	mm.visible_instance_count = n


static func _buoy_mesh() -> ArrayMesh:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var white := Color(1, 1, 1)          # tinted by the instance colour
	MeshBits.cyl(st, Transform3D(Basis(), Vector3(0, 0.3, 0)), 0.7, 1.0, white, 10, 0.55)
	MeshBits.cyl(st, Transform3D(Basis(), Vector3(0, 0.95, 0)), 0.56, 0.3, Color(0.95, 0.95, 0.9), 10)
	MeshBits.cyl(st, Transform3D(Basis(), Vector3(0, 1.6, 0)), 0.1, 1.2, Color(0.3, 0.3, 0.3), 5)
	MeshBits.cone(st, Vector3(0, 2.15, 0), 0.32, 0.55, white, 8)
	st.generate_normals()
	return st.commit()


# ------------------------------------------------------------------ the Mayor map
func set_map(active: bool, colony_id: String, zoom: float) -> void:
	if colony_id != map_colony: _map_dirty = true
	map_active = active; map_colony = colony_id; map_zoom = zoom
	map_root.visible = active


func _update_map() -> void:
	if _map_dirty:
		_map_dirty = false
		_rebuild_static_overlay()
		_rebuild_lanes()
	elif absf(map_zoom - _map_lanes_zoom) > _map_lanes_zoom * 0.15:
		_rebuild_lanes()
	# map labels keep ~a line of text on screen at any zoom (the camera is orthographic)
	var px := map_zoom * 0.0009
	for l in _labels.get_children():
		(l as Label3D).pixel_size = px
		(l as Label3D).position.y = float(l.get_meta("y", 0.0)) + map_zoom * 0.03
	var mm := _ship_markers.multimesh
	var n := 0
	var sc := maxf(map_zoom * 0.0022, 1.2)          # ~30 px on screen at any zoom
	for s in econ.shipping.ships:
		if s.state == "building" or n >= mm.instance_count: continue
		var xf := ship_transform(s)
		var p: Vector3 = xf[0]
		mm.set_instance_transform(n, Transform3D(Basis(Vector3.UP, float(xf[1])).scaled(Vector3.ONE * sc), p + Vector3(0, 4.0, 0)))
		mm.set_instance_color(n, _lane_color(s.lane))
		n += 1
	mm.visible_instance_count = n


func _lane_color(lid: String) -> Color:
	for i in range(econ.shipping.lanes.size()):
		if econ.shipping.lanes[i].id == lid: return LANE_COLORS[i % LANE_COLORS.size()]
	return Color("f1e5ca")


func _rebuild_lanes() -> void:
	_map_lanes_zoom = map_zoom
	for c in _lane_meshes.get_children(): c.queue_free()
	var width := clampf(map_zoom * 0.008, 1.5, 60.0)
	for i in range(econ.shipping.lanes.size()):
		var l: Dictionary = econ.shipping.lanes[i]
		var r := econ.shipping.route(l.from, l.to)
		if r.is_empty(): continue
		var mi := MeshInstance3D.new()
		mi.mesh = _ribbon(r.points, width, 3.0)
		mi.material_override = _overlay_mat(LANE_COLORS[i % LANE_COLORS.size()], false)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_lane_meshes.add_child(mi)


func _rebuild_static_overlay() -> void:
	for c in _static_overlay.get_children(): c.queue_free()
	for c in _labels.get_children(): c.queue_free()
	var im := ImmediateMesh.new()
	var lines := 0
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for cid in econ.towns:
		var t: ColonyTown = econ.towns[cid]
		var label := Label3D.new()
		var state := "colony · %d people · %d%% happy" % [t.colonists.size(), int(t.happiness)] if t.founded else ("charter %d coins" % econ.charter_cost(cid) if t.discovered else "not yet visited")
		label.text = "%s\n%s" % [t.display_name, state]
		label.font_size = 28; label.outline_size = 10
		label.no_depth_test = true; label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		# drawn after the sea and every other transparent surface, so water never cuts the text
		label.render_priority = 100; label.outline_render_priority = 99
		label.modulate = Color("f6ce75") if cid == map_colony else (Color("f1e5ca") if t.founded else Color("c9c0a8"))
		label.outline_modulate = Color("203d39")
		label.position = t.hall; label.set_meta("y", t.hall.y)
		_labels.add_child(label)
		if cid != map_colony: continue
		# the build area
		for k in range(96):
			for s in [k, k + 1]:
				var a: float = TAU * s / 96.0
				var p := Vector2(t.hall.x + cos(a) * EconomyCatalog.build_radius(cid), t.hall.z + sin(a) * EconomyCatalog.build_radius(cid))
				im.surface_set_color(Color("f6ce75")); im.surface_add_vertex(Vector3(p.x, maxf(econ._height(p.x, p.y), 0.0) + 1.5, p.y)); lines += 1
		for b in t.buildings:
			if b.get("virtual", false): continue
			var col: Color = {"house": Color("e7b98e"), "raw": Color("9fc76a"), "processing": Color("5fb3c9"), "storage": Color("f1e5ca"), "port": Color("c792d8")}.get(String(EconomyCatalog.building(b.type).cat), Color.WHITE)
			var pts := ColonyEconomy.site_points(b.type, Vector3(float(b.x), 0, float(b.z)), float(b.yaw))
			var corners := [pts[0], pts[2], pts[8], pts[6]]
			for k in range(4):
				for q in [corners[k], corners[(k + 1) % 4]]:
					im.surface_set_color(col if b.built else col.darkened(0.4)); im.surface_add_vertex(Vector3(q.x, float(b.y) + 1.0, q.y)); lines += 1
	# pirate coves that threaten a lane
	if econ.shipping.pirates.is_valid():
		for camp in econ.shipping.pirates.call():
			var threat := false
			for l in econ.shipping.lanes:
				if camp.id in econ.shipping.lane_threats(l): threat = true
			var label := Label3D.new(); label.text = "Pirate cove: %s%s" % [ShippingNetwork.cove_name(String(camp.id)), "\nraids the lanes" if threat else ""]
			label.font_size = 24; label.outline_size = 8
			label.no_depth_test = true; label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.render_priority = 100; label.outline_render_priority = 99
			label.modulate = Color("e0735f") if threat else Color("c9a08a")
			label.position = camp.pos; label.set_meta("y", camp.pos.y)
			_labels.add_child(label)
	if lines > 0:
		im.surface_end()
		var mi := MeshInstance3D.new(); mi.mesh = im
		var mat := _overlay_mat(Color.WHITE, true)
		mi.material_override = mat
		_static_overlay.add_child(mi)
	else:
		im.clear_surfaces()


static func _overlay_mat(col: Color, vertex: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.vertex_color_use_as_albedo = vertex
	m.vertex_color_is_srgb = true
	m.no_depth_test = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.render_priority = 2
	return m


static func _ribbon(pts: PackedVector2Array, width: float, y: float) -> ArrayMesh:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(pts.size() - 1):
		var a := pts[i]; var b := pts[i + 1]
		var side := (b - a).normalized().orthogonal() * width * 0.5
		var q := [Vector3(a.x - side.x, y, a.y - side.y), Vector3(a.x + side.x, y, a.y + side.y), Vector3(b.x + side.x, y, b.y + side.y), Vector3(b.x - side.x, y, b.y - side.y)]
		for k in [0, 1, 2, 0, 2, 3]: st.add_vertex(q[k])
	return st.commit()


static func _arrow_mesh() -> ArrayMesh:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in [Vector3(0, 0, -9), Vector3(4, 0, 5), Vector3(0, 0, 2), Vector3(0, 0, -9), Vector3(0, 0, 2), Vector3(-4, 0, 5)]:
		st.set_color(Color.WHITE); st.add_vertex(v)
	return st.commit()


## The placement ghost: the building's and the yard's outlines plus a translucent block.
static func ghost_mesh(type: String, ok: bool) -> ArrayMesh:
	var def := EconomyCatalog.building(type)
	var yard := ColonyProps.yard_width(String(def.get("prop", "")))
	var f := ColonyEconomy.footprint(type)
	var col := Color(0.55, 0.85, 0.6, 0.45) if ok else Color(0.9, 0.45, 0.4, 0.45)
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	MeshBits.box(st, Transform3D(Basis(), Vector3(-yard * 0.5, 1.6 * int(def.floors), 0)), Vector3(float(def.w), 3.2 * int(def.floors), float(def.d)), col)
	MeshBits.box(st, Transform3D(Basis(), Vector3(0, 0.1, 0)), Vector3(f.x * 2.0, 0.2, f.y * 2.0), Color(col.r, col.g, col.b, 0.25))
	MeshBits.box(st, Transform3D(Basis(), Vector3(-yard * 0.5, 0.5, float(def.d) * 0.5 + 1.2)), Vector3(1.0, 1.0, 1.0), Color(1, 1, 1, 0.6))
	return st.commit()
