extends Node
## Offline authoring pass: exact mesh/LOD/hull cache, no visual or collider simplification.
func _ready() -> void: call_deferred("run")
func run() -> void:
	if not "--rebuild-rock-library" in OS.get_cmdline_user_args():
		push_error("Baker requires --rebuild-rock-library to bypass existing disk resources")
		get_tree().quit(1)
		return
	Game.current.world.streamer.load_everything()
	var report := RockGen.save_baked_library()
	report["procedural_bake_ms"] = RockGen.cache_usec / 1000.0
	print("ROCK LIBRARY ",JSON.stringify(report))
	var file:=FileAccess.open("res://artifacts/performance-controls/rock-library-build.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"));file.close()
	get_tree().quit(0 if report.failures==0 else 1)
