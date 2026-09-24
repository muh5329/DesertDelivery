class_name BuildingKit
extends RefCounted
## The architecture kit: turns plot records (data/outer/plan.json, ADR 0010; CONTEXT "Plot") into
## buildings with a strong identity per town style, and the core island's houses (style "core").
##
##   build_group(parent, plots, origin)  every plot of a streamed group under `parent` (whose global
##       position is `origin`): ONE merged mesh (walls, reveals, trim, roofs; one surface, one
##       material), one MultiMeshInstance3D per module type (windows, doors, balconies, chimneys...),
##       one StaticBody3D with a box / convex shape per building part.
##   build_lod(plots) -> Mesh             the whole-town silhouette: vertex coloured boxes, roofs,
##       towers, walls inset 0.3 m so the detailed buildings cover it when both show.
##   build_local(parent, plot, collide)   one building in `parent`'s own frame (WorldKit._house).
##   annotate(plots)                      marks party walls (sides touching a neighbour) in place.
##
## Plot: {id, style, kind, x, z, y (pad), yaw (degrees in plan.json; the street side faces
## (sin yaw, 0, cos yaw)), w (frontage, local x), d (depth, local z), floors, seed, tags, ground_min}.
## Styles: puerto, valdoro, sarmada, isola, campo, core. Unknown kinds build as houses.
## Everything is deterministic from the plot's seed. See world/kit/building/ for the parts:
## ArchStyles (plans), ArchFacade (walls, openings, roofs), ArchModules (instanced pieces),
## ArchSpecial (towers, churches, walls, gates, windmills, citadel), ArchMaterials, ArchMesh.

const L = preload("res://world/kit/building/arch_materials.gd")
const F = preload("res://world/kit/building/arch_facade.gd")
const M = preload("res://world/kit/building/arch_modules.gd")
const UP := Vector3.UP

static var last_ms := 0.0
static var total_ms := 0.0
static var geom_ms := 0.0
static var finish_ms := 0.0
static var calls := 0
static var last_keys: Array = []
static var prof := {}


static func _pt(key: String, t0: int) -> int:
	var t := Time.get_ticks_usec()
	prof[key] = prof.get(key, 0) + (t - t0)
	return t


## Start decoding the kit's textures in the background (boot).
static func warm() -> void:
	ArchMaterials.warm()


static func yaw_of(p: Dictionary) -> float:
	return deg_to_rad(float(p.get("yaw", 0.0)))


static func build_group(parent: Node3D, plots: Array, origin: Vector3) -> void:
	if parent == null: return
	var t0 := Time.get_ticks_usec()
	var c := ArchCtx.new()
	c.far = 220.0
	for p: Dictionary in plots:
		var xf := Transform3D(Basis(UP, yaw_of(p)), Vector3(float(p.x), float(p.y), float(p.z)) - origin)
		build_plot(c, p, xf)
	var t1 := Time.get_ticks_usec()
	c.bake_modules(2)
	last_keys = c.inst.keys()
	c.finish(parent)
	var t2 := Time.get_ticks_usec()
	geom_ms += (t1 - t0) / 1000.0
	finish_ms += (t2 - t1) / 1000.0
	last_ms = (t2 - t0) / 1000.0
	total_ms += last_ms
	calls += 1


## One building in `parent`'s frame: the plot's x, y, z, yaw are in that frame.
static func build_local(parent: Node3D, p: Dictionary, collide := true) -> void:
	var c := ArchCtx.new()
	c.collide = collide
	c.far = 160.0
	var xf := Transform3D(Basis(UP, yaw_of(p)), Vector3(float(p.get("x", 0.0)), float(p.get("y", 0.0)), float(p.get("z", 0.0))))
	build_plot(c, p, xf)
	c.bake_modules()
	c.finish(parent, "House")


static func build_plot(c: ArchCtx, p: Dictionary, xf: Transform3D) -> void:
	c.begin(xf, int(p.get("seed", 1)))
	c.m.uv_off = Vector2(c.rng.randf() * 40.0, c.rng.randf() * 40.0)
	var kind: String = p.get("kind", "house")
	match kind:
		"tower": ArchSpecial.tower(c, p)
		"church": ArchSpecial.church(c, p)
		"windmill": ArchSpecial.windmill(c, p)
		"lighthouse": ArchSpecial.lighthouse(c, p)
		"citadel": ArchSpecial.citadel(c, p)
		"gate": ArchSpecial.gate(c, p)
		"wall": ArchSpecial.town_wall(c, p)
		"market_hall":
			var q := ArchStyles.plan(p)
			q.arcade = true; q.shop = true
			if q.roof == "flat": q.dome = true
			house(c, p, q)
		_:
			var t0 := Time.get_ticks_usec()
			var q := ArchStyles.plan(p)
			_pt("plan", t0)
			house(c, p, q)


## Mark each plot's sides that touch a neighbour (`party` = [left (-x), right (+x)]) so rows share
## party walls: no windows and no roof overhang there. O(n) with a spatial hash.
static func annotate(plots: Array) -> void:
	var cell := 24.0
	var grid := {}
	for i in range(plots.size()):
		var p: Dictionary = plots[i]
		var k := Vector2i(floori(float(p.x) / cell), floori(float(p.z) / cell))
		if not grid.has(k): grid[k] = []
		grid[k].append(i)
	for i in range(plots.size()):
		var p: Dictionary = plots[i]
		if p.kind in ["wall", "gate", "citadel", "tower", "windmill", "church", "lighthouse"]:
			p["party"] = [false, false]
			continue
		var yaw := yaw_of(p)
		var f := Vector2(sin(yaw), cos(yaw)); var t := Vector2(f.y, -f.x)
		var c0 := Vector2(float(p.x), float(p.z))
		var hw := float(p.w) * 0.5; var hd := float(p.d) * 0.5
		var party := [false, false]
		var k := Vector2i(floori(c0.x / cell), floori(c0.y / cell))
		for s: int in [0, 1]:
			var sgn := -1.0 if s == 0 else 1.0
			var hits := 0
			for a: float in [-0.6, 0.0, 0.6]:
				var q := c0 + t * sgn * (hw + 0.35) + f * (a * hd)
				var hit := false
				for dx: int in [-1, 0, 1]:
					for dz: int in [-1, 0, 1]:
						for j in grid.get(k + Vector2i(dx, dz), []):
							if j == i: continue
							var o: Dictionary = plots[j]
							if o.kind in ["wall", "gate", "citadel"]: continue
							var oy := yaw_of(o)
							var of := Vector2(sin(oy), cos(oy)); var ot := Vector2(of.y, -of.x)
							var r := q - Vector2(float(o.x), float(o.z))
							if absf(r.dot(ot)) <= float(o.w) * 0.5 + 0.05 and absf(r.dot(of)) <= float(o.d) * 0.5 + 0.05:
								hit = true; break
						if hit: break
					if hit: break
				if hit: hits += 1
			party[s] = hits >= 2
		p["party"] = party


# ---------------------------------------------------------------- the ordinary building
static func house(c: ArchCtx, p: Dictionary, q: Dictionary) -> void:
	var m := c.m
	var rng := c.rng
	var w: float = q.w; var d: float = q.d
	var fh: Array = q.fh
	var floors := fh.size()
	var style: String = q.style
	var party: Array = q.party
	var lift := 0.8 if q.get("staddles", false) else 0.0
	var ys := PackedFloat32Array([lift])
	for h in fh: ys.append(ys[ys.size() - 1] + h)
	var H: float = ys[floors]
	q.H = H
	var yb := minf(float(p.get("ground_min", p.get("y", 0.0))) - float(p.get("y", 0.0)) - 0.5, -0.35)
	var flat: bool = q.roof == "flat"
	var ph: float = q.parapet if flat else 0.0
	var top := H + ph
	var wall_mat: Array = q.wall
	var trim: Array = q.get("trim", [L.STONE, ArchStyles.GRANITE])
	var paint: Color = q.paint
	var R: float = q.R
	# the front can step back for an external stair (isola) or an arcade (plaza porticoes)
	var zf := d * 0.5
	var stair := bool(q.ext_stair) and d >= 7.0 and w >= 6.5 and floors >= 2
	if stair: zf = d * 0.5 - 1.35
	var arcade := bool(q.arcade) and floors >= 2 and d >= 7.0
	var gallery := 2.8 if arcade else 0.0
	m.ground = 0.0
	m.eave = H if not flat else top
	# ---------------- faces: 0 front, 1 back, 2 right (+x), 3 left (-x)
	var faces := [
		[Transform3D(Basis(Vector3(1, 0, 0), UP, Vector3(0, 0, 1)), Vector3(-w * 0.5, 0, zf)), w],
		[Transform3D(Basis(Vector3(-1, 0, 0), UP, Vector3(0, 0, -1)), Vector3(w * 0.5, 0, -d * 0.5)), w],
		[Transform3D(Basis(Vector3(0, 0, -1), UP, Vector3(1, 0, 0)), Vector3(w * 0.5, 0, zf)), zf + d * 0.5],
		[Transform3D(Basis(Vector3(0, 0, 1), UP, Vector3(-1, 0, 0)), Vector3(-w * 0.5, 0, -d * 0.5)), zf + d * 0.5],
	]
	var zones := _zones(q, ys, floors, top)
	var base_mat: Array = zones[0][2]
	# ---------------- plinth (a stone base down to the lowest ground under the footprint)
	var pl_h: float = q.plinth_h + lift * 0.0
	var ground_ops := {}
	var tp := Time.get_ticks_usec()
	for side in range(4):
		var fx: Transform3D = faces[side][0]; var W: float = faces[side][1]
		var attached: bool = side >= 2 and party[1 if side == 2 else 0]
		var ops: Array = [] if attached else _openings(c, q, side, W, ys, fh, stair, arcade)
		ground_ops[side] = ops
		tp = _pt("layout", tp)
		# walls with their holes
		F.use(m, c.bxf, fx)
		var holes: Array = []
		for o in ops:
			if o.kind == "arcade": continue
			var zmat: Array = _zone_at(zones, float(o.y) + 0.05)
			m.layer = zmat[0]; m.tint = zmat[1]
			F.opening(m, holes, o.x, o.y, o.w, o.h, o.R, o.arch, o.sill, o.key == "")
		if arcade and side == 0:
			_arcade_front(c, q, fx, W, ys, fh, holes, zones)
		for z in zones:
			m.layer = z[2][0]; m.tint = z[2][1]
			var x0 := 0.0; var x1 := W
			if attached:
				x0 = 0.01; x1 = W - 0.01
			F.wall(m, z[0], z[1], x0, x1, holes)
		tp = _pt("walls", tp)
		for o in ops:
			if o.key != "":
				var zw: Array = _zone_at(zones, float(o.y) + 0.05)
				c.place(o.key, fx * Transform3D(Basis(), Vector3(o.x, o.y, 0)), o.custom, Color(zw[1].r, zw[1].g, zw[1].b, zw[0]))
			if o.has("awning"): c.place(o.awning, fx * Transform3D(Basis(), Vector3(o.x, o.y + o.h + 0.05, 0)), o.awning_col)
			if o.has("lantern"): c.place(M.lantern(), fx * Transform3D(Basis(), Vector3(o.x + o.w * 0.5 + 0.5, o.y + minf(o.h + 0.2, 2.8), 0)))
			if o.has("loggia"): _loggia(c, q, fx, o, zones)
			if o.has("pots"):
				for s: float in [-1.0, 1.0]:
					c.place(M.pot(), fx * Transform3D(Basis(UP, rng.randf() * TAU), Vector3(o.x + s * (o.w * 0.5 + 0.45), 0.0, 0.35)), M.PLANTS[rng.randi() % 4])
		tp = _pt("place", tp)
		# plinth along this face, cut at doors
		if lift <= 0.0 and not (arcade and side == 0):
			var out := 0.0 if attached else 0.05
			F.use(m, c.bxf, fx * Transform3D(Basis(), Vector3(0, 0, out)))
			m.layer = _plinth_layer(q); m.tint = _plinth_tint(q)
			var gh: Array = []
			for o in ops:
				if o.y < pl_h: gh.append(PackedFloat32Array([o.x - o.w * 0.5, o.y - (0.17 if o.kind == "door" else 0.0), o.x + o.w * 0.5, pl_h + 1.0]))
			var ex0 := -0.05 if side < 2 and not party[0 if side == 0 else 1] else 0.0
			var ex1 := W + (0.05 if side < 2 and not party[1 if side == 0 else 0] else 0.0)
			if side >= 2:
				ex0 = -out; ex1 = W + out
			F.wall(m, yb, pl_h, ex0, ex1, gh)
			if out > 0.0:
				# the ledge on top, between the doors
				var xs := [ex0]
				for g in gh: xs.append(g[0]); xs.append(g[2])
				xs.append(ex1)
				for i in range(0, xs.size() - 1, 2):
					var a: float = xs[i]; var b: float = xs[i + 1]
					if b - a > 0.01: m.quad(Vector3(a, pl_h, 0), Vector3(b, pl_h, 0), Vector3(b, pl_h, -out), Vector3(a, pl_h, -out))
	tp = _pt("plinth", tp)
	# ---------------- trim: corner pilasters, string courses, cornice
	F.use(m, c.bxf, faces[0][0])
	var Wf: float = faces[0][1]
	m.layer = trim[0]; m.tint = trim[1]
	if q.pilasters:
		var pw := 0.42 if style != "campo" else 0.55
		var y_from := pl_h if lift <= 0.0 else lift
		var y_to := H - (0.36 if int(q.cornice) > 0 else 0.0)
		m.box(Vector3(0.0, y_from, 0.0), Vector3(pw, y_to, 0.06), 16 | (2 if not party[0] else 0) | 1)
		m.box(Vector3(Wf - pw, y_from, 0.0), Vector3(Wf, y_to, 0.06), 16 | (1 if not party[1] else 0) | 2)
		for s: int in [2, 3]:
			if party[1 if s == 2 else 0]: continue
			F.use(m, c.bxf, faces[s][0])
			var Ws: float = faces[s][1]
			m.box(Vector3(0.0, y_from, 0.0), Vector3(pw, y_to, 0.06), 16 | 1)
			m.box(Vector3(Ws - pw, y_from, 0.0), Vector3(Ws, y_to, 0.06), 16 | 2)
		F.use(m, c.bxf, faces[0][0])
	if q.bands:
		for k in range(1, floors):
			var y := ys[k]
			_band_all(c, faces, party, y - 0.18, y + 0.02, 0.08)
	if int(q.cornice) > 0 and not flat:
		var heavy := int(q.cornice) >= 2
		_band_all(c, faces, party, H - (0.42 if heavy else 0.3), H, 0.16 if heavy else 0.12)
		_band_all(c, faces, party, H - (0.2 if heavy else 0.14), H, 0.32 if heavy else 0.22)
	tp = _pt("trim", tp)
	if q.kind in ["palazzo", "town_hall"] and not flat and w >= 7.0:
		_pediment(c, q, faces[0][0], faces[0][1], H, trim)
	# ---------------- roof
	m.xf = c.bxf
	var roof_top := _roof(c, q, w, d, H, top, party, zf, flat, ph)
	if q.kind in ["palazzo", "town_hall"] and q.style == "campo" and not flat:
		_turret(c, q, w, zf, roof_top, trim)
	tp = _pt("roof", tp)
	# ---------------- roofscape and extras
	_roofscape(c, q, w, d, H, top, roof_top, party, flat, ph, zf)
	if stair: _ext_stair(c, q, w, d, zf, ys, fh)
	if q.get("staddles", false):
		for sx: float in [-1.0, 0.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				c.place(M.staddle(lift), Transform3D(Basis(), Vector3(sx * (w * 0.5 - 0.4), 0.0, sz * (d * 0.5 - 0.4))))
		m.xf = c.bxf
		m.layer = L.TIMBER; m.tint = Color(0.7, 0.6, 0.5)
		m.box(Vector3(-w * 0.5, lift - 0.25, -d * 0.5), Vector3(w * 0.5, lift, d * 0.5), 63 - 4)
	tp = _pt("scape", tp)
	# ---------------- collision
	_collide(c, q, w, d, yb, H, top, flat, ph, zf, arcade, gallery, fh, stair, lift)
	tp = _pt("collide", tp)


## A classical pediment over the middle of a palazzo's front, standing on the cornice.
static func _pediment(c: ArchCtx, q: Dictionary, fx: Transform3D, W: float, H: float, trim: Array) -> void:
	var m := c.m
	F.use(m, c.bxf, fx)
	var pw := minf(W * 0.55, 6.0)
	var x0 := (W - pw) * 0.5; var x1 := x0 + pw
	var ph := pw * 0.22
	var zo := 0.34
	var wall: Array = _zone_at(_zones(q, PackedFloat32Array([0.0, H]), 1, H), H - 0.1)
	m.layer = wall[0]; m.tint = wall[1]
	m.tri(Vector3(x0 + 0.25, H, zo - 0.1), Vector3(x1 - 0.25, H, zo - 0.1), Vector3((x0 + x1) * 0.5, H + ph - 0.18, zo - 0.1))
	m.layer = trim[0]; m.tint = trim[1]
	var apex := Vector3((x0 + x1) * 0.5, H + ph, zo)
	var a := Vector3(x0, H, zo); var b := Vector3(x1, H, zo)
	for s: float in [-1.0, 1.0]:
		var e := a if s < 0 else b
		var t := 0.2
		# the raking cornice: a sloped slab from the corner to the apex, and its top
		F.quad_out(m, e, apex, apex + Vector3(0, t, 0), e + Vector3(0, t, 0), Vector3(0, 0, 1))
		F.quad_out(m, e + Vector3(0, t, 0), apex + Vector3(0, t, 0), apex + Vector3(0, t, -zo - 0.4), e + Vector3(0, t, -zo - 0.4), Vector3(-s * 0.3, 1, 0))
		F.quad_out(m, e, apex, apex + Vector3(0, 0, -zo - 0.4), e + Vector3(0, 0, -zo - 0.4), Vector3(0, -1, 0))
	m.box(Vector3(x0, H - 0.05, zo - 0.12), Vector3(x1, H + 0.12, zo), 4 | 16 | 1 | 2)
	m.xf = c.bxf


## The town hall's clock turret astride the ridge (plains towns).
static func _turret(c: ArchCtx, q: Dictionary, w: float, zf: float, roof_top: float, trim: Array) -> void:
	var m := c.m
	var s := 2.4
	var y0 := roof_top - 1.2
	var h := 3.6
	var zc := zf - 2.4
	m.xf = c.bxf
	var wall: Array = q.wall
	m.layer = wall[0]; m.tint = wall[1]
	m.box(Vector3(-s * 0.5, y0, zc - s * 0.5), Vector3(s * 0.5, y0 + h, zc + s * 0.5), 63 - 8 - 4)
	m.layer = trim[0]; m.tint = trim[1]
	m.box(Vector3(-s * 0.5 - 0.12, y0 + h - 0.25, zc - s * 0.5 - 0.12), Vector3(s * 0.5 + 0.12, y0 + h, zc + s * 0.5 + 0.12), 63)
	m.xf = c.bxf * Transform3D(Basis(), Vector3(0, 0, zc))
	F.hip(m, s + 0.2, s + 0.2, y0 + h, tan(deg_to_rad(40.0)), 0.2, 0.15, [ArchStyles.wx(L.ROOF_TILE, 0.3), Color.WHITE], [ArchStyles.wx(L.TIMBER, 0.3), Color(0.6, 0.5, 0.4)])
	m.xf = c.bxf
	c.place(M.clock(0.75), Transform3D(Basis(), Vector3(0, y0 + h - 1.25, zc + s * 0.5 + 0.02)))
	c.place(M.bell(0.3), Transform3D(Basis(), Vector3(0, y0 + h + 1.1, zc)))


## Vertical material zones of the walls: [[y0, y1, [layer, tint]], ...] bottom to top.
static func _zones(q: Dictionary, ys: PackedFloat32Array, floors: int, top: float) -> Array:
	var out: Array = []
	var wall_mat: Array = q.wall
	var y := ys[0]
	var base = q.base
	var style: String = q.style
	if base != null:
		var bh: float = ys[1] if style in ["puerto", "campo", "valdoro"] else 1.0
		if style == "core": bh = 0.9
		bh = minf(bh, top - 0.5)
		out.append([y, bh, base])
		y = bh
	var upper = q.upper
	if upper != null and int(upper[2]) < floors:
		var yu := ys[int(upper[2])]
		if yu > y + 0.1:
			out.append([y, yu, wall_mat])
			y = yu
		out.append([y, top, [upper[0], upper[1]]])
	else:
		out.append([y, top, wall_mat])
	return out


static func _zone_at(zones: Array, y: float) -> Array:
	for z in zones:
		if y >= z[0] and y < z[1]: return z[2]
	return zones[zones.size() - 1][2]


static func _plinth_layer(q: Dictionary) -> float:
	match q.style:
		"valdoro": return ArchStyles.wx(L.RUBBLE, q.weather)
		"sarmada": return ArchStyles.wx(L.ADOBE, q.weather)
		"isola": return ArchStyles.wx(L.PLASTER, q.weather)
		"core": return ArchStyles.wx(L.RUBBLE, q.weather)
	return ArchStyles.wx(L.ASHLAR, q.weather)


static func _plinth_tint(q: Dictionary) -> Color:
	match q.style:
		"valdoro": return Color(0.85, 0.85, 0.85)
		"sarmada": return Color(0.86, 0.66, 0.44)
		"isola": return (q.wall[1] as Color).darkened(0.25)
		"core": return Color(0.95, 0.9, 0.82)
		"campo": return ArchStyles.CAMPO_HONEY.darkened(0.08)
	return ArchStyles.GRANITE.darkened(0.05)


## A horizontal moulding round every exposed face (front always, back, sides unless party).
static func _band_all(c: ArchCtx, faces: Array, party: Array, y0: float, y1: float, out: float) -> void:
	var m := c.m
	for side in range(4):
		if side >= 2 and party[1 if side == 2 else 0]: continue
		F.use(m, c.bxf, faces[side][0])
		var W: float = faces[side][1]
		var mask := 4 | 8 | 16
		var e0 := 0.0; var e1 := W
		if side < 2:
			var left_party: bool = party[0 if side == 0 else 1]; var right_party: bool = party[1 if side == 0 else 0]
			if not left_party: e0 = -out; mask |= 2
			if not right_party: e1 = W + out; mask |= 1
		else:
			e0 = 0.0; e1 = W
		m.box(Vector3(e0, y0, 0.0), Vector3(e1, y1, out), mask)
	m.xf = c.bxf


## The openings of one face: [{kind, x, y, w, h, R, arch, sill, key, custom, ...}].
static func _openings(c: ArchCtx, q: Dictionary, side: int, W: float, ys: PackedFloat32Array, fh: Array, stair: bool, arcade: bool) -> Array:
	var rng := c.rng
	var out: Array = []
	var floors := fh.size()
	var style: String = q.style
	var edge: float = q.edge
	var bay: float = q.bay
	if side >= 2:
		bay *= 1.25
	var span := W - 2.0 * edge
	var n := clampi(int(floor((span + 0.4) / bay)), 0, 12)
	if n == 0 and W > 2.2: n = 1; span = W - 1.2; edge = 0.6
	if n == 0: return out
	var step := span / n
	var xs := PackedFloat32Array()
	for i in range(n): xs.append(edge + step * (i + 0.5))
	var R: float = q.R
	var paint: Color = q.paint
	var ww: float = _qz(minf(q.win_w, step - 0.45), 0.1)
	var custom_paint := Color(paint.r, paint.g, paint.b, 1.0)
	var door_col: Color = q.door_paint
	var barn: bool = q.get("barn", false)
	var warehouse: bool = q.get("warehouse", false)
	var boathouse: bool = q.get("boathouse", false)
	if ww < 0.4: return out
	# -------- the ground floor
	var gh: float = fh[0]
	var y0 := ys[0]
	var door_i := -1
	if side == 0:
		door_i = (n - 1) / 2 if (n % 2 == 1 and (q.kind in ["palazzo", "town_hall", "church", "barn", "warehouse", "boathouse", "granary"] or rng.randf() < 0.3)) else (0 if rng.randf() < 0.5 else n - 1)
	elif side == 1 and rng.randf() < 0.4 and not barn:
		door_i = rng.randi_range(0, n - 1)
	var shop_run: Array = []
	if side == 0 and q.shop and not arcade:
		if n == 1: shop_run = [0]; door_i = -1
		else:
			var first := 1 if door_i == 0 else 0
			shop_run = [first]
			if n >= 3 and first + 1 < n and first + 1 != door_i and rng.randf() < 0.6: shop_run.append(first + 1)
	var stair_lo := 1e9; var stair_hi := -1e9
	if stair and side == 0:
		var run := ceilf(fh[0] / 0.2) * 0.3
		stair_lo = 0.0; stair_hi = run + 1.4
		if q.get("stair_dir", 1) < 0:
			stair_lo = W - run - 1.4; stair_hi = W
	if boathouse and side == 0:
		var dw: float = q.door_w
		out.append(_door_op(q, W * 0.5, y0, _qz(dw, 0.1), _qz(minf(q.door_h, gh - 0.2), 0.1), R, 1, custom_paint, false))
		return out
	for i in range(n):
		var x := xs[i]
		if arcade and side == 0: break
		if x > stair_lo - 0.6 and x < stair_hi + 0.6:
			continue
		if i in shop_run:
			if i != shop_run[0]: continue
			var x_a := xs[shop_run[0]]; var x_b := xs[shop_run[shop_run.size() - 1]]
			var sw := maxf(1.5, _qz(minf((x_b - x_a) + step - 0.5, 6.0), 0.75))
			var sh := _qz(minf(gh - 0.45, 3.4), 0.1)
			var o := {"kind": "shop", "x": (x_a + x_b) * 0.5, "y": y0, "w": sw, "h": sh, "R": minf(R, 0.3), "arch": 0, "sill": false,
				"key": "", "custom": custom_paint}
			if style == "sarmada":
				# souk stalls: a horseshoe arch with plank doors
				var aw := minf(_qz(sw, 0.5), 2.5)
				o = _door_op(q, o.x, y0, aw, minf(3.2, gh - 0.3), R, 2, custom_paint, false)
			else:
				o.key = M.shopfront(sw, sh, minf(R, 0.3))
			if q.awning != null:
				var ac: Color = q.awning
				o.awning = M.awning(sw + 0.3, 1.4, 0.7); o.awning_col = Color(ac.r, ac.g, ac.b, 1)
			out.append(o)
			continue
		if i == door_i:
			var dw: float = _qz(minf(q.door_w, step - 0.3), 0.1)
			if barn or warehouse: dw = _qz(minf(q.door_w, step + (step if n == 1 else 0.0) - 0.4), 0.1)
			var dh: float = _qz(minf(q.door_h, gh - 0.3), 0.1)
			var o := _door_op(q, x, y0, dw, dh, R, int(q.door_arch), Color(door_col.r, door_col.g, door_col.b, 1), side == 0)
			if side == 0 and q.lanterns > 0.0 and rng.randf() < q.lanterns: o.lantern = true
			if side == 0 and q.pots > 0.0 and rng.randf() < q.pots: o.pots = true
			out.append(o)
			continue
		if warehouse and side == 0:
			out.append(_door_op(q, x, y0, _qz(minf(q.door_w, step - 0.6), 0.1), _qz(minf(q.door_h, gh - 0.3), 0.1), R, 1, Color(door_col.r, door_col.g, door_col.b, 1), false))
			continue
		if rng.randf() < float(q.blank_ratio) + (0.35 if side >= 2 else 0.0) + (0.3 if side == 1 else 0.0): continue
		var sill: float = maxf(float(q.sill), 1.0 if style == "sarmada" else 0.8)
		var wh := _qz(minf(q.win_h, gh - sill - 0.35), 0.1)
		if wh < 0.35: continue
		out.append(_win_op(q, x, y0 + sill, ww, wh, R, custom_paint, style == "sarmada" or (style == "puerto" and rng.randf() < 0.5) or q.grille_ground))
	# -------- upper floors
	for k in range(1, floors):
		var y := ys[k]
		var h: float = fh[k]
		var top_floor := k == floors - 1
		var loggia_i := -1
		if side == 0 and top_floor and q.loggia and n >= 1:
			loggia_i = (n - 1) / 2
		for i in range(n):
			var x := xs[i]
			if i == loggia_i:
				var lw := minf(step * (2.0 if n >= 3 else 1.0) - 0.6, 3.2)
				var lh := h - 0.35
				out.append({"kind": "loggia", "x": x if n < 3 else xs[1], "y": y, "w": lw, "h": lh, "R": 1.3, "arch": 1, "sill": true, "key": "", "custom": custom_paint, "loggia": true})
				continue
			if loggia_i >= 0 and n >= 3 and absi(i - loggia_i) == 1 and i != loggia_i: continue
			if stair and side == 0 and k == 1 and x > stair_lo - 0.6 and x < stair_hi + 0.6:
				# the upper door at the stair's landing
				var lx := stair_hi - 0.7 if q.get("stair_dir", 1) > 0 else stair_lo + 0.7
				if absf(x - lx) < step * 0.5 or (i == 0 and q.get("stair_dir", 1) > 0) or (i == n - 1 and q.get("stair_dir", 1) < 0):
					out.append(_door_op(q, clampf(lx, 0.8, W - 0.8), y, minf(q.door_w, 1.0), _qz(minf(q.door_h, h - 0.35), 0.1), R, int(q.door_arch), Color(door_col.r, door_col.g, door_col.b, 1), false))
				continue
			if barn and side == 0 and i == (n - 1) / 2 and k == 1:
				out.append(_door_op(q, x, y + 0.2, _qz(minf(1.6, step - 0.4), 0.1), _qz(minf(1.8, h - 0.5), 0.1), R, 0, Color(door_col.r, door_col.g, door_col.b, 1), false))
				continue
			var blank: float = q.blank_ratio
			if side == 1: blank += 0.35
			if side >= 2: blank += 0.4
			if rng.randf() < blank: continue
			var fr: bool = side == 0 and int(q.french) > 0 and (int(q.french) == 2 or k == 1) and q.balcony >= 0
			if fr:
				var fw := _qz(minf(ww + 0.1, step - 0.45), 0.1)
				var fhh := _qz(minf(h - 0.5, 2.4), 0.2)
				var bal: int = q.balcony
				var bw := _qz(minf(fw + 0.7, step - 0.1), 0.2)
				if bal == 2: bw = _qz(step, 0.1) + 0.02      # alpine: bay to bay, one continuous balcony
				out.append({"kind": "french", "x": x, "y": y + 0.02, "w": fw, "h": fhh, "R": R, "arch": 0, "sill": true,
					"key": M.french(fw, fhh, R, q.surround, q.sur_col, bal, bw, q.shutters if style != "puerto" else 0, q.get("iron", Color(0.08, 0.08, 0.09))),
					"custom": Color(paint.r, paint.g, paint.b, _frame_i(q))})
				continue
			var sill: float = q.sill
			var wh := _qz(minf(q.win_h, h - sill - 0.3), 0.1)
			if top_floor and style == "puerto" and floors >= 4: wh = minf(wh, 1.2)
			if wh < 0.3: continue
			out.append(_win_op(q, x, y + sill, ww, wh, R, custom_paint, false))
	return out


static func _frame_i(q: Dictionary) -> int:
	if not q.has("_fi"): q["_fi"] = L.frame_index(q.frame)
	return q._fi


static func _qz(v: float, s: float) -> float:
	return floorf(v / s + 0.001) * s


static func _win_op(q: Dictionary, x: float, y: float, w: float, h: float, R: float, paint: Color, grille: bool) -> Dictionary:
	var arch := 3 if q.get("warehouse", false) else 0
	var kc: Dictionary = q.get("_kc", {})
	if kc.is_empty(): q["_kc"] = kc
	var ck := Vector4i(roundi(w * 100), roundi(h * 100), int(grille), 1)
	var key: String = kc.get(ck, "")
	if key == "":
		key = M.window(w, h, R, q.sill_col, q.surround, q.sur_col, q.shutters if not grille or q.style == "sarmada" else 0,
			q.lintel, grille, q.panes, arch)
		kc[ck] = key
	return {"kind": "win", "x": x, "y": y, "w": w, "h": h, "R": R, "arch": arch, "sill": true, "key": key, "custom": Color(paint.r, paint.g, paint.b, _frame_i(q))}


static func _door_op(q: Dictionary, x: float, y: float, w: float, h: float, R: float, arch: int, paint: Color, main: bool) -> Dictionary:
	var kc: Dictionary = q.get("_kc", {})
	if kc.is_empty(): q["_kc"] = kc
	var ck := Vector4i(roundi(w * 100), roundi(h * 100), arch * 2 + int(main), 2)
	var key: String = kc.get(ck, "")
	if key == "":
		key = M.door(w, h, R, q.door_leaf, q.fanlight and main and arch == 0, q.surround if main else 0.0, q.sur_col, arch, true)
		kc[ck] = key
	return {"kind": "door", "x": x, "y": y, "w": w, "h": h, "R": R, "arch": arch, "sill": false, "key": key, "custom": paint}


## The back of an arched loggia (island houses): a wall with a door, a parapet across the arch.
static func _loggia(c: ArchCtx, q: Dictionary, fx: Transform3D, o: Dictionary, zones: Array) -> void:
	var m := c.m
	var R: float = o.R
	var x: float = o.x; var y: float = o.y; var r: float = float(o.w) * 0.5; var h: float = o.h
	var back := fx * Transform3D(Basis(), Vector3(0, 0, -R))
	m.xf = c.bxf * back
	var zmat: Array = _zone_at(zones, y + 0.5)
	m.layer = zmat[0]; m.tint = zmat[1]
	var holes: Array = []
	var dw := 1.0; var dh := minf(float(q.door_h), h - r - 0.2)
	F.opening(m, holes, x, y, dw, dh, 0.25, 0, false, false)
	F.wall(m, y, y + h, x - r, x + r, holes)
	var paint: Color = q.door_paint
	c.place(M.door(dw, dh, 0.25, q.door_leaf, false, 0.0, Color.WHITE, 0, false), back * Transform3D(Basis(), Vector3(x, y, 0)), Color(paint.r, paint.g, paint.b, 1), Color(zmat[1].r, zmat[1].g, zmat[1].b, zmat[0]))
	m.xf = c.bxf * fx
	m.box(Vector3(x - r, y, -0.26), Vector3(x + r, y + 0.95, -0.02), 4 | 16 | 32)
	var trim: Array = q.get("trim", zmat)
	m.layer = trim[0]; m.tint = trim[1]
	m.box(Vector3(x - r, y + 0.95, -0.3), Vector3(x + r, y + 1.02, 0.02), 4 | 16 | 32)
	c.place(M.pot(), fx * Transform3D(Basis(), Vector3(x - r * 0.5, y + 1.02, -0.15)), M.PLANTS[c.rng.randi() % 4])


## Plaza porticoes: round arches on piers across the ground floor, a gallery behind them, shop
## fronts and doors on its back wall.
static func _arcade_front(c: ArchCtx, q: Dictionary, fx: Transform3D, W: float, ys: PackedFloat32Array, fh: Array, holes: Array, zones: Array) -> void:
	var m := c.m
	var gh: float = fh[0]
	var n := maxi(1, roundi(W / 3.3))
	var pier := 0.7
	var step := W / n
	var aw := step - pier
	var h := gh - 0.35
	var depth := 0.6
	var ceil_y := gh - 0.3
	var zmat: Array = _zone_at(zones, 0.5)
	m.layer = zmat[0]; m.tint = zmat[1]
	for i in range(n):
		var x := step * (i + 0.5)
		F.opening(m, holes, x, 0.0, aw, h, depth, 1, false)
	# the gallery: ceiling, back wall with shopfronts and doors, floor
	var G := 2.8
	m.xf = c.bxf * fx
	m.layer = ArchStyles.wx(L.TIMBER, 0.3); m.tint = Color(0.7, 0.58, 0.46)
	m.quad(Vector3(0, ceil_y, -G), Vector3(W, ceil_y, -G), Vector3(W, ceil_y, -depth), Vector3(0, ceil_y, -depth))
	m.layer = ArchStyles.wx(L.STONE, 0.4); m.tint = Color(0.8, 0.78, 0.72)
	m.quad(Vector3(0, 0.02, -depth), Vector3(W, 0.02, -depth), Vector3(W, 0.02, -G), Vector3(0, 0.02, -G))
	var back := fx * Transform3D(Basis(), Vector3(0, 0, -G))
	m.xf = c.bxf * back
	m.layer = zmat[0]; m.tint = zmat[1]
	var bh: Array = []
	var paint: Color = q.paint
	for i in range(n):
		var x := step * (i + 0.5)
		var sw := minf(aw - 0.3, 3.2)
		var sh := minf(ceil_y - 0.4, 3.0)
		F.opening(m, bh, x, 0.0, sw, sh, 0.25, 0, false, false)
		c.place(M.shopfront(sw, sh, 0.25), back * Transform3D(Basis(), Vector3(x, 0.0, 0)), Color(paint.r, paint.g, paint.b, 1), Color(zmat[1].r, zmat[1].g, zmat[1].b, zmat[0]))
	F.wall(m, 0.0, ceil_y, 0.0, W, bh)
	# end walls of the gallery (inner faces), unless the arcade runs on into the neighbour
	var party: Array = q.party
	m.xf = c.bxf * fx
	if not party[0]: m.quad(Vector3(0.001, 0, -depth), Vector3(0.001, 0, -G), Vector3(0.001, ceil_y, -G), Vector3(0.001, ceil_y, -depth))
	if not party[1]: m.quad(Vector3(W - 0.001, 0, -G), Vector3(W - 0.001, 0, -depth), Vector3(W - 0.001, ceil_y, -depth), Vector3(W - 0.001, ceil_y, -G))
	# lanterns hanging in the arches
	for i in range(n):
		if i % 2 == 0: c.place(M.lantern(), back * Transform3D(Basis(), Vector3(step * (i + 0.5) + 1.0, 2.6, 0)))


# ---------------------------------------------------------------- roofs
static func _roof(c: ArchCtx, q: Dictionary, w: float, d: float, H: float, top: float, party: Array, zf: float, flat: bool, ph: float) -> float:
	var m := c.m
	var roof_mat := [ArchStyles.wx(int(q.roof_layer), q.weather), q.roof_tint]
	var soffit := [ArchStyles.wx(int(q.soffit_layer), q.weather), q.soffit_tint]
	var k := tan(float(q.pitch))
	var t: float = q.thick
	var dd := zf + d * 0.5            # the walls' real depth (a stair recess shortens it)
	var zc := (zf - d * 0.5) * 0.5    # the walls' centre in z
	var gable_mat: Array = q.wall
	if q.upper != null and int(q.upper[2]) < (q.fh as Array).size(): gable_mat = [q.upper[0], q.upper[1]]
	var ov: float = q.ov_eave
	var vg: float = q.ov_verge
	match q.roof:
		"flat":
			var floor_mat := [ArchStyles.wx(int(q.roof_layer), q.weather), q.roof_tint]
			var wall_mat: Array = gable_mat
			var coping: Array = q.get("trim", wall_mat) if q.style == "isola" else wall_mat
			m.xf = c.bxf * Transform3D(Basis(), Vector3(0, 0, zc))
			F.flat(m, w, dd, H, ph, 0.25, floor_mat, wall_mat, coping, [true, true, not party[1], not party[0]])
			m.xf = c.bxf
			return top
		"barrel":
			var span := minf(w, dd)
			if w <= dd:
				m.xf = c.bxf * Transform3D(Basis(), Vector3(0, 0, zc))
				var r := F.barrel(m, w, dd, H, span * 0.28, roof_mat, gable_mat)
				m.xf = c.bxf
				return r
			m.xf = c.bxf * Transform3D(Basis(UP, PI * 0.5), Vector3(0, 0, zc))
			var r2 := F.barrel(m, dd, w, H, span * 0.28, roof_mat, gable_mat)
			m.xf = c.bxf
			return r2
		"hip":
			if w >= dd:
				m.xf = c.bxf * Transform3D(Basis(), Vector3(0, 0, zc))
				var r := F.hip(m, w, dd, H, k, ov, t, roof_mat, soffit)
				m.xf = c.bxf
				return r
			m.xf = c.bxf * Transform3D(Basis(UP, PI * 0.5), Vector3(0, 0, zc))
			var r3 := F.hip(m, dd, w, H, k, ov, t, roof_mat, soffit)
			m.xf = c.bxf
			return r3
		"gable_z":
			# ridge along the depth: the gable ends face the street and the back
			m.xf = c.bxf * Transform3D(Basis(UP, PI * 0.5), Vector3(0, 0, zc))
			var r4 := F.gable(m, dd, w, H, k, vg, vg, vg, t, roof_mat, soffit, gable_mat, true, 0.0 if party[1] else ov, 0.0 if party[0] else ov)
			m.xf = c.bxf
			return r4
		_:
			m.xf = c.bxf * Transform3D(Basis(), Vector3(0, 0, zc))
			var r5 := F.gable(m, w, dd, H, k, ov, 0.0 if party[0] else vg, 0.0 if party[1] else vg, t, roof_mat, soffit, gable_mat)
			m.xf = c.bxf
			return r5


static func _roofscape(c: ArchCtx, q: Dictionary, w: float, d: float, H: float, top: float, roof_top: float, party: Array, flat: bool, ph: float, zf: float) -> void:
	var rng := c.rng
	var wall_mat: Array = q.wall
	var wall_custom := Color(wall_mat[1].r, wall_mat[1].g, wall_mat[1].b, wall_mat[0])
	var zc := (zf - d * 0.5) * 0.5
	var dd := zf + d * 0.5
	var k := tan(float(q.pitch))
	var n_ch: int = q.chimneys
	var roof: String = q.roof
	for i in range(n_ch):
		var x := 0.0; var z := zc; var y := H
		match roof:
			"gable_x":
				x = (w * 0.5 - 0.7) * (-1.0 if i == 0 else 1.0) * (1.0 if rng.randf() < 0.8 else 0.4)
				z = zc - 0.5 - rng.randf() * 0.6
				y = F.gable_y(dd, H, k, q.thick, z - zc + 0.45) - 0.35
			"gable_z":
				z = zc + (dd * 0.5 - 1.2) * (1.0 if i == 0 else -1.0)
				x = 0.5 + rng.randf() * 0.4
				y = F.gable_y(w, H, k, q.thick, x + 0.5) - 0.4
			"hip":
				var xr := maxf(0.0, (maxf(w, dd) - minf(w, dd)) * 0.5)
				if w >= dd: x = xr * (-1.0 if i == 0 else 1.0) * 0.8
				else: z = zc + xr * (-1.0 if i == 0 else 1.0) * 0.8
				y = H + minf(w, dd) * 0.5 * k - 0.5
			"flat":
				x = (w * 0.5 - 0.6) * (-1.0 if i == 0 else 1.0); z = zc - dd * 0.25
				y = H
			_:
				continue
		# one stack height per kind (fewer module variants): the base sinks as far as needed
		var hgt: float = [2.2, 2.4, 2.2, 1.9][int(q.chimney_kind) % 4]
		if roof != "flat": y = minf(y, roof_top + 0.8 - hgt)
		else: hgt = ph + 1.1
		c.place(M.chimney(q.chimney_kind, hgt), Transform3D(Basis(), Vector3(x, y, z)), Color.WHITE, wall_custom)
	# dormers on the front slope of a street-parallel gable
	if roof == "gable_x" and int(q.dormers) > 0:
		var nd: int = q.dormers
		for i in range(nd):
			var x := (w / (nd + 1)) * (i + 1) - w * 0.5
			var zfront := zf - 0.25
			var y := F.gable_y(dd, H, k, q.thick, zfront - zc) - 0.12
			c.place(M.dormer(1.3, 1.5, 2.2, Color(0.95, 0.95, 0.93)), Transform3D(Basis(), Vector3(x, y, zfront)), Color.WHITE, wall_custom)
	if flat:
		# palm-wood beams, merlons, a stair head and a dome on desert roofs
		if q.merlons >= 0:
			var faces := [[Vector3(-w * 0.5, 0, zf - 0.125), Vector3(1, 0, 0), w], [Vector3(w * 0.5, 0, -d * 0.5 + 0.125), Vector3(-1, 0, 0), w]]
			for f in faces:
				var nm := int(f[2] / 1.4)
				for j in range(nm):
					var p: Vector3 = f[0] + f[1] * (f[2] * (j + 0.5) / nm)
					c.place(M.merlon(int(q.merlons), 0.55, 0.7, 0.26), Transform3D(Basis(UP, atan2(f[1].x, f[1].z) - PI * 0.5), p + Vector3(0, top, 0)), Color.WHITE, wall_custom)
		if q.stairhead and w >= 5.0 and dd >= 5.0:
			_stairhead(c, q, w, d, H, zc, dd)
		if q.dome and w >= 5.5:
			c.place(M.small_dome(1.3), Transform3D(Basis(), Vector3(w * 0.5 - 2.0, H, zc + dd * 0.5 - 2.2)), Color.WHITE, wall_custom)
	if q.beams:
		var fx := Transform3D(Basis(Vector3(1, 0, 0), UP, Vector3(0, 0, 1)), Vector3(-w * 0.5, 0, zf))
		var fh: Array = q.fh
		var yy := 0.0
		for kk in range(fh.size()):
			yy += fh[kk]
			if kk == fh.size() - 1: yy = H
			var nb := int((w - 1.0) / 0.6)
			for j in range(nb):
				c.place(M.beam(), fx * Transform3D(Basis(), Vector3(0.5 + 0.6 * (j + 0.5), yy - 0.2, 0)))
			break


## A little roof-top room over the stair (desert terraces): its own walls, a door, a parapet.
static func _stairhead(c: ArchCtx, q: Dictionary, w: float, d: float, H: float, zc: float, dd: float) -> void:
	var m := c.m
	var sw := 2.2; var sd := 2.4; var sh := 2.3
	var cx := -w * 0.5 + 0.25 + sw * 0.5
	var cz := zc - dd * 0.5 + 0.25 + sd * 0.5
	var wall_mat: Array = q.wall
	m.layer = wall_mat[0]; m.tint = wall_mat[1]
	var keep_g := m.ground; var keep_e := m.eave
	m.ground = H - 0.3; m.eave = H + sh
	var o := Vector3(cx, H, cz)
	# front face with a door
	var fx := Transform3D(Basis(Vector3(1, 0, 0), UP, Vector3(0, 0, 1)), o + Vector3(-sw * 0.5, 0, sd * 0.5))
	m.xf = c.bxf * fx
	var holes: Array = []
	F.opening(m, holes, sw * 0.5, 0.0, 0.9, 1.95, 0.3, 0, false, false)
	F.wall(m, 0.0, sh, 0.0, sw, holes)
	c.place(M.door(0.9, 1.95, 0.3, 1, false, 0.0, Color.WHITE, 0, false), fx * Transform3D(Basis(), Vector3(sw * 0.5, 0, 0)), Color(q.paint.r, q.paint.g, q.paint.b, 1), Color(wall_mat[1].r, wall_mat[1].g, wall_mat[1].b, wall_mat[0]))
	m.xf = c.bxf
	m.box(o + Vector3(-sw * 0.5, 0, -sd * 0.5), o + Vector3(sw * 0.5, sh, sd * 0.5), 1 | 2 | 32)
	m.layer = ArchStyles.wx(L.TERRACE, q.weather); m.tint = q.roof_tint
	m.box(o + Vector3(-sw * 0.5 - 0.05, sh, -sd * 0.5 - 0.05), o + Vector3(sw * 0.5 + 0.05, sh + 0.12, sd * 0.5 + 0.05), 63 - 8)
	m.ground = keep_g; m.eave = keep_e
	c.box_shape(o + Vector3(-sw * 0.5, 0, -sd * 0.5), o + Vector3(sw * 0.5, sh + 0.12, sd * 0.5))


## An external stair up the front to the first floor (island houses): solid masonry steps, a
## landing and a plastered balustrade, all inside the plot (the facade steps back for it).
static func _ext_stair(c: ArchCtx, q: Dictionary, w: float, d: float, zf: float, ys: PackedFloat32Array, fh: Array) -> void:
	var m := c.m
	var dir: int = q.get("stair_dir", 1)
	var rise_total: float = fh[0]
	var n := int(ceilf(rise_total / 0.2))
	var rise := rise_total / n
	var run := 0.3
	var sw := 1.2
	var z0 := zf; var z1 := zf + sw
	var wall_mat: Array = q.wall
	m.xf = c.bxf
	var x_start := -w * 0.5 if dir > 0 else w * 0.5
	for i in range(n):
		var xa := x_start + dir * run * i; var xb := xa + dir * run
		var lo := Vector3(minf(xa, xb), 0.0, z0); var hi := Vector3(maxf(xa, xb), rise * (i + 1), z1 - 0.2)
		m.layer = ArchStyles.wx(L.STONE, q.weather); m.tint = Color(0.86, 0.84, 0.8)
		m.box(Vector3(lo.x, hi.y - 0.04, lo.z), Vector3(hi.x, hi.y, hi.z), 4 | 16 | (2 if dir > 0 else 1))
		m.layer = wall_mat[0]; m.tint = wall_mat[1]
		m.box(lo, Vector3(hi.x, hi.y - 0.04, hi.z), (2 if dir > 0 else 1) | 16)
	# landing
	var lx0 := x_start + dir * run * n
	var lx1 := lx0 + dir * 1.4
	var llo := Vector3(minf(lx0, lx1), 0.0, z0); var lhi := Vector3(maxf(lx0, lx1), rise_total, z1)
	m.layer = wall_mat[0]; m.tint = wall_mat[1]
	m.box(llo, lhi, 16 | (1 if dir > 0 else 2))
	m.layer = ArchStyles.wx(L.STONE, q.weather); m.tint = Color(0.86, 0.84, 0.8)
	m.box(Vector3(llo.x, rise_total - 0.04, llo.z), Vector3(lhi.x, rise_total, lhi.z - 0.2), 4)
	# balustrade: a sloped plastered wall on the outer edge, and round the landing
	m.layer = wall_mat[0]; m.tint = wall_mat[1]
	var bx0 := x_start; var bx1 := lx0
	var bz0 := z1 - 0.2; var bz1 := z1
	var hb := 0.95
	var pa := Vector3(bx0, 0.0, bz1); var pb := Vector3(bx1, rise_total, bz1)
	F.quad_out(m, pa, pb, pb + Vector3(0, hb, 0), pa + Vector3(0, hb, 0), Vector3(0, 0, 1))
	F.quad_out(m, pa + Vector3(0, 0, -0.2), pb + Vector3(0, 0, -0.2), pb + Vector3(0, hb, -0.2), pa + Vector3(0, hb, -0.2), Vector3(0, 0, -1))
	F.quad_out(m, pa + Vector3(0, hb, 0), pb + Vector3(0, hb, 0), pb + Vector3(0, hb, -0.2), pa + Vector3(0, hb, -0.2), Vector3(0, 1, 0))
	m.box(Vector3(llo.x, rise_total, bz0), Vector3(lhi.x, rise_total + hb, bz1), 63 - 8)
	c.place(M.pot(), Transform3D(Basis(), Vector3((lx0 + lx1) * 0.5 + dir * 0.3, rise_total, z1 - 0.45)), M.PLANTS[c.rng.randi() % 4])
	# collision: a ramp and the landing
	var rl := sqrt(pow(run * n, 2) + rise_total * rise_total)
	var ang := atan2(rise_total, run * n) * dir
	c.box_shape_c(Vector3(x_start + dir * run * n * 0.5, rise_total * 0.5 - 0.15, (z0 + z1) * 0.5), Vector3(rl, 0.3, sw), Basis(Vector3.BACK, ang))
	c.box_shape(llo, lhi)


# ---------------------------------------------------------------- collision
static func _collide(c: ArchCtx, q: Dictionary, w: float, d: float, yb: float, H: float, top: float, flat: bool, ph: float, zf: float, arcade: bool, gallery: float, fh: Array, stair: bool, lift: float) -> void:
	if not c.collide: return
	var z0 := -d * 0.5
	if arcade:
		c.box_shape(Vector3(-w * 0.5, yb, z0), Vector3(w * 0.5, H, zf - gallery))
		c.box_shape(Vector3(-w * 0.5, fh[0] - 0.35, zf - gallery), Vector3(w * 0.5, H, zf))
		var n := maxi(1, roundi(w / 3.3))
		for i in range(n + 1):
			var x := -w * 0.5 + w * i / n
			c.box_shape(Vector3(x - 0.35, yb, zf - 0.6), Vector3(x + 0.35, fh[0], zf))
	else:
		c.box_shape(Vector3(-w * 0.5, yb, z0), Vector3(w * 0.5, H, zf))
	var zc := (zf + z0) * 0.5
	var dd := zf - z0
	if flat and ph > 0.05:
		var t := 0.25
		c.box_shape(Vector3(-w * 0.5, H, zf - t), Vector3(w * 0.5, top, zf))
		c.box_shape(Vector3(-w * 0.5, H, z0), Vector3(w * 0.5, top, z0 + t))
		c.box_shape(Vector3(-w * 0.5, H, z0), Vector3(-w * 0.5 + t, top, zf))
		c.box_shape(Vector3(w * 0.5 - t, H, z0), Vector3(w * 0.5, top, zf))
	elif not flat:
		var k := tan(float(q.pitch))
		match q.roof:
			"gable_x":
				var r := H + dd * 0.5 * k
				c.convex_shape(PackedVector3Array([Vector3(-w * 0.5, H, z0), Vector3(w * 0.5, H, z0), Vector3(-w * 0.5, H, zf), Vector3(w * 0.5, H, zf),
					Vector3(-w * 0.5, r, zc), Vector3(w * 0.5, r, zc)]))
			"gable_z":
				var r := H + w * 0.5 * k
				c.convex_shape(PackedVector3Array([Vector3(-w * 0.5, H, z0), Vector3(w * 0.5, H, z0), Vector3(-w * 0.5, H, zf), Vector3(w * 0.5, H, zf),
					Vector3(0, r, z0), Vector3(0, r, zf)]))
			"hip":
				var r := H + minf(w, dd) * 0.5 * k
				var xr := maxf(0.0, (w - dd) * 0.5); var zr := maxf(0.0, (dd - w) * 0.5)
				c.convex_shape(PackedVector3Array([Vector3(-w * 0.5, H, z0), Vector3(w * 0.5, H, z0), Vector3(-w * 0.5, H, zf), Vector3(w * 0.5, H, zf),
					Vector3(-xr, r, zc - zr), Vector3(xr, r, zc + zr)]))
			"barrel":
				var span := minf(w, dd)
				var pts := PackedVector3Array()
				for i in range(7):
					var a := PI * i / 6.0
					if w <= dd:
						pts.append(Vector3(cos(a) * w * 0.5, H + sin(a) * span * 0.28, z0)); pts.append(Vector3(cos(a) * w * 0.5, H + sin(a) * span * 0.28, zf))
					else:
						pts.append(Vector3(-w * 0.5, H + sin(a) * span * 0.28, zc + cos(a) * dd * 0.5)); pts.append(Vector3(w * 0.5, H + sin(a) * span * 0.28, zc + cos(a) * dd * 0.5))
				c.convex_shape(pts)


# ---------------------------------------------------------------- far silhouettes
static func build_lod(plots: Array) -> Mesh:
	var m := ArchMesh.new()
	m.lod = true
	for p: Dictionary in plots:
		m.xf = Transform3D(Basis(UP, yaw_of(p)), Vector3(float(p.x), float(p.y), float(p.z)))
		lod_plot(m, p)
	if m.size() == 0: return ArrayMesh.new()
	var mesh := m.commit()
	mesh.surface_set_material(0, ArchMaterials.lod())
	return mesh


const LOD_ROOF := {7: Color(0.66, 0.36, 0.24), 8: Color(0.36, 0.36, 0.37), 16: Color(0.86, 0.84, 0.8), 1: Color(0.94, 0.93, 0.9)}
const LOD_WALL := {2: Color(0.6, 0.59, 0.57), 3: Color(0.8, 0.77, 0.7), 4: Color(0.62, 0.34, 0.24), 5: Color(0.8, 0.72, 0.6), 6: Color(0.8, 0.84, 0.9), 9: Color(0.5, 0.4, 0.3)}


static func lod_plot(m: ArchMesh, p: Dictionary) -> void:
	var kind: String = p.get("kind", "house")
	if kind in ["tower", "church", "windmill", "lighthouse", "citadel", "gate", "wall"]:
		ArchSpecial.lod(m, p)
		return
	var q := ArchStyles.plan(p)
	var w: float = q.w - 0.6; var d: float = q.d - 0.6
	var H: float = q.H - 0.3
	var yb := minf(float(p.get("ground_min", p.y)) - float(p.y) - 0.5, -0.3)
	var wall_mat: Array = q.wall
	var col := lod_colour(wall_mat)
	if q.upper != null: col = col.lerp(lod_colour([q.upper[0], q.upper[1]]), 0.5)
	m.tint = col
	var flat: bool = q.roof == "flat"
	var top := H + (float(q.parapet) if flat else 0.0)
	m.box(Vector3(-w * 0.5, yb, -d * 0.5), Vector3(w * 0.5, top, d * 0.5), 63 - 8)
	var rl := int(q.roof_layer)
	var rc: Color = LOD_ROOF.get(rl, col)
	if rl == L.ROOF_TILE or rl == L.SLATE: rc = rc * (q.roof_tint as Color)
	m.tint = rc
	var k := tan(float(q.pitch))
	match q.roof:
		"flat":
			pass
		"barrel":
			var span := minf(w, d)
			m.tint = Color(0.94, 0.93, 0.9)
			if w <= d:
				for s: float in [-1.0, 1.0]:
					F.quad_out(m, Vector3(-w * 0.5 * s, H, d * 0.5), Vector3(0, H + span * 0.28, d * 0.5), Vector3(0, H + span * 0.28, -d * 0.5), Vector3(-w * 0.5 * s, H, -d * 0.5), Vector3(-s, 1, 0))
			else:
				for s: float in [-1.0, 1.0]:
					F.quad_out(m, Vector3(-w * 0.5, H, d * 0.5 * s), Vector3(-w * 0.5, H + span * 0.28, 0), Vector3(w * 0.5, H + span * 0.28, 0), Vector3(w * 0.5, H, d * 0.5 * s), Vector3(0, 1, s))
		"gable_z":
			var r := H + (w * 0.5 + 0.4) * k
			for s: float in [-1.0, 1.0]:
				F.quad_out(m, Vector3(0.7 * s * 0.0 + (w * 0.5 + 0.5) * s, H - 0.5 * k, d * 0.5 + 0.6), Vector3(0, r, d * 0.5 + 0.6), Vector3(0, r, -d * 0.5 - 0.6), Vector3((w * 0.5 + 0.5) * s, H - 0.5 * k, -d * 0.5 - 0.6), Vector3(s, 1, 0))
			m.tint = col
			for s: float in [-1.0, 1.0]:
				F.tri_out(m, Vector3(-w * 0.5, H, d * 0.5 * s), Vector3(w * 0.5, H, d * 0.5 * s), Vector3(0, r, d * 0.5 * s), Vector3(0, 0, s))
		"hip":
			if w >= d: F.hip(m, w, d, H, k, 0.5, 0.0, [0.0, rc], [0.0, rc])
			else:
				var keep := m.xf
				m.xf = m.xf * Transform3D(Basis(UP, PI * 0.5), Vector3.ZERO)
				F.hip(m, d, w, H, k, 0.5, 0.0, [0.0, rc], [0.0, rc])
				m.xf = keep
		_:
			var r := H + (d * 0.5 + 0.4) * k
			for s: float in [-1.0, 1.0]:
				F.quad_out(m, Vector3(-w * 0.5 - 0.3, H - 0.5 * k, (d * 0.5 + 0.5) * s), Vector3(w * 0.5 + 0.3, H - 0.5 * k, (d * 0.5 + 0.5) * s), Vector3(w * 0.5 + 0.3, r, 0), Vector3(-w * 0.5 - 0.3, r, 0), Vector3(0, 1, s))
			m.tint = col
			for s: float in [-1.0, 1.0]:
				F.tri_out(m, Vector3(w * 0.5 * s, H, d * 0.5), Vector3(w * 0.5 * s, H, -d * 0.5), Vector3(w * 0.5 * s, r, 0), Vector3(s, 0, 0))


static func lod_colour(mat: Array) -> Color:
	var layer := int(mat[0])
	var tint: Color = mat[1]
	if layer == L.AZULEJO: return Color(0.9, 0.9, 0.9).lerp(tint, 0.35)
	if LOD_WALL.has(layer): return LOD_WALL[layer] * tint
	return Color(0.9, 0.89, 0.86) * tint
