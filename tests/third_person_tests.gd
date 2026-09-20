extends SceneTree
## Headless physical regressions for the on-foot controller and orbit camera.
const DT := 1.0 / 60.0
var step_delta := DT
var failures := 0
var player: Player
var camera: ChaseCamera
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
 print(("PASS " if ok else "FAIL ") + label)
 if not ok: failures += 1
func solid(position: Vector3, size: Vector3, layer: int = 1) -> StaticBody3D:
 var body := StaticBody3D.new(); body.collision_layer = layer
 var shape := CollisionShape3D.new(); var box := BoxShape3D.new(); box.size = size; shape.shape = box
 body.add_child(shape); root.add_child(body); body.position = position
 return body
func step(intent: Controls.Intent, count: int = 1) -> void:
 for i in range(count):
  await physics_frame
  player.apply(intent); player._physics_process(step_delta)
func settle(position: Vector3 = Vector3(0, 10.04, 0)) -> void:
 player.place(position, Vector3.FORWARD)
 await step(Controls.Intent.new(), 12)
 camera.snap_to_target(); camera.set_look(0, .12)
func jump_height(held: bool) -> float:
 await settle()
 var start := player.position.y
 var intent := Controls.Intent.new(); intent.press(Controls.JUMP); intent.jump_held = held
 await step(intent)
 var peak := player.position.y
 for i in range(90):
  await step(intent)
  peak = maxf(peak, player.position.y)
 return peak - start
func run() -> void:
 Engine.physics_ticks_per_second = 60
 solid(Vector3(0, 9, 0), Vector3(100, 2, 100))
 player = Player.new(); root.add_child(player); player.set_physics_process(false)
 camera = ChaseCamera.new(); root.add_child(camera); camera.set_physics_process(false)
 camera.follow(player, ChaseCamera.Framing.FOOT); player.camera = camera
 await settle()
 var move := Controls.Intent.new(); move.move = Vector2(0, .5)
 await step(move, 30)
 check(absf(player.speed() - player.walk_speed * .5) < .05, "analog half-stick preserves half walking speed")
 var stop_at := player.position
 await step(Controls.Intent.new(), 12)
 check(player.speed() < .05 and player.position.distance_to(stop_at) < .18, "walking stops promptly without continued drifting")
 camera.look(Vector2(-PI/2, 0))
 var ray: Vector3 = camera.view_ray().direction
 check(ray.x < -.98, "look input updates the crosshair ray before the camera physics callback")
 move.move = Vector2(0, 1)
 await step(move)
 check(player.velocity.x < -.3 and absf(player.velocity.z) < .01, "movement responds to current orbit yaw in the same input tick")
 await step(move, 20)
 var jump := Controls.Intent.new(); jump.press(Controls.JUMP)
 await step(jump)
 var airborne_speed := player.speed()
 await step(Controls.Intent.new(), 8)
 check(absf(player.speed() - airborne_speed) < .02, "releasing movement preserves airborne horizontal momentum")
 check(player.model.leg_l.get_node("Knee").rotation.x < -.15, "airborne visual pose tucks the legs instead of retaining idle posture")
 check(not jump.pressed(Controls.JUMP), "jump input edge is consumed once")
 var high := await jump_height(true)
 var short := await jump_height(false)
 print("JUMP HEIGHT held=%.3f tap=%.3f" % [high, short])
 check(high > .9 and short < high * .65 and short > .3, "tap and held jumps produce meaningfully different controlled heights")
 await settle(Vector3(49.7,10.04,0))
 move.move=Vector2.RIGHT
 var left_floor := false
 for i in range(60):
  var was_floor := player.is_on_floor()
  await step(move)
  if was_floor and not player.is_on_floor(): left_floor=true;break
 jump=Controls.Intent.new();jump.press(Controls.JUMP)
 await step(jump)
 check(left_floor and player.velocity.y > 5, "coyote jump remains available immediately after a ledge")
 await settle()
 player.place(Vector3(0,10.18,0),Vector3.FORWARD)
 await step(Controls.Intent.new())
 jump=Controls.Intent.new();jump.press(Controls.JUMP)
 var buffered := false
 for i in range(12):
  await step(jump if i==0 else Controls.Intent.new())
  if player.velocity.y > 5:buffered=true;break
 check(buffered, "buffered jump launches on landing")
 await settle()
 var ceiling := solid(Vector3(0,12.25,0),Vector3(6,.2,6))
 await physics_frame;await physics_frame
 jump=Controls.Intent.new();jump.press(Controls.JUMP)
 var touched_ceiling := false
 for i in range(30):
  await step(jump)
  if player.is_on_ceiling(): touched_ceiling=true
 check(touched_ceiling and player.velocity.y <= 0 and not player._jump_active, "low ceiling cancels ascent without repeated jump impulses")
 ceiling.queue_free();await physics_frame
 await settle()
 # A 20-degree ramp is traversable and idle contact must not slide downhill.
 var ramp := solid(Vector3(12,10.5,0),Vector3(10,.4,10));ramp.rotation.z=deg_to_rad(20)
 await settle(Vector3(12,11.0,0))
 await step(Controls.Intent.new(),30)
 var resting := player.position
 await step(Controls.Intent.new(),30)
 check(player.is_on_floor() and player.position.distance_to(resting)<.04, "idle character stays planted on a slope")
 move.move=Vector2.RIGHT
 await step(move,35)
 print("SLOPE ",resting," -> ",player.position," floor=",player.is_on_floor())
 check(player.is_on_floor() and player.position.x>resting.x+1.0 and player.position.y>resting.y+.3, "walkable uphill slope retains floor contact and makes progress")
 Engine.physics_ticks_per_second=120;step_delta=1.0/120.0
 var high120 := await jump_height(true)
 var short120 := await jump_height(false)
 check(absf(high120-high)<.08 and absf(short120-short)<.08, "physical held and tap jump heights remain consistent at 60 and 120 Hz")
 Engine.physics_ticks_per_second=60;step_delta=DT
 await settle()
 camera.set_look(0,0);camera._orbit_update(DT)
 var wall := solid(Vector3(0,11.4,1.4),Vector3(8,4,.2),16)
 await physics_frame;await physics_frame
 camera._orbit_update(DT)
 check(camera.position.z < 1.3, "orbit retracts in the same frame when a prop wall appears")
 check(player._camera_hidden and not player.model.visible, "compressed camera cleanly hides the avatar without alpha x-ray artifacts")
 var compressed := camera.position.z
 wall.queue_free();await physics_frame;await physics_frame
 camera._orbit_update(DT)
 check(camera.position.z > compressed and camera.position.z < 2.0, "orbit recovers gently after an obstruction clears")
 var parallel_wall := solid(Vector3(.20,11.4,1.5),Vector3(.16,4,6))
 await physics_frame;await physics_frame
 camera._orbit_update(DT)
 check(camera.position.x < -.10, "orbit resolves initial sphere overlap beside a parallel wall")
 parallel_wall.queue_free();await physics_frame;await physics_frame
 camera.set_look(PI/2,.2);camera._last_look_t=-100
 player.velocity=Vector3(0,0,-3);player._speed_now=3
 var yaw := camera.control_yaw()
 camera._orbit_update(DT)
 check(is_equal_approx(camera.control_yaw(),yaw), "manual orbit does not fight walking with automatic recenter")
 camera.set_aiming(true);camera.fov=58
 for i in range(60):camera._orbit_update(DT)
 var fov60 := camera.fov
 camera.fov=58
 for i in range(120):camera._orbit_update(DT*.5)
 check(absf(camera.fov-fov60)<.0001, "aim FOV transition is consistent at 60 and 120 Hz")
 var reading := Controls.Reading.new();reading.held[&"jump"]=true
 var mapped := Controls.Intent.new();Controls.Foot.new().map(reading,mapped)
 check(mapped.jump_held, "foot scheme preserves held jump independently of press edges")
 player.place(Vector3(8,12,4),Vector3.RIGHT);camera.snap_to_target()
 check(camera.global_position.distance_to(player.global_position)<4.5 and player.velocity==Vector3.ZERO and player._jump_buffer_left==0, "teleport clears locomotion and snaps camera without a long catch-up")
 check(not player._camera_hidden and player.model.visible, "camera reset restores normal avatar visibility")
 player.queue_free();camera.queue_free();ramp.queue_free();await process_frame
 print("THIRD PERSON: %s (%d failures)" % ["PASS" if failures==0 else "FAIL",failures])
 quit(0 if failures==0 else 1)
