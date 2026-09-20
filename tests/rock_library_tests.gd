extends SceneTree
## Rebuild each baked piece from its canonical parameters and compare exact arrays.
var failures:=0
func _init() -> void:call_deferred("run")
func check(ok:bool,message:String) -> void:
	print(("PASS " if ok else "FAIL ")+message)
	if not ok:failures+=1
func equal_mesh(a:Mesh,b:Mesh) -> bool:
	if a.get_surface_count()!=b.get_surface_count():return false
	for surface in a.get_surface_count():
		var aa:=a.surface_get_arrays(surface);var bb:=b.surface_get_arrays(surface)
		for attribute in Mesh.ARRAY_MAX:
			if var_to_bytes(aa[attribute])!=var_to_bytes(bb[attribute]):return false
	return true
func run() -> void:
	var checked:=0;var mismatches:=0
	var first:Dictionary={}
	for file in DirAccess.get_files_at(RockGen.BAKED_DIR):
		if not file.ends_with(".res"):continue
		var resource:Resource=load(RockGen.BAKED_DIR+"/"+file)
		var p:Dictionary=resource.get_meta("parameters")
		var baked:Dictionary=resource.get_meta("piece")
		var regenerated:=RockGen.make_rock(p)
		var same:=equal_mesh(baked.mesh,regenerated.mesh) and equal_mesh(baked.mesh_lod1,regenerated.mesh_lod1)
		same=same and resource.get_meta("key")==RockGen._cache_key(p)
		same=same and var_to_bytes(baked.hull)==var_to_bytes(regenerated.hull) and baked.tris==regenerated.tris and baked.tris_lod1==regenerated.tris_lod1
		if not same: mismatches+=1;print("DIFFERENT ",file)
		if checked==0:first=p
		checked+=1
	check(checked==180 and mismatches==0,"all180 baked pieces exactly match regenerated vertices/normals/colors/LOD/collision hulls")
	RockGen._cache.clear()
	var before:=RockGen.disk_hits
	var baked:=RockGen.cached(first)
	check(RockGen.disk_hits==before+1,"runtime cache miss loads exact disk resource")
	var again:=RockGen.cached(first)
	check(again.mesh==baked.mesh and RockGen.disk_hits==before+1,"repeat request uses shared in-memory mesh")
	var unknown:=first.duplicate();unknown.seed=912345678
	var procedural:=RockGen.cached(unknown)
	check(procedural.mesh!=null and RockGen.disk_hits==before+1,"unbaked parameters fall back to deterministic generation")
	var defaults:=RockGen._cache_key({})
	check(defaults==RockGen._cache_key(RockGen.DEFAULTS),"cache fingerprint includes effective defaults without duplicate aliases")
	check(RockGen._cache_key({"cell":1.00000001})!=RockGen._cache_key({"cell":1.00000002}),"fingerprint retains close float values that display strings alias")
	for concave in [false,true]:
		var xf:=Transform3D(Basis(Vector3.UP,.37).scaled(Vector3(1.2,.8,1.4)),Vector3(10,4,7))
		var a:=RockGen.build_node(baked,xf,concave)
		var generated:=RockGen.make_rock(first)
		var b:=RockGen.build_node(generated,xf,concave)
		var shapes_a:=a.find_children("*","CollisionShape3D",true,false)
		var shapes_b:=b.find_children("*","CollisionShape3D",true,false)
		var same:bool=shapes_a[0].shape.get_faces()==shapes_b[0].shape.get_faces() if concave else shapes_a[0].shape.points==shapes_b[0].shape.points
		check(same,"pre-scaled collision unchanged (concave=%s)"%str(concave))
		a.free();b.free()
	print("ROCK LIBRARY failures: ",failures);quit(1 if failures else 0)
