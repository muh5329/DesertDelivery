class_name CargoSystem
extends Node
## Equipment and goods on the move: the courier's pack, the Jeep's bed, the Cart, and the
## stores he can load from — his colonies' halls and warehouses (their stock, free: they are
## his) and the road stations' and courier counters' shops (fuel cans and ammunition crates for
## coins). Everything is an Inventory move (Red Sea Baron's Stock and Transaction): a move that
## costs coins stages the payment, tries the move and undoes the payment if the move is refused.
##
## "Where things are" is a list of **holds** in reach of the courier, each a Dictionary:
##   {id, title, kind: pack|bed|cart|store|shop, inv: Inventory (not for a store), town: ColonyTown}
## The CargoPanel draws them; tests call the same functions.
##
##   holds() -> Array                    what is in reach right now (the pack first)
##   move(from_id, to_id, item, n) -> String   "" or why not (n is clamped to what fits)
##   move_all(from_id, to_id) -> int
##   use(hold_id, item) -> String        a fuel can fills a quarter tank, an ammo crate adds clips
##   parcel_hold() -> String             where the courier's parcel is: "pack" (on the courier or his
##                                       vehicle's rack) or "cart"; move_parcel(to_id)
##   can_open() -> String                "" or why the load panel cannot open here
##   save_state / load_state             the pack (the bed and the cart save with their owners)

const PACK_CAPACITY := 30.0
const STORE_REACH := 16.0
const VEHICLE_REACH := 4.0

var game: Game
var pack := Inventory.new(PACK_CAPACITY, "Courier's pack")
var hitch: HitchSystem
var last_message := ""


func setup(p_game: Game, p_hitch: HitchSystem) -> void:
	game = p_game
	hitch = p_hitch


func _courier() -> Node3D:
	return game.rider.courier()


func cart() -> CargoCart:
	return hitch.cart if hitch else null


## Stopped on the ground: the only time loads change hands.
func can_open() -> String:
	if game.rider.mode == Rider.Mode.SWIMMING: return "Not while swimming."
	if not game.rider.is_stopped(1.2): return "Stop first to move your load."
	return ""


func holds() -> Array:
	var out: Array = [{"id": "pack", "title": "Courier's pack", "kind": "pack", "inv": pack}]
	var c := _courier()
	if c == null: return out
	var here := c.global_position
	var active := game.rider.active_vehicle()
	var jeep: Jeep = game.jeep
	if jeep != null and (active == jeep or (active == null and (here.distance_to(jeep.global_position) < VEHICLE_REACH or here.distance_to(jeep.bed_point()) < VEHICLE_REACH))):
		if not jeep.afloat:
			out.append({"id": "bed", "title": "Jeep bed", "kind": "bed", "inv": jeep.bed})
	var ct := cart()
	if ct != null and _cart_in_reach(ct, active):
		out.append({"id": "cart", "title": "Cart", "kind": "cart", "inv": ct.inventory})
	var store := nearest_store(here)
	if not store.is_empty(): out.append(store)
	return out


## Red Sea Baron's can_access_cart: in reach, on the ground, stopped, with a clear line to it —
## or at the wheel of the vehicle towing it.
func _cart_in_reach(ct: CargoCart, active: Vehicle) -> bool:
	if active != null:
		return active.is_towing() and active.towing == ct
	var actor := _courier()
	return actor.global_position.distance_to(ct.global_position) <= hitch.REACH + 0.5 \
		and hitch.clear_access(actor.global_position + Vector3.UP * 1.4, ct.global_position + Vector3.UP * 1.1)


## A founded colony's hall or warehouse within reach, or a station's / counter's shop.
func nearest_store(at: Vector3) -> Dictionary:
	if game.colony != null and game.colony.economy != null:
		var best: Dictionary = {}
		var best_d := STORE_REACH
		for cid in game.colony.economy.towns:
			var t: ColonyTown = game.colony.economy.towns[cid]
			if not t.founded: continue
			for b in t.buildings:
				if not b.built or EconomyCatalog.building(b.type).get("cat", "") != "storage": continue
				var p := t.position_of(b)
				var d := Vector2(p.x - at.x, p.z - at.z).length()
				if d < best_d and absf(p.y - at.y) < 8.0:
					best_d = d
					best = {"id": "store", "title": "%s · %s" % [t.display_name, EconomyCatalog.building(b.type).get("name", "Warehouse")], "kind": "store", "town": t, "colony": cid}
		if not best.is_empty(): return best
	if game.journey != null:
		var st: Dictionary = game.journey.nearby_station()
		if not st.is_empty(): return {"id": "shop", "title": "%s shop" % st.name, "kind": "shop", "station": st.id}
		var hub: StringName = game.journey.nearby_hub()
		if hub != &"": return {"id": "shop", "title": "%s counter" % game.world.database.location_name(hub), "kind": "shop", "station": "counter.%s" % hub}
	return {}


## A line for the HUD when something can be hitched or loaded here ("" otherwise). Cheap: it
## runs every frame, so it only measures distances.
func hint() -> String:
	var ct := cart()
	var c := _courier()
	if ct == null or c == null: return ""
	var active := game.rider.active_vehicle()
	var here := c.global_position
	if active != null:
		if active.is_towing(): return ""
		if active.hitch_point().distance_to(ct.global_position - ct.global_basis.z * CargoCart.DRAWBAR) < 6.0:
			return "H · hitch the cart (back up to its drawbar, stopped)"
	elif here.distance_to(ct.global_position) < hitch.REACH:
		return "G · load the cart   ·   H · hitch it (a vehicle backed up to it)" if not hitch.tow_vehicle() else "G · load the cart   ·   H · unhitch it"
	var store := nearest_store(here)
	if store.get("kind", "") == "store": return "G · load / unload at %s" % String(store.title)
	return ""


func hold(id: String) -> Dictionary:
	for h in holds():
		if h.id == id: return h
	return {}


## What a hold has: item -> count. A shop always has its equipment.
func contents(h: Dictionary) -> Dictionary:
	match String(h.get("kind", "")):
		"store":
			var t: ColonyTown = h.town
			var out := {}
			for item in t.stock:
				if int(t.stock[item]) > 0 and ItemDefinition.get_item(String(item)) != null: out[String(item)] = int(t.stock[item])
			return out
		"shop":
			var out := {}
			for id in ItemDefinition.SHOP_STOCK: out[id] = 99
			return out
	return (h.inv as Inventory).contents() if h.has("inv") else {}


func _room(h: Dictionary, item: String) -> int:
	match String(h.get("kind", "")):
		"store":
			if not EconomyCatalog.ITEMS.has(item): return 0
			return (h.town as ColonyTown).room_for(item)
		"shop":
			return 999 if item in ItemDefinition.SHOP_STOCK else 0
	return (h.inv as Inventory).room_for(item)


func _say(text: String) -> void:
	last_message = text


## Move up to `n` of `item` from one hold to another. Returns "" or why nothing moved.
func move(from_id: String, to_id: String, item: String, n: int = 1) -> String:
	if from_id == to_id: return "Pick somewhere else to put it."
	var why := can_open()
	if why != "": return why
	var from := hold(from_id)
	var to := hold(to_id)
	if from.is_empty() or to.is_empty(): return "That is out of reach."
	var def := ItemDefinition.get_item(item)
	if def == null: return "Unknown item."
	var have := int(contents(from).get(item, 0))
	if have <= 0: return "There is no %s there." % def.title.to_lower()
	var room := _room(to, item)
	if room <= 0:
		if to.kind == "store" and not EconomyCatalog.ITEMS.has(item): return "The warehouse only keeps colony goods."
		if to.kind == "shop": return "The shop only takes back its own fuel cans and ammunition."
		return "No room for %s in the %s (%.0f kg)." % [def.title.to_lower(), String(to.title).to_lower(), def.mass]
	var count := mini(mini(n, have), room)
	var ok := false
	match [String(from.kind) == "shop", String(to.kind) == "shop", String(from.kind) == "store", String(to.kind) == "store"]:
		[true, false, false, false]:
			ok = _buy(to, item, count)
			if not ok: return "%d %s cost %d coins." % [count, def.title.to_lower(), count * def.value]
		[false, true, false, false]:
			ok = _sell(from, item, count)
		[false, false, true, false]:
			ok = _from_store(from, to, item, count)
		[false, false, false, true]:
			ok = _to_store(from, to, item, count)
		[false, false, false, false]:
			ok = (from.inv as Inventory).transfer_to(to.inv, item, count)
		_:
			return "Take it through your pack or a vehicle."
	if not ok: return "It would not fit."
	_say("%d %s → %s" % [count, def.title.to_lower(), String(to.title).to_lower()])
	return ""


func _buy(to: Dictionary, item: String, n: int) -> bool:
	var price := ItemDefinition.get_item(item).value * n
	if game.gm.coins < price: return false
	return Inventory.commit(func(): return (to.inv as Inventory).add(item, n),
		func(): game.gm.coins -= price, func(): game.gm.coins += price) and _wallet()


func _sell(from: Dictionary, item: String, n: int) -> bool:
	var refund := int(ItemDefinition.get_item(item).value * n / 2)
	return Inventory.commit(func(): return (from.inv as Inventory).remove(item, n),
		func(): game.gm.coins += refund, func(): game.gm.coins -= refund) and _wallet()


func _wallet() -> bool:
	game.gm.wallet_changed.emit(game.gm.coins)
	return true


## Out of a colony's stock: the stock only drops by what the hold accepted.
func _from_store(from: Dictionary, to: Dictionary, item: String, n: int) -> bool:
	var t: ColonyTown = from.town
	var taken := t.take(item, n)
	if taken <= 0: return false
	if (to.inv as Inventory).add(item, taken): _colony_changed(); return true
	t.add(item, taken)
	return false


func _to_store(from: Dictionary, to: Dictionary, item: String, n: int) -> bool:
	var t: ColonyTown = to.town
	if not (from.inv as Inventory).remove(item, n): return false
	var put := t.add(item, n)
	if put < n: (from.inv as Inventory).add(item, n - put)
	if put > 0:
		_colony_changed()
		var econ = game.colony.economy
		econ._notify(String(to.colony), "The courier brought %d %s to %s." % [put, ItemDefinition.get_item(item).title.to_lower(), t.display_name], false)
	return put > 0


func _colony_changed() -> void:
	if game.colony and game.colony.economy: game.colony.economy.changed.emit()


func move_all(from_id: String, to_id: String) -> int:
	var from := hold(from_id)
	if from.is_empty(): return 0
	var moved := 0
	for item: String in contents(from):
		if from.kind == "shop": break
		var n := int(contents(from).get(item, 0))
		if move(from_id, to_id, item, n) == "": moved += 1
	return moved


## Use one: a fuel can pours a quarter tank into the vehicle being driven (or the nearest one),
## an ammunition crate refills the Garand's pouch.
func use(hold_id: String, item: String) -> String:
	var h := hold(hold_id)
	if h.is_empty() or not h.has("inv"): return "Take it out of the store first."
	var def := ItemDefinition.get_item(item)
	if def == null or (h.inv as Inventory).count(item) <= 0: return "There is none here."
	match def.use:
		"fuel":
			var v := _fuel_target()
			if v == null: return "Stand by the bike or the jeep to pour the fuel in."
			var tank: float = game.journey.tank_of(v)
			if tank > 1.0 - ItemDefinition.CAN_TANK_SHARE * 0.5: return "The %s's tank is nearly full." % HitchSystem._name(v)
			var ok := Inventory.commit(func(): return (h.inv as Inventory).remove(item, 1),
				func(): game.journey.set_tank(v, tank + ItemDefinition.CAN_TANK_SHARE), func(): game.journey.set_tank(v, tank))
			if not ok: return "The can is stuck."
			_say("A can of fuel into the %s: %d%%." % [HitchSystem._name(v), roundi(game.journey.tank_of(v) * 100)])
			return ""
		"ammo":
			var gun := game.gun
			if gun.reserve_clips >= GunSystem.MAX_RESERVE: return "Your pouch is full of clips."
			var before := gun.reserve_clips
			var ok := Inventory.commit(func(): return (h.inv as Inventory).remove(item, 1),
				func(): gun.reserve_clips = mini(GunSystem.MAX_RESERVE, before + ItemDefinition.CLIPS_PER_CRATE), func(): gun.reserve_clips = before)
			if not ok: return "The crate is stuck."
			_say("Clips from the crate: %d in the pouch." % gun.reserve_clips)
			return ""
	return "%s is for colonies and customers, not for you." % def.title


func _fuel_target() -> Vehicle:
	var active := game.rider.active_vehicle()
	if active != null: return active
	var here := _courier().global_position
	var best: Vehicle = null
	var best_d := VEHICLE_REACH + 1.0
	for v: Vehicle in [game.bike, game.jeep]:
		var d := here.distance_to(v.global_position)
		if d < best_d: best_d = d; best = v
	return best


# ---------------------------------------------------------------- the courier's parcel
## Where the parcel rides: "pack" (the courier or his vehicle's rack) or "cart".
func parcel_hold() -> String:
	return "cart" if game.gm.parcel_in_cart else "pack"


func move_parcel(to_id: String) -> String:
	if not game.gm.carrying: return "You are not carrying a parcel."
	var why := can_open()
	if why != "": return why
	if to_id == parcel_hold(): return ""
	if to_id == "cart":
		if hold("cart").is_empty(): return "The cart is out of reach."
		game.gm.set_parcel_in_cart(true)
	elif to_id == "pack" or to_id == "bed":
		if game.gm.parcel_in_cart and hold("cart").is_empty(): return "The cart is out of reach."
		game.gm.set_parcel_in_cart(false)
	else:
		return "The parcel goes to its customer, not into a store."
	_say("The parcel is in the %s." % ("cart" if game.gm.parcel_in_cart else "pack"))
	return ""


func save_state() -> Dictionary:
	return {"version": 1, "pack": pack.save_state()}


func load_state(d: Dictionary) -> void:
	var items: Variant = d.get("pack", {})
	if not (items is Dictionary and pack.restore_contents(items)): pack.clear()


func load_missing_state() -> void:
	pack.clear()
