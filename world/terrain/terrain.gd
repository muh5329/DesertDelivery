class_name Terrain
extends Node3D
## Island terrain driven by `data/island_map.png` (world/mapgen: extract.py reads the reference
## painting, expand.py grows it to the 1248 m world): R = height, G = biome class, B = tree density.
## On top of that map: noise relief per biome, dirt roads stamped along Curve3D paths (with bridge
## spans where a road crosses water), flat pads for the hubs. The result is a 3 m heightfield
## (`heights`) that the road / pad / hub logic works on.
##
## Rendering and collision are handed to the Terrain3D plugin (`_build_terrain3d`): the heightfield
## is resampled to 1.5 m with a little per-biome micro relief, every cell gets a control-map entry
## (base texture by biome, rock on slopes, slab patches on the steepest faces, rubble at cliff
## feet, dirt + gravel shoulders on roads, soil strips in the vineyards) and a colour-map tint
## (biome palette, field strips, tyre ruts, contact darkening under canopy and at cliff feet,
## cavity darkening in gullies, depth banding), and Terrain3D draws it with PBR textures, normal maps
## and a clipmap LOD, and builds the physics collision. Ground queries (`height_at`, `normal_at`)
## read Terrain3D's data so gameplay stands exactly on what is drawn. If the plugin is missing the
## old flat-shaded facet mesh + HeightMapShape3D fallback is used (`_build_fallback_mesh`).
##
## Biomes: SEA, LIMESTONE (pale mountains, NW), FOREST (pines and scrub), FARM (vineyards, SW),
## BADLANDS (red hoodoos, SE), TOWN (NE), BEACH, LAKE, DUNES (south-west shore), MOOR (the
## northern Highlands), SALTFLAT (the salinas).

enum Biome { SEA, LIMESTONE, FOREST, FARM, BADLANDS, TOWN, BEACH, LAKE, DUNES, MOOR, SALTFLAT }
enum Tex { GRASS, ROCK, DIRT, SAND, CLAY, SCRUB, SOIL, SALT, CLIFF, RUBBLE, GRAVEL }

const SIZE := 25000.0        # physical square world extent in metres
const CORE_SIZE := 1248.0         # metres, square world (3x the area of the painted 720 m island)
const CELL := 3.0            # metres per grid cell
const N := int(CORE_SIZE / CELL) + 1   # vertices per side (417)
const SEA_LEVEL := 0.0
const MAP_PATH := "res://data/island_map.png"
const TEX_DIR := "res://assets/terrain/"
const FOLIAGE_DIR := "res://assets/foliage/"

# Terrain3D layout: 2x2 regions of 512 vertices at 1.5 m cover -768..768 m, the world plus a sea rim.
const T3D_SPACING := 1.5
const T3D_REGION := 512
const T3D_HALF := T3D_SPACING * T3D_REGION        # 768
const T3D_W := T3D_REGION * 2                     # 1024 px per map

var expanse: Node3D

var heights := PackedFloat32Array()   # N*N
var road_dist := PackedFloat32Array() # distance (m) to nearest road centreline, clamped to 40
var road_h := PackedFloat32Array()    # target road height (valid where road_dist < 14)
var roads: Array[Curve3D] = []
var pads: Array[Vector3] = []          # (x, z, radius) flat courtyards for buildings
var vine_fields: Array[Rect2] = []     # the vineyard parcels (world m): ploughed soil strips only inside these
var road_samples: Array = []          # Array of PackedVector3Array (world-space samples every ~1 m)
var bridges: Array = []
## Regions ground cover leaves bare, handed in by the Island (ADR 0009): {centre, radius} discs
## and {a, b, width} strips. The terrain does not know where the Town Square is.
var keep_clear: Array = []               # {road, from, to, deck} sample ranges that are elevated (water or viaduct)
var viaducts: Array = []              # {a: Vector2, b: Vector2, deck: float} road stretches carried on arches over land

var _map_h := PackedFloat32Array()    # raw map height per cell
var _map_b := PackedByteArray()       # biome per cell
var _map_d := PackedFloat32Array()    # tree density per cell
var _n1 := FastNoiseLite.new()
var _n2 := FastNoiseLite.new()
var _n3 := FastNoiseLite.new()
var _rock := FastNoiseLite.new()

var mesh_instance: MeshInstance3D      # fallback mesh only
var static_body: StaticBody3D          # fallback collider only
var terrain3d: Terrain3D               # the Terrain3D node when the plugin is available
var _t3d_data: Terrain3DData           # its data (height / normal queries)
var _slope := PackedFloat32Array()     # 1 - normal.y per cell, from `heights`
var build_ms := {}                     # timings per stage (debug overlay)
## Slope-break cells (world xz, 1.5 m map pixels) classified while the control map is built: a
## crest is a flat cell above a steep neighbourhood (the rock lip of a cliff top), a foot a flat
## cell below one (the talus at its base). The island's crest / ledge bush lines are drawn from
## these lists instead of re-walking the whole island with 9 `normal_at` samples per 3 m cell
## (round 3: the two walks cost 2.2 s of the 18 s generation).
var crest_cells := PackedVector2Array()
var foot_cells := PackedVector2Array()


func _init() -> void:
	_n1.seed = 1337; _n1.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH; _n1.frequency = 1.0 / 70.0
	_n2.seed = 4242; _n2.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH; _n2.frequency = 1.0 / 22.0
	_n3.seed = 777;  _n3.noise_type = FastNoiseLite.TYPE_SIMPLEX;        _n3.frequency = 1.0 / 6.0
	_rock.seed = 99; _rock.noise_type = FastNoiseLite.TYPE_CELLULAR;     _rock.frequency = 1.0 / 16.0
	_rock.fractal_octaves = 2
	_load_map()


static func smoothstep(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _load_map() -> void:
	var img := Image.new()
	var err := img.load(MAP_PATH)
	_map_h.resize(N * N); _map_b.resize(N * N); _map_d.resize(N * N)
	if err != OK or img.get_width() != N:
		push_error("Terrain: could not load %s (%s); using flat sea" % [MAP_PATH, err])
		_map_h.fill(-6.0); _map_b.fill(Biome.SEA); _map_d.fill(0.0)
		return
	for j in range(N):
		for i in range(N):
			var c := img.get_pixel(i, j)
			var id := j * N + i
			_map_h[id] = c.r8 / 255.0 * 90.0 - 10.0
			_map_b[id] = c.g8
			_map_d[id] = c.b8 / 255.0


func _idx(i: int, j: int) -> int:
	return j * N + i


func world_to_grid(x: float, z: float) -> Vector2:
	return Vector2((x + CORE_SIZE * 0.5) / CELL, (z + CORE_SIZE * 0.5) / CELL)


func _bilinear(arr: PackedFloat32Array, x: float, z: float) -> float:
	var g := world_to_grid(x, z)
	var gi := clampf(g.x, 0.0, N - 1.001)
	var gj := clampf(g.y, 0.0, N - 1.001)
	var i0 := int(gi); var j0 := int(gj)
	var fx := gi - i0; var fz := gj - j0
	return lerpf(lerpf(arr[_idx(i0, j0)], arr[_idx(i0 + 1, j0)], fx), lerpf(arr[_idx(i0, j0 + 1)], arr[_idx(i0 + 1, j0 + 1)], fx), fz)


## Biome at a world position (nearest cell).
func biome_at(x: float, z: float) -> int:
	if expanse != null and maxf(absf(x), absf(z)) > CORE_SIZE * 0.5:
		return expanse.biome_at(x, z)
	var g := world_to_grid(x, z)
	var i := clampi(int(round(g.x)), 0, N - 1)
	var j := clampi(int(round(g.y)), 0, N - 1)
	return _map_b[_idx(i, j)]


## Tree density 0..1 from the painting (dark canopy = dense).
func density_at(x: float, z: float) -> float:
	return _bilinear(_map_d, x, z)


func is_land(x: float, z: float) -> bool:
	var b := biome_at(x, z)
	return b != Biome.SEA and b != Biome.LAKE


## Map height plus biome-specific relief.
func base_height(x: float, z: float) -> float:
	var h := _bilinear(_map_h, x, z)
	var b := biome_at(x, z)
	match b:
		Biome.LIMESTONE:
			# craggy ridges: cellular noise carves the massif into blocks and gullies
			var r := _rock.get_noise_2d(x * 1.2, z * 1.2)
			h += 6.0 * r + 2.0 * _n2.get_noise_2d(x, z) + 0.5 * _n3.get_noise_2d(x, z)
		Biome.BADLANDS:
			# broken ground between the hoodoo spires (the spires themselves are props)
			var k := clampf((h - 2.0) / 8.0, 0.0, 1.0)   # calm ground on the lake shore
			h += k * (3.5 * absf(_n2.get_noise_2d(x * 0.6, z * 0.6)) + 1.5 * _n1.get_noise_2d(x * 0.5, z * 0.5)) + 0.25 * _n3.get_noise_2d(x * 0.5, z * 0.5)
		Biome.FOREST:
			h += 3.0 * _n1.get_noise_2d(x, z) + 1.4 * _n2.get_noise_2d(x, z) + 0.35 * _n3.get_noise_2d(x, z)
		Biome.FARM:
			h += 1.6 * _n1.get_noise_2d(x, z) + 0.5 * _n2.get_noise_2d(x, z)
		Biome.TOWN:
			h += 2.0 * _n1.get_noise_2d(x, z) + 0.6 * _n2.get_noise_2d(x, z)
		Biome.BEACH:
			h += 0.3 * _n2.get_noise_2d(x, z)
		Biome.DUNES:
			# wind-ridged dunes: sharp crests from |noise|, softened by a second octave
			h += 2.6 * absf(_n1.get_noise_2d(x * 1.4, z * 1.4)) + 0.9 * _n2.get_noise_2d(x, z) + 0.2 * _n3.get_noise_2d(x, z)
		Biome.MOOR:
			# heath over broken limestone: rocky hummocks and peat hollows
			h += 4.5 * _n1.get_noise_2d(x, z) + 3.0 * _rock.get_noise_2d(x * 0.9, z * 0.9) + 0.6 * _n3.get_noise_2d(x, z)
		Biome.SALTFLAT:
			h += 0.05 * _n3.get_noise_2d(x, z)   # dead flat
		_:
			h += 0.4 * _n2.get_noise_2d(x, z)
	# a stream gorge under each viaduct so the arches have something to stride over
	for v in viaducts:
		var q := Vector2(x, z)
		var ab: Vector2 = v.b - v.a
		var t: float = clampf((q - v.a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var d: float = (v.a + ab * t).distance_to(q)
		var along := smoothstep(0.0, 0.18, t) * (1.0 - smoothstep(0.82, 1.0, t))
		h -= 7.0 * (1.0 - smoothstep(3.0, 16.0, d)) * along
	return h


## Ground height at world XZ: Terrain3D's data once it is built (exactly what is drawn and
## collided with), the 3 m heightfield before that or without the plugin.
func height_at(x: float, z: float) -> float:
	if expanse != null and maxf(absf(x), absf(z)) > CORE_SIZE * 0.5:
		return expanse.height_at(x, z)
	if _t3d_data != null:
		var h: float = _t3d_data.get_height(Vector3(x, 0.0, z))
		if not is_nan(h): return h
	return _bilinear(heights, x, z)


## The 3 m field the build cut (roads, ramps, pads) — what every build stage asks; `height_at`
## is the ground as drawn and collided (ADR 0009).
func heightfield_at(x: float, z: float) -> float:
	return _bilinear(heights, x, z)


## How far the drawn ground strays from the heightfield the build cut (worst case, metres),
## measured along the roads — the surfaces the build cut and the courier rides. Off-road the
## 1.5 m resample adds deliberate relief (micro relief, crest lips), which is not drift.
func heightfield_drift() -> float:
	var worst := 0.0
	for r in range(road_samples.size()):
		var samples: PackedVector3Array = road_samples[r]
		var skip := PackedInt32Array()   # deck spans: the courier rides the deck there, not the ground
		for b in bridges:
			if b.road != r: continue
			var span: Vector2i = b.deck_span(self)
			skip.append(span.x); skip.append(span.y)
		for k in range(0, samples.size(), 4):
			# the heightfield the build cut is the core's: outer roads stand on the outer ground
			if maxf(absf(samples[k].x), absf(samples[k].z)) > CORE_SIZE * 0.5 - 6.0: continue
			var on_deck := false
			for q in range(0, skip.size(), 2):
				if k >= skip[q] - 8 and k <= skip[q + 1] + 8: on_deck = true; break
			if on_deck: continue
			var p := samples[k]
			var hf := heightfield_at(p.x, p.z)
			if hf < 0.5: continue
			worst = maxf(worst, absf(height_at(p.x, p.z) - hf))
	return worst


## Validates data/island_map.json (written by expand.py) against what this runtime assumes.
## Returns "" when it matches, else a named mismatch.
func map_contract_error() -> String:
	var f := FileAccess.open("res://data/island_map.json", FileAccess.READ)
	if f == null: return "data/island_map.json is missing"
	var parsed = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary): return "data/island_map.json is not a JSON object"
	var m: Dictionary = parsed
	if not is_equal_approx(float(m.get("size", -1.0)), CORE_SIZE): return "size %s != %s" % [m.get("size"), CORE_SIZE]
	if not is_equal_approx(float(m.get("cell", -1.0)), CELL): return "cell %s != %s" % [m.get("cell"), CELL]
	if int(m.get("grid", -1)) != N: return "grid %s != %d" % [m.get("grid"), N]
	if not is_equal_approx(float(m.get("height_min", 1.0)), -10.0): return "height_min %s != -10" % m.get("height_min")
	if not is_equal_approx(float(m.get("height_range", 0.0)), 90.0): return "height_range %s != 90" % m.get("height_range")
	var biomes: Dictionary = m.get("biomes", {})
	for name in Biome.keys():
		if not biomes.has(name): return "biome %s missing from the map contract" % name
		if int(biomes[name]) != Biome[name]: return "biome %s is %s in the map, %d in Terrain" % [name, biomes[name], Biome[name]]
	if biomes.size() != Biome.size(): return "map declares %d biomes, Terrain has %d" % [biomes.size(), Biome.size()]
	return ""


func normal_at(x: float, z: float) -> Vector3:
	if expanse != null and maxf(absf(x), absf(z)) > CORE_SIZE * 0.5:
		return expanse.normal_at(x, z)
	if _t3d_data != null:
		var n: Vector3 = _t3d_data.get_normal(Vector3(x, 0.0, z))
		if not is_nan(n.y): return n
	var e := 1.0
	var hl := height_at(x - e, z); var hr := height_at(x + e, z)
	var hd := height_at(x, z - e); var hu := height_at(x, z + e)
	return Vector3(hl - hr, 2.0 * e, hd - hu).normalized()


func road_dist_at(x: float, z: float) -> float:
	if maxf(absf(x), absf(z)) > CORE_SIZE * 0.5:
		return expanse.road_dist_at(x, z) if expanse != null else 40.0
	var g := world_to_grid(x, z)
	var i := clampi(int(round(g.x)), 0, N - 1)
	var j := clampi(int(round(g.y)), 0, N - 1)
	return road_dist[_idx(i, j)]


func add_road(points: Array) -> Curve3D:
	var c := Curve3D.new()
	for p in points:
		c.add_point(Vector3(p.x, 0.0, p.y))
	for k in range(c.point_count):
		var prev := c.get_point_position(maxi(k - 1, 0))
		var next := c.get_point_position(mini(k + 1, c.point_count - 1))
		var t := (next - prev) * 0.25
		c.set_point_in(k, -t)
		c.set_point_out(k, t)
	c.bake_interval = 1.0
	roads.append(c)
	return c


## Build the heightfield, stamp roads (bridging water), flatten pads, mesh + collision.
func build() -> void:
	var t_start := Time.get_ticks_msec()
	heights.resize(N * N)
	road_dist.resize(N * N)
	road_h.resize(N * N)
	road_dist.fill(40.0)
	road_h.fill(0.0)
	var half := CORE_SIZE * 0.5
	for j in range(N):
		for i in range(N):
			heights[_idx(i, j)] = base_height(i * CELL - half, j * CELL - half)

	road_samples.clear()
	bridges.clear()
	var is_bridge_sample: Array = []   # per road: PackedByteArray
	for r in range(roads.size()):
		var c: Curve3D = roads[r]
		var pts: PackedVector3Array = c.get_baked_points()
		var hs := PackedFloat32Array(); hs.resize(pts.size())
		var over_water := PackedByteArray(); over_water.resize(pts.size())
		for k in range(pts.size()):
			hs[k] = base_height(pts[k].x, pts[k].z)
			over_water[k] = 1 if hs[k] < SEA_LEVEL + 0.8 else 0
			for v in viaducts:
				var q := Vector2(pts[k].x, pts[k].z)
				var cl: Vector2 = Geometry2D.get_closest_point_to_segment(q, v.a, v.b)
				if cl.distance_to(q) < 2.5 and hs[k] < v.deck - 0.5:
					over_water[k] = 2
		# bridge spans: water runs get a flat deck level from the higher bank, with a little margin
		var k := 0
		while k < pts.size():
			if over_water[k] != 0:
				var k0 := k
				var kind := over_water[k]
				while k < pts.size() and over_water[k] == kind: k += 1
				var k1 := k - 1
				var a := hs[maxi(k0 - 6, 0)]; var b := hs[mini(k1 + 6, pts.size() - 1)]
				if kind == 1 and k1 - k0 < 14:
					# a puddle or a stream: a low causeway is stamped through it instead of a bridge
					for kk in range(k0, k1 + 1):
						hs[kk] = maxf(hs[kk], SEA_LEVEL + 1.0)
						over_water[kk] = 0
					continue
				var deck := maxf(maxf(a, b), 2.5)
				if kind == 2:
					for v in viaducts:
						var q := Vector2(pts[k0].x, pts[k0].z)
						if Geometry2D.get_closest_point_to_segment(q, v.a, v.b).distance_to(q) < 2.5: deck = v.deck
				for kk in range(k0, k1 + 1): hs[kk] = deck
				bridges.append(Bridge.new(r, PackedVector3Array(), k0, k1, deck))
			else:
				k += 1
		# smooth the land profile so grades are gentle (bridges stay flat)
		for _pass in range(2):
			var sm := PackedFloat32Array(); sm.resize(hs.size())
			var w := 12
			for kk in range(hs.size()):
				if over_water[kk] != 0: sm[kk] = hs[kk]; continue
				var acc := 0.0; var cnt := 0
				for d in range(-w, w + 1):
					var q := clampi(kk + d, 0, hs.size() - 1)
					if over_water[q] != 0: continue   # decks are not part of the land profile
					acc += hs[q]; cnt += 1
				if cnt == 0: sm[kk] = hs[kk]; continue
				sm[kk] = acc / cnt
			hs = sm
		# grade limit: no stretch steeper than 28 % (cut/fill), bridges and viaducts stay level
		for _pass in range(2):
			for kk in range(1, hs.size()):
				if over_water[kk] != 0 or over_water[kk - 1] != 0: continue
				var d := pts[kk].distance_to(pts[kk - 1]) * 0.28
				hs[kk] = clampf(hs[kk], hs[kk - 1] - d, hs[kk - 1] + d)
			for kk in range(hs.size() - 2, -1, -1):
				if over_water[kk] != 0 or over_water[kk + 1] != 0: continue
				var d := pts[kk].distance_to(pts[kk + 1]) * 0.28
				hs[kk] = clampf(hs[kk], hs[kk + 1] - d, hs[kk + 1] + d)
		# earthen ramps (20 %) up onto every deck, applied last so smoothing can't dip them
		for b in bridges:
			if b.road != r: continue
			var dist := 0.0
			for kk in range(b.from - 1, -1, -1):
				if over_water[kk] != 0: break
				dist += pts[kk].distance_to(pts[kk + 1])
				if absf(hs[kk] - b.deck) <= dist * 0.2: break
				hs[kk] = clampf(hs[kk], b.deck - dist * 0.2, b.deck + dist * 0.2)   # fill below, cut above
			dist = 0.0
			for kk in range(b.to + 1, pts.size()):
				if over_water[kk] != 0: break
				dist += pts[kk].distance_to(pts[kk - 1])
				if absf(hs[kk] - b.deck) <= dist * 0.2: break
				hs[kk] = clampf(hs[kk], b.deck - dist * 0.2, b.deck + dist * 0.2)
		var world_pts := PackedVector3Array(); world_pts.resize(pts.size())
		for kk in range(pts.size()):
			world_pts[kk] = Vector3(pts[kk].x, hs[kk], pts[kk].z)
		road_samples.append(world_pts)
		is_bridge_sample.append(over_water)
	# junctions: where a road ends on (or crosses) another road, its last samples ramp to the other
	# road's height so the two profiles agree instead of leaving a step between them
	for r in range(road_samples.size()):
		var pts: PackedVector3Array = road_samples[r]
		var ow: PackedByteArray = is_bridge_sample[r]
		for end: int in [0, pts.size() - 1]:
			var e := pts[end]
			var other_h := INF; var best := 6.0
			for r2 in range(road_samples.size()):
				if r2 == r: continue
				var p2: PackedVector3Array = road_samples[r2]
				for k2 in range(0, p2.size(), 2):
					var d := Vector2(p2[k2].x - e.x, p2[k2].z - e.z).length()
					if d < best: best = d; other_h = p2[k2].y
			if other_h == INF: continue
			var n_blend := mini(30, pts.size() - 1)
			for i in range(n_blend + 1):
				var k: int = end + i if end == 0 else end - i
				if ow[k] != 0: break
				var t := 1.0 - float(i) / n_blend
				pts[k].y = lerpf(pts[k].y, other_h, t)
		road_samples[r] = pts
	# bind each Bridge to its road's final samples (PackedVector3Array is a value type, so this
	# has to happen after the junction blending above)
	for b in bridges:
		b.samples = road_samples[b.road]
	# stamp every road into the heightfield (nearest sample wins)
	var r_cells := int(ceil(19.0 / CELL))
	for r in range(road_samples.size()):
		var pts: PackedVector3Array = road_samples[r]
		var ow: PackedByteArray = is_bridge_sample[r]
		for kk in range(pts.size()):
			if ow[kk] != 0: continue   # the ground under a bridge or viaduct is left alone
			var p := pts[kk]
			var g := world_to_grid(p.x, p.z)
			var ci := int(round(g.x)); var cj := int(round(g.y))
			for dj in range(-r_cells, r_cells + 1):
				var jj := cj + dj
				if jj < 0 or jj >= N: continue
				for di in range(-r_cells, r_cells + 1):
					var ii := ci + di
					if ii < 0 or ii >= N: continue
					var wx := ii * CELL - half; var wz := jj * CELL - half
					var d := Vector2(wx - p.x, wz - p.z).length()
					var id := _idx(ii, jj)
					if d < road_dist[id]:
						road_dist[id] = d
						road_h[id] = p.y
	for j in range(N):
		for i in range(N):
			var id := _idx(i, j)
			var d := road_dist[id]
			if d < 18.0 and (heights[id] > SEA_LEVEL - 0.5 or (d < 6.0 and road_h[id] > SEA_LEVEL + 0.5)):
				var t := 1.0 - smoothstep(5.5, 18.0, d)
				heights[id] = lerpf(heights[id], road_h[id], t)
	# under every deck the ground must stay below it: a bank or cliff that pokes through a bridge
	# or viaduct would wall the road off (cut it down within 6 m of the centreline, never raise it)
	var c_cells := int(ceil(8.0 / CELL))
	for r in range(road_samples.size()):
		var pts: PackedVector3Array = road_samples[r]
		var ow: PackedByteArray = is_bridge_sample[r]
		for kk in range(pts.size()):
			if ow[kk] == 0: continue
			var p := pts[kk]
			var g := world_to_grid(p.x, p.z)
			var ci := int(round(g.x)); var cj := int(round(g.y))
			for dj in range(-c_cells, c_cells + 1):
				var jj := cj + dj
				if jj < 0 or jj >= N: continue
				for di in range(-c_cells, c_cells + 1):
					var ii := ci + di
					if ii < 0 or ii >= N: continue
					var d := Vector2(ii * CELL - half - p.x, jj * CELL - half - p.z).length()
					if d >= 8.0: continue
					var id := _idx(ii, jj)
					# shave, never dig: the ground ends up just inside the deck slab (which is 0.9 m thick),
					# so a bank that stood above the deck becomes a cutting flush with it and a bike that
					# cuts the corner at a bridgehead only meets a kerb, not a drop
					var limit := (road_h[id] if road_dist[id] < 5.5 else p.y) - 0.2
					if heights[id] > limit:
						heights[id] = lerpf(heights[id], limit, 1.0 - smoothstep(5.0, 8.0, d))
	for pad in pads:
		var px: float = pad.x; var pz: float = pad.y; var pr: float = pad.z
		var ph := height_at(px, pz)
		var gc := world_to_grid(px, pz)
		var gid := _idx(clampi(int(round(gc.x)), 0, N - 1), clampi(int(round(gc.y)), 0, N - 1))
		if road_dist[gid] < 14.0: ph = road_h[gid]   # a pad on a road sits at road level, never a step
		var cells := int(ceil((pr + 10.0) / CELL))
		var g := world_to_grid(px, pz)
		for dj in range(-cells, cells + 1):
			for di in range(-cells, cells + 1):
				var ii := int(round(g.x)) + di; var jj := int(round(g.y)) + dj
				if ii < 0 or ii >= N or jj < 0 or jj >= N: continue
				var wx := ii * CELL - half; var wz := jj * CELL - half
				var d := Vector2(wx - px, wz - pz).length()
				var t := 1.0 - smoothstep(pr, pr + 10.0, d)
				var id := _idx(ii, jj)
				if heights[id] > SEA_LEVEL - 0.5:
					heights[id] = lerpf(heights[id], ph, t)
					if d < pr + 3.0:
						road_dist[id] = minf(road_dist[id], 2.0 + d * 0.3)
	# half-strength 3x3 blur: keeps the big shapes, takes the per-cell fizz (and the facet
	# checkerboard it causes) out of the ground; sea cells are left alone so the shoreline stays crisp
	var sm := PackedFloat32Array(); sm.resize(N * N)
	for j in range(N):
		for i in range(N):
			var id := _idx(i, j)
			if heights[id] < SEA_LEVEL - 0.3 or road_dist[id] < 8.0: sm[id] = heights[id]; continue   # roads keep their exact profile
			var acc := 0.0; var cnt := 0
			for dj in range(-1, 2):
				for di in range(-1, 2):
					var ii := clampi(i + di, 0, N - 1); var jj := clampi(j + dj, 0, N - 1)
					acc += heights[_idx(ii, jj)]; cnt += 1
			sm[id] = lerpf(heights[id], acc / cnt, 0.5)
	heights = sm
	build_ms["heightfield"] = Time.get_ticks_msec() - t_start
	_compute_slope()
	if "--facet" in OS.get_cmdline_user_args():
		_build_mesh()          # the old painterly look, for comparison renders
		_build_collision()
	else:
		_build_terrain3d()


func _vertex_color(x: float, z: float, h: float, n: Vector3, rd: float) -> Color:
	var slope := 1.0 - n.y
	var b := biome_at(x, z)
	var col: Color
	# the mixing noise is quantised to a few steps so the ground reads as flat painted patches,
	# not an airbrushed gradient
	var m: float = floor(_n2.get_noise_2d(x * 0.28 + 500.0, z * 0.28) * 3.0 + 0.5) / 3.0
	var dens: float = floor(density_at(x, z) * 3.0 + 0.5) / 3.0
	match b:
		Biome.LIMESTONE:
			# warm ivory karst with olive scrub only where the painting shows canopy
			col = Color(0.66, 0.62, 0.55).lerp(Color(0.48, 0.52, 0.32), clampf(dens * 1.2, 0.0, 1.0))
			col = col.lerp(Color(0.58, 0.56, 0.48), 0.5 * absf(m))
		Biome.FOREST:
			col = Color(0.49, 0.53, 0.31).lerp(Color(0.62, 0.59, 0.36), clampf(m + 0.5, 0.0, 1.0))
			col = col.lerp(Color(0.72, 0.68, 0.54), 0.6 * (1.0 - clampf(dens * 1.5, 0.0, 1.0)))
		Biome.FARM:
			# field parcels: ruled strips of gold, olive and green on a diagonal like the vineyards
			var strip := fmod(absf(x * 0.7 + z * 0.35), 24.0)
			var band: int = int(floor(strip / 6.0))
			var strips: Array[Color] = [Color(0.77, 0.70, 0.36), Color(0.56, 0.60, 0.31), Color(0.66, 0.62, 0.33), Color(0.45, 0.55, 0.26)]
			col = strips[band]
			# parcel boundaries: a darker hedge line every 24 m each way
			var px := fmod(absf(x + 1000.0), 26.0); var pz := fmod(absf(z + 1000.0), 22.0)
			if px < 1.6 or pz < 1.6: col = col.darkened(0.35)
		Biome.BADLANDS:
			col = Color(0.76, 0.46, 0.27).lerp(Color(0.60, 0.34, 0.19), clampf(m + 0.5, 0.0, 1.0))
		Biome.TOWN:
			col = Color(0.80, 0.75, 0.62).lerp(Color(0.52, 0.56, 0.32), clampf(dens * 1.2, 0.0, 1.0))
		Biome.BEACH:
			col = Color(0.84, 0.78, 0.60)
		Biome.LAKE:
			col = Color(0.80, 0.72, 0.52).lerp(Color(0.32, 0.52, 0.52), smoothstep(-0.2, -4.0, h))
		_:
			# seabed: bright sand in the shallows, dark blue in the deep -> turquoise ring through the water
			# three depth bands: turquoise shelf, mid blue, deep navy
			if h > -2.6: col = Color(0.62, 0.80, 0.66)
			elif h > -6.0: col = Color(0.16, 0.42, 0.56)
			else: col = Color(0.02, 0.10, 0.30)
	# bare warm rock only on the really steep faces
	if b != Biome.BADLANDS and b != Biome.SEA and b != Biome.LAKE:
		col = col.lerp(Color(0.72, 0.66, 0.54), smoothstep(0.30, 0.55, slope))
	# road dirt with two darker ruts
	var road_t := 1.0 - smoothstep(2.6, 6.0, rd)
	col = col.lerp(Color(0.66, 0.52, 0.34), road_t)
	return col


func _build_mesh() -> void:
	# Flat-shaded facets: every triangle gets its own normal and one colour (sampled at its centroid),
	# so the ground reads as hard-edged painted patches rather than an airbrushed gradient.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := CORE_SIZE * 0.5
	var verts := PackedVector3Array(); verts.resize(N * N)
	for j in range(N):
		for i in range(N):
			verts[_idx(i, j)] = Vector3(i * CELL - half, heights[_idx(i, j)], j * CELL - half)
	for j in range(N - 1):
		for i in range(N - 1):
			var a := verts[_idx(i, j)]; var b := verts[_idx(i + 1, j)]
			var c := verts[_idx(i, j + 1)]; var d := verts[_idx(i + 1, j + 1)]
			# split the quad along the diagonal that follows the terrain better (less "tent" artefacts)
			var tris: Array = [[a, b, c], [b, d, c]] if absf(a.y - d.y) < absf(b.y - c.y) else [[a, b, d], [a, d, c]]
			for t in tris:
				var p0: Vector3 = t[0]; var p1: Vector3 = t[1]; var p2: Vector3 = t[2]
				var n := (p2 - p0).cross(p1 - p0).normalized()   # clockwise front faces
				var cen := (p0 + p1 + p2) / 3.0
				var g := world_to_grid(cen.x, cen.z)
				var rd := road_dist[_idx(clampi(int(round(g.x)), 0, N - 1), clampi(int(round(g.y)), 0, N - 1))]
				var col := _vertex_color(cen.x, cen.z, cen.y, n, rd)
				for p in [p0, p1, p2]:
					st.set_normal(n)
					st.set_color(col)
					st.set_uv(Vector2(p.x, p.z) * 0.08)
					st.add_vertex(p)
	var mesh := st.commit()
	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "TerrainMesh"
	mesh_instance.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 1.0
	var noise_tex := NoiseTexture2D.new()
	var nn := FastNoiseLite.new()
	nn.seed = 5; nn.frequency = 0.06; nn.fractal_octaves = 4
	noise_tex.noise = nn
	noise_tex.width = 256; noise_tex.height = 256
	noise_tex.seamless = true
	noise_tex.color_ramp = Gradient.new()
	noise_tex.color_ramp.set_color(0, Color(0.80, 0.80, 0.80))
	noise_tex.color_ramp.set_color(1, Color(1.08, 1.08, 1.08))
	mat.albedo_texture = noise_tex
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3(0.35, 0.35, 0.35)
	mesh_instance.material_override = mat
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mesh_instance)


func _build_collision() -> void:
	static_body = StaticBody3D.new()
	static_body.name = "TerrainBody"
	var shape := HeightMapShape3D.new()
	shape.map_width = N
	shape.map_depth = N
	shape.map_data = heights
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3(CELL, 1.0, CELL)
	static_body.add_child(cs)
	add_child(static_body)


## --- Terrain3D --------------------------------------------------------------------------
## Per-cell slope (1 - normal.y) from the finished heightfield; drives the rock overlay.
func _compute_slope() -> void:
	_slope.resize(N * N)
	for j in range(N):
		for i in range(N):
			var i0 := maxi(i - 1, 0); var i1 := mini(i + 1, N - 1)
			var j0 := maxi(j - 1, 0); var j1 := mini(j + 1, N - 1)
			var dx := (heights[_idx(i1, j)] - heights[_idx(i0, j)]) / (CELL * (i1 - i0))
			var dz := (heights[_idx(i, j1)] - heights[_idx(i, j0)]) / (CELL * (j1 - j0))
			_slope[_idx(i, j)] = 1.0 - 1.0 / sqrt(1.0 + dx * dx + dz * dz)


## Base texture per biome (rock is the slope overlay, dirt the road overlay).
const BIOME_TEX := {
	Biome.SEA: Tex.SAND, Biome.LIMESTONE: Tex.SCRUB, Biome.FOREST: Tex.GRASS, Biome.FARM: Tex.GRASS,
	Biome.BADLANDS: Tex.CLAY, Biome.TOWN: Tex.SCRUB, Biome.BEACH: Tex.SAND, Biome.LAKE: Tex.SAND,
	Biome.DUNES: Tex.SAND, Biome.MOOR: Tex.GRASS, Biome.SALTFLAT: Tex.SALT,
}
## Micro relief amplitude (m) added at 1.5 m resolution, per biome. Zero on roads and pads.
const BIOME_DETAIL := {
	Biome.SEA: 0.15, Biome.LIMESTONE: 0.45, Biome.FOREST: 0.22, Biome.FARM: 0.12, Biome.BADLANDS: 0.5,
	Biome.TOWN: 0.1, Biome.BEACH: 0.12, Biome.LAKE: 0.1, Biome.DUNES: 0.3, Biome.MOOR: 0.45, Biome.SALTFLAT: 0.0,
}


func _build_terrain3d() -> void:
	var t0 := Time.get_ticks_msec()
	var t3d := Terrain3D.new()
	t3d.name = "Terrain3D"
	t3d.region_size = T3D_REGION
	t3d.vertex_spacing = T3D_SPACING
	t3d.mesh_lods = 7
	t3d.mesh_size = 48
	t3d.cast_shadows = RenderingServer.SHADOW_CASTING_SETTING_ON
	add_child(t3d)
	terrain3d = t3d
	# textures
	t3d.assets = Terrain3DAssets.new()
	_build_texture_assets(t3d.assets)
	t3d.material.world_background = Terrain3DMaterial.NONE   # the sea plane and the abyss take over past the regions
	# a softer blend than before: the road edge and the rock line should be ragged, not a seam
	t3d.material.set_shader_param(&"blend_sharpness", 0.72)
	# steep faces sample the textures projected along the face (uv = along-slope, -y) instead of
	# the planar xz uv stretched 2-3x down a 60 deg slope (r3 item 11: "vertical streaks, a wax
	# curtain"); faces steeper than ~32 deg (normal.y <= 0.85) switch over
	t3d.material.set_shader_param(&"enable_projection", true)
	t3d.material.set_shader_param(&"projection_threshold", 0.85)
	# macro variation: two broad patch noises (~80 m and ~35 m, the shader's uv is in vertices)
	# that push the ground toward a warm shadowed tan and a cool grey; big patches read painterly
	t3d.material.set_shader_param(&"enable_macro_variation", true)
	# (critique r1: #c8b9a2 warm / #7f7a76 dark-grey at ~50 m so the plateau is not one flat bone)
	t3d.material.set_shader_param(&"macro_variation1", Color("c8b9a2"))
	# (critique r2 item 8: the dark-grey patch at 25 % not 50 % - the slopes read as mud)
	t3d.material.set_shader_param(&"macro_variation2", Color("a29e9a"))
	t3d.material.set_shader_param(&"noise1_scale", 0.28)
	t3d.material.set_shader_param(&"noise2_scale", 0.55)
	t3d.material.set_shader_param(&"macro_variation_slope", 0.5)
	build_ms["t3d_setup"] = Time.get_ticks_msec() - t0; t0 = Time.get_ticks_msec()
	# maps
	var maps := _build_t3d_maps()
	build_ms["t3d_maps"] = Time.get_ticks_msec() - t0; t0 = Time.get_ticks_msec()
	build_ms["crest_n"] = crest_cells.size(); build_ms["foot_n"] = foot_cells.size()
	t3d.data.import_images(maps, Vector3(-T3D_HALF, 0.0, -T3D_HALF), 0.0, 1.0)
	_t3d_data = t3d.data
	# collision: the whole world, built once (the bike, the plane and teleports go everywhere)
	t3d.collision.layer = 1
	t3d.collision.mask = 1
	t3d.collision.mode = Terrain3DCollision.FULL_GAME
	build_ms["t3d_import"] = Time.get_ticks_msec() - t0


## Contact darkening under scattered props (bushes, trees): the colour map is pulled toward `col`
## in a disc of `radius` round every point (full `strength` at the centre, fading to the rim). The
## scatters need the finished terrain, so this runs after `import_images`: it edits the regions'
## colour images in place and re-uploads the colour maps once. (critique r1 item 8: "#6a5a48 at
## 50 % under every bush/tree" - the painted canopy density only covered the forest stands.)
func paint_halos(points: PackedVector3Array, radius: float, col: Color, strength: float) -> void:
	if _t3d_data == null or points.is_empty(): return
	var t0 := Time.get_ticks_msec()
	var imgs: Dictionary = {}   # region location -> its colour Image
	var reg_m := T3D_SPACING * T3D_REGION   # metres per region
	for p in points:
		var loc := Vector2i(int(floor(p.x / reg_m)), int(floor(p.z / reg_m)))
		if not imgs.has(loc):
			var reg: Terrain3DRegion = _t3d_data.get_region(loc)
			if reg == null: continue
			imgs[loc] = reg.get_color_map()
			reg.set_modified(true)
		var img: Image = imgs[loc]
		# the region's colour map may be stored at a coarser resolution than the height map
		var w := img.get_width()
		var m_px := reg_m / w
		var cx := int(round((p.x - loc.x * reg_m) / m_px)); var cy := int(round((p.z - loc.y * reg_m) / m_px))
		var r_px := int(ceil(radius / m_px))
		for dy in range(-r_px, r_px + 1):
			var py := cy + dy
			if py < 0 or py >= w: continue
			for dx in range(-r_px, r_px + 1):
				var px := cx + dx
				if px < 0 or px >= w: continue
				var d := sqrt(float(dx * dx + dy * dy)) * m_px
				if d > radius: continue
				var c := img.get_pixel(px, py)
				var k := strength * (1.0 - smoothstep(radius * 0.35, radius, d))
				# the sum of halo + painted-canopy darkening is capped (r3 item 10): a pixel the map
				# already darkened toward the humus colour takes proportionally less of the halo
				k *= clampf((c.get_luminance() - col.get_luminance()) / 0.25, 0.0, 1.0)
				var nc := c.lerp(col, k)
				nc.a = c.a
				img.set_pixel(px, py, nc)
	if not imgs.is_empty():
		_t3d_data.update_maps(Terrain3DRegion.TYPE_COLOR, true, false)
	build_ms["halos"] = Time.get_ticks_msec() - t0
	build_ms["halos_n"] = points.size()


## The Terrain3D camera follows the active viewport camera; tools without one set it here.
func set_view_camera(cam: Camera3D) -> void:
	if terrain3d != null and cam != null:
		terrain3d.set_camera(cam)


## A 3 m grid field (N*N floats) as a T3D_W map image: padded into the sea rim like the height
## map, blurred by a `down`x shrink (trilinear = mip averaged) and grown back bilinearly. Used for
## the neighbourhood fields (mean height, nearby steepness) that drive the colour-map shading.
func _grid_field_map(arr: PackedFloat32Array, fill: float, down: int) -> Image:
	var pad := int((T3D_HALF - CORE_SIZE * 0.5) / CELL)
	var grid := Image.create_from_data(N, N, false, Image.FORMAT_RF, arr.to_byte_array())
	var big := Image.create_empty(T3D_W / 2, T3D_W / 2, false, Image.FORMAT_RF)
	big.fill(Color(fill, 0, 0, 1))
	big.blit_rect(grid, Rect2i(0, 0, N, N), Vector2i(pad, pad))
	big.resize(T3D_W / 2 / down, T3D_W / 2 / down, Image.INTERPOLATE_TRILINEAR)
	big.resize(T3D_W, T3D_W, Image.INTERPOLATE_BILINEAR)
	return big


## Exact distance (m) from every map pixel to the nearest road sample, 40 beyond 7.5 m. The 3 m
## `road_dist` grid is too coarse for a 4.5 m road (bilinear across the V of the centreline smears
## it), so the road, its shoulders and the ruts are drawn from this field instead.
func _fine_road_dist() -> PackedFloat32Array:
	var out := PackedFloat32Array(); out.resize(T3D_W * T3D_W); out.fill(40.0)
	var r_px := 5
	var inv := 1.0 / T3D_SPACING
	for r in range(road_samples.size()):
		var pts: PackedVector3Array = road_samples[r]
		for kk in range(pts.size()):
			var p := pts[kk]
			var cx := int(round((p.x + T3D_HALF) * inv)); var cy := int(round((p.z + T3D_HALF) * inv))
			for dy in range(-r_px, r_px + 1):
				var py := cy + dy
				if py < 0 or py >= T3D_W: continue
				var wz := py * T3D_SPACING - T3D_HALF
				var row := py * T3D_W
				for dx in range(-r_px, r_px + 1):
					var px := cx + dx
					if px < 0 or px >= T3D_W: continue
					var wx := px * T3D_SPACING - T3D_HALF
					var d := sqrt((wx - p.x) * (wx - p.x) + (wz - p.z) * (wz - p.z))
					if d < out[row + px]: out[row + px] = d
	return out


## Height (RF), control (RF, packed uint32) and colour (RGBA8) maps at 1.5 m over -768..768.
## Everything is written into packed arrays and turned into images at the end: per-pixel
## `set_pixel` was the bulk of the old loop's time.
func _build_t3d_maps() -> Array:
	# height: the 3 m grid padded into a 512 grid (-768..768 at 3 m), cubic-resampled to 1024
	var pad := int((T3D_HALF - CORE_SIZE * 0.5) / CELL)   # 48 cells of sea rim each side: world -624..624 inside -768..768
	var grid := Image.create_from_data(N, N, false, Image.FORMAT_RF, heights.to_byte_array())
	var big := Image.create_empty(T3D_W / 2, T3D_W / 2, false, Image.FORMAT_RF)
	big.fill(Color(-10.5, 0, 0, 1))
	big.blit_rect(grid, Rect2i(0, 0, N, N), Vector2i(pad, pad))
	big.resize(T3D_W, T3D_W, Image.INTERPOLATE_CUBIC)
	var hdata := big.get_data().to_float32_array()
	var cdata := PackedFloat32Array(); cdata.resize(T3D_W * T3D_W)
	var col := PackedByteArray(); col.resize(T3D_W * T3D_W * 4)
	# neighbourhood fields for the shading: mean height over ~15 m (cavities are below it) and
	# mean slope over ~9 m (a flat cell next to steep ones is a cliff foot or crest)
	var mean_h := _grid_field_map(heights, -10.5, 5).get_data().to_float32_array()
	var near_sl := _grid_field_map(_slope, 0.0, 3).get_data().to_float32_array()
	var fine_rd := _fine_road_dist()
	# micro relief, edge dither and tint noise come from noise images (native), sampled per pixel
	var dn := FastNoiseLite.new(); dn.seed = 31; dn.noise_type = FastNoiseLite.TYPE_SIMPLEX; dn.frequency = 0.9; dn.fractal_octaves = 3
	var detail := dn.get_seamless_image(256, 256).get_data()          # L8, per pixel
	var en := FastNoiseLite.new(); en.seed = 53; en.noise_type = FastNoiseLite.TYPE_SIMPLEX; en.frequency = 0.3; en.fractal_octaves = 2
	var edge := en.get_seamless_image(256, 256).get_data()            # L8, ~5 m: ragged road edges and rock lines
	var tn := FastNoiseLite.new(); tn.seed = 77; tn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH; tn.frequency = 0.012; tn.fractal_octaves = 3
	var tint_noise := tn.get_image(T3D_W, T3D_W).get_data()           # L8, large patches in map pixels directly
	var rock_ov: int = Terrain3DUtil.enc_overlay(Tex.ROCK)
	var dirt_ov: int = Terrain3DUtil.enc_overlay(Tex.DIRT)
	var cliff_ov: int = Terrain3DUtil.enc_overlay(Tex.CLIFF)
	var rubble_ov: int = Terrain3DUtil.enc_overlay(Tex.RUBBLE)
	var gravel_ov: int = Terrain3DUtil.enc_overlay(Tex.GRAVEL)
	var soil_ov: int = Terrain3DUtil.enc_overlay(Tex.SOIL)
	var base_enc := PackedInt32Array(); base_enc.resize(Tex.size())
	for t in range(Tex.size()): base_enc[t] = Terrain3DUtil.enc_base(t)
	var blend_enc := PackedInt32Array(); blend_enc.resize(256)
	for b in range(256): blend_enc[b] = Terrain3DUtil.enc_blend(b)
	var biome_tex := PackedInt32Array(); biome_tex.resize(Biome.size())
	var biome_det := PackedFloat32Array(); biome_det.resize(Biome.size())
	for b in range(Biome.size()):
		biome_tex[b] = BIOME_TEX[b]; biome_det[b] = BIOME_DETAIL[b]
	var sea_ctrl: float = Terrain3DUtil.as_float(base_enc[Tex.SAND])
	var half := CORE_SIZE * 0.5
	var inv_cell := 1.0 / CELL
	var nm1 := N - 1
	# the palette: desaturated, warm, nothing neon (the reference lives in a narrow band of dry
	# olive, straw, bone and tan). Tints multiply the texture's `albedo_color`, which is set to
	# each texture's brightest use, so every value here is <= 1.
	# (critique r1: the ground read chalk-white, #bbaa9b on the headland; target <= #a08a74, warm,
	# with the road a visibly darker, redder band: crown #c9a77a, ruts #8f7658, margin #7a6a55)
	# band 0 is the ploughed soil strip under the vine rows: dark earth (r2 item 9), not straw
	# (r4 item 8: bands 1 and 2 warm brown-straw too, the vineyard region is H46 S0.51 in the reference)
	# (r5 item 5: the strips ran over every FARM slope, vines or not, and the villa foreground was
	# orange soil (8.3 % of the lower frame, ref 1.3 %). Soil only inside `vine_fields`, one narrow
	# band per period, and the band tints are straw everywhere except under the soil: the
	# reference's vineyard is straw-gold ground (H30-60 S0.3-0.7, 39 % of the frame) with brown
	# strips, its brightest ground saturated straw, never grey-white)
	var farm_strips: Array[Color] = [Color(0.94, 0.84, 0.60), Color(0.92, 0.86, 0.52), Color(0.86, 0.82, 0.48), Color(0.92, 0.88, 0.56)]
	var meadow_a := Color(0.96, 0.88, 0.54); var meadow_b := Color(0.84, 0.80, 0.48)   # FARM outside the parcels: dry straw with broad patches
	# the parcel mask on the 3 m grid: a cell is "in a field" when a vine rect covers it
	var field := PackedByteArray(); field.resize(N * N)
	for fr in vine_fields:
		var i0 := clampi(int((fr.position.x + half) * inv_cell), 0, nm1); var i1 := clampi(int(ceil((fr.end.x + half) * inv_cell)), 0, nm1)
		var j0f := clampi(int((fr.position.y + half) * inv_cell), 0, nm1); var j1 := clampi(int(ceil((fr.end.y + half) * inv_cell)), 0, nm1)
		for jj in range(j0f, j1 + 1):
			for ii in range(i0, i1 + 1): field[jj * N + ii] = 1
	var road_col := Color(1.0, 0.93, 0.76)     # pale dusty crown, #c2ae8c-class after the grade (both references have the road lighter than the ground; r5: yellower, the villa lane is S0.55 in the reference)
	var rut_col := Color(0.82, 0.68, 0.44)      # compacted ruts, ~0.15 V under the crown (r6 item 7: (0.62,0.52,0.40) made the 3 m-grid lane dark mud, V0.46-0.56 under the straw beside it; ref lane #a47b49 V0.64 is the brightest ground)
	var bone := Color(0.94, 0.89, 0.80)         # sea-cliff faces above the water line: pale warm limestone, not brown
	var bench_col := Color(0.88, 0.82, 0.62)    # r6 item 11: H40 in (was (0.90,0.80,0.64) H30 - the bench rendered H20 pink-brown, ref H51 straw sand). The bench at the cliff foot: sand / earth (#b09776), lighter and warmer than the rock
	var margin_col := Color(0.62, 0.52, 0.32)   # r6 item 7: straw-gold, was (0.42,0.37,0.29) dark. Trodden margin that bleeds 1.5 m into the scrub
	# the sea-cliff tops (r4 item 7): dry straw between the scrub (#b8a878 / #b4986d in the reference,
	# H36 S0.38), not the bone of the faces and not a green lawn - the Grass texture under a
	# warm straw tint on every flat cell of the coast above the bench
	var straw_a := Color(0.90, 0.78, 0.58); var straw_b := Color(0.76, 0.66, 0.48)
	for py in range(T3D_W):
		var wz := py * T3D_SPACING - T3D_HALF
		var gz := (wz + half) * inv_cell
		var jn := int(round(gz))
		var row := py * T3D_W
		if jn < 0 or jn > nm1:
			# open sea beyond the world: sand, deep-blue tint
			for px in range(T3D_W):
				cdata[row + px] = sea_ctrl
				var o := (row + px) * 4
				col[o] = 115; col[o + 1] = 158; col[o + 2] = 184; col[o + 3] = 128
			continue
		var j0 := clampi(int(gz), 0, nm1 - 1); var fz := clampf(gz - j0, 0.0, 1.0)
		var ny := (py & 255) << 8
		for px in range(T3D_W):
			var pid := row + px
			var wx := px * T3D_SPACING - T3D_HALF
			var gx := (wx + half) * inv_cell
			var i_n := int(round(gx))
			if i_n < 0 or i_n > nm1:
				cdata[pid] = sea_ctrl
				var o := pid * 4
				col[o] = 115; col[o + 1] = 158; col[o + 2] = 184; col[o + 3] = 128
				continue
			var i0 := clampi(int(gx), 0, nm1 - 1); var fx := clampf(gx - i0, 0.0, 1.0)
			var id00 := j0 * N + i0
			var biome := _map_b[jn * N + i_n]
			var h := hdata[pid]
			# cubic resampling overshoots at cliffs, bridgeheads and pad edges: clamp every pixel to the
			# range of the four grid cells round it so nothing pokes above a deck or below a shore
			var h00 := heights[id00]; var h10 := heights[id00 + 1]; var h01 := heights[id00 + N]; var h11 := heights[id00 + N + 1]
			var hmax := maxf(maxf(h00, h10), maxf(h01, h11))
			var hc := clampf(h, minf(minf(h00, h10), minf(h01, h11)), hmax)
			if biome == Biome.SEA and hmax < -1.2 and road_dist[id00] > 8.0:
				# open sea floor, well under the water line and away from any bridge: sand with the
				# depth tint, none of the slope / road / shading work below (round 3: ~30 % of the
				# land rows are sea floor, and the full per-pixel pass on them cost ~1 s)
				hdata[pid] = hc
				cdata[pid] = sea_ctrl
				var st := Color(0.72, 0.86, 0.80).lerp(Color(0.30, 0.42, 0.58), smoothstep(-2.0, -8.0, hc))
				var so := pid * 4
				col[so] = int(st.r * 255.0); col[so + 1] = int(st.g * 255.0); col[so + 2] = int(st.b * 255.0); col[so + 3] = 128
				continue
			# bilinear road distance (grid: includes pads), slope and canopy density
			var rd := lerpf(lerpf(road_dist[id00], road_dist[id00 + 1], fx), lerpf(road_dist[id00 + N], road_dist[id00 + N + 1], fx), fz)
			var sl := lerpf(lerpf(_slope[id00], _slope[id00 + 1], fx), lerpf(_slope[id00 + N], _slope[id00 + N + 1], fx), fz)
			var rdf := fine_rd[pid]
			var nx := ny | (px & 255)
			# --- micro relief (never on roads, pads or salt)
			var amp := biome_det[biome] * smoothstep(3.0, 9.0, minf(rd, rdf))
			if amp > 0.0:
				hc += amp * (detail[nx] * (2.0 / 255.0) - 1.0)
			hdata[pid] = hc
			h = hc
			# --- control: base by biome, rock on slopes, dirt on roads
			var base := biome_tex[biome]
			var overlay := rock_ov
			# the coast cliffs are painted as sea; their flat tops (and the limestone behind them)
			# are straw ground, the rock lip / faces come from the slope overlays below
			var coast_top := (biome == Biome.SEA and h > 1.5) or (biome == Biome.LIMESTONE and wx < -440.0 and wz > -350.0 and wz < -100.0)
			if coast_top and sl < 0.4: base = Tex.GRASS
			var ej := edge[nx] * (1.0 / 255.0) - 0.5          # -0.5..0.5, ~5 m: ragged edges everywhere
			var slj := sl + ej * 0.06
			# rock: a sharper line than before, stronger on steep faces (the old 0.22..0.5 ramp left
			# the slopes half-grassed); karst and moor keep a little bare stone on any slope
			var blend := smoothstep(0.24, 0.40, slj)
			if biome == Biome.BADLANDS: blend = smoothstep(0.3, 0.5, slj)
			elif biome == Biome.MOOR or biome == Biome.LIMESTONE: blend = maxf(smoothstep(0.17, 0.34, slj), 0.12 * clampf(slj * 6.0, 0.0, 1.0))
			elif biome == Biome.SALTFLAT or biome == Biome.LAKE: blend = 0.0
			var m := tint_noise[pid] * (1.0 / 255.0) - 0.5    # -0.5..0.5 broad patches
			var nsl := near_sl[pid]
			var cav := mean_h[pid] - h                        # > 0: below the neighbourhood (gully, cliff foot)
			var dry_land := biome != Biome.LAKE and biome != Biome.SALTFLAT and biome != Biome.BADLANDS and (biome != Biome.SEA or h > 0.5)
			if sl > 0.45:
				# the steepest faces are all rock: the coarse bedded limestone with the same set tiled
				# 2.6x finer in ~50 % patches (r2 item 8: one 20 m tiling read as smeared mud)
				base = Tex.ROCK
				overlay = cliff_ov
				# (r3 item 11: a 1.5 m map texel spans 3-4 m down a 60 deg face, so any 5 m variation
				# in the patch blend stretches into vertical streaks - broad 80 m patches only)
				blend = smoothstep(-0.2, 0.2, m + ej * 0.1)
			elif dry_land and sl < 0.4 and nsl > 0.18 and cav > 0.1:
				# talus: a flat-ish cell below a steep neighbourhood gets rubble at the cliff's feet
				var tb := smoothstep(0.18, 0.34, nsl) * smoothstep(0.1, 2.0, cav) * (0.85 + ej * 0.5)
				if tb > blend: overlay = rubble_ov; blend = clampf(tb, 0.0, 1.0)
				# a ledge foot for the bush lines: clearly below the neighbourhood, next to steep ground
				if nsl > 0.2 and cav > 0.5 and h > 1.2 and rd > 4.0 and ((px + py) & 1) == 0: foot_cells.append(Vector2(wx, wz))
			elif dry_land and sl < 0.3 and nsl > 0.2 and cav < -0.3:
				# crest: a flat cell above a steep neighbourhood is the bare limestone lip of the
				# cliff top, so the crest bushes sit on rock, not on grass (r2 item 12)
				var cb := smoothstep(0.2, 0.36, nsl) * smoothstep(-0.3, -2.0, cav) * (0.8 + ej * 0.6)
				if cb > blend: overlay = rock_ov; blend = clampf(cb, 0.0, 1.0)
				if nsl > 0.22 and cav < -0.6 and h > 1.2 and rd > 4.0 and ((px + py) & 1) == 0: crest_cells.append(Vector2(wx, wz))
			# road: 4.5 m of trodden dirt with a ragged edge, a gravel shoulder to ~4.5 m out
			var rdr := rdf + ej * 1.3
			# the sea-cliff bench (coast road on painted-sea ground, 0-9 m up): sand / earth to
			# ~10 m out, so the bench reads as pale ground under the wall, not as cliff (r2 item 4)
			var bench := (biome == Biome.SEA or (biome == Biome.LIMESTONE and wx < -440.0 and wz > -350.0 and wz < -100.0)) and h > 0.3 and h < 12.0 and rdf < 12.0
			if rdr < 2.25:
				overlay = dirt_ov; blend = 1.0
			elif rdr < 4.6:
				overlay = gravel_ov; blend = 1.0 - smoothstep(2.9, 4.6, rdr)
			elif bench and sl < 0.35:
				var bb := 1.0 - smoothstep(6.0, 11.0, rdr)
				if bb > blend: overlay = dirt_ov; blend = bb
			elif rd < 7.0 and rdf > 6.0:
				# a courtyard pad (the grid distance is lowered round pads): packed dirt fading out
				var rb := 1.0 - smoothstep(2.4, 6.5, rd)
				if rb > blend * 0.6: overlay = dirt_ov; blend = rb
			var in_field := biome == Biome.FARM and field[jn * N + i_n] == 1
			if in_field and rdf >= 7.0 and rd >= 7.0:
				# ploughed strips between the vine rows read as bare soil (r5: a third of the
				# period, and only inside the parcels)
				var strip := fmod(absf(wx * 0.7 + wz * 0.35), 24.0)
				if strip < 8.0 and sl < 0.2: overlay = soil_ov; blend = 0.85
			cdata[pid] = Terrain3DUtil.as_float(base_enc[base] | overlay | blend_enc[int(blend * 255.0)])
			# --- colour tint
			var tint: Color
			match biome:
				Biome.SEA:
					# turquoise shelf, darker blue in the deep (seen through the shallows); the map paints
					# the coast cliffs as sea, so above the water line it is bone-pale stone instead
					tint = Color(0.72, 0.86, 0.80).lerp(Color(0.30, 0.42, 0.58), smoothstep(-2.0, -8.0, h))
					tint = tint.lerp(bone, smoothstep(-0.4, 0.6, h))
				Biome.LIMESTONE:
					# pale bone plateau, a greyer patch here and there; olive only under the painted canopy
					tint = Color(0.88, 0.80, 0.66).lerp(Color(0.72, 0.66, 0.56), clampf(m + 0.5, 0.0, 1.0))
				Biome.FOREST:
					# dry olive meadow (#8f8f57 .. #b3a468 over the straw texture), never yellow-green
					tint = Color(0.82, 0.80, 0.54).lerp(Color(0.96, 0.90, 0.62), clampf(m + 0.5, 0.0, 1.0))
				Biome.FARM:
					if in_field:
						var strip := fmod(absf(wx * 0.7 + wz * 0.35), 24.0)
						var band: int = int(floor(strip / 6.0))
						tint = farm_strips[band]
						var pxm := fmod(absf(wx + 1000.0), 26.0); var pzm := fmod(absf(wz + 1000.0), 22.0)
						if pxm < 1.5 or pzm < 1.5: tint = tint.darkened(0.3)
					else:
						tint = meadow_a.lerp(meadow_b, clampf(m + 0.5, 0.0, 1.0))
				Biome.BADLANDS:
					tint = Color(0.94, 0.84, 0.74).lerp(Color(0.82, 0.64, 0.50), clampf(m + 0.5, 0.0, 1.0))
				Biome.TOWN:
					tint = Color(0.92, 0.86, 0.72).lerp(Color(0.80, 0.78, 0.64), clampf(m + 0.5, 0.0, 1.0))
				Biome.BEACH:
					tint = Color(1.0, 0.97, 0.90)
				Biome.LAKE:
					tint = Color(0.86, 0.80, 0.60).lerp(Color(0.55, 0.70, 0.66), smoothstep(-0.3, -3.0, h))
				Biome.DUNES:
					tint = Color(1.0, 0.96, 0.86).lerp(Color(0.92, 0.86, 0.72), clampf(m + 0.5, 0.0, 1.0))
				Biome.MOOR:
					# heather and peat: muted mauve-brown patches over the grass, greyer on the rock
					tint = Color(0.86, 0.78, 0.78).lerp(Color(0.84, 0.82, 0.66), clampf(m + 0.5, 0.0, 1.0))
				Biome.SALTFLAT:
					tint = Color(0.92, 0.92, 0.90)
				_:
					tint = Color(1, 1, 1)
			if coast_top:
				tint = tint.lerp(straw_a.lerp(straw_b, clampf(m + 0.5, 0.0, 1.0)), 1.0 - smoothstep(0.28, 0.42, sl))
			if (biome != Biome.SEA or h > -0.4) and biome != Biome.LAKE:
				# steep faces: cooler, and the streak patches a touch darker; the shader's macro
				# variation is halved on slopes so this is where their variety comes from
				# (r2 item 8: lighter, toward #c9bfae - the slopes are pale limestone, not mud)
				# (r3 item 11: nearly one flat tint on the steepest faces - per-texel tint variation
				# reads as vertical streaks down a slope, see the control blend above)
				if sl > 0.3:
					tint = tint.lerp(Color(0.92, 0.88, 0.82), smoothstep(0.3, 0.5, sl) * 0.9)
				# contact darkening, the AO the renderer cannot do: cliff feet and the ground under
				# the painted canopy get a dark halo, gullies sink into shadow
				var dens := lerpf(lerpf(_map_d[id00], _map_d[id00 + 1], fx), lerpf(_map_d[id00 + N], _map_d[id00 + N + 1], fx), fz)
				# (r3 item 10: the painted-canopy darkening halved - stacked with the trees' own
				# shadows and the per-tree halos it made 10-20 m chocolate-navy blotches under every
				# stand; the whole ground darkening is capped at 40 % and pulled toward a warm humus)
				var halo := smoothstep(0.3, 0.8, dens + ej * 0.3) * 0.14
				var foot := clampf((nsl - sl) * 4.0, 0.0, 1.0) * smoothstep(0.0, 2.0, cav) * 0.35
				var gully := smoothstep(0.6, 4.0, cav) * 0.25
				var dark := clampf(maxf(maxf(halo, foot), gully) + minf(halo, foot) * 0.5, 0.0, 0.3)   # r4 item 8: cap 0.4 -> 0.3
				# never on the road or its shoulders: the bench road at a cliff foot is exactly a
				# "flat cell below steep neighbours" and went the colour of the rock (r2 item 4)
				dark *= smoothstep(3.5, 7.5, rdf)
				if dark > 0.0: tint = tint.lerp(Color(0.42, 0.38, 0.26), dark)   # olive humus, never mauve under a blue shadow
				if bench: tint = tint.lerp(bench_col, (1.0 - smoothstep(5.0, 12.0, rdf)) * 0.8)
			# road: two darker compacted ruts at ~1 m either side of a lighter crown, a dusty margin
			if rdf < 5.0:
				var road_t := 1.0 - smoothstep(2.0, 3.0, rdr)
				var rut := smoothstep(0.45, 0.7, rdf) * (1.0 - smoothstep(1.2, 1.6, rdf))
				var rc := road_col.lerp(rut_col, rut * 0.9)
				tint = tint.lerp(rc, road_t)
				# a dark trodden margin just outside the crown: this is what makes the road read at 150 m
				tint = tint.lerp(margin_col, (1.0 - smoothstep(2.4, 4.2, rdr)) * (1.0 - road_t) * 0.7)
			elif rd < 7.0:
				tint = tint.lerp(road_col, 1.0 - smoothstep(2.4, 7.0, rd))   # pads
			var o := pid * 4
			col[o] = int(clampf(tint.r, 0.0, 1.0) * 255.0); col[o + 1] = int(clampf(tint.g, 0.0, 1.0) * 255.0)
			col[o + 2] = int(clampf(tint.b, 0.0, 1.0) * 255.0); col[o + 3] = 128
	var hmap := Image.create_from_data(T3D_W, T3D_W, false, Image.FORMAT_RF, hdata.to_byte_array())
	var ctrl := Image.create_from_data(T3D_W, T3D_W, false, Image.FORMAT_RF, cdata.to_byte_array())
	var cmap := Image.create_from_data(T3D_W, T3D_W, false, Image.FORMAT_RGBA8, col)
	return [hmap, ctrl, cmap]


## Biome paint layers share the generated gouache albedo; old packed normal maps
## remain as quiet surface relief. Layer IDs are unchanged for existing control maps.
func _build_texture_assets(assets: Terrain3DAssets) -> void:
	var specs := [
		["Grass", "ground015", Color(.64,.72,.43), .12, .10, .16],
		["Rock", "rock019", Color(.71,.70,.62), .07, .18, .20],
		["Dirt", "ground004", Color(.72,.61,.43), .15, .08, .15],
		["Sand", "sand", Color(.86,.80,.62), .12, .07, .10],
		["Clay", "clay", Color(.69,.43,.29), .12, .10, .14],
		["Scrub", "ground024", Color(.64,.65,.44), .10, .10, .16],
		["Soil", "soil", Color(.47,.38,.25), .14, .12, .18],
		["Salt", "salt", Color(.90,.90,.82), .12, .05, .06],
		["Cliff", "rock019", Color(.76,.75,.66), .10, .20, .20],
		["Rubble", "rocks002", Color(.66,.65,.53), .14, .18, .20],
		["Gravel", "gravel009", Color(.64,.56,.40), .16, .10, .14],
	]
	var paper := _texture_512("res://assets/storybook/gouache_surface.png")
	var cache: Dictionary = {}
	for i in range(specs.size()):
		var sp: Array = specs[i]
		var ta := Terrain3DTextureAsset.new()
		ta.name = sp[0]
		ta.id = i
		if not cache.has(sp[1]):
			cache[sp[1]] = _texture_512(TEX_DIR + sp[1] + "_nrm_rgh.png")
		ta.albedo_texture = paper
		ta.normal_texture = cache[sp[1]]
		ta.albedo_color = sp[2]
		ta.uv_scale = sp[3]
		ta.normal_depth = sp[4]
		ta.ao_strength = sp[5]
		ta.detiling_rotation = .35
		ta.detiling_shift = .25
		assets.set_texture(i, ta)


## Every texture in the array must match: 512 px RGBA8 with mipmaps.
func _texture_512(path: String) -> ImageTexture:
	var tex: Texture2D = load(path)
	var img: Image = tex.get_image()
	if img.is_compressed(): img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	if img.get_width() != 512 or img.get_height() != 512: img.resize(512, 512, Image.INTERPOLATE_LANCZOS)
	if not img.has_mipmaps(): img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

## --- Ground queries ---------------------------------------------------------------------
## Ground under a world position: the heightfield, or whatever is built on top of it (roof,
## deck, pier) if that is higher. Returns {height, normal, built: bool}.
func probe(pos: Vector3) -> Dictionary:
	var h := height_at(pos.x, pos.z)
	var n := normal_at(pos.x, pos.z)
	var built := false
	if is_inside_tree():
		var space := get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 2.0, 0), Vector3(pos.x, h - 0.5, pos.z), 1)
		var hit := space.intersect_ray(q)
		if hit and hit.position.y > h + 0.05:
			h = hit.position.y
			n = hit.normal
			built = true
	return {"height": h, "normal": n, "built": built}


var _road_grid: Dictionary = {}
const ROAD_CELL := 8.0
## A coarse second grid (every 2nd sample in 256 m cells) answers `nearest_road` anywhere in the
## 25 km world when nothing lies within the fine grid's 480 m search.
var _road_coarse: Dictionary = {}
const ROAD_COARSE := 256.0


func _build_road_grid() -> void:
	_road_grid.clear()
	_road_coarse.clear()
	for r in range(road_samples.size()):
		var pts: PackedVector3Array = road_samples[r]
		for k in range(pts.size()):
			var c := Vector2i(int(floor(pts[k].x / ROAD_CELL)), int(floor(pts[k].z / ROAD_CELL)))
			if not _road_grid.has(c):
				_road_grid[c] = []
			_road_grid[c].append([r, k])
			if k % 2 == 0 or k == pts.size() - 1:
				var cc := Vector2i(int(floor(pts[k].x / ROAD_COARSE)), int(floor(pts[k].z / ROAD_COARSE)))
				if not _road_coarse.has(cc): _road_coarse[cc] = []
				_road_coarse[cc].append([r, k])


## Nearest road sample to a world position: {point: Vector3, tangent: Vector3 (flat, unit)}.
## Is this ground-cover point inside a region the Island asked to keep bare?
func _in_keep_clear(p: Vector2) -> bool:
	for r in keep_clear:
		if r.has("centre"):
			if p.distance_squared_to(r.centre) < r.radius * r.radius: return true
		elif p.distance_to(Geometry2D.get_closest_point_to_segment(p, r.a, r.b)) < r.width: return true
	return false


func nearest_road(pos: Vector3) -> Dictionary:
	if _road_grid.is_empty():
		_build_road_grid()
	var cc := Vector2i(int(floor(pos.x / ROAD_CELL)), int(floor(pos.z / ROAD_CELL)))
	var best_d := INF
	var best_r := 0
	var best_k := 0
	var ring := 0
	while ring < 60:
		for dj in range(-ring, ring + 1):
			for di in range(-ring, ring + 1):
				if ring > 0 and absi(di) != ring and absi(dj) != ring: continue
				var c := Vector2i(cc.x + di, cc.y + dj)
				if not _road_grid.has(c): continue
				for e in _road_grid[c]:
					var p: Vector3 = road_samples[e[0]][e[1]]
					var d := Vector2(p.x - pos.x, p.z - pos.z).length_squared()
					if d < best_d:
						best_d = d; best_r = e[0]; best_k = e[1]
		if best_d < INF and sqrt(best_d) < (ring + 0.5) * ROAD_CELL:
			break
		ring += 1
	if best_d == INF:
		# far from every road: search the coarse grid outwards (the whole world if need be)
		var ccc := Vector2i(int(floor(pos.x / ROAD_COARSE)), int(floor(pos.z / ROAD_COARSE)))
		ring = 0
		while ring < 120:
			for dj in range(-ring, ring + 1):
				for di in range(-ring, ring + 1):
					if ring > 0 and absi(di) != ring and absi(dj) != ring: continue
					var c := Vector2i(ccc.x + di, ccc.y + dj)
					if not _road_coarse.has(c): continue
					for e in _road_coarse[c]:
						var p: Vector3 = road_samples[e[0]][e[1]]
						var d := Vector2(p.x - pos.x, p.z - pos.z).length_squared()
						if d < best_d:
							best_d = d; best_r = e[0]; best_k = e[1]
			if best_d < INF and sqrt(best_d) < (ring + 0.5) * ROAD_COARSE:
				break
			ring += 1
	if road_samples.is_empty(): return {"point": pos, "tangent": Vector3.FORWARD}
	var pts: PackedVector3Array = road_samples[best_r]
	var k0 := clampi(best_k, 0, pts.size() - 2)
	var tangent: Vector3 = pts[k0 + 1] - pts[k0]
	tangent.y = 0.0
	return {"point": pts[best_k], "tangent": tangent.normalized()}


func nearest_road_point(pos: Vector3) -> Vector3:
	return nearest_road(pos).point


func road_tangent_near(pos: Vector3) -> Vector3:
	return nearest_road(pos).tangent


## --- Ground cover (Terrain3D instancer) --------------------------------------------------
## Grass, dry grass, dune grass and wild flowers as alpha-cut texture cards planted through
## Terrain3D's instancer, which batches them per region cell with distance fades. Density per
## biome, never on roads or pads (road_dist covers both), never on steep ground.
const COVER := [
	# name, texture, size (w, h), lod0 range (m), shadows
	["Grass", "grass_card", Vector2(1.3, 0.8), 110.0],
	["DryGrass", "dry_grass_card", Vector2(1.3, 0.8), 110.0],
	["DuneGrass", "dune_grass_card", Vector2(1.4, 0.9), 110.0],
	["FlowerPink", "flower_card_pink", Vector2(0.9, 0.7), 70.0],
	["FlowerYellow", "flower_card_yellow", Vector2(0.9, 0.7), 70.0],
	["FlowerWhite", "flower_card_white", Vector2(0.9, 0.7), 70.0],
]
## biome -> [mesh id, plants per 3 m cell, tint]. Meadows (forest floor, farmland) are dense with
## a darker base tint; the limestone coast and the dunes are sparse tufts on bare ground, the way
## the reference's cliff-top benches read (dry grass in patches, not a carpet).
const COVER_BY_BIOME := {
	Biome.FOREST: [0, 6.5, Color(0.76, 0.78, 0.60)],
	Biome.FARM: [0, 6.0, Color(0.82, 0.80, 0.60)],
	Biome.TOWN: [1, 2.2, Color(0.86, 0.80, 0.64)],
	Biome.MOOR: [1, 4.2, Color(0.80, 0.74, 0.74)],
	Biome.LIMESTONE: [1, 1.6, Color(0.80, 0.72, 0.56)],
	Biome.DUNES: [2, 0.8, Color(0.92, 0.92, 0.88)],
	Biome.BEACH: [2, 0.3, Color(0.92, 0.92, 0.88)],
	Biome.BADLANDS: [1, 0.4, Color(0.84, 0.74, 0.64)],
	Biome.SEA: [1, 1.2, Color(0.84, 0.74, 0.54)],   # the coast cliffs are painted as sea: sparse straw tufts on the tops (r4 item 7), crest tufts
}
## Patch mask threshold on the L8 noise (128 = zero, ~Gaussian): 126 keeps ~55 % of the cells, thinned at the patch edges.
const COVER_MASK_THR := 126
## Where the reference views are framed (the coast bench under the sea cliffs, the villa lanes):
## the patch mask is relaxed round these so the foreground keeps its tufts.
const COVER_HERO: Array[Vector2] = [Vector2(-522, -200), Vector2(-500, -250), Vector2(-326, 3)]


func plant_ground_cover(seed_v: int) -> void:
	if terrain3d == null: return
	var t0 := Time.get_ticks_msec()
	var assets: Terrain3DAssets = terrain3d.assets
	for i in range(COVER.size()):
		var c: Array = COVER[i]
		var ma := Terrain3DMeshAsset.new()
		ma.name = c[0]
		ma.id = i
		ma.generated_type = Terrain3DMeshAsset.TYPE_TEXTURE_CARD
		ma.generated_faces = 2
		ma.generated_size = c[2]
		var m: Material = ma.material_override
		if m is StandardMaterial3D:
			m.albedo_texture = load(FOLIAGE_DIR + c[1] + ".png")
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			m.alpha_scissor_threshold = 0.45
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.roughness = 1.0
			m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
			m.vertex_color_use_as_albedo = true
		ma.cast_shadows = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ma.last_lod = 0
		ma.lod0_range = c[3]
		ma.fade_margin = 12.0
		assets.set_mesh_asset(i, ma)
	var rng := RandomNumberGenerator.new(); rng.seed = seed_v
	var xf: Array = []; var cols: Array = []
	for i in range(COVER.size()):
		xf.append([] as Array[Transform3D]); cols.append([] as Array[Color])
	var half := CORE_SIZE * 0.5
	var flower_ids := [3, 4, 5]
	# patch mask (r3, RESEARCH §3.4: dry grass grows in patches at ~45 % coverage, never a lawn):
	# a ~15 m noise per 3 m cell, sampled as one native image; cells under the threshold stay bare
	# ground. The mask relaxes near the hero patches so the framed benches keep their tufts.
	# It is also the cheapest speed-up there is: 317 k -> ~180 k instances (r3 timing table).
	var mn := FastNoiseLite.new(); mn.seed = seed_v & 0xffff; mn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH; mn.frequency = 0.2; mn.fractal_octaves = 2
	var mask := mn.get_image(N, N).get_data()   # L8, 128 = zero noise
	for j in range(1, N - 1):
		for i in range(1, N - 1):
			var id := _idx(i, j)
			var b := _map_b[id]
			if not COVER_BY_BIOME.has(b): continue
			if road_dist[id] < (6.1 if b==Biome.TOWN else 5.0) or _slope[id] > 0.45 or heights[id] < 1.2: continue
			var spec: Array = COVER_BY_BIOME[b]
			var mesh_id: int = spec[0]
			var want: float = spec[1]
			var tint: Color = spec[2]
			var cx := i * CELL - half; var cz := j * CELL - half
			if b == Biome.FARM and fmod(absf(cx * 0.7 + cz * 0.35), 24.0) < 6.0: continue   # the ploughed strips
			var crest := false
			# crest lines: a flat cell whose neighbour drops away steeply gets a band of dry tufts
			# (with the crest bushes of the island scatter, the vegetation line the reference has
			# along every cliff lip and ledge)
			if _slope[id] < 0.3:
				var hh := heights[id]
				for nid in [id - 1, id + 1, id - N, id + N]:
					if _slope[nid] > 0.5 and heights[nid] < hh - 1.5:
						want += 3.0; mesh_id = 1; crest = true
						break
			if want <= 0.0: continue
			if not crest:
				var thr := COVER_MASK_THR
				for hp in COVER_HERO:
					if absf(hp.x - cx) < 110.0 and absf(hp.y - cz) < 110.0: thr = COVER_MASK_THR - 34; break
				var mv := mask[id]
				if mv < thr: continue
				# the patch edge thins out instead of stopping dead
				want *= clampf(float(mv - thr) / 14.0, 0.55, 1.0)
			var n := int(want) + (1 if rng.randf() < want - int(want) else 0)
			for k in range(n):
				var x := cx + rng.randf_range(-1.5, 1.5); var z := cz + rng.randf_range(-1.5, 1.5)
				var grass_point:=Vector2(x,z)
				if _in_keep_clear(grass_point): continue
				var y := height_at(x, z)
				var s := rng.randf_range(0.75, 1.35)
				var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(s, s * rng.randf_range(0.8, 1.2), s))
				var mid := mesh_id
				if mesh_id == 0 and rng.randf() < 0.05: mid = flower_ids[rng.randi_range(0, 2)]
				xf[mid].append(Transform3D(basis, Vector3(x, y - 0.05, z)))
				var v := rng.randf_range(-0.12, 0.12)
				cols[mid].append(Color(tint.r + v, tint.g + v * 0.8, tint.b + v * 0.5))
	var total := 0
	for i in range(COVER.size()):
		if xf[i].is_empty(): continue
		terrain3d.instancer.add_transforms(i, xf[i], cols[i], false)
		total += xf[i].size()
	terrain3d.instancer.update_mmis(true)
	build_ms["ground_cover"] = Time.get_ticks_msec() - t0
	build_ms["ground_cover_n"] = total
