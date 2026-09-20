extends SceneTree
## Rendered controller review, run without headless:
## godot --path . --script res://tests/third_person_view.gd -- --out=/tmp/on-foot-review
var player: Player
var camera: ChaseCamera
var elapsed := 0.0
var next_capture := 0
var out := "/tmp/on-foot-review"
var jumped := false
var wall: StaticBody3D
var wall_shown := false
var captures := [[.9,"run"],[1.7,"jump"],[2.9,"land"],[4.2,"orbit"],[5.2,"camera-wall"],[6.8,"aim"]]
func _init() -> void: call_deferred("setup")
func box_at(pos: Vector3, size: Vector3, color: Color) -> StaticBody3D:
 var body := StaticBody3D.new();body.collision_layer=1
 var collider:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=size;collider.shape=shape;body.add_child(collider)
 var visual:=MeshInstance3D.new();var mesh:=BoxMesh.new();mesh.size=size;visual.mesh=mesh
 var material:=StandardMaterial3D.new();material.albedo_color=color;material.roughness=.9;visual.material_override=material
 body.add_child(visual);root.add_child(body);body.position=pos
 return body
func setup() -> void:
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--out="):out=arg.substr(6)
 DirAccess.make_dir_recursive_absolute(out)
 box_at(Vector3(0,-.5,0),Vector3(60,1,60),Color(.31,.43,.27))
 for z in range(-25,20,5):box_at(Vector3(2,.015,z),Vector3(.16,.03,1),Color(.75,.66,.42))
 var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-45,-30,0);light.shadow_enabled=true;root.add_child(light)
 var environment:=WorldEnvironment.new();var env:=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color(.58,.72,.84);env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color(.8,.85,1);env.ambient_light_energy=.6;environment.environment=env;root.add_child(environment)
 player=Player.new();root.add_child(player);player.place(Vector3(0,.08,5),Vector3.FORWARD)
 camera=ChaseCamera.new();root.add_child(camera);camera.follow(player,ChaseCamera.Framing.FOOT);player.camera=camera;camera.set_look(.20,.18)
func _process(delta: float) -> bool:
 if player==null:return false
 elapsed+=delta
 var intent:=Controls.Intent.new();intent.jump_held=true
 if elapsed<2.35:intent.move=Vector2(0,1);intent.run=true
 if player.motion==Player.Motion.RISE:jumped=true
 if elapsed>1.32 and not jumped:intent.press(Controls.JUMP)
 if elapsed>3.25 and elapsed<4.1:camera.look(Vector2(delta*.95,0))
 if elapsed>4.7 and not wall_shown:
  var pivot:=player.global_position+Vector3.UP*1.4
  var center:=pivot+(camera.global_position-pivot).normalized()*1.4
  wall=box_at(center,Vector3(4,3,.2),Color(.62,.48,.32));wall.rotation.y=camera.control_yaw();wall_shown=true
 if elapsed>5.6 and is_instance_valid(wall):wall.queue_free()
 if elapsed>6.0:camera.set_aiming(true);player.aiming=true;player.aim_pitch=camera.pitch()
 player.apply(intent)
 if next_capture<captures.size() and elapsed>=float(captures[next_capture][0]):
  root.get_texture().get_image().save_png(out+"/"+String(captures[next_capture][1])+".png")
  next_capture+=1
 if elapsed>7.1:quit()
 return false
