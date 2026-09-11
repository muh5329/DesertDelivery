extends Node
## Lists the colliders within 2.5 m of PX,PY,PZ (env vars) — what is the bike wedged on?
## Run: PX=.. PY=.. PZ=.. godot --headless --path . -- --test=near_probe --nostream
func _ready() -> void:
	await get_tree().process_frame
	await get_tree().physics_frame
	var lv: WorldManager = Game.current.world
	var c := Vector3(float(OS.get_environment("PX")), float(OS.get_environment("PY")), float(OS.get_environment("PZ")))
	var space := get_tree().root.get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var sh := SphereShape3D.new(); sh.radius = 2.5; q.shape = sh
	q.transform = Transform3D(Basis(), c); q.collision_mask = 1
	for hit in space.intersect_shape(q, 16):
		var col: Node = hit.collider
		print("hit: ", col.get_path(), " parent=", col.get_parent().name, " pos=", col.global_position)
		var par: Node = col.get_parent()
		if par is Node3D and par.get_child_count() > 0 and par.get_child(0) is MeshInstance3D:
			var mi: MeshInstance3D = par.get_child(0)
			print("      mesh aabb=", mi.mesh.get_aabb(), " scale=", par.global_transform.basis.get_scale(), " mat=", mi.material_override)
	print("ground=", lv.terrain.height_at(c.x, c.z), " road_dist=", lv.terrain.road_dist_at(c.x, c.z))
	# every rock piece (Node3D holding a MeshInstance3D + StaticBody3D) within 16 m, with its size
	for chunk in lv.streamer.get_children():
		for n in chunk.get_children():
			if not (n is Node3D): continue
			var o: Vector3 = n.global_position
			if Vector2(o.x - c.x, o.z - c.z).length() > 16.0: continue
			var desc := ""
			for ch in n.get_children(): desc += ch.get_class() + " "
			if n.get_child_count() > 0 and n.get_child(0) is MeshInstance3D:
				var mi: MeshInstance3D = n.get_child(0)
				desc += " size=%s" % [mi.mesh.get_aabb().size if mi.mesh else Vector3.ZERO]
			print("node ", n.name, " at ", o, " scale=", n.global_transform.basis.get_scale(), " ", desc, " ground=", lv.terrain.height_at(o.x, o.z))
	get_tree().quit()
