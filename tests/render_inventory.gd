extends Node
func _ready() -> void: call_deferred("run")
func run() -> void:
	var g:=Game.current; g.use_scripted_controls()
	g.bike.set_physics_process(false); g.cam.set_physics_process(false)
	var home:=g.world.database.location_pos(&"villa_rosa_office"); g.bike.global_position=home
	var camera:=Camera3D.new(); add_child(camera); camera.current=true; camera.look_at_from_position(home+Vector3(10,5,12),home+Vector3(0,1,0))
	for frame in 120: await get_tree().process_frame
	var rows:Array=[]
	for n in g.find_children("*","GeometryInstance3D",true,false):
		var mesh:Mesh; var instances:=1
		if n is MeshInstance3D: mesh=n.mesh
		elif n is MultiMeshInstance3D: mesh=n.multimesh.mesh; instances=n.multimesh.instance_count
		if mesh==null or not n.is_visible_in_tree(): continue
		var box:AABB=n.global_transform*n.get_aabb(); var dist:=camera.global_position.distance_to(box.get_center())
		if not camera.is_position_in_frustum(box.get_center()) and not box.has_point(camera.global_position): continue
		if n.visibility_range_begin>dist or (n.visibility_range_end>0 and n.visibility_range_end<dist): continue
		var tris:=0
		for surface in mesh.get_surface_count():
			var a:=mesh.surface_get_arrays(surface)
			tris+=(a[Mesh.ARRAY_INDEX].size() if a[Mesh.ARRAY_INDEX]!=null and not a[Mesh.ARRAY_INDEX].is_empty() else a[Mesh.ARRAY_VERTEX].size())/3
		rows.append({"path":str(n.get_path()),"tris":tris*instances,"instances":instances,"dist":dist,"size":str(box.size)})
	rows.sort_custom(func(a,b):return a.tris>b.tris)
	var f:=FileAccess.open("res://artifacts/performance-controls/inventory.json",FileAccess.WRITE); f.store_string(JSON.stringify(rows,"\t")); f.close()
	for r in rows.slice(0,25): print(r)
	get_tree().quit()
