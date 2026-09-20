"""Regrade runtime GLBs through Blender MCP, preserving animation pivots.
Original GLBs are archived once, making repeated passes idempotent. The truck
and palm have independent geometry generators. Unrelated Blender scenes survive.
"""
import bpy
import math
import pathlib
import shutil

PROJECT = pathlib.Path('/Users/mun/Documents/Projects/DesertDelivery')
MODELS = PROJECT / 'assets/models'
BACKUP = PROJECT / 'artifacts/overhaul-2026-09-19/original-models'
BACKUP.mkdir(parents=True, exist_ok=True)


def reauthor(filename):
    source = MODELS / filename
    backup = BACKUP / filename
    if not backup.exists():
        shutil.copy2(source, backup)
    previous = bpy.context.window.scene
    before_objects = set(bpy.data.objects)
    before_meshes = set(bpy.data.meshes)
    before_materials = set(bpy.data.materials)
    # Blender names are global even across scenes. Temporarily reserve unrelated
    # names so import/export retains exact Godot animation node/material names.
    names = {item: item.name for item in before_objects | before_materials}
    scene = bpy.data.scenes.new('DD_Paint_' + source.stem)
    staging = source.with_name(source.stem + '.paint-staging.glb')
    try:
        for item in names:
            item.name = 'DD_Preserved_' + str(item.as_pointer())
        bpy.context.window.scene = scene
        bpy.ops.import_scene.gltf(filepath=str(backup))
        objects = set(bpy.data.objects) - before_objects
        materials = set()
        for obj in objects:
            if obj.type != 'MESH':
                continue
            materials.update(m for m in obj.data.materials if m)
            mesh = obj.data
            old = mesh.color_attributes.get('PaintScumble')
            if old:
                mesh.color_attributes.remove(old)
            # Enum values checked against the connected Blender 5.1 RNA.
            attr = mesh.color_attributes.new(name='PaintScumble', type='FLOAT_COLOR', domain='CORNER')
            for loop in mesh.loops:
                p = mesh.vertices[loop.vertex_index].co
                wave = math.sin(p.x * 8.2 + p.z * 3.1) * math.cos(p.y * 6.7 - p.z * 2.3)
                grain = .96 + .04 * wave
                attr.data[loop.index].color = (grain, grain, grain, 1)
            mesh.color_attributes.active_color = attr
        for mat in materials:
            if not mat.use_nodes:
                continue
            shader = next((n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'), None)
            if not shader or shader.inputs['Alpha'].default_value < .99:
                continue
            shader.inputs['Roughness'].default_value = max(.8, shader.inputs['Roughness'].default_value)
            shader.inputs['Metallic'].default_value = min(.18, shader.inputs['Metallic'].default_value)
            shader.inputs['Specular IOR Level'].default_value = .22
        if source.stem == 'courier_character':
            for obj in objects:
                if obj.name == 'Head':
                    obj.scale *= 1.12
        bpy.ops.object.select_all(action='DESELECT')
        for obj in objects:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = next(iter(objects))
        # ACTIVE is verified from the installed glTF exporter's EnumProperty.
        # Without this option Blender silently omits paint from material meshes.
        bpy.ops.export_scene.gltf(filepath=str(staging), use_selection=True,
                                  use_active_scene=True, export_animations=False,
                                  export_vertex_color='ACTIVE', export_all_vertex_colors=False)
        staging.replace(source)
        count = sum(len(o.data.vertices) for o in objects if o.type == 'MESH')
        print('PAINTED', filename, count, 'vertices')
    finally:
        bpy.context.window.scene = previous
        for obj in set(bpy.data.objects) - before_objects:
            bpy.data.objects.remove(obj, do_unlink=True)
        bpy.data.scenes.remove(scene)
        for mesh in set(bpy.data.meshes) - before_meshes:
            if mesh.users == 0:
                bpy.data.meshes.remove(mesh)
        for mat in set(bpy.data.materials) - before_materials:
            if mat.users == 0:
                bpy.data.materials.remove(mat)
        for item, name in names.items():
            item.name = name
        if staging.exists():
            staging.unlink()


if __name__ == '__main__':
    for source in sorted(MODELS.glob('*.glb')):
        if source.stem not in ['courier_truck', 'harbour_palm', 'courier_character']:
            reauthor(source.name)
