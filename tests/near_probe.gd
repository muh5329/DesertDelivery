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
	print("ground=", lv.terrain.height_at(c.x, c.z), " road_dist=", lv.terrain.road_dist_at(c.x, c.z))
	get_tree().quit()
