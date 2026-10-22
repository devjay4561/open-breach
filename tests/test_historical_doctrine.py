"""Preserve historical ROE metadata and versioned authored map baselines."""
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from historical_maps.common import MapBuilder
from validate_missions import prop_assets, validate_document

# Frozen before P7 from the shared workspace originals. Do not regenerate
# these expectations when authoring maps: they protect geometry/AI/provenance.
# Active map baselines include the approved fictional dossier and asset renames.
ORIGINAL_SHA256 = {
    "game/data/archive.json": "d64a1ae17d9aeeca4023b73f6a7622144b14ae93b5fcd70726ffe1db2115e616",
    "game/data/archive_challenge.json": "3542af72b8847bb0fb370e8764820bdbaef932064e20a29270e9d8e58215dd6f",
    "game/data/courtyard.json": "77a7e28b94a5746deccbfb8180e3e16e1b33401f2f3ca40d91d0e71ef2348648",
    "game/data/depot.json": "b150f80194235d6ae6ea7540562c8748754a57be08abf6e18b2fe9d9106dc261",
    "game/data/depot_challenge.json": "0f6c92ce0ea20fd6b0c4b4778177da996db260f6bd6ff5eaaba7a282c8311255",
    "game/data/garage.json": "6591412faff11f3b238a3b5f3168d7c65b89642332e6b23902ae54cb380aeeac",
    "game/data/historical/H01.json": "90cb5378fa472fc7aed14ad5c7f530d5b7915a3a7e328fa73066d4209f5ef00d",
    "game/data/historical/H02.json": "7ecc7bb4aa7efbe911a217f2f4a8e89ac5c27a8737add08f1e665f5f847efc55",
    "game/data/historical/H03.json": "2fbcf9d156ad112115321d5e7d09c82f62ef7d3b7f1a93b31868a87854da6e2c",
    "game/data/historical/H04.json": "1837a58eb2bdcaf09b9c40f9ba89322fcc01eb596795645aa87a6a23c81362c6",
    "game/data/historical/H06.json": "10e4f929707e658fcf6eadf9db742e7e551688de19c153f4d725c8cfaf95faeb",
    "game/data/historical/H07.json": "93288cd5dd7fb44b9704407580c86d305c0e3313dd352bf0edd47e5f2834e697",
    "game/data/historical/H09.json": "3c9cd59c0181da919f2541868804f29dccfd4f0a1e5374b5cb88eb7354b608d9",
    "game/data/historical/H11.json": "84b195c733a50da8b595995dd1cdbce0993910767c4a48fa864b6736cbe4bf48",
    "game/data/historical/H16.json": "9f7d05448012f3b34960416d6d0231b79538b45b3a5c0e91673700330fca75f0",
    "game/data/historical/H26.json": "949dfd9a3a6be7572f7615c360acd88f6a1bb37784333c840ed39495613934c5",
    "game/data/historical/H29.json": "16dc85dbec8e1cba7fd78f13b5e0c93882868606d15d9f3f06cf8bb06a8f1e12",
    "game/data/historical/H36.json": "653f8e81d63fe17e38edccb79c93e34226bc6c02554e928f3d8dc46ad17ab98d",
    "game/data/house.json": "fc8bfa5e90479812cc5709d3a135d105409446669ab3df5e61f2d7e78df0fe5d",
    "game/data/house_challenge.json": "7b81a658c943d41123d8cf0e2a6489265caab885c7b941b6444e0edafaf090dc",
    "game/data/motel.json": "5055958db82d4ee9558aa5f763fca0f7eac18531aa59c89934a2779c64d9bf9b",
    "game/data/offices.json": "79cec900eca0fcee4794400badc78fecb4d8b5c1624fdd8dd9819aec4899c3d7",
    "game/data/shops.json": "bbd46017b8e931dab596cc11db9ec28defb22a40260ab780a36142d8f26be0ad",
    "game/data/terminal.json": "3133d32375cad70d7534d655c040161c1509deba0f306e5b0d7584a67db4a7ae",
    "game/data/tutorial.json": "0f81acef660bb24e54900d4868f974d7a0237a52594890b9b3dd51d736b2d163"
}


def restore_historical_metadata(text):
    return text.replace('  "schema_version": 6,\n', '  "schema_version": 2,\n', 1).replace('  "roe": "precision",\n', '', 1)


class HistoricalDoctrineTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.kinds = set(prop_assets())
        cls.historical = sorted(path for path in ORIGINAL_SHA256 if "/historical/" in path)
        cls.legacy = sorted(path for path in ORIGINAL_SHA256 if "/historical/" not in path)

    def test_exact_roster(self):
        self.assertEqual(len(self.historical), 12)
        self.assertEqual(len(self.legacy), 13)
        self.assertEqual([Path(path).stem for path in self.historical], ['H01', 'H02', 'H03', 'H04', 'H06', 'H07', 'H09', 'H11', 'H16', 'H26', 'H29', 'H36'])
        self.assertEqual(sorted(path.name for path in (ROOT / "game/data/historical").glob("H*.json")), ['H01.json', 'H02.json', 'H03.json', 'H04.json', 'H06.json', 'H07.json', 'H09.json', 'H11.json', 'H16.json', 'H26.json', 'H29.json', 'H36.json'])

    def test_only_two_metadata_fields_change(self):
        for relative in self.historical:
            with self.subTest(path=relative):
                text = (ROOT / relative).read_text()
                mission = json.loads(text)
                restored = restore_historical_metadata(text)
                original = json.loads(restored)
                self.assertEqual(mission["schema_version"], 6)
                self.assertEqual(mission["roe"], "precision")
                self.assertEqual(original["schema_version"], 2)
                self.assertNotIn("roe", original)
                self.assertEqual(hashlib.sha256(restored.encode()).hexdigest(), ORIGINAL_SHA256[relative])
                self.assertEqual(set(mission), set(original) | {"roe"})
                for key in original:
                    if key != "schema_version": self.assertEqual(mission[key], original[key], key)

    def test_all_historical_documents_validate(self):
        for relative in self.historical:
            with self.subTest(path=relative):
                document = json.loads((ROOT / relative).read_text())
                self.assertEqual(validate_document(document, self.kinds), [])

    def test_original_fictional_bytes_stay_exact(self):
        for relative in self.legacy:
            with self.subTest(path=relative):
                raw = (ROOT / relative).read_bytes()
                self.assertEqual(hashlib.sha256(raw).hexdigest(), ORIGINAL_SHA256[relative])
                self.assertEqual(json.loads(raw)["schema_version"], 1)

    def test_future_generator_uses_the_same_metadata(self):
        builder = MapBuilder("H01", "Header fixture", [64, 64],  6)
        self.assertEqual(builder.data["roe"], "precision")
        self.assertEqual(builder.data["seed"], 20261010)

    def test_room_control_remains_runtime_only(self):
        document = json.loads((ROOT / self.historical[0]).read_text())
        for key in ("room_states", "room_states_observed", "room_doctrine"):
            self.assertNotIn(key, document)
            corrupted = deepcopy(document)
            corrupted[key] = {}
            self.assertTrue(validate_document(corrupted, self.kinds), key)


if __name__ == "__main__":
    unittest.main()
