#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import unittest
from pathlib import Path

from swd_decoder import (
    ACTIVE_COUNT_OFFSET,
    FILE_SIZE,
    HEADER_SIZE,
    POINT_OFFSET,
    POINT_SIZE,
    POINT_SLOT_COUNT,
    SwdFormatError,
    catalog_documents,
    decode_bytes,
    decode_file,
    encode_document,
)


ROOT = Path(__file__).resolve().parents[1]
PATH_ROOT = ROOT / "assets" / "original" / "paths"

EXPECTED = {
    "att001.swd": (
        "880ba7f0355ef98e6abde803c135e6c9c60733f84c26844d3b6511c7172c6a1e",
        (3, 117, 0, 0, 1, 0, 51, 0, 2),
        7,
    ),
    "att002.swd": (
        "880ba7f0355ef98e6abde803c135e6c9c60733f84c26844d3b6511c7172c6a1e",
        (3, 117, 0, 0, 1, 0, 51, 0, 2),
        7,
    ),
    "att003.swd": (
        "87c6ac6394ab3eee0db69e846c1e7f486a8ccf5ae1f9c5f84857920ac6b1c88f",
        (-15, 142, 0, 0, 1, 0, -13, 0, 3),
        6,
    ),
    "att004.swd": (
        "8a8cf01e0921fcf8b99c12d7caa976bf981fb2ca1a00354dcffc310ed1ca3a28",
        (15, 142, 0, 0, 1, 0, -13, 0, 3),
        6,
    ),
    "att005.swd": (
        "1a0d0819640363599b78f6fd5cc60ef6bcb78f7eaf9aec4c1fa6d9821460b337",
        (-82, 130, 0, 0, 1, 0, 0, 0, 1),
        13,
    ),
    "att006.swd": (
        "1af149cc2532eb09f3699791929daa2e92dfe42fa3968bcc61998e64aae8d91b",
        (-101, 130, 0, 1, 1, 0, -128, 0, 3),
        3,
    ),
    "att007.swd": (
        "8cc5867bc2cbb6173de5010e38c3ac80bc1667764aa9497775c3c7a8c92b16d1",
        (-63, 142, 0, 0, 1, 0, -448, 0, 3),
        14,
    ),
    "att008.swd": (
        "e4376aa1dc223920b08ee2bb5a4742924a98b95ff40e4c4335bf6e9df01fb74f",
        (-90, 76, 0, 0, 1, 282, -448, 0, 1),
        14,
    ),
    "att009.swd": (
        "10c154e6aa421c8497f5727fe27bf8ce8fb36995d3a5b410bab6f8bd03554297",
        (-93, 92, 0, 0, 1, 0, -26, 0, 2),
        18,
    ),
    "att010.swd": (
        "a27b2eeb66aee767763008d0a4da5bfabfc27839950d94650be8b2e58153f080",
        (-93, 92, 0, 0, 1, 0, -26, 0, 2),
        18,
    ),
    "att011.swd": (
        "4541b93d6edb78efe6bf0b7f4be407d13d548f5e72afe3c109f8fb45609c1474",
        (-87, 113, 0, 0, 1, 0, 448, 0, 1),
        12,
    ),
    "att012.swd": (
        "09296fc4ec72d4fed947b3f20e819f69161ac9abffcfa0fa2fef43b9c557e7aa",
        (87, 113, 0, 0, 1, 0, 448, 0, 1),
        12,
    ),
    "att013.swd": (
        "1c9731609891f3dbe392e9d62744311fbab5deb447c495552d83bde0f23e77ca",
        (93, 92, 0, 0, 1, 0, -26, 0, 2),
        18,
    ),
    "att014.swd": (
        "360745783324ca20ddc36b69b0cbe4baf7429df023907f93009865e1fd801d61",
        (93, 92, 0, 0, 1, 0, -26, 0, 2),
        18,
    ),
}


class SwdRoundTripTests(unittest.TestCase):
    def paths(self) -> list[Path]:
        return sorted(PATH_ROOT.glob("att*.swd"))

    def test_layout_closes_exact_file_size(self) -> None:
        self.assertEqual(HEADER_SIZE, POINT_OFFSET)
        self.assertEqual(
            POINT_OFFSET + POINT_SLOT_COUNT * POINT_SIZE, ACTIVE_COUNT_OFFSET
        )
        self.assertEqual(ACTIVE_COUNT_OFFSET + 4, FILE_SIZE)

    def test_retail_set_hashes_headers_counts_and_round_trips(self) -> None:
        paths = self.paths()
        self.assertEqual([path.name for path in paths], list(EXPECTED))
        for path in paths:
            expected_hash, expected_header, expected_count = EXPECTED[path.name]
            original = path.read_bytes()
            document = decode_file(path)
            self.assertEqual(len(original), FILE_SIZE, path.name)
            self.assertEqual(hashlib.sha256(original).hexdigest(), expected_hash)
            self.assertEqual(document["sha256"], expected_hash)
            self.assertEqual(tuple(document["header_words"]), expected_header)
            self.assertEqual(document["active_point_count"], expected_count)
            self.assertEqual(encode_document(document), original)

    def test_every_retail_active_point_has_zero_opcode_and_word_3(self) -> None:
        for path in self.paths():
            document = decode_file(path)
            for point in document["active_points"]:
                self.assertEqual(point["words"][2:4], [0, 0], (path.name, point))

    def test_inactive_slots_are_preserved_not_normalized(self) -> None:
        document = decode_file(PATH_ROOT / "att011.swd")
        self.assertEqual(document["active_point_count"], 12)
        self.assertEqual(document["point_slots"][12]["words"], [0, 0, 0, 0, 22])
        self.assertEqual(
            document["point_slots"][13]["words"], [115, 154, 0, 0, 11]
        )
        self.assertEqual(
            encode_document(document), (PATH_ROOT / "att011.swd").read_bytes()
        )

    def test_only_retail_duplicate_is_att001_att002(self) -> None:
        catalog = catalog_documents(self.paths())
        self.assertEqual(catalog["file_count"], 14)
        self.assertEqual(catalog["duplicate_groups"], [["att001.swd", "att002.swd"]])

    def test_invalid_size_and_count_are_rejected(self) -> None:
        with self.assertRaises(SwdFormatError):
            decode_bytes(b"\0" * (FILE_SIZE - 1))

        document = decode_file(PATH_ROOT / "att001.swd")
        document["active_point_count"] = 151
        with self.assertRaises(SwdFormatError):
            encode_document(document)


if __name__ == "__main__":
    unittest.main()
