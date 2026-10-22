"""Focused ground sectors; metres, doors and indoor dimensions stay authored."""
from copy import deepcopy
import math

# Origin and extent in the original author's coordinates, not a mesh scale.
SECTORS = {
    'H01': (42, 32, 157, 37), 'H02': (210, 36, 78, 80),
    'H09': (5, 0, 110, 70), 'H11': (54, 27, 96, 98),
    'H16': (50, 38, 116, 108), 'H26': (42, 18, 70, 68),
    'H29': (55, 28, 130, 105), 'H36': (55, 55, 110, 82),
}


def _move_group(data, prefix, dx, dz):
    for group in ('rooms', 'walls', 'doors', 'props', 'scenery'):
        for item in data.get(group, []):
            if item['id'].startswith(prefix):
                item['x'] += dx
                item['z'] += dz


def _squad(data, x, z):
    for actor, (dx, dz) in zip(data['units'], ((0, 0), (.85, 0), (0, .85), (.85, .85))):
        actor.update(x=x+dx, z=z+dz, facing=-1.5707963267948966)


def compact(source, registry):
    data = deepcopy(source)
    mid = data['id']
    if mid == 'H03':
        return data  # Already authored as a 42 x 40 metre sector.
    if mid in ('H04', 'H06', 'H07'):
        plane = next(s for s in data['scenery'] if s['id'] == 'historical_airframe')
        length, _, span = registry[plane['asset']]['dimensions_m']
        x0=math.floor((plane['x']-length/2-5)*4)/4
        z0=math.floor((plane['z']-span/2-5)*4)/4
        sector=(x0,z0,math.ceil((length+10.5)*4)/4,math.ceil((span+10.5)*4)/4)
        entrance = data['doors'][0]
        _squad(data, entrance['x']-1, plane['z']+7)
        data['scenery'] = [plane]
        data['props'] = [p for p in data['props'] if not p['id'].startswith('baggage_cart')]
    else:
        sector = SECTORS[mid]
    if mid == 'H01':
        data['scenery'] = [s for s in data['scenery'] if s['id'] not in ('naval_over_sea', 'boarding_rhib', 'stern_lifeboat')]
        # Overlap neighboring deck strips so float subtraction cannot create sea slivers.
        for area in data['walkable_areas']: area['w']+=.02
    elif mid == 'H02':
        _squad(data, 250, 108)
        data['enemies'][0].update(x=220, z=105)
        data['enemies'][-1].update(x=281, z=100)
        data['scenery'] = []
        data['walls'] = [p for p in data['walls'] if not p['id'].startswith('old_terminal_facade')]
        data['props'] = [p for p in data['props'] if p['id'] not in ('black_sedan', 'terminal_objects_4', 'terminal_objects_5')]
        data['objectives'] = ['구터미널 대합실과 직원 구역의 위협을 처리하세요.', '민간인을 확인하고 모두 확보하세요.']
    elif mid == 'H09':
        old = [(90,142),(114,174),(136,119),(181,153),(217,112),(245,144),(263,99)]
        new = [(20,35),(35,55),(40,20),(55,40),(75,20),(80,45),(95,15)]
        for i, ((x,z),(nx,nz)) in enumerate(zip(old,new)):
            for prefix in (f'village_hut_{i}', f'hut_shell_{i}', f'hut_living_prop_{i}'):
                _move_group(data,prefix,nx-x,nz-z)
        for actor in data['enemies']+data['civilians']:
            i=min(range(len(old)),key=lambda i:(actor['x']-old[i][0])**2+(actor['z']-old[i][1])**2)
            actor['x']+=new[i][0]-old[i][0]
            actor['z']+=new[i][1]-old[i][1]
        data['enemies'][-1].update(x=62,z=56)
        data['rooms'] = [r for r in data['rooms'] if r['id'] != 'mud_track']
        data['walkable_areas'] = [dict(id='rescue_bank',x=60,z=35,w=110,d=70)]
        data['scenery'] = [s for s in data['scenery'] if s['id'].startswith('hut_shell')]
        for i,(x,z) in enumerate(((12,12),(15,61),(50,8),(67,64),(104,53))):
            data['scenery'].append(dict(id=f'village_edge_palm_{i}',asset='palm_tree',x=x,z=z,rotation=0,scale=.9,height=0))
        data['environment']['water']=False
        data.pop('walkable_areas',None)
        data['props'] = [p for p in data['props'] if p['id'] != 'landing_supply']
        _squad(data,20,48)
        data['objectives'] = ['오두막 사이의 근거리 통로를 확보하세요.', '억류 인원을 확인하고 모두 확보하세요.']
    elif mid == 'H11':
        _squad(data,89,120)
        data['scenery'] = [s for s in data['scenery'] if s['id'].startswith('compound_bush')]
        data['walls'] = [w for w in data['walls'] if not w['id'].startswith('compound_three_storey_shell')]
    elif mid == 'H16':
        _squad(data,104,133)
        next(t for t in data['interactive_targets'] if t['id']=='regroup').update(x=105,z=138)
    elif mid == 'H26':
        _squad(data,72,78)
        next(t for t in data['interactive_targets'] if t['id']=='return_wadi').update(x=72,z=79)
        data['rooms'] = [r for r in data['rooms'] if r['id']!='wadi']
    elif mid == 'H29':
        _move_group(data,'farm_safehouse',37,-26)
        next(t for t in data['interactive_targets'] if t['id']=='guerrilla_meeting').update(x=66,z=111)
        next(w for w in data['win'] if w['type']=='escort_to_zone')['zone']=[66,111,22,14]
        _squad(data,60,103)
    elif mid == 'H36':
        _squad(data,75,123)
        next(t for t in data['interactive_targets'] if t['id']=='ground_evacuation').update(x=75,z=123)
        next(w for w in data['win'] if w['type']=='escort_to_zone')['zone']=[75,123,24,16]
        next(r for r in data['rooms'] if r['id']=='evacuation_muster_area').update(x=75,z=123)
        data['walls']=[w for w in data['walls'] if w['id']!='hotel_upper_backdrop']
        data['props']=[p for p in data['props'] if p['id']!='hotel_balcony_slab']
    x0,z0,width,depth=sector
    x1,z1=x0+width,z0+depth
    # Clip non-playable terrain and external boundaries; never clip an indoor room or door.
    for group in ('rooms','walls','props','walkable_areas'):
        kept=[]
        for item in data.get(group,[]):
            left=max(x0,item['x']-item['w']/2);right=min(x1,item['x']+item['w']/2)
            top=max(z0,item['z']-item['d']/2);bottom=min(z1,item['z']+item['d']/2)
            if right<=left or bottom<=top:
                assert group!='rooms' or not item.get('indoor',True), (mid,item['id'])
                continue
            if (left>item['x']-item['w']/2 or right<item['x']+item['w']/2 or top>item['z']-item['d']/2 or bottom<item['z']+item['d']/2) and (group in ('walls','walkable_areas') or group=='rooms' and not item.get('indoor',True)):
                item.update(x=(left+right)/2,z=(top+bottom)/2,w=right-left,d=bottom-top)
            kept.append(item)
        if group in data:data[group]=kept
    data['scenery']=[s for s in data['scenery'] if x0+2<s['x']<x1-2 and z0+2<s['z']<z1-2]
    for group in ('rooms','walls','doors','props','walkable_areas','units','enemies','civilians','interactive_targets','scenery'):
        for item in data.get(group,[]):
            item['x']=round(item['x']-x0,6);item['z']=round(item['z']-z0,6)
            for key in ('w','d'):
                if key in item:item[key]=round(item[key],6)
            assert 0<=item['x']<=width and 0<=item['z']<=depth, (mid,group,item['id'])
    for rule in data['win']:
        if 'zone' in rule:rule['zone']=[round(rule['zone'][0]-x0,6),round(rule['zone'][1]-z0,6),*rule['zone'][2:]]
    data.update(bounds=[round(width,3),round(depth,3)],focus=[round(width/2,3),round(depth/2,3)],revision=source['revision']+1)
    data['description']='진입 직전부터 시작하는 근거리 작전 구역입니다. 건물·객실·문은 미터 단위 크기를 유지하며 위협과 구조 대상을 확인하세요.'
    data['briefing'].update(estimated_minutes='3–8',tip='출입구 앞에서 시작합니다. 문 진입과 구획 확인을 계획하고 민간인을 확보하세요.')
    note=data['historical']['accuracy_note']
    note=note.replace(' 고유 외관을 연상시키는 전체 건축 외피는 대표 지상층 플레이 영역과 분리한 외곽 배경으로 배치했습니다. 배경 외피와 추정 실내를 같은 실측 건물로 주장하지 않습니다.','')
    if mid=='H01':note=note.replace(', "Naval", "RHIB", "밀폐구명정"','')
    if mid=='H09':note=note.replace(' 브레스크 개울의 43m 폭 대표 수로가 두 강둑을 분리합니다. 북쪽 북쪽 마을는 연결하지 않은 배경이며 자유 수영으로 강을 건너지는 않습니다. 수로 폭은 실측이 아닌 공간 설계입니다.',' 강과 북쪽 강둑은 플레이 구역에서 생략하고 남쪽 마을 구출 구역만 표현합니다.')
    data['historical']['accuracy_note']=note
    data['historical']['accuracy_note']+='가상의 작전 구역입니다. 실내·객실·문은 사람 크기에 맞춰 설계했으며 지상층에서 목표를 수행합니다.'
    return data
