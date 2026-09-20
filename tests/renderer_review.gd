extends Node
## Compare renderer output at fixed authored viewpoints after shader/streaming warmup.
func _ready() -> void: call_deferred("run")
func run() -> void:
	var game:=Game.current
	game.use_scripted_controls();game.bike.set_physics_process(false);game.cam.set_physics_process(false)
	if game.cli.has("shadow-distance"):
		game.world.island.sun.directional_shadow_max_distance=game.cli.get_float("shadow-distance",320.0)
	for layer in game.find_children("*","CanvasLayer",true,false):layer.visible=false
	game.bike.visible=false;game.player.visible=false
	var camera:=Camera3D.new();camera.far=20000;camera.fov=62;add_child(camera);camera.current=true
	game.world.terrain.set_view_camera(camera)
	var table:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://reference/spots.json"))
	var out:=game.cli.get_string("out","res://artifacts/performance-controls/visual-final")
	DirAccess.make_dir_recursive_absolute(out)
	for name in game.cli.get_string("spots","villa,cliff_coast").split(","):
		var spot:Dictionary=table[name]
		var from:=Vector3(spot.from[0],spot.from[1],spot.from[2]);var at:=Vector3(spot.at[0],spot.at[1],spot.at[2])
		if spot.get("ground_relative",false):from.y+=game.world.terrain.height_at(from.x,from.z);at.y+=game.world.terrain.height_at(at.x,at.z)
		game.bike.global_position=at;game.world.streamer.load_all_pending();camera.look_at_from_position(from,at)
		for frame in 120:await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out+"/"+name+".png")
	get_tree().quit()
