class_name StationPanel
extends CanvasLayer
## A town station's shop window: fill the tank, and buy a coach (or ferry) ticket to any town
## the courier has ridden into. Opened with B on a town station's apron, or from a courier
## counter ("Coach & ferry"). Modal through Game.panels like the counter and the journal.

var game: Game
var journey: JourneySystem
var services: RoadServices
var panel: Control
var from_id := ""
var _shade: ColorRect
var _title: Label
var _subtitle: Label
var _fuel_text: Label
var _fuel_button: Button
var _rows: VBoxContainer
var _status: Label
var _feedback := ""
var _theme: Theme

const W := 860.0
const H := 600.0


func setup(p_game: Game, p_journey: JourneySystem, p_services: RoadServices) -> void:
	game = p_game; journey = p_journey; services = p_services
	layer = 15
	name = "StationPanel"
	_build()
	get_viewport().size_changed.connect(_layout)


func is_open() -> bool:
	return panel != null and panel.visible


func open_at(station_id: String) -> bool:
	if is_open(): return true
	var s: Dictionary = services.by_id.get(station_id, {})
	if s.is_empty(): return false
	from_id = station_id
	game.panels.open(self)
	_feedback = ""
	panel.show(); _shade.show()
	_refresh(); _layout()
	_fuel_button.grab_focus()
	return true


func close_panel() -> void:
	if not is_open(): return
	panel.hide(); _shade.hide()
	game.panels.close(self)


func _input(event: InputEvent) -> void:
	if not is_open(): return
	if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B:
		close_panel(); get_viewport().set_input_as_handled(); return
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode in [KEY_ESCAPE, KEY_B]:
		close_panel()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not is_open(): return
	# walked or rode away: the window closes
	var s: Dictionary = services.by_id.get(from_id, {})
	var c: Vector3 = game.rider.courier().global_position
	var reach := RoadServices.USE_RADIUS + 6.0 if s.get("kind", "") != "counter" else JourneySystem.HUB_RADIUS + 6.0
	if s.is_empty() or Vector2(c.x - s.pos.x, c.z - s.pos.z).length() > reach:
		close_panel()


func _buy_fuel() -> void:
	journey.refuel_here()
	_feedback = journey.last_feedback
	_refresh()


func _buy_ticket(cid: String) -> void:
	var why := services.travel(from_id, cid)
	if why == "":
		close_panel()
		return
	_feedback = why
	_refresh()


func _refresh() -> void:
	var s: Dictionary = services.by_id.get(from_id, {})
	if s.is_empty(): return
	_title.text = String(s.name)
	_subtitle.text = ("FUEL  ·  SHOP  ·  COACH & FERRY" if s.kind != "counter" else "COURIER COUNTER  ·  TICKETS") + "  /  " + game.life.clock_text().get_slice("  ·  ", 0).to_upper()
	var price := journey.refill_price()
	_fuel_text.text = "Tank %d%%  ·  about %.0f km left  ·  %d coins in your wallet" % [roundi(journey.current_tank() * 100.0), journey.fuel_range_m() / 1000.0, game.gm.coins]
	_fuel_button.text = "Fill tank · %d coins" % price if price > 0 else "Tank full"
	_fuel_button.disabled = price == 0 or game.gm.coins < price or not journey.bike_at_station(s)
	for c in _rows.get_children(): c.queue_free()
	for d in services.destinations(from_id):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		var what := Label.new()
		what.text = "%s  ·  %s" % ["Ferry" if d.ferry else "Coach", d.name]
		what.custom_minimum_size = Vector2(300, 0)
		what.add_theme_font_size_override("font_size", 19)
		row.add_child(what)
		var info := Label.new()
		info.text = "%.0f km  ·  %d min" % [d.km, d.minutes] if d.open else "Not visited yet"
		info.tooltip_text = "" if d.open else String(d.reason)
		info.custom_minimum_size = Vector2(250, 0)
		info.clip_text = true
		info.add_theme_font_size_override("font_size", 17)
		info.add_theme_color_override("font_color", Color("5e6453"))
		row.add_child(info)
		var buy := Button.new()
		buy.text = "Ticket · %d coins" % d.price
		buy.custom_minimum_size = Vector2(190, 38)
		buy.add_theme_font_size_override("font_size", 17)
		buy.disabled = not d.open or game.gm.coins < int(d.price)
		var cid: String = d.id
		buy.pressed.connect(func(): _buy_ticket(cid))
		row.add_child(buy)
		_rows.add_child(row)
	_status.text = _feedback if _feedback != "" else "Your bike rides on the coach's roof rack. The trip takes game time; parcels have no deadline."


func _build() -> void:
	var font := SystemFont.new(); font.font_names = PackedStringArray(["Georgia", "Noto Serif", "DejaVu Serif"])
	_theme = Theme.new(); _theme.default_font = font; _theme.default_font_size = 19
	for type in ["Label", "Button"]:
		_theme.set_color("font_color", type, Color("2e403d"))
	_theme.set_stylebox("normal", "Button", _style(Color("dfc694"), Color("ac9060")))
	_theme.set_stylebox("hover", "Button", _style(Color("f5dfae"), Color("698b87")))
	_theme.set_stylebox("pressed", "Button", _style(Color("aecac3"), Color("698b87")))
	_theme.set_stylebox("focus", "Button", _style(Color(0, 0, 0, 0), Color("416d75"), 2))
	_theme.set_stylebox("disabled", "Button", _style(Color("d3ccba"), Color("b2a88e")))
	_theme.set_color("font_disabled_color", "Button", Color("837e6c"))
	_theme.set_color("font_hover_color", "Button", Color("263d3b"))
	_theme.set_color("font_focus_color", "Button", Color("263d3b"))
	_theme.set_color("font_pressed_color", "Button", Color("263d3b"))
	_shade = ColorRect.new(); _shade.color = Color(0.035, 0.06, 0.055, 0.72)
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(_shade); _shade.hide()
	panel = Control.new(); panel.size = Vector2(W, H); panel.theme = _theme; add_child(panel); panel.hide()
	var outer := Panel.new(); outer.add_theme_stylebox_override("panel", _style(Color("e9dfc7"), Color("765e40"), 4))
	_place(outer, Rect2(0, 0, W, H))
	var banner := Panel.new(); banner.add_theme_stylebox_override("panel", _style(Color("7a2a1f"), Color("a9543d")))
	_place(banner, Rect2(20, 18, W - 40, 78))
	_title = _label("", Rect2(40, 26, 560, 38), 29, Color("fff0d2"))
	_subtitle = _label("", Rect2(42, 62, 600, 26), 16, Color("ebcf9e"))
	_subtitle.clip_text = true
	var close := Button.new(); close.text = "Close · B / Esc"; _place(close, Rect2(W - 200, 38, 160, 40))
	close.add_theme_font_size_override("font_size", 16)
	close.pressed.connect(close_panel)
	_label("Fuel", Rect2(40, 112, 300, 32), 24)
	_fuel_text = _label("", Rect2(40, 148, 560, 28), 17, Color("5e6453"))
	_fuel_button = Button.new(); _place(_fuel_button, Rect2(W - 260, 128, 220, 44))
	_fuel_button.add_theme_font_size_override("font_size", 17)
	_fuel_button.pressed.connect(_buy_fuel)
	_label("Coach & ferry tickets", Rect2(40, 196, 500, 32), 24)
	_rows = VBoxContainer.new(); _rows.add_theme_constant_override("separation", 8)
	_place(_rows, Rect2(40, 236, W - 80, 270))
	_status = _label("", Rect2(40, H - 80, W - 80, 56), 16, Color("5e6453"))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _place(c: Control, r: Rect2) -> void:
	panel.add_child(c); c.position = r.position; c.size = r.size


func _label(text: String, r: Rect2, size: int, col: Color = Color("2e403d")) -> Label:
	var l := Label.new(); l.text = text
	l.add_theme_font_size_override("font_size", size); l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(l, r); return l


func _style(fill: Color, border: Color, width: int = 1) -> StyleBoxFlat:
	var st := StyleBoxFlat.new(); st.bg_color = fill; st.border_color = border; st.set_border_width_all(width)
	st.set_corner_radius_all(5); st.set_content_margin_all(8); return st


func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	var zoom := minf(1.15, minf(vp.x / (W + 40.0), vp.y / (H + 40.0)))
	panel.scale = Vector2.ONE * zoom
	panel.position = (vp - panel.size * zoom) * 0.5
