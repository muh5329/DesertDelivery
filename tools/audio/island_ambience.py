"""Original procedural field ambience: filtered breeze, distant surf and bird phrases.
No recordings or third-party audio. Run with Python 3 to rebuild the looping WAVs.
"""
from pathlib import Path
import math, random, struct, wave
ROOT=Path(__file__).resolve().parents[2]/'assets/audio'
RATE=22050

def write(name,seconds,kind):
    rng=random.Random(713+kind)
    frames=bytearray(); low=[0.,0.]; slow=[0.,0.]
    phrases=[(3.1,.23,2400,320), (3.5,.19,2850,-500), (11.6,.31,2100,900),
             (12.1,.18,2900,-400), (22.2,.26,2450,620), (22.6,.23,2950,-550)]
    for i in range(RATE*seconds):
        t=i/RATE
        fade=min(1,t/.15,(seconds-t)/.15)
        pair=[]
        for channel in range(2):
            n=rng.uniform(-1,1)
            low[channel]+=(n-low[channel])*(.055 if kind==0 else .15)
            slow[channel]+=(low[channel]-slow[channel])*.001
            if kind==0:
                value=(low[channel]-slow[channel])*(.45+.12*math.sin(t*math.tau/seconds+channel*.5))
            elif kind==1:
                swell=(.5+.5*math.sin(t*math.tau/8+channel*.16))**2
                value=(low[channel]-slow[channel])*(.10+swell*.52)
            else:
                value=0
                for start,dur,freq,sweep in phrases:
                    u=(t-start)/dur
                    if 0<u<1:
                        env=math.sin(math.pi*u)**2
                        phase=math.tau*(freq*(t-start)+sweep*(t-start)**2/(2*dur))
                        value+=math.sin(phase+math.sin(u*28)*.4)*env*.13*(1 if channel==0 else .65)
            pair.append(max(-.95,min(.95,value*fade)))
        frames.extend(struct.pack('<hh',int(pair[0]*32767),int(pair[1]*32767)))
    with wave.open(str(ROOT/name),'wb') as out:
        out.setparams((2,2,RATE,0,'NONE','not compressed')); out.writeframes(frames)

ROOT.mkdir(parents=True,exist_ok=True)
write('breeze.wav',24,0)
write('shore.wav',24,1)
write('garden_birds.wav',31,2)
print('Wrote original stereo ambience loops to',ROOT)
