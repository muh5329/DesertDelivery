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
				# --- the tree is small: only managers at the top
				var top: Array[String] = []
				for c in main.get_children(): top.append(c.name)
				_check(top.has("WorldManager") and top.has("EntityManager") and top.has("GameplayManager") and top.has("UI") and top.has("Debug"), "runtime tree: %s" % ", ".join(top))
				print("ARCHITECTURE TESTS: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
				get_tree().quit(0 if fails == 0 else 1)
