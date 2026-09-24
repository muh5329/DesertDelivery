class_name OuterGround
extends RefCounted
## The outer world's ground, answered exactly the way it is drawn and collided with.
##
## Data (data/outer, written by world/mapgen/outer.py): a 2001 x 2001 float32 heightfield at
## 12.5 m (`height.f32`), RGBA maps at the same grid (`splat.png`, `aux.png`: forest, flatten,
## biome, dryness), a 25 m tint (`tint.png`), a 6.1 m road mask for the far shader (`roads.png`),
## a 64 m tileable micro-relief tile (`micro.png`) and the plan (`plan.json`).
##
## The surface is triangles on a 6.25 m LATTICE (half the data spacing): each lattice point is the
## bilinear data height plus micro relief x (1 - flatten), and each lattice cell is split along the
## same diagonal as the render patches and the collision tiles (lower triangle u + v <= 1). The GPU
## terrain (outer_terrain.gdshader), the collision tiles and `height_at` all evaluate this one
## definition, so the bike stands on exactly what is drawn. world/mapgen/outer.py (`surface_at`)
## mirrors it for the plot and road heights it writes.

const N := 2001
const STEP := 12.5
const ORIGIN := -12500.0
const HALF := 12500.0
const LAT := 6.25
const LN := 4001                  # lattice points per side
const MICRO_N := 256
const SEA_FLOOR := -40.0
const DIR := "res://data/outer/"

var heights := PackedFloat32Array()
var aux := PackedByteArray()      # RGBA8 N*N: R forest, G flatten, B biome id, A dryness
var splat := PackedByteArray()    # RGBA8 N*N: R rock, G sand, B farmland, A snow
var micro := PackedByteArray()    # L8 256*256
var micro_amp := 0.45
var plan: Dictionary = {}
var minmax := PackedFloat32Array()   # 128 x 128 x (min, max): 200 m leaves over [-12800, 12800]
var height_image: Image
var aux_image: Image
var splat_image: Image
var tint_image: Image
var roads_image: Image
var micro_image: Image
var load_ms := 0


func load_data() -> bool:
	var t0 := Time.get_ticks_msec()
	var f := FileAccess.open(DIR + "height.f32", FileAccess.READ)
	if f == null:
		push_error("OuterGround: %sheight.f32 missing - run world/mapgen/outer.py" % DIR)
		return false
	var raw := f.get_buffer(f.get_length())
	heights = raw.to_float32_array()
	if heights.size() != N * N:
		push_error("OuterGround: height.f32 has %d samples, want %d" % [heights.size(), N * N])
		return false
	height_image = Image.create_from_data(N, N, false, Image.FORMAT_RF, raw)
	aux_image = _png("aux.png"); splat_image = _png("splat.png"); tint_image = _png("tint.png")
	roads_image = _png("roads.png"); micro_image = _png("micro.png")
	if aux_image == null or splat_image == null or micro_image == null: return false
	aux_image.convert(Image.FORMAT_RGBA8); splat_image.convert(Image.FORMAT_RGBA8)
	micro_image.convert(Image.FORMAT_L8)
	aux = aux_image.get_data(); splat = splat_image.get_data(); micro = micro_image.get_data()
	var mf := FileAccess.open(DIR + "minmax.f32", FileAccess.READ)
	if mf: minmax = mf.get_buffer(mf.get_length()).to_float32_array()
	var pf := FileAccess.open(DIR + "plan.json", FileAccess.READ)
	if pf:
		var parsed: Variant = JSON.parse_string(pf.get_as_text())
		if parsed is Dictionary: plan = parsed
	if plan.has("surface"): micro_amp = float(plan.surface.get("micro_amp", micro_amp))
	load_ms = Time.get_ticks_msec() - t0
	return true


func _png(file: String) -> Image:
	var bytes := FileAccess.get_file_as_bytes(DIR + file)
	if bytes.is_empty():
		push_error("OuterGround: %s%s missing" % [DIR, file]); return null
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK: return null
	return img


## One lattice point (integer lattice coordinates, 0..LN-1): bilinear data + masked micro relief.
func lattice(I: int, J: int) -> float:
	I = clampi(I, 0, LN - 1); J = clampi(J, 0, LN - 1)
	var i0 := I >> 1; var j0 := J >> 1
	var k := j0 * N + i0
	var h: float; var fl: float
	if (I & 1) == 0:
		if (J & 1) == 0:
			h = heights[k]; fl = aux[k * 4 + 1]
		else:
			h = (heights[k] + heights[k + N]) * 0.5; fl = (aux[k * 4 + 1] + aux[(k + N) * 4 + 1]) * 0.5
	elif (J & 1) == 0:
		h = (heights[k] + heights[k + 1]) * 0.5; fl = (aux[k * 4 + 1] + aux[(k + 1) * 4 + 1]) * 0.5
	else:
		h = (heights[k] + heights[k + 1] + heights[k + N] + heights[k + N + 1]) * 0.25
		fl = (aux[k * 4 + 1] + aux[(k + 1) * 4 + 1] + aux[(k + N) * 4 + 1] + aux[(k + N + 1) * 4 + 1]) * 0.25
	var m := micro[posmod(J * 25 - 50000, MICRO_N) * MICRO_N + posmod(I * 25 - 50000, MICRO_N)]
	return h + (m - 128.0) / 127.0 * micro_amp * (1.0 - fl / 255.0)


## The ground height: the lattice triangle under (x, z). Beyond the world: the deep sea floor.
func height_at(x: float, z: float) -> float:
	if absf(x) > HALF or absf(z) > HALF: return SEA_FLOOR
	var gx := (x - ORIGIN) / LAT; var gz := (z - ORIGIN) / LAT
	var I := clampi(int(floor(gx)), 0, LN - 2); var J := clampi(int(floor(gz)), 0, LN - 2)
	var u := gx - I; var v := gz - J
	var b := lattice(I + 1, J); var c := lattice(I, J + 1)
	if u + v <= 1.0:
		var a := lattice(I, J)
		return a + (b - a) * u + (c - a) * v
	var d := lattice(I + 1, J + 1)
	return d + (c - d) * (1.0 - u) + (b - d) * (1.0 - v)


func normal_at(x: float, z: float) -> Vector3:
	var e := 1.0
	return Vector3(height_at(x - e, z) - height_at(x + e, z), 2.0 * e, height_at(x, z - e) - height_at(x, z + e)).normalized()


## Smooth data height (bilinear, no micro relief): for scatter and far queries.
func data_height(x: float, z: float) -> float:
	var gx := clampf((x - ORIGIN) / STEP, 0.0, N - 1.0001); var gz := clampf((z - ORIGIN) / STEP, 0.0, N - 1.0001)
	var i := int(gx); var j := int(gz); var u := gx - i; var v := gz - j
	var k := j * N + i
	return lerpf(lerpf(heights[k], heights[k + 1], u), lerpf(heights[k + N], heights[k + N + 1], u), v)


func _nearest(x: float, z: float) -> int:
	var i := clampi(int(round((x - ORIGIN) / STEP)), 0, N - 1)
	var j := clampi(int(round((z - ORIGIN) / STEP)), 0, N - 1)
	return j * N + i


func biome_at(x: float, z: float) -> int:
	if absf(x) > HALF or absf(z) > HALF: return Terrain.Biome.SEA
	return aux[_nearest(x, z) * 4 + 2]


## 0..1 forest density, flatten (roads and pads), dryness; splat weights (rock, sand, farm, snow).
func forest_at(x: float, z: float) -> float: return aux[_nearest(x, z) * 4] / 255.0
func flatten_at(x: float, z: float) -> float: return aux[_nearest(x, z) * 4 + 1] / 255.0
func dryness_at(x: float, z: float) -> float: return aux[_nearest(x, z) * 4 + 3] / 255.0
func splat_at(x: float, z: float) -> Color:
	var k := _nearest(x, z) * 4
	return Color(splat[k] / 255.0, splat[k + 1] / 255.0, splat[k + 2] / 255.0, splat[k + 3] / 255.0)


## Road distance proxy from the flatten mask (the core's `road_dist_at` contract: < 5.5 on a road).
func road_dist_at(x: float, z: float) -> float:
	var f := flatten_at(x, z)
	return 2.0 if f > 0.95 else (8.0 if f > 0.4 else 40.0)


## Min / max ground height of a terrain LOD node: level 0 = the 200 m leaves (128 x 128 over
## [-12800, 12800]), level l = (128 >> l)^2 nodes of 200 * 2^l m.
var _pyramid: Array[PackedFloat32Array] = []


func build_pyramid() -> void:
	_pyramid.clear()
	if minmax.size() != 128 * 128 * 2:
		minmax = PackedFloat32Array(); minmax.resize(128 * 128 * 2)
		for k in range(128 * 128): minmax[k * 2] = -40.0; minmax[k * 2 + 1] = 1400.0
	_pyramid.append(minmax)
	var n := 128
	while n > 1:
		var prev: PackedFloat32Array = _pyramid[-1]
		var m := n >> 1
		var out := PackedFloat32Array(); out.resize(m * m * 2)
		for j in range(m):
			for i in range(m):
				var lo := INF; var hi := -INF
				for dj in range(2):
					for di in range(2):
						var k := ((j * 2 + dj) * n + i * 2 + di) * 2
						lo = minf(lo, prev[k]); hi = maxf(hi, prev[k + 1])
				out[(j * m + i) * 2] = lo; out[(j * m + i) * 2 + 1] = hi
		_pyramid.append(out)
		n = m


func node_range(level: int, i: int, j: int) -> Vector2:
	if _pyramid.is_empty(): build_pyramid()
	var n := 128 >> level
	var k := (clampi(j, 0, n - 1) * n + clampi(i, 0, n - 1)) * 2
	var lvl: PackedFloat32Array = _pyramid[level]
	return Vector2(lvl[k], lvl[k + 1])
