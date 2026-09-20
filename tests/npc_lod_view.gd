extends SceneTree
## Side-by-side native-render comparison at actual LOD transition distances.
## Godot --path . -s tests/npc_lod_view.gd -- --out=<folder>
var out := "res://artifacts/performance-controls/npc-lod-visual"
func _init() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): out=argument.substr(6)
	call_deferred("run")
func run() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	var environment := Environment.new(); environment.background_mode=Environment.BG_COLOR
	environment.background_color=Color(.64,.68,.72)
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color=Color(.8,.85,1);environment.ambient_light_energy=.45
	var world_environment:=WorldEnvironment.new();world_environment.environment=environment;root.add_child(world_environment)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-35,155,0);sun.light_energy=.8;root.add_child(sun)
	var camera:=Camera3D.new();camera.fov=58;root.add_child(camera);camera.current=true
	var people:Array[RiderModel]=[]
	for index in 2:
		var person:=RiderModel.new();root.add_child(person)
		person.position.x=-1.1 if index==0 else 1.1
		person.set_palette(Color(.38,.55,.72),Color(.73,.55,.29),Color(.58,.28,.08),Color(.90,.71,.53))
		person.enable_resident_lod()
		person.animate("walk",1.35,.13);person.sync_resident_pose()
		person.set_resident_lod_distance(17 if index==0 else 23)
		people.append(person)
		var label:=Label3D.new();label.text="FULL 103,650 tris" if index==0 else "LOD 13,451 tris"
		label.font_size=32;label.pixel_size=.004;label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
		root.add_child(label);label.position=person.position+Vector3.UP*2.25
	for distance in [18.0,22.0,4.5]:
		camera.look_at_from_position(Vector3(0,1.05,-distance),Vector3(0,1.05,0))
		for frame in 12:await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out+"/full-vs-lod-%sm.png"%str(distance))
		print("NPC LOD VIEW captured distance ",distance)
	quit()
