extends SceneTree
## Debug viewer for the bike + rider model: captures front-3/4, side, rear views on a plain backdrop.
## xvfb-run godot --path . --rendering-driver opengl3 -s tests/bike_view.gd -- --out=/tmp/bike  (standalone: no game needed)

var out := "/tmp/bike"
var frame := 0
var idx := 0
var cams := []
var cam: Camera3D
var vis_ref


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	var root := Node3D.new()
	get_root().add_child(root)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.82, 0.82, 0.84)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.75, 0.85)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new(); we.environment = env; root.add_child(we)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-50, 30, 0); sun.light_energy = 1.0; sun.shadow_enabled = true; root.add_child(sun)
	var ground := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(20, 20); ground.mesh = pm
	var gm := StandardMaterial3D.new(); gm.albedo_color = Color(0.8, 0.8, 0.8); ground.material_override = gm; root.add_child(ground)
	var vis = load("res://entities/vehicles/bike/bike_visual.gd").new()
	root.add_child(vis)
	vis_ref = vis
	cams = [
		[Vector3(-3.2, 1.6, -3.0), Vector3(0, 0.9, 0)],
		[Vector3(-4.0, 1.2, 0.0), Vector3(0, 0.9, 0)],
		[Vector3(0.0, 1.5, 4.2), Vector3(0, 0.9, 0)],
		[Vector3(3.0, 1.6, -3.2), Vector3(0, 0.9, 0)],
	]
	cam = Camera3D.new(); cam.fov = 45; root.add_child(cam); cam.current = true
	_place()


func _place() -> void:
	cam.global_position = cams[idx][0]
	cam.look_at(cams[idx][1], Vector3.UP)


func _process(_d: float) -> bool:
	frame += 1
	if frame == 2:
		_place()
		vis_ref.set_package_visible(true)
	if frame % 6 == 0 and frame > 6:
		var img := get_root().get_texture().get_image()
		img.save_png("%s/bike_%d.png" % [out, idx])
		idx += 1
		if idx >= cams.size():
			quit(); return true
		_place()
	return false
