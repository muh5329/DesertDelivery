extends Node
## Rendering cost of townsfolk, old resident path (courier GLB + wardrobe primitives) against
## CharacterLook people, near (8 m, detailed meshes) and far (40 m, light meshes):
##   xvfb-run godot --path . --rendering-driver vulkan -- --facet --test=people_benchmark
## Prints draw calls, primitives and objects attributable to the people (a frame without
## them is subtracted), frame times, and mesh build cost.
const COUNT := 24
var game: Game
var camera: Camera3D
var stage: Node3D

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	game = Game.current
	game.use_scripted_controls(); game.hud.hide(); game.cam.set_physics_process(false)
	stage = Node3D.new(); add_child(stage); stage.position = Vector3(0, 700, 0)
	camera = Camera3D.new(); add_child(camera); camera.fov = 40.0; camera.current = true
	var results: Array = []
	for distance in [8.0, 40.0]:
		camera.look_at_from_position(Vector3(0, 701.6, -distance), Vector3(0, 700.9, 0))
		var empty := await _measure()
		for mode in ["old", "new"]:
			var people := _spawn(mode, distance)
			var m := await _measure()
			var row := {"mode": mode, "distance": distance,
				"draw_calls": m.draws - empty.draws, "primitives": m.prims - empty.prims, "objects": m.objects - empty.objects,
				"frame_ms": m.ms, "empty_frame_ms": empty.ms}
			results.append(row)
			print("PEOPLE BENCH %s @%dm: %d people -> %.0f draw calls (%.1f each), %.0f primitives (%.0f each), %.0f objects; frame %.1f ms (empty %.1f ms)" % [
				mode, int(distance), COUNT, row.draw_calls, row.draw_calls / COUNT, row.primitives, row.primitives / COUNT, row.objects, m.ms, empty.ms])
			people.free()
			for i in 3: await get_tree().process_frame
	print("PEOPLE BENCH build: %d looks, %.1f ms per person (near + far meshes)" % [PersonBuilder.builds, PersonBuilder.build_ms / maxf(PersonBuilder.builds, 1)])
	var file := FileAccess.open(game.cli.get_string("out", "/tmp/people_benchmark.json"), FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(results, "  "))
	get_tree().quit()

func _spawn(mode: String, distance: float) -> Node3D:
	var group := Node3D.new(); stage.add_child(group)
	var residents: Array[Resident] = game.life.residents
	for i in COUNT:
		var r: Resident = residents[i * 2]
		var person := RiderModel.new()
		if mode == "new": person.look = CharacterLook.for_resident(r)
		group.add_child(person)
		if mode == "old":
			person.set_palette(Color(r.palette[0]), Color(r.palette[1]), Color(r.palette[2]), Color(r.palette[3]))
			person.set_character_identity(r.id, r.occupation, r.palette)
		person.enable_resident_lod()
		person.set_resident_lod_distance(distance)
		person.position = Vector3((float(i % 8) - 3.5) * .9, 0, float(i / 8) * 1.2)
		person.animate("idle", 0.0, 1.0)
		person.sync_resident_pose()
	return group

func _measure() -> Dictionary:
	for i in 4: await get_tree().process_frame
	var draws := 0.0; var prims := 0.0; var objects := 0.0
	var frames := 20
	var started := Time.get_ticks_usec()
	for i in frames:
		await RenderingServer.frame_post_draw
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		objects += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	var ms := float(Time.get_ticks_usec() - started) / 1000.0 / frames
	return {"draws": draws / frames, "prims": prims / frames, "objects": objects / frames, "ms": ms}
