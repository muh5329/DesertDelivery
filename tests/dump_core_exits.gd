extends Node
## Writes the core exits (the last four core roads, `Island._define_roads`) to
## world/mapgen/core_exits.json for the offline outer-world generator (world/mapgen/outer.py):
## every sample of each exit road plus its bridge spans. Run headless:
##   godot --headless --path . -- --test=dump_core_exits
const EXIT_NAMES := ["north", "east", "south", "west"]
const FIRST_EXIT := 17


func _ready() -> void:
	var t: Terrain = Game.current.world.terrain
	var out := {}
	for e in range(EXIT_NAMES.size()):
		var r := FIRST_EXIT + e
		var s: PackedVector3Array = t.road_samples[r]
		var pts := []
		for p in s: pts.append([p.x, p.y, p.z])
		var spans := []
		for b in t.bridges:
			if b.road == r: spans.append([b.from, b.to, b.deck])
		out[EXIT_NAMES[e]] = {"road": r, "points": pts, "bridges": spans}
	var path := ProjectSettings.globalize_path("res://world/mapgen/core_exits.json")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(out, " "))
	f.close()
	for k in out: print(k, " last ", out[k].points[-1], " n=", out[k].points.size(), " bridges ", out[k].bridges)
	get_tree().quit()
