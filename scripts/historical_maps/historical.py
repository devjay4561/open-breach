'가상의 작전 구역입니다. 실내·객실·문은 사람 크기에 맞춰 설계했으며 지상층에서 목표를 수행합니다.'
from __future__ import annotations

from math import pi
from .common import MapBuilder


def _setup(code, title, bounds, note, biome, color,
           night=False, surface='gravel'):
    m = MapBuilder(code, title, bounds,  biome, color)
    m.data['environment'].update(time_of_day='night' if night else 'day',
                                 lighting=.66 if night else .96,
                                 ground_surface=surface)
    m.data['historical']['accuracy_note'] = note
    m.data['description'] = note
    return m


def _cell(m, id, x, z, label, side='south', w=6, d=7, material='masonry'):
    """Human-scale compartment; never shrink a whole historical building."""
    return m.building(id, x, z, w, d, label, side, .95, 3.0, material)


def _furniture(m, id, x, z, kind='desk'):
    dimensions = {'desk': (1.3, .7), 'table': (1.6, .8), 'bed': (.9, 2),
                  'crate': (.9, .8), 'cabinet': (.8, .5), 'chair': (.5, .5)}
    w, d = dimensions[kind]
    return m.prop(id, kind, x, z, w, d, height=.8 if kind != 'bed' else .55)


def _rock(m, id, x, z, size=2.8):
    m.scenery(id + '_mesh', 'rock', x, z, scale=size / 2.8)
    m.wall(id + '_solid', x, z, size * .8, size * .95,
           height=.86051 * size / 2.8, material='masonry', render=False)


def _fence(m, id, x, z, w, d):
    m.wall(id, x, z, w, d, height=1.5, material='wood')


def _targets_win(m):
    return dict(type='targets_complete', targets=[v['id'] for v in m.data['interactive_targets']])


def _merchant(m, id, x, z, length=82, beam=11):
    """Original period cargo silhouette, static and wholly non-interactive.

    The hull is deliberately not a modern tanker or an unrelated warship asset.
    Stepped ends and deckhouses are coarse authored geometry, not ship plans.
    """
    m.prop(id + '_deck', 'rug', x, z, length, beam, solid=False,
           cover='none', height=.05, material='wood')
    m.wall(id + '_hull', x, z, length - 6, beam, height=2.6, material='steel')
    m.wall(id + '_bow', x + length / 2 - 2, z, 4, beam * .55,
           height=2.6, material='steel')
    m.wall(id + '_stern', x - length / 2 + 2, z, 4, beam * .75,
           height=2.6, material='steel')
    m.prop(id + '_deckhouse', 'cabinet', x - length * .28, z, 6, 7,
           height=5.5, material='steel')
    for j, offset in enumerate([-.1, .23]):
        m.prop(id + f'_mast{j}', 'pillar', x + length * offset, z, .35, .35,
               height=8, material='wood')


def stone_echo():
    m = _setup('H26', '스톤 에코', (112, 96),
        '오르브렌 본부에서 문서를 회수하고 정보 오류를 확인한 뒤 복귀하세요.',
        'dry_ravine', '#777063', True)
    m.room('wadi', 28, 55, 32, 62, '거친 와디 접근', False)
    m.room('garden', 71, 61, 45, 20, '본부 앞 정원', False)
    m.room('vehicle_yard', 97, 60, 20, 22, '차량 마당', False)
    for i, (x, z) in enumerate([(15, 16), (26, 27), (39, 43), (19, 74), (37, 80), (53, 13)]):
        _rock(m, f'wadi_rock{i}', x, z, 3.4)
    _fence(m, 'garden_west', 47, 48, .22, 27)
    _fence(m, 'garden_east', 105, 47, .22, 35)
    _fence(m, 'garden_south_left', 57, 72, 20, .22)
    _fence(m, 'garden_south_right', 91, 72, 28, .22)
    m.room('hq_corridor', 78, 34, 4.2, 19, '본부 현관과 통로', True,
           floor_surface='tile')
    for i, z in enumerate([27.5, 34, 40.5]):
        _cell(m, f'hq_w{i}', 72.9, z, '본부 지상층 서측실', 'east', 6, 6, 'plaster')
        _cell(m, f'hq_e{i}', 83.1, z, '본부 지상층 동측실', 'west', 6, 6, 'plaster')
        _furniture(m, f'hq_desk{i}', 71, z - 1.7)
    m.wall('corridor_north', 78, 24.5, 4.2, .18, material='plaster')
    m.wall('vestibule_left', 76.71, 43.5, 1.625, .18, material='plaster')
    m.wall('vestibule_right', 79.29, 43.5, 1.625, .18, material='plaster')
    m.door('hq_front_door', 78, 43.5)
    m.scenery('period_utility_vehicle', 'utility_vehicle', 97, 55)
    m.wall('utility_vehicle_collision', 97, 55, 3.625, 1.71, 1.3, 'metal', render=False)
    m.scenery('rough_garden_tree', 'pine', 58, 52, scale=.55)
    m.prop('tree_trunk', 'pillar', 58, 52, .35, .35, height=4, material='wood')
    m.enemy(83.1, 27.5, hold_position=True)
    m.enemy(95, 63, hold_position=True)
    m.enemy(72.9, 40.5, hold_position=True)
    m.target('headquarters_documents', 83.1, 34, label='본부 문서 확인 · 정보 오류', action='recover', duration=5)
    m.target('return_wadi', 17, 83, label='와디 철수 지점 확인', duration=3)
    m.squad(13, 83)
    return m.finish(objectives=['본부의 지상층을 확인하고 문서를 회수하세요.',
        '지휘 인원의 부재와 정보 오류를 확인한 뒤 와디로 복귀하세요.'])


def wide_furrow():
    m = _setup('H29', '와이드 퍼로우', (208, 160),
        '브렐케스 수용소의 포로를 확보하고 협력 인원의 집결지로 호송하세요.',
        'tropical_farmland', '#797c57', True)
    m.room('rice_fields', 37, 78, 60, 130, '수용소 밖 논과 접근 둑', False)
    m.room('north_road', 139, 25, 130, 7, '수용소 북쪽 도로', False)
    m.room('camp_yard', 128, 78, 96, 84, '포로수용소 마당', False)
    _fence(m, 'camp_north', 128, 35, 100, .22)
    _fence(m, 'camp_east', 178, 79, .22, 88)
    _fence(m, 'camp_south', 128, 123, 100, .22)
    _fence(m, 'camp_west_top', 78, 68, .22, 66)
    _fence(m, 'camp_west_bottom', 78, 115, .22, 16)
    m.room('gate_passage', 80, 104, 8, 6, '목재 정문', False)
    for row, x in enumerate([99, 116, 138, 155]):
        for j, z in enumerate([62, 70, 78]):
            _cell(m, f'barrack{row}_{j}', x, z, '포로 막사' if row < 3 else '경비 막사',
                  'west', 7, 6.5, 'wood')
            _furniture(m, f'bunk{row}_{j}', x + 1.8, z - 1.6, 'bed')
    _cell(m, 'guard_house', 86, 92, '정문 경비실', 'west', 6, 6, 'wood')
    _cell(m, 'camp_records_room', 165, 48, '수용소 기록실', 'south', 7, 6, 'wood')
    _cell(m, 'farm_safehouse', 29, 137, '협력 협력 주민 집결지', 'east', 8, 7, 'wood')
    m.scenery('north_watchtower', 'watchtower', 169, 38)
    for i, (dx, dz) in enumerate([(-1.6, -1.6), (-1.6, 1.6), (1.6, -1.6), (1.6, 1.6)]):
        m.wall(f'watchtower_support{i}', 169 + dx, 38 + dz, .18, .18, 6, 'wood', render=False)
    m.scenery('farm_palm', 'palm', 47, 126)
    m.prop('palm_base', 'pillar', 47, 126, .45, .45, height=6, material='wood')
    m.scenery('camp_truck', 'truck', 169, 109)
    m.wall('truck_solid', 169, 109, 6.45, 2.46, 2.2, 'metal', render=False)
    for i, (x, z) in enumerate([(99, 62), (100, 63), (116, 70), (117, 71),
                               (138, 62), (139, 63), (138, 78), (139, 79)]):
        m.civilian(x, z, name=f'구출 포로 {i + 1}')
    m.enemy(86, 92, hold_position=True)
    m.enemy(155, 70, hold_position=True)
    m.enemy(165, 117, hold_position=True)
    m.target('camp_roster', 165, 48, label='포로 기록 회수', action='recover', duration=5)
    m.target('guerrilla_meeting', 29, 137, label='협력 협력 인원과 철수 확인', duration=4)
    m.squad(19, 136)
    return m.finish(win=[dict(type='neutralize_all'), dict(type='secure_all_civilians'),
        _targets_win(m), dict(type='escort_to_zone', zone=[35, 137, 22, 14])],
        objectives=['수용소 경비를 제압하고 포로를 확보하세요.', '기록을 회수하고 협력 협력 인원이 있는 서쪽 집결지로 호송하세요.'])


def _light_aircraft(m, id, x, z, length, span):
    """Original approximate airframe outline; wing and body have real footprint."""
    m.wall(id + '_body', x, z, length, 1.5, 1.3, 'metal')
    m.wall(id + '_wing', x, z, 2.0, span, .75, 'metal')
    m.wall(id + '_tail', x - length * .4, z, 1.1, span * .3, .95, 'metal')
    m.prop(id + '_cockpit', 'pillar', x + length * .22, z, 1.8, 1.3,
           height=1.7, material='glass')


def red_veranda():
    m = _setup('H36', '레드 베란다', (192, 160),
        '네르베스 하우스 호텔에서 인질과 구조 명단을 확보하고 지상 집결지로 호송하세요.',
        'tropical_city', '#8e8069', surface='concrete')
    m.room('west_city_street', 47, 78, 10, 146, '호텔 서쪽 시가지 도로', False)
    m.room('hotel_front_street', 118, 120, 138, 10, '호텔 앞 대피 도로', False)
    m.room('hotel_courtyard', 116, 87, 27, 26, 'Nerveth House 호텔 추정 중정', False)
    m.room('evacuation_muster_area', 28, 137, 26, 18, '도심 지상 집결지', False)
    _cell(m, 'hotel_lobby', 116, 65, '호텔 로비 · 추정 평면', 'south', 8, 8, 'plaster')
    _cell(m, 'hotel_reception', 107, 65, '접수·자료실', 'south', 6, 7, 'plaster')
    for i, z in enumerate([77, 87, 97]):
        _cell(m, f'hotel_west{i}', 94, z, '호텔 지상 서측 대기실', 'east', 7, 7, 'plaster')
        _cell(m, f'hotel_east{i}', 137, z, '호텔 지상 동측 대기실', 'west', 7, 7, 'plaster')
        _furniture(m, f'hotel_bed_w{i}', 91.8, z - 1.9, 'bed')
        _furniture(m, f'hotel_bed_e{i}', 139.2, z - 1.9, 'bed')
    _cell(m, 'city_service_hut', 64, 67, '도심 부속 건물', 'south', 6, 6, 'masonry')
    m.wall('courtyard_front_west', 99, 109, 28, .28, 2, 'masonry')
    m.wall('courtyard_front_east', 130, 109, 28, .28, 2, 'masonry')
    for i, (x, z) in enumerate([(73, 115), (159, 111), (161, 44), (33, 28)]):
        m.scenery(f'tropical_city_palm{i}', 'palm', x, z)
        m.prop(f'palm_collision{i}', 'pillar', x, z, .42, .42, height=6, material='wood')
    m.scenery('period_ground_transport', 'utility_vehicle', 65, 132)
    m.wall('utility_vehicle_solid', 65, 132, 3.625, 1.71, 1.3, 'metal', render=False)
    m.wall('hotel_upper_backdrop', 116, 53, 40, .3, 6.8, 'plaster')
    m.prop('hotel_balcony_slab', 'table', 116, 54.2, 38, 1.3,
           solid=False, cover='none', height=.15, base_height=3.1, material='concrete')
    for i, (x, z) in enumerate([(94, 77), (95, 78), (94, 97), (95, 98), (137, 87), (138, 88)]):
        m.civilian(x, z, name=f'구출 인질 {i + 1}')
    m.enemy(64, 67, hold_position=True)
    m.enemy(137, 77, hold_position=True)
    m.enemy(157, 100, hold_position=True)
    m.target('nerveth_lobby', 116, 65, label='호텔 로비 구조 확인', duration=4)
    m.target('nerveth_records', 107, 65, label='구조 명단 회수', action='recover', duration=5)
    m.target('ground_evacuation', 28, 137, label='도심 지상 집결 완료', duration=4)
    m.squad(21, 137)
    return m.finish(win=[dict(type='neutralize_all'), dict(type='secure_all_civilians'),
        _targets_win(m), dict(type='escort_to_zone', zone=[28, 137, 24, 16])],
        objectives=['Nerveth House 호텔 주변 인질을 확보하고 구조 명단을 회수하세요.',
        '서쪽 도심 지상 집결지로 호송하세요. 공항과 항공 대피는 별도 구역입니다.'])


def build_maps():
    return [stone_echo(), wide_furrow(), red_veranda()]
