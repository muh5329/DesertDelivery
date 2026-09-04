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
##   ├── GameplayManager   DeliverySystem, GunSystem, (Autopilot)
##   ├── Rider             the player's controller: mode + ControlIntent routing
##   ├── ChaseCamera
##   ├── BikeAudio
##   ├── UI                HUD
##   └── Debug             DebugOverlay (F3)
##
## Autoloads: `Events` (EventBus) and `Saves` (SaveManager). Nothing else is global.

static var current: Game

var cli := CliArgs.new()
var state := GameState.new()
var config: WorldConfig

var world: WorldManager
var entities: EntityManager
var gameplay: GameplayManager
var rider: Rider
var bike: Bike
var player: Player
var cam: ChaseCamera
var audio: BikeAudio
var hud: HUD
var debug: DebugOverlay
var player_controls: Controls.Keyboard
var scripted_controls: Controls.Scripted

# convenience aliases used by tests and tools
var gm: DeliverySystem:
	get: return gameplay.delivery
var gun: GunSystem:
	get: return gameplay.gun
var level: Island:
	get: return world.island
var autopilot: Autopilot:
	get: return gameplay.autopilot

var _quit_armed := 0.0
var _shot_t := 0.0
var _shot_n := 0


func _ready() -> void:
	current = self
	_read_cli()
	config = load("res://data/config/world.tres")
	_boot_world()
	_boot_entities()
	_boot_gameplay()
	_boot_ui()
	_wire()
	_start()
	print("[game] world generated in %d ms (%d recipes in %d chunks); tree %d nodes" % [world.generate_ms, world.database.record_count, world.database.chunks().size(), get_tree().get_node_count()])


func _read_cli() -> void:
	state.autotest = cli.has("autotest")
	state.shots_dir = cli.get_string("shots", "")
	state.shot_interval = cli.get_float("shot-interval", 4.0)
	state.max_time = cli.get_float("maxtime", 240.0)
	state.need_deliveries = cli.get_int("deliveries", 1)


func _boot_world() -> void:
	world = WorldManager.new(); world.name = "WorldManager"; add_child(world)
	world.setup(config)


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
	var spawn := world.road_spawn(world.database.location_pos(&"villa_square") + Vector3(-30, 0, 18), world.database.location_pos(&"villa_rosa_office"))
	bike.place(spawn.pos, spawn.forward)

	player = Player.new(); player.name = "Player"
	player.terrain = world.terrain
	player.set_meta("always_full", true)
	entities.register(player, &"player", &"player")
	player.place(bike.global_position + Vector3(1.2, 0, 0), bike.flat_forward())

	cam = ChaseCamera.new(); cam.name = "ChaseCamera"; cam.terrain = world.terrain; add_child(cam)
	player.camera = cam
	cam.follow(bike, ChaseCamera.Framing.BIKE)

	world.set_focus(bike)
	entities.focus = bike
	rider.mode_changed.connect(func(_from, to): _refocus(to))


func _boot_gameplay() -> void:
	gameplay = GameplayManager.new(); gameplay.name = "GameplayManager"; add_child(gameplay)
	gameplay.setup(world, entities, bike, player, cam, GameplayManager.load_jobs())
	audio = BikeAudio.new(); audio.name = "BikeAudio"; add_child(audio)
	audio.setup(bike)
	gameplay.gun.audio = audio


func _boot_ui() -> void:
	var ui := Node.new(); ui.name = "UI"; add_child(ui)
	hud = HUD.new(); hud.name = "HUD"; ui.add_child(hud)
	hud.setup(bike, gameplay.delivery, cam)
	hud.player = player
	hud.rider = rider
	var dbg := Node.new(); dbg.name = "Debug"; add_child(dbg)
	debug = DebugOverlay.new(); debug.name = "DebugOverlay"; dbg.add_child(debug)
	debug.setup(self)


func _wire() -> void:
	bike.crashed.connect(func(): cam.shake(1.0); Events.vehicle_crashed.emit(&"vehicle.bike"))
	bike.landed.connect(func(impact: float):
		if impact > 6.0: cam.shake(impact * 0.08)
		Events.vehicle_landed.emit(&"vehicle.bike", impact))
	Events.package_collected.connect(func(_id): print("[game] package collected at t=%.1f" % state.time))
	Events.delivery_completed.connect(_on_delivery)
	Saves.register("delivery", gameplay.delivery)
	Saves.register("gun", gameplay.gun)
	Saves.register("bike", bike)
	Saves.register("rider", rider)


func _start() -> void:
	player_controls = Controls.Keyboard.new()
	scripted_controls = Controls.Scripted.new()
	var use_scripted := state.autotest or state.shots_dir != ""
	rider.setup(bike, player, cam, gameplay.gun, world, scripted_controls if use_scripted else player_controls)
	if use_scripted:
		gameplay.enable_autopilot(bike, world.terrain, scripted_controls)
		print("[game] autopilot enabled (autotest=%s shots=%s)" % [state.autotest, state.shots_dir])
	if state.shots_dir != "":
		DirAccess.make_dir_recursive_absolute(state.shots_dir)
	if cli.has("nostream"):
		world.streamer.load_everything()
	else:
		world.streamer.load_all_pending()   # the first ring of chunks before the first frame
	if cli.has("load"):
		Saves.load_game(cli.get_string("load", "quick"))
	if cli.has("test"):
		_run_test(cli.get_string("test"))


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


## The streamer and the tiers follow whoever the player is right now.
func _refocus(mode: int) -> void:
	var f: Node3D = bike if (mode == Rider.Mode.RIDING or mode == Rider.Mode.FLYING) else player
	world.set_focus(f)
	entities.focus = f


## Tests and tools call this to take the controls away from the keyboard.
func use_scripted_controls() -> Controls.Scripted:
	rider.controls = scripted_controls
	return scripted_controls


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		player_controls.feed_mouse(event.relative)
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F5:
				if Saves.save_game("quick"): Events.message.emit("Game saved.", 2.0)
			KEY_F9:
				if Saves.load_game("quick"): Events.message.emit("Game loaded.", 2.0)
				else: Events.message.emit("No save yet (F5 saves).", 2.0)


func _on_delivery(_job_id: StringName, total: int) -> void:
	print("[game] DELIVERY COMPLETED #%d at t=%.1f (odometer %.0f m)" % [total, state.time, bike.odometer])
	if state.autotest and total >= state.need_deliveries:
		print("AUTOTEST PASS: %d deliveries in %.1fs, avg fps %.1f" % [total, state.time, state.avg_fps()])
		get_tree().quit(0)


func _process(delta: float) -> void:
	state.time += delta
	state.fps_n += 1
	state.fps_acc += Engine.get_frames_per_second()
	# Esc: first press arms (and frees the mouse), second within 3 s quits; a click re-captures
	if _quit_armed > 0.0:
		_quit_armed -= delta
	if Input.is_action_just_pressed("quit_game"):
		if _quit_armed > 0.0:
			get_tree().quit()
		else:
			_quit_armed = 3.0
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			Events.message.emit("Press Esc again within 3 s to quit.", 3.0)
	if rider.is_on_foot() and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and Input.is_action_just_pressed("fire"):
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
