extends Node
## Offline tool: writes what the minimap bake (world/mapgen/minimap.py) needs from the core island
## that only exists at runtime - its roads (1 m samples thinned to ~3 m), houses, paved courtyards
## and named places - to world/mapgen/minimap_core.json. Run after changing the core's roads:
##   godot --headless --path . -- --test=minimap_export
## then `python3 world/mapgen/minimap.py`.

func _ready() -> void:
	var g: Game = Game.current
	var island: Island = g.world.island
	var t: Terrain = g.world.terrain
	var roads := []
	var n := island.exit_roads.y if island.exit_roads.y > 0 else t.road_samples.size()
	for i in range(n):
		var r: PackedVector3Array = t.road_samples[i]
		var pts := []
		for k in range(0, r.size(), 3): pts.append([snappedf(r[k].x, 0.1), snappedf(r[k].z, 0.1)])
		pts.append([snappedf(r[-1].x, 0.1), snappedf(r[-1].z, 0.1)])
		var exit := i >= island.exit_roads.x and island.exit_roads.x >= 0
		roads.append({"class": "highway" if exit else "road", "width": 11.0 if exit else 6.0, "points": pts})
	var houses := []
	for h in island._houses: houses.append([snappedf(h.x, 0.1), snappedf(h.y, 0.1)])
	var courts := []
	for c in island._town_courtyards: courts.append([snappedf(c.x, 0.1), snappedf(c.y, 0.1), 29.0])
	var places := []
	for id in g.world.database.locations:
		var p: Vector3 = g.world.database.location_pos(id)
		if absf(p.x) > Terrain.CORE_SIZE * 0.5 or absf(p.z) > Terrain.CORE_SIZE * 0.5: continue
		places.append({"id": String(id), "name": g.world.database.location_name(id), "x": snappedf(p.x, 0.1), "z": snappedf(p.z, 0.1)})
	var out := "res://world/mapgen/minimap_core.json"
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify({"roads": roads, "houses": houses, "courtyards": courts, "places": places}))
	f.close()
	print("minimap_export: %d roads, %d houses, %d places -> %s" % [roads.size(), houses.size(), places.size(), out])
	get_tree().quit(0)
