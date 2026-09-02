#!/usr/bin/env python3

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import sys
from pathlib import Path
from typing import Any


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_EXE = PROJECT_ROOT / "Game" / "warblade.exe"
DEFAULT_LEVELS = PROJECT_ROOT / "content" / "levels.json"
DEFAULT_SPRITES = PROJECT_ROOT / "content" / "sprite_frames.json"
DEFAULT_OUTPUT = PROJECT_ROOT / "content" / "bosses.json"
DEFAULT_EVIDENCE = PROJECT_ROOT / "docs" / "evidence" / "BIG_BOSS_STATE_13.md"
EXECUTABLE_SHA256 = "ddf1778c307af1087ff9dcb512786111e665d972298aeaac3f1b4b2996d079ef"
SHEET_IDS = [f"alien_big1_{index}" for index in range(1, 7)]
LEVEL_50_SHEET_IDS = [f"alien_big2_{index}" for index in range(1, 7)]
# Endless per-hundred state-13 health additive: the traced consumer at
# 0x0056b52f-0x0056b546 stores authored base + int(additive * 20.0) where
# the additive accumulates 5.0 per hundred (ENDLESS_PROGRESSION.md).
ENDLESS_STEP_HEALTH_ADDITIVE = 100
LEVEL_75_SHEET_IDS = [f"alien_big3_{index}" for index in range(1, 7)]
LEVEL_100_SHEET_IDS = [f"alien_big4_{index}" for index in range(1, 7)]
AUTHORED_PAYLOAD_CANONICALIZATION = "warblade_canonical_payload_v1"
AUTHORED_LEVEL_PAYLOAD_SHA256 = (
    "6ec7ac4f9f5eb5ea7a074d0315a2393acc37da1b0f1fd8f08f9b2c9032a6498f"
)
LEVEL_50_AUTHORED_LEVEL_PAYLOAD_SHA256 = (
    "c4ae166f52d970d2e099ae82edab819d24904473cec5f80cdfbc55917f3494bd"
)
LEVEL_75_AUTHORED_LEVEL_PAYLOAD_SHA256 = (
    "daa437aca2a5fe322fef8941a3632d2962da6c7d3d627eca9cae46887af4c64d"
)
LEVEL_100_AUTHORED_LEVEL_PAYLOAD_SHA256 = (
    "ccc5c188f1c4f4e1344d831c759d01590159ccb99b02ae935784a2283bb56f47"
)


def _effect_runtime_contract() -> dict[str, Any]:
    return {
        "id": "retail_big_boss_effects_v1",
        "executable_sha256": EXECUTABLE_SHA256,
        "preset": {
            "id": "retail_high",
            "high_effects": True,
            "particle_density": 100,
            "evidence": "0x005bab12/0x005bab3a",
        },
        "pools": {
            "flash": {"capacity": 50, "base": "DAT_00847720"},
            "debris": {"capacity": 150, "base": "DAT_00b04a54"},
            "smoke": {"capacity": 500, "base": "DAT_00ac5c98"},
            "particle": {"capacity": 1000, "base": "DAT_007e3948"},
            "screen": {"capacity": 4, "base": "DAT_008ff578"},
        },
        "creation_order": {
            "FUN_005dfee0": ["scan_flash", "RngInt(0,2)"],
            "FUN_005e0650": [
                "scan_screen_if_variant_positive",
                "scan_flash",
                "RngInt(0,3)",
                "RngInt(0,150)",
                "FUN_005df370(density*3)",
            ],
            "FUN_005defe0_each_allocated": [
                "RngInt(0,359)",
                "RngFloat(1,6)",
                "RngFloat(2,3)",
                "RngInt(0,5)",
                "RngInt(0,2)",
                "RngFloat(5,45)",
                "RngInt(0,100)",
                "RngInt(150,255)",
            ],
            "FUN_0052f440": [
                "RngFloat(1.5,6) x3 before scan",
                "count+1 allocation attempts",
                "each: RngFloat(1,40), RngFloat(2,4), RngFloat(.01,.2), RngInt(0,3600)",
            ],
            "FUN_00570420": {
                "rank_ready_false": ["RngInt(0,6)"],
                "rank_ready_true": [
                    "RngInt(0,5)",
                    "RngInt(0,7) if eligibility roll is 0, otherwise RngInt(0,6)",
                ],
            },
            "FUN_00571080_each_allocated": {
                "only_blue_coins_false": [
                    "RngInt(0,100)",
                    "remaining record draws",
                ],
                "only_blue_coins_true": [
                    "force base type 32",
                    "remaining record draws",
                ],
            },
        },
        "same_tick_update_order": [
            "FUN_00622150_flash",
            "FUN_00622540_screen",
            "FUN_00622be0_smoke",
            "FUN_0052f8a0_particle",
            "FUN_005f4210_debris",
        ],
        "exact_trace_complete": True,
    }


class BossContractError(ValueError):
    pass


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _canonical_payload_bytes(value: Any) -> bytes:
    """Encode JSON-domain data without depending on object insertion order."""
    if value is None:
        return b"n"
    if isinstance(value, bool):
        return b"b1" if value else b"b0"
    if isinstance(value, int):
        return f"i{value};".encode("ascii")
    if isinstance(value, str):
        encoded = value.encode("utf-8")
        return f"s{len(encoded)}:".encode("ascii") + encoded
    if isinstance(value, list):
        return (
            f"a{len(value)}[".encode("ascii")
            + b"".join(_canonical_payload_bytes(item) for item in value)
            + b"]"
        )
    if isinstance(value, dict):
        if not all(isinstance(key, str) for key in value):
            raise BossContractError("canonical boss payload keys must be strings")
        keys = sorted(value)
        return (
            f"d{len(keys)}{{".encode("ascii")
            + b"".join(
                _canonical_payload_bytes(key)
                + _canonical_payload_bytes(value[key])
                for key in keys
            )
            + b"}"
        )
    raise BossContractError(
        f"canonical boss payload contains unsupported {type(value).__name__}"
    )


def _normalized_authored_payload(level: dict[str, Any]) -> dict[str, Any]:
    level_label = f"level {level.get('id', '?')}"
    authored = level.get("authored_lvd")
    if not isinstance(authored, dict):
        raise BossContractError(f"{level_label} is missing its authored payload")

    def integer(source: dict[str, Any], key: str) -> int:
        value = source.get(key)
        if isinstance(value, bool) or not isinstance(value, int):
            raise BossContractError(f"{level_label} authored {key} must be an integer")
        return value

    supplemental = authored.get("supplemental_spawn_records_raw_words")
    fixed = authored.get("fixed_table_records_raw_words")
    groups = authored.get("groups")
    if not isinstance(supplemental, list) or not isinstance(fixed, list):
        raise BossContractError(f"{level_label} authored fixed records are malformed")
    if not isinstance(groups, list):
        raise BossContractError(f"{level_label} authored groups are malformed")

    normalized_groups: list[dict[str, Any]] = []
    for group in groups:
        if not isinstance(group, dict):
            raise BossContractError(f"{level_label} authored group must be an object")
        enemies = group.get("enemies")
        points = group.get("path_points")
        if not isinstance(enemies, list) or not isinstance(points, list):
            raise BossContractError(f"{level_label} authored group arrays are malformed")
        normalized_enemies: list[dict[str, int]] = []
        for enemy in enemies:
            if not isinstance(enemy, dict):
                raise BossContractError(f"{level_label} authored enemy must be an object")
            normalized_enemies.append(
                {
                    key: integer(enemy, key)
                    for key in [
                        "id",
                        "formation_target_x",
                        "formation_target_y",
                        "resource_slot_id",
                        "base_health",
                        "behavior_timer_a_initial",
                        "behavior_timer_a_step",
                        "behavior_timer_b_initial",
                        "behavior_timer_b_step",
                    ]
                }
            )
        normalized_points: list[dict[str, int]] = []
        for point in points:
            if not isinstance(point, dict):
                raise BossContractError(f"{level_label} authored path point must be an object")
            normalized_points.append(
                {
                    key: integer(point, key)
                    for key in [
                        "id",
                        "acceleration_x_milli",
                        "acceleration_y_milli",
                        "opcode",
                        "unknown_0c",
                        "duration_threshold_ticks",
                    ]
                }
            )
        normalized_groups.append(
            {
                **{
                    key: integer(group, key)
                    for key in [
                        "id",
                        "entry_origin_x",
                        "entry_origin_y",
                        "first_activation_delay_ticks",
                        "activation_stagger_ticks",
                        "initial_velocity_x_milli",
                        "initial_velocity_y_milli",
                        "kill_cohort_id",
                        "group_mode_id",
                    ]
                },
                "enemies": normalized_enemies,
                "path_points": normalized_points,
            }
        )

    normalized_supplemental: list[list[int]] = []
    for record in supplemental:
        if (
            not isinstance(record, list)
            or any(isinstance(word, bool) or not isinstance(word, int) for word in record)
        ):
            raise BossContractError(f"{level_label} supplemental record is malformed")
        normalized_supplemental.append(list(record))
    normalized_fixed: list[list[int]] = []
    for record in fixed:
        if (
            not isinstance(record, list)
            or any(isinstance(word, bool) or not isinstance(word, int) for word in record)
        ):
            raise BossContractError(f"{level_label} fixed-table record is malformed")
        normalized_fixed.append(list(record))

    title = authored.get("source_title_cp1252")
    mirror = authored.get("mirror_x")
    if not isinstance(title, str) or not isinstance(mirror, bool):
        raise BossContractError(f"{level_label} authored title or mirror flag is malformed")
    return {
        "schema": str(authored.get("schema", "")),
        "source_title_cp1252": title,
        "level_mode_id": integer(authored, "level_mode_id"),
        "logical_width": integer(authored, "logical_width"),
        "mirror_x": mirror,
        "supplemental_spawn_records_raw_words": normalized_supplemental,
        "fixed_table_records_raw_words": normalized_fixed,
        "groups": normalized_groups,
    }


def _authored_payload_sha256(level: dict[str, Any]) -> str:
    return _sha256(_canonical_payload_bytes(_normalized_authored_payload(level)))


def _load_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise BossContractError(f"{path} must contain a JSON object")
    return value


def _verify_boss_level_source(
    level: dict[str, Any],
    level_id: int,
    sheet_ids: list[str],
    supplemental_record: list[int],
    expected_payload_sha256: str,
    expected_group_modes: list[int],
) -> None:
    authored = level.get("authored_lvd", {})
    if level.get("id") != level_id or authored.get("level_mode_id") != 4:
        raise BossContractError(
            f"retail boss source must be level {level_id} mode 4"
        )
    if [group.get("group_mode_id") for group in authored.get("groups", [])] != (
        expected_group_modes
    ):
        raise BossContractError(f"level {level_id} group-mode signature changed")
    resources = level.get("enemy_resources", [])
    if (
        [resource.get("resource_slot_id") for resource in resources]
        != list(range(1, 7))
        or [resource.get("enemy_sheet_id") for resource in resources] != sheet_ids
    ):
        raise BossContractError(f"level {level_id} boss resource bindings changed")
    if authored.get("supplemental_spawn_records_raw_words", [None])[0] != supplemental_record:
        raise BossContractError(
            f"level {level_id} state-13 initialization record changed"
        )
    authored_payload_sha256 = _authored_payload_sha256(level)
    if authored_payload_sha256 != expected_payload_sha256:
        raise BossContractError(
            f"level {level_id} normalized authored payload changed: SHA-256 "
            f"{authored_payload_sha256} does not match {expected_payload_sha256}"
        )


def _verify_sources(
    exe_path: Path,
    levels_path: Path,
    sprites_path: Path,
) -> tuple[int, dict[int, dict[str, Any]]]:
    executable_hash = _sha256(exe_path.read_bytes())
    if executable_hash != EXECUTABLE_SHA256:
        raise BossContractError(
            f"{exe_path}: SHA-256 {executable_hash} does not match {EXECUTABLE_SHA256}"
        )
    levels = _load_json(levels_path)
    levels_version = levels.get("version")
    if levels_version not in (3, 4, 5, 6, 7, 8, 9, 10) or levels.get(
        "schema"
    ) != f"warblade.levels.v{levels_version}":
        raise BossContractError(
            "boss extraction requires levels.json v3 through v10"
        )
    level_entries = levels.get("levels")
    expected_level_count = {3: 30, 4: 35, 5: 49, 6: 50, 7: 62, 8: 100, 9: 100, 10: 100}[
        levels_version
    ]
    if (
        not isinstance(level_entries, list)
        or [entry.get("id") for entry in level_entries]
        != list(range(1, expected_level_count + 1))
    ):
        raise BossContractError(
            f"boss extraction requires exact levels 1 through {expected_level_count}"
        )
    boss_levels = {25: level_entries[24]}
    _verify_boss_level_source(
        boss_levels[25],
        25,
        SHEET_IDS,
        [1, 1, 300, 904, 10],
        AUTHORED_LEVEL_PAYLOAD_SHA256,
        [4, 5, 6, 7, 7],
    )
    if levels_version >= 6:
        boss_levels[50] = level_entries[49]
        _verify_boss_level_source(
            boss_levels[50],
            50,
            LEVEL_50_SHEET_IDS,
            [1, 1, 500, 1377, 8],
            LEVEL_50_AUTHORED_LEVEL_PAYLOAD_SHA256,
            [4, 5, 6, 7, 7],
        )
    if levels_version >= 8:
        boss_levels[75] = level_entries[74]
        _verify_boss_level_source(
            boss_levels[75],
            75,
            LEVEL_75_SHEET_IDS,
            [1, 1, 613, 904, 10],
            LEVEL_75_AUTHORED_LEVEL_PAYLOAD_SHA256,
            [4, 5, 6, 7, 7],
        )
        boss_levels[100] = level_entries[99]
        _verify_boss_level_source(
            boss_levels[100],
            100,
            LEVEL_100_SHEET_IDS,
            [1, 1, 500, 904, 10],
            LEVEL_100_AUTHORED_LEVEL_PAYLOAD_SHA256,
            [4, 5, 6, 6, 7, 7],
        )
    sprites = _load_json(sprites_path)
    expected_sprite_version = {3: 4, 4: 5, 5: 6, 6: 7, 7: 8, 8: 9, 9: 10, 10: 11}[
        levels_version
    ]
    if (
        sprites.get("version") != expected_sprite_version
        or sprites.get("schema")
        != f"warblade.sprite-frames.v{expected_sprite_version}"
    ):
        raise BossContractError(
            f"levels.json v{levels_version} boss extraction requires "
            f"sprite_frames.json v{expected_sprite_version}"
        )
    sheet_by_id = {
        sheet.get("id"): sheet
        for sheet in sprites.get("enemy_sheets", [])
        if isinstance(sheet, dict)
    }
    required_sheet_ids = SHEET_IDS + (LEVEL_50_SHEET_IDS if levels_version >= 6 else [])
    if levels_version >= 8:
        required_sheet_ids += LEVEL_75_SHEET_IDS + LEVEL_100_SHEET_IDS
    for sheet_id in required_sheet_ids:
        sheet = sheet_by_id.get(sheet_id)
        if not isinstance(sheet, dict):
            raise BossContractError(f"sprite catalog is missing {sheet_id}")
        if (sheet.get("sheet_width"), sheet.get("sheet_height")) != (576, 96):
            raise BossContractError(f"{sheet_id} geometry changed")
    return levels_version, boss_levels


def _apply_authored_v4_metadata(
    contract: dict[str, Any], level: dict[str, Any]
) -> None:
    authored = level["authored_lvd"]
    groups = authored["groups"]
    burst_groups = []
    for group in groups:
        if group["group_mode_id"] != 6:
            continue
        enemies = group["enemies"]
        if not enemies:
            raise BossContractError(
                f"level {level['id']} burst group {group['id']} has no records"
            )
        speed = enemies[0]["base_health"] / 10.0
        burst_groups.append(
            {
                "group_id": group["id"],
                "group_mode_id": 6,
                "authored_record_count": len(enemies),
                "record_order": "reverse",
                "reverse_records": True,
                "speed_from_first_health_divisor": 10,
                "speed": speed,
            }
        )
    if not burst_groups or len({entry["speed"] for entry in burst_groups}) != 1:
        raise BossContractError(
            f"level {level['id']} burst groups must share one authored speed"
        )
    contract["initialization"].update(
        {
            "mirror_x": authored["mirror_x"],
            "fixed_record_0_raw_words": authored[
                "fixed_table_records_raw_words"
            ][0],
            "supplemental_record_0_raw_words": authored[
                "supplemental_spawn_records_raw_words"
            ][0],
        }
    )
    contract["opcode_2"].update(
        {
            "dynamic_record_count": sum(
                entry["authored_record_count"] for entry in burst_groups
            ),
            "speed": burst_groups[0]["speed"],
            "burst_groups": burst_groups,
        }
    )
    contract["path"]["group_opcode_sequences"] = {
        str(group["id"]): [point["opcode"] for point in group["path_points"]]
        for group in groups
    }
    contract["aimed_fire"]["origin_groups"] = [
        {
            "group_id": group["id"],
            "path_opcodes": [point["opcode"] for point in group["path_points"]],
        }
        for group in groups
        if group["group_mode_id"] == 7
    ]


def _late_boss_contract(
    base: dict[str, Any],
    *,
    level_id: int,
    sheet_ids: list[str],
    health: int,
    timer: int,
    timer_step: int,
    reward_tail_score: int,
    opcode_allowlist: list[int],
    aimed_bounds: list[list[int] | None],
    aimed_pixels: list[int],
    burst_bounds: list[list[int] | None],
    burst_pixels: list[int],
) -> dict[str, Any]:
    contract = copy.deepcopy(base)
    contract["id"] = f"retail_big_boss_level_{level_id}_v1"
    contract["level_id"] = level_id
    contract["resources"]["sheet_ids"] = sheet_ids
    contract["rendering"]["normal_handles"] = sheet_ids
    contract["rendering"]["hit_flash_handles"] = [
        f"{sheet_id}_mask" for sheet_id in sheet_ids
    ]
    contract["health"]["retail"] = health
    contract["projectile_allocation"]["enemy_sheet_id"] = sheet_ids[0]
    contract["projectile_allocation"]["mask_id"] = sheet_ids[0]
    contract["aimed_fire"].update(
        {
            "timer": timer,
            "authored_timer_initial": timer,
            "runtime_timer_initial": timer,
            "runtime_rng_upper": timer,
            "timer_a_step": timer_step,
            "hma_occupied_bounds": aimed_bounds,
            "hma_occupied_pixels": aimed_pixels,
        }
    )
    contract["opcode_2"].update(
        {
            "hma_occupied_bounds": burst_bounds,
            "hma_occupied_pixels": burst_pixels,
        }
    )
    contract["path"]["opcode_allowlist"] = opcode_allowlist
    if 3 not in opcode_allowlist:
        contract["path"].pop("opcode_3", None)
    if 6 in opcode_allowlist:
        contract["path"]["opcode_6"] = "deactivate"
    contract["reward"].update(
        {
            "tail_score": reward_tail_score,
            "base_score": reward_tail_score * 1000,
        }
    )
    for key in list(contract["routing"]):
        if key.startswith("explicit_end_level_"):
            contract["routing"].pop(key)
    contract["routing"][f"explicit_end_level_{level_id}_policy"] = (
        f"complete_without_requesting_level_{level_id + 1}"
    )
    contract["routing"]["extended_campaign_policy"] = (
        f"request_get_ready_level_{level_id + 1}_once"
        if level_id < 100
        else "reject_level_101_out_of_catalog"
    )
    return contract


def build_document(
    exe_path: Path = DEFAULT_EXE,
    levels_path: Path = DEFAULT_LEVELS,
    sprites_path: Path = DEFAULT_SPRITES,
) -> dict[str, Any]:
    levels_version, boss_levels = _verify_sources(
        exe_path, levels_path, sprites_path
    )
    authored_payload_sha256 = _authored_payload_sha256(boss_levels[25])
    document = {
        "version": 2,
        "schema": "warblade.bosses.v2",
        "bosses": {
            "retail_big_boss_v1": {
                "id": "retail_big_boss_v1",
                "level_id": 25,
                "level_mode_id": 4,
                "executable_sha256": EXECUTABLE_SHA256,
                "retail_state_id": 13,
                "exact_trace_complete": True,
                "authored_level_payload": {
                    "canonicalization": AUTHORED_PAYLOAD_CANONICALIZATION,
                    "sha256": authored_payload_sha256,
                },
                "resources": {
                    "slots": list(range(1, 7)),
                    "sheet_ids": SHEET_IDS,
                    "sheet_size": [576, 96],
                },
                "initialization": {
                    "group_modes": [4, 5, 6, 7, 7],
                    "common_projectile_slots": 100,
                    "authored_entity_slots": 150,
                    "position_offset": [-16, -16],
                    "hum_pitch_rng": [15000, 30000],
                    "hum_delta_rng": [-100, 100],
                },
                "animation": {
                    "stage_min": 0,
                    "stage_max": 5,
                    "stage_count": 6,
                    "stage_to_resource_slot": list(range(1, 7)),
                    "period_rng": [2, 5],
                    "countdown_initial": "period",
                    "countdown_step": "subtract_tick_scale",
                    "advance_when": "countdown<0",
                    "advance": 1,
                    "wrap": "5_to_0",
                    "bounce": False,
                    "health_driven": False,
                },
                "rendering": {
                    "part_count": 2,
                    "position_rounding": "trunc_toward_zero",
                    "normal_handles": SHEET_IDS,
                    "hit_flash_handles": [
                        f"{sheet_id}_mask" for sheet_id in SHEET_IDS
                    ],
                    "hit_flash": {
                        "successful_hit_countdown": 5,
                        "selection": "mask_when_nonzero_else_normal",
                        "decrement": "after_each_part_render",
                        "reset": "successful_hit_assigns_5",
                    },
                    "parts": [
                        {
                            "part_index": 0,
                            "source_rect": [0, 0, 256, 64],
                            "destination_offset": [-112, 0],
                            "size": [256, 64],
                        },
                        {
                            "part_index": 1,
                            "source_rect": [256, 0, 256, 64],
                            "destination_offset": [-112, 64],
                            "size": [256, 64],
                        },
                    ],
                },
                "health": {
                    "retail": 300,
                    "balanced_coop_multiplier": 2,
                    "damage_divisor": 10,
                    "minimum_damage": 1,
                    "terminal_hit_below": 0,
                    "death_below": 0,
                },
                "collision": {
                    "anchor_x_offset": -128,
                    "strict_local_bounds": [16, 16, 240, 112],
                    "special_projectile_local_y": 60,
                    "hma_damage_test": False,
                },
                "projectile_allocation": {
                    "common_projectile_slots": 100,
                    "protocol": "reserve_then_finalize",
                    "reserve_callback": "allocate_common_projectile",
                    "finalize_callback": "finalize_common_projectile",
                    "callback_response": {
                        "ok": "required_boolean",
                        "error": "required_string",
                        "pool_full": "ok_true_allocated_false",
                        "callback_failure": "ok_false_stops_encounter",
                    },
                    "retained_response_fields": [
                        "retained_animation_frame",
                        "retained_animation_period",
                        "retained_animation_countdown",
                    ],
                    "pool_full_rng": "none",
                    "finalize_failure": "block_encounter",
                    "position_storage": "32x32_sprite_top_left",
                    "center_offset": [16, 16],
                    "resource_slot_id": 1,
                    "enemy_sheet_id": "alien_big1_1",
                    "mask_id": "alien_big1_1",
                    "update_order": ["animation", "movement", "retirement"],
                    "animation_countdown_step": "subtract_tick_scale",
                    "animation_advance_when": "countdown<0",
                    "movement": "add_spawn_tick_scaled_velocity",
                    "retirement": {
                        "axis": "top_left_y",
                        "comparison": ">surface_height",
                        "default_surface_height": 600,
                        "x_bounds": False,
                        "age_limit": False,
                    },
                    "player_collision": {
                        "fighter_rect_size": [40, 27],
                        "strict_broad_overlap": True,
                        "pixel_policy": "broad_hit_when_pixel_disabled_or_either_mask_null_else_hma",
                        "invalid_hma_bounds": "miss",
                        "on_hit": "consume_and_one_armour_step",
                    },
                },
                "aimed_fire": {
                    "owning_group_mode": 5,
                    "origin_group_mode": 7,
                    "trigger_multiplier": 3,
                    "timer": 904,
                    "travel_rng": [45, 55],
                    "jitter_rng": [-40, 40],
                    "projectile_type": 15,
                    "size": [32, 32],
                    "broadphase_inset": [8, 8],
                    "broadphase": [24, 24],
                    "source_rects": [
                        [0, 64, 32, 32],
                        [32, 64, 32, 32],
                        [64, 64, 32, 32],
                        [96, 64, 32, 32],
                    ],
                    "animation": {
                        "initialization": "retain_common_slot_fields",
                        "frame_wrap": "3_to_0",
                        "source_rect": "[frame*32,64,32,32]_unclamped",
                    },
                    "hma_occupied_bounds": [
                        [11, 12, 20, 21],
                        [11, 12, 20, 21],
                        [11, 12, 20, 20],
                        None,
                    ],
                    "hma_occupied_pixels": [92, 91, 90, 0],
                    "sound_frequency_rng": [28000, 32000],
                },
                "opcode_2": {
                    "source_group_mode": 6,
                    "reverse_records": True,
                    "spawn_offset_y": 48,
                    "speed_from_first_health_divisor": 10,
                    "projectile_type": 14,
                    "size": [32, 32],
                    "broadphase_inset": [4, 4],
                    "broadphase": [28, 28],
                    "source_rects": [
                        [512, 0, 32, 32],
                        [512, 32, 32, 32],
                        [512, 64, 32, 32],
                        [544, 0, 32, 32],
                        [544, 32, 32, 32],
                        [544, 64, 32, 32],
                    ],
                    "animation": {
                        "initial_frame": 0,
                        "period_rng": [1, 4],
                        "countdown_rng": [1, 4],
                        "independent_draws": True,
                        "frame_wrap": "5_to_0",
                    },
                    "hma_occupied_bounds": [
                        [1, 0, 30, 31],
                        [0, 1, 31, 30],
                        [0, 1, 31, 30],
                        [0, 1, 31, 30],
                        [1, 0, 30, 31],
                        [1, 0, 30, 30],
                    ],
                    "hma_occupied_pixels": [571, 573, 571, 568, 569, 571],
                    "projectile_sound_frequency_rng": [24000, 30000],
                    "deferred_projectile_sound": {
                        "sample": "alienshoot2",
                        "overwrite": "last_allocated_wins",
                        "flush_order": "after_bigfire_later_same_main_tick",
                        "flush_gate": "alternating_global_sound_tick",
                        "flush_gate_initial": 4,
                        "flush_gate_lifetime": "match_process_not_level",
                        "flush_gate_step": "old_then_decrement;old==0_sets_1_and_flushes",
                        "closed_gate": "discard_at_next_enemy_update",
                        "spatial_source": "final_projectile_top_left",
                        "spatial_lookup": "FUN_00627530_then_af6048",
                        "x_clamp_uses_surface_height": True,
                    },
                    "burst_sound_frequency_rng": [28000, 32000],
                },
                "path": {
                    "opcode_allowlist": [0, 1, 2, 7],
                    "loop_ease": 0.9599999785423279,
                    "crossing": "trunc(progress)>duration",
                    "opcode_7": "ease_to_anchor_then_restart_mode_5",
                },
                "death": {
                    "explosion_count_rng": [8, 15],
                    "explosion_y_rng": [-32, 32],
                    "explosion_x_rng": [64, 192],
                    "explosion_effect": "FUN_00570420",
                    "post_effects": [
                        "FUN_00571080",
                        "FUN_005e0650",
                        "FUN_005e0650",
                        "FUN_0052f440",
                    ],
                    "post_effect_count": 500,
                    "plume_count": 2,
                    "plume_y_float_rng": [0, 96],
                    "plume_x_float_rng": [0, 224],
                    "plume_particle_count_rng": [50, 100],
                    "plume_effect": "FUN_005defe0",
                    "sfx_cooldown_rng": [40, 200],
                    "sfx_pair_fields": [
                        "first_min_argument",
                        "first_max_argument",
                        "frequency_min_argument",
                        "frequency_max_argument",
                    ],
                    "first_pair_range_semantics": "unsigned_reversed_bound_retail_bug",
                    "sfx_pairs": [
                        [216, 190, 35000, 44100],
                        [216, 190, 30000, 40000],
                        [216, 190, 25000, 30000],
                    ],
                },
                "reward": {
                    "tail_score": 500,
                    "retail_scale": 1000,
                    "base_score": 500000,
                    "marks_level_complete": True,
                    "stops_hum": True,
                    "rank_markers_unchanged": True,
                    "destroyed_count": {
                        "killer_delta": 1,
                        "classic_coop_partner_delta": 1,
                        "completion_condition": "destroyed_plus_partner>=authored_total",
                        "completion_timestamp": "set_if_zero",
                    },
                    "ordinary_completion_bonus_and_rockets": True,
                },
                "routing": {
                    "completion_mark_timing": "inside FUN_00585840 collision",
                    "dispatcher_poll_timing": "same tick after FUN_00605fe0 + render",
                    "retail_next_level_intent": True,
                    "campaign_wrapper_policy": "configured_end_level",
                    "explicit_end_level_25_policy": "complete_without_requesting_level_26",
                    "extended_campaign_policy": "request_get_ready_level_26_once",
                },
                "effects": {
                    "policy": "synchronous_root_rng_callback",
                    "callback_required": True,
                    "progression_inputs": {
                        "only_blue_coins_active": "selected_physical_player_persistent_boolean",
                        "rank_ready": "projectile_owner_physical_seat_persistent_boolean",
                    },
                    "progression_producers": {
                        "rank_ready": {
                            "storage": "DAT_008487b4",
                            "initialization": "0x006245a2",
                            "set_function": "FUN_0055f650",
                            "set_case": "0x0d",
                            "set_address": "0x00565094",
                            "set_condition": (
                                "all_six_rank_bits_already_set_and_once_per_shop_"
                                "reward_succeeds_and_DAT_00848ba8_is_false"
                            ),
                            "state_13_samples": [
                                "0x005860a7",
                                "0x00588340",
                                "0x0058a2fc",
                            ],
                        },
                        "only_blue_coins_active": {
                            "storage": "DAT_008489d4",
                            "initialization": "0x00624487",
                            "persisted_hydration_function": "FUN_00549460",
                            "persisted_score_condition": ">19999",
                            "persisted_hydration_address": "0x005495ec",
                            "runtime_set_function": "FUN_00571c60",
                            "runtime_set_condition": (
                                "third_type_0_sucker_or_blue_money_pickup"
                            ),
                            "runtime_set_address": "0x00578b90",
                            "state_13_sample_function": "FUN_00571080",
                            "state_13_sample_address": "0x0057116e",
                        },
                    },
                    "death_order": [
                        "FUN_00570420_each",
                        "deactivate_boss",
                        "FUN_00571080",
                        "FUN_005e0650_left",
                        "FUN_005e0650_right",
                        "FUN_0052f440",
                        "FUN_005defe0_first",
                        "FUN_005defe0_second",
                        "death_sound_triple",
                        "score_popup",
                        "level_complete_mark",
                        "stop_hum",
                    ],
                },
                "sounds": {
                    "music": "boss",
                    "hum": "boss",
                    "hit": "hit1",
                    "terminal_hit": "hit2",
                    "death": "explo4",
                    "aimed_projectile": "bigsmall",
                    "opcode_2_deferred": "alienshoot2",
                    "opcode_2_direct": "bigfire",
                },
                "effect_runtime": _effect_runtime_contract(),
                "evidence": {
                    "init": "0x00569260",
                    "update": "0x00605fe0",
                    "collision": "0x00585840",
                    "mark": "0x00555c40",
                    "dispatcher": "0x005afc50",
                    "renderer": "0x00618560",
                    "projectile_type_15_spawn": "0x00612fc7-0x006132bf",
                    "projectile_type_14_spawn": "0x00614031-0x006143cf",
                    "common_projectile_update": "0x006027e3-0x00602de0",
                    "projectile_renderer": "0x00603808/0x00603b32",
                    "projectile_player_collision": "0x005842c0",
                    "projectile_hma_collision": "0x00625a50",
                    "global_sound_gate_thunk": "0x00525924->0x00567990",
                    "global_sound_gate_dispatch_calls": (
                        "0x005b0c72/0x005b0d96/0x005b10ac/0x005b1191/0x005b1280"
                    ),
                    "get_ready_to_level_transitions": "0x005abac2/0x005abfc0",
                    "warp_to_shop_transitions": (
                        "0x0061bce8/0x0061be78/0x0061c082"
                    ),
                    "rank_ready_storage_and_initialization": (
                        "DAT_008487b4@0x006245a2"
                    ),
                    "rank_ready_shop_producer": "0x00565094",
                    "rank_ready_state_13_samples": (
                        "0x005860a7/0x00588340/0x0058a2fc"
                    ),
                    "only_blue_storage_and_initialization": (
                        "DAT_008489d4@0x00624487"
                    ),
                    "only_blue_persisted_hydration": "0x005495ec",
                    "only_blue_runtime_producer": "0x00578b90",
                    "only_blue_state_13_sample": "0x0057116e",
                },
            }
        },
    }
    if levels_version < 6:
        return document

    document["version"] = 3
    document["schema"] = "warblade.bosses.v3"
    level_25_contract = document["bosses"]["retail_big_boss_v1"]
    level_25_contract["aimed_fire"].update(
        {
            "timer_a_step": 10,
            "timer_a_step_application": "kill_pass_tightening_only",
            "timer_a_step_active_effect": (
                "inert_state_13_is_sole_active_entity_and_deactivates_before_"
                "terminal_tightening"
            ),
        }
    )
    level_25_contract["path"]["point_zero_opcode_dispatch"] = False

    level_50_contract = copy.deepcopy(level_25_contract)
    level_50_contract["id"] = "retail_big_boss_level_50_v1"
    level_50_contract["level_id"] = 50
    level_50_contract["authored_level_payload"]["sha256"] = (
        _authored_payload_sha256(boss_levels[50])
    )
    level_50_contract["resources"]["sheet_ids"] = LEVEL_50_SHEET_IDS
    level_50_contract["rendering"]["normal_handles"] = LEVEL_50_SHEET_IDS
    level_50_contract["rendering"]["hit_flash_handles"] = [
        f"{sheet_id}_mask" for sheet_id in LEVEL_50_SHEET_IDS
    ]
    level_50_contract["health"]["retail"] = 500
    level_50_contract["projectile_allocation"]["enemy_sheet_id"] = (
        LEVEL_50_SHEET_IDS[0]
    )
    level_50_contract["projectile_allocation"]["mask_id"] = (
        LEVEL_50_SHEET_IDS[0]
    )
    level_50_contract["aimed_fire"].update(
        {
            "timer": 1377,
            "authored_timer_initial": 1377,
            "runtime_timer_initial": 1377,
            "runtime_rng_upper": 1377,
            "timer_a_step": 8,
            "hma_occupied_bounds": [
                [11, 12, 20, 21],
                [2, 0, 20, 21],
                [5, 0, 20, 21],
                None,
            ],
            "hma_occupied_pixels": [92, 94, 97, 0],
        }
    )
    level_50_contract["opcode_2"].update(
        {
            "hma_occupied_bounds": [
                [2, 2, 29, 29],
                [2, 2, 29, 29],
                [2, 2, 29, 29],
                [2, 2, 29, 29],
                [2, 2, 29, 29],
                [2, 2, 29, 29],
            ],
            "hma_occupied_pixels": [646, 645, 645, 645, 645, 645],
            "dynamic_record_count": 10,
            "speed": 5.0,
        }
    )
    level_50_contract["path"]["opcode_allowlist"] = [0, 1, 2, 3, 7]
    level_50_contract["path"]["opcode_3"] = {
        "effect": "set_mode_7_aim_enabled",
        "rng_draws": 0,
        "loads_acceleration": False,
        "resets_progress": False,
    }
    level_50_contract["reward"].update(
        {
            "tail_score": 1000,
            "base_score": 1000000,
        }
    )
    level_50_contract["routing"].pop("explicit_end_level_25_policy")
    level_50_contract["routing"]["explicit_end_level_50_policy"] = (
        "complete_without_requesting_level_51"
    )
    level_50_contract["routing"]["extended_campaign_policy"] = (
        "request_get_ready_level_51_once"
    )
    document["bosses"][level_50_contract["id"]] = level_50_contract
    if levels_version < 8:
        return document

    document["version"] = 4
    document["schema"] = "warblade.bosses.v4"
    level_75_contract = _late_boss_contract(
        level_50_contract,
        level_id=75,
        sheet_ids=LEVEL_75_SHEET_IDS,
        health=613,
        timer=904,
        timer_step=10,
        reward_tail_score=5000,
        opcode_allowlist=[0, 1, 2, 3, 7],
        aimed_bounds=[
            [9, 0, 20, 21],
            [9, 0, 20, 20],
            [11, 12, 21, 21],
            None,
        ],
        aimed_pixels=[95, 91, 100, 0],
        burst_bounds=[
            [0, 0, 31, 31],
            [1, 1, 31, 31],
            [1, 1, 31, 30],
            [2, 0, 31, 31],
            [1, 1, 31, 31],
            [0, 0, 30, 30],
        ],
        burst_pixels=[441, 469, 487, 494, 496, 479],
    )
    level_75_contract["authored_level_payload"]["sha256"] = (
        _authored_payload_sha256(boss_levels[75])
    )
    level_75_contract["initialization"]["group_modes"] = [4, 5, 6, 7, 7]

    level_100_contract = _late_boss_contract(
        level_50_contract,
        level_id=100,
        sheet_ids=LEVEL_100_SHEET_IDS,
        health=500,
        timer=904,
        timer_step=10,
        reward_tail_score=10000,
        opcode_allowlist=[0, 1, 2, 6, 7],
        aimed_bounds=[
            [11, 12, 20, 21],
            [11, 12, 20, 20],
            [11, 12, 20, 21],
            [7, 0, 20, 20],
        ],
        aimed_pixels=[91, 90, 97, 87],
        burst_bounds=[
            [0, 0, 30, 31],
            [0, 0, 31, 31],
            [0, 0, 31, 31],
            [0, 0, 31, 31],
            [0, 0, 31, 31],
            [1, 0, 31, 31],
        ],
        burst_pixels=[671, 588, 773, 698, 659, 661],
    )
    level_100_contract["authored_level_payload"]["sha256"] = (
        _authored_payload_sha256(boss_levels[100])
    )
    level_100_contract["initialization"]["group_modes"] = [4, 5, 6, 6, 7, 7]

    contracts_by_level = {
        25: level_25_contract,
        50: level_50_contract,
        75: level_75_contract,
        100: level_100_contract,
    }
    for level_id, contract in contracts_by_level.items():
        _apply_authored_v4_metadata(contract, boss_levels[level_id])
    document["bosses"][level_75_contract["id"]] = level_75_contract
    document["bosses"][level_100_contract["id"]] = level_100_contract

    document["version"] = 5
    document["schema"] = "warblade.bosses.v5"
    for contract in document["bosses"].values():
        contract["health"]["endless_step_additive"] = ENDLESS_STEP_HEALTH_ADDITIVE
        contract["health"]["endless_step_evidence"] = {
            "consumer_va_range": ["0x0056b52f", "0x0056b546"],
            "formula": "authored_base + int(step_additive_float * 20.0)",
            "step_additive_float_per_step": 5.0,
            "per_hundred_health": ENDLESS_STEP_HEALTH_ADDITIVE,
            "source": "docs/evidence/ENDLESS_PROGRESSION.md",
        }
    return document


def _json_text(document: dict[str, Any]) -> str:
    return json.dumps(document, indent=2, ensure_ascii=False) + "\n"


def _evidence_text(document: dict[str, Any]) -> str:
    artifact_hash = _sha256(_json_text(document).encode("utf-8"))
    contract = document["bosses"]["retail_big_boss_v1"]
    evidence = contract["evidence"]
    contract_lines = []
    for boss_contract in document["bosses"].values():
        level_id = boss_contract["level_id"]
        contract_lines.extend(
            [
                f"- Level-{level_id} contract: `{boss_contract['id']}`",
                (
                    f"- Canonical level-{level_id} authored payload SHA-256: "
                    f"`{boss_contract['authored_level_payload']['sha256']}`"
                ),
            ]
        )
    return "\n".join(
        [
            "# Retail big boss state 13",
            "",
            *contract_lines,
            f"- Executable SHA-256: `{contract['executable_sha256']}`",
            f"- Generated `bosses.json` SHA-256: `{artifact_hash}`",
            "- Source encounters: levels 25, 50, and 75 use LVD mode 4 with group modes `4,5,6,7,7`; mirrored level 100 uses `4,5,6,6,7,7`.",
            "- Trace status: exact and complete; runtime loading must reject a false or missing `exact_trace_complete` gate.",
            "",
            "## Pinned trace entry points",
            "",
            "| Role | Virtual address |",
            "|---|---:|",
            *[
                f"| {role.replace('_', ' ')} | `{address}` |"
                for role, address in evidence.items()
            ],
            "",
            "All `*_rng` arrays record the retail half-open call arguments unless a field says otherwise. The first two arguments in every death SFX tuple are deliberately retained as the retail unsigned reversed-bound bug (`216,190`); they are not normalized or reordered.",
            "",
            "The authoritative JSON preserves each encounter's six animation sheets, exact two-part packed renderer and per-part hit-flash countdown, state-13 collision and attack constants, exact death event ordering, destroyed-count completion mark, unchanged rank-marker policy, and reward scale. Its v4 routing contracts separate retail next-level intent from configured campaign boundaries at 25, 50, 75, and 100. Level 50 pins opcode 3, the 1,377 aimed-fire timer, ten dynamic opcode-2 records at speed 5.0, and Big2 HMA bounds. Level 75 pins 613 health, a 5,000,000-point reward, one reverse 16-record burst at speed 4.6, and group-3/4 aimed origins. Mirrored level 100 pins a 10,000,000-point reward, two reverse four-record bursts at speed 7.5, opcode-6 terminal paths, group-4/5 aimed origins, and rejection of level 101. The contracts also pin the retail-high effect preset, all five bounded pool capacities and update order, plus the per-physical-player `rank_ready` and `only_blue_coins_active` RNG branches. The gameplay-critical closure list is empty.",
            "",
        ]
    )


def _check_or_write(path: Path, text: str, check: bool) -> None:
    if check:
        if not path.is_file() or path.read_text(encoding="utf-8") != text:
            raise BossContractError(f"{path} is stale; regenerate boss contracts")
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Generate the exact retail state-13 boss contract.")
    parser.add_argument("--exe", type=Path, default=DEFAULT_EXE)
    parser.add_argument("--levels", type=Path, default=DEFAULT_LEVELS)
    parser.add_argument("--sprites", type=Path, default=DEFAULT_SPRITES)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--evidence", type=Path, default=DEFAULT_EVIDENCE)
    parser.add_argument("--check", action="store_true")
    return parser


def main() -> int:
    args = _build_parser().parse_args()
    try:
        document = build_document(args.exe, args.levels, args.sprites)
        _check_or_write(args.output, _json_text(document), args.check)
        _check_or_write(args.evidence, _evidence_text(document), args.check)
    except (BossContractError, OSError, json.JSONDecodeError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    if args.check:
        print("boss contract and evidence are current")
    else:
        print("generated exact retail state-13 boss contract and evidence")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
