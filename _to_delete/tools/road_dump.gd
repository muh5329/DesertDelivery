extends SceneTree
## Prints the elevated stretches the terrain found and the profile of one road.
func _init():
	var lv := Level.new()
	get_root().add_child(lv)
	lv.build_terrain()
	for b in lv.terrain.bridges:
		var s: PackedVector3Array = lv.terrain.road_samples[b.road]
		print("bridge road=%d from=%d to=%d deck=%.1f  a=%s b=%s" % [b.road, b.from, b.to, b.deck, s[b.from], s[b.to]])
	var ri := int(OS.get_environment("ROAD")) if OS.get_environment("ROAD") != "" else 3
	var s: PackedVector3Array = lv.terrain.road_samples[ri]
	for k in range(0, s.size(), 8):
		var p := s[k]
		print("k=%d x=%.1f z=%.1f road_h=%.1f ground=%.1f base=%.1f biome=%d" % [k, p.x, p.z, p.y, lv.terrain.height_at(p.x, p.z), lv.terrain.base_height(p.x, p.z), lv.terrain.biome_at(p.x, p.z)])
	quit()
