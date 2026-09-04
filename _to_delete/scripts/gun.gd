class_name GunSystem
extends Node
## A pistol hidden at the Dunes Lookout. Once picked up (walk over it on foot) the boy can fire it
## on foot: hitscan from the camera, muzzle flash, tracer, dust puff, and tin-can targets that pop
## off the fences at the farm and the lookout. Score is shown in the HUD.

signal picked_up
signal fired
signal target_hit(hit: int, total: int)
signal message(text: String, duration: float)

var level: Level
var player: Player
var camera: ChaseCamera
var has_gun := false
var targets_hit := 0
var targets_total := 0
var ammo := 12
var max_ammo := 12
var _reload_t := 0.0
var _cooldown := 0.0
var _pickup: Area3D
var _pistol: Node3D
var _flash: MeshInstance3D
var _flash_t := 0.0
var _tracers: Array = []
var _aim_t := 0.0
var _targets: Array = []
var _pickup_rot := 0.0
var audio: Node
var debug_last := ""

const TARGET_LAYER := 8


func setup(p_level: Level, p_player: Player, p_cam: ChaseCamera) -> void:
	level = p_level
	player = p_player
	camera = p_cam
	_build_pickup()
	_build_targets()
	_pistol = _make_pistol()
	_pistol.visible = false
	player.model.hand_r.add_child(_pistol)
	_pistol.position = Vector3(0, -0.02, -0.06)
	_pistol.rotation_degrees = Vector3(-90, 0, 0)
	_flash = Mats.sphere(0.09, Mats.solid(Color(1.0, 0.85, 0.4), 0.3, 0.0, Color(1.0, 0.7, 0.2)), Vector3(0, 0.07, -0.2), Vector3(1, 1, 1.6), 8)
	_flash.visible = false
	_pistol.add_child(_flash)


func _make_pistol() -> Node3D:
	var n := Node3D.new()
	var steel := Mats.solid(Color(0.22, 0.23, 0.26), 0.45, 0.6)
	var grip := Mats.solid(Color(0.45, 0.30, 0.18), 0.8)
	n.add_child(Mats.box(Vector3(0.035, 0.05, 0.19), steel, Vector3(0, 0.06, -0.06)))   # slide
	n.add_child(Mats.cylinder(0.012, 0.16, steel, Vector3(0, 0.055, -0.08), Vector3(90, 0, 0), 8))
	n.add_child(Mats.box(Vector3(0.03, 0.10, 0.04), grip, Vector3(0, -0.01, 0.02), Vector3(15, 0, 0)))   # grip
	n.add_child(Mats.box(Vector3(0.012, 0.03, 0.015), steel, Vector3(0, 0.02, -0.04)))  # trigger
	return n


func _build_pickup() -> void:
	var loc: Dictionary = level.locations["Dunes Lookout"]
	var pos: Vector3 = loc.pos + Vector3(-3.5, 0.0, 2.5)
	pos.y = level.terrain.height_at(pos.x, pos.z)
	_pickup = Area3D.new()
	_pickup.name = "PistolPickup"
	_pickup.collision_layer = 0
	_pickup.collision_mask = 4
	_pickup.position = pos
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new(); sh.radius = 1.3
	cs.shape = sh; cs.position = Vector3(0, 0.8, 0)
	_pickup.add_child(cs)
	# a wooden crate with the pistol on top and a soft glow so it can be found
	_pickup.add_child(Mats.box(Vector3(0.9, 0.6, 0.9), Mats.solid(Color(0.55, 0.36, 0.22), 0.85), Vector3(0, 0.3, 0)))
	var p := _make_pistol()
	p.name = "Display"
	p.position = Vector3(0, 0.66, 0)
	p.rotation_degrees = Vector3(0, 30, 0)
	p.scale = Vector3(1.6, 1.6, 1.6)
	_pickup.add_child(p)
	var glow_mat := StandardMaterial3D.new()
	glow_mat.albedo_color = Color(0.6, 0.9, 1.0, 0.25)
	glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var beam := Mats.cylinder(0.5, 14.0, glow_mat, Vector3(0, 7.0, 0), Vector3.ZERO, 10, 0.1)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pickup.add_child(beam)
	_pickup.body_entered.connect(_on_pickup_body)
	level.add_child(_pickup)


func _on_pickup_body(body: Node) -> void:
	if has_gun or body != player: return
	has_gun = true
	_pistol.visible = true
	_pickup.queue_free()
	_pickup = null
	picked_up.emit()
	message.emit("You found an old pistol! On foot: aim with the camera, F / left-click to fire. Pop the tin cans!", 7.0)


func _build_targets() -> void:
	# tin cans: one row on top of the farm's stone wall, one on the lookout bench —
	# the hubs say where those surfaces are
	var spots: Array[Vector3] = []
	var farm: Hub = level.hub("Hilltop Farm")
	for i in range(5):
		var p = farm.wall_top(farm.centre.x + 12.0 + i * 1.5)
		if p != null: spots.append(p)
	var lookout: Hub = level.hub("Dunes Lookout")
	for i in range(4):
		spots.append(lookout.bench_top(0.2 + i * 0.2))
	for s in spots:
		var top := 0.0
		var t := Area3D.new()
		t.collision_layer = TARGET_LAYER
		t.collision_mask = 0
		t.position = s
		var can := Node3D.new()
		can.name = "Can"
		can.position = Vector3(0, top, 0)
		var tin := Mats.solid(Color(0.75, 0.78, 0.80), 0.35, 0.7)
		can.add_child(Mats.cylinder(0.11, 0.26, tin, Vector3(0, 0.13, 0), Vector3.ZERO, 10))
		can.add_child(Mats.box(Vector3(0.23, 0.12, 0.02), Mats.solid(Color(0.85, 0.25, 0.2), 0.7), Vector3(0, 0.13, -0.105)))
		t.add_child(can)
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new(); sh.radius = 0.16; sh.height = 0.34
		cs.shape = sh; cs.position = Vector3(0, top + 0.17, 0)
		t.add_child(cs)
		level.add_child(t)
		_targets.append(t)
	targets_total = _targets.size()


## Remaining tin cans (read-only view for the HUD, tests and tools).
func targets() -> Array:
	return _targets.duplicate()


## Where the pistol can be picked up, or null once it has been.
func pickup_position() -> Variant:
	return _pickup.global_position if _pickup else null


## Where the barrel points (world space).
func barrel_direction() -> Vector3:
	return -_pistol.global_transform.basis.z


## Give the boy the pistol without walking over the crate (tools / debug).
func grant() -> void:
	_on_pickup_body(player)


func is_recently_fired() -> bool:
	return _aim_t > 0.0


func can_fire(on_foot: bool) -> bool:
	return has_gun and on_foot and not player.swimming and _cooldown <= 0.0 and ammo > 0


func try_fire(on_foot: bool) -> bool:
	if not can_fire(on_foot):
		if has_gun and on_foot and player.swimming:
			message.emit("Can't shoot while swimming.", 1.5)
		elif has_gun and on_foot and ammo <= 0 and _reload_t <= 0.0:
			_reload_t = 1.2
			message.emit("Reloading...", 1.0)
		elif has_gun and not on_foot:
			message.emit("Hop off the bike (E) to use the pistol.", 2.0)
		return false
	ammo -= 1
	_cooldown = 0.22
	_aim_t = 2.0
	player.aiming = true
	# hitscan: camera ray through the crosshair finds the aim point, then a second ray from
	# the muzzle to that point so the tracer leaves the barrel and nearby cover still blocks
	var ray: Dictionary = camera.view_ray()
	var from: Vector3 = ray.origin
	var dir: Vector3 = ray.direction
	var to := from + dir * 160.0
	var space := player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | TARGET_LAYER)
	q.collide_with_areas = true
	q.collide_with_bodies = true
	q.exclude = [player.get_rid()]
	var hit := space.intersect_ray(q)
	var aim_point: Vector3 = hit.position if hit else to
	var muzzle: Vector3 = _flash.global_position
	var q2 := PhysicsRayQueryParameters3D.create(muzzle, aim_point + (aim_point - muzzle).normalized() * 0.5, 1 | TARGET_LAYER)
	q2.collide_with_areas = true
	q2.collide_with_bodies = true
	q2.exclude = [player.get_rid()]
	var hit2 := space.intersect_ray(q2)
	var end := aim_point
	debug_last = "cam_hit=%s at %s | muzzle=%s muzzle_hit=%s at %s" % [hit.collider.name if hit else "none", aim_point, muzzle, hit2.collider.name if hit2 else "none", hit2.position if hit2 else Vector3.ZERO]
	if hit2:
		end = hit2.position
		var col: Object = hit2.collider
		if col is Area3D and col in _targets:
			_pop_target(col)
		else:
			_impact_puff(hit2.position, hit2.normal)
	camera.shake(0.35)
	_muzzle_and_tracer(end)
	if audio: audio.play_shot()
	fired.emit()
	if ammo == 0:
		_reload_t = 1.2
		message.emit("Reloading...", 1.0)
	return true


func _pop_target(t: Area3D) -> void:
	_targets.erase(t)
	targets_hit += 1
	t.collision_layer = 0
	var can := t.get_node("Can")
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(can, "position", can.position + Vector3(randf_range(-1, 1), 2.2, randf_range(-1, 1)), 0.6).set_ease(Tween.EASE_OUT)
	tw.tween_property(can, "rotation", Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6)), 0.6)
	tw.chain().tween_property(can, "position:y", 0.12, 0.5).set_ease(Tween.EASE_IN)
	_impact_puff(t.global_position + can.position, Vector3.UP)
	target_hit.emit(targets_hit, targets_total)
	if targets_hit == targets_total:
		message.emit("Sharpshooter! All %d cans down." % targets_total, 5.0)
	else:
		message.emit("Ping! %d / %d cans" % [targets_hit, targets_total], 1.5)


func _impact_puff(pos: Vector3, normal: Vector3) -> void:
	var puff := Mats.sphere(0.18, Mats.solid(Color(0.85, 0.78, 0.62), 1.0), pos + normal * 0.1, Vector3.ONE, 8)
	level.add_child(puff)
	var tw := create_tween()
	tw.tween_property(puff, "scale", Vector3(2.2, 2.2, 2.2), 0.35)
	tw.parallel().tween_property(puff, "transparency", 1.0, 0.35)
	tw.tween_callback(puff.queue_free)


func _muzzle_and_tracer(end: Vector3) -> void:
	_flash.visible = true
	_flash_t = 0.06
	var start: Vector3 = _flash.global_position
	var d := end - start
	var len := d.length()
	if len < 0.5: return
	var tr := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.012; cm.bottom_radius = 0.012; cm.height = len; cm.radial_segments = 4
	tr.mesh = cm
	tr.material_override = Mats.solid(Color(1.0, 0.9, 0.6), 0.5, 0.0, Color(1.0, 0.8, 0.4))
	tr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	level.add_child(tr)
	var y := d.normalized()
	var helper := Vector3.RIGHT if absf(y.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var x := helper.cross(y).normalized()
	var z := x.cross(y).normalized()
	tr.global_transform = Transform3D(Basis(x, y, z), (start + end) * 0.5)
	var tw := create_tween()
	tw.tween_property(tr, "transparency", 1.0, 0.12)
	tw.tween_callback(tr.queue_free)


func _process(delta: float) -> void:
	if _cooldown > 0.0: _cooldown -= delta
	if _reload_t > 0.0:
		_reload_t -= delta
		if _reload_t <= 0.0:
			ammo = max_ammo
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0: _flash.visible = false
	if _aim_t > 0.0:
		_aim_t -= delta
		if _aim_t <= 0.0: player.aiming = false
	if _pickup:
		_pickup_rot += delta
		var disp := _pickup.get_node_or_null("Display")
		if disp:
			disp.rotation.y = _pickup_rot
			disp.position.y = 0.72 + sin(_pickup_rot * 2.0) * 0.06


func set_visible_on_player(v: bool) -> void:
	if _pistol: _pistol.visible = v and has_gun
