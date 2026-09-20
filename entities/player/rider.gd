class_name Rider
extends Node
## The Rider (the player's controller): the one owner of "what is the boy doing right now" and of every transition
## between bike riding, truck driving, flying, walking and swimming. Everything else — vehicles, player, camera, HUD,
## audio, delivery loop — either receives a ControlIntent from here or reacts to `mode_changed`.
##
## Interface:
##   courier() -> Node3D          the body everyone else should measure distance to
##   active_vehicle() -> Vehicle  what he is driving, or null on foot
##   can_hand_over() -> bool      may a parcel change hands this tick
##   is_stopped() -> bool         standing still enough to talk to somebody
##   is_aiming() -> bool          looking down the crosshair
##   mode (read-only)             RIDING | DRIVING | FLYING | ON_FOOT | SWIMMING — for the debug
##                                overlay and the save file. Ask a question above instead: every
##                                caller that re-derived a policy from this enum got it slightly
##                                different, and adding a Mode silently split them.
##   request_dismount() -> bool   exit the active vehicle (only when stopped and grounded)
##   request_mount() -> bool      enter the nearest vehicle (only when close, not swimming)
##   request_wings() -> void      fold the wings out / in (not in the air)
##   request_reset() -> void      active vehicle and rider back to the nearest road
##   controls: Controls.Source    the adapter that supplies intents (player input or scripted)
##   signals mode_changed(from, to), message(text, duration)

enum Mode { RIDING, FLYING, ON_FOOT, SWIMMING, DRIVING }

signal mode_changed(from: int, to: int)
signal message(text: String, duration: float)
signal vehicle_changed(from: Vehicle, to: Vehicle)

var mode: int = Mode.RIDING
var controls: Controls.Source
var bike: Bike
var truck: Truck
var vehicle: Vehicle
var player: Player
var cam: ChaseCamera
var gun: GunSystem
var world: WorldManager
var _last_intent: Controls.Intent = Controls.Intent.new()
var _aiming := false
var _foot := Controls.Foot.new()
var pointer_blocks_actions: Callable


func _init() -> void:
	process_physics_priority = -40


func setup(p_bike: Bike, p_truck: Truck, p_player: Player, p_cam: ChaseCamera, p_gun: GunSystem, p_world: WorldManager, p_controls: Controls.Source) -> void:
	bike = p_bike; truck = p_truck; vehicle = bike
	player = p_player; cam = p_cam; gun = p_gun; world = p_world
	message.connect(func(t, d): Events.message.emit(t, d))
	mode_changed.connect(func(a, b): Events.rider_mode_changed.emit(a, b))
	controls = p_controls
	bike.took_off.connect(func(): _set_mode(Mode.FLYING))
	bike.landed_plane.connect(func(): if mode == Mode.FLYING: _set_mode(Mode.RIDING))
	bike.fell_in_sea.connect(func(): if mode == Mode.FLYING: _set_mode(Mode.RIDING))
	truck.fell_in_sea.connect(func(): message.emit("Splash! The truck is back on the road.", 3.0))
	truck.denied.connect(func(t): message.emit(t, 3.0))
	truck.winch_changed.connect(func(attached, distance):
		if attached: message.emit("Winch anchored %.0f m ahead — pulling now. Q detaches." % distance, 3.0)
		else: message.emit("Winch released.", 1.5))
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
	return mode == Mode.RIDING or mode == Mode.FLYING or mode == Mode.DRIVING


func is_on_foot() -> bool:
	return mode == Mode.ON_FOOT or mode == Mode.SWIMMING


# ---------------------------------------------------------------- what everyone else asks
## The courier himself: the body a delivery Ring, a shop counter or the ambience measures to.
func courier() -> Node3D:
	return player if is_on_foot() else vehicle


## What he is driving, or null when he is on his feet.
func active_vehicle() -> Vehicle:
	return null if is_on_foot() else vehicle


## Can a parcel change hands this tick? Not mid-flight, not mid-swim.
func can_hand_over() -> bool:
	return mode == Mode.RIDING or mode == Mode.DRIVING or mode == Mode.ON_FOOT


## Standing still enough to hand something over or talk to somebody. Swimming and flying are
## never "stopped", whatever the speed reads.
func is_stopped(max_speed: float = 2.5) -> bool:
	match mode:
		Mode.ON_FOOT:
			return player != null and player.is_on_floor() \
				and Vector2(player.velocity.x, player.velocity.z).length() < max_speed
		Mode.RIDING, Mode.DRIVING:
			return vehicle != null and vehicle.grounded and absf(vehicle.speed) < max_speed
	return false


## Looking down the crosshair. The ControlIntent stops at the Rider; nobody else reads it.
func is_aiming() -> bool:
	return _aiming


# ---------------------------------------------------------------- per-tick control routing
func _physics_process(delta: float) -> void:
	if controls == null or bike == null: return
	# The active Scheme comes from whatever is being controlled — no Context, no vehicle state
	# travelling backwards through the seam.
	var i := controls.read(_foot if is_on_foot() else vehicle.control_scheme(), delta)
	if pointer_blocks_actions.is_valid() and pointer_blocks_actions.call():
		i.commands.erase(Controls.FIRE)
	_last_intent = i
	if i.pressed(Controls.INTERACT):
		var transitioned := request_dismount() if is_riding() else request_mount()
		# A scheme was sampled for the previous body. Do not apply its jump/brake/fire
		# meanings to a different body during this same physics tick.
		if transitioned:
			return
	if i.pressed(Controls.RESET):
		request_reset()
		return
	if is_riding():
		_aiming = false
		if i.pressed(Controls.WINGS) and vehicle == bike:
			request_wings()
		vehicle.apply(i)
		cam.set_look_back(i.look_back)
		if i.pressed(Controls.FIRE):
			gun.try_fire(false)
	else:
		player.apply(i)
		cam.look(i.look)
		_aiming = i.aim and gun.has_gun and mode == Mode.ON_FOOT
		cam.set_aiming(_aiming)
		player.aiming = _aiming or gun.is_recently_fired()
		player.aim_pitch = cam.pitch()
		if i.pressed(Controls.FIRE):
			gun.try_fire(true)


# ---------------------------------------------------------------- transitions
func request_dismount() -> bool:
	if not is_riding(): return false
	if (vehicle == bike and bike.airborne) or not vehicle.grounded:
		message.emit("Not while airborne!", 1.5)
		return false
	if absf(vehicle.speed) > 2.5 and not (vehicle == bike and bike.speed < 0.0 and bike.speed > -5.5 and bike.brake > 0.0):
		message.emit("Stop the vehicle before hopping out.", 2.0)
		return false
	var spot = _dismount_spot()
	if spot == null:
		message.emit("No room to hop off here.", 2.0)
		return false
	player.place(spot, vehicle.flat_forward())
	_set_mode(Mode.ON_FOOT)
	message.emit("On foot. Press E beside the bike or truck to drive it.", 3.5)
	return true


func request_mount() -> bool:
	if mode != Mode.ON_FOOT:
		return false
	var bike_distance := player.global_position.distance_to(bike.global_position)
	var truck_distance := player.global_position.distance_to(truck.global_position)
	var chosen: Vehicle = bike if bike_distance <= truck_distance else truck
	if player.global_position.distance_to(chosen.global_position) > 2.9:
		message.emit("Walk up to the bike or truck and press E.", 2.0)
		return false
	if not chosen.grounded or absf(chosen.speed) > 2.5:
		message.emit("Wait until the vehicle is safely stopped.", 2.0)
		return false
	var sight := PhysicsRayQueryParameters3D.create(
		player.global_position + Vector3.UP, chosen.global_position + Vector3.UP, 1)
	sight.exclude = [player.get_rid(), chosen.get_rid()]
	if not player.get_world_3d().direct_space_state.intersect_ray(sight).is_empty():
		message.emit("Walk around to the vehicle first.", 2.0)
		return false
	_set_vehicle(chosen)
	_set_mode(Mode.RIDING if chosen == bike else Mode.DRIVING)
	if chosen == truck:
		message.emit("Truck ready. Q fires the winch; stop and press G to pack the cargo bed.", 5.0)
	return true


func request_wings() -> void:
	if not is_riding() or vehicle != bike: return
	bike.toggle_wings()


## R: bring the active vehicle (and the boy, if he's on foot) back to the nearest road.
func request_reset() -> void:
	if is_riding():
		vehicle.reset_to_road()
		if mode == Mode.FLYING: _set_mode(Mode.RIDING)
		return
	vehicle.set_parked(false)
	vehicle.reset_to_road()
	vehicle.set_parked(true)
	var side := vehicle.global_transform.basis.x.normalized()
	var p := vehicle.global_position + side * 1.2
	p.y = world.probe(p).height + 0.05
	player.place(p, vehicle.flat_forward())
	cam.snap_to_target()
	if mode == Mode.SWIMMING: _set_mode(Mode.ON_FOOT)
	message.emit("Back on the road.", 2.0)


func _set_mode(to: int) -> void:
	if to == mode: return
	var from := mode
	mode = to
	_apply_mode_effects(to)
	mode_changed.emit(from, to)


func _set_vehicle(to: Vehicle) -> void:
	if to == vehicle: return
	var from := vehicle
	vehicle = to
	vehicle_changed.emit(from, to)


## The choreography of a transition lives here and nowhere else.
func _apply_mode_effects(to: int) -> void:
	_aiming = false
	player.aiming = false
	player.apply(Controls.Intent.new())
	cam.set_aiming(false)
	cam.set_look_back(false)
	var riding := to == Mode.RIDING or to == Mode.FLYING or to == Mode.DRIVING
	bike.set_parked(not riding or vehicle != bike)
	truck.set_parked(not riding or vehicle != truck)
	bike.set_rider_visible(riding and vehicle == bike)
	truck.set_rider_visible(riding and vehicle == truck)
	player.visible = not riding
	player.process_mode = Node.PROCESS_MODE_DISABLED if riding else Node.PROCESS_MODE_INHERIT
	gun.set_visible_on_player(not riding)
	match to:
		Mode.RIDING:   cam.follow(bike, ChaseCamera.Framing.PLANE if bike.wings_out else ChaseCamera.Framing.BIKE)
		Mode.FLYING:   cam.follow(bike, ChaseCamera.Framing.PLANE)
		Mode.DRIVING:  cam.follow(truck, ChaseCamera.Framing.TRUCK)
		Mode.ON_FOOT:  cam.follow(player, ChaseCamera.Framing.FOOT)
		Mode.SWIMMING: cam.follow(player, ChaseCamera.Framing.SWIM); message.emit("Swimming — head back to the shore to climb out.", 3.0)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if not riding else Input.MOUSE_MODE_VISIBLE


## A clear spot next to the bike (right, left, behind) with a floor under it.
func _dismount_spot() -> Variant:
	var space := vehicle.get_world_3d().direct_space_state
	var side := vehicle.global_transform.basis.x.normalized()
	var back := -vehicle.flat_forward()
	var sh := CapsuleShape3D.new(); sh.radius = 0.28; sh.height = 1.8
	for off in [side * 1.2, -side * 1.2, back * 1.8, side * 2.0, -side * 2.0]:
		var p: Vector3 = vehicle.global_position + off
		var g := world.probe(p + Vector3(0, 0.6, 0))
		if absf(g.height - vehicle.global_position.y) > 3.0: continue   # not the surface the vehicle is on
		var foot := Vector3(p.x, g.height + 0.05, p.z)
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = sh
		q.transform = Transform3D(Basis(), foot + Vector3(0, 0.95, 0))
		q.collision_mask = 1 | 2 | 16
		q.exclude = [vehicle.get_rid()]
		if space.intersect_shape(q, 1).is_empty():
			return foot
	return null


# ---------------------------------------------------------------- persistence
func save_state() -> Dictionary:
	return {"mode": mode, "vehicle": "truck" if vehicle == truck else "bike", "player_pos": player.global_position, "player_forward": player.flat_forward(),
		"stamina": player.stamina, "sprint_exhausted": player.sprint_exhausted, "regen_delay": player.regen_delay}


func load_state(d: Dictionary) -> void:
	var saved_stamina := float(d.get("stamina", player.stamina_max))
	player.stamina = clampf(saved_stamina, 0.0, player.stamina_max) if is_finite(saved_stamina) else player.stamina_max
	player.sprint_exhausted = bool(d.get("sprint_exhausted", false))
	var saved_delay := float(d.get("regen_delay", 0.0))
	player.regen_delay = clampf(saved_delay, 0.0, .65) if is_finite(saved_delay) else 0.0
	var m: int = int(d.get("mode", Mode.RIDING))
	if m == Mode.FLYING: m = Mode.RIDING
	_set_vehicle(truck if d.get("vehicle", "bike") == "truck" else bike)
	if m == Mode.ON_FOOT or m == Mode.SWIMMING:
		player.place(d.get("player_pos", bike.global_position + Vector3(1.2, 0, 0)), d.get("player_forward", bike.flat_forward()))
		_set_mode(Mode.ON_FOOT)
	else:
		_set_mode(Mode.DRIVING if vehicle == truck else Mode.RIDING)
	cam.snap_to_target()
