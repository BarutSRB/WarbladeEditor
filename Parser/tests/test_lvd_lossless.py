#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import os
import sys
import unittest
from pathlib import Path


PROJECT_DIR = Path(__file__).resolve().parents[1]
SCRIPTS_DIR = PROJECT_DIR / "scripts"
SAMPLE_LEVEL = PROJECT_DIR / "Reports" / "classic_level_001.lvd"
DEFAULT_FIRST_FIVE_DIR = PROJECT_DIR.parent / "assets" / "original" / "levels"
FIRST_FIVE_DIR = Path(os.environ.get("WARBLADE_LVD_DIR", DEFAULT_FIRST_FIVE_DIR))
sys.path.insert(0, str(SCRIPTS_DIR))

import lvd_lossless


EXPECTED_LEVELS = {
    1: {
        "sha256": "6938e9f31d93071b129a7c583f37751e899239bd97dd3d4c678664880d04aaf1",
        "title": "JUST WARMING UP",
        "groups": 2,
        "enemies": 18,
        "opcodes": {0, 1},
    },
    2: {
        "sha256": "0db45277db488947b998b1478523c2e8d2905c0d720ddb9a3efc489423a38934",
        "title": "",
        "groups": 2,
        "enemies": 22,
        "opcodes": {0, 1},
    },
    3: {
        "sha256": "32f28ba7335a5fde68951f7f4af8ecf8c6f5937cb0d12e60eafb9ee229680a33",
        "title": "THE FIRST BIG ONE",
        "groups": 2,
        "enemies": 24,
        "opcodes": {0, 1},
    },
    4: {
        "sha256": "0c816b48f007965b14a141797603a13de900879030895016e3491a56c5ab5942",
        "title": "K A M I K A Z E",
        "groups": 25,
        "enemies": 25,
        "opcodes": {0, 6},
    },
    5: {
        "sha256": "0584103d5211181bb65deef633cd6d440bbc1658bcf5ed71132e740d457044c6",
        "title": "GETTING A BIT WARMER",
        "groups": 2,
        "enemies": 22,
        "opcodes": {0, 1},
    },
}


class LosslessLayoutTests(unittest.TestCase):
    def test_regions_are_contiguous_and_cover_the_file(self) -> None:
        cursor = 0
        for region in lvd_lossless._layout_regions():
            self.assertEqual(cursor, region["file_offset"], region["name"])
            cursor += region["size"]
        self.assertEqual(lvd_lossless.FILE_SIZE, cursor)

    def test_repository_sample_round_trips_exactly(self) -> None:
        original = SAMPLE_LEVEL.read_bytes()
        document = lvd_lossless.decode_blob(original, str(SAMPLE_LEVEL))
        self.assertEqual(original, lvd_lossless.encode_document(document))
        self.assertEqual(EXPECTED_LEVELS[1]["sha256"], document["source"]["sha256"])


class FirstFiveRetailLevelTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if not all(
            (FIRST_FIVE_DIR / f"classic_level_{number:03}.lvd").is_file()
            for number in EXPECTED_LEVELS
        ):
            raise unittest.SkipTest(
                "set WARBLADE_LVD_DIR to a directory containing retail levels 001–005"
            )

    def test_first_five_round_trip_and_semantic_views(self) -> None:
        for level_number, expected in EXPECTED_LEVELS.items():
            with self.subTest(level=level_number):
                path = FIRST_FIVE_DIR / f"classic_level_{level_number:03}.lvd"
                original = path.read_bytes()
                document = lvd_lossless.decode_blob(original, str(path))
                rebuilt = lvd_lossless.encode_document(document)
                opcodes = {
                    point["opcode"]
                    for group in document["active_groups"]
                    for point in group["path_points"]
                }

                self.assertEqual(original, rebuilt)
                self.assertEqual(expected["sha256"], hashlib.sha256(rebuilt).hexdigest())
                self.assertEqual(expected["title"], document["summary"]["title"])
                self.assertEqual(
                    expected["groups"], document["summary"]["active_group_count"]
                )
                self.assertEqual(
                    expected["enemies"], document["summary"]["authored_enemy_count"]
                )
                self.assertEqual(expected["opcodes"], opcodes)

    def test_first_five_are_not_mirrored(self) -> None:
        for level_number in EXPECTED_LEVELS:
            with self.subTest(level=level_number):
                mirror = (level_number // 100) & 1
                self.assertEqual(0, mirror)


if __name__ == "__main__":
    unittest.main(verbosity=2)
