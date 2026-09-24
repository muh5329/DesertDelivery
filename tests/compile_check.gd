extends SceneTree
## Loads scripts (with autoloads present) so parse / compile errors show without booting the world.
func _process(_d: float) -> bool:
	var bad := 0
	for a in OS.get_cmdline_user_args():
		if not a.ends_with(".gd"): continue
		var s: Script = load(a)
		if s == null or not s.can_instantiate():
			print("COMPILE FAIL ", a); bad += 1
	print("COMPILE CHECK DONE, failures=", bad)
	quit(bad)
	return true
