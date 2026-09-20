extends Node
## Measure actual running gameplay and streaming; report frame-time tails, not just average FPS.
func _ready() -> void: call_deferred("run")
func run() -> void:
	var game:=Game.current
	game.use_scripted_controls()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED); Engine.max_fps=0
	get_window().grab_focus()
	for i in 120: await get_tree().process_frame
	var times:Array[float]=[];var last:=Time.get_ticks_usec();var start:=Time.get_ticks_msec()
	var origin:=game.bike.global_position
	var stalls:Array=[]
	for frame in 1800:
		game.scripted_controls.intent.throttle=.65
		game.scripted_controls.intent.steer=sin((Time.get_ticks_msec()-start)*.0004)*.14
		await get_tree().process_frame
		var now:=Time.get_ticks_usec();times.append((now-last)/1000.0);last=now
		if times[-1]>35.0:stalls.append({"frame":frame,"ms":times[-1],"position":str(game.bike.global_position),"stream":game.world.streamer.stats(),"physics_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000,"pipeline_draw":Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW),"pipeline_mesh":Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_MESH),"pipeline_specialization":Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SPECIALIZATION)})
	var sum:=0.0
	for t in times:sum+=t
	times.sort()
	var result:={"renderer":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name(),"frames":times.size(),"average_fps":times.size()*1000/sum,"median_ms":times[times.size()/2],"p95_ms":times[int(times.size()*.95)],"p99_ms":times[int(times.size()*.99)],"max_ms":times[-1],"displacement_m":origin.distance_to(game.bike.global_position),"final_speed":game.bike.speed,"streaming":game.world.streamer.stats(),"stalls":stalls}
	print("TRAVERSAL ",JSON.stringify(result))
	var f:=FileAccess.open("res://artifacts/performance-controls/traversal.json",FileAccess.WRITE);f.store_string(JSON.stringify(result,"\t"));f.close()
	get_tree().quit()
