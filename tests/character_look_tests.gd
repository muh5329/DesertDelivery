extends SceneTree
## CharacterLook / PersonBuilder: deterministic, diverse, cheap, and bound to the shared rig.
##   godot --headless --path . -s tests/character_look_tests.gd
var failures := 0

func _init() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ") + message)
	if not ok: failures += 1

func run() -> void:
	# determinism
	var a := CharacterLook.from_seed(123, &"puerto", "dockworker")
	var b := CharacterLook.from_seed(123, &"puerto", "dockworker")
	check(var_to_str(a) == var_to_str(b), "from_seed is deterministic")
	var c := CharacterLook.from_seed(124, &"puerto", "dockworker")
	check(var_to_str(a) != var_to_str(c), "a different seed gives a different person")
	# residents
	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/life/residents.json"))
	var records: Array = []
	for src in parsed.residents: records.append(Resident.from_source(src))
	var signatures := {}
	var hair := {}; var tops := {}; var skins := {}; var sexes := {}; var ages := 0
	for r in records:
		var look := CharacterLook.for_resident(r)
		signatures[str(CharacterLook.signature(look))] = true
		hair[look.hair] = true; tops[look.top] = true
		skins[snappedf(float(look.skin_tone), 1.0)] = true
		sexes[look.sex] = int(sexes.get(look.sex, 0)) + 1
		if int(look.age) >= 62: ages += 1
		if CharacterLook.sex_for_name(r.name) != "" and look.sex != CharacterLook.sex_for_name(r.name):
			check(false, "%s presents as named" % r.name)
	print("RESIDENT LOOKS: %d signatures, %d hair styles, %d tops, %d skin steps, sexes %s, elders %d" % [signatures.size(), hair.size(), tops.size(), skins.size(), sexes, ages])
	check(signatures.size() == records.size(), "no two of the 64 residents share (hair, hair colour, top, top colour)")
	check(hair.size() >= 8, "at least 8 hair styles among residents")
	check(tops.size() >= 7, "at least 7 garment silhouettes among residents")
	check(skins.size() >= 5, "a wide range of skin tones")
	var again := CharacterLook.for_resident(records[10])
	CharacterLook._resident_cache.clear()
	check(var_to_str(again) == var_to_str(CharacterLook.for_resident(records[10])), "resident looks are derived from the id alone")
	# styles
	for style in CharacterLook.STYLES:
		var colors := {}; var styles := {}
		for i in 8:
			var look := CharacterLook.from_seed(1000 + i, style, "")
			colors[look.top_color_name] = true; styles[look.hair] = true
		check(colors.size() >= 4 and styles.size() >= 4, "%s: 8 townsfolk use %d colours and %d hair styles" % [style, colors.size(), styles.size()])
	# meshes
	var started := Time.get_ticks_usec()
	var near_v := 0; var far_v := 0; var max_near := 0; var max_far := 0
	var weights_ok := true; var indices_ok := true
	for r in records:
		var look := CharacterLook.for_resident(r)
		var meshes := PersonBuilder.meshes(look)
		for which in ["near", "far"]:
			var mesh: ArrayMesh = meshes[which]
			var arrays := mesh.surface_get_arrays(0)
			var verts: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			if which == "near": near_v += verts; max_near = maxi(max_near, verts)
			else: far_v += verts; max_far = maxi(max_far, verts)
			if r == records[0] or r == records[37]:
				var w: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
				for v in range(0, w.size(), 4):
					if absf(w[v] + w[v + 1] + w[v + 2] + w[v + 3] - 1.0) > .001: weights_ok = false
				var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				for i in idx: if i < 0 or i >= verts: indices_ok = false
			if mesh.get_surface_count() != 1: check(false, "one surface (one draw call) per person")
	var elapsed := float(Time.get_ticks_usec() - started) / 1000.0
	print("MESHES: 64 residents built in %.0f ms (%.1f ms each); near avg %d (max %d) verts, far avg %d (max %d)" % [elapsed, elapsed / 64.0, near_v / 64, max_near, far_v / 64, max_far])
	check(weights_ok, "bone weights are normalised")
	check(indices_ok, "indices are in range")
	check(max_near < 22000 and max_far < 3000, "vertex budgets: near < 22k, far < 3k")
	# rig
	var person := RiderModel.new()
	person.look = CharacterLook.from_seed(7, &"valdoro", "farmer")
	root.add_child(person)
	await process_frame
	check(person.is_person() and person._skin_bridge._pivots.size() == 13, "townsperson binds all 13 pivots to the skin")
	check(person.hand_r != null and person.leg_l.get_node("Knee") != null and person.arm_l.get_node("Elbow/Hand") != null, "pivots keep the courier's names")
	check(is_equal_approx(person.scale.x, float(person.look.height)), "height applied as body scale")
	person.enable_resident_lod()
	person.set_resident_lod_distance(30.0)
	check(person.resident_lod_active and person._person_far.visible and not person._person_near.visible, "far mesh beyond 22 m")
	person.set_resident_lod_distance(10.0)
	check(not person.resident_lod_active and person._person_near.visible, "near mesh within 18 m")
	var before: Mesh = person._person_near.mesh
	CharacterLook.apply(person, CharacterLook.from_seed(8, &"sarmada", "vendor"))
	check(person._person_near.mesh != before and person._skin_bridge._pivots.size() == 13, "apply swaps the look on a live model")
	person.animate("walk", 1.3, .1)
	person.sync_resident_pose()
	var skeleton: Skeleton3D = person.find_child("Skeleton3D", true, false)
	var hand := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("Skin_HandR"))
	check(hand.origin.distance_to(person.hand_r.global_position) < .002, "hand bone follows the animated pivot")
	var spawned := CharacterLook.spawn(99, &"isola", "fisher")
	root.add_child(spawned)
	await process_frame
	check(spawned.is_person() and spawned.look.style == &"isola", "spawn builds a townsperson of a style")
	# background builds (streamed residents)
	var queued: Array = []
	for i in 4: queued.append(CharacterLook.from_seed(9000 + i, &"campo", "farmer"))
	for look in queued: PersonBuilder.request(look)
	var streamed := RiderModel.new(); streamed.look = queued[0]; streamed.async_build = true
	root.add_child(streamed)
	PersonBuilder.wait_all()
	var all_cached := true
	for look in queued: all_cached = all_cached and PersonBuilder.is_cached(look)
	check(all_cached and PersonBuilder.pending() == 0, "background builds finish and are committed")
	streamed._process(0.0)
	check(streamed._person_near.mesh != null, "a streamed townsperson appears once its meshes are ready")
	streamed.free()
	person.free(); spawned.free()
	print("CHARACTER LOOK failures: ", failures)
	quit(1 if failures else 0)
