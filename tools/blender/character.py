exec(open('/Users/mun/Documents/Projects/DesertDelivery/tools/blender/common.py').read())
asset=start('CourierCharacter')
# Reference pass: continuous tailored silhouettes and inset almond eyes.
import bmesh
def soften(obj, levels=1):
    bpy.context.view_layer.objects.active=obj
    mod=obj.modifiers.new('Sculpted cloth and facial planes','SUBSURF'); mod.levels=levels
    bpy.ops.object.modifier_apply(modifier=mod.name)
    return obj
skin=material('Skin warm peach',(.72,.49,.29),.78)
hair=material('Hair copper',(.48,.205,.048),.58)
hair_hi=material('Hair golden strands',(.61,.285,.067),.62)
shirt=material('Shirt cornflower',(.23,.29,.43),.87)
seam=material('Shirt seams',(.15,.23,.40),.87)
scarf=material('Neckerchief coral',(.73,.20,.11),.8)
pants=material('Trousers ochre',(.70,.50,.22),.88)
strap=material('Suspenders flax',(.89,.70,.32),.8)
boot=material('Leather walnut',(.125,.069,.039),.74)
sole=material('Soles',(.058,.039,.027),.9)
brass=material('Buckles antique brass',(.44,.34,.16),.36,.65)
white=material('Eye ivory',(.97,.94,.83),.3)
iris=material('Eyes hazel',(.28,.12,.025),.27)
pupil=material('Pupils',(.018,.013,.009),.23)
lip=material('Lips',(.52,.25,.12),.8)
root=empty('Root',asset,(0,.82,0))
hips=loft('Tailored hips',[(-.015,0,0,.16,.10),(0,0,0,.165,.105),(.22,0,0,.164,.111),(.32,0,0,.153,.101)],pants,root)
# Lower waistband shell follows the crotch arch rather than a straight apron hem.
for vertex in hips.data.vertices[:32]:
    q=C.inverted()@vertex.co
    q.y += .12*(abs(q.x)/.16)**1.4
    vertex.co=v(q)
loft('Waistband',[(.280,0,0,.160,.113),(.325,0,0,.160,.113)],strap,root)
# Hidden tucked cloth keeps the rigid pelvis/chest overlap closed when leaning.

torso=empty('Torso',root,(0,.08,0))
loft('Shirt tailored body',[(.17,0,0,.143,.094),(.23,0,0,.152,.101),(.30,0,0,.171,.108),(.43,0,0,.176,.108),(.53,0,0,.185,.099),(.575,0,0,.166,.083),(.606,0,0,.11,.064),(.622,0,0,.057,.052)],shirt,torso)
# Central placket and tiny mother-of-pearl buttons.
tube('Button placket',[(0,.24,-.106),(0,.40,-.110),(0,.56,-.095)],.004,seam,torso)
for y in [.29,.40,.51]: ell('Shirt button',(0,y,-.11),(.007,.007,.003),white,torso,12)
def ribbon(name,points,width,mat,parent):
    dense=[]
    for a,b in zip(points,points[1:]):
        a,b=Vector(a),Vector(b); steps=max(1,int((b-a).length/.008))
        for i in range(steps): dense.append(a.lerp(b,i/steps))
    dense.append(Vector(points[-1])); points=dense
    vertices=[]
    for x,y,z in points: vertices.extend([(x-width/2,y,z),(x+width/2,y,z)])
    obj=mesh(name,vertices,[(i*2,i*2+1,i*2+3,i*2+2) for i in range(len(points)-1)],mat,parent)
    return obj
for s in [-1,1]:
    mesh('Pointed collar',[(s*.035,.624,-.045),(s*.104,.592,-.063),(s*.074,.533,-.110),(s*.026,.594,-.089)],[(0,1,2,3)],shirt,torso)
    ribbon('Front suspender',[(s*.115,.235,-.083),(s*.126,.36,-.085),(s*.142,.51,-.075),(s*.123,.58,-.062),(s*.132,.585,-.055)],.024,strap,torso)
    ribbon('Y suspender',[(s*.132,.585,.055),(s*.12,.58,.061),(s*.067,.48,.106),(0,.42,.114),(0,.235,.108)],.024,strap,torso)
    ribbon('Shoulder suspender',[(s*.132,.585,-.055),(s*.146,.596,0),(s*.132,.585,.055)],.024,strap,torso)
    box('Suspender clip',(s*.115,.24,-.083),(.027,.031,.009),brass,torso,.004)
loft('Folded rear collar',[(.594,0,0,.080,.066),(.600,0,0,.080,.066),(.622,0,0,.064,.058),(.626,0,0,.060,.054)],shirt,torso)
tube('Neck',[(0,.57,0),(0,.73,0)],.052,skin,torso,20)
torus('Scarf collar',(0,.625,0),.054,.014,scarf,torso,'y',32)
ell('Scarf knot',(0,.604,-.063),(.029,.034,.024),scarf,torso)
soften(loft('Scarf soft tail',[(.625,0,-.073,.021,.012),(.593,0,-.087,.035,.016),(.555,0,-.108,.027,.014),(.514,0,-.119,.012,.008),(.492,0,-.119,.001,.001)],scarf,torso,20),2)
head=empty('Head',torso,(0,.79,0))
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
    cx=side*.050; cy=-.006
    outline=[]
    for j in range(32):
        t=math.tau*j/32; x=cx+.028*math.cos(t)
        y=cy+.015*math.sin(t)*(abs(math.sin(t))**.28)
        outline.append((x,y,-.119+.19*abs(x)))
    eye=mesh('Almond sclera',[(cx,cy,-.112)]+outline,[(0,j+1,(j+1)%32+1) for j in range(32)],white,head)
    ell('Hazel iris',(cx,cy,-.113),(.012,.016,.0028),iris,head)
    ell('Pupil',(cx,cy,-.116),(.006,.010,.0016),pupil,head,16)
    ell('Catchlight',(cx-.004,cy+.006,-.118),(.0025,.0025,.001),white,head,12)
    top=[outline[j] for j in range(17)]
    tube('Upper eyelid',top,.0025,boot,head,6)
    tube('Lower eyelid',[outline[j] for j in range(16,32)]+[outline[0]],.0018,skin,head,6)
    tube('Eyebrow',[(side*.023,.027,-.116),(side*.047,.033,-.112),(side*.073,.030,-.104),(side*.082,.024,-.096)],.004,hair,head,8,[.4,1,.8,.1])
# Continuous facial sculpt: nose bridge, tip, cheek planes and a shallow muzzle.
for vertex in face.data.vertices:
    q=C.inverted()@vertex.co
    front=max(0,min(1,(-q.z-.025)/.05))
    bridge=.013*math.exp(-(q.x/.014)**2-((q.y+.012)/.05)**2)
    tip=.026*math.exp(-(q.x/.017)**2-((q.y+.064)/.018)**2)
    cheeks=.004*math.exp(-((abs(q.x)-.060)/.032)**2-((q.y+.045)/.045)**2)
    muzzle=.005*math.exp(-(q.x/.042)**2-((q.y+.091)/.025)**2)
    chin=.051*math.exp(-((q.y+.132)/.045)**2)
    q.z-=(bridge+tip+cheeks+muzzle+chin)*front
    vertex.co=v(q)
for side in [-1,1]: ell('Nostril',(side*.011,-.075,-.126),(.003,.0015,.002),lip,head,12)
tube('Mouth',[(-.028,-.094,-.097),(-.014,-.094,-.107),(0,-.092,-.111),(.014,-.094,-.107),(.028,-.094,-.097)],.0017,lip,head,8)
ell('Lower lip',(0,-.100,-.106),(.017,.003,.002),skin,head,16)
# Flattened swept locks, interpolated along a smooth path; broad interlocking hair masses.
ell('Hair crown',(0,.076,.039),(.132,.098,.105),hair,head,32)
def lock(name,points,width,depth=.46,around=None):
    pts=[Vector(p) for p in points]; dense=[]; widths=[]
    for i in range(len(pts)-1):
        p0=pts[max(0,i-1)]; p1=pts[i]; p2=pts[i+1]; p3=pts[min(len(pts)-1,i+2)]
        for j in range(5):
            t=j/5; dense.append(.5*((2*p1)+(-p0+p2)*t+(2*p0-5*p1+4*p2-p3)*t*t+(-p0+3*p1-3*p2+p3)*t*t*t))
            u=(i+t)/(len(pts)-1); widths.append(max(.006, (.55+u*1.8) if u<.25 else (1.0 if u<.58 else ((1-u)/.42)**.8)))
    dense.append(pts[-1]); widths.append(.008)
    obj=tube(name,dense,width,hair,head,12,widths)
    # Compress each cross-section normal depth, preserving a broad leaf-shaped silhouette.
    for i,center in enumerate(dense):
        for j in range(12):
            vert=obj.data.vertices[i*12+j]; q=C.inverted()@vert.co
            tangent=dense[min(i+1,len(dense)-1)]-dense[max(0,i-1)]
            axis=Vector((-tangent.y,tangent.x,0)).normalized() if around is None else Vector((-math.sin(around),0,math.cos(around)))
            normal=Vector((0,0,1)) if around is None else tangent.cross(axis).normalized()
            angle=math.tau*j/12
            q=center+axis*(math.cos(angle)*width*widths[i])+normal*(math.sin(angle)*width*widths[i]*depth)
            vert.co=v(q)
    return obj
for i in range(9):
    a=math.pi*i/8
    x=math.cos(a)*.117; z=.035+math.sin(a)*.108
    lock('Layered nape',[(x*.18,.204,z*.26),(x*.66,.163,z*.77),(x,.076,z),(x*1.13,-.028-.015*math.cos(i*2),z+.023),(x*1.26,-.082-.012*math.cos(i*2),z+.035)],.049,.47,a)
for i in range(6):
    a=.12+math.pi*i/5.4
    x=math.cos(a)*.112; z=.04+math.sin(a)*.106
    lock('Layered undercurl',[(x*.80,.056,z*.90),(x,-.007,z),(x*1.07,-.062,z+.014),(x*1.23,-.096,z+.027),(x*1.35,-.116,z+.035)],.034,.48,a)
lock('Hero swept forelock',[(-.097,.138,-.030),(-.070,.194,-.046),(.002,.170,-.101),(.060,.118,-.122),(.045,.058,-.124)],.056,.48)
lock('Left swept temple',[(-.106,.133,-.017),(-.124,.113,-.064),(-.120,.063,-.083),(-.103,.023,-.076)],.038,.56)
lock('Right swept wave',[(-.048,.180,-.025),(.027,.193,-.043),(.095,.158,-.072),(.135,.136,-.057),(.151,.161,-.039)],.053,.52)
lock('Right lower wave',[(.026,.146,-.067),(.076,.121,-.092),(.124,.085,-.065),(.147,.090,-.033)],.040,.55)
lock('Crown crest',[(-.094,.136,.013),(-.092,.209,-.007),(-.057,.212,-.014),(.011,.186,-.040)],.046,.55)
lock('Fine forelock edge',[(-.072,.190,-.068),(-.025,.166,-.121),(.027,.107,-.141),(.048,.072,-.133)],.025,.35)
lock('Fine swept crest',[(-.101,.178,-.036),(-.124,.210,-.032),(-.133,.241,-.018),(-.116,.211,-.028)],.023,.5)
for s in [-1,1]:
    ell('Shirt shoulder drape',(s*.151,.522,0),(.063,.055,.079),shirt,torso,32)
    arm=empty('ArmL' if s<0 else 'ArmR',torso,(s*.185,.54,0))
    loft('Loose sleeve',[(.018,-s*.025,0,.054,.052),(.008,-s*.008,0,.060,.063),(-.075,s*.005,0,.067,.066),(-.20,s*.012,0,.076,.068),(-.305,s*.012,0,.065,.059),(-.335,s*.008,0,.058,.054)],shirt,arm)
    soften(loft('Rolled cuff',[(-.280,s*.008,0,.059,.057),(-.291,s*.008,0,.070,.065),(-.326,s*.008,0,.074,.067),(-.354,s*.008,0,.066,.061),(-.359,s*.008,0,.059,.056)],shirt,arm),1)
    tube('Cuff seam',[(s*.01,-.343,-.061),(s*.04,-.343,-.046)],.003,seam,arm)
    elbow=empty('Elbow',arm,(0,-.395,0))
    loft('Forearm',[(.062,0,0,.043,.045),(-.06,0,0,.045,.042),(-.12,0,-.002,.032,.032),(-.18,0,-.005,.026,.027)],skin,elbow,24)
    hand=empty('Hand',elbow,(0,-.235,0))
    ell('Fingerless glove',(0,.007,-.004),(.039,.063,.025),boot,hand)
    loft('Glove cuff',[(.039,0,0,.035,.031),(.076,0,0,.038,.034),(.095,0,0,.0405,.036)],boot,hand,24)
    box('Glove stitched knuckle patch',(0,.014,-.028),(.054,.052,.006),boot,hand,.006)
    for i in range(4):
        x=-.025+i*.016
        tube('Fingers',[(x,-.027,-.01),(x,-.063-[.001,.010,.007,-.005][i],-.010),(x,-.087-[.001,.010,.007,-.005][i],-.016)],.0105,skin,hand,12,[1,.9,.6])
    tube('Thumb',[(s*.036,.003,0),(s*.047,-.025,-.019),(s*.044,-.043,-.026)],.012,skin,hand,8,[1,.9,.6])
    leg=empty('LegL' if s<0 else 'LegR',root,(s*.09,0,0))

    loft('Wide trouser leg',[(.13,0,0,.085,.103),(-.035,s*.012,0,.102,.111),(-.15,s*.031,0,.115,.118),(-.29,s*.036,0,.130,.119),(-.435,s*.038,0,.129,.113)],pants,leg)
    tube('Trouser outside seam',[(s*.078,0,0),(s*.108,-.21,0),(s*.091,-.40,0)],.0026,strap,leg,5)
    knee=empty('Knee',leg,(0,-.42,0))

    loft('Gathered breeches',[(.020,s*.038,0,.129,.113),(-.04,s*.038,0,.130,.111),(-.09,s*.038,0,.125,.104),(-.115,s*.038,0,.100,.078),(-.125,s*.038,0,.056,.052)],pants,knee)
    loft('Gathered cuff',[(-.075,s*.05,0,.062,.055),(-.107,s*.05,0,.056,.050)],strap,knee)
    loft('Long sock',[(-.105,s*.05,0,.040,.038),(-.16,s*.05,0,.037,.035),(-.235,s*.05,0,.030,.030),(-.28,s*.05,0,.031,.031)],pants,knee,24)
    ell('Boot sole',(s*.05,-.367,-.036),(.076,.018,.128),sole,knee,32)
    ell('Laced shoe',(s*.05,-.335,-.047),(.074,.052,.125),boot,knee)
    loft('Boot ankle',[(-.34,s*.05,.012,.054,.060),(-.29,s*.05,.012,.050,.051),(-.232,s*.05,.008,.051,.053)],boot,knee,24)
    for i in range(4):
        tube('Boot lace',[(s*.05-.029,-.286-i*.011,-.038-i*.013),(s*.05+.027,-.297-i*.009,-.045-i*.014)],.0028,stitch if 'stitch' in globals() else brass,knee,5)
exec(open('/Users/mun/Documents/Projects/DesertDelivery/tools/blender/character_hair.py').read())
exec(open('/Users/mun/Documents/Projects/DesertDelivery/tools/blender/character_shoes.py').read())
# Match the reference's longer rounded forefoot without moving ankle/heel contacts.
for obj in list(asset.children_recursive):
    if obj.type=='MESH' and obj.name.startswith('Shoe '):
        inv=obj.matrix_local.inverted()
        for vertex in obj.data.vertices:
            q=C.inverted()@(obj.matrix_local@vertex.co)
            if q.z<-.04: q.z=-.04+(q.z+.04)*1.30
            vertex.co=inv@v(q)
# Reference-only detail edits before unifying clothing and attaching a skin.
for obj in list(asset.children_recursive):
    if obj.type!='MESH': continue
    if obj.parent==head:
        for vertex in obj.data.vertices:
            q=C.inverted()@vertex.co
            if obj.name.startswith(('Hair','Layered','Hero swept','Left swept','Right','Crown','Fine')):
                q.x=-q.x*1.10
                if q.y>0: q.y*=.87
            vertex.co=v(q*.82)
        obj.location*=.82
    if obj.name.startswith(('Scarf hanging',)):
        for vertex in obj.data.vertices: vertex.co.z+=.070
    if obj.parent and obj.parent.name.startswith('Arm'):
        pass
# A-pose at bind time separates the sleeve from the side seam during remeshing.
for side,pivot in [(-1,arm if False else bpy.data.objects.get('ArmL')),(1,bpy.data.objects.get('ArmR'))]:
    if pivot: pivot.rotation_euler.y=-side*.30
bpy.context.view_layer.update()
exec(open('/Users/mun/Documents/Projects/DesertDelivery/tools/blender/character_face.py').read())
exec(open('/Users/mun/Documents/Projects/DesertDelivery/tools/blender/character_skin.py').read())
exec(open('/Users/mun/Documents/Projects/DesertDelivery/tools/blender/character_accessory_skin.py').read())
for obj in list(asset.children_recursive):
    if obj.type!='MESH': continue
    bm=bmesh.new(); bm.from_mesh(obj.data); bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces)); bm.to_mesh(obj.data); bm.free()
export(asset,'courier_character')
bpy.ops.wm.save_as_mainfile(filepath='/Users/mun/Documents/Projects/DesertDelivery/assets/source/courier_reference.blend')
