class_name MayorView
extends CanvasLayer
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
var selected_id: String = ""
var current_page: String = "Jobs"
var rows: Dictionary = {}
var role_choice: OptionButton
var work_toggle: CheckButton
var detail: Label
var clock: float = 0
var cursor_mesh: MeshInstance3D
var marker: MeshInstance3D
var resident_markers: MultiMeshInstance3D
func setup(p_game: Node3D, p_colony: Node) -> void:
	game = p_game
	colony = p_colony
	if _configured: return
	_configured = true
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
	entry.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	entry.offset_left = -96
	entry.offset_right = 96
	entry.offset_top = 60
	entry.offset_bottom = 98
	entry.pressed.connect(toggle)
	add_child(entry)
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var top := panel(root,16,16,-16,88,true,false)
	var bar := HBoxContainer.new()
	top.add_child(bar)
	var branding := VBoxContainer.new()
	branding.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(branding)
	title_label = label(branding,"ISLAND COLONY  /  MAYOR VIEW",22)
	stock_label = label(branding,"Island residents · Colony stores",13)
	button(bar,"Save  F5",func(): save_requested.emit())
	pause_button = button(bar,"Pause colony",func(): colony.set_paused(not colony.paused); refresh_readouts())
	button(bar,"Return  F4",toggle)
	var side := panel(root,16,106,344,-112,false,true)
	sidebar = VBoxContainer.new()
	sidebar.add_theme_constant_override("separation",8)
	side.add_child(sidebar)
	var tabs := HBoxContainer.new()
	sidebar.add_child(tabs)
	for page in ["Jobs","Areas","Build","Paths"]:
		button(tabs,page,func(): current_page=page; build_page())
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar.add_child(scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation",8)
	scroll.add_child(content)
	var footer := panel(root,16,-100,-16,-16,true,true)
	footer.anchor_top = 1
	var bottom := VBoxContainer.new()
	footer.add_child(bottom)
	help_label = label(bottom,"Select a villager or choose an area tool.",15)
	note = label(bottom,"Mark resources, then enable a villager’s matching profession.",12)
	label(bottom,"WASD pan · Q/E rotate · Wheel zoom · Right-drag pan · F4 return",12)
	root.visible = false
	colony.changed.connect(func(): if active: build_page())
	colony.message.connect(show_note)
	build_page()
func panel(parent: Control, left: float, top: float, right: float, bottom: float, right_anchor: bool, bottom_anchor: bool) -> PanelContainer:
	var node := PanelContainer.new()
	parent.add_child(node)
	if right_anchor: node.anchor_right = 1
	if bottom_anchor: node.anchor_bottom = 1
	node.offset_left = left
	node.offset_right = right
	node.offset_top = top
	node.offset_bottom = bottom
	var style := StyleBoxFlat.new()
	style.bg_color = Color("203d39")
	style.set_corner_radius_all(8)
	style.set_content_margin_all(12)
	style.border_color = Color("61756a")
	style.set_border_width_all(1)
	node.add_theme_stylebox_override("panel",style)
	return node
func label(parent: Node, text: String, size: int) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size",size)
	node.add_theme_color_override("font_color",Color("f1e5ca"))
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(node)
	return node
func button(parent: Node, text: String, action: Callable) -> Button:
	var node := Button.new()
	node.text = text
	node.custom_minimum_size.y = 34
	node.pressed.connect(action)
	node.focus_mode = Control.FOCUS_NONE
	parent.add_child(node)
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
	root.visible = active
	marker.visible = active
	resident_markers.visible = active
	entry.visible = not active
	if active:
		previous_camera = get_viewport().get_camera_3d()
		center = game.player.global_position
		camera.make_current()
		game.world.terrain.set_view_camera(camera)
		build_page()
		update_camera()
	else:
		camera.current = false
		if is_instance_valid(previous_camera):
			previous_camera.make_current()
			game.world.terrain.set_view_camera(previous_camera)
	active_changed.emit(active)
func resident(id: String) -> Resident:
	for person: Resident in game.life.residents:
		if person.id == id: return person
	return null
func set_tool(value: String) -> void:
	tool = value
	drawing = false
	stroke.clear()
	cursor_mesh.visible = false
	help_label.text = {"Select":"Select a villager. Jobs continue when you return to the road.","Road":"Drag a road around obstacles. Villagers prefer its connected route.","Path":"Drag a footpath. Villagers prefer paths over unmarked ground.","Erase":"Click an existing road or path to remove its stroke."}.get(value,"Click and drag over matching resources." if value.begins_with("zone:") else "Click clear ground to place a blueprint. Construction costs 10 timber.")
func build_page() -> void:
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	rows.clear()
	role_choice = null
	work_toggle = null
	detail = null
	if current_page=="Jobs":
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
		label(content,"Choose a resident near the work area. Colony routes cover up to 256 m per trip.",12)
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
	elif current_page=="Areas":
		label(content,"DESIGNATE RESOURCES",17)
		label(content,"Drag a circle over visible resources, then assign the matching profession in Jobs.",13)
		for pair in [["Forager","Gather berries"],["Woodcutter","Cut timber"],["Miner","Mine ore / stone"],["Farmer","Harvest olives"]]:
			button(content,pair[1],func(): set_tool("zone:"+pair[0]))
		for area in colony.areas:
			label(content,"%s · %d stands"%[area.role,colony.area_sources(area).size()],14)
			var row := HBoxContainer.new()
			content.add_child(row)
			button(row,"Disable" if area.enabled else "Enable",func(): colony.set_area_enabled(area.id,not area.enabled))
			button(row,"Remove",func(): colony.remove_area(area.id))
	elif current_page=="Build":
		label(content,"CORE WORKPLACES",17)
		label(content,"Place a blueprint. Builders carry 10 timber from the warehouse to finish it. Gather timber first.",13)
		for kind in ColonyCatalog.WORKPLACES:
			button(content,kind+" · 10 timber",func(): set_tool("build:"+kind))
		label(content,"Camps store gathered goods nearby. Transporters bring them to the warehouse. Farms grow renewable olives.",13)
		for site in colony.sites.values():
			label(content,site.blueprint+(" · Ready" if site.built else " · %d/10 timber"%site.inventory.get("wood",0)),13)
	else:
		label(content,"DRAW THE CONNECTIONS",17)
		label(content,"Drag local paths between resources and workplaces (256 m trips). Roads take priority; water and obstacles remain impassable.",13)
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
	button(content,"Select / cancel tool",func(): set_tool("Select"))
	refresh_readouts()
func show_note(text: String) -> void:
	if note: note.text = text
func update_camera() -> void:
	center.x = clampf(center.x,-12450,12450)
	center.z = clampf(center.z,-12450,12450)
	center.y = game.world.terrain.height_at(center.x,center.z)
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
	if active and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		set_active(false)
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
		elif event.button_index==MOUSE_BUTTON_WHEEL_DOWN and event.pressed: zoom=minf(1800,zoom*1.12)
		elif event.button_index==MOUSE_BUTTON_RIGHT:
			panning = event.pressed
		elif event.button_index==MOUSE_BUTTON_LEFT:
			var at: Variant = project_ground(event.position)
			if event.pressed and at!=null:
				anchor = at
				stroke = PackedVector3Array([at])
				drawing = true
				if tool=="Select":
					for worker: Resident in game.life.residents:
						if Vector2(worker.position.x-at.x,worker.position.z-at.z).length()<maxf(4.0,zoom*0.012): selected_id=worker.id; current_page="Jobs"; build_page(); break
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
		elif tool.begins_with("build:") and not drawing:
			var at: Variant = project_ground(event.position)
			if at!=null: preview(at)
		elif drawing:
			var at: Variant = project_ground(event.position)
			if at!=null and stroke[stroke.size()-1].distance_to(at)>2: stroke.append(at)
			if at!=null: preview(at)
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
func refresh_readouts() -> void:
	if stock_label==null: return
	stock_label.text = colony.stock_summary()
	pause_button.text = "Resume colony" if colony.paused else "Pause colony"
	for id in rows:
		var worker := resident(id)
		var assignment: Dictionary = colony.assignments[id]
		rows[id].text = ("› " if id==selected_id else "")+worker.name+" · "+assignment.role+("  [off]" if not assignment.enabled else "  [on]")
	if detail and resident(selected_id)!=null:
		var worker := resident(selected_id)
		detail.text = "%s · %s\nCargo: %s\n%s"%[worker.name,worker.status,colony.worker_cargo(selected_id),colony.statuses.get(selected_id,"Enable work after marking a matching area.")]
func _process(delta: float) -> void:
	if not _configured or not active: return
	var axis := Vector2(float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)),float(Input.is_physical_key_pressed(KEY_S))-float(Input.is_physical_key_pressed(KEY_W)))
	var forward := -camera.global_basis.z
	forward.y = 0
	center += (camera.global_basis.x*axis.x-forward.normalized()*axis.y)*delta*zoom*0.65
	if Input.is_physical_key_pressed(KEY_Q): yaw -= delta
	if Input.is_physical_key_pressed(KEY_E): yaw += delta
	update_camera()
	var marker_scale := clampf(zoom / 100.0, 1.0, 8.0)
	for index in game.life.residents.size():
		var person: Resident = game.life.residents[index]
		resident_markers.multimesh.set_instance_transform(index,Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*marker_scale),person.position+Vector3.UP*0.3))
		resident_markers.multimesh.set_instance_color(index,Color("f6ce75") if person.id==selected_id else Color("f1e5ca"))
	var selected := resident(selected_id)
	marker.visible = selected != null
	if selected != null: marker.position = selected.position+Vector3.UP*0.15
	clock += delta
	if clock>=0.25:
		clock = 0
		refresh_readouts()
func _exit_tree() -> void:
	if active: set_active(false)
	for node in [camera,cursor_mesh,marker,map_focus,resident_markers]:
		if is_instance_valid(node): node.queue_free()
