class_name CargoCart
extends CharacterBody3D
## The Cart: a two-wheeled load bed that the bike or the Jeep tows (Red Sea Baron's CargoCart).
## With a tow vehicle, the Cart and it are one **Rig**.
##
## Towing, as in the source: every tick the drawbar is solved from the *real* axle-to-hitch
## direction (not the smoothed visual yaw, which drags a jackknifed cart beside the tow vehicle),
## the body moves by velocity so it collides like anything else, its yaw only changes where the
## turned box is clear (VehicleClearance), its visual pitches and rolls to the ground under it
## (GroundPose), and the wheels roll by the signed distance travelled along the floor plane.
## The tow vehicle is tethered to the cart's axle (GroundDrive.tether_*): an over-stretched
## drawbar takes speed off the rig rather than stretching.
##
##   tow_vehicle            the Vehicle it is hitched to, or null (HitchSystem sets it)
##   inventory              its load (Inventory, kg)
##   total_mass()           the cart and its load: what slows the tow vehicle and burns fuel
##   place(pos, forward) / place_behind(vehicle)
##   recover()              back on the nearest road (or with its rig) after a fall or a swim
##   signals recovered, message(text)

signal recovered
signal message(text: String)

const DRAWBAR := 2.0            ## hitch to the cart's origin (m)
const SLACK := 1.1              ## how far the tow vehicle may get beyond the drawbar before it is held
const EMPTY_MASS := 60.0        ## kg, the cart itself
const CAPACITY := 240.0         ## kg of load
const MINIMUM_WORLD_Y := -64.0
const FALL_BELOW_GROUND := 12.0
const FREEZE_DISTANCE := 320.0  ## a detached cart further than this from the focus holds still

var inventory := Inventory.new(CAPACITY, "Cart")
var tow_vehicle: Vehicle
var terrain: Terrain
var entity_id: StringName = &"vehicle.cart"
var visual: CartVisual
var ground_pose := GroundPose.new()
var canopy_collision: CollisionShape3D
var travelled := 0.0
var enabled := true
var wheel_spin := 0.0           ## accumulated signed tyre rotation (rad), for tests
var focus: Node3D               ## the streaming focus: a detached cart far from it holds still
var _last_good := Vector3.ZERO
var _last_good_forward := Vector3.FORWARD
var _rest := 0


func _ready() -> void:
	add_to_group("navigation_obstacles")
	collision_layer = 2
	collision_mask = VehicleClearance.WORLD_AND_VEHICLES
	floor_snap_length = 1.1
	floor_max_angle = deg_to_rad(50)
	safe_margin = 0.02
	var collider := CollisionShape3D.new(); collider.name = "Chassis"
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.62, 1.1, 2.0)
	collider.shape = shape
	collider.position.y = 0.60
	add_child(collider)
	visual = CartVisual.new(); visual.name = "CartVisual"
	add_child(visual)
	canopy_collision = CollisionShape3D.new(); canopy_collision.name = "Canopy"
	var cover_shape := ConvexPolygonShape3D.new()
	cover_shape.points = CartCanopy.collision_points()
	canopy_collision.shape = cover_shape
	add_child(canopy_collision)
	inventory.changed.connect(_update_cargo)
	_update_cargo()
	_last_good = global_position


func wheels() -> Array[Node3D]:
	return visual.wheels


func total_mass() -> float:
	var parcel := 0.0
	var g := Game.current
	if g != null and g.gameplay != null and g.gm.parcel_in_cart: parcel = g.gm.carried_mass()
	return EMPTY_MASS + inventory.mass() + parcel


func _update_cargo() -> void:
	if visual and visual.load_view: visual.load_view.show_inventory(inventory)


func set_parcel_visible(v: bool) -> void:
	if visual: visual.set_parcel_visible(v)


func place(pos: Vector3, forward: Vector3) -> void:
	var f := Vector3(forward.x, 0, forward.z)
	if f.length_squared() < 0.001: f = Vector3.FORWARD
	f = f.normalized()
	global_position = pos + Vector3.UP * 0.12
	rotation = Vector3(0, atan2(-f.x, -f.z), 0)
	velocity = Vector3.ZERO
	if visual: visual.transform = Transform3D.IDENTITY
	if canopy_collision: canopy_collision.transform = Transform3D.IDENTITY
	_last_good = global_position
	_last_good_forward = f
	_rest = 0


## Straight behind a vehicle's hitch, on the ground there.
func place_behind(v: Vehicle) -> void:
	var fwd := v.flat_forward()
	var p := v.hitch_point() - fwd * DRAWBAR
	var y := p.y
	if terrain != null:
		var g := terrain.probe(p + Vector3.UP * 1.5)
		y = maxf(float(g.height), v.global_position.y - 1.5) if absf(float(g.height) - v.global_position.y) < 3.0 else v.global_position.y
	place(Vector3(p.x, y, p.z), fwd)


func _physics_process(delta: float) -> void:
	if not enabled: return
	if tow_vehicle == null and focus != null and is_instance_valid(focus) \
			and focus.global_position.distance_to(global_position) > FREEZE_DISTANCE:
		# The ground under a far, parked cart may not be collided any more: it holds still
		# (Red Sea Baron suspends distant home cargo the same way).
		velocity = Vector3.ZERO
		return
	if _fallen():
		recover()
		message.emit("The cart is back on the road. Its load is safe.")
		return
	# parked and settled: nothing moves it until something hitches it or pushes it
	if tow_vehicle == null and is_on_floor() and velocity.length_squared() < 0.0001 and get_slide_collision_count() == 0:
		_rest += 1
		if _rest > 30 and _rest % 30 != 0: return
	else:
		_rest = 0
	var from := global_position
	if tow_vehicle != null and is_instance_valid(tow_vehicle):
		var hitch := tow_vehicle.hitch_point()
		var offset := global_position - hitch
		offset.y = 0
		if offset.length() > 0.1:
			var proposed_yaw := lerp_angle(rotation.y, atan2(offset.x, offset.z), minf(1, delta * 8))
			VehicleClearance.apply_turn(self, proposed_yaw, collision_mask)
		# Solve the drawbar from the real axle-to-hitch direction. Using the smoothed visual yaw
		# here can drag a jackknifed cart beside the tow vehicle.
		var drawbar_direction := offset.normalized() if offset.length() > 0.1 else -tow_vehicle.flat_forward()
		var desired := hitch + drawbar_direction * DRAWBAR
		var pull := (desired - global_position) / delta
		velocity.x = clampf(pull.x, -35, 35)
		velocity.z = clampf(pull.z, -35, 35)
		# snagged (a bollard, a wall): the drawbar is stretched and the rig stops
		if offset.length() > DRAWBAR + 1.2:
			tow_vehicle.speed = move_toward(tow_vehicle.speed, 0, delta * 60)
	else:
		velocity.x = move_toward(velocity.x, 0, delta * 25)
		velocity.z = move_toward(velocity.z, 0, delta * 25)
	velocity.y -= delta * 24
	if is_on_floor() and velocity.y < -1.0: velocity.y = -1.0
	move_and_slide()
	ground_pose.sample(self)
	var previous_visual := visual.transform
	var blend := 1 - exp(-delta * 12)
	visual.rotation.x = lerpf(visual.rotation.x, ground_pose.pitch, blend)
	visual.rotation.z = lerpf(visual.rotation.z, ground_pose.roll, blend)
	visual.position.y = lerpf(visual.position.y, ground_pose.height, blend)
	_sync_canopy(previous_visual)
	var distance := from.distance_to(global_position)
	travelled += distance
	var displacement := global_position - from
	if is_on_floor() and Vector2(displacement.x, displacement.z).length_squared() > 0.00000001:
		var rolling_direction := (-global_basis.z).slide(get_floor_normal()).normalized()
		var rolled := displacement.dot(rolling_direction)
		wheel_spin -= rolled / CartVisual.WHEEL_RADIUS
		visual.animate_travel(rolled)
	if tow_vehicle != null and is_instance_valid(tow_vehicle):
		visual.aim_drawbar_local((global_transform * visual.transform).affine_inverse() * tow_vehicle.hitch_point())
	else:
		# unhitched: the drawbar rests on its eye on the ground ahead
		visual.aim_drawbar_local(Vector3(0, 0.1, -1.95))
	if is_on_floor() and not _in_deep_water():
		_last_good = global_position
		_last_good_forward = -global_basis.z


## Fell off the world, far under the ground, or into water too deep for its wheels.
func _fallen() -> bool:
	var p := global_position
	if p.y < MINIMUM_WORLD_Y: return true
	if terrain == null: return false
	if p.y < terrain.height_at(p.x, p.z) - FALL_BELOW_GROUND: return true
	return _in_deep_water()


func _in_deep_water() -> bool:
	return terrain != null and terrain.vehicle_submerged(global_position + Vector3.UP * 0.3)


func _sync_canopy(previous_visual: Transform3D) -> void:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = canopy_collision.shape
	query.transform = global_transform * visual.transform
	query.collision_mask = 1
	query.exclude = [get_rid()]
	if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
		visual.transform = previous_visual
	canopy_collision.transform = visual.transform


## Back on the road. A hitched cart goes with its rig: the tow vehicle recovers and the hitch
## puts the cart behind it (Red Sea Baron: "a coupled recovery belongs to the bike").
func recover() -> void:
	if tow_vehicle != null and is_instance_valid(tow_vehicle):
		tow_vehicle.reset_to_road(true)
		place_behind(tow_vehicle)
	elif terrain != null:
		var road := terrain.nearest_road(_last_good)
		var p: Vector3 = road.point
		place(Vector3(p.x, maxf(p.y, terrain.height_at(p.x, p.z)), p.z), road.tangent)
	else:
		place(_last_good, _last_good_forward)
	recovered.emit()


func save_state() -> Dictionary:
	return {"pos": global_position, "forward": -global_basis.z, "items": inventory.save_state(),
		"hitched": String(tow_vehicle.get_meta("entity_id", "")) if tow_vehicle else "", "travelled": travelled}


func load_state(d: Dictionary) -> void:
	# the hitch (HitchSystem) restores the coupling; the cart restores itself
	place(d.get("pos", global_position), d.get("forward", -global_basis.z))
	var items: Variant = d.get("items", {})
	if not (items is Dictionary and inventory.restore_contents(items)):
		inventory.clear()
	travelled = maxf(0.0, float(d.get("travelled", 0.0)))
