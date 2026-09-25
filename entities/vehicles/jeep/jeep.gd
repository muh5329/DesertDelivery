class_name Jeep
extends Vehicle
## The courier's Jeep (from LegendOfJeep): a 4x4 that drives on the shared GroundDrive
## (data/vehicles/jeep.tres: its top speed, torque, steering fall-off, handbrake drift and boost
## tank, retuned for this island) and, being amphibious, floats and planes across the sea, the
## lagoon, the estuary and the lakes on its own PlaningDrive, then drives back out where the bed
## rises again. What is the Jeep's own is up here: the water, the boost, the front winch it
## inherited from the old cargo truck, and the small load bed behind the seats.
##
## A Cart can be hitched behind it (the Rig). A cart cannot float, so with one hitched the Jeep
## stays a land vehicle: deep water is a splash and a recovery for the whole rig.

signal crashed
signal landed(impact: float)
signal denied(text: String)
signal winch_changed(attached: bool, distance: float)
signal fell_in_sea
signal water_entered
signal water_exited

const BED_CAPACITY := 120.0
## Out of fuel the engine limps, like the bike's (Bike.LIMP_SPEED).
const LIMP_SPEED := 6.0
const LIMP_ACCEL := 1.6

var afloat := false
var boost_left := 0.0
var boosting := false
var bed := Inventory.new(BED_CAPACITY, "Jeep bed")
var winch_attached := false
var winch_range := 38.0
var winch_pull_speed := 10.5
var winch_distance := 0.0
var water: PlaningDrive

var _dust: CPUParticles3D
var _anchor_node: Node3D
var _anchor_local := Vector3.ZERO
var _anchor_static := Vector3.ZERO
var _wheel_offsets: Array = []
var _bank_t := 0.0


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | 16
	# the tub and bonnet ride on the floor solver like the truck did; the roll cage above
	var cs := CollisionShape3D.new(); cs.name = "Body"
	var shape := BoxShape3D.new(); shape.size = Vector3(1.78, 1.30, 3.78)
	cs.shape = shape; cs.position = Vector3(0, 0.65, 0.0); add_child(cs)
	var cage := CollisionShape3D.new(); cage.name = "Cage"
	var cage_shape := BoxShape3D.new(); cage_shape.size = Vector3(1.66, 0.80, 2.2)
	cage.shape = cage_shape; cage.position = Vector3(0, 1.70, 0.45); add_child(cage)
	floor_max_angle = deg_to_rad(62.0)
	floor_snap_length = 0.72
	safe_margin = 0.035
	var wb: float = definition.wheelbase if definition else 2.45
	# FL, FR, RL, RR, the order the visual's wheels are in
	_wheel_offsets = [Vector3(-0.80, 1.0, -wb * 0.5), Vector3(0.80, 1.0, -wb * 0.5), Vector3(-0.80, 1.0, wb * 0.5), Vector3(0.80, 1.0, wb * 0.5)]
	_build_drive(_wheel_offsets, 2.8)
	water = PlaningDrive.new(self, definition, drive)
	water.terrain = terrain
	boost_left = definition.boost_seconds
	visual = JeepVisual.new(); visual.name = "JeepVisual"; add_child(visual)
	bed.changed.connect(func(): if visual: visual.show_bed(bed))
	_build_dust()


func _build_dust() -> void:
	_dust = CPUParticles3D.new(); _dust.amount = 64; _dust.lifetime = 1.5
	_dust.position = Vector3(0, 0.18, 1.7); _dust.direction = Vector3(0, 0.45, 1)
	_dust.spread = 38; _dust.initial_velocity_min = 1.2; _dust.initial_velocity_max = 3.2
	_dust.gravity = Vector3(0, 0.5, 0); _dust.damping_min = 1.0; _dust.damping_max = 2.0
	_dust.local_coords = false
	var mesh := SphereMesh.new(); mesh.radius = 0.28; mesh.height = 0.56; mesh.radial_segments = 7; mesh.rings = 4
	var mat := StandardMaterial3D.new(); mat.albedo_color = Color(0.84, 0.72, 0.52, 0.2)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mat; _dust.mesh = mesh; _dust.emitting = false
	_dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_dust)


## Q fires the winch; Shift (the reading's `run`) is the boost. Everything else is a ground
## vehicle's — the same keys drive it afloat.
class JeepScheme:
	extends Vehicle.GroundScheme
	func map(r: Controls.Reading, i: Controls.Intent) -> void:
		super.map(r, i)
		if r.just(&"winch"): i.press(Controls.WINCH)


func _make_scheme() -> Controls.Scheme:
	return JeepScheme.new(self)


func apply(intent: Controls.Intent) -> void:
	super.apply(intent)
	if intent.pressed(Controls.WINCH): toggle_winch()


## Somebody is at the wheel (the visual's brake lamps, the engine audio).
func driven() -> bool:
	return not parked


func place(pos: Vector3, forward: Vector3) -> void:
	_leave_water(false)
	_bank_t = 0.0
	detach_winch()
	super.place(pos, forward)


func reset_to_road(away_from_sea: bool = false) -> void:
	detach_winch()
	_leave_water(false)
	super.reset_to_road(away_from_sea)


func status_line() -> String:
	if afloat: return "Jeep · afloat"
	if winch_attached: return "Jeep · winch %.0fm" % winch_distance
	return "Jeep"


## Suspension travel of wheel i (FL, FR, RL, RR) from its contact ray: + is compressed.
func wheel_travel(i: int) -> float:
	if drive == null or i >= drive._rays.size(): return 0.0
	var ray: RayCast3D = drive._rays[i]
	if not ray.is_colliding(): return -JeepVisual.TRAVEL
	var hit := to_local(ray.get_collision_point())
	var o: Vector3 = _wheel_offsets[i]
	return clampf(hit.y, -JeepVisual.TRAVEL, JeepVisual.TRAVEL) if absf(hit.x - o.x) < 0.5 else 0.0


# ---------------------------------------------------------------- winch (from the cargo truck)
func toggle_winch() -> void:
	if winch_attached:
		detach_winch()
		return
	if afloat:
		denied.emit("The winch needs the wheels on the ground.")
		return
	_fire_winch()


func _fire_winch() -> bool:
	var space := get_world_3d().direct_space_state
	var origin := global_position + flat_forward() * 2.05 + Vector3(0, 0.62, 0)
	# The higher casts make walls and tree trunks useful climbing anchors; the shallow cast catches
	# low rocks and roadside obstacles. Closest successful cast wins.
	var best: Dictionary = {}
	var best_distance := INF
	for rise in [0.30, 0.17, 0.06]:
		var direction: Vector3 = (flat_forward() + Vector3.UP * float(rise)).normalized()
		var q := PhysicsRayQueryParameters3D.create(origin, origin + direction * winch_range, 1)
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		if hit and origin.distance_to(hit.position) < best_distance:
			best = hit; best_distance = origin.distance_to(hit.position)
	if best.is_empty():
		denied.emit("No tree or obstacle in winch range.")
		return false
	_anchor_static = best.position
	_anchor_node = best.collider as Node3D
	if _anchor_node: _anchor_local = _anchor_node.to_local(best.position)
	winch_attached = true; winch_distance = best_distance
	winch_changed.emit(true, best_distance)
	return true


func attach_winch_for_test(world_point: Vector3) -> void:
	_anchor_node = null; _anchor_static = world_point
	winch_attached = true; winch_distance = global_position.distance_to(world_point)
	winch_changed.emit(true, winch_distance)


func detach_winch() -> void:
	if not winch_attached: return
	winch_attached = false; winch_distance = 0.0; _anchor_node = null
	winch_changed.emit(false, 0.0)


func winch_anchor_world() -> Vector3:
	if _anchor_node and is_instance_valid(_anchor_node): return _anchor_node.to_global(_anchor_local)
	return _anchor_static


# ---------------------------------------------------------------- driving
func fuel_ratio() -> float:
	return clampf(float(get_meta("fuel_ratio", 1.0)), 0.0, 1.0)


## A full bed and a towed cart cost top speed and pull; an empty tank limps; the boost adds a
## burst on top. Everything else the Jeep drives on comes from its .tres.
func _drive_mods() -> GroundDrive.Mods:
	var m := super._drive_mods()
	var bed_scale := 1.0 / (1.0 + bed.mass() / 600.0)
	m.top_speed *= bed_scale
	m.motor_accel *= bed_scale
	if boosting:
		m.top_speed *= definition.boost_top
		m.motor_accel += definition.boost_accel
	if fuel_ratio() <= 0.001:
		m.motor_accel = LIMP_ACCEL
		m.soft_limit = LIMP_SPEED
		m.reverse_limit = minf(m.reverse_limit, LIMP_SPEED)
	return m


func _update_boost(delta: float) -> void:
	var want := drive.intent.boost and boost_left > 0.05 and drive.throttle > 0.1 and fuel_ratio() > 0.001
	boosting = want
	if boosting: boost_left = maxf(0.0, boost_left - delta)
	else: boost_left = minf(definition.boost_seconds, boost_left + delta * definition.boost_refill)


func _physics_process(delta: float) -> void:
	if water.terrain != terrain: water.terrain = terrain
	if parked:
		if afloat:
			drive.throttle = 0.0; drive.brake = 0.0; drive.steer = 0.0
			water.step(delta)
		else:
			drive.idle(delta)
		if visual: visual.update_visual(self, delta)
		_dust.emitting = false
		return
	drive.mods = _drive_mods()
	drive.read_intent(delta)
	_update_boost(delta)
	update_tether()
	if afloat:
		if water.step(delta, 1.0 / (1.0 + bed.mass() / 600.0), boosting):
			_leave_water(true)
		if visual: visual.update_visual(self, delta)
		_dust.emitting = false
		return
	_winch_pull(delta)
	_bank_climb(delta)
	var tick := drive.step(delta)
	drive.climbing = false
	if tick.crashed: crashed.emit()
	if tick.landed_impact >= 0.0:
		landed.emit(tick.landed_impact)
		if visual: visual.landed(tick.landed_impact)
		if tick.landed_impact > definition.hard_landing_impact: crashed.emit()
	if can_float() and _bank_t <= 0.0 and water.should_float(global_position):
		_enter_water()
	elif tick.in_sea and not can_float():
		fell_in_sea.emit()
		reset_to_road(true)
	if visual: visual.update_visual(self, delta)
	# dust off the road (or in a slide), not in a trail down the asphalt
	var off_road: bool = terrain == null or terrain.road_dist_at(global_position.x, global_position.z) > 4.0
	_dust.emitting = grounded and absf(speed) > definition.dust_min_speed and not _wet() and (off_road or drive.slip > 0.3)


## A cart cannot float: with one hitched the Jeep is a land vehicle.
func can_float() -> bool:
	return definition.amphibious and not is_towing()


func _wet() -> bool:
	if terrain == null: return false
	return global_position.y < terrain.water_level_at(global_position.x, global_position.z) + 0.1


func _winch_pull(delta: float) -> void:
	# A taut cable reels in the drivetrain, so the winch can pull even with no throttle.
	if not winch_attached: return
	var anchor := winch_anchor_world()
	var hook := global_position + flat_forward() * 1.95 + Vector3(0, 0.6, 0)
	var cable := anchor - hook
	winch_distance = cable.length()
	if winch_distance < 1.45:
		detach_winch()
		return
	var anchor_dir := cable / winch_distance
	speed += anchor_dir.dot(flat_forward()) * 8.5 * delta
	var reel_speed := minf(winch_pull_speed, maxf(3.0, (winch_distance - 1.4) * 1.5))
	drive.extra_velocity = anchor_dir * reel_speed
	# A cable fixed above the bumper gives deliberate wall-climbing lift instead of pinning
	# the Jeep endlessly against the first vertical face it touches.
	if anchor_dir.y > 0.04:
		drive.min_vertical = anchor_dir.y * reel_speed + 1.4
		drive.climbing = true


## Out of the water where the shore has a step (the island's beaches drop a metre or two at the
## waterline): for a few seconds the wheels claw up a bank in front of them, the way the winch
## lifts the jeep up a face (LegendOfJeep's rigid body did it with its springs). Meanwhile it
## does not float again, so it cannot bob back and forth at the step.
func _bank_climb(delta: float) -> void:
	if _bank_t <= 0.0 or terrain == null: return
	_bank_t -= delta
	if drive.throttle < 0.2: return
	var ahead := global_position + flat_forward() * (definition.wheelbase * 0.5 + 0.9)
	var rise := terrain.height_at(ahead.x, ahead.z) - global_position.y
	if rise > 0.15 and rise < 2.4:
		drive.min_vertical = 2.2
		drive.climbing = true
		speed = maxf(speed, 1.5)


func _enter_water() -> void:
	if afloat: return
	afloat = true
	detach_winch()
	# the splash: water takes the speed off a jeep that hits it fast
	speed = minf(speed * 0.6, definition.water_max_speed * 1.1)
	drive.grounded = false
	drive.slip = 0.0
	water.reset()
	water_entered.emit()


func _leave_water(announce: bool) -> void:
	if not afloat: return
	afloat = false
	water.reset()
	drive.grounded = true
	drive.ground_normal = Vector3.UP
	rotation = Vector3(0, drive.yaw, 0)
	if announce:
		_bank_t = 3.0
		water_exited.emit()


func save_state() -> Dictionary:
	var d := super.save_state()
	d["bed"] = bed.save_state()
	d["afloat"] = afloat
	d["boost"] = boost_left
	return d


func load_state(d: Dictionary) -> void:
	super.load_state(d)
	var items: Variant = d.get("bed", {})
	if not (items is Dictionary and bed.restore_contents(items)): bed.clear()
	boost_left = clampf(float(d.get("boost", definition.boost_seconds)), 0.0, definition.boost_seconds)
	# saved afloat: it floats again where it was (place() put it on the surface's level)
	if bool(d.get("afloat", false)) and can_float() and water.water_at(global_position).depth > definition.float_depth:
		_enter_water()


func exit_block() -> String:
	return "Drive up onto a beach first: you can't step out onto the water." if afloat else ""


## The middle of the load bed behind the seats, in world space (loading reach).
func bed_point() -> Vector3:
	return global_transform * Vector3(0, 1.1, 1.2)
