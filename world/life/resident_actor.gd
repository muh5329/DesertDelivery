class_name ResidentActor
extends CharacterBody3D
## A nearby view of a resident record. Identity and schedule live in IslandLife.
var person: RiderModel
var car: Node3D
var label: Label3D
var prop: Node3D
var _activity := ""
var _was_driving := false
var _body_shape: CollisionShape3D
var _wheel_roll := 0.0
var _visual_elapsed := 0.0
## Imported animation pivots are stable for this actor's lifetime.
var _wheels: Array[Node3D] = []
var _steering: Array[Node3D] = []

## FULL tier: worth drawing the name tag and the small activity flourishes.
var detailed := true

func setup(record: Resident) -> void:
	collision_layer=16; collision_mask=1|2|4|16
	floor_snap_length=.65; floor_max_angle=deg_to_rad(48); safe_margin=.015
	_body_shape=CollisionShape3D.new(); add_child(_body_shape)
	_set_collision(record.driving)
	# Each islander is their own person (CharacterLook), built on the shared animated rig.
	person = RiderModel.new()
	person.look = CharacterLook.for_resident(record)
	person.async_build = true
	add_child(person)
	person.enable_resident_lod()
	car = IslandArt.instantiate("island_car"); add_child(car); car.visible = false
	for node_name in ["WheelFL", "WheelFR", "WheelRL", "WheelRR"]:
		var wheel := car.find_child(node_name, true, false) as Node3D
		if wheel: _wheels.append(wheel)
	for node_name in ["SteeringFL", "SteeringFR"]:
		var steering := car.find_child(node_name, true, false) as Node3D
		if steering: _steering.append(steering)
	for mi in car.find_children("*", "MeshInstance3D", true, false):
		for i in range(mi.mesh.get_surface_count()):
			var src: Material = mi.get_surface_override_material(i)
			if src==null: src=mi.mesh.surface_get_material(i)
			if src is StandardMaterial3D and src.resource_name == "Car seafoam":
				var mat: StandardMaterial3D = src.duplicate(); mat.albedo_color = Color(record.car_color)
				mi.set_surface_override_material(i,mat)
	label = Label3D.new(); label.position.y = 2.15; label.font_size = 22
	label.pixel_size = .005
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; label.width=320; label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(.98,.93,.79); label.outline_size = 5
	label.visibility_range_end = 7.0
	add_child(label)
	prop = Node3D.new(); person.hand_r.add_child(prop)

func update_view(record: Resident, delta: float, nearby: bool) -> void:
	var camera := get_viewport().get_camera_3d()
	var distance := camera.global_position.distance_to(global_position) if camera else 0.0
	person.set_resident_lod_distance(distance)
	_visual_elapsed += delta
	var interval := 1.0 / (20.0 if person.resident_lod_active else 60.0)
	# State changes must update body size/visibility immediately. Only cosmetic
	# animation is throttled; IslandLife still moves this body's collision at120Hz.
	if _visual_elapsed < interval and record.driving == _was_driving and record.activity == _activity: return
	var visual_delta := _visual_elapsed
	_visual_elapsed = 0.0
	_update_visual_pose(record, visual_delta, nearby)
	person.sync_resident_pose()

func _update_visual_pose(record: Resident, delta: float, nearby: bool) -> void:
	var driving: bool = record.driving
	car.visible = driving
	person.visible = record.activity != "sleep"
	label.visible = nearby and detailed and person.visible and not driving
	label.text = record.name
	if driving != _was_driving:
		_set_collision(driving)
		if not driving:
			person.root.position=Vector3(0,RiderModel.HIP_H,0)
			person.root.rotation=Vector3.ZERO
		_was_driving=driving
	if driving:
		var normal: Vector3=record.surface_normal
		var local_normal:=global_basis.inverse()*normal
		car.rotation.x=lerpf(car.rotation.x,atan2(local_normal.z,local_normal.y),minf(1,delta*10))
		car.rotation.z=lerpf(car.rotation.z,-atan2(local_normal.x,local_normal.y),minf(1,delta*10))
		_wheel_roll-=float(record.speed)*delta/.34
		for wheel in _wheels:
			wheel.rotation.x=_wheel_roll
		var steer:=0.0
		if record.moving and int(record.cursor)<record.route.size():
			var toward: Vector3=record.route[int(record.cursor)]-record.position
			steer=clampf(wrapf(atan2(-toward.x,-toward.z)-rotation.y,-PI,PI),-.5,.5)
		for steering in _steering:
			steering.rotation.y=steer
		person.rotation=car.rotation
		person.pose_riding(false, false)
		person.position = Vector3(-.31,-.067,.065)
		person.scale = Vector3.ONE * .77
		person.root.position = Vector3(0,1.10,.25)
	else:
		person.rotation=Vector3.ZERO
		person.position = Vector3.ZERO
		person.scale = Vector3.ONE * person.body_scale
		for limb in [person.leg_l,person.leg_r,person.arm_l,person.arm_r]:
			limb.scale = Vector3.ONE; limb.rotation.z = 0; limb.rotation.y = 0
		person.root.position.z = 0
		person.head.rotation.y=lerpf(person.head.rotation.y,0,minf(1,delta*8))
		person.animate("walk" if record.moving and float(record.speed)>.05 else "idle",float(record.speed),delta)
		if not record.moving:
			var t := Time.get_ticks_msec()*.001
			match String(record.activity):
				"garden", "repair", "bake", "fish", "build":
					person.arm_r.rotation.x = .55 + sin(t*2)*.24
					person.arm_l.rotation.x = .35
					person.torso.rotation.x = -.14
				"social", "sell", "teach":
					person.arm_r.rotation.x = .25+maxf(0,sin(t))* .6
					person.head.rotation.y = sin(t*.7)*.16
	if _activity != record.activity:
		_activity = record.activity
		_build_prop(_activity)
	prop.visible = not record.moving and not driving

func _build_prop(activity: String) -> void:
	for child in prop.get_children(): child.queue_free()
	var wood := Mats.solid(Color(.34,.20,.10),.85)
	var metal := Mats.solid(Color(.40,.44,.43),.4,.6)
	match activity:
		"garden", "build":
			prop.add_child(Mats.cylinder(.016,.85,wood,Vector3(0,.23,0)))
			prop.add_child(Mats.box(Vector3(.20,.05,.10),metal,Vector3(0,-.19,0)))
		"repair":
			prop.add_child(Mats.box(Vector3(.055,.25,.025),metal,Vector3(0,-.06,0)))
		"fish":
			prop.add_child(Mats.cylinder(.009,1.8,wood,Vector3(0,.65,0)))
		"deliver", "sell", "bake":
			prop.add_child(Mats.box(Vector3(.23,.19,.20),wood,Vector3(0,-.10,-.06)))
		"teach", "read":
			prop.add_child(Mats.box(Vector3(.15,.035,.20),Mats.solid(Color(.68,.30,.17)),Vector3(0,-.04,-.08)))

## The ViewPool decides whether this actor exists at all; the EntityManager decides how much of
## it to run once it does. Below FULL the label and the fine animation are not worth the frame.
func set_simulation_tier(tier: int) -> void:
	detailed = tier == EntityManager.SimulationTier.FULL

func _set_collision(driving: bool) -> void:
	if driving:
		var shape:=BoxShape3D.new(); shape.size=Vector3(1.5,1.1,3.0)
		_body_shape.shape=shape; _body_shape.position.y=.83
	else:
		var shape:=CapsuleShape3D.new(); shape.radius=.27; shape.height=1.65
		_body_shape.shape=shape; _body_shape.position.y=.84

func move_supported(destination: Vector3, delta: float) -> Vector3:
	if delta<=0: return destination
	# The persistent record supplies a ground-conforming desired displacement;
	# CharacterBody resolves nearby walls, vehicles and people without clipping.
	velocity=(destination-global_position)/delta
	velocity.y-=1.5
	move_and_slide()
	var result:=global_position
	# Support sampling provides wheel/feet contact on slopes independently of
	# the deliberately raised chassis collider, whose bottom isn't a tire.
	if Vector2(result.x-destination.x,result.z-destination.z).length()<.05:
		result.y=destination.y
	global_position=result
	return result
