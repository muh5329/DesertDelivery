class_name ShipModel
extends Node3D
## A procedural period ship for the shipping lanes: a lofted hull (keel, forefoot, sheer, transom,
## red boot-top under a painted topside and a sheer strake), deck, bulwarks and rails, hatches
## and a cargo of crates, and either
##   coaster  - a 1920s motor coaster: wheelhouse aft, a raked funnel, a foremast with a derrick;
##   schooner - a two-masted topsail schooner: gaff sails, topsails, jibs on a bowsprit.
## One vertex-coloured mesh for the ship, one double-sided mesh for the canvas, a foam wake and
## bow wave that show while under way. The bow points to -Z; the waterline is y = 0.

const WATERLINE := 0.0
var type := "coaster"
var length := 34.0
var beam := 7.0
var speed := 0.0          # m/s, drives the wake and the pitch
var docked := true
var hull: MeshInstance3D
var canvas: MeshInstance3D
var cargo_node: MeshInstance3D
var wake: MeshInstance3D
var bow_wave: MeshInstance3D
var _t := 0.0
var _seed := 0
var _cargo_units := -1

static var _hull_mat: StandardMaterial3D
static var _sail_mat: StandardMaterial3D
static var _wake_mat: ShaderMaterial
static var _meshes: Dictionary = {}


func build(p_type: String, p_seed: int = 0) -> void:
	type = p_type; _seed = p_seed
	length = 34.0 if type == "coaster" else 30.0
	beam = 7.0 if type == "coaster" else 6.4
	if _hull_mat == null:
		_hull_mat = StandardMaterial3D.new(); _hull_mat.vertex_color_use_as_albedo = true; _hull_mat.roughness = 0.72
		_sail_mat = StandardMaterial3D.new(); _sail_mat.vertex_color_use_as_albedo = true; _sail_mat.roughness = 0.95
		_sail_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_wake_mat = ShaderMaterial.new(); _wake_mat.shader = _wake_shader()
	var key := "%s.%d" % [type, _seed % 3]
	if not _meshes.has(key): _meshes[key] = _build_meshes()
	var m: Array = _meshes[key]
	hull = MeshInstance3D.new(); hull.name = "Hull"; hull.mesh = m[0]; hull.material_override = _hull_mat
	add_child(hull)
	if m[1] != null:
		canvas = MeshInstance3D.new(); canvas.name = "Canvas"; canvas.mesh = m[1]; canvas.material_override = _sail_mat
		add_child(canvas)
	cargo_node = MeshInstance3D.new(); cargo_node.name = "Cargo"; cargo_node.material_override = _hull_mat
	add_child(cargo_node)
	wake = MeshInstance3D.new(); wake.name = "Wake"; wake.mesh = _wake_mesh(length * 3.2, beam * 0.9, beam * 5.0)
	wake.material_override = _wake_mat; wake.position = Vector3(0, 0.06, length * 0.5 - 1.0)
	wake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(wake)
	bow_wave = MeshInstance3D.new(); bow_wave.name = "BowWave"; bow_wave.mesh = _bow_mesh()
	bow_wave.material_override = _wake_mat; bow_wave.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bow_wave)


## Show a deck cargo of crates, sacks and barrels for `units` of `cap`.
func set_cargo(units: int, cap: int) -> void:
	var n := clampi(ceili(float(units) / maxf(cap, 1) * 8.0), 0, 8)
	if n == _cargo_units: return
	_cargo_units = n
	if n == 0: cargo_node.mesh = null; return
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new(); rng.seed = _seed + n
	var z0 := -length * 0.22 if type == "coaster" else -length * 0.05
	var f := _freeboard(0.45)
	for i in range(n):
		var col: Color = [Color("9a7448"), Color("b58d57"), Color("7d6a4c"), Color("c8b48a")][rng.randi() % 4]
		var x := (float(i % 2) - 0.5) * 1.5
		var z := z0 + float(i / 2) * 1.35
		var h := rng.randf_range(0.7, 1.1)
		MeshBits.box(st, Transform3D(Basis(Vector3.UP, rng.randf_range(-0.1, 0.1)), Vector3(x, f + 0.9 + h * 0.5, z)), Vector3(1.2, h, 1.1), col)
	st.generate_normals()
	cargo_node.mesh = st.commit()


func _process(delta: float) -> void:
	_t += delta
	var sway := 1.0 if docked else 0.6
	position.y = WATERLINE + sin(_t * 0.9 + _seed) * 0.12 * sway
	hull.rotation = Vector3(sin(_t * 0.7 + _seed) * 0.012 + (-0.01 if speed > 1.0 else 0.0), 0, sin(_t * 0.55 + _seed * 0.3) * 0.03 * sway)
	if canvas: canvas.rotation = hull.rotation
	cargo_node.rotation = hull.rotation
	var way := clampf(speed / 14.0, 0.0, 1.0)
	wake.visible = way > 0.05
	bow_wave.visible = way > 0.05
	if wake.visible:
		wake.set_instance_shader_parameter("strength", way)
		bow_wave.set_instance_shader_parameter("strength", way)


# ------------------------------------------------------------------ the hull
func _half_beam(t: float) -> float:
	var p := 1.0
	if t < 0.22: p = lerpf(0.84, 1.0, sqrt(t / 0.22))
	elif t > 0.58: p = sqrt(maxf(0.0, 1.0 - pow((t - 0.58) / 0.42, 2.0)))
	return beam * 0.5 * p


func _draft(t: float) -> float:
	var d := 2.4 if type == "coaster" else 2.2
	if t > 0.8: d *= lerpf(1.0, 0.35, (t - 0.8) / 0.2)
	if t < 0.08: d *= lerpf(0.7, 1.0, t / 0.08)
	return d


func _freeboard(t: float) -> float:
	var f := 1.9 if type == "coaster" else 1.5
	return f + 1.3 * pow(maxf(0.0, t - 0.55) / 0.45, 2.0) + 0.45 * maxf(0.0, 0.18 - t) / 0.18


func _z(t: float) -> float:
	return length * 0.5 - t * length        # stern at +z, bow at -z


func _build_meshes() -> Array:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var topside: Color = Color("1f2a33") if type == "coaster" else [Color("274a3a"), Color("22324d"), Color("5a2a24")][_seed % 3]
	var strake := Color("e9e2cf") if type == "coaster" else Color("c9a24a")
	var boot := Color("8a2f24")
	var S := 30; var U := 8
	var rings: Array = []
	for i in range(S + 1):
		var t := float(i) / S
		var hb := _half_beam(t); var d := _draft(t); var f := _freeboard(t)
		var ring := PackedVector3Array()
		for j in range(U + 1):
			var u := float(j) / U
			var y := lerpf(-d, f, u)
			var x := hb * pow(sin(u * PI * 0.5), 0.42)
			ring.append(Vector3(x, y, _z(t)))
		rings.append(ring)
	for side in [1.0, -1.0]:
		for i in range(S):
			for j in range(U):
				var a: Vector3 = rings[i][j]; var b: Vector3 = rings[i + 1][j]
				var c: Vector3 = rings[i + 1][j + 1]; var d2: Vector3 = rings[i][j + 1]
				a.x *= side; b.x *= side; c.x *= side; d2.x *= side
				var ym := (a.y + c.y) * 0.5
				var col := boot if ym < 0.25 else (strake if ym > _freeboard(float(i) / S) - 0.35 else topside)
				if side > 0: MeshBits.quad(st, a, b, c, d2, col)
				else: MeshBits.quad(st, a, d2, c, b, col)
	# transom
	for j in range(U):
		var a: Vector3 = rings[0][j]; var b: Vector3 = rings[0][j + 1]
		var col := boot if a.y < 0.25 else topside
		MeshBits.quad(st, a, b, Vector3(-b.x, b.y, b.z), Vector3(-a.x, a.y, a.z), col)
	# deck and bulwarks
	var deck := Color("a7865a")
	for i in range(S):
		var t0 := float(i) / S; var t1 := float(i + 1) / S
		var f0 := _freeboard(t0) - 0.05; var f1 := _freeboard(t1) - 0.05
		var h0 := _half_beam(t0) * 0.99; var h1 := _half_beam(t1) * 0.99
		MeshBits.quad(st, Vector3(-h0, f0, _z(t0)), Vector3(h0, f0, _z(t0)), Vector3(h1, f1, _z(t1)), Vector3(-h1, f1, _z(t1)), deck)
		for side in [1.0, -1.0]:
			var a := Vector3(h0 * side, f0, _z(t0)); var b := Vector3(h1 * side, f1, _z(t1))
			var up := Vector3(0, 0.85, 0)
			if side > 0:
				MeshBits.quad(st, a, b, b + up, a + up, strake)
				MeshBits.quad(st, b, a, a + up, b + up, Color("d8cdb2"))
			else:
				MeshBits.quad(st, b, a, a + up, b + up, strake)
				MeshBits.quad(st, a, b, b + up, a + up, Color("d8cdb2"))
			# the cap rail
			var ia := a + up + Vector3(-0.14 * side, 0.02, 0); var ib := b + up + Vector3(-0.14 * side, 0.02, 0)
			if side > 0: MeshBits.quad(st, a + up, b + up, ib, ia, Color("6b4a2e"))
			else: MeshBits.quad(st, a + up, ia, ib, b + up, Color("6b4a2e"))
	var sails: SurfaceTool = null
	if type == "coaster": _coaster(st)
	else:
		sails = SurfaceTool.new(); sails.begin(Mesh.PRIMITIVE_TRIANGLES)
		_schooner(st, sails)
	st.generate_normals()
	var mesh := st.commit()
	var canvas_mesh: ArrayMesh = null
	if sails:
		sails.generate_normals(); canvas_mesh = sails.commit()
	return [mesh, canvas_mesh]


func _coaster(st: SurfaceTool) -> void:
	var white := Color("efeadc"); var wood := Color("8c6a45"); var dark := Color("2a2f33")
	var fa := _freeboard(0.12)
	# poop house and wheelhouse aft
	MeshBits.box(st, Transform3D(Basis(), Vector3(0, fa + 1.1, length * 0.34)), Vector3(beam * 0.78, 2.2, 7.0), white)
	MeshBits.box(st, Transform3D(Basis(), Vector3(0, fa + 3.2, length * 0.3)), Vector3(beam * 0.6, 2.0, 3.6), white)
	for k in range(4):
		MeshBits.box(st, Transform3D(Basis(), Vector3(-1.5 + k, fa + 3.45, length * 0.3 - 1.82)), Vector3(0.7, 0.8, 0.06), dark)
	MeshBits.box(st, Transform3D(Basis(), Vector3(0, fa + 4.3, length * 0.3)), Vector3(beam * 0.66, 0.18, 4.0), Color("5b3a2a"))
	# the funnel: raked, black top over a red band
	var fz := length * 0.39
	var rake := Basis(Vector3.RIGHT, deg_to_rad(12))
	MeshBits.cyl(st, Transform3D(rake, Vector3(0, fa + 3.4, fz)), 0.75, 3.2, Color("c9a24a"), 12)
	MeshBits.cyl(st, Transform3D(rake, Vector3(0, fa + 4.9, fz + 0.32)), 0.78, 0.5, Color("a8322a"), 12)
	MeshBits.cyl(st, Transform3D(rake, Vector3(0, fa + 5.45, fz + 0.44)), 0.78, 0.7, Color("1d1d1d"), 12)
	# lifeboat on the house
	MeshBits.box(st, Transform3D(Basis(), Vector3(beam * 0.3, fa + 2.55, length * 0.38)), Vector3(1.0, 0.6, 4.0), white)
	# the hatches and the foremast with its derrick
	for hz in [-length * 0.2, length * 0.02]:
		MeshBits.box(st, Transform3D(Basis(), Vector3(0, _freeboard(0.45) + 0.45, hz)), Vector3(beam * 0.55, 0.9, 5.2), wood)
		MeshBits.box(st, Transform3D(Basis(), Vector3(0, _freeboard(0.45) + 0.95, hz)), Vector3(beam * 0.5, 0.12, 5.0), Color("4d5a4a"))
	var mz := -length * 0.08
	MeshBits.cyl(st, Transform3D(Basis(), Vector3(0, _freeboard(0.55) + 5.5, mz)), 0.18, 11.0, Color("c9b48a"), 8)
	MeshBits.cyl(st, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-62)), Vector3(0, _freeboard(0.55) + 2.4, mz - 3.6)), 0.12, 8.0, Color("8a7a60"), 6)
	MeshBits.box(st, Transform3D(Basis(), Vector3(0, _freeboard(0.55) + 7.2, mz)), Vector3(3.2, 0.12, 0.12), Color("8a7a60"))
	# anchors, windlass, a mast on the house
	MeshBits.box(st, Transform3D(Basis(), Vector3(0, _freeboard(0.9) + 0.4, -length * 0.4)), Vector3(1.6, 0.7, 1.0), dark)
	MeshBits.cyl(st, Transform3D(Basis(), Vector3(0, fa + 6.5, length * 0.3)), 0.1, 5.0, Color("c9b48a"), 6)
	# rigging: stays from the mast to the bow and the house
	_rope(st, Vector3(0, _freeboard(0.55) + 11.0, mz), Vector3(0, _freeboard(1.0) + 0.5, -length * 0.5 + 0.6))
	_rope(st, Vector3(0, _freeboard(0.55) + 11.0, mz), Vector3(0, fa + 8.9, length * 0.3))
	for side in [1.0, -1.0]:
		_rope(st, Vector3(0, _freeboard(0.55) + 10.5, mz), Vector3(side * _half_beam(0.55), _freeboard(0.55) + 0.8, mz + 1.0))


func _schooner(st: SurfaceTool, sails: SurfaceTool) -> void:
	var spar := Color("b58a55"); var wood := Color("8c6a45")
	var canvas := Color("ede3c8")
	var fa := _freeboard(0.3)
	# deckhouse, hatch, wheel box
	MeshBits.box(st, Transform3D(Basis(), Vector3(0, fa + 0.6, length * 0.18)), Vector3(beam * 0.45, 1.2, 4.0), Color("d9cfb4"))
	MeshBits.box(st, Transform3D(Basis(), Vector3(0, fa + 1.25, length * 0.18)), Vector3(beam * 0.5, 0.1, 4.3), wood)
	MeshBits.box(st, Transform3D(Basis(), Vector3(0, _freeboard(0.5) + 0.4, -length * 0.02)), Vector3(beam * 0.45, 0.8, 3.4), wood)
	MeshBits.box(st, Transform3D(Basis(), Vector3(0, _freeboard(0.05) + 0.6, length * 0.43)), Vector3(0.8, 1.0, 0.8), wood)
	# bowsprit
	var bz := -length * 0.5
	var bf := _freeboard(1.0)
	MeshBits.cyl(st, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-78)), Vector3(0, bf + 0.9, bz - 3.0)), 0.16, 8.0, spar, 8)
	var sprit_end := Vector3(0, bf + 1.8, bz - 6.8)
	# masts: fore (shorter) and main
	var masts := [[-length * 0.18, 17.0, 7.5], [length * 0.14, 20.0, 9.5]]
	for m in masts:
		var z: float = m[0]; var h: float = m[1]; var boom: float = m[2]
		var base := _freeboard(0.5 - z / length)
		var rake := Basis(Vector3.RIGHT, deg_to_rad(-4))
		MeshBits.cyl(st, Transform3D(rake, Vector3(0, base + h * 0.5, z)), 0.2, h, spar, 8)
		# boom and gaff
		var boom_y := base + 1.6
		MeshBits.cyl(st, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(90)), Vector3(0.0, boom_y, z + boom * 0.5)), 0.12, boom, spar, 6)
		var gaff_a := Vector3(0, base + h * 0.72, z + 0.2)
		var gaff_b := Vector3(0, base + h * 0.86, z + boom * 0.85)
		MeshBits.spar(st, gaff_a, gaff_b, 0.1, spar)
		# gaff sail: luff on the mast, foot on the boom, head on the gaff; bellied to starboard
		var belly := Vector3(0.9, 0, 0)
		var tack := Vector3(0, boom_y + 0.2, z + 0.3); var clew := Vector3(0, boom_y + 0.2, z + boom - 0.2)
		var throat := gaff_a + Vector3(0, -0.2, 0); var peak := gaff_b + Vector3(0, -0.2, 0)
		_sail(sails, [tack, clew, peak, throat], belly, canvas)
		# gaff topsail
		var mast_top := Vector3(0, base + h - 0.4, z - 0.5)
		_sail(sails, [throat + Vector3(0, 0.3, 0), peak + Vector3(0, 0.1, -0.6), mast_top], belly * 0.6, canvas.darkened(0.03))
		# stays
		for side in [1.0, -1.0]:
			_rope(st, Vector3(0, base + h * 0.8, z), Vector3(side * _half_beam(0.5 - z / length), base + 0.8, z + 1.2))
	# headsails on the forestays
	var fore_top := Vector3(0, _freeboard(0.68) + 15.8, -length * 0.18 - 0.6)
	_rope(st, fore_top, sprit_end)
	_rope(st, Vector3(0, _freeboard(0.68) + 13.0, -length * 0.18 - 0.4), Vector3(0, bf + 1.0, bz + 0.6))
	_sail(sails, [sprit_end + Vector3(0, 0.3, 0.5), fore_top + Vector3(0, -1.0, 0.3), Vector3(0, bf + 2.2, bz + 3.6)], Vector3(0.6, 0, 0), canvas)
	_sail(sails, [Vector3(0, bf + 1.1, bz + 0.9), Vector3(0, _freeboard(0.68) + 12.4, -length * 0.18 - 0.3), Vector3(0, _freeboard(0.7) + 1.6, -length * 0.25 + 2.8)], Vector3(0.7, 0, 0), canvas)
	_rope(st, Vector3(0, _freeboard(0.3) + 19.6, length * 0.14 - 0.8), fore_top)


# ------------------------------------------------------------------ mesh helpers
static func _rope(st: SurfaceTool, a: Vector3, b: Vector3) -> void:
	MeshBits.spar(st, a, b, 0.025, Color("3b3026"), 4)


## A sail over a polygon, bellied by `belly` towards its middle; subdivided so it curves.
static func _sail(st: SurfaceTool, pts: Array, belly: Vector3, col: Color) -> void:
	var c := Vector3.ZERO
	for p in pts: c += p
	c /= pts.size()
	var R := 4
	for k in range(pts.size()):
		var a: Vector3 = pts[k]; var b: Vector3 = pts[(k + 1) % pts.size()]
		for i in range(R):
			for j in range(R - i):
				var tri := [[i, j], [i + 1, j], [i, j + 1]]
				_sail_tri(st, a, b, c, tri, R, belly, col)
				if j < R - i - 1:
					_sail_tri(st, a, b, c, [[i + 1, j], [i + 1, j + 1], [i, j + 1]], R, belly, col)


static func _sail_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, tri: Array, R: int, belly: Vector3, col: Color) -> void:
	for ij in tri:
		var u := float(ij[0]) / R; var v := float(ij[1]) / R
		var w := 1.0 - u - v
		var p := a * w + b * u + c * v
		var bulge := v * (1.0 - v) * 4.0 * (0.6 + 0.4 * sin(u * PI))
		st.set_color(col.darkened(0.08 * (1.0 - bulge)))
		st.add_vertex(p + belly * bulge * 0.8)


# ------------------------------------------------------------------ foam
func _wake_mesh(len_: float, w0: float, w1: float) -> ArrayMesh:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 12
	for i in range(n):
		var t0 := float(i) / n; var t1 := float(i + 1) / n
		var a := lerpf(w0, w1, sqrt(t0)) * 0.5; var b := lerpf(w0, w1, sqrt(t1)) * 0.5
		var z0 := t0 * len_; var z1 := t1 * len_
		var verts := [[Vector3(-a, 0, z0), Vector2(0, t0)], [Vector3(a, 0, z0), Vector2(1, t0)], [Vector3(b, 0, z1), Vector2(1, t1)], [Vector3(-b, 0, z1), Vector2(0, t1)]]
		for idx in [0, 2, 1, 0, 3, 2]:
			st.set_uv(verts[idx][1]); st.set_normal(Vector3.UP); st.add_vertex(verts[idx][0])
	return st.commit()


func _bow_mesh() -> ArrayMesh:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bz := -length * 0.5
	for side in [1.0, -1.0]:
		var a := Vector3(0, 0.08, bz - 0.4); var b := Vector3(side * beam * 0.55, 0.08, bz + length * 0.35)
		var c := Vector3(side * beam * 1.1, 0.06, bz + length * 0.45); var d := Vector3(side * 0.4, 0.08, bz + 1.5)
		for v in [[a, Vector2(0.5, 0)], [b, Vector2(0.9, 0.8)], [c, Vector2(1, 1)], [a, Vector2(0.5, 0)], [c, Vector2(1, 1)], [d, Vector2(0.55, 0.3)]]:
			st.set_uv(v[1]); st.set_normal(Vector3.UP); st.add_vertex(v[0])
	return st.commit()


static func _wake_shader() -> Shader:
	var s := Shader.new()
	s.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;
instance uniform float strength = 1.0;
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n(vec2 p) { vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y); }
void fragment() {
	vec2 uv = UV;
	float edge = 1.0 - abs(uv.x - 0.5) * 2.0;
	float churn = n(vec2(uv.x * 9.0, uv.y * 30.0 - TIME * 2.2)) * 0.6 + n(vec2(uv.x * 23.0, uv.y * 70.0 - TIME * 3.1)) * 0.4;
	float centre = smoothstep(0.55, 1.0, edge) * (1.0 - uv.y);
	float rims = smoothstep(0.0, 0.25, edge) * (1.0 - smoothstep(0.35, 0.6, edge)) * (1.0 - uv.y * 0.8);
	float a = clamp((centre * 0.9 + rims * 0.8) * smoothstep(0.25, 0.75, churn) + centre * 0.25, 0.0, 1.0);
	a *= (1.0 - smoothstep(0.6, 1.0, uv.y)) * strength;
	ALBEDO = vec3(0.95, 0.97, 0.97);
	ALPHA = a * 0.85;
}
"""
	return s
