extends SceneTree
## Source mechanics port: costs, exhaustion latch, directional roll and orbit.
var player: Player
var camera: ChaseCamera
var dt := 1.0 / 60.0
var failures := 0
var checks := 0
func _init(): call_deferred('run')
func check(ok: bool, label: String):
 checks += 1
 print(('PASS ' if ok else 'FAIL ') + label)
 if not ok: failures += 1
func tick(intent: Controls.Intent, count := 1):
 for i in range(count):
  await physics_frame
  player.apply(intent); player._physics_process(dt)
func settle():
 player.place(Vector3(0,10.04,0),Vector3.FORWARD)
 player.stamina = 100; player.regen_delay = 0; player.sprint_exhausted = false
 await tick(Controls.Intent.new(),12)
func run():
 Engine.physics_ticks_per_second = 60
 var floor := StaticBody3D.new(); var shape := CollisionShape3D.new(); var box := BoxShape3D.new()
 box.size = Vector3(200,2,200); shape.shape=box; floor.add_child(shape); root.add_child(floor); floor.position.y=9
 player=Player.new();root.add_child(player);player.set_physics_process(false)
 camera=ChaseCamera.new();root.add_child(camera);camera.set_physics_process(false)
 camera.follow(player,ChaseCamera.Framing.FOOT);player.camera=camera
 await settle()
 var sprint:=Controls.Intent.new();sprint.move=Vector2(0,1);sprint.run=true
 await tick(sprint,60)
 check(absf(player.speed()-8.5)<.01 and absf(player.stamina-82)<.05,'source sprint8.5 drains18 stamina per second')
 player.stamina=.1
 await tick(sprint,2)
 check(player.sprint_exhausted and player.stamina==0,'exhaustion latches at zero')
 await tick(sprint,110)
 check(player.stamina>20 and player.sprint_exhausted and player.speed()<4.61,'held sprint does not bypass exhaustion after regeneration')
 await tick(Controls.Intent.new())
 await tick(sprint,30)
 check(not player.sprint_exhausted and player.speed()>8.4,'release above20 rearms sprint')
 await settle()
 var dodge:=Controls.Intent.new();dodge.move=Vector2.RIGHT;dodge.press(Controls.DODGE)
 var before:=player.position
 await tick(dodge)
 check(player.motion==Player.Motion.DODGE and absf(player.stamina-73)<.01 and player.rolls==1,'ground dodge charges27 once and enters dodge state')
 check(not dodge.pressed(Controls.DODGE),'dodge edge consumed once')
 dodge.move=Vector2.LEFT
 var remaining:=28
 await tick(dodge,remaining)
 check(absf(player.position.x-before.x-5.76)<.03 and absf(player.position.z-before.z)<.01,'12m/s locked-direction .48s roll integrates5.76m despite reversed input')
 await tick(Controls.Intent.new())
 check(player.dodge_remaining==0 and absf(player.model.root.rotation.x)<.01,'roll ends without an extra reverse visual rotation')
 await settle()
 player.stamina=26
 dodge=Controls.Intent.new();dodge.press(Controls.DODGE)
 await tick(dodge)
 check(player.dodge_remaining==0 and player.stamina>=26,'insufficient stamina rejects dodge')
 player.stamina=11
 var jump:=Controls.Intent.new();jump.press(Controls.JUMP)
 await tick(jump)
 check(not player._jump_active,'insufficient stamina rejects jump')
 player.stamina=100
 await tick(jump)
 check(player._jump_active and absf(player.stamina-88)<.01,'buffered affordable jump spends12 once')
 dodge=Controls.Intent.new();dodge.press(Controls.DODGE)
 await tick(dodge)
 check(player.dodge_remaining==0,'airborne dodge rejected')
 var saved:=player.stamina
 player.place(Vector3(0,10.04,0),Vector3.FORWARD)
 check(player.dodge_remaining==0 and player.stamina==saved,'teleport/mount placement cancels roll without stamina refill exploit')
 await settle()
 player.speed_multiplier=.5;player.surface_speed_multiplier=.8
 var walk:=Controls.Intent.new();walk.move=Vector2(0,1)
 await tick(walk,30)
 check(absf(player.speed()-4.6*.5*.8)<.01,'source carried-load and surface multipliers combine')
 player.speed_multiplier=1;player.surface_speed_multiplier=1
 camera.snap_to_target();camera._orbit_update(1)
 check(absf(camera.orbit_distance-6.2)<.01 and absf(camera.fov-64)<.01,'source6.2m/64degree orbit framing')
 camera.zoom(-100);check(camera.orbit_distance==3,'zoom clamps near3m')
 camera.zoom(100);check(camera.orbit_distance==9,'zoom clamps far9m')
 camera.follow(player,ChaseCamera.Framing.PLANE);camera.zoom(-4)
 check(camera.orbit_distance==9 and camera.far>=28000,'flight framing and 5000m visibility remain independent of foot zoom')
 var reading:=Controls.Reading.new();reading.pressed[&'dodge']=true
 var mapped:=Controls.Intent.new();Controls.Foot.new().map(reading,mapped)
 check(mapped.pressed(Controls.DODGE),'foot scheme maps source dodge command')
 Engine.physics_ticks_per_second=120;dt=1.0/120.0
 await settle()
 dodge=Controls.Intent.new();dodge.move=Vector2.RIGHT;dodge.press(Controls.DODGE)
 before=player.position
 await tick(dodge,58)
 check(absf(player.position.x-before.x-5.76)<.03,'120Hz roll matches60Hz authored5.76m distance')
 await settle()
 var wall:=StaticBody3D.new();var wall_shape:=CollisionShape3D.new();var wall_box:=BoxShape3D.new()
 wall_box.size=Vector3(1,5,10);wall_shape.shape=wall_box;wall.add_child(wall_shape);root.add_child(wall);wall.position=Vector3(2,12,0)
 await physics_frame
 dodge=Controls.Intent.new();dodge.move=Vector2.RIGHT;dodge.press(Controls.DODGE)
 await tick(dodge,58)
 check(player.position.x<1.3 and player.position.x>.5,'dodge uses capsule collision and cannot tunnel through a wall')
 await settle()
 dodge=Controls.Intent.new();dodge.move=Vector2.RIGHT;dodge.press(Controls.DODGE)
 await tick(dodge,4)
 var stamina_before_hold:=player.stamina
 player._jump_buffer_left=.14
 player._jump_active=true;player.velocity.y=player.jump_speed
 player.hold_controls()
 check(player.dodge_remaining==0 and player._jump_buffer_left==0 and player._intent.commands.is_empty() and player.velocity.x==0 and player.velocity.z==0,'modal hold cancels roll, buffered jump and movement intent')
 check(player.stamina==stamina_before_hold and absf(player.model.root.rotation.x)<.001 and player.model.root.position.is_equal_approx(Vector3.UP*RiderModel.HIP_H),'modal hold restores neutral roll pose without stamina refill')
 check(not player._jump_active and player.velocity.y==0,'grounded modal hold also cancels a landing-buffered launch')
 await settle()
 dodge=Controls.Intent.new();dodge.move=Vector2.RIGHT;dodge.press(Controls.DODGE)
 await tick(dodge,4)
 stamina_before_hold=player.stamina
 # Rider hides/disables this actor while the separate seated model is shown;
 # dismount calls place before enabling it again.
 player.visible=false;player.process_mode=Node.PROCESS_MODE_DISABLED
 player.place(Vector3(0,10.04,0),Vector3.FORWARD)
 player.visible=true;player.process_mode=Node.PROCESS_MODE_INHERIT
 check(player.stamina==stamina_before_hold and player.dodge_remaining==0 and player.model.root.rotation.is_equal_approx(Vector3.ZERO) and player.model.root.position.is_equal_approx(Vector3.UP*RiderModel.HIP_H),'hidden mounted actor placement restores neutral dismount pose and preserves stamina')
 print('CONTROLLER PORT: ',checks,' checks, ',failures,' failures')
 quit(1 if failures else 0)
