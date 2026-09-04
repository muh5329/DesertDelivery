class_name WorldStreamer
extends Node3D
## Keeps the chunks around the focus (the player) instantiated and frees the rest.
## Loads nearest-first with a per-frame budget so a teleport never hitches for long; unloads with
## one chunk of hysteresis so riding along a chunk edge doesn't thrash.

var db: WorldDatabase
var kit: WorldKit
var config: WorldConfig
var focus: Node3D
var loaded: Dictionary = {}      # Vector2i -> Chunk
var _pending: Array[Vector2i] = []
var _focus_chunk := Vector2i(1 << 20, 1 << 20)
var enabled := true


func setup(p_db: WorldDatabase, p_kit: WorldKit, p_config: WorldConfig) -> void:
	db = p_db; kit = p_kit; config = p_config


func focus_position() -> Vector3:
	return focus.global_position if focus else Vector3.ZERO


func _process(_delta: float) -> void:
	if not enabled or db == null: return
	var fc := db.chunk_of_pos(focus_position())
	if fc != _focus_chunk:
		_focus_chunk = fc
		_replan()
	var budget: int = maxi(config.chunks_per_frame, 1)
	while budget > 0 and not _pending.is_empty():
		var c: Vector2i = _pending.pop_front()
		if not loaded.has(c):
			_load(c)
			budget -= 1


func _replan() -> void:
	var r := config.stream_radius
	# unload what is now out of range (radius + margin)
	var keep := r + config.unload_margin
	for c in loaded.keys():
		if maxi(absi(c.x - _focus_chunk.x), absi(c.y - _focus_chunk.y)) > keep:
			_unload(c)
	# queue what should be in, nearest first
	_pending.clear()
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var c := _focus_chunk + Vector2i(dx, dz)
			if not loaded.has(c) and not db.records_in(c).is_empty():
				_pending.append(c)
	_pending.sort_custom(func(a, b): return (a - _focus_chunk).length_squared() < (b - _focus_chunk).length_squared())


func _load(c: Vector2i) -> void:
	var ch := Chunk.new()
	ch.coord = c
	add_child(ch)
	ch.build(db, kit)
	loaded[c] = ch
	Events.chunk_loaded.emit(c)


func _unload(c: Vector2i) -> void:
	var ch: Chunk = loaded[c]
	loaded.erase(c)
	ch.queue_free()
	Events.chunk_unloaded.emit(c)


## Load everything within range right now (tests, screenshots, teleports).
func load_all_pending() -> void:
	_focus_chunk = db.chunk_of_pos(focus_position())
	_replan()
	while not _pending.is_empty():
		var c: Vector2i = _pending.pop_front()
		if not loaded.has(c): _load(c)


## Load every chunk of the world and stop streaming (fixed-camera renders, profiling).
func load_everything() -> void:
	enabled = false
	for c in db.chunks():
		if not loaded.has(c): _load(c)


func is_loaded_at(p: Vector3) -> bool:
	return loaded.has(db.chunk_of_pos(p))


func stats() -> Dictionary:
	var ms := 0
	for ch in loaded.values(): ms += ch.build_ms
	return {"loaded": loaded.size(), "pending": _pending.size(), "total": db.chunks().size(), "focus": _focus_chunk, "build_ms": ms}
