class_name MayorView
extends CanvasLayer
## The top-down Mayor view (F4): the colony sim over the courier game.
##   top bar       colony switcher, coins and the colony's stock, speed, pause, save, return
##   left pages    Colony (overview, needs, stock, buildings, notices, charter), Build (by
##                 category, costs, the placement ghost), Trade (ports, fleet, lanes, cargo
##                 rules, raid risk, trip log), and the core island's original tools: Jobs,
##                 Areas, Paths
##   right panel   the building inspector (workers, flow, buffers, efficiency, pause, demolish)
##   the map       lanes, ships, colony names, the build area and footprints (ColonyViews)
## Mouse: left click selects / places, right drag pans, wheel zooms. Keys: WASD pan, Q/E rotate,
## R rotate the ghost, Esc cancels a tool (or leaves), F4 returns. See README "Colonies".
var game: Node3D
var colony: Node
signal active_changed(value: bool)
signal save_requested
var previous_camera: Camera3D
var _configured := false
var active: bool = false
var entry_pointer_pressed: bool = false
var camera: Camera3D
var map_focus: Node3D
var center := Vector3(0,0,10)
var yaw: float = -0.6
var zoom: float = 85
var tool: String = "Select"
var drawing: bool = false
var panning: bool = false
var stroke := PackedVector3Array()
var anchor := Vector3.ZERO
var root: Control
var entry: Button
var sidebar: VBoxContainer
var content: VBoxContainer
var title_label: Label
var stock_label: Label
var help_label: Label
var note: Label
var pause_button: Button
var speed_button: Button
var colony_picker: OptionButton
var inspector: PanelContainer
var inspector_box: VBoxContainer
var selected_id: String = ""
var colony_id := "core"
var selected_building := ""
var current_page: String = "Colony"
var rows: Dictionary = {}
var role_choice: OptionButton
var work_toggle: CheckButton
var detail: Label
var clock: float = 0
var cursor_mesh: MeshInstance3D
var marker: MeshInstance3D
var resident_markers: MultiMeshInstance3D
var ghost: MeshInstance3D
var ghost_yaw_turns := 0
var ghost_ok := false
var trade: MayorTradePage
var _live: Dictionary = {}          # name -> Control refreshed with the readouts
var _signature := ""
var _structure_t := 0.0

const T = preload("res://ui/mayor/mayor_theme.gd")
const PAGES := [["Colony", "Build", "Trade"], ["Jobs", "Areas", "Paths"]]


func setup(p_game: Node3D, p_colony: Node) -> void:
	game = p_game
	colony = p_colony
	if _configured: return
	_configured = true
	trade = MayorTradePage.new(self)
	if not game.life.residents.is_empty(): selected_id = game.life.residents[0].id
	layer = 20
	map_focus = Node3D.new()
	map_focus.name = "MayorMapFocus"
	game.add_child(map_focus)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.far = 40000
	camera.near = 0.5
	game.add_child(camera)
	cursor_mesh = MeshInstance3D.new()
	game.add_child(cursor_mesh)
	ghost = MeshInstance3D.new(); ghost.name = "MayorGhost"
	var gm := StandardMaterial3D.new(); gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; gm.vertex_color_use_as_albedo = true
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; gm.cull_mode = BaseMaterial3D.CULL_DISABLED
	ghost.material_override = gm; ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	game.add_child(ghost); ghost.visible = false
	var ring := TorusMesh.new()
	ring.inner_radius = 0.8
	ring.outer_radius = 1.0
	marker = MeshInstance3D.new()
	marker.mesh = ring
	marker.material_override = marker_material()
	game.add_child(marker)
	marker.visible = false
	resident_markers = MultiMeshInstance3D.new()
	var discs := MultiMesh.new()
	discs.transform_format = MultiMesh.TRANSFORM_3D
	discs.use_colors = true
	var disc := CylinderMesh.new()
	disc.top_radius = 0.9
	disc.bottom_radius = 0.9
	disc.height = 0.12
	disc.radial_segments = 12
	discs.mesh = disc
	discs.instance_count = game.life.residents.size()
	resident_markers.multimesh = discs
	var map_material := marker_material()
	map_material.albedo_color = Color.WHITE
	map_material.vertex_color_use_as_albedo = true
	map_material.no_depth_test = true
	resident_markers.material_override = map_material
	resident_markers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	game.add_child(resident_markers)
	resident_markers.visible = false
	entry = Button.new()
	entry.text = "Mayor view  [F4]"
	entry.theme = T.theme()
	entry.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	entry.offset_left = -96
	entry.offset_right = 96
	entry.offset_top = 60
	entry.offset_bottom = 98
	entry.pressed.connect(toggle)
	add_child(entry)
	root = Control.new()
	root.theme = T.theme()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	# top bar: the journal's green band
	var top := panel(root,16,16,-16,88,true,false,T.band())
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	top.add_child(bar)
	var branding := VBoxContainer.new()
	branding.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(branding)
	title_label = label(branding,"COLONIES  /  MAYOR VIEW",21,T.BAND_TEXT)
	stock_label = label(branding,"",13,Color("e5d6b7"))
	stock_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	stock_label.clip_text = true
	colony_picker = OptionButton.new(); colony_picker.focus_mode = Control.FOCUS_NONE
	colony_picker.custom_minimum_size = Vector2(210, 34)
	colony_picker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	colony_picker.item_selected.connect(func(i: int): select_colony(EconomyCatalog.COLONIES.keys()[i], true))
	colony_picker.tooltip_text = "Switch colony (the camera flies there)."
	bar.add_child(colony_picker)
	speed_button = button(bar,"Speed 1x",func(): cycle_speed())
	speed_button.tooltip_text = "Colony time: 1x, 2x, 4x."
	button(bar,"Save  F5",func(): save_requested.emit())
	pause_button = button(bar,"Pause colony",func(): colony.set_paused(not colony.paused); refresh_readouts())
	button(bar,"Return  F4",toggle)
	# the left pages: a paper panel
	var side := panel(root,16,106,376,-112,false,true,T.paper())
	sidebar = VBoxContainer.new()
	sidebar.add_theme_constant_override("separation",6)
	side.add_child(sidebar)
	for group in PAGES:
		var tabs := HBoxContainer.new()
		tabs.add_theme_constant_override("separation",4)
		sidebar.add_child(tabs)
		for page in group:
			var tb := button(tabs,page,func(): current_page=page; set_tool("Select"); build_page())
			tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			tb.custom_minimum_size.y = 30
			tb.name = "Tab" + page
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar.add_child(scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation",6)
	scroll.add_child(content)
	# the building inspector, right
	inspector = panel(root,-376,106,-16,-112,true,true,T.paper())
	inspector.anchor_left = 1
	var iscroll := ScrollContainer.new(); iscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inspector.add_child(iscroll)
	inspector_box = VBoxContainer.new(); inspector_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector_box.add_theme_constant_override("separation", 5)
	iscroll.add_child(inspector_box)
	inspector.visible = false
	# the footer: help, the latest notice, the keys
	var footer := panel(root,16,-100,-16,-16,true,true,T.band())
	footer.anchor_top = 1
	var bottom := VBoxContainer.new()
	footer.add_child(bottom)
	help_label = label(bottom,"Choose a colony, then build, trade or assign jobs.",15,T.BAND_TEXT)
	note = label(bottom,"",13,Color("f6ce75"))
	label(bottom,"WASD pan · Q/E rotate · Wheel zoom · Right-drag pan · R rotate building · Esc cancel tool · F4 return",12,Color("c9c0a8"))
	root.visible = false
	colony.changed.connect(func(): if active and current_page in ["Jobs","Areas","Paths"]: build_page())
	colony.message.connect(show_note)
	_fill_colony_picker()
	build_page()


func panel(parent: Control, left: float, top: float, right: float, bottom: float, right_anchor: bool, bottom_anchor: bool, style: StyleBox = null) -> PanelContainer:
	var node := PanelContainer.new()
	parent.add_child(node)
	if right_anchor: node.anchor_right = 1
	if bottom_anchor: node.anchor_bottom = 1
	node.offset_left = left
	node.offset_right = right
	node.offset_top = top
	node.offset_bottom = bottom
	node.add_theme_stylebox_override("panel",style if style != null else T.paper())
	return node
func label(parent: Node, text: String, size: int, color: Color = T.INK) -> Label:
	return T.label(parent, text, size, color)
func button(parent: Node, text: String, action: Callable) -> Button:
	var node := T.button(parent, text, action, 14)
	node.custom_minimum_size.y = 32
	return node
func marker_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("efc877")
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat
func blocks_world_input() -> bool:
	return active or entry_pointer_pressed or (entry != null and entry.visible and entry.get_global_rect().has_point(entry.get_global_mouse_position()))
func close_panel() -> void:
	set_active(false)
func toggle() -> void:
	set_active(not active)
func set_active(value: bool) -> void:
	if not _configured or active == value: return
	if value:
		if game.panels.any_open(): return
		if game.rider.mode != Rider.Mode.ON_FOOT or not game.player.is_on_floor():
			show_note("Dismount on solid ground to enter Mayor view.")
			game.hud.show_message("Dismount on solid ground to enter Mayor view.",3.0)
			entry.tooltip_text = "Dismount on solid ground to enter Mayor view."
			return
	active = value
	drawing = false
	panning = false
	stroke.clear()
	cursor_mesh.visible = false
	ghost.visible = false
	root.visible = active
	marker.visible = active
	resident_markers.visible = active
	entry.visible = not active
	if active:
		previous_camera = get_viewport().get_camera_3d()
		center = game.player.global_position
		# open on the colony the courier stands in, if any
		var here := nearest_colony(center)
		if here != "": select_colony(here, false)
		camera.make_current()
		game.world.terrain.set_view_camera(camera)
		_fill_colony_picker()
		build_page()
		update_camera()
	else:
		camera.current = false
		if is_instance_valid(previous_camera):
			previous_camera.make_current()
			game.world.terrain.set_view_camera(previous_camera)
	if colony.economy and colony.economy.views: colony.economy.views.set_map(active, colony_id, zoom)
	active_changed.emit(active)


func economy() -> ColonyEconomy:
	return colony.economy


## The founded colony whose build area holds `p` ("" if none).
func nearest_colony(p: Vector3) -> String:
	var best := ""; var d := INF
	for cid in economy().towns:
		var t: ColonyTown = economy().towns[cid]
		var e := Vector2(t.hall.x - p.x, t.hall.z - p.z).length()
		if t.founded and e < EconomyCatalog.build_radius(cid) + 150.0 and e < d: d = e; best = cid
	return best


func select_colony(cid: String, fly: bool) -> void:
	colony_id = cid
	selected_building = ""
	inspector.visible = false
	set_tool("Select")
	if fly:
		var t := economy().town(cid)
		center = t.hall
		zoom = 300.0 if t.founded else 700.0
		update_camera()
	_fill_colony_picker()
	if economy().views: economy().views.set_map(active, colony_id, zoom)
	build_page()


func _fill_colony_picker() -> void:
	if colony_picker == null: return
	colony_picker.clear()
	var keys := EconomyCatalog.COLONIES.keys()
	for i in range(keys.size()):
		var t := economy().town(keys[i])
		colony_picker.add_item("%s%s" % [t.display_name.get_slice(" (", 0), "" if t.founded else (" · charter" if t.discovered else " · unvisited")])
		if keys[i] == colony_id: colony_picker.select(i)


func cycle_speed() -> void:
	var e := economy()
	e.time_scale = 2.0 if e.time_scale < 1.5 else (4.0 if e.time_scale < 3.0 else 1.0)
	refresh_readouts()


func resident(id: String) -> Resident:
	for person: Resident in game.life.residents:
		if person.id == id: return person
	return null


func set_tool(value: String) -> void:
	tool = value
	drawing = false
	stroke.clear()
	cursor_mesh.visible = false
	if ghost: ghost.visible = false
	if help_label == null: return
	if value.begins_with("place:"):
		var def := EconomyCatalog.building(value.trim_prefix("place:"))
		help_label.text = "Place %s: %s. Click clear flat ground inside the ring · R rotates · Esc cancels." % [def.name, EconomyCatalog.describe_cost(def.cost, int(def.coins))]
		return
	help_label.text = {"Select":"Click a building to inspect it, or a villager in Jobs. Choose Build to place.","Road":"Drag a road around obstacles. Villagers prefer its connected route.","Path":"Drag a footpath. Villagers prefer paths over unmarked ground.","Erase":"Click an existing road or path to remove its stroke."}.get(value,"Click and drag over matching resources." if value.begins_with("zone:") else "Click clear ground to place a blueprint. Construction costs 10 timber.")


# ------------------------------------------------------------------ pages
func build_page() -> void:
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	rows.clear()
	_live.clear()
	role_choice = null
	work_toggle = null
	detail = null
	for group in PAGES:
		for page in group:
			var tb := sidebar.find_child("Tab" + page, true, false) as Button
			if tb: tb.add_theme_stylebox_override("normal", T.box(Color("bfd1d1") if page == current_page else T.PAPER_DEEP, Color("73909a") if page == current_page else T.EDGE))
	match current_page:
		"Colony": _page_colony()
		"Build": _page_build()
		"Trade": trade.build(content)
		"Jobs": _page_jobs()
		"Areas": _page_areas()
		_: _page_paths()
	button(content,"Select / cancel tool",func(): set_tool("Select"))
	_signature = _structure()
	refresh_readouts()


func _page_colony() -> void:
	var e := economy()
	var t := e.town(colony_id)
	label(content, t.display_name, 20)
	if not t.founded:
		if colony_id == "core": return
		label(content, ("Visited. A founding charter costs %d coins and brings a colony hall with a warehouse, %d settlers and a starter stock (planks, blocks, tools, food)." % [e.charter_cost(colony_id), EconomyCatalog.CHARTER_SETTLERS]) if t.discovered else "Ride to %s to discover it; then it can be chartered as a colony." % t.display_name, 14)
		var raw := PackedStringArray()
		for r in EconomyCatalog.COLONIES[colony_id].raw: raw.append(EconomyCatalog.item_name(r).to_lower())
		label(content, "The land gives: " + ", ".join(raw) + ".", 13, T.MUTED)
		var b := button(content, "Found colony · %d coins" % e.charter_cost(colony_id), func():
			var err := e.found(colony_id)
			show_note(err if err != "" else "%s founded." % t.display_name)
			_fill_colony_picker(); select_colony(colony_id, true))
		b.disabled = not t.discovered
		return
	_live.pop = label(content, "", 14)
	_live.happy = T.bar(content, "Happiness", t.happiness / 100.0, T.ACCENT)
	_live.food = T.bar(content, "Food", t.needs.food)
	_live.variety = T.bar(content, "Variety", t.needs.variety)
	_live.goods = T.bar(content, "Goods", t.needs.goods)
	_live.housing = T.bar(content, "Housing", t.needs.housing)
	_live.growth = T.bar(content, "Next settler", t.growth, Color("c9a24a"))
	label(content, "Food: bread, fish, preserved fish, dates, olives, berries (variety helps). Goods: cloth, tools, oil, wine.", 11, T.MUTED)
	T.rule(content)
	T.heading(content, "Stockpile")
	_live.capacity = label(content, "", 12, T.MUTED)
	_live.stock = label(content, "", 13)
	T.rule(content)
	T.heading(content, "Buildings")
	for b in t.buildings:
		if b.get("virtual", false): continue
		var bid: String = b.id
		var bb := button(content, "%s · %s" % [EconomyCatalog.building(b.type).name, t.status(b)], func(): inspect(bid, true))
		bb.clip_text = true; bb.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		bb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		bb.add_theme_font_size_override("font_size", 13)
	T.rule(content)
	T.heading(content, "Notices")
	_live.log = label(content, "", 12, T.MUTED)


func _page_build() -> void:
	var e := economy()
	var t := e.town(colony_id)
	label(content, "BUILD · " + t.display_name.to_upper(), 17)
	if not t.founded:
		label(content, "Found the colony first (Colony page).", 14)
		return
	label(content, "Coins come from your wallet, materials from the colony's stockpile. Buildings rise on a staked foundation and a scaffold; colonists without jobs build faster.", 12, T.MUTED)
	for cat in EconomyCatalog.CATEGORIES:
		T.heading(content, cat[1])
		for type in EconomyCatalog.BUILDINGS:
			var def: Dictionary = EconomyCatalog.BUILDINGS[type]
			if def.cat != cat[0] or def.get("unique", false): continue
			var ok := EconomyCatalog.buildable_in(colony_id, type)
			var afford := t.can_afford(def.cost) and e.coins() >= int(def.coins)
			var flow := EconomyCatalog.describe_flow(def)
			var b := button(content, "%s · %s" % [def.name, EconomyCatalog.describe_cost(def.cost, int(def.coins))], func(): set_tool("place:" + type))
			b.clip_text = true; b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.add_theme_font_size_override("font_size", 13)
			b.disabled = not ok
			var tip := PackedStringArray()
			if flow != "": tip.append(flow)
			if def.has("workers"): tip.append("%d workers · storage %d" % [int(def.workers), int(def.get("storage", 0))])
			if def.has("housing"): tip.append("Houses %d colonists" % int(def.housing))
			if def.has("capacity"): tip.append("+%d stockpile capacity" % int(def.capacity))
			if def.get("coast", false): tip.append("By the water")
			if def.get("port", false): tip.append("Near the berth; builds ships")
			if not ok: tip.append("Needs %s, which %s does not have." % [EconomyCatalog.item_name(String(def.get("raw", ""))).to_lower(), t.display_name])
			elif not afford: tip.append("Cannot afford it yet.")
			b.tooltip_text = "\n".join(tip)
			if ok and not afford: b.modulate = Color(1, 1, 1, 0.6)
			if flow != "" and ok: label(content, "   " + flow, 11, T.MUTED)
	if colony_id == "core":
		T.rule(content)
		T.heading(content, "Island workplaces (timber blueprints)")
		label(content,"Place a blueprint. Builders carry 10 timber from the warehouse to finish it. Gather timber first.",12,T.MUTED)
		for kind in ColonyCatalog.WORKPLACES:
			button(content,kind+" · 10 timber",func(): set_tool("build:"+kind))
		label(content,"Camps store gathered goods nearby. Transporters bring them to the warehouse. Farms grow renewable olives.",12,T.MUTED)
		for site in colony.sites.values():
			label(content,site.blueprint+(" · Ready" if site.built else " · %d/10 timber"%site.inventory.get("wood",0)),12)


func _page_jobs() -> void:
	label(content,"RESIDENTS / PROFESSIONS",17)
	var roster_scroll := ScrollContainer.new()
	roster_scroll.custom_minimum_size.y = 218
	roster_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(roster_scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roster_scroll.add_child(list)
	for worker: Resident in game.life.residents:
		var row := button(list,worker.name,func(): selected_id=worker.id; build_page())
		row.add_theme_font_size_override("font_size",13)
		row.custom_minimum_size.y = 28
		rows[worker.id] = row
	label(content,"ASSIGN PROFESSION",14)
	label(content,"Choose a resident near the work area. Colony routes cover up to 256 m per trip.",12,T.MUTED)
	role_choice = OptionButton.new()
	for role in ColonyCatalog.CORE: role_choice.add_item(role)
	role_choice.get_popup().add_separator("Future workplaces")
	for role in ColonyCatalog.PROFESSIONS:
		if role in ColonyCatalog.CORE: continue
		role_choice.add_item(role+" · planned")
		role_choice.set_item_disabled(role_choice.item_count-1,true)
	role_choice.custom_minimum_size.y = 36
	content.add_child(role_choice)
	role_choice.select(ColonyCatalog.CORE.find(colony.assignments[selected_id].role))
	role_choice.item_selected.connect(func(index):
		if index<ColonyCatalog.CORE.size(): colony.assign_role(selected_id,ColonyCatalog.CORE[index])
	)
	work_toggle = CheckButton.new()
	work_toggle.text = "Work enabled"
	work_toggle.set_pressed_no_signal(colony.assignments[selected_id].enabled)
	work_toggle.toggled.connect(func(value): colony.assign_role(selected_id,colony.assignments[selected_id].role,value))
	content.add_child(work_toggle)
	detail = label(content,"",13)
	button(content,"Find villager",func(): center=resident(selected_id).position)
	button(content,"Retry blocked job",func(): colony.retry_worker(selected_id))


func _page_areas() -> void:
	label(content,"DESIGNATE RESOURCES",17)
	label(content,"Drag a circle over visible resources, then assign the matching profession in Jobs.",13,T.MUTED)
	for pair in [["Forager","Gather berries"],["Woodcutter","Cut timber"],["Miner","Mine ore / stone"],["Farmer","Harvest olives"]]:
		button(content,pair[1],func(): set_tool("zone:"+pair[0]))
	for area in colony.areas:
		label(content,"%s · %d stands"%[area.role,colony.area_sources(area).size()],14)
		var row := HBoxContainer.new()
		content.add_child(row)
		button(row,"Disable" if area.enabled else "Enable",func(): colony.set_area_enabled(area.id,not area.enabled))
		button(row,"Remove",func(): colony.remove_area(area.id))


func _page_paths() -> void:
	label(content,"DRAW THE CONNECTIONS",17)
	label(content,"Drag local paths between resources and workplaces (256 m trips). Roads take priority; water and obstacles remain impassable.",13,T.MUTED)
	button(content,"Draw road",func(): set_tool("Road"))
	button(content,"Draw footpath",func(): set_tool("Path"))
	button(content,"Erase stroke",func(): set_tool("Erase"))
	button(content,"Undo last stroke",func():
		if not colony.roads.roads.is_empty():
			colony.roads.roads.pop_back()
			colony.roads.rebuild()
			colony.replan_workers()
	)
	label(content,"Roads: %d / 64"%colony.roads.roads.size(),13)


## What the page's layout depends on; a change rebuilds it (numbers only refresh).
func _structure() -> String:
	var e := economy()
	if current_page == "Colony":
		var t := e.town(colony_id)
		var parts := PackedStringArray([str(t.founded), str(t.discovered)])
		for b in t.buildings: parts.append("%s%s%s" % [b.id, b.built, t.status(b).get_slice(" (", 0)])
		return "|".join(parts)
	if current_page == "Trade":
		var parts := PackedStringArray([str(e.ports_ready)])
		for s in e.shipping.ships: parts.append("%s%s%s%s%d" % [s.id, s.state, s.lane, s.port, int(s.trips)])
		for l in e.shipping.lanes: parts.append("%s%d%d" % [l.id, l.log.size(), int(e.shipping.lane_risk(l) * 100)])
		return "|".join(parts)
	if current_page == "Build":
		return "%d|%d" % [e.coins(), e.town(colony_id).stock.hash()]
	return ""


# ------------------------------------------------------------------ the inspector
func inspect(bid: String, fly := false) -> void:
	selected_building = bid
	var t := economy().town(colony_id)
	var b := t.building(bid)
	if b.is_empty():
		inspector.visible = false
		return
	if fly:
		center = Vector3(float(b.x), float(b.y), float(b.z)); zoom = minf(zoom, 90.0); update_camera()
	_build_inspector()


func _build_inspector() -> void:
	for c in inspector_box.get_children(): c.queue_free()
	var t := economy().town(colony_id)
	var b := t.building(selected_building)
	if b.is_empty():
		inspector.visible = false
		return
	inspector.visible = true
	var def := EconomyCatalog.building(b.type)
	var head := T.row(inspector_box)
	label(head, def.name, 19).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	T.button(head, "Close", func(): selected_building = ""; inspector.visible = false, 12)
	label(inspector_box, t.display_name, 12, T.MUTED)
	_live.i_status = label(inspector_box, "", 14)
	var flow := EconomyCatalog.describe_flow(def)
	if flow != "": label(inspector_box, "Cycle: " + flow, 13)
	if def.has("workers"): _live.i_workers = label(inspector_box, "", 13)
	if def.has("outputs"):
		_live.i_eff = T.bar(inspector_box, "Efficiency", t.efficiency(b), T.ACCENT)
		_live.i_cycle = T.bar(inspector_box, "This cycle", float(b.cycle), Color("c9a24a"))
		_live.i_buffers = label(inspector_box, "", 12)
		_live.i_porter = label(inspector_box, "", 12, T.MUTED)
	if def.has("housing"): label(inspector_box, "Houses %d colonists." % int(def.housing), 13)
	if def.has("capacity"): label(inspector_box, "Adds %d to the stockpile's capacity." % int(def.capacity), 13)
	if b.type == "shipyard": label(inspector_box, "Lay down ships on the Trade page.", 13, T.MUTED)
	if not b.built: _live.i_build = T.bar(inspector_box, "Construction", float(b.progress), Color("c9a24a"))
	T.rule(inspector_box)
	var actions := T.row(inspector_box)
	var bid: String = b.id
	if def.has("workers"):
		T.button(actions, "Resume" if b.paused else "Pause", func(): economy().toggle_pause(colony_id, bid); _build_inspector(), 13).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if b.type != "colony_hall":
		T.button(actions, "Demolish", func():
			economy().remove(colony_id, bid); selected_building = ""; inspector.visible = false
			show_note("%s demolished; its goods went back to the stockpile." % def.name); build_page(), 13).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	T.button(inspector_box, "Centre on it", func(): inspect(bid, true), 12)
	refresh_readouts()


func show_note(text: String) -> void:
	if note: note.text = text


func focus_route(lid: String) -> void:
	var sh := economy().shipping
	var l := sh.lane(lid)
	if l.is_empty(): return
	var r := sh.route(l.from, l.to)
	if r.is_empty(): return
	var box := Rect2(r.points[0], Vector2.ZERO)
	for p in r.points: box = box.expand(p)
	center = Vector3(box.get_center().x, 0, box.get_center().y)
	zoom = clampf(maxf(box.size.x, box.size.y) * 1.1, 400.0, 1800.0)
	update_camera()


# ------------------------------------------------------------------ camera and input
func update_camera() -> void:
	center.x = clampf(center.x,-12450,12450)
	center.z = clampf(center.z,-12450,12450)
	center.y = maxf(game.world.terrain.height_at(center.x,center.z), 0.0)
	map_focus.position = center
	camera.size = zoom
	var distance := maxf(120.0, zoom * 1.15)
	camera.position = center+Vector3(sin(yaw)*distance,distance*0.85,cos(yaw)*distance)
	camera.look_at(center)
func project_ground(screen: Vector2) -> Variant:
	# Terrain height queries remain available outside streamed collision tiles.
	# Bracket the ray then bisect; a flat-plane projection fails on coastal cliffs.
	var origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	if direction.y >= -0.001: return null
	var previous := 0.0
	for step in range(1,257):
		var distance := step * 32.0
		var point := origin + direction * distance
		if absf(point.x)>12500 or absf(point.z)>12500: return null
		if point.y <= game.world.terrain.height_at(point.x,point.z):
			var low := previous
			var high := distance
			for iteration in 15:
				var middle := (low+high)*0.5
				var sample := origin+direction*middle
				if sample.y > game.world.terrain.height_at(sample.x,sample.z): low=middle
				else: high=middle
			return origin+direction*((low+high)*0.5)
		previous = distance
	return null
func pointer_over_ui(position: Vector2) -> bool:
	for child in root.get_children():
		if child is Control and child.visible and child.get_global_rect().has_point(position): return true
	return false
func _input(event: InputEvent) -> void:
	if not _configured: return
	if active and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if tool != "Select": set_tool("Select")
			else: set_active(false)
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_R and tool.begins_with("place:"):
			ghost_yaw_turns = (ghost_yaw_turns + 1) % 4
			_update_ghost(ghost.global_position if ghost.visible else center)
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if not event.pressed: entry_pointer_pressed = false
		elif entry.visible and entry.get_global_rect().has_point(event.position): entry_pointer_pressed = true
	if not active or not event is InputEventMouseButton or event.pressed: return
	# A drag released over a panel never reaches unhandled input. Cancel it here.
	if event.button_index==MOUSE_BUTTON_RIGHT: panning = false
	if event.button_index==MOUSE_BUTTON_LEFT and drawing:
		if pointer_over_ui(event.position):
			drawing = false
			stroke.clear()
			cursor_mesh.visible = false
			get_viewport().set_input_as_handled()
func _unhandled_input(event: InputEvent) -> void:
	if not active: return
	if event is InputEventMouseButton and pointer_over_ui(event.position): return
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_WHEEL_UP and event.pressed: zoom=maxf(35,zoom/1.12)
		elif event.button_index==MOUSE_BUTTON_WHEEL_DOWN and event.pressed: zoom=minf(2400,zoom*1.12)
		elif event.button_index==MOUSE_BUTTON_RIGHT:
			panning = event.pressed
		elif event.button_index==MOUSE_BUTTON_LEFT:
			var at: Variant = project_ground(event.position)
			if tool.begins_with("place:"):
				if not event.pressed and at != null: place_at(at)
			elif event.pressed and at!=null:
				anchor = at
				stroke = PackedVector3Array([at])
				drawing = true
				if tool=="Select": select_at(at)
			elif not event.pressed and drawing:
				drawing = false
				if at!=null: finish_stroke(at)
				cursor_mesh.visible = false
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		if panning:
			var right := camera.global_basis.x
			var forward := -camera.global_basis.z
			forward.y = 0
			center += (-right*event.relative.x+forward.normalized()*event.relative.y)*zoom/get_viewport().get_visible_rect().size.y
		elif tool.begins_with("place:"):
			var at: Variant = project_ground(event.position)
			if at!=null: _update_ghost(at)
		elif tool.begins_with("build:") and not drawing:
			var at: Variant = project_ground(event.position)
			if at!=null: preview(at)
		elif drawing:
			var at: Variant = project_ground(event.position)
			if at!=null and stroke[stroke.size()-1].distance_to(at)>2: stroke.append(at)
			if at!=null: preview(at)


## Select: a colony building under the pointer opens the inspector; else a villager.
func select_at(at: Vector3) -> void:
	var e := economy()
	for cid in e.towns:
		var t: ColonyTown = e.towns[cid]
		for b in t.buildings:
			if b.get("virtual", false): continue
			var f := ColonyEconomy.footprint(b.type)
			var local := Basis(Vector3.UP, float(b.yaw)).inverse() * (at - Vector3(float(b.x), at.y, float(b.z)))
			if absf(local.x) <= f.x and absf(local.z) <= f.y:
				if cid != colony_id:
					colony_id = cid; _fill_colony_picker()
					if current_page == "Colony" or current_page == "Build": build_page()
				inspect(b.id)
				return
	for worker: Resident in game.life.residents:
		if Vector2(worker.position.x-at.x,worker.position.z-at.z).length()<maxf(4.0,zoom*0.012): selected_id=worker.id; current_page="Jobs"; build_page(); break


func ghost_yaw(at: Vector3) -> float:
	var hall := economy().town(colony_id).hall
	var base := atan2(hall.x - at.x, hall.z - at.z)
	base = snappedf(base, PI * 0.5)
	return base + ghost_yaw_turns * PI * 0.5


func _update_ghost(at: Vector3) -> void:
	var type := tool.trim_prefix("place:")
	var y := ghost_yaw(at)
	var why: String = economy().check_site(colony_id, type, at, y)
	var ok := why == ""
	if ok != ghost_ok or ghost.mesh == null or String(ghost.get_meta("type", "")) != type:
		ghost.mesh = ColonyViews.ghost_mesh(type, ok); ghost.set_meta("type", type); ghost_ok = ok
	ghost.global_position = Vector3(at.x, economy()._pad(at, type, y) + 0.05, at.z)
	ghost.rotation = Vector3(0, y, 0)
	ghost.visible = true
	var def := EconomyCatalog.building(type)
	help_label.text = ("%s here · %s · R rotates · Esc cancels" % [def.name, EconomyCatalog.describe_cost(def.cost, int(def.coins))]) if ok else "%s: %s" % [def.name, why]


func place_at(at: Vector3) -> void:
	var type := tool.trim_prefix("place:")
	var err: String = economy().place(colony_id, type, at, ghost_yaw(at))
	if err != "":
		show_note(err)
		return
	show_note("%s started at %s." % [EconomyCatalog.building(type).name, economy().town(colony_id).display_name])
	build_page()


func finish_stroke(at: Vector3) -> void:
	if tool.begins_with("zone:"):
		colony.designate(tool.trim_prefix("zone:"),anchor,Vector2(at.x-anchor.x,at.z-anchor.z).length())
	elif tool.begins_with("build:"): colony.place_site(tool.trim_prefix("build:"),at)
	elif tool in ["Road","Path"]:
		stroke.append(at)
		if colony.roads.add_stroke(stroke,tool):
			colony.replan_workers()
			show_note("Route connected. Villagers now prefer it.")
		else: show_note(colony.roads.last_error)
	elif tool=="Erase":
		colony.roads.erase_at(at)
		colony.replan_workers()
	build_page()
func preview(at: Vector3) -> void:
	var mesh := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color("eac27a")
	mesh.surface_begin(Mesh.PRIMITIVE_LINES,mat)
	if tool.begins_with("build:"):
		var kind := tool.trim_prefix("build:")
		mat.albedo_color = Color("8fcb99") if colony.can_place(at,kind) else Color("d88572")
		var left := -8.0 if kind=="Farm" else -3.0
		var points := [Vector2(left,-3),Vector2(3,-3),Vector2(3,3),Vector2(left,3)]
		for i in range(4):
			for p: Vector2 in [points[i],points[(i+1)%4]]:
				mesh.surface_add_vertex(colony.grounded(Vector2(at.x+p.x,at.z+p.y))+Vector3.UP*0.15)
	elif tool.begins_with("zone:"):
		var radius := clampf(Vector2(at.x-anchor.x,at.z-anchor.z).length(),6,32)
		for i in range(64):
			for step in [i,i+1]:
				var p := Vector2(anchor.x,anchor.z)+Vector2(cos(step*TAU/64),sin(step*TAU/64))*radius
				mesh.surface_add_vertex(colony.grounded(p)+Vector3.UP*0.2)
	else:
		var points := stroke.duplicate()
		points.append(at)
		for i in range(points.size()-1):
			mesh.surface_add_vertex(points[i]+Vector3.UP*0.2)
			mesh.surface_add_vertex(points[i+1]+Vector3.UP*0.2)
	mesh.surface_end()
	cursor_mesh.mesh = mesh
	cursor_mesh.visible = true


# ------------------------------------------------------------------ readouts
func refresh_readouts() -> void:
	if stock_label==null: return
	var e := economy()
	var t := e.town(colony_id)
	title_label.text = "COLONIES  /  MAYOR VIEW  ·  " + t.display_name.to_upper()
	stock_label.text = "Coins %d  ·  %s" % [e.coins(), _stock_line(t) if t.founded else "not chartered"]
	pause_button.text = "Resume colony" if colony.paused else "Pause colony"
	speed_button.text = "Speed %dx" % int(e.time_scale)
	if not e.notifications.is_empty() and note.text == "": note.text = e.notifications[-1].text
	if _live.has("pop"):
		_live.pop.text = "%d colonists · housing %d · %d without work · +%d coins in taxes pending" % [t.colonists.size(), t.housing(), t.unemployed(), int(t.coins_due)]
		_live.happy.value = t.happiness
		_live.food.value = t.needs.food * 100.0; _live.variety.value = t.needs.variety * 100.0
		_live.goods.value = t.needs.goods * 100.0; _live.housing.value = t.needs.housing * 100.0
		_live.growth.value = t.growth * 100.0
		_live.capacity.text = "%d / %d capacity (by weight)" % [int(t.stock_mass()), int(t.capacity())]
		var lines := PackedStringArray()
		var keys := t.stock.keys(); keys.sort()
		for item in keys:
			if int(t.stock[item]) > 0: lines.append("%s %d" % [EconomyCatalog.item_name(item), int(t.stock[item])])
		_live.stock.text = "   ".join(lines) if not lines.is_empty() else "Empty."
		var notes := PackedStringArray()
		for n in t.journal.slice(maxi(0, t.journal.size() - 6)): notes.append("· " + String(n.text))
		_live.log.text = "\n".join(notes) if not notes.is_empty() else "Nothing yet."
	if inspector.visible and selected_building != "":
		var b := t.building(selected_building)
		if b.is_empty(): inspector.visible = false
		else:
			if _live.has("i_status"): _live.i_status.text = t.status(b)
			if _live.has("i_workers"): _live.i_workers.text = "Workers %d / %d%s" % [t.workers_at(b.id), t.workers_needed(b), "  (no free colonists)" if t.workers_at(b.id) < t.workers_needed(b) and t.unemployed() == 0 else ""]
			if _live.has("i_eff"):
				_live.i_eff.value = t.efficiency(b) * 100.0
				_live.i_cycle.value = float(b.cycle) * 100.0
				_live.i_buffers.text = "In: %s\nOut: %s   (storage %d)\nProduced so far: %d" % [_buf(b.inbuf), _buf(b.outbuf), int(EconomyCatalog.building(b.type).get("storage", 0)), int(b.produced)]
				var c: Dictionary = b.carry
				_live.i_porter.text = "Porter: " + ("waiting for goods" if c.is_empty() else ("to the warehouse with %s" % _buf(c.load) if int(c.phase) == 0 else "back with %s" % _buf(c.load)))
			if _live.has("i_build") and is_instance_valid(_live.i_build): _live.i_build.value = float(b.progress) * 100.0
	for id in rows:
		var worker := resident(id)
		var assignment: Dictionary = colony.assignments[id]
		rows[id].text = ("› " if id==selected_id else "")+worker.name+" · "+assignment.role+("  [off]" if not assignment.enabled else "  [on]")
	if detail and resident(selected_id)!=null:
		var worker := resident(selected_id)
		detail.text = "%s · %s\nCargo: %s\n%s"%[worker.name,worker.status,colony.worker_cargo(selected_id),colony.statuses.get(selected_id,"Enable work after marking a matching area.")]


func _stock_line(t: ColonyTown) -> String:
	var parts := PackedStringArray()
	for item in ["planks", "blocks", "tools", "wood", "stone", "bread", "fish"]:
		if t.count(item) > 0: parts.append("%s %d" % [EconomyCatalog.item_name(item).to_lower(), t.count(item)])
	return "%d colonists · %d%% happy · %s" % [t.colonists.size(), int(t.happiness), " · ".join(parts)]


static func _buf(d: Dictionary) -> String:
	if d.is_empty(): return "-"
	var parts := PackedStringArray()
	for item in d: parts.append("%d %s" % [int(d[item]), EconomyCatalog.item_name(item).to_lower()])
	return ", ".join(parts)


func _process(delta: float) -> void:
	if not _configured or not active: return
	var axis := Vector2(float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)),float(Input.is_physical_key_pressed(KEY_S))-float(Input.is_physical_key_pressed(KEY_W)))
	var forward := -camera.global_basis.z
	forward.y = 0
	center += (camera.global_basis.x*axis.x-forward.normalized()*axis.y)*delta*zoom*0.65
	if Input.is_physical_key_pressed(KEY_Q): yaw -= delta
	if Input.is_physical_key_pressed(KEY_E): yaw += delta
	update_camera()
	if economy().views: economy().views.set_map(true, colony_id, zoom)
	var marker_scale := clampf(zoom / 100.0, 1.0, 8.0)
	for index in game.life.residents.size():
		var person: Resident = game.life.residents[index]
		resident_markers.multimesh.set_instance_transform(index,Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*marker_scale),person.position+Vector3.UP*0.3))
		resident_markers.multimesh.set_instance_color(index,Color("f6ce75") if person.id==selected_id else Color("f1e5ca"))
	var selected := resident(selected_id)
	marker.visible = selected != null and current_page == "Jobs"
	if selected != null: marker.position = selected.position+Vector3.UP*0.15
	clock += delta
	_structure_t += delta
	if clock>=0.25:
		clock = 0
		refresh_readouts()
	if _structure_t >= 0.5:
		_structure_t = 0.0
		if current_page in ["Colony", "Trade", "Build"] and _structure() != _signature and not _popup_open(): build_page()


func _popup_open() -> bool:
	for n in content.find_children("*", "OptionButton", true, false):
		if (n as OptionButton).get_popup().visible: return true
	return colony_picker.get_popup().visible


func _exit_tree() -> void:
	if active: set_active(false)
	for node in [camera,cursor_mesh,marker,map_focus,resident_markers,ghost]:
		if is_instance_valid(node): node.queue_free()
