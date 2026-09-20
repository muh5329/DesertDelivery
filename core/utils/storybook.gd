class_name Storybook
extends RefCounted
## A shared, bounded material cache. Preserve transparency and authored textures;
## add a quiet gouache surface only to opaque untextured paint, cloth and plaster.
const CACHE_LIMIT := 256
const FINISHED := &"storybook_finished"
static var _materials: Dictionary = {}
static var _paper: Texture2D

static func material(source: Material) -> Material:
	if not source is StandardMaterial3D: return source
	if source.get_meta(FINISHED, false): return source
	var key := source.get_instance_id()
	if _materials.has(key): return _materials[key]
	var result: StandardMaterial3D = source.duplicate()
	finish(result)
	if _materials.size() >= CACHE_LIMIT:
		_materials.erase(_materials.keys()[0])
	_materials[key] = result
	return result

static func finish(mat: StandardMaterial3D) -> void:
	mat.set_meta(FINISHED, true)
	if mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED: return
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_BURLEY
	mat.specular_mode = BaseMaterial3D.SPECULAR_TOON
	mat.roughness = maxf(mat.roughness, .78)
	mat.metallic = minf(mat.metallic, .22)
	mat.rim_enabled = true
	mat.rim = .12
	mat.rim_tint = .75
	if mat.albedo_texture == null and not mat.emission_enabled:
		if _paper == null: _paper = load("res://assets/storybook/gouache_surface.png")
		mat.albedo_texture = _paper
		mat.uv1_triplanar = true
		mat.uv1_scale = Vector3.ONE * .75
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

static func apply(root: Node) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		if not node.mesh: continue
		for index in range(node.mesh.get_surface_count()):
			var source: Material = node.get_surface_override_material(index)
			if source == null: source = node.mesh.surface_get_material(index)
			node.set_surface_override_material(index, material(source))
