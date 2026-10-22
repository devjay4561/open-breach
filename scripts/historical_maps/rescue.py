"""Authored, metre-scale rescue environments H01–H12.

Verified vehicle dimensions are kept separate from interpreted interiors. These
are twelve distinct sites, not twelve variations of the original 32 m room.
"""
from __future__ import annotations

import json
import math

from .common import MapBuilder


def _wall_with_openings(b, key, axis, fixed, lo, hi, openings=(), height=3.0,
                        material="concrete"):
    """Wall fragments leave an exact opening; doors never overlap their wall."""
    cursor = lo
    for number, (center, width) in enumerate(sorted(openings)):
        left, right = center - width / 2, center + width / 2
        if left > cursor:
            midpoint = (cursor + left) / 2
            b.wall(f"{key}_s{number}", midpoint if axis == "x" else fixed,
                   fixed if axis == "x" else midpoint,
                   left - cursor if axis == "x" else .2,
                   .2 if axis == "x" else left - cursor,
                   height=height, material=material)
        b.door(f"{key}_d{number}", center if axis == "x" else fixed,
               fixed if axis == "x" else center,
               w=width if axis == "x" else .18,
               d=.18 if axis == "x" else width, axis=axis)
        cursor = max(cursor, right)
    if cursor < hi:
        midpoint = (cursor + hi) / 2
        b.wall(f"{key}_last", midpoint if axis == "x" else fixed,
               fixed if axis == "x" else midpoint,
               hi - cursor if axis == "x" else .2,
               .2 if axis == "x" else hi - cursor,
               height=height, material=material)


def _perimeter(b, key, x, z, w, d, south=(), north=(), west=(), east=(),
               height=3.0, material="concrete"):
    _wall_with_openings(b, key + "_n", "x", z - d / 2, x - w / 2, x + w / 2,
                        north, height, material)
    _wall_with_openings(b, key + "_s", "x", z + d / 2, x - w / 2, x + w / 2,
                        south, height, material)
    _wall_with_openings(b, key + "_w", "z", x - w / 2, z - d / 2, z + d / 2,
                        west, height, material)
    _wall_with_openings(b, key + "_e", "z", x + w / 2, z - d / 2, z + d / 2,
                        east, height, material)


def _box(b, key, x, z, w, d, label, south=True, north=False, west=False,
         east=False, door_width=1.05, height=3.0):
    b.room(key, x, z, w, d, label=label)
    _perimeter(b, key, x, z, w, d,
               south=[(x, door_width)] if south else (),
               north=[(x, door_width)] if north else (),
               west=[(z, door_width)] if west else (),
               east=[(z, door_width)] if east else (), height=height)


def _suite(b, key, x, z, w, d, cells=3, corridor=1.6, labels=(), height=3.0):
    """Two rows of rooms connected by a real 1.6–2.0 m corridor."""
    _perimeter(b, key, x, z, w, d, west=[(z, 1.1)], east=[(z, 1.1)], height=height)
    b.room(key + "_hall", x, z, w, corridor, label="연결 복도")
    cell_width = w / cells
    depth = (d - corridor) / 2
    doors = [(x - w / 2 + cell_width * (i + .5), 1.05) for i in range(cells)]
    for sign, row in [(-1, "north"), (1, "south")]:
        _wall_with_openings(b, key + "_" + row, "x", z + sign * corridor / 2,
                            x - w / 2, x + w / 2, doors, height)
        for i in range(cells):
            cx = x - w / 2 + cell_width * (i + .5)
            cz = z + sign * (corridor / 2 + depth / 2)
            label = labels[i + (0 if sign < 0 else cells)] if len(labels) == 2 * cells else "생활·업무실"
            b.room(f"{key}_{row}_{i}", cx, cz, cell_width, depth, label=label)
            if i:
                b.wall(f"{key}_{row}_partition{i}", x - w / 2 + i * cell_width,
                       cz, .2, depth, height=height)


def _deep_suite(b, key, x, z, w, d, rows=5, corridor=1.8, labels=(), height=3.2):
    """Deep terrace / hotel wing with an axial hallway and narrow side rooms."""
    _perimeter(b, key, x, z, w, d, north=[(x, 1.1)], south=[(x, 1.1)], height=height)
    b.room(key + "_hall", x, z, corridor, d, label="긴 중앙 복도")
    room_width = (w - corridor) / 2
    room_depth = d / rows
    doors = [(z - d / 2 + room_depth * (i + .5), 1.05) for i in range(rows)]
    for sign, side in [(-1, "west"), (1, "east")]:
        _wall_with_openings(b, key + "_" + side, "z", x + sign * corridor / 2,
                            z - d / 2, z + d / 2, doors, height)
        for i in range(rows):
            cx = x + sign * (corridor / 2 + room_width / 2)
            cz = z - d / 2 + room_depth * (i + .5)
            label = labels[i] if len(labels) == rows else "대표 실내 구획"
            b.room(f"{key}_{side}_{i}", cx, cz, room_width, room_depth, label=label)
            if i:
                b.wall(f"{key}_{side}_partition{i}", cx, z - d / 2 + i * room_depth,
                       room_width, .2, height=height)


def _actors(b, enemies=(), civilians=()):
    for x, z in enemies:
        b.enemy(x, z)
    for x, z in civilians:
        b.civilian(x, z)


def _furniture(b, key, items):
    for i, (kind, x, z, w, d) in enumerate(items):
        b.prop(f"{key}_{i}", kind, x, z, w, d)


def _background(b, key, asset, x, z, w, d, height, rotation=0):
    """Whole exterior silhouettes remain apart from playable room footprints."""
    b.scenery(key, asset, x, z, rotation=rotation).update(cutaway=False)
    b.wall(key + "_collision", x, z, w, d, height=height, render=False)


def _finish(b, objectives, focus, dimensions=None, win=None):
    result = b.finish(objectives=objectives, focus=focus, win=win)
    result["historical"]["playable_levels"] = 1
    result["historical"]["vertical_scope"] = '가상의 작전 구역입니다. 실내·객실·문은 사람 크기에 맞춰 설계했으며 지상층에서 목표를 수행합니다.'
    if dimensions:
        result["historical"]["verified_dimensions_m"] = dimensions
    return result


def salt_meridian():
    b = MapBuilder("H01", '솔트 메리디언', (240, 100),  biome="ocean", ground_color="#123c51")
    b.data["environment"]["water"] = True
    b.data["environment"]["water_level"] = -3.45
    b.data["environment"]["time_of_day"] = "dim"
    b.data["environment"]["ground_surface"] = "ship_deck"
    # Exact hull length/beam; only the narrower painted deck and bow are walkable.
    b.scenery("tanker_hull", "ship_tanker", 120, 50)
    b.land("working_deck", 112.725, 50, 101.85, 22.5)
    # Conservative strips follow the actual Blender hull contour: a flared
    # stern, full-width middle, taper, then pointed bow. Water is never floor.
    def tapered_strips(key, lo, hi, half_lo, half_hi):
        cursor, i = lo, 0
        while cursor < hi:
            end = min(cursor + 2, hi)
            half_start = half_lo + (half_hi - half_lo) * (cursor - lo) / (hi - lo)
            half_end = half_lo + (half_hi - half_lo) * (end - lo) / (hi - lo)
            usable_half = min(half_start, half_end) - .15
            if usable_half > .5:
                b.land(f"{key}_{i}", (cursor + end) / 2, 50, end - cursor, usable_half * 2)
            cursor, i = end, i + 1
    tapered_strips("aft_flare", 47.25, 61.8, 10.902, 11.85)
    tapered_strips("forward_taper", 163.65, 182.565, 11.85, 7.584)
    tapered_strips("bow_taper", 182.565, 192.75, 7.584, 0)
    b.room("main_deck", 120, 50, 145.5, 23.7, label="145.5m 화학탱커 · 녹색 주갑판", indoor=False, color="#326854")
    _suite(b, "aft_accommodation", 65, 50, 25, 20.5, 4, 1.6,
           ("선원 식당", "휴게실", "비품실", "작업 사무실", "승무원 거실", "승무원 거실", "의무 구역", "생활실"))
    # The outer bays are divided into 6.25 × 4.73 m human-scale rooms.
    for side, partition_z in [("north", 44.475), ("south", 55.525)]:
        _wall_with_openings(b, f"aft_{side}_inner", "x", partition_z, 52.5, 77.5,
                            [(55.625 + i * 6.25, 1.05) for i in range(4)])
    b.scenery("white_aft_superstructure", "tanker_superstructure", 66, 50)
    # Pipes are long, discontinuous bundles, not shipping containers or giant tanks.
    for i, (x, length) in enumerate([(88, 10), (107, 15), (130, 17), (155, 18), (178, 8)]):
        b.wall(f"pipeline_proxy_{i}", x, 50, length, 3.2,
               height=.95, material="metal", render=False)
    b.scenery("process_pipe_bundle", "pipes", 125, 50)
    for i, x in enumerate([90, 122, 148, 172]):
        b.prop(f"pump_cabinet_{i}", "cabinet", x, 56, 1.3, 1.1,
               height=1.45, cover="full")
    b.wall("port_rail", 120, 38.65, 145.5, .16, height=1.05, material="metal", render=False)
    b.wall("starboard_rail", 120, 61.35, 145.5, .16, height=1.05, material="metal", render=False)
    b.scenery("naval_over_sea", "naval", 210, 76, height=10)
    b.scenery("boarding_rhib", "rhib", 55, 69, rotation=math.pi / 2, height=-3.65)
    b.scenery("stern_lifeboat", "lifeboat", 56, 64, height=-3.65)
    _furniture(b, "crew_furniture", [("table", 56, 41.5, 2.2, .85),
                                    ("sofa", 66, 42.5, 2.2, .9),
                                    ("cabinet", 74, 42.4, 1.6, .7),
                                    ("bed", 56, 57.8, 1, 2.0),
                                    ("desk", 67, 53.3, 1.4, .7),
                                    ("bed", 73, 57.8, 1, 2.0)])
    b.squad(174, 55.5)
    _actors(b, [(168, 44), (145, 54), (113, 44), (91, 54), (70, 50), (73, 53)],
            [(55.5, 46.8), (63.5, 53), (73.5, 47), (56, 52.3), (64.5, 45.5)])
    result = _finish(b, ["실제 길이의 주갑판과 배관 통로를 확보하세요.",
                         "후방 거주구의 승무원을 확인하고 보호하세요."], (119, 50),
                     {"ship_length": 145.5, "ship_beam": 23.7})
    result["historical"]["landmarks"] = ["화학탱커 관로 갑판", "흰 후방 거주구", "Naval", "RHIB", "밀폐구명정"]
    return result


def glass_horizon():
    b = MapBuilder("H02", '글래스 호라이즌', (360, 240),  biome="airport", ground_color="#74776b")
    b.data["environment"]["time_of_day"] = "dim"
    b.room("apron", 170, 164, 320, 112, label="야간 계류장 · 실제 크기 수송기", indoor=False)
    _box(b, "old_terminal_hall", 250, 83, 52, 26, "구터미널 대합실", south=True,
         north=True, west=True, east=True, door_width=2.2, height=3.5)
    _suite(b, "terminal_service", 250, 55, 52, 24, 4, 2,
           ("수하물", "사무실", "통신실", "문서실", "보안실", "직원 휴게실", "의료 구역", "물품창고"), 3.2)
    _background(b, "old_terminal_facade", "terminal", 317, 55, 56.28, 22.326, 6.8)
    b.scenery("transport_transport_turboprop", "transport_turboprop", 83, 168, rotation=math.pi)
    b.scenery("escort_utility_vehicle_1", "utility_vehicle", 182, 138)
    b.scenery("escort_utility_vehicle_2", "utility_vehicle", 190, 144)
    b.prop("black_sedan", "vehicle", 169, 143, 4.8, 1.8, height=1.5, cover="full")
    # Sparse apron equipment creates readable lanes rather than a crate maze.
    for i, x in enumerate([204, 225, 248, 272]):
        b.prop(f"terminal_column_{i}", "pillar", x, 103, .6, .6, height=3.5)
    _furniture(b, "terminal_objects", [("chair", 230, 87, .55, .55), ("chair", 234, 87, .55, .55),
                                      ("sofa", 240, 73, 2.2, .8), ("desk", 260, 73, 1.6, .7),
                                      ("crate", 207, 135, 2.5, 1.1), ("crate", 292, 114, 1.8, 1.1),
                                      ("cabinet", 232, 51, 1.6, .7)])
    for i, (x, z) in enumerate([(292, 68), (300, 87), (304, 115), (220, 30), (196, 73)]):
        b.scenery(f"terminal_tree_{i}", "palm", x, z, scale=.9 + i * .06)
    b.squad(106, 172)
    _actors(b, [(187, 124), (217, 91), (237, 83), (263, 82), (244, 55), (269, 49), (281, 116)],
            [(232, 78), (241, 91), (261, 87), (254, 74), (256, 61), (269, 58)])
    return _finish(b, ["계류장에서 구터미널의 여러 구획으로 이동하세요.", "인질을 확인하고 수송기 이송 공간을 확보하세요."], (226, 108))


def quiet_lantern():
    b = MapBuilder("H03", '콰이어트 랜턴', (42, 40),  ground_color="#686765")
    b.data["revision"] = 2
    b.data["description"] = "진입 직전의 인도에서 시작합니다. 폭 1.8m 복도와 생활 크기의 업무실을 확인하고 위협 5명을 무력화하며 민간인 4명을 확보하세요. 뒤뜰과 동쪽 통로로 후문에도 접근할 수 있습니다."
    b.data["briefing"].update(estimated_minutes="3–6", tip="전면 출입문과 동쪽 통로의 후문이 연결됩니다. 좁은 복도에서는 한 명씩 통과시키고 방 안의 민간인을 확보하세요.")
    b.room("consulate_lane", 21, 36.5, 42, 7, label="Consulate Lane 도로", indoor=False)
    b.room("front_pavement", 21, 32, 42, 2, label="진입 대기 인도", indoor=False)
    b.room("front_forecourt", 21, 30, 10.4, 2, label="전면 출입 공간", indoor=False)
    b.room("rear_garden", 21, 4.5, 9.6, 5, label="후면 정원", indoor=False)
    b.room("side_passage", 27.4, 16.5, 2.8, 29, label="동쪽 후문 연결 통로", indoor=False)
    # A 9.6 × 22 m interpreted ground floor; no neighbouring house interiors.
    _perimeter(b, "embassy", 21, 18, 9.6, 22, south=[(21, 1.05)],
               north=[(21, 1.05)], height=3.1, material="masonry")
    b.room("embassy_hall", 21, 16.5, 1.8, 19, label="중앙 복도 · 폭 1.8m", floor_surface="wood")
    b.room("embassy_vestibule", 21, 27.5, 1.8, 3, label="현관 전실", floor_surface="tile")
    bays = [(7, 13.5, "후면 지원실", "후면 업무실"),
            (13.5, 19, "직원 휴게실", "소회의실"),
            (19, 23.5, "비자 사무실", "자료실"),
            (23.5, 29, "접수실", "방문객 대기실")]
    for side, cx, wall_x, name_index in [("west", 18.15, 20.1, 2), ("east", 23.85, 21.9, 3)]:
        openings = [(10.25, .95), (16.25, .95), (21.25, .95), (27.3, .95)]
        if side == "west": openings[:1] = [(8.5, .95), (11.75, .95)]
        _wall_with_openings(b, f"hall_{side}", "z", wall_x, 7, 29, openings)
        if side == "east":
            for door in b.data["doors"]:
                if door["id"].startswith("hall_east_"): door["swing_sign"] = 1
        for i, bay in enumerate(bays):
            lo, hi = bay[:2]
            if side == "west" and i == 0:
                b.room("embassy_store", cx, 8.5, 3.9, 3, label="비품·수납실", floor_surface="tile")
                b.room("embassy_washroom", cx, 11.75, 3.9, 3.5, label="세면·설비실", floor_surface="tile")
                b.wall("west_service_partition", cx, 10, 3.9, .2, material="plaster")
            else:
                b.room(f"embassy_{side}_{i}", cx, (lo + hi) / 2, 3.9, hi - lo,
                       label=bay[name_index], floor_surface="wood")
            if i: b.wall(f"{side}_partition_{i}", cx, lo, 3.9, .2, material="plaster")
    for i, x in enumerate([11.2, 33.8]):
        b.scenery(f"adjoining_terrace_{i}", "terrace_townhouse", x, 18).update(cutaway=False)
        b.wall(f"adjoining_terrace_{i}_collision", x, 18, 9.8, 22.2, height=14.4, render=False)
    b.scenery("embassy_upper_floors", "terrace_townhouse", 21, 18)
    _wall_with_openings(b, "front_railing", "x", 31, 15.8, 26.2, [(21, 1.2)], 1.05, "metal")
    for door, label in zip(b.data["doors"], ["후문", "현관", "비품실", "세면실", "휴게실", "비자실", "접수실", "후면 업무실", "회의실", "자료실", "대기실", "철문"]):
        door["label"] = label
    _furniture(b, "embassy_objects", [
        ("desk", 17.4, 25.1, 1.4, .7), ("chair", 17.4, 24.3, .5, .5),
        ("cabinet", 16.8, 28, .5, 1.1), ("sofa", 24.8, 25.2, .85, 2.1),
        ("table", 23.4, 24.4, 1.1, .6), ("chair", 23.2, 28.1, .5, .5),
        ("desk", 17.3, 20.2, 1.4, .7), ("chair", 17.3, 21, .5, .5),
        ("bookshelf", 16.7, 22.4, .4, 1.2), ("cabinet", 25.2, 20.1, .5, 1.2),
        ("bookshelf", 23, 19.5, 1.2, .4), ("desk", 23, 22.7, 1.4, .7),
        ("sofa", 16.9, 15.7, .85, 2.1), ("table", 18, 14.4, 1.2, .7),
        ("cabinet", 16.8, 18.1, 1.1, .5), ("table", 23.8, 16.2, 1.8, .85),
        ("chair", 23, 15.2, .5, .5), ("chair", 24.6, 17.2, .5, .5),
        ("cabinet", 25.2, 18, .5, 1.1), ("cabinet", 16.8, 8.4, .5, 1.2),
        ("bookshelf", 18.3, 7.6, 1.2, .4), ("cabinet", 17.2, 12.6, 1.1, .5),
        ("desk", 23.8, 8.2, 1.4, .7), ("chair", 23.8, 9, .5, .5),
        ("bookshelf", 25.2, 12.2, .4, 1.2), ("plant", 25.1, 28.1, .45, .45)])
    b.prop("police_vehicle", "vehicle", 8, 36.2, 4.4, 1.8, height=1.5, cover="full")
    b.squad(20.1, 33.8)
    for unit in b.data["units"]: unit["facing"] = -math.pi / 2
    _actors(b, [(18.8, 26.8), (23.2, 20.9), (18.6, 17.7), (23.5, 11.3), (21, 14.4)],
            [(23.1, 26.5), (18.8, 22.4), (23.9, 18.1), (18.8, 8.5)])
    result = _finish(b, ["전면 현관 또는 동쪽 통로의 후문으로 대사관 지상층을 확인하세요.",
                         "모든 위협을 처리하고 민간인 4명을 확보하세요."], (21, 21))
    result["historical"]["accuracy_note"] = '가상의 작전 구역입니다. 실내·객실·문은 사람 크기에 맞춰 설계했으며 지상층에서 목표를 수행합니다.'
    result["historical"]["landmarks"] = ["흰 스터코 연립 외관", "현관 전실", "중앙 복도", "전면 철제 난간", "동쪽 통로와 뒤뜰"]
    return result


def _aircraft_map(mid, title, bounds, center, length, width,
                  asset, rows, left_seats, right_seats, biome="airport"):
    b = MapBuilder(mid, title, bounds,  biome=biome,
                   ground_color="#636d73" if mid != "H07" else "#a09b8f")
    x, z = center
    b.scenery("historical_airframe", asset, x, z)
    b.room("apron", bounds[0] / 2, bounds[1] / 2, bounds[0] - 6, bounds[1] - 6,
           label="지상 계류장 · 이동 계단", indoor=False)
    # Usable cabin, cockpit and galley together remain inside the real fuselage.
    cabin_length = length - 5.4
    x0, x1 = x - cabin_length / 2, x + cabin_length / 2
    _perimeter(b, "cabin", x, z, cabin_length, width,
               south=[(x0 + 1.5, 1.02), (x1 - 1.5, 1.02)], height=2.1, material="metal")
    # Registry +X is the nose, so the forward galley is at the high-X end.
    b.room("front_galley", x1 - 1.8, z, 3.6, width, label="전방 갤리·출입구")
    b.room("rear_galley", x0 + 1.8, z, 3.6, width, label="후방 갤리·출입구")
    b.room("passenger_cabin", x, z, cabin_length - 7.2, width, label=f"{width:.2f}m 객실 · 단일 통로")
    aisle = .55
    seat_width = .43  # 17-inch seat width; human proportions remain intact.
    aisle_z = z - (right_seats - left_seats) * seat_width / 2
    seat_pitch = .80
    max_rows = int((cabin_length - 7.2) / seat_pitch)
    rows = min(rows, max_rows)
    start_x = x - (rows - 1) * seat_pitch / 2
    # Seats are paired/three-abreast banks around a continuous 0.55 m route.
    for i in range(rows):
        sx = start_x + i * seat_pitch
        for side, count in [(-1, left_seats), (1, right_seats)]:
            for j in range(count):
                sz = aisle_z + side * (aisle / 2 + seat_width * (j + .5))
                b.prop(f"seat_{i}_{side}_{j}", "chair", sx, sz, .48, seat_width,
                       height=.95, rotation=0, cover="low")
    b.prop("galley_forward", "cabinet", x1 - .65, z - .7, .8, .75, height=1.3)
    b.prop("galley_aft", "cabinet", x0 + .6, z - .7, .75, .75, height=1.3)
    for i, gx in enumerate([x0 + 1.5, x1 - 1.5]):
        b.room(f"boarding_step_{i}", gx, z + 3.3, 1.1, 3.4,
               label="지상과 객실 연결 · 높이 전환 각색", indoor=False)
    b.squad(22, bounds[1] - 19)
    _actors(b, [(x0 + 2, aisle_z), (x + 3.2, aisle_z), (x1 - 2, aisle_z)],
            [(x - 5.5, aisle_z), (x - 1.5, aisle_z), (x + 1.3, aisle_z), (x + 6.5, aisle_z)])
    b.scenery("cargo_apron_truck", "truck", bounds[0] - 21, bounds[1] - 23)
    b.prop("baggage_cart_1", "crate", x - 17, z + 18, 1.8, 1.0, height=.55)
    b.prop("baggage_cart_2", "crate", x + 18, z + 17, 1.8, 1.0, height=.55)
    b.scenery("remote_hangar", "hangar", bounds[0] - 28, 15, scale=.65)
    # The grounded airframe's cabin floor sits above its landing gear. Keep
    # that real vertical relation in the renderer while retaining one X/Z
    # navigation layer. Apron and boarding-approach rooms stay at ground level.
    cabin_base = 2.145 if asset == "airliner_reartwin" else 2.022
    for room in b.data["rooms"]:
        if room.get("indoor", True):
            room["base_height"] = cabin_base
    for group in ["walls", "doors", "props"]:
        for item in b.data[group]:
            if (x0 - .15 <= item["x"] <= x1 + .15
                    and z - width / 2 - .15 <= item["z"] <= z + width / 2 + .15):
                item["base_height"] = cabin_base
    b.data["historical"]["accuracy_note"] += f" 객실 바닥은 지상 기준 {cabin_base + .2:.3f}m에 배치하여 착륙장치 높이와 사람 크기를 유지합니다. 지상→객실 연결은 단일 X/Z 이동층의 시각 높이 전환으로 각색했습니다. 좌석·벽·문은 같은 객실 바닥 높이를 사용합니다."
    return b


def iron_vesper():
    b = _aircraft_map("H04", '아이언 베스퍼',
                      (140, 100), (70, 40.125), 30.53, 3.54, "airliner_twinjet", 23, 3, 3)
    b.data["environment"]["time_of_day"] = "dim"
    return _finish(b, ["야간 계류장의 실제 크기 쌍발 여객기 객실로 이동하세요.", "좌석 구역에서 승객을 구분하고 보호하세요."], (70, 48),
                   {"airframe_length": 30.53, "cabin_width": 3.54, "seat_width": .43, "aisle_width": .55})


def cold_runway():
    b = _aircraft_map("H06", '콜드 런웨이',
                      (170, 110), (82, 42.34), 36.37, 3.1, "airliner_reartwin", 29, 2, 3)
    b.data["environment"]["time_of_day"] = "dim"
    b.scenery("cargo_shed", "hangar", 32, 21, scale=.6)
    return _finish(b, ["화물구역에서 후방 쌍발 여객기의 좁은 객실로 이동하세요.", "승객과 승무원을 확인하고 안전한 출입로를 확보하세요."], (82, 51),
                   {"airframe_length": 36.37, "cabin_width": 3.1})


def white_gantry():
    b = _aircraft_map("H07", '화이트 갠트리',
                      (190, 140), (95, 65.125), 46.61, 3.55, "airliner_quadjet", 40, 3, 3)
    b.data["environment"]["time_of_day"] = "day"
    return _finish(b, ["주간 계류장에서 4발 여객기를 확인하세요.", "긴 객실의 여러 승객 구역을 확보하세요."], (95, 76),
                   {"airframe_length": 46.61, "cabin_width": 3.55})


def river_ash():
    b = MapBuilder("H09", '리버 애시', (320, 220),  biome="jungle", ground_color="#365b4b")
    b.land("village_riverbank", 160, 146, 308, 136)
    b.land("north_bank_background_bank", 160, 17, 308, 34)
    b.data["historical"]["accuracy_note"] += " 브레스크 개울의 43m 폭 대표 수로가 두 강둑을 분리합니다. 북쪽 마을은 연결하지 않은 배경이며 자유 수영으로 강을 건너지는 않습니다. 수로 폭은 실측이 아닌 공간 설계입니다."
    b.room("mud_track", 162, 142, 280, 9, label="붉은 흙 마을 이동로", indoor=False)
    huts = [(90, 142, 7, 9), (114, 174, 8, 8), (136, 119, 9, 7),
            (181, 153, 8, 9), (217, 112, 10, 8), (245, 144, 8, 9), (263, 99, 10, 9)]
    for i, (x, z, w, d) in enumerate(huts):
        _box(b, f"village_hut_{i}", x, z, w, d,
             "인질 체류 오두막" if i == 4 else "마을 오두막", south=True, north=(i % 2 == 0), height=2.6)
        b.scenery(f"hut_shell_{i}", "hut", x, z, scale=.8 if w < 9 else 1)
        b.prop(f"hut_living_prop_{i}", "bed" if i % 2 else "table", x - 1.8, z - 2,
               1 if i % 2 else 1.5, 2 if i % 2 else .8)
    # Trees frame paths; vegetation is never filled with full-height collision boxes.
    for i in range(40):
        x = 18 + (i * 37) % 283
        z = 84 + (i * 29) % 122
        if any(abs(x - hx) < hw / 2 + 5 and abs(z - hz) < hd / 2 + 5 for hx, hz, hw, hd in huts):
            continue
        if abs(z - 142) < 8:
            continue
        b.scenery(f"river_forest_{i}", "palm", x, z, rotation=i * .43, scale=.8 + (i % 5) * .13)
        if i % 3 == 0:
            b.scenery(f"river_shrub_{i}", "bush", x + 2, z + 2, scale=1.1)
    for i, x in enumerate([95, 153, 207]):
        b.scenery(f"north_bank_background_{i}", "hut", x, 20, scale=.85)
    b.scenery("river_ash_naval", "naval", 42, 187)
    b.scenery("captured_land_rover", "utility_vehicle", 202, 180)
    b.prop("landing_supply", "crate", 46, 170, 1.5, 1, height=.6)
    b.squad(45, 190)
    _actors(b, [(92, 143), (117, 174), (141, 130), (176, 143), (217, 109), (246, 148), (270, 116), (193, 170)],
            [(217, 114), (263, 101), (180, 156), (244.8, 146)])
    return _finish(b, ["정글 가장자리에서 켈브리스 마을의 오두막 군으로 이동하세요.", "억류 인원과 차량 주변의 안전한 회수 공간을 확보하세요."], (165, 139))


def night_ledger():
    b = MapBuilder("H11", '나이트 레저', (180, 160),  ground_color="#948f75")
    b.room("unpaved_access_road", 58, 123, 90, 8, label="좁은 비포장 진입도로", indoor=False)
    _perimeter(b, "compound_boundary", 102, 74, 84, 82,
               south=[(89, 2.8)], west=[(100, 1.2)], height=4.5)
    # The exterior gate is shared with the boundary, rather than duplicated.
    b.room("security_entrance", 89, 109, 12, 12, label="두 출입문 사이의 공간", indoor=False)
    _wall_with_openings(b, "security_entrance_n", "x", 103, 83, 95, [(89, 2.8)], 3.8)
    _wall_with_openings(b, "security_entrance_w", "z", 83, 103, 115, (), 3.8)
    _wall_with_openings(b, "security_entrance_e", "z", 95, 103, 115, (), 3.8)
    b.room("outer_courtyard", 104, 90, 70, 35, label="외부 마당", indoor=False)
    _wall_with_openings(b, "internal_division", "x", 73, 60, 144, [(85, 1.2)], 3.3)
    _suite(b, "main_house_ground", 113, 51, 24, 22, 3, 1.8,
           ("주방", "생활실", "저장실", "침실", "업무실", "가족 생활실"), 3.1)
    _box(b, "guest_house", 78, 49, 14, 16, "별채·생활 구역", south=True, east=True, height=2.8)
    _background(b, "compound_three_storey_shell", "compound", 159, 134, 28.3, 19, 8.6)
    b.scenery("adjacent_home_1", "townhouse", 34, 53)
    b.scenery("adjacent_home_2", "townhouse", 160, 58)
    b.prop("household_vehicle", "vehicle", 133, 96, 4.2, 1.75, height=1.5, cover="full")
    _furniture(b, "household_objects", [("table", 105, 44, 1.7, .8), ("sofa", 112, 45, 2.1, .85),
                                       ("cabinet", 123, 44, 1.5, .65), ("bed", 105, 58, 1.4, 2),
                                       ("desk", 112, 57, 1.4, .7), ("bed", 120, 58, 1.4, 2),
                                       ("table", 74, 45, 1.4, .7), ("bed", 81, 47, 1, 2)])
    for i, (x, z) in enumerate([(66, 86), (132, 82), (70, 69), (98, 37), (158, 123)]):
        b.scenery(f"compound_bush_{i}", "bush", x, z, scale=1.0 + .12 * i)
    b.squad(29, 129)
    _actors(b, [(97, 103), (128, 87), (85, 70), (113, 51), (122, 57), (79, 49)],
            [(105, 56), (113, 44), (123, 46), (74, 51)])
    result = _finish(b, ["이중 출입 공간과 높은 외벽 안의 구획을 확인하세요.", "생활 공간에서 비전투원을 보호하고 현장을 확보하세요."], (101, 79))
    result["historical"]["verified_dimensions_m"] = {"outer_wall_height_range": [3.66, 5.49]}
    return result


def build_maps():
    return [salt_meridian(), glass_horizon(), quiet_lantern(), iron_vesper(), cold_runway(), white_gantry(), river_ash(), night_ledger()]
