class_name Island
extends WorldKit
## The island from the reference painting (data/island_map.png is extracted from it and grown
## by world/mapgen/expand.py): limestone mountains NW, harbour town on the NE peninsula (joined by
## an aqueduct across the strait), forest and a hamlet by the bay in the centre, vineyards and the
## villa SW, red hoodoo badlands around a lake SE, sea stacks all round. North of the massif the
## Highlands: moorland with the monastery on its peak, the marble quarry and the refugio on the
## pass. South of everything the Southern Shore: dunes and the fishing cove of Cala Blanca, the
## salt pans of the Salinas, the bodega's vineyards, a lagoon, and the old fort on the badlands
## headland. Roads on the painted part are traced in painting pixels (`_px`); on the new land in
## world metres.
##
## This is a GENERATOR: `generate()` builds the resident world (terrain, sea, sky) into the
## environment node and writes everything else into the WorldDatabase as build recipes, one per
## chunk (`_at(x, z, callable)`). The WorldStreamer runs those recipes when a chunk loads.
## Gameplay data (delivery ring positions, hub walls and benches) is defined here at generation
## time, so it exists whether or not the chunk is loaded.

## The hubs: id -> [centre (world m), flat pad radius]. The one place these numbers live.
## The first four are the painting's places (scaled by K), the rest live on the new land.
const HUB_TABLE := {
	&"villa_rosa": [Vector2(-326, 3), 24.0],
	&"hilltop_farm": [Vector2(-265, -253), 20.0],
	&"harbour": [Vector2(189, -156), 20.0],
	&"dunes_lookout": [Vector2(166, 127), 10.0],
	&"monastery": [Vector2(-300, -468), 17.0],
	&"quarry": [Vector2(-125, -398), 24.0],
	&"cala_blanca": [Vector2(-340, 438), 16.0],
	&"salinas": [Vector2(-160, 433), 15.0],
}
## Named places without a hub: id -> [position, facing, display name]; each gets a delivery ring
## and a little geometry (`_build_place`).
const PLACE_TABLE := {
	&"bodega": [Vector2(20, 430), Vector3(0, 0, -1), "Bodega San Marco"],
	&"torre_vieja": [Vector2(330, 520), Vector3(-1, 0, 0), "Torre Vieja"],
	&"lakeside_camp": [Vector2(88, 205), Vector3(1, 0, 0), "Lakeside Camp"],
	&"windmill_ridge": [Vector2(-225, -112), Vector3(0, 0, 1), "Windmill Ridge"],
	&"chapel": [Vector2(-15, 78), Vector3(-1, 0, 0), "Hill Chapel"],
	&"refugio": [Vector2(-335, -390), Vector3(1, 0, 0), "The Refugio"],
}

const IMG_W := 1672.0
const IMG_H := 941.0
const K := Terrain.SIZE / 720.0   # scale from the painting's 720 m world to this one
var _ppm := 1.34
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


## Record a build recipe for the chunk containing (x, z).
func _at(x: float, z: float, builder: Callable) -> void:
	db.add(x, z, builder)


## Split a scatter into per-chunk MultiMesh recipes.
func _scatter_records(parts: Array[PropPart], xforms: Array[Transform3D], colors: Array[Color], collide_radius: float = 0.0, shadows: bool = true) -> void:
	var by_chunk: Dictionary = {}
	for i in range(xforms.size()):
		var c := db.chunk_of_pos(xforms[i].origin)
		if not by_chunk.has(c): by_chunk[c] = [[] as Array[Transform3D], [] as Array[Color]]
		by_chunk[c][0].append(xforms[i]); by_chunk[c][1].append(colors[i])
	for c in by_chunk.keys():
		var xf: Array[Transform3D] = by_chunk[c][0]; var col: Array[Color] = by_chunk[c][1]
		var o := db.chunk_origin(c)
		_at(o.x + 1.0, o.z + 1.0, func(): _spawn_multimesh(parts, xf, col, collide_radius, shadows))


## Build the resident world into `env` and describe the rest in `database`.
func generate(database: WorldDatabase, env: Node3D, seed_v: int) -> void:
	db = database
	sink = env
	rng.seed = seed_v
	build_terrain()
	_build_sea()
	_build_boundaries()
	sink = null
	_gen_coast_and_islets()
	_gen_biomes()
	for id in HUB_TABLE.keys():
		define_hub(id)
	for id in PLACE_TABLE.keys():
		define_place(id)
	_gen_town()
	_gen_hamlet()
	_gen_highlands()
	_gen_south_shore()
	_gen_aqueducts()


## Sky, light and the heightfield with its roads and hub pads (resident, into `sink`).
func build_terrain() -> void:
	_load_meta()
	_build_environment()
	terrain = Terrain.new()
	terrain.name = "Terrain"
	sink.add_child(terrain)   # in the tree first: Terrain3D initialises its data on entering it
	_define_roads()
	for id in HUB_TABLE.keys():
		var c: Vector2 = HUB_TABLE[id][0]
		terrain.pads.append(Vector3(c.x, c.y, HUB_TABLE[id][1]))
	for id in PLACE_TABLE.keys():
		var c: Vector2 = PLACE_TABLE[id][0]
		terrain.pads.append(Vector3(c.x, c.y, 9.0))
	terrain.build()
	terrain.plant_ground_cover(rng.randi())
	print("[terrain] build stages ms: ", terrain.build_ms)


func _load_meta() -> void:
	var f := FileAccess.open("res://data/island_meta.json", FileAccess.READ)
	if f == null: return
	var d: Variant = JSON.parse_string(f.get_as_text())
	if d is Dictionary:
		_ppm = float(d.get("px_per_m", _ppm))
		_islets = d.get("islets", [])


## Publish one hub's data (ring, walls, bench) and record its geometry recipe.
func define_hub(id: StringName) -> Hub:
	var h := Hub.new(id, HUB_TABLE[id][0], HUB_TABLE[id][1], terrain)
	db.hubs[id] = h
	match id:
		&"villa_rosa":
			_define_villa(h); _at(h.centre.x, h.centre.y, func(): _build_villa_hub(h))
		&"hilltop_farm":
			_define_farm(h); _at(h.centre.x, h.centre.y, func(): _build_farm(h))
		&"harbour":
			_define_harbour(h); _at(h.centre.x, h.centre.y, func(): _build_harbour(h))
		&"dunes_lookout":
			_define_lookout(h); _at(h.centre.x, h.centre.y, func(): _build_lookout(h))
		&"monastery":
			_define_monastery(h); _at(h.centre.x, h.centre.y, func(): _build_monastery(h))
		&"quarry":
			_define_quarry(h); _at(h.centre.x, h.centre.y, func(): _build_quarry(h))
		&"cala_blanca":
			_define_cala(h); _at(h.centre.x, h.centre.y, func(): _build_cala(h))
		&"salinas":
			_define_salinas(h); _at(h.centre.x, h.centre.y, func(): _build_salinas(h))
	return h


## A named place: its location record (ring position on the pad) and a geometry recipe.
func define_place(id: StringName) -> void:
	var c: Vector2 = PLACE_TABLE[id][0]
	_register(id, PLACE_TABLE[id][2], c.x, c.y, PLACE_TABLE[id][1])
	_at(c.x, c.y, func(): _build_place(id, c))


# ---------------------------------------------------------------- roads (painting pixels)
func _define_roads() -> void:
	# central spine: strait bridgehead -> forest valley -> farmland -> SW farmhouse
	terrain.add_road(_pxs([[760, 302], [722, 340], [690, 400], [642, 452], [600, 500], [560, 540], [500, 580], [440, 602], [398, 642], [350, 700], [300, 742]]))
	# villa lane: through the villa square (east-west), then down to the SW coast
	var lane := _pxs([[600, 500], [520, 472]])
	lane.append_array([Vector2(-277, 3), Vector2(-326, 3), Vector2(-357, 10)])
	lane.append_array(_pxs([[330, 522], [282, 562]]))
	terrain.add_road(lane)
	# mountain loop through the NW villages
	terrain.add_road(_pxs([[722, 340], [680, 300], [642, 255], [600, 222], [560, 182], [500, 132], [478, 92], [420, 62], [350, 82], [300, 142], [252, 202], [232, 262], [300, 322], [380, 342], [450, 332], [520, 334], [600, 334], [660, 338], [690, 400]]))
	# northern aqueduct across the strait into the town: a tall arcade, not a causeway
	terrain.viaducts.append({"a": Vector2(6.0 * K, -109.5 * K), "b": Vector2(52.0 * K, -113.0 * K), "deck": 15.0})
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
	# ---- the Highlands (world metres): the pass road from the top of the mountain loop up past
	# the refugio to the monastery, and the quarry loop back down to the loop's north-east corner
	terrain.add_road([_px(420, 62), Vector2(-322, -340), Vector2(-335, -390), Vector2(-322, -430), Vector2(-300, -468)])
	terrain.add_road([Vector2(-322, -430), Vector2(-262, -428), Vector2(-192, -412), Vector2(-125, -398), Vector2(-118, -350), Vector2(-150, -290), Vector2(-165, -240), _px(600, 222)])
	# ---- the Southern Shore: the coast road from the villa lane's end round the west coast to
	# Cala Blanca, along the dunes past the Salinas and the bodega to the old fort on the headland
	terrain.add_road([_px(282, 562), Vector2(-440, 150), Vector2(-446, 250), Vector2(-432, 330), Vector2(-405, 395), Vector2(-360, 425), Vector2(-340, 438),
		Vector2(-300, 468), Vector2(-232, 480), Vector2(-175, 452), Vector2(-160, 433), Vector2(-92, 428), Vector2(-20, 440), Vector2(20, 430), Vector2(108, 430),
		Vector2(200, 455), Vector2(288, 492), Vector2(330, 520)])
	# the bodega's link north through the southern forest to the east-coast road
	terrain.add_road([Vector2(108, 430), Vector2(104, 380), Vector2(116, 330), _px(1000, 862)])
	# short tracks to the hill chapel and the lakeside camp
	terrain.add_road([_px(780, 542), Vector2(-25, 72), Vector2(-15, 78)])
	terrain.add_road([_px(940, 720), Vector2(84, 198), Vector2(88, 205)])


# ---------------------------------------------------------------- coast
func _gen_coast_and_islets() -> void:
	var pale := _limestone_material()
	var red := _hoodoo_material()
	# islets and sea stacks from the painting
	for isl in _islets:
		var p := _px(isl[0], isl[1])
		var r: float = maxf(float(isl[2]) / _ppm, 1.5)
		if _near_road(p.x, p.y, 10.0): continue
		var s := r * rng.randf_range(0.9, 1.3)
		var scl := Vector3(s, s * rng.randf_range(0.9, 1.8), s * rng.randf_range(0.7, 1.1)); var yaw := rng.randf_range(0, 360)
		_at(p.x, p.y, func(): _add_rock(Vector3(p.x, -s * 0.45, p.y), scl, yaw, pale, s > 3.0))
		if r > 4.0:
			for k in range(2):
				var q := p + Vector2(rng.randf_range(-r, r), rng.randf_range(-r, r))
				var s2 := s * rng.randf_range(0.3, 0.6); var yaw2 := rng.randf_range(0, 360)
				_at(q.x, q.y, func(): _add_rock(Vector3(q.x, -s2 * 0.5, q.y), Vector3(s2, s2 * 1.4, s2), yaw2, pale, false))
	# offshore sea stacks: pale pillars standing in the water off the western and southern coasts
	var stacks := 0; var st_tries := 0
	var hw := Terrain.SIZE * 0.5 - 12.0
	while stacks < 160 and st_tries < 90000:
		st_tries += 1
		var x := rng.randf_range(-hw, hw); var z := rng.randf_range(-hw, hw)
		if x > 104.0 and z < 69.0 and z > -400.0: continue   # not in the harbour bay / town side
		if terrain.is_land(x, z) or terrain.biome_at(x, z) == Terrain.Biome.LAKE: continue
		var depth := _ground(x, z)
		if depth > -1.0 or depth < -8.0: continue
		if _near_road(x, z, 14.0): continue
		var s := rng.randf_range(2.0, 7.5)
		var scl := Vector3(s, s * rng.randf_range(1.4, 2.6), s * rng.randf_range(0.7, 1.1)); var yaw := rng.randf_range(0, 360)
		_at(x, z, func(): _add_rock(Vector3(x, -s * 0.5, z), scl, yaw, pale, s > 3.0))
		stacks += 1
	# coastal cliff boulders: pale rocks on the shore ring all round the island
	var placed := 0; var tries := 0
	while placed < 700 and tries < 60000:
		tries += 1
		var x := rng.randf_range(-hw, hw); var z := rng.randf_range(-hw, hw)
		var h := _ground(x, z)
		if h < -0.5 or h > 5.0: continue
		var bb := terrain.biome_at(x, z)
		if bb == Terrain.Biome.LAKE or bb == Terrain.Biome.SALTFLAT: continue
		if bb != Terrain.Biome.BEACH and bb != Terrain.Biome.DUNES and h > 1.5: continue
		if _near_location(x, z, 30.0): continue
		var s := rng.randf_range(1.5, 5.0)
		if terrain.road_dist_at(x, z) < 5.0 + s or _near_road(x, z, 6.0 + s): continue
		var rm: Material = red if terrain.biome_at(x, z) == Terrain.Biome.BADLANDS else pale
		var scl := Vector3(s, s * rng.randf_range(0.8, 1.5), s * rng.randf_range(0.7, 1.2)); var yaw := rng.randf_range(0, 360)
		_at(x, z, func(): _add_rock(Vector3(x, h - s * 0.35, z), scl, yaw, rm, s > 2.5))
		placed += 1


# ---------------------------------------------------------------- biomes
func _gen_biomes() -> void:
	_gen_forest()
	_gen_limestone()
	_gen_badlands()
	_gen_farmland()
	_gen_ground_cover()


## Scatter helper restricted to one biome; density-weighted when `use_density`.
func _scatter_biome(biome: int, count: int, min_road: float, max_slope: float, scale_range: Vector2, spread: float, use_density: bool, hub_clear: float = 24.0, min_h: float = 1.0) -> Array:
	var xforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	var tries := 0
	var half := Terrain.SIZE * 0.5 - 12.0
	while xforms.size() < count and tries < count * 30:
		tries += 1
		var x := rng.randf_range(-half, half)
		var z := rng.randf_range(-half, half)
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


func _gen_forest() -> void:
	var pines := _scatter_biome(Terrain.Biome.FOREST, 2200, 6.5, 0.55, Vector2(0.7, 1.3), 0.10, true, 22.0)
	_scatter_records(_pine_parts(), pines[0], pines[1], 0.35)
	# pines also climb the mountain gullies and edge the town
	var pines2 := _scatter_biome(Terrain.Biome.LIMESTONE, 1500, 6.0, 0.5, Vector2(0.6, 1.1), 0.10, true, 34.0)
	_scatter_records(_pine_parts(), pines2[0], pines2[1], 0.35)
	var pines3 := _scatter_biome(Terrain.Biome.TOWN, 250, 6.0, 0.5, Vector2(0.6, 1.0), 0.10, true, 20.0)
	_scatter_records(_pine_parts(), pines3[0], pines3[1], 0.35)
	var olives := _scatter_biome(Terrain.Biome.FOREST, 700, 5.0, 0.4, Vector2(0.8, 1.3), 0.10, false, 22.0)
	_scatter_records(_olive_parts(), olives[0], olives[1], 0.5)


func _gen_limestone() -> void:
	var pale := _limestone_material()
	# craggy outcrops on the steep faces of the massif
	var placed := 0; var tries := 0
	while placed < 620 and tries < 40000:
		tries += 1
		var x := rng.randf_range(-607, 104); var z := rng.randf_range(-610, -35)
		var bb := terrain.biome_at(x, z)
		if bb != Terrain.Biome.LIMESTONE and bb != Terrain.Biome.MOOR: continue
		var h := _ground(x, z)
		if h < 6.0: continue
		var steep := 1.0 - terrain.normal_at(x, z).y
		if rng.randf() > steep * 2.5 + 0.08: continue
		if _near_location(x, z, 48.0): continue
		var s := rng.randf_range(3.0, 11.0)
		if terrain.road_dist_at(x, z) < 5.0 + s * 1.1 or _near_road(x, z, 5.0 + s * 1.1): continue
		var scl := Vector3(s, s * rng.randf_range(0.9, 1.6), s * rng.randf_range(0.7, 1.2)); var yaw := rng.randf_range(0, 360)
		_at(x, z, func(): _add_rock(Vector3(x, h - s * 0.4, z), scl, yaw, pale, s > 4.0))
		placed += 1
	# small pale boulders and scrub
	var bush := _scatter_biome(Terrain.Biome.LIMESTONE, 7000, 3.5, 0.6, Vector2(0.7, 1.6), 0.12, false, 30.0)
	_scatter_records(_bush_parts(), bush[0], bush[1], 0.0)
	# a scatter of mountain houses along the loop road (the painting's hill villages)
	var houses := 0; tries = 0
	while houses < 26 and tries < 20000:
		tries += 1
		var x := rng.randf_range(-572, 35); var z := rng.randf_range(-355, -69)
		if terrain.biome_at(x, z) != Terrain.Biome.LIMESTONE: continue
		var rd := terrain.road_dist_at(x, z)
		if rd < 10.0 or rd > 15.0: continue
		if terrain.normal_at(x, z).y < 0.9: continue
		if _near_location(x, z, 34.0) or _near_house(x, z, 22.0): continue
		var t := terrain.nearest_road(Vector3(x, 0, z))
		var yaw := rad_to_deg(atan2(-(t.point.x - x), -(t.point.z - z)))
		var hw := rng.randf_range(6.0, 8.0); var hd := rng.randf_range(5.0, 6.5); var fl := 1 + rng.randi_range(0, 1); var wc := STONE.lerp(Color(0.95, 0.90, 0.80), rng.randf())
		_at(x, z, func(): _house(sink, Vector3(x, _ground(x, z), z), yaw, hw, hd, fl, wc))
		_houses.append(Vector2(x, z))
		houses += 1


var _houses: Array[Vector2] = []

func _near_house(x: float, z: float, r: float) -> bool:
	for p in _houses:
		if p.distance_to(Vector2(x, z)) < r: return true
	return false


func _gen_badlands() -> void:
	# hoodoo spires: a forest of tapered stacks, tallest deep in the badlands
	var kits: Array = []
	for k in range(12): kits.append(_hoodoo_parts(300 + k))
	var groups: Array = []
	for k in range(12): groups.append([[] as Array[Transform3D], [] as Array[Color]])
	var placed := 0; var tries := 0
	var lake_c := _px(1060, 745)
	while placed < 1000 and tries < 120000:
		tries += 1
		var x := rng.randf_range(-125, 445); var z := rng.randf_range(0, 600)
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
		_scatter_records(kits[k], groups[k][0], groups[k][1], 0.9)
	# broken rock rubble between the spires
	var mat := _hoodoo_material()
	for k in range(420):
		var x := rng.randf_range(-125, 445); var z := rng.randf_range(0, 600)
		if terrain.biome_at(x, z) != Terrain.Biome.BADLANDS: continue
		var h := _ground(x, z)
		var s := rng.randf_range(1.5, 5.0)
		if h < 3.0 or terrain.road_dist_at(x, z) < 5.0 + s or _near_road(x, z, 6.0 + s) or _near_location(x, z, 16.0): continue
		var scl := Vector3(s, s * rng.randf_range(0.6, 1.2), s * rng.randf_range(0.7, 1.3)); var yaw := rng.randf_range(0, 360)
		_at(x, z, func(): _add_rock(Vector3(x, h - s * 0.35, z), scl, yaw, mat, s > 2.5))
	# sparse dark shrubs
	var bush := _scatter_biome(Terrain.Biome.BADLANDS, 900, 4.0, 0.6, Vector2(0.4, 0.9), 0.1, false, 14.0, 3.0)
	_scatter_records(_bush_parts(), bush[0], bush[1], 0.0)


## Vineyard rows in the field strips, cypress avenues and a few farmhouses.
func _gen_farmland() -> void:
	var vine_parts: Array[PropPart] = []
	# a vine: a leafy card along the row (rows run along z) and a narrower one across it
	var vmat := _leaf_material("broadleaf_clump", Color(0.8, 0.9, 0.7))
	vine_parts.append(PropPart.new(_card_mesh(2.3, 1.35, true), vmat, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0, 0.05, 0))))
	vine_parts.append(PropPart.new(_card_mesh(0.9, 1.25, true), vmat, Transform3D(Basis(), Vector3(0, 0.05, 0))))
	var post := CylinderMesh.new(); post.top_radius = 0.05; post.bottom_radius = 0.05; post.height = 1.8; post.radial_segments = 5
	vine_parts.append(PropPart.new(post, Mats.solid(WOOD, 0.9), Transform3D(Basis(), Vector3(0, 0.9, -1.1))))
	var vine_x: Array[Transform3D] = []; var vine_c: Array[Color] = []
	# field patches read off the painting (pixel rectangles, rows run along the strip direction)
	var fields := [[300, 560, 460, 640], [480, 520, 600, 600], [250, 640, 420, 720], [430, 640, 560, 700], [300, 480, 380, 540], [560, 440, 660, 520], [400, 400, 520, 460], [200, 560, 300, 640], [470, 600, 600, 680], [520, 380, 640, 440], [360, 380, 460, 440], [230, 480, 300, 560], [600, 520, 700, 600]]
	var rects: Array = []
	for f in fields: rects.append([_px(f[0], f[1]), _px(f[2], f[3])])
	# the bodega's vineyards on the southern shore (world metres)
	for f in [[-60, 380, 0, 420], [40, 375, 110, 415], [-70, 445, -10, 495], [45, 445, 120, 500], [-20, 470, 30, 520]]:
		rects.append([Vector2(f[0], f[1]), Vector2(f[2], f[3])])
	for r in rects:
		var a: Vector2 = r[0]; var b: Vector2 = r[1]
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
	_scatter_records(vine_parts, vine_x, vine_c, 0.0)
	# cypress lines along the farm lanes and olive groves on the slopes
	var cyp := _scatter_biome(Terrain.Biome.FARM, 1100, 4.0, 0.4, Vector2(0.9, 1.5), 0.08, false, 22.0)
	var keep_x: Array[Transform3D] = []; var keep_c: Array[Color] = []
	for i in range(cyp[0].size()):
		var o: Vector3 = cyp[0][i].origin
		if terrain.road_dist_at(o.x, o.z) < 9.0 or rng.randf() < 0.45:
			keep_x.append(cyp[0][i]); keep_c.append(cyp[1][i])
	_scatter_records(_cypress_parts(), keep_x, keep_c, 0.4)
	var oli := _scatter_biome(Terrain.Biome.FARM, 700, 5.0, 0.4, Vector2(0.8, 1.4), 0.10, false, 22.0)
	_scatter_records(_olive_parts(), oli[0], oli[1], 0.5)
	# farmhouses dotted round the fields
	for p in [[300, 742], [500, 585], [560, 445], [740, 395], [640, 470], [420, 640]]:
		var w := _px(p[0], p[1])
		var t := terrain.nearest_road(Vector3(w.x, 0, w.y))
		var side := Vector2(-t.tangent.z, t.tangent.x).normalized()
		var q := Vector2(t.point.x, t.point.z) + side * 13.0
		if not terrain.is_land(q.x, q.y) or _near_location(q.x, q.y, 30.0): continue
		var yaw := rad_to_deg(atan2(-(t.point.x - q.x), -(t.point.z - q.y)))
		var wc := STONE.lerp(Color(0.95, 0.90, 0.80), rng.randf())
		_at(q.x, q.y, func(): _house(sink, Vector3(q.x, _ground(q.x, q.y), q.y), yaw, 8.0, 6.5, 1, wc))
		_houses.append(q)
		var cp := Vector3(q.x + side.x * 6.0, _ground(q.x + side.x * 6.0, q.y + side.y * 6.0), q.y + side.y * 6.0)
		_at(cp.x, cp.z, func(): _place_prop(_cypress_parts(), cp, 1.2, 0.0))
	# the water tower on the ridge in the middle of the island
	var wt := _px(540, 372)
	_at(wt.x, wt.y, func(): _water_tower(sink, Vector3(wt.x, _ground(wt.x, wt.y), wt.y)))
	# cows in the meadows
	for k in range(30):
		var x := rng.randf_range(-435, -70); var z := rng.randf_range(-104, 208)
		if terrain.biome_at(x, z) != Terrain.Biome.FARM or terrain.road_dist_at(x, z) < 6.0 or _near_location(x, z, 24.0): continue
		var yaw := rng.randf_range(0, 360)
		_at(x, z, func(): _cow(sink, Vector3(x, _ground(x, z), z), yaw))


func _gen_ground_cover() -> void:
	var world := Rect2(-Terrain.SIZE * 0.5 + 10, -Terrain.SIZE * 0.5 + 10, Terrain.SIZE - 20, Terrain.SIZE - 20)
	# (grass itself is planted by Terrain3D's instancer: Terrain.plant_ground_cover)
	var bush := _scatter(2000, 3.6, 1.8, 60.0, 0.45, Vector2(0.5, 1.3), Color(1, 1, 1), 0.12, world, 14.0)
	_scatter_records(_bush_parts(), bush[0], bush[1], 0.0)
	var meadows := Rect2(-450, -140, 450, 350)
	var fl := _scatter(800, 3.0, 2.5, 30.0, 0.35, Vector2(0.6, 1.6), Color(1, 1, 1), 0.08, meadows, 0.0)
	_scatter_records(_flower_parts(Color(0.75, 0.45, 0.70)), fl[0], fl[1], 0.0, false)
	var fl2 := _scatter(550, 3.0, 2.5, 30.0, 0.35, Vector2(0.6, 1.4), Color(1, 1, 1), 0.08, meadows, 0.0)
	_scatter_records(_flower_parts(Color(0.92, 0.70, 0.30)), fl2[0], fl2[1], 0.0, false)


# ---------------------------------------------------------------- the town (NE peninsula)
func _gen_town() -> void:
	var walls := [Color(0.93, 0.88, 0.76), Color(0.90, 0.80, 0.62), Color(0.88, 0.74, 0.58), Color(0.95, 0.92, 0.84), Color(0.86, 0.70, 0.52)]
	var roofs := [TERRACOTTA, Color(0.66, 0.36, 0.26), Color(0.78, 0.46, 0.30), Color(0.60, 0.34, 0.24)]
	var placed := 0; var tries := 0
	while placed < 230 and tries < 120000:
		tries += 1
		var x := rng.randf_range(69, 572); var z := rng.randf_range(-347, -69)
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
		var wc: Color = walls[rng.randi_range(0, walls.size() - 1)]; var rc: Color = roofs[rng.randi_range(0, roofs.size() - 1)]
		_at(x, z, func(): _house(sink, Vector3(x, h, z), yaw, w, d, floors, wc, rc))
		_houses.append(Vector2(x, z))
		if rng.randf() < 0.3:
			var pp := Vector3(x, h, z) + Vector3(cos(deg_to_rad(yaw)) * (w * 0.5 + 0.8), 0, -sin(deg_to_rad(yaw)) * (w * 0.5 + 0.8))
			if terrain.road_dist_at(pp.x, pp.z) > 5.5: _at(pp.x, pp.z, func(): _pot_plant(sink, pp, 1.0))
		placed += 1
	# church with a bell tower on the town's high square
	var sq := _px(1160, 150)
	var sq_y := _ground(sq.x, sq.y)
	_at(sq.x, sq.y, func():
		_flagstones(sink, sq.x, sq.y, 10.0, Color(0.68, 0.64, 0.56))
		_house(sink, Vector3(sq.x - 8, sq_y, sq.y - 6), 0, 9.0, 14.0, 2, Color(0.95, 0.92, 0.84))
		_tower(sink, Vector3(sq.x - 1, sq_y, sq.y - 14), 4.0, 16.0, Color(0.95, 0.92, 0.84))
		_lamp_post(sink, Vector3(sq.x + 4, sq_y, sq.y + 4))
		_lamp_post(sink, Vector3(sq.x - 6, sq_y, sq.y + 6)))
	db.add_location(&"town_square", Vector3(sq.x, sq_y, sq.y), Vector3(0, 0, -1), "Town Square")
	# lighthouse at the tip of the peninsula
	var lh := _px(1540, 92)
	var lp := Vector3(lh.x, maxf(_ground(lh.x, lh.y), 1.0), lh.y)
	_at(lp.x, lp.z, func(): _lighthouse(sink, lp))
	db.add_location(&"lighthouse", lp, Vector3(-1, 0, 0), "Lighthouse")
	# the harbour front: a working waterfront below the town — a quay wall along the bay shore,
	# piers every ~18 m, boats packed along them and moored out in the bay
	var shore_pts := _shoreline(_px(960, 300), _px(1320, 345), 6.0)
	var quay_prev := Vector2.INF
	for sp in shore_pts:
		if quay_prev != Vector2.INF and quay_prev.distance_to(sp) < 14.0 and not _near_road(sp.x, sp.y, 7.0) and not _near_road(quay_prev.x, quay_prev.y, 7.0):
			var qa: Vector2 = quay_prev; var qb: Vector2 = sp
			_at(qa.x, qa.y, func(): _stone_wall(sink, qa, qb, 1.2))
		quay_prev = sp
	var pier_i := 0
	var hull_cols := [Color(0.20, 0.22, 0.28), Color(0.55, 0.20, 0.16), Color(0.16, 0.30, 0.45), Color(0.28, 0.40, 0.30), Color(0.75, 0.62, 0.30)]
	for i in range(0, shore_pts.size(), 3):
		var sp: Vector2 = shore_pts[i]
		var nrm := _sea_normal(sp)
		if nrm == Vector2.ZERO or _near_road(sp.x, sp.y, 8.0): continue
		var yaw := rad_to_deg(atan2(nrm.x, nrm.y)) + 180.0
		var len := 16.0 + (pier_i % 3) * 5.0
		_at(sp.x, sp.y, func(): _pier(sink, Vector3(sp.x, 1.0, sp.y), yaw, len))
		# boats moored along both sides of the pier
		var along := Vector2(-sin(deg_to_rad(yaw)), -cos(deg_to_rad(yaw)))
		var perp := Vector2(along.y, -along.x)
		for side in [-1.0, 1.0]:
			var d := 6.0
			while d < len - 2.0:
				var bp: Vector2 = sp + along * d + perp * (side * 3.0)
				if not terrain.is_land(bp.x, bp.y):
					var byaw := yaw + rng.randf_range(-8, 8); var hc: Color = hull_cols[rng.randi_range(0, hull_cols.size() - 1)]; var sail := rng.randf() < 0.3
					_at(sp.x, sp.y, func(): _boat(sink, Vector3(bp.x, 0.2, bp.y), byaw, hc, sail))
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
					var cp := q + Vector2(rng.randf_range(-1.2, 1.2), rng.randf_range(-1.2, 1.2)); var cy := rng.randf_range(0, 90)
					_at(cp.x, cp.y, func(): _static_box(sink, Vector3(1.1, 1.1, 1.1), crate, Vector3(cp.x, _ground(cp.x, cp.y) + 0.55, cp.y), Vector3(0, cy, 0)))
			1:
				for k in range(rng.randi_range(2, 4)):
					var bp := q + Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5))
					_at(bp.x, bp.y, func():
						sink.add_child(Mats.cylinder(0.45, 0.9, barrel, Vector3(bp.x, _ground(bp.x, bp.y) + 0.45, bp.y), Vector3.ZERO, 10))
						_add_cylinder_body(sink, 0.45, 0.9, Vector3(bp.x, _ground(bp.x, bp.y), bp.y)))
			2:
				_at(q.x, q.y, func(): _lamp_post(sink, Vector3(q.x, gy, q.y)))
			3:
				# a heap of nets
				_at(q.x, q.y, func(): sink.add_child(Mats.sphere(0.9, Mats.solid(Color(0.45, 0.42, 0.30), 1.0), Vector3(q.x, gy + 0.3, q.y), Vector3(1.4, 0.5, 1.1), 8)))
	# more boats riding at anchor out in the bay
	var moored := 0; var btries := 0
	while moored < 14 and btries < 2000:
		btries += 1
		var w := _px(rng.randf_range(960, 1300), rng.randf_range(330, 420))
		if terrain.is_land(w.x, w.y) or _ground(w.x, w.y) > -1.2: continue
		var byaw := rng.randf_range(0, 360); var hc: Color = hull_cols[rng.randi_range(0, hull_cols.size() - 1)]; var sail := rng.randf() < 0.5
		_at(w.x, w.y, func(): _boat(sink, Vector3(w.x, 0.2, w.y), byaw, hc, sail))
		moored += 1
	# signposts at the town approach
	var ap := _px(1010, 186)
	_at(ap.x, ap.y, func(): _signpost(sink, Vector3(ap.x + 4, _ground(ap.x + 4, ap.y + 5), ap.y + 5), 20, [["HARBOUR", 1.0], ["LIGHTHOUSE", 1.0], ["VILLA ROSA", -1.0], ["THE DUNES", -1.0]]))


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
func _gen_hamlet() -> void:
	for p in [[912, 318], [896, 348], [935, 300], [925, 372], [905, 395]]:
		var w := _px(p[0], p[1])
		if not terrain.is_land(w.x, w.y) or _ground(w.x, w.y) < 1.5: continue
		if terrain.road_dist_at(w.x, w.y) < 9.5 or _near_house(w.x, w.y, 8.0): continue
		var t := terrain.nearest_road(Vector3(w.x, 0, w.y))
		var yaw := rad_to_deg(atan2(-(t.point.x - w.x), -(t.point.z - w.y)))
		var hw := rng.randf_range(6, 8); var hd := rng.randf_range(5, 6.5); var fl := 1 + rng.randi_range(0, 1)
		_at(w.x, w.y, func(): _house(sink, Vector3(w.x, _ground(w.x, w.y), w.y), yaw, hw, hd, fl, Color(0.92, 0.86, 0.72)))
		_houses.append(w)
	var wp := _px(965, 345)
	var shore := _shore_point(wp, 10.0)
	_at(shore.x, shore.y, func(): _pier(sink, Vector3(shore.x, 1.0, shore.y), 250.0, 16.0))
	var bp := _px(985, 372)
	if not terrain.is_land(bp.x, bp.y):
		_at(bp.x, bp.y, func(): _boat(sink, Vector3(bp.x, 0.25, bp.y), 40.0, Color(0.85, 0.30, 0.25)))
	db.add_location(&"hamlet", Vector3(wp.x, _ground(wp.x, wp.y), wp.y), Vector3(1, 0, 0), "Hamlet by the bay")


# ---------------------------------------------------------------- aqueducts
## Every elevated road stretch the terrain found (the strait crossing and the badlands viaduct)
## becomes an arched stone aqueduct with a rideable deck.
func _gen_aqueducts() -> void:
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
		var mid: Vector3 = pts[pts.size() / 2]
		var deck: float = b.deck
		_at(mid.x, mid.z, func(): _arcade(sink, pts, deck, stone))


# ---------------------------------------------------------------- hubs
func _build_villa_hub(hb_rec: Hub) -> void:
	var hub := Node3D.new(); hub.name = "VillaHub"; sink.add_child(hub)
	var cx := hb_rec.centre.x; var cz := hb_rec.centre.y
	var g := _ground(cx, cz)
	_flagstones(hub, cx + 1 * K, cz + 4 * K, 11.0)
	var villa := _house(hub, Vector3(cx - 16 * K, g, cz - 6 * K), 32, 10.0, 8.0, 2)
	villa.add_child(Mats.box(Vector3(5.5, 0.25, 8.0), Mats.solid(STONE_DARK, 0.9), Vector3(7.7, 3.2, 0)))
	villa.add_child(Mats.box(Vector3(5.5, 1.0, 0.1), Mats.solid(Color(0.15, 0.15, 0.15), 0.6, 0.3), Vector3(7.7, 3.8, -3.95)))
	villa.add_child(Mats.cylinder(0.04, 2.4, Mats.solid(Color(0.6, 0.6, 0.6), 0.5, 0.4), Vector3(7.7, 4.5, -1)))
	villa.add_child(Mats.cone(1.6, 0.7, Mats.solid(Color(0.55, 0.62, 0.85), 0.9), Vector3(7.7, 5.7, -1), 10))
	var office := _house(hub, Vector3(cx + 15 * K, g, cz - 9 * K), -90, 9.0, 7.0, 1, Color(0.80, 0.72, 0.58))
	_awning(office, Vector3(0, 2.65, -3.5), 0, 6.0, Color(0.25, 0.48, 0.30))
	_pot_plant(office, Vector3(-3.2, 0, -4.4), 1.1)
	_pot_plant(office, Vector3(3.4, 0, -4.4), 0.9)
	for i in range(3):
		office.add_child(Mats.cylinder(0.45, 0.9, Mats.solid(WOOD, 0.85), Vector3(4.2 + i * 0.6, 0.45, -1.5 + i * 0.9), Vector3.ZERO, 10))
		_add_cylinder_body(office, 0.45, 0.9, Vector3(4.2 + i * 0.6, 0.0, -1.5 + i * 0.9))
	var gate := Node3D.new(); gate.position = Vector3(cx + 2 * K, g, cz + 17 * K); gate.rotation_degrees = Vector3(0, 20, 0); hub.add_child(gate)
	var stone := Mats.solid(STONE, 0.9)
	_static_box(gate, Vector3(1.2, 4.0, 1.2), stone, Vector3(-2.2, 2.0, 0))
	_static_box(gate, Vector3(1.2, 4.0, 1.2), stone, Vector3(2.2, 2.0, 0))
	gate.add_child(Mats.box(Vector3(5.6, 0.8, 1.4), stone, Vector3(0, 4.4, 0)))
	gate.add_child(Mats.prism(Vector3(6.4, 1.3, 2.4), Mats.solid(TERRACOTTA, 0.85), Vector3(0, 5.45, 0)))
	_stone_wall(hub, Vector2(cx - 22 * K, cz + 14 * K), Vector2(cx - 4 * K, cz + 26 * K))
	_stone_wall(hub, Vector2(cx + 22 * K, cz + 18 * K), Vector2(cx + 36 * K, cz + 30 * K))
	_lamp_post(hub, Vector3(cx + 11 * K, _ground(cx + 11 * K, cz + 8 * K), cz + 8 * K))
	_lamp_post(hub, Vector3(cx - 7 * K, _ground(cx - 7 * K, cz - 12 * K), cz - 12 * K))
	_signpost(hub, Vector3(cx + 5.5 * K, _ground(cx + 5.5 * K, cz - 6 * K), cz - 6 * K), 35, [["HILLTOP FARM", -1.0], ["HARBOUR", 1.0], ["THE DUNES", 1.0], ["CALA BLANCA", -1.0]])
	_pot_plant(hub, Vector3(cx - 8 * K, g, cz + 6 * K), 1.2)
	_pot_plant(hub, Vector3(cx - 6 * K, g, cz + 14 * K), 1.0)
	var plinth := Node3D.new(); plinth.position = Vector3(cx - 8 * K, g, cz + 9 * K); hub.add_child(plinth)
	_static_box(plinth, Vector3(2.2, 1.2, 2.2), stone, Vector3(0, 0.6, 0))
	plinth.add_child(Mats.box(Vector3(1.4, 1.6, 1.4), stone, Vector3(0, 2.0, 0)))
	plinth.add_child(Mats.capsule(0.32, 1.4, Mats.solid(Color(0.92, 0.90, 0.86), 0.6), Vector3(0, 3.7, 0)))
	plinth.add_child(Mats.sphere(0.28, Mats.solid(Color(0.92, 0.90, 0.86), 0.6), Vector3(0, 4.75, 0)))
	# the painting's tall cypress sentinels round the villa
	var cyp := _cypress_parts(); var oli := _olive_parts()
	for p in [Vector2(-24, 12), Vector2(-24, 6), Vector2(-9, -14), Vector2(24, 12), Vector2(-4, 22), Vector2(-28, -10), Vector2(-20, -18), Vector2(4, -20), Vector2(20, -18)]:
		_place_prop(cyp, Vector3(cx + p.x * K, _ground(cx + p.x * K, cz + p.y * K), cz + p.y * K), rng.randf_range(1.1, 1.6), rng.randf_range(0, 360))
	for p in [Vector2(-30, 12), Vector2(26, -6), Vector2(28, 26), Vector2(-16, 30)]:
		_place_prop(oli, Vector3(cx + p.x * K, _ground(cx + p.x * K, cz + p.y * K), cz + p.y * K), rng.randf_range(1.0, 1.4), rng.randf_range(0, 360))


func _define_villa(hb_rec: Hub) -> void:
	var cx := hb_rec.centre.x; var cz := hb_rec.centre.y
	_register(&"villa_rosa_office", "Villa Rosa Office", cx + 6.5 * K, cz - 4 * K, Vector3(-1, 0, 0))
	_register(&"villa_square", "Villa Square", cx, cz, Vector3(0, 0, -1))
	hb_rec.ring_pos = db.location_pos(&"villa_rosa_office"); hb_rec.ring_facing = Vector3(-1, 0, 0)
	hb_rec.add_wall(Vector2(cx - 22 * K, cz + 14 * K), Vector2(cx - 4 * K, cz + 26 * K), 1.0)
	hb_rec.add_wall(Vector2(cx + 22 * K, cz + 18 * K), Vector2(cx + 36 * K, cz + 30 * K), 1.0)


func _build_farm(hb_rec: Hub) -> void:
	var farm := Node3D.new(); farm.name = "Farm"; sink.add_child(farm)
	var cx := hb_rec.centre.x; var cz := hb_rec.centre.y
	var g := _ground(cx, cz)
	var barn := _house(farm, Vector3(cx + 24 * K, g, cz - 12 * K), 10, 12.0, 9.0, 1, Color(0.66, 0.52, 0.36), Color(0.50, 0.34, 0.22))
	barn.scale = Vector3(1, 1.5, 1)
	_house(farm, Vector3(cx - 10 * K, g, cz + 6 * K), 70, 8.0, 6.5, 1)
	var truck := Node3D.new(); truck.position = Vector3(cx - 20 * K, g, cz + 22 * K); truck.rotation_degrees = Vector3(0, -65, 0); farm.add_child(truck)
	var green := Mats.solid(Color(0.62, 0.66, 0.36), 0.6)
	_static_box(truck, Vector3(1.6, 1.5, 1.7), green, Vector3(0, 1.15, -1.4))
	_static_box(truck, Vector3(1.7, 0.7, 2.6), green, Vector3(0, 0.75, 0.9))
	truck.add_child(Mats.box(Vector3(1.4, 0.6, 0.1), Mats.solid(Color(0.2, 0.25, 0.3), 0.2), Vector3(0, 1.5, -2.26)))
	for p in [Vector3(-0.85, 0.4, -1.3), Vector3(0.85, 0.4, -1.3), Vector3(-0.85, 0.4, 1.4), Vector3(0.85, 0.4, 1.4)]:
		truck.add_child(Mats.cylinder(0.4, 0.3, Mats.solid(Color(0.1, 0.1, 0.1), 0.9), p, Vector3(0, 0, 90), 12))
	var ws := Node3D.new(); ws.position = Vector3(cx - 22 * K, _ground(cx - 22 * K, cz - 14 * K), cz - 14 * K); farm.add_child(ws)
	ws.add_child(Mats.cylinder(0.05, 6.0, Mats.solid(Color(0.6, 0.6, 0.6), 0.5, 0.4), Vector3(0, 3, 0)))
	ws.add_child(Mats.cylinder(0.32, 2.2, Mats.solid(Color(0.95, 0.40, 0.15), 0.8), Vector3(1.1, 5.9, 0), Vector3(0, 0, 90), 10, 0.18))
	_add_cylinder_body(ws, 0.1, 6.0, Vector3.ZERO)
	_stone_wall(farm, Vector2(cx + 6 * K, cz - 24 * K), Vector2(cx + 40 * K, cz - 24 * K), 0.8)   # the long wall east of the road (tin cans go here)
	_stone_wall(farm, Vector2(cx + 40 * K, cz - 24 * K), Vector2(cx + 36 * K, cz + 14 * K), 0.8)
	for i in range(4):
		farm.add_child(Mats.cylinder(0.7, 1.2, Mats.solid(Color(0.86, 0.72, 0.38), 1.0), Vector3(cx - 16 * K + i * 1.6, g + 0.7, cz + 18 * K), Vector3(90, 0, 0), 10))
		_add_cylinder_body(farm, 0.7, 1.4, Vector3(cx - 16 * K + i * 1.6, g, cz + 18 * K))
	_lamp_post(farm, Vector3(cx - 8 * K, g, cz + 8 * K))
	_signpost(farm, Vector3(cx - 4 * K, _ground(cx - 4 * K, cz + 14 * K), cz + 14 * K), 60, [["VILLA ROSA", 1.0], ["HILLTOP FARM", -1.0], ["MONASTERY", -1.0]])
	var cypf := _cypress_parts(); var olif := _olive_parts()
	for p in [Vector2(-18, -6), Vector2(-20, 0), Vector2(22, -18), Vector2(-26, 16), Vector2(8, 22)]:
		_place_prop(cypf, Vector3(cx + p.x * K, _ground(cx + p.x * K, cz + p.y * K), cz + p.y * K), rng.randf_range(0.9, 1.3), rng.randf_range(0, 360))
	for p in [Vector2(-32, 8), Vector2(28, 4), Vector2(16, -24)]:
		_place_prop(olif, Vector3(cx + p.x * K, _ground(cx + p.x * K, cz + p.y * K), cz + p.y * K), rng.randf_range(1.0, 1.5), rng.randf_range(0, 360))
	for k in range(4):
		var x := cx + rng.randf_range(-40, 40) * K; var z := cz + rng.randf_range(-40, 40) * K
		if terrain.road_dist_at(x, z) < 6.0 or _near_location(x, z, 20.0) or terrain.normal_at(x, z).y < 0.9: continue
		_cow(farm, Vector3(x, _ground(x, z), z), rng.randf_range(0, 360))


func _define_farm(hb_rec: Hub) -> void:
	var cx := hb_rec.centre.x; var cz := hb_rec.centre.y
	_register(&"hilltop_farm", "Hilltop Farm", cx - 3 * K, cz + 1 * K, Vector3(0, 0, 1))
	hb_rec.ring_pos = db.location_pos(&"hilltop_farm"); hb_rec.ring_facing = Vector3(0, 0, 1)
	hb_rec.add_wall(Vector2(cx + 6 * K, cz - 24 * K), Vector2(cx + 40 * K, cz - 24 * K), 0.8)   # the tin-can wall
	hb_rec.add_wall(Vector2(cx + 40 * K, cz - 24 * K), Vector2(cx + 36 * K, cz + 14 * K), 0.8)


func _build_harbour(hb_rec: Hub) -> void:
	var hb := Node3D.new(); hb.name = "Harbour"; sink.add_child(hb)
	var cx := hb_rec.centre.x; var cz := hb_rec.centre.y
	var g := _ground(cx, cz)
	_flagstones(hb, cx + 2 * K, cz + 2 * K, 12.0, Color(0.60, 0.57, 0.52))
	_house(hb, Vector3(cx - 14 * K, g, cz - 10 * K), 25, 7.0, 6.0, 2, Color(0.88, 0.80, 0.66))
	_house(hb, Vector3(cx - 8 * K, g, cz + 12 * K), -60, 6.0, 5.0, 1, Color(0.82, 0.74, 0.60))
	var cafe := _house(hb, Vector3(cx + 10 * K, g, cz - 6 * K), -110, 8.0, 6.0, 1, Color(0.90, 0.84, 0.70))
	_awning(cafe, Vector3(0, 2.65, -3.0), 0, 5.5, Color(0.72, 0.28, 0.25))
	_pot_plant(cafe, Vector3(-3, 0, -4), 1.0)
	for i in range(2):
		cafe.add_child(Mats.cylinder(0.5, 0.05, Mats.solid(Color(0.9, 0.9, 0.9), 0.5), Vector3(-1.5 + i * 3.0, 0.75, -4.2), Vector3.ZERO, 10))
		cafe.add_child(Mats.cylinder(0.04, 0.75, Mats.solid(Color(0.2, 0.2, 0.2), 0.5, 0.3), Vector3(-1.5 + i * 3.0, 0.37, -4.2)))
	for p in [Vector2(-14, -10), Vector2(-8, 12), Vector2(10, -6)]:
		_houses.append(Vector2(cx + p.x * K, cz + p.y * K))
	_lamp_post(hb, Vector3(cx + 2 * K, g, cz + 4 * K))
	_lamp_post(hb, Vector3(cx + 18 * K, g, cz + 12 * K))
	_signpost(hb, Vector3(cx - 6 * K, _ground(cx - 6 * K, cz - 20 * K), cz - 20 * K), -30, [["VILLA ROSA", -1.0], ["HARBOUR", 1.0]])
	_pot_plant(hb, Vector3(cx - 2 * K, g, cz + 10 * K), 1.1)
	var cyph := _cypress_parts()
	for p in [Vector2(-22, -4), Vector2(-20, 14), Vector2(18, -16)]:
		_place_prop(cyph, Vector3(cx + p.x * K, _ground(cx + p.x * K, cz + p.y * K), cz + p.y * K), rng.randf_range(0.9, 1.3), rng.randf_range(0, 360))


func _define_harbour(hb_rec: Hub) -> void:
	var cx := hb_rec.centre.x; var cz := hb_rec.centre.y
	_register(&"harbour_cafe", "Harbour Cafe", cx + 2 * K, cz + 4 * K, Vector3(0, 0, -1))
	hb_rec.ring_pos = db.location_pos(&"harbour_cafe"); hb_rec.ring_facing = Vector3(0, 0, -1)


func _build_lookout(hb_rec: Hub) -> void:
	var lk := Node3D.new(); lk.name = "Lookout"; sink.add_child(lk)
	var cx := hb_rec.centre.x; var cz := hb_rec.centre.y
	var g := _ground(cx, cz)
	# an old stone hut with a bench looking over the lake in the badlands
	_house(lk, Vector3(cx - 8 * K, g, cz - 4 * K), 110, 5.0, 4.5, 1, STONE_DARK, Color(0.5, 0.42, 0.34))
	_signpost(lk, Vector3(cx + 2 * K, _ground(cx + 2 * K, cz + 6 * K), cz + 6 * K), -70, [["THE DUNES", 1.0], ["VILLA ROSA", -1.0], ["LAKESIDE CAMP", 1.0]])
	lk.add_child(Mats.box(Vector3(2.0, 0.1, 0.5), Mats.solid(WOOD, 0.9), Vector3(cx + 4 * K, g + 0.5, cz - 3 * K)))
	for sx in [-0.8, 0.8]:
		lk.add_child(Mats.box(Vector3(0.1, 0.5, 0.5), Mats.solid(WOOD, 0.9), Vector3(cx + 4 * K + sx, g + 0.25, cz - 3 * K)))


func _define_lookout(hb_rec: Hub) -> void:
	var cx := hb_rec.centre.x; var cz := hb_rec.centre.y
	var g := _ground(cx, cz)
	_register(&"dunes_lookout", "Dunes Lookout", cx + 1 * K, cz - 1 * K, Vector3(1, 0, 0))
	hb_rec.ring_pos = db.location_pos(&"dunes_lookout"); hb_rec.ring_facing = Vector3(1, 0, 0)
	hb_rec.bench = Vector3(cx + 4 * K, g + 0.55, cz - 3 * K); hb_rec.bench_width = 2.0


# ---------------------------------------------------------------- the Highlands (north)
## Moorland: heather cushions, wind-bent pines in the hollows, grey outcrops (shared with the
## limestone pass in _gen_limestone), drystone walls and sheep near the pass.
func _gen_highlands() -> void:
	var heather := _scatter_biome(Terrain.Biome.MOOR, 3200, 3.5, 0.6, Vector2(0.8, 1.6), 0.14, false, 26.0, 2.0)
	_scatter_records(_heather_parts(), heather[0], heather[1], 0.0)
	var pines := _scatter_biome(Terrain.Biome.MOOR, 500, 6.5, 0.5, Vector2(0.5, 0.9), 0.12, true, 30.0)
	_scatter_records(_pine_parts(), pines[0], pines[1], 0.35)
	# drystone walls striding across the moor near the pass, and sheep behind them
	for w in [[Vector2(-380, -372), Vector2(-350, -352)], [Vector2(-300, -370), Vector2(-262, -382)], [Vector2(-262, -382), Vector2(-250, -412)], [Vector2(-360, -420), Vector2(-338, -452)]]:
		var a: Vector2 = w[0]; var b: Vector2 = w[1]
		if _near_road(a.x, a.y, 7.0) or _near_road(b.x, b.y, 7.0): continue
		_at(a.x, a.y, func(): _stone_wall(sink, a, b, 0.9))
	for k in range(30):
		var x := rng.randf_range(-400, -230); var z := rng.randf_range(-460, -340)
		if terrain.biome_at(x, z) != Terrain.Biome.MOOR or terrain.road_dist_at(x, z) < 6.0 or _near_location(x, z, 22.0) or terrain.normal_at(x, z).y < 0.85: continue
		var yaw := rng.randf_range(0, 360)
		_at(x, z, func(): _sheep(sink, Vector3(x, _ground(x, z), z), yaw))
	# a stone cairn on every rise
	var pale := _limestone_material()
	for k in range(40):
		var x := rng.randf_range(-560, -40); var z := rng.randf_range(-600, -330)
		if terrain.biome_at(x, z) != Terrain.Biome.MOOR or terrain.road_dist_at(x, z) < 8.0 or _near_location(x, z, 30.0): continue
		var h := _ground(x, z)
		if h < 30.0 or terrain.normal_at(x, z).y < 0.95: continue
		_at(x, z, func():
			for i in range(4):
				sink.add_child(Mats.sphere(0.5 - i * 0.08, pale, Vector3(x + rng.randf_range(-0.2, 0.2), h + 0.3 + i * 0.55, z + rng.randf_range(-0.2, 0.2)), Vector3(1.3, 0.8, 1.1), 6)))


# ---------------------------------------------------------------- the Southern Shore
## Dunes with marram tufts, the salt pans' dykes and heaps, reeds round the lagoon, a badlands
## headland (the hoodoos come from _gen_badlands) and olives on the bodega's slopes.
func _gen_south_shore() -> void:
	var scrub := _scatter_biome(Terrain.Biome.DUNES, 700, 4.0, 0.6, Vector2(0.5, 1.1), 0.12, false, 18.0, 2.5)
	_scatter_records(_bush_parts(), scrub[0], scrub[1], 0.0)
	# reeds on the lagoon and lake shores
	var reeds_x: Array[Transform3D] = []; var reeds_c: Array[Color] = []
	var tries := 0
	while reeds_x.size() < 900 and tries < 40000:
		tries += 1
		var x := rng.randf_range(-100, 280); var z := rng.randf_range(140, 600)
		var h := _ground(x, z)
		if h < -0.6 or h > 1.2: continue
		var lake := false
		for d in [Vector2(6, 0), Vector2(-6, 0), Vector2(0, 6), Vector2(0, -6)]:
			if terrain.biome_at(x + d.x, z + d.y) == Terrain.Biome.LAKE: lake = true
		if not lake or terrain.road_dist_at(x, z) < 4.0 or _near_location(x, z, 12.0): continue
		var s := rng.randf_range(0.8, 1.4)
		reeds_x.append(Transform3D(Basis(Vector3.UP, rng.randf_range(0, TAU)).scaled(Vector3(s, s, s)), Vector3(x, h - 0.05, z)))
		reeds_c.append(Color(1.0, 1.0 + rng.randf_range(-0.1, 0.1), 1.0))
	_scatter_records(_reed_parts(), reeds_x, reeds_c, 0.0, false)
	# the salt pans: a grid of low dykes over the flat, heaps of salt along the northern edge
	var dykes: Array = []
	for i in range(5):
		var x := -215.0 + i * 30.0
		dykes.append([Vector2(x, 448), Vector2(x, 540)])
	for j in range(4):
		var z := 452.0 + j * 28.0
		dykes.append([Vector2(-222, z), Vector2(-85, z)])
	for d in dykes:
		# in 8 m pieces, leaving gaps where the coast road crosses the pans
		var a: Vector2 = d[0]; var b: Vector2 = d[1]
		var n := int(ceil(a.distance_to(b) / 8.0))
		for k in range(n):
			var p0 := a.lerp(b, float(k) / n); var p1 := a.lerp(b, float(k + 1) / n)
			var mid := (p0 + p1) * 0.5
			if _near_road(mid.x, mid.y, 8.0) or terrain.biome_at(mid.x, mid.y) != Terrain.Biome.SALTFLAT: continue
			_at(mid.x, mid.y, func(): _dyke(sink, p0, p1))
	for k in range(9):
		var x := -210.0 + k * 15.0 + rng.randf_range(-3, 3); var z := 452.0 + rng.randf_range(-2, 2)
		if terrain.road_dist_at(x, z) < 6.0: continue
		var s := rng.randf_range(0.8, 1.5)
		_at(x, z, func(): _salt_heap(sink, Vector3(x, _ground(x, z), z), s))
	# olive terraces on the bodega's slopes and pines in the southern forest
	var oli := _scatter_biome(Terrain.Biome.FARM, 400, 5.0, 0.4, Vector2(0.8, 1.4), 0.10, false, 22.0)
	var keep_x: Array[Transform3D] = []; var keep_c: Array[Color] = []
	for i in range(oli[0].size()):
		if oli[0][i].origin.z > 300.0: keep_x.append(oli[0][i]); keep_c.append(oli[1][i])
	_scatter_records(_olive_parts(), keep_x, keep_c, 0.5)
	# beach clutter on the south coast: driftwood and a few upturned boats
	for k in range(14):
		var x := rng.randf_range(-470, 250); var z := rng.randf_range(380, 610)
		if terrain.biome_at(x, z) != Terrain.Biome.BEACH or _near_road(x, z, 8.0) or _near_location(x, z, 20.0): continue
		var yaw := rng.randf_range(0, 360)
		var h := _ground(x, z)
		if k % 3 == 0:
			_at(x, z, func(): _boat(sink, Vector3(x, h + 0.3, z), yaw, Color(0.55, 0.45, 0.35)))
		else:
			_at(x, z, func(): sink.add_child(Mats.cylinder(0.18, rng.randf_range(2.0, 4.0), Mats.solid(Color(0.66, 0.58, 0.46), 0.95), Vector3(x, h + 0.15, z), Vector3(0, yaw, 88), 6)))


# ---------------------------------------------------------------- new hubs
func _build_monastery(hb_rec: Hub) -> void:
	var m := Node3D.new(); m.name = "Monastery"; sink.add_child(m)
	var cx := hb_rec.centre.x; var cz := hb_rec.centre.y
	var g := _ground(cx, cz)
	var wall := Color(0.90, 0.86, 0.76)
	_flagstones(m, cx, cz + 2, 8.0, Color(0.66, 0.62, 0.54))
	# church with its bell tower, the cloister beside it, the monks' dormitory behind
	var church := _house(m, Vector3(cx - 2, g, cz - 14), 0, 9.0, 17.0, 2, wall, Color(0.62, 0.36, 0.26))
	church.add_child(Mats.box(Vector3(0.5, 3.2, 0.5), Mats.solid(STONE_DARK, 0.9), Vector3(0, 9.4, -8.0)))
	church.add_child(Mats.box(Vector3(2.2, 0.4, 0.4), Mats.solid(STONE_DARK, 0.9), Vector3(0, 10.2, -8.0)))
	_tower(m, Vector3(cx + 6, g, cz - 24), 3.6, 15.0, wall)
	_cloister(m, Vector3(cx + 13, g, cz + 1), 14.0, wall)
	_house(m, Vector3(cx - 18, g, cz - 6), 90, 7.0, 15.0, 2, wall)
	_stone_wall(m, Vector2(cx - 22, cz + 18), Vector2(cx - 16, cz + 18), 1.2)   # the gate gap is where the road comes in
	_stone_wall(m, Vector2(cx - 4, cz + 18), Vector2(cx + 24, cz + 18), 1.2)
	_stone_wall(m, Vector2(cx - 22, cz - 26), Vector2(cx - 22, cz + 18), 1.2)
	_lamp_post(m, Vector3(cx + 3, g, cz + 8))
	_signpost(m, Vector3(cx - 16, _ground(cx - 16, cz + 12), cz + 12), 80, [["QUARRY", 1.0], ["REFUGIO", -1.0], ["HILLTOP FARM", -1.0]])
	var cyp := _cypress_parts()
	for p in [Vector2(-8, -30), Vector2(10, -32), Vector2(-26, 0), Vector2(-26, -12), Vector2(26, 10), Vector2(26, -8)]:
		_place_prop(cyp, Vector3(cx + p.x, _ground(cx + p.x, cz + p.y), cz + p.y), rng.randf_range(1.1, 1.6), rng.randf_range(0, 360))
	# beehives on the slope below the wall
	for i in range(5):
		var bp := Vector3(cx - 2 + i * 3.0, 0, cz + 23)
		bp.y = _ground(bp.x, bp.z)
		_static_box(m, Vector3(0.9, 0.9, 0.9), Mats.solid(Color(0.85, 0.72, 0.42), 0.9), bp + Vector3(0, 0.45, 0))
		m.add_child(Mats.box(Vector3(1.1, 0.1, 1.1), Mats.solid(STONE_DARK, 0.9), bp + Vector3(0, 0.95, 0)))


func _define_monastery(hb_rec: Hub) -> void:
	var cx := hb_rec.centre.x; var cz := hb_rec.centre.y
	_register(&"monastery", "San Telmo Monastery", cx, cz + 4, Vector3(0, 0, -1))
	hb_rec.ring_pos = db.location_pos(&"monastery"); hb_rec.ring_facing = Vector3(0, 0, -1)
	hb_rec.add_wall(Vector2(cx - 4, cz + 18), Vector2(cx + 24, cz + 18), 1.2)


func _build_quarry(hb_rec: Hub) -> void:
	var q := Node3D.new(); q.name = "Quarry"; sink.add_child(q)
	var cx := hb_rec.centre.x; var cz := hb_rec.centre.y
	var g := _ground(cx, cz)
	# the cut: a stepped white face on the hill's north side, cranes and blocks on the floor
	var marble := Mats.solid(Color(0.93, 0.91, 0.87), 0.75)
	for i in range(3):
		var y := g + i * 3.0
		_static_box(q, Vector3(40.0 - i * 6.0, 3.0, 5.0), marble, Vector3(cx + 2, y + 1.5, cz - 18 - i * 4.0))
	_static_box(q, Vector3(6.0, 9.0, 12.0), marble, Vector3(cx - 22, g + 4.5, cz - 20))
	_crane(q, Vector3(cx + 8, g, cz - 6), 20)
	_crane(q, Vector3(cx - 10, g, cz - 12), -40)
	for i in range(7):
		var bp := Vector3(cx - 26 + i * 3.2, g, cz + 8 + (i % 2) * 3.0)
		_marble_block(q, bp, Vector3(2.4, rng.randf_range(1.0, 2.0), 1.8), rng.randf_range(-15, 15))
	_house(q, Vector3(cx + 16, g, cz + 10), -90, 7.0, 5.0, 1, Color(0.80, 0.74, 0.62))
	_house(q, Vector3(cx - 14, g, cz + 16), 0, 9.0, 6.0, 1, Color(0.66, 0.52, 0.36), Color(0.50, 0.34, 0.22))
	_lamp_post(q, Vector3(cx + 7, g, cz + 3))
	_signpost(q, Vector3(cx + 10, _ground(cx + 10, cz + 20), cz + 20), 100, [["MONASTERY", -1.0], ["HILLTOP FARM", 1.0]])
	_stone_wall(q, Vector2(cx - 24, cz + 20), Vector2(cx - 4, cz + 22), 0.9)
	# rubble everywhere
	var pale := _limestone_material()
	for k in range(14):
		var x := cx + rng.randf_range(-26, 26); var z := cz + rng.randf_range(-24, 20)
		if terrain.road_dist_at(x, z) < 6.0 or _near_location(x, z, 8.0): continue
		var s := rng.randf_range(0.6, 1.8)
		_add_rock(Vector3(x, _ground(x, z) - s * 0.3, z), Vector3(s, s * 0.8, s), rng.randf_range(0, 360), pale, s > 1.2)


func _define_quarry(hb_rec: Hub) -> void:
	var cx := hb_rec.centre.x; var cz := hb_rec.centre.y
	_register(&"quarry", "Marble Quarry", cx + 2, cz - 1, Vector3(0, 0, 1))
	hb_rec.ring_pos = db.location_pos(&"quarry"); hb_rec.ring_facing = Vector3(0, 0, 1)
	hb_rec.add_wall(Vector2(cx - 24, cz + 20), Vector2(cx - 4, cz + 22), 0.9)


func _build_cala(hb_rec: Hub) -> void:
	var c := Node3D.new(); c.name = "CalaBlanca"; sink.add_child(c)
	var cx := hb_rec.centre.x; var cz := hb_rec.centre.y
	var g := _ground(cx, cz)
	var whites := [Color(0.97, 0.96, 0.92), Color(0.95, 0.92, 0.84), Color(0.92, 0.90, 0.86)]
	var blues := [Color(0.20, 0.36, 0.62), Color(0.28, 0.52, 0.60), Color(0.60, 0.34, 0.26)]
	_flagstones(c, cx + 2, cz + 2, 9.0, Color(0.70, 0.68, 0.62))
	# the coast road runs NW -> SE through the square: whitewashed fishermen's houses line its
	# north-east side facing the cove, the taverna sits on the cove side
	var along := Vector2(0.8, 0.6); var nrm := Vector2(0.6, -0.8)
	for i in range(6):
		var q: Vector2 = Vector2(cx, cz) + along * (-18.0 + i * 7.0) + nrm * 13.0
		var hp := Vector3(q.x, _ground(q.x, q.y), q.y)
		_house(c, hp, -37 + rng.randf_range(-6, 6), rng.randf_range(5.5, 7.0), 5.0, 1 + (1 if i % 3 == 0 else 0), whites[i % 3], blues[i % 3])
		_houses.append(q)
	var tq: Vector2 = Vector2(cx, cz) + along * (-2.0) + nrm * (-12.0)
	var tav := _house(c, Vector3(tq.x, _ground(tq.x, tq.y), tq.y), 143, 9.0, 6.0, 1, whites[0], blues[0])
	_awning(tav, Vector3(0, 2.65, -3.0), 0, 6.0, Color(0.22, 0.42, 0.62))
	_pot_plant(tav, Vector3(-3.5, 0, -4.2), 1.0)
	for i in range(2):
		tav.add_child(Mats.cylinder(0.5, 0.05, Mats.solid(Color(0.9, 0.9, 0.9), 0.5), Vector3(-1.5 + i * 3.0, 0.75, -4.2), Vector3.ZERO, 10))
		tav.add_child(Mats.cylinder(0.04, 0.75, Mats.solid(Color(0.2, 0.2, 0.2), 0.5, 0.3), Vector3(-1.5 + i * 3.0, 0.37, -4.2)))
	# the pier into the cove and boats hauled up on the sand
	var shore := _shore_point(Vector2(cx - 22, cz), 6.0)
	_pier(c, Vector3(shore.x, 1.0, shore.y), 90.0, 22.0)
	var hulls := [Color(0.16, 0.30, 0.45), Color(0.75, 0.62, 0.30), Color(0.55, 0.20, 0.16), Color(0.28, 0.40, 0.30)]
	for i in range(4):
		var bp := Vector2(shore.x + rng.randf_range(-3, 4), shore.y + 10 + i * 5.0)
		if terrain.is_land(bp.x, bp.y):
			_boat(c, Vector3(bp.x, _ground(bp.x, bp.y) + 0.3, bp.y), 90 + rng.randf_range(-15, 15), hulls[i])
	for i in range(3):
		var wp := Vector2(shore.x - 12 - i * 7.0, shore.y - 6 + i * 5.0)
		if not terrain.is_land(wp.x, wp.y):
			_boat(c, Vector3(wp.x, 0.2, wp.y), rng.randf_range(0, 360), hulls[(i + 1) % 4], i == 1)
	# nets, crates and a lamp on the quay
	for i in range(3):
		var np := Vector3(shore.x + 3 + i * 2.2, 0, shore.y - 4)
		np.y = _ground(np.x, np.z) + 0.3
		c.add_child(Mats.sphere(0.8, Mats.solid(Color(0.45, 0.42, 0.30), 1.0), np, Vector3(1.3, 0.45, 1.0), 8))
	_lamp_post(c, Vector3(cx - 2, g, cz + 6))
	_lamp_post(c, Vector3(shore.x + 2, _ground(shore.x + 2, shore.y + 3), shore.y + 3))
	_signpost(c, Vector3(cx + 4, _ground(cx + 4, cz + 12), cz + 12), -20, [["SALINAS", 1.0], ["VILLA ROSA", -1.0]])
	_stone_wall(c, Vector2(cx - 12, cz + 14), Vector2(cx + 4, cz + 16), 0.8)


func _define_cala(hb_rec: Hub) -> void:
	var cx := hb_rec.centre.x; var cz := hb_rec.centre.y
	_register(&"cala_blanca", "Cala Blanca", cx + 2, cz + 2, Vector3(0, 0, -1))
	hb_rec.ring_pos = db.location_pos(&"cala_blanca"); hb_rec.ring_facing = Vector3(0, 0, -1)
	hb_rec.add_wall(Vector2(cx - 12, cz + 14), Vector2(cx + 4, cz + 16), 0.8)


func _build_salinas(hb_rec: Hub) -> void:
	var s := Node3D.new(); s.name = "Salinas"; sink.add_child(s)
	var cx := hb_rec.centre.x; var cz := hb_rec.centre.y
	var g := _ground(cx, cz)
	# the salt warehouse, the pump windmill, the weighbridge office
	var wh := _house(s, Vector3(cx - 12, g, cz - 8), 0, 14.0, 8.0, 1, Color(0.84, 0.78, 0.66), Color(0.50, 0.42, 0.34))
	wh.scale = Vector3(1, 1.4, 1)
	_house(s, Vector3(cx + 14, g, cz - 12), -90, 6.0, 5.0, 1, Color(0.93, 0.90, 0.82))
	_windmill(s, Vector3(cx + 4, _ground(cx + 4, cz + 16), cz + 16), 200, 8.0)
	_lamp_post(s, Vector3(cx + 8, g, cz + 6))
	for i in range(6):
		var bp := Vector3(cx + 14 + (i % 3) * 1.4, g + 0.5, cz + 8 + (i / 3) * 1.4)
		_static_box(s, Vector3(1.0, 1.0, 1.0), Mats.solid(Color(0.86, 0.82, 0.70), 0.95), bp, Vector3(0, rng.randf_range(-10, 10), 0))
	_salt_heap(s, Vector3(cx + 22, _ground(cx + 22, cz + 9), cz + 9), 1.6)
	_signpost(s, Vector3(cx - 16, _ground(cx - 16, cz + 4), cz + 4), 30, [["CALA BLANCA", -1.0], ["BODEGA", 1.0]])
	_stone_wall(s, Vector2(cx - 22, cz - 16), Vector2(cx + 22, cz - 16), 0.8)


func _define_salinas(hb_rec: Hub) -> void:
	var cx := hb_rec.centre.x; var cz := hb_rec.centre.y
	_register(&"salinas", "The Salinas", cx + 2, cz + 1, Vector3(0, 0, 1))
	hb_rec.ring_pos = db.location_pos(&"salinas"); hb_rec.ring_facing = Vector3(0, 0, 1)
	hb_rec.add_wall(Vector2(cx - 22, cz - 16), Vector2(cx + 22, cz - 16), 0.8)


# ---------------------------------------------------------------- places (no hub)
func _build_place(id: StringName, c: Vector2) -> void:
	var n := Node3D.new(); n.name = String(id).capitalize().replace(" ", ""); sink.add_child(n)
	var cx := c.x; var cz := c.y
	var g := _ground(cx, cz)
	match id:
		&"bodega":
			# the winery: a big estate house, the cellar barn, barrels in the yard, a cypress avenue
			var casa := _house(n, Vector3(cx - 14, g, cz - 16), 180, 12.0, 9.0, 2, Color(0.90, 0.80, 0.62))
			_awning(casa, Vector3(0, 2.65, -4.5), 0, 7.0, Color(0.55, 0.20, 0.22))
			var barn := _house(n, Vector3(cx + 16, g, cz + 16), 0, 9.0, 14.0, 1, Color(0.72, 0.60, 0.46), Color(0.50, 0.36, 0.26))
			barn.scale = Vector3(1, 1.4, 1)
			for i in range(8):
				var bp := Vector3(cx - 2 + (i % 4) * 1.3, 0, cz + 9 + (i / 4) * 1.3)
				n.add_child(Mats.cylinder(0.5, 1.0, Mats.solid(WOOD, 0.85), Vector3(bp.x, g + 0.5, bp.z), Vector3.ZERO, 10))
				_add_cylinder_body(n, 0.5, 1.0, Vector3(bp.x, g, bp.z))
			_lamp_post(n, Vector3(cx - 6, g, cz + 8))
			_signpost(n, Vector3(cx + 6, _ground(cx + 6, cz + 12), cz + 12), 10, [["SALINAS", -1.0], ["TORRE VIEJA", 1.0], ["THE DUNES", 1.0]])
			var cyp := _cypress_parts()
			for i in range(6):
				for side in [-1.0, 1.0]:
					var p := Vector2(cx - 30 + i * 6.0, cz + 16 + side * 4.0)
					_place_prop(cyp, Vector3(p.x, _ground(p.x, p.y), p.y), rng.randf_range(1.2, 1.6), rng.randf_range(0, 360))
		&"torre_vieja":
			# the ruined coastal fort on the headland: the round tower, a broken curtain wall, cannons
			_fort_tower(n, Vector3(cx + 4, g, cz - 4), 4.5, 13.0)
			_stone_wall(n, Vector2(cx - 18, cz + 8), Vector2(cx - 2, cz + 10), 2.4)
			_stone_wall(n, Vector2(cx - 18, cz + 8), Vector2(cx - 22, cz - 10), 1.6)
			var iron := Mats.solid(Color(0.16, 0.16, 0.17), 0.5, 0.4)
			for i in range(2):
				var cp := Vector3(cx - 8 + i * 6.0, g, cz + 6)
				n.add_child(Mats.cylinder(0.22, 2.4, iron, cp + Vector3(0, 0.7, 0), Vector3(-80, 0, 0), 10, 0.16))
				_static_box(n, Vector3(1.0, 0.6, 1.4), Mats.solid(WOOD.darkened(0.2), 0.9), cp + Vector3(0, 0.3, 0.2))
			_signpost(n, Vector3(cx - 8, _ground(cx - 8, cz + 14), cz + 14), -30, [["BODEGA", -1.0], ["DUNES LOOKOUT", -1.0]])
			var pale := _limestone_material()
			for k in range(6):
				var x := cx + rng.randf_range(-24, 20); var z := cz + rng.randf_range(-20, 18)
				if terrain.road_dist_at(x, z) < 6.0 or _near_location(x, z, 8.0): continue
				var s := rng.randf_range(1.0, 2.5)
				_add_rock(Vector3(x, _ground(x, z) - s * 0.3, z), Vector3(s, s * 0.7, s), rng.randf_range(0, 360), pale, s > 1.5)
		&"lakeside_camp":
			# tents round a fire on the lake shore, a jetty and a rowing boat
			_campfire(n, Vector3(cx + 2, _ground(cx + 2, cz + 8), cz + 8))
			_tent(n, Vector3(cx - 7, _ground(cx - 7, cz + 8), cz + 8), 60, Color(0.80, 0.50, 0.30))
			_tent(n, Vector3(cx - 1, _ground(cx - 1, cz + 14), cz + 14), -20, Color(0.34, 0.48, 0.62))
			_tent(n, Vector3(cx + 7, _ground(cx + 7, cz + 3), cz + 3), 250, Color(0.62, 0.62, 0.40))
			for i in range(3):
				var lp := Vector3(cx + 4 + i * 1.2, _ground(cx + 4, cz + 11) + 0.15, cz + 11)
				n.add_child(Mats.cylinder(0.14, 1.6, Mats.solid(WOOD.darkened(0.1), 0.95), lp, Vector3(0, 20, 88), 6))
			var shore := _shore_point(Vector2(cx + 6, cz - 2), 4.0)
			_pier(n, Vector3(shore.x, 0.6, shore.y), -90.0, 10.0, 2.2)
			_boat(n, Vector3(shore.x + 14, 0.15, shore.y + 3), 120, Color(0.75, 0.62, 0.30))
			_signpost(n, Vector3(cx + 5, _ground(cx + 5, cz - 8), cz - 8), 60, [["DUNES LOOKOUT", -1.0], ["VILLA ROSA", -1.0]])
		&"windmill_ridge":
			# three windmills in a row on the ridge above the vineyards
			for i in range(3):
				var wp := Vector3(cx - 22 + i * 22.0, 0, cz - 6 + (i % 2) * 4.0)
				wp.y = _ground(wp.x, wp.z)
				_windmill(n, wp, rng.randf_range(-30, 30), rng.randf_range(8.5, 10.5))
			_house(n, Vector3(cx + 12, g, cz - 14), 0, 6.0, 5.0, 1, Color(0.88, 0.82, 0.68))
			_signpost(n, Vector3(cx - 4, _ground(cx - 4, cz + 3), cz + 3), 0, [["HILLTOP FARM", -1.0], ["VILLA ROSA", 1.0]])
			for i in range(4):
				n.add_child(Mats.cylinder(0.7, 1.2, Mats.solid(Color(0.86, 0.72, 0.38), 1.0), Vector3(cx - 4 + i * 1.6, g + 0.7, cz + 4), Vector3(90, 0, 0), 10))
				_add_cylinder_body(n, 0.7, 1.4, Vector3(cx - 4 + i * 1.6, g, cz + 4))
		&"chapel":
			# a whitewashed hill chapel with a bell gable, a cypress pair and a low wall
			var ch := _house(n, Vector3(cx + 10, _ground(cx + 10, cz - 9), cz - 9), 90, 6.0, 10.0, 1, Color(0.96, 0.95, 0.90), Color(0.66, 0.36, 0.26))
			ch.add_child(Mats.box(Vector3(2.4, 2.4, 0.5), Mats.solid(Color(0.96, 0.95, 0.90), 0.9), Vector3(0, 4.6, -5.2)))
			ch.add_child(Mats.box(Vector3(0.9, 1.1, 0.6), Mats.solid(Color(0.16, 0.19, 0.24), 0.3), Vector3(0, 4.6, -5.2)))
			ch.add_child(Mats.sphere(0.25, Mats.solid(Color(0.55, 0.45, 0.25), 0.4, 0.6), Vector3(0, 4.5, -5.2), Vector3.ONE, 8))
			ch.add_child(Mats.box(Vector3(0.3, 1.0, 0.1), Mats.solid(Color(0.96, 0.95, 0.90), 0.9), Vector3(0, 6.2, -5.2)))
			ch.add_child(Mats.box(Vector3(0.9, 0.3, 0.1), Mats.solid(Color(0.96, 0.95, 0.90), 0.9), Vector3(0, 6.1, -5.2)))
			_stone_wall(n, Vector2(cx - 8, cz + 8), Vector2(cx + 12, cz + 8), 0.8)
			var cyp := _cypress_parts()
			for p in [Vector2(2, -18), Vector2(18, -18)]:
				_place_prop(cyp, Vector3(cx + p.x, _ground(cx + p.x, cz + p.y), cz + p.y), 1.4, rng.randf_range(0, 360))
			n.add_child(Mats.box(Vector3(1.8, 0.1, 0.5), Mats.solid(WOOD, 0.9), Vector3(cx - 4, g + 0.5, cz + 4)))
			for sx in [-0.7, 0.7]:
				n.add_child(Mats.box(Vector3(0.1, 0.5, 0.5), Mats.solid(WOOD, 0.9), Vector3(cx - 4 + sx, g + 0.25, cz + 4)))
		&"refugio":
			# the mountain hut at the top of the pass: stone hut, woodpile, a water trough, a cairn
			_house(n, Vector3(cx + 11, _ground(cx + 11, cz - 2), cz - 2), 90, 7.0, 5.0, 1, STONE_DARK, Color(0.45, 0.40, 0.34))
			for i in range(6):
				n.add_child(Mats.cylinder(0.14, 1.2, Mats.solid(WOOD, 0.95), Vector3(cx + 10 + (i % 3) * 0.3, _ground(cx + 10, cz - 7) + 0.15 + (i / 3) * 0.28, cz - 7), Vector3(0, 0, 90), 6))
			_static_box(n, Vector3(2.4, 0.6, 0.8), Mats.solid(STONE_DARK, 0.95), Vector3(cx - 9, _ground(cx - 9, cz + 4) + 0.3, cz + 4))
			n.add_child(Mats.box(Vector3(2.2, 0.05, 0.6), Mats.solid(Color(0.32, 0.52, 0.52), 0.2), Vector3(cx - 9, _ground(cx - 9, cz + 4) + 0.58, cz + 4)))
			_signpost(n, Vector3(cx - 7, _ground(cx - 7, cz - 8), cz - 8), 100, [["MONASTERY", 1.0], ["HILLTOP FARM", -1.0]])
			_stone_wall(n, Vector2(cx - 14, cz + 10), Vector2(cx - 6, cz + 10), 0.9)
			_stone_wall(n, Vector2(cx + 6, cz + 10), Vector2(cx + 16, cz + 10), 0.9)
			var pale := _limestone_material()
			for i in range(4):
				n.add_child(Mats.sphere(0.5 - i * 0.08, pale, Vector3(cx - 8 + rng.randf_range(-0.2, 0.2), _ground(cx - 8, cz - 6) + 0.3 + i * 0.55, cz - 6), Vector3(1.3, 0.8, 1.1), 6))
