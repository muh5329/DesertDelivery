class_name ColonyRoads
extends Node3D
## Four-metre terrain grid, matching the source colony's road strokes and route costs.
var colony: ColonySystem
var roads: Array = []
var last_error := ""
var preferences: Dictionary = {}
var mesh: MeshInstance3D
var _walk_cache: Dictionary = {}
func _ready() -> void:
	mesh = MeshInstance3D.new(); add_child(mesh)
func cell(at: Vector3) -> Vector2i:
	return Vector2i(roundi(at.x/4.0), roundi(at.z/4.0))
func point(at: Vector2i) -> Vector3:
	return colony.grounded(Vector2(at)*4.0)
func add_stroke(raw: PackedVector3Array, kind: String) -> bool:
	last_error = "Draw at least two points; maximum 64 strokes of 255 cells."
	if raw.size()<2 or roads.size()>=64 or kind not in ["Road","Path"]: return false
	var cells: Array[Vector2i] = []
	for at in raw:
		if not at.is_finite() or maxf(absf(at.x),absf(at.z))>12496:
			last_error="Route lies outside the island."; return false
		var target := cell(at)
		if cells.is_empty(): cells.append(target)
		while cells.back()!=target and cells.size()<256:
			var previous: Vector2i = cells.back()
			var diff := target-previous
			cells.append(previous+(Vector2i(signi(diff.x),0) if absi(diff.x)>absi(diff.y) else Vector2i(0,signi(diff.y))))
	if cells.size()<2 or cells.size()>=256:
		last_error="Draw a shorter connected route."; return false
	var previous := point(cells[0])
	for c in cells:
		var p := point(c)
		if not colony.walkable(p) or absf(p.y-previous.y)>2:
			last_error="Route crosses water, an obstacle or a steep slope."; return false
		previous=p
	var points: Array = []
	for c in cells: points.append([c.x*4,c.y*4])
	roads.append({"kind":kind,"points":points}); rebuild(); colony.replan_workers(); colony.changed.emit()
	return true
func erase_at(at: Vector3) -> bool:
	for i in range(roads.size()-1,-1,-1):
		for p in roads[i].points:
			if Vector2(p[0]-at.x,p[1]-at.z).length()<4:
				roads.remove_at(i); rebuild(); colony.replan_workers(); colony.changed.emit(); return true
	return false
func rebuild() -> void:
	_walk_cache.clear()
	preferences.clear()
	var st:=SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count:=0
	for road in roads:
		for p in road.points:
			var c:=cell(Vector3(p[0],0,p[1]))
			preferences[c]=minf(float(preferences.get(c,4)),1.0 if road.kind=="Road" else 1.6)
		for i in range(road.points.size()-1):
			var a:=Vector2(road.points[i][0],road.points[i][1]); var b:=Vector2(road.points[i+1][0],road.points[i+1][1])
			var side:=Vector2(-(b-a).y,(b-a).x).normalized()*(1.5 if road.kind=="Road" else .85)
			for p in [a-side,a+side,b+side,a-side,b+side,b-side]:
				st.set_normal(Vector3.UP); st.set_color(Color("d1b482") if road.kind=="Road" else Color("a99a77")); st.add_vertex(colony.grounded(p)+Vector3.UP*.08); count+=1
	if mesh:
		mesh.mesh=st.commit() if count>0 else null
		var mat:=StandardMaterial3D.new(); mat.vertex_color_use_as_albedo=true; mat.cull_mode=BaseMaterial3D.CULL_DISABLED; mesh.material_override=mat
func route(from: Vector3, to: Vector3) -> PackedVector3Array:
	if _walk_cache.size()>16000: _walk_cache.clear()
	var a:=cell(from); var b:=cell(to)
	if maxi(absi(a.x-b.x),absi(a.y-b.y))>64:
		last_error="Colony routes are local (256 m). Use a closer workplace or resident."; return PackedVector3Array()
	var lo:=Vector2i(mini(a.x,b.x)-8,mini(a.y,b.y)-8)
	var hi:=Vector2i(maxi(a.x,b.x)+8,maxi(a.y,b.y)+8)
	var grid:=AStarGrid2D.new(); grid.region=Rect2i(lo,hi-lo+Vector2i.ONE); grid.cell_size=Vector2.ONE*4
	grid.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_NEVER; grid.default_compute_heuristic=AStarGrid2D.HEURISTIC_MANHATTAN; grid.update()
	for x in range(lo.x,hi.x+1):
		for z in range(lo.y,hi.y+1):
			var c:=Vector2i(x,z); var p:=point(c)
			if not _walk_cache.has(c):
				var valid:=p.y>=.2 and maxf(absf(p.x),absf(p.z))<=12496
				for d in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
					if absf(point(c+d).y-p.y)>2.5: valid=false
				_walk_cache[c]=valid
			grid.set_point_solid(c,not _walk_cache[c])
			grid.set_point_weight_scale(c,float(preferences.get(c,4.0)))
	if grid.is_point_solid(a) or grid.is_point_solid(b): return PackedVector3Array()
	# Physics is queried only along candidate routes, never for every grid cell.
	# A discovered obstacle removes that cell and A* searches an alternate path.
	var checked: Dictionary = {}
	for attempt in range(16):
		var ids:=grid.get_id_path(a,b)
		if ids.is_empty(): return PackedVector3Array()
		var blocked:=false
		var previous:=from
		for c in ids:
			if not checked.has(c): checked[c]=colony.walkable(point(c))
			if not checked[c] or not colony.segment_clear(previous,point(c)):
				grid.set_point_solid(c,true); blocked=true
			previous=point(c)
		if blocked: continue
		var path:=PackedVector3Array()
		for c in ids: path.append(point(c))
		if not colony.walkable(to) or not colony.segment_clear(path[-1],to): return PackedVector3Array()
		path.append(to)
		return path
	last_error="Route blocked. Draw a path around the obstacle or retry closer."
	return PackedVector3Array()
