class_name Level
extends WorldKit
## The island from the reference painting (data/island_map.png is extracted from it):
## limestone mountains NW, harbour town on the NE peninsula (joined by an aqueduct across the
## strait), forest and a hamlet by the bay in the centre, vineyards and the villa SW, red hoodoo
## badlands around a lake SE, sea stacks all round. Roads are traced in painting pixels (`_px`).

## The four hubs: name -> [centre, flat pad radius]. The one place these numbers live.
const HUB_TABLE := {
	"Villa Rosa": [Vector2(-188, 2), 22.0],
	"Hilltop Farm": [Vector2(-153, -146), 18.0],
	"Harbour": [Vector2(109, -90), 18.0],
	"Dunes Lookout": [Vector2(96, 73), 9.0],
}

const IMG_W := 1672.0
const IMG_H := 941.0
var _ppm := 2.322
var _islets: Array = []


func hub_table() -> Dictionary:
	return HUB_TABLE


## Painting pixel -> world XZ.
func _px(x: float, y: float) -> Vector2:
	return Vector2(x / _ppm - Terrain.SIZE * 0.5, (y - IMG_H * 0.5) / _ppm)


func _pxs(pts: Array) -> Array:
	var out := []
	for p in pts: out.append(_px(p[0], p[1]))
	return out


func build() -> void:
	build_terrain()
	_build_sea()
	_build_coast_and_islets()
	_build_biomes()
	for name in HUB_TABLE.keys():
		build_hub(name)
	_build_town()
	_build_hamlet()
	_build_aqueducts()
	_build_boundaries()


## Sky, light and the heightfield with its roads and hub pads. Hubs can be built on top one at a
## time with build_hub(), which is what the tests use to get a fast level.
func build_terrain() -> void:
	rng.seed = 2026
	_load_meta()
	_build_environment()
	terrain = Terrain.new()
	terrain.name = "Terrain"
	_define_roads()
	for name in HUB_TABLE.keys():
		var c: Vector2 = HUB_TABLE[name][0]
		terrain.pads.append(Vector3(c.x, c.y, HUB_TABLE[name][1]))
	terrain.build()
	add_child(terrain)


func _load_meta() -> void:
	var f := FileAccess.open("res://data/island_meta.json", FileAccess.READ)
	if f == null: return
	var d: Variant = JSON.parse_string(f.get_as_text())
	if d is Dictionary:
		_ppm = float(d.get("px_per_m", _ppm))
		_islets = d.get("islets", [])


## Build one hub's buildings, props and delivery ring, and publish its Hub record.
func build_hub(name: String) -> Hub:
	var h := Hub.new(name, HUB_TABLE[name][0], HUB_TABLE[name][1], terrain)
	hubs[name] = h
	match name:
		"Villa Rosa": _build_villa_hub(h)
		"Hilltop Farm": _build_farm(h)
		"Harbour": _build_harbour(h)
		"Dunes Lookout": _build_lookout(h)
	return h


# ---------------------------------------------------------------- roads (painting pixels)
func _define_roads() -> void:
	# central spine: strait bridgehead -> forest valley -> farmland -> SW farmhouse
	terrain.add_road(_pxs([[760, 302], [722, 340], [690, 400], [642, 452], [600, 500], [560, 540], [500, 580], [440, 602], [398, 642], [350, 700], [300, 742]]))
	# villa lane: through the villa square (east-west), then down to the SW coast
	var lane := _pxs([[600, 500], [520, 472]])
	lane.append_array([Vector2(-160, 2), Vector2(-188, 2), Vector2(-206, 6)])
	lane.append_array(_pxs([[330, 522], [282, 562]]))
	terrain.add_road(lane)
	# mountain loop through the NW villages
	terrain.add_road(_pxs([[722, 340], [680, 300], [642, 255], [600, 222], [560, 182], [500, 132], [478, 92], [420, 62], [350, 82], [300, 142], [252, 202], [232, 262], [300, 322], [380, 342], [450, 332], [520, 334], [600, 334], [660, 338], [690, 400]]))
	# northern aqueduct across the strait into the town: a tall arcade, not a causeway
	terrain.viaducts.append({"a": Vector2(6.0, -109.5), "b": Vector2(52.0, -113.0), "deck": 15.0})
	terrain.add_road(_pxs([[760, 302], [800, 232], [838, 218], [950, 206], [1000, 182]]))
	# town: north ridge road to the lighthouse, and the loop down to the harbour front
	terrain.add_road(_pxs([[1000, 182], [1060, 142], [1100, 102], [1180, 72], [1280, 62], [1380, 82], [1460, 110], [1520, 104]]))
	terrain.add_road(_pxs([[1000, 182], [1030, 240], [1075, 275], [1150, 298], [1250, 288], [1330, 262], [1400, 222], [1430, 162], [1380, 122], [1300, 110], [1180, 72]]))
	# east-coast road round the badlands, back up to the harbour via the hamlet bay
	terrain.add_road(_pxs([[1330, 262], [1380, 332], [1420, 402], [1500, 470], [1520, 540], [1450, 602], [1380, 652], [1300, 702], [1250, 772], [1180, 832], [1100, 852], [1000, 862], [900, 852], [830, 802], [760, 762], [730, 702], [720, 642], [740, 582], [780, 542], [820, 502], [860, 470], [900, 430], [930, 380]]))
	# southern aqueduct: a viaduct over the gorge into the badlands, then the loop round the lake
	var a := _px(905, 508); var b := _px(1030, 545)
	terrain.viaducts.append({"a": a, "b": b, "deck": 19.0})
	terrain.add_road(_pxs([[820, 502], [870, 498], [1030, 545], [1080, 590]]))
	terrain.add_road(_pxs([[1030, 545], [1080, 590], [1150, 620], [1200, 680], [1180, 760], [1120, 800], [1050, 810], [980, 780], [940, 720], [960, 660], [1000, 610], [1030, 545]]))
	# hamlet track up to the bridgehead
	terrain.add_road(_pxs([[930, 380], [905, 330], [880, 290], [860, 250], [838, 218]]))


# ---------------------------------------------------------------- coast
func _build_coast_and_islets() -> void:
	var pale := _limestone_material()
	var red := _hoodoo_material()
	# islets and sea stacks from the painting
	for isl in _islets:
		var p := _px(isl[0], isl[1])
		var r: float = maxf(float(isl[2]) / _ppm, 1.5)
		if _near_road(p.x, p.y, 10.0): continue
		var s := r * rng.randf_range(0.9, 1.3)
		_add_rock(Vector3(p.x, -s * 0.45, p.y), Vector3(s, s * rng.randf_range(0.9, 1.8), s * rng.randf_range(0.7, 1.1)), rng.randf_range(0, 360), pale, s > 3.0)
		if r > 4.0:
			for k in range(2):
				var q := p + Vector2(rng.randf_range(-r, r), rng.randf_range(-r, r))
				var s2 := s * rng.randf_range(0.3, 0.6)
				_add_rock(Vector3(q.x, -s2 * 0.5, q.y), Vector3(s2, s2 * 1.4, s2), rng.randf_range(0, 360), pale, false)
	# offshore sea stacks: pale pillars standing in the water off the western and southern coasts
	var stacks := 0; var st_tries := 0
	while stacks < 60 and st_tries < 30000:
		st_tries += 1
		var x := rng.randf_range(-350, 350); var z := rng.randf_range(-215, 215)
		if x > 60.0 and z < 40.0: continue   # not in the harbour bay / town side
		if terrain.is_land(x, z) or terrain.biome_at(x, z) == Terrain.Biome.LAKE: continue
		var depth := _ground(x, z)
		if depth > -1.0 or depth < -8.0: continue
		if _near_road(x, z, 14.0): continue
		var s := rng.randf_range(2.0, 7.5)
		_add_rock(Vector3(x, -s * 0.5, z), Vector3(s, s * rng.randf_range(1.4, 2.6), s * rng.randf_range(0.7, 1.1)), rng.randf_range(0, 360), pale, s > 3.0)
		stacks += 1
	# coastal cliff boulders: pale rocks on the shore ring all round the island
	var placed := 0; var tries := 0
	while placed < 260 and tries < 20000:
		tries += 1
		var x := rng.randf_range(-350, 350); var z := rng.randf_range(-215, 215)
		var h := _ground(x, z)
		if h < -0.5 or h > 5.0: continue
		if terrain.biome_at(x, z) == Terrain.Biome.LAKE: continue
		if terrain.biome_at(x, z) != Terrain.Biome.BEACH and h > 1.5: continue
		if _near_location(x, z, 30.0): continue
		var s := rng.randf_range(1.5, 5.0)
		if terrain.road_dist_at(x, z) < 5.0 + s or _near_road(x, z, 6.0 + s): continue
		var rm: Material = red if terrain.biome_at(x, z) == Terrain.Biome.BADLANDS else pale
		_add_rock(Vector3(x, h - s * 0.35, z), Vector3(s, s * rng.randf_range(0.8, 1.5), s * rng.randf_range(0.7, 1.2)), rng.randf_range(0, 360), rm, s > 2.5)
		placed += 1


# ---------------------------------------------------------------- biomes
func _build_biomes() -> void:
	_build_forest()
	_build_limestone()
	_build_badlands()
	_build_farmland()
	_build_ground_cover()


## Scatter helper restricted to one biome; density-weighted when `use_density`.
func _scatter_biome(biome: int, count: int, min_road: float, max_slope: float, scale_range: Vector2, spread: float, use_density: bool, hub_clear: float = 24.0, min_h: float = 1.0) -> Array:
	var xforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	var tries := 0
	var half := Terrain.SIZE * 0.5 - 12.0
	while xforms.size() < count and tries < count * 30:
		tries += 1
		var x := rng.randf_range(-half, half)
		var z := rng.randf_range(-half * 0.62, half * 0.62)
		if terrain.biome_at(x, z) != biome: continue
		var h := _ground(x, z)
		if h < min_h: continue
		if terrain.road_dist_at(x, z) < min_road: continue
		if terrain.normal_at(x, z).y < 1.0 - max_slope: continue
		if use_density and rng.randf() > terrain.density_at(x, z) * 1.6 + 0.05: continue
		if hub_clear > 0.0 and _near_location(x, z, hub_clear): continue
		var s := rng.randf_range(scale_range.x, scale_range.y)
		var b := Basis(Vector3.UP, rng.randf_range(0, TAU)).scaled(Vector3(s, s * rng.randf_range(0.9, 1.15), s))
		xforms.append(Transform3D(b, Vector3(x, h - 0.05, z)))
		var v := rng.randf_range(-spread, spread)
		colors.append(Color(1.0 + v, 1.0 + v * 0.8, 1.0 + v * 0.5))
	return [xforms, colors]


func _build_forest() -> void:
	var pines := _scatter_biome(Terrain.Biome.FOREST, 720, 6.5, 0.55, Vector2(0.7, 1.3), 0.10, true, 22.0)
	_spawn_multimesh(_pine_parts(), pines[0], pines[1], 0.35)
	# pines also climb the mountain gullies and edge the town
	var pines2 := _scatter_biome(Terrain.Biome.LIMESTONE, 560, 6.0, 0.5, Vector2(0.6, 1.1), 0.10, true, 34.0)
	_spawn_multimesh(_pine_parts(), pines2[0], pines2[1], 0.35)
	var pines3 := _scatter_biome(Terrain.Biome.TOWN, 90, 6.0, 0.5, Vector2(0.6, 1.0), 0.10, true, 20.0)
	_spawn_multimesh(_pine_parts(), pines3[0], pines3[1], 0.35)
	var olives := _scatter_biome(Terrain.Biome.FOREST, 260, 5.0, 0.4, Vector2(0.8, 1.3), 0.10, false, 22.0)
	_spawn_multimesh(_olive_parts(), olives[0], olives[1], 0.5)


func _build_limestone() -> void:
	var pale := _limestone_material()
	# craggy outcrops on the steep faces of the massif
	var placed := 0; var tries := 0
	while placed < 220 and tries < 12000:
		tries += 1
		var x := rng.randf_range(-350, 60); var z := rng.randf_range(-215, -20)
		if terrain.biome_at(x, z) != Terrain.Biome.LIMESTONE: continue
		var h := _ground(x, z)
		if h < 6.0: continue
		var steep := 1.0 - terrain.normal_at(x, z).y
		if rng.randf() > steep * 2.5 + 0.08: continue
		if _near_location(x, z, 48.0): continue
		var s := rng.randf_range(3.0, 11.0)
		if terrain.road_dist_at(x, z) < 5.0 + s * 1.1 or _near_road(x, z, 5.0 + s * 1.1): continue
		_add_rock(Vector3(x, h - s * 0.4, z), Vector3(s, s * rng.randf_range(0.9, 1.6), s * rng.randf_range(0.7, 1.2)), rng.randf_range(0, 360), pale, s > 4.0)
		placed += 1
	# small pale boulders and scrub
	var bush := _scatter_biome(Terrain.Biome.LIMESTONE, 2800, 3.5, 0.6, Vector2(0.7, 1.6), 0.12, false, 30.0)
	_spawn_multimesh(_bush_parts(), bush[0], bush[1], 0.0)
	# a scatter of mountain houses along the loop road (the painting's hill villages)
	var houses := 0; tries = 0
	while houses < 14 and tries < 6000:
		tries += 1
		var x := rng.randf_range(-330, 20); var z := rng.randf_range(-205, -40)
		if terrain.biome_at(x, z) != Terrain.Biome.LIMESTONE: continue
		var rd := terrain.road_dist_at(x, z)
		if rd < 10.0 or rd > 15.0: continue
		if terrain.normal_at(x, z).y < 0.9: continue
		if _near_location(x, z, 34.0) or _near_house(x, z, 22.0): continue
		var t := terrain.nearest_road(Vector3(x, 0, z))
		var yaw := rad_to_deg(atan2(-(t.point.x - x), -(t.point.z - z)))
		_house(self, Vector3(x, _ground(x, z), z), yaw, rng.randf_range(6.0, 8.0), rng.randf_range(5.0, 6.5), 1 + rng.randi_range(0, 1), STONE.lerp(Color(0.95, 0.90, 0.80), rng.randf()))
		_houses.append(Vector2(x, z))
		houses += 1


var _houses: Array[Vector2] = []

func _near_house(x: float, z: float, r: float) -> bool:
	for p in _houses:
		if p.distance_to(Vector2(x, z)) < r: return true
	return false


func _build_badlands() -> void:
	# hoodoo spires: a forest of tapered stacks, tallest deep in the badlands
	var kits: Array = []
	for k in range(12): kits.append(_hoodoo_parts(300 + k))
	var groups: Array = []
	for k in range(12): groups.append([[] as Array[Transform3D], [] as Array[Color]])
	var placed := 0; var tries := 0
	var lake_c := _px(1060, 745)
	while placed < 340 and tries < 30000:
		tries += 1
		var x := rng.randf_range(-70, 230); var z := rng.randf_range(0, 190)
		if terrain.biome_at(x, z) != Terrain.Biome.BADLANDS: continue
		var h := _ground(x, z)
		if h < 3.0: continue
		if terrain.road_dist_at(x, z) < 5.5 or _near_road(x, z, 7.0): continue
		if _near_location(x, z, 16.0): continue
		var dl := lake_c.distance_to(Vector2(x, z))
		if dl < 40.0: continue
		var s := rng.randf_range(0.8, 1.8) * (0.8 + 0.5 * terrain.density_at(x, z))
		if rng.randf() < 0.12: s *= 1.5
		var k := rng.randi_range(0, 11)
		var tilt := Basis(Vector3(cos(rng.randf_range(0, TAU)), 0, sin(rng.randf_range(0, TAU))).normalized(), deg_to_rad(rng.randf_range(2.0, 8.0)))
		var b := (tilt * Basis(Vector3.UP, rng.randf_range(0, TAU))).scaled(Vector3(s * 1.7, s * rng.randf_range(0.5, 1.9), s * 1.7))
		groups[k][0].append(Transform3D(b, Vector3(x, h - 0.4, z)))
		var v := rng.randf_range(-0.12, 0.12)
		groups[k][1].append(Color(1.0 + v, 1.0 + v * 0.6, 1.0 + v * 0.3))
		placed += 1
	for k in range(12):
		_spawn_multimesh(kits[k], groups[k][0], groups[k][1], 0.9)
	# broken rock rubble between the spires
	var mat := _hoodoo_material()
	for k in range(120):
		var x := rng.randf_range(-70, 230); var z := rng.randf_range(0, 190)
		if terrain.biome_at(x, z) != Terrain.Biome.BADLANDS: continue
		var h := _ground(x, z)
		var s := rng.randf_range(1.5, 5.0)
		if h < 3.0 or terrain.road_dist_at(x, z) < 5.0 + s or _near_road(x, z, 6.0 + s) or _near_location(x, z, 16.0): continue
		_add_rock(Vector3(x, h - s * 0.35, z), Vector3(s, s * rng.randf_range(0.6, 1.2), s * rng.randf_range(0.7, 1.3)), rng.randf_range(0, 360), mat, s > 2.5)
	# sparse dark shrubs
	var bush := _scatter_biome(Terrain.Biome.BADLANDS, 300, 4.0, 0.6, Vector2(0.4, 0.9), 0.1, false, 14.0, 3.0)
	_spawn_multimesh(_bush_parts(), bush[0], bush[1], 0.0)


## Vineyard rows in the field strips, cypress avenues and a few farmhouses.
func _build_farmland() -> void:
	var vine_parts: Array[PropPart] = []
	var vmat := StandardMaterial3D.new(); vmat.albedo_color = Color(0.24, 0.40, 0.17); vmat.roughness = 1.0; vmat.vertex_color_use_as_albedo = true
	var vb := BoxMesh.new(); vb.size = Vector3(0.8, 1.2, 2.2)
	vine_parts.append(PropPart.new(vb, vmat, Transform3D(Basis(), Vector3(0, 0.6, 0))))
	var post := CylinderMesh.new(); post.top_radius = 0.05; post.bottom_radius = 0.05; post.height = 1.8; post.radial_segments = 5
	vine_parts.append(PropPart.new(post, Mats.solid(WOOD, 0.9), Transform3D(Basis(), Vector3(0, 0.9, -1.1))))
	var vine_x: Array[Transform3D] = []; var vine_c: Array[Color] = []
	# field patches read off the painting (pixel rectangles, rows run along the strip direction)
	var fields := [[300, 560, 460, 640], [480, 520, 600, 600], [250, 640, 420, 720], [430, 640, 560, 700], [300, 480, 380, 540], [560, 440, 660, 520], [400, 400, 520, 460], [200, 560, 300, 640], [470, 600, 600, 680], [520, 380, 640, 440], [360, 380, 460, 440], [230, 480, 300, 560], [600, 520, 700, 600]]
	for f in fields:
		var a := _px(f[0], f[1]); var b := _px(f[2], f[3])
		var tint := Color(1, 1, 1).lerp(Color(1.4, 1.2, 0.6), rng.randf() * 0.7)
		var x := a.x
		while x < b.x:
			var z := a.y
			while z < b.y:
				if terrain.biome_at(x, z) == Terrain.Biome.FARM and terrain.road_dist_at(x, z) > 4.5 and not _near_location(x, z, 14.0) and _ground(x, z) > 1.5:
					vine_x.append(Transform3D(Basis(Vector3.UP, 0.0).scaled(Vector3(0.9, 1.0, 0.9)), Vector3(x, _ground(x, z), z)))
					vine_c.append(tint.lerp(Color(1, 1, 1), rng.randf() * 0.3))
				z += 2.4
			x += 3.2
	_spawn_multimesh(vine_parts, vine_x, vine_c, 0.0)
	# cypress lines along the farm lanes and olive groves on the slopes
	var cyp := _scatter_biome(Terrain.Biome.FARM, 420, 4.0, 0.4, Vector2(0.9, 1.5), 0.08, false, 22.0)
	var keep_x: Array[Transform3D] = []; var keep_c: Array[Color] = []
	for i in range(cyp[0].size()):
		var o: Vector3 = cyp[0][i].origin
		if terrain.road_dist_at(o.x, o.z) < 9.0 or rng.randf() < 0.45:
			keep_x.append(cyp[0][i]); keep_c.append(cyp[1][i])
	_spawn_multimesh(_cypress_parts(), keep_x, keep_c, 0.4)
	var oli := _scatter_biome(Terrain.Biome.FARM, 260, 5.0, 0.4, Vector2(0.8, 1.4), 0.10, false, 22.0)
	_spawn_multimesh(_olive_parts(), oli[0], oli[1], 0.5)
	# farmhouses dotted round the fields
	for p in [[300, 742], [500, 585], [560, 445], [740, 395], [640, 470], [420, 640]]:
		var w := _px(p[0], p[1])
		var t := terrain.nearest_road(Vector3(w.x, 0, w.y))
		var side := Vector2(-t.tangent.z, t.tangent.x).normalized()
		var q := Vector2(t.point.x, t.point.z) + side * 13.0
		if not terrain.is_land(q.x, q.y) or _near_location(q.x, q.y, 30.0): continue
		var yaw := rad_to_deg(atan2(-(t.point.x - q.x), -(t.point.z - q.y)))
		var hs := _house(self, Vector3(q.x, _ground(q.x, q.y), q.y), yaw, 8.0, 6.5, 1, STONE.lerp(Color(0.95, 0.90, 0.80), rng.randf()))
		_houses.append(q)
		_place_prop(_cypress_parts(), Vector3(q.x + side.x * 6.0, _ground(q.x + side.x * 6.0, q.y + side.y * 6.0), q.y + side.y * 6.0), 1.2, 0.0)
	# the water tower on the ridge in the middle of the island
	var wt := _px(540, 372)
	_water_tower(self, Vector3(wt.x, _ground(wt.x, wt.y), wt.y))
	# cows in the meadows
	for k in range(10):
		var x := rng.randf_range(-250, -40); var z := rng.randf_range(-60, 120)
		if terrain.biome_at(x, z) != Terrain.Biome.FARM or terrain.road_dist_at(x, z) < 6.0 or _near_location(x, z, 24.0): continue
		_cow(self, Vector3(x, _ground(x, z), z), rng.randf_range(0, 360))


func _build_ground_cover() -> void:
	var grass := _scatter(5000, 3.0, 1.5, 80.0, 0.5, Vector2(0.7, 1.6), Color(1, 1, 1), 0.10, Rect2(-350, -215, 700, 430), 9.0)
	_spawn_multimesh(_grass_parts(), grass[0], grass[1], 0.0, false)
	var bush := _scatter(700, 3.6, 1.8, 60.0, 0.45, Vector2(0.5, 1.3), Color(1, 1, 1), 0.12, Rect2(-350, -215, 700, 430), 14.0)
	_spawn_multimesh(_bush_parts(), bush[0], bush[1], 0.0)
	var fl := _scatter(300, 3.0, 2.5, 30.0, 0.35, Vector2(0.6, 1.6), Color(1, 1, 1), 0.08, Rect2(-260, -80, 260, 200), 0.0)
	_spawn_multimesh(_flower_parts(Color(0.75, 0.45, 0.70)), fl[0], fl[1], 0.0, false)
	var fl2 := _scatter(200, 3.0, 2.5, 30.0, 0.35, Vector2(0.6, 1.4), Color(1, 1, 1), 0.08, Rect2(-260, -80, 260, 200), 0.0)
	_spawn_multimesh(_flower_parts(Color(0.92, 0.70, 0.30)), fl2[0], fl2[1], 0.0, false)


# ---------------------------------------------------------------- the town (NE peninsula)
func _build_town() -> void:
	var town := Node3D.new(); town.name = "Town"; add_child(town)
	var walls := [Color(0.93, 0.88, 0.76), Color(0.90, 0.80, 0.62), Color(0.88, 0.74, 0.58), Color(0.95, 0.92, 0.84), Color(0.86, 0.70, 0.52)]
	var roofs := [TERRACOTTA, Color(0.66, 0.36, 0.26), Color(0.78, 0.46, 0.30), Color(0.60, 0.34, 0.24)]
	var placed := 0; var tries := 0
	while placed < 110 and tries < 40000:
		tries += 1
		var x := rng.randf_range(40, 330); var z := rng.randf_range(-200, -40)
		if terrain.biome_at(x, z) != Terrain.Biome.TOWN: continue
		var h := _ground(x, z)
		if h < 2.0: continue
		var rd := terrain.road_dist_at(x, z)
		var w := rng.randf_range(5.5, 9.0); var d := rng.randf_range(5.0, 7.0)
		if rd < 5.5 + maxf(w, d) * 0.5 or rd > 18.0: continue   # the whole footprint clears the road
		if terrain.normal_at(x, z).y < 0.86: continue
		if _near_location(x, z, 26.0) or _near_house(x, z, 9.5): continue
		var t := terrain.nearest_road(Vector3(x, 0, z))
		var yaw := rad_to_deg(atan2(-(t.point.x - x), -(t.point.z - z)))
		var floors := 1 + rng.randi_range(0, 1) + (1 if rng.randf() < 0.25 else 0)
		_house(town, Vector3(x, h, z), yaw, w, d, floors, walls[rng.randi_range(0, walls.size() - 1)], roofs[rng.randi_range(0, roofs.size() - 1)])
		_houses.append(Vector2(x, z))
		if rng.randf() < 0.3:
			var pp := Vector3(x, h, z) + Vector3(cos(deg_to_rad(yaw)) * (w * 0.5 + 0.8), 0, -sin(deg_to_rad(yaw)) * (w * 0.5 + 0.8))
			if terrain.road_dist_at(pp.x, pp.z) > 5.5: _pot_plant(town, pp, 1.0)
		placed += 1
	# church with a bell tower on the town's high square
	var sq := _px(1160, 150)
	var sq_y := _ground(sq.x, sq.y)
	_flagstones(town, sq.x, sq.y, 10.0, Color(0.68, 0.64, 0.56))
	_house(town, Vector3(sq.x - 8, sq_y, sq.y - 6), 0, 9.0, 14.0, 2, Color(0.95, 0.92, 0.84))
	_tower(town, Vector3(sq.x - 1, sq_y, sq.y - 14), 4.0, 16.0, Color(0.95, 0.92, 0.84))
	_lamp_post(town, Vector3(sq.x + 4, sq_y, sq.y + 4))
	_lamp_post(town, Vector3(sq.x - 6, sq_y, sq.y + 6))
	# lighthouse at the tip of the peninsula
	var lh := _px(1540, 92)
	var lp := Vector3(lh.x, maxf(_ground(lh.x, lh.y), 1.0), lh.y)
	_lighthouse(town, lp)
	# the harbour front: a working waterfront below the town — a quay wall along the bay shore,
	# piers every ~18 m, boats packed along them and moored out in the bay
	var shore_pts := _shoreline(_px(960, 300), _px(1320, 345), 6.0)
	var quay_prev := Vector2.INF
	for sp in shore_pts:
		if quay_prev != Vector2.INF and quay_prev.distance_to(sp) < 14.0 and not _near_road(sp.x, sp.y, 7.0) and not _near_road(quay_prev.x, quay_prev.y, 7.0):
			_stone_wall(town, quay_prev, sp, 1.2)
		quay_prev = sp
	var pier_i := 0
	var hull_cols := [Color(0.20, 0.22, 0.28), Color(0.55, 0.20, 0.16), Color(0.16, 0.30, 0.45), Color(0.28, 0.40, 0.30), Color(0.75, 0.62, 0.30)]
	for i in range(0, shore_pts.size(), 3):
		var sp: Vector2 = shore_pts[i]
		var nrm := _sea_normal(sp)
		if nrm == Vector2.ZERO or _near_road(sp.x, sp.y, 8.0): continue
		var yaw := rad_to_deg(atan2(nrm.x, nrm.y)) + 180.0
		var len := 16.0 + (pier_i % 3) * 5.0
		_pier(town, Vector3(sp.x, 1.0, sp.y), yaw, len)
		# boats moored along both sides of the pier
		var along := Vector2(-sin(deg_to_rad(yaw)), -cos(deg_to_rad(yaw)))
		var perp := Vector2(along.y, -along.x)
		for side in [-1.0, 1.0]:
			var d := 6.0
			while d < len - 2.0:
				var bp: Vector2 = sp + along * d + perp * (side * 3.0)
				if not terrain.is_land(bp.x, bp.y):
					_boat(town, Vector3(bp.x, 0.2, bp.y), yaw + rng.randf_range(-8, 8), hull_cols[rng.randi_range(0, hull_cols.size() - 1)], rng.randf() < 0.3)
				d += 4.5
		pier_i += 1
	# quay clutter: crates, barrels and lamp posts along the waterfront
	var crate := Mats.solid(Color(0.62, 0.48, 0.30), 0.9)
	var barrel := Mats.solid(WOOD.darkened(0.1), 0.85)
	for i in range(shore_pts.size()):
		var sp: Vector2 = shore_pts[i]
		var nrm := _sea_normal(sp)
		if nrm == Vector2.ZERO or _near_road(sp.x, sp.y, 6.0): continue
		var q := sp - nrm * rng.randf_range(2.5, 5.0)
		var gy := _ground(q.x, q.y)
		if gy < 0.5: continue
		match i % 5:
			0:
				for k in range(rng.randi_range(1, 3)):
					var cp := q + Vector2(rng.randf_range(-1.2, 1.2), rng.randf_range(-1.2, 1.2))
					_static_box(town, Vector3(1.1, 1.1, 1.1), crate, Vector3(cp.x, _ground(cp.x, cp.y) + 0.55, cp.y), Vector3(0, rng.randf_range(0, 90), 0))
			1:
				for k in range(rng.randi_range(2, 4)):
					var bp := q + Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5))
					town.add_child(Mats.cylinder(0.45, 0.9, barrel, Vector3(bp.x, _ground(bp.x, bp.y) + 0.45, bp.y), Vector3.ZERO, 10))
					_add_cylinder_body(town, 0.45, 0.9, Vector3(bp.x, _ground(bp.x, bp.y), bp.y))
			2:
				_lamp_post(town, Vector3(q.x, gy, q.y))
			3:
				# a heap of nets
				town.add_child(Mats.sphere(0.9, Mats.solid(Color(0.45, 0.42, 0.30), 1.0), Vector3(q.x, gy + 0.3, q.y), Vector3(1.4, 0.5, 1.1), 8))
	# more boats riding at anchor out in the bay
	var moored := 0; var btries := 0
	while moored < 14 and btries < 2000:
		btries += 1
		var w := _px(rng.randf_range(960, 1300), rng.randf_range(330, 420))
		if terrain.is_land(w.x, w.y) or _ground(w.x, w.y) > -1.2: continue
		_boat(town, Vector3(w.x, 0.2, w.y), rng.randf_range(0, 360), hull_cols[rng.randi_range(0, hull_cols.size() - 1)], rng.randf() < 0.5)
		moored += 1
	# signposts at the town approach
	var ap := _px(1010, 186)
	_signpost(town, Vector3(ap.x + 4, _ground(ap.x + 4, ap.y + 5), ap.y + 5), 20, [["HARBOUR", 1.0], ["LIGHTHOUSE", 1.0], ["VILLA ROSA", -1.0]])


## Points along the shore between two painting positions: samples the segment, and for each
## sample walks perpendicular to it until the land/sea edge. Returns land-side points `step` apart.
func _shoreline(a: Vector2, b: Vector2, step: float) -> Array:
	var out: Array = []
	var n := int(a.distance_to(b) / step)
	var dir := (b - a).normalized()
	var perp := Vector2(-dir.y, dir.x)
	for i in range(n + 1):
		var q := a + dir * (i * step)
		var best := Vector2.INF
		for sgn in [1.0, -1.0]:
			var prev_land := terrain.is_land(q.x, q.y) and _ground(q.x, q.y) > 0.4
			for r in range(1, 40):
				var t: Vector2 = q + perp * (sgn * r)
				var land := terrain.is_land(t.x, t.y) and _ground(t.x, t.y) > 0.4
				if land != prev_land:
					var edge: Vector2 = t if land else q + perp * (sgn * (r - 1))
					if best == Vector2.INF or edge.distance_to(q) < best.distance_to(q): best = edge
					break
		if best != Vector2.INF and (out.is_empty() or out[out.size() - 1].distance_to(best) > step * 0.5):
			out.append(best)
	return out


## Unit direction from a shore point towards open water (zero if no water nearby).
func _sea_normal(p: Vector2) -> Vector2:
	var acc := Vector2.ZERO
	for a in range(16):
		var dir := Vector2(cos(a * TAU / 16.0), sin(a * TAU / 16.0))
		for r in [4.0, 8.0, 12.0]:
			var q: Vector2 = p + dir * r
			if not terrain.is_land(q.x, q.y) or _ground(q.x, q.y) < 0.0: acc += dir
	return acc.normalized() if acc.length() > 0.5 else Vector2.ZERO


## Walk from `p` towards the nearest land (or sea) until the shoreline; returns a point `back`
## metres inland from the water's edge.
func _shore_point(p: Vector2, back: float) -> Vector2:
	var best := p
	var best_d := 1e9
	for a in range(24):
		var dir := Vector2(cos(a * TAU / 24.0), sin(a * TAU / 24.0))
		for r in range(2, 60, 2):
			var q := p + dir * r
			if terrain.is_land(q.x, q.y) and _ground(q.x, q.y) > 0.6:
				if r < best_d:
					best_d = r; best = q + dir * back * 0.3
				break
	if terrain.is_land(p.x, p.y) and _ground(p.x, p.y) > 0.6:
		return p
	return best


# ---------------------------------------------------------------- hamlet by the bay
func _build_hamlet() -> void:
	var hm := Node3D.new(); hm.name = "Hamlet"; add_child(hm)
	for p in [[912, 318], [896, 348], [935, 300], [925, 372], [905, 395]]:
		var w := _px(p[0], p[1])
		if not terrain.is_land(w.x, w.y) or _ground(w.x, w.y) < 1.5: continue
		if terrain.road_dist_at(w.x, w.y) < 9.5 or _near_house(w.x, w.y, 8.0): continue
		var t := terrain.nearest_road(Vector3(w.x, 0, w.y))
		var yaw := rad_to_deg(atan2(-(t.point.x - w.x), -(t.point.z - w.y)))
		_house(hm, Vector3(w.x, _ground(w.x, w.y), w.y), yaw, rng.randf_range(6, 8), rng.randf_range(5, 6.5), 1 + rng.randi_range(0, 1), Color(0.92, 0.86, 0.72))
		_houses.append(w)
	var wp := _px(965, 345)
	var shore := _shore_point(wp, 10.0)
	_pier(hm, Vector3(shore.x, 1.0, shore.y), 250.0, 16.0)
	var bp := _px(985, 372)
	if not terrain.is_land(bp.x, bp.y):
		_boat(hm, Vector3(bp.x, 0.25, bp.y), 40.0, Color(0.85, 0.30, 0.25))


# ---------------------------------------------------------------- aqueducts
## Every elevated road stretch the terrain found (the strait crossing and the badlands viaduct)
## becomes an arched stone aqueduct with a rideable deck.
func _build_aqueducts() -> void:
	var aq := Node3D.new(); aq.name = "Aqueducts"; add_child(aq)
	var stone := Mats.solid(Color(0.81, 0.76, 0.64), 0.95)
	for b in terrain.bridges:
		if b.to - b.from < 8: continue
		var samples: PackedVector3Array = terrain.road_samples[b.road]
		# the deck also covers the embankment ramps on both banks (wherever the road sits above the ground)
		var pts := PackedVector3Array()
		var k: int = b.from
		while k > 0 and samples[k - 1].y - terrain.height_at(samples[k - 1].x, samples[k - 1].z) > 0.25 and b.from - k < 80: k -= 1
		var last_k: int = b.to
		while last_k < samples.size() - 1 and samples[last_k + 1].y - terrain.height_at(samples[last_k + 1].x, samples[last_k + 1].z) > 0.25 and last_k - b.to < 80: last_k += 1
		k = maxi(k - 3, 0); last_k = mini(last_k + 3, samples.size() - 1)
		while k <= last_k:
			pts.append(samples[k])
			k += 4
		if pts[pts.size() - 1] != samples[last_k]: pts.append(samples[last_k])
		_arcade(aq, pts, b.deck, stone)


# ---------------------------------------------------------------- hubs
func _build_villa_hub(hb_rec: Hub) -> void:
	var hub := Node3D.new(); hub.name = "VillaHub"; add_child(hub)
	var cx := hb_rec.centre.x; var cz := hb_rec.centre.y
	var g := _ground(cx, cz)
	_flagstones(hub, cx + 1, cz + 4, 11.0)
	var villa := _house(hub, Vector3(cx - 16, g, cz - 6), 32, 10.0, 8.0, 2)
	villa.add_child(Mats.box(Vector3(5.5, 0.25, 8.0), Mats.solid(STONE_DARK, 0.9), Vector3(7.7, 3.2, 0)))
	villa.add_child(Mats.box(Vector3(5.5, 1.0, 0.1), Mats.solid(Color(0.15, 0.15, 0.15), 0.6, 0.3), Vector3(7.7, 3.8, -3.95)))
	villa.add_child(Mats.cylinder(0.04, 2.4, Mats.solid(Color(0.6, 0.6, 0.6), 0.5, 0.4), Vector3(7.7, 4.5, -1)))
	villa.add_child(Mats.cone(1.6, 0.7, Mats.solid(Color(0.55, 0.62, 0.85), 0.9), Vector3(7.7, 5.7, -1), 10))
	var office := _house(hub, Vector3(cx + 15, g, cz - 9), -90, 9.0, 7.0, 1, Color(0.80, 0.72, 0.58))
	_awning(office, Vector3(0, 2.65, -3.5), 0, 6.0, Color(0.25, 0.48, 0.30))
	_pot_plant(office, Vector3(-3.2, 0, -4.4), 1.1)
	_pot_plant(office, Vector3(3.4, 0, -4.4), 0.9)
	for i in range(3):
		office.add_child(Mats.cylinder(0.45, 0.9, Mats.solid(WOOD, 0.85), Vector3(4.2 + i * 0.6, 0.45, -1.5 + i * 0.9), Vector3.ZERO, 10))
		_add_cylinder_body(office, 0.45, 0.9, Vector3(4.2 + i * 0.6, 0.0, -1.5 + i * 0.9))
	var gate := Node3D.new(); gate.position = Vector3(cx + 2, g, cz + 17); gate.rotation_degrees = Vector3(0, 20, 0); hub.add_child(gate)
	var stone := Mats.solid(STONE, 0.9)
	_static_box(gate, Vector3(1.2, 4.0, 1.2), stone, Vector3(-2.2, 2.0, 0))
	_static_box(gate, Vector3(1.2, 4.0, 1.2), stone, Vector3(2.2, 2.0, 0))
	gate.add_child(Mats.box(Vector3(5.6, 0.8, 1.4), stone, Vector3(0, 4.4, 0)))
	gate.add_child(Mats.prism(Vector3(6.4, 1.3, 2.4), Mats.solid(TERRACOTTA, 0.85), Vector3(0, 5.45, 0)))
	_stone_wall(hub, Vector2(cx - 22, cz + 14), Vector2(cx - 4, cz + 26))
	_stone_wall(hub, Vector2(cx + 22, cz + 18), Vector2(cx + 36, cz + 30))
	_lamp_post(hub, Vector3(cx + 11, _ground(cx + 11, cz + 8), cz + 8))
	_lamp_post(hub, Vector3(cx - 7, _ground(cx - 7, cz - 12), cz - 12))
	_signpost(hub, Vector3(cx + 5.5, _ground(cx + 5.5, cz - 6), cz - 6), 35, [["HILLTOP FARM", -1.0], ["HARBOUR", 1.0], ["THE DUNES", 1.0]])
	_pot_plant(hub, Vector3(cx - 8, g, cz + 6), 1.2)
	_pot_plant(hub, Vector3(cx - 6, g, cz + 14), 1.0)
	var plinth := Node3D.new(); plinth.position = Vector3(cx - 8, g, cz + 9); hub.add_child(plinth)
	_static_box(plinth, Vector3(2.2, 1.2, 2.2), stone, Vector3(0, 0.6, 0))
	plinth.add_child(Mats.box(Vector3(1.4, 1.6, 1.4), stone, Vector3(0, 2.0, 0)))
	plinth.add_child(Mats.capsule(0.32, 1.4, Mats.solid(Color(0.92, 0.90, 0.86), 0.6), Vector3(0, 3.7, 0)))
	plinth.add_child(Mats.sphere(0.28, Mats.solid(Color(0.92, 0.90, 0.86), 0.6), Vector3(0, 4.75, 0)))
	# the painting's tall cypress sentinels round the villa
	var cyp := _cypress_parts(); var oli := _olive_parts()
	for p in [Vector2(-24, 12), Vector2(-24, 6), Vector2(-9, -14), Vector2(24, 12), Vector2(-4, 22), Vector2(-28, -10), Vector2(-20, -18), Vector2(4, -20), Vector2(20, -18)]:
		_place_prop(cyp, Vector3(cx + p.x, _ground(cx + p.x, cz + p.y), cz + p.y), rng.randf_range(1.1, 1.6), rng.randf_range(0, 360))
	for p in [Vector2(-30, 12), Vector2(26, -6), Vector2(28, 26), Vector2(-16, 30)]:
		_place_prop(oli, Vector3(cx + p.x, _ground(cx + p.x, cz + p.y), cz + p.y), rng.randf_range(1.0, 1.4), rng.randf_range(0, 360))
	_register("Villa Rosa Office", cx + 6.5, cz - 4, Vector3(-1, 0, 0))
	_register("Villa Square", cx, cz, Vector3(0, 0, -1))
	hb_rec.ring_pos = locations["Villa Rosa Office"].pos; hb_rec.ring_facing = Vector3(-1, 0, 0)


func _build_farm(hb_rec: Hub) -> void:
	var farm := Node3D.new(); farm.name = "Farm"; add_child(farm)
	var cx := hb_rec.centre.x; var cz := hb_rec.centre.y
	var g := _ground(cx, cz)
	var barn := _house(farm, Vector3(cx + 24, g, cz - 12), 10, 12.0, 9.0, 1, Color(0.66, 0.52, 0.36), Color(0.50, 0.34, 0.22))
	barn.scale = Vector3(1, 1.5, 1)
	_house(farm, Vector3(cx - 10, g, cz + 6), 70, 8.0, 6.5, 1)
	var truck := Node3D.new(); truck.position = Vector3(cx - 20, g, cz + 22); truck.rotation_degrees = Vector3(0, -65, 0); farm.add_child(truck)
	var green := Mats.solid(Color(0.62, 0.66, 0.36), 0.6)
	_static_box(truck, Vector3(1.6, 1.5, 1.7), green, Vector3(0, 1.15, -1.4))
	_static_box(truck, Vector3(1.7, 0.7, 2.6), green, Vector3(0, 0.75, 0.9))
	truck.add_child(Mats.box(Vector3(1.4, 0.6, 0.1), Mats.solid(Color(0.2, 0.25, 0.3), 0.2), Vector3(0, 1.5, -2.26)))
	for p in [Vector3(-0.85, 0.4, -1.3), Vector3(0.85, 0.4, -1.3), Vector3(-0.85, 0.4, 1.4), Vector3(0.85, 0.4, 1.4)]:
		truck.add_child(Mats.cylinder(0.4, 0.3, Mats.solid(Color(0.1, 0.1, 0.1), 0.9), p, Vector3(0, 0, 90), 12))
	var ws := Node3D.new(); ws.position = Vector3(cx - 22, _ground(cx - 22, cz - 14), cz - 14); farm.add_child(ws)
	ws.add_child(Mats.cylinder(0.05, 6.0, Mats.solid(Color(0.6, 0.6, 0.6), 0.5, 0.4), Vector3(0, 3, 0)))
	ws.add_child(Mats.cylinder(0.32, 2.2, Mats.solid(Color(0.95, 0.40, 0.15), 0.8), Vector3(1.1, 5.9, 0), Vector3(0, 0, 90), 10, 0.18))
	_add_cylinder_body(ws, 0.1, 6.0, Vector3.ZERO)
	_stone_wall(farm, Vector2(cx + 6, cz - 24), Vector2(cx + 40, cz - 24), 0.8, hb_rec)   # the long wall east of the road (tin cans go here)
	_stone_wall(farm, Vector2(cx + 40, cz - 24), Vector2(cx + 36, cz + 14), 0.8, hb_rec)
	for i in range(4):
		farm.add_child(Mats.cylinder(0.7, 1.2, Mats.solid(Color(0.86, 0.72, 0.38), 1.0), Vector3(cx - 16 + i * 1.6, g + 0.7, cz + 18), Vector3(90, 0, 0), 10))
		_add_cylinder_body(farm, 0.7, 1.4, Vector3(cx - 16 + i * 1.6, g, cz + 18))
	_lamp_post(farm, Vector3(cx - 8, g, cz + 8))
	_signpost(farm, Vector3(cx - 4, _ground(cx - 4, cz + 14), cz + 14), 60, [["VILLA ROSA", 1.0], ["HILLTOP FARM", -1.0]])
	var cypf := _cypress_parts(); var olif := _olive_parts()
	for p in [Vector2(-18, -6), Vector2(-20, 0), Vector2(22, -18), Vector2(-26, 16), Vector2(8, 22)]:
		_place_prop(cypf, Vector3(cx + p.x, _ground(cx + p.x, cz + p.y), cz + p.y), rng.randf_range(0.9, 1.3), rng.randf_range(0, 360))
	for p in [Vector2(-32, 8), Vector2(28, 4), Vector2(16, -24)]:
		_place_prop(olif, Vector3(cx + p.x, _ground(cx + p.x, cz + p.y), cz + p.y), rng.randf_range(1.0, 1.5), rng.randf_range(0, 360))
	for k in range(4):
		var x := cx + rng.randf_range(-40, 40); var z := cz + rng.randf_range(-40, 40)
		if terrain.road_dist_at(x, z) < 6.0 or _near_location(x, z, 20.0) or terrain.normal_at(x, z).y < 0.9: continue
		_cow(farm, Vector3(x, _ground(x, z), z), rng.randf_range(0, 360))
	_register("Hilltop Farm", cx - 3, cz + 1, Vector3(0, 0, 1))
	hb_rec.ring_pos = locations["Hilltop Farm"].pos; hb_rec.ring_facing = Vector3(0, 0, 1)


func _build_harbour(hb_rec: Hub) -> void:
	var hb := Node3D.new(); hb.name = "Harbour"; add_child(hb)
	var cx := hb_rec.centre.x; var cz := hb_rec.centre.y
	var g := _ground(cx, cz)
	_flagstones(hb, cx + 2, cz + 2, 12.0, Color(0.60, 0.57, 0.52))
	_house(hb, Vector3(cx - 14, g, cz - 10), 25, 7.0, 6.0, 2, Color(0.88, 0.80, 0.66))
	_house(hb, Vector3(cx - 8, g, cz + 12), -60, 6.0, 5.0, 1, Color(0.82, 0.74, 0.60))
	var cafe := _house(hb, Vector3(cx + 10, g, cz - 6), -110, 8.0, 6.0, 1, Color(0.90, 0.84, 0.70))
	_awning(cafe, Vector3(0, 2.65, -3.0), 0, 5.5, Color(0.72, 0.28, 0.25))
	_pot_plant(cafe, Vector3(-3, 0, -4), 1.0)
	for i in range(2):
		cafe.add_child(Mats.cylinder(0.5, 0.05, Mats.solid(Color(0.9, 0.9, 0.9), 0.5), Vector3(-1.5 + i * 3.0, 0.75, -4.2), Vector3.ZERO, 10))
		cafe.add_child(Mats.cylinder(0.04, 0.75, Mats.solid(Color(0.2, 0.2, 0.2), 0.5, 0.3), Vector3(-1.5 + i * 3.0, 0.37, -4.2)))
	for p in [Vector2(-14, -10), Vector2(-8, 12), Vector2(10, -6)]:
		_houses.append(Vector2(cx + p.x, cz + p.y))
	_lamp_post(hb, Vector3(cx + 2, g, cz + 4))
	_lamp_post(hb, Vector3(cx + 18, g, cz + 12))
	_signpost(hb, Vector3(cx - 6, _ground(cx - 6, cz - 20), cz - 20), -30, [["VILLA ROSA", -1.0], ["HARBOUR", 1.0]])
	_pot_plant(hb, Vector3(cx - 2, g, cz + 10), 1.1)
	var cyph := _cypress_parts()
	for p in [Vector2(-22, -4), Vector2(-20, 14), Vector2(18, -16)]:
		_place_prop(cyph, Vector3(cx + p.x, _ground(cx + p.x, cz + p.y), cz + p.y), rng.randf_range(0.9, 1.3), rng.randf_range(0, 360))
	_register("Harbour Cafe", cx + 2, cz + 4, Vector3(0, 0, -1))
	hb_rec.ring_pos = locations["Harbour Cafe"].pos; hb_rec.ring_facing = Vector3(0, 0, -1)


func _build_lookout(hb_rec: Hub) -> void:
	var lk := Node3D.new(); lk.name = "Lookout"; add_child(lk)
	var cx := hb_rec.centre.x; var cz := hb_rec.centre.y
	var g := _ground(cx, cz)
	# an old stone hut with a bench looking over the lake in the badlands
	_house(lk, Vector3(cx - 8, g, cz - 4), 110, 5.0, 4.5, 1, STONE_DARK, Color(0.5, 0.42, 0.34))
	_signpost(lk, Vector3(cx + 2, _ground(cx + 2, cz + 6), cz + 6), -70, [["THE DUNES", 1.0], ["VILLA ROSA", -1.0]])
	lk.add_child(Mats.box(Vector3(2.0, 0.1, 0.5), Mats.solid(WOOD, 0.9), Vector3(cx + 4, g + 0.5, cz - 3)))
	hb_rec.bench = Vector3(cx + 4, g + 0.55, cz - 3); hb_rec.bench_width = 2.0
	for sx in [-0.8, 0.8]:
		lk.add_child(Mats.box(Vector3(0.1, 0.5, 0.5), Mats.solid(WOOD, 0.9), Vector3(cx + 4 + sx, g + 0.25, cz - 3)))
	_register("Dunes Lookout", cx + 1, cz - 1, Vector3(1, 0, 0))
	hb_rec.ring_pos = locations["Dunes Lookout"].pos; hb_rec.ring_facing = Vector3(1, 0, 0)
