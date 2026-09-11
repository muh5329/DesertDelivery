extends Node
## Loads the whole island and prints what the RockGen cache cost: unique meshes, bake time,
## and the total chunk build time. Run: godot --headless --path . -- --test=rock_stats
func _ready() -> void:
	var lvl: WorldManager = Game.current.world
	var t0 := Time.get_ticks_msec()
	lvl.streamer.load_everything()
	var st := lvl.streamer.stats()
	print("[rocks] unique RockGen meshes: %d, baked in %d ms; all %d chunks built in %d ms (%d ms wall)" % [
		RockGen.cache_size(), RockGen.cache_usec / 1000, st.loaded, st.build_ms, Time.get_ticks_msec() - t0])
	get_tree().quit()
