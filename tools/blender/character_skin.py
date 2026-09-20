"""Continuous garment surfaces weighted to a skin driven by the legacy gameplay pivots.
Executed by character.py while its authored objects and helpers are available.
"""
import bmesh
from mathutils import Matrix

def smoothstep(a,b,x):
    t=max(0.,min(1.,(x-a)/(b-a)))
    return t*t*(3-2*t)

# Keep rest axes identical to pivots: this preserves nonuniform resident proportions
# without asking Godot Skeleton3D to represent a sheared local bone transform.
pivots={'Root':root,'Torso':torso,'Head':head}
for side in ['L','R']:
    ap=next(o for o in asset.children_recursive if o.name=='Arm'+side)
    ep=next(o for o in ap.children if o.type=='EMPTY' and o.name.startswith('Elbow'))
    hp=next(o for o in ep.children if o.type=='EMPTY' and o.name.startswith('Hand'))
    lp=next(o for o in asset.children_recursive if o.name=='Leg'+side)
    kp=next(o for o in lp.children if o.type=='EMPTY' and o.name.startswith('Knee'))
    pivots.update({'Arm'+side:ap,'Elbow'+side:ep,'Hand'+side:hp,'Leg'+side:lp,'Knee'+side:kp})
arm_data=bpy.data.armatures.new('CourierClothRig')
rig=link(bpy.data.objects.new('CourierClothRig',arm_data),asset)
bpy.ops.object.select_all(action='DESELECT'); rig.select_set(True); bpy.context.view_layer.objects.active=rig
bpy.ops.object.mode_set(mode='EDIT')
reverse={obj:key for key,obj in pivots.items()}
for key,obj in pivots.items():
    bone=arm_data.edit_bones.new('Skin_'+key)
    bone.head=(0,0,0); bone.tail=(0,.1,0)
    bone.matrix=rig.matrix_world.inverted()@obj.matrix_world
    bone.length=.1
    if obj.parent in reverse: bone.parent=arm_data.edit_bones['Skin_'+reverse[obj.parent]]
bpy.ops.object.mode_set(mode='OBJECT')

def tailored_trousers():
    # Pair-of-pants topology: one waist loop branches continuously into two legs.
    # The shared crotch saddle replaces all intersecting hip/thigh cylinders.
    count=64; half=32; vertices=[]; faces=[]
    for y,rx,rz in [(1.135,.153,.103),(1.115,.158,.107),(1.04,.166,.112),(.96,.177,.117)]:
        for j in range(count):
            a=-math.pi/2+math.tau*j/count; vertices.append((rx*math.cos(a),y,rz*math.sin(a)))
    for row in range(3):
        for j in range(count): faces.append((row*count+j,row*count+(j+1)%count,(row+1)*count+(j+1)%count,(row+1)*count+j))
    split=len(vertices)
    for side in [1,-1]:
        for j in range(half):
            a=math.pi+math.tau*j/half if side>0 else math.tau*j/half
            vertices.append((side*.09+.09*math.cos(a),.855,.114*math.sin(a)))
    for j in range(count): faces.append((3*count+j,3*count+(j+1)%count,split+(j+1)%count,split+j))
    for side_index,side in enumerate([1,-1]):
        previous=split+side_index*half
        for y,cx,rx,rz in [(.78,.112,.100,.119),(.64,.133,.117,.119),(.46,.14,.126,.113),(.36,.14,.121,.105),(.335,.14,.105,.087),(.32,.14,.060,.052)]:
            base=len(vertices)
            for j in range(half):
                a=math.pi+math.tau*j/half if side>0 else math.tau*j/half
                vertices.append((side*cx+rx*math.cos(a),y,rz*math.sin(a)))
            for j in range(half): faces.append((previous+j,previous+(j+1)%half,base+(j+1)%half,base+j))
            previous=base
    obj=mesh('Tailored continuous trousers',vertices,faces,pants,asset)
    bm=bmesh.new(); bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.0001)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces)); bm.to_mesh(obj.data); bm.free()
    soften(obj,2)
    bpy.context.view_layer.objects.active=obj
    reduction=obj.modifiers.new('Trouser silhouette budget','DECIMATE'); reduction.ratio=.65
    bpy.ops.object.modifier_apply(modifier=reduction.name)
    return obj

# Voxel union removes the apron/stacked-cylinder silhouette and intersecting caps.
def garment(prefixes,label,mat,kind):
    if kind=='pants':
        for old in list(asset.children_recursive):
            if old.type=='MESH' and old.name.startswith(prefixes): bpy.data.objects.remove(old,do_unlink=True)
        obj=tailored_trousers()
    else:
        parts=[o for o in asset.children_recursive if o.type=='MESH' and o.name.startswith(prefixes)]
        bpy.ops.object.select_all(action='DESELECT')
        for obj in parts: obj.select_set(True)
        bpy.context.view_layer.objects.active=parts[0]; bpy.ops.object.join()
        obj=parts[0]; world_matrix=obj.matrix_world.copy(); obj.parent=None; obj.matrix_world=world_matrix
        bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
        bm=bmesh.new(); bm.from_mesh(obj.data); bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces)); bm.to_mesh(obj.data); bm.free()
        remesh=obj.modifiers.new('Continuous tailored surface','REMESH'); remesh.mode='VOXEL'; remesh.voxel_size=.005; remesh.use_smooth_shade=True
        bpy.ops.object.modifier_apply(modifier=remesh.name)
        smoothing=obj.modifiers.new('Soft tailored folds','SMOOTH'); smoothing.factor=.75; smoothing.iterations=12
        bpy.ops.object.modifier_apply(modifier=smoothing.name)
        # A modest reduction preserves the high resolution silhouette while avoiding needless interior loops.
        decimate=obj.modifiers.new('Garment surface budget','DECIMATE'); decimate.ratio=.40
        bpy.ops.object.modifier_apply(modifier=decimate.name)
    obj.name=label; obj.parent=rig; obj.data.materials.clear(); obj.data.materials.append(mat)
    for poly in obj.data.polygons: poly.use_smooth=True; poly.material_index=0
    groups={key:obj.vertex_groups.new(name='Skin_'+key) for key in pivots}
    for vertex in obj.data.vertices:
        q=C.inverted()@vertex.co; weights={}
        if kind=='pants':
            pelvis=smoothstep(.86,1.04,q.y)
            right=smoothstep(-.026,.026,q.x)
            knee=1-smoothstep(.32,.51,q.y)
            weights={'Root':pelvis,'LegL':(1-pelvis)*(1-right)*(1-knee),'KneeL':(1-pelvis)*(1-right)*knee,'LegR':(1-pelvis)*right*(1-knee),'KneeR':(1-pelvis)*right*knee}
        else:
            side='R' if q.x>0 else 'L'
            arm=smoothstep(.155,.245,abs(q.x))
            pelvis=1-smoothstep(1.155,1.32,q.y)
            weights={'Root':(1-arm)*pelvis,'Torso':(1-arm)*(1-pelvis),'Arm'+side:arm}
        for key,weight in weights.items():
            if weight>1e-6: groups[key].add([vertex.index],weight,'REPLACE')
    mod=obj.modifiers.new('Gameplay-driven continuous cloth','ARMATURE'); mod.object=rig
    return obj

trousers=garment(('Tailored hips','Wide trouser leg','Gathered breeches'),'ContinuousTrousers',pants,'pants')
blouse=garment(('Shirt tailored body','Shirt shoulder drape','Loose sleeve'),'ContinuousShirt',shirt,'shirt')
for obj in list(asset.children_recursive):
    if obj.name.startswith('Trouser outside seam'): bpy.data.objects.remove(obj,do_unlink=True)
# Tailoring details: curved pockets, fly and cuff stitching at the new high waist.
for side in [-1,1]:
    tube('Pocket welt',[(side*.141,.285,-.054),(side*.128,.238,-.081),(side*.095,.183,-.099)],.002,pants,root,8)
tube('Fly stitching',[(0,.278,-.104),(0,.195,-.115),(0,.10,-.117)],.0016,pants,root,8)
print('CONTINUOUS CLOTH',len(trousers.data.vertices),len(blouse.data.vertices),'bones',len(arm_data.bones))

# Lay the suspenders on the finished union surface instead of burying them in it.
from mathutils.bvhtree import BVHTree
bm=bmesh.new(); bm.from_mesh(blouse.data); surface=BVHTree.FromBMesh(bm); bm.free()
bpy.context.view_layer.update()
for obj in list(asset.children_recursive):
    if obj.type!='MESH' or not obj.name.startswith(('Front suspender','Y suspender')): continue
    rear=obj.name.startswith('Y suspender')
    inv=obj.matrix_world.inverted()
    for vertex in obj.data.vertices:
        p=C.inverted()@(obj.matrix_world@vertex.co)
        origin=v((p.x,p.y,1 if rear else -1)); direction=v((0,0,-1 if rear else 1))
        hit,normal,index,distance=surface.ray_cast(origin,direction,2)
        if hit is not None:
            q=C.inverted()@hit; p.z=q.z+(.004 if rear else -.004)
            vertex.co=inv@v(p)
    mod=obj.modifiers.new('Woven strap thickness','SOLIDIFY'); mod.thickness=.002; mod.offset=0
    bpy.context.view_layer.objects.active=obj; bpy.ops.object.modifier_apply(modifier=mod.name)

# Folded collar corners remain distinct from the shirt neck surface.
for obj in list(torso.children):
    if obj.type!='MESH' or not obj.name.startswith('Pointed collar'): continue
    bm=bmesh.new(); bm.from_mesh(obj.data); bmesh.ops.subdivide_edges(bm,edges=list(bm.edges),cuts=6,use_grid_fill=True); bm.to_mesh(obj.data); bm.free()
    inv=obj.matrix_world.inverted()
    for vertex in obj.data.vertices:
        p=C.inverted()@(obj.matrix_world@vertex.co)
        hit,normal,index,distance=surface.ray_cast(v((p.x,p.y,-1)),v((0,0,1)),2)
        if hit is not None:
            p.z=(C.inverted()@hit).z-.006; vertex.co=inv@v(p)
    mod=obj.modifiers.new('Folded collar cloth','SOLIDIFY'); mod.thickness=.003
    bpy.context.view_layer.objects.active=obj; bpy.ops.object.modifier_apply(modifier=mod.name)

# Shoulder bridges are projected downward, wrapping front-to-back across the seam.
for obj in list(torso.children):
    if obj.type!='MESH' or not obj.name.startswith('Shoulder suspender'): continue
    inv=obj.matrix_world.inverted()
    for vertex in obj.data.vertices:
        p=C.inverted()@(obj.matrix_world@vertex.co)
        hit,normal,index,distance=surface.ray_cast(v((p.x,3,p.z)),v((0,-1,0)),4)
        if hit is not None:
            p.y=(C.inverted()@hit).y+.004; vertex.co=inv@v(p)
    mod=obj.modifiers.new('Woven bridge thickness','SOLIDIFY'); mod.thickness=.002; mod.offset=0
    bpy.context.view_layer.objects.active=obj; bpy.ops.object.modifier_apply(modifier=mod.name)
