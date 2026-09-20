class_name JourneySystem
extends CanvasLayer
## Local courier counters: optional consignments, motorcycle fuel/workshop and home rest.
## Delivery owns earned coins and route state; this provider owns fuel and engine upgrades.
const HUB_RADIUS:=24.0
const SERVICE_BIKE_RADIUS:=35.0
const FULL_TANK_PRICE:=18
const ENGINE_PRICES: Array[int]=[120,240,360]
const OFFER_TYPES: Array[String]=["light","fragile","heavy"]
var game: Game
var fuel_ratio:=1.0
var engine_level:=0
var active_cargo_mass_kg:=0.0
var panel: Control
var _shade: ColorRect
var _opened_hub: StringName=&""
var _hubs: Array[StringName]=[]
## The modal protocol lives in Game.panels; this is a window onto it for existing callers.
var just_closed: bool:
	get: return game!=null and game.panels.just_closed()
var _odometer:=0.0
var _refresh:=0.0
var _title: Label
var _wallet: Label
var _subtitle: Label
var _service_note: Label
var _fuel_button: Button
var _reserve_button: Button
var _upgrade_button: Button
var _rest_button: Button
var _offer_buttons: Array[Button]=[]
var _offer_text: Array[RichTextLabel]=[]
var _theme: Theme
var _status: Label
var _feedback:=""

func setup(p_game: Game) -> void:
	game=p_game; layer=14
	for job in game.gm.jobs:
		if job.from_location not in _hubs: _hubs.append(job.from_location)
	_odometer=game.bike.odometer
	_build_ui(); _publish_bike_state()
	get_viewport().size_changed.connect(_layout)

func is_open() -> bool: return panel!=null and panel.visible

func nearby_hub() -> StringName:
	if game==null or game.rider==null: return &""
	var actor: Node3D=game.rider.courier()
	if actor==null: return &""
	var closest: StringName=&""; var distance:=HUB_RADIUS
	for id in _hubs:
		var offset:=actor.global_position-game.world.database.location_pos(id)
		var d:=Vector2(offset.x,offset.z).length()
		if d<distance and absf(offset.y)<3.0:
			distance=d; closest=id
	return closest

func _courier_stopped() -> bool:
	return game.rider.is_stopped()

func interaction_hint() -> String:
	var hub:=nearby_hub()
	if hub==&"" or is_open(): return ""
	return "B · %s courier counter" % game.world.database.location_name(hub) if _courier_stopped() else "Slow down for the courier counter · B"

func status_text() -> String:
	return "Fuel %d%% · Engine %d/3%s" % [roundi(fuel_ratio*100),engine_level," · Cargo %.0f kg" % active_cargo_mass_kg if active_cargo_mass_kg>0 else ""]

func open_counter() -> bool:
	if is_open(): return true
	if game.catalogue.is_open():
		Events.message.emit("Close the journal before visiting the courier counter.",2.5); return false
	var hub:=nearby_hub()
	if hub==&"":
		Events.message.emit("Find a village delivery stop to browse jobs and services. Press B beside the counter.",3.0); return false
	if not _courier_stopped():
		Events.message.emit("Stop on the ground to visit the courier counter.",2.5); return false
	_opened_hub=hub
	game.panels.open(self)
	panel.show(); _shade.show(); _feedback=""; _refresh_ui(); _layout()
	if not _offer_buttons[0].disabled: _offer_buttons[0].grab_focus()
	else: _fuel_button.grab_focus()
	return true

func close_counter() -> void:
	if not is_open(): return
	panel.hide(); _shade.hide()
	game.panels.close(self)

func _input(event: InputEvent) -> void:
	if game.mayor != null and game.mayor.active: return
	if event is InputEventJoypadButton and event.pressed and event.button_index==JOY_BUTTON_B and is_open():
		close_counter(); get_viewport().set_input_as_handled(); return
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode==KEY_B:
		if game.catalogue.is_open(): return # B remains usable as text inside the journal.
		if is_open(): close_counter()
		else: open_counter()
		get_viewport().set_input_as_handled()
	elif is_open() and event.keycode in [KEY_ESCAPE,KEY_N]:
		if event.keycode==KEY_ESCAPE: close_counter()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if game==null: return
	var distance:=maxf(0.0,game.bike.odometer-_odometer); _odometer=game.bike.odometer
	if game.rider.active_vehicle()==game.bike:
		# Distance, not frame rate or wall time: idling at a shop never drains a tank.
		var load_factor:=1.0+active_cargo_mass_kg/80.0
		fuel_ratio=maxf(0.0,fuel_ratio-distance/10000.0*load_factor)
	_publish_bike_state()
	_refresh+=delta
	if _refresh<.25: return
	_refresh=0.0
	if is_open():
		if nearby_hub()!=_opened_hub or not _courier_stopped():
			close_counter(); return
		_refresh_ui()

func _publish_bike_state() -> void:
	var job:=game.gm.current_job()
	active_cargo_mass_kg=clampf(job.cargo_mass_kg,0,80) if game.gm.carrying and job else 0.0
	var loaded_bike:=game.rider.active_vehicle()==game.bike
	game.bike.set_meta("cargo_mass_kg",active_cargo_mass_kg if loaded_bike else 0.0)
	game.bike.set_meta("engine_level",engine_level)
	game.bike.set_meta("fuel_ratio",fuel_ratio)

func offers_for(hub: StringName) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for index in range(game.gm.jobs.size()):
		var job: JobDefinition=game.gm.jobs[index]
		if job.from_location!=hub: continue
		for type in OFFER_TYPES:
			var mass: float={"light":6.0,"fragile":14.0,"heavy":55.0}[type]
			var rate: float={"light":1.0,"fragile":1.35,"heavy":1.7}[type]
			result.append({"kind":type,"job_index":index,"mass_kg":mass,"reward":roundi(job.reward*rate),"item":job.item,"destination":job.to_location})
		break
	return result

func accept_offer(kind: String) -> bool:
	var hub:=nearby_hub()
	if hub==&"" or not _courier_stopped() or game.gm.carrying: return _result(false,"Deliver the parcel you are carrying before taking another job.")
	for offer in offers_for(hub):
		if offer.kind!=kind: continue
		if not game.gm.select_board_offer(int(offer.job_index),offer): return _result(false,"This consignment is not available.")
		_publish_bike_state(); close_counter()
		Events.message.emit("%s consignment selected · %.0f kg · %d coins. Collect it at the marked stop. No deadline." % [kind.capitalize(),offer.mass_kg,offer.reward],4.0)
		return true
	return _result(false,"This consignment is not available.")

func _bike_at_counter() -> bool:
	var hub:=nearby_hub()
	return hub!=&"" and _courier_stopped() and game.bike.global_position.distance_to(game.world.database.location_pos(hub))<=SERVICE_BIKE_RADIUS and game.bike.grounded

func refill_price() -> int:
	return maxi(1,ceili((1.0-fuel_ratio)*FULL_TANK_PRICE)) if fuel_ratio<.999 else 0

func refuel() -> bool:
	if not _bike_at_counter(): return _result(false,"Bring your bike to the counter for fuel.")
	var price:=refill_price()
	if price==0: return _result(false,"Your tank is already full.")
	if not game.gm.spend_coins(price): return _result(false,"You need %d coins to fill the tank." % price)
	fuel_ratio=1.0; _publish_bike_state()
	return _result(true,"Tank filled · %d coins paid." % price)

func courier_reserve() -> bool:
	if not _bike_at_counter(): return _result(false,"Bring your bike to the counter for reserve fuel.")
	if fuel_ratio>=.20: return _result(false,"Reserve fuel is for tanks below 20%.")
	fuel_ratio=.20; _publish_bike_state()
	return _result(true,"The courier service supplied a 20% reserve. Safe travels.")

func upgrade_engine() -> bool:
	if not _bike_at_counter(): return _result(false,"Bring your bike to the workshop.")
	if engine_level>=3: return _result(false,"Your engine is fully upgraded.")
	var price:=ENGINE_PRICES[engine_level]
	if not game.gm.spend_coins(price): return _result(false,"You need %d coins for the next engine upgrade." % price)
	engine_level+=1; _publish_bike_state()
	return _result(true,"Engine upgraded to level %d · %d coins paid." % [engine_level,price])

func rest_until_morning() -> bool:
	if nearby_hub()!=&"villa_rosa_office" or not _courier_stopped(): return _result(false,"You can rest at your home in Villa Rosa.")
	# The counter asks the simulation to skip the night. It used to synthesise a whole save
	# payload here — and had to hand-copy three lifetime counters back into it, because any field
	# it left out of that payload was silently reset by load_state.
	var next_morning: float=(floorf(game.life.total_minutes/1440.0)+1.0)*1440.0+480.0
	game.life.advance_to(next_morning)
	return _result(true,"A fresh morning · %s. Your delivery has no deadline." % game.life.clock_text())

func _result(ok: bool, message: String) -> bool:
	_feedback=message
	if is_open(): _refresh_ui()
	else: Events.message.emit(message,3.0)
	return ok

func save_state() -> Dictionary:
	return {"version":1,"fuel_ratio":fuel_ratio,"engine_level":engine_level}

func load_state(data: Dictionary) -> void:
	fuel_ratio=clampf(float(data.get("fuel_ratio",1.0)),0,1)
	engine_level=clampi(int(data.get("engine_level",0)),0,3)
	_odometer=game.bike.odometer; _publish_bike_state()
	if is_open(): _refresh_ui()

func _build_ui() -> void:
	var font:=SystemFont.new(); font.font_names=PackedStringArray(["Georgia","Noto Serif","DejaVu Serif"])
	_theme=Theme.new(); _theme.default_font=font; _theme.default_font_size=19
	for type in ["Label","Button","RichTextLabel"]:
		_theme.set_color("font_color",type,Color("2e403d")); _theme.set_color("default_color",type,Color("2e403d"))
	_theme.set_stylebox("normal","Button",_style(Color("dfc694"),Color("ac9060")))
	_theme.set_stylebox("hover","Button",_style(Color("f5dfae"),Color("698b87")))
	_theme.set_stylebox("pressed","Button",_style(Color("aecac3"),Color("698b87")))
	_theme.set_stylebox("focus","Button",_style(Color(0,0,0,0),Color("416d75"),2))
	_theme.set_stylebox("disabled","Button",_style(Color("d3ccba"),Color("b2a88e")))
	_theme.set_color("font_disabled_color","Button",Color("837e6c"))
	_theme.set_color("font_focus_color","Button",Color("263d3b"))
	_theme.set_color("font_hover_color","Button",Color("263d3b")); _theme.set_color("font_pressed_color","Button",Color("263d3b"))
	_shade=ColorRect.new(); _shade.color=Color(.035,.06,.055,.78); _shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(_shade); _shade.hide()
	panel=Control.new(); panel.size=Vector2(1120,710); panel.theme=_theme; add_child(panel); panel.hide()
	var outer:=Panel.new(); outer.add_theme_stylebox_override("panel",_style(Color("e9dfc7"),Color("765e40"),4)); _place(outer,Rect2(12,16,1096,674))
	var banner:=Panel.new(); banner.add_theme_stylebox_override("panel",_style(Color("944735"),Color("b56f50"))); _place(banner,Rect2(32,35,1056,82))
	_title=_label("",Rect2(55,46,830,38),30,Color("fff0d2"))
	_subtitle=_label("LOCAL COURIER COUNTER",Rect2(58,87,830,24),14,Color("ebcf9e"))
	var close:=_button("Close · B / Esc",Rect2(891,57,178,40)); close.pressed.connect(close_counter)
	_label("Choose your next journey",Rect2(54,138,690,34),28)
	_wallet=_label("",Rect2(755,141,311,30),19); _wallet.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	_label("Unhurried deliveries. Pick a load, find your route, and take the day as it comes.",Rect2(55,177,1008,29),17,Color("6f725e"))
	for index in range(3):
		var x:=55.0+index*345.0
		var card:=Panel.new(); card.add_theme_stylebox_override("panel",_style(Color("f8efda"),Color("bdad8d"))); _place(card,Rect2(x,222,323,208))
		var stripe:=ColorRect.new(); stripe.color=[Color("87a99b"),Color("caad78"),Color("a97758")][index]; _place(stripe,Rect2(x+1,223,321,6)); stripe.mouse_filter=Control.MOUSE_FILTER_IGNORE
		var text:=RichTextLabel.new(); text.bbcode_enabled=true; text.scroll_active=false; _place(text,Rect2(x+17,242,289,124)); _offer_text.append(text)
		var take:=_button("Choose consignment",Rect2(x+16,377,291,36)); take.add_theme_font_size_override("font_size",17)
		take.pressed.connect(func(): accept_offer(OFFER_TYPES[index])); _offer_buttons.append(take)
	_label("Before you head out",Rect2(55,449,620,31),25)
	_service_note=_label("",Rect2(56,487,1005,25),16,Color("6f725e"))
	_fuel_button=_button("",Rect2(55,529,237,46)); _fuel_button.pressed.connect(refuel)
	_reserve_button=_button("Reserve fuel · Free",Rect2(309,529,237,46)); _reserve_button.pressed.connect(courier_reserve)
	_upgrade_button=_button("",Rect2(563,529,237,46)); _upgrade_button.pressed.connect(upgrade_engine)
	_rest_button=_button("Rest until 08:00",Rect2(817,529,248,46)); _rest_button.pressed.connect(rest_until_morning)
	for button in [_fuel_button,_reserve_button,_upgrade_button,_rest_button]: button.add_theme_font_size_override("font_size",16)
	_status=_label("",Rect2(57,600,1008,57),17); _status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	_label("J / Esc  Return to island     ·     F5  Save journey     ·     Engine upgrades improve your bike’s performance",Rect2(55,669,1010,26),13,Color("6d6654"))

func _refresh_ui() -> void:
	if _opened_hub==&"": return
	_title.text=game.world.database.location_name(_opened_hub)
	_subtitle.text="ISLAND COURIER SERVICE  /  "+game.life.clock_text().to_upper()
	_wallet.text="%d coins  ·  %d deliveries" % [game.gm.coins,game.gm.deliveries]
	var offers:=offers_for(_opened_hub)
	for i in range(_offer_buttons.size()):
		_offer_buttons[i].disabled=game.gm.carrying or i>=offers.size()
		if i>=offers.size(): _offer_text[i].text="No consignment available."; continue
		var offer: Dictionary=offers[i]
		var title: String={"light":"Light parcel","fragile":"Fragile parcel","heavy":"Heavy freight"}[offer.kind]
		_offer_text[i].text="[font_size=24]%s[/font_size]\n[color=#687461]%.0f kg  ·  %d coins[/color]\n\n%s\nTo %s" % [title,offer.mass_kg,offer.reward,offer.item,game.world.database.location_name(offer.destination)]
		_offer_buttons[i].text="Finish current delivery" if game.gm.carrying else "Choose this consignment"
	var bike_here:=_bike_at_counter()
	_fuel_button.text="Fill tank · %d coins" % refill_price() if refill_price()>0 else "Tank full"
	_fuel_button.disabled=not bike_here or refill_price()==0 or game.gm.coins<refill_price()
	_reserve_button.disabled=not bike_here or fuel_ratio>=.20
	_upgrade_button.text="Engine %d · %d coins" % [engine_level+1,ENGINE_PRICES[engine_level]] if engine_level<3 else "Engine fully upgraded"
	_upgrade_button.disabled=not bike_here or engine_level>=3 or game.gm.coins<ENGINE_PRICES[mini(engine_level,2)]
	_rest_button.disabled=_opened_hub!=&"villa_rosa_office"
	_rest_button.tooltip_text="Sleep at home in Villa Rosa until tomorrow morning. Parcels have no deadline."
	_reserve_button.tooltip_text="Free courier reserve brings a tank below 20% back to 20%."
	_service_note.text=status_text()+"  ·  "+("Your bike is ready for service." if bike_here else "Bring your bike within 35 m for fuel and upgrades.")
	_status.text=_feedback if not _feedback.is_empty() else ("Your parcel is safe. Complete the current delivery before choosing another." if game.gm.carrying else "Collect at the delivery marker. Fragile cargo loses value in crashes and hard landings; heavy loads need more runway. Reserve fuel is free below 20%.")

func _place(control: Control,rect: Rect2) -> void:
	panel.add_child(control); control.position=rect.position; control.size=rect.size

func _label(text: String,rect: Rect2,font_size: int,color: Color=Color("2e403d")) -> Label:
	var label:=Label.new(); label.text=text; label.add_theme_font_size_override("font_size",font_size); label.add_theme_color_override("font_color",color)
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE; _place(label,rect); return label

func _button(text: String,rect: Rect2) -> Button:
	var button:=Button.new(); button.text=text; _place(button,rect); return button

func _style(fill: Color,border: Color,width: int=1) -> StyleBoxFlat:
	var style:=StyleBoxFlat.new(); style.bg_color=fill; style.border_color=border; style.set_border_width_all(width); style.set_corner_radius_all(5); style.set_content_margin_all(8); return style

func _layout() -> void:
	var viewport:=get_viewport().get_visible_rect().size
	var zoom:=minf(1.15,minf(viewport.x/1140.0,viewport.y/740.0))
	panel.scale=Vector2.ONE*zoom; panel.position=(viewport-panel.size*zoom)*.5
