extends SceneTree
## Prints a GLB's node tree with transforms and mesh AABBs (a dev tool).
func _init() -> void:
	var path := "res://assets/models/vehicles/realistic_amphibious_jeep_v1.glb"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--glb="): path = a.substr(6)
	var root: Node3D = load(path).instantiate()
	_dump(root, 0, Transform3D.IDENTITY)
	quit()

func _dump(n: Node, depth: int, parent_xf: Transform3D) -> void:
	var xf := parent_xf
	var extra := ""
	if n is Node3D:
		xf = parent_xf * (n as Node3D).transform
		extra = " pos=%s rot=%s scale=%s" % [(n as Node3D).position, (n as Node3D).rotation_degrees, (n as Node3D).scale]
	if n is MeshInstance3D and n.mesh:
		var aabb: AABB = xf * n.mesh.get_aabb()
		var mats := []
		for i in n.mesh.get_surface_count():
			var m = n.mesh.surface_get_material(i)
			mats.append(m.resource_name if m else "null")
		extra += " AABB(world)=%s surfaces=%d mats=%s" % [aabb, n.mesh.get_surface_count(), mats]
	print("  ".repeat(depth) + n.name + " [" + n.get_class() + "]" + extra)
	for c in n.get_children(): _dump(c, depth + 1, xf)
