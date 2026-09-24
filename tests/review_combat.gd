extends Node
## REVIEW PROBE (adversarial QA): combat edge cases the combat_tests do not cover.
##  A  a camp lookout at REDUCED tier (camp spawns at 220 m, full tier is 100 m): does he stay on his tower?
##  B  long-range sniping: can the courier clear a camp from ~190 m without taking damage?
##  C  an enemy between the camera and the courier: does a shot fired forward hit him (shooting backwards)?
##  D  quick save / load in the middle of a reload: does the left hand / hand clip reset?
##  E  manual reload with a full pouch: are loose rounds silently lost?
##  F  is the courier's health saved?
##  G  every plan camp: are the men standing on dry ground, not in the sea / floating / buried?
##  H  death while carrying a package: is the parcel kept, where does he wake?
## Run: godot --headless --path . -- --test=review_combat

var game: Game
var sc: Controls.Scripted
var dir: EncounterDirector
var gun: GunSystem
var pl: Player
var fails := 0


func _ready() -> void:
	game = Game.current
	call_deferred("_run")


func _say(s: String) -> void:
	print("[review] ", s)


func _flag(cond: bool, label: String) -> void:
	print(("  OK   " if cond else "  BUG  ") + label)
	if not cond: fails += 1


func _frames(n: int) -> void:
	for i in n: await get_tree().physics_frame


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


func _head(e: Enemy) -> Vector3:
	for a in e._hurt:
		if a.get_meta("zone", &"") == &"head": return (a as Area3D).global_position + Vector3(0, 0.05, 0)
	return e.global_position + Vector3(0, 1.6, 0)


func _run() -> void:
	sc = game.use_scripted_controls()
	dir = game.encounters; gun = game.gun; pl = game.player
	dir.ambush_enabled = false
	var rider: Rider = game.rider
	var vit: PlayerVitals = game.vitals
	rider.request_dismount()
	await _secs(0.5)
	var s: Vector3 = game.world.database.location_pos(&"salinas")
	var at := _ground(s.x + 30.0, s.z - 25.0)
	pl.place(at, Vector3(0, 0, -1))
	game.world.set_focus(pl)
	game.cam.snap_to_target()
	await _secs(0.5)

	# ------------------------------------------------------------------ A: lookout on his tower
	var f := Vector3(0, 0, -1)
	var cpos := _ground(at.x, at.z - 160.0)
	dir.add_camp(&"camp.review.tower", &"bandit", cpos, -f, 6, &"")
	dir.spawn_camp(&"camp.review.tower")
	var look: Enemy = null
	for e in dir.enemies_of(&"camp.review.tower"):
		if e.role == &"lookout": look = e
	if look == null:
		_flag(false, "A: no lookout in a size-6 bandit camp")
	else:
		var perch: float = look.home.y
		var gy: float = game.world.terrain.height_at(look.home.x, look.home.z)
		await _secs(2.0)
		_say("A: lookout tier %d, perch y %.2f (ground %.2f): after 2 s at 160 m he is at y %.2f" % [look._tier, perch, gy, look.global_position.y])
		_flag(absf(look.global_position.y - perch) < 0.5, "A: at 160 m (REDUCED tier) the lookout stays on his tower (perch %.1f, now %.1f)" % [perch, look.global_position.y])
		pl.place(_ground(at.x, at.z - 90.0), Vector3(0, 0, -1)); game.cam.snap_to_target()
		await _secs(2.0)
		_say("A: at 70 m (tier %d) lookout y %.2f" % [look._tier, look.global_position.y])
		_flag(absf(look.global_position.y - perch) < 0.5, "A: after walking closer (FULL tier) the lookout is still on his tower (now %.1f)" % look.global_position.y)
		vit.health.invulnerable = 999.0
	dir.remove_camp(&"camp.review.tower")
	pl.place(at, Vector3(0, 0, -1)); game.cam.snap_to_target()
	await _secs(0.5)

	# ------------------------------------------------------------------ B: sniping from 190 m
	vit.health.invulnerable = 0.0
	vit.health.reset()
	gun.reserve_clips = 12; gun.ammo = 8
	var bpos := _ground(at.x, at.z - 190.0)
	dir.add_camp(&"camp.review.snipe", &"bandit", bpos, Vector3(0, 0, 1), 5, &"")
	dir.spawn_camp(&"camp.review.snipe")
	var men: Array = dir.enemies_of(&"camp.review.snipe")
	sc.intent.aim = true
	await _secs(1.0)
	var min_h := 100.0
	var t := 0.0
	var fired := 0
	var enemy_shots_0 := 0
	var next_fire := 0.0
	while t < 90.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		min_h = minf(min_h, vit.health.current)
		var alive: Array = men.filter(func(e): return is_instance_valid(e) and not e.is_dead() and e.state != Enemy.State.FLEE)
		if alive.is_empty(): break
		var tgt: Enemy = alive[0]
		_aim_at(_head(tgt))
		if t > next_fire and not gun.reloading and gun.ammo > 0 and gun.ads_blend > 0.95:
			sc.press("fire"); fired += 1; next_fire = t + 0.9
	var eshots := 0
	var states := {}
	for e in men:
		if is_instance_valid(e):
			eshots += e.shots
			states[Enemy.State.keys()[e.state]] = states.get(Enemy.State.keys()[e.state], 0) + 1
	_say("B: sniping from 190 m: %.1f s, %d shots fired, courier min health %.0f, enemy shots %d, states %s, cleared %s" % [t, fired, min_h, eshots, states, dir.is_cleared(&"camp.review.snipe")])
	_flag(not (dir.is_cleared(&"camp.review.snipe") and min_h >= 99.0), "B: a camp cannot be cleared from 190 m without any risk (cleared=%s, min health %.0f, %d enemy shots)" % [dir.is_cleared(&"camp.review.snipe"), min_h, eshots])
	sc.intent.aim = false
	dir.remove_camp(&"camp.review.snipe")
	await _secs(0.3)

	# ------------------------------------------------------------------ C: enemy behind the courier
	vit.health.invulnerable = 999.0
	pl.place(at, Vector3(0, 0, -1)); game.cam.snap_to_target()
	await _secs(0.8)
	var cam_p: Vector3 = game.cam.global_position
	var mid := pl.global_position.lerp(cam_p, 0.55)
	mid = _ground(mid.x, mid.z)
	dir.add_camp(&"camp.review.behind", &"bandit", mid, Vector3(0, 0, -1), 1, &"squad")
	dir.spawn_camp(&"camp.review.behind")
	var bm: Array = dir.enemies_of(&"camp.review.behind")
	if not bm.is_empty():
		var be: Enemy = bm[0]
		be.global_position = mid
		be.set_physics_process(false)
		await _frames(2)
		_aim_at(pl.global_position + Vector3(0, 1.4, -60.0))
		await _frames(2)
		var h0: float = be.health.current
		gun.ammo = 8
		sc.press("fire")
		await _frames(3)
		_say("C: camera at %s, courier at %s, bandit at %s; shot: %s (collider %s)" % [game.cam.global_position, pl.global_position, be.global_position, gun.debug_last, gun.last_shot.collider])
		_flag(be.health.current >= h0, "C: firing forward does not hit a bandit standing BEHIND the courier (health %.0f -> %.0f)" % [h0, be.health.current])
	dir.remove_camp(&"camp.review.behind")

	# ------------------------------------------------------------------ D: save/load mid-reload
	gun.ammo = 3; gun.reserve_clips = 4
	await _frames(2)
	gun.try_reload()
	await _secs(0.45)
	var mid_vis: bool = gun._hand_clip.visible
	Saves.save_game("review_reload")
	Saves.load_game("review_reload")
	await _secs(1.5)
	_say("D: mid-reload hand clip visible %s; after load: reloading %s, hand clip visible %s, left grip weight %.2f, ammo %d" % [mid_vis, gun.reloading, gun._hand_clip.visible, pl.model.left_grip_weight, gun.ammo])
	_flag(not gun._hand_clip.visible and pl.model.left_grip_weight < 0.05, "D: loading a save made mid-reload resets the reload pose (hand clip %s, left grip %.2f)" % [gun._hand_clip.visible, pl.model.left_grip_weight])

	# ------------------------------------------------------------------ E: loose rounds with a full pouch
	await _secs(0.3)
	gun.reloading = false
	gun.reserve_clips = GunSystem.MAX_RESERVE; gun.loose_rounds = 6; gun.ammo = 5
	var before := gun.reserve_clips * 8 + gun.loose_rounds + gun.ammo
	gun.try_reload()
	await _secs(GunSystem.RELOAD_TIME + 0.3)
	var after := gun.reserve_clips * 8 + gun.loose_rounds + gun.ammo
	_say("E: rounds before manual reload %d, after %d (reserve %d, loose %d, ammo %d)" % [before, after, gun.reserve_clips, gun.loose_rounds, gun.ammo])
	_flag(after == before, "E: a manual reload with a full pouch keeps every round (%d -> %d)" % [before, after])

	# ------------------------------------------------------------------ F: health in the save
	vit.health.invulnerable = 0.0
	vit.health.reset()
	vit.hit(70.0, pl.global_position + Vector3(0, 1, -5), &"test")
	var hurt: float = vit.health.current
	Saves.save_game("review_health")
	vit.health.reset()
	Saves.load_game("review_health")
	await _frames(2)
	_say("F: health %.0f at save, %.0f after load" % [hurt, vit.health.current])
	_flag(absf(vit.health.current - hurt) < 1.0, "F: the courier's health survives save/load (%.0f -> %.0f)" % [hurt, vit.health.current])

	# ------------------------------------------------------------------ H: knocked out with a package
	vit.health.invulnerable = 0.0
	game.gm.carrying = true
	var coins0: int = game.gm.coins
	vit.hit(1000.0, pl.global_position + Vector3(0, 1, -5), &"test")
	await _secs(PlayerVitals.RESPAWN_AT + 0.5)
	_say("H: after knock-out: carrying %s, coins %d -> %d, woke at %s" % [game.gm.carrying, coins0, game.gm.coins, rider.courier().global_position])
	game.gm.carrying = false

	# ------------------------------------------------------------------ G: every plan camp
	vit.health.invulnerable = 999.0
	var ids: Array = dir.camps.keys()
	for id in ids:
		var r: Dictionary = dir.camps[id]
		if String(id).begins_with("camp.review"): continue
		var p: Vector3 = r.pos
		var stand := _ground(p.x + 60.0, p.z + 60.0)
		pl.place(stand + Vector3.UP * 0.5, Vector3(0, 0, -1))
		game.world.set_focus(pl)
		game.world.outer.refresh_collision()
		game.world.streamer.load_all_pending()
		await _secs(0.4)
		if not dir.is_spawned(id): dir.spawn_camp(id)
		await _secs(1.2)
		var bad: Array = []
		for e in dir.enemies_of(id):
			var ep: Vector3 = e.global_position
			var gy: float = game.world.terrain.height_at(ep.x, ep.z)
			var wet := gy < Terrain.SEA_LEVEL + 0.05
			var off := ep.y - gy
			if wet or (off > 0.6 and e.role != &"lookout") or off < -0.4:
				bad.append("%s %s at (%.0f, %.1f, %.0f) ground %.2f%s" % [e.enemy_id, e.role, ep.x, ep.y, ep.z, gy, " IN WATER" if wet else ""])
		var n: int = dir.enemies_of(id).size()
		_say("G: %s (%s, %s) at (%.0f, %.1f, %.0f): %d men, %d misplaced %s" % [id, r.kind, r.layout, p.x, p.y, p.z, n, bad.size(), bad])
		if not bad.is_empty(): fails += 1
		dir.despawn_camp(id)
	print("REVIEW COMBAT: %d findings" % fails)
	get_tree().quit(0)
