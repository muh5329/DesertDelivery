class_name HUD
extends CanvasLayer
## In-game HUD styled after the reference: package/compass badge top-left, day card top-right,
## speedometer strip bottom-centre, objective + messages.

var bike: Bike
var gm: GameManager
var camera: Camera3D
var player: Node3D
var rider: Rider
var _on_foot := false

var _speed_label: Label
var _needle: Control
var _objective: Label
var _distance: Label
var _message: Label
var _msg_timer := 0.0
var _msg_queue: Array = []
var _compass: Control
var _deliveries: Label
var _timer_label: Label
var _package_badge: Panel
var _controls: Label
var _controls_timer := 14.0
var _prompt_bg: Panel
var _title: Label
var _crosshair: Control
var _speed_group: Array = []
var _gun_label: Label
var _mode_label: Label
var _cans_hit := 0
var _cans_total := 0
var _has_gun := false
var _title_t := 5.0

const PANEL := Color(0.97, 0.94, 0.86, 0.92)
const INK := Color(0.16, 0.13, 0.10)
const GREEN := Color(0.36, 0.62, 0.30)


func setup(p_bike: Bike, p_gm: GameManager, p_cam: Camera3D) -> void:
	bike = p_bike
	gm = p_gm
	camera = p_cam
	gm.message.connect(show_message)
	gm.job_changed.connect(_on_job_changed)
	_build()


func _panel(pos: Vector2, size: Vector2, radius: float = 10.0) -> Panel:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.set_corner_radius_all(int(radius))
	sb.border_color = INK
	sb.set_border_width_all(3)
	sb.shadow_color = Color(0, 0, 0, 0.25)
	sb.shadow_size = 6
	p.add_theme_stylebox_override("panel", sb)
	p.position = pos
	p.size = size
	return p


func _label(text: String, size: int, col: Color = INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# --- top-left: package / compass badge
	_package_badge = _panel(Vector2(28, 26), Vector2(120, 120), 60)
	root.add_child(_package_badge)
	_compass = Control.new()
	_compass.position = Vector2(60, 60)
	_compass.size = Vector2.ZERO
	_package_badge.add_child(_compass)
	_compass.draw.connect(_draw_compass)
	_distance = _label("", 20)
	_distance.position = Vector2(30, 150)
	_distance.size = Vector2(120, 30)
	_distance.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_distance)

	# --- top-right: day card + deliveries
	var day := _panel(Vector2(-250, 26), Vector2(220, 78), 6)
	day.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	day.position = Vector2(-250, 26)
	root.add_child(day)
	var d1 := _label("Fri.", 34); d1.position = Vector2(16, 6); day.add_child(d1)
	var d2 := _label("Morning", 14); d2.position = Vector2(18, 48); day.add_child(d2)
	var d3 := _label("SPRING", 12); d3.position = Vector2(140, 8); day.add_child(d3)
	var d4 := _label("5", 40); d4.position = Vector2(155, 22); day.add_child(d4)
	_deliveries = _label("Deliveries 0/4", 18)
	_deliveries.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_deliveries.position = Vector2(-250, 112)
	root.add_child(_deliveries)
	_timer_label = _label("0:00", 18)
	_timer_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_timer_label.position = Vector2(-90, 112)
	root.add_child(_timer_label)

	# --- objective banner (top centre)
	_objective = _label("", 22)
	_objective.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_objective.position = Vector2(-300, 30)
	_objective.size = Vector2(600, 40)
	_objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_objective.add_theme_color_override("font_color", Color(0.98, 0.96, 0.9))
	_objective.add_theme_color_override("font_outline_color", INK)
	_objective.add_theme_constant_override("outline_size", 6)
	root.add_child(_objective)

	# --- message toast (centre)
	_message = _label("", 26)
	_message.set_anchors_preset(Control.PRESET_CENTER)
	_message.position = Vector2(-400, 120)
	_message.size = Vector2(800, 50)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.add_theme_color_override("font_color", Color(1.0, 0.95, 0.8))
	_message.add_theme_color_override("font_outline_color", INK)
	_message.add_theme_constant_override("outline_size", 8)
	root.add_child(_message)

	# --- speedometer strip (bottom centre)
	var strip := _panel(Vector2(-260, -84), Vector2(520, 58), 8)
	strip.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	strip.position = Vector2(-260, -84)
	root.add_child(strip)
	_speed_group.append(strip)
	for i in range(7):
		var t := _label(str(i * 50), 18)
		t.position = Vector2(26 + i * 70 - 12, 8)
		t.size = Vector2(48, 30)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		strip.add_child(t)
	var bar := ColorRect.new()
	bar.color = GREEN
	bar.position = Vector2(20, 44)
	bar.size = Vector2(480, 6)
	strip.add_child(bar)
	_needle = Control.new()
	_needle.position = Vector2(26, 28)
	strip.add_child(_needle)
	_needle.draw.connect(_draw_needle)
	_speed_label = _label("", 14)
	_speed_label.position = Vector2(-80, -110)
	_speed_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_speed_label.position = Vector2(-60, -104)
	_speed_label.size = Vector2(120, 20)
	_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speed_label.add_theme_color_override("font_color", Color(0.98, 0.96, 0.9))
	_speed_label.add_theme_color_override("font_outline_color", INK)
	_speed_label.add_theme_constant_override("outline_size", 5)
	root.add_child(_speed_label)
	_speed_group.append(_speed_label)
	# round gauges either side (fuel / engine) like the reference
	for sx in [-320.0, 268.0]:
		var g := _panel(Vector2(sx, -90), Vector2(52, 52), 26)
		g.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		g.position = Vector2(sx, -90)
		root.add_child(g)
		_speed_group.append(g)
		var ring := Control.new(); ring.position = Vector2(26, 26); g.add_child(ring)
		ring.draw.connect(func(): ring.draw_arc(Vector2.ZERO, 16, PI * 0.75, PI * 2.25, 24, GREEN, 5.0, true))

	# --- crosshair (only with the pistol, on foot)
	_crosshair = Control.new()
	_crosshair.set_anchors_preset(Control.PRESET_CENTER)
	_crosshair.visible = false
	root.add_child(_crosshair)
	_crosshair.draw.connect(func():
		var c := Color(0.98, 0.96, 0.9)
		var o := Color(0.1, 0.08, 0.06, 0.85)
		_crosshair.draw_arc(Vector2.ZERO, 9, 0, TAU, 24, o, 4.5, true)
		_crosshair.draw_arc(Vector2.ZERO, 9, 0, TAU, 24, c, 2.0, true)
		for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			_crosshair.draw_line(d * 12, d * 20, o, 4.5)
			_crosshair.draw_line(d * 12, d * 20, c, 2.0))
	_gun_label = _label("", 18, Color(0.98, 0.96, 0.9))
	_gun_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_gun_label.position = Vector2(-460, -140)
	_gun_label.size = Vector2(430, 60)
	_gun_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_gun_label.add_theme_color_override("font_outline_color", INK)
	_gun_label.add_theme_constant_override("outline_size", 6)
	root.add_child(_gun_label)
	_mode_label = _label("", 16, Color(0.98, 0.96, 0.9))
	_mode_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_mode_label.position = Vector2(-330, -80)
	_mode_label.size = Vector2(300, 50)
	_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_mode_label.add_theme_color_override("font_outline_color", INK)
	_mode_label.add_theme_constant_override("outline_size", 6)
	root.add_child(_mode_label)

	# --- title card (fades out)
	_title = _label("DESERT DELIVERY", 64, Color(0.98, 0.95, 0.86))
	_title.set_anchors_preset(Control.PRESET_CENTER)
	_title.position = Vector2(-400, -140)
	_title.size = Vector2(800, 90)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_color_override("font_outline_color", INK)
	_title.add_theme_constant_override("outline_size", 10)
	root.add_child(_title)
	var sub := _label("Ride. Collect. Deliver.", 24, Color(0.98, 0.95, 0.86))
	sub.position = Vector2(0, 80)
	sub.size = Vector2(800, 30)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_outline_color", INK)
	sub.add_theme_constant_override("outline_size", 6)
	_title.add_child(sub)

	# --- controls hint (bottom left, fades out)
	_prompt_bg = _panel(Vector2(28, -150), Vector2(330, 118), 8)
	_prompt_bg.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_prompt_bg.position = Vector2(28, -150)
	root.add_child(_prompt_bg)
	_controls = _label("W/S ride · A/D steer · Space handbrake · R reset\nE hop off / on the bike · T wings (plane mode)\nOn foot: WASD walk · Shift run · Space jump · F fire\nStop inside a glowing ring to collect / deliver.", 15)
	_controls.position = Vector2(14, 10)
	_prompt_bg.add_child(_controls)


func _draw_compass() -> void:
	# arrow pointing toward the target relative to camera heading + a small package glyph
	var c := _compass
	c.draw_circle(Vector2.ZERO, 44, Color(0.98, 0.96, 0.90))
	c.draw_arc(Vector2.ZERO, 44, 0, TAU, 48, INK, 3.0, true)
	var ang := _target_angle()
	var dir := Vector2(sin(ang), -cos(ang))
	var tip := dir * 40
	var l := dir.rotated(2.6) * 22
	var r := dir.rotated(-2.6) * 22
	var col := Color(0.86, 0.25, 0.18)
	c.draw_colored_polygon(PackedVector2Array([tip, l, Vector2.ZERO, r]), col)
	# package glyph in the centre
	c.draw_rect(Rect2(-11, -8, 22, 16), Color(0.55, 0.36, 0.22))
	c.draw_line(Vector2(0, -8), Vector2(0, 8), Color(0.85, 0.72, 0.4), 2.0)
	c.draw_line(Vector2(-11, 0), Vector2(11, 0), Color(0.85, 0.72, 0.4), 2.0)


func _target_angle() -> float:
	if not gm or gm.stage == GameManager.Stage.DONE: return 0.0
	var to := gm.target_position() - _actor_pos()
	to.y = 0.0
	if to.length() < 0.1: return 0.0
	var cam_f := -camera.global_transform.basis.z
	cam_f.y = 0.0
	cam_f = cam_f.normalized()
	var world_ang := atan2(to.x, -to.z)
	var cam_ang := atan2(cam_f.x, -cam_f.z)
	return world_ang - cam_ang


func _draw_needle() -> void:
	var kmh := bike.speed_kmh() if bike else 0.0
	var x := clampf(kmh / 300.0, 0.0, 1.0) * 420.0
	_needle.draw_colored_polygon(PackedVector2Array([Vector2(x - 5, 22), Vector2(x + 5, 22), Vector2(x, -6)]), Color(0.86, 0.22, 0.16))


func _actor_pos() -> Vector3:
	return player.global_position if (_on_foot and player) else bike.global_position


func set_gun(v: bool) -> void:
	_has_gun = v


func set_cans(h: int, t: int) -> void:
	_cans_hit = h
	_cans_total = t


func set_mode(bk: Bike, pl: Player, gn: GunSystem) -> void:
	var on_foot := rider.is_on_foot() if rider else false
	_on_foot = on_foot
	for n in _speed_group:
		n.visible = not on_foot
	_crosshair.visible = on_foot and _has_gun and not pl.swimming and ((rider.last_intent.aim if rider else false) or gn.is_recently_fired())
	_crosshair.queue_redraw()
	if _has_gun:
		_gun_label.text = "Pistol  %d/%d   Cans %d/%d%s" % [gn.ammo, gn.max_ammo, gn.targets_hit, gn.targets_total, "   (hold RMB to aim)" if on_foot else ""]
	else:
		_gun_label.text = ""
	if on_foot:
		_mode_label.text = "Swimming" if pl.swimming else "On foot  —  E near the bike to ride"
	elif bk.airborne:
		_mode_label.text = "Flying  —  S up · W down · Shift boost  —  altitude %d m" % int(bk.altitude)
	elif bk.wings_out:
		_mode_label.text = "Plane mode  —  W past %d km/h, then S to lift off · T folds wings" % int(bk.takeoff_speed * 3.6)
	else:
		_mode_label.text = "E hop off · T wings"


func show_message(text: String, duration: float) -> void:
	if _msg_timer > 0.8 and _message.text != "":
		_msg_queue.append([text, duration])
		return
	_message.text = text
	_message.modulate.a = 1.0
	_msg_timer = duration


func _on_job_changed(job: Dictionary, st: String) -> void:
	_deliveries.text = "Deliveries %d/%d" % [gm.deliveries, gm.jobs.size()]
	if job.is_empty():
		_objective.text = "All packages delivered — nice riding!"
		return
	if st == "pickup":
		_objective.text = "Collect: %s  →  at %s" % [job["item"], job["from"]]
	else:
		_objective.text = "Deliver: %s  →  to %s" % [job["item"], job["to"]]
	_deliveries.text = "Deliveries %d/%d" % [gm.deliveries, gm.jobs.size()]


func _process(delta: float) -> void:
	if not bike: return
	_needle.queue_redraw()
	_compass.queue_redraw()
	_speed_label.text = "%d km/h" % int(bike.speed_kmh())
	if gm and gm.stage != GameManager.Stage.DONE:
		var d := (gm.target_position() - _actor_pos()).length()
		_distance.text = "%d m" % int(d)
	else:
		_distance.text = ""
	_timer_label.text = GameManager.format_time(gm.elapsed) if gm else ""
	if _msg_timer > 0.0:
		_msg_timer -= delta
		_message.modulate.a = clampf(_msg_timer * 2.0, 0.0, 1.0)
		if _msg_timer <= 0.0:
			_message.text = ""
			if not _msg_queue.is_empty():
				var nxt: Array = _msg_queue.pop_front()
				show_message(nxt[0], nxt[1])
	if _title_t > 0.0:
		_title_t -= delta
		_title.modulate.a = clampf(_title_t * 0.8, 0.0, 1.0)
		if _title_t <= 0.0:
			_title.visible = false
	if _controls_timer > 0.0:
		_controls_timer -= delta
		if _controls_timer < 2.0:
			_prompt_bg.modulate.a = clampf(_controls_timer * 0.5, 0.0, 1.0)
		if _controls_timer <= 0.0:
			_prompt_bg.visible = false
