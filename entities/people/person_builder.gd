class_name PersonBuilder
extends RefCounted
## Builds (and caches) the two meshes of a townsperson from a look Dictionary
## (CharacterLook): a detailed one for the street and a light one beyond ~20 m that keeps
## the same silhouette, hair, skin and clothing colours. Both are single-surface skinned
## meshes on the shared 13-bone rig, drawn with one shared material.

const CACHE_LIMIT := 72
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


## {"near": ArrayMesh, "far": ArrayMesh}
static func meshes(look: Dictionary) -> Dictionary:
	var key := key_of(look)
	if _cache.has(key):
		_order.erase(key); _order.append(key)
		return _cache[key]
	var started := Time.get_ticks_usec()
	var result := {"near": build(look, true), "far": build(look, false)}
	build_ms += float(Time.get_ticks_usec() - started) / 1000.0
	builds += 1
	_cache[key] = result
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
	return _cache.has(key_of(look))


static func cached(look: Dictionary) -> Dictionary:
	return _cache.get(key_of(look), {})


static func request(look: Dictionary) -> void:
	var key := key_of(look)
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
