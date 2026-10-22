"""Focused nested-content discovery and the real native validation bridge."""
from __future__ import annotations

import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("mission_validator", ROOT / "scripts/validate_missions.py")
validator = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(validator)


def fixture():
    door_z = 7.8
    return {
        "schema_version": 6, "id": "CQB_GEOMETRY_QA", "revision": 1,
        "title": "Geometry", "seed": 0, "bounds": [16, 18], "focus": [8, 5],
        "rooms": [
            {"id": "inside", "x": 8, "z": 5, "w": 5.6, "d": 5.6, "indoor": True},
            {"id": "outside", "x": 8, "z": door_z + 2.8, "w": 5.6, "d": 5.6, "indoor": False},
        ],
        "walls": [
            {"id": "north", "x": 8, "z": 2.2, "w": 5.6, "d": .2},
            {"id": "west", "x": 5.2, "z": 5, "w": .2, "d": 5.6},
            {"id": "east", "x": 10.8, "z": 5, "w": .2, "d": 5.6},
            {"id": "left", "x": 6.2, "z": door_z, "w": 2, "d": .2},
            {"id": "right", "x": 9.8, "z": door_z, "w": 2, "d": .2},
            {"id": "outside_west", "x": 5.2, "z": door_z + 2.8, "w": .2, "d": 5.6},
            {"id": "outside_east", "x": 10.8, "z": door_z + 2.8, "w": .2, "d": 5.6},
            {"id": "south", "x": 8, "z": door_z + 5.6, "w": 5.6, "d": .2},
        ],
        "doors": [{"id": "entry", "x": 8, "z": door_z, "w": 1.6, "d": .2,
                   "axis": "x", "state": "CLOSED", "hinge_side": -1, "swing_sign": -1}],
        "props": [],
        "units": [{"id": unit_id, "x": 8 if index == 0 else 7.2 + 1.6 * (index % 2), "z": door_z + 3.5 if index == 0 else door_z + 1.4 + .8 * (index // 2)}
                  for index, unit_id in enumerate(("alpha", "bravo", "charlie", "delta"))],
        "enemies": [{"id": "enemy", "x": 7.2, "z": door_z + 3,
                     "spawns": [{"x": 7.2, "z": door_z + 3}, {"x": 8.8, "z": door_z + 3}]}],
        "civilians": [], "objectives": ["Geometry"],
        "win": [{"type": "neutralize_all"}], "fail": [],
    }


class ContentGeometryTests(unittest.TestCase):
    def test_mission_workers_preserve_single_worker_and_four_worker_bound(self):
        with patch.object(validator, "ThreadPoolExecutor", side_effect=AssertionError("one mission must not create a pool")):
            self.assertEqual(list(validator.ordered_mission_results(["one"], lambda item: item, 4)), ["one"])
            self.assertEqual(list(validator.ordered_mission_results([], lambda item: item, 4)), [])
        with patch.object(validator, "ThreadPoolExecutor", wraps=validator.ThreadPoolExecutor) as executor:
            values = [5, 4, 3, 2, 1]
            self.assertEqual(list(validator.ordered_mission_results(values, lambda item: item * 2, 4)), [10, 8, 6, 4, 2])
            executor.assert_called_once_with(max_workers=4)

    def test_actual_two_mission_reports_match_jobs_one_and_four(self):
        # Keep the real schema/assets/NPC/leaf/RoomDrill engines intact. These
        # two small authored missions prove ordered reporting without repeating
        # the frozen 90-map final-build audit.
        paths = [ROOT / "game/data/depot.json", ROOT / "game/data/tutorial.json"]
        with tempfile.TemporaryDirectory() as folder:
            reports = []
            outputs = []
            for jobs in (1, 4):
                report_path = Path(folder) / f"jobs{jobs}.json"
                process = subprocess.run([sys.executable, str(ROOT / "scripts/validate_missions.py"),
                                          *(str(path) for path in paths), "--jobs", str(jobs),
                                          "--report", str(report_path)], capture_output=True, text=True, timeout=120)
                self.assertEqual(process.returncode, 0, process.stdout + process.stderr)
                reports.append(report_path.read_bytes())
                outputs.append(process.stdout)
            self.assertEqual(reports[0], reports[1], "all report fields and errors must be exactly identical")
            self.assertEqual(outputs[0], outputs[1], "PASS/error output keeps the input order")
            report = json.loads(reports[0])
            self.assertEqual([mission["id"] for mission in report["missions"]], ["M03", "T01"])
            self.assertTrue(all(mission["geometry"]["entry_drills"]["entry_methods"] for mission in report["missions"]))

    def test_nested_discovery_includes_history_and_cqb(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            expected = [root / "house.json", root / "historical/H01.json", root / "cqb/SH01.json"]
            for path in expected + [root / "equipment_catalog.json", root / "historical_roster.json"]:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("{}")
            self.assertEqual(validator.default_mission_files(root), sorted(expected))

    def test_required_manifest_rejects_missing_and_wrong_ids(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for mission_id in validator.CQB_IDS:
                path = root / "cqb" / f"{mission_id}.json"
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(json.dumps({"id": mission_id}))
            self.assertEqual(validator.cqb_source_errors(root), [])
            (root / "cqb/CQB12.json").unlink()
            (root / "cqb/SH01.json").write_text('{"id":"SH02"}')
            errors = validator.cqb_source_errors(root)
            self.assertEqual(len(errors), 2)
            self.assertTrue(any("missing" in error and "CQB12" in error for error in errors))
            self.assertTrue(any("mismatch" in error and "SH01" in error for error in errors))

    def test_runtime_registration_is_required(self):
        documents = {mission_id: {} for mission_id in validator.CQB_IDS}
        self.assertEqual(validator.cqb_catalog_errors(documents), [])
        del documents["CQB09"]
        self.assertEqual(validator.cqb_catalog_errors(documents), ["missing CQB runtime catalog operation: CQB09"])

    def test_final_build_requires_all_active_geometry_summaries(self):
        missions = []
        for mission_id in (*validator.CQB_IDS, *json.loads((validator.ROOT / "game/data/historical_roster.json").read_text())["active_ids"]):
            missions.append({"id": mission_id, "counts": {"doors": 1},
                             "geometry": {"candidate_combinations": 16 if mission_id.startswith("SH") else 256 if mission_id.startswith("CQB") else 1,
                                          "entry_drills": {"door_count": 1, "entry_doors": 1, "entry_directions": 2,
                                                           "short_guards": 0, "passages": [],
                                                           "entry_methods": [{"door_id": "entry", "room_id": "logical_room", "entry_side": side, "method": "OPEN_DOOR"}
                                                                             for side in (-1, 1)]}}})
        covered = validator.cqb_geometry_coverage(missions)
        self.assertEqual(covered["errors"], [])
        self.assertEqual((covered["new_authored_maps"], covered["historical_maps"]), (18, 12))
        self.assertEqual(covered["entry_directions"], 60)
        self.assertEqual(len(covered["entry_methods"]), 60)
        partial = copy.deepcopy(missions)
        partial[0]["geometry"].pop("entry_drills")
        partial[6]["geometry"]["candidate_combinations"] = 128
        partial[7]["geometry"]["entry_drills"]["door_count"] = 2
        del partial[-1]
        errors = validator.cqb_geometry_coverage(partial)["errors"]
        self.assertEqual(len(errors), 4)
        self.assertTrue(any("missing actual" in error for error in errors))
        self.assertTrue(any("incomplete NPC" in error for error in errors))
        self.assertTrue(any("unclassified" in error for error in errors))
        self.assertTrue(any("H36" in error for error in errors))
        unsupported = copy.deepcopy(missions)
        unsupported[0]["geometry"]["entry_drills"]["entry_methods"][0]["method"] = "KICK_DOOR"
        self.assertEqual(validator.cqb_geometry_coverage(unsupported)["errors"], ["missing actual supported entry method: SH01"])
        duplicated_side = copy.deepcopy(missions)
        duplicated_side[0]["geometry"]["entry_drills"]["entry_methods"][1]["entry_side"] = -1
        self.assertEqual(validator.cqb_geometry_coverage(duplicated_side)["errors"], ["missing actual supported entry method: SH01"])
        invalid_side = copy.deepcopy(missions)
        invalid_side[0]["geometry"]["entry_drills"]["entry_methods"][0]["entry_side"] = True
        self.assertEqual(validator.cqb_geometry_coverage(invalid_side)["errors"], ["missing actual supported entry method: SH01"])

    def test_real_native_bridge_keeps_physical_checks_and_static_draft_separate(self):
        # One map/two engine calls exercise the bridge and the old secondary
        # spawn rejection. The frozen 54-map audit belongs to final build;
        # this unit does not repeat every room for each NPC combination.
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "fixture.json"
            source = fixture()
            path.write_text(json.dumps(source))
            result = validator.validate_geometry(path, validator.engine_path(None))
            self.assertEqual(result["errors"], [], result)
            self.assertEqual(result["candidate_combinations"], 2)
            self.assertEqual(result["spawn_candidates"], 6)
            self.assertEqual(result["entry_drills"]["entry_directions"], 1)
            self.assertEqual(result["entry_drills"]["entry_doors"], 1)
            self.assertNotIn("layouts", result["entry_drills"])
            blocked = copy.deepcopy(source)
            blocked["enemies"][0]["spawns"][1]["x"] = 5.2
            path.write_text(json.dumps(blocked))
            failure = validator.validate_geometry(path, validator.engine_path(None))
            self.assertEqual(failure["candidate_combinations"], 2)
            self.assertTrue(any("enemy candidate 1: initial spawn" in error for error in failure["errors"]), failure)
            self.assertEqual(failure["entry_drills"]["errors"], [])


if __name__ == "__main__":
    unittest.main()
