extends Node
## Dumps the road network (every 4th sample), bridges and locations to JSON for offline tools.
func _ready() -> void:
	var g: Game = Game.current
	var t: Terrain = g.world.terrain
	var roads := []
	for r in t.road_samples:
		var pts := []
		for k in range(0, r.size(), 4): pts.append([snappedf(r[k].x,.01), snappedf(r[k].y,.01), snappedf(r[k].z,.01)])
		pts.append([r[-1].x, r[-1].y, r[-1].z])
		roads.append(pts)
	var locs := {}
	for id in g.world.database.locations: 
		var p: Vector3 = g.world.database.locations[id].pos
		locs[String(id)] = [p.x, p.y, p.z]
	var f := FileAccess.open(g.cli.get_string("out", "/tmp/roads.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"roads": roads, "locations": locs}))
	f.close()
	print("dumped ", roads.size(), " roads")
	get_tree().quit()
