class_name PlayerVitals
extends Node
## The courier's health and what happens when it runs out. A Health component on the Player
## body (100 hp, regenerating 14 hp/s after 5 s without a hit); hits arrive from the bad guys
## through `hit()`, which knows the Rider's rule for vehicles:
##   * on foot / swimming: full damage
##   * riding or driving: 60 % (the machine takes some of it) — and fast riders are hard to hit
##     anyway, because enemy accuracy falls with the target's speed; flying: 30 %
## Down: the controls are held, the screen fades to black, a small coin penalty (10 %, at most
## 25) is paid and he wakes on the nearest road to the last safe spot (sampled every 2 s when no
## fight is near), with 3 s of invulnerability shown as a flicker.
##
##   hit(amount, from, source) -> float     damage actually taken
##   is_down() / respawn_now() / fade (0..1, the HUD's black) / last_safe / deaths

signal went_down
signal respawned(position: Vector3)

const RIDING_SCALE := 0.6
const FLYING_SCALE := 0.3
const PENALTY_FRACTION := 0.1
const PENALTY_MAX := 25
const INVULNERABLE := 3.0
const FADE_OUT := 1.0
const RESPAWN_AT := 1.5
const FADE_IN := 0.8

var health: Health
var rider: Rider
var player: Player
var world: WorldManager
var delivery: DeliverySystem
var director: Node          # EncounterDirector: is a fight near? (for the safe spot)
var fade := 0.0
var last_safe := Vector3.ZERO
var deaths := 0
var last_penalty := 0
var last_hit_from := Vector3.ZERO
var last_hit_time := -99.0
var _down := false
var _down_t := 0.0
var _safe_t := 0.0
var _flicker_on := false
var _grace := 0.0                   # the post-respawn invulnerability that flickers
var _clock := 0.0


func setup(p_rider: Rider, p_player: Player, p_world: WorldManager, p_delivery: DeliverySystem) -> void:
	rider = p_rider
	player = p_player
	world = p_world
	delivery = p_delivery
	health = Health.new()
	health.name = "Health"
	health.max_health = 100.0
	health.regen_delay = 5.0
	health.regen_rate = 14.0
	health.process_mode = Node.PROCESS_MODE_ALWAYS   # keeps regenerating while he rides (the body is disabled then)
	player.add_child(health)
	health.died.connect(_on_died)
	last_safe = rider.courier().global_position if rider.bike else player.global_position


func is_down() -> bool:
	return _down


func hit(amount: float, from: Vector3, source: StringName = &"") -> float:
	if _down: return 0.0
	var scale := 1.0
	if rider.is_riding():
		scale = FLYING_SCALE if rider.mode == Rider.Mode.FLYING else RIDING_SCALE
	var taken := health.damage(amount * scale, from, source)
	if taken > 0.0:
		last_hit_from = from
		last_hit_time = _clock
		Events.player_damaged.emit(taken, from)
	return taken


func _on_died() -> void:
	if _down: return
	_down = true
	_down_t = 0.0
	deaths += 1
	rider.hold = true
	Events.player_died.emit()
	went_down.emit()
	Events.message.emit("You were knocked out...", 2.5)


## Skip the fade (tests, tools): wake up at the respawn point now.
func respawn_now() -> void:
	if not _down:
		_down = true
		deaths += 1
	_respawn()


func _respawn() -> void:
	var anchor := last_safe
	var road: Dictionary = world.road_spawn(anchor, anchor + rider.courier().global_transform.basis.z * -5.0)
	rider.respawn_at(road.pos, road.forward)
	last_penalty = mini(PENALTY_MAX, int(ceil(delivery.coins * PENALTY_FRACTION)))
	if last_penalty > 0:
		delivery.coins -= last_penalty
		delivery.wallet_changed.emit(delivery.coins)
	health.reset()
	health.invulnerable = INVULNERABLE
	_grace = INVULNERABLE
	_down = false
	_down_t = RESPAWN_AT
	rider.hold = false
	Events.player_respawned.emit(road.pos)
	respawned.emit(road.pos)
	Events.message.emit("You came to by the road.%s" % (" (-%d coins)" % last_penalty if last_penalty > 0 else ""), 3.0)


func _process(delta: float) -> void:
	_clock += delta
	if _down:
		_down_t += delta
		fade = clampf(_down_t / FADE_OUT, 0.0, 1.0)
		if _down_t >= RESPAWN_AT: _respawn()
		return
	if fade > 0.0: fade = maxf(0.0, fade - delta / FADE_IN)
	# invulnerability flicker (the respawn grace only; tools may make him invulnerable quietly)
	_grace = maxf(0.0, _grace - delta)
	var flicker := _grace > 0.0 and health.invulnerable > 0.0
	if flicker:
		var on := int(_grace * 12.0) % 2 == 0
		player.model.visible = on
		_flicker_on = true
	elif _flicker_on:
		_flicker_on = false
		player.model.visible = true
	# the last safe spot: on the ground, no fight nearby, not in the water
	_safe_t -= delta
	if _safe_t <= 0.0:
		_safe_t = 2.0
		var c := rider.courier()
		var p := c.global_position
		var calm: bool = director == null or not director.threat_near(p, 70.0)
		var dry := p.y > (world.terrain.water_level_at(p.x, p.z) if world and world.terrain else Terrain.SEA_LEVEL) + 0.3
		if calm and dry and (_clock - last_hit_time) > 6.0 and rider.mode != Rider.Mode.FLYING:
			last_safe = p


func low_health() -> bool:
	return health.fraction() < 0.3 and not _down
