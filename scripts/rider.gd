class_name Rider
extends Node
## The Rider module: the one owner of "what is the boy doing right now" and of every transition
## between riding, flying, walking and swimming. Everything else — bike, player, camera, HUD,
## audio, delivery loop — either receives a ControlIntent from here or reacts to `mode_changed`.
##
## Interface:
##   mode (read-only)             RIDING | FLYING | ON_FOOT | SWIMMING
##   request_dismount() -> bool   hop off the bike (only when stopped and grounded)
##   request_mount() -> bool      get back on (only next to the bike, not while swimming)
##   request_wings() -> void      fold the wings out / in (not in the air)
##   request_reset() -> void      back to the nearest road, bike and boy together
##   controls: Controls.Source    the adapter that supplies intents (player input or scripted)
##   signals mode_changed(from, to), message(text, duration)

enum Mode { RIDING, FLYING, ON_FOOT, SWIMMING }

signal mode_changed(from: int, to: int)
signal message(text: String, duration: float)

var mode: int = Mode.RIDING
var controls: Controls.Source
var bike: Bike
var player: Player
var cam: ChaseCamera
var gun: GunSystem
var level: Level
var last_intent: Controls.Intent = Controls.Intent.new()
var _ctx := Controls.Context.new()


func setup(p_bike: Bike, p_player: Player, p_cam: ChaseCamera, p_gun: GunSystem, p_level: Level, p_controls: Controls.Source) -> void:
	bike = p_bike; player = p_player; cam = p_cam; gun = p_gun; level = p_level
	controls = p_controls
	bike.took_off.connect(func(): _set_mode(Mode.FLYING))
	bike.landed_plane.connect(func(): if mode == Mode.FLYING: _set_mode(Mode.RIDING))
	bike.fell_in_sea.connect(func(): if mode == Mode.FLYING: _set_mode(Mode.RIDING))
	player.entered_water.connect(func(): if mode == Mode.ON_FOOT: _set_mode(Mode.SWIMMING))
	player.left_water.connect(func(): if mode == Mode.SWIMMING: _set_mode(Mode.ON_FOOT))
	bike.transformed.connect(func(out):
		message.emit("Wings out! Throttle up past %d km/h, then pull back (S) to take off." % int(bike.takeoff_speed * 3.6) if out else "Wings folded.", 4.0)
		cam.follow(bike, ChaseCamera.Framing.PLANE if out else ChaseCamera.Framing.BIKE))
	bike.took_off.connect(func(): message.emit("Airborne! S pulls the nose up, W pushes it down, A/D bank, Shift boosts. To land: nose down gently, then pull up just before touchdown.", 5.0))
	bike.landed_plane.connect(func(): message.emit("Touchdown. Press T to fold the wings.", 3.0))
	bike.hard_landing.connect(func(_sink): message.emit("Ouch — hard landing!", 2.0))
	bike.denied.connect(func(t): message.emit(t, 2.0))
	bike.fell_in_sea.connect(func(): cam.snap_to_target(); message.emit("Splash! Back on the road you go.", 3.0))
	_apply_mode_effects(Mode.RIDING)


func is_riding() -> bool:
	return mode == Mode.RIDING or mode == Mode.FLYING


func is_on_foot() -> bool:
	return mode == Mode.ON_FOOT or mode == Mode.SWIMMING


# ---------------------------------------------------------------- per-tick control routing
func _physics_process(delta: float) -> void:
	if controls == null or bike == null: return
	_ctx.on_foot = is_on_foot()
	_ctx.wings_out = bike.wings_out
	_ctx.airborne = bike.airborne
	_ctx.at_takeoff_speed = bike.at_takeoff_speed()
	var i := controls.read(_ctx, delta)
	last_intent = i
	if i.interact_pressed:
		if is_riding(): request_dismount()
		else: request_mount()
	if i.reset_pressed:
		request_reset()
	if is_riding():
		if i.wings_pressed:
			request_wings()
		bike.apply(i)
		cam.set_look_back(i.look_back)
		if i.fire_pressed:
			gun.try_fire(false)
	else:
		player.apply(i)
		cam.look(i.look)
		var aiming := i.aim and gun.has_gun and mode == Mode.ON_FOOT
		cam.set_aiming(aiming)
		player.aiming = aiming or gun.is_recently_fired()
		player.aim_pitch = cam.pitch()
		if i.fire_pressed:
			gun.try_fire(true)


# ---------------------------------------------------------------- transitions
func request_dismount() -> bool:
	if not is_riding(): return false
	if bike.airborne or not bike.grounded:
		message.emit("Not while airborne!", 1.5)
		return false
	if absf(bike.speed) > 2.5 and not (bike.speed < 0.0 and bike.speed > -5.5 and bike.brake > 0.0):
		message.emit("Stop the bike before hopping off.", 2.0)
		return false
	var spot = _dismount_spot()
	if spot == null:
		message.emit("No room to hop off here.", 2.0)
		return false
	player.place(spot, bike.flat_forward())
	_set_mode(Mode.ON_FOOT)
	message.emit("On foot. Walk with WASD, Shift to run, Space to jump. E by the bike to ride again.", 4.0)
	return true


func request_mount() -> bool:
	if mode != Mode.ON_FOOT:
		return false
	if player.global_position.distance_to(bike.global_position) > 2.6:
		message.emit("Walk back to the bike and press E.", 2.0)
		return false
	_set_mode(Mode.RIDING)
	return true


func request_wings() -> void:
	if not is_riding(): return
	bike.toggle_wings()


## R: bring the bike (and the boy, if he's on foot) back to the nearest road.
func request_reset() -> void:
	if is_riding():
		bike.reset_to_road()
		if mode == Mode.FLYING: _set_mode(Mode.RIDING)
		return
	bike.set_parked(false)
	bike.reset_to_road()
	bike.set_parked(true)
	var side := bike.global_transform.basis.x.normalized()
	var p := bike.global_position + side * 1.2
	p.y = level.terrain.probe(p).height + 0.05
	player.place(p, bike.flat_forward())
	if mode == Mode.SWIMMING: _set_mode(Mode.ON_FOOT)
	message.emit("Back on the road.", 2.0)


func _set_mode(to: int) -> void:
	if to == mode: return
	var from := mode
	mode = to
	_apply_mode_effects(to)
	mode_changed.emit(from, to)


## The choreography of a transition lives here and nowhere else.
func _apply_mode_effects(to: int) -> void:
	var riding := to == Mode.RIDING or to == Mode.FLYING
	bike.set_parked(not riding)
	bike.visual.set_rider_visible(riding)
	player.visible = not riding
	player.process_mode = Node.PROCESS_MODE_DISABLED if riding else Node.PROCESS_MODE_INHERIT
	gun.set_visible_on_player(not riding)
	match to:
		Mode.RIDING:   cam.follow(bike, ChaseCamera.Framing.PLANE if bike.wings_out else ChaseCamera.Framing.BIKE)
		Mode.FLYING:   cam.follow(bike, ChaseCamera.Framing.PLANE)
		Mode.ON_FOOT:  cam.follow(player, ChaseCamera.Framing.FOOT)
		Mode.SWIMMING: cam.follow(player, ChaseCamera.Framing.SWIM); message.emit("Swimming — head back to the shore to climb out.", 3.0)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if not riding else Input.MOUSE_MODE_VISIBLE


## A clear spot next to the bike (right, left, behind) with a floor under it.
func _dismount_spot() -> Variant:
	var space := bike.get_world_3d().direct_space_state
	var side := bike.global_transform.basis.x.normalized()
	var back := -bike.flat_forward()
	var sh := CapsuleShape3D.new(); sh.radius = 0.28; sh.height = 1.8
	for off in [side * 1.2, -side * 1.2, back * 1.8, side * 2.0, -side * 2.0]:
		var p: Vector3 = bike.global_position + off
		var g := level.terrain.probe(p + Vector3(0, 0.6, 0))
		if absf(g.height - bike.global_position.y) > 3.0: continue   # not the surface the bike is on
		var foot := Vector3(p.x, g.height + 0.05, p.z)
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = sh
		q.transform = Transform3D(Basis(), foot + Vector3(0, 0.95, 0))
		q.collision_mask = 1
		q.exclude = [bike.get_rid()]
		if space.intersect_shape(q, 1).is_empty():
			return foot
	return null
