class_name Player
extends CharacterBody3D
## On-foot controller for the boy: camera-relative walking/running, jumping, and swimming
## when he wades into the sea. His M1 Garand rides on the model (slung, or in his hands).

signal entered_water
signal left_water

# Movement defaults and stamina/dodge rules ported from Red Sea Baron:
# scripts/player/{movement_config,player_controller}.gd. Input still enters
# through Controls.Intent so vehicles, tests and AI share the courier seam.
@export var walk_speed := 4.6
@export var run_speed := 8.5
@export var swim_speed := 2.6
@export var jump_speed := 8.4
@export var gravity := 24.0
@export var ground_acceleration := 30.0
@export var ground_braking := 30.0
@export var air_acceleration := 9.0
@export var coyote_time := 0.12
@export var jump_buffer_time := 0.14
@export var fall_gravity_scale := 1.4
@export var released_jump_gravity_scale := 2.4
@export var terminal_speed := 38.0
@export var turn_response := 16.0
@export var dodge_speed := 12.0
@export var dodge_duration := 0.48
@export var dodge_cost := 27.0
@export var jump_cost := 12.0
@export var sprint_drain := 18.0
@export var stamina_regen := 26.0
@export var stamina_max := 100.0
signal jumped
signal dodged
var stamina := 100.0
var speed_multiplier := 1.0
var surface_speed_multiplier := 1.0
var dodge_remaining := 0.0
var dodge_direction := Vector3.FORWARD
var regen_delay := 0.0
var sprint_exhausted := false
var movement_distance := 0.0
var jumps := 0
var rolls := 0

enum Motion { IDLE, WALK, RUN, RISE, FALL, SWIM, DODGE }
signal motion_changed(previous: int, current: int)
var motion: int = Motion.IDLE
var _coyote_left := 0.0
var _jump_buffer_left := 0.0
var _floor_valid := false
var _jump_active := false
var _air_pose_blend := 0.0
var _camera_hidden := false
var _dodge_pose_active := false

var model: RiderModel
var terrain: Terrain
var camera: Camera3D
var swimming := false
var water_surface := WATER_SURFACE       ## the water level over the courier (sea, lake or river)
var aiming := false
var _intent: Controls.Intent = Controls.Intent.new()
var aim_pitch := 0.0          # camera pitch (rad, + down) so the rifle follows the crosshair
var _yaw := 0.0
var _move_dir := Vector3.ZERO
var _speed_now := 0.0
var _splash: CPUParticles3D

const WATER_SURFACE := Terrain.SEA_LEVEL     # the sea; inland water asks the terrain (water_level_at)
const SWIM_DEPTH := 0.6           # how far the capsule origin sits below the surface


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 2 | 16 | 64      # 64: bandits and pirates (Enemy.BODY_LAYER)
	var cs := CollisionShape3D.new()
	var sh := CapsuleShape3D.new()
	sh.radius = 0.28
	sh.height = 1.8
	cs.shape = sh
	cs.position = Vector3(0, 0.9, 0)
	add_child(cs)
	floor_max_angle = deg_to_rad(48)
	floor_snap_length = 0.45
	floor_constant_speed = true
	floor_stop_on_slope = true
	wall_min_slide_angle = deg_to_rad(15)
	safe_margin = .025
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
	_speed_now = 0.0
	_move_dir = Vector3.ZERO
	_coyote_left = 0.0
	_jump_buffer_left = 0.0
	_floor_valid = false
	_jump_active = false
	_air_pose_blend = 0.0
	dodge_remaining = 0.0
	_dodge_pose_active = false
	if model:
		model.root.rotation.x = 0.0
		model.root.position = Vector3(0, RiderModel.HIP_H, 0)
	set_camera_distance(10.0)
	aiming = false
	aim_pitch = 0.0
	reset_physics_interpolation()
	_intent = Controls.Intent.new()
	if swimming:
		swimming = false
		if _splash: _splash.emitting = false
		left_water.emit()
	_set_motion(Motion.IDLE)


func _set_motion(next: int) -> void:
	if next == motion: return
	var previous := motion
	motion = next
	motion_changed.emit(previous, motion)


func flat_forward() -> Vector3:
	return Vector3(-sin(_yaw), 0, -cos(_yaw))


## The Rider hands the boy his ControlIntent once per physics tick, before he steps.
func apply(intent: Controls.Intent) -> void:
	_intent = intent


## Source set_controls(false) semantics for modal ownership. The caller owns
## process suspension; queued edges and a half-finished roll must not resume.
func hold_controls() -> void:
	_intent = Controls.Intent.new()
	_jump_buffer_left = 0.0
	dodge_remaining = 0.0
	velocity.x = 0.0
	velocity.z = 0.0
	_speed_now = 0.0
	_move_dir = Vector3.ZERO
	if _dodge_pose_active and model:
		model.root.rotation.x = 0.0
		model.root.position = Vector3(0, RiderModel.HIP_H, 0)
		model.animate("idle", 0.0, 0.0)
	_dodge_pose_active = false
	if not swimming and is_on_floor():
		velocity.y = 0.0
		_jump_active = false
		_coyote_left = 0.0
		_set_motion(Motion.IDLE)


func spend_stamina(amount: float) -> bool:
	if stamina < amount: return false
	stamina -= amount
	regen_delay = 0.65
	return true


func _physics_process(delta: float) -> void:
	if _dodge_pose_active:
		model.root.rotation.x = 0.0
		model.root.position = Vector3(0, RiderModel.HIP_H, 0)
		_dodge_pose_active = false
	var before := global_position
	regen_delay = maxf(0.0, regen_delay - delta)
	if not _intent.run and stamina > 20.0: sprint_exhausted = false
	var inp := _intent.move.limit_length(1.0)
	var running := false
	_jump_buffer_left = maxf(0.0, _jump_buffer_left - delta)
	if _intent.pressed(Controls.JUMP):
		_jump_buffer_left = jump_buffer_time
		_intent.commands.erase(Controls.JUMP)
	# camera-relative movement basis
	var cam_yaw: float = camera.control_yaw() if camera is ChaseCamera else (camera.global_rotation.y if camera else _yaw)
	var fwd := Vector3(-sin(cam_yaw), 0, -cos(cam_yaw))
	var right := Vector3(-fwd.z, 0, fwd.x)   # camera-right (fwd rotated -90° about Y)
	var wish := (fwd * inp.y + right * inp.x)
	var wish_len := wish.length()
	if wish_len > 1.0: wish /= wish_len
	wish_len = minf(wish_len, 1.0)
	var direction := wish.normalized() if wish_len > 0.001 else Vector3.ZERO

	# --- water check
	var seabed: float = terrain.height_at(global_position.x, global_position.z) if terrain else 0.0
	# the sea, or the mountain lake / a river over this spot (M-5: they were walked on like dry land)
	var surface: float = terrain.water_level_at(global_position.x, global_position.z) if terrain else WATER_SURFACE
	water_surface = surface
	var in_water: bool
	if swimming:
		in_water = terrain != null and seabed < surface - 0.45          # stays swimming until the bottom rises
	else:
		in_water = terrain != null and global_position.y < surface - 0.15 and seabed < surface - 0.75
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
		var v := Vector3(velocity.x, 0.0, velocity.z).move_toward(direction * target_speed, 8.0 * delta)
		_speed_now = Vector2(v.x, v.z).length()
		_coyote_left = 0.0
		_jump_buffer_left = 0.0
		_jump_active = false
		_floor_valid = false
		dodge_remaining = 0.0
		if regen_delay <= 0.0: stamina = minf(stamina_max, stamina + stamina_regen * delta)
		_intent.commands.erase(Controls.DODGE)
		_set_motion(Motion.SWIM)
		# buoyancy: settle the hips just below the surface, can climb out on a shallow bottom
		var target_y := surface - SWIM_DEPTH
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

	var grounded := _floor_valid and is_on_floor() and not _jump_active
	if _intent.pressed(Controls.DODGE):
		_intent.commands.erase(Controls.DODGE)
		if grounded and dodge_remaining <= 0.0 and spend_stamina(dodge_cost):
			dodge_remaining = dodge_duration
			dodge_direction = direction if wish_len > 0.1 else flat_forward()
			_yaw = atan2(-dodge_direction.x, -dodge_direction.z)
			rolls += 1
			dodged.emit()
	running = _intent.run and not aiming and wish_len > .1 and grounded and dodge_remaining <= 0.0 and not sprint_exhausted
	if running:
		stamina = maxf(0.0, stamina - sprint_drain * delta)
		regen_delay = 0.6
		if stamina <= 0.0: sprint_exhausted = true
	elif dodge_remaining <= 0.0 and regen_delay <= 0.0:
		stamina = minf(stamina_max, stamina + stamina_regen * delta)
	var dodging := dodge_remaining > 0.0
	var target_speed := (run_speed if running else walk_speed) * wish_len * speed_multiplier * surface_speed_multiplier
	if aiming: target_speed *= 0.7
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if grounded:
		horizontal = horizontal.move_toward(direction * target_speed, (ground_acceleration if wish_len > 0.05 else ground_braking) * delta)
		_coyote_left = coyote_time
		velocity.y = 0.0
		_jump_active = false
	else:
		# Releasing the stick in the air preserves a jump's momentum; input still
		# provides bounded steering, rather than stopping the character in midair.
		if wish_len > .05: horizontal = horizontal.move_toward(direction * target_speed, air_acceleration * delta)
		_coyote_left = maxf(0.0, _coyote_left - delta)
		var gravity_scale := fall_gravity_scale if velocity.y < 0.0 else 1.0
		if _jump_active and velocity.y > 0.0 and not _intent.jump_held:
			gravity_scale = released_jump_gravity_scale
		velocity.y = maxf(velocity.y - gravity * gravity_scale * delta, -terminal_speed)
	if dodging:
		# Integrate the last partial dodge tick exactly, independent of tick rate.
		horizontal = dodge_direction * dodge_speed * minf(1.0, dodge_remaining / delta)
		dodge_remaining = maxf(0.0, dodge_remaining - delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if not dodging and _jump_buffer_left > 0.0 and (grounded or _coyote_left > 0.0):
		_launch_jump()
	move_and_slide()
	_floor_valid = true
	if is_on_floor() and velocity.y <= 0.0: _jump_active = false
	# Consume a buffered press on the landing tick, with no extra grounded tick.
	if not dodging and is_on_floor() and not _jump_active and _jump_buffer_left > 0.0:
		_launch_jump()
	if is_on_ceiling() and velocity.y <= 0.0: _jump_active = false
	_speed_now = Vector2(velocity.x, velocity.z).length()
	if dodging:
		_set_motion(Motion.DODGE)
	elif _jump_active or not is_on_floor():
		_set_motion(Motion.RISE if velocity.y > 0.0 else Motion.FALL)
	else:
		_set_motion((Motion.RUN if running else Motion.WALK) if _speed_now > 0.3 else Motion.IDLE)
	# Exponential turning has the same response at different physics rates.
	if dodging:
		_yaw = atan2(-dodge_direction.x, -dodge_direction.z)
	elif aiming:
		_yaw = lerp_angle(_yaw, cam_yaw, 1.0 - exp(-24.0 * delta))
	elif wish_len > 0.1:
		_yaw = lerp_angle(_yaw, atan2(-wish.x, -wish.z), 1.0 - exp(-turn_response * delta))
	rotation = Vector3(0, _yaw, 0)
	var mode := "idle"
	if motion == Motion.WALK or motion == Motion.RUN:
		mode = "run" if motion == Motion.RUN else "walk"
	model.animate(mode, _speed_now / walk_speed, delta, aiming, wish_len, aim_pitch)
	_animate_air_pose(delta)
	if dodging:
		# The source's forward roll is applied around the courier pelvis pivot,
		# retaining the imported character and its continuous skin/attachments.
		for leg in [model.leg_l, model.leg_r]:
			leg.rotation.x = .8
			leg.get_node("Knee").rotation.x = -1.3
		_dodge_pose_active = true
		var roll_angle := -TAU * (1.0 - dodge_remaining / dodge_duration)
		model.root.rotation.x = roll_angle
		# Source visual rotates about .94m, above this courier's .82m pelvis.
		# Preserve that roll center so the inverted head clears the foot plane.
		model.root.position = Vector3.UP * .94 + Basis(Vector3.RIGHT, roll_angle) * Vector3.UP * (RiderModel.HIP_H - .94)
	movement_distance += Vector2(global_position.x - before.x, global_position.z - before.z).length()


func _animate_air_pose(delta: float) -> void:
	var in_air := motion == Motion.RISE or motion == Motion.FALL
	_air_pose_blend = lerpf(_air_pose_blend, 1.0 if in_air else 0.0, 1.0 - exp(-18.0 * delta))
	if _air_pose_blend < .001:
		model.leg_l.rotation.z = 0.0
		model.leg_r.rotation.z = 0.0
		return
	# Small limb tucks communicate lift and descent without changing collision
	# height or running the grounded stride cycle while suspended in the air.
	var tuck := 1.0 if motion == Motion.RISE else clampf(1.0 + velocity.y / 10.0, .25, 1.0)
	for side in [-1.0, 1.0]:
		var leg := model.leg_l if side < 0.0 else model.leg_r
		# Keep a readable asymmetric tuck through the apex, then extend for landing.
		var lift := (.68 if side < 0.0 else .34) * tuck
		leg.rotation.x = lerpf(leg.rotation.x, lift, _air_pose_blend)
		leg.rotation.z = side * .12 * _air_pose_blend
		var knee: Node3D = leg.get_node("Knee")
		knee.rotation.x = lerpf(knee.rotation.x, (-1.05 if side < 0.0 else -.65) * tuck, _air_pose_blend)
		if not aiming:
			var arm := model.arm_l if side < 0.0 else model.arm_r
			arm.rotation.x = lerpf(arm.rotation.x, -.24 * tuck, _air_pose_blend)
			arm.rotation.z = lerpf(arm.rotation.z, side * .34, _air_pose_blend)


func set_camera_distance(distance: float) -> void:
	# Alpha blending reveals layered skin/clothes through one another. Hide the
	# complete visual only when very close, with hysteresis to avoid flickering.
	if not _camera_hidden and distance < 1.10:
		_camera_hidden = true
	elif _camera_hidden and distance > 1.25:
		_camera_hidden = false
	if model: model.visible = not _camera_hidden


func _launch_jump() -> void:
	if not spend_stamina(jump_cost): return
	jumps += 1
	jumped.emit()
	velocity.y = jump_speed
	_jump_buffer_left = 0.0
	_coyote_left = 0.0
	_jump_active = true


func camera_speed() -> float:
	return speed()


func camera_top_speed() -> float:
	return run_speed


func speed() -> float:
	return _speed_now
