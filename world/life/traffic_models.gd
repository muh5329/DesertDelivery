class_name TrafficModels
extends RefCounted
## The vehicles of the outer roads' traffic: the island car and the courier truck's model (as a
## lorry) from assets/models, and three built here from primitives — a country bus, a tractor and
## a donkey cart. Every view carries metadata the traffic reads: "body" (its kinematic collider),
## "wheels" / "radius", "steer", "driver" (a seated townsperson, far mesh), "legs" (the donkey).
## All face -Z, origin on the ground between the axles.

const PAINT_NAMES := {"car": ["Car seafoam"], "lorry": ["Truck vermilion enamel"]}

static var _mats: Dictionary = {}


static func _mat(key: String, c: Color, rough := 0.8, metal := 0.0) -> StandardMaterial3D:
	if not _mats.has(key):
		_mats[key] = Mats.solid(c, rough, metal)
	return _mats[key]


static func build(kind: String) -> Node3D:
	var root := Node3D.new(); root.name = "Traffic_" + kind
	var wheels: Array = []
	var steer: Array = []
	var size: Vector3 = Vector3(OuterTraffic.KINDS[kind][1], OuterTraffic.KINDS[kind][2], OuterTraffic.KINDS[kind][0])
	var seat := Transform3D()
	var radius := 0.34
	match kind:
		"car":
			var car := IslandArt.instantiate("island_car"); root.add_child(car)
			for n in ["WheelFL", "WheelFR", "WheelRL", "WheelRR"]:
				var w := car.find_child(n, true, false); if w: wheels.append(w)
			for n in ["SteeringFL", "SteeringFR"]:
				var s := car.find_child(n, true, false); if s: steer.append(s)
			seat = Transform3D(Basis().scaled(Vector3.ONE * 0.77), Vector3(-.31, -.067, .065))
		"lorry":
			var truck := IslandArt.instantiate("courier_truck"); root.add_child(truck)
			for id in ["FL", "FR", "RL", "RR"]:
				var w := truck.find_child("Wheel" + id, true, false); if w: wheels.append(w)
			for id in ["FL", "FR"]:
				var s := truck.find_child("Steering" + id, true, false); if s: steer.append(s)
			seat = Transform3D(Basis().scaled(Vector3.ONE * 0.82), Vector3(.30, .07, -1.02))
			radius = 0.42
		"bus":
			_bus(root, wheels)
			seat = Transform3D(Basis().scaled(Vector3.ONE * 0.85), Vector3(-0.72, 0.42, -3.45))
			radius = 0.5
		"tractor":
			_tractor(root, wheels)
			seat = Transform3D(Basis().scaled(Vector3.ONE * 0.86), Vector3(0.0, 0.62, 0.35))
			radius = 0.72
		"cart":
			_cart(root, wheels)
			seat = Transform3D(Basis().scaled(Vector3.ONE * 0.86), Vector3(0.0, 0.28, 0.05))
			radius = 0.55
	# the collider: a box the courier's vehicles run into
	var body := AnimatableBody3D.new(); body.name = "Collider"
	body.sync_to_physics = false
	body.collision_layer = 16; body.collision_mask = 0
	var cs := CollisionShape3D.new(); var bx := BoxShape3D.new()
	bx.size = Vector3(size.x, size.y * 0.8, size.z)
	cs.shape = bx; cs.position = Vector3(0, size.y * 0.45, 0)
	body.add_child(cs); root.add_child(body)
	root.set_meta("body", body)
	root.set_meta("wheels", wheels)
	root.set_meta("steer", steer)
	root.set_meta("radius", radius)
	root.set_meta("seat", seat)
	root.set_meta("roll", 0.0)
	return root


## Re-paint the body colour (the car's and lorry's paint surfaces, the bus's band).
static func paint(view: Node3D, kind: String, c: Color) -> void:
	if kind in ["car", "lorry"]:
		var names: Array = PAINT_NAMES[kind]
		var overrides: Array = view.get_meta("paint_nodes", [])
		if overrides.is_empty():
			for mi: MeshInstance3D in view.find_children("*", "MeshInstance3D", true, false):
				if mi.mesh == null: continue
				for i in mi.mesh.get_surface_count():
					var src: Material = mi.get_surface_override_material(i)
					if src == null: src = mi.mesh.surface_get_material(i)
					if src is StandardMaterial3D and String(src.resource_name) in names:
						var m: StandardMaterial3D = src.duplicate()
						mi.set_surface_override_material(i, m)
						overrides.append(m)
			view.set_meta("paint_nodes", overrides)
		for m: StandardMaterial3D in overrides:
			m.albedo_color = c if kind == "car" else c.darkened(0.1)
	elif kind == "bus":
		var band: MeshInstance3D = view.get_meta("band") if view.has_meta("band") else null
		if band:
			var m: StandardMaterial3D = band.material_override
			m.albedo_color = c.darkened(0.15)


## A seated townsperson at the wheel (far mesh only: nobody looks at a driver up close for long).
static func set_driver(view: Node3D, kind: String, seed_value: int, style: StringName) -> void:
	var driver: RiderModel = view.get_meta("driver") if view.has_meta("driver") else null
	var look := CharacterLook.from_seed(seed_value, style if CharacterLook.STYLE_DATA.has(style) else &"campo", "farmer" if kind in ["tractor", "cart"] else "driver")
	if driver == null:
		driver = RiderModel.new(); driver.name = "Driver"
		driver.manual_meshes = true
		driver.look = look
		view.add_child(driver)
		driver.enable_resident_lod()
		view.set_meta("driver", driver)
	else:
		driver.set_look(look)
	driver.transform = view.get_meta("seat")
	driver.pose_riding(false)
	if kind == "cart":
		driver.leg_l.rotation.x = 1.3; driver.leg_r.rotation.x = 1.3
		driver.sync_resident_pose()
	driver.show_person_level(false)
	driver.visible = false
	view.set_meta("driver_look", look)
	PersonBuilder.request_part(look, false)


static func animate(view: Node3D, kind: String, speed: float, delta: float, _n: int) -> void:
	var roll: float = float(view.get_meta("roll", 0.0)) - speed * delta / float(view.get_meta("radius", 0.4))
	view.set_meta("roll", roll)
	for w: Node3D in view.get_meta("wheels", []): w.rotation.x = roll
	var driver: RiderModel = view.get_meta("driver") if view.has_meta("driver") else null
	if driver and not driver.visible:
		var mesh := PersonBuilder.part(view.get_meta("driver_look"), false)
		if mesh:
			driver.set_person_meshes(null, mesh)
			driver.show_person_level(false)
			driver.visible = true
			driver.sync_resident_pose()
	if kind == "cart":
		var legs: Array = view.get_meta("legs", [])
		var t: float = roll * 0.9
		for i in legs.size():
			(legs[i] as Node3D).rotation.x = sin(t + (PI if i % 2 == 1 else 0.0) + (PI * 0.5 if i >= 2 else 0.0)) * (0.45 if speed > 0.2 else 0.0)
		var head: Node3D = view.get_meta("head") if view.has_meta("head") else null
		if head: head.rotation.x = sin(t * 0.5) * 0.08


# ---------------------------------------------------------------- built vehicles
static func _wheel(root: Node3D, wheels: Array, pos: Vector3, r: float, w: float, tyre: Material, hub: Material) -> void:
	var pivot := Node3D.new(); pivot.position = pos
	root.add_child(pivot)
	pivot.add_child(Mats.cylinder(r, w, tyre, Vector3.ZERO, Vector3(0, 0, 90), 14))
	pivot.add_child(Mats.cylinder(r * 0.55, w + 0.02, hub, Vector3.ZERO, Vector3(0, 0, 90), 10))
	pivot.add_child(Mats.box(Vector3(w + 0.04, r * 1.5, 0.08), hub, Vector3.ZERO))
	wheels.append(pivot)


static func _bus(root: Node3D, wheels: Array) -> void:
	var cream := _mat("bus_cream", Color("ece3cd"))
	var band := Mats.solid(Color("3f5a7a"), 0.7)
	var glass := _mat("bus_glass", Color("2a3a44"), 0.2, 0.3)
	var dark := _mat("tyre", Color("1c1b1a"), 0.9)
	var chrome := _mat("hub", Color("b8b4a8"), 0.35, 0.6)
	root.add_child(Mats.box(Vector3(2.45, 2.2, 8.9), cream, Vector3(0, 1.55, 0)))
	var b := Mats.box(Vector3(2.47, 0.55, 8.92), band, Vector3(0, 0.75, 0))
	root.add_child(b); root.set_meta("band", b)
	root.add_child(Mats.box(Vector3(2.5, 0.75, 7.6), glass, Vector3(0, 2.0, 0.35)))
	root.add_child(Mats.box(Vector3(2.2, 0.95, 0.06), glass, Vector3(0, 1.95, -4.46)))
	root.add_child(Mats.box(Vector3(2.35, 0.18, 8.7), cream, Vector3(0, 2.72, 0)))
	root.add_child(Mats.box(Vector3(1.6, 0.3, 2.2), _mat("rack", Color("5a4a3a")), Vector3(0, 2.95, 0.8)))
	for z in [-2.9, 2.6]:
		for x in [-1.12, 1.12]:
			_wheel(root, wheels, Vector3(x, 0.5, z), 0.5, 0.32, dark, chrome)


static func _tractor(root: Node3D, wheels: Array) -> void:
	var red := _mat("tractor_red", Color("b0402f"), 0.6)
	var dark := _mat("tyre", Color("1c1b1a"), 0.9)
	var hub := _mat("tractor_hub", Color("d9b64a"), 0.5)
	var iron := _mat("iron", Color("2a2a2a"), 0.6, 0.4)
	root.add_child(Mats.box(Vector3(0.8, 0.75, 1.9), red, Vector3(0, 1.0, -0.55)))
	root.add_child(Mats.box(Vector3(0.7, 0.2, 0.2), iron, Vector3(0, 0.95, -1.55)))
	root.add_child(Mats.cylinder(0.05, 0.9, iron, Vector3(0.25, 1.7, -1.05)))
	root.add_child(Mats.box(Vector3(1.0, 0.45, 0.9), red, Vector3(0, 0.95, 0.55)))
	root.add_child(Mats.box(Vector3(0.5, 0.12, 0.45), iron, Vector3(0, 1.2, 0.5)))
	root.add_child(Mats.box(Vector3(0.5, 0.45, 0.08), iron, Vector3(0, 1.45, 0.76)))
	for x in [-0.55, 0.55]:
		root.add_child(Mats.box(Vector3(0.36, 0.08, 1.1), red, Vector3(x * 1.45, 1.47, 0.62)))
	_wheel(root, wheels, Vector3(-0.82, 0.72, 0.62), 0.72, 0.42, dark, hub)
	_wheel(root, wheels, Vector3(0.82, 0.72, 0.62), 0.72, 0.42, dark, hub)
	_wheel(root, wheels, Vector3(-0.52, 0.38, -1.15), 0.38, 0.22, dark, hub)
	_wheel(root, wheels, Vector3(0.52, 0.38, -1.15), 0.38, 0.22, dark, hub)


static func _cart(root: Node3D, wheels: Array) -> void:
	var wood := _mat("cart_wood", Color("8a6440"))
	var dark := _mat("cart_dark", Color("4a3526"))
	var sack := _mat("sack", Color("cdb88f"))
	var coat := _mat("donkey", Color("6f655c"))
	var belly := _mat("donkey_belly", Color("b8ada0"))
	# the cart behind, shafts forward to the donkey
	root.add_child(Mats.box(Vector3(1.3, 0.08, 1.8), wood, Vector3(0, 0.62, 0.9)))
	for x in [-0.63, 0.63]:
		root.add_child(Mats.box(Vector3(0.06, 0.35, 1.8), wood, Vector3(x, 0.82, 0.9)))
		root.add_child(Mats.box(Vector3(0.07, 0.07, 2.4), dark, Vector3(x * 0.62, 0.72, -0.9), Vector3(-6, 0, 0)))
	root.add_child(Mats.box(Vector3(1.3, 0.35, 0.06), wood, Vector3(0, 0.82, 1.78)))
	root.add_child(Mats.box(Vector3(1.0, 0.1, 0.35), dark, Vector3(0, 0.95, 0.15)))
	root.add_child(Mats.sphere(0.32, sack, Vector3(-0.3, 0.85, 1.2), Vector3(1.1, 0.8, 1.0), 8))
	root.add_child(Mats.sphere(0.3, sack, Vector3(0.28, 0.85, 1.35), Vector3(1.0, 0.85, 1.1), 8))
	_wheel(root, wheels, Vector3(-0.78, 0.55, 1.0), 0.55, 0.08, dark, wood)
	_wheel(root, wheels, Vector3(0.78, 0.55, 1.0), 0.55, 0.08, dark, wood)
	# the donkey
	var donkey := Node3D.new(); donkey.name = "Donkey"; donkey.position = Vector3(0, 0, -1.55)
	root.add_child(donkey)
	donkey.add_child(Mats.capsule(0.26, 1.05, coat, Vector3(0, 0.98, 0), Vector3(90, 0, 0), Vector3(1.0, 1.0, 1.1)))
	donkey.add_child(Mats.sphere(0.2, belly, Vector3(0, 0.88, 0.05), Vector3(1.1, 0.8, 2.0), 8))
	var head := Node3D.new(); head.position = Vector3(0, 1.15, -0.5); donkey.add_child(head)
	head.add_child(Mats.capsule(0.1, 0.5, coat, Vector3(0, 0.12, -0.08), Vector3(-35, 0, 0)))
	head.add_child(Mats.capsule(0.1, 0.42, coat, Vector3(0, 0.32, -0.3), Vector3(-80, 0, 0)))
	head.add_child(Mats.sphere(0.075, belly, Vector3(0, 0.26, -0.52), Vector3(1, 1, 1.2), 8))
	for x in [-0.06, 0.06]:
		head.add_child(Mats.capsule(0.03, 0.26, coat, Vector3(x, 0.52, -0.2), Vector3(-20, 0, x * 250)))
	root.set_meta("head", head)
	var legs: Array = []
	for z in [-0.34, 0.34]:
		for x in [-0.13, 0.13]:
			var leg := Node3D.new(); leg.position = Vector3(x, 0.85, z); donkey.add_child(leg)
			leg.add_child(Mats.capsule(0.055, 0.85, coat, Vector3(0, -0.42, 0)))
			leg.add_child(Mats.cylinder(0.05, 0.08, _mat("hoof", Color("2a241f")), Vector3(0, -0.82, 0), Vector3.ZERO, 8))
			legs.append(leg)
	root.set_meta("legs", legs)
