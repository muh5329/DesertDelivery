class_name HUD
extends CanvasLayer
## In-game HUD styled after the reference: package/compass badge top-left, day card top-right,
## speedometer strip bottom-centre, objective + messages.

var bike: Bike
var gm: DeliverySystem
var camera: Camera3D
var player: Node3D
var rider: Rider
var _on_foot := false

var _speed_label: Label
var _needle: Control
var _objective: Label
## An open urgent supply job from a colony (UrgentSupply), under the objective.
var _urgent: Label
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
var combat: CombatHud
var _speed_group: Array = []
var _gun_label: Label
var _mode_label: Label
var _cans_hit := 0
var _cans_total := 0
var _has_gun := false
var _title_t := 5.0
var _font: SystemFont
var _service_hint: Label
var _fuel_gauge: Control
var _engine_gauge: Control
var _cargo_label: Label
var _stamina_bar: ProgressBar
var _stamina_label: Label

const PANEL := Color(0.94, 0.89, 0.76, 0.95)
const INK := Color(0.16, 0.13, 0.10)
const GREEN := Color(0.36, 0.62, 0.30)


func setup(p_bike: Bike, p_gm: DeliverySystem, p_cam: Camera3D) -> void:
	bike = p_bike
	gm = p_gm
	camera = p_cam
	# the HUD listens to the world; nothing has to know the HUD exists
	Events.message.connect(show_message)
	Events.job_changed.connect(_on_job_changed)
	Events.gun_picked_up.connect(func(): set_gun(true))
	Events.can_hit.connect(func(_id, h, t): set_cans(h, t))
	_build()
	_on_job_changed(gm.current_job(), &"dropoff" if gm.stage==DeliverySystem.Stage.TO_DROPOFF else &"pickup")


func _panel(pos: Vector2, size: Vector2, radius: float = 10.0) -> Panel:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.set_corner_radius_all(int(radius))
	sb.border_color = Color("877356")
	sb.set_border_width_all(1)
	sb.shadow_color = Color(0, 0, 0, 0.25)
	sb.shadow_size = 6
	p.add_theme_stylebox_override("panel", sb)
	p.position = pos
	p.size = size
	return p


func _label(text: String, size: int, col: Color = INK) -> Label:
	var l := Label.new()
	l.text = text
	if _font: l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


func _build() -> void:
	_font=SystemFont.new(); _font.font_names=PackedStringArray(["Georgia","Noto Serif","DejaVu Serif"])
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# --- top-left: package / compass badge
	_package_badge = _panel(Vector2(26, 26), Vector2(88, 88), 44)
	root.add_child(_package_badge)
	_compass = Control.new()
	_compass.position = Vector2(44, 44)
	_compass.scale = Vector2.ONE * .72
	_compass.size = Vector2.ZERO
	_package_badge.add_child(_compass)
	_compass.draw.connect(_draw_compass)
	_distance = _label("", 20)
	_distance.position = Vector2(14, 116)
	_distance.size = Vector2(112, 26)
	_distance.add_theme_color_override("font_color",Color("f4e9cf"))
	_distance.add_theme_color_override("font_outline_color",INK)
	_distance.add_theme_constant_override("outline_size",3)
	_distance.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_distance)

	# Live calendar and resident catalogue are provided by ResidentCatalogue.
	_deliveries = _label("", 16, Color("f4e9cf"))
	_deliveries.add_theme_color_override("font_outline_color",INK)
	_deliveries.add_theme_constant_override("outline_size",3)
	_deliveries.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_deliveries.position = Vector2(-390, 76)
	root.add_child(_deliveries)
	_timer_label = _label("", 18)
	_timer_label.visible=false
	_timer_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_timer_label.position = Vector2(-80, 76)
	root.add_child(_timer_label)

	# --- objective banner (top centre)
	_objective = _label("", 18)
	_objective.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_objective.offset_left=134; _objective.offset_right=-475
	_objective.offset_top=30; _objective.offset_bottom=94
	_objective.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	_objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_objective.add_theme_color_override("font_color", Color(0.98, 0.96, 0.9))
	_objective.add_theme_color_override("font_outline_color", INK)
	_objective.add_theme_constant_override("outline_size", 3)
	root.add_child(_objective)
	_urgent = _label("", 15)
	_urgent.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_urgent.offset_left=134; _urgent.offset_right=-475
	_urgent.offset_top=92; _urgent.offset_bottom=116
	_urgent.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_urgent.add_theme_color_override("font_color", Color(1.0, 0.78, 0.42))
	_urgent.add_theme_color_override("font_outline_color", INK)
	_urgent.add_theme_constant_override("outline_size", 3)
	root.add_child(_urgent)

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
		var t := _label(str(i * 30), 18)
		t.position = Vector2(26 + i * 70 - 12, 8)
		t.size = Vector2(48, 30)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		strip.add_child(t)
	var bar := ColorRect.new()
	bar.color = Color("887858")
	bar.position = Vector2(20, 44)
	bar.size = Vector2(480, 1)
	strip.add_child(bar)
	for tick in range(37):
		var mark:=ColorRect.new(); mark.color=Color("a39578")
		mark.position=Vector2(26+tick*420.0/36.0,35)
		mark.size=Vector2(1,9 if tick%6==0 else 4); strip.add_child(mark)
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
	# Live fuel and workshop gauges share the actual journey state.
	for sx in [-320.0, 268.0]:
		var g := _panel(Vector2(sx, -90), Vector2(52, 52), 26)
		g.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		g.position = Vector2(sx, -90)
		root.add_child(g)
		_speed_group.append(g)
		var ring := Control.new(); ring.position = Vector2(26, 26); g.add_child(ring)
		if sx < 0:
			_fuel_gauge=ring; ring.draw.connect(_draw_fuel)
		else:
			_engine_gauge=ring; ring.draw.connect(_draw_engine)
	_cargo_label=_label("",14,Color("f4e9cf"))
	_cargo_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM); _cargo_label.position=Vector2(-230,-24)
	_cargo_label.size=Vector2(460,20); _cargo_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	_cargo_label.add_theme_color_override("font_outline_color",INK); _cargo_label.add_theme_constant_override("outline_size",3)
	root.add_child(_cargo_label); _speed_group.append(_cargo_label)
	_service_hint=_label("",18,Color("f4e9cf")); root.add_child(_service_hint)
	_service_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM); _service_hint.position=Vector2(-380,-152)
	_service_hint.size=Vector2(760,28); _service_hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	_service_hint.add_theme_color_override("font_outline_color",INK); _service_hint.add_theme_constant_override("outline_size",4)

	_gun_label = _label("", 18, Color(0.98, 0.96, 0.9))
	_gun_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_gun_label.position = Vector2(-460, -222)
	_gun_label.size = Vector2(430, 30)
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
	_stamina_label = _label("Stamina", 16, Color("f4e9cf"))
	_stamina_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_stamina_label.position = Vector2(26, -96)
	_stamina_label.add_theme_color_override("font_outline_color", INK)
	_stamina_label.add_theme_constant_override("outline_size", 3)
	root.add_child(_stamina_label)
	_stamina_bar = ProgressBar.new()
	_stamina_bar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_stamina_bar.position = Vector2(26, -70)
	_stamina_bar.size = Vector2(210, 14)
	_stamina_bar.show_percentage = false
	_stamina_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var stamina_fill := StyleBoxFlat.new(); stamina_fill.bg_color = GREEN
	stamina_fill.set_corner_radius_all(5)
	_stamina_bar.add_theme_stylebox_override("fill", stamina_fill)
	root.add_child(_stamina_bar)

	# --- title card (fades out)
	_title = _label("DESERT DELIVERY", 64, Color(0.98, 0.95, 0.86))
	_title.set_anchors_preset(Control.PRESET_CENTER)
	_title.position = Vector2(-400, -140)
	_title.size = Vector2(800, 90)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_color_override("font_outline_color", INK)
	_title.add_theme_constant_override("outline_size", 10)
	root.add_child(_title)
	var sub := _label("The long way home.", 24, Color(0.98, 0.95, 0.86))
	sub.position = Vector2(0, 80)
	sub.size = Vector2(800, 30)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_outline_color", INK)
	sub.add_theme_constant_override("outline_size", 6)
	_title.add_child(sub)

	# --- controls hint (bottom left, fades out)
	_prompt_bg = _panel(Vector2(28, -174), Vector2(400, 140), 8)
	_prompt_bg.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_prompt_bg.position = Vector2(28, -174)
	root.add_child(_prompt_bg)
	_controls = _label("W/S ride  ·  A/D steer  ·  Space brake\nE hop off  ·  T unfold wings  ·  R recover\nB courier counter  ·  N island journal\nTruck: Q winch  ·  G packing (while stopped)\nF5 save  ·  F9 load", 15)
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
	# low fuel: a pump marker on the rim toward the nearest station
	var game := Game.current
	if game and game.journey and game.journey.services and game.journey.fuel_ratio < JourneySystem.LOW_FUEL[0]:
		var n: Dictionary = game.journey.services.nearest_fuel(_actor_pos())
		if not n.is_empty():
			var cam_f := -camera.global_transform.basis.z
			var a: float = float(n.bearing) - atan2(cam_f.x, -cam_f.z)
			var at := Vector2(sin(a), -cos(a)) * 44.0
			var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.008)
			c.draw_circle(at, 11.0, Color(0.1, 0.08, 0.06))
			c.draw_circle(at, 9.0, Color(0.95, 0.55, 0.12, pulse))
			c.draw_rect(Rect2(at + Vector2(-3.5, -5), Vector2(6, 10)), INK)
			c.draw_line(at + Vector2(2.5, -3), at + Vector2(5, 1), INK, 1.5)
	# package glyph in the centre
	c.draw_rect(Rect2(-11, -8, 22, 16), Color(0.55, 0.36, 0.22))
	c.draw_line(Vector2(0, -8), Vector2(0, 8), Color(0.85, 0.72, 0.4), 2.0)
	c.draw_line(Vector2(-11, 0), Vector2(11, 0), Color(0.85, 0.72, 0.4), 2.0)


func _target_angle() -> float:
	if not gm or gm.stage == DeliverySystem.Stage.DONE: return 0.0
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
	var vehicle := _active_vehicle()
	var kmh := vehicle.speed_kmh() if vehicle else 0.0
	var x := clampf(kmh / 180.0, 0.0, 1.0) * 420.0
	_needle.draw_colored_polygon(PackedVector2Array([Vector2(x - 5, 22), Vector2(x + 5, 22), Vector2(x, -6)]), Color(0.86, 0.22, 0.16))


func _draw_fuel() -> void:
	var value:=clampf(float(bike.get_meta("fuel_ratio",1.0)),0,1)
	var low:=value<JourneySystem.LOW_FUEL[0]
	if value<JourneySystem.LOW_FUEL[1]:
		# reserve: the whole gauge blinks
		var on:=int(Time.get_ticks_msec()/350)%2==0
		_fuel_gauge.draw_circle(Vector2.ZERO,24,Color(0.75,0.18,0.1,0.55 if on else 0.15))
	_fuel_gauge.draw_arc(Vector2.ZERO,19,PI*.75,PI*2.25,40,Color("b3a483"),4,true)
	# the quarter-tank tick
	var q:=PI*.75+PI*1.5*JourneySystem.LOW_FUEL[0]
	_fuel_gauge.draw_line(Vector2(cos(q),sin(q))*14,Vector2(cos(q),sin(q))*23,INK,1.5)
	if value>.001:
		_fuel_gauge.draw_arc(Vector2.ZERO,19,PI*.75,PI*.75+PI*1.5*value,40,Color("a3442f") if low else GREEN,4,true)
	_fuel_gauge.draw_string(_font,Vector2(-5,5),"F",HORIZONTAL_ALIGNMENT_LEFT,-1,15,INK)


func _draw_engine() -> void:
	var level:=clampi(int(bike.get_meta("engine_level",0)),0,3)
	for i in range(4):
		var a:=PI*.75+i*PI*.375
		_engine_gauge.draw_arc(Vector2.ZERO,19,a,a+PI*.30,12,GREEN if i<=level else Color("b3a483"),4,true)
	_engine_gauge.draw_string(_font,Vector2(-5,5),str(level),HORIZONTAL_ALIGNMENT_LEFT,-1,15,INK)


func _actor_pos() -> Vector3:
	var vehicle := _active_vehicle()
	return player.global_position if (_on_foot and player) else vehicle.global_position


func _active_vehicle() -> Vehicle:
	return rider.vehicle if rider and rider.vehicle else bike


## The fighting half of the HUD (crosshair, the Garand's clip, health, damage).
func setup_combat(gun: GunSystem, vitals: PlayerVitals) -> void:
	combat = CombatHud.new()
	combat.name = "CombatHud"
	get_child(0).add_child(combat)
	get_child(0).move_child(combat, 0)
	combat.setup(gun, vitals, camera, rider, _font)


func set_gun(v: bool) -> void:
	_has_gun = v


func set_cans(h: int, t: int) -> void:
	_cans_hit = h
	_cans_total = t


func set_mode(bk: Bike, pl: Player, gn: GunSystem) -> void:
	var on_foot := rider.is_on_foot() if rider else false
	var vehicle := _active_vehicle()
	_on_foot = on_foot
	_stamina_bar.visible = on_foot
	_stamina_label.visible = on_foot
	_prompt_bg.position.y = -260 if on_foot else -174
	_controls.text = "WASD move · Shift sprint · Space jump\nRMB aim · LMB / F fire · V reload\nCtrl / Q dodge · Mouse / JLIK look\nE mount · B counter · N journal\nF5 save · F9 load" if on_foot else "W/S ride · A/D steer · Space brake\nE hop off · T wings · R recover\nB courier counter · N journal\nTruck: Q winch · G packing\nF5 save · F9 load"
	_stamina_bar.max_value = pl.stamina_max
	_stamina_bar.value = pl.stamina
	_stamina_label.text = "Catch your breath — release Shift" if pl.sprint_exhausted else "Stamina  %d%%  ·  Ctrl / Q dodge" % roundi(pl.stamina / pl.stamina_max * 100.0)
	for n in _speed_group:
		n.visible = not on_foot
	# the Garand's clip and the crosshair live in CombatHud; the tin cans are a practice score
	_gun_label.text = "Tin cans %d/%d" % [gn.targets_hit, gn.targets_total] if on_foot and gn.targets_hit > 0 else ""
	if on_foot:
		_mode_label.text = "Swimming" if pl.swimming else "On foot  —  E near the bike or truck to drive"
	elif rider and vehicle == rider.truck:
		var truck: Truck = rider.truck
		if truck.cargo_build_mode:
			_mode_label.text = "PACKING  —  WASD move · Z rotate · Space place · X undo · G finish  —  %s" % truck.cargo_status()
		elif truck.winch_attached:
			_mode_label.text = "TRUCK  —  winch pulling %.0f m · Q release  —  %s" % [truck.winch_distance, truck.cargo_status()]
		else:
			_mode_label.text = "TRUCK  —  Q winch · stop + G pack cargo · E exit  —  %s" % truck.cargo_status()
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


func _on_job_changed(job: JobDefinition, st: StringName) -> void:
	_deliveries.text = "Deliveries %d/%d  ·  %d coins" % [gm.deliveries, gm.jobs.size(), gm.coins]
	if job == null:
		_objective.text = "All packages delivered — nice riding!"
		return
	var truck := "  ·  cargo truck" if job.vehicle == "truck" else ""
	if st == &"pickup":
		_objective.text = "Collect: %s  →  at %s%s" % [job.item, gm.db.location_name(job.from_location), truck]
	else:
		_objective.text = "Deliver: %s  →  to %s%s" % [job.item, gm.db.location_name(job.to_location), truck]


func _process(delta: float) -> void:
	if not bike: return
	# a modal panel (journal, counter, station) owns the screen: the HUD steps back
	var g0 := Game.current
	var covered: bool = g0 != null and g0.panels != null and g0.panels.any_open()
	get_child(0).visible = not covered
	if g0 and g0.mayor and g0.mayor.entry and not g0.mayor.active: g0.mayor.entry.visible = not covered
	var vehicle := _active_vehicle()
	_needle.queue_redraw()
	_compass.queue_redraw()
	_speed_label.text = "%d km/h" % int(vehicle.speed_kmh())
	_deliveries.text="%d delivered   ·   %d coins" % [gm.deliveries,gm.coins]
	_fuel_gauge.queue_redraw(); _engine_gauge.queue_redraw()
	var game_ref:=Game.current
	var range_km:=game_ref.journey.fuel_range_m()/1000.0 if game_ref and game_ref.get("journey") else 0.0
	_cargo_label.text="%.0f kg cargo   ·   Engine +%d   ·   Fuel %d%% (~%.0f km)" % [float(bike.get_meta("cargo_mass_kg",0.0)),int(bike.get_meta("engine_level",0)),int(float(bike.get_meta("fuel_ratio",1.0))*100),range_km]
	if gm.carrying and gm.current_job() and gm.current_job().cargo_kind=="fragile":
		_cargo_label.text+="   ·   Intact %d%%" % roundi(gm.parcel_condition*100)
	if rider and vehicle==rider.truck: _cargo_label.text="Cargo truck  ·  Stop to arrange your load"
	var game:=Game.current
	if _urgent and game and game.colony and game.colony.economy:
		_urgent.text = game.colony.economy.urgent.hud_text()
	if game and game.get("journey"):
		_service_hint.text=game.journey.interaction_hint()
		if game.journey.is_open() or game.catalogue.is_open(): _service_hint.text=""
	if gm and gm.stage != DeliverySystem.Stage.DONE:
		var d := (gm.target_position() - _actor_pos()).length()
		_distance.text = "%d m" % int(d)
	else:
		_distance.text = ""
	_timer_label.text = DeliverySystem.format_time(gm.elapsed) if gm else ""
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
