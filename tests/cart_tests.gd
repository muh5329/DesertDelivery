extends Node
## The Cart and the Rig — Red Sea Baron's cart, towing, cart-wheel, cart-recovery, canopy and
## cargo-access verifiers ported into this game's in-game test style, plus this game's own:
## hitching to the bike and to the jeep (different hitches), towing on a straight, round tight
## bends forward and in reverse without the cart ever swinging through its tow vehicle, the
## over-stretched drawbar holding the tow vehicle, tyre spin by signed floor distance, detaching,
## recovery after a fall, the wings and the water refused while towing, the load (capacity and
## mass limits, the stacks shown on the bed), mass slowing the rig and burning fuel, a parcel
## delivered by cart, colony goods carried from one colony's warehouse to another's, a real road
## round a tight bend and over an outer highway bridge, and save / load mid-tow.
## Run: godot --headless --path . -- --test=cart_tests

var game: Game
var sc: Controls.Scripted
var cart: CargoCart
var hitch: HitchSystem
var fails := 0
var platform: StaticBody3D
const PAD := Vector3(300, 420, -300)


func _ready() -> void:
	game = Game.current
	sc = game.use_scripted_controls()
	game.encounters.ambush_enabled = false
	game.vitals.health.invulnerable = 1e9
	cart = game.cart
	hitch = game.hitch
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	print(("  PASS " if ok else "  FAIL ") + label)
	if not ok: fails += 1


func frames(n: int) -> void:
	for i in n: await get_tree().physics_frame


func _release() -> void:
	sc.intent = Controls.Intent.new()


func _stop(v: Vehicle) -> void:
	_release(); sc.intent.brake = 1.0
	for i in 200:
		await get_tree().physics_frame
		if absf(v.speed) < 0.05 and i > 20: break
	_release()
	await frames(5)


## Put the courier at the wheel of `v` (the Rider's own transitions).
func _drive(v: Vehicle) -> void:
	var r := game.rider
	if r.vehicle == v and r.is_riding(): return
	if r.is_riding(): r.request_dismount()
	await frames(3)
	r._set_vehicle(v)
	r._set_mode(Rider.Mode.RIDING if v == game.bike else Rider.Mode.DRIVING)
	await frames(3)


func _run() -> void:
	await frames(20)
	check(cart != null and game.entities.has_entity(&"vehicle.cart") and not hitch.tow_vehicle(), "the cart is an entity and starts unhitched")
	var d := cart.global_position.distance_to(game.jeep.global_position)
	check(d < 14.0 and cart.is_on_floor(), "it waits on the lane behind the jeep (%.1f m), on its wheels" % d)
	_make_pad()
	await _bike_rig()
	await _jeep_rig()
	await _recovery()
	await _loading()
	await _save_mid_tow()
	platform.queue_free()
	await _parcel_by_cart()
	await _colony_goods()
	await _tight_bend()
	await _highway_bridge()
	await _water_refused()
	print("CART TESTS: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)


func _make_pad() -> void:
	platform = StaticBody3D.new(); platform.name = "CartTestPad"; platform.collision_layer = 1; platform.collision_mask = 0
	var cs := CollisionShape3D.new(); var box := BoxShape3D.new(); box.size = Vector3(300, 2, 300)
	cs.shape = box; cs.position = Vector3(0, -1, 0); platform.add_child(cs)
	game.add_child(platform); platform.global_position = PAD


## Vehicle and cart on the pad, the cart backed up to it (its eye at the hitch).
func _rig_on_pad(v: Vehicle, at: Vector3, fwd := Vector3.FORWARD) -> void:
	if hitch.tow_vehicle(): hitch._decouple()
	var other: Vehicle = game.jeep if v == game.bike else game.bike
	other.place(PAD + Vector3(-140, 0.2, 140), Vector3.FORWARD)
	v.place(PAD + at + Vector3(0, 0.1, 0), fwd)
	cart.place_behind(v)
	game.world.set_focus(v)
	await _drive(v)
	await frames(30)


## Red Sea Baron's inset box: penetration, not touching, of the cart into the tow vehicle.
func _overlapping(v: Vehicle) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	var shape := BoxShape3D.new(); shape.size = Vector3(1.56, 1.04, 1.94)
	q.shape = shape
	q.transform = cart.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, 0.6, 0))
	q.collision_mask = 2
	q.exclude = [cart.get_rid()]
	for hit in cart.get_world_3d().direct_space_state.intersect_shape(q, 4):
		if hit.collider == v: return true
	return false


func _maneuver(v: Vehicle, throttle: float, brake: float, steer: float, count: int) -> Dictionary:
	_release()
	sc.intent.throttle = throttle; sc.intent.brake = brake; sc.intent.steer = steer
	var origin := v.global_position
	var overlaps := 0
	var gap := 0.0
	for i in roundi(count * Engine.physics_ticks_per_second / 60.0):   # counts are 60 Hz frames (Red Sea Baron's)
		await get_tree().physics_frame
		if _overlapping(v): overlaps += 1
		gap = maxf(gap, Vector2(v.global_position.x - cart.global_position.x, v.global_position.z - cart.global_position.z).length())
	_release()
	return {"travel": origin.distance_to(v.global_position), "overlaps": overlaps, "gap": gap}


func _behind(v: Vehicle) -> Vector3:
	return v.global_transform.affine_inverse() * cart.global_position


func _bike_rig() -> void:
	var bike := game.bike
	await _rig_on_pad(bike, Vector3(0, 0, 100))
	# refusals first: moving, wings out, too far
	bike.speed = 3.0
	check(hitch.hitch(bike) != "" and not hitch.tow_vehicle(), "no hitching while the bike rolls")
	await _stop(bike)
	bike.toggle_wings()
	check(hitch.hitch(bike) != "", "no hitching with the wings out")
	bike.toggle_wings()
	var eye := cart.global_position
	cart.place(eye + Vector3(0, 0, 6), bike.flat_forward())
	await frames(10)
	check(hitch.hitch(bike) != "", "no hitching a cart that is not backed up to")
	cart.place_behind(bike)
	await frames(20)
	sc.press("hitch")
	await frames(3)
	check(hitch.tow_vehicle() == bike and bike.is_towing() and bike.towed_mass() >= CargoCart.EMPTY_MASS, "H hitches the cart to the stopped bike")
	bike.toggle_wings()
	check(not bike.wings_out, "the wings stay folded while the bike tows the cart")
	# straight ahead: the cart trails on the drawbar, the tyres roll forward
	var spin0 := cart.wheel_spin
	var p0 := cart.global_position
	var r := await _maneuver(bike, 1.0, 0.0, 0.0, 180)
	var rel := _behind(bike)
	var rolled := p0.distance_to(cart.global_position)
	check(r.travel > 10.0 and rel.z > 2.6 and rel.z < 4.2 and absf(rel.x) < 0.5, "the cart trails straight behind the bike (%.2f m back, %.2f across)" % [rel.z, rel.x])
	check(cart.wheel_spin - spin0 < -3.0 and absf((cart.wheel_spin - spin0) + rolled / CartVisual.WHEEL_RADIUS) < 0.25 * rolled,
		"its tyres roll forward by the distance travelled (%.1f rad for %.1f m)" % [cart.wheel_spin - spin0, rolled])
	check(bike.speed < bike.definition.max_speed * 0.9, "the cart holds the bike below its solo top speed (%.1f m/s)" % bike.speed)
	await _stop(bike)
	# reverse: the tyres turn the other way
	spin0 = cart.wheel_spin
	sc.intent.brake = 1.0
	await frames(30)
	var rb := await _maneuver(bike, 0.0, 1.0, 0.0, 120)
	check(rb.travel > 1.0 and cart.wheel_spin - spin0 > 0.5, "reversing rolls its tyres backwards (%.2f rad)" % (cart.wheel_spin - spin0))
	await _stop(bike)
	# Red Sea Baron's loaded manoeuvres: forward turn, reverse turn, forward recovery
	cart.inventory.add("ore", 40)
	for spec in [[1.0, 0.0, -1.0, 240, "Forward turn"], [0.0, 1.0, 1.0, 240, "Reverse turn"], [1.0, 0.0, 1.0, 240, "Forward recovery"]]:
		var m := await _maneuver(bike, spec[0], spec[1], spec[2], spec[3])
		check(m.travel > 2.0, "%s makes progress (%.1f m)" % [spec[4], m.travel])
		check(m.overlaps == 0, "%s never swings the cart through the bike (%d frames)" % [spec[4], m.overlaps])
		check(m.gap < bike.definition.hitch_offset.length() + CargoCart.DRAWBAR + CargoCart.SLACK + 0.3, "%s keeps the drawbar (max %.2f m)" % [spec[4], m.gap])
		await _stop(bike)
	var straight := await _maneuver(bike, 1.0, 0.0, 0.0, 300)
	rel = _behind(bike)
	check(straight.travel > 8.0 and rel.z > 2.6 and absf(rel.x) < 0.6, "a straight run recovers the cart behind the bike after a tight reverse (%.2f, %.2f)" % [rel.z, rel.x])
	check(cart.inventory.count("ore") == 40, "the manoeuvres keep the load")
	await _stop(bike)
	# the load slows the rig
	cart.inventory.clear()
	await _stop(bike)
	var light := await _speed_after(bike, 150)
	cart.inventory.add("blocks", 70)
	await _stop(bike)
	var heavy := await _speed_after(bike, 150)
	check(heavy < light - 1.0, "210 kg aboard slows the bike (%.1f vs %.1f m/s)" % [heavy, light])
	check(game.journey._burn_per_m_for(bike, false) > 1.0 / bike.definition.tank_range_m * 1.5, "and burns its fuel faster")
	# the over-stretched drawbar holds the tow vehicle: a jammed cart stops the rig
	await _stop(bike)
	var before := bike.global_position
	cart.enabled = false          # the cart jammed: it does not move at all
	var m2 := await _maneuver(bike, 1.0, 0.0, 0.0, 90)
	cart.enabled = true
	check(m2.gap < bike.definition.hitch_offset.length() + CargoCart.DRAWBAR + CargoCart.SLACK + 0.2 and bike.global_position.distance_to(before) < 2.5,
		"a jammed cart holds the bike on the drawbar (%.2f m, moved %.2f m)" % [m2.gap, bike.global_position.distance_to(before)])
	await _stop(bike)
	cart.inventory.clear()
	# unhitch: not while moving, yes when stopped
	bike.speed = 4.0
	check(hitch.unhitch() != "" and hitch.tow_vehicle() == bike, "no unhitching on the move")
	await _stop(bike)
	sc.press("hitch")
	await frames(3)
	check(hitch.tow_vehicle() == null and not bike.is_towing() and bike.towed_mass() == 0.0, "H unhitches the stopped rig")
	var parked := cart.global_position
	var spin := cart.wheel_spin
	await frames(90)
	check(cart.global_position.distance_to(parked) < 0.05 and absf(cart.wheel_spin - spin) < 0.05, "a parked cart does not creep and its tyres stay still")


func _speed_after(v: Vehicle, n: int) -> float:
	_release(); sc.intent.throttle = 1.0
	await frames(roundi(n * Engine.physics_ticks_per_second / 60.0))
	var s := v.speed
	_release()
	return s


func _jeep_rig() -> void:
	var jeep := game.jeep
	await _rig_on_pad(jeep, Vector3(40, 0, 100))
	# on foot: the courier walks up to the cart and hitches the jeep backed up to it
	game.rider.request_dismount()
	await frames(5)
	game.player.place(cart.global_position + cart.global_basis.x * 1.6, Vector3.FORWARD)
	await frames(10)
	check(hitch.hitch(hitch._candidate()) == "" and hitch.tow_vehicle() == jeep, "on foot beside the cart, H hitches the jeep backed up to it")
	await _drive(jeep)
	var off := jeep.definition.hitch_offset.z
	var r := await _maneuver(jeep, 1.0, 0.0, 0.0, 180)
	var rel := _behind(jeep)
	check(r.travel > 10.0 and absf(rel.z - (off + CargoCart.DRAWBAR)) < 0.7 and absf(rel.x) < 0.5,
		"the jeep's hitch is further back than the bike's: the cart trails %.2f m behind it" % rel.z)
	# a sharp turn both ways, loaded: never through the jeep
	cart.inventory.add("planks", 60)
	for spec in [[1.0, 0.0, 1.0, 200, "Jeep forward turn"], [0.0, 1.0, -1.0, 200, "Jeep reverse turn"]]:
		await _stop(jeep)
		var m := await _maneuver(jeep, spec[0], spec[1], spec[2], spec[3])
		check(m.overlaps == 0 and m.travel > 2.0, "%s: no jackknife through the jeep (%d frames, %.1f m)" % [spec[4], m.overlaps, m.travel])
	await _stop(jeep)
	var sv := jeep._drive_mods()
	check(sv.top_speed < jeep.definition.max_speed, "the loaded cart trims the jeep's top speed (%.1f m/s)" % sv.top_speed)
	cart.inventory.clear()


func _recovery() -> void:
	var jeep := game.jeep
	# a detached cart fallen off the world comes back to the nearest road with its load
	if hitch.tow_vehicle(): hitch._decouple()
	cart.inventory.add("tools", 5)
	var road_near := game.world.road_spawn(game.bike.global_position, game.jeep.global_position)
	cart.place(road_near.pos + Vector3(0, 0.5, 0), road_near.forward)
	await frames(20)
	cart.focus = cart          # (the courier is far away on the test deck)
	cart.global_position = Vector3(cart.global_position.x, -70, cart.global_position.z)
	cart.velocity = Vector3(5, -15, 0)
	var recovered := [0]
	cart.recovered.connect(func(): recovered[0] += 1)
	await frames(6)
	var road: Dictionary = game.world.terrain.nearest_road(cart.global_position)
	check(recovered[0] >= 1 and cart.global_position.y > -10.0 and (road.point as Vector3).distance_to(cart.global_position) < 6.0,
		"a cart that falls off the world is recovered onto the nearest road")
	check(cart.inventory.count("tools") == 5 and hitch.tow_vehicle() == null, "recovery keeps its load and leaves it unhitched")
	await frames(40)
	check(cart.is_on_floor(), "and it stands on the ground there")
	cart.focus = game.rider.courier()
	# hitched: the whole rig recovers together
	await _rig_on_pad(jeep, Vector3(80, 0, 100))
	check(hitch.hitch(jeep) == "", "the jeep hitches the cart again")
	cart.global_position = Vector3(cart.global_position.x, -70, cart.global_position.z)
	await frames(6)
	await frames(30)
	var rel := _behind(jeep)
	check(hitch.tow_vehicle() == jeep and absf(rel.z - (jeep.definition.hitch_offset.z + CargoCart.DRAWBAR)) < 1.0 and absf(rel.x) < 0.6,
		"a hitched cart's fall recovers the whole rig to a road, the cart behind its jeep")
	check(cart.inventory.count("tools") == 5, "with the load aboard")
	cart.inventory.clear()


func _loading() -> void:
	var cargo := game.cargo
	var jeep := game.jeep
	await _rig_on_pad(jeep, Vector3(-60, 0, 100))
	if hitch.tow_vehicle() == null: hitch.hitch(jeep)
	# Inventory rules (Red Sea Baron's cart_verifier)
	cart.inventory.clear()
	check(cart.inventory.add("planks", 100) and cart.inventory.mass() == 200.0, "100 planks (200 kg) go into the cart")
	check(not cart.inventory.add("planks", 30) and cart.inventory.count("planks") == 100, "30 more would pass its 240 kg: refused, nothing changes")
	check(not cart.inventory.add("nonsense", 1) and not cart.inventory.add("planks", 0), "unknown items and empty amounts are refused")
	await frames(2)
	check(cart.visual.load_view.shown.get("planks", 0) >= 5, "the planks stand on the bed in stacks (%d)" % cart.visual.load_view.shown.get("planks", 0))
	cart.inventory.clear()
	cart.inventory.add("wine", 6); cart.inventory.add("grain", 20); cart.inventory.add("ammo_crate", 2)
	await frames(2)
	var shown: Dictionary = cart.visual.load_view.shown
	check(shown.has("barrel") and shown.has("sack") and shown.has("ammo"), "barrels, sacks and ammunition crates each look like themselves (%s)" % str(shown))
	# the courier's pack and the cart, on foot (the cargo access rules)
	game.rider.request_dismount()
	await frames(5)
	game.player.place(_beside_hitch(jeep), Vector3.FORWARD)
	await frames(90)
	var ids: Array = []
	for h in cargo.holds(): ids.append(h.id)
	check("pack" in ids and "cart" in ids and "bed" in ids, "beside the rig the pack, the jeep's bed and the cart are in reach (%s)" % str(ids))
	check(cargo.move("cart", "pack", "grain", 20) == "" and cargo.pack.count("grain") == 20 and cart.inventory.count("grain") == 0, "20 grain from the cart into the pack")
	check(cargo.move("cart", "pack", "wine", 6) == "" and cargo.pack.count("wine") == 6, "the wine too (26 kg in the pack)")
	check(cargo.move("cart", "pack", "ammo_crate", 1) != "" and cart.inventory.count("ammo_crate") == 2, "a 6 kg crate would overfill the 30 kg pack: refused, the cart keeps it")
	check(cargo.move("pack", "bed", "grain", 20) == "" and jeep.bed.count("grain") == 20, "from the pack onto the jeep's bed")
	# use: an ammunition crate refills the pouch, a fuel can fills a quarter tank
	game.gun.reserve_clips = 1
	check(cargo.use("cart", "ammo_crate") == "" and game.gun.reserve_clips == 1 + ItemDefinition.CLIPS_PER_CRATE and cart.inventory.count("ammo_crate") == 1, "an ammunition crate adds its clips to the pouch")
	cart.inventory.add("fuel_can", 1)
	game.rider._set_vehicle(jeep)
	game.journey.jeep_fuel = 0.3
	check(cargo.use("cart", "fuel_can") == "" and absf(game.journey.jeep_fuel - 0.55) < 0.01, "a fuel can pours a quarter tank into the jeep")
	# out of reach: walk away and the cart leaves the list
	game.player.place(cart.global_position + Vector3(12, 0, 0), Vector3.FORWARD)
	await frames(10)
	ids.clear()
	for h in cargo.holds(): ids.append(h.id)
	check(not "cart" in ids and cargo.move("pack", "cart", "wine", 1) != "", "12 m away the cart is out of reach")
	# the panel opens on the same holds
	game.player.place(_beside_hitch(jeep), Vector3.FORWARD)
	await frames(90)
	check(game.cargo_panel.open() and game.cargo_panel.is_open(), "G opens the load panel beside the cart")
	game.cargo_panel.source = 0; game.cargo_panel.line = 0
	for k in game.cargo_panel._holds.size():
		if game.cargo_panel._holds[k].id == "cart": game.cargo_panel.target = k
	game.cargo_panel._refresh(true)
	var item: String = game.cargo_panel.selected_item()
	var before := cart.inventory.count(item) if item != "" else -1
	game.cargo_panel.move_selected(1)
	check(item != "" and cart.inventory.count(item) == before + 1, "the panel moves one %s from the pack to the cart (Space)" % item)
	game.cargo_panel.close_panel()
	await frames(3)
	cargo.pack.clear(); jeep.bed.clear(); cart.inventory.clear()
	await _drive(jeep)


func _save_mid_tow() -> void:
	var bike := game.bike
	await _rig_on_pad(bike, Vector3(-100, 0, 100))
	hitch.hitch(bike)
	cart.inventory.add("cloth", 12); cart.inventory.add("tools", 4)
	var r := await _maneuver(bike, 1.0, 0.0, 0.3, 90)
	var at := bike.global_position
	check(Saves.save_game("cart_tests"), "saved mid-tow")
	hitch._decouple()
	cart.inventory.clear()
	cart.place(at + Vector3(30, 0, 0), Vector3.FORWARD)
	check(Saves.load_game("cart_tests"), "loaded")
	await frames(10)
	var rel := _behind(bike)
	check(hitch.tow_vehicle() == bike and bike.is_towing(), "the load puts the cart back on the bike's hitch")
	check(absf(rel.z - (bike.definition.hitch_offset.z + CargoCart.DRAWBAR)) < 0.6 and absf(rel.x) < 0.5, "behind it (%.2f, %.2f)" % [rel.z, rel.x])
	check(cart.inventory.count("cloth") == 12 and cart.inventory.count("tools") == 4, "with its load")
	await _stop(bike)
	hitch._decouple()
	cart.inventory.clear()


## Collect a heavy consignment with the cart hitched: it rides in the cart, and the cart in the
## drop-off ring delivers it.
func _parcel_by_cart() -> void:
	var gm := game.gm
	var bike := game.bike
	var coins := gm.coins
	var offer := {"kind": "heavy", "mass_kg": 55.0, "reward": 60}
	check(gm.select_board_offer(gm.job_index, offer), "a heavy consignment is taken at the counter")
	var from := gm.target_position()
	# hitch up on a road out of the ring, then pull into it
	var sp := game.world.road_spawn(from + Vector3(40, 0, 0), from)
	bike.place(sp.pos + Vector3(0, 0.2, 0), sp.forward)
	cart.place_behind(bike)
	game.world.set_focus(bike)
	game.world.streamer.load_all_pending()
	await _drive(bike)
	await frames(90)
	var why := hitch.hitch(bike)
	check(why == "", "the bike tows the cart to the pickup %s" % why)
	var fwd: Vector3 = from - (sp.pos as Vector3); fwd.y = 0
	bike.place(from + Vector3(0, 0.3, 0), fwd.normalized())
	await frames(240)
	check(gm.carrying and gm.parcel_in_cart, "the heavy parcel is loaded into the cart")
	check(cart.visual.load_view.parcel_visible(), "the parcel shows on the cart bed")
	check(cart.total_mass() >= CargoCart.EMPTY_MASS + 55.0, "its 55 kg count toward the cart's mass (%.0f kg)" % cart.total_mass())
	# the panel can take it out and put it back
	check(game.cargo.move_parcel("pack") == "" and not gm.parcel_in_cart, "the parcel can move to the courier's rack")
	check(game.cargo.move_parcel("cart") == "" and gm.parcel_in_cart, "and back into the cart")
	var to := gm.target_position()
	var t_fwd := (to - from); t_fwd.y = 0
	bike.place(to + t_fwd.normalized() * 3.0 + Vector3(0, 0.3, 0), t_fwd.normalized())
	game.world.set_focus(bike)
	game.world.streamer.load_all_pending()
	await frames(90)
	check(gm.deliveries >= 1 and gm.coins > coins and not gm.carrying, "the cart in the drop-off ring hands the parcel over (+%d coins)" % (gm.coins - coins))
	await _stop(bike)
	hitch._decouple()


func _colony_goods() -> void:
	var econ := game.colony.economy
	var core: ColonyTown = econ.town("core")
	econ.earn(1000)
	var cid := ""
	for c in ["campo_real", "puerto_alto", "sarmada", "isola_serena", "valdoro"]:
		if econ.town(c) != null and (econ.town(c).founded or econ.found(c, true) == ""):
			cid = c; break
	check(cid != "", "a second colony is chartered (%s)" % cid)
	if cid == "": return
	var other: ColonyTown = econ.town(cid)
	var jeep := game.jeep
	# at the villa's warehouse
	var sp := game.world.road_spawn(core.hall + Vector3(12, 0, 0), core.hall)
	jeep.place(sp.pos, sp.forward)
	cart.place_behind(jeep)
	game.world.set_focus(jeep)
	game.world.streamer.load_all_pending()
	await _drive(jeep)
	await frames(30)
	hitch.hitch(jeep)
	core.add("planks", 30)
	var core_before := core.count("planks")
	var store := game.cargo.nearest_store(jeep.global_position)
	check(store.get("kind", "") == "store" and store.town == core, "the villa's colony warehouse is in reach of the rig (%s)" % store.get("title", "-"))
	check(game.cargo.move("store", "cart", "planks", 25) == "" and cart.inventory.count("planks") == 25 and core.count("planks") == core_before - 25,
		"25 planks leave the villa's stock for the cart")
	# to the other colony's hall
	var hall := other.hall
	var sp2 := game.world.road_spawn(hall + Vector3(10, 0, 0), hall)
	jeep.place(sp2.pos, sp2.forward)
	game.world.set_focus(jeep)
	game.world.outer.refresh_collision()
	game.world.streamer.load_all_pending()
	await frames(40)
	var store2 := game.cargo.nearest_store(jeep.global_position)
	if store2.get("town") != other:
		# the hall stands off the road: walk the rig up to it
		jeep.place(hall + (sp2.pos - hall).normalized() * 9.0 + Vector3.UP * 0.5, (hall - sp2.pos).normalized())
		await frames(40)
		store2 = game.cargo.nearest_store(jeep.global_position)
	check(store2.get("town") == other, "%s's colony hall is in reach at the other end" % other.display_name)
	var other_before := other.count("planks")
	check(game.cargo.move("cart", "store", "planks", 25) == "" and other.count("planks") == other_before + 25 and cart.inventory.count("planks") == 0,
		"the planks go into %s's stock: land trade by cart" % other.display_name)
	await _stop(jeep)
	hitch._decouple()


## Pure pursuit along road samples (the Autopilot's steering); per-frame overlap and gap checks.
func _follow(v: Vehicle, pts: PackedVector3Array, cap: float, seconds: float) -> Dictionary:
	var pi := 1
	var overlaps := 0
	var gap := 0.0
	var cart_off := 0.0
	var falls := [0]
	var cb := func(): falls[0] += 1
	cart.recovered.connect(cb)
	var t := 0.0
	while t < seconds:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		var pos := v.global_position
		while pi < pts.size() - 1 and Vector2(pts[pi].x - pos.x, pts[pi].z - pos.z).length() < 7.0: pi += 1
		if pi >= pts.size() - 2: break
		var to := pts[pi] - pos; to.y = 0
		sc.intent.steer = clampf(-v.flat_forward().signed_angle_to(to.normalized(), Vector3.UP) * 1.8, -1.0, 1.0)
		sc.intent.throttle = 1.0 if v.speed < cap else 0.0
		sc.intent.brake = 0.5 if v.speed > cap + 2.0 else 0.0
		if _overlapping(v): overlaps += 1
		gap = maxf(gap, Vector2(pos.x - cart.global_position.x, pos.z - cart.global_position.z).length())
		if cart.is_on_floor():
			var g: float = game.world.terrain.probe(cart.global_position + Vector3.UP * 1.5).height
			cart_off = maxf(cart_off, absf(cart.global_position.y - g))
	cart.recovered.disconnect(cb)
	_release()
	return {"done": pi >= pts.size() - 3, "overlaps": overlaps, "gap": gap, "falls": falls[0], "cart_off": cart_off, "at": pi, "of": pts.size()}


## The tightest bend on the network's roads and tracks: the biggest change of heading within 18 m
## either side of a point (a hairpin or a junction corner), on a gentle grade.
func _tight_bend() -> void:
	var t: Terrain = game.world.terrain
	var best: Dictionary = {}
	for r in range(t.road_samples.size()):
		var P: PackedVector3Array = t.road_samples[r]
		if P.size() < 40: continue
		# arc-length index: the sample ~18 m before and after each point
		var cum := PackedFloat32Array(); cum.resize(P.size()); cum[0] = 0.0
		for k in range(1, P.size()): cum[k] = cum[k - 1] + Vector2(P[k].x - P[k - 1].x, P[k].z - P[k - 1].z).length()
		var lo := 0; var hi := 0
		for k in range(P.size()):
			while lo < k and cum[k] - cum[lo] > 18.0: lo += 1
			while hi < P.size() - 1 and cum[hi] - cum[k] < 18.0: hi += 1
			if cum[k] < 40.0 or cum[P.size() - 1] - cum[k] < 50.0: continue
			var a := P[k] - P[lo]; a.y = 0
			var b := P[hi] - P[k]; b.y = 0
			if a.length() < 12.0 or b.length() < 12.0: continue
			var turn := absf(a.signed_angle_to(b, Vector3.UP))
			var climb := absf(P[hi].y - P[lo].y)
			if climb < 5.0 and turn > deg_to_rad(55.0) and (best.is_empty() or turn > best.turn):
				best = {"r": r, "k": k, "turn": turn, "cum": cum}
	check(not best.is_empty(), "a tight bend on the roads to tow round")
	if best.is_empty(): return
	var P: PackedVector3Array = t.road_samples[best.r]
	var cumb: PackedFloat32Array = best.cum
	var k0: int = best.k; var k1: int = best.k
	while k0 > 0 and cumb[best.k] - cumb[k0] < 40.0: k0 -= 1
	while k1 < P.size() - 1 and cumb[k1] - cumb[best.k] < 45.0: k1 += 1
	var path := P.slice(k0, k1 + 1)
	print("    bend: road %d sample %d, %.0f degrees at %s" % [best.r, best.k, rad_to_deg(best.turn), P[best.k]])
	var bike := game.bike
	var fwd := path[4] - path[0]; fwd.y = 0
	bike.place(path[0] + Vector3.UP * 0.3, fwd.normalized())
	cart.place_behind(bike)
	game.world.set_focus(bike)
	if game.world.outer: game.world.outer.refresh_collision()
	game.world.streamer.load_all_pending()
	await _drive(bike)
	await frames(40)
	check(hitch.hitch(bike) == "", "hitched on the road before the bend")
	cart.inventory.add("wood", 30)
	var run := await _follow(bike, path, 7.0, 40.0)
	check(run.done and run.overlaps == 0 and run.falls == 0, "the bike tows the loaded cart round a %.0f degree bend: through it, never through the bike, never off the road (%d/%d, %d overlaps)" % [rad_to_deg(best.turn), run.at, run.of, run.overlaps])
	check(run.cart_off < 0.6, "the cart's wheels stay on the road surface (worst %.2f m)" % run.cart_off)
	await _stop(bike)
	hitch._decouple()
	cart.inventory.clear()


## Over an outer highway bridge with the jeep: up the ramp, along the deck, down the far side.
func _highway_bridge() -> void:
	var outer: OuterWorld = game.world.outer
	check(outer != null and outer.ok, "the outer world is loaded")
	if outer == null or not outer.ok: return
	var path := PackedVector3Array()
	var name := ""
	for e in outer.roads.roads:
		if String(e.get("cls", "")) != "highway" or e.get("seam", false) or e.bridges.is_empty(): continue
		var P: PackedVector3Array = e.pts
		var span: Array = e.bridges[0]
		var a := maxi(int(span[0]) - 30, 0); var b := mini(int(span[1]) + 20, P.size() - 1)
		if b - a < 20: continue
		path = P.slice(a, b + 1); name = "%s [%d..%d]" % [e.id, span[0], span[1]]
		break
	check(path.size() > 10, "an outer highway bridge (%s)" % name)
	if path.size() <= 10: return
	var jeep := game.jeep
	var fwd := path[3] - path[0]; fwd.y = 0
	jeep.place(path[0] + Vector3.UP * 0.4, fwd.normalized())
	cart.place_behind(jeep)
	game.world.set_focus(jeep)
	outer.refresh_collision()
	game.world.streamer.load_all_pending()
	await _drive(jeep)
	await frames(40)
	check(hitch.hitch(jeep) == "", "the jeep hitches the cart at the bridge approach")
	cart.inventory.add("blocks", 40)
	var lowest_deck := INF
	for q in path: lowest_deck = minf(lowest_deck, q.y)
	var run := await _follow(jeep, path, 14.0, 60.0)
	check(run.done and run.falls == 0 and run.overlaps == 0, "the loaded rig crosses %s: up the ramp, over the deck, down the far side (%d/%d)" % [name, run.at, run.of])
	check(run.cart_off < 0.7, "the cart follows the deck's profile, wheels on it (worst %.2f m)" % run.cart_off)
	await _stop(jeep)
	hitch._decouple()
	cart.inventory.clear()


## A cart cannot float: the jeep towing one stays a land vehicle, and deep water is a splash.
func _water_refused() -> void:
	var t: Terrain = game.world.terrain
	var jeep := game.jeep
	var spot := Vector3.ZERO
	for a in range(0, 360, 6):
		var dir := Vector3(cos(deg_to_rad(a)), 0, sin(deg_to_rad(a)))
		for r in range(300, 760, 4):
			var p := dir * float(r)
			if t.height_at(p.x, p.z) < -3.0:
				spot = p; break
		if spot != Vector3.ZERO: break
	check(spot != Vector3.ZERO, "deep water off the island")
	jeep.place(Vector3(spot.x, 0.2, spot.z), Vector3.FORWARD)
	cart.place_behind(jeep)
	hitch._couple(jeep)
	var splashed := [false]
	jeep.fell_in_sea.connect(func(): splashed[0] = true, CONNECT_ONE_SHOT)
	await _drive(jeep)
	for i in 120:
		await get_tree().physics_frame
		if splashed[0]: break
	await frames(10)
	check(splashed[0] and not jeep.afloat, "towing a cart, the jeep does not float: deep water is a splash")
	var road: Dictionary = t.nearest_road(jeep.global_position)
	var rel := _behind(jeep)
	check((road.point as Vector3).distance_to(jeep.global_position) < 3.0 and hitch.tow_vehicle() == jeep and rel.z > 3.0,
		"the rig comes back to the nearest road together")
	hitch._decouple()


## On the pad beside a vehicle's hitch, between it and its cart, feet on the deck.
func _beside_hitch(v: Vehicle) -> Vector3:
	var p := v.hitch_point() + v.global_transform.basis.x.normalized() * 1.6
	return Vector3(p.x, v.global_position.y + 0.05, p.z)
