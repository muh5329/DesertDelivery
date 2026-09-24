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
var hand_l: Node3D
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
		else: hand_l = hand
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
	if crouch > 0.001: _crouch_legs()
	if long_gun != null:
		_base_upper_body(mode, s, swing, idle_t, delta)
		gun_raise = move_toward(gun_raise, 1.0 if aim else 0.0, delta * (7.0 if aim else 3.5))
		_ads_blend = move_toward(_ads_blend, gun_ads, delta * 5.0)
		recoil = move_toward(recoil, 0.0, delta * 6.0)
		long_gun.visible = gun_raise > 0.02
		if slung_gun: slung_gun.visible = not long_gun.visible
		if _strap: _strap.visible = slung_gun != null and slung_gun.visible
		_last_mode = mode
		if long_gun.visible: _pose_long_gun(mode, aim_pitch)
	elif aim:
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
		_base_upper_body(mode, s, swing, idle_t, delta)


func _base_upper_body(mode: String, s: float, swing: float, idle_t: float, delta: float) -> void:
	arm_l.rotation = Vector3(-s * swing * 0.8, 0.0, deg_to_rad(6.0))
	arm_r.rotation = Vector3(s * swing * 0.8, 0.0, deg_to_rad(-6.0))
	arm_l.get_node("Elbow").rotation.x = 0.35 + maxf(0.0, -s) * swing * 0.6
	arm_r.get_node("Elbow").rotation.x = 0.35 + maxf(0.0, s) * swing * 0.6
	if long_gun != null:
		arm_l.get_node("Elbow/Hand").rotation = Vector3.ZERO
		arm_r.get_node("Elbow/Hand").rotation = Vector3.ZERO
		head.rotation.y = lerpf(head.rotation.y, 0.0, clampf(delta * 8.0, 0, 1))
		head.rotation.z = lerpf(head.rotation.z, 0.0, clampf(delta * 8.0, 0, 1))
		leg_l.rotation.z = 0.0
		leg_r.rotation.z = 0.0
	torso.rotation.y = lerpf(torso.rotation.y, 0.0, clampf(delta * 6.0, 0, 1))
	torso.rotation.x = deg_to_rad(4.0 if mode != "idle" else 0.0) + (sin(idle_t * 1.6) * 0.02 if mode == "idle" else 0.0)
	torso.rotation.x -= flinch * 0.35


## Kneeling behind cover: pelvis down, left foot planted forward, right knee on the ground.
## Applied before the upper body so a rifle pose follows the lowered torso.
var crouch := 0.0
## A hit reaction: the torso snaps back and recovers (the owner decays it).
var flinch := 0.0


func _crouch_legs() -> void:
	var c := clampf(crouch, 0.0, 1.0)
	root.position.y = lerpf(root.position.y, 0.50, c)
	leg_l.rotation.x = lerpf(leg_l.rotation.x, 1.30, c)
	leg_l.get_node("Knee").rotation.x = lerpf(leg_l.get_node("Knee").rotation.x, -1.30, c)
	leg_r.rotation.x = lerpf(leg_r.rotation.x, -0.10, c)
	leg_r.get_node("Knee").rotation.x = lerpf(leg_r.get_node("Knee").rotation.x, -1.50, c)


# ------------------------------------------------------------------------------ long guns
## A rifle carried two-handed (the courier's Garand, a bandit's lever rifle). `held` must carry
## the markers Butt, GripR and GripL: the butt plate centre and the two HAND PIVOT transforms
## (wrist position + hand orientation) in the rifle's own frame, -Z toward the muzzle. `slung`
## is the same rifle as it sits across the back (parented to the torso here).
##
## The owner steers the pose with plain fields; animate() blends everything:
##   animate(..., aim=true)  raise the rifle (gun_raise eases 0 -> 1); false lowers and slings it
##   gun_ads                 0 = hip / low ready, 1 = stock in the shoulder, cheek on the comb
##   recoil                  set 1.0 on a shot: the rifle kicks back and the muzzle climbs
##   sway                    (yaw, pitch) wobble in radians, e.g. from walking
var long_gun: Node3D
var slung_gun: Node3D
var gun_raise := 0.0
var gun_ads := 1.0
var recoil := 0.0
var sway := Vector2.ZERO
var _ads_blend := 1.0
var _strap: MeshInstance3D
## A temporary target for the left hand in the rifle's frame (reloading), blended in by weight.
var left_grip_override := Transform3D.IDENTITY
var left_grip_weight := 0.0
var _last_mode := "idle"

## Torso-local shoulder pocket (ADS) and hip tuck (hip fire) the butt plate goes into.
const SHOULDER_POCKET := Vector3(0.075, 0.600, -0.120)
const HIP_POCKET := Vector3(0.200, 0.130, 0.040)
const STANCE_YAW := -0.40        # blade the torso: left shoulder toward the target
const HEAD_ADS := Vector3(-0.42, 0.34, -0.26)   # chin down, face back to the target, cheek onto the comb
const POLE_R := Vector3(1.0, -0.75, 0.25)       # right elbow out to the side and down
const POLE_L := Vector3(-0.25, -1.0, 0.10)      # left elbow under the rifle
## Across the back, butt low on the right, muzzle up past the left shoulder, profile outward.
const SLUNG := Transform3D(Basis(Vector3(0.0, 0.0, -1.0), Vector3(0.92, 0.39, 0.0), Vector3(0.39, -0.92, 0.0)), Vector3(0.02, 0.36, 0.16))


func attach_long_gun(held: Node3D, slung: Node3D) -> void:
	long_gun = held
	slung_gun = slung
	if held:
		add_child(held)
		held.visible = false
	if slung:
		torso.add_child(slung)
		# the rifle's middle rides at the SLUNG origin in the small of the back
		slung.transform = SLUNG * Transform3D(Basis(), Vector3(0, 0.05, 0.55))
		_strap = _make_strap()
		torso.add_child(_strap)


## Bring the rifle up this instant (a snap shot from the sling), so the muzzle is where a shot
## leaves from before the next animate() blends anything.
func snap_long_gun(pitch: float) -> void:
	if long_gun == null: return
	gun_raise = 1.0
	_ads_blend = gun_ads
	long_gun.visible = true
	if slung_gun: slung_gun.visible = false
	if _strap: _strap.visible = false
	_pose_long_gun(_last_mode, pitch)


func _make_strap() -> MeshInstance3D:
	# the sling crossing the chest: from the left shoulder, over the front, down to the right hip
	var k := MeshKit.new()
	var pts := PackedVector3Array()
	for i in range(9):
		var t := float(i) / 8.0
		var a := Vector3(-0.13, 0.64, 0.02).lerp(Vector3(0.17, 0.10, -0.06), t)
		var bulge := sin(t * PI)
		pts.append(a + Vector3(0, 0, -0.105 - bulge * 0.035))
	k.tube(pts, 0.0028, 8, Vector2(1.0, 5.5), true, true, Vector3(0, 0, -1))
	var mi := MeshInstance3D.new()
	mi.mesh = k.commit(null, WeaponMats.leather())
	return mi


func _pose_long_gun(mode: String, pitch: float) -> void:
	var r := smoothstep(0.0, 1.0, gun_raise)
	var ads := _ads_blend
	# --- stance: blade the torso, lean into the rifle, cheek down onto the comb
	torso.rotation.y = lerpf(torso.rotation.y, STANCE_YAW * lerpf(0.75, 1.0, ads), r)
	torso.rotation.x = lerpf(torso.rotation.x, -0.07 + pitch * 0.30 - recoil * 0.06, r)
	var head_target := Vector3(lerpf(-0.05, HEAD_ADS.x, ads) - pitch * 0.55, -STANCE_YAW * 0.85, lerpf(0.0, HEAD_ADS.z, ads))
	head.rotation = head.rotation.lerp(head_target, r)
	if mode == "idle":
		leg_l.rotation.x = lerpf(leg_l.rotation.x, 0.16, r)
		leg_r.rotation.x = lerpf(leg_r.rotation.x, -0.12, r)
		leg_l.rotation.z = -0.05 * r
		leg_r.rotation.z = 0.07 * r
	# --- the rifle: butt in the pocket, bore along the aim (+ sway, + recoil climb)
	var body_basis := global_transform.basis.orthonormalized()
	var p_eff := lerpf(0.85, pitch - recoil * 0.10 + sway.y, r)
	var dir := body_basis * (Basis(Vector3.UP, sway.x) * Vector3(0, -sin(p_eff), -cos(p_eff)))
	var up := body_basis * Basis(Vector3(0, 0, 1), lerpf(-0.12, 0.0, ads)) * Vector3.UP
	var basis := Basis.looking_at(dir, up)
	var pocket := torso.global_transform * HIP_POCKET.lerp(SHOULDER_POCKET, ads)
	var butt: Vector3 = long_gun.get_node("Butt").position
	var origin := pocket - basis * butt + basis * Vector3(0, 0, recoil * 0.035)
	long_gun.global_transform = Transform3D(basis, origin)
	# --- hands onto the rifle
	_reach(arm_r, long_gun.get_node("GripR").global_transform, torso.global_basis * POLE_R, r)
	var grip_l: Transform3D = long_gun.get_node("GripL").global_transform
	if left_grip_weight > 0.0:
		grip_l = grip_l.interpolate_with(long_gun.global_transform * left_grip_override, clampf(left_grip_weight, 0.0, 1.0))
	_reach(arm_l, grip_l, torso.global_basis * POLE_L, r)


## Two-bone IK: the upper arm and forearm (elbow hinged on its local X, flexing forward) bring
## the palm onto `grip.origin`, the elbow toward `pole`. The hand stays in line with the forearm
## (the glove's cuff runs up the wrist) and rolls so the palm faces `grip`'s -Z. Two passes: the
## first finds the forearm's direction, the second backs the wrist off along it so the palm, not
## the wrist, lands on the grip. Blended over whatever pose the arm already has by `w`.
func _reach(arm: Node3D, grip: Transform3D, pole: Vector3, w: float) -> void:
	var elbow: Node3D = arm.get_node("Elbow")
	var hand: Node3D = elbow.get_node("Hand")
	var s := arm.global_position
	var a := elbow.global_position.distance_to(s)
	var b := hand.global_position.distance_to(elbow.global_position)
	var palm_dir := -grip.basis.z.normalized()
	var sol := _two_bone(s, grip.origin - palm_dir * 0.024, a, b, pole)
	var f: Vector3 = sol[1]
	sol = _two_bone(s, grip.origin - palm_dir * 0.024 - f * 0.035, a, b, pole)
	var e: Vector3 = sol[0]
	f = sol[1]
	var u := (e - s).normalized()
	var zc := f - u * f.dot(u)
	var z_axis := -zc.normalized() if zc.length_squared() > 1e-10 else -(pole - u * pole.dot(u)).normalized()
	var y_axis := -u
	var gb := Basis(y_axis.cross(z_axis), y_axis, z_axis)
	var parent_basis: Basis = (arm.get_parent() as Node3D).global_basis.orthonormalized()
	var local_q := Quaternion((parent_basis.inverse() * gb).orthonormalized())
	arm.quaternion = arm.quaternion.slerp(local_q, w)
	elbow.rotation = Vector3(lerpf(elbow.rotation.x, acos(clampf(f.dot(u), -1.0, 1.0)), w), 0.0, 0.0)
	# the hand: +Y back up the forearm, palm (-Z) turned toward the grip surface
	var hy := -f
	var hz := -(palm_dir - hy * palm_dir.dot(hy))
	if hz.length_squared() < 1e-8: hz = z_axis
	hz = hz.normalized()
	var hb := Basis(hy.cross(hz), hy, hz)
	var hq := Quaternion((elbow.global_basis.orthonormalized().inverse() * hb).orthonormalized())
	hand.quaternion = Quaternion.IDENTITY.slerp(hq, w)


## Shoulder at `s`, wrist target `t`, bone lengths a, b, elbow toward `pole`:
## returns [elbow position, forearm direction (elbow -> wrist)].
static func _two_bone(s: Vector3, t: Vector3, a: float, b: float, pole: Vector3) -> Array:
	var to := t - s
	var dir := to.normalized() if to.length_squared() > 1e-10 else Vector3.FORWARD
	var d := clampf(to.length(), absf(a - b) + 0.002, a + b - 0.002)
	var cos_a := clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
	var sin_a := sqrt(1.0 - cos_a * cos_a)
	var pp := pole - dir * pole.dot(dir)
	if pp.length_squared() < 1e-8: pp = dir.cross(Vector3.RIGHT)
	pp = pp.normalized()
	var e := s + dir * (a * cos_a) + pp * (a * sin_a)
	return [e, (s + dir * d - e).normalized()]
