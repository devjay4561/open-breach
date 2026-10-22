"""Author-file validation follows the shared operator equipment catalog."""
from pathlib import Path
import copy
import importlib.util
import json
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("equipment_mission_validation", ROOT / "scripts/validate_missions.py")
validation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validation)


class EquipmentAuthoringTest(unittest.TestCase):
    def setUp(self):
        self.mission = json.loads((ROOT / "game/data/tutorial.json").read_text())
        self.kinds = set(validation.prop_assets())
        self.choice = {
            "weapon": "standard", "equipment": {"stun": 1, "probe_c1": 1, "breach": 1},
            "sidearm": "pico_p1", "armor": "swift_v3", "helmet": "crown_h2",
            "attachments": ["scope", "suppressor", "extended_mag"], "preset": "custom",
            "appearance": {"name": "레이븐", "callsign": "RAVEN", "color": "#40516c", "patch": "raven"},
        }

    def errors(self, choice, *, actor=False):
        mission = copy.deepcopy(self.mission)
        if actor:
            mission["units"][0].update(choice)
        else:
            mission["loadout"] = {"alpha": choice}
        return validation.validate_document(mission, self.kinds)

    def test_complete_loadout_and_legacy_choices(self):
        self.assertEqual(self.errors(self.choice), [])
        self.assertEqual(self.errors({"weapon": "standard", "equipment": {"breach": 2}}), [])
        self.assertEqual(self.errors({"weapon": "light", "equipment": ["stun", "stun"]}), [])

    def test_extended_magazine_capacity_is_checked(self):
        self.assertEqual(self.errors({**self.choice, "ammo": 32, "cameras": 1}, actor=True), [])
        self.assertTrue(self.errors({**self.choice, "ammo": 33}, actor=True))
        self.assertTrue(self.errors({**self.choice, "cameras": 3}, actor=True))

    def test_invalid_gear_and_mount_conflicts_are_rejected(self):
        for change in (
            {"armor": "unregistered"}, {"helmet": True}, {"sidearm": "unregistered"},
            {"attachments": ["scope", "dot"]}, {"attachments": ["dot", "dot"]},
            {"weapon": "shotgun", "attachments": ["extended_mag"]},
            {"equipment": {"stun": 2, "probe_c1": 1}}, {"equipment": {"breach": 2, "stun": 1}},
            {"equipment": {"stun": True}}, {"preset": "unregistered"},
        ):
            with self.subTest(change=change):
                self.assertTrue(self.errors({**self.choice, **change}))

    def test_personal_labels_are_bounded_and_safe(self):
        for appearance in (
            {"callsign": "line\nbreak"}, {"name": "x" * 49}, {"callsign": "x" * 33},
            {"color": "not-a-color"}, {"patch": "external-file"}, {"file": "res://outside.glb"},
        ):
            with self.subTest(appearance=appearance):
                self.assertTrue(self.errors({**self.choice, "appearance": appearance}))


if __name__ == "__main__":
    unittest.main()
