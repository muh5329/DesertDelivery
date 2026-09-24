class_name PersonHead
extends RefCounted
## Head, face, hair, facial hair, hats and glasses of a townsperson (CharacterMesh parts).
##
## The skull is a lofted profile; the face is sculpted into it by displacement fields
## (brow ridge, eye sockets, nose bridge/tip/wings, cheekbones, lips, chin) whose sizes are
## the look's face parameters, so every face has its own structure. Eyes are separate lens
## patches whose iris and pupil the shader draws (sharp at any distance); lash lines, lids
## and brows are thin tubes. Hair, beards, knit caps and scarves are offset shells of the
## head surface whose edges tuck under the skin, so hairlines follow smooth contours
## rather than the grid; long hair adds a curtain that hangs clear of the shoulders.
## Coordinates are head-local (origin at the head pivot, eye level) until emitted.

const M = preload("res://entities/people/character_mesh.gd")
const PIVOT := Vector3(0, 1.69, 0)

var m: CharacterMesh
var look: Dictionary
var body: PersonBody
var near := true
var f: Dictionary = {}         # face parameters
var female := false
var hair_color: Color
var skin: Color
var rows := 0
var cols := 0
var hpos := PackedVector3Array()   # head grid (head-local)
var hnrm := PackedVector3Array()
var hy := PackedFloat32Array()     # row heights
var cap_t := PackedFloat32Array()  # hair thickness per head vertex (for hats)
var landmarks: Dictionary = {}
var paint: Dictionary = {}

const PROFILE := [
	[.128, .0, .0, .0], [.123, .034, .036, .048], [.112, .056, .060, .075], [.094, .070, .077, .090],
	[.072, .077, .086, .098], [.046, .079, .092, .101], [.020, .078, .095, .100], [.0, .076, .096, .096],
	[-.020, .075, .095, .091], [-.040, .072, .093, .083], [-.060, .067, .089, .071], [-.080, .060, .083, .055],
	[-.095, .051, .077, .042], [-.107, .039, .068, .029], [-.116, .025, .058, .016], [-.122, .010, .045, .006], [-.125, .0, .0, .0]]


func _init(mesh: CharacterMesh, p_look: Dictionary, p_body: PersonBody, detail_near: bool) -> void:
	m = mesh; look = p_look; body = p_body; near = detail_near
	f = look.face
	female = look.sex == "f"
	hair_color = look.hair_color
	skin = look.skin
	var lips := skin.darkened(.10).lerp(Color(.62, .26, .24), .28 if skin.get_luminance() > .45 else .14)
	paint.skin = m.add_paint(skin, M.Mat.SKIN)
	paint.hair = m.add_paint(hair_color, M.Mat.HAIR)
	paint.brow = m.add_paint(look.brow_color, M.Mat.HAIR)
	paint.lash = m.add_paint(Color(look.brow_color).darkened(.55).lerp(Color("1b1411"), .5), M.Mat.HAIR)
	paint.lid = m.add_paint(skin.darkened(.05), M.Mat.SKIN)
	paint.lips = m.add_paint(lips, M.Mat.SKIN)
	paint.eye = m.add_paint(look.eyes, M.Mat.EYE, 11, Color("e2dacd"))
	paint.hat = m.add_paint(look.hat_color, int(look.get("hat_fabric", M.Mat.WOOL)), int(look.get("hat_pattern", 0)), look.get("hat_color2", Color.BLACK))
	paint.hat2 = m.add_paint(look.get("hat_color2", Color.BLACK), M.Mat.COTTON)
	paint.frame = m.add_paint(look.get("glasses_color", Color("2a211c")), M.Mat.LEATHER if not look.get("glasses_metal", false) else M.Mat.METAL)
	landmarks = _landmarks()


func build() -> void:
	_head()
	if near:
		_eyes()
		_brows()
	_ears()
	_facial_hair()
	_hair()
	_hat()
	if near and look.get("glasses", false): _glasses()


# ------------------------------------------------------------------ the skull and face
func _landmarks() -> Dictionary:
	var fl: float = f.face_len
	var tip := -.041 * float(f.nose_len) * fl
	return {"brow_y": .021, "eye_y": .0, "eye_x": .0325 * float(f.eye_gap), "nose_top": .012,
		"tip_y": tip + .004 * float(f.nose_tip), "base_y": tip - .0095, "mouth_y": -.067 * fl, "chin_y": -.104 * fl}


func _profile(y: float) -> Array:
	var fl: float = f.face_len
	var yy := y / fl if y < 0.0 else y / float(f.forehead)
	yy = clampf(yy, -.125, .128)
	var a: Array = PROFILE[0]; var b: Array = PROFILE[-1]
	for k in PROFILE.size() - 1:
		if yy <= float(PROFILE[k][0]) and yy >= float(PROFILE[k + 1][0]):
			a = PROFILE[k]; b = PROFILE[k + 1]; break
	var t := 0.0 if is_equal_approx(float(a[0]), float(b[0])) else (float(a[0]) - yy) / (float(a[0]) - float(b[0]))
	var rx := lerpf(float(a[1]), float(b[1]), t)
	var rf := lerpf(float(a[2]), float(b[2]), t)
	var rb := lerpf(float(a[3]), float(b[3]), t)
	var size := .975 if female else 1.0
	var jaw := lerpf(1.0, float(f.jaw) * (.94 if female else 1.0), smoothstep(-.03, -.09, y))
	rx *= size * float(f.width) * jaw
	rf *= size; rb *= size
	var n := 2.35 if y > -.1 else 2.1
	# the chin sits forward of the skull's axis
	var cz := -.012 * smoothstep(-.09, -.124, y)
	return [rx, rf, rb, n, cz]


## Displacement of the face surface at head-local (x, y), outward, in metres.
func _sculpt(x: float, y: float) -> float:
	var L := landmarks
	var ax := absf(x)
	var d := 0.0
	# brow ridge (stronger in men), a slight glabella between the brows
	d += .0048 * float(f.brow) * exp(-pow((y - L.brow_y) / .0095, 2.0)) * smoothstep(.066, .03, ax)
	# eye sockets
	d -= .0115 * exp(-pow((ax - L.eye_x) / .0175, 2.0) - pow((y - L.eye_y + .0015) / .0115, 2.0))
	# nose: bridge to tip, then the columella tucks back to the lip
	var top: float = L.nose_top; var tip: float = L.tip_y; var base: float = L.base_y
	var proj := 0.0
	var width := .0068
	if y <= top and y >= tip:
		var t := (top - y) / (top - tip)
		proj = lerpf(.0048, .0205 * float(f.nose_proj), pow(t, 1.25)) + .0032 * float(f.nose_bridge) * sin(PI * t)
		width = lerpf(.0068, .0118, t) * float(f.nose_width)
	elif y < tip:
		var t2 := (tip - y) / maxf(tip - base, .001)
		proj = .0205 * float(f.nose_proj) * exp(-pow(t2 * 1.25, 2.0))
		width = .0122 * float(f.nose_width)
	else:
		proj = .0048 * exp(-pow((y - top) / .01, 2.0))
	d += proj * exp(-pow(ax / width, 2.0))
	# alar wings and the grooves beside them
	d += .0058 * float(f.nose_width) * exp(-pow((ax - .0142 * float(f.nose_width)) / .0056, 2.0) - pow((y - base - .003) / .0056, 2.0))
	d -= .0018 * exp(-pow((ax - .0245 * float(f.nose_width)) / .004, 2.0) - pow((y - base) / .008, 2.0))
	# cheekbones
	d += .0062 * float(f.cheek) * exp(-pow((ax - .047) / .017, 2.0) - pow((y + .021) / .0145, 2.0))
	# mouth: muzzle, upper and lower lip, the line between
	var my: float = L.mouth_y
	var lw := .0205 * float(f.mouth_w)
	d += .0045 * exp(-pow(ax / .03, 2.0) - pow((y - my) / .019, 2.0))
	d += .0036 * float(f.lips) * exp(-pow((y - my - .0048) / .0036, 2.0)) * exp(-pow(ax / lw, 4.0))
	d += .0046 * float(f.lips) * exp(-pow((y - my + .0062) / .0044, 2.0)) * exp(-pow(ax / (lw * .88), 4.0))
	d -= .0030 * exp(-pow((y - my) / .0015, 2.0)) * exp(-pow(ax / (lw * 1.08), 4.0))
	# philtrum ridges
	d += .001 * exp(-pow((ax - .0045) / .002, 2.0) - pow((y - (my + base) * .5) / .006, 2.0))
	# chin
	d += .0062 * float(f.chin) * exp(-pow(ax / .021, 2.0) - pow((y - L.chin_y) / .012, 2.0))
	# temples
	d -= .0025 * exp(-pow((ax - .07) / .012, 2.0) - pow((y - .035) / .02, 2.0))
	return d


func _surface_point(th: float, y: float, sculpt: bool, profile: Array = []) -> Vector3:
	var pr := profile if not profile.is_empty() else _profile(y)
	var e := 2.0 / float(pr[3])
	var sn := sin(th); var cs := cos(th)
	var x := signf(sn) * pow(absf(sn), e) * float(pr[0])
	var z := -signf(cs) * pow(absf(cs), e) * (float(pr[1]) if cs > 0.0 else float(pr[2])) + float(pr[4])
	if sculpt and z < -.02:
		var front := smoothstep(-.02, -.06, z)
		var d := _sculpt(x, y) * front
		var radial := Vector2(x * .55, z).normalized()
		x += radial.x * d; z += radial.y * d
	return Vector3(x, y, z)


## The face surface at head-local (x, y) (front only).
func face_point(x: float, y: float) -> Vector3:
	var pr := _profile(y)
	var e := float(pr[3]) / 2.0
	var s := clampf(absf(x) / maxf(float(pr[0]), .001), 0.0, 1.0)
	var sn := pow(s, e)
	var th := asin(clampf(sn, 0.0, 1.0)) * signf(x)
	return _surface_point(th, y, near)


func _rows() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if near:
		var y := .128
		while y > -.125:
			out.append(y)
			y -= .011 if y > .07 else (.0062 if y > .035 else .0038)
		out.append(-.125)
	else:
		for y in [.128, .11, .08, .045, .015, -.01, -.035, -.06, -.085, -.105, -.118, -.125]: out.append(y)
	return out


func _head() -> void:
	hy = _rows()
	rows = hy.size()
	cols = 52 if near else 12
	var warp := .44 if near else .8
	hpos.resize(rows * cols)
	var pnt := PackedInt32Array(); pnt.resize(rows * cols)
	var tint := PackedColorArray(); tint.resize(rows * cols)
	for i in rows:
		var pr := _profile(hy[i])
		for j in cols:
			var t := -1.0 + 2.0 * float(j) / float(cols)
			var th := PI * (warp * t + (1.0 - warp) * t * t * t)
			hpos[i * cols + j] = _surface_point(th, hy[i], near, pr)
			pnt[i * cols + j] = paint.skin
	for k in hpos.size(): tint[k] = _face_color(hpos[k])
	var world := _to_model(hpos)
	var got: Array = []
	m.grid(rows, cols, world, pnt, true, M.Rig.HEAD, {"colors": tint, "normals_out": got})
	hnrm = got[0]
	cap_t.resize(rows * cols)


func _to_model(points: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array(); out.resize(points.size())
	for k in points.size(): out[k] = points[k] + PIVOT
	return out


## Painted face: blush, lids, lips, stubble shadow, scalp under the hair and (far) the eyes.
func _face_color(q: Vector3) -> Color:
	var L := landmarks
	var c := skin
	var ax := absf(q.x)
	var front := smoothstep(-.03, -.07, q.z)
	if front <= 0.0 and q.y < -.085 and look.facial_hair == "none":
		return skin
	var light := skin.get_luminance()
	var flush := Color(skin.r * 1.02, skin.g * .80, skin.b * .78)
	var blush := .30 * exp(-pow((ax - .048) / .02, 2.0) - pow((q.y + .03) / .02, 2.0)) * front
	blush += .22 * exp(-pow(ax / .013, 2.0) - pow((q.y - L.tip_y) / .012, 2.0)) * front
	blush += .12 * exp(-pow(ax / .02, 2.0) - pow((q.y - L.chin_y) / .012, 2.0)) * front
	c = c.lerp(flush, blush * (1.0 if light > .35 else .5))
	# lid crease and socket shading
	var socket := exp(-pow((ax - L.eye_x) / .016, 2.0) - pow((q.y - .006) / .007, 2.0)) * front
	c = c.darkened(.13 * socket)
	# lips
	var my: float = L.mouth_y
	var lw := .0205 * float(f.mouth_w)
	var upper := smoothstep(.0072, .0048, q.y - my) * smoothstep(-.0005, .0012, q.y - my)
	var bow := .0012 * (1.0 - exp(-pow((ax - .0055) / .004, 2.0)))
	upper *= smoothstep(.0075 + bow, .005, q.y - my)
	var lower := smoothstep(-.0112, -.0085, q.y - my) * smoothstep(.0008, -.0006, q.y - my)
	var lipmask := clampf(upper + lower, 0.0, 1.0) * (1.0 - smoothstep(lw * .85, lw * 1.05, ax)) * front
	var lips: Color = m.paints[paint.lips][0]
	c = c.lerp(lips, lipmask)
	# stubble / beard shadow
	var fh: String = look.facial_hair
	var beard := _beard_mask(q) * (1.0 - lipmask)
	if fh == "stubble": c = c.lerp(hair_color.darkened(.25), beard * .42)
	elif fh != "none": c = c.lerp(hair_color.darkened(.2), beard * .55)
	elif not female: c = c.lerp(hair_color.darkened(.35), beard * .07)
	# scalp under the hair
	var hm := _hair_region(q)
	if hm > 0.0: c = c.lerp(hair_color.darkened(.2), clampf(hm, 0.0, 1.0) * .9)
	if not near:
		# the far head has no eye patches: paint dark eyes and brows so faces keep a gaze
		var eye := exp(-pow((ax - L.eye_x) / .01, 2.0) - pow((q.y - L.eye_y) / .0065, 2.0)) * front
		c = c.lerp(Color(look.eyes).darkened(.55), eye * .8)
		var brow := exp(-pow((ax - L.eye_x) / .016, 2.0) - pow((q.y - L.brow_y - .003) / .004, 2.0)) * front
		c = c.lerp(Color(look.brow_color), brow * .75)
		c = c.lerp(lips.darkened(.2), exp(-pow(ax / .016, 2.0) - pow((q.y - my) / .005, 2.0)) * front * .6)
	return c


func _beard_mask(q: Vector3) -> float:
	var L := landmarks
	var az := absf(atan2(q.x, -q.z))
	if az > 2.0: return 0.0
	# the beard line runs from the sideburn down towards the corner of the mouth
	var line := -.07 + .8 * absf(q.x)
	var below_cheek := smoothstep(line + .009, line - .009, q.y)
	var above_neck := smoothstep(-.126, -.112, q.y) if az < 1.2 else smoothstep(-.09, -.06, q.y)
	var sideburn := smoothstep(1.62, 1.4, az)
	var upper_lip := smoothstep(float(L.base_y) - .001, float(L.base_y) - .004, q.y)
	var mask := below_cheek * sideburn * upper_lip
	# up the sideburns to meet the hair
	mask = maxf(mask, smoothstep(1.15, 1.35, az) * smoothstep(1.62, 1.45, az) * smoothstep(.03, .0, q.y))
	return clampf(mask * above_neck, 0.0, 1.0)


# ------------------------------------------------------------------ eyes, lids, brows, ears
func _eyes() -> void:
	var L := landmarks
	var size: float = f.eye_size
	var W := .0132 * size
	var hu := .0058 * size
	var hl := .0042 * size
	var tilt := .0018 * float(f.eye_tilt)
	for side: float in [-1.0, 1.0]:
		var cx: float = side * L.eye_x
		var cy: float = L.eye_y
		var ur := 13; var vr := 9
		var pos := PackedVector3Array(); pos.resize(ur * vr)
		var pnt := PackedInt32Array(); pnt.resize(ur * vr)
		var uv := PackedVector2Array(); uv.resize(ur * vr)
		for i in vr:
			var v := 1.0 - 2.0 * float(i) / float(vr - 1)
			for j in ur:
				var u := -1.0 + 2.0 * float(j) / float(ur - 1)
				var x := cx + u * W
				var up := hu * pow(maxf(1.0 - u * u, 0.0), .72) + tilt * u * side
				var lo := -hl * pow(maxf(1.0 - u * u, 0.0), .9) + tilt * u * side * .6
				var y := cy + (up * v if v > 0.0 else -lo * v)
				var s := face_point(x, y)
				var r2 := clampf(u * u + v * v * .6, 0.0, 1.0)
				# a gently convex lens just proud of the socket
				s.z -= .0009 + .0031 * (1.0 - r2)
				pos[i * ur + j] = s + PIVOT
				pnt[i * ur + j] = paint.eye
				# the shader draws the iris and pupil from this offset (metres)
				# (the iris sits a little high, its top tucked under the upper lid)
				uv[i * ur + j] = Vector2(x - cx - side * .0006, y - cy - .0009)
		_patch(vr, ur, pos, pnt, uv)
		# lash line, lid fold and lower lid
		var lash := PackedVector3Array(); var lr := PackedFloat32Array()
		var fold := PackedVector3Array(); var fr := PackedFloat32Array()
		var lower := PackedVector3Array(); var lwr := PackedFloat32Array()
		for k in 11:
			var u := -1.08 + 2.16 * float(k) / 10.0
			var uu := clampf(u, -1.0, 1.0)
			var x := cx + u * W
			var up := hu * pow(maxf(1.0 - uu * uu, 0.0), .72) + tilt * uu * side
			var lo := -hl * pow(maxf(1.0 - uu * uu, 0.0), .9) + tilt * uu * side * .6
			var sp := face_point(x, cy + up + .0004)
			lash.append(sp + PIVOT + Vector3(0, 0, -.0006))
			var outer := clampf((u * side + 1.0) * .5, 0.0, 1.0)
			lr.append(lerpf(.0008, .0017, outer) * (1.0 - .6 * pow(absf(u) / 1.08, 6.0)))
			var fp := face_point(x, cy + up + .0032 * size)
			fold.append(fp + PIVOT + Vector3(0, 0, -.0004)); fr.append(.0016 * (1.0 - .7 * pow(absf(u) / 1.08, 4.0)))
			var lp := face_point(x, cy + lo - .0003)
			lower.append(lp + PIVOT + Vector3(0, 0, -.0005)); lwr.append(.0008 * (1.0 - .8 * pow(absf(u) / 1.08, 4.0)))
		m.tube(lash, lr, 5, paint.lash, M.Rig.HEAD, .55, Vector3.FORWARD)
		m.tube(fold, fr, 5, paint.lid, M.Rig.HEAD, .6, Vector3.FORWARD)
		m.tube(lower, lwr, 4, paint.lid, M.Rig.HEAD, .6, Vector3.FORWARD)


func _patch(rws: int, cls: int, pos: PackedVector3Array, pnt: PackedInt32Array, uv: PackedVector2Array) -> void:
	var start := m.positions.size()
	m.grid(rws, cls, pos, pnt, false, M.Rig.HEAD, {"flip": false})
	for k in uv.size(): m.uvs[start + k] = uv[k]


func _brows() -> void:
	var L := landmarks
	var thick: float = f.brow_thick
	for side: float in [-1.0, 1.0]:
		var pts := PackedVector3Array(); var rad := PackedFloat32Array()
		for k in 9:
			var t := float(k) / 8.0
			var x: float = side * lerpf(.011, .060, t) * float(f.eye_gap)
			var arch := .0052 * sin(PI * pow(t, .8)) * float(f.brow_arch)
			var y: float = L.brow_y + .001 + arch - t * .004
			var sp := face_point(x, y)
			var n := Vector3(sp.x * .5, 0, sp.z).normalized()
			pts.append(sp + n * .0013 + PIVOT)
			rad.append(lerpf(.0027, .0012, t) * thick * (1.0 - .5 * pow(t, 5.0)))
		m.tube(pts, rad, 5, paint.brow, M.Rig.HEAD, .42, Vector3.FORWARD)


func _ears() -> void:
	var size: float = f.ear
	for side: float in [-1.0, 1.0]:
		var pr := _profile(-.012)
		var center := Vector3(side * (float(pr[0]) + .0045), -.012, .013) + PIVOT
		var basis := Basis(Vector3.UP, side * deg_to_rad(-16.0)) * Basis(Vector3.RIGHT, deg_to_rad(10.0))
		var rings := 9 if near else 4
		var segs := 12 if near else 6
		var pos := PackedVector3Array(); pos.resize((rings + 1) * segs)
		var pnt := PackedInt32Array(); pnt.resize((rings + 1) * segs)
		var tint := PackedColorArray(); tint.resize((rings + 1) * segs)
		var radii := Vector3(.0085, .029, .017) * size
		for i in rings + 1:
			var phi := PI * float(i) / float(rings)
			for j in segs:
				var th := -PI + TAU * float(j) / float(segs)
				var lx := sin(phi) * sin(th); var ly := cos(phi); var lz := -sin(phi) * cos(th)
				# ear rim: the outward face is cupped (the concha)
				var cup := 0.0
				if lx * side > 0.2:
					cup = .55 * exp(-(ly * ly) / .35 - (lz * lz) / .45)
				var local := Vector3(lx * radii.x * (1.0 - cup), ly * radii.y * (1.0 - .12 * lz), lz * radii.z)
				# the lobe is softer and narrower at the bottom
				if ly < -.3: local.z *= .82
				pos[i * segs + j] = center + basis * local
				pnt[i * segs + j] = paint.skin
				var flush := Color(skin.r * 1.03, skin.g * .83, skin.b * .8)
				tint[i * segs + j] = skin.lerp(flush, .35).darkened(.18 * cup)
		m.grid(rings + 1, segs, pos, pnt, true, M.Rig.HEAD, {"colors": tint})


# ------------------------------------------------------------------ shells (hair, beards, caps)
## Emits the part of the head grid whose offset is positive (plus a one-vertex tucked rim),
## displaced along the head normal. offsets are per head vertex, metres.
func _shell(offsets: PackedFloat32Array, pid: int, scheme: int = M.Rig.HEAD, colors: PackedColorArray = PackedColorArray(), push: PackedVector3Array = PackedVector3Array()) -> void:
	var r0 := rows; var r1 := -1
	for i in rows:
		for j in cols:
			if offsets[i * cols + j] > 0.0:
				r0 = mini(r0, i); r1 = maxi(r1, i)
	if r1 < 0: return
	r0 = maxi(r0 - 1, 0); r1 = mini(r1 + 1, rows - 1)
	var n := r1 - r0 + 1
	var pos := PackedVector3Array(); pos.resize(n * cols)
	var pnt := PackedInt32Array(); pnt.resize(n * cols)
	var keep := PackedByteArray(); keep.resize(n * cols)
	var tint := PackedColorArray()
	if not colors.is_empty(): tint.resize(n * cols)
	for i in n:
		for j in cols:
			var k := (i + r0) * cols + j
			var o := offsets[k]
			var d := o if o > 0.0 else -.0012
			var q := hpos[k] + hnrm[k] * d
			if not push.is_empty() and o > 0.0: q += push[k]
			pos[i * cols + j] = q + PIVOT
			pnt[i * cols + j] = pid
			keep[i * cols + j] = 1 if o > 0.0 else 0
			if not colors.is_empty(): tint[i * cols + j] = colors[k]
	var opts := {"keep": keep}
	if not colors.is_empty(): opts["colors"] = tint
	m.grid(n, cols, pos, pnt, true, scheme, opts)


func _azimuth(q: Vector3) -> float:
	return atan2(q.x, -q.z)


## Where the scalp is covered (0..1), for painting.
func _hair_region(q: Vector3) -> float:
	var style: String = look.hair
	if style == "bald": return 0.0
	var line := _hairline(absf(_azimuth(q)))
	var inside := smoothstep(line - .004, line + .006, q.y)
	if style == "balding":
		inside *= 1.0 - smoothstep(.052, .07, q.y - .5 * cos(_azimuth(q)) * .03) * smoothstep(2.4, 1.6, absf(_azimuth(q)))
	return inside


func _hairline(az: float) -> float:
	var style: String = look.hair
	var fy: float = .061 * float(f.forehead) + float(look.get("recede", 0.0))
	var temple := fy - (.012 if not female else .004) + float(look.get("recede", 0.0)) * .6
	var side := -.026 if not female else -.008
	if style in ["long_straight", "long_wavy", "curly", "afro", "braid"]: side = -.03
	var pts := [[0.0, fy], [.5, temple], [.95, temple - .012], [1.22, side], [1.42, side * .3 + .012], [1.55, .022],
		[1.95, .018], [2.15, -.03], [2.6, -.066], [PI, -.074]]
	if style in ["long_straight", "long_wavy", "afro", "curly"]:
		pts[5][1] = -.02; pts[6][1] = -.03
	for k in pts.size() - 1:
		if az <= float(pts[k + 1][0]):
			var t := (az - float(pts[k][0])) / (float(pts[k + 1][0]) - float(pts[k][0]))
			return lerpf(float(pts[k][1]), float(pts[k + 1][1]), smoothstep(0.0, 1.0, t))
	return float(pts[-1][1])


func _noise(q: Vector3, s: float) -> float:
	return (sin(q.x * s + 1.7) * sin(q.y * s * 1.3 + .4) * sin(q.z * s * .9 + 2.2) + sin(q.x * s * 2.1 + q.z * s * 1.7) * .5) * .66


func _hair() -> void:
	var style: String = look.hair
	cap_t.fill(0.0)
	if style == "bald": return
	var base := {"crop": .0065, "buzz": .0022, "side_part": .011, "textured": .011, "afro": .032, "curly": .02,
		"long_straight": .0085, "long_wavy": .0095, "bun": .0065, "ponytail": .0065, "braid": .006,
		"balding": .005, "headscarf": .0}[style] as float
	var offsets := PackedFloat32Array(); offsets.resize(rows * cols)
	var push := PackedVector3Array(); push.resize(rows * cols)
	var part_side := 1.0 if int(look.seed) % 2 == 0 else -1.0
	for i in rows:
		for j in cols:
			var k := i * cols + j
			var q := hpos[k]
			var az := _azimuth(q)
			var line := _hairline(absf(az))
			var above := q.y - line
			var fall := smoothstep(-.002, .014, above)
			var t := base * fall
			var top := smoothstep(.02, .11, q.y)
			match style:
				"crop": t += .004 * top
				"side_part":
					t += .009 * top + .006 * smoothstep(0.0, .9, az * part_side) * smoothstep(.03, .09, q.y)
					push[k] = Vector3(-part_side * .004, .002, -.003) * top * fall
				"textured": t += (.006 + .0035 * _noise(q, 260.0)) * top
				"afro":
					t += .012 * top + .006 * _noise(q, 140.0)
					push[k] = Vector3(q.x, q.y + .02, q.z + .01).normalized() * .006 * fall
				"curly": t += .008 * top + .005 * _noise(q, 170.0)
				"long_straight", "long_wavy": t += .004 * top
				"bun", "ponytail", "braid": t += .0015 * top
				"balding":
					var crown := smoothstep(.048, .066, q.y - .02 * cos(az)) * smoothstep(2.5, 1.4, absf(az))
					t *= 1.0 - crown
				"headscarf": t = 0.0
			if above < -.001: t = 0.0
			offsets[k] = t
			cap_t[k] = t
	if style != "headscarf":
		_shell(offsets, paint.hair, M.Rig.HEAD, PackedColorArray(), push)
	match style:
		"long_straight", "long_wavy", "curly": _curtain(style)
		"bun": _bun()
		"ponytail": _ponytail()
		"braid": _braid()
		"headscarf": _headscarf()


## Long hair: a two-sided sheet from under the cap down the back and sides.
func _curtain(style: String) -> void:
	var length: float = look.get("hair_len", .30)
	if style == "curly": length = minf(length, .17)
	var nu := 30 if near else 10
	var nv := 12 if near else 4
	var start := 1.18
	var pos := PackedVector3Array(); pos.resize(nu * nv)
	var pnt := PackedInt32Array(); pnt.resize(nu * nv)
	for j in nu:
		var th := wrapf(start + (TAU - 2.0 * start) * float(j) / float(nu - 1), -PI, PI)
		var back := clampf((absf(th) - start) / (PI - start), 0.0, 1.0)
		var bottom := lerpf(-.16, -length, pow(back, .7))
		var top := _surface_point(th, .025, false)
		var widest := _surface_point(th, .0, false)
		for i in nv:
			var t := float(i) / float(nv - 1)
			var y := lerpf(.035, bottom, t)
			var ring := top if y > .0 else widest
			var dir := Vector2(ring.x, ring.z)
			var rr := dir.length() + .007 + .018 * t * (.4 + back)
			if style == "curly": rr += .012 + .006 * sin(float(j) * 1.7 + t * 9.0)
			if style == "long_wavy": rr += .0045 * sin(t * 17.0 + float(j) * .6)
			var d := dir.normalized() * rr
			var q := Vector3(d.x, y, d.y)
			# keep off the shoulders and upper back
			var model_y := y + PIVOT.y
			var clear := body.outer_radius(th, model_y) + .014 if body else 0.0
			var qr := Vector2(q.x, q.z - .0)
			if qr.length() < clear: qr = qr.normalized() * clear
			pos[i * nu + j] = Vector3(qr.x, y, qr.y) + PIVOT
			pnt[i * nu + j] = paint.hair
	m.grid(nv, nu, pos, pnt, false, M.Rig.HAIR, {"two_sided": true, "inset": .003})


func _bun() -> void:
	var pr := _profile(.06)
	var c := Vector3(0, .062, float(pr[2]) + .022) + PIVOT
	var rings := 7 if near else 3
	var segs := 12 if near else 5
	m.ellipsoid(c, Vector3(.036, .031, .03), Basis(Vector3.RIGHT, -.5), rings, segs, paint.hair, M.Rig.HEAD)


func _ponytail() -> void:
	var pr := _profile(.045)
	var z := float(pr[2])
	var pts := PackedVector3Array([Vector3(0, .05, z + .002), Vector3(0, .04, z + .022), Vector3(0, .0, z + .038),
		Vector3(0, -.07, z + .04), Vector3(0, -.15, z + .03), Vector3(0, -.2, z + .026)])
	for k in pts.size(): pts[k] += PIVOT
	m.tube(pts, PackedFloat32Array([.016, .019, .022, .019, .011, .003]), 10 if near else 5, paint.hair, M.Rig.HAIR, .8, Vector3.RIGHT)
	if near:
		m.ellipsoid(Vector3(0, .04, z + .022) + PIVOT, Vector3(.015, .015, .008), Basis(Vector3.RIGHT, .9), 4, 8, paint.hat2, M.Rig.HEAD)


func _braid() -> void:
	var pr := _profile(-.03)
	var z := float(pr[2])
	var pts := PackedVector3Array(); var rad := PackedFloat32Array()
	var count := 16 if near else 5
	for k in count:
		var t := float(k) / float(count - 1)
		var y := lerpf(-.02, -.30, t)
		pts.append(Vector3(0, y, z + .012 + .02 * sin(t * 1.2)) + PIVOT)
		var lump := (.5 + .5 * absf(sin(t * 16.0))) if near else 1.0
		rad.append(lerpf(.017, .008, t) * (.85 + .25 * lump))
	# rest the braid on the back
	for k in pts.size():
		var mr := body.outer_radius(PI, pts[k].y) + .016 if body else 0.0
		pts[k].z = maxf(pts[k].z, mr)
	m.tube(pts, rad, 8 if near else 4, paint.hair, M.Rig.HAIR, .9, Vector3.RIGHT)


func _headscarf() -> void:
	# a kerchief over the hair, covering the ears, tied at the nape
	var offsets := PackedFloat32Array(); offsets.resize(rows * cols)
	for i in rows:
		for j in cols:
			var k := i * cols + j
			var q := hpos[k]
			var az := absf(_azimuth(q))
			var line := lerpf(.052, -.07, smoothstep(.5, 1.6, az))
			if az > 2.4: line = lerpf(-.07, -.085, smoothstep(2.4, PI, az))
			var t := .010 * smoothstep(line - .002, line + .01, q.y) + .004 * smoothstep(.0, .1, q.y)
			offsets[k] = t
			cap_t[k] = t
	var pid := m.add_paint(look.get("scarf_head_color", look.hat_color), M.Mat.COTTON, int(look.get("scarf_head_pattern", 0)), Color(look.get("scarf_head_color", look.hat_color)).lightened(.5))
	_shell(offsets, pid)
	var pr := _profile(-.06)
	var knot := Vector3(0, -.062, float(pr[2]) + .012) + PIVOT
	m.ellipsoid(knot, Vector3(.022, .018, .016), Basis.IDENTITY, 4 if near else 3, 8 if near else 5, pid, M.Rig.HEAD)
	if near:
		for side: float in [-1.0, 1.0]:
			var tail := PackedVector3Array([knot, knot + Vector3(side * .02, -.035, .012), knot + Vector3(side * .03, -.075, .02)])
			m.tube(tail, PackedFloat32Array([.014, .016, .004]), 5, pid, M.Rig.HAIR, .3, Vector3.FORWARD)


func _facial_hair() -> void:
	var fh: String = look.facial_hair
	if fh in ["none", "stubble"] or female: return
	var L := landmarks
	var offsets := PackedFloat32Array(); offsets.resize(rows * cols)
	var push := PackedVector3Array(); push.resize(rows * cols)
	var any := false
	for i in rows:
		for j in cols:
			var k := i * cols + j
			var q := hpos[k]
			var ax := absf(q.x)
			var t := 0.0
			var my: float = L.mouth_y
			var lw := .0205 * float(f.mouth_w)
			var mous := smoothstep(float(L.base_y) - .0005, float(L.base_y) - .004, q.y) * smoothstep(my + .0048, my + .0075, q.y) * smoothstep(lw + .012, lw, ax) * smoothstep(-.05, -.08, q.z)
			# the moustache droops a little past the mouth corners
			mous = maxf(mous, smoothstep(my + .006, my - .004, q.y) * smoothstep(my - .014, my - .006, q.y) * smoothstep(lw - .004, lw + .002, ax) * smoothstep(lw + .01, lw + .005, ax) * smoothstep(-.05, -.08, q.z))
			match fh:
				"moustache": t = .0042 * mous
				"goatee":
					var chin := smoothstep(my - .006, my - .012, q.y) * smoothstep(.022, .012, ax) * smoothstep(-.03, -.06, q.z)
					t = maxf(.0042 * mous, .0055 * chin)
				"beard", "full_beard":
					var mask := _beard_mask(q)
					var lipgap := 1.0 - exp(-pow(ax / (lw * 1.05), 4.0) - pow((q.y - my + .002) / .008, 2.0))
					var depth := .0055 if fh == "beard" else .011
					t = maxf(.0042 * mous, depth * mask * lipgap)
					if fh == "full_beard":
						var chin_down := smoothstep(-.085, -.12, q.y) * smoothstep(.05, .0, ax)
						push[k] = Vector3(0, -.016, -.006) * chin_down * mask
			offsets[k] = t
			if t > 0.0: any = true
	if any: _shell(offsets, paint.hair, M.Rig.HEAD, PackedColorArray(), push)


# ------------------------------------------------------------------ hats and glasses
func _hat() -> void:
	var hat: String = look.hat
	if hat == "": return
	match hat:
		"flat_cap": _flat_cap()
		"straw", "sunhat": _brimmed(hat)
		"felt": _brimmed(hat)
		"knit": _knit()
		"beret": _beret()
		"baker": _baker()
		"headwrap": _headwrap()


## Offsets over the head grid above a band line (front, side, back heights), enclosing hair.
func _cap_offsets(front_y: float, side_y: float, back_y: float, extra: float, crown: float) -> PackedFloat32Array:
	var offsets := PackedFloat32Array(); offsets.resize(rows * cols)
	for i in rows:
		for j in cols:
			var k := i * cols + j
			var q := hpos[k]
			var az := absf(_azimuth(q))
			var band := lerpf(front_y, side_y, smoothstep(0.0, 1.57, az)) if az < 1.57 else lerpf(side_y, back_y, smoothstep(1.57, PI, az))
			var inside := smoothstep(band - .001, band + .004, q.y)
			offsets[k] = (cap_t[k] + extra + crown * smoothstep(.06, .128, q.y)) * inside if q.y > band - .002 else 0.0
	return offsets


func _flat_cap() -> void:
	var offsets := _cap_offsets(.052, .042, .02, .005, .0)
	var push := PackedVector3Array(); push.resize(rows * cols)
	for k in rows * cols:
		var q := hpos[k]
		# the flat cap's crown is pressed flat and slopes forward over the peak
		push[k] = Vector3(0, -.022, -.014) * smoothstep(.06, .125, q.y) * (1.0 if offsets[k] > 0.0 else 0.0)
	_shell(offsets, paint.hat, M.Rig.HEAD, PackedColorArray(), push)
	# the peak
	var nu := 11 if near else 5
	var nv := 4 if near else 2
	var pos := PackedVector3Array(); pos.resize(nu * nv)
	var pnt := PackedInt32Array(); pnt.resize(nu * nv)
	for i in nv:
		var t := float(i) / float(nv - 1)
		for j in nu:
			var u := -1.0 + 2.0 * float(j) / float(nu - 1)
			var x := u * .074 * (1.0 - .25 * t * t)
			var base := face_point(x * .9, .054)
			var z := base.z - .006 - t * .05 * sqrt(maxf(1.0 - u * u * .7, 0.0))
			pos[i * nu + j] = Vector3(x, .056 - t * .012, z) + PIVOT
			pnt[i * nu + j] = paint.hat
	m.grid(nv, nu, pos, pnt, false, M.Rig.HEAD, {"two_sided": true, "inset": .003})


func _brimmed(kind: String) -> void:
	var crown_h := {"straw": .062, "sunhat": .052, "felt": .075}[kind] as float
	var brim := {"straw": .078, "sunhat": .105, "felt": .042}[kind] as float
	var band_y := .05
	var pr := _profile(band_y)
	var rx := float(pr[0]) + .014 + _max_cap()
	var rf := float(pr[1]) + .014 + _max_cap() * .6
	var rb := float(pr[2]) + .014 + _max_cap()
	var main: int = paint.hat
	var ribbon: int = paint.hat2
	# crown
	var crown: Array = []
	var steps := 5 if near else 2
	for k in steps + 1:
		var t := float(k) / float(steps)
		var y := band_y - .004 + crown_h * t
		var shrink := 1.0 - (.1 * t if kind != "felt" else .26 * t)
		var dome := 1.0 - pow(t, 6.0) * .5
		crown.append({"y": y, "rx": rx * shrink * dome, "rf": rf * shrink * dome, "rb": rb * shrink * dome, "cz": .006, "paint": main})
	crown.append({"y": band_y - .004 + crown_h + .004, "rx": .0, "rf": .0, "rb": .0, "cz": .006, "paint": main})
	for s in crown: s.y += PIVOT.y
	m.loft(crown, 20 if near else 8, 1, M.Rig.HEAD)
	if kind == "felt" and near:
		# the crease on top of the alpine hat
		m.ellipsoid(Vector3(0, band_y + crown_h - .004, .006) + PIVOT, Vector3(.012, .004, .05), Basis.IDENTITY, 3, 8, paint.hat, M.Rig.HEAD)
	# band
	var band: Array = []
	for dy in [.0, .012 if kind != "felt" else .016]:
		band.append({"y": band_y + dy + PIVOT.y, "rx": rx + .002, "rf": rf + .002, "rb": rb + .002, "cz": .006, "paint": ribbon})
	m.loft(band, 20 if near else 8, 1, M.Rig.HEAD)
	# brim: rows go outward from the crown; the sun hat droops, the felt hat turns up at the sides
	var nu := 28 if near else 10
	var nv := 4 if near else 2
	var pos := PackedVector3Array(); pos.resize(nu * nv)
	var pnt := PackedInt32Array(); pnt.resize(nu * nv)
	for i in nv:
		var t := float(i) / float(nv - 1)
		for j in nu:
			var th := -PI + TAU * float(j) / float(nu)
			var sn := sin(th); var cs := cos(th)
			var r0x := rx * .98; var r0z := (rf if cs > 0.0 else rb) * .98
			var out := brim * t
			var x := sn * (r0x + out)
			var z := -cs * (r0z + out) + .006
			var y := band_y - .002
			if kind == "sunhat": y -= .028 * t * t
			elif kind == "felt": y += .02 * t * t * sn * sn - .006 * t * cs * cs
			else: y -= .006 * t * t
			pos[i * nu + j] = Vector3(x, y, z) + PIVOT
			pnt[i * nu + j] = main
	# rows run outward and columns sweep towards +X: d/dcol x d/drow points up
	m.grid(nv, nu, pos, pnt, true, M.Rig.HEAD, {"two_sided": true, "inset": .0025})


func _max_cap() -> float:
	var best := 0.0
	for k in cap_t.size():
		if hpos[k].y > .04: best = maxf(best, cap_t[k])
	return minf(best, .03)


func _knit() -> void:
	var offsets := _cap_offsets(.05, .03, .0, .01, .012)
	_shell(offsets, paint.hat)
	# the folded cuff
	var cuff := PackedFloat32Array(); cuff.resize(rows * cols)
	for k in rows * cols:
		var q := hpos[k]
		var az := absf(_azimuth(q))
		var band := lerpf(.05, .03, smoothstep(0.0, 1.57, az)) if az < 1.57 else lerpf(.03, .0, smoothstep(1.57, PI, az))
		var o := offsets[k]
		cuff[k] = o + .004 if o > 0.0 and q.y < band + .024 else 0.0
	_shell(cuff, paint.hat)
	if look.get("pompom", false):
		m.ellipsoid(Vector3(0, .148, .0) + PIVOT, Vector3(.022, .02, .022), Basis.IDENTITY, 5 if near else 3, 8 if near else 5, paint.hat2, M.Rig.HEAD)


func _beret() -> void:
	var tilt := Basis(Vector3.FORWARD, .22 * (1.0 if int(look.seed) % 2 == 0 else -1.0)) * Basis(Vector3.RIGHT, -.12)
	m.ellipsoid(Vector3(0, .088 + _max_cap() * .6, .008) + PIVOT, Vector3(.106, .03, .11), tilt, 6 if near else 3, 16 if near else 8, paint.hat, M.Rig.HEAD)
	var offsets := _cap_offsets(.06, .05, .045, .004, .0)
	_shell(offsets, paint.hat)


func _baker() -> void:
	# a soft linen toque: a band hugging the head, a puffed crown leaning back a little
	var offsets := _cap_offsets(.046, .03, .012, .006, .0)
	_shell(offsets, paint.hat)
	var pr := _profile(.05)
	var rx := float(pr[0]) + .012 + _max_cap()
	var rf := float(pr[1]) + .012; var rb := float(pr[2]) + .012
	var rows_list: Array = []
	var ys := [.035, .06, .085, .115, .145, .168, .18, .184]
	var widen := [1.0, 1.04, 1.16, 1.26, 1.28, 1.12, .7, .0]
	for k in ys.size():
		var w: float = widen[k]
		rows_list.append({"y": float(ys[k]) + PIVOT.y, "rx": rx * w, "rf": rf * w, "rb": rb * w, "cz": .004 + .014 * float(k) / 7.0, "paint": paint.hat})
	m.loft(rows_list, 18 if near else 8, 2 if near else 1, M.Rig.HEAD)


func _headwrap() -> void:
	var offsets := _cap_offsets(.04, .012, -.025, .018, .016)
	var push := PackedVector3Array(); push.resize(rows * cols)
	for k in rows * cols:
		var q := hpos[k]
		if offsets[k] <= 0.0: continue
		# wrapped folds rising diagonally round the head
		var az := _azimuth(q)
		offsets[k] += .0045 * sin(q.y * 150.0 + az * 2.0) * smoothstep(.0, .06, offsets[k])
	_shell(offsets, paint.hat, M.Rig.HEAD, PackedColorArray(), push)
	if near:
		var pr := _profile(.0)
		var tail := PackedVector3Array([Vector3(0, .04, float(pr[2]) + .022), Vector3(.02, -.02, float(pr[2]) + .03), Vector3(.03, -.11, float(pr[2]) + .03)])
		for k in tail.size(): tail[k] += PIVOT
		m.tube(tail, PackedFloat32Array([.02, .024, .006]), 6, paint.hat, M.Rig.HAIR, .3, Vector3.FORWARD)


func _glasses() -> void:
	var L := landmarks
	var is_round := int(look.seed) % 3 == 0
	var rw := .0175 if not is_round else .016
	var rh := .0135 if not is_round else .016
	var z_off := -.011
	for side: float in [-1.0, 1.0]:
		var cx: float = side * L.eye_x
		var c := face_point(cx, .001)
		var pts := PackedVector3Array(); var rad := PackedFloat32Array()
		for k in 21:
			var a := TAU * float(k) / 20.0
			pts.append(Vector3(cx + cos(a) * rw, .001 + sin(a) * rh, c.z + z_off) + PIVOT)
			rad.append(.0013)
		m.tube(pts, rad, 5, paint.frame, M.Rig.HEAD)
		# temple arm back to the ear
		var pr := _profile(.004)
		var arm := PackedVector3Array([Vector3(side * (L.eye_x + rw), .004, c.z + z_off + .002) + PIVOT,
			Vector3(side * (float(pr[0]) + .006), .006, -.03) + PIVOT, Vector3(side * (float(pr[0]) + .004), .0, .012) + PIVOT])
		m.tube(arm, PackedFloat32Array([.0011, .0011, .0011]), 4, paint.frame, M.Rig.HEAD)
	var nose := face_point(0.0, .006)
	var bridge := PackedVector3Array([Vector3(-L.eye_x + rw * .92, .004, nose.z + z_off * .3) + PIVOT, Vector3(0, .008, nose.z - .004) + PIVOT, Vector3(L.eye_x - rw * .92, .004, nose.z + z_off * .3) + PIVOT])
	m.tube(bridge, PackedFloat32Array([.0011, .0011, .0011]), 4, paint.frame, M.Rig.HEAD)
