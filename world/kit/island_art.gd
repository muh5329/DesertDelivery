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
	var key := original.resource_name
	if materials.has(key): return materials[key]
	var mat: StandardMaterial3D = original.duplicate()
	if "plaster" in key.to_lower() or "limestone" in key.to_lower() or "clay" in key.to_lower() or "wood" in key.to_lower():
		var tex := NoiseTexture2D.new()
		var noise := FastNoiseLite.new(); noise.seed = 712; noise.frequency = .09
		noise.fractal_octaves = 3
		tex.width = 128; tex.height = 128; tex.noise = noise; tex.seamless = true
		tex.color_ramp = Gradient.new()
		tex.color_ramp.set_color(0, Color(.94, .93, .91))
		tex.color_ramp.set_color(1, Color(1, 1, .96))
		mat.albedo_texture = tex
		mat.uv1_triplanar = true
		mat.uv1_scale = Vector3.ONE * .65
		mat.roughness = .92
	if "glass" in key.to_lower():
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if "foliage" in key.to_lower():
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
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mi.mesh.surface_get_arrays(i))
			var mat: Material = mi.get_surface_override_material(i)
			result.append(WorldKit.PropPart.new(mesh, mat, xf))
	root.free()
	parts[asset] = result
	return result
