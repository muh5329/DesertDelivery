class_name Chunk
extends Node3D
## Incremental recipe construction. A built recipe owns a container so large
## structures can transfer to another chunk without recreating their colliders.
var coord: Vector2i
var built := false
var build_ms := 0
var _build_usec := 0
var max_recipe_usec := 0
var worst_recipe := Vector2.ZERO
var worst_mesh_bake_usec := 0
var worst_collision_usec := 0
var worst_disk_load_usec := 0
var _db: WorldDatabase
var _cursor := 0
var _rng_state := 0
var _owned: Dictionary = {} # Recipe -> live Node3D container

func begin(db: WorldDatabase) -> void:
	_db = db
	name = "Chunk_%d_%d" % [coord.x, coord.y]
	var random := RandomNumberGenerator.new()
	random.seed = hash(coord) ^ 0x5EED
	_rng_state = random.state

## Synchronous compatibility path for tests and deliberate teleport loading.
func build(db: WorldDatabase, kit: WorldKit) -> void:
	begin(db)
	while not built: build_step(kit)

## At most one unclaimed recipe per call. Builders are atomic; the caller checks
## its time budget between calls and records any single expensive recipe.
func build_step(kit: WorldKit) -> void:
	if built or _db == null: return
	var records := _db.records_in(coord)
	while _cursor < records.size():
		var recipe: Recipe = records[_cursor]
		_cursor += 1
		if not recipe.unclaimed(): continue
		var container: Node3D = null
		if recipe.radius > 0.0:
			container = Node3D.new()
			container.name = "Recipe_%d" % (_cursor - 1)
			add_child(container)
		_owned[recipe] = container
		recipe.claim(coord)
		var previous_sink := kit.sink
		var previous_rng := kit.rng.state
		kit.sink = container if container != null else self
		kit.rng.state = _rng_state
		var start := Time.get_ticks_usec()
		var mesh_before := RockGen.cache_usec
		var collision_before := RockGen.collision_usec
		var disk_before := RockGen.disk_load_usec
		recipe.builder.call()
		var elapsed := Time.get_ticks_usec() - start
		_build_usec += elapsed
		build_ms = int(_build_usec / 1000.0)
		if elapsed > max_recipe_usec:
			max_recipe_usec = elapsed; worst_recipe = recipe.pos
			worst_mesh_bake_usec = RockGen.cache_usec - mesh_before
			worst_collision_usec = RockGen.collision_usec - collision_before
			worst_disk_load_usec = RockGen.disk_load_usec - disk_before
		_rng_state = kit.rng.state
		kit.rng.state = previous_rng
		kit.sink = previous_sink
		if _cursor >= records.size(): built = true
		return
	built = true

## Existing physics and visual nodes keep their identity and world transform.
func transfer_recipe(recipe: Recipe, destination: Chunk) -> void:
	if not _owned.has(recipe) or _owned[recipe] == null: return
	var container: Node3D = _owned[recipe]
	_owned.erase(recipe)
	container.reparent(destination, true)
	destination._owned[recipe] = container
	recipe.claim(destination.coord)

## Compatibility hook: rescan unclaimed records incrementally, never rebuild
## already-owned structures. Normal streaming transfers containers instead.
func adopt_released(_kit: WorldKit) -> void:
	if _db == null: return
	_cursor = 0; built = false

func release_recipes() -> void:
	for recipe: Recipe in _owned:
		if recipe.owner == coord: recipe.release()
	_owned.clear()

## queue_free is deferred. Remove retired shapes from collision immediately so
## an explicit same-frame reload cannot overlap the previous generation.
func deactivate_collision() -> void:
	for body in find_children("*", "CollisionObject3D", true, false):
		body.collision_layer = 0
		body.collision_mask = 0

func _exit_tree() -> void:
	release_recipes()
