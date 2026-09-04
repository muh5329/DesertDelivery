class_name Mats
extends RefCounted
## Small material / primitive helpers shared by the procedural asset builders.

static var _cache: Dictionary = {}


static func solid(color: Color, rough: float = 0.75, metal: float = 0.0, emission: Color = Color.BLACK) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f|%s" % [color.to_html(), rough, metal, emission.to_html()]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	if emission != Color.BLACK:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = 1.5
	_cache[key] = m
	return m


static func glass(color: Color = Color(0.85, 0.92, 1.0, 0.35)) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.15
	m.metallic = 0.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func mesh_node(mesh: Mesh, mat: Material, pos: Vector3 = Vector3.ZERO, rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.scale = scl
	return mi


static func box(size: Vector3, mat: Material, pos: Vector3 = Vector3.ZERO, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return mesh_node(b, mat, pos, rot_deg)


static func sphere(radius: float, mat: Material, pos: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE, segs: int = 20) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = segs
	s.rings = maxi(int(segs / 2.0), 4)
	return mesh_node(s, mat, pos, Vector3.ZERO, scl)


static func cylinder(radius: float, height: float, mat: Material, pos: Vector3 = Vector3.ZERO, rot_deg: Vector3 = Vector3.ZERO, segs: int = 16, top_radius: float = -1.0) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.bottom_radius = radius
	c.top_radius = radius if top_radius < 0.0 else top_radius
	c.height = height
	c.radial_segments = segs
	return mesh_node(c, mat, pos, rot_deg)


static func cone(radius: float, height: float, mat: Material, pos: Vector3 = Vector3.ZERO, segs: int = 10) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.bottom_radius = radius
	c.top_radius = 0.0
	c.height = height
	c.radial_segments = segs
	return mesh_node(c, mat, pos)


static func capsule(radius: float, height: float, mat: Material, pos: Vector3 = Vector3.ZERO, rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var c := CapsuleMesh.new()
	c.radius = radius
	c.height = height
	c.radial_segments = 14
	c.rings = 6
	return mesh_node(c, mat, pos, rot_deg, scl)


## Capsule spanning from point a to point b (local coords of the parent).
static func limb(a: Vector3, b: Vector3, radius: float, mat: Material) -> MeshInstance3D:
	var d := b - a
	var len := d.length()
	var c := CapsuleMesh.new()
	c.radius = radius
	c.height = maxf(len + radius * 2.0, radius * 2.0)
	c.radial_segments = 12
	c.rings = 4
	var mi := MeshInstance3D.new()
	mi.mesh = c
	mi.material_override = mat
	var y := d.normalized()
	var helper := Vector3.RIGHT if absf(y.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var x := helper.cross(y).normalized()
	var z := x.cross(y).normalized()
	mi.transform = Transform3D(Basis(x, y, z), (a + b) * 0.5)
	return mi


static func torus(inner: float, outer: float, mat: Material, pos: Vector3 = Vector3.ZERO, rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	t.rings = 24
	t.ring_segments = 12
	return mesh_node(t, mat, pos, rot_deg, scl)


static func prism(size: Vector3, mat: Material, pos: Vector3 = Vector3.ZERO, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var p := PrismMesh.new()
	p.size = size
	return mesh_node(p, mat, pos, rot_deg)


## Generates the winged "C" courier logo as a small texture.
static func logo_texture() -> ImageTexture:
	if _cache.has("logo"):
		return _cache["logo"]
	var s := 96
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var white := Color(0.97, 0.95, 0.9, 1)
	var c := Vector2(38, 48)
	for y in range(s):
		for x in range(s):
			var p := Vector2(x, y)
			var r := p.distance_to(c)
			# ring with an opening on the right side
			if r > 17 and r < 27 and not (x > c.x + 6 and absf(y - c.y) < 9):
				img.set_pixel(x, y, white)
	# three wing bars trailing to the right
	for bar in range(3):
		var y0 := 34 + bar * 11
		var x0 := 50 + bar * 6
		var x1 := 92 - bar * 7
		for y in range(y0, y0 + 7):
			for x in range(x0, x1):
				img.set_pixel(x, y, white)
	var tex := ImageTexture.create_from_image(img)
	_cache["logo"] = tex
	return tex


static func decal_material(tex: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.roughness = 0.7
	m.cull_mode = BaseMaterial3D.CULL_BACK
	return m
