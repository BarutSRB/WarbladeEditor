#!/usr/bin/env python3

from __future__ import annotations

import argparse
import hashlib
import json
import struct
from dataclasses import dataclass
from pathlib import Path
from typing import Any


WARBLADE_EXE_SHA256 = "ddf1778c307af1087ff9dcb512786111e665d972298aeaac3f1b4b2996d079ef"

SPECIAL_PROTOTYPES = {
    19: ("War.I.Plasma", "root"),
    20: ("War.I.Plasma", "child"),
    21: ("War.I.Plasma", "child"),
    25: ("Fireballs", "root"),
    26: ("Fireballs", "child"),
    30: ("Fireballs", "child"),
    31: ("Fireballs", "grandchild"),
}

SPEED_CASES = {
    "easy": (0x00568835, 0x0077D824, 0x00568841, 0x0077D7D8),
    "normal": (0x00568964, 0x00778E80, 0x00568970, 0x0077D814),
    "hard": (0x00568A97, 0x00779AE8, 0x00568AA3, 0x0077B144),
    "ace": (0x00568BCA, 0x0077ADA4, 0x00568BD6, 0x0077ADDC),
}


def _hex(value: int) -> str:
    return f"0x{value:08x}"


def _f32(value: float) -> float:
    return struct.unpack("<f", struct.pack("<f", value))[0]


@dataclass(frozen=True)
class Section:
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
        return hashlib.sha256(self.data).hexdigest()

    def file_offset(self, va: int, size: int = 1) -> int:
        for section in self.sections:
            extent = max(section.virtual_size, section.raw_size)
            if section.va <= va and va + size <= section.va + extent:
                offset = section.raw_offset + va - section.va
                if offset + size > section.raw_offset + section.raw_size:
                    raise ValueError(f"{_hex(va)} is uninitialized PE data")
                return offset
        raise ValueError(f"{_hex(va)} is outside mapped PE sections")

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


def _verify_signature(
    image: PEImage,
    va: int,
    expected_hex: str,
    purpose: str,
    records: list[dict[str, Any]],
) -> None:
    expected = bytes.fromhex(expected_hex)
    actual = image.bytes_at(va, len(expected))
    if actual != expected:
        raise ValueError(
            f"signature mismatch for {purpose} at {_hex(va)}: "
            f"expected {expected.hex()}, got {actual.hex()}"
        )
    records.append(
        {
            "purpose": purpose,
            "va": _hex(va),
            "size": len(expected),
            "sha256": hashlib.sha256(expected).hexdigest(),
        }
    )


def _verify_speed_load(
    image: PEImage,
    instruction_va: int,
    source_va: int,
    destination_va: int,
) -> None:
    expected = (
        b"\xD9\x05"
        + struct.pack("<I", source_va)
        + b"\xD9\x1D"
        + struct.pack("<I", destination_va)
    )
    actual = image.bytes_at(instruction_va, len(expected))
    if actual != expected:
        raise ValueError(f"speed assignment mismatch at {_hex(instruction_va)}")


def _manual_line(lines: list[str], line_number: int, required: str) -> dict[str, Any]:
    line = lines[line_number - 1].strip()
    if required not in line:
        raise ValueError(
            f"manual line {line_number} no longer contains expected text {required!r}"
        )
    return {
        "line": line_number,
        "sha256": hashlib.sha256(line.encode("utf-8")).hexdigest(),
    }


def build_evidence(exe_path: Path, manual_path: Path) -> dict[str, Any]:
    image = PEImage(exe_path)
    if image.sha256 != WARBLADE_EXE_SHA256:
        raise ValueError(
            f"unexpected warblade.exe SHA-256 {image.sha256}; "
            f"expected {WARBLADE_EXE_SHA256}"
        )

    manual_lines = manual_path.read_text(encoding="cp1252").splitlines()
    manual_refs = {
        "bullet_start": _manual_line(manual_lines, 326, "start off with 5 bullets"),
        "fighters": _manual_line(manual_lines, 346, "start with three lives / fighters"),
        "armour": _manual_line(manual_lines, 354, "maximum of 2 armours"),
        "bullet_limit": _manual_line(manual_lines, 359, "At the start of the game this limit is 5"),
    }

    signatures: list[dict[str, Any]] = []
    signature_specs = (
        (
            0x005E0B71,
            "0fbf88388884003b4d08",
            "pre-volley live-projectile capacity comparison",
        ),
        (
            0x005DF878,
            "0fbf8838888400034d1c8b551069d2d8040000",
            "per-object live-projectile increment",
        ),
        (
            0x005DF8DB,
            "668b4d1c66898880e3d500",
            "per-object counter contribution store",
        ),
        (
            0x005DFC77,
            "51d94524d91c2451d94520d91c248b451c50",
            "child-A recursion preserves the counter contribution",
        ),
        (
            0x005DFCD1,
            "51d94524d91c2451d94520d91c248b451c50",
            "child-B recursion preserves the counter contribution",
        ),
        (
            0x005DFA46,
            "8b4514d9048588d67c00dc1db02d7800",
            "special movement lower-threshold comparison",
        ),
        (
            0x005DFAB8,
            "8b4514d9048588d67c00dc1d10657800",
            "special movement spawn-jitter threshold comparison",
        ),
        (
            0x00620974,
            "833d38b9af000074378b45f869c0a000000083b884e3d50000",
            "persistent projectile frame-chain branch",
        ),
        (
            0x00585945,
            "83b884e3d500007429d9eed99d28ffffff",
            "beam collision top override to zero",
        ),
        (
            0x0058595F,
            "8b8860e3d50069c9d8040000d981f0868400",
            "beam collision bottom reads the owning player's live retail Y",
        ),
        (
            0x005DF92C,
            "d94508dc0558ad77008b4514db048540d37c00dc35409b7700",
            "projectile spawn X is centered on the retail forty-pixel ship",
        ),
        (
            0x00587465,
            "d98408ac9b8400d8a26ce3d500",
            "ordinary-enemy projectile damage subtraction",
        ),
        (
            0x005874D1,
            "8b45e869c0a0000000d9806ce3d500dc35409b7700",
            "persistent projectile damage halving",
        ),
        (
            0x00562DD6,
            "a144208f0069c0d8040000c7806887840001000000",
            "Auto Fire shop enable",
        ),
        (
            0x00561F06,
            "a144208f0069c0d8040000c7809087840001000000",
            "Super Auto Fire ownership flag",
        ),
        (
            0x00561F1B,
            "a144208f0069c0d8040000c7802088840019000000",
            "Super Auto Fire 25-millisecond delay",
        ),
        (
            0x00623C84,
            "8b450869c0d8040000c7802088840064000000",
            "default 100-millisecond autofire delay",
        ),
        (
            0x005EC7D3,
            "a140208f0069c0d80400008b0dbc27ab003b881c888400",
            "strict autofire absolute-deadline comparison",
        ),
        (
            0x005EC8D5,
            "a140208f0069c0d80400008b0dbc27ab00038820888400",
            "autofire deadline reschedule",
        ),
        (
            0x00628CD9,
            "68e051f900ff15982bfa00",
            "millisecond QPC timer source",
        ),
        (
            0x00628D26,
            "ff159030fa00",
            "timeGetTime millisecond fallback",
        ),
        (
            0x00562F35,
            "a144208f0069c0d8040000d980fc868400d90580208f00",
            "Less Speed live-base guard",
        ),
        (
            0x005630D3,
            "a144208f0069c0d8040000d90584208f00d80d88208f00d80580208f00",
            "Extra Speed stored-ceiling formula",
        ),
        (
            0x00563046,
            "a144208f0069c0d80400000fbf883688840083f932",
            "Extra Bullet capacity cap of 50",
        ),
        (
            0x00571A0E,
            "0fbf883688840083f9057e24",
            "death-time capacity floor of five",
        ),
        (
            0x00562BB9,
            "a144208f0069c0d80400008b0d44208f0069c9d8040000",
            "Armour shop configuration lookup",
        ),
        (
            0x00584A7D,
            "a140208f0069c0d80400008b0d40208f0069c9d8040000",
            "alien-projectile armour threshold branch",
        ),
        (
            0x00584E18,
            "8b804088840099b905000000f7f969c0e80300000305bc27ab00",
            "armour shield expiry formula",
        ),
        (
            0x005629C7,
            "a144208f0069c0d80400008b0d44208f0069c9d8040000",
            "Extra Life shop configuration lookup",
        ),
        (
            0x005ECFBE,
            "8b0d40208f0069c9d80400008b91c08884008b0c95f0a9b400",
            "death-time fighter-step lookup",
        ),
        (
            0x0062381F,
            "d905dc9a7700d99800878400",
            "fighter banking phase initialization",
        ),
        (
            0x005EB935,
            "c745f801000000a140208f0069c0d8040000d98000878400d805a4f77c00",
            "right-input banking increment",
        ),
        (
            0x005EC978,
            "837df8000f858e000000a140208f0069c0d8040000d98000878400",
            "idle banking return-to-neutral branch",
        ),
    )
    for va, expected, purpose in signature_specs:
        _verify_signature(image, va, expected, purpose, signatures)

    lower_threshold = image.f64(0x00782DB0)
    upper_threshold = image.f64(0x00786510)
    special_results = []
    for prototype_id, (weapon, role) in SPECIAL_PROTOTYPES.items():
        raw = image.f32(0x007CD688 + prototype_id * 4)
        if lower_threshold < raw < upper_threshold:
            spread = raw - lower_threshold
            rule = {
                "kind": "random_horizontal_velocity",
                "formula": "vx = random_float(0, secondary - 160) - (secondary - 160) / 2",
                "vx_min": -spread / 2,
                "vx_max": spread / 2,
                "per_update": "x += vx * tick_scale",
            }
        elif upper_threshold < raw:
            spread = raw - upper_threshold
            rule = {
                "kind": "random_spawn_x_jitter",
                "formula": "x += (random_float(0, secondary - 170) - (secondary - 170) / 2) * tick_scale; vx = 0",
                "unscaled_random_min": -spread / 2,
                "unscaled_random_max": spread / 2,
                "horizontal_velocity_after_spawn": 0,
            }
        else:
            raise ValueError(f"prototype {prototype_id} is not special")
        special_results.append(
            {
                "prototype_id": prototype_id,
                "weapon": weapon,
                "role": role,
                "secondary_raw": raw,
                **rule,
            }
        )

    laser_chain = []
    frame = 22
    visited: set[int] = set()
    while frame != -1:
        if frame in visited:
            raise ValueError("laser frame chain loops")
        visited.add(frame)
        laser_chain.append(frame)
        frame = image.i32(0x007CDC00 + frame * 4)
    laser_flags = {
        str(item): image.i32(0x007CDE30 + item * 4) for item in laser_chain
    }
    laser_width = image.i32(0x007CD340 + 22 * 4)
    laser_x_offset = image.i32(0x007CDAE8 + 22 * 4)
    laser_y_offset = image.i32(0x007CD9D0 + 22 * 4)
    player_half_width = image.f64(0x0077AD58)

    speed_by_difficulty: dict[str, Any] = {}
    maximum_upgrade_count = image.f32(0x0077B1C4)
    for difficulty, (
        base_instruction,
        base_source,
        increment_instruction,
        increment_source,
    ) in SPEED_CASES.items():
        _verify_speed_load(image, base_instruction, base_source, 0x008F2080)
        _verify_speed_load(
            image, increment_instruction, increment_source, 0x008F2084
        )
        base = image.f32(base_source)
        increment = image.f32(increment_source)
        speed_by_difficulty[difficulty] = {
            "base": base,
            "increment": increment,
            "stored_shop_ceiling": _f32(
                base + increment * maximum_upgrade_count
            ),
            "base_write_va": _hex(base_instruction),
            "increment_write_va": _hex(increment_instruction),
        }

    life_base, life_step, life_initial_offset, life_maximum_offset = struct.unpack(
        "<4i", image.bytes_at(0x007D1524, 16)
    )
    armour_base, armour_step, armour_maximum_offset = struct.unpack(
        "<3i", image.bytes_at(0x007D1534, 12)
    )
    default_shield_duration_field = image.u32(0x00623EB7)

    return {
        "schema_version": 1,
        "source": {
            "exe": str(exe_path),
            "exe_sha256": image.sha256,
            "manual": str(manual_path),
            "manual_references": manual_refs,
        },
        "confidence_legend": {
            "proven": "Direct executable data/control-flow or explicit bundled-manual statement.",
            "supported": "Strong bounded evidence, but not every caller or ordering boundary is closed.",
            "evidence_only": "Exact retained source data with no supported-runtime semantic consumer.",
        },
        "projectile_capacity": {
            "confidence": "proven",
            "session_stride": "0x4d8",
            "capacity_field_va_player_zero": "0x00848836",
            "live_object_count_va_player_zero": "0x00848838",
            "initial_capacity": 5,
            "upgrade_cap": 50,
            "normal_object_contribution": 1,
            "alternate_non_counting_contribution": 0,
            "semantics": "Every successfully allocated projectile object increments the live count by the inherited contribution. Immediate recursive children inherit the same contribution, so roots and children each count.",
            "volley_gate": "The capacity comparison runs once before spawning a complete recursive volley. A legal volley can therefore leave the live count above capacity; later volleys remain blocked until live count is below capacity again.",
            "child_origin": "All immediate recursive children receive the original fire X/Y. Prototype offsets are independently relative to that fire origin, not recursively accumulated.",
            "death_downgrade": "If capacity is above five, player death subtracts exactly one; it never downgrades below five.",
            "gate_va": "0x005e0b71-0x005e0b7b",
            "spawn_increment_va": "0x005df878-0x005df88b",
            "contribution_store_va": "0x005df8db-0x005df8df",
            "recursive_calls_va": [
                "0x005dfc6a-0x005dfcb2",
                "0x005dfcc4-0x005dfd0c",
            ],
            "upgrade_va": "0x00563046-0x0056307f",
            "death_downgrade_va": "0x00571a0e-0x00571a37",
        },
        "special_projectile_movement": {
            "confidence": "proven",
            "secondary_table_va": "0x007cd688",
            "lower_threshold": lower_threshold,
            "upper_threshold": upper_threshold,
            "spawn_routine_va": "0x005df6e0",
            "ordinary_and_random_velocity_update": "Both stored X and Y velocities are multiplied by tick_scale on each generic projectile update.",
            "prototype_rules": special_results,
            "random_endpoint_inclusion": {
                "confidence": "proven",
                "raw_word_domain": "0..0xffffffff",
                "scale": "2^-32",
                "note": "The mathematical maximum-word result is below the upper argument, but the executable's final float32 store rounds the weapon spans to that endpoint. Each helper call consumes exactly one raw word.",
            },
        },
        "laser": {
            "confidence": "proven",
            "weapon_id": 7,
            "root_prototype_id": 22,
            "initial_damage": image.f32(0x007CF018 + 7 * 4),
            "width": laser_width,
            "height": image.i32(0x007CD458 + 22 * 4),
            "prototype_x_offset": laser_x_offset,
            "prototype_y_offset": laser_y_offset,
            "primary_velocity_fp": image.i32(0x007CD570 + 22 * 4),
            "secondary_velocity": image.f32(0x007CD688 + 22 * 4),
            "persistent_flags_by_frame": laser_flags,
            "frame_chain": laser_chain + [-1],
            "live_update_transitions": len(laser_chain),
            "lifetime_rule": "During nonzero gameplay state, the persistent frame advances once per projectile-update call. Reaching -1 deactivates the object.",
            "spawn_geometry": {
                "retail_player_coordinate_convention": "The X/Y arguments passed to the projectile spawner are the retail player's stored sprite-origin coordinates.",
                "projectile_left_formula": "player_x + 20 - projectile_width / 2 - prototype_x_offset",
                "projectile_left_for_laser": player_half_width
                - laser_width / 2
                - laser_x_offset,
                "projectile_visual_top_formula": "player_y - prototype_y_offset",
                "projectile_visual_top_for_laser": "-86 relative to retail player_y",
            },
            "collision_bounds": {
                "left": "projectile_x",
                "right": "projectile_x + 16",
                "top": 0,
                "bottom": "owning_player_current_retail_y",
            },
            "attachment": "Horizontal position is latched at spawn and never follows later player X movement. The collision bottom is recomputed from the owning player's current live retail Y on every collision pass, so vertical movement changes the column's bottom while the beam remains alive.",
            "ordinary_enemy_damage_sequence": "For each confirmed collision in array order, subtract current damage and then halve the projectile's stored damage: 10, 5, 2.5, 1.25, ... . The beam is not removed on its first hit.",
            "special_enemy_exception": "At least one special-enemy family has a separate damage divisor/minimum path; the ordinary-enemy sequence is the first-five integration contract.",
            "collision_pass_count": {
                "confidence": "proven",
                "count": 4,
                "frames": [22, 23, 24, 50],
                "order": "The authoritative dispatcher performs the player-projectile collision pass before projectile update. A newly fired Laser begins colliding on the next tick; each live frame receives one stable enemy-array scan before advancing, and frame 50 retires after its pass.",
            },
            "update_va": "0x00620974-0x00620b21",
            "collision_bounds_va": "0x00585945-0x00585971",
            "ordinary_damage_va": "0x00587465-0x00587487",
            "damage_halving_va": "0x005874d1-0x005874ef",
        },
        "fire_timing": {
            "confidence": "proven",
            "clock_unit": "milliseconds",
            "manual_fire": {
                "cooldown_ms": None,
                "rule": "Manual fire is edge-latched. A press fires immediately when armed; release rearms it. There is no universal 100-millisecond weapon cooldown.",
                "latch_va_player_zero": "0x00848994",
                "edge_path_va": "0x005ec5fb-0x005ec75f",
            },
            "autofire": {
                "enabled_va_player_zero": "0x00848768",
                "next_deadline_va_player_zero": "0x0084881c",
                "delay_va_player_zero": "0x00848820",
                "default_delay_ms": image.u32(0x00623C93),
                "super_delay_ms": image.u32(0x00561F2C),
                "deadline_rule": "Fire only when current_ms > next_deadline, then next_deadline = current_ms + delay_ms.",
                "initial_edge_interaction": "The manual edge does not reschedule the deadline and falls through to the Auto path. If the old deadline is already expired, one update can emit the manual-edge volley and a second Auto volley.",
                "start_or_resume_seed": "Gameplay start/resume writes next_deadline = current_ms. The Auto Fire bonus path also seeds it to current_ms before enabling; the shop enable path leaves the existing deadline unchanged.",
                "shop_enable_va": "0x00562dd6-0x00562deb",
                "super_enable_va": "0x00561eee-0x00561f3b",
                "deadline_compare_va": "0x005ec7d3-0x005ec7ea",
                "deadline_store_va": "0x005ec8d5-0x005ec8f8",
                "timer_source_va": "0x00628cd0-0x00628d82",
            },
        },
        "fighter_banking": {
            "confidence": "proven",
            "phase_va_player_zero": "0x00848700",
            "initial_phase": image.f32(0x00779ADC),
            "step_per_player_update": image.f32(0x007CF7A4),
            "neutral_phase": image.f64(0x00778DE8),
            "rendered_frame": "truncate_toward_zero(phase) % 11",
            "left": "Subtract 0.5 and clamp negative results to 0.",
            "right": "Add 0.5. The aligned raw phase reaches 10.5; the next 0.5 step reaches threshold 11 and is reset to 10. Rendered frame remains 10 throughout this endpoint quirk.",
            "idle": "Move phase toward 5 by 0.5 per player update without overshooting.",
            "cross_reference": "docs/evidence/SPRITE_ATLAS.md",
        },
        "speed_shop": {
            "confidence": "proven",
            "current_speed_va_player_zero": "0x008486fc",
            "maximum_upgrade_count": maximum_upgrade_count,
            "by_difficulty": speed_by_difficulty,
            "extra_speed": "If current speed is below base + increment * 16, add one live difficulty increment, then clamp any overshoot to that stored ceiling.",
            "less_speed": "If current speed is above the live difficulty base, subtract one live difficulty increment. There is no post-subtraction clamp; valid retail upgrade-lattice values land on the base.",
            "movement_cap_before_tick_scale": image.f64(0x0077DC48),
            "movement_rule": "movement = min(stored_speed * normal_movement_scale, 14) * tick_scale",
            "bootstrap_correction": "The 0.75 value written during bootstrap is overwritten by the selected difficulty before player initialization and is not the live Normal increment.",
            "extra_speed_va": "0x005630d3-0x005631be",
            "less_speed_va": "0x00562f35-0x00562fc1",
            "movement_consumer_va": "0x005eb5d2-0x005eb617",
        },
        "first_shop_survivability": {
            "confidence": "proven",
            "extra_life": {
                "item_id": 11,
                "field_va_player_zero": "0x00848750",
                "default_raw_encoding": {
                    "base": life_base,
                    "step": life_step,
                    "initial_offset": life_initial_offset,
                    "maximum_offset": life_maximum_offset,
                },
                "initial_total_fighters": life_initial_offset // life_step,
                "purchase_effect_total_fighters": 1,
                "maximum_total_fighters": life_maximum_offset // life_step,
                "death_rule": "Subtract one encoded step first; respawn only while raw > base. Starting from three total fighters, the third death is terminal.",
                "purchase_va": "0x005629c7-0x00562b33",
                "death_va": "0x005ecfbe-0x005ed084",
            },
            "armour": {
                "item_id": 9,
                "field_va_player_zero": "0x008487e8",
                "shield_expiry_va_player_zero": "0x00848808",
                "default_raw_encoding": {
                    "base": armour_base,
                    "step": armour_step,
                    "maximum_offset": armour_maximum_offset,
                },
                "initial_charges": 0,
                "purchase_effect_charges": 1,
                "maximum_charges": armour_maximum_offset // armour_step,
                "default_duration_field": default_shield_duration_field,
                "default_shield_ms": default_shield_duration_field // 5 * 1000,
                "traced_projectile_hit": "With at least one charge, avoid the death branch, consume exactly one charge, and set shield expiry. Alien-projectile collision work is skipped while that expiry field is nonzero.",
                "purchase_va": "0x00562bb9-0x00562d28",
                "collision_va": "0x005842c0; protected branch 0x00584d80-0x00584e7c",
                "all_hazard_coverage": {
                    "confidence": "supported",
                    "note": "Several other damage routines read the shield timer, but this bounded trace does not claim that every non-projectile hazard consumes armour identically.",
                },
            },
        },
        "verified_signatures": signatures,
    }


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--exe",
        type=Path,
        default=root / "Game" / "warblade.exe",
    )
    parser.add_argument(
        "--manual",
        type=Path,
        default=root / "Game" / "Warblade_Manual_V1.34_Eng.txt",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=root / "docs" / "evidence" / "weapon_runtime.json",
    )
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    evidence = build_evidence(args.exe.resolve(), args.manual.resolve())
    payload = json.dumps(evidence, indent=2, ensure_ascii=False) + "\n"
    if args.check:
        existing = args.output.read_text(encoding="utf-8")
        if existing != payload:
            raise SystemExit(f"{args.output} is stale; regenerate it")
        print(f"verified {args.output}")
        return 0
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(payload, encoding="utf-8")
    print(f"wrote {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
