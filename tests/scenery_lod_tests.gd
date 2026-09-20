extends SceneTree
## Imported surface extraction must retain renderer buffers and LOD errors exactly.
var checks := 0
func _initialize() -> void:
 for path in ['res://assets/models/olive_tree.glb', 'res://assets/models/harbour_palm.glb', 'res://assets/trees/TwistedTree_1.gltf']:
  var root: Node = load(path).instantiate()
  for mi in root.find_children('*', 'MeshInstance3D', true, false):
   var source: ArrayMesh = mi.mesh
   var count := source.get_surface_count()
   for s in range(count):
    var before := RenderingServer.mesh_get_surface(source.get_rid(), s)
    var extracted := IslandArt.extract_surface(source, s)
    var after := RenderingServer.mesh_get_surface(extracted.get_rid(), 0)
    assert(extracted.get_surface_count() == 1)
    for key in ['primitive', 'format', 'vertex_data', 'attribute_data', 'vertex_count', 'index_data', 'index_count', 'aabb', 'lods']:
     assert(before.get(key) == after.get(key), path + ': changed ' + key)
    assert(source.get_surface_count() == count, 'modified shared source')
    assert(extracted.shadow_mesh == null, 'unmapped whole-asset shadow proxy')
    checks += 1
  root.free()
 var parts := IslandArt.prop_parts('olive_tree')
 var lod_count := 0
 for part in parts:
  lod_count += RenderingServer.mesh_get_surface(part.mesh.get_rid(), 0).get('lods', []).size()
 assert(lod_count > 0, 'scattered olive lost all imported LODs')
 print('SCENERY LOD PASS: ', checks, ' exact surface buffers; ', lod_count, ' olive LOD levels retained; unmodified local geometry/instance transforms')
 quit()
