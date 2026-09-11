class_name Vehicle
extends CharacterBody3D
## What every rideable / drivable thing is: a body, a VehicleDefinition, and a GroundDrive that
## turns this tick's ControlIntent into motion. A controller (the player's Rider, the Autopilot,
## later an NPC driver) drives any of them through the same interface:
##
##   apply_definition(d)   read the tunables (before _ready, or any time)
##   apply(intent)         hand over this tick's ControlIntent
##   set_parked(v)         nobody aboard: hold still, keep gravity
##   place(pos, fwd)       teleport onto the ground facing `fwd`
##   reset_to_road(away)   nearest road point, upright — after a swim or a rollover
##   speed / grounded / heading() / flat_forward() / speed_kmh() / status_line()
##
## The drive is the implementation; this class is the seam. `speed`, `grounded`, `steer` and the
## rest read straight through to it, so a visual, the HUD or a test still says `bike.speed`.
##
## A concrete vehicle adds only what is genuinely its own — the Bike adds wings and flight, the
## Truck adds a cargo rack and a winch — and overrides `_drive_mods()` if its load, fuel or
## upgrades change how it drives this tick.

var definition: VehicleDefinition
var drive: GroundDrive
var visual: Node3D

## The ground the vehicle stands on. Set it whenever; the drive is kept in step.
var terrain: Terrain:
	get: return _terrain
	set(value):
		_terrain = value
		if drive != null: drive.terrain = value
var _terrain: Terrain
var parked := false
var entity_id: StringName = &""


func apply_definition(d: VehicleDefinition) -> void:
	definition = d
	if drive != null:
		push_warning("%s: apply_definition after the drive was built" % name)


## Concrete vehicles call this from _ready() once their wheel offsets are known.
func _build_drive(wheel_offsets: Array, ray_length: float = 2.4) -> void:
	drive = GroundDrive.new(self, definition)
	drive.add_wheel_rays(wheel_offsets, ray_length)
	drive.terrain = _terrain


# --- state, read through to the drive so callers and tests keep one vocabulary ----------------

var speed: float:
	get: return drive.speed if drive != null else 0.0
	set(value):
		if drive != null: drive.speed = value

var grounded: bool:
	get: return drive.grounded if drive != null else true
	set(value):
		if drive != null: drive.grounded = value

var ground_normal: Vector3:
	get: return drive.ground_normal if drive != null else Vector3.UP

var steer: float:
	get: return drive.steer if drive != null else 0.0

var throttle: float:
	get: return drive.throttle if drive != null else 0.0

var brake: float:
	get: return drive.brake if drive != null else 0.0

var handbrake: bool:
	get: return drive.handbrake if drive != null else false

var slip: float:
	get: return drive.slip if drive != null else 0.0

var air_time: float:
	get: return drive.air_time if drive != null else 0.0

var vertical_vel: float:
	get: return drive.vertical_vel if drive != null else 0.0
	set(value):
		if drive != null: drive.vertical_vel = value

var odometer: float:
	get: return drive.odometer if drive != null else 0.0
	set(value):
		if drive != null: drive.odometer = value


# --- interface --------------------------------------------------------------------------------

## How this vehicle reads the device. The Rider hands it to the Source each tick, so the
## Keyboard never has to know what is being driven.
class GroundScheme:
	extends Controls.Scheme
	var vehicle: Vehicle
	func _init(v: Vehicle) -> void:
		vehicle = v
	func map(r: Controls.Reading, i: Controls.Intent) -> void:
		i.steer = r.side
		i.throttle = r.forward
		i.brake = r.back
		i.boost = r.run
		i.handbrake = r.down(&"handbrake")
		if r.just(&"fire"): i.press(Controls.FIRE)

var _scheme: Controls.Scheme


func control_scheme() -> Controls.Scheme:
	if _scheme == null: _scheme = _make_scheme()
	return _scheme


func _make_scheme() -> Controls.Scheme:
	return GroundScheme.new(self)


func apply(intent: Controls.Intent) -> void:
	if drive != null: drive.intent = intent


func set_parked(v: bool) -> void:
	parked = v
	if v: speed = 0.0


func place(pos: Vector3, forward: Vector3) -> void:
	if drive != null: drive.place(pos, forward)


func reset_to_road(away_from_sea: bool = false) -> void:
	if drive != null: drive.recover_to_road(away_from_sea)


func flat_forward() -> Vector3:
	return drive.flat_forward() if drive != null else -global_transform.basis.z


func heading() -> float:
	return drive.yaw if drive != null else atan2(global_transform.basis.z.x, global_transform.basis.z.z)


func speed_kmh() -> float:
	return absf(speed) * 3.6


## How this vehicle drives *this tick*: cargo, fuel and upgrades live in the concrete vehicle,
## never in the drive.
func _drive_mods() -> GroundDrive.Mods:
	var m := GroundDrive.Mods.new()
	m.top_speed = definition.max_speed
	m.motor_accel = definition.accel
	m.reverse_limit = definition.reverse_speed
	return m


## Visual hooks live on the vehicle interface so gameplay systems never reach into a concrete
## bike/truck renderer (and new script classes compile from a completely cold cache).
func set_rider_visible(v: bool) -> void:
	if visual: visual.set_rider_visible(v)


func set_package_visible(v: bool) -> void:
	if visual: visual.set_package_visible(v)


## What the ChaseCamera needs from whatever it is following — nothing more, so it never has to
## ask "am I looking at a Bike?".
func camera_speed() -> float:
	return speed


func camera_top_speed() -> float:
	return definition.max_speed if definition else 27.0


## One line the HUD can show without knowing what kind of vehicle this is.
func status_line() -> String:
	return definition.display_name if definition else "Vehicle"


func save_state() -> Dictionary:
	return {"pos": global_position, "forward": flat_forward(), "odometer": odometer}


func load_state(d: Dictionary) -> void:
	place(d.get("pos", global_position), d.get("forward", flat_forward()))
	odometer = float(d.get("odometer", 0.0))
