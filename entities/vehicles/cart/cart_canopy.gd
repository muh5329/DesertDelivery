class_name CartCanopy
extends RefCounted
## Red Sea Baron's fixed curved cover: one elliptical cross-section shared by the double-sided
## canvas mesh and a convex collision shape. Here the canvas is rolled forward over the front
## third of the bed (FRONT..BACK), so the load behind it is on show; the bare hoops stand over
## the rest of the bed.
const HALF_WIDTH: float = 0.86
const HALF_LENGTH: float = 1.03
const EAVE_HEIGHT: float = 1.62
const RISE: float = 0.52
const SEGMENTS: int = 12
## The canvas' ends along z (the cart's front is -z).
const FRONT: float = -1.03
const BACK: float = -0.30
static var cloth: StandardMaterial3D


static func point(index: int, z: float) -> Vector3:
	var angle := -PI / 2 + PI * index / SEGMENTS
	return Vector3(HALF_WIDTH * sin(angle), EAVE_HEIGHT + RISE * cos(angle), z)


static func collision_points() -> PackedVector3Array:
	var points := PackedVector3Array()
	for i in range(SEGMENTS + 1):
		for z in [FRONT, BACK]: points.append(point(i, z))
	for side in [-1.0, 1.0]:
		for z in [FRONT, BACK]: points.append(Vector3(side * 0.82, 1.30, z))
	return points


static func build(parent: Node3D) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(SEGMENTS):
		for corner in [[i, FRONT], [i + 1, FRONT], [i, BACK], [i, BACK], [i + 1, FRONT], [i + 1, BACK]]:
			var angle: float = -PI / 2 + PI * int(corner[0]) / SEGMENTS
			surface.set_normal(Vector3(sin(angle) / HALF_WIDTH, cos(angle) / RISE, 0).normalized())
			surface.add_vertex(point(int(corner[0]), float(corner[1])))
	var cover := MeshInstance3D.new()
	cover.name = "Canopy"
	cover.mesh = surface.commit()
	if cloth == null:
		cloth = Mats.solid(Color("d5c6a5"), 0.95)
		cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	cover.material_override = cloth
	parent.add_child(cover)
	var brass := Mats.solid(Color("b39358"), 0.5, 0.4)
	var strap := Mats.solid(Color("715d40"), 0.8)
	# the hoops: over the canvas' ends and bare over the load
	for z in [FRONT + 0.06, BACK + 0.02, 0.35, 0.96]:
		for i in range(SEGMENTS):
			parent.add_child(Mats.limb(point(i, z) - Vector3.UP * 0.018, point(i + 1, z) - Vector3.UP * 0.018, 0.018, brass))
	for side in [-1.0, 1.0]:
		parent.add_child(Mats.limb(Vector3(side * 0.84, EAVE_HEIGHT, -0.98), Vector3(side * 0.84, EAVE_HEIGHT, 0.98), 0.024, strap))
		for z in [-0.95, 0.95]:
			parent.add_child(Mats.limb(Vector3(side * 0.82, 0.67, z), Vector3(side * 0.84, EAVE_HEIGHT + 0.02, z), 0.034, brass))
