class_name PersonBuilder
extends RefCounted
## Builds (and caches) the two meshes of a townsperson from a look Dictionary
## (CharacterLook): a detailed one for the street and a light one beyond ~20 m that keeps
## the same silhouette, hair, skin and clothing colours. Both are single-surface skinned
## meshes on the shared 13-bone rig, drawn with one shared material.

## ~1 MB per person (near + far); live models keep their meshes regardless.
const CACHE_LIMIT := 40
static var _cache: Dictionary = {}
static var _order: Array = []
static var _skin: Skin
## Milliseconds spent building meshes (for the benchmark and tests).
static var build_ms := 0.0
static var builds := 0


static func shared_skin() -> Skin:
	if _skin == null: _skin = CharacterMesh.make_skin()
	return _skin


static func key_of(look: Dictionary) -> String:
	if look.has("key"): return String(look.key) + "|" + str(look.get("variant", 0))
	return str(var_to_str(look).hash())


## Looks that must never be evicted (the bandits' and pirates' few variants: an enemy that spawns
## must not wait ~100 ms for a body). key -> {"near", "far"} once built.
static var _pinned: Dictionary = {}


static func pin(look: Dictionary) -> void:
	var key := key_of(look)
	if not _pinned.has(key): _pinned[key] = {}
	if _pinned[key].is_empty() and _cache.has(key): _pinned[key] = _cache[key]


static func _restore_pinned(key: String) -> void:
	if not _cache.has(key) and _pinned.has(key) and not (_pinned[key] as Dictionary).is_empty():
		_cache[key] = _pinned[key]
		_order.append(key)


## {"near": ArrayMesh, "far": ArrayMesh}
static func meshes(look: Dictionary) -> Dictionary:
	var key := key_of(look)
	_restore_pinned(key)
	if _cache.has(key):
		_order.erase(key); _order.append(key)
		return _cache[key]
	var started := Time.get_ticks_usec()
	var result := {"near": build(look, true), "far": build(look, false)}
	build_ms += float(Time.get_ticks_usec() - started) / 1000.0
	builds += 1
	_cache[key] = result
	if _pinned.has(key): _pinned[key] = result
	_order.append(key)
	while _order.size() > CACHE_LIMIT:
		_cache.erase(_order.pop_front())
	return result


static func build(look: Dictionary, near: bool) -> ArrayMesh:
	return _assemble(look, near).commit()


## The pure-data part of a build (safe on a worker thread).
static func _assemble(look: Dictionary, near: bool) -> CharacterMesh:
	var m := CharacterMesh.new()
	var body := PersonBody.new(m, look, near)
	body.build()
	var head := PersonHead.new(m, look, body, near)
	head.build()
	return m


# ------------------------------------------------------------------ background builds
## Streaming residents never wait on a build: request() assembles the arrays on a worker
## thread; poll() (main thread) turns finished ones into meshes. A model whose meshes are
## not ready yet simply draws nothing until they are.
static var _mutex := Mutex.new()
static var _pending: Dictionary = {}
static var _finished: Dictionary = {}


static func is_cached(look: Dictionary) -> bool:
	_restore_pinned(key_of(look))
	return _cache.has(key_of(look))


static func cached(look: Dictionary) -> Dictionary:
	_restore_pinned(key_of(look))
	return _cache.get(key_of(look), {})


static func request(look: Dictionary) -> void:
	var key := key_of(look)
	_restore_pinned(key)
	if _cache.has(key) or _pending.has(key): return
	_pending[key] = WorkerThreadPool.add_task(Callable(PersonBuilder, "_build_task").bind(look.duplicate(true), key), false, "townsperson mesh")


static func _build_task(look: Dictionary, key: String) -> void:
	var started := Time.get_ticks_usec()
	var near := _assemble(look, true)
	var far := _assemble(look, false)
	_mutex.lock()
	_finished[key] = [near, far]
	build_ms += float(Time.get_ticks_usec() - started) / 1000.0
	builds += 1
	_mutex.unlock()


## Commits finished background builds (at most `limit` per call). Returns how many.
static func poll(limit: int = 3) -> int:
	if _pending.is_empty(): return 0
	_mutex.lock()
	var keys := _finished.keys().slice(0, limit)
	var done: Array = []
	for key in keys:
		done.append([key, _finished[key]])
		_finished.erase(key)
	_mutex.unlock()
	for item in done:
		var key: String = item[0]
		var parts: Array = item[1]
		# the task has finished; waiting releases it
		if int(_pending.get(key, -1)) >= 0: WorkerThreadPool.wait_for_task_completion(_pending[key])
		_pending.erase(key)
		_cache[key] = {"near": (parts[0] as CharacterMesh).commit(), "far": (parts[1] as CharacterMesh).commit()}
		if _pinned.has(key): _pinned[key] = _cache[key]
		_order.erase(key); _order.append(key)
	while _order.size() > CACHE_LIMIT:
		_cache.erase(_order.pop_front())
	return done.size()


static func pending() -> int:
	return _pending.size()


## Blocks until every background build has finished and commits them (tests, shutdown).
static func wait_all() -> void:
	for key in _pending.keys(): WorkerThreadPool.wait_for_task_completion(_pending[key])
	_mutex.lock()
	var done := _finished.size()
	_mutex.unlock()
	# (the waits above released the tasks; poll must not wait on them again)
	for key in _pending.keys(): _pending[key] = -1
	while done > 0 and poll(64) > 0: pass


static func clear_cache() -> void:
	_cache.clear(); _order.clear()
	for key in _pinned: _pinned[key] = {}


# ------------------------------------------------------------------ parts (crowds)
## The ambient crowds of the outer towns need many people at once but few up close: a far
## mesh (~10 ms, 1.7k vertices) for everybody on screen and a near mesh (~90 ms, 13k vertices)
## for the handful within ~20 m. Parts are built (and committed) on worker threads, so the
## main thread only swaps a finished mesh in; each kind has its own LRU cache. A part already
## present in the whole-person cache above is reused.
const PART_LIMIT_NEAR := 56
const PART_LIMIT_FAR := 320
## At most this many part builds in flight at once: one core stays the main thread's.
static var part_workers := clampi(OS.get_processor_count() - 1, 1, 3)
static var _parts: Dictionary = {}          # "key|n" / "key|f" -> ArrayMesh
static var _parts_order := {true: [], false: []}
static var _part_pending: Dictionary = {}   # pkey -> task id
static var _part_done: Dictionary = {}      # pkey -> ArrayMesh (committed on the worker)
static var _part_queue: Array = []          # [pkey, look, near] waiting for a worker slot
static var part_builds := 0
static var part_build_ms := 0.0


static func part_key(look: Dictionary, near: bool) -> String:
	return key_of(look) + ("|n" if near else "|f")


## The finished mesh of one detail level, or null.
static func part(look: Dictionary, near: bool) -> ArrayMesh:
	var whole: Dictionary = _cache.get(key_of(look), {})
	if not whole.is_empty(): return whole.near if near else whole.far
	var pkey := part_key(look, near)
	var mesh: ArrayMesh = _parts.get(pkey)
	if mesh != null:
		var order: Array = _parts_order[near]
		order.erase(pkey); order.append(pkey)
	return mesh


## Ask for one detail level. `urgent` goes to the front of the queue (the nearest people).
static func request_part(look: Dictionary, near: bool, urgent := false) -> void:
	var pkey := part_key(look, near)
	if _parts.has(pkey) or _part_pending.has(pkey) or _cache.has(key_of(look)): return
	for q in _part_queue:
		if q[0] == pkey:
			if urgent:
				_part_queue.erase(q); _part_queue.push_front(q)
			return
	var item := [pkey, look.duplicate(true), near]
	if urgent: _part_queue.push_front(item)
	else: _part_queue.append(item)


## Forget queued (not started) requests, e.g. when the crowd they were for has moved on.
static func cancel_parts() -> void:
	_part_queue.clear()


static func parts_waiting() -> int:
	return _part_queue.size() + _part_pending.size()


static func _part_task(look: Dictionary, near: bool, pkey: String) -> void:
	var started := Time.get_ticks_usec()
	var mesh := _assemble(look, near).commit()
	_mutex.lock()
	_part_done[pkey] = mesh
	part_build_ms += float(Time.get_ticks_usec() - started) / 1000.0
	part_builds += 1
	_mutex.unlock()


## Main thread, once a frame: collect finished parts, start queued ones. Cheap: the meshes
## were committed on the worker, so nothing here costs more than a dictionary move.
static func poll_parts() -> int:
	var n := 0
	if not _part_pending.is_empty():
		_mutex.lock()
		var done := _part_done.duplicate()
		_part_done.clear()
		_mutex.unlock()
		for pkey in done:
			if _part_pending.has(pkey):
				WorkerThreadPool.wait_for_task_completion(_part_pending[pkey])
				_part_pending.erase(pkey)
			_parts[pkey] = done[pkey]
			var near := String(pkey).ends_with("|n")
			var order: Array = _parts_order[near]
			order.erase(pkey); order.append(pkey)
			var limit := PART_LIMIT_NEAR if near else PART_LIMIT_FAR
			while order.size() > limit: _parts.erase(order.pop_front())
			n += 1
	while _part_pending.size() < part_workers and not _part_queue.is_empty():
		var q: Array = _part_queue.pop_front()
		_part_pending[q[0]] = WorkerThreadPool.add_task(Callable(PersonBuilder, "_part_task").bind(q[1], q[2], q[0]), false, "townsperson part")
	return n


## Blocks until every part in flight or queued is built (tests, shutdown).
static func wait_parts() -> void:
	var guard := 0
	while (not _part_pending.is_empty() or not _part_queue.is_empty()) and guard < 100000:
		guard += 1
		for pkey in _part_pending.keys(): WorkerThreadPool.wait_for_task_completion(_part_pending[pkey])
		_mutex.lock()
		var done := _part_done.duplicate()
		_part_done.clear()
		_mutex.unlock()
		for pkey in done:
			_part_pending.erase(pkey)
			_parts[pkey] = done[pkey]
			_parts_order[String(pkey).ends_with("|n")].append(pkey)
		for pkey in _part_pending.keys():
			if not done.has(pkey): _part_pending.erase(pkey)
		while _part_pending.size() < part_workers and not _part_queue.is_empty():
			var q: Array = _part_queue.pop_front()
			_part_pending[q[0]] = WorkerThreadPool.add_task(Callable(PersonBuilder, "_part_task").bind(q[1], q[2], q[0]), false, "townsperson part")
