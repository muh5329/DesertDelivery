class_name RockGen
extends RefCounted
## Procedural stratified limestone pieces (pure GDScript; the verified recipe from
## RESEARCH_tech.md §4, `/root/t3dtest/tech/rockgen.gd`).
##
## Shape: a subdivided box -> rounded-box (bevel) mapping -> bedding recess on alternate beds ->
## vertical joint grooves -> two-octave FastNoiseLite displacement along the box-face normal. Then
## crease-angle normals (smooth inside the angle, crisp across it) and a per-vertex bake into COLOR:
##   r = cavity/AO 0..1 (1 = open), g = bedding shade (soft beds darker, dark line under every
##   bedding plane), b = height above the ground line 0..1 (sand dusting in the shader).
## Beds and joints are LOCAL to the piece (not world-locked as in the sandbox version): that is what
## lets one baked mesh be cached and reused with scale/rotation variation, which is how the world
## keeps generation time down (a few dozen unique meshes for thousands of rocks). Pieces that must
## share strata (the courses of a cliff wall) are built at the same height with the same bed
## parameters, so their beds line up anyway.
##
## Usage:
##   var r := RockGen.cached({"size": Vector3(8, 4, 3), "seed": 7})   # memoised by parameters
##   r.mesh (ArrayMesh, LOD0)  r.mesh_lod1  r.tris  r.tris_lod1  r.hull (PackedVector3Array, LOD1 points)
##   var node := RockGen.build_node(r, Transform3D(...), false, mat)   # LODs + collision

const DEFAULTS := {
	"size": Vector3(8.0, 4.0, 3.0),   # full extents (m)
	"seed": 1,
	"cell": 0.6,                      # target grid cell size at LOD0 (m)
	"cell_lod1": 1.8,
	"bevel": 0.5,                     # edge rounding radius (m) on the vertical and bottom edges
	"bevel_top": -1.0,                # rounding of the top edges (weathered rims); -1 = same as bevel
	"bed_height": 4.0,                # metres between bedding planes
	"bed_tilt": 0.06,                 # dy per metre of x (3-5 degrees)
	"bed_origin_y": 0.0,              # local y of a bedding plane
	"bed_inset": 0.6,                 # soft beds recessed by this much (m)
	"bed_darken": 0.15,               # soft beds this much darker (baked into COLOR.g)
	"bed_line_width": 0.5,            # dark cavity line half-width at each bedding plane (m)
	"bed_line_strength": 0.55,
	"bed_band": 0.03,                 # r4: one soft 1-1.5 m course per bed this much darker (a BAND with 0.4 m ramps, not a line); r5: 0.04 -> 0.03, the ref beds are nearly invisible in value
	"bed_band_h": 1.2,                # height of that course (m)
	"joint_spacing": 6.0,             # vertical joints every N metres (local x and z)
	"joint_depth": 0.3,
	"joint_width": 0.5,
	"noise_amp": 0.35,                # low-frequency form noise (m)
	"noise_metres": 6.0,
	"detail_amp": 0.08,               # high-frequency surface noise (m)
	"detail_metres": 1.2,
	"top_amp": 0.0,                   # extra form noise on the top face (jagged stack tops)
	"taper": 0.0,                     # the top is this fraction narrower than the bottom (stacks); < 0 flares
	"undercut_h": 0.0,                # the bottom band of the side faces (m) is recessed (a soft bed under a hard one)
	"undercut_inset": 1.2,            # by this much (m); the recess rounds into the face above
	"arch_rise": 0.0,                 # lintels: the underside is lifted into a vault by this much (m) at x = 0
	"arch_half": 0.0,                 # half width of the vault (m): the lift is zero beyond +/- arch_half
	"facet_amp": 0.0,                 # sub-facets: Worley cells in the face plane, each pushed +/- this much (m) along the normal
	"facet_metres": 4.5,              # cell size of the facets (m)
	"facet_tilt": 0.12,               # each facet plane is also tilted by up to this (m per m, ~7 deg)
	"top_steps": 0,                   # broken top: the top face is cut into this many steps along local x ...
	"top_drop": 3.0,                  # ... each dropped by up to this much (m); 0 steps = flat top
	"top_cut": 0.0,                   # boulders: the top is sliced flat at this fraction of the half height (0 = none): one flat facet on a rounded block
	"top_cut_tilt": 0.12,             # ... the slice plane tilts up to this (m per m)
	"crease_deg": 28.0,               # normals are smoothed only across edges flatter than this
	"conc_strength": 0.5,             # how dark the concavity (crease) AO goes: 0.5 normal, 0.8 on hero pieces
	"ground_y": -1000.0,              # local y of the ground line (contact AO, sand); -1000 = none
	"boulder": false,                 # true = rounded talus boulder: big bevel, no beds/joints
	"bed_phase": -1,                  # -1 = random which beds are soft; 0/1 = forced (wall courses)
}

static var _cache: Dictionary = {}     # parameter key -> make_rock() result
static var _cache_parameters: Dictionary = {}
static var use_baked_library := not ("--rebuild-rock-library" in OS.get_cmdline_user_args())
const BAKED_SCHEMA := 2 # Bump when the geometry algorithm changes. Defaults are in the key.
const BAKED_DIR := "res://assets/rocks/generated"
static var disk_load_usec := 0
static var disk_hits := 0
static var collision_usec := 0
static var cache_usec: int = 0         # total time spent building cached pieces (profiling)


## Memoised make_rock: the same parameters always return the same (shared) meshes.
static func _canonical_parameters(p_in: Dictionary) -> Dictionary:
	var effective := DEFAULTS.duplicate()
	effective.merge(p_in, true)
	var keys := effective.keys(); keys.sort()
	var canonical: Dictionary = {}
	for k in keys: canonical[k] = effective[k]
	return canonical

static func _cache_key(p_in: Dictionary) -> String:
	# Variant binary encoding retains full float precision, unlike display strings.
	return "schema=%d;" % BAKED_SCHEMA + var_to_bytes(_canonical_parameters(p_in)).hex_encode()

static func _baked_path(key: String) -> String:
	return BAKED_DIR + "/" + key.sha256_text() + ".res"

static func cached(p_in: Dictionary) -> Dictionary:
	var key := _cache_key(p_in)
	if _cache.has(key): return _cache[key]
	var path := _baked_path(key)
	_cache_parameters[key] = _canonical_parameters(p_in)
	if use_baked_library and ResourceLoader.exists(path):
		var start := Time.get_ticks_usec()
		var baked: Resource = load(path)
		if baked != null and baked.get_meta("key", "") == key and baked.has_meta("piece"):
			var piece: Variant = baked.get_meta("piece")
			if _valid_piece(piece):
				_cache[key] = piece
				disk_load_usec += Time.get_ticks_usec() - start
				disk_hits += 1
				return piece
	var result := make_rock(p_in)
	cache_usec += int(result.usec)
	_cache[key] = result
	return result

static func _valid_piece(piece: Variant) -> bool:
	if not piece is Dictionary: return false
	if not (piece.get("mesh") is ArrayMesh and piece.get("mesh_lod1") is ArrayMesh and piece.get("hull") is PackedVector3Array): return false
	return piece.mesh.get_surface_count() > 0 and piece.mesh_lod1.get_surface_count() > 0 and piece.hull.size() >= 4 and piece.get("size") is Vector3 and piece.get("tris") is int and piece.get("tris_lod1") is int

## Authoring-only: run the full-world baker once, then ship exact binary mesh
## resources. Runtime loads only the requested piece, not the entire library.
static func save_baked_library() -> Dictionary:
	DirAccess.make_dir_recursive_absolute(BAKED_DIR)
	var bytes := 0
	var failures := 0
	var saved: Dictionary = {}
	for key: String in _cache:
		var resource := Resource.new()
		resource.set_meta("key", key)
		resource.set_meta("parameters", _cache_parameters[key])
		var piece: Dictionary = _cache[key].duplicate()
		piece.usec = 0 # This resource was already baked; runtime records disk load separately.
		resource.set_meta("piece", piece)
		var path := _baked_path(key)
		var error := ResourceSaver.save(resource, path, ResourceSaver.FLAG_COMPRESS)
		if error != OK: failures += 1
		else:
			var file := FileAccess.open(path, FileAccess.READ)
			bytes += file.get_length()
			saved[path.get_file()] = true
	# This directory is owned by the baker; remove superseded schema resources only
	# after the complete new library has saved successfully.
	if failures == 0:
		for filename in DirAccess.get_files_at(BAKED_DIR):
			if filename.ends_with(".res") and filename.get_basename().length() == 64 and not saved.has(filename):
				DirAccess.remove_absolute(BAKED_DIR + "/" + filename)
	return {"pieces":_cache.size(),"bytes":bytes,"failures":failures,"schema":BAKED_SCHEMA}


static func cache_size() -> int:
	return _cache.size()


static func make_rock(p_in: Dictionary) -> Dictionary:
	var p := DEFAULTS.duplicate()
	for k in p_in:
		p[k] = p_in[k]
	if p.boulder:
		p.bevel = min(p.size.x, p.size.y, p.size.z) * 0.45
		p.bed_inset = 0.0
		p.bed_darken = 0.0
		p.bed_line_strength = 0.0
		p.joint_depth = 0.0
	var t0 := Time.get_ticks_usec()
	var lod0 := _build(p, float(p.cell))
	var lod1 := _build(p, float(p.cell_lod1))
	return {
		"mesh": lod0.mesh, "tris": lod0.tris,
		"mesh_lod1": lod1.mesh, "tris_lod1": lod1.tris,
		"hull": lod1.unique_positions,
		"size": p.size,
		"usec": Time.get_ticks_usec() - t0,
	}


## Wraps a piece in a Node3D: LOD0 (0..lod_dist), LOD1 (lod_dist..far), StaticBody3D collision.
## concave=true builds a trimesh from LOD1 (needed for arches / overhangs you drive under),
## otherwise a convex hull of LOD1 (cheap, fine for boulders and slabs). The collision shape is
## built from pre-scaled points so the body carries rotation only (no non-uniform shape scaling).
static func build_node(r: Dictionary, xf: Transform3D, concave: bool, mat: Material = null,
		collide: bool = true, lod_dist: float = 90.0, far: float = 0.0) -> Node3D:
	# the root carries rotation + position only; the scale goes on the mesh instances, so the
	# collision body (identity, pre-scaled points) lands exactly on the mesh. (r0/r1 gave the root
	# the full transform *and* the body a world transform, which put every collider at twice the
	# rock's offset from the origin: phantom rocks on roads, none under the visible ones.)
	var root := Node3D.new()
	root.transform = Transform3D(xf.basis.orthonormalized(), xf.origin)
	# exact remainder (root * mesh_xf == xf), whatever order scale and rotation were composed in
	var local_b := root.basis.inverse() * xf.basis
	var mesh_xf := Transform3D(local_b, Vector3.ZERO)
	var m0 := MeshInstance3D.new()
	m0.mesh = r.mesh
	m0.transform = mesh_xf
	m0.visibility_range_end = lod_dist
	m0.visibility_range_end_margin = 6.0
	m0.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED  # fade costs an alpha pass in Compat
	var m1 := MeshInstance3D.new()
	m1.mesh = r.mesh_lod1
	m1.transform = mesh_xf
	m1.visibility_range_begin = lod_dist
	m1.visibility_range_begin_margin = 6.0
	m1.visibility_range_end = far
	m1.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	if mat:
		m0.material_override = mat
		m1.material_override = mat
	root.add_child(m0)
	root.add_child(m1)
	if collide:
		var collision_start := Time.get_ticks_usec()
		var body := StaticBody3D.new()
		body.collision_layer = 1
		var cs := CollisionShape3D.new()
		if concave:
			var arr: Array = r.mesh_lod1.surface_get_arrays(0)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var faces := PackedVector3Array()
			faces.resize(v.size())
			for i in v.size():
				faces[i] = local_b * v[i]
			var shape := ConcavePolygonShape3D.new()
			shape.set_faces(faces)
			cs.shape = shape
		else:
			var pts := PackedVector3Array()
			pts.resize(r.hull.size())
			for i in r.hull.size():
				pts[i] = local_b * r.hull[i]
			var hull := ConvexPolygonShape3D.new()
			hull.points = pts
			cs.shape = hull
		body.add_child(cs)
		root.add_child(body)   # identity: the root already has the rotation, the points the scale
		collision_usec += Time.get_ticks_usec() - collision_start
	return root


# ---------------------------------------------------------------------------------------------
static func _build(p: Dictionary, cell: float) -> Dictionary:
	var h: Vector3 = p.size * 0.5
	var bevel: float = p.bevel
	var bevel_top: float = p.bevel_top if float(p.bevel_top) >= 0.0 else bevel
	var bed_height: float = p.bed_height
	var bed_tilt: float = p.bed_tilt
	var bed_origin_y: float = p.bed_origin_y
	var bed_inset: float = p.bed_inset
	var bed_darken: float = p.bed_darken
	var bed_line_width: float = p.bed_line_width
	var bed_line_strength: float = p.bed_line_strength
	var joint_spacing: float = p.joint_spacing
	var joint_depth: float = p.joint_depth
	if cell >= 1.0: joint_depth *= 0.5
	# a groove narrower than the grid moves single vertices, which the concavity AO then paints as a
	# grid of dark blobs at the bed/joint crossings: grooves are at least 1.6 cells wide.
	# r4: at the far LOD (cells >= 1 m, seen beyond 60-140 m) that rule made every joint a 3 m wide,
	# 0.4 m deep trench with a dark AO floor: 3-4 px black lines through every course at 150 m. Far
	# grooves are 1.0 cell wide and half as deep (the AO probe is cell-normalised, so it stays soft).
	var far_lod: bool = cell >= 1.0
	var joint_width: float = maxf(p.joint_width, cell * (1.0 if far_lod else 1.6))
	var noise_amp: float = p.noise_amp
	var detail_amp: float = p.detail_amp
	var top_amp: float = p.top_amp
	var taper: float = p.taper
	var ground_y: float = p.ground_y
	var undercut_h: float = p.undercut_h
	var undercut_inset: float = p.undercut_inset
	var arch_rise: float = p.arch_rise
	var arch_half: float = p.arch_half
	var facet_amp: float = p.facet_amp
	var facet_metres: float = p.facet_metres
	var facet_tilt: float = p.facet_tilt
	var top_steps: int = int(p.top_steps)
	var top_drop: float = p.top_drop
	var top_cut: float = p.top_cut
	var bed_band: float = p.bed_band
	var bed_band_h: float = p.bed_band_h
	var has_beds: bool = bed_inset > 0.0 or bed_darken > 0.0
	var noise := FastNoiseLite.new()
	noise.seed = p.seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 1.0 / p.noise_metres
	var detail := FastNoiseLite.new()
	detail.seed = p.seed + 1
	detail.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	detail.frequency = 1.0 / p.detail_metres
	var rng := RandomNumberGenerator.new()
	rng.seed = p.seed
	var bed_phase: int = rng.randi() % 2   # which beds are the soft (recessed) ones
	if int(p.bed_phase) >= 0:
		bed_phase = int(p.bed_phase)
	var joint_off := Vector2(rng.randf() * joint_spacing, rng.randf() * joint_spacing)
	var facet_seed: int = rng.randi() & 0xffff
	# r4: the crease between two facets blends over >= 1.6 grid cells (in cell-field units). At 0.12
	# of a 4.5 m facet (0.54 m) on a 0.6 m grid every vertex fell wholly into one facet and each
	# diagonal border aliased into a staircase of one-cell steps: the "dotted staircases" on every
	# arch, stack and hero column. A ~1 m chamfer reads as the soft fracture shadow of the ref.
	# r5: 1.6 -> 1.0 cells: the 1 m chamfer rendered as 20-60 px diagonal smears on the arch; 1 cell
	# (0.5-0.7 m) still spans the grid diagonal, so no staircase, but the crease is a plane break again
	var facet_blend: float = maxf(0.12 * facet_metres, 1.0 * cell) / facet_metres
	# the flat top facet of a split boulder: a plane at top_cut x half height, tilted a little
	# (own RNG: the r3 pieces keep their step / joint / facet layout)
	var rng4 := RandomNumberGenerator.new()
	rng4.seed = int(p.seed) * 31 + 7
	var cut_tilt := Vector2(rng4.randf_range(-1.0, 1.0), rng4.randf_range(-1.0, 1.0)) * float(p.top_cut_tilt)
	var band_phase: float = rng4.randf()   # where in each bed the soft course sits
	# broken top: step boundaries along local x (the first segment keeps the full height so the
	# crown is stepped, not simply lowered), drops 40-100 % of top_drop
	var step_x: Array[float] = []
	var step_drop: Array[float] = []
	if top_steps > 0:
		var bounds: Array[float] = []
		for k in top_steps - 1:
			bounds.append(rng.randf_range(-0.6, 0.6) * h.x)
		bounds.sort()
		var high := rng.randi_range(0, top_steps - 1)
		for k in top_steps:
			step_x.append(bounds[k - 1] if k > 0 else -INF)
			step_drop.append(0.0 if k == high else top_drop * rng.randf_range(0.4, 1.0))

	# ---- 1. grid on 6 faces, welded by position ----
	var positions := PackedVector3Array()
	var box_normals := PackedVector3Array()   # unbeveled face normal per unique vertex (for displacement)
	var face_mask := PackedByteArray()        # bit per box face the vertex lies on (edge vertices belong to two)
	var rim := PackedFloat32Array()           # 1 on the weathered top rim (baked into COLOR.a)
	var index_of := {}                        # quantised position -> unique index
	var tris := PackedInt32Array()
	var axes := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	for a in 3:
		var n_axis: Vector3 = axes[a]
		var u_axis: Vector3 = axes[(a + 1) % 3]
		var v_axis: Vector3 = axes[(a + 2) % 3]
		var nu := maxi(2, int(ceil(2.0 * h.dot(u_axis) / cell)))
		var nv := maxi(2, int(ceil(2.0 * h.dot(v_axis) / cell)))
		for side in [1.0, -1.0]:
			var face_n: Vector3 = n_axis * side
			var face_bit := 1 << (a * 2 + (0 if side > 0.0 else 1))
			var grid := PackedInt32Array()
			grid.resize((nu + 1) * (nv + 1))
			for j in nv + 1:
				for i in nu + 1:
					var fu := (float(i) / nu) * 2.0 - 1.0
					var fv := (float(j) / nv) * 2.0 - 1.0
					var cube: Vector3 = face_n + u_axis * fu + v_axis * fv          # point on the unit cube
					var box_pt := cube * h
					var bp := box_pt
					if top_steps > 0:
						# broken top: the column of grid rows at this x is SQUASHED so its top lands on the
						# step line (r4). r2/r3 clamped y instead, which collapsed every side row above the
						# cut onto one welded point per column: fans of sliver triangles whose crease
						# normals and rim / AO bake drew a dotted diagonal staircase down the front face
						# of every stepped piece. Squashing keeps every row a real row; the riser between
						# two steps is the top face itself, sheared over the ramp width.
						var drop := _step_drop(step_x, step_drop, box_pt.x, cell)
						bp.y = -h.y + (box_pt.y + h.y) * (1.0 - drop / (2.0 * h.y))
					var pt := _rounded_box(bp, h, bevel, bevel_top)
					if taper != 0.0:
						var tk := 1.0 - taper * (pt.y / h.y + 1.0) * 0.5
						pt = Vector3(pt.x * tk, pt.y, pt.z * tk)
					if arch_rise > 0.0 and arch_half > 0.0:
						# vault: the underside (and the foot of the front/back faces) is lifted into a
						# parabola, full at the bottom row, fading out over the rise + 2 m above it
						var ax := clampf(absf(pt.x) / arch_half, 0.0, 1.0)
						var lift := arch_rise * (1.0 - ax * ax)
						if lift > 0.01:
							var up := pt.y + h.y
							pt.y += lift * (1.0 - smoothstep(0.0, lift + 2.0, up))
					var key := Vector3i((pt * 200.0).round())
					var idx: int
					if index_of.has(key):
						idx = index_of[key]
						face_mask[idx] |= face_bit
					else:
						idx = positions.size()
						index_of[key] = idx
						positions.push_back(pt)
						box_normals.push_back(face_n)
						face_mask.push_back(face_bit)
						# the top rim: near a vertical side and near the top at the same time
						var r_top := bevel_top + 0.4
						var d_side := minf(h.x - absf(box_pt.x), h.z - absf(box_pt.z))
						var d_top := h.y - box_pt.y
						rim.push_back((1.0 - smoothstep(0.0, r_top, d_side)) * (1.0 - smoothstep(0.0, r_top, d_top)))
					grid[j * (nu + 1) + i] = idx
			for j in nv:
				for i in nu:
					var a0 := grid[j * (nu + 1) + i]
					var a1 := grid[j * (nu + 1) + i + 1]
					var a2 := grid[(j + 1) * (nu + 1) + i + 1]
					var a3 := grid[(j + 1) * (nu + 1) + i]
					if side > 0.0:
						tris.append_array([a0, a2, a1, a0, a3, a2])
					else:
						tris.append_array([a0, a1, a2, a0, a2, a3])

	# ---- 2. displace: bedding recess, joints, noise ----
	var soft_flags := PackedByteArray()
	soft_flags.resize(positions.size())
	var facet_shade := PackedFloat32Array()   # per-facet albedo variation (+/- 8 %): facets read even in flat light
	facet_shade.resize(positions.size())
	facet_shade.fill(1.0)
	for i in positions.size():
		var lp := positions[i]
		var bn := box_normals[i]
		var horiz := Vector3(bn.x, 0.0, bn.z)
		var d := 0.0
		# bedding: alternate beds recessed inward on side faces
		var yb: float = (lp.y - bed_origin_y + lp.x * bed_tilt) / bed_height
		var bed_i := int(floor(yb))
		var soft := (posmod(bed_i + bed_phase, 2) == 0)
		soft_flags[i] = 1 if soft else 0
		if soft and bed_inset > 0.0 and horiz.length() > 0.5:
			var fr: float = yb - floor(yb)
			# soft bed recessed, with its top rounding into the hard bed above (undercut look)
			d -= bed_inset * (0.6 + 0.4 * smoothstep(0.0, 0.35, fr))
		# undercut: the bottom band of the side faces steps back, rounding into the face above
		if undercut_h > 0.0 and horiz.length() > 0.5:
			var uy := lp.y + h.y
			d -= undercut_inset * (1.0 - smoothstep(undercut_h * 0.6, undercut_h, uy))
		# vertical joints (grooves) at x / z multiples of joint_spacing
		if joint_depth > 0.0:
			var jx := absf(fposmod(lp.x + joint_off.x + joint_spacing * 0.5, joint_spacing) - joint_spacing * 0.5)
			var jz := absf(fposmod(lp.z + joint_off.y + joint_spacing * 0.5, joint_spacing) - joint_spacing * 0.5)
			var g := maxf(1.0 - smoothstep(0.0, joint_width, jx), 1.0 - smoothstep(0.0, joint_width, jz))
			d -= joint_depth * g
		# sub-facets: per box face the vertex lies on, a Worley cell in that face's plane pushes it
		# in or out along that face's normal (a whole cell moves together: the triangles that
		# straddle two cells become the crease between two planes)
		var fd := Vector3.ZERO
		if facet_amp > 0.0:
			for f in 6:
				if face_mask[i] & (1 << f) == 0: continue
				var fn: Vector3 = axes[f >> 1] * (1.0 if (f & 1) == 0 else -1.0)
				var amp := facet_amp if absf(fn.y) < 0.5 else facet_amp * 0.4   # tops chip less than faces
				var fr := _facet(lp, fn, facet_metres, amp, facet_tilt, facet_seed + f * 7919, facet_blend)
				fd += fn * fr.x
				facet_shade[i] = 1.0 + (fr.y - 0.5) * 0.12
		# form + detail noise (same sample points at both LODs, so they agree)
		d += noise.get_noise_3dv(lp) * noise_amp
		d += detail.get_noise_3dv(lp) * detail_amp
		if top_amp > 0.0 and bn.y > 0.5:
			d += noise.get_noise_3dv(lp * 0.8 + Vector3(31.0, 0.0, 17.0)) * top_amp
		positions[i] = lp + bn * d + fd
		if top_cut > 0.0:
			# the flat top facet of a split boulder, cut after the noise so it stays a plane: the
			# vertices above it drop straight down onto it (the cap is a height field, no folds)
			var q := positions[i]
			positions[i].y = minf(q.y, h.y * top_cut + cut_tilt.x * q.x + cut_tilt.y * q.z)

	# ---- 3. face normals, adjacency ----
	var ntri := tris.size() / 3
	var fnorm := PackedVector3Array()
	fnorm.resize(ntri)
	var farea := PackedFloat32Array()
	farea.resize(ntri)
	var adj := []                              # per vertex: PackedInt32Array of triangle ids
	adj.resize(positions.size())
	for i in positions.size():
		adj[i] = PackedInt32Array()
	for t in ntri:
		var i0 := tris[t * 3]; var i1 := tris[t * 3 + 1]; var i2 := tris[t * 3 + 2]
		# Godot front faces are wound clockwise seen from outside, so (e1 x e2) points INTO the
		# piece: negate it. (r0-r2 stored the inward vector: every rock was lit from the wrong side,
		# tops read as undersides — dark, fracture-tinted, shadow-biased into acne — and the
		# concavity AO darkened the bumps instead of the hollows.)
		var c := (positions[i2] - positions[i0]).cross(positions[i1] - positions[i0])
		var l := c.length()
		fnorm[t] = c / l if l > 1e-9 else Vector3.UP
		farea[t] = l
		adj[i0].push_back(t); adj[i1].push_back(t); adj[i2].push_back(t)

	# ---- 4. smooth normals (all-adjacent, used by the AO bake) + AO / bed shade per unique vertex ----
	var ao := PackedFloat32Array()
	ao.resize(positions.size())
	var shade := PackedFloat32Array()
	shade.resize(positions.size())
	var cos_crease := cos(deg_to_rad(p.crease_deg))
	var conc_strength: float = p.conc_strength
	if cell >= 1.0: conc_strength *= 0.6   # r4: far LOD: the joint floors were 3-4 px black lines at 150 m
	for i in positions.size():
		var nsum := Vector3.ZERO
		var csum := Vector3.ZERO
		var cnt := 0
		for t in adj[i]:
			nsum += fnorm[t] * farea[t]
			# neighbour centroid (concavity probe)
			csum += (positions[tris[t * 3]] + positions[tris[t * 3 + 1]] + positions[tris[t * 3 + 2]]) / 3.0
			cnt += 1
		var sn := nsum.normalized() if nsum.length() > 1e-9 else box_normals[i]
		var lp := positions[i]
		# (a) concavity: neighbours sitting "above" the tangent plane => this vertex is in a hollow
		var conc := 0.0
		if cnt > 0:
			conc = clampf(((csum / cnt) - lp).dot(sn) / (cell * 0.35), 0.0, 1.0)
		var ao_c := 1.0 - conc * conc_strength
		# (b) height above ground: contact shadow, 0.5 at the ground, full at 1 m
		var ao_h := 1.0
		if ground_y > -999.0:
			ao_h = lerpf(0.5, 1.0, smoothstep(0.0, 1.0, lp.y - ground_y))
		# (c) undersides (overhangs) get less sky
		var ao_d := lerpf(0.5, 1.0, smoothstep(-1.0, 0.3, sn.y))
		# (d) just under a hard bed (top 0.6 m of a recessed soft bed)
		var ao_b := 1.0
		var yb: float = (lp.y - bed_origin_y + lp.x * bed_tilt)
		if soft_flags[i] == 1 and bed_inset > 0.0:
			var to_top: float = bed_height - fposmod(yb, bed_height)
			ao_b = lerpf(0.65, 1.0, smoothstep(0.0, 0.6, to_top))
		# (e) the undercut band sits under the overhang of the face above
		var ao_u := 1.0
		if undercut_h > 0.0 and absf(sn.y) < 0.7:
			ao_u = lerpf(0.55, 1.0, smoothstep(undercut_h * 0.5, undercut_h * 1.3, lp.y + h.y))
		ao[i] = clampf(ao_c * ao_h * ao_d * ao_b * ao_u, 0.0, 1.0)
		# bedding shade: soft beds darker, a dark line at every bedding plane on side faces
		var band := 1.0
		if has_beds:
			if soft_flags[i] == 1:
				band -= bed_darken
			var in_bed := fposmod(yb, bed_height)
			var dist_plane := minf(in_bed, bed_height - in_bed)
			var line_m := 1.0 - smoothstep(0.0, bed_line_width, dist_plane)
			var side_m := 1.0 - smoothstep(0.35, 0.8, sn.y)
			band *= 1.0 - line_m * bed_line_strength * side_m
			# r4: a soft course per bed (1-1.5 m tall, 0.4 m ramps, a few % darker): the reference's
			# stratification is bands of value, not lines; the line above only marks the plane
			if bed_band > 0.0:
				var bc: float = bed_line_width + 0.4 + band_phase * maxf(bed_height - bed_band_h - 2.0 * (bed_line_width + 0.4), 0.0)
				var db: float = absf(in_bed - bc - bed_band_h * 0.5) - bed_band_h * 0.5
				band *= 1.0 - (1.0 - smoothstep(-0.4, 0.0, db)) * bed_band * side_m
		shade[i] = band * facet_shade[i]

	# ---- 5. crease-angle corner normals, unindexed output ----
	var out_v := PackedVector3Array()
	var out_n := PackedVector3Array()
	var out_c := PackedColorArray()
	out_v.resize(ntri * 3); out_n.resize(ntri * 3); out_c.resize(ntri * 3)
	for t in ntri:
		var fn := fnorm[t]
		for k in 3:
			var vi := tris[t * 3 + k]
			var nsum := Vector3.ZERO
			for t2 in adj[vi]:
				if fnorm[t2].dot(fn) >= cos_crease:
					nsum += fnorm[t2] * farea[t2]
			var o := t * 3 + k
			out_v[o] = positions[vi]
			out_n[o] = nsum.normalized() if nsum.length() > 1e-9 else fn
			var hgt := 1.0
			if ground_y > -999.0:
				hgt = clampf((positions[vi].y - ground_y) / 1.5, 0.0, 1.0)
			out_c[o] = Color(ao[vi], shade[vi], hgt, rim[vi])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = out_v
	arrays[Mesh.ARRAY_NORMAL] = out_n
	arrays[Mesh.ARRAY_COLOR] = out_c
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return {"mesh": mesh, "tris": ntri, "unique_positions": positions}


## Maps a point on the surface of box `h` (half extents) to the surface of the same box with
## edges/corners rounded by radius r (r_top near the top face: weathered rims over crisp vertical
## edges; the radius blends over the upper half so the vertical edges show no step). Flat
## interiors are unchanged.
static func _rounded_box(pt: Vector3, h: Vector3, r: float, r_top: float = -1.0) -> Vector3:
	var rmax := minf(h.x, minf(h.y, h.z)) * 0.95
	r = minf(r, rmax)
	if r_top >= 0.0:
		r = lerpf(r, minf(r_top, rmax), smoothstep(0.2, 0.9, pt.y / h.y))
	var inner := h - Vector3(r, r, r)
	var q := pt.clamp(-inner, inner)
	var d := pt - q
	if d.length() < 1e-6:
		return pt
	return q + d.normalized() * r


## Broken-top cut depth at local x: the step of the segment x falls in, with the riser softened
## over at least 2.4 grid cells so it is a steep slope spanning several quads rather than a fold
## inside one (a 4 m drop across a single 0.5 m cell folded every quad along its diagonal: the
## crease normals then alternated and the tread rendered as a light/dark checkerboard).
static func _step_drop(step_x: Array[float], step_drop: Array[float], x: float, cell: float = 0.4) -> float:
	var drop := 0.0
	var w := maxf(0.25, cell * 1.2)
	for k in step_x.size():
		if k == 0:
			drop = step_drop[0]
			continue
		var t := smoothstep(step_x[k] - w, step_x[k] + w, x)
		drop = lerpf(drop, step_drop[k], t)
	return drop


static func _hash2(ix: int, iy: int, seed_v: int) -> float:
	var n := ix * 374761393 + iy * 668265263 + seed_v * 2246822519
	n = (n ^ (n >> 13)) * 1274126177
	n = n ^ (n >> 16)
	return float(n & 0xffffff) / float(0xffffff)


## Worley facet at local point `lp` on the face with box normal `fn`: the nearest of the jittered
## cell points decides the cell; each cell is a plane with its own push (+/- amp) and tilt. Hard
## edges fall between cells automatically (the offset is constant per cell). Returns (offset in
## metres, the cell's own random 0..1 for a per-facet shade).
static func _facet(lp: Vector3, fn: Vector3, cell: float, amp: float, tilt: float, seed_v: int, blend: float = 0.12) -> Vector2:
	var u: float; var v: float
	if absf(fn.x) > 0.5: u = lp.z; v = lp.y
	elif absf(fn.z) > 0.5: u = lp.x; v = lp.y
	else: u = lp.x; v = lp.z
	var cu := u / cell; var cv := v / cell
	var iu := int(floor(cu)); var iv := int(floor(cv))
	# nearest and second-nearest cell points
	var d1 := 1e9; var d2 := 1e9
	var c1 := Vector2i(iu, iv); var c2 := Vector2i(iu, iv)
	var p1 := Vector2.ZERO; var p2 := Vector2.ZERO
	for du: int in [-1, 0, 1]:
		for dv: int in [-1, 0, 1]:
			var cx := iu + du; var cy := iv + dv
			var pu := cx + _hash2(cx, cy, seed_v)
			var pv := cy + _hash2(cx, cy, seed_v + 101)
			var dd := sqrt((cu - pu) * (cu - pu) + (cv - pv) * (cv - pv))
			if dd < d1:
				d2 = d1; c2 = c1; p2 = p1
				d1 = dd; c1 = Vector2i(cx, cy); p1 = Vector2(pu, pv)
			elif dd < d2:
				d2 = dd; c2 = Vector2i(cx, cy); p2 = Vector2(pu, pv)
	var o1 := _facet_plane(c1, p1, u, v, cell, amp, tilt, seed_v)
	var o2 := _facet_plane(c2, p2, u, v, cell, amp, tilt, seed_v)
	# the crease: a 0.1-cell blend across the border, so the step between two facets is a steep
	# chamfer and not a box edge with its own little shadow-casting shelf
	var t := 0.5 * (1.0 - smoothstep(0.0, blend, d2 - d1))
	return Vector2(lerpf(o1, o2, t), _hash2(c1.x, c1.y, seed_v + 505))


static func _facet_plane(c: Vector2i, pt: Vector2, u: float, v: float, cell: float, amp: float, tilt: float, seed_v: int) -> float:
	var push := (_hash2(c.x, c.y, seed_v + 202) * 2.0 - 1.0) * amp
	var tu := (_hash2(c.x, c.y, seed_v + 303) * 2.0 - 1.0) * tilt
	var tv := (_hash2(c.x, c.y, seed_v + 404) * 2.0 - 1.0) * tilt
	return push + tu * (u - pt.x * cell) + tv * (v - pt.y * cell)
