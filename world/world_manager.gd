class_name WorldManager
extends Node3D
## Owns the world: the resident parts (terrain, sea, sky, boundaries), the WorldDatabase that
## describes everything else, and the WorldStreamer that turns nearby chunks into nodes.
##
##   WorldManager
##   ├── Environment   sky, sun, sea, abyss, boundary walls, terrain (always loaded)
##   └── WorldStreamer chunks around the focus
##
## Interface: `database`, `terrain`, `streamer`, `island` (the generator), `set_focus(node)`,
## `probe(pos)` / `nearest_road(pos)` forwarded from the terrain.

var config: WorldConfig
var database := WorldDatabase.new()
var island: Island
var terrain: Terrain
var environment: Node3D
var streamer: WorldStreamer
var generate_ms := 0


func setup(p_config: WorldConfig) -> void:
	config = p_config
	database.chunk_size = config.chunk_size
	environment = Node3D.new(); environment.name = "Environment"; add_child(environment)
	streamer = WorldStreamer.new(); streamer.name = "WorldStreamer"; add_child(streamer)
	var t0 := Time.get_ticks_msec()
	island = Island.new()
	island.name = "Island"
	add_child(island)
	island.generate(database, environment, config.seed)
	terrain = island.terrain
	streamer.setup(database, island, config)
	generate_ms = Time.get_ticks_msec() - t0


func set_focus(node: Node3D) -> void:
	streamer.focus = node


func probe(pos: Vector3) -> Dictionary:
	return terrain.probe(pos)


func nearest_road(pos: Vector3) -> Dictionary:
	return terrain.nearest_road(pos)


## A point on the road network near a location, facing towards `toward` (spawn helper).
func road_spawn(near: Vector3, toward: Vector3) -> Dictionary:
	var road := terrain.nearest_road(near)
	var p: Vector3 = road.point
	var t: Vector3 = road.tangent
	if t.dot(toward - p) < 0.0: t = -t
	return {"pos": Vector3(p.x, maxf(p.y, terrain.height_at(p.x, p.z)), p.z), "forward": t}
