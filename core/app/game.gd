class_name Game
extends Node3D
## The root of the running game. Small on purpose: it boots the managers and wires them, then
## gets out of the way. The scene tree is a temporary view of the authoritative state (the
## WorldDatabase, the entities, the save file), so the tree stays this shape however big the
## world gets:
##
##   Game
##   ├── WorldManager      terrain / sea / sky resident, everything else streamed by chunk
##   ├── EntityManager     registry + simulation tiers (bike, player body, pickups, targets, NPCs...)
##   ├── GameplayManager   DeliverySystem, GunSystem, PlayerVitals, EncounterDirector, (Autopilot)
##   ├── Rider             switches bike / jeep / on-foot and routes ControlIntents
##   ├── HitchSystem       the Cart and what tows it (the Rig)
##   ├── CargoSystem       the courier's pack, loads and stores (the G panel is CargoPanel under UI)
##   ├── ChaseCamera
##   ├── BikeAudio         procedural engine shared by the active vehicle
##   ├── UI                HUD
##   └── Debug             DebugOverlay (F3)
##
## Autoloads: `Events` (EventBus) and `Saves` (SaveManager). Nothing else is global.

static var current: Game
## The UI (authored at 1600x900, canvas_items stretch) is never drawn smaller than this: a
## 1280x720 window scales it by 0.85, not 0.8, so a 16 px label is 13.6 px on screen.
const UI_MIN_SCALE := 0.85

var cli := CliArgs.new()
var state := GameState.new()
var config: WorldConfig

var world: WorldManager
var entities: EntityManager
var gameplay: GameplayManager
var rider: Rider
var bike: Bike
var jeep: Jeep
var cart: CargoCart
var hitch: HitchSystem
var cargo: CargoSystem
var cargo_panel: CargoPanel
var player: Player
var cam: ChaseCamera
var audio: BikeAudio
var hud: HUD
var debug: DebugOverlay
var life: IslandLife
var panels: PanelStack
var catalogue: ResidentCatalogue
var journey: JourneySystem
var colony: ColonySystem
var mayor: MayorView
## The map: its data and state (WorldMap), the HUD's minimap, the full-screen map (M).
var map: WorldMap
var minimap: Minimap
var full_map: FullMap
var _mayor_player_physics := false
var _mayor_camera_physics := false
var _mayor_hud_visible := true
var player_controls: Controls.Keyboard
var scripted_controls: Controls.Scripted

# convenience aliases used by tests and tools
var gm: DeliverySystem:
	get: return gameplay.delivery
var gun: GunSystem:
	get: return gameplay.gun
var encounters: EncounterDirector:
	get: return gameplay.encounters
var vitals: PlayerVitals:
	get: return gameplay.vitals
var level: Island:
	get: return world.island
var autopilot: Autopilot:
	get: return gameplay.autopilot

var _quit_armed := 0.0
var _shot_t := 0.0
var _shot_n := 0


## The boot, stage by stage: [id, text on the loading screen, weight (its share of a typical boot,
## measured), what it does]. `_boot` draws one loading-screen frame between stages.
func _boot_stages() -> Array:
	var stages: Array = []
	var world_text := {&"terrain": "Shaping the island", &"ground": "Painting the ground", &"core": "Laying out the core island",
		&"outer_data": "Unrolling the outer country", &"outer_roads": "Surveying the roads",
		&"outer_towns": "Raising the towns", &"outer_wild": "Rivers and wilderness",
		&"sky": "Sky, sea and light", &"textures": "Uploading the building textures"}
	world = WorldManager.new(); world.name = "WorldManager"; add_child(world)
	for step in world.setup_steps(config):
		stages.append([step[0], world_text.get(step[0], String(step[0])), BOOT_WEIGHTS.get(step[0], 1.0), step[1]])
	stages.append([&"vehicles", "Fuelling the bike and the jeep", BOOT_WEIGHTS.vehicles, _boot_entities])
	stages.append([&"gameplay", "Deliveries, the Garand and the camps", BOOT_WEIGHTS.gameplay, _boot_gameplay])
	stages.append([&"life", "Waking the islanders", BOOT_WEIGHTS.life, func():
		life = IslandLife.new(); life.name = "IslandLife"; world.add_child(life)
		life.setup(world, entities)])
	stages.append([&"colony", "Colonies and shipping lanes", BOOT_WEIGHTS.colony, func():
		colony = ColonySystem.new(); colony.name = "Colony"; add_child(colony)
		colony.setup(self)])
	stages.append([&"ui", "Maps and the HUD", BOOT_WEIGHTS.ui, func():
		_boot_ui()
		_wire()
		_start_controls()])
	stages.append([&"streaming", "Building the world around you", BOOT_WEIGHTS.streaming, _start_world])
	return stages


## Measured on a boot (ms, cloud box); only the ratios matter. The settling after the boot
## (townsfolk, shaders, the first smooth frames) is the bar's last stretch.
const BOOT_WEIGHTS := {&"terrain": 2000.0, &"ground": 2100.0, &"core": 2450.0, &"outer_data": 420.0,
	&"outer_roads": 330.0, &"outer_towns": 390.0, &"outer_wild": 120.0, &"sky": 20.0, &"textures": 150.0,
	&"vehicles": 90.0, &"gameplay": 130.0, &"life": 190.0, &"colony": 50.0, &"ui": 90.0, &"streaming": 150.0}
## The share of the bar the boot stages fill; the rest is the settling.
const BOOT_SHARE := 0.92

var loading: LoadingScreen
## True once every boot stage has run (tests start then); `boot_finished` is emitted at that point.
var booted := false
signal boot_finished
var boot_ms: Dictionary = {}
## Frames the boot took (one per stage plus the first): the staging's whole overhead.
var boot_frames := 0


func _ready() -> void:
	current = self
	_read_cli()
	config = load("res://data/config/world.tres")
	loading = LoadingScreen.new(); loading.name = "LoadingScreen"; add_child(loading)
	loading.enabled = _interactive()
	_boot()


## A person is playing: not a test, a tool, the autotest or the screenshot run, not headless.
func _interactive() -> bool:
	return DisplayServer.get_name() != "headless" and not cli.has("test") and not state.autotest and state.shots_dir == ""


## Build the world stage by stage behind the loading screen. The tree is paused meanwhile (no
## physics step, no streaming, no life) and the 3D view is off (the frames in between cost only
## the loading screen), so the staging adds a few milliseconds, not frames of simulation.
func _boot() -> void:
	var tree := get_tree()
	tree.paused = true
	var vp := get_viewport()
	var had_3d := vp.disable_3d
	vp.disable_3d = true
	var vsync := DisplayServer.window_get_vsync_mode()
	if DisplayServer.get_name() != "headless": DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var t_boot := Time.get_ticks_msec()
	WorldMap.warm()              # the map textures decode on a worker while the world generates
	var stages := _boot_stages()
	var total := 0.0
	for st in stages: total += float(st[2])
	var done := 0.0
	for st in stages:
		loading.set_stage(st[0], st[1], done / total * BOOT_SHARE)
		await tree.process_frame      # draws the loading screen with this stage's line (the first: before any work)
		if cli.has("boot-shot"): _boot_shot(st[0])
		var t0 := Time.get_ticks_msec()
		(st[3] as Callable).call()
		boot_ms[st[0]] = Time.get_ticks_msec() - t0
		done += float(st[2])
	loading.set_stage(&"settle", "Settling in", BOOT_SHARE)
	vp.disable_3d = had_3d
	if DisplayServer.get_name() != "headless": DisplayServer.window_set_vsync_mode(vsync)
	tree.paused = false
	booted = true
	boot_frames = Engine.get_process_frames()
	print("[game] world generated in %d ms (%d recipes in %d chunks); tree %d nodes" % [world.generate_ms, world.database.record_count, world.database.chunks().size(), get_tree().get_node_count()])
	print("[game] boot %d ms in %d stages: %s" % [Time.get_ticks_msec() - t_boot, stages.size(), boot_ms])
	boot_finished.emit()
	if loading.enabled:
		# up until the world round the courier is built and the first frames stop hitching
		loading.wait_until_ready(world.settled, world.settle_remaining, panels)
		loading.finished.connect(func(): hud.skip_title(), CONNECT_ONE_SHOT)
	else:
		loading.dismiss()
	if cli.has("test"):
		_run_test(cli.get_string("test"))


func _read_cli() -> void:
	state.autotest = cli.has("autotest")
	state.shots_dir = cli.get_string("shots", "")
	state.shot_interval = cli.get_float("shot-interval", 4.0)
	state.max_time = cli.get_float("maxtime", 240.0)
	state.need_deliveries = cli.get_int("deliveries", 1)


func _boot_entities() -> void:
	entities = EntityManager.new(); entities.name = "EntityManager"; add_child(entities)
	entities.setup(config)
	# The Rider is added before the bodies so it reads controls and hands out intents before the
	# bike, player and camera step in the same physics tick.
	rider = Rider.new(); rider.name = "Rider"; add_child(rider)

	bike = Bike.new(); bike.name = "Bike"
	bike.apply_definition(load("res://data/vehicles/bike.tres"))
	bike.terrain = world.terrain
	bike.set_meta("always_full", true)
	entities.register(bike, &"vehicle.bike", &"vehicle")
	var spawn := world.road_spawn(world.database.location_pos(&"villa_square") + Vector3(46, 0, 0), world.database.location_pos(&"villa_rosa_office"))   # the straight lane east of the villa, facing the office
	bike.place(spawn.pos, spawn.forward)

	jeep = Jeep.new(); jeep.name = "Jeep"
	jeep.apply_definition(load("res://data/vehicles/jeep.tres"))
	jeep.terrain = world.terrain
	jeep.set_meta("always_full", true)
	entities.register(jeep, &"vehicle.jeep", &"vehicle")
	# Park it a short walk behind the starting bike, directly on the same lane.
	var jeep_spawn := world.road_spawn(spawn.pos - spawn.forward * 10.0, spawn.pos)
	jeep.place(jeep_spawn.pos, jeep_spawn.forward)
	jeep.set_parked(true)

	# The Cart waits a little further back on the lane, its drawbar toward the jeep.
	cart = CargoCart.new(); cart.name = "Cart"
	cart.terrain = world.terrain
	cart.set_meta("always_full", true)
	entities.register(cart, &"vehicle.cart", &"vehicle")
	var cart_spawn := world.road_spawn(spawn.pos - spawn.forward * 18.5, spawn.pos)
	cart.place(cart_spawn.pos, cart_spawn.forward)

	player = Player.new(); player.name = "Player"
	player.terrain = world.terrain
	player.set_meta("always_full", true)
	entities.register(player, &"player", &"player")
	player.place(bike.global_position + Vector3(1.2, 0, 0), bike.flat_forward())

	cam = ChaseCamera.new(); cam.name = "ChaseCamera"; cam.terrain = world.terrain; add_child(cam)
	player.camera = cam
	cam.follow(bike, ChaseCamera.Framing.BIKE)
	world.terrain.set_view_camera(cam)   # Terrain3D centres its clipmap on this camera

	world.set_focus(bike)
	entities.focus = bike
	cart.focus = bike
	hitch = HitchSystem.new(); hitch.name = "HitchSystem"; add_child(hitch)
	var towers: Array[Vehicle] = [bike, jeep]
	hitch.setup(cart, rider, towers, player)
	hitch.spawn_pos = cart_spawn.pos; hitch.spawn_forward = cart_spawn.forward
	rider.mode_changed.connect(func(_from, to): _refocus(to))


func _boot_gameplay() -> void:
	gameplay = GameplayManager.new(); gameplay.name = "GameplayManager"; add_child(gameplay)
	gameplay.setup(world, entities, bike, player, cam, GameplayManager.load_jobs())
	gameplay.delivery.player = player
	gameplay.delivery.rider = rider
	gameplay.setup_combat(world, entities, rider)
	audio = BikeAudio.new(); audio.name = "BikeAudio"; add_child(audio)
	audio.setup(bike, jeep)
	gameplay.gun.audio = audio


func _apply_ui_scale() -> void:
	var win := get_window()
	if win == null or DisplayServer.get_name() == "headless": return
	var base := Vector2(ProjectSettings.get_setting("display/window/size/viewport_width", 1600), ProjectSettings.get_setting("display/window/size/viewport_height", 900))
	var s := minf(win.size.x / base.x, win.size.y / base.y)
	win.content_scale_factor = UI_MIN_SCALE / s if s > 0.0 and s < UI_MIN_SCALE else 1.0


func _boot_ui() -> void:
	_apply_ui_scale()
	get_window().size_changed.connect(_apply_ui_scale)
	var ui := Node.new(); ui.name = "UI"; add_child(ui)
	hud = HUD.new(); hud.name = "HUD"; ui.add_child(hud)
	hud.setup(bike, gameplay.delivery, cam)
	hud.player = player
	hud.rider = rider
	hud.setup_combat(gameplay.gun, gameplay.vitals)
	panels = PanelStack.new(self)
	catalogue = ResidentCatalogue.new(); catalogue.name = "ResidentCatalogue"; ui.add_child(catalogue)
	catalogue.setup(life, self)
	journey = JourneySystem.new(); journey.name = "JourneySystem"; ui.add_child(journey)
	journey.setup(self)
	cargo = CargoSystem.new(); cargo.name = "CargoSystem"; add_child(cargo)
	cargo.setup(self, hitch)
	cargo_panel = CargoPanel.new(); cargo_panel.name = "CargoPanel"; ui.add_child(cargo_panel)
	cargo_panel.setup(self, cargo)
	mayor = MayorView.new(); mayor.name = "MayorView"; ui.add_child(mayor)
	mayor.setup(self, colony)
	mayor.active_changed.connect(_on_mayor_active)
	mayor.save_requested.connect(func():
		if Saves.save_game("quick"): mayor.show_note("Colony and journey saved.")
		else: mayor.show_note("Could not save the game.")
	)
	var gfx := GraphicsMenu.new(); ui.add_child(gfx); gfx.setup(self)   # F10: quality presets
	map = WorldMap.new(); ui.add_child(map); map.setup(self)
	map.finish()
	minimap = Minimap.new(); hud.attach_minimap(minimap); minimap.setup(self, map)
	full_map = FullMap.new(); ui.add_child(full_map); full_map.setup(self, map)
	var dbg := Node.new(); dbg.name = "Debug"; add_child(dbg)
	debug = DebugOverlay.new(); debug.name = "DebugOverlay"; dbg.add_child(debug)
	debug.setup(self)


func _wire() -> void:
	bike.crashed.connect(func(): cam.shake(1.0); Events.vehicle_crashed.emit(&"vehicle.bike"))
	bike.landed.connect(func(impact: float):
		if impact > 6.0: cam.shake(impact * 0.08)
		Events.vehicle_landed.emit(&"vehicle.bike", impact))
	jeep.crashed.connect(func(): cam.shake(0.8); Events.vehicle_crashed.emit(&"vehicle.jeep"))
	jeep.landed.connect(func(impact: float):
		if impact > 6.0: cam.shake(impact * 0.06)
		Events.vehicle_landed.emit(&"vehicle.jeep", impact))
	rider.hitch_requested.connect(func(): hitch.toggle())
	rider.cargo_requested.connect(func(): cargo_panel.toggle())
	hitch.message.connect(func(t): Events.message.emit(t, 3.5))
	gameplay.delivery.cart = cart
	rider.vehicle_changed.connect(func(_from, to):
		gameplay.delivery.set_vehicle(to)
		_refocus(rider.mode))
	Events.package_collected.connect(func(_id): print("[game] package collected at t=%.1f" % state.time))
	Events.delivery_completed.connect(_on_delivery)
	Events.player_died.connect(func(): _down_at = rider.courier().global_position)
	Events.player_respawned.connect(func(_pos): cover_move(_down_at, "Coming to by the road"))
	Saves.register("delivery", gameplay.delivery)
	Saves.register("gun", gameplay.gun)
	Saves.register("vitals", gameplay.vitals)
	Saves.register("combat", gameplay.encounters)
	Saves.register("bike", bike)
	Saves.register("jeep", jeep)
	Saves.alias("truck", "jeep")          # a save from before the Jeep: its truck block moves the jeep
	Saves.register("cart", hitch)
	Saves.register("cargo", cargo)
	Saves.register("rider", rider)
	Saves.register("island_life", life)
	Saves.register("catalogue", catalogue)
	Saves.register("journey", journey)
	Saves.register("colony", colony)
	Saves.register("map", map)


func _start_controls() -> void:
	Controls.install_foot_bindings()
	Controls.install_map_bindings()
	player_controls = Controls.Keyboard.new()
	scripted_controls = Controls.Scripted.new()
	var use_scripted := state.autotest or state.shots_dir != ""
	rider.setup(bike, jeep, player, cam, gameplay.gun, world, scripted_controls if use_scripted else player_controls)
	rider.pointer_blocks_actions = func(): return rider.controls == player_controls and mayor.blocks_world_input()
	if use_scripted:
		gameplay.enable_autopilot(bike, world.terrain, scripted_controls)
		print("[game] autopilot enabled (autotest=%s shots=%s)" % [state.autotest, state.shots_dir])
	if state.shots_dir != "":
		DirAccess.make_dir_recursive_absolute(state.shots_dir)


func _start_world() -> void:
	if cli.has("nostream"):
		world.streamer.load_everything()
	else:
		world.streamer.load_all_pending()   # the first ring of chunks before the first frame
	if cli.has("load"):
		Saves.load_game(cli.get_string("load", "quick"))


## --test=<name>: run res://tests/<name>.gd as a node inside the booted game (the test runner).
## Tests see the whole game through `Game.current` and quit the tree themselves.
func _run_test(name: String) -> void:
	var script := load("res://tests/%s.gd" % name)
	if script == null:
		push_error("no such test: %s" % name)
		get_tree().quit(2)
		return
	var t: Node = script.new()
	t.name = "Test_" + name
	add_child(t)


## A move this far (m) is a long one: the loading screen covers it.
const FAR_MOVE := 400.0
var _down_at := Vector3.ZERO


## --boot-shot=DIR (render tools): the frame just drawn, the loading screen at this stage.
func _boot_shot(id: StringName) -> void:
	var dir := cli.get_string("boot-shot", "/tmp/boot")
	DirAccess.make_dir_recursive_absolute(dir)
	var img := get_viewport().get_texture().get_image()
	if img: img.save_png("%s/boot_%02d_%s.png" % [dir, loading.stage_log.size(), id])


## A long move (a coach or ferry ticket, F6): the loading screen is drawn first, then `move` runs,
## and the screen stays up until the world round the courier is built. Without a loading screen
## (tests, tools) the move simply runs now.
func relocate(text: String, move: Callable) -> void:
	if loading == null or not loading.enabled or loading.showing():
		move.call()
		return
	loading.cover(text, panels)
	await _drawn_frame()
	move.call()
	loading.wait_until_ready(world.settled, world.settle_remaining, panels)


## After a move that has already happened (a respawn, a loaded save): if it went far, cover the
## world popping in round the courier's new place.
func cover_move(from: Vector3, text: String) -> void:
	if loading == null or not loading.enabled or loading.showing(): return
	var to := rider.courier().global_position
	if Vector2(from.x, from.z).distance_to(Vector2(to.x, to.z)) < FAR_MOVE: return
	loading.cover(text, panels)
	loading.wait_until_ready(world.settled, world.settle_remaining, panels)


## Wait until a frame has been drawn (the headless server draws none: one process frame).
func _drawn_frame() -> void:
	if DisplayServer.get_name() == "headless": await get_tree().process_frame
	else: await RenderingServer.frame_post_draw


## The streamer and the tiers follow whoever the player is right now.
func _refocus(mode: int) -> void:
	if mayor != null and mayor.active: return
	var f: Node3D = rider.courier()
	world.set_focus(f)
	entities.focus = f
	if cart: cart.focus = f


## Tests and tools call this to take the controls away from the keyboard.
func use_scripted_controls() -> Controls.Scripted:
	rider.controls = scripted_controls
	return scripted_controls


func _input(event: InputEvent) -> void:
	if not booted: return
	if not event is InputEventKey or not event.pressed or event.echo: return
	match event.keycode:
		KEY_F4:
			mayor.toggle()
		KEY_F5:
			if Saves.save_game("quick"):
				Events.message.emit("Game saved.", 2.0)
				if mayor.active: mayor.show_note("Colony and journey saved.")
		KEY_F9:
			panels.close_all()
			var from := rider.courier().global_position
			if Saves.load_game("quick"):
				Events.message.emit("Game loaded.", 2.0)
				cover_move(from, "Loading your journey")
			else: Events.message.emit("No save yet (F5 saves).", 2.0)
		_:
			return
	get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not booted: return
	if mayor != null and mayor.active: return
	if event is InputEventMouseButton and event.pressed and rider.is_on_foot() and not panels.any_open() and not panels.just_closed():
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: cam.zoom(-1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: cam.zoom(1)
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		player_controls.feed_mouse(event.relative)


func _on_mayor_active(active: bool) -> void:
	if active:
		_quit_armed = 0.0
		panels.open(mayor)
		_mayor_player_physics = player.is_physics_processing()
		_mayor_camera_physics = cam.is_physics_processing()
		_mayor_hud_visible = hud.visible
		player.hold_controls()
		player.set_physics_process(false)
		cam.set_physics_process(false)
		hud.hide()
		catalogue.hide()
		world.set_focus(mayor.map_focus)
	else:
		world.set_focus(rider.courier())
		world.streamer.load_all_pending()
		player.set_physics_process(_mayor_player_physics)
		cam.set_physics_process(_mayor_camera_physics)
		hud.visible = _mayor_hud_visible
		catalogue.show()
		panels.close(mayor)


## Shutdown: townsfolk meshes build on worker threads; a quit with builds in flight must let
## them finish (a GDScript task still running while the tree goes away hangs the exit).
func _exit_tree() -> void:
	PersonBuilder.wait_all()
	PersonBuilder.cancel_parts()
	PersonBuilder.wait_parts()
	if life != null and life.outer != null: life.outer.wait()
	if colony != null and colony.economy != null: colony.economy.shipping.wait()


func _on_delivery(_job_id: StringName, total: int) -> void:
	print("[game] DELIVERY COMPLETED #%d at t=%.1f (odometer %.0f m)" % [total, state.time, rider.vehicle.odometer])
	if state.autotest and total >= state.need_deliveries:
		print("AUTOTEST PASS: %d deliveries in %.1fs, avg fps %.1f" % [total, state.time, state.avg_fps()])
		get_tree().quit(0)


func _process(delta: float) -> void:
	if not booted: return
	state.time += delta
	state.fps_n += 1
	state.fps_acc += Engine.get_frames_per_second()
	# Esc: first press arms (and frees the mouse), second within 3 s quits; a click re-captures
	if _quit_armed > 0.0:
		_quit_armed -= delta
	panels.process()
	if Input.is_action_just_pressed("quit_game") and not panels.any_open() and not panels.just_closed():
		if _quit_armed > 0.0:
			get_tree().quit()
		else:
			_quit_armed = 3.0
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			Events.message.emit("Press Esc again within 3 s to quit.", 3.0)
	if rider.is_on_foot() and not panels.any_open() and not panels.just_closed() and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and Input.is_action_just_pressed("fire"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.set_mode(bike, player, gameplay.gun)
	if state.shots_dir != "":
		_shot_t += delta
		if _shot_t >= state.shot_interval:
			_shot_t = 0.0
			_take_shot()
	if state.autotest and state.time > state.max_time:
		print("AUTOTEST FAIL: timeout after %.0fs (deliveries=%d, stage=%d, pos=%s)" % [state.time, gm.deliveries, gm.stage, bike.global_position])
		get_tree().quit(1)


func _take_shot() -> void:
	var img := get_viewport().get_texture().get_image()
	if img:
		var path := "%s/shot_%03d.png" % [state.shots_dir, _shot_n]
		img.save_png(path)
		print("[game] screenshot %s (t=%.1f)" % [path, state.time])
		_shot_n += 1
