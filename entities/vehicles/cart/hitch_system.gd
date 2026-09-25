class_name HitchSystem
extends Node
## Hitching and unhitching the Cart (Red Sea Baron's HitchSystem), for the bike and the Jeep.
## The same rules as the source: the tow vehicle stopped and on its wheels (the bike's wings
## folded, the Jeep on land), the courier at the wheel or on foot within reach of the cart with
## a clear line to it, the cart backed up to — its drawbar eye within reach of the vehicle's
## hitch — on clear ground; unhitching only when the rig is stopped. A hitched cart follows its
## tow vehicle wherever that is put (a road recovery, a respawn, a save loaded).
##
## Also the save provider for the cart: where it stands, its load, what it is hitched to.
##
##   toggle() -> bool             H: hitch or unhitch, whichever applies
##   hitch(vehicle) -> String     "" or why not
##   unhitch() -> String          "" or why not
##   tow_vehicle() -> Vehicle     what the cart is hitched to (or null)
##   rig_of(vehicle) -> bool      is this vehicle towing the cart
##   signal message(text)

signal message(text: String)
signal changed(hitched: bool)

const REACH := 4.5            ## the courier on foot, from the cart
const EYE_REACH := 2.5        ## the cart's drawbar eye from the vehicle's hitch
const STOPPED := 1.0          ## m/s

var cart: CargoCart
var rider: Rider
var vehicles: Array[Vehicle] = []
var player: Player
var spawn_pos := Vector3.ZERO
var spawn_forward := Vector3.FORWARD


func setup(p_cart: CargoCart, p_rider: Rider, p_vehicles: Array[Vehicle], p_player: Player) -> void:
	cart = p_cart; rider = p_rider; vehicles = p_vehicles; player = p_player
	for v in vehicles:
		v.relocated.connect(_on_relocated.bind(v))
	cart.message.connect(func(t): message.emit(t))


func tow_vehicle() -> Vehicle:
	return cart.tow_vehicle if cart != null and is_instance_valid(cart.tow_vehicle) else null


func rig_of(v: Vehicle) -> bool:
	return v != null and tow_vehicle() == v


func _on_relocated(v: Vehicle) -> void:
	if tow_vehicle() == v: cart.place_behind(v)


## The courier's position: his body on foot, his vehicle when driving.
func _actor() -> Node3D:
	return rider.courier() if rider else player


func clear_access(from: Vector3, to: Vector3, extra: Array = []) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	# ignore the participants, keep whatever terrain or wall stands between them
	var ex: Array[RID] = [cart.get_rid()]
	if player: ex.append(player.get_rid())
	for v in vehicles: ex.append(v.get_rid())
	for e in extra: ex.append(e)
	query.exclude = ex
	return cart.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func toggle() -> bool:
	var why := unhitch() if tow_vehicle() != null else hitch(_candidate())
	if why != "":
		message.emit(why)
		return false
	return true


## The vehicle to hitch: the one being driven, or on foot the one whose hitch is nearest the cart.
func _candidate() -> Vehicle:
	var active := rider.active_vehicle() if rider else null
	if active != null: return active
	var best: Vehicle = null
	var best_d := INF
	for v in vehicles:
		var d := v.hitch_point().distance_to(_eye())
		if d < best_d: best_d = d; best = v
	return best


## The cart's drawbar eye where it rests: DRAWBAR ahead of the axle, along the cart's heading.
func _eye() -> Vector3:
	return cart.global_position - cart.global_basis.z * CargoCart.DRAWBAR


func hitch(v: Vehicle) -> String:
	if v == null: return "Back a vehicle up to the cart first."
	if tow_vehicle() != null: return "The cart is already hitched."
	var afloat: bool = v.get("afloat") == true
	var wings: bool = v.get("wings_out") == true
	if absf(v.speed) > STOPPED or not v.grounded or afloat or wings:
		return "Fold the wings, stop on the ground, then hitch." if wings else "Stop on the ground to use the hitch."
	var actor := _actor()
	if rider and rider.is_on_foot():
		if actor.global_position.distance_to(cart.global_position) > REACH:
			return "Walk up to the cart to use its hitch."
		if not clear_access(actor.global_position + Vector3.UP * 1.4, cart.global_position + Vector3.UP * 1.1):
			return "Approach the cart from a clear side."
	if v.hitch_point().distance_to(_eye()) > EYE_REACH or not cart.is_on_floor() \
			or not clear_access(v.global_position + Vector3.UP * 0.55, cart.global_position + Vector3.UP * 0.55):
		return "Back the %s up to the cart's drawbar on clear ground." % _name(v)
	_couple(v)
	message.emit("Cart hitched to the %s. H unhitches it when you stop; G opens the load." % _name(v))
	return ""


func unhitch() -> String:
	var v := tow_vehicle()
	if v == null: return "Nothing is hitched."
	if absf(v.speed) > STOPPED or not v.grounded:
		return "Stop the rig to unhitch the cart."
	var actor := _actor()
	if rider and rider.is_on_foot() and actor.global_position.distance_to(cart.global_position) > REACH \
			and actor.global_position.distance_to(v.global_position) > REACH:
		return "Walk up to the cart to unhitch it."
	_decouple()
	message.emit("Cart unhitched. Its load stays aboard.")
	return ""


func _couple(v: Vehicle) -> void:
	cart.tow_vehicle = v
	v.set_towing(cart)
	_tow_bar(v, true)
	changed.emit(true)


func _decouple() -> void:
	var v := tow_vehicle()
	cart.tow_vehicle = null
	cart.velocity = Vector3.ZERO
	if v != null:
		v.set_towing(null)
		_tow_bar(v, false)
	changed.emit(false)


## The bike has no tow bar of its own: a small bracket from its rear axle to the hitch.
func _tow_bar(v: Vehicle, on: bool) -> void:
	if not v is Bike: return
	var bar: Node3D = v.get_node_or_null("TowBar")
	if bar == null:
		bar = Node3D.new(); bar.name = "TowBar"; v.add_child(bar)
		var steel := Mats.solid(Color(0.18, 0.18, 0.19), 0.5, 0.6)
		var h: Vector3 = v.definition.hitch_offset
		bar.add_child(Mats.limb(Vector3(-0.12, 0.34, 0.72), h + Vector3(0, -0.03, -0.1), 0.025, steel))
		bar.add_child(Mats.limb(Vector3(0.12, 0.34, 0.72), h + Vector3(0, -0.03, -0.1), 0.025, steel))
		bar.add_child(Mats.sphere(0.045, Mats.solid(Color(0.7, 0.7, 0.72), 0.3, 0.8), h))
	bar.visible = on


# ---------------------------------------------------------------- persistence (key "cart")
func save_state() -> Dictionary:
	return cart.save_state()


func load_state(d: Dictionary) -> void:
	if tow_vehicle() != null: _decouple()
	cart.load_state(d)
	var to := String(d.get("hitched", ""))
	for v in vehicles:
		if String(v.get_meta("entity_id", "")) == to or (to == "vehicle.truck" and v is Jeep):
			_couple(v)
			cart.place_behind(v)


## A save from before the cart: it stands where a new game puts it, empty and unhitched.
func load_missing_state() -> void:
	if tow_vehicle() != null: _decouple()
	cart.inventory.clear()
	cart.place(spawn_pos, spawn_forward)


static func _name(v: Vehicle) -> String:
	return "bike" if v is Bike else ("jeep" if v is Jeep else "vehicle")
