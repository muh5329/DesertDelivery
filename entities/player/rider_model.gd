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

const HIP_H := 0.82
const THIGH := 0.42
const SHIN := 0.40


const MODEL = preload("res://assets/models/courier_character.glb")

func _ready() -> void:
	var model: Node3D = MODEL.instantiate()
	add_child(model)
	root = model.find_child("Root", true, false)
	torso = model.find_child("Torso", true, false)
	head = model.find_child("Head", true, false)
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


func pose_riding() -> void:
	root.position = Vector3(0, 1.10, 0.25)
	torso.rotation.x = -0.28
	for side in [-1.0, 1.0]:
		var leg := leg_l if side < 0 else leg_r
		leg.rotation = Vector3(1.20, side * -0.25, side * 0.30)
		leg.get_node("Knee").rotation.x = -1.53
		var arm := arm_l if side < 0 else arm_r
		arm.rotation = Vector3(0.85, 0, side * 0.13)
		arm.scale.y = 1.35
		arm.get_node("Elbow").rotation.x = 0.35


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
				node.set_surface_override_material(index, mat)


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
