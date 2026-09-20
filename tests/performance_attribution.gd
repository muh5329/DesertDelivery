extends Node
## Diagnostic-only toggles. Restores original state between cases; does not change production settings.
func _ready() -> void: call_deferred("run")

func run() -> void:
	var game:=Game.current
	game.use_scripted_controls(); game.bike.set_physics_process(false); game.cam.set_physics_process(false)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED); Engine.max_fps=0
	var camera:=Camera3D.new(); camera.far=30000; add_child(camera); camera.current=true
	var home:=game.world.database.location_pos(&"villa_rosa_office")
	game.bike.global_position=home; game.world.terrain.set_view_camera(camera)
	camera.look_at_from_position(home+Vector3(10,5,12),home+Vector3(0,1,0))
	var rows: Array=[]
	var original_scale:=get_viewport().scaling_3d_scale
	for mode in ["baseline","life_frozen","life_frozen_hidden_residents","baseline_restore","resolution_075","baseline_final"]:
		game.life.set_physics_process(mode not in ["life_frozen","life_frozen_hidden_residents"])
		for actor in game.life.actors.values(): actor.visible=mode!="life_frozen_hidden_residents"
		get_viewport().scaling_3d_scale=.75 if mode=="resolution_075" else original_scale
		for frame in 90: await get_tree().process_frame
		var frames: Array[float]=[]
		var draw:=0.0; var process:=0.0; var physics:=0.0
		var last:=Time.get_ticks_usec()
		for frame in 180:
			await get_tree().process_frame
			var now:=Time.get_ticks_usec(); frames.append((now-last)/1000.0); last=now
			draw+=Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			process+=Performance.get_monitor(Performance.TIME_PROCESS)*1000.0
			physics+=Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0
		var total:=0.0
		for value in frames: total+=value
		frames.sort()
		var row: Dictionary={"mode":mode,"fps":180000.0/total,"median_ms":frames[90],"p95_ms":frames[171],"draw_calls":draw/180.0,"cpu_process_ms":process/180.0,"cpu_physics_ms":physics/180.0,"actors":game.life.actors.size(),"render_scale":get_viewport().scaling_3d_scale}
		rows.append(row); print("ATTRIBUTION ",JSON.stringify(row))
	var out:=game.cli.get_string("out","res://artifacts/overhaul-2026-09-19")
	var file:=FileAccess.open(out+"/attribution.json",FileAccess.WRITE); file.store_string(JSON.stringify(rows,"\t")); file.close()
	get_tree().quit()
