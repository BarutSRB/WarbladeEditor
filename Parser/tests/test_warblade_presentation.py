#!/usr/bin/env python3

from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path


PROJECT_DIR = Path(__file__).resolve().parents[1]
SCRIPTS_DIR = PROJECT_DIR / "scripts"
GAME_ROOT = PROJECT_DIR.parent / "Game"
sys.path.insert(0, str(SCRIPTS_DIR))

import warblade_presentation


class PresentationInventoryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if not (GAME_ROOT / "data" / "warblade.pac").is_file():
            raise unittest.SkipTest(f"retail game data is unavailable: {GAME_ROOT}")
        cls.inventory = warblade_presentation.build_inventory(GAME_ROOT)

    def test_retail_source_counts_and_pinned_archive_hash(self) -> None:
        self.assertEqual(
            {
                "rasters": 407,
                "hit_masks": 127,
                "music": 13,
                "sfx": 112,
                "voices": 139,
            },
            self.inventory["counts"],
        )
        self.assertEqual(
            ["mp3", "ogg"], self.inventory["audio_formats"]["inventoried"]
        )
        self.assertIn(
            "permanent product non-goal",
            self.inventory["audio_formats"]["excluded_music_modules"],
        )
        self.assertEqual(
            warblade_presentation.EXPECTED_PAC_SHA256,
            self.inventory["source"]["pac"]["sha256"],
        )

    def test_core_texture_dimensions_formats_and_hashes_are_exact(self) -> None:
        expected = {
            "alien001.tga": (
                "tga",
                576,
                96,
                "6bd559f5fb7d03736131673fcf77a7f5925c993afb7fbfd1eeca5e2db30f760e",
            ),
            "stars1.jpg": (
                "jpg",
                1024,
                1024,
                "6cfa144b70f11bde8278fbdcf28d145f5c83983bc4af57a40c6897c5189ac33a",
            ),
            "newscreen.png": (
                "png",
                800,
                600,
                "3eaf032da056172d049ac2b44770c03b228d6b69bb6d6e803fce66743ba8cefb",
            ),
        }
        for filename, (image_format, width, height, digest) in expected.items():
            with self.subTest(filename=filename):
                record = self.inventory["rasters"][filename]
                self.assertEqual(image_format, record["format"])
                self.assertEqual(width, record["width"])
                self.assertEqual(height, record["height"])
                self.assertEqual(digest, record["sha256"])
                self.assertEqual(
                    f"warblade.pac:{filename}", record["source_id"]
                )

    def test_tga_and_hma_orientation_contracts_are_validated(self) -> None:
        alien = self.inventory["rasters"]["alien001.tga"]
        mask = self.inventory["hit_masks"]["alien001.hma"]
        self.assertEqual("bottom_left", alien["storage_origin"])
        self.assertEqual(32, alien["pixel_depth"])
        self.assertEqual("top_left_row_major", mask["orientation"])
        self.assertEqual("alien001.tga", mask["paired_raster"])
        self.assertEqual((alien["width"], alien["height"]), (mask["width"], mask["height"]))
        self.assertEqual(alien["width"] * alien["height"], mask["byte_size"])
        self.assertEqual(
            "0b04983374edaddf153dabfe571093b1106d4fb735ea3de0a2cb9db44258fa49",
            mask["sha256"],
        )
        unmatched = self.inventory["hit_masks"]["mothership.hma"]
        self.assertIsNone(unmatched["paired_raster"])
        self.assertIsNone(unmatched["width"])
        self.assertIsNone(unmatched["height"])

    def test_external_audio_paths_and_hashes_are_namespaced(self) -> None:
        title = self.inventory["music"]["title.mp3"]
        single_shot = self.inventory["sfx"]["singleshot.mp3"]
        warp_malfunction = self.inventory["voices"]["1/warpmalfunction.mp3"]
        self.assertEqual("data/music/title.mp3", title["source_path"])
        self.assertEqual("external:data/music/title.mp3", title["source_id"])
        self.assertEqual(
            "5512b2c91fb0484d4f10865a90eeadbc97d430537ea3ab85c75771ef3c253d48",
            title["sha256"],
        )
        self.assertEqual("data/samples/singleshot.mp3", single_shot["source_path"])
        self.assertEqual("external:data/samples/singleshot.mp3", single_shot["source_id"])
        self.assertEqual(
            "c55ad4a9ee88dae270b9ed9bcf1a48baba84ea9a30e7dbaf52c1c1d4192d345d",
            single_shot["sha256"],
        )
        self.assertEqual(
            "data/samples/voices/1/warpmalfunction.mp3",
            warp_malfunction["source_path"],
        )
        self.assertEqual(
            "86a0559085e01c7b4cd818246676ee6b5efc5c3d6f7070a7ed654bb2b342deee",
            warp_malfunction["sha256"],
        )
        loser = self.inventory["voices"]["2/loser.ogg"]
        self.assertEqual("ogg", loser["format"])
        self.assertEqual("data/samples/voices/2/loser.ogg", loser["source_path"])
        self.assertEqual("external:data/samples/voices/2/loser.ogg", loser["source_id"])
        self.assertEqual(
            "9577704c4c0f5ab81af9e968053a9734967b95f1ca2b9447fbeb733a41d93d0a",
            loser["sha256"],
        )

    def test_source_hash_validation_rejects_missing_and_changed_sources(self) -> None:
        warblade_presentation.validate_source_hashes(
            self.inventory,
            {
                "warblade.pac:alien001.tga": self.inventory["rasters"]["alien001.tga"][
                    "sha256"
                ],
                "external:data/music/title.mp3": self.inventory["music"]["title.mp3"][
                    "sha256"
                ],
            },
        )
        with self.assertRaisesRegex(ValueError, "not inventoried"):
            warblade_presentation.validate_source_hashes(
                self.inventory, {"warblade.pac:missing.tga": "0" * 64}
            )
        with self.assertRaisesRegex(ValueError, "SHA-256 mismatch"):
            warblade_presentation.validate_source_hashes(
                self.inventory, {"warblade.pac:alien001.tga": "0" * 64}
            )

    def test_hma_validation_rejects_invalid_values_and_dimensions(self) -> None:
        with self.assertRaisesRegex(ValueError, "expected only 0 or 1"):
            warblade_presentation.validate_hma(b"\x00\x02", "invalid.hma")
        with self.assertRaisesRegex(ValueError, "size mismatch"):
            warblade_presentation.validate_hma(b"\x00\x01", "short.hma", 2, 2)

    def test_inventory_serialization_is_deterministic(self) -> None:
        first = json.dumps(self.inventory, indent=2, sort_keys=True) + "\n"
        second_inventory = warblade_presentation.build_inventory(GAME_ROOT)
        second = json.dumps(second_inventory, indent=2, sort_keys=True) + "\n"
        self.assertEqual(first, second)


if __name__ == "__main__":
    unittest.main(verbosity=2)
