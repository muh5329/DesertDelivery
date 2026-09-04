extends Node
## EventBus (autoload `Events`): application-wide signals so systems never reference each other
## directly. Keep it to genuinely cross-cutting events; two nodes with a natural parent/child
## relationship should use local signals instead.
##
## Naming: past tense, one payload per fact, ids are stable StringNames from the world database
## (`location.villa_rosa_office`, `vehicle.bike`, `can.hilltop_farm.2`), never node paths.

# --- player / rider
signal rider_mode_changed(from: int, to: int)
signal message(text: String, duration: float)           # something the HUD should say to the player

# --- delivery loop
signal job_changed(job: JobDefinition, stage: StringName) # stage: &"pickup" | &"dropoff" | &"done"
signal package_collected(job_id: StringName)
signal delivery_completed(job_id: StringName, total: int)

# --- weapons
signal gun_picked_up
signal can_hit(can_id: StringName, hit: int, total: int)

# --- vehicles
signal vehicle_crashed(vehicle_id: StringName)
signal vehicle_landed(vehicle_id: StringName, impact: float)

# --- world streaming
signal chunk_loaded(coord: Vector2i)
signal chunk_unloaded(coord: Vector2i)
signal location_entered(location_id: StringName)

# --- entities
signal entity_registered(entity_id: StringName)
signal entity_unregistered(entity_id: StringName)
signal simulation_tier_changed(entity_id: StringName, tier: int)

# --- persistence
signal game_saved(slot: String)
signal game_loaded(slot: String)
