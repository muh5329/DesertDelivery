extends Node
## Debug viewer: the whole island loaded, screenshots from fixed vantage points.
## Usage: xvfb-run godot --path . --rendering-driver opengl3 -- --test=view --nostream --out=/tmp/view [--nofog] [--nosea]

var out := "/tmp/view"
var frame := 0
var cams := []
var cam: Camera3D
var idx := 0


func _ready() -> void:
	var game: Game = Game.current
	out = game.cli.get_string("out", out)
	DirAccess.make_dir_recursive_absolute(out)
	var root := self
	var lvl: WorldManager = game.world
	if "--nostream" in OS.get_cmdline_user_args():
		lvl.streamer.load_everything()
	game.hud.visible = false
	game.bike.visible = false
	game.player.visible = false
	var args := OS.get_cmdline_user_args()
	if "--nofog" in args:
		for c in lvl.environment.get_children():
			if c is WorldEnvironment: c.environment.fog_enabled = false
	if "--debugsea" in args:
		for c in lvl.environment.get_children():
			if c is MeshInstance3D and c.name == "Sea":
				var m: ShaderMaterial = c.material_override
				var code: String = m.shader.code
				code = code.replace("ROUGHNESS = 0.18;", "ROUGHNESS = 1.0; SPECULAR = 0.0;").replace("METALLIC = 0.15;", "METALLIC = 0.0;").replace("ALPHA = mix(0.42, 1.0, smoothstep(0.8, 6.5, d));", "ALPHA = 1.0;")
				var sh2 := Shader.new(); sh2.code = code; m.shader = sh2
	if "--noterrain" in args:
		if lvl.terrain.mesh_instance: lvl.terrain.mesh_instance.visible = false
		if lvl.terrain.terrain3d: lvl.terrain.terrain3d.visible = false
	if "--noabyss" in args:
		for c in lvl.environment.get_children():
			if c is MeshInstance3D and c.mesh is PlaneMesh and c.position.y < -1.0: c.visible = false
	if "--nosea" in args:
		for c in lvl.environment.get_children():
			if c is MeshInstance3D and c.mesh is PlaneMesh: c.visible = false
	if "--rockplain" in args:
		for c in lvl.environment.get_children():
			if c is MeshInstance3D and c.mesh is ArrayMesh and c != lvl.terrain.mesh_instance:
				var mm := StandardMaterial3D.new(); mm.albedo_color = Color(0.60, 0.55, 0.46); mm.roughness = 0.95
				c.material_override = mm
	if "--plain" in args:
		var m := StandardMaterial3D.new(); m.albedo_color = Color(0.1, 0.9, 0.1)
		lvl.terrain.mesh_instance.material_override = m
		for c in lvl.environment.get_children():
			if c is WorldEnvironment:
				c.environment.sky.sky_material.ground_bottom_color = Color(1, 0, 1)
				c.environment.sky.sky_material.ground_horizon_color = Color(1, 0, 1)
				c.environment.fog_enabled = false
	if "--nocolor" in args or "--small" in args or "--tangents" in args or "--flat" in args:
		var m0: ArrayMesh = lvl.terrain.mesh_instance.mesh
		var arr = m0.surface_get_arrays(0)
		if "--nocolor" in args:
			arr[Mesh.ARRAY_COLOR] = null
		if "--small" in args:
			# keep only triangles near the villa
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			var keep := PackedInt32Array()
			for k in range(0, ix.size(), 3):
				if v[ix[k]].distance_to(Vector3(0, 6, 20)) < 80.0:
					keep.append(ix[k]); keep.append(ix[k+1]); keep.append(ix[k+2])
			arr[Mesh.ARRAY_INDEX] = keep
		var m1 := ArrayMesh.new()
		if "--tangents" in args:
			var st := SurfaceTool.new()
			st.create_from_arrays(arr)
			st.generate_tangents()
			m1 = st.commit()
		elif "--flat" in args:
			# de-index into flat triangles, no color
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for k in range(0, ix.size(), 3):
				var a := v[ix[k]]; var b := v[ix[k+1]]; var c := v[ix[k+2]]
				var n := (b - a).cross(c - a).normalized()
				st.set_normal(n); st.add_vertex(a)
				st.set_normal(n); st.add_vertex(b)
				st.set_normal(n); st.add_vertex(c)
			m1 = st.commit()
		else:
			m1.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		lvl.terrain.mesh_instance.mesh = m1
		print("rebuilt mesh: ", m1.get_surface_count(), " ", m1.get_aabb())
	var t = lvl.terrain
	var db := game.world.database
	cams = [
		[Vector3(40, 620, 1000), Vector3(0, 10, -80)],                                              # the whole island from the south, high
		[Vector3(-250, t.height_at(-250, 110) + 60, 110), Vector3(-330, 8, 0)],                     # villa & the vineyard parcels from above
		[Vector3(-170, t.height_at(-170, -170) + 30, -170), Vector3(-330, 45, -270)],               # limestone massif
		[Vector3(38, 5, -256), Vector3(47, 13, -192)],                                                # strait aqueduct from the water, town behind
		[Vector3(104, t.height_at(104, -69) + 14, -69), Vector3(260, 10, -190)],                     # harbour front
		[Vector3(35, 42, 120), Vector3(100, 14, 42)],                                                 # badlands viaduct from the gorge
		[Vector3(277, t.height_at(277, 208) + 45, 208), Vector3(165, 0, 208)],                       # lake in the badlands
		[Vector3(430, t.height_at(430, -243) + 30, -243), Vector3(525, 8, -284)],                    # lighthouse
		[Vector3(-400, t.height_at(-400, -140) + 45, -140), Vector3(-520, 30, -295)],                # NW massif from the farmland
	]
	# every named place from 45 m away and 22 m up (new places first)
	var ids := [&"monastery", &"quarry", &"refugio", &"cala_blanca", &"salinas", &"bodega", &"torre_vieja", &"lakeside_camp", &"windmill_ridge", &"chapel", &"hilltop_farm", &"harbour_cafe", &"dunes_lookout", &"town_square"]
	for id in ids:
		if not db.locations.has(id): continue
		var p: Vector3 = db.location_pos(id)
		var f: Vector3 = db.locations[id].facing
		var from: Vector3 = p + f * 45.0 + Vector3(0, 22, 0)
		from.y = maxf(from.y, t.height_at(from.x, from.z) + 12.0)
		cams.append([from, p + Vector3(0, 3, 0)])
	if "--close" in args:
		# rider's-eye views: 2.2 m above the road, looking 35 m along it
		cams = []
		var spots := [Vector3(-300, 0, 3), Vector3(-330, 0, -300), Vector3(-320, 0, -400), Vector3(60, 0, 60), Vector3(-380, 0, 420), Vector3(-180, 0, 470), Vector3(60, 0, 430), Vector3(300, 0, 500), Vector3(150, 0, -260), Vector3(-150, 0, -100)]
		if "--few" in args: spots = [Vector3(-300, 0, 3), Vector3(-150, 0, -100), Vector3(-320, 0, -400)]
		for spot in spots:
			var r := t.nearest_road(spot)
			var p: Vector3 = r.point
			var d: Vector3 = r.tangent
			var eye: Vector3 = p + Vector3(0, 2.2, 0) - d * 2.0
			cams.append([eye, p + d * 35.0 + Vector3(0, 1.0, 0)])
	cam = Camera3D.new()
	cam.fov = 62
	cam.far = 20000
	root.add_child(cam)
	cam.current = true
	t.set_view_camera(cam)
	_place()


func _place() -> void:
	cam.look_at_from_position(cams[idx][0], cams[idx][1], Vector3.UP)
	# stream the chunks round the subject (the bike is the streamer's focus)
	var game: Game = Game.current
	game.bike.place(cams[idx][1] + Vector3(0, 30, 0), Vector3(0, 0, -1))
	game.world.streamer.load_all_pending()


func _process(_d: float) -> void:
	frame += 1
	if frame % 5 == 0:
		var img := get_tree().root.get_texture().get_image()
		var p := "%s/view_%d.png" % [out, idx]
		img.save_png(p)
		print("saved ", p)
		idx += 1
		if idx >= cams.size():
			get_tree().quit()
			return
		_place()
	return
