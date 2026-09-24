class_name OuterTerrainView
extends Node3D
## GPU terrain for the outer world: a CDLOD quadtree over [-12800, 12800] whose selected nodes are
## drawn as instances of ONE shared 32 x 32 grid patch (a single MultiMesh, one draw call). The
## vertex shader displaces and morphs the patch (outer_terrain.gdshader), so the CPU only selects
## nodes: level 0 = 200 m nodes with 6.25 m cells (the collision lattice), each level up doubles.
## Selection runs when the camera has moved > 2 m or turned; the instance buffer is rewritten
## (a few hundred instances).

const P := 32                       # quads per patch side
const LEAF := 200.0                 # level-0 node size (m)
const LEVELS := 8                   # 200 m .. 25.6 km
const ROOT := 25600.0
const RANGE0 := 800.0               # level 0 is used within this distance; each level doubles (560 left coarse 200 m triangles
                                    # sawing the far coastlines into teeth)
const MORPH_START := 0.72
const MAX_INSTANCES := 1600
const LAYERS := [   # the texture array layers (outer_terrain.gdshader layer ids)
	"meadow", "ground015", "alpine", "ground024", "ground004", "soil", "sand",
	"rock019", "rock021", "gravel009", "snow", "clay", "rocks002"]

var ground: OuterGround
var material: ShaderMaterial
var mmi: MultiMeshInstance3D
var multimesh: MultiMesh
var ranges := PackedFloat32Array()
var selected := 0
var _last_cam := Vector3(INF, INF, INF)
var _last_dir := Vector3.ZERO
var _sel_origin := PackedVector2Array()
var _sel_level := PackedInt32Array()
var camera_override: Camera3D
var _r16_task := -1
var _r16: Image
var _r16_range := Vector2.ZERO


func setup(p_ground: OuterGround) -> void:
	ground = p_ground
	name = "OuterTerrain"
	ground.build_pyramid()
	for l in range(LEVELS): ranges.append(RANGE0 * pow(2.0, l))
	material = ShaderMaterial.new()
	material.shader = load("res://world/outer/outer_terrain.gdshader")
	var htex := ImageTexture.create_from_image(ground.height_image)
	material.set_shader_parameter("height_tex", htex)
	material.set_shader_parameter("height_lin", htex)
	# m-16: the filtered reads (normals) sample an R32F texture with linear filtering, which not
	# every GPU / MoltenVK combination supports (Apple silicon does). A normalised R16 copy (2.5 cm
	# steps, filterable everywhere) is built on a worker and swapped in when ready.
	if DisplayServer.get_name() != "headless":
		_r16_task = WorkerThreadPool.add_task(_build_r16, false, "outer height r16")
	var atex := ImageTexture.create_from_image(ground.aux_image)
	material.set_shader_parameter("aux_tex", atex)
	material.set_shader_parameter("aux_lin", atex)
	material.set_shader_parameter("splat_tex", ImageTexture.create_from_image(ground.splat_image))
	material.set_shader_parameter("tint_tex", ImageTexture.create_from_image(ground.tint_image))
	var fimg: Image = ground.feat_image.duplicate()
	fimg.generate_mipmaps()
	material.set_shader_parameter("feat_tex", ImageTexture.create_from_image(fimg))
	var rimg: Image = ground.roads_image.duplicate()
	rimg.generate_mipmaps()
	material.set_shader_parameter("road_tex", ImageTexture.create_from_image(rimg))
	var mtex := ImageTexture.create_from_image(ground.micro_image)
	material.set_shader_parameter("micro_tex", mtex)
	material.set_shader_parameter("micro_lin", mtex)
	material.set_shader_parameter("micro_amp", ground.micro_amp)
	material.set_shader_parameter("noise_tex", _noise_texture())
	var arrays := texture_arrays()
	material.set_shader_parameter("alb_arr", arrays[0])
	material.set_shader_parameter("nrm_arr", arrays[1])
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = _patch_mesh()
	multimesh.instance_count = MAX_INSTANCES
	multimesh.visible_instance_count = 0
	mmi = MultiMeshInstance3D.new()
	mmi.name = "Patches"
	mmi.multimesh = multimesh
	mmi.material_override = material
	mmi.custom_aabb = AABB(Vector3(-13000, -60, -13000), Vector3(26000, 1600, 26000))
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mmi)


## The shared patch: (P+1)^2 vertices at integer grid positions, quads split along the b-c
## diagonal exactly like the collision lattice (lower triangle a, b, c; upper b, d, c).
func _patch_mesh() -> ArrayMesh:
	var verts := PackedVector3Array(); var idx := PackedInt32Array()
	for j in range(P + 1):
		for i in range(P + 1):
			verts.append(Vector3(i, 0, j))
	for j in range(P):
		for i in range(P):
			var a := j * (P + 1) + i; var b := a + 1; var c := a + P + 1; var d := c + 1
			idx.append_array(PackedInt32Array([a, b, c, b, d, c]))
	var arr := []; arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts; arr[Mesh.ARRAY_INDEX] = idx
	var normals := PackedVector3Array(); normals.resize(verts.size()); normals.fill(Vector3.UP)
	arr[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.custom_aabb = AABB(Vector3(-1, -100, -1), Vector3(P + 2, 1600, P + 2))
	return mesh


static var _decoded: Array = []
static var _compress := false


static func texture_arrays() -> Array:
	# decoded, mipmapped and compressed one layer per worker task (26 images)
	_compress = DisplayServer.get_name() != "headless" and RenderingServer.has_os_feature("s3tc")
	_decoded = []; _decoded.resize(LAYERS.size() * 2)
	var g := WorkerThreadPool.add_group_task(func(i: int):
		var nm: String = LAYERS[i / 2]
		_decoded[i] = _tex_image("res://assets/terrain/%s_%s.png" % [nm, "alb_ht" if i % 2 == 0 else "nrm_rgh"]), LAYERS.size() * 2, -1, true, "terrain layers")
	WorkerThreadPool.wait_for_group_task_completion(g)
	var albs: Array[Image] = []; var nrms: Array[Image] = []
	for i in range(LAYERS.size()):
		albs.append(_decoded[i * 2]); nrms.append(_decoded[i * 2 + 1])
	_decoded = []
	var a := Texture2DArray.new(); a.create_from_images(albs)
	var n := Texture2DArray.new(); n.create_from_images(nrms)
	return [a, n]


static func _tex_image(path: String) -> Image:
	var img := Image.new()
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty() or img.load_png_from_buffer(bytes) != OK:
		img = Image.create_empty(512, 512, false, Image.FORMAT_RGBA8); img.fill(Color(0.5, 0.5, 0.5, 0.5))
	img.convert(Image.FORMAT_RGBA8)
	if img.get_width() != 512: img.resize(512, 512, Image.INTERPOLATE_LANCZOS)
	img.generate_mipmaps()
	# m-14: DXT5 on a GPU (26 layers: 36 MB -> 9 MB); the alpha (height / roughness) keeps its own
	# block. A texel a hair under opaque keeps every layer DXT5 (an array has one format).
	if _compress:
		var c := img.get_pixel(0, 0); c.a = minf(c.a, 0.99); img.set_pixel(0, 0, c)
		img.compress(Image.COMPRESS_S3TC, Image.COMPRESS_SOURCE_SRGB if path.contains("_alb") else Image.COMPRESS_SOURCE_GENERIC)
	return img


static func _noise_texture() -> ImageTexture:
	var n := FastNoiseLite.new()
	n.seed = 77; n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH; n.frequency = 0.02; n.fractal_octaves = 3
	var img := n.get_seamless_image(256, 256)
	img.convert(Image.FORMAT_L8)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _camera() -> Camera3D:
	if camera_override and is_instance_valid(camera_override): return camera_override
	var vp := get_viewport()
	return vp.get_camera_3d() if vp else null


func _ready() -> void:
	if DisplayServer.get_name() == "headless": set_process(false)


func _build_r16() -> void:
	var raw := ground.height_image.get_data()
	var n := raw.size() / 4
	var lo := INF; var hi := -INF
	var f := raw.to_float32_array()
	for i in range(n):
		var v := f[i]
		if v < lo: lo = v
		if v > hi: hi = v
	var span := maxf(hi - lo, 1.0)
	var out := PackedByteArray(); out.resize(n * 2)
	var k := 65535.0 / span
	for i in range(n):
		out.encode_u16(i * 2, int((f[i] - lo) * k + 0.5))
	_r16_range = Vector2(lo, span / 65535.0)
	_r16 = Image.create_from_data(ground.height_image.get_width(), ground.height_image.get_height(), false, Image.FORMAT_R16, out)


func _swap_r16() -> void:
	WorkerThreadPool.wait_for_task_completion(_r16_task)
	_r16_task = -1
	if _r16 == null: return
	var tex := ImageTexture.create_from_image(_r16)
	material.set_shader_parameter("height_lin", tex)
	material.set_shader_parameter("height_lin_scale", _r16_range.y * 65535.0)
	material.set_shader_parameter("height_lin_offset", _r16_range.x)
	height_lin_ready.emit(tex, _r16_range.y * 65535.0, _r16_range.x)
	_r16 = null


## The filtered height texture was swapped for its R16 copy: (texture, scale, offset) - metres are
## r * scale + offset. OuterWorld hands it to the sea.
signal height_lin_ready(tex: Texture2D, scale: float, offset: float)


func _process(_delta: float) -> void:
	if _r16_task >= 0 and WorkerThreadPool.is_task_completed(_r16_task): _swap_r16()
	var cam := _camera()
	if cam == null: return
	var p := cam.global_position
	var dir := -cam.global_transform.basis.z
	if p.distance_to(_last_cam) < 2.0 and dir.dot(_last_dir) > 0.999: return
	update_selection(p, dir)


func update_selection(p: Vector3, dir: Vector3 = Vector3.FORWARD) -> void:
	_last_cam = p; _last_dir = dir
	material.set_shader_parameter("lod_camera", p)
	_sel_origin.clear(); _sel_level.clear()
	_select(LEVELS - 1, 0, 0, p, dir)
	selected = mini(_sel_origin.size(), MAX_INSTANCES)
	for k in range(selected):
		var lvl := _sel_level[k]
		var cell := LEAF * pow(2.0, lvl) / P
		var o := _sel_origin[k]
		multimesh.set_instance_transform(k, Transform3D(Basis().scaled(Vector3(cell, 1.0, cell)), Vector3(o.x, 0.0, o.y)))
		var r := ranges[lvl]
		multimesh.set_instance_custom_data(k, Color(cell, r * MORPH_START, r, 0.0))
	multimesh.visible_instance_count = selected


## The LOD distance: height above the ground counts half (VERT_WEIGHT; the vertex shader's morph
## uses the same metric). From a plane at 9 km a plain 3-D distance put the whole island on 100 m
## triangles and their slanted crossings of the sea level sawed the cliff coasts into teeth.
const VERT_WEIGHT := 0.5


func _dist_to_box(p: Vector3, x0: float, z0: float, size: float, hr: Vector2) -> float:
	var dx := maxf(maxf(x0 - p.x, 0.0), p.x - (x0 + size))
	var dz := maxf(maxf(z0 - p.z, 0.0), p.z - (z0 + size))
	var dy := maxf(maxf(hr.x - p.y, 0.0), p.y - hr.y) * VERT_WEIGHT
	return sqrt(dx * dx + dy * dy + dz * dz)


func _select(level: int, i: int, j: int, p: Vector3, dir: Vector3) -> void:
	var size := LEAF * pow(2.0, level)
	var x0 := -ROOT * 0.5 + i * size; var z0 := -ROOT * 0.5 + j * size
	# the world ends at +-12500 (sea beyond): skip nodes wholly outside it
	if x0 > 12500.0 or z0 > 12500.0 or x0 + size < -12500.0 or z0 + size < -12500.0: return
	var hr := ground.node_range(level, i, j)
	var d := _dist_to_box(p, x0, z0, size, hr)
	# a rough view cone cull: nodes well behind the camera are skipped (shadows come from near ones)
	if d > 400.0:
		var c := Vector3(x0 + size * 0.5, (hr.x + hr.y) * 0.5, z0 + size * 0.5)
		var rad := size * 0.75 + (hr.y - hr.x) * 0.5
		if (c - p).dot(dir) < -rad: return
	if level == 0 or d > ranges[level - 1]:
		_sel_origin.append(Vector2(x0, z0)); _sel_level.append(level)
		return
	for cj in range(2):
		for ci in range(2):
			_select(level - 1, i * 2 + ci, j * 2 + cj, p, dir)
