"""Mediterranean town revision, authored through Blender MCP; Godot metres, front -Z."""
exec(open('/Users/mun/Documents/Projects/DesertDelivery/tools/blender/common.py').read())
random.seed(1904)
# Repair winding of closed meshes (including loft caps) before the GLB is batched.
_raw_export = export
def export(root, filename):
    import bmesh
    for obj in root.children_recursive:
        if obj.type != 'MESH': continue
        bm=bmesh.new(); bm.from_mesh(obj.data)
        if all(e.is_manifold for e in bm.edges):
            bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
            bm.to_mesh(obj.data); obj.data.update()
        bm.free()
    _raw_export(root,filename)
plaster=material('Town lime plaster',(.88,.85,.75),.93)
stone=material('Town limestone trim',(.61,.60,.52),.9)
blue=material('Aegean blue ceramic',(.025,.24,.43),.42)
wood=material('Town walnut wood',(.13,.072,.033),.87)
glass=material('Town warm window glass',(.14,.20,.22),.25,.15)
iron=material('Town iron rail',(.07,.10,.11),.58,.6)
ivory=material('Town canvas cream',(.90,.86,.73),.9)
clay=material('Town terracotta clay',(.58,.26,.14),.91)
foliage=[material('Town foliage '+str(i),c,.9) for i,c in enumerate([(.13,.30,.045),(.28,.46,.065),(.43,.59,.11)])]

def arch(name,c,w,h,depth,mat,root):
    # Solid arched profile used for dark recesses and roof dormers.
    x,y,z=c; r=w*.5; vs=[(x-r,y,z),(x+r,y,z)]
    for i in range(17):
        a=i*math.pi/16; vs.append((x+r*math.cos(a),y+h-r+r*math.sin(a),z))
    nn=len(vs); vs += [(a,b,d+depth) for a,b,d in vs]
    fs=[tuple(reversed(range(nn))),tuple(range(nn,nn*2))]
    fs += [(i,(i+1)%nn,(i+1)%nn+nn,i+nn) for i in range(nn)]
    return mesh(name,vs,fs,mat,root,smooth=False)

def dome(root,h):
    box('Bell room',(0,h+.73,.55),(2.4,1.5,2.4),plaster,root,.065)
    arch('Arched bell opening',(0,h+.05,-.68),1.15,1.42,.035,wood,root)
    for x in [-1.15,1.15]: box('Bell pilaster',(x,h+.7,-.65),(.13,1.5,.14),stone,root,.015)
    # Hemisphere with flat equator, unlike a sphere sunk through the roof.
    vs=[]; fs=[]; n=40; m=10
    for j in range(m+1):
        a=j*math.pi*.5/m
        for i in range(n):
            b=i*math.tau/n; vs.append((1.36*math.cos(a)*math.cos(b),h+1.49+1.22*math.sin(a),.55+1.36*math.cos(a)*math.sin(b)))
    for j in range(m):
        for i in range(n): q=j*n+i; r=j*n+(i+1)%n; fs.append((q,r,r+n,q+n))
    mesh('Cobalt glazed dome',vs,fs,blue,root)
    tube('Dome rim',[(-1.28,h+1.50,-.68),(1.28,h+1.50,-.68)],.055,blue,root)

def town_house(floors,style):
    root=start('TownHouse%d_%d'%(floors,style)); h=3.15*floors
    box('Solid lime plaster',(0,h*.5-1.25,0),(6,h+2.5,6),plaster,root,.065)
    for y in [.22,h]+([3.15] if floors>1 else []): box('Limestone cornice',(0,y,0),(6.14,.15,6.14),stone,root,.02)
    box('Roof terrace tiles',(0,h+.035,0),(5.9,.08,5.9),clay,root,.02)
    for side in [-1,1]:
        box('Terrace parapet',(side*2.93,h+.30,0),(.18,.58,6.02),plaster,root,.045)
        box('Terrace parapet',(0,h+.30,side*2.93),(6.02,.58,.18),plaster,root,.045)
        box('Parapet coping',(side*2.93,h+.61,0),(.27,.10,6.10),stone,root,.025)
        box('Parapet coping',(0,h+.61,side*2.93),(6.10,.10,.27),stone,root,.025)
    if style==1:
        # Traditional barrel-vaulted roof; stone outline along curved ends.
        vs=[]; fs=[]
        for z in [-1.85,2.35]:
            for i in range(25):
                a=i*math.pi/24; vs.append((2.12*math.cos(a),h+2.12*math.sin(a),z))
        for i in range(24): fs.append((i,i+1,i+26,i+25))
        fs.extend([tuple(range(24,-1,-1)),tuple(range(25,50))])
        mesh('Barrel vault plaster',vs,fs,plaster,root)
        for z in [-1.88,2.38]:
            tube('Vault stone seam',[(2.12*math.cos(i*math.pi/24),h+2.12*math.sin(i*math.pi/24),z) for i in range(25)],.047,stone,root)
    if style==2: dome(root,h)
    for f in range(floors):
        y=1.85+f*3.15
        for x in [-1.75,1.75]:
            for s in [-1,1]:
                z=s*3.045
                box('Window shadow',(x,y,z),(1.18,1.55,.07),wood,root,.018)
                box('Window glass',(x,y,z+s*.035),(.91,1.29,.06),glass,root,.012)
                for dx in [-.52,.52]: box('Blue jamb',(x+dx,y,z+s*.07),(.115,1.5,.13),blue,root,.012)
                for dy in [-.70,.70]: box('Blue frame',(x,y+dy,z+s*.07),(1.12,.115,.13),blue,root,.012)
                box('Window mullion',(x,y,z+s*.09),(.043,1.4,.065),stone,root,.008)
                box('Limestone sill',(x,y-.81,z+s*.10),(1.32,.13,.33),stone,root,.02)
                if s<0 and (style+f)%2==0:
                    box('Blue shutter',(x+.83,y,z),(.44,1.49,.10),blue,root,.015)
                    for j in range(8): box('Shutter louvers',(x+.83,y-.58+j*.165,z-.07),(.36,.045,.04),stone,root,.004)
        for s in [-1,1]:
            for z in [-1.62,1.62]:
                box('Side window frame',(s*3.055,y,z),(.12,1.5,1.12),blue,root,.014)
                box('Side glazing',(s*3.13,y,z),(.035,1.25,.88),glass,root,.01)
                box('Side mullion',(s*3.16,y,z),(.04,1.3,.045),ivory,root,.004)
                box('Side sill',(s*3.16,y-.8,z),(.3,.14,1.28),stone,root,.02)
    arch('Arched limestone door surround',(0,0,-3.075),1.65,2.68,.075,stone,root)
    arch('Door timber',(0,.09,-3.165),1.32,2.40,.055,blue if style!=1 else wood,root)
    for i in range(6): box('Door boards',(-.53+i*.212,1.08,-3.205),(.018,1.96,.015),wood,root,.002)
    ell('Brass handle',(.41,1.10,-3.25),(.035,.045,.03),stone,root,12)
    box('Threshold',(0,.045,-3.25),(1.6,.09,.48),stone,root,.025)
    # Striped awning, brackets, inset address tile and street lantern.
    for i in range(10):
        x=-1.55+i*.31
        mesh('Blue striped awning',[(x,2.74,-3.08),(x+.31,2.74,-3.08),(x+.31,2.50,-3.90),(x,2.50,-3.90)],[(0,1,2,3)],blue if i%2 else ivory,root,smooth=False)
        box('Awning scallop',(x+.155,2.43,-3.89),(.307,.17,.035),blue if i%2 else ivory,root,.065)
    box('Address blue tile',(.99,1.99,-3.095),(.39,.26,.065),blue,root,.023)
    for xx in [.9,1.02,1.11]: box('Address lettering',(xx,1.99,-3.137),(.03,.12,.008),ivory,root,.002)
    tube('Lantern bracket',[(2.5,2.48,-3.0),(2.5,2.7,-3.44)],.023,iron,root)
    box('Lantern',(2.5,2.46,-3.4),(.20,.29,.20),ivory,root,.025)
    box('Lantern cap',(2.5,2.64,-3.4),(.29,.06,.28),iron,root,.02)
    if floors>1:
        box('Balcony',(0,3.21,-3.46),(3.8,.18,1.05),plaster,root,.025)
        for xx in [-1.85,1.85]: box('Balcony cheeks',(xx,3.62,-3.46),(.14,.76,1.03),plaster,root,.025)
        for xx in [-1.70+i*.28 for i in range(13)]: tube('Blue balustrade',[(xx,3.3,-3.93),(xx,4.02,-3.93)],.019,blue,root,6)
        tube('Balcony top rail',[(-1.83,4.04,-3.93),(1.83,4.04,-3.93)],.035,blue,root)
    # Trailing ivy strands, silhouette foliage and a corner planter.
    for i in range(28):
        y=h-.24-i*.13; x=2.63+math.sin(i*.95)*.19; z=-3.12-random.random()*.09
        ell('Trailing ivy',(x,y,z),(.16,.15,.09),foliage[i%3],root,8)
    loft('Terracotta pot',[(0,2.48,-3.40,.22,.22),(.45,2.48,-3.40,.35,.35),(.54,2.48,-3.40,.36,.36)],clay,root,16)
    for i in range(13):
        a=i*2.4; ell('Planter foliage',(2.48+math.cos(a)*.25,.67+(i%3)*.10,-3.40+math.sin(a)*.25),(.23,.17,.23),foliage[i%3],root,10)
    export(root,'town_house_%d_%d'%(floors,style))

def palm():
    root=start('HarbourPalm')
    tube('Leaning palm trunk',[(0,0,0),(.14,1.5,0),(.36,3,.1),(.64,4.4,.20),(.78,5.7,.26)],.19,wood,root,12,[1.2,1.05,.95,.85,.70])
    for i in range(22):
        y=.18+i*.24; x=.78*(y/5.7)**1.2
        torus('Trunk growth ring',(x,y,.26*y/5.7),.17-i*.0018,.014,clay,root,'y',12,4)
    for i in range(13):
        a=i*2.4; length=2.3+(i%3)*.25
        pts=[]
        for j in range(9):
            t=j/8; r=length*t; pts.append(Vector((.78+math.cos(a)*r,5.7+math.sin(t*math.pi)*.57-t*.70,.26+math.sin(a)*r)))
        tube('Palm frond stem',pts,.021,foliage[1],root,6,[1-j*.10 for j in range(9)])
        for j in range(1,9):
            t=j/8; c=pts[j]; side=Vector((-math.sin(a),0,math.cos(a))); forward=Vector((math.cos(a),-.34,math.sin(a)))
            ln=math.sin(t*math.pi*.92)*.61
            for s in [-1,1]:
                tip=c+side*s*ln+forward*.29
                mesh('Palm leaflets',[c-forward*.1,c+forward*.10,tip+Vector((0,-.12,0)),(c+tip)*.5+Vector((0,.035,0))],[(0,1,3),(1,2,3),(2,0,3)],foliage[(i+j)%3],root)
    export(root,'harbour_palm')

def car():
    root=start('IslandCar'); body=material('Car seafoam',(.16,.43,.38),.28,.10); cream=material('Car ivory roof',(.86,.83,.68),.34)
    tire=material('Car tire rubber',(.022,.026,.028),.87); chrome=material('Car polished chrome',(.64,.70,.69),.23,.8); dark=material('Car interior',(.045,.056,.057),.8)
    glass_car=material('Car blue tinted glass',(.10,.23,.29,.38),.13,.12)
    lamp=material('Car headlamp ivory',(.98,.86,.60),.23); red=material('Car tail red',(.70,.035,.018),.28)
    box('Chassis',(0,.40,0),(1.17,.18,2.76),dark,root,.07)
    # Curved side skins with actual wheel arch clearances.
    for s in [-1,1]:
        vs=[]; fs=[]; steps=90
        for i in range(steps+1):
            z=-1.55+3.1*i/steps; lower=.36
            for axle in [-1.,1.]:
                dz=z-axle
                if abs(dz)<.39: lower=max(lower,.34+math.sqrt(.39**2-dz**2))
            width=.70-.13*(abs(z)/1.55)**4
            vs.extend([(s*width,lower,z),(s*(width+.015),.83+.04*(1-abs(z)/1.55),z)])
        for i in range(steps): fs.append((2*i,2*i+1,2*i+3,2*i+2))
        mesh('Sculpted wheel arch body',vs,fs,body,root)
        tube('Belt chrome',[(s*.59,.88,-1.52),(s*.715,.91,-.70),(s*.715,.91,.70),(s*.59,.88,1.52)],.017,chrome,root)
        for z in [-1.,1.]:
            tube('Wheel arch lip',[(s*(.70-.13*(abs(z+.395*math.cos(j*math.pi/24))/1.55)**4),.34+.395*math.sin(j*math.pi/24),z+.395*math.cos(j*math.pi/24)) for j in range(25)],.024,body,root)
    box('Rounded bonnet',(0,.84,-1.02),(1.27,.20,1.12),body,root,.105)
    box('Front rounded fascia',(0,.665,-1.49),(1.22,.39,.17),body,root,.08)
    box('Rear rounded fascia',(0,.665,1.49),(1.22,.39,.15),body,root,.08)
    box('Rounded rear deck',(0,.83,1.15),(1.27,.19,.82),body,root,.105)
    box('Cab sill',(0,.84,.08),(1.34,.11,1.29),body,root,.04)
    box('Ivory curved roof',(0,1.56,.05),(1.17,.13,1.38),cream,root,.09)
    # Sloped windscreen and rear light; window doors with framed blue glass.
    mesh('Windscreen',[(-.58,.94,-.69),(.58,.94,-.69),(.53,1.51,-.56),(-.53,1.51,-.56)],[(0,1,2,3)],glass_car,root,smooth=False)
    mesh('Rear window',[(-.58,.94,.82),(.58,.94,.82),(.53,1.51,.67),(-.53,1.51,.67)],[(0,3,2,1)],glass_car,root,smooth=False)
    for s in [-1,1]:
        tube('A pillar',[(s*.61,.90,-.72),(s*.55,1.53,-.57)],.037,cream,root)
        tube('C pillar',[(s*.61,.91,.87),(s*.55,1.53,.67)],.045,cream,root)
        tube('B pillar',[(s*.68,.91,.24),(s*.57,1.52,.22)],.03,body,root)
        mesh('Side window',[(s*.65,.95,-.65),(s*.65,.95,.78),(s*.55,1.49,.64),(s*.55,1.49,-.53)],[(0,1,2,3)],glass_car,root,smooth=False)
        box('Door panel',(s*.68,.75,-.05),(.045,.25,1.36),body,root,.035)
        tube('Door seam',[(s*.708,.91,-.59),(s*.708,.47,-.54),(s*.708,.43,.51),(s*.708,.90,.61)],.006,dark,root,4)
        box('Chrome door handle',(s*.72,.86,.40),(.046,.031,.15),chrome,root,.012)
        tube('Mirror arm',[(s*.65,1.0,-.56),(s*.81,1.12,-.55)],.018,chrome,root)
        ell('Mirror',(s*.84,1.14,-.56),(.075,.057,.055),chrome,root,16)
        for z,tag in [(-1.,'F'),(1.,'R')]:
            center=(s*.72,.34,z); code=tag+('L' if s<0 else 'R')
            steer=empty('Steering'+code,root,center) if tag=='F' else root
            wheel=empty('Wheel'+code,steer,(0,0,0) if tag=='F' else center)
            torus('Tire',(0,0,0),.261,.079,tire,wheel,ns=40,nt=12)
            tube('Wheel rim',[(s*.07,0,0),(s*.086,0,0)],.214,chrome,wheel,32)
            tube('Painted wheel disk',[(s*.091,0,0),(s*.098,0,0)],.156,cream,wheel,32)
            ell('Chrome hubcap',(s*.105,0,0),(.035,.095,.095),chrome,wheel,20)
            for j in range(8):
                a=j*math.tau/8; ell('Wheel vents',(s*.102,.18*math.cos(a),.18*math.sin(a)),(.008,.02,.02),dark,wheel,8)
    for x in [-.31,.31]:
        box('Seat cushion',(x,.64,.26),(.49,.13,.47),wood,root,.08)
        box('Seat back',(x,.90,.49),(.49,.47,.14),wood,root,.08)
    box('Dashboard',(0,.99,-.51),(1.13,.15,.22),dark,root,.055)
    torus('Steering wheel',(-.32,1.06,-.35),.125,.018,chrome,root,'z',28)
    for s in [-1,1]:
        box('Chrome bumper',(0,.46,s*1.60),(1.30,.095,.105),chrome,root,.04)
        box('License plaque',(0,.54,s*1.59),(.36,.13,.03),cream,root,.015)
        for x in [-.47,.47]:
            ell('Headlamp bezel' if s<0 else 'Tail bezel',(x,.765,s*1.57),(.135,.12,.05),chrome,root,24)
            ell('Headlight' if s<0 else 'Taillight',(x,.765,s*1.615),(.106,.092,.025),lamp if s<0 else red,root,24)
    for i in range(5): box('Grille slat',(0,.655+i*.027,-1.583),(.64,.013,.022),chrome,root,.005)
    export(root,'island_car')

if __name__=='__main__':
    for f in [1,2]:
        for s in [0,1,2]: town_house(f,s)
    palm(); car()
    os.makedirs(OUT+'/../source',exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(OUT+'/../source/mediterranean_town_revision.blend'),copy=True)
    print('TOWN REVISION SAVED')
