"""Shared stable authoring defaults used by the original board generators.

Candidate zero preserves every original fixed puzzle. Alternative placements are
explicit authored points, never unchecked procedural coordinate jitter.
"""
from copy import deepcopy
import json


def preserve_enemy_strengths(data, path):
    """Keep manually tuned NPC tiers when regenerating a board's geometry."""
    if not path.is_file():
        return data
    previous = json.loads(path.read_text())
    if previous.get("id") != data.get("id"):
        return data
    strengths = {enemy["id"]: enemy["strength"] for enemy in previous.get("enemies", []) if "strength" in enemy}
    for enemy in data.get("enemies", []):
        if enemy["id"] in strengths:
            strength = strengths[enemy["id"]]
            if strength not in ("weak", "medium", "strong"):
                raise ValueError(f"Unknown NPC strength in {path}: {strength}")
            enemy["strength"] = strength
    data["revision"] = max(data.get("revision", 1), previous.get("revision", 1))
    return data

# Coordinates and imported mesh dimensions use metres, never map-relative
# shrinking. Keep the legacy 32m authoring profile separate from large maps.
SCHEMA_V1_MAX_EXTENT_M = 32.0
SCHEMA_V2_MAX_EXTENT_M = 512.0
METRE_PROFILE = {
    "standing_person_height": 1.75,
    "actor_collision_radius": 0.23,
    "navigation_cell": 0.25,
    "standard_door_width": 0.90,
    "standard_door_height": 2.10,
    "standard_storey_height": 3.00,
    "interior_wall_thickness": 0.20,
    "exterior_wall_thickness": 0.30,
}


def historical_profile(data, *, location, accuracy_note):
    """Apply the v2 metre contract without changing any authored geometry.

    Large real-world structures must fit the chosen bounds at their measured
    dimensions. Scaling an old 32m puzzle up/down is deliberately absent here.
    """
    bounds = data.get("bounds", [])
    if len(bounds) != 2 or any(type(n) not in (int, float) or not 1 <= n <= SCHEMA_V2_MAX_EXTENT_M for n in bounds):
        raise ValueError("Special operations require metre bounds in [1,512]")
    data["schema_version"] = 2
    data["historical"] = {
        "location": location,
        "accuracy_note": accuracy_note,
    }
    data.setdefault("scenery", [])
    data.setdefault("environment", {}).setdefault("ground_surface", "concrete")
    return data

COVER_DEFAULTS = {
    "table": "low", "desk": "low", "sofa": "low", "bed": "low",
    "cabinet": "full", "bookshelf": "full", "plant": "none",
    "chair": "none", "crate": "low", "rug": "none",
}
ALTERNATIVES = {
    "M01": {"e1": (12.25, 12.6), "e2": (6.3, 11.8), "e3": (18.1, 12.5), "e4": (13.25, 6.15), "e5": (5.4, 8.6), "e6": (18.7, 7.5)},
    "M01H": {"e1": (12.4, 12.3), "e2": (6.3, 11.8), "e3": (18.1, 12.5), "e4": (13.25, 6.15), "e5": (5.4, 8.6), "e6": (18.7, 7.5), "house_extra1": (11.7, 8.4), "house_extra2": (7.5, 8.0)},
    "M02": {"a_e1": (8.3, 12), "a_e2": (6.5, 7.7), "a_e3": (17.7, 7.5)},
    "M02H": {"a_e1": (8.3, 12), "a_e2": (6.5, 7.7), "a_e3": (17.7, 7.5), "archive_extra1": (15.2, 12), "archive_extra2": (9.3, 4)},
    "M03": {"b_e1": (8.2, 13.2), "b_e2": (4.3, 8.2), "b_e3": (10.8, 3.5), "b_e4": (17.7, 8)},
    "M03H": {"b_e1": (8.2, 13.2), "b_e2": (4.3, 8.2), "b_e3": (10.8, 3.5), "b_e4": (17.7, 8), "depot_extra1": (12.7, 8.7), "depot_extra2": (16, 13.7)},
}


def upgrade(data):
    data["default_seed"] = data["seed"]
    data["win"] = [{"type": "neutralize_all"}, {"type": "secure_all_civilians"}]
    data["fail"] = [{"type": "no_civilian_loss"}]
    data["variant"] = "challenge" if data["id"].endswith("H") else "normal"
    data["modifiers"] = []
    data["stars"] = [
        {"id": "single_plan", "label": "단일 계획", "stat": "plan_revisions", "op": "eq", "value": 0},
        {"id": "no_stun", "label": "스턴 미사용", "stat": "stuns_used", "op": "eq", "value": 0},
        {"id": "no_hits", "label": "피격 0", "stat": "hits_taken", "op": "eq", "value": 0},
        {"id": "small_team", "label": "소수 투입", "stat": "units_deployed", "op": "lte", "value": max(1, len(data["units"]) - 1)},
        {"id": "no_reload", "label": "재장전 0", "stat": "reloads", "op": "eq", "value": 0},
        {"id": "no_kills", "label": "무사살", "stat": "kills", "op": "eq", "value": 0},
    ]
    if data["id"] == "T01":
        data["stars"] = [star for star in data["stars"] if star["id"] != "no_kills"]
    for prop in data["props"]:
        prop["cover"] = COVER_DEFAULTS[prop["type"]]
    for enemy in data["enemies"]:
        enemy["enemy_type"] = "normal"
        if enemy["id"] not in ALTERNATIVES.get(data["id"], {}):
            continue
        first = {key: deepcopy(enemy[key]) for key in ("x", "z", "facing", "patrol") if key in enemy}
        second = deepcopy(first)
        second["x"], second["z"] = ALTERNATIVES[data["id"]][enemy["id"]]
        enemy["spawns"] = [first, second]
    return data
