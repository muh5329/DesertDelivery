class_name ArchFacade
extends RefCounted
## Geometry of walls and roofs for the architecture kit, written into a group's ArchMesh.
##
## A face is a Transform3D from face space to the building's local frame plus its width: in face
## space x runs along the wall to the viewer's right (0..W), y up from the pad, z out of the wall.
## Walls are cut around rectangular holes (openings); each hole gets a reveal (the wall's thickness
## seen in the opening) and, when arched, the spandrels and the curved intrados. Roofs are built in
## the building's local frame (x along the frontage, z depth, +z = street side).

const L = preload("res://world/kit/building/arch_materials.gd")
const UP := Vector3.UP


## The four faces of a w x d box: 0 front (+z), 1 back, 2 right (+x), 3 left (-x). -> [Transform3D, W]
static func face(side: int, w: float, d: float) -> Array:
	match side:
		1: return [Transform3D(Basis(Vector3(-1, 0, 0), UP, Vector3(0, 0, -1)), Vector3(w * 0.5, 0, -d * 0.5)), w]
		2: return [Transform3D(Basis(Vector3(0, 0, -1), UP, Vector3(1, 0, 0)), Vector3(w * 0.5, 0, d * 0.5)), d]
		3: return [Transform3D(Basis(Vector3(0, 0, 1), UP, Vector3(-1, 0, 0)), Vector3(-w * 0.5, 0, -d * 0.5)), d]
	return [Transform3D(Basis(Vector3(1, 0, 0), UP, Vector3(0, 0, 1)), Vector3(-w * 0.5, 0, d * 0.5)), w]


## Set the mesh transform to a face (call with ctx.bxf).
static func use(m: ArchMesh, bxf: Transform3D, fxf: Transform3D) -> void:
	m.xf = bxf * fxf


## A wall on the current face from y0 to y1 and x0 to x1, minus the holes ([x0, y0, x1, y1]; they
## must not overlap one another). Emits one quad per gap per horizontal band.
static func wall(m: ArchMesh, y0: float, y1: float, x0: float, x1: float, holes: Array) -> void:
	if y1 - y0 < 0.002 or x1 - x0 < 0.002: return
	var ys := PackedFloat32Array([y0, y1])
	var act: Array = []
	for h in holes:
		if h[3] <= y0 + 0.001 or h[1] >= y1 - 0.001 or h[2] <= x0 + 0.001 or h[0] >= x1 - 0.001: continue
		act.append(h)
		if h[1] > y0: ys.append(h[1])
		if h[3] < y1: ys.append(h[3])
	if act.is_empty():
		m.rect_z(x0, y0, x1, y1)
		return
	act.sort_custom(func(a, b): return a[0] < b[0])
	ys.sort()
	for i in range(ys.size() - 1):
		var ya := ys[i]; var yb := ys[i + 1]
		if yb - ya < 0.002: continue
		var ym := (ya + yb) * 0.5
		var x := x0
		for h in act:
			if h[1] > ym or h[3] < ym: continue
			var hx0: float = maxf(h[0], x0); var hx1: float = minf(h[2], x1)
			if hx0 > x + 0.002:
				m.rect_z(x, ya, hx0, yb)
			x = maxf(x, hx1)
		if x1 > x + 0.002:
			m.rect_z(x, ya, x1, yb)


## The reveal of a rectangular hole (sill, soffit, two jambs), R deep. `sill` false leaves the
## bottom open (doors: the step module covers it; arcades: the floor).
static func reveal(m: ArchMesh, x0: float, y0: float, x1: float, y1: float, R: float, sill := true, top := true) -> void:
	var z := -R
	var b := m.xf.basis
	if sill: m._push4(Vector3(x0, y0, 0), Vector3(x1, y0, 0), Vector3(x1, y0, z), Vector3(x0, y0, z), b.y,
		Vector2(x0, 0), Vector2(x1, 0), Vector2(x1, z), Vector2(x0, z))
	if top: m._push4(Vector3(x0, y1, z), Vector3(x1, y1, z), Vector3(x1, y1, 0), Vector3(x0, y1, 0), -b.y,
		Vector2(x0, -z), Vector2(x1, -z), Vector2(x1, 0), Vector2(x0, 0))
	m._push4(Vector3(x0, y0, 0), Vector3(x0, y0, z), Vector3(x0, y1, z), Vector3(x0, y1, 0), b.x,
		Vector2(0, -y0), Vector2(-z, -y0), Vector2(-z, -y1), Vector2(0, -y1))
	m._push4(Vector3(x1, y0, z), Vector3(x1, y0, 0), Vector3(x1, y1, 0), Vector3(x1, y1, z), -b.x,
		Vector2(z, -y0), Vector2(0, -y0), Vector2(0, -y1), Vector2(z, -y1))


## An opening centred at x, bottom y0, width w, total height h (to the top of the arch if arched).
## Appends its hole(s) to `holes` and emits the spandrels, and the reveal / intrados unless a
## module brings its own (`rev` false). Returns the springing
## height (y0 + h for a flat head).
static func opening(m: ArchMesh, holes: Array, x: float, y0: float, w: float, h: float, R: float, arch: int, sill := true, rev := true) -> float:
	var r := w * 0.5
	if arch == 0:
		holes.append(PackedFloat32Array([x - r, y0, x + r, y0 + h]))
		if rev: reveal(m, x - r, y0, x + r, y0 + h, R, sill)
		return y0 + h
	var pts := ArchModules.arch_points(w, 0.0, arch, 10)
	var top := 0.0; var wide := r
	for p in pts:
		top = maxf(top, p.y); wide = maxf(wide, absf(p.x))
	var spring := y0 + h - top
	# the hole: straight jambs up to the springing line, then the arch's bounding box
	holes.append(PackedFloat32Array([x - r, y0, x + r, spring]))
	holes.append(PackedFloat32Array([x - wide, spring, x + wide, y0 + h]))
	if rev: reveal(m, x - r, y0, x + r, spring, R, sill, false)
	# spandrels (wall face between the curve and the box) and the intrados
	var ytop := y0 + h
	var cy := spring + (r * tan(deg_to_rad(28.0)) if arch == 2 else 0.0)
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i] + Vector2(x, spring); var b: Vector2 = pts[i + 1] + Vector2(x, spring)
		if (a.y + b.y) * 0.5 >= cy - 0.001:
			# strip from the curve up to the top of the box (b is left of a)
			m.quad(Vector3(b.x, b.y, 0), Vector3(a.x, a.y, 0), Vector3(a.x, ytop, 0), Vector3(b.x, ytop, 0))
		else:
			# horseshoe foot: strip from the springing line up to the curve
			var lo := minf(a.x, b.x); var hi := maxf(a.x, b.x)
			var ylo := a.y if a.x < b.x else b.y; var yhi := b.y if a.x < b.x else a.y
			m.quad(Vector3(lo, spring, 0), Vector3(hi, spring, 0), Vector3(hi, yhi, 0), Vector3(lo, ylo, 0))
		if rev: m.quad(Vector3(a.x, a.y, 0), Vector3(b.x, b.y, 0), Vector3(b.x, b.y, -R), Vector3(a.x, a.y, -R))
	return spring


## Height of an arch head above its springing line for an opening of width w.
static func arch_top(w: float, arch: int) -> float:
	var top := 0.0
	for p in ArchModules.arch_points(w, 0.0, arch, 10): top = maxf(top, p.y)
	return top


## A box in the current (face or local) frame; thin alias for the mesh's own box.
static func fbox(m: ArchMesh, x0: float, y0: float, z0: float, x1: float, y1: float, z1: float, mask: int = 63) -> void:
	m.box(Vector3(x0, y0, z0), Vector3(x1, y1, z1), mask)


# ---------------------------------------------------------------- roofs (building local frame)
## A quad whose winding is fixed so its normal points along `out`.
static func quad_out(m: ArchMesh, a: Vector3, b: Vector3, c: Vector3, d: Vector3, out: Vector3) -> void:
	if (b - a).cross(d - a).dot(out) >= 0.0: m.quad(a, b, c, d)
	else: m.quad(d, c, b, a)


static func tri_out(m: ArchMesh, a: Vector3, b: Vector3, c: Vector3, out: Vector3) -> void:
	if (b - a).cross(c - a).dot(out) >= 0.0: m.tri(a, b, c)
	else: m.tri(a, c, b)


## A raised cap strip along a roof line a -> b (ridge or hip), `wd` wide, `lift` high.
static func cap(m: ArchMesh, a: Vector3, b: Vector3, wd: float, lift: float) -> void:
	var dir := b - a
	var side := dir.cross(UP).normalized() * wd * 0.5
	var up := Vector3(0, lift, 0)
	var len := dir.length()
	for s: float in [-1.0, 1.0]:
		var p0 := a + side * s; var p1 := b + side * s
		var out: Vector3 = side * s + up * 3.0
		if (p1 - p0).cross(a + up - p0).dot(out) >= 0.0:
			m.quad_uv(p0, p1, b + up, a + up, Vector2(0, 0), Vector2(0, len), Vector2(0.24, len), Vector2(0.24, 0))
		else:
			m.quad_uv(a + up, b + up, p1, p0, Vector2(0.24, 0), Vector2(0.24, len), Vector2(0, len), Vector2(0, 0))


## Gable roof, ridge along local x. Walls span x in [-Lx/2, Lx/2], z in [-D/2, D/2], eaves at H.
## ov = eave overhang (front/back), vl / vr = verge overhang at -x / +x (0 against a party wall).
## gable = [layer, tint] of the gable-end triangles (null: none). Returns the ridge height (top).
static func gable(m: ArchMesh, Lx: float, D: float, H: float, k: float, ov: float, vl: float, vr: float, t: float,
		roof: Array, soffit: Array, gable_wall, ridge_cap := true, ov_p := -1.0, ov_n := -1.0) -> float:
	var rise := D * 0.5 * k
	var tv := t * sqrt(1.0 + k * k)
	if ov_p < 0.0: ov_p = ov
	if ov_n < 0.0: ov_n = ov
	var yep := H - ov_p * k; var yen := H - ov_n * k
	var zp := D * 0.5 + ov_p; var zn := D * 0.5 + ov_n
	var xa := -Lx * 0.5 - vl; var xb := Lx * 0.5 + vr
	var yr := H + rise
	m.layer = roof[0]; m.tint = roof[1]
	var keep_eave := m.eave
	m.eave = 1000.0
	# slopes
	m.quad(Vector3(xa, yep + tv, zp), Vector3(xb, yep + tv, zp), Vector3(xb, yr + tv, 0), Vector3(xa, yr + tv, 0))
	m.quad(Vector3(xb, yen + tv, -zn), Vector3(xa, yen + tv, -zn), Vector3(xa, yr + tv, 0), Vector3(xb, yr + tv, 0))
	if ridge_cap:
		cap(m, Vector3(xa, yr + tv - 0.02, 0), Vector3(xb, yr + tv - 0.02, 0), 0.34, 0.12)
	# fascia and barge boards
	m.layer = soffit[0]; m.tint = soffit[1]
	m.quad(Vector3(xa, yep, zp), Vector3(xb, yep, zp), Vector3(xb, yep + tv, zp), Vector3(xa, yep + tv, zp))
	m.quad(Vector3(xb, yen, -zn), Vector3(xa, yen, -zn), Vector3(xa, yen + tv, -zn), Vector3(xb, yen + tv, -zn))
	for s: float in [-1.0, 1.0]:
		var x := xa if s < 0 else xb
		quad_out(m, Vector3(x, yep, zp), Vector3(x, yr, 0), Vector3(x, yr + tv, 0), Vector3(x, yep + tv, zp), Vector3(s, 0, 0))
		quad_out(m, Vector3(x, yen, -zn), Vector3(x, yr, 0), Vector3(x, yr + tv, 0), Vector3(x, yen + tv, -zn), Vector3(s, 0, 0))
	# soffits: under the eaves, and under the verges beyond the gable walls
	m.eave = H
	if ov_p > 0.01:
		quad_out(m, Vector3(xa, H, D * 0.5), Vector3(xb, H, D * 0.5), Vector3(xb, yep, zp), Vector3(xa, yep, zp), Vector3(0, -1, -k))
	if ov_n > 0.01:
		quad_out(m, Vector3(xa, H, -D * 0.5), Vector3(xb, H, -D * 0.5), Vector3(xb, yen, -zn), Vector3(xa, yen, -zn), Vector3(0, -1, k))
	for s: float in [-1.0, 1.0]:
		var v := vl if s < 0 else vr
		if v <= 0.01: continue
		var x0 := -Lx * 0.5 if s < 0 else Lx * 0.5
		var x1 := xa if s < 0 else xb
		for zs: float in [-1.0, 1.0]:
			quad_out(m, Vector3(x0, H, D * 0.5 * zs), Vector3(x1, H, D * 0.5 * zs), Vector3(x1, yr, 0), Vector3(x0, yr, 0), Vector3(0, -1, -k * zs))
	# gable ends
	if gable_wall != null:
		m.layer = gable_wall[0]; m.tint = gable_wall[1]
		m.eave = yr
		for s: float in [-1.0, 1.0]:
			var x := Lx * 0.5 * s
			tri_out(m, Vector3(x, H, D * 0.5), Vector3(x, H, -D * 0.5), Vector3(x, yr, 0), Vector3(s, 0, 0))
	m.eave = keep_eave
	return yr + tv


## Hip roof (Lx >= D; a pyramid when equal). Overhang ov all round. Returns the ridge top height.
static func hip(m: ArchMesh, Lx: float, D: float, H: float, k: float, ov: float, t: float, roof: Array, soffit: Array) -> float:
	var tv := t * sqrt(1.0 + k * k)
	var ye := H - ov * k
	var ex := Lx * 0.5 + ov; var ez := D * 0.5 + ov
	var xr := maxf(0.0, (Lx - D) * 0.5)
	var yr := H + minf(Lx, D) * 0.5 * k
	var keep_eave := m.eave
	m.eave = 1000.0
	m.layer = roof[0]; m.tint = roof[1]
	var c0 := Vector3(-ex, ye + tv, ez); var c1 := Vector3(ex, ye + tv, ez); var c2 := Vector3(ex, ye + tv, -ez); var c3 := Vector3(-ex, ye + tv, -ez)
	var r0 := Vector3(-xr, yr + tv, 0); var r1 := Vector3(xr, yr + tv, 0)
	if Lx >= D:
		m.quad(c0, c1, r1, r0)
		m.quad(c2, c3, r0, r1)
		m.tri(c1, c2, r1)
		m.tri(c3, c0, r0)
	var lift := 0.1
	cap(m, c0 + Vector3(0, 0.02, 0), r0, 0.3, lift); cap(m, c1 + Vector3(0, 0.02, 0), r1, 0.3, lift)
	cap(m, c2 + Vector3(0, 0.02, 0), r1, 0.3, lift); cap(m, c3 + Vector3(0, 0.02, 0), r0, 0.3, lift)
	if xr > 0.01: cap(m, r0 - Vector3(0, 0.02, 0), r1 - Vector3(0, 0.02, 0), 0.34, 0.12)
	# fascia
	m.layer = soffit[0]; m.tint = soffit[1]
	var e := [Vector3(-ex, ye, ez), Vector3(ex, ye, ez), Vector3(ex, ye, -ez), Vector3(-ex, ye, -ez)]
	var w := [Vector3(-Lx * 0.5, H, D * 0.5), Vector3(Lx * 0.5, H, D * 0.5), Vector3(Lx * 0.5, H, -D * 0.5), Vector3(-Lx * 0.5, H, -D * 0.5)]
	for i in range(4):
		var a: Vector3 = e[i]; var b: Vector3 = e[(i + 1) % 4]
		var out := ((a + b) * 0.5 * Vector3(1, 0, 1)).normalized()
		quad_out(m, a, b, b + Vector3(0, tv, 0), a + Vector3(0, tv, 0), out)
		m.eave = H
		quad_out(m, w[i], w[(i + 1) % 4], b, a, Vector3(0, -1, 0) - out * k)
		m.eave = 1000.0
	m.eave = keep_eave
	return yr + tv


## A flat roof inside a parapet: the terrace floor at H, the parapet's inner faces and coping.
## The parapet's outer faces are the facade walls carried up to H + ph. tp = parapet thickness.
## lips: per side (front, back, right, left) whether the coping overhangs the wall outward.
static func flat(m: ArchMesh, w: float, d: float, H: float, ph: float, tp: float, floor_mat: Array, wall_mat: Array, coping: Array, lips := [true, true, true, true]) -> void:
	var keep_eave := m.eave
	m.eave = 1000.0
	var hx := w * 0.5; var hz := d * 0.5
	m.layer = floor_mat[0]; m.tint = floor_mat[1]
	m.quad(Vector3(-hx + tp, H, hz - tp), Vector3(hx - tp, H, hz - tp), Vector3(hx - tp, H, -hz + tp), Vector3(-hx + tp, H, -hz + tp))
	if ph <= 0.01:
		m.eave = keep_eave
		return
	m.layer = wall_mat[0]; m.tint = wall_mat[1]
	m.ground = H - 0.4
	var top := H + ph
	m.quad(Vector3(hx - tp, H, hz - tp), Vector3(-hx + tp, H, hz - tp), Vector3(-hx + tp, top, hz - tp), Vector3(hx - tp, top, hz - tp))
	m.quad(Vector3(-hx + tp, H, -hz + tp), Vector3(hx - tp, H, -hz + tp), Vector3(hx - tp, top, -hz + tp), Vector3(-hx + tp, top, -hz + tp))
	m.quad(Vector3(-hx + tp, H, hz - tp), Vector3(-hx + tp, H, -hz + tp), Vector3(-hx + tp, top, -hz + tp), Vector3(-hx + tp, top, hz - tp))
	m.quad(Vector3(hx - tp, H, -hz + tp), Vector3(hx - tp, H, hz - tp), Vector3(hx - tp, top, hz - tp), Vector3(hx - tp, top, -hz + tp))
	m.layer = coping[0]; m.tint = coping[1]
	var lo := 0.05
	var fx0 := -hx - (lo if lips[3] else 0.0); var fx1 := hx + (lo if lips[2] else 0.0)
	var fz0 := -hz - (lo if lips[1] else 0.0); var fz1 := hz + (lo if lips[0] else 0.0)
	var ct := 0.07
	m.box(Vector3(fx0, top, fz1 - tp - lo), Vector3(fx1, top + ct, fz1), 4 | 16 | 8 | (1 if lips[2] else 0) | (2 if lips[3] else 0))
	m.box(Vector3(fx0, top, fz0), Vector3(fx1, top + ct, fz0 + tp + lo), 4 | 32 | 8 | (1 if lips[2] else 0) | (2 if lips[3] else 0))
	m.box(Vector3(fx1 - tp - lo, top, fz0 + tp + lo), Vector3(fx1, top + ct, fz1 - tp - lo), 4 | 1 | 8)
	m.box(Vector3(fx0, top, fz0 + tp + lo), Vector3(fx0 + tp + lo, top + ct, fz1 - tp - lo), 4 | 2 | 8)
	m.eave = keep_eave


## A barrel vault along local z over walls w wide, springing at H; `rise` = height at the crown.
## Its end walls (lunettes) take `wall_mat`. Returns the crown height.
static func barrel(m: ArchMesh, w: float, d: float, H: float, rise: float, shell: Array, wall_mat, seg := 8) -> float:
	var keep_eave := m.eave
	m.eave = 1000.0
	var hz := d * 0.5 + 0.12
	var hx := w * 0.5 + 0.08
	var pts := PackedVector2Array()
	for i in range(seg + 1):
		var a := PI * i / seg
		pts.append(Vector2(cos(a) * hx, H + sin(a) * rise))
	m.layer = shell[0]; m.tint = shell[1]
	for i in range(seg):
		var a := pts[i]; var b := pts[i + 1]
		quad_out(m, Vector3(a.x, a.y, hz), Vector3(b.x, b.y, hz), Vector3(b.x, b.y, -hz), Vector3(a.x, a.y, -hz), Vector3((a.x + b.x) * 0.5, (a.y + b.y) * 0.5 - H + 0.01, 0))
		# the shell's edge at both ends
		for s: float in [-1.0, 1.0]:
			var inner_a := Vector3(a.x * 0.97, H + (a.y - H) * 0.94, hz * s); var inner_b := Vector3(b.x * 0.97, H + (b.y - H) * 0.94, hz * s)
			quad_out(m, Vector3(a.x, a.y, hz * s), Vector3(b.x, b.y, hz * s), inner_b, inner_a, Vector3(0, 0, s))
	if wall_mat != null:
		m.layer = wall_mat[0]; m.tint = wall_mat[1]
		m.eave = H + rise
		for s: float in [-1.0, 1.0]:
			var z := d * 0.5 * s
			for i in range(seg):
				var a := pts[i]; var b := pts[i + 1]
				var ax := clampf(a.x, -w * 0.5, w * 0.5); var bx := clampf(b.x, -w * 0.5, w * 0.5)
				quad_out(m, Vector3(ax, H, z), Vector3(bx, H, z), Vector3(bx, H + (b.y - H) * 0.94, z), Vector3(ax, H + (a.y - H) * 0.94, z), Vector3(0, 0, s))
	m.eave = keep_eave
	return H + rise


## Height of a gable roof's top surface at local z (ridge along x) — for chimneys and dormers.
static func gable_y(D: float, H: float, k: float, t: float, z: float) -> float:
	return H + (D * 0.5 - absf(z)) * k + t * sqrt(1.0 + k * k)
