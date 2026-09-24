class_name ArchStyles
extends RefCounted
## Per-style palettes and the deterministic plan of one building (from its plot and seed): floor
## heights, wall / base / trim / roof materials and colours, the facade rhythm, openings, roof type,
## roofscape extras. BuildingKit builds from the plan; build_lod() reads the same plan so the far
## silhouette always matches the detailed building.

const L = preload("res://world/kit/building/arch_materials.gd")

const PUERTO_WALLS := [Color(0.95, 0.76, 0.38), Color(0.93, 0.63, 0.53), Color(0.87, 0.56, 0.60), Color(0.68, 0.30, 0.24),
	Color(0.58, 0.68, 0.80), Color(0.58, 0.75, 0.64), Color(0.95, 0.90, 0.78), Color(0.97, 0.96, 0.93), Color(0.74, 0.64, 0.80),
	Color(0.90, 0.57, 0.32), Color(0.98, 0.84, 0.55), Color(0.46, 0.60, 0.72)]
const AZULEJO_INKS := [Color(0.10, 0.22, 0.62), Color(0.10, 0.22, 0.62), Color(0.12, 0.42, 0.32), Color(0.80, 0.58, 0.12), Color(0.30, 0.52, 0.72)]
const VALDORO_PLASTER := [Color(0.90, 0.88, 0.83), Color(0.86, 0.80, 0.68), Color(0.80, 0.80, 0.78)]
const SARMADA_WALLS := [Color(1.0, 1.0, 1.0), Color(0.99, 0.98, 0.95), Color(1.0, 1.0, 1.0), Color(0.97, 0.95, 0.90)]
const SARMADA_OCHRE := [Color(0.96, 0.74, 0.48), Color(0.94, 0.83, 0.64), Color(0.93, 0.66, 0.46), Color(0.98, 0.86, 0.72)]
const SARMADA_BLUES := [Color(0.10, 0.36, 0.64), Color(0.10, 0.36, 0.64), Color(0.14, 0.52, 0.72), Color(0.18, 0.28, 0.58), Color(0.12, 0.46, 0.40)]
const ISOLA_WALLS := [Color(0.98, 0.64, 0.62), Color(1.0, 0.84, 0.42), Color(0.46, 0.80, 0.80), Color(1.0, 0.72, 0.50),
	Color(0.98, 0.97, 0.94), Color(0.80, 0.68, 0.88), Color(0.64, 0.88, 0.70), Color(0.58, 0.76, 0.94), Color(1.0, 0.56, 0.46), Color(0.99, 0.9, 0.62)]
const ISOLA_SHUTTERS := [Color(0.14, 0.46, 0.28), Color(0.12, 0.36, 0.64), Color(0.16, 0.54, 0.54), Color(0.14, 0.46, 0.28), Color(0.95, 0.95, 0.93)]
const CAMPO_PLASTER := [Color(0.94, 0.85, 0.66), Color(0.90, 0.72, 0.50), Color(0.96, 0.91, 0.81), Color(0.86, 0.62, 0.44), Color(0.92, 0.80, 0.60)]
const CAMPO_HONEY := Color(1.0, 0.86, 0.62)
const WOOD_PAINTS := [Color(0.20, 0.33, 0.24), Color(0.36, 0.24, 0.16), Color(0.55, 0.20, 0.16), Color(0.22, 0.30, 0.42), Color(0.12, 0.12, 0.12), Color(0.46, 0.36, 0.26)]
const PUERTO_DOORS := [Color(0.16, 0.30, 0.22), Color(0.45, 0.14, 0.12), Color(0.14, 0.20, 0.36), Color(0.30, 0.20, 0.13), Color(0.10, 0.10, 0.11), Color(0.20, 0.42, 0.45)]
const AWNINGS := [Color(0.72, 0.16, 0.12), Color(0.16, 0.36, 0.26), Color(0.16, 0.28, 0.55), Color(0.85, 0.60, 0.15), Color(0.45, 0.20, 0.35)]
const ROOF_TINTS := [Color(1.0, 1.0, 1.0), Color(0.96, 0.9, 0.86), Color(1.04, 0.96, 0.92), Color(0.92, 0.84, 0.8)]
const GRANITE := Color(0.74, 0.73, 0.70)
const WHITE := Color(0.96, 0.95, 0.92)


static func pick(rng: RandomNumberGenerator, a: Array):
	return a[rng.randi_range(0, a.size() - 1)]


static func wx(layer: int, weather: float) -> float:
	return float(layer) + clampf(weather, 0.0, 0.79)


## The plan of one ordinary building (house, rowhouse, shop, palazzo, warehouse, barn, granary,
## boathouse, town_hall and every unknown kind).
static func plan(p: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(p.get("seed", 1))
	var style: String = p.get("style", "campo")
	var kind: String = p.get("kind", "house")
	var tags: Array = p.get("tags", [])
	var floors: int = clampi(int(p.get("floors", 2)), 1, 7)
	var w: float = maxf(float(p.get("w", 8.0)), 2.5)
	var d: float = maxf(float(p.get("d", 8.0)), 2.5)
	var q := {"style": style, "kind": kind, "w": w, "d": d, "floors": floors, "tags": tags}
	q.weather = rng.randf_range(0.05, 0.7)
	q.party = p.get("party", [kind == "rowhouse" or (style == "puerto" and kind in ["shop", "palazzo"]), kind == "rowhouse" or (style == "puerto" and kind in ["shop", "palazzo"])])
	q.shop = kind == "shop" or "shopfront" in tags
	q.arcade = "arcade" in tags
	q.terrace = "terrace" in tags
	q.corner = "corner" in tags
	# defaults, overwritten per style
	q.R = 0.3; q.bay = 2.6; q.edge = 0.7; q.plinth_h = 0.45
	q.pilasters = false; q.bands = false; q.cornice = 0
	q.win_w = 1.0; q.win_h = 1.4; q.sill = 0.95; q.panes = Vector2i(2, 3)
	q.french = 0; q.balcony = -1; q.shutters = 0; q.frame = WHITE; q.surround = 0.0; q.sur_col = GRANITE
	q.sill_col = Color(0.8, 0.78, 0.74); q.lintel = 0; q.grille_ground = false
	q.paint = pick(rng, WOOD_PAINTS); q.door_paint = q.paint
	q.door_w = 1.2; q.door_h = 2.5; q.door_leaf = 0; q.fanlight = false; q.door_arch = 0
	q.awning = null
	q.roof = "gable_x"; q.roof_layer = L.ROOF_TILE; q.roof_tint = pick(rng, ROOF_TINTS)
	q.pitch = deg_to_rad(24.0); q.ov_eave = 0.45; q.ov_verge = 0.3; q.thick = 0.2; q.parapet = 0.0
	q.soffit_layer = L.TIMBER; q.soffit_tint = Color(0.62, 0.5, 0.4)
	q.chimneys = rng.randi_range(0, 2); q.chimney_kind = 0; q.dormers = 0
	q.beams = false; q.merlons = -1; q.dome = false; q.stairhead = false; q.loggia = false; q.ext_stair = false
	q.upper = null; q.base = null
	q.blank_ratio = 0.0; q.pots = 0.0; q.lanterns = 0.0
	var fh: Array = []
	match style:
		"puerto": _puerto(q, rng, fh)
		"valdoro": _valdoro(q, rng, fh)
		"sarmada": _sarmada(q, rng, fh)
		"isola": _isola(q, rng, fh)
		"core": _core(q, rng, fh, p)
		_: _campo(q, rng, fh)
	# kind overrides that are the same everywhere
	match kind:
		"barn": _barn(q, rng, fh)
		"granary": _granary(q, rng, fh)
		"warehouse": _warehouse(q, rng, fh)
		"boathouse": _boathouse(q, rng, fh)
	if fh.is_empty():
		for i in range(floors): fh.append(3.1)
	q.fh = fh
	var H := 0.0
	for v in fh: H += v
	q.H = H
	return q


static func _floors(fh: Array, n: int, ground: float, upper: float, top: float, rng: RandomNumberGenerator) -> void:
	for i in range(n):
		var h := upper
		if i == 0: h = ground
		elif i == n - 1 and n > 2: h = top
		fh.append(h + rng.randf_range(-0.08, 0.08))


static func _puerto(q: Dictionary, rng: RandomNumberGenerator, fh: Array) -> void:
	var floors: int = q.floors
	var palazzo: bool = q.kind == "palazzo"
	_floors(fh, floors, 4.0 if q.shop else 3.6, rng.randf_range(3.05, 3.4), 2.9, rng)
	if palazzo:
		for i in range(fh.size()): fh[i] += 0.35 if i == 1 else 0.15
	q.wall = [wx(L.PLASTER, q.weather), pick(rng, PUERTO_WALLS)]
	var tiled := rng.randf() < (0.34 if not palazzo else 0.15)
	if tiled:
		# azulejo from the first floor up: the ink is the tint, the glaze stays white
		q.upper = [wx(L.AZULEJO, q.weather * 0.3), pick(rng, AZULEJO_INKS), 1]
	q.base = [wx(L.ASHLAR, q.weather), GRANITE] if rng.randf() < 0.55 or palazzo else null
	q.trim = [wx(L.STONE, q.weather), GRANITE if rng.randf() < 0.7 else WHITE]
	q.pilasters = true
	q.bands = palazzo or rng.randf() < 0.45
	q.cornice = 2 if palazzo else 1
	q.R = 0.25; q.bay = rng.randf_range(2.1, 2.5) if not palazzo else 2.7; q.edge = 0.75
	q.win_w = 1.0 + (0.1 if palazzo else 0.0); q.win_h = 1.6; q.sill = 0.9; q.panes = Vector2i(2, 3)
	q.french = 2 if rng.randf() < 0.75 else 1        # 2: every upper floor, 1: first floor only
	q.balcony = 1 if palazzo or rng.randf() < 0.55 else 0
	q.iron = Color(0.08, 0.08, 0.09)
	q.shutters = 0 if rng.randf() < 0.7 else 1
	q.frame = WHITE if rng.randf() < 0.7 else pick(rng, [Color(0.18, 0.3, 0.22), Color(0.35, 0.22, 0.14), Color(0.55, 0.16, 0.14)])
	q.surround = 0.16; q.sur_col = GRANITE; q.sill_col = GRANITE
	q.door_paint = pick(rng, PUERTO_DOORS); q.paint = q.door_paint
	q.door_w = 1.3; q.door_h = 2.9; q.fanlight = true
	q.awning = pick(rng, AWNINGS) if q.shop and rng.randf() < 0.7 else null
	q.roof = "gable_x" if not palazzo or q.party[0] or q.party[1] else "hip"
	q.pitch = deg_to_rad(rng.randf_range(22.0, 30.0)); q.ov_eave = 0.5
	q.dormers = rng.randi_range(0, 2) if floors >= 3 and rng.randf() < 0.45 else 0
	q.chimneys = rng.randi_range(1, 2); q.chimney_kind = 0
	q.lanterns = 0.25


static func _valdoro(q: Dictionary, rng: RandomNumberGenerator, fh: Array) -> void:
	var floors: int = q.floors
	_floors(fh, floors, 2.9, 2.75, 2.6, rng)
	var plastered := rng.randf() < 0.25
	q.wall = [wx(L.PLASTER, q.weather + 0.25), pick(rng, VALDORO_PLASTER)] if plastered else [wx(L.RUBBLE, q.weather), Color(1.0, 0.99, 0.97).lerp(Color(0.92, 0.9, 0.86), rng.randf())]
	if floors >= 2 and rng.randf() < 0.55:
		q.upper = [wx(L.TIMBER, q.weather + 0.2), pick(rng, [Color(1, 1, 1), Color(0.8, 0.72, 0.64), Color(0.9, 0.88, 0.86)]), floors - 1]
	q.base = [wx(L.RUBBLE, q.weather), Color(0.9, 0.9, 0.9)] if plastered else null
	q.trim = [wx(L.STONE, q.weather), Color(0.66, 0.66, 0.66)]
	q.pilasters = plastered
	q.R = 0.5; q.bay = rng.randf_range(2.6, 3.4); q.edge = 1.0
	q.win_w = 0.72; q.win_h = 0.95; q.sill = 0.95; q.panes = Vector2i(1, 2)
	q.shutters = 1 if rng.randf() < 0.8 else 3
	q.paint = pick(rng, [Color(0.22, 0.34, 0.24), Color(0.36, 0.25, 0.17), Color(0.5, 0.4, 0.3), Color(0.55, 0.22, 0.17), Color(0.4, 0.46, 0.5)])
	q.frame = Color(0.42, 0.32, 0.22); q.surround = 0.0; q.lintel = 1; q.sill_col = Color(0.62, 0.62, 0.62)
	q.door_paint = Color(0.42, 0.3, 0.2) if rng.randf() < 0.6 else q.paint
	q.door_w = 1.05; q.door_h = 2.2; q.door_leaf = 1
	q.balcony = 2 if floors >= 2 and rng.randf() < 0.6 else -1
	q.french = 1 if q.balcony == 2 else 0      # a long wooden balcony across the first floor
	q.roof = "gable_z"; q.roof_layer = L.SLATE; q.roof_tint = Color(1, 1, 1).lerp(Color(0.86, 0.88, 0.9), rng.randf())
	q.pitch = deg_to_rad(rng.randf_range(26.0, 33.0)); q.ov_eave = 0.8; q.ov_verge = 0.9; q.thick = 0.28
	q.chimneys = rng.randi_range(1, 2); q.chimney_kind = 1
	q.plinth_h = 0.3
	q.pots = 0.3


static func _sarmada(q: Dictionary, rng: RandomNumberGenerator, fh: Array) -> void:
	var floors: int = q.floors
	_floors(fh, floors, 3.2, 3.0, 2.9, rng)
	var ochre := rng.randf() < 0.3
	q.wall = [wx(L.ADOBE, q.weather), pick(rng, SARMADA_OCHRE)] if ochre else [wx(L.WHITEWASH, q.weather * 0.6), pick(rng, SARMADA_WALLS)]
	q.trim = [wx(L.ADOBE, q.weather), pick(rng, SARMADA_OCHRE)]
	q.base = [wx(L.ADOBE, q.weather), q.trim[1]] if rng.randf() < 0.35 and not ochre else null
	q.R = 0.45; q.bay = rng.randf_range(2.8, 3.8); q.edge = 1.0
	q.win_w = 0.62; q.win_h = 0.9; q.sill = 1.1; q.panes = Vector2i(1, 2)
	q.blank_ratio = 0.35
	q.shutters = 2 if rng.randf() < 0.5 else 1
	q.paint = pick(rng, SARMADA_BLUES); q.door_paint = q.paint
	q.frame = q.paint; q.surround = 0.18 if rng.randf() < 0.6 else 0.0
	q.sur_col = Color(0.93, 0.78, 0.55) if not ochre else Color(0.99, 0.98, 0.95)
	q.sill_col = q.sur_col; q.lintel = 2 if q.surround == 0.0 else 0
	q.grille_ground = true
	q.door_w = 1.2; q.door_h = 2.6; q.door_leaf = 1; q.door_arch = 2 if rng.randf() < 0.75 else 1
	q.roof = "flat"; q.parapet = rng.randf_range(0.9, 1.3); q.roof_layer = L.TERRACE; q.roof_tint = q.wall[1]
	q.chimneys = 0
	q.beams = rng.randf() < 0.6
	q.merlons = 0 if rng.randf() < 0.3 else -1
	q.dome = rng.randf() < 0.18
	q.stairhead = q.terrace or rng.randf() < 0.5
	q.awning = pick(rng, [Color(0.85, 0.6, 0.2), Color(0.7, 0.2, 0.15), Color(0.16, 0.36, 0.6)]) if q.shop and rng.randf() < 0.5 else null
	q.plinth_h = 0.25


static func _isola(q: Dictionary, rng: RandomNumberGenerator, fh: Array) -> void:
	var floors: int = q.floors
	_floors(fh, floors, 3.0, 2.95, 2.9, rng)
	q.wall = [wx(L.PLASTER, q.weather), pick(rng, ISOLA_WALLS)]
	q.trim = [wx(L.PLASTER, q.weather * 0.5), WHITE]
	q.R = 0.32; q.bay = rng.randf_range(2.2, 2.8); q.edge = 0.7
	q.win_w = 0.9; q.win_h = 1.3; q.sill = 0.9; q.panes = Vector2i(1, 3)
	q.shutters = 1 if rng.randf() < 0.75 else 3
	q.paint = pick(rng, ISOLA_SHUTTERS); q.door_paint = q.paint if rng.randf() < 0.6 else pick(rng, ISOLA_SHUTTERS)
	q.frame = WHITE; q.surround = 0.14; q.sur_col = Color(0.985, 0.98, 0.97); q.sill_col = Color(0.96, 0.95, 0.93)
	q.door_w = 1.1; q.door_h = 2.4; q.door_leaf = 1 if rng.randf() < 0.5 else 0; q.door_arch = 1 if rng.randf() < 0.5 else 0
	q.french = 1 if floors >= 2 and rng.randf() < 0.3 else 0
	q.balcony = 1 if q.french > 0 else -1
	q.iron = Color(0.1, 0.1, 0.1)
	var vault: bool = rng.randf() < 0.45 and float(q.w) <= 9.5
	q.roof = "barrel" if vault else "flat"
	q.parapet = 0.55 if not vault else 0.0
	q.roof_layer = L.WHITEWASH if vault else L.TERRACE
	q.roof_tint = WHITE if vault else Color(0.95, 0.93, 0.9)
	q.chimneys = rng.randi_range(0, 1); q.chimney_kind = 3
	q.loggia = floors >= 2 and rng.randf() < 0.35
	q.ext_stair = floors >= 2 and rng.randf() < 0.4
	q.stair_dir = 1 if rng.randf() < 0.5 else -1
	q.pots = 0.6
	q.plinth_h = 0.35
	q.base = [wx(L.PLASTER, q.weather), q.wall[1].darkened(0.12)] if rng.randf() < 0.5 else null


static func _campo(q: Dictionary, rng: RandomNumberGenerator, fh: Array) -> void:
	var floors: int = q.floors
	var palazzo: bool = q.kind in ["palazzo", "town_hall"]
	_floors(fh, floors, 3.6 if q.shop or q.arcade else 3.3, 3.2, 3.0, rng)
	var r := rng.randf()
	if r < 0.35: q.wall = [wx(L.ASHLAR, q.weather), CAMPO_HONEY.lerp(Color(1, 0.94, 0.82), rng.randf() * 0.6)]
	elif r < 0.6: q.wall = [wx(L.BRICK, q.weather), Color(1, 1, 1).lerp(Color(1.0, 0.9, 0.8), rng.randf())]
	else: q.wall = [wx(L.PLASTER, q.weather), pick(rng, CAMPO_PLASTER)]
	q.trim = [wx(L.STONE, q.weather), CAMPO_HONEY]
	q.base = [wx(L.ASHLAR, q.weather), CAMPO_HONEY.darkened(0.05)] if q.wall[0] != wx(L.ASHLAR, q.weather) else null
	q.pilasters = palazzo or q.wall[0] >= L.BRICK and q.wall[0] < L.BRICK + 1
	q.bands = palazzo or rng.randf() < 0.4
	q.cornice = 2 if palazzo else 1
	q.R = 0.32; q.bay = rng.randf_range(2.6, 3.2); q.edge = 0.8
	q.win_w = 0.95; q.win_h = 1.45; q.sill = 0.95; q.panes = Vector2i(2, 3)
	q.shutters = 1 if rng.randf() < 0.7 else 2 if rng.randf() < 0.5 else 3
	q.paint = pick(rng, [Color(0.38, 0.25, 0.15), Color(0.32, 0.38, 0.24), Color(0.25, 0.33, 0.27), Color(0.5, 0.36, 0.22), Color(0.55, 0.52, 0.45)])
	q.door_paint = Color(0.34, 0.22, 0.14)
	q.frame = Color(0.9, 0.88, 0.84); q.surround = 0.15 if rng.randf() < 0.6 or palazzo else 0.0; q.sur_col = CAMPO_HONEY
	q.sill_col = CAMPO_HONEY
	q.french = 1 if floors >= 2 and rng.randf() < 0.35 else 0
	q.balcony = 1 if q.french > 0 else -1
	q.iron = Color(0.1, 0.1, 0.1)
	q.door_w = 1.3; q.door_h = 2.6; q.door_leaf = 0 if rng.randf() < 0.5 else 1; q.door_arch = 1 if rng.randf() < 0.4 else 0
	q.roof = "hip" if rng.randf() < 0.5 and not (q.party[0] or q.party[1]) else "gable_x"
	q.pitch = deg_to_rad(rng.randf_range(17.0, 22.0)); q.ov_eave = 0.6; q.ov_verge = 0.35
	q.chimneys = rng.randi_range(0, 2); q.chimney_kind = 2 if q.wall[0] >= L.BRICK and q.wall[0] < L.BRICK + 1 else 0
	q.awning = pick(rng, AWNINGS) if q.shop and not q.arcade and rng.randf() < 0.5 else null
	q.pots = 0.25


static func _core(q: Dictionary, rng: RandomNumberGenerator, fh: Array, p: Dictionary) -> void:
	for i in range(int(q.floors)): fh.append(3.1)
	var wc: Color = p.get("wall", Color(0.95, 0.93, 0.88))
	q.wall = [wx(L.WHITEWASH, q.weather * 0.7), wc]
	q.trim = [wx(L.WHITEWASH, q.weather * 0.5), Color(0.99, 0.99, 0.98)]
	q.base = [wx(L.RUBBLE, q.weather), Color(1.0, 0.97, 0.9)] if rng.randf() < 0.4 else null
	q.R = 0.32; q.bay = rng.randf_range(2.2, 2.8); q.edge = 0.8
	q.win_w = 0.85; q.win_h = 1.2; q.sill = 0.95; q.panes = Vector2i(1, 3)
	q.shutters = 1 if rng.randf() < 0.75 else 3
	q.paint = pick(rng, [Color(0.14, 0.36, 0.66), Color(0.14, 0.36, 0.66), Color(0.12, 0.46, 0.62), Color(0.2, 0.46, 0.3)])
	q.door_paint = q.paint if rng.randf() < 0.7 else Color(0.38, 0.26, 0.16)
	q.frame = WHITE; q.surround = 0.12 if rng.randf() < 0.5 else 0.0; q.sur_col = Color(0.985, 0.98, 0.97); q.sill_col = Color(0.9, 0.88, 0.84)
	q.door_w = 1.1; q.door_h = 2.3; q.door_leaf = 1 if rng.randf() < 0.5 else 0; q.door_arch = 1 if rng.randf() < 0.3 else 0
	q.roof_tint = p.get("roof", Color(1, 1, 1))
	q.chimneys = rng.randi_range(0, 1); q.chimney_kind = 3
	q.pots = 0.4
	if q.terrace:
		# town houses: a roof terrace 0.6 m above the top floor's ceiling (WorldKit._house's terrace collider)
		q.roof = "flat"; q.parapet = 0.55; q.roof_layer = L.TERRACE; q.roof_tint = Color(0.95, 0.93, 0.9)
		fh[fh.size() - 1] = float(fh[fh.size() - 1]) + 0.6
	else:
		q.roof = "gable_z"; q.ov_eave = 0.3; q.ov_verge = 0.3
		q.pitch = atan2(1.75, q.w * 0.56)
		q.core_ridge = 1.75


static func _barn(q: Dictionary, rng: RandomNumberGenerator, fh: Array) -> void:
	fh.clear()
	var n: int = q.floors
	var style: String = q.style
	for i in range(n): fh.append(3.4 if i == 0 else 3.0)
	q.shop = false; q.awning = null; q.french = 0; q.balcony = -1; q.dormers = 0; q.chimneys = 0; q.loggia = false; q.ext_stair = false
	q.win_w = 0.6; q.win_h = 0.6; q.sill = 1.8; q.shutters = 2; q.blank_ratio = 0.5; q.panes = Vector2i(1, 1)
	q.door_w = minf(3.4, q.w - 2.0); q.door_h = 3.3; q.door_leaf = 1; q.fanlight = false; q.surround = 0.0
	q.door_paint = pick(rng, [Color(0.5, 0.36, 0.24), Color(0.55, 0.22, 0.16), Color(0.42, 0.4, 0.36), Color(0.36, 0.3, 0.22)])
	q.barn = true
	match style:
		"valdoro":
			q.wall = [q.wall[0] if q.wall[0] >= L.RUBBLE and q.wall[0] < L.RUBBLE + 1 else wx(L.RUBBLE, q.weather), Color(0.97, 0.96, 0.94)]
			q.upper = [wx(L.TIMBER, q.weather + 0.25), Color(0.9, 0.84, 0.78), 1 if n >= 2 else 99]
			q.roof = "gable_z"
		"sarmada":
			q.wall = [wx(L.ADOBE, q.weather), pick(rng, SARMADA_OCHRE)]
			q.roof = "flat"; q.parapet = 0.6
		"isola":
			q.roof = "barrel"; q.roof_layer = L.WHITEWASH; q.roof_tint = WHITE
		_:
			q.wall = [wx(L.BRICK, q.weather), Color(1, 0.95, 0.9)] if rng.randf() < 0.45 else [wx(L.RUBBLE, q.weather), Color(1.0, 0.92, 0.8)]
			q.roof = "gable_z" if q.d > q.w else "gable_x"
			q.pitch = deg_to_rad(22.0)
	q.pilasters = false; q.bands = false; q.cornice = 0


static func _granary(q: Dictionary, rng: RandomNumberGenerator, fh: Array) -> void:
	_barn(q, rng, fh)
	q.granary = true
	match q.style:
		"campo", "valdoro", "core":
			if rng.randf() < 0.5 or q.style == "valdoro":
				q.staddles = true             # a timber granary raised on mushroom stones
				fh.clear(); fh.append(2.6)
				if q.floors >= 2: fh.append(2.2)
				q.wall = [wx(L.TIMBER, q.weather + 0.2), Color(0.86, 0.76, 0.66)]
				q.upper = null; q.w = minf(q.w, 7.0); q.d = minf(q.d, 6.0)
				q.door_w = 1.0; q.door_h = 1.8
				q.roof = "gable_x"
				if q.style == "valdoro": q.roof_layer = L.SLATE
			else:
				q.tower = true                # a tall brick granary tower with a pyramid roof
				fh.clear()
				for i in range(maxi(3, q.floors + 1)): fh.append(3.2)
				q.wall = [wx(L.BRICK, q.weather), Color(1.0, 0.94, 0.88)]
				q.w = minf(q.w, 7.0); q.d = q.w
				q.roof = "hip"; q.pitch = deg_to_rad(30.0)
				q.door_w = 1.2; q.door_h = 2.4
		"sarmada":
			q.wall = [wx(L.ADOBE, q.weather), pick(rng, SARMADA_OCHRE).darkened(0.05)]
			q.roof = "flat"; q.parapet = 0.9; q.merlons = 0
			q.door_w = 1.0; q.door_h = 1.8
	q.win_w = 0.45; q.win_h = 0.45


static func _warehouse(q: Dictionary, rng: RandomNumberGenerator, fh: Array) -> void:
	fh.clear()
	for i in range(int(q.floors)): fh.append(4.2 if i == 0 else 3.6)
	q.wall = [wx(L.BRICK, q.weather), Color(1, 0.96, 0.92)]
	q.upper = null; q.base = [wx(L.ASHLAR, q.weather), GRANITE]
	q.shop = false; q.awning = null; q.french = 0; q.balcony = -1; q.dormers = 0
	q.warehouse = true
	q.win_w = 1.3; q.win_h = 1.9; q.sill = 1.0; q.panes = Vector2i(3, 4); q.shutters = 0; q.frame = Color(0.25, 0.3, 0.28)
	q.door_w = 3.2; q.door_h = 3.9; q.door_leaf = 1; q.door_arch = 1; q.fanlight = false
	q.door_paint = pick(rng, [Color(0.2, 0.3, 0.26), Color(0.45, 0.16, 0.12), Color(0.3, 0.22, 0.16)])
	q.bay = 4.2; q.edge = 1.2; q.pilasters = true; q.bands = true; q.cornice = 1
	q.roof = "gable_z" if q.d > q.w else "gable_x"; q.pitch = deg_to_rad(20.0)


static func _boathouse(q: Dictionary, rng: RandomNumberGenerator, fh: Array) -> void:
	fh.clear(); fh.append(3.8)
	q.shop = false; q.awning = null; q.french = 0; q.balcony = -1; q.loggia = false; q.ext_stair = false; q.chimneys = 0
	q.boathouse = true
	q.door_w = minf(q.w - 1.4, 3.6); q.door_h = 3.4; q.door_leaf = 1; q.door_arch = 1; q.fanlight = false
	q.roof = "barrel"; q.roof_layer = L.WHITEWASH; q.roof_tint = WHITE; q.parapet = 0.0
	q.win_w = 0.5; q.win_h = 0.5; q.sill = 2.2; q.blank_ratio = 0.6
