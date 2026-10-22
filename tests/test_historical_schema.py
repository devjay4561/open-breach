"""Strict authoring contract checks for metre-scale historical missions."""
from copy import deepcopy
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from validate_missions import historical_assets, prop_assets, validate_document


class HistoricalSchemaTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.kinds = set(prop_assets())

    def mission(self, version=2, width=128, depth=96):
        return {
            "schema_version": version, "id": "HISTORICAL_QA", "revision": 1,
            "title": "Historical authoring QA", "seed": 1, "bounds": [width, depth],
            "focus": [width / 2, depth / 2],
            "rooms": [{"id": "ground", "x": width / 2, "z": depth / 2, "w": width, "d": depth}],
            "walls": [], "doors": [], "props": [],
            "units": [{"id": "alpha", "name": "Alpha", "role": "Assault", "weapon": "standard", "x": 4, "z": 4, "facing": 0}],
            "enemies": [], "civilians": [], "objectives": ["Reach the far zone"],
            "win": [{"type": "reach_zone", "zone": [width - 4, depth - 4, 2, 2]}],
        }

    def validate(self, mission):
        return validate_document(mission, self.kinds)

    def test_separate_version_bounds(self):
        self.assertFalse(self.validate(self.mission(1, 32, 32)))
        self.assertTrue(self.validate(self.mission(1, 33, 32)))
        self.assertFalse(self.validate(self.mission(2, 512, 512)))
        self.assertTrue(self.validate(self.mission(2, 513, 512)))
        self.assertTrue(self.validate(self.mission(True, 32, 32)))

    def test_real_building_height_keeps_actor_dimensions_separate(self):
        mission = self.mission()
        mission["walls"] = [{"id": "tower", "x": 50, "z": 50, "w": 4, "d": 4, "height": 12.2}]
        self.assertFalse(self.validate(mission))
        mission["units"][0]["weapon_height"] = 12.2
        self.assertTrue(self.validate(mission))
        del mission["units"][0]["weapon_height"]
        mission["walls"][0]["height"] = 65
        self.assertTrue(self.validate(mission))
        legacy = self.mission(1, 32, 32)
        legacy["walls"] = [{"id": "tower", "x": 16, "z": 16, "w": 4, "d": 4, "height": 12.2}]
        self.assertTrue(self.validate(legacy))

    def test_collision_proxy_render_field_is_versioned(self):
        mission = self.mission()
        mission["walls"] = [{"id": "proxy", "x": 50, "z": 50, "w": 4, "d": 4, "render": False}]
        self.assertFalse(self.validate(mission))
        mission["walls"][0]["render"] = True
        self.assertFalse(self.validate(mission))
        mission["walls"][0]["render"] = 0
        self.assertTrue(self.validate(mission))
        legacy = self.mission(1, 32, 32)
        legacy["walls"] = [{"id": "proxy", "x": 16, "z": 16, "w": 4, "d": 4, "render": False}]
        self.assertTrue(self.validate(legacy))

    def test_new_fields_are_v2_only(self):
        mission = self.mission(1, 32, 32)
        mission["walkable_areas"] = [{"id": "floor", "x": 16, "z": 16, "w": 32, "d": 32}]
        self.assertTrue(self.validate(mission))
        mission["schema_version"] = 2
        self.assertFalse(self.validate(mission))

    def test_water_requires_explicit_actor_floor(self):
        mission = self.mission()
        mission["environment"] = {"water": True}
        self.assertTrue(self.validate(mission))
        mission["walkable_areas"] = [{"id": "deck", "x": 64, "z": 48, "w": 110, "d": 20}]
        self.assertFalse(self.validate(mission))
        mission["walkable_areas"] = []
        self.assertTrue(self.validate(mission))

    def test_history_source_and_nested_shape(self):
        mission = self.mission()
        mission["historical"] = {"location": "Nervask Strait", "accuracy_note": "Test fixture only"}
        self.assertFalse(self.validate(mission))
        for key, value in (("accuracy_note", ""), ("location", True), ("script", "injected")):
            broken = deepcopy(mission)
            broken["historical"][key] = value
            self.assertTrue(self.validate(broken))

    def test_interactive_targets_and_references(self):
        mission = self.mission()
        mission["interactive_targets"] = [{"id": "radio", "x": 100, "z": 50, "w": 2, "d": 2, "label": "Radio", "action": "disable", "duration": 3}]
        mission["win"] = [{"type": "targets_complete", "targets": ["radio"]}]
        mission["fail"] = [{"type": "no_shots"}]
        self.assertFalse(self.validate(mission))
        for targets in (["missing"], ["radio", "radio"], [], [True]):
            broken = deepcopy(mission)
            broken["win"][0]["targets"] = targets
            self.assertTrue(self.validate(broken))
        for key, value in (("duration", 0), ("duration", 61), ("progress", 3), ("action", "teleport"), ("id", "alpha")):
            broken = deepcopy(mission)
            broken["interactive_targets"][0][key] = value
            self.assertTrue(self.validate(broken))

    def test_environment_stays_strict(self):
        mission = self.mission()
        mission["environment"] = {"biome": "coast", "ground_color": "#667a83", "ground_surface": "concrete", "water": False, "water_level": -3.45}
        self.assertFalse(self.validate(mission))
        for key, value in (("weather", "rain"), ("ground_color", "#12"), ("water", 1), ("ground_surface", "lava"), ("water_level", 0.1), ("water_level", -17)):
            broken = deepcopy(mission)
            broken["environment"][key] = value
            self.assertTrue(self.validate(broken))

    def test_scenery_registry_and_files(self):
        mission = self.mission()
        mission["scenery"] = [{"id": "unknown", "asset": "missing_model", "x": 40, "z": 40}]
        self.assertTrue(self.validate(mission))
        registry = historical_assets()
        if not registry:
            self.skipTest("Historical asset build is not available yet")
        root = Path(__file__).resolve().parents[1]
        for asset_id, entry in registry.items():
            resource = entry.get("path", "res://assets/historical/" + asset_id + ".glb")
            self.assertTrue((root / "game" / resource.removeprefix("res://")).is_file(), asset_id)
        mission["scenery"][0]["asset"] = next(iter(registry))
        mission["scenery"][0]["cutaway"] = False
        self.assertFalse(self.validate(mission))
        for key, value in (("scale", True), ("scale", 0), ("height", -65), ("cutaway", 0), ("collision", True)):
            broken = deepcopy(mission)
            broken["scenery"][0][key] = value
            self.assertTrue(self.validate(broken))


if __name__ == "__main__":
    unittest.main()
