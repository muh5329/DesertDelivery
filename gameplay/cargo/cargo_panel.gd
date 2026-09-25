class_name CargoPanel
extends CanvasLayer
## The load panel (G): the courier's pack, the Jeep's bed, the Cart and the store in reach, side
## by side on the field journal's parchment (MayorTheme). Pick a column and a line, pick where it
## goes, move one, ten or the lot; use a fuel can or an ammunition crate. Modal through
## Game.panels like the counter and the journal; CargoSystem does the moving.
##
## Keys: A/D or ←/→ column · W/S or ↑/↓ line · Tab destination · Space move 1 · Shift+Space
## move 10 · Enter move all of it · X empty the column into the destination · U use · G/Esc close.

const W := 1180.0
const H := 660.0
const COL_W := 268.0

var game: Game
var cargo: CargoSystem
var panel: Control
var source := 0                   ## column index
var target := 1
var line := 0
var feedback := ""
var _shade: ColorRect
var _title: Label
var _subtitle: Label
var _columns: HBoxContainer
var _target_label: Label
var _status: Label
var _buttons: Dictionary = {}
var _holds: Array = []
var _refresh_t := 0.0
var _signature := ""


func setup(p_game: Game, p_cargo: CargoSystem) -> void:
	game = p_game; cargo = p_cargo
	layer = 15
	_build()
	get_viewport().size_changed.connect(_layout)


func is_open() -> bool:
	return panel != null and panel.visible


func toggle() -> void:
	if is_open(): close_panel()
	else: open()


func open() -> bool:
	if is_open(): return true
	if game.catalogue.is_open() or game.journey.is_open() or (game.mayor and game.mayor.active): return false
	var why := cargo.can_open()
	if why != "":
		Events.message.emit(why, 2.5)
		return false
	_holds = cargo.holds()
	source = 0; line = 0
	target = 1 if _holds.size() > 1 else 0
	feedback = "Nothing to load here: stand by the jeep, the cart, a colony warehouse or a station shop." if _holds.size() < 2 else ""
	game.panels.open(self)
	panel.show(); _shade.show()
	_refresh(true); _layout()
	return true


func close_panel() -> void:
	if not is_open(): return
	panel.hide(); _shade.hide()
	game.panels.close(self)


func _process(delta: float) -> void:
	if not is_open(): return
	_refresh_t += delta
	if _refresh_t < 0.25: return
	_refresh_t = 0.0
	if cargo.can_open() != "":
		close_panel(); return
	_refresh(false)


func _input(event: InputEvent) -> void:
	if not is_open(): return
	if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B:
		close_panel(); get_viewport().set_input_as_handled(); return
	if not event is InputEventKey or not event.pressed: return
	var k: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	var handled := true
	match k:
		KEY_ESCAPE, KEY_G: close_panel()
		KEY_A, KEY_LEFT: _select_column(-1)
		KEY_D, KEY_RIGHT: _select_column(1)
		KEY_W, KEY_UP: _select_line(-1)
		KEY_S, KEY_DOWN: _select_line(1)
		KEY_TAB: _cycle_target()
		KEY_SPACE: move_selected(10 if event.shift_pressed else 1)
		KEY_ENTER, KEY_KP_ENTER: move_selected(100000)
		KEY_X: empty_column()
		KEY_U: use_selected()
		_: handled = false
	if handled: get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- actions (also for tests)
func _rows(i: int) -> Array:
	if i < 0 or i >= _holds.size(): return []
	var h: Dictionary = _holds[i]
	var out: Array = []
	if game.gm.carrying and ((h.id == "pack" and cargo.parcel_hold() == "pack") or (h.id == "cart" and cargo.parcel_hold() == "cart")):
		out.append({"id": "parcel", "title": "Parcel · %s" % game.gm.current_job().item, "count": 1, "mass": game.gm.carried_mass()})
	var c := cargo.contents(h)
	var ids: Array = c.keys()
	ids.sort_custom(func(a, b): return ItemDefinition.get_item(a).title < ItemDefinition.get_item(b).title)
	for id: String in ids:
		var def := ItemDefinition.get_item(id)
		out.append({"id": id, "title": def.title, "count": int(c[id]), "mass": def.mass, "colour": def.colour, "use": def.use, "price": def.value})
	return out


func selected_item() -> String:
	var rows := _rows(source)
	return String(rows[line].id) if line >= 0 and line < rows.size() else ""


func move_selected(n: int) -> void:
	var item := selected_item()
	if item == "" or source == target:
		feedback = "Pick a line, and somewhere else to put it (Tab)."
	elif item == "parcel":
		var why := cargo.move_parcel(String(_holds[target].id))
		feedback = why if why != "" else cargo.last_message
	else:
		var why := cargo.move(String(_holds[source].id), String(_holds[target].id), item, n)
		feedback = why if why != "" else cargo.last_message
	_refresh(true)


func empty_column() -> void:
	if source == target: return
	var moved := cargo.move_all(String(_holds[source].id), String(_holds[target].id))
	feedback = "Moved %d kinds of goods to the %s." % [moved, String(_holds[target].title).to_lower()] if moved > 0 else "Nothing more fits there."
	_refresh(true)


func use_selected() -> void:
	var item := selected_item()
	if item == "" or item == "parcel":
		feedback = "Pick a fuel can or an ammunition crate to use."
	else:
		var why := cargo.use(String(_holds[source].id), item)
		feedback = why if why != "" else cargo.last_message
	_refresh(true)


func _select_column(d: int) -> void:
	source = clampi(source + d, 0, _holds.size() - 1)
	if target == source: _cycle_target()
	line = clampi(line, 0, maxi(0, _rows(source).size() - 1))
	_refresh(true)


func _select_line(d: int) -> void:
	line = clampi(line + d, 0, maxi(0, _rows(source).size() - 1))
	_refresh(true)


func _cycle_target() -> void:
	if _holds.size() < 2: return
	target = (target + 1) % _holds.size()
	if target == source: target = (target + 1) % _holds.size()
	_refresh(true)


# ---------------------------------------------------------------- drawing
func _refresh(force: bool) -> void:
	var holds := cargo.holds()
	var sig := ""
	for h in holds: sig += String(h.id) + String(h.title) + str(cargo.contents(h)) + "|"
	sig += str(game.gm.carrying) + cargo.parcel_hold() + str(game.gm.coins)
	if not force and sig == _signature: return
	_signature = sig
	var ids_before: Array = []
	for h in _holds: ids_before.append(h.id)
	_holds = holds
	source = clampi(source, 0, _holds.size() - 1)
	target = clampi(target, 0, _holds.size() - 1)
	if target == source and _holds.size() > 1: target = (source + 1) % _holds.size()
	line = clampi(line, 0, maxi(0, _rows(source).size() - 1))
	var where := "stopped"
	for h in _holds:
		if h.kind in ["store", "shop"]: where = "at " + String(h.title)
	_title.text = "Load & unload"
	_subtitle.text = ("%s  ·  %d coins  ·  %s" % [where.to_upper(), game.gm.coins, game.life.clock_text().get_slice("  ·  ", 0)]).to_upper()
	for c in _columns.get_children(): c.queue_free()
	for i in _holds.size():
		_columns.add_child(_column(i))
	var dest := String(_holds[target].title) if _holds.size() > 1 else "—"
	_target_label.text = "From  %s   →   to  %s   (Tab changes where it goes)" % [String(_holds[source].title), dest]
	_status.text = feedback if feedback != "" else "Colony warehouses give and take their goods free; shops sell fuel cans and ammunition crates. Mass slows the tow vehicle and burns fuel."
	var item := selected_item()
	var def := ItemDefinition.get_item(item) if item != "" and item != "parcel" else null
	(_buttons.use as Button).disabled = def == null or def.use == "" or not _holds[source].has("inv")
	for key in ["one", "ten", "all", "empty"]: (_buttons[key] as Button).disabled = _holds.size() < 2


func _column(i: int) -> Control:
	var h: Dictionary = _holds[i]
	var box := PanelContainer.new()
	var selected := i == source
	var is_target := i == target and _holds.size() > 1
	box.add_theme_stylebox_override("panel", MayorTheme.box(Color("f7eedb") if selected else MayorTheme.PAPER, MayorTheme.ACCENT if selected else (MayorTheme.GOOD if is_target else MayorTheme.EDGE), 3 if selected or is_target else 1))
	box.custom_minimum_size = Vector2(COL_W, 420)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 4)
	box.add_child(v)
	var head := Label.new(); head.text = String(h.title); head.add_theme_font_size_override("font_size", 20)
	head.clip_text = true; head.custom_minimum_size = Vector2(COL_W - 20, 0)
	v.add_child(head)
	var sub := Label.new(); sub.add_theme_font_size_override("font_size", 16); sub.add_theme_color_override("font_color", MayorTheme.MUTED)
	var bar := ProgressBar.new(); bar.show_percentage = false; bar.custom_minimum_size = Vector2(COL_W - 24, 10)
	match String(h.kind):
		"store":
			var t: ColonyTown = h.town
			sub.text = "Colony stock  ·  %.0f / %.0f kg" % [t.stock_mass(), t.capacity()]
			sub.tooltip_text = String(h.get("building", ""))
			bar.max_value = t.capacity(); bar.value = t.stock_mass()
		"shop":
			sub.text = "Shop  ·  buy for coins, half back"
			bar.visible = false
		_:
			var inv: Inventory = h.inv
			var extra := game.gm.carried_mass() if game.gm.carrying and ((h.id == "cart" and game.gm.parcel_in_cart) or (h.id == "pack" and not game.gm.parcel_in_cart)) else 0.0
			sub.text = "%.0f / %.0f kg%s" % [inv.mass(), inv.capacity, "  (+ parcel)" if extra > 0.0 else ""]
			bar.max_value = inv.capacity; bar.value = inv.mass()
	v.add_child(sub); v.add_child(bar)
	if is_target:
		var tag := Label.new(); tag.text = "▼ goods go here"; tag.add_theme_font_size_override("font_size", 16); tag.add_theme_color_override("font_color", MayorTheme.GOOD)
		v.add_child(tag)
	var scroll := ScrollContainer.new(); scroll.custom_minimum_size = Vector2(COL_W - 16, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var list := VBoxContainer.new(); list.add_theme_constant_override("separation", 2)
	scroll.add_child(list)
	var rows := _rows(i)
	if rows.is_empty():
		var empty := Label.new(); empty.text = "Empty"; empty.add_theme_color_override("font_color", MayorTheme.MUTED)
		list.add_child(empty)
	for r in rows.size():
		list.add_child(_row(i, r, rows[r], h))
	return box


func _row(col: int, r: int, row: Dictionary, h: Dictionary) -> Control:
	var b := Button.new()
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(COL_W - 30, 30)
	b.clip_text = true
	b.add_theme_font_size_override("font_size", 16)
	var count := "×%d" % int(row.count) if String(h.kind) != "shop" else "%d coins" % int(row.get("price", 0))
	var mark := "▶ " if col == source and r == line else "   "
	b.text = "%s%s  %s  · %.0f kg" % [mark, String(row.title), count, float(row.mass) * (1 if String(h.kind) == "shop" else int(row.count))]
	if col == source and r == line:
		b.add_theme_stylebox_override("normal", MayorTheme.box(Color("dfe7df"), MayorTheme.ACCENT, 2))
	if row.has("colour"):
		b.add_theme_color_override("font_color", MayorTheme.INK)
	b.pressed.connect(func():
		if source == col and line == r: move_selected(1)
		else:
			source = col; line = r
			if target == source: _cycle_target()
			_refresh(true))
	return b


func _build() -> void:
	_shade = ColorRect.new(); _shade.color = Color(0.035, 0.06, 0.055, 0.66)
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(_shade); _shade.hide()
	panel = Control.new(); panel.size = Vector2(W, H); panel.theme = MayorTheme.theme(); add_child(panel); panel.hide()
	var outer := Panel.new(); outer.add_theme_stylebox_override("panel", MayorTheme.box(MayorTheme.PAPER, Color("765e40"), 4))
	_place(outer, Rect2(0, 0, W, H))
	var band := Panel.new(); band.add_theme_stylebox_override("panel", MayorTheme.box(MayorTheme.BAND, MayorTheme.BAND.lightened(0.2)))
	_place(band, Rect2(20, 18, W - 40, 76))
	_title = _label("", Rect2(40, 24, 700, 38), 29, MayorTheme.BAND_TEXT)
	_subtitle = _label("", Rect2(42, 60, 800, 26), 16, Color("d9c9a2"))
	_subtitle.clip_text = true
	var close := Button.new(); close.text = "Close · G / Esc"; _place(close, Rect2(W - 210, 36, 170, 40))
	close.add_theme_font_size_override("font_size", 16)
	close.pressed.connect(close_panel)
	_columns = HBoxContainer.new(); _columns.add_theme_constant_override("separation", 14)
	_place(_columns, Rect2(28, 110, W - 56, 430))
	_target_label = _label("", Rect2(30, 548, W - 60, 26), 17)
	var x := 30.0
	for spec in [["one", "Move 1 · Space", func(): move_selected(1)], ["ten", "Move 10 · Shift+Space", func(): move_selected(10)],
			["all", "Move all · Enter", func(): move_selected(100000)], ["empty", "Empty column · X", empty_column],
			["use", "Use · U", use_selected]]:
		var b := Button.new(); b.text = spec[1]; b.add_theme_font_size_override("font_size", 16)
		var w := 212.0 if spec[0] != "use" else 130.0
		_place(b, Rect2(x, 580, w, 38)); x += w + 10
		b.pressed.connect(spec[2])
		_buttons[spec[0]] = b
	_status = _label("", Rect2(30, 624, W - 60, 28), 16, MayorTheme.MUTED)
	_status.clip_text = true


func _place(c: Control, r: Rect2) -> void:
	panel.add_child(c); c.position = r.position; c.size = r.size


func _label(text: String, r: Rect2, size: int, col: Color = MayorTheme.INK) -> Label:
	var l := Label.new(); l.text = text
	l.add_theme_font_size_override("font_size", size); l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(l, r); return l


func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	var zoom := minf(1.1, minf(vp.x / (W + 40.0), vp.y / (H + 40.0)))
	panel.scale = Vector2.ONE * zoom
	panel.position = (vp - panel.size * zoom) * 0.5
