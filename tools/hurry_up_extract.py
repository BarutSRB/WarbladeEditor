#!/usr/bin/env python3
"""Extract the retail hurry-up secret-ship contract from warblade.exe.

Retail arms a per-player hurry-up deadline from the difficulty timed-effect
interval (``0x008f2090``). When ordinary play runs past that deadline the
spawner ``FUN_0058e350`` drops a "H U R R Y   U P" banner, plays one of the two
hurry-up voice clips, re-randomises the parallax planet row, and creates a
mothership (behavior state 9). Every eighth spawn additionally creates the
money ship (behavior state 0xc). Killing either records a found-secret id into
the profile: 3 for the mothership, 6 for the money ship.

Everything emitted here is pinned to exact retail instruction bytes. Two
further secret ships share the same death dispatcher but have their own
spawners and are reported as evidence only: the money sucker (state 0xb,
``FUN_00581250``) and the guard ship (state 0x12, ``FUN_00581990``).
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

# float32 constants consumed by the spawner, motion handlers, and hitboxes.
F32_CONSTANTS: tuple[tuple[int, str, float], ...] = (
    (0x00779BB4, "mothership_spawn_y", 20.0),
    (0x00778E7C, "special_speed_minimum", 2.0),
    (0x00778E80, "mothership_animation_interval_maximum", 4.0),
    (0x00779B68, "mothership_frame_last", 19.0),
    (0x0077DC40, "mothership_hitbox_height", 57.0),
    (0x0077DC58, "mothership_hitbox_width", 96.0),
    (0x0077D834, "rare_spawn_y", -110.0),
    (0x0077ADA4, "rare_animation_interval", 3.0),
    (0x0077D7D8, "rare_speed_scalar_minimum", 0.800000011920929),
    (0x0077DB08, "rare_hitbox_extent", 100.0),
    (0x00779C80, "rare_heading_step_range", 8.0),
    (0x0077B0E4, "rare_turn_countdown_range", 160.0),
    (0x0077D804, "rare_turn_countdown_default", 30.0),
    (0x0078688C, "rare_wrap_target_low", -120.0),
)

# float64 constants consumed by the same code paths.
F64_CONSTANTS: tuple[tuple[int, str, float], ...] = (
    (0x0077B220, "rare_turn_countdown_base", 50.0),
    (0x00779B78, "rare_heading_step_base", 3.0),
    (0x00782E50, "rare_turn_countdown_offset", 40.0),
    (0x00782DC0, "rare_steer_lower_edge", 180.0),
    (0x00786858, "rare_steer_upper_edge", 80.0),
    (0x00786880, "rare_wrap_threshold_low", -120.0),
    (0x00778DE8, "rare_animation_health_divisor", 5.0),
    (0x00779BA0, "rare_animation_divisor", 4.0),
    (0x00778E48, "one", 1.0),
    (0x0077AD58, "mothership_frame_count", 20.0),
    (0x0077DC48, "rare_hitbox_offset", 14.0),
    (0x00786848, "mothership_left_despawn", -70.0),
)

# int32 constants.
I32_CONSTANTS: tuple[tuple[int, str, int], ...] = (
    (0x007D32F8, "surface_width", 800),
    (0x007D32FC, "surface_height", 600),
    (0x007CD100, "score_table_multiplier", 7),
)

# Instruction pins: (va, expected bytes, label). Each pin anchors one claim.
INSTRUCTION_PINS: tuple[tuple[int, bytes, str], ...] = (
    # Deadline arming (FUN_00552440) and the per-mode getter (FUN_00552680).
    (0x0055248E, bytes.fromhex("8b0d90208f0089888c898400"), "arm_interval_store"),
    (
        0x005524A5,
        bytes.fromhex("8b0dbc27ab0003888c8984008b1540208f0069d2d8040000"),
        "arm_deadline_store",
    ),
    (0x0055268C, bytes.fromhex("8dbd30ffffffb934000000"), "deadline_getter_default"),
    # Spawner guards (FUN_0058e350).
    (
        0x0058E386,
        bytes.fromhex("e832a0f9ff3905bc27ab000f86ed0d0000"),
        "spawn_guard_deadline",
    ),
    (0x0058E3A2, bytes.fromhex("83b82889840000"), "spawn_guard_level_complete"),
    (0x0058E3AF, bytes.fromhex("833d205ca90004"), "spawn_guard_phase_four"),
    (0x0058E3BC, bytes.fromhex("833dd8208f0006"), "spawn_guard_time_trial"),
    (0x0058E3C9, bytes.fromhex("833d205ca90003"), "spawn_guard_phase_three"),
    (0x0058E3E8, bytes.fromhex("817df896000000"), "spawn_slot_scan_limit"),
    # Entry-side coin flip and entry X.
    (0x0058E415, bytes.fromhex("6a646a00e8bfb1f9ff83c40883f832"), "spawn_entry_coin_draw"),
    (0x0058E438, bytes.fromhex("c78408149b840001000000"), "spawn_entry_right_flag"),
    (0x0058E443, bytes.fromhex("a1f8327d00"), "spawn_entry_right_x_source"),
    (0x0058E4AF, bytes.fromhex("c78408149b840000000000"), "spawn_entry_left_flag"),
    (0x0058E4BA, bytes.fromhex("db05e863d500d9eedee1"), "spawn_entry_left_x_negate"),
    # Banner and parallax-planet rejig.
    (0x0058E609, bytes.fromhex("c705f82b800000000000"), "spawn_banner_clear"),
    (0x0058E613, bytes.fromhex("a1bc27ab0005e8030000a3d414e100"), "spawn_banner_deadline"),
    (0x0058E637, bytes.fromhex("3b051ce97c00"), "spawn_planet_rejig_bound"),
    (0x0058E65A, bytes.fromhex("89048d886bd500"), "spawn_planet_x_store"),
    (
        0x0058E670,
        bytes.fromhex("833d1ce97c00087e0ac7051ce97c0008"),
        "spawn_planet_count_cap",
    ),
    # Mothership fields.
    (
        0x0058E684,
        bytes.fromhex("d90574208f00d91c2451d9057c8e7700"),
        "spawn_mothership_speed_draw",
    ),
    (0x0058E6E7, bytes.fromhex("d905b49b7700"), "spawn_mothership_y_source"),
    (
        0x0058E6F5,
        bytes.fromhex("d905808e7700d91c2451d9057c8e7700"),
        "spawn_mothership_anim_draw",
    ),
    (0x0058E812, bytes.fromhex("a1e81de10050"), "spawn_mothership_score_read"),
    (0x0058E843, bytes.fromhex("e89882f9ff03056c208f00"), "spawn_mothership_health_base"),
    (0x0058E89F, bytes.fromhex("c78408f49a840009000000"), "spawn_mothership_state"),
    # Rare-ship cadence and fields.
    (0x0058E926, bytes.fromhex("83b86488840008"), "spawn_rare_counter_period"),
    (0x0058EA81, bytes.fromhex("a1c01de10050"), "spawn_rare_score_read"),
    (
        0x0058EAC9,
        bytes.fromhex("a1f8327d002dc8000000d1f8506a00e800abf9ff83c40883c064"),
        "spawn_rare_x_draw",
    ),
    (0x0058EB1A, bytes.fromhex("d90534d87700"), "spawn_rare_y_source"),
    (0x0058EB8A, bytes.fromhex("c78408f49a84000c000000"), "spawn_rare_state"),
    (0x0058EBC6, bytes.fromhex("c78408149b840002000000"), "spawn_rare_turn_mode"),
    (0x0058EBD1, bytes.fromhex("6a056a00e803aaf9ff83c40883c012"), "spawn_rare_heading_draw"),
    (0x0058EBFF, bytes.fromhex("e8dc7ef9ff03057c208f00"), "spawn_rare_health_base"),
    (
        0x0058EC65,
        bytes.fromhex("d90508db7700d91c2451d9eed91c24e8aaa9f9ff83c408dc0520b27700"),
        "spawn_rare_turn_countdown_draw",
    ),
    (0x0058EEDF, bytes.fromhex("c784085c9c840009000000"), "spawn_rare_frame_max"),
    # Spawner tail: 10s re-arm and the floored global decrement.
    (0x0058F048, bytes.fromhex("c7808c89840010270000"), "spawn_interval_reset"),
    (0x0058F07B, bytes.fromhex("a12c208f0083e808"), "spawn_global_decrement"),
    (0x0058F088, bytes.fromhex("833d2c208f00287d0ac7052c208f0028"), "spawn_global_floor"),
    # Motion handlers (FUN_00605fe0).
    (
        0x00610B67,
        bytes.fromhex("a140208f0069c0d804000083b8ec87840000"),
        "motion_mothership_level_complete_gate",
    ),
    (0x00610BD4, bytes.fromhex("3b051ce97c00"), "motion_mothership_planet_bound"),
    (
        0x00611243,
        bytes.fromhex("d98432809a8400d80d7412e100d88408509a8400"),
        "motion_mothership_advance",
    ),
    (0x00611287, bytes.fromhex("8b15f8327d0083c246"), "motion_mothership_right_bound"),
    (
        0x006117CB,
        bytes.fromhex("d98408409b8400dc1d58ad7700"),
        "motion_mothership_frame_ceiling",
    ),
    (
        0x00611732,
        bytes.fromhex("d905689b7700d99c08409b8400"),
        "motion_mothership_frame_wrap_back",
    ),
    (0x0060FD67, bytes.fromhex("d80cbd58057d00"), "motion_rare_heading_table_x"),
    (0x0060FDFF, bytes.fromhex("d80cbdf8057d00"), "motion_rare_heading_table_y"),
    # Collision boxes (FUN_00585840).
    (
        0x0058716E,
        bytes.fromhex("d90540dc7700d99df8feffffd90558dc7700"),
        "hitbox_mothership",
    ),
    (0x005870D9, bytes.fromhex("dc0548dc7700d99d64ffffff"), "hitbox_rare_offset"),
    (0x0058710D, bytes.fromhex("d90508db7700d99df8feffff"), "hitbox_rare_extent"),
    # Death handling (FUN_00585840).
    (0x0058A771, bytes.fromhex("6a036a396a60"), "death_mothership_explosion_size"),
    (0x0058A8A2, bytes.fromhex("833dd8208f00007531"), "death_secret_requires_solo"),
    (0x0058A8C2, bytes.fromhex("c780ec898400010000006a03"), "death_mothership_secret_three"),
    (0x0058A47E, bytes.fromhex("6a0368800000006880000000"), "death_rare_explosion_size"),
    (0x0058A61D, bytes.fromhex("c780f8898400010000006a06"), "death_rare_secret_six"),
    # Score table initialisation (FUN_00775150).
    (0x0077542B, bytes.fromhex("6a0068c4090000"), "score_mothership_literal"),
    (0x0077537A, bytes.fromhex("6a0068a8610000"), "score_rare_literal"),
    # Shared effect pool: the planet-debris spawn and its steering.
    (0x00610DA0, bytes.fromhex("6a036a00e83488f1ff83c408"), "debris_animation_interval_draw"),
    (0x00610DCA, bytes.fromhex("6a036a00e80a88f1ff83c408"), "debris_animation_countdown_draw"),
    (0x00610DF4, bytes.fromhex("6a056a00e8e087f1ff83c408"), "debris_steering_reload_draw"),
    (0x00610E6B, bytes.fromhex("a128208f00506a00e86587f1ff"), "debris_lifetime_draw"),
    (0x00610E9C, bytes.fromhex("833dd8208f00020f85bd000000"), "debris_duel_owner_draw"),
    (
        0x00610FA1,
        bytes.fromhex("51d90534208f00d91c2451d90530208f00d91c24"),
        "debris_speed_draw",
    ),
    (
        0x006021A2,
        bytes.fromhex("b9650000002b887087840083c101516a00e8"),
        "debris_steering_range",
    ),
    (
        0x006021BD,
        bytes.fromhex("d90538208f00e81849f2ff3bf0"),
        "debris_steering_threshold_read",
    ),
    (0x006021D0, bytes.fromhex("6a646a00e80474f2ff83c40883f821"), "debris_wander_down"),
    (0x00602202, bytes.fromhex("6a646a00e8d273f2ff83c40883f842"), "debris_wander_up"),
    # Other secret ships that share the death dispatcher (evidence only).
    (0x00581711, bytes.fromhex("c78408f49a84000b000000"), "money_sucker_state"),
    (0x00581E37, bytes.fromhex("c78408f49a840012000000"), "guard_state"),
)

# The 40-entry heading tables the rare ship shares with supplemental state 6.
HEADING_TABLE_X_VA = 0x007D0558
HEADING_TABLE_Y_VA = 0x007D05F8
HEADING_TABLE_COUNT = 40


@dataclass(frozen=True)
class Section:
    name: str
    va: int
    virtual_size: int
    raw_offset: int
    raw_size: int


class PEImage:
    def __init__(self, path: Path):
        if not path.is_file():
            raise ValueError(
                f"missing retail executable: {path} "
                "(expected Game/warblade.exe inside the project root)"
            )
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
                    raise ValueError(f"{hex_va(va)} is uninitialized PE data")
                return offset
        raise ValueError(f"{hex_va(va)} is outside mapped PE sections")

    def bytes_at(self, va: int, size: int) -> bytes:
        offset = self.file_offset(va, size)
        return self.data[offset : offset + size]

    def f32(self, va: int) -> float:
        return struct.unpack("<f", self.bytes_at(va, 4))[0]

    def f64(self, va: int) -> float:
        return struct.unpack("<d", self.bytes_at(va, 8))[0]

    def i32(self, va: int) -> int:
        return struct.unpack("<i", self.bytes_at(va, 4))[0]

    def f32_table(self, va: int, count: int) -> list[float]:
        return list(struct.unpack(f"<{count}f", self.bytes_at(va, count * 4)))


def hex_va(value: int) -> str:
    return f"0x{value:08x}"


def _constants(image: PEImage) -> dict[str, Any]:
    constants: dict[str, Any] = {}
    for va, name, expected in F32_CONSTANTS:
        value = image.f32(va)
        constants[name] = {
            "va": hex_va(va),
            "width": "float32",
            "bytes_hex": image.bytes_at(va, 4).hex(),
            "value": value,
            "matches_documented_value": value == expected,
        }
    for va, name, expected_f64 in F64_CONSTANTS:
        value = image.f64(va)
        constants[name] = {
            "va": hex_va(va),
            "width": "float64",
            "bytes_hex": image.bytes_at(va, 8).hex(),
            "value": value,
            "matches_documented_value": value == expected_f64,
        }
    for va, name, expected_i32 in I32_CONSTANTS:
        value = image.i32(va)
        constants[name] = {
            "va": hex_va(va),
            "width": "int32",
            "bytes_hex": image.bytes_at(va, 4).hex(),
            "value": value,
            "matches_documented_value": value == expected_i32,
        }
    drifted = sorted(
        name
        for name, entry in constants.items()
        if not entry["matches_documented_value"]
    )
    if drifted:
        raise ValueError("constant values drifted at: " + ", ".join(drifted))
    return constants


def _instruction_pins(image: PEImage) -> dict[str, Any]:
    pins: dict[str, Any] = {}
    failures: list[str] = []
    for va, expected, label in INSTRUCTION_PINS:
        actual = image.bytes_at(va, len(expected))
        pins[label] = {
            "va": hex_va(va),
            "bytes_hex": actual.hex(),
            "matches_documented_bytes": actual == expected,
        }
        if actual != expected:
            failures.append(label)
    if failures:
        raise ValueError("executable bytes drifted at: " + ", ".join(sorted(failures)))
    return pins


def build_evidence(exe_path: Path) -> dict[str, Any]:
    image = PEImage(exe_path)
    if image.sha256 != WARBLADE_EXE_SHA256:
        raise ValueError(
            f"unexpected executable hash {image.sha256}; expected {WARBLADE_EXE_SHA256}"
        )

    constants = _constants(image)
    pins = _instruction_pins(image)
    heading_x = image.f32_table(HEADING_TABLE_X_VA, HEADING_TABLE_COUNT)
    heading_y = image.f32_table(HEADING_TABLE_Y_VA, HEADING_TABLE_COUNT)

    return {
        "schema": "warblade-hurry-up-v1",
        "source": {
            "path": str(exe_path),
            "sha256": image.sha256,
            "image_base": hex_va(image.image_base),
        },
        "confidence_scale": {
            "proven": (
                "The retail instruction bytes and their gameplay consumers are "
                "pinned by this extraction."
            ),
            "evidence_only": (
                "The exact value is preserved but its consumer is not closed here."
            ),
        },
        "deadline": {
            "confidence": "proven",
            "arming_va": "0x00552440",
            "getter_va": "0x00552680",
            "interval_source_global_va": "0x008f2090",
            "interval_by_difficulty_ms": {
                "easy": 50000,
                "normal": 40000,
                "hard": 30000,
                "ace": 20000,
            },
            "interval_field_va": "0x0084898c",
            "deadline_field_va": "0x00848854",
            "player_stride_bytes": 1240,
            "rule": "interval = difficulty timed-effect milliseconds; deadline = now + interval",
            "shared_slot_match_modes": [2],
            "post_spawn_interval_ms": 10000,
            "post_spawn_interval_va": "0x0058f048",
            "re_arm_events": [
                "spawner completes a hurry-up wave",
                "mothership leaves the surface",
                "mothership is destroyed",
            ],
        },
        "spawner": {
            "confidence": "proven",
            "va": "0x0058e350",
            "call_site_va": "0x005b1237",
            "call_order": [
                "FUN_00585840 collision and death dispatcher",
                "FUN_00581250 money-sucker spawner",
                "FUN_0058e350 hurry-up spawner",
                "FUN_00581990 guard spawner",
                "FUN_00605fe0 motion dispatcher",
            ],
            "guards": [
                {
                    "va": "0x0058e386",
                    "rule": "now <= deadline aborts before any random draw",
                },
                {
                    "va": "0x0058e3a2",
                    "rule": "the per-player level-complete flag 0x00848928 aborts",
                },
                {"va": "0x0058e3af", "rule": "screen state 0x00a95c20 == 4 aborts"},
                {"va": "0x0058e3bc", "rule": "match mode 6 (Time Trial) aborts"},
                {"va": "0x0058e3c9", "rule": "screen state 0x00a95c20 == 3 aborts"},
                {
                    "va": "0x0058e3e8",
                    "rule": "the 150-slot entity array must have a free slot",
                },
            ],
            "random_draw_order": [
                "RngInt(0, 100) entry-side coin: < 50 enters from the right",
                "RngInt(0, 2 or 1) hurry-up voice selection over the loaded clips",
                "RngInt(128, surface_width - 128) once per already-visible planet",
                "RngFloat(2.0, difficulty special speed maximum) mothership speed",
                "RngFloat(2.0, 4.0) mothership animation interval",
                "every eighth spawn only: the rare-ship draws listed under rare_ship",
            ],
            "entry_sides": {
                "right": {
                    "coin": "RngInt(0, 100) < 50",
                    "direction_flag": 1,
                    "spawn_x": "surface_width",
                    "pan": 1.0,
                },
                "left": {
                    "coin": "RngInt(0, 100) >= 50",
                    "direction_flag": 0,
                    "spawn_x": "-mothership_sheet_width",
                    "pan": -1.0,
                },
            },
            "banner": {
                "text": "H U R R Y   U P",
                "duration_ms": 1000,
                "deadline_field_va": "0x00e114d4",
            },
            "voice": {
                "clip_keys": ["hurryup1", "hurryup2"],
                "selection": "RngInt(0, loaded clip count) over the loaded clips in order",
            },
            "planet_row": {
                "count_global_va": "0x007ce91c",
                "initial_count": 1,
                "maximum_count": 8,
                "table_va": "0x00d56b88",
                "rule": (
                    "every already-visible planet takes a fresh "
                    "RngInt(128, surface_width - 128) X, then the count grows by one "
                    "and is capped at eight"
                ),
            },
            "global_decrement": {
                "va": "0x0058f07b",
                "global_va": "0x008f202c",
                "step": -8,
                "floor": 40,
                "confidence": "evidence_only",
            },
        },
        "mothership": {
            "confidence": "proven",
            "behavior_state": 9,
            "sheet": "mothership2",
            "mask_sheet": "mothership2_mask",
            "hit_mask": "mothership",
            "sheet_size": [288, 512],
            "frame_size": [96, 57],
            "frame_count": 20,
            "frame_layout": "column-major: source x = (frame / 8) * 96, source y = (frame % 8) * 57",
            "sheet_width_global_va": "0x00d563e8",
            "sheet_width": 288,
            "spawn_y": 20.0,
            "speed": "RngFloat(2.0, difficulty special speed maximum)",
            "animation_interval": "RngFloat(2.0, 4.0)",
            "kill_score": 2500,
            "health": "trunc(endless ordinary health additive) + difficulty special health base A",
            "health_base_global_va": "0x008f206c",
            "health_base_by_difficulty": {"easy": 10, "normal": 16, "hard": 20, "ace": 25},
            "speed_maximum_global_va": "0x008f2074",
            "speed_maximum_by_difficulty": {"easy": 3, "normal": 4, "hard": 5, "ace": 6},
            "hitbox": {"offset": [0, 0], "width": 96.0, "height": 57.0},
            "hit_mask": {
                "file": "mothership.hma",
                "bytes": 109440,
                "sha256": (
                    "59f4d1f1942e7190ac88b67563be1727a92ed787bff54f3dbc46bb3762302517"
                ),
                "layout": "single column of twenty 96x57 frames, frame-major",
                "atlas_size": [96, 1140],
                "note": (
                    "the mask packs its frames differently from the 3x8 texture, so "
                    "the mask rectangle is derived from the frame index alone"
                ),
            },
            "motion_va": "0x00610b67",
            "motion": {
                "gate": "the per-player level-complete flag 0x008487ec suspends the handler",
                "planet_sweep": (
                    "a planet whose X is behind the mothership's travel direction is "
                    "cleared to zero and emits one debris burst plus its sound"
                ),
                "advance": "x += speed * simulation scale in the entry direction",
                "despawn_right": "x > surface_width + 70",
                "despawn_left": "x < -70",
                "on_despawn": "counts as an escaped level object and re-arms the deadline",
                "animation": (
                    "frame countdown -= scale; on underflow reload the interval and "
                    "step the frame, wrapping 0..19"
                ),
            },
            "death_va": "0x0058a67d",
            "death": {
                "explosion_size": [96, 57],
                "secret_id": 3,
                "secret_flag_va": "0x008489ec",
                "re_arms_deadline": True,
            },
        },
        "rare_ship": {
            "confidence": "proven",
            "behavior_state": 12,
            "sheet": "moneyship",
            "mask_sheet": "moneyship_mask",
            "sheet_size": [128, 1280],
            "frame_size": [128, 128],
            "frame_count": 10,
            "frame_layout": "single column: source x = 0, source y = frame * 128",
            "cadence": {
                "counter_global_va": "0x00848864",
                "period": 8,
                "rule": "the counter increments on every hurry-up spawn and fires on eight",
            },
            "spawn_x": "100 + RngInt(0, (surface_width - 200) / 2)",
            "spawn_y": -110.0,
            "kill_score": 25000,
            "health": "trunc(endless ordinary health additive) + difficulty special health base C",
            "health_base_global_va": "0x008f207c",
            "health_base_by_difficulty": {
                "easy": 75,
                "normal": 100,
                "hard": 125,
                "ace": 150,
            },
            "random_draw_order": [
                "RngInt(0, (surface_width - 200) / 2) spawn X",
                "RngInt(0, 5) heading offset added to 18",
                "RngFloat(0.0, 100.0) turn countdown, plus 50.0",
                "RngInt(0, 2) animation direction",
                "RngFloat(0.8, 3.0) speed scalar",
                "RngInt(0, 3) heading step interval, plus 2",
                "RngFloat(0.0, 8.0) heading step countdown, plus 3.0",
            ],
            "heading_table_x_va": hex_va(HEADING_TABLE_X_VA),
            "heading_table_y_va": hex_va(HEADING_TABLE_Y_VA),
            "heading_table_entries": HEADING_TABLE_COUNT,
            "heading_table_x": heading_x,
            "heading_table_y": heading_y,
            "hitbox": {"offset": [14.0, 14.0], "width": 100.0, "height": 100.0},
            "hit_mask": {
                "file": "moneyship.hma",
                "bytes": 163840,
                "sha256": (
                    "f7e327b95385cb3996ab75e587732a9d990326384f0724aa29be839473887b09"
                ),
                "layout": "row-major copy of the 128x1280 sheet",
                "atlas_size": [128, 1280],
                "note": "the traced 100x100 rectangle bounds the mask sample",
            },
            "motion_va": "0x0060fcxx",
            "motion": {
                "advance": (
                    "x += axis scale * heading table x * speed scalar * simulation "
                    "scale; y uses the matching y table"
                ),
                "wrap": (
                    "x > surface_width + 120 wraps to -120; x < -120 wraps to "
                    "surface_width + 110; y uses surface_height with the same offsets"
                ),
                "steering": (
                    "on turn-countdown underflow the turn mode resets to 2 with a 30.0 "
                    "countdown, then the four edge tests may set turn mode 1 or 3 with "
                    "a RngFloat(0.0, 160.0) + 40.0 countdown"
                ),
                "steer_edges": {
                    "right": "top-left x > 700 with heading < 20",
                    "left": "top-left x < 36 with heading >= 20",
                    "bottom": "top-left y > 180 with 10 <= heading < 30",
                    "top": "top-left y < 80 with heading < 10 or heading > 29",
                },
                "heading_step": "turn mode 3 increments, turn mode 1 decrements, wrapping 0..39",
                "animation": (
                    "countdown reload is (health / (spawn health / 5)) / 4, so the ship "
                    "animates faster as it takes damage; the frame ping-pongs 0..9"
                ),
            },
            "death_va": "0x0058a38a",
            "death": {
                "explosion_size": [128, 128],
                "secret_id": 6,
                "secret_flag_va": "0x008489f8",
                "re_arms_deadline": (
                    "only when another state 12 ship is still active, through the "
                    "0x0058a66c fallthrough into the mothership death case"
                ),
            },
        },
        "secret_recording": {
            "confidence": "proven",
            "recorder_va": "0x00548e10",
            "guards": [
                "a profile handle must be attached (0x007d0f80 != -1)",
                "match mode must be 0 (solo)",
                "the frame hook 0x00afbbf4 must not be the attract-mode handler 0x0052972c",
            ],
            "ids": {"mothership": 3, "rare_ship": 6},
            "id_space": "0..29, matching the shop secret draw RngInt(0, 30)",
        },
        "effect_pool": {
            "confidence": "proven",
            "base_va": "0x00af7ea4",
            "slot_count": 100,
            "slot_stride_bytes": 140,
            "update_va": "0x00601cd0",
            "player_collision_va": "0x005842c0",
            "note": (
                "a shared hazard pool rather than a decoration: player fire clears "
                "an object, and an object that reaches a captive or the fighter "
                "destroys it"
            ),
            "planet_debris": {
                "kind": 9,
                "sheet": "rocket",
                "frame_size": [24, 24],
                "spawn_offset": [32, 25],
                "start_heading": 17,
                "heading_count": 32,
                "heading_table_x_va": "0x007d0454",
                "heading_table_y_va": "0x007d04d4",
                "random_draw_order": [
                    "RngInt(0, 3) + 4 animation interval",
                    "RngInt(0, 3) + 3 animation countdown",
                    "RngInt(0, 5) + 3 steering reload",
                    "RngInt(0, difficulty lifetime range) + difficulty lifetime base",
                    "duel only: RngInt(0, 2) owning seat",
                    "RngFloat(difficulty speed minimum, difficulty speed maximum)",
                ],
                "lifetime_base_global_va": "0x008f2024",
                "lifetime_range_global_va": "0x008f2028",
                "speed_minimum_global_va": "0x008f2030",
                "speed_maximum_global_va": "0x008f2034",
                "steering_threshold_global_va": "0x008f2038",
                "steering": {
                    "range": "101 - per-player field 0x00848770 + 1",
                    "per_player_field_default": 0,
                    "rule": (
                        "a draw below the difficulty threshold wanders "
                        "(RngInt(0,100) < 33 turns one step back, RngInt(0,100) > 66 "
                        "turns one step forward); otherwise it turns one step along "
                        "the shorter arc toward the fighter, breaking a tie with "
                        "RngInt(0,100) < 50"
                    ),
                    "quadrant_table": [0, 0, 0, 0, 0, 0x15, 0xD, 0, 0, 0x1D, 5],
                },
            },
            "guard_beam": {
                "kind": 18,
                "sheet": "beam",
                "frame_size": [64, 70],
                "lifetime": 5.0,
                "column_step": 70,
                "column_offset": 30,
                "note": "static segments with no motion and no random draws",
            },
            "settings_gated_draws": {
                "confidence": "evidence_only",
                "global_va": "0x00af7870",
                "note": (
                    "the debris spawn's optional trail block is gated on a graphics "
                    "setting, so retail's own stream through it depends on a user "
                    "option; the remake models only the unconditional draws"
                ),
            },
        },
        "level_object_accounting": {
            "confidence": "proven",
            "total_field_va": "0x00848918",
            "killed_field_va": "0x00848920",
            "escaped_field_va": "0x00848924",
            "complete_flag_va": "0x00848928",
            "rule": (
                "each spawned hurry-up ship raises the level object total by one, so "
                "the level cannot complete until every one is killed or has left"
            ),
        },
        "other_secret_ships": {
            "confidence": "evidence_only",
            "note": (
                "These two ships share the death dispatcher switch at 0x005887bc with "
                "the hurry-up family but have independent spawners and triggers. They "
                "are recorded here so the family is documented in one place; neither "
                "is implemented by the hurry-up wave."
            ),
            "money_sucker": {
                "behavior_state": 11,
                "spawner_va": "0x00581250",
                "sheet": "moneysucker2",
                "trigger": (
                    "cash above 750 with a 120000 ms cooldown, weighted by cash / 1340 "
                    "plus RngInt(3, 10)"
                ),
                "kill_effect": "raises the special health base B global 0x008f2070 by 20",
                "hitbox": {"width": 128.0, "height": 50.0},
            },
            "guard_ship": {
                "behavior_state": 18,
                "spawner_va": "0x00581990",
                "sheet": "guard",
                "trigger": (
                    "level above 15 and at least 10 levels since the previous guard "
                    "ship; excluded in match mode 6"
                ),
                "hitbox": {"width": 128.0, "height": 64.0},
            },
        },
        "constants": constants,
        "instruction_pins": pins,
    }


def _default_paths() -> tuple[Path, Path]:
    root = Path(__file__).resolve().parents[1]
    return (
        root / "Game" / "warblade.exe",
        root / "docs" / "evidence" / "hurry_up.json",
    )


def main() -> int:
    default_exe, default_output = _default_paths()
    parser = argparse.ArgumentParser(
        description="Extract bounded retail hurry-up secret-ship evidence."
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
        print(f"hurry-up evidence is current: {args.output}")
        return 0
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(rendered, encoding="utf-8")
    print(f"wrote {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
