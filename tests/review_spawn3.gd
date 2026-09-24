extends Node
## REVIEW PROBE (adversarial QA): which part of an enemy's first physics tick costs ~3 s.
## Spawns camp.bandit.0 212 m from the bike, stops the men's own physics, then times each man's
## _think and _move by hand, and the first physics frame after handing control back.
## Run: godot --headless --path . -- --test=review_spawn3

var game: Game


func _ready() -> void:
	game = Game.current
	call_deferred("_run")


func _run() -> void:
	var dir: EncounterDirector = game.encounters
	dir.ambush_enabled = false
	game.bike.set_physics_process(false)
	var c: Vector3 = dir.camps[&"camp.bandit.0"].pos
	var near := Vector3(c.x - 212.0, 0, c.z); near.y = game.world.terrain.height_at(near.x, near.z) + 1.0
	dir.set_process(false)
	game.bike.global_position = near
	game.world.set_focus(game.bike)
	game.world.outer.refresh_collision()
	game.world.streamer.load_all_pending()
	for i in range(60): await get_tree().physics_frame
	var t0 := Time.get_ticks_usec()
	dir.spawn_camp(&"camp.bandit.0")
	print("[spawn3] spawn_camp %.1f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	var men: Array = dir.enemies_of(&"camp.bandit.0")
	for e in men: e.set_physics_process(false)
	await get_tree().physics_frame
	for e: Enemy in men:
		var a := Time.get_ticks_usec()
		e._think(0.1)
		var b := Time.get_ticks_usec()
		e._move(1.0 / 120.0)
		var c2 := Time.get_ticks_usec()
		e._animate(1.0 / 120.0)
		var d := Time.get_ticks_usec()
		print("[spawn3] %s (%s, tier %d): _think %.1f ms, _move %.1f ms, _animate %.1f ms" % [e.enemy_id, e.role, e._tier, (b - a) / 1000.0, (c2 - b) / 1000.0, (d - c2) / 1000.0])
	# a second round, warm
	for e: Enemy in men:
		var a := Time.get_ticks_usec()
		e._move(1.0 / 120.0)
		print("[spawn3] %s second _move %.1f ms" % [e.enemy_id, (Time.get_ticks_usec() - a) / 1000.0])
	for e in men: e.set_physics_process(true)
	var last := Time.get_ticks_usec()
	for i in range(6):
		await get_tree().physics_frame
		var now := Time.get_ticks_usec()
		print("[spawn3] physics frame %d after: %.1f ms" % [i, (now - last) / 1000.0])
		last = now
	get_tree().quit(0)
