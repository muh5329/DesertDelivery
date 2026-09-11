extends Node
## Actual resident/traffic views, with the game simulation running throughout.
var main: Game
var camera: Camera3D

func _ready() -> void:
	main=Game.current
	call_deferred("capture")

func capture() -> void:
	main.use_scripted_controls()
	main.cam.set_physics_process(false)
	main.bike.set_physics_process(false)
	main.hud.visible=false
	main.bike.visible=false
	main.player.visible=false
	camera=Camera3D.new(); camera.fov=48; add_child(camera); camera.current=true
	main.world.terrain.set_view_camera(camera)
	var out:=main.cli.get_string("out","/tmp/island-life-review")
	DirAccess.make_dir_recursive_absolute(out)
	var subjects: Array[Resident]=[main.life.residents[0],main.life.residents[6]]
	for index in subjects.size():
		var record:=subjects[index]
		main.bike.global_position=record.position+Vector3(8,1,8)
		for i in 8: await get_tree().physics_frame
		main.world.streamer.load_all_pending()
		for i in 35:
			var position: Vector3=record.position
			var forward: Vector3=record.forward
			var side:=forward.cross(Vector3.UP)
			var eye:=position+forward*5.5+side*4.8+Vector3.UP*2.6
			if not record.driving:
				var road:=main.world.terrain.nearest_road(position)
				eye=road.point+road.tangent*3.0+Vector3.UP*1.8
			camera.look_at_from_position(eye,position+Vector3.UP*.95)
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_tree().root.get_texture().get_image().save_png(out+"/resident_%d.png"%index)
		print("RESIDENT VIEW ",record.name," / ",record.status," / ",record.position)
	get_tree().quit()
