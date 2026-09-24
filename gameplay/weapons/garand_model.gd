class_name GarandModel
extends Node3D
## The courier's M1 Garand, built in code to the real rifle's proportions: 1.107 m overall, a
## 24" (0.61 m) barrel, walnut stock with the semi-pistol-grip wrist (no separate grip), the
## parkerised receiver with the aperture rear sight and its two drums, the operating rod and
## handle on the right, the gas cylinder slung UNDER the muzzle with the front sight and its
## ears on top, the lower and upper bands, trigger guard, steel butt plate, sling swivels and a
## leather sling, and the en-bloc clip showing in the receiver well.
##
## Frame: -Z toward the muzzle, +Y up, the origin on the bore axis in the plane of the butt plate.
## Markers (children) for poses, effects and the sling: Muzzle, Butt, GripR, GripL, Sight,
## Ejection, SlingFront, SlingRear. The meshes are built once and shared by every instance.
##
##   set_loaded(rounds)   clip + cartridges visible when loaded; bolt locked back when empty
##   cycle()              the operating rod slams back and forward (a shot)
##   set_sling(taut)      sling hanging under the rifle, or drawn up tight (slung on the back)
##   make_clip()          an empty en-bloc clip (the one that pings out)

const LENGTH := 1.107
const SIGHT_Y := 0.040
const BOLT_TRAVEL := 0.058

static var _meshes: Dictionary = {}

var bolt: Node3D
var clip: Node3D
var _sling_hang: MeshInstance3D
var _sling_taut: MeshInstance3D
var _cycle_t := -1.0
var _locked_back := false


func _init() -> void:
	if _meshes.is_empty(): _build_meshes()
	name = "Garand"
	_mi(_meshes.body)
	bolt = Node3D.new(); bolt.name = "Bolt"; add_child(bolt)
	var bm := MeshInstance3D.new(); bm.mesh = _meshes.bolt; bolt.add_child(bm)
	clip = Node3D.new(); clip.name = "Clip"; add_child(clip)
	var cm := MeshInstance3D.new(); cm.mesh = _meshes.clip; clip.add_child(cm)
	_sling_hang = _mi(_meshes.sling_hang)
	_sling_taut = _mi(_meshes.sling_taut)
	_sling_taut.visible = false
	# the hand markers are palm contacts: the point on the wood the palm rests on, the palm
	# facing the marker's -Z. Right hand on the right side of the wrist of the stock; left hand
	# cupping the forend from below, just ahead of the lower band.
	var grip_r := Transform3D(Basis(Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0)), Vector3(0.017, -0.050, -0.236))
	var grip_l := Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0)), Vector3(0.0, -0.047, -0.655))
	for m in [["Muzzle", Transform3D(Basis(), Vector3(0, 0, -LENGTH - 0.004))], ["Butt", Transform3D(Basis(), Vector3(0, -0.106, 0.0))],
			["GripR", grip_r], ["GripL", grip_l],
			["Sight", Transform3D(Basis(), Vector3(0, SIGHT_Y, -0.285))], ["Ejection", Transform3D(Basis(), Vector3(0, 0.03, -0.37))],
			["SlingFront", Transform3D(Basis(), Vector3(0, -0.066, -0.616))], ["SlingRear", Transform3D(Basis(), Vector3(0, -0.152, -0.118))]]:
		var n := Node3D.new(); n.name = m[0]; n.transform = m[1]; add_child(n)


func _mi(mesh: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)
	return mi


func marker(n: String) -> Node3D:
	return get_node(n)


func set_loaded(rounds: int) -> void:
	clip.visible = rounds > 0
	_locked_back = rounds <= 0
	if _cycle_t < 0.0: bolt.position.z = BOLT_TRAVEL if _locked_back else 0.0


func cycle() -> void:
	_cycle_t = 0.0
	set_process(true)


func set_sling(taut: bool) -> void:
	_sling_hang.visible = not taut
	_sling_taut.visible = taut


func _ready() -> void:
	set_process(false)


func _process(delta: float) -> void:
	if _cycle_t < 0.0:
		set_process(false)
		return
	_cycle_t += delta
	# the operating rod drives the bolt back in ~25 ms and the spring returns it in ~55 ms
	var t := _cycle_t
	var back := clampf(t / 0.025, 0.0, 1.0) if t < 0.025 else clampf(1.0 - (t - 0.025) / 0.055, 0.0, 1.0)
	if _locked_back and t >= 0.025: back = 1.0
	bolt.position.z = back * BOLT_TRAVEL
	if t > 0.09:
		_cycle_t = -1.0
		bolt.position.z = BOLT_TRAVEL if _locked_back else 0.0


## An en-bloc clip: two side walls and a ribbed back, open to the front; `full` adds the eight
## rounds (double stack, bullets forward) for the one in the courier's hand.
static func make_clip(full: bool = false) -> Node3D:
	if _meshes.is_empty(): _build_meshes()
	var n := Node3D.new()
	var mi := MeshInstance3D.new(); mi.mesh = _meshes.clip_full if full else _meshes.clip_empty
	n.add_child(mi)
	return n


# ============================================================================== geometry
static func _build_meshes() -> void:
	var wood := MeshKit.new()
	var steel := MeshKit.new()
	var dark := MeshKit.new()
	var brass := MeshKit.new()
	var copper := MeshKit.new()
	var bore := MeshKit.new()

	# --- stock: butt, comb, the swelled wrist (semi pistol grip), action, forend -------------
	# rows: [z, top, bottom, half width, exponent]
	var stock := [
		[-0.004, -0.040, -0.172, 0.0205, 2.7],
		[-0.040, -0.037, -0.163, 0.0212, 2.6],
		[-0.090, -0.033, -0.148, 0.0215, 2.6],
		[-0.140, -0.029, -0.130, 0.0210, 2.5],
		[-0.180, -0.026, -0.113, 0.0195, 2.4],
		[-0.208, -0.023, -0.099, 0.0172, 2.3],
		[-0.232, -0.021, -0.094, 0.0158, 2.2],
		[-0.255, -0.017, -0.091, 0.0158, 2.3],
		[-0.272, -0.010, -0.080, 0.0172, 2.5],
		[-0.286, -0.001, -0.066, 0.0198, 2.9],
		[-0.302, 0.004, -0.061, 0.0218, 3.3],
		[-0.400, 0.005, -0.061, 0.0226, 3.4],
		[-0.470, 0.004, -0.060, 0.0226, 3.4],
		[-0.502, 0.001, -0.056, 0.0222, 3.2],
		[-0.560, -0.001, -0.051, 0.0215, 3.0],
		[-0.700, -0.003, -0.045, 0.0205, 3.0],
		[-0.860, -0.005, -0.040, 0.0190, 3.0],
		[-0.925, -0.006, -0.037, 0.0180, 3.0],
	]
	wood.loft(MeshKit.sections(stock, 3, 28))
	# handguards on top of the barrel: rear (behind the lower band) and front
	wood.loft(MeshKit.sections([
		[-0.506, 0.017, -0.006, 0.0172, 2.4], [-0.515, 0.0205, -0.006, 0.0185, 2.4],
		[-0.595, 0.0205, -0.006, 0.0185, 2.4], [-0.603, 0.018, -0.006, 0.0178, 2.4]], 2, 24))
	wood.loft(MeshKit.sections([
		[-0.630, 0.018, -0.006, 0.0180, 2.4], [-0.640, 0.0205, -0.006, 0.0186, 2.4],
		[-0.800, 0.0195, -0.007, 0.0180, 2.4], [-0.905, 0.0180, -0.008, 0.0170, 2.4],
		[-0.915, 0.0160, -0.008, 0.0160, 2.4]], 2, 24))

	# --- butt plate (steel, checkered face implied by a slight dome) ------------------------
	steel.loft([MeshKit.ring(0.004, 0.0, -0.106, 0.0212, 0.067, 2.8, 28), MeshKit.ring(-0.004, 0.0, -0.106, 0.0209, 0.0665, 2.8, 28)])
	# trap door outline: a thin raised plate
	steel.block(Vector3(0, -0.105, 0.0045), Vector3(0.026, 0.07, 0.0015), 6.0)

	# --- receiver ------------------------------------------------------------------------------
	steel.loft(MeshKit.sections([
		[-0.266, 0.010, -0.012, 0.0105, 3.0], [-0.274, 0.019, -0.019, 0.0160, 4.0],
		[-0.336, 0.020, -0.020, 0.0166, 4.5]], 2, 24))
	# the well: two rails either side and the floor between them
	for side in [-1.0, 1.0]:
		steel.loft(MeshKit.sections([[-0.336, 0.020, -0.018, 0.0038, 4.0, side * 0.0128],
			[-0.456, 0.020, -0.018, 0.0038, 4.0, side * 0.0128]], 1, 12))
	steel.loft(MeshKit.sections([[-0.336, -0.002, -0.020, 0.0150, 4.0], [-0.456, -0.002, -0.020, 0.0150, 4.0]], 1, 16))
	steel.loft(MeshKit.sections([
		[-0.456, 0.020, -0.020, 0.0166, 4.5], [-0.488, 0.0185, -0.0185, 0.0160, 3.6],
		[-0.503, 0.0155, -0.0155, 0.0148, 2.6]], 2, 24))
	# rear sight: base, protective ears, aperture, elevation (left) and windage (right) drums
	steel.loft(MeshKit.sections([[-0.270, 0.027, 0.012, 0.0115, 4.0], [-0.302, 0.028, 0.012, 0.0115, 4.0]], 1, 16))
	for side in [-1.0, 1.0]:
		steel.block(Vector3(side * 0.0092, 0.036, -0.287), Vector3(0.0028, 0.020, 0.022), 5.0)
	steel.hoop(Vector3(0, SIGHT_Y, -0.285), Vector3(0, 0, 1), 0.0062, 0.0022, 18, 6)
	steel.block(Vector3(0, 0.031, -0.285), Vector3(0.006, 0.006, 0.004), 4.0)
	_knurled_drum(steel, Vector3(-0.0215, 0.024, -0.287), Vector3(-1, 0, 0), 0.0105, 0.0085)
	_knurled_drum(steel, Vector3(0.0200, 0.024, -0.287), Vector3(1, 0, 0), 0.0078, 0.0065)
	# clip latch button, left side of the receiver
	steel.cyl(Vector3(-0.0172, 0.003, -0.330), Vector3(1, 0, 0), 0.0035, 0.004, 10)

	# --- barrel, gas cylinder, front sight -----------------------------------------------------
	steel.tube(PackedVector3Array([Vector3(0, 0, -0.503), Vector3(0, 0, -0.62), Vector3(0, 0, -0.93), Vector3(0, 0, -1.104)]),
		[0.0140, 0.0128, 0.0112, 0.0099], 20)
	bore.cyl(Vector3(0, 0, -1.1045), Vector3(0, 0, 1), 0.0040, 0.0012, 12)
	# gas cylinder under the muzzle, its rear ring round the barrel, the front sight base
	steel.tube(PackedVector3Array([Vector3(0, -0.0215, -0.958), Vector3(0, -0.0215, -1.096)]), 0.0118, 18)
	steel.loft(MeshKit.sections([[-0.953, 0.0135, -0.0345, 0.0142, 2.4], [-0.972, 0.0135, -0.0345, 0.0142, 2.4]], 1, 22))
	steel.loft(MeshKit.sections([[-1.072, 0.0170, -0.0345, 0.0138, 2.6], [-1.098, 0.0170, -0.0345, 0.0138, 2.6]], 1, 22))
	for side in [-1.0, 1.0]:
		steel.loft(MeshKit.sections([[-1.076, 0.044, 0.012, 0.0016, 4.0, side * 0.0086],
			[-1.094, 0.044, 0.012, 0.0016, 4.0, side * 0.0086]], 1, 10))
	steel.loft(MeshKit.sections([[-1.080, SIGHT_Y + 0.001, 0.012, 0.0011, 4.0], [-1.090, SIGHT_Y + 0.001, 0.012, 0.0011, 4.0]], 1, 10))
	# gas cylinder lock screw with its valve slot, bayonet lug, stacking swivel
	steel.cyl(Vector3(0, -0.0215, -1.1015), Vector3(0, 0, 1), 0.0098, 0.007, 16)
	bore.block(Vector3(0, -0.0215, -1.1052), Vector3(0.012, 0.0022, 0.0008), 3.0)
	steel.block(Vector3(0, -0.0365, -1.050), Vector3(0.0072, 0.007, 0.028), 4.0)
	steel.hoop(Vector3(0, -0.047, -0.995), Vector3(1, 0, 0), 0.0105, 0.0019, 14, 5)
	steel.block(Vector3(0, -0.0355, -0.995), Vector3(0.006, 0.006, 0.010), 4.0)

	# --- bands and the rear handguard ferrule ------------------------------------------------
	steel.loft(MeshKit.sections([[-0.607, 0.0225, -0.0505, 0.0228, 2.7], [-0.625, 0.0225, -0.0505, 0.0228, 2.7]], 1, 26))
	steel.loft(MeshKit.sections([[-0.916, 0.0205, -0.0405, 0.0198, 2.7], [-0.934, 0.0205, -0.0405, 0.0198, 2.7]], 1, 26))
	steel.loft(MeshKit.sections([[-0.503, 0.0215, -0.004, 0.0190, 2.6], [-0.511, 0.0215, -0.004, 0.0190, 2.6]], 1, 22))
	# front sling swivel hangs under the lower band; rear swivel under the butt
	steel.block(Vector3(0, -0.054, -0.616), Vector3(0.006, 0.008, 0.010), 4.0)
	steel.hoop(Vector3(0, -0.066, -0.616), Vector3(1, 0, 0), 0.0105, 0.0019, 14, 5)
	steel.block(Vector3(0, -0.134, -0.118), Vector3(0.012, 0.004, 0.036), 5.0)
	steel.hoop(Vector3(0, -0.150, -0.118), Vector3(1, 0, 0), 0.0115, 0.0019, 14, 5)

	# --- trigger group: housing plate, guard, trigger, safety ----------------------------------
	steel.loft(MeshKit.sections([[-0.284, -0.057, -0.064, 0.0105, 4.0], [-0.392, -0.057, -0.064, 0.0105, 4.0]], 1, 16))
	steel.tube(_smooth_path([Vector3(0, -0.060, -0.291), Vector3(0, -0.080, -0.295), Vector3(0, -0.093, -0.308),
		Vector3(0, -0.097, -0.334), Vector3(0, -0.094, -0.362), Vector3(0, -0.081, -0.378), Vector3(0, -0.062, -0.386)], 4),
		0.0026, 8, Vector2(1.0, 2.2), true, true, Vector3.RIGHT)
	dark.tube(PackedVector3Array([Vector3(0, -0.062, -0.333), Vector3(0, -0.073, -0.337), Vector3(0, -0.084, -0.333)]),
		0.0019, 8, Vector2(1.0, 1.9), true, true, Vector3.RIGHT)
	steel.block(Vector3(0, -0.068, -0.389), Vector3(0.006, 0.006, 0.008), 4.0)

	# --- operating rod along the right side under the handguard lip ---------------------------
	steel.tube(PackedVector3Array([Vector3(0.0185, -0.004, -0.505), Vector3(0.0180, -0.006, -0.95)]), 0.0042, 10)
	var body := wood.commit(null, WeaponMats.wood())
	steel.commit(body, WeaponMats.parkerised())
	dark.commit(body, WeaponMats.dark_steel())
	bore.commit(body, WeaponMats.bore())
	_meshes.body = body

	# --- bolt + operating rod handle (the part that cycles) -----------------------------------
	var b := MeshKit.new()
	b.loft(MeshKit.sections([[-0.390, 0.0175, 0.000, 0.0088, 3.2], [-0.456, 0.0175, 0.000, 0.0088, 3.2]], 1, 16))
	b.cyl(Vector3(0.0, 0.0115, -0.405), Vector3(1, 0, 0), 0.0040, 0.020, 10)      # bolt lug roller
	b.tube(PackedVector3Array([Vector3(0.0165, 0.004, -0.452), Vector3(0.0280, 0.004, -0.454), Vector3(0.0360, 0.009, -0.461)]),
		0.0036, 10)
	b.tube(PackedVector3Array([Vector3(0.0360, 0.009, -0.461), Vector3(0.0385, 0.013, -0.466)]), 0.0062, 12)
	b.block(Vector3(0.0180, 0.003, -0.478), Vector3(0.005, 0.009, 0.050), 4.0)
	_meshes.bolt = b.commit(null, WeaponMats.parkerised())

	# --- the loaded en-bloc clip: rails and the two top cartridges behind the bolt ------------
	var cl := MeshKit.new()
	for side in [-1.0, 1.0]:
		cl.block(Vector3(side * 0.0098, 0.0035, -0.365), Vector3(0.0016, 0.012, 0.056), 5.0)
	var br := MeshKit.new()
	var cu := MeshKit.new()
	for c in [[0.0042, 0.0085], [-0.0042, 0.0010]]:
		var cx: float = c[0]; var cy: float = c[1]
		br.tube(PackedVector3Array([Vector3(cx, cy, -0.338), Vector3(cx, cy, -0.392)]), 0.0060, 14)
		br.tube(PackedVector3Array([Vector3(cx, cy, -0.392), Vector3(cx, cy, -0.400)]), [0.0060, 0.0045], 14)
		cu.tube(PackedVector3Array([Vector3(cx, cy, -0.400), Vector3(cx, cy, -0.412), Vector3(cx, cy, -0.420)]), [0.0045, 0.0040, 0.0012], 14)
	var clipm := cl.commit(null, WeaponMats.parkerised())
	br.commit(clipm, WeaponMats.brass())
	cu.commit(clipm, WeaponMats.copper())
	_meshes.clip = clipm

	# --- empty en-bloc clip (ejected): side walls + ribbed back, 58 x 22 x 16 mm ---------------
	var ce := MeshKit.new()
	for side in [-1.0, 1.0]:
		ce.block(Vector3(side * 0.0105, 0.0, 0.0), Vector3(0.0012, 0.058, 0.016), 6.0)
		ce.block(Vector3(side * 0.0080, 0.028, 0.002), Vector3(0.0050, 0.003, 0.012), 4.0)   # rim lips
	ce.block(Vector3(0, 0.0, 0.0078), Vector3(0.021, 0.058, 0.0012), 6.0)
	for y in [-0.018, 0.0, 0.018]:
		ce.block(Vector3(0, y, 0.0088), Vector3(0.016, 0.004, 0.0012), 4.0)
	_meshes.clip_empty = ce.commit(null, WeaponMats.parkerised())
	var cf := MeshKit.new()
	for side in [-1.0, 1.0]:
		cf.block(Vector3(side * 0.0105, 0.0, 0.0), Vector3(0.0012, 0.058, 0.016), 6.0)
	cf.block(Vector3(0, 0.0, 0.0078), Vector3(0.021, 0.058, 0.0012), 6.0)
	var rb := MeshKit.new()
	var rc := MeshKit.new()
	for r in range(8):
		var cx := -0.0045 if r % 2 == 0 else 0.0045
		var cy := -0.024 + r * 0.0068
		rb.tube(PackedVector3Array([Vector3(cx, cy, 0.007), Vector3(cx, cy, -0.055)]), 0.0058, 10)
		rc.tube(PackedVector3Array([Vector3(cx, cy, -0.055), Vector3(cx, cy, -0.066), Vector3(cx, cy, -0.078)]), [0.0045, 0.0040, 0.0012], 10)
	var fullm := cf.commit(null, WeaponMats.parkerised())
	rb.commit(fullm, WeaponMats.brass())
	rc.commit(fullm, WeaponMats.copper())
	_meshes.clip_full = fullm

	# --- sling: leather strap swivel to swivel, hanging or drawn tight -------------------------
	_meshes.sling_hang = _sling(0.105)
	_meshes.sling_taut = _sling(0.012)


## Catmull-Rom through the points, `per` samples per span.
static func _smooth_path(pts: Array, per: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in range(pts.size() - 1):
		var p0: Vector3 = pts[maxi(i - 1, 0)]; var p1: Vector3 = pts[i]
		var p2: Vector3 = pts[i + 1]; var p3: Vector3 = pts[mini(i + 2, pts.size() - 1)]
		for k in range(per):
			var t := float(k) / per
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t))
	out.append(pts[pts.size() - 1])
	return out


static func _knurled_drum(k: MeshKit, centre: Vector3, axis: Vector3, radius: float, width: float) -> void:
	var rings: Array = []
	var segs := 24
	for s in range(4):
		var d := (float(s) / 3.0 - 0.5) * width
		var pts := PackedVector3Array()
		var r := radius * (0.94 if s == 0 or s == 3 else 1.0)
		for i in range(segs):
			var t := TAU * float(i) / float(segs)
			var rr := r * (1.0 if i % 2 == 0 else 0.93)       # knurling
			pts.append(centre + axis * d + Vector3(0, cos(t) * rr, sin(t) * rr))
		rings.append(pts)
	k.loft(rings)


static func _sling(sag: float) -> ArrayMesh:
	var a := Vector3(0, -0.076, -0.616)
	var b := Vector3(0, -0.160, -0.118)
	var ctrl := (a + b) * 0.5 + Vector3(0, -sag * 2.0, 0)
	var pts := PackedVector3Array()
	for i in range(17):
		var t := float(i) / 16.0
		pts.append(a.lerp(ctrl, t).lerp(ctrl.lerp(b, t), t))
	var k := MeshKit.new()
	k.tube(pts, 0.0024, 10, Vector2(6.5, 1.0), true, true, Vector3.RIGHT)
	# a keeper and the buckle
	var mid := pts[5]
	var keep := MeshKit.new()
	keep.block(mid, Vector3(0.036, 0.009, 0.014), 5.0)
	keep.block(pts[11], Vector3(0.036, 0.008, 0.010), 5.0)
	var m := k.commit(null, WeaponMats.leather())
	keep.commit(m, WeaponMats.parkerised())
	return m
