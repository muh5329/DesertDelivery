class_name ArchModules
extends RefCounted
## The architecture kit's repeated pieces (windows, doors, shopfronts, balconies, awnings, chimneys,
## dormers, beams, merlons, pots...), each built once per key and drawn as a MultiMesh per group.
##
## Module frame = the opening frame: x across the opening (to the viewer's right), y up from the
## opening's bottom, z out of the wall; z = 0 is the wall face, z = -R the back of the reveal. The
## wall's hole and its reveal are part of the merged group mesh (ArchFacade); a module fills it.
## Parts are tagged for arch.gdshader: flag 0 fixed colour, 1 x paint (INSTANCE_CUSTOM.rgb),
## 2 x the host wall (INSTANCE_CUSTOM.rgb tint and .a layer).

const L = preload("res://world/kit/building/arch_materials.gd")
const F = preload("res://world/kit/building/arch_facade.gd")
static var _cache: Dictionary = {}       # key -> ArrayMesh
static var shadows: Dictionary = {}      # key -> bool (does it cast shadows)
static var details: Dictionary = {}      # key -> bool (an add-on that may fade out with distance; never one that fills a hole)
static var build_ms := 0.0


static func has(key: String) -> bool:
	return _cache.has(key)


static func mesh(key: String) -> ArrayMesh:
	return _cache.get(key)


static var _arrays: Dictionary = {}
static var _runs: Dictionary = {}

## Runs of consecutive vertices sharing a part (colour, layer, flag): [start, count, Color, layer, flag]
## (baking fills whole runs instead of looping over vertices).
static func runs(key: String) -> Array:
	if _runs.has(key): return _runs[key]
	var arr := arrays(key)
	var c0: PackedFloat32Array = arr[Mesh.ARRAY_CUSTOM0]
	var u2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2]
	var out: Array = []
	var n := u2.size()
	var start := 0
	for i in range(1, n + 1):
		if i < n and u2[i] == u2[start] and c0[i * 4] == c0[start * 4] and c0[i * 4 + 1] == c0[start * 4 + 1] and c0[i * 4 + 2] == c0[start * 4 + 2]:
			continue
		out.append([start, i - start, Color(c0[start * 4], c0[start * 4 + 1], c0[start * 4 + 2], 1.0), u2[start].x, u2[start].y])
		start = i
	_runs[key] = out
	return out

## The module's surface arrays (for baking modules into a merged mesh).
static func arrays(key: String) -> Array:
	if not _arrays.has(key):
		_arrays[key] = (_cache[key] as ArrayMesh).surface_get_arrays(0)
	return _arrays[key]


static func _begin() -> ArchMesh:
	var m := ArchMesh.new()
	m.module = true
	return m


static func _put(key: String, m: ArchMesh, cast := false, detail := false) -> String:
	_cache[key] = m.commit()
	shadows[key] = cast
	details[key] = detail
	return key


static func _part(m: ArchMesh, layer: int, tint: Color, flag: float) -> void:
	m.layer = float(layer); m.tint = tint; m.flag = flag


# ---------------------------------------------------------------- openings
## A window: frame, glazing bars, glass, sill, optional stone surround / lintel, shutters, grille.
## shutter: 0 none, 1 open, 2 closed, 3 one leaf closed. bars: panes across x panes down per leaf.
static func window(w: float, h: float, R: float, sill: Color, surround: float, sur_col: Color,
		shutter: int, lintel: int = 0, grille: bool = false, panes: Vector2i = Vector2i(1, 3), arch: int = 0) -> String:
	var key := "win|%d|%d|%d|%s|%d|%s|%d|%d|%d|%d|%d|%d" % [roundi(w * 100), roundi(h * 100), roundi(R * 100), sill.to_html(false),
		roundi(surround * 100), sur_col.to_html(false), shutter, lintel, int(grille), panes.x, panes.y, arch]
	if _cache.has(key): return key
	var t0 := Time.get_ticks_usec()
	var m := _begin()
	var zf := -maxf(0.1, R * 0.6)            # frame plane: deep in thick walls
	var fw := 0.07
	var spring := h if arch == 0 else h - F.arch_top(w, arch)
	_part(m, L.PLASTER, Color.WHITE, 2)
	_reveal(m, w, spring, zf - 0.03, arch)
	# glass (behind the frame) and the frame
	_part(m, L.GLASS, Color.WHITE, 0)
	m.quad(Vector3(-w * 0.5, 0, zf - 0.02), Vector3(w * 0.5, 0, zf - 0.02), Vector3(w * 0.5, spring, zf - 0.02), Vector3(-w * 0.5, spring, zf - 0.02))
	if arch > 0: _arch_fill(m, w, spring, zf - 0.02, arch)
	_part(m, L.PLASTER, Color.WHITE, 3)
	_frame(m, w, spring, zf, fw, 0.08)
	var leaves := 2 if w > 0.75 else 1
	var lw := w / leaves
	for i in range(1, leaves):
		m.cbox(Vector3(-w * 0.5 + lw * i, spring * 0.5, zf), Vector3(fw, spring, 0.08), 63 - 8)
	# glazing bars
	var bar := 0.028
	for li in range(leaves):
		var x0 := -w * 0.5 + lw * li
		for k in range(1, panes.y):
			m.cbox(Vector3(x0 + lw * 0.5, spring * k / panes.y, zf + 0.005), Vector3(lw - fw, bar, 0.04), 1 | 2 | 4 | 8 | 16)
		for k in range(1, panes.x):
			m.cbox(Vector3(x0 + lw * k / panes.x, spring * 0.5, zf + 0.005), Vector3(bar, spring - fw, 0.04), 1 | 2 | 16)
	# sill: a stone slab that runs through the reveal and out past the wall
	_part(m, L.STONE, sill, 0)
	m.box(Vector3(-w * 0.5 - 0.07, -0.07, zf), Vector3(w * 0.5 + 0.07, 0.0, 0.07), 63 - 32)
	# stone surround (architrave) or a painted band
	if surround > 0.0:
		_part(m, L.STONE if sur_col.v < 0.97 else L.PLASTER, sur_col, 0)
		var s := surround
		var top := h
		m.box(Vector3(-w * 0.5 - s, -0.07, 0.0), Vector3(-w * 0.5, top + s, 0.035), 1 | 2 | 4 | 16)
		m.box(Vector3(w * 0.5, -0.07, 0.0), Vector3(w * 0.5 + s, top + s, 0.035), 1 | 2 | 4 | 16)
		if arch == 0:
			m.box(Vector3(-w * 0.5, top, 0.0), Vector3(w * 0.5, top + s, 0.035), 4 | 8 | 16)
		else:
			_arch_band(m, w, spring, s, 0.035, arch)
	if lintel == 1:            # a rough stone lintel (alpine)
		_part(m, L.STONE, sill.darkened(0.1), 0)
		m.box(Vector3(-w * 0.5 - 0.22, h, -0.02), Vector3(w * 0.5 + 0.22, h + 0.24, 0.04), 1 | 2 | 4 | 8 | 16)
	elif lintel == 2:          # a timber lintel (desert)
		_part(m, L.TIMBER, Color(0.75, 0.62, 0.5), 0)
		m.box(Vector3(-w * 0.5 - 0.2, h, -0.02), Vector3(w * 0.5 + 0.2, h + 0.14, 0.05), 1 | 2 | 4 | 8 | 16)
	if grille:
		_part(m, L.IRON, Color(0.2, 0.2, 0.22), 0)
		var nb := maxi(2, roundi(w / 0.13))
		for k in range(1, nb):
			m.cbox(Vector3(-w * 0.5 + w * k / nb, spring * 0.5, -0.04), Vector3(0.02, spring, 0.02), 1 | 2 | 16)
		for yy: float in [spring * 0.3, spring * 0.7]:
			m.cbox(Vector3(0, yy, -0.03), Vector3(w, 0.025, 0.02), 4 | 8 | 16)
	if shutter > 0:
		_part(m, L.SHUTTER, Color.WHITE, 1)
		var sw := w * 0.5
		for side: float in [-1.0, 1.0]:
			var closed := shutter == 2 or (shutter == 3 and side > 0.0)
			if closed:
				m.box(Vector3(minf(0.0, side * sw), 0.0, zf + 0.04), Vector3(maxf(0.0, side * sw), spring, zf + 0.075), 1 | 2 | 4 | 16)
			else:
				var x0 := side * (w * 0.5 + 0.02)
				m.box(Vector3(minf(x0, x0 + side * sw), 0.0, 0.03), Vector3(maxf(x0, x0 + side * sw), spring, 0.065), 1 | 2 | 4 | 8 | 16)
	build_ms += (Time.get_ticks_usec() - t0) / 1000.0
	return _put(key, m)


## A French window (door-height glazing) with a balcony: 0 railing flush with the wall (Juliet),
## 1 stone slab on brackets with an iron railing, 2 wooden balcony.
static func french(w: float, h: float, R: float, surround: float, sur_col: Color, balcony: int, bw: float,
		shutter: int, iron: Color) -> String:
	var key := "fr|%d|%d|%d|%d|%s|%d|%d|%d|%s" % [roundi(w * 100), roundi(h * 100), roundi(R * 100), roundi(surround * 100),
		sur_col.to_html(false), balcony, roundi(bw * 100), shutter, iron.to_html(false)]
	if _cache.has(key): return key
	var t0 := Time.get_ticks_usec()
	var m := _begin()
	var zf := -maxf(0.1, R * 0.6)
	_part(m, L.PLASTER, Color.WHITE, 2)
	_reveal(m, w, h, zf - 0.03, 0)
	m.quad(Vector3(-w * 0.5, 0, 0), Vector3(w * 0.5, 0, 0), Vector3(w * 0.5, 0, zf - 0.03), Vector3(-w * 0.5, 0, zf - 0.03))
	_part(m, L.GLASS, Color.WHITE, 0)
	m.quad(Vector3(-w * 0.5, 0, zf - 0.02), Vector3(w * 0.5, 0, zf - 0.02), Vector3(w * 0.5, h, zf - 0.02), Vector3(-w * 0.5, h, zf - 0.02))
	_part(m, L.PLASTER, Color.WHITE, 3)
	_frame(m, w, h, zf, 0.08, 0.08)
	m.cbox(Vector3(0, h * 0.5, zf), Vector3(0.07, h, 0.08), 63 - 8)
	for side: float in [-1.0, 1.0]:
		m.cbox(Vector3(side * w * 0.25, 0.45, zf + 0.01), Vector3(w * 0.5 - 0.08, 0.7, 0.05), 1 | 2 | 4 | 16)     # the lower panels
		for k in range(1, 4):
			m.cbox(Vector3(side * w * 0.25, 0.8 + (h - 0.8) * k / 4.0, zf + 0.005), Vector3(w * 0.5 - 0.08, 0.028, 0.04), 1 | 2 | 4 | 8 | 16)
	if surround > 0.0:
		_part(m, L.STONE if sur_col.v < 0.97 else L.PLASTER, sur_col, 0)
		var s := surround
		m.box(Vector3(-w * 0.5 - s, 0.0, 0.0), Vector3(-w * 0.5, h + s, 0.035), 1 | 2 | 4 | 16)
		m.box(Vector3(w * 0.5, 0.0, 0.0), Vector3(w * 0.5 + s, h + s, 0.035), 1 | 2 | 4 | 16)
		m.box(Vector3(-w * 0.5, h, 0.0), Vector3(w * 0.5, h + s, 0.035), 4 | 8 | 16)
		# a small cornice (hood) over the surround
		m.box(Vector3(-w * 0.5 - s - 0.06, h + s, -0.01), Vector3(w * 0.5 + s + 0.06, h + s + 0.09, 0.12), 1 | 2 | 4 | 8 | 16)
	if shutter > 0:
		_part(m, L.SHUTTER, Color.WHITE, 1)
		var sw := w * 0.5
		for side: float in [-1.0, 1.0]:
			var x0 := side * (w * 0.5 + surround + 0.02)
			m.box(Vector3(minf(x0, x0 + side * sw), 0.05, 0.04), Vector3(maxf(x0, x0 + side * sw), h, 0.075), 1 | 2 | 4 | 8 | 16)
	# the balcony
	var depth := 0.0
	if balcony == 1:
		depth = 0.5
		_part(m, L.STONE, sur_col if sur_col.v < 0.97 else Color(0.78, 0.76, 0.72), 0)
		m.box(Vector3(-bw * 0.5, -0.12, zf), Vector3(bw * 0.5, 0.0, depth), 63 - 32)
		m.box(Vector3(-bw * 0.5 + 0.04, -0.19, 0.0), Vector3(bw * 0.5 - 0.04, -0.12, depth - 0.05), 1 | 2 | 8 | 16)
		for side: float in [-1.0, 1.0]:        # console brackets
			m.box(Vector3(side * (bw * 0.5 - 0.15) - 0.06, -0.45, 0.0), Vector3(side * (bw * 0.5 - 0.15) + 0.06, -0.12, 0.3), 1 | 2 | 8 | 16)
		_railing(m, bw, depth, iron, 0.95, 0.1)
	elif balcony == 0:
		_railing(m, w + 0.1, 0.0, iron, 0.9, 0.03)
	elif balcony == 2:
		depth = 0.9
		_part(m, L.TIMBER, Color(0.62, 0.5, 0.4), 0)
		m.box(Vector3(-bw * 0.5, -0.1, zf), Vector3(bw * 0.5, 0.0, depth), 63 - 32)
		for k in range(4):             # joists under the deck
			var x := -bw * 0.5 + 0.1 + (bw - 0.2) * k / 3.0
			m.box(Vector3(x - 0.05, -0.24, -0.1), Vector3(x + 0.05, -0.1, depth), 1 | 2 | 8 | 16)
		_wood_rail(m, bw, depth)
	build_ms += (Time.get_ticks_usec() - t0) / 1000.0
	return _put(key, m, balcony > 0)


## A door in its opening: leaf style 0 panelled (two leaves), 1 planks; a fanlight above (glazed);
## a step; a surround; arch 0 flat, 1 round, 2 horseshoe (the leaf follows the arch).
static func door(w: float, h: float, R: float, leaf: int, fanlight: bool, surround: float, sur_col: Color, arch: int = 0, step: bool = true, frame: Color = Color(0.3, 0.3, 0.3)) -> String:
	var key := "door|%d|%d|%d|%d|%d|%d|%s|%d|%d|%s" % [roundi(w * 100), roundi(h * 100), roundi(R * 100), leaf, int(fanlight), roundi(surround * 100),
		sur_col.to_html(false), arch, int(step), frame.to_html(false)]
	if _cache.has(key): return key
	var t0 := Time.get_ticks_usec()
	var m := _begin()
	var zd := -minf(maxf(R * 0.6, 0.12), 0.3)
	var spring := h if arch == 0 else h - F.arch_top(w, arch)
	var leaf_top := spring - (0.55 if fanlight and arch == 0 else 0.0)
	_part(m, L.PLASTER, Color.WHITE, 2)
	_reveal(m, w, spring, zd - 0.01, arch)
	# the leaf (paint): door texture 0..1.2 m wide = panelled, 1.2..2.4 = planks
	_part(m, L.DOOR, Color.WHITE, 1)
	var u0 := 0.0 if leaf == 0 else 1.2
	var uw := minf(w, 1.2)
	m.quad_uv(Vector3(-w * 0.5, 0, zd), Vector3(w * 0.5, 0, zd), Vector3(w * 0.5, leaf_top, zd), Vector3(-w * 0.5, leaf_top, zd),
		Vector2(u0, 0), Vector2(u0 + uw, 0), Vector2(u0 + uw, -2.4 * leaf_top / maxf(h, 2.4) * 1.0), Vector2(u0, -2.4 * leaf_top / maxf(h, 2.4)))
	if arch > 0:
		_arch_fill(m, w, spring, zd, arch)
	if w > 1.3 and leaf == 0:        # a double door: a meeting stile
		m.cbox(Vector3(0, leaf_top * 0.5, zd + 0.02), Vector3(0.06, leaf_top, 0.04), 1 | 2 | 16)
	if fanlight and arch == 0:
		_part(m, L.GLASS, Color.WHITE, 0)
		m.quad(Vector3(-w * 0.5, leaf_top, zd + 0.01), Vector3(w * 0.5, leaf_top, zd + 0.01), Vector3(w * 0.5, h, zd + 0.01), Vector3(-w * 0.5, h, zd + 0.01))
		_part(m, L.IRON, frame, 0)
		m.cbox(Vector3(0, leaf_top + 0.03, zd + 0.03), Vector3(w, 0.07, 0.06), 4 | 8 | 16)
		for k in range(1, 4):
			m.cbox(Vector3(-w * 0.5 + w * k / 4.0, (leaf_top + h) * 0.5, zd + 0.03), Vector3(0.025, h - leaf_top, 0.03), 1 | 2 | 16)
	# door frame (jambs) in the reveal
	_part(m, L.TIMBER, Color(0.55, 0.45, 0.36), 0)
	_frame(m, w, spring, zd + 0.03, 0.06, 0.06, false)
	if step:
		_part(m, L.STONE, sur_col if sur_col.v < 0.97 else Color(0.74, 0.72, 0.68), 0)
		m.box(Vector3(-w * 0.5 - 0.15, -0.18, zd), Vector3(w * 0.5 + 0.15, 0.0, 0.32), 63 - 32 - 8)
	if surround > 0.0:
		_part(m, L.STONE if sur_col.v < 0.97 else L.PLASTER, sur_col, 0)
		var s := surround
		m.box(Vector3(-w * 0.5 - s, 0.0, 0.0), Vector3(-w * 0.5, spring + (s if arch == 0 else 0.0), 0.04), 1 | 2 | 4 | 16)
		m.box(Vector3(w * 0.5, 0.0, 0.0), Vector3(w * 0.5 + s, spring + (s if arch == 0 else 0.0), 0.04), 1 | 2 | 4 | 16)
		if arch == 0:
			m.box(Vector3(-w * 0.5, h, 0.0), Vector3(w * 0.5, h + s, 0.04), 4 | 8 | 16)
		else:
			_arch_band(m, w, spring, s, 0.04, arch)
	build_ms += (Time.get_ticks_usec() - t0) / 1000.0
	return _put(key, m)


## A shopfront filling a wide opening: stall riser, glazing in a painted timber frame, a door, the
## fascia (sign board) above. Paint = the joinery colour.
static func shopfront(w: float, h: float, R: float) -> String:
	var key := "shop|%d|%d|%d" % [roundi(w * 100), roundi(h * 100), roundi(R * 100)]
	if _cache.has(key): return key
	var m := _begin()
	var z := -minf(R * 0.5, 0.2)
	_part(m, L.PLASTER, Color.WHITE, 2)
	_reveal(m, w, h, z - 0.1, 0)
	var door_w := 1.0
	var dx := -w * 0.5 + 0.25 + door_w * 0.5
	var riser := 0.55
	var fascia := 0.55
	var top := h - fascia
	_part(m, L.GLASS, Color.WHITE, 0)
	m.quad(Vector3(dx + door_w * 0.5, riser, z - 0.02), Vector3(w * 0.5, riser, z - 0.02), Vector3(w * 0.5, top, z - 0.02), Vector3(dx + door_w * 0.5, top, z - 0.02))
	m.quad(Vector3(-w * 0.5, riser, z - 0.02), Vector3(dx - door_w * 0.5, riser, z - 0.02), Vector3(dx - door_w * 0.5, top, z - 0.02), Vector3(-w * 0.5, top, z - 0.02))
	m.quad(Vector3(dx - door_w * 0.5, 1.2, z - 0.1), Vector3(dx + door_w * 0.5, 1.2, z - 0.1), Vector3(dx + door_w * 0.5, top, z - 0.1), Vector3(dx - door_w * 0.5, top, z - 0.1))
	_part(m, L.TIMBER, Color(0.92, 0.9, 0.86), 1)
	# riser panels and the door's lower panel
	m.box(Vector3(dx + door_w * 0.5, 0.0, z - 0.02), Vector3(w * 0.5, riser, z + 0.03), 4 | 16)
	m.box(Vector3(-w * 0.5, 0.0, z - 0.02), Vector3(dx - door_w * 0.5, riser, z + 0.03), 4 | 16)
	m.box(Vector3(dx - door_w * 0.5, 0.0, z - 0.1), Vector3(dx + door_w * 0.5, 1.2, z - 0.06), 4 | 16)
	# frame: posts, transom, door frame
	_frame(m, w, top, z, 0.09, 0.1, false)
	var posts := maxi(1, roundi((w - door_w - 0.5) / 1.3))
	var x_from := dx + door_w * 0.5
	for k in range(posts + 1):
		var x := x_from + (w * 0.5 - x_from) * k / posts
		m.cbox(Vector3(x, (riser + top) * 0.5, z + 0.01), Vector3(0.07, top - riser, 0.08), 1 | 2 | 16)
	m.cbox(Vector3(dx - door_w * 0.5, top * 0.5, z + 0.01), Vector3(0.08, top, 0.08), 1 | 2 | 16)
	m.cbox(Vector3(0, top - 0.45, z + 0.01), Vector3(w, 0.06, 0.07), 4 | 8 | 16)
	m.cbox(Vector3(0, riser, z + 0.03), Vector3(w, 0.06, 0.1), 4 | 16)
	# fascia board with a moulded cornice
	m.box(Vector3(-w * 0.5, top, z), Vector3(w * 0.5, h, 0.08), 4 | 8 | 16 | 1 | 2)
	m.box(Vector3(-w * 0.5 - 0.1, h - 0.1, 0.08), Vector3(w * 0.5 + 0.1, h, 0.2), 63 - 32)
	# the sign lettering band (dark)
	_part(m, L.IRON, Color(0.85, 0.8, 0.6), 0)
	m.box(Vector3(-w * 0.35, top + 0.14, 0.08), Vector3(w * 0.35, h - 0.16, 0.095), 16)
	return _put(key, m)


## A striped canvas awning on iron arms: sloping out from the wall, a scalloped-ish valance.
static func awning(w: float, proj: float, drop: float) -> String:
	var key := "awn|%d|%d|%d" % [roundi(w * 100), roundi(proj * 100), roundi(drop * 100)]
	if _cache.has(key): return key
	var m := _begin()
	_part(m, L.CANVAS, Color.WHITE, 1)
	var a := Vector3(-w * 0.5, 0, 0.05); var b := Vector3(w * 0.5, 0, 0.05)
	var c := Vector3(w * 0.5, -drop, proj); var d := Vector3(-w * 0.5, -drop, proj)
	m.quad_uv(d, c, b, a, Vector2(0, 2), Vector2(w, 2), Vector2(w, 0), Vector2(0, 0))
	m.quad_uv(a, b, c, d, Vector2(0, 0), Vector2(w, 0), Vector2(w, 2), Vector2(0, 2))       # underside
	var vh := 0.28
	m.quad_uv(d + Vector3(0, -vh, 0), c + Vector3(0, -vh, 0), c, d, Vector2(0, 0.3), Vector2(w, 0.3), Vector2(w, 0), Vector2(0, 0))
	m.quad_uv(c + Vector3(0, -vh, 0), d + Vector3(0, -vh, 0), d, c, Vector2(0, 0.3), Vector2(w, 0.3), Vector2(w, 0), Vector2(0, 0))
	for side: float in [-1.0, 1.0]:
		var x := side * w * 0.5
		if side > 0: m.tri(Vector3(x, 0, 0.05), Vector3(x, -drop, 0.05), Vector3(x, -drop, proj))
		else: m.tri(Vector3(x, 0, 0.05), Vector3(x, -drop, proj), Vector3(x, -drop, 0.05))
	_part(m, L.IRON, Color(0.25, 0.25, 0.27), 0)
	var p0 := Vector3(0, -0.85, 0.05); var p1 := Vector3(0, -drop, proj)
	var dv := p1 - p0
	for side: float in [-1.0, 1.0]:
		var x := side * (w * 0.5 - 0.05)
		m.rbox(Vector3(x, 0, 0) + (p0 + p1) * 0.5, Vector3(0.03, 0.03, dv.length()), Basis(Vector3.RIGHT, atan2(-dv.y, dv.z)))
	return _put(key, m, true, true)


# ---------------------------------------------------------------- roofscape
## A chimney stack standing on y = 0 (placed below the roof line so it never floats).
## kind 0 rendered stack + tiled hood (Mediterranean), 1 rubble stack + slab cap on stones (alpine),
## 2 brick stack with pots, 3 whitewash stack with a little pierced cap (core / island).
static func chimney(kind: int, height: float) -> String:
	var key := "chim|%d|%d" % [kind, roundi(height * 10)]
	if _cache.has(key): return key
	var m := _begin()
	match kind:
		0:
			_part(m, L.PLASTER, Color.WHITE, 2)
			m.box(Vector3(-0.35, 0, -0.28), Vector3(0.35, height, 0.28), 63 - 8)
			_part(m, L.STONE, Color(0.9, 0.88, 0.84), 0)
			m.box(Vector3(-0.42, height, -0.35), Vector3(0.42, height + 0.08, 0.35), 63)
			_part(m, L.ROOF_TILE, Color.WHITE, 0)
			_gable_cap(m, 0.9, 0.8, height + 0.35, height + 0.6)
			_part(m, L.PLASTER, Color.WHITE, 2)
			for sx: float in [-0.25, 0.25]:
				m.box(Vector3(sx - 0.08, height + 0.08, -0.25), Vector3(sx + 0.08, height + 0.35, 0.25), 1 | 2 | 16 | 32)
		1:
			_part(m, L.RUBBLE, Color(0.95, 0.95, 0.95), 0)
			m.box(Vector3(-0.45, 0, -0.45), Vector3(0.45, height, 0.45), 63 - 8)
			_part(m, L.STONE, Color(0.55, 0.55, 0.56), 0)
			for c: Vector2 in [Vector2(-0.35, -0.35), Vector2(0.35, -0.35), Vector2(-0.35, 0.35), Vector2(0.35, 0.35)]:
				m.box(Vector3(c.x - 0.08, height, c.y - 0.08), Vector3(c.x + 0.08, height + 0.3, c.y + 0.08), 1 | 2 | 16 | 32)
			_part(m, L.SLATE, Color(0.9, 0.9, 0.92), 0)
			m.box(Vector3(-0.62, height + 0.3, -0.62), Vector3(0.62, height + 0.42, 0.62), 63)
		2:
			_part(m, L.BRICK, Color.WHITE, 0)
			m.box(Vector3(-0.35, 0, -0.3), Vector3(0.35, height, 0.3), 63 - 8)
			m.box(Vector3(-0.42, height - 0.18, -0.37), Vector3(0.42, height - 0.05, 0.37), 63)
			_part(m, L.ROOF_TILE, Color(0.9, 0.7, 0.6), 0)
			m.cylinder(Vector3(-0.15, height, 0), 0.09, 0.08, 0.35, 6)
			m.cylinder(Vector3(0.15, height, 0), 0.09, 0.08, 0.28, 6)
		_:
			_part(m, L.WHITEWASH, Color.WHITE, 2)
			m.box(Vector3(-0.3, 0, -0.3), Vector3(0.3, height, 0.3), 63 - 8)
			m.box(Vector3(-0.38, height, -0.38), Vector3(0.38, height + 0.08, 0.38), 63)
			for c: Vector2 in [Vector2(-0.28, -0.28), Vector2(0.28, -0.28), Vector2(-0.28, 0.28), Vector2(0.28, 0.28)]:
				m.box(Vector3(c.x - 0.08, height + 0.08, c.y - 0.08), Vector3(c.x + 0.08, height + 0.36, c.y + 0.08), 1 | 2 | 16 | 32)
			_part(m, L.ROOF_TILE, Color.WHITE, 0)
			_gable_cap(m, 0.9, 0.9, height + 0.36, height + 0.56)
	return _put(key, m, true, true)


## A dormer on a pitched roof: its front wall (host plaster), a small window, a tiled gable roof.
## Frame: x across, y up from the roof's eave-side base, z out (the front); it runs back `depth`
## into the roof so its sides always meet the slope.
static func dormer(w: float, h: float, depth: float, frame: Color) -> String:
	var key := "dorm|%d|%d|%d|%s" % [roundi(w * 100), roundi(h * 100), roundi(depth * 100), frame.to_html(false)]
	if _cache.has(key): return key
	var m := _begin()
	_part(m, L.PLASTER, Color.WHITE, 2)
	var hw := w * 0.5
	m.box(Vector3(-hw, 0, -depth), Vector3(-hw + 0.18, h, 0), 2 | 16)
	m.box(Vector3(hw - 0.18, 0, -depth), Vector3(hw, h, 0), 1 | 16)
	m.box(Vector3(-hw + 0.18, h - 0.22, -0.2), Vector3(hw - 0.18, h, 0), 16 | 8)
	m.box(Vector3(-hw + 0.18, 0, -0.2), Vector3(hw - 0.18, 0.2, 0), 16 | 4)
	var gh := w * 0.42
	m.tri(Vector3(-hw, h, 0), Vector3(hw, h, 0), Vector3(0, h + gh, 0))
	_part(m, L.GLASS, Color.WHITE, 0)
	m.quad(Vector3(-hw + 0.18, 0.2, -0.16), Vector3(hw - 0.18, 0.2, -0.16), Vector3(hw - 0.18, h - 0.22, -0.16), Vector3(-hw + 0.18, h - 0.22, -0.16))
	_part(m, L.PLASTER, frame, 0)
	_frame(m, w - 0.36, h - 0.42, -0.14, 0.05, 0.05)
	m.cbox(Vector3(0, h * 0.5, -0.14), Vector3(0.04, h - 0.42, 0.05), 16)
	_part(m, L.ROOF_TILE, Color.WHITE, 0)
	var o := 0.18
	var ridge := Vector3(0, h + gh + 0.12, 0.18)
	for side: float in [-1.0, 1.0]:
		var e0 := Vector3(side * (hw + o), h - 0.05, 0.18); var e1 := Vector3(side * (hw + o), h - 0.05, -depth)
		var r1 := Vector3(0, h + gh + 0.12, -depth)
		if side > 0: m.quad(e0, e1, r1, ridge)
		else: m.quad(e1, e0, ridge, r1)
	return _put(key, m, true)


## Palm-trunk beam end sticking out of a wall (the desert town's floor joists).
static func beam() -> String:
	var key := "beam"
	if _cache.has(key): return key
	var m := _begin()
	_part(m, L.TIMBER, Color(0.6, 0.5, 0.4), 0)
	var keep := m.xf
	m.xf = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO)
	m.cylinder(Vector3(0, -0.2, 0), 0.07, 0.065, 0.62, 8, true)
	m.xf = keep
	return _put(key, m, true, true)


## A crenel merlon on a wall top: kind 0 stepped (desert), 1 square (plains), 2 swallow-tail.
static func merlon(kind: int, w: float, h: float, t: float) -> String:
	var key := "merl|%d|%d|%d|%d" % [kind, roundi(w * 100), roundi(h * 100), roundi(t * 100)]
	if _cache.has(key): return key
	var m := _begin()
	_part(m, L.ADOBE, Color.WHITE, 2)
	match kind:
		0:
			m.box(Vector3(-w * 0.5, 0, -t * 0.5), Vector3(w * 0.5, h * 0.6, t * 0.5), 63 - 8)
			m.box(Vector3(-w * 0.3, h * 0.6, -t * 0.5), Vector3(w * 0.3, h * 0.85, t * 0.5), 63 - 8)
			m.box(Vector3(-w * 0.12, h * 0.85, -t * 0.5), Vector3(w * 0.12, h, t * 0.5), 63 - 8)
		2:
			m.box(Vector3(-w * 0.5, 0, -t * 0.5), Vector3(w * 0.5, h * 0.7, t * 0.5), 63 - 8)
			m.box(Vector3(-w * 0.5, h * 0.7, -t * 0.5), Vector3(-w * 0.2, h, t * 0.5), 63 - 8)
			m.box(Vector3(w * 0.2, h * 0.7, -t * 0.5), Vector3(w * 0.5, h, t * 0.5), 63 - 8)
		_:
			m.box(Vector3(-w * 0.5, 0, -t * 0.5), Vector3(w * 0.5, h, t * 0.5), 63 - 8)
	return _put(key, m, true, true)


## A small whitewashed dome on a drum (desert and island roofs, qubba).
static func small_dome(r: float) -> String:
	var key := "sdome|%d" % roundi(r * 100)
	if _cache.has(key): return key
	var m := _begin()
	_part(m, L.WHITEWASH, Color.WHITE, 2)
	m.box(Vector3(-r - 0.15, 0, -r - 0.15), Vector3(r + 0.15, 0.6, r + 0.15), 63 - 8)
	m.cylinder(Vector3(0, 0.6, 0), r, r, 0.3, 12, false)
	m.dome(Vector3(0, 0.9, 0), r, 0.95, 12, 4)
	return _put(key, m, true, true)


## Terracotta pot with a shrub (steps, terraces, sills).
static func pot() -> String:
	var key := "pot"
	if _cache.has(key): return key
	var m := _begin()
	_part(m, L.ROOF_TILE, Color(1.0, 0.85, 0.75), 0)
	m.cylinder(Vector3(0, 0, 0), 0.16, 0.22, 0.34, 8, false)
	_part(m, L.TIMBER, Color(1, 1, 1), 1)
	m.dome(Vector3(0, 0.3, 0), 0.3, 1.2, 7, 3)
	m.dome(Vector3(0.12, 0.45, 0.05), 0.2, 1.0, 6, 2)
	return _put(key, m, true, true)


## Plant colours for pots (instance paint): greens, a bougainvillea, a geranium.
const PLANTS := [Color(0.5, 0.75, 0.4), Color(0.55, 0.8, 0.45), Color(1.1, 0.55, 0.95), Color(1.3, 0.45, 0.4)]


## Wall lantern on a bracket.
static func lantern() -> String:
	var key := "lantern"
	if _cache.has(key): return key
	var m := _begin()
	_part(m, L.IRON, Color(0.18, 0.18, 0.2), 0)
	m.box(Vector3(-0.02, -0.02, 0.0), Vector3(0.02, 0.02, 0.45), 63)
	m.box(Vector3(-0.12, -0.35, 0.33), Vector3(0.12, -0.3, 0.57), 63)
	m.box(Vector3(-0.14, -0.02, 0.31), Vector3(0.14, 0.03, 0.59), 63)
	_part(m, L.GLASS, Color(1.0, 0.9, 0.6), 0)
	m.box(Vector3(-0.1, -0.3, 0.35), Vector3(0.1, -0.02, 0.55), 63 - 8 - 4)
	return _put(key, m, false, true)


## A clock face (tower): stone disc, dark ring, iron hands.
static func clock(r: float) -> String:
	var key := "clock|%d" % roundi(r * 100)
	if _cache.has(key): return key
	var m := _begin()
	_part(m, L.STONE, Color(0.95, 0.94, 0.9), 0)
	var keep := m.xf
	m.xf = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO)
	m.cylinder(Vector3(0, 0, 0), r, r, 0.06, 16, true)
	_part(m, L.IRON, Color(0.12, 0.12, 0.14), 0)
	m.cylinder(Vector3(0, 0.0, 0), r + 0.08, r + 0.08, 0.04, 16, false)
	m.xf = keep
	m.rbox(Vector3(0.0, r * 0.3, 0.08), Vector3(0.05, r * 0.6, 0.02), Basis())
	m.rbox(Vector3(r * 0.2, -r * 0.1, 0.09), Vector3(0.05, r * 0.5, 0.02), Basis(Vector3.BACK, -2.0))
	for k in range(12):
		var a := TAU * k / 12.0
		m.rbox(Vector3(sin(a), cos(a), 0) * r * 0.82 + Vector3(0, 0, 0.065), Vector3(0.04, 0.12, 0.01), Basis(Vector3.BACK, -a))
	return _put(key, m)


## A bronze bell hanging in a belfry arch.
static func bell(r: float) -> String:
	var key := "bell|%d" % roundi(r * 100)
	if _cache.has(key): return key
	var m := _begin()
	_part(m, L.IRON, Color(0.55, 0.42, 0.22), 0)
	m.cylinder(Vector3(0, -r * 1.6, 0), r, r * 0.55, r * 1.3, 10, true, true)
	m.dome(Vector3(0, -r * 0.3, 0), r * 0.55, 0.6, 10, 2)
	_part(m, L.TIMBER, Color(0.4, 0.3, 0.2), 0)
	m.box(Vector3(-r * 1.4, -0.05, -0.08), Vector3(r * 1.4, 0.12, 0.08), 63)
	return _put(key, m, false, true)


## Windmill sails: four lattice arms on a hub, in the xy plane (z = forward).
static func sails(radius: float) -> String:
	var key := "sails|%d" % roundi(radius * 10)
	if _cache.has(key): return key
	var m := _begin()
	_part(m, L.TIMBER, Color(0.75, 0.66, 0.55), 0)
	var keep := m.xf
	m.xf = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO)
	m.cylinder(Vector3(0, -0.2, 0), 0.35, 0.3, 0.6, 8, true)
	m.xf = keep
	for k in range(4):
		var b := Basis(Vector3.BACK, TAU * k / 4.0 + 0.3)
		m.rbox(b * Vector3(0, radius * 0.5, 0.3), Vector3(0.14, radius, 0.14), b)
		# lattice: rungs and two rails
		for r in range(1, 9):
			var y := radius * (0.2 + 0.8 * r / 8.0)
			m.rbox(b * Vector3(0.45, y, 0.33), Vector3(0.9, 0.05, 0.05), b)
		m.rbox(b * Vector3(0.9, radius * 0.6, 0.33), Vector3(0.05, radius * 0.8, 0.05), b)
		_part(m, L.CANVAS, Color(0.95, 0.93, 0.88), 0)
		m.rbox(b * Vector3(0.45, radius * 0.6, 0.36), Vector3(0.85, radius * 0.78, 0.01), b, 16 | 32)
		_part(m, L.TIMBER, Color(0.75, 0.66, 0.55), 0)
	return _put(key, m, true)


## A staddle stone (mushroom) that granaries stand on.
static func staddle(h: float) -> String:
	var key := "stad|%d" % roundi(h * 100)
	if _cache.has(key): return key
	var m := _begin()
	_part(m, L.STONE, Color(0.8, 0.76, 0.66), 0)
	m.cylinder(Vector3(0, 0, 0), 0.2, 0.12, h - 0.12, 7, false)
	m.cylinder(Vector3(0, h - 0.12, 0), 0.34, 0.3, 0.12, 9, true, true)
	return _put(key, m, true)


# ---------------------------------------------------------------- helpers
## The reveal of the opening a module fills: two jambs and a soffit (or the arch's intrados) from
## the wall face back to depth z, in the host wall's material (flag 2).
static func _reveal(m: ArchMesh, w: float, sp: float, z: float, arch: int) -> void:
	var hw := w * 0.5
	m.quad(Vector3(-hw, 0, 0), Vector3(-hw, 0, z), Vector3(-hw, sp, z), Vector3(-hw, sp, 0))
	m.quad(Vector3(hw, 0, z), Vector3(hw, 0, 0), Vector3(hw, sp, 0), Vector3(hw, sp, z))
	if arch == 0:
		m.quad(Vector3(-hw, sp, z), Vector3(hw, sp, z), Vector3(hw, sp, 0), Vector3(-hw, sp, 0))
		return
	var pts := arch_points(w, sp, arch, 10)
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]; var b: Vector2 = pts[i + 1]
		m.quad(Vector3(a.x, a.y, 0), Vector3(b.x, b.y, 0), Vector3(b.x, b.y, z), Vector3(a.x, a.y, z))


## A rectangular frame of four bars round an opening w x h at depth z.
static func _frame(m: ArchMesh, w: float, h: float, z: float, fw: float, fd: float, bottom: bool = true) -> void:
	m.box(Vector3(-w * 0.5, 0, z - fd * 0.5), Vector3(-w * 0.5 + fw, h, z + fd * 0.5), 1 | 16)
	m.box(Vector3(w * 0.5 - fw, 0, z - fd * 0.5), Vector3(w * 0.5, h, z + fd * 0.5), 2 | 16)
	m.box(Vector3(-w * 0.5, h - fw, z - fd * 0.5), Vector3(w * 0.5, h, z + fd * 0.5), 8 | 16)
	if bottom: m.box(Vector3(-w * 0.5, 0, z - fd * 0.5), Vector3(w * 0.5, fw, z + fd * 0.5), 4 | 16)


## Fill an arch head (above `spring`) as a flat fan at depth z. arch 1 round, 2 horseshoe.
static func _arch_fill(m: ArchMesh, w: float, spring: float, z: float, arch: int = 1) -> void:
	var pts := arch_points(w, spring, arch, 10)
	var c := Vector3(0, spring, z)
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]; var b: Vector2 = pts[i + 1]
		m.tri(c, Vector3(a.x, a.y, z), Vector3(b.x, b.y, z))


## A band following the arch (archivolt) of width s standing proud by d.
static func _arch_band(m: ArchMesh, w: float, spring: float, s: float, d: float, arch: int = 1) -> void:
	var inner := arch_points(w, spring, arch, 10)
	var outer := arch_points(w + s * 2.0, spring, arch, 10)
	for i in range(inner.size() - 1):
		var a: Vector2 = inner[i]; var b: Vector2 = inner[i + 1]
		var c: Vector2 = outer[i + 1]; var e: Vector2 = outer[i]
		m.quad(Vector3(e.x, e.y, d), Vector3(a.x, a.y, d), Vector3(b.x, b.y, d), Vector3(c.x, c.y, d))


## Points of an arch head from the right springing point round to the left (x, y), for an opening
## of width w springing at `spring`. arch 1 = semicircle, 2 = horseshoe (continues below the
## springing line to 1.15 x the radius), 3 = segmental (rise w/5).
static func arch_points(w: float, spring: float, arch: int, seg: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var r := w * 0.5
	match arch:
		2:
			var R := r / cos(deg_to_rad(28.0))
			var cy := spring + R * sin(deg_to_rad(28.0))
			for i in range(seg + 1):
				var a := deg_to_rad(-28.0) + (PI + deg_to_rad(56.0)) * i / seg
				out.append(Vector2(cos(a) * R, cy + sin(a) * R))
		3:
			var rise := w * 0.2
			var R := (r * r + rise * rise) / (2.0 * rise)
			var cy := spring + rise - R
			var a0 := asin(clampf(r / R, -1, 1))
			for i in range(seg + 1):
				var a := PI * 0.5 - a0 + 2.0 * a0 * i / seg
				out.append(Vector2(cos(a) * R, cy + sin(a) * R))
		_:
			for i in range(seg + 1):
				var a := PI * i / seg
				out.append(Vector2(cos(a) * r, spring + sin(a) * r))
	return out


## Small tiled gable cap (chimney hoods).
static func _gable_cap(m: ArchMesh, w: float, d: float, y0: float, y1: float) -> void:
	var hw := w * 0.5; var hd := d * 0.5
	m.quad(Vector3(-hw, y0, hd), Vector3(hw, y0, hd), Vector3(hw, y1, 0), Vector3(-hw, y1, 0))
	m.quad(Vector3(hw, y0, -hd), Vector3(-hw, y0, -hd), Vector3(-hw, y1, 0), Vector3(hw, y1, 0))
	m.tri(Vector3(hw, y0, hd), Vector3(hw, y0, -hd), Vector3(hw, y1, 0))
	m.tri(Vector3(-hw, y0, -hd), Vector3(-hw, y0, hd), Vector3(-hw, y1, 0))


## A painted iron railing (balconies): posts, top and bottom rails, balusters, returns.
static func _railing(m: ArchMesh, w: float, depth: float, iron: Color, h: float, z0: float) -> void:
	_part(m, L.IRON, iron, 0)
	var zf := depth - 0.03 if depth > 0.0 else z0
	m.box(Vector3(-w * 0.5, h - 0.04, zf - 0.025), Vector3(w * 0.5, h, zf + 0.025), 63)
	m.box(Vector3(-w * 0.5, 0.06, zf - 0.015), Vector3(w * 0.5, 0.1, zf + 0.015), 63 - 4 - 8)
	var n := maxi(3, roundi(w / 0.12))
	for k in range(n + 1):
		var x := -w * 0.5 + w * k / n
		m.box(Vector3(x - 0.01, 0.0, zf - 0.01), Vector3(x + 0.01, h - 0.04, zf + 0.01), 1 | 2 | 16 | 32)
	if depth > 0.2:
		for side: float in [-1.0, 1.0]:
			var x := side * (w * 0.5 - 0.02)
			m.box(Vector3(x - 0.02, h - 0.04, 0.0), Vector3(x + 0.02, h, zf), 63)
			var nd := maxi(2, roundi(depth / 0.12))
			for k in range(1, nd):
				var z := zf * k / nd
				m.box(Vector3(x - 0.01, 0.0, z - 0.01), Vector3(x + 0.01, h - 0.04, z + 0.01), 1 | 2 | 16 | 32)
	# a scroll bulge: two curved bars at the corners read as wrought iron from a distance
	m.box(Vector3(-w * 0.5, h * 0.5 - 0.015, zf - 0.012), Vector3(w * 0.5, h * 0.5 + 0.015, zf + 0.012), 4 | 8 | 16 | 32)


## A wooden balcony rail: flat boards, posts and a top rail (alpine).
static func _wood_rail(m: ArchMesh, w: float, depth: float) -> void:
	_part(m, L.TIMBER, Color(0.66, 0.54, 0.44), 0)
	var h := 1.0
	var zf := depth - 0.05
	m.box(Vector3(-w * 0.5, h - 0.08, zf - 0.05), Vector3(w * 0.5, h, zf + 0.05), 63)
	var n := maxi(3, roundi(w / 0.22))
	for k in range(n):
		var x := -w * 0.5 + (k + 0.5) * w / n
		m.box(Vector3(x - 0.045, 0.1, zf - 0.015), Vector3(x + 0.045, h - 0.08, zf + 0.015), 1 | 2 | 16 | 32)
	m.box(Vector3(-w * 0.5, 0.0, zf - 0.03), Vector3(w * 0.5, 0.1, zf + 0.03), 63)
	for side: float in [-1.0, 1.0]:
		var x := side * (w * 0.5 - 0.05)
		m.box(Vector3(x - 0.05, 0.0, 0.0), Vector3(x + 0.05, h, zf), 63 - 8)
