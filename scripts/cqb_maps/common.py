"""Shared static authoring geometry; no runtime room states or RNG mutation.

The two-row grid's tree has six horizontal portals and one vertical portal.
One additional vertical portal supplies the internal bypass. Both external
entrances open into the bottom row from a real outdoor preparation area.
"""
from copy import deepcopy
from math import pi
import re

THICK = 0.24
ORIGIN = (3.0, 3.0)
ORDER = ("alpha", "bravo", "charlie", "delta")


def line_walls(axis, fixed, start, end, openings=(), *, prefix="wall", material="wood"):
    """Wall surfaces and portal gaps share the same centre coordinates."""
    result, cursor = [], float(start)
    for center, width in sorted(openings):
        lo, hi = center - width / 2, center + width / 2
        if lo < start or hi > end or lo < cursor - 1e-8:
            raise ValueError(f"Overlapping/out-of-bounds portal in {prefix}")
        if lo > cursor:
            result.append({"x": (cursor + lo) / 2 if axis == "x" else fixed,
                           "z": fixed if axis == "x" else (cursor + lo) / 2,
                           "w": lo - cursor if axis == "x" else THICK,
                           "d": THICK if axis == "x" else lo - cursor,
                           "material": material})
        cursor = hi
    if cursor < end:
        result.append({"x": (cursor + end) / 2 if axis == "x" else fixed,
                       "z": fixed if axis == "x" else (cursor + end) / 2,
                       "w": end - cursor if axis == "x" else THICK,
                       "d": THICK if axis == "x" else end - cursor,
                       "material": material})
    for index, wall in enumerate(result, 1):
        wall["id"] = f"{prefix}_{index}"
    return result


def door(id, x, z, axis, label, *, width=1.8, **extra):
    return {"id": id, "x": float(x), "z": float(z),
            "w": float(width) if axis == "x" else THICK,
            "d": THICK if axis == "x" else float(width),
            "axis": axis, "label": label, "material": "wood", **extra}


def units_at(x, z):
    return [{"id": id, "name": id.upper(), "role": ("선봉", "지원", "돌입", "엄호")[i],
             "x": x + (-1.3 if i % 2 == 0 else 1.3), "z": z + 0.7 * (i // 2),
             "facing": -pi / 2, "weapon": "standard" if i < 2 else "light",
             "equipment": {"stun": 2, "breach": 1}, "reserve_ammo": 90}
            for i, id in enumerate(ORDER)]


def room_by_id(data, id):
    return next(room for room in data["rooms"] if room["id"] == id)


def door_by_id(data, id):
    return next(portal for portal in data["doors"] if portal["id"] == id)


def prop(id, kind, x, z, w, d, *, solid=True, cover="low", **extra):
    return {"id": id, "type": kind, "x": x, "z": z, "w": w, "d": d,
            "rotation": 0, "solid": solid, "cover": cover, **extra}


def grid_mission(id, title, title_en, topic, topic_en, columns=4,
                 row_depths=(5.6, 5.6), column_widths=None, door_width=1.8,
                 roe="precision"):
    """Return a detached schema-6 mission with r1..rN plus prep.

    inner_h{row}_{col} joins left/right neighbours; inner_v0 is the tree
    connection and inner_v{columns-1} its bypass. No metadata fields outside
    the mission schema are added. Callers may author props/actors/door details.
    """
    widths = list(column_widths or [5.6] * columns)
    depths = list(row_depths)
    if columns < 2 or len(widths) != columns or len(depths) != 2 or min(widths + depths) < 1.8:
        raise ValueError("CQB grid needs two rows and at least two metre-scale columns")
    if roe not in ("precision", "high_intensity"):
        raise ValueError("Unknown ROE")
    xs, zs = [ORIGIN[0]], [ORIGIN[1]]
    for width in widths: xs.append(xs[-1] + width)
    for depth in depths: zs.append(zs[-1] + depth)
    xc = [(xs[i] + xs[i + 1]) / 2 for i in range(columns)]
    zc = [(zs[i] + zs[i + 1]) / 2 for i in range(2)]
    rooms = [{"id": f"r{row * columns + col + 1}", "label": f"{row * columns + col + 1:02d}",
              "x": xc[col], "z": zc[row], "w": widths[col], "d": depths[row],
              "indoor": True, "color": "#697065", "floor_surface": "concrete"}
             for row in range(2) for col in range(columns)]
    rooms.append({"id": "prep", "label": "PREP", "x": (xs[0] + xs[-1]) / 2,
                  "z": zs[-1] + 3.25, "w": xs[-1] - xs[0] + 4,
                  "d": 6.5, "indoor": False, "color": "#555d54"})
    walls = line_walls("x", zs[0], xs[0], xs[-1], prefix="outer_north")
    walls += line_walls("x", zs[-1], xs[0], xs[-1], [(xc[0], door_width), (xc[-1], door_width)], prefix="outer_south")
    walls += line_walls("z", xs[0], zs[0], zs[-1], prefix="outer_west")
    walls += line_walls("z", xs[-1], zs[0], zs[-1], prefix="outer_east")
    doors = [door("ext_left", xc[0], zs[-1], "x", "좌측 외부 진입", width=door_width),
             door("ext_right", xc[-1], zs[-1], "x", "우측 외부 진입", width=door_width)]
    for col in range(columns - 1):
        walls += line_walls("z", xs[col + 1], zs[0], zs[-1], [(zc[row], door_width) for row in range(2)], prefix=f"partition_c{col}")
        for row in range(2):
            doors.append(door(f"inner_h{row}_{col}", xs[col + 1], zc[row], "z", "연결 방", width=door_width))
    walls += line_walls("x", zs[1], xs[0], xs[-1], [(xc[0], door_width), (xc[-1], door_width)], prefix="partition_rows")
    doors += [door("inner_v0", xc[0], zs[1], "x", "상층 연결", width=door_width),
              door(f"inner_v{columns-1}", xc[-1], zs[1], "x", "내부 우회", width=door_width)]
    digits = re.findall(r"\d+", id)
    seed = 10000 + int(digits[0]) if digits else 10001
    enemies = []
    for index, room in enumerate(rooms[:-1], 1):
        first = {"x": room["x"] - 0.45, "z": room["z"] - 0.3, "facing": pi / 2}
        second = {"x": room["x"] + 0.45, "z": room["z"] - 0.3, "facing": pi / 2}
        enemies.append({"id": f"e{index}", "name": "무장 인원", **first,
                        "enemy_type": "normal", "spawns": [first, second]})
    indoor_ids = [room["id"] for room in rooms[:-1]]
    return {"schema_version": 6, "id": id, "revision": 1,
            "title": title, "title_en": title_en, "subtitle": "CQB DOCTRINE",
            "description": topic, "description_en": topic_en,
            "seed": seed, "default_seed": seed, "bounds": [xs[-1] + 3, zs[-1] + 7.5],
            "focus": [(xs[0] + xs[-1]) / 2, (zs[0] + zs[-1]) / 2],
            "roe": roe, "noise_discipline": "verbal", "variant": "normal", "modifiers": [],
            "rooms": rooms, "walls": walls, "doors": doors, "props": [],
            "units": units_at(xc[0], zs[-1] + 1.5), "enemies": enemies, "civilians": [],
            "objectives": [topic, "모든 방을 정리하고 외부 종료 구역으로 이동하세요."],
            "win": [{"type": "rooms_cleared", "room_ids": indoor_ids}, {"type": "neutralize_all"},
                    {"type": "secure_all_civilians"}, {"type": "reach_zone", "zone": [xc[-1], zs[-1] + 2.5, 2.8, 1.8]}],
            "fail": [{"type": "no_civilian_loss"}],
            "stars": [{"id": "no_hits", "label": "피격 0", "stat": "hits_taken", "op": "eq", "value": 0},
                      {"id": "no_civilian_damage", "label": "민간인 피해 0", "stat": "civilian_damage", "op": "eq", "value": 0}]}


def training_targets(data):
    """Authored non-return-fire targets use existing tutorial actor fields."""
    for enemy in data["enemies"]:
        enemy.update(target=True, passive=True, training=True, ammo=0)
    return data


def clone(data):
    return deepcopy(data)
