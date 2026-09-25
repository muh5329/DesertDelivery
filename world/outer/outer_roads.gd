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
const KIND := {"highway": 0, "road": 1, "track": 2, "street": 3, "main": 3, "lane": 4, "plaza": 5, "quay": 6, "apron": 7}
const RIBBON_FAR := 1150.0
## town style -> id carried to the street shader in COLOR.g (paving by town: Lisbon calcada in Puerto)
const STYLE_ID := {"campo": 0, "puerto": 1, "valdoro": 2, "sarmada": 3, "isola": 4}

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
	# town id -> paving style: the main streets are plan roads (M-10: they were drawn in style 0)
	var town_style := {}
	for group in ["towns", "hamlets"]:
		for t: Dictionary in plan.get(group, []): town_style[t.id] = STYLE_ID.get(t.style, 0)
	for r: Dictionary in plan.get("roads", []):
		var pts := PackedVector3Array()
		for p in r.points: pts.append(Vector3(p[0], p[1], p[2]))
		var br := PackedByteArray(); br.resize(pts.size())
		for span in r.bridges:
			for k in range(int(span[0]), int(span[1]) + 1): br[k] = 1
			_ease_deck(pts, int(span[0]), int(span[1]))
		var e := {"id": r.id, "cls": r["class"], "kind": KIND.get(r["class"], 1), "width": float(r.width), "pts": pts, "bridge": br,
			"bridges": r.bridges, "nav": -1, "from": r.get("from", ""), "to": r.get("to", ""), "join": r.get("join", {})}
		if r["class"] == "street": e.kind = 3
		if r.has("town"): e["style"] = town_style.get(r.town, 0)
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
				pts = _densify(pts, 4.0)
				var br := PackedByteArray(); br.resize(pts.size())
				roads.append({"id": "%s.%s" % [t.id, st.kind], "cls": st.kind, "kind": KIND.get(st.kind, 4), "width": float(st.width),
					"pts": pts, "bridge": br, "bridges": [], "nav": -1, "from": "", "to": "", "style": STYLE_ID.get(t.style, 0)})
	for e in roads:
		if e.kind == 5 and (e.pts as PackedVector3Array).size() >= 2:
			var pp: PackedVector3Array = e.pts
			plazas.append([Vector2(pp[0].x, pp[0].z), Vector2(pp[pp.size() - 1].x, pp[pp.size() - 1].z), float(e.width) * 0.5])
	_core_seams()
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


## C-4: where a spoke leaves the core, the core exit's own bridge (a 5 m stone arcade, Island's
## `_gen_aqueducts`, which skips the exits while the outer world is up) is replaced by the highway's
## concrete deck: from the core exit's bridgehead on land to the seam at the core edge, its width
## growing from the core road's to the highway's, same parapets, collision and asphalt, so the two
## decks meet edge to edge at the same height. Drawn and built like any other bridge (render and
## collision only: the core exit stays the navigation road).
const SEAM_START_WIDTH := 6.5
const SEAM_BANK := 14.0
var seams: Array = []                 # [{id, road (core road index), from (its bridgehead sample), bank_from, pts}]


func _core_seams() -> void:
	for ri in range(roads.size()):
		var e: Dictionary = roads[ri]
		if not String(e.get("from", "")).begins_with("core_"): continue
		var p0: Vector3 = (e.pts as PackedVector3Array)[0]
		# the core exit road that ends on the spoke's first sample
		var core := -1
		for ci in range(nav_first):
			var cand: PackedVector3Array = terrain.road_samples[ci]
			if cand.size() > 1 and Vector2(cand[cand.size() - 1].x - p0.x, cand[cand.size() - 1].z - p0.z).length() < 1.5:
				core = ci; break
		if core < 0: continue
		var cs: PackedVector3Array = terrain.road_samples[core]
		var start := cs.size() - 1
		for b in terrain.bridges:
			if b.road != core or b.to < cs.size() - 3: continue
			start = mini(start, (b.deck_span(terrain) as Vector2i).x)
		if start >= cs.size() - 2: continue
		# the deck also covers the last SEAM_BANK m of the bank: the core's cut leaves bumps of 0.2-0.4 m
		# at the bridgehead (the north exit's 20 % ramp threw the bike 0.4 s into the air there)
		var bank_end := start
		var back := 0.0
		while start > 0 and back < SEAM_BANK:
			back += cs[start].distance_to(cs[start - 1]); start -= 1
		# samples every 2 m on the bank, ~4 m over the water, the last exactly on the spoke's start
		var pts := PackedVector3Array(); var acc := 4.0
		var bank := 0
		for k in range(start, cs.size() - 1):
			if k > start: acc += cs[k].distance_to(cs[k - 1])
			if acc >= (2.0 if k <= bank_end + 4 else 4.0):
				pts.append(cs[k]); acc = 0.0
				if k <= bank_end + 4: bank = pts.size()
		if pts.size() > 1 and pts[pts.size() - 1].distance_to(p0) < 2.0: pts.remove_at(pts.size() - 1)
		pts.append(p0)
		if pts.size() < 3: continue
		# on the bank the deck rides just over the core's ground: the upper envelope of the road's
		# profile and the ground across the carriageway, starting flush with the dirt road (no lip);
		# past a bump it comes down at most 3 % (over the water it may stand a little above the core
		# bridge's level, it meets the spoke's deck at the seam), and its dips are filled, so the
		# ride has no crest sharper than the ramp's own
		var n := pts.size()
		for k in range(mini(bank, n - 1)):
			var q := pts[k]
			var a := pts[maxi(k - 1, 0)]; var b := pts[mini(k + 1, n - 1)]
			var tan := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
			var rt := Vector3(-tan.z, 0.0, tan.x)
			var hi := q.y
			for u: float in [-1.0, 0.0, 1.0]:
				for v: float in [-1.0, 0.0, 1.0]:
					var c := q + tan * u + rt * v
					hi = maxf(hi, terrain.height_at(c.x, c.z))
			pts[k].y = terrain.height_at(q.x, q.z) if k == 0 else hi + 0.03
		for k in range(maxi(bank, 1), n - 1):
			pts[k].y = maxf(pts[k].y, pts[k - 1].y - 0.03 * pts[k].distance_to(pts[k - 1]))
		for _pass in range(12):
			for k in range(1, mini(bank, n - 1)):
				pts[k].y = maxf(pts[k].y, 0.5 * (pts[k - 1].y + pts[k + 1].y))
		var L := 0.0
		for k in range(1, pts.size()): L += pts[k].distance_to(pts[k - 1])
		var full: float = e.width
		var widths := PackedFloat32Array(); var s := 0.0
		var ramp := clampf(L - 40.0, L * 0.35, L * 0.8)
		for k in range(pts.size()):
			if k > 0: s += pts[k].distance_to(pts[k - 1])
			widths.append(lerpf(SEAM_START_WIDTH, full, smoothstep(0.0, ramp, s)))
		var br := PackedByteArray(); br.resize(pts.size()); br.fill(1)
		# the deck's collision runs 0.6 m on over the spoke's own deck: no seam between two shapes
		var sp: PackedVector3Array = e.pts
		var tail := p0 + (sp[1] - p0).normalized() * 0.6
		roads.append({"id": "seam.%s" % e.id, "cls": "highway", "kind": 0, "width": full, "pts": pts, "bridge": br,
			"bridges": [[0, pts.size() - 1]], "nav": -1, "from": "", "to": "", "widths": widths, "seam": true, "tail": tail,
			"rail_from": maxi(bank - 3, 0)})
		seams.append({"id": "seam.%s" % e.id, "road": core, "from": bank_end, "bank_from": start, "pts": pts})


## A deck's profile is the road's: grade limited but not its change, so a deck over a gully could
## kink 8 % at one sample (road.dam's bridge threw the bike 0.34 s). The interior samples are eased
## (three 1-2-1 passes; the abutments stay), a few centimetres at most.
static func _ease_deck(pts: PackedVector3Array, a: int, b: int) -> void:
	if b - a < 3: return
	for _pass in range(3):
		var prev := pts[a].y
		for k in range(a + 1, b):
			var y := pts[k].y
			pts[k].y = 0.25 * prev + 0.5 * y + 0.25 * pts[k + 1].y
			prev = y


## A road that joins another starts (or ends) on the parent's centre line; its ribbon is trimmed
## back to the parent's edge so the two surfaces do not overlap.
## Samples at most `step` apart (a plaza or a quay may be two points 90 m apart; its ribbon has to
## drape over the ground between them).
static func _densify(pts: PackedVector3Array, step: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for k in range(pts.size() - 1):
		var a := pts[k]; var b := pts[k + 1]
		var n := maxi(int(ceil(a.distance_to(b) / step)), 1)
		for i in range(n): out.append(a.lerp(b, float(i) / n))
	out.append(pts[pts.size() - 1])
	return out


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
	for kind in range(8):
		var m := ShaderMaterial.new(); m.shader = shader
		m.set_shader_parameter("kind", kind)
		m.set_shader_parameter("asphalt_tex", asphalt); m.set_shader_parameter("asphalt_nrm", asphalt_n)
		m.set_shader_parameter("sett_tex", sett); m.set_shader_parameter("sett_nrm", sett_n)
		m.set_shader_parameter("dirt_tex", dirt); m.set_shader_parameter("dirt_nrm", dirt_n)
		m.set_shader_parameter("noise_tex", noise)
		materials[kind] = m
	rail_mat = StandardMaterial3D.new(); rail_mat.albedo_color = Color(0.72, 0.73, 0.74); rail_mat.metallic = 0.6; rail_mat.roughness = 0.45
	post_mat = StandardMaterial3D.new(); post_mat.vertex_color_use_as_albedo = true; post_mat.roughness = 0.7


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
	var lamp_pts: Array[Transform3D] = []
	for run in tiles[t]:
		var e: Dictionary = roads[run[0]]
		var k0: int = maxi(maxi(run[1] - 1, 0), int(e.get("trim0", 0))); var k1: int = mini(mini(run[2] + 1, e.pts.size() - 1), int(e.get("trim1", 1 << 30)))
		if k1 > k0: _ribbon(e, k0, k1, surfaces)
		if e.kind <= 1:
			has_rails = _rails(e, run[1], run[2], rails, rail_faces) or has_rails
		if e.kind == 0:
			has_posts = _km_posts(e, run[1], run[2], posts) or has_posts
		if e.kind <= 2 and e.nav >= 0:
			has_posts = _furniture(e, run[1], run[2], posts, lamp_pts) or has_posts
	for key in surfaces:
		var s: Array = surfaces[key]
		if (s[4] as PackedInt32Array).is_empty(): continue
		var arr := []; arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = s[0]; arr[Mesh.ARRAY_NORMAL] = s[1]; arr[Mesh.ARRAY_TEX_UV] = s[2]
		arr[Mesh.ARRAY_TANGENT] = s[3]; arr[Mesh.ARRAY_INDEX] = s[4]; arr[Mesh.ARRAY_COLOR] = s[6]
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
		mi.visibility_range_end = 380.0; node.add_child(mi)
	if not lamp_pts.is_empty():
		var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D; mm.mesh = _lamp_mesh()
		mm.instance_count = lamp_pts.size()
		for i in range(lamp_pts.size()): mm.set_instance_transform(i, lamp_pts[i])
		var mmi := MultiMeshInstance3D.new(); mmi.multimesh = mm; mmi.visibility_range_end = 900.0
		node.add_child(mmi)
		NightLights.register(mmi, _lamp_heads(lamp_pts))


## Offsets across the ribbon. Highways, roads and tracks carry a gravel shoulder beyond the
## carriageway (the outermost vertices, COLOR.a = 1 in outer_road.gdshader).
const SHOULDER := {0: 1.6, 1: 1.1, 2: 0.7}


func _cross(e: Dictionary) -> PackedFloat32Array:
	var hw: float = e.width * 0.5
	var sh: float = SHOULDER.get(e.kind, 0.0)
	if e.kind == 2: return PackedFloat32Array([-hw - sh, -hw, 0.0, hw, hw + sh])
	if e.kind >= 3:
		# wide plazas and quays drape over the ground with a vertex every ~4 m across
		var nseg := maxi(4, int(ceil(e.width / 4.0)))
		var out := PackedFloat32Array()
		for i in range(nseg + 1): out.append(-hw + e.width * i / nseg)
		return out
	return PackedFloat32Array([-hw - sh, -hw, -hw * 0.5, 0.0, hw * 0.5, hw, hw + sh])


func _ribbon(e: Dictionary, k0: int, k1: int, surfaces: Dictionary) -> void:
	var mat := material_for(e.kind, e.width)
	var key := mat.get_instance_id()
	if not surfaces.has(key):
		surfaces[key] = [PackedVector3Array(), PackedVector3Array(), PackedVector2Array(), PackedFloat32Array(), PackedInt32Array(), mat, PackedColorArray()]
	var s: Array = surfaces[key]
	var V: PackedVector3Array = s[0]; var Nn: PackedVector3Array = s[1]; var U: PackedVector2Array = s[2]
	var Tg: PackedFloat32Array = s[3]; var I: PackedInt32Array = s[4]; var Cl: PackedColorArray = s[6]
	var pts: PackedVector3Array = e.pts
	var cross := _cross(e)
	var nc := cross.size()
	var base := V.size()
	var hw: float = e.width * 0.5
	# a plaza is drawn as one long piece: its length rides in COLOR.r (the pattern is centred on it)
	var plaza_len := 0.0
	if e.kind == 5:
		for q in range(pts.size() - 1): plaza_len += pts[q].distance_to(pts[q + 1])
	var along := float(k0) * 4.0
	var widths: PackedFloat32Array = e.get("widths", PackedFloat32Array())
	for k in range(k0, k1 + 1):
		var p := pts[k]
		var a := pts[maxi(k - 1, 0)]; var b := pts[mini(k + 1, pts.size() - 1)]
		var tan := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
		var right := Vector3(-tan.z, 0.0, tan.x)
		if not widths.is_empty(): right *= widths[k] / float(e.width)      # a tapering deck (core seams)
		var on_bridge: bool = e.bridge[k] == 1
		var nrm := Vector3.UP if on_bridge else outer.normal_at(p.x, p.z)
		for c in range(nc):
			var off := cross[c]
			var q := p + right * off
			var outer_v := absf(off) > hw + 0.01
			if on_bridge and outer_v: q = p + right * signf(off) * hw     # no shoulder on a deck
			# where ribbons overlap (a main street crossing its plaza) the plaza wins: it rides 3 cm higher
			var lift := 0.045 + (0.03 if e.kind == 5 else (0.015 if e.kind == 6 else 0.0))
			q.y = (p.y + 0.03) if on_bridge else (outer.height_at(q.x, q.z) + (0.015 if outer_v else lift))
			V.append(q); Nn.append(nrm)
			U.append(Vector2((off / e.width) + 0.5, along))
			Tg.append_array(PackedFloat32Array([tan.x, tan.y, tan.z, 1.0]))
			Cl.append(Color(plaza_len / 200.0, float(e.get("style", 0)) / 8.0, 0.0, 1.0 if outer_v else 0.0))
		if k < k1:
			along += p.distance_to(pts[k + 1])
			var r0 := base + (k - k0) * nc; var r1 := r0 + nc
			for c in range(nc - 1):
				I.append_array(PackedInt32Array([r0 + c, r1 + c, r0 + c + 1, r0 + c + 1, r1 + c, r1 + c + 1]))
	# a street or a lane across a plaza is not drawn there: the plaza's paving is (two draped
	# surfaces a few cm apart z-fight where the ground is not flat)
	if (e.kind == 3 or e.kind == 4) and not plazas.is_empty():
		var keep := PackedInt32Array()
		var i0 := I.size() - (k1 - k0) * (nc - 1) * 6
		for i in range(0, i0): keep.append(I[i])
		for i in range(maxi(i0, 0), I.size(), 3):
			var cen := (V[I[i]] + V[I[i + 1]] + V[I[i + 2]]) / 3.0
			if not in_plaza(cen.x, cen.z, 0.4): keep.append_array(PackedInt32Array([I[i], I[i + 1], I[i + 2]]))
		I = keep
	s[0] = V; s[1] = Nn; s[2] = U; s[3] = Tg; s[4] = I; s[6] = Cl


## Is (x, z) on any drawn ribbon (a road, a street, a lane, a plaza, a quay), `margin` inside its
## edge? A fine index of the segments (8 m cells), built per 250 m tile the first time it is asked
## about (OuterTowns keeps the aprons round the buildings off the streets with it).
const SEG_CELL := 8.0
var _seg_cells: Dictionary = {}
var _seg_tiles: Dictionary = {}


func on_ribbon(x: float, z: float, margin := 0.0) -> bool:
	var t := Vector2i(floori(x / TILE), floori(z / TILE))
	for dj in range(-1, 2):
		for di in range(-1, 2):
			_index_tile(Vector2i(t.x + di, t.y + dj))
	var q := Vector2(x, z)
	for sg in _seg_cells.get(Vector2i(floori(x / SEG_CELL), floori(z / SEG_CELL)), []):
		if Geometry2D.get_closest_point_to_segment(q, sg[0], sg[1]).distance_to(q) < float(sg[2]) - margin: return true
	return false


## The ribbon segments ([a, b, half width]) of the SEG_CELL cells covering `rect`, by cell: a
## private snapshot a worker thread may read while this thread keeps indexing (OuterFlora keeps
## its grass and trees off the paving with it). Main thread only.
func segments_near(rect: Rect2) -> Dictionary:
	for tj in range(floori(rect.position.y / TILE) - 1, floori(rect.end.y / TILE) + 2):
		for ti in range(floori(rect.position.x / TILE) - 1, floori(rect.end.x / TILE) + 2):
			_index_tile(Vector2i(ti, tj))
	var out: Dictionary = {}
	for cj in range(floori(rect.position.y / SEG_CELL), floori(rect.end.y / SEG_CELL) + 1):
		for ci in range(floori(rect.position.x / SEG_CELL), floori(rect.end.x / SEG_CELL) + 1):
			var c := Vector2i(ci, cj)
			if _seg_cells.has(c): out[c] = (_seg_cells[c] as Array).duplicate()
	return out


## Is (x, z) on a ribbon of a `segments_near` snapshot, `margin` inside its edge (negative: outside)?
static func on_snapshot(snap: Dictionary, x: float, z: float, margin := 0.0) -> bool:
	var q := Vector2(x, z)
	for sg in snap.get(Vector2i(floori(x / SEG_CELL), floori(z / SEG_CELL)), []):
		if Geometry2D.get_closest_point_to_segment(q, sg[0], sg[1]).distance_to(q) < float(sg[2]) - margin: return true
	return false


func _index_tile(t: Vector2i) -> void:
	if _seg_tiles.has(t): return
	_seg_tiles[t] = true
	for run in tiles.get(t, []):
		var e: Dictionary = roads[run[0]]
		var pts: PackedVector3Array = e.pts
		var hw: float = float(e.width) * 0.5
		for k in range(int(run[1]), mini(int(run[2]), pts.size() - 1)):
			var a := Vector2(pts[k].x, pts[k].z); var b := Vector2(pts[k + 1].x, pts[k + 1].z)
			var bb := Rect2(a, Vector2.ZERO).expand(b).grow(hw + 1.0)
			for cj in range(floori(bb.position.y / SEG_CELL), floori(bb.end.y / SEG_CELL) + 1):
				for ci in range(floori(bb.position.x / SEG_CELL), floori(bb.end.x / SEG_CELL) + 1):
					var c := Vector2i(ci, cj)
					if not _seg_cells.has(c): _seg_cells[c] = []
					_seg_cells[c].append([a, b, hw])


## Plazas (the `plaza` ribbons: a segment and a half width). Is (x, z) on one, `margin` inside its edge?
var plazas: Array = []


func in_plaza(x: float, z: float, margin := 0.0) -> bool:
	var q := Vector2(x, z)
	for pz in plazas:
		var a: Vector2 = pz[0]; var ab: Vector2 = pz[1] - a
		var L2 := ab.length_squared()
		if L2 < 1e-4: continue
		var t := (q - a).dot(ab) / L2
		if t <= 0.0 or t >= 1.0: continue
		if (a + ab * t).distance_to(q) < float(pz[2]) - margin: return true
	return false


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


## Road furniture: white delineator posts with a black band every ~48 m beyond the shoulder,
## red-and-white chevron boards before sharp bends, and street lights on the approaches to the towns.
var _town_centres: Array = []


func _near_town(p: Vector3, extra: float) -> bool:
	if _town_centres.is_empty():
		for t: Dictionary in outer.ground.plan.get("towns", []):
			_town_centres.append([Vector2(t.center[0], t.center[1]), float(t.radius)])
	for tc in _town_centres:
		if Vector2(p.x, p.z).distance_to(tc[0]) < float(tc[1]) + extra: return true
	return false


func _furniture(e: Dictionary, k0: int, k1: int, st: SurfaceTool, lamps: Array[Transform3D]) -> bool:
	var pts: PackedVector3Array = e.pts
	var n := pts.size()
	var hw: float = e.width * 0.5 + SHOULDER.get(e.kind, 0.0)
	var made := false
	for k in range(k0, k1 + 1):
		if k < 3 or k > n - 4 or e.bridge[k] == 1: continue
		var a := pts[k - 1]; var b := pts[k + 1]
		var tan := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
		var right := Vector3(-tan.z, 0.0, tan.x)
		var town := _near_town(pts[k], 120.0)
		if town and e.kind <= 1 and _near_town(pts[k], 350.0) and k % 8 == 0:
			# street lights on the approaches: alternate sides, arm over the carriageway
			var side := 1.0 if (k / 8) % 2 == 0 else -1.0
			var q := pts[k] + right * side * (hw + 0.4)
			q.y = outer.height_at(q.x, q.z)
			lamps.append(Transform3D(Basis(Vector3.UP, atan2(-right.x * side, -right.z * side)), q))
		if town: continue
		if k % 12 == 0 and e.kind <= 1:
			for side: float in [-1.0, 1.0]:
				var q := pts[k] + right * side * (hw + 0.7)
				q.y = outer.height_at(q.x, q.z)
				_cbox(st, q + Vector3(0, 0.5, 0), Vector3(0.12, 1.0, 0.12), Color(0.94, 0.94, 0.92))
				_cbox(st, q + Vector3(0, 0.86, 0), Vector3(0.13, 0.14, 0.13), Color(0.08, 0.08, 0.08))
				_cbox(st, q + Vector3(0, 0.86, 0) - Vector3(tan.x, 0, tan.z) * side * 0.066, Vector3(0.05, 0.06, 0.02), Color(1.0, 0.55, 0.1))
			made = true
		# bend warnings: the heading turns > 40 degrees over the next 100 m
		if k % 6 == 0 and k + 25 < n and e.kind <= 1:
			var t2 := (pts[k + 25] - pts[k + 23]); t2.y = 0.0
			var turn := tan.angle_to(t2.normalized())
			if turn > deg_to_rad(40.0):
				var left_turn := tan.cross(t2.normalized()).y > 0.0
				var q := pts[k] + right * (hw + 0.9)
				q.y = outer.height_at(q.x, q.z)
				_chevron(st, q, tan, right, left_turn)
				made = true
	return made


## A chevron board on two posts facing the oncoming traffic (red with white arrows).
static func _chevron(st: SurfaceTool, q: Vector3, tan: Vector3, right: Vector3, left_turn: bool) -> void:
	for s in [-0.45, 0.45]:
		_cbox(st, q + right * s + Vector3(0, 0.7, 0), Vector3(0.07, 1.4, 0.07), Color(0.6, 0.6, 0.6))
	var c := q + Vector3(0, 1.55, 0)
	var face := -tan
	var w := right * 0.6
	# the board
	_cquad(st, c - w + Vector3(0, -0.25, 0), c + w + Vector3(0, -0.25, 0), c + w + Vector3(0, 0.25, 0), c - w + Vector3(0, 0.25, 0), face, Color(0.8, 0.12, 0.1))
	# two white arrows
	var dir := -1.0 if left_turn else 1.0
	for i in range(2):
		var o := c + right * (-0.25 + i * 0.45) * 1.0 + face * 0.01
		var tip := o + right * dir * 0.14
		_cquad(st, o - right * dir * 0.08 + Vector3(0, 0.18, 0), tip + Vector3(0, 0.0, 0), tip + Vector3(0, 0.0, 0), o - right * dir * 0.08 + Vector3(0, 0.08, 0), face, Color(0.96, 0.96, 0.94))
		_cquad(st, o - right * dir * 0.08 + Vector3(0, -0.08, 0), tip, tip, o - right * dir * 0.08 + Vector3(0, -0.18, 0), face, Color(0.96, 0.96, 0.94))
		_cquad(st, o - right * dir * 0.08 + Vector3(0, 0.08, 0), tip, tip, o - right * dir * 0.08 + Vector3(0, -0.08, 0), face, Color(0.96, 0.96, 0.94))


static func _cquad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col: Color) -> void:
	for v in [a, b, c, a, c, d]:
		st.set_normal(n); st.set_color(col); st.add_vertex(v)
	for v in [a, c, b, a, d, c]:
		st.set_normal(-n); st.set_color(col); st.add_vertex(v)


static func _cbox(st: SurfaceTool, c: Vector3, s: Vector3, col: Color) -> void:
	var h := s * 0.5
	var p := [c + Vector3(-h.x, -h.y, -h.z), c + Vector3(h.x, -h.y, -h.z), c + Vector3(h.x, h.y, -h.z), c + Vector3(-h.x, h.y, -h.z),
		c + Vector3(-h.x, -h.y, h.z), c + Vector3(h.x, -h.y, h.z), c + Vector3(h.x, h.y, h.z), c + Vector3(-h.x, h.y, h.z)]
	var faces := [[0, 3, 2, 1, Vector3(0, 0, -1)], [4, 5, 6, 7, Vector3(0, 0, 1)], [0, 4, 7, 3, Vector3(-1, 0, 0)],
		[1, 2, 6, 5, Vector3(1, 0, 0)], [3, 7, 6, 2, Vector3(0, 1, 0)]]
	for f in faces:
		for i in [0, 2, 1, 0, 3, 2]:
			st.set_normal(f[4]); st.set_color(col); st.add_vertex(p[f[i]])


func _km_posts(e: Dictionary, k0: int, k1: int, st: SurfaceTool) -> bool:
	var made := false
	for k in range(k0, k1 + 1):
		if k % 250 != 0 or k == 0 or e.bridge[k] == 1: continue      # every kilometre (4 m samples)
		var pts: PackedVector3Array = e.pts
		var a := pts[maxi(k - 1, 0)]; var b := pts[mini(k + 1, pts.size() - 1)]
		var tan := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
		var q: Vector3 = pts[k] + Vector3(-tan.z, 0, tan.x) * (float(e.width) * 0.5 + 1.2)
		q.y = outer.height_at(q.x, q.z) - 0.1
		_cbox(st, q + Vector3(0, 0.4, 0), Vector3(0.3, 0.8, 0.18), Color(0.93, 0.92, 0.88))
		_cbox(st, q + Vector3(0, 0.86, 0), Vector3(0.3, 0.14, 0.19), Color(0.75, 0.15, 0.12))
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
## A bridge or viaduct over samples a..b. Highways cross on concrete: a box-girder deck on tapered
## wall piers with hammerhead caps, concrete barriers topped with a steel rail. Roads and tracks
## (and the causeway) cross on masonry: arches springing from piers, spandrel walls, a string
## course, a parapet with coping. Both are ArchMesh geometry in the architecture kit's material, so
## the stone and concrete weather like the towns. Collision: the deck and the parapets' inner faces.
func _build_bridge(e: Dictionary, a: int, b: int) -> void:
	var pts: PackedVector3Array = e.pts
	_flare_ends = (0 if (a == 0 and String(e.get("from", "")).begins_with("core_")) else 1) | (0 if e.get("seam", false) else 2)
	a = maxi(a - 1, 0); b = mini(b + 1, pts.size() - 1)
	if b - a < 2: return
	var hw: float = e.width * 0.5 + 0.8
	var stone: bool = e.kind >= 1
	var n := b - a + 1
	# the frame at every sample: centre, right, deck height, foot (ground or sea bed)
	var C := PackedVector3Array(); var Rt := PackedVector3Array(); var foot := PackedFloat32Array()
	var length := 0.0
	for k in range(a, b + 1):
		var p := pts[k]
		var pa := pts[maxi(k - 1, 0)]; var pb := pts[mini(k + 1, pts.size() - 1)]
		var tan := Vector3(pb.x - pa.x, 0.0, pb.z - pa.z).normalized()
		var wsc := 1.0
		if e.has("widths"): wsc = (float(e.widths[k]) + 1.6) / (float(e.width) + 1.6)      # a tapering deck
		C.append(p); Rt.append(Vector3(-tan.z, 0.0, tan.x) * wsc)
		var g := outer.height_at(p.x, p.z)
		foot.append(minf(g, 0.0) - 2.5 if g < 0.5 else g - 0.8)
		if k > a: length += p.distance_to(pts[k - 1])
	if e.has("tail"):
		# (a core seam: its deck runs on a little over the spoke's, see _core_seams)
		C.append(e.tail); Rt.append(Rt[Rt.size() - 1]); foot.append(foot[foot.size() - 1])
	var m := ArchMesh.new()
	m.uv_off = Vector2(absf(C[0].x) * 0.37, absf(C[0].z) * 0.21)
	var faces := PackedVector3Array()
	var lamps: Array[Transform3D] = []
	if stone: _masonry_bridge(m, C, Rt, foot, hw, faces)
	# (a core seam's deck has no parapets on the bank: a rider cutting the bend onto it must not
	# meet the end of a barrier)
	else: _concrete_bridge(m, C, Rt, foot, hw, faces, maxi(int(e.get("rail_from", 0)) - a, 0))
	for k in range(n):
		if k % 12 == 6 and length > 200.0:
			var side := 1.0 if (k / 12) % 2 == 0 else -1.0
			lamps.append(Transform3D(Basis(), C[k] + Rt[k] * side * (hw - 0.25)))
	var mesh := m.commit(null, ArchMaterials.merged())
	var mi := MeshInstance3D.new(); mi.name = "Bridge_%s_%d" % [e.id, a]
	mi.mesh = mesh
	mi.visibility_range_end = 7000.0
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
		NightLights.register(mmi, _lamp_heads(lamps))
	bridge_count += 1


## Deck collision (top at the sample heights) and the parapets' inner faces up to `ph`.
static func _deck_faces(C: PackedVector3Array, Rt: PackedVector3Array, hw: float, inset: float, ph: float, faces: PackedVector3Array, rail_from := 0) -> void:
	for k in range(C.size() - 1):
		var l0 := C[k] - Rt[k] * hw; var r0 := C[k] + Rt[k] * hw
		var l1 := C[k + 1] - Rt[k + 1] * hw; var r1 := C[k + 1] + Rt[k + 1] * hw
		faces.append_array(PackedVector3Array([l0, r0, r1, l0, r1, l1]))
		if k < rail_from: continue
		for side: float in [-1.0, 1.0]:
			var e0: Vector3 = C[k] + Rt[k] * side * (hw - inset) + Rt[k].normalized() * side * _flare(k, rail_from, C.size())
			var e1: Vector3 = C[k + 1] + Rt[k + 1] * side * (hw - inset) + Rt[k + 1].normalized() * side * _flare(k + 1, rail_from, C.size())
			var up := Vector3(0, ph, 0)
			faces.append_array(PackedVector3Array([e0, e1, e1 + up, e0, e1 + up, e0 + up]))


## The parapets flare out at both ends of a deck (FLARE m over the last sample): a rider on the
## approach's shoulder meets them at a glancing angle, not their end head-on (the Isola causeway's
## inner bridge end crashed the bike).
## Not where the deck runs on into another: a spoke's first span meets its core seam's deck.
const FLARE := 1.4
static var _flare_ends := 3            # bit 1: the start flares, bit 2: the end (set per bridge)


static func _flare(k: int, first: int, n: int) -> float:
	if k == first and (_flare_ends & 1) != 0: return FLARE
	if k == n - 1 and (_flare_ends & 2) != 0: return FLARE
	return 0.0


## Both windings of a quad (walls whose outward side depends on the road's curve direction).
static func _q2(m: ArchMesh, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	m.quad(a, b, c, d); m.quad(b, a, d, c)


func _masonry_bridge(m: ArchMesh, C: PackedVector3Array, Rt: PackedVector3Array, foot: PackedFloat32Array, hw: float, faces: PackedVector3Array) -> void:
	var n := C.size()
	var hmax := 0.0
	for k in range(n): hmax = maxf(hmax, C[k].y - foot[k])
	# span in samples (4 m): short arches on a low causeway, longer ones on a tall viaduct
	var span := clampi(roundi(hmax * 0.14), 3, 6)
	var ashlar := Color(0.86, 0.8, 0.7)
	var deck_t := 1.1
	# piers at the span joints; each span an arch from pier face to pier face
	var joints: Array[int] = [0]
	var k := span
	while k < n - 2:
		joints.append(k); k += span
	joints.append(n - 1)
	var pier_w := 1.6 if hmax < 14.0 else 2.4
	for j in range(joints.size() - 1):
		var k0 := joints[j]; var k1 := joints[j + 1]
		# dense points along the span (1 m), each with its centre, right and deck height
		var S: Array = []
		var slen := 0.0
		for q in range(k0, k1):
			var d := C[q].distance_to(C[q + 1])
			var sub := maxi(int(ceil(d)), 1)
			for u in range(sub):
				var t := float(u) / sub
				S.append([C[q].lerp(C[q + 1], t), Rt[q].lerp(Rt[q + 1], t).normalized(), lerpf(foot[q], foot[q + 1], t), slen + d * t])
			slen += d
		S.append([C[k1], Rt[k1], foot[k1], slen])
		var fmax := -INF
		for sp in S: fmax = maxf(fmax, sp[2])
		var deck_lo: float = minf(C[k0].y, C[k1].y) - deck_t
		var open := slen - pier_w
		var rise := minf(open * 0.5, deck_lo - 0.6 - (fmax + 0.5))
		var ys := deck_lo - 0.6 - rise
		for side: float in [-1.0, 1.0]:
			m.layer = float(ArchMaterials.ASHLAR) + 0.35; m.tint = ashlar
			m.ground = fmax - 1.0; m.eave = C[k0].y
			for i in range(S.size() - 1):
				var A: Array = S[i]; var B: Array = S[i + 1]
				var ca: Vector3 = A[0]; var cb: Vector3 = B[0]
				var pa: Vector3 = ca + (A[1] as Vector3) * side * hw; var pb: Vector3 = cb + (B[1] as Vector3) * side * hw
				var ya: float = _arch_y(A[3], slen, pier_w, ys, rise, A[2]); var yb: float = _arch_y(B[3], slen, pier_w, ys, rise, B[2])
				var ta := ca.y - 0.02; var tb := cb.y - 0.02
				_q2(m, Vector3(pa.x, ya, pa.z), Vector3(pb.x, yb, pb.z), Vector3(pb.x, tb, pb.z), Vector3(pa.x, ta, pa.z))
				if side > 0.0:
					# the arch barrel (intrados) and, under the piers, their feet
					var la: Vector3 = ca - (A[1] as Vector3) * hw; var lb: Vector3 = cb - (B[1] as Vector3) * hw
					m.layer = float(ArchMaterials.RUBBLE) + 0.5; m.tint = ashlar.darkened(0.12)
					_q2(m, Vector3(la.x, ya, la.z), Vector3(lb.x, yb, lb.z), Vector3(pb.x, yb, pb.z), Vector3(pa.x, ya, pa.z))
					m.layer = float(ArchMaterials.ASHLAR) + 0.35; m.tint = ashlar
			# the string course under the parapet
			m.layer = float(ArchMaterials.STONE) + 0.2; m.tint = Color(0.92, 0.88, 0.8)
			for i in range(S.size() - 1):
				var A: Array = S[i]; var B: Array = S[i + 1]
				var pa: Vector3 = (A[0] as Vector3) + (A[1] as Vector3) * side * (hw + 0.18); var pb: Vector3 = (B[0] as Vector3) + (B[1] as Vector3) * side * (hw + 0.18)
				var y0: float = (A[0] as Vector3).y; var y1: float = (B[0] as Vector3).y
				_q2(m, Vector3(pa.x, y0 - 0.35, pa.z), Vector3(pb.x, y1 - 0.35, pb.z), Vector3(pb.x, y1 - 0.05, pb.z), Vector3(pa.x, y0 - 0.05, pa.z))
				_q2(m, Vector3(pa.x, y0 - 0.05, pa.z), Vector3(pb.x, y1 - 0.05, pb.z), pb - (B[1] as Vector3) * side * 0.18 + Vector3(0, -0.05, 0), pa - (A[1] as Vector3) * side * 0.18 + Vector3(0, -0.05, 0))
		# the pier at the span's start (not at the abutment)
		if j > 0:
			_pier_box(m, C[k0], Rt[k0], hw + 0.35, pier_w, foot[k0] - 0.5, ys + 0.3, ashlar, true)
	# parapets with coping, the deck soffit edge
	_parapets(m, C, Rt, hw, 0.42, 1.0, Color(0.88, 0.83, 0.74), Color(0.93, 0.9, 0.84))
	_deck_faces(C, Rt, hw, 0.42, 1.0, faces)


static func _arch_y(s: float, slen: float, pier_w: float, ys: float, rise: float, foot_y: float) -> float:
	if rise < 0.8: return foot_y
	var u := (s - pier_w * 0.5) / maxf(slen - pier_w, 0.1)
	if u <= 0.0 or u >= 1.0: return maxf(foot_y, ys) if u <= 0.0 or u >= 1.0 else ys
	var c := u * 2.0 - 1.0
	return maxf(ys + rise * sqrt(maxf(1.0 - c * c, 0.0)), foot_y)


func _pier_box(m: ArchMesh, c: Vector3, rt: Vector3, half_across: float, along: float, y0: float, y1: float, tint: Color, cutwater: bool) -> void:
	if y1 - y0 < 0.3: return
	var fw := Vector3(rt.z, 0.0, -rt.x)
	m.layer = float(ArchMaterials.ASHLAR) + 0.4; m.tint = tint
	m.ground = y0 + 0.5; m.eave = y1 + 2.0
	var corners: Array[Vector3] = []
	for sa: float in [-1.0, 1.0]:
		for sb: float in [-1.0, 1.0]:
			corners.append(c + rt * sa * half_across + fw * sb * along * 0.5)
	# sides
	var ring := [corners[0], corners[1], corners[3], corners[2]]
	for i in range(4):
		var p: Vector3 = ring[i]; var q: Vector3 = ring[(i + 1) % 4]
		_q2(m, Vector3(p.x, y0, p.z), Vector3(q.x, y0, q.z), Vector3(q.x, y1, q.z), Vector3(p.x, y1, p.z))
	if cutwater and y0 < 0.0:
		# pointed cutwaters up- and downstream on a pier standing in the water
		for sa: float in [-1.0, 1.0]:
			var tip := c + rt * sa * (half_across + along * 0.7)
			var p0 := c + rt * sa * half_across + fw * along * 0.5; var p1 := c + rt * sa * half_across - fw * along * 0.5
			var top := minf(y1, 2.5)
			_q2(m, Vector3(p0.x, y0, p0.z), Vector3(tip.x, y0, tip.z), Vector3(tip.x, top, tip.z), Vector3(p0.x, top, p0.z))
			_q2(m, Vector3(tip.x, y0, tip.z), Vector3(p1.x, y0, p1.z), Vector3(p1.x, top, p1.z), Vector3(tip.x, top, tip.z))


## Parapet walls on both deck edges: outer and inner faces, a coping on top.
static func _parapets(m: ArchMesh, C: PackedVector3Array, Rt: PackedVector3Array, hw: float, thick: float, h: float, wall: Color, cope: Color, rail_from := 0) -> void:
	for side: float in [-1.0, 1.0]:
		for k in range(rail_from, C.size() - 1):
			var f0: Vector3 = Rt[k].normalized() * side * _flare(k, rail_from, C.size())
			var f1: Vector3 = Rt[k + 1].normalized() * side * _flare(k + 1, rail_from, C.size())
			var o0: Vector3 = C[k] + Rt[k] * side * hw + f0; var o1: Vector3 = C[k + 1] + Rt[k + 1] * side * hw + f1
			var i0: Vector3 = C[k] + Rt[k] * side * (hw - thick) + f0; var i1: Vector3 = C[k + 1] + Rt[k + 1] * side * (hw - thick) + f1
			var up := Vector3(0, h, 0)
			m.layer = float(ArchMaterials.ASHLAR) + 0.3; m.tint = wall
			m.ground = minf(C[k].y, C[k + 1].y) - 3.0; m.eave = maxf(C[k].y, C[k + 1].y) + h + 0.5
			_q2(m, o0 - Vector3(0, 0.02, 0), o1 - Vector3(0, 0.02, 0), o1 + up, o0 + up)
			_q2(m, i0, i1, i1 + up, i0 + up)
			m.layer = float(ArchMaterials.STONE) + 0.15; m.tint = cope
			var cu := Vector3(0, 0.1, 0)
			var o0c := o0 + Rt[k] * side * 0.06; var o1c := o1 + Rt[k + 1] * side * 0.06
			_q2(m, o0c + up, o1c + up, i1 + up + cu, i0 + up + cu)
			_q2(m, o0c + up - cu, o1c + up - cu, o1c + up, o0c + up)


func _concrete_bridge(m: ArchMesh, C: PackedVector3Array, Rt: PackedVector3Array, foot: PackedFloat32Array, hw: float, faces: PackedVector3Array, rail_from := 0) -> void:
	var n := C.size()
	var conc := Color(0.8, 0.79, 0.76)
	var girder := 2.1
	for k in range(n - 1):
		var up0 := C[k]; var up1 := C[k + 1]
		for side: float in [-1.0, 1.0]:
			# the slab edge (a fascia 0.45 m deep) and the cantilever underside, then the box web
			var e0 := up0 + Rt[k] * side * hw; var e1 := up1 + Rt[k + 1] * side * hw
			var w0 := up0 + Rt[k] * side * hw * 0.55; var w1 := up1 + Rt[k + 1] * side * hw * 0.55
			m.layer = float(ArchMaterials.STONE) + 0.5; m.tint = conc
			m.ground = up0.y - girder - 1.0; m.eave = up0.y + 1.5
			_q2(m, e0 + Vector3(0, -0.45, 0), e1 + Vector3(0, -0.45, 0), e1 - Vector3(0, 0.02, 0), e0 - Vector3(0, 0.02, 0))
			_q2(m, e0 + Vector3(0, -0.45, 0), e1 + Vector3(0, -0.45, 0), w1 + Vector3(0, -0.7, 0), w0 + Vector3(0, -0.7, 0))
			_q2(m, w0 + Vector3(0, -0.7, 0), w1 + Vector3(0, -0.7, 0), w1 + Vector3(0, -girder, 0), w0 + Vector3(0, -girder, 0))
		var l0 := up0 - Rt[k] * hw * 0.55 - Vector3(0, girder, 0); var r0 := up0 + Rt[k] * hw * 0.55 - Vector3(0, girder, 0)
		var l1 := up1 - Rt[k + 1] * hw * 0.55 - Vector3(0, girder, 0); var r1 := up1 + Rt[k + 1] * hw * 0.55 - Vector3(0, girder, 0)
		_q2(m, l0, r0, r1, l1)
		# piers every ~40 m where the deck stands clear of the ground or the sea
		if k % 10 == 5 and k < n - 3:
			var h := C[k].y - girder - foot[k]
			if h > 1.0:
				_wall_pier(m, C[k], Rt[k], hw, foot[k], C[k].y - girder, conc)
	# barriers: a concrete safety kerb with a steel rail on posts
	_parapets(m, C, Rt, hw, 0.45, 0.85, Color(0.84, 0.83, 0.8), Color(0.86, 0.85, 0.82), rail_from)
	m.layer = float(ArchMaterials.IRON) + 0.3; m.tint = Color(0.62, 0.64, 0.66)
	for side: float in [-1.0, 1.0]:
		for k in range(rail_from, n - 1):
			var f0: Vector3 = Rt[k].normalized() * side * _flare(k, rail_from, n)
			var f1: Vector3 = Rt[k + 1].normalized() * side * _flare(k + 1, rail_from, n)
			var p0 := C[k] + Rt[k] * side * (hw - 0.22) + f0 + Vector3(0, 1.1, 0); var p1 := C[k + 1] + Rt[k + 1] * side * (hw - 0.22) + f1 + Vector3(0, 1.1, 0)
			_q2(m, p0, p1, p1 + Vector3(0, 0.12, 0), p0 + Vector3(0, 0.12, 0))
			if k % 1 == 0:
				var c := C[k] + Rt[k] * side * (hw - 0.22) + f0
				m.cbox(c + Vector3(0, 0.98, 0), Vector3(0.08, 0.26, 0.08))
	_deck_faces(C, Rt, hw, 0.45, 1.2, faces, rail_from)


func _wall_pier(m: ArchMesh, c: Vector3, rt: Vector3, hw: float, y0: float, y1: float, conc: Color) -> void:
	var fw := Vector3(rt.z, 0.0, -rt.x)
	m.layer = float(ArchMaterials.STONE) + 0.55; m.tint = conc.darkened(0.04)
	m.ground = y0 + 0.6; m.eave = y1 + 1.0
	# a tapered wall pier: narrow at the foot, wider under the hammerhead cap
	var hb := hw * 0.32; var ht := hw * 0.45; var th := 1.1
	var cap := hw * 0.62
	for side: float in [-1.0, 1.0]:
		var b0 := c + rt * side * hb - fw * th; var b1 := c + rt * side * hb + fw * th
		var t0 := c + rt * side * ht - fw * th; var t1 := c + rt * side * ht + fw * th
		_q2(m, Vector3(b0.x, y0, b0.z), Vector3(b1.x, y0, b1.z), Vector3(t1.x, y1 - 1.4, t1.z), Vector3(t0.x, y1 - 1.4, t0.z))
	for sf: float in [-1.0, 1.0]:
		var bl := c - rt * hb + fw * sf * th; var br := c + rt * hb + fw * sf * th
		var tl := c - rt * ht + fw * sf * th; var tr := c + rt * ht + fw * sf * th
		_q2(m, Vector3(bl.x, y0, bl.z), Vector3(br.x, y0, br.z), Vector3(tr.x, y1 - 1.4, tr.z), Vector3(tl.x, y1 - 1.4, tl.z))
	# the cap
	var keep := m.xf
	m.xf = Transform3D(Basis(rt, Vector3.UP, -fw), Vector3(c.x, 0, c.z))
	m.box(Vector3(-cap, y1 - 1.4, -th - 0.2), Vector3(cap, y1, th + 0.2))
	m.xf = keep


static func _quad_one(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	# one-sided quad facing n (winding chosen from n)
	var fn := (b - a).cross(c - a)
	if fn.dot(n) > 0.0:
		for v in [a, c, b, a, d, c]:
			st.set_normal(n); st.add_vertex(v)
	else:
		for v in [a, b, c, a, c, d]:
			st.set_normal(n); st.add_vertex(v)


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
	# the lamp head is the shared bulb glass: dark by day, lit with the street lamps (DayNight)
	m1.surface_set_material(0, pole); m1.surface_set_material(1, NightLights.bulb_material())
	_lamp = m1
	return _lamp


## Where each lamp's light hangs (under the head at the end of the arm), for the NightLights pool.
static func _lamp_heads(xfs: Array[Transform3D]) -> PackedVector3Array:
	var out := PackedVector3Array()
	for xf in xfs: out.append(xf * Vector3(0, 6.6, 0.7))
	return out
