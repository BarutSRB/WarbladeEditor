#!/usr/bin/env python3

from __future__ import annotations

import json
import struct
import unittest
from pathlib import Path

from difficulty_rules import (
    PEImage,
    WARBLADE_EXE_SHA256,
    build_evidence,
)


ROOT = Path(__file__).resolve().parents[1]
EXE = ROOT / "Game" / "warblade.exe"
DECODED = ROOT / "content" / "lvd_decoded"
GENERATED = ROOT / "docs" / "evidence" / "difficulty_rules.json"


class DifficultyRuleExtractionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.image = PEImage(EXE)
        cls.evidence = build_evidence(EXE.resolve(), DECODED.resolve())

    def test_retail_identity_enum_and_jump_table(self) -> None:
        self.assertEqual(self.image.sha256, WARBLADE_EXE_SHA256)
        self.assertEqual(self.evidence["schema"], "warblade-difficulty-rules-v2")
        enum = self.evidence["difficulty_enum"]
        self.assertEqual(
            enum["jump_table"],
            ["0x005687a3", "0x005688d2", "0x00568a01", "0x00568b34"],
        )
        self.assertEqual(
            [(item["numeric_id"], item["menu_label"]) for item in enum["cases"]],
            [(0, "EASY"), (1, "NORMAL"), (2, "HARD"), (3, "ACE")],
        )
        self.assertEqual(
            self.image.bytes_at(0x0056877E, 5),
            b"\xA1\x40\x79\xAF\x00",
        )

    def test_all_28_case_assignments_are_extracted(self) -> None:
        cases = self.evidence["difficulty_init"]["assignments_by_difficulty"]
        expected_destinations = {
            item["destination_va"] for item in cases["easy"]
        }
        self.assertEqual(len(expected_destinations), 28)
        for difficulty in ("easy", "normal", "hard", "ace"):
            self.assertEqual(len(cases[difficulty]), 28)
            self.assertEqual(
                {item["destination_va"] for item in cases[difficulty]},
                expected_destinations,
            )

    def test_critical_float_bits_and_runtime_values(self) -> None:
        runtime = self.evidence["difficulty_init"]["runtime_summary"]
        self.assertEqual(runtime["easy"]["simulation_scale"]["bits"], "0x3f800000")
        self.assertEqual(runtime["normal"]["simulation_scale"]["bits"], "0x3f800000")
        self.assertEqual(runtime["hard"]["simulation_scale"]["bits"], "0x3f955555")
        self.assertEqual(runtime["ace"]["simulation_scale"]["bits"], "0x3faaaaab")
        self.assertEqual(
            runtime["normal"]["alien_projectile_base_speed"]["bits"],
            "0x4089999a",
        )
        self.assertEqual(
            runtime["hard"]["alien_projectile_default_vertical_speed"]["bits"],
            "0x40baaaaa",
        )
        self.assertEqual(
            runtime["ace"]["alien_projectile_default_vertical_speed"]["bits"],
            "0x40eaaaab",
        )
        self.assertEqual(
            [
                runtime[item]["timer_a_initial_adjustment"]
                for item in ("easy", "normal", "hard", "ace")
            ],
            [400, 200, -50, -200],
        )
        self.assertEqual(
            [
                runtime[item]["timer_a_floor"]
                for item in ("easy", "normal", "hard", "ace")
            ],
            [300, 200, 190, 180],
        )

    def test_first_five_health_and_timer_transforms(self) -> None:
        levels = self.evidence["first_five_levels"]["levels"]
        expected_authored = [
            (1, 2400, 100, 2400, 100),
            (1, 2400, 85, 2400, 85),
            (1, 2400, 75, 2400, 80),
            (1, 1500, 44, 0, 20),
            (1, 2394, 85, 2906, 105),
        ]
        for level, expected in zip(levels, expected_authored, strict=True):
            contract = level["unique_authored_enemy_contracts"]
            self.assertEqual(len(contract), 1)
            self.assertEqual(
                (
                    contract[0]["base_health"],
                    contract[0]["timer_a_initial"],
                    contract[0]["timer_a_step"],
                    contract[0]["timer_b_initial"],
                    contract[0]["timer_b_step"],
                ),
                expected,
            )
            for difficulty in ("easy", "normal", "hard", "ace"):
                self.assertEqual(
                    level["by_difficulty"][difficulty]["enemy_health_result"],
                    [1],
                )
        level_one = levels[0]["by_difficulty"]
        self.assertEqual(
            [
                level_one[item]["timer_contracts"][0]["spawn_runtime"]["timer_a"]
                for item in ("easy", "normal", "hard", "ace")
            ],
            [2800, 2600, 2350, 2200],
        )
        level_four = levels[3]["by_difficulty"]
        self.assertEqual(
            [
                level_four[item]["timer_contracts"][0]["spawn_runtime"]["timer_b"]
                for item in ("easy", "normal", "hard", "ace")
            ],
            [400, 200, 190, 180],
        )

    def test_timer_updates_are_kill_count_not_tick_scale(self) -> None:
        self.assertEqual(
            self.image.bytes_at(0x0058B9A4, 14),
            bytes.fromhex("8b9432c89b84000faf95ecfeffff"),
        )
        timer = self.evidence["first_five_levels"]
        self.assertIn("qualifying enemy destructions", timer["timer_rule"])
        self.assertNotIn("tick_scale", timer["timer_rule"])
        self.assertEqual(len(timer["timer_kill_counter_increment_vas"]), 6)

    def test_fire_rng_and_strict_threshold(self) -> None:
        fire = self.evidence["alien_fire"]
        self.assertEqual(fire["rng"]["unit_scale"], 2.0**-32)
        self.assertEqual(fire["threshold"]["double_two"], 2.0)
        self.assertEqual(
            fire["threshold"]["strict_condition"],
            "fire only when r < 2 * simulation_scale",
        )
        self.assertEqual(
            self.image.bytes_at(0x00607793, 7),
            bytes.fromhex("db8408cc9b8400"),
        )
        self.assertEqual(
            self.image.bytes_at(0x006077AC, 16),
            bytes.fromhex("d9057412e100dc0d409b7700ded9dfe0"),
        )
        self.assertEqual(
            self.image.bytes_at(0x0052F83F, 27),
            bytes.fromhex(
                "dfad30ffffffdc8d38ffffffdc0d908e7700d84508d99d2cffffff"
            ),
        )

    def test_simulation_scale_reaches_activation_paths_and_player(self) -> None:
        self.assertEqual(
            self.evidence["simulation_scale"]["retail_update_target"]["value"],
            60,
        )
        self.assertEqual(
            self.image.bytes_at(0x005A0830, 10),
            bytes.fromhex("c7059078af003c000000"),
        )
        self.assertEqual(
            self.image.bytes_at(0x00607F5A, 6),
            bytes.fromhex("d9057412e100"),
        )
        self.assertEqual(
            self.image.bytes_at(0x00613A4A, 13),
            bytes.fromhex("d98432609a8400d80d7412e100"),
        )
        self.assertEqual(
            self.image.bytes_at(0x005EB6CD, 9),
            bytes.fromhex("d945ecd80d7412e100"),
        )
        consumers = {
            item["role"] for item in self.evidence["simulation_scale"]["consumers"]
        }
        self.assertEqual(
            consumers,
            {
                "enemy activation countdown",
                "enemy path position, velocity, and progress",
                "player movement",
                "alien projectile velocity",
            },
        )

    def test_health_addition_starts_zero_and_has_no_difficulty_write(self) -> None:
        self.assertEqual(
            self.image.bytes_at(0x0053818A, 8),
            bytes.fromhex("d9eed91df813e100"),
        )
        for assignments in self.evidence["difficulty_init"][
            "assignments_by_difficulty"
        ].values():
            self.assertNotIn(
                "0x00e113f8",
                {item["destination_va"] for item in assignments},
            )
        self.assertEqual(
            self.image.bytes_at(0x0056D094, 6),
            bytes.fromhex("d905f813e100"),
        )

    def test_border_mapping(self) -> None:
        self.assertEqual(
            [
                (item["difficulty"], item["numeric_id"], item["filename"])
                for item in self.evidence["borders"]
            ],
            [
                ("easy", 0, "border_easy.jpg"),
                ("normal", 1, "border.jpg"),
                ("hard", 2, "border_hard.jpg"),
                ("ace", 3, "border_ace.jpg"),
            ],
        )
        self.assertEqual(
            self.image.bytes_at(0x005A2D32, 5),
            b"\x68" + struct.pack("<I", 0x007826D8),
        )
        self.assertEqual(
            self.image.bytes_at(0x0061F9E1, 7),
            bytes.fromhex("833d4079af0003"),
        )

    def test_three_means_total_fighters_and_third_death_is_terminal(self) -> None:
        lives = self.evidence["lives"]
        self.assertEqual(lives["raw_encoding"], {
            "base": 26,
            "step": 4,
            "initial_offset": 12,
            "maximum_offset": 20,
        })
        self.assertEqual(lives["initial_total_fighters"], 3)
        self.assertEqual(lives["maximum_total_fighters"], 5)
        self.assertEqual(lives["hud"]["initial_reserve_icons"], 2)
        self.assertEqual(lives["storage"]["session_stride"], "0x4d8")
        self.assertIn("own encoded fighter", lives["storage"]["retail_ownership"])
        self.assertEqual(
            [
                (item["fighters_after_decrement"], item["respawns"])
                for item in lives["death_and_respawn"]["initial_death_sequence"]
            ],
            [(2, True), (1, True), (0, False)],
        )
        self.assertEqual(
            self.image.bytes_at(0x005ECFD7, 12),
            bytes.fromhex("8b90508784002b5104a14020"),
        )
        self.assertEqual(
            self.image.bytes_at(0x005ED07C, 10),
            bytes.fromhex("8b90508784003b110f8e"),
        )

    def test_drop_consumer_is_proven_and_cash_is_evidence_only(self) -> None:
        boundary = self.evidence["score_and_cash"]
        self.assertEqual(
            boundary["score"]["direct_difficulty_references_in_bounded_path"],
            [],
        )
        self.assertEqual(boundary["score"]["confidence"], "supported")
        drop = boundary["falling_bonus_drop"]
        self.assertEqual(drop["confidence"], "proven")
        self.assertEqual(
            {
                difficulty: item["value"]
                for difficulty, item in drop["denominators"].items()
            },
            {"easy": 18, "normal": 28, "hard": 38, "ace": 48},
        )
        self.assertEqual(
            [item["sha256"] for item in drop["consumer_regions"]],
            [
                "0b460ce357f41c34d27162607b458d4f79b5bf6bb5f811632eed0f9e73e71a73",
                "7bd6fe35e6bf561d1b55e53d10a9582ccbf5bada2ad128f1f32173f24d948d7b",
            ],
        )
        self.assertEqual(
            drop["integer_range"]["sha256"],
            "b27d59c32a354995f57f49207261c37579988725cf7a33f6d2bf72a724f29ec0",
        )
        self.assertEqual(
            drop["runtime_contract"],
            "1 + (U32 mod (denominator - 1)) < 4",
        )
        self.assertEqual(boundary["cash"]["confidence"], "evidence_only")
        self.assertIsNone(boundary["cash"]["runtime_consumer"])
        self.assertIn(
            "not proof",
            boundary["score"]["conclusion"].lower(),
        )

    def test_difficulty_assignment_classifications_match_runtime_reachability(self) -> None:
        easy = {
            item["destination_va"]: item
            for item in self.evidence["difficulty_init"][
                "assignments_by_difficulty"
            ]["easy"]
        }
        self.assertEqual(
            easy["0x008f203c"]["name"],
            "falling_bonus_drop_denominator",
        )
        self.assertEqual(easy["0x008f203c"]["confidence"], "proven")
        self.assertEqual(
            easy["0x008f2068"]["name"],
            "state_six_aimed_shot_travel_multiplier",
        )
        self.assertIn("travel divisor", easy["0x008f2068"]["role"])
        for address in (
            "0x008f2058",
            "0x008f2024",
            "0x008f2028",
            "0x008f202c",
            "0x008f2074",
        ):
            self.assertEqual(easy[address]["confidence"], "evidence_only")
        for address in (
            "0x008f20a4",
            "0x008f2094",
            "0x008f2098",
            "0x008f209c",
            "0x008f2020",
            "0x008f2068",
        ):
            self.assertEqual(easy[address]["confidence"], "proven")

        expected_travel_multipliers = {
            "easy": 3.0,
            "normal": 2.200000047683716,
            "hard": 2.0,
            "ace": 1.7999999523162842,
        }
        for difficulty, expected_value in expected_travel_multipliers.items():
            runtime = self.evidence["difficulty_init"]["runtime_summary"][
                difficulty
            ]
            self.assertEqual(
                expected_value,
                runtime["state_six_aimed_shot_travel_multiplier"]["value"],
            )

    def test_generated_json_is_current(self) -> None:
        generated = json.loads(GENERATED.read_text(encoding="utf-8"))
        self.assertEqual(generated, self.evidence)


if __name__ == "__main__":
    unittest.main(verbosity=2)
