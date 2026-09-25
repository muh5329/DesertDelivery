class_name MapIcons
extends RefCounted
## The map's markers, drawn with CanvasItem primitives (shared by the minimap and the full map),
## in the HUD's ink-and-parchment look. Every icon is centred on `at` and sized by `s` (1 = the
## minimap's size).

const INK := Color(0.16, 0.13, 0.10)
const CREAM := Color(0.98, 0.95, 0.88)
const RED := Color(0.80, 0.22, 0.16)
const GOLD := Color(0.93, 0.70, 0.22)
const BLUE := Color(0.20, 0.45, 0.78)
const PUMP := Color(0.95, 0.55, 0.12)
const GREEN := Color("2f5d52")
const SEA_LANE := Color(0.14, 0.36, 0.56, 0.85)


static func arrow(ci: CanvasItem, at: Vector2, dir: Vector2, s := 1.0, col := RED) -> void:
	dir = dir.normalized() if dir.length() > 0.001 else Vector2(0, -1)
	var side := Vector2(-dir.y, dir.x)
	var tip := at + dir * 11.0 * s
	var l := at - dir * 7.0 * s + side * 7.5 * s
	var r := at - dir * 7.0 * s - side * 7.5 * s
	var notch := at - dir * 3.0 * s
	var pts := PackedVector2Array([tip, l, notch, r])
	var halo := PackedVector2Array([tip + dir * 2.5 * s, l + (side - dir) * 2.0 * s, notch - dir * 2.5 * s, r + (-side - dir) * 2.0 * s])
	ci.draw_colored_polygon(halo, CREAM)
	ci.draw_colored_polygon(pts, col)
	ci.draw_polyline(PackedVector2Array([tip, l, notch, r, tip]), INK, 1.4 * s, true)


static func _disc(ci: CanvasItem, at: Vector2, r: float, fill: Color) -> void:
	ci.draw_circle(at, r + 1.6, INK)
	ci.draw_circle(at, r, fill)


static func fuel(ci: CanvasItem, at: Vector2, s := 1.0) -> void:
	_disc(ci, at, 7.0 * s, PUMP)
	ci.draw_rect(Rect2(at + Vector2(-3.0, -4.0) * s, Vector2(5.0, 8.5) * s), INK)
	ci.draw_rect(Rect2(at + Vector2(-2.0, -3.0) * s, Vector2(3.0, 2.5) * s), PUMP.lightened(0.5))
	ci.draw_line(at + Vector2(2.0, -2.5) * s, at + Vector2(4.0, 1.5) * s, INK, 1.3 * s)


static func counter(ci: CanvasItem, at: Vector2, s := 1.0) -> void:
	var r := Rect2(at - Vector2(7, 5.5) * s, Vector2(14, 11) * s)
	ci.draw_rect(r.grow(1.6), INK)
	ci.draw_rect(r, RED)
	ci.draw_polyline(PackedVector2Array([r.position + Vector2(1.5, 1.5) * s, at + Vector2(0, 1.0) * s, r.position + Vector2(r.size.x - 1.5 * s, 1.5 * s)]), CREAM, 1.4 * s)


static func camp(ci: CanvasItem, at: Vector2, s := 1.0, cleared := false) -> void:
	var c := Color(0.55, 0.52, 0.48) if cleared else Color(0.55, 0.16, 0.10)
	_disc(ci, at, 7.5 * s, c)
	# a tent
	ci.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -5) * s, at + Vector2(5, 4) * s, at + Vector2(-5, 4) * s]), CREAM)
	ci.draw_line(at + Vector2(0, -1) * s, at + Vector2(0, 4) * s, c, 1.6 * s)
	if cleared: ci.draw_line(at + Vector2(-6, 6) * s, at + Vector2(6, -6) * s, INK, 1.6 * s)


static func cove(ci: CanvasItem, at: Vector2, s := 1.0, cleared := false) -> void:
	var c := Color(0.55, 0.52, 0.48) if cleared else Color(0.10, 0.10, 0.12)
	_disc(ci, at, 7.5 * s, c)
	# a black flag with a white cross
	ci.draw_line(at + Vector2(-3.5, 5) * s, at + Vector2(-3.5, -5) * s, CREAM, 1.4 * s)
	ci.draw_rect(Rect2(at + Vector2(-3, -5) * s, Vector2(7.5, 5.5) * s), CREAM)
	ci.draw_line(at + Vector2(-1.5, -4) * s, at + Vector2(3, -0.5) * s, c, 1.2 * s)
	ci.draw_line(at + Vector2(3, -4) * s, at + Vector2(-1.5, -0.5) * s, c, 1.2 * s)
	if cleared: ci.draw_line(at + Vector2(-6, 6) * s, at + Vector2(6, -6) * s, INK, 1.6 * s)


static func colony(ci: CanvasItem, at: Vector2, s := 1.0) -> void:
	var p := PackedVector2Array([at + Vector2(0, -8) * s, at + Vector2(7, -2) * s, at + Vector2(7, 6) * s, at + Vector2(-7, 6) * s, at + Vector2(-7, -2) * s])
	var halo := PackedVector2Array()
	for q in p: halo.append(at + (q - at) * 1.25)
	ci.draw_colored_polygon(halo, INK)
	ci.draw_colored_polygon(p, GREEN)
	ci.draw_rect(Rect2(at + Vector2(-2, 1) * s, Vector2(4, 5) * s), CREAM)


static func ship(ci: CanvasItem, at: Vector2, dir: Vector2, s := 1.0) -> void:
	dir = dir.normalized() if dir.length() > 0.001 else Vector2(0, -1)
	var side := Vector2(-dir.y, dir.x)
	var hull := PackedVector2Array([at + dir * 8 * s, at + side * 3.5 * s, at - dir * 7 * s + side * 3 * s, at - dir * 7 * s - side * 3 * s, at - side * 3.5 * s])
	var halo := PackedVector2Array()
	for q in hull: halo.append(at + (q - at) * 1.3)
	ci.draw_colored_polygon(halo, CREAM)
	ci.draw_colored_polygon(hull, Color(0.45, 0.28, 0.16))
	ci.draw_line(at - dir * 2 * s, at + dir * 3 * s, CREAM, 2.0 * s)


static func lane(ci: CanvasItem, pts: PackedVector2Array, s := 1.0) -> void:
	# dashes along the route
	var on := true
	for k in range(pts.size() - 1):
		if on: ci.draw_line(pts[k], pts[k + 1], SEA_LANE, 2.0 * s, true)
		on = not on


static func vehicle(ci: CanvasItem, at: Vector2, kind: StringName, s := 1.0) -> void:
	match kind:
		&"bike":
			_disc(ci, at, 7.5 * s, Color(0.78, 0.2, 0.15))
			ci.draw_arc(at + Vector2(-3, 1.5) * s, 2.3 * s, 0, TAU, 12, CREAM, 1.3 * s)
			ci.draw_arc(at + Vector2(3, 1.5) * s, 2.3 * s, 0, TAU, 12, CREAM, 1.3 * s)
			ci.draw_line(at + Vector2(-3, 1.5) * s, at + Vector2(0.5, -2.5) * s, CREAM, 1.3 * s)
			ci.draw_line(at + Vector2(0.5, -2.5) * s, at + Vector2(3, 1.5) * s, CREAM, 1.3 * s)
		&"jeep":
			_disc(ci, at, 7.5 * s, Color(0.42, 0.46, 0.30))
			ci.draw_rect(Rect2(at + Vector2(-4.5, -3) * s, Vector2(9, 4.5) * s), CREAM)
			ci.draw_circle(at + Vector2(-2.5, 2.5) * s, 1.6 * s, CREAM)
			ci.draw_circle(at + Vector2(2.5, 2.5) * s, 1.6 * s, CREAM)
		&"cart":
			_disc(ci, at, 6.5 * s, Color(0.55, 0.40, 0.24))
			ci.draw_rect(Rect2(at + Vector2(-4, -3) * s, Vector2(8, 4) * s), CREAM)
			ci.draw_circle(at + Vector2(0, 2.5) * s, 1.7 * s, CREAM)


## A pin (pickup, drop-off, waypoint): a teardrop whose point is at `at`.
static func pin(ci: CanvasItem, at: Vector2, kind: StringName, s := 1.0) -> void:
	var col := GOLD if kind == &"pickup" else (BLUE if kind == &"waypoint" else RED)
	var head := at + Vector2(0, -13) * s
	ci.draw_colored_polygon(PackedVector2Array([at, head + Vector2(-6.2, 2.5) * s, head + Vector2(6.2, 2.5) * s]), INK)
	ci.draw_circle(head, 8.2 * s, INK)
	ci.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -2) * s, head + Vector2(-5, 2.5) * s, head + Vector2(5, 2.5) * s]), col)
	ci.draw_circle(head, 6.6 * s, col)
	match kind:
		&"pickup":
			ci.draw_rect(Rect2(head + Vector2(-4, -3) * s, Vector2(8, 6) * s), Color(0.55, 0.36, 0.22))
			ci.draw_line(head + Vector2(0, -3) * s, head + Vector2(0, 3) * s, GOLD.lightened(0.3), 1.2 * s)
		&"dropoff":
			ci.draw_line(head + Vector2(-2.5, 4) * s, head + Vector2(-2.5, -4) * s, CREAM, 1.4 * s)
			ci.draw_colored_polygon(PackedVector2Array([head + Vector2(-2, -4) * s, head + Vector2(4, -2) * s, head + Vector2(-2, 0) * s]), CREAM)
		&"waypoint":
			ci.draw_circle(head, 2.6 * s, CREAM)


## An off-edge pointer: a small wedge on the rim pointing out toward something beyond the view.
static func pointer(ci: CanvasItem, at: Vector2, dir: Vector2, kind: StringName, s := 1.0) -> void:
	var col := GOLD if kind == &"pickup" else (BLUE if kind == &"waypoint" else RED)
	dir = dir.normalized()
	var side := Vector2(-dir.y, dir.x)
	var tip := at + dir * 9.0 * s
	var tri := PackedVector2Array([tip, at - dir * 3.0 * s + side * 7.0 * s, at - dir * 3.0 * s - side * 7.0 * s])
	var halo := PackedVector2Array([tip + dir * 2.2 * s, at - dir * 4.5 * s + side * 9.0 * s, at - dir * 4.5 * s - side * 9.0 * s])
	ci.draw_colored_polygon(halo, INK)
	ci.draw_colored_polygon(tri, col)


static func label(ci: CanvasItem, font: Font, at: Vector2, text: String, size: int, col := CREAM, outline := 4) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var p := at + Vector2(-w * 0.5, size * 0.35)
	ci.draw_string_outline(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, INK)
	ci.draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


## Draw one marker record from WorldMap.markers at a screen point.
static func marker(ci: CanvasItem, m: Dictionary, at: Vector2, s := 1.0, rot := 0.0) -> void:
	match m.kind:
		&"fuel": fuel(ci, at, s)
		&"counter": counter(ci, at, s)
		&"camp": camp(ci, at, s, m.get("cleared", false))
		&"cove": cove(ci, at, s, m.get("cleared", false))
		&"colony": colony(ci, at, s)
		&"ship": ship(ci, at, (m.heading as Vector2).rotated(-rot), s)
		&"bike", &"jeep", &"cart": vehicle(ci, at, m.kind, s)
		&"pickup", &"dropoff", &"waypoint": pin(ci, at, m.kind, s)
