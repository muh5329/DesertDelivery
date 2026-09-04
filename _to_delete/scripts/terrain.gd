class_name Terrain
extends Node3D
## Island terrain driven by `data/island_map.png`, which tools/mapgen/extract.py derives from the
## reference island painting: R = height, G = biome class, B = tree density. On top of that map:
## noise detail per biome, dirt roads stamped along Curve3D paths (with bridge spans where a road
## crosses water), flat pads for the hubs, a vertex-coloured mesh and a HeightMapShape3D collider.
##
## Biomes: SEA, LIMESTONE (pale mountains, NW), FOREST (pines and scrub), FARM (vineyards, SW),
## BADLANDS (red hoodoos, SE), TOWN (NE), BEACH, LAKE.

enum Biome { SEA, LIMESTONE, FOREST, FARM, BADLANDS, TOWN, BEACH, LAKE }

const SIZE := 720.0          # metres, square world
const CELL := 3.0            # metres per grid cell
const N := int(SIZE / CELL) + 1   # vertices per side (241)
const SEA_LEVEL := 0.0
const MAP_PATH := "res://data/island_map.png"

var heights := PackedFloat32Array()   # N*N
var road_dist := PackedFloat32Array() # distance (m) to nearest road centreline, clamped to 40
var road_h := PackedFloat32Array()    # target road height (valid where road_dist < 14)
var roads: Array[Curve3D] = []
var pads: Array[Vector3] = []          # (x, z, radius) flat courtyards for buildings
var road_samples: Array = []          # Array of PackedVector3Array (world-space samples every ~1 m)
var bridges: Array = []               # {road, from, to, deck} sample ranges that are elevated (water or viaduct)
var viaducts: Array = []              # {a: Vector2, b: Vector2, deck: float} road stretches carried on arches over land

var _map_h := PackedFloat32Array()    # raw map height per cell
var _map_b := PackedByteArray()       # biome per cell
var _map_d := PackedFloat32Array()    # tree density per cell
var _n1 := FastNoiseLite.new()
var _n2 := FastNoiseLite.new()
var _n3 := FastNoiseLite.new()
var _rock := FastNoiseLite.new()

var mesh_instance: MeshInstance3D
var static_body: StaticBody3D


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
	return Vector2((x + SIZE * 0.5) / CELL, (z + SIZE * 0.5) / CELL)


func _bilinear(arr: PackedFloat32Array, x: float, z: float) -> float:
	var g := world_to_grid(x, z)
	var gi := clampf(g.x, 0.0, N - 1.001)
	var gj := clampf(g.y, 0.0, N - 1.001)
	var i0 := int(gi); var j0 := int(gj)
	var fx := gi - i0; var fz := gj - j0
	return lerpf(lerpf(arr[_idx(i0, j0)], arr[_idx(i0 + 1, j0)], fx), lerpf(arr[_idx(i0, j0 + 1)], arr[_idx(i0 + 1, j0 + 1)], fx), fz)


## Biome at a world position (nearest cell).
func biome_at(x: float, z: float) -> int:
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


## Bilinear height lookup at world XZ (after roads and pads).
func height_at(x: float, z: float) -> float:
	return _bilinear(heights, x, z)


func normal_at(x: float, z: float) -> Vector3:
	var e := 1.0
	var hl := height_at(x - e, z); var hr := height_at(x + e, z)
	var hd := height_at(x, z - e); var hu := height_at(x, z + e)
	return Vector3(hl - hr, 2.0 * e, hd - hu).normalized()


func road_dist_at(x: float, z: float) -> float:
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
	heights.resize(N * N)
	road_dist.resize(N * N)
	road_h.resize(N * N)
	road_dist.fill(40.0)
	road_h.fill(0.0)
	var half := SIZE * 0.5
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
				bridges.append({"road": r, "from": k0, "to": k1, "deck": deck})
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
	_build_mesh()
	_build_collision()


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
	var half := SIZE * 0.5
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


func _build_road_grid() -> void:
	_road_grid.clear()
	for r in range(road_samples.size()):
		var pts: PackedVector3Array = road_samples[r]
		for k in range(pts.size()):
			var c := Vector2i(int(floor(pts[k].x / ROAD_CELL)), int(floor(pts[k].z / ROAD_CELL)))
			if not _road_grid.has(c):
				_road_grid[c] = []
			_road_grid[c].append([r, k])


## Nearest road sample to a world position: {point: Vector3, tangent: Vector3 (flat, unit)}.
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
	var pts: PackedVector3Array = road_samples[best_r]
	var k0 := clampi(best_k, 0, pts.size() - 2)
	var tangent: Vector3 = pts[k0 + 1] - pts[k0]
	tangent.y = 0.0
	return {"point": pts[best_k], "tangent": tangent.normalized()}


func nearest_road_point(pos: Vector3) -> Vector3:
	return nearest_road(pos).point


func road_tangent_near(pos: Vector3) -> Vector3:
	return nearest_road(pos).tangent
