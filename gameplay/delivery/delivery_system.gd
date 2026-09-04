class_name DeliverySystem
extends Node3D
## Delivery loop: a sequence of JobDefinitions (pick up at A, deliver to B). Zones are Area3D
## cylinders with a tall beacon + floating package icon so they read from far away.
## Stopping (or rolling slowly) inside a zone completes the step automatically.
## Locations come from the WorldDatabase, so the loop does not care what is loaded.
## Facts are published on the EventBus (job_changed, package_collected, delivery_completed).

signal delivery_completed(total: int)
signal package_collected()

enum Stage { TO_PICKUP, TO_DROPOFF, DONE }

var jobs: Array[JobDefinition] = []
var job_index := 0
var stage: int = Stage.TO_PICKUP
var deliveries := 0
var carrying := false
var elapsed := 0.0
var bike: Bike
var db: WorldDatabase
var pickup_zone: Area3D
var dropoff_zone: Area3D
var _zone_timer := 0.0
var _in_zone := false
var _beacon_mat: StandardMaterial3D
var _icon: Node3D
var _all_done := false
var _cooldown := 0.0
var actor: Node3D
var player: Node3D
var rider: Rider
var _foot_hint_shown := false


func set_actor(a: Node3D) -> void:
	actor = a


func setup(p_db: WorldDatabase, p_bike: Bike, p_jobs: Array[JobDefinition]) -> void:
	db = p_db
	bike = p_bike
	jobs = p_jobs
	_beacon_mat = StandardMaterial3D.new()
	_beacon_mat.albedo_color = Color(1.0, 0.80, 0.30, 0.16)
	_beacon_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beacon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beacon_mat.emission_enabled = true
	_beacon_mat.emission = Color(1.0, 0.8, 0.3)
	_beacon_mat.emission_energy_multiplier = 1.4
	_beacon_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beacon_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_start_job(0)


func current_job() -> JobDefinition:
	if job_index < jobs.size():
		return jobs[job_index]
	return null


func target_location() -> StringName:
	var j := current_job()
	if j == null: return &""
	return j.from_location if stage == Stage.TO_PICKUP else j.to_location


func target_position() -> Vector3:
	var id := target_location()
	return db.location_pos(id) if id != &"" else Vector3.ZERO


func target_name() -> String:
	var id := target_location()
	return db.location_name(id) if id != &"" else ""


func _say(text: String, duration: float) -> void:
	Events.message.emit(text, duration)


func _make_zone(pos: Vector3, radius: float) -> Area3D:
	var a := Area3D.new()
	a.collision_layer = 0
	a.collision_mask = 2 | 4
	a.position = pos
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = radius
	sh.height = 8.0
	cs.shape = sh
	cs.position = Vector3(0, 3.0, 0)
	a.add_child(cs)
	# ground ring
	var ring := Mats.torus(radius - 0.35, radius, _beacon_mat, Vector3(0, 0.25, 0), Vector3.ZERO, Vector3(1, 0.4, 1))
	a.add_child(ring)
	# tall soft beacon
	var beam := Mats.cylinder(0.7, 50.0, _beacon_mat, Vector3(0, 25.0, 0), Vector3.ZERO, 12, 0.12)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	a.add_child(beam)
	# floating package icon
	var icon := Node3D.new()
	icon.name = "Icon"
	icon.position = Vector3(0, 3.6, 0)
	icon.add_child(Mats.box(Vector3(1.0, 0.7, 0.8), Mats.solid(Color(0.74, 0.80, 0.62), 0.8, 0, Color(0.3, 0.35, 0.2)), Vector3.ZERO))
	icon.add_child(Mats.box(Vector3(1.04, 0.1, 0.1), Mats.solid(Color(0.85, 0.72, 0.4), 0.8), Vector3.ZERO))
	icon.add_child(Mats.box(Vector3(0.1, 0.1, 0.84), Mats.solid(Color(0.85, 0.72, 0.4), 0.8), Vector3.ZERO))
	a.add_child(icon)
	add_child(a)
	return a


func _clear_zones() -> void:
	if pickup_zone: pickup_zone.queue_free(); pickup_zone = null
	if dropoff_zone: dropoff_zone.queue_free(); dropoff_zone = null


func _start_job(i: int) -> void:
	_clear_zones()
	job_index = i
	if job_index >= jobs.size():
		stage = Stage.DONE
		_all_done = true
		Events.job_changed.emit(null, &"done")
		_say("All deliveries done! Ride free, or press R by a road to reset. Total: %d packages in %s" % [deliveries, format_time(elapsed)], 12.0)
		return
	stage = Stage.TO_PICKUP
	carrying = false
	bike.visual.set_package_visible(false)
	var j := current_job()
	pickup_zone = _make_zone(db.location_pos(j.from_location), 6.0)
	Events.job_changed.emit(j, &"pickup")
	if deliveries == 0:
		_say("New job: collect the %s at %s" % [j.item, db.location_name(j.from_location)], 5.0)
	else:
		get_tree().create_timer(2.6).timeout.connect(func(): _say("Next job: %s → %s" % [j.item, db.location_name(j.to_location)], 4.0))


func _process(delta: float) -> void:
	if _all_done: return
	elapsed += delta
	if _cooldown > 0.0:
		_cooldown -= delta
		return
	var zone := pickup_zone if stage == Stage.TO_PICKUP else dropoff_zone
	if zone == null: return
	var icon := zone.get_node_or_null("Icon")
	if icon:
		icon.rotation.y += delta * 1.2
		icon.position.y = 3.6 + sin(Time.get_ticks_msec() * 0.003) * 0.25
	var inside := zone.overlaps_body(bike)
	var sp: float = absf(bike.speed)
	if player and not _foot_hint_shown and zone.overlaps_body(player):
		_foot_hint_shown = true
		_say("The package rides on the bike — bring the bike into the ring.", 3.5)
	if inside and sp < 2.5 and (rider == null or rider.is_riding()):
		_zone_timer += delta
		if _zone_timer > 0.5:
			_complete_stage()
			_zone_timer = 0.0
	else:
		_zone_timer = 0.0
	if inside != _in_zone:
		_in_zone = inside
		if inside:
			_say("Slow down to %s" % ("collect the package" if stage == Stage.TO_PICKUP else "hand over the package"), 3.0)


func _complete_stage() -> void:
	var j := current_job()
	if stage == Stage.TO_PICKUP:
		stage = Stage.TO_DROPOFF
		carrying = true
		bike.visual.set_package_visible(true)
		if pickup_zone: pickup_zone.queue_free(); pickup_zone = null
		dropoff_zone = _make_zone(db.location_pos(j.to_location), 6.5)
		package_collected.emit()
		Events.package_collected.emit(j.id)
		Events.job_changed.emit(j, &"dropoff")
		_say("Package on the rack! Deliver the %s to %s." % [j.item, db.location_name(j.to_location)], 5.0)
	elif stage == Stage.TO_DROPOFF:
		deliveries += 1
		carrying = false
		bike.visual.set_package_visible(false)
		delivery_completed.emit(deliveries)
		Events.delivery_completed.emit(j.id, deliveries)
		_say("Delivered! +%d coins  (%d/%d)" % [j.reward, deliveries, jobs.size()], 4.0)
		_cooldown = 2.5
		_start_job(job_index + 1)


func save_state() -> Dictionary:
	return {"job_index": job_index, "stage": stage, "deliveries": deliveries, "elapsed": elapsed}


func load_state(d: Dictionary) -> void:
	deliveries = int(d.get("deliveries", 0))
	elapsed = float(d.get("elapsed", 0.0))
	_all_done = false
	_start_job(int(d.get("job_index", 0)))
	if int(d.get("stage", Stage.TO_PICKUP)) == Stage.TO_DROPOFF and stage == Stage.TO_PICKUP:
		_complete_stage()   # re-collect the package silently
		_cooldown = 0.0


static func format_time(t: float) -> String:
	var m := int(t / 60.0)
	var s := int(t) % 60
	return "%d:%02d" % [m, s]
