extends Node
## REVIEW PROBE (adversarial QA): what makes a capsule's move_and_slide cost ~0.5 s in the outer world.
## A bare CharacterBody3D capsule (the Enemy's shape) at camp.bandit.0 and at the core salt flats;
## move_and_slide timed per collision layer, and the colliders the capsule overlaps.
## Run: godot --headless --path . -- --test=review_spawn4

var game: Game


func _ready() -> void:
	game = Game.current
	call_deferred("_run")


func _probe(label: String, at: Vector3) -> void:
	game.bike.global_position = at + Vector3(-150, 0, 0)
	game.world.set_focus(game.bike)
	game.world.outer.refresh_collision()
	game.world.streamer.load_all_pending()
	for i in range(10): await get_tree().physics_frame
	var body := CharacterBody3D.new()
	var cs := CollisionShape3D.new(); var sh := CapsuleShape3D.new(); sh.radius = 0.28; sh.height = 1.75
	cs.shape = sh; cs.position = Vector3(0, 0.875, 0); body.add_child(cs)
	add_child(body)
	body.global_position = Vector3(at.x, game.world.terrain.height_at(at.x, at.z) + 0.05, at.z)
	await get_tree().physics_frame
	for mask in [1, 2, 4, 64, 1 | 2 | 4 | 64]:
		body.collision_mask = mask
		body.velocity = Vector3(1.0, -0.5, 0.0)
		var t0 := Time.get_ticks_usec()
		body.move_and_slide()
		print("[spawn4] %s: move_and_slide with mask %d: %.1f ms" % [label, mask, (Time.get_ticks_usec() - t0) / 1000.0])
	var q := PhysicsShapeQueryParameters3D.new()
	var big := SphereShape3D.new(); big.radius = 3.0
	q.shape = big; q.transform = Transform3D(Basis(), body.global_position + Vector3(0, 1, 0)); q.collision_mask = 0xFFFFFFFF
	var hits := get_viewport().get_world_3d().direct_space_state.intersect_shape(q, 64)
	var names: Array = []
	for h in hits:
		var n: Node = h.collider
		var shp: Shape3D = null
		if n is CollisionObject3D:
			var owners := (n as CollisionObject3D).get_shape_owners()
			if not owners.is_empty(): shp = (n as CollisionObject3D).shape_owner_get_shape(owners[0], 0)
		names.append("%s/%s (%s, layer %d)" % [n.get_parent().name if n.get_parent() else "", n.name, shp.get_class() if shp else "?", (n as CollisionObject3D).collision_layer if n is CollisionObject3D else -1])
	print("[spawn4] %s: within 3 m: %s" % [label, names])
	body.queue_free()


func _run() -> void:
	var dir: EncounterDirector = game.encounters
	dir.set_process(false)
	await _probe("camp.bandit.0", dir.camps[&"camp.bandit.0"].pos)
	var s: Vector3 = game.world.database.location_pos(&"salinas")
	await _probe("core salinas", Vector3(s.x + 30.0, 0, s.z - 25.0))
	await _probe("open outer (3000, -2000)", Vector3(3000, 0, -2000))
	get_tree().quit(0)
