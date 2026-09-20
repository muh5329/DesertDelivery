extends SceneTree
## Asset integration: preserve hand attachment and keep motorcycle boots on the authored pegs.
var failures := 0
func _init() -> void:
	call_deferred("run")
func check(ok: bool, description: String) -> void:
	print(("PASS " if ok else "FAIL ") + description)
	if not ok: failures += 1

func check_seat_contact(character: RiderModel, skeleton: Skeleton3D) -> void:
	# Evaluate the imported garment's actual skinned rear-pelvis patch, not just
	# a pelvis pivot that can sit near the seat while the visible cloth floats.
	var trousers: MeshInstance3D = character.find_child("ContinuousTrousers", true, false)
	var contacts := 0
	var nearest := INF
	for surface in range(trousers.mesh.get_surface_count()):
		var arrays := trousers.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var stride: int = bones.size() / vertices.size()
		for index in range(vertices.size()):
			var vertex := vertices[index]
			if absf(vertex.x) > .09 or vertex.y < .87 or vertex.y > 1.0 or vertex.z < .06: continue
			var posed := Vector3.ZERO
			for slot in range(stride):
				var bind_index := bones[index * stride + slot]
				var bone := trousers.skin.get_bind_bone(bind_index)
				if bone < 0: bone = skeleton.find_bone(trousers.skin.get_bind_name(bind_index))
				posed += (skeleton.global_transform * skeleton.get_bone_global_pose(bone) * trousers.skin.get_bind_pose(bind_index) * vertex) * weights[index * stride + slot]
			# Authored saddle: center(0,1.015,.41), size(.32,.105,.61).
			if absf(posed.x) > .16 or posed.z < .105 or posed.z > .715: continue
			var separation := absf(posed.y - 1.0675)
			nearest = minf(nearest, separation)
			if separation < .025: contacts += 1
	print("Rear pelvis / saddle: %d nearby vertices, nearest %.4f m" % [contacts, nearest])
	check(contacts >= 8, "visible rear pelvis meets saddle within 2.5 cm over a surface patch")

func check_waist_overlap(character: RiderModel, skeleton: Skeleton3D) -> void:
	# Sample the actual lower shirt surface in the authored waistband overlap
	# band. Its posed vertices must remain tucked inside the belt ellipse.
	var shirt: MeshInstance3D = character.find_child("ContinuousShirt", true, false)
	var samples := 0
	var outside := 0
	var max_radius := 0.0
	for surface in range(shirt.mesh.get_surface_count()):
		var arrays := shirt.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var stride: int = bones.size() / vertices.size()
		for index in range(vertices.size()):
			var vertex := vertices[index]
			if absf(vertex.x) > .158 or vertex.y < 1.125 or vertex.y > 1.145: continue
			var posed := Vector3.ZERO
			for slot in range(stride):
				var bind_index := bones[index * stride + slot]
				var bone := shirt.skin.get_bind_bone(bind_index)
				if bone < 0: bone = skeleton.find_bone(shirt.skin.get_bind_name(bind_index))
				posed += (skeleton.global_transform * skeleton.get_bone_global_pose(bone) * shirt.skin.get_bind_pose(bind_index) * vertex) * weights[index * stride + slot]
			var belt_local := character.root.to_local(posed)
			# Waistband authored radii .160/.113, bottom .280, top .325.
			var radial := sqrt(pow(belt_local.x / .160, 2) + pow(belt_local.z / .113, 2))
			max_radius = maxf(max_radius, radial)
			samples += 1
			if radial > 1.04 or belt_local.y > .330 or belt_local.y < .275: outside += 1
	print("Shirt / waistband: %d samples, %d outside, maximum normalized radius %.4f" % [samples, outside, max_radius])
	check(samples >= 32 and outside == 0, "seated shirt lower edge stays tucked within waistband surface")

func run() -> void:
	var character := RiderModel.new()
	root.add_child(character)
	await process_frame
	check(character.hand_r != null, "right hand attachment survives GLB rebuild")
	var skeletons := character.find_children("*", "Skeleton3D", true, false)
	check(skeletons.size() == 1 and character._skin_bridge != null, "imported continuous garments have an active skeleton bridge")
	var skeleton: Skeleton3D = skeletons[0]
	check(character._skin_bridge._pivots.size() == 13 and character._skin_bridge.is_processing(), "all thirteen imported joints bind during character initialization")
	var hand_index := skeleton.find_bone("Skin_HandR")
	var hand_offset := character.hand_r.global_transform.affine_inverse() * skeleton.global_transform * skeleton.get_bone_global_rest(hand_index)
	character.pose_riding(true)
	await process_frame
	await process_frame
	var actual_hand_bone := skeleton.global_transform * skeleton.get_bone_global_pose(hand_index)
	var expected_hand_bone := character.hand_r.global_transform * hand_offset
	check(actual_hand_bone.origin.distance_to(expected_hand_bone.origin) < .001, "actual imported hand bone follows seated gameplay pivot")
	check_seat_contact(character, skeleton)
	check_waist_overlap(character, skeleton)
	for side in [-1.0, 1.0]:
		var leg: Node3D = character.leg_l if side < 0 else character.leg_r
		var knee: Node3D = leg.get_node("Knee")
		var sole_center := knee.to_global(Vector3(side * .05, -.385, -.043))
		# Actual motorcycle pegs: x .20..42, y .38 with .023 radius, z .21.
		# Authored sole bottom center; the broad shoe overlaps the peg end.
		check(absf(sole_center.x) > .36 and absf(sole_center.x) < .46, "boot clears side fairing and reaches peg")
		check(absf(sole_center.y - .403) < .045, "boot sole sits at peg height")
		check(absf(sole_center.z - .21) < .08, "boot overlaps peg fore/aft")
		var arm: Node3D = character.arm_l if side < 0 else character.arm_r
		var palm: Vector3 = arm.get_node("Elbow/Hand").to_global(Vector3(0, -.015, -.004))
		# Authored bike.py grip endpoints plus ForkPivot=(0,1.05,-.52).
		var grip_a := Vector3(side * .25, 1.11, -.445)
		var grip_b := Vector3(side * .39, 1.11, -.40)
		var nearest := Geometry3D.get_closest_point_to_segment(palm, grip_a, grip_b)
		var reach_error := palm.distance_to(nearest)
		print("Motorcycle palm-to-grip distance: %.4f m" % reach_error)
		check(reach_error < .06, "palm reaches handlebar within combined glove and grip radius")
	character.pose_riding()
	check(is_equal_approx(character.leg_r.rotation.x, 1.20), "car/truck seating retains its original fit")
	character.queue_free()
	await process_frame
	print("CHARACTER FIT: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
