extends SceneTree
## Graphical counterpart of bike_dynamics_tests.gd. Run without --headless:
## godot --path . --script tests/bike_dynamics_view.gd
## Captures the production bike on the same physical convex crest at launch,
## apex, first spring contact and settled riding; writes measured state alongside.
const DT := 1.0 / 120.0
const OUTPUT := "res://artifacts/handling-pass"
var bike: Bike
var camera: Camera3D
var records: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("run")

func finish_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = .9
	return material

func capture(label: String) -> void:
	camera.global_position = bike.global_position + Vector3(4.5, 1.6, 1.7)
	camera.look_at(bike.global_position + Vector3.UP * .8)
	await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(OUTPUT + "/bike_" + label + ".png")
	assert(error == OK, "Unable to save handling capture")
	records.append({"phase":label,"position":[bike.position.x,bike.position.y,bike.position.z],
		"speed":bike.speed,"vertical_velocity":bike.vertical_vel,"grounded":bike.grounded,
		"air_time":bike.air_time,"front_travel":bike.drive.front_suspension,
		"rear_travel":bike.drive.rear_suspension,"suspension_load":bike.drive.suspension_load})

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.size = Vector2i(1600, 900)
	var environment := WorldEnvironment.new(); environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("bbcbd4")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("d6dfeb")
	environment.environment.ambient_light_energy = .65
	root.add_child(environment)
	var sunlight := DirectionalLight3D.new(); sunlight.rotation_degrees = Vector3(-48, -35, 0)
	sunlight.light_energy = 1.4; sunlight.shadow_enabled = true; root.add_child(sunlight)
	var floor := StaticBody3D.new(); root.add_child(floor)
	var collision := CollisionShape3D.new(); var box := BoxShape3D.new(); box.size = Vector3(200, 2, 200)
	collision.shape = box; floor.add_child(collision); floor.position.y = 219
	var floor_view := MeshInstance3D.new(); var ground := BoxMesh.new(); ground.size = box.size
	floor_view.mesh = ground; floor_view.material_override = finish_material(Color("97a884")); floor.add_child(floor_view)
	var a := Vector3(-8, 220, 20); var b := Vector3(8, 220, 20)
	var c := Vector3(-8, 223, 0); var d := Vector3(8, 223, 0)
	var e := Vector3(-8, 220, -20); var f := Vector3(8, 220, -20)
	var vertices := PackedVector3Array([a,c,b,b,c,d,c,e,d,d,e,f])
	var ramp := StaticBody3D.new(); root.add_child(ramp)
	var ramp_collision := CollisionShape3D.new(); var ramp_shape := ConcavePolygonShape3D.new()
	ramp_shape.set_faces(vertices); ramp_collision.shape = ramp_shape; ramp.add_child(ramp_collision)
	var normals := PackedVector3Array()
	for i in range(0, vertices.size(), 3):
		var normal := (vertices[i+2]-vertices[i]).cross(vertices[i+1]-vertices[i]).normalized()
		for j in 3: normals.append(normal)
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX); arrays[Mesh.ARRAY_VERTEX] = vertices; arrays[Mesh.ARRAY_NORMAL] = normals
	var ramp_mesh := ArrayMesh.new(); ramp_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var ramp_view := MeshInstance3D.new(); ramp_view.mesh = ramp_mesh; ramp_view.material_override = finish_material(Color("b59b72")); ramp.add_child(ramp_view)
	camera = Camera3D.new(); root.add_child(camera); camera.current = true; camera.fov = 48
	bike = Bike.new(); bike.apply_definition(load("res://data/vehicles/bike.tres"))
	root.add_child(bike); bike.set_physics_process(false); bike.ceiling = 450
	await physics_frame; await physics_frame
	bike.place(Vector3(0, 220.30, 18), Vector3.FORWARD)
	for index in 120:
		await physics_frame; bike._physics_process(DT)
	bike.speed = 20
	var go := Controls.Intent.new(); go.throttle = .6; bike.apply(go)
	var launched := false; var apex := false; var touchdown := false
	for index in 420:
		await physics_frame; bike._physics_process(DT)
		camera.global_position = bike.global_position + Vector3(4.5, 1.6, 1.7)
		camera.look_at(bike.global_position + Vector3.UP * .8)
		if not launched and not bike.grounded and bike.air_time > .05 and bike.position.z < 1:
			launched = true; await capture("takeoff")
		elif launched and not apex and bike.vertical_vel <= 0:
			apex = true; await capture("apex")
		elif apex and not touchdown and bike.grounded:
			touchdown = true; await capture("landing")
	await capture("settled")
	var file := FileAccess.open(OUTPUT + "/bike-dynamics-captures.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(records, "\t"))
	print("Captured bike dynamics to ",ProjectSettings.globalize_path(OUTPUT)," phases=",records.size())
	quit(0 if launched and apex and touchdown else 1)
