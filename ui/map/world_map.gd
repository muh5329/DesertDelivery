class_name WorldMap
extends Node
## The map service behind the minimap (HUD) and the full-screen map (M): the baked map textures
## (data/minimap, world/mapgen/minimap.py), what the courier has discovered, the waypoint and the
## minimap's settings, and the dynamic markers both views draw.
##
## Interface:
##   warm() (static, at boot)   decode + mipmap + compress the textures on a worker thread
##   finish()                   make the textures (main thread; waits for the worker)
##   overview / detail          Texture2D (null headless), meta (map.json), apply_to(material)
##   world_to_uv(p) / uv_of(x, z)       the overview's uv of a world point (north, -z, up)
##   waypoint, has_waypoint, set_waypoint(p), clear_waypoint()     (saved as "map")
##   zoom_level (0 close .. 2 far), cycle_zoom(), rotate (heading-up), toggle_rotate()
##   discovered: camp id -> true (a camp is on the map once the courier has come within 450 m)
##   markers(center, radius) -> Array of {kind, pos: Vector2 (x, z), ...} to draw
##   labels(center, radius, zoom_m) -> Array of {text, pos, size}
##   load_image(which) (static)  the decoded image, for tests and tools

signal changed

const DIR := "res://data/minimap/"
## Base view radius (m from the centre to the minimap's rim) per zoom level.
const ZOOM_RADII: Array[float] = [160.0, 450.0, 1300.0]
const ZOOM_NAMES: Array[String] = ["close", "medium", "far"]
const DISCOVER_RADIUS := 450.0
## Ports: lanes and ships show on the minimap within this distance of a port's berth.
const PORT_AREA := 1800.0

static var _task := -1
static var _images: Dictionary = {}          # "overview" / "detail" -> Image (worker output)
static var _meta: Dictionary = {}

var game: Game
var meta: Dictionary = {}
var overview: Texture2D
var detail: Texture2D
var waypoint := Vector3.ZERO
var has_waypoint := false
var zoom_level := 1
var rotate := true
var discovered: Dictionary = {}
var _check_t := 0.0
var _labels: Array = []                      # {text, pos, rank}: towns 2, hamlets 1, core places 0


## Start decoding the map on a worker (Game._boot calls this before the first stage).
static func warm() -> void:
	if _task >= 0 or DisplayServer.get_name() == "headless": return
	_meta = read_meta()
	if _meta.is_empty(): return
	_task = WorkerThreadPool.add_task(_decode, false, "minimap decode")


static func read_meta() -> Dictionary:
	var f := FileAccess.open(DIR + "map.json", FileAccess.READ)
	if f == null: return {}
	var d: Variant = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


## The decoded image ("overview" or "detail"), or null when the bake is missing.
static func load_image(which: String) -> Image:
	var m := read_meta()
	if m.is_empty(): return null
	var file: String = m.overview.file if which == "overview" else m.detail.file
	var bytes := FileAccess.get_file_as_bytes(DIR + file)
	if bytes.is_empty(): return null
	var img := Image.new()
	var err := img.load_webp_from_buffer(bytes) if file.ends_with(".webp") else img.load_png_from_buffer(bytes)
	return img if err == OK else null


static var decode_ms := 0
static var wait_ms := 0


static func _decode() -> void:
	var t0 := Time.get_ticks_msec()
	for which in ["overview", "detail"]:
		var img := load_image(which)
		if img == null: continue
		img.convert(Image.FORMAT_RGBA8)
		img.generate_mipmaps()
		# the 4096^2 overview goes to the GPU as DXT1 (11 MB with its mips instead of 85 MB); the
		# insets stay exact so the close zoom's street lines are crisp
		if which == "overview": img.compress(Image.COMPRESS_S3TC, Image.COMPRESS_SOURCE_SRGB)
		_images[which] = img
	decode_ms = Time.get_ticks_msec() - t0


func setup(p_game: Game) -> void:
	game = p_game
	name = "WorldMap"
	meta = _meta if not _meta.is_empty() else read_meta()
	_build_labels()


## The textures, made on the main thread from the worker's images (waits for it if need be).
func finish() -> void:
	var t0 := Time.get_ticks_msec()
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	wait_ms = Time.get_ticks_msec() - t0
	if _images.has("overview"): overview = ImageTexture.create_from_image(_images.overview)
	if _images.has("detail"): detail = ImageTexture.create_from_image(_images.detail)
	if overview: print("[map] textures: decoded on a worker in %d ms, the boot waited %d ms, uploaded in %d ms" % [decode_ms, wait_ms, Time.get_ticks_msec() - t0 - wait_ms])
	_images.clear()


func ready() -> bool:
	return not meta.is_empty()


## Hand the map's textures and insets to a map.gdshader material.
func apply_to(mat: ShaderMaterial) -> void:
	if meta.is_empty(): return
	mat.set_shader_parameter("overview", overview)
	mat.set_shader_parameter("detail", detail)
	var w: Array = meta.world
	mat.set_shader_parameter("world", Vector3(w[0], w[1], w[2]))
	var insets: Array = meta.detail.insets
	var size: Array = meta.detail.size
	var iw := PackedVector4Array(); var iu := PackedVector4Array()
	for k in range(mini(insets.size(), 24)):
		var r: Dictionary = insets[k]
		iw.append(Vector4(r.world[0], r.world[1], r.world[2], r.world[3]))
		iu.append(Vector4(float(r.px[0]) / size[0], float(r.px[1]) / size[1], float(r.px[2]) / size[0], float(r.px[3]) / size[1]))
	while iw.size() < 24: iw.append(Vector4.ZERO); iu.append(Vector4.ZERO)
	mat.set_shader_parameter("inset_world", iw)
	mat.set_shader_parameter("inset_uv", iu)
	mat.set_shader_parameter("inset_count", mini(insets.size(), 24))


func uv_of(x: float, z: float) -> Vector2:
	var w: Array = meta.world if not meta.is_empty() else [-12500.0, -12500.0, 25000.0]
	return Vector2((x - float(w[0])) / float(w[2]), (z - float(w[1])) / float(w[2]))


func world_to_uv(p: Vector3) -> Vector2:
	return uv_of(p.x, p.z)


# ---------------------------------------------------------------- state
func set_waypoint(p: Vector3) -> void:
	waypoint = Vector3(p.x, 0.0, p.z)
	if game and game.world: waypoint.y = game.world.terrain.height_at(p.x, p.z)
	has_waypoint = true
	changed.emit()


func clear_waypoint() -> void:
	has_waypoint = false
	changed.emit()


func cycle_zoom() -> int:
	zoom_level = (zoom_level + 1) % ZOOM_RADII.size()
	changed.emit()
	return zoom_level


func toggle_rotate() -> bool:
	rotate = not rotate
	changed.emit()
	return rotate


func save_state() -> Dictionary:
	return {"waypoint": [waypoint.x, waypoint.y, waypoint.z] if has_waypoint else [], "zoom": zoom_level,
		"rotate": rotate, "discovered": discovered.keys()}


func load_state(d: Dictionary) -> bool:
	var wp: Array = d.get("waypoint", []) if d.get("waypoint") is Array else []
	has_waypoint = wp.size() == 3
	if has_waypoint: waypoint = Vector3(wp[0], wp[1], wp[2])
	zoom_level = clampi(int(d.get("zoom", 1)), 0, ZOOM_RADII.size() - 1)
	rotate = bool(d.get("rotate", true))
	discovered.clear()
	for id in d.get("discovered", []): discovered[StringName(str(id))] = true
	changed.emit()
	return true


func load_missing_state() -> void:
	has_waypoint = false
	discovered.clear()


# ---------------------------------------------------------------- discovery
func _process(delta: float) -> void:
	if game == null or not game.booted: return
	_check_t -= delta
	if _check_t > 0.0: return
	_check_t = 0.5
	var enc := game.encounters
	if enc == null: return
	var c := game.rider.courier().global_position
	for id in enc.camps:
		if discovered.has(id) or String(id).begins_with("ambush"): continue
		var p: Vector3 = enc.camps[id].pos
		if Vector2(p.x - c.x, p.z - c.z).length() < DISCOVER_RADIUS or enc.is_cleared(id) or enc.is_spawned(id):
			discovered[id] = true


# ---------------------------------------------------------------- markers
func _build_labels() -> void:
	_labels.clear()
	var plan: Dictionary = {}
	if game and game.world and game.world.outer and game.world.outer.ok: plan = game.world.outer.plan()
	for t in plan.get("towns", []): _labels.append({"text": t.name, "pos": Vector2(t.center[0], t.center[1]), "rank": 2})
	for t in plan.get("hamlets", []): _labels.append({"text": t.name, "pos": Vector2(t.center[0], t.center[1]), "rank": 1})
	if game and game.world:
		var db := game.world.database
		for id in db.hubs:
			var h: Hub = db.hubs[id]
			_labels.append({"text": String(id).capitalize(), "pos": Vector2(h.centre.x, h.centre.y), "rank": 0})


## Place names inside a view: towns always, hamlets from the medium zoom in, the core's hubs
## only close up (`view_radius`: metres from the centre to the view's edge).
func labels(center: Vector2, reach: float, view_radius: float) -> Array:
	var out: Array = []
	for l in _labels:
		var rank: int = l.rank
		if rank == 1 and view_radius > 2600.0: continue
		if rank == 0 and view_radius > 700.0: continue
		if (l.pos as Vector2).distance_to(center) > reach: continue
		out.append(l)
	return out


## The dynamic markers round `center` within `reach` metres (plus the delivery target and the
## waypoint wherever they are: the views pin those to their edge).
func markers(center: Vector2, reach: float, show_lanes := false, counters := true) -> Array:
	var out: Array = []
	if game == null or not game.booted: return out
	var near := func(p: Vector3) -> bool: return Vector2(p.x, p.z).distance_to(center) <= reach
	# fuel stations and courier counters
	if game.journey and game.journey.services:
		for s in game.journey.services.stations:
			var p: Vector3 = s.pos
			if s.kind == "counter" and not counters: continue
			if near.call(p): out.append({"kind": &"counter" if s.kind == "counter" else &"fuel", "pos": Vector2(p.x, p.z), "name": s.get("name", "")})
	# bandit camps and pirate coves the courier has found
	var enc := game.encounters
	if enc:
		for id in discovered:
			if not enc.camps.has(id): continue
			var r: Dictionary = enc.camps[id]
			var p: Vector3 = r.pos
			if near.call(p): out.append({"kind": &"cove" if String(r.get("kind", "")) == "pirate" else &"camp", "pos": Vector2(p.x, p.z), "cleared": enc.is_cleared(id)})
	# colony halls
	var econ: ColonyEconomy = game.colony.economy if game.colony else null
	if econ:
		for cid in econ.towns:
			var t: ColonyTown = econ.towns[cid]
			if not t.founded or t.hall == Vector3.ZERO: continue
			if near.call(t.hall): out.append({"kind": &"colony", "pos": Vector2(t.hall.x, t.hall.z), "name": t.display_name})
		# shipping: in a port's area (or on the full map), its lanes and the ships on them
		var sh: ShippingNetwork = econ.shipping
		if sh and sh.ready:
			var in_port := show_lanes
			if not in_port:
				for pid in sh.ports:
					var berth: Vector3 = sh.ports[pid].berth
					if Vector2(berth.x, berth.z).distance_to(center) < PORT_AREA: in_port = true; break
			if in_port:
				for l in sh.lanes:
					var r := sh.route(l.from, l.to)
					if not r.is_empty(): out.append({"kind": &"lane", "points": r.points})
				for s in sh.ships:
					var pose := sh.ship_pose(s)
					var at: Vector2 = pose[0]
					if at.distance_to(center) <= reach: out.append({"kind": &"ship", "pos": at, "heading": pose[1], "docked": pose[2]})
	# the vehicles the courier is not driving
	var rider := game.rider
	for v in [game.bike, game.jeep]:
		if v == null or (v == rider.vehicle and not rider.is_on_foot()): continue
		if near.call(v.global_position): out.append({"kind": &"bike" if v == game.bike else &"jeep", "pos": Vector2(v.global_position.x, v.global_position.z), "heading": _fwd(v)})
	var towed_along: bool = game.hitch != null and game.hitch.tow_vehicle() != null and game.hitch.tow_vehicle() == rider.vehicle and not rider.is_on_foot()
	if game.cart and not towed_along:
		var cp := game.cart.global_position
		if near.call(cp): out.append({"kind": &"cart", "pos": Vector2(cp.x, cp.z)})
	# the delivery: the pickup (until the parcel is collected) and the drop-off
	var gm := game.gm
	if gm and gm.stage != DeliverySystem.Stage.DONE and gm.current_job():
		var job := gm.current_job()
		if gm.stage == DeliverySystem.Stage.TO_PICKUP:
			var pp := gm.db.location_pos(job.from_location)
			out.append({"kind": &"pickup", "pos": Vector2(pp.x, pp.z), "target": true, "name": gm.db.location_name(job.from_location)})
		var dp := gm.db.location_pos(job.to_location)
		out.append({"kind": &"dropoff", "pos": Vector2(dp.x, dp.z), "target": gm.stage == DeliverySystem.Stage.TO_DROPOFF, "name": gm.db.location_name(job.to_location)})
	if has_waypoint: out.append({"kind": &"waypoint", "pos": Vector2(waypoint.x, waypoint.z), "target": true})
	return out


static func _fwd(n: Node3D) -> Vector2:
	var f: Vector3 = n.flat_forward() if n.has_method("flat_forward") else -n.global_transform.basis.z
	return Vector2(f.x, f.z)
