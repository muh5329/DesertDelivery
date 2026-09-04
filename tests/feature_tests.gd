extends Node
## Headless feature checks driven through the ControlIntent seam and the Rider interface —
## the same paths a player's keys take: dismount/walk/mount, swimming, pistol, plane.
## Run: godot --headless --path . -- --test=feature_tests

var main
var sc: Controls.Scripted
var phase := 0
var pt := 0.0
var fails := 0
var mark := Vector3.ZERO
var mark_yaw := 0.0
var landed := false
var max_alt := 0.0
var took_off := false
var modes_seen: Array = []


func _ready() -> void:
	main = Game.current


func _check(cond: bool, label: String) -> void:
	print(("  PASS " if cond else "  FAIL ") + label)
	if not cond: fails += 1


func _next() -> void:
	phase += 1
	pt = 0.0


func _aim_at(target: Vector3) -> void:
	var d: Vector3 = target - main.cam.global_position
	main.cam.set_look(atan2(-d.x, -d.z), -atan2(d.y, Vector2(d.x, d.z).length()))


func _physics_process(delta: float) -> void:
	pt += delta
	var bike = main.bike
	var pl = main.player
	var rider = main.rider
	if bike == null or pl == null: return
	if sc == null:
		sc = main.use_scripted_controls()
		rider.mode_changed.connect(func(f, t): modes_seen.append([f, t]))
	match phase:
		0:  # dismount at standstill through the interface
			if pt > 0.5:
				var ok: bool = rider.request_dismount()
				_check(ok and rider.mode == Rider.Mode.ON_FOOT and pl.visible and bike.parked, "dismount at standstill")
				_check(modes_seen.size() == 1 and modes_seen[0][1] == Rider.Mode.ON_FOOT, "mode_changed fired once (RIDING -> ON_FOOT)")
				mark = pl.global_position
				sc.intent.move = Vector2(0, 1); sc.intent.run = true
				_next()
		1:  # run for 2.5 s
			if pt > 2.5:
				var d: float = pl.global_position.distance_to(mark)
				print("[test] ran %.1f m in 2.5 s (y=%.2f)" % [d, pl.global_position.y])
				_check(d > 8.0 and d < 22.0, "runs a sensible distance")
				_check(pl.global_position.y > bike.global_position.y - 2.0, "stays on the ground")
				sc.intent.move = Vector2.ZERO; sc.intent.run = false
				_check(not rider.request_mount(), "cannot mount from far away")
				var side: Vector3 = bike.global_transform.basis.x
				pl.global_position = bike.global_position + side * 1.0
				_next()
		2:
			if pt > 0.3:
				_check(rider.request_mount() and rider.mode == Rider.Mode.RIDING and not bike.parked, "mount again next to the bike")
				_check(not rider.request_mount(), "mount is refused while already riding")
				# --- swimming: hop off and go into the water
				rider.request_dismount()
				var tr = main.level.terrain
				pl.global_position = Vector3(150, 0.3, 203)   # the lake in the badlands (the north shore is 20 m away)
				print("[test] seabed at the lake = %.2f" % tr.height_at(150, 203))
				_next()
		3:
			if pt > 1.5:
				print("[test] mode=%s y=%.2f" % [rider.mode, pl.global_position.y])
				_check(rider.mode == Rider.Mode.SWIMMING and pl.swimming, "enters swim state in deep water")
				_check(pl.global_position.y > -1.2 and pl.global_position.y < 0.2, "floats near the surface")
				_check(not rider.request_mount(), "cannot mount while swimming")
				mark = pl.global_position
				main.cam.set_look(0.0, 0.0)   # face north, toward the lake shore
				sc.intent.move = Vector2(0, 1)
				_next()
		4:
			if pt > 18.0:
				var d: float = mark.distance_to(pl.global_position)
				print("[test] swam %.1f m, mode=%s, x=%.1f y=%.2f" % [d, rider.mode, pl.global_position.x, pl.global_position.y])
				_check(d > 15.0, "swims forward")
				_check(rider.mode == Rider.Mode.ON_FOOT and pl.global_position.y > 0.3, "climbs out on the beach")
				sc.intent.move = Vector2.ZERO
				# --- pistol pickup
				var pk = main.gun.pickup_position()
				pl.global_position = pk + Vector3(0, 0.1, 0)
				_next()
		5:
			if pt > 0.6:
				_check(main.gun.has_gun and main.gun.pickup_position() == null, "pistol picked up by walking over it")
				# stand 7 m in front of a can
				var t: Area3D = main.gun.targets()[0]
				var stand: Vector3 = t.global_position + Vector3(0, 0, 7.0)
				stand.y = main.level.terrain.height_at(stand.x, stand.z) + 0.1
				pl.place(stand, Vector3(0, 0, -1))
				main.cam.snap_to_target()
				_next()
		6:
			if pt < 0.01: mark.x = -1.0
			if pt > 0.8 and pt < 2.0:
				# hold aim and steer the crosshair onto the can each tick until it settles
				sc.intent.aim = true
				_aim_at(main.gun.targets()[0].global_position + Vector3(0, 0.13, 0))   # the can sits on its target origin
			if pt > 2.0 and mark.x < 0.0:
				mark.x = main.gun.targets_hit
				sc.press("fire")
			if pt > 2.3 and pt < 2.31:
				print("[test] ", main.gun.debug_last)
				_check(main.gun.targets_hit == int(mark.x) + 1, "pressing fire pops the aimed tin can")
				_check(main.gun.ammo == main.gun.max_ammo - 1, "ammo decrements")
				sc.press("fire")   # two presses 0.1 s apart: only the first can fire (0.22 s cooldown)
			if pt > 2.4 and pt < 2.41:
				sc.press("fire")
			if pt > 2.5:
				_check(main.gun.ammo == main.gun.max_ammo - 2, "rate of fire is limited")
				_next()
		7:
			if pt > 0.1:
				var ray: Dictionary = main.cam.view_ray()
				var dot: float = main.gun.barrel_direction().dot(ray.direction)
				print("[test] barrel·view = %.2f" % dot)
				_check(dot > 0.7, "pistol barrel points along the view ray")
				sc.intent.aim = false
				# --- plane mode
				var side: Vector3 = bike.global_transform.basis.x
				pl.global_position = bike.global_position + side * 1.0
				rider.request_mount()
				_check(rider.mode == Rider.Mode.RIDING, "back on the bike")
				rider.request_wings()
				_check(bike.wings_out, "wings deploy")
				bike.took_off.connect(func(): took_off = true)
				bike.landed_plane.connect(func(): landed = true)
				sc.intent.throttle = 1.0; sc.intent.pitch = 1.0; sc.intent.steer = 0.0
				_next()
		8:  # take off and climb, then bank right and check the turn direction
			max_alt = maxf(max_alt, bike.altitude)
			if pt > 3.0 and sc.intent.steer == 0.0:
				sc.intent.steer = 0.5
				mark_yaw = bike.heading()
			if pt > 9.0:
				var dyaw: float = wrapf(bike.heading() - mark_yaw, -PI, PI)
				print("[test] mode=%s speed=%.1f alt=%.1f max_alt=%.1f dyaw=%.2f roll=%.2f" % [rider.mode, bike.speed, bike.altitude, max_alt, dyaw, bike.flight_roll])
				_check(took_off and bike.airborne and rider.mode == Rider.Mode.FLYING, "takes off with speed + pull-up; rider is FLYING")
				_check(max_alt > 6.0 and max_alt < 125.0, "gains altitude but respects the ceiling")
				_check(dyaw < -0.3, "banking right turns right (yaw decreases)")
				_check(bike.flight_roll < 0.0, "right wing dips when steering right")
				_check(not rider.request_dismount(), "cannot hop off mid-air")
				sc.intent.pitch = -0.35; sc.intent.throttle = 0.25
				_next()
		9:  # glide down and land
			if landed or pt > 30.0:
				print("[test] landed=%s after %.1f s, alt=%.1f speed=%.1f resets=%d" % [landed, pt, bike.altitude, bike.speed, bike.sea_resets])
				_check(landed and not bike.airborne and rider.mode == Rider.Mode.RIDING, "lands again; rider is RIDING")
				rider.request_wings()
				_check(not bike.wings_out, "wings fold after landing")
				_next()
		10:
			print("FEATURE TESTS: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
			get_tree().quit(0 if fails == 0 else 1)
			return
	return
