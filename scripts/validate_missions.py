#!/usr/bin/env python3
"""Validate arbitrary authored mission JSON with strict schema + the real Godot nav.

No third-party Python dependencies. This never rewrites maps or their manifest.
"""
from __future__ import annotations

import argparse
import copy
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
ID = re.compile(r"^[A-Za-z][A-Za-z0-9_-]{0,63}$")
GROUPS = ("rooms", "walls", "doors", "props", "units", "enemies", "civilians")
OPTIONAL = {"briefing", "subtitle", "description", "title_en", "description_en", "win", "fail", "stars", "variant", "modifiers", "default_seed", "base_id", "challenge", "custom", "loadout", "roster", "environment"}
V2_OPTIONAL = {"historical", "scenery", "walkable_areas", "interactive_targets"}
V5_OPTIONAL = {"noise_discipline"}
V6_OPTIONAL = {"roe"}
CURRENT_SCHEMA_VERSION = 6
V3_DOOR_FIELDS = {"kick_resistance", "reinforced"}
TOP = {"schema_version", "id", "revision", "title", "seed", "bounds", "focus", *GROUPS, "objectives"} | OPTIONAL
RECT = {"id", "x", "z", "w", "d"}
GEOMETRY_FIELDS = {"height", "base_height", "material", "opacity", "resistance", "opaque", "penetration_resistance"}
ACTOR_FIELDS = {"stance", "movement_mode", "hold_position", "reserve_ammo", "body_facing", "aim_progress", "injury", "injury_status", "mobility_multiplier", "velocity_x", "velocity_z", "awareness_state", "awareness_confidence", "observation_source", "exposure", "aim_state", "action_multiplier", "reload_duration", "weapon_height"}
MATERIALS = {"wood", "concrete", "metal", "fabric", "glass", "masonry", "plaster", "foliage", "steel", "drywall", "brick", "cloth"}
SURFACES = {"concrete", "tile", "wood", "carpet", "gravel"}
AWARENESS = {"UNAWARE", "DETECTED", "IDENTIFIED", "TRACKING", "SUSPICIOUS"}
SOURCES = {"none", "sight", "sound", "report"}
LOADOUT_FIELDS = {"weapon", "equipment", "sidearm", "armor", "helmet", "attachments", "appearance", "preset"}
FIELDS = {
    "rooms": RECT | {"label", "color", "indoor", "lighting", "floor_surface"}, "walls": RECT | {"thin"} | GEOMETRY_FIELDS,
    "doors": RECT | {"axis", "label", "state", "swing_sign", "hinge_side", "locked", "hp", "durability", "destroyed", "progress", "initial_states"} | GEOMETRY_FIELDS,
    "props": RECT | {"type", "rotation", "solid", "cover"} | GEOMETRY_FIELDS,
    "units": {"id", "name", "role", "x", "z", "facing", "weapon", "hp", "ammo", "stuns", "smokes", "charges", "breaches", "cameras", "vision_range", "fov", "trait", "roster_id", "base_id", "equipment"} | ACTOR_FIELDS | LOADOUT_FIELDS,
    "enemies": {"id", "name", "x", "z", "facing", "weapon", "hp", "ammo", "vision_range", "fov", "patrol", "target", "passive", "training", "strength","enemy_type", "response_role", "spawns"} | ACTOR_FIELDS,
    "civilians": {"id", "name", "x", "z", "facing", "hp", "secured"} | ACTOR_FIELDS,
}
MAX_COUNTS = {"rooms": 64, "walls": 512, "doors": 64, "props": 512, "units": 4, "enemies": 32, "civilians": 32}
RULES = {"neutralize_all", "secure_all_civilians", "reach_zone", "before_alert", "time_limit", "escort_to_zone", "no_civilian_loss"}
V2_RULES = {"targets_complete", "no_shots"}
V4_RULES = {"rooms_cleared"}
MODIFIERS = {"night", "dim", "low_ammo", "fast_reaction", "no_stun"}
STAR_STATS = {"plan_revisions", "stuns_used", "hits_taken", "units_deployed", "reloads", "kills", "arrests", "shots_fired", "command_failures", "losses", "duration", "time", "civilian_losses"}
V6_STAR_STATS = {"civilian_damage", "unit_damage"}
COVER_DEFAULTS = {"table": "low", "desk": "low", "sofa": "low", "bed": "low", "cabinet": "full", "bookshelf": "full", "plant": "none", "chair": "none", "crate": "low", "rug": "none", "vehicle": "full", "pillar": "full"}
MAX_COMBINATIONS = 65536
CQB_IDS = ("SH01", "SH02", "SH03", "SH04", "SH05_PRECISION", "SH05_HIGH_INTENSITY", *(f"CQB{index:02}" for index in range(1, 13)))


def strict_json(text: str):
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise ValueError(f"duplicate JSON key: {key}")
            result[key] = value
        return result

    def invalid(value):
        raise ValueError(f"non-finite JSON number: {value}")
    return json.loads(text, object_pairs_hook=pairs, parse_constant=invalid)


def number(value) -> bool:
    return type(value) in (int, float) and math.isfinite(value)


def prop_assets() -> dict[str, str]:
    source = (ROOT / "game/scripts/environment_assets.gd").read_text()
    block = re.search(r"const ASSETS\s*:?=\s*\{(.*?)\n\}", source, re.S)
    if not block:
        raise ValueError("Cannot find renderer ASSETS mapping; update the validator adapter")
    mapping = dict(re.findall(r'"([a-z_]+)"\s*:\s*preload\("(res://[^"]+)"\)', block[1]))
    if not mapping:
        raise ValueError("Renderer ASSETS mapping has no readable resources")
    procedural = re.search(r"const PROCEDURAL_TYPES(?:\s*:\s*Array\[String\])?\s*:?=\s*\[(.*?)\]", source, re.S)
    world_source = (ROOT / "game/scripts/world_view.gd").read_text()
    prop_renderer = world_source.split("func _build_prop(", 1)[-1].split("\nfunc ", 1)[0]
    for kind in re.findall(r'"([a-z_]+)"', procedural[1] if procedural else ""):
        if not re.search(r'^\s*"' + re.escape(kind) + r'":\s*$', prop_renderer, re.M):
            raise ValueError(f"Procedural prop {kind} has no actual _build_prop renderer branch")
        if kind in mapping:
            raise ValueError(f"Duplicate procedural/imported prop registration: {kind}")
        mapping[kind] = "procedural:" + kind
    return mapping


def historical_assets() -> dict[str, dict]:
    """Read the same allowlist as the runtime historical scenery renderer."""
    path = ROOT / "game/assets/historical/registry.json"
    if not path.is_file():
        return {}
    registry = strict_json(path.read_text())
    if not isinstance(registry, dict) or not all(isinstance(key, str) and ID.fullmatch(key) and isinstance(entry, dict) for key, entry in registry.items()):
        raise ValueError("Historical registry must map stable asset identifiers to entries")
    return registry


def rectangle(obj):
    width, depth = obj["w"], obj["d"]
    if abs(math.sin(obj.get("rotation", 0))) > 0.7:
        width, depth = depth, width
    return (obj["x"] - width / 2, obj["z"] - depth / 2, obj["x"] + width / 2, obj["z"] + depth / 2)


def overlap(a, b):
    a, b = rectangle(a), rectangle(b)
    return min(a[2], b[2]) - max(a[0], b[0]) > 1e-6 and min(a[3], b[3]) - max(a[1], b[1]) > 1e-6


def validate_document(data, kinds: set[str]) -> list[str]:
    errors: list[str] = []

    def check(ok, path, message):
        if not ok:
            errors.append(f"{path}: {message}")

    def shape(obj, allowed, required, path):
        if not isinstance(obj, dict):
            errors.append(f"{path}: expected object")
            return False
        check(not (set(obj) - allowed), path, f"unsupported fields: {sorted(set(obj) - allowed)}")
        check(not (required - set(obj)), path, f"missing fields: {sorted(required - set(obj))}")
        return not (required - set(obj))

    version = data.get("schema_version", 1) if isinstance(data, dict) and type(data.get("schema_version")) is int else 1
    v2 = version >= 2
    max_extent = 512 if v2 else 32
    if not shape(data, TOP | (V2_OPTIONAL if v2 else set()) | (V5_OPTIONAL if version >= 5 else set()) | (V6_OPTIONAL if version >= 6 else set()), TOP - OPTIONAL, "$ "):
        return errors
    check(type(data["schema_version"]) is int and 1 <= data["schema_version"] <= CURRENT_SCHEMA_VERSION, "schema_version", "expected integer in [1,6]")
    if "noise_discipline" in data:
        check(isinstance(data["noise_discipline"], str) and data["noise_discipline"] in {"verbal", "hand_signals"}, "noise_discipline", "expected verbal or hand_signals string")
    if "roe" in data:
        check(isinstance(data["roe"], str) and data["roe"] in {"precision", "high_intensity"}, "roe", "expected precision or high_intensity string")
    check(type(data["revision"]) is int and data["revision"] >= 1, "revision", "expected positive integer")
    check(type(data["seed"]) is int and 0 <= data["seed"] <= 2**31 - 1, "seed", "expected nonnegative safe JSON integer")
    check(isinstance(data["id"], str) and bool(ID.fullmatch(data["id"])), "id", "expected stable ASCII identifier")
    for key, limit in (("title", 128), ("subtitle", 128), ("description", 2000), ("title_en", 128), ("description_en", 2000)):
        if key in data:
            check(isinstance(data[key], str) and 0 < len(data[key]) <= limit, key, f"expected nonempty text, max {limit} characters")
    bounds = data["bounds"]
    valid_bounds = isinstance(bounds, list) and len(bounds) == 2 and all(number(n) and 1 <= n <= max_extent for n in bounds)
    check(valid_bounds, "bounds", f"expected two finite dimensions in [1, {max_extent}] for this version")
    if not valid_bounds:
        return errors

    def point(value, path):
        valid = isinstance(value, list) and len(value) == 2 and all(number(v) for v in value)
        check(valid, path, "expected [finite x, finite z]")
        if valid:
            check(0 <= value[0] <= bounds[0] and 0 <= value[1] <= bounds[1], path, "point lies outside bounds")

    point(data["focus"], "focus")

    catalog_path = ROOT / "game/data/equipment_catalog.json"
    catalog = strict_json(catalog_path.read_text()) if catalog_path.is_file() else {}
    tool_ids = {item["id"] for item in catalog.get("equipment", [])} or {"stun", "smoke", "breach"}

    def equipment(value, path):
        if isinstance(value, str):
            check(value == "none" or value in tool_ids, path, "unknown equipment ID")
            counts = {} if value == "none" else {value: 1}
        elif isinstance(value, list):
            valid = len(value) <= 3 and all(isinstance(slot, str) and slot in tool_ids for slot in value)
            check(valid, path, "expected known equipment IDs in up to three slots")
            if not valid: return
            counts = {slot: value.count(slot) for slot in set(value)}
        elif shape(value, tool_ids, set(), path):
            valid = all(type(count) is int and 0 <= count <= 2 for count in value.values())
            check(valid, path, "expected integer equipment counts in [0,2]")
            if not valid: return
            counts = value
        else:
            return
        # Existing two-slot plans can include two breach charges.
        if sum(counts.values()) > 2:
            check(counts.get("breach", 0) <= 1, path, "equipment exceeds one large slot")
            check(sum(count for slot, count in counts.items() if slot != "breach") <= 2, path, "equipment exceeds two small slots")

    def customization(choice, path):
        for field, group in (("sidearm", "sidearms"), ("armor", "armor"), ("helmet", "helmets")):
            if field not in choice: continue
            identifiers = {item["id"] for item in catalog.get(group, [])} | {"none"}
            check(isinstance(choice[field], str) and choice[field] in identifiers, path + "." + field, "unknown equipment ID")
        if "attachments" in choice:
            items = choice["attachments"]
            definitions = {item["id"]: item for item in catalog.get("attachments", [])}
            valid = isinstance(items, list) and len(items) <= 3 and all(isinstance(item, str) and item in definitions for item in items)
            check(valid, path + ".attachments", "expected up to three known attachment IDs")
            if valid:
                check(len(set(items)) == len(items), path + ".attachments", "duplicate attachment")
                slots = [definitions[item].get("slot", item) for item in items]
                check(len(set(slots)) == len(slots), path + ".attachments", "attachments share a mount")
                weapon = choice.get("weapon", "standard")
                check(all(weapon in definitions[item].get("weapons", [weapon]) for item in items), path + ".attachments", "attachment is incompatible with weapon")
        if "preset" in choice:
            presets = {item["id"] for item in catalog.get("presets", [])} | {"custom"}
            check(isinstance(choice["preset"], str) and choice["preset"] in presets, path + ".preset", "unknown preset")
        if "appearance" in choice and shape(choice["appearance"], {"name", "callsign", "color", "patch"}, set(), path + ".appearance"):
            appearance = choice["appearance"]
            for field, limit in (("name", 48), ("callsign", 32)):
                if field in appearance:
                    valid_label = isinstance(appearance[field], str) and len(appearance[field]) <= limit
                    check(valid_label, path + ".appearance." + field, "personal label exceeds limit")
                    if valid_label: check(all(ord(char) >= 32 and ord(char) != 127 for char in appearance[field]), path + ".appearance." + field, "control characters in personal label")
            if "color" in appearance:
                check(isinstance(appearance["color"], str) and bool(re.fullmatch(r"#[0-9a-fA-F]{6}", appearance["color"])), path + ".appearance.color", "expected #RRGGBB")
            if "patch" in appearance:
                patches = catalog.get("appearance", {}).get("patches", [])
                check(isinstance(appearance["patch"], str) and appearance["patch"] in patches, path + ".appearance.patch", "unknown patch")

    if "default_seed" in data:
        check(type(data["default_seed"]) is int and 0 <= data["default_seed"] <= 2**31 - 1, "default_seed", "expected nonnegative safe JSON integer")
    if "base_id" in data:
        check(isinstance(data["base_id"], str) and bool(ID.fullmatch(data["base_id"])), "base_id", "expected stable identifier")
    if "challenge" in data:
        check(type(data["challenge"]) is bool, "challenge", "expected boolean")
    if "custom" in data:
        check(type(data["custom"]) is bool, "custom", "expected boolean")
    environment_fields = {"time_of_day", "lighting"} | ({"biome", "ground_color", "water", "ground_surface", "water_level"} if v2 else set())
    if "environment" in data and shape(data["environment"], environment_fields, set(), "environment"):
        environment = data["environment"]
        if "time_of_day" in environment: check(environment["time_of_day"] in ("day", "dim", "night"), "environment.time_of_day", "unknown lighting environment")
        if "lighting" in environment: check(number(environment["lighting"]) and 0 <= environment["lighting"] <= 1, "environment.lighting", "expected finite lighting in [0,1]")
        if "biome" in environment: check(isinstance(environment["biome"], str) and 0 < len(environment["biome"]) <= 64, "environment.biome", "expected biome name, max 64 characters")
        if "ground_surface" in environment: check(isinstance(environment["ground_surface"], str) and environment["ground_surface"] in (SURFACES | ({"ship_deck"} if v2 else set())), "environment.ground_surface", "unknown ground surface")
        if "water" in environment: check(type(environment["water"]) is bool, "environment.water", "expected boolean")
        if "water_level" in environment: check(number(environment["water_level"]) and -16 <= environment["water_level"] <= 0, "environment.water_level", "expected finite water height in [-16,0] metres")
        if environment.get("water") is True: check(isinstance(data.get("walkable_areas"), list) and bool(data["walkable_areas"]), "walkable_areas", "water maps require explicit allowed actor floor")
        if "ground_color" in environment: check(isinstance(environment["ground_color"], str) and bool(re.fullmatch(r"#[0-9a-fA-F]{6}", environment["ground_color"])), "environment.ground_color", "expected #RRGGBB")
    if v2 and "historical" in data and shape(data["historical"], {"location", "location_en", "accuracy_note", "accuracy_note_en"}, {"location", "accuracy_note"}, "historical"):
        for key, value in data["historical"].items():
            limit = 256 if key.startswith("location") else 2000
            check(isinstance(value, str) and 0 < len(value) <= limit, "historical." + key, f"expected nonempty fictional dossier text, max {limit} characters")
    if "loadout" in data:
        loadout = data["loadout"]
        if not isinstance(loadout, dict) or len(loadout) > 8:
            errors.append("loadout: expected up to eight keyed equipment choices")
        else:
            for key, choice in loadout.items():
                path = "loadout." + str(key)
                if not shape(choice, LOADOUT_FIELDS, set(), path): continue
                if "weapon" in choice: check(choice["weapon"] in ("standard", "light", "shotgun", "suppressed"), path, "unknown weapon")
                if "equipment" in choice: equipment(choice["equipment"], path + ".equipment")
                customization(choice, path)
    if "roster" in data:
        roster = data["roster"]
        if not isinstance(roster, list) or len(roster) > 8:
            errors.append("roster: expected up to eight selected roster entries")
        else:
            for index, member in enumerate(roster):
                path = f"roster[{index}]"
                if not shape(member, {"id", "base_id", "name", "trait"}, {"id"}, path): continue
                for key in ("id", "base_id"):
                    if key in member: check(isinstance(member[key], str) and bool(ID.fullmatch(member[key])), path + "." + key, "expected safe identifier")
                if "name" in member: check(isinstance(member["name"], str) and 0 < len(member["name"]) <= 128, path + ".name", "expected nonempty name")
                if "trait" in member: check(member["trait"] in ("", "breacher", "marksman", "cautious", "rescuer", "hold_after_hit"), path + ".trait", "unknown fixed trait")
    if "variant" in data:
        check(data["variant"] in {"normal", "standard", "base", "challenge", "hostage", "escort", "infiltration", "timed", "arrest"}, "variant", "unknown operation type")
    if "modifiers" in data:
        values = data["modifiers"]
        check(isinstance(values, list) and len(values) <= len(MODIFIERS) and all(isinstance(v, str) and v in MODIFIERS for v in values) and len(set(v for v in values if isinstance(v, str))) == len(values), "modifiers", "expected distinct known modifier IDs")
    for key in ("win", "fail"):
        if key not in data:
            continue  # Existing schema version 1 author files keep their old defaults.
        rules = data[key]
        if not isinstance(rules, list) or len(rules) > 16 or (key == "win" and not rules):
            errors.append(key + ": expected " + ("1–16" if key == "win" else "0–16") + " rule objects")
            continue
        for i, rule in enumerate(rules):
            path = f"{key}[{i}]"
            if not isinstance(rule, dict):
                errors.append(path + ": expected rule object")
                continue
            kind = rule.get("type")
            check(isinstance(kind, str) and kind in (RULES | (V2_RULES if v2 else set()) | (V4_RULES if version >= 4 else set())), path + ".type", "unknown rule")
            allowed = {"type"}
            if kind in ("reach_zone", "escort_to_zone"):
                allowed.add("zone")
                zone = rule.get("zone")
                valid = isinstance(zone, list) and len(zone) == 4 and all(number(v) for v in zone)
                check(valid, path + ".zone", "expected [center x, center z, width, depth]")
                if valid:
                    check(zone[2] > 0 and zone[3] > 0 and zone[0] - zone[2] / 2 >= 0 and zone[1] - zone[3] / 2 >= 0 and zone[0] + zone[2] / 2 <= bounds[0] and zone[1] + zone[3] / 2 <= bounds[1], path + ".zone", "zone extends outside bounds or has nonpositive dimensions")
            if kind == "time_limit":
                allowed.add("seconds")
                check(number(rule.get("seconds")) and 0 < rule["seconds"] <= 3600, path + ".seconds", "expected finite seconds in (0,3600]")
            if kind == "targets_complete":
                allowed.add("targets")
                targets = rule.get("targets")
                valid_targets = isinstance(targets, list) and 1 <= len(targets) <= 64 and all(isinstance(target, str) and ID.fullmatch(target) for target in targets)
                check(valid_targets, path + ".targets", "expected 1–64 stable target IDs")
                if valid_targets: check(len(set(targets)) == len(targets), path + ".targets", "duplicate target ID")
            if kind == "rooms_cleared" and version >= 4:
                allowed.add("room_ids")
                if "room_ids" in rule:
                    room_ids = rule["room_ids"]
                    valid_rooms = isinstance(room_ids, list) and 1 <= len(room_ids) <= 64 and all(isinstance(room_id, str) and ID.fullmatch(room_id) for room_id in room_ids)
                    check(valid_rooms, path + ".room_ids", "expected 1–64 stable room IDs")
                    if valid_rooms: check(len(set(room_ids)) == len(room_ids), path + ".room_ids", "duplicate room ID")
            # Omitting room_ids selects all authored rooms. Keep legacy rules'
            # required fields and mission dictionaries unchanged.
            shape(rule, allowed, {"type"} if kind == "rooms_cleared" else allowed, path)
    if "stars" in data:
        stars = data["stars"]
        if not isinstance(stars, list) or len(stars) > 16:
            errors.append("stars: expected up to 16 star objectives")
        else:
            star_ids = set()
            for i, star in enumerate(stars):
                path = f"stars[{i}]"
                if not shape(star, {"id", "label", "stat", "op", "value", "type"}, {"id", "label"}, path): continue
                valid_id = isinstance(star["id"], str) and bool(ID.fullmatch(star["id"]))
                check(valid_id, path + ".id", "expected stable identifier")
                if valid_id:
                    check(star["id"] not in star_ids, path + ".id", "duplicate star ID")
                    star_ids.add(star["id"])
                check(isinstance(star["label"], str) and 0 < len(star["label"]) <= 128, path + ".label", "expected nonempty label")
                if "type" in star:
                    check(star["type"] in ("completion", "survivors", "par_time"), path + ".type", "unknown legacy medal type")
                    if star.get("type") == "par_time": check(number(star.get("value")) and star["value"] > 0, path + ".value", "par time requires positive seconds")
                    check(not {"stat", "op"} & set(star), path, "legacy medals cannot also use stat/op")
                else:
                    allowed_stats = STAR_STATS | (V6_STAR_STATS if version >= 6 else set())
                    allowed_ops = ("eq", "lte", "gte") if version >= 6 else ("eq", "lte")
                    check(isinstance(star.get("stat"), str) and star["stat"] in allowed_stats, path + ".stat", "unknown run statistic")
                    check(star.get("op") in allowed_ops, path + ".op", "expected " + ", ".join(allowed_ops))
                    check(number(star.get("value")) and star["value"] >= 0, path + ".value", "expected finite nonnegative target")
                    # New v6 authoring follows Godot's existing numeric target
                    # bound without changing the historical v1–5 Python contract.
                    if version >= 6:
                        check(number(star.get("value")) and star["value"] <= 1e9, path + ".value", "target exceeds 1000000000")
    objectives = data["objectives"]
    check(isinstance(objectives, list) and 0 < len(objectives) <= 16 and all(isinstance(v, str) and 0 < len(v) <= 500 for v in objectives), "objectives", "expected 1–16 nonempty text objectives")
    if "briefing" in data:
        briefing = data["briefing"]
        if shape(briefing, {"difficulty", "estimated_minutes", "threat", "tip"}, set(), "briefing"):
            check(all(isinstance(v, str) and 0 < len(v) <= 1000 for v in briefing.values()), "briefing", "all values must be nonempty text")
    ids: set[str] = set()
    if v2:
        registry = historical_assets() if data.get("scenery") else {}
        for group, limit in (("scenery", 512), ("walkable_areas", 128), ("interactive_targets", 64)):
            if group not in data: continue
            entries = data[group]
            if not isinstance(entries, list):
                errors.append(group + ": expected array")
                continue
            check(len(entries) <= limit and (group != "walkable_areas" or bool(entries)), group, f"expected {'1–' if group == 'walkable_areas' else '0–'}{limit} entries")
            for index, obj in enumerate(entries):
                path = f"{group}[{index}]"
                allowed = {"id", "asset", "x", "z", "rotation", "scale", "height", "cutaway"} if group == "scenery" else RECT
                required = {"id", "asset", "x", "z"} if group == "scenery" else RECT
                if group == "interactive_targets": allowed = required = RECT | {"label", "action", "duration"}
                if not shape(obj, allowed, required, path): continue
                valid_id = isinstance(obj["id"], str) and bool(ID.fullmatch(obj["id"]))
                check(valid_id, path + ".id", "expected stable ASCII identifier")
                if valid_id:
                    check(obj["id"] not in ids, path + ".id", "duplicate mission-wide identifier")
                    ids.add(obj["id"])
                point([obj["x"], obj["z"]], path)
                if group == "scenery":
                    check(isinstance(obj["asset"], str) and obj["asset"] in registry, path + ".asset", "unregistered special operations renderer asset")
                    if "cutaway" in obj: check(type(obj["cutaway"]) is bool, path + ".cutaway", "expected boolean")
                    if "rotation" in obj: check(number(obj["rotation"]), path + ".rotation", "expected finite radians")
                    if "scale" in obj: check(number(obj["scale"]) and 0.01 <= obj["scale"] <= 10, path + ".scale", "expected finite uniform scale in [0.01,10]")
                    if "height" in obj: check(number(obj["height"]) and -64 <= obj["height"] <= 64, path + ".height", "expected placement height in [-64,64] metres")
                else:
                    for key in ("w", "d"): check(number(obj[key]) and 0.01 <= obj[key] <= max_extent, path + "." + key, f"expected finite positive extent ≤{max_extent}")
                    if all(number(obj[key]) for key in ("x", "z", "w", "d")):
                        rect = rectangle(obj)
                        check(rect[0] >= 0 and rect[1] >= 0 and rect[2] <= bounds[0] and rect[3] <= bounds[1], path, "rectangle extends outside bounds")
                if group == "interactive_targets":
                    check(isinstance(obj["label"], str) and 0 < len(obj["label"]) <= 128, path + ".label", "expected target label")
                    check(obj["action"] in ("recover", "disable", "inspect", "board"), path + ".action", "unknown target action")
                    check(number(obj["duration"]) and 0 < obj["duration"] <= 60, path + ".duration", "expected finite seconds in (0,60]")
    for group in GROUPS:
        values = data[group]
        if not isinstance(values, list):
            errors.append(f"{group}: expected array")
            continue
        check(len(values) <= MAX_COUNTS[group], group, f"maximum authoring budget is {MAX_COUNTS[group]}")
        if group in ("rooms", "units"):
            check(bool(values), group, "at least one entry is required")
        for index, obj in enumerate(values):
            path = f"{group}[{index}]"
            required = set(RECT) if group in ("rooms", "walls", "doors", "props") else {"id", "x", "z"}
            required |= {"axis"} if group == "doors" else set()
            required |= {"type"} if group == "props" else set()
            required |= {"name", "role", "facing", "weapon"} if group == "units" else set()
            allowed_fields = FIELDS[group] | ({"render"} if v2 and group == "walls" else ({"base_height"} if v2 and group == "rooms" else set()))
            if version >= 3 and group == "doors": allowed_fields |= V3_DOOR_FIELDS
            if not shape(obj, allowed_fields, required, path):
                continue
            entity_id = obj["id"]
            valid_id = isinstance(entity_id, str) and bool(ID.fullmatch(entity_id))
            check(valid_id, path + ".id", "expected stable ASCII identifier")
            if valid_id:
                check(entity_id not in ids, path + ".id", f"duplicate mission-wide identifier {entity_id}")
                ids.add(entity_id)
            point([obj["x"], obj["z"]], path)
            if group in ("rooms", "walls", "doors", "props"):
                for key in ("w", "d"):
                    check(number(obj[key]) and 0 < obj[key] <= max_extent, path + "." + key, f"expected finite positive extent ≤{max_extent}")
                if all(number(obj[k]) for k in ("x", "z", "w", "d")) and number(obj.get("rotation", 0)):
                    rect = rectangle(obj)
                    check(rect[0] >= -1e-6 and rect[1] >= -1e-6 and rect[2] <= bounds[0] + 1e-6 and rect[3] <= bounds[1] + 1e-6, path, "rectangle extends outside bounds")
            for key in ("name", "label", "role"):
                if key in obj:
                    check(isinstance(obj[key], str) and 0 < len(obj[key]) <= 128, path + "." + key, "expected nonempty text ≤128 characters")
            if "trait" in obj:
                check(obj["trait"] in ("", "breacher", "marksman", "cautious", "rescuer", "hold_after_hit"), path + ".trait", "unknown fixed trait")
            for key in ("roster_id", "base_id"):
                if key in obj: check(isinstance(obj[key], str) and bool(ID.fullmatch(obj[key])), path + "." + key, "expected safe identifier")
            if "equipment" in obj: equipment(obj["equipment"], path + ".equipment")
            if group == "units": customization(obj, path)
            if "color" in obj:
                check(isinstance(obj["color"], str) and bool(re.fullmatch(r"#[0-9a-fA-F]{6}", obj["color"])), path + ".color", "expected #RRGGBB")
            for key in ("target", "passive", "training", "secured", "solid", "thin", "hold_position", "locked", "destroyed", "indoor", "opaque", "render", "reinforced"):
                if key in obj:
                    check(type(obj[key]) is bool, path + "." + key, "expected boolean")
            for key in ("facing", "rotation", "body_facing"):
                if key in obj:
                    check(number(obj[key]), path + "." + key, "expected finite radians")
            for key in ("height", "base_height", "weapon_height"):
                height_limit = 64 if v2 and group in ("rooms", "walls", "doors", "props") and key != "weapon_height" else 8
                if key in obj: check(number(obj[key]) and 0 <= obj[key] <= height_limit, path + "." + key, f"expected finite height in [0,{height_limit}]")
            for key in ("opacity", "lighting", "progress", "aim_progress", "mobility_multiplier", "awareness_confidence", "exposure"):
                if key in obj: check(number(obj[key]) and 0 <= obj[key] <= 1, path + "." + key, "expected finite value in [0,1]")
            for key in ("resistance", "durability", "penetration_resistance"):
                if key in obj: check(number(obj[key]) and 0 <= obj[key] <= 1000, path + "." + key, "expected finite value in [0,1000]")
            for key in ("velocity_x", "velocity_z"):
                if key in obj: check(number(obj[key]) and -32 <= obj[key] <= 32, path + "." + key, "expected finite velocity in [-32,32]")
            if "reserve_ammo" in obj: check(type(obj["reserve_ammo"]) is int and 0 <= obj["reserve_ammo"] <= 10000, path + ".reserve_ammo", "expected finite integer reserve ammunition in [0,10000]")
            if "action_multiplier" in obj: check(number(obj["action_multiplier"]) and 1 <= obj["action_multiplier"] <= 4, path + ".action_multiplier", "expected finite action multiplier in [1,4]")
            if "reload_duration" in obj: check(number(obj["reload_duration"]) and 0 <= obj["reload_duration"] <= 600, path + ".reload_duration", "expected finite reload seconds in [0,600]")
            for key, allowed in (("material", MATERIALS), ("floor_surface", SURFACES), ("stance", ("standing", "crouched")), ("movement_mode", ("careful", "normal", "fast")), ("injury", ("none", "hurt", "wounded")), ("injury_status", ("none", "hurt", "wounded")), ("aim_state", ("idle", "acquiring", "ready", "lowered")), ("awareness_state", AWARENESS), ("observation_source", SOURCES)):
                if key in obj: check(isinstance(obj[key], str) and obj[key] in allowed, path + "." + key, "unknown state or material")
            if group == "props":
                check(isinstance(obj["type"], str) and obj["type"] in kinds, path + ".type", "no corresponding renderer asset")
                if "cover" in obj:
                    check(obj["cover"] in ("none", "low", "full"), path + ".cover", "expected none, low or full")
                else:
                    check("solid" in obj or obj["type"] in COVER_DEFAULTS, path, "missing solid/cover collision classification")
                rotation = obj.get("rotation", 0)
                if number(rotation):
                    check(abs(rotation / (math.pi / 2) - round(rotation / (math.pi / 2))) < 1e-5, path + ".rotation", "authoring supports quarter turns only; arbitrary rotations disagree with collision")
            if group == "doors":
                if "kick_resistance" in obj: check(number(obj["kick_resistance"]) and 0 <= obj["kick_resistance"] <= 1, path + ".kick_resistance", "expected finite kick success probability in [0,1]")
                check(obj["axis"] in ("x", "z"), path + ".axis", "expected x or z along the doorway width")
                if obj["axis"] in ("x", "z") and number(obj["w"]) and number(obj["d"]):
                    span, thickness = (obj["w"], obj["d"]) if obj["axis"] == "x" else (obj["d"], obj["w"])
                    check(span > max(thickness, 0.46), path, "door axis/span must admit the 0.23m actor radius")
                if "state" in obj:
                    check(obj["state"] in ("CLOSED", "AJAR", "OPEN", "DESTROYED"), path + ".state", "unknown initial door state")
                for key in ("swing_sign", "hinge_side"):
                    if key in obj: check(number(obj[key]) and obj[key] in (-1, 1), path + "." + key, "expected -1 or +1")
                if obj.get("state") == "AJAR" and "progress" in obj: check(number(obj["progress"]) and 0 < obj["progress"] < 1, path + ".progress", "ajar progress must be strictly between closed and open")
                if "initial_states" in obj: check(isinstance(obj["initial_states"], list) and 1 <= len(obj["initial_states"]) <= 3 and all(isinstance(state, str) and state in ("OPEN", "CLOSED", "AJAR") for state in obj["initial_states"]), path + ".initial_states", "expected one to three known initial door states")
            if "weapon" in obj:
                check(obj["weapon"] in ("standard", "light", "shotgun", "suppressed"), path + ".weapon", "unknown weapon identifier")
            if "strength" in obj:
                check(obj["strength"] in ("weak", "medium", "strong"), path + ".strength", "unknown enemy strength")
            if "enemy_type" in obj:
                check(obj["enemy_type"] in ("normal", "sentry", "rusher", "hostage_taker", "guard"), path + ".enemy_type", "unknown enemy type")
            for key, lower, upper in (("hp", 0 if group == "doors" else 1, 1000), ("vision_range", 0.1, 32), ("fov", 1, 360)):
                if key in obj:
                    check(number(obj[key]) and lower <= obj[key] <= upper, path + "." + key, f"expected finite value in [{lower}, {upper}]")
            capacity = 32 if obj.get("weapon") == "light" else (8 if obj.get("weapon") == "shotgun" else 24)
            if group == "units" and catalog:
                weapon_definition = next((item for item in catalog.get("weapons", []) if item["id"] == obj.get("weapon", "standard")), {})
                capacity = int(weapon_definition.get("stats", {}).get("ammo", capacity))
                attached = obj.get("attachments", [])
                if isinstance(attached, list):
                    capacity += sum(int(item.get("modifiers", {}).get("ammo_add", 0)) for item in catalog.get("attachments", []) if item["id"] in attached)
                capacity = max(32, capacity)  # Preserve the Godot legacy author-file bound.
            for key, upper in (("ammo", capacity), ("stuns", 8), ("smokes", 8), ("charges", 8), ("breaches", 8), ("cameras", 2)):
                if key in obj:
                    check(type(obj[key]) is int and 0 <= obj[key] <= upper, path + "." + key, f"expected integer in [0, {upper}]")
            if "response_role" in obj:
                check(isinstance(obj["response_role"], str) and obj["response_role"] in {"guard", "patrol", "reserve"}, path + ".response_role", "unknown response role")
            if "patrol" in obj:
                patrol = obj["patrol"]
                if isinstance(patrol, list) and len(patrol) <= 64:
                    for i, waypoint in enumerate(patrol):
                        point(waypoint, f"{path}.patrol[{i}]")
                else:
                    errors.append(path + ".patrol: expected up to 64 [x,z] points")
            if "spawns" in obj:
                spawns = obj["spawns"]
                if not isinstance(spawns, list) or not 1 <= len(spawns) <= 8:
                    errors.append(path + ".spawns: expected 1–8 candidate objects")
                    continue
                for i, spawn in enumerate(spawns):
                    location = f"{path}.spawns[{i}]"
                    if not shape(spawn, {"x", "z", "facing", "patrol"}, {"x", "z", "facing"}, location): continue
                    point([spawn["x"], spawn["z"]], location)
                    check(number(spawn["facing"]), location + ".facing", "expected finite radians")
                    patrol = spawn.get("patrol", [])
                    if not isinstance(patrol, list) or len(patrol) > 64:
                        errors.append(location + ".patrol: expected up to 64 points")
                    else:
                        for j, waypoint in enumerate(patrol): point(waypoint, f"{location}.patrol[{j}]")
                first = spawns[0]
                if isinstance(first, dict):
                    check(all(first.get(k) == obj.get(k) for k in ("x", "z", "facing")) and first.get("patrol", []) == obj.get("patrol", []), path + ".spawns[0]", "candidate zero must preserve the original fixed spawn and patrol")
    if errors:
        return errors
    target_ids = {target["id"] for target in data.get("interactive_targets", [])}
    room_ids = {room["id"] for room in data["rooms"]}
    for rule in data.get("win", []) + data.get("fail", []):
        if rule.get("type") == "targets_complete":
            check(set(rule["targets"]) <= target_ids, "targets_complete", "rule references an unknown interactive target")
        if rule.get("type") == "rooms_cleared":
            targets = rule.get("room_ids", room_ids)
            check(bool(targets), "rooms_cleared", "at least one authored room must be selected")
            check(set(targets) <= room_ids, "rooms_cleared", "rule references an unknown room")
    combinations = math.prod(len(enemy.get("spawns", [enemy])) for enemy in data["enemies"])
    check(combinations <= MAX_COMBINATIONS, "enemies.spawns", f"Cartesian product exceeds {MAX_COMBINATIONS} combinations")
    check(bool(data["enemies"] or data["civilians"] or any(rule.get("type") in ("reach_zone", "targets_complete", "rooms_cleared") for rule in data.get("win", []))), "objectives", "an authored mission needs at least one actual completion target")
    for index, door in enumerate(data["doors"]):
        for obstacle in data["walls"] + data["doors"][index + 1:] + [p for p in data["props"] if p.get("cover", "full" if p.get("solid", False) else COVER_DEFAULTS.get(p["type"], "none")) != "none"]:
            check(not overlap(door, obstacle), door["id"], f"closed doorway overlaps {obstacle['id']}")
    return errors


def validate_map_assets(data, mapping: dict[str, str]) -> dict:
    # The renderer preloads its complete furniture table even when a mission
    # uses only one kind; every entry is therefore a real startup dependency.
    errors, files = [], {resource for resource in mapping.values() if resource.startswith("res://")}
    manifest = strict_json((ROOT / "asset-manifest.json").read_text())
    registered: dict[str, set[str]] = {}
    for item in manifest["assets"]:
        for entry in item.get("selected_files", []):
            registered.setdefault(entry["path"], set()).add(entry["sha256"])
    for prop in data["props"]:
        if mapping[prop["type"]].startswith("res://"): files.add(mapping[prop["type"]])
    registry = historical_assets() if data.get("scenery") else {}
    for obj in data.get("scenery", []):
        entry = registry[obj["asset"]]
        resource = entry.get("path", "res://assets/historical/" + obj["asset"] + ".glb")
        if not isinstance(resource, str) or not resource.startswith("res://assets/historical/") or ".." in resource:
            errors.append("invalid historical registry resource: " + obj["asset"])
        else:
            files.add(resource)
    # Shared resources are renderer-owned; maps cannot supply arbitrary paths.
    sources = ["game/scripts/actor_visual.gd", "game/scripts/door_geometry.gd"]
    for script in sources:
        files.update(re.findall(r'preload\("(res://assets/[^"]+)"\)', (ROOT / script).read_text()))
    checked = []
    for resource in sorted(files):
        relative = "game/" + resource.removeprefix("res://")
        path = ROOT / relative
        if not path.is_file():
            errors.append(f"asset missing: {relative}")
            continue
        sha = hashlib.sha256(path.read_bytes()).hexdigest()
        expected = registered.get(relative, set())
        if expected != {sha}:
            errors.append(f"asset manifest missing, conflicting or stale hash: {relative}")
        checked.append({"path": relative, "sha256": sha})
    procedural = [{"type":kind,"renderer":"game/scripts/world_view.gd","sha256":hashlib.sha256((ROOT / "game/scripts/world_view.gd").read_bytes()).hexdigest()} for kind, resource in mapping.items() if resource.startswith("procedural:") and any(prop["type"] == kind for prop in data["props"])]
    return {"errors": errors, "files": checked, "procedural": procedural}


# Reuse the engine's actual blockers, door leaf and actor radius. Hypothetically
# opened doors establish structural connectivity; each real leaf is then checked
# on both swing sides independently. This is not an AI/combat playthrough.
GEOMETRY_SCRIPT = r'''extends SceneTree
const Navigation = preload("res://scripts/navigation.gd")
const DoorGeometry = preload("res://scripts/door_geometry.gd")
const ContentGeometry = preload("res://scripts/content_geometry_validator.gd")
var errors: Array[String] = []
var checks: int = 0
var combinations: int = 0
var candidates: int = 0
var nav: RefCounted
var origin: Vector2
var open_ids: Array = []
func check(value: bool, message: String) -> void:
    checks += 1
    if not value: errors.append(message)
func point(obj: Dictionary) -> Vector2:
    return Vector2(float(obj.x), float(obj.z))
func valid_route(start: Vector2, target: Vector2, opened: Array, label: String) -> void:
    var route: Array = nav.path(start, target, opened)
    check(not route.is_empty(), label + ": no route")
    var previous: Vector2 = start
    for raw: Array in route:
        var current: Vector2 = Vector2(raw[0], raw[1])
        check(nav.segment_clear(previous, current, Navigation.RADIUS, opened), label + ": route clips collision")
        previous = current
func check_open_passage(door: Dictionary, opened: Array, label: String) -> void:
    var normal := Vector2.DOWN if door.axis == "x" else Vector2.RIGHT
    var across := Vector2.RIGHT if door.axis == "x" else Vector2.DOWN
    var fronts: Array[Vector2] = []
    var backs: Array[Vector2] = []
    for distance: float in [0.55, 0.8, 1.1]:
        for shift: float in [0.0, -0.2, 0.2]:
            var center: Vector2 = point(door) + across * DoorGeometry.width(door) * shift
            if nav.walkable(center + normal * distance, opened): fronts.append(center + normal * distance)
            if nav.walkable(center - normal * distance, opened): backs.append(center - normal * distance)
    for front: Vector2 in fronts:
        for back: Vector2 in backs:
            if not nav.path(front, back, opened).is_empty():
                valid_route(front, back, opened, label)
                return
    check(false, label + ": no navigable passage between handle-side floor samples")
func candidate(actor: Dictionary, spawn: Dictionary, label: String, challenge: bool) -> Dictionary:
    candidates += 1
    var actor_data: Dictionary = actor.duplicate(true)
    for key: String in spawn: actor_data[key] = spawn[key]
    var before: int = errors.size()
    check(nav.walkable(point(actor_data)), label + ": initial spawn touches a wall, prop, closed doorway or door leaf")
    valid_route(origin, point(actor_data), open_ids, label)
    var previous: Vector2 = point(actor_data)
    var patrol: Array = actor_data.get("patrol", [])
    for raw: Array in patrol:
        var target := Vector2(float(raw[0]), float(raw[1]))
        check(nav.walkable(target), label + ": patrol endpoint initially blocked")
        valid_route(previous, target, open_ids, label + " patrol operable doors")
        if challenge: valid_route(previous, target, open_ids, label + " patrol doors-open")
        previous = target
    if not patrol.is_empty():
        valid_route(previous, point(actor_data), open_ids, label + " patrol return operable doors")
        if challenge: valid_route(previous, point(actor_data), open_ids, label + " patrol return doors-open")
    actor_data["_validation_ok"] = errors.size() == before
    actor_data["_candidate_label"] = label
    return actor_data
func check_combination(choices: Array, index: int, actors: Array) -> void:
    if index < choices.size():
        for actor: Dictionary in choices[index]:
            actors.append(actor)
            check_combination(choices, index + 1, actors)
            actors.pop_back()
        return
    combinations += 1
    # Navigation excludes actors, so candidate route validity is independent of
    # every other choice. Cache it once, assert it for every Cartesian member,
    # then check the inter-actor constraint on the complete selected placement.
    for actor: Dictionary in actors:
        check(bool(actor._validation_ok), "combination " + str(combinations) + " " + str(actor._candidate_label) + ": spawn/reachability/patrol validation failed")
    for i: int in range(actors.size()):
        for j: int in range(i + 1, actors.size()):
            check(point(actors[i]).distance_to(point(actors[j])) >= Navigation.RADIUS * 2.0, "combination " + str(combinations) + " " + str(actors[i]._candidate_label) + "/" + str(actors[j]._candidate_label) + ": overlapping spawns")
func reachable_zone(rect: Array, label: String) -> void:
    var center := Vector2(float(rect[0]), float(rect[1]))
    if nav.walkable(center, open_ids) and not nav.path(origin, center, open_ids).is_empty():
        check(true, label + ": reachable center")
        return
    var found := false
    var width: float = float(rect[2])
    var depth: float = float(rect[3])
    var nx: int = maxi(1, ceili(width / Navigation.CELL))
    var nz: int = maxi(1, ceili(depth / Navigation.CELL))
    for xi: int in range(nx):
        for zi: int in range(nz):
            var p := Vector2(float(rect[0]) - width * 0.5 + (xi + 0.5) * width / nx, float(rect[1]) - depth * 0.5 + (zi + 0.5) * depth / nz)
            if nav.walkable(p, open_ids) and not nav.path(origin, p, open_ids).is_empty():
                found = true
                break
        if found: break
    check(found, label + ": no reachable interior floor sample")
func _initialize() -> void:
    var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
    var doors: Array = data.doors.duplicate(true)
    for door: Dictionary in doors:
        door.state = str(door.get("state", "CLOSED"))
        if door.state == "DESTROYED":
            door.destroyed = true
            door.state = "OPEN"
        door.progress = 1.0 if door.state == "OPEN" else (float(door.get("progress", 0.52)) if door.state == "AJAR" else 0.0)
        open_ids.append(door.id)
    nav = Navigation.new()
    nav.build(data, doors)
    origin = point(data.units[0])
    var challenge: bool = bool(data.get("challenge", str(data.id).ends_with("H")))
    var choices: Array = []
    for actor: Dictionary in data.units + data.enemies + data.civilians:
        var options: Array = []
        var spawns: Array = actor.get("spawns", [actor])
        for i: int in range(spawns.size()):
            options.append(candidate(actor, spawns[i], str(actor.id) + " candidate " + str(i), challenge))
        choices.append(options)
    check_combination(choices, 0, [])
    for room: Dictionary in data.rooms:
        reachable_zone([room.x,room.z,room.w,room.d], str(room.id))
    for target: Dictionary in data.get("interactive_targets", []):
        reachable_zone([target.x,target.z,target.w,target.d], str(target.id))
    for rule: Dictionary in data.get("win",[]):
        if rule.type in ["reach_zone","escort_to_zone"]: reachable_zone(rule.zone, str(rule.type) + " goal")
    for door: Dictionary in doors:
        check(not nav.approach(origin, door, 0.85, open_ids).is_empty(), str(door.id) + ": no reachable handle-side approach")
        var initial_state: String = door.state
        var initial_progress: float = door.progress
        var initial_sign: float = float(door.get("swing_sign", -1.0))
        var other_open: Array = open_ids.duplicate()
        other_open.erase(door.id)
        for sign: float in ([initial_sign] if door.has("swing_sign") else [-1.0, 1.0]):
            door.state = "OPEN"
            door.progress = 1.0
            door.swing_sign = sign
            nav.rebuild()
            check_open_passage(door, other_open, str(door.id) + " opened leaf sign=" + str(sign))
        door.state = initial_state
        door.progress = initial_progress
        door.swing_sign = initial_sign
        nav.rebuild()
    # Run the static draft once after the original physical-door checks. NPC
    # candidate products do not repeat it or become planning body blockers.
    var entry_drills: Dictionary = ContentGeometry.validate_entry_drills(data)
    checks += int(entry_drills.checks)
    for error: String in entry_drills.errors: errors.append(error)
    entry_drills.erase("layouts")
    print("MISSION_GEOMETRY_JSON " + JSON.stringify({"checks":checks,"errors":errors,"candidate_combinations":combinations,"spawn_candidates":candidates,"entry_drills":entry_drills,"engine":Engine.get_version_info().string}))
    quit(0 if errors.is_empty() else 1)
'''


def engine_path(explicit: str | None) -> str:
    candidate = explicit or os.environ.get("GODOT_BIN")
    if candidate:
        return candidate
    bundled = ROOT / ".tools/Godot.app/Contents/MacOS/Godot"
    return str(bundled) if bundled.is_file() else (shutil.which("godot") or "godot")


def validate_geometry(path: Path, engine: str) -> dict:
    with tempfile.TemporaryDirectory(prefix="breach-mission-check-") as folder:
        script = Path(folder) / "geometry.gd"
        script.write_text(GEOMETRY_SCRIPT)
        try:
            process = subprocess.run([engine, "--headless", "--path", str(ROOT / "game"), "--script", str(script), "--", str(path.resolve())], capture_output=True, text=True, timeout=120)
        except (OSError, subprocess.TimeoutExpired) as exc:
            return {"checks": 0, "errors": [f"Godot geometry validator unavailable: {exc}"]}
        output = process.stdout + process.stderr
        summaries = [line.removeprefix("MISSION_GEOMETRY_JSON ") for line in output.splitlines() if line.startswith("MISSION_GEOMETRY_JSON ")]
        if not summaries or re.search(r"SCRIPT ERROR|Parse Error|(^|\n)ERROR:", output):
            return {"checks": 0, "errors": ["Godot geometry runner did not finish cleanly"], "output": output[-8000:]}
        result = json.loads(summaries[-1])
        if process.returncode and not result["errors"]:
            result["errors"].append(f"Godot exited {process.returncode}")
        return result


def catalog_documents(engine: str) -> dict:
    """Read derived operations from the actual runtime catalog, not a mirror."""
    script_text = '''extends SceneTree
const Catalog = preload("res://scripts/mission_catalog.gd")
func _initialize() -> void:
    print("MISSION_CATALOG_JSON " + JSON.stringify(Catalog.missions()))
    quit()
'''
    with tempfile.TemporaryDirectory(prefix="breach-catalog-check-") as folder:
        script = Path(folder) / "catalog.gd"
        script.write_text(script_text)
        process = subprocess.run([engine, "--headless", "--path", str(ROOT / "game"), "--script", str(script)], capture_output=True, text=True, timeout=60)
        output = process.stdout + process.stderr
        summaries = [line.removeprefix("MISSION_CATALOG_JSON ") for line in output.splitlines() if line.startswith("MISSION_CATALOG_JSON ")]
        if process.returncode or not summaries or re.search(r"SCRIPT ERROR|Parse Error|(^|\n)ERROR:", output):
            raise ValueError("runtime catalog did not load cleanly: " + output[-4000:])
        return strict_json(summaries[-1])


def self_test(mapping, engine=None):
    original = strict_json((ROOT / "game/data/tutorial.json").read_text())
    tests = []
    mutations = [
        ("version", lambda d: d.update(schema_version=True)),
        ("boolean-coordinate", lambda d: d["units"][0].update(x=True)),
        ("unknown-field", lambda d: d["units"][0].update(fcaing=1)),
        ("duplicate-id", lambda d: d["units"][1].update(id=d["units"][0]["id"])),
        ("unknown-asset", lambda d: d["props"][0].update(type="missing_asset")),
        ("nonfinite-coordinate", lambda d: d["units"][0].update(z=float("inf"))),
        ("unsupported-rotation", lambda d: d["props"][0].update(rotation=0.23)),
        ("wrong-door-axis", lambda d: d["doors"][0].update(axis="y")),
        ("closed-door-overlap", lambda d: d["doors"][0].update(z=6)),
        ("oversized-map", lambda d: d.update(bounds=[33, 20])),
        ("negative-health", lambda d: d["units"][0].update(hp=-1)),
        ("patrol-outside-map", lambda d: d["enemies"][0].update(patrol=[[100, 5]])),
        ("unknown-win-rule", lambda d: d.update(win=[{"type": "mystery"}])),
        ("unknown-fail-rule", lambda d: d.update(fail=[{"type": "mystery"}])),
        ("missing-zone", lambda d: d.update(win=[{"type": "reach_zone"}])),
        ("zone-outside-map", lambda d: d.update(win=[{"type": "reach_zone", "zone": [0,0,2,2]}])),
        ("empty-win-rules", lambda d: d.update(win=[])),
        ("invalid-time-rule", lambda d: d.update(fail=[{"type": "time_limit", "seconds": 0}])),
        ("extra-rule-field", lambda d: d.update(win=[{"type": "neutralize_all", "probability": 0.5}])),
        ("unknown-star-statistic", lambda d: d["stars"][0].update(stat="experience")),
        ("unknown-star-operation", lambda d: d["stars"][0].update(op="gte")),
        ("duplicate-star-id", lambda d: d["stars"][1].update(id=d["stars"][0]["id"])),
        ("unknown-cover", lambda d: d["props"][0].update(cover="invisible")),
        ("nonboolean-thin-wall", lambda d: d["walls"][0].update(thin="yes")),
        ("unknown-enemy-type", lambda d: d["enemies"][0].update(enemy_type="boss")),
        ("empty-spawn-candidates", lambda d: d["enemies"][0].update(spawns=[])),
        ("unknown-modifier", lambda d: d.update(modifiers=["infinite_ammo"])),
        ("duplicate-modifier", lambda d: d.update(modifiers=["night", "night"])),
        ("oversized-seed", lambda d: d.update(seed=2**31)),
        ("invalid-stance", lambda d: d["units"][0].update(stance="invisible")),
        ("invalid-movement-mode", lambda d: d["units"][0].update(movement_mode="teleport")),
        ("nonboolean-position-hold", lambda d: d["units"][0].update(hold_position="yes")),
        ("negative-reserve-ammunition", lambda d: d["units"][0].update(reserve_ammo=-1)),
        ("fractional-reserve-ammunition", lambda d: d["units"][0].update(reserve_ammo=2.5)),
        ("nonfinite-wall-height", lambda d: d["walls"][0].update(height=float("nan"))),
        ("negative-base-height", lambda d: d["walls"][0].update(base_height=-1)),
        ("unknown-material", lambda d: d["walls"][0].update(material="magic")),
        ("excessive-opacity", lambda d: d["props"][0].update(opacity=1.1)),
        ("nonboolean-opacity", lambda d: d["props"][0].update(opaque=1)),
        ("negative-resistance", lambda d: d["props"][0].update(penetration_resistance=-1)),
        ("invalid-door-hinge", lambda d: d["doors"][0].update(hinge_side=0)),
        ("invalid-door-progress", lambda d: d["doors"][0].update(state="AJAR", progress=1)),
        ("invalid-door-candidates", lambda d: d["doors"][0].update(initial_states=["INVISIBLE"])),
        ("unknown-lighting-environment", lambda d: d.update(environment={"time_of_day": "sunset"})),
        ("nonfinite-environment-lighting", lambda d: d.update(environment={"lighting": float("inf")})),
        ("unknown-environment-field", lambda d: d.update(environment={"weather": "rain"})),
        ("unknown-floor-surface", lambda d: d["rooms"][0].update(floor_surface="lava")),
        ("nonfinite-velocity", lambda d: d["units"][0].update(velocity_x=float("inf"))),
        ("unknown-awareness", lambda d: d["units"][0].update(awareness_state="OMNISCIENT")),
        ("excessive-confidence", lambda d: d["units"][0].update(awareness_confidence=1.1)),
        ("unknown-observation-source", lambda d: d["units"][0].update(observation_source="wallhack")),
    ]
    tests.append(("valid-existing-map", not validate_document(original, set(mapping))))
    enriched = copy.deepcopy(original)
    enriched["environment"] = {"time_of_day": "dim", "lighting": 0.45}
    enriched["modifiers"] = ["dim"]
    enriched["rooms"][0].update(indoor=True, lighting=0.6, floor_surface="tile")
    enriched["walls"][0].update(height=2.6, base_height=0, material="concrete", opacity=1, resistance=4)
    enriched["props"][0].update(height=0.8, material="wood", penetration_resistance=1)
    enriched["doors"][0].update(state="AJAR", progress=0.52, hinge_side=-1.0, swing_sign=1.0, locked=True, hp=70, durability=100, destroyed=False, initial_states=["CLOSED", "AJAR", "OPEN"])
    enriched["units"][0].update(stance="crouched", movement_mode="careful", hold_position=True, reserve_ammo=48, body_facing=0.3, aim_progress=0.8, injury_status="hurt", mobility_multiplier=0.9, velocity_x=-0.1, velocity_z=0.2, awareness_state="IDENTIFIED", awareness_confidence=0.8, observation_source="sight", exposure=0.5, aim_state="acquiring", action_multiplier=1.2, reload_duration=2, weapon_height=0.9)
    tests.append(("valid-complete-realism-fields", not validate_document(enriched, set(mapping))))
    # P1 authoring extends v2 rather than dropping historical map contracts.
    doctrine = copy.deepcopy(enriched)
    doctrine["schema_version"] = 3
    doctrine["doors"][0].update(kick_resistance=0.8, reinforced=True)
    tests.append(("valid-doctrine-version-3", not validate_document(doctrine, set(mapping))))
    for value in (0, 0.25, 0.5, 0.8, 1):
        data = copy.deepcopy(doctrine)
        data["doors"][0]["kick_resistance"] = value
        tests.append(("known-kick-probability:" + str(value), not validate_document(data, set(mapping))))
    for value in (-0.01, 1.01, float("nan"), float("inf"), True, "0.5"):
        data = copy.deepcopy(doctrine)
        data["doors"][0]["kick_resistance"] = value
        tests.append(("invalid-kick-probability:" + str(value), any("kick_resistance" in error for error in validate_document(data, set(mapping)))))
    for value in (0, 1, "true", None):
        data = copy.deepcopy(doctrine)
        data["doors"][0]["reinforced"] = value
        tests.append(("nonboolean-door-reinforcement:" + str(value), any("reinforced" in error for error in validate_document(data, set(mapping)))))
    for version in (1, 2):
        data = copy.deepcopy(doctrine)
        data["schema_version"] = version
        tests.append(("doctrine-fields-require-v3:" + str(version), any("unsupported fields" in error for error in validate_document(data, set(mapping)))))
    data = copy.deepcopy(doctrine)
    data["schema_version"] = CURRENT_SCHEMA_VERSION + 1
    tests.append(("unknown-future-version", any("schema_version" in error for error in validate_document(data, set(mapping)))))
    for version in (2, 3, 4):
        data = copy.deepcopy(original)
        data["schema_version"] = version
        data["bounds"] = [48, 48]
        data["rooms"][0]["base_height"] = 0
        data["walls"][0].update(height=20, render=False)
        data["environment"] = {"ground_surface": "ship_deck", "biome": "urban"}
        data["historical"] = {"location": "Schema fixture", "accuracy_note": "Synthetic validation fixture"}
        data["interactive_targets"] = [{"id": "schema_target", "x": 4, "z": 4, "w": 1, "d": 1, "label": "Inspect", "action": "inspect", "duration": 1}]
        data["win"] = [{"type": "targets_complete", "targets": ["schema_target"]}, {"type": "no_shots"}]
        tests.append(("historical-contract-preserved-v" + str(version), not validate_document(data, set(mapping))))
        data["interactive_targets"][0]["duration"] = float("inf")
        tests.append(("historical-validation-preserved-v" + str(version), any("duration" in error for error in validate_document(data, set(mapping)))))
    # P3 adds only a v4 rule/optional target list. Keep the explicit P1 v3
    # contract above and exercise the new current version independently.
    data = copy.deepcopy(doctrine)
    data["schema_version"] = CURRENT_SCHEMA_VERSION
    tests.append(("valid-current-doctrine-version", not validate_document(data, set(mapping))))
    # P4's policy is optional and only authored in v5. Runtime defaults must
    # not be injected into an older document under its unchanged version.
    for version in (1, 2, 3, 4, 5):
        for seed in range(30):
            data = copy.deepcopy(original)
            data.update(schema_version=version, seed=seed)
            before = copy.deepcopy(data)
            tests.append((f"absent-noise-policy-v{version}-seed{seed}", not validate_document(data, set(mapping))))
            tests.append((f"noise-default-preserves-source-v{version}-seed{seed}", data == before and "noise_discipline" not in data))
    for mode in ("verbal", "hand_signals"):
        data = copy.deepcopy(original)
        data.update(schema_version=5, noise_discipline=mode)
        before = copy.deepcopy(data)
        tests.append(("explicit-noise-policy:" + mode, not validate_document(data, set(mapping))))
        tests.append(("explicit-noise-policy-preserves-source:" + mode, data == before))
        for version in (1, 2, 3, 4):
            data = copy.deepcopy(original)
            data.update(schema_version=version, noise_discipline=mode)
            tests.append((f"noise-policy-requires-v5:{version}:{mode}", any("unsupported fields" in error for error in validate_document(data, set(mapping)))))
    for value in (None, True, False, 0, 1, 1.5, float("nan"), float("inf"), [], ["verbal"], {}, {"mode": "verbal"}, "", "Verbal", "HAND_SIGNALS", "hand_signal", "quiet", " verbal"):
        data = copy.deepcopy(original)
        data.update(schema_version=5, noise_discipline=value)
        tests.append(("invalid-noise-policy:" + str(value), any("noise_discipline" in error for error in validate_document(data, set(mapping)))))
    room_goal = copy.deepcopy(original)
    room_goal.update(schema_version=4, enemies=[], civilians=[], win=[{"type": "rooms_cleared"}], fail=[])
    authored_room_ids = [room["id"] for room in room_goal["rooms"]]
    tests.append(("valid-room-only-completion-goal", not validate_document(room_goal, set(mapping))))
    for field in ("win", "fail"):
        for selection in (None, authored_room_ids[:1], authored_room_ids):
            data = copy.deepcopy(room_goal)
            rule = {"type": "rooms_cleared"}
            if selection is not None: rule["room_ids"] = selection
            data[field] = [rule]
            tests.append(("valid-room-goal:" + field + ":" + str(selection), not validate_document(data, set(mapping))))
        for version in (1, 2, 3):
            data = copy.deepcopy(original)
            data["schema_version"] = version
            data[field] = [{"type": "rooms_cleared"}]
            tests.append(("room-rule-requires-v4:" + field + ":" + str(version), any("unknown rule" in error for error in validate_document(data, set(mapping)))))
    for value in (None, True, 1, 1.5, "t_ready", {}, [], [None], [True], [1], [{}], [[]], [""], ["bad room"], ["x" * 65], ["unknown"], [original["units"][0]["id"]], [authored_room_ids[0]] * 2, [authored_room_ids[0]] * 65):
        data = copy.deepcopy(room_goal)
        data["win"][0]["room_ids"] = value
        tests.append(("invalid-room-selection:" + str(value), bool(validate_document(data, set(mapping)))))
    data = copy.deepcopy(room_goal)
    data["rooms"] = []
    tests.append(("empty-all-room-goal", bool(validate_document(data, set(mapping)))))
    data = copy.deepcopy(original)
    data["schema_version"] = 4
    data["win"] = [{"type": "neutralize_all", "room_ids": authored_room_ids}]
    tests.append(("room-ids-belong-to-room-rule", any("unsupported fields" in error for error in validate_document(data, set(mapping)))))
    for version in (1, 2, 3, 4):
        for role in ("guard", "patrol", "reserve"):
            data = copy.deepcopy(original)
            data["schema_version"] = version
            data["enemies"][0]["response_role"] = role
            tests.append(("legacy-response-role:" + str(version) + ":" + role, not validate_document(data, set(mapping))))
    for role in (None, True, 1, [], {}, "reinforcements"):
        data = copy.deepcopy(original)
        data["enemies"][0]["response_role"] = role
        tests.append(("invalid-response-role:" + str(role), any("response_role" in error for error in validate_document(data, set(mapping)))))
    limit_goal = copy.deepcopy(room_goal)
    width, depth = limit_goal["bounds"]
    limit_goal["rooms"] = [{"id": f"room_{index}", "x": width / 2, "z": depth / 2, "w": width, "d": depth} for index in range(64)]
    limit_goal["win"][0]["room_ids"] = [room["id"] for room in limit_goal["rooms"]]
    tests.append(("room-selection-inclusive-64", not validate_document(limit_goal, set(mapping))))
    inherited = copy.deepcopy(room_goal)
    inherited.update(schema_version=5, noise_discipline="hand_signals", bounds=[512,512], focus=[480,480], walls=[], doors=[], props=[])
    inherited["rooms"] = [{"id":"upper", "x":480, "z":480, "w":8, "d":8, "base_height":64}]
    inherited["units"] = [dict(original["units"][0], x=478, z=478)]
    inherited["win"] = [{"type":"rooms_cleared", "room_ids":["upper"]}, {"type":"no_shots"}]
    inherited["environment"] = {"water":True, "water_level":-1, "ground_surface":"ship_deck"}
    inherited["walkable_areas"] = [{"id":"deck", "x":480, "z":480, "w":8, "d":8}]
    tests.append(("v5-inherits-rooms-shots-512-floor-water", not validate_document(inherited, set(mapping))))
    for version in (2, 3, 4):
        data = copy.deepcopy(room_goal)
        data.update(schema_version=version, bounds=[512, 512], focus=[480, 480], walls=[], doors=[], props=[])
        data["rooms"] = [{"id": "upper", "x": 480, "z": 480, "w": 8, "d": 8, "base_height": 64}]
        data["units"] = [dict(original["units"][0], x=478, z=478)]
        data["win"] = [{"type": "reach_zone", "zone": [480,480,1,1]}, {"type": "no_shots"}]
        tests.append(("legacy-max-bounds-floor:" + str(version), not validate_document(data, set(mapping))))
    for material in sorted(MATERIALS):
        data = copy.deepcopy(original)
        data["walls"][0]["material"] = material
        tests.append(("known-material:" + material, not validate_document(data, set(mapping))))
    for state in ("CLOSED", "AJAR", "OPEN", "DESTROYED"):
        data = copy.deepcopy(original)
        data["doors"][0].update(state=state, progress=0.52 if state == "AJAR" else (1 if state in ("OPEN", "DESTROYED") else 0), hp=0 if state == "DESTROYED" else 70)
        tests.append(("known-door-state:" + state, not validate_document(data, set(mapping))))
    for kind in RULES:
        data = copy.deepcopy(original)
        rule = {"type": kind}
        if kind in ("reach_zone", "escort_to_zone"): rule["zone"] = [2,2,1,1]
        if kind == "time_limit": rule["seconds"] = 30
        data["win"] = [rule]
        tests.append(("known-rule:" + kind, not validate_document(data, set(mapping))))
    for kind in ("normal", "sentry", "rusher", "hostage_taker"):
        data = copy.deepcopy(original)
        data["enemies"][0]["enemy_type"] = kind
        tests.append(("known-enemy-type:" + kind, not validate_document(data, set(mapping))))
    oversized_product = copy.deepcopy(original)
    template = oversized_product["enemies"][0]
    oversized_product["enemies"] = []
    for i in range(6):
        enemy = copy.deepcopy(template)
        enemy["id"] = "product_enemy" + str(i)
        enemy["spawns"] = [{key: copy.deepcopy(enemy[key]) for key in ("x", "z", "facing")} for _ in range(8)]
        oversized_product["enemies"].append(enemy)
    tests.append(("cartesian-budget-rejection", any("Cartesian product" in error for error in validate_document(oversized_product, set(mapping)))))
    for label, mutation in mutations:
        data = copy.deepcopy(original)
        mutation(data)
        tests.append((label, bool(validate_document(data, set(mapping)))))
    for text in ('{"id":"a","id":"b"}', '{"x":NaN}', '{"x":Infinity}'):
        rejected = False
        try:
            strict_json(text)
        except ValueError:
            rejected = True
        tests.append(("strict-json:" + text, rejected))
    if engine:
        with tempfile.TemporaryDirectory(prefix="breach-author-fixtures-") as folder:
            path = Path(folder) / "arbitrary-author-file.json"
            authored = copy.deepcopy(original)
            authored["id"] = "QA99"
            authored["enemies"].pop()
            path.write_text(json.dumps(authored))
            tests.append(("arbitrary-file-id-and-counts", not validate_geometry(path, engine)["errors"]))
            blocked = copy.deepcopy(authored)
            blocked["units"][0].update(x=3.0, z=10.0)
            path.write_text(json.dumps(blocked))
            result = validate_geometry(path, engine)
            tests.append(("engine-rejects-blocked-spawn", any("initial spawn" in error for error in result["errors"])))
            sealed = copy.deepcopy(authored)
            sealed["walls"].append({"id": "sealed_test", "x": 6.0, "z": 9.0, "w": 6.0, "d": 0.24})
            path.write_text(json.dumps(sealed))
            result = validate_geometry(path, engine)
            tests.append(("engine-rejects-unreachable-target", any("target1 candidate 0: no route" in error for error in result["errors"])))
            second_spawn = copy.deepcopy(authored)
            enemy = second_spawn["enemies"][0]
            enemy["spawns"] = [{key: enemy[key] for key in ("x", "z", "facing")}, {"x": second_spawn["units"][0]["x"], "z": second_spawn["units"][0]["z"], "facing": 0}]
            path.write_text(json.dumps(second_spawn))
            result = validate_geometry(path, engine)
            tests.append(("engine-checks-secondary-spawn-combination", result.get("candidate_combinations") == 2 and any("overlapping spawns" in error for error in result["errors"])))
    return {"checks": len(tests), "errors": [label for label, passed in tests if not passed]}


def default_mission_files(data_root: Path | None = None) -> list[Path]:
    """Nested historical/CQB sources are first-class authoring inputs."""
    root = data_root or ROOT / "game/data"
    # These shared catalogs are consumed separately; all other JSON stays validated.
    non_mission_files = {root / "equipment_catalog.json", root / "historical_roster.json"}
    return sorted(path for path in root.rglob("*.json") if path not in non_mission_files)


def cqb_source_errors(data_root: Path | None = None) -> list[str]:
    root = data_root or ROOT / "game/data"
    errors = []
    for mission_id in CQB_IDS:
        path = root / "cqb" / (mission_id + ".json")
        if not path.is_file():
            errors.append(f"missing CQB authoring file: {path}")
            continue
        try:
            document = strict_json(path.read_text())
            if not isinstance(document, dict) or document.get("id") != mission_id:
                errors.append(f"CQB file/ID mismatch: {path} expected {mission_id}")
        except (OSError, ValueError) as exc:
            errors.append(f"invalid CQB authoring file: {path}: {exc}")
    return errors


def cqb_catalog_errors(documents: dict) -> list[str]:
    return [f"missing CQB runtime catalog operation: {mission_id}" for mission_id in CQB_IDS if mission_id not in documents]


def cqb_geometry_coverage(missions: list[dict]) -> dict:
    """Make final-build coverage explicit; never replace a validation check."""
    required = {*CQB_IDS, *json.loads((ROOT / "game/data/historical_roster.json").read_text())["active_ids"]}
    by_id = {mission.get("id"): mission for mission in missions if mission.get("id") in required}
    result = {"new_authored_maps": 0, "historical_maps": 0, "physical_doors": 0,
              "entry_doors": 0, "entry_directions": 0, "short_guards": 0,
              "outdoor_passages": [], "entry_methods": [], "candidate_combinations": {}, "errors": []}
    for mission_id in sorted(required):
        mission = by_id.get(mission_id)
        if mission is None:
            result["errors"].append(f"missing frozen content geometry evidence: {mission_id}")
            continue
        geometry = mission.get("geometry", {})
        draft = geometry.get("entry_drills")
        if not isinstance(draft, dict):
            result["errors"].append(f"missing actual entry-drill evidence: {mission_id}")
            continue
        is_new = mission_id in CQB_IDS
        result["new_authored_maps" if is_new else "historical_maps"] += 1
        doors = mission.get("counts", {}).get("doors")
        if draft.get("door_count") != doors or draft.get("entry_doors", 0) + len(draft.get("passages", [])) != doors:
            result["errors"].append(f"unclassified authored door: {mission_id}")
        result["physical_doors"] += doors or 0
        for key in ("entry_doors", "entry_directions", "short_guards"):
            result[key] += draft.get(key, 0)
        methods = draft.get("entry_methods")
        if (not isinstance(methods, list) or len(methods) != draft.get("entry_directions")
                or any(not isinstance(proof, dict)
                       or not isinstance(proof.get("door_id"), str) or not proof["door_id"]
                       or not isinstance(proof.get("room_id"), str) or not proof["room_id"]
                       or not number(proof.get("entry_side")) or proof["entry_side"] not in (-1, 1)
                       or proof.get("method") not in ("OPEN_DOOR", "SHOTGUN_BREACH", "BREACH_DOOR")
                       for proof in methods)
                or len({(proof["door_id"], proof["room_id"], proof["entry_side"]) for proof in methods}) != len(methods)):
            result["errors"].append(f"missing actual supported entry method: {mission_id}")
        else:
            result["entry_methods"].extend({"mission_id": mission_id, **proof} for proof in methods)
        for passage in draft.get("passages", []):
            result["outdoor_passages"].append({"mission_id": mission_id, **passage})
        combinations = geometry.get("candidate_combinations")
        result["candidate_combinations"][mission_id] = combinations
        if is_new and combinations != (16 if mission_id.startswith("SH") else 256):
            result["errors"].append(f"incomplete NPC candidate product: {mission_id}")
    return result


def ordered_mission_results(items, worker, jobs: int):
    """Bound engine concurrency without changing report/input order."""
    if not items:
        return
    workers = min(4, jobs, len(items))
    if workers == 1:
        for item in items:
            yield worker(item)
        return
    with ThreadPoolExecutor(max_workers=workers) as executor:
        yield from executor.map(worker, items)


def validate_authoring_file(path: Path, mapping: dict, schema_only: bool, godot: str | None) -> dict:
    result = {"path": str(path), "errors": []}
    try:
        if path.stat().st_size > 2 * 1024 * 1024:
            raise ValueError("mission exceeds 2MiB authoring limit")
        data = strict_json(path.read_text())
        result["sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
        result["errors"] = validate_document(data, set(mapping))
        if not result["errors"]:
            result["id"] = data["id"]
            result["counts"] = {group: len(data[group]) for group in GROUPS}
            if not schema_only:
                assets = validate_map_assets(data, mapping)
                result["assets"] = assets["files"]
                result["procedural_props"] = assets["procedural"]
                result["errors"].extend(assets["errors"])
                result["geometry"] = validate_geometry(path, engine_path(godot))
                result["errors"].extend(result["geometry"]["errors"])
    except (OSError, ValueError, TypeError, KeyError, OverflowError) as exc:
        result["errors"].append(f"cannot validate authoring file: {exc}")
    result["passed"] = not result["errors"]
    return result


def validate_derived_mission(item: tuple, mapping: dict, schema_only: bool, godot: str | None) -> dict:
    mission_id, data, path = item
    result = {"id": mission_id, "path": "catalog:" + mission_id, "errors": validate_document(data, set(mapping)), "counts": {group: len(data[group]) for group in GROUPS}}
    if not result["errors"] and not schema_only:
        path.write_text(json.dumps(data, ensure_ascii=False))
        result["geometry"] = validate_geometry(path, engine_path(godot))
        result["errors"].extend(result["geometry"]["errors"])
    result["passed"] = not result["errors"]
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("maps", nargs="*", type=Path, help="JSON files; defaults to all nested authoring sources and runtime catalog operations")
    parser.add_argument("--godot", help="Godot executable, otherwise GODOT_BIN/bundled/godot")
    parser.add_argument("--report", type=Path, help="write machine-readable JSON report")
    parser.add_argument("--schema-only", action="store_true", help="explicit partial check; skips assets and engine geometry")
    parser.add_argument("--self-test", action="store_true", help="also check malformed authoring examples are rejected")
    parser.add_argument("--catalog", action="store_true", help="also validate runtime-derived operation types (automatic in a complete default check)")
    parser.add_argument("--jobs", type=int, choices=range(1, 5), default=4, help="maximum concurrent mission workers (1-4, default 4; one mission uses one worker)")
    args = parser.parse_args()
    report = {"schema_version": 1, "scope": "schema-only" if args.schema_only else "schema-assets-engine-geometry", "missions": [], "source_hashes": {path: hashlib.sha256((ROOT / path).read_bytes()).hexdigest() for path in ("game/scripts/navigation.gd", "game/scripts/door_geometry.gd", "game/scripts/environment_assets.gd", "game/scripts/world_view.gd", "game/scripts/mission_catalog.gd", "game/scripts/mission_schema.gd", "game/scripts/content_geometry_validator.gd", "game/scripts/room_drill.gd", "game/scripts/spatial_profile.gd", "scripts/validate_missions.py")}}
    try:
        mapping = prop_assets()
    except (OSError, ValueError) as exc:
        print(f"MISSION_VALIDATION FAILED: {exc}")
        return 1
    files = args.maps or default_mission_files()
    if not args.maps:
        missing = cqb_source_errors()
        if missing:
            report["missions"].append({"path": "cqb-authoring-manifest", "passed": False, "errors": missing})
            for error in missing: print("FAIL " + error)
    authoring_worker = lambda path: validate_authoring_file(path, mapping, args.schema_only, args.godot)
    for result in ordered_mission_results(files, authoring_worker, args.jobs):
        report["missions"].append(result)
        print(f"{'PASS' if result['passed'] else 'FAIL'} {result['path']} ({report['scope']})")
        for error in result["errors"]:
            print(f"  {error}")
    if args.catalog or (not args.maps and not args.schema_only):
        try:
            documents = catalog_documents(engine_path(args.godot))
            missing = cqb_catalog_errors(documents)
            if missing:
                report["missions"].append({"path": "cqb-runtime-manifest", "passed": False, "errors": missing})
                for error in missing: print("FAIL " + error)
            original_ids = {mission.get("id") for mission in report["missions"]}
            with tempfile.TemporaryDirectory(prefix="breach-derived-missions-") as folder:
                derived = [(mission_id, data, Path(folder) / (mission_id + ".json")) for mission_id, data in documents.items() if mission_id not in original_ids]
                derived_worker = lambda item: validate_derived_mission(item, mapping, args.schema_only, args.godot)
                for result in ordered_mission_results(derived, derived_worker, args.jobs):
                    report["missions"].append(result)
                    print(f"{'PASS' if result['passed'] else 'FAIL'} {result['path']} ({report['scope']})")
                    for error in result["errors"]: print("  " + error)
        except (OSError, ValueError, subprocess.TimeoutExpired) as exc:
            report["missions"].append({"path": "runtime-catalog", "passed": False, "errors": [str(exc)]})
            print("FAIL runtime-catalog: " + str(exc))
    if args.self_test:
        report["self_test"] = self_test(mapping, None if args.schema_only else engine_path(args.godot))
        print(f"VALIDATOR_SELF_TEST checks={report['self_test']['checks']} failures={len(report['self_test']['errors'])}")
    if not args.maps and not args.schema_only:
        report["content_geometry_coverage"] = cqb_geometry_coverage(report["missions"])
    report["passed"] = all(item["passed"] for item in report["missions"]) and not report.get("self_test", {}).get("errors")
    report["passed"] = report["passed"] and not report.get("content_geometry_coverage", {}).get("errors")
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(f"MISSION_VALIDATION_RESULT maps={len(report['missions'])} status={'PASS' if report['passed'] else 'FAIL'} scope={report['scope']}")
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
