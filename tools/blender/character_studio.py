"""Non-destructive four-view studio render of the authored Blender asset."""
import bpy, math
from mathutils import Vector
name='Courier_Reference_Review'
old=bpy.data.scenes.get(name)
if old:
    for obj in list(old.objects): bpy.data.objects.remove(obj,do_unlink=True)
    bpy.data.scenes.remove(old)
scene=bpy.data.scenes.new(name)
bpy.context.window.scene=scene
coll=bpy.data.collections.get('CourierCharacter')
for i,rot in enumerate([0,-math.pi/2,math.pi,math.pi/2]):
    obj=bpy.data.objects.new('Turnaround_'+str(i),None); obj.instance_type='COLLECTION'; obj.instance_collection=coll
    scene.collection.objects.link(obj); obj.location.x=1.38-i*.92; obj.rotation_euler.z=-rot
cam_data=bpy.data.cameras.new('ReferenceCamera'); cam=bpy.data.objects.new('ReferenceCamera',cam_data); scene.collection.objects.link(cam)
cam.location=(0,6,.96); cam.rotation_euler=(Vector((0,0,.96))-cam.location).to_track_quat('-Z','Y').to_euler()
cam_data.type='ORTHO'; cam_data.ortho_scale=3.8; scene.camera=cam
# Broad light sources produce the soft studio shadows used in the supplied turnaround.
for name,pos,power,size in [('Key',(-3,4,6),450,5),('Fill',(4,2,3),170,4),('Rim',(0,-3,4),250,3)]:
    light=bpy.data.lights.new('CourierReview_'+name,'AREA'); light.energy=power; light.shape='DISK'; light.size=size
    obj=bpy.data.objects.new(light.name,light); scene.collection.objects.link(obj); obj.location=pos; obj.rotation_euler=(Vector((0,0,1))-obj.location).to_track_quat('-Z','Y').to_euler()
world=bpy.data.worlds.new('CourierReview_World'); world.use_nodes=True
bg=next(n for n in world.node_tree.nodes if n.type=='BACKGROUND'); bg.inputs['Color'].default_value=(.65,.65,.65,1); bg.inputs['Strength'].default_value=.65; scene.world=world
mesh=bpy.data.meshes.new('ReviewGround'); mesh.from_pydata([(-100,-100,0),(100,-100,0),(100,100,0),(-100,100,0)],[],[(0,1,2,3)])
ground=bpy.data.objects.new('ReviewGround',mesh); scene.collection.objects.link(ground)
mat=bpy.data.materials.new('ReviewGround'); mat.use_nodes=True
shader=next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED'); shader.inputs['Base Color'].default_value=(.65,.65,.65,1); shader.inputs['Roughness'].default_value=.9; mesh.materials.append(mat)
scene.render.engine='CYCLES'; scene.cycles.samples=32; scene.cycles.use_denoising=True
scene.render.resolution_x=1717; scene.render.resolution_y=916; scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'; scene.render.filepath='/Users/mun/Documents/Projects/DesertDelivery/artifacts/character-match/studio.png'
bpy.ops.render.render(write_still=True)
bpy.context.window.scene=bpy.data.scenes['DesertDelivery_Assets']
