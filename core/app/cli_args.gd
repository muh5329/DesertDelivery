class_name CliArgs
extends RefCounted
## Command-line flags after `--`, parsed once:
##   --autotest            drive automatically and quit(0) after N deliveries (default 1)
##   --deliveries=N        how many deliveries the autotest needs
##   --maxtime=S           autotest timeout in seconds (default 240)
##   --shots=DIR           save a screenshot every few seconds into DIR (needs a display)
##   --shot-interval=S     seconds between screenshots (default 4)
##   --load=SLOT           load a save slot at start
##   --nostream            load the whole world at once (renders, profiling)
##   --test=NAME           run res://tests/NAME.gd inside the game
##   --out=DIR             output directory for render tools

var args: Dictionary = {}


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else "true"


func has(key: String) -> bool:
	return args.has(key)


func get_string(key: String, default: String = "") -> String:
	return String(args.get(key, default))


func get_float(key: String, default: float) -> float:
	return float(args.get(key, default))


func get_int(key: String, default: int) -> int:
	return int(args.get(key, default))
