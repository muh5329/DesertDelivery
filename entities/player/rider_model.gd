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


func _ready() -> void:
	var skin := Mats.solid(SKIN, 0.8)
	var hair := Mats.solid(HAIR, 0.75)
	var shirt := Mats.solid(SHIRT, 0.85)
	var scarf := Mats.solid(SCARF, 0.8)
	var trouser := Mats.solid(TROUSER, 0.9)
	var boot := Mats.solid(BOOT, 0.8)
	var strap := Mats.solid(STRAP, 0.9)

	root = Node3D.new()
	root.name = "Root"
	root.position = Vector3(0, HIP_H, 0)
	add_child(root)
	# pelvis
	root.add_child(Mats.sphere(0.15, trouser, Vector3(0, 0.02, 0), Vector3(1.2, 0.7, 1.0)))
	# legs
	leg_l = _leg(root, -0.09, trouser, boot)
	leg_r = _leg(root, 0.09, trouser, boot)
	# torso
	torso = Node3D.new()
	torso.position = Vector3(0, 0.08, 0)
	root.add_child(torso)
	torso.add_child(Mats.capsule(0.15, 0.40, shirt, Vector3(0, 0.30, 0), Vector3.ZERO, Vector3(1.15, 1.0, 0.75)))
	for sx in [-0.07, 0.07]:
		torso.add_child(Mats.box(Vector3(0.035, 0.42, 0.012), strap, Vector3(sx, 0.30, -0.125)))
		# Y-back: two straps meeting between the shoulder blades
		torso.add_child(Mats.box(Vector3(0.035, 0.26, 0.012), strap, Vector3(sx * 0.5, 0.40, 0.125), Vector3(0, 0, sx * -2.4)))
	torso.add_child(Mats.box(Vector3(0.035, 0.22, 0.012), strap, Vector3(0, 0.16, 0.125)))
	torso.add_child(Mats.cylinder(0.05, 0.1, skin, Vector3(0, 0.56, 0)))
	torso.add_child(Mats.sphere(0.09, scarf, Vector3(0, 0.54, 0), Vector3(1.4, 0.55, 1.2)))
	# head
	head = Node3D.new()
	head.position = Vector3(0, 0.74, 0)
	torso.add_child(head)
	head.add_child(Mats.sphere(0.155, skin, Vector3.ZERO, Vector3(0.95, 1.05, 0.95)))
	head.add_child(Mats.sphere(0.17, hair, Vector3(0, 0.055, 0.02), Vector3(1.0, 0.85, 1.0)))
	head.add_child(Mats.sphere(0.09, hair, Vector3(0.0, 0.15, -0.02), Vector3(1.4, 0.7, 1.2)))
	head.add_child(Mats.sphere(0.06, hair, Vector3(0.09, 0.14, -0.05), Vector3(1.0, 1.3, 1.0)))
	head.add_child(Mats.sphere(0.06, hair, Vector3(-0.08, 0.15, -0.03), Vector3(1.0, 1.3, 1.0)))
	var eye := Mats.solid(Color(0.25, 0.16, 0.1), 0.4)
	head.add_child(Mats.sphere(0.018, eye, Vector3(0.05, 0.01, -0.14)))
	head.add_child(Mats.sphere(0.018, eye, Vector3(-0.05, 0.01, -0.14)))
	# arms
	arm_l = _arm(torso, -0.20, shirt, skin, boot)
	arm_r = _arm(torso, 0.20, shirt, skin, boot)


func _leg(parent: Node3D, sx: float, trouser: Material, boot: Material) -> Node3D:
	var piv := Node3D.new()
	piv.position = Vector3(sx, 0, 0)
	parent.add_child(piv)
	# wide breeches on the thigh, gathered just below the knee, then a sock/shin and a boot
	piv.add_child(Mats.limb(Vector3.ZERO, Vector3(0, -THIGH, 0), 0.10, trouser))
	var knee := Node3D.new()
	knee.name = "Knee"
	knee.position = Vector3(0, -THIGH, 0)
	piv.add_child(knee)
	knee.add_child(Mats.limb(Vector3.ZERO, Vector3(0, -0.12, 0), 0.095, trouser))
	knee.add_child(Mats.limb(Vector3(0, -0.10, 0), Vector3(0, -SHIN, 0), 0.055, Mats.solid(Color(0.62, 0.52, 0.32), 0.9)))
	knee.add_child(Mats.box(Vector3(0.13, 0.11, 0.27), boot, Vector3(0, -SHIN - 0.02, -0.04)))
	return piv


func _arm(parent: Node3D, sx: float, shirt: Material, skin: Material, glove: Material) -> Node3D:
	var piv := Node3D.new()
	piv.position = Vector3(sx, 0.50, 0)
	parent.add_child(piv)
	piv.add_child(Mats.sphere(0.07, shirt, Vector3.ZERO))
	piv.add_child(Mats.limb(Vector3.ZERO, Vector3(0, -0.18, 0), 0.058, shirt))         # rolled sleeve
	piv.add_child(Mats.cylinder(0.066, 0.06, shirt, Vector3(0, -0.19, 0), Vector3.ZERO, 10))  # sleeve roll
	piv.add_child(Mats.limb(Vector3(0, -0.2, 0), Vector3(0, -0.26, 0), 0.045, skin))
	var elbow := Node3D.new()
	elbow.name = "Elbow"
	elbow.position = Vector3(0, -0.26, 0)
	piv.add_child(elbow)
	elbow.add_child(Mats.limb(Vector3.ZERO, Vector3(0, -0.24, 0), 0.045, skin))
	var hand := Node3D.new()
	hand.name = "Hand"
	hand.position = Vector3(0, -0.27, 0)
	elbow.add_child(hand)
	hand.add_child(Mats.sphere(0.055, glove, Vector3.ZERO, Vector3(1, 0.8, 1.2)))
	if sx > 0.0:
		hand_r = hand
	return piv


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
