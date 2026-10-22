"""CQB07–12: authored control choices, expanded with existing primitives.

The topology and equipment provide the puzzle. No room-state, command macro,
AI decision or private observation is serialized into a mission.
"""
from math import pi

from .common import door, grid_mission, line_walls, room_by_id


def _patrol(data, index, room_id):
    room = room_by_id(data, room_id)
    enemy = data["enemies"][index]
    enemy["response_role"] = "patrol"
    points = [[room["x"] - 0.9, room["z"] + 0.6],
              [room["x"] + 0.9, room["z"] + 0.6]]
    enemy["patrol"] = points
    for candidate in enemy["spawns"]:
        candidate["patrol"] = [point[:] for point in points]


def _star(data, id, label, stat, op, value):
    data["stars"].append(dict(id=id, label=label, stat=stat, op=op, value=value))


def _finish(data):
    for wall in data["walls"]:
        wall["height"] = 3.0
    for portal in data["doors"]:
        portal.update(state="CLOSED", height=2.1, hinge_side=-1, swing_sign=-1)
    return data


def build():
    rolling = grid_mission(
        "CQB07", "넓은 통로의 엄호", "Cover in the wide passage",
        "넓은 통로에서 롤링 T의 측면 경계를 유지하고 우회로의 순찰에 대비하세요.",
        "Keep the rolling T flank sectors in the wide passage and watch the bypass patrol.",
        row_depths=(5.6, 3.6))
    for id in ("r5", "r6", "r7", "r8"):
        room_by_id(rolling, id)["label"] = "WIDE " + id[1:]
    _patrol(rolling, 7, "r8")
    rolling["enemies"][3]["response_role"] = "reserve"

    junction = grid_mission(
        "CQB08", "T 교차로의 자세", "Stances at the T junction",
        "T 교차로에서 높은 자세와 낮은 자세의 사선을 나누고 연결 방을 정리하세요.",
        "Split standing and crouched firing lanes at the T junction before clearing the connecting rooms.",
        row_depths=(5.6, 3.6))
    # Move the single tree connection to the middle column. The bottom-row
    # left/right portals and this north portal make a real T; the far-right
    # vertical portal remains the one internal bypass.
    junction["walls"] = [wall for wall in junction["walls"]
                         if not wall["id"].startswith("partition_rows_")]
    junction["walls"] += line_walls("x", 8.6, 3.0, 25.4,
                                    [(11.4, 1.8), (22.6, 1.8)],
                                    prefix="partition_rows")
    junction["doors"] = [portal for portal in junction["doors"]
                         if portal["id"] != "inner_v0"]
    junction["doors"].append(door("inner_v1", 11.4, 8.6, "x", "T 북측 연결"))
    room_by_id(junction, "r6")["label"] = "T JUNCTION"
    junction["units"][1]["stance"] = "crouched"
    junction["units"][3]["stance"] = "crouched"
    junction["enemies"][1]["response_role"] = "guard"

    quiet = grid_mission(
        "CQB09", "조용한 인계", "Quiet handover",
        "수신호로 준비를 맞추고, 발소리와 문 소리에 반응하는 후방 예비대를 확인하세요.",
        "Coordinate readiness with hand signals and watch the rear reserve reacting to footsteps and doors.")
    quiet["noise_discipline"] = "hand_signals"
    for unit in quiet["units"]:
        unit["weapon"] = "suppressed"
        unit["movement_mode"] = "careful"
    quiet["enemies"][6]["response_role"] = "reserve"
    quiet["enemies"][7]["response_role"] = "guard"

    identify = grid_mission(
        "CQB10", "식별 후 통제", "Identify before control",
        "민간인이 있는 정밀 작전입니다. 관측한 인원을 식별하고 투항자와 민간인을 통제하세요.",
        "A precision operation with civilians: identify observed people, then control surrendered suspects and secure civilians.")
    for index, id in enumerate(("r2", "r7"), 1):
        room = room_by_id(identify, id)
        identify["civilians"].append(dict(id=f"civilian{index}", name="민간인",
                                          x=room["x"] + 1.25, z=room["z"] + 1.15,
                                          facing=pi / 2))
    _star(identify, "arrest", "투항자 체포", "arrests", "gte", 1)

    reload = grid_mission(
        "CQB11", "재장전 경계 인계", "Cover during reload",
        "짧은 탄창으로 시작합니다. 재장전 중 동료에게 경계 구역을 인계하고 후방을 지키세요.",
        "Start with nearly empty magazines. Hand the sector to a teammate during reload and keep rear cover.")
    for unit in reload["units"]:
        unit["ammo"] = 3
        unit["reserve_ammo"] = 60
    reload["enemies"][7]["response_role"] = "reserve"
    _star(reload, "reload_cover", "재장전 후 완수", "reloads", "gte", 1)

    fragments = grid_mission(
        "CQB12", "얇은 벽 너머", "Beyond the thin wall",
        "고강도 작전입니다. 파편이 얇은 벽을 통과하므로 인접 방의 아군을 고려해 장비를 선택하세요.",
        "A high intensity operation: fragments cross thin walls, so choose equipment with adjacent-room teammates in mind.",
        roe="high_intensity")
    for wall in fragments["walls"]:
        if wall["id"].startswith("partition_"):
            wall["material"] = "drywall"
            wall["penetration_resistance"] = 0.3
    for unit in fragments["units"]:
        unit["equipment"] = {"frag": 1, "stun": 1, "breach": 1}
    _star(fragments, "team_damage", "아군 피해 0", "unit_damage", "eq", 0)
    return [_finish(data) for data in
            (rolling, junction, quiet, identify, reload, fragments)]
