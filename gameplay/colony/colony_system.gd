class_name ColonySystem
extends Node3D
## Red Sea Baron colony rules, using DesertDelivery's existing resident population.
## Inventory moves only at pickup/delivery commits; active orders reserve stock.
## `economy` (ColonyEconomy) is the colony-sim layer built on it: every town a colony, production
## chains, needs and growth, shipping lanes. The colony warehouse is the core colony's stockpile.
## Save format: version 2 = the v1 fields + "economy"; a v1 save loads with the economy at its
## starting state (its warehouse becomes the core stockpile).
signal changed
signal message(text: String)
var game: Game
var areas: Array = []
var sites: Dictionary = {}
var assignments: Dictionary = {}
var statuses: Dictionary = {}
var orders: Dictionary = {}
const SAVE_VERSION := 2
var warehouse: Dictionary = {"wood":20}
var economy: ColonyEconomy
var warehouse_position := Vector3.ZERO
var roads: ColonyRoads
var next_id := 1
var paused := false
var _sources: Array[ColonyResource] = []
var _residents: Dictionary = {}
var _clock := 0.0
var _visuals: Node3D
var _area_visuals: Node3D
var _test_height: Callable
var _initial_state: Dictionary = {}
var _plan_queue: Dictionary = {}
func setup(p_game: Game) -> void:
	game=p_game
	warehouse_position=game.world.database.location_pos(&"villa_square")
	_initialize(game.life.residents)
	_seed_resources()
	economy.setup_world(game)
	_initial_state=save_state()
func _initialize(residents: Array) -> void:
	_visuals=Node3D.new(); add_child(_visuals)
	_area_visuals=Node3D.new(); add_child(_area_visuals)
	roads=ColonyRoads.new(); roads.colony=self; add_child(roads)
	for r: Resident in residents:
		_residents[r.id]=r; assignments[r.id]={"role":"Unemployed","enabled":false}
	_marker(_visuals,warehouse_position,Color("bd9763"),Vector3(2,1.4,2),"Colony warehouse")
	for item in EconomyCatalog.CHARTER_STOCK: warehouse[item]=int(warehouse.get(item,0))+int(EconomyCatalog.CHARTER_STOCK[item])
	economy=ColonyEconomy.new(); economy.name="Economy"; add_child(economy)
	economy.setup_core(self,warehouse_position)
func grounded(at: Vector2) -> Vector3:
	var height:=float(_test_height.call(at)) if _test_height.is_valid() else game.world.terrain.height_at(at.x,at.y)
	return Vector3(at.x,height+.08,at.y)
func walkable(at: Vector3) -> bool:
	if not at.is_finite() or maxf(absf(at.x),absf(at.z))>12496 or at.y<.2: return false
	if game==null: return true
	var q:=PhysicsShapeQueryParameters3D.new(); var s:=BoxShape3D.new(); s.size=Vector3(.65,1.5,.65); q.shape=s
	q.transform.origin=at+Vector3.UP*.9; q.collision_mask=1 # Static obstacles; resident layer16 must not block its own origin.
	return get_world_3d().direct_space_state.intersect_shape(q,1).is_empty()
func segment_clear(from: Vector3,to: Vector3) -> bool:
	if game==null: return true
	var query:=PhysicsRayQueryParameters3D.create(from+Vector3.UP*.9,to+Vector3.UP*.9,1)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()
func _seed_resources() -> void:
	var entries: Array = [["wood",Vector2(-36,53)],["wood",Vector2(-43,57)],["wood",Vector2(-34,64)],["wood",Vector2(-45,68)],["wood",Vector2(-54,62)],["berry",Vector2(-37,-30)],["berry",Vector2(-42,-33)],["berry",Vector2(-31,-35)],["stone",Vector2(65,39)],["stone",Vector2(73,40)],["ore",Vector2(72,30)],["olive",Vector2(-48,-48)]]
	for i in range(entries.size()):
		var at: Vector2=Vector2(warehouse_position.x,warehouse_position.z)+entries[i][1]
		# Keep the original relative resource clusters, nudging blocked seeds onto dry ground.
		var candidate:=grounded(at)
		for attempt in range(128):
			candidate=grounded(at+Vector2(cos(attempt*2.39996),sin(attempt*2.39996))*sqrt(float(attempt))*2.0)
			if walkable(candidate): break
		if walkable(candidate): _add_source("colony_resource_%d"%i,entries[i][0],candidate,entries[i][0] in ["berry","olive"])
func _add_source(id: String,item: String,at: Vector3,renewable: bool) -> ColonyResource:
	var source:=ColonyResource.new(); source.source_id=id; source.item_id=item; source.position=at; source.renewable=renewable
	source.title={"wood":"Timber stand","berry":"Berry patch","stone":"Stone deposit","ore":"Iron deposit","olive":"Olive beds"}[item]
	add_child(source); _sources.append(source)
	_marker(source,Vector3.ZERO,ColonyCatalog.color({"wood":"Woodcutter","berry":"Forager","olive":"Farmer"}.get(item,"Miner")),Vector3(1.7,2.5 if item=="wood" else .7,1.7),source.title)
	return source
func _marker(parent: Node3D,at: Vector3,color: Color,size: Vector3,title: String) -> void:
	var m:=MeshInstance3D.new(); var box:=BoxMesh.new(); box.size=size; m.mesh=box; m.position=at+Vector3.UP*size.y*.5
	var mat:=StandardMaterial3D.new(); mat.albedo_color=color; mat.roughness=1; m.material_override=mat; parent.add_child(m)
	var label:=Label3D.new(); label.text=title; label.position=at+Vector3.UP*(size.y+.5); label.billboard=BaseMaterial3D.BILLBOARD_ENABLED; label.font_size=24; label.pixel_size=.012; label.visibility_range_end=90; parent.add_child(label)
func sources() -> Array[ColonyResource]: return _sources
func source_by_id(id: String) -> Node3D:
	if sites.has(id): return sites[id]
	for source in _sources:
		if source.source_id==id: return source
	return null
func area_sources(area: Dictionary) -> Array[ColonyResource]:
	var result: Array[ColonyResource]=[]
	for source in _sources:
		if ColonyCatalog.accepts(area.role,source.item_id) and Vector2(source.position.x-area.x,source.position.z-area.z).length()<=float(area.radius): result.append(source)
	return result
func designate(role: String,at: Vector3,radius: float) -> bool:
	if role not in ColonyCatalog.ZONE_ROLES or areas.size()>=64 or not at.is_finite() or maxf(absf(at.x),absf(at.z))>12496: return false
	var area: Dictionary={"id":"zone_%d"%next_id,"role":role,"x":at.x,"z":at.z,"radius":clampf(radius,6,32),"enabled":true}
	if area_sources(area).is_empty(): message.emit("No matching resources inside this area."); return false
	next_id+=1; areas.append(area); redraw_areas(); changed.emit(); return true
func redraw_areas() -> void:
	for child in _area_visuals.get_children(): child.queue_free()
	for area in areas:
		var mesh:=ImmediateMesh.new(); var mat:=StandardMaterial3D.new(); mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED; mat.albedo_color=ColonyCatalog.color(area.role) if area.enabled else Color.GRAY
		mesh.surface_begin(Mesh.PRIMITIVE_LINES,mat)
		for i in range(64):
			for step in [i,i+1]:
				var p:=Vector2(area.x,area.z)+Vector2(cos(step*TAU/64),sin(step*TAU/64))*float(area.radius)
				mesh.surface_add_vertex(grounded(p)+Vector3.UP*.12)
		mesh.surface_end(); var node:=MeshInstance3D.new(); node.mesh=mesh; _area_visuals.add_child(node)
func set_area_enabled(id: String,value: bool) -> void:
	for area in areas:
		if area.id==id: area.enabled=value
	redraw_areas(); changed.emit()
func remove_area(id: String) -> bool:
	for order in orders.values():
		if order.get("zone","")==id: message.emit("Disable the area and let current deliveries finish first."); return false
	for i in range(areas.size()):
		if areas[i].id==id: areas.remove_at(i); redraw_areas(); changed.emit(); return true
	return false
func assign_role(id: String,role: String,enabled: bool=true) -> bool:
	if not _residents.has(id) or role not in ColonyCatalog.CORE: return false
	assignments[id]={"role":role,"enabled":enabled and role!="Unemployed"}
	if enabled and role!="Unemployed": _claim(id)
	elif not orders.has(id): _release(id)
	changed.emit(); return true
func _claim(id: String) -> void:
	if game: game.life.colony_owned[id]=true
	var r: Resident=_residents[id]; r.driving=false; r.activity="build"; r.station_validated=true; r.moving=false; r.speed=0; r.route.clear()
func _release(id: String) -> void:
	if game: game.life.colony_owned.erase(id)
	var r: Resident=_residents[id]; r.task_key=""; r.moving=false; r.speed=0
func set_paused(value: bool) -> void: paused=value; changed.emit()
func can_place(at: Vector3,kind: String="Depot") -> bool:
	if kind not in ColonyCatalog.WORKPLACES or not at.is_finite() or maxf(absf(at.x),absf(at.z))>12490 or sites.size()>=32: return false
	var floor_at:=grounded(Vector2(at.x,at.z))
	if not walkable(floor_at): return false
	for offset in [Vector2(3,3),Vector2(-8 if kind=="Farm" else -3,-3),Vector2(3,-3),Vector2(-8 if kind=="Farm" else -3,3)]:
		var p:=grounded(Vector2(at.x,at.z)+offset)
		if absf(p.y-floor_at.y)>1.5 or not walkable(p): return false
	for site: ColonySite in sites.values():
		if Vector2(site.position.x-at.x,site.position.z-4-at.z).length()<9: return false
	if game:
		var q:=PhysicsShapeQueryParameters3D.new(); var shape:=BoxShape3D.new()
		shape.size=Vector3(11 if kind=="Farm" else 6,3.0,6); q.shape=shape
		q.transform.origin=floor_at+Vector3(-2.5 if kind=="Farm" else 0,1.9,0); q.collision_mask=1|2|16
		if not get_world_3d().direct_space_state.intersect_shape(q,1).is_empty(): return false
	return true
func place_site(kind: String,at: Vector3) -> bool:
	if not can_place(at,kind): message.emit("Choose clear, dry, gently sloped ground."); return false
	_create_site("site_%d"%next_id,kind,grounded(Vector2(at.x,at.z+4))); next_id+=1; changed.emit(); return true
func _create_site(id: String,kind: String,at: Vector3,built: bool=false) -> ColonySite:
	var site:=ColonySite.new(); site.site_id=id; site.blueprint=kind; site.position=at; site.built=built; add_child(site); sites[id]=site
	site.completed.connect(func(): _build_visual(site); replan_workers(); changed.emit(); message.emit(kind+" completed."))
	_build_visual(site); return site
func _build_visual(site: ColonySite) -> void:
	for child in site.get_children():
		if child!=site.field: child.queue_free()
	_marker(site,Vector3(0,0,-4),Color("dbcaaa") if site.built else Color("ae9367"),Vector3(4.8,2.2 if site.built else .2,4),site.blueprint+(" · Ready" if site.built else " · 10 timber"))
	if site.built:
		var body:=StaticBody3D.new(); body.collision_layer=1; body.collision_mask=0; site.add_child(body)
		var collider:=CollisionShape3D.new(); var box:=BoxShape3D.new(); box.size=Vector3(4.8,2.2,4); collider.shape=box; collider.position=Vector3(0,1.1,-4); body.add_child(collider)
	if site.built and site.blueprint=="Farm" and site.field==null:
		site.field=_add_source("farm_"+site.site_id,"olive",grounded(Vector2(site.position.x-5,site.position.z-2)),true)
func _stock(id: String,item: String) -> int:
	if id=="warehouse": return int(warehouse.get(item,0))
	var node:=source_by_id(id)
	if node is ColonyResource: return node.stock if node.item_id==item else 0
	if node is ColonySite: return int(node.inventory.get(item,0))
	return 0
func reserved(id: String,item: String,incoming: bool=false) -> int:
	var total:=0
	for order in orders.values():
		if order.get("item","")!=item: continue
		if incoming and order.get("destination","")==id: total+=int(order.amount)
		elif not incoming and order.get("source","")==id and not order.get("acquired",false): total+=int(order.amount)
	return total
func available(id: String,item: String) -> int: return maxi(0,_stock(id,item)-reserved(id,item))
func _position(id: String) -> Vector3:
	return warehouse_position if id=="warehouse" else source_by_id(id).position
func destination_for(role: String,from: Vector3) -> String:
	var best:="warehouse"; var distance:=from.distance_squared_to(warehouse_position)
	for site: ColonySite in sites.values():
		if site.built and (ColonyCatalog.WORKPLACES[site.blueprint]==role or site.blueprint=="Depot") and from.distance_squared_to(site.position)<distance:
			best=site.site_id; distance=from.distance_squared_to(site.position)
	return best
func choose_task(r: Resident,role: String) -> Dictionary:
	if role in ColonyCatalog.ZONE_ROLES:
		for area in areas:
			if not area.enabled or area.role!=role: continue
			var candidates:=area_sources(area)
			candidates.sort_custom(func(a,b): return r.position.distance_squared_to(a.position)<r.position.distance_squared_to(b.position))
			for source in candidates:
				var amount:=mini(5,available(source.source_id,source.item_id))
				if amount>0: return {"role":role,"zone":area.id,"source":source.source_id,"destination":destination_for(role,source.position),"item":source.item_id,"amount":amount}
	elif role=="Builder":
		for site: ColonySite in sites.values():
			var amount:=mini(10-int(site.inventory.get("wood",0))-reserved(site.site_id,"wood",true),mini(5,available("warehouse","wood")))
			if not site.built and amount>0: return {"role":role,"source":"warehouse","destination":site.site_id,"item":"wood","amount":amount}
	elif role=="Transporter":
		for site: ColonySite in sites.values():
			if not site.built: continue
			for item: String in site.inventory:
				var amount:=mini(5,available(site.site_id,item))
				if amount>0: return {"role":role,"source":site.site_id,"destination":"warehouse","item":item,"amount":amount}
	return {}
func _begin(id: String,task: Dictionary) -> void:
	_claim(id); task=task.duplicate(true); task.merge({"phase":"pickup","acquired":false,"elapsed":0.0,"path":[],"cursor":0},true); orders[id]=task; _plan(id,_position(task.source))
func _plan(id: String,to: Vector3) -> void:
	_plan_queue[id]=to
	var order: Dictionary=orders[id]; order.target=[to.x,to.y,to.z]; order.blocked=true; order.retry=5.0
	var r: Resident=_residents[id]; r.moving=false; r.speed=0
func _solve_plan(id: String,to: Vector3) -> void:
	var r: Resident=_residents[id]; var path:=roads.route(r.position,to); var order: Dictionary=orders[id]
	order.path=[]
	for p in path: order.path.append([p.x,p.y,p.z])
	order.cursor=0; order.target=[to.x,to.y,to.z]; order.blocked=path.is_empty(); order.retry=5.0
	r.moving=not path.is_empty(); r.status=(roads.last_error if not roads.last_error.is_empty() else "Route blocked") if path.is_empty() else "Colony · "+String(order.phase); statuses[id]=r.status
func retry_worker(id: String) -> void:
	if orders.has(id):
		var p: Array=orders[id].target; _plan(id,Vector3(p[0],p[1],p[2]))
func replan_workers() -> void:
	roads._walk_cache.clear()
	for id: String in orders: retry_worker(id)
func manual_order(id: String,at: Vector3) -> bool:
	if not _residents.has(id) or not walkable(at): return false
	if orders.has(id): message.emit("Let this resident finish carrying cargo before issuing a move order."); return false
	assign_role(id,"Unemployed",false); _claim(id)
	orders[id]={"phase":"move","acquired":false,"elapsed":0.0,"path":[],"cursor":0}; _plan(id,grounded(Vector2(at.x,at.z))); return true
func _physics_process(delta: float) -> void: tick(delta)
func tick(delta: float) -> void:
	if paused or roads==null: return
	# One bounded route build per tick; never plan 64 residents in one frame.
	if not _plan_queue.is_empty():
		var id: String=_plan_queue.keys()[0]; var target: Vector3=_plan_queue[id]; _plan_queue.erase(id)
		if orders.has(id): _solve_plan(id,target)
	for source in _sources: source.tick(delta)
	for id: String in orders.keys(): _advance_order(id,delta)
	_clock+=delta
	if _clock<.5: return
	_clock=fmod(_clock,.5)
	for id: String in assignments:
		if not assignments[id].enabled or orders.has(id): continue
		var task:=choose_task(_residents[id],assignments[id].role)
		statuses[id]="Waiting for area / stock / workplace" if task.is_empty() else "Assigned"
		if not task.is_empty(): _begin(id,task)
func _advance_order(id: String,delta: float) -> void:
	var order: Dictionary=orders[id]; var r: Resident=_residents[id]
	if order.get("blocked",false):
		order.retry-=delta; r.speed=0; r.moving=false
		if order.retry<=0: retry_worker(id)
		return
	var remaining:=delta*2.2; r.speed=2.2; r.moving=true
	while int(order.cursor)<order.path.size():
		var p: Array=order.path[order.cursor]; var to:=Vector3(p[0],p[1],p[2]); var diff:=to-r.position; var distance:=diff.length()
		if distance>remaining:
			r.forward=Vector3(diff.x,0,diff.z).normalized(); r.position+=diff.normalized()*remaining; r.distance+=remaining; return
		r.position=to; r.distance+=distance; remaining-=distance; order.cursor+=1
	r.speed=0; r.moving=false
	if order.phase=="move": _finish(id); return
	order.elapsed+=delta; r.status="Working · "+String(order.role); statuses[id]=r.status
	if order.elapsed<(4.0 if order.role=="Builder" else 2.5): return
	order.elapsed=0.0
	if order.phase=="pickup":
		if _stock(order.source,order.item)<int(order.amount): _finish(id); statuses[id]="Source empty; selecting another"; return
		_take(order.source,order.item,order.amount); order.acquired=true; order.phase="deliver"; _plan(id,_position(order.destination))
	else:
		if not _has_capacity(order.destination,order.item,order.amount):
			r.status="Destination full; holding cargo"; statuses[id]=r.status; return
		var destination: String=order.destination; var item: String=order.item; var amount:=int(order.amount)
		r.completed_tasks+=1; _finish(id); _deposit(destination,item,amount)
	changed.emit()
func _take(id: String,item: String,amount: int) -> void:
	if id=="warehouse": warehouse[item]=int(warehouse.get(item,0))-amount; return
	var node:=source_by_id(id)
	if node is ColonyResource: node.stock-=amount
	else: node.inventory[item]=int(node.inventory.get(item,0))-amount
func _has_capacity(id: String,item: String,amount: int) -> bool:
	if id=="warehouse": return economy.town("core").room_for(item)>=amount
	var stock: Dictionary=sites[id].inventory
	var mass:=0.0
	for key in stock: mass+=EconomyCatalog.mass(key)*int(stock[key])
	return mass+EconomyCatalog.mass(item)*amount<=1000.0001
func _deposit(id: String,item: String,amount: int) -> void:
	if id=="warehouse": warehouse[item]=int(warehouse.get(item,0))+amount
	else: (sites[id] as ColonySite).receive(item,amount)
func _finish(id: String) -> void:
	orders.erase(id); _plan_queue.erase(id)
	if not assignments[id].enabled: _release(id)
	statuses[id]="Idle"
func worker_cargo(id: String) -> String:
	var task: Dictionary=orders.get(id,{})
	return "%d %s"%[task.amount,task.item] if task.get("acquired",false) else "Empty"
func roster() -> Array:
	var result: Array=[]
	for id: String in _residents:
		var r: Resident=_residents[id]
		result.append({"id":id,"name":r.name,"position":r.position,"role":assignments[id].role,"enabled":assignments[id].enabled,"status":statuses.get(id,r.status),"cargo":worker_cargo(id)})
	return result
func stock_summary() -> String:
	var result:=PackedStringArray()
	for item in ["wood","berry","stone","ore","olive"]: result.append("%s %d"%[item,int(warehouse.get(item,0))])
	for item in warehouse:
		if not item in EconomyCatalog.LEGACY_ITEMS and int(warehouse[item])>0: result.append("%s %d"%[item,int(warehouse[item])])
	return " · ".join(result)
func save_state() -> Dictionary:
	var buildings: Array=[]; var resources: Array=[]; var workers: Dictionary={}
	for site: ColonySite in sites.values(): buildings.append({"id":site.site_id,"kind":site.blueprint,"position":[site.position.x,site.position.y,site.position.z],"built":site.built,"inventory":site.inventory.duplicate(true)})
	for source in _sources: resources.append({"id":source.source_id,"stock":source.stock,"renewal":source.renewal})
	for id: String in _residents:
		var r: Resident=_residents[id]; workers[id]={"position":[r.position.x,r.position.y,r.position.z],"forward":[r.forward.x,r.forward.y,r.forward.z]}
	return {"version":SAVE_VERSION,"economy":economy.save_state(),"next_id":next_id,"paused":paused,"areas":areas.duplicate(true),"roads":roads.roads.duplicate(true),"sites":buildings,"assignments":assignments.duplicate(true),"orders":orders.duplicate(true),"warehouse":warehouse.duplicate(true),"resources":resources,"workers":workers}
func _inventory_copy(value: Dictionary) -> Dictionary:
	var result: Dictionary={}
	for item in value: result[item]=int(value[item])
	return result
func _valid_inventory(value: Variant) -> bool:
	if not value is Dictionary: return false
	for item in value:
		if not EconomyCatalog.ITEMS.has(item) or not _whole(value[item],0,1000000): return false
	return true
func _whole(value: Variant,low: int,high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)==floorf(float(value)) and float(value)>=low and float(value)<=high
func _number(value: Variant,low: float,high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=low and float(value)<=high
func _vector(value: Variant) -> bool:
	return value is Array and value.size()==3 and _number(value[0],-12500,12500) and _number(value[1],-100,2000) and _number(value[2],-12500,12500)
func accepts(data: Dictionary) -> bool:
	if not _whole(data.get("version"),1,SAVE_VERSION) or not _whole(data.get("next_id"),1,1000000) or not data.get("paused") is bool: return false
	if int(data.version)==SAVE_VERSION and not economy.valid(data.get("economy")): return false
	if not _valid_inventory(data.get("warehouse")): return false
	for key in ["areas","roads","sites","resources"]:
		if not data.get(key) is Array or data[key].size()>(32 if key=="sites" else 128 if key=="resources" else 64): return false
	for key in ["assignments","orders","workers"]:
		if not data.get(key) is Dictionary or data[key].size()>_residents.size(): return false
	if data.assignments.size()!=_residents.size() or data.workers.size()!=_residents.size(): return false
	for id in data.assignments:
		var a: Variant=data.assignments[id]
		if not _residents.has(id) or not a is Dictionary or a.get("role") not in ColonyCatalog.CORE or not a.get("enabled") is bool: return false
	var ids: Dictionary={}; var zones: Dictionary={}; var destination_ids: Dictionary={"warehouse":true}; var source_items: Dictionary={}
	for source in _sources:
		if not source.source_id.begins_with("farm_"): source_items[source.source_id]=source.item_id
	for area in data.areas:
		if not area is Dictionary or not area.get("id") is String or not area.id.begins_with("zone_") or ids.has(area.id) or area.get("role") not in ColonyCatalog.ZONE_ROLES: return false
		if not area.id.trim_prefix("zone_").is_valid_int() or not _whole(int(area.id.trim_prefix("zone_")),1,int(data.next_id)-1) or not _number(area.get("x"),-12496,12496) or not _number(area.get("z"),-12496,12496) or not _number(area.get("radius"),6,32) or not area.get("enabled") is bool: return false
		ids[area.id]=true; zones[area.id]=area
	for site in data.sites:
		if not site is Dictionary or not site.get("id") is String or not site.id.begins_with("site_") or ids.has(site.id) or site.get("kind") not in ColonyCatalog.WORKPLACES or not site.get("built") is bool or not _vector(site.get("position")) or not _valid_inventory(site.get("inventory")): return false
		if not site.id.trim_prefix("site_").is_valid_int() or not _whole(int(site.id.trim_prefix("site_")),1,int(data.next_id)-1): return false
		ids[site.id]=true; destination_ids[site.id]=true
		if site.built and site.kind=="Farm": source_items["farm_"+site.id]="olive"
	var resources_seen: Dictionary={}
	for source in data.resources:
		if not source is Dictionary or not source_items.has(source.get("id")) or resources_seen.has(source.id) or not _whole(source.get("stock"),0,10000) or not _number(source.get("renewal"),0,20): return false
		resources_seen[source.id]=true
	if resources_seen.size()!=source_items.size(): return false
	for road in data.roads:
		if not road is Dictionary or road.get("kind") not in ["Road","Path"] or not road.get("points") is Array or road.points.size()<2 or road.points.size()>256: return false
		var previous: Variant=null
		for point in road.points:
			if not point is Array or point.size()!=2 or not _number(point[0],-12496,12496) or not _number(point[1],-12496,12496) or not is_zero_approx(fmod(float(point[0]),4)) or not is_zero_approx(fmod(float(point[1]),4)): return false
			if previous!=null and not is_equal_approx(Vector2(point[0]-previous[0],point[1]-previous[1]).length(),4): return false
			previous=point
	for id in data.workers:
		var r: Variant=data.workers[id]
		if not _residents.has(id) or not r is Dictionary or not _vector(r.get("position")) or not _vector(r.get("forward")): return false
	for id in data.orders:
		var o: Variant=data.orders[id]
		if not _residents.has(id) or not data.workers.has(id) or not o is Dictionary or o.get("phase") not in ["pickup","deliver","move"] or not o.get("acquired") is bool or not _number(o.get("elapsed"),0,5) or not _vector(o.get("target")): return false
		if not o.get("path") is Array or o.path.size()>1000 or not _whole(o.get("cursor"),0,o.path.size()) or not o.get("blocked") is bool or not _number(o.get("retry"),-1,5): return false
		for p in o.path:
			if not _vector(p): return false
		if o.phase=="move":
			if o.acquired: return false
			continue
		if o.get("role") not in ColonyCatalog.CORE or not _whole(o.get("amount"),1,5) or not destination_ids.has(o.get("destination")) or o.get("item") not in ["wood","berry","stone","ore","olive"]: return false
		if o.acquired!=(o.phase=="deliver"): return false
		if o.role=="Builder":
			if o.get("source")!="warehouse" or o.destination=="warehouse" or o.item!="wood": return false
		elif o.role=="Transporter":
			if o.get("source")=="warehouse" or not destination_ids.has(o.get("source")) or o.destination!="warehouse": return false
		elif not zones.has(o.get("zone")) or zones[o.zone].role!=o.role or source_items.get(o.get("source"),"")!=o.item or not ColonyCatalog.accepts(o.role,o.item): return false
	return true
func load_missing_state() -> void:
	if not _initial_state.is_empty(): load_state(_initial_state)
func load_state(data: Dictionary) -> bool:
	if data.is_empty(): return true
	if not accepts(data): return false
	_plan_queue.clear()
	for id: String in _residents: _release(id)
	for site: ColonySite in sites.values(): site.free()
	sites.clear()
	for i in range(_sources.size()-1,-1,-1):
		if _sources[i].source_id.begins_with("farm_"): _sources[i].free(); _sources.remove_at(i)
	areas=data.areas.duplicate(true); next_id=int(data.next_id); paused=data.paused; warehouse=_inventory_copy(data.warehouse); assignments=data.assignments.duplicate(true); orders=data.orders.duplicate(true)
	for record in data.sites:
		var p: Array=record.position; var site:=_create_site(record.id,record.kind,Vector3(p[0],p[1],p[2]),record.built); site.inventory=_inventory_copy(record.inventory)
	for record in data.resources:
		var source:=source_by_id(record.id) as ColonyResource; source.stock=int(record.stock); source.renewal=float(record.renewal)
	for id: String in data.workers:
		# Residents not currently managed by colony belong to the IslandLife save.
		if not assignments[id].enabled and not orders.has(id): continue
		var r: Resident=_residents[id]; var p: Array=data.workers[id].position; var f: Array=data.workers[id].forward
		r.position=Vector3(p[0],p[1],p[2]); r.forward=Vector3(f[0],f[1],f[2]); _claim(id)
	roads.roads=data.roads.duplicate(true); roads.rebuild(); redraw_areas(); statuses.clear()
	if int(data.version)==SAVE_VERSION: economy.load_state(data.economy)
	elif _initial_state.has("economy"): economy.load_state(_initial_state.economy) # v1 -> v2: a fresh economy round the saved warehouse
	else: economy.town("core")
	changed.emit(); return true
