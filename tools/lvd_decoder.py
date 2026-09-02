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


FILE_SIZE = 0x1CB98
GLOBAL_HEADER_OFFSET = 0x0000
GLOBAL_HEADER_WORD_COUNT = 27
GLOBAL_HEADER_SIZE = GLOBAL_HEADER_WORD_COUNT * 4

GROUP_OFFSET = 0x006C
GROUP_SLOT_COUNT = 25
GROUP_SIZE = 0x0664
GROUP_HEADER_WORD_COUNT = 9
GROUP_HEADER_SIZE = GROUP_HEADER_WORD_COUNT * 4
ENEMY_SLOT_COUNT = 50
ENEMY_RECORD_WORD_COUNT = 8
ENEMY_RECORD_SIZE = ENEMY_RECORD_WORD_COUNT * 4

PATH_COUNT_OFFSET = 0xA030
TITLE_OFFSET = 0xA094
TITLE_SIZE = 0x24
AUTHOR_OFFSET = 0xA0B8
AUTHOR_SIZE = 0x34

PATH_OFFSET = 0xA0EC
PATH_GROUP_SIZE = 0x0BB8
PATH_POINT_SLOT_COUNT = 150
PATH_POINT_WORD_COUNT = 5
PATH_POINT_SIZE = PATH_POINT_WORD_COUNT * 4

RESOURCE_OFFSET = 0x1C5E4
RESOURCE_SLOT_COUNT = 12
RESOURCE_SLOT_SIZE = 0x33

FIXED_TABLE_OFFSET = 0x1C848
FIXED_TABLE_RECORD_COUNT = 50
FIXED_TABLE_RECORD_WORD_COUNT = 4
FIXED_TABLE_RECORD_SIZE = FIXED_TABLE_RECORD_WORD_COUNT * 4

TAIL_A_OFFSET = 0x1CB68
TAIL_B_OFFSET = 0x1CB80
TAIL_WORD_COUNT = 6

WARBLADE_EXE_SHA256 = "ddf1778c307af1087ff9dcb512786111e665d972298aeaac3f1b4b2996d079ef"


class LvdFormatError(ValueError):
    pass


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _hex_offset(value: int) -> str:
    return f"0x{value:05x}"


def _read_words(data: bytes, offset: int, count: int) -> list[int]:
    end = offset + count * 4
    if offset < 0 or end > len(data):
        raise LvdFormatError(
            f"word read {_hex_offset(offset)}..{_hex_offset(end)} exceeds "
            f"{len(data)}-byte input"
        )
    return list(struct.unpack_from(f"<{count}i", data, offset))


def _pascal_slot(data: bytes, offset: int, size: int) -> dict[str, Any]:
    raw = data[offset : offset + size]
    if len(raw) != size:
        raise LvdFormatError(f"short Pascal-string slot at {_hex_offset(offset)}")
    length = raw[0]
    valid_length = length <= size - 1
    payload_end = 1 + min(length, size - 1)
    payload = raw[1:payload_end]
    return {
        "file_offset": offset,
        "length": length,
        "length_is_valid": valid_length,
        "text_cp1252": payload.decode("cp1252", errors="replace"),
        "payload_hex": payload.hex(),
        "padding_hex": raw[payload_end:].hex(),
        "raw_hex": raw.hex(),
    }


def _layout_regions() -> list[dict[str, Any]]:
    return [
        {
            "name": "global_header",
            "file_offset": GLOBAL_HEADER_OFFSET,
            "size": GLOBAL_HEADER_SIZE,
            "word_count": GLOBAL_HEADER_WORD_COUNT,
        },
        {
            "name": "group_slots",
            "file_offset": GROUP_OFFSET,
            "size": GROUP_SLOT_COUNT * GROUP_SIZE,
            "record_count": GROUP_SLOT_COUNT,
            "record_size": GROUP_SIZE,
        },
        {
            "name": "path_point_counts",
            "file_offset": PATH_COUNT_OFFSET,
            "size": GROUP_SLOT_COUNT * 4,
            "word_count": GROUP_SLOT_COUNT,
        },
        {
            "name": "title_pascal_slot",
            "file_offset": TITLE_OFFSET,
            "size": TITLE_SIZE,
        },
        {
            "name": "author_pascal_slot",
            "file_offset": AUTHOR_OFFSET,
            "size": AUTHOR_SIZE,
        },
        {
            "name": "path_point_slabs",
            "file_offset": PATH_OFFSET,
            "size": GROUP_SLOT_COUNT * PATH_GROUP_SIZE,
            "record_count": GROUP_SLOT_COUNT,
            "record_size": PATH_GROUP_SIZE,
        },
        {
            "name": "resource_pascal_slots",
            "file_offset": RESOURCE_OFFSET,
            "size": RESOURCE_SLOT_COUNT * RESOURCE_SLOT_SIZE,
            "record_count": RESOURCE_SLOT_COUNT,
            "record_size": RESOURCE_SLOT_SIZE,
        },
        {
            "name": "fixed_table_raw",
            "file_offset": FIXED_TABLE_OFFSET,
            "size": FIXED_TABLE_RECORD_COUNT * FIXED_TABLE_RECORD_SIZE,
            "record_count": FIXED_TABLE_RECORD_COUNT,
            "record_size": FIXED_TABLE_RECORD_SIZE,
        },
        {
            "name": "tail_array_a_raw",
            "file_offset": TAIL_A_OFFSET,
            "size": TAIL_WORD_COUNT * 4,
            "word_count": TAIL_WORD_COUNT,
        },
        {
            "name": "tail_array_b_raw",
            "file_offset": TAIL_B_OFFSET,
            "size": TAIL_WORD_COUNT * 4,
            "word_count": TAIL_WORD_COUNT,
        },
    ]


def _field_contract() -> dict[str, Any]:
    return {
        "confidence_scale": {
            "proven": "Confirmed by the executable loader and a traced consumer.",
            "supported": "The structure/use is confirmed, but the exact gameplay term or unit is not.",
            "evidence_only": "No supported-runtime semantic consumer is proved; the raw value is retained losslessly.",
        },
        "fields": {
            "level_mode_id": {
                "confidence": "proven",
                "source": "global header +0x00; numeric level-state selector",
                "evidence_va": ["0x00559048", "0x0056d39e", "0x00608c8e"],
                "caveat": "Numeric IDs are retained; only modes exercised by traced branches are described.",
            },
            "active_group_count": {
                "confidence": "proven",
                "source": "global header +0x04",
                "evidence_va": ["0x0055905b", "0x00559149", "0x0056b83a"],
            },
            "supplemental_spawn_records": {
                "confidence": "supported",
                "source": "global header +0x08; five records of five signed words",
                "evidence_va": ["0x00559080", "0x0055912f", "0x0056d468"],
                "caveat": "The normalized v9 runtime promotes only executable-backed consumers; all other exact words remain address-qualified evidence-only data.",
            },
            "entry_origin_x": {
                "confidence": "proven",
                "source": "group header +0x00",
                "evidence_va": ["0x0056ccec", "0x0056cd90"],
                "transform": "logical_width / 2 ± value - 16; mirror selects subtraction",
            },
            "entry_origin_y": {
                "confidence": "proven",
                "source": "group header +0x04",
                "evidence_va": ["0x0056cd97", "0x0056cdc1"],
                "transform": "value - 16",
            },
            "first_activation_delay_ticks": {
                "confidence": "proven",
                "source": "group header +0x08",
                "evidence_va": ["0x0056bc04", "0x0056d380", "0x00607f1a"],
            },
            "activation_stagger_ticks": {
                "confidence": "proven",
                "source": "group header +0x0c; added after each enemy except in level mode 2",
                "evidence_va": ["0x0056d39e", "0x0056d3b9"],
            },
            "active_enemy_count": {
                "confidence": "proven",
                "source": "group header +0x10",
                "evidence_va": ["0x0055930b", "0x0056bc34"],
            },
            "initial_velocity_x_milli": {
                "confidence": "proven",
                "source": "group header +0x14, divided by 1000.0 while loading",
                "evidence_va": ["0x00559221", "0x0055923c", "0x0056ce04"],
            },
            "initial_velocity_y_milli": {
                "confidence": "proven",
                "source": "group header +0x18, divided by 1000.0 while loading",
                "evidence_va": ["0x00559266", "0x00559281", "0x0056ce36"],
            },
            "kill_cohort_id": {
                "confidence": "proven",
                "source": "group header +0x1c",
                "evidence_va": ["0x0056cfef", "0x00588f64", "0x00588fde"],
            },
            "group_mode_id": {
                "confidence": "proven",
                "source": "group header +0x20; numeric behavior selector only",
                "evidence_va": ["0x005592ea", "0x00605fe0", "0x00569260"],
            },
            "formation_target_x": {
                "confidence": "proven",
                "source": "enemy record +0x00",
                "evidence_va": ["0x0056cc15", "0x0056cca8"],
                "transform": "logical_width / 2 ± value; mirror selects subtraction",
            },
            "formation_target_y": {
                "confidence": "proven",
                "source": "enemy record +0x04",
                "evidence_va": ["0x0056ccaf", "0x0056ccda"],
            },
            "resource_slot_id": {
                "confidence": "proven",
                "source": "enemy record +0x08; selects one of six traced resource cases",
                "evidence_va": ["0x0056bccb"],
            },
            "base_health": {
                "confidence": "proven",
                "source": "enemy record +0x0c; difficulty contribution is added at spawn",
                "evidence_va": ["0x0056d094", "0x0056d114", "0x00585e55", "0x0058603b"],
            },
            "behavior_timer_pairs": {
                "confidence": "supported",
                "source": "enemy record +0x10..+0x1c",
                "evidence_va": ["0x0058b9a4", "0x0058ba73"],
                "caveat": "Countdown/update behavior is proven; a fire-specific role is not.",
            },
            "active_path_point_count": {
                "confidence": "proven",
                "source": "path-count array indexed by active group",
                "evidence_va": ["0x00559531", "0x0055954d"],
            },
            "path_acceleration_components_milli": {
                "confidence": "proven",
                "source": "path point +0x00/+0x04, divided by 1000.0 while loading",
                "evidence_va": ["0x0055968c", "0x0055971b", "0x0060867d", "0x006087a2", "0x00613afc"],
            },
            "path_opcode": {
                "confidence": "proven",
                "source": "path point +0x08; numeric command selector only",
                "evidence_va": ["0x00559765", "0x00605fe0"],
            },
            "path_unknown_0c": {
                "confidence": "evidence_only",
                "source": "path point +0x0c",
                "evidence_va": [],
            },
            "path_duration_threshold_ticks": {
                "confidence": "proven",
                "source": "path point +0x10; advance occurs when integer progress is strictly greater",
                "evidence_va": ["0x005597f1", "0x00613b85", "0x00613c2d"],
            },
        },
    }


def _runtime_contract() -> dict[str, Any]:
    return {
        "logical_width": 800,
        "logical_width_source_va": "0x007d32f8",
        "sprite_half_extent": 16,
        "mirror_flag_va": "0x00e10f3b",
        "mirror_rule": "(current_level_number // 100) & 1",
        "mirror_rule_evidence_va": ["0x0056a6f6", "0x0056a712"],
        "fixed_tick_scale_va": "0x00e11274",
        "normal_fixed_tick_scale": 1,
        "special_fast_tick_scale": 3,
        "nominal_updates_per_second": 60,
        "nominal_update_evidence_va": "0x005a0830",
        "rendering_guidance": (
            "Keep the original fixed-tick simulation authoritative and interpolate "
            "rendering for high refresh rates."
        ),
        "path_integrator": [
            "position += velocity * tick_scale",
            "velocity += acceleration * tick_scale",
            "progress += tick_scale",
            "advance when int(progress) > duration_threshold_ticks",
        ],
        "path_opcode_observations": {
            "0": "normal acceleration segment; no extra traced side effect",
            "1": (
                "non-100 threshold stops velocity/acceleration; threshold 100 is a "
                "terminal scripted-entry marker"
            ),
            "2": "spawns secondary objects from groups whose group_mode_id is 6",
            "3": "sets executable global 0x00e11a38",
            "6": (
                "level mode 2 enters state 10 kamikaze/randomized motion; other "
                "traced modes deactivate the entity"
            ),
            "7": (
                "sets an entity flag, reverses positive velocity components, and "
                "clears acceleration/progress"
            ),
        },
        "unproven": [
            "logical playfield height",
            "player movement bounds",
            "human-readable names for every numeric group mode",
        ],
    }


def _validate_layout() -> None:
    checks = [
        (GROUP_OFFSET, GLOBAL_HEADER_SIZE, "global header end"),
        (
            PATH_COUNT_OFFSET,
            GROUP_OFFSET + GROUP_SLOT_COUNT * GROUP_SIZE,
            "group region end",
        ),
        (TITLE_OFFSET, PATH_COUNT_OFFSET + GROUP_SLOT_COUNT * 4, "path-count end"),
        (AUTHOR_OFFSET, TITLE_OFFSET + TITLE_SIZE, "title end"),
        (PATH_OFFSET, AUTHOR_OFFSET + AUTHOR_SIZE, "author end"),
        (
            RESOURCE_OFFSET,
            PATH_OFFSET + GROUP_SLOT_COUNT * PATH_GROUP_SIZE,
            "path region end",
        ),
        (
            FIXED_TABLE_OFFSET,
            RESOURCE_OFFSET + RESOURCE_SLOT_COUNT * RESOURCE_SLOT_SIZE,
            "resource region end",
        ),
        (
            TAIL_A_OFFSET,
            FIXED_TABLE_OFFSET
            + FIXED_TABLE_RECORD_COUNT * FIXED_TABLE_RECORD_SIZE,
            "fixed-table end",
        ),
        (TAIL_B_OFFSET, TAIL_A_OFFSET + TAIL_WORD_COUNT * 4, "tail A end"),
        (FILE_SIZE, TAIL_B_OFFSET + TAIL_WORD_COUNT * 4, "tail B end"),
        (
            GROUP_SIZE,
            GROUP_HEADER_SIZE + ENEMY_SLOT_COUNT * ENEMY_RECORD_SIZE,
            "group record size",
        ),
        (
            PATH_GROUP_SIZE,
            PATH_POINT_SLOT_COUNT * PATH_POINT_SIZE,
            "path slab size",
        ),
    ]
    for actual, expected, label in checks:
        if actual != expected:
            raise AssertionError(
                f"internal LVD layout error for {label}: "
                f"{_hex_offset(actual)} != {_hex_offset(expected)}"
            )


def decode_blob(data: bytes, source_name: str = "<memory>") -> dict[str, Any]:
    _validate_layout()
    if len(data) != FILE_SIZE:
        raise LvdFormatError(
            f"{source_name}: expected {FILE_SIZE} bytes (0x{FILE_SIZE:x}), "
            f"got {len(data)}"
        )

    header_words = _read_words(data, GLOBAL_HEADER_OFFSET, GLOBAL_HEADER_WORD_COUNT)
    active_group_count = header_words[1]
    if not 0 <= active_group_count <= GROUP_SLOT_COUNT:
        raise LvdFormatError(
            f"{source_name}: active group count {active_group_count} is outside "
            f"0..{GROUP_SLOT_COUNT}"
        )

    path_counts = _read_words(data, PATH_COUNT_OFFSET, GROUP_SLOT_COUNT)
    groups: list[dict[str, Any]] = []
    authored_enemy_count = 0
    active_path_point_total = 0

    for group_index in range(active_group_count):
        group_offset = GROUP_OFFSET + group_index * GROUP_SIZE
        header = _read_words(data, group_offset, GROUP_HEADER_WORD_COUNT)
        active_enemy_count = header[4]
        if not 0 <= active_enemy_count <= ENEMY_SLOT_COUNT:
            raise LvdFormatError(
                f"{source_name}: group {group_index} enemy count "
                f"{active_enemy_count} is outside 0..{ENEMY_SLOT_COUNT}"
            )

        path_count = path_counts[group_index]
        if not 0 <= path_count <= PATH_POINT_SLOT_COUNT:
            raise LvdFormatError(
                f"{source_name}: group {group_index} path count {path_count} "
                f"is outside 0..{PATH_POINT_SLOT_COUNT}"
            )

        enemies: list[dict[str, Any]] = []
        for enemy_index in range(active_enemy_count):
            enemy_offset = group_offset + GROUP_HEADER_SIZE + enemy_index * ENEMY_RECORD_SIZE
            words = _read_words(data, enemy_offset, ENEMY_RECORD_WORD_COUNT)
            enemies.append(
                {
                    "index": enemy_index,
                    "file_offset": enemy_offset,
                    "raw_words": words,
                    "formation_target_x": words[0],
                    "formation_target_y": words[1],
                    "resource_slot_id": words[2],
                    "base_health": words[3],
                    "behavior_timer_a_initial": words[4],
                    "behavior_timer_a_step": words[5],
                    "behavior_timer_b_initial": words[6],
                    "behavior_timer_b_step": words[7],
                }
            )

        path_points: list[dict[str, Any]] = []
        path_group_offset = PATH_OFFSET + group_index * PATH_GROUP_SIZE
        for point_index in range(path_count):
            point_offset = path_group_offset + point_index * PATH_POINT_SIZE
            words = _read_words(data, point_offset, PATH_POINT_WORD_COUNT)
            path_points.append(
                {
                    "index": point_index,
                    "file_offset": point_offset,
                    "raw_words": words,
                    "acceleration_x_milli": words[0],
                    "acceleration_y_milli": words[1],
                    "opcode": words[2],
                    "unknown_0c": words[3],
                    "duration_threshold_ticks": words[4],
                }
            )

        authored_enemy_count += active_enemy_count
        active_path_point_total += path_count
        groups.append(
            {
                "index": group_index,
                "file_offset": group_offset,
                "raw_header_words": header,
                "entry_origin_x": header[0],
                "entry_origin_y": header[1],
                "first_activation_delay_ticks": header[2],
                "activation_stagger_ticks": header[3],
                "active_enemy_count": active_enemy_count,
                "initial_velocity_x_milli": header[5],
                "initial_velocity_y_milli": header[6],
                "kill_cohort_id": header[7],
                "group_mode_id": header[8],
                "active_path_point_count": path_count,
                "enemies": enemies,
                "path_points": path_points,
            }
        )

    title = _pascal_slot(data, TITLE_OFFSET, TITLE_SIZE)
    author = _pascal_slot(data, AUTHOR_OFFSET, AUTHOR_SIZE)
    resources = [
        {
            "index": resource_index,
            "traced_bitmap_slot": resource_index < 6,
            **_pascal_slot(
                data,
                RESOURCE_OFFSET + resource_index * RESOURCE_SLOT_SIZE,
                RESOURCE_SLOT_SIZE,
            ),
        }
        for resource_index in range(RESOURCE_SLOT_COUNT)
    ]

    fixed_table = []
    for record_index in range(FIXED_TABLE_RECORD_COUNT):
        record_offset = FIXED_TABLE_OFFSET + record_index * FIXED_TABLE_RECORD_SIZE
        fixed_table.append(
            {
                "index": record_index,
                "file_offset": record_offset,
                "raw_words": _read_words(
                    data, record_offset, FIXED_TABLE_RECORD_WORD_COUNT
                ),
            }
        )

    sha256 = _sha256(data)
    return {
        "schema": "warblade.lvd.lossless.v1",
        "interpretation_policy": (
            "raw_blob_base64 is the round-trip authority; interpreted aliases are "
            "read-only evidence views and are not serialized by encode"
        ),
        "source": {
            "file_name": Path(source_name).name,
            "size": len(data),
            "sha256": sha256,
        },
        "executable_evidence": {
            "warblade_exe_sha256": WARBLADE_EXE_SHA256,
            "file_read_function_va": "0x00568190",
            "deserializer_function_va": "0x00558d60",
            "address_kind": "32-bit PE virtual address",
        },
        "layout": {
            "file_size": FILE_SIZE,
            "regions": _layout_regions(),
        },
        "field_contract": _field_contract(),
        "runtime_contract": _runtime_contract(),
        "summary": {
            "title": title["text_cp1252"],
            "author": author["text_cp1252"],
            "level_mode_id": header_words[0],
            "active_group_count": active_group_count,
            "authored_enemy_count": authored_enemy_count,
            "active_path_point_total": active_path_point_total,
            "nonempty_resource_slots": [
                resource["text_cp1252"]
                for resource in resources
                if resource["length"] > 0
            ],
            "swd_reference_status": (
                "No literal .swd reference occurs in the fully mapped LVD blob; "
                "the executable instead loads a global compacted 14-file SWD "
                "catalog and state 2 selects from it without a per-LVD mapping."
            ),
        },
        "global_header": {
            "file_offset": GLOBAL_HEADER_OFFSET,
            "raw_words": header_words,
            "level_mode_id": header_words[0],
            "active_group_count": active_group_count,
            "supplemental_spawn_records_raw_words": [
                header_words[2 + record_index * 5 : 7 + record_index * 5]
                for record_index in range(5)
            ],
        },
        "path_count_array": {
            "file_offset": PATH_COUNT_OFFSET,
            "raw_words": path_counts,
        },
        "title_slot": title,
        "author_slot": author,
        "active_groups": groups,
        "inactive_group_slots_preserved_in_raw_blob": GROUP_SLOT_COUNT
        - active_group_count,
        "resource_slots": resources,
        "unresolved_fixed_table": {
            "file_offset": FIXED_TABLE_OFFSET,
            "records": fixed_table,
        },
        "unresolved_tail_array_a": {
            "file_offset": TAIL_A_OFFSET,
            "raw_words": _read_words(data, TAIL_A_OFFSET, TAIL_WORD_COUNT),
        },
        "unresolved_tail_array_b": {
            "file_offset": TAIL_B_OFFSET,
            "raw_words": _read_words(data, TAIL_B_OFFSET, TAIL_WORD_COUNT),
        },
        "raw_blob_base64": base64.b64encode(data).decode("ascii"),
    }


def decode_file(path: Path) -> dict[str, Any]:
    return decode_blob(path.read_bytes(), str(path))


def encode_document(document: dict[str, Any]) -> bytes:
    if document.get("schema") != "warblade.lvd.lossless.v1":
        raise LvdFormatError("unsupported or missing schema")
    encoded = document.get("raw_blob_base64")
    if not isinstance(encoded, str):
        raise LvdFormatError("raw_blob_base64 is missing or is not a string")
    try:
        data = base64.b64decode(encoded, validate=True)
    except (ValueError, TypeError) as error:
        raise LvdFormatError(f"invalid raw_blob_base64: {error}") from error
    if len(data) != FILE_SIZE:
        raise LvdFormatError(
            f"decoded raw blob is {len(data)} bytes, expected {FILE_SIZE}"
        )

    source = document.get("source")
    expected_hash = source.get("sha256") if isinstance(source, dict) else None
    actual_hash = _sha256(data)
    if expected_hash is not None and expected_hash != actual_hash:
        raise LvdFormatError(
            f"raw blob SHA-256 {actual_hash} does not match source.sha256 "
            f"{expected_hash}"
        )
    decode_blob(data, source.get("file_name", "<encoded-json>") if source else "")
    return data


def _dump_json(document: dict[str, Any], output_path: Path | None) -> None:
    text = json.dumps(document, indent=2, ensure_ascii=False) + "\n"
    if output_path is None:
        sys.stdout.write(text)
    else:
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(text, encoding="utf-8")


def _load_json(path: Path) -> dict[str, Any]:
    loaded = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(loaded, dict):
        raise LvdFormatError(f"{path}: root JSON value must be an object")
    return loaded


def _decode_command(input_path: Path, output_path: Path | None) -> int:
    _dump_json(decode_file(input_path), output_path)
    return 0


def _encode_command(input_path: Path, output_path: Path) -> int:
    data = encode_document(_load_json(input_path))
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(data)
    return 0


def _verify_paths(paths: Iterable[Path]) -> int:
    failures = 0
    for path in paths:
        try:
            original = path.read_bytes()
            document = decode_blob(original, str(path))
            rebuilt = encode_document(document)
            if rebuilt != original:
                raise LvdFormatError("decode/encode bytes differ")
            print(
                f"OK {path}: {len(original)} bytes, sha256={_sha256(original)}, "
                f"groups={document['summary']['active_group_count']}, "
                f"enemies={document['summary']['authored_enemy_count']}"
            )
        except (OSError, LvdFormatError, ValueError) as error:
            failures += 1
            print(f"FAIL {path}: {error}", file=sys.stderr)
    return 1 if failures else 0


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Losslessly decode the fixed-size Warblade LVD structure traced from "
            "warblade.exe."
        )
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    decode_parser = subparsers.add_parser("decode", help="decode an LVD file to JSON")
    decode_parser.add_argument("input", type=Path)
    decode_parser.add_argument("-o", "--output", type=Path)

    encode_parser = subparsers.add_parser(
        "encode", help="restore an LVD byte stream from lossless decoder JSON"
    )
    encode_parser.add_argument("input", type=Path)
    encode_parser.add_argument("output", type=Path)

    verify_parser = subparsers.add_parser(
        "verify", help="prove byte-identical decode/encode round trips"
    )
    verify_parser.add_argument("inputs", nargs="+", type=Path)
    return parser


def main() -> int:
    args = _build_parser().parse_args()
    try:
        if args.command == "decode":
            return _decode_command(args.input, args.output)
        if args.command == "encode":
            return _encode_command(args.input, args.output)
        if args.command == "verify":
            return _verify_paths(args.inputs)
        raise AssertionError(f"unhandled command {args.command}")
    except (OSError, json.JSONDecodeError, LvdFormatError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
