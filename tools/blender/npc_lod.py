"""Build a weighted NPC LOD from the exported hero in an isolated Blender process.
Run: Blender --background --factory-startup --python tools/blender/npc_lod.py
Never changes the hero GLB or the live authoring session.
"""
import bpy, pathlib, json, hashlib, struct
root = pathlib.Path(__file__).resolve().parents[2]
source = root / 'assets/models/courier_character.glb'
output = root / 'assets/models/courier_character_npc_lod.glb'
before = hashlib.sha256(source.read_bytes()).hexdigest()
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=str(source))
blob = source.read_bytes()
source_json = json.loads(blob[20:20 + struct.unpack_from('<I', blob, 12)[0]])
source_mesh_names = {node['name'] for node in source_json['nodes'] if 'mesh' in node}
# The importer creates an Icosphere custom bone-display helper. It is not art.
for obj in list(bpy.context.scene.objects):
    if obj.type == 'MESH' and obj.name not in source_mesh_names:
        bpy.data.objects.remove(obj, do_unlink=True)
objects = [obj for obj in bpy.context.scene.objects if obj.type == 'MESH']
def triangles(obj):
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)
initial = sum(triangles(obj) for obj in objects)
ratio = min(1.0, 13500 / initial)
rows = []
for obj in objects:
    original = triangles(obj)
    bpy.ops.object.select_all(action='DESELECT'); obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    if original > 32:
        modifier = obj.modifiers.new('Distant NPC weighted geometry', 'DECIMATE')
        modifier.ratio = max(ratio, 32 / original)
        modifier.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    rows.append({'name': obj.name, 'before_triangles': original, 'after_triangles': triangles(obj)})
bpy.ops.export_scene.gltf(filepath=str(output), export_format='GLB', export_animations=False,
    export_skins=True, export_all_influences=False, export_materials='EXPORT', export_yup=True)
assert hashlib.sha256(source.read_bytes()).hexdigest() == before, 'Hero source changed'
report={'source_sha256':before, 'source_triangles':initial,
        'lod_triangles':sum(triangles(obj) for obj in objects),'meshes':rows}
folder=root/'artifacts/performance-2026-09-20'; folder.mkdir(parents=True,exist_ok=True)
(folder/'npc-lod-build.json').write_text(json.dumps(report,indent=2))
print('NPC_LOD',json.dumps(report))
