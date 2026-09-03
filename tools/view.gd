extends SceneTree
## Debug viewer: builds the level and captures screenshots from fixed vantage points.
## Usage: xvfb-run godot --path . --rendering-driver opengl3 -s tools/view.gd -- --out=/tmp/view [--nosea] [--plain]

var out := "/tmp/view"
var frame := 0
var cams := []
var cam: Camera3D
var idx := 0


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	var root := Node3D.new()
	get_root().add_child(root)
	var lvl = load("res://scripts/level.gd").new()
	root.add_child(lvl)
	lvl.build()
	var args := OS.get_cmdline_user_args()
	if "--nofog" in args:
		for c in lvl.get_children():
			if c is WorldEnvironment: c.environment.fog_enabled = false
	if "--debugsea" in args:
		for c in lvl.get_children():
			if c is MeshInstance3D and c.name == "Sea":
				var m: ShaderMaterial = c.material_override
				var code: String = m.shader.code
				code = code.replace("ROUGHNESS = 0.18;", "ROUGHNESS = 1.0; SPECULAR = 0.0;").replace("METALLIC = 0.15;", "METALLIC = 0.0;").replace("ALPHA = mix(0.42, 1.0, smoothstep(0.8, 6.5, d));", "ALPHA = 1.0;")
				var sh2 := Shader.new(); sh2.code = code; m.shader = sh2
	if "--noterrain" in args:
		lvl.terrain.mesh_instance.visible = false
	if "--noabyss" in args:
		for c in lvl.get_children():
			if c is MeshInstance3D and c.mesh is PlaneMesh and c.position.y < -1.0: c.visible = false
	if "--nosea" in args:
		for c in lvl.get_children():
			if c is MeshInstance3D and c.mesh is PlaneMesh: c.visible = false
	if "--rockplain" in args:
		for c in lvl.get_children():
			if c is MeshInstance3D and c.mesh is ArrayMesh and c != lvl.terrain.mesh_instance:
				var mm := StandardMaterial3D.new(); mm.albedo_color = Color(0.60, 0.55, 0.46); mm.roughness = 0.95
				c.material_override = mm
	if "--plain" in args:
		var m := StandardMaterial3D.new(); m.albedo_color = Color(0.1, 0.9, 0.1)
		lvl.terrain.mesh_instance.material_override = m
		for c in lvl.get_children():
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
	cams = [
		[Vector3(20, 290, 300), Vector3(0, 10, -50)],                                               # painting's view: high, from the south
		[Vector3(-150, t.height_at(-150, 60) + 40, 60), Vector3(-200, 8, 0)],                    # villa & the vineyard parcels from above                     # villa & vineyards
		[Vector3(-100, t.height_at(-100, -100) + 25, -100), Vector3(-200, 40, -160)],             # limestone massif
		[Vector3(22, 5, -148), Vector3(27, 13, -111)],                                               # strait aqueduct from the water, town behind
		[Vector3(60, t.height_at(60, -40) + 12, -40), Vector3(150, 10, -110)],                    # harbour front
		[Vector3(20, 42, 70), Vector3(58, 14, 24)],                          # badlands viaduct from the gorge
		[Vector3(160, t.height_at(160, 120) + 40, 120), Vector3(95, 0, 120)],                     # lake in the badlands
		[Vector3(250, t.height_at(250, -140) + 30, -140), Vector3(303, 8, -164)],                 # lighthouse
		[Vector3(-230, t.height_at(-230, -80) + 45, -80), Vector3(-300, 30, -170)],               # NW massif from the farmland
	]
	cam = Camera3D.new()
	cam.fov = 62
	cam.far = 20000
	root.add_child(cam)
	cam.current = true
	_place()


func _place() -> void:
	cam.look_at_from_position(cams[idx][0], cams[idx][1], Vector3.UP)


func _process(_d: float) -> bool:
	frame += 1
	if frame % 12 == 0:
		var img := get_root().get_texture().get_image()
		var p := "%s/view_%d.png" % [out, idx]
		img.save_png(p)
		print("saved ", p)
		idx += 1
		if idx >= cams.size():
			quit()
			return true
		_place()
	return false
