class_name ArchMaterials
extends RefCounted
## The architecture kit's materials: every layer of assets/buildings (world/mapgen/facades.py) in
## two Texture2DArrays and one shader (arch.gdshader), shared by every building of every town.
## `merged()` is for the per-group meshes, `instanced()` for the MultiMesh modules. The arrays are
## decoded once (a worker thread started by `warm()` at boot, or on first use).

const DIR := "res://assets/buildings/"
const SHADER := "res://world/kit/building/arch.gdshader"
## layer order = facades.py LAYERS = the shader's TILE table
const NAMES := ["plaster", "whitewash", "rubble", "ashlar", "brick", "adobe", "azulejo", "roof_tile",
	"slate", "timber", "shutter", "glass", "iron", "stone", "door", "canvas", "terrace"]
const PLASTER := 0
const WHITEWASH := 1
const RUBBLE := 2
const ASHLAR := 3
const BRICK := 4
const ADOBE := 5
const AZULEJO := 6
const ROOF_TILE := 7
const SLATE := 8
const TIMBER := 9
const SHUTTER := 10
const GLASS := 11
const IRON := 12
const STONE := 13
const DOOR := 14
const CANVAS := 15
const TERRACE := 16
## window-frame paints (arch.gdshader frame_palette, module flag 3)
const FRAMES := [Color(0.95, 0.95, 0.93), Color(0.9, 0.86, 0.76), Color(0.18, 0.3, 0.22), Color(0.35, 0.22, 0.14),
	Color(0.55, 0.16, 0.14), Color(0.55, 0.42, 0.3), Color(0.25, 0.3, 0.28), Color(0.14, 0.36, 0.64)]
## the layer size used at runtime (the PNGs are 1024; software renderers get half)
static var size := 1024

static var _merged: ShaderMaterial
static var _instanced: ShaderMaterial
static var _lod: StandardMaterial3D
static var _task := -1
static var _images: Array = []          # [alb Array[Image], nrm Array[Image]] from the worker
static var load_ms := 0.0


## Start decoding the textures on a worker thread (call at boot; the first build waits for it).
static func warm() -> void:
	if _merged != null or _task >= 0: return
	var adapter := RenderingServer.get_video_adapter_name().to_lower()
	if "llvmpipe" in adapter or "swiftshader" in adapter or "lavapipe" in adapter or DisplayServer.get_name() == "headless":
		size = 512
	_task = WorkerThreadPool.add_task(_decode, false, "arch textures")


static func _decode() -> void:
	var t0 := Time.get_ticks_usec()
	var albs: Array = []
	var nrms: Array = []
	for n: String in NAMES:
		albs.append(_image(DIR + n + "_alb.png"))
		nrms.append(_image(DIR + n + "_nrm.png"))
	_images = [albs, nrms]
	load_ms = (Time.get_ticks_usec() - t0) / 1000.0


static func _image(path: String, main_thread := false) -> Image:
	# Worker thread: decode the PNG straight from the project (no RenderingServer calls, which
	# would wait on the main thread). Exported builds have no raw PNGs: the main thread then loads
	# the imported texture instead (`main_thread`).
	var img: Image = null
	if not main_thread:
		var full := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(full):
			img = Image.new()
			if img.load(full) != OK: img = null
	elif ResourceLoader.exists(path):
		var tex = load(path)
		if tex is Texture2D: img = (tex as Texture2D).get_image()
	if img == null:
		if not main_thread: return null
		img = Image.create(size, size, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.8, 0.8, 0.8, 1.0) if path.ends_with("_alb.png") else Color(0.5, 0.5, 1.0, 0.9))
	if img.is_compressed(): img.decompress()
	if img.get_format() != Image.FORMAT_RGBA8: img.convert(Image.FORMAT_RGBA8)
	if img.get_width() != size: img.resize(size, size, Image.INTERPOLATE_LANCZOS)
	img.generate_mipmaps()
	return img


static func _ensure() -> void:
	if _merged != null: return
	if _task < 0: warm()
	WorkerThreadPool.wait_for_task_completion(_task)
	for k in range(2):
		for i in range(NAMES.size()):
			if _images[k][i] == null:
				_images[k][i] = _image(DIR + NAMES[i] + ("_alb.png" if k == 0 else "_nrm.png"), true)
	var a0: Array[Image] = []; a0.assign(_images[0])
	var a1: Array[Image] = []; a1.assign(_images[1])
	var alb := Texture2DArray.new(); alb.create_from_images(a0)
	var nrm := Texture2DArray.new(); nrm.create_from_images(a1)
	_images = []
	var sh: Shader = load(SHADER)
	_merged = ShaderMaterial.new(); _merged.shader = sh
	_merged.set_shader_parameter("alb_tex", alb)
	_merged.set_shader_parameter("nrm_tex", nrm)
	_merged.set_shader_parameter("noise_tex", load(DIR + "noise.png"))
	var pal := PackedVector3Array()
	for col: Color in FRAMES: pal.append(Vector3(col.r, col.g, col.b))
	_merged.set_shader_parameter("frame_palette", pal)
	_instanced = _merged.duplicate()
	_instanced.set_shader_parameter("instanced", true)


static func merged() -> ShaderMaterial:
	_ensure()
	return _merged


static func instanced() -> ShaderMaterial:
	_ensure()
	return _instanced


## The palette index nearest a frame colour.
static func frame_index(c: Color) -> int:
	var best := 0; var bd := 1e9
	for i in range(FRAMES.size()):
		var f: Color = FRAMES[i]
		var dd := Vector3(f.r - c.r, f.g - c.g, f.b - c.b).length_squared()
		if dd < bd: bd = dd; best = i
	return best


## The far silhouettes: plain vertex colour, no textures.
static func lod() -> StandardMaterial3D:
	if _lod: return _lod
	_lod = StandardMaterial3D.new()
	_lod.vertex_color_use_as_albedo = true
	_lod.roughness = 0.92
	_lod.diffuse_mode = BaseMaterial3D.DIFFUSE_BURLEY
	return _lod
