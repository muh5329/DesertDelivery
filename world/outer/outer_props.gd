class_name OuterProps
extends RefCounted
## The outer towns' dressing (plan.json town `props` and `terraces`, placed by
## world/mapgen/outer_props.py): fountains, plaza trees in planters, benches, lamps, market stalls,
## cafe tables, carts, barrels, crates, pots, washing lines, bollards, boats, jetties, cranes, net
## racks, gardens, hay; and Valdoro's dry-stone terrace walls. Filed per 60 m chunk as WorldDatabase
## recipes; a chunk's props become one ArchCtx group (a merged mesh for the one-off pieces, one
## MultiMesh per repeated prop, one body of box colliders), the trees go through the wilderness'
## tree models and the boats get their own MultiMesh with the bobbing material.
##
## Record: [kind, x, y, z, yaw_deg, variant]. Paint (awnings, parasols, hulls) comes from the town's
## palette, picked from the prop's position, so nothing is stored for it.

const PAINT := {
	"puerto": [Color(0.72, 0.18, 0.16), Color(0.15, 0.32, 0.55), Color(0.95, 0.92, 0.84), Color(0.2, 0.45, 0.3), Color(0.9, 0.7, 0.2)],
	"campo": [Color(0.78, 0.35, 0.2), Color(0.35, 0.45, 0.25), Color(0.92, 0.85, 0.7), Color(0.6, 0.2, 0.18)],
	"sarmada": [Color(0.2, 0.42, 0.72), Color(0.92, 0.9, 0.84), Color(0.78, 0.3, 0.18), Color(0.95, 0.75, 0.25), Color(0.25, 0.55, 0.5)],
	"valdoro": [Color(0.55, 0.18, 0.15), Color(0.25, 0.35, 0.25), Color(0.85, 0.8, 0.7)],
	"isola": [Color(0.2, 0.55, 0.75), Color(0.95, 0.85, 0.3), Color(0.85, 0.35, 0.3), Color(0.35, 0.65, 0.45), Color(0.95, 0.95, 0.92), Color(0.9, 0.55, 0.65)],
}
const BOATS := ["boat_fishing", "boat_small", "dinghy"]
const NO_COLLIDE := ["washing", "tree", "lamp_plaza", "garden", "jetty"]

var outer: OuterWorld
var db: WorldDatabase
var kit: WorldKit
var count := 0
var recipes := 0
var terrace_km := 0.0
var _bob_mat: ShaderMaterial
var _wall_mat: ShaderMaterial


func setup(p_outer: OuterWorld, p_db: WorldDatabase, p_kit: WorldKit) -> void:
	outer = p_outer; db = p_db; kit = p_kit
	for group in ["towns", "hamlets"]:
		for t: Dictionary in outer.ground.plan.get(group, []):
			_define(t)


func _define(t: Dictionary) -> void:
	var style: String = t.get("style", "campo")
	var per_chunk: Dictionary = {}
	for rec in t.get("props", []):
		var c := db.chunk_of(float(rec[1]), float(rec[3]))
		if not per_chunk.has(c): per_chunk[c] = []
		per_chunk[c].append(rec)
		count += 1
	for c: Vector2i in per_chunk:
		var group: Array = per_chunk[c]
		var o := db.chunk_origin(c) + Vector3(db.chunk_size * 0.5, 0, db.chunk_size * 0.5)
		var reach := 50.0
		for rec in group:
			if String(rec[0]).begins_with("crane") or rec[0] == "jetty": reach = 70.0
		db.add(o.x, o.z, func(): _build(kit.sink, group, style), reach)
		recipes += 1
	# quay walls along the water side of every quay (<= 48 m pieces)
	for edge in t.get("quay_edges", []):
		var pts := PackedVector2Array()
		for q in edge: pts.append(Vector2(q[0], q[1]))
		pts = _resample(pts, 4.0)
		var k0 := 0
		while k0 < pts.size() - 1:
			var k1 := mini(k0 + 12, pts.size() - 1)
			var piece := pts.slice(k0, k1 + 1)
			var mid := piece[piece.size() / 2]
			db.add(mid.x, mid.y, func(): _build_quay(kit.sink, piece), 50.0)
			recipes += 1
			k0 = k1
	# terrace walls: runs cut into <= 60 m pieces, filed where each piece starts
	for run in t.get("terraces", []):
		var pts := PackedVector2Array()
		for q in run: pts.append(Vector2(q[0], q[1]))
		var k0 := 0
		while k0 < pts.size() - 1:
			var k1 := mini(k0 + 10, pts.size() - 1)
			var piece := pts.slice(k0, k1 + 1)
			var mid := piece[piece.size() / 2]
			for k in range(1, piece.size()): terrace_km += piece[k].distance_to(piece[k - 1]) / 1000.0
			db.add(mid.x, mid.y, func(): _build_wall(kit.sink, piece), 40.0)
			recipes += 1
			k0 = k1


func _paint(style: String, x: float, z: float, salt: int) -> Color:
	var pal: Array = PAINT.get(style, PAINT.campo)
	var hsh := absi(int(x * 7.13) * 73856093 ^ int(z * 3.71) * 19349663 ^ salt * 83492791)
	return pal[hsh % pal.size()]


func _build(parent: Node3D, group: Array, style: String) -> void:
	if parent == null: return
	var origin := parent.global_position if parent.is_inside_tree() else Vector3.ZERO
	var c := ArchCtx.new()
	c.far = 260.0
	var trees: Dictionary = {}           # species -> [xforms, colours]
	var boats: Dictionary = {}           # key -> [xforms, paints]
	for rec in group:
		var kind: String = rec[0]
		var pos := Vector3(float(rec[1]), float(rec[2]), float(rec[3])) - origin
		var yaw := deg_to_rad(float(rec[4]))
		var variant: int = int(rec[5])
		if kind.begins_with("tree:"):
			var sp := kind.substr(5)
			if not trees.has(sp): trees[sp] = [[] as Array[Transform3D], [] as Array[Color]]
			var s := 0.85 + 0.1 * float(absi(int(pos.x * 13.0)) % 5)
			trees[sp][0].append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s)), pos + Vector3(0, 0.5, 0)))
			trees[sp][1].append(Color(1, 1, 1))
			continue
		var key := ArchProps.key_for(kind, variant)
		if key == "": continue
		var paint := _paint(style, float(rec[1]), float(rec[3]), variant)
		if kind in BOATS:
			if not boats.has(key): boats[key] = [[], PackedColorArray()]
			boats[key][0].append(Transform3D(Basis(Vector3.UP, yaw), Vector3(pos.x, -origin.y + (0.35 if kind == "boat_fishing" else 0.22), pos.z)
				if float(rec[2]) < 0.5 else pos))
			boats[key][1].append(Color(paint.r, paint.g, paint.b, 0.0))
			continue
		c.begin(Transform3D(Basis(Vector3.UP, yaw), pos), variant + 1)
		c.place(key, Transform3D.IDENTITY, Color(paint.r, paint.g, paint.b, 0.0))
		if kind == "jetty":
			c.box_shape(Vector3(-1.6, 2.2 - float(rec[2]), -float(variant)), Vector3(1.6, 2.45 - float(rec[2]), 0.5))
		elif not kind in NO_COLLIDE:
			var fp := ArchProps.footprint(kind)
			if fp.y > 0.0: c.box_shape_c(Vector3(0, fp.y * 0.5, 0), Vector3(fp.x * 2.0, fp.y, fp.z * 2.0))
	c.bake_modules(1)
	c.finish(parent, "Props")
	for sp in trees:
		if outer.flora and outer.flora.species.has(sp):
			var set: Dictionary = outer.flora.species[sp]
			outer.flora._emit(parent, set.full[0], trees[sp][0], trees[sp][1], 0.0, 420.0, true)
	for key in boats: _boats(parent, key, boats[key])


## Boats float: their own MultiMesh with the kit's material plus a slow heave, pitch and roll
## (arch.gdshader `bob`), phased by position so a harbour never rocks in step.
func _boats(parent: Node3D, key: String, e: Array) -> void:
	if _bob_mat == null:
		_bob_mat = ArchMaterials.instanced().duplicate()
		_bob_mat.set_shader_parameter("bob", 1.0)
	var xfs: Array = e[0]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true; mm.use_custom_data = true
	mm.mesh = ArchModules.mesh(key)
	mm.instance_count = xfs.size()
	for i in range(xfs.size()):
		mm.set_instance_transform(i, xfs[i])
		mm.set_instance_custom_data(i, e[1][i])
		mm.set_instance_color(i, Color(1, 1, 1, 0))
	var mmi := MultiMeshInstance3D.new(); mmi.name = "Boats"
	mmi.multimesh = mm; mmi.material_override = _bob_mat
	mmi.visibility_range_end = 900.0
	parent.add_child(mmi)


static func _resample(pts: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if pts.size() < 2: return pts
	out.append(pts[0])
	var carry := 0.0
	for k in range(pts.size() - 1):
		var a := pts[k]; var b := pts[k + 1]
		var L := a.distance_to(b)
		var s := step - carry
		while s <= L:
			out.append(a.lerp(b, s / L)); s += step
		carry = L - (s - step)
	if out[out.size() - 1].distance_to(pts[pts.size() - 1]) > step * 0.3: out.append(pts[pts.size() - 1])
	return out


## A stone quay wall: from the quay edge the wall stands where the ground meets the water, its
## ashlar face down to the dredged bed, a coping course on top, and a paved deck back to the edge
## so the quay is flat to its lip (walkable, collided).
func _build_quay(parent: Node3D, pts: PackedVector2Array) -> void:
	if parent == null or pts.size() < 2: return
	var origin := parent.global_position if parent.is_inside_tree() else Vector3.ZERO
	var n := pts.size()
	var sea: Array[Vector2] = []; var reach := PackedFloat32Array(); var top := PackedFloat32Array()
	for k in range(n):
		var a := pts[maxi(k - 1, 0)]; var b := pts[mini(k + 1, n - 1)]
		var d := (b - a).normalized(); var nn := Vector2(-d.y, d.x)
		if outer.height_at(pts[k].x + nn.x * 8.0, pts[k].y + nn.y * 8.0) > outer.height_at(pts[k].x - nn.x * 8.0, pts[k].y - nn.y * 8.0): nn = -nn
		sea.append(nn)
		var r := 0.5
		while r < 14.0 and outer.height_at(pts[k].x + nn.x * r, pts[k].y + nn.y * r) > -0.4: r += 0.5
		reach.append(r)
		top.append(maxf(outer.height_at(pts[k].x - nn.x * 1.5, pts[k].y - nn.y * 1.5), 1.6) + 0.05)
	# smooth the wall line so it does not zig-zag with the lattice
	var rs := reach.duplicate()
	for k in range(n):
		var acc := 0.0; var w := 0.0
		for q in range(maxi(k - 2, 0), mini(k + 3, n)): acc += reach[q]; w += 1.0
		rs[k] = maxf(acc / w, reach[k] * 0.8)
	var m := ArchMesh.new()
	var faces := PackedVector3Array()
	var cope := ArchMesh.new()
	for k in range(n - 1):
		var p0 := pts[k] + sea[k] * rs[k]; var p1 := pts[k + 1] + sea[k + 1] * rs[k + 1]
		var i0 := pts[k] - sea[k] * 0.6; var i1 := pts[k + 1] - sea[k + 1] * 0.6
		var y0 := top[k]; var y1 := top[k + 1]
		var F0 := Vector3(p0.x, y0, p0.y) - origin; var F1 := Vector3(p1.x, y1, p1.y) - origin
		var B0 := Vector3(p0.x, -3.6, p0.y) - origin; var B1 := Vector3(p1.x, -3.6, p1.y) - origin
		var D0 := Vector3(i0.x, y0, i0.y) - origin; var D1 := Vector3(i1.x, y1, i1.y) - origin
		m.layer = float(ArchMaterials.ASHLAR) + 0.45; m.tint = Color(0.84, 0.8, 0.72)
		m.ground = -3.6 - origin.y; m.eave = y0 - origin.y + 4.0
		m.quad(B0, B1, F1, F0); m.quad(B1, B0, F0, F1)
		m.layer = float(ArchMaterials.STONE) + 0.2; m.tint = Color(0.9, 0.87, 0.8)
		m.quad(D0, D1, F1, F0); m.quad(D1, D0, F0, F1)
		# the coping: a proud course along the lip
		var up := Vector3(0, 0.22, 0)
		var s0 := Vector3(sea[k].x, 0, sea[k].y) * 0.25; var s1 := Vector3(sea[k + 1].x, 0, sea[k + 1].y) * 0.25
		cope.layer = float(ArchMaterials.STONE); cope.tint = Color(0.95, 0.93, 0.88)
		cope.ground = -10.0; cope.eave = 100.0
		cope.quad(F0 + s0 - up * 0.5, F1 + s1 - up * 0.5, F1 + s1 + up, F0 + s0 + up)
		cope.quad(F0 + s0 + up, F1 + s1 + up, F1 - s1 * 3.0 + up, F0 - s0 * 3.0 + up)
		faces.append_array(PackedVector3Array([B0, B1, F1, B0, F1, F0, D0, D1, F1, D0, F1, F0]))
	var mi := MeshInstance3D.new(); mi.name = "QuayWall"
	var mesh := m.commit(null, ArchMaterials.merged())
	cope.commit(mesh, ArchMaterials.merged())
	mi.mesh = mesh
	mi.visibility_range_end = 1400.0
	parent.add_child(mi)
	var body := StaticBody3D.new(); body.collision_layer = 1
	var shape := ConcavePolygonShape3D.new(); shape.backface_collision = true; shape.set_faces(faces)
	var cs := CollisionShape3D.new(); cs.shape = shape; body.add_child(cs); parent.add_child(body)


## A dry-stone terrace wall along a contour: its face stands on the downhill side, its top a
## little above the uphill ground, capped with flat stones; collided.
func _build_wall(parent: Node3D, pts: PackedVector2Array) -> void:
	if parent == null or pts.size() < 2: return
	var origin := parent.global_position if parent.is_inside_tree() else Vector3.ZERO
	var m := ArchMesh.new()
	m.layer = float(ArchMaterials.RUBBLE) + 0.3
	m.tint = Color(0.86, 0.83, 0.78)
	var faces := PackedVector3Array()
	for k in range(pts.size() - 1):
		var a := pts[k]; var b := pts[k + 1]
		var d := (b - a).normalized(); var n := Vector2(-d.y, d.x)
		# which side is downhill?
		var ga := outer.height_at(a.x + n.x * 2.0, a.y + n.y * 2.0); var gb := outer.height_at(a.x - n.x * 2.0, a.y - n.y * 2.0)
		if ga > gb: n = -n
		var ta := outer.height_at(a.x, a.y); var tb := outer.height_at(b.x, b.y)
		var top_a := ta + 0.9; var top_b := tb + 0.9
		var lo_a := outer.height_at(a.x + n.x * 0.6, a.y + n.y * 0.6) - 0.3
		var lo_b := outer.height_at(b.x + n.x * 0.6, b.y + n.y * 0.6) - 0.3
		var A0 := Vector3(a.x + n.x * 0.35, lo_a, a.y + n.y * 0.35) - origin
		var B0 := Vector3(b.x + n.x * 0.35, lo_b, b.y + n.y * 0.35) - origin
		var A1 := Vector3(a.x + n.x * 0.3, top_a, a.y + n.y * 0.3) - origin
		var B1 := Vector3(b.x + n.x * 0.3, top_b, b.y + n.y * 0.3) - origin
		var A2 := Vector3(a.x - n.x * 0.3, top_a, a.y - n.y * 0.3) - origin
		var B2 := Vector3(b.x - n.x * 0.3, top_b, b.y - n.y * 0.3) - origin
		var A3 := Vector3(a.x - n.x * 0.3, ta - 0.3, a.y - n.y * 0.3) - origin
		var B3 := Vector3(b.x - n.x * 0.3, tb - 0.3, b.y - n.y * 0.3) - origin
		m.ground = minf(A0.y, B0.y); m.eave = maxf(A1.y, B1.y) + 3.0
		# faces: outward (downhill) face, top, uphill face - both windings (the side is data-driven)
		for q in [[A0, B0, B1, A1], [A1, B1, B2, A2], [A2, B2, B3, A3]]:
			m.quad(q[0], q[1], q[2], q[3]); m.quad(q[1], q[0], q[3], q[2])
		faces.append_array(PackedVector3Array([A0, B0, B1, A0, B1, A1, A1, B1, B2, A1, B2, A2]))
	var mi := MeshInstance3D.new(); mi.name = "TerraceWall"
	mi.mesh = m.commit(null, ArchMaterials.merged())
	mi.visibility_range_end = 700.0
	parent.add_child(mi)
	var body := StaticBody3D.new(); body.collision_layer = 1
	var shape := ConcavePolygonShape3D.new(); shape.backface_collision = true; shape.set_faces(faces)
	var cs := CollisionShape3D.new(); cs.shape = shape; body.add_child(cs); parent.add_child(body)
