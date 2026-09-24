class_name ArchProps
extends RefCounted
## Street furniture, market and harbour props for the outer towns (OuterProps places them from
## plan.json `props`). Each prop is an ArchModules-style module: built once per key with ArchMesh
## (module = true), drawn with the architecture kit's instanced material, so it shares the town's
## texture layers (stone, timber, iron, canvas, terracotta, glass...) and costs one MultiMesh per
## prop kind per streamed group. Frame: x to the right, y up from the ground, z = the prop's front.
## Parts flagged 1 take the instance paint (INSTANCE_CUSTOM.rgb): awnings, parasols, boat hulls.

const L = preload("res://world/kit/building/arch_materials.gd")

const WOOD := Color(0.62, 0.48, 0.34)
const DARK_WOOD := Color(0.42, 0.32, 0.24)
const STONE := Color(0.9, 0.86, 0.78)
const IRON := Color(0.16, 0.16, 0.17)
const WATER := Color(0.24, 0.42, 0.44)
const TERRA := Color(0.95, 0.72, 0.58)

static var _box_cache := {}


static func _begin() -> ArchMesh:
	var m := ArchMesh.new()
	m.module = true
	return m


static func _part(m: ArchMesh, layer: int, tint: Color, flag: float = 0.0) -> void:
	m.layer = float(layer); m.tint = tint; m.flag = flag


static func _put(key: String, m: ArchMesh, cast := true) -> String:
	ArchModules._cache[key] = m.commit()
	ArchModules.shadows[key] = cast
	ArchModules.details[key] = true
	return key


static func _has(key: String) -> bool:
	return ArchModules._cache.has(key)


## A cylinder along an arbitrary local frame (wheels, lying bales, beams).
static func _cyl_xf(m: ArchMesh, xf: Transform3D, r0: float, r1: float, h: float, seg: int = 10, caps: bool = true) -> void:
	var keep := m.xf
	m.xf = keep * xf
	m.cylinder(Vector3.ZERO, r0, r1, h, seg, caps, caps)
	m.xf = keep


## Collision footprint of a prop (half extents x, height, half z) for OuterProps.
static func footprint(kind: String) -> Vector3:
	match kind:
		"fountain_grand": return Vector3(4.7, 1.0, 4.7)
		"fountain_basin", "fountain_moorish": return Vector3(3.0, 0.8, 3.0)
		"fountain_trough": return Vector3(2.2, 1.0, 0.8)
		"well": return Vector3(1.0, 1.0, 1.0)
		"bench": return Vector3(0.95, 0.5, 0.3)
		"planter", "planter_round": return Vector3(0.85, 0.6, 0.85)
		"stall": return Vector3(1.3, 1.0, 0.7)
		"cart": return Vector3(0.9, 1.0, 1.6)
		"barrel": return Vector3(0.35, 0.9, 0.35)
		"crates": return Vector3(1.2, 1.0, 0.8)
		"bollard", "quay_bollard": return Vector3(0.2, 0.8, 0.2)
		"net_rack": return Vector3(2.2, 1.6, 0.3)
		"haybale": return Vector3(0.8, 1.4, 0.7)
		"garden": return Vector3(4.2, 0.5, 6.2)
		"cafe": return Vector3(0.9, 0.8, 0.9)
		"pot_big": return Vector3(0.45, 0.8, 0.45)
		"lamp_plaza": return Vector3(0.2, 3.0, 0.2)
		"crane_port": return Vector3(3.2, 6.0, 3.2)
		"lobster_pots": return Vector3(0.8, 0.8, 0.6)
	return Vector3.ZERO


static func key_for(kind: String, variant: int) -> String:
	match kind:
		"fountain_grand": return fountain_grand()
		"fountain_basin": return fountain_basin()
		"fountain_moorish": return fountain_moorish()
		"fountain_trough": return fountain_trough()
		"well": return well()
		"bench": return bench(variant % 2)
		"planter": return planter(false)
		"planter_round": return planter(true)
		"stall": return stall(variant % 4)
		"cafe": return cafe(variant % 2)
		"cart": return cart()
		"barrel": return barrel()
		"crates": return crates(variant % 3)
		"bollard": return bollard(false)
		"quay_bollard": return bollard(true)
		"pot_big": return pot_big()
		"lamp_plaza": return lamp_plaza()
		"washing": return washing(variant)
		"boat_fishing": return boat(9.5, 3.1, 1.3, true, variant % 3)
		"boat_small": return boat(6.2, 2.1, 0.85, false, variant % 3)
		"dinghy": return boat(3.8, 1.5, 0.6, false, 3)
		"net_rack": return net_rack()
		"lobster_pots": return lobster_pots()
		"jetty": return jetty(variant)
		"crane_port": return crane_port()
		"haybale": return haybale(variant % 3)
		"garden": return garden(variant % 2)
	return ""


# ---------------------------------------------------------------- fountains
## The grand plaza fountain: a round basin with a moulded rim, a pedestal, two bowls and a finial.
static func fountain_grand() -> String:
	var key := "p_fountain_grand"
	if _has(key): return key
	var m := _begin()
	_part(m, L.STONE, STONE)
	m.cylinder(Vector3(0, 0, 0), 4.6, 4.6, 0.25, 24, false)
	m.cylinder(Vector3(0, 0.25, 0), 4.4, 4.35, 0.5, 24, true)       # rim top ring (the inside is the water disc)
	m.cylinder(Vector3(0, 0.75, 0), 4.5, 4.5, 0.12, 24, true)
	_part(m, L.GLASS, WATER)
	m.cylinder(Vector3(0, 0.62, 0), 4.05, 4.05, 0.2, 24, true)       # the water, a hair under the rim
	_part(m, L.STONE, STONE)
	m.cylinder(Vector3(0, 0.6, 0), 0.75, 0.55, 1.2, 12, false)
	m.cylinder(Vector3(0, 1.8, 0), 0.35, 1.7, 0.45, 16, true)          # lower bowl
	m.cylinder(Vector3(0, 2.25, 0), 0.4, 0.3, 0.9, 10, false)
	m.cylinder(Vector3(0, 3.15, 0), 0.22, 0.9, 0.3, 12, true)          # upper bowl
	m.cylinder(Vector3(0, 3.45, 0), 0.18, 0.12, 0.6, 8, false)
	m.dome(Vector3(0, 4.05, 0), 0.2, 1.2, 8, 3)
	_part(m, L.GLASS, Color(0.7, 0.85, 0.9))
	# water falling from the bowls: thin sheets as open cylinders
	m.cylinder(Vector3(0, 0.75, 0), 1.72, 1.66, 1.05, 16, false)
	m.cylinder(Vector3(0, 2.3, 0), 0.92, 0.88, 0.85, 12, false)
	return _put(key, m)


## A plain round basin with a central column (Campo, hamlets).
static func fountain_basin() -> String:
	var key := "p_fountain_basin"
	if _has(key): return key
	var m := _begin()
	_part(m, L.STONE, Color(0.92, 0.85, 0.72))
	m.cylinder(Vector3.ZERO, 2.9, 2.9, 0.7, 20, false)
	m.cylinder(Vector3(0, 0.7, 0), 3.0, 2.95, 0.12, 20, true)
	_part(m, L.GLASS, WATER)
	m.cylinder(Vector3(0, 0.55, 0), 2.6, 2.6, 0.1, 20, true)
	_part(m, L.STONE, Color(0.92, 0.85, 0.72))
	m.cylinder(Vector3(0, 0.6, 0), 0.4, 0.3, 2.2, 10, true)
	m.dome(Vector3(0, 2.8, 0), 0.35, 1.0, 10, 3)
	_part(m, L.IRON, Color(0.45, 0.4, 0.3))
	for k in range(4):
		var a := TAU * k / 4.0
		m.rbox(Vector3(sin(a) * 0.45, 2.0, cos(a) * 0.45), Vector3(0.05, 0.05, 0.3), Basis(Vector3.UP, a))
	return _put(key, m)


## Sarmada: a low octagonal basin faced with tiles, a small bowl on a tiled drum.
static func fountain_moorish() -> String:
	var key := "p_fountain_moorish"
	if _has(key): return key
	var m := _begin()
	_part(m, L.AZULEJO, Color(1, 1, 1))
	m.cylinder(Vector3.ZERO, 2.8, 2.8, 0.55, 8, false)
	_part(m, L.STONE, Color(0.95, 0.9, 0.8))
	m.cylinder(Vector3(0, 0.55, 0), 2.95, 2.95, 0.1, 8, true)
	_part(m, L.GLASS, Color(0.2, 0.45, 0.5))
	m.cylinder(Vector3(0, 0.45, 0), 2.55, 2.55, 0.08, 8, true)
	_part(m, L.AZULEJO, Color(1, 1, 1))
	m.cylinder(Vector3(0, 0.5, 0), 0.6, 0.6, 0.6, 8, false)
	_part(m, L.STONE, Color(0.95, 0.9, 0.8))
	m.cylinder(Vector3(0, 1.1, 0), 0.25, 1.0, 0.25, 12, true)
	m.cylinder(Vector3(0, 1.35, 0), 0.08, 0.06, 0.35, 6, true)
	return _put(key, m)


## Valdoro: a long stone trough fed by an iron spout from a stone stele.
static func fountain_trough() -> String:
	var key := "p_fountain_trough"
	if _has(key): return key
	var m := _begin()
	_part(m, L.RUBBLE, Color(0.85, 0.83, 0.8))
	m.box(Vector3(-2.0, 0, -0.55), Vector3(2.0, 0.75, 0.55))
	_part(m, L.GLASS, WATER)
	m.box(Vector3(-1.85, 0.6, -0.42), Vector3(1.85, 0.77, 0.42), 4)
	_part(m, L.ASHLAR, Color(0.88, 0.86, 0.82))
	m.box(Vector3(-0.6, 0, -0.95), Vector3(0.6, 2.2, -0.55))
	m.cylinder(Vector3(0, 2.2, -0.75), 0.62, 0.0, 0.5, 4, false)
	_part(m, L.IRON, Color(0.35, 0.3, 0.25))
	m.box(Vector3(-0.04, 1.35, -0.55), Vector3(0.04, 1.42, -0.2))
	return _put(key, m)


## A village well: a round stone head, two posts, a beam with a bucket, a little tiled roof.
static func well() -> String:
	var key := "p_well"
	if _has(key): return key
	var m := _begin()
	_part(m, L.RUBBLE, Color(0.9, 0.87, 0.82))
	m.cylinder(Vector3.ZERO, 0.95, 0.95, 0.85, 12, false)
	m.cylinder(Vector3(0, 0.85, 0), 1.0, 1.0, 0.1, 12, true)
	_part(m, L.GLASS, Color(0.08, 0.12, 0.12))
	m.cylinder(Vector3(0, 0.8, 0), 0.72, 0.72, 0.08, 12, true)
	_part(m, L.TIMBER, DARK_WOOD)
	m.box(Vector3(-0.95, 0.8, -0.08), Vector3(-0.8, 2.3, 0.08))
	m.box(Vector3(0.8, 0.8, -0.08), Vector3(0.95, 2.3, 0.08))
	m.box(Vector3(-1.0, 2.0, -0.05), Vector3(1.0, 2.1, 0.05))
	_part(m, L.ROOF_TILE, Color(1, 1, 1))
	m.quad(Vector3(-1.2, 2.3, 0.7), Vector3(1.2, 2.3, 0.7), Vector3(1.2, 2.75, 0), Vector3(-1.2, 2.75, 0))
	m.quad(Vector3(1.2, 2.3, -0.7), Vector3(-1.2, 2.3, -0.7), Vector3(-1.2, 2.75, 0), Vector3(1.2, 2.75, 0))
	_part(m, L.TIMBER, WOOD)
	m.cylinder(Vector3(0.2, 1.3, 0), 0.16, 0.13, 0.3, 8, true, true)
	return _put(key, m)


# ---------------------------------------------------------------- furniture
static func bench(v: int) -> String:
	var key := "p_bench|%d" % v
	if _has(key): return key
	var m := _begin()
	if v == 0:
		# wooden slats on cast-iron ends
		_part(m, L.IRON, IRON)
		for x in [-0.8, 0.8]:
			m.box(Vector3(x - 0.04, 0, -0.25), Vector3(x + 0.04, 0.44, 0.22))
			m.box(Vector3(x - 0.04, 0.44, -0.28), Vector3(x + 0.04, 0.85, -0.2))
		_part(m, L.TIMBER, Color(0.58, 0.42, 0.28))
		for k in range(4):
			m.box(Vector3(-0.95, 0.42, -0.2 + k * 0.11), Vector3(0.95, 0.46, -0.2 + k * 0.11 + 0.08))
		for k in range(3):
			m.box(Vector3(-0.95, 0.52 + k * 0.1, -0.27), Vector3(0.95, 0.59 + k * 0.1, -0.24))
	else:
		# a stone bench
		_part(m, L.ASHLAR, Color(0.92, 0.88, 0.8))
		m.box(Vector3(-0.9, 0, -0.18), Vector3(-0.65, 0.4, 0.18))
		m.box(Vector3(0.65, 0, -0.18), Vector3(0.9, 0.4, 0.18))
		m.box(Vector3(-1.0, 0.4, -0.25), Vector3(1.0, 0.5, 0.25))
	return _put(key, m)


static func planter(round_: bool) -> String:
	var key := "p_planter|%d" % int(round_)
	if _has(key): return key
	var m := _begin()
	_part(m, L.ASHLAR, Color(0.9, 0.86, 0.78))
	if round_:
		m.cylinder(Vector3.ZERO, 0.85, 0.8, 0.55, 14, false)
	else:
		m.box(Vector3(-0.85, 0, -0.85), Vector3(0.85, 0.55, 0.85), 63 - 4)
	_part(m, L.TIMBER, Color(0.35, 0.28, 0.2))
	if round_: m.cylinder(Vector3(0, 0.48, 0), 0.74, 0.74, 0.02, 14, true)
	else: m.box(Vector3(-0.75, 0.46, -0.75), Vector3(0.75, 0.5, 0.75), 4)
	return _put(key, m)


static func pot_big() -> String:
	var key := "p_pot_big"
	if _has(key): return key
	var m := _begin()
	_part(m, L.ROOF_TILE, TERRA)
	m.cylinder(Vector3.ZERO, 0.22, 0.42, 0.55, 12, false)
	m.cylinder(Vector3(0, 0.55, 0), 0.42, 0.46, 0.1, 12, false)
	_part(m, L.TIMBER, Color(0.45, 0.7, 0.35), 1)
	m.dome(Vector3(0, 0.6, 0), 0.5, 1.1, 9, 3)
	m.dome(Vector3(0.18, 0.85, 0.1), 0.3, 1.0, 7, 2)
	return _put(key, m)


static func bollard(quay: bool) -> String:
	var key := "p_bollard|%d" % int(quay)
	if _has(key): return key
	var m := _begin()
	if quay:
		_part(m, L.IRON, Color(0.22, 0.22, 0.24))
		m.cylinder(Vector3.ZERO, 0.24, 0.2, 0.45, 10, false)
		m.cylinder(Vector3(0, 0.45, 0), 0.2, 0.34, 0.12, 10, true)
	else:
		_part(m, L.STONE, Color(0.88, 0.85, 0.78))
		m.cylinder(Vector3.ZERO, 0.16, 0.14, 0.75, 8, false)
		m.dome(Vector3(0, 0.75, 0), 0.14, 0.8, 8, 2)
	return _put(key, m)


static func lamp_plaza() -> String:
	var key := "p_lamp_plaza"
	if _has(key): return key
	var m := _begin()
	_part(m, L.IRON, Color(0.14, 0.15, 0.15))
	m.cylinder(Vector3.ZERO, 0.22, 0.18, 0.5, 8, true)
	m.cylinder(Vector3(0, 0.5, 0), 0.08, 0.06, 3.6, 8, false)
	m.box(Vector3(-0.75, 3.9, -0.03), Vector3(0.75, 3.96, 0.03))
	for x in [-0.72, 0.72]:
		m.box(Vector3(x - 0.13, 3.5, -0.13), Vector3(x + 0.13, 3.54, 0.13))
		m.cylinder(Vector3(x, 3.85, 0), 0.16, 0.05, 0.22, 6, true)
		_part(m, L.GLASS, Color(1.0, 0.92, 0.66))
		m.box(Vector3(x - 0.11, 3.54, -0.11), Vector3(x + 0.11, 3.85, 0.11), 63 - 4 - 8)
		_part(m, L.IRON, Color(0.14, 0.15, 0.15))
	m.dome(Vector3(0, 4.0, 0), 0.08, 2.0, 6, 2)
	return _put(key, m)


# ---------------------------------------------------------------- the market and cafes
const GOODS := [
	[Color(1.0, 0.55, 0.12), Color(0.95, 0.18, 0.12), Color(0.55, 0.78, 0.25), Color(1.0, 0.85, 0.2)],   # fruit
	[Color(0.3, 0.6, 0.2), Color(0.85, 0.3, 0.2), Color(0.9, 0.85, 0.7), Color(0.45, 0.25, 0.4)],       # vegetables
	[Color(0.75, 0.42, 0.28), Color(0.9, 0.82, 0.68), Color(0.2, 0.42, 0.7), Color(0.85, 0.6, 0.4)],     # pottery
	[Color(0.75, 0.15, 0.2), Color(0.2, 0.35, 0.65), Color(0.95, 0.75, 0.2), Color(0.25, 0.55, 0.45)],   # cloth
]


## A market stall: timber trestle, crates of goods, a canvas awning in the instance paint.
static func stall(v: int) -> String:
	var key := "p_stall|%d" % v
	if _has(key): return key
	var m := _begin()
	_part(m, L.TIMBER, WOOD)
	for x in [-1.2, 1.2]:
		for z in [-0.6, 0.6]:
			m.box(Vector3(x - 0.04, 0, z - 0.04), Vector3(x + 0.04, 2.3 if z < 0 else 2.0, z + 0.04))
	m.box(Vector3(-1.3, 0.78, -0.65), Vector3(1.3, 0.84, 0.65))
	m.box(Vector3(-1.25, 0.2, -0.6), Vector3(1.25, 0.24, 0.6))
	# the awning: sloped canvas and a scalloped valance, in the paint colour
	_part(m, L.CANVAS, Color(1, 1, 1), 1)
	m.quad(Vector3(-1.4, 2.3, -0.75), Vector3(1.4, 2.3, -0.75), Vector3(1.4, 1.95, 0.95), Vector3(-1.4, 1.95, 0.95))
	m.quad(Vector3(-1.4, 1.95, 0.95), Vector3(1.4, 1.95, 0.95), Vector3(1.4, 2.3, -0.75), Vector3(-1.4, 2.3, -0.75))
	m.quad(Vector3(-1.4, 1.95, 0.95), Vector3(1.4, 1.95, 0.95), Vector3(1.4, 1.72, 0.96), Vector3(-1.4, 1.72, 0.96))
	m.quad(Vector3(1.4, 1.72, 0.96), Vector3(1.4, 1.95, 0.95), Vector3(-1.4, 1.95, 0.95), Vector3(-1.4, 1.72, 0.96))
	# the goods: crates on the table, each full of one colour
	var g: Array = GOODS[v]
	for i in range(4):
		var x := -0.95 + i * 0.63
		_part(m, L.TIMBER, Color(0.72, 0.58, 0.42))
		m.box(Vector3(x - 0.28, 0.84, -0.45), Vector3(x + 0.28, 0.98, 0.35))
		_part(m, L.PLASTER, g[i])
		if v <= 1:
			for q in range(3):
				for r in range(2):
					m.dome(Vector3(x - 0.17 + q * 0.17, 0.96, -0.3 + r * 0.35 + (q % 2) * 0.08), 0.1, 0.9, 6, 2)
		elif v == 2:
			m.cylinder(Vector3(x - 0.12, 0.98, -0.1), 0.1, 0.13, 0.28, 8, true)
			m.cylinder(Vector3(x + 0.12, 0.98, 0.15), 0.12, 0.08, 0.22, 8, true)
		else:
			m.box(Vector3(x - 0.24, 0.98, -0.38), Vector3(x + 0.24, 1.1, 0.3))
			m.box(Vector3(x - 0.2, 1.1, -0.3), Vector3(x + 0.2, 1.18, 0.2))
	# a sack and a basket under the table
	_part(m, L.CANVAS, Color(0.85, 0.75, 0.55))
	m.dome(Vector3(-0.7, 0.24, 0.1), 0.3, 1.4, 7, 3)
	_part(m, L.TIMBER, Color(0.8, 0.65, 0.4))
	m.cylinder(Vector3(0.6, 0.24, 0.0), 0.25, 0.3, 0.3, 8, false)
	return _put(key, m)


## A cafe table with two (v 0) or four (v 1) chairs under a parasol in the paint colour.
static func cafe(v: int) -> String:
	var key := "p_cafe|%d" % v
	if _has(key): return key
	var m := _begin()
	_part(m, L.IRON, Color(0.2, 0.2, 0.2))
	m.cylinder(Vector3.ZERO, 0.25, 0.25, 0.04, 8, true)
	m.cylinder(Vector3(0, 0.04, 0), 0.04, 0.04, 0.7, 6, false)
	_part(m, L.STONE, Color(0.95, 0.93, 0.88))
	m.cylinder(Vector3(0, 0.72, 0), 0.4, 0.4, 0.04, 12, true, true)
	var n := 2 if v == 0 else 4
	for k in range(n):
		var a := TAU * k / n + 0.4
		var d := Vector3(sin(a), 0, cos(a))
		var c := d * 0.72
		var b := Basis(Vector3.UP, a)
		_part(m, L.IRON, Color(0.2, 0.2, 0.2))
		for sx in [-0.17, 0.17]:
			for sz in [-0.17, 0.17]:
				m.rbox(c + b * Vector3(sx, 0.22, sz), Vector3(0.03, 0.44, 0.03), b)
		m.rbox(c + b * Vector3(0, 0.66, 0.19), Vector3(0.38, 0.36, 0.03), b)
		_part(m, L.TIMBER, Color(0.65, 0.5, 0.35))
		m.rbox(c + Vector3(0, 0.45, 0), Vector3(0.4, 0.04, 0.4), b)
	# parasol
	_part(m, L.TIMBER, Color(0.85, 0.8, 0.7))
	m.cylinder(Vector3(0, 0.76, 0), 0.03, 0.03, 1.7, 6, false)
	_part(m, L.CANVAS, Color(1, 1, 1), 1)
	m.cylinder(Vector3(0, 2.2, 0), 1.35, 0.02, 0.4, 8, false)
	m.cylinder(Vector3(0, 2.2, 0), 1.35, 1.35, 0.12, 8, false)
	m.cylinder(Vector3(0, 2.32, 0), 1.33, 0.02, 0.38, 8, false, true)
	return _put(key, m, true)


static func cart() -> String:
	var key := "p_cart"
	if _has(key): return key
	var m := _begin()
	_part(m, L.TIMBER, Color(0.6, 0.45, 0.3))
	m.box(Vector3(-0.75, 0.6, -0.9), Vector3(0.75, 0.68, 1.0))
	m.box(Vector3(-0.75, 0.68, -0.9), Vector3(-0.7, 1.0, 1.0))
	m.box(Vector3(0.7, 0.68, -0.9), Vector3(0.75, 1.0, 1.0))
	m.box(Vector3(-0.75, 0.68, -0.95), Vector3(0.75, 1.0, -0.9))
	for x in [-0.35, 0.35]:
		m.rbox(Vector3(x, 0.35, 1.7), Vector3(0.06, 0.06, 1.6), Basis(Vector3.RIGHT, 0.35))
	_part(m, L.TIMBER, DARK_WOOD)
	for x in [-0.85, 0.85]:
		_cyl_xf(m, Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(x + (0.05 if x > 0 else -0.05), 0.55, 0.0)), 0.55, 0.55, 0.1, 12)
	# a load of sacks and a crate
	_part(m, L.CANVAS, Color(0.82, 0.72, 0.52))
	m.dome(Vector3(-0.3, 0.68, 0.3), 0.35, 1.0, 7, 2)
	m.dome(Vector3(0.25, 0.68, -0.3), 0.33, 1.1, 7, 2)
	return _put(key, m)


static func barrel() -> String:
	var key := "p_barrel"
	if _has(key): return key
	var m := _begin()
	_part(m, L.TIMBER, Color(0.62, 0.45, 0.3))
	m.cylinder(Vector3.ZERO, 0.29, 0.34, 0.42, 10, false)
	m.cylinder(Vector3(0, 0.42, 0), 0.34, 0.29, 0.42, 10, true)
	_part(m, L.IRON, Color(0.3, 0.28, 0.26))
	for y in [0.06, 0.4, 0.76]:
		m.cylinder(Vector3(0, y, 0), 0.305 + (0.035 if absf(y - 0.4) < 0.1 else 0.0), 0.305 + (0.035 if absf(y - 0.4) < 0.1 else 0.0), 0.05, 10, false)
	return _put(key, m)


static func crates(v: int) -> String:
	var key := "p_crates|%d" % v
	if _has(key): return key
	var m := _begin()
	var rng := RandomNumberGenerator.new(); rng.seed = 31 + v
	var n := 3 + v * 2
	for i in range(n):
		var s := rng.randf_range(0.5, 0.8)
		var p := Vector3(rng.randf_range(-0.7, 0.7), 0.0, rng.randf_range(-0.4, 0.4))
		if i >= 3: p.y = s * 0.9
		_part(m, L.TIMBER, Color(0.75, 0.6, 0.42).darkened(rng.randf() * 0.2))
		m.rbox(p + Vector3(0, s * 0.5, 0), Vector3(s, s * 0.8, s * 0.8), Basis(Vector3.UP, rng.randf_range(-0.3, 0.3)))
	if v == 2:
		_part(m, L.TIMBER, Color(0.62, 0.45, 0.3))
		m.cylinder(Vector3(1.0, 0, 0.2), 0.29, 0.34, 0.8, 10, true)
	return _put(key, m)


# ---------------------------------------------------------------- lanes
## A washing line across a lane between two facades (length in metres, centred), hung with sheets
## and shirts in fixed colours.
static func washing(length: int) -> String:
	var key := "p_washing|%d" % length
	if _has(key): return key
	var m := _begin()
	var half := length * 0.5
	_part(m, L.IRON, Color(0.3, 0.3, 0.3))
	m.box(Vector3(-half, -0.015, -0.015), Vector3(half, 0.015, 0.015))
	var cols := [Color(0.97, 0.97, 0.95), Color(0.85, 0.3, 0.3), Color(0.35, 0.55, 0.8), Color(0.95, 0.85, 0.4), Color(0.97, 0.97, 0.95), Color(0.55, 0.75, 0.5)]
	var rng := RandomNumberGenerator.new(); rng.seed = length * 7
	var x := -half + 0.4
	while x < half - 0.6:
		var w := rng.randf_range(0.35, 0.9)
		var h := rng.randf_range(0.45, 1.0)
		_part(m, L.CANVAS, cols[rng.randi() % cols.size()])
		m.quad(Vector3(x, -h, 0.0), Vector3(x + w, -h, 0.0), Vector3(x + w, 0.0, 0.0), Vector3(x, 0.0, 0.0))
		m.quad(Vector3(x + w, -h, 0.0), Vector3(x, -h, 0.0), Vector3(x, 0.0, 0.0), Vector3(x + w, 0.0, 0.0))
		x += w + rng.randf_range(0.15, 0.5)
	return _put(key, m, true)


# ---------------------------------------------------------------- the harbour
## A boat hull lofted through U sections from the transom stern to a raked stem: `length` along
## +z (bow forward), `beam`, `depth` (keel to gunwale). Painted hull (flag 1), a white sheer
## stripe, a timber deck; a fishing boat gets a wheelhouse, a mast and a pile of nets.
static func boat(length: float, beam: float, depth: float, fishing: bool, v: int) -> String:
	var key := "p_boat|%d|%d|%d" % [roundi(length * 10), int(fishing), v]
	if _has(key): return key
	var m := _begin()
	var ns := 9
	var rings: Array = []
	for i in range(ns + 1):
		var t := float(i) / ns                            # 0 stern .. 1 bow
		var z := (t - 0.5) * length
		var w := beam * 0.5 * (1.0 - pow(maxf(t - 0.35, 0.0) / 0.65, 1.8)) * (0.86 + 0.14 * sin(minf(t * 3.0, 1.0) * PI * 0.5))
		w = maxf(w, 0.02)
		var sheer := depth * (0.55 + 0.45 * pow(t, 2.2)) + (0.08 if t < 0.05 else 0.0)
		var keel := -depth * 0.45 * (1.0 - pow(t, 3.0)) * (0.7 + 0.3 * sin(t * PI))
		rings.append([Vector3(-w, sheer, z), Vector3(-w * 0.82, keel * 0.35, z), Vector3(0, keel, z), Vector3(w * 0.82, keel * 0.35, z), Vector3(w, sheer, z)])
	_part(m, L.TIMBER, Color(1, 1, 1), 1)
	for i in range(ns):
		var a: Array = rings[i]; var b: Array = rings[i + 1]
		for c in range(4):
			m.quad(a[c], b[c], b[c + 1], a[c + 1])
			m.quad(a[c + 1], b[c + 1], b[c], a[c])
	# the transom
	var st: Array = rings[0]
	for c in range(1, 4):
		m.tri(st[0], st[c], st[c + 1])
		m.tri(st[0], st[c + 1], st[c])
	# the sheer stripe and rubbing strake
	_part(m, L.PLASTER, Color(0.95, 0.94, 0.9) if v != 1 else Color(0.95, 0.8, 0.25))
	for i in range(ns):
		var a: Array = rings[i]; var b: Array = rings[i + 1]
		for side in [0, 4]:
			var p0: Vector3 = a[side]; var p1: Vector3 = b[side]
			var o := Vector3(0.03 if side == 4 else -0.03, 0, 0)
			m.quad(p0 + o + Vector3(0, -0.22, 0), p1 + o + Vector3(0, -0.22, 0), p1 + o, p0 + o)
			m.quad(p1 + o + Vector3(0, -0.22, 0), p0 + o + Vector3(0, -0.22, 0), p0 + o, p1 + o)
	# deck / thwarts
	_part(m, L.TIMBER, Color(0.78, 0.66, 0.5))
	var dy := depth * 0.5
	if fishing:
		m.box(Vector3(-beam * 0.42, dy, -length * 0.46), Vector3(beam * 0.42, dy + 0.06, length * 0.28), 4)
	else:
		for k in range(3):
			var zz := (-0.3 + k * 0.3) * length
			m.box(Vector3(-beam * 0.4, dy * 0.8, zz - 0.12), Vector3(beam * 0.4, dy * 0.8 + 0.05, zz + 0.12))
	if fishing:
		# wheelhouse
		_part(m, L.PLASTER, Color(0.96, 0.95, 0.9))
		var wz := -length * 0.12
		m.box(Vector3(-0.8, dy, wz - 0.9), Vector3(0.8, dy + 1.7, wz + 0.9), 63 - 8)
		_part(m, L.GLASS, Color(0.3, 0.4, 0.45))
		m.box(Vector3(-0.7, dy + 1.0, wz + 0.9), Vector3(0.7, dy + 1.5, wz + 0.92), 16)
		m.box(Vector3(-0.82, dy + 1.0, wz - 0.6), Vector3(-0.8, dy + 1.5, wz + 0.6), 2)
		m.box(Vector3(0.8, dy + 1.0, wz - 0.6), Vector3(0.82, dy + 1.5, wz + 0.6), 1)
		_part(m, L.ROOF_TILE, Color(0.55, 0.2, 0.15))
		m.box(Vector3(-0.9, dy + 1.7, wz - 1.0), Vector3(0.9, dy + 1.8, wz + 1.0))
		# mast, boom and a derrick line
		_part(m, L.TIMBER, Color(0.75, 0.62, 0.45))
		m.cylinder(Vector3(0, dy, length * 0.2), 0.08, 0.06, 5.5, 6, true)
		m.rbox(Vector3(0, dy + 2.2, length * 0.2 - 1.3), Vector3(0.07, 0.07, 2.6), Basis(Vector3.RIGHT, 0.5))
		# nets and floats on the after deck
		_part(m, L.CANVAS, Color(0.25, 0.38, 0.3))
		m.dome(Vector3(0.1, dy + 0.05, -length * 0.36), 0.8, 0.6, 8, 2)
		_part(m, L.PLASTER, Color(0.95, 0.5, 0.15))
		for k in range(4):
			m.dome(Vector3(-0.4 + k * 0.25, dy + 0.4, -length * 0.36 + (k % 2) * 0.3), 0.1, 1.0, 5, 2)
	else:
		# an outboard on the transom, oars on the thwarts
		_part(m, L.IRON, Color(0.2, 0.22, 0.25))
		m.box(Vector3(-0.15, dy * 0.2, -length * 0.5 - 0.35), Vector3(0.15, dy + 0.5, -length * 0.5 - 0.05))
		_part(m, L.TIMBER, Color(0.75, 0.62, 0.45))
		m.rbox(Vector3(0.3, dy * 0.9, 0.0), Vector3(0.06, 0.04, length * 0.55), Basis(Vector3.UP, 0.08))
	return _put(key, m, true)


static func net_rack() -> String:
	var key := "p_net_rack"
	if _has(key): return key
	var m := _begin()
	_part(m, L.TIMBER, DARK_WOOD)
	for x in [-2.0, 0.0, 2.0]:
		m.box(Vector3(x - 0.06, 0, -0.06), Vector3(x + 0.06, 2.1, 0.06))
	m.box(Vector3(-2.1, 2.0, -0.07), Vector3(2.1, 2.1, 0.07))
	# nets hung over the bar: two drapes and a sag
	_part(m, L.CANVAS, Color(0.3, 0.42, 0.38))
	for s in [-1.0, 1.0]:
		m.quad(Vector3(-1.9, 0.4, 0.3 * s), Vector3(1.9, 0.4, 0.3 * s), Vector3(1.9, 2.05, 0.05 * s), Vector3(-1.9, 2.05, 0.05 * s))
		m.quad(Vector3(1.9, 0.4, 0.3 * s), Vector3(-1.9, 0.4, 0.3 * s), Vector3(-1.9, 2.05, 0.05 * s), Vector3(1.9, 2.05, 0.05 * s))
	_part(m, L.PLASTER, Color(0.95, 0.55, 0.15))
	for k in range(6):
		m.dome(Vector3(-1.7 + k * 0.68, 0.45, 0.3), 0.09, 1.0, 5, 2)
	return _put(key, m)


static func lobster_pots() -> String:
	var key := "p_lobster_pots"
	if _has(key): return key
	var m := _begin()
	_part(m, L.TIMBER, Color(0.55, 0.45, 0.32))
	var at := [Vector3(-0.35, 0, 0), Vector3(0.35, 0, 0.05), Vector3(0, 0.46, 0.02), Vector3(0.1, 0, -0.45)]
	for p in at:
		var keep := m.xf
		m.xf = keep * Transform3D(Basis(Vector3.BACK, PI * 0.5), p + Vector3(0.25, 0.22, 0))
		m.cylinder(Vector3.ZERO, 0.22, 0.22, 0.5, 8, true, true)
		m.xf = keep
	_part(m, L.CANVAS, Color(0.8, 0.72, 0.5))
	m.cylinder(Vector3(0.6, 0, -0.4), 0.3, 0.3, 0.12, 10, true)      # a coil of rope
	return _put(key, m)


## A timber jetty on piles (length in metres along -z from the quay edge at z = 0), with a ladder
## and bollards; its deck is walkable (OuterProps gives it a box collider).
static func jetty(length: int) -> String:
	var key := "p_jetty|%d" % length
	if _has(key): return key
	var m := _begin()
	var w := 1.6
	_part(m, L.TIMBER, Color(0.66, 0.55, 0.42))
	m.box(Vector3(-w, 2.2, -length), Vector3(w, 2.45, 0.5))
	_part(m, L.TIMBER, DARK_WOOD)
	var k := 0.0
	while k <= length:
		for x in [-w + 0.15, w - 0.15]:
			m.cylinder(Vector3(x, -3.0, -k), 0.14, 0.14, 5.6, 6, true)
		m.box(Vector3(-w, 1.85, -k - 0.1), Vector3(w, 2.2, -k + 0.1))
		k += 4.0
	_part(m, L.IRON, Color(0.22, 0.22, 0.24))
	for z in [-length * 0.33, -length * 0.66, -length + 0.5]:
		for x in [-w + 0.3, w - 0.3]:
			m.cylinder(Vector3(x, 2.45, z), 0.1, 0.13, 0.3, 8, true)
	return _put(key, m, true)


## A steel harbour crane on a portal gantry (the working quay of Puerto Alto): legs straddle the
## quay's rails, a machinery house, a luffing jib out over the water (-z).
static func crane_port() -> String:
	var key := "p_crane_port"
	if _has(key): return key
	var m := _begin()
	var steel := Color(0.92, 0.55, 0.18)
	_part(m, L.IRON, steel)
	for x in [-2.6, 2.6]:
		for z in [-2.6, 2.6]:
			m.box(Vector3(x - 0.22, 0, z - 0.22), Vector3(x + 0.22, 7.0, z + 0.22))
		m.rbox(Vector3(x, 3.5, 0), Vector3(0.12, 0.12, 7.2), Basis(Vector3.RIGHT, 0.95))
	m.box(Vector3(-3.0, 7.0, -3.0), Vector3(3.0, 7.6, 3.0))
	m.cylinder(Vector3(0, 7.6, 0), 1.4, 1.4, 0.6, 12, true)
	_part(m, L.PLASTER, Color(0.9, 0.88, 0.82))
	m.box(Vector3(-1.6, 8.2, -1.2), Vector3(1.6, 10.8, 3.2))
	_part(m, L.GLASS, Color(0.3, 0.4, 0.45))
	m.box(Vector3(-1.2, 9.3, -1.22), Vector3(1.2, 10.4, -1.2), 32)
	_part(m, L.IRON, steel)
	# the jib: two chords in a long lattice box, raised at 35 degrees, out over -z
	var jb := Basis(Vector3.RIGHT, 0.62)          # luffed up: the jib climbs out over -z
	var root := Vector3(0, 9.0, -1.0)
	var jl := 26.0
	for x in [-0.55, 0.55]:
		m.rbox(root + jb * Vector3(x, 0, -jl * 0.5), Vector3(0.18, 0.18, jl), jb)
		m.rbox(root + jb * Vector3(x, 0.9, -jl * 0.5), Vector3(0.12, 0.12, jl), jb)
	for k in range(12):
		var z := -jl * (k + 0.5) / 12.0
		m.rbox(root + jb * Vector3(0, 0.45, z), Vector3(1.1, 0.08, 0.08), jb)
		m.rbox(root + jb * Vector3(0.55, 0.45, z), Vector3(0.06, 0.9, 0.06), jb * Basis(Vector3.RIGHT, 0.6))
	var tip := root + jb * Vector3(0, 0, -jl)
	_part(m, L.IRON, Color(0.2, 0.2, 0.2))
	m.box(Vector3(-0.02, 1.5, tip.z - 0.02), Vector3(0.02, tip.y, tip.z + 0.02))
	_part(m, L.IRON, Color(0.9, 0.75, 0.2))
	m.box(Vector3(-0.35, 1.2, tip.z - 0.25), Vector3(0.35, 1.5, tip.z + 0.25))
	return _put(key, m, true)


# ---------------------------------------------------------------- the country
## Hay: a round bale (0), a stack of square bales (1), a traditional stook (2).
static func haybale(v: int) -> String:
	var key := "p_hay|%d" % v
	if _has(key): return key
	var m := _begin()
	_part(m, L.CANVAS, Color(0.93, 0.8, 0.5))
	if v == 0:
		_cyl_xf(m, Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0.6, 0.75, 0)), 0.75, 0.75, 1.2, 14)
	elif v == 1:
		for k in range(5):
			var p := Vector3(-0.55 + (k % 3) * 0.55 + (0.27 if k >= 3 else 0.0), 0.2 + (0.4 if k >= 3 else 0.0), 0)
			m.cbox(p + Vector3(0, 0.0, 0), Vector3(0.52, 0.4, 0.9))
	else:
		m.cylinder(Vector3.ZERO, 0.9, 0.55, 1.1, 10, false)
		m.dome(Vector3(0, 1.1, 0), 0.55, 1.6, 10, 3)
	return _put(key, m, true)


## A 3 m run of dry-stone field wall (rubble, a rough coping of rounded stones).
static func field_wall() -> String:
	var key := "p_field_wall"
	if _has(key): return key
	var m := _begin()
	_part(m, L.RUBBLE, Color(0.86, 0.83, 0.77))
	m.box(Vector3(-1.55, -0.2, -0.28), Vector3(1.55, 0.8, 0.28), 63 - 8)
	_part(m, L.RUBBLE, Color(0.8, 0.78, 0.72))
	var rng := RandomNumberGenerator.new(); rng.seed = 5
	for i in range(7):
		m.dome(Vector3(-1.4 + i * 0.47, 0.78, rng.randf_range(-0.06, 0.06)), rng.randf_range(0.18, 0.26), 0.8, 6, 2)
	return _put(key, m, true)


## A kitchen garden plot: a low stone edge, soil beds with rows of greens, bean canes, a fence.
static func garden(v: int) -> String:
	var key := "p_garden|%d" % v
	if _has(key): return key
	var m := _begin()
	_part(m, L.RUBBLE, Color(0.85, 0.8, 0.72))
	m.box(Vector3(-4.0, 0, -6.0), Vector3(4.0, 0.25, -5.8))
	m.box(Vector3(-4.0, 0, 5.8), Vector3(4.0, 0.25, 6.0))
	m.box(Vector3(-4.0, 0, -6.0), Vector3(-3.8, 0.25, 6.0))
	m.box(Vector3(3.8, 0, -6.0), Vector3(4.0, 0.25, 6.0))
	_part(m, L.ADOBE, Color(0.55, 0.42, 0.32))
	m.box(Vector3(-3.8, 0, -5.8), Vector3(3.8, 0.12, 5.8), 4)
	var greens := [Color(0.35, 0.6, 0.25), Color(0.45, 0.68, 0.3), Color(0.3, 0.5, 0.28)]
	for r in range(9):
		var x := -3.3 + r * 0.82
		_part(m, L.TIMBER, greens[(r + v) % 3])
		if (r + v) % 4 == 3:
			# canes with beans
			_part(m, L.TIMBER, Color(0.7, 0.62, 0.45))
			for k in range(6):
				m.box(Vector3(x - 0.02, 0.1, -4.6 + k * 1.8 - 0.02), Vector3(x + 0.02, 1.9, -4.6 + k * 1.8 + 0.02))
			_part(m, L.TIMBER, Color(0.3, 0.55, 0.25))
			m.box(Vector3(x - 0.15, 0.5, -5.0), Vector3(x + 0.15, 1.7, 5.0), 63 - 8)
		else:
			for k in range(10):
				m.dome(Vector3(x, 0.1, -5.0 + k * 1.1), 0.24 + 0.06 * ((k + r) % 3), 0.8, 6, 2)
	return _put(key, m)
