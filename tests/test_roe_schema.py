"""P5 authoring keeps legacy missions intact and agrees with Godot validation."""
from pathlib import Path
import copy
import importlib.util
import json
import math
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("roe_mission_validation", ROOT / "scripts/validate_missions.py")
validation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validation)


def fixture(version=6, seed=0):
    return {
        "schema_version": version, "id": "ROE_SCHEMA", "revision": 1,
        "title": "ROE authoring contract", "seed": seed, "bounds": [12, 12], "focus": [6, 6],
        "rooms": [{"id": "front", "x": 3, "z": 6, "w": 6, "d": 12, "indoor": False},
                  {"id": "back", "x": 9, "z": 6, "w": 6, "d": 12, "indoor": True}],
        "walls": [], "doors": [], "props": [],
        "units": [{"id": "alpha", "name": "ALPHA", "role": "entry", "x": 3, "z": 3,
                   "facing": 0, "weapon": "standard"}], "enemies": [], "civilians": [],
        "objectives": ["Reach the designated room"], "win": [{"type": "reach_zone", "zone": [9, 9, 1, 1]}], "fail": [],
    }


def star(stat="arrests", op="gte", value=1):
    return {"id": "contract_star", "label": "Contract star", "stat": stat, "op": op, "value": value}


class ROEAuthoringTest(unittest.TestCase):
    def validate(self, source):
        return validation.validate_document(source, set())

    def test_optional_policy_never_rewrites_legacy_versions(self):
        self.assertEqual(validation.CURRENT_SCHEMA_VERSION, 6)
        for version in range(1, 7):
            for seed in range(30):
                with self.subTest(version=version, seed=seed):
                    source = fixture(version, seed)
                    before = copy.deepcopy(source)
                    self.assertEqual(self.validate(source), [])
                    self.assertEqual(source, before)
                    self.assertNotIn("roe", source)

    def test_policy_enum_requires_v6_and_exact_strings(self):
        for policy in ("precision", "high_intensity"):
            for version in range(1, 7):
                source = fixture(version)
                source["roe"] = policy
                with self.subTest(policy=policy, version=version):
                    self.assertEqual(not self.validate(source), version == 6)
        for policy in (None, True, False, 0, 1, 1.5, math.nan, math.inf, [], {}, ["precision"],
                       {"mode": "precision"}, "", "Precision", "HIGH_INTENSITY", "high-intensity", " precision", "precision "):
            source = fixture()
            source["roe"] = policy
            with self.subTest(policy=policy):
                self.assertTrue(self.validate(source))

    def test_damage_and_gte_are_only_new_authoring(self):
        for version in range(1, 7):
            for stat in ("civilian_damage", "unit_damage"):
                for op in ("eq", "lte", "gte"):
                    for value in (0, 0.0, 0.5, 1, 1e9):
                        source = fixture(version)
                        source["stars"] = [star(stat, op, value)]
                        with self.subTest(version=version, stat=stat, op=op, value=value):
                            self.assertEqual(not self.validate(source), version == 6)
            for op in ("eq", "lte", "gte"):
                source = fixture(version)
                source["stars"] = [star("arrests", op, 1)]
                with self.subTest(version=version, op=op):
                    self.assertEqual(not self.validate(source), version == 6 or op != "gte")
        # Capturing two suspects must still satisfy arrests >= 1. The schema
        # accepts a lower bound; gameplay evaluates gte without an eq-1 cap.
        source = fixture()
        source["stars"] = [star("arrests", "gte", 1)]
        self.assertEqual(self.validate(source), [])
        self.assertEqual(source["stars"][0], star("arrests", "gte", 1))

    def test_malformed_predicates_and_runtime_fields_are_rejected(self):
        for value in (None, True, False, -0.001, "0", [], {}, math.nan, math.inf, -math.inf, 1e9 + 1):
            source = fixture()
            source["stars"] = [star("civilian_damage", "eq", value)]
            with self.subTest(value=value):
                self.assertTrue(self.validate(source))
        for stat in ("frags_used", "damage", "civilian_injuries", "unit_injuries", None, True, 1, [], {}):
            source = fixture()
            source["stars"] = [star(stat)]
            with self.subTest(stat=stat):
                self.assertTrue(self.validate(source))
        for op in ("gt", "lt", "GTE", None, True, 1, [], {}):
            source = fixture()
            source["stars"] = [star(op=op)]
            with self.subTest(op=op):
                self.assertTrue(self.validate(source))
        for field in ("rules_of_engagement", "frags", "civilian_damage", "unit_damage", "stats_observed", "result", "stars_observed"):
            source = fixture()
            source[field] = 0
            self.assertTrue(self.validate(source))
        for field in ("frags", "available_frags", "civilian_damage", "unit_damage"):
            source = fixture()
            source["units"][0][field] = 1
            self.assertTrue(self.validate(source))

    def test_old_source_files_remain_valid_at_30_fixed_seeds(self):
        kinds = set(validation.prop_assets())
        files = sorted(path for path in (ROOT / "game/data").glob("*.json") if path.name != "equipment_catalog.json")
        self.assertGreaterEqual(len(files), 13)
        for path in files:
            authored = validation.strict_json(path.read_text())
            for seed in range(30):
                source = copy.deepcopy(authored)
                source["seed"] = seed
                before = copy.deepcopy(source)
                with self.subTest(path=path.name, seed=seed):
                    self.assertEqual(validation.validate_document(source, kinds), [])
                    self.assertEqual(source, before)
                    self.assertEqual(source["schema_version"], authored["schema_version"])
                    self.assertNotIn("roe", source)

    def test_frag_uses_existing_catalog_equipment_and_slot_limits(self):
        for version in range(1, 7):
            for count in (0, 1, 2):
                source = fixture(version)
                source["units"][0]["equipment"] = {"frag": count}
                self.assertEqual(self.validate(source), [])
        for count in (True, False, -1, 3, 1.5, "1", None, [], {}):
            source = fixture()
            source["units"][0]["equipment"] = {"frag": count}
            with self.subTest(count=count):
                self.assertTrue(self.validate(source))
        for equipment in ({"frag": 2, "stun": 1}, {"frag": 1, "probe_c1": 1, "smoke": 1},
                          {"frag": 1, "breach": 2}, {"frag_unknown": 1}):
            source = fixture()
            source["units"][0]["equipment"] = equipment
            self.assertTrue(self.validate(source))

    def test_godot_and_python_accept_the_same_json_contracts(self):
        godot = os.environ.get("GODOT_BIN", str(ROOT / ".tools/Godot.app/Contents/MacOS/Godot"))
        with tempfile.TemporaryDirectory(prefix="breach-roe-schema-") as directory:
            output = Path(directory) / "contracts.json"
            result = subprocess.run(
                [godot, "--headless", "--path", str(ROOT / "game"), "--script", "res://tests/roe_schema_test.gd", "--", f"--contract-output={output}"],
                cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120,
            )
            self.assertEqual(result.returncode, 0, result.stdout[-6000:])
            self.assertNotIn("SCRIPT ERROR", result.stdout)
            self.assertNotIn("ERROR:", result.stdout)
            self.assertRegex(result.stdout, r"BREACH_ROE_SCHEMA_RESULT checks=\d+ failures=0")
            contracts = json.loads(output.read_text())
            self.assertGreater(len(contracts), 150)
            for contract in contracts:
                with self.subTest(label=contract["label"]):
                    errors = self.validate(contract["source"])
                    self.assertEqual(not errors, contract["accepted"], errors)


if __name__ == "__main__":
    unittest.main()
