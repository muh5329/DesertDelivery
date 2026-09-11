class_name TruckCargo
extends Node3D
## A small, physical Tetris rack on the truck bed. The player positions a preview tetromino
## on a 4 x 6 grid, rotates it, and locks it into the load. Cargo must fit and touch the bed or
## another piece, so the resulting stack is an actual packing puzzle rather than a skin swap.

const WIDTH := 4
const HEIGHT := 6
const CELL := 0.43
const SHAPES := [
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)], # I
	[Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 2)], # L
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1)], # T
	[Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1)], # S
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)], # O
]
const COLOURS := [
	Color(0.75, 0.45, 0.20), Color(0.48, 0.62, 0.34), Color(0.78, 0.63, 0.27),
	Color(0.48, 0.58, 0.68), Color(0.66, 0.40, 0.30),
]

var build_mode := false
var cursor := Vector2i(0, 0)
var next_shape := 0
var rotation_steps := 0
var placed: Array[Dictionary] = []
var occupied: Dictionary = {}
var _pieces_root: Node3D
var _preview: Node3D
var _delivery_package: Node3D


func _ready() -> void:
	_pieces_root = Node3D.new(); _pieces_root.name = "PackedPieces"; add_child(_pieces_root)
	_preview = Node3D.new(); _preview.name = "Preview"; add_child(_preview)
	_build_delivery_package()
	# A couple of packed pieces make the truck read as a cargo vehicle from the first encounter.
	_force_place(4, 0, Vector2i(0, 0))
	_force_place(1, 0, Vector2i(2, 0))
	next_shape = 2
	cursor = Vector2i(0, 3)
	_rebuild()


func set_build_mode(v: bool) -> void:
	build_mode = v
	_preview.visible = v
	if v:
		_fit_cursor()
	_rebuild_preview()


func move_cursor(delta: Vector2i) -> void:
	if not build_mode or delta == Vector2i.ZERO: return
	cursor += delta
	_fit_cursor()
	_rebuild_preview()


func rotate_piece() -> void:
	if not build_mode: return
	rotation_steps = (rotation_steps + 1) % 4
	_fit_cursor()
	_rebuild_preview()


func place_piece() -> bool:
	if not build_mode: return false
	var cells := _cells(next_shape, rotation_steps, cursor)
	if not _valid(cells):
		return false
	placed.append({"shape": next_shape, "rotation": rotation_steps, "origin": cursor})
	for c in cells: occupied[c] = placed.size() - 1
	next_shape = (next_shape + 1) % SHAPES.size()
	rotation_steps = 0
	cursor = Vector2i(0, _first_open_row())
	_fit_cursor()
	_rebuild()
	return true


func remove_last() -> bool:
	if not build_mode or placed.is_empty(): return false
	placed.pop_back()
	_rebuild_occupancy()
	_rebuild()
	return true


func piece_count() -> int:
	return placed.size()


func block_count() -> int:
	return occupied.size()


func fill_ratio() -> float:
	return float(block_count()) / float(WIDTH * HEIGHT)


func set_package_visible(v: bool) -> void:
	var highest := -1
	for c in occupied.keys(): highest = maxi(highest, c.y)
	_delivery_package.position.y = float(highest + 1) * CELL + 0.30
	_delivery_package.visible = v


func status_text() -> String:
	return "Cargo %d/%d blocks" % [block_count(), WIDTH * HEIGHT]


func save_state() -> Dictionary:
	var out: Array = []
	for p in placed:
		out.append({"shape": p.shape, "rotation": p.rotation, "origin": p.origin})
	return {"placed": out, "next_shape": next_shape}


func load_state(data: Dictionary) -> void:
	placed.clear()
	for p in data.get("placed", []):
		var origin: Variant = p.get("origin", Vector2i.ZERO)
		if origin is Vector2:
			origin = Vector2i(int(origin.x), int(origin.y))
		elif origin is Array and origin.size() >= 2:
			origin = Vector2i(int(origin[0]), int(origin[1]))
		placed.append({"shape": int(p.get("shape", 0)), "rotation": int(p.get("rotation", 0)), "origin": origin})
	next_shape = int(data.get("next_shape", 0)) % SHAPES.size()
	_rebuild_occupancy()
	_rebuild()


func _force_place(shape_i: int, rot: int, origin: Vector2i) -> void:
	placed.append({"shape": shape_i, "rotation": rot, "origin": origin})
	for c in _cells(shape_i, rot, origin): occupied[c] = placed.size() - 1


func _cells(shape_i: int, rot: int, origin: Vector2i) -> Array[Vector2i]:
	var raw: Array[Vector2i] = []
	for source in SHAPES[shape_i]:
		var c: Vector2i = source
		for _step in range(rot): c = Vector2i(-c.y, c.x)
		raw.append(c)
	var mn := raw[0]
	for c in raw: mn = Vector2i(mini(mn.x, c.x), mini(mn.y, c.y))
	var out: Array[Vector2i] = []
	for c in raw: out.append(c - mn + origin)
	return out


func _valid(cells: Array[Vector2i]) -> bool:
	var supported := false
	for c in cells:
		if c.x < 0 or c.x >= WIDTH or c.y < 0 or c.y >= HEIGHT or occupied.has(c):
			return false
		if c.y == 0 or occupied.has(c + Vector2i(0, -1)): supported = true
	return supported


func _fit_cursor() -> void:
	var cells := _cells(next_shape, rotation_steps, Vector2i.ZERO)
	var max_cell := Vector2i.ZERO
	for c in cells: max_cell = Vector2i(maxi(max_cell.x, c.x), maxi(max_cell.y, c.y))
	cursor.x = clampi(cursor.x, 0, WIDTH - max_cell.x - 1)
	cursor.y = clampi(cursor.y, 0, HEIGHT - max_cell.y - 1)


func _first_open_row() -> int:
	for y in range(HEIGHT):
		for x in range(WIDTH):
			if not occupied.has(Vector2i(x, y)): return y
	return 0


func _rebuild_occupancy() -> void:
	occupied.clear()
	for i in range(placed.size()):
		var p := placed[i]
		for c in _cells(p.shape, p.rotation, p.origin): occupied[c] = i


func _rebuild() -> void:
	for child in _pieces_root.get_children(): child.queue_free()
	for i in range(placed.size()):
		var p := placed[i]
		var piece := Node3D.new(); piece.name = "Piece%d" % i; _pieces_root.add_child(piece)
		for c in _cells(p.shape, p.rotation, p.origin):
			_add_crate_cell(piece, c, COLOURS[p.shape % COLOURS.size()])
	_rebuild_preview()


func _rebuild_preview() -> void:
	for child in _preview.get_children(): child.queue_free()
	if not build_mode: return
	var cells := _cells(next_shape, rotation_steps, cursor)
	var ok := _valid(cells)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = (Color(0.35, 0.9, 0.45, 0.52) if ok else Color(0.95, 0.2, 0.15, 0.52))
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for c in cells:
		_preview.add_child(Mats.box(Vector3(CELL * 0.88, CELL * 0.88, CELL * 0.88), mat, _cell_pos(c) + Vector3(0, 0, -0.04)))


func _add_crate_cell(parent: Node3D, cell: Vector2i, colour: Color) -> void:
	var p := _cell_pos(cell)
	var box_mat := Mats.solid(colour, 0.88)
	var band := Mats.solid(Color(0.28, 0.20, 0.13), 0.82)
	parent.add_child(Mats.box(Vector3(CELL * 0.92, CELL * 0.92, CELL * 0.9), box_mat, p))
	parent.add_child(Mats.box(Vector3(CELL * 0.08, CELL * 0.94, CELL * 0.93), band, p + Vector3(0, 0, -0.005)))


func _cell_pos(c: Vector2i) -> Vector3:
	return Vector3((float(c.x) - (WIDTH - 1) * 0.5) * CELL, (float(c.y) + 0.5) * CELL, 0)


func _build_delivery_package() -> void:
	_delivery_package = Node3D.new(); _delivery_package.name = "DeliveryPackage"
	_delivery_package.position = Vector3(0, 0.30, 0)
	var cardboard := Mats.solid(Color(0.72, 0.55, 0.34), 0.9)
	var twine := Mats.solid(Color(0.91, 0.78, 0.48), 0.85)
	_delivery_package.add_child(Mats.box(Vector3(1.20, 0.58, 0.84), cardboard))
	_delivery_package.add_child(Mats.box(Vector3(0.08, 0.60, 0.87), twine))
	_delivery_package.add_child(Mats.box(Vector3(1.22, 0.08, 0.87), twine))
	_delivery_package.visible = false
	add_child(_delivery_package)
