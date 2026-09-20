"""Final topology/normal polish, executed through Blender MCP after the asset generators."""
exec(open('/Users/mun/Documents/Projects/DesertDelivery/tools/blender/common.py').read())
import bmesh
# character.py now polishes individual reference-driven components before batching.
# Never subdivide its merged face/eye/joint geometry here.
for asset_name,filename in [('CourierBike','courier_bike')]:
    root=bpy.data.objects[asset_name]
    for scene in bpy.data.scenes:
        if root.name in scene.objects: bpy.context.window.scene=scene; break
    for obj in root.children_recursive:
        if obj.type!='MESH': continue
        bm=bmesh.new(); bm.from_mesh(obj.data)
        bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
        bm.to_mesh(obj.data); bm.free(); obj.data.update()
        if obj.get('hero_polished'): continue
        if obj.name in ['Head_Geometry','Torso_Geometry','LegL_Geometry','LegR_Geometry','Body_Geometry']:
            bpy.ops.object.select_all(action='DESELECT'); obj.select_set(True); bpy.context.view_layer.objects.active=obj
            mod=obj.modifiers.new('Sculpted surface finish','SUBSURF'); mod.levels=1; mod.render_levels=1
            bpy.ops.object.modifier_apply(modifier=mod.name)
        obj['hero_polished']=True
    export(root,filename)
bpy.ops.wm.save_as_mainfile(filepath='/Users/mun/Documents/Projects/DesertDelivery/assets/source/courier_hero_assets.blend')
print('Hero normals and surfaces finished')
