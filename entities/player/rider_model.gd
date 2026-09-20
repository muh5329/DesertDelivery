class_name RiderModel
extends Node3D
## Standalone animated boy (same design as the seated rider): orange hair, blue shirt, coral
## neckerchief, tan trousers with suspenders, brown boots and gloves. Built from primitives with
## pivot nodes so we can animate walking, idling, swimming and aiming. Origin at the feet.

const SKIN := Color(0.96, 0.82, 0.68)
const HAIR := Color(0.80, 0.45, 0.16)
const SHIRT := Color(0.55, 0.59, 0.80)
const SCARF := Color(0.90, 0.42, 0.34)
const TROUSER := Color(0.87, 0.76, 0.52)
const BOOT := Color(0.40, 0.25, 0.16)
const STRAP := Color(0.93, 0.85, 0.58)

var root: Node3D          # body root (pelvis pivot), lets us tilt the whole body for swimming
var torso: Node3D
var head: Node3D
var arm_l: Node3D
var arm_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var hand_r: Node3D        # attachment point for the pistol
var gun_node: Node3D
var _t := 0.0
var _base_head_scale := Vector3.ONE
var _skin_bridge: PivotSkinBridge
var _model: Node3D
var resident_lod_active := false
var _lod_pairs: Array[Dictionary] = []
static var _lod_parts: Dictionary = {}
const NPC_LOD = preload("res://assets/models/courier_character_npc_lod.glb")

const HIP_H := 0.82
const THIGH := 0.42
const SHIN := 0.40


const MODEL = preload("res://assets/models/courier_character.glb")

func _ready() -> void:
	var model: Node3D = MODEL.instantiate()
	_model = model
	add_child(model)
	# Authored character colors use a clean matte surface, matching the supplied turnaround.
	for mesh_instance in model.find_children("*", "MeshInstance3D", true, false):
		for surface in mesh_instance.mesh.get_surface_count():
			var source = mesh_instance.mesh.surface_get_material(surface)
			if source is StandardMaterial3D:
				var mat: StandardMaterial3D = source.duplicate()
				mat.roughness = maxf(mat.roughness, .55)
				mat.metallic = minf(mat.metallic, .2)
				mesh_instance.set_surface_override_material(surface, mat)
	root = model.find_child("Root", true, false)
	torso = model.find_child("Torso", true, false)
	head = model.find_child("Head", true, false)
	_base_head_scale = head.scale
	arm_l = model.find_child("ArmL", true, false)
	arm_r = model.find_child("ArmR", true, false)
	leg_l = model.find_child("LegL", true, false)
	leg_r = model.find_child("LegR", true, false)
	for arm in [arm_l, arm_r]:
		var elbow: Node3D = arm.find_child("Elbow*", true, false)
		elbow.name = "Elbow"
		var hand: Node3D = elbow.find_child("Hand*", true, false)
		hand.name = "Hand"
		if arm == arm_r: hand_r = hand
	for leg in [leg_l, leg_r]:
		leg.find_child("Knee*", true, false).name = "Knee"
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	if not skeletons.is_empty():
		_skin_bridge = PivotSkinBridge.new()
		add_child(_skin_bridge)
		var bindings: Dictionary = {"Skin_Root":root, "Skin_Torso":torso, "Skin_Head":head}
		for side in ["L", "R"]:
			var arm: Node3D = arm_l if side == "L" else arm_r
			var leg: Node3D = leg_l if side == "L" else leg_r
			bindings["Skin_Arm"+side] = arm
			bindings["Skin_Elbow"+side] = arm.get_node("Elbow")
			bindings["Skin_Hand"+side] = arm.get_node("Elbow/Hand")
			bindings["Skin_Leg"+side] = leg
			bindings["Skin_Knee"+side] = leg.get_node("Knee")
		var skin_bound := _skin_bridge.bind(skeletons[0], bindings)
		assert(skin_bound, "Courier cloth skin must bind to every gameplay pivot")



## Resident-only visibility LOD keeps every pivot, accessory and skeleton alive.
## Immutable sibling meshes avoid resizing active skinned buffers on Metal.
## Call after palette/identity initialization. The player never enables this path.
func enable_resident_lod() -> void:
	if "--full-npcs" in OS.get_cmdline_user_args(): return
	if not _lod_pairs.is_empty(): return
	if _lod_parts.is_empty():
		var reduced: Node3D = NPC_LOD.instantiate()
		for node in reduced.find_children("*", "MeshInstance3D", true, false):
			_lod_parts[String(node.name)] = {"mesh":node.mesh, "skin":node.skin}
		reduced.free()
	for node in _model.find_children("*", "MeshInstance3D", true, false):
		if not _lod_parts.has(String(node.name)): continue
		var low: Dictionary = _lod_parts[String(node.name)]
		var colors: Dictionary = {}
		var full_materials: Array[Material] = []
		for surface in node.mesh.get_surface_count():
			var source: Material = node.mesh.surface_get_material(surface)
			var active: Material = node.get_active_material(surface)
			full_materials.append(active)
			if source: colors[source.resource_name] = active
		var low_materials: Array[Material] = []
		for surface in low.mesh.get_surface_count():
			var source: Material = low.mesh.surface_get_material(surface)
			low_materials.append(colors.get(source.resource_name, source) if source else null)
		var reduced_node := MeshInstance3D.new()
		reduced_node.name = String(node.name) + "NPCLOD"
		reduced_node.mesh = low.mesh
		# The reduced export's bind names/poses are verified equal by the asset
		# contract test. Reuse the ORIGINAL skin and original live skeleton.
		reduced_node.skin = node.skin
		reduced_node.skeleton = node.skeleton
		reduced_node.transform = node.transform
		reduced_node.cast_shadow = node.cast_shadow
		reduced_node.layers = node.layers
		reduced_node.visible = false
		for surface in low_materials.size():
			reduced_node.set_surface_override_material(surface, low_materials[surface])
		node.get_parent().add_child(reduced_node)
		_lod_pairs.append({"node":node,"reduced_node":reduced_node,"full_mesh":node.mesh,"full_skin":node.skin,
			"low_mesh":low.mesh,"low_skin":low.skin,"full_materials":full_materials,"low_materials":low_materials})
	# ResidentActor explicitly flushes after all occupation-specific limb edits.
	if _skin_bridge: _skin_bridge.set_process(false)

func set_resident_lod_distance(distance: float) -> void:
	if _lod_pairs.is_empty(): return
	var reduced := distance > 22.0 if not resident_lod_active else distance >= 18.0
	if reduced == resident_lod_active: return
	resident_lod_active = reduced
	for pair in _lod_pairs:
		pair.node.visible = not reduced
		pair.reduced_node.visible = reduced

func sync_resident_pose() -> void:
	if _skin_bridge: _skin_bridge.sync_pose()


func pose_riding(motorcycle_fit: bool = false, sync_skin: bool = true) -> void:
	# Motorcycle pelvis rests on the saddle; the car keeps its higher footwell pose.
	root.position = Vector3(0, 1.025, .53) if motorcycle_fit else Vector3(0, 1.10, 0.25)
	torso.rotation.x = -.65 if motorcycle_fit else -0.28
	head.rotation.x = .45 if motorcycle_fit else 0.0
	for side in [-1.0, 1.0]:
		var leg := leg_l if side < 0 else leg_r
		# Bike footpegs are y=.38, z=.21; the car seating pose has a higher footwell.
		leg.rotation = Vector3(.90, side * -.22735, side * .25392) if motorcycle_fit else Vector3(1.20, side * -0.25, side * 0.30)
		leg.get_node("Knee").rotation.x = -.80387 if motorcycle_fit else -1.53
		var arm := arm_l if side < 0 else arm_r
		arm.rotation = Vector3(1.50, 0, side * .17801) if motorcycle_fit else Vector3(0.85, 0, side * 0.13)
		arm.scale.y = 1.21657 if motorcycle_fit else 1.25
		arm.get_node("Elbow").rotation.x = .36834 if motorcycle_fit else 0.35
	if sync_skin and _skin_bridge: _skin_bridge.sync_pose()


func set_palette(shirt_color: Color, trouser_color: Color, hair_color: Color, skin_color: Color) -> void:
	for node in find_children("*", "MeshInstance3D", true, false):
		for index in range(node.mesh.get_surface_count()):
			var original: Material = node.mesh.surface_get_material(index)
			if not original is StandardMaterial3D: continue
			var tint := Color.TRANSPARENT
			if original.resource_name.begins_with("Shirt"): tint = shirt_color
			elif original.resource_name.begins_with("Trousers"): tint = trouser_color
			elif original.resource_name.begins_with("Hair"): tint = hair_color
			elif original.resource_name.begins_with("Skin"): tint = skin_color
			if tint.a > 0:
				var mat: StandardMaterial3D = original.duplicate()
				mat.albedo_color = tint
				Storybook.finish(mat)
				node.set_surface_override_material(index, mat)


## Residents share a rig, but wear deterministic occupation silhouettes. Accessories
## attach to existing pivots, so walking, working, driving and hand props keep animating.
func set_character_identity(identity: String, occupation: String, palette: Array) -> void:
	if head == null or torso == null: return
	for pivot in [head, torso]:
		var old: Node3D = pivot.get_node_or_null("ResidentWardrobe")
		if old: pivot.remove_child(old); old.queue_free()
	var hair := Mats.solid(Color(palette[2]), .94)
	var cloth := Mats.solid(Color(palette[0]).darkened(.12), .96)
	var linen := Mats.solid(Color("e6d8b4"), .98)
	var leather := Mats.solid(Color("604c3d"), .93)
	var brass := Mats.solid(Color("b9a174"), .82)
	var seed_value := absi(identity.hash())
	var crown := Node3D.new(); crown.name="ResidentWardrobe"; head.add_child(crown)
	var outfit := Node3D.new(); outfit.name="ResidentWardrobe"; torso.add_child(outfit)
	# Small proportion differences alter the silhouette while retaining foot contact.
	torso.scale.x = [0.94,1.0,1.10,1.16][seed_value % 4]
	head.scale = _base_head_scale * [0.98,1.02,1.06][(seed_value >> 2) % 3]
	var style := seed_value % 4
	if style == 0:
		crown.add_child(Mats.sphere(.088,hair,Vector3(0,.075,.14),Vector3(1,.85,1)))
	elif style == 1:
		for side in [-1.0,1.0]:
			crown.add_child(Mats.capsule(.043,.21,hair,Vector3(side*.12,-.015,.068),Vector3(0,0,side*12)))
	elif style == 2:
		for index in range(5):
			var angle:=float(index)*TAU/5.0
			crown.add_child(Mats.sphere(.059,hair,Vector3(sin(angle)*.09,.12,cos(angle)*.07),Vector3(1,.8,1)))
	if occupation in ["Gardener","Shepherd","Ranger"]:
		var straw:=Mats.solid(Color("c9b57b"),.97)
		crown.add_child(Mats.cylinder(.25,.024,straw,Vector3(0,.155,.012),Vector3(0,0,-5),32))
		crown.add_child(Mats.cylinder(.143,.115,straw,Vector3(0,.22,.012),Vector3(0,0,-5),24,.114))
		crown.add_child(Mats.cylinder(.145,.022,cloth,Vector3(0,.177,.012),Vector3(0,0,-5),24))
	elif occupation == "Baker":
		crown.add_child(Mats.cylinder(.14,.074,linen,Vector3(0,.166,0),Vector3.ZERO,24))
		for offset in [-.08,0.0,.08]: crown.add_child(Mats.sphere(.094,linen,Vector3(offset,.239,.016),Vector3(1,.87,1)))
	elif occupation in ["Courier","Produce driver","Mechanic"]:
		crown.add_child(Mats.sphere(.169,cloth,Vector3(0,.207,.015),Vector3(1,.75,1)))
		crown.add_child(Mats.sphere(.15,cloth,Vector3(0,.172,-.12),Vector3(1,.08,.60)))
		crown.add_child(Mats.sphere(.022,brass,Vector3(0,.217,-.123),Vector3(1,1,.20)))
	elif occupation == "Fisher":
		crown.add_child(Mats.sphere(.169,cloth,Vector3(0,.205,.016),Vector3(1,.83,1)))
		crown.add_child(Mats.torus(.131,.167,cloth,Vector3(0,.162,.016),Vector3.ZERO,Vector3(1,.65,1)))
	if occupation in ["Baker","Shopkeeper","Gardener","Mechanic"]:
		var apron := linen if occupation in ["Baker","Shopkeeper"] else cloth
		outfit.add_child(_tailored_panel(apron))
		outfit.add_child(Mats.box(Vector3(.13,.083,.012),cloth,Vector3(0,.10,-.133)))
		for side in [-1.0,1.0]: outfit.add_child(Mats.box(Vector3(.027,.22,.018),apron,Vector3(side*.075,.405,-.104),Vector3(0,0,side*8)))
	elif occupation in ["Teacher","Ranger","Shepherd"]:
		for side in [-1.0,1.0]:
			outfit.add_child(Mats.capsule(.07,.42,cloth,Vector3(side*.118,.22,.052),Vector3.ZERO,Vector3(1,1,1.28)))
		outfit.add_child(Mats.limb(Vector3(-.13,.47,-.10),Vector3(.15,.06,-.135),.016,leather))
		outfit.add_child(Mats.box(Vector3(.19,.20,.09),leather,Vector3(.19,.045,.01),Vector3(0,0,-9)))
	if occupation == "Teacher" or seed_value % 5 == 0:
		for side in [-1.0,1.0]:
			crown.add_child(Mats.torus(.031,.038,leather,Vector3(side*.057,.002,-.126),Vector3(90,0,0)))
		crown.add_child(Mats.limb(Vector3(-.021,.005,-.126),Vector3(.021,.005,-.126),.006,leather))

func _tailored_panel(material: Material) -> MeshInstance3D:
	# A flared cloth panel follows the chest and falls over the hips, with three
	# shallow folds; this avoids a solid box that would intersect moving legs.
	var mesh := SurfaceTool.new(); mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows: Array[Vector3] = []
	for row in range(3):
		var y: float=[.40,.14,-.16][row]
		var width: float=[.115,.15,.185][row]
		for col in range(5):
			rows.append(Vector3(lerpf(-width,width,col/4.0),y,-.12-(.012 if col%2==0 else 0.0)))
	for row in range(2):
		for col in range(4):
			var a:=row*5+col
			for index in [a,a+5,a+1,a+1,a+5,a+6]: mesh.add_vertex(rows[index])
	mesh.generate_normals()
	var panel := MeshInstance3D.new(); panel.mesh=mesh.commit(); panel.material_override=material
	return panel


## Conventions (model faces -Z): a POSITIVE rotation.x on a limb pivot swings the limb FORWARD.
## Knees only ever flex backward (a NEGATIVE knee rotation swings the shin back); elbows only ever
## flex forward (a POSITIVE elbow rotation lifts the forearm forward).
## mode: "idle", "walk", "run", "swim"; aim overlays the upper body on top of any ground mode.
func animate(mode: String, move_speed: float, delta: float, aim: bool = false, moving_input: float = 1.0, aim_pitch: float = 0.0) -> void:
	var swing := 0.0
	var bob := 0.0
	var cadence := 0.0
	match mode:
		"walk":
			swing = deg_to_rad(26.0); bob = 0.03; cadence = 1.9 * TAU
		"run":
			swing = deg_to_rad(40.0); bob = 0.05; cadence = 2.8 * TAU
	if mode == "swim":
		_t += delta
		# prone body, face turned up to breathe, crawl strokes sweeping under the body,
		# slow flutter kick; at rest he treads water instead of windmilling
		root.rotation.x = lerpf(root.rotation.x, deg_to_rad(-78.0), clampf(delta * 5.0, 0, 1))
		root.position.y = lerpf(root.position.y, 0.5, clampf(delta * 5.0, 0, 1))
		head.rotation.x = lerpf(head.rotation.x, 1.1, clampf(delta * 5.0, 0, 1))
		var active := clampf(moving_input, 0.0, 1.0)
		var st := _t * TAU * lerpf(0.5, 0.95, active)
		var amp := lerpf(0.45, 1.35, active)
		arm_l.rotation.x = deg_to_rad(95.0) + sin(st) * amp
		arm_r.rotation.x = deg_to_rad(95.0) + sin(st + PI) * amp
		arm_l.rotation.z = deg_to_rad(10.0)
		arm_r.rotation.z = deg_to_rad(-10.0)
		arm_l.get_node("Elbow").rotation.x = 0.5
		arm_r.get_node("Elbow").rotation.x = 0.5
		var kick := lerpf(0.12, 0.28, active)
		leg_l.rotation.x = sin(st * 2.0) * kick
		leg_r.rotation.x = -sin(st * 2.0) * kick
		leg_l.get_node("Knee").rotation.x = -0.25 - maxf(0.0, -sin(st * 2.0)) * 0.3
		leg_r.get_node("Knee").rotation.x = -0.25 - maxf(0.0, sin(st * 2.0)) * 0.3
		torso.rotation.y = 0.0
		return
	_t += delta * cadence / TAU
	var s := sin(_t * TAU) if cadence > 0.0 else 0.0
	var idle_t := Time.get_ticks_msec() * 0.001
	root.rotation.x = lerpf(root.rotation.x, 0.0, clampf(delta * 6.0, 0, 1))
	root.position.y = lerpf(root.position.y, HIP_H + absf(s) * bob, clampf(delta * 10.0, 0, 1))
	head.rotation.x = lerpf(head.rotation.x, 0.0, clampf(delta * 6.0, 0, 1))
	# legs: forward swing positive; the trailing leg's knee flexes back (positive) as it swings through
	leg_l.rotation.x = s * swing
	leg_r.rotation.x = -s * swing
	leg_l.get_node("Knee").rotation.x = -maxf(0.0, -s) * swing * 1.3
	leg_r.get_node("Knee").rotation.x = -maxf(0.0, s) * swing * 1.3
	if aim:
		# upper body only: right arm straight out along the look direction, left hand supporting
		arm_r.rotation.x = lerpf(arm_r.rotation.x, deg_to_rad(88.0) - aim_pitch, clampf(delta * 12.0, 0, 1))
		arm_r.rotation.z = deg_to_rad(-4.0)
		arm_r.get_node("Elbow").rotation.x = lerpf(arm_r.get_node("Elbow").rotation.x, 0.0, clampf(delta * 12.0, 0, 1))
		arm_l.rotation.x = lerpf(arm_l.rotation.x, deg_to_rad(70.0) - aim_pitch * 0.8, clampf(delta * 12.0, 0, 1))
		arm_l.rotation.z = deg_to_rad(22.0)
		arm_l.get_node("Elbow").rotation.x = lerpf(arm_l.get_node("Elbow").rotation.x, 0.9, clampf(delta * 12.0, 0, 1))
		torso.rotation.y = lerpf(torso.rotation.y, deg_to_rad(-14.0), clampf(delta * 8.0, 0, 1))
		torso.rotation.x = lerpf(torso.rotation.x, aim_pitch * 0.15, clampf(delta * 8.0, 0, 1))
	else:
		arm_l.rotation.x = -s * swing * 0.8
		arm_r.rotation.x = s * swing * 0.8
		arm_l.rotation.z = deg_to_rad(6.0)
		arm_r.rotation.z = deg_to_rad(-6.0)
		arm_l.get_node("Elbow").rotation.x = 0.35 + maxf(0.0, -s) * swing * 0.6
		arm_r.get_node("Elbow").rotation.x = 0.35 + maxf(0.0, s) * swing * 0.6
		torso.rotation.y = lerpf(torso.rotation.y, 0.0, clampf(delta * 6.0, 0, 1))
		torso.rotation.x = deg_to_rad(4.0 if mode != "idle" else 0.0) + (sin(idle_t * 1.6) * 0.02 if mode == "idle" else 0.0)
