extends Node
## Renders of the Jeep, the Cart and the load panel (Forward+, --facet):
##   start        the jeep parked at the start beside the bike, the cart behind it
##   jeep         the jeep close up (3/4 front; jeep_rear from behind)
##   hitch        the jeep's tow hitch and the cart's drawbar, from the side (cart_load: the load)
##   highway      the jeep towing a loaded cart along an outer highway (highway_front)
##   town         the bike towing the cart through a town street
##   water        the jeep afloat off the island, pontoons down (water_rear: driving back out)
##   panel        the load panel at the villa's warehouse (render it at 1600x900)
## Usage (a Forward+ frame of the whole world is ~5 GB under llvmpipe; the session's memory cap
## is ~6 GB, so keep the load down and split the scenes over runs):
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --audio-driver Dummy --rendering-driver vulkan
##     --resolution 1280x720 -- --facet --quality=low --no-outer-life --test=vehicle_shots --out=DIR
##     [--only=start,jeep,hitch,highway,town] [--settle=10]

var game: Game
var sc: Controls.Scripted
var out := "/tmp/vehicle_shots"
var settle := 10
var only: PackedStringArray
var cam: Camera3D
var follow: Node3D
var follow_offset := Vector3.ZERO     # in the followed node's frame (x right, y up, z back)
var follow_look := Vector3.ZERO


func _ready() -> void:
	game = Game.current
	sc = game.use_scripted_controls()
	out = game.cli.get_string("out", out)
	settle = game.cli.get_int("settle", settle)
	only = game.cli.get_string("only", "").split(",", false)
	game.encounters.ambush_enabled = false
	game.vitals.health.invulnerable = 1e9
	DirAccess.make_dir_recursive_absolute(out)
	Engine.max_physics_steps_per_frame = 64
	cam = Camera3D.new(); cam.fov = 55.0; cam.far = 30000; cam.near = 0.1
	add_child(cam)
	game.world.terrain.set_view_camera(cam)
	_run.call_deferred()


func _want(n: String) -> bool:
	return only.is_empty() or n in only


func frames(n: int) -> void:
	for i in n: await get_tree().physics_frame


func _hud(on: bool) -> void:
	game.hud.visible = on
	var ui := game.get_node_or_null("UI")
	if ui:
		for c in ui.get_children():
			if c is CanvasLayer and c != game.cargo_panel: c.visible = on


func _process(_d: float) -> void:
	if follow == null or not is_instance_valid(follow): return
	var b := Basis(Vector3.UP, follow.global_rotation.y)
	cam.global_position = follow.global_position + b * follow_offset
	cam.look_at(follow.global_position + b * follow_look, Vector3.UP)


## Between shots the camera looks at the empty sky (llvmpipe draws a frame in seconds; the sky is
## cheap) and physics may run many steps a frame, so set-ups and drives go at full speed; a shot
## is drawn for `settle` frames and saved.
func _shoot(name: String) -> void:
	print("[shots] drawing ", name)
	var outer: OuterWorld = game.world.outer
	if outer and outer.ok:
		outer.view.update_selection(cam.global_position, -cam.global_basis.z)
		outer.roads.flush()
		outer.flora.flush()
	for i in settle: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var p := "%s/%s.png" % [out, name]
	img.save_png(p)
	print("saved ", p)
	_sky_cam()


func _sky_cam() -> void:
	follow = null
	var c := game.rider.courier().global_position
	cam.global_position = c + Vector3(0, 400, 0)
	cam.look_at(c + Vector3(0.01, 1000, 0), Vector3.FORWARD)


func _stream(at: Vector3) -> void:
	game.world.set_focus(game.rider.courier())
	var outer: OuterWorld = game.world.outer
	if outer and outer.ok:
		outer.refresh_collision()
		outer.view.update_selection(cam.global_position, (at - cam.global_position).normalized())
		outer.roads.flush()
		outer.flora.flush()
	game.world.streamer.load_all_pending()


func _drive(v: Vehicle) -> void:
	var r := game.rider
	if r.vehicle == v and r.is_riding(): return
	if r.is_riding(): r.request_dismount()
	await frames(3)
	r._set_vehicle(v)
	r._set_mode(Rider.Mode.RIDING if v == game.bike else Rider.Mode.DRIVING)
	await frames(3)


## Pure pursuit along road samples for `seconds` (the Autopilot's steering).
func _pursue(v: Vehicle, pts: PackedVector3Array, cap: float, seconds: float) -> void:
	var pi := 1
	var t := 0.0
	while t < seconds:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		var pos := v.global_position
		while pi < pts.size() - 1 and Vector2(pts[pi].x - pos.x, pts[pi].z - pos.z).length() < 7.0: pi += 1
		if pi >= pts.size() - 2: break
		var to := pts[pi] - pos; to.y = 0
		sc.intent.steer = clampf(-v.flat_forward().signed_angle_to(to.normalized(), Vector3.UP) * 1.8, -1.0, 1.0)
		sc.intent.throttle = 1.0 if v.speed < cap else 0.0
		sc.intent.brake = 0.4 if v.speed > cap + 2.0 else 0.0


func _run() -> void:
	_sky_cam()
	cam.current = true
	_hud(false)
	await frames(10)
	print("[shots] ready")
	if _want("start"): await _start()
	if _want("jeep"): await _jeep()
	if _want("hitch"): await _hitch()
	if _want("highway"): await _highway()
	if _want("town"): await _town()
	if _want("water"): await _water()
	if _want("panel"): await _panel()
	get_tree().quit()


func _start() -> void:
	var bike := game.bike; var jeep := game.jeep
	var mid := (bike.global_position + jeep.global_position + game.cart.global_position) / 3.0
	var side := jeep.global_transform.basis.x.normalized()
	follow = null
	cam.global_position = mid + side * 13.0 - jeep.flat_forward() * 6.0 + Vector3.UP * 4.5
	cam.look_at(mid + Vector3.UP * 0.8, Vector3.UP)
	_stream(mid)
	await _shoot("start")


func _jeep() -> void:
	var jeep := game.jeep
	follow = null
	var f := jeep.flat_forward(); var side := jeep.global_transform.basis.x.normalized()
	cam.global_position = jeep.global_position + f * 5.2 + side * 3.6 + Vector3.UP * 1.9
	cam.look_at(jeep.global_position + Vector3.UP * 1.0, Vector3.UP)
	_stream(jeep.global_position)
	await _shoot("jeep")
	cam.global_position = jeep.global_position - f * 5.5 - side * 3.2 + Vector3.UP * 2.3
	cam.look_at(jeep.global_position + Vector3.UP * 0.9, Vector3.UP)
	await _shoot("jeep_rear")


func _hitch() -> void:
	var jeep := game.jeep; var cart := game.cart
	cart.place_behind(jeep)
	game.hitch._couple(jeep)
	cart.inventory.clear()
	cart.inventory.add("planks", 20); cart.inventory.add("wine", 4); cart.inventory.add("grain", 15); cart.inventory.add("fuel_can", 2)
	await frames(30)
	follow = null
	var side := jeep.global_transform.basis.x.normalized()
	var h := jeep.hitch_point()
	cam.global_position = h + side * 4.2 + Vector3.UP * 0.9 + jeep.flat_forward() * 0.3
	cam.look_at(h + Vector3.DOWN * 0.1, Vector3.UP)
	_stream(h)
	await _shoot("hitch")
	cam.global_position = cart.global_position + side * 3.5 - jeep.flat_forward() * 4.5 + Vector3.UP * 3.2
	cam.look_at(cart.global_position + Vector3.UP * 0.8, Vector3.UP)
	await _shoot("cart_load")


func _highway() -> void:
	var outer: OuterWorld = game.world.outer
	if outer == null or not outer.ok: return
	var path := PackedVector3Array()
	for e in outer.roads.roads:
		if String(e.get("cls", "")) != "highway" or e.get("seam", false): continue
		var P: PackedVector3Array = e.pts
		if P.size() < 400: continue
		# the straightest 160-sample stretch, well away from the ends
		var best := INF
		for k in range(60, P.size() - 220, 20):
			var a := P[k + 80] - P[k]; var b := P[k + 160] - P[k + 80]
			a.y = 0; b.y = 0
			var bend := absf(a.signed_angle_to(b, Vector3.UP)) + absf(P[k + 160].y - P[k].y) * 0.02
			if bend < best: best = bend; path = P.slice(k, k + 170)
		break
	if path.is_empty(): return
	var jeep := game.jeep; var cart := game.cart
	if game.hitch.tow_vehicle(): game.hitch._decouple()
	var fwd := path[4] - path[0]; fwd.y = 0
	jeep.place(path[0] + Vector3.UP * 0.4, fwd.normalized())
	cart.place_behind(jeep)
	game.hitch._couple(jeep)
	cart.inventory.clear(); cart.inventory.add("blocks", 30); cart.inventory.add("planks", 25); cart.inventory.add("oil", 6)
	await _drive(jeep)
	_stream(jeep.global_position)
	await frames(30)
	follow = jeep
	follow_offset = Vector3(5.5, 2.6, 7.5); follow_look = Vector3(0, 0.8, 2.4)
	await _pursue(jeep, path, 12.0, 7.0)
	var road: Dictionary = game.world.terrain.nearest_road(jeep.global_position)
	print("[shots] highway: %.1f m off the road centre at %.1f m/s" % [(road.point as Vector3).distance_to(jeep.global_position), jeep.speed])
	# the stills: the rig rolls to a stop on the lane while the frames draw
	sc.intent = Controls.Intent.new(); sc.intent.brake = 0.35
	_stream(jeep.global_position)
	await _shoot("highway")
	follow = jeep
	follow_offset = Vector3(-7.5, 3.6, -7.0); follow_look = Vector3(0, 0.6, 2.8)
	await _shoot("highway_front")
	sc.intent = Controls.Intent.new(); sc.intent.brake = 1.0
	await frames(90)
	sc.intent = Controls.Intent.new()


func _town() -> void:
	var outer: OuterWorld = game.world.outer
	if outer == null or not outer.ok: return
	var path := PackedVector3Array()
	for tid in ["puerto_alto", "sarmada", "campo_real", "isola_serena", "valdoro"]:
		var ri: int = outer.roads.by_id.get("street.%s.main" % tid, -1)
		if ri < 0: continue
		var P: PackedVector3Array = outer.roads.roads[ri].pts
		if P.size() > 80:
			path = P.slice(10, P.size() - 5); break
	if path.is_empty(): return
	var bike := game.bike; var cart := game.cart
	if game.hitch.tow_vehicle(): game.hitch._decouple()
	var fwd := path[4] - path[0]; fwd.y = 0
	bike.place(path[0] + Vector3.UP * 0.3, fwd.normalized())
	cart.place_behind(bike)
	game.hitch._couple(bike)
	cart.inventory.clear(); cart.inventory.add("bread", 20); cart.inventory.add("fish", 15); cart.inventory.add("cloth", 20)
	await _drive(bike)
	_stream(bike.global_position)
	await frames(40)
	follow = bike
	follow_offset = Vector3(-4.6, 3.4, 6.8); follow_look = Vector3(0, 0.7, 2.0)
	await _pursue(bike, path, 7.0, 6.0)
	sc.intent = Controls.Intent.new(); sc.intent.brake = 0.35
	_stream(bike.global_position)
	await _shoot("town")
	sc.intent = Controls.Intent.new(); sc.intent.brake = 1.0
	await frames(90)
	sc.intent = Controls.Intent.new()
	game.hitch._decouple()


func _water() -> void:
	var t: Terrain = game.world.terrain
	var jeep := game.jeep
	if game.hitch.tow_vehicle(): game.hitch._decouple()
	var beach: Dictionary = await load("res://tests/beach_finder.gd").find(game, jeep)
	if beach.is_empty(): return
	jeep.place(beach.land, beach.dir)
	await _drive(jeep)
	_stream(jeep.global_position)
	await frames(20)
	sc.intent.throttle = 1.0
	for i in 60 * 14:
		await get_tree().physics_frame
		if jeep.afloat: break
	for i in 60 * 3: await get_tree().physics_frame
	sc.intent.throttle = 0.7; sc.intent.steer = 0.35
	follow = jeep
	follow_offset = Vector3(6.5, 2.4, 3.5); follow_look = Vector3(0, 0.5, 0.5)
	_stream(jeep.global_position)
	await _shoot("water")
	follow = jeep
	sc.intent.steer = 0.0
	follow_offset = Vector3(-6.5, 3.4, 9.5); follow_look = Vector3(0, 0.6, 0)
	await _shoot("water_rear")
	sc.intent = Controls.Intent.new()


func _panel() -> void:
	follow = null
	var jeep := game.jeep; var cart := game.cart
	var core: ColonyTown = game.colony.economy.town("core")
	var sp := game.world.road_spawn(core.hall + Vector3(10, 0, 0), core.hall)
	if game.hitch.tow_vehicle(): game.hitch._decouple()
	jeep.place(sp.pos, sp.forward)
	cart.place_behind(jeep)
	game.hitch._couple(jeep)
	cart.inventory.clear(); cart.inventory.add("planks", 20); cart.inventory.add("fuel_can", 2); cart.inventory.add("wine", 4)
	jeep.bed.clear(); jeep.bed.add("tools", 6)
	game.cargo.pack.clear(); game.cargo.pack.add("bread", 6); game.cargo.pack.add("ammo_crate", 1)
	await _drive(jeep)
	game.rider.request_dismount()
	await frames(5)
	game.player.place(cart.global_position + cart.global_basis.x * 1.8, jeep.flat_forward())
	await frames(20)
	cam.global_position = game.player.global_position + Vector3(6, 4, 6)
	cam.look_at(cart.global_position, Vector3.UP)
	_stream(cart.global_position)
	await frames(20)
	_hud(true)
	game.hud.visible = true
	var ok: bool = game.cargo_panel.open()
	print("panel open: ", ok, " holds: ", game.cargo.holds().map(func(h): return h.id))
	game.cargo_panel.source = 2 if game.cargo_panel._holds.size() > 2 else 0
	game.cargo_panel._refresh(true)
	await _shoot("panel")
	game.cargo_panel.close_panel()
	_hud(false)
