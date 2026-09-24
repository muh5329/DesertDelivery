extends Node
## REVIEW PROBE (adversarial QA): single-frame costs the streaming budget does not cover.
##  - EncounterDirector.spawn_camp (props + men) for real plan camps, as it happens when the courier
##    rides within 220 m (one call, one frame)
##  - a colony charter's find_hall_site is covered by review_colony
##  - WorldStreamer: the worst single recipe (a BuildingKit group) in each town
## Run: godot --headless --path . -- --test=review_spawn

var game: Game


func _ready() -> void:
	game = Game.current
	call_deferred("_run")


func _run() -> void:
	var dir: EncounterDirector = game.encounters
	dir.ambush_enabled = false
	for id in [&"camp.bandit.0", &"camp.bandit.4", &"camp.pirate.1", &"camp.core.badlands"]:
		var r: Dictionary = dir.camps[id]
		var p: Vector3 = r.pos
		game.bike.global_position = Vector3(p.x + 150.0, game.world.terrain.height_at(p.x + 150.0, p.z) + 1.0, p.z)
		game.world.set_focus(game.bike)
		game.world.outer.refresh_collision()
		for i in range(5): await get_tree().process_frame
		if dir.is_spawned(id): dir.despawn_camp(id)
		for i in range(3): await get_tree().process_frame
		var t0 := Time.get_ticks_usec()
		dir.spawn_camp(id)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		# a second time (caches warm)
		dir.despawn_camp(id)
		for i in range(3): await get_tree().process_frame
		t0 = Time.get_ticks_usec()
		dir.spawn_camp(id)
		var ms2 := (Time.get_ticks_usec() - t0) / 1000.0
		print("[spawn] %s: spawn_camp %.0f ms (first), %.0f ms (again), %d men" % [id, ms, ms2, dir.enemies_of(id).size()])
		dir.despawn_camp(id)
	# one enemy on its own
	var e := Enemy.new()
	var t1 := Time.get_ticks_usec()
	e.setup(dir, &"enemy.review.0", &"camp.review", &"bandit", &"lever", &"guard", Vector3(0, 30, 0), Vector3.FORWARD, 123)
	add_child(e)
	print("[spawn] one Enemy (RiderModel + outfit + rifle + hurtboxes): %.0f ms" % ((Time.get_ticks_usec() - t1) / 1000.0))
	e.queue_free()
	# the streamer's worst recipe in each town
	for id in [&"puerto_alto", &"sarmada", &"valdoro", &"isola_serena", &"campo_real"]:
		var s := game.world.streamer
		s.max_recipe_usec = 0
		var p := game.world.database.location_pos(id)
		game.bike.global_position = p + Vector3.UP * 40.0
		game.world.set_focus(game.bike)
		var t2 := Time.get_ticks_usec()
		s.load_all_pending()
		print("[spawn] town %s: load_all_pending %.0f ms, worst single recipe %.1f ms %s" % [id, (Time.get_ticks_usec() - t2) / 1000.0, s.max_recipe_usec / 1000.0, s.worst_recipe_attribution])
	get_tree().quit(0)
