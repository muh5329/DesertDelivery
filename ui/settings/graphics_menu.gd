class_name GraphicsMenu
extends CanvasLayer
## F10: the graphics quality menu (GraphicsSettings presets Low / Medium / High / Ultra), with the
## frame rate while it is open so the choice can be judged on the spot. Opens through the
## PanelStack like every other modal panel (frees the mouse, blocks the controls).

var game: Node
var _panel: PanelContainer
var _buttons: Array[Button] = []
var _info: Label
var _fps: Label
var _open := false


func setup(p_game: Node) -> void:
	game = p_game
	layer = 20
	name = "GraphicsMenu"
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(560, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.08, 0.07, 0.92); sb.set_corner_radius_all(10)
	sb.content_margin_left = 22; sb.content_margin_right = 22; sb.content_margin_top = 18; sb.content_margin_bottom = 18
	sb.border_color = Color(0.85, 0.72, 0.5, 0.6); sb.set_border_width_all(1)
	_panel.add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new(); box.add_theme_constant_override("separation", 12)
	_panel.add_child(box)
	var title := Label.new(); title.text = "Graphics quality"
	title.add_theme_font_size_override("font_size", 26); title.add_theme_color_override("font_color", Color(0.96, 0.9, 0.78))
	box.add_child(title)
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	for i in range(GraphicsSettings.NAMES.size()):
		var b := Button.new(); b.text = GraphicsSettings.NAMES[i]; b.toggle_mode = true
		b.custom_minimum_size = Vector2(118, 44); b.add_theme_font_size_override("font_size", 18)
		b.pressed.connect(_choose.bind(i))
		row.add_child(b); _buttons.append(b)
	_info = Label.new(); _info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = Vector2(516, 0); _info.add_theme_font_size_override("font_size", 16)
	_info.add_theme_color_override("font_color", Color(0.86, 0.82, 0.74))
	box.add_child(_info)
	_fps = Label.new(); _fps.add_theme_font_size_override("font_size", 16)
	_fps.add_theme_color_override("font_color", Color(0.7, 0.85, 0.7))
	box.add_child(_fps)
	var hint := Label.new(); hint.text = "F10 or Esc closes · saved for next time"
	hint.add_theme_font_size_override("font_size", 14); hint.add_theme_color_override("font_color", Color(0.65, 0.62, 0.56))
	box.add_child(hint)
	add_child(_panel)
	_panel.visible = false
	_refresh()


func _refresh() -> void:
	for i in range(_buttons.size()): _buttons[i].button_pressed = i == GraphicsSettings.level
	_info.text = GraphicsSettings.describe(GraphicsSettings.level)
	# centre (the anchors preset leaves the offsets at the minimum size)
	_panel.reset_size()
	_panel.position = (_panel.get_viewport_rect().size - _panel.size) * 0.5


func _choose(i: int) -> void:
	GraphicsSettings.apply(game.world, i)
	GraphicsSettings.save()
	_refresh()


func is_open() -> bool:
	return _open


func open_panel() -> void:
	if _open: return
	_open = true
	_panel.visible = true
	_refresh()
	if game.panels: game.panels.open(self)


func close_panel() -> void:
	if not _open: return
	_open = false
	_panel.visible = false
	if game.panels: game.panels.close(self)


func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode == KEY_F10:
		if _open: close_panel()
		else: open_panel()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE and _open:
		close_panel()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if _open: _fps.text = "%d fps · %.1f ms" % [Engine.get_frames_per_second(), 1000.0 / maxf(Engine.get_frames_per_second(), 1.0)]
