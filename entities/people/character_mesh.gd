class_name CharacterMesh
extends RefCounted
## One skinned townsperson surface, accumulated part by part and committed as a single
## ArrayMesh surface with one shared material (one draw call per person).
##
## Every part is a parametric grid: the caller computes the positions (rows along the part,
## columns around it) and a paint index per vertex; `grid()` derives normals, tangents, UVs
## (fabric-space metres), bone weights and triangles. Everything is authored in the rig's
## rest pose (pivots unrotated, arms and legs hanging straight), in model space, so the
## same 13 bones the courier's cloth uses (Skin_Root ... Skin_KneeR) drive it through the
## PivotSkinBridge. Nothing is rigid: clothing, hair and hats are skinned like the body.
##
## Per-vertex channels read by person.gdshader:
##   COLOR      base albedo (sRGB)
##   CUSTOM0    rgb = pattern / secondary colour, a = material * 16 + pattern
##   UV         fabric-space metres (u around a part, v along it or the rest height)
##   TANGENT    along the part (strand direction for hair)

enum Bone { ROOT, TORSO, HEAD, ARM_L, ELBOW_L, HAND_L, ARM_R, ELBOW_R, HAND_R, LEG_L, KNEE_L, LEG_R, KNEE_R }
const BONE_NAMES: Array[String] = ["Skin_Root", "Skin_Torso", "Skin_Head", "Skin_ArmL", "Skin_ElbowL",
	"Skin_HandL", "Skin_ArmR", "Skin_ElbowR", "Skin_HandR", "Skin_LegL", "Skin_KneeL", "Skin_LegR", "Skin_KneeR"]
const BONE_PARENTS: Array[int] = [-1, 0, 1, 1, 3, 4, 1, 6, 7, 0, 9, 0, 11]
## Model-space rest positions: identical to the courier's pivots (RiderModel).
const BONE_REST: Array[Vector3] = [Vector3(0, .82, 0), Vector3(0, .90, 0), Vector3(0, 1.69, 0),
	Vector3(-.185, 1.44, 0), Vector3(-.185, 1.045, 0), Vector3(-.185, .81, 0),
	Vector3(.185, 1.44, 0), Vector3(.185, 1.045, 0), Vector3(.185, .81, 0),
	Vector3(-.09, .82, 0), Vector3(-.09, .40, 0), Vector3(.09, .82, 0), Vector3(.09, .40, 0)]

## How a part follows the rig.
enum Rig { HEAD, NECK, TORSO, ARM, HAND, LEG, FOOT, SKIRT, HAIR, ROOT, TORSO_RIGID }

## Material classes (shader switch) and patterns.
enum Mat { SKIN, HAIR, COTTON, LINEN, WOOL, DENIM, LEATHER, EYE, METAL, STRAW, KNIT, RUBBER }
enum Pattern { PLAIN, STRIPES, PINSTRIPE, CHECKS, PLAID, RIB, CABLE, WEAVE, DOTS, HERRINGBONE, BANDS }

var positions := PackedVector3Array()
var normals := PackedVector3Array()
var tangents := PackedFloat32Array()
var colors := PackedColorArray()
var uvs := PackedVector2Array()
var custom := PackedByteArray()
var bones := PackedInt32Array()
var weights := PackedFloat32Array()
var indices := PackedInt32Array()

## paint index -> [base Color, material, pattern, secondary Color]
var paints: Array = []
var _paint_color := PackedColorArray()
var _paint_bytes: Array[PackedByteArray] = []
## Skirt hem height for Rig.SKIRT (set by the builder before emitting skirts).
var skirt_top := 1.0
var skirt_hem := .45

static var _material: ShaderMaterial


static func shared_material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://entities/people/person.gdshader")
		_material.set_shader_parameter("paper", load("res://assets/storybook/gouache_surface.png"))
	return _material


func add_paint(base: Color, material: int, pattern: int = Pattern.PLAIN, secondary: Color = Color.BLACK) -> int:
	paints.append([base, material, pattern, secondary])
	_paint_color.append(base)
	_paint_bytes.append(PackedByteArray([secondary.r8, secondary.g8, secondary.b8, material * 16 + pattern]))
	return paints.size() - 1


func vertex_count() -> int:
	return positions.size()


## Emits a rows x cols grid. `pos` is row-major (rows * cols). Closed grids wrap around the
## columns (the seam column is duplicated for continuous UVs). Normals are (d/dcol x d/drow),
## so callers order columns and rows such that this points outward (for a vertical loft:
## columns sweep from the back through the character's front towards +X, rows go down).
## opts: two_sided (bool, also emits an inner copy), keep (PackedByteArray per vertex: a quad
## is emitted when any corner is kept), uv_y (bool: v = rest height), flip (bool),
## colors (PackedColorArray overriding the paint's base colour per vertex),
## normals_out (Array: receives the computed normals), inset (float, inner copy offset).
func grid(rows: int, cols: int, pos: PackedVector3Array, paint: PackedInt32Array, closed: bool, scheme: int, opts: Dictionary = {}) -> void:
	var nrm := PackedVector3Array(); nrm.resize(rows * cols)
	var flip: bool = opts.get("flip", false)
	for i in rows:
		var i0 := maxi(i - 1, 0); var i1 := mini(i + 1, rows - 1)
		for j in cols:
			var j0: int; var j1: int
			if closed:
				j0 = (j - 1 + cols) % cols; j1 = (j + 1) % cols
			else:
				j0 = maxi(j - 1, 0); j1 = mini(j + 1, cols - 1)
			var du := pos[i * cols + j1] - pos[i * cols + j0]
			var dv := pos[i1 * cols + j] - pos[i0 * cols + j]
			var n := du.cross(dv)
			if flip: n = -n
			nrm[i * cols + j] = n.normalized() if n.length_squared() > 1e-14 else Vector3.ZERO
	# Poles (a row collapsed to a point) take the mean of the neighbouring row.
	for i in rows:
		for j in cols:
			if nrm[i * cols + j] != Vector3.ZERO: continue
			var acc := Vector3.ZERO
			for k in [i - 1, i + 1]:
				if k < 0 or k >= rows: continue
				for jj in cols: acc += nrm[k * cols + jj]
			nrm[i * cols + j] = acc.normalized() if acc.length_squared() > 1e-12 else Vector3.UP
	if opts.has("normals_out"): (opts.normals_out as Array).append(nrm)
	var keep: PackedByteArray = opts.get("keep", PackedByteArray())
	var uv_y: bool = opts.get("uv_y", false)
	var tint: PackedColorArray = opts.get("colors", PackedColorArray())
	var ucols := cols + (1 if closed else 0)
	# arc length along rows (u) and down columns (v)
	var ucoord := PackedFloat32Array(); ucoord.resize(rows * ucols)
	var vcoord := PackedFloat32Array(); vcoord.resize(rows * ucols)
	for i in rows:
		var acc := 0.0
		for j in ucols:
			if j > 0: acc += pos[i * cols + j % cols].distance_to(pos[i * cols + (j - 1) % cols])
			ucoord[i * ucols + j] = acc
	for j in ucols:
		var acc := 0.0
		for i in rows:
			if i > 0: acc += pos[i * cols + j % cols].distance_to(pos[(i - 1) * cols + j % cols])
			vcoord[i * ucols + j] = -pos[i * cols + j % cols].y if uv_y else acc
	var base := positions.size()
	for i in rows:
		var i0 := maxi(i - 1, 0); var i1 := mini(i + 1, rows - 1)
		for jj in ucols:
			var j := jj % cols
			var k := i * cols + j
			var p := pos[k]
			var t := pos[i1 * cols + j] - pos[i0 * cols + j]
			if t.length_squared() < 1e-14: t = Vector3.DOWN
			t = t.normalized()
			_vertex(p, nrm[k], t, Vector2(ucoord[i * ucols + jj], vcoord[i * ucols + jj]), paint[k], scheme, tint[k] if not tint.is_empty() else Color(-1, 0, 0))
	var qcols := ucols - 1
	var first_index := indices.size()
	for i in rows - 1:
		for j in qcols:
			var a := base + i * ucols + j
			var b := a + 1
			var c := a + ucols
			var d := c + 1
			if not keep.is_empty():
				var ka := keep[i * cols + j % cols]; var kb := keep[i * cols + (j + 1) % cols]
				var kc := keep[(i + 1) * cols + j % cols]; var kd := keep[(i + 1) * cols + (j + 1) % cols]
				if ka + kb + kc + kd == 0: continue
			# Godot's front faces wind clockwise seen from outside.
			if flip: indices.append_array([a, b, c, b, d, c])
			else: indices.append_array([a, c, b, b, c, d])
	if opts.get("two_sided", false):
		var inset: float = opts.get("inset", .0015)
		var start := positions.size()
		for v in range(base, start):
			var n: Vector3 = normals[v]
			positions.append(positions[v] - n * inset); normals.append(-n)
			tangents.append_array([tangents[v * 4], tangents[v * 4 + 1], tangents[v * 4 + 2], 1.0])
			colors.append(colors[v].darkened(.22)); uvs.append(uvs[v])
			custom.append_array([custom[v * 4], custom[v * 4 + 1], custom[v * 4 + 2], custom[v * 4 + 3]])
			bones.append_array([bones[v * 4], bones[v * 4 + 1], bones[v * 4 + 2], bones[v * 4 + 3]])
			weights.append_array([weights[v * 4], weights[v * 4 + 1], weights[v * 4 + 2], weights[v * 4 + 3]])
		var shift := start - base
		var count := indices.size()
		for q in range(first_index, count, 3):
			indices.append_array([indices[q] + shift, indices[q + 2] + shift, indices[q + 1] + shift])


func _vertex(p: Vector3, n: Vector3, t: Vector3, uv: Vector2, paint_index: int, scheme: int, tint: Color) -> void:
	positions.append(p); normals.append(n)
	tangents.append(t.x); tangents.append(t.y); tangents.append(t.z); tangents.append(1.0)
	colors.append(_paint_color[paint_index] if tint.r < 0.0 else tint)
	uvs.append(uv)
	custom.append_array(_paint_bytes[paint_index])
	_weights(scheme, p)


## Up to four (bone, weight) pairs per vertex, by region of the rest pose.
func _weights(scheme: int, p: Vector3) -> void:
	var b0 := 0; var b1 := 0; var b2 := 0; var b3 := 0
	var w0 := 1.0; var w1 := 0.0; var w2 := 0.0; var w3 := 0.0
	var right := p.x > 0.0
	match scheme:
		Rig.HEAD:
			b0 = Bone.HEAD
		Rig.NECK:
			var t := smoothstep(1.53, 1.65, p.y)
			b0 = Bone.TORSO; b1 = Bone.HEAD; w0 = 1.0 - t; w1 = t
		Rig.HAIR:
			var t := smoothstep(1.58, 1.40, p.y) * .75
			b0 = Bone.HEAD; b1 = Bone.TORSO; w0 = 1.0 - t; w1 = t
		Rig.TORSO when p.y < .845:
			# the crotch follows the thighs a little, like the seat of a pair of trousers
			var share := smoothstep(.845, .74, p.y) * .65
			var side := smoothstep(-.045, .045, p.x)
			b0 = Bone.ROOT; b1 = Bone.LEG_L; b2 = Bone.LEG_R
			w0 = 1.0 - share; w1 = share * (1.0 - side); w2 = share * side
		Rig.TORSO:
			var t := smoothstep(.88, 1.05, p.y)
			var arm := smoothstep(.12, .19, absf(p.x)) * smoothstep(1.33, 1.45, p.y) * .45
			b0 = Bone.ROOT; b1 = Bone.TORSO; b2 = Bone.ARM_R if right else Bone.ARM_L
			w0 = 1.0 - t; w1 = t * (1.0 - arm); w2 = t * arm
		Rig.SKIRT:
			if p.y < .86:
				var share := smoothstep(.86, skirt_hem, p.y) * .82
				var side := smoothstep(-.075, .075, p.x)
				var mine := share * (side if right else 1.0 - side)
				# long hems also follow the shins a little, so a trailing calf stays inside
				var knee := smoothstep(.42, .12, p.y) * .5
				var leg := Bone.LEG_R if right else Bone.LEG_L
				b0 = Bone.ROOT; b1 = leg; b2 = leg + 1; b3 = Bone.LEG_L if right else Bone.LEG_R
				w0 = 1.0 - share; w1 = mine * (1.0 - knee); w2 = mine * knee; w3 = share - mine
			else:
				var t := smoothstep(.88, 1.05, p.y)
				b0 = Bone.ROOT; b1 = Bone.TORSO; w0 = 1.0 - t; w1 = t
		Rig.TORSO_RIGID:
			b0 = Bone.TORSO
		Rig.ROOT:
			b0 = Bone.ROOT
		Rig.ARM:
			var arm := Bone.ARM_R if right else Bone.ARM_L
			var hand := smoothstep(.87, .80, p.y)
			var elbow := smoothstep(1.10, .99, p.y)
			if hand > 0.0:
				b0 = arm + 1; b1 = arm + 2; w0 = 1.0 - hand; w1 = hand
			elif elbow > 0.0:
				b0 = arm; b1 = arm + 1; w0 = 1.0 - elbow; w1 = elbow
			else:
				var torso := smoothstep(1.40, 1.50, p.y) * .55
				b0 = arm; b1 = Bone.TORSO; w0 = 1.0 - torso; w1 = torso
		Rig.HAND:
			b0 = Bone.HAND_R if right else Bone.HAND_L
		Rig.LEG:
			var leg := Bone.LEG_R if right else Bone.LEG_L
			var knee := smoothstep(.47, .35, p.y)
			if knee > 0.0:
				b0 = leg; b1 = leg + 1; w0 = 1.0 - knee; w1 = knee
			else:
				var hip := smoothstep(.92, .74, p.y)
				b0 = Bone.ROOT; b1 = leg; w0 = 1.0 - hip; w1 = hip
		Rig.FOOT:
			b0 = Bone.KNEE_R if right else Bone.KNEE_L
	var total := w0 + w1 + w2 + w3
	bones.append(b0); bones.append(b1); bones.append(b2); bones.append(b3)
	weights.append(w0 / total); weights.append(w1 / total); weights.append(w2 / total); weights.append(w3 / total)


## A vertical loft: sections are Dictionaries {y, rx, rf, rb, cx?, cz?, n?, paint, belly?,
## bust?, glute?, blade?} (rf = depth towards the front, -Z; rb = towards the back). `sub`
## Catmull-Rom subdivisions per span. warp < 1 packs columns towards the front.
## Returns [positions, rows, cols, paint] so callers can build shells from it.
func loft(sections: Array, cols: int, sub: int, scheme: int, opts: Dictionary = {}) -> Array:
	var warp: float = opts.get("warp", 1.0)
	var rows_data: Array = _interpolate(sections, sub)
	var rows := rows_data.size()
	var pos := PackedVector3Array(); pos.resize(rows * cols)
	var paint := PackedInt32Array(); paint.resize(rows * cols)
	var paint_fn: Callable = opts.get("paint_fn", Callable())
	var gap: float = opts.get("gap", 0.0)
	var keep := PackedByteArray()
	if gap > 0.0: keep.resize(rows * cols)
	for i in rows:
		var s: Dictionary = rows_data[i]
		var e := 2.0 / float(s.get("n", 2.0))
		var cx: float = s.get("cx", 0.0); var cz: float = s.get("cz", 0.0)
		for j in cols:
			var t := -1.0 + 2.0 * float(j) / float(cols)
			var th := PI * (warp * t + (1.0 - warp) * t * t * t)
			var sn := sin(th); var cs := cos(th)
			var x := signf(sn) * pow(absf(sn), e) * float(s.rx)
			var z := -signf(cs) * pow(absf(cs), e) * (float(s.rf) if cs > 0.0 else float(s.rb))
			var bump := _bumps(s, th)
			if bump != 0.0:
				var radial := Vector2(x, z)
				if radial.length_squared() > 1e-10:
					radial = radial.normalized() * bump
					x += radial.x; z += radial.y
			pos[i * cols + j] = Vector3(cx + x, float(s.y), cz + z)
			var pid: int = s.paint
			if paint_fn.is_valid(): pid = paint_fn.call(th, s, pid)
			paint[i * cols + j] = pid
			if gap > 0.0: keep[i * cols + j] = 1 if absf(th) > gap or float(s.y) > float(opts.get("gap_above", 99.0)) else 0
	var o := opts.duplicate()
	if gap > 0.0: o["keep"] = keep
	# rows listed bottom-up wind the other way
	if float(rows_data[0].y) < float(rows_data[-1].y): o["flip"] = not bool(o.get("flip", false))
	grid(rows, cols, pos, paint, true, scheme, o)
	return [pos, rows, cols, paint]


func _bumps(s: Dictionary, th: float) -> float:
	var d := 0.0
	if s.has("belly"): d += float(s.belly) * exp(-pow(th / .95, 2.0))
	if s.has("bust"):
		for c in [-.42, .42]: d += float(s.bust) * exp(-pow((th - c) / .30, 2.0))
	if s.has("glute"):
		for c in [PI - .5, -PI + .5]: d += float(s.glute) * exp(-pow(wrapf(th - c, -PI, PI) / .42, 2.0))
	if s.has("blade"):
		for c in [PI - .62, -PI + .62]: d += float(s.blade) * exp(-pow(wrapf(th - c, -PI, PI) / .35, 2.0))
	if s.has("calf"): d += float(s.calf) * exp(-pow(wrapf(th - PI, -PI, PI) / .9, 2.0))
	if s.has("ridge"): d += float(s.ridge)
	return d


## Catmull-Rom over the numeric fields; paint and non-numeric keys come from the span start.
func _interpolate(sections: Array, sub: int) -> Array:
	if sub <= 1 or sections.size() < 3: return sections
	var out: Array = []
	var n := sections.size()
	for k in n - 1:
		var p0: Dictionary = sections[maxi(k - 1, 0)]; var p1: Dictionary = sections[k]
		var p2: Dictionary = sections[k + 1]; var p3: Dictionary = sections[mini(k + 2, n - 1)]
		var steps := 1 if p2.get("hard", false) or p1.get("hard", false) else sub
		for q in steps:
			var t := float(q) / float(steps)
			if q == 0: out.append(p1); continue
			var s := p1.duplicate()
			for key in p1:
				if key == "paint" or not (p1[key] is float or p1[key] is int) or not p2.has(key): continue
				var a := float(p0.get(key, p1[key])); var b := float(p1[key]); var c := float(p2[key]); var d := float(p3.get(key, p2[key]))
				s[key] = .5 * ((2.0 * b) + (-a + c) * t + (2.0 * a - 5.0 * b + 4.0 * c - d) * t * t + (-a + 3.0 * b - 3.0 * c + d) * t * t * t)
			for key in p2:
				if not s.has(key) and (p2[key] is float): s[key] = float(p2[key]) * t
			out.append(s)
	out.append(sections[n - 1])
	return out


## An ellipsoid (pole axis `up`, facing axis `fwd`) with rings x segs.
func ellipsoid(center: Vector3, radii: Vector3, basis: Basis, rings: int, segs: int, paint: int, scheme: int, opts: Dictionary = {}) -> void:
	var pos := PackedVector3Array(); pos.resize((rings + 1) * segs)
	var pnt := PackedInt32Array(); pnt.resize((rings + 1) * segs)
	for i in rings + 1:
		var phi := PI * float(i) / float(rings)
		for j in segs:
			var th := -PI + TAU * float(j) / float(segs)
			var local := Vector3(sin(phi) * sin(th) * radii.x, cos(phi) * radii.y, -sin(phi) * cos(th) * radii.z)
			pos[i * segs + j] = center + basis * local
			pnt[i * segs + j] = paint
	grid(rings + 1, segs, pos, pnt, true, scheme, opts)


## A tube along a polyline with per-point radius; `up` orients the cross-section.
func tube(points: PackedVector3Array, radii: PackedFloat32Array, segs: int, paint: int, scheme: int, flat: float = 1.0, up: Vector3 = Vector3.UP, opts: Dictionary = {}) -> void:
	var n := points.size()
	var pos := PackedVector3Array(); pos.resize(n * segs)
	var pnt := PackedInt32Array(); pnt.resize(n * segs)
	for i in n:
		var t := (points[mini(i + 1, n - 1)] - points[maxi(i - 1, 0)]).normalized()
		var side := t.cross(up)
		if side.length_squared() < 1e-8: side = t.cross(Vector3.FORWARD)
		side = side.normalized()
		var nup := side.cross(t).normalized()
		for j in segs:
			var a := -PI + TAU * float(j) / float(segs)
			pos[i * segs + j] = points[i] + (side * sin(a) + nup * cos(a) * flat) * radii[i]
			pnt[i * segs + j] = paint
	grid(n, segs, pos, pnt, true, scheme, opts)


func commit(custom_aabb: AABB = AABB(Vector3(-1.0, -.35, -1.2), Vector3(2.0, 2.7, 2.4))) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_CUSTOM0] = custom
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {},
		Mesh.ARRAY_CUSTOM_RGBA8_UNORM << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	mesh.surface_set_material(0, shared_material())
	# Skinned poses (riding, swimming, reaching) leave the rest bounds; keep culling honest.
	mesh.custom_aabb = custom_aabb
	return mesh


## The shared skin: bind poses are the inverse rest transforms of the 13 bones.
static func make_skin() -> Skin:
	var skin := Skin.new()
	for index in BONE_NAMES.size():
		skin.add_named_bind(BONE_NAMES[index], Transform3D(Basis.IDENTITY, BONE_REST[index]).affine_inverse())
	return skin


## A skeleton whose rest pose is the rig's: local rests are parent-relative translations.
static func make_skeleton() -> Skeleton3D:
	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	for index in BONE_NAMES.size():
		skeleton.add_bone(BONE_NAMES[index])
	for index in BONE_NAMES.size():
		var parent := BONE_PARENTS[index]
		if parent >= 0: skeleton.set_bone_parent(index, parent)
		var local := BONE_REST[index] - (BONE_REST[parent] if parent >= 0 else Vector3.ZERO)
		skeleton.set_bone_rest(index, Transform3D(Basis.IDENTITY, local))
		skeleton.set_bone_pose(index, Transform3D(Basis.IDENTITY, local))
	return skeleton
