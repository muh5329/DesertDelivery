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
	for step in setup_steps(p_config): (step[1] as Callable).call()


## `setup` as named steps, in order: [id, Callable]. Game's boot runs them one per frame behind
## the loading screen (core/app/game.gd `_boot`); `setup` runs them back to back (tools, tests).
func setup_steps(p_config: WorldConfig) -> Array:
	var steps: Array = []
	steps.append([&"terrain", func():
		config = p_config
		database.chunk_size = config.chunk_size
		environment = Node3D.new(); environment.name = "Environment"; add_child(environment)
		streamer = WorldStreamer.new(); streamer.name = "WorldStreamer"; add_child(streamer)
		_t0 = Time.get_ticks_msec()
		TexMips.cpu_compression()   # workers compress textures: keep Image.compress() off the render thread
		BuildingKit.warm()          # the architecture kit's textures decode on a worker while the world generates
		island = Island.new()
		island.name = "Island"
		add_child(island)
		island.generate_heightfield(database, environment, config.seed)
		terrain = island.terrain])
	steps.append([&"ground", func(): island.generate_ground()])
	steps.append([&"core", func(): island.generate_places()])
	for id in OuterWorld.SETUP_STEPS:
		steps.append([id, func():
			if id == &"outer_data":
				outer = OuterWorld.new()
				environment.add_child(outer)
			outer.setup_step(id, terrain, database, island, config.seed)
			if id == &"outer_wild": terrain.expanse = outer])
	steps.append([&"sky", func():
		day_night = DayNight.new()
		environment.add_child(day_night)
		day_night.setup(self)
		GraphicsSettings.apply(self)     # the saved quality preset (F10), High by default
		streamer.setup(database, island, config)])
	steps.append([&"textures", func():
		# the kit's texture arrays were decoded and compressed on the workers during the generation:
		# upload them now, behind the loading screen, not at the first town (m-14)
		ArchMaterials.finish_boot()
		RockGen.prefetch_library()   # the baked rocks read on the loader's threads, not mid-ride (m-5)
		generate_ms = Time.get_ticks_msec() - _t0])
	return steps


var _t0 := 0


## Everything round the focus is built: chunks, collision tiles, road ribbons, near wilderness.
func settled() -> bool:
	if streamer == null or not streamer.idle(): return false
	return outer == null or outer.settled()


## How much is still to build round the focus (the loading screen's bar after a long move).
func settle_remaining() -> int:
	var n := streamer.remaining() if streamer else 0
	if outer: n += outer.settle_remaining()
	return n


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
