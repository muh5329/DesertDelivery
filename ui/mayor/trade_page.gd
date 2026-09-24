class_name MayorTradePage
extends RefCounted
## The Mayor view's Trade page: ports, the fleet (build at a shipyard, assign to a lane), the
## lanes (cargo rules, raid risk and the coves behind it, trips, the log) and the new-lane editor
## ("load up to 40 grain at Puerto Alto, unload at Isola Serena; return with 30 fish").

const T = preload("res://ui/mayor/mayor_theme.gd")

var view: MayorView
var from_id := ""
var to_id := ""
var out_rule: Dictionary = {}
var back_rule: Dictionary = {}
var pick_out := "grain"
var pick_back := "fish"
var amount_out := 40
var amount_back := 30


func _init(p_view: MayorView) -> void:
	view = p_view


func econ() -> ColonyEconomy:
	return view.colony.economy


func build(parent: VBoxContainer) -> void:
	var e := econ()
	var sh := e.shipping
	T.heading(parent, "Shipping lanes")
	if not e.ports_ready:
		T.label(parent, "Charting the sea lanes (the water grid is being built)...", 13, T.MUTED)
		T.button(parent, "Refresh", func(): e.ensure_shipping(); view.build_page())
		return
	# ports
	var ports := T.label(parent, "", 13, T.MUTED)
	var parts := PackedStringArray()
	for cid in sh.ports:
		var t := e.town(cid)
		parts.append("%s%s" % [t.display_name.get_slice(" (", 0), "" if t.founded else " (no charter)"])
	ports.text = "Ports: " + ", ".join(parts)
	T.rule(parent)
	# the fleet
	T.heading(parent, "Fleet")
	if sh.ships.is_empty(): T.label(parent, "No ships yet. Build a shipyard at a port colony, then lay down a ship.", 13, T.MUTED)
	for s in sh.ships:
		var box := VBoxContainer.new(); parent.add_child(box)
		T.label(box, "%s · %s" % [s.name, EconomyCatalog.SHIPS[s.type].name], 14)
		T.label(box, _ship_status(s), 12, T.MUTED)
		var pick := OptionButton.new(); pick.focus_mode = Control.FOCUS_NONE
		pick.add_theme_font_size_override("font_size", 13)
		pick.add_item("Idle in port")
		var sel := 0
		for i in range(sh.lanes.size()):
			pick.add_item("Lane: " + sh.lane_title(sh.lanes[i]))
			if sh.lanes[i].id == s.lane: sel = i + 1
		pick.select(sel)
		var sid: String = s.id
		var sname: String = s.name
		pick.item_selected.connect(func(idx: int):
			sh.assign(sid, "" if idx == 0 else String(sh.lanes[idx - 1].id))
			view.show_note("%s assigned." % sname)
			view.build_page())
		box.add_child(pick)
	# the shipyard of the selected colony
	var here := e.town(view.colony_id)
	var yard_row := T.row(parent)
	for type in ["coaster", "schooner"]:
		var def: Dictionary = EconomyCatalog.SHIPS[type]
		var why := e.can_build_ship(view.colony_id, type)
		var b := T.button(yard_row, "Build %s" % def.name.to_lower(), func():
			var err := e.build_ship(view.colony_id, type)
			view.show_note(err if err != "" else "The %s is on the stocks at %s." % [def.name.to_lower(), here.display_name])
			view.build_page(), 12)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.disabled = why != ""
		b.tooltip_text = "%s: %d units, %.0f m/s. Costs %s.%s" % [def.name, int(def.capacity), float(def.speed), EconomyCatalog.describe_cost(def.cost, int(def.coins)), ("\n" + why) if why != "" else ""]
	T.rule(parent)
	# lanes
	T.heading(parent, "Lanes")
	if sh.lanes.is_empty(): T.label(parent, "No lanes. Create one below.", 13, T.MUTED)
	for i in range(sh.lanes.size()):
		var l: Dictionary = sh.lanes[i]
		var head := T.row(parent)
		var swatch := ColorRect.new(); swatch.color = ColonyViews.LANE_COLORS[i % ColonyViews.LANE_COLORS.size()]
		swatch.custom_minimum_size = Vector2(12, 12); swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(swatch)
		T.label(head, sh.lane_title(l), 14).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		T.label(parent, "Out: %s\nBack: %s" % [_rule_text(l.out, l.from), _rule_text(l.back, l.to)], 12)
		var risk := sh.lane_risk(l)
		var threats := sh.lane_threats(l)
		var rl := T.label(parent, ("Raid risk %d%% per leg - pirate cove%s nearby (clear %s to make it safe)" % [int(risk * 100), "s" if threats.size() > 1 else "", "them" if threats.size() > 1 else "it"]) if risk > 0.0 else "Safe waters", 12, T.BAD if risk > 0.0 else T.GOOD)
		rl.tooltip_text = ", ".join(threats)
		var r := sh.route(l.from, l.to)
		T.label(parent, "%.1f km · %d trips · %d ship%s" % [float(r.get("length", 0.0)) / 1000.0, int(l.trips), l.ships.size(), "" if l.ships.size() == 1 else "s"], 12, T.MUTED)
		for line in l.log.slice(maxi(0, l.log.size() - 3)):
			T.label(parent, "· " + String(line), 11, T.MUTED)
		var actions := T.row(parent)
		var lid: String = l.id
		T.button(actions, "Show on map", func(): view.focus_route(lid), 12).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		T.button(actions, "Remove", func():
			sh.remove_lane(lid); view.show_note("Lane removed."); view.build_page(), 12)
		T.rule(parent)
	_editor(parent)


func _editor(parent: VBoxContainer) -> void:
	var e := econ()
	var sh := e.shipping
	T.heading(parent, "New lane")
	var ports: Array = []
	for cid in sh.ports:
		if e.town(cid).founded: ports.append(cid)
	if ports.size() < 2:
		T.label(parent, "Two chartered port colonies are needed (the core harbour, Puerto Alto, Sarmada, Isola Serena).", 12, T.MUTED)
		return
	if not from_id in ports: from_id = ports[0]
	if not to_id in ports or to_id == from_id: to_id = ports[1] if ports[0] == from_id else ports[0]
	var pick_row := T.row(parent)
	var f := _port_picker(ports, from_id, func(cid): from_id = cid; view.build_page())
	var t := _port_picker(ports, to_id, func(cid): to_id = cid; view.build_page())
	pick_row.add_child(f); T.label(pick_row, "to", 13, T.MUTED).autowrap_mode = TextServer.AUTOWRAP_OFF; pick_row.add_child(t)
	f.size_flags_horizontal = Control.SIZE_EXPAND_FILL; t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rule_editor(parent, "Load at %s" % e.town(from_id).display_name.get_slice(" (", 0), out_rule, true)
	_rule_editor(parent, "Return from %s with" % e.town(to_id).display_name.get_slice(" (", 0), back_rule, false)
	var create := T.button(parent, "Create lane", func():
		var l := e.add_lane(from_id, to_id, out_rule, back_rule)
		if l.is_empty(): view.show_note("No sea route between those ports.")
		else:
			view.show_note("Lane %s created. Assign a ship in the fleet list." % sh.lane_title(l))
			out_rule = {}; back_rule = {}
		view.build_page())
	create.disabled = from_id == to_id or (out_rule.is_empty() and back_rule.is_empty())
	create.tooltip_text = "Needs at least one cargo rule."


func _port_picker(ports: Array, current: String, on_pick: Callable) -> OptionButton:
	var o := OptionButton.new(); o.focus_mode = Control.FOCUS_NONE
	o.add_theme_font_size_override("font_size", 13)
	for i in range(ports.size()):
		o.add_item(econ().town(ports[i]).display_name.get_slice(" (", 0))
		if ports[i] == current: o.select(i)
	o.item_selected.connect(func(i: int): on_pick.call(ports[i]))
	return o


func _rule_editor(parent: VBoxContainer, caption: String, rule: Dictionary, outbound: bool) -> void:
	T.label(parent, caption + ":", 13)
	for item in rule:
		var r := T.row(parent)
		T.label(r, "  up to %d %s" % [int(rule[item]), EconomyCatalog.item_name(item).to_lower()], 13).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		T.button(r, "x", func(): rule.erase(item); view.build_page(), 12)
	var r := T.row(parent)
	var items := OptionButton.new(); items.focus_mode = Control.FOCUS_NONE
	items.add_theme_font_size_override("font_size", 12)
	var keys := EconomyCatalog.ITEMS.keys()
	var current := pick_out if outbound else pick_back
	for i in range(keys.size()):
		items.add_item(EconomyCatalog.item_name(keys[i]))
		if keys[i] == current: items.select(i)
	items.item_selected.connect(func(i: int):
		if outbound: pick_out = keys[i]
		else: pick_back = keys[i])
	items.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(items)
	var spin := SpinBox.new(); spin.min_value = 1; spin.max_value = 90; spin.step = 5
	spin.value = amount_out if outbound else amount_back
	spin.value_changed.connect(func(v: float):
		if outbound: amount_out = int(v)
		else: amount_back = int(v))
	spin.custom_minimum_size.x = 70
	r.add_child(spin)
	T.button(r, "Add", func():
		if outbound: rule[pick_out] = amount_out
		else: rule[pick_back] = amount_back
		view.build_page(), 12)


func _rule_text(rule: Dictionary, at: String) -> String:
	if rule.is_empty(): return "nothing (sail empty)"
	var parts := PackedStringArray()
	for item in rule: parts.append("%d %s" % [int(rule[item]), EconomyCatalog.item_name(item).to_lower()])
	return "up to " + ", ".join(parts) + " from " + econ().town(at).display_name.get_slice(" (", 0)


func _ship_status(s: Dictionary) -> String:
	var sh := econ().shipping
	var cargo := PackedStringArray()
	for item in s.cargo: cargo.append("%d %s" % [int(s.cargo[item]), EconomyCatalog.item_name(item).to_lower()])
	var load := ("carrying " + ", ".join(cargo)) if not cargo.is_empty() else "empty"
	match String(s.state):
		"building": return "On the stocks at %s (%d s)" % [econ().town(s.home).display_name.get_slice(" (", 0), int(s.timer)]
		"docked":
			var here := econ().town(s.port).display_name.get_slice(" (", 0)
			return ("Loading at %s · %s" % [here, load]) if s.lane != "" else ("Idle at %s · %s" % [here, load])
		_:
			var r := sh.current_route(s)
			var l := sh.lane(s.lane)
			var dest: String = (l.to if int(s.leg) == 0 else l.from) if not l.is_empty() else s.port
			if int(s.leg) == 2: dest = s.get("reposition", [s.port, s.port])[1]
			return "Sailing to %s (%d%%) · %s" % [econ().town(dest).display_name.get_slice(" (", 0), int(float(s.s) / maxf(float(r.get("length", 1.0)), 1.0) * 100.0), load]
