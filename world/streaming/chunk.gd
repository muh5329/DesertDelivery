class_name Chunk
extends Node3D
## One streamed section of the world: builds its recipes from the WorldDatabase when loaded and
## is simply freed when unloaded. Deterministic: the kit's rng is reseeded from the coordinate.

var coord: Vector2i
var built := false
var build_ms := 0
var _db: WorldDatabase


func build(db: WorldDatabase, kit: WorldKit) -> void:
	var t0 := Time.get_ticks_msec()
	_db = db
	name = "Chunk_%d_%d" % [coord.x, coord.y]
	_run_unclaimed(kit)
	built = true
	build_ms = Time.get_ticks_msec() - t0


## Build every recipe filed here that nobody has built yet. A recipe with an extent is filed in
## several chunks; the first one to reach it claims it, so the geometry exists exactly once.
func _run_unclaimed(kit: WorldKit) -> void:
	kit.sink = self
	kit.rng.seed = hash(coord) ^ 0x5EED
	for r in _db.records_in(coord):
		if not r.unclaimed(): continue
		r.claim(coord)
		r.builder.call()
	kit.sink = null


## Offer this chunk's released recipes a new home — called after a neighbour unloaded.
func adopt_released(kit: WorldKit) -> void:
	if _db == null: return
	_run_unclaimed(kit)


## Anything this chunk claimed goes with it, and becomes available to a chunk still loaded.
func release_recipes() -> void:
	if _db == null: return
	for r in _db.records_in(coord):
		if r.owner == coord: r.release()


func _exit_tree() -> void:
	release_recipes()
