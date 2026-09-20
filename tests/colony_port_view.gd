extends Node
## Actual rendered integration review: all mayor pages and courier dodge phases.
var game: Game
var output := "res://artifacts/colony-port"
func _ready() -> void: call_deferred("run")
func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output+"/"+name+".png")
func run() -> void:
	game = Game.current
	game.hud._title_t = 0.0
	game.hud._title.hide()
	game.use_scripted_controls()
	game.rider._set_mode(Rider.Mode.ON_FOOT)
	var at := game.bike.global_position + Vector3(2,0,0)
	at.y = game.world.terrain.height_at(at.x,at.z)+.1
	game.player.place(at,Vector3.FORWARD)
	for frame in 100: await get_tree().physics_frame
	game.mayor.set_active(true)
	if not game.mayor.active:
		push_error("Mayor entry failed in visual fixture");get_tree().quit(1);return
	for page in ["Jobs","Areas","Build","Paths"]:
		game.mayor.current_page=page;game.mayor.build_page()
		for frame in 35: await get_tree().process_frame
		await capture("mayor-"+page.to_lower())
	game.mayor.close_panel()
	for frame in 10: await get_tree().physics_frame
	game.cam.set_look(0,.12)
	await capture("courier-stamina")
	game.scripted_controls.intent.move=Vector2(0,1)
	game.scripted_controls.intent.press(Controls.DODGE)
	for phase in 3:
		for frame in 14: await get_tree().physics_frame
		await capture("courier-dodge-"+str(phase))
	game.scripted_controls.intent.move=Vector2.ZERO
	for frame in 80: await get_tree().physics_frame
	await capture("courier-after-dodge")
	get_tree().quit()
