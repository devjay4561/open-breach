import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from mission_authoring import preserve_enemy_strengths


class EnemyStrengthAuthoringTest(unittest.TestCase):
    def test_regeneration_preserves_tuned_tiers_by_id(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "map.json"
            path.write_text(json.dumps({"id":"QA","revision":3,"enemies":[{"id":"a","strength":"strong"},{"id":"b","strength":"medium"}]}))
            data = {"id":"QA","revision":1,"enemies":[{"id":"b"},{"id":"new"},{"id":"a"}]}
            preserve_enemy_strengths(data, path)
            self.assertEqual(data["revision"], 3)
            self.assertEqual(data["enemies"], [{"id":"b","strength":"medium"},{"id":"new"},{"id":"a","strength":"strong"}])

    def test_cqb_export_keeps_authored_tiers(self):
        with tempfile.TemporaryDirectory() as folder:
            subprocess.run([sys.executable, str(ROOT / "scripts/create_cqb_maps.py"), "--output", folder], check=True, capture_output=True, text=True)
            for path in (ROOT / "game/data/cqb").glob("CQB*.json"):
                authored = json.loads(path.read_text())
                exported = json.loads((Path(folder) / path.name).read_text())
                self.assertEqual({e["id"]:e["strength"] for e in exported["enemies"]}, {e["id"]:e["strength"] for e in authored["enemies"]})


if __name__ == "__main__":
    unittest.main()
