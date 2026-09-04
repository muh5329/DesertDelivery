extends Node
## Drives one job with the autopilot from its pickup: --test=route_probe --job=N [--from=ID]
var t := 0.0
var started := false
func _physics_process(d: float) -> void:
	var main: Game = Game.current
	if not started:
		started = true
		var job := main.cli.get_int("job", 2)
		main.gm._start_job(job)
		var j = main.gm.current_job()
		var sp := main.world.road_spawn(main.world.database.location_pos(j.from_location), main.world.database.location_pos(j.to_location))
		main.bike.place(sp.pos, sp.forward)
		main.autopilot.log_enabled = true
		print("[route] job %s: %s -> %s" % [j.id, j.from_location, j.to_location])
	t += d
	if main.gm.deliveries > 0:
		print("ROUTE PASS in %.1f s" % t); get_tree().quit(0)
	if t > main.cli.get_float("limit", 300.0):
		print("ROUTE FAIL: timeout at ", main.bike.global_position); get_tree().quit(1)
