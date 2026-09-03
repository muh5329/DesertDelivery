extends Node3D
## Entry point: builds the world and wires the modules together.
##   Rider          owns the mode (riding / flying / on foot / swimming) and every transition
##   Controls.*     the ControlIntent seam: Controls.Keyboard reads real input, Controls.Scripted
##                  is what the Autopilot and the test suites drive
##   Bike / Player  physics, fed intents by the Rider
##   ChaseCamera    framing intents from the Rider
##   GameManager    the delivery loop;  GunSystem  the pistol;  HUD;  BikeAudio
## Command-line flags (after `--`):
##   --autotest            drive automatically and quit(0) after N deliveries (default 1)
##   --deliveries=N        how many deliveries the autotest needs
##   --maxtime=S           autotest timeout in seconds (default 240)
##   --shots=DIR           save a screenshot every few seconds into DIR (needs a display)
##   --shot-interval=S     seconds between screenshots (default 4)

var level: Level
var rider: Rider
var bike: Bike
var cam: ChaseCamera
var gm: GameManager
var hud: HUD
var autopilot: Autopilot
var player: Player
var gun: GunSystem
var audio: Node
var player_controls: Controls.Keyboard
var scripted_controls: Controls.Scripted
var _quit_armed := 0.0
var _args := {}
var _autotest := false
var _shots_dir := ""
var _shot_interval := 4.0
var _shot_t := 0.0
var _shot_n := 0
var _time := 0.0
var _max_time := 240.0
var _need_deliveries := 1
var _fps_acc := 0.0
var _fps_n := 0


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			_args[kv[0]] = kv[1] if kv.size() > 1 else "true"
	_autotest = _args.has("autotest")
	_shots_dir = _args.get("shots", "")
	_shot_interval = float(_args.get("shot-interval", "4"))
	_max_time = float(_args.get("maxtime", "240"))
	_need_deliveries = int(_args.get("deliveries", "1"))


func _ready() -> void:
	_parse_args()
	var t0 := Time.get_ticks_msec()
	level = Level.new()
	level.name = "Level"
	add_child(level)
	level.build()
	print("[main] level built in %d ms (%d nodes)" % [Time.get_ticks_msec() - t0, get_tree().get_node_count()])

	# The Rider is added first so it reads controls and hands out intents before the
	# bike, player and camera step in the same physics tick.
	rider = Rider.new()
	rider.name = "Rider"
	add_child(rider)

	bike = Bike.new()
	bike.name = "Bike"
	bike.terrain = level.terrain
	add_child(bike)
	var start: Dictionary = level.locations["Villa Square"]
	# start ON the road ~40 m south of the square, pointing up the road toward the office ring
	var road := level.terrain.nearest_road(start.pos + Vector3(-30, 0, 18))
	var near: Vector3 = road.point
	var tangent: Vector3 = road.tangent
	var office: Vector3 = level.locations["Villa Rosa Office"].pos
	if tangent.dot(office - near) < 0.0: tangent = -tangent   # face the office ring
	bike.place_on_road(Vector3(near.x, maxf(near.y, level.terrain.height_at(near.x, near.z)), near.z), tangent)

	player = Player.new()
	player.name = "Player"
	player.terrain = level.terrain
	add_child(player)
	player.place(bike.global_position + Vector3(1.2, 0, 0), bike.flat_forward())

	cam = ChaseCamera.new()
	cam.name = "ChaseCamera"
	cam.terrain = level.terrain
	add_child(cam)
	player.camera = cam
	cam.follow(bike, ChaseCamera.Framing.BIKE)

	gm = GameManager.new()
	gm.name = "GameManager"
	add_child(gm)
	gm.setup(level, bike)
	gm.player = player
	gm.rider = rider
	gm.delivery_completed.connect(_on_delivery)
	gm.package_collected.connect(func(): print("[game] package collected at t=%.1f" % _time))

	gun = GunSystem.new()
	gun.name = "GunSystem"
	add_child(gun)
	gun.setup(level, player, cam)

	audio = load("res://scripts/bike_audio.gd").new()
	audio.name = "BikeAudio"
	add_child(audio)
	audio.setup(bike)
	gun.audio = audio

	hud = HUD.new()
	hud.name = "HUD"
	add_child(hud)
	hud.setup(bike, gm, cam)
	hud.player = player
	hud.rider = rider

	# everything that wants to tell the player something goes through the HUD
	rider.message.connect(hud.show_message)
	gun.message.connect(hud.show_message)
	gun.target_hit.connect(hud.set_cans)
	gun.picked_up.connect(func(): hud.set_gun(true))
	bike.crashed.connect(func(): cam.shake(1.0))
	bike.landed.connect(func(impact: float): if impact > 6.0: cam.shake(impact * 0.08))

	player_controls = Controls.Keyboard.new()
	scripted_controls = Controls.Scripted.new()
	var use_scripted := _autotest or _shots_dir != ""
	rider.setup(bike, player, cam, gun, level, scripted_controls if use_scripted else player_controls)

	if use_scripted:
		autopilot = Autopilot.new()
		autopilot.name = "Autopilot"
		add_child(autopilot)
		autopilot.setup(bike, gm, level.terrain, scripted_controls)
		print("[main] autopilot enabled (autotest=%s shots=%s)" % [_autotest, _shots_dir])
	if _shots_dir != "":
		DirAccess.make_dir_recursive_absolute(_shots_dir)


## Tests and tools call this to take the controls away from the keyboard.
func use_scripted_controls() -> Controls.Scripted:
	rider.controls = scripted_controls
	return scripted_controls


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		player_controls.feed_mouse(event.relative)


func _on_delivery(total: int) -> void:
	print("[game] DELIVERY COMPLETED #%d at t=%.1f (odometer %.0f m)" % [total, _time, bike.odometer])
	if _autotest and total >= _need_deliveries:
		print("AUTOTEST PASS: %d deliveries in %.1fs, avg fps %.1f" % [total, _time, _fps_acc / maxf(_fps_n, 1)])
		get_tree().quit(0)


func _process(delta: float) -> void:
	_time += delta
	_fps_n += 1
	_fps_acc += Engine.get_frames_per_second()
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
			hud.show_message("Press Esc again within 3 s to quit.", 3.0)
	if rider.is_on_foot() and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and Input.is_action_just_pressed("fire"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.set_mode(bike, player, gun)
	if _shots_dir != "":
		_shot_t += delta
		if _shot_t >= _shot_interval:
			_shot_t = 0.0
			_take_shot()
	if _autotest and _time > _max_time:
		print("AUTOTEST FAIL: timeout after %.0fs (deliveries=%d, stage=%d, pos=%s)" % [_time, gm.deliveries, gm.stage, bike.global_position])
		get_tree().quit(1)


func _take_shot() -> void:
	var img := get_viewport().get_texture().get_image()
	if img:
		var path := "%s/shot_%03d.png" % [_shots_dir, _shot_n]
		img.save_png(path)
		print("[main] screenshot %s (t=%.1f)" % [path, _time])
		_shot_n += 1
