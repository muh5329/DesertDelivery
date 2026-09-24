extends SceneTree
## Which way MeshBits faces point: generate_normals follows Godot's front-face winding, so the
## top of a box must come out with +y normals (and a ship's topside with outward normals).
func _init() -> void:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	MeshBits.box(st, Transform3D(), Vector3.ONE, Color.WHITE)
	st.generate_normals()
	var arrays := st.commit_to_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]; var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i in range(verts.size()):
		if verts[i].y > 0.49 and absf(normals[i].y) > 0.9: print("BOX TOP normal y ", normals[i].y); break
	# Godot's own box, for reference: the first top-face triangle's winding
	var bm := BoxMesh.new()
	var a := bm.get_mesh_arrays()
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]; var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]; var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	for t in range(0, idx.size(), 3):
		if n[idx[t]].y > 0.9:
			var p0 := v[idx[t]]; var p1 := v[idx[t + 1]]; var p2 := v[idx[t + 2]]
			print("BoxMesh top tri cross y ", (p1 - p0).cross(p2 - p0).y)
			break
	var s2 := SurfaceTool.new(); s2.begin(Mesh.PRIMITIVE_TRIANGLES)
	MeshBits.box(s2, Transform3D(), Vector3.ONE, Color.WHITE)
	var a2 := s2.commit_to_arrays()
	var v2: PackedVector3Array = a2[Mesh.ARRAY_VERTEX]
	for t in range(0, v2.size(), 3):
		if v2[t].y > 0.49 and v2[t + 1].y > 0.49 and v2[t + 2].y > 0.49:
			print("MeshBits top tri cross y ", (v2[t + 1] - v2[t]).cross(v2[t + 2] - v2[t]).y)
			break
	quit()
