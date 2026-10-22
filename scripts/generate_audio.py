#!/usr/bin/env python3
"""Generate original, deterministic PCM game effects offline; no runtime synthesis."""
from pathlib import Path
import math, random, struct, wave
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'web/assets/audio'
RATE=22050
TAU=2*math.pi

def smoothstep(a): return a*a*(3-2*a)
def generate(name,duration):
 rng=random.Random('OPEN BREACH/'+name)
 count=round(duration*RATE); samples=[]; low=0.
 for n in range(count):
  t=n/RATE; p=n/max(1,count-1); noise=rng.uniform(-1,1)
  low=.7*low+.3*noise
  fade=min(1,t/.004)*min(1,(duration-t)/.025)
  if name=='select':
   value=.20*math.sin(TAU*880*t)*math.exp(-40*t)
  elif name=='order':
   local=t%0.10; freq=640 if t<.10 else 960
   value=.18*math.sin(TAU*freq*t)*math.exp(-25*local)*min(1,local/.003)
  elif name=='door':
   value=.3*low*math.exp(-7*t)+.20*math.sin(TAU*(92*t-30*t*t))*math.exp(-12*t)
   if .25<t<.31: value+=.13*noise*math.exp(-40*(t-.25))
  elif name=='shot':
   value=.40*noise*math.exp(-42*t)+.24*math.sin(TAU*(90*t-120*t*t))*math.exp(-26*t)+.13*low*math.exp(-12*t)
  elif name=='hit':
   value=.25*low*math.exp(-28*t)+.2*math.sin(TAU*145*t)*math.exp(-36*t)
  elif name=='stun':
   value=(.22*low+.12*math.sin(TAU*(140*t+25*t*t)))*math.exp(-5*t)
  elif name in ('win','fail'):
   notes=[440,554.37,659.25] if name=='win' else [392,329.63,261.63]
   value=0
   for idx,freq in enumerate(notes):
    local=t-idx*.14
    if local>=0: value+=.12*math.sin(TAU*freq*local)*math.exp(-3.8*local)*min(1,local/.015)
  else:
   # Integer frequency/8 keeps the loop mathematically periodic.
   value=.065*math.sin(TAU*55*t)+.025*math.sin(TAU*82.5*t)+.018*math.sin(TAU*110*t)
   value*=.75+.25*math.cos(TAU*t/duration)
   fade=1
  samples.append(max(-.8,min(.8,value*fade)))
 OUT.mkdir(parents=True,exist_ok=True)
 with wave.open(str(OUT/(name+'.wav')),'wb') as f:
  f.setnchannels(1); f.setsampwidth(2); f.setframerate(RATE)
  f.writeframes(b''.join(struct.pack('<h',round(v*32767)) for v in samples))
 print(name, f'{duration:.2f}s', len(samples)*2+44,'bytes')

for name,duration in [('select',.10),('order',.22),('stun',.70),('win',1.10),('fail',1.10),('ambient',8)]:
 generate(name,duration)
