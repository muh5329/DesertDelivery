extends SceneTree
## Articulation contract: suspension geometry must stay joined to moving axles,
## while the rider, handlebars and saddle keep their authored fit.
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures += 1
func run() -> void:
	var bike := Bike.new(); bike.apply_definition(load("res://data/vehicles/bike.tres"))
	root.add_child(bike); bike.set_physics_process(false)
	await process_frame
	var visual: Node3D = bike.visual
	check(visual._front_suspension != null and visual._rear_swingarm != null,
		"polished bike exports lower-fork and swingarm pivots")
	bike.drive.front_suspension = 0; bike.drive.rear_suspension = 0
	visual.update_visual(bike, 0)
	check(visual.front_wheel.global_position.distance_to(Vector3(0,.32,-.76)) < .001,
		"front axle retains authored rest transform")
	check(visual.rear_wheel.global_position.distance_to(Vector3(0,.32,.70)) < .001,
		"rear axle retains authored rest transform")
	var palm: Vector3 = visual.rider.hand_r.global_position
	var fork_position: Vector3 = visual.fork_pivot.global_position
	var seam_errors := 0
	for travel in [-.2, -.04, .0, .12, .2]:
		bike.drive.front_suspension = travel; bike.drive.rear_suspension = travel
		visual.update_visual(bike, 0)
		for index in 2:
			var side := -1.0 if index == 0 else 1.0
			var stanchion: Node3D = visual._stanchions[index]
			var front_end := stanchion.to_global(Vector3.UP * Vector2(.73,.24).length() * .5)
			var axle_end: Vector3 = visual.front_wheel.global_position + visual.fork_pivot.global_basis.x * side * .12
			if front_end.distance_to(axle_end) > .001: seam_errors += 1
			var shock: Node3D = visual._shocks[index]
			var rear_end := shock.to_global(Vector3.DOWN * Vector2(.55,.30).length() * .5)
			var rear_mount: Vector3 = visual.rear_wheel.global_position + Vector3(side*.21,.02,0)
			if rear_end.distance_to(rear_mount) > .001: seam_errors += 1
	check(seam_errors == 0, "fork rods and rear shocks meet axle mounts throughout full suspension travel")
	check(visual.rider.hand_r.global_position.distance_to(palm) < .001 and visual.fork_pivot.global_position.distance_to(fork_position) < .001,
		"wheel articulation preserves rider and handlebar attachment fit")
	bike.queue_free(); await process_frame
	print("BIKE SUSPENSION ART: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
