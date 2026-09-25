class_name CartVisual
extends Node3D
## Red Sea Baron's wooden cart: a plank bed with slatted sides and a tailboard, iron-shod
## wheels on a live axle with red fenders, a drawbar, and the rolled-forward canopy. The rigid
## parts are baked into one mesh per material (its StaticBatcher did the same); the wheels spin
## on their own pivots, and the drawbar swings to meet whatever it is hitched to.
##
## The cart's front is -z. Its origin is on the ground under the axle line's middle.

const WOOD := Color("996943")
const FRAME := Color("596460")
const METAL := Color("b39358")
const WHEEL_RADIUS := 0.44
const AXLE_Z := 0.25
## The drawbar's hinge on the front of the bed, and its eye's rest position (cart space).
const TONGUE_ROOT := Vector3(0, 0.50, -1.0)
const TONGUE_REST := Vector3(0, 0.50, -2.0)

var wheels: Array[Node3D] = []
var load_view: CargoLoadView
var drawbar: Node3D
var _drawbar_len := 1.0


func _ready() -> void:
	var rigid := Node3D.new(); rigid.name = "Body"; add_child(rigid)
	var wood := Mats.solid(WOOD, 0.85)
	var frame := Mats.solid(FRAME, 0.6, 0.3)
	var metal := Mats.solid(METAL, 0.5, 0.45)
	var fender := Mats.solid(Color("a84e3d"), 0.7)
	var boards: Array[Material] = [wood, Mats.solid(WOOD.lightened(0.03), 0.85), Mats.solid(WOOD.lightened(0.06), 0.85)]
	var wood_dark := Mats.solid(WOOD.darkened(0.06), 0.85)
	for i in range(5):
		rigid.add_child(Mats.box(Vector3(0.30, 0.10, 2.0), wood if i % 2 == 0 else wood_dark, Vector3(-0.66 + i * 0.33, 0.66, 0)))
	for side in [-1.0, 1.0]:
		var x: float = side * 0.80
		for i in range(2):          # two boards: the load shows over the sides
			rigid.add_child(Mats.box(Vector3(0.08, 0.15, 2.0), boards[i], Vector3(x, 0.80 + i * 0.17, 0)))
		for z in [-0.93, 0.93]:
			rigid.add_child(Mats.box(Vector3(0.12, 0.66, 0.10), metal, Vector3(x, 1.01, z)))
			for y in [0.8, 1.2]:
				rigid.add_child(Mats.cylinder(0.034, 0.03, frame, Vector3(x + side * 0.065, y, z), Vector3(0, 0, 90), 6))
		# the chassis rail under the bed, and the fender over the wheel
		rigid.add_child(Mats.limb(Vector3(side * 0.58, 0.52, -0.95), Vector3(side * 0.58, 0.52, 0.9), 0.055, frame))
		rigid.add_child(_fender(side, fender))
		var wheel := _wheel(Vector3(side * 0.95, WHEEL_RADIUS, AXLE_Z), frame, metal)
		wheels.append(wheel)
	for i in range(2):
		rigid.add_child(Mats.box(Vector3(1.52, 0.15, 0.08), boards[i], Vector3(0, 0.80 + i * 0.17, 0.95)))
		rigid.add_child(Mats.box(Vector3(1.52, 0.15, 0.08), boards[i], Vector3(0, 0.80 + i * 0.17, -0.95)))
	rigid.add_child(Mats.limb(Vector3(-1.04, WHEEL_RADIUS, AXLE_Z), Vector3(1.04, WHEEL_RADIUS, AXLE_Z), 0.05, frame))
	# two tail reflectors, so it reads at night behind the courier
	var red := Mats.solid(Color(0.75, 0.10, 0.08), 0.4, 0.0, Color(0.35, 0.02, 0.0))
	rigid.add_child(Mats.box(Vector3(0.14, 0.10, 0.04), red, Vector3(-0.62, 0.72, 1.0)))
	rigid.add_child(Mats.box(Vector3(0.14, 0.10, 0.04), red, Vector3(0.62, 0.72, 1.0)))
	CartCanopy.build(rigid)
	_batch(rigid)
	_build_drawbar(frame, metal)
	load_view = CargoLoadView.new(); load_view.name = "Load"; add_child(load_view)
	var slots: Array[Vector3] = []
	for level in 2:
		for z in [0.62, 0.02, -0.58]:
			for x in [-0.36, 0.36]:
				slots.append(Vector3(x, 0.72 + level * 0.46, z))
	load_view.setup(slots, 20.0)


func _fender(side: float, mat: Material) -> Node3D:
	var n := Node3D.new()
	for i in range(7):
		var a0 := lerpf(-1.1, 1.1, i / 7.0)
		var a1 := lerpf(-1.1, 1.1, (i + 1) / 7.0)
		var r := WHEEL_RADIUS + 0.07
		var p0 := Vector3(side * 0.95, WHEEL_RADIUS + cos(a0) * r, AXLE_Z + sin(a0) * r)
		var p1 := Vector3(side * 0.95, WHEEL_RADIUS + cos(a1) * r, AXLE_Z + sin(a1) * r)
		n.add_child(Mats.box(Vector3(0.24, 0.025, p0.distance_to(p1) + 0.01), mat, (p0 + p1) * 0.5, Vector3(rad_to_deg((a0 + a1) * 0.5), 0, 0)))
	return n


func _wheel(at: Vector3, frame: Material, metal: Material) -> Node3D:
	var pivot := Node3D.new(); pivot.name = "Wheel"; pivot.position = at; add_child(pivot)
	var tyre := Mats.solid(Color("293632"), 0.8, 0.2)
	var spokes := Mats.solid(WOOD.darkened(0.1), 0.8)
	pivot.add_child(Mats.torus(WHEEL_RADIUS - 0.06, WHEEL_RADIUS, tyre, Vector3.ZERO, Vector3(0, 0, 90)))
	pivot.add_child(Mats.torus(WHEEL_RADIUS - 0.10, WHEEL_RADIUS - 0.055, spokes, Vector3.ZERO, Vector3(0, 0, 90)))
	pivot.add_child(Mats.cylinder(0.09, 0.16, metal, Vector3.ZERO, Vector3(0, 0, 90), 10))
	for i in range(8):
		var a := TAU * i / 8.0
		pivot.add_child(Mats.limb(Vector3.ZERO, Vector3(0, cos(a), sin(a)) * (WHEEL_RADIUS - 0.08), 0.022, spokes))
	_batch(pivot)
	return pivot


func _build_drawbar(frame: Material, metal: Material) -> void:
	drawbar = Node3D.new(); drawbar.name = "Drawbar"; drawbar.position = TONGUE_ROOT; add_child(drawbar)
	var bar := Node3D.new(); bar.name = "Bar"; drawbar.add_child(bar)
	# two arms from the bed's front corners to one eye, along -z of the pivot (length 1)
	bar.add_child(Mats.limb(Vector3(-0.42, 0, 0.02), Vector3(0, 0, -1.0), 0.045, metal))
	bar.add_child(Mats.limb(Vector3(0.42, 0, 0.02), Vector3(0, 0, -1.0), 0.045, metal))
	bar.add_child(Mats.limb(Vector3(0, 0, 0.0), Vector3(0, 0, -1.0), 0.05, frame))
	_batch(bar)
	var eye := Mats.torus(0.035, 0.07, frame, Vector3(0, 0, -1.02), Vector3(0, 0, 0))
	eye.name = "Eye"; drawbar.add_child(eye)
	aim_drawbar_local(TONGUE_REST)


## Swing the drawbar so its eye meets `local_eye` (cart visual space).
func aim_drawbar_local(local_eye: Vector3) -> void:
	var d := local_eye - TONGUE_ROOT
	var length := clampf(d.length(), 0.6, 2.6)
	if d.length() < 0.05: d = Vector3(0, 0, -1)
	var fwd := d.normalized()
	var basis := Basis.looking_at(fwd, Vector3.UP)
	drawbar.basis = basis
	var bar: Node3D = drawbar.get_node("Bar")
	bar.scale = Vector3(1, 1, length)
	drawbar.get_node("Eye").position = Vector3(0, 0, -length - 0.02)
	_drawbar_len = length


func set_parcel_visible(v: bool) -> void:
	if load_view: load_view.set_parcel_visible(v)


## Wheel spin from signed rolling distance (Red Sea Baron: floor-plane displacement).
func animate_travel(distance: float) -> void:
	for wheel in wheels: wheel.rotation.x = fmod(wheel.rotation.x - distance / WHEEL_RADIUS, TAU)


## One mesh per material out of every MeshInstance3D under `root` (the static batcher).
static func _batch(root: Node3D) -> void:
	var groups: Dictionary = {}
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		if m.mesh == null: continue
		var mat: Material = m.material_override
		if not groups.has(mat): groups[mat] = []
		groups[mat].append(m)
	for mat: Material in groups:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for m: MeshInstance3D in groups[mat]:
			st.append_from(m.mesh, 0, root.global_transform.affine_inverse() * m.global_transform if root.is_inside_tree() else _rel(root, m))
		var out := MeshInstance3D.new()
		out.mesh = st.commit()
		out.material_override = mat
		root.add_child(out)
	for mat: Material in groups:
		for m: MeshInstance3D in groups[mat]:
			m.get_parent().remove_child(m)
			m.free()


static func _rel(root: Node3D, n: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf
