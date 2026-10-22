#!/usr/bin/env python3
"""Two original fictional game boards using the existing licensed furniture kit."""
import json
from pathlib import Path
from mission_authoring import upgrade, preserve_enemy_strengths
ROOT=Path(__file__).resolve().parents[1]
def wall(axis,fixed,start,end,gaps=()):
    out=[];cursor=start
    for center,width in sorted(gaps):
        lo,hi=center-width/2,center+width/2
        if lo>cursor:out.append(dict(x=(cursor+lo)/2 if axis=='x' else fixed,z=fixed if axis=='x' else (cursor+lo)/2,w=lo-cursor if axis=='x' else .24,d=.24 if axis=='x' else lo-cursor))
        cursor=hi
    if cursor<end:out.append(dict(x=(cursor+end)/2 if axis=='x' else fixed,z=fixed if axis=='x' else (cursor+end)/2,w=end-cursor if axis=='x' else .24,d=.24 if axis=='x' else end-cursor))
    return out
def room(i,label,x,z,w,d,color):return dict(id=i,label=label,x=x,z=z,w=w,d=d,color=color)
def prop(kind,x,z,w,d):return dict(type=kind,x=x,z=z,w=w,d=d,solid=kind not in ['rug','plant','chair'])
def door(i,x,z,axis):return dict(id=i,x=x,z=z,w=1.8 if axis=='x' else .24,d=.24 if axis=='x' else 1.8,axis=axis)
def unit(i,x,z):return dict(id=i,name=i.upper(),role='대원',x=x,z=z,facing=-1.5707963268,weapon='standard')
def enemy(i,x,z):return dict(id=i,x=x,z=z,facing=1.5707963268,weapon='light')
def board(i,title,seed):return dict(schema_version=1,id=i,revision=1,title=title,seed=seed,bounds=[24,20],focus=[12,10],rooms=[],walls=[],doors=[],props=[],units=[],enemies=[],civilians=[],objectives=['모든 위협을 처리하세요.','민간인을 확보하세요.'])
a=board('M02','닫힌 기록실',2093)
a['rooms']=[room('lobby','01 / RECEPTION',12,13,18,6,'#687a77'),room('archive','02 / ARCHIVE',7.5,6.5,9,7,'#777666'),room('office','03 / OFFICE',16.5,6.5,9,7,'#66777b')]
a['walls']=wall('x',3,3,21)+wall('x',16,3,21,[(6,2.4)])+wall('z',3,3,16)+wall('z',21,3,16)+wall('x',10,3,21,[(7.5,1.8),(17,1.8)])+wall('z',12,3,10,[(6,1.8)])
a['doors']=[door('a1',7.5,10,'x'),door('a2',17,10,'x'),door('a3',12,6,'z')]
a['props']=[prop('desk',12,13.5,3,1),prop('sofa',19.5,13,1,3),prop('plant',4,11,.7,.7),prop('rug',7,13,3.5,3),prop('bookshelf',5,5,.7,2),prop('bookshelf',8,5,.7,2),prop('bookshelf',10.8,8,.7,2),prop('desk',17,4.3,3,1),prop('chair',17,5.2,.6,.6),prop('cabinet',20,7,.6,2),prop('rug',16.5,7.5,4,3)]
a['units']=[unit('alpha',5.5,17.4),unit('bravo',6.7,18.1)]
a['enemies']=[enemy('a_e1',9,12),enemy('a_e2',6.5,7),enemy('a_e3',17,7.5)]
a['civilians']=[dict(id='a_c1',x=19,z=4.5,name='기록실 직원')]
b=board('M03','화물 보관소',3119)
b['rooms']=[room('loading','01 / LOADING',12,14,18,6,'#6d7268'),room('storage','02 / STORAGE',8.5,6.5,11,9,'#7b7865'),room('dispatch','03 / DISPATCH',17.5,6.5,7,9,'#68777a')]
b['walls']=wall('x',2,3,21)+wall('x',17,3,21,[(12,2.4)])+wall('z',3,2,17)+wall('z',21,2,17)+wall('z',14,2,11,[(6,1.8)])+wall('x',11,14,21,[(17.5,1.8)])
b['doors']=[door('b1',14,6,'z'),door('b2',17.5,11,'x')]
b['props']=[prop('crate',6,6,2,2),prop('crate',10.5,6,2,2),prop('crate',6,10,2,2),prop('crate',10.5,10,2,2),prop('crate',18,14,2.5,1.5),prop('cabinet',4,14,.6,2),prop('desk',17.5,3.3,3.5,1),prop('chair',17.5,4.3,.6,.6),prop('cabinet',20.2,7.7,.6,2.5),prop('rug',17,7.5,3,4)]
b['units']=[unit('alpha',11,18.1),unit('bravo',12.3,18.1),unit('charlie',13.4,18.8)]
b['units'][2]['weapon']='light'
b['enemies']=[enemy('b_e1',8.2,12.5),enemy('b_e2',4.3,7.5),enemy('b_e3',11.5,3.5),enemy('b_e4',17,8)]
b['civilians']=[dict(id='b_c1',x=19.5,z=3.5,name='보관소 직원')]
for name,data in [('archive',a),('depot',b)]:
    for kind in ['walls','props']:
        for i,item in enumerate(data[kind]):item['id']=f'{name}_{kind}_{i}'
    upgrade(data)
    preserve_enemy_strengths(data, (ROOT/'game/data'/f'{name}.json'))
    (ROOT/'game/data'/f'{name}.json').write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
    print(name, len(data['rooms']),len(data['enemies']))
