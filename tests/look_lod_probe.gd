extends Node
## m-6 probe: the far silhouettes' mesh (BuildingKit.build_lod) for one town - surfaces, their
## materials, and a sample of wall normals / vertex colours.
## Run: godot --headless --path . -- --test=look_lod_probe [--town=puerto_alto]


func _ready() -> void:
	var game: Game = Game.current
	var outer: OuterWorld = game.world.outer
	var want := game.cli.get_string("town", "puerto_alto")
	for t: Dictionary in outer.plan().towns:
		if String(t.id) != want: continue
		var mesh: Mesh = BuildingKit.build_lod(t.plots.slice(0, 40))
		print("[lod] surfaces %d" % mesh.get_surface_count())
		for s in range(mesh.get_surface_count()):
			var mat := mesh.surface_get_material(s)
			var arr := mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var c: PackedColorArray = arr[Mesh.ARRAY_COLOR] if arr[Mesh.ARRAY_COLOR] != null else PackedColorArray()
			print("[lod] surface %d: %d verts, material %s (%s), colours %d" % [s, v.size(), mat, mat.shader.resource_path if mat is ShaderMaterial and mat.shader else "-", c.size()])
			for i in range(0, mini(v.size(), 60), 6):
				print("[lod]   v %s n %s c %s" % [v[i], n[i] if i < n.size() else Vector3.ZERO, c[i] if i < c.size() else Color()])
	for c in outer.get_children():
		if c.name == "OuterTowns" or c is OuterTowns:
			var cells: Dictionary = c.lod_cells
			var k = cells.keys()[0]
			var mi: MeshInstance3D = cells[k]
			print("[lod] cell %s: override %s, surface material %s" % [k, mi.material_override, mi.mesh.surface_get_material(0) if mi.mesh.get_surface_count() > 0 else null])
	get_tree().quit(0)
