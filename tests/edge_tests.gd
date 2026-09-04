extends Node
## Headless edge-case checks through the ControlIntent seam:
##   1. Braking to a stop must not roll into reverse; a fresh brake press reverses.
##   2. The camera stays behind the bike while reversing.
##   3. Driving into the sea auto-resets the bike onto a road, facing inland.
## Run: godot --headless --path . -- --test=edge_tests

var main
var sc: Controls.Scripted
var t := 0.0
var phase := 0
var phase_t := 0.0
var fails := 0
var min_speed_after_stop := 0.0
var stop_t := -1.0


func _ready() -> void:
	main = Game.current


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  PASS ", label)
	else:
		print("  FAIL ", label)
		fails += 1


func _physics_process(delta: float) -> void:
	t += delta
	phase_t += delta
	var bike = main.bike
	if bike == null: return
	if sc == null:
		sc = main.use_scripted_controls()
	match phase:
		0:  # accelerate for 3 s
			sc.intent.throttle = 1.0; sc.intent.brake = 0.0
			if phase_t > 3.0:
				print("[test] speed after 3 s throttle: %.1f m/s" % bike.speed)
				_check(bike.speed > 9.0, "bike accelerates")
				phase = 1; phase_t = 0.0
		1:  # hold brake to a stop: must NOT roll into reverse; release + re-press: reverse engages
			sc.intent.throttle = 0.0
			sc.intent.brake = 1.0 if (phase_t < 2.5 or phase_t > 2.8) else 0.0   # brief release at 2.5-2.8 s
			if stop_t < 0.0 and bike.speed <= 0.05:
				stop_t = phase_t
			if stop_t >= 0.0 and phase_t < 2.5:
				min_speed_after_stop = minf(min_speed_after_stop, bike.speed)
			if phase_t > 4.0:
				print("[test] min speed while holding the brake after stopping: %.2f, speed after re-press: %.2f" % [min_speed_after_stop, bike.speed])
				_check(min_speed_after_stop > -0.05, "holding the brake to a stop never rolls into reverse")
				_check(bike.speed < -1.0, "reverse engages after releasing and re-pressing the brake")
				_check(bike.global_position.distance_to(main.cam.global_position) < 8.0 and main.cam.global_transform.basis.z.dot(bike.flat_forward()) < 0.0, "camera stays behind the bike while reversing")
				phase = 2; phase_t = 0.0
				# teleport to the beach facing the sea
				var tr: Terrain = main.level.terrain
				bike.place_on_road(Vector3(-40, tr.height_at(-40, 500), 500), Vector3(0, 0, 1))   # the bodega's fields, facing the lagoon
		2:  # drive into the sea
			sc.intent.throttle = 1.0; sc.intent.brake = 0.0
			if phase_t > 8.0:
				print("[test] sea resets: %d, bike y now: %.2f" % [bike.sea_resets, bike.global_position.y])
				_check(bike.sea_resets > 0, "bike auto-resets after falling into the sea")
				_check(bike.global_position.y > 0.5, "bike is back on land")
				phase = 3
	if phase == 3:
		print("EDGE TESTS: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
		get_tree().quit(0 if fails == 0 else 1)
		return
	return
