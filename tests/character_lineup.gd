extends Node
## Renders the townsfolk for review, in the running game (Forward+: add --facet in the cloud):
##   residents-front-1/2.png   16 residents side by side at 5 m, facing the camera
##   residents-34-1/2.png      the same 16 at three quarters
##   crowd-30m.png             40 residents milling at 30 m (far meshes)
##   crowd-60m.png             the same crowd at 60 m
##   style-<town>.png          8 townsfolk of each town style
##   faces-1/2.png             close-up faces
##   stride.png                mid-stride side view: skirts, robes, coats, aprons, long hair
##   courier.png               the player's courier beside three townsfolk
## --only=name,name limits the set.
var game: Game
var stage: Node3D
var camera: Camera3D
var out := "/tmp/characters"
var only: PackedStringArray = []

func _ready() -> void:
	call_deferred("capture")

func capture() -> void:
	game = Game.current
	game.use_scripted_controls(); game.hud.hide(); game.cam.set_physics_process(false)
	for layer in get_tree().root.find_children("*", "CanvasLayer", true, false):
		layer.visible = false
	out = game.cli.get_string("out", out)
	var o := game.cli.get_string("only", "")
	if o != "": only = o.split(",")
	DirAccess.make_dir_recursive_absolute(out)
	stage = Node3D.new(); add_child(stage); stage.position = Vector3(0, 500, 0)
	var ground := Mats.box(Vector3(160, .1, 160), Mats.solid(Color("cfc9b2")), Vector3(0, -.05, 0))
	stage.add_child(ground)
	camera = Camera3D.new(); add_child(camera); camera.fov = 40.0; camera.current = true
	camera.far = 400.0
	var residents: Array[Resident] = game.life.residents
	# 16 residents spread over every district: every fourth by id
	var sample: Array[Resident] = []
	for i in range(0, residents.size(), 4): sample.append(residents[i])
	if _want("residents"):
		for half in 2:
			var group := _row(sample.slice(half * 8, half * 8 + 8).map(func(r): return CharacterLook.for_resident(r)), .86)
			await _shot(group, Vector3(0, 501.45, -5.0), Vector3(0, 500.95, 0), "residents-front-%d" % (half + 1))
			for person in group.get_children(): if person is RiderModel: person.rotation.y = deg_to_rad(-35.0)
			await _shot(group, Vector3(0, 501.45, -5.0), Vector3(0, 500.95, 0), "residents-34-%d" % (half + 1))
			group.queue_free()
	if _want("crowd"):
		var crowd := Node3D.new(); stage.add_child(crowd)
		var rng := RandomNumberGenerator.new(); rng.seed = 7
		for i in 40:
			var person := RiderModel.new()
			person.look = CharacterLook.for_resident(residents[i])
			crowd.add_child(person)
			person.enable_resident_lod()
			var row := i / 8; var col := i % 8
			person.position = Vector3((float(col) - 3.5) * 1.3 + rng.randf_range(-.35, .35), 0, float(row) * 1.6 + rng.randf_range(-.4, .4))
			person.rotation.y = rng.randf_range(-PI, PI)
			var walking := i % 3 == 0
			person.animate("walk" if walking else "idle", 1.2, .12 + float(i) * .05)
			person.sync_resident_pose()
		for d in [30.0, 60.0]:
			for person in crowd.get_children(): person.set_resident_lod_distance(d)
			camera.fov = 11.0 if d > 40.0 else 20.0
			await _shot(crowd, Vector3(3, 500 + d * .12 + 1.6, -d), Vector3(0, 500.9, 3.0), "crowd-%dm" % int(d))
			camera.fov = 40.0
		crowd.queue_free()
	if _want("styles"):
		var jobs := {&"island": ["gardener", "baker", "merchant", "teacher", "fisher", "courier", "", ""],
			&"puerto": ["dockworker", "dockworker", "fisher", "merchant", "teacher", "baker", "", ""],
			&"valdoro": ["farmer", "shepherd", "baker", "merchant", "teacher", "stonemason", "", ""],
			&"sarmada": ["vendor", "weaver", "porter", "merchant", "baker", "", "", ""],
			&"isola": ["fisher", "fisher", "baker", "vendor", "", "", "", ""],
			&"campo": ["farmer", "farmer", "vendor", "mechanic", "baker", "", "", ""]}
		for style in CharacterLook.STYLES:
			var looks: Array = []
			for i in 8: looks.append(CharacterLook.from_seed(5000 + i * 31, style, jobs[style][i]))
			var group := _row(looks, .86)
			for person in group.get_children(): if person is RiderModel: person.rotation.y = deg_to_rad(-18.0)
			await _shot(group, Vector3(0, 501.45, -5.0), Vector3(0, 500.95, 0), "style-%s" % style)
			group.queue_free()
	if _want("faces"):
		for half in 2:
			var looks: Array = []
			for i in 5: looks.append(CharacterLook.for_resident(residents[(half * 5 + i) * 6 + 1]))
			var group := _row(looks, .42)
			for person in group.get_children(): if person is RiderModel: person.rotation.y = deg_to_rad(-12.0)
			camera.fov = 26.0
			await _shot(group, Vector3(0, 501.66, -2.6), Vector3(0, 501.6, 0), "faces-%d" % (half + 1))
			camera.fov = 40.0
			group.queue_free()
	if _want("stride"):
		var looks: Array = [CharacterLook.from_seed(11, &"sarmada", "vendor", "f"), CharacterLook.from_seed(3, &"isola", "", "f"),
			CharacterLook.from_seed(21, &"valdoro", "shepherd", "m"), CharacterLook.from_seed(40, &"island", "baker", "m"),
			CharacterLook.from_seed(52, &"puerto", "teacher", "f"), CharacterLook.from_seed(64, &"sarmada", "porter", "m")]
		# make sure the long garments are represented
		looks[0].top = "robe"; looks[0].hem = .09; looks[0].bottom = "none"
		looks[1].top = "dress"; looks[1].hem = .42; looks[1].bottom = "none"
		looks[2].top = "coat"; looks[2].hem = .5; looks[2].under = "shirt"; looks[3].apron = "bib"
		looks[4].top = "blouse"; looks[4].bottom = "skirt"; looks[4].hem = .38; looks[4].hair = "long_wavy"
		for l in looks: l.key = str(l.key) + "|stride"
		var group := _row(looks, 1.05)
		var phase := 0
		for person in group.get_children():
			if not person is RiderModel: continue
			person.rotation.y = PI * .5
			person.animate("walk", 1.3, .13 + .1 * phase)
			person.sync_resident_pose()
			phase += 1
		await _shot(group, Vector3(0, 501.2, -5.2), Vector3(0, 500.9, 0), "stride")
		for person in group.get_children():
			if not person is RiderModel: continue
			person.animate("walk", 1.3, .26)
			person.sync_resident_pose()
		await _shot(group, Vector3(0, 501.2, -5.2), Vector3(0, 500.9, 0), "stride-b")
		group.queue_free()
	if _want("courier"):
		var group := Node3D.new(); stage.add_child(group)
		var courier := RiderModel.new(); group.add_child(courier)
		courier.position = Vector3(-1.5, 0, 0)
		courier.animate("idle", 0, 1.0)
		var looks := [CharacterLook.for_resident(residents[5]), CharacterLook.for_resident(residents[18]), CharacterLook.for_resident(residents[43])]
		for i in 3:
			var person := RiderModel.new(); person.look = looks[i]; group.add_child(person)
			person.position = Vector3(-.5 + float(i) * 1.0, 0, 0)
			person.animate("idle", 0, 1.0)
		camera.fov = 30.0
		await _shot(group, Vector3(0, 501.5, -3.6), Vector3(0, 501.0, 0), "courier")
		camera.fov = 40.0
		group.queue_free()
	print("CHARACTER LINEUP: renders in ", out)
	get_tree().quit()

func _want(name: String) -> bool:
	return only.is_empty() or name in only

## A row of townsfolk facing the camera (-Z), spaced `gap` metres.
func _row(looks: Array, gap: float) -> Node3D:
	var group := Node3D.new(); stage.add_child(group)
	for i in looks.size():
		var person := RiderModel.new()
		person.look = looks[i]
		group.add_child(person)
		person.position = Vector3((float(i) - (looks.size() - 1) * .5) * gap, 0, 0)
		person.rotation.y = 0.0
		person.animate("idle", 0.0, 1.0)
		person.sync_resident_pose()
	return group

func _shot(_group: Node3D, eye: Vector3, target: Vector3, name: String) -> void:
	camera.look_at_from_position(eye, target)
	for frame in 6: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("RENDER ", name)
