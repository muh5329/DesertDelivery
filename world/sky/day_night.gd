class_name DayNight
extends Node
## The island's light over the day (M-12). One clock (IslandLife's hour, or `set_hour`) decides the
## sun and the moon, and everything that is lit follows from that single state:
##   - the DirectionalLight "Sun" is the sun by day and the moon by night (one light, one shadow map:
##     it swaps while the sun is below the horizon and its energy is 0, so the swap never shows);
##   - the sky shader: gradient, sun disc and glow, the moon, stars, cloud colours;
##   - the environment: ambient, fog colour and sun scatter, exposure;
##   - the sea's own fog and horizon (it rebuilds the sky's horizon colour in its shader);
##   - the global shader uniforms every material that fakes light reads (project.godot
##     [shader_globals]): `dn_fill` scales the hand-made sky/ambient fills and emission floors
##     (leaves, arch kit, rocks, terrain litter, sea foam, far silhouettes), `dn_night` (0 day .. 1
##     night), `dn_lamps` (street lamps on), `dn_windows` (fraction of windows lit), `dn_sun_dir`.
## Day values are the reference look (WorldKit.Atmosphere) unchanged; the other key frames are by
## the sun's elevation, so dawn and dusk share one palette.
##
## Interface: setup(world), set_hour(h), hour, sun_elevation, night, lamps, windows, light_dir,
## lights (the NightLights pool), changed (signal, after every push).

signal changed

## The running game's cycle (vehicle lamps, fires and tools read it; null before the world boots).
static var now: DayNight

## The latitude and declination are chosen so that at REFERENCE_HOUR the sun stands exactly where
## the art passes put it (WorldKit.Atmosphere: 48 deg up, yaw -40 = south-west), so the reference
## look (reference/compare.py, tests/view.gd pins this hour) is the afternoon of the running day.
const LATITUDE := 45.7          # degrees: a northern Mediterranean island
const DECLINATION := 10.0       # late summer; the moon (full) sits opposite at -DECLINATION
const SOLAR_NOON := 13.0        # summer time: noon at 13:00, sunrise ~6:19, sunset ~19:41
const REFERENCE_HOUR := 14.728  # 14:44: the sun at Atmosphere.sun_elevation_deg / sun_yaw_deg (within 0.03 deg)

## Key frames by sun elevation (degrees). Colours are sRGB (as the sky/Atmosphere use them).
## sky_* = the sky shader's gradient, glow = the sun-side lobe, sun = the direct light,
## amb = the environment's ambient, fog = the fog colour, cloud = the flat cloud colour,
## fill = the multiplier on the materials' own fills (linear), exposure = tonemap exposure.
const KEYS := [
	{"el": -18.0, "top": Color("03060f"), "hor": Color("0d1628"), "zen": Color("02050d"), "energy": 1.0,
		"glow": Color("000000"), "glow_amt": 0.0, "wide": Color("000000"), "wide_amt": 0.0,
		"amb": Color("5d77b0"), "amb_e": 0.20, "fog": Color("0b1222"), "scatter": 0.0,
		"cloud": Color("141b2b"), "cloud_edge": Color("c8d4ff"), "fill": Vector3(0.07, 0.085, 0.14), "exposure": 0.95, "stars": 1.0},
	{"el": -9.0, "top": Color("08122b"), "hor": Color("2a2f4f"), "zen": Color("060e24"), "energy": 1.0,
		"glow": Color("5a3a5a"), "glow_amt": 0.2, "wide": Color("3a3350"), "wide_amt": 0.2,
		"amb": Color("6d7cb0"), "amb_e": 0.22, "fog": Color("181d33"), "scatter": 0.05,
		"cloud": Color("262a42"), "cloud_edge": Color("b0a8d0"), "fill": Vector3(0.10, 0.11, 0.17), "exposure": 0.92, "stars": 0.8},
	{"el": -4.0, "top": Color("1d3160"), "hor": Color("8a6682"), "zen": Color("172a58"), "energy": 1.0,
		"glow": Color("e0785a"), "glow_amt": 0.45, "wide": Color("8c6a8e"), "wide_amt": 0.35,
		"amb": Color("8d8cb4"), "amb_e": 0.28, "fog": Color("4f4f70"), "scatter": 0.25,
		"cloud": Color("6a5470"), "cloud_edge": Color("ffb090"), "fill": Vector3(0.26, 0.25, 0.34), "exposure": 0.82, "stars": 0.15},
	{"el": 0.5, "top": Color("4270aa"), "hor": Color("f59a68"), "zen": Color("2b5692"), "energy": 1.05,
		"glow": Color("ff8a48"), "glow_amt": 0.75, "wide": Color("ffb28c"), "wide_amt": 0.5,
		"amb": Color("c7a79e"), "amb_e": 0.36, "fog": Color("b58f86"), "scatter": 0.55,
		"cloud": Color("f0a07e"), "cloud_edge": Color("ffc59a"), "fill": Vector3(0.62, 0.52, 0.50), "exposure": 0.72, "stars": 0.0},
	{"el": 7.0, "top": Color("5b98d0"), "hor": Color("f0cda6"), "zen": Color("3a78b8"), "energy": 1.12,
		"glow": Color("ffc07a"), "glow_amt": 0.35, "wide": Color("ffd8b0"), "wide_amt": 0.3,
		"amb": Color("d6c7b4"), "amb_e": 0.42, "fog": Color("b3b2b8"), "scatter": 0.4,
		"cloud": Color("fff0dc"), "cloud_edge": Color("fff0d8"), "fill": Vector3(0.88, 0.84, 0.78), "exposure": 0.64, "stars": 0.0},
	{"el": 20.0, "day": true},
]

## Direct light by elevation: [el, energy multiplier on Atmosphere.sun_energy, colour].
const SUN_KEYS := [
	[-4.0, 0.0, Color("ff7a3a")], [0.5, 0.35, Color("ff8a48")], [4.0, 0.62, Color("ffb070")],
	[10.0, 0.85, Color("ffd8a6")], [22.0, 1.0, Color("fff0d3")],
]
const MOON_COLOR := Color("aebfff")
const MOON_ENERGY := 0.34

var hour := 9.5
var sun_elevation := 0.0
var moon_elevation := 0.0
var night := 0.0
var lamps := 0.0
var windows := 0.0
var light_dir := Vector3.UP               # toward whichever body drives the light
var sun_dir := Vector3.UP
var moon_dir := Vector3.DOWN
var palette: Dictionary = {}
var lights: NightLights
var world: Node
var _sun: DirectionalLight3D
var _env: Environment
var _sky_mat: ShaderMaterial
var _sea_mat: ShaderMaterial
var _day: Dictionary = {}
var _pushed_hour := -100.0
var _sky_pushed := -100.0
var _override := -1.0


func setup(p_world: Node) -> void:
	world = p_world
	name = "DayNight"
	now = self
	var env_root: Node = p_world.environment
	for c in env_root.get_children():
		if c is WorldEnvironment: _env = (c as WorldEnvironment).environment
		elif c is DirectionalLight3D and _sun == null: _sun = c
	if _sun == null and p_world.island: _sun = p_world.island.sun
	if _env and _env.sky and _env.sky.sky_material is ShaderMaterial: _sky_mat = _env.sky.sky_material
	var sea := env_root.get_node_or_null("Sea") as MeshInstance3D
	if sea and sea.material_override is ShaderMaterial: _sea_mat = sea.material_override
	var A: Dictionary = WorldKit.Atmosphere
	_day = {"top": A.sky_top, "hor": A.sky_horizon, "zen": A.sky_zenith, "energy": A.sky_energy,
		"glow": A.sky_glow_color, "glow_amt": A.sky_glow_amount, "wide": A.sky_glow_wide_color, "wide_amt": A.sky_glow_wide,
		"amb": A.ambient_color, "amb_e": A.ambient_energy, "fog": A.fog_color, "scatter": A.fog_sun_scatter,
		"cloud": A.cloud_base, "cloud_edge": A.cloud_mul_edge, "fill": Vector3.ONE, "exposure": A.exposure, "stars": 0.0}
	lights = NightLights.new(); add_child(lights)
	_build_beams(p_world)
	var cli_hour := -1.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hour="): cli_hour = float(a.substr(7))
	if cli_hour >= 0.0: _override = cli_hour
	set_hour(_override if _override >= 0.0 else hour, true)


## The lighthouses' beams are resident (seen across the bay long before the chunk streams in):
## the core's, every plan lighthouse landmark, and the lighthouse plots (Puerto Alto's mole).
func _build_beams(w: Node) -> void:
	var root := Node3D.new(); root.name = "LighthouseBeams"; add_child(root)
	var db: WorldDatabase = w.database
	if db.locations.has(&"lighthouse"):
		LighthouseBeam.attach(root, db.location_pos(&"lighthouse") + Vector3(0, 19.6, 0), 0.0)
	var outer: OuterWorld = w.outer
	if outer == null or not outer.ok: return
	var plan: Dictionary = outer.plan()
	for lm: Dictionary in plan.get("landmarks", []):
		if lm.kind != "lighthouse" or lm.get("plot", false): continue
		var x := float(lm.pos[0]); var z := float(lm.pos[2])
		LighthouseBeam.attach(root, Vector3(x, outer.height_at(x, z) + 19.6, z), x * 0.013)
	for group in ["towns", "hamlets"]:
		for t: Dictionary in plan.get(group, []):
			for p: Dictionary in t.plots:
				if p.get("kind", "") == "lighthouse":
					LighthouseBeam.attach(root, Vector3(float(p.x), float(p.y) + 17.15, float(p.z)), float(p.x) * 0.013)


func _exit_tree() -> void:
	if now == self: now = null


## Pin the clock (renders, tests): IslandLife's updates are ignored while pinned; < 0 unpins.
func pin_hour(h: float) -> void:
	_override = h
	if h >= 0.0: set_hour(h, true)


## The one entry point: the hour of the day (0..24). Cheap when nothing moved.
func set_hour(h: float, force := false) -> void:
	if _override >= 0.0 and not force: h = _override
	h = fposmod(h, 24.0)
	if not force and absf(h - _pushed_hour) < 0.004: return      # ~15 s of game time
	_pushed_hour = h
	hour = h
	sun_dir = _body_dir(h, DECLINATION, 0.0)
	moon_dir = _body_dir(h, -DECLINATION, 12.0)
	sun_elevation = rad_to_deg(asin(clampf(sun_dir.y, -1.0, 1.0)))
	moon_elevation = rad_to_deg(asin(clampf(moon_dir.y, -1.0, 1.0)))
	night = smoothstep(3.0, -7.0, sun_elevation)
	lamps = smoothstep(4.0, -1.5, sun_elevation)
	windows = night * _window_share(h) + (1.0 - night) * lamps * 0.35
	palette = _palette(sun_elevation)
	_push_light()
	_push_env(force)
	_push_globals()
	changed.emit()


## How many windows are lit, by the hour: most in the evening, a few all night, some before dawn.
static func _window_share(h: float) -> float:
	if h >= 17.0: return lerpf(0.62, 0.5, clampf((h - 21.0) / 2.5, 0.0, 1.0))
	if h < 1.5: return lerpf(0.5, 0.22, h / 1.5)
	if h < 4.5: return lerpf(0.22, 0.1, (h - 1.5) / 3.0)
	return lerpf(0.1, 0.4, clampf((h - 4.5) / 1.5, 0.0, 1.0))


## Direction toward a body on the celestial sphere (x east, y up, -z north).
static func _body_dir(h: float, dec_deg: float, shift_h: float) -> Vector3:
	var H := deg_to_rad((h - SOLAR_NOON - shift_h) * 15.0)
	var lat := deg_to_rad(LATITUDE); var dec := deg_to_rad(dec_deg)
	var up := sin(lat) * sin(dec) + cos(lat) * cos(dec) * cos(H)
	var east := -cos(dec) * sin(H)
	var north := cos(lat) * sin(dec) - sin(lat) * cos(dec) * cos(H)
	return Vector3(east, up, -north).normalized()


func _palette(el: float) -> Dictionary:
	var keys: Array = KEYS
	if el <= float(keys[0].el): return keys[0]
	for i in range(1, keys.size()):
		var b: Dictionary = keys[i]
		if el <= float(b.el) or i == keys.size() - 1:
			var a: Dictionary = keys[i - 1]
			var bb: Dictionary = _day if b.has("day") else b
			if el >= float(b.el): return bb
			var t := smoothstep(0.0, 1.0, (el - float(a.el)) / (float(b.el) - float(a.el)))
			var out := {}
			for k in bb:
				var va = a[k]; var vb = bb[k]
				if va is Color: out[k] = (va as Color).lerp(vb, t)
				elif va is Vector3: out[k] = (va as Vector3).lerp(vb, t)
				else: out[k] = lerpf(float(va), float(vb), t)
			return out
	return _day


func _sun_light(el: float) -> Array:
	var k: Array = SUN_KEYS
	if el <= float(k[0][0]): return [0.0, k[0][2]]
	for i in range(1, k.size()):
		if el <= float(k[i][0]):
			var t := (el - float(k[i - 1][0])) / (float(k[i][0]) - float(k[i - 1][0]))
			return [lerpf(k[i - 1][1], k[i][1], t), (k[i - 1][2] as Color).lerp(k[i][2], t)]
	return [1.0, k[k.size() - 1][2]]


func _push_light() -> void:
	if _sun == null: return
	var A: Dictionary = WorldKit.Atmosphere
	var use_sun := sun_elevation > -4.0
	var energy := 0.0
	var col: Color = A.sun_color
	if use_sun:
		var sl := _sun_light(sun_elevation)
		energy = float(A.sun_energy) * float(sl[0])
		col = sl[1]
		light_dir = sun_dir
	else:
		# the moon: faded in as the sky darkens, and as it climbs off the horizon
		energy = MOON_ENERGY * smoothstep(-4.0, -10.0, sun_elevation) * smoothstep(-2.0, 12.0, moon_elevation)
		col = MOON_COLOR
		light_dir = moon_dir if moon_dir.y > -0.05 else Vector3(moon_dir.x, 0.05, moon_dir.z).normalized()
	# never light the world from below the horizon (the ground would glow on its underside)
	var d := light_dir
	if d.y < 0.06: d = Vector3(d.x, 0.06, d.z).normalized()
	var up := Vector3.UP if absf(d.y) < 0.98 else Vector3.FORWARD
	_sun.basis = Basis.looking_at(-d, up)
	_sun.light_energy = energy
	_sun.light_color = col
	_sun.visible = energy > 0.001
	# the moon's shadows are soft; the sun keeps the tuned angular size
	if WorldKit.forward_plus(): _sun.light_angular_distance = 0.6 if use_sun else 1.6


func _push_env(force: bool) -> void:
	var P := palette
	if _env:
		_env.ambient_light_color = P.amb
		_env.ambient_light_energy = P.amb_e
		_env.fog_light_color = P.fog
		_env.fog_sun_scatter = P.scatter
		_env.tonemap_exposure = P.exposure
		# the volumetric fog's own albedo follows the fog, so the shafts stay in the evening's key
		if _env.volumetric_fog_enabled:
			var A: Dictionary = WorldKit.Atmosphere
			_env.volumetric_fog_albedo = (A.vol_fog_albedo as Color).lerp(P.fog.lightened(0.2), 1.0 - smoothstep(4.0, 20.0, sun_elevation))
	# the sky's radiance map is re-filtered on every change: push it at most every ~2 game minutes
	if _sky_mat and (force or absf(hour - _sky_pushed) > 0.03):
		_sky_pushed = hour
		_push_sky()
	if _sea_mat: _push_sea()


func _push_sky() -> void:
	var P := palette
	var m := _sky_mat
	m.set_shader_parameter("sky_top_color", P.top)
	m.set_shader_parameter("sky_horizon_color", P.hor)
	m.set_shader_parameter("sky_zenith_color", P.zen)
	m.set_shader_parameter("sky_energy", P.energy)
	m.set_shader_parameter("ground_horizon_color", P.hor)
	m.set_shader_parameter("ground_bottom_color", (P.hor as Color).darkened(0.06))
	m.set_shader_parameter("ground_energy", P.energy)
	m.set_shader_parameter("glow_color", P.glow)
	m.set_shader_parameter("glow_amount", P.glow_amt)
	m.set_shader_parameter("glow_wide_color", P.wide)
	m.set_shader_parameter("glow_wide", P.wide_amt)
	m.set_shader_parameter("cloud_base", P.cloud)
	m.set_shader_parameter("cloud_mul_edge", P.cloud_edge)
	m.set_shader_parameter("daylight", 1.0)
	m.set_shader_parameter("sun_vec", sun_dir)
	m.set_shader_parameter("moon_vec", moon_dir)
	var sl := _sun_light(sun_elevation)
	var sc: Color = sl[1]
	m.set_shader_parameter("sun_disc_color", Vector3(sc.srgb_to_linear().r, sc.srgb_to_linear().g, sc.srgb_to_linear().b) * float(WorldKit.Atmosphere.sun_energy) * maxf(float(sl[0]), 0.35))
	m.set_shader_parameter("night", night)
	m.set_shader_parameter("stars", P.stars)
	# the stars wheel round the pole with the hour
	m.set_shader_parameter("star_rot", Basis(Vector3(0, cos(deg_to_rad(LATITUDE)), -sin(deg_to_rad(LATITUDE))).normalized(), hour / 24.0 * TAU))


func _push_sea() -> void:
	var P := palette
	var m := _sea_mat
	var fog: Color = P.fog
	var fe := _env.fog_light_energy if _env else 1.0
	var fl := fog.srgb_to_linear() * fe
	m.set_shader_parameter("fog_color_lin", Vector3(fl.r, fl.g, fl.b))
	m.set_shader_parameter("fog_sun_scatter", P.scatter)
	var hor: Color = P.hor
	m.set_shader_parameter("sky_horizon_srgb", Vector3(hor.r, hor.g, hor.b))
	m.set_shader_parameter("sky_energy_mul", P.energy)
	var g: Color = P.glow; var w: Color = P.wide
	m.set_shader_parameter("sky_glow_srgb", Vector3(g.r, g.g, g.b))
	m.set_shader_parameter("sky_glow_wide_srgb", Vector3(w.r, w.g, w.b))
	m.set_shader_parameter("sky_glow_amount", P.glow_amt)
	m.set_shader_parameter("sky_glow_wide", P.wide_amt)
	m.set_shader_parameter("sky_zenith", hor.lerp(fog, 0.3))
	m.set_shader_parameter("sky_horizon", fog)
	m.set_shader_parameter("sun_dir", sun_dir if sun_elevation > -4.0 else moon_dir)
	m.set_shader_parameter("glow_dir", sun_dir)
	if _sun:
		m.set_shader_parameter("sun_color", _sun.light_color)
		m.set_shader_parameter("sun_energy", _sun.light_energy)


func _push_globals() -> void:
	RenderingServer.global_shader_parameter_set(&"dn_fill", palette.fill)
	RenderingServer.global_shader_parameter_set(&"dn_night", night)
	RenderingServer.global_shader_parameter_set(&"dn_lamps", lamps)
	RenderingServer.global_shader_parameter_set(&"dn_windows", windows)
	RenderingServer.global_shader_parameter_set(&"dn_sun_dir", light_dir)
