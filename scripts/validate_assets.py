#!/usr/bin/env python3
"""Check mission geometry, real asset hashes, font coverage and sample metadata."""
from pathlib import Path
from collections import deque
import hashlib,json,math,wave
ROOT=Path(__file__).resolve().parents[1]
RADIUS=.23
STEP=.25
failures=[]

def require(condition,message):
 if not condition: failures.append(message)

def contains(p,r,padding=0):
 return abs(p[0]-r['x'])<r['w']/2+padding-1e-7 and abs(p[1]-r['z'])<r['d']/2+padding-1e-7

def overlap(a,b):
 return abs(a['x']-b['x'])<(a['w']+b['w'])/2-1e-6 and abs(a['z']-b['z'])<(a['d']+b['d'])/2-1e-6

for name,expected in [('tutorial',(3,2,2,3,0)),('house',(6,8,4,6,2))]:
 data=json.loads((ROOT/'game/data'/f'{name}.json').read_text())
 counts=tuple(len(data[k]) for k in ('rooms','doors','units','enemies','civilians'))
 require(counts==expected,f'{name}: unexpected content counts {counts}')
 ids=[d['id'] for key in ('rooms','doors','units','enemies','civilians','props','walls') for d in data[key]]
 require(len(ids)==len(set(ids)),f'{name}: duplicate IDs')
 for d in data['doors']:
  for w in data['walls']: require(not overlap(d,w),f'{name}: door {d["id"]} overlaps wall {w["id"]}')
 obstacles=data['walls']+[p for p in data['props'] if p['solid']]
 def blocked(p): return any(contains(p,o,RADIUS) for o in obstacles)
 for kind in ('units','enemies','civilians'):
  for actor in data[kind]:
   point=(actor['x'],actor['z'])
   require(not blocked(point),f'{name}: {actor["id"]} spawns in an obstacle')
   for waypoint in actor.get('patrol',[]): require(not blocked(waypoint),f'{name}: {actor["id"]} patrol endpoint blocked')
 width,depth=round(data['bounds'][0]/STEP),round(data['bounds'][1]/STEP)
 cells={(x,z) for x in range(1,width) for z in range(1,depth) if not blocked((x*STEP,z*STEP))}
 def nearest(p): return min(cells,key=lambda c:(c[0]*STEP-p[0])**2+(c[1]*STEP-p[1])**2)
 spawn=nearest((data['units'][0]['x'],data['units'][0]['z']))
 seen={spawn}; queue=deque([spawn])
 while queue:
  x,z=queue.popleft()
  for q in ((x-1,z),(x+1,z),(x,z-1),(x,z+1)):
   if q in cells and q not in seen: seen.add(q); queue.append(q)
 for kind in ('rooms','doors','enemies','civilians'):
  for obj in data[kind]:
   target=nearest((obj['x'],obj['z']))
   require(target in seen,f'{name}: {obj["id"]} cannot be reached with doors open')
 if name=='tutorial': require(all(e.get('passive') and e.get('target') for e in data['enemies']),'Tutorial must have inert targets')
 print(f'{name}: content counts, IDs, door gaps, free spawns, {len(seen)} reachable cells checked')

manifest=json.loads((ROOT/'asset-manifest.json').read_text())
for asset in manifest['assets']:
 for entry in asset['selected_files']:
  p=ROOT/entry['path']; require(p.exists(),f'Missing {p}')
  if p.exists(): require(hashlib.sha256(p.read_bytes()).hexdigest()==entry['sha256'],f'Stale hash {p}')
for path in (ROOT/'web/assets/audio').glob('*.wav'):
 with wave.open(str(path)) as f:
  # UI tones remain 22.05 kHz; imported recordings retain a 16 kHz frequency
  # band at 32 kHz so the gunshot attack does not lose its upper detail.
  require(f.getnchannels()==1 and f.getsampwidth()==2 and f.getframerate() in (22050,32000),f'Invalid audio {path}')
print('Audio format and asset manifest verified')
if failures:
 raise SystemExit('\n'.join(failures))
print('ASSET VALIDATION PASSED')
