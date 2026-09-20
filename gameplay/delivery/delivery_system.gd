class_name DeliverySystem
extends Node3D
## Delivery loop: a sequence of JobDefinitions (pick up at A, deliver to B). Zones are Area3D
## cylinders with a tall beacon + floating package icon so they read from far away.
## Stopping (or rolling slowly) inside a zone completes the step automatically.
## Locations come from the WorldDatabase, so the loop does not care what is loaded.
## Facts are published on the EventBus (job_changed, package_collected, delivery_completed).

signal delivery_completed(total: int)
signal package_collected()
signal wallet_changed(coins: int)

enum Stage { TO_PICKUP, TO_DROPOFF, DONE }

var jobs: Array[JobDefinition] = []
var job_index := 0
var stage: int = Stage.TO_PICKUP
var deliveries := 0
var carrying := false
var elapsed := 0.0
var coins := 0
var _revision := 0
var _transitioning := false
## Bounded delivery receipts make payouts inspectable and persist with the wallet.
var receipts: Array[Dictionary] = []
var active_job_override: JobDefinition
var handoffs_paused := false
var _foot_package: Node3D
var bike: Bike
var vehicle: Vehicle
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
## Fragile cargo: 1.0 intact .. 0.0 wrecked. Only the courier's own vehicle crashing or landing
## hard damages it, once per impact (the cooldown stops one collision counting every frame).
var parcel_condition := 1.0
var _impact_cooldown := 0.0
const CRASH_DAMAGE := 0.22
const LANDING_THRESHOLD := 8.0
const LANDING_DAMAGE := 0.12


func set_actor(a: Node3D) -> void:
	actor = a


func setup(p_db: WorldDatabase, p_bike: Bike, p_jobs: Array[JobDefinition]) -> void:
	db = p_db
	bike = p_bike
	vehicle = p_bike
	jobs = p_jobs
	_beacon_mat = StandardMaterial3D.new()
	_beacon_mat.albedo_color = Color(1.0, 0.80, 0.30, 0.12)
	_beacon_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beacon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beacon_mat.emission_enabled = true
	_beacon_mat.emission = Color(1.0, 0.8, 0.3)
	_beacon_mat.emission_energy_multiplier = 0.45
	_beacon_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beacon_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	if not Events.vehicle_crashed.is_connected(_on_vehicle_crashed):
		Events.vehicle_crashed.connect(_on_vehicle_crashed)
		Events.vehicle_landed.connect(_on_vehicle_landed)
	_start_job(0)


func _carrying_fragile() -> bool:
	var j := current_job()
	return carrying and j != null and j.cargo_kind == "fragile"


func _is_courier_vehicle(id: StringName) -> bool:
	return vehicle != null and vehicle.entity_id == id


func _damage_parcel(amount: float) -> void:
	if _impact_cooldown > 0.0: return
	parcel_condition = clampf(parcel_condition - amount, 0.0, 1.0)
	_impact_cooldown = 0.5


func _on_vehicle_crashed(id: StringName) -> void:
	if _carrying_fragile() and _is_courier_vehicle(id): _damage_parcel(CRASH_DAMAGE)


func _on_vehicle_landed(id: StringName, impact: float) -> void:
	if impact > LANDING_THRESHOLD and _carrying_fragile() and _is_courier_vehicle(id):
		_damage_parcel(LANDING_DAMAGE * (impact / LANDING_THRESHOLD))


## What the current job really pays: fragile cargo loses up to half its value as it breaks.
func current_payout() -> int:
	var j := current_job()
	if j == null: return 0
	if j.cargo_kind == "fragile": return roundi(j.reward * (0.5 + 0.5 * parcel_condition))
	return j.reward


func set_vehicle(next: Vehicle) -> void:
	if next == vehicle: return
	if vehicle: vehicle.set_package_visible(false)
	vehicle = next
	if vehicle: vehicle.set_package_visible(carrying)


func current_job() -> JobDefinition:
	if active_job_override != null: return active_job_override
	if job_index >= 0 and job_index < jobs.size():
		return jobs[job_index]
	return null


func target_location() -> StringName:
	var j := current_job()
	if j == null or stage == Stage.DONE: return &""
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
	a.set_meta("radius", radius)
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
	# a thin, short beacon post (r4 critique item 9: the 50 m x 0.7 m beam was a pole through the
	# whole villa frame; 14 m tapering to nothing still reads over the trees at road distance)
	var beam := Mats.cylinder(0.28, 14.0, _beacon_mat, Vector3(0, 7.0, 0), Vector3.ZERO, 10, 0.0)
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


func _start_job(i: int, announce: bool = true, publish: bool = true) -> void:
	_clear_zones()
	active_job_override = null
	_revision += 1
	_zone_timer = 0.0; _in_zone = false; _foot_hint_shown = false
	job_index = clampi(i, 0, jobs.size())
	carrying = false
	_all_done = false
	vehicle.set_package_visible(false)
	if job_index >= jobs.size():
		stage = Stage.DONE
		_all_done = true
		if publish: Events.job_changed.emit(null, &"done")
		if announce: _say("Route list complete! Visit a courier counter for another job. Total: %d packages in %s" % [deliveries, format_time(elapsed)], 12.0)
		return
	stage = Stage.TO_PICKUP
	carrying = false
	vehicle.set_package_visible(false)
	var j := current_job()
	pickup_zone = _make_zone(db.location_pos(j.from_location), 6.0)
	if publish: Events.job_changed.emit(j, &"pickup")
	if not announce: return
	if deliveries == 0:
		_say("New job: collect the %s at %s" % [j.item, db.location_name(j.from_location)], 5.0)
	else:
		var revision := _revision
		get_tree().create_timer(2.6).timeout.connect(func():
			if revision == _revision: _say("Next job: %s → %s" % [j.item, db.location_name(j.to_location)], 4.0))


func _process(delta: float) -> void:
	_sync_package_visuals()
	if _all_done: return
	elapsed += delta
	if handoffs_paused:
		_zone_timer = 0.0
		return
	if _impact_cooldown > 0.0: _impact_cooldown -= delta
	if _cooldown > 0.0:
		_cooldown -= delta
		return
	var zone := pickup_zone if stage == Stage.TO_PICKUP else dropoff_zone
	if zone == null: return
	var icon := zone.get_node_or_null("Icon")
	if icon:
		icon.rotation.y += delta * 1.2
		icon.position.y = 3.6 + sin(Time.get_ticks_msec() * 0.003) * 0.25
	var courier: Node3D = player if rider and rider.is_on_foot() else vehicle
	if courier == null: return
	var inside := _contains_courier(zone, courier)
	var velocity_speed := 0.0
	if courier is CharacterBody3D:
		velocity_speed = Vector2(courier.velocity.x, courier.velocity.z).length()
	var speed := maxf(velocity_speed, absf(vehicle.speed)) if courier == vehicle else velocity_speed
	var available := rider == null or rider.mode == Rider.Mode.RIDING or rider.mode == Rider.Mode.DRIVING or rider.mode == Rider.Mode.ON_FOOT
	if courier == vehicle: available = available and vehicle.grounded
	elif courier is CharacterBody3D: available = available and courier.is_on_floor()
	if inside and speed < 2.5 and available:
		_zone_timer += delta
		if _zone_timer >= 0.5:
			_complete_stage()
			_zone_timer = 0.0
	else:
		_zone_timer = 0.0
	if inside != _in_zone:
		_in_zone = inside
		if inside:
			_say("Slow down to %s" % ("collect the package" if stage == Stage.TO_PICKUP else "hand over the package"), 3.0)


func _complete_stage() -> void:
	if _transitioning: return
	var j := current_job()
	if j == null or stage == Stage.DONE: return
	_transitioning = true
	_in_zone = false; _zone_timer = 0.0
	if stage == Stage.TO_PICKUP:
		stage = Stage.TO_DROPOFF
		carrying = true
		parcel_condition = 1.0
		_impact_cooldown = 0.0
		vehicle.set_package_visible(true)
		if pickup_zone: pickup_zone.queue_free(); pickup_zone = null
		dropoff_zone = _make_zone(db.location_pos(j.to_location), 6.5)
		package_collected.emit()
		Events.package_collected.emit(j.id)
		Events.job_changed.emit(j, &"dropoff")
		_say("Package loaded! Deliver the %s to %s." % [j.item, db.location_name(j.to_location)], 5.0)
	elif stage == Stage.TO_DROPOFF:
		deliveries += 1
		var paid := current_payout()
		coins += paid
		receipts.append({"job_id":String(j.id),"item":j.item,"coins":paid,"condition":parcel_condition,"elapsed":elapsed,"delivery":deliveries})
		if receipts.size()>32: receipts.pop_front()
		# Commit cargo and stage before publishing any transaction callbacks.
		stage = Stage.DONE
		carrying = false
		vehicle.set_package_visible(false)
		parcel_condition = 1.0
		_cooldown = 2.5
		_start_job(job_index + 1)
		wallet_changed.emit(coins)
		delivery_completed.emit(deliveries)
		Events.delivery_completed.emit(j.id, deliveries)
		_say("Delivered! +%d coins · %d completed" % [paid, deliveries], 4.0)
	_transitioning = false


func _contains_courier(zone: Area3D, courier: Node3D) -> bool:
	# Body origins are at the feet/wheel contact. A 3D area alone accepts a truck roof
	# or a hovering aircraft, so require the actual courier to be at the handoff height.
	var offset := courier.global_position - zone.global_position
	return Vector2(offset.x, offset.z).length() <= float(zone.get_meta("radius", 6.0)) and absf(offset.y) < 1.6


func _sync_package_visuals() -> void:
	var on_foot := rider != null and rider.is_on_foot()
	if vehicle: vehicle.set_package_visible(carrying and not on_foot)
	if player and _foot_package == null and player.get("model"):
		_foot_package = Node3D.new(); _foot_package.name = "CourierParcel"
		player.model.torso.add_child(_foot_package)
		var paper := Mats.solid(Color(.70,.59,.37),.88)
		var cord := Mats.solid(Color(.33,.23,.12),.9)
		_foot_package.add_child(Mats.box(Vector3(.28,.32,.16),paper,Vector3(0,.28,.20)))
		_foot_package.add_child(Mats.box(Vector3(.025,.33,.17),cord,Vector3(0,.28,.20)))
		_foot_package.add_child(Mats.box(Vector3(.29,.024,.17),cord,Vector3(0,.28,.20)))
	if _foot_package: _foot_package.visible = carrying and on_foot


func save_state() -> Dictionary:
	var job := current_job()
	var data := {"version":2, "receipts":receipts.duplicate(true), "job_id": String(job.id) if job else "", "job_index": job_index, "stage": stage, "deliveries": deliveries, "elapsed": elapsed, "coins": coins, "parcel_condition": parcel_condition}
	if active_job_override:
		data["offer"]={"kind":active_job_override.cargo_kind,"mass_kg":active_job_override.cargo_mass_kg,"reward":active_job_override.reward}
	return data


func load_state(d: Dictionary) -> void:
	if _transitioning: return
	_transitioning = true
	receipts.clear()
	for receipt in d.get("receipts", []):
		if receipt is Dictionary: receipts.append(receipt.duplicate(true))
	while receipts.size()>32: receipts.pop_front()
	_impact_cooldown=0.0
	deliveries = maxi(0, int(d.get("deliveries", 0)))
	elapsed = maxf(0.0, float(d.get("elapsed", 0.0)))
	coins = maxi(0, int(d.get("coins", 0)))
	var index := int(d.get("job_index", 0))
	if d.has("job_id") and not String(d.job_id).is_empty():
		for i in range(jobs.size()):
			if String(jobs[i].id) == String(d.job_id): index = i; break
	_cooldown = 0.0
	_start_job(index, false, false)
	if stage != Stage.DONE and d.get("offer",{}) is Dictionary and not d.get("offer",{}).is_empty():
		_apply_offer(d.offer)
	# Restore the stage directly: loading must never collect again, award coins, or emit
	# package/delivery events (other systems use those events for real transactions).
	if int(d.get("stage", Stage.TO_PICKUP)) == Stage.TO_DROPOFF and stage == Stage.TO_PICKUP:
		stage = Stage.TO_DROPOFF; carrying = true
		_clear_zones()
		dropoff_zone = _make_zone(db.location_pos(current_job().to_location), 6.5)
	parcel_condition = clampf(float(d.get("parcel_condition", 1.0)), 0.0, 1.0)
	_sync_package_visuals()
	Events.job_changed.emit(current_job(), &"done" if stage==Stage.DONE else (&"dropoff" if carrying else &"pickup"))
	wallet_changed.emit(coins)
	_transitioning = false


func select_board_offer(index: int, offer: Dictionary) -> bool:
	# Selecting a route is a reversible choice until a parcel has actually been collected.
	if _transitioning or carrying or index<0 or index>=jobs.size(): return false
	var kind:=String(offer.get("kind",""))
	if kind not in ["light","fragile","heavy"]: return false
	_transitioning = true
	_start_job(index,false,false)
	_apply_offer(offer)
	_cooldown=0.0
	Events.job_changed.emit(current_job(), &"pickup")
	_transitioning = false
	return true

func _apply_offer(offer: Dictionary) -> void:
	active_job_override=jobs[job_index].duplicate()
	active_job_override.cargo_kind=String(offer.get("kind","standard"))
	active_job_override.cargo_mass_kg=clampf(float(offer.get("mass_kg",0.0)),0.0,80.0)
	active_job_override.reward=maxi(0,int(offer.get("reward",jobs[job_index].reward)))

func spend_coins(amount: int) -> bool:
	if amount<0 or coins<amount: return false
	coins-=amount
	wallet_changed.emit(coins)
	return true


static func format_time(t: float) -> String:
	var m := int(t / 60.0)
	var s := int(t) % 60
	return "%d:%02d" % [m, s]
