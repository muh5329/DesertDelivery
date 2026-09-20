exec(open('/Users/mun/Documents/Projects/DesertDelivery/tools/blender/common.py').read())
asset=start('CourierCharacter')
# Reference pass: continuous tailored silhouettes and inset almond eyes.
import bmesh
def soften(obj, levels=1):
    bpy.context.view_layer.objects.active=obj
    mod=obj.modifiers.new('Sculpted cloth and facial planes','SUBSURF'); mod.levels=levels
    bpy.ops.object.modifier_apply(modifier=mod.name)
    return obj
skin=material('Skin warm peach',(.88,.65,.42),.78)
hair=material('Hair copper',(.48,.205,.048),.58)
hair_hi=material('Hair golden strands',(.61,.285,.067),.62)
shirt=material('Shirt cornflower',(.30,.39,.58),.87)
seam=material('Shirt seams',(.15,.23,.40),.87)
scarf=material('Neckerchief coral',(.73,.20,.11),.8)
pants=material('Trousers ochre',(.79,.60,.30),.88)
strap=material('Suspenders flax',(.89,.70,.32),.8)
boot=material('Leather walnut',(.125,.069,.039),.74)
sole=material('Soles',(.058,.039,.027),.9)
brass=material('Buckles antique brass',(.44,.34,.16),.36,.65)
white=material('Eye ivory',(.97,.94,.83),.3)
iris=material('Eyes hazel',(.28,.12,.025),.27)
pupil=material('Pupils',(.018,.013,.009),.23)
lip=material('Lips',(.52,.25,.12),.8)
root=empty('Root',asset,(0,.82,0))
hips=loft('Tailored hips',[(-.015,0,0,.16,.10),(0,0,0,.165,.105),(.16,0,0,.160,.102),(.25,0,0,.153,.100)],pants,root)
# Lower waistband shell follows the crotch arch rather than a straight apron hem.
for vertex in hips.data.vertices[:32]:
    q=C.inverted()@vertex.co
    q.y += .12*(abs(q.x)/.16)**1.4
    vertex.co=v(q)
loft('Waistband',[(.215,0,0,.156,.106),(.255,0,0,.156,.106)],strap,root)
# Hidden tucked cloth keeps the rigid pelvis/chest overlap closed when leaning.
ell('Tucked shirt overlap',(0,.22,-.005),(.146,.115,.098),shirt,root,24)
torso=empty('Torso',root,(0,.08,0))
loft('Shirt tailored body',[(.065,0,0,.142,.094),(.15,0,0,.149,.098),(.19,0,0,.161,.104),(.27,0,0,.168,.106),(.39,0,0,.179,.101),(.47,0,0,.184,.090),(.51,0,0,.149,.079),(.545,0,0,.059,.052)],shirt,torso)
# Central placket and tiny mother-of-pearl buttons.
tube('Button placket',[(0,.18,-.106),(0,.30,-.108),(0,.49,-.094)],.004,seam,torso)
for y in [.24,.34,.44]: ell('Shirt button',(0,y,-.11),(.007,.007,.003),white,torso,12)
def ribbon(name,points,width,mat,parent):
    vertices=[]
    for x,y,z in points: vertices.extend([(x-width/2,y,z),(x+width/2,y,z)])
    obj=mesh(name,vertices,[(i*2,i*2+1,i*2+3,i*2+2) for i in range(len(points)-1)],mat,parent)
    mod=obj.modifiers.new('Woven strap thickness','SOLIDIFY'); mod.thickness=.003
    bpy.context.view_layer.objects.active=obj; bpy.ops.object.modifier_apply(modifier=mod.name)
    return obj
for s in [-1,1]:
    mesh('Pointed collar',[(s*.045,.55,-.056),(s*.12,.505,-.092),(s*.078,.442,-.108),(s*.022,.509,-.094)],[(0,1,2,3)],shirt,torso)
    ribbon('Front suspender',[(s*.115,.18,-.078),(s*.126,.27,-.079),(s*.145,.45,-.067),(s*.11,.525,-.056)],.022,strap,torso)
    ribbon('Y suspender',[(s*.11,.525,.056),(s*.07,.34,.100),(0,.25,.111),(0,.18,.108)],.022,strap,torso)
    box('Suspender clip',(s*.115,.185,-.119),(.031,.038,.012),brass,torso,.005)
tube('Neck',[(0,.51,0),(0,.64,0)],.052,skin,torso,20)
torus('Scarf collar',(0,.565,0),.062,.016,scarf,torso,'y',32)
ell('Scarf knot',(0,.535,-.074),(.035,.040,.030),scarf,torso)
mesh('Scarf hanging triangle',[(-.039,.54,-.09),(.039,.54,-.09),(.026,.46,-.114),(0,.411,-.10),(-.026,.46,-.114),(0,.51,-.129)],[(0,5,4),(4,5,3),(3,5,2),(2,5,1),(1,5,0)],scarf,torso)
head=empty('Head',torso,(0,.74,0))
# Broad facial planes: flatten the front of the oval, rather than mount eyes on a sphere.
face=loft('Face',[(-.158,0,-.016,.043,.043),(-.14,0,-.010,.075,.065),(-.106,0,0,.101,.082),(-.060,0,.004,.120,.098),(.008,0,.008,.127,.106),(.069,0,.014,.127,.110),(.12,0,.02,.11,.095),(.151,0,.025,.07,.064),(.16,0,.025,.018,.02)],skin,head,48)
for vert in face.data.vertices:
    q=C.inverted()@vert.co
    if q.z < -.035 and abs(q.x)<.112 and -.11<q.y<.095:
        q.z-=.018*(1-(q.x/.13)**2)
        vert.co=v(q)
soften(face,2)
for side in [-1,1]:
    ell('Ear',(side*.127,-.029,.009),(.022,.037,.022),skin,head)
    ell('Ear concha',(side*.143,-.028,-.005),(.005,.019,.011),lip,head,16)
    # Almond surface follows the facial curvature, only 1 mm proud of the skin.
    cx=side*.052; cy=.009
    outline=[]
    for j in range(32):
        t=math.tau*j/32; x=cx+.033*math.cos(t)
        y=cy+.017*math.sin(t)*(abs(math.sin(t))**.28)
        outline.append((x,y,-.119+.19*abs(x)))
    eye=mesh('Almond sclera',[(cx,cy,-.112)]+outline,[(0,j+1,(j+1)%32+1) for j in range(32)],white,head)
    ell('Hazel iris',(cx,cy,-.113),(.012,.016,.0028),iris,head)
    ell('Pupil',(cx,cy,-.116),(.006,.010,.0016),pupil,head,16)
    ell('Catchlight',(cx-.004,cy+.006,-.118),(.0025,.0025,.001),white,head,12)
    top=[outline[j] for j in range(17)]
    tube('Upper eyelid',top,.0025,boot,head,6)
    tube('Lower eyelid',[outline[j] for j in range(16,32)]+[outline[0]],.0018,skin,head,6)
    tube('Eyebrow',[(side*.023,.046,-.116),(side*.047,.053,-.112),(side*.073,.048,-.104),(side*.085,.042,-.096)],.004,hair,head,8,[.4,1,.8,.1])
# One connected tapered nose, embedded bridge and subtle nostrils.
soften(loft('Nose',[(-.052,0,-.115,.012,.010),(-.044,0,-.129,.017,.016),(-.034,0,-.126,.013,.015),(-.014,0,-.114,.010,.012),(.010,0,-.103,.008,.005)],skin,head,24),1)
for side in [-1,1]: ell('Nostril',(side*.010,-.049,-.132),(.003,.0018,.002),lip,head,12)
tube('Mouth',[(-.028,-.094,-.097),(-.014,-.094,-.107),(0,-.092,-.111),(.014,-.094,-.107),(.028,-.094,-.097)],.0017,lip,head,8)
ell('Lower lip',(0,-.100,-.106),(.017,.003,.002),skin,head,16)
# Flattened swept locks, interpolated along a smooth path; broad interlocking hair masses.
ell('Hair crown',(0,.095,.043),(.136,.105,.109),hair,head,32)
def lock(name,points,width,depth=.46):
    pts=[Vector(p) for p in points]; dense=[]; widths=[]
    for i in range(len(pts)-1):
        p0=pts[max(0,i-1)]; p1=pts[i]; p2=pts[i+1]; p3=pts[min(len(pts)-1,i+2)]
        for j in range(5):
            t=j/5; dense.append(.5*((2*p1)+(-p0+p2)*t+(2*p0-5*p1+4*p2-p3)*t*t+(-p0+3*p1-3*p2+p3)*t*t*t))
            u=(i+t)/(len(pts)-1); widths.append(max(.006,min(.7+u*3,1.0)*(1-u)**.85))
    dense.append(pts[-1]); widths.append(.008)
    obj=tube(name,dense,width,hair,head,12,widths)
    # Compress each cross-section normal depth, preserving a broad leaf-shaped silhouette.
    for i,center in enumerate(dense):
        for j in range(12):
            vert=obj.data.vertices[i*12+j]; q=C.inverted()@vert.co
            tangent=dense[min(i+1,len(dense)-1)]-dense[max(0,i-1)]
            axis=Vector((-tangent.y,tangent.x,0)).normalized()
            angle=math.tau*j/12
            q=center+axis*(math.cos(angle)*width*widths[i])+Vector((0,0,math.sin(angle)*width*widths[i]*depth))
            vert.co=v(q)
    return obj
for i in range(11):
    a=math.pi*i/10
    x=math.cos(a)*.113; z=.035+math.sin(a)*.105
    lock('Layered nape',[(x*.65,.155,z*.65),(x,.072,z),(x*1.02,-.015,z+.004),(x*1.08,-.055-.020*math.cos(i*2),z+.015),(x*1.20,-.085-.028*math.cos(i*2),z+.015)],.032,.7)
lock('Hero swept forelock',[(-.097,.138,-.030),(-.070,.194,-.046),(.002,.170,-.101),(.060,.118,-.122),(.045,.058,-.124)],.046,.48)
lock('Left swept temple',[(-.106,.133,-.017),(-.124,.113,-.064),(-.120,.063,-.083),(-.103,.023,-.076)],.038,.56)
lock('Right swept wave',[(-.048,.180,-.025),(.027,.193,-.043),(.095,.158,-.072),(.135,.136,-.057),(.151,.161,-.039)],.048,.52)
lock('Right lower wave',[(.026,.146,-.067),(.076,.121,-.092),(.124,.085,-.065),(.147,.090,-.033)],.040,.55)
lock('Crown crest',[(-.094,.136,.013),(-.092,.209,-.007),(-.057,.212,-.014),(.011,.186,-.040)],.046,.55)
lock('Fine forelock edge',[(-.072,.190,-.068),(-.025,.166,-.121),(.027,.107,-.141),(.048,.072,-.133)],.025,.35)
lock('Fine swept crest',[(-.101,.178,-.036),(-.124,.210,-.032),(-.133,.241,-.018),(-.116,.211,-.028)],.023,.5)
for s in [-1,1]:
    arm=empty('ArmL' if s<0 else 'ArmR',torso,(s*.20,.50,0))
    loft('Loose sleeve',[(.018,-s*.025,0,.054,.052),(.008,-s*.008,0,.060,.063),(-.05,s*.005,0,.078,.073),(-.12,s*.012,0,.076,.070),(-.17,s*.012,0,.062,.058),(-.21,s*.008,0,.058,.054)],shirt,arm)
    loft('Rolled cuff',[(-.175,s*.008,0,.065,.061),(-.195,s*.008,0,.070,.064),(-.222,s*.008,0,.064,.060)],shirt,arm)
    tube('Cuff seam',[(s*.01,-.192,-.061),(s*.04,-.192,-.046)],.003,seam,arm)
    ell('Elbow skin',(0,-.239,0),(.043,.040,.045),skin,arm)
    elbow=empty('Elbow',arm,(0,-.26,0))
    loft('Forearm',[(.012,0,0,.043,.045),(-.06,0,0,.045,.042),(-.16,0,-.002,.032,.032),(-.235,0,-.005,.026,.027)],skin,elbow,24)
    hand=empty('Hand',elbow,(0,-.27,0))
    ell('Fingerless glove',(0,-.005,-.004),(.039,.050,.024),boot,hand)
    loft('Glove cuff',[(.028,0,0,.030,.028),(.048,0,0,.033,.029),(.065,0,0,.030,.027)],boot,hand,24)
    for i in range(4):
        x=-.025+i*.016
        tube('Fingers',[(x,-.027,-.01),(x,-.071,-.008),(x,-.086,-.022)],.008,skin,hand,8,[1,.9,.6])
    tube('Thumb',[(s*.036,.003,0),(s*.047,-.025,-.019),(s*.044,-.043,-.026)],.012,skin,hand,8,[1,.9,.6])
    leg=empty('LegL' if s<0 else 'LegR',root,(s*.09,0,0))
    ell('Hip cloth overlap',(0,.045,0),(.086,.105,.103),pants,leg,24)
    loft('Wide trouser leg',[(.13,0,0,.085,.103),(-.035,s*.012,0,.102,.111),(-.19,s*.020,0,.108,.110),(-.34,s*.024,0,.108,.103),(-.435,s*.024,0,.103,.097)],pants,leg)
    tube('Trouser outside seam',[(s*.078,0,0),(s*.108,-.21,0),(s*.091,-.40,0)],.0026,strap,leg,5)
    knee=empty('Knee',leg,(0,-.42,0))
    ell('Continuous knee cloth',(s*.024,0,0),(.102,.100,.096),pants,knee,24)
    loft('Gathered breeches',[(.010,s*.024,0,.103,.097),(-.05,s*.024,0,.107,.096),(-.135,s*.024,0,.105,.090),(-.19,s*.024,0,.094,.079),(-.204,s*.024,0,.053,.051)],pants,knee)
    loft('Gathered cuff',[(-.197,s*.024,0,.058,.052),(-.226,s*.024,0,.054,.050)],strap,knee)
    tube('Long sock',[(s*.024,-.22,0),(s*.014,-.31,0)],.039,pants,knee,16)
    ell('Boot sole',(s*.014,-.367,-.036),(.065,.018,.118),sole,knee,32)
    ell('Laced shoe',(s*.014,-.335,-.047),(.064,.048,.113),boot,knee)
    loft('Boot ankle',[(-.34,s*.014,.012,.054,.060),(-.29,s*.014,.012,.050,.051),(-.265,s*.014,.008,.044,.045)],boot,knee,24)
    for i in range(4):
        tube('Boot lace',[(s*.014-.029,-.286-i*.011,-.038-i*.013),(s*.014+.027,-.297-i*.009,-.045-i*.014)],.0028,stitch if 'stitch' in globals() else brass,knee,5)
# Polish individual cloth masses before batching so collars/eyes/joint caps retain shape.
for obj in list(asset.children_recursive):
    if obj.type!='MESH': continue
    if obj.name.startswith(('Shirt tailored','Loose sleeve','Wide trouser','Gathered breeches','Tailored hips')):
        # Open joint boundaries preserve equal radii instead of subdividing caps into beads.
        bm=bmesh.new(); bm.from_mesh(obj.data)
        bmesh.ops.delete(bm,geom=[f for f in bm.faces if len(f.verts)>4 and (obj.name.startswith('Gathered breeches') or (obj.name.startswith('Wide trouser') and f.calc_center_median().z<0))],context='FACES_ONLY')
        bm.to_mesh(obj.data); bm.free(); soften(obj,1)
    bm=bmesh.new(); bm.from_mesh(obj.data); bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces)); bm.to_mesh(obj.data); bm.free()
export(asset,'courier_character')
bpy.ops.wm.save_as_mainfile(filepath='/Users/mun/Documents/Projects/DesertDelivery/assets/source/courier_reference.blend')
