"""Shared authoring tools. Coordinates and dimensions are real-world metres.

Buildings retain human-scale rooms and doors; only terrain context is cropped.
This module never rewrites the existing fictional maps.
"""
from __future__ import annotations
import math

ALIASES = {
    'ship_tanker': 'tanker_ship_hull', 'rock':'rock_medium', 'rock_small':'rock_small',
    'rock_large':'rock_large','pine':'pine_tree','palm':'palm_tree',
    'container':'cargo_container','pipes':'tanker_deck_pipes',
    'utility':'helicopter_utility','light':'helicopter_light','naval':'helicopter_naval',
    'tandem':'helicopter_tandem','cargo':'helicopter_cargo','heavy_lift':'helicopter_heavy_lift',
    'transport':'helicopter_transport','rescue':'helicopter_rescue',
    'utility_vehicle':'utility_vehicle','truck':'cargo_truck','hangar':'hangar_shell',
    'bridge_lift':'lift_bridge','bridge_glider':'girder_bridge',
    'glider_glider':'cargo_glider','ship_patrol_ship':'patrol_ship_hull',
    'terminal':'terminal_shell','fortress':'fortress_shell','temple':'temple_sanctum',
    'compound':'compound_shell','townhouse':'townhouse_shell','hotel_courtyard':'courtyard_hotel_shell',
    'industrial':'industrial_shell','fence':'fence_panel',
}

class MapBuilder:
    def __init__(self, id, title, bounds, biome='urban', ground_color='#77745d'):
        self.data = dict(schema_version=6,roe='precision',id=id,revision=1,title=title,
            title_en=title, seed=20261009+int(id[1:]),bounds=list(bounds),
            focus=[bounds[0]/2,bounds[1]/2],rooms=[],walls=[],doors=[],props=[],
            units=[],enemies=[],civilians=[],objectives=[],scenery=[],
            historical=dict(location="가상 작전 구역",
                accuracy_note='가상의 장소에서 수행하는 특수 작전입니다.'),
            environment=dict(time_of_day='day',lighting=0.95,biome=biome,ground_color=ground_color,water=False,ground_surface='concrete'),
            description='가상의 장소에서 수행하는 특수 작전입니다.',
            briefing=dict(difficulty='중급',estimated_minutes='8–15',threat='무장 위협과 구조 대상',tip='넓은 전장입니다. 휠로 확대하고 WASD로 이동하며 경유점을 계획하세요.'))
        self._ids=set()

    def _add(self, group, item):
        if item['id'] in self._ids: raise ValueError(f'{self.data["id"]}: duplicate {item["id"]}')
        self._ids.add(item['id']); self.data.setdefault(group,[]).append(item); return item

    def room(self,id,x,z,w,d,label='',indoor=True,**kwargs):
        return self._add('rooms',dict(id=id,x=x,z=z,w=w,d=d,label=label or id,indoor=indoor,**kwargs))

    def wall(self,id,x,z,w,d,height=3,material='concrete',**kwargs):
        return self._add('walls',dict(id=id,x=x,z=z,w=w,d=d,height=height,material=material,**kwargs))

    def door(self,id,x,z,w=0.95,d=0.18,axis='x',**kwargs):
        return self._add('doors',dict(id=id,x=x,z=z,w=w,d=d,axis=axis,height=2.1,hinge_side=-1,swing_sign=-1,state='CLOSED',**kwargs))

    def prop(self,id,type,x,z,w,d,solid=True,height=None,rotation=0,cover=None,**kwargs):
        item=dict(id=id,type=type,x=x,z=z,w=w,d=d,solid=solid,rotation=rotation,**kwargs)
        if height is not None:item['height']=height
        if cover is not None:item['cover']=cover
        return self._add('props',item)

    def scenery(self,id,asset,x,z,rotation=0,scale=1,height=0):
        return self._add('scenery',dict(id=id,asset=ALIASES.get(asset,asset),x=x,z=z,rotation=rotation,scale=scale,height=height))

    def land(self,id,x,z,w,d):
        self.data['environment']['water']=True
        return self._add('walkable_areas',dict(id=id,x=x,z=z,w=w,d=d))

    def building(self,id,x,z,w,d,label='',door_side='south',door_width=1.0,wall_height=3.0,material='concrete'):
        t=.18
        room=self.room(id,x,z,w-t,d-t,label,True)
        for side in ['north','south','west','east']:
            horizontal=side in ['north','south']
            span=w if horizontal else d
            cx=x+(0 if horizontal else (-w/2 if side=='west' else w/2))
            cz=z+((-d/2 if side=='north' else d/2) if horizontal else 0)
            if side==door_side:
                piece=(span-door_width)/2
                for index,sign in enumerate([-1,1]):
                    offset=sign*(door_width/2+piece/2)
                    self.wall(f'{id}_{side}_{index}',cx+(offset if horizontal else 0),cz+(0 if horizontal else offset),piece if horizontal else t,t if horizontal else piece,wall_height,material)
                self.door(f'{id}_door',cx,cz,w=door_width if horizontal else t,d=t if horizontal else door_width,axis='x' if horizontal else 'z')
            else:
                self.wall(f'{id}_{side}',cx,cz,w if horizontal else t,t if horizontal else d,wall_height,material)
        return room

    def squad(self,x,z):
        for i,(dx,dz) in enumerate([(0,0),(.85,0),(0,.85),(.85,.85)]):
            self._add('units',dict(id=f'u{i+1}',name=f'대원 {i+1}',role='대원',x=x+dx,z=z+dz,facing=0,weapon='standard',hp=100,ammo=24,reserve_ammo=168,stuns=2,vision_range=28,fov=110))
        self.data['focus']=[x+5,z]
        return self.data['units']

    def enemy(self,x,z,id=None,**kwargs):
        defaults=dict(id=id or f'e{len(self.data["enemies"])+1}',x=x,z=z,facing=math.pi,weapon='standard',hp=70,ammo=24,vision_range=22,fov=105)
        defaults.update(kwargs);return self._add('enemies',defaults)

    def civilian(self,x,z,id=None,**kwargs):
        item=dict(id=id or f'c{len(self.data["civilians"])+1}',x=x,z=z,name='구조 대상',hp=100,facing=0)
        item.update(kwargs);return self._add('civilians',item)

    def target(self,id,x,z,w=2,d=2,label='',action='inspect',duration=3):
        return self._add('interactive_targets',dict(id=id,x=x,z=z,w=w,d=d,label=label or id,action=action,duration=duration))

    def finish(self,win=None,fail=None,objectives=None,focus=None):
        if not self.data['units']:raise ValueError('Missing squad')
        targets=self.data.get('interactive_targets',[])
        if win is None:
            win=[]
            if self.data['enemies']:win.append(dict(type='neutralize_all'))
            if self.data['civilians']:win.append(dict(type='secure_all_civilians'))
            if targets:win.append(dict(type='targets_complete',targets=[t['id'] for t in targets]))
            if not win:raise ValueError('Mission requires a meaningful objective')
        self.data['win']=win
        self.data['fail']=fail if fail is not None else [dict(type='no_civilian_loss')]
        self.data['objectives']=objectives or ['지정 목표를 완료하고 대원의 생존을 유지하세요.']
        if focus is not None:self.data['focus']=list(focus)
        return self.data
