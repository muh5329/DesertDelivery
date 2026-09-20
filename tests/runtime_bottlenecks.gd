extends Node
func _ready() -> void: call_deferred("run")
func run() -> void:
	var game:=Game.current
	game.use_scripted_controls(); game.bike.set_physics_process(false); game.cam.set_physics_process(false)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED); Engine.max_fps=0
	var camera:=Camera3D.new(); camera.far=30000; add_child(camera); camera.current=true
	var home:=game.world.database.location_pos(&"villa_rosa_office")
	game.bike.global_position=home; game.world.terrain.set_view_camera(camera)
	camera.look_at_from_position(home+Vector3(10,5,12),home+Vector3(0,1,0))
	for frame in 120: await get_tree().process_frame
	var rows: Array=[]
	for mode in ["baseline","no_residents","no_shadows","no_chunks","no_msaa","baseline_final"]:
		game.world.island.sun.shadow_enabled=mode!="no_shadows"
		game.world.streamer.visible=mode!="no_chunks"
		get_viewport().msaa_3d=Viewport.MSAA_DISABLED if mode=="no_msaa" else Viewport.MSAA_4X
		for actor in game.life.actors.values(): actor.visible=mode!="no_residents"
		for frame in 60: await get_tree().process_frame
		var times: Array[float]=[]; var draws:=0.0; var primitives:=0.0
		var last:=Time.get_ticks_usec()
		for frame in 180:
			await get_tree().process_frame
			var now:=Time.get_ticks_usec(); times.append((now-last)/1000.0); last=now
			draws+=Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			primitives+=Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		var sum:=0.0
		for t in times: sum+=t
		times.sort()
		var row:={"mode":mode,"fps":180000/sum,"median_ms":times[90],"p95_ms":times[171],"draws":draws/180,"primitives":primitives/180}
		rows.append(row); print("BOTTLENECK ",JSON.stringify(row))
	var file:=FileAccess.open("res://artifacts/performance-controls/bottlenecks.json",FileAccess.WRITE); file.store_string(JSON.stringify(rows,"\t")); file.close()
	get_tree().quit()
