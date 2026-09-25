class_name FullMap
extends CanvasLayer
## M (Start on a gamepad): the full-screen map on a parchment sheet. Drag or WASD / the left stick
## to pan, the wheel / +- / the triggers to zoom about the cursor; a left click (A at the cross)
## sets the waypoint the minimap and the compass show, a right click (X) clears it; C centres on
## the courier, R switches the minimap between heading-up and north-up. M, Esc or B closes.
## A modal panel of the PanelStack (frees the mouse, blocks the controls, the HUD steps back).

const MPP_MIN := 0.9
const MPP_MAX := 32.0
const MARGIN := 34.0
const LEGEND_W := 250.0
const MIN_FONT := 16

var game: Game
var map: WorldMap
var center := Vector2.ZERO
var mpp := 10.0
var _root: Control
var _sheet: Panel
var _view: ColorRect
var _mat: ShaderMaterial
var _overlay: Control
var _legend: Control
var _hint: Label
var _title: Label
var _font: SystemFont
var _open := false
var _drag := false
var _drag_from := Vector2.ZERO
var _drag_moved := 0.0
var _markers: Array = []
var _labels: Array = []
var _marker_t := 0.0
var _hover := Vector2(-1, -1)


func setup(p_game: Game, p_map: WorldMap) -> void:
	game = p_game
	map = p_map
	name = "FullMap"
	layer = 18
	_font = SystemFont.new(); _font.font_names = PackedStringArray(["Georgia", "Noto Serif", "DejaVu Serif"])
	_root = Control.new(); _root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var shade := ColorRect.new(); shade.color = Color(0.04, 0.05, 0.045, 0.72)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT); shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(shade)
	_sheet = Panel.new()
	_sheet.add_theme_stylebox_override("panel", MayorTheme.paper())
	_sheet.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sheet.offset_left = MARGIN; _sheet.offset_top = MARGIN; _sheet.offset_right = -MARGIN; _sheet.offset_bottom = -MARGIN
	_sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_sheet)
	_title = MayorTheme.label(_sheet, "MAP OF THE COUNTRY", 22, MayorTheme.INK)
	_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	_title.position = Vector2(22, 12)
	_title.add_theme_font_override("font", _font)
	_view = ColorRect.new()
	_view.anchor_right = 1.0; _view.anchor_bottom = 1.0
	_view.offset_left = 18; _view.offset_top = 52; _view.offset_right = -(LEGEND_W + 30); _view.offset_bottom = -48
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new(); _mat.shader = load("res://ui/map/map.gdshader")
	_mat.set_shader_parameter("circle", false)
	_view.material = _mat
	_sheet.add_child(_view)
	_overlay = Control.new()
	_overlay.anchor_right = 1.0; _overlay.anchor_bottom = 1.0
	_overlay.clip_contents = true
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	_view.add_child(_overlay)
	_legend = Control.new()
	_legend.anchor_left = 1.0; _legend.anchor_right = 1.0; _legend.anchor_bottom = 1.0
	_legend.offset_left = -(LEGEND_W + 12); _legend.offset_right = -12; _legend.offset_top = 52; _legend.offset_bottom = -48
	_legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_legend.draw.connect(_draw_legend)
	_sheet.add_child(_legend)
	_hint = MayorTheme.label(_sheet, "", 16, MayorTheme.MUTED)
	_hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	_hint.anchor_top = 1.0; _hint.anchor_bottom = 1.0; _hint.anchor_right = 1.0
	_hint.offset_left = 20; _hint.offset_top = -40; _hint.offset_bottom = -12; _hint.offset_right = -20
	_hint.add_theme_font_override("font", _font)
	_root.visible = false
	map.apply_to(_mat)


func refresh_textures() -> void:
	map.apply_to(_mat)


func is_open() -> bool:
	return _open


func toggle() -> void:
	if _open: close_panel()
	else: open_panel()


func open_panel() -> void:
	if _open or not map.ready(): return
	_open = true
	_root.visible = true
	var cp := game.rider.courier().global_position
	center = Vector2(cp.x, cp.z)
	mpp = 9.0
	_marker_t = 0.0
	_refresh_hint()
	if game.panels: game.panels.open(self)


func close_panel() -> void:
	if not _open: return
	_open = false
	_drag = false
	_root.visible = false
	if game.panels: game.panels.close(self)


func _refresh_hint() -> void:
	_hint.text = "Click: set waypoint  ·  Right click: clear  ·  Drag / WASD: pan  ·  Wheel: zoom  ·  C: centre on you  ·  R: minimap %s  ·  M / Esc: close" % ("heading-up" if map.rotate else "north-up")


## The world point (x, z) under a point of the map view.
func to_world(q: Vector2) -> Vector2:
	return center + (q - _view.size * 0.5) * mpp


func to_screen(p: Vector2) -> Vector2:
	return (p - center) / mpp + _view.size * 0.5


func zoom_at(q: Vector2, factor: float) -> void:
	var before := to_world(q)
	mpp = clampf(mpp * factor, MPP_MIN, MPP_MAX)
	center += before - to_world(q)
	_clamp_center()


func _clamp_center() -> void:
	center = center.clamp(Vector2(-12500, -12500), Vector2(12500, 12500))


func _input(event: InputEvent) -> void:
	if not _open: return
	var local := _view.get_local_mouse_position() if event is InputEventMouse else Vector2.ZERO
	var inside := Rect2(Vector2.ZERO, _view.size).has_point(local)
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP and inside: zoom_at(local, 1.0 / 1.18)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and inside: zoom_at(local, 1.18)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and inside:
				_drag = true; _drag_from = local; _drag_moved = 0.0
			elif not mb.pressed and _drag:
				_drag = false
				if _drag_moved < 5.0: _set_waypoint(to_world(local))
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT and inside:
			map.clear_waypoint()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		_hover = local if inside else Vector2(-1, -1)
		if _drag:
			var rel: Vector2 = (event as InputEventMouseMotion).relative
			_drag_moved += rel.length()
			center -= rel * mpp
			_clamp_center()
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_B, JOY_BUTTON_START: close_panel()
			JOY_BUTTON_A: _set_waypoint(center)
			JOY_BUTTON_X: map.clear_waypoint()
			JOY_BUTTON_Y: center = _courier()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE, KEY_M: close_panel()
			KEY_C: center = _courier()
			KEY_R:
				map.toggle_rotate(); _refresh_hint()
			KEY_EQUAL, KEY_KP_ADD: zoom_at(_view.size * 0.5, 1.0 / 1.4)
			KEY_MINUS, KEY_KP_SUBTRACT: zoom_at(_view.size * 0.5, 1.4)
			_: return
		get_viewport().set_input_as_handled()


## M / Start opens the map; Z / D-pad down cycles the minimap's zoom, Shift+Z its orientation.
func _unhandled_input(event: InputEvent) -> void:
	if _open or game == null or not game.booted: return
	if game.mayor != null and game.mayor.active: return
	if game.panels != null and (game.panels.any_open() or game.panels.just_closed()): return
	if event is InputEventKey and event.echo: return
	if event.is_action_pressed("map_open"):
		open_panel()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("map_zoom"):
		if event is InputEventKey and event.shift_pressed:
			Events.message.emit("Minimap: %s." % ("heading-up" if map.toggle_rotate() else "north-up"), 1.5)
		else:
			Events.message.emit("Minimap zoom: %s." % WorldMap.ZOOM_NAMES[map.cycle_zoom()], 1.2)
		get_viewport().set_input_as_handled()


func _courier() -> Vector2:
	var cp := game.rider.courier().global_position
	return Vector2(cp.x, cp.z)


func _set_waypoint(p: Vector2) -> void:
	map.set_waypoint(Vector3(p.x, 0.0, p.y))
	Events.message.emit("Waypoint set: %.1f km away." % (p.distance_to(_courier()) / 1000.0), 2.0)


func _process(delta: float) -> void:
	if not _open: return
	# keys and the left stick pan, the triggers zoom
	var pan := Vector2(Input.get_axis("steer_left", "steer_right"), Input.get_axis("accelerate", "brake"))
	var stick := Controls.radial_deadzone(Vector2(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), Input.get_joy_axis(0, JOY_AXIS_LEFT_Y)))
	pan += stick
	if pan.length() > 0.01:
		center += pan.limit_length(1.0) * 600.0 * mpp * delta
		_clamp_center()
	var trig := Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) - Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT)
	if absf(trig) > 0.1: zoom_at(_view.size * 0.5, exp(-trig * delta * 1.6))
	_mat.set_shader_parameter("center", center)
	_mat.set_shader_parameter("mpp", mpp)
	_mat.set_shader_parameter("rotation", 0.0)
	_mat.set_shader_parameter("rect_size", _view.size)
	_mat.set_shader_parameter("detail_mix", clampf((5.0 - mpp) / 2.0, 0.0, 1.0))
	_marker_t -= delta
	if _marker_t <= 0.0:
		_marker_t = 0.1
		var reach := _view.size.length() * 0.5 * mpp
		_markers = map.markers(center, reach, true, mpp < 6.0)
		_labels = map.labels(center, reach, mpp * 150.0)
	_overlay.queue_redraw()
	_legend.queue_redraw()


func _draw_overlay() -> void:
	var ci := _overlay
	var box := Rect2(Vector2.ZERO, _view.size)
	var s := 1.15
	for m in _markers:
		if m.kind != &"lane": continue
		var src: PackedVector2Array = m.points
		var pts := PackedVector2Array()
		var step := maxi(1, src.size() / 200)
		for k in range(0, src.size(), step): pts.append(to_screen(src[k]))
		pts.append(to_screen(src[src.size() - 1]))
		MapIcons.lane(ci, pts, 1.2)
	for l in _labels:
		var q := to_screen(l.pos)
		if not box.grow(40).has_point(q): continue
		MapIcons.label(ci, _font, q + Vector2(0, -16), l.text, 22 if l.rank == 2 else (18 if l.rank == 1 else MIN_FONT), MapIcons.CREAM, 5)
	var pinned: Array = []
	for m in _markers:
		if m.kind == &"lane": continue
		var q := to_screen(m.pos)
		if m.get("target", false):
			pinned.append([m, q]); continue
		if box.grow(-4).has_point(q): MapIcons.marker(ci, m, q, s)
	for pq in pinned:
		var m: Dictionary = pq[0]; var q: Vector2 = pq[1]
		if box.grow(-12).has_point(q):
			MapIcons.pin(ci, q, m.kind, 1.3)
		else:
			var c := box.get_center()
			var dir := (q - c).normalized()
			var t := minf(absf((box.size.x * 0.5 - 14.0) / dir.x) if absf(dir.x) > 0.001 else INF, absf((box.size.y * 0.5 - 14.0) / dir.y) if absf(dir.y) > 0.001 else INF)
			MapIcons.pointer(ci, c + dir * t, dir, m.kind, 1.3)
	var cp := _courier()
	var f := WorldMap._fwd(game.rider.courier())
	MapIcons.arrow(ci, to_screen(cp), f, 1.4)
	# the cross at the centre (the gamepad's waypoint aim) and the scale bar
	var cc := box.get_center()
	ci.draw_line(cc + Vector2(-9, 0), cc + Vector2(-3, 0), MapIcons.INK, 1.5)
	ci.draw_line(cc + Vector2(3, 0), cc + Vector2(9, 0), MapIcons.INK, 1.5)
	ci.draw_line(cc + Vector2(0, -9), cc + Vector2(0, -3), MapIcons.INK, 1.5)
	ci.draw_line(cc + Vector2(0, 3), cc + Vector2(0, 9), MapIcons.INK, 1.5)
	_draw_scale(ci, Vector2(18, box.size.y - 22))
	ci.draw_rect(box, Color("8f8265"), false, 2.0)


func _draw_scale(ci: CanvasItem, at: Vector2) -> void:
	var metres := [50, 100, 200, 500, 1000, 2000, 5000]
	var pick := 50
	for m in metres:
		if m / mpp <= 180.0: pick = m
	var w: float = pick / mpp
	ci.draw_rect(Rect2(at + Vector2(-6, -24), Vector2(w + 12, 34)), Color(MayorTheme.PAPER.r, MayorTheme.PAPER.g, MayorTheme.PAPER.b, 0.85))
	ci.draw_line(at, at + Vector2(w, 0), MapIcons.INK, 3.0)
	ci.draw_line(at + Vector2(0, -5), at + Vector2(0, 5), MapIcons.INK, 2.0)
	ci.draw_line(at + Vector2(w, -5), at + Vector2(w, 5), MapIcons.INK, 2.0)
	var text := "%d m" % pick if pick < 1000 else "%d km" % (pick / 1000)
	ci.draw_string(_font, at + Vector2(2, -9), text, HORIZONTAL_ALIGNMENT_LEFT, -1, MIN_FONT, MapIcons.INK)


var _ly := 0.0


func _legend_head(t: String) -> void:
	_legend.draw_string(_font, Vector2(4, _ly + 6), t, HORIZONTAL_ALIGNMENT_LEFT, -1, MIN_FONT, Color("5a4a33"))
	_ly += 30.0


func _legend_row(draw: Callable, t: String) -> void:
	draw.call(Vector2(18, _ly))
	_legend.draw_string(_font, Vector2(42, _ly + 6), t, HORIZONTAL_ALIGNMENT_LEFT, -1, MIN_FONT, MayorTheme.INK)
	_ly += 30.0


func _draw_legend() -> void:
	var ci := _legend
	_ly = 14.0
	_legend_head("LEGEND")
	_legend_row(func(p): MapIcons.arrow(ci, p, Vector2(0, -1), 1.0), "You")
	_legend_row(func(p): MapIcons.pin(ci, p + Vector2(0, 8), &"pickup", 0.85), "Pickup")
	_legend_row(func(p): MapIcons.pin(ci, p + Vector2(0, 8), &"dropoff", 0.85), "Drop-off")
	_legend_row(func(p): MapIcons.pin(ci, p + Vector2(0, 8), &"waypoint", 0.85), "Waypoint")
	_legend_row(func(p): MapIcons.vehicle(ci, p, &"bike", 1.0), "Bike")
	_legend_row(func(p): MapIcons.vehicle(ci, p, &"jeep", 1.0), "Jeep")
	_legend_row(func(p): MapIcons.vehicle(ci, p, &"cart", 1.0), "Cart")
	_legend_row(func(p): MapIcons.fuel(ci, p, 1.0), "Fuel station")
	_legend_row(func(p): MapIcons.counter(ci, p, 1.0), "Courier counter")
	_legend_row(func(p): MapIcons.camp(ci, p, 1.0), "Bandit camp")
	_legend_row(func(p): MapIcons.cove(ci, p, 1.0), "Pirate cove")
	_legend_row(func(p): MapIcons.colony(ci, p, 1.0), "Colony hall")
	_legend_row(func(p): MapIcons.ship(ci, p, Vector2(1, -0.4), 1.1), "Ship")
	_legend_row(func(p): ci.draw_line(p - Vector2(10, 0), p + Vector2(10, 0), MapIcons.SEA_LANE, 2.5), "Sea lane")
	_ly += 6.0
	_legend_head("ROADS")
	for r in [[Color(0.47, 0.2, 0.14), Color(0.93, 0.67, 0.27), "Highway"], [Color(0.44, 0.36, 0.27), Color(0.96, 0.93, 0.81), "Road"], [Color(0.5, 0.39, 0.27), Color(0.5, 0.39, 0.27), "Track"]]:
		_legend_row(func(p):
			ci.draw_line(p - Vector2(11, 0), p + Vector2(11, 0), r[0], 6.0)
			ci.draw_line(p - Vector2(11, 0), p + Vector2(11, 0), r[1], 3.5), r[2])
	if _hover.x >= 0.0:
		var d := to_world(_hover).distance_to(_courier())
		ci.draw_string(_font, Vector2(4, _legend.size.y - 10), "Cursor: %.1f km from you" % (d / 1000.0), HORIZONTAL_ALIGNMENT_LEFT, -1, MIN_FONT, MayorTheme.MUTED)
