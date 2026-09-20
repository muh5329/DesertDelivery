extends SceneTree
## NPC LOD preserves the live rig, recoloring and attachment points while reducing geometry.
var failures := 0
func _init() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ") + message)
	if not ok: failures += 1
func triangles(model: Node) -> int:
	var count := 0
	for node in model.find_children("*", "MeshInstance3D", true, false):
		if not node.is_visible_in_tree(): continue
		for surface in node.mesh.get_surface_count():
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			count += (arrays[Mesh.ARRAY_INDEX].size() if arrays[Mesh.ARRAY_INDEX] != null and arrays[Mesh.ARRAY_INDEX].size() else arrays[Mesh.ARRAY_VERTEX].size()) / 3
	return count
func run() -> void:
	var person := RiderModel.new(); root.add_child(person)
	person.set_palette(Color.RED,Color.BLUE,Color.GREEN,Color(.9,.7,.5))
	var full_count := triangles(person)
	var root_id := person.root.get_instance_id()
	var hand_id := person.hand_r.get_instance_id()
	var attachment := Node3D.new(); person.hand_r.add_child(attachment)
	person.enable_resident_lod()
	check(person._lod_pairs.size() == 15, "all 15 authored meshes have a reduced counterpart")
	var low := RiderModel.NPC_LOD.instantiate(); root.add_child(low)
	for pair in person._lod_pairs:
		var reduced: MeshInstance3D = low.find_child(String(pair.node.name),true,false)
		check(reduced != null and pair.node.global_transform.is_equal_approx(reduced.global_transform), "roundtrip preserves mesh frame " + String(pair.node.name))
		if pair.full_skin:
			check(pair.low_skin != null and pair.full_skin.get_bind_count() == pair.low_skin.get_bind_count(), "skin bind count " + String(pair.node.name))
			for bind in pair.full_skin.get_bind_count():
				check(pair.full_skin.get_bind_name(bind) == pair.low_skin.get_bind_name(bind) and pair.full_skin.get_bind_pose(bind).is_equal_approx(pair.low_skin.get_bind_pose(bind)), "skin rest unchanged " + String(pair.node.name) + "/" + str(bind))
	low.free()
	person.animate("walk",1.35,.14)
	person.sync_resident_pose()
	var hand_pose := person.hand_r.global_transform
	person.set_resident_lod_distance(23.0)
	var low_count := triangles(person)
	print("NPC GEOMETRY full=%d low=%d" % [full_count,low_count])
	check(person.resident_lod_active and low_count <= 15000 and low_count < full_count*.2,"distant NPC under 15k triangles and at least 80% reduction")
	check(person.root.get_instance_id()==root_id and person.hand_r.get_instance_id()==hand_id and attachment.get_parent()==person.hand_r,"LOD never replaces live pivots or attachments")
	check(person.hand_r.global_transform.is_equal_approx(hand_pose),"LOD switch preserves current walk pose")
	var colors_ok := true
	for pair in person._lod_pairs:
		for surface in pair.low_materials.size():
			colors_ok = colors_ok and pair.reduced_node.get_active_material(surface)==pair.low_materials[surface]
	check(colors_ok,"resident recoloring retained after surface reorder")
	var immutable := true
	for pair in person._lod_pairs:
		immutable = immutable and pair.node.mesh == pair.full_mesh and pair.node.skin == pair.full_skin
		immutable = immutable and pair.reduced_node.skin == pair.full_skin
		immutable = immutable and not pair.node.visible and pair.reduced_node.visible
		immutable = immutable and pair.node.global_transform.is_equal_approx(pair.reduced_node.global_transform)
	check(immutable,"LOD only toggles visibility: immutable buffers, original skin and identical mesh frames")
	person.set_resident_lod_distance(20); check(person.resident_lod_active,"22/18m hysteresis retains reduced model")
	person.set_resident_lod_distance(17); check(not person.resident_lod_active and triangles(person)==full_count,"close range restores full model")
	person.set_resident_lod_distance(20); check(not person.resident_lod_active,"hysteresis retains full model inside 22m")
	person.pose_riding(); person.set_resident_lod_distance(40); person.sync_resident_pose()
	check(person.root.position.is_equal_approx(Vector3(0,1.1,.25)),"seated pose survives LOD switch")
	var hero := RiderModel.new(); root.add_child(hero); hero.set_resident_lod_distance(100)
	check(not hero.resident_lod_active and hero._skin_bridge.is_processing(),"player keeps full geometry and automatic skin updates")
	var camera := Camera3D.new(); root.add_child(camera); camera.position=Vector3(0,2,80); camera.current=true
	var resident := Resident.new(); resident.id="lod_test"; resident.name="LOD test"; resident.activity="read"
	resident.palette=["#4477aa","#bb9944","#884422","#eebb99"]
	var actor = load("res://world/life/resident_actor.gd").new(); root.add_child(actor); actor.setup(resident)
	actor.update_view(resident,1.0/120.0,false)
	check(actor.person.resident_lod_active and not actor.person._skin_bridge.is_processing(),"distant actor uses reduced geometry and explicit skin flush")
	var phase: float = actor.person._t
	actor.update_view(resident,1.0/120.0,false)
	check(is_equal_approx(actor.person._t,phase),"distant cosmetic pose skips intermediate physics ticks")
	var body_id: int = actor.get_instance_id()
	resident.driving=true
	actor.update_view(resident,.001,false)
	check(actor._body_shape.shape is BoxShape3D and actor.get_instance_id()==body_id,"driving transition updates collision immediately despite animation throttle")
	resident.driving=false; resident.activity="sleep"
	actor.update_view(resident,.001,false)
	check(actor._body_shape.shape is CapsuleShape3D and not actor.person.visible,"sleep and walking state transition is immediate")
	actor.free(); camera.free()
	person.free(); hero.free()
	print("NPC LOD failures: ",failures); quit(1 if failures else 0)
