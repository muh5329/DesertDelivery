"""Reproducible Blender MCP asset tools. Author in Godot metres, facing -Z."""
import bpy, math, random, os
from mathutils import Vector, Matrix
OUT = '/Users/mun/Documents/Projects/DesertDelivery/assets/models'
os.makedirs(OUT, exist_ok=True)
C = Matrix(((1,0,0),(0,0,-1),(0,1,0)))
def v(p): return C @ Vector(p)
def material(name, color, rough=.65, metal=0):
    m=bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.diffuse_color=(*color[:3],color[3] if len(color)>3 else 1)
    m.use_nodes=True
    s=m.node_tree.nodes.get('Principled BSDF')
    s.inputs['Base Color'].default_value=m.diffuse_color
    s.inputs['Roughness'].default_value=rough
    s.inputs['Metallic'].default_value=metal
    s.inputs['Alpha'].default_value=m.diffuse_color[3]
    if m.diffuse_color[3]<1: m.surface_render_method='DITHERED'
    return m
def start(name):
    scene=bpy.data.scenes.get('DesertDelivery_Assets')
    if not scene: scene=bpy.data.scenes.new('DesertDelivery_Assets')
    bpy.context.window.scene=scene
    old=bpy.data.collections.get(name)
    if old:
        for o in list(old.objects): bpy.data.objects.remove(o,do_unlink=True)
        bpy.data.collections.remove(old)
    coll=bpy.data.collections.new(name); scene.collection.children.link(coll)
    globals()['COLL']=coll
    return empty(name)
def link(o, parent=None, pos=(0,0,0)):
    for c in list(o.users_collection): c.objects.unlink(o)
    COLL.objects.link(o); o.parent=parent; o.location=v(pos)
    return o
def empty(name,parent=None,pos=(0,0,0)):
    return link(bpy.data.objects.new(name,None),parent,pos)
def finish_obj(o,name,mat,parent,pos):
    o.name=name
    if mat: o.data.materials.append(mat)
    for p in o.data.polygons: p.use_smooth=True
    return link(o,parent,pos)
def mesh(name, verts, faces, mat, parent=None, pos=(0,0,0), smooth=True):
    m=bpy.data.meshes.new(name); m.from_pydata([v(p) for p in verts],[],faces); m.update()
    o=finish_obj(bpy.data.objects.new(name,m),name,mat,parent,pos)
    for p in m.polygons: p.use_smooth=smooth
    return o
def ell(name,pos,size,mat,parent=None,seg=24):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg,ring_count=12,radius=1)
    o=bpy.context.object
    o.scale=(size[0],size[2],size[1]); bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    return finish_obj(o,name,mat,parent,pos)
def box(name,pos,size,mat,parent=None,bevel=.025):
    bpy.ops.mesh.primitive_cube_add(size=1)
    o=bpy.context.object; o.scale=(size[0],size[2],size[1]); bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    if bevel:
        mod=o.modifiers.new('Soft crafted edges','BEVEL'); mod.width=bevel; mod.segments=3
        bpy.ops.object.modifier_apply(modifier=mod.name)
    o=finish_obj(o,name,mat,parent,pos)
    mod=o.modifiers.new('Weighted normals','WEIGHTED_NORMAL'); mod.keep_sharp=True
    bpy.context.view_layer.objects.active=o; bpy.ops.object.modifier_apply(modifier=mod.name)
    return o
def tube(name,points,radius,mat,parent=None,sides=8,radii=None):
    pts=[Vector(p) for p in points]; verts=[]; faces=[]
    for i,p in enumerate(pts):
        d=(pts[min(i+1,len(pts)-1)]-pts[max(0,i-1)]).normalized()
        u=d.cross(Vector((0,1,0)))
        if u.length<.01: u=d.cross(Vector((1,0,0)))
        u.normalize(); w=d.cross(u).normalized(); r=radius*(radii[i] if radii else 1)
        for j in range(sides): verts.append(p+(u*math.cos(j*math.tau/sides)+w*math.sin(j*math.tau/sides))*r)
    for i in range(len(pts)-1):
        for j in range(sides):
            a=i*sides+j; b=i*sides+(j+1)%sides
            faces.append((a,b,b+sides,a+sides))
    faces.extend([tuple(reversed(range(sides))),tuple((len(pts)-1)*sides+j for j in range(sides))])
    return mesh(name,verts,faces,mat,parent)
def loft(name,rings,mat,parent=None,n=32):
    # y, centre x, centre z, width radius, depth radius
    verts=[]; faces=[]
    for y,x,z,rx,rz in rings:
        for j in range(n):
            a=math.tau*j/n; verts.append((x+rx*math.cos(a),y,z+rz*math.sin(a)))
    for i in range(len(rings)-1):
        for j in range(n):
            a=i*n+j; b=i*n+(j+1)%n; faces.append((a,a+n,b+n,b))
    faces.extend([tuple(range(n-1,-1,-1)),tuple((len(rings)-1)*n+j for j in range(n))])
    return mesh(name,verts,faces,mat,parent)
def torus(name,pos,major,minor,mat,parent=None,axis='x',ns=48,nt=10):
    verts=[]; faces=[]
    for i in range(ns):
        a=math.tau*i/ns
        for j in range(nt):
            b=math.tau*j/nt; r=major+minor*math.cos(b)
            p=(minor*math.sin(b),r*math.cos(a),r*math.sin(a))
            if axis=='z': p=(p[1],p[2],p[0])
            if axis=='y': p=(p[1],p[0],p[2])
            verts.append(p)
    for i in range(ns):
        for j in range(nt): faces.append((i*nt+j,((i+1)%ns)*nt+j,((i+1)%ns)*nt+(j+1)%nt,i*nt+(j+1)%nt))
    return mesh(name,verts,faces,mat,parent,pos)
def merge_children(root):
    # Preserve transform pivots; batch the static geometry at each pivot into one mesh.
    for parent in [o for o in [root]+list(root.children_recursive) if o.type=='EMPTY']:
        children=[o for o in parent.children if o.type=='MESH']
        if len(children)<2: continue
        bpy.ops.object.select_all(action='DESELECT')
        for o in children: o.select_set(True)
        bpy.context.view_layer.objects.active=children[0]; bpy.ops.object.join()
        children[0].name=parent.name+'_Geometry'
def export(root,filename):
    merge_children(root)
    bpy.ops.object.select_all(action='DESELECT')
    root.select_set(True)
    for o in root.children_recursive: o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT,filename+'.glb'),export_format='GLB',use_selection=True,use_active_scene=True,export_yup=True,export_animations=False)
    print('EXPORTED',filename, 'meshes',sum(o.type=='MESH' for o in root.children_recursive),'vertices',sum(len(o.data.vertices) for o in root.children_recursive if o.type=='MESH'))
