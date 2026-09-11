exec(open('/Users/mun/Documents/Projects/DesertDelivery/tools/blender/common.py').read())
random.seed(742)
plaster=material('Limewashed plaster',(.77,.66,.48),.93)
stone=material('Cut limestone',(.64,.57,.44),.95)
roof=material('Fired clay tiles',(.42,.16,.075),.84)
roof_hi=material('Sunlit clay',(.53,.23,.11),.84)
wood=material('Chestnut wood',(.18,.091,.039),.87)
shutter=material('Sage shutters',(.19,.29,.18),.82)
window=material('Blue window glass',(.11,.21,.24),.25,.1)
iron=material('Wrought iron',(.055,.065,.057),.62,.5)
ivory=material('Canvas ivory',(.9,.81,.61),.9)
leaf=material('Olive foliage',(.22,.34,.095),.96)
leaf_hi=material('Sunlit foliage',(.35,.46,.14),.95)
leaf_dark=material('Foliage shade',(.095,.22,.058),.96)
flower=material('Bougainvillea petals',(.70,.15,.28),.89)
def house(floors):
    root=start('VillageHouse'+str(floors)); h=floors*3.1
    box('Plaster walls',(0,(h-3)/2,0),(6,h+3,6),plaster,root,.08)
    box('Foundation course',(0,.23,0),(6.12,.45,6.12),stone,root,.03)
    for y in [h,.55]+([3.1] if floors>1 else []): box('Stone string course',(0,y,0),(6.2,.13,6.2),stone,root,.025)
    for s in [-1,1]:
        for z in [-2.99,2.99]:
            for i in range(int(h/.40)):
                box('Corner quoin',(s*2.98,.2+i*.40,z),(.38 if i%2 else .52,.36,.28),stone,root,.015)
    # Gable roof; individual barrel tiles follow both slopes.
    mesh('Roof bed',[(-3.35,h,-3.35),(3.35,h,-3.35),(0,h+1.75,-3.35),(-3.35,h,3.35),(3.35,h,3.35),(0,h+1.75,3.35)],[(0,2,1),(3,4,5),(0,3,5,2),(2,5,4,1),(0,1,4,3)],roof,root,smooth=False)
    for s in [-1,1]:
        for ix in range(10):
            x=s*(.17+ix*.335); y=h+1.75-abs(x)*1.75/3.35+.045
            for iz in range(16):
                z=-3.24+iz*.425
                tube('Barrel roof tile',[(x,y,z),(x-s*.025,y+.035,z+.43)],.092,roof_hi if random.random()<.3 else roof,root,8)
        tube('Eave beam',[(s*3.32,h,-3.38),(s*3.32,h,3.38)],.09,wood,root)
    tube('Ridge tiles',[(0,h+1.79,-3.43),(0,h+1.79,3.43)],.16,roof_hi,root,12)
    box('Chimney',(1.85,h+1.55,1.4),(.56,1.8,.60),plaster,root,.03)
    box('Chimney cap',(1.85,h+2.47,1.4),(.76,.14,.80),stone,root,.03)
    for f in range(floors):
        y=1.75+f*3.1
        for x in [-1.72,1.72]:
            for s in [-1,1]:
                z=s*3.035
                box('Window recess',(x,y,z),(1.13,1.46,.07),wood,root,.02)
                box('Glazing',(x,y,z+s*.045),(.97,1.27,.045),window,root,.009)
                for dx in [-.53,0,.53]: box('Window mullion',(x+dx,y,z+s*.08),(.047,1.44,.04),ivory,root,.006)
                for dy in [-.7,0,.7]: box('Window crossbar',(x,y+dy,z+s*.08),(1.10,.05,.04),ivory,root,.006)
                box('Window sill',(x,y-.76,z+s*.12),(1.28,.12,.32),stone,root,.02)
                for dx in [-.83,.83]:
                    box('Shutter leaf',(x+dx,y,z),(.47,1.48,.10),shutter,root,.015)
                    for k in range(10): box('Louver slat',(x+dx,y-.61+k*.135,z+s*.063),(.42,.06,.04),shutter,root,.005)
    box('Door frame',(0,1.12,-3.055),(1.45,2.3,.10),stone,root,.03)
    box('Timber door',(0,1.06,-3.12),(1.15,2.12,.09),wood,root,.025)
    for x in [-.42,-.21,0,.21,.42]: box('Door plank',(x,1.06,-3.174),(.015,2.04,.012),stone,root,.002)
    ell('Door handle',(.38,1.04,-3.22),(.035,.035,.03),iron,root)
    for y in [.055,.16]: box('Doorstep',(0,y,-3.39),(1.6,.11,.62),stone,root,.03)
    # Small striped fabric awning and iron shop brackets.
    for i in range(12):
        x=-1.8+i*.30
        mesh('Striped canvas',[(x,2.55,-3.08),(x+.30,2.55,-3.08),(x+.30,2.30,-4.0),(x,2.30,-4.0)],[(0,1,2,3)],ivory if i%2 else shutter,root)
        box('Scalloped valance',(x+.15,2.23,-3.98),(.298,.18,.035),ivory if i%2 else shutter,root,.04)
    for x in [-1.8,1.8]: tube('Awning bracket',[(x,2.53,-3.05),(x,2.29,-4),(x,1.9,-3.05)],.025,iron,root)
    if floors>1:
        box('Balcony slab',(0,3.25,-3.5),(4.95,.18,1.15),stone,root,.035)
        for x in [i*.27-2.43 for i in range(19)]: tube('Balcony baluster',[(x,3.30,-4.0),(x,4.12,-4.0)],.015,iron,root,6)
        tube('Balcony rail',[(-2.48,4.14,-3),(-2.48,4.14,-4.02),(2.48,4.14,-4.02),(2.48,4.14,-3)],.033,iron,root)
    export(root,'village_house_'+str(floors))
house(1); house(2)
# A branching broadleaf olive tree; clustered individual leaves survive close views.
root=start('OliveTree')
tube('Twisted trunk',[(0,0,0),(.12,1.15,.04),(-.11,2.25,0),(.12,3.1,.11)],.25,wood,root,10,[1.3,1,.7,.3])
for i in range(9):
    a=i*2.4; r=1.25+(i%3)*.35; p=Vector((math.cos(a)*r,3.0+(i%3)*.55,math.sin(a)*r))
    tube('Olive branch',[(-.08,1.65,0),p*.65+Vector((0,.6,0)),p],.12,wood,root,8,[1,.6,.15])
    for j in range(65):
        q=p+Vector((random.uniform(-.95,.95),random.uniform(-.32,.65),random.uniform(-.9,.9)))
        a=random.random()*math.tau; sz=random.uniform(.12,.26)
        # Folded leaf diamond (four triangles), softer silhouette than blob crowns.
        dx=math.cos(a)*sz; dz=math.sin(a)*sz
        verts=[q+Vector((-dx,0,-dz)),q+Vector((dz*.42,0,-dx*.42)),q+Vector((dx,0,dz)),q+Vector((-dz*.42,0,dx*.42)),q+Vector((0,.06,0))]
        mesh('Olive leaves',verts,[(0,1,4),(1,2,4),(2,3,4),(3,0,4)],random.choice([leaf,leaf_hi,leaf_dark]),root)
export(root,'olive_tree')
# Tall jointed limestone mass, normalized around the origin for existing rock placements.
root=start('LimestoneCliff'); random.seed(80)
verts=[]; faces=[]; n=18; levels=12
rad=[random.uniform(.72,1.08) for _ in range(n)]
for k in range(levels):
    y=-.65+k*.15
    for i in range(n):
        a=math.tau*i/n; r=rad[i]*(1+random.uniform(-.055,.055))*(1-.10*k/levels)
        verts.append((math.cos(a)*r,y+random.uniform(-.045,.045),math.sin(a)*r*.8))
for k in range(levels-1):
    for i in range(n): a=k*n+i; b=k*n+(i+1)%n; faces.append((a,a+n,b+n,b))
faces.extend([tuple(range(n-1,-1,-1)),tuple((levels-1)*n+i for i in range(n))])
o=mesh('Stratified limestone',verts,faces,stone,root,smooth=False)
mod=o.modifiers.new('Weathered edges','BEVEL'); mod.width=.028; mod.segments=2
bpy.context.view_layer.objects.active=o; o.select_set(True); bpy.ops.object.modifier_apply(modifier=mod.name)
export(root,'limestone_cliff')
# Rounded village runabout, a proper open-window cab with visible driver space.
root=start('IslandCar')
body=material('Car seafoam',(.20,.43,.35),.35); rubber=material('Traffic tire',(.026,.029,.023),.9); chrome=material('Car trim',(.63,.64,.56),.35,.65)
box('Lower body',(0,.61,0),(1.40,.55,2.8),body,root,.19)
box('Bonnet',(0,.91,-.95),(1.33,.25,.80),body,root,.10)
box('Cab roof',(0,1.76,.10),(1.30,.14,1.55),body,root,.10)
for x in [-.61,.61]:
    for z in [-.60,.78]: tube('Window pillar',[(x,.93,z),(x,1.72,z*.85)],.047,body,root)
    box('Door',(x,1.01,.09),(.09,.30,1.47),body,root,.025)
    box('Door handle',(x*1.08,1.10,.50),(.055,.025,.15),chrome,root,.01)
    ell('Side mirror',(x*1.22,1.35,-.54),(.075,.047,.05),chrome,root)
    for z in [-.90,.91]: torus('Car tire',(x*1.12,.35,z),.265,.08,rubber,root); tube('Hubcap',[(x*1.23,.35,z),(x*1.27,.35,z)],.19,chrome,root,24)
box('Bench seat',(0,.91,.36),(1.04,.18,.54),wood,root,.08)
box('Seat back',(0,1.18,.64),(1.04,.52,.14),wood,root,.08)
torus('Steering wheel',(-.32,1.23,-.39),.13,.014,iron,root,'z',24)
for s in [-1,1]:
    box('Bumper',(0,.55,s*1.44),(1.45,.10,.11),chrome,root,.035)
    for x in [-.45,.45]: ell('Car lamp',(x,.85,s*1.39),(.13,.12,.045),ivory if s<0 else roof_hi,root)
export(root,'island_car')
# Fishing launch and triangular sail, origin at the waterline.
root=start('FishingBoat')
blue=material('Boat blue',(.055,.20,.27),.6)
verts=[(-.78,.38,1.6),(.78,.38,1.6),(.89,.38,-.8),(0,.52,-2.3),(-.89,.38,-.8),(-.48,-.30,1.3),(.48,-.30,1.3),(.50,-.30,-.6),(0,-.15,-1.8),(-.50,-.30,-.6)]
mesh('Launch hull',verts,[(0,1,6,5),(1,2,7,6),(2,3,8,7),(3,4,9,8),(4,0,5,9),(5,6,7,8,9)],blue,root,smooth=False)
mesh('Wood deck',verts[:5],[(0,4,3,2,1)],wood,root,smooth=False)
tube('Gunwale',verts[:5]+[verts[0]],.055,ivory,root)
tube('Mast',[(0,.35,-.30),(0,4.1,-.30)],.045,wood,root)
tube('Boom',[(0,1.0,-.30),(0,1.0,1.8)],.032,wood,root)
mesh('Cream sail',[(0,3.95,-.28),(0,1.1,-.28),(.16,1.1,1.72),(.20,2.1,.55)],[(0,1,3),(1,2,3),(2,0,3)],ivory,root)
box('Stern bench',(0,.61,1.04),(1.25,.13,.34),wood,root,.025)
export(root,'fishing_boat')
# Articulated farm and wild animals share a lightweight limb layout.
for kind in ['sheep','deer','dog','rabbit','gull']:
    root=start(kind.title()); wool=material(kind+' coat', {'sheep':(.80,.75,.57),'deer':(.42,.24,.10),'dog':(.47,.29,.14),'rabbit':(.50,.43,.32),'gull':(.87,.87,.78)}[kind],.9)
    hoof=material('Animal eyes and hooves',(.03,.025,.02),.6)
    if kind=='gull':
        ell('Body',(0,0,0),(.12,.11,.30),wool,root,16)
        ell('Head',(0,.10,-.24),(.09,.09,.10),wool,root,16)
        tube('Beak',[(0,.1,-.3),(0,.08,-.43)],.035,roof_hi,root,6,[1,.05])
        for s in [-1,1]:
            wing=empty('WingL' if s<0 else 'WingR',root)
            mesh('Wing',[(0,.05,0),(s*.42,.06,-.15),(s*.83,-.02,.05),(s*.44,.01,.19),(0,0,.12)],[(0,1,4),(1,3,4),(1,2,3)],wool,wing)
    else:
        scale={'sheep':1,'deer':1.25,'dog':.7,'rabbit':.4}[kind]
        ell('Body',(0,.69*scale,0),(.30*scale,.30*scale,.52*scale),wool,root,20)
        h=empty('AnimalHead',root,(0,.91*scale,-.44*scale))
        ell('Head',(0,0,-.08*scale),(.16*scale,.20*scale,.22*scale),wool,h,20)
        ell('Muzzle',(0,-.07*scale,-.27*scale),(.12*scale,.08*scale,.12*scale),hoof if kind=='sheep' else wool,h,16)
        for s in [-1,1]:
            ell('Eye',(s*.146*scale,.015,-.17*scale),(.018*scale,.022*scale,.02*scale),hoof,h,12)
            ell('Ear',(s*.18*scale,.14*scale,0),(.075*scale,(.28 if kind=='rabbit' else .11)*scale,.045*scale),wool,h,16)
            for z in [-.32,.34]:
                leg=empty('AnimalLeg',root,(s*.20*scale,.55*scale,z*scale))
                tube('Leg',[(0,0,0),(0,-.47*scale,0)],.048*scale,wool,leg)
                ell('Hoof',(0,-.50*scale,-.016*scale),(.064*scale,.05*scale,.082*scale),hoof,leg,12)
        tube('Tail',[(0,.75*scale,.43*scale),(0,.82*scale,.72*scale),(0,.96*scale,.79*scale)],.045*scale,wool,root,8,[1,.6,.05])
        if kind=='deer':
            for s in [-1,1]:
                tube('Antler',[(s*.09,.15,0),(s*.19,.48,0),(s*.26,.65,.09)],.023,wood,h,6,[1,.7,.1])
                tube('Antler tine',[(s*.18,.41,0),(s*.10,.58,-.06)],.016,wood,h,6,[1,.1])
    export(root,kind)
print('Island art kit complete')
