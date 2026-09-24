class_name OuterRivers
extends Node3D
## The outer world's rivers (plan.json `rivers`, traced and carved by world/mapgen/outer_water.py):
## each run is a polyline of [x, water level, z, width] from its head to the sea, the estuary or the
## lagoon. Drawn as resident ribbon meshes in ~1 km pieces (river.gdshader: flowing normals, depth
## tint against the bed, foam on the rapids and along the banks). Render only - the bed is carved
## into the ground, so the bike rides through the shallows and the roads cross on bridges.

const PIECE := 250                    # samples per mesh piece (~1 km)
const FAR := 7000.0

var outer: OuterWorld
var runs: Array = []                  # [{id, pts: PackedVector3Array, width: PackedFloat32Array}]
var total_km := 0.0
var material: ShaderMaterial
var channel: Dictionary = {}          # 4 m cells under the water (flora keeps out of them)
const CELL := 4.0


func setup(p_outer: OuterWorld) -> void:
	outer = p_outer
	name = "OuterRivers"
	material = ShaderMaterial.new()
	material.shader = load("res://world/outer/river.gdshader")
	material.set_shader_parameter("noise_tex", OuterTerrainView._noise_texture())
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


## Is (x, z) under a river's water (to the nearest 4 m cell)? Cheap: the flora asks per instance.
func in_channel(x: float, z: float) -> bool:
	return channel.has(Vector2i(floori(x / CELL), floori(z / CELL)))


func _stamp(pts: PackedVector3Array, wd: PackedFloat32Array) -> void:
	# cross-sections every ~3 m down the run, a point every 2 m across (70k lookups for all the rivers)
	for k in range(pts.size() - 1):
		var a := Vector2(pts[k].x, pts[k].z); var b := Vector2(pts[k + 1].x, pts[k + 1].z)
		var ab := b - a
		if ab.length() < 0.01: continue
		var side := Vector2(-ab.y, ab.x).normalized()
		var half := wd[k] * 0.5 + 2.0          # the water's edge and a little of the bank
		var steps := maxi(1, ceili(ab.length() / 3.0))
		var m := ceili(half / 2.0)
		for s in range(steps):
			var c := a + ab * (float(s) / steps)
			for o in range(-m, m + 1):
				var q := c + side * clampf(o * 2.0, -half, half)
				channel[Vector2i(floori(q.x / CELL), floori(q.y / CELL))] = true


## Is (x, z) in a river channel? Returns the water level there, or NAN (swimming, splashes).
func water_at(x: float, z: float) -> float:
	var p := Vector2(x, z)
	for r in runs:
		var pts: PackedVector3Array = r.pts
		var wd: PackedFloat32Array = r.width
		for k in range(0, pts.size() - 1, 4):
			var a := Vector2(pts[k].x, pts[k].z)
			if a.distance_squared_to(p) > 2500.0: continue
			var kk := mini(k + 4, pts.size() - 1)
			var b := Vector2(pts[kk].x, pts[kk].z)
			var ab := b - a
			var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
			if (a + ab * t).distance_to(p) < wd[k] * 0.5:
				return lerpf(pts[k].y, pts[kk].y, t)
	return NAN


func _piece(id: String, pts: PackedVector3Array, wd: PackedFloat32Array, k0: int, k1: int) -> void:
	var V := PackedVector3Array(); var Nn := PackedVector3Array(); var U := PackedVector2Array()
	var C := PackedColorArray(); var I := PackedInt32Array()
	var along := 0.0
	for k in range(k0, k1 + 1):
		var p := pts[k]
		var a := pts[maxi(k - 1, 0)]; var b := pts[mini(k + 1, pts.size() - 1)]
		var tan := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
		var right := Vector3(-tan.z, 0.0, tan.x)
		var half := wd[k] * 0.5 + 1.2              # a little under the banks
		var drop := maxf(a.y - b.y, 0.0) / maxf(Vector2(b.x - a.x, b.z - a.z).length(), 0.1)
		if k > k0: along += p.distance_to(pts[k - 1])
		for c in range(3):
			var off := (c - 1) * half
			V.append(p + right * off); Nn.append(Vector3.UP)
			U.append(Vector2(c * 0.5, along))
			C.append(Color(clampf(drop * 12.0, 0.0, 1.0), wd[k] / 40.0, 0.0, 1.0))
		if k < k1:
			var r0 := (k - k0) * 3; var r1 := r0 + 3
			for c in range(2):
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
