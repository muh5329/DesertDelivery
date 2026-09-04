extends Node
## Prints the elevated stretches the terrain found and the profile of one road.
## Run: ROAD=n godot --headless --path . -- --test=road_dump
func _ready() -> void:
	var t: Terrain = Game.current.world.terrain
	for b in t.bridges:
		var s: PackedVector3Array = t.road_samples[b.road]
		print("bridge road=%d from=%d to=%d deck=%.1f  a=%s b=%s" % [b.road, b.from, b.to, b.deck, s[b.from], s[b.to]])
	var ri := int(OS.get_environment("ROAD")) if OS.get_environment("ROAD") != "" else 3
	var s: PackedVector3Array = t.road_samples[ri]
	for k in range(0, s.size(), 8):
		var p := s[k]
		print("k=%d x=%.1f z=%.1f road_h=%.1f ground=%.1f base=%.1f biome=%d" % [k, p.x, p.z, p.y, t.height_at(p.x, p.z), t.base_height(p.x, p.z), t.biome_at(p.x, p.z)])
	get_tree().quit()
