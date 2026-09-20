class_name IslandArt
extends RefCounted
## Shared imported Blender meshes and materials; all streamed instances reuse these resources.

static var scenes: Dictionary = {}
static var parts: Dictionary = {}
static var materials: Dictionary = {}

static func scene(asset: String) -> PackedScene:
	if not scenes.has(asset): scenes[asset] = load("res://assets/models/%s.glb" % asset)
	return scenes[asset]

static func instantiate(asset: String) -> Node3D:
	var node: Node3D = scene(asset).instantiate()
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		for i in range(mi.mesh.get_surface_count()):
			mi.set_surface_override_material(i, surface_material(mi.mesh.surface_get_material(i)))
	return node

static func surface_material(original: Material) -> Material:
	if not original is StandardMaterial3D: return original
	var key := str(original.get_instance_id())
	var material_name := original.resource_name
	if materials.has(key): return materials[key]
	var mat: StandardMaterial3D = original.duplicate()
	Storybook.finish(mat)
	if "glass" in material_name.to_lower():
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if "foliage" in material_name.to_lower():
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.backlight_enabled = true; mat.backlight = Color(.12,.16,.05)
	materials[key] = mat
	return mat

static func prop_parts(asset: String) -> Array[WorldKit.PropPart]:
	if parts.has(asset): return parts[asset]
	var result: Array[WorldKit.PropPart] = []
	var root := instantiate(asset)
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var xf: Transform3D = mi.transform
		var parent: Node = mi.get_parent()
		while parent is Node3D:
			xf = parent.transform * xf
			parent = parent.get_parent()
		for i in range(mi.mesh.get_surface_count()):
			var mesh := extract_surface(mi.mesh, i)
			var mat: Material = mi.get_surface_override_material(i)
			result.append(WorldKit.PropPart.new(mesh, mat, xf))
	root.free()
	parts[asset] = result
	return result

## Keep importer LOD index buffers and compressed vertex data when splitting a
## material surface for MultiMesh. Rebuilding from arrays silently loses both.
## Vertices stay in mesh-local space; instance transforms also scale LOD errors.
static func extract_surface(source: ArrayMesh, surface: int) -> ArrayMesh:
	assert(surface >= 0 and surface < source.get_surface_count())
	var result := source.duplicate() as ArrayMesh
	result.shadow_mesh = null
	for i in range(result.get_surface_count() - 1, -1, -1):
		if i != surface: result.surface_remove(i)
	# Imported shadow proxies can merge or reorder surfaces. Retain the prior
	# full-geometry shadow path rather than assume a surface correspondence.
	return result
