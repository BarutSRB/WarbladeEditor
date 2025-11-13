#!/usr/bin/env python3
"""
Warblade .lvd helper.

Subcommands:
  decode <level>      - Read '<level>' from warblade.pac and emit structured JSON.
  encode --json <path> --out <path>
                      - Convert JSON produced by 'decode' back into a .lvd blob.

The JSON layout mirrors the block ranges observed in fcn.0019f1a0:
- header (blocks 0-1)
- formations (blocks 3-1285)
- six shop chunks (blocks 1287-1764)
- 19 auxiliary tables (blocks 1849-3540)
- footers (blocks 3631, 3650, 3675)
Anything outside that layout is preserved via the "remainder" list.
"""

from __future__ import annotations

import argparse
import json
import struct
import tarfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Iterable, List, Tuple

ARCHIVE_NAME = "data/warblade.pac"
RECORD_SIZE = 32  # bytes (8 little-endian ints)
EVENT_TABLE_PREFIX = "event_table_"
ENEMY_FORMATION_SECTION = "enemy_formations"
EVENT_SLOT_FIELD_ORDER: Tuple[str, ...] = (
    "in_use_flag",
    "spawn_delay_frames",
    "owner_id",
    "table_index",
    "normalized_progress",
    "base_delta",
    "event_stage",
    "event_stage_secondary",
    "child_handle_a",
    "child_handle_b",
    "wave_counter",
    "sprite_behavior_c",
    "cached_global_a",
    "cached_global_b",
    "sprite_behavior_a",
    "sprite_behavior_b",
    "start_time",
    "target_time",
    "travel_duration",
    "speed_accumulator",
    "unused_word_20",
    "promotion_ramp",
    "hud_enabled",
    "scoreboard_slot",
    "fade_timer",
    "blink_counter",
    "rng_offset_a",
    "rng_offset_b",
    "base_scale",
    "current_scale",
    "base_alpha",
    "current_alpha",
)
EVENT_TABLE_WORDS_PER_RECORD = 8
FORMATION_FIELD_ORDER: Tuple[str, ...] = (
    "spawn_delay_start",
    "spawn_delay_increment",
    "spawn_delay_secondary",
    "spawn_window_secondary",
    "offset_x",
    "offset_y",
    "enemy_type",
    "behavior_flags",
)
HEADER_FIELD_ORDER: Tuple[str, ...] = (
    "version_id",
    "mode_id",
    "seed_word_0",
    "seed_word_1",
    "difficulty_mask",
    "starting_lives",
    "starting_credits",
    "reserved_word",
)
HEADER_RESERVED_FIELD_ORDER: Tuple[str, ...] = tuple(
    f"reserved_word_{idx}" for idx in range(8)
)
FOOTER_METADATA_FIELD_ORDER: Tuple[str, ...] = (
    "checksum",
    "signature_word_0",
    "signature_word_1",
    "signature_word_2",
    "signature_word_3",
    "signature_word_4",
    "record_count_marker",
    "reserved_word",
)
FOOTER_UNLOCK_FLAGS_FIELD_ORDER: Tuple[str, ...] = (
    "flags_word_0",
    "flags_word_1",
    "unlock_flag_primary",
    "flags_word_3",
    "flags_word_4",
    "flags_word_5",
    "flags_word_6",
    "flags_word_7",
)
FOOTER_SLOT_COUNT_FIELD_ORDER: Tuple[str, ...] = (
    "reserved_word_0",
    "reserved_word_1",
    "shop_slot_count",
    "reserved_word_3",
    "reserved_word_4",
    "reserved_word_5",
    "reserved_word_6",
    "reserved_word_7",
)
SHOP_IMDA_HEADER_FIELD_ORDER: Tuple[str, ...] = (
    "signature",
    "record_size_bytes",
    "reserved_word_0",
    "reserved_word_1",
    "reserved_word_2",
    "reserved_word_3",
    "reserved_word_4",
    "reserved_word_5",
)
EVENT_AUX_FIELD_ORDER: Tuple[str, ...] = (
    "origin_x",
    "origin_y",
    "target_x",
    "target_y",
    "velocity_x",
    "velocity_y",
    "timer_primary",
    "timer_secondary",
)
NEWS_TICKER_FIELD_ORDER: Tuple[str, ...] = EVENT_AUX_FIELD_ORDER
EVENT_AUX_SECTION_ALIASES: Dict[str, str] = {
    "event_table_1_aux": "promotion_banner_paths",
    "event_table_2_aux": "meteor_arc_paths",
    "event_table_3_aux": "boss_callout_paths",
    "event_table_4_aux": "rank_marker_gates",
    "event_table_5_aux": "reward_ribbon_paths",
    "event_table_6_aux": "hud_flash_counters",
}
EVENT_AUX_FRIENDLY_TO_RAW: Dict[str, str] = {
    friendly: raw for raw, friendly in EVENT_AUX_SECTION_ALIASES.items()
}
SECTION_SEGMENT_LABELS: Dict[str, Tuple[str, ...]] = {
    "promotion_banner_paths": (
        "vertical_pre_roll",
        "column_alignment_gate",
        "backdrop_swing",
        "slot_anchor_offset",
        "diagonal_swoop",
        "linger_jitter",
        "scoreboard_snap",
        "return_buffer",
        "flash_hold",
        "diagonal_exit",
        "fade_out_clamp",
    ),
    "meteor_arc_paths": (
        "entry_lane",
        "hud_speed_meter",
        "abort_lane",
        "cooldown_gate",
    ),
    "boss_callout_paths": (
        "warning_left_slide",
        "camera_pan_left",
        "warning_center_slide",
        "warning_right_slide",
        "blink_gate_a",
        "blink_gate_b",
        "linger_counter",
    ),
    "rank_marker_gates": (
        "required_mark_gate",
        "slot_0_marker_gate",
        "slot_1_marker_gate",
        "slot_2_marker_gate",
        "slot_3_marker_gate",
        "slot_4_marker_gate",
        "slot_5_marker_gate",
        "full_set_latch",
        "full_height_flash_gate",
    ),
    "reward_ribbon_paths": (
        "carousel_anchor_top_left",
        "carousel_anchor_top_right",
        "carousel_anchor_bottom_left",
        "carousel_anchor_bottom_right",
        "expand_vertical_gate",
        "expand_horizontal_gate",
        "collapse_horizontal_gate",
        "collapse_vertical_gate",
        "scoreboard_sync_gate",
        "reserved_slot_9",
        "reserved_slot_10",
        "reserved_slot_11",
        "reserved_slot_12",
        "reserved_slot_13",
        "reserved_slot_14",
        "reserved_slot_15",
    ),
    "hud_flash_counters": (
        "rank_flash_timer",
        "reward_flash_timer",
    ),
    "news_ticker_globals": (
        "news_slot_1",
        "news_slot_2",
        "news_slot_3",
        "news_slot_4",
    ),
}
NAMED_SECTION_FIELDS: Dict[str, Tuple[str, ...]] = {
    "header": HEADER_FIELD_ORDER,
    "header_reserved": HEADER_RESERVED_FIELD_ORDER,
    "shop_inventory_imda_header": SHOP_IMDA_HEADER_FIELD_ORDER,
    "footer_metadata": FOOTER_METADATA_FIELD_ORDER,
    "footer_unlock_flags": FOOTER_UNLOCK_FLAGS_FIELD_ORDER,
    "footer_slot_counts": FOOTER_SLOT_COUNT_FIELD_ORDER,
    "news_ticker_globals": NEWS_TICKER_FIELD_ORDER,
    "news_ticker_runtime_shadow": NEWS_TICKER_FIELD_ORDER,
}
for raw_name in EVENT_AUX_SECTION_ALIASES:
    NAMED_SECTION_FIELDS[raw_name] = EVENT_AUX_FIELD_ORDER
SHOP_INVENTORY_CHUNK_NAMES: Tuple[str, ...] = tuple(
    f"shop_inventory_chunk_{idx}" for idx in range(6)
)
SHOP_INVENTORY_ENTRY_WORDS = 19  # 0x4c-byte structs / 4-byte ints
SHOP_INVENTORY_FIELD_ORDER: Tuple[str, ...] = (
    "slot_state",
    "page_id",
    "category",
    "price_primary",
    "price_secondary",
    "stock_count",
    "stock_alt",
    "ui_column",
    "ui_pos_x",
    "ui_pos_y",
    "ui_width",
    "ui_height",
    "icon_id",
    "icon_variant",
    "item_id",
    "item_arg_0",
    "item_arg_1",
    "unlock_req",
    "reserved_word",
)


def _annotate_event_records(records: List[List[int]]) -> List[Dict[str, int]]:
    return _annotate_named_records(records, EVENT_SLOT_FIELD_ORDER)


def _flatten_event_record(entry: Any, word_count: int) -> List[int]:
    return _flatten_named_record(entry, EVENT_SLOT_FIELD_ORDER[:word_count])


def _annotate_named_records(records: List[List[int]], field_order: Tuple[str, ...]) -> List[Dict[str, int]]:
    annotated: List[Dict[str, int]] = []
    for record in records:
        entry: Dict[str, int] = {}
        for idx, value in enumerate(record):
            field_name = field_order[idx] if idx < len(field_order) else f"word_{idx}"
            entry[field_name] = value
        annotated.append(entry)
    return annotated


def _flatten_named_record(entry: Any, field_order: Tuple[str, ...]) -> List[int]:
    if isinstance(entry, list):
        return entry
    if isinstance(entry, dict):
        return [int(entry.get(field, 0)) for field in field_order]
    raise TypeError("Record must be a list or dict")


def _extract_shop_inventory_entries(sections: Dict[str, Dict[str, Any]]) -> None:
    chunk_sections: List[Dict[str, Any]] = []
    for name in SHOP_INVENTORY_CHUNK_NAMES:
        section = sections.get(name)
        if section is None:
            return
        chunk_sections.append(section)
    if not chunk_sections:
        return
    flattened: List[int] = []
    for section in chunk_sections:
        for record in section["records"]:
            flattened.extend(record)
    if not flattened:
        return
    entries: List[Dict[str, int]] = []
    for idx in range(0, len(flattened), SHOP_INVENTORY_ENTRY_WORDS):
        words = flattened[idx : idx + SHOP_INVENTORY_ENTRY_WORDS]
        if len(words) < SHOP_INVENTORY_ENTRY_WORDS:
            words = words + [0] * (SHOP_INVENTORY_ENTRY_WORDS - len(words))
        entry = {
            field: int(words[field_idx])
            for field_idx, field in enumerate(SHOP_INVENTORY_FIELD_ORDER)
        }
        entries.append(entry)
    sections["shop_inventory"] = {
        "start_block": chunk_sections[0]["start_block"],
        "end_block": chunk_sections[-1]["end_block"],
        "record_count": len(entries),
        "entry_words": SHOP_INVENTORY_ENTRY_WORDS,
        "source_chunks": list(SHOP_INVENTORY_CHUNK_NAMES),
        "records": entries,
    }


def _tag_section_segment_labels(section_name: str, section: Dict[str, Any]) -> None:
    labels = SECTION_SEGMENT_LABELS.get(section_name)
    if not labels:
        return
    for record, label in zip(section.get("records", []), labels):
        if isinstance(record, dict):
            record.setdefault("segment_name", label)


def _apply_segment_labels(sections: Dict[str, Dict[str, Any]]) -> None:
    for name, section in sections.items():
        _tag_section_segment_labels(name, section)


def _alias_event_aux_sections(sections: Dict[str, Dict[str, Any]]) -> None:
    for raw_name, friendly_name in EVENT_AUX_SECTION_ALIASES.items():
        section = sections.pop(raw_name, None)
        if section is None:
            continue
        aliased = dict(section)
        aliased.setdefault("source_section", raw_name)
        _tag_section_segment_labels(friendly_name, aliased)
        sections[friendly_name] = aliased


def _decode_news_asset_blob(sections: Dict[str, Dict[str, Any]]) -> None:
    section = sections.get("news_asset_blob")
    if section is None:
        return
    raw_records = section.get("records", [])
    if raw_records and isinstance(raw_records[0], dict):
        return  # already decoded
    blob = bytearray()
    for record in raw_records:
        blob.extend(struct.pack("<8i", *record))
    total_bytes = len(blob)
    entries: List[Dict[str, Any]] = []
    current_padding: List[int] = []
    idx = 0
    while idx < total_bytes:
        byte = blob[idx]
        if byte < 0x20:
            current_padding.append(byte)
            idx += 1
            continue
        start = idx
        while idx < total_bytes and blob[idx] >= 0x20:
            idx += 1
        raw_name = blob[start:idx].decode("ascii", errors="ignore")
        lower = raw_name.lower()
        bmp_pos = lower.find(".bmp")
        if bmp_pos != -1:
            raw_name = raw_name[: bmp_pos + 4]
        raw_name = raw_name.strip()
        entries.append(
            {
                "filename": raw_name,
                "padding": list(current_padding),
            }
        )
        current_padding = []
        if idx < total_bytes and blob[idx] == 0:
            idx += 1  # skip the mandatory terminator
    section["raw_block_count"] = section.get(
        "raw_block_count", len(raw_records)
    )
    section["byte_length"] = total_bytes
    section["record_count"] = len(entries)
    section["records"] = entries
    section["trailing_padding"] = list(current_padding)


def _encode_news_asset_blob(section: Dict[str, Any], total_blocks: int) -> List[List[int]]:
    entries = section.get("records", [])
    trailing_bytes: Iterable[int] = section.get("trailing_padding", [])
    total_bytes = total_blocks * RECORD_SIZE
    blob = bytearray()
    for entry in entries:
        padding = entry.get("padding", [])
        blob.extend(bytes(int(b) & 0xFF for b in padding))
        filename = entry.get("filename", "")
        blob.extend(filename.encode("ascii"))
        blob.append(0)
    blob.extend(bytes(int(b) & 0xFF for b in trailing_bytes))
    if len(blob) > total_bytes:
        raise ValueError(
            f"news_asset_blob exceeds allocated size ({len(blob)} > {total_bytes})"
        )
    if len(blob) < total_bytes:
        blob.extend(b"\x00" * (total_bytes - len(blob)))
    ints = [
        struct.unpack("<i", blob[offset : offset + 4])[0]
        for offset in range(0, total_bytes, 4)
    ]
    return [ints[idx : idx + INTS_PER_RECORD] for idx in range(0, len(ints), INTS_PER_RECORD)]


def _restore_event_aux_sections(sections: Dict[str, Dict[str, Any]]) -> None:
    for friendly_name, raw_name in EVENT_AUX_FRIENDLY_TO_RAW.items():
        section = sections.pop(friendly_name, None)
        if section is None:
            continue
        if raw_name in sections:
            raise ValueError(
                f"Descriptor contains both '{friendly_name}' and '{raw_name}' sections"
            )
        sections[raw_name] = section


def _apply_shop_inventory_entries(sections: Dict[str, Dict[str, Any]]) -> None:
    shop_section = sections.pop("shop_inventory", None)
    if not shop_section:
        return
    flattened: List[int] = []
    for entry in shop_section.get("records", []):
        flattened.extend(
            int(entry.get(field, 0)) for field in SHOP_INVENTORY_FIELD_ORDER
        )
    total_ints = len(flattened)
    cursor = 0
    for name in SHOP_INVENTORY_CHUNK_NAMES:
        chunk = sections.get(name)
        if chunk is None:
            start, end = SECTION_LAYOUT_MAP.get(name, (0, -1))
            record_count = max(0, end - start + 1)
            chunk = {
                "start_block": start,
                "end_block": end,
                "record_count": record_count,
                "records": [[0] * INTS_PER_RECORD for _ in range(record_count)],
            }
            sections[name] = chunk
        record_count = chunk["record_count"]
        ints_needed = record_count * INTS_PER_RECORD
        chunk_values = flattened[cursor : cursor + ints_needed]
        cursor += ints_needed
        if len(chunk_values) < ints_needed:
            chunk_values = chunk_values + [0] * (ints_needed - len(chunk_values))
        chunk["records"] = [
            chunk_values[idx : idx + INTS_PER_RECORD]
            for idx in range(0, ints_needed, INTS_PER_RECORD)
        ]
    if cursor < total_ints:
        # Extra ints beyond the chunk allocation are silently dropped to preserve layout.
        pass


# (name, start_block, end_block) inclusive ranges
SECTION_LAYOUT: Tuple[Tuple[str, int, int], ...] = (
    ("header", 0, 1),
    ("header_reserved", 2, 2),
    ("enemy_formations", 3, 1285),
    ("shop_inventory_imda_header", 1286, 1286),
    ("shop_inventory_chunk_0", 1287, 1300),
    ("shop_inventory_chunk_0_tail", 1301, 1302),
    ("shop_inventory_chunk_1", 1381, 1394),
    ("shop_inventory_chunk_1_tail", 1395, 1407),
    ("shop_inventory_chunk_2", 1474, 1485),
    ("shop_inventory_chunk_2_tail", 1486, 1487),
    ("shop_inventory_chunk_3", 1568, 1579),
    ("shop_inventory_chunk_3_tail", 1580, 1581),
    ("shop_inventory_chunk_4", 1662, 1671),
    ("shop_inventory_chunk_4_tail", 1672, 1675),
    ("shop_inventory_chunk_5", 1756, 1764),
    ("shop_inventory_chunk_5_tail", 1765, 1766),
    ("event_table_0", 1849, 1852),
    ("news_ticker_globals", 1853, 1856),
    ("event_table_1", 1943, 1945),
    ("event_table_1_aux", 1946, 1956),
    ("event_table_2", 2037, 2039),
    ("event_table_2_aux", 2040, 2043),
    ("event_table_3", 2131, 2132),
    ("event_table_3_aux", 2133, 2139),
    ("event_table_4_header", 2224, 2224),
    ("event_table_4", 2225, 2226),
    ("event_table_4_aux", 2227, 2235),
    ("event_table_5", 2318, 2320),
    ("event_table_5_aux", 2321, 2336),
    ("event_table_6", 2412, 2414),
    ("event_table_6_aux", 2415, 2416),
    ("event_table_7", 2506, 2507),
    ("event_table_8_header", 2599, 2599),
    ("event_table_8", 2600, 2601),
    ("event_table_9", 2693, 2695),
    ("event_table_10", 2787, 2789),
    ("event_table_11", 2881, 2882),
    ("event_table_12", 2975, 2976),
    ("event_table_13", 3068, 3070),
    ("event_table_14", 3162, 3165),
    ("event_table_15", 3256, 3259),
    ("event_table_16", 3350, 3352),
    ("event_table_17", 3443, 3446),
    ("event_table_18", 3537, 3540),
    ("footer_metadata", 3631, 3631),
    ("news_asset_blob", 3632, 3639),
    ("footer_unlock_flags", 3650, 3650),
    ("news_ticker_runtime_shadow", 3651, 3652),
    ("footer_slot_counts", 3675, 3675),
)
SECTION_LAYOUT_MAP: Dict[str, Tuple[int, int]] = {name: (start, end) for name, start, end in SECTION_LAYOUT}
INTS_PER_RECORD = RECORD_SIZE // 4


@dataclass
class SectionView:
    name: str
    start: int
    end: int
    records: List[List[int]]

    @property
    def expected_count(self) -> int:
        return self.end - self.start + 1


def _iter_records(blob: bytes, total_blocks: int) -> Iterable[List[int]]:
    for idx in range(total_blocks):
        chunk = blob[idx * RECORD_SIZE : (idx + 1) * RECORD_SIZE]
        if len(chunk) < RECORD_SIZE:
            # Should not happen, but guard anyway.
            chunk = chunk.ljust(RECORD_SIZE, b"\x00")
        yield list(struct.unpack("<8i", chunk))


def parse_lvd_bytes(blob: bytes) -> Dict:
    total_blocks = len(blob) // RECORD_SIZE
    tail = blob[total_blocks * RECORD_SIZE :]
    records = list(_iter_records(blob, total_blocks))

    sections: Dict[str, SectionView] = {}
    covered = set()
    for name, start, end in SECTION_LAYOUT:
        section_records = records[start : end + 1] if end < len(records) else []
        sections[name] = SectionView(name, start, end, section_records)
        covered.update(range(start, min(end + 1, len(records))))

    remainder = [
        {"block": idx, "values": record}
        for idx, record in enumerate(records)
        if idx not in covered and any(record)
    ]

    sections_dict: Dict[str, Dict[str, Any]] = {}
    for name, view in sections.items():
        records: Iterable[Any]
        if name == ENEMY_FORMATION_SECTION:
            records = _annotate_named_records(view.records, FORMATION_FIELD_ORDER)
        elif name in NAMED_SECTION_FIELDS:
            records = _annotate_named_records(view.records, NAMED_SECTION_FIELDS[name])
        elif name.startswith(EVENT_TABLE_PREFIX):
            records = _annotate_event_records(view.records)
        else:
            records = view.records
        sections_dict[name] = {
            "start_block": view.start,
            "end_block": view.end,
            "record_count": len(view.records),
            "records": list(records),
        }

    _extract_shop_inventory_entries(sections_dict)
    _alias_event_aux_sections(sections_dict)
    _apply_segment_labels(sections_dict)
    _decode_news_asset_blob(sections_dict)

    return {
        "record_size": RECORD_SIZE,
        "total_blocks": total_blocks,
        "sections": sections_dict,
        "remainder": remainder,
        "tail_hex": tail.hex(),
    }


def encode_lvd(descriptor: Dict) -> bytes:
    total_blocks = descriptor["total_blocks"]
    record_size = descriptor.get("record_size", RECORD_SIZE)
    if record_size != RECORD_SIZE:
        raise ValueError(f"Unsupported record_size {record_size}")

    blocks: List[List[int]] = [[0] * 8 for _ in range(total_blocks)]

    sections = dict(descriptor.get("sections", {}))
    _apply_shop_inventory_entries(sections)
    _restore_event_aux_sections(sections)
    for name, meta in sections.items():
        start = meta["start_block"]
        end = meta["end_block"]
        raw_records: List[Any] = meta["records"]
        if name == ENEMY_FORMATION_SECTION:
            processed_records = [
                _flatten_named_record(entry, FORMATION_FIELD_ORDER)
                for entry in raw_records
            ]
        elif name == "news_asset_blob" and (
            "trailing_padding" in meta
            or (raw_records and isinstance(raw_records[0], dict))
        ):
            processed_records = _encode_news_asset_blob(
                meta, total_blocks=end - start + 1
            )
        elif name in NAMED_SECTION_FIELDS:
            processed_records = [
                _flatten_named_record(entry, NAMED_SECTION_FIELDS[name])
                for entry in raw_records
            ]
        elif name.startswith(EVENT_TABLE_PREFIX):
            processed_records = [
                _flatten_event_record(entry, EVENT_TABLE_WORDS_PER_RECORD)
                for entry in raw_records
            ]
        else:
            processed_records = raw_records
        records: List[List[int]] = processed_records
        expected = end - start + 1
        if len(records) != expected:
            raise ValueError(f"Section '{name}' expects {expected} records, got {len(records)}")
        for offset, record in enumerate(records):
            if len(record) != 8:
                raise ValueError(f"Section '{name}' record {offset} must have 8 ints")
            blocks[start + offset] = record

    for entry in descriptor.get("remainder", []):
        idx = entry["block"]
        values = entry["values"]
        if len(values) != 8:
            raise ValueError(f"Remainder block {idx} must have 8 ints")
        blocks[idx] = values

    tail_hex = descriptor.get("tail_hex", "")
    tail_bytes = bytes.fromhex(tail_hex) if tail_hex else b""

    blob = bytearray(total_blocks * RECORD_SIZE + len(tail_bytes))
    for idx, record in enumerate(blocks):
        chunk = struct.pack("<8i", *record)
        blob[idx * RECORD_SIZE : (idx + 1) * RECORD_SIZE] = chunk
    if tail_bytes:
        blob[total_blocks * RECORD_SIZE :] = tail_bytes
    return bytes(blob)


def extract_lvd_from_pac(pac_path: Path, member_name: str) -> bytes:
    with tarfile.open(pac_path, "r") as tar:
        member = tar.getmember(member_name)
        fileobj = tar.extractfile(member)
        if fileobj is None:
            raise RuntimeError(f"Unable to read {member_name} from {pac_path}")
        return fileobj.read()


def decode_command(args: argparse.Namespace) -> None:
    if args.file is not None:
        blob = args.file.read_bytes()
    elif args.entry:
        blob = extract_lvd_from_pac(args.pac, args.entry)
    else:
        raise SystemExit("decode: provide a tar entry name or use --file")
    descriptor = parse_lvd_bytes(blob)
    output = json.dumps(descriptor, indent=2)
    if args.json:
        args.json.write_text(output)
    else:
        print(output)


def encode_command(args: argparse.Namespace) -> None:
    descriptor = json.loads(args.json.read_text())
    blob = encode_lvd(descriptor)
    args.out.write_bytes(blob)
    print(f"[lvd] wrote {args.out} ({len(blob)} bytes)")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    decode_p = subparsers.add_parser("decode", help="Decode a level into JSON")
    decode_p.add_argument(
        "entry",
        nargs="?",
        help="Tar entry name (e.g., classic_level_001.lvd). Omit when using --file.",
    )
    decode_p.add_argument(
        "--pac",
        type=Path,
        default=Path(ARCHIVE_NAME),
        help=f"Path to warblade.pac (default: {ARCHIVE_NAME})",
    )
    decode_p.add_argument(
        "--file",
        type=Path,
        help="Read directly from a standalone .lvd file instead of the PAC entry.",
    )
    decode_p.add_argument(
        "--json",
        type=Path,
        help="Destination JSON path (stdout if omitted)",
    )

    encode_p = subparsers.add_parser("encode", help="Encode JSON back into .lvd")
    encode_p.add_argument(
        "--json",
        type=Path,
        required=True,
        help="JSON file produced by the decode command",
    )
    encode_p.add_argument(
        "--out",
        type=Path,
        required=True,
        help="Path to write the .lvd blob",
    )

    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()
    if args.command == "decode":
        decode_command(args)
    elif args.command == "encode":
        encode_command(args)
    else:
        parser.error("Unknown command")


if __name__ == "__main__":
    main()
