class_name IslandWildlife
extends Node3D
## Deterministic habitats, grazing cycles, gull flocks and water-validated sailing circuits.
var world: WorldManager
var entities: EntityManager
var elapsed := 0.0
var creatures: Array[Dictionary] = []
var boats: Array[Dictionary] = []
var _pool: ViewPool
var _views: Dictionary:
	get: return _pool.views
var _rng := RandomNumberGenerator.new()
var _tick := 0.0

func setup(p_world: WorldManager, p_entities: EntityManager) -> void:
	world=p_world; entities=p_entities; _rng.seed=19517
	_pool=ViewPool.new(entities,&"wildlife",_build_view)
	_pool.keep_margin=world.config.view_keep_margin
	# Gulls are visible from much further off than a rabbit is.
	var bird_radius: float=world.config.bird_view_radius
	var ground_radius: float=world.config.wildlife_view_radius
	_pool.radius_for=func(r: Dictionary) -> float: return bird_radius if r.kind=="gull" else ground_radius
	var habitats := [
		["sheep",20,Vector2(-265,-253),55.0],
		["deer",14,Vector2(-235,-100),160.0],
		["rabbit",24,Vector2(-330,25),150.0],
		["dog",8,Vector2(189,-156),42.0],
		["rabbit",12,Vector2(-160,433),80.0],
	]
	for habitat in habitats:
		var count := 0
		for attempt in range(2500):
			if count>=habitat[1]: break
			var centre: Vector2=habitat[2]+Vector2(_rng.randf_range(-1,1),_rng.randf_range(-1,1))*float(habitat[3])
			if not _safe_habitat(centre,4.5): continue
			var r := {"id":"wildlife.%s.%d" % [habitat[0],creatures.size()],"kind":habitat[0],"centre":centre,"radius":_rng.randf_range(1.4,4.2),"phase":_rng.randf()*TAU,"position":Vector3.ZERO,"yaw":0.0,"moving":false}
			creatures.append(r); count+=1
	for i in range(30):
		var centre:=Vector2(185,-156) if i<15 else Vector2(-350,435)
		creatures.append({"id":"wildlife.gull.%d"%i,"kind":"gull","centre":centre,"radius":_rng.randf_range(15,85),"phase":_rng.randf()*TAU,"position":Vector3.ZERO,"yaw":0.0,"moving":true,"altitude":_rng.randf_range(14,34)})
	for i in range(6):
		var candidates := [Vector2(-490,400),Vector2(245,-105),Vector2(-520,60),Vector2(-480,485),Vector2(450,5),Vector2(300,-110)]
		var path:=_water_loop(candidates[i])
		if path.is_empty(): continue
		var boat:=IslandArt.instantiate("fishing_boat"); boat.name="SailingLaunch%d"%i
		add_child(boat)
		boats.append({"node":boat,"path":path,"phase":float(i)*.17})
	_update_creatures()
	print("[life] %d animals and birds, %d sailing boats" % [creatures.size(),boats.size()])

func _safe_habitat(centre: Vector2, radius: float) -> bool:
	for i in range(9):
		var p:=centre+Vector2.from_angle(i*TAU/8)*radius if i<8 else centre
		if world.terrain.height_at(p.x,p.y)<1.0 or world.terrain.normal_at(p.x,p.y).y<.91 or world.terrain.road_dist_at(p.x,p.y)<5.5: return false
	return true

func _water_loop(near: Vector2) -> PackedVector3Array:
	for attempt in range(160):
		var centre:=near+Vector2(_rng.randf_range(-45,45),_rng.randf_range(-45,45))
		var path:=PackedVector3Array()
		var radius:=_rng.randf_range(12,30)
		var valid:=true
		for i in range(64):
			var p:=centre+Vector2.from_angle(i*TAU/64)*radius
			if world.terrain.height_at(p.x,p.y)>-2.0 or world.terrain.road_dist_at(p.x,p.y)<12:
				valid=false; break
			path.append(Vector3(p.x,0,p.y))
		if valid: return path
	return PackedVector3Array()

func _process(delta: float) -> void:
	if world==null or entities.focus==null: return
	elapsed+=delta; _tick+=delta
	if _tick>.3:
		_tick=0; _update_creatures(); _sync_views()
	for r in creatures:
		var node: Node3D=_pool.view(r.id)
		if node==null: continue
		var limbs: Array=node.get_meta("limbs",[])
		var head: Node3D=node.get_meta("head",null)
		node.position=node.position.lerp(r.position,clampf(delta*8,0,1))
		node.rotation.y=lerp_angle(node.rotation.y,r.yaw,clampf(delta*5,0,1))
		if r.kind=="gull":
			for wing in limbs:
				wing.rotation.z=sin(elapsed*5+r.phase)*.38*(1 if String(wing.name).begins_with("WingL") else -1)
		else:
			for i in range(limbs.size()):
				limbs[i].rotation.x=sin(elapsed*5+r.phase+i*PI)*(.27 if r.moving else .0)
			if head:
				head.rotation.x=.47+sin(elapsed*.7+r.phase)*.13 if not r.moving else .0
	for b in boats:
		var u: float=fposmod(elapsed*.014+b.phase,1.0)*b.path.size()
		var index:=floori(u)
		var p: Vector3=b.path[index].lerp(b.path[(index+1)%b.path.size()],u-index)
		var forward: Vector3=(b.path[(index+1)%b.path.size()]-b.path[index]).normalized()
		b.node.position=p+Vector3(0,sin(elapsed*1.5+b.phase)*.08,0)
		b.node.rotation=Vector3(sin(elapsed*.8)*.025,atan2(-forward.x,-forward.z),sin(elapsed*1.1+b.phase)*.06)
		b.node.visible=entities.focus.global_position.distance_to(p)<420

func _update_creatures() -> void:
	for r in creatures:
		var angle: float=r.phase+elapsed*(.085 if r.kind=="gull" else .028)
		var p: Vector2=r.centre+Vector2.from_angle(angle)*r.radius
		var y:=world.terrain.height_at(p.x,p.y)
		if r.kind=="gull": y=maxf(y,0)+float(r.altitude)
		# Graze for half of each cycle, then walk. Integrate a paused angle so transitions never jump.
		if r.kind!="gull":
			var cycle:=fposmod(elapsed+r.phase*7,24.0)
			r.moving=cycle<12
			var walked: float=floor((elapsed+r.phase*7)/24.0)*12+minf(cycle,12)
			angle=r.phase+walked*.065
			p=r.centre+Vector2.from_angle(angle)*r.radius
			y=world.terrain.height_at(p.x,p.y)
		r.position=Vector3(p.x,y+.03,p.y)
		r.yaw=-angle

func _build_view(r: Dictionary) -> Node3D:
	var node: Node3D=IslandArt.instantiate(r.kind)
	node.position=r.position
	var limbs: Array[Node3D]=[]
	for child in node.find_children("*","Node3D",true,false):
		if child is MeshInstance3D: continue
		if String(child.name).begins_with("AnimalLeg") or String(child.name).begins_with("Wing"): limbs.append(child)
	node.set_meta("limbs",limbs)
	node.set_meta("head",node.find_child("AnimalHead*",true,false))
	return node

func _sync_views() -> void:
	_pool.sync(creatures,entities.focus.global_position)
