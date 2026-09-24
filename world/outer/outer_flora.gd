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
var oases: Array = []               # [Vector2 centre, radius]
var instance_total := 0


func setup(p_outer: OuterWorld, world_seed: int) -> void:
	outer = p_outer; ground = outer.ground; seed_value = world_seed
	name = "OuterFlora"
	for lm: Dictionary in ground.plan.get("landmarks", []):
		if lm.kind == "oasis": oases.append([Vector2(lm.pos[0], lm.pos[2]), float(lm.get("radius", 180.0))])
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
	species.maquis = {"full": [_bush("heather_clump", 2.6, 1.6)], "card": [_bush("heather_clump", 2.6, 1.6)]}
	species.hedge = {"full": [_bush("scrub_clump", 3.0, 2.2)], "card": [_bush("scrub_clump", 3.0, 2.2)]}
	grass_parts.grass = _grass("grass_card", 1.3, 0.75)
	grass_parts.dry = _grass("dry_grass_card", 1.3, 0.75)
	grass_parts.dune = _grass("dune_grass_card", 1.4, 0.9)
	grass_parts.flower_y = _grass("flower_card_yellow", 0.9, 0.6)
	grass_parts.flower_p = _grass("flower_card_pink", 0.9, 0.6)
	grass_parts.flower_w = _grass("flower_card_white", 0.9, 0.6)
	var rmat := WorldKit.rock_material("rock024", WorldKit.LIMESTONE_TINT, 0.12)
	for i in range(3):
		rock_parts.append([WorldKit.PropPart.new(_rock_mesh(31 + i), rmat, Transform3D())])


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
	if not near_pending.is_empty(): _build_near(near_pending.pop_front())
	elif not pending.is_empty(): build_tile(pending.pop_front())


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
	_process(0.0)
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
	var h := ground.data_height(x, z)
	if h < 1.6: return NAN
	var e := 3.0
	var dx := ground.data_height(x + e, z) - ground.data_height(x - e, z)
	var dz := ground.data_height(x, z + e) - ground.data_height(x, z - e)
	if sqrt(dx * dx + dz * dz) / (2.0 * e) > max_slope: return NAN
	return ground.height_at(x, z)


func _pick_species(x: float, z: float, h: float, biome: int, dry: float, r: float) -> String:
	for o in oases:
		if Vector2(x, z).distance_to(o[0]) < o[1]: return "palm"
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
	var node := Node3D.new(); node.name = "Wild_%d_%d" % [k.x, k.y]
	node.position = Vector3(k.x * TILE, 0, k.y * TILE)
	add_child(node); loaded[k] = node
	var rng := _rng_for(k, 1)
	var groups: Dictionary = {}          # species -> [xforms, colors]
	var rocks: Array = [[], []]
	var n := int(TILE / TREE_GRID)
	var count := 0
	for j in range(n):
		for i in range(n):
			var x := k.x * TILE + (i + rng.randf()) * TREE_GRID
			var z := k.y * TILE + (j + rng.randf()) * TREE_GRID
			var roll := rng.randf(); var r2 := rng.randf(); var sc := rng.randf_range(0.8, 1.3); var yaw := rng.randf() * TAU
			var dens := ground.forest_at(x, z)
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
			groups[sp][0].append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s * rng.randf_range(0.9, 1.15), s)), Vector3(x, h - 0.1, z) - node.position))
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
		rocks[0].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).rotated(Vector3.RIGHT, rng.randf_range(-0.3, 0.3)).scaled(Vector3(s, s * rng.randf_range(0.5, 1.0), s)), Vector3(x, h - s * 0.3, z) - node.position))
		rocks[1].append(Color(1, 1, 1))
	_hedges(k, node, groups, rng)
	for sp in groups:
		var set: Dictionary = species[sp]
		var xf: Array = groups[sp][0]; var cl: Array = groups[sp][1]
		var variants: Array = set.full
		var buckets: Array = []
		for v in range(variants.size()): buckets.append([[] as Array[Transform3D], [] as Array[Color]])
		for i in range(xf.size()):
			var b: int = i % variants.size()
			buckets[b][0].append(xf[i]); buckets[b][1].append(cl[i])
		var is_tree: bool = sp in ["pine", "oak", "olive", "umbrella"]
		for v in range(variants.size()):
			if buckets[v][0].is_empty(): continue
			_emit(node, variants[v], buckets[v][0], buckets[v][1], 0.0, FULL_RANGE if is_tree else 420.0, is_tree)
			if is_tree: _emit(node, set.card[0], buckets[v][0], buckets[v][1], FULL_RANGE, CARD_RANGE, false)
		instance_total += xf.size()
	for v in range(rock_parts.size()):
		var xs: Array[Transform3D] = []; var cs: Array[Color] = []
		for i in range(v, rocks[0].size(), rock_parts.size()):
			xs.append(rocks[0][i]); cs.append(rocks[1][i])
		if not xs.is_empty(): _emit(node, rock_parts[v], xs, cs, 0.0, 600.0, true)
	instance_total += rocks[0].size()


## Hedgerows on the farmland parcel edges (the same parcels outer_terrain.gdshader paints).
func _hedges(k: Vector2i, node: Node3D, groups: Dictionary, rng: RandomNumberGenerator) -> void:
	var x0 := k.x * TILE; var z0 := k.y * TILE
	if ground.splat_at(x0 + TILE * 0.5, z0 + TILE * 0.5).b < 0.2 and ground.splat_at(x0, z0).b < 0.2: return
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
			groups.hedge[0].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.4), s)), Vector3(x, h - 0.1, z) - node.position))
			groups.hedge[1].append(Color(0.8, 0.95, 0.7))


## The parcel pattern of outer_terrain.gdshader `fields()`: (crop, distance to the parcel edge,
## furrow, random) - kept in step with the shader.
static func field_at(w: Vector2) -> Vector4:
	var p := _rot(w, 0.35) + Vector2(sin(w.y * 0.0021) * 40.0, sin(w.x * 0.0017) * 35.0)
	var cell := Vector2(190.0, 115.0)
	var row := floorf(p.y / cell.y)
	p.x += _hash21(Vector2(row, 17.0)) * cell.x
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
	var node := Node3D.new(); node.name = "Grass_%d_%d" % [k.x, k.y]
	node.position = Vector3(k.x * NEAR, 0, k.y * NEAR)
	add_child(node); near_loaded[k] = node
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
		if kind == "grass" and rng.randf() < 0.07: kind = ["flower_y", "flower_p", "flower_w"][rng.randi_range(0, 2)]
		if not groups.has(kind): groups[kind] = [[] as Array[Transform3D], [] as Array[Color]]
		groups[kind][0].append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s * rng.randf_range(0.8, 1.25), s)), Vector3(x, h - 0.05, z) - node.position))
		var v := rng.randf_range(-0.12, 0.12)
		groups[kind][1].append(Color(0.9 + v, 0.92 + v * 0.8, 0.75 + v * 0.5))
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
		"max_tiles": (2 * RADIUS + 3) * (2 * RADIUS + 3), "max_instances": (2 * RADIUS + 3) * (2 * RADIUS + 3) * (MAX_TREES * 2 + 70 + 4500) + (2 * NEAR_RADIUS + 3) * (2 * NEAR_RADIUS + 3) * 900 * 2}
