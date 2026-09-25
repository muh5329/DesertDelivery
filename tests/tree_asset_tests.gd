extends SceneTree
## The imported trees' assets: the procedural bark (world/mapgen/tree_bark.py) is closed tubes
## within budget, the leaf cards are untouched, and every model has its impostor.
##   godot --headless --path . -s tests/tree_asset_tests.gd
const MODELS := {"TwistedTree_1": 3000, "TwistedTree_2": 3000, "TwistedTree_3": 3000,
	"Pine_1": 900, "Pine_2": 900, "Pine_3": 900, "Pine_4": 900, "Pine_5": 900}
const LEAF_TRIS := {"TwistedTree_1": 2352, "TwistedTree_2": 2344, "TwistedTree_3": 2700,
	"Pine_1": 770, "Pine_2": 770, "Pine_3": 462, "Pine_4": 1210, "Pine_5": 1158}

var fails := 0


func _check(cond: bool, label: String) -> void:
	print(("PASS " if cond else "FAIL ") + label)
	if not cond: fails += 1


func _initialize() -> void:
	for model: String in MODELS:
		var parts := WorldKit._tree_parts(model, "olive", 1.0)
		_check(parts.size() == 2, "%s: bark + leaves (%d parts)" % [model, parts.size()])
		if parts.size() != 2: continue
		var bark: Mesh = null; var leaf: Mesh = null
		for p: WorldKit.PropPart in parts:
			if (p.mat as ShaderMaterial).shader.resource_path.ends_with("bark.gdshader"): bark = p.mesh
			else: leaf = p.mesh
		_check(bark != null and leaf != null, "%s: one bark and one leaf surface" % model)
		if bark == null or leaf == null: continue
		var a := bark.surface_get_arrays(0)
		var V: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var I: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		_check(I.size() / 3 <= MODELS[model], "%s: bark %d tris <= %d" % [model, I.size() / 3, MODELS[model]])
		_check((leaf.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3 == LEAF_TRIS[model], "%s: leaf cards untouched" % model)
		# closed: welded by position, every edge is shared by two triangles but the rings
		var weld: Dictionary = {}; var id := PackedInt32Array(); id.resize(V.size())
		for i in range(V.size()):
			var k := Vector3i(roundi(V[i].x * 2000.0), roundi(V[i].y * 2000.0), roundi(V[i].z * 2000.0))
			if not weld.has(k): weld[k] = weld.size()
			id[i] = weld[k]
		var edges: Dictionary = {}
		for t in range(0, I.size(), 3):
			for e in [[0, 1], [1, 2], [2, 0]]:
				var x := id[I[t + e[0]]]; var y := id[I[t + e[1]]]
				var key := Vector2i(mini(x, y), maxi(x, y))
				edges[key] = int(edges.get(key, 0)) + 1
		var open := 0
		for key: Vector2i in edges:
			if edges[key] == 1: open += 1
		var degenerate := 0
		for t in range(0, I.size(), 3):
			if (V[I[t + 1]] - V[I[t]]).cross(V[I[t + 2]] - V[I[t]]).length() < 1e-9: degenerate += 1
		_check(degenerate == 0, "%s: no degenerate bark triangles" % model)
		# the decimated trunks had ~1.5 open edges per triangle (a lattice of shards); the tubes are
		# open only at the buried foot, the limbs' mouths inside their parents and a side-count step
		_check(open < I.size() / 3 / 4, "%s: bark is closed tubes (%d open ring edges / %d tris)" % [model, open, I.size() / 3])
		var imp := WorldKit.tree_impostor(model, "pine", 1.0)
		_check(imp.size() == 1 and (imp[0].mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() == 18, "%s: impostor is one mesh of three cards" % model)
	print("TREE ASSETS: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)
