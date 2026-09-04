class_name Vehicle
extends CharacterBody3D
## What every rideable / drivable thing has in common, so a controller (the player's Rider, an
## NPC driver, the Autopilot) can drive any of them through the same interface:
##   definition        VehicleDefinition (tunables, look)
##   apply(intent)     consume this tick's ControlIntent (from whoever controls the vehicle)
##   set_parked(v)     nobody aboard: hold still, keep gravity
##   place(pos, fwd)   teleport onto the ground facing `fwd`
##   speed / grounded / parked / flat_forward() / heading()
## Concrete vehicles (Bike, later cars and boats) extend this and implement the physics.

var definition: VehicleDefinition
var speed := 0.0
var grounded := true
var parked := false
var odometer := 0.0
var entity_id: StringName = &""


func apply(_intent: Controls.Intent) -> void:
	pass


func set_parked(v: bool) -> void:
	parked = v


func place(_pos: Vector3, _forward: Vector3) -> void:
	pass


func flat_forward() -> Vector3:
	var f := -global_transform.basis.z
	f.y = 0.0
	return f.normalized()


func heading() -> float:
	var f := flat_forward()
	return atan2(-f.x, -f.z)


## Bike/car/boat report their state for the save file; override to add fields.
func save_state() -> Dictionary:
	return {"pos": global_position, "forward": flat_forward(), "odometer": odometer}


func load_state(d: Dictionary) -> void:
	odometer = float(d.get("odometer", 0.0))
	place(d.get("pos", global_position), d.get("forward", flat_forward()))
