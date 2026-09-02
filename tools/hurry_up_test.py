#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import json
import math
import unittest
from pathlib import Path

from hurry_up_extract import (
    F32_CONSTANTS,
    F64_CONSTANTS,
    I32_CONSTANTS,
    INSTRUCTION_PINS,
    PEImage,
    WARBLADE_EXE_SHA256,
    build_evidence,
)


ROOT = Path(__file__).resolve().parents[1]
EXE = ROOT / "Game" / "warblade.exe"
GENERATED = ROOT / "docs" / "evidence" / "hurry_up.json"
MARKDOWN = ROOT / "docs" / "evidence" / "HURRY_UP_SECRET_SHIPS.md"


class HurryUpExtractionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.image = PEImage(EXE)
        cls.evidence = build_evidence(EXE.resolve())

    def test_retail_identity_and_schema(self) -> None:
        self.assertEqual(self.image.sha256, WARBLADE_EXE_SHA256)
        self.assertEqual(self.evidence["schema"], "warblade-hurry-up-v1")

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

    def test_every_constant_matches_its_documented_value(self) -> None:
        constants = self.evidence["constants"]
        self.assertEqual(
            len(constants),
            len(F32_CONSTANTS) + len(F64_CONSTANTS) + len(I32_CONSTANTS),
        )
        for name, entry in constants.items():
            self.assertTrue(
                entry["matches_documented_value"],
                f"constant drifted at {name} ({entry['va']})",
            )

    def test_deadline_interval_matches_difficulty_content(self) -> None:
        deadline = self.evidence["deadline"]
        self.assertEqual(deadline["interval_source_global_va"], "0x008f2090")
        self.assertEqual(deadline["post_spawn_interval_ms"], 10000)
        difficulties = json.loads(
            (ROOT / "content" / "difficulties.json").read_text(encoding="utf-8")
        )["difficulties"]
        by_id = {entry["id"]: entry for entry in difficulties}
        for difficulty_id, interval_ms in deadline["interval_by_difficulty_ms"].items():
            self.assertEqual(
                by_id[difficulty_id]["timed_effect_seconds"] * 1000,
                interval_ms,
                f"{difficulty_id} timed-effect interval disagrees with the executable",
            )

    def test_difficulty_content_carries_the_special_ship_fields(self) -> None:
        difficulties = json.loads(
            (ROOT / "content" / "difficulties.json").read_text(encoding="utf-8")
        )["difficulties"]
        by_id = {entry["id"]: entry for entry in difficulties}
        mothership = self.evidence["mothership"]
        rare_ship = self.evidence["rare_ship"]
        for difficulty_id, value in mothership["health_base_by_difficulty"].items():
            self.assertEqual(by_id[difficulty_id]["special_health_base_a"], value)
        for difficulty_id, value in rare_ship["health_base_by_difficulty"].items():
            self.assertEqual(by_id[difficulty_id]["special_health_base_c"], value)
        for difficulty_id, value in mothership["speed_maximum_by_difficulty"].items():
            self.assertEqual(by_id[difficulty_id]["special_speed_maximum"], value)

    def test_mothership_sheet_geometry_is_consistent(self) -> None:
        mothership = self.evidence["mothership"]
        sheet_width, sheet_height = mothership["sheet_size"]
        frame_width, frame_height = mothership["frame_size"]
        self.assertEqual(mothership["behavior_state"], 9)
        self.assertEqual(mothership["kill_score"], 2500)
        self.assertEqual(mothership["sheet_width"], sheet_width)
        columns = sheet_width // frame_width
        rows = sheet_height // frame_height
        self.assertGreaterEqual(columns * 8, mothership["frame_count"])
        self.assertGreaterEqual(rows, 8)
        self.assertEqual(
            self.evidence["constants"]["mothership_frame_count"]["value"],
            float(mothership["frame_count"]),
        )
        self.assertEqual(
            self.evidence["constants"]["mothership_frame_last"]["value"],
            float(mothership["frame_count"] - 1),
        )
        self.assertEqual(
            self.evidence["constants"]["mothership_hitbox_width"]["value"],
            float(frame_width),
        )
        self.assertEqual(
            self.evidence["constants"]["mothership_hitbox_height"]["value"],
            float(frame_height),
        )

    def test_rare_ship_sheet_geometry_is_consistent(self) -> None:
        rare_ship = self.evidence["rare_ship"]
        sheet_width, sheet_height = rare_ship["sheet_size"]
        frame_width, frame_height = rare_ship["frame_size"]
        self.assertEqual(rare_ship["behavior_state"], 12)
        self.assertEqual(rare_ship["kill_score"], 25000)
        self.assertEqual(sheet_width, frame_width)
        self.assertEqual(sheet_height // frame_height, rare_ship["frame_count"])
        # The traced 100x100 box sits centred inside the 128x128 frame.
        offset_x, offset_y = rare_ship["hitbox"]["offset"]
        self.assertEqual(offset_x * 2 + rare_ship["hitbox"]["width"], frame_width)
        self.assertEqual(offset_y * 2 + rare_ship["hitbox"]["height"], frame_height)

    def test_hit_mask_files_match_their_declared_layout(self) -> None:
        for ship, relative in (
            ("mothership", "assets/original/evidence/enemies/mothership.hma"),
            ("rare_ship", "assets/original/textures/enemies/moneyship.hma"),
        ):
            mask = self.evidence[ship]["hit_mask"]
            path = ROOT / relative
            raw = path.read_bytes()
            self.assertEqual(len(raw), mask["bytes"], relative)
            self.assertEqual(
                hashlib.sha256(raw).hexdigest(), mask["sha256"], relative
            )
            width, height = mask["atlas_size"]
            self.assertEqual(width * height, mask["bytes"], relative)
            frame_width, frame_height = self.evidence[ship]["frame_size"]
            self.assertEqual(width, frame_width, relative)
            self.assertEqual(
                height, frame_height * self.evidence[ship]["frame_count"], relative
            )
            self.assertEqual(set(raw) - {0, 1}, set(), f"{relative} is not a 0/1 mask")

    def test_rare_ship_cadence_is_every_eighth_spawn(self) -> None:
        cadence = self.evidence["rare_ship"]["cadence"]
        self.assertEqual(cadence["period"], 8)
        self.assertEqual(cadence["counter_global_va"], "0x00848864")

    def test_heading_tables_are_the_shared_forty_entry_circle(self) -> None:
        rare_ship = self.evidence["rare_ship"]
        heading_x = rare_ship["heading_table_x"]
        heading_y = rare_ship["heading_table_y"]
        self.assertEqual(len(heading_x), 40)
        self.assertEqual(len(heading_y), 40)
        for index in range(40):
            angle = index * math.tau / 40.0
            self.assertAlmostEqual(heading_x[index], math.sin(angle), delta=1e-6)
            self.assertAlmostEqual(heading_y[index], -math.cos(angle), delta=1e-6)

    def test_secret_ids_are_three_and_six(self) -> None:
        secrets = self.evidence["secret_recording"]
        self.assertEqual(secrets["ids"]["mothership"], 3)
        self.assertEqual(secrets["ids"]["rare_ship"], 6)
        self.assertEqual(self.evidence["mothership"]["death"]["secret_id"], 3)
        self.assertEqual(self.evidence["rare_ship"]["death"]["secret_id"], 6)

    def test_time_trial_excludes_the_hurry_up_family(self) -> None:
        guards = [guard["rule"] for guard in self.evidence["spawner"]["guards"]]
        self.assertIn("match mode 6 (Time Trial) aborts", guards)
        time_trial = json.loads(
            (ROOT / "content" / "time_trial.json").read_text(encoding="utf-8")
        )
        self.assertIs(
            time_trial["runtime"]["rules"]["hurry_up_special_ships"],
            False,
        )

    def test_other_secret_ships_stay_evidence_only(self) -> None:
        others = self.evidence["other_secret_ships"]
        self.assertEqual(others["confidence"], "evidence_only")
        self.assertEqual(others["money_sucker"]["behavior_state"], 11)
        self.assertEqual(others["guard_ship"]["behavior_state"], 18)

    def test_markdown_records_the_same_identity(self) -> None:
        markdown = MARKDOWN.read_text(encoding="utf-8")
        self.assertIn(WARBLADE_EXE_SHA256, markdown)
        self.assertIn("FUN_0058e350", markdown)
        self.assertIn("FUN_00552440", markdown)


if __name__ == "__main__":
    unittest.main()
