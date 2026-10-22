#!/usr/bin/env python3
"""Author the two original OPEN BREACH maps from shared center-based geometry."""
import json
from pathlib import Path
from mission_authoring import upgrade, preserve_enemy_strengths
ROOT = Path(__file__).resolve().parents[1]
THICK = .24

def line_walls(axis, fixed, start, end, openings):
    pieces=[]; cursor=start
    for center,width in sorted(openings):
        lo,hi=center-width/2,center+width/2
        if lo>cursor:
            pieces.append({'x':(cursor+lo)/2 if axis=='x' else fixed,'z':fixed if axis=='x' else (cursor+lo)/2,'w':lo-cursor if axis=='x' else THICK,'d':THICK if axis=='x' else lo-cursor})
        cursor=hi
    if cursor<end:
        pieces.append({'x':(cursor+end)/2 if axis=='x' else fixed,'z':fixed if axis=='x' else (cursor+end)/2,'w':end-cursor if axis=='x' else THICK,'d':THICK if axis=='x' else end-cursor})
    return pieces

def prop(kind,x,z,w,d,rotation=0,solid=None):
    return {'type':kind,'x':x,'z':z,'w':w,'d':d,'rotation':rotation,'solid':kind in ('cabinet','bed','sofa','table','crate','desk','bookshelf','bath') if solid is None else solid}

def door(id,x,z,axis,label):
    return {'id':id,'x':x,'z':z,'w':1.8 if axis=='x' else THICK,'d':THICK if axis=='x' else 1.8,'axis':axis,'label':label}

def unit(id,name,role,x,z):
    return {'id':id,'name':name,'role':role,'x':x,'z':z,'facing':-1.5707963268,'weapon':'standard'}

def enemy(id,x,z,facing,**extra):
    return dict(id=id,x=x,z=z,facing=facing,**extra)

tutorial={
 'schema_version':1,'id':'T01','revision':1,'title':'첫 번째 진입','subtitle':'ORIENTATION',
 'description':'멈춘 시간 속에서 경로를 그리고, 두 대원에게 진입을 지시하세요. 반격하지 않는 표적 3개를 모두 무력화하면 조작 퍼즐이 끝납니다.',
 'seed':42,'bounds':[24,20],'focus':[12,10],
 'rooms':[
  {'id':'t_ready','label':'01 / MOVEMENT','x':6,'z':10,'w':6,'d':12,'color':'#5f655e'},
  {'id':'t_breach','label':'02 / BREACH','x':12,'z':10,'w':6,'d':12,'color':'#766d5b'},
  {'id':'t_signal','label':'03 / COORDINATE','x':18,'z':10,'w':6,'d':12,'color':'#626b65'}],
 'walls':line_walls('x',4,3,21,[])+line_walls('x',16,3,21,[(6,2.2)])+line_walls('z',3,4,16,[])+line_walls('z',21,4,16,[])+line_walls('z',9,4,16,[(10,1.8)])+line_walls('z',15,4,16,[(10,1.8)]),
 'doors':[door('d1',9,10,'z','표적실 진입'),door('d2',15,10,'z','협동 표적실')],
 'props':[
  prop('crate',4.3,5.1,1.3,1.2),prop('crate',4.3,6.55,1.3,1.2),prop('cabinet',7.8,4.75,1.7,.6),
  prop('rug',6,12,3.7,4.4,solid=False),prop('plant',3.8,14.9,.65,.65),prop('cabinet',7.8,15.4,1.7,.6),
  prop('table',12,5.7,2.7,1.1),prop('chair',10.7,5.7,.6,.6,solid=False),prop('chair',13.3,5.7,.6,.6,solid=False),
  prop('crate',10.1,14.8,1.1,1.1),prop('crate',11.4,14.8,1.1,1.1),prop('cabinet',14.3,13.5,.65,2.6),
  prop('rug',12,11.2,3.8,3.7,solid=False),prop('plant',14.1,4.9,.7,.7),
  prop('sofa',18.1,14.7,3.1,.95),prop('rug',18,12.1,3.8,3.5,solid=False),prop('table',18.1,13,1.7,.8),
  prop('cabinet',20.25,5.9,.65,2.9),prop('plant',16.1,5.1,.7,.7),prop('crate',16.1,14.8,1.1,1.1)],
 'units':[unit('alpha','ALPHA','선봉',5.7,17.65),unit('bravo','BRAVO','지원',6.9,18.35)],
 'enemies':[enemy('target1',6.4,7.5,1.57,target=True,passive=True,name='표적 01'),enemy('target2',12,8,1.57,target=True,passive=True,name='표적 02'),enemy('target3',18.4,7.7,1.57,target=True,passive=True,name='표적 03')],
 'civilians':[],
 'objectives':['대원 선택 후 이동 도구 또는 바닥 우클릭으로 경로를 계획하세요.','문 열기 명령을 이용해 두 개의 방에 진입하세요.','표적 3개를 모두 무력화하세요.'],
 'briefing':{'difficulty':'조작 퍼즐','estimated_minutes':'3–5','threat':'반격하지 않는 표적','tip':'Space로 실행과 정지를 전환합니다. 먼저 문을 연 뒤 다음 방의 이동을 추가하세요.'}}

house={
 'schema_version':1,'id':'M01','revision':1,'title':'고요한 주택','subtitle':'OPERATION STILL HOUSE',
 'description':'주택 내부의 위협을 제거하고 민간인 두 명을 안전하게 확보하세요. 정문에서 시작해 방마다 시야를 확보하고, 필요할 때 시간을 멈춰 계획을 수정하세요.',
 'seed':1049,'bounds':[24,20],'focus':[12,10],
 'rooms':[
  {'id':'h_master','label':'04 / BEDROOM','x':6,'z':6.5,'w':6,'d':7,'color':'#796c59'},
  {'id':'h_study','label':'05 / STUDY','x':12,'z':6.5,'w':6,'d':7,'color':'#6c6e5e'},
  {'id':'h_guest','label':'06 / GUEST ROOM','x':18,'z':6.5,'w':6,'d':7,'color':'#766c61'},
  {'id':'h_living','label':'02 / LIVING','x':6,'z':13.5,'w':6,'d':7,'color':'#847968'},
  {'id':'h_entry','label':'01 / ENTRY','x':12,'z':13.5,'w':6,'d':7,'color':'#656c64'},
  {'id':'h_kitchen','label':'03 / KITCHEN','x':18,'z':13.5,'w':6,'d':7,'color':'#778079'}],
 'walls':line_walls('x',3,3,21,[])+line_walls('x',17,3,21,[(12,1.8)])+line_walls('z',3,3,17,[])+line_walls('z',21,3,17,[])+line_walls('z',9,3,17,[(6.5,1.8),(13.6,1.8)])+line_walls('z',15,3,17,[(6.5,1.8),(13.6,1.8)])+line_walls('x',10,3,21,[(6,1.8),(12,1.8)]),
 'doors':[door('d1',12,17,'x','정문'),door('d2',9,13.6,'z','거실'),door('d3',15,13.6,'z','주방'),door('d4',12,10,'x','서재'),door('d5',9,6.5,'z','침실'),door('d6',15,6.5,'z','손님방'),door('d7',6,10,'x','침실 보조문')],
 'props':[
  prop('bed',5,5,2.3,3.1),prop('cabinet',3.65,8.2,.65,2.4),prop('table',7.1,3.9,.65,.65),prop('plant',8.15,8.8,.65,.65),prop('rug',6.9,7.2,2.7,3.2,solid=False),
  prop('desk',12,3.9,3.3,1.05),prop('chair',12.1,5.05,.65,.65,solid=False),prop('bookshelf',14.45,8.5,.6,2.1),prop('cabinet',9.65,4.35,.65,2.1),prop('rug',12.1,7.2,3.5,3.7,solid=False),prop('plant',10,8.9,.65,.65),
  prop('bed',17.2,4.9,2.1,2.7),prop('table',19.2,3.9,.7,.7),prop('cabinet',20.4,8.1,.65,2.8),prop('rug',17.6,7.3,3.2,3.7,solid=False),prop('plant',16,8.95,.65,.65),
  prop('sofa',4.2,13.5,1,3.1),prop('table',6.2,14.1,1.8,1.1),prop('rug',6.05,13.7,3.9,4.1,solid=False),prop('cabinet',7.05,16.45,2.8,.65),prop('plant',3.8,16.1,.65,.65),prop('chair',7.7,11.4,.8,.8,solid=False),
  prop('rug',12,14.15,2.5,4.6,solid=False),prop('cabinet',9.65,15.65,.65,1.65),prop('cabinet',14.4,11.4,.65,1.55),prop('plant',13.9,16.2,.65,.65),prop('table',10.3,11.4,1.15,.6),
  prop('cabinet',18.4,10.65,4.4,.65),prop('cabinet',20.35,12.05,.65,2.1),prop('table',18.1,14.65,2.3,1.15),prop('chair',16.65,14.65,.65,.65,solid=False),prop('chair',19.55,14.65,.65,.65,solid=False),prop('rug',18.1,14.7,4,2.8,solid=False),prop('plant',20.05,16.2,.65,.65)],
 'units':[unit('alpha','ALPHA','선봉',11.15,18.2),unit('bravo','BRAVO','지원',12.45,18.2),unit('charlie','CHARLIE','돌입',10.8,19.15),unit('delta','DELTA','엄호',13,19.15)],
 'enemies':[
  enemy('e1',12.25,11.85,-1.57,name='무장 인원'),
  enemy('e2',5.5,11.8,-2.5,name='무장 인원'),
  enemy('e3',18.65,12.5,0.2,name='무장 인원'),
  enemy('e4',13.25,5.3,-2.6,name='무장 인원',patrol=[[13.25,5.3],[13.25,8.2]]),
  enemy('e5',4.65,8.6,-1.57,name='무장 인원'),
  enemy('e6',18.7,8.25,-1.2,name='무장 인원',patrol=[[18.7,8.25],[19.4,7.2]])],
 'civilians':[{'id':'c1','x':7.55,'z':4.65,'name':'민간인 01'},{'id':'c2','x':19.8,'z':4.7,'name':'민간인 02'}],
 'objectives':['주택의 무장 인원 6명을 모두 무력화하세요.','민간인 2명에게 접근해 확보하세요.','대원 전원의 생존을 목표로 작전을 수행하세요.'],
 'briefing':{'difficulty':'보통','estimated_minutes':'5–10','threat':'무장 인원 · 민간인 혼재','tip':'문 앞에서 대열을 정리하세요. 스턴과 대기 신호 A/B를 사용하면 동시 진입을 계획할 수 있습니다.'}}
tutorial['units'][1]['weapon']='light'
house['units'][2]['weapon']='light'
house['units'][3]['weapon']='light'
for name,data in [('tutorial',tutorial),('house',house)]:
    for i,wall in enumerate(data['walls']): wall['id']=f'{name}_w{i+1:02d}'
    for i,p in enumerate(data['props']): p['id']=f'{name}_p{i+1:02d}'
    upgrade(data)
    path=ROOT/'game/data'/f'{name}.json'
    preserve_enemy_strengths(data, path)
    path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
    print(f'{path.name}: {len(data["rooms"])} rooms, {len(data["doors"])} doors, {len(data["props"])} props')
