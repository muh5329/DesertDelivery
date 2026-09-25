extends Node
## The imported trees on show: every model (TwistedTree_1-3, Pine_1-5) at its in-game kind and
## scale on a flat plaza floating 600 m up (nothing else in the way), each as the near model
## (WorldKit._tree_parts) and, beside it, as its far impostor (WorldKit.tree_impostor), drawn the
## way the scatters draw them (a one-instance MultiMesh per part). Views:
##   close  the trunk foot of an olive (TwistedTree_2) and of a pine (Pine_4) from 3 m
##   row    the near models from 30 m
##   pair   near model vs impostor side by side from 120 m (a long lens) and from the air
##   forest a 300 x 300 m stand of impostors seen from 400 m, from a hill and from above
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --audio-driver Dummy --rendering-driver vulkan -- \
##       --facet --test=tree_showcase --out=/tmp/trees [--views=close,row,pair,forest]
## Prints triangle counts per model (bark / leaves / impostor).

const Y := 600.0
const ORIGIN := Vector3(0.0, Y, -15000.0)
const MODELS := [["TwistedTree_1", "shade", 0.9], ["TwistedTree_2", "olive", 0.55], ["TwistedTree_3", "olive", 0.5],
	["Pine_1", "pine", 1.15], ["Pine_2", "pine", 1.2], ["Pine_3", "pine", 1.1], ["Pine_4", "pine", 1.1], ["Pine_5", "pine", 1.15]]
const SPACING := 16.0

var game: Game
var out := "/tmp/trees"
var cams: Array = []
var idx := 0
var frame := 0
var settle := 20
var cam: Camera3D


func _ready() -> void:
	game = Game.current
	out = game.cli.get_string("out", out)
	settle = game.cli.get_int("settle", 20)
	DirAccess.make_dir_recursive_absolute(out)
	game.hud.visible = false
	var ui := game.get_node_or_null("UI")
	if ui:
		for c in ui.get_children():
			if c is CanvasLayer or c is Control: c.visible = false
	game.bike.visible = false; game.player.visible = false
	if "truck" in game and game.truck: game.truck.visible = false
	var views: PackedStringArray = game.cli.get_string("views", "close,row,pair,forest").split(",", false)
	var root := Node3D.new(); root.name = "TreeShowcase"; add_child(root)
	_ground(root)
	for i in range(MODELS.size()):
		var m: Array = MODELS[i]
		var near := WorldKit._tree_parts(m[0], m[1], m[2])
		var far := WorldKit.tree_impostor(m[0], m[1], m[2])
		var x := ORIGIN.x + i * SPACING
		_spawn(root, near, [Transform3D(Basis(), Vector3(x, Y, ORIGIN.z))])
		_spawn(root, far, [Transform3D(Basis(), Vector3(x, Y, ORIGIN.z - 40.0))])
		var tris := []
		for p: WorldKit.PropPart in near: tris.append(_tris(p.mesh))
		print("TREE %-14s near parts %s tris, impostor %d tris" % [m[0], str(tris), _tris(far[0].mesh) if not far.is_empty() else -1])
	# a stand of impostors: the flora's mix of pines and broadleaves
	var rng := RandomNumberGenerator.new(); rng.seed = 7
	var stand: Dictionary = {}
	for j in range(40):
		for i in range(40):
			var p := ORIGIN + Vector3(-400.0 + i * 7.5 + rng.randf() * 7.5, 0.0, -600.0 + j * 7.5 + rng.randf() * 7.5)
			if rng.randf() > 0.7: continue
			var mi: int = [3, 4, 6, 7, 0, 2][rng.randi() % 6]
			var s := rng.randf_range(0.8, 1.3)
			if not stand.has(mi): stand[mi] = []
			stand[mi].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), p))
	for mi in stand:
		var m: Array = MODELS[mi]
		_spawn(root, WorldKit.tree_impostor(m[0], m[1], m[2]), stand[mi])
	var tw := ORIGIN + Vector3(0, 0, 0)
	for v in views:
		match v:
			"close":
				cams.append(["close_olive", Vector3(tw.x + SPACING - 2.2, Y + 1.4, tw.z + 2.6), Vector3(tw.x + SPACING, Y + 1.6, tw.z)])
				cams.append(["close_pine", Vector3(tw.x + 6 * SPACING - 2.0, Y + 1.5, tw.z + 2.4), Vector3(tw.x + 6 * SPACING, Y + 2.2, tw.z)])
				cams.append(["close_shade", Vector3(tw.x - 5.0, Y + 1.8, tw.z + 7.0), Vector3(tw.x + 1.0, Y + 5.0, tw.z)])
			"row":
				cams.append(["row", Vector3(tw.x + 56, Y + 8, tw.z + 40), Vector3(tw.x + 56, Y + 5, tw.z)])
			"pair":
				cams.append(["pair_side", Vector3(tw.x + 56 + 110, Y + 12, tw.z - 20), Vector3(tw.x + 56, Y + 6, tw.z - 20), 22.0])
				cams.append(["pair_air", Vector3(tw.x + 56, Y + 90, tw.z + 70), Vector3(tw.x + 56, Y, tw.z - 20), 40.0])
			"forest":
				cams.append(["forest_side", Vector3(tw.x - 250, Y + 30, tw.z + 60), Vector3(tw.x - 250, Y + 5, tw.z - 450)])
				cams.append(["forest_air", Vector3(tw.x - 250, Y + 420, tw.z + 150), Vector3(tw.x - 250, Y, tw.z - 450)])
	if cams.is_empty():
		get_tree().quit(); return
	cam = Camera3D.new(); cam.far = 20000; cam.near = 0.05
	add_child(cam); cam.current = true
	game.world.terrain.set_view_camera(cam)
	game.bike.place(ORIGIN + Vector3(0, 2, 30), Vector3(0, 0, -1))
	game.world.set_focus(game.bike)
	_place()


static func _tris(m: Mesh) -> int:
	if m == null or m.get_surface_count() == 0: return 0
	var a := m.surface_get_arrays(0)
	if a[Mesh.ARRAY_INDEX] != null: return (a[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3


func _spawn(root: Node3D, parts: Array, xforms: Array) -> void:
	for part: WorldKit.PropPart in parts:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D; mm.use_colors = true
		mm.mesh = part.mesh; mm.instance_count = xforms.size()
		for i in range(xforms.size()):
			mm.set_instance_transform(i, (xforms[i] as Transform3D) * part.xform)
			mm.set_instance_color(i, Color(1, 1, 1))
		var mmi := MultiMeshInstance3D.new(); mmi.multimesh = mm; mmi.material_override = part.mat
		root.add_child(mmi)


func _ground(root: Node3D) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(3000, 3000)
	mi.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.46, 0.5, 0.33)
	mat.roughness = 0.95
	mi.material_override = mat
	mi.position = Vector3(ORIGIN.x, Y - 0.02, ORIGIN.z)
	root.add_child(mi)


func _place() -> void:
	var from: Vector3 = cams[idx][1]; var at: Vector3 = cams[idx][2]
	cam.fov = float(cams[idx][3]) if cams[idx].size() > 3 else game.cli.get_float("fov", 62.0)
	cam.look_at_from_position(from, at, Vector3.UP)
	frame = 0


func _process(_d: float) -> void:
	frame += 1
	game.bike.global_position = ORIGIN + Vector3(0, 2, 30)
	if frame >= settle:
		var img := get_tree().root.get_texture().get_image()
		var p := "%s/%s.png" % [out, cams[idx][0]]
		img.save_png(p)
		print("saved ", p, "  draw calls %d, primitives %d" % [Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
		idx += 1
		if idx >= cams.size():
			get_tree().quit(); return
		_place()
