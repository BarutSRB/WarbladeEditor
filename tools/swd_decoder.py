#!/usr/bin/env python3

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import struct
import sys
from pathlib import Path
from typing import Any, Iterable


FILE_SIZE = 0x0BE0
HEADER_OFFSET = 0x0000
HEADER_WORD_COUNT = 9
HEADER_SIZE = HEADER_WORD_COUNT * 4
POINT_OFFSET = 0x0024
POINT_SLOT_COUNT = 150
POINT_WORD_COUNT = 5
POINT_SIZE = POINT_WORD_COUNT * 4
ACTIVE_COUNT_OFFSET = 0x0BDC
TOTAL_WORD_COUNT = FILE_SIZE // 4

WARBLADE_EXE_SHA256 = (
    "ddf1778c307af1087ff9dcb512786111e665d972298aeaac3f1b4b2996d079ef"
)


class SwdFormatError(ValueError):
    pass


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _require_i32(value: Any, label: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise SwdFormatError(f"{label} must be a signed 32-bit integer")
    if value < -(1 << 31) or value >= 1 << 31:
        raise SwdFormatError(f"{label} is outside the signed 32-bit range")
    return value


def _require_words(value: Any, count: int, label: str) -> list[int]:
    if not isinstance(value, list) or len(value) != count:
        raise SwdFormatError(f"{label} must contain exactly {count} words")
    return [_require_i32(word, f"{label}[{index}]") for index, word in enumerate(value)]


def _point_document(index: int, words: list[int], active: bool) -> dict[str, Any]:
    return {
        "slot_index": index,
        "active": active,
        "file_offset": POINT_OFFSET + index * POINT_SIZE,
        "words": words,
        "runtime_interpretation": {
            "acceleration_x_fixed_256": words[0],
            "acceleration_y_fixed_256": words[1],
            "opcode": words[2],
            "unresolved_word_3": words[3],
            "progress_threshold": words[4],
        },
    }


def decode_bytes(data: bytes, source_name: str = "<memory>") -> dict[str, Any]:
    if len(data) != FILE_SIZE:
        raise SwdFormatError(
            f"{source_name}: expected {FILE_SIZE} bytes, found {len(data)}"
        )

    words = list(struct.unpack(f"<{TOTAL_WORD_COUNT}i", data))
    header_words = words[:HEADER_WORD_COUNT]
    point_words = [
        words[
            HEADER_WORD_COUNT + index * POINT_WORD_COUNT :
            HEADER_WORD_COUNT + (index + 1) * POINT_WORD_COUNT
        ]
        for index in range(POINT_SLOT_COUNT)
    ]
    active_count = words[-1]
    if active_count < 0 or active_count > POINT_SLOT_COUNT:
        raise SwdFormatError(
            f"{source_name}: active point count {active_count} is outside 0..150"
        )

    point_slots = [
        _point_document(index, values, index < active_count)
        for index, values in enumerate(point_words)
    ]
    return {
        "format": "warblade_swd",
        "source_name": source_name,
        "file_size": len(data),
        "sha256": _sha256(data),
        "source_executable_sha256": WARBLADE_EXE_SHA256,
        "layout": {
            "header": {
                "file_offset": HEADER_OFFSET,
                "size": HEADER_SIZE,
                "word_count": HEADER_WORD_COUNT,
            },
            "point_slots": {
                "file_offset": POINT_OFFSET,
                "size": POINT_SLOT_COUNT * POINT_SIZE,
                "record_count": POINT_SLOT_COUNT,
                "record_size": POINT_SIZE,
                "record_word_count": POINT_WORD_COUNT,
            },
            "active_point_count": {
                "file_offset": ACTIVE_COUNT_OFFSET,
                "size": 4,
            },
        },
        "header_words": header_words,
        "header_runtime_interpretation": {
            "initial_velocity_x_fixed_256": header_words[5],
            "initial_velocity_y_fixed_256": header_words[6],
            "return_selector": header_words[8],
            "unresolved_word_indices": [0, 1, 2, 3, 4, 7],
        },
        "active_point_count": active_count,
        "active_points": point_slots[:active_count],
        "point_slots": point_slots,
        "raw_blob_base64": base64.b64encode(data).decode("ascii"),
    }


def decode_file(path: Path) -> dict[str, Any]:
    return decode_bytes(path.read_bytes(), path.name)


def encode_document(document: dict[str, Any]) -> bytes:
    if not isinstance(document, dict):
        raise SwdFormatError("document must be an object")

    header_words = _require_words(
        document.get("header_words"), HEADER_WORD_COUNT, "header_words"
    )
    active_count = _require_i32(
        document.get("active_point_count"), "active_point_count"
    )
    if active_count < 0 or active_count > POINT_SLOT_COUNT:
        raise SwdFormatError("active_point_count must be in 0..150")

    slots = document.get("point_slots")
    if not isinstance(slots, list) or len(slots) != POINT_SLOT_COUNT:
        raise SwdFormatError("point_slots must contain exactly 150 records")

    flat_points: list[int] = []
    for index, slot in enumerate(slots):
        if not isinstance(slot, dict):
            raise SwdFormatError(f"point_slots[{index}] must be an object")
        if slot.get("slot_index") != index:
            raise SwdFormatError(
                f"point_slots[{index}].slot_index must equal {index}"
            )
        flat_points.extend(
            _require_words(
                slot.get("words"),
                POINT_WORD_COUNT,
                f"point_slots[{index}].words",
            )
        )

    encoded = struct.pack(
        f"<{TOTAL_WORD_COUNT}i", *(header_words + flat_points + [active_count])
    )
    if len(encoded) != FILE_SIZE:
        raise AssertionError("internal SWD layout size mismatch")
    return encoded


def catalog_documents(paths: Iterable[Path]) -> dict[str, Any]:
    documents = [decode_file(path) for path in paths]
    hashes: dict[str, list[str]] = {}
    for document in documents:
        hashes.setdefault(document["sha256"], []).append(document["source_name"])

    return {
        "format": "warblade_swd_catalog",
        "source_executable_sha256": WARBLADE_EXE_SHA256,
        "loader_contract": {
            "filename_pattern": "att%03d.swd",
            "probe_index_inclusive_range": [1, 50],
            "file_size": FILE_SIZE,
            "runtime_stride": FILE_SIZE,
            "selection_scope": "all successfully loaded SWDs",
        },
        "file_count": len(documents),
        "duplicate_groups": [
            names for names in hashes.values() if len(names) > 1
        ],
        "files": documents,
    }


def _default_paths() -> list[Path]:
    root = Path(__file__).resolve().parents[1]
    return sorted((root / "assets" / "original" / "paths").glob("att*.swd"))


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Losslessly decode original Warblade fixed-size SWD attack paths."
    )
    parser.add_argument(
        "paths",
        nargs="*",
        type=Path,
        help="SWD files; defaults to assets/original/paths/att*.swd",
    )
    parser.add_argument(
        "--catalog",
        action="store_true",
        help="emit one catalog object instead of one object per file",
    )
    parser.add_argument(
        "--verify-roundtrip",
        action="store_true",
        help="fail if structured re-encoding differs from any input byte",
    )
    return parser.parse_args()


def main() -> int:
    args = _parse_args()
    paths = args.paths or _default_paths()
    if not paths:
        print("no SWD files found", file=sys.stderr)
        return 2

    try:
        documents = [decode_file(path) for path in paths]
        if args.verify_roundtrip:
            for path, document in zip(paths, documents):
                encoded = encode_document(document)
                original = path.read_bytes()
                if encoded != original:
                    raise SwdFormatError(f"{path}: structured round trip differs")

        output: Any
        if args.catalog:
            output = catalog_documents(paths)
        elif len(documents) == 1:
            output = documents[0]
        else:
            output = documents
        json.dump(output, sys.stdout, indent=2, sort_keys=True)
        sys.stdout.write("\n")
        return 0
    except (OSError, SwdFormatError) as error:
        print(error, file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
