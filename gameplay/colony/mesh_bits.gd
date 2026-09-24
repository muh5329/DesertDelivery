class_name MeshBits
extends RefCounted
## Vertex-coloured primitives appended to a SurfaceTool (TRIANGLES), so a ship or a building
## yard is one mesh and one draw call. Faces wind for Godot's default back-face culling.


static func quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	st.set_color(col)
	for p in [a, b, c, a, c, d]: st.add_vertex(p)


static func tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	st.set_color(col)
	for p in [a, b, c]: st.add_vertex(p)


static func box(st: SurfaceTool, xf: Transform3D, size: Vector3, col: Color) -> void:
	var h := size * 0.5
	var c := [Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
		Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]
	for f in [[0, 3, 2, 1], [4, 5, 6, 7], [0, 4, 7, 3], [1, 2, 6, 5], [3, 7, 6, 2], [0, 1, 5, 4]]:
		quad(st, xf * c[f[0]], xf * c[f[1]], xf * c[f[2]], xf * c[f[3]], col)


## A box standing on y = 0 at (x, z), turned by yaw.
static func block(st: SurfaceTool, x: float, z: float, size: Vector3, col: Color, yaw := 0.0, y := 0.0) -> void:
	box(st, Transform3D(Basis(Vector3.UP, yaw), Vector3(x, y + size.y * 0.5, z)), size, col)


static func cyl(st: SurfaceTool, xf: Transform3D, r: float, h: float, col: Color, seg := 8, r_top := -1.0) -> void:
	var rt := r if r_top < 0.0 else r_top
	for i in range(seg):
		var a0 := TAU * i / seg; var a1 := TAU * (i + 1) / seg
		var p0 := Vector3(cos(a0) * r, -h * 0.5, sin(a0) * r); var p1 := Vector3(cos(a1) * r, -h * 0.5, sin(a1) * r)
		var q0 := Vector3(cos(a0) * rt, h * 0.5, sin(a0) * rt); var q1 := Vector3(cos(a1) * rt, h * 0.5, sin(a1) * rt)
		quad(st, xf * p0, xf * q0, xf * q1, xf * p1, col)
		if rt > 0.0: tri(st, xf * Vector3(0, h * 0.5, 0), xf * q1, xf * q0, col)


## An upright cylinder standing on y = 0.
static func post(st: SurfaceTool, x: float, z: float, r: float, h: float, col: Color, seg := 6, y := 0.0) -> void:
	cyl(st, Transform3D(Basis(), Vector3(x, y + h * 0.5, z)), r, h, col, seg)


## A round beam from a to b.
static func spar(st: SurfaceTool, a: Vector3, b: Vector3, r: float, col: Color, seg := 6) -> void:
	var dir := b - a
	var y := dir.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	cyl(st, Transform3D(Basis(x, y, z), (a + b) * 0.5), r, dir.length(), col, seg)


static func cone(st: SurfaceTool, at: Vector3, r: float, h: float, col: Color, seg := 8) -> void:
	for i in range(seg):
		var a0 := TAU * i / seg; var a1 := TAU * (i + 1) / seg
		tri(st, at + Vector3(cos(a0) * r, 0, sin(a0) * r), at + Vector3(0, h, 0), at + Vector3(cos(a1) * r, 0, sin(a1) * r), col)


## A low-poly ball (a squashed octahedron sphere): tree crowns, sacks, shrubs.
static func blob(st: SurfaceTool, at: Vector3, r: Vector3, col: Color, rings := 4, seg := 7) -> void:
	for i in range(rings):
		var v0 := PI * i / rings; var v1 := PI * (i + 1) / rings
		for j in range(seg):
			var u0 := TAU * j / seg; var u1 := TAU * (j + 1) / seg
			var p := func(u: float, v: float) -> Vector3: return at + Vector3(sin(v) * cos(u) * r.x, cos(v) * r.y, sin(v) * sin(u) * r.z)
			var shade := col.darkened(0.12 * float(i) / rings)
			quad(st, p.call(u0, v0), p.call(u1, v0), p.call(u1, v1), p.call(u0, v1), shade)
