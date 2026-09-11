extends SceneTree
## Standalone turntable render for visual QA of the procedural truck and packed cargo rack.

const TRUCK_VISUAL_SCRIPT = preload("res://entities/vehicles/truck/truck_visual.gd")

var out := "/tmp/truck"
var frame := 0
var index := 0
var camera: Camera3D
var truck_visual
var views := [
	[Vector3(-5.2, 2.8, -5.4), Vector3(0, 1.45, 0)],
	[Vector3(-6.2, 2.5, 0.2), Vector3(0, 1.45, 0.2)],
	[Vector3(0, 3.1, 6.3), Vector3(0, 1.55, 0.5)],
	[Vector3(5.2, 2.8, -5.4), Vector3(0, 1.45, 0)],
]


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	var root := Node3D.new(); get_root().add_child(root)
	var environment := Environment.new(); environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.72, 0.78, 0.78); environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.78, 0.79, 0.75); environment.ambient_light_energy = 0.75
	var world_environment := WorldEnvironment.new(); world_environment.environment = environment; root.add_child(world_environment)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-48, 32, 0); sun.light_energy = 1.15; sun.shadow_enabled = true; root.add_child(sun)
	var ground := MeshInstance3D.new(); var plane := PlaneMesh.new(); plane.size = Vector2(20, 20); ground.mesh = plane
	ground.material_override = Mats.solid(Color(0.70, 0.62, 0.48), 0.95); root.add_child(ground)
	truck_visual = TRUCK_VISUAL_SCRIPT.new(); root.add_child(truck_visual)
	camera = Camera3D.new(); camera.fov = 42; root.add_child(camera); camera.current = true


func _place_camera() -> void:
	camera.global_position = views[index][0]
	camera.look_at(views[index][1], Vector3.UP)


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 2:
		truck_visual.set_rider_visible(true); truck_visual.set_package_visible(true)
		_place_camera()
	if frame % 8 == 0 and frame > 8:
		get_root().get_texture().get_image().save_png("%s/truck_%d.png" % [out, index])
		index += 1
		if index >= views.size(): quit(); return true
		_place_camera()
	return false
