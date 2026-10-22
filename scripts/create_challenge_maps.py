#!/usr/bin/env python3
"""Fixed, reviewable challenge layouts. Retry preserves the same puzzle."""
import json
from pathlib import Path
from mission_authoring import upgrade, preserve_enemy_strengths
ROOT=Path(__file__).resolve().parents[1]
variants={
 'house': {'patrols':{'e1':[[11.7,12.3],[13.2,14.7]],'e2':[[5.5,11.8],[7.7,12.5]],'e3':[[18.65,12.5],[17,12.2]]},'extra':[(11,8.4),(7.5,8.7)]},
 'archive':{'patrols':{'a_e1':[[9,12],[7.5,14.5]],'a_e2':[[6.5,7],[9,8]],'a_e3':[[17,7.5],[18.5,8.4]]},'extra':[(14.5,12),(10,4)]},
 'depot':{'patrols':{'b_e1':[[8.2,12.5],[11.8,14.5]],'b_e2':[[4.3,7.5],[8,7.5]],'b_e3':[[11.5,3.5],[8,3.5]],'b_e4':[[17,8],[18.7,6.2]]},'extra':[(12.7,8),(16,13)]}}
for name,config in variants.items():
    data=json.loads((ROOT/'game/data'/f'{name}.json').read_text())
    data['id']+='H';data['title']+=' · 도전';data['seed']+=5000
    for enemy in data['enemies']:
        if enemy['id'] in config['patrols']:
            points=config['patrols'][enemy['id']]
            enemy.update(x=points[0][0],z=points[0][1],patrol=points)
    for i,(x,z) in enumerate(config['extra']):
        data['enemies'].append(dict(id=f'{name}_extra{i+1}',x=x,z=z,facing=1.5707963268,weapon='light'))
    data['objectives']=[f"위협 {len(data['enemies'])}명 처리",f"민간인 {len(data['civilians'])}명 확보",'도전 난이도 기록 달성']
    upgrade(data)
    preserve_enemy_strengths(data, (ROOT/'game/data'/f'{name}_challenge.json'))
    (ROOT/'game/data'/f'{name}_challenge.json').write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
