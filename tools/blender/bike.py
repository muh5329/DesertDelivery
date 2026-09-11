exec(open('/Users/mun/Documents/Projects/DesertDelivery/tools/blender/common.py').read())
root=start('CourierBike')
red=material('Vermilion enamel',(.67,.095,.055),.3)
cream=material('Warm ivory',(.92,.83,.66),.38)
chrome=material('Brushed aluminium',(.65,.68,.69),.27,.75)
dark=material('Graphite engine',(.065,.057,.049),.62,.35)
rubber=material('Tread rubber',(.035,.029,.023),.92)
tan=material('Saddle leather',(.57,.34,.17),.78)
stitch=material('Saddle stitching',(.80,.62,.38),.7)
glass=material('Windscreen',(.70,.82,.83,.24),.15)
lamp=material('Headlamp glass',(.98,.92,.75),.2)
amber=material('Amber signal',(.96,.27,.03),.3)
# Coach-built body: a longitudinal loft, raised nose and broad continuous lower fairings.
body=empty('Body',root)
for side in [-1,1]:
    # sculpted side panel, intentionally tapered at the seat and belly
    rings=[(.35,side*.24,.02,.05,.15),(.40,side*.26,-.03,.085,.26),(.52,side*.275,-.10,.10,.38),(.70,side*.27,-.20,.105,.47),(.85,side*.235,-.34,.08,.43),(.96,side*.19,-.48,.045,.31)]
    loft('Swept fairing',rings,red,body)
ell('Nose cowl',(0,.88,-.73),(.29,.255,.40),red,body)
ell('Ivory nose',(0,.88,-1.008),(.263,.227,.12),cream,body)
torus('Headlamp bezel',(0,.88,-1.113),.165,.025,chrome,body,'z')
ell('Headlamp lens',(0,.88,-1.127),(.152,.152,.022),lamp,body)
ell('Tank',(0,1.0,-.15),(.20,.155,.265),red,body)
ell('Fuel cap',(0,1.144,-.20),(.052,.012,.057),chrome,body)
box('Engine',(0,.48,.18),(.34,.26,.34),dark,body,.06)
for i in range(6): box('Cooling fin',(0,.40+i*.03,.20),(.37,.012,.30),chrome,body,.003)
for side in [-1,1]:
    tube('Frame',[(side*.18,.40,.4),(side*.18,.91,.34),(side*.17,.98,-.37),(side*.17,.38,.08),(side*.18,.40,.4)],.022,chrome,body)
    tube('Swingarm',[(side*.18,.37,.16),(side*.18,.32,.70)],.035,dark,body)
    a=Vector((side*.21,.34,.70)); b=Vector((side*.21,.89,.40)); d=(b-a).normalized(); u=Vector((1,0,0)); w=d.cross(u)
    tube('Damper',[a,b],.025,chrome,body)
    pts=[]
    for k in range(151):
        t=k/150; pts.append(a.lerp(b,.12+t*.72)+(u*math.cos(t*math.tau*10)+w*math.sin(t*math.tau*10))*.056)
    tube('Coil spring',pts,.011,cream,body,6)
    tube('Exhaust pipe',[(side*.19,.43,.08),(side*.25,.48,.37),(side*.29,.72,.71),(side*.29,.76,1.12)],.035,chrome,body)
    tube('Silencer',[(side*.29,.76,.75),(side*.29,.76,1.18)],.073,chrome,body,20)
    torus('Exhaust rim',(side*.29,.76,1.18),.054,.013,chrome,body,'z',32)
    ell('Exhaust opening',(side*.29,.76,1.185),(.044,.044,.005),dark,body)
    for i in range(4): tube('Cowl vent',[(side*.272,.98,-.87+i*.10),(side*.294,1.045,-.81+i*.10)],.012,dark,body)
    tube('Indicator',[(side*.29,.85,-.79),(side*.29,.85,-.62)],.026,cream,body)
    ell('Indicator lens',(side*.302,.85,-.69),(.012,.025,.035),amber,body)
    # Raised winged courier emblem on both sides.
    pts=[(side*.378,.60+math.sin(a)*.11,.04+math.cos(a)*.12) for a in [math.radians(45+i*270/28) for i in range(29)]]
    tube('Courier roundel',pts,.021,cream,body)
    for k in range(3):
        tube('Courier wing',[(side*.379,.64-k*.035,.025),(side*.379,.64-k*.035,.22-k*.035)],.017,cream,body)
# Stitched saddle with kick-up back and tubular luggage carrier.
box('Leather saddle',(0,1.015,.41),(.32,.105,.61),tan,body,.048)
ell('Seat back',(0,1.105,.686),(.165,.16,.068),tan,body)
for i in range(7): tube('Seat seam',[(-.138,1.063,.15+i*.072),(0,1.07,.15+i*.072),(.138,1.063,.15+i*.072)],.0028,stitch,body,5)
tube('Seat piping',[(-.162,1.025,.16),(-.17,1.035,.59),(-.14,1.22,.71),(0,1.245,.73),(.14,1.22,.71),(.17,1.035,.59),(.162,1.025,.16)],.013,chrome,body)
tube('Rear carrier',[(-.23,.98,.76),(-.23,.98,1.25),(-.17,.98,1.30),(.17,.98,1.30),(.23,.98,1.25),(.23,.98,.76)],.023,chrome,body)
for z in [.86,1.0,1.16]: tube('Rack slat',[(-.23,.975,z),(.23,.975,z)],.012,chrome,body)
box('Rear fender',(0,.89,1.04),(.36,.08,.48),red,body,.035)
ell('Tail lamp',(0,.83,1.292),(.067,.067,.028),amber,body)
torus('Tail bezel',(0,.83,1.286),.068,.012,chrome,body,'z',32)
for s in [-1,1]: tube('Footpeg',[(s*.20,.38,.21),(s*.42,.38,.21)],.023,rubber,body)
# Curved open windscreen surface with riveted ivory edge.
verts=[]; faces=[]; edge=[]
for i in range(13):
    t=i/12; y=1.035+t*.52; width=.247*math.sqrt(max(.001,1-t*t)); z=-.59+t*.10
    for j in range(13):
        u=-1+2*j/12; verts.append((u*width,y,z-.105*(1-u*u)))
for i in range(12):
    for j in range(12): a=i*13+j; faces.append((a,a+13,a+14,a+1))
mesh('Curved windscreen',verts,faces,glass,body)
for s in [-1,1]:
    pts=[]
    for i in range(25):
        t=i/24; pts.append((s*.247*math.sqrt(max(.001,1-t*t)),1.035+t*.52,-.59+t*.10))
    tube('Ivory windscreen frame',pts,.018,cream,body)
    for i in range(1,24,3): ell('Rivet',pts[i],(.009,.009,.009),chrome,body,12)
tube('Screen lower frame',[verts[j] for j in range(13)],.018,cream,body)
fork=empty('ForkPivot',root,(0,1.05,-.52))
for s in [-1,1]:
    tube('Fork stanchion',[(s*.12,0,0),(s*.12,-.73,-.24)],.026,chrome,fork)
    tube('Fork slider',[(s*.12,-.42,-.14),(s*.12,-.73,-.24)],.042,chrome,fork)
    tube('Handlebar',[(0,.06,.05),(s*.22,.06,.02),(s*.35,.06,.11)],.018,chrome,fork)
    tube('Grip',[(s*.25,.06,.075),(s*.39,.06,.12)],.027,rubber,fork)
    tube('Mirror stem',[(s*.30,.07,.075),(s*.40,.27,.04)],.010,chrome,fork)
    ell('Mirror',(s*.40,.29,.04),(.062,.057,.022),chrome,fork)
def wheel(name,parent,pos):
    w=empty(name,parent,pos)
    torus('Knobby tire',(0,0,0),.251,.069,rubber,w)
    for x in [-.048,.048]: torus('Rim',(x,0,0),.217,.013,chrome,w)
    tube('Axle',[(-.105,0,0),(.105,0,0)],.052,chrome,w,24)
    for side in [-1,1]:
        for i in range(24):
            a=i*math.tau/24; b=a+.24
            tube('Spoke',[(side*.063,.051*math.cos(b),.051*math.sin(b)),(side*.040,.213*math.cos(a),.213*math.sin(a))],.003,chrome,w,5)
    for i in range(36):
        a=i*math.tau/36
        for x in [-.046,0,.046]:
            o=box('Tread',(x,.314*math.cos(a),.314*math.sin(a)),(.044,.016,.038),rubber,w,.004)
            o.rotation_euler=(C @ Matrix.Rotation(a,3,'X') @ C.inverted()).to_euler()
    return w
wheel('RearWheel',root,(0,.32,.70))
wheel('FrontWheel',fork,(0,-.73,-.24))
# A short upper mudguard, leaving the wheel visible in profile.
for x in [-.055,0,.055]:
    tube('Front mudguard',[(x,-.73+.357*math.cos(a),-.24+.357*math.sin(a)) for a in [-1.1+i*1.95/24 for i in range(25)]],.045,red,fork)
export(root,'courier_bike')
