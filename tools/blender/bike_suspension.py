"""Add articulated suspension to the existing polished bike without remeshing it.
Run in an isolated Blender process; preserves every source vertex/material layer.
"""
import bpy, bmesh, math, pathlib, json, hashlib
from mathutils import Vector, Matrix
BASE = pathlib.Path(__file__).resolve().parents[2]
SOURCE = BASE/'assets/models/courier_bike.glb'
C = Matrix(((1,0,0),(0,0,-1),(0,1,0)))
CI = C.inverted()
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=str(SOURCE))
root = bpy.data.objects.get('CourierBike')
assert root is not None
if bpy.data.objects.get('FrontSuspension'):
    raise RuntimeError('Bike already has suspension pivots; use the preserved source GLB for a rebuild')
report = {'source_sha256': hashlib.sha256(SOURCE.read_bytes()).hexdigest(), 'parts': {}}
backup = BASE/'artifacts/handling-pass/courier-bike-before-suspension.glb'
backup.parent.mkdir(parents=True,exist_ok=True)
if not backup.exists(): backup.write_bytes(SOURCE.read_bytes())

def empty(name,parent,pos):
    obj=bpy.data.objects.new(name,None); bpy.context.scene.collection.objects.link(obj)
    obj.parent=parent; obj.location=C@Vector(pos)
    return obj

def reparent(obj,parent):
    matrix=obj.matrix_world.copy(); obj.parent=parent; obj.matrix_world=matrix

def components(obj, reference):
    # Mesh joins preserve connected-component identity, even after polishing.
    mesh=obj.data; neighbors=[[] for _ in mesh.vertices]
    for edge in mesh.edges:
        a,b=edge.vertices; neighbors[a].append(b); neighbors[b].append(a)
    seen=set(); result=[]
    transform=reference.matrix_world.inverted()@obj.matrix_world
    for start in range(len(mesh.vertices)):
        if start in seen: continue
        pending=[start]; seen.add(start); indices=[]
        while pending:
            index=pending.pop(); indices.append(index)
            for neighbor in neighbors[index]:
                if neighbor not in seen: seen.add(neighbor); pending.append(neighbor)
        points=[CI@(transform@mesh.vertices[index].co) for index in indices]
        low=Vector(tuple(min(p[i] for p in points) for i in range(3)))
        high=Vector(tuple(max(p[i] for p in points) for i in range(3)))
        center=(low+high)*.5
        result.append((indices,low,high,center))
    return result

def extract(obj, indices, name, parent):
    assert indices, 'Missing '+name
    chosen=set(indices)
    duplicate=obj.copy(); duplicate.data=obj.data.copy(); duplicate.name=name
    bpy.context.scene.collection.objects.link(duplicate)
    duplicate.matrix_world=obj.matrix_world.copy()
    bm=bmesh.new(); bm.from_mesh(duplicate.data); bm.verts.ensure_lookup_table()
    bmesh.ops.delete(bm,geom=[v for v in bm.verts if v.index not in chosen],context='VERTS')
    bm.to_mesh(duplicate.data); bm.free(); duplicate.data.update()
    reparent(duplicate,parent)
    report['parts'][name]=len(duplicate.data.vertices)
    return duplicate

def remove_vertices(obj, indices):
    chosen=set(indices); bm=bmesh.new(); bm.from_mesh(obj.data); bm.verts.ensure_lookup_table()
    bmesh.ops.delete(bm,geom=[v for v in bm.verts if v.index in chosen],context='VERTS')
    bm.to_mesh(obj.data); bm.free(); obj.data.update()

def segment_pivot(name,parent,a,b):
    a,b=Vector(a),Vector(b)
    node=empty(name,parent,(a+b)*.5)
    node.rotation_mode='QUATERNION'
    node.rotation_quaternion=Vector((0,0,1)).rotation_difference(C@(b-a).normalized())
    bpy.context.view_layer.update()
    return node

bpy.context.view_layer.update()
fork=bpy.data.objects['ForkPivot']
front=bpy.data.objects['FrontWheel']; rear=bpy.data.objects['RearWheel']
front_rest=(0,-.73,-.24)
lower=empty('FrontSuspension',fork,front_rest)
swing=empty('RearSwingarm',root,(0,.37,.16))
bpy.context.view_layer.update(); reparent(front,lower); reparent(rear,swing)

fork_mesh=next(o for o in fork.children if o.type=='MESH')
lower_indices=[]; rods={-1:[],1:[]}
for indices,low,high,center in components(fork_mesh,fork):
    if low.y < -.69 and high.y > -.05 and abs(abs(center.x)-.12)<.02:
        rods[-1 if center.x<0 else 1].extend(indices)
    elif high.y < -.25:
        lower_indices.extend(indices)  # Slider tubes and the three mudguard strips.
assert lower_indices and all(rods.values()), 'Fork component contract changed'
extract(fork_mesh,lower_indices,'LowerForkGeometry',lower)
for side,label in [(-1,'L'),(1,'R')]:
    pivot=segment_pivot('ForkStanchion'+label,fork,(side*.12,0,0),(side*.12,-.73,-.24))
    extract(fork_mesh,rods[side],'StanchionGeometry'+label,pivot)
remove_vertices(fork_mesh,lower_indices+rods[-1]+rods[1])

body=bpy.data.objects['Body']
body_mesh=next(o for o in body.children if o.type=='MESH')
swing_indices=[]; shocks={-1:[],1:[]}
for indices,low,high,center in components(body_mesh,root):
    if abs(abs(center.x)-.18)<.018 and high.y<.46 and low.z>.10 and high.z>.66:
        swing_indices.extend(indices)
    elif abs(abs(center.x)-.21)<.018 and low.y<.61 and high.y>.79 and low.z>.30 and high.z>.62:
        shocks[-1 if center.x<0 else 1].extend(indices)
assert swing_indices and all(shocks.values()), 'Rear suspension component contract changed'
extract(body_mesh,swing_indices,'SwingarmGeometry',swing)
for side,label in [(-1,'L'),(1,'R')]:
    pivot=segment_pivot('RearShock'+label,root,(side*.21,.34,.70),(side*.21,.89,.40))
    extract(body_mesh,shocks[side],'ShockGeometry'+label,pivot)
remove_vertices(body_mesh,swing_indices+shocks[-1]+shocks[1])

# Do not subdivide/decimate/recolor: this operation only changes hierarchy.
bpy.context.view_layer.update()
report['output_vertices']=sum(len(o.data.vertices) for o in root.children_recursive if o.type=='MESH')
bpy.ops.object.select_all(action='DESELECT'); root.select_set(True)
for obj in root.children_recursive: obj.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(SOURCE),export_format='GLB',use_selection=True,export_yup=True,export_animations=False)
(BASE/'artifacts/handling-pass/bike-suspension-build.json').write_text(json.dumps(report,indent=2))
print('BIKE_SUSPENSION',json.dumps(report))
