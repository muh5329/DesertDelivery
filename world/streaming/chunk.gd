class_name Chunk
extends Node3D
## One streamed section of the world: builds its recipes from the WorldDatabase when loaded and
## is simply freed when unloaded. Deterministic: the kit's rng is reseeded from the coordinate.

var coord: Vector2i
var built := false
var build_ms := 0


func build(db: WorldDatabase, kit: WorldKit) -> void:
	var t0 := Time.get_ticks_msec()
	name = "Chunk_%d_%d" % [coord.x, coord.y]
	kit.sink = self
	kit.rng.seed = hash(coord) ^ 0x5EED
	for r in db.records_in(coord):
		r.call()
	kit.sink = null
	built = true
	build_ms = Time.get_ticks_msec() - t0
