#!/usr/bin/env python3

from __future__ import annotations

import json
import unittest
from pathlib import Path

from endless_progression_extract import (
    F64_CONSTANTS,
    INSTRUCTION_PINS,
    PEImage,
    WARBLADE_EXE_SHA256,
    build_evidence,
)


ROOT = Path(__file__).resolve().parents[1]
EXE = ROOT / "Game" / "warblade.exe"
GENERATED = ROOT / "docs" / "evidence" / "endless_progression.json"


class EndlessProgressionExtractionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.image = PEImage(EXE)
        cls.evidence = build_evidence(EXE.resolve())

    def test_retail_identity_and_schema(self) -> None:
        self.assertEqual(self.image.sha256, WARBLADE_EXE_SHA256)
        self.assertEqual(self.evidence["schema"], "warblade-endless-progression-v1")

    def test_generated_file_is_current(self) -> None:
        rendered = json.dumps(self.evidence, indent=2, ensure_ascii=False) + "\n"
        self.assertEqual(GENERATED.read_text(encoding="utf-8"), rendered)

    def test_all_instruction_pins_match(self) -> None:
        pins = self.evidence["instruction_pins"]
        self.assertEqual(len(pins), len(INSTRUCTION_PINS))
        for label, pin in pins.items():
            self.assertTrue(
                pin["matches_documented_bytes"],
                f"instruction bytes drifted at {label} ({pin['va']})",
            )

    def test_step_constants(self) -> None:
        constants = self.evidence["constants"]
        self.assertEqual(len(constants), len(F64_CONSTANTS))
        self.assertEqual(constants["ordinary_health_step"]["value"], 1.0)
        self.assertEqual(constants["special_health_step"]["value"], 5.0)
        self.assertEqual(
            constants["projectile_speed_step_multiplier"]["value"],
            1.024999976158142,
        )
        self.assertEqual(
            constants["simulation_scale_step"]["value"],
            0.11999999731779099,
        )
        self.assertEqual(
            constants["special_health_traced_class_multiplier"]["value"], 20.0
        )

    def test_step_trigger_is_per_hundred_above_five(self) -> None:
        trigger = self.evidence["step_trigger"]
        self.assertEqual(trigger["rule"], "level > 5 and (level - 1) mod 100 == 0")
        self.assertEqual(trigger["cumulative_steps_at_level"], "(level - 1) // 100")

    def test_timer_step_and_floor(self) -> None:
        timers = self.evidence["step_effects"]["timer_adjustments"]
        self.assertEqual(timers["per_step_decrement"], 50)
        self.assertEqual(timers["floor"], -500)

    def test_update_target_steps_by_difficulty(self) -> None:
        target = self.evidence["step_effects"]["update_target"]
        self.assertEqual(target["retail_default"], 60)
        self.assertEqual(
            target["per_step_increment_by_difficulty"],
            {"easy": 2, "normal": 3, "hard": 3, "ace": 2},
        )

    def test_mirror_rule_and_clamp(self) -> None:
        self.assertEqual(
            self.evidence["mirror_rule"]["rule"], "mirror_x = (level // 100) & 1"
        )
        self.assertEqual(
            self.evidence["level_counter_clamp"]["maximum_level"], 3999
        )

    def test_content_cycling_formula(self) -> None:
        cycling = self.evidence["content_cycling"]
        self.assertEqual(
            cycling["wrapped_level_formula"], "((level - 1) mod 100) + 1"
        )


if __name__ == "__main__":
    unittest.main()
