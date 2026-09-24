class_name CombatHud
extends Control
## The fighting half of the HUD, in the same parchment-and-ink style as the rest:
##   * crosshair: four ticks whose gap IS the shot cone (hip wide, aimed tight, blooming with
##     each shot), a dot when aiming; a white hit marker, a red kill marker, gold for heads
##   * the Garand panel: eight cartridge pips for the clip, reserve clips (and loose rounds),
##     a reload bar, and a "ping!" that jumps out when the empty clip flies
##   * health bar, red damage-direction arcs round the crosshair, a red vignette on hits and
##     at low health (with a heartbeat), and the black of being knocked out
## Reads GunSystem / PlayerVitals / the camera each frame; listens to Events for hits.

const PANEL := Color(0.94, 0.89, 0.76, 0.95)
const INK := Color(0.16, 0.13, 0.10)
const CREAM := Color(0.98, 0.96, 0.9)
const BRASS := Color(0.86, 0.68, 0.32)
const COPPER := Color(0.74, 0.44, 0.27)
const RED := Color(0.72, 0.18, 0.13)
const GOLD := Color(1.0, 0.82, 0.3)

var gun: GunSystem
var vitals: PlayerVitals
var camera: Camera3D
var rider: Rider
var font: Font

var _cross: Control
var _panel: Panel
var _pips: Control
var _reserve: Label
var _title: Label
var _ping: Label
var _ping_t := 0.0
var _health_bar: ProgressBar
var _health_label: Label
var _vignette: TextureRect
var _black: ColorRect
var _down_label: Label
var _marker_t := 0.0
var _marker_kind := &"hit"
var _hurt_flash := 0.0
var _arcs: Array = []           # [world_from, t]
var _beat_t := 0.0
var _spread_px := 10.0
var marker_count := 0           # hit markers shown (tests)
var kill_markers := 0


func setup(p_gun: GunSystem, p_vitals: PlayerVitals, p_camera: Camera3D, p_rider: Rider, p_font: Font) -> void:
	gun = p_gun; vitals = p_vitals; camera = p_camera; rider = p_rider; font = p_font
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	Events.target_damaged.connect(func(_id, _amt, head, killed): _marker(killed, head))
	Events.player_damaged.connect(func(amount, from): _hurt(amount, from))
	Events.clip_pinged.connect(func(): _ping_t = 1.0)


func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	if font: l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build() -> void:
	# vignette under everything
	_vignette = TextureRect.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var g := Gradient.new()
	g.set_color(0, Color(0.55, 0.05, 0.03, 0.0))
	g.add_point(0.55, Color(0.55, 0.05, 0.03, 0.0))
	g.set_color(g.get_point_count() - 1, Color(0.55, 0.04, 0.02, 0.85))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.05, 0.5)
	gt.width = 256; gt.height = 256
	_vignette.texture = gt
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.modulate.a = 0.0
	add_child(_vignette)

	_cross = Control.new()
	_cross.set_anchors_preset(Control.PRESET_CENTER)
	_cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cross)
	_cross.draw.connect(_draw_cross)

	# the Garand panel, bottom right
	_panel = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.set_corner_radius_all(8)
	sb.border_color = Color("877356")
	sb.set_border_width_all(1)
	sb.shadow_color = Color(0, 0, 0, 0.25)
	sb.shadow_size = 6
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_panel.position = Vector2(-300, -186)
	_panel.size = Vector2(270, 84)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	_title = _label("M1 GARAND", 13, INK)
	_title.position = Vector2(14, 6)
	_panel.add_child(_title)
	_pips = Control.new()
	_pips.position = Vector2(14, 28)
	_pips.size = Vector2(160, 46)
	_pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_pips)
	_pips.draw.connect(_draw_pips)
	_reserve = _label("", 22, INK)
	_reserve.position = Vector2(176, 30)
	_reserve.size = Vector2(84, 40)
	_reserve.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_panel.add_child(_reserve)
	_ping = _label("ping!", 30, GOLD)
	_ping.add_theme_color_override("font_outline_color", INK)
	_ping.add_theme_constant_override("outline_size", 8)
	_ping.position = Vector2(70, -46)
	_ping.visible = false
	_panel.add_child(_ping)

	# health, bottom left above the stamina bar
	_health_label = _label("Health", 16, Color("f4e9cf"))
	_health_label.add_theme_color_override("font_outline_color", INK)
	_health_label.add_theme_constant_override("outline_size", 3)
	_health_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_health_label.position = Vector2(26, -148)
	add_child(_health_label)
	_health_bar = ProgressBar.new()
	_health_bar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_health_bar.position = Vector2(26, -122)
	_health_bar.size = Vector2(210, 16)
	_health_bar.show_percentage = false
	_health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new(); fill.bg_color = Color(0.74, 0.26, 0.18); fill.set_corner_radius_all(5)
	var bg := StyleBoxFlat.new(); bg.bg_color = Color(0.94, 0.89, 0.76, 0.85); bg.set_corner_radius_all(5)
	bg.border_color = Color("877356"); bg.set_border_width_all(1)
	_health_bar.add_theme_stylebox_override("fill", fill)
	_health_bar.add_theme_stylebox_override("background", bg)
	add_child(_health_bar)

	_black = ColorRect.new()
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.color = Color(0.03, 0.02, 0.02, 0.0)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_black)
	_down_label = _label("Knocked out...", 40, CREAM)
	_down_label.add_theme_color_override("font_outline_color", INK)
	_down_label.add_theme_constant_override("outline_size", 8)
	_down_label.set_anchors_preset(Control.PRESET_CENTER)
	_down_label.position = Vector2(-300, -30)
	_down_label.size = Vector2(600, 60)
	_down_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_down_label.modulate.a = 0.0
	add_child(_down_label)


# ------------------------------------------------------------------------------ events
func _marker(killed: bool, head: bool) -> void:
	_marker_t = 1.0
	_marker_kind = &"kill" if killed else (&"head" if head else &"hit")
	marker_count += 1
	if killed: kill_markers += 1


func _hurt(amount: float, from: Vector3) -> void:
	_hurt_flash = clampf(_hurt_flash + amount / 30.0 + 0.25, 0.0, 1.0)
	_arcs.append([from, 1.6])
	if _arcs.size() > 6: _arcs.remove_at(0)


# ------------------------------------------------------------------------------ drawing
func _spread_to_px(deg: float) -> float:
	var cam := camera
	var h := get_viewport_rect().size.y
	if cam == null: return deg * 10.0
	return tan(deg_to_rad(deg)) / tan(deg_to_rad(cam.fov * 0.5)) * h * 0.5


func _draw_cross() -> void:
	var c := CREAM
	var o := Color(0.1, 0.08, 0.06, 0.85)
	var on_foot := rider != null and rider.is_on_foot()
	var armed := on_foot and gun and gun.has_gun and not gun.player.swimming and ((rider.is_aiming()) or gun.is_recently_fired() or gun.reloading)
	if armed:
		var gap := clampf(_spread_px, 4.0, 90.0)
		for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			_cross.draw_line(d * gap, d * (gap + 11.0), o, 4.5)
			_cross.draw_line(d * gap, d * (gap + 11.0), c, 2.0)
		if gun.ads_blend > 0.6:
			_cross.draw_circle(Vector2.ZERO, 2.6, o)
			_cross.draw_circle(Vector2.ZERO, 1.6, c)
		if gun.reloading:
			var k := gun.reload_progress()
			_cross.draw_arc(Vector2.ZERO, gap + 18.0, -PI * 0.5, -PI * 0.5 + TAU * k, 40, o, 5.0, true)
			_cross.draw_arc(Vector2.ZERO, gap + 18.0, -PI * 0.5, -PI * 0.5 + TAU * k, 40, BRASS, 2.5, true)
	if _marker_t > 0.0:
		var a := clampf(_marker_t * 1.6, 0.0, 1.0)
		var col := CREAM
		var size := 12.0
		if _marker_kind == &"kill": col = RED; size = 17.0
		elif _marker_kind == &"head": col = GOLD; size = 14.0
		col.a = a
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var dn: Vector2 = d.normalized()
			_cross.draw_line(dn * 6.0, dn * size, Color(0.1, 0.08, 0.06, a * 0.85), 5.0)
			_cross.draw_line(dn * 6.0, dn * size, col, 2.5)
	# damage direction: an arc on the side the shot came from
	if camera:
		var fwd := -camera.global_transform.basis.z; fwd.y = 0.0
		var cam_ang := atan2(fwd.x, -fwd.z)
		var me := camera.global_position
		if gun and gun.player: me = gun.player.global_position
		for e in _arcs:
			var to: Vector3 = e[0] - me
			var ang := atan2(to.x, -to.z) - cam_ang - PI * 0.5
			var alpha := clampf(float(e[1]) / 1.2, 0.0, 1.0)
			_cross.draw_arc(Vector2.ZERO, 130.0, ang - 0.32, ang + 0.32, 20, Color(0.1, 0.05, 0.03, 0.6 * alpha), 11.0, true)
			_cross.draw_arc(Vector2.ZERO, 130.0, ang - 0.30, ang + 0.30, 20, Color(0.85, 0.2, 0.12, 0.9 * alpha), 6.0, true)


func _draw_pips() -> void:
	if gun == null: return
	var loaded := gun.ammo
	for i in range(GunSystem.CLIP):
		var x := i * 19.0
		var full := i < loaded
		var body := Rect2(x, 14, 12, 30)
		if full:
			_pips.draw_rect(body, BRASS)
			_pips.draw_colored_polygon(PackedVector2Array([Vector2(x, 14), Vector2(x + 12, 14), Vector2(x + 9, 4), Vector2(x + 6, 0), Vector2(x + 3, 4)]), COPPER)
			_pips.draw_rect(Rect2(x, 40, 12, 4), BRASS.darkened(0.3))
		else:
			_pips.draw_rect(body, Color(0.6, 0.55, 0.45, 0.35))
			_pips.draw_rect(body, Color("877356"), false, 1.0)
	if gun.reloading:
		_pips.draw_rect(Rect2(0, 48, 150 * gun.reload_progress(), 3), INK)


func _process(delta: float) -> void:
	if gun == null: return
	var parent := get_parent() as Control
	if parent and size != parent.size: size = parent.size
	var on_foot := rider != null and rider.is_on_foot()
	_spread_px = lerpf(_spread_px, _spread_to_px(gun.current_spread()), 1.0 - exp(-18.0 * delta))
	_marker_t = maxf(0.0, _marker_t - delta * 2.5)
	for e in _arcs: e[1] -= delta
	_arcs = _arcs.filter(func(e): return e[1] > 0.0)
	_cross.queue_redraw()
	_pips.queue_redraw()
	_panel.visible = on_foot or gun.reloading
	var extra := " +%d" % gun.loose_rounds if gun.loose_rounds > 0 else ""
	_reserve.text = "×%d%s" % [gun.reserve_clips, extra]
	_reserve.add_theme_color_override("font_color", RED if gun.reserve_clips == 0 else INK)
	_title.text = "M1 GARAND  ·  RELOADING" if gun.reloading else ("M1 GARAND  ·  V reload" if gun.ammo < GunSystem.CLIP and gun.reserve_clips > 0 else "M1 GARAND")
	# the ping: jumps up out of the panel and fades
	if _ping_t > 0.0:
		_ping_t = maxf(0.0, _ping_t - delta * 1.1)
		_ping.visible = true
		_ping.position.y = -30.0 - (1.0 - _ping_t) * 34.0
		_ping.modulate.a = clampf(_ping_t * 2.0, 0.0, 1.0)
		_ping.scale = Vector2.ONE * (1.0 + (1.0 - _ping_t) * 0.25)
	else:
		_ping.visible = false
	# health
	if vitals:
		var h := vitals.health
		_health_bar.max_value = h.max_health
		_health_bar.value = h.current
		_health_label.text = "Health  %d" % roundi(h.current)
		var low := vitals.low_health()
		_hurt_flash = maxf(0.0, _hurt_flash - delta * 0.9)
		var pulse := 0.0
		if low:
			pulse = 0.35 + 0.2 * sin(Time.get_ticks_msec() * 0.001 * TAU * 1.2)
			_beat_t -= delta
			if _beat_t <= 0.0:
				_beat_t = 0.85
				gun.sounds.play(&"heartbeat", null, -3.0)
		var hurt := clampf(maxf(_hurt_flash * 0.8, pulse * (1.0 - h.fraction() / 0.3)), 0.0, 1.0)
		_vignette.modulate.a = hurt
		_black.color.a = vitals.fade
		_down_label.modulate.a = vitals.fade if vitals.is_down() else maxf(0.0, vitals.fade - 0.3)
