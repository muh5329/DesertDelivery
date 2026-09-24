class_name EncounterDirector
extends Node3D
## Where the bad guys are. Camps are data — id, kind (&"bandit" / &"pirate"), position, facing,
## size — and exist whether or not anything is built: a camp's props and men are spawned when
## the courier comes within SPAWN_RADIUS and freed beyond DESPAWN_RADIUS. Killed men stay dead
## (by stable id), cleared camps stay cleared, looted ammo crates stay looted: all saved.
##
## Sources of camps:
##   * the outer world's plan (`data/outer/plan.json` -> camps: kind, pos, facing_deg)
##   * two near the core, so a fight is a short ride from the start: a bandit camp in the
##     badlands east of the Dunes Lookout and a pirate cove in the dunes of the south-west shore
##   * road ambushes: now and then, while a package rides on an outer highway, a bandit
##     roadblock (a cart and three or four men) appears ahead; transient, not saved
##
## API (the world and tests):
##   add_camp(id, kind, pos, facing, size, layout = &"")   remove_camp(id)
##   camp(id) -> Dictionary     enemies_of(id) -> Array[Enemy]     is_cleared(id)
##   spawn_camp(id) / despawn_camp(id)   (forced, for tools and tests)
##   spawn_ambush_ahead(force) -> StringName
## What enemies ask of it (the ctx seam): courier(), courier_speed(), courier_hidden(),
## courier_in_cover(), hit_courier(), cover_points(), cover_taken(), claim_cover(),
## release_cover(), allies_alive(), fx, sounds, terrain.

signal camp_spawned(id: StringName)
signal camp_despawned(id: StringName)
signal camp_cleared(id: StringName)

const SPAWN_RADIUS := 220.0
const DESPAWN_RADIUS := 320.0
const CHECK_EVERY := 0.5
const AMBUSH_EVERY := 20.0
const AMBUSH_CHANCE := 0.12
const AMBUSH_COOLDOWN := 150.0
const AMBUSH_AHEAD := 190.0
const BOUNTY := 20
const CORE_HALF := 700.0

var world: WorldManager
var entities: EntityManager
var rider: Rider
var gun: GunSystem
var vitals: PlayerVitals
var delivery: DeliverySystem
var fx: CombatFx
var sounds: WeaponAudio
var terrain: Terrain

var camps: Dictionary = {}          # id -> record
var cleared: Dictionary = {}        # id -> true
var dead: Dictionary = {}           # camp id -> Array[int] of slot indices killed or fled
var looted: Dictionary = {}         # camp id -> true (ammo crate taken)
var stats := {"kills": 0, "headshots": 0, "fled": 0, "camps_cleared": 0, "ambushes": 0}
var ambush_enabled := true
var ambush_note := ""                # why the last ambush attempt did not happen (tools, tests)

var _claims: Dictionary = {}        # Enemy -> Vector3
var _check_t := 0.0
var _ambush_t := AMBUSH_EVERY
var _last_ambush := -9999.0
var _clock := 0.0
var _ambush_n := 0
var _rng := RandomNumberGenerator.new()


func setup(p_world: WorldManager, p_entities: EntityManager, p_rider: Rider, p_gun: GunSystem, p_vitals: PlayerVitals, p_delivery: DeliverySystem) -> void:
	world = p_world
	entities = p_entities
	rider = p_rider
	gun = p_gun
	vitals = p_vitals
	delivery = p_delivery
	fx = gun.fx
	sounds = gun.sounds
	terrain = world.terrain
	_rng.seed = 5150
	vitals.director = self
	Events.shot_fired.connect(_on_shot)
	Events.player_respawned.connect(func(_p): _lose_track())
	_load_plan_camps()
	_core_camps()
	EnemyOutfit.prewarm()          # the bandits' and pirates' bodies, built in the background


# ============================================================================== camps as data
func add_camp(id: StringName, kind: StringName, pos: Vector3, facing: Vector3, size: int, layout: StringName = &"") -> void:
	if camps.has(id): remove_camp(id)
	camps[id] = {"id": id, "kind": kind, "pos": pos, "facing": facing, "size": clampi(size, 1, 8),
		"layout": layout if layout != &"" else kind, "node": null, "enemies": [], "cover": [],
		"transient": layout == &"roadblock", "alerted": false, "seed": absi(String(id).hash())}


func remove_camp(id: StringName) -> void:
	if not camps.has(id): return
	despawn_camp(id)
	camps.erase(id)


func camp(id: StringName) -> Dictionary:
	return camps.get(id, {})


func is_cleared(id: StringName) -> bool:
	return cleared.has(id)


func is_spawned(id: StringName) -> bool:
	return camps.has(id) and camps[id].node != null


func enemies_of(id: StringName) -> Array:
	if not camps.has(id): return []
	return (camps[id].enemies as Array).filter(func(e): return is_instance_valid(e))


func all_enemies() -> Array:
	var out: Array = []
	for id in camps: out.append_array(enemies_of(id))
	return out


func _load_plan_camps() -> void:
	var outer: OuterWorld = world.outer
	if outer == null or not outer.ok: return
	for c: Dictionary in outer.plan().get("camps", []):
		var p: Array = c.pos
		var yaw := deg_to_rad(float(c.get("facing_deg", 0.0)))
		var kind := StringName(c.get("kind", "bandit"))
		var pos := Vector3(p[0], p[1], p[2])
		add_camp(StringName(c.id), kind, pos, Vector3(sin(yaw), 0, cos(yaw)), 5 if kind == &"bandit" else 4)


## Two camps near the core so the fight is a short ride from the start.
func _core_camps() -> void:
	var db := world.database
	var lookout := db.location_pos(&"dunes_lookout")
	# the open mesa top north-east of the lookout (tests/camp_site_probe.gd: no rocks or hoodoos
	# within 13 m), looking down at the lookout and the road
	var site: Variant = _settle_site(Vector3(192, 0, 53), 14.0)
	if site != null:
		var f: Vector3 = lookout - site
		add_camp(&"camp.core.badlands", &"bandit", site, Vector3(f.x, 0, f.z).normalized(), 5)
	var cove: Variant = _find_shore(Vector3(-480, 0, 400), 120.0)
	if cove != null:
		add_camp(&"camp.core.cove", &"pirate", cove.pos, cove.facing, 4)


## The flattest dry, off-road spot within `radius` of `nominal`.
func _settle_site(nominal: Vector3, radius: float) -> Variant:
	var best: Variant = null
	var best_s := INF
	var step := 6.0
	var n := int(radius / step)
	for j in range(-n, n + 1):
		for i in range(-n, n + 1):
			var x := nominal.x + i * step; var z := nominal.z + j * step
			var h := terrain.height_at(x, z)
			if h < 1.5: continue
			if terrain.road_dist_at(x, z) < 20.0: continue
			var rough := 0.0
			for o in [Vector2(10, 0), Vector2(-10, 0), Vector2(0, 10), Vector2(0, -10), Vector2(7, 7), Vector2(-7, -7)]:
				rough += absf(terrain.height_at(x + o.x, z + o.y) - h)
			# open ground: few built things (rocks, hoodoos, trees) filed near the spot
			var s := rough + Vector2(i, j).length() * step * 0.02 + _clutter(x, z, 18.0) * 2.5
			if s < best_s:
				best_s = s
				best = Vector3(x, h, z)
	return best


## How many build recipes (rocks, trees, houses...) are filed within `r` of (x, z): the world
## database knows before anything is loaded.
func _clutter(x: float, z: float, r: float) -> int:
	var db := world.database
	var n := 0
	var c0 := db.chunk_of(x - r, z - r); var c1 := db.chunk_of(x + r, z + r)
	for cz in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			for rec in db.records_in(Vector2i(cx, cz)):
				if rec.radius > 30.0: continue
				if Vector2(x, z).distance_to(rec.pos) < r + rec.radius: n += 1
	return n


## A low, gentle shore spot near `nominal`: dry land a few metres above the sea with water
## within ~30 m, far from delivery places. Facing points at the water.
func _find_shore(nominal: Vector3, radius: float) -> Variant:
	var best: Variant = null
	var best_d := INF
	var step := 10.0
	var n := int(radius / step)
	var db := world.database
	for j in range(-n, n + 1):
		for i in range(-n, n + 1):
			var x := nominal.x + i * step; var z := nominal.z + j * step
			var h := terrain.height_at(x, z)
			if h < 0.8 or h > 4.0: continue
			if terrain.road_dist_at(x, z) < 30.0: continue
			var sea := Vector3.ZERO
			var low := 0
			for k in range(8):
				var a := TAU * k / 8.0
				var o := Vector2(cos(a), sin(a)) * 30.0
				var hh := terrain.height_at(x + o.x, z + o.y)
				if hh < -0.8:
					low += 1
					sea += Vector3(o.x, 0, o.y)
			if low < 2 or low > 5: continue
			var rough := 0.0
			for o in [Vector2(8, 0), Vector2(-8, 0), Vector2(0, 8), Vector2(0, -8)]:
				rough += absf(terrain.height_at(x + o.x, z + o.y) - h)
			if rough > 4.5: continue
			var p := Vector3(x, h, z)
			var near_place := false
			for id in db.locations.keys():
				if db.location_pos(id).distance_to(p) < 110.0: near_place = true; break
			if near_place: continue
			var d := Vector2(i, j).length() * step + rough * 4.0
			if d < best_d:
				best_d = d
				best = {"pos": p, "facing": sea.normalized()}
	return best


# ============================================================================== streaming
func _process(delta: float) -> void:
	_clock += delta
	_check_t -= delta
	if _check_t <= 0.0:
		_check_t = CHECK_EVERY
		_stream()
	if ambush_enabled:
		_ambush_t -= delta
		if _ambush_t <= 0.0:
			_ambush_t = AMBUSH_EVERY
			_maybe_ambush()


func _stream() -> void:
	var c := courier()
	if c == null: return
	var p := c.global_position
	for id in camps.keys():
		var r: Dictionary = camps[id]
		var d := Vector2(p.x - r.pos.x, p.z - r.pos.z).length()
		if r.node == null and d < SPAWN_RADIUS:
			spawn_camp(id)
		elif r.node != null and d > DESPAWN_RADIUS:
			despawn_camp(id)
			if r.transient: camps.erase(id)


func spawn_camp(id: StringName) -> void:
	var r: Dictionary = camps.get(id, {})
	if r.is_empty() or r.node != null: return
	var built := CampKit.build(r.kind, r.layout, r.pos, r.facing, r.size, terrain, r.seed)
	var node := Node3D.new()
	node.name = String(id).replace(".", "_")
	add_child(node)
	node.add_child(built.node)
	r.node = node
	r.cover = built.cover
	r.enemies = []
	r.alerted = false
	if not looted.has(id):
		_ammo_crate(r, built.ammo)
	if not cleared.has(id):
		var gone: Array = dead.get(id, [])
		var slots: Array = built.slots
		for i in range(slots.size()):
			if i in gone: continue
			_spawn_enemy(r, i, slots[i])
	camp_spawned.emit(id)


func despawn_camp(id: StringName) -> void:
	var r: Dictionary = camps.get(id, {})
	if r.is_empty() or r.node == null: return
	for e in r.enemies:
		if is_instance_valid(e):
			_claims.erase(e)
			entities.unregister(e.enemy_id)
	r.node.queue_free()
	r.node = null
	r.enemies = []
	r.cover = []
	camp_despawned.emit(id)


func _short(id: StringName) -> String:
	return String(id).replace("camp.", "camp_").replace(".", "_")


func _spawn_enemy(r: Dictionary, index: int, slot: Dictionary) -> void:
	var rng := RandomNumberGenerator.new(); rng.seed = r.seed + index * 7919
	var weapon: StringName
	if slot.role == &"lookout": weapon = &"lever" if r.kind == &"bandit" else &"carbine"
	elif r.kind == &"pirate": weapon = &"carbine" if rng.randf() < 0.6 else &"revolver"
	else: weapon = &"lever" if rng.randf() < 0.7 else &"revolver"
	var e := Enemy.new()
	var eid := StringName("enemy.%s.%d" % [_short(r.id), index])
	e.setup(self, eid, r.id, r.kind, weapon, slot.role, slot.pos, slot.facing, rng.seed)
	e.set_meta("slot", index)
	r.node.add_child(e)
	e.global_position = slot.pos + Vector3(0, 0.05, 0)
	entities.register(e, eid, &"enemy")
	e.died.connect(_on_enemy_died)
	e.alerted.connect(_on_enemy_alerted)
	e.fled.connect(_on_enemy_fled)
	r.enemies.append(e)


func _ammo_crate(r: Dictionary, pos: Vector3) -> void:
	var a := _pickup(pos, 2, 0, Color(0.36, 0.40, 0.26), true)
	a.set_meta("camp", r.id)
	r.node.add_child(a)
	a.global_position = pos


# ============================================================================== pickups
func _pickup(pos: Vector3, clips: int, coins: int, tint: Color, crate: bool) -> Area3D:
	var a := Area3D.new()
	a.name = "AmmoCrate" if crate else "Loot"
	a.collision_layer = 0
	a.collision_mask = 4
	a.set_meta("clips", clips)
	a.set_meta("coins", coins)
	var cs := CollisionShape3D.new(); var sh := SphereShape3D.new(); sh.radius = 1.1
	cs.shape = sh; cs.position = Vector3(0, 0.6, 0); a.add_child(cs)
	if crate:
		var b := StaticBody3D.new(); b.collision_layer = 1; b.set_meta("surface", &"wood")
		b.add_child(Mats.box(Vector3(0.7, 0.42, 0.45), Mats.solid(tint, 0.85), Vector3(0, 0.21, 0)))
		b.add_child(Mats.box(Vector3(0.72, 0.06, 0.2), Mats.solid(Color(0.85, 0.8, 0.6), 0.9), Vector3(0, 0.3, 0)))
		var bcs := CollisionShape3D.new(); var bsh := BoxShape3D.new(); bsh.size = Vector3(0.7, 0.42, 0.45)
		bcs.shape = bsh; bcs.position = Vector3(0, 0.21, 0); b.add_child(bcs)
		a.add_child(b)
		var clip := GarandModel.make_clip(true); clip.position = Vector3(0.1, 0.48, 0); clip.scale = Vector3.ONE * 1.6; clip.rotation_degrees = Vector3(0, 30, 90)
		a.add_child(clip)
	else:
		# a dropped satchel with a glint
		a.add_child(Mats.box(Vector3(0.28, 0.14, 0.2), Mats.solid(Color(0.45, 0.32, 0.2), 0.9), Vector3(0, 0.07, 0), Vector3(0, 25, 0)))
		if clips > 0:
			var clip := GarandModel.make_clip(true); clip.position = Vector3(0.0, 0.2, 0); clip.scale = Vector3.ONE * 1.5
			a.add_child(clip)
		if coins > 0:
			a.add_child(Mats.cylinder(0.035, 0.012, Mats.solid(Color(0.9, 0.75, 0.3), 0.3, 0.9), Vector3(0.18, 0.02, 0.05), Vector3.ZERO, 12))
	var glow := OmniLight3D.new(); glow.light_color = Color(1.0, 0.85, 0.5); glow.light_energy = 0.6; glow.omni_range = 1.6
	glow.position = Vector3(0, 0.5, 0); a.add_child(glow)
	a.body_entered.connect(func(body): if body == rider.player: _collect(a))
	return a


func _collect(a: Area3D) -> void:
	if not is_instance_valid(a) or a.is_queued_for_deletion(): return
	var clips := int(a.get_meta("clips", 0))
	var coins := int(a.get_meta("coins", 0))
	var got := gun.add_ammo(clips) if clips > 0 else 0
	if coins > 0:
		delivery.coins += coins
		delivery.wallet_changed.emit(delivery.coins)
	if a.has_meta("camp"): looted[StringName(a.get_meta("camp"))] = true
	sounds.play(&"pickup", null, -4.0)
	var parts: Array[String] = []
	if clips > 0: parts.append("+%d clip%s" % [got, "" if got == 1 else "s"] if got > 0 else "pouch full")
	if coins > 0: parts.append("+%d coins" % coins)
	Events.message.emit("  ·  ".join(parts), 1.8)
	a.queue_free()


# ============================================================================== events
func _on_enemy_died(e: Enemy, headshot: bool) -> void:
	stats.kills += 1
	if headshot: stats.headshots += 1
	var r: Dictionary = camps.get(e.camp_id, {})
	_claims.erase(e)
	if not r.is_empty():
		_mark_gone(r, e)
		for other in enemies_of(r.id):
			if other != e: other.ally_down(e.global_position)
		# loot: ammo most of the time, coins half the time
		var rng := RandomNumberGenerator.new(); rng.seed = r.seed + int(e.get_meta("slot", 0)) * 31
		var clips := 1 if rng.randf() < 0.65 else 0
		var coins := rng.randi_range(3, 8) if rng.randf() < 0.5 else 0
		if clips + coins > 0 and r.node != null:
			var drop := _pickup(e.global_position, clips, coins, Color.WHITE, false)
			r.node.add_child(drop)
			drop.global_position = e.global_position + e.global_transform.basis.x * 0.6
	Events.enemy_killed.emit(e.enemy_id, e.kind, headshot)
	_check_cleared(e.camp_id)


func _on_enemy_fled(e: Enemy) -> void:
	stats.fled += 1
	var r: Dictionary = camps.get(e.camp_id, {})
	_claims.erase(e)
	if not r.is_empty(): _mark_gone(r, e)
	var cid := e.camp_id
	e.queue_free()
	Events.message.emit("A %s ran for it!" % String(e.kind), 1.6)
	_check_cleared(cid)


func _mark_gone(r: Dictionary, e: Enemy) -> void:
	if not dead.has(r.id): dead[r.id] = []
	var slot := int(e.get_meta("slot", -1))
	if slot >= 0 and not slot in dead[r.id]: dead[r.id].append(slot)


func _check_cleared(id: StringName) -> void:
	var r: Dictionary = camps.get(id, {})
	if r.is_empty() or cleared.has(id): return
	for e in enemies_of(id):
		if not e.is_dead() and not e.is_queued_for_deletion(): return
	cleared[id] = true
	stats.camps_cleared += 1
	delivery.coins += BOUNTY
	delivery.wallet_changed.emit(delivery.coins)
	camp_cleared.emit(id)
	Events.camp_cleared.emit(id)
	var what := "Roadblock cleared" if r.layout == &"roadblock" else ("Pirate cove cleared" if r.kind == &"pirate" else "Bandit camp cleared")
	Events.message.emit("%s!  +%d coins bounty" % [what, BOUNTY], 4.0)


func _on_enemy_alerted(e: Enemy) -> void:
	var r: Dictionary = camps.get(e.camp_id, {})
	if r.is_empty(): return
	for other in enemies_of(r.id):
		if other != e and other.global_position.distance_to(e.global_position) < 60.0:
			other.alert_to(e.target_pos)
	if not r.alerted:
		r.alerted = true
		Events.camp_alerted.emit(r.id)


func _on_shot(origin: Vector3, shooter: StringName, loudness: float) -> void:
	for id in camps:
		var r: Dictionary = camps[id]
		if r.node == null: continue
		if Vector2(origin.x - r.pos.x, origin.z - r.pos.z).length() > loudness + 40.0: continue
		for e in enemies_of(id): e.hear(origin, loudness, shooter)


func _lose_track() -> void:
	# he vanished (knocked out, woke by a road): nobody knows where he went
	for e in all_enemies():
		if e.state == Enemy.State.COMBAT:
			e.state = Enemy.State.SEARCH
			e._state_t = e._t
			e._investigate = e.target_pos
			e.last_seen = -999.0


## Is anyone fighting near `p`? (the courier's last safe spot must not be in a firefight)
func threat_near(p: Vector3, radius: float) -> bool:
	for id in camps:
		var r: Dictionary = camps[id]
		if r.node == null: continue
		if Vector2(p.x - r.pos.x, p.z - r.pos.z).length() > radius + 40.0: continue
		for e in enemies_of(id):
			if not e.is_dead() and e.is_alerted() and e.global_position.distance_to(p) < radius: return true
	return false


# ============================================================================== ambushes
func _maybe_ambush() -> void:
	if delivery == null or not delivery.carrying: return
	if not rider.is_riding(): return
	if _clock - _last_ambush < AMBUSH_COOLDOWN: return
	if _rng.randf() > AMBUSH_CHANCE: return
	spawn_ambush_ahead(false)


## A roadblock on the outer highway ahead of the courier. Returns its camp id, or &"".
func spawn_ambush_ahead(force: bool) -> StringName:
	var c := courier()
	if c == null: return &""
	var p := c.global_position
	if not force and absf(p.x) < CORE_HALF and absf(p.z) < CORE_HALF:
		ambush_note = "in the core"; return &""
	var outer: OuterWorld = world.outer
	if outer == null or outer.roads == null:
		ambush_note = "no outer roads"; return &""
	var best_d := 30.0 * 30.0
	var best_road: Dictionary = {}
	var best_k := -1
	for e: Dictionary in outer.roads.roads:
		if e.cls != "highway" and not (force and e.cls == "road"): continue
		var pts: PackedVector3Array = e.pts
		for k in range(0, pts.size(), 3):
			var q := pts[k]
			var dd := (q.x - p.x) * (q.x - p.x) + (q.z - p.z) * (q.z - p.z)
			if dd < best_d:
				best_d = dd; best_road = e; best_k = k
	if best_k < 0:
		ambush_note = "no highway within 30 m"; return &""
	var pts: PackedVector3Array = best_road.pts
	var k0 := clampi(best_k, 1, pts.size() - 2)
	var tangent := (pts[k0 + 1] - pts[k0 - 1]); tangent.y = 0.0
	var travel := -c.global_transform.basis.z
	if c is Vehicle: travel = (c as Vehicle).flat_forward()
	var dir := 1 if tangent.dot(travel) >= 0.0 else -1
	var spacing := maxf(pts[k0].distance_to(pts[k0 + 1]), 0.5)
	var br: PackedByteArray = best_road.bridge
	var k2 := -1
	# ~190 m ahead, nudged nearer or further to stay off bridges
	for dist in [AMBUSH_AHEAD, AMBUSH_AHEAD - 30.0, AMBUSH_AHEAD + 30.0, AMBUSH_AHEAD - 60.0]:
		var k := k0 + dir * int(dist / spacing)
		if k < 2 or k > pts.size() - 3: continue
		if k < br.size() and br[k] == 1: continue
		k2 = k
		break
	if k2 < 0:
		ambush_note = "no road ahead (k0 %d of %d, dir %d)" % [k0, pts.size(), dir]; return &""
	var at := pts[k2]
	var face := -(pts[k2 + dir] - pts[k2 - dir]); face.y = 0.0
	_ambush_n += 1
	_last_ambush = _clock
	var id := StringName("ambush.%d" % _ambush_n)
	add_camp(id, &"bandit", at, face.normalized(), 3 + (_ambush_n % 2), &"roadblock")
	stats.ambushes += 1
	Events.ambush_started.emit(id)
	Events.message.emit("Bandits ahead! A roadblock on the road.", 3.5)
	return id


# ============================================================================== the ctx seam
func courier() -> Node3D:
	return rider.courier() if rider else null


func courier_speed() -> float:
	var c := courier()
	if c is Player: return (c as Player).speed()
	if c is Vehicle: return absf((c as Vehicle).speed)
	return 0.0


func courier_hidden() -> bool:
	return vitals != null and vitals.is_down()


## Is the courier's lower body hidden from `from` (he is behind something)?
func courier_in_cover(chest: Vector3, from: Vector3) -> bool:
	var c := courier()
	if not (c is Player): return false
	var q := PhysicsRayQueryParameters3D.create(from, chest - Vector3(0, 0.75, 0), 1 | 2)
	q.exclude = [(c as Player).get_rid()]
	return not get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func hit_courier(amount: float, from: Vector3, source: StringName) -> void:
	if vitals: vitals.hit(amount, from, source)


func cover_points(id: StringName) -> Array:
	return camps[id].cover if camps.has(id) else []


func cover_taken(p: Vector3, by: Object) -> bool:
	for e in _claims:
		if e != by and is_instance_valid(e) and (_claims[e] as Vector3).distance_to(p) < 1.3: return true
	return false


func claim_cover(p: Vector3, by: Object) -> void:
	_claims[by] = p


func release_cover(by: Object) -> void:
	_claims.erase(by)


func allies_alive(id: StringName) -> int:
	var n := 0
	for e in enemies_of(id):
		if not e.is_dead() and e.state != Enemy.State.FLEE: n += 1
	return n


# ============================================================================== persistence
func save_state() -> Dictionary:
	var d := {}
	var l := {}
	for id in dead:
		if camps.has(id) and not camps[id].transient: d[String(id)] = (dead[id] as Array).duplicate()
	for id in looted:
		if camps.has(id) and not camps[id].transient: l[String(id)] = true
	var c: Array = []
	for id in cleared:
		if camps.has(id) and not camps[id].transient: c.append(String(id))
	return {"version": 1, "cleared": c, "dead": d, "looted": l, "stats": stats.duplicate()}


func load_state(d: Dictionary) -> void:
	var was_spawned: Array = []
	for id in camps.keys():
		if camps[id].transient:
			remove_camp(id)
		elif camps[id].node != null:
			was_spawned.append(id)
			despawn_camp(id)
	cleared.clear(); dead.clear(); looted.clear()
	for id in d.get("cleared", []): cleared[StringName(id)] = true
	var dd: Dictionary = d.get("dead", {})
	for id in dd:
		var arr: Array = []
		for v in dd[id]: arr.append(int(v))
		dead[StringName(id)] = arr
	for id in d.get("looted", {}): looted[StringName(id)] = true
	var st: Dictionary = d.get("stats", {})
	for k in stats: stats[k] = int(st.get(k, 0))
	for id in was_spawned: spawn_camp(id)


func load_missing_state() -> void:
	load_state({})
