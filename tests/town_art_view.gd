extends SceneTree
## Reproducible close asset review, independent of terrain streaming.
var frame := 0
var out := "/tmp/desert-town-art"
var cam: Camera3D
var target: Node3D
var stage := 0
func _init() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	var root := Node3D.new(); get_root().add_child(root)
	var env := Environment.new(); env.background_mode = Environment.BG_COLOR; env.background_color = Color(.68,.76,.81)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.ambient_light_color = Color(.76,.80,.87); env.ambient_light_energy = .55
	env.tonemap_mode = Environment.TONE_MAPPER_ACES; env.ssao_enabled = true; env.ssao_radius = .8
	var we := WorldEnvironment.new(); we.environment = env; root.add_child(we)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-43,-24,0); sun.light_energy = 1.7; sun.shadow_enabled = true; root.add_child(sun)
	var ground := MeshInstance3D.new(); var mesh := PlaneMesh.new(); mesh.size = Vector2(90,90); ground.mesh = mesh
	var mat := StandardMaterial3D.new(); mat.albedo_color = Color(.65,.64,.58); ground.material_override = mat; root.add_child(ground)
	target = Node3D.new(); root.add_child(target)
	var car := IslandArt.instantiate("island_car"); target.add_child(car)
	cam = Camera3D.new(); cam.fov = 45; root.add_child(cam); cam.current = true
	cam.look_at_from_position(Vector3(-3.9,2.0,-4.0),Vector3(0,.75,0))
func _process(_delta: float) -> bool:
	frame += 1
	if frame == 16:
		get_root().get_texture().get_image().save_png(out+"/car.png")
		for child in target.get_children(): child.queue_free()
		for i in range(3):
			var house := IslandArt.instantiate("town_house_2_%d" % i); target.add_child(house); house.position.x = (i-1)*7.4
		var palm := IslandArt.instantiate("harbour_palm"); target.add_child(palm); palm.position = Vector3(-7,0,-5)
		cam.look_at_from_position(Vector3(-17,12,-25),Vector3(0,3,0))
	if frame == 32:
		get_root().get_texture().get_image().save_png(out+"/houses.png")
		quit(); return true
	return false
