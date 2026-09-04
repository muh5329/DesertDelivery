class_name Player
extends CharacterBody3D
## On-foot controller for the boy: camera-relative walking/running, jumping, and swimming
## when he wades into the sea. Also carries the pistol once it has been found.

signal entered_water
signal left_water

@export var walk_speed := 4.2
@export var run_speed := 7.0
@export var swim_speed := 2.6
@export var jump_speed := 6.5
@export var gravity := 20.0

var model: RiderModel
var terrain: Terrain
var camera: Camera3D
var swimming := false
var aiming := false
var _intent: Controls.Intent = Controls.Intent.new()
var aim_pitch := 0.0          # camera pitch (rad, + down) so the pistol follows the crosshair
var _yaw := 0.0
var _move_dir := Vector3.ZERO
var _speed_now := 0.0
var _splash: CPUParticles3D

const WATER_SURFACE := Terrain.SEA_LEVEL
const SWIM_DEPTH := 0.6           # how far the capsule origin sits below the surface


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 2
	var cs := CollisionShape3D.new()
	var sh := CapsuleShape3D.new()
	sh.radius = 0.28
	sh.height = 1.8
	cs.shape = sh
	cs.position = Vector3(0, 0.9, 0)
	add_child(cs)
	floor_max_angle = deg_to_rad(55)
	floor_snap_length = 0.4
	model = RiderModel.new()
	model.name = "Model"
	add_child(model)
	_splash = CPUParticles3D.new()
	_splash.amount = 30
	_splash.lifetime = 0.9
	_splash.emitting = false
	_splash.position = Vector3(0, 0.7, -0.2)
	_splash.direction = Vector3(0, 1, 0)
	_splash.spread = 60
	_splash.initial_velocity_min = 1.0
	_splash.initial_velocity_max = 2.5
	_splash.gravity = Vector3(0, -6, 0)
	_splash.scale_amount_min = 0.4
	_splash.scale_amount_max = 0.9
	var sm := SphereMesh.new(); sm.radius = 0.12; sm.height = 0.24; sm.radial_segments = 6; sm.rings = 3
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.85, 0.95, 1.0, 0.7)
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.material = smat
	_splash.mesh = sm
	add_child(_splash)


func place(pos: Vector3, facing: Vector3) -> void:
	global_position = pos
	_yaw = atan2(-facing.x, -facing.z)
	rotation = Vector3(0, _yaw, 0)
	velocity = Vector3.ZERO


func flat_forward() -> Vector3:
	return Vector3(-sin(_yaw), 0, -cos(_yaw))


## The Rider hands the boy his ControlIntent once per physics tick, before he steps.
func apply(intent: Controls.Intent) -> void:
	_intent = intent


func _physics_process(delta: float) -> void:
	var inp := _intent.move.limit_length(1.0)
	var running := _intent.run
	# camera-relative movement basis
	var cam_yaw := camera.global_rotation.y if camera else _yaw
	var fwd := Vector3(-sin(cam_yaw), 0, -cos(cam_yaw))
	var right := Vector3(-fwd.z, 0, fwd.x)   # camera-right (fwd rotated -90° about Y)
	var wish := (fwd * inp.y + right * inp.x)
	var wish_len := wish.length()
	if wish_len > 1.0: wish /= wish_len

	# --- water check
	var seabed: float = terrain.height_at(global_position.x, global_position.z) if terrain else 0.0
	var in_water: bool
	if swimming:
		in_water = seabed < WATER_SURFACE - 0.45          # stays swimming until the bottom rises
	else:
		in_water = global_position.y < WATER_SURFACE - 0.15 and seabed < WATER_SURFACE - 0.75
	if in_water and not swimming:
		swimming = true
		_splash.emitting = true
		entered_water.emit()
	elif not in_water and swimming:
		swimming = false
		_splash.emitting = false
		left_water.emit()

	if swimming:
		var target_speed := swim_speed * wish_len
		_speed_now = move_toward(_speed_now, target_speed, 8.0 * delta)
		var v := wish * _speed_now
		# buoyancy: settle the hips just below the surface, can climb out on a shallow bottom
		var target_y := WATER_SURFACE - SWIM_DEPTH
		var ground := terrain.height_at(global_position.x, global_position.z) if terrain else -10.0
		target_y = maxf(target_y, ground + 0.05)
		v.y = (target_y - global_position.y) * 6.0
		velocity = v
		move_and_slide()
		if wish_len > 0.1:
			_yaw = lerp_angle(_yaw, atan2(-wish.x, -wish.z), clampf(8.0 * delta, 0, 1))
		rotation = Vector3(0, _yaw, 0)
		model.animate("swim", _speed_now, delta, false, wish_len)
		return

	var target_speed := (run_speed if running else walk_speed) * wish_len
	_speed_now = move_toward(_speed_now, target_speed, (18.0 if wish_len > 0.1 else 24.0) * delta)
	var vel := velocity
	var horiz := wish * _speed_now if wish_len > 0.05 else _move_dir * _speed_now
	if wish_len > 0.05:
		_move_dir = wish
	vel.x = horiz.x
	vel.z = horiz.z
	if is_on_floor():
		vel.y = -1.0
		if _intent.jump_pressed:
			vel.y = jump_speed
	else:
		vel.y -= gravity * delta
	velocity = vel
	move_and_slide()
	# facing: toward movement, or toward the camera direction when aiming
	if aiming:
		_yaw = lerp_angle(_yaw, cam_yaw, clampf(14.0 * delta, 0, 1))
	elif wish_len > 0.1:
		_yaw = lerp_angle(_yaw, atan2(-wish.x, -wish.z), clampf(12.0 * delta, 0, 1))
	rotation = Vector3(0, _yaw, 0)
	var mode := "idle"
	if _speed_now > 0.3:
		mode = "run" if running else "walk"
	model.animate(mode, _speed_now / walk_speed, delta, aiming, 1.0, aim_pitch)


func speed() -> float:
	return _speed_now
