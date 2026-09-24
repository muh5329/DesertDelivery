extends Node
## REVIEW PROBE (adversarial QA): where the ~3 s frame near a camp comes from.
## The bike is parked 240 m from camp.bandit.0 (streamer and collision settled), then moved to 212 m so
## the EncounterDirector spawns the camp on its own schedule. Each of the next 40 frames is timed,
## split into process and physics time, with the camp's state.
## Run: godot --headless --path . -- --test=review_spawn2

var game: Game
var _last := 0
var frames := -1
var log: Array = []


func _ready() -> void:
	game = Game.current
	call_deferred("_run")


func _run() -> void:
	var dir: EncounterDirector = game.encounters
	dir.ambush_enabled = false
	game.bike.set_physics_process(false)
	var c: Vector3 = dir.camps[&"camp.bandit.0"].pos
	var away := Vector3(c.x - 240.0, 0, c.z); away.y = game.world.terrain.height_at(away.x, away.z) + 1.0
	game.bike.global_position = away
	game.world.set_focus(game.bike)
	game.world.outer.refresh_collision()
	game.world.streamer.load_all_pending()
	for i in range(120): await get_tree().process_frame
	print("[spawn2] spawned before move: ", dir.is_spawned(&"camp.bandit.0"))
	var near := Vector3(c.x - 212.0, 0, c.z); near.y = game.world.terrain.height_at(near.x, near.z) + 1.0
	game.bike.global_position = near
	_last = Time.get_ticks_usec()
	frames = 0


func _process(_d: float) -> void:
	if frames < 0: return
	var now := Time.get_ticks_usec()
	var ms := (now - _last) / 1000.0
	_last = now
	print("[spawn2] frame %d: %.1f ms (process %.1f ms, physics %.1f ms) spawned %s, enemies %d" % [frames, ms,
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		game.encounters.is_spawned(&"camp.bandit.0"), game.encounters.enemies_of(&"camp.bandit.0").size()])
	frames += 1
	if frames > 40: get_tree().quit(0)
