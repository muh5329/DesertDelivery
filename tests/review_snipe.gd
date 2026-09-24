extends Node
## REVIEW PROBE (adversarial QA): can a camp be cleared from beyond the bandits' reach?
## The courier stands --dist metres (default 180) from a 5-man bandit camp on the open salt flats,
## aims (ADS) at the nearest man's chest and fires every 0.9 s. Reports kills, the bandits' states,
## shots they fired back and the courier's lowest health.
## Run: godot --headless --path . -- --test=review_snipe [--dist=180]

var game: Game


func _ready() -> void:
	game = Game.current
	call_deferred("_run")


func _run() -> void:
	var sc := game.use_scripted_controls()
	var dir: EncounterDirector = game.encounters
	var gun: GunSystem = game.gun
	var pl: Player = game.player
	var vit: PlayerVitals = game.vitals
	dir.ambush_enabled = false
	game.rider.request_dismount()
	for i in range(30): await get_tree().physics_frame
	var s: Vector3 = game.world.database.location_pos(&"salinas")
	var at := Vector3(s.x + 30.0, 0, s.z - 25.0); at.y = game.world.terrain.height_at(at.x, at.z) + 0.08
	pl.place(at, Vector3(0, 0, -1))
	game.world.set_focus(pl)
	game.cam.snap_to_target()
	var dist := game.cli.get_float("dist", 180.0)
	var cpos := Vector3(at.x, 0, at.z - dist); cpos.y = game.world.terrain.height_at(cpos.x, cpos.z)
	dir.add_camp(&"camp.review.snipe", &"bandit", cpos, Vector3(0, 0, 1), 5, &"")
	dir.spawn_camp(&"camp.review.snipe")
	var men: Array = dir.enemies_of(&"camp.review.snipe")
	gun.reserve_clips = 12
	vit.health.reset()
	sc.intent.aim = true
	for i in range(90): await get_tree().physics_frame
	var t := 0.0
	var next := 0.0
	var min_h := 100.0
	var fired := 0
	var hits := 0
	while t < 120.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		min_h = minf(min_h, vit.health.current)
		var alive: Array = men.filter(func(e): return is_instance_valid(e) and not e.is_dead() and e.state != Enemy.State.FLEE)
		if alive.is_empty(): break
		var tgt: Enemy = alive[0]
		var aim := tgt.global_position + Vector3(0, 1.2, 0)
		var d: Vector3 = aim - game.cam.global_position
		game.cam.set_look(atan2(-d.x, -d.z), -atan2(d.y, Vector2(d.x, d.z).length()))
		if t > next and not gun.reloading and gun.ammo > 0:
			var before := gun.shots_hit
			sc.press("fire"); fired += 1; next = t + 0.9
			await get_tree().physics_frame
			if gun.shots_hit > before: hits += 1
			if fired <= 3: print("[snipe] shot %d: %s" % [fired, gun.debug_last])
	var eshots := 0
	var states := {}
	for e in men:
		if is_instance_valid(e):
			eshots += e.shots
			var k: String = Enemy.State.keys()[e.state]
			states[k] = int(states.get(k, 0)) + 1
	print("[snipe] from %.0f m: %.0f s, %d shots, %d hits, kills %d, courier min health %.0f, bandit shots %d, states %s, cleared %s" % [dist, t, fired, hits, dir.stats.kills, min_h, eshots, states, dir.is_cleared(&"camp.review.snipe")])
	get_tree().quit(0)
