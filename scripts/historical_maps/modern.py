"""Fictional prison-camp authoring in metre units."""
from __future__ import annotations
import math
from .common import MapBuilder


def _brief(m, description, accuracy, surface='gravel', lighting=.95):
    m.data['description'] = description
    m.data['historical']['accuracy_note'] = accuracy + ' 공통 실물 기준: 사람 키 1.78m, 실내문 0.95–1.2×2.1m, 일반 층고 3m. 전체 장소를 축소하지 않고 대표 구역을 선택했습니다.'
    m.data['environment'].update(ground_surface=surface, lighting=lighting)
    m.data['briefing']['tip'] = '가상의 작전 구역입니다. 실내·객실·문은 사람 크기에 맞춰 설계했으며 지상층에서 목표를 수행합니다.'


def _field(m, label, color):
    w, d = m.data['bounds']
    m.room('terrain', w/2, d/2, w-.6, d-.6, label, False, color=color, floor_surface='gravel')


def _targets(m, objectives, peaceful=False, focus=None):
    # The ground renderer draws land unions; a whole-map room would hide water
    # and make the non-walkable sides of a ridge look like a walkable floor.
    if m.data.get('walkable_areas'):
        m.data['rooms'] = [r for r in m.data['rooms'] if r['id'] != 'terrain']
    for target in m.data['interactive_targets']:
        target['action'] = {'extract':'board','rescue':'inspect','search':'inspect','observe':'inspect','communicate':'inspect','secure':'inspect'}.get(target['action'],target['action'])
    return m.finish(win=[{'type':'targets_complete','targets':[t['id'] for t in m.data['interactive_targets']]}],
                    fail=[{'type':'no_civilian_loss'}] + ([{'type':'no_shots'}] if peaceful else []),
                    objectives=objectives, focus=focus)


def _three_rooms(m, ident, x, z, w=18, d=12, label='시설', wall_height=3):
    """Three 6×9m offices with a 3m circulation corridor, 1m doors."""
    m.building(ident,x,z,w,d,label,door_width=1.05,wall_height=wall_height)
    cell=w/3
    cz=z+d/2-3
    for i in range(3):
        cx=x-w/2+cell*(i+.5)
        m.room(f'{ident}_room{i+1}',cx,z-1.5,cell-.18,d-3.18,f'{label} / {i+1}실',True)
        for n,sgn in enumerate((-1,1)):
            span=(cell-1.0)/2
            m.wall(f'{ident}_cross{i}_{n}',cx+sgn*(.5+span/2),cz,span,.18,2.8)
        m.door(f'{ident}_internal{i}',cx,cz,1,.18)
        if i<2: m.wall(f'{ident}_partition{i}',x-w/2+cell*(i+1),z-1.5,.18,d-3,2.8)
    return m


def _barracks(m, ident, x, z, w=12, d=24, label='막사', wall_height=3):
    m.building(ident,x,z,w,d,label,door_width=1.1,wall_height=wall_height)
    for i in range(2):
        zz=z-d/2+d/3*(i+1)
        span=(w-1.05)/2
        for n,sgn in enumerate((-1,1)):
            m.wall(f'{ident}_divider{i}_{n}',x+sgn*(.525+span/2),zz,span,.18,2.8)
        m.door(f'{ident}_inside{i}',x,zz,1.05,.18)
    for i in range(3):
        m.room(f'{ident}_cell{i}',x,z-d/2+d/3*(i+.5),w-.4,d/3-.2,f'{label} / 구획 {i+1}',True)


def _rock(m, ident, x, z, scale=1, solid=True):
    m.scenery(ident,'rock',x,z,rotation=(x*.17+z*.11)%math.tau,scale=scale)
    if solid:
        m.wall(f'{ident}_collision',x,z,1.1*scale,.85*scale,1.1*scale,'masonry',render=False)


def _trees(m, points, palm=False, scale=1):
    for i,(x,z) in enumerate(points):
        m.scenery(f'tree{i}', 'palm' if palm else 'pine',x,z,rotation=(i*1.73)%math.tau,scale=scale*(.85+(i%4)*.1))


def grey_wicket():
    m=MapBuilder('H16','그레이 위킷',(192,176),biome='tropical',ground_color='#68775a')
    _brief(m,'192×176m 수용소와 외부 착륙 공간. 중정의 실물 크기 중량 수송 헬기, 낮은 수용동과 외벽을 수색한 뒤 포로가 없음을 확인하고 철수하세요.',
           '가상의 작전 구역입니다. 실내·객실·문은 사람 크기에 맞춰 설계했으며 지상층에서 목표를 수행합니다.',lighting=.8)
    _field(m,'수용소 주변 경작지','#68775a')
    for side,x,z,w,d in [('n',105,45,96,.25),('w',57,84,.25,78),('e',153,84,.25,78)]:m.wall(f'camp_wall_{side}',x,z,w,d,3.2,'masonry')
    m.wall('camp_wall_s1',79,123,44,.25,3.2,'masonry');m.wall('camp_wall_s2',131,123,44,.25,3.2,'masonry')
    _barracks(m,'west_cells',68,82,12,34,'서쪽 수용동')
    _barracks(m,'east_cells',141,80,12,34,'동쪽 수용동')
    _three_rooms(m,'north_cells',105,55,42,12,'북쪽 수용동')
    _three_rooms(m,'administration',126,111,18,10,'관리실')
    m.scenery('courtyard_heavy_lift','heavy_lift',104,87,rotation=math.pi/2)
    m.wall('heavy_lift_airframe',104,87,3.2,13.2,3.4,'metal',render=False)
    for i,(x,z) in enumerate([(57,45),(153,45),(57,123)]):m.scenery(f'watchtower{i}','watchtower',x,z)
    for i,(x,z) in enumerate([(64,72),(72,83),(137,70),(145,83),(93,52),(117,52)]):m.prop(f'empty_bed{i}','bed',x,z,.9,1.95,height=.55,cover='low')
    _trees(m,[(20,30),(30,58),(22,91),(25,127),(45,155),(164,147),(177,103),(168,24),(90,22),(133,16)],palm=True)
    m.squad(91,155)
    for p in [(69,91),(143,92),(107,57),(127,111),(149,119),(159,76)]:m.enemy(*p)
    m.target('west_search',68,79,3,3,'서쪽 수용동 포로 부재 확인','search',5)
    m.target('north_search',105,54,3,3,'북쪽 수용동 포로 부재 확인','search',5)
    m.target('records',126,112,3,3,'관리 기록 확인','inspect',4)
    m.target('regroup',37,144,7,5,'외부 철수 집결지','extract',4)
    return _targets(m,['서쪽·북쪽 수용동 수색','포로 부재와 기록 확인','외부 착륙 공간으로 철수'],focus=(103,88))


def build_maps():
    return [grey_wicket()]
