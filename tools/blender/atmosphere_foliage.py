"""Dense, asymmetric Mediterranean foliage. Reproduce through Blender MCP.
Game metres, front -Z. One batched tree, five foliage materials plus bark.
The canopy has irregular interior crowns with lanceolate leaves facing in 3D;
foliage is opaque geometry, so the streamed MultiMesh kit has no alpha overdraw.
"""
import bpy
previous_scene=bpy.context.window.scene
exec(open('/Users/mun/Documents/Projects/DesertDelivery/tools/blender/common.py').read())
random.seed(93017)
wood=material('Olive bark wood',(.16,.115,.065),.94)
bark_hi=wood
colors=[(.092,.17,.050),(.14,.235,.065),(.21,.30,.090),(.28,.36,.145),(.255,.32,.185)]
leaves=[material('Organic olive foliage '+str(i),c,.93) for i,c in enumerate(colors)]
root=start('OliveTree')
# Uneven old trunk, a low fork and tapered roots, rather than a straight pole.
loft('Gnarled trunk',[(-.08,0,0,.36,.33),(.38,.05,.03,.30,.28),(.92,-.055,.06,.26,.24),(1.38,.03,.02,.23,.22),(1.90,-.03,-.02,.19,.18),(2.34,-.12,-.07,.13,.12)],wood,root,20)
for i in range(5):
    a=i*2.39; end=Vector((math.cos(a)*.78,.015,math.sin(a)*.75))
    tube('Surface root',[(0,.25,0),end*.64+Vector((0,.055,0)),end],.095,wood,root,8,[1,.70,.08])
for i in range(7):
    a=i*math.tau/7
    pts=[(math.cos(a)*(.23-.015*j)+.055*math.sin(j*1.8),.14+j*.30,math.sin(a)*(.23-.015*j)+.055*math.cos(j*1.4)) for j in range(6)]
    tube('Furrowed bark',pts,.023,bark_hi,root,5,[1,1,.9,.8,.7,.25])
# Each branch carries several overlapping, unequal crowns. Open gaps remain
# around the fork and between the outer branches; the silhouette is never circular.
crowns=[]
for i in range(8):
    a=i*2.39996+.20; reach=1.40+(i%3)*.28
    p=Vector((math.cos(a)*reach,3.35+(i%3)*.24,math.sin(a)*reach))
    elbow=Vector((p.x*.46,2.48+(i%2)*.2,p.z*.46))
    tube('Major olive limb',[(.03,1.32,.04),elbow,p+Vector((0,-.23,0))],.15,wood,root,9,[1,.68,.12])
    for j in range(2):
        offset=Vector((math.cos(a+j*1.9)*.38,.18+j*.37,math.sin(a+j*1.9)*.41))
        center=p+offset
        radii=Vector((.72+random.random()*.25,.55+random.random()*.24,.70+random.random()*.25))
        crowns.append((center,radii))
        tube('Twig fork',[elbow,p,center+Vector((0,.23,0))],.045,wood,root,6,[1,.60,.08])
crowns.extend([(Vector((-.22,4.15,.12)),Vector((.99,.76,.94))), (Vector((.56,4.09,-.45)),Vector((.78,.69,.79)))])
# Dark irregular cores provide real shade and volume, with vertex-level lobing
# and height-dependent foliage shades; outer leaves break every crown boundary.
for ci,(center,radii) in enumerate(crowns):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1,radius=1)
    o=bpy.context.object
    for vertex in o.data.vertices:
        q=vertex.co.copy()
        noise=(math.sin(q.x*9.1+ci)*math.cos(q.y*7.3-ci*.7)+math.sin(q.z*8.4+ci*1.3))*.075
        q *= .79+noise
        # q is Blender xyz, remap scale to Godot xyz.
        vertex.co=Vector((q.x*radii.x,q.y*radii.z,q.z*radii.y))
    o=finish_obj(o,'Irregular inner canopy',None,root,center)
    for mat in leaves[:3]:o.data.materials.append(mat)
    for face in o.data.polygons:
        face.material_index=2 if face.center.z>.1 else (0 if face.center.z<-.2 else 1)
        face.use_smooth=True
    # A whorl of 3D leaves at random shell points, with a folded center rib.
    verts=[];faces=[];indices=[]
    for j in range(74):
        # Fibonacci directions spread leaves evenly, then loosen the arrangement.
        yy=1-2*(j+.5)/74; aa=j*2.39996+ci*1.37
        rr=math.sqrt(max(0,1-yy*yy)); direction=Vector((math.cos(aa)*rr,yy,math.sin(aa)*rr))
        q=center+Vector((direction.x*radii.x,direction.y*radii.y,direction.z*radii.z))*(.78+random.random()*.24)
        normal=(direction+Vector((0,.45,0))).normalized()
        axis=normal.cross(Vector((0,0,1)))
        if axis.length<.1:axis=normal.cross(Vector((1,0,0)))
        axis.normalize(); side=normal.cross(axis).normalized()
        ang=random.random()*math.tau
        long_axis=axis*math.cos(ang)+side*math.sin(ang); short_axis=normal.cross(long_axis)
        length=.16+random.random()*.085; width=length*(.40+random.random()*.14)
        k=len(verts)
        verts.extend([q-long_axis*length,q-long_axis*length*.25+short_axis*width,q+long_axis*length*.70+short_axis*width*.48,q+long_axis*length,q+long_axis*length*.70-short_axis*width*.48,q-long_axis*length*.25-short_axis*width,q+normal*.045])
        faces.extend([(k+l,k+(l+1)%6,k+6) for l in range(6)])
        shade=random.choices([0,1,2,3,4],[1,3,4,2,1])[0] if direction.y<.3 else random.choice([2,2,3,4])
        indices.extend([shade]*6)
    o=mesh('Lanceolate leaf whorls',verts,faces,None,root,smooth=True)
    for mat in leaves:o.data.materials.append(mat)
    for f,shade in zip(o.data.polygons,indices):f.material_index=shade
# Tiny olives are kept to a few visible clusters, avoiding close-up noise.
fruit=leaves[0]
for i in range(18):
    center,radii=crowns[i%len(crowns)]
    a=i*2.4
    ell('Olive fruit',center+Vector((math.cos(a)*radii.x*.70,-radii.y*.6,math.sin(a)*radii.z*.7)),(.025,.039,.026),fruit,root,8)
import bmesh
for o in root.children_recursive:
    if o.type!='MESH':continue
    bm=bmesh.new();bm.from_mesh(o.data)
    if all(e.is_manifold for e in bm.edges):
        bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(o.data)
    bm.free()
export(root,'olive_tree')
# A separate Blender scene is a reproducible visual proof; existing scenes survive.
preview=bpy.data.scenes.get('DesertDelivery_FoliagePreview')
if preview:
    for o in list(preview.objects):
        if o not in [root]+list(root.children_recursive):bpy.data.objects.remove(o,do_unlink=True)
    bpy.data.scenes.remove(preview)
preview=bpy.data.scenes.new('DesertDelivery_FoliagePreview')
bpy.context.window.scene=preview
for o in [root]+list(root.children_recursive):preview.collection.objects.link(o)
bpy.ops.mesh.primitive_plane_add(size=200)
ground=bpy.context.object;ground.name='Foliage review ground';ground.data.materials.append(material('Preview neutral earth',(.31,.29,.23),1))
world=bpy.data.worlds.new('Foliage Review Sky');world.use_nodes=True;world.node_tree.nodes.get('Background').inputs[0].default_value=(.5,.6,.75,1);world.node_tree.nodes.get('Background').inputs[1].default_value=.65;preview.world=world
bpy.ops.object.light_add(type='SUN',location=(0,0,8));sun=bpy.context.object;sun.name='Foliage review sun';sun.rotation_euler=(math.radians(30),math.radians(-20),math.radians(-35));sun.data.energy=2.5;sun.data.angle=.05
bpy.ops.object.camera_add(location=v((-7,4.7,-7)));camera=bpy.context.object;camera.rotation_euler=(v((0,2.5,0))-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.type='ORTHO';camera.data.ortho_scale=7.2;preview.camera=camera
preview.render.engine='CYCLES';preview.cycles.samples=24;preview.cycles.use_denoising=True
preview.render.resolution_x=1000;preview.render.resolution_y=1000;preview.render.resolution_percentage=100
preview.render.filepath='/tmp/desert-olive-blender.png'
bpy.ops.render.render(write_still=True)
os.makedirs(OUT+'/../source',exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(OUT+'/../source/organic_olive_foliage.blend'),copy=True)
bpy.context.window.scene=previous_scene
print('Organic olive export and preview complete')
