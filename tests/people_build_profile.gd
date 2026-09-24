extends SceneTree
## Where a townsperson's build time goes (near meshes), part by part:
##   godot --headless --path . -s tests/people_build_profile.gd
func _init() -> void: call_deferred("run")

func run() -> void:
	var totals := {}
	var count := 12
	for i in count:
		var look := CharacterLook.from_seed(300 + i, CharacterLook.STYLES[i % 6], "")
		var m := CharacterMesh.new()
		var body := PersonBody.new(m, look, true)
		for part in ["_torso_layer", "_outer_layer", "_skirt", "_neck"]:
			_time(totals, part, Callable(body, part))
		for part in ["_arm", "_hand", "_leg", "_foot"]:
			_time(totals, part, func(): body.call(part, -1.0); body.call(part, 1.0))
		for part in ["_belt", "_apron", "_neckerchief", "_satchel"]:
			_time(totals, part, Callable(body, part))
		var head := PersonHead.new(m, look, body, true)
		for part in ["_head", "_eyes", "_brows", "_ears", "_facial_hair", "_hair", "_hat"]:
			_time(totals, part, Callable(head, part))
		_time(totals, "commit", func(): m.commit())
	var keys := totals.keys()
	keys.sort_custom(func(a, b): return totals[a] > totals[b])
	var sum := 0.0
	for k in keys: sum += totals[k]
	for k in keys: print("PROFILE %-14s %6.1f ms per person" % [k, totals[k] / count])
	print("PROFILE total %.1f ms per near mesh" % (sum / count))
	quit()

func _time(totals: Dictionary, part: String, fn: Callable) -> void:
	var t := Time.get_ticks_usec()
	fn.call()
	totals[part] = float(totals.get(part, 0.0)) + float(Time.get_ticks_usec() - t) / 1000.0
