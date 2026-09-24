class_name ArchMesh
extends RefCounted
## Packed-array mesh builder for the architecture kit (indexed triangles, one surface). Geometry is
## written in a building's local frame (x along the frontage, y up from the pad, +z = the street
## side) and transformed by `xf` as it is appended, so a whole group of buildings is one mesh.
## Every vertex carries the attributes arch.gdshader reads:
##   UV   metres, planar per face (walls: u to the viewer's right, v = -height), + `uv_off`
##   UV2  (layer + weather, height above `ground`)           or, for modules, (layer, `flag`)
##   COLOR tint rgb, alpha = (eave - y) / 32                  or, for modules, alpha 1
## `lod = true` keeps only positions, normals and colours (the far silhouettes).
## Winding: quad(a, b, c, d) takes the corners counter-clockwise as seen from outside.

var v := PackedVector3Array()
var nrm := PackedVector3Array()
var uv := PackedVector2Array()
var uv2 := PackedVector2Array()
var col := PackedColorArray()
var cus := PackedFloat32Array()      # modules: CUSTOM0 = the part's own colour (vertex COLOR stays white)
var idx := PackedInt32Array()

var xf := Transform3D.IDENTITY
var layer := 0.0
var tint := Color.WHITE
var ground := 0.0
var eave := 1000.0
var uv_off := Vector2.ZERO
var module := false
var flag := 0.0
var lod := false


func size() -> int:
	return v.size()


func _emit(p: Vector3, n: Vector3, t: Vector2) -> void:
	v.append(xf * p)
	nrm.append(xf.basis * n)
	if lod:
		col.append(tint)
		return
	uv.append(t + uv_off)
	if module:
		uv2.append(Vector2(layer, flag))
		col.append(Color.WHITE)
		cus.append(tint.r); cus.append(tint.g); cus.append(tint.b); cus.append(1.0)
	else:
		uv2.append(Vector2(layer, p.y - ground))
		col.append(Color(tint.r, tint.g, tint.b, clampf((eave - p.y) * 0.03125, 0.0, 1.0)))


func _module4() -> void:
	var t2 := Vector2(layer, flag)
	uv2.append(t2); uv2.append(t2); uv2.append(t2); uv2.append(t2)
	col.append(Color.WHITE); col.append(Color.WHITE); col.append(Color.WHITE); col.append(Color.WHITE)
	for i in range(4):
		cus.append(tint.r); cus.append(tint.g); cus.append(tint.b); cus.append(1.0)


## Planar UV axes for a face normal: u to the viewer's right, v up the face.
static func axes(n: Vector3) -> Array:
	if absf(n.y) > 0.985:
		return [Vector3(1, 0, 0), Vector3(0, 0, -1) if n.y > 0.0 else Vector3(0, 0, 1)]
	var ua := Vector3.UP.cross(n).normalized()
	return [ua, n.cross(ua)]


func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var n := (b - a).cross(d - a)
	if n.length_squared() < 1e-14: n = (c - b).cross(a - b)
	n = n.normalized()
	var ua: Vector3; var va: Vector3
	if absf(n.y) > 0.985:
		ua = Vector3(1, 0, 0); va = Vector3(0, 0, -1) if n.y > 0.0 else Vector3(0, 0, 1)
	else:
		ua = Vector3.UP.cross(n).normalized(); va = n.cross(ua)
	_push4(a, b, c, d, xf.basis * n,
		Vector2(a.dot(ua), -a.dot(va)), Vector2(b.dot(ua), -b.dot(va)), Vector2(c.dot(ua), -c.dot(va)), Vector2(d.dot(ua), -d.dot(va)))


## The four corners of a flat quad (one normal), inlined for speed: builds are budgeted.
func _push4(a: Vector3, b: Vector3, c: Vector3, d: Vector3, wn: Vector3, ta: Vector2, tb: Vector2, tc: Vector2, td: Vector2) -> void:
	var base := v.size()
	v.append(xf * a); v.append(xf * b); v.append(xf * c); v.append(xf * d)
	nrm.append(wn); nrm.append(wn); nrm.append(wn); nrm.append(wn)
	idx.append(base); idx.append(base + 2); idx.append(base + 1)
	idx.append(base); idx.append(base + 3); idx.append(base + 2)
	if lod:
		col.append(tint); col.append(tint); col.append(tint); col.append(tint)
		return
	uv.append(ta + uv_off); uv.append(tb + uv_off); uv.append(tc + uv_off); uv.append(td + uv_off)
	if module:
		_module4()
		return
	uv2.append(Vector2(layer, a.y - ground)); uv2.append(Vector2(layer, b.y - ground))
	uv2.append(Vector2(layer, c.y - ground)); uv2.append(Vector2(layer, d.y - ground))
	var r := tint.r; var g := tint.g; var bl := tint.b
	col.append(Color(r, g, bl, clampf((eave - a.y) * 0.03125, 0.0, 1.0)))
	col.append(Color(r, g, bl, clampf((eave - b.y) * 0.03125, 0.0, 1.0)))
	col.append(Color(r, g, bl, clampf((eave - c.y) * 0.03125, 0.0, 1.0)))
	col.append(Color(r, g, bl, clampf((eave - d.y) * 0.03125, 0.0, 1.0)))


## A wall rectangle facing +z at depth z of the current frame (face space), inlined: walls are
## most of a building's quads.
func rect_z(x0: float, y0: float, x1: float, y1: float, z: float = 0.0) -> void:
	var base := v.size()
	v.append(xf * Vector3(x0, y0, z)); v.append(xf * Vector3(x1, y0, z)); v.append(xf * Vector3(x1, y1, z)); v.append(xf * Vector3(x0, y1, z))
	var wn := xf.basis.z
	nrm.append(wn); nrm.append(wn); nrm.append(wn); nrm.append(wn)
	idx.append(base); idx.append(base + 2); idx.append(base + 1)
	idx.append(base); idx.append(base + 3); idx.append(base + 2)
	if lod:
		col.append(tint); col.append(tint); col.append(tint); col.append(tint)
		return
	uv.append(Vector2(x0, -y0) + uv_off); uv.append(Vector2(x1, -y0) + uv_off); uv.append(Vector2(x1, -y1) + uv_off); uv.append(Vector2(x0, -y1) + uv_off)
	if module:
		_module4()
		return
	var g0 := Vector2(layer, y0 - ground); var g1 := Vector2(layer, y1 - ground)
	uv2.append(g0); uv2.append(g0); uv2.append(g1); uv2.append(g1)
	var c0 := Color(tint.r, tint.g, tint.b, clampf((eave - y0) * 0.03125, 0.0, 1.0))
	var c1 := Color(tint.r, tint.g, tint.b, clampf((eave - y1) * 0.03125, 0.0, 1.0))
	col.append(c0); col.append(c0); col.append(c1); col.append(c1)


## A quad with explicit UVs (roof ridges, rotated textures, door leaves).
func quad_uv(a: Vector3, b: Vector3, c: Vector3, d: Vector3, ta: Vector2, tb: Vector2, tc: Vector2, td: Vector2) -> void:
	var n := (b - a).cross(d - a)
	if n.length_squared() < 1e-14: n = (c - b).cross(a - b)
	_push4(a, b, c, d, xf.basis * n.normalized(), ta, tb, tc, td)


## A quad with per-corner normals (curved surfaces) and explicit UVs.
func quad_n(a: Vector3, b: Vector3, c: Vector3, d: Vector3, na: Vector3, nb: Vector3, nc: Vector3, nd: Vector3, ta: Vector2, tb: Vector2, tc: Vector2, td: Vector2) -> void:
	var base := v.size()
	_emit(a, na, ta); _emit(b, nb, tb); _emit(c, nc, tc); _emit(d, nd, td)
	idx.append(base); idx.append(base + 2); idx.append(base + 1)
	idx.append(base); idx.append(base + 3); idx.append(base + 2)


## Triangle, counter-clockwise from outside, planar UVs.
func tri(a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := (b - a).cross(c - a).normalized()
	var ax := axes(n)
	var ua: Vector3 = ax[0]; var va: Vector3 = ax[1]
	var base := v.size()
	_emit(a, n, Vector2(a.dot(ua), -a.dot(va)))
	_emit(b, n, Vector2(b.dot(ua), -b.dot(va)))
	_emit(c, n, Vector2(c.dot(ua), -c.dot(va)))
	idx.append(base); idx.append(base + 2); idx.append(base + 1)


## Axis-aligned box from lo to hi (local). mask bits: 1 +x, 2 -x, 4 +y, 8 -y, 16 +z, 32 -z.
func box(lo: Vector3, hi: Vector3, mask: int = 63) -> void:
	var b := xf.basis
	var p0 := Vector3(lo.x, lo.y, lo.z); var p1 := Vector3(hi.x, lo.y, lo.z); var p2 := Vector3(hi.x, hi.y, lo.z); var p3 := Vector3(lo.x, hi.y, lo.z)
	var p4 := Vector3(lo.x, lo.y, hi.z); var p5 := Vector3(hi.x, lo.y, hi.z); var p6 := Vector3(hi.x, hi.y, hi.z); var p7 := Vector3(lo.x, hi.y, hi.z)
	if mask & 16: _push4(p4, p5, p6, p7, b * Vector3(0, 0, 1), Vector2(lo.x, -lo.y), Vector2(hi.x, -lo.y), Vector2(hi.x, -hi.y), Vector2(lo.x, -hi.y))
	if mask & 32: _push4(p1, p0, p3, p2, b * Vector3(0, 0, -1), Vector2(-hi.x, -lo.y), Vector2(-lo.x, -lo.y), Vector2(-lo.x, -hi.y), Vector2(-hi.x, -hi.y))
	if mask & 1: _push4(p5, p1, p2, p6, b * Vector3(1, 0, 0), Vector2(-hi.z, -lo.y), Vector2(-lo.z, -lo.y), Vector2(-lo.z, -hi.y), Vector2(-hi.z, -hi.y))
	if mask & 2: _push4(p0, p4, p7, p3, b * Vector3(-1, 0, 0), Vector2(lo.z, -lo.y), Vector2(hi.z, -lo.y), Vector2(hi.z, -hi.y), Vector2(lo.z, -hi.y))
	if mask & 4: _push4(p7, p6, p2, p3, b * Vector3(0, 1, 0), Vector2(lo.x, hi.z), Vector2(hi.x, hi.z), Vector2(hi.x, lo.z), Vector2(lo.x, lo.z))
	if mask & 8: _push4(p0, p1, p5, p4, b * Vector3(0, -1, 0), Vector2(lo.x, -lo.z), Vector2(hi.x, -lo.z), Vector2(hi.x, -hi.z), Vector2(lo.x, -hi.z))


## Box centred at c with size s.
func cbox(c: Vector3, s: Vector3, mask: int = 63) -> void:
	box(c - s * 0.5, c + s * 0.5, mask)


## A box whose local frame is rotated by `b` about its centre c (beams, sails, rafters).
func rbox(c: Vector3, s: Vector3, b: Basis, mask: int = 63) -> void:
	var keep := xf
	xf = xf * Transform3D(b, c)
	box(-s * 0.5, s * 0.5, mask)
	xf = keep


## Vertical cylinder (or cone frustum) from y0 to y1 at c (x, z), smooth sides, optional caps.
func cylinder(c: Vector3, r0: float, r1: float, h: float, seg: int = 12, top: bool = true, bottom: bool = false) -> void:
	var circ := TAU * maxf(r0, r1)
	var slope := (r0 - r1) / maxf(h, 0.001)
	for i in range(seg):
		var a0 := TAU * i / seg; var a1 := TAU * (i + 1) / seg
		var d0 := Vector3(sin(a0), 0, cos(a0)); var d1 := Vector3(sin(a1), 0, cos(a1))
		var n0 := Vector3(d0.x, slope, d0.z).normalized(); var n1 := Vector3(d1.x, slope, d1.z).normalized()
		var u0 := circ * i / seg; var u1 := circ * (i + 1) / seg
		quad_n(c + d0 * r0, c + d1 * r0, c + d1 * r1 + Vector3(0, h, 0), c + d0 * r1 + Vector3(0, h, 0),
			n0, n1, n1, n0, Vector2(u0, -c.y), Vector2(u1, -c.y), Vector2(u1, -c.y - h), Vector2(u0, -c.y - h))
	if top and r1 > 0.001:
		var t := c + Vector3(0, h, 0)
		for i in range(seg):
			var a0 := TAU * i / seg; var a1 := TAU * (i + 1) / seg
			tri(t, t + Vector3(sin(a0), 0, cos(a0)) * r1, t + Vector3(sin(a1), 0, cos(a1)) * r1)
	if bottom and r0 > 0.001:
		for i in range(seg):
			var a0 := TAU * i / seg; var a1 := TAU * (i + 1) / seg
			tri(c, c + Vector3(sin(a1), 0, cos(a1)) * r0, c + Vector3(sin(a0), 0, cos(a0)) * r0)


## Hemisphere-ish dome on a circle of radius r at c; `rise` = height / r (1 = half sphere,
## > 1 onion-ish pointed, < 1 flat saucer). Smooth normals, UVs in metres round and up.
func dome(c: Vector3, r: float, rise: float = 1.0, seg: int = 12, rings: int = 5) -> void:
	var circ := TAU * r
	for j in range(rings):
		var t0 := PI * 0.5 * j / rings; var t1 := PI * 0.5 * (j + 1) / rings
		var r0 := cos(t0) * r; var r1 := cos(t1) * r
		var y0 := sin(t0) * r * rise; var y1 := sin(t1) * r * rise
		for i in range(seg):
			var a0 := TAU * i / seg; var a1 := TAU * (i + 1) / seg
			var d0 := Vector3(sin(a0), 0, cos(a0)); var d1 := Vector3(sin(a1), 0, cos(a1))
			var p00 := c + d0 * r0 + Vector3(0, y0, 0); var p10 := c + d1 * r0 + Vector3(0, y0, 0)
			var p11 := c + d1 * r1 + Vector3(0, y1, 0); var p01 := c + d0 * r1 + Vector3(0, y1, 0)
			var n00 := (d0 * cos(t0) + Vector3(0, sin(t0) / maxf(rise, 0.2), 0)).normalized()
			var n10 := (d1 * cos(t0) + Vector3(0, sin(t0) / maxf(rise, 0.2), 0)).normalized()
			var n11 := (d1 * cos(t1) + Vector3(0, sin(t1) / maxf(rise, 0.2), 0)).normalized()
			var n01 := (d0 * cos(t1) + Vector3(0, sin(t1) / maxf(rise, 0.2), 0)).normalized()
			var s0 := -r * rise * t0; var s1 := -r * rise * t1
			quad_n(p00, p10, p11, p01, n00, n10, n11, n01,
				Vector2(circ * i / seg, s0), Vector2(circ * (i + 1) / seg, s0), Vector2(circ * (i + 1) / seg, s1), Vector2(circ * i / seg, s1))


func arrays() -> Array:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_COLOR] = col
	if not lod:
		arr[Mesh.ARRAY_TEX_UV] = uv
		arr[Mesh.ARRAY_TEX_UV2] = uv2
	if module:
		arr[Mesh.ARRAY_CUSTOM0] = cus
	arr[Mesh.ARRAY_INDEX] = idx
	return arr


## Append this builder's triangles as a new surface of `mesh` (created if null).
func commit(mesh: ArrayMesh = null, mat: Material = null) -> ArrayMesh:
	if mesh == null: mesh = ArrayMesh.new()
	if v.is_empty(): return mesh
	var flags := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) if module else 0
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays(), [], {}, flags)
	if mat: mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
	return mesh
