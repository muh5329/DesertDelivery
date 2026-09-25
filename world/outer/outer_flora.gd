class_name OuterFlora
extends Node3D
## Streamed, deterministic wilderness for the outer world, built one tile per frame round the
## camera with a fixed instance budget:
##   - 200 m tiles (7 x 7): trees by biome and altitude (pines and firs in the range, oaks, olives,
##     cypresses and umbrella pines in the lowlands, palms at the oasis, maquis and scrub in the
##     west and the south), boulders, hedgerows and stone walls on the field edges. Near tiles use
##     the real tree models (Quaternius GLBs via WorldKit._tree_parts), the rest cheap card trees;
##   - 64 m tiles (7 x 7) of grass and flower cards.
## Nothing grows on roads, pads (the flatten mask), cliffs or in the water. Far forests are the
## terrain shader's canopy tint. Every tile reseeds its rng from its coordinate, so a tile that is
## unloaded and rebuilt is identical.

const TILE := 200.0
const RADIUS := 3
const NEAR := 64.0
const NEAR_RADIUS := 3
const TREE_GRID := 7.5              # candidate spacing for trees (m)
const MAX_TREES := 700
const FULL_RANGE := 260.0           # real tree models within this distance, cards beyond
const CARD_RANGE := 1250.0

var outer: OuterWorld
var ground: OuterGround
var seed_value := 2026
var loaded: Dictionary = {}
var near_loaded: Dictionary = {}
var pending: Array[Vector2i] = []
var near_pending: Array[Vector2i] = []
var _last := Vector2i(-9999, -9999)
var _last_near := Vector2i(-9999, -9999)
var species: Dictionary = {}        # name -> {full: Array[PropPart], card: Array[PropPart]}
var grass_parts: Dictionary = {}
var rock_parts: Array = []
var desert_rock_parts: Array = []
var oases: Array = []               # [Vector2 centre, radius]
var instance_total := 0
var _clump := FastNoiseLite.new()


func setup(p_outer: OuterWorld, world_seed: int) -> void:
	outer = p_outer; ground = outer.ground; seed_value = world_seed
	name = "OuterFlora"
	for lm: Dictionary in ground.plan.get("landmarks", []):
		if lm.kind == "oasis": oases.append([Vector2(lm.pos[0], lm.pos[2]), float(lm.get("radius", 180.0))])
	_clump.seed = world_seed + 404
	_clump.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_clump.frequency = 1.0 / 90.0
	_clump.fractal_octaves = 2
	_make_species()


func _make_species() -> void:
	species.pine = {"full": [WorldKit._tree_parts("Pine_5", "pine", 1.15), WorldKit._tree_parts("Pine_4", "pine", 1.1), WorldKit._tree_parts("Pine_2", "pine", 1.2)],
		"card": _card_tree("pine_clump", 2.6, 9.0, 0.16, true, Color(0.62, 0.72, 0.52))}
	species.oak = {"full": [WorldKit._tree_parts("TwistedTree_1", "shade", 0.9), WorldKit._tree_parts("TwistedTree_3", "shade", 0.85)],
		"card": _card_tree("broadleaf_clump", 6.0, 6.5, 0.22, false, Color(0.8, 0.86, 0.62))}
	species.olive = {"full": [WorldKit._tree_parts("TwistedTree_2", "olive", 0.55), WorldKit._tree_parts("TwistedTree_3", "olive", 0.5)],
		"card": _card_tree("olive_clump", 4.2, 3.8, 0.16, false, Color(0.85, 0.88, 0.75))}
	species.umbrella = {"full": [WorldKit._tree_parts("TwistedTree_1", "umbrella", 1.1), WorldKit._tree_parts("TwistedTree_2", "umbrella", 1.0)],
		"card": _card_tree("pine_clump", 7.0, 4.5, 0.2, false, Color(0.62, 0.7, 0.5), 7.0)}
	species.cypress = {"full": [_cypress()], "card": [_cypress()]}
	var palm: Array = IslandArt.prop_parts("harbour_palm") if ResourceLoader.exists("res://assets/models/harbour_palm.glb") else []
	species.palm = {"full": [palm], "card": [palm]}
	species.scrub = {"full": [_bush("scrub_clump", 2.2, 1.4)], "card": [_bush("scrub_clump", 2.2, 1.4)]}
	# riparian and oasis growth: oleander (a dark shrub in pink flower) and feathery grey tamarisk
	# along the wadis, tall pale poplars on the river banks
	species.oleander = {"full": [_oleander()], "card": [_oleander()]}
	species.tamarisk = {"full": _card_tree("pine_clump", 3.8, 4.4, 0.12, false, Color(0.78, 0.84, 0.72), 1.3),
		"card": _card_tree("pine_clump", 3.8, 4.4, 0.12, false, Color(0.78, 0.84, 0.72), 1.3)}
	species.poplar = {"full": [_poplar()], "card": [_poplar()]}
	species.understory = {"full": [_bush("scrub_clump", 1.6, 0.9)], "card": [_bush("scrub_clump", 1.6, 0.9)]}
	species.fern = {"full": [_bush("heather_clump", 1.3, 0.7)], "card": [_bush("heather_clump", 1.3, 0.7)]}
	species.vine = {"full": [_vine_row()], "card": [_vine_row()]}
	var am := ArchMaterials.instanced()
	species.log = {"full": [[WorldKit.PropPart.new(ArchModules.mesh(_log_key()), am, Transform3D())]], "card": []}
	for v in range(3):
		species["hay%d" % v] = {"full": [[WorldKit.PropPart.new(ArchModules.mesh(ArchProps.haybale(v)), am, Transform3D())]], "card": []}
	species.fieldwall = {"full": [[WorldKit.PropPart.new(ArchModules.mesh(ArchProps.field_wall()), am, Transform3D())]], "card": []}
	species.maquis = {"full": [_bush("heather_clump", 2.6, 1.6)], "card": [_bush("heather_clump", 2.6, 1.6)]}
	species.hedge = {"full": [_bush("scrub_clump", 3.0, 2.2)], "card": [_bush("scrub_clump", 3.0, 2.2)]}
	grass_parts.grass = _grass("grass_card", 1.3, 0.75)
	grass_parts.dry = _grass("dry_grass_card", 1.3, 0.75)
	grass_parts.dune = _grass("dune_grass_card", 1.4, 0.9)
	grass_parts.flower_y = _grass("flower_card_yellow", 0.9, 0.6)
	grass_parts.flower_p = _grass("flower_card_pink", 0.9, 0.6)
	grass_parts.flower_w = _grass("flower_card_white", 0.9, 0.6)
	var rmat := WorldKit.rock_material("rock024", WorldKit.LIMESTONE_TINT, 0.12)
	# the desert's boulders are the mesas' red-brown sandstone, not the coast's limestone
	var dmat := WorldKit.rock_material("rock024", Color(0.74, 0.52, 0.38), 0.0)
	# the kit's bedded limestone boulders (RockGen, the baked library's LOD1), scaled to the old
	# sphere-rock size (~2 m across at scale 1), not smooth grey blobs
	for i in range(4):
		var r := RockGen.cached({"size": Vector3(4.0, 3.4, 3.6), "seed": 300 + i, "cell": 0.4, "cell_lod1": 1.2,
			"boulder": true, "noise_amp": 0.55, "noise_metres": 2.5, "detail_amp": 0.1, "detail_metres": 0.8,
			"top_cut": 0.0 if i == 3 else 0.78 + 0.03 * i, "top_amp": 0.15, "ground_y": -1.0})
		var mesh: Mesh = r.get("mesh_lod1", null)
		if mesh == null: mesh = _rock_mesh(31 + i)
		rock_parts.append([WorldKit.PropPart.new(mesh, rmat, Transform3D(Basis().scaled(Vector3(0.5, 0.5, 0.5)), Vector3.ZERO))])
		desert_rock_parts.append([WorldKit.PropPart.new(mesh, dmat, Transform3D(Basis().scaled(Vector3(0.5, 0.5, 0.5)), Vector3.ZERO))])


func _card_tree(tex: String, w: float, h: float, trunk_r: float, conifer: bool, tint: Color, trunk_h: float = -1.0) -> Array:
	var parts: Array[WorldKit.PropPart] = []
	var th := trunk_h if trunk_h > 0.0 else (h * 0.3 if conifer else h * 0.45)
	var trunk := CylinderMesh.new(); trunk.top_radius = trunk_r * 0.6; trunk.bottom_radius = trunk_r; trunk.height = th; trunk.radial_segments = 5; trunk.rings = 1
	parts.append(WorldKit.PropPart.new(trunk, Mats.solid(Color(0.36, 0.28, 0.2), 0.95), Transform3D(Basis(), Vector3(0, th * 0.5, 0))))
	var mat := WorldKit._leaf_material(tex, tint)
	if conifer:
		WorldKit._tier(parts, mat, w, h * 0.55, th * 0.4, 3, false)
		WorldKit._tier(parts, mat, w * 0.7, h * 0.45, th * 0.4 + h * 0.4, 3, false, 0.0, 1)
	else:
		WorldKit._tier(parts, mat, w, h - th + 0.8, th - 0.8, 3, true)
	return [parts]


func _cypress() -> Array[WorldKit.PropPart]:
	var parts: Array[WorldKit.PropPart] = []
	var trunk := CylinderMesh.new(); trunk.top_radius = 0.10; trunk.bottom_radius = 0.16; trunk.height = 1.4; trunk.radial_segments = 5
	parts.append(WorldKit.PropPart.new(trunk, Mats.solid(WorldKit.WOOD, 0.9), Transform3D(Basis(), Vector3(0, 0.7, 0))))
	var mat := WorldKit._leaf_material("cypress_clump")
	WorldKit._tier(parts, mat, 1.7, 4.2, 0.9, 3, false)
	WorldKit._tier(parts, mat, 1.5, 4.0, 3.6, 3, false, 0.0, 1)
	WorldKit._tier(parts, mat, 1.0, 3.2, 6.4, 3, true, 0.0, 2)
	return parts


func _oleander() -> Array[WorldKit.PropPart]:
	var parts: Array[WorldKit.PropPart] = []
	WorldKit._tier(parts, WorldKit._leaf_material("scrub_clump", Color(0.72, 0.85, 0.6)), 2.8, 2.2, -0.1, 3, true, 0.15)
	WorldKit._tier(parts, WorldKit._leaf_material("flower_card_pink"), 2.4, 1.6, 0.55, 2, false, 0.0, 1)
	return parts


func _poplar() -> Array[WorldKit.PropPart]:
	var parts: Array[WorldKit.PropPart] = []
	var trunk := CylinderMesh.new(); trunk.top_radius = 0.1; trunk.bottom_radius = 0.2; trunk.height = 3.0; trunk.radial_segments = 5
	parts.append(WorldKit.PropPart.new(trunk, Mats.solid(Color(0.62, 0.6, 0.55), 0.9), Transform3D(Basis(), Vector3(0, 1.5, 0))))
	var mat := WorldKit._leaf_material("broadleaf_clump", Color(0.86, 0.95, 0.66))
	WorldKit._tier(parts, mat, 2.6, 5.0, 1.8, 3, false)
	WorldKit._tier(parts, mat, 2.2, 5.0, 5.8, 3, false, 0.0, 1)
	WorldKit._tier(parts, mat, 1.4, 3.6, 9.8, 3, true, 0.0, 2)
	return parts


## A vineyard row: an 8 m strip of vine foliage on its wires (one card each side).
func _vine_row() -> Array[WorldKit.PropPart]:
	var parts: Array[WorldKit.PropPart] = []
	var mat := WorldKit._leaf_material("scrub_clump", Color(0.8, 0.95, 0.55))
	parts.append(WorldKit.PropPart.new(WorldKit._card_mesh(8.0, 1.25, true), mat, Transform3D(Basis(), Vector3(0, 0.1, 0))))
	parts.append(WorldKit.PropPart.new(WorldKit._card_mesh(8.0, 1.1, true), mat, Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0.15, 0.05))))
	return parts


## A fallen trunk: bark, a pale broken end, a few stubs.
static func _log_key() -> String:
	var key := "p_log"
	if ArchModules.has(key): return key
	var m := ArchMesh.new(); m.module = true
	m.layer = float(ArchMaterials.TIMBER); m.tint = Color(0.42, 0.34, 0.27); m.flag = 0.0
	var keep := m.xf
	m.xf = Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(3.0, 0.32, 0))
	m.cylinder(Vector3.ZERO, 0.34, 0.26, 6.0, 8, false, false)
	m.tint = Color(0.8, 0.7, 0.55)
	m.cylinder(Vector3(0, 6.0, 0), 0.26, 0.26, 0.02, 8, true, false)
	m.cylinder(Vector3(0, 0, 0), 0.34, 0.34, 0.02, 8, false, true)
	m.xf = keep
	m.tint = Color(0.42, 0.34, 0.27)
	m.rbox(Vector3(0.8, 0.6, 0.2), Vector3(0.12, 0.7, 0.12), Basis(Vector3.BACK, 0.5))
	m.rbox(Vector3(-1.6, 0.55, -0.2), Vector3(0.1, 0.6, 0.1), Basis(Vector3.RIGHT, 0.6))
	ArchModules._cache[key] = m.commit()
	ArchModules.shadows[key] = true
	ArchModules.details[key] = true
	return key


func _bush(tex: String, w: float, h: float) -> Array[WorldKit.PropPart]:
	var parts: Array[WorldKit.PropPart] = []
	WorldKit._tier(parts, WorldKit._leaf_material(tex), w, h, -0.1, 3, true, 0.2)
	return parts


func _grass(tex: String, w: float, h: float) -> Array[WorldKit.PropPart]:
	var parts: Array[WorldKit.PropPart] = []
	WorldKit._tier(parts, WorldKit._leaf_material(tex), w, h, -0.05, 2, false)
	return parts


func _rock_mesh(seed_v: int) -> ArrayMesh:
	var s := SphereMesh.new(); s.radius = 1.0; s.height = 1.6; s.radial_segments = 9; s.rings = 5
	var arr := s.get_mesh_arrays()
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var n := FastNoiseLite.new(); n.seed = seed_v; n.frequency = 0.9
	for i in range(v.size()):
		var p := v[i]
		v[i] = p * (1.0 + 0.28 * n.get_noise_3dv(p)) * Vector3(1.3, 0.8, 1.0)
	arr[Mesh.ARRAY_VERTEX] = v
	var st := SurfaceTool.new(); st.create_from_arrays(arr); st.generate_normals()
	return st.commit()


# ---------------------------------------------------------------- streaming
func _view_pos() -> Vector3:
	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp else null
	if cam: return cam.global_position
	return outer.focus.global_position if outer.focus else Vector3.ZERO


func _ready() -> void:
	# purely visual streaming: a headless run (tests, tools) builds on demand through flush()
	if DisplayServer.get_name() == "headless": set_process(false)


func _process(_delta: float) -> void:
	_update_rings()
	# m-5: the placement (every height, slope, splat and noise lookup: 15-35 ms a tile) runs on a
	# worker, one tile at a time; this thread only makes the MultiMeshes of a finished tile
	if _job >= 0:
		if not WorkerThreadPool.is_task_completed(_job): return
		_finish_job()
		return
	if not near_pending.is_empty(): _start(near_pending.pop_front(), true)
	elif not pending.is_empty(): _start(pending.pop_front(), false)


## Unload the tiles out of range and list the missing ones, nearest first.
func _update_rings() -> void:
	var p := _view_pos()
	var t := Vector2i(floori(p.x / TILE), floori(p.z / TILE))
	if t != _last:
		_last = t
		for k: Vector2i in loaded.keys():
			if maxi(absi(k.x - t.x), absi(k.y - t.y)) > RADIUS + 1:
				loaded[k].queue_free(); loaded.erase(k)
		pending = _ring(t, RADIUS, loaded, TILE)
	var tn := Vector2i(floori(p.x / NEAR), floori(p.z / NEAR))
	if tn != _last_near:
		_last_near = tn
		for k: Vector2i in near_loaded.keys():
			if maxi(absi(k.x - tn.x), absi(k.y - tn.y)) > NEAR_RADIUS + 1:
				near_loaded[k].queue_free(); near_loaded.erase(k)
		near_pending = _ring(tn, NEAR_RADIUS, near_loaded, NEAR)


## Wait for the tile being planned and emit it if it is still wanted.
func _finish_job() -> void:
	if _job < 0: return
	WorkerThreadPool.wait_for_task_completion(_job)
	_job = -1
	var t0 := Time.get_ticks_usec()
	if _job_near:
		if not near_loaded.has(_job_key) and _in_range(_job_key, _last_near, NEAR_RADIUS + 1): _emit_near(_job_key, _job_out)
	elif not loaded.has(_job_key) and _in_range(_job_key, _last, RADIUS + 1): _emit_tile(_job_key, _job_out)
	last_build_ms = (Time.get_ticks_usec() - t0) / 1000.0
	max_build_ms = maxf(max_build_ms, last_build_ms)
	_job_out = {}


var _job := -1
var _job_key := Vector2i.ZERO
var _job_near := false
var _job_out: Dictionary = {}
var last_build_ms := 0.0


func _start(k: Vector2i, near: bool) -> void:
	_job_key = k; _job_near = near
	_job = WorkerThreadPool.add_task(func(): _job_out = _plan_near(k) if near else _plan_tile(k), false, "flora tile")


static func _in_range(k: Vector2i, c: Vector2i, r: int) -> bool:
	return maxi(absi(k.x - c.x), absi(k.y - c.y)) <= r


## Wait for a tile being planned on the worker (flush, shutdown).
func wait() -> void:
	if _job >= 0:
		WorkerThreadPool.wait_for_task_completion(_job)
		_job = -1
		_job_out = {}


func _exit_tree() -> void:
	wait()


func _ring(t: Vector2i, r: int, have: Dictionary, size: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var k := t + Vector2i(dx, dz)
			if have.has(k): continue
			var cx := (k.x + 0.5) * size; var cz := (k.y + 0.5) * size
			if absf(cx) > 12500.0 or absf(cz) > 12500.0: continue
			if maxf(absf(cx), absf(cz)) < 1300.0 - size: continue       # the core and its lagoon
			out.append(k)
	out.sort_custom(func(a: Vector2i, b: Vector2i): return (a - t).length_squared() < (b - t).length_squared())
	return out


## Build everything round the camera now (render tools, tests).
func flush() -> void:
	_finish_job()
	_update_rings()
	while not near_pending.is_empty(): _build_near(near_pending.pop_front())
	while not pending.is_empty(): build_tile(pending.pop_front())


func _rng_for(k: Vector2i, salt: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash("%d:%d:%d:%d" % [seed_value, k.x, k.y, salt])
	return r


## Can something grow at (x, z)? Returns the ground height, or NAN.
func _site(x: float, z: float, max_slope: float) -> float:
	if maxf(absf(x), absf(z)) < 1200.0: return NAN
	if ground.flatten_at(x, z) > 0.2: return NAN
	if outer.rivers != null and outer.rivers.in_channel(x, z): return NAN
	var h := ground.data_height(x, z)
	if h < 1.6: return NAN
	var e := 3.0
	var dx := ground.data_height(x + e, z) - ground.data_height(x - e, z)
	var dz := ground.data_height(x, z + e) - ground.data_height(x, z - e)
	if sqrt(dx * dx + dz * dz) / (2.0 * e) > max_slope: return NAN
	return ground.height_at(x, z)


func _pick_species(x: float, z: float, h: float, biome: int, dry: float, r: float) -> String:
	for o in oases:
		if Vector2(x, z).distance_to(o[0]) < o[1]: return "palm" if r < 0.72 else "olive"
	var ft := ground.feat_at(x, z)
	if ft.g > 0.3: return "palm" if r < 0.6 else "olive"
	if ft.r > 0.12 and (biome == Terrain.Biome.BADLANDS or biome == Terrain.Biome.DUNES):
		return "oleander" if r < 0.55 else "tamarisk"
	# gravel bars and sand on a northern river bank: poplars
	if biome != Terrain.Biome.BADLANDS and ground.splat_at(x, z).g > 0.3 and h > 4.0 and r < 0.6: return "poplar"
	match biome:
		Terrain.Biome.LIMESTONE: return "pine" if h > 400.0 else "umbrella"
		Terrain.Biome.MOOR:
			if z < -2500.0: return "pine"
			return "maquis" if r < 0.6 else "umbrella"
		Terrain.Biome.BADLANDS, Terrain.Biome.DUNES:
			return "scrub" if r < 0.8 else "olive"
		Terrain.Biome.BEACH: return "umbrella"
		Terrain.Biome.FARM: return "olive" if r < 0.35 else ("oak" if r < 0.8 else "cypress")
	# FOREST: conifers up in the range, broadleaf and olives below, cypress here and there
	if h > 300.0 or z < -3500.0: return "pine" if r < 0.85 else "oak"
	if dry > 0.55: return "olive" if r < 0.55 else ("umbrella" if r < 0.8 else "cypress")
	return "oak" if r < 0.55 else ("umbrella" if r < 0.75 else ("olive" if r < 0.9 else "cypress"))


var max_build_ms := 0.0


func build_tile(k: Vector2i) -> void:
	var t0 := Time.get_ticks_usec()
	_build_tile_impl(k)
	max_build_ms = maxf(max_build_ms, (Time.get_ticks_usec() - t0) / 1000.0)


func _build_tile_impl(k: Vector2i) -> void:
	_emit_tile(k, _plan_tile(k))


## Where everything on a wilderness tile goes (pure: no nodes, safe on a worker thread).
func _plan_tile(k: Vector2i) -> Dictionary:
	var origin := Vector3(k.x * TILE, 0, k.y * TILE)
	var rng := _rng_for(k, 1)
	var groups: Dictionary = {}          # species -> [xforms, colors]
	var rocks: Array = [[], []]
	var n := int(TILE / TREE_GRID)
	var count := 0
	var extras := 0
	for j in range(n):
		for i in range(n):
			var x := k.x * TILE + (i + rng.randf()) * TREE_GRID
			var z := k.y * TILE + (j + rng.randf()) * TREE_GRID
			var roll := rng.randf(); var r2 := rng.randf(); var sc := rng.randf_range(0.8, 1.3); var yaw := rng.randf() * TAU
			var r3 := rng.randf(); var r4 := rng.randf()
			var dens := ground.forest_at(x, z)
			# forests are not an even carpet: dense stands, glades and edges (a ~90 m clump field)
			var clump := _clump.get_noise_2d(x, z) * 0.5 + 0.5
			dens *= 0.45 + 1.1 * clump
			# the understory and the forest floor: shrubs and ferns under the trees, fallen trunks
			if dens > 0.45 and extras < 520 and r3 < (dens - 0.35) * 0.9:
				var hu := _site(x + 2.5, z - 1.5, 0.8)
				if not is_nan(hu):
					var usp := "fern" if int(x - z) % 3 == 0 and hu > 250.0 else "understory"
					if r4 < 0.03 * dens and ground.biome_at(x, z) == Terrain.Biome.FOREST: usp = "log"
					if not groups.has(usp): groups[usp] = [[] as Array[Transform3D], [] as Array[Color]]
					var us := rng.randf_range(0.7, 1.25)
					var ub := Basis(Vector3.UP, r4 * TAU * 7.0)
					if usp == "log": ub = ub * Basis(Vector3.RIGHT, rng.randf_range(-0.08, 0.08))
					groups[usp][0].append(Transform3D(ub.scaled(Vector3(us, us, us)), Vector3(x + 2.5, hu - (0.15 if usp == "log" else 0.05), z - 1.5) - origin))
					groups[usp][1].append(Color(0.9 + r4 * 0.2, 0.95, 0.8))
					extras += 1
			var base_chance := 0.012
			var b0 := ground.biome_at(x, z)
			if b0 == Terrain.Biome.BADLANDS or b0 == Terrain.Biome.DUNES: base_chance = 0.05
			elif b0 == Terrain.Biome.MOOR: base_chance = 0.03
			if roll > dens * 0.55 + base_chance: continue
			var h := _site(x, z, 0.75)
			if is_nan(h): continue
			var biome := ground.biome_at(x, z)
			if biome == Terrain.Biome.TOWN or biome == Terrain.Biome.SEA or biome == Terrain.Biome.LAKE: continue
			var sp := _pick_species(x, z, h, biome, ground.dryness_at(x, z), r2)
			if sp == "pine" and h > 1150.0: continue
			if not groups.has(sp): groups[sp] = [[] as Array[Transform3D], [] as Array[Color]]
			var s := sc * (0.7 if h > 950.0 else 1.0)
			groups[sp][0].append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s * rng.randf_range(0.9, 1.15), s)), Vector3(x, h - 0.1, z) - origin))
			var v := rng.randf_range(-0.1, 0.1)
			groups[sp][1].append(Color(1.0 + v, 1.0 + v * 0.8, 1.0 + v * 0.5))
			count += 1
			if count >= MAX_TREES: break
		if count >= MAX_TREES: break
	# boulders: more on steep, rocky and high ground
	for i in range(70):
		var x := k.x * TILE + rng.randf() * TILE; var z := k.y * TILE + rng.randf() * TILE
		var sp := ground.splat_at(x, z)
		var s := rng.randf_range(0.4, 2.2)
		if rng.randf() > 0.15 + sp.r * 0.8: continue
		var h := _site(x, z, 1.4)
		if is_nan(h): continue
		rocks[0].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).rotated(Vector3.RIGHT, rng.randf_range(-0.3, 0.3)).scaled(Vector3(s, s * rng.randf_range(0.5, 1.0), s)), Vector3(x, h - s * 0.3, z) - origin))
		rocks[1].append(Color(1, 1, 1))
	# scree and boulders under the cliffs and in the forests
	for i in range(40):
		var x := k.x * TILE + rng.randf() * TILE; var z := k.y * TILE + rng.randf() * TILE
		var f := ground.forest_at(x, z)
		var s := rng.randf_range(0.3, 1.4)
		if rng.randf() > f * 0.35: continue
		var h := _site(x, z, 1.1)
		if is_nan(h): continue
		rocks[0].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.45, 0.8), s)), Vector3(x, h - s * 0.35, z) - origin))
		rocks[1].append(Color(1, 1, 1))
	_hedges(k, origin, groups, rng)
	_fields(k, origin, groups, rng)
	var cb := ground.biome_at(k.x * TILE + TILE * 0.5, k.y * TILE + TILE * 0.5)
	return {"groups": groups, "rocks": rocks, "cb": cb}


func _emit_tile(k: Vector2i, plan: Dictionary) -> void:
	var node := Node3D.new(); node.name = "Wild_%d_%d" % [k.x, k.y]
	node.position = Vector3(k.x * TILE, 0, k.y * TILE)
	add_child(node); loaded[k] = node
	var groups: Dictionary = plan.groups
	var rocks: Array = plan.rocks
	for sp in groups:
		var set: Dictionary = species[sp]
		var xf: Array = groups[sp][0]; var cl: Array = groups[sp][1]
		var variants: Array = set.full
		var buckets: Array = []
		for v in range(variants.size()): buckets.append([[] as Array[Transform3D], [] as Array[Color]])
		for i in range(xf.size()):
			var b: int = i % variants.size()
			buckets[b][0].append(xf[i]); buckets[b][1].append(cl[i])
		var is_tree: bool = sp in ["pine", "oak", "olive", "umbrella", "tamarisk"]
		for v in range(variants.size()):
			if buckets[v][0].is_empty(): continue
			_emit(node, variants[v], buckets[v][0], buckets[v][1], 0.0, FULL_RANGE if is_tree else 420.0, is_tree)
			if is_tree: _emit(node, set.card[0], buckets[v][0], buckets[v][1], FULL_RANGE, CARD_RANGE, false)
		instance_total += xf.size()
	var cb: int = plan.cb
	var rparts: Array = desert_rock_parts if (cb == Terrain.Biome.BADLANDS or cb == Terrain.Biome.DUNES) else rock_parts
	for v in range(rparts.size()):
		var xs: Array[Transform3D] = []; var cs: Array[Color] = []
		for i in range(v, rocks[0].size(), rparts.size()):
			xs.append(rocks[0][i]); cs.append(rocks[1][i])
		if not xs.is_empty(): _emit(node, rparts[v], xs, cs, 0.0, 600.0, true)
	instance_total += rocks[0].size()


## Hedgerows on the farmland parcel edges (the same parcels outer_terrain.gdshader paints).
func _hedges(k: Vector2i, origin: Vector3, groups: Dictionary, rng: RandomNumberGenerator) -> void:
	var x0 := k.x * TILE; var z0 := k.y * TILE
	if ground.splat_at(x0 + TILE * 0.5, z0 + TILE * 0.5).b < 0.2 and ground.splat_at(x0, z0).b < 0.2: return
	# the hill and island country fences its fields with dry-stone walls, the plains with hedges
	var walls := false
	var c := Vector2(x0 + TILE * 0.5, z0 + TILE * 0.5)
	if _vine_centres.is_empty(): _fields_centres()
	var best := 1e9
	for vc in _vine_centres:
		var d: float = c.distance_to(vc[0])
		if d < best: best = d; walls = vc[1] in ["valdoro", "isola", "sarmada"]
	if walls and best < 3500.0:
		_walls(k, origin, groups, rng)
		return
	for j in range(0, int(TILE / 3.0)):
		for i in range(0, int(TILE / 3.0)):
			var x := x0 + i * 3.0 + 1.5; var z := z0 + j * 3.0 + 1.5
			var f := OuterFlora.field_at(Vector2(x, z))
			if f.y > 1.6: continue
			if ground.splat_at(x, z).b < 0.45: continue
			if fmod(f.w * 7.0, 1.0) < 0.35: continue          # some parcel edges are open
			var h := _site(x, z, 0.4)
			if is_nan(h): continue
			if not groups.has("hedge"): groups["hedge"] = [[] as Array[Transform3D], [] as Array[Color]]
			var s := rng.randf_range(0.8, 1.3)
			groups.hedge[0].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.4), s)), Vector3(x, h - 0.1, z) - origin))
			groups.hedge[1].append(Color(0.8, 0.95, 0.7))


## What the parcels grow: vine rows (crop 3) near the vineyard towns, hay bales on the mown parcels
## (crop 5), olive orchards in grid rows (crop 4) round the towns and hamlets.
var _vine_centres: Array = []


func _fields(k: Vector2i, origin: Vector3, groups: Dictionary, rng: RandomNumberGenerator) -> void:
	var x0 := k.x * TILE; var z0 := k.y * TILE
	var c := Vector2(x0 + TILE * 0.5, z0 + TILE * 0.5)
	if ground.splat_at(c.x, c.y).b < 0.2 and ground.splat_at(x0, z0).b < 0.2 and ground.splat_at(x0 + TILE, z0 + TILE).b < 0.2: return
	if _vine_centres.is_empty(): _fields_centres()
	var near_vines := false; var near_town := false
	for vc in _vine_centres:
		var d: float = c.distance_to(vc[0])
		if d < float(vc[3]) + 60.0: return          # no vineyard in the middle of a town
		if d < vc[2] and vc[1] in ["campo", "valdoro", "puerto"]: near_vines = true
		if d < vc[2] * 0.7: near_town = true
	var added := 0
	# rows run along the parcel's furrows: the district's parcel frame angle (parcel_frame)
	var ang: float = parcel_frame(c)[2]
	var row_dir := Vector2(cos(-ang), sin(-ang))
	var row_yaw := atan2(-row_dir.y, row_dir.x)
	var perp_dir := Vector2(-row_dir.y, row_dir.x)
	for j in range(-58, 59):
		for i in range(-19, 20):
			var q := c + perp_dir * (j * 2.6) + row_dir * (i * 8.0)
			if q.x < x0 or q.y < z0 or q.x >= x0 + TILE or q.y >= z0 + TILE: continue
			var x := q.x; var z := q.y
			var f := OuterFlora.field_at(Vector2(x, z))
			if f.y < 4.0 or ground.splat_at(x, z).b < 0.5: continue
			if ground.biome_at(x, z) == Terrain.Biome.TOWN: continue
			var crop := int(f.x)
			if crop == 3 and near_vines and added < 2400:
				var h := _site(x, z, 0.3)
				if is_nan(h): continue
				if not groups.has("vine"): groups["vine"] = [[] as Array[Transform3D], [] as Array[Color]]
				groups.vine[0].append(Transform3D(Basis(Vector3.UP, row_yaw), Vector3(x, h - 0.05, z) - origin))
				groups.vine[1].append(Color(0.95 + rng.randf() * 0.1, 1.0, 0.85))
				added += 1
			elif crop == 5 and posmod(i * 3 + j * 7, 11) == 0 and added < 2400:
				var h2 := _site(x, z, 0.25)
				if is_nan(h2): continue
				var v := int(f.w * 3.0) % 3
				var key := "hay%d" % v
				if not groups.has(key): groups[key] = [[] as Array[Transform3D], [] as Array[Color]]
				groups[key][0].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(x, h2 - 0.05, z) - origin))
				groups[key][1].append(Color(1, 1, 1))
				added += 1
			elif crop == 4 and near_town and posmod(j, 3) == 0 and added < 2400:
				var h3 := _site(x, z, 0.3)
				if is_nan(h3): continue
				if not groups.has("olive"): groups["olive"] = [[] as Array[Transform3D], [] as Array[Color]]
				var s := rng.randf_range(0.8, 1.0)
				groups.olive[0].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), Vector3(x, h3 - 0.1, z) - origin))
				groups.olive[1].append(Color(1.0, 1.0, 0.95))
				added += 1


func _fields_centres() -> void:
	for group in ["towns", "hamlets"]:
		for t: Dictionary in ground.plan.get(group, []):
			_vine_centres.append([Vector2(t.center[0], t.center[1]), t.style, 2200.0 if group == "towns" else 900.0, float(t.radius)])


## Dry-stone walls along the parcel edges: 3 m segments laid along whichever edge is nearer.
func _walls(k: Vector2i, origin: Vector3, groups: Dictionary, rng: RandomNumberGenerator) -> void:
	var x0 := k.x * TILE; var z0 := k.y * TILE
	for j in range(0, int(TILE / 3.0)):
		for i in range(0, int(TILE / 3.0)):
			var x := x0 + i * 3.0 + 1.5; var z := z0 + j * 3.0 + 1.5
			var f := OuterFlora.field_at(Vector2(x, z))
			if f.y > 1.5: continue
			if ground.splat_at(x, z).b < 0.45: continue
			if fmod(f.w * 7.0, 1.0) < 0.3: continue
			var h := _site(x, z, 0.45)
			if is_nan(h): continue
			var along_x := OuterFlora.field_edge_along_x(Vector2(x, z))
			var fa: float = parcel_frame(Vector2(x, z))[2]
			var ax := Vector2(cos(-fa), sin(-fa)); var ay := Vector2(-ax.y, ax.x)
			var d := ax if along_x else ay
			if not groups.has("fieldwall"): groups["fieldwall"] = [[] as Array[Transform3D], [] as Array[Color]]
			groups.fieldwall[0].append(Transform3D(Basis(Vector3.UP, atan2(-d.y, d.x)).scaled(Vector3(1.0, rng.randf_range(0.85, 1.15), 1.0)), Vector3(x, h - 0.12, z) - origin))
			groups.fieldwall[1].append(Color(1, 1, 1))


## The farmland's parcel frame at w (outer_terrain.gdshader `parcel_frame`, P-2: per-district
## furrow angle and row depth, per-row parcel length): [p (frame coordinates), cell size, angle].
static func parcel_frame(w: Vector2) -> Array:
	var dq := w / 1300.0 + Vector2(sin(w.y * 0.0009), sin(w.x * 0.0011)) * 0.3
	var did := Vector2(floorf(dq.x), floorf(dq.y))
	var ang := 0.35 + (_hash21(did * 13.0 + Vector2(5.0, 5.0)) - 0.5) * 1.4
	var p := _rot(w, ang) + Vector2(sin(w.y * 0.0021) * 40.0, sin(w.x * 0.0017) * 35.0)
	var rh := lerpf(80.0, 150.0, _hash21(did * 13.0 + Vector2(9.0, 9.0)))
	var row := floorf(p.y / rh)
	var len := lerpf(110.0, 280.0, _hash21(Vector2(row, did.x * 31.0 + did.y * 7.0 + 3.0)))
	p.x += _hash21(Vector2(row, 17.0)) * len
	return [p, Vector2(len, rh), ang]


## Does the nearest parcel edge at w run along the parcel frame's x axis (true) or its y axis?
static func field_edge_along_x(w: Vector2) -> bool:
	var fr := parcel_frame(w)
	var p: Vector2 = fr[0]; var cell: Vector2 = fr[1]
	var fx := p.x / cell.x - floorf(p.x / cell.x); var fy := p.y / cell.y - floorf(p.y / cell.y)
	return minf(fy, 1.0 - fy) * cell.y < minf(fx, 1.0 - fx) * cell.x


## The parcel pattern of outer_terrain.gdshader `fields()`: (crop, distance to the parcel edge,
## furrow, random) - kept in step with the shader.
static func field_at(w: Vector2) -> Vector4:
	var fr := parcel_frame(w)
	var p: Vector2 = fr[0]; var cell: Vector2 = fr[1]
	var id := Vector2(floorf(p.x / cell.x), floorf(p.y / cell.y))
	var f := Vector2(p.x / cell.x - id.x, p.y / cell.y - id.y)
	var crop := floorf(_hash21(id) * 6.0)
	var e := Vector2(minf(f.x, 1.0 - f.x) * cell.x, minf(f.y, 1.0 - f.y) * cell.y)
	return Vector4(crop, minf(e.x, e.y), 0.0, _hash21(id + Vector2(7.0, 7.0)))


static func _rot(p: Vector2, a: float) -> Vector2:
	return Vector2(cos(a) * p.x - sin(a) * p.y, sin(a) * p.x + cos(a) * p.y)


static func _hash21(p: Vector2) -> float:
	var qx := (int(p.x) + 100000) & 0xffffffff; var qy := (int(p.y) + 100000) & 0xffffffff
	var h := (qx * 374761393 + qy * 668265263) & 0xffffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0xffffffff
	return float((h ^ (h >> 16)) & 0xffff) / 65535.0


func _build_near(k: Vector2i) -> void:
	_emit_near(k, _plan_near(k))


func _plan_near(k: Vector2i) -> Dictionary:
	var origin := Vector3(k.x * NEAR, 0, k.y * NEAR)
	var rng := _rng_for(k, 2)
	var groups: Dictionary = {}
	for i in range(900):
		var x := k.x * NEAR + rng.randf() * NEAR; var z := k.y * NEAR + rng.randf() * NEAR
		var r := rng.randf(); var s := rng.randf_range(0.7, 1.35); var yaw := rng.randf() * TAU
		var biome := ground.biome_at(x, z)
		var sp := ground.splat_at(x, z)
		var dens := 0.55
		var kind := "grass"
		match biome:
			Terrain.Biome.BADLANDS: dens = 0.12; kind = "dry"
			Terrain.Biome.DUNES, Terrain.Biome.BEACH: dens = 0.1; kind = "dune"
			Terrain.Biome.LIMESTONE: dens = 0.15; kind = "dry"
			Terrain.Biome.MOOR: dens = 0.45; kind = "grass" if r < 0.6 else "dry"
			Terrain.Biome.FARM: dens = 0.3
			Terrain.Biome.TOWN, Terrain.Biome.SEA, Terrain.Biome.LAKE: continue
		if ground.dryness_at(x, z) > 0.6 and kind == "grass": kind = "dry"
		dens *= (1.0 - sp.r) * (1.0 - sp.a)
		if r > dens: continue
		var h := _site(x, z, 0.8)
		if is_nan(h): continue
		# flowers: a sprinkle in the lowland grass, whole drifts on the alpine meadows (clumped by
		# the same glade noise the forests use)
		var fl := 0.07
		if h > 600.0 and biome == Terrain.Biome.MOOR and ground.forest_at(x, z) < 0.3:
			fl = 0.18 + 0.3 * smoothstep(0.45, 0.8, _clump.get_noise_2d(x * 3.0, z * 3.0) * 0.5 + 0.5)
		if kind == "grass" and rng.randf() < fl: kind = ["flower_y", "flower_p", "flower_w"][rng.randi_range(0, 2)]
		if not groups.has(kind): groups[kind] = [[] as Array[Transform3D], [] as Array[Color]]
		groups[kind][0].append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s * rng.randf_range(0.8, 1.25), s)), Vector3(x, h - 0.05, z) - origin))
		var v := rng.randf_range(-0.12, 0.12)
		groups[kind][1].append(Color(0.9 + v, 0.92 + v * 0.8, 0.75 + v * 0.5))
	return {"groups": groups}


func _emit_near(k: Vector2i, plan: Dictionary) -> void:
	var node := Node3D.new(); node.name = "Grass_%d_%d" % [k.x, k.y]
	node.position = Vector3(k.x * NEAR, 0, k.y * NEAR)
	add_child(node); near_loaded[k] = node
	var groups: Dictionary = plan.groups
	for kind in groups:
		_emit(node, grass_parts[kind], groups[kind][0], groups[kind][1], 0.0, 150.0, false)
		instance_total += groups[kind][0].size()


func _emit(node: Node3D, parts: Array, xforms: Array, colors: Array, begin: float, end: float, shadows: bool) -> void:
	if xforms.is_empty() or parts.is_empty(): return
	for part: WorldKit.PropPart in parts:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D; mm.use_colors = true
		mm.mesh = part.mesh; mm.instance_count = xforms.size()
		for i in range(xforms.size()):
			mm.set_instance_transform(i, (xforms[i] as Transform3D) * part.xform)
			mm.set_instance_color(i, colors[i])
		var mmi := MultiMeshInstance3D.new(); mmi.multimesh = mm; mmi.material_override = part.mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if begin > 0.0:
			mmi.visibility_range_begin = begin; mmi.visibility_range_begin_margin = 30.0
		mmi.visibility_range_end = end; mmi.visibility_range_end_margin = 40.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		node.add_child(mmi)


func stats() -> Dictionary:
	var instances := 0; var views := 0
	for dict in [loaded, near_loaded]:
		for node: Node3D in dict.values():
			for v in node.get_children():
				if v is MultiMeshInstance3D: instances += v.multimesh.instance_count; views += 1
	return {"tiles": loaded.size(), "near_tiles": near_loaded.size(), "pending": pending.size() + near_pending.size(), "instances": instances, "views": views,
		"max_tiles": (2 * RADIUS + 3) * (2 * RADIUS + 3), "max_instances": (2 * RADIUS + 3) * (2 * RADIUS + 3) * (MAX_TREES * 2 + 70 + 40 + 520 + 2400 + 4500) + (2 * NEAR_RADIUS + 3) * (2 * NEAR_RADIUS + 3) * 900 * 2}
