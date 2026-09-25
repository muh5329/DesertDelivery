class_name NightLights
extends Node3D
## Real light from the lamps, near the camera only (M-12). Every street lamp, lantern and wall
## lamp glows by its emissive glass everywhere (arch.gdshader, `bulb_material`); only the nearest
## few also cast light, from a small pool of OmniLight3Ds moved onto them at a few Hz and faded
## in and out at the edge of the range, so nothing pops.
##
## A source is any node in the group `night_lights` with the meta `night_lights`
## (PackedVector3Array of lamp positions in the node's local space); `register(node, points)` sets
## both. Nodes leave the group when they are freed, so a streamed chunk takes its lamps with it.
## The budget (`budget`, lights) and the range come from the quality preset (GraphicsSettings).

const GROUP := &"night_lights"
const COLOR := Color(1.0, 0.72, 0.42)

var budget := 12
var reach := 70.0                 # lights beyond this are never picked
var energy := 1.6
var light_range := 13.0
var _pool: Array[OmniLight3D] = []
var _t := 0.0
static var _bulb: ShaderMaterial


## Mark `node` as holding lamps at `points` (its local space).
static func register(node: Node, points: PackedVector3Array) -> void:
	if points.is_empty(): return
	node.set_meta("night_lights", points)
	node.add_to_group(GROUP)


## The shared glass of every stand-alone lamp (lamp posts, bridge lamps): off by day, a warm glow
## while the lamps are on (the global `dn_lamps`).
static func bulb_material() -> ShaderMaterial:
	if _bulb: return _bulb
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
global uniform float dn_lamps;
uniform vec3 glass : source_color = vec3(1.0, 0.94, 0.78);
uniform vec3 glow : source_color = vec3(1.0, 0.72, 0.38);
uniform float power = 7.0;
void fragment() {
	ALBEDO = glass * mix(0.85, 0.35, dn_lamps);
	ROUGHNESS = 0.25;
	SPECULAR = 0.6;
	EMISSION = glow * power * dn_lamps;
}
"""
	_bulb = ShaderMaterial.new(); _bulb.shader = sh
	return _bulb


func _ready() -> void:
	name = "NightLights"
	_resize()


func set_budget(n: int) -> void:
	budget = maxi(n, 0)
	if is_inside_tree(): _resize()


func _resize() -> void:
	while _pool.size() < budget:
		var l := OmniLight3D.new()
		l.light_color = COLOR
		l.omni_range = light_range
		l.omni_attenuation = 1.4
		l.shadow_enabled = false
		l.light_volumetric_fog_energy = 0.6
		l.light_specular = 0.4
		l.distance_fade_enabled = true
		l.distance_fade_begin = reach * 0.75
		l.distance_fade_length = reach * 0.25
		l.visible = false
		add_child(l)
		_pool.append(l)
	while _pool.size() > budget:
		var l: OmniLight3D = _pool.pop_back()
		l.queue_free()


func _process(delta: float) -> void:
	var dn: DayNight = get_parent() as DayNight
	var on := dn.lamps if dn else 0.0
	if on <= 0.001 or budget == 0:
		for l in _pool:
			l.visible = false
			l.set_meta("w", 0.0)
		return
	_t -= delta
	if _t <= 0.0:
		_t = 0.25
		_pick()
	# each light eases toward its weight: a lamp that joins or leaves the set fades, never pops
	for l in _pool:
		var w := move_toward(float(l.get_meta("w", 0.0)), float(l.get_meta("goal", 0.0)), delta * 3.0)
		l.set_meta("w", w)
		l.light_energy = energy * on * w
		l.visible = w > 0.002


## The nearest `budget` lamps to the camera (weighted down toward the edge of the reach). A light
## already on a lamp that is still wanted stays there; the others fade out and are then reused.
func _pick() -> void:
	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp else null
	if cam == null: return
	var c := cam.global_position
	var r2 := reach * reach
	var found: Array = []
	for n in get_tree().get_nodes_in_group(GROUP):
		var node := n as Node3D
		if node == null or not node.is_visible_in_tree(): continue
		var xf := node.global_transform
		var pts: PackedVector3Array = node.get_meta("night_lights", PackedVector3Array())
		# a quick reject on the node's first lamp: a source holds one street or one building group
		if pts.is_empty() or (xf * pts[0]).distance_squared_to(c) > r2 * 9.0: continue
		for p: Vector3 in pts:
			var w: Vector3 = xf * p
			var d2 := w.distance_squared_to(c)
			if d2 < r2: found.append([w, d2])
	found.sort_custom(func(a, b): return a[1] < b[1])
	found.resize(mini(budget, found.size()))
	var used: Array[bool] = []; used.resize(found.size()); used.fill(false)
	var free: Array[OmniLight3D] = []
	for l in _pool:
		var kept := false
		for i in range(found.size()):
			if not used[i] and l.global_position.distance_squared_to(found[i][0]) < 0.04 and float(l.get_meta("w", 0.0)) > 0.0:
				used[i] = true; kept = true
				l.set_meta("goal", 1.0 - smoothstep(reach * 0.7, reach, sqrt(float(found[i][1]))))
				break
		if not kept:
			l.set_meta("goal", 0.0)
			if float(l.get_meta("w", 0.0)) <= 0.002: free.append(l)
	for i in range(found.size()):
		if used[i] or free.is_empty(): continue
		var l: OmniLight3D = free.pop_back()
		l.global_position = found[i][0]
		l.set_meta("w", 0.0)
		l.set_meta("goal", 1.0 - smoothstep(reach * 0.7, reach, sqrt(float(found[i][1]))))


## How many lamps are casting light right now (tests, the F3 overlay).
func active() -> int:
	var n := 0
	for l in _pool:
		if l.visible: n += 1
	return n
