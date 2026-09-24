class_name ArchSpecial
extends RefCounted
## The architecture kit's one-off buildings: towers (clock tower, campanile, minaret), churches,
## windmills, lighthouses, town walls, gates and the desert citadel, per style, and their far
## silhouettes (`lod`). Same conventions as BuildingKit.house (local frame, +z = the street side).

const L = preload("res://world/kit/building/arch_materials.gd")
const F = preload("res://world/kit/building/arch_facade.gd")
const M = preload("res://world/kit/building/arch_modules.gd")
const S = preload("res://world/kit/building/arch_styles.gd")
const UP := Vector3.UP


static func _rng(p: Dictionary) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = int(p.get("seed", 1)) ^ 0x5bd1e995
	return r


static func _yb(p: Dictionary) -> float:
	return minf(float(p.get("ground_min", p.get("y", 0.0))) - float(p.get("y", 0.0)) - 0.5, -0.35)


## Materials of the masonry of a special building per style: [wall, trim, roof, roof tint]
static func _mats(style: String, rng: RandomNumberGenerator) -> Array:
	var w := rng.randf_range(0.1, 0.5)
	match style:
		"puerto": return [[S.wx(L.ASHLAR, w), Color(1.0, 0.98, 0.94)], [S.wx(L.STONE, w), S.GRANITE], L.ROOF_TILE, Color(1, 1, 1)]
		"valdoro": return [[S.wx(L.RUBBLE, w), Color(0.98, 0.97, 0.95)], [S.wx(L.STONE, w), Color(0.7, 0.7, 0.7)], L.SLATE, Color(1, 1, 1)]
		"sarmada": return [[S.wx(L.ADOBE, w), Color(0.93, 0.68, 0.45)], [S.wx(L.ADOBE, w), Color(0.98, 0.84, 0.66)], L.TERRACE, Color(0.9, 0.7, 0.5)]
		"isola": return [[S.wx(L.PLASTER, w), Color(0.98, 0.9, 0.62)], [S.wx(L.PLASTER, w * 0.5), S.WHITE], L.ROOF_TILE, Color(1, 1, 1)]
		"core": return [[S.wx(L.WHITEWASH, w), Color(0.97, 0.96, 0.92)], [S.wx(L.STONE, w), Color(0.9, 0.88, 0.82)], L.ROOF_TILE, Color(1, 1, 1)]
	return [[S.wx(L.BRICK, w), Color(1, 0.96, 0.92)], [S.wx(L.STONE, w), S.CAMPO_HONEY], L.ROOF_TILE, Color(1, 1, 1)]


## Walls of a w x d prism from y0 to y1 on all four faces (with per-face openings: side ->
## Array of [x, y, w, h, R, arch, sill, key, custom]); the faces are built in face space.
static func prism(c: ArchCtx, x0: float, x1: float, z0: float, z1: float, y0: float, y1: float, mat: Array, ops := {}) -> void:
	var m := c.m
	var w := x1 - x0; var d := z1 - z0
	var faces := [
		[Transform3D(Basis(Vector3(1, 0, 0), UP, Vector3(0, 0, 1)), Vector3(x0, 0, z1)), w],
		[Transform3D(Basis(Vector3(-1, 0, 0), UP, Vector3(0, 0, -1)), Vector3(x1, 0, z0)), w],
		[Transform3D(Basis(Vector3(0, 0, -1), UP, Vector3(1, 0, 0)), Vector3(x1, 0, z1)), d],
		[Transform3D(Basis(Vector3(0, 0, 1), UP, Vector3(-1, 0, 0)), Vector3(x0, 0, z0)), d]]
	for side in range(4):
		var fx: Transform3D = faces[side][0]
		F.use(m, c.bxf, fx)
		m.layer = mat[0]; m.tint = mat[1]
		var holes: Array = []
		for o in ops.get(side, []):
			F.opening(m, holes, o[0], o[1], o[2], o[3], o[4], o[5], o[6], o[7] == "")
			if o[7] != "": c.place(o[7], fx * Transform3D(Basis(), Vector3(o[0], o[1], 0)), o[8], Color(mat[1].r, mat[1].g, mat[1].b, mat[0]))
			if o.size() > 9 and o[9] == "bell":
				c.place(M.bell(0.35), fx * Transform3D(Basis(), Vector3(o[0], o[1] + o[3] - 0.25, -o[4] * 0.5)))
				# a dark back to the belfry arch
				m.layer = S.wx(L.TIMBER, 0.6); m.tint = Color(0.25, 0.2, 0.17)
				m.quad(Vector3(o[0] - o[2] * 0.7, o[1], -o[4]), Vector3(o[0] + o[2] * 0.7, o[1], -o[4]), Vector3(o[0] + o[2] * 0.7, o[1] + o[3], -o[4]), Vector3(o[0] - o[2] * 0.7, o[1] + o[3], -o[4]))
				m.layer = mat[0]; m.tint = mat[1]
		F.wall(m, y0, y1, 0.0, faces[side][1], holes)
	m.xf = c.bxf


static func _faces_xf(w: float, d: float, side: int) -> Transform3D:
	return F.face(side, w, d)[0]


## A band (string course / cornice) round a w x d prism.
static func band(c: ArchCtx, w: float, d: float, y0: float, y1: float, out: float, mat: Array) -> void:
	var m := c.m
	m.xf = c.bxf
	m.layer = mat[0]; m.tint = mat[1]
	m.box(Vector3(-w * 0.5 - out, y0, -d * 0.5 - out), Vector3(w * 0.5 + out, y1, d * 0.5 + out), 63 - 8 - 4)
	m.quad(Vector3(-w * 0.5 - out, y1, d * 0.5 + out), Vector3(w * 0.5 + out, y1, d * 0.5 + out), Vector3(w * 0.5 + out, y1, d * 0.5), Vector3(-w * 0.5 - out, y1, d * 0.5))
	m.quad(Vector3(w * 0.5 + out, y1, -d * 0.5 - out), Vector3(-w * 0.5 - out, y1, -d * 0.5 - out), Vector3(-w * 0.5 - out, y1, -d * 0.5), Vector3(w * 0.5 + out, y1, -d * 0.5))
	m.quad(Vector3(w * 0.5, y1, d * 0.5), Vector3(w * 0.5 + out, y1, d * 0.5), Vector3(w * 0.5 + out, y1, -d * 0.5), Vector3(w * 0.5, y1, -d * 0.5))
	m.quad(Vector3(-w * 0.5 - out, y1, d * 0.5), Vector3(-w * 0.5, y1, d * 0.5), Vector3(-w * 0.5, y1, -d * 0.5), Vector3(-w * 0.5 - out, y1, -d * 0.5))
	m.box(Vector3(-w * 0.5 - out, y0 - 0.001, -d * 0.5 - out), Vector3(w * 0.5 + out, y0, d * 0.5 + out), 8)


## Merlons along a line (local), each facing `n` (outward).
static func merlons(c: ArchCtx, a: Vector3, b: Vector3, kind: int, custom: Color, spacing := 1.3, mw := 0.6, mh := 0.8, mt := 0.4) -> void:
	var len := a.distance_to(b)
	var n := maxi(1, int(len / spacing))
	var dir := (b - a) / len
	var yaw := atan2(dir.x, dir.z) - PI * 0.5
	for i in range(n):
		var p := a + dir * (len * (i + 0.5) / n)
		c.place(M.merlon(kind, mw, mh, mt), Transform3D(Basis(UP, yaw), p), Color.WHITE, custom)


static func _plinth(c: ArchCtx, w: float, d: float, yb: float, h: float, mat: Array) -> void:
	var m := c.m
	m.xf = c.bxf
	m.layer = mat[0]; m.tint = mat[1]
	m.box(Vector3(-w * 0.5 - 0.06, yb, -d * 0.5 - 0.06), Vector3(w * 0.5 + 0.06, h, d * 0.5 + 0.06), 63 - 8)


# ---------------------------------------------------------------- towers
static func tower(c: ArchCtx, p: Dictionary) -> void:
	var rng := _rng(p)
	var style: String = p.get("style", "campo")
	var s: float = clampf(minf(float(p.w), float(p.d)), 4.0, 9.0)
	var floors := clampi(int(p.get("floors", 5)), 2, 8)
	var mats := _mats(style, rng)
	var wall: Array = mats[0]; var trim: Array = mats[1]
	var yb := _yb(p)
	var shaft := floors * (3.3 if style != "sarmada" else 3.6)
	var belfry := 3.8
	var paint := Color(0.2, 0.2, 0.22, 3)
	var hw := s * 0.5
	var m := c.m
	m.ground = 0.0; m.eave = shaft + belfry
	_plinth(c, s, s, yb, 0.6, trim)
	# the shaft: a door at the foot, slit windows up the faces, a clock under the belfry
	var ops := {0: [], 1: [], 2: [], 3: []}
	var dk := M.door(1.3, 2.7, 0.6, 1 if style == "valdoro" else 0, false, 0.2, trim[1], 1, true)
	ops[0].append([hw, 0.0, 1.3, 2.7, 0.6, 1, false, dk, Color(0.3, 0.2, 0.14, 1)])
	var slit := M.window(0.45, 1.1, 0.6, trim[1], 0.12 if style != "valdoro" else 0.0, trim[1], 0, 1 if style == "valdoro" else 0, false, Vector2i(1, 1), 0)
	for f in range(4):
		for k in range(1, floors):
			if (k + f) % 2 == 0: ops[f].append([hw, k * shaft / floors + 0.8, 0.45, 1.1, 0.6, 0, true, slit, paint])
	prism(c, -hw, hw, -hw, hw, 0.0, shaft, wall, ops)
	if style != "valdoro": band(c, s, s, shaft - 0.35, shaft, 0.12, trim)
	# clock faces (towns with a clock tower)
	if style in ["puerto", "campo", "core"]:
		for f: int in [0, 1]:
			c.place(M.clock(1.05), _faces_xf(s, s, f) * Transform3D(Basis(), Vector3(hw, shaft - 1.6, 0.06)))
	# the belfry: an arch on each face with a bell, then the top by style
	var bw := minf(s - 1.6, 2.4)
	var bops := {}
	for f in range(4):
		bops[f] = [[hw, shaft + 0.25, bw, belfry - 0.7, 0.6, 1, true, "", paint, "bell"]]
	var bs := s - 0.3 if style != "sarmada" else s
	var bh := (s - bs) * 0.5
	prism(c, -hw + bh, hw - bh, -hw + bh, hw - bh, shaft, shaft + belfry, wall, bops)
	var top := shaft + belfry
	m.xf = c.bxf
	match style:
		"valdoro":
			band(c, bs, bs, top - 0.25, top, 0.1, trim)
			var k := tan(deg_to_rad(64.0))
			F.hip(m, bs, bs, top, k, 0.25, 0.2, [S.wx(L.SLATE, 0.3), Color(0.95, 0.95, 0.97)], [S.wx(L.STONE, 0.3), Color(0.6, 0.6, 0.6)])
			_cross(c, Vector3(0, top + bs * 0.5 * k + 0.2, 0))
		"sarmada":
			var custom := Color(wall[1].r, wall[1].g, wall[1].b, wall[0])
			m.layer = S.wx(L.TERRACE, 0.3); m.tint = wall[1]
			m.quad(Vector3(-hw, top, hw), Vector3(hw, top, hw), Vector3(hw, top, -hw), Vector3(-hw, top, -hw))
			band(c, s, s, top - 0.4, top, 0.15, trim)
			for f in range(4):
				var fx := _faces_xf(s, s, f)
				merlons(c, fx * Vector3(0, top, -0.2), fx * Vector3(s, top, -0.2), 0, custom, 1.2, 0.6, 0.85, 0.35)
			# the lantern stage with a dome
			var ls := s * 0.42
			prism(c, -ls * 0.5, ls * 0.5, -ls * 0.5, ls * 0.5, top, top + 3.2, wall, {0: [[ls * 0.5, top + 0.6, 0.7, 1.8, 0.3, 2, true, "", paint]], 1: [[ls * 0.5, top + 0.6, 0.7, 1.8, 0.3, 2, true, "", paint]]})
			band(c, ls, ls, top + 2.9, top + 3.2, 0.1, trim)
			c.place(M.small_dome(ls * 0.42), Transform3D(Basis(), Vector3(0, top + 3.2, 0)), Color.WHITE, custom)
			m.xf = c.bxf
			m.layer = S.wx(L.IRON, 0.2); m.tint = Color(0.8, 0.65, 0.3)
			m.cylinder(Vector3(0, top + 3.2 + 0.6 + ls * 0.42 * 0.95 + 0.3, 0), 0.05, 0.05, 1.2, 5)
		"isola":
			band(c, bs, bs, top - 0.3, top, 0.12, trim)
			m.xf = c.bxf
			m.layer = S.wx(L.PLASTER, 0.05); m.tint = Color(0.3, 0.55, 0.5)
			m.cylinder(Vector3(0, top, 0), bs * 0.42, bs * 0.42, 0.8, 12, false)
			m.dome(Vector3(0, top + 0.8, 0), bs * 0.42, 1.3, 12, 5)
		_:
			band(c, bs, bs, top - 0.35, top, 0.18, trim)
			var k2 := tan(deg_to_rad(38.0 if style != "puerto" else 30.0))
			var rt := F.hip(m, bs, bs, top, k2, 0.35, 0.2, [S.wx(mats[2], 0.3), mats[3]], [S.wx(L.TIMBER, 0.3), Color(0.6, 0.5, 0.4)])
			m.layer = S.wx(L.IRON, 0.2); m.tint = Color(0.3, 0.3, 0.32)
			m.cylinder(Vector3(0, rt - 0.1, 0), 0.04, 0.03, 1.6, 5)
	m.xf = c.bxf
	c.box_shape(Vector3(-hw, yb, -hw), Vector3(hw, top, hw))


static func _cross(c: ArchCtx, at: Vector3) -> void:
	var m := c.m
	m.xf = c.bxf
	m.layer = S.wx(L.IRON, 0.2); m.tint = Color(0.25, 0.25, 0.27)
	m.box(at + Vector3(-0.05, 0, -0.05), at + Vector3(0.05, 1.4, 0.05))
	m.box(at + Vector3(-0.4, 0.85, -0.05), at + Vector3(0.4, 0.95, 0.05))


# ---------------------------------------------------------------- churches
static func church(c: ArchCtx, p: Dictionary) -> void:
	var rng := _rng(p)
	var style: String = p.get("style", "valdoro")
	var w: float = maxf(float(p.w), 6.0); var d: float = maxf(float(p.d), 9.0)
	var mats := _mats(style, rng)
	var wall: Array = mats[0]; var trim: Array = mats[1]
	if style == "isola": wall = [S.wx(L.PLASTER, 0.2), S.pick(rng, [Color(0.99, 0.88, 0.55), Color(0.98, 0.97, 0.94), Color(0.97, 0.8, 0.72)])]
	elif style == "valdoro": wall = [S.wx(L.PLASTER, 0.45), Color(0.93, 0.92, 0.88)]
	var yb := _yb(p)
	var H := 7.5 if style != "puerto" else 10.0
	var m := c.m
	m.ground = 0.0; m.eave = H
	_plinth(c, w, d, yb, 0.5, [S.wx(L.RUBBLE if style == "valdoro" else L.ASHLAR, 0.4), Color(0.9, 0.88, 0.84)])
	var paint := Color(0.4, 0.26, 0.16, 3)
	var ops := {0: [], 1: [], 2: [], 3: []}
	ops[0].append([w * 0.5, 0.0, 1.8, 3.6, 0.6, 1, false, M.door(1.8, 3.6, 0.6, 1, false, 0.3, trim[1], 1, true), paint])
	ops[0].append([w * 0.5, 4.6, 1.2, 1.2, 0.5, 1, true, M.window(1.2, 1.2, 0.5, trim[1], 0.18, trim[1], 0, 0, false, Vector2i(3, 3), 1), paint])
	var nwin := maxi(2, int(d / 4.5))
	for f: int in [2, 3]:
		for i in range(nwin):
			var x := d * (i + 0.5) / nwin
			ops[f].append([x, 2.6, 0.8, 2.6, 0.55, 1, true, M.window(0.8, 2.6, 0.55, trim[1], 0.0, trim[1], 0, 0, false, Vector2i(2, 5), 1), paint])
	prism(c, -w * 0.5, w * 0.5, -d * 0.5, d * 0.5, 0.0, H, wall, ops)
	band(c, w, d, H - 0.3, H, 0.14, trim)
	m.xf = c.bxf * Transform3D(Basis(UP, PI * 0.5), Vector3.ZERO)
	var k := tan(deg_to_rad(30.0 if style != "valdoro" else 32.0))
	var roof := [S.wx(mats[2], 0.3), mats[3]]
	if style == "sarmada": roof = [S.wx(L.ROOF_TILE, 0.3), Color(1, 1, 1)]
	var ridge := F.gable(m, d, w, H, k, 0.4, 0.3, 0.3, 0.22, roof, [S.wx(L.TIMBER, 0.4), Color(0.55, 0.45, 0.36)], wall)
	m.xf = c.bxf
	_cross(c, Vector3(0, ridge, d * 0.5 + 0.2))
	# the apse at the back: a half cylinder with a half cone
	var ar := w * 0.5 - 1.2
	m.layer = wall[0]; m.tint = wall[1]
	var seg := 8
	var apex := Vector3(0, H + 0.2, -d * 0.5)
	for i in range(seg):
		var a0 := PI * i / seg; var a1 := PI * (i + 1) / seg
		var p0 := Vector3(cos(a0) * ar, 0, -d * 0.5 - sin(a0) * ar); var p1 := Vector3(cos(a1) * ar, 0, -d * 0.5 - sin(a1) * ar)
		var outv := Vector3((p0.x + p1.x) * 0.5, 0, (p0.z + p1.z) * 0.5 + d * 0.5)
		m.layer = wall[0]; m.tint = wall[1]
		F.quad_out(m, p0 + Vector3(0, yb, 0), p1 + Vector3(0, yb, 0), p1 + Vector3(0, H - 1.5, 0), p0 + Vector3(0, H - 1.5, 0), outv)
		m.layer = roof[0]; m.tint = roof[1]
		var e0 := Vector3(p0.x * 1.1, H - 1.6, -d * 0.5 + (p0.z + d * 0.5) * 1.1); var e1 := Vector3(p1.x * 1.1, H - 1.6, -d * 0.5 + (p1.z + d * 0.5) * 1.1)
		F.tri_out(m, e0, e1, apex, outv + Vector3(0, ar, 0))
	m.layer = wall[0]; m.tint = wall[1]
	match style:
		"isola", "puerto":
			if style == "puerto":
				# twin bell towers framing the front
				var ts := minf(3.6, w * 0.3)
				var th := H + 7.5
				var keep := c.bxf
				for sx: float in [-1.0, 1.0]:
					c.bxf = keep * Transform3D(Basis(), Vector3(sx * (w * 0.5 - ts * 0.5), 0, d * 0.5 - ts * 0.5 + 0.4))
					m.xf = c.bxf
					prism(c, -ts * 0.5, ts * 0.5, -ts * 0.5, ts * 0.5, yb, th, wall, {0: [[ts * 0.5, th - 3.2, 1.3, 2.5, 0.5, 1, true, "", paint, "bell"]],
						2 if sx > 0 else 3: [[ts * 0.5, th - 3.2, 1.3, 2.5, 0.5, 1, true, "", paint, "bell"]]})
					band(c, ts, ts, th - 0.35, th, 0.14, trim)
					band(c, ts, ts, H - 0.3, H, 0.14, trim)
					F.hip(m, ts, ts, th, tan(deg_to_rad(55.0)), 0.25, 0.18, roof, [S.wx(L.TIMBER, 0.3), Color(0.6, 0.5, 0.4)])
					_cross(c, Vector3(0, th + ts * 0.5 * tan(deg_to_rad(55.0)) + 0.2, 0))
					c.box_shape(Vector3(-ts * 0.5, yb, -ts * 0.5), Vector3(ts * 0.5, th, ts * 0.5))
				c.bxf = keep
				m.xf = keep
			# a tiled dome on a drum over the crossing
			var dr := minf(w * 0.34, 3.4)
			var cz := -d * 0.15
			var dy := ridge - 0.6
			m.layer = wall[0]; m.tint = wall[1]
			m.xf = c.bxf
			var dseg := 12
			for i in range(dseg):
				var a0 := TAU * i / dseg; var a1 := TAU * (i + 1) / dseg
				var q0 := Vector3(sin(a0) * dr, 0, cos(a0) * dr + cz); var q1 := Vector3(sin(a1) * dr, 0, cos(a1) * dr + cz)
				F.quad_out(m, q0 + Vector3(0, H, 0), q1 + Vector3(0, H, 0), q1 + Vector3(0, dy + 1.6, 0), q0 + Vector3(0, dy + 1.6, 0), (q0 + q1) * 0.5 - Vector3(0, 0, cz))
			m.layer = trim[0]; m.tint = trim[1]
			m.cylinder(Vector3(0, dy + 1.6, cz), dr + 0.12, dr + 0.12, 0.2, dseg, false)
			m.layer = S.wx(L.PLASTER, 0.05); m.tint = Color(0.22, 0.42, 0.78) if style == "isola" else Color(0.3, 0.55, 0.5)
			m.dome(Vector3(0, dy + 1.8, cz), dr, 1.15, dseg, 6)
			m.layer = trim[0]; m.tint = trim[1]
			m.cylinder(Vector3(0, dy + 1.8 + dr * 1.15 - 0.1, cz), 0.45, 0.4, 1.0, 8, false)
			m.dome(Vector3(0, dy + 2.7 + dr * 1.15 - 0.1, cz), 0.45, 1.0, 8, 3)
			_cross(c, Vector3(0, dy + 3.1 + dr * 1.15, cz))
			if style == "isola":
				# a bell gable over the front
				m.layer = wall[0]; m.tint = wall[1]
				var gz := d * 0.5
				var bx := 2.8
				var fxf := Transform3D(Basis(), Vector3(-bx * 0.5, 0, gz))
				F.use(m, c.bxf, fxf)
				var holes: Array = []
				F.opening(m, holes, bx * 0.5, ridge + 0.1, 0.9, 1.6, 0.3, 1, true)
				F.wall(m, ridge - 0.6, ridge + 2.2, 0.0, bx, holes)
				m.box(Vector3(0, ridge - 0.6, -0.3), Vector3(bx, ridge + 2.2, 0.0), 1 | 2 | 4 | 32)
				c.place(M.bell(0.3), fxf * Transform3D(Basis(), Vector3(bx * 0.5, ridge + 1.45, -0.15)))
				m.xf = c.bxf
		"campo", "sarmada", "core":
			# a squat bell tower beside the front
			var ts := 3.6
			var th := H + 6.0
			var keep := c.bxf
			c.bxf = c.bxf * Transform3D(Basis(), Vector3(w * 0.5 + ts * 0.5 - 0.2, 0, d * 0.5 - ts * 0.5))
			m.xf = c.bxf
			prism(c, -ts * 0.5, ts * 0.5, -ts * 0.5, ts * 0.5, yb, th, wall, {0: [[ts * 0.5, th - 3.0, 1.4, 2.4, 0.5, 1, true, "", paint, "bell"]], 2: [[ts * 0.5, th - 3.0, 1.4, 2.4, 0.5, 1, true, "", paint, "bell"]]})
			band(c, ts, ts, th - 0.3, th, 0.12, trim)
			F.hip(m, ts, ts, th, tan(deg_to_rad(35.0)), 0.3, 0.2, roof, [S.wx(L.TIMBER, 0.3), Color(0.6, 0.5, 0.4)])
			c.box_shape(Vector3(-ts * 0.5, yb, -ts * 0.5), Vector3(ts * 0.5, th, ts * 0.5))
			c.bxf = keep
			m.xf = keep
	c.box_shape(Vector3(-w * 0.5, yb, -d * 0.5), Vector3(w * 0.5, H, d * 0.5))
	c.convex_shape(PackedVector3Array([Vector3(-w * 0.5, H, -d * 0.5), Vector3(w * 0.5, H, -d * 0.5), Vector3(-w * 0.5, H, d * 0.5), Vector3(w * 0.5, H, d * 0.5),
		Vector3(0, ridge - 0.2, -d * 0.5), Vector3(0, ridge - 0.2, d * 0.5)]))


# ---------------------------------------------------------------- windmill, lighthouse
static func windmill(c: ArchCtx, p: Dictionary) -> void:
	var rng := _rng(p)
	var s: float = minf(float(p.w), float(p.d))
	var r0 := clampf(s * 0.36, 2.2, 3.6); var r1 := r0 * 0.82
	var H := 8.5 + rng.randf_range(-0.5, 0.8)
	var yb := _yb(p)
	var m := c.m
	m.ground = 0.0; m.eave = H
	m.xf = c.bxf
	m.layer = S.wx(L.WHITEWASH, rng.randf_range(0.2, 0.6)); m.tint = Color(0.98, 0.97, 0.95)
	m.cylinder(Vector3(0, yb, 0), r0 + 0.1, r0, -yb, 14, false)
	m.cylinder(Vector3(0, 0, 0), r0, r1, H, 14, false)
	# a porch with the door, blind windows up the drum
	var fx := Transform3D(Basis(), Vector3(-0.85, 0, r0 - 0.35))
	F.use(m, c.bxf, fx)
	var holes: Array = []
	F.opening(m, holes, 0.85, 0.0, 1.0, 2.2, 0.4, 1, false, false)
	F.wall(m, 0.0, 2.9, 0.0, 1.7, holes)
	m.box(Vector3(0, 0, -0.6), Vector3(1.7, 2.9, 0), 1 | 2)
	m.layer = S.wx(L.ROOF_TILE, 0.3); m.tint = Color(0.9, 0.9, 0.9)
	m.box(Vector3(-0.1, 2.9, -0.6), Vector3(1.8, 3.05, 0.12), 63)
	c.place(M.door(1.0, 2.2, 0.4, 1, false, 0.0, Color.WHITE, 1, true), fx * Transform3D(Basis(), Vector3(0.85, 0, 0)), Color(0.18, 0.34, 0.6, 1), Color(0.98, 0.97, 0.95, L.WHITEWASH))
	m.xf = c.bxf
	for i in range(2):
		var a := PI * (0.7 + 0.6 * i)
		var y := 4.2 + i * 1.8
		var rr := lerpf(r0, r1, y / H) + 0.02
		var b := Basis(UP, a)
		var keep := m.xf
		m.xf = c.bxf * Transform3D(b, Vector3(sin(a) * rr, y, cos(a) * rr))
		m.layer = S.wx(L.GLASS, 0.0); m.tint = Color.WHITE
		m.quad(Vector3(-0.3, 0, 0), Vector3(0.3, 0, 0), Vector3(0.3, 0.7, 0), Vector3(-0.3, 0.7, 0))
		m.layer = S.wx(L.STONE, 0.2); m.tint = Color(0.9, 0.88, 0.84)
		m.box(Vector3(-0.38, -0.08, -0.05), Vector3(0.38, 0.0, 0.1))
		m.xf = keep
	# the cap and the sails
	m.layer = S.wx(L.TIMBER, 0.5); m.tint = Color(0.42, 0.4, 0.38)
	m.cylinder(Vector3(0, H, 0), r1 + 0.3, 0.1, 2.6, 14, false, true)
	var face_yaw := rng.randf_range(-0.5, 0.5)
	c.place(M.sails(7.5), Transform3D(Basis(UP, face_yaw), Vector3(sin(face_yaw) * (r1 + 0.1), H + 1.0, cos(face_yaw) * (r1 + 0.1))))
	# the tail pole down the back
	var tb := Basis(UP, face_yaw)
	var ta := Vector3(0, H + 0.3, -(r1 + 0.3)); var tz := Vector3(0, 0.4, -(r0 + 2.2))
	var tv := ta - tz
	m.rbox(tb * ((ta + tz) * 0.5), Vector3(0.18, 0.18, tv.length()), tb * Basis(Vector3.RIGHT, atan2(-tv.y, tv.z)))
	var cyl := CylinderShape3D.new(); cyl.radius = r0; cyl.height = H - yb
	if c.collide: c.shapes.append([cyl, c.bxf * Transform3D(Basis(), Vector3(0, (H + yb) * 0.5, 0))])


static func lighthouse(c: ArchCtx, p: Dictionary) -> void:
	var yb := _yb(p)
	var r := clampf(minf(float(p.w), float(p.d)) * 0.3, 1.8, 3.0)
	var H := 16.0
	var m := c.m
	m.ground = 0.0; m.eave = H
	m.xf = c.bxf
	m.layer = S.wx(L.PLASTER, 0.3); m.tint = Color(0.97, 0.96, 0.94)
	m.cylinder(Vector3(0, yb, 0), r * 1.1, r, H * 0.45 - yb, 14, false)
	m.tint = Color(0.72, 0.18, 0.14)
	m.cylinder(Vector3(0, H * 0.45, 0), r, r * 0.9, H * 0.2, 14, false)
	m.tint = Color(0.97, 0.96, 0.94)
	m.cylinder(Vector3(0, H * 0.65, 0), r * 0.9, r * 0.82, H * 0.35, 14, true)
	m.layer = S.wx(L.STONE, 0.3); m.tint = Color(0.8, 0.8, 0.78)
	m.cylinder(Vector3(0, H, 0), r * 1.2, r * 1.2, 0.25, 14, true, true)
	m.layer = S.wx(L.GLASS, 0.0); m.tint = Color.WHITE
	m.cylinder(Vector3(0, H + 0.25, 0), r * 0.6, r * 0.6, 1.8, 10, false)
	m.layer = S.wx(L.IRON, 0.2); m.tint = Color(0.2, 0.22, 0.24)
	m.dome(Vector3(0, H + 2.05, 0), r * 0.66, 0.8, 10, 3)
	var cyl := CylinderShape3D.new(); cyl.radius = r; cyl.height = H - yb
	if c.collide: c.shapes.append([cyl, c.bxf * Transform3D(Basis(), Vector3(0, (H + yb) * 0.5, 0))])


# ---------------------------------------------------------------- walls, gates, citadel
static func _fort_mats(style: String, rng: RandomNumberGenerator) -> Array:
	if style == "sarmada": return [[S.wx(L.ADOBE, rng.randf_range(0.2, 0.6)), Color(0.92, 0.68, 0.46)], [S.wx(L.ADOBE, 0.3), Color(0.96, 0.8, 0.6)], 0]
	if style == "valdoro": return [[S.wx(L.RUBBLE, 0.4), Color(1, 1, 1)], [S.wx(L.STONE, 0.3), Color(0.7, 0.7, 0.7)], 1]
	return [[S.wx(L.RUBBLE, rng.randf_range(0.2, 0.6)), Color(1.0, 0.9, 0.74)], [S.wx(L.ASHLAR, 0.3), S.CAMPO_HONEY], 1]


static func town_wall(c: ArchCtx, p: Dictionary) -> void:
	var rng := _rng(p)
	var style: String = p.get("style", "sarmada")
	var fm := _fort_mats(style, rng)
	var w: float = float(p.w) + 0.6; var d: float = maxf(float(p.d), 1.8)
	var H := clampf(int(p.get("floors", 3)) * 2.6, 4.0, 12.0)
	var yb := _yb(p)
	var m := c.m
	m.ground = 0.0; m.eave = H + 2.0
	m.xf = c.bxf
	m.layer = fm[0][0]; m.tint = fm[0][1]
	var bat := 0.25             # batter: the wall leans in as it rises
	m.quad(Vector3(-w * 0.5, yb, d * 0.5), Vector3(w * 0.5, yb, d * 0.5), Vector3(w * 0.5, H, d * 0.5 - bat), Vector3(-w * 0.5, H, d * 0.5 - bat))
	m.quad(Vector3(w * 0.5, yb, -d * 0.5), Vector3(-w * 0.5, yb, -d * 0.5), Vector3(-w * 0.5, H, -d * 0.5 + bat), Vector3(w * 0.5, H, -d * 0.5 + bat))
	for s: float in [-1.0, 1.0]:
		F.quad_out(m, Vector3(w * 0.5 * s, yb, d * 0.5), Vector3(w * 0.5 * s, yb, -d * 0.5), Vector3(w * 0.5 * s, H, -d * 0.5 + bat), Vector3(w * 0.5 * s, H, d * 0.5 - bat), Vector3(s, 0, 0))
	m.layer = S.wx(L.TERRACE, 0.5); m.tint = fm[0][1]
	m.quad(Vector3(-w * 0.5, H, d * 0.5 - bat), Vector3(w * 0.5, H, d * 0.5 - bat), Vector3(w * 0.5, H, -d * 0.5 + bat), Vector3(-w * 0.5, H, -d * 0.5 + bat))
	# a string course below the parapet and merlons on both edges
	m.layer = fm[1][0]; m.tint = fm[1][1]
	m.box(Vector3(-w * 0.5, H - 0.9, d * 0.5 - bat), Vector3(w * 0.5, H - 0.7, d * 0.5 - bat + 0.1), 4 | 8 | 16)
	m.box(Vector3(-w * 0.5, H - 0.9, -d * 0.5 + bat - 0.1), Vector3(w * 0.5, H - 0.7, -d * 0.5 + bat), 4 | 8 | 32)
	var custom := Color(fm[0][1].r, fm[0][1].g, fm[0][1].b, fm[0][0])
	var mk: int = 0 if style == "sarmada" else 1
	merlons(c, Vector3(-w * 0.5, H, d * 0.5 - bat - 0.2), Vector3(w * 0.5, H, d * 0.5 - bat - 0.2), mk, custom, 1.4, 0.7, 0.9, 0.4)
	merlons(c, Vector3(w * 0.5, H, -d * 0.5 + bat + 0.2), Vector3(-w * 0.5, H, -d * 0.5 + bat + 0.2), mk, custom, 1.4, 0.7, 0.9, 0.4)
	# drainage spouts / putlog holes: beam ends on the sarmada walls
	if style == "sarmada":
		for i in range(int(w / 1.6)):
			c.place(M.beam(), Transform3D(Basis(), Vector3(-w * 0.5 + 0.8 + i * 1.6, H - 2.2 - (i % 2) * 1.6, d * 0.5 - bat * 0.6)))
	c.box_shape(Vector3(-w * 0.5, yb, -d * 0.5), Vector3(w * 0.5, H, d * 0.5))


static func gate(c: ArchCtx, p: Dictionary) -> void:
	var rng := _rng(p)
	var style: String = p.get("style", "sarmada")
	var fm := _fort_mats(style, rng)
	var w: float = float(p.w); var d: float = float(p.d)
	var H := clampf(int(p.get("floors", 3)) * 3.3, 7.0, 13.0)
	var yb := _yb(p)
	var pw := minf(4.4, w - 4.0)
	var arch := 2 if style == "sarmada" else 1
	var ph := minf(H - 2.5, 6.0)
	var m := c.m
	m.ground = 0.0; m.eave = H
	_plinth(c, w, d, yb, 0.0, fm[0])
	for side: int in [0, 1]:
		var fx := F.face(side, w, d)[0] as Transform3D
		F.use(m, c.bxf, fx)
		m.layer = fm[0][0]; m.tint = fm[0][1]
		var holes: Array = []
		F.opening(m, holes, w * 0.5, 0.0, pw, ph, d if side == 0 else 0.0, arch, false)
		F.wall(m, 0.0, H, 0.0, w, holes)
		# the archivolt: a proud band of dressed stone round the arch, a panel above
		m.xf = c.bxf * fx * Transform3D(Basis(), Vector3(w * 0.5, 0, 0))
		m.layer = fm[1][0]; m.tint = fm[1][1]
		var top := F.arch_top(pw, arch)
		ArchModules._arch_band(m, pw, ph - top, 0.45, 0.08, arch)
		m.box(Vector3(-pw * 0.5 - 0.45, 0.0, 0.0), Vector3(-pw * 0.5, ph - top, 0.08), 1 | 2 | 16)
		m.box(Vector3(pw * 0.5, 0.0, 0.0), Vector3(pw * 0.5 + 0.45, ph - top, 0.08), 1 | 2 | 16)
		m.box(Vector3(-pw * 0.5 - 0.8, ph + 0.5, 0.0), Vector3(pw * 0.5 + 0.8, ph + 0.62, 0.14), 63 - 32)
	m.xf = c.bxf
	for s: int in [2, 3]:
		F.use(m, c.bxf, F.face(s, w, d)[0])
		m.layer = fm[0][0]; m.tint = fm[0][1]
		F.wall(m, 0.0, H, 0.0, d, [])
	m.xf = c.bxf
	m.layer = S.wx(L.TERRACE, 0.4); m.tint = fm[0][1]
	m.quad(Vector3(-w * 0.5, H, d * 0.5), Vector3(w * 0.5, H, d * 0.5), Vector3(w * 0.5, H, -d * 0.5), Vector3(-w * 0.5, H, -d * 0.5))
	band(c, w, d, H - 0.5, H - 0.3, 0.1, fm[1])
	var custom := Color(fm[0][1].r, fm[0][1].g, fm[0][1].b, fm[0][0])
	var mk: int = 0 if style == "sarmada" else 1
	for side in range(4):
		var fx := F.face(side, w, d)
		var W: float = fx[1]
		merlons(c, (fx[0] as Transform3D) * Vector3(0, H, -0.22), (fx[0] as Transform3D) * Vector3(W, H, -0.22), mk, custom, 1.3, 0.7, 1.0, 0.44)
	# collision: two piers and the mass over the passage
	c.box_shape(Vector3(-w * 0.5, yb, -d * 0.5), Vector3(-pw * 0.5, H, d * 0.5))
	c.box_shape(Vector3(pw * 0.5, yb, -d * 0.5), Vector3(w * 0.5, H, d * 0.5))
	c.box_shape(Vector3(-pw * 0.5, ph, -d * 0.5), Vector3(pw * 0.5, H, d * 0.5))


## The kasbah: curtain walls round a courtyard, square corner towers, a gate in the front wall,
## a keep in the middle; crenellated everything.
static func citadel(c: ArchCtx, p: Dictionary) -> void:
	var rng := _rng(p)
	var style: String = p.get("style", "sarmada")
	var fm := _fort_mats(style, rng)
	var w: float = float(p.w); var d: float = float(p.d)
	var yb := _yb(p)
	var H := 9.0
	var t := 3.0
	var ts := 8.0
	var TH := 13.5
	var m := c.m
	m.ground = 0.0
	var custom := Color(fm[0][1].r, fm[0][1].g, fm[0][1].b, fm[0][0])
	var mk: int = 0 if style == "sarmada" else 1
	var keep_xf := c.bxf
	# curtain walls: each a town wall of the right length, placed along the sides
	var sides := [[Vector3(0, 0, d * 0.5 - t * 0.5), 0.0, w - ts], [Vector3(0, 0, -d * 0.5 + t * 0.5), PI, w - ts],
		[Vector3(w * 0.5 - t * 0.5, 0, 0), PI * 0.5, d - ts], [Vector3(-w * 0.5 + t * 0.5, 0, 0), -PI * 0.5, d - ts]]
	for i in range(4):
		var s: Array = sides[i]
		c.bxf = keep_xf * Transform3D(Basis(UP, s[1]), s[0])
		m.xf = c.bxf
		m.eave = H + 2.0
		var len: float = s[2]
		m.layer = fm[0][0]; m.tint = fm[0][1]
		var fx := Transform3D(Basis(), Vector3(-len * 0.5, 0, t * 0.5))
		var bx := Transform3D(Basis(Vector3(-1, 0, 0), UP, Vector3(0, 0, -1)), Vector3(len * 0.5, 0, -t * 0.5))
		for face: Transform3D in [fx, bx]:
			F.use(m, c.bxf, face)
			var holes: Array = []
			if i == 0:
				F.opening(m, holes, len * 0.5, 0.0, 4.2, 6.0, t if face == fx else 0.0, 2 if style == "sarmada" else 1, false)
				if face == fx:
					m.xf = c.bxf * face * Transform3D(Basis(), Vector3(len * 0.5, 0, 0))
					m.layer = fm[1][0]; m.tint = fm[1][1]
					ArchModules._arch_band(m, 4.2, 6.0 - F.arch_top(4.2, 2 if style == "sarmada" else 1), 0.5, 0.1, 2 if style == "sarmada" else 1)
					F.use(m, c.bxf, face)
					m.layer = fm[0][0]; m.tint = fm[0][1]
			F.wall(m, yb, H, 0.0, len, holes)
		m.xf = c.bxf
		m.layer = S.wx(L.TERRACE, 0.5); m.tint = fm[0][1]
		m.quad(Vector3(-len * 0.5, H, t * 0.5), Vector3(len * 0.5, H, t * 0.5), Vector3(len * 0.5, H, -t * 0.5), Vector3(-len * 0.5, H, -t * 0.5))
		merlons(c, Vector3(-len * 0.5, H, t * 0.5 - 0.22), Vector3(len * 0.5, H, t * 0.5 - 0.22), mk, custom, 1.3, 0.7, 1.0, 0.44)
		if i == 0:
			c.box_shape(Vector3(-len * 0.5, yb, -t * 0.5), Vector3(-2.1, H, t * 0.5))
			c.box_shape(Vector3(2.1, yb, -t * 0.5), Vector3(len * 0.5, H, t * 0.5))
			c.box_shape(Vector3(-2.1, 6.0, -t * 0.5), Vector3(2.1, H, t * 0.5))
		else:
			c.box_shape(Vector3(-len * 0.5, yb, -t * 0.5), Vector3(len * 0.5, H, t * 0.5))
	c.bxf = keep_xf
	m.xf = keep_xf
	# corner towers
	for cx: float in [-1.0, 1.0]:
		for cz: float in [-1.0, 1.0]:
			c.bxf = keep_xf * Transform3D(Basis(), Vector3(cx * (w * 0.5 - ts * 0.5), 0, cz * (d * 0.5 - ts * 0.5)))
			m.xf = c.bxf
			m.eave = TH + 1.0
			var slit := M.window(0.4, 1.4, 0.5, fm[1][1], 0.1, fm[1][1], 0, 0, false, Vector2i(1, 1), 0)
			var ops := {0: [[ts * 0.5, 7.0, 0.4, 1.4, 0.5, 0, true, slit, Color(1, 1, 1, 3)]], 2: [[ts * 0.5, 10.0, 0.4, 1.4, 0.5, 0, true, slit, Color(1, 1, 1, 3)]]}
			prism(c, -ts * 0.5, ts * 0.5, -ts * 0.5, ts * 0.5, yb, TH, fm[0], ops)
			band(c, ts, ts, TH - 1.4, TH - 1.1, 0.12, fm[1])
			m.layer = S.wx(L.TERRACE, 0.5); m.tint = fm[0][1]
			m.quad(Vector3(-ts * 0.5, TH, ts * 0.5), Vector3(ts * 0.5, TH, ts * 0.5), Vector3(ts * 0.5, TH, -ts * 0.5), Vector3(-ts * 0.5, TH, -ts * 0.5))
			for side in range(4):
				var fx := F.face(side, ts, ts)
				merlons(c, (fx[0] as Transform3D) * Vector3(0, TH, -0.22), (fx[0] as Transform3D) * Vector3(ts, TH, -0.22), mk, custom, 1.3, 0.7, 1.0, 0.44)
			c.box_shape(Vector3(-ts * 0.5, yb, -ts * 0.5), Vector3(ts * 0.5, TH, ts * 0.5))
	# the keep
	var ks := minf(16.0, minf(w, d) * 0.32)
	var KH := 16.0
	c.bxf = keep_xf * Transform3D(Basis(), Vector3(0, 0, -d * 0.12))
	m.xf = c.bxf
	m.eave = KH + 1.0
	var kw := M.window(0.7, 1.1, 0.5, fm[1][1], 0.16, fm[1][1], 2, 0, false, Vector2i(1, 2), 0)
	var kd := M.door(1.6, 3.0, 0.6, 1, false, 0.35, fm[1][1], 2 if style == "sarmada" else 1, true)
	var kops := {0: [[ks * 0.5, 0.0, 1.6, 3.0, 0.6, 2 if style == "sarmada" else 1, false, kd, Color(0.12, 0.34, 0.6, 1)]], 1: [], 2: [], 3: []}
	for f in range(4):
		for k in range(2):
			for j in range(2):
				kops[f].append([ks * (0.3 + 0.4 * j), 6.0 + k * 4.5, 0.7, 1.1, 0.5, 0, true, kw, Color(0.12, 0.34, 0.6, 7)])
	prism(c, -ks * 0.5, ks * 0.5, -ks * 0.5, ks * 0.5, yb, KH, fm[0], kops)
	band(c, ks, ks, KH - 1.4, KH - 1.1, 0.14, fm[1])
	m.layer = S.wx(L.TERRACE, 0.5); m.tint = fm[0][1]
	m.quad(Vector3(-ks * 0.5, KH, ks * 0.5), Vector3(ks * 0.5, KH, ks * 0.5), Vector3(ks * 0.5, KH, -ks * 0.5), Vector3(-ks * 0.5, KH, -ks * 0.5))
	for side in range(4):
		var fx := F.face(side, ks, ks)
		merlons(c, (fx[0] as Transform3D) * Vector3(0, KH, -0.22), (fx[0] as Transform3D) * Vector3(ks, KH, -0.22), mk, custom, 1.3, 0.7, 1.0, 0.44)
	c.place(M.small_dome(2.0), Transform3D(Basis(), Vector3(ks * 0.2, KH, -ks * 0.2)), Color.WHITE, custom)
	c.box_shape(Vector3(-ks * 0.5, yb, -ks * 0.5), Vector3(ks * 0.5, KH, ks * 0.5))
	c.bxf = keep_xf
	m.xf = keep_xf


# ---------------------------------------------------------------- silhouettes
static func lod(m: ArchMesh, p: Dictionary) -> void:
	var kind: String = p.get("kind", "tower")
	var style: String = p.get("style", "campo")
	var rng := _rng(p)
	var w: float = float(p.w); var d: float = float(p.d)
	var yb := _yb(p)
	var mats := _mats(style, rng)
	var col: Color = BuildingKit.lod_colour(mats[0])
	var fort: Color = BuildingKit.lod_colour(_fort_mats(style, rng)[0])
	var roof: Color = BuildingKit.LOD_ROOF.get(mats[2], col)
	var i := 0.3
	match kind:
		"tower":
			var s := clampf(minf(w, d), 4.0, 9.0) - 0.6
			var top := clampi(int(p.get("floors", 5)), 2, 8) * (3.3 if style != "sarmada" else 3.6) + 3.8
			m.tint = col
			m.box(Vector3(-s * 0.5, yb, -s * 0.5), Vector3(s * 0.5, top, s * 0.5), 63 - 8)
			m.tint = roof
			if style != "sarmada": F.hip(m, s, s, top, tan(deg_to_rad(64.0 if style == "valdoro" else 36.0)), 0.2, 0.0, [0.0, roof], [0.0, roof])
			else: m.box(Vector3(-s * 0.21, top, -s * 0.21), Vector3(s * 0.21, top + 3.8, s * 0.21), 63 - 8)
		"church":
			m.tint = col
			var H := 7.5 if style != "puerto" else 10.0
			m.box(Vector3(-w * 0.5 + i, yb, -d * 0.5 + i), Vector3(w * 0.5 - i, H, d * 0.5 - i), 63 - 8)
			m.tint = roof
			var k := tan(deg_to_rad(30.0))
			for s: float in [-1.0, 1.0]:
				F.quad_out(m, Vector3(w * 0.5 * s, H - 0.2, d * 0.5), Vector3(0, H + w * 0.5 * k, d * 0.5), Vector3(0, H + w * 0.5 * k, -d * 0.5), Vector3(w * 0.5 * s, H - 0.2, -d * 0.5), Vector3(s, 1, 0))
			if style in ["isola", "puerto"]:
				m.tint = Color(0.2, 0.36, 0.6)
				m.dome(Vector3(0, H + w * 0.5 * k, -d * 0.15), minf(w * 0.34, 3.4), 1.15, 6, 2)
		"windmill":
			m.tint = Color(0.95, 0.94, 0.92)
			var r := clampf(minf(w, d) * 0.36, 2.2, 3.6) - 0.2
			m.cylinder(Vector3(0, yb, 0), r, r * 0.82, 8.5 - yb, 6, false)
			m.tint = Color(0.35, 0.33, 0.32)
			m.cylinder(Vector3(0, 8.5, 0), r * 0.82 + 0.3, 0.05, 2.6, 6, false)
		"lighthouse":
			m.tint = Color(0.95, 0.94, 0.92)
			m.cylinder(Vector3(0, yb, 0), 2.0, 1.7, 18.0 - yb, 6, true)
		"wall":
			m.tint = fort
			var H2 := clampf(int(p.get("floors", 3)) * 2.6, 4.0, 12.0)
			m.box(Vector3(-w * 0.5, yb, -d * 0.5 + i), Vector3(w * 0.5, H2 + 0.6, d * 0.5 - i), 63 - 8)
		"gate":
			m.tint = fort
			var H3 := clampf(int(p.get("floors", 3)) * 3.3, 7.0, 13.0)
			m.box(Vector3(-w * 0.5 + i, yb, -d * 0.5 + i), Vector3(w * 0.5 - i, H3 + 0.7, d * 0.5 - i), 63 - 8)
		"citadel":
			m.tint = fort
			m.box(Vector3(-w * 0.5 + i, yb, -d * 0.5 + i), Vector3(w * 0.5 - i, 9.6, d * 0.5 - i), 63 - 8)
			for cx: float in [-1.0, 1.0]:
				for cz: float in [-1.0, 1.0]:
					var o := Vector3(cx * (w * 0.5 - 4.0), 0, cz * (d * 0.5 - 4.0))
					m.box(o + Vector3(-3.7, 9.6, -3.7), o + Vector3(3.7, 14.4, 3.7), 63 - 8)
			var ks := minf(16.0, minf(w, d) * 0.32) - 0.6
			m.box(Vector3(-ks * 0.5, 9.6, -d * 0.12 - ks * 0.5), Vector3(ks * 0.5, 16.8, -d * 0.12 + ks * 0.5), 63 - 8)
