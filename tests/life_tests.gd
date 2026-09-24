extends Node
## Real island integration checks; no screenshot-only or mirrored implementation assertions.
class SlidingActor extends ResidentActor:
	func move_supported(_destination: Vector3, _delta: float) -> Vector3:
		# Controlled collision response: the body slid sideways, not toward
		# the pending waypoint. This reproduces the integration regression.
		global_position+=Vector3(.12,0,0)
		return global_position

var failures:=0
var main: Game
var life: IslandLife

func _check(ok: bool, description: String) -> void:
	print(("  PASS " if ok else "  FAIL ")+description)
	if not ok: failures+=1

func _ready() -> void:
	main=Game.current; life=main.life
	call_deferred("_run")

func _run() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	life.set_physics_process(false)
	var original:=life.save_state()
	var empty_routine := Resident.new()
	_check(empty_routine.task_at(0, 570).activity == "sleep", "empty resident routine safely rests at home")
	var failed_route := life.residents[0].clone()
	failed_route.driving = true
	failed_route.moving = false
	failed_route.transition(Resident.State.ROUTE_BLOCKED)
	failed_route.route_retry = 100.0
	var original_deliveries := failed_route.deliveries_completed
	life._advance(failed_route, 20.0)
	_check(failed_route.deliveries_completed == original_deliveries, "failed route cannot invent a completed delivery")
	failed_route.destination = Vector3(23, 4, 51)
	var restored := Resident.new()
	restored.apply_dict(failed_route.to_dict())
	_check(restored.destination == failed_route.destination and restored.state == Resident.State.ROUTE_BLOCKED, "route destination and explicit blocked state survive persistence")

	_check(life.residents.size()==64,"64 individually identified residents")
	var complete_days:=true
	var connected:=true
	for r in life.residents:
		for day in 7:
			var schedule:=r.schedule_for(day)
			complete_days=complete_days and schedule[0].at==0 and schedule[-1].until==1440
			for i in range(1,schedule.size()): complete_days=complete_days and schedule[i-1].until==schedule[i].at
			for entry in schedule: complete_days=complete_days and r.has_station(entry.place)
		for destination in r.route_locations:
			var route:=life.navigation.path(r.position,main.world.database.location_pos(StringName(destination)),1.05,main.world.terrain)
			if route.size()<2: print("    Missing road route ",r.name," → ",destination); connected=false
	_check(complete_days,"all weekly schedules cover every minute and reference real stations")
	_check(connected,"every resident delivery destination is connected through roads")
	var lane_error:=0.0

	for r in life.residents:
		if r.transport!="car": continue
		for destination in r.route_locations:
			var path:=life.navigation.path(r.position,main.world.database.location_pos(StringName(destination)),1.05,main.world.terrain)
			for index in range(2,path.size()):
				for weight in [.25,.5,.75]:
					var point: Vector3=path[index-1].lerp(path[index],weight)
					var nearest_id:=life.navigation.graph.get_closest_point(point)
					var nearest_point:=life.navigation.graph.get_point_position(nearest_id)
					var error:=INF
					for neighbor in life.navigation.graph.get_point_connections(nearest_id):
						if life.navigation.road_ids[neighbor]!=life.navigation.road_ids[nearest_id]: continue
						var endpoint:=life.navigation.graph.get_point_position(neighbor)
						var closest:=Geometry2D.get_closest_point_to_segment(Vector2(point.x,point.z),Vector2(nearest_point.x,nearest_point.z),Vector2(endpoint.x,endpoint.z))
						error=minf(error,closest.distance_to(Vector2(point.x,point.z)))
					lane_error=maxf(lane_error,error)
	_check(lane_error<2.4,"traffic segments remain inside road corridor (max %.2fm from centre)"%lane_error)
	var person: Resident=life.residents[0]
	var monday:=person.task_at(0,570)
	_check(monday==person.task_at(7,570),"weekly tasks repeat after Sunday")
	life.total_minutes=10079.8
	life.total_minutes+=.5
	_check(life.day_index()==0 and life.week_number()==2 and absf(life.minute_of_day()-.3)<.001,"calendar wraps to Monday of week two without resetting absolute time")
	life.total_minutes=570
	var sample_count:=0
	var biggest_error:=0.0
	for road in main.world.terrain.road_samples:
		for i in range(0,road.size(),23):
			var near:=main.world.terrain.nearest_road(road[i])
			var p: Vector3=near.point+near.tangent.cross(Vector3.UP)*3.3
			var ground:=main.world.terrain.height_at(p.x,p.z)
			# Away from bridges, the verge must use its own terrain height.
			if absf(near.point.y-main.world.terrain.height_at(near.point.x,near.point.z))<.2:
				biggest_error=maxf(biggest_error,absf(float(life.surface_at(p,false).height)-ground)); sample_count+=1
	_check(sample_count>100 and biggest_error<.02,"sloped verges use foot position terrain (max error %.3fm across %d samples)"%[biggest_error,sample_count])
	var bridge_ok:=true
	for bridge in main.world.terrain.bridges:
		var samples: PackedVector3Array=bridge.samples
		var p: Vector3=samples[(int(bridge.from)+int(bridge.to))/2]
		bridge_ok=bridge_ok and float(life.surface_at(p,false).height)>=p.y-.05
	_check(bridge_ok,"abstract residents use real bridge decks over the seabed")
	var destination: Vector3=person.station("cafe")
	var pedestrian_route:=life.navigation.path(person.position,destination,3.3,main.world.terrain)
	_check(not pedestrian_route.is_empty() and Vector2(pedestrian_route[-1].x-destination.x,pedestrian_route[-1].z-destination.z).length()<.01,"walking route reaches the actual activity station")
	var before_jobs:=int(person.completed_tasks)
	person.moving=false; person.driving=false; person.activity="garden"
	life._advance(person,30.1)
	_check(int(person.completed_tasks)==before_jobs+1,"working at a station completes a timed work cycle")
	var driver: Resident=life.residents.filter(func(r: Resident): return r.transport=="car")[0]
	driver.driving=true; driver.activity="deliver"; driver.moving=false; driver.wait=17.9
	var before_deliveries:=int(driver.deliveries_completed)
	life._advance(driver,.2)
	_check(int(driver.deliveries_completed)==before_deliveries+1 and driver.moving,"drivers unload cargo then dispatch to another connected destination")
	# Use a distant road to exercise the abstract movement with no actor/collider loaded.
	var remote: Resident=life.residents.filter(func(r: Resident): return r.transport=="car" and not life.actors.has(r.id))[-1]
	remote.driving=true; remote.activity="deliver"; remote.task_key=""; life._assign_task(remote,true)
	life._route_to(remote,main.world.database.location_pos(&"hilltop_farm"))
	var start: Vector3=remote.position
	for i in 100: life._advance(remote,.1)
	_check(remote.position.distance_to(start)>4 and float(remote.speed)<=7.5,"distant traffic advances with capped acceleration and speed")
	# A car must brake for a person standing immediately ahead, even without a view.
	var blocker: Resident=life.residents[1]
	var ahead: Vector3=remote.route[mini(int(remote.cursor),remote.route.size()-1)]-remote.position; ahead.y=0; ahead=ahead.normalized()
	blocker.position=remote.position+ahead*1.5; blocker.activity="social"; blocker.driving=false
	var blocked_start: Vector3=remote.position
	for i in 10: life._advance(remote,.1)
	_check(remote.position.distance_to(blocked_start)<.5,"traffic yields before crossing a pedestrian")
	var population:=life.residents
	var crossing_a:=driver.clone()
	var crossing_b:=driver.clone()
	crossing_a.id="test.crossing.a"; crossing_b.id="test.crossing.b"
	var centre:=Vector3(650,0,650)
	for entry in [[crossing_a,Vector3.RIGHT],[crossing_b,Vector3.BACK]]:
		var r: Resident=entry[0]; var direction: Vector3=entry[1]
		r.position=centre-direction*9
		r.position.y=life.surface_at(r.position,false).height
		r.forward=direction; r.route=PackedVector3Array([r.position,centre+direction*9]); r.cursor=1
		r.moving=true; r.driving=true; r.speed=0.0; r.blocked_time=0.0
	var pair: Array[Resident]=[crossing_a,crossing_b]
	life.residents=pair
	var minimum_separation:=INF
	for i in 400:
		life._advance(crossing_a,.05); life._advance(crossing_b,.05)
		minimum_separation=minf(minimum_separation,Vector2(crossing_a.position.x-crossing_b.position.x,crossing_a.position.z-crossing_b.position.z).length())
	_check(crossing_a.position.x>centre.x+5 and crossing_b.position.z>centre.z+5,"simultaneous perpendicular drivers both clear the junction")
	_check(minimum_separation>3.0,"junction priority preserves safe separation (%.2fm)"%minimum_separation)
	life.residents=population
	var harbour_positions: Array[Vector3]=[]
	for r in life.residents:
		if r.location=="harbour_cafe" and r.transport!="car": harbour_positions.append(r.station("work"))
	var spread:=0.0
	for a in harbour_positions:
		for b in harbour_positions: spread=maxf(spread,a.distance_to(b))
	_check(spread>30,"Harbour residents work across town and waterfront stations")
	var sliding:=SlidingActor.new(); main.entities.add_child(sliding)
	var sliding_record:=driver.clone()
	sliding_record.id="test.sideways"; sliding_record.position=centre
	sliding_record.position.y=life.surface_at(centre,false).height
	sliding.global_position=sliding_record.position
	sliding_record.route=PackedVector3Array([sliding_record.position,sliding_record.position+Vector3(0,0,.12)])
	sliding_record.cursor=1; sliding_record.moving=true; sliding_record.driving=true; sliding_record.speed=2.0
	life.actors[sliding_record.id]=sliding
	life._advance(sliding_record,.1)
	_check(sliding_record.moving and sliding_record.cursor==1,"sideways collision response does not consume an unreached waypoint")
	life.actors.erase(sliding_record.id); sliding.queue_free()
	var saved:=life.save_state()
	var saved_distance: float=remote.distance
	life.total_minutes=9000; remote.distance=0; remote.completed_tasks=999
	life.load_state(saved)
	_check(absf(life.total_minutes-float(saved.total_minutes))<.001 and is_equal_approx(float(remote.distance),saved_distance) and remote.completed_tasks==saved.residents[remote.id].completed_tasks,"save/load restores clock, route progress and completed work")
	# The Resident's fields, its save and its load used to be three hand-written lists that had
	# already drifted apart. They are one list now, and this is the check that keeps them one.
	var probe_person: Resident=life.residents[3]
	probe_person.blocked_time=4.25; probe_person.station_validated=true; probe_person.activity="fish"
	probe_person.work_progress=7.5; probe_person.task="Mend the nets"; probe_person.place="work"
	var round_trip:=probe_person.to_dict()
	var fresh:=Resident.new()
	fresh.apply_dict(round_trip)
	var dropped: Array[String]=[]
	for key in Resident.SAVED:
		if fresh.get(key)!=probe_person.get(key): dropped.append(key)
	# Spawn/despawn hysteresis had no test at all while it was written out twice, in IslandLife
	# and IslandWildlife, with three different pairs of radii. One pool, one table of checks.
	var pool:=ViewPool.new(main.entities,&"testview",func(_r: Resident) -> Node3D: return Node3D.new())
	pool.spawn_radius=50.0; pool.keep_margin=20.0
	var subject:=driver.clone(); subject.id="test.pool.a"; subject.position=Vector3.ZERO; subject.activity="garden"
	var population_of_one: Array[Resident]=[subject]
	pool.sync(population_of_one,Vector3(0,0,60))
	_check(pool.count()==0,"a record beyond the spawn radius has no body")
	pool.sync(population_of_one,Vector3(0,0,40))
	_check(pool.count()==1 and main.entities.has_entity(&"test.pool.a"),"coming inside the spawn radius builds and registers a view")
	pool.sync(population_of_one,Vector3(0,0,60))
	_check(pool.count()==1,"hysteresis keeps the view alive just past the spawn radius")
	pool.sync(population_of_one,Vector3(0,0,80))
	_check(pool.count()==0 and not main.entities.has_entity(&"test.pool.a"),"passing the keep margin frees and unregisters the view")
	pool.awake_for=func(r: Resident) -> bool: return r.activity!="sleep"
	subject.activity="sleep"
	pool.sync(population_of_one,Vector3.ZERO)
	_check(pool.count()==0,"a sleeping resident never gets a body, however close the focus")
	_check(dropped.is_empty(),"every saved Resident field survives the round trip%s" % ("" if dropped.is_empty() else " (dropped: %s)" % ", ".join(dropped)))
	# Skipping the night is the simulation's own operation now, not a fake save payload posted
	# from the courier counter. Lifetime totals must survive it by construction.
	var before_totals: Array=[]
	for r in life.residents: before_totals.append(r.lifetime_totals())
	var morning: float=(floorf(life.total_minutes/1440.0)+1.0)*1440.0+480.0
	life.advance_to(morning)
	var totals_kept:=true
	var at_station:=true
	for i in range(life.residents.size()):
		var r: Resident=life.residents[i]
		for key in Resident.LIFETIME:
			totals_kept=totals_kept and r.get(key)==before_totals[i][key]
		# Drivers are dispatched onto a route by the new task; walkers start where it puts them.
		if not r.driving:
			at_station=at_station and r.position.distance_to(r.station(r.place))<.01 and not r.moving
	_check(absf(life.total_minutes-morning)<.001 and life.minute_of_day()==480.0,"advance_to lands on the next morning at 08:00")
	_check(totals_kept,"a time skip preserves every lifetime total")
	_check(at_station,"every walker starts the new day at the station their task calls for")
	# Regression: exiting a car cannot leave the riding hip offset on a walker.
	if life.actors.has(person.id):
		var actor: ResidentActor=life.actors[person.id]
		person.driving=true; actor.update_view(person,.016,true)
		person.driving=false; person.moving=false; actor.update_view(person,.016,true)
		_check(absf(actor.person.root.position.y-RiderModel.HIP_H)<.001,"dismounted resident pelvis resets immediately to grounded pose")
		var foot_height: float=actor.person.sole_height()-actor.global_position.y
		_check(absf(foot_height)<.10,"visible boot soles touch the resident support plane (%.3fm)"%foot_height)
	# Every islander is their own person: looks are derived from the id and never repeat.
	var signatures:={}
	for r in life.residents: signatures[str(CharacterLook.signature(CharacterLook.for_resident(r)))]=true
	_check(signatures.size()==life.residents.size(),"no two residents share hair, hair colour, top and top colour (%d looks)"%signatures.size())
	var probe_look:=var_to_str(CharacterLook.for_resident(life.residents[9]))
	CharacterLook._resident_cache.clear()
	_check(probe_look==var_to_str(CharacterLook.for_resident(life.residents[9])),"resident looks are deterministic")
	var dressed:=true
	for id in life.actors:
		var view: ResidentActor=life.actors[id]
		dressed=dressed and view.person.is_person() and view.person.look.get("key","")==CharacterLook.for_resident(life.by_id[id]).key
	_check(dressed and life.actors.size()>0,"resident views wear their own look (%d views)"%life.actors.size())
	# Exercise actual broad-phase bodies, isolated above the terrain so a floor
	# collision cannot accidentally make these assertions pass.
	var truck_transform: Transform3D=main.truck.global_transform
	var bike_transform: Transform3D=main.bike.global_transform
	var player_transform: Transform3D=main.player.global_transform
	main.truck.set_physics_process(false); main.bike.set_physics_process(false); main.player.set_physics_process(false)
	var car_actor:=ResidentActor.new(); main.entities.add_child(car_actor); car_actor.setup(driver)
	main.truck.global_position=Vector3(0,100,0); main.truck.rotation=Vector3.ZERO
	main.bike.global_position=Vector3(30,100,0)
	main.player.process_mode=Node.PROCESS_MODE_INHERIT
	main.player.set_physics_process(false)
	main.player.collision_mask=1|2|16
	main.player.global_position=Vector3(60,100,0)
	car_actor.global_position=Vector3(0,100,8)
	await get_tree().physics_frame
	_check(car_actor.test_move(car_actor.global_transform,Vector3(0,0,-8)),"resident vehicle body collides with parked player truck")
	_check(main.truck.test_move(main.truck.global_transform,Vector3(0,0,8)),"player truck body collides with resident vehicle")
	car_actor.global_position=Vector3(30,100,8)
	await get_tree().physics_frame
	_check(main.bike.test_move(main.bike.global_transform,Vector3(0,0,8)),"player bike body collides with resident vehicle")
	car_actor.global_position=Vector3(60,100,8)
	await get_tree().physics_frame
	_check(main.player.test_move(main.player.global_transform,Vector3(0,0,8)),"walking player collides with resident vehicle")
	# Restore the real truck onto its road before checking the traffic sensor.
	main.truck.global_transform=truck_transform
	main.truck.process_mode=Node.PROCESS_MODE_INHERIT
	main.truck.set_physics_process(false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var probe:=driver.clone()
	probe.position=main.truck.global_position+Vector3(0,0,7)
	probe.driving=true
	var obstacle_distance:=life._obstacle_distance(probe,Vector3.FORWARD,12.0)
	_check(obstacle_distance<7,"traffic sensor brakes for parked truck independent of current player focus")
	car_actor.queue_free()
	main.bike.global_transform=bike_transform; main.player.global_transform=player_transform
	life.load_state(original)
	print("LIFE TESTS: %s (%d failures)"%["PASS" if failures==0 else "FAIL",failures])
	get_tree().quit(0 if failures==0 else 1)
