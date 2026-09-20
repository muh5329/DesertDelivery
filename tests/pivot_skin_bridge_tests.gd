extends SceneTree
## Independent native-engine contracts. Run with --headless --script res://tests/pivot_skin_bridge_tests.gd.
const Bridge = preload("res://entities/player/pivot_skin_bridge.gd")
var failures := 0
var checks := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures += 1
	print(("PASS " if condition else "FAIL ") + message)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var model := Node3D.new(); root.add_child(model)
	model.transform=Transform3D(Basis(Vector3.UP,.37).scaled(Vector3.ONE*1.2),Vector3(8,2,-5))
	var pivots: Array[Node3D] = []
	var parent: Node3D = model
	var names := ["Skin_Root","Skin_Torso","Skin_ArmR","Skin_ElbowR","Skin_HandR"]
	var offsets := [Vector3(0,.82,0),Vector3(0,.08,0),Vector3(.2,.5,0),Vector3(0,-.24,0),Vector3(0,-.235,0)]
	for index in names.size():
		var pivot := Node3D.new(); parent.add_child(pivot); pivot.position=offsets[index]
		pivots.append(pivot); parent=pivot
	var prop := Node3D.new(); parent.add_child(prop); prop.position=Vector3(.03,-.06,-.07)
	var skeleton := Skeleton3D.new(); model.add_child(skeleton)
	skeleton.transform=Transform3D(Basis(Vector3.RIGHT,.24),Vector3(.15,.22,-.19))
	var mapping := {}
	for index in names.size():
		skeleton.add_bone(names[index])
		if index>0: skeleton.set_bone_parent(index,index-1)
		# Native rest axes aligned to the legacy pivots, independent of the skeleton object's transform.
		var desired := skeleton.global_transform.affine_inverse()*pivots[index].global_transform
		var previous := Transform3D.IDENTITY if index==0 else skeleton.get_bone_global_rest(index-1)
		skeleton.set_bone_rest(index,previous.affine_inverse()*desired)
		mapping[names[index]]=pivots[index]
	skeleton.reset_bone_poses()
	var bridge := Bridge.new(); model.add_child(bridge)
	check(bridge.bind(skeleton,mapping),"aligned legacy hierarchy binds")
	await process_frame; await process_frame
	var rest_ok := true
	var probe := Vector3(.21,1.19,-.08)
	for index in names.size():
		var deformed: Vector3=skeleton.get_bone_global_pose(index)*skeleton.get_bone_global_rest(index).affine_inverse()*probe
		rest_ok=rest_ok and deformed.distance_to(probe)<.00001
	check(rest_ok,"native rest pose times inverse bind leaves all bind-space vertices unchanged")
	# Real resident width variation plus seated arm elongation must compose without shear when authored axes align.
	pivots[0].rotation=Vector3(.12,.25,-.05); pivots[0].position+=Vector3(.1,.28,.25)
	pivots[1].rotation.x=-.28; pivots[1].scale=Vector3(1.16,1,1)
	pivots[2].rotation=Vector3(.85,0,-.13); pivots[2].scale.y=1.35
	pivots[3].rotation.x=.35
	model.position+=Vector3(100,3,-40); model.rotate_y(.61)
	var prop_before:=prop.global_transform
	bridge.sync_pose(); await process_frame; await process_frame
	var aligned := true
	for index in names.size():
		var actual: Transform3D=skeleton.global_transform*skeleton.get_bone_global_pose(index)
		aligned=aligned and actual.is_equal_approx(pivots[index].global_transform)
	check(aligned,"nonuniform torso and riding arm scales preserve every native bone/pivot world transform")
	check(prop_before.is_equal_approx(prop.global_transform) and prop.get_parent()==pivots[-1],"skin bridge never reparents or transforms hand props")
	# A work animation mutates an arm after the ordinary walking animator. The bridge reads the final pivot pose.
	pivots[2].rotation.x=.79; pivots[3].rotation.x=.91
	await process_frame; await process_frame
	check((skeleton.global_transform*skeleton.get_bone_global_pose(4)).is_equal_approx(pivots[4].global_transform),"late activity pose reaches the hand bone through normal bridge processing")
	# Relocating the Skeleton object alone must not make the skin drift from the legacy animation targets.
	skeleton.position+=Vector3(.4,-.2,.3); skeleton.rotate_y(.19)
	await process_frame; await process_frame
	check((skeleton.global_transform*skeleton.get_bone_global_pose(4)).is_equal_approx(pivots[4].global_transform),"nonidentity skeleton relocation compensates into bone space")
	check(not bridge.bind(skeleton,{"NotAuthored":pivots[0]}) and not bridge.is_processing(),"missing authored joint rejects the whole binding")
	check(bridge.bind(null,{}) and not bridge.is_processing(),"legacy model without skeleton uses disabled optional bridge")
	check(bridge.bind(skeleton,mapping),"valid binding can be restored after failure")
	pivots[-1].free()
	await process_frame; await process_frame
	check(not bridge.is_processing(),"freed legacy pivot safely disables binding")
	model.free()
	print("PIVOT SKIN BRIDGE TESTS: %s (%d checks, %d failures)" % ["PASS" if failures==0 else "FAIL", checks, failures])
	quit(0 if failures==0 else 1)
