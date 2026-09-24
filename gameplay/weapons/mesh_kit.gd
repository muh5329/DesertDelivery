class_name MeshKit
extends RefCounted
## A tiny hard-surface mesh builder for the procedural weapons and camp gear: lofts through
## superellipse sections (a rounded box whose bevel is the exponent — 2 is an ellipse, 4+ a box
## with softened edges), tubes along polylines, and flat-capped ends. Smooth area-weighted
## normals, clockwise front faces (Godot's convention), one ArrayMesh surface per material.
##
##   var k := MeshKit.new()
##   k.loft(MeshKit.sections([[z, top, bottom, half_width, n], ...], 4), 24)
##   k.tube(points, radius)
##   mesh = k.commit(mesh, material)      # appends a surface

var verts := PackedVector3Array()
var norms := PackedVector3Array()
var fixed := PackedByteArray()        # 1 = normal preset (caps): not smoothed
var idx := PackedInt32Array()


func is_empty() -> bool:
	return idx.is_empty()


func _add(p: Vector3, n: Vector3 = Vector3.ZERO, is_fixed := false) -> int:
	verts.append(p)
	norms.append(n)
	fixed.append(1 if is_fixed else 0)
	return verts.size() - 1


## A triangle whose outward side faces `hint` (winding is fixed up here, so callers never
## have to think about it).
func tri(a: int, b: int, c: int, hint: Vector3) -> void:
	var n := (verts[b] - verts[a]).cross(verts[c] - verts[a])
	if n.dot(hint) < 0.0:
		var t := b; b = c; c = t
	# Godot: clockwise = front. (b-a)x(c-a) points outward, so emit a, c, b.
	idx.append(a); idx.append(c); idx.append(b)


# ------------------------------------------------------------------------------------ sections
## A superellipse ring at depth z: centre (cx, cy), half extents (hw, hh), exponent n.
static func ring(z: float, cx: float, cy: float, hw: float, hh: float, n: float, segs: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	var e := 2.0 / maxf(n, 0.5)
	for i in range(segs):
		var t := TAU * float(i) / float(segs)
		var c := cos(t); var s := sin(t)
		out.append(Vector3(cx + hw * signf(c) * pow(absf(c), e), cy + hh * signf(s) * pow(absf(s), e), z))
	return out


## Rows [z, top, bottom, half_width, exponent(, cx)] -> rings, Catmull-Rom smoothed with
## `per_span` rings between each pair of rows so the profile has no creases at the rows.
static func sections(rows: Array, per_span: int = 3, segs: int = 24) -> Array:
	var out: Array = []
	var m := rows.size()
	for i in range(m - 1):
		var steps := per_span if i < m - 2 else per_span + 1
		for s in range(steps):
			var t := float(s) / float(per_span)
			var r := _cr_row(rows, i, t)
			out.append(ring(r[0], r[5], (r[1] + r[2]) * 0.5, r[3], (r[1] - r[2]) * 0.5, r[4], segs))
	return out


static func _cr_row(rows: Array, i: int, t: float) -> Array:
	var p0: Array = rows[maxi(i - 1, 0)]; var p1: Array = rows[i]
	var p2: Array = rows[i + 1]; var p3: Array = rows[mini(i + 2, rows.size() - 1)]
	var out: Array = []
	for k in range(6):
		var a: float = p0[k] if k < p0.size() else 0.0
		var b: float = p1[k] if k < p1.size() else 0.0
		var c: float = p2[k] if k < p2.size() else 0.0
		var d: float = p3[k] if k < p3.size() else 0.0
		if k == 0:
			out.append(lerpf(b, c, t))      # z stays monotonic: plain lerp
		else:
			var t2 := t * t; var t3 := t2 * t
			out.append(0.5 * ((2.0 * b) + (-a + c) * t + (2.0 * a - 5.0 * b + 4.0 * c - d) * t2 + (-a + 3.0 * b - 3.0 * c + d) * t3))
	return out


# ------------------------------------------------------------------------------------ lofts
## Closed rings (same point count) joined in order, optional flat caps on the ends.
func loft(rings: Array, cap_a := true, cap_b := true) -> void:
	if rings.size() < 2: return
	var n: int = (rings[0] as PackedVector3Array).size()
	var base := verts.size()
	var centres: Array[Vector3] = []
	for r: PackedVector3Array in rings:
		var c := Vector3.ZERO
		for p in r:
			_add(p)
			c += p
		centres.append(c / float(n))
	for i in range(rings.size() - 1):
		for j in range(n):
			var j2 := (j + 1) % n
			var a := base + i * n + j; var b := base + i * n + j2
			var c := base + (i + 1) * n + j; var d := base + (i + 1) * n + j2
			var mid := (verts[a] + verts[d]) * 0.5
			var hint := mid - (centres[i] + centres[i + 1]) * 0.5
			tri(a, b, d, hint)
			tri(a, d, c, hint)
	if cap_a: _cap(rings[0], centres[0], centres[0] - centres[1])
	if cap_b: _cap(rings[rings.size() - 1], centres[centres.size() - 1], centres[centres.size() - 1] - centres[centres.size() - 2])


func _cap(r: PackedVector3Array, centre: Vector3, outward: Vector3) -> void:
	var nrm := outward.normalized()
	var c := _add(centre, nrm, true)
	var first := verts.size()
	for p in r: _add(p, nrm, true)
	for j in range(r.size()):
		tri(c, first + j, first + (j + 1) % r.size(), nrm)


## A tube along a polyline. `radius` may be a float or an Array of per-point radii; `aspect`
## squashes the profile (x across the path's side axis, y along its bend normal) for straps
## and flat springs. Parallel-transport frames, so it never twists.
func tube(path: PackedVector3Array, radius: Variant, segs: int = 10, aspect: Vector2 = Vector2.ONE, cap_a := true, cap_b := true, up_hint: Vector3 = Vector3.UP) -> void:
	var m := path.size()
	if m < 2: return
	var rings: Array = []
	var tangent := (path[1] - path[0]).normalized()
	var side := tangent.cross(up_hint)
	if side.length_squared() < 1e-6: side = tangent.cross(Vector3.RIGHT)
	side = side.normalized()
	for i in range(m):
		var t_new: Vector3
		if i == 0: t_new = (path[1] - path[0]).normalized()
		elif i == m - 1: t_new = (path[m - 1] - path[m - 2]).normalized()
		else: t_new = ((path[i + 1] - path[i]).normalized() + (path[i] - path[i - 1]).normalized()).normalized()
		# transport the side vector onto the new tangent
		side = (side - t_new * side.dot(t_new)).normalized()
		var up := t_new.cross(side).normalized()
		var r: float = float(radius[i]) if radius is Array else float(radius)
		var ring_pts := PackedVector3Array()
		for s in range(segs):
			var a := TAU * float(s) / float(segs)
			ring_pts.append(path[i] + side * (cos(a) * r * aspect.x) + up * (sin(a) * r * aspect.y))
		rings.append(ring_pts)
	loft(rings, cap_a, cap_b)


## A ring (torus) of `radius` round `centre` in the plane with normal `axis`.
func hoop(centre: Vector3, axis: Vector3, radius: float, thickness: float, segs: int = 16, tube_segs: int = 6) -> void:
	var a := axis.normalized()
	var u := a.cross(Vector3.UP if absf(a.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT).normalized()
	var v := a.cross(u)
	var pts := PackedVector3Array()
	for i in range(segs + 1):
		var t := TAU * float(i) / float(segs)
		pts.append(centre + (u * cos(t) + v * sin(t)) * radius)
	tube(pts, thickness, tube_segs, Vector2.ONE, false, false, a)


## An axis-aligned rounded box (a two-row loft), for small blocks: sights, lugs, keepers.
func block(centre: Vector3, size: Vector3, n: float = 5.0, segs: int = 16) -> void:
	var h := size * 0.5
	loft([ring(centre.z + h.z, centre.x, centre.y, h.x, h.y, n, segs), ring(centre.z - h.z, centre.x, centre.y, h.x, h.y, n, segs)])


## A cylinder along `axis` (unit X, Y or Z) — knobs, screws, pins.
func cyl(centre: Vector3, axis: Vector3, radius: float, length: float, segs: int = 14) -> void:
	var half := axis.normalized() * length * 0.5
	tube(PackedVector3Array([centre - half, centre + half]), radius, segs, Vector2.ONE, true, true,
		Vector3.RIGHT if absf(axis.normalized().dot(Vector3.UP)) > 0.9 else Vector3.UP)


# ------------------------------------------------------------------------------------ output
func commit(mesh: ArrayMesh, material: Material) -> ArrayMesh:
	if mesh == null: mesh = ArrayMesh.new()
	if idx.is_empty(): return mesh
	var acc := PackedVector3Array(); acc.resize(verts.size())
	for t in range(0, idx.size(), 3):
		var a := idx[t]; var c := idx[t + 1]; var b := idx[t + 2]   # stored a, c, b
		var fn := (verts[b] - verts[a]).cross(verts[c] - verts[a])
		for v in [a, b, c]:
			if fixed[v] == 0: acc[v] += fn
	var out := PackedVector3Array(); out.resize(verts.size())
	for i in range(verts.size()):
		out[i] = norms[i] if fixed[i] == 1 else (acc[i].normalized() if acc[i].length_squared() > 1e-14 else Vector3.UP)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = out
	arr[Mesh.ARRAY_INDEX] = idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.surface_set_material(mesh.get_surface_count() - 1, material)
	return mesh
