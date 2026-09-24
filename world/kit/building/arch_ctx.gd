class_name ArchCtx
extends RefCounted
## The state of one BuildingKit.build_group() call: the merged mesh of the whole group, the module
## instances per module key, the collision shapes, and the frame of the building being built
## (`bxf`: its local frame -> the group's frame). `finish()` turns it into nodes: one
## MeshInstance3D, one MultiMeshInstance3D per module key, one StaticBody3D.

var m := ArchMesh.new()
var inst: Dictionary = {}          # key -> [Array (Transform3D), PackedColorArray (custom)]
var shapes: Array = []             # [Shape3D, Transform3D]
var bxf := Transform3D.IDENTITY
var rng := RandomNumberGenerator.new()
var collide := true
var far := 0.0                     # visibility range end of the small details (0 = none)


func begin(xf: Transform3D, seed_v: int) -> void:
	bxf = xf
	m.xf = xf
	rng.seed = seed_v


## Place a module (by key, see ArchModules) at `local` in the current building's frame. `custom`:
## paint rgb + window-frame index; `wall`: the host wall's tint rgb + layer (reveals, stacks).
func place(key: String, local: Transform3D, custom: Color = Color.WHITE, wall: Color = Color(1, 1, 1, 0)) -> void:
	var e: Array = inst.get(key, [])
	if e.is_empty():
		e = [[], PackedColorArray(), PackedColorArray()]
		inst[key] = e
	e[0].append(bxf * local)
	e[1].append(custom)
	e[2].append(wall)


## A box collider from lo to hi in the building's local frame (optionally rotated by b about its centre).
func box_shape(lo: Vector3, hi: Vector3, b: Basis = Basis()) -> void:
	if not collide: return
	var s := BoxShape3D.new()
	s.size = (hi - lo).abs()
	shapes.append([s, bxf * Transform3D(b, (lo + hi) * 0.5)])


## A box collider of size s centred at c (local), rotated by b.
func box_shape_c(c: Vector3, s: Vector3, b: Basis = Basis()) -> void:
	if not collide: return
	var sh := BoxShape3D.new()
	sh.size = s.abs()
	shapes.append([sh, bxf * Transform3D(b, c)])


## A convex collider from local points (roofs).
func convex_shape(pts: PackedVector3Array) -> void:
	if not collide: return
	var s := ConvexPolygonShape3D.new()
	s.points = pts
	shapes.append([s, bxf])


## Bake module instances into the merged mesh: every key (single buildings) or only the keys with
## at most `max_count` instances (a MultiMesh of one or two instances is a wasted draw call).
## Each run of a module's vertices shares one part, so colours and layers are bulk fills.
func bake_modules(max_count: int = 1000000) -> void:
	var pal: Array = ArchMaterials.FRAMES
	var baked: Array = []
	var tc := PackedColorArray()
	var tu := PackedVector2Array()
	for key: String in inst:
		var e: Array = inst[key]
		if (e[0] as Array).size() > max_count: continue
		baked.append(key)
		var arr := ArchModules.arrays(key)
		var rs := ArchModules.runs(key)
		var mv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var mn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var mu: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		var mi: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var xfs: Array = e[0]
		var cus: PackedColorArray = e[1]
		var walls: PackedColorArray = e[2]
		for k in range(xfs.size()):
			var xf: Transform3D = xfs[k]
			var cu: Color = cus[k]
			var wl: Color = walls[k]
			var fr: Color = pal[clampi(int(cu.a + 0.5), 0, pal.size() - 1)]
			var base := m.v.size()
			m.v.append_array(xf * mv)
			m.nrm.append_array(Transform3D(xf.basis.orthonormalized(), Vector3.ZERO) * mn)
			m.uv.append_array(mu)
			for r in rs:
				var col: Color = r[2]
				var layer: float = r[3]
				var f: float = r[4]
				if f > 2.5: col = col * fr
				elif f > 1.5:
					col = col * wl; layer = wl.a
				elif f > 0.5: col = col * cu
				col.a = 1.0
				var n: int = r[1]
				tc.resize(n); tc.fill(col); m.col.append_array(tc)
				tu.resize(n); tu.fill(Vector2(layer, 20.0)); m.uv2.append_array(tu)
			for i in mi: m.idx.append(i + base)
	for key in baked: inst.erase(key)


func finish(parent: Node3D, name_prefix: String = "Buildings") -> void:
	if m.size() > 0:
		var mi := MeshInstance3D.new()
		mi.name = name_prefix
		mi.mesh = m.commit(null, ArchMaterials.merged())
		parent.add_child(mi)
	var mat := ArchMaterials.instanced()
	for key: String in inst:
		var e: Array = inst[key]
		var xfs: Array = e[0]
		var cus: PackedColorArray = e[1]
		var walls: PackedColorArray = e[2]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		var mesh := ArchModules.mesh(key)
		mm.mesh = mesh
		mm.instance_count = xfs.size()
		# the bounds, set now (the server computes them lazily); the node sits at its instances' centre (a node parked at the group origin would claim to
		# reach it, and the headless server reports no MultiMesh bounds at all)
		var mab := mesh.get_aabb()
		var box := (xfs[0] as Transform3D) * mab
		for i in range(1, xfs.size()): box = box.merge((xfs[i] as Transform3D) * mab)
		var centre := box.get_center()
		for i in range(xfs.size()):
			var t: Transform3D = xfs[i]
			mm.set_instance_transform(i, Transform3D(t.basis, t.origin - centre))
			mm.set_instance_custom_data(i, cus[i])
			mm.set_instance_color(i, walls[i])
		box.position -= centre
		mm.custom_aabb = box
		var mmi := MultiMeshInstance3D.new()
		mmi.name = key.get_slice("|", 0)
		mmi.multimesh = mm
		mmi.position = centre
		mmi.material_override = mat
		if not ArchModules.shadows.get(key, false):
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if far > 0.0 and ArchModules.details.get(key, false):
			mmi.visibility_range_end = far
		parent.add_child(mmi)
	if not shapes.is_empty():
		var body := StaticBody3D.new()
		body.name = name_prefix + "Body"
		body.collision_layer = 1
		for s in shapes:
			var cs := CollisionShape3D.new()
			cs.shape = s[0]
			cs.transform = s[1]
			body.add_child(cs)
		parent.add_child(body)
