class_name ArchMaterials
extends RefCounted
## The architecture kit's materials: every layer of assets/buildings (world/mapgen/facades.py) in
## two Texture2DArrays and one shader (arch.gdshader), shared by every building of every town.
## `merged()` is for the per-group meshes, `instanced()` for the MultiMesh modules. The arrays are
## decoded and VRAM-compressed once, on the worker threads (`warm()` at boot), and uploaded behind
## the loading screen (`finish_boot()`), not at the first town (m-14).

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
## m-14: the layers are VRAM-compressed on the worker threads - albedo as S3TC (DXT1/DXT5: its
## alpha is the tint mask), the packed normal / cavity / roughness maps as BPTC (BC7 keeps the four
## channels apart) - so the two arrays take a quarter of the RGBA8 memory (1024^2 x 34 layers with
## mipmaps: ~190 MB -> ~47 MB). Apple silicon (Metal) samples both natively. False = RGBA8.
static var vram_compress := true

static var _merged: ShaderMaterial
static var _instanced: ShaderMaterial
static var _lod: ShaderMaterial
static var _task := -1
static var _images: Array = []          # [alb Array[Image], nrm Array[Image]] from the workers
static var load_ms := 0.0
static var bytes_rgba8 := 0             # what the arrays would take uncompressed (with mipmaps)
static var bytes_used := 0              # what they take


## Start decoding (and compressing) the textures on the worker threads, one task per layer (call at
## boot; the first build, or `finish_boot()`, waits for them).
static func warm() -> void:
	if _merged != null or _task >= 0: return
	var adapter := RenderingServer.get_video_adapter_name().to_lower()
	var software := "llvmpipe" in adapter or "swiftshader" in adapter or "lavapipe" in adapter
	if (software or DisplayServer.get_name() == "headless") and not "--arch-full" in OS.get_cmdline_user_args():
		size = 512
	# headless runs have no GPU memory to save; software rasterisers decode BC in the shader path
	if DisplayServer.get_name() == "headless" or not (RenderingServer.has_os_feature("s3tc") or RenderingServer.has_os_feature("bptc")) or "--arch-rgba8" in OS.get_cmdline_user_args():
		vram_compress = false
	var albs: Array = []; albs.resize(NAMES.size())
	var nrms: Array = []; nrms.resize(NAMES.size())
	_images = [albs, nrms]
	_t0 = Time.get_ticks_usec()
	_task = WorkerThreadPool.add_group_task(_decode_one, NAMES.size() * 2, -1, false, "arch textures")


static var _t0 := 0


static func _decode_one(i: int) -> void:
	var k := i % 2
	var n: int = i / 2
	var path: String = DIR + NAMES[n] + ("_alb.png" if k == 0 else "_nrm.png")
	_images[k][n] = _image(path, false, k == 1)


static func _image(path: String, main_thread := false, normal := false) -> Image:
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
	if vram_compress:
		# every layer of an array must share one format: DXT5 for all albedo (even the opaque ones,
		# which S3TC would make DXT1), BC7 for every packed normal map
		if normal:
			img.compress(Image.COMPRESS_BPTC, Image.COMPRESS_SOURCE_GENERIC)
		else:
			# S3TC picks DXT1 for a fully opaque image: one texel a hair under opaque keeps DXT5
			if img.detect_alpha() == Image.ALPHA_NONE:
				var c := img.get_pixel(0, 0); c.a = 0.99; img.set_pixel(0, 0, c)
			img.compress(Image.COMPRESS_S3TC, Image.COMPRESS_SOURCE_SRGB)
	return img


## Finish the arrays now (the boot calls this after the world is generated, so the upload happens
## behind the loading screen and not at the first town).
static func finish_boot() -> void:
	_ensure()


static func _ensure() -> void:
	if _merged != null: return
	if _task < 0: warm()
	WorkerThreadPool.wait_for_group_task_completion(_task)
	for k in range(2):
		for i in range(NAMES.size()):
			if _images[k][i] == null:
				_images[k][i] = _image(DIR + NAMES[i] + ("_alb.png" if k == 0 else "_nrm.png"), true, k == 1)
	var a0: Array[Image] = []; a0.assign(_images[0])
	var a1: Array[Image] = []; a1.assign(_images[1])
	_unify(a0, false); _unify(a1, true)
	bytes_rgba8 = 0; bytes_used = 0
	for img in a0 + a1:
		bytes_used += img.get_data_size()
		bytes_rgba8 += _rgba8_bytes(img.get_width())
	var alb := Texture2DArray.new(); alb.create_from_images(a0)
	var nrm := Texture2DArray.new(); nrm.create_from_images(a1)
	_images = []
	load_ms = (Time.get_ticks_usec() - _t0) / 1000.0
	print("[arch] textures: %d layers x2 at %d px, %s, %.0f MB (RGBA8 would be %.0f MB), ready %.0f ms after boot started" % [NAMES.size(), size,
		"S3TC + BPTC" if a0[0].is_compressed() else "RGBA8", bytes_used / 1048576.0, bytes_rgba8 / 1048576.0, load_ms])
	var sh: Shader = load(SHADER)
	_merged = ShaderMaterial.new(); _merged.shader = sh
	_merged.set_shader_parameter("alb_tex", alb)
	_merged.set_shader_parameter("nrm_tex", nrm)
	_merged.set_shader_parameter("noise_tex", TexMips.ensure(load(DIR + "noise.png")))
	var pal := PackedVector3Array()
	for col: Color in FRAMES: pal.append(Vector3(col.r, col.g, col.b))
	_merged.set_shader_parameter("frame_palette", pal)
	_instanced = _merged.duplicate()
	_instanced.set_shader_parameter("instanced", true)


## RGBA8 with a full mip chain, for the before / after report.
static func _rgba8_bytes(w: int) -> int:
	var total := 0
	while w >= 1:
		total += w * w * 4
		w /= 2
	return total


## Every layer of a Texture2DArray must have the same format: when one layer failed to compress
## (or fell back), the whole array goes uncompressed.
static func _unify(imgs: Array[Image], _normal: bool) -> void:
	var f := imgs[0].get_format()
	var same := true
	for img in imgs: same = same and img.get_format() == f
	if same: return
	for img in imgs:
		if img.is_compressed(): img.decompress()
		if img.get_format() != Image.FORMAT_RGBA8: img.convert(Image.FORMAT_RGBA8)
		if not img.has_mipmaps(): img.generate_mipmaps()


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


## The far silhouettes: the vertex colour is the near building's mean albedo (linear), lit like
## the kit's walls, with lit windows at night (arch_lod.gdshader, m-6 / M-12).
static func lod() -> ShaderMaterial:
	if _lod: return _lod
	_lod = ShaderMaterial.new()
	_lod.shader = load("res://world/kit/building/arch_lod.gdshader")
	return _lod
