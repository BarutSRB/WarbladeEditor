#!/usr/bin/env python3

from __future__ import annotations

import json
import unittest
from pathlib import Path

import letter_award_extract


PROJECT_ROOT = Path(__file__).resolve().parents[1]


class LetterAwardEvidenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.committed = json.loads(
            letter_award_extract.DEFAULT_OUTPUT.read_text(encoding="utf-8")
        )
        cls.generated = letter_award_extract.build_document(
            letter_award_extract.DEFAULT_EXE
        )

    def test_committed_evidence_is_exact_regeneration(self) -> None:
        self.assertEqual(self.generated, self.committed)

    def test_contract_pins_the_retail_award_values(self) -> None:
        contract = self.committed["contract"]
        self.assertEqual(100, contract["letter_collect_score"])
        self.assertEqual(5000000, contract["sequence_super_score"])
        self.assertEqual(1000000, contract["all_collected_score"])
        self.assertEqual(10, contract["all_collected_bonus_time_grant"])
        self.assertTrue(contract["score_multiplier_applies"])
        self.assertFalse(contract["flags_cleared_by_completion"])
        self.assertEqual(["E", "X", "T", "R", "A"], contract["forward_sequence"])
        self.assertEqual(["A", "R", "T", "X", "E"], contract["reverse_sequence"])

    def test_banners_reference_the_dispatcher(self) -> None:
        banners = self.committed["banners"]
        self.assertEqual(
            {"extra", "super_extra", "artxe", "super_artxe"}, set(banners)
        )
        for banner in banners.values():
            self.assertTrue(banner["dispatcher_reference_va"].startswith("0x0057"))

    def test_simulation_constants_match_the_evidence(self) -> None:
        simulation = (PROJECT_ROOT / "src" / "sim" / "game_simulation.gd").read_text(
            encoding="utf-8"
        )
        contract = self.committed["contract"]
        self.assertIn(
            "const LETTER_COLLECT_SCORE := %d" % contract["letter_collect_score"],
            simulation,
        )
        self.assertIn(
            "const LETTER_SEQUENCE_SUPER_SCORE := %d"
            % contract["sequence_super_score"],
            simulation,
        )
        self.assertIn(
            "const LETTER_ALL_COLLECTED_SCORE := %d"
            % contract["all_collected_score"],
            simulation,
        )
        self.assertIn(
            "const LETTER_ALL_COLLECTED_BONUS_TIME := %d"
            % contract["all_collected_bonus_time_grant"],
            simulation,
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
