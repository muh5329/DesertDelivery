extends SceneTree
## Reference-aligned orthographic turnaround using the actual imported runtime character.
var frame := 0
var output := "res://artifacts/character-match/pass1.png"
var subjects: Array[RiderModel] = []
func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output=arg.substr(6)
	call_deferred("build")
func build() -> void:
	root.mesh_lod_threshold=0.0
	var stage := Node3D.new(); root.add_child(stage)
	var env := Environment.new(); env.background_mode=Environment.BG_COLOR
	env.background_color=Color("d5d4d2"); env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color=Color("ece7df"); env.ambient_light_energy=.60
	var world := WorldEnvironment.new(); world.environment=env; stage.add_child(world)
	var key := DirectionalLight3D.new(); key.rotation_degrees=Vector3(-35,145,0); key.light_energy=.65; key.shadow_enabled=false; stage.add_child(key)
	var fill := DirectionalLight3D.new(); fill.rotation_degrees=Vector3(-20,-55,0); fill.light_energy=.13; stage.add_child(fill)
	var ground := MeshInstance3D.new(); var plane := PlaneMesh.new(); plane.size=Vector2(30,30); ground.mesh=plane
	var mat := StandardMaterial3D.new(); mat.albedo_color=Color("c7c6c4"); ground.material_override=mat; stage.add_child(ground)
	for i in range(4):
		var person := RiderModel.new(); stage.add_child(person); subjects.append(person)
		person.position.x=1.38-i*.92; person.rotation.y=[0,-PI/2,PI,PI/2][i]
		for side in [-1.0,1.0]:
			var arm: Node3D=person.arm_l if side<0 else person.arm_r
			arm.rotation=Vector3(0,0,side*.30); arm.get_node("Elbow").rotation=Vector3.ZERO
		if person._skin_bridge: person._skin_bridge.sync_pose()
	var camera := Camera3D.new(); camera.projection=Camera3D.PROJECTION_ORTHOGONAL; camera.size=2.14
	stage.add_child(camera); camera.look_at_from_position(Vector3(0,.94,-6),Vector3(0,.94,0)); camera.current=true
	for i in range(8): await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	root.get_texture().get_image().save_png(output)
	print("REFERENCE TURNAROUND: ",output)
	quit()
