extends Node
## End-to-end checks for mounting the second vehicle, packing its cargo grid through ControlIntent,
## and firing the physical winch at a collision target ahead.

var main: Game
var sc: Controls.Scripted
var phase := 0
var pt := 0.0
var fails := 0
var blocks_before := 0
var start_pos := Vector3.ZERO
var start_distance := 0.0
var rotation_before := 0
var max_height := -INF
var obstacle: StaticBody3D


func _ready() -> void:
	main = Game.current
	sc = main.use_scripted_controls()


func _check(condition: bool, label: String) -> void:
	print(("  PASS " if condition else "  FAIL ") + label)
	if not condition: fails += 1


func _next() -> void:
	phase += 1; pt = 0.0


func _physics_process(delta: float) -> void:
	pt += delta
	var truck: Truck = main.truck
	match phase:
		0:
			if pt > 0.4:
				_check(truck != null and truck.definition.id == &"vehicle.cargo_truck", "truck is a data-defined vehicle")
				_check(main.entities.has_entity(&"vehicle.truck") and truck.parked, "truck is registered and starts parked")
				_check(truck.cargo_blocks() == 8, "rear rack starts with two visible tetrominoes")
				main.rider.request_dismount()
				main.player.global_position = truck.global_position + truck.global_transform.basis.x.normalized() * 1.4
				_next()
		1:
			if pt > 0.3:
				_check(main.rider.request_mount(), "E-style interaction mounts the nearby truck")
				_check(main.rider.mode == Rider.Mode.DRIVING and main.rider.vehicle == truck and not truck.parked and main.cam.target == truck and main.gm.vehicle == truck, "rider, camera, deliveries and controls switch to truck driving")
				blocks_before = truck.cargo_blocks()
				sc.press("cargo")
				_next()
		2:
			if pt > 0.15:
				_check(truck.cargo_build_mode, "G enters cargo packing mode while stopped")
				sc.press("place_cargo")
				_next()
		3:
			if pt > 0.15:
				_check(truck.cargo_blocks() == blocks_before + 4, "Space locks a supported tetromino into the rack")
				rotation_before = truck.visual.cargo.rotation_steps
				sc.press("rotate_cargo")
				_next()
		4:
			if pt > 0.15:
				_check(truck.visual.cargo.rotation_steps != rotation_before, "Z rotates the next cargo piece")
				sc.press("cargo")
				_next()
		5:
			if pt > 0.2:
				_check(not truck.cargo_build_mode, "G secures the load and returns to driving")
				_make_anchor(truck)
				start_pos = truck.global_position
				_next()
		6:
			if pt > 0.2:
				sc.press("winch")
				_next()
		7:
			max_height = maxf(max_height, truck.global_position.y)
			if pt > 0.2 and start_distance == 0.0:
				_check(truck.winch_attached, "Q raycasts and hooks a solid obstacle ahead")
				start_distance = truck.winch_distance
			if pt > 1.8:
				var moved: float = truck.global_position.distance_to(start_pos)
				_check(moved > 1.5, "taut cable physically pulls the truck")
				_check(truck.winch_distance < start_distance or not truck.winch_attached, "winch reels the vehicle toward its anchor")
				_check(max_height > start_pos.y + 0.5, "high anchor lifts the truck up a wall face")
				truck.detach_winch()
				if obstacle: obstacle.queue_free()
				print("TRUCK TESTS: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
				get_tree().quit(0 if fails == 0 else 1)


func _make_anchor(truck) -> void:
	obstacle = StaticBody3D.new(); obstacle.name = "WinchTestAnchor"; obstacle.collision_layer = 1; obstacle.collision_mask = 0
	var collision := CollisionShape3D.new(); var shape := BoxShape3D.new(); shape.size = Vector3(3.0, 8.0, 1.2); collision.shape = shape
	obstacle.add_child(collision)
	main.add_child(obstacle)
	obstacle.global_position = truck.global_position + truck.flat_forward() * 14.0 + Vector3(0, 3.2, 0)
