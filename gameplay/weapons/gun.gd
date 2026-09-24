class_name GunSystem
extends Node3D
## The courier's M1 Garand: his primary weapon from the first minute. Semi-automatic, fed by
## 8-round en-bloc clips — the 8th shot throws the empty clip out with the famous "ping", a
## reload presses a fresh clip in and the bolt slams home; a part-empty clip can be ejected
## (and its loose rounds kept) with a manual reload. Hitscan down the crosshair with spread
## (hip vs. aimed, movement, bloom), damage falling off with range, headshots x2.5, a tracer,
## muzzle flash and smoke, and an impact per surface. The tin cans at the farm wall and the
## lookout bench are still there for practice; the crate at the Dunes Lookout (where the old
## pistol used to lie) is now a cache of clips.
##
## Interface (the Rider, HUD, tests and the encounter director use these):
##   try_fire(on_foot) -> bool      try_reload() -> bool      set_aim(bool)
##   current_spread() -> float      (degrees, half-angle)     add_ammo(clips, rounds) -> int
##   ammo / max_ammo / reserve_clips / loose_rounds / reloading / reload_progress()
##   signals fired, clip_pinged, reloaded, hit_confirmed(id, headshot, killed), target_hit(h, t)

signal picked_up
signal fired
signal clip_pinged
signal reloaded
signal hit_confirmed(entity_id: StringName, headshot: bool, killed: bool)
signal target_hit(hit: int, total: int)
signal message(text: String, duration: float)

const CLIP := 8
const MAX_RESERVE := 12
const MAX_LOOSE := CLIP * 2 - 1   # a part clip ejected with a full pouch still fits
const TARGET_LAYER := 8
const HURTBOX_LAYER := 32
const SHOT_MASK := 1 | 2 | TARGET_LAYER | 16 | HURTBOX_LAYER
const RANGE := 400.0
const DAMAGE := 60.0
const HEADSHOT := 2.5
const FALLOFF_START := 60.0       # full damage to here (m) ...
const FALLOFF_END := 300.0        # ... then linearly down to FALLOFF_MIN at this range
const FALLOFF_MIN := 0.55
const COOLDOWN := 0.14            # semi-auto: as fast as the trigger resets, not faster
const RELOAD_TIME := 1.9
const SPREAD_HIP := 2.6           # degrees, half-angle of the shot cone
const SPREAD_ADS := 0.22
const SPREAD_MOVE_HIP := 1.6      # extra at walking speed (scales with speed)
const SPREAD_MOVE_ADS := 0.7
const SPREAD_AIR := 3.0
const BLOOM_HIP := 0.9            # per shot, decays at BLOOM_DECAY deg/s
const BLOOM_ADS := 0.35
const BLOOM_DECAY := 5.0
const RECOIL_ADS := 0.032         # camera kick (rad), recovered by the camera
const RECOIL_HIP := 0.05
const LOUDNESS := 240.0           # enemies hear the crack inside this radius (fight within 45 %, look beyond)

var db: WorldDatabase
var world: WorldManager
var entities: EntityManager
var player: Player
var camera: ChaseCamera
var fx: CombatFx
var sounds: WeaponAudio
var audio: Node                    # the engine audio (kept for compatibility; unused)

var has_gun := true
var ammo := CLIP
var max_ammo := CLIP
var reserve_clips := 4
var loose_rounds := 0
var reloading := false
var ads := false
var ads_blend := 0.0
var bloom := 0.0
var shots_fired := 0
var shots_hit := 0
var clips_pinged := 0
var hit_ids: Array[StringName] = []     # stable ids of popped cans (saved)
var targets_hit := 0
var targets_total := 0
var cache_taken := false
var debug_last := ""
var last_shot: Dictionary = {}

var held: GarandModel
var slung: GarandModel
var _reload_t := 0.0
var _reload_steps := {}
var _hand_clip: Node3D
var _cooldown := 0.0
var _aim_t := 0.0
var _auto_reload_t := -1.0
var _sway_t := 0.0
var _targets: Array = []
var _cache: Area3D
var _cache_rot := 0.0
var _flying: Array = []          # ejected clips: [node, velocity, spin, age, bounced]
var _rng := RandomNumberGenerator.new()


func setup(p_world: WorldManager, p_entities: EntityManager, p_player: Player, p_cam: ChaseCamera) -> void:
	world = p_world
	db = p_world.database
	entities = p_entities
	player = p_player
	camera = p_cam
	message.connect(func(t, d): Events.message.emit(t, d))
	fx = CombatFx.new(); fx.name = "CombatFx"; add_child(fx)
	sounds = WeaponAudio.new(); sounds.name = "WeaponAudio"; add_child(sounds)
	held = GarandModel.new()
	slung = GarandModel.new(); slung.set_sling(true)
	player.model.attach_long_gun(held, slung)
	_hand_clip = GarandModel.make_clip(true)
	_hand_clip.visible = false
	player.model.hand_l.add_child(_hand_clip)
	_hand_clip.position = Vector3(0.0, -0.10, -0.03)
	_sync_models()
	_build_cache()
	_build_targets()


## A slung Garand on another RiderModel (the courier on the bike).
func dress_rider(model: RiderModel) -> void:
	if model == null or model.torso == null: return
	var g := GarandModel.new(); g.set_sling(true); g.set_loaded(CLIP)
	model.attach_long_gun(null, g)


# ---------------------------------------------------------------------------- the cache
func _build_cache() -> void:
	var pos: Vector3 = db.location_pos(&"dunes_lookout") + Vector3(-3.5, 0.0, 2.5)
	pos.y = world.terrain.height_at(pos.x, pos.z)
	_cache = Area3D.new()
	_cache.name = "AmmoCache"
	_cache.collision_layer = 0
	_cache.collision_mask = 4
	_cache.position = pos
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new(); sh.radius = 1.3
	cs.shape = sh; cs.position = Vector3(0, 0.8, 0)
	_cache.add_child(cs)
	# an ammunition crate with a bandolier of clips on top and a soft glow so it can be found
	var crate := Mats.box(Vector3(0.9, 0.6, 0.9), Mats.solid(Color(0.40, 0.42, 0.28), 0.85), Vector3(0, 0.3, 0))
	crate.set_meta("surface", &"wood")
	_cache.add_child(crate)
	_cache.add_child(Mats.box(Vector3(0.92, 0.05, 0.3), Mats.solid(Color(0.85, 0.8, 0.6), 0.9), Vector3(0, 0.42, 0)))
	var disp := Node3D.new(); disp.name = "Display"
	disp.position = Vector3(0, 0.72, 0)
	for i in range(3):
		var c := GarandModel.make_clip(true)
		c.position = Vector3((i - 1) * 0.06, 0, 0)
		c.scale = Vector3.ONE * 1.8
		disp.add_child(c)
	_cache.add_child(disp)
	var glow_mat := StandardMaterial3D.new()
	glow_mat.albedo_color = Color(1.0, 0.85, 0.5, 0.22)
	glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var beam := Mats.cylinder(0.5, 14.0, glow_mat, Vector3(0, 7.0, 0), Vector3.ZERO, 10, 0.1)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cache.add_child(beam)
	_cache.body_entered.connect(_on_cache_body)
	entities.register(_cache, &"pickup.ammo.dunes_lookout", &"pickup")


func _on_cache_body(body: Node) -> void:
	if cache_taken or body != player: return
	_take_cache()
	var got := add_ammo(4)
	sounds.play(&"pickup")
	picked_up.emit()
	Events.gun_picked_up.emit()
	message.emit("A cache of Garand clips! +%d clips. Hold RMB to aim, LMB / F to fire, V to reload." % got, 6.0)


func _take_cache() -> void:
	cache_taken = true
	if _cache:
		_cache.queue_free()
		_cache = null


## Where the ammo cache is, or null once it has been emptied.
func pickup_position() -> Variant:
	return _cache.global_position if _cache else null


## Legacy tool hook (the pistol used to be granted): hand over the cache's clips.
func grant() -> void:
	if not cache_taken: _on_cache_body(player)


## Full clips (and loose rounds) into the pouch. Returns the clips actually taken.
func add_ammo(clips: int, rounds: int = 0) -> int:
	var before := reserve_clips
	reserve_clips = mini(MAX_RESERVE, reserve_clips + maxi(clips, 0))
	loose_rounds += maxi(rounds, 0)
	_pack_loose()
	return reserve_clips - before


func _pack_loose() -> void:
	while loose_rounds >= CLIP and reserve_clips < MAX_RESERVE:
		loose_rounds -= CLIP
		reserve_clips += 1
	loose_rounds = mini(loose_rounds, MAX_LOOSE)


# ---------------------------------------------------------------------------- tin cans
func _build_targets() -> void:
	# tin cans: one row on top of the farm's stone wall, one on the lookout bench —
	# the hubs say where those surfaces are
	var spots: Array[Vector3] = []
	var ids: Array[StringName] = []
	var farm: Hub = db.hub(&"hilltop_farm")
	for i in range(5):
		var p = farm.wall_top(farm.centre.x + 12.0 + i * 1.5)
		if p != null: spots.append(p); ids.append(StringName("can.hilltop_farm.%d" % i))
	var lookout: Hub = db.hub(&"dunes_lookout")
	for i in range(4):
		spots.append(lookout.bench_top(0.2 + i * 0.2)); ids.append(StringName("can.dunes_lookout.%d" % i))
	for si in range(spots.size()):
		var t := Area3D.new()
		t.collision_layer = TARGET_LAYER
		t.collision_mask = 0
		t.position = spots[si]
		t.set_meta("surface", &"metal")
		var can := Node3D.new()
		can.name = "Can"
		var tin := Mats.solid(Color(0.75, 0.78, 0.80), 0.35, 0.7)
		can.add_child(Mats.cylinder(0.11, 0.26, tin, Vector3(0, 0.13, 0), Vector3.ZERO, 10))
		can.add_child(Mats.box(Vector3(0.23, 0.12, 0.02), Mats.solid(Color(0.85, 0.25, 0.2), 0.7), Vector3(0, 0.13, -0.105)))
		t.add_child(can)
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new(); sh.radius = 0.16; sh.height = 0.34
		cs.shape = sh; cs.position = Vector3(0, 0.17, 0)
		t.add_child(cs)
		entities.register(t, ids[si], &"target")
		_targets.append(t)
	targets_total = _targets.size()


## Remaining tin cans (read-only view for the HUD, tests and tools).
func targets() -> Array:
	return _targets.duplicate()


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
	fx.impact(t.global_position + Vector3(0, 0.15, 0), Vector3.UP, &"metal")
	var cid: StringName = t.get_meta("entity_id", &"")
	hit_ids.append(cid)
	target_hit.emit(targets_hit, targets_total)
	Events.can_hit.emit(cid, targets_hit, targets_total)
	if targets_hit == targets_total:
		message.emit("Sharpshooter! All %d cans down." % targets_total, 5.0)
	else:
		message.emit("Ping! %d / %d cans" % [targets_hit, targets_total], 1.5)


# ---------------------------------------------------------------------------- aiming
## The Rider says whether the aim button is held (on foot) every tick.
func set_aim(on: bool) -> void:
	ads = on and not reloading


## The current shot cone, half-angle in degrees: hip or aimed, plus movement, air and bloom.
func current_spread() -> float:
	var move := clampf(player.speed() / maxf(player.walk_speed, 0.1), 0.0, 1.8)
	var s := lerpf(SPREAD_HIP, SPREAD_ADS, ads_blend)
	s += lerpf(SPREAD_MOVE_HIP, SPREAD_MOVE_ADS, ads_blend) * move
	if not player.is_on_floor() and not player.swimming: s += SPREAD_AIR
	return s + bloom


## Where the barrel points (world space).
func barrel_direction() -> Vector3:
	return -held.get_node("Muzzle").global_transform.basis.z


func muzzle_position() -> Vector3:
	return held.get_node("Muzzle").global_position


func is_recently_fired() -> bool:
	return _aim_t > 0.0


func reload_progress() -> float:
	return clampf(_reload_t / RELOAD_TIME, 0.0, 1.0) if reloading else 0.0


func can_fire(on_foot: bool) -> bool:
	return has_gun and on_foot and not player.swimming and _cooldown <= 0.0 and ammo > 0 and not reloading


# ---------------------------------------------------------------------------- firing
func try_fire(on_foot: bool) -> bool:
	if not can_fire(on_foot):
		if has_gun and on_foot and player.swimming:
			message.emit("Can't shoot while swimming.", 1.5)
		elif has_gun and on_foot and ammo <= 0 and not reloading and _cooldown <= 0.0:
			sounds.play(&"dry")
			_cooldown = 0.25
			if not try_reload(): message.emit("Out of clips — look for ammo crates at camps.", 2.5)
		elif has_gun and not on_foot:
			message.emit("Hop off (E) to use the Garand.", 2.0)
		return false
	# the rifle comes up instantly for a snap shot, so the muzzle is where the model shows it
	if player.model.gun_raise < 0.9: player.model.snap_long_gun(player.aim_pitch)
	ammo -= 1
	shots_fired += 1
	_cooldown = COOLDOWN
	_aim_t = maxf(_aim_t, 1.6)
	player.aiming = true
	var spread := current_spread()
	# hitscan: the camera ray through the crosshair (inside the spread cone) finds the aim point;
	# a second ray from the muzzle to that point so nearby cover still blocks and the tracer
	# leaves the barrel. The camera sits behind the courier, so the aim ray starts at the
	# muzzle's depth along the view (nothing between the camera and the courier can become the
	# aim point), and an aim point behind the muzzle is never used: the bullet leaves the barrel.
	var muzzle := muzzle_position()
	var shot := aim_ray(muzzle, spread)
	var hit: Dictionary = shot.hit
	var aim_point: Vector3 = shot.aim
	var space := player.get_world_3d().direct_space_state
	var q2 := PhysicsRayQueryParameters3D.create(muzzle, aim_point + (aim_point - muzzle).normalized() * 0.5, SHOT_MASK)
	q2.collide_with_areas = true
	q2.exclude = [player.get_rid()]
	var hit2 := space.intersect_ray(q2)
	var end := aim_point
	last_shot = {"spread": spread, "from": muzzle, "to": aim_point, "collider": "", "surface": &"", "damage": 0.0, "headshot": false}
	if hit2:
		end = hit2.position
		_resolve_hit(hit2, muzzle)
	debug_last = "cam_hit=%s at %s | muzzle=%s muzzle_hit=%s at %s" % [hit.collider.name if hit else "none", aim_point, muzzle, hit2.collider.name if hit2 else "none", hit2.position if hit2 else Vector3.ZERO]
	# recoil, flash, smoke, tracer, sound; the bolt cycles
	var kick := lerpf(RECOIL_HIP, RECOIL_ADS, ads_blend)
	camera.kick(kick, _rng.randf_range(-0.3, 0.3) * kick)
	player.model.recoil = 1.0
	held.cycle()
	bloom += lerpf(BLOOM_HIP, BLOOM_ADS, ads_blend)
	var mx: Transform3D = held.get_node("Muzzle").global_transform
	fx.muzzle(mx)
	fx.tracer(muzzle, end)
	sounds.play(&"garand_shot", null, -2.0, _rng.randf_range(0.97, 1.03))
	Events.shot_fired.emit(muzzle, &"player", LOUDNESS)
	Events.bullet_landed.emit(end, muzzle, &"player")
	fired.emit()
	if ammo == 0:
		_ping_clip()
		if reserve_clips > 0: _auto_reload_t = 0.45
		else: message.emit("Ping! Out of clips.", 2.0)
	_sync_models()
	return true


## What the crosshair covers (one ray a frame while the rifle is up), so the rifle converges on it.
func _view_point() -> Variant:
	var ray: Dictionary = camera.view_ray()
	var view: Vector3 = (ray.direction as Vector3).normalized()
	var from: Vector3 = ray.origin + view * maxf(0.0, (muzzle_position() - ray.origin).dot(view))
	var to: Vector3 = from + view * 200.0
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 2 | 16 | HURTBOX_LAYER)
	q.collide_with_areas = true
	q.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position if hit else to


## The shot's aim: a ray down the view (inside the spread cone) that starts level with the muzzle,
## so a man between the camera and the courier is never the target. Returns {aim, hit, dir}.
## An aim point that ends up behind the muzzle (the courier's own body in the way, cover at his
## shoulder) is replaced by a point straight down the cone from the muzzle.
func aim_ray(muzzle: Vector3, spread: float) -> Dictionary:
	var ray: Dictionary = camera.view_ray()
	var view: Vector3 = (ray.direction as Vector3).normalized()
	var depth := maxf(0.0, (muzzle - ray.origin).dot(view))
	var from: Vector3 = ray.origin + view * depth
	var dir: Vector3 = _cone(view, spread)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * RANGE, SHOT_MASK)
	q.collide_with_areas = true
	q.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	var aim: Vector3 = hit.position if hit else from + dir * RANGE
	if (aim - muzzle).dot(view) <= 0.05:
		aim = muzzle + dir * RANGE
		hit = {}
	return {"aim": aim, "hit": hit, "dir": dir}


func _cone(dir: Vector3, spread_deg: float) -> Vector3:
	var r := deg_to_rad(spread_deg) * sqrt(_rng.randf())
	var a := _rng.randf() * TAU
	var side := dir.cross(Vector3.UP)
	if side.length_squared() < 1e-4: side = dir.cross(Vector3.RIGHT)
	side = side.normalized()
	var up := side.cross(dir).normalized()
	return (dir + (side * cos(a) + up * sin(a)) * tan(r)).normalized()


func damage_at(distance: float) -> float:
	var k := clampf((distance - FALLOFF_START) / (FALLOFF_END - FALLOFF_START), 0.0, 1.0)
	return DAMAGE * lerpf(1.0, FALLOFF_MIN, k)


func _resolve_hit(hit: Dictionary, muzzle: Vector3) -> void:
	var col: Object = hit.collider
	last_shot.collider = String(col.name) if col is Node else ""
	if col is Area3D and col in _targets:
		shots_hit += 1
		_pop_target(col)
		return
	if col is Area3D and col.has_meta("hurtbox"):
		var victim: Object = col.get_meta("hurtbox")
		if is_instance_valid(victim) and victim.has_method("take_hit"):
			var head: bool = col.get_meta("zone", &"body") == &"head"
			var dmg := damage_at(muzzle.distance_to(hit.position)) * (HEADSHOT if head else 1.0)
			var killed: bool = victim.take_hit(dmg, head, hit.position, muzzle, &"player")
			shots_hit += 1
			last_shot.damage = dmg
			last_shot.headshot = head
			var vid: StringName = (victim as Node).get_meta("entity_id", &"") if victim is Node else &""
			hit_confirmed.emit(vid, head, killed)
			Events.target_damaged.emit(vid, dmg, head, killed)
			sounds.play(&"kill" if killed else &"hit", null, -6.0)
			fx.impact(hit.position, hit.normal, &"cloth")
			last_shot.surface = &"cloth"
			return
	var surface := CombatFx.surface_of(col)
	last_shot.surface = surface
	fx.impact(hit.position, hit.normal, surface)


## The 8th round is gone: the empty en-bloc clip is thrown out of the receiver with its ping.
func _ping_clip() -> void:
	clips_pinged += 1
	var c := GarandModel.make_clip(false)
	add_child(c)
	c.global_transform = held.get_node("Ejection").global_transform
	var b := held.global_transform.basis
	var vel := b.y * _rng.randf_range(3.0, 3.8) + b.x * _rng.randf_range(0.4, 0.9) + b.z * 0.5
	_flying.append([c, vel, Vector3(_rng.randf_range(-18, 18), _rng.randf_range(-8, 8), _rng.randf_range(-18, 18)), 0.0, false])
	sounds.play(&"ping", held.get_node("Ejection").global_position, 2.0)
	clip_pinged.emit()
	Events.clip_pinged.emit()


# ---------------------------------------------------------------------------- reloading
## Press a fresh clip in. A part-empty clip is ejected first (ping!) and its rounds pocketed.
func try_reload() -> bool:
	if reloading or not has_gun: return false
	if ammo >= CLIP:
		return false
	if reserve_clips <= 0:
		message.emit("No clips left.", 1.5)
		return false
	if ammo > 0 and reserve_clips >= MAX_RESERVE and loose_rounds + ammo > MAX_LOOSE:
		message.emit("Pouch full: fire this clip first.", 1.5)
		return false
	if ammo > 0:
		loose_rounds += ammo
		ammo = 0
		_ping_clip()
		_pack_loose()
	reloading = true
	ads = false
	_reload_t = 0.0
	_reload_steps = {}
	_auto_reload_t = -1.0
	_aim_t = maxf(_aim_t, RELOAD_TIME + 0.3)
	_sync_models()
	return true


func _update_reload(delta: float) -> void:
	_reload_t += delta
	var t := _reload_t
	var m := player.model
	# the left hand leaves the handguard, brings a clip over the receiver, thumbs it down,
	# then knocks the operating rod handle to let the bolt slam home, and returns
	# palm contacts in the rifle's frame (the palm faces each marker's -Z)
	var down := Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))
	var over := Transform3D(down, Vector3(0.0, 0.11, -0.37))
	var press := Transform3D(down, Vector3(0.0, 0.045, -0.37))
	var handle := Transform3D(Basis(Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0)), Vector3(0.055, 0.015, -0.47))
	if t < 0.35:
		m.left_grip_weight = smoothstep(0.0, 0.35, t)
		m.left_grip_override = over
	elif t < 0.8:
		m.left_grip_weight = 1.0
		m.left_grip_override = over.interpolate_with(press, smoothstep(0.35, 0.7, t))
	elif t < 1.25:
		m.left_grip_weight = 1.0
		m.left_grip_override = press.interpolate_with(handle, smoothstep(0.85, 1.2, t))
	else:
		m.left_grip_override = handle
		m.left_grip_weight = 1.0 - smoothstep(1.35, RELOAD_TIME - 0.1, t)
	_hand_clip.visible = t > 0.15 and t < 0.72
	if t >= 0.72 and not _reload_steps.has("in"):
		_reload_steps["in"] = true
		held.clip.visible = true
		sounds.play(&"clip_in", held.get_node("Ejection").global_position)
	if t >= 1.32 and not _reload_steps.has("bolt"):
		_reload_steps["bolt"] = true
		sounds.play(&"bolt", held.get_node("Ejection").global_position)
		player.model.recoil = 0.35
		reserve_clips -= 1
		ammo = CLIP
		_pack_loose()        # loose rounds from a part clip fill the pouch's free slot
		_sync_models()
	if t >= RELOAD_TIME:
		reloading = false
		m.left_grip_weight = 0.0
		_hand_clip.visible = false
		reloaded.emit()


## Drop a reload in progress and put the left hand back on the handguard (a load mid-reload).
func _cancel_reload() -> void:
	reloading = false
	_reload_t = 0.0
	_reload_steps = {}
	_auto_reload_t = -1.0
	if _hand_clip: _hand_clip.visible = false
	if player and player.model:
		player.model.left_grip_weight = 0.0
		player.model.left_grip_override = Transform3D.IDENTITY
	if held and held.clip: held.clip.visible = ammo > 0


func _sync_models() -> void:
	if held: held.set_loaded(ammo)
	if held and reloading and _reload_steps.has("in"): held.clip.visible = true
	if slung: slung.set_loaded(maxi(ammo, 1))


# ---------------------------------------------------------------------------- per frame
func _process(delta: float) -> void:
	if _cooldown > 0.0: _cooldown -= delta
	bloom = move_toward(bloom, 0.0, BLOOM_DECAY * delta)
	ads_blend = move_toward(ads_blend, 1.0 if ads else 0.0, delta * 6.0)
	if _aim_t > 0.0:
		_aim_t -= delta
		if _aim_t <= 0.0 and player.aiming and not ads: player.aiming = false
	if _auto_reload_t >= 0.0:
		_auto_reload_t -= delta
		if _auto_reload_t < 0.0: try_reload()
	if reloading: _update_reload(delta)
	# the pose: shouldered when aiming, at the hip for snap shots and reloads; walking sways it
	var m := player.model
	m.gun_ads = 1.0 if ads else 0.0
	m.aim_point = _view_point() if player.aiming and player.visible else null
	_sway_t += delta
	var mv := clampf(player.speed() / maxf(player.walk_speed, 0.1), 0.0, 1.8)
	var breathe := 0.004 + (1.0 - ads_blend) * 0.004
	m.sway = Vector2(sin(_sway_t * 5.8) * 0.018 * mv + sin(_sway_t * 0.9) * breathe,
		absf(sin(_sway_t * 11.6)) * 0.012 * mv + sin(_sway_t * 1.3) * breathe * 0.8)
	_update_flying(delta)
	if _cache:
		_cache_rot += delta
		var disp := _cache.get_node_or_null("Display")
		if disp:
			disp.rotation.y = _cache_rot
			disp.position.y = 0.78 + sin(_cache_rot * 2.0) * 0.05


func _update_flying(delta: float) -> void:
	for i in range(_flying.size() - 1, -1, -1):
		var e: Array = _flying[i]
		var node: Node3D = e[0]
		e[3] += delta
		if not is_instance_valid(node):
			_flying.remove_at(i); continue
		var v: Vector3 = e[1]
		v.y -= 9.8 * delta
		var p := node.global_position + v * delta
		var ground := world.terrain.height_at(p.x, p.z) + 0.01
		if p.y < ground:
			p.y = ground
			if not e[4]:
				e[4] = true
				v = Vector3(v.x * 0.35, absf(v.y) * 0.3, v.z * 0.35)
				e[2] = e[2] * 0.4
			else:
				v = Vector3.ZERO
				e[2] = Vector3.ZERO
		e[1] = v
		node.global_position = p
		node.rotate_x(e[2].x * delta); node.rotate_y(e[2].y * delta); node.rotate_z(e[2].z * delta)
		if e[3] > 6.0:
			node.queue_free()
			_flying.remove_at(i)


func set_visible_on_player(_v: bool) -> void:
	# the rifles live on the courier's model: they show and hide with him
	pass


# ---------------------------------------------------------------------------- persistence
func save_state() -> Dictionary:
	return {"version": 2, "has_gun": has_gun, "ammo": ammo, "reserve_clips": reserve_clips, "loose_rounds": loose_rounds,
		"cache_taken": cache_taken, "hit": hit_ids.duplicate()}


func load_state(d: Dictionary) -> void:
	has_gun = bool(d.get("has_gun", true))
	var legacy := int(d.get("version", 1)) < 2
	# the old pistol held 12: a legacy save keeps what fits in one clip, and the crate it
	# was found on (now the ammo cache) stays emptied if the pistol had been picked up
	ammo = clampi(int(d.get("ammo", CLIP)), 0, CLIP)
	reserve_clips = clampi(int(d.get("reserve_clips", reserve_clips)), 0, MAX_RESERVE)
	loose_rounds = clampi(int(d.get("loose_rounds", 0)), 0, MAX_LOOSE)
	var taken := bool(d.get("cache_taken", legacy and bool(d.get("has_gun", false))))
	if taken and not cache_taken: _take_cache()
	_cancel_reload()
	_sync_models()
	for cid in d.get("hit", []):
		for t in _targets.duplicate():
			if t.get_meta("entity_id", &"") == StringName(cid):
				_targets.erase(t)
				targets_hit += 1
				hit_ids.append(StringName(cid))
				t.queue_free()
	target_hit.emit(targets_hit, targets_total)
