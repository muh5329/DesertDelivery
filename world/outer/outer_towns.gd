class_name OuterTowns
extends Node3D
## The towns, hamlets and landmarks of the outer world (plan.json), as WorldDatabase content:
##   - every town and hamlet is a named location (its delivery ring is on the plaza);
##   - its building plots are filed per 60 m chunk as recipes (groups of <= 6 plots) that the
##     WorldStreamer builds near the focus: BuildingKit.build_group() when the architecture kit
##     exists (res://world/kit/building_kit.gd), otherwise a simple placeholder (box, pitched or
##     flat roof, plinth, per-style colours) with box collision;
##   - street lamps along the town streets, landmarks (lighthouses, cranes, the dam, the castle
##     ruins, viewpoints, chapels...) and junction signposts are recipes too;
##   - a far silhouette per chunk (merged boxes, or BuildingKit.build_lod) is resident and hidden
##     while the chunk with the real buildings is loaded; a merged whole-town mesh takes over
##     beyond 2.5 km, so towns read from anywhere on the map.

const KIT_PATH := "res://world/kit/building_kit.gd"
const GROUP := 6
const FLOOR_H := 3.1
const STYLE_WALLS := {
	"puerto": [Color("e8d9b8"), Color("e7b98e"), Color("d9a3a0"), Color("c9d6d8"), Color("f1ece0"), Color("e3c46f")],
	"valdoro": [Color("a39f95"), Color("8f8b82"), Color("b5aa98"), Color("9c9384")],
	"sarmada": [Color("f2ede2"), Color("eadcc0"), Color("d9b98a"), Color("e8d2a8")],
	"isola": [Color("f0b9b0"), Color("f3dc93"), Color("a9cbe0"), Color("bfe0c0"), Color("f4efe6"), Color("e8a98a")],
	"campo": [Color("e9dcc0"), Color("dcc39a"), Color("efe6d2"), Color("cfae84")],
}
const STYLE_ROOFS := {
	"puerto": [Color("b0553a"), Color("a0482f"), Color("bd6a48")],
	"valdoro": [Color("4b4f55"), Color("5a5d60"), Color("3f4347")],
	"sarmada": [Color("e8e0cf")],
	"isola": [Color("f2ede4"), Color("c9674a")],
	"campo": [Color("b86243"), Color("a8573b"), Color("c2744f")],
}

var outer: OuterWorld
var db: WorldDatabase
var kit: WorldKit
var building_kit: Script = null
var lod_root: Node3D
var lod_cells: Dictionary = {}      # Vector2i chunk -> MeshInstance3D
var town_lods: Array = []
var plot_count := 0
var recipe_count := 0
var locations: Array[StringName] = []
var names: Dictionary = {}          # id -> display name
var props: OuterProps
var _mat_cache: StandardMaterial3D
var _lamp_mm_mesh: ArrayMesh
var _kit_methods: Dictionary = {}


func setup(p_outer: OuterWorld, p_db: WorldDatabase, p_kit: WorldKit) -> void:
	outer = p_outer; db = p_db; kit = p_kit
	name = "OuterTowns"
	if ResourceLoader.exists(KIT_PATH):
		var s = load(KIT_PATH)
		if s is Script: building_kit = s
	if _kit_has("warm"): building_kit.call("warm")      # decode the kit's textures in the background
	lod_root = Node3D.new(); lod_root.name = "TownSilhouettes"; add_child(lod_root)
	var plan: Dictionary = outer.ground.plan
	for group in ["towns", "hamlets"]:
		for t: Dictionary in plan.get(group, []):
			names[t.id] = t.name
			_define_town(t)
	for lm: Dictionary in plan.get("landmarks", []):
		_define_landmark(lm)
	_define_signposts()
	props = OuterProps.new()
	props.setup(outer, db, kit)
	if Events.has_signal("chunk_loaded"):
		Events.chunk_loaded.connect(_on_chunk_loaded)
		Events.chunk_unloaded.connect(_on_chunk_unloaded)


## Does the architecture kit script define this (static) function?
func _kit_has(method: String) -> bool:
	if building_kit == null: return false
	if _kit_methods.is_empty():
		for m in building_kit.get_script_method_list(): _kit_methods[m.name] = true
	return _kit_methods.has(method)


# ---------------------------------------------------------------- towns
func _define_town(t: Dictionary) -> void:
	var pz: Array = t.plaza if t.plaza != null else [t.center[0], 0.0, t.center[1]]
	var pos := Vector3(pz[0], pz[1], pz[2])
	pos.y = outer.height_at(pos.x, pos.z)
	var id := StringName(t.id)
	db.add_location(id, pos, Vector3(0, 0, 1), t.name)
	locations.append(id)
	# party walls: which sides of each plot touch a neighbour (rows share walls, no eaves there)
	if _kit_has("annotate"): building_kit.call("annotate", t.plots)
	# plots per chunk, in groups
	var per_chunk: Dictionary = {}
	for p: Dictionary in t.plots:
		var c := db.chunk_of(p.x, p.z)
		if not per_chunk.has(c): per_chunk[c] = []
		per_chunk[c].append(p)
		plot_count += 1
	for c: Vector2i in per_chunk:
		var plots: Array = per_chunk[c]
		for g in range(0, plots.size(), GROUP):
			var group: Array = plots.slice(g, g + GROUP)
			var centre := Vector2.ZERO
			for p in group: centre += Vector2(p.x, p.z)
			centre /= group.size()
			# the extent: the corners of the axis-aligned box round every footprint (what a merged
			# mesh's AABB covers), plus room for eaves and the kit's own detailing
			var box := Rect2(centre, Vector2.ZERO)
			for p in group:
				var yaw := deg_to_rad(float(p.yaw))
				var f := Vector2(sin(yaw), cos(yaw)); var tt := Vector2(f.y, -f.x)
				for sx in [-1.0, 1.0]:
					for sy in [-1.0, 1.0]:
						box = box.expand(Vector2(p.x, p.z) + tt * sx * (float(p.w) * 0.5 + 1.0) + f * sy * (float(p.d) * 0.5 + 1.0))
			var reach := 4.0
			for corner in [box.position, box.end, Vector2(box.position.x, box.end.y), Vector2(box.end.x, box.position.y)]:
				reach = maxf(reach, (corner as Vector2).distance_to(centre) + 4.0)
			db.add(centre.x, centre.y, func(): _build_plots(kit.sink, group), reach)
			recipe_count += 1
		_build_lod_cell(c, plots)
	_define_lamps(t)
	_build_town_lod(t)
	_define_counter(t, pos)


func _build_plots(parent: Node3D, plots: Array) -> void:
	if parent == null: return
	var origin := parent.global_position if parent.is_inside_tree() else Vector3.ZERO
	if _kit_has("build_group"):
		building_kit.call("build_group", parent, plots, origin)
		return
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body := StaticBody3D.new(); body.collision_layer = 1; body.name = "Plots"
	for p: Dictionary in plots:
		_placeholder(st, p, origin, body)
	var mi := MeshInstance3D.new(); mi.name = "PlaceholderBuildings"
	mi.mesh = st.commit(); mi.material_override = _vertex_colour_material()
	parent.add_child(mi); parent.add_child(body)


## The fallback building: a plinth down to the lowest ground under the plot, the walls (floors x
## 3.1 m) and a roof by style; walls, gates and towers as plain masses.
func _placeholder(st: SurfaceTool, p: Dictionary, origin: Vector3, body: StaticBody3D) -> void:
	var rng := RandomNumberGenerator.new(); rng.seed = int(p.seed)
	var style: String = p.style
	var kind: String = p.kind
	var w: float = p.w; var d: float = p.d
	var floors: int = int(p.floors)
	var y: float = p.y
	var g0: float = float(p.get("ground_min", y)) - 0.4
	var yaw := deg_to_rad(float(p.yaw))
	var basis := Basis(Vector3.UP, yaw)
	var c := Vector3(p.x, 0.0, p.z) - origin
	var walls: Array = STYLE_WALLS.get(style, STYLE_WALLS.campo)
	var roofs: Array = STYLE_ROOFS.get(style, STYLE_ROOFS.campo)
	var wall: Color = walls[rng.randi_range(0, walls.size() - 1)]
	var roof: Color = roofs[rng.randi_range(0, roofs.size() - 1)]
	var h := floors * FLOOR_H
	var flat_roof: bool = style == "sarmada" or "terrace" in p.tags or kind in ["wall", "gate", "citadel", "tower"] and style != "valdoro"
	match kind:
		"wall": h = floors * 2.6; wall = walls[0].darkened(0.15)
		"gate": h = floors * 3.2; wall = walls[0].darkened(0.1)
		"tower": h = floors * 3.6
		"church": h = maxf(h, 9.0)
		"lighthouse": h = 22.0; wall = Color("f2f0ea")
		"windmill": h = 10.0; wall = Color("f0ebe0")
		"barn": wall = Color("8a5a3c"); roof = Color("6b4a36")
		"granary": wall = Color("d8c7a0")
		"boathouse": h = 3.2; wall = walls[rng.randi_range(0, walls.size() - 1)]
		"warehouse": wall = wall.darkened(0.12)
	var base_y := minf(g0, y - 0.2)
	# plinth + walls in one box from the ground to the eaves
	_box(st, c + Vector3(0, (base_y + y + h) * 0.5, 0), Vector3(w, y + h - base_y, d), basis, wall, Color(wall.darkened(0.25)), y - base_y)
	var top := y + h
	if kind == "church" and style == "puerto":
		_dome(st, c + Vector3(0, top, 0), minf(w, d) * 0.36, Color("d8d2c4"))
	elif kind in ["tower", "lighthouse"] and style != "sarmada":
		_pyramid(st, c + Vector3(0, top, 0), Vector3(w * 1.1, 3.0, d * 1.1), basis, roof)
	elif flat_roof:
		_box(st, c + Vector3(0, top + 0.4, 0), Vector3(w + 0.2, 0.8, d + 0.2), basis, wall.lightened(0.05), wall, 0.0)
	else:
		_gable(st, c + Vector3(0, top, 0), Vector3(w + 0.6, clampf(minf(w, d) * 0.35, 1.5, 4.5), d + 0.6), basis, roof)
	var cs := CollisionShape3D.new(); var sh := BoxShape3D.new()
	sh.size = Vector3(w, top - base_y, d); cs.shape = sh
	cs.transform = Transform3D(basis, c + Vector3(0, (base_y + top) * 0.5, 0))
	body.add_child(cs)


static func _box(st: SurfaceTool, c: Vector3, s: Vector3, b: Basis, col: Color, low_col: Color, low_h: float) -> void:
	var h := s * 0.5
	var corners := []
	for v in [Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, 1, -1), Vector3(-1, 1, -1), Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(-1, 1, 1)]:
		corners.append(c + b * (v * h))
	var faces := [[0, 3, 2, 1, Vector3(0, 0, -1)], [4, 5, 6, 7, Vector3(0, 0, 1)], [0, 4, 7, 3, Vector3(-1, 0, 0)],
		[1, 2, 6, 5, Vector3(1, 0, 0)], [3, 7, 6, 2, Vector3(0, 1, 0)]]
	var split := c.y - h.y + low_h
	for f in faces:
		var n: Vector3 = b * (f[4] as Vector3)
		for i in [0, 2, 1, 0, 3, 2]:
			var v: Vector3 = corners[f[i]]
			st.set_normal(n); st.set_color(low_col if v.y < split + 0.01 and low_h > 0.3 and f[4] != Vector3(0, 1, 0) and v.y < c.y - h.y + 0.01 else col)
			st.add_vertex(v)


static func _gable(st: SurfaceTool, c: Vector3, s: Vector3, b: Basis, col: Color) -> void:
	# ridge along the longer side
	var along_x := s.x >= s.z
	var hx := s.x * 0.5; var hz := s.z * 0.5
	var r0: Vector3; var r1: Vector3
	var p := [Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(hx, 0, hz), Vector3(-hx, 0, hz)]
	if along_x:
		r0 = Vector3(-hx, s.y, 0); r1 = Vector3(hx, s.y, 0)
		_tri_list(st, c, b, col, [[p[0], r0, r1], [p[0], r1, p[1]], [p[2], r1, r0], [p[2], r0, p[3]], [p[3], r0, p[0]], [p[1], r1, p[2]]])
	else:
		r0 = Vector3(0, s.y, -hz); r1 = Vector3(0, s.y, hz)
		_tri_list(st, c, b, col, [[p[1], r0, r1], [p[1], r1, p[2]], [p[3], r1, r0], [p[3], r0, p[0]], [p[0], r0, p[1]], [p[2], r1, p[3]]])


static func _pyramid(st: SurfaceTool, c: Vector3, s: Vector3, b: Basis, col: Color) -> void:
	var hx := s.x * 0.5; var hz := s.z * 0.5
	var p := [Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(hx, 0, hz), Vector3(-hx, 0, hz)]
	var apex := Vector3(0, s.y, 0)
	_tri_list(st, c, b, col, [[p[0], apex, p[1]], [p[1], apex, p[2]], [p[2], apex, p[3]], [p[3], apex, p[0]]])


static func _dome(st: SurfaceTool, c: Vector3, r: float, col: Color) -> void:
	var seg := 12; var rings := 5
	for i in range(rings):
		var a0 := PI * 0.5 * i / rings; var a1 := PI * 0.5 * (i + 1) / rings
		for j in range(seg):
			var t0 := TAU * j / seg; var t1 := TAU * (j + 1) / seg
			var v := [Vector3(cos(a0) * cos(t0), sin(a0), cos(a0) * sin(t0)), Vector3(cos(a0) * cos(t1), sin(a0), cos(a0) * sin(t1)),
				Vector3(cos(a1) * cos(t1), sin(a1), cos(a1) * sin(t1)), Vector3(cos(a1) * cos(t0), sin(a1), cos(a1) * sin(t0))]
			for k in [0, 2, 1, 0, 3, 2, 0, 1, 2, 0, 2, 3]:
				st.set_normal(v[k]); st.set_color(col); st.add_vertex(c + v[k] * r + Vector3(0, r * 0.3, 0))
	# the drum under the dome
	for j in range(seg):
		var t0 := TAU * j / seg; var t1 := TAU * (j + 1) / seg
		var a := Vector3(cos(t0), 0, sin(t0)) * r; var b2 := Vector3(cos(t1), 0, sin(t1)) * r
		var up := Vector3(0, r * 0.3, 0)
		for v in [a, b2 + up, b2, a, a + up, b2 + up, a, b2, b2 + up, a, b2 + up, a + up]:
			st.set_normal(Vector3(v.x, 0, v.z).normalized()); st.set_color(col.darkened(0.08)); st.add_vertex(c + v)


static func _tri_list(st: SurfaceTool, c: Vector3, b: Basis, col: Color, tris: Array) -> void:
	for t in tris:
		var a: Vector3 = c + b * (t[0] as Vector3); var bb: Vector3 = c + b * (t[1] as Vector3); var cc: Vector3 = c + b * (t[2] as Vector3)
		var n := (bb - a).cross(cc - a).normalized()
		if n.y < 0.0 and absf(n.y) > 0.3: n = -n
		for v in [a, bb, cc]:
			st.set_normal(n); st.set_color(col); st.add_vertex(v)
		for v in [a, cc, bb]:
			st.set_normal(-n); st.set_color(col); st.add_vertex(v)


func _vertex_colour_material() -> StandardMaterial3D:
	if _mat_cache: return _mat_cache
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.9
	if ResourceLoader.exists("res://assets/storybook/gouache_surface.png"):
		m.albedo_texture = load("res://assets/storybook/gouache_surface.png")
		m.uv1_triplanar = true; m.uv1_scale = Vector3(0.12, 0.12, 0.12)
	_mat_cache = m
	return m


## The red courier counter beside the plaza ring, like the core's pickup locations have.
func _define_counter(t: Dictionary, ring: Vector3) -> void:
	var road := outer.terrain.nearest_road(ring)
	var out: Vector3 = ring - road.point; out.y = 0.0
	if out.length() < 0.5: out = Vector3(-road.tangent.z, 0, road.tangent.x)
	out = out.normalized()
	var p := ring + out * 6.0 + Vector3(road.tangent.x, 0, road.tangent.z) * 3.0
	p.y = outer.height_at(p.x, p.z)
	var yaw := atan2(out.x, out.z)
	db.add(p.x, p.z, func(): kit._courier_counter(kit.sink, p - (kit.sink.global_position if kit.sink and kit.sink.is_inside_tree() else Vector3.ZERO), yaw))


# ---------------------------------------------------------------- far silhouettes
func _lod_mesh(plots: Array, origin: Vector3) -> Mesh:
	if _kit_has("build_lod"):
		var m = building_kit.call("build_lod", plots)
		if m is Mesh: return m
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body := StaticBody3D.new()
	for p: Dictionary in plots: _placeholder(st, p, origin, body)
	body.free()
	return st.commit()


func _build_lod_cell(c: Vector2i, plots: Array) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Lod_%d_%d" % [c.x, c.y]
	mi.mesh = _lod_mesh(plots, Vector3.ZERO)
	mi.material_override = _vertex_colour_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 2600.0
	lod_root.add_child(mi)
	lod_cells[c] = mi


func _build_town_lod(t: Dictionary) -> void:
	if t.plots.is_empty(): return
	var mi := MeshInstance3D.new()
	mi.name = "TownLod_%s" % t.id
	mi.mesh = _lod_mesh(t.plots, Vector3.ZERO)
	mi.material_override = _vertex_colour_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_begin = 2400.0
	mi.visibility_range_end = 16000.0
	lod_root.add_child(mi)
	town_lods.append(mi)


func _on_chunk_loaded(c: Vector2i) -> void:
	if lod_cells.has(c): lod_cells[c].visible = false


func _on_chunk_unloaded(c: Vector2i) -> void:
	if lod_cells.has(c): lod_cells[c].visible = true


# ---------------------------------------------------------------- street lamps
func _define_lamps(t: Dictionary) -> void:
	var per_chunk: Dictionary = {}
	for st: Dictionary in t.streets:
		if st.kind == "plaza": continue
		var pts: Array = st.points
		var acc := 0.0; var side := 1.0
		for k in range(1, pts.size()):
			var a := Vector3(pts[k - 1][0], pts[k - 1][1], pts[k - 1][2]); var b := Vector3(pts[k][0], pts[k][1], pts[k][2])
			acc += a.distance_to(b)
			if acc < 30.0: continue
			acc = 0.0; side = -side
			var tan := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
			var q := b + Vector3(-tan.z, 0, tan.x) * side * (float(st.width) * 0.5 + 0.7)
			q.y = outer.height_at(q.x, q.z)
			var c := db.chunk_of(q.x, q.z)
			if not per_chunk.has(c): per_chunk[c] = []
			per_chunk[c].append(q)
	for c: Vector2i in per_chunk:
		var pts: Array = per_chunk[c]
		var o := db.chunk_origin(c) + Vector3(db.chunk_size * 0.5, 0, db.chunk_size * 0.5)
		db.add(o.x, o.z, func(): _build_lamps(kit.sink, pts))


func _build_lamps(parent: Node3D, pts: Array) -> void:
	var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _lamp_mesh(); mm.instance_count = pts.size()
	var origin := parent.global_position if parent.is_inside_tree() else Vector3.ZERO
	for i in range(pts.size()): mm.set_instance_transform(i, Transform3D(Basis(), (pts[i] as Vector3) - origin))
	var mmi := MultiMeshInstance3D.new(); mmi.multimesh = mm; mmi.name = "StreetLamps"
	mmi.visibility_range_end = 260.0
	parent.add_child(mmi)


func _lamp_mesh() -> ArrayMesh:
	if _lamp_mm_mesh: return _lamp_mm_mesh
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	OuterRoads._box(st, Vector3(0, 1.9, 0), Vector3(0.1, 3.8, 0.1))
	OuterRoads._box(st, Vector3(0, 0.1, 0), Vector3(0.3, 0.2, 0.3))
	var m := st.commit()
	var st2 := SurfaceTool.new(); st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	OuterRoads._box(st2, Vector3(0, 3.95, 0), Vector3(0.34, 0.42, 0.34))
	st2.commit(m)
	var iron := StandardMaterial3D.new(); iron.albedo_color = Color(0.15, 0.15, 0.16); iron.metallic = 0.3; iron.roughness = 0.6
	var glow := StandardMaterial3D.new(); glow.albedo_color = Color(1.0, 0.92, 0.7); glow.emission_enabled = true
	glow.emission = Color(1.0, 0.8, 0.45); glow.emission_energy_multiplier = 0.5
	m.surface_set_material(0, iron); m.surface_set_material(1, glow)
	_lamp_mm_mesh = m
	return m


# ---------------------------------------------------------------- landmarks
func _define_landmark(lm: Dictionary) -> void:
	var pos := Vector3(lm.pos[0], lm.pos[1], lm.pos[2])
	var yaw: float = lm.get("yaw_deg", 0.0)
	var kind: String = lm.kind
	var reach := 30.0
	match kind:
		"dam": reach = 170.0
		"castle_ruin", "monastery": reach = 40.0
		"oasis", "windmill_site": return
	if kind in ["lighthouse", "castle_ruin", "monastery", "chapel", "viewpoint", "hut", "watchtower", "dam", "gatehouse"]:
		var lid := StringName(String(lm.id).replace(".", "_"))
		# the ring at the road's end; the building stands beside it (outer.py site_landmarks)
		var ring := Vector3(lm.ring[0], lm.ring[1], lm.ring[2]) if lm.has("ring") else pos
		db.add_location(lid, ring, Vector3(0, 0, 1), _landmark_name(lm))
		names[lm.id] = _landmark_name(lm)
	if lm.get("plot", false): return           # built by its plot (Puerto Alto's lighthouse on the mole)
	db.add(pos.x, pos.z, func(): _build_landmark(kit.sink, kind, pos, yaw), reach)
	recipe_count += 1


func _landmark_name(lm: Dictionary) -> String:
	var id: String = lm.id
	var tail := id.get_slice(".", 1).replace("_", " ").capitalize()
	match lm.kind:
		"lighthouse": return "%s Lighthouse" % (tail if not id.begins_with("poi") else tail.replace(" Cape", " Cape"))
		"dam": return "Lago Alto Dam"
		"gatehouse": return "Lago Alto Gatehouse"
		"castle_ruin": return "Castle Ruin" if id.begins_with("poi") else "Castelo de Puerto Alto"
		"monastery": return "Monasterio de las Nieves"
		"chapel": return "Pass Chapel"
		"hut": return "Alpine Hut"
		"viewpoint": return "%s Viewpoint" % tail
		"watchtower": return "%s Watchtower" % tail
	return tail


func _build_landmark(parent: Node3D, kind: String, pos: Vector3, yaw: float) -> void:
	if parent == null: return
	var origin := parent.global_position if parent.is_inside_tree() else Vector3.ZERO
	var p := pos - origin
	p.y = outer.height_at(pos.x, pos.z) - origin.y
	match kind:
		"lighthouse": kit._lighthouse(parent, p)
		"crane": kit._crane(parent, p, yaw)
		"castle_ruin":
			kit._fort_tower(parent, p + Vector3(6, 0, -4), 5.0, 15.0)
			kit._fort_tower(parent, p + Vector3(-14, outer.height_at(pos.x - 14, pos.z + 10) - p.y, 10), 3.8, 9.0)
			kit._stone_wall(parent, Vector2(p.x - 14, p.z + 10), Vector2(p.x + 6, p.z - 4), 3.5)
			kit._stone_wall(parent, Vector2(p.x + 6, p.z - 4), Vector2(p.x + 22, p.z + 12), 2.4)
		"watchtower": kit._fort_tower(parent, p, 3.5, 11.0)
		"viewpoint":
			kit._static_box(parent, Vector3(2.2, 0.45, 0.6), Mats.solid(Color(0.62, 0.58, 0.5), 0.9), p + Vector3(0, 0.22, 2.0))
			kit._signpost(parent, p + Vector3(1.8, 0, -1.5), yaw, [["MIRADOR", 1.0]])
		"chapel":
			_landmark_building(parent, origin, pos, yaw, "church", "valdoro", 7.0, 11.0, 2)
			kit._tower(parent, p + Vector3(0, 0, -7.5), 2.4, 9.0, Color(0.92, 0.90, 0.84))
		"hut": _landmark_building(parent, origin, pos, yaw, "house", "valdoro", 8.0, 6.0, 1)
		"gatehouse": _landmark_building(parent, origin, pos, yaw, "house", "campo", 9.0, 7.0, 2)
		"monastery":
			kit._cloister(parent, p, 18.0, Color(0.92, 0.88, 0.78))
			kit._house(parent, p + Vector3(-16, 0, 0), 90.0, 8.0, 20.0, 2, Color(0.92, 0.88, 0.78))
			kit._tower(parent, p + Vector3(12, 0, -12), 3.6, 16.0, Color(0.92, 0.88, 0.78))
		"dam": _dam(parent, pos, origin)


## A small building for a landmark, built like a placeholder plot on the ground where it stands.
func _landmark_building(parent: Node3D, origin: Vector3, pos: Vector3, yaw: float, kind: String, style: String, w: float, d: float, floors: int) -> void:
	var g := outer.height_at(pos.x, pos.z)
	var lo := g
	for c in [Vector2(-w, -d), Vector2(w, -d), Vector2(-w, d), Vector2(w, d)]:
		lo = minf(lo, outer.height_at(pos.x + c.x * 0.5, pos.z + c.y * 0.5))
	var plot := {"id": "landmark", "style": style, "kind": kind, "x": pos.x, "z": pos.z, "y": g, "ground_min": lo, "yaw": yaw,
		"w": w, "d": d, "floors": floors, "seed": int(absf(pos.x * 13.0 + pos.z)), "tags": []}
	if _kit_has("build_group"):
		building_kit.call("build_group", parent, [plot], origin)
		return
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body := StaticBody3D.new(); body.collision_layer = 1
	_placeholder(st, plot, origin, body)
	var mi := MeshInstance3D.new(); mi.mesh = st.commit(); mi.material_override = _vertex_colour_material()
	parent.add_child(mi); parent.add_child(body)


## The dam across the lake's outlet gorge: a curved concrete wall from ground to crest.
func _dam(parent: Node3D, pos: Vector3, origin: Vector3) -> void:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var crest: float = pos.y
	var prev := []
	for i in range(-14, 15):
		var x := pos.x + i * 10.0
		var z := pos.z - (i * 10.0) * (i * 10.0) / 2200.0      # bowed toward the lake
		var g := outer.height_at(x, z)
		if g > crest + 2.0 and prev.is_empty(): continue
		var bot := minf(g, crest) - 2.0
		var up := Vector3(x, crest, z) - origin; var dn := Vector3(x, bot, z) - origin
		var up2 := up + Vector3(0, 0, 7.0); var dn2 := dn + Vector3(0, 0, 18.0)
		if not prev.is_empty():
			OuterRoads._quad(st, prev[0], up, dn, prev[1])        # upstream face
			OuterRoads._quad(st, prev[2], prev[3], dn2, up2)      # downstream face
			OuterRoads._quad(st, prev[0], prev[2], up2, up)       # crest
			faces.append_array(PackedVector3Array([prev[0], up, dn, prev[0], dn, prev[1], prev[0], prev[2], up2, prev[0], up2, up, prev[2], prev[3], dn2, prev[2], dn2, up2]))
		prev = [up, dn, up2, dn2]
		if g > crest + 2.0: break
	var mi := MeshInstance3D.new(); mi.name = "Dam"; mi.mesh = st.commit()
	var m := StandardMaterial3D.new(); m.albedo_color = Color(0.74, 0.72, 0.68); m.roughness = 0.85
	m.albedo_texture = OuterRoads._tex("gravel009_alb_ht"); m.uv1_triplanar = true; m.uv1_scale = Vector3(0.1, 0.1, 0.1)
	mi.material_override = m
	parent.add_child(mi)
	var body := StaticBody3D.new(); body.collision_layer = 1
	var shape := ConcavePolygonShape3D.new(); shape.backface_collision = true; shape.set_faces(faces)
	var cs := CollisionShape3D.new(); cs.shape = shape; body.add_child(cs); parent.add_child(body)


# ---------------------------------------------------------------- signposts at junctions
func _define_signposts() -> void:
	var rd: OuterRoads = outer.roads
	if rd == null: return
	for e: Dictionary in rd.roads:
		if e.nav < 0 or (e.join as Dictionary).is_empty(): continue
		if not rd.by_id.has(e.join.road): continue
		var parent: Dictionary = rd.roads[rd.by_id[e.join.road]]
		var k: int = e.join.index
		var P: PackedVector3Array = parent.pts
		var J := P[k]
		var tan := Vector3(P[mini(k + 1, P.size() - 1)].x - P[maxi(k - 1, 0)].x, 0, P[mini(k + 1, P.size() - 1)].z - P[maxi(k - 1, 0)].z).normalized()
		var bpts: PackedVector3Array = e.pts
		var out: Vector3 = bpts[mini(6, bpts.size() - 1)] - J; out.y = 0; out = out.normalized()
		var side := Vector3(-tan.z, 0, tan.x)
		if side.dot(out) < 0: side = -side
		var pos: Vector3 = J + side * (float(parent.width) * 0.5 + 2.6) - tan * 9.0
		pos.y = outer.height_at(pos.x, pos.z)
		var rot := rad_to_deg(atan2(-tan.z, tan.x))
		var to_branch := _pretty(e.to)
		var km_branch := (bpts.size() - 1) * 0.004
		var labels := [["%s  %.1f km" % [to_branch, km_branch], 1.0 if out.dot(tan) >= 0.0 else -1.0]]
		if parent.to != "": labels.append(["%s  %.1f km" % [_pretty(parent.to), (P.size() - 1 - k) * 0.004], 1.0])
		if parent.from != "": labels.append(["%s  %.1f km" % [_pretty(parent.from), k * 0.004], -1.0])
		db.add(pos.x, pos.z, func(): kit._signpost(kit.sink, pos - (kit.sink.global_position if kit.sink and kit.sink.is_inside_tree() else Vector3.ZERO), rot, labels))


func _pretty(id: String) -> String:
	if names.has(id): return String(names[id]).to_upper()
	if id.begins_with("core_") or id == "network" or id == "gate": return "SAN TELMO" if id.begins_with("core") else "COAST ROAD"
	if id == "isola_junction": return "ISOLA SERENA"
	for t in ["hamlet_", "poi."]:
		if id.begins_with(t): id = id.trim_prefix(t)
	return id.replace("_", " ").to_upper()
