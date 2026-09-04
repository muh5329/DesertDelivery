extends Node
## SaveManager (autoload `Saves`): the save file is a set of differences from the default world,
## keyed by stable ids — never node paths. Each system that has state implements
## `save_state() -> Dictionary` / `load_state(d)`; the Game registers them under a key.
## Files live in user://saves/<slot>.json.

var _providers: Dictionary = {}   # key -> Object with save_state/load_state


func register(key: String, provider: Object) -> void:
	_providers[key] = provider


func unregister(key: String) -> void:
	_providers.erase(key)


func path_for(slot: String) -> String:
	return "user://saves/%s.json" % slot


func save_game(slot: String = "quick") -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://saves"))
	var data := {"version": 1, "saved_at": Time.get_datetime_string_from_system(), "systems": {}}
	for key in _providers.keys():
		var p: Object = _providers[key]
		if is_instance_valid(p) and p.has_method("save_state"):
			data.systems[key] = _encode(p.save_state())
	var f := FileAccess.open(path_for(slot), FileAccess.WRITE)
	if f == null:
		push_error("SaveManager: cannot write %s" % path_for(slot))
		return false
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	Events.game_saved.emit(slot)
	return true


func has_save(slot: String = "quick") -> bool:
	return FileAccess.file_exists(path_for(slot))


func load_game(slot: String = "quick") -> bool:
	if not has_save(slot): return false
	var f := FileAccess.open(path_for(slot), FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary): return false
	var systems: Dictionary = parsed.get("systems", {})
	for key in systems.keys():
		var p: Object = _providers.get(key)
		if p and is_instance_valid(p) and p.has_method("load_state"):
			p.load_state(_decode(systems[key]))
	Events.game_loaded.emit(slot)
	return true


# JSON has no Vector3: encode as {"__v3": [x, y, z]} recursively.
func _encode(v: Variant) -> Variant:
	if v is Vector3: return {"__v3": [v.x, v.y, v.z]}
	if v is Dictionary:
		var out := {}
		for k in v.keys(): out[String(k)] = _encode(v[k])
		return out
	if v is Array:
		var out := []
		for e in v: out.append(_encode(e))
		return out
	if v is StringName: return String(v)
	return v


func _decode(v: Variant) -> Variant:
	if v is Dictionary:
		if v.has("__v3"):
			var a: Array = v["__v3"]
			return Vector3(a[0], a[1], a[2])
		var out := {}
		for k in v.keys(): out[k] = _decode(v[k])
		return out
	if v is Array:
		var out := []
		for e in v: out.append(_decode(e))
		return out
	return v
