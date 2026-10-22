"""Six static contact puzzles using the existing schema-6 gameplay rules.

Each puzzle has eight occupied rooms, two exterior entrances and one internal
cycle. Spawn candidate zero preserves the default authored plan exactly.
"""
from __future__ import annotations

import argparse
from copy import deepcopy
import json
from mission_authoring import preserve_enemy_strengths
from math import hypot, pi
from pathlib import Path

from .common import door_by_id, grid_mission, line_walls, prop, room_by_id

ROOT = Path(__file__).resolve().parents[2]


def _finish(data):
    for wall in data["walls"]:
        wall["height"] = 3.0
    for portal in data["doors"]:
        portal.setdefault("state", "CLOSED")
        portal.setdefault("height", 2.1)
        portal.setdefault("hinge_side", -1)
        portal.setdefault("swing_sign", -1)
    for enemy in data["enemies"]:
        enemy.setdefault("response_role", "guard")
    return data


def _patrol(data, enemy_index, room_ids):
    """An actual existing portal route, with each candidate's start preserved."""
    enemy = data["enemies"][enemy_index]
    destinations = [[room_by_id(data, key)[axis] for axis in ("x", "z")]
                    for key in room_ids]
    enemy["response_role"] = "patrol"
    enemy["patrol"] = [[enemy["x"], enemy["z"]], *destinations]
    for candidate in enemy["spawns"]:
        candidate["patrol"] = [[candidate["x"], candidate["z"]],
                               *deepcopy(destinations)]


def _resize_side_doors(data, width):
    """Resize the six side portals together with their actual wall openings."""
    rooms = [room for room in data["rooms"] if room["indoor"]]
    start = min(room["z"] - room["d"] / 2 for room in rooms)
    end = max(room["z"] + room["d"] / 2 for room in rooms)
    portals = [portal for portal in data["doors"] if portal["axis"] == "z"]
    data["walls"] = [wall for wall in data["walls"]
                     if not wall["id"].startswith("partition_c")]
    for index, boundary in enumerate(sorted({portal["x"] for portal in portals})):
        openings = []
        for portal in portals:
            if portal["x"] != boundary:
                continue
            portal["d"] = width
            openings.append((portal["z"], width))
        data["walls"].extend(line_walls(
            "z", boundary, start, end, openings, prefix=f"partition_c{index}",
        ))


def build():
    reinforced = grid_mission(
        "CQB01", "보강 문과 두 번째 입구", "Reinforced Door, Second Entrance",
        "보강된 좌측 문은 차기로 열리지 않습니다. 산탄총·장약 또는 우측 입구를 선택하고, 문 조작 뒤 같은 신호로 진입하세요.",
        "The reinforced left door cannot be kicked open. Choose a shotgun, a charge or the right entrance, then synchronize entry after the door action.",
    )
    door_by_id(reinforced, "ext_left").update(
        locked=True, reinforced=True, kick_resistance=0.0,
        material="metal", hp=100, label="보강 외부 문",
    )
    reinforced["units"][-1]["weapon"] = "shotgun"
    reinforced["enemies"][5]["response_role"] = "reserve"

    short = grid_mission(
        "CQB02", "연속되는 짧은 방", "Short Room Chain",
        "깊이 2.4m의 방이 이어집니다. 두 명만 들어가고 나머지는 문 밖을 경계하며, 연결 문을 넘어갈 때 다시 순서를 정하세요.",
        "A chain of rooms only 2.4 metres deep. Enter with two operators, cover from outside and set the order again at each connecting door.",
        row_depths=(2.4, 2.4), door_width=1.4,
    )
    # The exterior leaves open into the outdoor preparation area. The narrow
    # rooms remain physical rooms; SHORT is calculated from their dimensions.
    for key in ("ext_left", "ext_right"):
        door_by_id(short, key)["swing_sign"] = -1
    # A 2.4m room allows only .85m from its centre to a wall-safe jamb point.
    # The .8m portal gives an actual .80m jamb (including leaf/body clearance),
    # while the .46m body still fits. Resize the wall gaps with the portals,
    # preserving the room depths and both exterior/vertical portals.
    _resize_side_doors(short, 0.8)
    short["enemies"][6]["response_role"] = "reserve"

    rear = grid_mission(
        "CQB03", "L자 사무실의 후방", "Rear of the L Office",
        "오른쪽 위 모서리에서 동선이 L자로 꺾입니다. 왼쪽 연결 문과 내부 우회로는 지원 인원의 접근로이므로, 정리한 방을 떠날 때 후방을 경계하세요.",
        "The route turns into an L at the upper-right corner. The left connecting door and internal bypass let reserves approach; cover the rear when leaving a cleared room.",
    )
    rear["enemies"][0].update(enemy_type="rusher", response_role="reserve")
    rear["enemies"][7]["response_role"] = "reserve"
    _patrol(rear, 6, ("r7", "r8", "r4", "r8", "r7"))

    response = grid_mission(
        "CQB04", "두 입구와 대응조", "Two Entrances and the Reserve",
        "좌우 입구는 서로 다른 방으로 이어집니다. 동시 진입과 조용한 개방을 비교하고, 총성을 들은 대응조가 연결 문으로 이동하는 데 대비하세요.",
        "The two entrances lead to different rooms. Compare synchronized entry with quiet opening and prepare for reserves moving through connected doors after hearing gunfire.",
        column_widths=(5.6, 6.4, 6.4, 5.6),
    )
    response["enemies"][5]["response_role"] = "reserve"
    response["enemies"][6]["response_role"] = "reserve"
    _patrol(response, 1, ("r2", "r3", "r2"))

    domination = grid_mission(
        "CQB05", "가구 뒤의 지배 지점", "Domination Around Furniture",
        "수납장과 책상이 기본 지배 지점을 막습니다. 진입 초안을 확인해 도달 가능한 지점으로 고치고, 가구 뒤의 위협을 관측한 뒤 교전하세요.",
        "Cabinets and desks obstruct the default domination points. Review the entry draft, move the goals to reachable positions and identify threats behind furniture before firing.",
        column_widths=(6.4, 5.6, 5.6, 6.4),
    )
    for key in ("r2", "r5", "r8"):
        room = room_by_id(domination, key)
        domination["props"].append(prop(
            f"cabinet_{key}", "cabinet", room["x"] - room["w"] / 2 + 0.9,
            room["z"] + room["d"] / 2 - 0.95, 1.0, 1.4,
            cover="full", height=2.1, material="wood",
        ))
    for key in ("r3", "r6"):
        room = room_by_id(domination, key)
        domination["props"].append(prop(
            f"desk_{key}", "desk", room["x"] + 1.15, room["z"] + 0.9,
            1.6, 0.9, cover="low", height=0.85, material="wood",
        ))

    serpentine = grid_mission(
        "CQB06", "좁은 연결 통로", "Narrow Connecting Lanes",
        "가운데 연결 통로의 벽 표면 간 폭은 1.76m입니다. 서펜타인으로 앞·좌·우·뒤를 나누어 경계하고, 넓은 양끝 방에서 진입 대형을 다시 정하세요.",
        "The middle lanes have 1.76 metres between wall surfaces. Use serpentine cover for front, left, right and rear, then reset the entry formation in the wider end rooms.",
        column_widths=(5.6, 2.0, 5.6, 5.6), door_width=1.4,
    )
    # Both leaves beside each narrow lane open into the wider neighbouring
    # rooms, leaving the real 1.76m corridor available for covered movement.
    for row in range(2):
        door_by_id(serpentine, f"inner_h{row}_0")["swing_sign"] = -1
        door_by_id(serpentine, f"inner_h{row}_1")["swing_sign"] = 1
    # Patrols cross real horizontal portals; a patrol label without an authored
    # route would not exercise the existing moving-contact gameplay.
    _patrol(serpentine, 5, ("r6", "r7", "r6"))
    serpentine["enemies"][3]["response_role"] = "reserve"

    return [_finish(data) for data in
            (reinforced, short, rear, response, domination, serpentine)]


def _room_at(data, x, z):
    return next((room for room in data["rooms"]
                 if abs(x - room["x"]) < room["w"] / 2
                 and abs(z - room["z"]) < room["d"] / 2), None)


def check(missions):
    """Fast strict schema and authored topology checks; engine nav is separate."""
    from scripts.validate_missions import prop_assets, validate_document

    checks = 0

    def require(condition, message):
        nonlocal checks
        checks += 1
        if not condition:
            raise AssertionError(message)

    require([data["id"] for data in missions] == [f"CQB{i:02}" for i in range(1, 7)], "six stable contact IDs")
    for data in missions:
        label = data["id"]
        require(not validate_document(data, set(prop_assets())), f"{label}: strict schema")
        require(len(data["rooms"]) == 9 and len(data["doors"]) == 10, f"{label}: room/door counts")
        require(sum(room["indoor"] for room in data["rooms"]) == 8, f"{label}: eight indoor rooms")
        require(len(data["enemies"]) == 8, f"{label}: enemy count")
        graph = {room["id"]: set() for room in data["rooms"]}
        external = 0
        for portal in data["doors"]:
            dx, dz = (0, 0.4) if portal["axis"] == "x" else (0.4, 0)
            sides = [_room_at(data, portal["x"] + sign * dx, portal["z"] + sign * dz)
                     for sign in (-1, 1)]
            require(all(sides) and sides[0]["id"] != sides[1]["id"], f"{label}/{portal['id']}: genuine adjacent rooms")
            a, b = sides
            graph[a["id"]].add(b["id"])
            graph[b["id"]].add(a["id"])
            external += int(not a["indoor"] or not b["indoor"])
        require(external == 2, f"{label}: two exterior entrances")
        reached, pending = set(), ["r1"]
        while pending:
            room_id = pending.pop()
            if room_id in reached:
                continue
            reached.add(room_id)
            pending.extend(graph[room_id] - reached)
        require(len(reached) == 9, f"{label}: connected building and preparation area")
        inside = {room["id"] for room in data["rooms"] if room["indoor"]}
        reached, pending = set(), ["r1"]
        while pending:
            room_id = pending.pop()
            if room_id in reached:
                continue
            reached.add(room_id)
            pending.extend((graph[room_id] & inside) - reached)
        require(reached == inside, f"{label}: all rooms connected without leaving the building")
        require(sum(len(graph[key] & inside) for key in inside) // 2 == 8,
                f"{label}: seven tree connections plus one internal bypass")
        occupied = set()
        for enemy in data["enemies"]:
            candidates = enemy["spawns"]
            require(len(candidates) == 2, f"{label}/{enemy['id']}: two candidates")
            require(candidates[0] == {key: deepcopy(enemy[key]) for key in ("x", "z", "facing", "patrol") if key in enemy}, f"{label}/{enemy['id']}: exact default candidate")
            room = _room_at(data, enemy["x"], enemy["z"])
            require(room is not None and room["indoor"] and room["id"] not in occupied, f"{label}: one enemy per room")
            occupied.add(room["id"])
            require(all(_room_at(data, candidate["x"], candidate["z"])["id"] == room["id"] for candidate in candidates), f"{label}: candidates remain in their authored room")
            require(hypot(candidates[0]["x"] - candidates[1]["x"], candidates[0]["z"] - candidates[1]["z"]) >= 0.7, f"{label}: separated candidate positions")
        require(len(occupied) == 8, f"{label}: all eight rooms occupied")
        require(all(wall["height"] == 3.0 for wall in data["walls"]), f"{label}: metre-scale walls")
    require(door_by_id(missions[0], "ext_left")["kick_resistance"] == 0.0, "reinforced topic changes actual kick rule")
    require(all(min(room["w"], room["d"]) <= 2.5 for room in missions[1]["rooms"] if room["indoor"]), "SHORT topic changes actual dimensions")
    require(any(enemy["response_role"] == "reserve" for enemy in missions[2]["enemies"]), "rear topic has an actual reserve")
    require(sum(enemy["response_role"] == "reserve" for enemy in missions[3]["enemies"]) == 2, "two-entry response has reserves")
    require(any(item["cover"] == "full" for item in missions[4]["props"]), "domination topic has physical full cover")
    require(room_by_id(missions[5], "r2")["w"] - 0.24 < 1.8, "serpentine topic changes wall-surface width")
    return checks


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true", help="write only CQB01–06 JSON")
    args = parser.parse_args()
    missions = build()
    checks = check(missions)
    if args.write:
        target = ROOT / "game/data/cqb"
        target.mkdir(parents=True, exist_ok=True)
        for data in missions:
            preserve_enemy_strengths(data, (target / f"{data['id']}.json"))
            (target / f"{data['id']}.json").write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
    print(f"BREACH_CQB_CONTACT_AUTHORING_RESULT checks={checks} failures=0")


if __name__ == "__main__":
    main()
