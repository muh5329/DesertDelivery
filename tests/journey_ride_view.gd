extends Node
## Visual review through the real riding camera and HUD, with scripted throttle only.
var game: Game
var out: String
var controls: Controls.Scripted
var frame:=0
var busy:=false
func _ready() -> void:
	game=Game.current; controls=game.use_scripted_controls()
	out=game.cli.get_string("out","/tmp/feel-ride")
	DirAccess.make_dir_recursive_absolute(out)
	game.hud._title_t=0; game.hud._title.hide()
	game.hud._controls_timer=0; game.hud._prompt_bg.hide()
	game.hud._msg_timer=0; game.hud._message.text=""; game.hud._msg_queue.clear()
	var road:=game.world.terrain.nearest_road(Vector3(235,0,-200))
	game.bike.place(road.point,road.tangent)
	game.world.streamer.load_all_pending(); game.cam.snap_to_target()
func _physics_process(_delta: float) -> void:
	frame+=1
	controls.intent.throttle=.42 if frame<165 else 0
	controls.intent.brake=1.0 if frame>=165 else 0
	if frame==120 and not busy:
		busy=true
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out+"/riding.png")
		busy=false
	if frame==230:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out+"/stopped.png")
		print("RIDING VIEW PASS: real camera and live HUD captured")
		get_tree().quit()
