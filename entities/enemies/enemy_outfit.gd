class_name EnemyOutfit
extends RefCounted
## Dresses a RiderModel (the shared courier rig) as one of the bad guys. Everything attaches to
## the existing pivots, so walking, crouching, aiming and falling keep working:
##   bandits: a long duster (the shirt re-coloured as its body, skirt panels from the hips round
##            the back), a wide-brimmed hat with a pinched crown, a bandana over the nose and a
##            cartridge bandolier
##   pirates: a knotted headscarf with trailing ends, a striped shirt, a wide sash with hanging
##            ends, a gold earring, rolled canvas trousers
## Deterministic per `seed`: the same enemy id always wears the same clothes.

const DUSTERS := [Color("8a7453"), Color("5f5143"), Color("7b6a58"), Color("4c4a45"), Color("97805c")]
const HATS := [Color("3a2f27"), Color("5a4634"), Color("2b2a28"), Color("6e5a41")]
const BANDANAS := [Color("9c2f25"), Color("27395a"), Color("1f1f1f"), Color("7a2a3a")]
const SCARVES := [Color("b02a24"), Color("22407a"), Color("d8cfb8"), Color("1c1c1c"), Color("c9772c")]
const STRIPES := [Color("1f3358"), Color("9a2626"), Color("222222")]
const SASHES := [Color("a3262a"), Color("3c5a2e"), Color("c08a2a"), Color("5a2a6e")]
const SKINS := [Color("f0c9a4"), Color("d9a77e"), Color("b98a62"), Color("8d6443"), Color("e6b894")]
const HAIRS := [Color("2a1d14"), Color("4a3322"), Color("1b1b1b"), Color("6b4a2c"), Color("8a8a84")]

static var _stripe_shader: Shader


static func dress(m: RiderModel, kind: StringName, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new(); rng.seed = seed_value
	if kind == &"pirate": _pirate(m, rng)
	else: _bandit(m, rng)


static func _pick(rng: RandomNumberGenerator, a: Array) -> Color:
	return a[rng.randi() % a.size()]


# ------------------------------------------------------------------------------ bandit
static func _bandit(m: RiderModel, rng: RandomNumberGenerator) -> void:
	var duster := _pick(rng, DUSTERS)
	m.set_palette(duster, Color("4a4038").lerp(Color("6b5a44"), rng.randf()), _pick(rng, HAIRS), _pick(rng, SKINS))
	var felt := Mats.solid(_pick(rng, HATS), 0.95)
	var band := Mats.solid(Color("1e1a17"), 0.8)
	var cloth := Mats.solid(duster.darkened(0.05), 0.95)
	var bandana := Mats.solid(_pick(rng, BANDANAS), 0.92)
	var leather := Mats.solid(Color("4a3322"), 0.85)
	var brass := Mats.solid(Color("c29a4c"), 0.35, 0.8)
	_recolor(m, ["SkinnedSuspenders", "Waistband"], "Suspenders", duster.darkened(0.25))
	_recolor(m, ["Torso_Geometry"], "Neckerchief", (bandana as StandardMaterial3D).albedo_color)
	var crown := _node(m.head, "Outfit")
	# hat: a flat brim with a slight roll and a tall pinched crown
	var hat := MeshKit.new()
	hat.loft([MeshKit.ring(0.0, 0.0, 0.0, 0.215, 0.215, 2.0, 32), MeshKit.ring(-0.012, 0.0, 0.0, 0.225, 0.225, 2.0, 32)])
	var hm := MeshInstance3D.new(); hm.mesh = hat.commit(null, felt)
	hm.rotation_degrees = Vector3(-90 + rng.randf_range(-6, 4), 0, rng.randf_range(-4, 4)); hm.position = Vector3(0, 0.16, 0.0)
	crown.add_child(hm)
	var cr := MeshKit.new()
	cr.loft([MeshKit.ring(0.0, 0.0, 0.0, 0.118, 0.105, 2.2, 24), MeshKit.ring(-0.07, 0.0, 0.0, 0.110, 0.098, 2.4, 24),
		MeshKit.ring(-0.12, 0.0, 0.0, 0.090, 0.070, 2.6, 24), MeshKit.ring(-0.135, 0.0, 0.0, 0.050, 0.030, 2.0, 24)])
	var cm := MeshInstance3D.new(); cm.mesh = cr.commit(null, felt)
	cm.rotation_degrees = Vector3(90, 0, 0); cm.position = Vector3(0, 0.155, 0.0)
	crown.add_child(cm)
	var hb := MeshKit.new()
	hb.loft([MeshKit.ring(0.0, 0.0, 0.0, 0.121, 0.108, 2.2, 24), MeshKit.ring(-0.022, 0.0, 0.0, 0.119, 0.106, 2.2, 24)], false, false)
	var hbm := MeshInstance3D.new(); hbm.mesh = hb.commit(null, band)
	hbm.rotation_degrees = Vector3(90, 0, 0); hbm.position = Vector3(0, 0.16, 0.0)
	crown.add_child(hbm)
	# bandana over nose and mouth, knotted behind
	crown.add_child(_band(0.140, -0.085, 0.0, 0.07, -118.0, 118.0, bandana, 0.0))
	crown.add_child(Mats.sphere(0.022, bandana, Vector3(0, -0.075, 0.125), Vector3(1.3, 1.0, 0.8), 8))
	for side in [-1.0, 1.0]:
		crown.add_child(Mats.box(Vector3(0.03, 0.09, 0.008), bandana, Vector3(side * 0.018, -0.12, 0.13), Vector3(-10, 0, side * 16.0)))
	var tri := SurfaceTool.new(); tri.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in [Vector3(-0.11, -0.075, -0.10), Vector3(0.11, -0.075, -0.10), Vector3(0.0, -0.20, -0.105)]: tri.add_vertex(v)
	for v in [Vector3(-0.11, -0.075, -0.10), Vector3(0.0, -0.20, -0.105), Vector3(0.11, -0.075, -0.10)]: tri.add_vertex(v)
	tri.generate_normals()
	var tm := MeshInstance3D.new(); tm.mesh = tri.commit(); tm.material_override = bandana
	crown.add_child(tm)
	# duster skirt: panels round the back and sides, hanging from the hips to the knees
	var hips := _node(m.root, "Outfit")
	hips.add_child(_skirt(cloth, 0.19, 0.29, 0.10, -0.60, 40.0, 320.0))
	for side in [-1.0, 1.0]:
		hips.add_child(Mats.box(Vector3(0.012, 0.64, 0.10), cloth, Vector3(side * 0.16, -0.24, -0.15), Vector3(0, side * -20.0, side * 4.0)))
	# bandolier across the chest with brass cartridge tips
	var outfit := _node(m.torso, "Outfit")
	var strap := MeshKit.new()
	var pts := PackedVector3Array()
	for i in range(9):
		var t := float(i) / 8.0
		var p := Vector3(0.14, 0.64, 0.0).lerp(Vector3(-0.16, 0.12, 0.0), t)
		pts.append(p + Vector3(0, 0, -0.112 - sin(t * PI) * 0.035))
	strap.tube(pts, 0.004, 8, Vector2(1.0, 5.0), true, true, Vector3(0, 0, -1))
	var sm := MeshInstance3D.new(); sm.mesh = strap.commit(null, leather); outfit.add_child(sm)
	for i in range(1, 8):
		outfit.add_child(Mats.cylinder(0.006, 0.022, brass, pts[i] + Vector3(0, 0.0, -0.006), Vector3(0, 0, -58), 6))
	# a gun belt with a holster on the right hip
	hips.add_child(Mats.torus(0.165, 0.185, leather, Vector3(0, 0.12, 0), Vector3.ZERO, Vector3(1, 0.35, 0.78)))
	hips.add_child(Mats.box(Vector3(0.05, 0.16, 0.08), leather, Vector3(0.19, -0.02, 0.0), Vector3(0, 0, -6)))


# ------------------------------------------------------------------------------ pirate
static func _pirate(m: RiderModel, rng: RandomNumberGenerator) -> void:
	var stripe := _pick(rng, STRIPES)
	m.set_palette(Color("e8e2d2"), Color("3d4a5c").lerp(Color("b8a98a"), rng.randf()), _pick(rng, HAIRS), _pick(rng, SKINS))
	_stripe_shirt(m, Color("ece6d6"), stripe)
	var scarf := Mats.solid(_pick(rng, SCARVES), 0.92)
	var sash := Mats.solid(_pick(rng, SASHES), 0.9)
	var gold := Mats.solid(Color("d8b04a"), 0.3, 0.9)
	_recolor(m, ["SkinnedSuspenders", "Waistband"], "Suspenders", Color("3b2c22"))
	_recolor(m, ["Torso_Geometry"], "Neckerchief", (sash as StandardMaterial3D).albedo_color.lightened(0.1))
	var crown := _node(m.head, "Outfit")
	# headscarf: a snug cap over the crown, a knot at the back and two trailing ends
	crown.add_child(Mats.sphere(0.158, scarf, Vector3(0, 0.075, 0.012), Vector3(1.0, 0.72, 1.05), 20))
	crown.add_child(Mats.sphere(0.034, scarf, Vector3(0.02, 0.05, 0.155), Vector3(1.2, 0.9, 0.8), 10))
	for side in [-1.0, 1.0]:
		crown.add_child(Mats.box(Vector3(0.045, 0.15, 0.012), scarf, Vector3(0.02 + side * 0.028, -0.03, 0.165), Vector3(-12, 0, side * 14.0)))
	crown.add_child(Mats.torus(0.009, 0.014, gold, Vector3(-0.142, -0.035, 0.0), Vector3(0, 0, 90)))
	# a wide sash round the waist, ends hanging on the left hip
	var hips := _node(m.root, "Outfit")
	hips.add_child(_band(0.185, 0.07, 0.0, 0.085, -180.0, 180.0, sash, 0.0, 0.0))
	for i in range(2):
		hips.add_child(Mats.box(Vector3(0.06, 0.22 - i * 0.05, 0.014), sash, Vector3(-0.17 - i * 0.02, -0.07 - i * 0.02, -0.07 + i * 0.03), Vector3(0, -30, 8 + i * 10)))
	# a powder-horn style bag strap over one shoulder (a satchel for the loot)
	var outfit := _node(m.torso, "Outfit")
	var strap := MeshKit.new()
	var pts := PackedVector3Array()
	for i in range(7):
		var t := float(i) / 6.0
		pts.append(Vector3(-0.13, 0.63, 0.0).lerp(Vector3(0.17, 0.10, 0.0), t) + Vector3(0, 0, -0.108 - sin(t * PI) * 0.03))
	strap.tube(pts, 0.003, 8, Vector2(1.0, 4.0), true, true, Vector3(0, 0, -1))
	var sm := MeshInstance3D.new(); sm.mesh = strap.commit(null, Mats.solid(Color("5a4230"), 0.85)); outfit.add_child(sm)
	hips.add_child(Mats.box(Vector3(0.05, 0.14, 0.08), Mats.solid(Color("4a3322"), 0.85), Vector3(0.19, -0.02, 0.0), Vector3(0, 0, -6)))


# ------------------------------------------------------------------------------ helpers
static func _node(parent: Node3D, n: String) -> Node3D:
	var old := parent.get_node_or_null(n)
	if old: parent.remove_child(old); old.queue_free()
	var o := Node3D.new(); o.name = n
	parent.add_child(o)
	return o


## A band of cloth round a pivot: radius, centre height, depth offset, height, from/to angle
## (degrees, 0 = straight ahead), flare (radius growth toward the bottom).
static func _band(radius: float, y: float, z: float, h: float, a0: float, a1: float, mat: Material, flare: float, bulge: float = 0.0) -> MeshInstance3D:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 20
	for i in range(segs):
		var t0 := deg_to_rad(lerpf(a0, a1, float(i) / segs)); var t1 := deg_to_rad(lerpf(a0, a1, float(i + 1) / segs))
		var r0 := radius + bulge
		var q := [Vector3(sin(t0) * r0, y + h * 0.5, -cos(t0) * r0 + z), Vector3(sin(t1) * r0, y + h * 0.5, -cos(t1) * r0 + z),
			Vector3(sin(t1) * (r0 + flare), y - h * 0.5, -cos(t1) * (r0 + flare) + z), Vector3(sin(t0) * (r0 + flare), y - h * 0.5, -cos(t0) * (r0 + flare) + z)]
		for k in [0, 1, 2, 0, 2, 3]: st.add_vertex(q[k])
	st.generate_normals()
	var mi := MeshInstance3D.new(); mi.mesh = st.commit()
	var mat2: StandardMaterial3D = (mat as StandardMaterial3D).duplicate()
	mat2.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat2
	return mi


## A flared skirt of cloth from the hips (radius r_top at y_top) to the knees (r_bottom at
## y_bottom), round from a0 to a1 degrees (0 = straight ahead, so 40..320 leaves the front open).
static func _skirt(mat: Material, r_top: float, r_bottom: float, y_top: float, y_bottom: float, a0: float, a1: float) -> MeshInstance3D:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 22; var rows := 5
	for j in range(rows):
		for i in range(segs):
			var pts: Array[Vector3] = []
			for c in [[i, j], [i + 1, j], [i + 1, j + 1], [i, j + 1]]:
				var t := deg_to_rad(lerpf(a0, a1, float(c[0]) / segs))
				var v := float(c[1]) / rows
				var r := lerpf(r_top, r_bottom, v) + sin(t * 7.0) * 0.012 * v     # soft folds
				pts.append(Vector3(sin(t) * r, lerpf(y_top, y_bottom, v), -cos(t) * r * 0.85))
			for k in [0, 1, 2, 0, 2, 3]: st.add_vertex(pts[k])
	st.generate_normals()
	var mi := MeshInstance3D.new(); mi.mesh = st.commit()
	var mat2: StandardMaterial3D = (mat as StandardMaterial3D).duplicate()
	mat2.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat2
	return mi


## Re-tint the surfaces of the named meshes whose material names start with `prefix`.
static func _recolor(m: RiderModel, meshes: Array, prefix: String, c: Color) -> void:
	for node in m.find_children("*", "MeshInstance3D", true, false):
		if not String(node.name) in meshes: continue
		for i in range(node.mesh.get_surface_count()):
			var src: Material = node.mesh.surface_get_material(i)
			if src is StandardMaterial3D and src.resource_name.begins_with(prefix):
				var mat: StandardMaterial3D = src.duplicate()
				mat.albedo_color = c
				node.set_surface_override_material(i, mat)


static func _stripe_shirt(m: RiderModel, a: Color, b: Color) -> void:
	if _stripe_shader == null:
		_stripe_shader = Shader.new()
		_stripe_shader.code = """
shader_type spatial;
uniform vec3 col_a : source_color;
uniform vec3 col_b : source_color;
varying vec3 lp;
void vertex() { lp = VERTEX; }
void fragment() {
	float s = step(0.5, fract(lp.y * 16.0));
	ALBEDO = mix(col_a, col_b, s);
	ROUGHNESS = 0.9;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = _stripe_shader
	mat.set_shader_parameter("col_a", a)
	mat.set_shader_parameter("col_b", b)
	for node in m.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = node.mesh
		if mesh == null: continue
		for i in range(mesh.get_surface_count()):
			var src: Material = mesh.surface_get_material(i)
			if src and src.resource_name.begins_with("Shirt"):
				node.set_surface_override_material(i, mat)
