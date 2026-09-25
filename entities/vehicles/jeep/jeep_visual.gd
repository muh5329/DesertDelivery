class_name JeepVisual
extends Node3D
## The Jeep as drawn: LegendOfJeep's realistic amphibious 4x4 (assets/models/vehicles/
## realistic_amphibious_jeep_v1.glb, authored in Blender with its own PBR materials and maps),
## animated the way its JeepMesh does it — steering pivots on the front wheels, a spin pivot in
## every wheel, each wheel riding its own suspension travel, the body leaning into turns and
## pitching under throttle and brakes, and the amphibious transformation driven by one 0..1
## blend: the side pontoons swing down from the rockers, the propeller pods fold out from the
## rear crossmember and spin, and the mode glow lights. The winch cable, the seated driver, the
## load on the rear bed and the tow hitch are this project's.
##
## The GLB's wheel pivots sit at the wheel centres (y = 0) with 0.56 m tyres, so the model is
## raised by WHEEL_RADIUS to put the tyres on the vehicle's ground plane (the body origin).

const MODEL_PATH := "res://assets/models/vehicles/realistic_amphibious_jeep_v1.glb"
const WHEEL_RADIUS := 0.56
const TRAVEL := 0.16                 ## suspension travel either way (m)
const STEER_MAX := 0.62              ## rad at the front wheels (LegendOfJeep)
## Road-mode and water-mode poses of the amphibious gear (JeepMesh.update_amphibious, imported branch).
const PONTOON_Y := [0.26, 0.10]
const PROP_Y := [0.47, 0.31]
const PROP_Z := [1.77, 1.92]
const GROUND := -0.51                ## JeepMesh.GROUND: the source's body-space ground

var model: Node3D
var body_pivot: Node3D
var wheels: Array[Node3D] = []       ## FL, FR, RL, RR steering pivots
var wheel_spins: Array[Node3D] = []
var pontoons: Array[Node3D] = []
var propellers: Array[Node3D] = []
var propeller_spins: Array[Node3D] = []
var mode_glows: Array[MeshInstance3D] = []
var brake_glows: Array[MeshInstance3D] = []
var driver: RiderModel
var load_view: CargoLoadView
var amphibious_blend := 0.0
var wheel_travel: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _wheel_rest: Array[Vector3] = []
var _wheel_spin: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _prop_angle := 0.0
var _rope: MeshInstance3D
var _rope_mesh: CylinderMesh
var _squash := 0.0
var _spray: CPUParticles3D


func _ready() -> void:
	model = Node3D.new(); model.name = "Model"; model.position = Vector3(0, WHEEL_RADIUS, 0); add_child(model)
	var imported: Node3D = (load(MODEL_PATH) as PackedScene).instantiate()
	imported.name = "ImportedRealisticJeep"
	model.add_child(imported)
	var root: Node3D = imported.find_child("RealisticAmphibious4x4", true, false)
	if root == null: root = imported
	_bind_vertex_materials(root)
	body_pivot = root.find_child("BodyPivot", true, false)
	for i in 4:
		var w: Node3D = root.find_child("Wheel%d" % i, true, false)
		wheels.append(w)
		_wheel_rest.append(w.position)
		wheel_spins.append(w.find_child("Spin*", true, false))
	for suffix in ["L", "R"]:
		var side := -1.0 if suffix == "L" else 1.0
		var p: Node3D = root.find_child("Pontoon" + suffix, true, false); p.set_meta("side", side); pontoons.append(p)
		var pr: Node3D = root.find_child("Propeller" + suffix, true, false); pr.set_meta("side", side); propellers.append(pr)
		propeller_spins.append(pr.find_child("PropSpin*", true, false))
		mode_glows.append(root.find_child("ModeGlow" + suffix, true, false))
	VehicleLights.dress(model, true)
	_build_brake_glow()
	_build_driver()
	_build_bed()
	_build_hitch()
	_build_rope()
	_build_spray()
	update_amphibious(0.0)


## LegendOfJeep: the Blender sections carry a colour atlas in COLOR_0 that Godot imports without
## enabling it as albedo; without this the whole vehicle is the material's white factor.
func _bind_vertex_materials(root: Node3D) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		if m.mesh == null or m.mesh.get_surface_count() == 0: continue
		if (m.mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_COLOR) == 0: continue
		var source := m.get_active_material(0) as StandardMaterial3D
		if source == null: continue
		var inst := source.duplicate() as StandardMaterial3D
		inst.vertex_color_use_as_albedo = true
		m.material_override = inst


func _build_brake_glow() -> void:
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(1.0, 0.12, 0.06)
	for x in [-0.67, 0.67]:
		var q := Mats.box(Vector3(0.16, 0.24, 0.01), glow, Vector3(x, 0.53, 1.806))
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		q.visible = false
		body_pivot.add_child(q)
		brake_glows.append(q)


func _build_driver() -> void:
	driver = RiderModel.new()
	driver.name = "Driver"
	driver.scale = Vector3.ONE * 0.92
	driver.position = Vector3(-0.42, 0.25, 0.12)
	body_pivot.add_child(driver)
	driver.pose_seated(0.36)
	for side in [-1.0, 1.0]:
		var arm: Node3D = driver.arm_l if side < 0 else driver.arm_r
		arm.rotation = Vector3(1.05, 0, side * 0.12)
		arm.get_node("Elbow").rotation.x = 0.55


## The rear bed behind the seats: a load view over the tub floor (the Jeep's own small hold).
func _build_bed() -> void:
	load_view = CargoLoadView.new(); load_view.name = "Bed"
	body_pivot.add_child(load_view)
	var slots: Array[Vector3] = []
	for z in [0.98, 1.40]:
		for x in [-0.34, 0.34]:
			slots.append(Vector3(x, 0.62, z))
	load_view.setup(slots, 30.0)


func _build_hitch() -> void:
	var steel := Mats.solid(Color(0.16, 0.16, 0.17), 0.5, 0.6)
	var hitch := Node3D.new(); hitch.name = "TowHitch"; body_pivot.add_child(hitch)
	hitch.add_child(Mats.box(Vector3(0.08, 0.08, 0.34), steel, Vector3(0, -0.02, 2.02)))
	hitch.add_child(Mats.sphere(0.05, Mats.solid(Color(0.7, 0.7, 0.72), 0.3, 0.8), Vector3(0, 0.04, 2.17)))


func _build_rope() -> void:
	_rope_mesh = CylinderMesh.new(); _rope_mesh.top_radius = 0.023; _rope_mesh.bottom_radius = 0.023; _rope_mesh.height = 1.0; _rope_mesh.radial_segments = 6
	_rope = MeshInstance3D.new(); _rope.name = "WinchCable"; _rope.mesh = _rope_mesh
	_rope.material_override = Mats.solid(Color(0.12, 0.10, 0.08), 0.55, 0.25)
	_rope.visible = false; add_child(_rope)
	# the winch drum on the front bumper
	var drum := Mats.cylinder(0.09, 0.40, Mats.solid(Color(0.18, 0.18, 0.19), 0.45, 0.6), Vector3(0, 0.03, -1.97), Vector3(0, 0, 90), 12)
	drum.name = "WinchDrum"; body_pivot.add_child(drum)


func _build_spray() -> void:
	_spray = CPUParticles3D.new(); _spray.name = "BowSpray"
	_spray.amount = 60; _spray.lifetime = 0.9; _spray.emitting = false; _spray.local_coords = false
	_spray.position = Vector3(0, 0.25, -1.9)
	_spray.direction = Vector3(0, 0.8, 0.4); _spray.spread = 60
	_spray.initial_velocity_min = 1.5; _spray.initial_velocity_max = 4.0
	_spray.gravity = Vector3(0, -9, 0)
	_spray.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX; _spray.emission_box_extents = Vector3(0.9, 0.05, 0.2)
	var m := QuadMesh.new(); m.size = Vector2(0.45, 0.45)
	var mat := StandardMaterial3D.new(); mat.albedo_color = Color(0.94, 0.97, 1.0, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.vertex_color_use_as_albedo = true
	# a soft round droplet cloud, not a square
	var soft := GradientTexture2D.new(); soft.width = 32; soft.height = 32
	soft.fill = GradientTexture2D.FILL_RADIAL; soft.fill_from = Vector2(0.5, 0.5); soft.fill_to = Vector2(1.0, 0.5)
	soft.gradient = Gradient.new(); soft.gradient.set_color(0, Color.WHITE); soft.gradient.set_color(1, Color(1, 1, 1, 0))
	mat.albedo_texture = soft
	m.material = mat; _spray.mesh = m
	_spray.color_ramp = Gradient.new()
	_spray.color_ramp.set_color(0, Color(1, 1, 1, 0.8)); _spray.color_ramp.set_color(1, Color(1, 1, 1, 0.0))
	_spray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_spray)


func set_rider_visible(v: bool) -> void:
	if driver: driver.visible = v


func set_package_visible(v: bool) -> void:
	if load_view: load_view.set_parcel_visible(v)


func show_bed(inv: Inventory) -> void:
	if load_view: load_view.show_inventory(inv)


## The whole amphibious transformation from one blend (0 road, 1 water), as JeepMesh does it.
func update_amphibious(blend: float) -> void:
	amphibious_blend = blend
	var t := smoothstep(0.0, 1.0, clampf(blend, 0.0, 1.0))
	for p in pontoons:
		var side: float = p.get_meta("side", 1.0)
		p.rotation.z = lerpf(side * deg_to_rad(88.0), 0.0, t)
		p.position.y = lerpf(PONTOON_Y[0], PONTOON_Y[1], t)
	for p in propellers:
		var side: float = p.get_meta("side", 1.0)
		p.position = Vector3(side * 0.48, lerpf(PROP_Y[0], PROP_Y[1], t), lerpf(PROP_Z[0], PROP_Z[1], t))
		p.rotation.x = lerpf(deg_to_rad(82.0), 0.0, t)
	for s in propeller_spins: s.rotation.z = _prop_angle
	for g in mode_glows:
		g.visible = blend > 0.08
		g.scale.z = maxf(0.05, t)


func update_visual(jeep, delta: float) -> void:
	var afloat: bool = jeep.afloat
	# the transformation takes about a second either way (LegendOfJeep: delta / 1.05)
	var blend := move_toward(amphibious_blend, 1.0 if afloat else 0.0, delta / 1.05)
	if afloat and (jeep.throttle > 0.04 or absf(jeep.speed) > 1.0):
		_prop_angle += delta * (7.0 + absf(jeep.speed) * 1.4) * (1.0 if jeep.speed >= -0.1 else -1.0)
	update_amphibious(blend)
	# wheels: steer, spin, and ride the suspension (lifted into the arches afloat)
	var steer_angle: float = jeep.steer * STEER_MAX * (1.0 - 0.55 * clampf(absf(jeep.speed) / 24.0, 0.0, 1.0))
	for i in 4:
		if i < 2: wheels[i].rotation.y = lerp_angle(wheels[i].rotation.y, -steer_angle, clampf(delta * 18.0, 0, 1))
		var travel: float = jeep.wheel_travel(i) if not afloat else 0.0
		wheel_travel[i] = lerpf(wheel_travel[i], clampf(travel, -TRAVEL, TRAVEL), clampf(delta * 20.0, 0, 1))
		wheels[i].position.y = _wheel_rest[i].y + wheel_travel[i] + amphibious_blend * 0.28
		if not afloat: _wheel_spin[i] -= jeep.speed / WHEEL_RADIUS * delta
		wheel_spins[i].rotation.x = _wheel_spin[i]
	# body: roll into the turn, pitch under throttle and brake, a squash on a hard landing
	var lateral: float = clampf(jeep.speed * jeep.drive.yaw_input / 12.0, -1.0, 1.0)
	var target_roll := -lateral * 0.08
	var target_pitch := clampf(jeep.throttle * 0.035 - jeep.brake * 0.05 * signf(jeep.speed), -0.08, 0.08) if not afloat else 0.0
	body_pivot.rotation.z = lerp_angle(body_pivot.rotation.z, target_roll, clampf(delta * 6.0, 0, 1))
	body_pivot.rotation.x = lerp_angle(body_pivot.rotation.x, target_pitch, clampf(delta * 6.0, 0, 1))
	_squash = move_toward(_squash, 0.0, delta * 3.2)
	var s := _squash * 0.2
	body_pivot.scale = body_pivot.scale.lerp(Vector3(1.0 + s * 0.5, 1.0 - s, 1.0 + s * 0.5), clampf(delta * 16.0, 0, 1))
	var braking: bool = jeep.brake > 0.05 and jeep.speed > 0.3 or jeep.handbrake
	for g in brake_glows: g.visible = braking and jeep.driven()
	if driver: driver.rotation.y = lerpf(driver.rotation.y, -jeep.steer * 0.1, clampf(delta * 4.0, 0, 1))
	_spray.emitting = afloat and absf(jeep.speed) > 2.5
	_spray.initial_velocity_max = 2.5 + absf(jeep.speed) * 0.35
	if jeep.winch_attached: _update_rope(jeep.winch_anchor_world())
	else: _rope.visible = false


func landed(impact: float) -> void:
	_squash = clampf(impact / 14.0, 0.0, 1.0)


func _update_rope(world_anchor: Vector3) -> void:
	var a := body_pivot.transform * Vector3(0, 0.03, -2.02) + model.position
	var b := to_local(world_anchor)
	var d := b - a
	var length := d.length()
	if length < 0.05: _rope.visible = false; return
	_rope.visible = true
	_rope_mesh.height = length
	var y := d / length
	var helper := Vector3.RIGHT if absf(y.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var x := helper.cross(y).normalized()
	var z := x.cross(y).normalized()
	_rope.transform = Transform3D(Basis(x, y, z), (a + b) * 0.5)
