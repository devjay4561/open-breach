"""P7 control puzzles must change playable data, not only briefing text."""
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ControlContentTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.maps = {i: json.loads((ROOT / f"game/data/cqb/CQB{i:02}.json").read_text())
                    for i in range(7, 13)}

    def test_eight_occupied_rooms_two_entrances_one_bypass(self):
        for id, data in self.maps.items():
            with self.subTest(id=id):
                indoor = [r for r in data["rooms"] if r["indoor"]]
                self.assertEqual(len(indoor), 8)
                self.assertEqual(len(data["rooms"]), 9)
                self.assertEqual(len(data["doors"]), 10)
                self.assertEqual(len(data["enemies"]), 8)
                adjacent = []
                for portal in data["doors"]:
                    dx, dz = (0, .4) if portal["axis"] == "x" else (.4, 0)
                    sides = []
                    for sign in (-1, 1):
                        x, z = portal["x"] + sign * dx, portal["z"] + sign * dz
                        matches = [r for r in data["rooms"]
                                   if abs(x-r["x"]) < r["w"]/2
                                   and abs(z-r["z"]) < r["d"]/2]
                        self.assertEqual(len(matches), 1)
                        sides.append(matches[0])
                    self.assertNotEqual(sides[0]["id"], sides[1]["id"])
                    adjacent.append(sides)
                inside_edges = [(a["id"], b["id"]) for a, b in adjacent if a["indoor"] and b["indoor"]]
                self.assertEqual(len(inside_edges), 8)  # Connected eight-node tree plus one cycle.
                self.assertEqual(sum(not a["indoor"] or not b["indoor"] for a, b in adjacent), 2)
                reached = {indoor[0]["id"]}
                for _ in range(8):
                    reached.update(b for a, b in inside_edges if a in reached)
                    reached.update(a for a, b in inside_edges if b in reached)
                self.assertEqual(reached, {r["id"] for r in indoor})
                occupied = set()
                for enemy in data["enemies"]:
                    self.assertEqual(len(enemy["spawns"]), 2)
                    self.assertEqual(enemy["spawns"][0], {k: enemy[k] for k in ("x", "z", "facing", "patrol") if k in enemy})
                    for spawn in enemy["spawns"]:
                        room = next(r for r in indoor if abs(spawn["x"]-r["x"]) < r["w"]/2 and abs(spawn["z"]-r["z"]) < r["d"]/2)
                        occupied.add(room["id"])
                self.assertEqual(len(occupied), 8)

    def test_wide_and_t_junction_have_real_portals(self):
        wide, junction = self.maps[7], self.maps[8]
        self.assertTrue(all(min(r["w"], r["d"])-.24 > 1.8 for r in wide["rooms"] if r["indoor"]))
        self.assertTrue(any(e.get("response_role") == "patrol" and e.get("patrol") for e in wide["enemies"]))
        portals = {d["id"]: d for d in junction["doors"]}
        self.assertNotIn("inner_v0", portals)
        self.assertEqual([portals["inner_v1"]["x"], portals["inner_v1"]["z"]], [11.4, 8.6])
        self.assertTrue({"inner_h1_0", "inner_h1_1", "inner_v1"} <= portals.keys())
        self.assertEqual(sum(u.get("stance") == "crouched" for u in junction["units"]), 2)

    def test_signal_identification_reload_and_fragment_rules(self):
        quiet, identify, reload, fragments = (self.maps[i] for i in range(9, 13))
        self.assertEqual(quiet["noise_discipline"], "hand_signals")
        self.assertTrue(all(u["weapon"] == "suppressed" and u["movement_mode"] == "careful" for u in quiet["units"]))
        self.assertTrue(any(e.get("response_role") == "reserve" for e in quiet["enemies"]))
        self.assertEqual(identify["roe"], "precision")
        self.assertEqual(len(identify["civilians"]), 2)
        self.assertTrue(any(r["type"] == "secure_all_civilians" for r in identify["win"]))
        self.assertTrue(any(s["stat"] == "arrests" and s["op"] == "gte" for s in identify["stars"]))
        self.assertTrue(all(u["ammo"] == 3 and u["reserve_ammo"] > 3 for u in reload["units"]))
        self.assertTrue(any(s["stat"] == "reloads" and s["value"] >= 1 for s in reload["stars"]))
        self.assertEqual(fragments["roe"], "high_intensity")
        self.assertEqual(fragments["civilians"], [])
        self.assertTrue(all(u["equipment"].get("frag") == 1 for u in fragments["units"]))
        self.assertTrue(all(w["material"] == "drywall" and w["penetration_resistance"] < .6 for w in fragments["walls"] if w["id"].startswith("partition_")))
        self.assertTrue(any(s["stat"] == "unit_damage" and s["value"] == 0 for s in fragments["stars"]))


if __name__ == "__main__":
    unittest.main()
