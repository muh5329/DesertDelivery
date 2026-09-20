extends SceneTree
## Runtime character reference captures: front, profile, back, three-quarter, portrait.
## xvfb-run godot --path . --rendering-driver opengl3 -s tests/bike_view.gd -- --out=/tmp/character  (standalone: no game needed)

var out := "/tmp/character"
var pose := "idle"
var frame := 0
var idx := 0
var cams := []
var cam: Camera3D
var vis_ref


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
		if a.begins_with("--pose="): pose = a.substr(7)
	DirAccess.make_dir_recursive_absolute(out)
	var root := Node3D.new()
	get_root().add_child(root)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.82, 0.82, 0.84)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.75, 0.85)
	env.ambient_light_energy = 0.35
	var we := WorldEnvironment.new(); we.environment = env; root.add_child(we)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-35, 155, 0); sun.light_energy = 0.55; sun.shadow_enabled = true; root.add_child(sun)
	var ground := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(20, 20); ground.mesh = pm
	var gm := StandardMaterial3D.new(); gm.albedo_color = Color(0.8, 0.8, 0.8); ground.material_override = gm; root.add_child(ground)
	var vis = RiderModel.new()
	root.add_child(vis)
	vis_ref = vis
	cams = [
		[Vector3(0, 1.02, -3.4), Vector3(0, 1.02, 0)],
		[Vector3(-3.4, 1.02, 0), Vector3(0, 1.02, 0)],
		[Vector3(0, 1.02, 3.4), Vector3(0, 1.02, 0)],
		[Vector3(-1.5, 1.3, -3), Vector3(0, 1.02, 0)],
		[Vector3(-.24, 1.67, -1.0), Vector3(0, 1.65, 0)],
	]
	cam = Camera3D.new(); cam.fov = 45; root.add_child(cam); cam.current = true


func _place() -> void:
	cam.global_position = cams[idx][0]
	cam.look_at(cams[idx][1], Vector3.UP)


func _process(_d: float) -> bool:
	frame += 1
	if frame == 2:
		_place()
		vis_ref.animate("idle" if pose == "aim" else pose, 4, 0.14, pose == "aim")
	if frame % 6 == 0 and frame > 6:
		var img := get_root().get_texture().get_image()
		img.save_png("%s/character_%d.png" % [out, idx])
		idx += 1
		if idx >= cams.size():
			quit(); return true
		_place()
	return false
