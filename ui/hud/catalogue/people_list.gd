extends ScrollContainer
## Separate text controls preserve real two-line typography in the resident roster.
signal item_selected(index: int)
var rows: Array[Button]=[]
var names: Array[Label]=[]
var roles: Array[Label]=[]
var portraits: Array[TextureRect]=[]
var column: VBoxContainer
var selected:=-1
var normal: StyleBoxFlat
var selected_style: StyleBoxFlat

func _ready() -> void:
	horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	focus_mode=Control.FOCUS_ALL
	follow_focus=true
	column=VBoxContainer.new(); column.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation",2); add_child(column)
	normal=StyleBoxFlat.new(); normal.bg_color=Color(0,0,0,0)
	normal.border_color=Color(.50,.46,.34,.20); normal.border_width_bottom=1
	normal.set_corner_radius_all(4)
	selected_style=StyleBoxFlat.new(); selected_style.bg_color=Color("b7cbd0")
	selected_style.border_color=Color("7899a0"); selected_style.set_border_width_all(1)
	selected_style.set_corner_radius_all(5)

func clear() -> void:
	for row in rows:
		column.remove_child(row); row.queue_free()
	rows.clear(); names.clear(); roles.clear(); portraits.clear(); selected=-1

func add_item(title: String,texture: Texture2D=null) -> int:
	var index:=rows.size()
	var row:=Button.new(); row.custom_minimum_size=Vector2(0,75)
	row.add_theme_stylebox_override("normal",normal)
	row.add_theme_stylebox_override("hover",selected_style)
	row.add_theme_stylebox_override("pressed",selected_style)
	column.add_child(row); rows.append(row)
	var image:=TextureRect.new(); image.position=Vector2(9,5); image.size=Vector2(57,64)
	image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; image.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED
	image.texture=texture; image.mouse_filter=Control.MOUSE_FILTER_IGNORE; row.add_child(image); portraits.append(image)
	var parts:=title.split("\n")
	var person:=Label.new(); person.text=parts[0]; person.position=Vector2(82,11)
	person.add_theme_font_size_override("font_size",21); person.mouse_filter=Control.MOUSE_FILTER_IGNORE
	row.add_child(person); names.append(person)
	var occupation:=Label.new(); occupation.text=parts[1] if parts.size()>1 else ""
	occupation.position=Vector2(83,42); occupation.add_theme_font_size_override("font_size",14)
	occupation.add_theme_color_override("font_color",Color("6e6b57")); occupation.mouse_filter=Control.MOUSE_FILTER_IGNORE
	row.add_child(occupation); roles.append(occupation)
	row.pressed.connect(func(): select(index); item_selected.emit(index))
	return index

func select(index: int) -> void:
	if index<0 or index>=rows.size(): return
	if selected>=0 and selected<rows.size(): rows[selected].add_theme_stylebox_override("normal",normal)
	selected=index; rows[index].add_theme_stylebox_override("normal",selected_style)

func set_item_icon(index: int,texture: Texture2D) -> void: portraits[index].texture=texture
func set_item_tooltip(index: int,value: String) -> void: rows[index].tooltip_text=value
func ensure_current_is_visible() -> void:
	_scroll_selected.call_deferred()

func _scroll_selected() -> void:
	# Container layout settles after rows and the book are resized.
	await get_tree().process_frame
	await get_tree().process_frame
	if selected>=0 and selected<rows.size() and is_ancestor_of(rows[selected]):
		scroll_vertical=maxi(0,int(rows[selected].position.y-size.y*.35))

func focus_selected() -> void:
	# Focus a row instead of the scroll container so arrows/gamepad move through people.
	await get_tree().process_frame
	await get_tree().process_frame
	if selected>=0 and selected<rows.size() and is_ancestor_of(rows[selected]):
		rows[selected].grab_focus()
		ensure_control_visible(rows[selected])
