"""Freeze pre-fictionalization gameplay data and GLB binary geometry."""
import hashlib
import json
from pathlib import Path
import struct
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from historical_maps.dossiers import DOSSIERS

NARRATIVE = ['title', 'title_en', 'description', 'description_en', 'historical', 'briefing', 'label', 'name', 'objectives', 'biome']
MAP_GEOMETRY = {'H01': '83b29db915bdcd3ca7e9f2e1f8cc850e1bb380dc4ce19ea809a0cca96371c708',
 'H02': '041f2c845b2b186791521a441b39050d7d6707dea24122525d17d49b5dcc9e6f',
 'H03': 'e84ab6bb3e11a662e53989aa15edeb5a9254b650da32cabfbb6522faf8770d23',
 'H04': 'ee9bbca34c4f33ca5bb1ad555f33265cd5a9109401c34c9e4f49dd190d6c72f0',
 'H06': '8b4b45d11dde20d3bb4df403795e793122ba52c9291be63fa86a8cf59792a12a',
 'H07': '8c2c572fea5b70b6b6b3ac32e9174156a36d0ac2cca5f45189d402f1f5301388',
 'H09': '328afce6f11615a479813ab520797d4bdd045b1019abf01b247ba1f29751d15b',
 'H11': '9b917342926d387c40053796c928606cdcf3fdfebe102bc6262e6a1400f5d2c7',
 'H16': '853fcd739f102ff170375caa03ea101e2ea7e59d10e73b8ed4c51f25b93f7e02',
 'H26': 'b9d546cfe80250c824f51ddf7aa2e1bc1d2093324a0d8d76f1e7a515baee9502',
 'H29': 'eadaf0af78db1ad29e92c0b5e9d4524655d47168246f9c8add4c0a7ed3412987',
 'H36': '029a1c35cfadaa8d1ae2f9c01c1b6f9dd809e3d7d5fd10849fb916d76c875a06'}
GLB_BINARY = {'airliner_quadjet': '07e35ba406aa820762612ae0adaed1581fc9e99a25fed3799b8f2234ce1d1bd3',
 'airliner_reartwin': '2d5d3919d74bb4f22570b85dc0296b4d94aecb6d3f78f12f3c630d350e20ad9d',
 'airliner_twinjet': 'b834913e8fcb223bb605c3861949ccc2029b85b60be4d3023b55660ca988591d',
 'bush': '59296d5285d435aa085a2cefd3375f7c5a21076e14332b89147275ae2d63ed20',
 'cargo_truck': 'c954bcf213c2e01ac51a84347358347ef68ccf3d2fc68f0d2cf05af6e9e4415d',
 'helicopter_heavy_lift': '0de2ff93744f1a8e42f565952d5b894512c89dd91decba1d43fd36cf5033c57b',
 'hut': '11729ad5ec4fd2539a8cc9ec6968bf96c7355d3ee21e2a5c8175b1ea16cb45c8',
 'palm_tree': 'cd8d82626944f1b6f7c6fe7d88fdc6d094bb0938fc2600e56f0c4c65798536d7',
 'pine_tree': '941d63e9c3f15539df2589cef97f3ea8190ef36a362841a5741e2d7fa6dc7557',
 'tanker_deck_pipes': 'ba934dbb18afba08ba5a6cfe52e03dd6e95b585d1c29ac0e6eb2370c63ad173b',
 'tanker_ship_hull': 'f840bab970a01be61ec62681743aa63630a8402bd6f6f937ace0a0c60b3e7643',
 'tanker_superstructure': 'c5833d74280ffd01bce114b65e93be9394a2a6a805206f407b6b8e3bcaefb0f7',
 'terrace_townhouse': '1594295204f9f3141f363e4f325bbcca388363766541099b77e22895c8710784',
 'utility_vehicle': '4e37e44f9978258148f4c8cc8f76afd1bd317306bce5e96bfb29fb608f3d19a4',
 'watchtower': '782499819a151887fefaca82944af520ef7b8b2326bbcce09760e37386ef1f12'}


def gameplay(value):
    if isinstance(value, dict):
        return {key: gameplay(item) for key, item in value.items() if key not in NARRATIVE}
    if isinstance(value, list):
        return [gameplay(item) for item in value]
    return value


class SpecialOpsTest(unittest.TestCase):
    def test_original_gameplay_and_localized_dossiers(self):
        self.assertEqual(set(DOSSIERS), set(MAP_GEOMETRY))
        for mid, expected in MAP_GEOMETRY.items():
            with self.subTest(mission=mid):
                data = json.loads((ROOT / f"game/data/historical/{mid}.json").read_text())
                payload = json.dumps(gameplay(data), sort_keys=True, ensure_ascii=False).encode()
                self.assertEqual(hashlib.sha256(payload).hexdigest(), expected)
                title, title_en, location, location_en, _, note, note_en = DOSSIERS[mid]
                self.assertEqual((data["title"], data["title_en"]), (title, title_en))
                self.assertEqual(data["historical"], dict(location=location, location_en=location_en,
                    accuracy_note=note, accuracy_note_en=note_en))
                self.assertRegex(title_en, r"^[A-Z]+ [A-Z]+$")

    def test_original_mesh_binary_chunks(self):
        for asset, expected in GLB_BINARY.items():
            with self.subTest(asset=asset):
                raw = (ROOT / f"game/assets/historical/{asset}.glb").read_bytes()
                length = struct.unpack_from("<I", raw, 12)[0]
                self.assertEqual(hashlib.sha256(raw[20 + length:]).hexdigest(), expected)


if __name__ == "__main__":
    unittest.main()
