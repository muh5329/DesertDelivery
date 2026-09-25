class_name TexMips
extends RefCounted
## Mipmaps for textures that reach 3D materials from code (m-16). The project's textures are
## imported with the importer's defaults (lossless, no mipmaps: the .import files are not in the
## repository, and "detect 3D" never fires for textures only loaded by scripts), so a leaf atlas or
## a bark map minified on a real GPU samples its full-size level: shimmer and sparkle in motion,
## worst on alpha-cut foliage. `ensure(tex)` returns the texture itself when it already has
## mipmaps, else a mipmapped copy (built once, cached by path). Headless runs keep the original.
##
## `compress = true` also VRAM-compresses the copy (S3TC/BPTC family on desktop: DXT1 or DXT5 by
## alpha), which every Apple-silicon Mac samples natively through Metal.

static var _cache: Dictionary = {}


## Runtime VRAM compression must run on the CPU compressors (etcpak / cvtt): with a GPU present,
## Image.compress() defaults to the RenderingDevice compressor (Betsy), which needs the render
## thread - called from a worker while the main thread waits for that worker, it deadlocks (and on
## a software rasteriser it ran to 6 GB). Call once before any worker compresses.
static func cpu_compression() -> void:
	ProjectSettings.set_setting("rendering/textures/vram_compression/compress_with_gpu", false)


static func ensure(tex: Texture2D, compress := false, normal := false) -> Texture2D:
	if tex == null or DisplayServer.get_name() == "headless": return tex
	var key := tex.resource_path if tex.resource_path != "" else str(tex.get_instance_id())
	key += "|%d%d" % [int(compress), int(normal)]
	if _cache.has(key): return _cache[key]
	var img := _source_image(tex)
	if img == null or img.is_empty():
		_cache[key] = tex
		return tex
	if img.has_mipmaps() and not compress:
		_cache[key] = tex
		return tex
	if img.is_compressed(): img.decompress()
	if img.get_format() != Image.FORMAT_RGBA8 and img.get_format() != Image.FORMAT_RGB8: img.convert(Image.FORMAT_RGBA8)
	img.generate_mipmaps(normal)
	if compress and not normal:
		img.compress(Image.COMPRESS_S3TC, Image.COMPRESS_SOURCE_SRGB)
	var out := ImageTexture.create_from_image(img)
	out.resource_name = tex.resource_name
	_cache[key] = out
	return out


## The pixels: the source PNG when the project has it (no GPU read-back), else the texture's image.
static func _source_image(tex: Texture2D) -> Image:
	var path := tex.resource_path
	if path.begins_with("res://") and not path.contains("::"):
		var full := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(full):
			var img := Image.new()
			if img.load(full) == OK:
				return img
	return tex.get_image()
