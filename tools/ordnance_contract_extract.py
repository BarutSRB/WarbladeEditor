#!/usr/bin/env python3

"""Generate the executable-backed Rocket Pack and Alien Lock contract."""

from __future__ import annotations

import argparse
import hashlib
import json
import struct
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_EXE = PROJECT_ROOT / "Game" / "warblade.exe"
DEFAULT_MANUAL = PROJECT_ROOT / "Game" / "Warblade_Manual_V1.34_Eng.txt"
DEFAULT_OUTPUT = PROJECT_ROOT / "content" / "ordnance.json"
DEFAULT_EVIDENCE = PROJECT_ROOT / "docs" / "evidence" / "ORDNANCE_RUNTIME_TRACE.md"

EXECUTABLE_SHA256 = "ddf1778c307af1087ff9dcb512786111e665d972298aeaac3f1b4b2996d079ef"


class OrdnanceContractError(ValueError):
    pass


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _hex(value: int) -> str:
    return f"0x{value:08x}"


@dataclass(frozen=True)
class Section:
    va: int
    virtual_size: int
    raw_offset: int
    raw_size: int


class PEImage:
    """Minimal PE32 reader used to pin the original executable by virtual address."""

    def __init__(self, path: Path):
        self.path = path
        self.data = path.read_bytes()
        if self.data[:2] != b"MZ":
            raise OrdnanceContractError(f"{path} is not a PE executable")
        pe_offset = struct.unpack_from("<I", self.data, 0x3C)[0]
        if self.data[pe_offset : pe_offset + 4] != b"PE\0\0":
            raise OrdnanceContractError(f"{path} has no PE signature")
        section_count = struct.unpack_from("<H", self.data, pe_offset + 6)[0]
        optional_size = struct.unpack_from("<H", self.data, pe_offset + 20)[0]
        optional_offset = pe_offset + 24
        if struct.unpack_from("<H", self.data, optional_offset)[0] != 0x10B:
            raise OrdnanceContractError(f"{path} is not a 32-bit PE image")
        self.image_base = struct.unpack_from("<I", self.data, optional_offset + 28)[0]
        section_offset = optional_offset + optional_size
        sections: list[Section] = []
        for index in range(section_count):
            offset = section_offset + index * 40
            virtual_size, rva, raw_size, raw_offset = struct.unpack_from(
                "<IIII", self.data, offset + 8
            )
            sections.append(
                Section(
                    va=self.image_base + rva,
                    virtual_size=virtual_size,
                    raw_offset=raw_offset,
                    raw_size=raw_size,
                )
            )
        self.sections = tuple(sections)

    @property
    def sha256(self) -> str:
        return _sha256(self.data)

    def file_offset(self, va: int, size: int = 1) -> int:
        for section in self.sections:
            extent = max(section.virtual_size, section.raw_size)
            if section.va <= va and va + size <= section.va + extent:
                offset = section.raw_offset + va - section.va
                if offset + size > section.raw_offset + section.raw_size:
                    raise OrdnanceContractError(f"{_hex(va)} is uninitialized PE data")
                return offset
        raise OrdnanceContractError(f"{_hex(va)} is outside mapped PE sections")

    def bytes_at(self, va: int, size: int) -> bytes:
        offset = self.file_offset(va, size)
        return self.data[offset : offset + size]

    def u32(self, va: int) -> int:
        return struct.unpack("<I", self.bytes_at(va, 4))[0]

    def f32(self, va: int) -> float:
        return struct.unpack("<f", self.bytes_at(va, 4))[0]

    def f64(self, va: int) -> float:
        return struct.unpack("<d", self.bytes_at(va, 8))[0]

    def c_string(self, va: int, maximum: int = 2048) -> str:
        offset = self.file_offset(va)
        end = self.data.find(b"\0", offset, offset + maximum)
        if end < 0:
            raise OrdnanceContractError(f"unterminated executable string at {_hex(va)}")
        return self.data[offset:end].decode("cp1252")


CODE_REGIONS = (
    ("rocket_pack_purchase", 0x00562007, 176, "97c0220e3a8d757d02c8eb7a4d00a2e077ef06281fe55b525789f3a08f4f1614"),
    ("alien_lock_purchase", 0x00561F92, 112, "ed0d0e47518ad751608d554643edc208b8305a17e7198aa8e9d419b0c46ee297"),
    ("secondary_input_target_and_spawn", 0x005EBB6E, 1232, "26a6e21c46cdb24682f73133e3100a49cfc13ffcaaae90f5bfe3a3a035529a49"),
    ("missile_update", 0x0061FFF0, 2288, "48fa98b2b573ea8436bd0e291805a3e99b157b7ba53f7fadcad414a22ba17e2a"),
    ("missile_render", 0x006211E0, 1040, "4ac9d7741aeb13aa0f46503ca0033e857069b87e69cd270341e1a7be5ed1f8e6"),
    ("player_projectile_enemy_collision", 0x00585840, 7424, "1ed35c685d70a977f7deb74719dba25697acb12f27d8c420e29e0a687ac44da5"),
    ("warp_alien_lock_retention", 0x0055DA8C, 168, "b058cb6b5e2574ba099df1a781a7df8baac6e2dda07a243b028c80f73e6ef850"),
    ("ordinary_death_alien_lock_clear", 0x005719D8, 32, "507c5aaee7f7b67007df7b20452c40ab7b271b5ad6929eaabc66dbb77d0f4eae"),
    ("final_kill_projectile_reward", 0x00555D08, 880, "01fc20ec14e492c8bb57dab17c1217d93906d3fc98a84fd6393b6dbaccf85fe0"),
    ("final_kill_rocket_inventory_reward", 0x005562B2, 162, "078953b55d4771388529f71bc72870ea4b4ca4467f8db0915997911c9bf0cdab"),
    ("saved_game_snapshot_writer", 0x00537C80, 928, "586da2f9c89cf79c075793a76fed08f47930807202cf132d79e796d6aa12c2c8"),
    ("saved_game_snapshot_loader", 0x005384F0, 2064, "bdfc973ce575edaacae60128163ff94d6348ec2b53793a5ca012845db9ab5d95"),
    ("above_level_25_accuracy_sample", 0x005696F0, 224, "d37ed95d889d4ce60b10586b1d13420c68735d0fc97150533794f8f2f3f83352"),
    ("new_player_initialization", 0x00623980, 1424, "d771cc1cb0d62a989c6d5936fc2342dd822f795503e83e33cc1af485df97218f"),
    ("retail_match_mode_identity_switch", 0x0059C8A7, 121, "79f5cd01d6827784ed74a944c67e2ac8a585a19f32f082e2f6a968287e3ea48f"),
)

EXECUTABLE_STRINGS = {
    "rocket_reward_notice": (0x0077AE00, "10 ROCKETS ADDED", False),
    "alien_lock_notice": (0x0077B290, "ALIEN LOCK ON", False),
    "rocket_pack_description": (0x0077CEB0, "R O C K E T   P A C K :||Buy 10 fast homing missiles.", True),
    "alien_lock_description": (0x0077D0B8, "A L I E N   L O C K :||This powerful device can hold captured aliens", True),
    "secondary_binding_label": (0x00785E39, "FIRE ROCKET :", True),
    "rocket_sound": (0x00779724, "rocket", False),
    "expiry_sound": (0x007797D8, "explo1", False),
    "flare_texture": (0x00782900, "flare4.tga", False),
    "time_trial_mode_label": (0x00780E1C, "Game mode : TIME TRIAL GAME\r\n", False),
}

MANUAL_REFS = {
    "pc_secondary_control": (293, "Fire Missiles =  Left ALT"),
    "mac_secondary_control": (304, "Fire Missiles =  Z"),
    "alien_lock_savegame_fix": (734, "Savegames causing alien lock loss"),
    "player_two_rockets_fix": (777, "Player 2 was unable to fire rockets"),
    "rocket_particles": (855, "Particle routine to rockets"),
    "post_death_input_fix": (992, "fire rocets after you die"),
    "meteor_storm_input_fix": (993, "fire rockets in meteor storm"),
    "distance_audio": (1112, "distance between player and missile"),
}

ASSETS = {
    "texture": {
        "path": "assets/original/textures/weapons/rocket.tga",
        "size": 59178,
        "sha256": "a5c98c0179c1cb3e71768a05b4ab1a97b8ec0aed612a5212c2b40851d094b6e7",
    },
    "hit_mask": {
        "path": "assets/original/textures/weapons/rocket.hma",
        "size": 55296,
        "sha256": "36bd2fa91456584345b4239d14196112044ced58d8663b277f34370b05718e05",
    },
    "fire_sound": {
        "path": "assets/original/samples/rocket.mp3",
        "size": 26656,
        "sha256": "6cedd252acfaf8268faf74005b069d13bbaba076da201c687d7b39cd2e8fa131",
    },
    "shop_image": {
        "path": "assets/original/textures/shop/shop_rocketpack.jpg",
        "size": 6999,
        "sha256": "442c98b18071003ee691f35467bb5aed868009762fb4cdb4c6809e56dbe040b7",
    },
}

# FUN_0061fff0 indexes each address with the retail heading itself (1...32),
# so the first used value is four bytes after the encoded base. These are raw
# IEEE-754 binary32 words, not values regenerated with a host trig library.
MOVEMENT_X_FLOAT32_BITS = [
    0x00000000, 0x3E47C5C2, 0x3EC3EF15, 0x3F0E39DA,
    0x3F3504F3, 0x3F54DB31, 0x3F6C835E, 0x3F7B14BE,
    0x3F800000, 0x3F7B14BE, 0x3F6C835E, 0x3F54DB31,
    0x3F3504F3, 0x3F0E39DA, 0x3EC3EF15, 0x3E47C5C2,
    0x00000000, 0xBE47C5C2, 0xBEC3EF15, 0xBF0E39DA,
    0xBF3504F3, 0xBF54DB31, 0xBF6C835E, 0xBF7B14BE,
    0xBF800000, 0xBF7B14BE, 0xBF6C835E, 0xBF54DB31,
    0xBF3504F3, 0xBF0E39DA, 0xBEC3EF15, 0xBE47C5C2,
]
MOVEMENT_Y_FLOAT32_BITS = [
    0xBF800000, 0xBF7B14BE, 0xBF6C835E, 0xBF54DB31,
    0xBF3504F3, 0xBF0E39DA, 0xBEC3EF15, 0xBE47C5C2,
    0x00000000, 0x3E47C5C2, 0x3EC3EF15, 0x3F0E39DA,
    0x3F3504F3, 0x3F54DB31, 0x3F6C835E, 0x3F7B14BE,
    0x3F800000, 0x3F7B14BE, 0x3F7B14BE, 0x3F6C835E,
    0x3F54DB31, 0x3F3504F3, 0x3F0E39DA, 0x3EC3EF15,
    0x3E47C5C2, 0x00000000, 0xBE47C5C2, 0xBEC3EF15,
    0xBF0E39DA, 0xBF3504F3, 0xBF54DB31, 0xBF6C835E,
]
MOVEMENT_X_Q16 = [
    0, 12785, 25080, 36410, 46341, 54491, 60547, 64277,
    65536, 64277, 60547, 54491, 46341, 36410, 25080, 12785,
    0, -12785, -25080, -36410, -46341, -54491, -60547, -64277,
    -65536, -64277, -60547, -54491, -46341, -36410, -25080, -12785,
]
MOVEMENT_Y_Q16 = [
    -65536, -64277, -60547, -54491, -46341, -36410, -25080, -12785,
    0, 12785, 25080, 36410, 46341, 54491, 60547, 64277,
    65536, 64277, 64277, 60547, 54491, 46341, 36410, 25080,
    12785, 0, -12785, -25080, -36410, -46341, -54491, -60547,
]


def _manual_ref(lines: list[str], line_number: int, required: str) -> dict[str, Any]:
    if line_number > len(lines):
        raise OrdnanceContractError(f"manual is missing line {line_number}")
    line = lines[line_number - 1].strip()
    if required not in line:
        raise OrdnanceContractError(
            f"manual line {line_number} no longer contains {required!r}"
        )
    return {"line": line_number, "sha256": _sha256(line.encode("utf-8"))}


def _verify_source(image: PEImage, manual_path: Path) -> tuple[dict[str, Any], list[str]]:
    if image.sha256 != EXECUTABLE_SHA256:
        raise OrdnanceContractError(
            f"unexpected warblade.exe SHA-256 {image.sha256}; expected {EXECUTABLE_SHA256}"
        )

    code_regions: list[dict[str, Any]] = []
    for name, va, size, expected_hash in CODE_REGIONS:
        actual_hash = _sha256(image.bytes_at(va, size))
        if actual_hash != expected_hash:
            raise OrdnanceContractError(
                f"{name} code bytes at {_hex(va)} do not match the pinned trace"
            )
        code_regions.append(
            {"id": name, "va": _hex(va), "size": size, "sha256": expected_hash}
        )

    strings: dict[str, dict[str, Any]] = {}
    for name, (va, required, prefix_only) in EXECUTABLE_STRINGS.items():
        actual = image.c_string(va)
        valid = actual.startswith(required) if prefix_only else actual == required
        if not valid:
            comparison = "prefix" if prefix_only else "value"
            raise OrdnanceContractError(
                f"{name} {comparison} mismatch at {_hex(va)}"
            )
        strings[name] = {
            "va": _hex(va),
            "sha256": _sha256(actual.encode("cp1252")),
        }

    manual_bytes = manual_path.read_bytes()
    manual_lines = manual_bytes.decode("cp1252").splitlines()
    manual_refs = {
        name: _manual_ref(manual_lines, line, required)
        for name, (line, required) in MANUAL_REFS.items()
    }
    source = {
        "executable": {
            "path": "Game/warblade.exe",
            "format": "PE32",
            "sha256": image.sha256,
        },
        "manual": {
            "path": "Game/Warblade_Manual_V1.34_Eng.txt",
            "encoding": "cp1252",
            "sha256": _sha256(manual_bytes),
            "references": manual_refs,
        },
        "code_regions": code_regions,
        "executable_strings": strings,
        "trace_method": "static_PE32_disassembly_and_dataflow_with_byte_pinned_regions",
        "gameplay_critical_unresolved": [],
        "exact_trace_complete": True,
    }
    return source, manual_lines


def _verify_tables_and_constants(image: PEImage) -> dict[str, Any]:
    state_classes = list(image.bytes_at(0x005ED204, 13))
    reservation_classes = list(image.bytes_at(0x005ED220, 13))
    expected_classes = [0, 2, 2, 0, 2, 0, 0, 1, 2, 2, 2, 2, 1]
    if state_classes != expected_classes or reservation_classes != expected_classes:
        raise OrdnanceContractError("missile target state-class tables drifted")
    weight_targets = [image.u32(0x005ED1F8 + index * 4) for index in range(3)]
    reservation_targets = [image.u32(0x005ED214 + index * 4) for index in range(3)]
    if weight_targets != [0x005EBDCA, 0x005EBEC7, 0x005EC0B9]:
        raise OrdnanceContractError("missile target weight jump table drifted")
    if reservation_targets != [0x005EC180, 0x005EC19C, 0x005EC1B8]:
        raise OrdnanceContractError("missile reservation jump table drifted")

    constants = {
        "targetability_max": image.f64(0x00778E48),
        "spawn_x_offset": image.f64(0x0077DA60),
        "spawn_y_offset": -image.f64(0x00778E18),
        "damage": image.f32(0x0077D830),
        "lifetime": image.f32(0x00782D44),
        "speed": image.f32(0x0077AD20),
        "effect_angle_max": image.f32(0x0077AD24),
        "effect_speed_max": image.f32(0x00779ADC),
        "boss_local_min": image.f32(0x0077B1C4),
        "boss_damage_divisor": image.f64(0x00779E98),
    }
    expected = {
        "targetability_max": 1.0,
        "spawn_x_offset": 9.0,
        "spawn_y_offset": -8.0,
        "damage": 200.0,
        "lifetime": 300.0,
        "speed": 10.0,
        "effect_angle_max": 359.0,
        "effect_speed_max": 5.0,
        "boss_local_min": 16.0,
        "boss_damage_divisor": 10.0,
    }
    if constants != expected:
        raise OrdnanceContractError(f"missile constants drifted: {constants!r}")
    return {
        "state_ids_6_through_18": list(range(6, 19)),
        "state_class_map": state_classes,
        "weight_jump_targets": [_hex(value) for value in weight_targets],
        "reservation_class_map": reservation_classes,
        "reservation_jump_targets": [_hex(value) for value in reservation_targets],
        "constants": constants,
    }


def _float32_from_word(word: int) -> float:
    return struct.unpack("<f", struct.pack("<I", word))[0]


def _nearest_q16(value: float) -> int:
    magnitude = int(abs(value) * 65536 + 0.5)
    return -magnitude if value < 0 else magnitude


def _verify_movement_tables(image: PEImage) -> dict[str, Any]:
    x_indexed_base = 0x007D0454
    y_indexed_base = 0x007D04D4
    x_words = [image.u32(x_indexed_base + heading * 4) for heading in range(1, 33)]
    y_words = [image.u32(y_indexed_base + heading * 4) for heading in range(1, 33)]
    if x_words != MOVEMENT_X_FLOAT32_BITS:
        raise OrdnanceContractError("missile X movement table drifted")
    if y_words != MOVEMENT_Y_FLOAT32_BITS:
        raise OrdnanceContractError("missile Y movement table drifted")

    x_values = [_float32_from_word(word) for word in x_words]
    y_values = [_float32_from_word(word) for word in y_words]
    x_q16 = [_nearest_q16(value) for value in x_values]
    y_q16 = [_nearest_q16(value) for value in y_values]
    if x_q16 != MOVEMENT_X_Q16 or y_q16 != MOVEMENT_Y_Q16:
        raise OrdnanceContractError("missile canonical Q16 movement projection drifted")

    x_raw = b"".join(struct.pack("<I", word) for word in x_words)
    y_raw = b"".join(struct.pack("<I", word) for word in y_words)
    return {
        "heading_domain": [1, 32],
        "index_expression": "table_base_plus_heading_times_4_without_subtracting_1",
        "float32_tables": {
            "x": {
                "indexed_base_va": _hex(x_indexed_base),
                "first_used_va": _hex(x_indexed_base + 4),
                "last_used_va": _hex(x_indexed_base + 32 * 4),
                "raw_sha256": _sha256(x_raw),
                "ieee754_words": [f"0x{word:08x}" for word in x_words],
                "values": x_values,
            },
            "y": {
                "indexed_base_va": _hex(y_indexed_base),
                "first_used_va": _hex(y_indexed_base + 4),
                "last_used_va": _hex(y_indexed_base + 32 * 4),
                "raw_sha256": _sha256(y_raw),
                "ieee754_words": [f"0x{word:08x}" for word in y_words],
                "values": y_values,
            },
        },
        "retail_float_operation": {
            "x": "float32_store(position_x + table_x[heading]*speed*DAT_00e11274_tick_scale)",
            "y": "float32_store(position_y + table_y[heading]*speed*DAT_00e11274_tick_scale)",
            "x_load_and_store_evidence": "0x00620844-0x00620887",
            "y_load_and_store_evidence": "0x0062088d-0x006208d0",
            "intermediate": "x87_extended_then_one_binary32_position_store_per_axis",
        },
        "canonical_q16_projection": {
            "fraction_bits": 16,
            "scale": 65536,
            "conversion": "nearest_integer(exact_decoded_binary32*65536);ties_away_from_zero",
            "ties_present": False,
            "x": x_q16,
            "y": y_q16,
            "vectors": [
                {"heading": heading, "x": x_q16[heading - 1], "y": y_q16[heading - 1]}
                for heading in range(1, 33)
            ],
            "speed_10_update": {
                "velocity_x_fp": "x_q16[heading-1]*10",
                "velocity_y_fp": "y_q16[heading-1]*10",
                "delta_x_fp": "trunc_toward_zero(velocity_x_fp*simulation_scale_numerator/6)",
                "delta_y_fp": "trunc_toward_zero(velocity_y_fp*simulation_scale_numerator/6)",
                "position": "add_each_delta_to_the_corresponding_Q16_position",
            },
        },
        "retail_y_table_irregularity": {
            "must_preserve": True,
            "duplicate": "headings_18_and_19_are_both_0x3f7b14be",
            "consequence": "do_not_replace_with_runtime_cos_or_a_symmetric_32_direction_table",
        },
    }


def _verify_assets() -> dict[str, Any]:
    verified: dict[str, Any] = {}
    for asset_id, specification in ASSETS.items():
        path = PROJECT_ROOT / specification["path"]
        data = path.read_bytes()
        if len(data) != specification["size"] or _sha256(data) != specification["sha256"]:
            raise OrdnanceContractError(f"{asset_id} asset bytes do not match evidence")
        verified[asset_id] = dict(specification)

    texture_data = (PROJECT_ROOT / ASSETS["texture"]["path"]).read_bytes()
    if len(texture_data) < 18:
        raise OrdnanceContractError("rocket.tga header is truncated")
    header = struct.unpack_from("<BBBHHBHHHHBB", texture_data)
    image_type, width, height, bits_per_pixel, descriptor = (
        header[2], header[8], header[9], header[10], header[11]
    )
    if (image_type, width, height, bits_per_pixel, descriptor) != (10, 768, 72, 32, 8):
        raise OrdnanceContractError("rocket.tga geometry or pixel format drifted")
    verified["texture"].update(
        {
            "image_type": "run_length_encoded_true_color",
            "dimensions": [width, height],
            "bits_per_pixel": bits_per_pixel,
            "descriptor": descriptor,
        }
    )

    mask_data = (PROJECT_ROOT / ASSETS["hit_mask"]["path"]).read_bytes()
    mask_domain = sorted(set(mask_data))
    if mask_domain != [0, 1] or len(mask_data) != width * height:
        raise OrdnanceContractError("rocket.hma dimensions or byte domain drifted")
    verified["hit_mask"].update(
        {
            "dimensions": [width, height],
            "byte_domain": mask_domain,
            "source_rect_authority": True,
        }
    )
    return verified


def build_document(
    exe_path: Path = DEFAULT_EXE,
    manual_path: Path = DEFAULT_MANUAL,
) -> dict[str, Any]:
    image = PEImage(exe_path)
    source, _manual_lines = _verify_source(image, manual_path)
    tables = _verify_tables_and_constants(image)
    movement_tables = _verify_movement_tables(image)
    assets = _verify_assets()

    return {
        "version": 1,
        "schema": "warblade.ordnance.v1",
        "source": source,
        "rocket_pack": {
            "id": "rocket_pack",
            "shop_item_id": 18,
            "unlock": {"comparison": ">=", "historical_threshold": 70},
            "price": 5000,
            "storage": {
                "kind": "signed_int32",
                "base": "DAT_00848b88",
                "player_stride_bytes": 1240,
                "owner_selector": "DAT_008f2044_shop_selected_physical_seat",
            },
            "purchase": {
                "pre_count_accepts": "<50",
                "pre_count_rejects": ">=50",
                "grant": 10,
                "capacity": 50,
                "accepted_result": "count=min(pre_count+10,50);subtract_price_once;success_notice_once",
                "rejected_result": "count_unchanged;cash_unchanged;shared_reject_feedback",
                "clamped_purchase_examples": {"40": 50, "41": 50, "49": 50},
                "evidence": "0x00562007-0x005620b6",
            },
            "lifecycle": {
                "new_player_initial_value": 0,
                "new_player_initializer": "0x00623cb0",
                "ordinary_death": "preserve_count",
                "level_and_warp_transition": "preserve_count",
                "saved_game_persistence": {
                    "scope": "both_physical_seats_in_full_live_snapshot",
                    "snapshot_base": "DAT_008486d8",
                    "snapshot_size_bytes": 694808,
                    "seat_0_relative_offset": "0x4b0",
                    "seat_1_relative_offset": "0x988",
                    "writer": "FUN_00537c80",
                    "loader": "FUN_005384f0",
                    "format": "zlib_1.2.1_compressed_svg_payload",
                },
                "consumption": "one_only_after_successful_missile_allocation_and_target_selection",
            },
        },
        "alien_lock": {
            "id": "alien_lock",
            "shop_item_id": 19,
            "unlock": {"comparison": ">=", "historical_threshold": 80},
            "price": 15000,
            "storage": {
                "kind": "uint8_boolean",
                "base": "DAT_00848b8c",
                "player_stride_bytes": 1240,
                "owner_selector": "DAT_008f2044_shop_selected_physical_seat",
            },
            "purchase": {
                "pre_value_accepts": 0,
                "pre_value_rejects": "nonzero",
                "accepted_result": "set_1;subtract_price_once;success_notice_once",
                "rejected_result": "value_unchanged;cash_unchanged;shared_reject_feedback",
                "evidence": "0x00561f92-0x00562002",
            },
            "meaning": {
                "preserves": [
                    {
                        "slot": "a",
                        "occupied_base": "DAT_00848824",
                        "enemy_index_base": "DAT_00848828",
                    },
                    {
                        "slot": "b",
                        "occupied_base": "DAT_0084882c",
                        "enemy_index_base": "DAT_00848830",
                    },
                ],
                "transition": "Warp and equivalent level-transition cleanup",
                "unlocked_transition_result": "clear_both_occupied_flags_for_transition_owner",
                "locked_transition_result": "preserve_occupied_flags_indices_and_captured_state_8_records",
                "captured_enemy_update": "read_captured_record_owner_and_preserve_departure_state_when_that_owner_lock_is_set",
                "retention_not_invulnerability": True,
                "missile_targeting_effect": "none",
                "evidence": "0x0055da8c-0x0055db34",
                "equivalent_cleanup_evidence": [
                    "0x00574f2a",
                    "0x00577d32",
                    "0x0057c2c1",
                    "0x005b0e2a",
                    "0x005b0e89",
                    "0x005b1345",
                    "0x005b13a4",
                    "0x005e4c7a",
                    "0x005feba9",
                    "0x005ff25a",
                    "0x005ff8db",
                ],
            },
            "lifecycle": {
                "new_player_initial_value": 0,
                "new_player_initializer": "0x00623ca0",
                "saved_game_persistence": {
                    "scope": "both_physical_seats_in_full_live_snapshot",
                    "snapshot_base": "DAT_008486d8",
                    "snapshot_size_bytes": 694808,
                    "seat_0_relative_offset": "0x4b4",
                    "seat_1_relative_offset": "0x98c",
                    "load_reconstruction": "if_lock_0_clear_owner_occupied_flags_else_reconstruct_both_captured_enemy_resources_from_saved_indices",
                    "writer": "FUN_00537c80",
                    "loader": "FUN_005384f0",
                },
                "ordinary_death": "clear_to_0_for_all_currently_supported_match_modes",
                "ordinary_death_evidence": "0x005719d8",
                "retail_mode_6_exception": {
                    "identity": "time_trial_match_mode",
                    "identity_evidence": "0x0059c8a7-0x0059c91d",
                    "reset_behavior": "skip_entire_FUN_00571990_loadout_reset",
                    "is_phase": False,
                    "maps_to_current_remake_phase": False,
                    "implementation_status": "implemented_match_mode",
                    "supported_policy": "do_not_apply_exception_to_level_warp_or_warp_malfunction_phases",
                },
                "warp": "preserve_lock_itself;apply_lock_to_captive_cleanup",
                "per_level_initialization": "preserve_lock_and_captive_ownership",
            },
            "duel": {
                "mode_id": 2,
                "ownership": "test_and_apply_each_physical_seat_independently",
                "player_0_storage": "base",
                "player_1_storage": "base+1240",
            },
        },
        "missile_runtime": {
            "id": "retail_player_rocket_v1",
            "input": {
                "action": "secondary_fire",
                "query_evidence": "0x005ebb6e-0x005ebb7e",
                "dispatch": "per_seat_control_mode_to_keyboard_binding_or_joystick_mask",
                "suppressed_game_modes": [9, 10, 11, 17, 20],
                "suppression_evidence": "0x005ebb84-0x005ebbbf",
                "requires_player_control_block": {
                    "base": "DAT_00848848",
                    "required_value": 0,
                    "player_stride_bytes": 1240,
                },
                "edge_latch": {
                    "base": "DAT_00848998",
                    "player_stride_bytes": 1240,
                    "release_sets": 1,
                    "armed_press_clears": 0,
                    "press_consumed_before_pool_and_target_scan": True,
                    "failed_press_requires_release_before_retry": True,
                },
                "requires_ammo": ">0",
                "dispatch_order": [
                    "query_secondary_for_active_physical_seat",
                    "if_released_set_edge_latch_1_and_stop",
                    "reject_suppressed_mode_or_nonzero_player_control_block",
                    "reject_unarmed_latch_or_zero_ammo",
                    "clear_edge_latch_before_pool_scan",
                    "scan_pool_then_targets_then_commit_successful_spawn",
                ],
            },
            "pool": {
                "kind": "shared_physical_player_projectile_pool",
                "base_active_field": "DAT_00d5e358",
                "capacity": 100,
                "record_stride_bytes": 160,
                "allocation": "ascending_first_inactive_slot",
                "pool_full": "no_target_scan;no_rng;no_ammo_decrement;no_sound",
                "ordinary_live_projectile_capacity_counter": "not_checked_or_incremented",
                "stale_counter_contribution_quirk": {
                    "field_offset": 40,
                    "spawn_write": "none_retain_free_slot_bytes",
                    "confirmed_collision_teardown": "subtract_stale_value_from_ordinary_live_count_then_clamp_nonnegative",
                    "lifetime_expiry_teardown": "no_ordinary_live_count_adjustment",
                },
            },
            "targeting": {
                "enemy_world": {
                    "normal": "active_physical_player_world",
                    "duel_mode_2": 0,
                    "duel_owner_remains": "active_physical_seat",
                },
                "record_base": "DAT_00849a4c",
                "enemy_world_stride_bytes": 140400,
                "record_stride_bytes": 936,
                "scan_count": 150,
                "candidate_buffer_capacity": 500,
                "eligibility": [
                    "active!=0",
                    "targetability_scalar_at_offset_0x88<=1.0_and_ordered",
                    "state!=8",
                    "state!=5",
                    "reservation_byte_at_offset_0x398==0",
                ],
                "weights": {
                    "8": [6, 9, 11, 12],
                    "16": [13, 18],
                    "1": [7, 8, 10, 14, 15, 16, 17],
                    "default": 1,
                    "note": "state_8_is_encoded_but_rejected_by_the_earlier_filter",
                },
                "selection": "one_RngInt(0,total_weight)_over_duplicated_candidates",
                "no_candidate": "no_rng;no_ammo_decrement;no_sound",
                "stored_target_field_offset": 92,
                "reservation": {
                    "set_1_states": [6, 7, 8, 9, 10, 11, 12, 14, 15, 16, 17],
                    "leave_or_set_0_states": [13, 18],
                    "clear_on_confirmed_collision_or_expiry": True,
                },
                "alien_lock_on_off_equivalence": "identical_candidates_weights_rng_and_reservation",
                "executable_tables": tables,
                "evidence": "0x005ebccf-0x005ec1d1",
            },
            "spawn": {
                "preconditions": ["armed_press", "ammo>0", "free_pool_slot", "target_selected"],
                "mutation_order": [
                    "set_global_plus_500ms_timer",
                    "set_global_timer_active",
                    "set_any_player_projectile_allocated_flag",
                    "decrement_firing_seat_rocket_count_by_1",
                    "increment_firing_seat_rocket_fire_counter_by_1",
                    "activate_and_initialize_pool_record",
                    "RngInt(0,3)+4_animation_period",
                    "RngInt(0,3)+3_animation_countdown",
                    "play_rocket_sound",
                ],
                "rng_order_after_weighted_target_draw": [
                    {"call": "RngInt", "arguments": [0, 3], "add": 4, "field": "animation_period", "result_range": [4, 6]},
                    {"call": "RngInt", "arguments": [0, 3], "add": 3, "field": "animation_countdown", "result_range": [3, 5]},
                ],
                "record": {
                    "asset_binding_offsets_before_active": [-32, -28, -24, -20],
                    "source_rect_offsets_before_active": [-16, -12, -8, -4],
                    "active_offset_0x00": 1,
                    "owner_offset_0x08": "active_physical_seat",
                    "damage_offset_0x14": 200.0,
                    "kind_offset_0x18": 200,
                    "persistent_offset_0x2c": 0,
                    "offset_x_0x30": 0,
                    "offset_y_0x34": 0,
                    "width_0x38": 24,
                    "height_0x3c": 24,
                    "x_0x40": "player_origin_x+9.0",
                    "y_0x44": "player_origin_y-8.0",
                    "speed_0x54": 10.0,
                    "heading_0x58": 1,
                    "target_0x5c": "selected_enemy_index_active_world_relative",
                    "lifetime_0x60": 300.0,
                    "animation_row_0x64": 0,
                    "animation_period_0x68": "RngInt(0,3)+4",
                    "animation_countdown_0x6c": "RngInt(0,3)+3",
                    "steering_period_0x70": 1,
                    "steering_countdown_0x74": 1,
                    "scale_x_0x78": 1.0,
                    "scale_y_0x7c": 1.0,
                },
                "failure_atomicity": "pool_full_or_no_target_changes_no_ammo_counters_sound_or_rng_beyond_any_completed_prior_stage",
                "evidence": "0x005ec1d2-0x005ec525",
            },
            "update": {
                "function": "FUN_0061fff0",
                "lifetime": {
                    "step": "subtract_tick_scale",
                    "expire_when": "updated_value<=0",
                    "expiry_order": ["clear_stored_target_reservation", "capture_position", "deactivate", "expiry_sound", "flare_effect"],
                },
                "inactive_stored_target": {
                    "replacement": "ascending_first_currently_eligible_enemy",
                    "weighted": False,
                    "rng": False,
                    "stored_target_overwrite": False,
                    "replacement_reservation": False,
                    "none_found": "skip_steering_and_continue_current_heading",
                },
                "animation": {
                    "enabled_when": "retail_game_mode!=0",
                    "step": "subtract_tick_scale",
                    "advance_when": "predecrement_countdown==0",
                    "frames": [0, 1, 2],
                    "wrap": "2_to_0",
                    "reset_countdown_to": "animation_period",
                },
                "steering": {
                    "countdown": "postdecrement<=0_then_reset_to_period_1",
                    "target_point": "enemy_position_fields_0x04_0x08",
                    "quadrant_desired_headings": [5, 13, 21, 29],
                    "heading_domain": [1, 32],
                    "turn": "one_step_shortest_circular_direction",
                    "exact_tie": "RngInt(0,100)<50_decrement_else_increment",
                    "movement": movement_tables,
                },
                "root_rng_expiry_effect_order": [
                    "RngInt(35000,44100)_explo1_frequency",
                    "RngInt(0,50)+128",
                    "RngInt(0,50)+128",
                    "RngFloat(0,359)",
                    "RngFloat(0,5)",
                ],
                "evidence": "0x00620090-0x006208d6",
            },
            "rendering": {
                "texture": "rocket.tga",
                "hit_mask": "rocket.hma",
                "atlas": {"dimensions": [768, 72], "frame_size": [24, 24], "headings": 32, "animation_rows": 3},
                "source_rect": "[(heading-1)*24,animation_row*24,24,24]",
                "runtime_rotation": False,
                "renderer_writes_source_rect_to_pool_record": True,
                "headless_requirement": "derive_identical_source_rect_before_collision",
                "cosmetic_rng": "shares_root_rng;preserve_FUN_006211e0_draw_order_for_selected_effect_preset",
                "evidence": "0x0062124e-0x006215ea",
            },
            "collision": {
                "ordinary_enemy": {
                    "broadphase": "projectile_enemy_AABB",
                    "narrowphase": "rocket_hma_against_enemy_hma_using_current_source_rect",
                    "damage": 200.0,
                    "retail_outcome": "destroys_normal_targets_because_authored_normal_health_is_at_most_200",
                    "evidence": "0x00587245-0x00587487",
                },
                "state_13_boss": {
                    "strict_local_bounds": [16, 16, 240, 112],
                    "hma_damage_test": False,
                    "damage_formula": "max(1,projectile_damage/10)",
                    "rocket_damage": 20,
                    "boss_pipeline_owner": "retail_big_boss_v1",
                    "evidence": "0x00585a65-0x00586d1f",
                },
                "confirmed_hit_common_order": [
                    "subtract_damage",
                    "deactivate_nonpersistent_missile",
                    "clear_stored_target_reservation",
                    "increment_owner_shared_successful_hit_numerator",
                    "increment_global_successful_hit_counter",
                ],
                "missile_persistent_flag": 0,
            },
            "audio_and_effects": {
                "fire": {"sample": "rocket", "frequency": 32000, "volume": 255, "pan_source": "missile_x", "rng": False, "once": True},
                "expiry": {"sample": "explo1", "frequency_rng": [35000, 44100], "effect_texture": "flare4.tga"},
                "distance_ping_manual_semantics": True,
                "root_rng_authority": True,
            },
        },
        "integration": {
            "frame_order": {
                "authoritative_gameplay": [
                    "player_projectile_enemy_collision",
                    "missile_update",
                ],
                "collision_before_update": True,
                "retail_source_rect": "written_by_the_prior_render_from_heading_and_animation_row",
                "headless_source_rect": "derive_the_same_rect_from_current_pre_update_state_before_collision",
            },
            "ownership": {
                "player_stride_bytes": 1240,
                "shop_owner": "DAT_008f2044",
                "active_gameplay_owner": "DAT_008f2040",
                "ammo_latch_projectile_owner_and_stats": "physical_seat_scoped",
                "duel_mode_2_enemy_world": 0,
                "duel_projectile_owner": "firing_physical_seat",
            },
            "accuracy": {
                "ordinary_projectile_denominator": "DAT_00848748_per_seat",
                "missile_fire_counter": "DAT_00848870_per_seat",
                "shared_successful_hit_numerator": "DAT_0084874c_per_seat",
                "successful_missile_spawn": "increment_missile_fire_counter_only_not_ordinary_denominator",
                "confirmed_missile_hit": "increment_shared_successful_hit_numerator",
                "retail_percentage": "floor(100*shared_hits/ordinary_projectile_denominator)_then_clamp_100",
                "consequence": "rocket_hits_can_raise_the_displayed_or_profile_percentage_but_never_above_100",
                "profile_sample": {
                    "condition": "per_seat_level>25",
                    "level_25_end_creates_sample": False,
                    "update": "monotonic_max",
                    "duel": "submit_each_physical_seat_independently_to_active_profile_max",
                },
                "new_player_initialization": "zero_ordinary_denominator_shared_hits_and_missile_fire_counter",
                "per_level_initialization": "preserve_cumulative_ordinary_denominator_and_shared_hits;clear_per_seat_missile_fire_counter",
                "evidence": "0x005df8a8-0x005df8ba/0x005ec218-0x005ec238/0x00568fff-0x00569054",
            },
            "final_kill_reward": {
                "qualification": "any_player_projectile_allocated_flag==0_and_any_alien_projectile_processed_flag!=0",
                "player_projectile_flag": {
                    "name": "any_player_projectile_allocated",
                    "storage": "DAT_00e11346",
                    "reset": "0x005694a0",
                    "set_by_generic_primary_allocation": "0x005df855",
                    "set_by_successful_missile_allocation": "0x005ec1eb",
                    "not_rocket_only": True,
                    "failed_secondary_press_sets": False,
                },
                "alien_projectile_flag": {
                    "name": "any_alien_or_common_projectile_processed",
                    "storage": "DAT_00e11347",
                    "reset": "0x005694a7",
                    "set": "0x00601d79",
                },
                "reward": {
                    "if_rocket_count_below_50": "add_10_then_clamp_50_and_show_10_ROCKETS_ADDED_for_1500ms",
                    "if_rocket_count_at_least_50": "add_50000_times_score_multiplier",
                },
                "evidence": "0x00555d08-0x00556075/0x005562b2-0x00556353",
            },
            "boss_interaction": {
                "state": 13,
                "ordnance_scope": "collision_damage_and_common_missile_teardown_only",
                "authoritative_controller": "retail_big_boss_v1",
                "must_not_duplicate": ["boss_health_terminal_rule", "boss_death_sequence", "boss_rewards", "boss_completion_routing"],
            },
            "determinism": {
                "rng": "single_match_root_rng",
                "successful_spawn_draws_after_target": 2,
                "failure_draw_policy": "draw_only_the_stages_reached_by_retail_control_flow",
                "effects": "synchronous_and_ordered_with_gameplay_on_the_same_root_rng",
            },
            "fail_closed": {
                "requires_exact_trace_complete": True,
                "requires_assets_and_hma": True,
                "requires_boss_contract_for_state_13": True,
                "forbid_unresolved_gameplay_fields": True,
            },
            "exact_trace_complete": True,
        },
        "assets": assets,
    }


def _json_text(document: dict[str, Any]) -> str:
    return json.dumps(document, indent=2, ensure_ascii=False) + "\n"


def _evidence_text(document: dict[str, Any]) -> str:
    artifact_hash = _sha256(_json_text(document).encode("utf-8"))
    source = document["source"]
    movement = document["missile_runtime"]["update"]["steering"]["movement"]
    x_table = movement["float32_tables"]["x"]
    y_table = movement["float32_tables"]["y"]
    vectors = movement["canonical_q16_projection"]["vectors"]
    return "\n".join(
        [
            "# Rocket Pack and Alien Lock runtime trace",
            "",
            f"- Contract schema: `{document['schema']}`",
            f"- Executable SHA-256: `{source['executable']['sha256']}`",
            f"- Generated `ordnance.json` SHA-256: `{artifact_hash}`",
            "- Trace status: exact and complete; the gameplay-critical closure list is empty.",
            "",
            "## Retail contract corrections",
            "",
            "- Rocket Pack adds 10 and clamps at 50. A pre-purchase count of 50 or more rejects without charging; counts 41 through 49 still pay and clamp to 50.",
            "- Alien Lock preserves the owning seat's two captured-alien slots (occupied flags, saved indices, and state-8 records) through Warp. It has no homing, weighting, reservation, or RNG effect on rockets. Ordinary death consumes the lock but preserves rocket inventory in every supported remake match mode.",
            "- Retail match mode 6 is Time Trial (`0x0059c8a7-0x0059c91d`), not a gameplay phase. It skips the entire death-loadout reset. Time Trial is a separate product program, so this exception must not be applied to current level, Warp, or Warp Malfunction phases.",
            "- Secondary fire is release-armed. A pool-full or targetless press costs no rocket, makes no sound, and requires release before retry.",
            "- Rockets share the 100-record physical player projectile pool. Successful spawn consumes one rocket, uses one weighted target draw followed by the two animation draws, and records the firing physical seat as owner.",
            "- A rocket deals 200 to ordinary enemies. State 13 uses strict local boss bounds, no HMA damage test, and `max(1, damage/10)`, so a rocket deals 20 before the boss controller owns terminal behavior.",
            "- `DAT_00e11346` is an any-player-projectile-allocation flag, not a rocket-fired flag. Both successful primary and missile allocations disqualify the alien-projectile final-kill reward.",
            "- Missile fire increments a separate rocket counter, not the ordinary-shot denominator. Confirmed missile hits do increment the shared hit numerator; retail clamps the computed percentage to 100.",
            "",
            "## Byte-pinned executable regions",
            "",
            "| Role | Virtual address | Bytes | SHA-256 |",
            "|---|---:|---:|---|",
            *[
                f"| {region['id'].replace('_', ' ')} | `{region['va']}` | {region['size']} | `{region['sha256']}` |"
                for region in source["code_regions"]
            ],
            "",
            "## Runtime ordering",
            "",
            "The weighted scan admits active, unreserved records whose targetability scalar is at most 1, excluding states 5 and 8. States 6, 9, 11, and 12 have weight 8; states 13 and 18 have weight 16; all remaining admitted states have weight 1. State 13 and 18 targets are deliberately not reserved. Alien Lock on and off traverse identical candidates and consume identical RNG.",
            "",
            "After the target draw, spawn consumes `RngInt(0,3)+4` for animation period and `RngInt(0,3)+3` for its initial countdown. Expiry consumes the explosion-frequency draw before flare draws. Steering consumes RNG only for an exact circular-direction tie. Cosmetic effects remain synchronous users of the root match RNG.",
            "",
            "## Missile movement tables",
            "",
            f"The X lookup uses indexed base `{x_table['indexed_base_va']}` and bytes `{x_table['first_used_va']}..{x_table['last_used_va']}` (SHA-256 `{x_table['raw_sha256']}`). The Y lookup uses indexed base `{y_table['indexed_base_va']}` and bytes `{y_table['first_used_va']}..{y_table['last_used_va']}` (SHA-256 `{y_table['raw_sha256']}`). The heading itself, 1 through 32, is multiplied by four and added to each base; there is no heading-minus-one adjustment in the executable load.",
            "",
            "| Heading | X binary32 | Y binary32 | X Q16 | Y Q16 |",
            "|---:|---:|---:|---:|---:|",
            *[
                f"| {vector['heading']} | `{x_table['ieee754_words'][vector['heading'] - 1]}` | `{y_table['ieee754_words'][vector['heading'] - 1]}` | {vector['x']} | {vector['y']} |"
                for vector in vectors
            ],
            "",
            "The Q16 projection decodes the pinned binary32 word, multiplies by 65536, and rounds to the nearest integer (ties away from zero; no table entry is tied). At retail speed 10, multiply the selected Q16 component by 10, then apply the existing `simulation_scale_numerator / 6` with truncation toward zero before adding it to the position.",
            "",
            "The retail Y table is intentionally not normalized: headings 18 and 19 both contain `0x3f7b14be`. This shifts the remaining second-half values, so a host `sin`/`cos` call or symmetric direction-table derivation is gameplay-incompatible.",
            "",
            "The checked JSON is authoritative for field offsets, lifecycle, per-seat and Duel ownership, HMA-backed 32-by-3 atlas rendering, collision teardown, the stale counter-contribution quirk, final-kill qualification, and accuracy accounting. Runtime loading must fail closed if the trace gate, required rocket assets, HMA domain, or state-13 boss contract is absent.",
            "",
        ]
    )


def _check_or_write(path: Path, text: str, check: bool) -> None:
    if check:
        if not path.is_file() or path.read_text(encoding="utf-8") != text:
            raise OrdnanceContractError(f"{path} is stale; regenerate ordnance contract")
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Generate the exact retail Rocket Pack and Alien Lock contract."
    )
    parser.add_argument("--exe", type=Path, default=DEFAULT_EXE)
    parser.add_argument("--manual", type=Path, default=DEFAULT_MANUAL)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--evidence", type=Path, default=DEFAULT_EVIDENCE)
    parser.add_argument("--check", action="store_true")
    return parser


def main() -> int:
    args = _build_parser().parse_args()
    try:
        document = build_document(args.exe, args.manual)
        _check_or_write(args.output, _json_text(document), args.check)
        _check_or_write(args.evidence, _evidence_text(document), args.check)
    except (OrdnanceContractError, OSError, UnicodeDecodeError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    if args.check:
        print("ordnance contract and evidence are current")
    else:
        print("generated exact retail Rocket Pack and Alien Lock contract and evidence")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
