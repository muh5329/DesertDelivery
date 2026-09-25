extends Node
## SaveManager (autoload `Saves`): the save file is a set of differences from the default world,
## keyed by stable ids — never node paths. Each system that has state implements
## `save_state() -> Dictionary` / `load_state(d)`; the Game registers them under a key.
## Files live in user://saves/<slot>.json.

var _providers: Dictionary = {}   # key -> Object with save_state/load_state
## What the last load could not use or had to repair ("system: what"); empty after a clean load.
var last_report: Array[String] = []


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
	# atomically: a crash mid-write leaves the previous save, never half a file
	var tmp := path_for(slot) + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("SaveManager: cannot write %s" % tmp)
		return false
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path_for(slot)))
	if err != OK:
		push_error("SaveManager: cannot replace %s (%d)" % [path_for(slot), err])
		return false
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
	var systems: Dictionary = parsed.get("systems", {}) if parsed.get("systems") is Dictionary else {}
	last_report.clear()
	for key in systems.keys():
		var p: Object = _providers.get(key)
		if p and is_instance_valid(p) and p.has_method("load_state"):
			var data: Variant = _decode(systems[key])
			if not data is Dictionary:
				last_report.append("%s: unreadable, kept as it was" % key)
				continue
			var ok: Variant = p.load_state(data)
			if ok is bool and not ok: last_report.append("%s: could not be loaded, kept as it was" % key)
			if p.has_method("load_report"):
				for w in p.load_report(): last_report.append("%s: %s" % [key, w])
	if not last_report.is_empty():
		for w in last_report: push_warning("SaveManager: " + w)
		Events.message.emit("Loaded with problems: %s%s" % [last_report[0], (" (+%d more)" % (last_report.size() - 1)) if last_report.size() > 1 else ""], 6.0)
	# New optional systems can explicitly reset when loading a pre-feature save.
	for key in _providers:
		var p: Object = _providers[key]
		if not systems.has(key) and is_instance_valid(p) and p.has_method("load_missing_state"):
			p.load_missing_state()
	Events.game_loaded.emit(slot)
	return true


# JSON has no Vector3: encode as {"__v3": [x, y, z]} recursively.
func _encode(v: Variant) -> Variant:
	if v is Vector3: return {"__v3": [v.x, v.y, v.z]}
	if v is Vector2i: return {"__v2i": [v.x, v.y]}
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
		if v.has("__v2i"):
			var a: Array = v["__v2i"]
			return Vector2i(int(a[0]), int(a[1]))
		var out := {}
		for k in v.keys(): out[k] = _decode(v[k])
		return out
	if v is Array:
		var out := []
		for e in v: out.append(_decode(e))
		return out
	return v
