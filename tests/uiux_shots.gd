extends Node
## Render tool for the loading screen and the map (Forward+, --facet):
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --audio-driver Dummy --rendering-driver vulkan \
##     -- --facet --quality=low --test=uiux_shots --out=DIR --size=1600x900 --views=highway,town
## Views: keyart (the loading screen's picture, no UI), highway (the HUD and the minimap riding a
## highway), town (on foot in a town, close zoom), flying (the minimap zoomed out in flight),
## fullmap (the M map with a waypoint), loading (the loading screen over a long move).
## The boot's own loading screen: add --boot-shot=DIR (Game._boot saves a frame per stage).

var game: Game
var out := "/tmp/uiux_shots"
var tag := ""
var sc: Controls.Scripted


func _ready() -> void:
	game = Game.current
	out = game.cli.get_string("out", out)
	DirAccess.make_dir_recursive_absolute(out)
	var sz := game.cli.get_string("size", "1600x900")
	tag = sz
	var wh := sz.split("x")
	get_window().size = Vector2i(int(wh[0]), int(wh[1]))
	call_deferred("run")


func _snap(name: String, frames := 30) -> void:
	for i in range(frames): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var p := "%s/%s_%s.png" % [out, name, tag]
	img.save_png(p)
	print("saved ", p, " ", img.get_size())


func _plaza(tid: String) -> Vector3:
	for t in game.world.outer.plan().towns:
		if t.id == tid: return Vector3(t.plaza[0], t.plaza[1], t.plaza[2])
	return Vector3.ZERO


## The courier on his bike on the road nearest `near`, facing `toward`.
func _ride_at(near: Vector3, toward: Vector3) -> Dictionary:
	var sp := game.world.road_spawn(near, toward)
	if game.rider.is_on_foot(): game.rider.request_mount()
	for i in range(10): await get_tree().physics_frame
	game.rider.respawn_at(sp.pos, sp.forward)
	game.world.set_focus(game.rider.courier())
	game.world.outer.refresh_collision()
	game.world.streamer.load_all_pending()
	game.world.outer.roads.flush()
	game.world.outer.flora.flush()
	game.cam.snap_to_target()
	return sp


func run() -> void:
	sc = game.use_scripted_controls()
	game.hud.skip_title()
	game.hud._controls_timer = 0.0
	game.encounters.ambush_enabled = false
	game.vitals.health.invulnerable = 1e9
	game.colony.economy.ensure_shipping()
	game.colony.economy.shipping.wait()
	var views := game.cli.get_string("views", "highway,town,flying,fullmap").split(",")
	for v in views:
		match v:
			"keyart": await _keyart()
			"highway": await _highway()
			"town": await _town()
			"flying": await _flying()
			"fullmap": await _fullmap()
			"loading": await _loading()
	get_tree().quit(0)


func _hide_ui(hide: bool) -> void:
	for c in game.get_node("UI").get_children():
		if c is CanvasLayer: c.visible = not hide
	game.hud.visible = not hide


func _keyart() -> void:
	_hide_ui(true)
	# golden hour (sunset ~19:41), the courier on the coast highway east of Sarmada, riding in
	game.life.advance_to(game.life.total_minutes + (19.0 * 60.0 + 2.0 - fmod(game.life.total_minutes, 1440.0)))
	var pl := _plaza("sarmada")
	var sp: Dictionary = await _ride_at(pl + Vector3(420, 0, 170), pl)
	var at: Vector3 = sp.pos
	var fwd: Vector3 = sp.forward
	var side := fwd.cross(Vector3.UP).normalized()
	var cam := Camera3D.new(); cam.far = 30000.0; cam.near = 0.1
	add_child(cam)
	cam.current = true
	game.world.terrain.set_view_camera(cam)
	var shots := {
		# behind and above the courier: the road running down to the walled town in the evening haze
		"keyart": [at - fwd * 9.5 - side * 3.2 + Vector3.UP * 4.2, at + fwd * 150.0 + side * 18.0 - Vector3.UP * 6.0, 52.0],
	}
	for key in shots:
		var v: Array = shots[key]
		var eye: Vector3 = v[0]
		eye.y = maxf(eye.y, game.world.terrain.height_at(eye.x, eye.z) + 1.0)
		cam.fov = v[2]
		cam.look_at_from_position(eye, v[1], Vector3.UP)
		await _snap(key, 45)
	cam.current = false
	game.cam.make_current()
	game.world.terrain.set_view_camera(game.cam)
	cam.queue_free()
	_hide_ui(false)


func _highway() -> void:
	game.map.zoom_level = 1
	var pl := _plaza("puerto_alto")
	# on the ring highway south-west of Puerto Alto, riding toward it
	var sp: Dictionary = await _ride_at(pl + Vector3(-1500, 0, 600), pl)
	game.minimap.snap()
	await _snap("hud_highway", 40)


func _town() -> void:
	game.map.zoom_level = 0
	var pl := _plaza("sarmada")
	await _ride_at(pl + Vector3(40, 0, 60), pl)
	game.rider.request_dismount()
	for i in range(60): await get_tree().physics_frame
	game.cam.snap_to_target()
	game.minimap.snap()
	await _snap("hud_town", 40)


func _flying() -> void:
	game.map.zoom_level = 1
	var sp: Dictionary = await _ride_at(Vector3(900, 0, -420), Vector3(2600, 0, -900))
	var bike := game.bike
	if not bike.wings_out: bike.toggle_wings()
	var at: Vector3 = sp.pos + Vector3.UP * 260.0
	bike.global_position = at
	bike.airborne = true
	bike.grounded = false
	bike.took_off.emit()
	sc.intent.throttle = 1.0
	game.cam.snap_to_target()
	for i in range(40): await get_tree().physics_frame
	game.world.set_focus(bike)
	game.world.outer.refresh_collision()
	game.minimap.snap()
	await _snap("hud_flying", 30)
	sc.intent.throttle = 0.0


func _fullmap() -> void:
	var home := game.world.database.location_pos(&"villa_rosa_office")
	await _ride_at(home + Vector3(40, 0, 0), home)
	game.map.set_waypoint(Vector3(7789.0, 0.0, 1608.0))
	game.full_map.open_panel()
	game.full_map.center = Vector2(2600, 300)
	game.full_map.mpp = 16.0
	await _snap("fullmap", 20)
	game.full_map.center = Vector2(-200, -100)
	game.full_map.mpp = 2.2
	await _snap("fullmap_core", 20)
	game.full_map.close_panel()
	game.map.clear_waypoint()


func _loading() -> void:
	game.loading.enabled = true
	var pl := _plaza("valdoro")
	var sp := game.world.road_spawn(pl + Vector3(60, 0, 0), pl)
	game.relocate("Coach to Valdoro", func(): game.rider.respawn_at(sp.pos, sp.forward))
	await _snap("loading_travel", 6)
	game.loading.dismiss()
	game.loading.enabled = false
