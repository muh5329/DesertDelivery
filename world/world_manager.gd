class_name WorldManager
extends Node3D
## Owns the world: the resident parts (terrain, sea, sky, boundaries), the WorldDatabase that
## describes everything else, and the WorldStreamer that turns nearby chunks into nodes.
##
##   WorldManager
##   ├── Environment   sky, sun, sea, abyss, boundary walls, terrain, DayNight (always loaded)
##   └── WorldStreamer chunks around the focus
##
## Interface: `database`, `terrain`, `streamer`, `island` (the generator), `outer` (the outer
## world), `set_focus(node)`,
## `probe(pos)` / `nearest_road(pos)` forwarded from the terrain.

var config: WorldConfig
var database := WorldDatabase.new()
var island: Island
var terrain: Terrain
var environment: Node3D
var streamer: WorldStreamer
var generate_ms := 0
## The 25 km country round the core (world/outer, ADR 0010).
var outer: OuterWorld
## The light of the hour: sun, moon, sky, fog, lamps (world/sky, M-12).
var day_night: DayNight


func setup(p_config: WorldConfig) -> void:
	config = p_config
	database.chunk_size = config.chunk_size
	environment = Node3D.new(); environment.name = "Environment"; add_child(environment)
	streamer = WorldStreamer.new(); streamer.name = "WorldStreamer"; add_child(streamer)
	var t0 := Time.get_ticks_msec()
	TexMips.cpu_compression()   # workers compress textures: keep Image.compress() off the render thread
	BuildingKit.warm()          # the architecture kit's textures decode on a worker while the world generates
	island = Island.new()
	island.name = "Island"
	add_child(island)
	island.generate(database, environment, config.seed)
	terrain = island.terrain
	outer = OuterWorld.new()
	environment.add_child(outer)
	outer.setup(terrain, database, island, config.seed)
	terrain.expanse = outer
	day_night = DayNight.new()
	environment.add_child(day_night)
	day_night.setup(self)
	GraphicsSettings.apply(self)     # the saved quality preset (F10), High by default
	streamer.setup(database, island, config)
	# the kit's texture arrays were decoded and compressed on the workers during the generation:
	# upload them now, behind the loading screen, not at the first town (m-14)
	ArchMaterials.finish_boot()
	generate_ms = Time.get_ticks_msec() - t0


func set_focus(node: Node3D) -> void:
	streamer.focus = node
	outer.focus = node
	outer.refresh_collision()


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
