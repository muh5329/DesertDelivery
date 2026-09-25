class_name CargoLoadView
extends Node3D
## What an Inventory looks like on a load bed: a fixed grid of slots, each showing one stack of
## one kind of thing — crates, sacks, barrels, planks, logs, stone blocks, cloth bolts, fuel cans,
## ammunition crates — drawn from one MultiMesh pool per part (Red Sea Baron's CartVisual kept
## three pools for up to eight crates; the same idea with a pool per look). The exact contents
## stay in the Inventory; this only shows roughly how much of what is aboard.
##
##   setup(slots, slot_mass)   slot centres (bed-top, local) and the kg one stack stands for
##   show_inventory(inv)       redraw from an Inventory (call on `changed`)
##   set_parcel_visible(v)     the courier's parcel rides in the first free slot

var slots: Array[Vector3] = []
var slot_mass := 20.0
var used_slots := 0
var shown: Dictionary = {}        ## look -> stacks drawn (for tests)
var _pools: Dictionary = {}       ## look -> Array of {mmi, parts: Array[Transform3D]}
var _parcel: Node3D
var _parcel_on := false
var _last: Dictionary = {}

## look -> parts: [mesh kind, size, colour source ("item" tints with the good's colour), offsets]
const PARTS := {
	"crate": [["box", Vector3(0.54, 0.40, 0.50), "wood", [Vector3(0, 0.20, 0)]],
		["box", Vector3(0.56, 0.07, 0.52), "item", [Vector3(0, 0.30, 0)]],
		["box", Vector3(0.07, 0.42, 0.52), "band", [Vector3(0, 0.20, 0)]]],
	"sack": [["sphere", Vector3(0.50, 0.40, 0.46), "burlap", [Vector3(0, 0.19, 0)]],
		["box", Vector3(0.20, 0.06, 0.20), "item", [Vector3(0, 0.38, 0)]]],
	"barrel": [["cyl", Vector3(0.21, 0.46, 0.21), "oak", [Vector3(0, 0.23, -0.13), Vector3(0, 0.23, 0.13)]],
		["cyl", Vector3(0.225, 0.04, 0.225), "hoop", [Vector3(0, 0.36, -0.13), Vector3(0, 0.36, 0.13), Vector3(0, 0.10, -0.13), Vector3(0, 0.10, 0.13)]],
		["cyl", Vector3(0.16, 0.012, 0.16), "item", [Vector3(0, 0.463, -0.13), Vector3(0, 0.463, 0.13)]]],
	"planks": [["box", Vector3(0.56, 0.08, 0.54), "plank", [Vector3(0, 0.05, 0), Vector3(0, 0.15, 0), Vector3(0, 0.25, 0)]],
		["box", Vector3(0.05, 0.31, 0.56), "band", [Vector3(-0.18, 0.15, 0), Vector3(0.18, 0.15, 0)]]],
	"logs": [["logz", Vector3(0.10, 0.54, 0.10), "bark", [Vector3(-0.17, 0.10, 0), Vector3(0.0, 0.10, 0), Vector3(0.17, 0.10, 0), Vector3(-0.085, 0.27, 0), Vector3(0.085, 0.27, 0)]]],
	"blocks": [["box", Vector3(0.25, 0.22, 0.24), "item", [Vector3(-0.14, 0.11, -0.13), Vector3(0.14, 0.11, -0.13), Vector3(-0.14, 0.11, 0.13), Vector3(0.14, 0.11, 0.13), Vector3(0, 0.33, 0)]]],
	"bolt": [["logx", Vector3(0.09, 0.52, 0.09), "item", [Vector3(0, 0.09, -0.17), Vector3(0, 0.09, 0.0), Vector3(0, 0.09, 0.17), Vector3(0, 0.25, -0.085), Vector3(0, 0.25, 0.085)]]],
	"can": [["box", Vector3(0.17, 0.34, 0.26), "item", [Vector3(-0.12, 0.17, -0.10), Vector3(0.12, 0.17, -0.10), Vector3(-0.12, 0.17, 0.18), Vector3(0.12, 0.17, 0.18)]],
		["box", Vector3(0.05, 0.06, 0.10), "band", [Vector3(-0.12, 0.37, -0.16), Vector3(0.12, 0.37, -0.16), Vector3(-0.12, 0.37, 0.12), Vector3(0.12, 0.37, 0.12)]]],
	"ammo": [["box", Vector3(0.50, 0.26, 0.34), "item", [Vector3(0, 0.13, -0.10), Vector3(0, 0.40, 0.02)]],
		["box", Vector3(0.20, 0.06, 0.345), "stencil", [Vector3(0, 0.13, -0.10), Vector3(0, 0.40, 0.02)]]],
}
const TONES := {
	"wood": Color("a57a4b"), "band": Color("4a3a28"), "burlap": Color("b89c6a"), "oak": Color("7a5232"),
	"hoop": Color("3e3a36"), "plank": Color("c79a5f"), "bark": Color("6e5238"), "stencil": Color("d8cfa4"),
}


func setup(p_slots: Array[Vector3], p_slot_mass: float) -> void:
	slots = p_slots
	slot_mass = p_slot_mass
	for look: String in PARTS:
		var list: Array = []
		for part: Array in PARTS[look]:
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "%s_%s" % [look, part[2]]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.mesh = _mesh(String(part[0]), part[1])
			var offsets: Array = part[3]
			mm.instance_count = slots.size() * offsets.size()
			mm.visible_instance_count = 0
			mmi.multimesh = mm
			var mat := StandardMaterial3D.new()
			mat.vertex_color_use_as_albedo = true
			mat.roughness = 0.85
			mmi.material_override = mat
			add_child(mmi)
			list.append({"mmi": mmi, "offsets": offsets, "tone": String(part[2])})
		_pools[look] = list
	_parcel = Node3D.new(); _parcel.name = "Parcel"; add_child(_parcel)
	var paper := Mats.solid(Color(0.72, 0.55, 0.34), 0.9)
	var twine := Mats.solid(Color(0.91, 0.78, 0.48), 0.85)
	_parcel.add_child(Mats.box(Vector3(0.52, 0.36, 0.46), paper, Vector3(0, 0.18, 0)))
	_parcel.add_child(Mats.box(Vector3(0.05, 0.37, 0.47), twine, Vector3(0, 0.18, 0)))
	_parcel.add_child(Mats.box(Vector3(0.53, 0.05, 0.47), twine, Vector3(0, 0.30, 0)))
	_parcel.visible = false


func _mesh(kind: String, size: Vector3) -> Mesh:
	match kind:
		"sphere":
			var s := SphereMesh.new(); s.radius = 0.5; s.height = 1.0; s.radial_segments = 10; s.rings = 6
			var arr := s.get_mesh_arrays()
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for i in verts.size(): verts[i] = Vector3(verts[i].x * size.x, verts[i].y * size.y, verts[i].z * size.z)
			arr[Mesh.ARRAY_VERTEX] = verts
			var am := ArrayMesh.new(); am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			return am
		"cyl", "logz", "logx":
			var c := CylinderMesh.new(); c.top_radius = size.x; c.bottom_radius = size.x; c.height = size.y
			c.radial_segments = 10; c.rings = 1
			if kind == "cyl": return c
			var arr := c.get_mesh_arrays()
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var rot := Basis(Vector3.RIGHT, PI * 0.5) if kind == "logz" else Basis(Vector3.BACK, PI * 0.5)
			for i in verts.size():
				verts[i] = rot * verts[i]; norms[i] = rot * norms[i]
			arr[Mesh.ARRAY_VERTEX] = verts; arr[Mesh.ARRAY_NORMAL] = norms
			var am := ArrayMesh.new(); am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			return am
	var b := BoxMesh.new(); b.size = size
	return b


## Decide the stacks: the heaviest goods first, one stack per `slot_mass` kg (at least one for
## anything aboard), until the bed is full.
func show_inventory(inv: Inventory) -> void:
	var contents := inv.contents() if inv else {}
	var order: Array = contents.keys()
	order.sort_custom(func(a, b): return ItemDefinition.get_item(a).mass * contents[a] > ItemDefinition.get_item(b).mass * contents[b])
	var plan: Array = []                 # [look, colour] per slot
	var free := slots.size() - (1 if _parcel_on else 0)
	for id: String in order:
		var item := ItemDefinition.get_item(id)
		var stacks := maxi(1, ceili(item.mass * int(contents[id]) / slot_mass))
		for i in stacks:
			if plan.size() >= free: break
			plan.append([item.look, item.colour])
	_last = contents
	used_slots = plan.size()
	shown.clear()
	var per_look: Dictionary = {}
	for i in plan.size():
		var look: String = plan[i][0]
		if not per_look.has(look): per_look[look] = []
		per_look[look].append([i, plan[i][1]])
		shown[look] = int(shown.get(look, 0)) + 1
	for look: String in _pools:
		var entries: Array = per_look.get(look, [])
		for pool: Dictionary in _pools[look]:
			var mm: MultiMesh = (pool.mmi as MultiMeshInstance3D).multimesh
			var offsets: Array = pool.offsets
			var n := 0
			for e: Array in entries:
				var at: Vector3 = slots[int(e[0])]
				var tone: String = pool.tone
				var col: Color = e[1] if tone == "item" else TONES.get(tone, Color.WHITE)
				for o: Vector3 in offsets:
					mm.set_instance_transform(n, Transform3D(Basis.IDENTITY, at + o))
					mm.set_instance_color(n, col)
					n += 1
			mm.visible_instance_count = n
	if _parcel_on and slots.size() > 0:
		_parcel.position = slots[mini(used_slots, slots.size() - 1)]


func set_parcel_visible(v: bool) -> void:
	if v == _parcel_on and _parcel.visible == v: return
	_parcel_on = v
	_parcel.visible = v
	var inv := Inventory.new(1e9)
	inv.restore_contents(_last)
	show_inventory(inv)


func parcel_visible() -> bool:
	return _parcel_on
