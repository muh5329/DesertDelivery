class_name WorldStreamer
extends Node3D
## Nearest-first recipe streaming, with a shared construction budget per frame.
## Synchronous helpers remain available for tests and intentional teleports.
var db: WorldDatabase
var kit: WorldKit
var config: WorldConfig
var focus: Node3D
var loaded: Dictionary = {}
var _pending: Array[Vector2i] = []
var _building: Array[Vector2i] = []
var _focus_chunk := Vector2i(1 << 20, 1 << 20)
var enabled := true
var build_budget_usec := 3000
var last_build_usec := 0
var max_build_usec := 0
var max_recipe_usec := 0
var worst_recipe := Vector2.ZERO
var worst_recipe_attribution: Dictionary = {}
var total_build_usec := 0

func setup(p_db: WorldDatabase, p_kit: WorldKit, p_config: WorldConfig) -> void:
	db = p_db; kit = p_kit; config = p_config

func focus_position() -> Vector3:
	return focus.global_position if focus else Vector3.ZERO

func _process(_delta: float) -> void:
	last_build_usec = 0
	if not enabled or db == null: return
	var started := Time.get_ticks_usec()
	var fc := db.chunk_of_pos(focus_position())
	if fc != _focus_chunk:
		_focus_chunk = fc
		_replan()
	var starts := maxi(config.chunks_per_frame, 1)
	while starts > 0 and not _pending.is_empty():
		var c: Vector2i = _pending.pop_front()
		if not loaded.has(c):
			_start(c)
			starts -= 1
	_sort_building()
	var deadline := started + build_budget_usec
	while not _building.is_empty() and Time.get_ticks_usec() < deadline:
		var c := _building[0]
		var chunk: Chunk = loaded[c]
		chunk.build_step(kit)
		_record_recipe_time(chunk)
		if chunk.built:
			_building.pop_front()
			Events.chunk_loaded.emit(c)
	last_build_usec = Time.get_ticks_usec() - started
	max_build_usec = maxi(max_build_usec,last_build_usec)
	total_build_usec += last_build_usec

func _sort_building() -> void:
	_building.sort_custom(func(a: Vector2i,b: Vector2i): return (a-_focus_chunk).length_squared() < (b-_focus_chunk).length_squared())

func _replan() -> void:
	var keep := config.stream_radius + config.unload_margin
	var departing: Array[Vector2i] = []
	for c: Vector2i in loaded:
		if maxi(absi(c.x-_focus_chunk.x),absi(c.y-_focus_chunk.y)) > keep: departing.append(c)
	_unload_group(departing)
	_pending.clear()
	var radius := config.stream_radius
	for dz in range(-radius,radius+1):
		for dx in range(-radius,radius+1):
			var c := _focus_chunk + Vector2i(dx,dz)
			if not loaded.has(c) and not db.records_in(c).is_empty(): _pending.append(c)
	_pending.sort_custom(func(a: Vector2i,b: Vector2i): return (a-_focus_chunk).length_squared() < (b-_focus_chunk).length_squared())
	_sort_building()

func _start(c: Vector2i) -> Chunk:
	var chunk := Chunk.new(); chunk.coord=c
	add_child(chunk); chunk.begin(db)
	loaded[c]=chunk; _building.append(c)
	return chunk

func _record_recipe_time(chunk: Chunk) -> void:
	if chunk.max_recipe_usec > max_recipe_usec:
		max_recipe_usec=chunk.max_recipe_usec; worst_recipe=chunk.worst_recipe
		worst_recipe_attribution={"mesh_bake_ms":chunk.worst_mesh_bake_usec/1000.0,"collision_ms":chunk.worst_collision_usec/1000.0,"disk_load_ms":chunk.worst_disk_load_usec/1000.0}

func _load(c: Vector2i) -> void:
	var chunk: Chunk = loaded[c] if loaded.has(c) else _start(c)
	if chunk.built: return
	while not chunk.built: chunk.build_step(kit)
	_record_recipe_time(chunk)
	_building.erase(c)
	Events.chunk_loaded.emit(c)

## Remove all departing owners before a single transfer pass, so a structure
## never bounces through other departing chunks or gets rebuilt outside budget.
func _unload_group(coords: Array[Vector2i]) -> void:
	var departures: Array[Chunk] = []
	for c in coords:
		if not loaded.has(c): continue
		departures.append(loaded[c]); loaded.erase(c); _building.erase(c)
	for chunk in departures:
		for recipe: Recipe in chunk._owned.keys():
			for c: Vector2i in recipe.chunks(db.chunk_size):
				if loaded.has(c):
					chunk.transfer_recipe(recipe,loaded[c]); break
		chunk.release_recipes()
		chunk.deactivate_collision()
		chunk.queue_free()
		Events.chunk_unloaded.emit(chunk.coord)

func _unload(c: Vector2i) -> void:
	_unload_group([c])

func load_all_pending() -> void:
	_focus_chunk=db.chunk_of_pos(focus_position()); _replan()
	for c in _building.duplicate(): _load(c)
	while not _pending.is_empty():
		var c: Vector2i = _pending.pop_front()
		_load(c)

func load_everything() -> void:
	enabled=false
	for c: Vector2i in db.chunks(): _load(c)
	_pending.clear()

## Nothing waiting to be started or finished round the focus (the loading screen's readiness).
func idle() -> bool:
	if not enabled: return true
	if db != null and db.chunk_of_pos(focus_position()) != _focus_chunk: return false
	return _pending.is_empty() and _building.is_empty()

## Chunks still to start or finish round the focus.
func remaining() -> int:
	return _pending.size() + _building.size()

func is_loaded_at(p: Vector3) -> bool:
	var c := db.chunk_of_pos(p)
	return loaded.has(c) and loaded[c].built

func stats() -> Dictionary:
	var ms := 0
	for chunk in loaded.values(): ms += chunk.build_ms
	return {"loaded":loaded.size(),"pending":_pending.size()+_building.size(),"total":db.chunks().size(),"focus":_focus_chunk,"build_ms":ms,
		"last_build_ms":last_build_usec/1000.0,"max_build_ms":max_build_usec/1000.0,"max_recipe_ms":max_recipe_usec/1000.0,"worst_recipe":worst_recipe,"worst_recipe_attribution":worst_recipe_attribution,"total_build_ms":total_build_usec/1000.0}
