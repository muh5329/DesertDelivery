extends Node3D
## The outer island has a fixed geometry budget, independent of the 3 m painted
## town heightfield. Visuals, ground queries and streamed physics use one grid.
## 400 x 400 cells cover exactly 25 km; only 25 nearby collision tiles exist.
const EXTENT := 25000.0
const CELLS := 400
const STEP := EXTENT / CELLS
const HALF := EXTENT * 0.5
const TILE_CELLS := 8
const TILE_SIZE := STEP * TILE_CELLS
const COLLISION_RADIUS := 2
const CORE_RIM := 750.0
var dressing: Node3D
var focus: Node3D
var terrain: Terrain
var heights := PackedFloat32Array()
var loaded: Dictionary = {}
var _last_tile := Vector2i(-9999, -9999)
var _relief := FastNoiseLite.new()
var _detail := FastNoiseLite.new()

func setup(source: Terrain, seed_value: int) -> void:
	name = "OuterIsland25km"
	terrain = source
	_relief.seed = seed_value
	_relief.frequency = 0.00035
	_relief.fractal_octaves = 4
	_detail.seed = seed_value + 73
	_detail.frequency = 0.0018
	_detail.fractal_octaves = 3
	heights.resize((CELLS + 1) * (CELLS + 1))
	for z in range(CELLS + 1):
		for x in range(CELLS + 1):
			heights[_index(x,z)] = _landform(x * STEP - HALF, z * STEP - HALF)
	_build_mesh()
	if not terrain.road_samples.is_empty(): _build_north_viaduct()
	dressing=preload("res://world/terrain/outer_dressing.gd").new()
	add_child(dressing); dressing.setup(self,seed_value)

func _index(x: int, z: int) -> int:
	return z * (CELLS + 1) + x

func _landform(x: float, z: float) -> float:
	# A sheltered inner lagoon surrounds the detailed original settlement.
	# The surrounding highlands carry distinct long ridges and broad valleys.
	var q := Vector2(x, z)
	var square_radius := maxf(absf(x), absf(z))
	var island_radius := 11100.0 + _detail.get_noise_2d(x * .12, z * .12) * 1100.0
	var coast := smoothstep(island_radius + 650.0, island_radius - 1000.0, q.length())
	var inner := smoothstep(CORE_RIM, 1550.0, square_radius)
	var broad := _relief.get_noise_2d(x,z)
	var ridge := pow(1.0 - absf(_relief.get_noise_2d(x + 9120.0,z - 7600.0)), 3.0)
	var mountain := smoothstep(500.0, 7000.0, -z) * ridge * 620.0
	var h := 85.0 + broad * 160.0 + mountain + _detail.get_noise_2d(x,z) * 32.0
	return lerpf(-10.5, maxf(8.0,h), coast * inner)

func height_at(x: float, z: float) -> float:
	if absf(x) > HALF or absf(z) > HALF: return -10.5
	var gx := clampf((x + HALF) / STEP, 0.0, CELLS - .00001)
	var gz := clampf((z + HALF) / STEP, 0.0, CELLS - .00001)
	var ix := int(gx); var iz := int(gz)
	var u := gx - ix; var v := gz - iz
	var a := heights[_index(ix,iz)]
	var b := heights[_index(ix+1,iz)]
	var c := heights[_index(ix,iz+1)]
	var d := heights[_index(ix+1,iz+1)]
	# Exactly the same diagonal as the rendered and collidable triangles.
	if u + v <= 1.0: return a + (b-a)*u + (c-a)*v
	return d + (c-d)*(1.0-u) + (b-d)*(1.0-v)

func normal_at(x: float, z: float) -> Vector3:
	return Vector3(height_at(x-1.0,z)-height_at(x+1.0,z),2.0,height_at(x,z-1.0)-height_at(x,z+1.0)).normalized()

func biome_at(x: float, z: float) -> int:
	var h := height_at(x,z)
	if h < 0.0: return Terrain.Biome.SEA
	if h < 8.0: return Terrain.Biome.BEACH
	if h > 300.0: return Terrain.Biome.LIMESTONE
	if z < -2500.0: return Terrain.Biome.MOOR
	return Terrain.Biome.FOREST

func _hole(x: int, z: int) -> bool:
	var wx := x * STEP - HALF
	var wz := z * STEP - HALF
	return wx >= -562.5 and wx < 562.5 and wz >= -562.5 and wz < 562.5

func _build_mesh() -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array(); uvs.resize(heights.size())
	vertices.resize(heights.size()); normals.resize(heights.size()); colors.resize(heights.size())
	for z in range(CELLS+1):
		for x in range(CELLS+1):
			var i := _index(x,z)
			var h := heights[i]
			vertices[i] = Vector3(x*STEP-HALF,h,z*STEP-HALF)
			uvs[i] = Vector2(x*STEP,z*STEP)*.006
			var dx := heights[_index(maxi(0,x-1),z)]-heights[_index(mini(CELLS,x+1),z)]
			var dz := heights[_index(x,maxi(0,z-1))]-heights[_index(x,mini(CELLS,z+1))]
			normals[i] = Vector3(dx,STEP*2.0,dz).normalized()
			var meadow := Color(.39,.53,.29).lerp(Color(.65,.66,.39), clampf(h / 330.0,0.0,1.0))
			var rock := smoothstep(250.0,600.0,h)
			colors[i] = meadow.lerp(Color(.60,.65,.65),rock)
			if h < 8.0: colors[i] = Color(.72,.72,.52)
	var indices := PackedInt32Array()
	for z in range(CELLS):
		for x in range(CELLS):
			if _hole(x,z): continue
			var a := _index(x,z); var b := a+1; var c := a+CELLS+1; var d := c+1
			indices.append_array(PackedInt32Array([a,b,c,b,d,c]))
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices; arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_COLOR]=colors; arrays[Mesh.ARRAY_INDEX]=indices; arrays[Mesh.ARRAY_TEX_UV]=uvs
	var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var view := MeshInstance3D.new(); view.mesh=mesh
	var mat := StandardMaterial3D.new(); mat.vertex_color_use_as_albedo=true
	mat.roughness=1.0; mat.specular_mode=BaseMaterial3D.SPECULAR_DISABLED
	if ResourceLoader.exists("res://assets/storybook/gouache_surface.png"):
		mat.albedo_texture=load("res://assets/storybook/gouache_surface.png")
	view.material_override=mat
	add_child(view)

func _physics_process(_delta: float) -> void:
	if focus == null: return
	var tile := Vector2i(floori((focus.global_position.x+HALF)/TILE_SIZE),floori((focus.global_position.z+HALF)/TILE_SIZE))
	if tile != _last_tile: refresh_collision()

func refresh_collision() -> void:
	if focus == null: return
	_last_tile=Vector2i(floori((focus.global_position.x+HALF)/TILE_SIZE),floori((focus.global_position.z+HALF)/TILE_SIZE))
	for tile: Vector2i in loaded.keys():
		if maxi(absi(tile.x-_last_tile.x),absi(tile.y-_last_tile.y)) > COLLISION_RADIUS:
			# Remove immediately from physics before scheduling the node deletion.
			loaded[tile].collision_layer = 0
			loaded[tile].queue_free(); loaded.erase(tile)
	for dz in range(-COLLISION_RADIUS,COLLISION_RADIUS+1):
		for dx in range(-COLLISION_RADIUS,COLLISION_RADIUS+1):
			var tile := _last_tile+Vector2i(dx,dz)
			if loaded.has(tile) or tile.x<0 or tile.y<0 or tile.x>=CELLS/TILE_CELLS or tile.y>=CELLS/TILE_CELLS: continue
			_build_collision(tile)

func _build_collision(tile: Vector2i) -> void:
	var faces := PackedVector3Array()
	for z in range(tile.y*TILE_CELLS,(tile.y+1)*TILE_CELLS):
		for x in range(tile.x*TILE_CELLS,(tile.x+1)*TILE_CELLS):
			if _hole(x,z): continue
			var a := Vector3(x*STEP-HALF,heights[_index(x,z)],z*STEP-HALF)
			var b := Vector3((x+1)*STEP-HALF,heights[_index(x+1,z)],z*STEP-HALF)
			var c := Vector3(x*STEP-HALF,heights[_index(x,z+1)],(z+1)*STEP-HALF)
			var d := Vector3((x+1)*STEP-HALF,heights[_index(x+1,z+1)],(z+1)*STEP-HALF)
			faces.append_array(PackedVector3Array([a,b,c,b,d,c]))
	var body := StaticBody3D.new(); body.collision_layer=1
	if not faces.is_empty():
		var shape := ConcavePolygonShape3D.new(); shape.set_faces(faces)
		var collision := CollisionShape3D.new(); collision.shape=shape; body.add_child(collision)
	add_child(body); loaded[tile]=body

## A real, physical road joins the old monastery district to the new highlands.
## It is inserted into the same navigation data used by traffic and autopilot.
func _build_north_viaduct() -> void:
	var join: Dictionary = terrain.nearest_road(Vector3(-300,0,-490))
	var start: Vector3 = join.point
	var finish := Vector3(start.x, height_at(start.x,-1900.0), -1900.0)
	var count := ceili(start.distance_to(finish)/4.0)
	var samples := PackedVector3Array()
	for i in range(count+1):
		var t := float(i)/count
		var p := start.lerp(finish,t)
		var floor_h: float = terrain.height_at(p.x,p.z) if absf(p.z)<624.0 else height_at(p.x,p.z)
		p.y=maxf(p.y, floor_h+.08)
		samples.append(p)
	# Keep the deck above terrain while removing tiny heightfield ripples.
	for pass_index in range(2):
		for i in range(1,samples.size()): samples[i].y=maxf(samples[i].y,samples[i-1].y-4.0*.24)
		for i in range(samples.size()-2,-1,-1): samples[i].y=maxf(samples[i].y,samples[i+1].y-4.0*.24)
	var road_index := terrain.road_samples.size()
	terrain.road_samples.append(samples)
	terrain.bridges.append(Bridge.new(road_index,samples,0,samples.size()-1,start.y))
	terrain._road_grid.clear()
	var curve := Curve3D.new()
	for p in samples: curve.add_point(p)
	terrain.roads.append(curve)
	var deck_mat := StandardMaterial3D.new(); deck_mat.albedo_color=Color(.70,.65,.51); deck_mat.roughness=1.0
	var stone_mat := StandardMaterial3D.new(); stone_mat.albedo_color=Color(.52,.57,.50); stone_mat.roughness=1.0
	var surface := SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	for i in range(samples.size()-1):
		var a := samples[i]; var b := samples[i+1]
		var left := Vector3(-4.5,0,0)
		var quad := [a+left,a-left,b+left,b-left]
		for index in [0,2,1,1,2,3]:
			surface.set_normal(Vector3.UP); surface.add_vertex(quad[index]); faces.append(quad[index])
		if i%10==0:
			var base := terrain.height_at(a.x,a.z) if absf(a.z)<624.0 else height_at(a.x,a.z)
			if a.y-base>3.0:
				var pillar := MeshInstance3D.new(); var box := BoxMesh.new()
				box.size=Vector3(7.0,a.y-base,2.0); pillar.mesh=box; pillar.material_override=stone_mat
				pillar.position=Vector3(a.x,(a.y+base)*.5,a.z); add_child(pillar)
	var view := MeshInstance3D.new(); view.mesh=surface.commit(); view.material_override=deck_mat; add_child(view)
	var body := StaticBody3D.new(); body.collision_layer=1
	var collider := CollisionShape3D.new(); var shape := ConcavePolygonShape3D.new(); shape.set_faces(faces)
	collider.shape=shape; body.add_child(collider); add_child(body)
	print('[world] 25 km terrain, north viaduct ',samples.size(),' navigation samples')
