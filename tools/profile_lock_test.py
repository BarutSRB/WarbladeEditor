#!/usr/bin/env python3

from __future__ import annotations

import json
import re
import unittest
from pathlib import Path

import profile_lock_extract


PROJECT_ROOT = Path(__file__).resolve().parents[1]


class ProfileLockEvidenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.committed = json.loads(
            profile_lock_extract.DEFAULT_OUTPUT.read_text(encoding="utf-8")
        )
        cls.generated = profile_lock_extract.build_document(
            profile_lock_extract.DEFAULT_EXE
        )

    def test_committed_evidence_is_exact_regeneration(self) -> None:
        self.assertEqual(self.generated, self.committed)

    def test_tier_tables_are_complete(self) -> None:
        contract = self.committed["contract"]
        self.assertEqual(9, len(contract["score_tiers"]))
        self.assertEqual(9, len(contract["grouped_best_tiers"]))
        self.assertEqual(11, len(contract["games_played_tiers"]))
        self.assertEqual(
            [5000000, 7500000, 10000000, 20000000, 50000000,
             100000000, 250000000, 500000000, 1000000000],
            [tier["threshold"] for tier in contract["score_tiers"]],
        )
        self.assertEqual(
            [1000, 2500, 5000, 10000, 15000, 20000, 25000, 35000,
             50000, 75000, 100000],
            [tier["threshold"] for tier in contract["games_played_tiers"]],
        )

    def test_evaluator_covers_every_threshold(self) -> None:
        evaluator = (
            PROJECT_ROOT / "src" / "client" / "match_config.gd"
        ).read_text(encoding="utf-8")
        contract = self.committed["contract"]
        for tier in contract["score_tiers"]:
            self.assertIn(
                f"best_score >= {tier['threshold']}",
                evaluator,
                f"score tier {tier['threshold']} must be evaluated",
            )
        for tier in contract["games_played_tiers"]:
            self.assertIn(
                f"games_played >= {tier['threshold']}",
                evaluator,
                f"games tier {tier['threshold']} must be evaluated",
            )
        self.assertIn("secret_counter", evaluator)
        self.assertIn("highest_rank >= 32", evaluator)
        # The only-blue-coins lock keys on games played, never on score.
        self.assertNotIn(
            'best_score", 0)) >= 20000',
            evaluator,
            "only-blue-coins must come from the games-played lock",
        )

    def test_simulation_consumes_the_start_state(self) -> None:
        simulation = (
            PROJECT_ROOT / "src" / "sim" / "game_simulation.gd"
        ).read_text(encoding="utf-8")
        for key in (
            "_apply_profile_start_state",
            "autofire_through_shop",
            "_apply_shop_exit_auto_fire_reset",
            "excluded_bonus_types",
            "_locked_out_bonus_types",
        ):
            self.assertIn(key, simulation)


if __name__ == "__main__":
    unittest.main(verbosity=2)
