class_name RoadNavigation
extends RefCounted
## Road topology survives streaming. Cross-road links are only allowed at nearby,
## same-level intersections; parallel samples cannot shortcut across a bend.
var graph := AStar3D.new()
var buckets: Dictionary = {}
var road_ids: Dictionary = {}
var bridge_segments: Array[Dictionary] = []
var bridge_buckets: Dictionary = {}
const CELL := 4.0

func build(terrain: Terrain) -> void:
	graph.clear(); buckets.clear(); road_ids.clear(); bridge_segments.clear(); bridge_buckets.clear()
	for road_index in terrain.road_samples.size():
		var samples: PackedVector3Array = terrain.road_samples[road_index]
		var previous := -1
		for index in samples.size():
			if index % 3 != 0 and index != samples.size()-1: continue
			var p: Vector3 = samples[index]
			var id := graph.get_available_point_id()
			graph.add_point(id,p); road_ids[id]=road_index
			if previous >= 0: graph.connect_points(previous,id)
			previous=id
			var cell := Vector2i(floori(p.x/CELL),floori(p.z/CELL))
			for dx in range(-1,2):
				for dz in range(-1,2):
					for other in buckets.get(cell+Vector2i(dx,dz),[]):
						var q := graph.get_point_position(other)
						if road_ids[other] != road_index and p.distance_to(q)<3.8 and absf(p.y-q.y)<1.2:
							graph.connect_points(id,other)
			if not buckets.has(cell): buckets[cell]=[]
			buckets[cell].append(id)
	for bridge in terrain.bridges:
		var samples: PackedVector3Array=bridge.samples
		var span:=bridge.deck_span(terrain)
		for i in range(span.x,mini(span.y,samples.size()-1)):
			var segment: Dictionary={"a":samples[i],"b":samples[i+1]}
			bridge_segments.append(segment)
			var a: Vector3=samples[i]; var b: Vector3=samples[i+1]
			for x in range(floori((minf(a.x,b.x)-3)/8),floori((maxf(a.x,b.x)+3)/8)+1):
				for z in range(floori((minf(a.z,b.z)-3)/8),floori((maxf(a.z,b.z)+3)/8)+1):
					var cell:=Vector2i(x,z)
					if not bridge_buckets.has(cell): bridge_buckets[cell]=[]
					bridge_buckets[cell].append(segment)

func nearest(p: Vector3) -> int:
	return graph.get_closest_point(p)

func support(p: Vector3, terrain: Terrain) -> Dictionary:
	var height := terrain.height_at(p.x,p.z)
	var normal := terrain.normal_at(p.x,p.z)
	# Elevate only over a real deck, never because a nearby road is uphill.
	for segment in bridge_buckets.get(Vector2i(floori(p.x/8),floori(p.z/8)),[]):
		var a: Vector3=segment.a; var b: Vector3=segment.b
		var ab := Vector2(b.x-a.x,b.z-a.z)
		var t := clampf(Vector2(p.x-a.x,p.z-a.z).dot(ab)/maxf(ab.length_squared(),.001),0,1)
		var closest := a.lerp(b,t)
		if Vector2(p.x-closest.x,p.z-closest.z).length()<2.32 and closest.y>height:
			height=closest.y
			var forward := (b-a).normalized()
			normal=forward.cross(Vector3.UP).cross(forward).normalized()
	return {"height":height,"normal":normal}

func path(from: Vector3, to: Vector3, lane: float, terrain: Terrain) -> PackedVector3Array:
	var a := nearest(from); var b := nearest(to)
	if a<0 or b<0: return PackedVector3Array()
	var centre := graph.get_point_path(a,b)
	if centre.is_empty(): return centre
	var result := PackedVector3Array([from])
	for i in centre.size():
		var tangent := centre[mini(i+1,centre.size()-1)]-centre[maxi(i-1,0)]
		tangent.y=0
		if tangent.length_squared()<.01: tangent=terrain.nearest_road(centre[i]).tangent
		# Pedestrians stay on the deck inside its parapets when crossing water.
		var ground := terrain.height_at(centre[i].x,centre[i].z)
		var offset := minf(lane,1.95) if centre[i].y-ground>.4 else lane
		var p := centre[i]+tangent.normalized().cross(Vector3.UP)*offset
		p.y=support(p,terrain).height
		if p.distance_to(result[-1])>.12: result.append(p)
	# Traffic finishes in its lane. People must reach the actual activity station.
	if lane>2.0:
		var destination:=to
		destination.y=support(destination,terrain).height
		if destination.distance_to(result[-1])>.001: result.append(destination)
	return result
