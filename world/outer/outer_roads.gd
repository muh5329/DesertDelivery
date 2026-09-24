class_name OuterRoads
extends Node3D
## The outer road network (plan.json `roads`): registered with the Terrain so the autopilot and
## traffic graph (RoadNavigation), the reset key and `nearest_road` work everywhere, and drawn as
## streamed ribbon meshes (250 m tiles within ~1 km; farther away the terrain shader paints the
## roads from its road mask). Bridges (decks, parapets, piers, lamps) are resident with their own
## collision. Town streets, plazas and quays are drawn by the same ribbons (render only).
##
## Roads the generator joined to another road start (or end) exactly on one of its samples, so the
## navigation graph links them (RoadNavigation joins samples within 3.8 m and 1.2 m of height).

const TILE := 250.0
const RADIUS := 4
const KIND := {"highway": 0, "road": 1, "track": 2, "street": 3, "main": 3, "lane": 4, "plaza": 5, "quay": 6}
const RIBBON_FAR := 1150.0

var outer: OuterWorld
var terrain: Terrain
var roads: Array = []                 # {id, cls, kind, width, pts: PackedVector3Array, bridge: PackedByteArray, nav: int, from, to}
var by_id: Dictionary = {}
var tiles: Dictionary = {}            # Vector2i -> Array of [road index, k0, k1]
var loaded: Dictionary = {}           # Vector2i -> Node3D
var pending: Array[Vector2i] = []
var materials: Dictionary = {}        # kind -> ShaderMaterial
var rail_mat: StandardMaterial3D
var post_mat: StandardMaterial3D
var bridges_node: Node3D
var bridge_count := 0
var nav_first := 0
var total_km := 0.0
var _last_tile := Vector2i(-9999, -9999)


func setup(p_outer: OuterWorld, p_terrain: Terrain) -> void:
	outer = p_outer; terrain = p_terrain
	name = "OuterRoads"
	var plan: Dictionary = outer.ground.plan
	nav_first = terrain.road_samples.size()
	for r: Dictionary in plan.get("roads", []):
		var pts := PackedVector3Array()
		for p in r.points: pts.append(Vector3(p[0], p[1], p[2]))
		var br := PackedByteArray(); br.resize(pts.size())
		for span in r.bridges:
			for k in range(int(span[0]), int(span[1]) + 1): br[k] = 1
		var e := {"id": r.id, "cls": r["class"], "kind": KIND.get(r["class"], 1), "width": float(r.width), "pts": pts, "bridge": br,
			"bridges": r.bridges, "nav": -1, "from": r.get("from", ""), "to": r.get("to", ""), "join": r.get("join", {})}
		if r["class"] == "street": e.kind = 3
		e.nav = _register(pts, r.bridges)
		by_id[r.id] = roads.size()
		roads.append(e)
		total_km += (pts.size() - 1) * 0.004
	# town streets: drawn, not navigated (the main streets are roads above)
	for group in ["towns", "hamlets"]:
		for t: Dictionary in plan.get(group, []):
			for st: Dictionary in t.streets:
				if st.kind == "main": continue
				var pts := PackedVector3Array()
				for p in st.points: pts.append(Vector3(p[0], p[1], p[2]))
				if pts.size() < 2: continue
				var br := PackedByteArray(); br.resize(pts.size())
				roads.append({"id": "%s.%s" % [t.id, st.kind], "cls": st.kind, "kind": KIND.get(st.kind, 4), "width": float(st.width),
					"pts": pts, "bridge": br, "bridges": [], "nav": -1, "from": "", "to": ""})
	_junction_trims()
	terrain._road_grid.clear()
	_bucket()
	_make_materials()
	bridges_node = Node3D.new(); bridges_node.name = "Bridges"; add_child(bridges_node)
	for e in roads:
		for span in e.bridges: _build_bridge(e, int(span[0]), int(span[1]))


## Append one road to the Terrain's network (samples, curve, bridges). Returns its road index.
func _register(pts: PackedVector3Array, spans: Array) -> int:
	var idx := terrain.road_samples.size()
	terrain.road_samples.append(pts)
	var curve := Curve3D.new()
	curve.bake_interval = 4.0
	for k in range(0, pts.size(), 4): curve.add_point(pts[k])
	if (pts.size() - 1) % 4 != 0: curve.add_point(pts[pts.size() - 1])
	terrain.roads.append(curve)
	for span in spans:
		var a := int(span[0]); var b := int(span[1])
		var deck := 0.0
		for k in range(a, b + 1): deck = maxf(deck, pts[k].y)
		terrain.bridges.append(Bridge.new(idx, pts, a, b, deck))
	return idx


## A road that joins another starts (or ends) on the parent's centre line; its ribbon is trimmed
## back to the parent's edge so the two surfaces do not overlap.
func _junction_trims() -> void:
	for e in roads:
		e["trim0"] = 0; e["trim1"] = (e.pts as PackedVector3Array).size() - 1
		for end in ["join", "join_end"]:
			var j: Dictionary = e.get(end, {})
			if j.is_empty() or not by_id.has(j.road): continue
			var parent: Dictionary = roads[by_id[j.road]]
			var P: PackedVector3Array = e.pts
			var J: Vector3 = (parent.pts as PackedVector3Array)[int(j.index)]
			var reach: float = float(parent.width) * 0.5 + 0.3
			if end == "join":
				var k := 0
				while k < P.size() - 2 and Vector2(P[k].x - J.x, P[k].z - J.z).length() < reach: k += 1
				e.trim0 = maxi(k - 1, 0)
			else:
				var k := P.size() - 1
				while k > 1 and Vector2(P[k].x - J.x, P[k].z - J.z).length() < reach: k -= 1
				e.trim1 = mini(k + 1, P.size() - 1)
	# the town main streets start on the ring's gate sample: trim them at the gate too
	for e in roads:
		if e.cls != "street" or e.nav < 0: continue
		var P: PackedVector3Array = e.pts
		var k := 0
		while k < P.size() - 2 and Vector2(P[k].x - P[0].x, P[k].z - P[0].z).length() < 6.0: k += 1
		e.trim0 = maxi(e.trim0, k - 1)


func _bucket() -> void:
	tiles.clear()
	for ri in range(roads.size()):
		var pts: PackedVector3Array = roads[ri].pts
		var cur := Vector2i(-99999, -99999); var k0 := 0
		for k in range(pts.size() - 1):
			var m := (pts[k] + pts[k + 1]) * 0.5
			var t := Vector2i(floori(m.x / TILE), floori(m.z / TILE))
			if t != cur:
				if cur.x != -99999: _add_run(cur, ri, k0, k)
				cur = t; k0 = k
		if cur.x != -99999: _add_run(cur, ri, k0, pts.size() - 1)


func _add_run(t: Vector2i, ri: int, k0: int, k1: int) -> void:
	if not tiles.has(t): tiles[t] = []
	tiles[t].append([ri, k0, k1])


func _make_materials() -> void:
	var asphalt := _tex("asphalt_alb_ht"); var asphalt_n := _tex("asphalt_nrm_rgh")
	var sett := _tex("cobble_alb_ht"); var sett_n := _tex("cobble_nrm_rgh")
	var dirt := _tex("ground004_alb_ht"); var dirt_n := _tex("ground004_nrm_rgh")
	var noise: Texture2D = OuterTerrainView._noise_texture()
	var shader: Shader = load("res://world/outer/outer_road.gdshader")
	for kind in range(7):
		var m := ShaderMaterial.new(); m.shader = shader
		m.set_shader_parameter("kind", kind)
		m.set_shader_parameter("asphalt_tex", asphalt); m.set_shader_parameter("asphalt_nrm", asphalt_n)
		m.set_shader_parameter("sett_tex", sett); m.set_shader_parameter("sett_nrm", sett_n)
		m.set_shader_parameter("dirt_tex", dirt); m.set_shader_parameter("dirt_nrm", dirt_n)
		m.set_shader_parameter("noise_tex", noise)
		materials[kind] = m
	rail_mat = StandardMaterial3D.new(); rail_mat.albedo_color = Color(0.72, 0.73, 0.74); rail_mat.metallic = 0.6; rail_mat.roughness = 0.45
	post_mat = StandardMaterial3D.new(); post_mat.albedo_color = Color(0.9, 0.9, 0.88); post_mat.roughness = 0.7


static func _tex(name: String) -> ImageTexture:
	var img := OuterTerrainView._tex_image("res://assets/terrain/%s.png" % name)
	return ImageTexture.create_from_image(img)


func material_for(kind: int, width: float) -> ShaderMaterial:
	var key := "%d|%.1f" % [kind, width]
	if not materials.has(key):
		var m: ShaderMaterial = (materials[kind] as ShaderMaterial).duplicate()
		m.set_shader_parameter("width", width)
		materials[key] = m
	return materials[key]


# ---------------------------------------------------------------- streaming
func _view_pos() -> Vector3:
	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp else null
	if cam: return cam.global_position
	return outer.focus.global_position if outer.focus else Vector3.ZERO


func _ready() -> void:
	# purely visual streaming: a headless run (tests, tools) builds on demand through flush()
	if DisplayServer.get_name() == "headless": set_process(false)


func _process(_delta: float) -> void:
	var p := _view_pos()
	var t := Vector2i(floori(p.x / TILE), floori(p.z / TILE))
	if t != _last_tile:
		_last_tile = t
		for k: Vector2i in loaded.keys():
			if maxi(absi(k.x - t.x), absi(k.y - t.y)) > RADIUS + 1:
				loaded[k].queue_free(); loaded.erase(k)
		pending.clear()
		for dz in range(-RADIUS, RADIUS + 1):
			for dx in range(-RADIUS, RADIUS + 1):
				var k := t + Vector2i(dx, dz)
				if not loaded.has(k) and tiles.has(k): pending.append(k)
		pending.sort_custom(func(a: Vector2i, b: Vector2i): return (a - t).length_squared() < (b - t).length_squared())
	if not pending.is_empty(): build_tile(pending.pop_front())


## Build every pending ribbon tile now (tests, teleports, render tools).
func flush() -> void:
	_process(0.0)
	while not pending.is_empty(): build_tile(pending.pop_front())


var max_build_ms := 0.0


func build_tile(t: Vector2i) -> void:
	var t0 := Time.get_ticks_usec()
	_build_tile_impl(t)
	max_build_ms = maxf(max_build_ms, (Time.get_ticks_usec() - t0) / 1000.0)


func _build_tile_impl(t: Vector2i) -> void:
	var node := Node3D.new(); node.name = "Roads_%d_%d" % [t.x, t.y]
	add_child(node); loaded[t] = node
	var surfaces: Dictionary = {}     # material key -> [verts, normals, uvs, tangents, indices]
	var rails := SurfaceTool.new(); rails.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rail_faces := PackedVector3Array()
	var posts := SurfaceTool.new(); posts.begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_rails := false; var has_posts := false
	for run in tiles[t]:
		var e: Dictionary = roads[run[0]]
		var k0: int = maxi(maxi(run[1] - 1, 0), int(e.get("trim0", 0))); var k1: int = mini(mini(run[2] + 1, e.pts.size() - 1), int(e.get("trim1", 1 << 30)))
		if k1 > k0: _ribbon(e, k0, k1, surfaces)
		if e.kind <= 1:
			has_rails = _rails(e, run[1], run[2], rails, rail_faces) or has_rails
		if e.kind == 0:
			has_posts = _km_posts(e, run[1], run[2], posts) or has_posts
	for key in surfaces:
		var s: Array = surfaces[key]
		if (s[4] as PackedInt32Array).is_empty(): continue
		var arr := []; arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = s[0]; arr[Mesh.ARRAY_NORMAL] = s[1]; arr[Mesh.ARRAY_TEX_UV] = s[2]
		arr[Mesh.ARRAY_TANGENT] = s[3]; arr[Mesh.ARRAY_INDEX] = s[4]
		var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mi := MeshInstance3D.new(); mi.mesh = mesh; mi.material_override = s[5]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = RIBBON_FAR; mi.visibility_range_end_margin = 60.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		node.add_child(mi)
	if has_rails:
		var mi := MeshInstance3D.new(); mi.mesh = rails.commit(); mi.material_override = rail_mat
		mi.visibility_range_end = 450.0; node.add_child(mi)
		var body := StaticBody3D.new(); body.collision_layer = 1
		var shape := ConcavePolygonShape3D.new(); shape.backface_collision = true; shape.set_faces(rail_faces)
		var cs := CollisionShape3D.new(); cs.shape = shape; body.add_child(cs); node.add_child(body)
	if has_posts:
		var mi := MeshInstance3D.new(); mi.mesh = posts.commit(); mi.material_override = post_mat
		mi.visibility_range_end = 300.0; node.add_child(mi)


func _cross(e: Dictionary) -> PackedFloat32Array:
	var hw: float = e.width * 0.5
	if e.kind == 2: return PackedFloat32Array([-hw, 0.0, hw])
	if e.kind >= 5: return PackedFloat32Array([-hw, -hw * 0.5, 0.0, hw * 0.5, hw])
	return PackedFloat32Array([-hw, -hw * 0.5, 0.0, hw * 0.5, hw])


func _ribbon(e: Dictionary, k0: int, k1: int, surfaces: Dictionary) -> void:
	var mat := material_for(e.kind, e.width)
	var key := mat.get_instance_id()
	if not surfaces.has(key):
		surfaces[key] = [PackedVector3Array(), PackedVector3Array(), PackedVector2Array(), PackedFloat32Array(), PackedInt32Array(), mat]
	var s: Array = surfaces[key]
	var V: PackedVector3Array = s[0]; var Nn: PackedVector3Array = s[1]; var U: PackedVector2Array = s[2]
	var Tg: PackedFloat32Array = s[3]; var I: PackedInt32Array = s[4]
	var pts: PackedVector3Array = e.pts
	var cross := _cross(e)
	var nc := cross.size()
	var base := V.size()
	var along := float(k0) * 4.0
	for k in range(k0, k1 + 1):
		var p := pts[k]
		var a := pts[maxi(k - 1, 0)]; var b := pts[mini(k + 1, pts.size() - 1)]
		var tan := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
		var right := Vector3(-tan.z, 0.0, tan.x)
		var on_bridge: bool = e.bridge[k] == 1
		var nrm := Vector3.UP if on_bridge else outer.normal_at(p.x, p.z)
		for c in range(nc):
			var off := cross[c]
			var q := p + right * off
			q.y = (p.y + 0.03) if on_bridge else (outer.height_at(q.x, q.z) + 0.045)
			V.append(q); Nn.append(nrm)
			U.append(Vector2((off / e.width) + 0.5, along))
			Tg.append_array(PackedFloat32Array([tan.x, tan.y, tan.z, 1.0]))
		if k < k1:
			along += p.distance_to(pts[k + 1])
			var r0 := base + (k - k0) * nc; var r1 := r0 + nc
			for c in range(nc - 1):
				I.append_array(PackedInt32Array([r0 + c, r1 + c, r0 + c + 1, r0 + c + 1, r1 + c, r1 + c + 1]))
	s[0] = V; s[1] = Nn; s[2] = U; s[3] = Tg; s[4] = I


## Guard rails where the ground falls away more than 3 m beside the road (not on bridges).
func _rails(e: Dictionary, k0: int, k1: int, st: SurfaceTool, faces: PackedVector3Array) -> bool:
	var pts: PackedVector3Array = e.pts
	var hw: float = e.width * 0.5
	var made := false
	for side: float in [-1.0, 1.0]:
		var prev_top := Vector3.INF; var prev_bot := Vector3.INF
		for k in range(k0, k1 + 1):
			var p := pts[k]
			var ok := false
			if e.bridge[k] == 0:
				var a := pts[maxi(k - 1, 0)]; var b := pts[mini(k + 1, pts.size() - 1)]
				var tan := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
				var right := Vector3(-tan.z, 0.0, tan.x) * side
				var edge := p + right * (hw + 0.6)
				var drop := p.y - outer.height_at(p.x + right.x * (hw + 4.5), p.z + right.z * (hw + 4.5))
				if drop > 3.0:
					ok = true
					edge.y = outer.height_at(edge.x, edge.z)
					var top := edge + Vector3(0, 0.78, 0); var bot := edge + Vector3(0, 0.45, 0)
					if prev_top != Vector3.INF:
						_quad(st, prev_bot, bot, top, prev_top)
						faces.append_array(PackedVector3Array([prev_bot, bot, top, prev_bot, top, prev_top]))
					if k % 1 == 0:
						_box(st, edge + Vector3(0, 0.38, 0), Vector3(0.1, 0.76, 0.1))
					prev_top = top; prev_bot = bot
					made = true
			if not ok:
				prev_top = Vector3.INF; prev_bot = Vector3.INF
	return made


func _km_posts(e: Dictionary, k0: int, k1: int, st: SurfaceTool) -> bool:
	var made := false
	for k in range(k0, k1 + 1):
		if k % 250 != 0 or k == 0 or e.bridge[k] == 1: continue      # every kilometre (4 m samples)
		var pts: PackedVector3Array = e.pts
		var a := pts[maxi(k - 1, 0)]; var b := pts[mini(k + 1, pts.size() - 1)]
		var tan := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
		var q: Vector3 = pts[k] + Vector3(-tan.z, 0, tan.x) * (float(e.width) * 0.5 + 1.2)
		q.y = outer.height_at(q.x, q.z)
		_box(st, q + Vector3(0, 0.5, 0), Vector3(0.22, 1.0, 0.12))
		made = true
	return made


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var n := (b - a).cross(d - a).normalized()
	for v in [a, b, c, a, c, d]:
		st.set_normal(n); st.add_vertex(v)
	for v in [a, c, b, a, d, c]:
		st.set_normal(-n); st.add_vertex(v)


static func _box(st: SurfaceTool, c: Vector3, s: Vector3) -> void:
	var h := s * 0.5
	var p := [c + Vector3(-h.x, -h.y, -h.z), c + Vector3(h.x, -h.y, -h.z), c + Vector3(h.x, h.y, -h.z), c + Vector3(-h.x, h.y, -h.z),
		c + Vector3(-h.x, -h.y, h.z), c + Vector3(h.x, -h.y, h.z), c + Vector3(h.x, h.y, h.z), c + Vector3(-h.x, h.y, h.z)]
	var faces := [[0, 3, 2, 1, Vector3(0, 0, -1)], [4, 5, 6, 7, Vector3(0, 0, 1)], [0, 4, 7, 3, Vector3(-1, 0, 0)],
		[1, 2, 6, 5, Vector3(1, 0, 0)], [3, 7, 6, 2, Vector3(0, 1, 0)], [0, 1, 5, 4, Vector3(0, -1, 0)]]
	for f in faces:
		for i in [0, 2, 1, 0, 3, 2]:
			st.set_normal(f[4]); st.add_vertex(p[f[i]])


# ---------------------------------------------------------------- bridges
func _build_bridge(e: Dictionary, a: int, b: int) -> void:
	var pts: PackedVector3Array = e.pts
	a = maxi(a - 1, 0); b = mini(b + 1, pts.size() - 1)
	if b - a < 2: return
	var hw: float = e.width * 0.5 + 0.8
	var stone: bool = e.kind >= 1
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var prev_l := Vector3.INF; var prev_r := Vector3.INF
	var length := 0.0
	var lamps: Array[Transform3D] = []
	for k in range(a, b + 1):
		var p := pts[k]
		var pa := pts[maxi(k - 1, 0)]; var pb := pts[mini(k + 1, pts.size() - 1)]
		var tan := Vector3(pb.x - pa.x, 0.0, pb.z - pa.z).normalized()
		var right := Vector3(-tan.z, 0.0, tan.x)
		var l := p - right * hw; var r := p + right * hw
		if prev_l != Vector3.INF:
			length += p.distance_to(pts[k - 1])
			# deck top (collision at the sample height), slab sides, soffit, parapets
			faces.append_array(PackedVector3Array([prev_l, prev_r, r, prev_l, r, l]))
			_quad_one(st, prev_l + Vector3(0, -0.02, 0), prev_r + Vector3(0, -0.02, 0), r + Vector3(0, -0.02, 0), l + Vector3(0, -0.02, 0), Vector3.UP)
			var dn := Vector3(0, -1.3, 0)
			_quad_one(st, prev_l + dn, l + dn, r + dn, prev_r + dn, Vector3.DOWN)
			for side: float in [-1.0, 1.0]:
				var e0: Vector3 = prev_l if side < 0 else prev_r
				var e1: Vector3 = l if side < 0 else r
				var out: Vector3 = right * side
				var wall_in0 := e0 - out * 0.35; var wall_in1 := e1 - out * 0.35
				var up := Vector3(0, 1.0, 0)
				_quad(st, e0 + dn, e1 + dn, e1 + up, e0 + up)                 # outer face down to the soffit
				_quad(st, wall_in0, wall_in1, wall_in1 + up, wall_in0 + up)   # inner face of the parapet
				_quad_one(st, wall_in0 + up, e0 + up, e1 + up, wall_in1 + up, Vector3.UP)
				faces.append_array(PackedVector3Array([wall_in0, wall_in1, wall_in1 + up, wall_in0, wall_in1 + up, wall_in0 + up]))
		prev_l = l; prev_r = r
		# piers every ~32 m where the deck stands clear of the ground or the sea
		if (k - a) % 8 == 4 and k < b - 2:
			var g := outer.height_at(p.x, p.z)
			var foot := minf(g, 0.0) - 2.0 if g < 0.5 else g - 1.0
			var h := p.y - 1.3 - foot
			if h > 1.5:
				for side: float in [-1.0, 1.0]:
					var c := p + right * side * (hw * 0.55) + Vector3(0, -1.3 - h * 0.5, 0)
					_box(st, c, Vector3(1.8 if h < 25 else 2.6, h, 1.8 if h < 25 else 2.6) if not stone else Vector3(2.2, h, 3.0))
				# a crossbeam under the deck
				_box(st, p + Vector3(0, -1.6, 0), Vector3(1.2, 0.7, hw * 2.0) if absf(tan.x) > absf(tan.z) else Vector3(hw * 2.0, 0.7, 1.2))
		if (k - a) % 12 == 6 and (b - a) > 50:
			var side := 1.0 if ((k - a) / 12) % 2 == 0 else -1.0
			lamps.append(Transform3D(Basis(), p + right * side * (hw - 0.25)))
	var mesh := st.commit()
	var mi := MeshInstance3D.new(); mi.name = "Bridge_%s_%d" % [e.id, a]
	mi.mesh = mesh; mi.material_override = _bridge_material(stone)
	mi.visibility_range_end = 6000.0
	bridges_node.add_child(mi)
	var body := StaticBody3D.new(); body.collision_layer = 1
	var shape := ConcavePolygonShape3D.new(); shape.backface_collision = true; shape.set_faces(faces)
	var cs := CollisionShape3D.new(); cs.shape = shape; body.add_child(cs)
	mi.add_child(body)
	if not lamps.is_empty():
		var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D; mm.mesh = _lamp_mesh()
		mm.instance_count = lamps.size()
		for i in range(lamps.size()): mm.set_instance_transform(i, lamps[i])
		var mmi := MultiMeshInstance3D.new(); mmi.multimesh = mm; mmi.visibility_range_end = 900.0
		bridges_node.add_child(mmi)
	bridge_count += 1


static func _quad_one(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	# one-sided quad facing n (winding chosen from n)
	var fn := (b - a).cross(c - a)
	if fn.dot(n) > 0.0:
		for v in [a, c, b, a, d, c]:
			st.set_normal(n); st.add_vertex(v)
	else:
		for v in [a, b, c, a, c, d]:
			st.set_normal(n); st.add_vertex(v)


var _bridge_mats := {}
func _bridge_material(stone: bool) -> StandardMaterial3D:
	if _bridge_mats.has(stone): return _bridge_mats[stone]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.78, 0.72, 0.62) if stone else Color(0.74, 0.73, 0.70)
	m.albedo_texture = _tex("rock019_alb_ht") if stone else _tex("gravel009_alb_ht")
	m.uv1_triplanar = true; m.uv1_scale = Vector3(0.25, 0.25, 0.25) if stone else Vector3(0.6, 0.6, 0.6)
	m.roughness = 0.9
	_bridge_mats[stone] = m
	return m


var _lamp: ArrayMesh
func _lamp_mesh() -> ArrayMesh:
	if _lamp: return _lamp
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box(st, Vector3(0, 3.5, 0), Vector3(0.14, 7.0, 0.14))
	_box(st, Vector3(0, 7.0, 0), Vector3(0.12, 0.12, 1.6))
	var m1 := st.commit()
	var st2 := SurfaceTool.new(); st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box(st2, Vector3(0, 6.9, 0.7), Vector3(0.35, 0.18, 0.6))
	st2.commit(m1)
	var pole := StandardMaterial3D.new(); pole.albedo_color = Color(0.3, 0.32, 0.33); pole.metallic = 0.5; pole.roughness = 0.5
	var glow := StandardMaterial3D.new(); glow.albedo_color = Color(1.0, 0.95, 0.8); glow.emission_enabled = true; glow.emission = Color(1.0, 0.85, 0.55); glow.emission_energy_multiplier = 0.6
	m1.surface_set_material(0, pole); m1.surface_set_material(1, glow)
	_lamp = m1
	return _lamp
