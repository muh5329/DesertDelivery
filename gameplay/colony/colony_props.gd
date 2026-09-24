class_name ColonyProps
extends RefCounted
## The dressing that says what a colony building does - log piles, fish racks, salt pans, vats,
## a forge, drying frames, a slipway - and the construction stages (a staked foundation, then
## walls rising inside a timber scaffold). Each is ONE vertex-coloured mesh in the site's frame:
## the building stands at x = -yard / 2, the yard beside it on +x, the front faces +z.

const B = preload("res://gameplay/colony/mesh_bits.gd")
const FIELD_PROPS := ["wheat", "olives", "vines", "cotton", "palms"]

const WOOD := Color("7a5534")
const WOOD_LIGHT := Color("b38a58")
const BARK := Color("5e4630")
const STONE := Color("b9b2a3")
const DARK := Color("3a3632")
const CANVAS := Color("e9e0c9")
const LEAF := Color("5f7a3c")


static func yard_width(prop: String) -> float:
	if prop in FIELD_PROPS: return 16.0
	if prop == "garden": return 5.0
	if prop == "slipway": return 12.0
	return 8.0


## The yard mesh for `prop` (null for none). `w`, `d`: the building; the yard spans
## x in [w/2 - yard/2 + 0.5, w/2 + yard/2], z in [-d/2, d/2].
static func yard(prop: String, w: float, d: float, seed: int) -> ArrayMesh:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new(); rng.seed = seed
	var y := yard_width(prop)
	var x0 := w * 0.5 - y * 0.5 + 0.8
	var x1 := w * 0.5 + y * 0.5 - 0.4
	var cx := (x0 + x1) * 0.5
	var z0 := -d * 0.5 + 0.4; var z1 := d * 0.5 - 0.4
	# a trodden earth yard under everything
	B.quad(st, Vector3(x0, 0.04, z0), Vector3(x0, 0.04, z1), Vector3(x1, 0.04, z1), Vector3(x1, 0.04, z0), Color("a38a66") if not prop in FIELD_PROPS else Color("8a6f4c"))
	match prop:
		"logs": _logs(st, rng, cx, z0, z1, x1)
		"quarry": _quarry(st, rng, cx, x0, x1, z0, z1)
		"mine": _mine(st, rng, cx, x0, x1, z0, z1)
		"wheat": _rows(st, rng, x0, x1, z0, z1, "wheat")
		"olives": _rows(st, rng, x0, x1, z0, z1, "olives")
		"vines": _rows(st, rng, x0, x1, z0, z1, "vines")
		"cotton": _rows(st, rng, x0, x1, z0, z1, "cotton")
		"palms": _rows(st, rng, x0, x1, z0, z1, "palms")
		"fish_racks", "smoke_racks": _racks(st, rng, x0, x1, z0, z1, prop == "smoke_racks")
		"salt": _salt(st, rng, x0, x1, z0, z1)
		"sawmill": _sawmill(st, rng, x0, x1, z0, z1)
		"sacks": _sacks(st, rng, cx, z0, z1)
		"oven": _oven(st, rng, cx, z0, z1)
		"vats": _vats(st, rng, x0, x1, z0, z1)
		"barrels": _barrels(st, rng, x0, x1, z0, z1)
		"forge": _forge(st, rng, cx, x0, x1, z0, z1)
		"frames": _frames(st, rng, x0, x1, z0, z1)
		"blocks": _blocks(st, rng, x0, x1, z0, z1)
		"crates": _crates(st, rng, x0, x1, z0, z1)
		"slipway": _slipway(st, rng, x0, x1, z0, z1)
		"garden": _garden(st, rng, x0, x1, z0, z1)
	st.generate_normals()
	return st.commit()


static func _logs(st: SurfaceTool, rng: RandomNumberGenerator, cx: float, z0: float, z1: float, x1: float) -> void:
	for pile in range(2):
		var pz := lerpf(z0 + 1.5, z1 - 1.5, float(pile))
		for row in range(3):
			for k in range(4 - row):
				var y := 0.22 + row * 0.38
				var x := cx - 1.2 + k * 0.42 + row * 0.21
				B.cyl(st, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(x, y, pz)), 0.2, 3.2, BARK, 7)
				B.cyl(st, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(x, y, pz + 1.61)), 0.17, 0.02, WOOD_LIGHT, 7)
	B.post(st, x1 - 1.2, 0.0, 0.35, 0.6, WOOD, 8)
	B.spar(st, Vector3(x1 - 1.2, 0.6, 0.0), Vector3(x1 - 0.8, 0.95, 0.3), 0.03, WOOD)


static func _quarry(st: SurfaceTool, rng: RandomNumberGenerator, cx: float, x0: float, x1: float, z0: float, z1: float) -> void:
	for i in range(7):
		var s := Vector3(rng.randf_range(0.6, 1.3), rng.randf_range(0.5, 1.0), rng.randf_range(0.6, 1.2))
		B.block(st, rng.randf_range(x0 + 0.8, x1 - 0.8), rng.randf_range(z0 + 0.8, z1 - 0.8), s, STONE.darkened(rng.randf_range(0, 0.15)), rng.randf_range(-0.4, 0.4))
	# an A-frame derrick
	var top := Vector3(cx, 4.2, 0.0)
	for side in [-1.0, 1.0]: B.spar(st, Vector3(cx + side * 1.4, 0, -0.8), top, 0.09, WOOD)
	B.spar(st, Vector3(cx, 0, 1.4), top, 0.09, WOOD)
	B.spar(st, top, Vector3(cx + 2.2, 2.6, 0.0), 0.06, WOOD)


static func _mine(st: SurfaceTool, rng: RandomNumberGenerator, cx: float, x0: float, x1: float, z0: float, z1: float) -> void:
	# the adit: a timber portal on a rock face
	B.block(st, cx, z0 + 0.9, Vector3(x1 - x0 - 0.6, 2.8, 1.6), Color("8c8474"))
	B.block(st, cx, z0 + 1.72, Vector3(1.6, 2.0, 0.1), DARK)
	for side in [-1.0, 1.0]: B.post(st, cx + side * 0.95, z0 + 1.8, 0.14, 2.2, WOOD)
	B.box(st, Transform3D(Basis(), Vector3(cx, 2.25, z0 + 1.8)), Vector3(2.4, 0.3, 0.3), WOOD)
	# rails and an ore cart
	for side in [-1.0, 1.0]: B.box(st, Transform3D(Basis(), Vector3(cx + side * 0.4, 0.07, (z0 + z1) * 0.5 + 0.8)), Vector3(0.08, 0.08, z1 - z0 - 2.0), DARK)
	B.block(st, cx, z1 - 2.2, Vector3(1.1, 0.7, 1.4), Color("4b3a2c"), 0.0, 0.25)
	B.blob(st, Vector3(cx, 1.0, z1 - 2.2), Vector3(0.5, 0.25, 0.6), Color("6a5f5a"))
	B.blob(st, Vector3(x1 - 1.2, 0.2, z1 - 1.0), Vector3(1.0, 0.6, 0.9), Color("5f5550"))


static func _rows(st: SurfaceTool, rng: RandomNumberGenerator, x0: float, x1: float, z0: float, z1: float, crop: String) -> void:
	var step: float = {"wheat": 1.1, "olives": 3.2, "vines": 1.8, "cotton": 1.2, "palms": 3.8}[crop]
	var z := z0 + step * 0.5
	while z < z1 - 0.2:
		match crop:
			"wheat":
				B.block(st, (x0 + x1) * 0.5, z, Vector3(x1 - x0 - 0.8, 0.75, 0.75), Color("d9b85c").darkened(rng.randf_range(0, 0.1)))
			"cotton":
				B.block(st, (x0 + x1) * 0.5, z, Vector3(x1 - x0 - 0.8, 0.55, 0.6), Color("5d7440"))
				var x := x0 + 0.8
				while x < x1 - 0.8:
					B.blob(st, Vector3(x + rng.randf_range(-0.2, 0.2), 0.62, z + rng.randf_range(-0.2, 0.2)), Vector3(0.14, 0.12, 0.14), Color("f6f3ea"), 2, 5)
					x += 0.45
			"vines":
				var x := x0 + 0.6
				B.spar(st, Vector3(x0 + 0.5, 1.3, z), Vector3(x1 - 0.5, 1.3, z), 0.02, DARK, 4)
				while x < x1 - 0.4:
					B.post(st, x, z, 0.05, 1.4, WOOD, 4)
					B.blob(st, Vector3(x + 0.5, 1.0, z), Vector3(0.55, 0.45, 0.35), Color("56743a").lightened(rng.randf_range(0, 0.1)), 3, 6)
					x += 1.1
			"olives", "palms":
				var x := x0 + step * 0.5
				while x < x1 - 0.5:
					var p := Vector3(x + rng.randf_range(-0.3, 0.3), 0, z + rng.randf_range(-0.3, 0.3))
					if crop == "olives":
						B.cyl(st, Transform3D(Basis(Vector3.FORWARD, rng.randf_range(-0.2, 0.2)), p + Vector3(0, 0.8, 0)), 0.16, 1.6, Color("6d5a44"), 6, 0.1)
						B.blob(st, p + Vector3(0, 2.1, 0), Vector3(1.3, 0.9, 1.3), Color("7d8f5e").darkened(rng.randf_range(0, 0.1)))
					else:
						var h := rng.randf_range(5.0, 7.0)
						B.cyl(st, Transform3D(Basis(Vector3.FORWARD, rng.randf_range(-0.12, 0.12)), p + Vector3(0, h * 0.5, 0)), 0.22, h, Color("7b6147"), 6, 0.16)
						for f in range(8):
							var a := TAU * f / 8 + rng.randf()
							var tip := p + Vector3(cos(a) * 2.6, h - 1.1, sin(a) * 2.6)
							var side := Vector3(-sin(a), 0, cos(a)) * 0.35
							B.quad(st, p + Vector3(0, h, 0), p + Vector3(0, h, 0) + (tip - p - Vector3(0, h, 0)) * 0.5 + side + Vector3(0, 0.35, 0), tip, p + Vector3(0, h, 0) + (tip - p - Vector3(0, h, 0)) * 0.5 - side + Vector3(0, 0.35, 0), Color("5b7a3a"))
							B.quad(st, p + Vector3(0, h, 0), p + Vector3(0, h, 0) + (tip - p - Vector3(0, h, 0)) * 0.5 - side + Vector3(0, 0.35, 0), tip, p + Vector3(0, h, 0) + (tip - p - Vector3(0, h, 0)) * 0.5 + side + Vector3(0, 0.35, 0), Color("4d6a32"))
						B.blob(st, p + Vector3(0.3, h - 0.5, 0.2), Vector3(0.35, 0.4, 0.35), Color("a0612c"), 2, 5)
					x += step
		z += step


static func _racks(st: SurfaceTool, rng: RandomNumberGenerator, x0: float, x1: float, z0: float, z1: float, smoke: bool) -> void:
	var fish := Color("aebcc2") if not smoke else Color("9a6a3c")
	for r in range(2):
		var z := lerpf(z0 + 1.2, z1 - 1.2, float(r))
		for side in [x0 + 0.6, x1 - 0.6]:
			B.spar(st, Vector3(side, 0, z - 0.6), Vector3(side, 2.0, z), 0.05, WOOD, 4)
			B.spar(st, Vector3(side, 0, z + 0.6), Vector3(side, 2.0, z), 0.05, WOOD, 4)
		B.spar(st, Vector3(x0 + 0.6, 1.95, z), Vector3(x1 - 0.6, 1.95, z), 0.04, WOOD, 4)
		var x := x0 + 1.0
		while x < x1 - 0.8:
			B.box(st, Transform3D(Basis(Vector3.FORWARD, rng.randf_range(-0.1, 0.1)), Vector3(x, 1.55, z)), Vector3(0.12, 0.7, 0.05), fish)
			x += 0.28
	if smoke:
		B.block(st, (x0 + x1) * 0.5, (z0 + z1) * 0.5, Vector3(1.0, 0.4, 1.0), DARK)
	else:
		B.blob(st, Vector3((x0 + x1) * 0.5, 0.15, (z0 + z1) * 0.5), Vector3(1.0, 0.25, 0.8), Color("5d6a5a"), 2, 7)


static func _salt(st: SurfaceTool, rng: RandomNumberGenerator, x0: float, x1: float, z0: float, z1: float) -> void:
	var cols := 2; var rows := 2
	for i in range(cols):
		for j in range(rows):
			var cx := lerpf(x0 + 1.6, x1 - 1.6, float(i) / maxf(cols - 1, 1))
			var cz := lerpf(z0 + 1.4, z1 - 1.4, float(j) / maxf(rows - 1, 1))
			B.block(st, cx, cz, Vector3(3.0, 0.18, 2.6), Color("c8bfae"))
			B.block(st, cx, cz, Vector3(2.7, 0.19, 2.3), Color("eef0ec") if (i + j) % 2 == 0 else Color("b9cfd3"))
	for k in range(3): B.cone(st, Vector3(x1 - 0.8, 0.0, lerpf(z0 + 0.8, z1 - 0.8, k / 2.0)), 0.6, 0.8, Color("f4f3ee"), 8)


static func _sawmill(st: SurfaceTool, rng: RandomNumberGenerator, x0: float, x1: float, z0: float, z1: float) -> void:
	for k in range(3):
		B.cyl(st, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(x0 + 1.0 + k * 0.45, 0.22, z0 + 2.2)), 0.2, 3.6, BARK, 7)
	for layer in range(5):
		B.block(st, x1 - 1.5, z1 - 2.0, Vector3(1.6, 0.1, 3.2), WOOD_LIGHT.darkened(0.05 * (layer % 2)), 0.0, layer * 0.12)
	# the saw bench with its blade
	B.block(st, (x0 + x1) * 0.5, 0.2, Vector3(0.9, 0.85, 3.0), WOOD)
	B.cyl(st, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3((x0 + x1) * 0.5, 1.05, 0.2)), 0.45, 0.03, Color("9aa3a8"), 14)


static func _sacks(st: SurfaceTool, rng: RandomNumberGenerator, cx: float, z0: float, z1: float) -> void:
	for i in range(7):
		B.blob(st, Vector3(cx - 1.2 + (i % 4) * 0.7, 0.3 + (i / 4) * 0.45, z0 + 1.5 + (i / 4) * 0.2), Vector3(0.35, 0.3, 0.28), Color("d8c9a4"), 3, 6)
	# a hand cart
	B.block(st, cx + 0.5, z1 - 1.5, Vector3(1.2, 0.3, 1.8), WOOD, 0.0, 0.5)
	for side in [-1.0, 1.0]:
		B.cyl(st, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(cx + 0.5 + side * 0.68, 0.45, z1 - 1.5)), 0.45, 0.08, WOOD, 10)


static func _oven(st: SurfaceTool, rng: RandomNumberGenerator, cx: float, z0: float, z1: float) -> void:
	B.block(st, cx, 0.0, Vector3(2.4, 0.9, 2.4), Color("c9b89a"))
	B.blob(st, Vector3(cx, 0.9, 0.0), Vector3(1.1, 1.0, 1.1), Color("c2a17a"), 4, 9)
	B.block(st, cx, 1.12, Vector3(0.5, 0.45, 0.08), DARK, 0.0, 0.7)
	for k in range(4):
		B.cyl(st, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(cx - 0.6 + k * 0.3, 0.14, z1 - 1.0)), 0.12, 1.2, BARK, 6)


static func _vats(st: SurfaceTool, rng: RandomNumberGenerator, x0: float, x1: float, z0: float, z1: float) -> void:
	for k in range(2):
		var p := Vector3(lerpf(x0 + 1.4, x1 - 1.4, float(k)), 0, z0 + 1.6)
		B.cyl(st, Transform3D(Basis(), p + Vector3(0, 0.6, 0)), 1.0, 1.2, WOOD, 12)
		B.cyl(st, Transform3D(Basis(), p + Vector3(0, 1.21, 0)), 0.92, 0.02, Color("5c5a2a"), 12)
	# the press: a beam on a post over a stone bed
	B.block(st, (x0 + x1) * 0.5, z1 - 1.5, Vector3(1.6, 0.4, 1.6), STONE)
	B.post(st, (x0 + x1) * 0.5 - 1.1, z1 - 1.5, 0.15, 2.2, WOOD)
	B.spar(st, Vector3((x0 + x1) * 0.5 - 1.2, 2.0, z1 - 1.5), Vector3((x0 + x1) * 0.5 + 1.6, 1.3, z1 - 1.5), 0.13, WOOD)
	for k in range(3): B.cyl(st, Transform3D(Basis(), Vector3(x1 - 0.6, 0.35, z1 - 0.8 - k * 0.6)), 0.22, 0.7, Color("b0673e"), 8, 0.12)


static func _barrels(st: SurfaceTool, rng: RandomNumberGenerator, x0: float, x1: float, z0: float, z1: float) -> void:
	for i in range(6):
		var x := x0 + 0.8 + (i % 3) * 0.9; var z := z0 + 1.0 + (i / 3) * 1.0
		B.cyl(st, Transform3D(Basis(), Vector3(x, 0.45, z)), 0.38, 0.9, Color("7a4f2e"), 10)
		B.cyl(st, Transform3D(Basis(), Vector3(x, 0.45, z)), 0.4, 0.08, DARK, 10)
	for i in range(3):
		B.cyl(st, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(x1 - 1.2, 0.4, z1 - 1.0 - i * 0.85)), 0.38, 0.9, Color("6d4428"), 10)


static func _forge(st: SurfaceTool, rng: RandomNumberGenerator, cx: float, x0: float, x1: float, z0: float, z1: float) -> void:
	B.block(st, cx, z0 + 1.2, Vector3(1.8, 1.0, 1.4), Color("8f8579"))
	B.block(st, cx, z0 + 1.2, Vector3(0.8, 0.12, 0.6), Color("d8612a"), 0.0, 1.0)
	B.block(st, cx - 0.4, z0 + 0.8, Vector3(0.6, 3.6, 0.6), Color("8a5a45"))
	B.block(st, cx + 1.2, 0.0, Vector3(0.4, 0.6, 0.4), WOOD)
	B.block(st, cx + 1.2, 0.0, Vector3(0.7, 0.2, 0.3), DARK, 0.0, 0.6)
	B.blob(st, Vector3(x1 - 1.0, 0.2, z1 - 1.0), Vector3(0.8, 0.45, 0.7), Color("5f5550"), 2, 7)
	for k in range(4): B.spar(st, Vector3(x0 + 0.6, 0.1, z1 - 0.8 - k * 0.3), Vector3(x0 + 2.2, 0.1, z1 - 0.8 - k * 0.3), 0.04, DARK, 4)


static func _frames(st: SurfaceTool, rng: RandomNumberGenerator, x0: float, x1: float, z0: float, z1: float) -> void:
	var dyes := [Color("2b3a6b"), Color("c8923a"), Color("a8322a"), Color("e9e0c9"), Color("4f7f8c")]
	for r in range(2):
		var z := lerpf(z0 + 1.0, z1 - 1.0, float(r))
		B.post(st, x0 + 0.5, z, 0.06, 2.4, WOOD); B.post(st, x1 - 0.5, z, 0.06, 2.4, WOOD)
		B.spar(st, Vector3(x0 + 0.5, 2.35, z), Vector3(x1 - 0.5, 2.35, z), 0.04, WOOD, 4)
		var x := x0 + 0.8
		while x < x1 - 1.3:
			var c: Color = dyes[rng.randi() % dyes.size()]
			var wv := rng.randf_range(0.8, 1.2)
			B.quad(st, Vector3(x, 2.3, z), Vector3(x + wv, 2.3, z), Vector3(x + wv, 0.8, z + 0.05), Vector3(x, 0.8, z + 0.05), c)
			B.quad(st, Vector3(x + wv, 2.3, z), Vector3(x, 2.3, z), Vector3(x, 0.8, z + 0.05), Vector3(x + wv, 0.8, z + 0.05), c.darkened(0.15))
			x += wv + 0.2


static func _blocks(st: SurfaceTool, rng: RandomNumberGenerator, x0: float, x1: float, z0: float, z1: float) -> void:
	for pile in range(3):
		var px := lerpf(x0 + 1.2, x1 - 1.2, float(pile % 2)); var pz := lerpf(z0 + 1.2, z1 - 1.2, float(pile) / 2.0)
		for layer in range(3 - pile % 2):
			for k in range(2):
				B.block(st, px + (k - 0.5) * 0.85, pz, Vector3(0.8, 0.5, 1.4), STONE.lightened(rng.randf_range(0, 0.1)), 0.0, layer * 0.5)
	B.block(st, (x0 + x1) * 0.5, (z0 + z1) * 0.5, Vector3(1.2, 0.8, 0.8), WOOD)


static func _crates(st: SurfaceTool, rng: RandomNumberGenerator, x0: float, x1: float, z0: float, z1: float) -> void:
	for i in range(8):
		var s := rng.randf_range(0.7, 1.0)
		var x := x0 + 0.8 + (i % 3) * 1.2 + rng.randf_range(-0.1, 0.1); var z := z0 + 0.9 + (i / 3) * 1.3
		B.block(st, x, z, Vector3.ONE * s, [Color("9a7448"), Color("b58d57"), Color("7d6a4c")][rng.randi() % 3], rng.randf_range(-0.2, 0.2))
		if i % 3 == 0: B.block(st, x, z, Vector3.ONE * s * 0.8, Color("a8845a"), 0.2, s)
	for k in range(3): B.cyl(st, Transform3D(Basis(), Vector3(x1 - 0.8, 0.45, z1 - 0.8 - k * 0.85)), 0.36, 0.9, Color("7a4f2e"), 10)


static func _slipway(st: SurfaceTool, rng: RandomNumberGenerator, x0: float, x1: float, z0: float, z1: float) -> void:
	# a timber slip with a hull in frame: keel, stem and ribs
	var cx := (x0 + x1) * 0.5
	B.block(st, cx, 0.0, Vector3(4.0, 0.25, z1 - z0), WOOD.darkened(0.1))
	var keel_y := 0.9
	B.box(st, Transform3D(Basis(), Vector3(cx, keel_y, 0.0)), Vector3(0.3, 0.3, z1 - z0 - 1.5), WOOD)
	B.spar(st, Vector3(cx, keel_y, -(z1 - z0) * 0.5 + 0.8), Vector3(cx, keel_y + 3.0, -(z1 - z0) * 0.5 - 0.2), 0.15, WOOD)
	var z := -(z1 - z0) * 0.5 + 1.8
	while z < (z1 - z0) * 0.5 - 1.2:
		var t := (z + (z1 - z0) * 0.5) / (z1 - z0)
		var hb := 1.8 * sin(clampf(t, 0.08, 0.95) * PI) + 0.3
		for side in [-1.0, 1.0]:
			B.spar(st, Vector3(cx, keel_y, z), Vector3(cx + side * hb, keel_y + 1.0, z), 0.08, WOOD_LIGHT, 4)
			B.spar(st, Vector3(cx + side * hb, keel_y + 1.0, z), Vector3(cx + side * (hb + 0.2), keel_y + 2.6, z), 0.08, WOOD_LIGHT, 4)
		z += 1.0
	for side in [-1.0, 1.0]:
		for k in range(4): B.post(st, cx + side * 2.3, -3.0 + k * 2.0, 0.08, 1.2, WOOD, 4)
	for layer in range(4): B.block(st, x1 - 0.8, z1 - 1.8, Vector3(1.0, 0.12, 3.0), WOOD_LIGHT, 0.0, layer * 0.13)


static func _garden(st: SurfaceTool, rng: RandomNumberGenerator, x0: float, x1: float, z0: float, z1: float) -> void:
	B.block(st, (x0 + x1) * 0.5, (z0 + z1) * 0.5, Vector3(x1 - x0 - 0.8, 0.2, z1 - z0 - 1.6), Color("6a4a30"))
	var z := z0 + 1.2
	while z < z1 - 1.0:
		var x := x0 + 0.8
		while x < x1 - 0.6:
			B.blob(st, Vector3(x, 0.35, z), Vector3(0.28, 0.22, 0.28), LEAF.lightened(rng.randf_range(0, 0.15)), 2, 5)
			x += 0.7
		z += 0.8
	for side in [z0 + 0.3, z1 - 0.3]:
		B.spar(st, Vector3(x0 + 0.2, 0.7, side), Vector3(x1 - 0.2, 0.7, side), 0.03, WOOD, 4)
		var x := x0 + 0.2
		while x <= x1 - 0.1:
			B.post(st, x, side, 0.04, 0.8, WOOD, 4); x += 1.2


## Construction: a staked foundation (progress < 0.3), then walls rising in a timber scaffold.
static func construction(w: float, d: float, progress: float, colour: Color) -> ArrayMesh:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	B.block(st, 0.0, 0.0, Vector3(w + 0.6, 0.35, d + 0.6), STONE.darkened(0.1))
	if progress < 0.3:
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]: B.post(st, sx * (w * 0.5 + 0.6), sz * (d * 0.5 + 0.6), 0.05, 0.9, WOOD, 4)
		for k in range(4): B.block(st, w * 0.5 + 1.6, -d * 0.3 + k * 0.5, Vector3(0.8, 0.1, 3.0), WOOD_LIGHT, 0.0, k * 0.12)
		B.block(st, -w * 0.5 - 1.5, 0.0, Vector3(1.4, 0.7, 1.2), STONE)
		return _commit(st)
	var rise := clampf((progress - 0.3) / 0.7, 0.05, 1.0) * 5.5
	# the walls, as far as they have come (a gap for the door)
	for side in [-1.0, 1.0]:
		B.box(st, Transform3D(Basis(), Vector3(side * (w * 0.5 - 0.2), 0.35 + rise * 0.5, 0.0)), Vector3(0.4, rise, d), colour)
	B.box(st, Transform3D(Basis(), Vector3(0.0, 0.35 + rise * 0.5, -d * 0.5 + 0.2)), Vector3(w, rise, 0.4), colour)
	for side in [-1.0, 1.0]:
		B.box(st, Transform3D(Basis(), Vector3(side * w * 0.3, 0.35 + rise * 0.5, d * 0.5 - 0.2)), Vector3(w * 0.4, rise, 0.4), colour)
	# the scaffold: standards, ledgers and a plank walk every 2 m
	var sw := w * 0.5 + 1.1; var sd := d * 0.5 + 1.1
	var top := rise + 1.6
	for sx in [-1.0, 0.0, 1.0]:
		for sz in [-1.0, 1.0]: B.post(st, sx * sw, sz * sd, 0.06, top, WOOD_LIGHT, 5)
	for sz in [-0.33, 0.33]:
		for sx in [-1.0, 1.0]: B.post(st, sx * sw, sz * sd * 2.0, 0.06, top, WOOD_LIGHT, 5)
	var level := 2.0
	while level < top:
		for sz in [-1.0, 1.0]:
			B.spar(st, Vector3(-sw, level, sz * sd), Vector3(sw, level, sz * sd), 0.04, WOOD_LIGHT, 4)
			B.box(st, Transform3D(Basis(), Vector3(0.0, level + 0.05, sz * (sd - 0.45))), Vector3(sw * 2.0, 0.06, 0.8), WOOD)
		for sx in [-1.0, 1.0]:
			B.spar(st, Vector3(sx * sw, level, -sd), Vector3(sx * sw, level, sd), 0.04, WOOD_LIGHT, 4)
			B.box(st, Transform3D(Basis(), Vector3(sx * (sw - 0.45), level + 0.05, 0.0)), Vector3(0.8, 0.06, sd * 2.0), WOOD)
		level += 2.0
	# a diagonal brace and a hoist
	B.spar(st, Vector3(-sw, 0.0, sd), Vector3(0.0, top - 0.3, sd), 0.04, WOOD_LIGHT, 4)
	B.spar(st, Vector3(sw, top, -sd), Vector3(sw + 1.4, top + 0.4, -sd), 0.05, WOOD, 4)
	for k in range(3): B.block(st, w * 0.5 + 2.0, d * 0.5 - k * 0.9, Vector3(0.8, 0.5, 0.7), STONE.lightened(0.05))
	return _commit(st)


static func _commit(st: SurfaceTool) -> ArrayMesh:
	st.generate_normals()
	return st.commit()
