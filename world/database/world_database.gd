class_name WorldDatabase
extends RefCounted
## The authoritative description of the world, independent of what is currently loaded:
##   - `records`: per streaming chunk, the list of build recipes (Callables that create the
##     chunk's geometry when it is loaded — houses, rocks, vegetation batches, piers...)
##   - `locations`: id -> {pos, facing, name}: delivery rings and other named points
##   - `hubs`: id -> Hub records (walls, benches, pads) that gameplay can build on
## Gameplay systems read this database; they never have to know whether a chunk is loaded.

var chunk_size := 120.0
var records: Dictionary = {}       # Vector2i -> Array[Callable]
var locations: Dictionary = {}     # StringName -> {pos: Vector3, facing: Vector3, name: String}
var hubs: Dictionary = {}          # StringName -> Hub
var record_count := 0


func chunk_of(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / chunk_size), floori(z / chunk_size))


func chunk_of_pos(p: Vector3) -> Vector2i:
	return chunk_of(p.x, p.z)


func chunk_origin(c: Vector2i) -> Vector3:
	return Vector3(c.x * chunk_size, 0.0, c.y * chunk_size)


## Add a build recipe at world XZ. The Callable takes no arguments; the chunk sets the kit's
## `sink` before running it, so builders just build.
func add(x: float, z: float, builder: Callable) -> void:
	var c := chunk_of(x, z)
	if not records.has(c):
		records[c] = []
	records[c].append(builder)
	record_count += 1


func records_in(c: Vector2i) -> Array:
	return records.get(c, [])


func chunks() -> Array:
	return records.keys()


func add_location(id: StringName, pos: Vector3, facing: Vector3, display_name: String) -> void:
	locations[id] = {"pos": pos, "facing": facing.normalized(), "name": display_name}


func location_pos(id: StringName) -> Vector3:
	return locations[id]["pos"]


func location_name(id: StringName) -> String:
	return locations[id]["name"] if locations.has(id) else String(id)


func hub(id: StringName) -> Hub:
	return hubs[id]


## The nearest named location to a point (for "where am I" / debug).
func nearest_location(p: Vector3) -> StringName:
	var best: StringName = &""
	var bd := INF
	for id in locations.keys():
		var d: float = locations[id]["pos"].distance_to(p)
		if d < bd: bd = d; best = id
	return best
