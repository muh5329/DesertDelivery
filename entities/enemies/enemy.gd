class_name Enemy
extends CharacterBody3D
## A bandit or a pirate: the shared courier rig in their own clothes, with their own gun.
## Registered with the EntityManager under a stable id (`enemy.<camp>.<n>`); owned by the
## EncounterDirector, which spawns them with their camp and asks nothing of them but signals.
##
## AI (a small state machine, thinking at 10 Hz near the courier, 3 Hz further out):
##   IDLE        guard a post, walk a patrol round the camp, sit by the fire
##   SUSPICIOUS  something seen in the sight cone or a shot heard far off: turn, go and look
##   COMBAT      pick cover (camp cover points + sampled spots, a ray says what hides from the
##               courier), hide / peek and shoot / reload, flank now and then, fight in the open
##               if there is nothing to hide behind. Accuracy falls with distance, the
##               courier's speed and whether he is behind cover; the first shots of a peek
##               are the wildest
##   SEARCH      lost him: walk to where he was last seen, look round, give up after a while
##   FLEE        morale broken (friends down, badly hurt, alone): run, and vanish when clear
##   DEAD        falls (a ragdoll-lite tip over), drops ammo / coins through the director
## Sight lines and cover tests share one budget of rays per physics frame across all enemies.
## `set_simulation_tier`: FULL = physics + AI; REDUCED = no physics (kinematic, ground-snapped),
## slow AI; ABSTRACT / DORMANT = frozen.

enum State { IDLE, SUSPICIOUS, COMBAT, SEARCH, FLEE, DEAD }
enum Sub { MOVE_COVER, HIDE, PEEK, OPEN, FLANK }

signal died(enemy: Enemy, headshot: bool)
signal alerted(enemy: Enemy)
signal fled(enemy: Enemy)

const BODY_LAYER := 64
const HURTBOX_LAYER := 32
const SIGHT_MASK := 1 | 2
const RAYS_PER_FRAME := 10
const WALK := 1.7
const RUN := 4.4
const EYE := 1.55

static var _ray_frame := -1
static var _rays_used := 0
static var rays_total := 0        # for tests / the debug overlay

var ctx: Object                   # the EncounterDirector
var enemy_id: StringName
var camp_id: StringName
var kind: StringName = &"bandit"
var weapon: StringName = &"lever"
var role: StringName = &"guard"   # guard | patrol | sitter | lookout
var home := Vector3.ZERO
var facing := Vector3.FORWARD
var patrol: Array[Vector3] = []
var health: Health
var model: RiderModel
var state: int = State.IDLE
var sub: int = Sub.HIDE
var alertness := 0.0
var morale := 1.0
var mag := 7
var sees_target := false
var target_pos := Vector3.ZERO
var last_seen := -999.0
var shots := 0
var hits := 0
var killed_by_headshot := false

var _rng := RandomNumberGenerator.new()
var _stats: Dictionary
var _held: Node3D
var _revolver: Node3D
var _hurt: Array[Area3D] = []
var _tier := 0
var _think_t := 0.0
var _think_every := 0.1
var _t := 0.0                     # seconds alive (AI clock)
var _goal := Vector3.ZERO
var _speed := 0.0
var _has_goal := false
var _state_t := 0.0
var _sub_t := 0.0
var _fire_cd := 0.0
var _reload_t := 0.0
var _peek_shots := 0
var _cover: Variant = null
var _last_flank := 0.0
var _last_cover_check := 0.0
var _patrol_i := 0
var _wait_t := 0.0
var _progress_t := 0.0
var _progress_from := Vector3.ZERO
var _crouch := 0.0
var _flinch := 0.0
var _dead_t := -1.0
var _fall_dir := 1.0
var _mark: Label3D
var _look_yaw := 0.0
var _investigate := Vector3.ZERO
var _alone_hit := false
var _anim_accum := 0.0


func setup(p_ctx: Object, id: StringName, p_camp: StringName, p_kind: StringName, p_weapon: StringName, p_role: StringName, pos: Vector3, p_facing: Vector3, seed_value: int) -> void:
	ctx = p_ctx
	enemy_id = id
	camp_id = p_camp
	kind = p_kind
	weapon = p_weapon
	role = p_role
	home = pos
	facing = Vector3(p_facing.x, 0, p_facing.z).normalized() if p_facing.length_squared() > 0.01 else Vector3.FORWARD
	_rng.seed = seed_value
	_stats = EnemyWeapons.STATS[weapon]
	mag = int(_stats.mag)
	morale = 1.0 if kind == &"bandit" else 0.9
	name = String(id).replace(".", "_")


func _ready() -> void:
	collision_layer = BODY_LAYER
	collision_mask = 1 | 2 | 4 | BODY_LAYER
	floor_max_angle = deg_to_rad(50)
	floor_snap_length = 0.5
	var cs := CollisionShape3D.new()
	var sh := CapsuleShape3D.new(); sh.radius = 0.28; sh.height = 1.75
	cs.shape = sh; cs.position = Vector3(0, 0.875, 0)
	add_child(cs)
	health = Health.new(); health.name = "Health"
	health.max_health = 100.0 if kind == &"bandit" else 90.0
	add_child(health)
	model = RiderModel.new(); model.name = "Model"
	add_child(model)
	EnemyOutfit.dress(model, kind, _rng.seed)
	if EnemyWeapons.is_long(weapon):
		_held = EnemyWeapons.make(weapon)
		var slung := EnemyWeapons.make(weapon)
		model.attach_long_gun(_held, slung)
	else:
		_revolver = EnemyWeapons.make(weapon)
		model.hand_r.add_child(_revolver)
		_revolver.position = Vector3(0.0, -0.085, -0.02)
		_revolver.rotation_degrees = Vector3(-90, 0, 0)
		_revolver.visible = false
	_build_hurtboxes()
	_mark = Label3D.new()
	_mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_mark.font_size = 64; _mark.pixel_size = 0.004; _mark.outline_size = 10
	_mark.modulate = Color(1.0, 0.85, 0.3); _mark.position = Vector3(0, 2.25, 0)
	_mark.no_depth_test = true
	_mark.visible = false
	add_child(_mark)
	rotation.y = atan2(-facing.x, -facing.z)
	_look_yaw = rotation.y
	_think_t = _rng.randf() * 0.1     # spread the thinking over frames
	_goal = global_position
	health.died.connect(func(): _die())
	if role == &"patrol" and patrol.is_empty():
		for i in range(4):
			var a := TAU * i / 4.0 + _rng.randf() * 0.5
			patrol.append(home + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(7.0, 12.0))


func _build_hurtboxes() -> void:
	for spec in [[model.torso, &"body", Vector3(0, 0.36, 0), 0.21, 0.78], [model.root, &"body", Vector3(0, -0.38, 0), 0.19, 0.8], [model.head, &"head", Vector3(0, 0.05, 0), 0.155, 0.0]]:
		var a := Area3D.new()
		a.collision_layer = HURTBOX_LAYER
		a.collision_mask = 0
		a.monitoring = false
		a.set_meta("hurtbox", self)
		a.set_meta("zone", spec[1])
		a.set_meta("surface", &"cloth")
		var cs := CollisionShape3D.new()
		if spec[4] > 0.0:
			var c := CapsuleShape3D.new(); c.radius = spec[3]; c.height = spec[4]
			cs.shape = c
		else:
			var sp := SphereShape3D.new(); sp.radius = spec[3]
			cs.shape = sp
		cs.position = spec[2]
		a.add_child(cs)
		(spec[0] as Node3D).add_child(a)
		_hurt.append(a)


# ============================================================================== interface
func is_dead() -> bool:
	return state == State.DEAD


func is_alerted() -> bool:
	return state == State.COMBAT or state == State.SEARCH


## A bullet arrives. Returns true if it killed.
func take_hit(amount: float, headshot: bool, at: Vector3, from: Vector3, _source: StringName) -> bool:
	if state == State.DEAD: return false
	killed_by_headshot = headshot
	_fall_dir = 1.0 if (global_position - from).dot(-global_transform.basis.z) > 0.0 else -1.0
	health.damage(amount, from, _source)
	if state == State.DEAD: return true
	_flinch = 1.0
	_fire_cd = maxf(_fire_cd, 0.45)
	morale -= 0.12
	target_pos = from
	last_seen = _t
	if state != State.COMBAT: _enter_combat(from, true)
	elif sub == Sub.HIDE or sub == Sub.PEEK:
		_cover = null      # this cover is not working: move
		_pick_cover()
	return false


## Something happened nearby (a gunshot, an ally shouting): react as the distance deserves.
func hear(origin: Vector3, loudness: float, shooter: StringName) -> void:
	if state == State.DEAD or state == State.FLEE or shooter == enemy_id: return
	var d := global_position.distance_to(origin)
	if d > loudness: return
	if state == State.COMBAT: return
	if shooter == &"player" and d < loudness * 0.45:
		_enter_combat(origin, true)
	elif state == State.IDLE or state == State.SEARCH:
		_suspect(origin)


## An ally in the same camp has seen the courier.
func alert_to(pos: Vector3) -> void:
	if state == State.DEAD or state == State.FLEE: return
	if state != State.COMBAT: _enter_combat(pos, false)


func ally_down(pos: Vector3) -> void:
	if state == State.DEAD: return
	if global_position.distance_to(pos) < 35.0: morale -= 0.22
	if state != State.COMBAT and state != State.FLEE: _enter_combat(pos, false)


func set_simulation_tier(tier: int) -> void:
	_tier = tier
	_think_every = 0.1 if tier == EntityManager.SimulationTier.FULL else 0.3
	set_physics_process(tier <= EntityManager.SimulationTier.REDUCED or state == State.DEAD)
	if model: model.visible = tier <= EntityManager.SimulationTier.ABSTRACT


# ============================================================================== per frame
func _physics_process(delta: float) -> void:
	_t += delta
	if state == State.DEAD:
		_update_fall(delta)
		return
	if _fire_cd > 0.0: _fire_cd -= delta
	_flinch = move_toward(_flinch, 0.0, delta * 4.0)
	_think_t -= delta
	if _think_t <= 0.0:
		var dt := _think_every - _think_t
		_think_t = _think_every
		_think(dt)
	if _reload_t > 0.0:
		_reload_t -= delta
		if _reload_t <= 0.0: mag = int(_stats.mag)
	_move(delta)
	_animate(delta)


func _move(delta: float) -> void:
	var to := _goal - global_position
	to.y = 0.0
	var want := Vector3.ZERO
	if _has_goal and to.length() > 0.35:
		want = to.normalized() * _speed
	var full := _tier == EntityManager.SimulationTier.FULL
	if full:
		velocity.x = move_toward(velocity.x, want.x, 14.0 * delta)
		velocity.z = move_toward(velocity.z, want.z, 14.0 * delta)
		if is_on_floor(): velocity.y = -0.5
		else: velocity.y -= 22.0 * delta
		move_and_slide()
	else:
		# no physics far away: slide along the ground heights only
		velocity = want
		global_position += want * delta
		global_position.y = _ground(global_position)
	# never fall through a world whose collision has not streamed in yet
	var g := _ground(global_position)
	if global_position.y < g - 0.8:
		global_position.y = g + 0.05
		velocity.y = 0.0
	# stuck? step sideways
	if _has_goal and want.length() > 0.1:
		_progress_t += delta
		if _progress_t > 1.2:
			if global_position.distance_to(_progress_from) < 0.35:
				var side := Vector3(-want.z, 0, want.x).normalized() * (1.0 if _rng.randf() < 0.5 else -1.0)
				_goal = global_position + side * 2.2 + want.normalized() * 0.8
			_progress_t = 0.0
			_progress_from = global_position
	# facing: the target in a fight, else the way we walk
	var face_yaw := rotation.y
	if (state == State.COMBAT and sub != Sub.MOVE_COVER and sub != Sub.FLANK) or (state == State.SUSPICIOUS and want.length() < 0.1):
		var d := (target_pos if state == State.COMBAT else _investigate) - global_position
		if Vector2(d.x, d.z).length() > 0.1: face_yaw = atan2(-d.x, -d.z)
	elif want.length() > 0.2:
		face_yaw = atan2(-want.x, -want.z)
	elif state == State.SEARCH:
		face_yaw = _look_yaw
	rotation.y = lerp_angle(rotation.y, face_yaw, 1.0 - exp(-10.0 * delta))


func _ground(p: Vector3) -> float:
	var t: Terrain = ctx.terrain if ctx else null
	return t.height_at(p.x, p.z) if t else p.y


func _animate(delta: float) -> void:
	if _tier > EntityManager.SimulationTier.REDUCED: return
	_anim_accum += delta
	if _tier == EntityManager.SimulationTier.REDUCED and _anim_accum < 0.1: return
	var dt := _anim_accum
	_anim_accum = 0.0
	var spd := Vector2(velocity.x, velocity.z).length()
	var mode := "idle"
	if spd > 0.3: mode = "run" if spd > 3.0 else "walk"
	var fighting := state == State.COMBAT
	var aiming := state == State.COMBAT and sub != Sub.FLANK
	var want_crouch := 0.0
	if state == State.COMBAT and (sub == Sub.HIDE or (sub == Sub.OPEN and _reload_t > 0.0)) and spd < 0.5: want_crouch = 1.0
	if role == &"sitter" and state == State.IDLE: want_crouch = 1.0
	_crouch = move_toward(_crouch, want_crouch, dt * 4.0)
	model.crouch = _crouch
	model.flinch = _flinch
	model.gun_ads = 1.0 if (sub == Sub.PEEK or sub == Sub.OPEN) and state == State.COMBAT else 0.0
	var eye := global_position + Vector3(0, EYE * (1.0 - _crouch * 0.35), 0)
	var d := target_pos - eye
	var pitch := -atan2(d.y + 0.2, Vector2(d.x, d.z).length()) if state == State.COMBAT else 0.2
	if _revolver: _revolver.visible = fighting or aiming
	model.animate(mode, spd / 4.6, dt, aiming, 1.0, pitch)
	_mark.visible = (state == State.SUSPICIOUS or (state == State.COMBAT and _t - _state_t < 1.5)) and _tier == 0
	_mark.text = "?" if state == State.SUSPICIOUS else "!"


# ============================================================================== thinking
func _think(dt: float) -> void:
	var courier: Node3D = ctx.courier() if ctx else null
	if courier == null: return
	var cpos := courier.global_position
	var d := global_position.distance_to(cpos)
	var saw := sees_target
	sees_target = false
	# perception: sight cone in peace, all round in a fight
	var sight_range := 55.0
	if state == State.COMBAT or state == State.SEARCH: sight_range = 150.0
	elif state == State.SUSPICIOUS: sight_range = 80.0
	if role == &"lookout": sight_range *= 1.4
	if d < sight_range and not ctx.courier_hidden():
		var to := (cpos - global_position)
		to.y = 0.0
		var fwd := -global_transform.basis.z
		var in_cone := state == State.COMBAT or state == State.SEARCH or d < 4.0 or fwd.dot(to.normalized()) > cos(deg_to_rad(62.0))
		if in_cone:
			var see = _line_of_sight(cpos + Vector3(0, _chest(courier), 0))
			if see == null:
				sees_target = saw   # out of rays this frame: keep the last opinion
			else:
				sees_target = see
	if sees_target:
		target_pos = cpos + Vector3(0, _chest(courier), 0)
		last_seen = _t
	match state:
		State.IDLE: _think_idle(dt, d)
		State.SUSPICIOUS: _think_suspicious(dt, d)
		State.COMBAT: _think_combat(dt, d, courier)
		State.SEARCH: _think_search(dt)
		State.FLEE: _think_flee(dt, cpos)


func _chest(courier: Node3D) -> float:
	return 1.2 if courier is Player else 1.0


func _detect(dt: float, d: float, gain: float) -> void:
	if sees_target:
		var rate := lerpf(3.0, 0.45, clampf((d - 6.0) / 50.0, 0.0, 1.0)) * gain
		if ctx.courier_speed() > 6.0: rate *= 1.4
		alertness += rate * dt
		if alertness >= 1.0:
			_enter_combat(target_pos, true)
		elif alertness > 0.35 and state == State.IDLE:
			_suspect(target_pos)
	else:
		alertness = maxf(0.0, alertness - dt * 0.12)


func _think_idle(dt: float, d: float) -> void:
	_detect(dt, d, 1.0)
	if state != State.IDLE: return
	match role:
		&"patrol":
			if _wait_t > 0.0:
				_wait_t -= dt
				_has_goal = false
			else:
				_set_goal(patrol[_patrol_i], WALK)
				if global_position.distance_to(patrol[_patrol_i]) < 1.0:
					_patrol_i = (_patrol_i + 1) % patrol.size()
					_wait_t = _rng.randf_range(2.5, 6.0)
		_:
			if global_position.distance_to(home) > 1.5: _set_goal(home, WALK)
			else:
				_has_goal = false
				# guards look about now and then
				if _rng.randf() < dt * 0.25:
					var yaw := atan2(-facing.x, -facing.z) + _rng.randf_range(-0.9, 0.9)
					rotation.y = lerp_angle(rotation.y, yaw, 0.5)


func _suspect(pos: Vector3) -> void:
	if state == State.COMBAT or state == State.DEAD: return
	state = State.SUSPICIOUS
	_state_t = _t
	_investigate = pos
	alertness = maxf(alertness, 0.4)


func _think_suspicious(dt: float, d: float) -> void:
	_detect(dt, d, 1.8)
	if state != State.SUSPICIOUS: return
	var there := global_position.distance_to(_investigate)
	if _t - _state_t > 1.2 and there > 3.0 and role != &"lookout":
		_set_goal(_investigate, WALK)
	else:
		_has_goal = false
	if _t - _state_t > 10.0:
		state = State.IDLE
		_state_t = _t
		alertness = 0.2


func _enter_combat(pos: Vector3, shout: bool) -> void:
	if state == State.DEAD or state == State.FLEE: return
	var was := state
	state = State.COMBAT
	_state_t = _t
	alertness = 1.0
	target_pos = pos
	if was != State.COMBAT:
		last_seen = _t
		_cover = null
		sub = Sub.OPEN
		_sub_t = 0.0
		_pick_cover()
		if shout: alerted.emit(self)


func _think_combat(dt: float, d: float, courier: Node3D) -> void:
	# morale: flee when it breaks
	if morale < 0.08 or (morale < 0.3 and health.fraction() < 0.6) or (morale < 0.4 and ctx.allies_alive(camp_id) <= 1 and health.fraction() < 0.5):
		_start_flee()
		return
	if ctx.allies_alive(camp_id) <= 1 and not _alone_hit:
		_alone_hit = true
		morale -= 0.25
	if _t - last_seen > 8.0:
		state = State.SEARCH
		_state_t = _t
		_investigate = target_pos
		_release_cover()
		return
	_sub_t -= dt
	match sub:
		Sub.MOVE_COVER, Sub.FLANK:
			if _cover == null: sub = Sub.OPEN; return
			_set_goal(_cover, RUN)
			if global_position.distance_to(_cover) < 0.7 or _sub_t < -8.0:
				_has_goal = false
				sub = Sub.HIDE
				_sub_t = _rng.randf_range(0.6, 1.5)
		Sub.HIDE:
			_has_goal = false
			if mag <= 0 and _reload_t <= 0.0: _reload()
			# is this cover still any good? (he may have walked round it)
			if _t - _last_cover_check > 1.6 and _cover != null:
				_last_cover_check = _t
				var still = _covered(_cover, target_pos)
				if still == false:
					_cover = null
					_pick_cover()
					return
			if role != &"lookout" and _t - _last_flank > 11.0 and ctx.allies_alive(camp_id) >= 3 and _rng.randf() < 0.3 and d > 12.0:
				_last_flank = _t
				if _flank(courier): return
			if _sub_t <= 0.0 and _reload_t <= 0.0:
				sub = Sub.PEEK
				_sub_t = _rng.randf_range(1.4, 2.6)
				_peek_shots = 0
		Sub.PEEK:
			_has_goal = false
			_try_shoot(courier, d)
			if _sub_t <= 0.0 or mag <= 0:
				sub = Sub.HIDE
				_sub_t = _rng.randf_range(1.0, 2.3)
		Sub.OPEN:
			# nothing to hide behind: kneel and fight, keep looking for cover
			_has_goal = false
			if mag <= 0 and _reload_t <= 0.0: _reload()
			_try_shoot(courier, d)
			if _sub_t <= 0.0:
				_sub_t = 3.0
				if role != &"lookout": _pick_cover()


func _try_shoot(courier: Node3D, d: float) -> void:
	if not sees_target or _fire_cd > 0.0 or mag <= 0 or _reload_t > 0.0: return
	if d > float(_stats.range) * 1.6: return
	if absf(wrapf(rotation.y - atan2(-(target_pos.x - global_position.x), -(target_pos.z - global_position.z)), -PI, PI)) > 0.35: return
	_fire(courier, d)
	_fire_cd = float(_stats.rate) * _rng.randf_range(0.9, 1.5)


func _fire(courier: Node3D, d: float) -> void:
	mag -= 1
	shots += 1
	_peek_shots += 1
	var muzzle_node: Node3D = (_held if _held else _revolver).get_node("Muzzle")
	var mx := muzzle_node.global_transform
	var muzzle := mx.origin
	var chest := courier.global_position + Vector3(0, _chest(courier), 0)
	var p := hit_chance(d, ctx.courier_speed(), ctx.courier_in_cover(chest, muzzle), _peek_shots)
	var end: Vector3
	var fx: CombatFx = ctx.fx
	if _rng.randf() < p:
		hits += 1
		end = chest + Vector3(_rng.randf_range(-0.15, 0.15), _rng.randf_range(-0.25, 0.2), _rng.randf_range(-0.15, 0.15))
		ctx.hit_courier(float(_stats.damage), muzzle, enemy_id)
	else:
		# a miss: somewhere round him — into the ground at his feet or past his head
		var side := (chest - muzzle).cross(Vector3.UP).normalized()
		var off := side * _rng.randf_range(-2.2, 2.2) + Vector3(0, _rng.randf_range(-1.6, 1.4), 0)
		if off.length() < 0.6: off = off.normalized() * 0.8 if off.length() > 0.01 else side
		var aim := chest + off
		end = aim + (aim - muzzle).normalized() * 30.0
		var hit: Variant = _ray(muzzle, end, true)
		if hit is Dictionary and not hit.is_empty():
			end = hit.position
			fx.impact(hit.position, hit.normal, CombatFx.surface_of(hit.collider))
		else:
			var g := _ground(end)
			if end.y < g: end.y = g
		var head := courier.global_position + Vector3(0, 1.6, 0)
		var closest := Geometry3D.get_closest_point_to_segment(head, muzzle, end)
		if closest.distance_to(head) < 3.0: ctx.sounds.play(&"whiz", closest, -4.0)
	fx.muzzle(mx, 0.85)
	fx.tracer(muzzle, end, 0.8)
	ctx.sounds.play(_stats.sound, muzzle, -1.0, _rng.randf_range(0.95, 1.05))
	Events.shot_fired.emit(muzzle, enemy_id, 90.0)


## The chance a shot lands: the gun's accuracy, less with distance, with the courier's speed and
## when he is behind cover; the first rounds of a peek are hurried.
func hit_chance(d: float, target_speed: float, target_in_cover: bool, shot_in_peek: int) -> float:
	var reach := float(_stats.range)
	var dist_f := clampf(1.2 - d / reach, 0.12, 1.0)
	var speed_f := 1.0 / (1.0 + target_speed / 4.0)
	var cover_f := 0.4 if target_in_cover else 1.0
	var warm := clampf(0.55 + 0.2 * (shot_in_peek - 1), 0.55, 1.0)
	return clampf(float(_stats.accuracy) * dist_f * speed_f * cover_f * warm, 0.02, 0.85)


func _reload() -> void:
	_reload_t = float(_stats.reload)
	ctx.sounds.play(&"lever", global_position + Vector3(0, 1.2, 0), -8.0)


func _flank(courier: Node3D) -> bool:
	var cpos := courier.global_position
	var from := global_position - cpos
	from.y = 0.0
	var dist := clampf(from.length(), 14.0, 32.0)
	var a := deg_to_rad(_rng.randf_range(55.0, 80.0)) * (1.0 if _rng.randf() < 0.5 else -1.0)
	var dir := from.normalized().rotated(Vector3.UP, a)
	var p := cpos + dir * dist
	p.y = _ground(p)
	_release_cover()
	_cover = p
	sub = Sub.FLANK
	_sub_t = 0.0
	return true


func _pick_cover() -> bool:
	if role == &"lookout":
		_cover = global_position
		sub = Sub.HIDE
		_sub_t = _rng.randf_range(0.5, 1.2)
		return true
	var threat := target_pos
	var cands: Array = []
	for c: Vector3 in ctx.cover_points(camp_id):
		if c.distance_to(global_position) < 24.0 and not ctx.cover_taken(c, self): cands.append(c)
	for i in range(5):
		var a := _rng.randf() * TAU
		var p := global_position + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(3.0, 9.0)
		p.y = _ground(p)
		cands.append(p)
	var pref := 22.0 if weapon != &"revolver" else 14.0
	cands.sort_custom(func(a: Vector3, b: Vector3): return _cover_score(a, threat, pref) < _cover_score(b, threat, pref))
	var tested := 0
	for c: Vector3 in cands:
		if tested >= 3: break
		if c.distance_to(threat) < 6.0: continue
		tested += 1
		var ok = _covered(c, threat)
		if ok == null: return false
		if ok:
			_release_cover()
			_cover = c
			ctx.claim_cover(c, self)
			sub = Sub.MOVE_COVER
			_sub_t = 0.0
			return true
	_cover = null
	sub = Sub.OPEN
	_sub_t = 3.0
	return false


func _cover_score(p: Vector3, threat: Vector3, pref: float) -> float:
	return global_position.distance_to(p) * 0.7 + absf(p.distance_to(threat) - pref) * 0.35


## Does something solid stand between a kneeling man at `p` and `threat`? null = no rays left.
func _covered(p: Vector3, threat: Vector3) -> Variant:
	var from := p + Vector3(0, 0.95, 0)
	var hit = _ray(from, threat, false)
	if hit == null: return null
	return not hit.is_empty() and from.distance_to(hit.position) < 3.2


func _release_cover() -> void:
	if _cover != null and ctx: ctx.release_cover(self)
	_cover = null


func _think_search(dt: float) -> void:
	if sees_target:
		_enter_combat(target_pos, true)
		return
	var there := global_position.distance_to(_investigate)
	if there > 2.0 and _t - _state_t < 14.0:
		_set_goal(_investigate, WALK * 1.4)
	else:
		_has_goal = false
		_look_yaw += dt * 1.2
	if _t - _state_t > 20.0:
		state = State.IDLE
		_state_t = _t
		alertness = 0.3


func _start_flee() -> void:
	state = State.FLEE
	_state_t = _t
	_release_cover()
	_mark.visible = false


func _think_flee(_dt: float, cpos: Vector3) -> void:
	var away := global_position - cpos
	away.y = 0.0
	if away.length() < 0.1: away = Vector3.FORWARD
	var p := global_position + away.normalized().rotated(Vector3.UP, _rng.randf_range(-0.4, 0.4)) * 12.0
	_set_goal(p, RUN * 1.1)
	if (_t - _state_t > 6.0 and global_position.distance_to(cpos) > 60.0 and not sees_target) or _t - _state_t > 22.0:
		fled.emit(self)


func _set_goal(p: Vector3, spd: float) -> void:
	if not _has_goal or _goal.distance_to(p) > 0.5:
		_progress_t = 0.0
		_progress_from = global_position
	_goal = p
	_speed = spd
	_has_goal = true


## A ray on the shared budget. null = budget spent this frame; {} = clear; else the hit.
func _ray(from: Vector3, to: Vector3, force: bool) -> Variant:
	var f := Engine.get_physics_frames()
	if f != _ray_frame:
		_ray_frame = f
		_rays_used = 0
	if _rays_used >= RAYS_PER_FRAME and not force: return null
	_rays_used += 1
	rays_total += 1
	var q := PhysicsRayQueryParameters3D.create(from, to, SIGHT_MASK)
	q.exclude = [get_rid()]
	var courier: Node3D = ctx.courier() if ctx else null
	if courier is CollisionObject3D: q.exclude.append((courier as CollisionObject3D).get_rid())
	return get_world_3d().direct_space_state.intersect_ray(q)


func _line_of_sight(to: Vector3) -> Variant:
	var hit = _ray(global_position + Vector3(0, EYE * (1.0 - _crouch * 0.35), 0), to, false)
	if hit == null: return null
	return hit.is_empty()


# ============================================================================== dying
func _die() -> void:
	if state == State.DEAD: return
	state = State.DEAD
	_release_cover()
	collision_layer = 0
	collision_mask = 1
	for a in _hurt: a.collision_layer = 0
	_has_goal = false
	velocity = Vector3.ZERO
	_dead_t = 0.0
	_mark.visible = false
	set_physics_process(true)
	died.emit(self, killed_by_headshot)


func _update_fall(delta: float) -> void:
	if _dead_t < 0.0: return
	_dead_t += delta
	var k := clampf(_dead_t / 0.75, 0.0, 1.0)
	var e := k * k * (3.0 - 2.0 * k)
	# ragdoll-lite: the knees give, the body tips over the feet and settles on the ground
	model.crouch = minf(1.0, _dead_t * 3.0) * (1.0 - e * 0.6)
	model.rotation.x = -_fall_dir * e * 1.42
	model.position.y = e * 0.14
	model.position.z = _fall_dir * e * 0.25
	if k < 1.0:
		model.flinch = 1.0 - e
		model.gun_ads = 0.0
		model.animate("idle", 0.0, delta, _held != null, 1.0, 0.6)
		model.arm_l.rotation.z = lerpf(model.arm_l.rotation.z, 0.9, e)
		model.arm_r.rotation.z = lerpf(model.arm_r.rotation.z, -0.9, e)
	global_position.y = move_toward(global_position.y, _ground(global_position), delta * 3.0)
	if _dead_t > 1.0: set_physics_process(false)
