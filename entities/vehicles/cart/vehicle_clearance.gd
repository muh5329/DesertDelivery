class_name VehicleClearance
extends RefCounted
## Clearance (Red Sea Baron): does a proposed pose of a body fit in the world? A CharacterBody
## sweeps its translation, but assigning a yaw can swing a corner into a neighbour — a wall, a
## parked car, the vehicle towing it. Every yaw change of the Cart asks here first.

## What a towed cart must stay clear of: the world, vehicles (its tow vehicle too), traffic.
const WORLD_AND_VEHICLES: int = 1 | 2 | 16


static func turn_clear(body: CharacterBody3D, yaw: float, mask: int, lift: float = 0.0) -> bool:
	var pose := Transform3D(Basis(Vector3.UP, yaw), body.global_position + Vector3.UP * lift)
	for child in body.get_children():
		if not child is CollisionShape3D or child.disabled: continue
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = child.shape
		query.transform = pose * child.transform
		query.collision_mask = mask
		query.exclude = [body.get_rid()]
		if not body.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(): return false
	return true


static func apply_turn(body: CharacterBody3D, yaw: float, mask: int, adjust_floor: bool = true) -> bool:
	if is_equal_approx(body.rotation.y, yaw): return true
	if turn_clear(body, yaw, mask):
		body.rotation.y = yaw
		return true
	if not adjust_floor or not body.is_on_floor(): return false
	# An upright box changes its lowest corner when yawing on a slope. Lift only by that
	# geometric support difference; never ignore the floor collider.
	var normal := body.get_floor_normal()
	if normal.y < cos(body.floor_max_angle): return false
	var before := _lowest_projection(body, body.global_basis, normal)
	var after := _lowest_projection(body, Basis(Vector3.UP, yaw), normal)
	var lift := (before - after) / normal.y
	if not is_finite(lift) or lift <= 0 or lift > 0.08: return false
	lift += 0.002
	if not turn_clear(body, yaw, mask, lift): return false
	body.global_position.y += lift
	body.rotation.y = yaw
	return true


static func _lowest_projection(body: CharacterBody3D, basis: Basis, normal: Vector3) -> float:
	var lowest := INF
	for child in body.get_children():
		if not child is CollisionShape3D or child.disabled: continue
		if child.shape is ConvexPolygonShape3D:
			for point: Vector3 in child.shape.points:
				lowest = minf(lowest, normal.dot(basis * (child.transform * point)))
			continue
		if not child.shape is BoxShape3D: return INF
		var half_size: Vector3 = child.shape.size * 0.5
		var axes: Basis = basis * child.basis
		var support := absf(normal.dot(axes.x)) * half_size.x + absf(normal.dot(axes.y)) * half_size.y + absf(normal.dot(axes.z)) * half_size.z
		lowest = minf(lowest, normal.dot(basis * child.position) - support)
	return lowest
