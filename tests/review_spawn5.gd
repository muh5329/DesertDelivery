extends Node
## REVIEW PROBE (adversarial QA): split an Enemy's slow FULL-tier _move into its parts.
## Run: godot --headless --path . -- --test=review_spawn5

var game: Game


func _ready() -> void:
	game = Game.current
	call_deferred("_run")


func _t(label: String, f: Callable) -> void:
	var a := Time.get_ticks_usec()
	f.call()
	print("[spawn5] %s: %.1f ms" % [label, (Time.get_ticks_usec() - a) / 1000.0])


func _run() -> void:
	var dir: EncounterDirector = game.encounters
	dir.set_process(false)
	game.bike.set_physics_process(false)
	var c: Vector3 = dir.camps[&"camp.bandit.0"].pos
	game.bike.global_position = Vector3(c.x - 150.0, game.world.terrain.height_at(c.x - 150.0, c.z) + 1.0, c.z)
	game.world.set_focus(game.bike)
	game.world.outer.refresh_collision()
	game.world.streamer.load_all_pending()
	for i in range(20): await get_tree().physics_frame
	dir.spawn_camp(&"camp.bandit.0")
	var men: Array = dir.enemies_of(&"camp.bandit.0")
	for e in men: e.set_physics_process(false)
	await get_tree().physics_frame
	var e: Enemy = men[3]
	print("[spawn5] enemy at %s, mask %d, children %d" % [e.global_position, e.collision_mask, e.get_child_count()])
	_t("terrain.height_at", func(): game.world.terrain.height_at(e.global_position.x, e.global_position.z))
	_t("e._ground", func(): e._ground(e.global_position))
	e.velocity = Vector3(0.5, -0.5, 0)
	_t("e.move_and_slide (1)", func(): e.move_and_slide())
	_t("e.move_and_slide (2)", func(): e.move_and_slide())
	e.collision_mask = 1
	_t("e.move_and_slide mask 1", func(): e.move_and_slide())
	e.collision_mask = 64
	_t("e.move_and_slide mask 64", func(): e.move_and_slide())
	e.collision_mask = 1 | 2 | 4 | 64
	var model: Node3D = e.model
	e.remove_child(model)
	_t("e.move_and_slide without the model", func(): e.move_and_slide())
	e.add_child(model)
	_t("e.global_position += small", func(): e.global_position += Vector3(0.01, 0, 0))
	_t("e.model.global_transform read", func(): var _x = model.global_transform)
	get_tree().quit(0)
