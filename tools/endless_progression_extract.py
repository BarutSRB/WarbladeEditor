#!/usr/bin/env python3
"""Extract bounded retail evidence for campaign play beyond level 100.

The finite-campaign evidence in difficulty_rules.json documents that the
ordinary health additive at 0x00e113f8 increments only when
``level > 5 and (level - 1) mod 100 == 0``. This extractor pins the complete
retail progression step that fires at levels 101, 201, 301, ... together with
the content-cycling and mirror rules that make endless play coherent:

- per-step ordinary health additive (+1.0) and special-class health additive
  (+5.0, with one traced class consuming the additive times 20.0);
- per-step ordinary alien projectile base-speed multiplier (x1.025);
- per-step simulation-scale increment (+float32(0.12));
- per-step timer A/B initial-adjustment decrement (-50, floored at -500);
- per-step per-player update-target increment (+2/+3/+3/+2 by difficulty);
- content cycling on ``level mod 100`` (background bands) and the LVD mirror
  rule ``(level // 100) & 1``;
- the retail level counter clamp at 3999.

Two code sites apply the identical step: the level-start path
(0x00569be5-0x00569c55) and the cumulative resume/warp loop
(0x005382dd-0x00538403), whose loop bound proves steps accumulate once per
crossed hundred up to the current level.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import struct
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any


WARBLADE_EXE_SHA256 = "ddf1778c307af1087ff9dcb512786111e665d972298aeaac3f1b4b2996d079ef"

# Floating-point constants consumed by the progression step.
F64_CONSTANTS = (
    (0x00778E48, "ordinary_health_step", 1.0),
    (0x00778DE8, "special_health_step", 5.0),
    (0x00779AC8, "projectile_speed_step_multiplier", 1.024999976158142),
    (0x00779AB8, "simulation_scale_step", 0.11999999731779099),
    (0x0077AD58, "special_health_traced_class_multiplier", 20.0),
)

# Instruction pins: (va, expected bytes, label). Each pin anchors one claim.
INSTRUCTION_PINS = (
    # Cumulative loop condition: for L in ...: if L > 5 and (L - 1) mod 100 == 0.
    (0x005382E4, bytes.fromhex("b964000000"), "loop_divisor_100"),
    (0x005382E9, bytes.fromhex("f7f9"), "loop_idiv"),
    (0x005382EB, bytes.fromhex("85d2"), "loop_remainder_test"),
    (0x005382F3, bytes.fromhex("837df805"), "loop_level_above_five"),
    # Step body (cumulative site): timer adjustments -= 50, floored at -500.
    (0x00538334, bytes.fromhex("83e832"), "timer_step_decrement_50"),
    (0x0053833C, bytes.fromhex("813db4208f000cfeffff"), "timer_b_floor_minus_500"),
    (0x0053835F, bytes.fromhex("813db8208f000cfeffff"), "timer_a_floor_minus_500"),
    # Step body (cumulative site): health additive, projectile speed, sim scale,
    # per-player update target.
    (0x00538375, bytes.fromhex("d905f813e100"), "cumulative_health_add"),
    (0x00538387, bytes.fromhex("d905fc13e100"), "cumulative_special_health_add"),
    (0x00538399, bytes.fromhex("d90560208f00"), "cumulative_projectile_mul"),
    (0x005383AB, bytes.fromhex("d90520157d00"), "cumulative_scale_add"),
    (0x005383CE, bytes.fromhex("030d58208f00"), "cumulative_update_target_add"),
    # Step body (level-start site): identical operations.
    (0x00569BC7, bytes.fromhex("83e832"), "level_start_timer_decrement_50"),
    (0x00569BE5, bytes.fromhex("d905f813e100"), "level_start_health_add"),
    (0x00569BF7, bytes.fromhex("d905fc13e100"), "level_start_special_health_add"),
    (0x00569C09, bytes.fromhex("d90560208f00"), "level_start_projectile_mul"),
    (0x00569C1B, bytes.fromhex("d90520157d00"), "level_start_scale_add"),
    (0x00569C3E, bytes.fromhex("030d58208f00"), "level_start_update_target_add"),
    # Level counter clamp: min(level, 3999).
    (0x00569C73, bytes.fromhex("81b8bc8784009f0f0000"), "level_clamp_3999"),
    # Mirror rule: byte [0xe10f3b] = (level // 100) & 1.
    (0x0056A708, bytes.fromhex("b964000000"), "mirror_divisor_100"),
    (0x0056A70D, bytes.fromhex("f7f9"), "mirror_idiv"),
    (0x0056A70F, bytes.fromhex("83e001"), "mirror_and_one"),
    (0x0056A712, bytes.fromhex("a23b0fe100"), "mirror_flag_store"),
    # Content cycling: background band keys on level mod 100 (remainder).
    (0x00569D68, bytes.fromhex("b964000000"), "band_divisor_100"),
    (0x00569D6D, bytes.fromhex("f7f9"), "band_idiv"),
    (0x00569D6F, bytes.fromhex("89955cffffff"), "band_remainder_store"),
    # Ordinary spawn health consumers: current and max health.
    (0x0056D094, bytes.fromhex("d905f813e100"), "spawn_health_current_add"),
    (0x0056D0DF, bytes.fromhex("d905f813e100"), "spawn_health_max_add"),
    # Special-class consumer multiplying the +5.0 additive by 20.0.
    (0x0056B52F, bytes.fromhex("d905fc13e100"), "special_class_health_add"),
    (0x0056B535, bytes.fromhex("dc0d58ad7700"), "special_class_times_20"),
    # Per-player update-target initialization from the retail update target.
    (0x005B33DC, bytes.fromhex("8b0d9078af00"), "update_target_init_read"),
    (0x005B33E2, bytes.fromhex("8988a48b8400"), "update_target_init_store"),
)


@dataclass(frozen=True)
class Section:
    name: str
    va: int
    virtual_size: int
    raw_offset: int
    raw_size: int


class PEImage:
    def __init__(self, path: Path):
        self.path = path
        self.data = path.read_bytes()
        if self.data[:2] != b"MZ":
            raise ValueError(f"{path} is not a PE executable")
        pe_offset = struct.unpack_from("<I", self.data, 0x3C)[0]
        if self.data[pe_offset : pe_offset + 4] != b"PE\0\0":
            raise ValueError(f"{path} has no PE signature")
        section_count = struct.unpack_from("<H", self.data, pe_offset + 6)[0]
        optional_size = struct.unpack_from("<H", self.data, pe_offset + 20)[0]
        optional_offset = pe_offset + 24
        if struct.unpack_from("<H", self.data, optional_offset)[0] != 0x10B:
            raise ValueError(f"{path} is not a 32-bit PE image")
        self.image_base = struct.unpack_from("<I", self.data, optional_offset + 28)[0]
        section_offset = optional_offset + optional_size
        sections: list[Section] = []
        for index in range(section_count):
            offset = section_offset + index * 40
            name = self.data[offset : offset + 8].split(b"\0", 1)[0].decode("ascii")
            virtual_size, rva, raw_size, raw_offset = struct.unpack_from(
                "<IIII", self.data, offset + 8
            )
            sections.append(
                Section(
                    name=name,
                    va=self.image_base + rva,
                    virtual_size=virtual_size,
                    raw_offset=raw_offset,
                    raw_size=raw_size,
                )
            )
        self.sections = tuple(sections)

    @property
    def sha256(self) -> str:
        return hashlib.sha256(self.data).hexdigest()

    def file_offset(self, va: int, size: int = 1) -> int:
        for section in self.sections:
            extent = max(section.virtual_size, section.raw_size)
            if section.va <= va and va + size <= section.va + extent:
                offset = section.raw_offset + va - section.va
                if offset + size > section.raw_offset + section.raw_size:
                    raise ValueError(f"{_hex_va(va)} is uninitialized PE data")
                return offset
        raise ValueError(f"{_hex_va(va)} is outside mapped PE sections")

    def bytes_at(self, va: int, size: int) -> bytes:
        offset = self.file_offset(va, size)
        return self.data[offset : offset + size]

    def f64(self, va: int) -> float:
        return struct.unpack("<d", self.bytes_at(va, 8))[0]


def _hex_va(value: int) -> str:
    return f"0x{value:08x}"


def build_evidence(exe_path: Path) -> dict[str, Any]:
    image = PEImage(exe_path)
    if image.sha256 != WARBLADE_EXE_SHA256:
        raise ValueError(
            f"unexpected executable hash {image.sha256}; "
            f"expected {WARBLADE_EXE_SHA256}"
        )

    constants: dict[str, Any] = {}
    for va, name, expected in F64_CONSTANTS:
        value = image.f64(va)
        constants[name] = {
            "va": _hex_va(va),
            "bytes_hex": image.bytes_at(va, 8).hex(),
            "value": value,
            "matches_documented_value": value == expected,
        }

    pins: dict[str, Any] = {}
    failures: list[str] = []
    for va, expected, label in INSTRUCTION_PINS:
        actual = image.bytes_at(va, len(expected))
        pins[label] = {
            "va": _hex_va(va),
            "bytes_hex": actual.hex(),
            "matches_documented_bytes": actual == expected,
        }
        if actual != expected:
            failures.append(label)
    if failures:
        raise ValueError(
            "executable bytes drifted at: " + ", ".join(sorted(failures))
        )

    return {
        "schema": "warblade-endless-progression-v1",
        "source": {
            "path": str(exe_path),
            "sha256": image.sha256,
            "image_base": _hex_va(image.image_base),
        },
        "confidence_scale": {
            "proven": "The retail instruction bytes and their gameplay consumers are pinned by this extraction.",
            "evidence_only": "The exact value is preserved but its consumer is not closed here.",
        },
        "step_trigger": {
            "confidence": "proven",
            "rule": "level > 5 and (level - 1) mod 100 == 0",
            "levels": [101, 201, 301],
            "cumulative_steps_at_level": "(level - 1) // 100",
            "loop_va": "0x005382dd-0x00538403",
            "level_start_va": "0x00569be5-0x00569c55",
        },
        "step_effects": {
            "ordinary_health_additive": {
                "confidence": "proven",
                "global_va": "0x00e113f8",
                "per_step": 1.0,
                "spawn_consumers": {
                    "current_health_va": "0x0056d094",
                    "max_health_va": "0x0056d0df",
                    "rule": "spawn health = authored LVD base + int(additive)",
                },
            },
            "special_health_additive": {
                "confidence": "proven",
                "global_va": "0x00e113fc",
                "per_step": 5.0,
                "traced_class_multiplier": 20.0,
                "traced_class_consumer_va": "0x0056b52f-0x0056b546",
                "rule": "traced special classes use authored base + int(additive) and authored base + int(additive * 20.0)",
            },
            "projectile_speed": {
                "confidence": "proven",
                "global_va": "0x008f2060",
                "per_step_multiplier": 1.024999976158142,
                "rational": "41/40",
                "note": "retail stores float32(1.025) widened to double; the deterministic model uses exactly 41/40",
            },
            "simulation_scale": {
                "confidence": "proven",
                "global_va": "0x007d1520",
                "per_step_increment": 0.11999999731779099,
                "rational": "3/25",
                "note": "retail stores float32(0.12) widened to double; the deterministic model uses exactly 3/25",
            },
            "timer_adjustments": {
                "confidence": "proven",
                "global_vas": ["0x008f20b4", "0x008f20b8"],
                "per_step_decrement": 50,
                "floor": -500,
            },
            "update_target": {
                "confidence": "proven",
                "player_field_va": "0x00848ba4",
                "retail_default_va": "0x00af7890",
                "retail_default": 60,
                "per_step_increment_by_difficulty": {
                    "easy": 2,
                    "normal": 3,
                    "hard": 3,
                    "ace": 2,
                },
                "increment_source_global_va": "0x008f2058",
            },
        },
        "content_cycling": {
            "confidence": "proven",
            "rule": "level content and presentation cycle with period 100; the background band keys on level mod 100",
            "wrapped_level_formula": "((level - 1) mod 100) + 1",
            "band_va": "0x00569d61-0x00569d6f",
            "custom_level_support": "classic_level_%03d.lvd loads by exact number first; files above 100 are user content, while the built-in campaign cycles",
        },
        "mirror_rule": {
            "confidence": "proven",
            "flag_va": "0x00e10f3b",
            "rule": "mirror_x = (level // 100) & 1",
            "bands": "levels 100-199 mirrored, 200-299 not, alternating",
            "code_va": "0x0056a6f6-0x0056a712",
        },
        "level_counter_clamp": {
            "confidence": "proven",
            "maximum_level": 3999,
            "code_va": "0x00569c73-0x00569c81",
        },
        "constants": constants,
        "instruction_pins": pins,
        "first_step_side_effect": {
            "confidence": "evidence_only",
            "global_va": "0x007d0790",
            "value": 60,
            "note": "written once per session on the first progression step; no consumer is closed here",
        },
    }


def _default_paths() -> tuple[Path, Path]:
    root = Path(__file__).resolve().parents[1]
    return (
        root / "Game" / "warblade.exe",
        root / "docs" / "evidence" / "endless_progression.json",
    )


def main() -> int:
    default_exe, default_output = _default_paths()
    parser = argparse.ArgumentParser(
        description="Extract bounded retail endless-progression evidence."
    )
    parser.add_argument("--exe", type=Path, default=default_exe)
    parser.add_argument("--output", type=Path, default=default_output)
    parser.add_argument(
        "--check",
        action="store_true",
        help="Fail if the output file is not identical to freshly extracted evidence.",
    )
    parser.add_argument(
        "--stdout",
        action="store_true",
        help="Write extracted JSON to stdout instead of updating the output file.",
    )
    args = parser.parse_args()

    evidence = build_evidence(args.exe.resolve())
    rendered = json.dumps(evidence, indent=2, ensure_ascii=False) + "\n"
    if args.stdout:
        sys.stdout.write(rendered)
        return 0
    if args.check:
        if not args.output.exists():
            print(f"missing generated evidence: {args.output}", file=sys.stderr)
            return 1
        if args.output.read_text(encoding="utf-8") != rendered:
            print(f"stale generated evidence: {args.output}", file=sys.stderr)
            return 1
        print(f"endless progression evidence is current: {args.output}")
        return 0
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(rendered, encoding="utf-8")
    print(f"wrote {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
