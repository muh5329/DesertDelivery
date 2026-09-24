class_name IslandLife
extends Node3D
## Persistent seven-day simulation. Records keep running with no scene representation;
## models are created only near the player. Calendar, journeys and routines are saved.
signal calendar_changed
const DAYS := ["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"]
const WEEK_MINUTES := 10080.0
var total_minutes := 570.0
var minutes_per_second := .5 # 48 real minutes per island day.
var residents: Array[Resident] = []
# Colony jobs share these residents and their rendered actors.
var colony_owned: Dictionary = {}
var by_id: Dictionary = {}
## id -> ResidentActor, owned by the pool. Kept as `actors` because that is what everything
## from the catalogue to the tests calls it.
var actors: Dictionary:
	get: return _views.views
var _views: ViewPool
var world: WorldManager
var entities: EntityManager
var navigation := RoadNavigation.new()
var ambient: IslandWildlife
## The outer towns' people, the traffic on the outer roads and the fishing boats (OuterLife).
var outer: OuterLife
var _accumulator := 0.0
var _last_minute := -1
const NEIGHBOR_CELL := 24.0
var _prefetch_frame := 0
var _neighbors: Dictionary = {}

func _rebuild_neighbors() -> void:
	_neighbors.clear()
	for r in residents:
		if r.activity == "sleep": continue
		var cell := Vector2i(floori(r.position.x / NEIGHBOR_CELL), floori(r.position.z / NEIGHBOR_CELL))
		if not _neighbors.has(cell): _neighbors[cell] = []
		_neighbors[cell].append(r)

func _nearby_residents(p: Vector3, reach: float) -> Array:
	# Tests and tools may move records directly between simulation ticks.
	if not is_physics_processing() or _neighbors.is_empty(): return residents
	var found: Array = []
	var cell := Vector2i(floori(p.x / NEIGHBOR_CELL), floori(p.z / NEIGHBOR_CELL))
	var radius := maxi(1, ceili((reach + 4.0) / NEIGHBOR_CELL))
	for x in range(-radius, radius + 1):
		for z in range(-radius, radius + 1):
			found.append_array(_neighbors.get(cell + Vector2i(x,z), []))
	return found

func setup(p_world: WorldManager, p_entities: EntityManager) -> void:
	world=p_world; entities=p_entities
	_views=ViewPool.new(entities,&"resident",func(r: Resident) -> Node3D:
		var actor:=ResidentActor.new(); actor.name=String(r.id).replace(".","_")
		return actor)
	_views.configure=func(r: Resident,node: Node3D) -> void:
		node.setup(r); node.position=r.position
	_views.spawn_radius=world.config.resident_view_radius
	_views.keep_margin=world.config.view_keep_margin
	# Somebody asleep at home has no body in the world, however close you stand to the cottage.
	_views.awake_for=func(r: Resident) -> bool: return r.activity!="sleep"
	navigation.build(world.terrain)
	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/life/residents.json"))
	for source in parsed.residents:
		var r := Resident.from_source(source)
		var origin: Vector3 = world.database.location_pos(StringName(r.location))
		var road := world.terrain.nearest_road(origin)
		var along: Vector3 = road.tangent; along.y=0; along=along.normalized()
		var slot := float(r.slot)
		var place_offsets := {"home": -24.0-slot*5.0,"work": -16.0+slot*5.0,"cafe":18.0+slot*2.0,"market":-8.0+slot*2.0}
		for key in place_offsets:
			var near := world.terrain.nearest_road(road.point + along*place_offsets[key])
			var p: Vector3 = near.point + near.tangent.cross(Vector3.UP).normalized()*3.3
			p.y=navigation.support(p,world.terrain).height
			r.set_station(key,p)
		if String(r.location)=="harbour_cafe":
			var work_locations: Array[StringName]=[&"harbour_cafe",&"town_square",&"town_square",&"town_square",&"harbour_cafe",&"town_square",&"town_square",&"town_square"]
			var anchors: Dictionary={"home":&"town_square","work":work_locations[int(r.slot)%8],"cafe":&"harbour_cafe","market":&"town_square"}
			for key in anchors:
				var anchor: Vector3=world.database.location_pos(anchors[key])
				var nearest:=world.terrain.nearest_road(anchor)
				var shift:=float(int(r.slot)%4)*5.0-7.5
				var roadside:=world.terrain.nearest_road(nearest.point+nearest.tangent*shift)
				var side:=3.3 if int(r.slot)%2==0 else -3.3
				var p: Vector3=roadside.point+roadside.tangent.cross(Vector3.UP)*side
				p.y=navigation.support(p,world.terrain).height
				r.set_station(key,p)
			if r.transport=="car": r.route_locations=["town_square","harbour_cafe","lighthouse"]
			if int(r.slot)==5 and world.database.locations.has(&"town_courtyard_0"):
				var court: Vector3=world.database.location_pos(&"town_courtyard_0")
				court.y=navigation.support(court,world.terrain).height
				r.set_station("work",court)
		r.position=r.station("home"); r.forward=along
		residents.append(r); by_id[r.id]=r
		_assign_task(r,true)
	ambient=IslandWildlife.new(); ambient.name="WildlifeAndBoats"; add_child(ambient)
	ambient.setup(world,entities)
	outer=OuterLife.new(); add_child(outer)
	outer.setup(world,entities,self)
	_sync_views(0.0)
	print("[life] %d residents, %d road nodes, seven-day routines" % [residents.size(),navigation.graph.get_point_count()])

func day_index() -> int: return posmod(floori(total_minutes/1440.0),7)
func minute_of_day() -> float: return fposmod(total_minutes,1440.0)
func week_number() -> int: return floori(total_minutes/WEEK_MINUTES)+1
func clock_text() -> String:
	var minute := floori(minute_of_day())
	return "%s  %02d:%02d  ·  Week %d" % [DAYS[day_index()],minute/60,minute%60,week_number()]

func _assign_task(r: Resident, initial: bool=false) -> void:
	if colony_owned.has(r.id): return
	var task := r.task_at(day_index(),minute_of_day())
	var key := "%d:%s:%s" % [floori(total_minutes/1440),task.at,task.task]
	if key==r.task_key: return
	r.task_key=key; r.activity=task.activity; r.task=task.task; r.place=task.place
	r.driving = r.transport=="car" and r.activity=="deliver"
	r.wait=0.0; r.work_progress=0.0; r.station_validated=false
	r.blocked_time=0.0; r.route_retry=0.0; r.sim_elapsed=0.0
	var destination: Vector3=r.station(task.place)
	if initial:
		r.position=destination; r.speed=0.0
		r.route=PackedVector3Array(); r.cursor=0
	if r.driving:
		_dispatch_driver(r)
	elif not initial:
		_route_to(r,destination)
	else:
		r.status=r.task; r.moving=false
		r.transition(Resident.State.RESTING if r.activity=="sleep" else Resident.State.WORKING)

func _route_to(r: Resident, destination: Vector3) -> void:
	r.route=navigation.path(r.position,destination,1.05 if r.driving else 3.3,world.terrain)
	r.cursor=1 if r.route.size()>1 else 0
	r.moving=r.route.size()>1
	r.destination=destination
	if not r.moving:
		r.status="Route unavailable · "+r.task
		r.transition(Resident.State.ROUTE_BLOCKED)
		r.route_retry=5.0
	else:
		r.status=("Driving · " if r.driving else "Walking · ")+r.task
		r.transition(Resident.State.TRAVELLING)

func _dispatch_driver(r: Resident) -> void:
	if r.route_locations.is_empty():
		r.moving=false; r.transition(Resident.State.ROUTE_BLOCKED); r.route_retry=30.0
		r.status="No delivery stops assigned"
		return
	r.circuit=int(r.circuit)+1
	var stop: StringName=StringName(r.route_locations[int(r.circuit)%r.route_locations.size()])
	_route_to(r,world.database.location_pos(stop))
	r.status="Driving to "+world.database.location_name(stop)

func _physics_process(delta: float) -> void:
	if world==null: return
	total_minutes+=delta*minutes_per_second
	_accumulator+=delta
	if _accumulator>=.2:
		_accumulator=0.0
		for r in residents: _assign_task(r)
		if floori(total_minutes)!=_last_minute:
			_last_minute=floori(total_minutes); calendar_changed.emit()
		_update_daylight()
	_rebuild_neighbors()
	for r in residents:
		if actors.has(r.id):
			_advance(r,delta)
		else:
			r.sim_elapsed+=delta
			if r.sim_elapsed>=.2:
				_advance(r,float(r.sim_elapsed)); r.sim_elapsed=0.0
	_sync_views(delta)

func surface_at(p: Vector3, physics: bool=true) -> Dictionary:
	var support := navigation.support(p,world.terrain)
	if physics and is_inside_tree() and world.streamer.is_loaded_at(p):
		# Restrict to the expected support level so roofs, tree canopies and another
		# storey cannot teleport a pedestrian upwards.
		var top:=Vector3(p.x,float(support.height)+.65,p.z)
		var query:=PhysicsRayQueryParameters3D.create(top,top-Vector3.UP*1.5,1)
		var hit:=get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and hit.normal.y>.55:
			support={"height":hit.position.y,"normal":hit.normal}
	return support

func vehicle_support_at(p: Vector3, forward: Vector3, physics: bool=true) -> Dictionary:
	var right:=forward.cross(Vector3.UP).normalized()
	var front:=surface_at(p+forward,physics)
	var rear:=surface_at(p-forward,physics)
	var left:=surface_at(p-right*.72,physics)
	var other:=surface_at(p+right*.72,physics)
	var along:=forward*2+Vector3.UP*(float(front.height)-float(rear.height))
	var across:=right*1.44+Vector3.UP*(float(other.height)-float(left.height))
	return {"height":(float(front.height)+float(rear.height)+float(left.height)+float(other.height))*.25,"normal":across.cross(along).normalized()}

func _is_clear(p: Vector3, driving: bool=false) -> bool:
	if not world.streamer.is_loaded_at(p): return true
	var shape:=BoxShape3D.new()
	shape.size=Vector3(1.55,1.1,3.05) if driving else Vector3(.55,1.45,.55)
	var query:=PhysicsShapeQueryParameters3D.new()
	query.shape=shape; query.collision_mask=1
	query.transform=Transform3D(Basis(),p+Vector3.UP*(.82 if driving else .9))
	return get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func _validate_station(r: Resident) -> void:
	if r.station_validated or not world.streamer.is_loaded_at(r.position): return
	r.station_validated=true
	if _is_clear(r.position,r.driving): return
	# Old saves and authored props can occupy a station. Find a clear nearby
	# verge instead of spawning inside a wall or moving onto its roof.
	var road:=world.terrain.nearest_road(r.position)
	for distance in [0.0,2.0,-2.0,4.0,-4.0,7.0,-7.0]:
		for side in [3.1,-3.1,2.6,-2.6]:
			var p: Vector3=road.point+road.tangent*distance+road.tangent.cross(Vector3.UP)*side
			p.y=surface_at(p).height
			if _is_clear(p):
				r.position=p
				if not r.driving: r.set_station(r.place,p)
				return

func _travel_direction(r: Resident) -> Vector3:
	if r.moving and int(r.cursor)<r.route.size():
		var direction: Vector3=r.route[int(r.cursor)]-r.position
		direction.y=0
		if direction.length_squared()>.01: return direction.normalized()
	return r.forward

func _junction_stop_distance(r: Resident, other: Resident, direction: Vector3) -> float:
	if not r.driving or not other.driving or not other.moving or absf(r.position.y-other.position.y)>2.0: return INF
	var cross_direction:=_travel_direction(other)
	if absf(direction.dot(cross_direction))>.7: return INF
	var u:=Vector2(direction.x,direction.z)
	var v:=Vector2(cross_direction.x,cross_direction.z)
	var denominator:=u.cross(v)
	if absf(denominator)<.1: return INF
	var offset:=Vector2(other.position.x-r.position.x,other.position.z-r.position.z)
	var distance:=offset.cross(v)/denominator
	var other_distance:=offset.cross(u)/denominator
	if distance< -3.2 or other_distance< -3.2 or distance>14 or other_distance>14: return INF
	# Reserve the conflict area before either bumper enters it. A vehicle
	# already entering clears first; simultaneous arrivals use stable IDs.
	var priority: bool=String(r.id)<String(other.id)
	if distance<3.6 and other_distance>=3.6: priority=true
	elif other_distance<3.6 and distance>=3.6: priority=false
	if priority: return INF
	return maxf(0,distance-3.6)

func _obstacle_distance(r: Resident, direction: Vector3, reach: float) -> float:
	var clearance:=reach
	var position: Vector3=r.position
	var width:=.82 if r.driving else .32
	if entities.focus:
		var offset: Vector3=entities.focus.global_position-position
		var ahead:=offset.dot(direction)
		if ahead>0 and absf(offset.cross(direction).y)<width+.8 and absf(offset.y)<2:
			clearance=minf(clearance,maxf(0,ahead-1.8))
	for other in _nearby_residents(position, maxf(reach, 20.0)):
		if other.id==r.id or other.activity=="sleep": continue
		clearance=minf(clearance,_junction_stop_distance(r,other,direction))
		var offset: Vector3=other.position-position
		var ahead:=offset.dot(direction)
		var other_width:=.82 if other.driving else .3
		if ahead>0 and absf(offset.cross(direction).y)<width+other_width+.12 and absf(offset.y)<1.8:
			clearance=minf(clearance,maxf(0,ahead-(3.3 if other.driving and r.driving else 1.2)))
	if is_inside_tree():
		# Vehicles remain registered when the surrounding scenery is streamed
		# out. Their bodies must still stop abstract traffic.
		var mask: int=(1 if world.streamer.is_loaded_at(position) else 0)|2|4
		var right:=direction.cross(Vector3.UP).normalized()
		for side in [-width,0.0,width]:
			var start: Vector3=position+Vector3.UP*.9+right*float(side)
			var query:=PhysicsRayQueryParameters3D.create(start,start+direction*reach,mask)
			var hit:=get_world_3d().direct_space_state.intersect_ray(query)
			if not hit.is_empty(): clearance=minf(clearance,start.distance_to(hit.position)-(.95 if r.driving else .35))
	return maxf(0,clearance)

func _arrive(r: Resident) -> void:
	r.moving=false; r.speed=0.0; r.status=r.task; r.wait=0.0; r.station_validated=false
	r.transition(Resident.State.UNLOADING if r.driving else (Resident.State.RESTING if r.activity=="sleep" else Resident.State.WORKING))

func _advance(r: Resident, delta: float) -> void:
	if colony_owned.has(r.id): return
	r.state_elapsed += delta
	if r.state == Resident.State.ROUTE_BLOCKED:
		r.speed = 0.0
		r.route_retry -= delta
		if r.route_retry <= 0.0:
			if r.driving and r.route_locations.is_empty(): r.route_retry = 30.0
			else: _route_to(r, r.destination)
		return
	if not r.moving:
		r.speed=move_toward(float(r.speed),0,delta*6)
		_validate_station(r)
		var support:=vehicle_support_at(r.position,r.forward,actors.has(r.id)) if r.driving else surface_at(r.position,actors.has(r.id))
		r.position.y=support.height; r.surface_normal=support.normal
		if r.driving:
			r.transition(Resident.State.UNLOADING)
			r.wait+=delta
			r.status="Unloading · "+String(r.task)
			if r.wait>=18.0:
				r.deliveries_completed+=1; r.completed_tasks+=1; r.wait=0.0; _dispatch_driver(r)
		elif String(r.activity) in ["garden","repair","bake","fish","build","sell","teach","deliver"]:
			r.transition(Resident.State.WORKING)
			r.work_progress+=delta
			if r.work_progress>=30.0:
				r.completed_tasks+=floori(r.work_progress/30.0); r.work_progress=fposmod(r.work_progress,30.0)
		return
	if int(r.cursor)>=r.route.size():
		_arrive(r)
		return
	var target: Vector3=r.route[int(r.cursor)]
	var direction:=target-Vector3(r.position); direction.y=0
	while direction.length()<.18 and int(r.cursor)<r.route.size()-1:
		r.cursor+=1; target=r.route[int(r.cursor)]; direction=target-Vector3(r.position); direction.y=0
	var remaining:=direction.length()
	if remaining<.08:
		_arrive(r)
		return
	direction=direction.normalized()
	var desired_speed:=7.5 if r.driving else 1.35
	if r.driving:
		# Slow before bends; acceleration and braking have finite rates.
		var turn:=acos(clampf(Vector3(r.forward).dot(direction),-1,1))
		desired_speed*=lerpf(1.0,.23,clampf(turn/.8,0,1))
		if int(r.cursor)==r.route.size()-1: desired_speed=minf(desired_speed,sqrt(2*4.5*remaining))
	var reach:=maxf(3.0,float(r.speed)*float(r.speed)/9.0+2.0)
	var obstacle:=_obstacle_distance(r,direction,reach)
	if obstacle<reach-.05: desired_speed=minf(desired_speed,sqrt(maxf(0,2*4.5*(obstacle-.5))))
	if obstacle<.65:
		desired_speed=0; r.status="Yielding to traffic" if r.driving else "Waiting for a clear path"
		r.transition(Resident.State.YIELDING)
		r.blocked_time+=delta
	else:
		r.transition(Resident.State.TRAVELLING)
		r.blocked_time=0.0; r.status=("Driving · " if r.driving else "Walking · ")+String(r.task)
	if not r.driving and r.blocked_time>2.0:
		# A small, ground-validated detour around roadside props. Never tunnel
		# through them or teleport to the next schedule location.
		for side in [1.0,-1.0]:
			var detour: Vector3=r.position+direction*1.0+direction.cross(Vector3.UP)*side*1.3
			detour.y=surface_at(detour).height
			if _is_clear(detour) and absf(detour.y-r.position.y)<.7:
				r.route.insert(int(r.cursor),detour); r.blocked_time=0.0; break
	r.speed=move_toward(float(r.speed),desired_speed,delta*(2.0 if desired_speed>float(r.speed) else 6.0))
	var travel:=minf(minf(float(r.speed)*delta,remaining),maxf(0,obstacle-.25))
	var next: Vector3=r.position+direction*travel
	var support:=vehicle_support_at(next,direction,actors.has(r.id)) if r.driving else surface_at(next,actors.has(r.id))
	next.y=support.height
	if actors.has(r.id):
		var actor: ResidentActor=actors[r.id]
		next=actor.move_supported(next,delta)
	var travelled:=Vector2(next.x-r.position.x,next.z-r.position.z).length()
	r.position=next; r.distance+=travelled; r.surface_normal=support.normal
	if travelled>.001:
		var yaw:=lerp_angle(atan2(-r.forward.x,-r.forward.z),atan2(-direction.x,-direction.z),minf(1,delta*(3.0 if r.driving else 8.0)))
		r.forward=Vector3(-sin(yaw),0,-cos(yaw))
	if Vector2(target.x-next.x,target.z-next.z).length()<.08:
		r.cursor+=1
		if int(r.cursor)>=r.route.size():
			_arrive(r)

func _sync_views(delta: float) -> void:
	if entities.focus==null: return
	var focus:=entities.focus.global_position
	# Build the looks of residents about to come into view before they do (worker threads).
	PersonBuilder.poll()
	_prefetch_frame+=1
	if _prefetch_frame%20==0:
		var reach:=_views.spawn_radius+60.0
		for r in residents:
			if r.activity!="sleep" and not actors.has(r.id) and focus.distance_to(r.position)<reach:
				PersonBuilder.request(CharacterLook.for_resident(r))
	_views.sync(residents,focus)
	for r in residents:
		var actor: ResidentActor=_views.view(r.id)
		if actor==null: continue
		actor.position=r.position
		var yaw:=atan2(-r.forward.x,-r.forward.z)
		actor.rotation.y=lerp_angle(actor.rotation.y,yaw,clampf(delta*8,0,1))
		actor.update_view(r,delta,focus.distance_to(r.position)<14.0)

func _update_daylight() -> void:
	var hour:=minute_of_day()/60.0
	var daylight:=smoothstep(5.0,7.5,hour)*(1.0-smoothstep(18.0,21.0,hour))
	world.island.sun.light_energy=lerpf(.10,1.2,daylight)
	world.island.sun.rotation_degrees.x=lerpf(-12,-63,sin(clampf((hour-6)/12,0,1)*PI))
	for child in world.environment.get_children():
		if child is WorldEnvironment:
			var env: Environment=child.environment
			env.ambient_light_energy=lerpf(.25,.47,daylight)
			if env.sky.sky_material is ShaderMaterial: env.sky.sky_material.set_shader_parameter("daylight",lerpf(.08,1,daylight))

func save_state() -> Dictionary:
	var records: Dictionary={}
	for r in residents: records[r.id]=r.to_dict()
	return {"version":3,"total_minutes":total_minutes,"residents":records,"ambient_time":ambient.elapsed if ambient else 0.0}

func load_state(data: Dictionary) -> void:
	total_minutes=maxf(0,float(data.get("total_minutes",570.0)))
	for r in residents:
		r.task_key=""; _assign_task(r,true)
		r.apply_dict(data.get("residents",{}).get(r.id,{}))
	if ambient: ambient.elapsed=float(data.get("ambient_time",0.0))
	if outer and outer.towns: outer.towns.reset()
	_sync_views(0.0); _update_daylight(); calendar_changed.emit()


## Skip the clock forward — resting the night away at Villa Rosa, or anything else that wants
## time to pass. Everyone is placed at the station their new task calls for, in-flight routes are
## dropped, and lifetime totals carry across by construction: no caller has to hand-copy them,
## and adding a new counter to a Resident cannot silently reset it here.
func advance_to(absolute_minute: float) -> void:
	var totals: Dictionary={}
	for r in residents: totals[r.id]=r.lifetime_totals()
	total_minutes=maxf(total_minutes,absolute_minute)
	for r in residents:
		r.task_key=""
		r.route=PackedVector3Array(); r.cursor=0; r.moving=false; r.speed=0.0
		r.blocked_time=0.0; r.wait=0.0; r.work_progress=0.0
		_assign_task(r,true)
		r.restore_lifetime(totals[r.id])
	if outer and outer.towns: outer.towns.reset()
	_sync_views(0.0); _update_daylight(); calendar_changed.emit()
