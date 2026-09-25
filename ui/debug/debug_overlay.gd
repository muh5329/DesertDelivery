class_name DebugOverlay
extends CanvasLayer
## F3: the open-world dashboard — fps / frame time, position, chunk, loaded chunks, entities and
## their simulation tiers, draw calls, biome, nearest location, save slot.
## F6: teleport to the next hub.   F7: reload the chunk under the player.   F8: toggle streaming.

var game: Game
var _label: Label
var _visible := false
var _hub_i := 0


func setup(g: Game) -> void:
	game = g
	layer = 20
	_label = Label.new()
	_label.position = Vector2(12, 120)
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.9))
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_label)
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if game.mayor != null and game.mayor.active: return
	if not (event is InputEventKey and event.pressed and not event.echo): return
	match event.keycode:
		KEY_F3:
			_visible = not _visible
			visible = _visible
		KEY_F6:
			game.relocate("Teleporting", teleport_next_hub)
		KEY_F7:
			reload_chunk_under_player()
		KEY_F8:
			game.world.streamer.enabled = not game.world.streamer.enabled
			Events.message.emit("Streaming %s" % ("on" if game.world.streamer.enabled else "off"), 2.0)


func teleport_next_hub() -> void:
	var ids: Array = game.world.database.hubs.keys()
	if ids.is_empty(): return
	_hub_i = (_hub_i + 1) % ids.size()
	var hub: Hub = game.world.database.hubs[ids[_hub_i]]
	var sp := game.world.road_spawn(hub.centre3(), hub.ring_pos)
	game.bike.set_parked(false)
	game.bike.place(sp.pos, sp.forward)
	game.player.place(sp.pos + Vector3(1.2, 0, 0), sp.forward)
	if game.rider.is_on_foot(): game.rider.request_mount()
	game.cam.snap_to_target()
	game.world.streamer.load_all_pending()
	Events.message.emit("Teleported to %s" % String(ids[_hub_i]), 2.0)


func reload_chunk_under_player() -> void:
	var st := game.world.streamer
	var c: Vector2i = st.db.chunk_of_pos(st.focus_position())
	if st.loaded.has(c):
		st._unload(c)
		st._load(c)
		Events.message.emit("Reloaded chunk %s" % str(c), 2.0)


## The hour, the lamp lights in use, texture memory and the preset (M-12, m-4, m-14).
func _light_line() -> String:
	var dn: DayNight = game.world.day_night
	if dn == null: return ""
	return "%02d:%02d  sun %.0f deg  night %.2f  lamp lights %d/%d   textures %.0f MB (arch %.0f MB)   quality %s" % [int(dn.hour), int(fmod(dn.hour, 1.0) * 60.0),
		dn.sun_elevation, dn.night, dn.lights.active(), dn.lights.budget, Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
		ArchMaterials.bytes_used / 1048576.0, GraphicsSettings.NAMES[GraphicsSettings.level]]


## The shared mesh caches that grow with the towns visited (m-4: bounded by the kit's variety).
func _cache_line() -> String:
	return "caches: arch modules %d   person parts %d   rocks %d   texture copies %d" % [ArchModules._cache.size(),
		PersonBuilder._parts.size(), RockGen.cache_size(), TexMips._cache.size()]


func _process(_delta: float) -> void:
	if not _visible or game == null: return
	var st := game.world.streamer
	var s := st.stats()
	var p := st.focus_position()
	var tiers := game.entities.tier_counts()
	var db := game.world.database
	var chunk_ms: int = 0
	if st.loaded.has(s.focus): chunk_ms = st.loaded[s.focus].build_ms
	var lines := [
		"fps %d   frame %.1f ms   physics %d Hz" % [Engine.get_frames_per_second(), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Engine.physics_ticks_per_second],
		"pos (%.1f, %.1f, %.1f)   chunk %s   %s" % [p.x, p.y, p.z, str(s.focus), game.rider.Mode.keys()[game.rider.mode]],
		"chunks loaded %d / %d   pending %d   build %d ms (this chunk %d ms)   streaming %s" % [s.loaded, s.total, s.pending, s.build_ms, chunk_ms, "on" if st.enabled else "off"],
		"entities %d   tiers FULL %d  REDUCED %d  ABSTRACT %d  DORMANT %d" % [game.entities.count(), tiers[0], tiers[1], tiers[2], tiers[3]],
		"nodes %d   objects %d   draw calls %d   primitives %d" % [game.get_tree().get_node_count(), Performance.get_monitor(Performance.OBJECT_COUNT), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)],
		"biome %s   near %s   recipes %d" % [Terrain.Biome.keys()[game.world.terrain.biome_at(p.x, p.z)], String(db.nearest_location(p)), db.record_count],
		"job %s -> %s   deliveries %d   save: %s" % [String(game.gm.target_location()), game.gm.target_name(), game.gm.deliveries, "quick" if Saves.has_save("quick") else "none"],
		_light_line(),
		_cache_line(),
		"F3 hide   F5 save   F9 load   F6 next hub   F7 reload chunk   F8 streaming   F10 graphics",
	]
	_label.text = "\n".join(lines)
