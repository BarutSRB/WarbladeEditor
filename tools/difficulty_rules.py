#!/usr/bin/env python3

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

DIFFICULTIES = (
    {
        "id": "easy",
        "numeric_id": 0,
        "menu_label_va": 0x0077F4C8,
        "menu_compare_va": 0x00591B07,
        "init_case_va": 0x005687A3,
        "init_end_va": 0x005688D2,
    },
    {
        "id": "normal",
        "numeric_id": 1,
        "menu_label_va": 0x0077F494,
        "menu_compare_va": 0x00591B2A,
        "init_case_va": 0x005688D2,
        "init_end_va": 0x00568A01,
    },
    {
        "id": "hard",
        "numeric_id": 2,
        "menu_label_va": 0x0077F460,
        "menu_compare_va": 0x00591B4D,
        "init_case_va": 0x00568A01,
        "init_end_va": 0x00568B34,
    },
    {
        "id": "ace",
        "numeric_id": 3,
        "menu_label_va": 0x0077F42C,
        "menu_compare_va": 0x00591B70,
        "init_case_va": 0x00568B34,
        "init_end_va": 0x00568C62,
    },
)

FIELD_SPECS = (
    (0x007D1520, "simulation_scale", "f32", "proven", "Authoritative simulation pace used by activation, paths, player movement, and projectile velocity."),
    (0x008F2058, "raw_8f2058", "i32", "evidence_only", "No supported finite-campaign runtime consumer is proven."),
    (0x008F20A4, "extra_time_floor", "i32", "proven", "Consumed as an Extra Time field floor; it is not the player fighter count."),
    (0x008F20B4, "timer_b_initial_adjustment", "i32", "proven", "Added to authored timer B at enemy spawn."),
    (0x008F20B8, "timer_a_initial_adjustment", "i32", "proven", "Added to authored timer A at enemy spawn."),
    (0x008F20AC, "timer_b_floor", "i32", "proven", "Minimum runtime timer B value."),
    (0x008F20B0, "timer_a_floor", "i32", "proven", "Minimum runtime timer A value."),
    (0x008F2060, "alien_projectile_base_speed", "f32", "proven", "Base vertical speed for the traced ordinary alien projectile."),
    (0x008F2024, "raw_8f2024", "i32", "evidence_only", "No supported finite-campaign runtime consumer is proven."),
    (0x008F2028, "raw_8f2028", "i32", "evidence_only", "No supported finite-campaign runtime consumer is proven."),
    (0x008F202C, "raw_8f202c", "i32", "evidence_only", "No supported finite-campaign runtime consumer is proven."),
    (0x008F2030, "consumer_range_a_8f2030", "f32", "supported", "A bounded executable consumer proves a numeric range but not a narrower semantic name."),
    (0x008F2034, "consumer_range_b_8f2034", "f32", "supported", "A bounded executable consumer proves a numeric range but not a narrower semantic name."),
    (0x008F2038, "consumer_threshold_8f2038", "f32", "supported", "A bounded executable consumer proves a numeric threshold but not a narrower semantic name."),
    (0x008F2080, "player_base_lateral_speed", "f32", "proven", "Base player lateral speed before the authoritative simulation scale."),
    (0x008F2084, "player_speed_upgrade_increment", "f32", "proven", "Player speed-upgrade increment."),
    (0x008F2090, "timed_effect_duration_ms", "i32", "proven", "Added to a millisecond clock; it is not a score award."),
    (0x008F2094, "meteor_parameter_8f2094", "f32", "proven", "Consumed by the retail Meteor controller; the neutral address-qualified name avoids a narrower claim."),
    (0x008F2098, "meteor_parameter_8f2098", "i32", "proven", "Consumed by the retail Meteor controller; the neutral address-qualified name avoids a narrower claim."),
    (0x008F209C, "meteor_threshold", "i32", "proven", "Consumed as a threshold by the retail Meteor controller."),
    (0x008F203C, "falling_bonus_drop_denominator", "f32", "proven", "Converted to an integer upper bound by the falling-bonus drop gate."),
    (0x008F206C, "special_enemy_health_base_a", "i32", "proven", "Health base for a traced special-enemy family."),
    (0x008F2070, "special_enemy_health_base_b", "i32", "proven", "Health base for a traced special-enemy family."),
    (0x008F207C, "special_enemy_health_base_c", "i32", "proven", "Health base for a traced special-enemy family."),
    (0x008F2074, "raw_8f2074", "f32", "evidence_only", "No supported finite-campaign runtime consumer is proven."),
    (0x008F2078, "special_enemy_health_base_d", "i32", "proven", "Health base for a traced special-enemy family."),
    (0x008F2020, "follower_launch_threshold", "i32", "proven", "Consumed by the state-2 follower launch branch."),
    (
        0x008F2068,
        "state_six_aimed_shot_travel_multiplier",
        "f32",
        "proven",
        "Multiplies the state-6 aimed-shot random travel divisor before velocity derivation.",
    ),
)

FIELD_BY_VA = {
    va: {
        "name": name,
        "storage": storage,
        "confidence": confidence,
        "role": role,
    }
    for va, name, storage, confidence, role in FIELD_SPECS
}

BORDER_SPECS = (
    ("easy", 0, 0x007826D8, 0x00E11100, 0x005A2D32, 0x0061F66C),
    ("normal", 1, 0x007826C8, 0x00E11104, 0x005A2D58, 0x0061F793),
    ("hard", 2, 0x007826B4, 0x00E11108, 0x005A2D7E, 0x0061F8BA),
    ("ace", 3, 0x007826A0, 0x00E1110C, 0x005A2DA4, 0x0061F9E1),
)

FALLING_BONUS_DROP_REGIONS = (
    (
        "collision_death_branch_a",
        0x00588B57,
        55,
        "0b460ce357f41c34d27162607b458d4f79b5bf6bb5f811632eed0f9e73e71a73",
    ),
    (
        "collision_death_branch_b",
        0x00589F0A,
        55,
        "7bd6fe35e6bf561d1b55e53d10a9582ccbf5bada2ad128f1f32173f24d948d7b",
    ),
)
RETAIL_INTEGER_RANGE_REGION = (
    0x0052F6E0,
    82,
    "b27d59c32a354995f57f49207261c37579988725cf7a33f6d2bf72a724f29ec0",
)


def _hex_va(value: int) -> str:
    return f"0x{value:08x}"


def _f32_from_bits(bits: int) -> float:
    return struct.unpack("<f", struct.pack("<I", bits))[0]


def _f32_bits(value: float) -> int:
    return struct.unpack("<I", struct.pack("<f", value))[0]


def _signed_u32(value: int) -> int:
    return struct.unpack("<i", struct.pack("<I", value))[0]


def _verified_region(
    image: "PEImage",
    name: str,
    virtual_address: int,
    size: int,
    expected_sha256: str,
) -> dict[str, Any]:
    payload = image.bytes_at(virtual_address, size)
    digest = hashlib.sha256(payload).hexdigest()
    if digest != expected_sha256:
        raise ValueError(
            f"{name} at {_hex_va(virtual_address)} SHA-256 changed: "
            f"expected {expected_sha256}, found {digest}"
        )
    return {
        "name": name,
        "virtual_address": _hex_va(virtual_address),
        "size": size,
        "sha256": digest,
    }


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

    def u32(self, va: int) -> int:
        return struct.unpack("<I", self.bytes_at(va, 4))[0]

    def i32(self, va: int) -> int:
        return struct.unpack("<i", self.bytes_at(va, 4))[0]

    def f32(self, va: int) -> float:
        return struct.unpack("<f", self.bytes_at(va, 4))[0]

    def f64(self, va: int) -> float:
        return struct.unpack("<d", self.bytes_at(va, 8))[0]

    def cstring(self, va: int, limit: int = 256) -> str:
        payload = self.bytes_at(va, limit)
        end = payload.find(b"\0")
        if end < 0:
            raise ValueError(f"unterminated string at {_hex_va(va)}")
        return payload[:end].decode("cp1252")


def _scan_case_assignments(image: PEImage, start_va: int, end_va: int) -> list[dict[str, Any]]:
    data = image.bytes_at(start_va, end_va - start_va)
    assignments: list[dict[str, Any]] = []
    index = 0
    while index < len(data):
        instruction_va = start_va + index
        if data[index : index + 4] == b"\xD9\xE8\xD9\x1D":
            destination = struct.unpack_from("<I", data, index + 4)[0]
            if destination in FIELD_BY_VA:
                assignments.append(
                    _assignment_payload(
                        image,
                        instruction_va,
                        destination,
                        0x3F800000,
                        None,
                    )
                )
            index += 8
            continue
        if data[index : index + 2] == b"\xD9\x05" and data[index + 6 : index + 8] == b"\xD9\x1D":
            source = struct.unpack_from("<I", data, index + 2)[0]
            destination = struct.unpack_from("<I", data, index + 8)[0]
            if destination in FIELD_BY_VA:
                assignments.append(
                    _assignment_payload(
                        image,
                        instruction_va,
                        destination,
                        image.u32(source),
                        source,
                    )
                )
            index += 12
            continue
        if data[index : index + 2] == b"\xC7\x05":
            destination, immediate = struct.unpack_from("<II", data, index + 2)
            if destination in FIELD_BY_VA:
                assignments.append(
                    _assignment_payload(
                        image,
                        instruction_va,
                        destination,
                        immediate,
                        None,
                    )
                )
            index += 10
            continue
        index += 1
    expected_destinations = set(FIELD_BY_VA)
    actual_destinations = {int(item["destination_va"], 16) for item in assignments}
    if actual_destinations != expected_destinations or len(assignments) != len(FIELD_SPECS):
        missing = sorted(expected_destinations - actual_destinations)
        extra = sorted(actual_destinations - expected_destinations)
        raise ValueError(
            f"incomplete difficulty case at {_hex_va(start_va)}: "
            f"count={len(assignments)} missing={[ _hex_va(item) for item in missing ]} "
            f"extra={[ _hex_va(item) for item in extra ]}"
        )
    return assignments


def _assignment_payload(
    image: PEImage,
    instruction_va: int,
    destination: int,
    raw_bits: int,
    source: int | None,
) -> dict[str, Any]:
    spec = FIELD_BY_VA[destination]
    payload: dict[str, Any] = {
        "instruction_va": _hex_va(instruction_va),
        "destination_va": _hex_va(destination),
        "name": spec["name"],
        "storage": spec["storage"],
        "confidence": spec["confidence"],
        "role": spec["role"],
    }
    if source is not None:
        payload["source_va"] = _hex_va(source)
    if spec["storage"] == "f32":
        payload["bits"] = f"0x{raw_bits:08x}"
        payload["value"] = _f32_from_bits(raw_bits)
    else:
        payload["value"] = _signed_u32(raw_bits)
    return payload


def _assignment_map(assignments: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    return {str(item["name"]): item for item in assignments}


def _scalar(assignments: dict[str, dict[str, Any]], name: str) -> int | float:
    return assignments[name]["value"]


def _timer_contract(
    authored: tuple[int, int, int, int],
    assignments: dict[str, dict[str, Any]],
) -> dict[str, Any]:
    a_initial, a_step, b_initial, b_step = authored
    a_adjustment = int(_scalar(assignments, "timer_a_initial_adjustment"))
    b_adjustment = int(_scalar(assignments, "timer_b_initial_adjustment"))
    a_floor = int(_scalar(assignments, "timer_a_floor"))
    b_floor = int(_scalar(assignments, "timer_b_floor"))
    a_spawn = max(a_initial + a_adjustment, a_floor)
    if b_initial == 0 and b_step == 0:
        b_spawn = 0
    else:
        b_spawn = max(b_initial + b_adjustment, b_floor)
    return {
        "authored": {
            "timer_a_initial": a_initial,
            "timer_a_step": a_step,
            "timer_b_initial": b_initial,
            "timer_b_step": b_step,
        },
        "spawn_runtime": {
            "timer_a": a_spawn,
            "timer_a_step": a_step,
            "timer_b": b_spawn,
            "timer_b_step": b_step,
        },
        "after_cumulative_qualifying_kills": {
            "timer_a": f"max({a_spawn} - {a_step} * K, {a_floor})",
            "timer_b": (
                "0"
                if b_spawn == 0
                else f"max({b_spawn} - {b_step} * K, {b_floor})"
            ),
        },
    }


def _extract_first_five(
    decoded_dir: Path,
    assignments_by_difficulty: dict[str, dict[str, dict[str, Any]]],
) -> list[dict[str, Any]]:
    levels: list[dict[str, Any]] = []
    for level_number in range(1, 6):
        path = decoded_dir / f"classic_level_{level_number:03d}.json"
        decoded = json.loads(path.read_text(encoding="utf-8"))
        contracts: set[tuple[int, int, int, int, int]] = set()
        authored_enemy_count = 0
        for group in decoded["active_groups"]:
            for enemy in group["enemies"]:
                authored_enemy_count += 1
                contracts.add(
                    (
                        int(enemy["base_health"]),
                        int(enemy["behavior_timer_a_initial"]),
                        int(enemy["behavior_timer_a_step"]),
                        int(enemy["behavior_timer_b_initial"]),
                        int(enemy["behavior_timer_b_step"]),
                    )
                )
        difficulty_payload: dict[str, Any] = {}
        for difficulty, assignments in assignments_by_difficulty.items():
            difficulty_payload[difficulty] = {
                "enemy_health_adjustment": 0,
                "enemy_health_result": sorted({contract[0] for contract in contracts}),
                "timer_contracts": [
                    _timer_contract(contract[1:], assignments)
                    for contract in sorted(contracts)
                ],
            }
        levels.append(
            {
                "level_number": level_number,
                "decoded_source": str(path),
                "title": decoded["summary"]["title"],
                "level_mode_id": decoded["summary"]["level_mode_id"],
                "authored_enemy_count": authored_enemy_count,
                "unique_authored_enemy_contracts": [
                    {
                        "base_health": contract[0],
                        "timer_a_initial": contract[1],
                        "timer_a_step": contract[2],
                        "timer_b_initial": contract[3],
                        "timer_b_step": contract[4],
                    }
                    for contract in sorted(contracts)
                ],
                "by_difficulty": difficulty_payload,
            }
        )
    return levels


def _runtime_summary(
    assignments_by_difficulty: dict[str, dict[str, dict[str, Any]]]
) -> dict[str, Any]:
    summary: dict[str, Any] = {}
    for difficulty, assignments in assignments_by_difficulty.items():
        base_speed = float(_scalar(assignments, "alien_projectile_base_speed"))
        simulation_scale = float(_scalar(assignments, "simulation_scale"))
        projectile_bits = _f32_bits(base_speed * simulation_scale)
        summary[difficulty] = {
            "simulation_scale": {
                "value": simulation_scale,
                "bits": assignments["simulation_scale"]["bits"],
            },
            "timer_a_initial_adjustment": int(
                _scalar(assignments, "timer_a_initial_adjustment")
            ),
            "timer_a_floor": int(_scalar(assignments, "timer_a_floor")),
            "timer_b_initial_adjustment": int(
                _scalar(assignments, "timer_b_initial_adjustment")
            ),
            "timer_b_floor": int(_scalar(assignments, "timer_b_floor")),
            "alien_projectile_base_speed": {
                "value": base_speed,
                "bits": assignments["alien_projectile_base_speed"]["bits"],
            },
            "alien_projectile_default_vertical_speed": {
                "value": _f32_from_bits(projectile_bits),
                "bits": f"0x{projectile_bits:08x}",
                "formula": "float32(alien_projectile_base_speed * simulation_scale)",
            },
            "player_base_lateral_speed": {
                "value": float(_scalar(assignments, "player_base_lateral_speed")),
                "bits": assignments["player_base_lateral_speed"]["bits"],
            },
            "player_speed_upgrade_increment": {
                "value": float(
                    _scalar(assignments, "player_speed_upgrade_increment")
                ),
                "bits": assignments["player_speed_upgrade_increment"]["bits"],
            },
            "falling_bonus_drop_denominator": {
                "value": int(
                    float(_scalar(assignments, "falling_bonus_drop_denominator"))
                ),
                "bits": assignments["falling_bonus_drop_denominator"]["bits"],
            },
            "state_six_aimed_shot_travel_multiplier": {
                "value": float(
                    _scalar(
                        assignments,
                        "state_six_aimed_shot_travel_multiplier",
                    )
                ),
                "bits": assignments[
                    "state_six_aimed_shot_travel_multiplier"
                ]["bits"],
            },
            "special_enemy_health_bases": [
                int(_scalar(assignments, "special_enemy_health_base_a")),
                int(_scalar(assignments, "special_enemy_health_base_b")),
                int(_scalar(assignments, "special_enemy_health_base_c")),
                int(_scalar(assignments, "special_enemy_health_base_d")),
            ],
        }
    return summary


def _build_borders(image: PEImage) -> list[dict[str, Any]]:
    borders: list[dict[str, Any]] = []
    for difficulty, numeric_id, string_va, handle_va, load_va, render_compare_va in BORDER_SPECS:
        borders.append(
            {
                "difficulty": difficulty,
                "numeric_id": numeric_id,
                "filename": image.cstring(string_va, 32),
                "filename_va": _hex_va(string_va),
                "texture_handle_va": _hex_va(handle_va),
                "load_va": _hex_va(load_va),
                "render_compare_va": _hex_va(render_compare_va),
                "confidence": "proven",
            }
        )
    return borders


def _build_lives(image: PEImage) -> dict[str, Any]:
    base, step, initial_offset, maximum_offset = struct.unpack(
        "<4i", image.bytes_at(0x007D1524, 16)
    )
    initial_encoded = initial_offset // step
    maximum_encoded = maximum_offset // step
    sequence = []
    current = base + initial_offset
    for death in range(1, initial_encoded + 1):
        current -= step
        sequence.append(
            {
                "death_number": death,
                "raw_value_after_decrement": current,
                "fighters_after_decrement": (current - base) // step,
                "respawns": current > base,
            }
        )
    return {
        "confidence": "proven",
        "difficulty_independent": True,
        "ship_zero_config_va": _hex_va(0x007D1524),
        "ship_pointer_install_va": _hex_va(0x00624D32),
        "raw_encoding": {
            "base": base,
            "step": step,
            "initial_offset": initial_offset,
            "maximum_offset": maximum_offset,
        },
        "initial_total_fighters": initial_encoded,
        "maximum_total_fighters": maximum_encoded,
        "initialization": {
            "va": "0x00623aad-0x00623ade",
            "formula": f"raw = {base} + {initial_offset}; encoded = (raw - {base}) / {step} = {initial_encoded}",
        },
        "hud": {
            "va": "0x005d5e29-0x005d5e91",
            "formula": "encoded_count = (raw - base) / step; current player draws encoded_count - 1 reserve icons",
            "initial_reserve_icons": initial_encoded - 1,
        },
        "death_and_respawn": {
            "decrement_va": "0x005ecfbe-0x005ecfeb",
            "terminal_check_va": "0x005ed058-0x005ed084",
            "rule": "Subtract one encoded fighter first, then respawn only when raw > base.",
            "initial_death_sequence": sequence,
            "game_over_on_death_number": initial_encoded,
        },
        "storage": {
            "session_zero_field_va": "0x00848750",
            "session_stride": "0x4d8",
            "retail_ownership": "Each player session has its own encoded fighter field. A shared co-op pool is remake-specific.",
        },
        "manual_corroboration": {
            "path": "../Game/Warblade_Manual_V1.34_Eng.txt",
            "line": 346,
            "paraphrase": "Three fighters total: one in play and two on the sidebar.",
        },
        "remake_contract": "The value 3 is total fighters, not three reserves. A remaining-reserve representation must initialize to 2.",
    }


def _build_score_cash_boundary(
    image: PEImage,
    assignment_destinations: set[int],
    assignments_by_difficulty: dict[str, dict[str, dict[str, Any]]],
) -> dict[str, Any]:
    score_start = 0x0058663A
    score_end = 0x00586721
    score_bytes = image.bytes_at(score_start, score_end - score_start)
    watched = {0x00AF7940, *assignment_destinations}
    direct_refs = sorted(
        address
        for address in watched
        if struct.pack("<I", address) in score_bytes
    )
    drop_regions = [
        _verified_region(image, name, virtual_address, size, digest)
        for name, virtual_address, size, digest in FALLING_BONUS_DROP_REGIONS
    ]
    range_va, range_size, range_digest = RETAIL_INTEGER_RANGE_REGION
    range_region = _verified_region(
        image,
        "retail_half_open_integer_range",
        range_va,
        range_size,
        range_digest,
    )
    denominators: dict[str, dict[str, Any]] = {}
    for difficulty, assignments in assignments_by_difficulty.items():
        assignment = assignments["falling_bonus_drop_denominator"]
        value = float(assignment["value"])
        if not value.is_integer() or int(value) <= 1:
            raise ValueError(
                f"{difficulty} falling-bonus denominator is not a valid integer: {value}"
            )
        denominators[difficulty] = {
            "value": int(value),
            "float32_bits": str(assignment["bits"]),
            "assignment_va": str(assignment["instruction_va"]),
        }
    return {
        "score": {
            "confidence": "supported",
            "ordinary_alien_award_path_va": "0x0058663a-0x0058671b",
            "player_score_fields_va": ["0x00848760", "0x00848764"],
            "enemy_award_fields_va": ["0x00849bb8", "0x00849bbc"],
            "direct_difficulty_references_in_bounded_path": [
                _hex_va(item) for item in direct_refs
            ],
            "conclusion": "The traced ordinary-alien award path has no direct difficulty selector or difficulty-init global reference. This is not proof that every score source is difficulty-independent.",
        },
        "falling_bonus_drop": {
            "confidence": "proven",
            "difficulty_global_va": "0x008f203c",
            "denominators": denominators,
            "consumer_regions": drop_regions,
            "float_to_integer_thunk_va": "0x00526ae0",
            "integer_range": {
                **range_region,
                "lower_bound": 1,
                "upper_bound": "trunc_toward_zero(difficulty denominator)",
                "upper_bound_inclusive": False,
                "implementation": "unsigned U32 modulo (upper - lower), then add lower; no rejection sampling",
            },
            "success_condition": "random integer in [1, denominator) is strictly below 4",
            "runtime_contract": "1 + (U32 mod (denominator - 1)) < 4",
        },
        "cash": {
            "confidence": "evidence_only",
            "player_cash_field_va": "0x00848794",
            "runtime_consumer": None,
            "conclusion": "No reachable finite-campaign consumer for a difficulty cash multiplier is proven. The product applies no fabricated multiplier.",
        },
    }


def build_evidence(exe_path: Path, decoded_dir: Path) -> dict[str, Any]:
    image = PEImage(exe_path)
    if image.sha256 != WARBLADE_EXE_SHA256:
        raise ValueError(
            f"unexpected warblade.exe SHA-256 {image.sha256}; "
            f"expected {WARBLADE_EXE_SHA256}"
        )

    jump_table = [image.u32(0x00568C6C + index * 4) for index in range(4)]
    expected_jump_table = [int(item["init_case_va"]) for item in DIFFICULTIES]
    if jump_table != expected_jump_table:
        raise ValueError(
            f"difficulty jump table changed: "
            f"{[ _hex_va(item) for item in jump_table ]}"
        )

    assignments_by_difficulty: dict[str, dict[str, dict[str, Any]]] = {}
    assignment_lists: dict[str, list[dict[str, Any]]] = {}
    enum_cases: list[dict[str, Any]] = []
    for spec in DIFFICULTIES:
        assignments = _scan_case_assignments(
            image,
            int(spec["init_case_va"]),
            int(spec["init_end_va"]),
        )
        difficulty = str(spec["id"])
        menu_text = image.cstring(int(spec["menu_label_va"]), 0x34)
        assignment_lists[difficulty] = assignments
        assignments_by_difficulty[difficulty] = _assignment_map(assignments)
        enum_cases.append(
            {
                "id": difficulty,
                "numeric_id": int(spec["numeric_id"]),
                "menu_label": menu_text.rsplit(":", 1)[-1].strip(),
                "menu_text": menu_text,
                "menu_label_va": _hex_va(int(spec["menu_label_va"])),
                "menu_compare_va": _hex_va(int(spec["menu_compare_va"])),
                "init_case_va": _hex_va(int(spec["init_case_va"])),
            }
        )

    runtime_summary = _runtime_summary(assignments_by_difficulty)
    first_five = _extract_first_five(decoded_dir, assignments_by_difficulty)
    assignment_destinations = set(FIELD_BY_VA)

    return {
        "schema": "warblade-difficulty-rules-v2",
        "source": {
            "path": str(exe_path),
            "sha256": image.sha256,
            "image_base": _hex_va(image.image_base),
        },
        "confidence_scale": {
            "proven": "The retail executable assignment and complete gameplay consumer are traced.",
            "supported": "A bounded consumer supports the role, but its full gameplay boundary is not closed.",
            "evidence_only": "The raw difficulty value is exact, but no supported finite-campaign runtime behavior is asserted.",
        },
        "difficulty_enum": {
            "global_va": "0x00af7940",
            "switch_va": "0x0056877e-0x005687a2",
            "jump_table_va": "0x00568c6c",
            "jump_table": [_hex_va(item) for item in jump_table],
            "cases": enum_cases,
        },
        "difficulty_init": {
            "function_va": "0x00568760-0x00568c68",
            "assignments_by_difficulty": assignment_lists,
            "runtime_summary": runtime_summary,
        },
        "first_five_levels": {
            "health": {
                "confidence": "proven",
                "spawn_va": "0x0056d094-0x0056d114",
                "difficulty_additive_global_va": "0x00e113f8",
                "zero_init_va": "0x0053818a",
                "later_progression_increment_va": "0x00538375-0x00538381",
                "rule": "The additive health global starts at 0 and is not written by any difficulty case. Its first normal progression increment requires level > 5 and (level - 1) mod 100 == 0, so levels 1-5 use authored LVD health exactly.",
            },
            "timer_spawn_va": "0x0056d160-0x0056d2f7",
            "timer_kill_adjustment_va": "0x0058b900-0x0058bab9",
            "timer_kill_counter_increment_vas": [
                "0x00587ef6",
                "0x005881c0",
                "0x00588b30",
                "0x0058954a",
                "0x00589ee3",
                "0x0058b1e9",
            ],
            "timer_rule": "Timer A/B steps are multiplied by the number of qualifying enemy destructions in the collision/death pass, not by simulation tick scale. Remaining active non-state-8 enemies whose timer B is nonzero are tightened and clamped to difficulty floors.",
            "levels": first_five,
        },
        "simulation_scale": {
            "confidence": "proven",
            "difficulty_source_global_va": "0x007d1520",
            "authoritative_runtime_global_va": "0x00e11274",
            "ordinary_copy_va": "0x005a086a-0x005a0870",
            "special_fast_override_va": "0x005a0851-0x005a0868",
            "retail_update_target": {
                "value": 60,
                "global_va": "0x00af7890",
                "init_va": "0x005a0830",
            },
            "consumers": [
                {
                    "role": "enemy activation countdown",
                    "va": "0x00607f2e-0x00607fc4",
                    "operation": "countdown -= simulation_scale",
                },
                {
                    "role": "enemy path position, velocity, and progress",
                    "va": "0x00613a21-0x00613bbe",
                    "operation": "position += velocity * scale; velocity += acceleration * scale; progress += scale",
                },
                {
                    "role": "player movement",
                    "va": "0x005eb6cd-0x005eb6e8",
                    "operation": "player_delta *= simulation_scale",
                },
                {
                    "role": "alien projectile velocity",
                    "va": "0x006079fc-0x00607a34",
                    "operation": "projectile_base_speed *= simulation_scale",
                },
            ],
            "conclusion": "Hard and Ace accelerate the whole traced simulation boundary, including the player. This is not a renderer-frame-rate setting.",
        },
        "alien_fire": {
            "confidence": "proven",
            "gate_and_compare_va": "0x00607725-0x006077cc",
            "timer_a_runtime_field_va": "0x00849bcc",
            "gates": [
                "player/session field 0x8487ec must be zero",
                "global 0xe1146c must be zero",
                "enemy Y must be greater than -10.0",
                "level mode global 0xa95c20 must not equal 3",
                "a free projectile slot must exist",
            ],
            "rng": {
                "helper_va": "0x0052f800-0x0052f860",
                "prng_thunk_va": "0x0052856b",
                "unit_scale_constant_va": "0x00778e90",
                "unit_scale": image.f64(0x00778E90),
                "result": "r = float32(U32 * timer_a * 2^-32), with U32 interpreted unsigned through a zero high dword",
            },
            "threshold": {
                "double_two_constant_va": "0x00779b40",
                "double_two": image.f64(0x00779B40),
                "strict_condition": "fire only when r < 2 * simulation_scale",
                "idealized_probability_per_update": "min(1, 2 * simulation_scale / timer_a)",
                "caveat": "The retail boundary rounds the RNG helper result to float32 before the strict comparison.",
            },
            "timer_evolution": "timer_a = max(spawn_timer_a - authored_timer_a_step * cumulative_qualifying_kills, difficulty_timer_a_floor)",
        },
        "deterministic_server_guidance": {
            "bit_exact_retail": {
                "rule": "Load the original float32 bit patterns, round the RNG helper result to float32, and preserve the strict less-than comparison.",
                "critical_bits": {
                    "hard_simulation_scale": "0x3f955555",
                    "ace_simulation_scale": "0x3faaaaab",
                    "normal_projectile_base_speed_4_3": "0x4089999a",
                },
            },
            "recommended_modern_fixed_point": {
                "status": "intentional modernization, not bit-exact retail arithmetic",
                "simulation_scale_sixths": {
                    "easy": 6,
                    "normal": 6,
                    "hard": 7,
                    "ace": 8,
                    "denominator": 6,
                },
                "countdown_and_path_rule": "Store countdown and path progress in sixth-tick integer units.",
                "fire_test": "For deterministic U32 and timer A, test U32 * timer_a * 3 < 2^32 * scale_numerator, where scale_numerator is 6, 6, 7, or 8.",
                "fire_test_caveat": "This removes platform float variance but differs at rare retail float32 boundary cases; version it and cover it with golden replay tests.",
                "projectile_speed_sixtieths": {
                    "easy": 210,
                    "normal": 258,
                    "hard": 350,
                    "ace": 440,
                    "denominator": 60,
                },
            },
        },
        "borders": _build_borders(image),
        "lives": _build_lives(image),
        "score_and_cash": _build_score_cash_boundary(
            image, assignment_destinations, assignments_by_difficulty
        ),
        "corrections_to_earlier_evidence": [
            {
                "document": "docs/evidence/LVD_STATIC_TRACE.md",
                "correction": "0xe11274 is difficulty-controlled on Hard/Ace, not always 1.0 in normal gameplay.",
            },
            {
                "document": "docs/evidence/LVD_STATIC_TRACE.md",
                "correction": "0x58b9a4-0x58bab9 applies authored timer steps per qualifying kill count, not per tick_scale.",
            },
            {
                "document": "docs/evidence/PLAYER_STATIC_TRACE.md",
                "correction": "The encoded initial value 3 is now proven to mean three total fighters, with game over on the third death.",
            },
        ],
        "evidence_only": [
            "Difficulty globals marked evidence_only are retained by address and exact bits without manufactured finite-campaign behavior.",
            "No reachable finite-campaign consumer for a difficulty cash multiplier is proven; the product applies no multiplier.",
        ],
        "supported_semantic_boundaries": [
            "Only the ordinary-alien score award boundary is closed narrowly; no global score-multiplier claim is made.",
            "Timer B's runtime behavior is implemented at proven consumers without asserting a broader human taxonomy.",
        ],
    }


def _default_paths() -> tuple[Path, Path, Path]:
    root = Path(__file__).resolve().parents[1]
    return (
        root / "Game" / "warblade.exe",
        root / "content" / "lvd_decoded",
        root / "docs" / "evidence" / "difficulty_rules.json",
    )


def main() -> int:
    default_exe, default_decoded, default_output = _default_paths()
    parser = argparse.ArgumentParser(
        description="Extract bounded retail Warblade difficulty evidence."
    )
    parser.add_argument("--exe", type=Path, default=default_exe)
    parser.add_argument("--decoded-dir", type=Path, default=default_decoded)
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

    evidence = build_evidence(args.exe.resolve(), args.decoded_dir.resolve())
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
        print(f"difficulty evidence is current: {args.output}")
        return 0
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(rendered, encoding="utf-8")
    print(f"wrote {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
