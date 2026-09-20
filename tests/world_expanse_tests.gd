extends SceneTree
var failures := 0
func check(ok: bool, description: String) -> void:
	print(('PASS ' if ok else 'FAIL ') + description)
	if not ok: failures += 1
func _initialize() -> void:
	call_deferred('_run')
func _run() -> void:
	var terrain := Terrain.new()
	terrain.heights.resize(Terrain.N*Terrain.N); terrain.heights.fill(20.0)
	terrain.road_samples.append(PackedVector3Array([Vector3(-300,20,-490), Vector3(-300,20,-486)]))
	var expanse := preload('res://world/terrain/world_expanse.gd').new()
	root.add_child(expanse)
	expanse.setup(terrain, 2026)
	check(terrain.road_samples.size()==2 and terrain.bridges.size()==1, 'north viaduct connects into navigation graph')
	check(Terrain.SIZE == 25000.0 and Terrain.CORE_SIZE == 1248.0, '25 km world preserves authored core dimensions')
	check(expanse.heights.size() == 160801, 'outer terrain has bounded 160801 sample budget')
	check(expanse.height_at(12501,0) < 0, 'outside world is sea')
	check(absf(expanse.height_at(750,0)+10.5) < .01, 'outer mesh joins core sea rim')
	var focus := Node3D.new(); root.add_child(focus); expanse.focus=focus
	for point in [Vector3(-4200,0,-4200),Vector3(6000,0,6000),Vector3(12499,0,12499)]:
		focus.position=point; expanse.refresh_collision()
		check(expanse.loaded.size() <= 25, 'collision tile count bounded after teleport '+str(point))
		await physics_frame
		await physics_frame
		var y: float=expanse.height_at(point.x,point.z)
		var ray:=PhysicsRayQueryParameters3D.create(Vector3(point.x,y+100,point.z),Vector3(point.x,y-100,point.z),1)
		var hit: Dictionary=root.get_world_3d().direct_space_state.intersect_ray(ray)
		check(not hit.is_empty() and absf(float(hit.get('position',Vector3.ZERO).y)-y)<.03, 'physics ray matches rendered triangle interpolation '+str(point))
	var middle: Vector3=terrain.bridges[0].samples[100]
	var bridge_ray:=PhysicsRayQueryParameters3D.create(middle+Vector3.UP*30,middle-Vector3.UP*30,1)
	var bridge_hit: Dictionary=root.get_world_3d().direct_space_state.intersect_ray(bridge_ray)
	check(not bridge_hit.is_empty() and absf(bridge_hit.position.y-middle.y)<.03, 'north viaduct has upward physical deck')
	focus.position=Vector3(6000,0,6000)
	for i in range(30): await process_frame
	var dressing_stats: Dictionary=expanse.dressing.stats()
	check(dressing_stats.instances>0, 'remote land receives actual vegetation')
	check(dressing_stats.tiles<=25, 'wilderness dressing tiles bounded after teleport')
	check(dressing_stats.instances<=dressing_stats.max_instances, 'wilderness decoration has bounded instance budget')
	var tile:=Vector2i(18,18)
	var before: Node3D=expanse.dressing.loaded[tile]
	var signature_before:=vegetation_signature(before)
	before.queue_free(); expanse.dressing.loaded.erase(tile); expanse.dressing._build_tile(tile)
	check(signature_before==vegetation_signature(expanse.dressing.loaded[tile]), 'unloaded/reloaded vegetation keeps deterministic transforms and colors')
	print('WORLD EXPANSE FAILURES: ', failures)
	terrain.free()
	quit(failures)

func vegetation_signature(node: Node3D) -> int:
	var signature: Array=[]
	for view: MultiMeshInstance3D in node.get_children():
		var multi:=view.multimesh
		signature.append(multi.instance_count)
		for i in range(mini(8,multi.instance_count)):
			signature.append(multi.get_instance_transform(i)); signature.append(multi.get_instance_color(i))
	return hash(signature)
