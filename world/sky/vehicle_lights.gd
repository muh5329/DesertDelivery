class_name VehicleLights
extends Node3D
## Head and tail lamps for a vehicle model (M-12): the model's lamp glass surfaces (by material
## name) glow while the lamps are on (`dn_lamps`), and the lamps light the road ahead:
##   - the courier's bike and jeep: a real SpotLight3D (shadows from the quality preset);
##   - traffic: a projected pool of light (a Decal's emission, Forward+) - no light per car.
## Dark by day: nothing is visible and the node does no work.
##
## VehicleLights.dress(model, spot) -> VehicleLights (added under `model`, forward = -Z).

const HEAD := ["Headlamp glass", "Car headlamp ivory", "Truck lamp ivory", "M_Lamp_White"]
const TAIL := ["Car tail red", "Amber signal", "M_Lamp_Red"]
const HEAD_COLOR := Color(1.0, 0.92, 0.76)

## The quality preset: shadows from the courier's headlight (GraphicsSettings).
static var spot_shadows := true
static var _head: ShaderMaterial
static var _tail: ShaderMaterial
static var _pool_tex: ImageTexture

var spot: SpotLight3D
var pool: Decal
var _t := 0.0
var _on := -1.0


static func dress(model: Node3D, with_spot: bool) -> VehicleLights:
	var vl := VehicleLights.new()
	vl.name = "VehicleLights"
	var heads: Array[Vector3] = []
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null: continue
		for i in range(mi.mesh.get_surface_count()):
			var mat := mi.get_active_material(i)
			if mat == null: continue
			var nm := mat.resource_name
			if nm in HEAD:
				mi.set_surface_override_material(i, head_material())
				var box := _surface_box(mi.mesh, i)
				if box.size != Vector3.ZERO: heads.append(_to_model(model, mi) * box.get_center())
			elif nm in TAIL:
				mi.set_surface_override_material(i, tail_material(nm))
	var front := Vector3(0, 0.9, -1.0)
	if not heads.is_empty():
		front = Vector3.ZERO
		for h in heads: front += h
		front /= heads.size()
	vl.position = front
	model.add_child(vl)
	if with_spot:
		vl.spot = SpotLight3D.new()
		vl.spot.light_color = HEAD_COLOR
		vl.spot.spot_range = 42.0
		vl.spot.spot_angle = 30.0
		vl.spot.spot_angle_attenuation = 1.6
		vl.spot.spot_attenuation = 0.9
		vl.spot.light_volumetric_fog_energy = 0.8
		vl.spot.shadow_enabled = spot_shadows
		vl.spot.shadow_bias = 0.05
		vl.spot.rotation_degrees = Vector3(-7.0, 0, 0)   # dipped a little toward the road
		vl.spot.position = Vector3(0, 0, -0.15)
		vl.spot.visible = false
		vl.add_child(vl.spot)
	else:
		vl.pool = Decal.new()
		vl.pool.size = Vector3(5.5, 5.0, 13.0)
		vl.pool.position = Vector3(0, -front.y + 1.0, -7.5)
		vl.pool.texture_emission = _pool_texture()
		vl.pool.modulate = HEAD_COLOR
		vl.pool.albedo_mix = 0.0
		vl.pool.upper_fade = 0.3; vl.pool.lower_fade = 0.3
		vl.pool.cull_mask = 1       # the road and the ground, not the cars or the people
		vl.pool.distance_fade_enabled = true
		vl.pool.distance_fade_begin = 120.0; vl.pool.distance_fade_length = 40.0
		vl.pool.visible = false
		vl.add_child(vl.pool)
	return vl


static func head_material() -> ShaderMaterial:
	if _head == null: _head = _lamp_material(Color(0.95, 0.94, 0.88), HEAD_COLOR, 9.0)
	return _head


static func tail_material(nm: String) -> ShaderMaterial:
	if nm == "Amber signal": return _lamp_material(Color(0.95, 0.55, 0.12), Color(1.0, 0.45, 0.05), 0.0)
	if _tail == null: _tail = _lamp_material(Color(0.6, 0.06, 0.05), Color(1.0, 0.06, 0.03), 3.5)
	return _tail


static func _lamp_material(glass: Color, glow: Color, power: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = NightLights.bulb_material().shader
	m.set_shader_parameter("glass", glass)
	m.set_shader_parameter("glow", glow)
	m.set_shader_parameter("power", power)
	return m


static func _surface_box(mesh: Mesh, i: int) -> AABB:
	var arr := mesh.surface_get_arrays(i)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	if v.is_empty(): return AABB()
	var box := AABB(v[0], Vector3.ZERO)
	for p in v: box = box.expand(p)
	return box


## `node`'s transform relative to `root` (works before either is in the tree).
static func _to_model(root: Node3D, node: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != root:
		if n is Node3D: xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


static func _pool_texture() -> ImageTexture:
	if _pool_tex: return _pool_tex
	var img := Image.create(64, 128, false, Image.FORMAT_RGBA8)
	for y in range(128):
		for x in range(64):
			# a long soft oval, brightest a little ahead of the lamps (the texture's +y is the far end)
			var u := (x - 31.5) / 32.0; var v := (y - 63.5) / 64.0
			var along := clampf(1.0 - absf(v - 0.15) * 1.1, 0.0, 1.0)
			var across := clampf(1.0 - u * u * (1.2 + 0.8 * (1.0 - v)), 0.0, 1.0)
			var k := pow(along, 1.5) * across * 0.8
			img.set_pixel(x, y, Color(k, k, k, 1.0))
	_pool_tex = ImageTexture.create_from_image(img)
	return _pool_tex


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0: return
	_t = 0.3
	var dn := DayNight.now
	var on := dn.lamps if dn else 0.0
	if absf(on - _on) < 0.01: return
	_on = on
	if spot:
		spot.visible = on > 0.01
		spot.light_energy = 3.2 * on
		spot.shadow_enabled = spot_shadows
	if pool:
		pool.visible = on > 0.01
		pool.emission_energy = 1.6 * on
