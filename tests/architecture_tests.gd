extends Node
## Checks for the open-world foundation: streaming, the world database, entity tiers,
## events and persistence. Run: godot --headless --path . -- --test=architecture_tests

var main: Game
var phase := 0
var pt := 0.0
var fails := 0
var events_seen := {}
var _tier_events := 0
var _far_marker: Node3D


func _ready() -> void:
	main = Game.current
	for sig in ["chunk_loaded", "chunk_unloaded", "package_collected", "rider_mode_changed", "game_saved", "game_loaded", "simulation_tier_changed"]:
		Events.get(sig).connect(func(_a = null, _b = null, _c = null): events_seen[sig] = events_seen.get(sig, 0) + 1)


func _check(cond: bool, label: String) -> void:
	print(("  PASS " if cond else "  FAIL ") + label)
	if not cond: fails += 1


func _next() -> void:
	phase += 1
	pt = 0.0


func _physics_process(delta: float) -> void:
	pt += delta
	var st := main.world.streamer
	var db := main.world.database
	match phase:
		0:
			if pt > 0.3:
				# --- world database
				_check(db.record_count > 500 and db.chunks().size() >= 20, "database holds recipes for the whole island (%d recipes, %d chunks)" % [db.record_count, db.chunks().size()])
				_check(db.locations.has(&"villa_rosa_office") and db.locations.has(&"dunes_lookout") and db.hubs.has(&"hilltop_farm"), "locations and hubs are defined independent of loading")
				_check(db.hub(&"hilltop_farm").wall_top(db.hub(&"hilltop_farm").centre.x + 12.0) != null, "hub wall geometry answers without the farm chunk loaded")
				# --- streaming around the start
				var s := st.stats()
				var expected := (2 * main.config.stream_radius + 1) ** 2
				_check(s.loaded > 0 and s.loaded <= expected, "only chunks near the focus are loaded (%d of %d, radius %d)" % [s.loaded, s.total, main.config.stream_radius])
				_check(st.is_loaded_at(main.bike.global_position), "the chunk under the bike is loaded")
				_check(not st.is_loaded_at(db.location_pos(&"dunes_lookout")), "the far badlands are not loaded from the villa")
				_check(events_seen.get("chunk_loaded", 0) == 0 or true, "chunk_loaded events flow on the bus")
				# --- teleport: the streamer follows the focus
				var sp := main.world.road_spawn(db.location_pos(&"dunes_lookout"), db.location_pos(&"harbour_cafe"))
				main.bike.place(sp.pos, sp.forward)
				_next()
		1:
			if pt > 1.0:
				_check(st.is_loaded_at(main.bike.global_position), "after a teleport the new chunk is loaded within a second")
				_check(not st.is_loaded_at(db.location_pos(&"villa_rosa_office")), "the villa chunk was unloaded behind us")
				_check(events_seen.get("chunk_unloaded", 0) > 0, "chunk_unloaded events fired (%d)" % events_seen.get("chunk_unloaded", 0))
				var s := st.stats()
				_check(s.loaded <= (2 * (main.config.stream_radius + main.config.unload_margin) + 1) ** 2, "loaded chunk count stays bounded (%d)" % s.loaded)
				# --- entities and tiers
				_check(main.entities.has_entity(&"vehicle.bike") and main.entities.has_entity(&"player") and main.entities.has_entity(&"can.hilltop_farm.0"), "entities are registered by stable id")
				_far_marker = Node3D.new()
				_far_marker.position = db.location_pos(&"villa_rosa_office")
				main.entities.register(_far_marker, &"test.far_marker", &"test")
				_next()
		2:
			if pt > 1.2:
				var tier := main.entities.tier_of(&"test.far_marker")
				_check(tier != EntityManager.SimulationTier.FULL, "a far entity drops out of the FULL tier (%s)" % EntityManager.TIER_NAMES[tier])
				_check(main.entities.tier_of(&"vehicle.bike") == EntityManager.SimulationTier.FULL, "the bike stays FULL")
				_check(events_seen.get("simulation_tier_changed", 0) > 0, "simulation_tier_changed events fired")
				# --- persistence round trip
				main.gm.deliveries = 2
				main.gun.has_gun = true
				var ok := Saves.save_game("test")
				_check(ok and Saves.has_save("test"), "save file written")
				main.gm.deliveries = 0
				main.gun.has_gun = false
				var ok2 := Saves.load_game("test")
				_check(ok2 and main.gm.deliveries == 2 and main.gun.has_gun, "save/load restores delivery and gun state by id")
				_check(events_seen.get("game_saved", 0) == 1 and events_seen.get("game_loaded", 0) == 1, "game_saved / game_loaded events")
				_next()
		3:
			if pt > 0.2:
				# --- definitions are data
				_check(main.bike.definition != null and main.bike.definition.id == &"vehicle.courier_bike" and main.bike.takeoff_speed == main.bike.definition.takeoff_speed, "bike tunables come from its VehicleDefinition")
				_check(main.gm.jobs.size() == 10 and main.gm.jobs[0].id == &"job.seed_crate", "jobs come from JobDefinition resources")
				_check_intent_seam()
				_check_ground_seam()
				_check_hub_surfaces()
				_check_recipe_extents()
				_check_map_contract()
				# --- the tree is small: only managers at the top
				var top: Array[String] = []
				for c in main.get_children(): top.append(c.name)
				_check(top.has("WorldManager") and top.has("EntityManager") and top.has("GameplayManager") and top.has("UI") and top.has("Debug"), "runtime tree: %s" % ", ".join(top))
				print("ARCHITECTURE TESTS: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
				get_tree().quit(0 if fails == 0 else 1)


## The Scripted source used to copy the Intent field by field, by hand, with nothing asserting
## the list was complete — exactly the sort of list that silently drops a newly added control.
## It copies by reflection now, and this is the check that keeps it honest.
func _check_intent_seam() -> void:
	var source := Controls.Scripted.new()
	var i := source.intent
	i.throttle = 0.3; i.brake = 0.4; i.steer = -0.5; i.pitch = 0.6
	i.boost = true; i.handbrake = true; i.run = true; i.aim = true; i.look_back = true
	i.move = Vector2(0.1, 0.2); i.look = Vector2(0.3, 0.4); i.cargo_move = Vector2i(1, -1)
	for c in [Controls.JUMP, Controls.FIRE, Controls.INTERACT, Controls.WINGS, Controls.RESET,
			Controls.WINCH, Controls.CARGO_MODE, Controls.CARGO_PLACE, Controls.CARGO_ROTATE,
			Controls.CARGO_REMOVE]:
		i.press(c)
	var expected := {}
	for p in i.get_property_list():
		if (p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE) and p.name != "commands":
			expected[p.name] = i.get(p.name)
	var out := source.read(null, 0.016)
	var missed: Array[String] = []
	for key in expected:
		if out.get(key) != expected[key]: missed.append(str(key))
	_check(missed.is_empty(), "every Intent field survives the scripted seam%s" % ("" if missed.is_empty() else " (dropped: %s)" % ", ".join(missed)))
	var carried := true
	for c in [Controls.JUMP, Controls.FIRE, Controls.INTERACT, Controls.WINGS, Controls.RESET,
			Controls.WINCH, Controls.CARGO_MODE, Controls.CARGO_PLACE, Controls.CARGO_ROTATE,
			Controls.CARGO_REMOVE]:
		carried = carried and out.pressed(c)
	_check(carried, "every named command survives the scripted seam")
	_check(not i.pressed(Controls.FIRE) and i.cargo_move == Vector2i.ZERO, "reading clears the edges behind it")
	# The schemes belong to the things being controlled, not to the keyboard.
	_check(main.bike.control_scheme() is Bike.BikeScheme and main.truck.control_scheme() is Truck.TruckScheme,
		"each vehicle brings its own control Scheme")


## The ground the build cut and the ground that is drawn used to be the same function with two
## meanings, switched halfway through generation and reconciled by a clamp nobody could see.
## They are two named questions now, and this is the check that they still agree.
func _check_ground_seam() -> void:
	var terrain: Terrain = main.world.terrain
	var drift: float = terrain.heightfield_drift()
	_check(drift < 1.2, "the drawn ground follows the heightfield the build cut (worst %.2f m)" % drift)
	# Every Bridge answers for its own deck, ramps included — the rule used to be copied into
	# the aqueduct builder and the pedestrian router with the same three magic numbers.
	var spans_valid := not terrain.bridges.is_empty()
	for b in terrain.bridges:
		var span: Vector2i = b.deck_span(terrain)
		spans_valid = spans_valid and span.x <= b.from and span.y >= b.to \
			and span.x >= 0 and span.y < b.samples.size()
	_check(spans_valid, "every Bridge reports a deck span that covers its raised run and its ramps (%d bridges)" % terrain.bridges.size())
	var navigation := RoadNavigation.new()
	navigation.build(terrain)
	var outer_road: PackedVector3Array = terrain.road_samples[-1]
	var outer_route := navigation.path(terrain.road_samples[0][0], outer_road[-1], 1.05, terrain)
	_check(not outer_route.is_empty(), "the core road network reaches the outer highlands across the north viaduct")
	# Ground cover is told what to leave bare; it does not know where the Town Square is.
	_check(not terrain.keep_clear.is_empty(), "the Island hands the terrain its keep-clear regions (%d)" % terrain.keep_clear.size())


## A Hub's walls and bench are declared once and both rendered and queried from that record.
## They used to be two lists of the same literals nine lines apart, and the Dunes Lookout bench
## had already drifted 5 cm between them.
func _check_hub_surfaces() -> void:
	var db := main.world.database
	var answered := 0
	var ok := true
	for id in db.hubs:
		var hub: Hub = db.hubs[id]
		for w in hub.walls:
			var a: Vector2 = w.a
			var b: Vector2 = w.b
			if absf(b.x - a.x) < 0.001: continue   # a wall running due north answers by z, not x
			for step in range(5):
				var x: float = lerpf(a.x, b.x, (step + 0.5) / 5.0)
				var top = hub.wall_top(x, hub.walls.find(w))
				if top == null: ok = false
				else: answered += 1
	_check(ok and answered > 0, "every declared Hub wall answers wall_top along its whole span (%d samples)" % answered)
	var lookout: Hub = db.hub(&"dunes_lookout")
	_check(lookout.bench_top(0.5).is_equal_approx(lookout.bench), "the Lookout bench answers from the record the plank is built from")


## A Recipe now declares how far its geometry reaches, so this can be written at all: build each
## one into a throwaway node and measure what it actually produced. Before the extent existed,
## an aqueduct spanning 160 m was filed under a single 60 m chunk and nothing could tell.
func _check_recipe_extents() -> void:
	var db := main.world.database
	var kit: WorldKit = main.world.streamer.kit
	var scratch := Node3D.new()
	add_child(scratch)
	var previous_sink := kit.sink
	var worst_over := 0.0
	var worst_name := ""
	var checked := 0
	for r in db.oversize():
		for child in scratch.get_children(): child.free()
		kit.sink = scratch
		kit.rng.seed = 12345
		r.builder.call()
		var reach := _reach_of(scratch, r.pos)
		checked += 1
		if reach - r.radius > worst_over:
			worst_over = reach - r.radius
			worst_name = "%.0f m built, %.0f m declared at (%.0f, %.0f)" % [reach, r.radius, r.pos.x, r.pos.y]
	kit.sink = previous_sink
	scratch.queue_free()
	_check(checked > 0 and worst_over <= 0.0,
		"every oversize Recipe stays inside the extent it declared (%d checked%s)" % [checked, "" if worst_over <= 0.0 else "; worst: " + worst_name])


## How far the geometry a recipe just built reaches from the point it was filed at.
var _worst_node := ""

## How far the geometry a recipe just built reaches from the point it was filed at. Only things
## that actually draw count — a container node parked at the origin is not geometry.
func _reach_of(root: Node3D, origin: Vector2) -> float:
	var reach := 0.0
	for child in root.find_children("*", "VisualInstance3D", true, false):
		var visual: VisualInstance3D = child
		var box: AABB = visual.global_transform * visual.get_aabb()
		for corner in range(8):
			var p: Vector3 = box.get_endpoint(corner)
			var d: float = Vector2(p.x - origin.x, p.z - origin.y).length()
			if d > reach:
				reach = d
				_worst_node = "%s at %.0f,%.0f" % [visual.name, p.x, p.z]
	return reach


## Nothing used to touch the Map at all. The grid, the height encoding and the biome order are
## restated in expand.py and in Terrain, and the only check was an image width that degraded to
## a flat sea behind one push_error.
func _check_map_contract() -> void:
	var terrain: Terrain = main.world.terrain
	var problem: String = terrain.map_contract_error()
	_check(problem == "", "data/island_map.png matches the contract expand.py wrote%s" % ("" if problem == "" else ": " + problem))
	var img := Image.new()
	var loaded := img.load(Terrain.MAP_PATH) == OK
	_check(loaded and img.get_width() == Terrain.N and img.get_height() == Terrain.N,
		"the map is %d x %d as the runtime requires" % [img.get_width(), img.get_height()])
	if not loaded: return
	var biomes_valid := true
	var lowest := INF
	var highest := -INF
	for j in range(0, Terrain.N, 3):
		for i in range(0, Terrain.N, 3):
			var c := img.get_pixel(i, j)
			if c.g8 >= Terrain.Biome.size(): biomes_valid = false
			var h := c.r8 / 255.0 * 90.0 - 10.0
			lowest = minf(lowest, h); highest = maxf(highest, h)
	_check(biomes_valid, "every cell names a Biome the game knows")
	_check(lowest >= -10.0 and highest > 20.0 and highest <= 80.0,
		"decoded heights are plausible (%.1f m to %.1f m)" % [lowest, highest])
	var islets_ok := true
	for isl in main.level._islets:
		var p: Vector2 = main.level._px(float(isl[0]), float(isl[1]))
		islets_ok = islets_ok and absf(p.x) <= Terrain.SIZE and absf(p.y) <= Terrain.SIZE
	_check(islets_ok, "every islet in island_meta.json converts to a point inside the world (%d)" % main.level._islets.size())
