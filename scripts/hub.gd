class_name Hub
extends RefCounted
## A named place in the world — villa, farm, harbour, lookout — with the geometry other modules
## need to put things on it: its centre and ground height, the delivery ring, and any surfaces
## (stone walls, a bench) that props can sit on. Built by Level; read by GameManager, GunSystem,
## tests. Nobody else re-derives wall tops from level.gd literals any more.

var name := ""
var centre := Vector2.ZERO
var pad_radius := 20.0
var ground := 0.0                 # terrain height at the centre
var ring_pos := Vector3.ZERO      # where the delivery ring sits
var ring_facing := Vector3.FORWARD
var walls: Array = []             # each: {a: Vector2, b: Vector2, height: float, segments: int}
var bench := Vector3.ZERO         # top-centre of a bench, if the hub has one
var bench_width := 0.0
var _terrain: Terrain


func _init(p_name: String, p_centre: Vector2, p_pad: float, p_terrain: Terrain) -> void:
	name = p_name
	centre = p_centre
	pad_radius = p_pad
	_terrain = p_terrain
	ground = p_terrain.height_at(p_centre.x, p_centre.y)


func centre3() -> Vector3:
	return Vector3(centre.x, ground, centre.y)


## Record a stone wall that Level built between a and b (world XZ), `height` tall, in 4 m segments.
func add_wall(a: Vector2, b: Vector2, height: float) -> void:
	walls.append({"a": a, "b": b, "height": height, "segments": int(ceil(a.distance_to(b) / 4.0))})


## World position on top of the first wall at the given x (null if there is no wall there).
## Mirrors how Level builds the wall: each segment sits at the ground height of its midpoint.
func wall_top(x: float, wall_index: int = 0) -> Variant:
	if wall_index >= walls.size(): return null
	var w: Dictionary = walls[wall_index]
	var a: Vector2 = w.a; var b: Vector2 = w.b
	if absf(b.x - a.x) < 0.001: return null
	var t := clampf((x - a.x) / (b.x - a.x), 0.0, 1.0)
	var z := lerpf(a.y, b.y, t)
	var seg := clampi(int(t * w.segments), 0, w.segments - 1)
	var mid := a.lerp(b, (seg + 0.5) / w.segments)
	var top: float = _terrain.height_at(mid.x, mid.y) + w.height - 0.1
	return Vector3(x, top, z)


## World position on top of the bench at a fraction (0..1) along its width.
func bench_top(fraction: float) -> Vector3:
	return bench + Vector3((fraction - 0.5) * bench_width, 0.0, 0.0)
