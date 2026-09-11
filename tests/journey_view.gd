extends Node
## Render counter at two viewport sizes with a review fixture representing earned progress.
func _ready() -> void:
	var game:=Game.current
	var controls:=game.use_scripted_controls(); controls.intent.handbrake=true
	game.gm.handoffs_paused=true
	game.bike.place(game.world.database.location_pos(&"villa_rosa_office"),Vector3.FORWARD)
	game.world.streamer.load_all_pending()
	await get_tree().create_timer(.3).timeout
	# Fixture only: this runner does not save or modify a user's progress.
	game.gm.coins=168; game.journey.fuel_ratio=.38
	if not game.journey.open_counter():
		push_error("COUNTER_VIEW_FAILED_OPEN"); get_tree().quit(1); return
	for i in range(5): await get_tree().process_frame
	var output:=game.cli.get_string("out","/tmp/journey_counter.png")
	get_tree().root.get_texture().get_image().save_png(output)
	get_window().size=Vector2i(1280,720)
	for i in range(8): await get_tree().process_frame
	get_tree().root.get_texture().get_image().save_png(output.replace(".png","_1280.png"))
	print("JOURNEY_COUNTER_SCREENSHOTS "+output)
	get_tree().quit()
