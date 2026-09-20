extends Node3D
## Deterministic wilderness decoration, generated only near the active courier.
## Mesh resources are shared across tiles; instances carry only transforms/tints.
## At most 25 tiles, one tile built per frame, no terrain-scale scene-node forest.
const TILE_SIZE := 320.0
const RADIUS := 2
const TREE_ATTEMPTS := 360
const MEADOW_ATTEMPTS := 1800
var landscape: Node3D
var seed_value := 2026
var loaded: Dictionary = {}
var pending: Array[Vector2i] = []
var _last := Vector2i(-9999,-9999)
var _groves := FastNoiseLite.new()
var _meshes: Dictionary = {}
var _materials: Dictionary = {}
var _road_x := -300.0

func setup(source: Node3D, world_seed: int) -> void:
	landscape=source; seed_value=world_seed; name="StreamedWilderness"
	_groves.seed=world_seed+801; _groves.frequency=.007; _groves.fractal_octaves=2
	_make_resources()
	if not landscape.terrain.road_samples.is_empty(): _road_x=landscape.terrain.road_samples[-1][0].x

func _process(_delta: float) -> void:
	if landscape == null or landscape.focus == null: return
	var p: Vector3=landscape.focus.global_position
	var tile:=Vector2i(floori(p.x/TILE_SIZE),floori(p.z/TILE_SIZE))
	if tile != _last:
		_last=tile; pending.clear()
		for key: Vector2i in loaded.keys():
			if maxi(absi(key.x-tile.x),absi(key.y-tile.y))>RADIUS:
				loaded[key].queue_free(); loaded.erase(key)
		for dz in range(-RADIUS,RADIUS+1):
			for dx in range(-RADIUS,RADIUS+1):
				var key:=tile+Vector2i(dx,dz)
				if not loaded.has(key) and absf((key.x+.5)*TILE_SIZE)<12500 and absf((key.y+.5)*TILE_SIZE)<12500:
					pending.append(key)
		pending.sort_custom(func(a: Vector2i,b: Vector2i): return (a-tile).length_squared()<(b-tile).length_squared())
	if not pending.is_empty(): _build_tile(pending.pop_front())

func _make_resources() -> void:
	var trunk:=CylinderMesh.new(); trunk.top_radius=.09; trunk.bottom_radius=.20
	trunk.height=4.8; trunk.radial_segments=7; trunk.rings=1
	_meshes.trunk=_combine(trunk,[Transform3D(Basis(),Vector3(0,2.4,0))])
	var crown:=SphereMesh.new(); crown.radius=1.0; crown.height=2.0; crown.radial_segments=12; crown.rings=5
	_meshes.crown=_combine(crown,[
		Transform3D(Basis().scaled(Vector3(2.2,1.7,1.85)),Vector3(-.6,5.0,0)),
		Transform3D(Basis().scaled(Vector3(1.6,1.9,1.6)),Vector3(.9,5.9,.2)),
		Transform3D(Basis().scaled(Vector3(1.7,1.35,1.4)),Vector3(.3,4.8,-1.0))])
	_meshes.shrub=_combine(crown,[Transform3D(Basis().scaled(Vector3(.8,.62,.7)),Vector3(0,.50,0))])
	var rock:=SphereMesh.new(); rock.radius=1.0; rock.height=2.0; rock.radial_segments=7; rock.rings=3
	_meshes.rock=rock
	var grass:=SurfaceTool.new(); grass.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(20):
		var angle:=i*2.4
		var side:=Vector3(cos(angle),0,sin(angle))*.10
		var reach:=.15+float(i%5)*.17
		var base:=Vector3(sin(angle)*reach,0,cos(angle)*reach)
		for point in [base-side,base+side,base+Vector3(.12,.45+float(i%3)*.12,.06)]:
			grass.set_normal(Vector3.UP); grass.add_vertex(point)
	_meshes.grass=grass.commit()
	for key in ["trunk","crown","shrub","rock","grass"]:
		var mat:=StandardMaterial3D.new(); mat.vertex_color_use_as_albedo=true
		mat.roughness=1.0; mat.specular_mode=BaseMaterial3D.SPECULAR_DISABLED
		if key=="grass": mat.cull_mode=BaseMaterial3D.CULL_DISABLED
		_materials[key]=mat

func _combine(mesh: Mesh, transforms: Array) -> ArrayMesh:
	var surface:=SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for transform: Transform3D in transforms: surface.append_from(mesh,0,transform)
	return surface.commit()

func _build_tile(tile: Vector2i) -> void:
	var node:=Node3D.new(); node.name="Grove_%d_%d"%[tile.x,tile.y]
	node.position=Vector3(tile.x*TILE_SIZE,0,tile.y*TILE_SIZE); add_child(node)
	loaded[tile]=node
	var random:=RandomNumberGenerator.new()
	random.seed=hash("%d:%d:%d"%[seed_value,tile.x,tile.y])
	var transforms: Dictionary={}; var tints: Dictionary={}
	for kind in _meshes:
		transforms[kind]=[]; tints[kind]=[]
	for attempt in range(TREE_ATTEMPTS+MEADOW_ATTEMPTS):
		var x:=tile.x*TILE_SIZE+random.randf()*TILE_SIZE
		var z:=tile.y*TILE_SIZE+random.randf()*TILE_SIZE
		if maxf(absf(x),absf(z))<1100.0: continue
		var height: float=landscape.height_at(x,z)
		if height<6.0 or height>440.0: continue
		var normal: Vector3=landscape.normal_at(x,z)
		if normal.y<.88: continue
		# The north road needs a clear shoulder where it lands in the wilderness.
		if absf(x-_road_x)<16.0 and z>-2000.0 and z<-1000.0: continue
		var patch:=_groves.get_noise_2d(x,z)
		var origin:=Vector3(x-node.position.x,height,z-node.position.z)
		var scale_v:=random.randf_range(.85,1.40)
		var basis:=Basis(Vector3.UP,random.randf()*TAU).scaled(Vector3.ONE*scale_v)
		var transform:=Transform3D(basis,origin)
		if attempt<TREE_ATTEMPTS:
			if patch<-.06 or height>300.0: continue
			transforms.trunk.append(transform); tints.trunk.append(Color(.39,.32,.23))
			transforms.crown.append(transform)
			tints.crown.append(Color(.25,.44,.29).lerp(Color(.48,.60,.34),random.randf()))
		elif attempt%11==0:
			transform.basis=basis.scaled(Vector3(1.6,.75,1.3)); transform.origin.y-=.28
			transforms.rock.append(transform); tints.rock.append(Color(.63,.66,.59))
		elif patch>.02 and attempt%3==0:
			transforms.shrub.append(transform); tints.shrub.append(Color(.39,.53,.31))
		else:
			transforms.grass.append(transform)
			tints.grass.append(Color(.55,.62,.37).lerp(Color(.74,.72,.46),random.randf()))
	for kind in _meshes:
		if transforms[kind].is_empty(): continue
		var multi:=MultiMesh.new(); multi.transform_format=MultiMesh.TRANSFORM_3D; multi.use_colors=true
		multi.mesh=_meshes[kind]; multi.instance_count=transforms[kind].size()
		for i in range(multi.instance_count):
			multi.set_instance_transform(i,transforms[kind][i]); multi.set_instance_color(i,tints[kind][i])
		var view:=MultiMeshInstance3D.new(); view.multimesh=multi; view.material_override=_materials[kind]
		view.visibility_range_end=1050.0 if kind in ["trunk","crown"] else 550.0
		view.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if kind in ["grass","shrub"] else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		node.add_child(view)

func stats() -> Dictionary:
	var instances:=0
	for node: Node3D in loaded.values():
		for view in node.get_children():
			if view is MultiMeshInstance3D: instances+=view.multimesh.instance_count
	return {"tiles":loaded.size(),"pending":pending.size(),"instances":instances,"max_tiles":25,"max_instances":25*(TREE_ATTEMPTS*2+MEADOW_ATTEMPTS)}
