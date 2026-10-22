"""Five repeatable course families (the ROE comparison has two missions).

COURSE_SPECS is test/authoring metadata, never injected into mission JSON.
Every duration comes from real routes, door work, control and cursory search;
there is no timed WAIT padding in a course recipe.
"""
from copy import deepcopy
from math import pi
from .common import grid_mission, door_by_id, room_by_id, line_walls, ORDER, training_targets

COURSE_SPECS = {}


def _course(id, title, title_en, topic, topic_en, *, depths=(5.6, 5.6), roe="precision", seed=9001):
    data = grid_mission(id, title, title_en, topic, topic_en, columns=2,
                        row_depths=depths, column_widths=(5.6, 5.6), roe=roe)
    data["seed"] = data["default_seed"] = seed
    # The authored default leaf favours the right jamb. A training squad is
    # already on its corresponding sides; assembly is not a body-swap puzzle.
    entrance_x = door_by_id(data,"ext_left")["x"]
    for index, unit in enumerate(data["units"]):
        unit["x"] = entrance_x + (1.3 if index % 2 == 0 else -1.3)
    training_targets(data)
    data["briefing"] = {"difficulty": "훈련", "estimated_minutes": "0.5–1.5",
                        "threat": "반격하지 않는 훈련 표적", "tip": topic}
    data["stars"] = [{"id": "course_time", "label": "90초 이내", "stat": "duration", "op": "lte", "value": 90},
                     {"id": "no_hits", "label": "피격 0", "stat": "hits_taken", "op": "eq", "value": 0},
                     {"id": "no_civilian_damage", "label": "민간인 피해 0", "stat": "civilian_damage", "op": "eq", "value": 0}]
    COURSE_SPECS[id] = {"mission_id": id, "seed": seed, "order_ids": list(ORDER),
                        "duration_range": [30.0, 90.0], "formation_legs": [],
                        "legs": [{"door_id": portal, "room_id": room, "method": "OPEN_DOOR"}
                                 for portal, room in (("ext_left", "r3"), ("inner_h1_0", "r4"),
                                                      ("inner_v1", "r2"), ("inner_h0_0", "r1"))]}
    _finish(data)
    return data


def _finish(data, *, zone=None, room_id="r3", return_door_id="inner_v0", exit_door_id="ext_left"):
    left = door_by_id(data, exit_door_id)
    zone = zone or [door_by_id(data, "ext_right")["x"], left["z"] + 2.5, 2.8, 1.8]
    data["win"][-1]["zone"] = list(zone)
    bottom_left = room_by_id(data, room_id)
    COURSE_SPECS[data["id"]]["finish"] = {
        "via_doors": ([return_door_id] if return_door_id else []) + [exit_door_id], "zone": list(zone),
        "return_leg": {"door_id": return_door_id, "room_id": room_id, "method": "OPEN_DOOR"} if return_door_id else {},
        "outside_targets": {id: [left["x"] + (1.3 if i % 2 == 0 else -1.3), left["z"] + 1.5 + 0.7 * (i // 2)]
                            for i, id in enumerate(ORDER)},
        "finish_unit_id": "charlie",
        "waypoints": [[bottom_left["x"], bottom_left["z"]],
                      [left["x"], left["z"] + 1.1], [zone[0], zone[1]]]}


def _formation_return(data):
    # A completed hall formation cannot observe an entrance through the
    # building wall. Walk the squad back to four distinct authored prep
    # points before the first door lesson; initial hall spawns are not used
    # as return goals. This is actual route work, without timed WAIT padding.
    entrance = door_by_id(data, "ext_left")
    COURSE_SPECS[data["id"]]["transition_after_formations"] = {
        "targets": {id: [entrance["x"] + (1.3 if i % 2 == 0 else -1.3),
                         entrance["z"] + 1.5 + 0.7 * (i // 2)]
                    for i, id in enumerate(ORDER)}}


def _corner(data):
    portal = door_by_id(data, "inner_h1_0")
    # Leave room for the complete 1.3m jamb offset plus actor/wall radius.
    # The portal is still visibly off centre without a blocked corner stack.
    portal["z"] -= 0.8
    # This corner leaf opens into the destination room. Both approach jambs
    # can then reach the portal without sharing a return around its outer tip.
    portal["swing_sign"] = 1
    data["walls"] = [wall for wall in data["walls"] if not wall["id"].startswith("partition_c0_")]
    upper, lower = room_by_id(data, "r1"), room_by_id(data, "r3")
    openings = [(door_by_id(data, f"inner_h{row}_0")["z"], 1.8) for row in range(2)]
    data["walls"] += line_walls("z", portal["x"], upper["z"] - upper["d"] / 2,
                                lower["z"] + lower["d"] / 2, openings, prefix="partition_c0")


def _centre_corner_course(data):
    """Share one physical house and lane-preserving draft across ROE modes."""
    _corner(data)
    # Each leaf follows the course's first entry into its destination room.
    # The two subsequent turns retain the squad's actual jamb lanes.
    for portal_id, swing in (("inner_h1_0", 1), ("inner_v1", 1),
                             ("inner_h0_0", -1), ("inner_v0", -1)):
        door_by_id(data, portal_id).update(hinge_side=-1, swing_sign=swing)
    COURSE_SPECS[data["id"]]["legs"][2]["order_ids"] = ["delta", "bravo", "charlie", "alpha"]
    COURSE_SPECS[data["id"]]["legs"][3]["order_ids"] = ["bravo", "alpha", "delta", "charlie"]
    # The first room was already searched. Open the real return portal and
    # physically leave through it without issuing another domination drill
    # or handing secured followers to new entry operators merely to exit.
    finish = COURSE_SPECS[data["id"]]["finish"]
    finish["return_leg"] = {}
    finish["open_doors"] = ["inner_v0"]


def _formation_target_rooms(data):
    """Finish the hall lesson with two real target-control rooms.

    Only the lower house remains: the old row boundary becomes its solid
    north wall. Hall and junction walls are independent and stay unchanged.
    All four targets retain two seeded candidates in distinct lawful lanes.
    """
    left, right = room_by_id(data, "r3"), room_by_id(data, "r4")
    west, east = left["x"] - left["w"] / 2, right["x"] + right["w"] / 2
    north, south = left["z"] - left["d"] / 2, left["z"] + left["d"] / 2
    portal = door_by_id(data, "inner_h1_0")
    data["rooms"] = [room for room in data["rooms"] if room["id"] not in ("r1", "r2")]
    data["doors"] = [door for door in data["doors"] if door["id"] in ("ext_left", "ext_right", "inner_h1_0")]
    data["walls"] = [wall for wall in data["walls"]
                     if not wall["id"].startswith(("outer_", "partition_"))]
    data["walls"] += line_walls("x", north, west, east, prefix="outer_north")
    data["walls"] += line_walls("x", south, west, east,
                                [(door_by_id(data, id)["x"], door_by_id(data, id)["w"])
                                 for id in ("ext_left", "ext_right")], prefix="outer_south")
    data["walls"] += line_walls("z", west, north, south, prefix="outer_west")
    data["walls"] += line_walls("z", east, north, south, prefix="outer_east")
    data["walls"] += line_walls("z", portal["x"], north, south,
                                [(portal["z"], portal["d"])], prefix="partition_c0")
    for index, enemy in enumerate(data["enemies"]):
        room = left if index % 2 == 0 else right
        z = room["z"] + (-1.0 if index < 2 else 1.0)
        candidates = [{"x": room["x"] + dx, "z": z, "facing": enemy["facing"]}
                      for dx in (-0.45, 0.45)]
        enemy.update(**candidates[0], spawns=candidates)
    data["focus"] = [(west + east) / 2, (north + south) / 2]
    for rule in data["win"]:
        if rule["type"] == "rooms_cleared":
            rule["room_ids"] = ["r3", "r4"]
    spec = COURSE_SPECS[data["id"]]
    spec["legs"] = [{"door_id": "ext_left", "room_id": "r3", "method": "OPEN_DOOR"},
                    {"door_id": "inner_h1_0", "room_id": "r4", "method": "OPEN_DOOR", "stage_stacks": True}]
    old_finish = spec["finish"]
    zone = old_finish["zone"] if data["id"] == "SH04" else [right["x"], south + 3.7, 2.8, 1.8]
    finish_unit_id = old_finish["finish_unit_id"]
    _finish(data, zone=zone, room_id="r4", return_door_id="", exit_door_id="ext_right")
    spec["finish"]["finish_unit_id"] = finish_unit_id


def _short_rooms(data):
    # Enter each shallow room through its wide wall. A transverse portal in
    # the 2.4m side would leave too little space for two side-wall sectors and
    # an intact rotating leaf. The normal lower rooms remain interconnected.
    data["doors"] = [portal for portal in data["doors"] if portal["id"] != "inner_h0_0"]
    data["walls"] = [wall for wall in data["walls"] if not wall["id"].startswith("partition_c0_")]
    portal = door_by_id(data,"inner_h1_0")
    lower = room_by_id(data,"r3")
    data["walls"] += line_walls("z",portal["x"],3.0,lower["z"]+lower["d"]/2,
                                [(portal["z"],1.8)],prefix="partition_c0")
    COURSE_SPECS[data["id"]]["legs"] = [
        {"door_id":"ext_left","room_id":"r3","method":"OPEN_DOOR"},
        {"door_id":"inner_v0","room_id":"r1","method":"OPEN_DOOR","recover_short":True,
         "order_ids":["charlie","delta","alpha","bravo"]},
        {"door_id":"inner_h1_0","room_id":"r4","method":"OPEN_DOOR",
         "order_ids":["charlie","alpha","delta","bravo"]},
        {"door_id":"inner_v1","room_id":"r2","method":"OPEN_DOOR","recover_short":True,
         "order_ids":["bravo","alpha","delta","charlie"],"stage_stacks":True}]
    exit_portal = door_by_id(data,"ext_right")
    _finish(data,zone=[exit_portal["x"],exit_portal["z"]+3.7,2.8,1.8],
            room_id="r4",return_door_id="",exit_door_id="ext_right")


def _corridors(data):
    """A real narrow hall and a separate wide hall; walls are metre scale."""
    bottom = door_by_id(data, "ext_left")["z"]
    data["bounds"][0] = 19.0
    # Narrow hall physical clear width 1.6; wide hall physical width 3.36.
    for side, x in (("west", 0.88), ("east", 2.72)):
        data["walls"] += line_walls("z", x, 3.0, bottom, prefix=f"narrow_{side}")
    data["walls"] += line_walls("x", 3.0, 0.88, 2.72, prefix="narrow_cap")
    for side, x in (("west", 14.6), ("east", 18.2)):
        data["walls"] += line_walls("z", x, 3.0, bottom, prefix=f"wide_{side}")
    data["walls"] += line_walls("x", 3.0, 14.6, 18.2, prefix="wide_cap")
    data["rooms"] += [{"id": "narrow_hall", "label": "SERPENTINE", "x": 1.8, "z": (3.0 + bottom) / 2,
                       "w": 1.6, "d": bottom - 3.0, "indoor": False},
                      {"id": "wide_hall", "label": "ROLLING T", "x": 16.4, "z": (3.0 + bottom) / 2,
                       "w": 3.36, "d": bottom - 3.0, "indoor": False}]
    for index, unit in enumerate(data["units"]):
        unit.update(x=1.8, z=bottom - 3.2 + 0.7 * index)
    COURSE_SPECS[data["id"]]["formation_legs"] = [
        {"kind": "SERPENTINE", "target": [1.8, 4.0]},
        {"kind": "ROLLING_T", "target": [16.4, 4.0],
         "transition_before": {"targets": {
             id: [16.4, bottom - 3.2 + 0.7 * index]
             for index, id in enumerate(ORDER)}}}]
    _formation_return(data)


def _junction(data):
    # Same physical 3.2m stem/cross contract as the tested formation fixture,
    # translated below the building. Both branches are walkable authored halls.
    data["bounds"][1] = 31.0
    data["walls"] += line_walls("x", 16.2, 2.6, 14.6, prefix="t_north")
    data["walls"] += line_walls("x", 19.4, 2.6, 14.6, [(8.6, 3.2)], prefix="t_cross_south")
    for side, x in (("west", 2.6), ("east", 14.6)):
        data["walls"] += line_walls("z", x, 16.2, 19.4, prefix=f"t_cross_{side}")
    for side, x in (("west", 7.0), ("east", 10.2)):
        data["walls"] += line_walls("z", x, 19.4, 28.6, prefix=f"t_stem_{side}")
    data["walls"] += line_walls("x", 28.6, 7.0, 10.2, prefix="t_stem_south")
    # Doorless branch openings connect to the outdoor prep area. The T
    # junction's north wall is split, preserving the actual stem/cross shape.
    data["walls"] = [wall for wall in data["walls"] if not wall["id"].startswith("t_north_")]
    data["walls"] += line_walls("x", 16.2, 2.6, 14.6, [(4.2, 1.8), (13.0, 1.8)], prefix="t_north")
    data["rooms"] += [{"id": "t_stem", "label": "T APPROACH", "x": 8.6, "z": 24.0, "w": 2.96, "d": 9.2, "indoor": False},
                      {"id": "t_cross", "label": "T / L", "x": 8.6, "z": 17.8, "w": 11.76, "d": 2.96, "indoor": False}]
    for index, unit in enumerate(data["units"]): unit.update(x=8.6, z=23.6 + 0.7 * index)
    COURSE_SPECS[data["id"]]["formation_legs"] = [
        {"kind": "T_JUNCTION", "target": [8.6, 17.8]},
        {"kind": "SERPENTINE", "target": [4.2, 17.8]}]
    # Keep a full body route around each 1.8m exterior leaf. The original
    # 2m gap pinched its tip against the T north wall; translate this separate
    # training junction as a whole, preserving its widths and branch shape.
    for wall in data["walls"]:
        if wall["id"].startswith("t_"): wall["z"] += 1.0
    for room in data["rooms"]:
        if room["id"].startswith("t_"): room["z"] += 1.0
    for unit in data["units"]: unit["z"] += 1.0
    for leg in COURSE_SPECS[data["id"]]["formation_legs"]: leg["target"][1] += 1.0
    data["bounds"][1] += 1.0
    _finish(data, zone=[4.2,18.8,1.2,1.2])
    COURSE_SPECS[data["id"]]["finish"]["finish_unit_id"] = "delta"
    _formation_return(data)


def build():
    COURSE_SPECS.clear()
    first = _course("SH01", "킬하우스 01 · 중앙과 구석", "Shoot house 01 · Centre and corner",
                    "중앙 문과 구석 문에서 진입 순서와 지배 구역을 비교하세요.",
                    "Compare entry order and control sectors at centre and corner doors.", seed=9001)
    _centre_corner_course(first)
    COURSE_SPECS[first["id"]]["finish"]["rear_depth_margin"] = 1.0
    short = _course("SH02", "킬하우스 02 · 짧은 연결 방", "Shoot house 02 · Short connected rooms",
                    "짧은 방에서는 두 명이 진입하고 나머지는 연결 문을 경계하세요.",
                    "Use two entrants in short rooms while the rest cover connecting doors.", depths=(2.4, 5.6), seed=9002)
    _short_rooms(short)
    corridors = _course("SH03", "킬하우스 03 · 복도 대형", "Shoot house 03 · Corridor formations",
                        "좁은 복도는 서펜타인, 넓은 복도는 롤링 T로 통과하세요.",
                        "Use serpentine in the narrow hall and rolling T in the wide hall.", seed=9003)
    _corridors(corridors)
    _formation_target_rooms(corridors)
    junction = _course("SH04", "킬하우스 04 · T와 L", "Shoot house 04 · T and L junctions",
                       "T자 교차로에서 높낮이 역할을 나누고 L자 방향 전환을 계획하세요.",
                       "Split stance roles at the T junction, then plan the L turn.", seed=9004)
    _junction(junction)
    _formation_target_rooms(junction)
    precision = _course("SH05_PRECISION", "킬하우스 05 · 정밀 정리", "Shoot house 05 · Precision clearance",
                        "같은 집에서 표적과 민간인을 식별하고 모두 확보하세요.",
                        "Identify targets and secure civilians in the shared house.", seed=9055)
    _centre_corner_course(precision)
    # The comparison uses identical target candidates, gear, order, geometry
    # and seed. Only ROE and the presence of noncombatants differ in the map.
    precision["units"][0]["equipment"] = {"stun": 1, "frag": 1, "breach": 1}
    first_room = room_by_id(precision, "r3")
    last_room = room_by_id(precision, "r1")
    precision["civilians"] = [{"id": "c1", "name": "훈련 민간인 01", "x": first_room["x"] + 1.1, "z": first_room["z"] + 0.7},
                              {"id": "c2", "name": "훈련 민간인 02", "x": last_room["x"] + 1.1, "z": last_room["z"] + 0.7}]
    high = deepcopy(precision)
    high.update(id="SH05_HIGH_INTENSITY", title="킬하우스 05 · 고강도 정리", title_en="Shoot house 05 · High intensity clearance",
                description="비전투원이 없는 같은 집에서 파편 수류탄과 진입 드릴을 비교하세요.",
                description_en="Compare fragmentation and entry drills in the same house without noncombatants.", roe="high_intensity", civilians=[])
    COURSE_SPECS[high["id"]] = deepcopy(COURSE_SPECS[precision["id"]])
    COURSE_SPECS[high["id"]]["mission_id"] = high["id"]
    COURSE_SPECS[high["id"]]["finish"]["rear_depth_margin"] = 1.0
    COURSE_SPECS[high["id"]]["legs"][0]["pre_actions"] = [
        {"type": "OPEN_DOOR", "unit_id": "alpha", "args": {"door_id": "ext_left"}},
        {"type": "MOVE", "unit_id": "alpha", "args": {"target": [first_room["x"], door_by_id(high, "ext_left")["z"] + 2.0]}},
        {"type": "THROW_FRAG", "unit_id": "alpha", "args": {"target": [first_room["x"], first_room["z"]]}}]
    high["briefing"]["tip"] = high["description"]
    high["objectives"] = [high["description"], "모든 방을 정리하고 외부 종료 구역으로 이동하세요."]
    return [first, short, corridors, junction, precision, high]
