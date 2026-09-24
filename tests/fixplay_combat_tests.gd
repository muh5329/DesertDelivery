extends Node
## Regression checks for the combat findings of the September review (fixplay):
##   C-5  an outer camp streams in without a frame stall, and a fight inside 100 m stays smooth
##   M-1  a lookout stays on his tower at REDUCED and FULL tier
##   M-2  a shot starts at the muzzle: a bandit between the camera and the courier is not hit
##   M-7  health survives save/load; loading mid-reload resets the reload pose
##   m-1  a manual reload with a full pouch keeps every round
##   m-2  a kill from 200 m turns the camp on the shooter: they fight, answer and close in
## Run: godot --headless --path . -- --test=fixplay_combat_tests

var game: Game
var sc: Controls.Scripted
var dir: EncounterDirector
var gun: GunSystem
var pl: Player
var fails := 0
var checks := 0
var _frame_worst := 0.0
var _last_us := 0
var _measure := false


func _ready() -> void:
	game = Game.current
	call_deferred("_run")


func _check(cond: bool, label: String) -> void:
	checks += 1
	print(("  PASS " if cond else "  FAIL ") + label)
	if not cond: fails += 1


func _process(_d: float) -> void:
	var now := Time.get_ticks_usec()
	if _measure and _last_us > 0: _frame_worst = maxf(_frame_worst, (now - _last_us) / 1000.0)
	_last_us = now


func _secs(s: float) -> void:
	var t := 0.0
	while t < s:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()


func _ground(x: float, z: float) -> Vector3:
	return Vector3(x, game.world.terrain.height_at(x, z) + 0.08, z)


func _aim_at(p: Vector3) -> void:
	var d: Vector3 = p - game.cam.global_position
	game.cam.set_look(atan2(-d.x, -d.z), -atan2(d.y, Vector2(d.x, d.z).length()))


func _place(p: Vector3) -> void:
	pl.place(p, Vector3(0, 0, -1))
	game.world.set_focus(pl)
	game.entities.focus = pl
	game.world.outer.refresh_collision()
	game.world.streamer.load_all_pending()
	game.cam.snap_to_target()


func _run() -> void:
	sc = game.use_scripted_controls()
	dir = game.encounters; gun = game.gun; pl = game.player
	dir.ambush_enabled = false
	game.rider.request_dismount()
	await _secs(0.5)
	game.vitals.health.invulnerable = 9999.0
	await _outer_camp()
	await _lookout()
	await _muzzle()
	await _saves()
	await _pouch()
	await _sniper()
	print("FIXPLAY COMBAT %d checks / %d failures" % [checks, fails])
	get_tree().quit(1 if fails else 0)


# -------------------------------------------------------------------------- C-5
func _outer_camp() -> void:
	var id := &"camp.bandit.0"
	var c: Vector3 = dir.camps[id].pos
	_place(_ground(c.x - 240.0, c.z) + Vector3.UP * 0.4)
	await _secs(1.5)
	_check(not dir.is_spawned(id), "C-5: camp.bandit.0 is not built from 240 m")
	# walk into the spawn radius: the director streams it in (props, then a man a frame)
	_frame_worst = 0.0
	_measure = true
	_place(_ground(c.x - 212.0, c.z) + Vector3.UP * 0.4)
	_frame_worst = 0.0
	await _secs(2.0)
	_measure = false
	var men: Array = dir.enemies_of(id)
	print("  C-5: camp streamed in: %d men, worst frame %.1f ms" % [men.size(), _frame_worst])
	_check(dir.is_spawned(id) and men.size() >= 4, "C-5: riding up to the camp streams it in with its men (%d)" % men.size())
	_check(_frame_worst < 60.0, "C-5: no frame stall while the camp streams in (worst %.1f ms; was ~2600-3000 ms)" % _frame_worst)
	var tiers := men.map(func(e): return game.entities.tier_of(e.enemy_id))
	_check(not tiers.has(EntityManager.SimulationTier.FULL), "C-5: men spawned 212 m out start at their distance's tier, not FULL (%s)" % [tiers])
	# a fight inside 100 m: every man at FULL physics, alerted, shooting
	_place(_ground(c.x - 60.0, c.z) + Vector3.UP * 0.4)
	await _secs(1.0)
	for e in dir.enemies_of(id): e.alert_to(pl.global_position + Vector3(0, 1.2, 0))
	_frame_worst = 0.0
	_measure = true
	await _secs(4.0)
	_measure = false
	var full := dir.enemies_of(id).filter(func(e): return game.entities.tier_of(e.enemy_id) == EntityManager.SimulationTier.FULL).size()
	print("  C-5: fight at 60 m: %d men at FULL tier, worst frame %.1f ms" % [full, _frame_worst])
	_check(full >= 4 and _frame_worst < 60.0, "C-5: a fight at 60 m runs every man at FULL tier without stalls (%d men, worst %.1f ms)" % [full, _frame_worst])
	# a forced spawn (tools, tests) with the courier close by: the next physics frame is cheap
	dir.set_process(false)
	dir.despawn_camp(id)
	await _secs(0.3)
	var t0 := Time.get_ticks_usec()
	dir.spawn_camp(id)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	await get_tree().physics_frame
	var t1 := Time.get_ticks_usec()
	await get_tree().physics_frame
	var step := (Time.get_ticks_usec() - t1) / 1000.0
	print("  C-5: forced spawn_camp %.1f ms, next physics frame %.1f ms" % [ms, step])
	_check(dir.enemies_of(id).size() >= 4 and step < 60.0, "C-5: the first physics frame after a forced spawn is cheap (%.1f ms)" % step)
	dir.despawn_camp(id)
	dir.set_process(true)


# -------------------------------------------------------------------------- M-1
func _lookout() -> void:
	var s: Vector3 = game.world.database.location_pos(&"salinas")
	var at := _ground(s.x + 30.0, s.z - 25.0)
	_place(at)
	await _secs(0.5)
	dir.add_camp(&"camp.fix.tower", &"bandit", _ground(at.x, at.z - 160.0), Vector3(0, 0, 1), 6, &"")
	dir.spawn_camp(&"camp.fix.tower")
	var look: Enemy = null
	for e in dir.enemies_of(&"camp.fix.tower"):
		if e.role == &"lookout": look = e
	_check(look != null, "M-1: a size-6 bandit camp has a tower lookout")
	if look != null:
		var perch: float = look.home.y
		await _secs(2.0)
		_check(absf(look.global_position.y - perch) < 0.5, "M-1: at 160 m (REDUCED) the lookout stays on his tower (perch %.1f, now %.1f)" % [perch, look.global_position.y])
		_place(_ground(at.x, at.z - 90.0))
		await _secs(2.0)
		_check(game.entities.tier_of(look.enemy_id) == EntityManager.SimulationTier.FULL and absf(look.global_position.y - perch) < 0.5,
			"M-1: at 70 m (FULL) he is still up there (now %.1f)" % look.global_position.y)
		# ride away (the camp despawns) and come back (streamed in again, at REDUCED tier)
		_place(_ground(at.x, at.z + 250.0))
		await _secs(1.5)
		_place(_ground(at.x, at.z - 10.0))
		await _secs(3.0)
		var again: Enemy = null
		for e in dir.enemies_of(&"camp.fix.tower"):
			if e.role == &"lookout": again = e
		_check(again != null and again != look and absf(again.global_position.y - perch) < 0.5,
			"M-1: a camp streamed in again has its lookout on the tower (%s)" % (str(again.global_position.y) if again else "none"))
	dir.remove_camp(&"camp.fix.tower")
	_place(at)
	await _secs(0.5)


# -------------------------------------------------------------------------- M-2
func _muzzle() -> void:
	var s: Vector3 = game.world.database.location_pos(&"salinas")
	var at := _ground(s.x + 30.0, s.z - 25.0)
	_place(at)
	await _secs(0.8)
	var mid := pl.global_position.lerp(game.cam.global_position, 0.55)
	mid = _ground(mid.x, mid.z)
	dir.add_camp(&"camp.fix.behind", &"bandit", mid, Vector3(0, 0, -1), 1, &"squad")
	dir.spawn_camp(&"camp.fix.behind")
	var be: Enemy = dir.enemies_of(&"camp.fix.behind")[0]
	be.global_position = mid
	be.set_physics_process(false)
	await get_tree().physics_frame
	_aim_at(pl.global_position + Vector3(0, 1.4, -60.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var h0: float = be.health.current
	gun.ammo = 8
	sc.press("fire")
	await get_tree().physics_frame
	await get_tree().physics_frame
	print("  M-2: %s" % gun.debug_last)
	_check(be.health.current >= h0, "M-2: firing forward never hits a bandit behind the courier (health %.0f -> %.0f)" % [h0, be.health.current])
	var from: Vector3 = gun.last_shot.get("from", Vector3.ZERO)
	_check(from.distance_to(gun.muzzle_position()) < 0.6, "M-2: the shot starts at the muzzle")
	dir.remove_camp(&"camp.fix.behind")
	# and one in front of him is still hit
	var ahead := _ground(at.x, at.z - 14.0)
	dir.add_camp(&"camp.fix.front", &"bandit", ahead, Vector3(0, 0, 1), 1, &"squad")
	dir.spawn_camp(&"camp.fix.front")
	var fe: Enemy = dir.enemies_of(&"camp.fix.front")[0]
	fe.global_position = ahead
	fe.set_physics_process(false)
	sc.intent.aim = true
	await _secs(0.6)
	var hit := false
	for i in range(6):
		_aim_at(fe.global_position + Vector3(0, 1.2, 0))
		await get_tree().physics_frame
		var h := fe.health.current
		gun.ammo = 8
		sc.press("fire")
		await _secs(0.3)
		if fe.health.current < h or fe.is_dead(): hit = true; break
	sc.intent.aim = false
	_check(hit, "M-2: a bandit in front of the courier is still hit")
	dir.remove_camp(&"camp.fix.front")


# -------------------------------------------------------------------------- M-7
func _saves() -> void:
	var vit: PlayerVitals = game.vitals
	vit.health.invulnerable = 0.0
	vit.health.reset()
	vit.hit(70.0, pl.global_position + Vector3(0, 1, -5), &"test")
	var hurt: float = vit.health.current
	Saves.save_game("fixplay_health")
	vit.health.reset()
	Saves.load_game("fixplay_health")
	await get_tree().physics_frame
	_check(absf(vit.health.current - hurt) < 1.0, "M-7: health survives save/load (%.0f -> %.0f)" % [hurt, vit.health.current])
	vit.health.invulnerable = 9999.0
	gun.ammo = 3; gun.reserve_clips = 4
	await get_tree().physics_frame
	gun.try_reload()
	await _secs(0.45)
	var mid_vis: bool = gun._hand_clip.visible
	Saves.save_game("fixplay_reload")
	Saves.load_game("fixplay_reload")
	await _secs(0.5)
	_check(mid_vis and not gun.reloading and not gun._hand_clip.visible and pl.model.left_grip_weight < 0.05,
		"M-7: loading a save made mid-reload resets the pose (hand clip %s, left grip %.2f)" % [gun._hand_clip.visible, pl.model.left_grip_weight])


# -------------------------------------------------------------------------- m-1
func _pouch() -> void:
	gun.reloading = false
	gun.reserve_clips = GunSystem.MAX_RESERVE; gun.loose_rounds = 6; gun.ammo = 5
	var before := gun.reserve_clips * 8 + gun.loose_rounds + gun.ammo
	gun.try_reload()
	await _secs(GunSystem.RELOAD_TIME + 0.3)
	var after := gun.reserve_clips * 8 + gun.loose_rounds + gun.ammo
	_check(after == before, "m-1: a manual reload with a full pouch keeps every round (%d -> %d)" % [before, after])
	gun.reserve_clips = GunSystem.MAX_RESERVE; gun.loose_rounds = 12; gun.ammo = 6
	before = gun.reserve_clips * 8 + gun.loose_rounds + gun.ammo
	var ok := gun.try_reload()
	await _secs(GunSystem.RELOAD_TIME + 0.3)
	after = gun.reserve_clips * 8 + gun.loose_rounds + gun.ammo
	_check(not ok and after == before, "m-1: a reload that would spill rounds is refused (%d -> %d)" % [before, after])


# -------------------------------------------------------------------------- m-2
func _sniper() -> void:
	var s: Vector3 = game.world.database.location_pos(&"salinas")
	var at := _ground(s.x + 30.0, s.z - 25.0)
	_place(at)
	game.vitals.health.invulnerable = 9999.0
	await _secs(0.3)
	var camp := _ground(at.x, at.z - 200.0)
	dir.add_camp(&"camp.fix.snipe", &"bandit", camp, Vector3(0, 0, 1), 4, &"squad")
	dir.spawn_camp(&"camp.fix.snipe")
	var men: Array = dir.enemies_of(&"camp.fix.snipe")
	await _secs(0.5)
	var muzzle := pl.global_position + Vector3(0, 1.5, 0)
	var victim: Enemy = men[0]
	victim.take_hit(999.0, true, victim.global_position + Vector3(0, 1.6, 0), muzzle, &"player")
	await _secs(0.5)
	var alert := 0
	var near := 0
	var d0 := {}
	for e: Enemy in men:
		if e == victim or e.is_dead(): continue
		if e.state == Enemy.State.COMBAT: alert += 1
		if Vector2(e.target_pos.x - muzzle.x, e.target_pos.z - muzzle.z).length() < 30.0: near += 1
		d0[e] = e.global_position.distance_to(pl.global_position)
	_check(alert == men.size() - 1, "m-2: a headshot from 200 m puts the rest of the camp in a fight (%d/%d)" % [alert, men.size() - 1])
	_check(near == men.size() - 1, "m-2: they turn on the shooter's position, not the body (%d/%d within 30 m)" % [near, men.size() - 1])
	await _secs(15.0)
	var closer := 0
	var shots := 0
	for e: Enemy in men:
		if e == victim or not is_instance_valid(e) or e.is_dead(): continue
		shots += e.shots
		if d0.has(e) and e.global_position.distance_to(pl.global_position) < float(d0[e]) - 10.0: closer += 1
	print("  m-2: after 15 s: %d men closed in, %d shots fired back" % [closer, shots])
	_check(closer >= 1 or shots >= 2, "m-2: sniping is answered: men close in or fire back (%d closer, %d shots)" % [closer, shots])
	# a near miss is felt too
	dir.remove_camp(&"camp.fix.snipe")
	dir.add_camp(&"camp.fix.miss", &"bandit", camp, Vector3(0, 0, 1), 2, &"squad")
	dir.spawn_camp(&"camp.fix.miss")
	await _secs(0.3)
	var m: Enemy = dir.enemies_of(&"camp.fix.miss")[0]
	Events.bullet_landed.emit(m.global_position + Vector3(1.5, 0.3, 0), muzzle, &"player")
	await _secs(0.3)
	_check(m.state == Enemy.State.COMBAT, "m-2: a round cracking past a man 200 m out puts him in a fight")
	dir.remove_camp(&"camp.fix.miss")
