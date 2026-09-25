extends Node
## Probe (fixplay): why a fresh outer-camp enemy's first move_and_slide is slow.

var game: Game


func _ready() -> void:
	game = Game.current
	call_deferred("_run")


func _time_move(e: Enemy) -> float:
	e.velocity = Vector3(0.5, -0.5, 0)
	var t0 := Time.get_ticks_usec()
	e.move_and_slide()
	return (Time.get_ticks_usec() - t0) / 1000.0


func _fresh(dir: EncounterDirector) -> Array:
	if dir.camps[&"camp.bandit.0"].node != null: dir.despawn_camp(&"camp.bandit.0")
	await get_tree().physics_frame
	await get_tree().physics_frame
	dir.spawn_camp(&"camp.bandit.0")
	var men: Array = dir.enemies_of(&"camp.bandit.0")
	for e in men: e.set_physics_process(false)
	await get_tree().physics_frame
	return men


func _run() -> void:
	print("[probe] engine setting %s, server %s" % [ProjectSettings.get_setting("physics/3d/physics_engine"), PhysicsServer3D.get_class()])
	var dir: EncounterDirector = game.encounters
	dir.set_process(false)
	game.bike.set_physics_process(false)
	var c: Vector3 = dir.camps[&"camp.bandit.0"].pos
	game.bike.global_position = Vector3(c.x - 150.0, game.world.terrain.height_at(c.x - 150.0, c.z) + 1.0, c.z)
	game.world.set_focus(game.bike)
	game.world.outer.refresh_collision()
	game.world.streamer.load_all_pending()
	for i in range(20): await get_tree().physics_frame
	var men: Array = await _fresh(dir)
	print("[probe] A baseline: %.1f ms" % _time_move(men[3]))
	men = await _fresh(dir)
	men[3].collision_mask = men[3].collision_mask
	print("[probe] B same mask reassigned: %.1f ms" % _time_move(men[3]))
	men = await _fresh(dir)
	men[3].collision_layer = men[3].collision_layer
	print("[probe] C same layer reassigned: %.1f ms" % _time_move(men[3]))
	men = await _fresh(dir)
	for i in range(4): await get_tree().physics_frame
	print("[probe] F after 4 more frames: %.1f ms" % _time_move(men[3]))
	men = await _fresh(dir)
	var e: Enemy = men[3]
	var cs: CollisionShape3D = null
	for ch in e.get_children(): if ch is CollisionShape3D: cs = ch
	print("[probe] shape %s disabled %s owners %s" % [cs.shape, cs.disabled, e.get_shape_owners()])
	var rid := e.get_rid()
	print("[probe] server xform %s node %s" % [PhysicsServer3D.body_get_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM).origin, e.global_position])
	print("[probe] server mask %d layer %d mode %d" % [PhysicsServer3D.body_get_collision_mask(rid), PhysicsServer3D.body_get_collision_layer(rid), PhysicsServer3D.body_get_mode(rid)])
	print("[probe] G diag: %.1f ms" % _time_move(e))
	get_tree().quit(0)
