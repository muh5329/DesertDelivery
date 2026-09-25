class_name GroundPose
extends RefCounted
## A visual pose from the actual collision beneath an upright kinematic body (Red Sea Baron):
## the body's collider stays upright so it never snags, and its visual pitches and rolls to the
## ground it stands on.
var pitch: float = 0
var roll: float = 0
var height: float = 0


func sample(body: CharacterBody3D, active: bool = true) -> void:
	pitch = 0
	roll = 0
	height = 0
	if not active or not body.is_on_floor(): return
	var query := PhysicsRayQueryParameters3D.create(body.global_position + Vector3.UP * 2, body.global_position - Vector3.UP * 3, 1)
	query.exclude = [body.get_rid()]
	var hit := body.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): return
	var normal: Vector3 = body.global_basis.inverse() * (hit.normal as Vector3)
	pitch = clampf(atan2(normal.z, normal.y), -0.75, 0.75)
	roll = clampf(asin(clampf(-normal.x, -1, 1)), -0.75, 0.75)
	height = clampf((hit.position as Vector3).y - body.global_position.y, -1.2, 0.5)
