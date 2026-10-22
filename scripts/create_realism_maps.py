#!/usr/bin/env python3
"""Author connected, bounded floor plans and enrich physical map metadata.

No random geometry: seed variants only select explicit, validated actor/door
choices. Run validate_missions.py after authoring to check the real navigation.
"""
from __future__ import annotations

import copy
import json
from mission_authoring import preserve_enemy_strengths
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "game/data"
HEIGHTS = {"table": .74, "desk": .74, "sofa": .86, "bed": .77,
           "cabinet": 1.3, "bookshelf": 1.3, "plant": 1.1,
           "chair": .92, "crate": .68, "rug": .025,
           "vehicle": 1.65, "pillar": 2.8}
MATERIALS = {"table": "wood", "desk": "wood", "sofa": "fabric",
             "bed": "fabric", "cabinet": "wood", "bookshelf": "wood",
             "plant": "foliage", "chair": "fabric", "crate": "wood",
             "rug": "fabric", "vehicle": "metal", "pillar": "concrete"}
MAGAZINES = {"standard": 24, "light": 32, "shotgun": 8, "suppressed": 18}


def write(name, data):
    path = DATA / f"{name}.json"
    preserve_enemy_strengths(data, path)
    text = json.dumps(data, ensure_ascii=False, indent=2) + "\n"
    if not path.exists() or path.read_text() != text:
        path.write_text(text)


def door(mid, number, axis, c, at, state="CLOSED", locked=False):
    return dict(id=f"{mid}_d{number}", x=at if axis == "x" else c,
                z=c if axis == "x" else at,
                w=1.8 if axis == "x" else .24,
                d=.24 if axis == "x" else 1.8, axis=axis,
                state=state, label=f"D{number:02}", hinge_side=-1.0,
                swing_sign=-1.0, locked=locked, hp=100, destroyed=False,
                height=2.1, material="wood")


def floors(mid, rects, doors, open_edges=()):
    """Merge room boundaries while keeping deliberate wide archways open."""
    rooms = []
    edges = {}
    for index, (label, x1, z1, x2, z2, indoor, light, surface) in enumerate(rects):
        rooms.append(dict(id=f"{mid}_r{index + 1}", label=label,
                          x=(x1 + x2) / 2, z=(z1 + z2) / 2,
                          w=x2 - x1, d=z2 - z1,
                          color=("#626d64" if not indoor else
                                 ["#74766d", "#65756c", "#82796c"][index % 3]),
                          indoor=indoor, lighting=light, floor_surface=surface))
        for axis, c, lo, hi in [("x", z1, x1, x2), ("x", z2, x1, x2),
                                ("z", x1, z1, z2), ("z", x2, z1, z2)]:
            edges.setdefault((axis, c), []).append((lo, hi))
    gaps = [(d["axis"], d["z"] if d["axis"] == "x" else d["x"],
             (d["x"] if d["axis"] == "x" else d["z"]) - .9,
             (d["x"] if d["axis"] == "x" else d["z"]) + .9) for d in doors]
    gaps.extend(open_edges)
    walls = []
    for (axis, c), ranges in edges.items():
        marks = sorted({v for pair in ranges for v in pair} |
                       {v for a, b, lo, hi in gaps if a == axis and b == c for v in [lo, hi]})
        for lo, hi in zip(marks, marks[1:]):
            m = (lo + hi) / 2
            if not any(a <= m <= b for a, b in ranges):
                continue
            if any(a == axis and b == c and low < m < high for a, b, low, high in gaps):
                continue
            walls.append(dict(id=f"{mid}_w{len(walls) + 1}",
                              x=m if axis == "x" else c,
                              z=c if axis == "x" else m,
                              w=round(hi - lo, 4) if axis == "x" else .24,
                              d=.24 if axis == "x" else round(hi - lo, 4),
                              height=2.8, material="concrete"))
    return rooms, walls


def actors(mid, placements):
    result = []
    for index, (x, z, role, alternate, patrol) in enumerate(placements):
        actor = dict(id=f"{mid}_e{index + 1}",
                     name={"guard": "경비", "reserve": "지원 인원", "patrol": "순찰 인원"}[role],
                     x=x, z=z, facing=math.pi / 2, weapon="light",
                     reserve_ammo=96, stance="standing", movement_mode="normal",
                     enemy_type="normal", response_role=role)
        if patrol:
            actor["patrol"] = copy.deepcopy(patrol)
        # Each choice is an actual different floor position, not a facing-only alias.
        actor["spawns"] = [dict(x=x, z=z, facing=math.pi / 2, patrol=copy.deepcopy(patrol)),
                           dict(x=alternate[0], z=alternate[1], facing=0, patrol=copy.deepcopy(patrol))]
        result.append(actor)
    return result


def props(mid, placements):
    result = []
    for i, (kind, x, z, w, d) in enumerate(placements):
        result.append(dict(id=f"{mid}_p{i + 1}", type=kind, x=x, z=z, w=w, d=d,
                           rotation=0, height=HEIGHTS[kind], material=MATERIALS[kind],
                           cover="full" if kind in ["cabinet", "bookshelf", "pillar", "vehicle"] else
                                 ("none" if kind in ["plant", "chair", "rug"] else "low")))
    return result


def operation(mid, name, title, english, description, description_en, rects,
              doors, open_edges, placements, civilians, furniture, win, environment, tip):
    rooms, walls = floors(mid, rects, doors, open_edges)
    units = [dict(id=uid, name=uid.upper(), role="operator", x=x, z=29,
                  facing=-math.pi / 2, weapon=weapon,
                  reserve_ammo=MAGAZINES[weapon] * 3, stance="standing", movement_mode="normal",
                  stuns=2, smokes=1, breaches=1)
             for uid, x, weapon in [("alpha", 13.5, "standard"), ("bravo", 15, "light"),
                                    ("charlie", 16.5, "standard"), ("delta", 18, "shotgun")]]
    data = dict(schema_version=1, id=mid, revision=1, title=title, title_en=english,
                subtitle=english.upper(), description=description, description_en=description_en,
                seed=int(mid[1:]) * 1021, default_seed=int(mid[1:]) * 1021,
                bounds=[32, 32], focus=[16, 15], rooms=rooms, walls=walls,
                doors=doors, props=props(mid, furniture), units=units,
                enemies=actors(mid, placements),
                civilians=[dict(id=f"{mid}_c{i + 1}", name="민간인", x=x, z=z)
                           for i, (x, z) in enumerate(civilians)],
                objectives=[description], win=win, fail=[dict(type="no_civilian_loss")],
                variant="normal", modifiers=[], environment=environment,
                briefing=dict(difficulty="보통", estimated_minutes="5–12",
                              threat="분산 경비 · 순찰 · 지원", tip=tip),
                stars=[dict(id="complete", label="임무 완료", stat="command_failures", op="eq", value=0),
                       dict(id="survival", label="전원 생존", stat="losses", op="eq", value=0),
                       dict(id="par_time", label="240초 이내", stat="time", op="lte", value=240)])
    write(name, data)


def new_operations():
    garage_doors = [door("M07", i + 1, *v) for i, v in enumerate([
        ("x", 8, 5.5), ("x", 8, 13.5), ("x", 8, 24),
        ("z", 9, 5), ("z", 18, 5), ("x", 27, 8), ("x", 27, 25), ("z", 2, 15)])]
    for i in [0, 1, 3, 4]:
        garage_doors[i]["initial_states"] = ["CLOSED", "OPEN"]
    garage_doors[2]["locked"] = True  # Maintenance room also connects through security.
    operation("M07", "garage", "지하주차장", "Underground Garage",
              "차량과 기둥으로 나뉜 주차 구역 및 관리실의 위협을 처리하고 민간인 2명을 확보하세요. 남쪽 두 출입구와 서쪽 서비스문이 연결됩니다.",
              "Clear the parking lanes and service rooms, then secure both civilians. Two southern entrances and a western service door link through the open garage.",
              [("01 / STAIR LOBBY", 2, 2, 9, 8, True, .85, "tile"),
               ("02 / SECURITY", 9, 2, 18, 8, True, 1, "tile"),
               ("03 / MAINTENANCE", 18, 2, 30, 8, True, .9, "concrete"),
               ("04 / WEST PARKING", 2, 8, 16, 22, True, .75, "concrete"),
               ("05 / EAST PARKING", 16, 8, 30, 22, True, .85, "concrete"),
               ("06 / WEST RAMP", 2, 22, 16, 27, True, .95, "concrete"),
               ("07 / EAST RAMP", 16, 22, 30, 27, True, .95, "concrete")],
              garage_doors, [("z", 16, 8, 27), ("x", 22, 2, 30)],
              [(5, 5, "guard", (6.5, 5), []), (14, 5, "reserve", (15.5, 5), []),
               (23, 5, "guard", (25, 5), []), (11, 12, "guard", (12, 12), []),
               (20, 12, "patrol", (20, 13), [[20, 12], [20, 18], [26, 18]]),
               (11, 19, "reserve", (12, 19), []), (26, 12, "guard", (27, 12), []),
               (18, 24, "patrol", (20, 24), [[18, 24], [25, 24], [25, 18]])],
              [(4, 3.5), (28, 4)],
              [("vehicle", 6, 13, 2, 4.2), ("vehicle", 6, 19, 2, 4.2),
               ("vehicle", 15, 12, 2, 4.2), ("vehicle", 15, 19, 2, 4.2),
               ("vehicle", 24, 13, 2, 4.2), ("pillar", 9, 15.5, .8, .8),
               ("pillar", 18, 15.5, .8, .8), ("pillar", 27, 15.5, .8, .8),
               ("desk", 12, 3.5, 2, 1), ("cabinet", 17, 3.5, 1, 1),
               ("crate", 21, 3.5, 2, 1), ("table", 26, 6.5, 2, 1)],
              [dict(type="neutralize_all"), dict(type="secure_all_civilians")],
              dict(time_of_day="dim", lighting=.75),
              "차량 사이와 관리실은 서로 다른 시야 구조입니다. 잠긴 정비실 문에는 관리실을 통한 우회 연결도 있습니다.")

    shop_doors = [door("M08", i + 1, *v) for i, v in enumerate([
        ("z", 12, 7), ("z", 12, 15), ("z", 12, 23),
        ("z", 18, 7), ("z", 18, 15), ("z", 18, 23),
        ("x", 11, 7), ("x", 19, 7), ("x", 11, 24), ("x", 19, 24),
        ("x", 27, 15), ("z", 2, 23), ("z", 30, 15)])]
    for i in [0, 1, 3, 4, 6, 8]:
        shop_doors[i]["initial_states"] = ["CLOSED", "OPEN"]
    shop_doors[5]["locked"] = True  # Workshop has a route through the adjoining pharmacy.
    operation("M08", "shops", "연결 상가", "Linked Shops",
              "공용 복도와 점포 사이의 연결문을 이용해 직원 2명을 확보한 뒤 남쪽 집결 구역까지 호송하세요. 점포마다 가구와 조명이 다릅니다.",
              "Use the common passage and linked shop interiors to secure both staff members, then escort them to the southern extraction area. Each shop has its own furniture and lighting.",
              [("01 / BOOKSHOP", 2, 3, 12, 11, True, .95, "wood"),
               ("02 / CAFE", 2, 11, 12, 19, True, .85, "tile"),
               ("03 / STOCKROOM", 2, 19, 12, 27, True, .65, "concrete"),
               ("04 / COMMON PASSAGE", 12, 3, 18, 27, True, 1, "tile"),
               ("05 / PHARMACY", 18, 3, 30, 11, True, 1, "tile"),
               ("06 / REPAIR SHOP", 18, 11, 30, 19, True, .85, "concrete"),
               ("07 / WORKSHOP", 18, 19, 30, 27, True, .75, "concrete")],
              shop_doors, [],
              [(7, 7, "guard", (8.5, 7), []), (8, 15, "reserve", (8, 16), []),
               (7, 23, "guard", (8, 23), []), (15, 18, "patrol", (15, 16), [[15, 18], [15, 6]]),
               (24, 7, "guard", (25.5, 7), []), (27, 15, "reserve", (27, 16), []),
               (22, 23, "patrol", (22, 24), [[22, 23], [24, 23], [24, 15]]),
               (15, 8, "guard", (15, 10), [])],
              [(4, 9), (28, 4.5)],
              [("bookshelf", 4, 5.5, 1, 3), ("bookshelf", 10.5, 5.5, 1, 3),
               ("desk", 8, 9, 2, 1), ("table", 5, 14, 2, 1),
               ("table", 5, 17, 2, 1), ("crate", 4, 24, 1.8, 2),
               ("crate", 10, 21, 1.5, 1.5), ("cabinet", 20, 5.5, 1, 3),
               ("desk", 24, 9, 3, 1), ("table", 21, 14, 2, 1),
               ("cabinet", 29, 17, 1, 1.5), ("crate", 28, 24, 2, 2),
               ("table", 25, 21, 2, 1)],
              [dict(type="escort_to_zone", zone=[15, 29.5, 8, 3])],
              dict(time_of_day="dim", lighting=.7),
              "공용 복도에만 의존하지 않아도 됩니다. 연결된 점포를 통과하는 경로와 서비스 출입구를 확인하세요.")

    court_doors = [door("M09", i + 1, *v) for i, v in enumerate([
        ("z", 10, 6), ("z", 22, 6), ("z", 10, 14), ("z", 22, 14),
        ("z", 10, 23), ("z", 22, 23), ("x", 9, 6), ("x", 19, 6),
        ("x", 9, 26), ("x", 19, 26), ("x", 9, 16), ("x", 19, 16),
        ("x", 27, 16), ("z", 2, 14), ("z", 30, 23), ("x", 2, 16)])]
    for i in [0, 1, 2, 3, 4, 5]:
        court_doors[i]["initial_states"] = ["CLOSED", "OPEN"]
    operation("M09", "courtyard", "중정의 건물", "Courtyard Block",
              "실내 구역과 열린 중정의 위협을 처리하고 민간인을 확보한 뒤 북쪽 관리실의 지정 구역에 도달하세요. 양쪽 건물과 중정이 여러 경로로 연결됩니다.",
              "Clear the indoor wings and open courtyard, secure the civilian, then reach the marked zone in the northern administration room. Both wings connect through several indoor and outdoor routes.",
              [("01 / WEST OFFICE", 2, 2, 10, 9, True, .9, "wood"),
               ("02 / ADMINISTRATION", 10, 2, 22, 9, True, 1, "tile"),
               ("03 / EAST OFFICE", 22, 2, 30, 9, True, .95, "wood"),
               ("04 / WEST GALLERY", 2, 9, 10, 19, True, .75, "tile"),
               ("05 / COURTYARD", 10, 9, 22, 19, False, 1, "gravel"),
               ("06 / EAST GALLERY", 22, 9, 30, 19, True, .75, "tile"),
               ("07 / WEST SERVICE", 2, 19, 10, 27, True, .85, "concrete"),
               ("08 / ENTRANCE HALL", 10, 19, 22, 27, True, 1, "tile"),
               ("09 / EAST LOUNGE", 22, 19, 30, 27, True, .9, "carpet")],
              court_doors, [],
              [(6, 6, "guard", (7, 6), []), (16, 6, "reserve", (18, 6), []),
               (26, 6, "guard", (27, 6), []), (6, 14, "patrol", (6, 15), [[6, 14], [6, 10], [6, 6]]),
               (18, 14, "guard", (19, 14), []), (26, 14, "patrol", (26, 15), [[26, 14], [26, 18], [26, 23]]),
               (6, 23, "reserve", (7, 23), []), (16, 23, "guard", (18, 23), []),
               (26, 23, "guard", (27, 23), [])],
              [(28, 4)],
              [("desk", 4, 4, 2, 1), ("cabinet", 8.8, 4, 1, 2),
               ("table", 13, 4, 2, 1), ("cabinet", 20, 4, 1, 2),
               ("desk", 24, 4, 2, 1), ("table", 4, 16, 2, 1),
               ("pillar", 12.5, 11.5, .7, .7), ("pillar", 19.5, 11.5, .7, .7),
               ("pillar", 12.5, 16.5, .7, .7), ("pillar", 19.5, 16.5, .7, .7),
               ("plant", 16, 14, 1.8, 1.8), ("table", 28, 17, 2, 1),
               ("crate", 4, 25, 2, 1), ("cabinet", 8, 25, 1, 1),
               ("desk", 13, 25, 2, 1), ("sofa", 28, 25, 2, 1)],
              [dict(type="neutralize_all"), dict(type="secure_all_civilians"),
               dict(type="reach_zone", zone=[16, 4, 3, 2])],
              dict(time_of_day="day", lighting=1),
              "중정은 밝은 실외 공간이며 주변 실내는 조명이 다릅니다. 동서 연결문과 외곽 서비스 출입구가 있습니다.")


def split_for_door(data, identifier, axis, c, at):
    if any(d["id"] == identifier for d in data["doors"]):
        return
    selected = None
    for wall in data["walls"]:
        wall_c = wall["z"] if axis == "x" else wall["x"]
        center = wall["x"] if axis == "x" else wall["z"]
        span = wall["w"] if axis == "x" else wall["d"]
        if abs(wall_c - c) < 1e-6 and center - span / 2 < at - .9 and at + .9 < center + span / 2:
            selected = wall
            break
    if selected is None:
        raise ValueError(f"{data['id']}: no wall span for service door {identifier}")
    center = selected["x"] if axis == "x" else selected["z"]
    span = selected["w"] if axis == "x" else selected["d"]
    data["walls"].remove(selected)
    for index, (lo, hi) in enumerate([(center - span / 2, at - .9), (at + .9, center + span / 2)]):
        piece = copy.deepcopy(selected)
        piece["id"] = selected["id"] + f"_service{index + 1}"
        piece["x" if axis == "x" else "z"] = (lo + hi) / 2
        piece["w" if axis == "x" else "d"] = hi - lo
        data["walls"].append(piece)
    value = door(data["id"], len(data["doors"]) + 1, axis, c, at)
    value["id"] = identifier
    data["doors"].append(value)


def enrich_existing():
    env = {"M04": ("night", .55), "M06": ("dim", .7)}
    service = {"M01": ("service_east", "z", 21, 14),
               "M02": ("service_north", "x", 3, 19.5),
               "M03": ("service_west", "z", 3, 4.5),
               "M04": ("M04_guest_link", "z", 16, 8),
               "M05": ("M05_service_north", "x", 3, 13)}
    alternatives = {
        "M04": [(8,8),(14,7),(20,8),(26,8),(10.5,14),(24.5,19),(9.5,20),(17.5,20)],
        "M05": [(7,6),(8,15),(8,23),(13,18),(18,7),(27,7),(19,15),(25,15),(26,22)],
        "M06": [(7.5,5),(15.5,5),(21,5),(28,5),(6,13.5),(16,13.5),(21,18),(27,15),(8,23),(25,24)],
    }
    route_hints = {
        "M01": ("동쪽 서비스 출입구도 내부와 연결됩니다.", "The eastern service entrance also connects to the interior."),
        "M02": ("북쪽 직원 출입구를 통한 다른 경로가 있습니다.", "A northern staff entrance provides another route."),
        "M03": ("서쪽 서비스문으로 적재 구역에 접근할 수 있습니다.", "A western service door also reaches the storage area."),
        "M04": ("객실 사이 연결문은 복도를 거치지 않는 경로를 만듭니다.", "Interconnecting guest rooms provide a route independent of the corridor."),
        "M05": ("남쪽 집결 구역과 북쪽 직원 출입구가 공용 복도로 연결됩니다.", "The common hall connects the southern extraction area to a northern staff entrance."),
    }
    for path in sorted(DATA.glob("*.json")):
        data = json.loads(path.read_text())
        if data["id"] in ["M07", "M08", "M09"]:
            continue
        before = copy.deepcopy(data)
        mid = data["id"][:3]
        time, light = env.get(mid, ("day", 1))
        data.setdefault("environment", dict(time_of_day=time, lighting=light))
        for room in data["rooms"]:
            label = room.get("label", "").lower()
            room.setdefault("indoor", True)
            room.setdefault("lighting", .85 if any(s in label for s in ["storage", "service", "records"]) else 1)
            room.setdefault("floor_surface", "concrete" if mid == "M03" or mid == "M06" else
                            ("carpet" if mid == "M04" and "room" in label else
                             ("wood" if mid == "M01" else "tile")))
        if mid in service:
            split_for_door(data, *service[mid])
        for wall in data["walls"]:
            wall.setdefault("height", 2.8)
            wall.setdefault("material", "plaster" if mid in ["M01", "M04", "M05"] else "concrete")
        for value in data["doors"]:
            value.setdefault("hinge_side", -1.0)
            value.setdefault("swing_sign", -1.0)
            value.setdefault("locked", False)
            value.setdefault("hp", 100)
            value.setdefault("destroyed", False)
            value.setdefault("height", 2.1)
            value.setdefault("material", "wood")
        if mid in alternatives:
            for value in data["doors"][:4]:
                value.setdefault("initial_states", ["CLOSED", "OPEN"])
        for prop in data["props"]:
            prop.setdefault("height", HEIGHTS[prop["type"]])
            prop.setdefault("material", MATERIALS[prop["type"]])
        for group in ["units", "enemies"]:
            for actor in data[group]:
                actor.setdefault("reserve_ammo", MAGAZINES[actor.get("weapon", "standard")] * 3)
                actor.setdefault("stance", "standing")
                actor.setdefault("movement_mode", "normal")
        if mid in alternatives:
            for actor, (x,z) in zip(data["enemies"], alternatives[mid]):
                actor["spawns"] = [dict(x=actor["x"],z=actor["z"],facing=actor["facing"],patrol=copy.deepcopy(actor.get("patrol",[]))),
                                   dict(x=x,z=z,facing=0,patrol=copy.deepcopy(actor.get("patrol",[])))]
        if mid in route_hints:
            hint, english = route_hints[mid]
            if hint not in data["objectives"]:
                data["objectives"].append(hint)
            if english not in data.get("description_en", ""):
                data["description_en"] = data.get("description_en", "") + " " + english
            if hint not in data.get("description", ""):
                data["description"] = data.get("description", "") + " " + hint
        if before != data:
            data["revision"] += 1
            write(path.stem, data)


if __name__ == "__main__":
    new_operations()
    enrich_existing()
    print("Authored M07 garage, M08 linked shops, M09 courtyard; physical metadata and service links updated.")
