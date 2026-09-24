class_name OuterRivers
extends Node3D
## The outer world's rivers (plan.json `rivers`, traced and carved by world/mapgen/outer_water.py):
## each run is a polyline of [x, water level, z, width] from its head to the sea, the estuary or the
## lagoon. Drawn as resident ribbon meshes in ~1 km pieces (river.gdshader: flowing normals, depth
## tint against the bed, foam on the rapids and along the banks). Render only - the bed is carved
## into the ground, so the bike rides through the shallows and the roads cross on bridges.

const PIECE := 250                    # samples per mesh piece (~1 km)
const COLS := 5                       # vertices across the channel
const FAR := 7000.0

var outer: OuterWorld
var runs: Array = []                  # [{id, pts: PackedVector3Array, width: PackedFloat32Array}]
var total_km := 0.0
var material: ShaderMaterial
var channel: Dictionary = {}          # 4 m cell -> water level: cells under the water (flora keeps out, swimming)
const CELL := 4.0


func setup(p_outer: OuterWorld) -> void:
	outer = p_outer
	name = "OuterRivers"
	material = ShaderMaterial.new()
	material.shader = load("res://world/outer/river.gdshader")
	material.set_shader_parameter("noise_tex", OuterTerrainView._noise_texture())
	material.set_shader_parameter("sky_zenith", WorldKit.Atmosphere.sky_top)
	material.set_shader_parameter("sky_horizon", (WorldKit.Atmosphere.sky_horizon as Color).darkened(0.12))
	for r: Dictionary in outer.ground.plan.get("rivers", []):
		var pts := PackedVector3Array(); var wd := PackedFloat32Array()
		for q in r.points:
			pts.append(Vector3(q[0], q[1], q[2])); wd.append(float(q[3]))
		if pts.size() < 3: continue
		runs.append({"id": r.id, "pts": pts, "width": wd})
		_stamp(pts, wd)
		for k in range(1, pts.size()): total_km += pts[k].distance_to(pts[k - 1]) / 1000.0
		var k0 := 0
		while k0 < pts.size() - 1:
			var k1 := mini(k0 + PIECE, pts.size() - 1)
			_piece(r.id, pts, wd, k0, k1)
			k0 = k1


## The sky mirrored in the rivers follows the day: the sky shader's `daylight` (set by the clock)
## is copied once a second (the reflection is emitted light, so it would glow at night otherwise).
var _day_t := 0.0


func _process(delta: float) -> void:
	_day_t -= delta
	if _day_t > 0.0: return
	_day_t = 1.0
	var w := get_viewport().get_world_3d() if get_viewport() else null
	var env: Environment = w.environment if w else null
	if env == null or env.sky == null or not (env.sky.sky_material is ShaderMaterial): return
	var d = (env.sky.sky_material as ShaderMaterial).get_shader_parameter("daylight")
	if d != null: material.set_shader_parameter("daylight", clampf(float(d), 0.0, 1.0))


## Is (x, z) under a river's water (to the nearest 4 m cell)? Cheap: the flora asks per instance.
func in_channel(x: float, z: float) -> bool:
	return channel.has(Vector2i(floori(x / CELL), floori(z / CELL)))


func _stamp(pts: PackedVector3Array, wd: PackedFloat32Array) -> void:
	# cross-sections every ~3 m down the run, a point every 2 m across (70k lookups for all the rivers);
	# each cell keeps the water level there (the highest where two runs meet)
	for k in range(pts.size() - 1):
		var a := Vector2(pts[k].x, pts[k].z); var b := Vector2(pts[k + 1].x, pts[k + 1].z)
		var ab := b - a
		if ab.length() < 0.01: continue
		var side := Vector2(-ab.y, ab.x).normalized()
		var half := wd[k] * 0.5 + 2.0          # the water's edge and a little of the bank
		var steps := maxi(1, ceili(ab.length() / 3.0))
		var m := ceili(half / 2.0)
		for s in range(steps):
			var t := float(s) / steps
			var c := a + ab * t
			var lv := lerpf(pts[k].y, pts[k + 1].y, t)
			for o in range(-m, m + 1):
				var q := c + side * clampf(o * 2.0, -half, half)
				var key := Vector2i(floori(q.x / CELL), floori(q.y / CELL))
				channel[key] = maxf(float(channel.get(key, -INF)), lv)


## Is (x, z) in a river channel (to the 4 m cell, the water's edge plus 2 m of bank)? Returns the
## water level there, or NAN. The caller compares it with the ground: on the bank the ground stands
## above the water, so the depth there is <= 0 (OuterWorld.water_level_at, swimming, fords).
func water_at(x: float, z: float) -> float:
	var v = channel.get(Vector2i(floori(x / CELL), floori(z / CELL)))
	return NAN if v == null else float(v)


func _piece(id: String, pts: PackedVector3Array, wd: PackedFloat32Array, k0: int, k1: int) -> void:
	var V := PackedVector3Array(); var Nn := PackedVector3Array(); var U := PackedVector2Array()
	var C := PackedColorArray(); var I := PackedInt32Array()
	var along := 0.0
	for k in range(k0, k1 + 1):
		var p := pts[k]
		var a := pts[maxi(k - 1, 0)]; var b := pts[mini(k + 1, pts.size() - 1)]
		var tan := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
		var right := Vector3(-tan.z, 0.0, tan.x)
		# well under the banks: the shader fades the water out where it gets thin, so the waterline
		# is where the level meets the ground, not where the ribbon ends
		var half := wd[k] * 0.5 + 2.5
		var drop := maxf(a.y - b.y, 0.0) / maxf(Vector2(b.x - a.x, b.z - a.z).length(), 0.1)
		if k > k0: along += p.distance_to(pts[k - 1])
		for c in range(COLS):
			var u := float(c) / (COLS - 1)
			V.append(p + right * (u * 2.0 - 1.0) * half); Nn.append(Vector3.UP)
			U.append(Vector2(u, along))
			C.append(Color(clampf(drop * 12.0, 0.0, 1.0), half * 2.0 / 40.0, 0.0, 1.0))
		if k < k1:
			var r0 := (k - k0) * COLS; var r1 := r0 + COLS
			for c in range(COLS - 1):
				# front faces up (clockwise from above)
				I.append_array(PackedInt32Array([r0 + c, r0 + c + 1, r1 + c, r0 + c + 1, r1 + c + 1, r1 + c]))
	var arr := []; arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = V; arr[Mesh.ARRAY_NORMAL] = Nn; arr[Mesh.ARRAY_TEX_UV] = U
	arr[Mesh.ARRAY_COLOR] = C; arr[Mesh.ARRAY_INDEX] = I
	var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new(); mi.name = "River_%s_%d" % [id, k0]
	mi.mesh = mesh; mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = FAR
	add_child(mi)
