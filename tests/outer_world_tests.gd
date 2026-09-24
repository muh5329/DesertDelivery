extends Node
## The outer world (world/outer, data/outer, ADR 0010): data, ground/collision agreement, the
## collision tile budget, the road network (junctions link, the core reaches every town), towns
## and hamlets as locations, plot layout rules, streaming budgets.
## Run: godot --headless --path . -- --test=outer_world_tests

var game: Game
var outer: OuterWorld
var fails := 0
var passes := 0
var focus: Node3D


func _check(cond: bool, label: String) -> void:
	print(("  PASS " if cond else "  FAIL ") + label)
	if cond: passes += 1
	else: fails += 1


func _ready() -> void:
	game = Game.current
	outer = game.world.outer
	await get_tree().process_frame
	await _run()
	print("OUTER WORLD TESTS: %d passed, %d failed" % [passes, fails])
	get_tree().quit(1 if fails > 0 else 0)


func _ray(p: Vector3, up := 60.0, down := 60.0) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * up, p - Vector3.UP * down, 1)
	return get_viewport().get_world_3d().direct_space_state.intersect_ray(q)


func _settle(n := 3) -> void:
	for i in n: await get_tree().physics_frame


func _run() -> void:
	var t: Terrain = game.world.terrain
	var g := outer.ground
	var plan := g.plan
	# ---------------------------------------------------------------- data
	_check(outer.ok and g.heights.size() == OuterGround.N * OuterGround.N, "outer heightfield loaded (%d samples)" % g.heights.size())
	_check(plan.get("towns", []).size() == 5, "five towns in the plan")
	_check(plan.get("hamlets", []).size() >= 10 and plan.hamlets.size() <= 16, "10-16 hamlets (%d)" % plan.get("hamlets", []).size())
	_check(outer.roads.total_km >= 150.0 and outer.roads.total_km <= 250.0, "road network 150-250 km (%.1f km)" % outer.roads.total_km)
	_check(plan.get("sea_lanes", []).size() >= 3 and plan.get("ports", []).size() >= 4, "sea lanes (%d) and ports (%d)" % [plan.sea_lanes.size(), plan.ports.size()])
	var bandits := 0; var pirates := 0
	for c in plan.get("camps", []):
		if c.kind == "bandit": bandits += 1
		elif c.kind == "pirate": pirates += 1
	_check(bandits >= 8 and bandits <= 12 and pirates >= 3 and pirates <= 5, "camp candidates: %d bandit, %d pirate" % [bandits, pirates])
	_check(outer.load_ms_total() < 4000, "outer world boots quickly (%d ms)" % outer.load_ms_total())
	# ---------------------------------------------------------------- extent and ground
	_check(Terrain.SIZE == 25000.0 and Terrain.CORE_SIZE == 1248.0, "25 km world round the 1248 m core")
	_check(outer.height_at(12600.0, 0.0) < -30.0 and outer.height_at(0.0, -12600.0) < -30.0, "beyond the world edge is deep sea")
	_check(is_equal_approx(t.height_at(3000.0, -2000.0), outer.height_at(3000.0, -2000.0)), "Terrain forwards queries outside the core to the outer world")
	var lagoon := outer.height_at(900.0, 0.0)
	_check(lagoon < -2.0, "the lagoon round the core is sea (%.1f m at 900 m)" % lagoon)
	var peak := -INF
	for p in [Vector2(1200, -8600), Vector2(-600, -8200), Vector2(3300, -8000), Vector2(0, -9000)]:
		for dz in range(-800, 801, 100):
			for dx in range(-800, 801, 100): peak = maxf(peak, outer.height_at(p.x + dx, p.y + dz))
	_check(peak > 850.0 and peak < 1400.0, "alpine peaks in the north (%.0f m)" % peak)
	_check(outer.biome_at(-40.0 + 12000.0, 0.0) == Terrain.Biome.SEA, "biome_at answers SEA offshore")
	var n := outer.normal_at(4000.0, -3000.0)
	_check(n.y > 0.0 and absf(n.length() - 1.0) < 0.001, "normal_at is a unit upward normal")
	# lattice identity: the surface interpolates its lattice points exactly
	var x0 := -12500.0 + 1000 * 6.25; var z0 := -12500.0 + 1500 * 6.25
	_check(absf(outer.height_at(x0, z0) - g.lattice(1000, 1500)) < 1e-4, "height_at hits the lattice at lattice points")
	# ---------------------------------------------------------------- collision == height_at
	focus = Node3D.new(); add_child(focus)
	outer.focus = focus
	var remote := [Vector3(-4200, 0, -4200), Vector3(6000, 0, 5200), Vector3(-9000, 0, 1600), Vector3(1500, 0, -7200), Vector3(9000, 0, -2000)]
	for p: Vector3 in remote:
		focus.global_position = p
		outer.refresh_collision()
		_check(outer.loaded.size() <= 25, "collision tiles bounded after teleport to %s (%d)" % [p, outer.loaded.size()])
		await _settle()
		var worst := 0.0; var misses := 0
		for k in range(12):
			var q := p + Vector3(k * 13.37 - 70.0, 0, k * 7.91 - 40.0)
			var y := outer.height_at(q.x, q.z)
			var hit := _ray(Vector3(q.x, y, q.z))
			if hit.is_empty(): misses += 1; continue
			if hit.collider is StaticBody3D and String(hit.collider.name).begins_with("Ground_"):
				worst = maxf(worst, absf(hit.position.y - y))
		_check(misses == 0 and worst < 0.02, "physics rays match height_at near %s (worst %.3f m)" % [p, worst])
	# on a highway and on a bridge deck
	var hw: Dictionary = {}; var br: Dictionary = {}
	for e in outer.roads.roads:
		if e.cls == "highway" and hw.is_empty() and (e.bridges as Array).is_empty(): hw = e
		if br.is_empty() and not (e.bridges as Array).is_empty() and int(e.bridges[0][1]) - int(e.bridges[0][0]) > 40: br = e
	var hp: Vector3 = (hw.pts as PackedVector3Array)[(hw.pts as PackedVector3Array).size() / 2]
	focus.global_position = hp; outer.refresh_collision(); await _settle()
	var hh := _ray(hp)
	_check(not hh.is_empty() and absf(hh.position.y - hp.y) < 0.03, "a highway sample lies on the collided ground (%s)" % (str(absf(hh.position.y - hp.y)) if not hh.is_empty() else "no hit"))
	_check(absf(outer.height_at(hp.x, hp.z) - hp.y) < 0.03, "highway samples sit on height_at")
	var mid := (int(br.bridges[0][0]) + int(br.bridges[0][1])) / 2
	var bp: Vector3 = (br.pts as PackedVector3Array)[mid]
	focus.global_position = bp; outer.refresh_collision(); await _settle()
	var bh := _ray(bp, 5.0, 40.0)
	_check(not bh.is_empty() and absf(bh.position.y - bp.y) < 0.05, "bridge deck %s collides at its profile height (%s)" % [br.id, str(bh.position.y - bp.y) if not bh.is_empty() else "no hit"])
	# ships pass under every bridge that crosses a sea lane with >= 12 m to spare
	var low := 0; var crossings := 0
	for e in outer.roads.roads:
		var P: PackedVector3Array = e.pts
		for span in e.bridges:
			for k in range(int(span[0]), int(span[1]) + 1, 2):
				if outer.height_at(P[k].x, P[k].z) > -1.0: continue
				for l in plan.sea_lanes:
					var pts: Array = l.points
					for s in range(pts.size() - 1):
						var a := Vector2(pts[s][0], pts[s][1]); var b := Vector2(pts[s + 1][0], pts[s + 1][1])
						if Geometry2D.get_closest_point_to_segment(Vector2(P[k].x, P[k].z), a, b).distance_to(Vector2(P[k].x, P[k].z)) < 20.0:
							crossings += 1
							if P[k].y < 12.0: low += 1
	_check(low == 0, "decks over sea lanes clear 12 m (%d lane crossings, %d low)" % [crossings, low])
	# ---------------------------------------------------------------- the road network
	var roads := outer.roads
	var registered := 0
	for e in roads.roads:
		if e.nav >= 0: registered += 1
	_check(registered == plan.roads.size() and t.road_samples.size() >= roads.nav_first + registered, "every plan road is in Terrain.road_samples (%d)" % registered)
	var bad_join := 0; var joins := 0
	for e in roads.roads:
		for end in ["join", "join_end"]:
			var j: Dictionary = e.get(end, {})
			if j.is_empty(): continue
			joins += 1
			var parent: Dictionary = roads.roads[roads.by_id[j.road]]
			var P: PackedVector3Array = parent.pts
			var q: Vector3 = (e.pts as PackedVector3Array)[0 if end == "join" else (e.pts as PackedVector3Array).size() - 1]
			var k: int = j.index
			if q.distance_to(P[k]) > 0.02 or (k % 3 != 0 and k != P.size() - 1): bad_join += 1
	_check(joins > 20 and bad_join == 0, "branches end exactly on a navigation sample of their parent (%d joins, %d bad)" % [joins, bad_join])
	var nav := game.life.navigation if game.life else null
	if nav == null:
		nav = RoadNavigation.new(); nav.build(t)
	var core_id := nav.nearest(game.world.database.location_pos(&"villa_rosa_office"))
	for town in plan.towns:
		var pz := Vector3(town.plaza[0], town.plaza[1], town.plaza[2])
		var tid := nav.nearest(pz)
		var path := nav.graph.get_id_path(core_id, tid)
		var near := nav.graph.get_point_position(tid).distance_to(pz)
		_check(path.size() > 10 and near < 40.0, "the road graph connects the core to %s (%d nodes, plaza %.0f m off)" % [town.id, path.size(), near])
	var reached := 0
	for hm in plan.hamlets:
		var pz := Vector3(hm.plaza[0], hm.plaza[1], hm.plaza[2])
		if nav.graph.get_id_path(core_id, nav.nearest(pz)).size() > 10: reached += 1
	_check(reached == plan.hamlets.size(), "every hamlet is reachable by road (%d / %d)" % [reached, plan.hamlets.size()])
	var nr := t.nearest_road(Vector3(5400, 0, -7900))
	_check(nr.point.distance_to(Vector3(5400, nr.point.y, -7900)) < 6000.0 and nr.point != Vector3(5400, 0, -7900), "nearest_road answers far from the core (%.0f m away)" % nr.point.distance_to(Vector3(5400, nr.point.y, -7900)))
	_check(outer.roads.bridge_count >= 8, "bridges built (%d)" % outer.roads.bridge_count)
	# ---------------------------------------------------------------- towns and hamlets
	var db := game.world.database
	var missing := []
	for group in ["towns", "hamlets"]:
		for town in plan[group]:
			if not db.locations.has(StringName(town.id)): missing.append(town.id)
	_check(missing.is_empty(), "towns and hamlets are named locations (%s missing)" % [missing])
	var counts := {}
	for town in plan.towns: counts[town.id] = town.plots.size()
	_check(counts.get("puerto_alto", 0) >= 400 and counts.puerto_alto <= 700, "Puerto Alto has 400-700 plots (%d)" % counts.get("puerto_alto", 0))
	_check(counts.get("valdoro", 0) >= 120 and counts.valdoro <= 200, "Valdoro 120-200 plots (%d)" % counts.get("valdoro", 0))
	_check(counts.get("sarmada", 0) >= 200 and counts.sarmada <= 350, "Sarmada 200-350 plots (%d)" % counts.get("sarmada", 0))
	_check(counts.get("isola_serena", 0) >= 100 and counts.isola_serena <= 160, "Isola Serena 100-160 plots (%d)" % counts.get("isola_serena", 0))
	_check(counts.get("campo_real", 0) >= 200 and counts.campo_real <= 300, "Campo Real 200-300 plots (%d)" % counts.get("campo_real", 0))
	var overlaps := 0; var on_streets := 0; var floating := 0; var total := 0
	for group in ["towns", "hamlets"]:
		for town in plan[group]:
			var r := _plot_rules(town)
			overlaps += r.x; on_streets += r.y; floating += r.z; total += town.plots.size()
	_check(overlaps == 0, "plots never overlap each other (%d of %d)" % [overlaps, total])
	_check(on_streets == 0, "plots never overlap streets (%d)" % on_streets)
	_check(floating == 0, "every plot's y is its ground (the runtime surface) (%d off)" % floating)
	var styles_ok := true
	for town in plan.towns:
		for p in town.plots:
			if p.style != town.style or not (p.kind in ["house", "rowhouse", "shop", "warehouse", "palazzo", "tower", "church", "market_hall", "town_hall", "barn", "granary", "windmill", "lighthouse", "boathouse", "citadel", "gate", "wall"]): styles_ok = false
	_check(styles_ok, "plot style and kind follow the architecture-kit contract")
	# ---------------------------------------------------------------- streaming of a town
	var pa: Array = plan.towns[0].plaza
	var ppos := Vector3(pa[0], pa[1], pa[2])
	game.bike.place(ppos + Vector3(0, 1.0, 0), Vector3.FORWARD)
	game.world.set_focus(game.bike)
	game.world.streamer.load_all_pending()
	await _settle(2)
	var built := 0
	for c in game.world.streamer.loaded.values():
		built += c.find_children("PlaceholderBuildings", "MeshInstance3D", true, false).size()
		built += c.find_children("Plots*", "", true, false).size()
		built += c.find_children("Buildings", "MeshInstance3D", true, false).size()      # BuildingKit
	_check(built > 3, "town plots are built by the streamer near %s (%d groups)" % [plan.towns[0].id, built])
	var hidden := 0
	for c in game.world.streamer.loaded.keys():
		if outer.towns.lod_cells.has(c) and not outer.towns.lod_cells[c].visible: hidden += 1
	_check(hidden > 0, "far silhouettes hide where the real buildings are loaded (%d)" % hidden)
	# ---------------------------------------------------------------- wilderness budget
	var cam := Camera3D.new(); add_child(cam); cam.current = true
	cam.global_position = Vector3(-3000, outer.height_at(-3000, -4500) + 2.0, -4500)
	outer.flora.flush()
	var fs: Dictionary = outer.flora.stats()
	_check(fs.instances > 500, "remote land receives vegetation (%d instances)" % fs.instances)
	_check(fs.tiles <= fs.max_tiles and fs.instances <= fs.max_instances, "wilderness stays within its tile / instance budget (%d tiles, %d instances)" % [fs.tiles, fs.instances])
	var key: Vector2i = outer.flora.loaded.keys()[0]
	var sig_a := _signature(outer.flora.loaded[key])
	outer.flora.loaded[key].free(); outer.flora.loaded.erase(key); outer.flora.build_tile(key)
	_check(sig_a == _signature(outer.flora.loaded[key]), "a rebuilt wilderness tile is identical (deterministic)")
	outer.roads.flush()
	_check(outer.roads.loaded.size() <= (2 * OuterRoads.RADIUS + 3) * (2 * OuterRoads.RADIUS + 3), "road ribbon tiles bounded (%d)" % outer.roads.loaded.size())


## Overlaps between plots, plots over streets, plots whose y is not their ground.
func _plot_rules(town: Dictionary) -> Vector3i:
	var cells := {}
	var polys := []
	for p in town.plots:
		var poly := _poly(p)
		polys.append(poly)
		var bb := _bbox(poly)
		for j in range(floori(bb.position.y / 24.0), floori(bb.end.y / 24.0) + 1):
			for i in range(floori(bb.position.x / 24.0), floori(bb.end.x / 24.0) + 1):
				var k := Vector2i(i, j)
				if not cells.has(k): cells[k] = []
				cells[k].append(polys.size() - 1)
	var overlaps := 0
	var seen := {}
	for k in cells:
		var l: Array = cells[k]
		for a in range(l.size()):
			for b in range(a + 1, l.size()):
				var key := Vector2i(mini(l[a], l[b]), maxi(l[a], l[b]))
				if seen.has(key): continue
				seen[key] = true
				if _sat(polys[l[a]], polys[l[b]]): overlaps += 1
	var on_streets := 0
	for st in town.streets:
		var pts: Array = st.points
		var half: float = float(st.width) * 0.5 - 0.05
		for s in range(pts.size() - 1):
			var a := Vector2(pts[s][0], pts[s][2]); var b := Vector2(pts[s + 1][0], pts[s + 1][2])
			var sb := Rect2(a, Vector2.ZERO).expand(b).grow(half + 1.0)
			for j in range(floori(sb.position.y / 24.0), floori(sb.end.y / 24.0) + 1):
				for i in range(floori(sb.position.x / 24.0), floori(sb.end.x / 24.0) + 1):
					for idx in cells.get(Vector2i(i, j), []):
						if town.plots[idx].kind == "gate": continue       # a gate arches over its street by design
						if _seg_poly_dist(a, b, polys[idx]) < half: on_streets += 1
	var floating := 0
	for i in range(town.plots.size()):
		var p: Dictionary = town.plots[i]
		var poly: PackedVector2Array = polys[i]
		var top := -INF
		for q in poly: top = maxf(top, outer.height_at(q.x, q.y))
		for e in range(4):
			var m: Vector2 = (poly[e] + poly[(e + 3) % 4]) * 0.5
			top = maxf(top, outer.height_at(m.x, m.y))
		top = maxf(top, outer.height_at(p.x, p.z))
		if absf(top - float(p.y)) > 0.35:
			floating += 1
			print("    plot %s y %.2f ground %.2f" % [p.id, float(p.y), top])
	return Vector3i(overlaps, on_streets, floating)


func _poly(p: Dictionary) -> PackedVector2Array:
	var yaw := deg_to_rad(float(p.yaw))
	var f := Vector2(sin(yaw), cos(yaw)); var t := Vector2(f.y, -f.x)
	var c := Vector2(p.x, p.z); var hw := float(p.w) * 0.5; var hd := float(p.d) * 0.5
	return PackedVector2Array([c + t * hw + f * hd, c - t * hw + f * hd, c - t * hw - f * hd, c + t * hw - f * hd])


func _bbox(poly: PackedVector2Array) -> Rect2:
	var r := Rect2(poly[0], Vector2.ZERO)
	for q in poly: r = r.expand(q)
	return r


func _sat(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	for poly in [a, b]:
		for k in range(4):
			var e: Vector2 = poly[(k + 1) % 4] - poly[k]
			var ax := Vector2(-e.y, e.x).normalized()
			var amin := INF; var amax := -INF; var bmin := INF; var bmax := -INF
			for q in a: var d := q.dot(ax); amin = minf(amin, d); amax = maxf(amax, d)
			for q in b: var d := q.dot(ax); bmin = minf(bmin, d); bmax = maxf(bmax, d)
			if amax <= bmin + 0.1 or bmax <= amin + 0.1: return false
	return true


func _seg_poly_dist(a: Vector2, b: Vector2, poly: PackedVector2Array) -> float:
	if Geometry2D.is_point_in_polygon(a, poly) or Geometry2D.is_point_in_polygon(b, poly): return 0.0
	var best := INF
	for k in range(4):
		var c: Vector2 = poly[k]; var d: Vector2 = poly[(k + 1) % 4]
		if Geometry2D.segment_intersects_segment(a, b, c, d) != null: return 0.0
		best = minf(best, Geometry2D.get_closest_point_to_segment(c, a, b).distance_to(c))
		best = minf(best, Geometry2D.get_closest_point_to_segment(a, c, d).distance_to(a))
		best = minf(best, Geometry2D.get_closest_point_to_segment(b, c, d).distance_to(b))
	return best


func _signature(node: Node3D) -> int:
	var sig: Array = []
	for v in node.get_children():
		if v is MultiMeshInstance3D:
			var mm: MultiMesh = v.multimesh
			sig.append(mm.instance_count)
			for i in range(mini(6, mm.instance_count)):
				sig.append(mm.get_instance_transform(i)); sig.append(mm.get_instance_color(i))
	return hash(sig)
