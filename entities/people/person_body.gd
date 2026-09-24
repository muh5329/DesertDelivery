class_name PersonBody
extends RefCounted
## Body and clothing of a townsperson, authored in the rest pose into a CharacterMesh.
##
## The outermost layer is the only one generated: a tucked shirt IS the torso surface, a
## trouser leg IS the leg. Open garments (jackets, coats, waistcoats) are a second, larger
## shell with a smooth front opening, skinned with the same weights as the layer under
## them, so they move together and cannot interpenetrate. Skirts, dresses, robes and coat
## tails follow the legs (CharacterMesh.Rig.SKIRT) so a stride pushes the hem instead of
## a knee pushing through it.

const M = preload("res://entities/people/character_mesh.gd")
## The neckline sits here; open necklines cut [depth, half-angle] below it at the front.
const NECKLINE_Y := 1.506
const NECKLINES := {"v": [.095, .6], "open": [.082, .5], "scoop": [.07, 1.05], "collar": [.032, .3]}

var m: CharacterMesh
var look: Dictionary
var near := true
## Body measurements derived from the look (metres).
var p: Dictionary = {}
var paint: Dictionary = {}


func _init(mesh: CharacterMesh, p_look: Dictionary, detail_near: bool) -> void:
	m = mesh; look = p_look; near = detail_near
	_measure()
	_paints()


func build() -> void:
	_torso_layer()
	_outer_layer()
	_skirt()
	_neck()
	for side: float in [-1.0, 1.0]:
		_arm(side)
		_hand(side)
		_leg(side)
		_foot(side)
	_belt()
	_apron()
	_neckerchief()
	_satchel()


# ------------------------------------------------------------------ measurements
func _measure() -> void:
	var f: bool = look.sex == "f"
	var w: float = look.build
	var heavy := maxf(w, 0.0)
	var elder: bool = int(look.age) >= 62
	p.lf = 1.0 + .16 * w                      # limb girth
	p.hip = Vector3(.172 + .020 * w, .098 + .022 * w, .100 + .020 * w) if not f else Vector3(.188 + .022 * w, .100 + .022 * w, .116 + .022 * w)
	p.waist = Vector3(.132 + .030 * w, .092 + .012 * w + .050 * heavy, .086 + .010 * w) if not f else Vector3(.116 + .030 * w, .084 + .010 * w + .042 * heavy, .080 + .010 * w)
	p.chest = Vector3(.146 + .010 * w, .104 + .012 * w + .01 * heavy, .096 + .008 * w) if not f else Vector3(.134 + .010 * w, .094 + .010 * w, .090 + .008 * w)
	p.shoulder = (.152 if not f else .142) + .010 * heavy
	p.bust = (.022 + .014 * (w + 1.0) * .5) if f else 0.0
	p.belly = .012 + .038 * heavy + (.012 if elder and not f else 0.0)
	p.glute = .010 + .006 * w + (.008 if f else 0.0)
	p.blade = .004 + (.012 if elder else 0.0)
	p.neck = (.056 if not f else .047) * (1.0 + .12 * w)
	p.foot = 1.0 if not f else .92
	p.waist_y = 1.03 if not f else 1.06


func _paints() -> void:
	var skin: Color = look.skin
	paint.skin = m.add_paint(skin, M.Mat.SKIN)
	paint.skin_dark = m.add_paint(skin.darkened(.12), M.Mat.SKIN)
	paint.top = m.add_paint(look.top_color, look.top_fabric, look.top_pattern, look.top_color2)
	paint.top_edge = m.add_paint(Color(look.top_color).darkened(.18), look.top_fabric)
	paint.under = m.add_paint(look.under_color, look.under_fabric, look.under_pattern, look.under_color2)
	paint.under_edge = m.add_paint(Color(look.under_color).darkened(.15), look.under_fabric)
	paint.bottom = m.add_paint(look.bottom_color, look.bottom_fabric, look.bottom_pattern, look.bottom_color2)
	paint.bottom_edge = m.add_paint(Color(look.bottom_color).darkened(.2), look.bottom_fabric)
	paint.shoe = m.add_paint(look.shoe_color, M.Mat.LEATHER)
	paint.sole = m.add_paint(Color(look.shoe_color).darkened(.62), M.Mat.RUBBER)
	paint.belt = m.add_paint(look.belt_color, M.Mat.LEATHER)
	paint.metal = m.add_paint(Color("b59b62"), M.Mat.METAL)
	paint.apron = m.add_paint(look.apron_color, M.Mat.COTTON if look.apron != "leather" else M.Mat.LEATHER, look.get("apron_pattern", 0), Color(look.apron_color).darkened(.25))
	paint.sock = m.add_paint(look.get("sock_color", Color("d8d0c0")), M.Mat.KNIT, M.Pattern.RIB)
	paint.scarf = m.add_paint(look.get("scarf_color", Color("b04a3a")), M.Mat.COTTON, look.get("scarf_pattern", 0), Color(look.get("scarf_color", Color("b04a3a"))).lightened(.45))
	paint.bag = m.add_paint(look.get("satchel_color", Color("6b4a30")), M.Mat.LEATHER)


## Garment that forms the torso surface (under a vest, jacket or coat it is the shirt).
func _inner_top() -> String:
	var top: String = look.top
	if top in ["vest", "jacket", "coat", "overalls"]: return String(look.under)
	return top


func _inner_paint() -> int:
	return paint.under if look.top in ["vest", "jacket", "coat", "overalls"] else paint.top


func _tucked(kind: String) -> bool:
	return kind in ["shirt", "blouse"] and look.bottom in ["trousers", "shorts", "skirt"]


# ------------------------------------------------------------------ torso
var _section_cache: Dictionary = {}

func _torso_sections(ease: float, bottom: float = .745) -> Array:
	var key := Vector2(ease, bottom)
	if _section_cache.has(key):
		var cached: Array = _section_cache[key]
		var copy: Array = []
		for s in cached: copy.append(s.duplicate())
		return copy
	var made := _make_torso_sections(ease, bottom)
	_section_cache[key] = made
	return _torso_sections(ease, bottom)


func _make_torso_sections(ease: float, bottom: float) -> Array:
	var hip: Vector3 = p.hip; var waist: Vector3 = p.waist; var chest: Vector3 = p.chest
	var wy: float = p.waist_y
	var rows: Array = [
		[.745, Vector3(0, 0, 0), 2.2, {}],
		[.77, Vector3(hip.x * .72, .066, .076), 2.2, {}],
		[.82, Vector3(hip.x * .985, hip.y * .95, hip.z * .96), 2.3, {"glute": p.glute * .7}],
		[.88, hip, 2.3, {"glute": p.glute}],
		[lerpf(.88, wy, .5), hip.lerp(waist, .5), 2.25, {"glute": p.glute * .3, "belly": p.belly * .45}],
		[wy, waist, 2.2, {"belly": p.belly}],
		[lerpf(wy, 1.27, .4), waist.lerp(chest, .38), 2.3, {"belly": p.belly * .55, "bust": p.bust * .15}],
		[lerpf(wy, 1.27, .78), waist.lerp(chest, .8), 2.4, {"bust": p.bust * .7, "blade": p.blade * .5}],
		[1.27, chest, 2.5, {"bust": p.bust, "blade": p.blade}],
		[1.345, Vector3(chest.x * .985, chest.y * .95, chest.z * .98), 2.5, {"bust": p.bust * .3, "blade": p.blade}],
		[1.40, Vector3(p.shoulder, chest.y * .84, chest.z * .94), 2.6, {"blade": p.blade * .6}],
		[1.445, Vector3(p.shoulder * .955, chest.y * .76, chest.z * .88), 2.5, {"blade": p.blade * .3}],
		[1.478, Vector3(p.shoulder * .88, .07, .076), 2.4, {}],
		[1.508, Vector3(.104, .06, .064), 2.2, {}],
		[1.53, Vector3(p.neck + .01, p.neck + .004, p.neck + .006), 2.0, {}],
		# the top tucks inside the neck, so no torso edge shows round it
		[1.552, Vector3(p.neck * .92, p.neck * .8, p.neck * .9), 2.0, {}],
	]
	var out: Array = []
	for row in rows:
		var y: float = row[0]
		if y < bottom - .001: continue
		var r: Vector3 = row[1]
		var e := ease if y > .76 else ease * .5
		var s := {"y": y, "rx": r.x + e if r.x > 0.0 else 0.0, "rf": r.y + e if r.y > 0.0 else 0.0,
			"rb": r.z + e if r.z > 0.0 else 0.0, "n": row[2], "paint": 0}
		for key in row[3]: s[key] = float(row[3][key])
		out.append(s)
	return out


func _torso_layer() -> void:
	var inner := _inner_top()
	var top_paint := _inner_paint()
	var tucked := _tucked(inner)
	var hem_y := .86
	if inner in ["sweater", "tshirt", "tunic"]: hem_y = .84
	if inner == "blouse" and not tucked: hem_y = .9
	if look.top in ["dress", "robe"]: hem_y = -1.0
	var waist_y: float = p.waist_y - .05
	var neck: String = look.neck
	var bib: bool = look.top == "overalls"
	var bottom_paint: int = paint.bottom
	var sections := _torso_sections(.004 if inner in ["tshirt", "shirt", "blouse", "dress"] else .012)
	# garment edges are real steps: the trouser waistband over a tucked shirt, the hem of
	# an untucked top over the trousers
	if hem_y > 0.0:
		if tucked:
			_insert_step(sections, waist_y, .0015, -.0005, 0.0, .006)
		else:
			_insert_step(sections, hem_y, .0005, -.0005, .007 if inner != "sweater" else .01, 0.0)
	if neck != "turtle":
		_insert_step(sections, NECKLINE_Y, .0005, -.0005, 0.0, .0045)
	var skin: int = paint.skin
	var skirt_below: bool = look.bottom == "skirt" or look.top in ["dress", "robe"]
	var fn := func(th: float, s: Dictionary, _pid: int) -> int:
		var y: float = s.y
		var a := absf(th)
		# neckline: the skin above it belongs to the neck
		var neck_y := NECKLINE_Y
		if not near:
			# the far mesh has no neckline patch: paint the opening instead
			var cut: Array = NECKLINES.get(neck, [0.0, 0.0])
			if a < float(cut[1]): neck_y -= float(cut[0]) * (1.0 - a / float(cut[1]))
		if neck == "turtle": neck_y = 1.54
		if y > neck_y: return skin
		if bib:
			var strap := absf(a - .36) < .075 or absf(a - (PI - .5)) < .075
			if (a < .62 and y < 1.31) or (strap and y < 1.49) or y < 1.0: return bottom_paint
			return top_paint
		if hem_y > 0.0:
			if tucked and y < waist_y: return bottom_paint
			if not tucked and y < hem_y: return bottom_paint if not skirt_below else top_paint
		return top_paint
	m.loft(sections, 36 if near else 12, 3 if near else 1, M.Rig.TORSO, {"warp": .62 if near else 1.0, "paint_fn": fn, "uv_y": true})
	if near and NECKLINES.has(neck): _neckline(neck, top_paint)


## V, open, scoop and buttoned-collar necklines: a skin patch with exact edges over the
## torso layer, trimmed with a fabric edge, so the opening is a clean line at any angle.
func _neckline(neck: String, fabric: int) -> void:
	var cut: Array = NECKLINES[neck]
	var depth: float = cut[0]; var half: float = cut[1]
	var bottom := NECKLINE_Y - depth
	var ease := _inner_ease()
	var rows := 8; var cols := 9
	var pos := PackedVector3Array(); pos.resize(rows * cols)
	var pnt := PackedInt32Array(); pnt.resize(rows * cols)
	var trim_l := PackedVector3Array(); var trim_r := PackedVector3Array()
	for i in rows:
		var v := float(i) / float(rows - 1)
		var y := lerpf(NECKLINE_Y + .003, bottom, v)
		var g := _neckline_half(neck, y, depth, half)
		for j in cols:
			var th := lerpf(-g, g, float(j) / float(cols - 1))
			pos[i * cols + j] = torso_point(th, y, ease, .0012)
			pnt[i * cols + j] = paint.skin
		trim_l.append(torso_point(-g, y, ease, .002)); trim_r.append(torso_point(g, y, ease, .002))
	m.grid(rows, cols, pos, pnt, false, M.Rig.TORSO)
	var trim := PackedVector3Array(); var rad := PackedFloat32Array()
	for k in trim_l.size(): trim.append(trim_l[k])
	for k in range(trim_r.size() - 2, -1, -1): trim.append(trim_r[k])
	for k in trim.size(): rad.append(.0042)
	m.tube(trim, rad, 5, fabric, M.Rig.TORSO, .6, Vector3.FORWARD)


func _neckline_half(neck: String, y: float, depth: float, half: float) -> float:
	var t := clampf((y - (NECKLINE_Y - depth)) / depth, 0.0, 1.0)
	if neck == "scoop": return half * sqrt(t)
	return half * t


func _inner_ease() -> float:
	return .004 if _inner_top() in ["tshirt", "shirt", "blouse", "dress"] else .012


## A point on a torso layer (garment ease) at azimuth th and height y, pushed out by `lift`.
func torso_point(th: float, y: float, ease: float, lift: float = 0.0) -> Vector3:
	var r := _torso_radius(th, y, ease) + lift
	return Vector3(sin(th) * r, y, -cos(th) * r)


## Two hard rows at height y (upper at y+up, lower at y+down) with extra girth, making a
## visible garment edge.
func _insert_step(sections: Array, y: float, up: float, down: float, grow_up: float, grow_down: float) -> void:
	var at := -1
	for k in sections.size() - 1:
		if sections[k].y <= y and sections[k + 1].y > y: at = k
	if at < 0: return
	var a: Dictionary = sections[at]; var b: Dictionary = sections[at + 1]
	var rows: Array = []
	for pair in [[y + down, grow_down], [y + up, grow_up]]:
		var t: float = (float(pair[0]) - a.y) / (b.y - a.y)
		var s := a.duplicate()
		for key in a:
			if (a[key] is float) and b.has(key): s[key] = lerpf(a[key], b[key], t)
		s.y = pair[0]
		for key in ["rx", "rf", "rb"]: s[key] = float(s[key]) + float(pair[1])
		s["hard"] = true
		rows.append(s)
	sections.insert(at + 1, rows[1])
	sections.insert(at + 1, rows[0])


## Radial distance of the outermost torso layer from the body axis at azimuth th (0 = front,
## +X positive) and model height y. Hair, straps and bags use it to stay clear.
func outer_radius(th: float, y: float) -> float:
	if y > 1.532: return p.neck + .02
	var ease := .012
	match String(look.top):
		"vest": ease = .014
		"jacket": ease = .022
		"coat": ease = .026
	return _torso_radius(th, y, ease)


func _torso_radius(th: float, y: float, ease: float) -> float:
	if not _section_cache.has(Vector2(ease, .745)): _torso_sections(ease)
	var sections: Array = _section_cache[Vector2(ease, .745)]
	for k in sections.size() - 1:
		var a: Dictionary = sections[k]; var b: Dictionary = sections[k + 1]
		if y < a.y or y > b.y: continue
		var t: float = (y - a.y) / maxf(b.y - a.y, .0001)
		var s := {}
		for key in a:
			if a[key] is float: s[key] = lerpf(a[key], float(b.get(key, 0.0)), t)
		for key in b:
			if not s.has(key) and b[key] is float: s[key] = float(b[key]) * t
		var e := 2.0 / float(s.get("n", 2.0))
		var sn := sin(th); var cs := cos(th)
		var x := pow(absf(sn), e) * float(s.rx)
		var z := pow(absf(cs), e) * (float(s.rf) if cs > 0.0 else float(s.rb))
		return Vector2(x, z).length() + m._bumps(s, th)
	return p.neck + ease


## Waistcoat, jacket or coat: a larger open-fronted shell over the torso layer.
func _outer_layer() -> void:
	var top: String = look.top
	if not top in ["vest", "jacket", "coat"]: return
	var ease: float = {"vest": .014, "jacket": .022, "coat": .026}[top]
	var bottom: float = {"vest": .9, "jacket": .77, "coat": .8}[top]
	var sections: Array = []
	for s in _torso_sections(ease):
		if s.y < bottom or s.y > 1.51: continue
		if s.y <= .9 and top != "vest":
			s.rx += .012; s.rf += .01; s.rb += .012     # the skirt of the jacket hangs clear of the hips
		sections.append(s)
	var first: Dictionary = sections[0].duplicate()
	first.y = bottom - .001
	var open := func(y: float) -> float:
		match top:
			"vest": return .03 if y < 1.16 else lerpf(.03, .62, clampf((y - 1.16) / .33, 0.0, 1.0))
			"jacket": return .10 if y < 1.12 else lerpf(.10, .70, clampf((y - 1.12) / .36, 0.0, 1.0))
		return .16 if y < 1.1 else lerpf(.16, .72, clampf((y - 1.1) / .38, 0.0, 1.0))
	_open_loft(sections, 36 if near else 12, 3 if near else 1, M.Rig.TORSO, paint.top, open)


## A vertical loft whose columns span only the back and sides: the front opening's
## half-angle is open_fn(y), so its edges are smooth lines rather than a staircase.
func _open_loft(sections: Array, cols: int, sub: int, scheme: int, pid: int, open_fn: Callable) -> void:
	var rows_data: Array = m._interpolate(sections, sub)
	var rows := rows_data.size()
	var pos := PackedVector3Array(); pos.resize(rows * cols)
	var pnt := PackedInt32Array(); pnt.resize(rows * cols)
	for i in rows:
		var s: Dictionary = rows_data[i]
		var e := 2.0 / float(s.get("n", 2.0))
		var g: float = open_fn.call(float(s.y))
		for j in cols:
			var th := wrapf(g + (TAU - 2.0 * g) * float(j) / float(cols - 1), -PI, PI)
			var sn := sin(th); var cs := cos(th)
			var x := signf(sn) * pow(absf(sn), e) * float(s.rx)
			var z := -signf(cs) * pow(absf(cs), e) * (float(s.rf) if cs > 0.0 else float(s.rb))
			var bump := m._bumps(s, th)
			if bump != 0.0:
				var radial := Vector2(x, z).normalized() * bump
				x += radial.x; z += radial.y
			pos[i * cols + j] = Vector3(float(s.get("cx", 0.0)) + x, float(s.y), float(s.get("cz", 0.0)) + z)
			pnt[i * cols + j] = pid
	m.grid(rows, cols, pos, pnt, false, scheme, {"two_sided": true, "uv_y": true, "inset": .003,
		"flip": float(rows_data[0].y) < float(rows_data[-1].y)})


var _skirt_rows: Array = []

## Front depth of the skirt (or coat tails) at height y, or 0 without one.
func _skirt_front(y: float) -> float:
	for k in _skirt_rows.size() - 1:
		var a: Dictionary = _skirt_rows[k]; var b: Dictionary = _skirt_rows[k + 1]
		if y <= float(a.y) and y >= float(b.y):
			return lerpf(float(a.rf), float(b.rf), (float(a.y) - y) / maxf(float(a.y) - float(b.y), .0001)) + float(a.get("glute", 0.0)) * 0.0
	return 0.0


## Skirts, dresses, robes, long tunics and coat tails.
func _skirt() -> void:
	var top: String = look.top
	var kind := ""
	if look.bottom == "skirt": kind = "skirt"
	elif top in ["dress", "robe"]: kind = top
	elif top == "coat": kind = "coat"
	elif top == "tunic" and look.hem < .7: kind = "tunic"
	if kind == "": return
	var hem: float = look.hem
	var top_y: float = float(p.waist_y) - .02 if kind == "skirt" else .96
	if kind == "coat": top_y = .84
	if kind == "tunic": top_y = .9
	m.skirt_hem = hem
	var hip: Vector3 = p.hip
	var ease := .016 if kind != "coat" else .036
	var flare: float = {"skirt": .07, "dress": .08, "robe": .06, "coat": .06, "tunic": .05}[kind]
	var sections: Array = []
	var knee_clear := .205
	var steps := 7 if near else 3
	for k in steps + 1:
		var t := float(k) / float(steps)
		var y := lerpf(top_y, hem, t)
		var at_hip := smoothstep(top_y, .86, y)
		var base := Vector3(p.waist.x, p.waist.y, p.waist.z).lerp(hip, at_hip) if kind == "skirt" else hip
		var spread := flare * pow(t, 1.3)
		# below the hip the hem must clear both swinging thighs
		var clear := smoothstep(.86, .55, y) * knee_clear
		var s := {"y": y, "rx": maxf(base.x + ease + spread, clear), "rf": maxf(base.y + ease + spread * .9, clear * .78),
			"rb": maxf(base.z + ease + spread, clear * .78), "n": 2.15, "paint": paint.top if kind != "skirt" else paint.bottom}
		if kind != "coat" and y > .84: s["glute"] = p.glute * .6
		sections.append(s)
	if kind == "coat":
		_skirt_rows = sections.duplicate()
		var open := func(y: float) -> float: return .16 + (.84 - y) * .35
		_open_loft(sections, 30 if near else 10, 1, M.Rig.SKIRT, paint.top, open)
	else:
		# a turned hem: the last row folds up inside, so the skirt reads as cloth, not a tube
		var last: Dictionary = sections[-1].duplicate()
		last.y = hem + .012; last.rx -= .012; last.rf -= .012; last.rb -= .012
		last.paint = paint.top_edge if kind != "skirt" else paint.bottom_edge
		_skirt_rows = sections.duplicate()
		sections.append(last)
		m.loft(sections, 36 if near else 12, 1, M.Rig.SKIRT, {"uv_y": true})


func _neck() -> void:
	var r: float = p.neck
	var sections := [
		{"y": 1.49, "rx": r * 1.08, "rf": r, "rb": r * 1.04, "cz": .004, "paint": paint.skin},
		{"y": 1.55, "rx": r * .98, "rf": r * .94, "rb": r, "cz": .006, "paint": paint.skin},
		{"y": 1.61, "rx": r * .95, "rf": r * .92, "rb": r, "cz": .008, "paint": paint.skin},
		{"y": 1.665, "rx": r * .9, "rf": r * .82, "rb": r * .95, "cz": .012, "paint": paint.skin},
	]
	m.loft(sections, 16 if near else 8, 2 if near else 1, M.Rig.NECK)
	var neck: String = look.neck
	var collar_paint: int = paint.under if look.top in ["vest", "jacket", "coat", "overalls"] else paint.top
	if neck == "turtle":
		m.loft([{"y": 1.48, "rx": r + .022, "rf": r + .02, "rb": r + .022, "cz": .004, "paint": collar_paint, "n": 2.0},
			{"y": 1.535, "rx": r + .018, "rf": r + .016, "rb": r + .018, "cz": .005, "paint": collar_paint},
			{"y": 1.585, "rx": r + .012, "rf": r + .01, "rb": r + .012, "cz": .007, "paint": collar_paint},
			{"y": 1.60, "rx": r + .004, "rf": r + .002, "rb": r + .004, "cz": .008, "paint": collar_paint}],
			20 if near else 8, 1, M.Rig.NECK)
	elif neck in ["collar", "open"] and near:
		if neck == "collar": _fall_collar(collar_paint, .09, .30, .055, _inner_ease())
		else: _fall_collar(collar_paint, .30, .58, .07, _inner_ease())
	if look.top in ["jacket", "coat"] and near:
		# the lapels: a larger fall collar on the outer layer, reaching down the opening
		_fall_collar(paint.top, .42, .52, .19, .022 if look.top == "jacket" else .026, .016)


## A shirt collar (or, larger, lapels): a band from the neck that falls onto the shoulders,
## open at the front between half-angles g_in (at the neck) and g_out (at the points).
func _fall_collar(pid: int, g_in: float, g_out: float, drop: float, ease: float, stand: float = .007) -> void:
	var r: float = p.neck
	var rows := 5; var cols := 24
	var pos := PackedVector3Array(); pos.resize(rows * cols)
	var pnt := PackedInt32Array(); pnt.resize(rows * cols)
	for i in rows:
		var v := float(i) / float(rows - 1)
		var g := lerpf(g_in, g_out, v)
		for j in cols:
			var th := wrapf(g + (TAU - 2.0 * g) * float(j) / float(cols - 1), -PI, PI)
			var front := pow(maxf(cos(th), 0.0), 1.5)
			var y_in := lerpf(1.55, 1.525, front)
			var y_out := lerpf(1.502, NECKLINE_Y - drop, front)
			var y := lerpf(y_in, y_out, v)
			var inner := Vector3(sin(th) * (r + stand), y, -cos(th) * (r + stand) + .005)
			var outer := torso_point(th, minf(y, 1.53), ease, .0035)
			var t := smoothstep(0.0, 1.0, pow(v, .7))
			var q := inner.lerp(Vector3(outer.x, y, outer.z), t)
			# never inside the shirt's own shoulders
			var floor_r := _torso_radius(th, minf(y, 1.552), ease) + .003
			var flat := Vector2(q.x, q.z)
			if flat.length() < floor_r: flat = flat.normalized() * floor_r
			pos[i * cols + j] = Vector3(flat.x, y, flat.y)
			pnt[i * cols + j] = pid
	m.grid(rows, cols, pos, pnt, false, M.Rig.TORSO, {"two_sided": true, "inset": .002})


# ------------------------------------------------------------------ arms and hands
func _arm(side: float) -> void:
	var lf: float = p.lf
	var table := [[1.452, .010], [1.447, .028], [1.436, .041], [1.414, .047], [1.38, .047], [1.32, .045],
		[1.25, .043], [1.17, .040], [1.10, .037], [1.05, .035], [1.00, .037], [.95, .036], [.90, .032], [.865, .028], [.84, .026]]
	var sleeve: String = look.sleeves
	var outer: String = look.top
	var garment := _inner_top()
	var pid: int = _inner_paint()
	var ease := .007
	if outer in ["jacket", "coat"]:
		sleeve = "long"; pid = paint.top; ease = .018 if outer == "jacket" else .022
	elif outer == "overalls" or outer == "vest":
		pid = paint.under
	if garment in ["sweater", "tunic", "robe"] and not outer in ["jacket", "coat"]: ease = .012
	if garment == "robe": ease = .024
	if garment == "tshirt" and not outer in ["jacket", "coat"]: sleeve = "short"
	var end_y := .86
	match sleeve:
		"rolled": end_y = 1.075
		"short": end_y = 1.27 if garment != "tshirt" else 1.30
	if garment == "dress" and sleeve == "short": end_y = 1.30
	var sections: Array = []
	for row in table:
		var y: float = row[0]
		var r: float = float(row[1]) * lf
		var covered := y > end_y
		var e := ease if covered else 0.0
		if covered and garment == "robe": e += (1.25 - y) * .06 if y < 1.25 else 0.0
		var s := {"y": y, "rx": (r + e) * .96, "rf": r + e, "rb": r + e, "cx": side * .185, "cz": 0.0,
			"paint": pid if covered else paint.skin}
		sections.append(s)
	# the sleeve edge: a hem step onto the skin (a thick rolled band for rolled sleeves)
	var band := .03 if sleeve == "rolled" else .006
	var result: Array = []
	var inserted := false
	for s in sections:
		if not inserted and s.y <= end_y + band + .004:
			if s.y > end_y: continue
			var r_skin := _lerp_table(table, end_y) * lf
			var r_cloth := r_skin + ease + (.012 if sleeve == "rolled" else .004)
			result.append({"y": end_y + band, "rx": r_cloth * .96, "rf": r_cloth, "rb": r_cloth, "cx": side * .185, "paint": pid, "hard": true})
			result.append({"y": end_y + .001, "rx": r_cloth * .96, "rf": r_cloth, "rb": r_cloth, "cx": side * .185, "paint": pid, "hard": true})
			result.append({"y": end_y, "rx": r_skin * .96, "rf": r_skin, "rb": r_skin, "cx": side * .185, "paint": paint.skin, "hard": true})
			inserted = true
		result.append(s)
	m.loft(result, 16 if near else 6, 2 if near else 1, M.Rig.ARM, {"uv_y": true})


func _lerp_table(table: Array, y: float) -> float:
	for k in table.size() - 1:
		var a: Array = table[k]; var b: Array = table[k + 1]
		if y <= float(a[0]) and y >= float(b[0]):
			return lerpf(float(a[1]), float(b[1]), (float(a[0]) - y) / (float(a[0]) - float(b[0])))
	return float(table[-1][1]) if y < float(table[-1][0]) else float(table[0][1])


func _hand(side: float) -> void:
	var s := 1.12 + .08 * float(look.build) + (0.0 if look.sex == "m" else -.07)
	var x := side * .185
	var rows := [[.848, .025, .028, .026], [.82, .022, .035, .030], [.79, .019, .041, .034], [.76, .017, .042, .034],
		[.735, .015, .038, .031], [.715, .013, .031, .026], [.702, .009, .021, .018], [.695, .0, .0, .0]]
	var sections: Array = []
	for row in rows:
		var y: float = .848 - (.848 - float(row[0])) * s
		sections.append({"y": y, "rx": float(row[1]) * s, "rf": float(row[2]) * s, "rb": float(row[3]) * s, "cx": x - side * .004, "cz": -.004, "paint": paint.skin, "n": 2.4})
	m.loft(sections, 12 if near else 5, 2 if near else 1, M.Rig.HAND)
	if near:
		var thumb := PackedVector3Array([Vector3(x - side * .006, .822, -.026), Vector3(x - side * .010, .795, -.046), Vector3(x - side * .012, .772, -.052), Vector3(x - side * .012, .758, -.050)])
		m.tube(thumb, PackedFloat32Array([.011 * s, .0105 * s, .009 * s, .006 * s]), 8, paint.skin, M.Rig.HAND)


# ------------------------------------------------------------------ legs and feet
func _leg(side: float) -> void:
	var lf: float = p.lf
	var f: bool = look.sex == "f"
	var table := [[.95, .06], [.87, .073 if not f else .078], [.78, .08 if not f else .084], [.68, .076], [.58, .067], [.50, .059],
		[.44, .054], [.40, .052], [.35, .053], [.30, .055], [.24, .052], [.18, .044], [.13, .037], [.10, .034], [.075, .033]]
	var bottom: String = look.bottom
	var top_y := .95
	var long_top: bool = look.top in ["dress", "robe"] or bottom == "skirt" or (look.top == "tunic" and float(look.hem) < .7)
	if long_top: top_y = minf(float(look.hem) + .16, .8)
	var cover_to := .075                      # trouser hem
	var ease := .016
	var cover_paint: int = paint.bottom
	var boots: bool = look.shoes == "boots"
	var tuck: bool = boots and bool(look.get("tucked", false))
	if bottom == "shorts": cover_to = .47
	if long_top or bottom == "none": cover_to = 9.0
	var sock_to := -1.0
	if look.get("socks", false): sock_to = .36
	var sections: Array = []
	for row in table:
		var y: float = row[0]
		if y > top_y + .001: continue
		var r: float = float(row[1]) * lf
		var covered := y >= cover_to
		var e := 0.0
		var pid: int = paint.skin
		if covered:
			# trousers sit close at the hip (inside any untucked hem) and hang looser below
			e = lerpf(ease, .009, smoothstep(.72, .86, y))
			# a straight trouser leg below the knee
			if y < .5: r = maxf(r, .062 * lf)
			pid = cover_paint
		elif y >= .1 and y <= sock_to:
			e = .003; pid = paint.sock
		var s := {"y": y, "rx": (r + e) * .97, "rf": r + e, "rb": r + e, "cx": side * .09, "cz": .0, "paint": pid}
		if not covered and y < .34 and y > .2: s["calf"] = .008 * lf
		sections.append(s)
	var out: Array = []
	var inserted := false
	for s in sections:
		if bottom == "shorts" and not inserted and s.y < cover_to:
			var r_skin := _lerp_table(table, cover_to) * lf
			var r_cloth := r_skin + ease + .006
			out.append({"y": cover_to + .004, "rx": r_cloth, "rf": r_cloth, "rb": r_cloth, "cx": side * .09, "paint": cover_paint, "hard": true})
			out.append({"y": cover_to + .0005, "rx": r_cloth, "rf": r_cloth, "rb": r_cloth, "cx": side * .09, "paint": paint.bottom_edge, "hard": true})
			out.append({"y": cover_to, "rx": r_skin, "rf": r_skin, "rb": r_skin, "cx": side * .09, "paint": paint.skin, "hard": true})
			inserted = true
		out.append(s)
	if tuck and cover_to < 1.0:
		for s in out:
			if s.y < .3 and s.paint == cover_paint:
				s.rx = .05; s.rf = .052; s.rb = .052
	m.loft(out, 18 if near else 7, 2 if near else 1, M.Rig.LEG, {"uv_y": true})


func _foot(side: float) -> void:
	var sc: float = p.foot
	var x := side * .1
	var kind: String = look.shoes
	var stations := [[.058, .026, .062], [.05, .034, .082], [.028, .039, .094], [-.01, .042, .088], [-.05, .045, .074],
		[-.09, .046, .060], [-.12, .044, .050], [-.143, .038, .042], [-.157, .028, .033], [-.164, .012, .022], [-.166, .0, .012]]
	if kind == "sandals":
		_shoe_shell(stations, x, sc, -.002, paint.skin, -.004, .8)
		_shoe_shell(stations, x, sc, .004, paint.shoe, .0, 0.0, .018)
		if near:
			for z in [-.1, -.03]:
				var ring := PackedVector3Array(); var rad := PackedFloat32Array()
				for k in 9:
					var a := -PI * .5 + PI * float(k) / 8.0
					ring.append(Vector3(x + sin(a) * .047 * sc, .012 + cos(a) * .045, z * sc)); rad.append(.005)
				m.tube(ring, rad, 5, paint.shoe, M.Rig.FOOT, .5, Vector3.FORWARD)
		return
	_shoe_shell(stations, x, sc, 0.0, paint.shoe, .006, 1.0)
	_shoe_shell(stations, x, sc, .005, paint.sole, -.001, 0.0, .016)
	if kind == "boots":
		var r := .054
		var rows: Array = []
		for y in [.03, .09, .16, .22, .262]:
			rows.append({"y": y, "rx": r * .96, "rf": r, "rb": r * 1.02, "cx": x - side * .004, "cz": .012, "paint": paint.shoe})
		rows.append({"y": .266, "rx": r * .9, "rf": r * .93, "rb": r * .95, "cx": x - side * .004, "cz": .012, "paint": paint.shoe})
		rows.append({"y": .24, "rx": .04, "rf": .04, "rb": .04, "cx": x - side * .004, "cz": .012, "paint": paint.sole})
		m.loft(rows, 14 if near else 6, 1, M.Rig.FOOT)


## One lofted shoe shape from heel (+Z) to toe (-Z). `grow` widens it, `height` overrides the
## upper (a flat sole when given).
func _shoe_shell(stations: Array, x: float, sc: float, grow: float, pid: int, drop: float, height_scale: float, sole_h: float = -1.0) -> void:
	var cols := 16 if near else 6
	var rows := stations.size()
	var pos := PackedVector3Array(); pos.resize(rows * cols)
	var pnt := PackedInt32Array(); pnt.resize(rows * cols)
	for i in rows:
		var st: Array = stations[i]
		var z: float = float(st[0]) * sc
		var wx: float = float(st[1]) * sc + grow
		var h: float = sole_h if sole_h > 0.0 else float(st[2]) * height_scale
		if wx <= grow + .0001 and float(st[1]) == 0.0: wx = 0.0
		var hh := h * .5
		var cy := hh + drop
		for j in cols:
			var a := -PI + TAU * float(j) / float(cols)
			var sn := sin(a); var cs := cos(a)
			var e := .62
			var px := signf(sn) * pow(absf(sn), e) * wx
			var py := signf(cs) * pow(absf(cs), e) * hh
			if float(st[1]) == 0.0: px = 0.0; py = 0.0
			pos[i * cols + j] = Vector3(x + px, cy + py, z)
			pnt[i * cols + j] = pid
	m.grid(rows, cols, pos, pnt, true, M.Rig.FOOT)


# ------------------------------------------------------------------ accessories
func _belt() -> void:
	if not look.get("belt", false): return
	if look.top in ["dress", "robe", "coat", "overalls"]: return
	if _inner_top() in ["sweater", "tshirt", "tunic"] and look.top != "vest": return
	var y: float = p.waist_y - .05
	var w: Vector3 = p.waist.lerp(p.hip, .35)
	var e := .012
	var rows := []
	for dy in [.018, .0, -.018]:
		rows.append({"y": y + dy, "rx": w.x + e, "rf": w.y + e + p.belly * .8, "rb": w.z + e, "n": 2.2, "paint": paint.belt})
	m.loft(rows, 28 if near else 10, 1, M.Rig.TORSO)
	if near:
		m.ellipsoid(Vector3(0, y, -(w.y + e + p.belly * .8) - .003), Vector3(.018, .016, .005), Basis.IDENTITY, 3, 8, paint.metal, M.Rig.TORSO)


func _apron() -> void:
	var kind: String = look.apron
	if kind == "": return
	var top_y: float = 1.36 if kind in ["bib", "leather"] else float(p.waist_y) - .03
	var hem := .5 if kind != "waist" else .56
	var rows := 9 if near else 4
	var cols := 9 if near else 4
	var pos := PackedVector3Array(); pos.resize(rows * cols)
	var pnt := PackedInt32Array(); pnt.resize(rows * cols)
	for i in rows:
		var t := float(i) / float(rows - 1)
		var y := lerpf(top_y, hem, t)
		var half := lerpf(.10, .2, smoothstep(top_y, p.waist_y - .05, y)) if kind != "waist" else lerpf(.17, .21, t)
		# clear of the body, hanging forward below the hips where a striding thigh pushes it
		var depth := maxf(_front_depth(y) + .016 + .065 * smoothstep(.98, hem, y), _skirt_front(y) + .012)
		for j in cols:
			var u := -1.0 + 2.0 * float(j) / float(cols - 1)
			var xx := u * half
			# the apron wraps round the body a little and hangs forward below the hips
			var z := -depth + (u * u) * (.05 if y > .9 else .03)
			pos[i * cols + j] = Vector3(xx, y, z)
			pnt[i * cols + j] = paint.apron
	m.skirt_hem = hem
	m.grid(rows, cols, pos, pnt, false, M.Rig.SKIRT, {"two_sided": true, "inset": .002})
	if kind == "bib" and near:
		# the neck strap: from the bib's top corners over the shoulders and round the nape
		var strap := PackedVector3Array(); var rad := PackedFloat32Array()
		var e := _inner_ease()
		for k in 13:
			var t := float(k) / 12.0
			var side := -1.0 if t < .5 else 1.0
			var u := absf(t - .5) * 2.0          # 1 at the bib corners, 0 at the nape
			var th := side * lerpf(PI, .42, u)
			var y := lerpf(1.515, 1.36, pow(u, 1.6))
			strap.append(torso_point(th, y, e, .006) if y < 1.52 else Vector3(sin(th) * (p.neck + .012), y, -cos(th) * (p.neck + .012)))
			rad.append(.007)
		m.tube(strap, rad, 5, paint.apron, M.Rig.TORSO, .35, Vector3.FORWARD)


## Front depth of the outer torso surface at height y (for aprons and straps).
func _front_depth(y: float) -> float:
	var best := 0.1
	var sections := _torso_sections(.004 if not look.top in ["vest", "jacket", "coat"] else .026)
	for k in sections.size() - 1:
		var a: Dictionary = sections[k]; var b: Dictionary = sections[k + 1]
		if y >= a.y and y <= b.y:
			var t: float = (y - a.y) / (b.y - a.y)
			best = lerpf(a.rf + a.get("belly", 0.0) + a.get("bust", 0.0), b.rf + b.get("belly", 0.0) + b.get("bust", 0.0), t)
	return best


func _neckerchief() -> void:
	if not look.get("scarf", false): return
	var r: float = p.neck
	var rows := [{"y": 1.495, "rx": r + .024, "rf": r + .026, "rb": r + .022, "cz": .004, "paint": paint.scarf},
		{"y": 1.52, "rx": r + .02, "rf": r + .02, "rb": r + .018, "cz": .005, "paint": paint.scarf},
		{"y": 1.545, "rx": r + .012, "rf": r + .012, "rb": r + .012, "cz": .006, "paint": paint.scarf}]
	m.loft(rows, 16 if near else 8, 1, M.Rig.NECK)
	if near:
		m.ellipsoid(Vector3(0, 1.49, -r - .03), Vector3(.022, .02, .015), Basis.IDENTITY, 5, 8, paint.scarf, M.Rig.TORSO_RIGID)
		var tail := PackedVector3Array([Vector3(0, 1.48, -r - .035), Vector3(.01, 1.44, -r - .045), Vector3(.018, 1.40, -_front_depth(1.40) - .012)])
		m.tube(tail, PackedFloat32Array([.02, .026, .012]), 6, paint.scarf, M.Rig.TORSO_RIGID, .3, Vector3.FORWARD)


func _satchel() -> void:
	if not look.get("satchel", false): return
	# a strap from the right shoulder across the chest to a bag on the left hip
	var pts := PackedVector3Array(); var rad := PackedFloat32Array()
	var steps := 10 if near else 5
	var e := .018 if look.top in ["jacket", "coat"] else .008
	for k in steps + 1:
		var t := float(k) / float(steps)
		var y := lerpf(1.47, .98, t)
		var x := lerpf(.11, -.15, t)
		var depth := _front_depth(y) + e + .004
		var z := -depth * clampf(1.0 - pow(x / .19, 2.0), 0.2, 1.0) if t > .08 else 0.0
		pts.append(Vector3(x, y, z)); rad.append(.014)
	m.tube(pts, rad, 4 if near else 3, paint.bag, M.Rig.TORSO, .25, Vector3.FORWARD)
	m.ellipsoid(Vector3(-p.hip.x - .04, .94, .0), Vector3(.03, .09, .12), Basis.IDENTITY, 5 if near else 3, 10 if near else 5, paint.bag, M.Rig.ROOT)
