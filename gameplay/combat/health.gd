class_name Health
extends Node
## A hit-point pool: a component node under whatever can be shot (the courier, a bandit).
## Regenerates after `regen_delay` seconds without damage; `invulnerable` seconds ignore hits
## (the respawn grace). Knows nothing about who shot or what happens on death — it says so.
##
##   damage(amount, from, source) -> float   what was actually taken
##   heal(amount) / reset() / fraction() / is_dead()
##   signals damaged(amount, from, source), died, revived

signal damaged(amount: float, from: Vector3, source: StringName)
signal died
signal revived

@export var max_health := 100.0
@export var regen_delay := 5.0       # seconds after the last hit
@export var regen_rate := 0.0        # per second (0 = never)
var current := 100.0
var invulnerable := 0.0
var since_hit := 999.0
var last_from := Vector3.ZERO


func _ready() -> void:
	current = max_health


func damage(amount: float, from: Vector3 = Vector3.ZERO, source: StringName = &"") -> float:
	if is_dead() or invulnerable > 0.0 or amount <= 0.0: return 0.0
	var taken := minf(amount, current)
	current -= taken
	since_hit = 0.0
	last_from = from
	damaged.emit(taken, from, source)
	if current <= 0.0:
		current = 0.0
		died.emit()
	return taken


func heal(amount: float) -> void:
	if is_dead(): return
	current = minf(max_health, current + amount)


func reset() -> void:
	var was_dead := is_dead()
	current = max_health
	since_hit = 999.0
	if was_dead: revived.emit()


func fraction() -> float:
	return current / maxf(max_health, 0.001)


func is_dead() -> bool:
	return current <= 0.0


func _process(delta: float) -> void:
	since_hit += delta
	if invulnerable > 0.0: invulnerable = maxf(0.0, invulnerable - delta)
	if regen_rate > 0.0 and not is_dead() and since_hit > regen_delay and current < max_health:
		current = minf(max_health, current + regen_rate * delta)
