class_name Recipe
extends RefCounted
## One thing to build when its part of the world is loaded: a house, a pier, a batch of pines,
## a whole aqueduct.
##
## A Recipe knows its **extent** — how far the geometry it builds reaches from the point it was
## filed at. That used to be an unstated invariant of `WorldDatabase.add(x, z, builder)`: the
## builder was assumed to stay inside the 60 m chunk containing (x, z), and much of the generator
## did not. An aqueduct spanning 160 m, a Villa hub reaching 62 m in every direction and a Town
## courtyard promenade at least 32 m long were all filed under a single chunk, so they appeared
## and vanished with a chunk two rings away — while the courier was standing on them.
##
## A Recipe with an extent is filed into every chunk it overlaps and built once, by whichever of
## them loads first. When that chunk unloads the recipe is released, and the streamer offers it
## to the chunks still loaded, so it survives as long as any part of it is in range.

## Nothing owns this recipe yet.
const UNCLAIMED := Vector2i(1 << 30, 1 << 30)

var builder: Callable
var pos := Vector2.ZERO
var radius := 0.0
var owner := UNCLAIMED


func _init(p_builder: Callable, p_pos: Vector2, p_radius: float) -> void:
	builder = p_builder
	pos = p_pos
	radius = p_radius


func unclaimed() -> bool:
	return owner == UNCLAIMED


func claim(chunk: Vector2i) -> void:
	owner = chunk


func release() -> void:
	owner = UNCLAIMED


## The chunks this recipe's geometry reaches into.
func chunks(chunk_size: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var lo := Vector2i(floori((pos.x - radius) / chunk_size), floori((pos.y - radius) / chunk_size))
	var hi := Vector2i(floori((pos.x + radius) / chunk_size), floori((pos.y + radius) / chunk_size))
	for z in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			out.append(Vector2i(x, z))
	return out
