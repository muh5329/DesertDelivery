class_name OuterWorld
extends Node3D
## The 25 km country round the hand-built core: terrain, roads, towns, wilderness and sea lanes
## generated offline by world/mapgen/outer.py into data/outer (ADR 0010).
##
## Interface (what Terrain forwards to for anything outside the core square, `terrain.expanse`):
##   height_at(x, z), normal_at(x, z), biome_at(x, z), road_dist_at(x, z), focus, refresh_collision()
## Children: OuterTerrain (GPU CDLOD ground), OuterRoads (network, ribbons, bridges, signs),
## OuterTowns (towns, hamlets, landmarks as streamed recipes + far silhouettes), OuterFlora
## (streamed wilderness), the mountain lake. Collision: streamed ConcavePolygon tiles of the same
## 6.25 m lattice the terrain is drawn with, one built per physics frame, at most 25 alive.

const TILE_CELLS := 32                          # lattice cells per tile side
const TILE := OuterGround.LAT * TILE_CELLS      # 200 m
const TILES := 125                              # 25 km / 200 m
const COLLISION_RADIUS := 2                     # 5 x 5 tiles round the focus
const CORE_HALF := 624.0
## the estuary's centre line (world/mapgen/outer_land.py ESTUARY; plan.json "estuary" when present)
const ESTUARY := [[1350, 260], [2300, 420], [3300, 640], [4300, 520], [5300, 760], [6300, 1060],
	[7000, 1240], [7700, 1330], [8400, 1560], [9200, 1750], [10400, 1900]]

var ground := OuterGround.new()
var terrain: Terrain
var focus: Node3D
var view: OuterTerrainView
var roads: OuterRoads
var towns: OuterTowns
var flora: OuterFlora
var rivers: OuterRivers
var loaded: Dictionary = {}                     # Vector2i -> StaticBody3D
var pending: Array[Vector2i] = []
var _focus_tile := Vector2i(-9999, -9999)
var ok := false
var build_ms := {}


func setup(p_terrain: Terrain, database: WorldDatabase, kit: WorldKit, seed_value: int) -> void:
	name = "OuterWorld"
	terrain = p_terrain
	var t0 := Time.get_ticks_msec()
	ok = ground.load_data()
	build_ms["load"] = Time.get_ticks_msec() - t0
	if not ok: return
	t0 = Time.get_ticks_msec()
	view = OuterTerrainView.new(); add_child(view); view.setup(ground)
	build_ms["terrain_view"] = Time.get_ticks_msec() - t0; t0 = Time.get_ticks_msec()
	roads = OuterRoads.new(); add_child(roads); roads.setup(self, terrain)
	build_ms["roads"] = Time.get_ticks_msec() - t0; t0 = Time.get_ticks_msec()
	towns = OuterTowns.new(); add_child(towns); towns.setup(self, database, kit)
	build_ms["towns"] = Time.get_ticks_msec() - t0; t0 = Time.get_ticks_msec()
	# rivers before the flora: the scatter keeps its trees and grass out of the channels
	rivers = OuterRivers.new(); add_child(rivers); rivers.setup(self)
	build_ms["rivers"] = Time.get_ticks_msec() - t0; t0 = Time.get_ticks_msec()
	flora = OuterFlora.new(); add_child(flora); flora.setup(self, seed_value)
	build_ms["flora"] = Time.get_ticks_msec() - t0
	_build_lake()
	_hook_sea()
	print("[outer] loaded in %s ms" % [build_ms])


# ---------------------------------------------------------------- aerial perspective
## The core's fog is tuned for a 1.2 km island seen from the saddle. Over a 25 km country it hides
## everything past ~6 km, so the fog thins with the camera's height (and the sea's own fog, which
## copies the environment's at build time, follows).
var _env: Environment
var _sea_mat: ShaderMaterial
var _fog_base := 0.0
var _fog_height_base := 0.0
var _fog_scale := -1.0


var _sea: MeshInstance3D
var _abyss: MeshInstance3D
const SEA_PLANE := 240000.0


func _process(_delta: float) -> void:
	if _env == null: return
	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp else null
	if cam == null: return
	var y := cam.global_position.y
	_follow_camera(cam)
	# (polish: from the air the land kept ~55 % haze at 10 km; now ~35 %, the mountains read)
	var s := lerpf(0.62, 0.11, clampf((y - 30.0) / 1500.0, 0.0, 1.0))
	s = lerpf(s, 0.02, clampf((y - 1500.0) / 5000.0, 0.0, 1.0))
	if absf(s - _fog_scale) < 0.01: return
	_fog_scale = s
	_env.fog_density = _fog_base * s
	_env.fog_height_density = _fog_height_base * s * (1.0 - clampf((y - 150.0) / 1500.0, 0.0, 1.0))
	if _sea_mat:
		_sea_mat.set_shader_parameter("fog_density", _fog_base * s)
		var k := 1.0 + maxf(y, 0.0) / 350.0
		_sea_mat.set_shader_parameter("horizon_fade_start", 400.0 * k)
		_sea_mat.set_shader_parameter("horizon_fade_end", 2000.0 * k)


## From the air the view reaches past the 30 km the ground needs: the far plane grows with the
## camera's height, the sea plane (and the abyss under it) follow the camera, and the sea fogs into
## the sky's horizon colour before the far plane, so no band of sky shows under the horizon.
func _follow_camera(cam: Camera3D) -> void:
	var p := cam.global_position
	var want := clampf(30000.0 + maxf(p.y - 250.0, 0.0) * 11.0, 30000.0, 110000.0)
	if absf(cam.far - want) > 400.0: cam.far = want
	var snap := Vector3(snappedf(p.x, 2000.0), 0.0, snappedf(p.z, 2000.0))
	if _sea: _sea.global_position = Vector3(snap.x, _sea.global_position.y, snap.z)
	if _abyss: _abyss.global_position = Vector3(snap.x, _abyss.global_position.y, snap.z)
	if _sea_mat:
		_sea_mat.set_shader_parameter("far_fade_start", cam.far * 0.42)
		_sea_mat.set_shader_parameter("far_fade_end", cam.far * 0.96)


func _find_env(env_root: Node) -> void:
	for c in env_root.get_children():
		if c is WorldEnvironment and (c as WorldEnvironment).environment:
			_env = (c as WorldEnvironment).environment
			_fog_base = _env.fog_density
			_fog_height_base = _env.fog_height_density


## The sea plane (WorldKit._build_sea) reads its far depth from the core map; give it ours too so
## the outer coasts get the same shallows and foam, and stretch the abyss floor under the world.
func _hook_sea() -> void:
	var env := get_parent()
	if env == null: return
	_find_env(env)
	var sea := env.get_node_or_null("Sea") as MeshInstance3D
	if sea and sea.mesh is PlaneMesh:
		# reach well past the far plane (which grows with altitude) so no edge of the water shows
		var spm := (sea.mesh as PlaneMesh).duplicate() as PlaneMesh
		spm.size = Vector2(SEA_PLANE, SEA_PLANE)
		sea.mesh = spm
		sea.custom_aabb = AABB(Vector3(-SEA_PLANE * 0.5, -1.0, -SEA_PLANE * 0.5), Vector3(SEA_PLANE, 2.0, SEA_PLANE))
		_sea = sea
	if sea and sea.material_override is ShaderMaterial:
		var m: ShaderMaterial = sea.material_override
		_sea_mat = m
		m.set_shader_parameter("outer_height", view.material.get_shader_parameter("height_lin"))
		m.set_shader_parameter("outer_enabled", true)
		var est := PackedVector2Array()
		for q in ground.plan.get("estuary", ESTUARY): est.append(Vector2(q[0], q[1]))
		m.set_shader_parameter("estuary", est)
		m.set_shader_parameter("estuary_n", mini(est.size(), 12))
	var abyss := env.get_node_or_null("Abyss") as MeshInstance3D
	if abyss and abyss.mesh is PlaneMesh:
		var pm := (abyss.mesh as PlaneMesh).duplicate() as PlaneMesh
		pm.size = Vector2(SEA_PLANE, SEA_PLANE)
		abyss.mesh = pm
		_abyss = abyss
	# the sky's lower half shows only under the far edge of the sea: keep it the horizon colour
	if _env and _env.sky and _env.sky.sky_material is ShaderMaterial:
		var skm: ShaderMaterial = _env.sky.sky_material
		skm.set_shader_parameter("ground_bottom_color", (WorldKit.Atmosphere.sky_horizon as Color).darkened(0.06))


func load_ms_total() -> int:
	var total := 0
	for k in build_ms: total += int(build_ms[k])
	return total


# ---------------------------------------------------------------- ground queries
func height_at(x: float, z: float) -> float:
	return ground.height_at(x, z) if ok else -10.5


func normal_at(x: float, z: float) -> Vector3:
	return ground.normal_at(x, z) if ok else Vector3.UP


func biome_at(x: float, z: float) -> int:
	return ground.biome_at(x, z) if ok else Terrain.Biome.SEA


func road_dist_at(x: float, z: float) -> float:
	return ground.road_dist_at(x, z) if ok else 40.0


func plan() -> Dictionary:
	return ground.plan


# ---------------------------------------------------------------- collision tiles
func tile_of(p: Vector3) -> Vector2i:
	return Vector2i(floori((p.x - OuterGround.ORIGIN) / TILE), floori((p.z - OuterGround.ORIGIN) / TILE))


func _physics_process(_delta: float) -> void:
	if focus == null or not ok: return
	var t := tile_of(focus.global_position)
	if t != _focus_tile: _plan_tiles(t)
	if not pending.is_empty(): _build_tile(pending.pop_front())


## Synchronously bring the collision round the focus up to date (teleports, tests).
func refresh_collision() -> void:
	if focus == null or not ok: return
	_plan_tiles(tile_of(focus.global_position))
	while not pending.is_empty(): _build_tile(pending.pop_front())


func _plan_tiles(t: Vector2i) -> void:
	_focus_tile = t
	for key: Vector2i in loaded.keys():
		if maxi(absi(key.x - t.x), absi(key.y - t.y)) > COLLISION_RADIUS:
			var body: StaticBody3D = loaded[key]
			body.collision_layer = 0          # out of the physics world now, freed later
			body.queue_free(); loaded.erase(key)
	pending.clear()
	for dz in range(-COLLISION_RADIUS, COLLISION_RADIUS + 1):
		for dx in range(-COLLISION_RADIUS, COLLISION_RADIUS + 1):
			var k := t + Vector2i(dx, dz)
			if loaded.has(k) or k.x < 0 or k.y < 0 or k.x >= TILES or k.y >= TILES: continue
			pending.append(k)
	pending.sort_custom(func(a: Vector2i, b: Vector2i): return (a - t).length_squared() < (b - t).length_squared())


func _build_tile(k: Vector2i) -> void:
	var I0 := k.x * TILE_CELLS; var J0 := k.y * TILE_CELLS
	var n := TILE_CELLS + 1
	var tx0 := OuterGround.ORIGIN + I0 * OuterGround.LAT; var tz0 := OuterGround.ORIGIN + J0 * OuterGround.LAT
	if tx0 >= -CORE_HALF and tx0 + TILE <= CORE_HALF and tz0 >= -CORE_HALF and tz0 + TILE <= CORE_HALF:
		var empty := StaticBody3D.new(); empty.name = "Ground_%d_%d" % [k.x, k.y]; add_child(empty); loaded[k] = empty
		return
	var hs := PackedFloat32Array(); hs.resize(n * n)
	for j in range(n):
		for i in range(n):
			hs[j * n + i] = ground.lattice(I0 + i, J0 + j)
	var faces := PackedVector3Array()
	faces.resize(TILE_CELLS * TILE_CELLS * 6)
	var f := 0
	var L := OuterGround.LAT
	for j in range(TILE_CELLS):
		var z0 := OuterGround.ORIGIN + (J0 + j) * L
		for i in range(TILE_CELLS):
			var x0 := OuterGround.ORIGIN + (I0 + i) * L
			# cells wholly inside the core square are the core terrain's
			if x0 >= -CORE_HALF and x0 + L <= CORE_HALF and z0 >= -CORE_HALF and z0 + L <= CORE_HALF: continue
			var a := Vector3(x0, hs[j * n + i], z0)
			var b := Vector3(x0 + L, hs[j * n + i + 1], z0)
			var c := Vector3(x0, hs[(j + 1) * n + i], z0 + L)
			var d := Vector3(x0 + L, hs[(j + 1) * n + i + 1], z0 + L)
			faces[f] = a; faces[f + 1] = b; faces[f + 2] = c
			faces[f + 3] = b; faces[f + 4] = d; faces[f + 5] = c
			f += 6
	faces.resize(f)
	var body := StaticBody3D.new()
	body.name = "Ground_%d_%d" % [k.x, k.y]
	body.collision_layer = 1
	if f > 0:
		var shape := ConcavePolygonShape3D.new(); shape.set_faces(faces)
		var cs := CollisionShape3D.new(); cs.shape = shape
		body.add_child(cs)
	add_child(body)
	loaded[k] = body


# ---------------------------------------------------------------- the mountain lake
func _build_lake() -> void:
	if not ground.plan.has("lake"): return
	var lk: Dictionary = ground.plan.lake
	var poly := PackedVector2Array()
	for p in lk.get("polygon", []): poly.append(Vector2(p[0], p[1]))
	if poly.size() < 3: return
	if poly[0].distance_to(poly[poly.size() - 1]) < 1.0: poly.remove_at(poly.size() - 1)
	var tris := Geometry2D.triangulate_polygon(poly)
	if tris.is_empty(): return
	var verts := PackedVector3Array(); var normals := PackedVector3Array()
	for p in poly:
		verts.append(Vector3(p.x - lk.x, 0.0, p.y - lk.z)); normals.append(Vector3.UP)
	var idx := PackedInt32Array()
	for t in range(0, tris.size(), 3):
		var a := verts[tris[t]]; var b := verts[tris[t + 1]]; var c := verts[tris[t + 2]]
		# front faces up (clockwise seen from above)
		if (b - a).cross(c - a).y < 0.0: idx.append_array(PackedInt32Array([tris[t], tris[t + 1], tris[t + 2]]))
		else: idx.append_array(PackedInt32Array([tris[t], tris[t + 2], tris[t + 1]]))
	var arr := []; arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts; arr[Mesh.ARRAY_NORMAL] = normals; arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://world/outer/lake.gdshader")
	var water := MeshInstance3D.new()
	water.name = "MountainLake"
	water.mesh = mesh; water.material_override = mat
	water.position = Vector3(lk.x, lk.level, lk.z)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)
