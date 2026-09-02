#!/usr/bin/env python3

from __future__ import annotations

import json
import unittest
from pathlib import Path

from weapon_runtime_extract import (
    WARBLADE_EXE_SHA256,
    build_evidence,
)


ROOT = Path(__file__).resolve().parents[1]
EXE = ROOT / "Game" / "warblade.exe"
MANUAL = ROOT / "Game" / "Warblade_Manual_V1.34_Eng.txt"
GENERATED = ROOT / "docs" / "evidence" / "weapon_runtime.json"


class WeaponRuntimeExtractionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.evidence = build_evidence(EXE.resolve(), MANUAL.resolve())
        cls.generated = json.loads(GENERATED.read_text(encoding="utf-8"))

    def test_retail_identity_and_generated_evidence(self) -> None:
        self.assertEqual(self.evidence["source"]["exe_sha256"], WARBLADE_EXE_SHA256)
        self.assertEqual(self.generated, self.evidence)
        self.assertGreaterEqual(len(self.evidence["verified_signatures"]), 30)

    def test_capacity_counts_every_allocated_root_and_child(self) -> None:
        capacity = self.evidence["projectile_capacity"]
        self.assertEqual(5, capacity["initial_capacity"])
        self.assertEqual(50, capacity["upgrade_cap"])
        self.assertEqual(1, capacity["normal_object_contribution"])
        self.assertIn("roots and children each count", capacity["semantics"])
        self.assertIn("above capacity", capacity["volley_gate"])
        self.assertIn("not recursively accumulated", capacity["child_origin"])

    def test_special_movement_encodings_are_exact(self) -> None:
        rules = {
            item["prototype_id"]: item
            for item in self.evidence["special_projectile_movement"][
                "prototype_rules"
            ]
        }
        self.assertEqual(
            (-2.5, 2.5),
            (rules[19]["vx_min"], rules[19]["vx_max"]),
        )
        for prototype_id in (20, 21):
            self.assertEqual(
                (-1.5, 1.5),
                (rules[prototype_id]["vx_min"], rules[prototype_id]["vx_max"]),
            )
        for prototype_id in (25, 26):
            self.assertEqual(
                (-15.0, 15.0),
                (
                    rules[prototype_id]["unscaled_random_min"],
                    rules[prototype_id]["unscaled_random_max"],
                ),
            )
        for prototype_id in (30, 31):
            self.assertEqual(
                (-10.0, 10.0),
                (
                    rules[prototype_id]["unscaled_random_min"],
                    rules[prototype_id]["unscaled_random_max"],
                ),
            )
        self.assertTrue(
            all(
                rules[item]["horizontal_velocity_after_spawn"] == 0
                for item in (25, 26, 30, 31)
            )
        )
        endpoint = self.evidence["special_projectile_movement"][
            "random_endpoint_inclusion"
        ]
        self.assertEqual("proven", endpoint["confidence"])
        self.assertEqual("0..0xffffffff", endpoint["raw_word_domain"])
        self.assertIn("float32 store", endpoint["note"])

    def test_laser_frame_collision_and_damage_contract(self) -> None:
        laser = self.evidence["laser"]
        self.assertEqual([22, 23, 24, 50, -1], laser["frame_chain"])
        self.assertEqual(4, laser["live_update_transitions"])
        self.assertEqual(
            {"22": 1, "23": 1, "24": 1, "50": 1},
            laser["persistent_flags_by_frame"],
        )
        self.assertEqual(10.0, laser["initial_damage"])
        self.assertEqual(12.0, laser["spawn_geometry"]["projectile_left_for_laser"])
        self.assertEqual(
            "-86 relative to retail player_y",
            laser["spawn_geometry"]["projectile_visual_top_for_laser"],
        )
        self.assertEqual(0, laser["collision_bounds"]["top"])
        self.assertEqual(
            "owning_player_current_retail_y",
            laser["collision_bounds"]["bottom"],
        )
        self.assertIn("never follows later player X", laser["attachment"])
        self.assertIn("current live retail Y", laser["attachment"])
        self.assertIn("10, 5, 2.5", laser["ordinary_enemy_damage_sequence"])
        collision_pass = laser["collision_pass_count"]
        self.assertEqual("proven", collision_pass["confidence"])
        self.assertEqual(4, collision_pass["count"])
        self.assertEqual([22, 23, 24, 50], collision_pass["frames"])
        self.assertIn("collision pass before projectile update", collision_pass["order"])

    def test_manual_autofire_and_super_autofire_timing(self) -> None:
        timing = self.evidence["fire_timing"]
        self.assertIsNone(timing["manual_fire"]["cooldown_ms"])
        auto = timing["autofire"]
        self.assertEqual(100, auto["default_delay_ms"])
        self.assertEqual(25, auto["super_delay_ms"])
        self.assertIn("current_ms > next_deadline", auto["deadline_rule"])
        self.assertIn("second Auto volley", auto["initial_edge_interaction"])

    def test_speed_shop_uses_live_difficulty_values(self) -> None:
        speed = self.evidence["speed_shop"]
        self.assertEqual(16.0, speed["maximum_upgrade_count"])
        expected = {
            "easy": (4.199999809265137, 0.800000011920929, 17.0),
            "normal": (4.0, 0.699999988079071, 15.199999809265137),
            "hard": (3.5, 0.6000000238418579, 13.100000381469727),
            "ace": (3.0, 0.5, 11.0),
        }
        for difficulty, values in expected.items():
            actual = speed["by_difficulty"][difficulty]
            self.assertEqual(
                values,
                (
                    actual["base"],
                    actual["increment"],
                    actual["stored_shop_ceiling"],
                ),
            )
        self.assertEqual(14.0, speed["movement_cap_before_tick_scale"])
        self.assertIn("overwritten", speed["bootstrap_correction"])

    def test_banking_preserves_fractional_endpoint_quirk(self) -> None:
        banking = self.evidence["fighter_banking"]
        self.assertEqual(5.0, banking["initial_phase"])
        self.assertEqual(0.5, banking["step_per_player_update"])
        self.assertIn("10.5", banking["right"])
        self.assertIn("toward 5", banking["idle"])

    def test_extra_life_and_armour_shop_caps(self) -> None:
        shop = self.evidence["first_shop_survivability"]
        life = shop["extra_life"]
        self.assertEqual(3, life["initial_total_fighters"])
        self.assertEqual(1, life["purchase_effect_total_fighters"])
        self.assertEqual(5, life["maximum_total_fighters"])
        armour = shop["armour"]
        self.assertEqual(0, armour["initial_charges"])
        self.assertEqual(1, armour["purchase_effect_charges"])
        self.assertEqual(2, armour["maximum_charges"])
        self.assertEqual(4000, armour["default_shield_ms"])


if __name__ == "__main__":
    unittest.main()
