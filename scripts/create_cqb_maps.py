#!/usr/bin/env python3
"""Materialize the independently authored CQB missions in stable ID order."""
import argparse
import json
from mission_authoring import preserve_enemy_strengths
from pathlib import Path
from cqb_maps import shoot_house

ROOT = Path(__file__).resolve().parents[1]


def missions(include_puzzles=True):
    result = shoot_house.build()
    if include_puzzles:
        from cqb_maps import puzzles_contact, puzzles_control
        result += puzzles_contact.build() + puzzles_control.build()
    ids = [data["id"] for data in result]
    if len(ids) != len(set(ids)):
        raise ValueError("Duplicate CQB mission ID")
    return sorted(result, key=lambda data: data["id"])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--shoot-house-only", action="store_true")
    parser.add_argument("--output", type=Path, default=ROOT / "game/data/cqb")
    parser.add_argument("--course-specs", type=Path)
    args = parser.parse_args()
    data = missions(not args.shoot_house_only)
    args.output.mkdir(parents=True, exist_ok=True)
    for mission in data:
        preserve_enemy_strengths(mission, ROOT / "game/data/cqb" / f'{mission["id"]}.json')
        (args.output / f'{mission["id"]}.json').write_text(json.dumps(mission, ensure_ascii=False, indent=2) + "\n")
    if args.course_specs:
        args.course_specs.parent.mkdir(parents=True, exist_ok=True)
        args.course_specs.write_text(json.dumps(shoot_house.COURSE_SPECS, ensure_ascii=False, indent=2) + "\n")
    print(f"CQB_MAPS_RESULT missions={len(data)} output={args.output}")


if __name__ == "__main__":
    main()
