class_name ResidentCatalogue
extends CanvasLayer
## An island field journal. The week chart and daily itinerary share the simulation's
## resolved schedule, so weekly overrides and midnight are always represented accurately.
const BOOK=preload("res://ui/hud/catalogue/book_backdrop.gd")
const PEOPLE=preload("res://ui/hud/catalogue/people_list.gd")
const WEEK=preload("res://ui/hud/catalogue/week_grid.gd")
const INK:=Color("303831")
const MUTED:=Color("726f5a")
var life: IslandLife
var game: Game
var panel: Control
var shade: ColorRect
var clock_button: Button
var search: LineEdit
var list: ScrollContainer
var details: RichTextLabel
var day_picker: OptionButton
var count_label: Label
var shown_ids: Array[String]=[]
var selected_id:=""
## The modal protocol lives in Game.panels; this is a window onto it for existing callers.
var just_closed: bool:
	get: return game!=null and game.panels.just_closed()
var _refresh:=0.0
var _font: SystemFont
var _theme: Theme
var _name: Label
var _occupation: Label
var _home: Label
var _now: Label
var _travel: Label
var _portrait: TextureRect
var _grid: Control
var _notes: TextEdit
var _notes_by_id: Dictionary={}
var _editing_notes:=false
var _sort: OptionButton
var _journal_clock: Label
var _portraits: Dictionary={}
var _portrait_view: SubViewport
var _portrait_model: RiderModel
var _portrait_queue: Array[String]=[]
var _portrait_busy:=false

func setup(p_life: IslandLife,p_game: Game) -> void:
	life=p_life; game=p_game; layer=12
	_font=SystemFont.new(); _font.font_names=PackedStringArray(["Georgia","Noto Serif","DejaVu Serif"])
	_theme=Theme.new(); _theme.default_font=_font; _theme.default_font_size=18
	for type in ["Label","Button","LineEdit","OptionButton","ItemList","TextEdit"]:
		_theme.set_color("font_color",type,INK)
		_theme.set_color("font_hover_color",type,INK)
		_theme.set_color("font_focus_color",type,INK)
		_theme.set_color("font_pressed_color",type,INK)
		_theme.set_stylebox("focus",type,_style(Color(0,0,0,0),Color("496f84"),2))
	for type in ["Button","OptionButton"]:
		_theme.set_stylebox("normal",type,_style(Color("e5d6b7"),Color("b6a78a")))
		_theme.set_stylebox("hover",type,_style(Color("f6ebd2"),Color("73909a")))
		_theme.set_stylebox("pressed",type,_style(Color("bfd1d1"),Color("73909a")))
	_theme.set_color("default_color","RichTextLabel",INK)
	_theme.set_color("font_placeholder_color","LineEdit",MUTED)
	_theme.set_color("font_placeholder_color","TextEdit",MUTED)
	_theme.set_color("caret_color","LineEdit",INK)
	_theme.set_color("caret_color","TextEdit",INK)
	shade=ColorRect.new(); shade.color=Color(.035,.05,.045,.65); shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade); shade.hide()
	panel=Control.new(); panel.theme=_theme; panel.size=Vector2(1480,820); panel.mouse_filter=Control.MOUSE_FILTER_STOP
	add_child(panel); panel.hide()
	var backdrop:=Control.new(); backdrop.set_script(BOOK); backdrop.size=panel.size; panel.add_child(backdrop)
	_label("ISLAND FIELD JOURNAL",Rect2(100,10,420,28),16,Color("f0e3c8"))
	_journal_clock=_label("",Rect2(920,10,495,28),18,Color("f0e3c8")); _journal_clock.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	var top:=_button("People",Rect2(145,39,168,45)); top.add_theme_font_size_override("font_size",22); top.disabled=true
	top.add_theme_color_override("font_disabled_color",INK)
	top.add_theme_stylebox_override("disabled",_style(Color("ecdfbf"),Color("b6a78a")))
	_label("The lives that make an island",Rect2(330,45,500,28),18,Color("e5d6b7"))
	_button("Close  ·  Esc",Rect2(1235,41,170,35)).pressed.connect(toggle)
	for spec in [["People",180],["Routine",253],["Notes",326]]:
		var tab:=_button(spec[0],Rect2(25,spec[1],103,58))
		match spec[0]:
			"People": tab.pressed.connect(func(): list.focus_selected())
			"Routine": tab.pressed.connect(func(): day_picker.grab_focus())
			"Notes": tab.pressed.connect(func(): _notes.grab_focus())
	_label("People",Rect2(157,108,380,52),39)
	count_label=_label("",Rect2(158,160,520,30),18,MUTED)
	search=LineEdit.new(); _place(search,Rect2(155,206,346,38)); search.placeholder_text="Search people, jobs, places…"
	search.add_theme_font_size_override("font_size",16); search.add_theme_stylebox_override("normal",_style(Color("f4ead4"),Color("b9ac90")))
	search.text_changed.connect(func(_value): _populate())
	_sort=OptionButton.new(); _place(_sort,Rect2(511,206,173,38))
	for text in ["Name  A–Z","Occupation","District"]: _sort.add_item(text)
	_sort.add_theme_font_size_override("font_size",15); _sort.item_selected.connect(func(_i): _populate())
	list=ScrollContainer.new(); list.set_script(PEOPLE); _place(list,Rect2(151,260,538,433))
	list.item_selected.connect(func(index): _select_person(shown_ids[index]))
	_label("Every name has a place. Every day has a story.",Rect2(157,709,510,24),15,MUTED)
	_label("Search the island register, then choose a day to explore.",Rect2(157,734,520,22),13,MUTED)
	_name=_label("",Rect2(767,109,422,50),35)
	_occupation=_label("",Rect2(768,163,430,30),21)
	_home=_label("",Rect2(768,202,440,44),16,MUTED); _home.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	_now=_label("",Rect2(768,247,435,46),16); _now.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	_travel=_label("",Rect2(768,292,600,23),14,MUTED)
	var frame:=Panel.new(); frame.add_theme_stylebox_override("panel",_style(Color("fff6df"),Color("c9bb9c"))); _place(frame,Rect2(1217,108,166,185))
	_portrait=TextureRect.new(); _place(_portrait,Rect2(1225,116,150,169)); _portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; _portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_label("Weekly schedule",Rect2(768,321,350,30),23)
	_label("Repeats every seven days",Rect2(1135,329,246,20),13,MUTED)
	_grid=Control.new(); _grid.set_script(WEEK); _grid.life=life; _grid.font=_font; _place(_grid,Rect2(768,361,615,225))
	_grid.day_selected.connect(func(day): day_picker.select(day); _show_day())
	var legend_x:=772.0
	for key in ["home","work","cafe","market","community"]:
		var swatch:=ColorRect.new(); swatch.color=WEEK.COLORS[key]; swatch.mouse_filter=Control.MOUSE_FILTER_IGNORE; _place(swatch,Rect2(legend_x,594,12,12))
		_label({"home":"Home","work":"Work","cafe":"Meals","market":"Market","community":"Visits"}[key],Rect2(legend_x+17,590,95,21),12,MUTED)
		legend_x+=112
	day_picker=OptionButton.new(); _place(day_picker,Rect2(768,619,310,29)); day_picker.add_theme_font_size_override("font_size",16)
	for day in IslandLife.DAYS: day_picker.add_item(day+"’s routine")
	day_picker.select(life.day_index()); day_picker.item_selected.connect(func(_day): _show_day())
	details=RichTextLabel.new(); _place(details,Rect2(770,659,318,96)); details.bbcode_enabled=true; details.add_theme_font_size_override("normal_font_size",14)
	details.add_theme_font_size_override("bold_font_size",14); details.scroll_active=true
	_label("Field notes",Rect2(1120,619,250,28),19)
	_notes=TextEdit.new(); _place(_notes,Rect2(1116,659,265,96)); _notes.placeholder_text="Write a note about this person…"
	_notes.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY; _notes.add_theme_font_size_override("font_size",14)
	_notes.add_theme_stylebox_override("normal",_style(Color(.70,.64,.49,.10),Color("c4b798")))
	_notes.text_changed.connect(func():
		if not _editing_notes and not selected_id.is_empty(): _notes_by_id[selected_id]=_notes.text)
	_label("N  Journal     ·     Esc  Return to island     ·     Select a day for full task times     ·     F5  Save notes & game",Rect2(149,795,1248,24),15,Color("e8dfc6"))
	clock_button=Button.new(); clock_button.theme=_theme
	clock_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	clock_button.offset_left=-440; clock_button.offset_right=-24; clock_button.offset_top=20; clock_button.offset_bottom=62
	clock_button.pressed.connect(toggle); add_child(clock_button)
	_create_portrait_studio(); _populate(); _update_clock(); _layout()
	get_viewport().size_changed.connect(_layout)

func _place(control: Control,rect: Rect2) -> void:
	panel.add_child(control); control.position=rect.position; control.size=rect.size

func _label(text: String,rect: Rect2,font_size: int,color: Color=INK) -> Label:
	var label:=Label.new(); label.text=text; label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color); label.mouse_filter=Control.MOUSE_FILTER_IGNORE; _place(label,rect); return label

func _button(text: String,rect: Rect2) -> Button:
	var button:=Button.new(); button.text=text; _place(button,rect); return button

func _style(fill: Color,border: Color,width: int=1) -> StyleBoxFlat:
	var style:=StyleBoxFlat.new(); style.bg_color=fill; style.border_color=border
	style.set_border_width_all(width); style.set_corner_radius_all(4); style.set_content_margin_all(8); return style

func _layout() -> void:
	var viewport:=get_viewport().get_visible_rect().size
	var zoom:=minf(viewport.x/1480.0,viewport.y/830.0)
	panel.scale=Vector2.ONE*zoom; panel.position=(viewport-panel.size*zoom)*.5

func is_open() -> bool: return panel!=null and panel.visible

func toggle() -> void:
	if game.journey and game.journey.is_open(): return
	panel.visible=not panel.visible; shade.visible=panel.visible; clock_button.visible=not panel.visible
	if panel.visible:
		game.panels.open(self)
		day_picker.select(life.day_index()); _populate(); list.focus_selected()
	else:
		game.panels.close(self)

func _input(event: InputEvent) -> void:
	if game.mayor != null and game.mayor.active: return
	if game.journey and game.journey.is_open(): return
	if event is InputEventJoypadButton and event.pressed and event.button_index==JOY_BUTTON_B and is_open():
		toggle(); get_viewport().set_input_as_handled(); return
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode==KEY_ESCAPE and is_open():
		toggle(); get_viewport().set_input_as_handled()
	elif event.keycode==KEY_N and (not is_open() or not (search.has_focus() or _notes.has_focus())):
		toggle(); get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	_refresh+=delta
	if _refresh<.5 or life==null: return
	_refresh=0; _update_clock()
	if is_open():
		_update_live_person(); _grid.queue_redraw()

func _update_clock() -> void:
	clock_button.text=life.clock_text()+"  ·  N  Journal"
	_journal_clock.text=life.clock_text()
	count_label.text="%d island residents  ·  %d in this view" % [life.residents.size(),shown_ids.size()]

func _populate() -> void:
	shown_ids.clear(); list.clear()
	var query:=search.text.strip_edges().to_lower()
	var records: Array=life.residents.duplicate()
	var field: String=["name","occupation","district"][_sort.selected]
	records.sort_custom(func(a: Resident,b: Resident): return String(a.get(field))+a.name<String(b.get(field))+b.name)
	for r in records:
		var haystack: String=(r.name+" "+r.occupation+" "+r.district).to_lower()
		if not query.is_empty() and not query in haystack: continue
		shown_ids.append(r.id)
		var index: int=list.add_item("%s\n%s · %s" % [r.name,r.occupation,r.district],_portraits.get(r.id))
		list.set_item_tooltip(index,r.home)
		if not _portraits.has(r.id) and r.id not in _portrait_queue: _portrait_queue.append(r.id)
	if shown_ids.is_empty():
		selected_id=""; _name.text="No matches"; _occupation.text="Try another name, job or place."
		_home.text=""; _now.text=""; _travel.text=""; details.text=""; _portrait.texture=null
		_grid.record=null; _grid.queue_redraw(); _notes.editable=false; _editing_notes=true; _notes.text=""; _editing_notes=false
	else:
		if selected_id not in shown_ids: selected_id=shown_ids[0]
		list.select(shown_ids.find(selected_id)); list.ensure_current_is_visible(); _select_person(selected_id)
	_update_clock(); _render_next_portrait()

func _select_person(id: String) -> void:
	selected_id=id
	var r: Resident=life.by_id[id]
	_name.text=r.name; _occupation.text=r.occupation+"  |  "+r.district
	_home.text="Lives at "+r.home+"."
	_portrait.texture=_portraits.get(id)
	_notes.editable=true; _editing_notes=true; _notes.text=String(_notes_by_id.get(id,"")); _editing_notes=false
	_grid.record=r; _show_day(); _update_live_person()
	if not _portraits.has(id):
		_portrait_queue.erase(id); _portrait_queue.push_front(id); _render_next_portrait()

func _update_live_person() -> void:
	if selected_id.is_empty(): return
	var r: Resident=life.by_id[selected_id]
	_home.text="Lives at "+r.home+".\nWork completed: %d tasks" % r.completed_tasks
	_now.text="Now  ·  "+String(r.status)
	var distance:=0.0
	if game.entities.focus: distance=game.entities.focus.global_position.distance_to(r.position)
	_travel.text=("Travels by village runabout" if r.transport=="car" else "Walks the island paths")+"  ·  %.0f m away" % distance

func _show_day() -> void:
	if selected_id.is_empty(): return
	var r: Resident=life.by_id[selected_id]
	_grid.selected_day=day_picker.selected; _grid.queue_redraw()
	var text:=""
	for entry in r.schedule_for(day_picker.selected):
		text+="[b]%s–%s[/b]  %s\n" % [_time(entry.at),_time(entry.until),entry.task]
	details.text=text; details.scroll_to_line(0)

func _time(minute: int) -> String: return "%02d:%02d" % [minute/60,minute%60]

func save_state() -> Dictionary:
	return {"version":1,"notes":_notes_by_id.duplicate(),"selected_id":selected_id}

func load_state(data: Dictionary) -> void:
	_notes_by_id=data.get("notes",{}).duplicate(); selected_id=String(data.get("selected_id",""))
	if panel: _populate()

func _create_portrait_studio() -> void:
	_portrait_view=SubViewport.new(); _portrait_view.size=Vector2i(240,280); _portrait_view.own_world_3d=true
	_portrait_view.render_target_update_mode=SubViewport.UPDATE_DISABLED; add_child(_portrait_view)
	var env:=WorldEnvironment.new(); env.environment=Environment.new(); env.environment.background_mode=Environment.BG_COLOR
	env.environment.background_color=Color("91aeb0"); env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color=Color("fff0d1"); env.environment.ambient_light_energy=.7; _portrait_view.add_child(env)
	var light:=DirectionalLight3D.new(); light.rotation_degrees=Vector3(-35,-35,0); light.light_energy=1.6; _portrait_view.add_child(light)
	_portrait_model=RiderModel.new(); _portrait_model.look=CharacterLook.from_seed(0,&"island",""); _portrait_model.async_build=true
	_portrait_view.add_child(_portrait_model)
	var camera:=Camera3D.new(); _portrait_view.add_child(camera); camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=.93; camera.position=Vector3(-.18,1.60,-3); camera.look_at(Vector3(0,1.51,0)); camera.current=true

func _render_next_portrait() -> void:
	if DisplayServer.get_name()=="headless": return
	if _portrait_busy or _portrait_queue.is_empty() or _portrait_view==null: return
	_portrait_busy=true
	while not _portrait_queue.is_empty():
		var id: String=_portrait_queue.pop_front()
		if not life.by_id.has(id) or _portraits.has(id): continue
		# build the person off the main thread; the journal stays responsive meanwhile
		var look:=CharacterLook.for_resident(life.by_id[id])
		PersonBuilder.request(look)
		while not PersonBuilder.is_cached(look):
			PersonBuilder.poll()
			await get_tree().process_frame
			if not is_inside_tree(): return
		_portrait_model.set_look(look)
		_portrait_view.render_target_update_mode=SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		if not is_inside_tree(): return
		var texture:=ImageTexture.create_from_image(_portrait_view.get_texture().get_image())
		_portraits[id]=texture
		var index:=shown_ids.find(id)
		if index>=0: list.set_item_icon(index,texture)
		if selected_id==id: _portrait.texture=texture
	_portrait_busy=false
