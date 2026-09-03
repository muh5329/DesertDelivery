extends SceneTree
func _init():
	var lv := Level.new()
	get_root().add_child(lv)
	lv.build()
	await process_frame
	await physics_frame
	var c := Vector3(float(OS.get_environment("PX")), float(OS.get_environment("PY")), float(OS.get_environment("PZ")))
	var space := get_root().get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var sh := SphereShape3D.new(); sh.radius = 2.5; q.shape = sh
	q.transform = Transform3D(Basis(), c); q.collision_mask = 1
	for hit in space.intersect_shape(q, 16):
		var col: Node = hit.collider
		print("hit: ", col.get_path(), " parent=", col.get_parent().name, " pos=", col.global_position)
	print("ground=", lv.terrain.height_at(c.x, c.z), " road_dist=", lv.terrain.road_dist_at(c.x, c.z))
	quit()
