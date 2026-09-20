extends Node
## Full-render fixed-camera sample. No AAA or target-hardware certification.
var game: Game
func _ready() -> void:
	game=Game.current
	call_deferred("run")

func run() -> void:
	game.use_scripted_controls()
	game.bike.set_physics_process(false)
	game.cam.set_physics_process(false)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	# Avoid macOS occlusion throttling when the editor or another app overlaps the test.
	get_window().always_on_top = true
	Engine.max_fps=0
	if game.cli.has("mesh-lod"):
		get_viewport().mesh_lod_threshold=game.cli.get_float("mesh-lod",1.0)
	if game.cli.has("balanced-render"):
		get_viewport().msaa_3d=Viewport.MSAA_2X
		RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM)
	if game.cli.has("shadow-distance"):
		game.world.island.sun.directional_shadow_max_distance=game.cli.get_float("shadow-distance",160.0)
	var camera:=Camera3D.new(); camera.far=30000.0; add_child(camera); camera.current=true
	game.world.terrain.set_view_camera(camera)
	var result: Dictionary={"date":Time.get_datetime_string_from_system(),"renderer":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name(),"resolution":str(get_viewport().get_visible_rect().size),"world_generation_ms":game.world.generate_ms,"process_ready_ms":Time.get_ticks_msec(),"frames_per_scene":300,"warmup_frames":120,"vsync":"disabled","shadow_distance":game.world.island.sun.directional_shadow_max_distance,"scenes":[]}
	result["character_asset"] = character_asset_stats()
	var home:=game.world.database.location_pos(&"villa_rosa_office")
	var scenes: Array = ["village"] if game.cli.has("village-only") else ["village","wilderness","dense_meadow"]
	if game.cli.has("coastal-only"): scenes = ["harbour", "coast"]
	for scene in scenes:
		var pos: Vector3=home if scene=="village" else Vector3(-2600,game.world.terrain.height_at(-2600,-3600),-3600)
		if scene=="dense_meadow": pos=Vector3(4200,game.world.terrain.height_at(4200,3400),3400)
		if scene=="harbour": pos=game.world.database.location_pos(&"harbour_cafe")
		if scene=="coast": pos=Vector3(-522,5,-200)
		game.bike.global_position=pos
		game.world.expanse.refresh_collision()
		camera.look_at_from_position(pos+Vector3(10,5,12),pos+Vector3(0,1,0))
		if scene=="coast": camera.look_at_from_position(Vector3(-598,38,-326),pos)
		get_window().grab_focus()
		for frame in 120: await get_tree().process_frame
		# Same initial resident clock/stations for each build; simulation then runs normally.
		game.life.load_state({"total_minutes":570.0})
		for settle in 2: await get_tree().process_frame
		var times: Array[float]=[]
		var draws:=0.0; var objects:=0.0
		var focused_frames:=0
		var last:=Time.get_ticks_usec()
		for frame in 300:
			await get_tree().process_frame
			var now:=Time.get_ticks_usec(); times.append((now-last)/1000.0); last=now
			if get_window().has_focus(): focused_frames+=1
			draws+=Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			objects+=Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		var total:=0.0
		for ms in times: total+=ms
		times.sort()
		var row: Dictionary={"scene":scene,"focused_frames":focused_frames,"sample_wall_ms":total,"average_fps":300000.0/total,"median_frame_ms":times[150],"p95_frame_ms":times[285],"p99_frame_ms":times[297],"max_frame_ms":times[-1],"mean_draw_calls":draws/300.0,"mean_visible_objects":objects/300.0,"static_memory_mib":Performance.get_monitor(Performance.MEMORY_STATIC)/1048576.0,"video_memory_mib":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)/1048576.0,"node_count":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),"actors":game.life.actors.size(),"dressing":game.world.expanse.dressing.stats() if game.world.expanse.get("dressing")!=null else {}}
		result.scenes.append(row); print("BENCHMARK ",JSON.stringify(row))
	var directory:=game.cli.get_string("out","res://artifacts/overhaul-2026-09-19")
	var file:=FileAccess.open(directory+"/benchmark.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t")); file.close()
	get_tree().quit()


func character_asset_stats() -> Dictionary:
	var scene: PackedScene=load("res://assets/models/courier_character.glb")
	var model:=scene.instantiate()
	var meshes:=0; var surfaces:=0; var vertices:=0; var triangles:=0
	for node in model.find_children("*","MeshInstance3D",true,false):
		if node.mesh==null: continue
		meshes+=1
		for surface in node.mesh.get_surface_count():
			surfaces+=1
			var arrays: Array=node.mesh.surface_get_arrays(surface)
			var count: int=arrays[Mesh.ARRAY_VERTEX].size()
			vertices+=count
			triangles+=(arrays[Mesh.ARRAY_INDEX].size() if arrays[Mesh.ARRAY_INDEX]!=null and not arrays[Mesh.ARRAY_INDEX].is_empty() else count)/3
	var file:=FileAccess.open("res://assets/models/courier_character.glb",FileAccess.READ)
	var bytes:=file.get_length(); file.close(); model.free()
	return {"bytes":bytes,"mesh_nodes":meshes,"surfaces":surfaces,"vertices":vertices,"triangles":triangles}
