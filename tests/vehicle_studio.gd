extends SceneTree
## Studio renders of the Jeep, the Cart and the bike's hitch (no world boot): the real bodies on
## a flat deck, settled by their own physics, so the renders show whether tyres touch the ground,
## the drawbar meets the hitch, the driver sits in his seat and the load sits on the beds.
##   xvfb-run -a godot --path . --rendering-driver vulkan -s tests/vehicle_studio.gd -- --out=DIR [--only=a,b]
## Shots: jeep_front, jeep_side, jeep_rear, jeep_top, jeep_water (the amphibious pose), rig_side,
## rig_hitch, rig_top, bike_rig, cart_load.

var out := "/tmp/vehicle_studio"
var only: PackedStringArray = []
var stage: Node3D
var cam: Camera3D
var jeep: Jeep
var bike: Bike
var cart: CargoCart
var cart2: CargoCart
var frame := 0
var idx := 0
var shots: Array = []


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
		if a.begins_with("--only="): only = a.substr(7).split(",")
	DirAccess.make_dir_recursive_absolute(out)
	stage = Node3D.new()
	get_root().add_child(stage)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.74, 0.80, 0.86)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.80, 0.86)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new(); we.environment = env; stage.add_child(we)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-42, 140, 0); sun.light_energy = 1.2; sun.shadow_enabled = true
	stage.add_child(sun)
	var fill := DirectionalLight3D.new(); fill.rotation_degrees = Vector3(-18, -50, 0); fill.light_energy = 0.3
	stage.add_child(fill)
	var ground := StaticBody3D.new(); ground.collision_layer = 1
	var cs := CollisionShape3D.new(); var box := BoxShape3D.new(); box.size = Vector3(120, 1, 120); cs.shape = box; cs.position.y = -0.5
	ground.add_child(cs); stage.add_child(ground)
	var mesh := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(120, 120); mesh.mesh = pm
	var gm := StandardMaterial3D.new(); gm.albedo_color = Color(0.66, 0.60, 0.50); mesh.material_override = gm; ground.add_child(mesh)
	# a strip of "water" to stand the amphibious jeep in (visual only)
	var water := MeshInstance3D.new(); var wm := PlaneMesh.new(); wm.size = Vector2(12, 12); water.mesh = wm
	var wmat := StandardMaterial3D.new(); wmat.albedo_color = Color(0.25, 0.48, 0.56, 0.8); wmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.material_override = wmat; water.position = Vector3(30, 0.62, 0); stage.add_child(water)
	cam = Camera3D.new(); cam.fov = 38; stage.add_child(cam); cam.current = true
	# the jeep towing a loaded cart, the bike towing another
	jeep = Jeep.new(); jeep.apply_definition(load("res://data/vehicles/jeep.tres")); stage.add_child(jeep)
	jeep.place(Vector3(0, 0.05, 0), Vector3.FORWARD)
	cart = CargoCart.new(); stage.add_child(cart)
	cart.place_behind(jeep)
	cart.tow_vehicle = jeep; jeep.set_towing(cart)
	cart.inventory.add("planks", 20); cart.inventory.add("wine", 4); cart.inventory.add("grain", 15); cart.inventory.add("fuel_can", 2); cart.inventory.add("ammo_crate", 2)
	jeep.bed.add("tools", 6); jeep.bed.add("bread", 10)
	bike = Bike.new(); bike.apply_definition(load("res://data/vehicles/bike.tres")); stage.add_child(bike)
	bike.place(Vector3(-12, 0.05, 0), Vector3.FORWARD)
	cart2 = CargoCart.new(); stage.add_child(cart2)
	cart2.place_behind(bike)
	cart2.tow_vehicle = bike; bike.set_towing(cart2)
	cart2.inventory.add("fish", 20); cart2.inventory.add("cloth", 20); cart2.inventory.add("blocks", 10)
	bike.set_parked(false)
	jeep.set_parked(false)
	var tb: Node3D = Node3D.new()
	var h: Vector3 = bike.definition.hitch_offset
	tb.name = "TowBar"; bike.add_child(tb)
	var steel := Mats.solid(Color(0.18, 0.18, 0.19), 0.5, 0.6)
	tb.add_child(Mats.limb(Vector3(-0.12, 0.34, 0.72), h + Vector3(0, -0.03, -0.1), 0.025, steel))
	tb.add_child(Mats.limb(Vector3(0.12, 0.34, 0.72), h + Vector3(0, -0.03, -0.1), 0.025, steel))
	tb.add_child(Mats.sphere(0.045, Mats.solid(Color(0.7, 0.7, 0.72), 0.3, 0.8), h))
	var j := Vector3(0, 1.0, 0)
	shots = [
		["jeep_front", Vector3(5.5, 2.2, -6.5), j],
		["jeep_side", Vector3(8.5, 1.3, 0.2), j + Vector3(0, -0.2, 0)],
		["jeep_rear", Vector3(-5.0, 2.6, 7.5), Vector3(0, 0.9, 3.0)],
		["jeep_top", Vector3(4.0, 7.5, 2.5), Vector3(0, 0.6, 1.5)],
		["rig_side", Vector3(12.0, 2.4, 3.8), Vector3(0, 0.8, 3.2)],
		["rig_hitch", Vector3(3.2, 1.1, 3.4), Vector3(0, 0.55, 2.8)],
		["cart_load", Vector3(3.6, 3.4, 8.8), Vector3(0, 0.9, 4.3)],
		["bike_rig", Vector3(-6.5, 2.2, 5.0), Vector3(-12, 0.7, 2.0)],
		["jeep_water", Vector3(36.0, 2.4, -6.0), Vector3(30, 1.0, 0)],
	]
	if not only.is_empty():
		shots = shots.filter(func(s): return s[0] in only)


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 2:
		# settle on the deck, then the amphibious pose for the water shot
		pass
	if frame < 60: return false
	if idx >= shots.size():
		quit()
		return true
	var s: Array = shots[idx]
	if String(s[0]) == "jeep_water" and frame == 60 + idx * 12:
		jeep.set_towing(null); cart.tow_vehicle = null
		jeep.set_physics_process(false)
		jeep.global_position = Vector3(30, 0.62 - jeep.definition.draught, 0)
		jeep.afloat = true
		for k in 40: jeep.visual.update_visual(jeep, 0.05)
	if (frame - 60) % 12 == 0:
		cam.look_at_from_position(s[1], s[2], Vector3.UP)
	if (frame - 60) % 12 == 11:
		var img := get_root().get_texture().get_image()
		var p := "%s/%s.png" % [out, s[0]]
		img.save_png(p)
		print("saved ", p, "  jeep y %.3f cart y %.3f wheels %s" % [jeep.global_position.y, cart.global_position.y, str(jeep.visual.wheel_travel)])
		idx += 1
	return false
