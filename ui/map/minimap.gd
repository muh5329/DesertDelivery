class_name Minimap
extends Control
## The HUD's round minimap (top right, under the day card): the baked world map (map.gdshader,
## WorldMap's textures) centred on the courier, heading-up by default (Shift+Z: north-up), three
## zoom levels (Z / D-pad down) that widen with speed and in flight; over it, drawn per frame, only
## the markers: the courier's arrow, the other vehicles, the delivery's pickup and drop-off and the
## waypoint (pinned to the rim with a pointer when beyond it), stations, discovered camps and
## coves, colony halls, ships and lanes near a port, place names, the compass N.
## It lives in the HUD's root, so it steps back with the HUD (panels, the Mayor view, the journal).

const DIAMETER := 212.0
const RING := 7.0
const MIN_FONT := 16

var game: Game
var map: WorldMap
## The view as last drawn (tests read these).
var center := Vector2.ZERO
var radius_m := 450.0
var heading := 0.0
var mpp := 4.0
var _view: ColorRect
var _mat: ShaderMaterial
var _overlay: Control
var _font: SystemFont
var _markers: Array = []
var _labels: Array = []
var _marker_t := 0.0
var _snap := true


func setup(p_game: Game, p_map: WorldMap) -> void:
	game = p_game
	map = p_map
	name = "Minimap"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = SystemFont.new(); _font.font_names = PackedStringArray(["Georgia", "Noto Serif", "DejaVu Serif"])
	anchor_left = 1.0; anchor_right = 1.0; anchor_top = 0.0; anchor_bottom = 0.0
	offset_left = -26.0 - DIAMETER; offset_right = -26.0
	offset_top = 110.0; offset_bottom = 110.0 + DIAMETER
	_view = ColorRect.new()
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.position = Vector2(RING, RING); _view.size = Vector2(DIAMETER - 2 * RING, DIAMETER - 2 * RING)
	_mat = ShaderMaterial.new(); _mat.shader = load("res://ui/map/map.gdshader")
	_mat.set_shader_parameter("circle", true)
	_view.material = _mat
	add_child(_view)
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.position = Vector2.ZERO; _overlay.size = Vector2(DIAMETER, DIAMETER + 34)
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	map.apply_to(_mat)
	visible = map.ready()


## The textures arrived (WorldMap.finish after setup): hand them over.
func refresh_textures() -> void:
	map.apply_to(_mat)


func view_radius_px() -> float:
	return (DIAMETER - 2 * RING) * 0.5


## The view radius the minimap eases toward: the zoom level's, wider with speed, widest in flight.
func target_radius() -> float:
	var base: float = WorldMap.ZOOM_RADII[map.zoom_level]
	var rider := game.rider
	if rider == null: return base
	if rider.mode == Rider.Mode.FLYING:
		var alt: float = game.bike.altitude if game.bike else 0.0
		return maxf(base * 2.6, 1300.0 + alt * 2.0)
	var v: Vehicle = rider.vehicle
	var kmh := v.speed_kmh() if v and not rider.is_on_foot() else 0.0
	return base * lerpf(1.0, 2.4, clampf((kmh - 30.0) / 110.0, 0.0, 1.0))


func courier_bearing() -> float:
	var f := WorldMap._fwd(game.rider.courier())
	return atan2(f.x, -f.y)


func camera_bearing() -> float:
	var f := -game.cam.global_transform.basis.z
	return atan2(f.x, -f.z)


## Screen point (in this control) of a world point (x, z).
func to_screen(p: Vector2) -> Vector2:
	var d := (p - center) / mpp
	var c := cos(heading); var s := sin(heading)
	return Vector2(DIAMETER, DIAMETER) * 0.5 + Vector2(d.x * c + d.y * s, -d.x * s + d.y * c)


## The world point (x, z) under a screen point of this control.
func to_world(q: Vector2) -> Vector2:
	var l := (q - Vector2(DIAMETER, DIAMETER) * 0.5) * mpp
	var c := cos(heading); var s := sin(heading)
	return center + Vector2(l.x * c - l.y * s, l.x * s + l.y * c)


## On screen: visible, and so is the HUD layer it is drawn in (the Mayor view hides the layer).
func shown() -> bool:
	if not is_visible_in_tree(): return false
	var layer := get_canvas_layer_node()
	return layer == null or layer.visible


func _process(delta: float) -> void:
	if game == null or not game.booted or not shown(): return
	var cp := game.rider.courier().global_position
	center = Vector2(cp.x, cp.z)
	var want := target_radius()
	radius_m = want if _snap else lerpf(radius_m, want, 1.0 - exp(-delta * 2.2))
	_snap = false
	heading = camera_bearing() if map.rotate else 0.0
	mpp = radius_m / view_radius_px()
	_mat.set_shader_parameter("center", center)
	_mat.set_shader_parameter("mpp", mpp)
	_mat.set_shader_parameter("rotation", heading)
	_mat.set_shader_parameter("rect_size", _view.size)
	_mat.set_shader_parameter("detail_mix", clampf((5.0 - mpp) / 2.0, 0.0, 1.0))
	_marker_t -= delta
	if _marker_t <= 0.0:
		_marker_t = 0.1
		# far out, the courier counters would only crowd the core
		_markers = map.markers(center, radius_m * 1.45, false, radius_m < 900.0)
		_labels = map.labels(center, radius_m * 1.1, radius_m)
		# the waypoint is reached: it clears itself
		if map.has_waypoint and Vector2(map.waypoint.x, map.waypoint.z).distance_to(center) < 25.0:
			map.clear_waypoint()
			Events.message.emit("Waypoint reached.", 2.0)
	_overlay.queue_redraw()


## Snap the zoom next frame (no easing), e.g. after a zoom key or a long move.
func snap() -> void:
	_snap = true


func _draw_overlay() -> void:
	var ci := _overlay
	var c := Vector2(DIAMETER, DIAMETER) * 0.5
	var R := view_radius_px()
	# lanes first, under everything
	for m in _markers:
		if m.kind != &"lane": continue
		var pts := PackedVector2Array()
		var src: PackedVector2Array = m.points
		var step := maxi(1, src.size() / 80)
		for k in range(0, src.size(), step): pts.append(to_screen(src[k]))
		pts.append(to_screen(src[src.size() - 1]))
		_clip_polyline(ci, pts, c, R - 2.0)
	for l in _labels:
		var q := to_screen(l.pos) + Vector2(0, -16)
		if q.distance_to(c) > R - 18.0: continue
		if absf(q.y - c.y) < 16.0 and absf(q.x - c.x) < 60.0: q.y = c.y - 24.0   # never across the courier's arrow
		MapIcons.label(ci, _font, q, l.text, 17 if l.rank == 2 else MIN_FONT, MapIcons.CREAM, 4)
	var pinned: Array = []
	for m in _markers:
		if m.kind == &"lane": continue
		var q := to_screen(m.pos)
		if m.get("target", false):
			pinned.append([m, q]); continue
		if q.distance_to(c) > R - 6.0: continue
		MapIcons.marker(ci, m, q, 0.9, heading)
	# the pins last: inside, a pin; beyond the rim, a pointer on the rim toward it
	for pq in pinned:
		var m: Dictionary = pq[0]; var q: Vector2 = pq[1]
		if q.distance_to(c) <= R - 10.0:
			MapIcons.pin(ci, q, m.kind, 0.95)
		else:
			var dir := (q - c).normalized()
			MapIcons.pointer(ci, c + dir * (R - 9.0), dir, m.kind, 1.0)
	# the courier: his heading on the rotated map
	var b := courier_bearing() - heading
	MapIcons.arrow(ci, c, Vector2(sin(b), -cos(b)), 1.05)
	_draw_ring(ci, c, R)


func _clip_polyline(ci: CanvasItem, pts: PackedVector2Array, c: Vector2, R: float) -> void:
	var on := true
	for k in range(pts.size() - 1):
		var a := pts[k]; var b := pts[k + 1]
		if on and a.distance_to(c) < R and b.distance_to(c) < R:
			ci.draw_line(a, b, MapIcons.SEA_LANE, 2.0, true)
		on = not on


func _draw_ring(ci: CanvasItem, c: Vector2, R: float) -> void:
	var ring_r := R + RING * 0.5
	ci.draw_arc(c, ring_r + RING * 0.5 + 0.5, 0, TAU, 96, Color(0, 0, 0, 0.22), 4.0, true)
	ci.draw_arc(c, ring_r, 0, TAU, 96, HUD.PANEL, RING, true)
	ci.draw_arc(c, R, 0, TAU, 96, Color("877356"), 1.5, true)
	ci.draw_arc(c, R + RING, 0, TAU, 96, Color("877356"), 1.2, true)
	# ticks every 45 degrees, the cardinal ones longer; N in a red badge
	for k in range(8):
		var a := k * PI / 4.0 - heading
		var d := Vector2(sin(a), -cos(a))
		var l := 5.0 if k % 2 == 0 else 3.0
		ci.draw_line(c + d * (R + 1.0), c + d * (R + 1.0 + l), HUD.INK, 1.5 if k % 2 == 0 else 1.0)
	var n := Vector2(sin(-heading), -cos(-heading))
	var np := c + n * ring_r
	ci.draw_circle(np, 10.5, HUD.INK)
	ci.draw_circle(np, 9.0, Color(0.72, 0.2, 0.14))
	var w := _font.get_string_size("N", HORIZONTAL_ALIGNMENT_LEFT, -1, MIN_FONT).x
	ci.draw_string(_font, np + Vector2(-w * 0.5, 5.5), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, MIN_FONT, MapIcons.CREAM)
	# the scale and the keys under the rim
	var text := "%s  ·  Z zoom  ·  M map" % _scale_text()
	var tw := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, MIN_FONT).x
	var at := Vector2(c.x - tw * 0.5, DIAMETER + 20.0)
	ci.draw_string_outline(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, MIN_FONT, 5, HUD.INK)
	ci.draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, MIN_FONT, Color("f4e9cf"))


func _scale_text() -> String:
	return "%d m" % (roundi(radius_m / 10.0) * 10) if radius_m < 1000.0 else "%.1f km" % (radius_m / 1000.0)
