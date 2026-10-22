#!/usr/bin/env python3
"""Rebuild the three authored expansion floor plans; no random geometry."""
import json, math
from mission_authoring import preserve_enemy_strengths
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]

def create(mid, name, title, english, description, rects, gaps, placements, civilians, props, win=None):
    rooms=[dict(id=f'{mid}_r{i+1}',label=label,x=(x1+x2)/2,z=(z1+z2)/2,w=x2-x1,d=z2-z1,color=['#716c60','#67756d','#777368'][i%3]) for i,(label,x1,z1,x2,z2) in enumerate(rects)]
    edges={}
    for _,x1,z1,x2,z2 in rects:
        for axis,c,lo,hi in [('x',z1,x1,x2),('x',z2,x1,x2),('z',x1,z1,z2),('z',x2,z1,z2)]:edges.setdefault((axis,c),[]).append((lo,hi))
    walls=[];doors=[]
    for i,(axis,c,at) in enumerate(gaps):
        doors.append(dict(id=f'{mid}_d{i+1}',x=at if axis=='x' else c,z=c if axis=='x' else at,w=1.8 if axis=='x' else .24,d=.24 if axis=='x' else 1.8,axis=axis,state='CLOSED',label=f'D{i+1:02}'))
    for (axis,c),ranges in edges.items():
        marks=sorted({v for pair in ranges for v in pair}|{v for a,b,at in gaps if a==axis and b==c for v in [at-.9,at+.9]})
        for lo,hi in zip(marks,marks[1:]):
            m=(lo+hi)/2
            if not any(a<=m<=b for a,b in ranges) or any(a==axis and b==c and at-.9<m<at+.9 for a,b,at in gaps):continue
            walls.append(dict(id=f'{mid}_w{len(walls)+1}',x=m if axis=='x' else c,z=c if axis=='x' else m,w=round(hi-lo,4) if axis=='x' else .24,d=.24 if axis=='x' else round(hi-lo,4)))
    units=[dict(id=uid,name=label,role='operator',x=x,z=z,facing=-math.pi/2,weapon=weapon,stuns=2,smokes=1,breaches=1) for uid,label,x,z,weapon in [('alpha','ALPHA',13.5,29,'standard'),('bravo','BRAVO',15,29,'light'),('charlie','CHARLIE',16.5,29,'standard'),('delta','DELTA',18,29,'shotgun')]]
    enemies=[]
    for i,(x,z,role,patrol) in enumerate(placements):
        e=dict(id=f'{mid}_e{i+1}',name={'guard':'경비','reserve':'지원 인원','patrol':'순찰 인원'}[role],x=x,z=z,facing=math.pi/2,weapon='light',enemy_type='normal',response_role=role)
        if patrol:e['patrol']=patrol
        # Alternative facing preserves legal geometry and patrol connectivity.
        e['spawns']=[dict(x=x,z=z,facing=e['facing'],**({'patrol':patrol} if patrol else {})),dict(x=x,z=z,facing=0,**({'patrol':patrol} if patrol else {}))]
        enemies.append(e)
    data=dict(schema_version=1,id=mid,revision=1,title=title,title_en=english,subtitle=english.upper(),description=description,description_en={'M04':'Two entrances, linked guest rooms and a patrolled corridor. Gunfire alerts the other rooms. Secure the guests and clear the building.','M05':'Choose the service entrance or reception. Escort the staff out while guards hold cover and a reserve moves between floorspace sectors.','M06':'Clear the terminal and reach dispatch within 180 seconds. Long freight lanes reward smoke and covering positions; side offices offer an alternate route.'}[mid],seed=int(mid[1:])*1021,default_seed=int(mid[1:])*1021,bounds=[32,32],focus=[16,15],rooms=rooms,walls=walls,doors=doors,props=[dict(id=f'{mid}_p{i+1}',type=t,x=x,z=z,w=w,d=d,rotation=0,cover='full' if t=='cabinet' else 'low') for i,(t,x,z,w,d) in enumerate(props)],units=units,enemies=enemies,civilians=[dict(id=f'{mid}_c{i+1}',name='민간인',x=x,z=z) for i,(x,z) in enumerate(civilians)],objectives=[description],win=win or [dict(type='neutralize_all'),dict(type='secure_all_civilians')],fail=[dict(type='no_civilian_loss')],variant='normal',modifiers=[],briefing=dict(difficulty='보통',estimated_minutes='5–10',threat='분산 경비 · 순찰 · 지원',tip='진입로를 나누고 경보 이후의 이동에 대비하세요.'),stars=[dict(id='complete',label='임무 완료',stat='command_failures',op='eq',value=0),dict(id='survival',label='전원 생존',stat='losses',op='eq',value=0),dict(id='par_time',label='180초 이내',stat='time',op='lte',value=180)])
    if mid=='M06':data['fail'].append(dict(type='time_limit',seconds=180))
    preserve_enemy_strengths(data, (ROOT/'game/data'/f'{name}.json'))
    (ROOT/'game/data'/f'{name}.json').write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')

create('M04','motel','밤의 모텔','Night Motel','서쪽 서비스문과 남쪽 출입문을 활용해 투숙객 2명을 확보하고 모든 위협을 처리하세요.',[
 ('01 / ROOM A',4,4,10,12),('02 / ROOM B',10,4,16,12),('03 / ROOM C',16,4,22,12),('04 / ROOM D',22,4,28,12),('05 / CORRIDOR',4,12,28,16),('06 / LOUNGE',4,16,12,26),('07 / RECEPTION',12,16,20,26),('08 / SERVICE',20,16,28,26)],
 [('x',12,7),('x',12,13),('x',12,19),('x',12,25),('x',16,8),('x',16,16),('x',16,24),('x',26,16),('z',4,14),('z',10,8),('z',22,8),('z',12,22),('z',20,22)],
 [(7,8,'guard',[]),(13,7,'reserve',[]),(19,8,'guard',[]),(25,8,'guard',[]),(9,14,'patrol',[[9,14],[23,14]]),(23,19,'patrol',[[23,19],[23,14],[19,8]]),(8,20,'guard',[]),(16,20,'reserve',[])],[(7,5.5),(26,5.5)],
 [('bed',7,10,2.2,1.4),('bed',13,10,2.2,1.4),('bed',19,10,2.2,1.4),('bed',25,10,2.2,1.4),('cabinet',9,5.5,1,1.6),('cabinet',21,5.5,1,1.6),('sofa',6,22,2.4,1),('table',9,18,2,1),('desk',16,23,2.2,1),('crate',26,22,2,2)])
create('M05','offices','유리 없는 사무동','Office Lockdown','접수실 또는 서쪽 직원 출입구로 진입하고 직원 2명을 남쪽 집결 구역까지 호송하세요.',[
 ('01 / RECORDS',3,3,11,11),('02 / STAFF',3,11,11,19),('03 / SERVICE',3,19,11,27),('04 / HALL',11,3,15,27),('05 / CONFERENCE',15,3,29,11),('06 / OPEN OFFICE',15,11,22,19),('07 / SECURITY',22,11,29,19),('08 / RECEPTION',15,19,29,27)],
 [('z',11,7),('z',11,15),('z',11,23),('z',15,7),('z',15,15),('z',15,23),('x',11,7),('x',19,7),('x',11,19),('x',19,19),('x',19,26),('z',22,15),('x',27,7),('x',27,24)],
 [(6,6,'guard',[]),(7,15,'reserve',[]),(7,23,'guard',[]),(13,20,'patrol',[[13,20],[13,6]]),(19,7,'guard',[]),(26,7,'guard',[]),(18,15,'patrol',[[18,15],[13,15],[13,7]]),(26,15,'reserve',[]),(24,22,'guard',[])],[(5,8),(27,4.5)],
 [('cabinet',8,4.5,2,1),('desk',7,8.5,2.4,1),('table',6,13,2,1),('crate',5,24,1.4,1.4),('table',22,7,3,1.6),('desk',18,17,2,1),('desk',20,13,1.5,1),('cabinet',27,17,2,1),('desk',24,24,3,1),('sofa',18,21,2.4,1)],
 [dict(type='escort_to_zone',zone=[16,29.5,7,3])])
create('M06','terminal','새벽 물류 터미널','Freight Intercept','180초 안에 모든 위협을 처리하고 북동쪽 배차실에 도달하세요. 적재 통로와 측면 사무실을 함께 활용하세요.',[
 ('01 / BREAK ROOM',2,2,10,8),('02 / RECORDS',10,2,18,8),('03 / DISPATCH',18,2,30,8),('04 / WEST STORAGE',2,8,12,20),('05 / SORTING',12,8,24,20),('06 / CONTROL',24,8,30,20),('07 / LOADING',2,20,18,26),('08 / INSPECTION',18,20,30,26)],
 [('x',8,6),('x',8,14),('x',8,21),('x',8,27),('z',10,5),('z',18,5),('z',12,15),('z',24,15),('x',20,7),('x',20,15),('x',20,27),('z',18,23),('x',26,8),('x',26,25),('z',2,14)],
 [(6,5,'guard',[]),(14,5,'reserve',[]),(22,5,'guard',[]),(27,5,'guard',[]),(6,12,'patrol',[[6,12],[6,18],[15,18]]),(16,12,'guard',[]),(21,17,'patrol',[[21,17],[21,10],[21,5]]),(27,14,'reserve',[]),(7,23,'guard',[]),(25,23,'patrol',[[25,23],[21,23],[21,18]])],[],
 [('table',6,3.5,2,1),('cabinet',12,3.5,2,1),('desk',24,4,2,1),('crate',4,12,2,3),('crate',9,16,2,3),('crate',14,12,1.8,3),('crate',18.5,15,1.8,3),('crate',22,12,1.8,3),('cabinet',28.5,17,1,2),('crate',10,23,2,2),('crate',22,24,2,1)],
 [dict(type='neutralize_all'),dict(type='reach_zone',zone=[27,5,3,3]),dict(type='time_limit',seconds=180)])
