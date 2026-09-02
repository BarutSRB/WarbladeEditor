#!/usr/bin/env python3

from __future__ import annotations

import json
import unittest
from pathlib import Path

import game_bonus_tally_extract


PROJECT_ROOT = Path(__file__).resolve().parents[1]


class GameBonusTallyEvidenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.committed = json.loads(
            game_bonus_tally_extract.DEFAULT_OUTPUT.read_text(encoding="utf-8")
        )
        cls.generated = game_bonus_tally_extract.build_document(
            game_bonus_tally_extract.DEFAULT_EXE
        )

    def test_committed_evidence_is_exact_regeneration(self) -> None:
        self.assertEqual(self.generated, self.committed)

    def test_rank_bonus_table_shape_and_sums(self) -> None:
        table = self.committed["rank_bonus_table"]
        self.assertEqual(33, len(table))
        self.assertEqual(10000, table[0])
        self.assertEqual(50000000, table[-1])
        # Cumulative sums for the traced 1-based consumption.
        self.assertEqual(20000, sum(table[1:2]))
        self.assertEqual(200000, sum(table[1:6]))
        self.assertEqual(sum(table[1:33]), sum(table) - table[0])

    def test_contract_values(self) -> None:
        contract = self.committed["contract"]
        self.assertEqual(100, contract["cash_left_points_per_money_unit"])
        self.assertEqual(100000, contract["perfect_points"])
        self.assertEqual(1000, contract["hit_percent_points"])
        self.assertEqual(100, contract["hit_percent_clamp"])
        self.assertTrue(contract["profile_statistics_use_raw_score"])
        self.assertFalse(contract["max_cash_bonus"]["reachable"])
        self.assertEqual(50000000, contract["max_cash_bonus"]["value"])

    def test_simulation_constants_match_the_evidence(self) -> None:
        simulation = (PROJECT_ROOT / "src" / "sim" / "game_simulation.gd").read_text(
            encoding="utf-8"
        )
        contract = self.committed["contract"]
        self.assertIn(
            "const TALLY_CASH_POINTS_PER_MONEY := %d"
            % contract["cash_left_points_per_money_unit"],
            simulation,
        )
        self.assertIn(
            "const TALLY_PERFECT_POINTS := %d" % contract["perfect_points"],
            simulation,
        )
        self.assertIn(
            "const TALLY_HIT_PERCENT_POINTS := %d"
            % contract["hit_percent_points"],
            simulation,
        )
        import re

        table_match = re.search(
            r"const TALLY_RANK_BONUS_TABLE := \[(.*?)\]",
            simulation,
            re.DOTALL,
        )
        self.assertIsNotNone(table_match, "simulation must declare the rank bonus table")
        values = [
            int(value)
            for value in re.findall(r"\d+", table_match.group(1))
        ]
        self.assertEqual(self.committed["rank_bonus_table"], values)


if __name__ == "__main__":
    unittest.main(verbosity=2)
