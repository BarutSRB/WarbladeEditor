#!/usr/bin/env python3

import hashlib
import json
import struct
from pathlib import Path

from swd_content_extract import build_document as build_swd_content
from bonus_modes_extract import (
    build_document as build_bonus_modes_content,
    mode_three_level_aliases,
)
from sprite_atlas_extract import build_document as build_sprite_frames_content
from boss_contract_extract import build_document as build_boss_contract_content


ROOT = Path(__file__).resolve().parents[1]
CONTENT = ROOT / "content"
ASSETS = ROOT / "assets" / "original"
MANIFEST = ROOT / "docs" / "evidence" / "provenance_manifest.json"
FACTS = ROOT / "tools" / "known_facts.json"
ALLOWLIST = ROOT / "tools" / "pac_allowlist.json"
RETAIL_EXECUTABLE_SHA256 = "ddf1778c307af1087ff9dcb512786111e665d972298aeaac3f1b4b2996d079ef"
BONUS_WEIGHTS = [
    45, 45, 45, 45, 45, 111, 53, 90, 90, 130, 130, 65, 80, 80, 80, 20,
    140, 20, 60, 35, 50, 25, 35, 35, 35, 5, 25, 10, 15, 300, 150, 75, 30,
    8, 10, 15, 20,
]
BONUS_SOURCE_Y = [
    60, 80, 100, 120, 140, 20, 460, 160, 180, 280, 300, 40, 340, 320, 360,
    240, 380, 400, 260, 420, 0, 500, 520, 540, 560, 660, 440, 200, 480, 600,
    580, 620, 640, 220, 700, 680, 720,
]
BONUS_EFFECT_KEYS = [
    "letter_e", "letter_x", "letter_t", "letter_r", "letter_a",
    "mystery", "memory_station", "score_x2", "score_x5", "extra_bullet",
    "extra_speed", "shield", "single", "double", "triple", "warp", "scoop",
    "quad", "auto_fire", "gem_bomb", "meteor_storm", "armour",
    "sucker_blue_money", "sucker_gem_counter", "sucker_meteor_multiplier",
    "mirror", "money_bomb", "extra_life", "extra_time", "money_10",
    "money_50", "money_100", "money_200", "money_doubler", "drunk_mode",
    "freeze", "extra_bullet_speed",
]


def load_json(path):
    with path.open("r", encoding="utf-8") as stream:
        return json.load(stream)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def require_int(value, label, minimum=None):
    require(type(value) is int, f"{label} must be an integer")
    if minimum is not None:
        require(value >= minimum, f"{label} must be >= {minimum}")


def require_string(value, label):
    require(isinstance(value, str) and value, f"{label} must be a non-empty string")


def reject_floats(value, label):
    if isinstance(value, float):
        raise ValueError(f"{label} contains a floating-point value")
    if isinstance(value, dict):
        for key, child in value.items():
            reject_floats(child, f"{label}.{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            reject_floats(child, f"{label}[{index}]")


def contains_unresolved(value):
    if isinstance(value, str):
        return value.strip().lower() == "unresolved"
    if isinstance(value, dict):
        return any(contains_unresolved(child) for child in value.values())
    if isinstance(value, list):
        return any(contains_unresolved(child) for child in value)
    return False


def unique_ids(items, label):
    ids = [item["id"] for item in items]
    require(len(ids) == len(set(ids)), f"{label} contains duplicate IDs")
    return ids


def validate_weapons(data):
    require(data.get("version") == 1, "weapons.json has unsupported version")
    require(
        data.get("fire_control")
        == {
            "manual_fire": "edge_latched",
            "auto_fire_repeat_delay_ms": 100,
            "super_auto_fire_repeat_delay_ms": 25,
            "deadline_comparison": "strict_greater_than",
        },
        "weapons fire-control contract diverges from executable evidence",
    )
    weapons = data.get("weapons")
    require(isinstance(weapons, list), "weapons must be an array")
    require(unique_ids(weapons, "weapons") == list(range(9)), "weapon IDs must be 0 through 8")
    required = {"id", "name", "damage_fp", "sound", "projectiles"}
    projectile_required = {
        "prototype_id",
        "offset_x_fp",
        "offset_y_fp",
        "velocity_x_fp",
        "velocity_y_fp",
        "width",
        "height",
    }
    for weapon in weapons:
        require(required <= weapon.keys(), f"weapon {weapon.get('id')} is missing required fields")
        require_int(weapon["id"], "weapon.id", 0)
        require_string(weapon["name"], "weapon.name")
        require_int(weapon["damage_fp"], "weapon.damage_fp", 1)
        require_string(weapon["sound"], "weapon.sound")
        require(isinstance(weapon["projectiles"], list) and weapon["projectiles"], "weapon projectiles must not be empty")
        prototype_ids = []
        for projectile in weapon["projectiles"]:
            require(projectile_required <= projectile.keys(), "projectile is missing required fields")
            for field in projectile_required:
                require_int(projectile[field], f"projectile.{field}")
            if "special_secondary_raw" in projectile:
                require_int(
                    projectile["special_secondary_raw"],
                    "projectile.special_secondary_raw",
                    161,
                )
            require(projectile["width"] > 0 and projectile["height"] > 0, "projectile dimensions must be positive")
            prototype_ids.append(projectile["prototype_id"])
        require(len(prototype_ids) == len(set(prototype_ids)), "weapon contains duplicate projectile prototypes")


def bonus_reroll_gate(random_max_argument):
    return {
        "kind": "random_result_below_active_player_progression",
        "random_min_argument": 0,
        "random_max_argument": random_max_argument,
        "comparison": "strict_less_than",
        "active_player_progression_base_va": "0x008487bc",
        "active_player_stride_bytes": 1240,
    }


def validate_bonuses(data):
    require(data.get("version") == 1, "bonuses.json has unsupported version")
    require(
        data.get("schema") == "warblade.bonuses.v1",
        "bonuses.json has unsupported schema",
    )
    require(
        data.get("source_executable_sha256") == RETAIL_EXECUTABLE_SHA256,
        "bonuses.json executable provenance is missing or unsupported",
    )
    require(
        data.get("source")
        == {
            "spawn_function_va": "0x0056ff10",
            "collection_switch_va": "0x00571c60",
            "selection_weight_table_va": "0x007d0700",
            "source_x_table_va": "0x00e11910",
            "source_y_table_va": "0x007d07b0",
            "height_table_va": "0x007d0860",
            "width_table_va": "0x007d0910",
            "frame_count_table_va": "0x007d09a8",
            "logical_type_table_va": "0x007d0a40",
        },
        "bonuses source-table provenance diverges from executable evidence",
    )
    spawn_contract = {
        "pool_slots": 150,
        "selection_total_weight": 2252,
        "weighted_roll_min_argument": 0,
        "weighted_roll_max_adjustment": -1,
        "x_jitter_min_argument": 0,
        "x_jitter_max_argument": 6,
        "x_jitter_offset": -3,
        "animation_period_min": 3,
        "animation_period_max": 7,
        "initial_phase_min_argument": 0,
        "initial_phase_max_argument": 5,
        "initial_phase_offset": 2,
    }
    require(
        data.get("spawn_contract") == spawn_contract,
        "bonuses spawn contract diverges from executable evidence",
    )
    bonuses = data.get("bonuses")
    require(isinstance(bonuses, list) and len(bonuses) == 37, "bonuses must contain 37 logical types")
    require(all(isinstance(bonus, dict) for bonus in bonuses), "bonus entries must be objects")
    require(unique_ids(bonuses, "bonuses") == list(range(37)), "bonus IDs must be 0 through 36")
    required = {
        "id", "effect_id", "effect_key", "weight", "source_x", "source_y", "width",
        "height", "frame_count",
    }
    for index, bonus in enumerate(bonuses):
        require(required <= bonus.keys(), f"bonus {index} is missing required fields")
        for field in required - {"effect_key"}:
            require_int(bonus[field], f"bonus.{field}")
        require_string(bonus["effect_key"], "bonus.effect_key")
        require(bonus["effect_id"] == index, "bonus effect IDs must be contiguous")
        require(
            bonus["effect_key"] == BONUS_EFFECT_KEYS[index],
            f"bonus {index} effect key is unsupported",
        )
        require(
            bonus["weight"] == BONUS_WEIGHTS[index],
            f"bonus {index} weight diverges from executable evidence",
        )
        require(
            bonus["source_x"] == 0 and bonus["source_y"] == BONUS_SOURCE_Y[index],
            f"bonus {index} source position diverges from executable evidence",
        )
        require(
            (bonus["width"], bonus["height"], bonus["frame_count"]) == (20, 20, 10),
            f"bonus {index} frame geometry diverges from executable evidence",
        )
        if 12 <= index <= 14:
            require(
                bonus.get("reroll_gate") == bonus_reroll_gate([50, 150, 300][index - 12]),
                f"bonus {index} reroll gate diverges from executable evidence",
            )
        else:
            require("reroll_gate" not in bonus, f"bonus {index} has an unsupported reroll gate")
    require(
        sum(bonus["weight"] for bonus in bonuses) == spawn_contract["selection_total_weight"],
        "bonus selection weights do not match their executable total",
    )


def validate_levels(data):
    version = data.get("version")
    require(
        version in (1, 2, 3, 4, 5, 6, 7, 8, 9, 10),
        "levels.json has unsupported version",
    )
    if version >= 2:
        require(
            data.get("schema") == f"warblade.levels.v{version}",
            "levels.json has unsupported schema",
        )
    levels = data.get("levels")
    require(isinstance(levels, list), "levels must be an array")
    expected_level_count = {
        1: 20, 2: 25, 3: 30, 4: 35, 5: 49,
        6: 50, 7: 62, 8: 100, 9: 100, 10: 100,
    }[version]
    require(
        unique_ids(levels, "levels") == list(range(1, expected_level_count + 1)),
        f"level IDs must be 1 through {expected_level_count}",
    )
    required = {
        "id",
        "title",
        "author",
        "enemy_sprite",
        "ordinary_kill_score",
        "shop_after",
        "waves",
    }
    wave_required = {
        "start_tick",
        "count",
        "columns",
        "spawn_x",
        "spawn_y",
        "spacing_x",
        "spacing_y",
        "health_fp",
        "speed_fp",
        "path",
        "fire_interval_ticks",
        "projectile_speed_fp",
        "score",
        "cash",
    }
    for level in levels:
        require(required <= level.keys(), f"level {level.get('id')} is missing required fields")
        for field in ("title", "author"):
            require(isinstance(level[field], str), f"level.{field} must be a string")
        require_string(level["enemy_sprite"], "level.enemy_sprite")
        require_int(level["ordinary_kill_score"], "level.ordinary_kill_score", 0)
        if version >= 9:
            require(
                level.get("authored_runtime") == {"ordinary_speed_fp": 65536},
                "levels v9 must declare the exact source-backed authored runtime speed",
            )
        else:
            require(
                "authored_runtime" not in level,
                "predecessor levels cannot declare v9 authored runtime defaults",
            )
        if version >= 2:
            resources = level.get("enemy_resources")
            require(
                isinstance(resources, list) and resources,
                "level enemy_resources must be a nonempty array",
            )
            expected_resource_fields = {
                "resource_slot_id",
                "raw_name",
                "enemy_sheet_id",
                "kill_score",
            }
            for resource_index, resource in enumerate(resources, start=1):
                require(
                    isinstance(resource, dict)
                    and set(resource) == expected_resource_fields,
                    "level enemy resources must contain the exact fields",
                )
                require_int(
                    resource["resource_slot_id"],
                    "level enemy resource slot",
                    1,
                )
                require(
                    resource["resource_slot_id"] == resource_index,
                    "level enemy resources must be ordered by contiguous slot ID",
                )
                require_string(resource["raw_name"], "level enemy resource raw name")
                require_string(
                    resource["enemy_sheet_id"],
                    "level enemy resource sheet ID",
                )
                require_int(resource["kill_score"], "level enemy resource kill score", 0)
            require(
                level["enemy_sprite"] == resources[0]["enemy_sheet_id"]
                and level["ordinary_kill_score"] == resources[0]["kill_score"],
                "level scalar enemy aliases must equal resource slot 1",
            )
        require(type(level["shop_after"]) is bool, "shop_after must be boolean")
        require_string(level.get("raw_lvd"), "level.raw_lvd")
        require_string(level.get("raw_lvd_sha256"), "level.raw_lvd_sha256")
        raw_lvd = ROOT / level["raw_lvd"].removeprefix("res://")
        require(raw_lvd.is_file(), f"missing raw LVD: {level['raw_lvd']}")
        require(sha256_file(raw_lvd) == level["raw_lvd_sha256"], f"raw LVD SHA-256 mismatch: {level['id']}")
        validate_authored_lvd(level.get("authored_lvd"), level["id"], version)
        require(isinstance(level["waves"], list) and level["waves"], "level waves must not be empty")
        for wave in level["waves"]:
            require(wave_required <= wave.keys(), "wave is missing required fields")
            require_string(wave["path"], "wave.path")
            for field in wave_required - {"path"}:
                require_int(wave[field], f"wave.{field}")
            require(wave["count"] > 0 and wave["columns"] > 0, "wave count and columns must be positive")
            require(wave["health_fp"] > 0 and wave["speed_fp"] > 0, "wave health and speed must be positive")
            require(wave["fire_interval_ticks"] > 0, "wave fire interval must be positive")
    if version >= 2:
        level_24 = levels[23]
        require(
            level_24["authored_lvd"]["level_mode_id"] == 3
            and sum(
                len(group["enemies"])
                for group in level_24["authored_lvd"]["groups"]
            )
            == 30
            and level_24["shop_after"] is True,
            "level 24 must preserve its exact mode-3, 30-target, shop contract",
        )
        require(
            [group["group_mode_id"] for group in levels[24]["authored_lvd"]["groups"]]
            == [4, 5, 6, 7, 7],
            "level 25 authored group-mode signature drift",
        )
    if version >= 3:
        level_28 = levels[27]
        require(
            level_28["shop_after"] is True
            and level_28["authored_lvd"]["supplemental_spawn_records_raw_words"][0]
            == [2, 1, 30, 560, 7]
            and level_28["authored_lvd"]["fixed_table_records_raw_words"][0]
            == [4, 0, 0, 0],
            "level 28 must preserve its shop and two four-phase supplementals",
        )
        require(
            [resource["kill_score"] for resource in levels[29]["enemy_resources"]]
            == [500, 600],
            "level 30 resource-specific scores drift",
        )
    if version >= 4:
        level_32 = levels[31]
        require(
            level_32["shop_after"] is True
            and level_32["authored_lvd"]["supplemental_spawn_records_raw_words"][0]
            == [3, 1, 40, 1076, 30]
            and level_32["authored_lvd"]["fixed_table_records_raw_words"][0]
            == [4, 0, 0, 0],
            "level 32 must preserve its shop and three four-phase supplementals",
        )
        level_33 = levels[32]
        level_33_resource_counts = {1: 0, 2: 0}
        for group in level_33["authored_lvd"]["groups"]:
            for enemy in group["enemies"]:
                slot_id = enemy["resource_slot_id"]
                require(
                    slot_id in level_33_resource_counts,
                    "level 33 target references an unsupported resource slot",
                )
                level_33_resource_counts[slot_id] += 1
        require(
            level_33["authored_lvd"]["level_mode_id"] == 3
            and level_33_resource_counts == {1: 15, 2: 15}
            and [resource["kill_score"] for resource in level_33["enemy_resources"]]
            == [500, 600]
            and level_33["shop_after"] is False,
            "level 33 must preserve its mixed-resource mode-three target contract",
        )
        require(
            [
                sum(len(group["enemies"]) for group in level["authored_lvd"]["groups"])
                for level in levels[30:35]
            ]
            == [28, 18, 30, 30, 36],
            "levels 31 through 35 authored target counts drift",
        )
        require(
            [resource["kill_score"] for resource in levels[33]["enemy_resources"]]
            == [450, 550]
            and [resource["kill_score"] for resource in levels[34]["enemy_resources"]]
            == [450, 550],
            "levels 34 and 35 resource-specific scores drift",
        )
    if version >= 5:
        require(
            [level["id"] for level in levels if level["shop_after"]]
            == (
                list(range(4, 101, 4))
                if version >= 8
                else (
                    [4, 8, 12, 16, 20, 24, 28, 32, 36, 40, 44, 48, 52, 56, 60]
                    if version == 7
                    else [4, 8, 12, 16, 20, 24, 28, 32, 36, 40, 44, 48]
                )
            ),
            "late-campaign shop boundaries diverge from the retail cadence",
        )
        expected_supplemental = {
            36: [
                ([2, 2, 40, 818, 10], [4, 1, 0, 0]),
                ([1, 1, 59, 968, 14], [4, 1, 0, 0]),
            ],
            40: [([4, 1, 40, 818, 10], [4, 0, 0, 0])],
            44: [([4, 2, 79, 968, 19], [4, 1, 0, 0])],
            48: [([4, 1, 50, 1054, 13], [4, 1, 0, 0])],
        }
        for level_id, records in expected_supplemental.items():
            authored = levels[level_id - 1]["authored_lvd"]
            for record_index, (raw_words, fixed_words) in enumerate(records):
                require(
                    authored["supplemental_spawn_records_raw_words"][record_index]
                    == raw_words
                    and authored["fixed_table_records_raw_words"][record_index]
                    == fixed_words,
                    f"level {level_id} supplemental record {record_index} drift",
                )
        require(
            [
                sum(len(group["enemies"]) for group in level["authored_lvd"]["groups"])
                for level in levels[35:49]
            ]
            == [48, 36, 36, 40, 30, 40, 60, 40, 52, 30, 90, 60, 90, 40],
            "levels 36 through 49 authored target counts drift",
        )
        expected_late_resources = {
            36: (["alien_green_lilla_t", "alien_cyan_lilla_t"], [450, 550]),
            37: (["alien_green_lilla_t", "alien_cyan_lilla_t"], [450, 550]),
            38: (["alien_raudkule", "alien_cyan_lilla_t"], [500, 550]),
            39: (["alien_raudkule", "alien_raudkule2"], [500, 550]),
            40: (["alien_raudkule", "alien_raudkule2"], [500, 550]),
            41: (["alien_raudkule", "alien_raudkule2"], [500, 550]),
            42: (["alien_blavinger_gf", "alien_raudkule2"], [600, 550]),
            43: (["alien_blavinger_gf", "alien_raudkule2"], [600, 550]),
            44: (["alien_blavinger_gf", "alien_blavinger_gf2"], [600, 750]),
            45: (["alien_blavinger_gf2"], [200]),
            46: (["alien_rbille"], [800]),
            47: (["alien_rbille"], [850]),
            48: (["alien_rbille"], [850]),
            49: (["alien_rbille"], [750]),
        }
        for level_id, (sheet_ids, scores) in expected_late_resources.items():
            resources = levels[level_id - 1]["enemy_resources"]
            require(
                [resource["enemy_sheet_id"] for resource in resources] == sheet_ids
                and [resource["kill_score"] for resource in resources] == scores,
                f"level {level_id} resource binding or score drift",
            )
        for level_id in (41, 49):
            level = levels[level_id - 1]
            require(
                level["authored_lvd"]["level_mode_id"] == 3
                and sum(
                    len(group["enemies"])
                    for group in level["authored_lvd"]["groups"]
                )
                == 40
                and level["shop_after"] is False,
                f"level {level_id} must preserve its 40-target mode-three contract",
            )
    if version >= 6:
        level_50 = levels[49]
        authored = level_50["authored_lvd"]
        require(
            authored["level_mode_id"] == 4
            and [group["group_mode_id"] for group in authored["groups"]]
            == [4, 5, 6, 7, 7]
            and sum(len(group["enemies"]) for group in authored["groups"]) == 14,
            "level 50 must preserve its mode-4 state-13 group contract",
        )
        require(
            authored["supplemental_spawn_records_raw_words"][0]
            == [1, 1, 500, 1377, 8]
            and authored["fixed_table_records_raw_words"][0] == [6, 0, 0, 0],
            "level 50 state-13 initialization record drift",
        )
        require(
            [resource["enemy_sheet_id"] for resource in level_50["enemy_resources"]]
            == [f"alien_big2_{index}" for index in range(1, 7)]
            and [resource["kill_score"] for resource in level_50["enemy_resources"]]
            == [0, 0, 0, 0, 0, 0],
            "level 50 Big2 resource binding or score drift",
        )
    if version >= 7:
        expected_late_resources = {
            51: (["alien_gultop"], [1000]),
            52: (["alien_gultop"], [1000]),
            53: (["alien_gultop", "alien_lillatop"], [1000, 1200]),
            54: (["alien_gultop", "alien_rakett_gronn"], [500, 400]),
            55: (["alien_bluekreps", "alien_lbluekreps", "alien_brownkreps"], [750, 800, 1000]),
            56: (["alien_bluekreps", "alien_lbluekreps", "alien_brownkreps"], [750, 800, 1000]),
            57: (["alien_bluekreps", "alien_lbluekreps", "alien_brownkreps"], [750, 800, 1000]),
            58: (["alien_brownkreps2", "alien_gulkreps"], [500, 500]),
            59: (["alien_rvinggk", "alien_rvinggk"], [750, 750]),
            60: (["alien_rvinggk", "alien_gvingbk"], [750, 750]),
            61: (["alien_rvinggk", "alien_gvingbk"], [750, 750]),
            62: (["alien_gvingbk"], [500]),
        }
        for level_id, (sheet_ids, scores) in expected_late_resources.items():
            resources = levels[level_id - 1]["enemy_resources"]
            require(
                [resource["enemy_sheet_id"] for resource in resources] == sheet_ids
                and [resource["kill_score"] for resource in resources] == scores,
                f"level {level_id} resource binding or score drift",
            )
        require(
            [
                sum(len(group["enemies"]) for group in level["authored_lvd"]["groups"])
                for level in levels[50:62]
            ] == [76, 120, 30, 36, 60, 126, 110, 80, 40, 46, 22, 25],
            "levels 51 through 62 authored target counts drift",
        )
        expected_supplemental = {
            53: [
                ([2, 1, 59, 925, 8], [4, 0, 0, 0]),
                ([2, 1, 79, 1054, 22], [4, 0, 0, 0]),
            ],
            57: [([4, 3, 98, 1441, 7], [4, 1, 0, 0])],
            61: [([4, 1, 88, 1162, 23], [4, 1, 0, 0])],
        }
        for level_id, records in expected_supplemental.items():
            authored = levels[level_id - 1]["authored_lvd"]
            for record_index, (raw_words, fixed_words) in enumerate(records):
                require(
                    authored["supplemental_spawn_records_raw_words"][record_index]
                    == raw_words
                    and authored["fixed_table_records_raw_words"][record_index]
                    == fixed_words,
                    f"level {level_id} supplemental record {record_index} drift",
                )
        level_58 = levels[57]
        require(
            level_58["authored_lvd"]["level_mode_id"] == 3
            and sum(
                len(group["enemies"])
                for group in level_58["authored_lvd"]["groups"]
            ) == 80
            and level_58["shop_after"] is False,
            "level 58 must preserve its 80-target mode-three contract",
        )
    if version >= 8:
        require(
            data.get("level_mode_runtime")
            == {
                "6": {
                    "entry_state_id": 2,
                    "special_mode_classifier": False,
                    "ordinary_projectile_aim": {
                        "enabled": True,
                        "horizontal_speed_magnitude_rng_fp": [0, 98304],
                        "direction": "toward_active_player_x_side",
                        "tick_scale_applied": True,
                    },
                    "ordinary_projectile_vertical_speed": {
                        "base_multiplier_fp": 65536,
                        "accelerated_multiplier_fp": 81920,
                        "accelerated_when_level_strictly_above": 500,
                    },
                    "terminal_opcode_6": "deactivate",
                    "setup_flags": {
                        "aimed_shots": "0x008f201d",
                        "accelerated_shots": "0x008f201e",
                    },
                    "evidence": {
                        "level_mode_global_va": "0x00a95c20",
                        "setup_dispatch_region": "level_mode_setup_dispatch",
                        "setup_jump_table_region": "level_mode_setup_jump_table",
                        "terminal_dispatch_region": "path_terminal_dispatch",
                        "terminal_jump_table_region": "path_terminal_jump_table",
                        "aim_and_speed_consumer_region": "ordinary_projectile_aim_and_speed",
                    },
                }
            },
            "level-mode 6 runtime contract drift",
        )
        expected_modes = {
            63: 6, 64: 6, 65: 6, 66: 3, 67: 6, 68: 6, 69: 6,
            70: 2, 71: 6, 72: 6, 73: 6, 74: 3, 75: 4, 76: 6,
            77: 6, 78: 1, 79: 2, 80: 1, 81: 1, 82: 1, 83: 3,
            84: 1, 85: 1, 86: 1, 87: 2, 88: 6, 89: 6, 90: 6,
            91: 3, 92: 6, 93: 6, 94: 1, 95: 2, 96: 1, 97: 1,
            98: 1, 99: 3, 100: 4,
        }
        expected_target_counts = {
            63: 127, 64: 100, 65: 75, 66: 60, 67: 128, 68: 128,
            69: 26, 70: 35, 71: 78, 72: 68, 73: 56, 74: 84,
            75: 20, 76: 112, 77: 90, 78: 60, 79: 50, 80: 90,
            81: 100, 82: 80, 83: 90, 84: 140, 85: 60, 86: 96,
            87: 54, 88: 30, 89: 48, 90: 80, 91: 20, 92: 144,
            93: 123, 94: 80, 95: 60, 96: 116, 97: 60, 98: 45,
            99: 80, 100: 12,
        }
        for level_id in range(63, 101):
            authored = levels[level_id - 1]["authored_lvd"]
            require(
                authored["level_mode_id"] == expected_modes[level_id]
                and sum(len(group["enemies"]) for group in authored["groups"])
                == expected_target_counts[level_id],
                f"level {level_id} mode or authored target count drift",
            )
        expected_supplemental = {
            65: [([2, 1, 110, 1484, 14], [4, 1, 0, 0]), ([2, 2, 110, 1570, 14], [4, 1, 0, 0])],
            69: [([4, 1, 108, 1119, 17], [4, 1, 0, 0])],
            73: [([5, 1, 110, 1291, 10], [4, 1, 0, 0])],
            78: [([4, 1, 98, 1742, 26], [4, 1, 0, 0])],
            82: [([5, 1, 300, 1600, 5], [4, 1, 0, 0])],
            86: [([4, 1, 72, 710, 18], [4, 0, 0, 0])],
            90: [([3, 2, 118, 1398, 25], [7, 1, 0, 0])],
            94: [([4, 1, 118, 968, 23], [7, 1, 0, 0])],
            98: [([10, 3, 150, 2000, 10], [6, 1, 0, 0])],
        }
        for level_id, records in expected_supplemental.items():
            authored = levels[level_id - 1]["authored_lvd"]
            for record_index, (raw_words, fixed_words) in enumerate(records):
                require(
                    authored["supplemental_spawn_records_raw_words"][record_index]
                    == raw_words
                    and authored["fixed_table_records_raw_words"][record_index]
                    == fixed_words,
                    f"level {level_id} supplemental record {record_index} drift",
                )
        require(
            [group["group_mode_id"] for group in levels[74]["authored_lvd"]["groups"]]
            == [4, 5, 6, 7, 7]
            and [group["group_mode_id"] for group in levels[99]["authored_lvd"]["groups"]]
            == [4, 5, 6, 6, 7, 7],
            "late state-13 boss group-mode signatures drift",
        )


def validate_authored_lvd(authored, level_id, catalog_version=1):
    require(isinstance(authored, dict), f"level {level_id} is missing authored_lvd")
    require(
        authored.get("schema") == "warblade.lvd.authored.v2",
        f"level {level_id} has unsupported authored_lvd schema",
    )
    require(
        isinstance(authored.get("source_title_cp1252"), str),
        "authored_lvd source title must be a string",
    )
    require_int(authored.get("level_mode_id"), "authored_lvd.level_mode_id")
    if catalog_version >= 7 and level_id >= 51:
        require(
            authored["level_mode_id"] in ((1, 2, 3, 4, 6) if catalog_version >= 8 else (1, 2, 3)),
            "late authored level mode is outside the supported set",
        )
    require(authored.get("logical_width") == 800, "authored_lvd logical width must be 800")
    require(
        authored.get("mirror_x") is bool((level_id // 100) & 1),
        "authored_lvd mirror flag does not match the level number",
    )
    supplemental = authored.get("supplemental_spawn_records_raw_words")
    require(
        isinstance(supplemental, list) and len(supplemental) == 5,
        "authored_lvd must contain five supplemental records",
    )
    for record in supplemental:
        require(
            isinstance(record, list) and len(record) == 5,
            "authored_lvd supplemental records must contain five words",
        )
        for word in record:
            require_int(word, "authored_lvd supplemental word")
    fixed_records = authored.get("fixed_table_records_raw_words")
    require(
        isinstance(fixed_records, list) and len(fixed_records) == 50,
        "authored_lvd must contain fifty fixed-table records",
    )
    for record in fixed_records:
        require(
            isinstance(record, list) and len(record) == 4,
            "authored_lvd fixed-table records must contain four words",
        )
        for word in record:
            require_int(word, "authored_lvd fixed-table word")
    groups = authored.get("groups")
    require(
        isinstance(groups, list) and 1 <= len(groups) <= 25,
        "authored_lvd group count must be between 1 and 25",
    )
    group_fields = {
        "id",
        "entry_origin_x",
        "entry_origin_y",
        "first_activation_delay_ticks",
        "activation_stagger_ticks",
        "initial_velocity_x_milli",
        "initial_velocity_y_milli",
        "kill_cohort_id",
        "group_mode_id",
    }
    enemy_fields = {
        "id",
        "formation_target_x",
        "formation_target_y",
        "resource_slot_id",
        "base_health",
        "behavior_timer_a_initial",
        "behavior_timer_a_step",
        "behavior_timer_b_initial",
        "behavior_timer_b_step",
    }
    path_fields = {
        "id",
        "acceleration_x_milli",
        "acceleration_y_milli",
        "opcode",
        "unknown_0c",
        "duration_threshold_ticks",
    }
    for group_index, group in enumerate(groups):
        require(isinstance(group, dict), "authored group must be an object")
        for field in group_fields:
            require_int(group.get(field), f"authored group.{field}")
        require(group["id"] == group_index, "authored group IDs must be contiguous")
        require(
            group["first_activation_delay_ticks"] >= 0
            and group["activation_stagger_ticks"] >= 0,
            "authored group activation delays must be nonnegative",
        )
        require(group["kill_cohort_id"] >= 0, "authored group kill cohort must be nonnegative")
        enemies = group.get("enemies")
        require(
            isinstance(enemies, list) and 1 <= len(enemies) <= 50,
            "authored enemy count must be between 1 and 50",
        )
        for enemy_index, enemy in enumerate(enemies):
            require(isinstance(enemy, dict), "authored enemy must be an object")
            for field in enemy_fields:
                require_int(enemy.get(field), f"authored enemy.{field}")
            require(enemy["id"] == enemy_index, "authored enemy IDs must be contiguous")
            minimum_resource_slot = (
                0
                if catalog_version >= 2 and level_id == 25
                or catalog_version >= 6 and level_id == 50
                or catalog_version >= 8 and level_id in (75, 100)
                else 1
            )
            require(
                minimum_resource_slot <= enemy["resource_slot_id"] <= 6,
                "authored enemy resource slot is outside the supported range",
            )
            require(enemy["base_health"] > 0, "authored enemy base health must be positive")
        points = group.get("path_points")
        minimum_path_count = (
            0
            if catalog_version >= 2 and level_id == 25
            or catalog_version >= 6 and level_id == 50
            or catalog_version >= 8 and level_id in (75, 100)
            else 1
        )
        require(
            isinstance(points, list) and minimum_path_count <= len(points) <= 150,
            "authored path count is outside the supported range",
        )
        for point_index, point in enumerate(points):
            require(isinstance(point, dict), "authored path point must be an object")
            for field in path_fields:
                require_int(point.get(field), f"authored path point.{field}")
            require(point["id"] == point_index, "authored path point IDs must be contiguous")
            supported_opcodes = {0, 1, 6}
            if catalog_version >= 8 and level_id == 100:
                supported_opcodes = {0, 1, 2, 3, 6, 7}
            elif catalog_version >= 8 and level_id in (75, 94):
                supported_opcodes = {0, 1, 2, 3, 6, 7}
            elif catalog_version >= 2 and level_id == 25:
                supported_opcodes = {0, 1, 2, 7}
            elif catalog_version >= 6 and level_id == 50:
                supported_opcodes = {0, 1, 2, 3, 7}
            require(
                point["opcode"] in supported_opcodes,
                "authored path opcode is unsupported by the content contract",
            )
            require(
                point["duration_threshold_ticks"] >= 0,
                "authored path duration must be nonnegative",
            )


def validate_shop(data):
    require(data.get("version") == 1, "shop.json has unsupported version")
    items = data.get("items")
    require(isinstance(items, list), "shop items must be an array")
    require(unique_ids(items, "shop") == list(range(1, 22)), "shop IDs must be 1 through 21")
    effects = {
        "speed_up",
        "bullet_capacity_up",
        "equip_weapon",
        "speed_down",
        "enable_autofire",
        "armor_up",
        "life_up",
        "buy_secret",
        "rank_marker_up",
        "bonus_time_up",
        "rocket_pack",
        "enable_alien_lock",
        "enable_super_autofire",
        "clear_profile_shields",
    }
    gates = {"always", "hit_percent_above_level_25", "all_profile_shields"}
    for item in items:
        for field in ("id", "name", "price", "category", "effect", "unlock"):
            require(field in item, f"shop item {item.get('id')} is missing {field}")
        require_int(item["id"], "shop.id", 1)
        require_string(item["name"], "shop.name")
        require_int(item["price"], "shop.price", 0)
        require_string(item["category"], "shop.category")
        require(item["effect"] in effects, f"unsupported shop effect: {item['effect']}")
        if "weapon_id" in item:
            require_int(item["weapon_id"], "shop.weapon_id", 0)
            require(item["weapon_id"] <= 8, "shop weapon_id must be 0 through 8")
        unlock = item["unlock"]
        require(isinstance(unlock, dict), "shop unlock must be an object")
        require(unlock.get("kind") in gates, f"unsupported shop gate: {unlock.get('kind')}")
        require_int(unlock.get("threshold"), "shop.unlock.threshold", 0)


def validate_difficulties(data):
    require(data.get("version") == 4, "difficulties.json has unsupported version")
    difficulties = data.get("difficulties")
    require(isinstance(difficulties, list), "difficulties must be an array")
    require(
        unique_ids(difficulties, "difficulties") == ["easy", "normal", "hard", "ace"],
        "difficulty IDs must be easy, normal, hard, ace",
    )
    fields = {
        "simulation_scale_numerator",
        "simulation_scale_denominator",
        "timer_a_initial_adjustment",
        "timer_a_floor",
        "timer_b_initial_adjustment",
        "timer_b_floor",
        "alien_projectile_speed_numerator",
        "alien_projectile_speed_denominator",
        "player_base_speed_numerator",
        "player_base_speed_denominator",
        "player_speed_upgrade_numerator",
        "player_speed_upgrade_denominator",
        "special_health_base_a",
        "special_health_base_b",
        "special_health_base_c",
        "special_health_base_d",
        "special_speed_maximum",
        "debris_lifetime_base",
        "debris_lifetime_range",
        "debris_speed_minimum_milli",
        "debris_speed_maximum_milli",
        "debris_steering_threshold",
    }
    expected = {
        "easy": (6, 400, 300, 210, 252, 48),
        "normal": (6, 200, 200, 258, 240, 42),
        "hard": (7, -50, 190, 350, 210, 36),
        "ace": (8, -200, 180, 440, 180, 30),
    }
    # Hurry-up special-ship bases, docs/evidence/HURRY_UP_SECRET_SHIPS.md.
    expected_special = {
        "easy": (10, 300, 75, 1500, 3),
        "normal": (16, 350, 100, 1750, 4),
        "hard": (20, 450, 125, 2000, 5),
        "ace": (25, 600, 150, 2500, 6),
    }
    expected_debris = {
        "easy": (200, 200, 2400, 3200, 50),
        "normal": (200, 225, 3100, 3800, 40),
        "hard": (210, 230, 3300, 4300, 30),
        "ace": (220, 235, 3500, 4800, 20),
    }
    for difficulty in difficulties:
        require_string(difficulty["name"], "difficulty.name")
        for field in fields:
            require_int(difficulty.get(field), f"difficulty.{field}")
        require(
            difficulty["simulation_scale_denominator"] == 6,
            "difficulty simulation scale denominator must be six",
        )
        for field in (
            "simulation_scale_numerator",
            "timer_a_floor",
            "timer_b_floor",
            "alien_projectile_speed_numerator",
            "alien_projectile_speed_denominator",
            "player_base_speed_numerator",
            "player_base_speed_denominator",
            "player_speed_upgrade_numerator",
            "player_speed_upgrade_denominator",
            "special_health_base_a",
            "special_health_base_b",
            "special_health_base_c",
            "special_health_base_d",
            "special_speed_maximum",
            "debris_lifetime_base",
            "debris_lifetime_range",
            "debris_speed_minimum_milli",
            "debris_speed_maximum_milli",
            "debris_steering_threshold",
        ):
            require(difficulty[field] > 0, f"difficulty.{field} must be positive")
        require(
            (
                difficulty["simulation_scale_numerator"],
                difficulty["timer_a_initial_adjustment"],
                difficulty["timer_a_floor"],
                difficulty["alien_projectile_speed_numerator"],
                difficulty["player_base_speed_numerator"],
                difficulty["player_speed_upgrade_numerator"],
            )
            == expected[difficulty["id"]],
            f"difficulty {difficulty['id']} diverges from executable evidence",
        )
        require(
            difficulty["timer_b_initial_adjustment"]
            == difficulty["timer_a_initial_adjustment"]
            and difficulty["timer_b_floor"] == difficulty["timer_a_floor"],
            f"difficulty {difficulty['id']} timer A/B rules diverge",
        )
        require(
            difficulty["alien_projectile_speed_denominator"] == 60
            and difficulty["player_base_speed_denominator"] == 60
            and difficulty["player_speed_upgrade_denominator"] == 60,
            f"difficulty {difficulty['id']} rational denominators must be sixty",
        )
        require(
            (
                difficulty["special_health_base_a"],
                difficulty["special_health_base_b"],
                difficulty["special_health_base_c"],
                difficulty["special_health_base_d"],
                difficulty["special_speed_maximum"],
            )
            == expected_special[difficulty["id"]],
            f"difficulty {difficulty['id']} special-ship bases diverge from evidence",
        )
        require(
            (
                difficulty["debris_lifetime_base"],
                difficulty["debris_lifetime_range"],
                difficulty["debris_speed_minimum_milli"],
                difficulty["debris_speed_maximum_milli"],
                difficulty["debris_steering_threshold"],
            )
            == expected_debris[difficulty["id"]],
            f"difficulty {difficulty['id']} debris rules diverge from evidence",
        )


def validate_sprites(data):
    require(data.get("version") == 1, "sprites.json has unsupported version")
    sprites = data.get("sprites")
    require(isinstance(sprites, list) and sprites, "sprites must be a non-empty array")
    unique_ids(sprites, "sprites")
    for sprite in sprites:
        require_string(sprite["id"], "sprite.id")
        require_string(sprite["texture"], "sprite.texture")
        require_int(sprite["image_width"], "sprite.image_width", 1)
        require_int(sprite["image_height"], "sprite.image_height", 1)
        texture = ROOT / sprite["texture"].removeprefix("res://")
        require(texture.is_file(), f"missing sprite texture: {sprite['texture']}")
        if texture.suffix.lower() == ".tga":
            header = texture.read_bytes()[:18]
            require(len(header) == 18, f"truncated TGA header: {sprite['texture']}")
            width, height = struct.unpack_from("<HH", header, 12)
            require(width == sprite["image_width"], f"sprite width mismatch: {sprite['id']}")
            require(height == sprite["image_height"], f"sprite height mismatch: {sprite['id']}")
        if "mask" in sprite:
            mask = ROOT / sprite["mask"].removeprefix("res://")
            require(mask.is_file(), f"missing sprite mask: {sprite['mask']}")
            if mask.suffix.lower() == ".tga":
                header = mask.read_bytes()[:18]
                require(len(header) == 18, f"truncated mask TGA header: {sprite['mask']}")
                width, height = struct.unpack_from("<HH", header, 12)
                require(width == sprite["image_width"], f"mask width mismatch: {sprite['id']}")
                require(height == sprite["image_height"], f"mask height mismatch: {sprite['id']}")
        if "hit_mask" in sprite:
            hit_mask = ROOT / sprite["hit_mask"].removeprefix("res://")
            require(hit_mask.is_file(), f"missing hit mask: {sprite['hit_mask']}")
            require(
                hit_mask.stat().st_size == sprite["image_width"] * sprite["image_height"],
                f"HMA byte count mismatch: {sprite['id']}",
            )


def validate_sprite_frames(data):
    version = data.get("version")
    require(
        version in (2, 3, 4, 5, 6, 7, 8, 9, 10, 11),
        "sprite_frames.json has unsupported version",
    )
    latest_sprite_frames = build_sprite_frames_content() if version >= 9 else None
    require(
        data.get("schema") == f"warblade.sprite-frames.v{version}",
        "sprite_frames.json has unsupported schema",
    )
    layout = data.get("enemy_frame_layout")
    require(isinstance(layout, dict), "sprite_frames enemy layout must be an object")
    require(
        len(layout.get("direction_slope_ranges", [])) == 9,
        "sprite_frames must contain nine direction ranges",
    )
    require(
        layout.get("mirror_index_table") == list(range(8, 16)) + list(range(8)),
        "sprite_frames mirror table diverges from executable evidence",
    )
    expected_family_counts = {
        "directional_32": 16,
        "formation_animation_32": 6,
        "supplemental_large_animation_64": 7,
    }
    families = layout.get("families")
    require(isinstance(families, dict), "sprite_frames families must be an object")
    for family_id, expected_count in expected_family_counts.items():
        family = families.get(family_id)
        require(isinstance(family, dict), f"missing sprite family {family_id}")
        frames = family.get("frames")
        require(
            isinstance(frames, list) and len(frames) == expected_count,
            f"sprite family {family_id} has the wrong frame count",
        )
        for frame in frames:
            rect = frame.get("source_rect")
            require(isinstance(rect, dict), "enemy source rectangle must be an object")
            for field in ("x", "y", "width", "height"):
                require_int(rect.get(field), f"enemy source rectangle.{field}", 0)
            require(rect["width"] > 0 and rect["height"] > 0, "enemy rectangle must be positive")
            require(
                rect["x"] + rect["width"] <= 576
                and rect["y"] + rect["height"] <= 96,
                "enemy source rectangle is outside its atlas",
            )
            require(
                rect == frame.get("hit_mask_rect"),
                "enemy texture and HMA rectangles must match",
            )
    fighters = data.get("fighter_sheets")
    require(
        isinstance(fighters, list) and [fighter.get("id") for fighter in fighters] == ["fighter1", "fighter2"],
        "sprite_frames must contain both fighter sheets",
    )
    for fighter in fighters:
        require(fighter.get("sheet_width") == 440, "fighter sheet width must be 440")
        require(fighter.get("sheet_storage_height") == 28, "fighter sheet height must be 28")
        require(fighter.get("effective_frame_height") == 27, "fighter effective height must be 27")
        frames = fighter.get("frames")
        require(isinstance(frames, list) and len(frames) == 11, "fighter must contain eleven frames")
        for frame_index, frame in enumerate(frames):
            require(
                frame.get("source_rect")
                == {"x": frame_index * 40, "y": 0, "width": 40, "height": 27},
                "fighter source rectangle diverges from executable evidence",
            )
    projectile_sheet = data.get("projectile_sheet")
    require(isinstance(projectile_sheet, dict), "projectile sheet must be an object")
    require(
        projectile_sheet.get("sheet_width") == 672
        and projectile_sheet.get("sheet_height") == 100,
        "projectile atlas dimensions are wrong",
    )
    projectile_frames = projectile_sheet.get("frames")
    require(isinstance(projectile_frames, list) and projectile_frames, "projectile frames must not be empty")
    prototype_ids = [frame.get("prototype_id") for frame in projectile_frames]
    require(len(prototype_ids) == len(set(prototype_ids)), "projectile frame prototypes must be unique")
    reachable_prototypes = {
        projectile["prototype_id"]
        for weapon in load_json(CONTENT / "weapons.json")["weapons"]
        for projectile in weapon["projectiles"]
    }
    facts = load_json(FACTS)
    for definition in facts["weapons"]["definitions"]:
        reachable_prototypes.update(
            definition.get("captive_flattened_prototype_ids", [])
        )
    frame_by_id = {
        frame["prototype_id"]: frame
        for frame in projectile_frames
    }
    pending = list(reachable_prototypes)
    while pending:
        prototype_id = pending.pop()
        require(
            prototype_id in frame_by_id,
            f"sprite-frame catalog is missing projectile {prototype_id}",
        )
        next_id = frame_by_id[prototype_id].get("next_prototype_id")
        require_int(next_id, "projectile next_prototype_id", -1)
        require(
            isinstance(frame_by_id[prototype_id].get("persistent"), bool),
            "projectile persistent flag must be boolean",
        )
        if next_id >= 0 and next_id not in reachable_prototypes:
            reachable_prototypes.add(next_id)
            pending.append(next_id)
    require(
        set(prototype_ids) == reachable_prototypes,
        "sprite-frame projectile closure must match fighter and captive graphs",
    )
    for frame in projectile_frames:
        rect = frame.get("source_rect")
        require(isinstance(rect, dict), "projectile source rectangle must be an object")
        for field in ("x", "y", "width", "height"):
            require_int(rect.get(field), f"projectile source rectangle.{field}", 0)
        require(
            rect["width"] > 0
            and rect["height"] > 0
            and rect["x"] + rect["width"] <= 672
            and rect["y"] + rect["height"] <= 100,
            "projectile source rectangle is outside its atlas",
        )
        require(
            rect == frame.get("hit_mask_rect"),
            "projectile texture and HMA rectangles must match",
        )
    enemy_sheets = data.get("enemy_sheets")
    legacy_sheet_ids = ["alien001", "alien_2", "alien_3", "alien000", "alien_lilla"]
    expected_sheet_ids = list(legacy_sheet_ids)
    if version >= 3:
        expected_sheet_ids.extend(
            [
                "alien003",
                "alien003_3",
                "alien_big1_1",
                "alien_big1_2",
                "alien_big1_3",
                "alien_big1_4",
                "alien_big1_5",
                "alien_big1_6",
            ]
        )
    if version >= 4:
        expected_sheet_ids.extend(
            [
                "alien_rakett",
                "alien_rakett_gronn",
                "alien_baller",
                "alien_baller2",
            ]
        )
    if version >= 5:
        expected_sheet_ids.extend(
            [
                "alien_green_lilla_t",
                "alien_cyan_lilla_t",
            ]
        )
    if version >= 6:
        expected_sheet_ids.extend(
            [
                "alien_raudkule",
                "alien_raudkule2",
                "alien_blavinger_gf",
                "alien_blavinger_gf2",
                "alien_rbille",
            ]
        )
    if version >= 7:
        expected_sheet_ids.extend(
            [f"alien_big2_{index}" for index in range(1, 7)]
        )
    if version == 8:
        expected_sheet_ids.extend(
            [
                "alien_gultop",
                "alien_lillatop",
                "alien_bluekreps",
                "alien_lbluekreps",
                "alien_brownkreps",
                "alien_brownkreps2",
                "alien_gulkreps",
                "alien_rvinggk",
                "alien_gvingbk",
            ]
        )
    if version >= 9:
        expected_sheet_ids = [
            sheet["id"] for sheet in latest_sprite_frames["enemy_sheets"]
        ]
    require(
        isinstance(enemy_sheets, list)
        and [sheet.get("id") for sheet in enemy_sheets] == expected_sheet_ids,
        "sprite_frames enemy sheets must follow the supported retail order",
    )
    for sheet in enemy_sheets:
        require_string(sheet.get("texture"), "enemy sheet texture")
        require_string(sheet.get("hit_mask"), "enemy sheet hit mask")
        require(
            sheet.get("sheet_width") == 576 and sheet.get("sheet_height") == 96,
            "enemy sheet geometry must be 576x96",
        )
        if version >= 3:
            require(
                sheet.get("frame_width") == 576
                and sheet.get("frame_height") == 96,
                "enemy HMA frame geometry must be 576x96",
            )
        texture = ROOT / sheet["texture"].removeprefix("res://")
        hit_mask = ROOT / sheet["hit_mask"].removeprefix("res://")
        require(texture.is_file(), f"missing enemy texture: {sheet['texture']}")
        require(hit_mask.is_file(), f"missing enemy hit mask: {sheet['hit_mask']}")
        require(hit_mask.stat().st_size == 576 * 96, "enemy HMA byte count mismatch")
    usage = data.get("level_usage")
    expected_level_count = {
        2: 20, 3: 25, 4: 30, 5: 35, 6: 49,
        7: 50, 8: 62, 9: 100, 10: 100, 11: 100,
    }[version]
    require(
        isinstance(usage, list)
        and [entry.get("level_id") for entry in usage]
        == list(range(1, expected_level_count + 1)),
        f"sprite_frames must map levels one through {expected_level_count}",
    )
    require(
        [entry.get("enemy_sheet_id") for entry in usage]
        == (
            [entry["enemy_sheet_id"] for entry in latest_sprite_frames["level_usage"]]
            if version >= 9
            else (
            [
            "alien001", "alien001", "alien001", "alien001",
            "alien_2", "alien_2", "alien_2", "alien_2",
            "alien_3", "alien_3", "alien_3", "alien_3",
            "alien000", "alien000", "alien000", "alien000",
            "alien_lilla", "alien_lilla", "alien_lilla", "alien_lilla",
        ]
        + (
            ["alien003", "alien003", "alien003", "alien003", "alien_big1_1"]
            if version >= 3
            else []
        )
        + (
            ["alien_rakett", "alien_rakett", "alien_rakett", "alien_rakett", "alien_baller"]
            if version >= 4
            else []
        )
        + (
            ["alien_baller", "alien_baller", "alien_baller", "alien_green_lilla_t", "alien_green_lilla_t"]
            if version >= 5
            else []
        )
        + (
            [
                "alien_green_lilla_t", "alien_green_lilla_t",
                "alien_raudkule", "alien_raudkule", "alien_raudkule", "alien_raudkule",
                "alien_blavinger_gf", "alien_blavinger_gf", "alien_blavinger_gf",
                "alien_blavinger_gf2", "alien_rbille", "alien_rbille", "alien_rbille", "alien_rbille",
            ]
            if version >= 6
            else []
        )
        + (["alien_big2_1"] if version >= 7 else [])
        + (
            [
                "alien_gultop", "alien_gultop", "alien_gultop", "alien_gultop",
                "alien_bluekreps", "alien_bluekreps", "alien_bluekreps",
                "alien_brownkreps2", "alien_rvinggk", "alien_rvinggk",
                "alien_rvinggk", "alien_gvingbk",
            ]
            if version == 8
            else []
        )
        )
        ),
        "enemy sheet mapping diverges from LVD evidence",
    )
    if version >= 3:
        for entry in usage:
            resources = entry.get("enemy_resources")
            require(
                isinstance(resources, list) and resources,
                "sprite level usage must contain enemy resources",
            )
            for resource_index, resource in enumerate(resources, start=1):
                require(
                    isinstance(resource, dict)
                    and resource.get("resource_slot_id") == resource_index,
                    "sprite enemy resources must be ordered by contiguous slot",
                )
                require(
                    resource.get("enemy_sheet_id") in expected_sheet_ids,
                    "sprite enemy resource references an unknown sheet",
                )
            require(
                resources[0].get("enemy_sheet_id") == entry.get("enemy_sheet_id"),
                "sprite level alias must equal resource slot 1",
            )
    supplemental_linkages = data.get("supplemental_spawn_linkages")
    require(
        isinstance(supplemental_linkages, list)
        and [entry.get("level_id") for entry in supplemental_linkages]
        == (
            [entry["level_id"] for entry in latest_sprite_frames["supplemental_spawn_linkages"]]
            if version >= 9
            else (
            [3, 7, 11, 15, 19]
            if version == 2
            else (
                [3, 7, 11, 15, 19, 23]
                if version == 3
                else (
                    [3, 7, 11, 15, 19, 23, 28]
                    if version == 4
                    else (
                        [3, 7, 11, 15, 19, 23, 28, 32]
                        if version == 5
                        else (
                            [3, 7, 11, 15, 19, 23, 28, 32, 36, 36, 40, 44, 48, 53, 53, 57, 61]
                            if version == 8
                            else [3, 7, 11, 15, 19, 23, 28, 32, 36, 36, 40, 44, 48]
                        )
                    )
                )
            ))
        ),
        "supplemental state-6 reachability diverges from LVD evidence",
    )
    if version >= 4:
        for linkage in supplemental_linkages:
            phase_count = linkage.get("animation_phase_count")
            fixed_words = linkage.get("fixed_record_raw_words")
            require_int(phase_count, "supplemental animation phase count", 1)
            require(
                phase_count <= 7
                and linkage.get("valid_animation_phases") == list(range(phase_count))
                and isinstance(fixed_words, list)
                and len(fixed_words) == 4
                and fixed_words[0] == phase_count,
                "supplemental animation phase metadata is invalid",
            )
        expected_terminal_supplemental_level = (
            latest_sprite_frames["supplemental_spawn_linkages"][-1]["level_id"]
            if version >= 9
            else (28 if version == 4 else (32 if version == 5 else (61 if version == 8 else 48)))
        )
        expected_terminal_fixed_words = (
            latest_sprite_frames["supplemental_spawn_linkages"][-1]["fixed_record_raw_words"]
            if version >= 9
            else ([4, 1, 0, 0] if version >= 6 else [4, 0, 0, 0])
        )
        expected_terminal_phases = (
            latest_sprite_frames["supplemental_spawn_linkages"][-1]["valid_animation_phases"]
            if version >= 9
            else [0, 1, 2, 3]
        )
        require(
            supplemental_linkages[-1].get("level_id") == expected_terminal_supplemental_level
            and supplemental_linkages[-1].get("fixed_record_raw_words")
            == expected_terminal_fixed_words
            and supplemental_linkages[-1].get("valid_animation_phases") == expected_terminal_phases,
            f"level {expected_terminal_supplemental_level} supplemental animation phase contract drift",
        )
    enemy_projectiles = data.get("enemy_projectile_contracts")
    require(isinstance(enemy_projectiles, dict), "missing enemy projectile contracts")
    ordinary = enemy_projectiles.get("ordinary_type_7")
    require(isinstance(ordinary, dict), "missing ordinary type-7 projectile contract")
    require(ordinary.get("sound_key") == "alienshoot10", "ordinary alien shot sound drift")
    require(ordinary.get("suppressed_level_modes") == [3], "mode-3 shot suppression drift")
    supplemental_projectile = enemy_projectiles.get("supplemental_state_6_type_6")
    require(isinstance(supplemental_projectile, dict), "missing supplemental type-6 contract")
    require(supplemental_projectile.get("sound_key") == "alienshoot2", "supplemental shot sound drift")
    expected_projectile_masks = {
        "ordinary_type_7": {
            "alien001": [([0, 0, 5, 13], 76), ([0, 0, 5, 13], 76)],
            "alien_2": [([0, 0, 3, 11], 38), ([0, 0, 3, 11], 38)],
            "alien_3": [([0, 0, 5, 12], 71), ([0, 0, 6, 12], 73)],
            "alien000": [([0, 0, 7, 13], 104), ([0, 0, 7, 13], 96)],
            "alien_lilla": [([0, 0, 5, 9], 43), ([0, 0, 5, 9], 42)],
            "alien_raudkule": [([2, 2, 5, 7], 24), ([2, 2, 4, 5], 10)],
            "alien_raudkule2": [([0, 0, 7, 9], 64), ([0, 0, 7, 9], 64)],
            "alien_blavinger_gf": [([2, 2, 7, 7], 20), ([0, 0, 9, 9], 47)],
            "alien_blavinger_gf2": [([2, 2, 7, 7], 20), ([0, 0, 9, 9], 52)],
            "alien_rbille": [([0, 0, 7, 7], 49), ([0, 0, 7, 7], 50)],
            "alien_big2_1": [([0, 0, 28, 31], 857), ([0, 0, 28, 13], 172)],
            "alien_big2_2": [([0, 0, 28, 31], 855), ([0, 0, 28, 13], 169)],
            "alien_big2_3": [([0, 0, 28, 31], 847), ([0, 0, 28, 13], 166)],
            "alien_big2_4": [([0, 0, 28, 31], 836), ([0, 0, 28, 13], 164)],
            "alien_big2_5": [([0, 0, 28, 31], 849), ([0, 0, 28, 13], 167)],
            "alien_big2_6": [([0, 0, 29, 31], 911), ([0, 0, 28, 13], 203)],
            "alien_gultop": [([0, 0, 9, 11], 78), ([0, 0, 9, 11], 78)],
            "alien_lillatop": [([0, 0, 7, 9], 52), ([2, 0, 9, 9], 52)],
            "alien_bluekreps": [([0, 0, 11, 11], 82), ([2, 2, 9, 9], 44)],
            "alien_lbluekreps": [([0, 0, 11, 11], 80), ([0, 0, 11, 11], 80)],
            "alien_brownkreps": [([0, 0, 11, 11], 64), ([0, 0, 11, 11], 80)],
            "alien_brownkreps2": [([0, 0, 11, 11], 81), ([0, 0, 11, 11], 80)],
            "alien_gulkreps": [([0, 0, 11, 11], 80), ([3, 3, 8, 8], 32)],
            "alien_rvinggk": [([0, 0, 13, 13], 119), ([0, 0, 13, 13], 120)],
            "alien_gvingbk": [([0, 0, 13, 13], 100), ([0, 0, 13, 13], 100)],
        },
        "supplemental_state_6_type_6": {
            "alien001": [([0, 1, 11, 12], 72), ([0, 0, 11, 11], 132)],
            "alien_2": [([2, 2, 9, 9], 64), ([0, 0, 11, 11], 144)],
            "alien_3": [([0, 0, 31, 12], 94), ([0, 0, 31, 12], 135)],
            "alien000": [([0, 0, 13, 16], 187), ([0, 0, 13, 16], 186)],
            "alien_lilla": [([0, 0, 11, 11], 69), ([0, 0, 11, 11], 98)],
            "alien_raudkule": [([4, 4, 9, 9], 18), ([0, 0, 17, 17], 276)],
            "alien_raudkule2": [([0, 0, 17, 17], 276), (None, 0)],
            "alien_blavinger_gf": [([0, 0, 13, 13], 132), ([0, 0, 13, 13], 116)],
            "alien_blavinger_gf2": [([0, 0, 13, 13], 56), ([0, 0, 13, 13], 40)],
            "alien_rbille": [([0, 0, 17, 17], 308), ([0, 0, 17, 17], 309)],
            "alien_big2_1": [([0, 0, 31, 31], 1024), ([0, 0, 31, 14], 388)],
            "alien_big2_2": [([0, 0, 31, 31], 1024), ([0, 0, 31, 13], 374)],
            "alien_big2_3": [([0, 0, 31, 31], 1024), ([0, 0, 31, 13], 362)],
            "alien_big2_4": [([0, 0, 31, 31], 1024), ([0, 0, 31, 13], 336)],
            "alien_big2_5": [([0, 0, 31, 31], 1024), ([0, 0, 31, 13], 361)],
            "alien_big2_6": [([0, 0, 31, 31], 1024), ([0, 0, 31, 14], 407)],
            "alien_gultop": [([0, 2, 9, 11], 88), ([0, 2, 9, 11], 88)],
            "alien_lillatop": [([0, 4, 9, 11], 72), ([0, 4, 9, 11], 72)],
            "alien_bluekreps": [([0, 0, 11, 11], 128), ([2, 2, 9, 9], 48)],
            "alien_lbluekreps": [([0, 0, 11, 11], 128), ([0, 0, 11, 11], 128)],
            "alien_brownkreps": [([0, 0, 11, 11], 122), ([0, 0, 11, 11], 128)],
            "alien_brownkreps2": [([0, 0, 11, 11], 128), ([0, 0, 11, 11], 128)],
            "alien_gulkreps": [([0, 0, 11, 11], 128), ([3, 3, 8, 8], 32)],
            "alien_rvinggk": [([0, 0, 17, 17], 74), ([0, 0, 17, 17], 267)],
            "alien_gvingbk": [([0, 0, 17, 17], 276), ([2, 2, 17, 17], 208)],
        },
    }
    expected_broad_bounds = {
        "ordinary_type_7": {
            "alien001": [0, 0, 5, 13],
            "alien_2": [0, 0, 3, 11],
            "alien_3": [0, 0, 5, 12],
            "alien000": [0, 0, 7, 13],
            "alien_lilla": [0, 0, 5, 9],
            "alien_raudkule": [2, 2, 5, 7],
            "alien_raudkule2": [0, 0, 7, 9],
            "alien_blavinger_gf": [2, 2, 7, 7],
            "alien_blavinger_gf2": [2, 2, 7, 7],
            "alien_rbille": [0, 0, 7, 7],
            "alien_big2_1": [0, 0, 28, 31],
            "alien_big2_2": [0, 0, 28, 31],
            "alien_big2_3": [0, 0, 28, 31],
            "alien_big2_4": [0, 0, 28, 31],
            "alien_big2_5": [0, 0, 28, 31],
            "alien_big2_6": [0, 0, 29, 31],
            "alien_gultop": [0, 0, 9, 11],
            "alien_lillatop": [0, 0, 7, 9],
            "alien_bluekreps": [0, 0, 11, 11],
            "alien_lbluekreps": [0, 0, 11, 11],
            "alien_brownkreps": [0, 0, 11, 11],
            "alien_brownkreps2": [0, 0, 11, 11],
            "alien_gulkreps": [0, 0, 11, 11],
            "alien_rvinggk": [0, 0, 13, 13],
            "alien_gvingbk": [0, 0, 13, 13],
        },
        "supplemental_state_6_type_6": {
            "alien001": [0, 1, 11, 12],
            "alien_2": [2, 2, 9, 9],
            "alien_3": [0, 0, 31, 12],
            "alien000": [0, 0, 13, 16],
            "alien_lilla": [0, 0, 11, 11],
            "alien_raudkule": [4, 4, 9, 9],
            "alien_raudkule2": [0, 0, 17, 17],
            "alien_blavinger_gf": [0, 0, 13, 13],
            "alien_blavinger_gf2": [0, 0, 13, 13],
            "alien_rbille": [0, 0, 17, 17],
            "alien_big2_1": [0, 0, 31, 31],
            "alien_big2_2": [0, 0, 31, 31],
            "alien_big2_3": [0, 0, 31, 31],
            "alien_big2_4": [0, 0, 31, 31],
            "alien_big2_5": [0, 0, 31, 31],
            "alien_big2_6": [0, 0, 31, 31],
            "alien_gultop": [0, 2, 9, 11],
            "alien_lillatop": [0, 4, 9, 11],
            "alien_bluekreps": [0, 0, 11, 11],
            "alien_lbluekreps": [0, 0, 11, 11],
            "alien_brownkreps": [0, 0, 11, 11],
            "alien_brownkreps2": [0, 0, 11, 11],
            "alien_gulkreps": [0, 0, 11, 11],
            "alien_rvinggk": [0, 0, 17, 17],
            "alien_gvingbk": [0, 0, 17, 17],
        },
    }
    if version >= 9:
        expected_projectile_masks = {}
        expected_broad_bounds = {}
        for contract_id, contract in latest_sprite_frames["enemy_projectile_contracts"].items():
            expected_projectile_masks[contract_id] = {}
            expected_broad_bounds[contract_id] = {}
            for sheet_id, sheet_contract in contract["sheet_masks"].items():
                expected_projectile_masks[contract_id][sheet_id] = [
                    (phase["local_inclusive_bounds"], phase["occupied_pixel_count"])
                    for phase in sheet_contract["phases"]
                ]
                expected_broad_bounds[contract_id][sheet_id] = sheet_contract[
                    "retail_broad_phase_bounds"
                ]
    if version < 7:
        for big2_sheet_id in (f"alien_big2_{index}" for index in range(1, 7)):
            for contract_id in expected_projectile_masks:
                expected_projectile_masks[contract_id].pop(big2_sheet_id)
                expected_broad_bounds[contract_id].pop(big2_sheet_id)
    if version < 8:
        for new_sheet_id in (
            "alien_gultop",
            "alien_lillatop",
            "alien_bluekreps",
            "alien_lbluekreps",
            "alien_brownkreps",
            "alien_brownkreps2",
            "alien_gulkreps",
            "alien_rvinggk",
            "alien_gvingbk",
        ):
            for contract_id in expected_projectile_masks:
                expected_projectile_masks[contract_id].pop(new_sheet_id)
                expected_broad_bounds[contract_id].pop(new_sheet_id)
    if version < 6:
        for late_sheet_id in (
            "alien_raudkule",
            "alien_raudkule2",
            "alien_blavinger_gf",
            "alien_blavinger_gf2",
            "alien_rbille",
        ):
            for contract_id in expected_projectile_masks:
                expected_projectile_masks[contract_id].pop(late_sheet_id)
                expected_broad_bounds[contract_id].pop(late_sheet_id)
    for contract_id, expected_masks in expected_projectile_masks.items():
        sheet_masks = enemy_projectiles[contract_id].get("sheet_masks")
        require(
            isinstance(sheet_masks, dict) and list(sheet_masks) == expected_sheet_ids,
            f"{contract_id} must cover all enemy sheets in retail order",
        )
        for sheet_id, expected_phases in expected_masks.items():
            sheet_contract = sheet_masks[sheet_id]
            require(
                sheet_contract.get("retail_broad_phase_bounds")
                == expected_broad_bounds[contract_id][sheet_id],
                f"{contract_id} {sheet_id} retail broad-phase metadata drift",
            )
            phases = sheet_contract.get("phases", [])
            actual_phases = [
                (phase.get("local_inclusive_bounds"), phase.get("occupied_pixel_count"))
                for phase in phases
            ]
            require(
                actual_phases == expected_phases,
                f"{contract_id} {sheet_id} projectile hit-mask metadata drift",
            )
    if version >= 3:
        require(
            supplemental_projectile.get("reachable_levels")
            == (
                latest_sprite_frames["enemy_projectile_contracts"]["supplemental_state_6_type_6"]["reachable_levels"]
                if version >= 9
                else (
                [3, 7, 11, 15, 19, 23]
                if version == 3
                else (
                    [3, 7, 11, 15, 19, 23, 28]
                    if version == 4
                    else (
                        [3, 7, 11, 15, 19, 23, 28, 32]
                        if version == 5
                        else (
                            [3, 7, 11, 15, 19, 23, 28, 32, 36, 40, 44, 48, 53, 57, 61]
                            if version == 8
                            else [3, 7, 11, 15, 19, 23, 28, 32, 36, 40, 44, 48]
                        )
                    )
                ))
            ),
            "supplemental projectile reachability drift",
        )
    if version == 10:
        require(
            data == latest_sprite_frames,
            "sprite_frames.json v10 is stale or diverges from pinned executable/assets",
        )


def validate_swd_paths(data):
    require(data.get("version") == 1, "swd_paths.json has unsupported version")
    require(
        data.get("schema") == "warblade.swd.runtime.v1",
        "swd_paths.json has unsupported schema",
    )
    require(
        data.get("selection_scope") == "global_loaded_catalog",
        "SWD selection must use the complete loaded catalog",
    )
    require(
        data.get("inactive_runtime_point_policy") == "zero_fill",
        "SWD runtime points must preserve loader zero-fill behavior",
    )
    paths = data.get("paths")
    require(isinstance(paths, list) and len(paths) == 14, "SWD catalog must contain fourteen paths")
    require(unique_ids(paths, "SWD paths") == list(range(14)), "SWD runtime IDs must be contiguous")
    for index, path in enumerate(paths):
        require(path.get("source_file") == f"att{index + 1:03d}.swd", "SWD loader order is wrong")
        require_string(path.get("source_sha256"), "SWD source_sha256")
        require_int(path.get("initial_velocity_x_fixed_256"), "SWD initial velocity X")
        require_int(path.get("initial_velocity_y_fixed_256"), "SWD initial velocity Y")
        require_int(path.get("return_selector"), "SWD return selector", 1)
        require(path["return_selector"] <= 3, "SWD return selector is outside the proven set")
        points = path.get("points")
        require(isinstance(points, list), "SWD points must be an array")
        require_int(path.get("active_point_count"), "SWD active point count", 0)
        require(len(points) == path["active_point_count"] <= 150, "SWD active point count mismatch")
        for point in points:
            for field in (
                "acceleration_x_fixed_256",
                "acceleration_y_fixed_256",
                "opcode",
                "unresolved_word_3",
                "progress_threshold",
            ):
                require_int(point.get(field), f"SWD point.{field}")
            require(point["opcode"] in (0, 1, 6), "SWD point opcode is unsupported")
            require(point["progress_threshold"] >= 0, "SWD progress threshold must be nonnegative")
    require(data == build_swd_content(), "swd_paths.json is stale or diverges from retail SWD files")


def validate_bonus_modes(data):
    require(data.get("version") == 1, "bonus_modes.json has unsupported version")
    require(
        data.get("schema") == "warblade.bonus-modes.v1",
        "bonus_modes.json has unsupported schema",
    )
    level_8 = data.get("level_8_bonus", {})
    mode_three = data.get("mode_three_bonus", {})
    require(mode_three.get("level_mode_id") == 3, "mode-three level-mode binding drift")
    require("level_id" not in mode_three, "canonical mode-three contract must be level-neutral")
    require(
        "authored_target_count" not in mode_three,
        "canonical mode-three contract must not expose a single target count",
    )
    require(
        "background_texture" not in mode_three,
        "canonical mode-three contract must leave backgrounds to the level presentation binding",
    )
    require(
        mode_three.get("levels") == mode_three_level_aliases(CONTENT / "levels.json"),
        "mode-three level facts drift",
    )
    require(
        mode_three.get("ordinary_enemy_projectiles_suppressed") is True,
        "mode-three projectile suppression drift",
    )
    require(level_8.get("level_id") == 8, "bonus-mode level binding drift")
    require(level_8.get("level_mode_id") == 3, "level 8 must retain retail mode 3")
    require(
        level_8.get("ordinary_enemy_projectiles_suppressed") is True,
        "level-8 projectile suppression drift",
    )
    require(
        level_8.get("rewards", {}).get("perfect_reward_progression")
        == [10000, 25000, 50000, 100000, 250000, 500000, 1000000, 2500000, 5000000, 10000000],
        "level-8 perfect reward progression drift",
    )
    legacy_rewards = level_8.get("rewards", {})
    canonical_rewards = mode_three.get("rewards", {})
    expected_rewards = dict(legacy_rewards)
    expected_rewards.pop("authored_enemy_score", None)
    require(
        canonical_rewards == expected_rewards,
        "canonical mode-three rewards must omit only the per-level score",
    )
    require(
        "authored_enemy_score" not in canonical_rewards,
        "canonical mode-three rewards must source scores from levels[]",
    )
    legacy_timing = level_8.get("timing_and_flow", {})
    canonical_timing = mode_three.get("timing_and_flow", {})
    expected_timing = dict(legacy_timing)
    expected_timing.pop("shop_rule", None)
    require(
        canonical_timing == expected_timing,
        "canonical mode-three timing must omit only the level-8 shop prose",
    )
    require(
        "shop_rule" not in canonical_timing,
        "canonical mode-three timing must remain level-neutral",
    )
    ranks = data.get("rank_promotion", {}).get("ranks", [])
    require([entry.get("rank") for entry in ranks] == list(range(1, 21)), "rank speech range drift")
    voice_assets = data.get("rank_promotion", {}).get("voice_assets", {})
    for entry in ranks:
        for cue in entry.get("queue", []):
            require(cue.get("key") in voice_assets, "rank queue references a missing voice")
            require_int(cue.get("padding_ms"), "rank cue padding_ms", 0)
    require(
        data == build_bonus_modes_content(),
        "bonus_modes.json is stale or diverges from pinned executable/assets",
    )


def validate_bosses(data):
    version = data.get("version")
    require(version in (1, 2, 3, 4, 5), "bosses.json has unsupported version")
    require(
        data.get("schema") == f"warblade.bosses.v{version}",
        "bosses.json has unsupported schema",
    )
    bosses = data.get("bosses")
    expected_boss_ids = ["retail_big_boss_v1"]
    if version >= 3:
        expected_boss_ids.append("retail_big_boss_level_50_v1")
    if version >= 4:
        expected_boss_ids.extend(
            ["retail_big_boss_level_75_v1", "retail_big_boss_level_100_v1"]
        )
    if version >= 5:
        for contract_id, contract in (bosses or {}).items():
            health = contract.get("health", {})
            require(
                health.get("endless_step_additive") == 100,
                f"{contract_id} must declare the traced endless per-hundred "
                "health additive of 100",
            )
    require(
        isinstance(bosses, dict) and list(bosses) == expected_boss_ids,
        "bosses.json contains unsupported or misordered boss contracts",
    )
    expected_levels = {
        "retail_big_boss_v1": 25,
        "retail_big_boss_level_50_v1": 50,
        "retail_big_boss_level_75_v1": 75,
        "retail_big_boss_level_100_v1": 100,
    }
    for contract_id in expected_boss_ids:
        contract = bosses[contract_id]
        require(isinstance(contract, dict), f"{contract_id} must be an object")
        require(
            contract.get("id") == contract_id
            and contract.get("level_id") == expected_levels[contract_id]
            and contract.get("level_mode_id") == 4
            and contract.get("retail_state_id") == 13,
            f"{contract_id} identity or encounter binding drift",
        )
        require(
            contract.get("exact_trace_complete") is True,
            f"{contract_id} must fail closed without an exact complete trace",
        )
        require(
            not contains_unresolved(contract),
            f"{contract_id} contains unresolved gameplay behavior",
        )
    if version == 4:
        require(
            data == build_boss_contract_content(),
            "bosses.json is stale or diverges from the exact state-13 traces",
        )


def validate_ordnance(data):
    require(data.get("version") == 1, "ordnance.json has unsupported version")
    require(
        data.get("schema") == "warblade.ordnance.v1",
        "ordnance.json has unsupported schema",
    )
    for section_name in (
        "source",
        "rocket_pack",
        "alien_lock",
        "missile_runtime",
        "integration",
    ):
        require(
            isinstance(data.get(section_name), dict),
            f"ordnance.json is missing {section_name}",
        )


TALENT_GATED_EFFECTS = [
    "enable_alien_lock",
    "enable_autofire",
    "enable_super_autofire",
    "rocket_pack",
]
# The contract's per-seat start-state vocabulary (match_contract.gd), plus the
# top-level starting_rockets grant channel.
TALENT_INT_KEYS = {
    "bullet_capacity", "speed_steps", "weapon_at_least", "armour_charges",
    "money", "bonus_time", "bonus_time_max", "timed_score_multiplier",
    "starting_rockets",
}
TALENT_BOOL_KEYS = {
    "speed_half_max", "speed_max", "auto_fire", "super_auto_fire",
    "bonus_time_half_max", "bonus_time_full_max", "bullet_speed_up",
    "rank_32_bullet_speed", "meteor_storm_multiplier_enabled", "gem_counter",
    "secret_counter", "missile_stealth", "autofire_through_shop",
    "timed_scoop", "time_trial_extra_minute", "only_blue_coins", "alien_lock",
}


def validate_talents(data):
    require(data.get("version") == 1, "talents.json has unsupported version")
    require(
        data.get("schema") == "warblade.talents.v1",
        "talents.json has unsupported schema",
    )
    require(
        data.get("applies_to_modes") == ["solo", "coop"],
        "talents.json must apply to exactly solo and coop",
    )
    migration = data.get("shop_migration")
    require(isinstance(migration, dict), "talents.json is missing shop_migration")
    gated = migration.get("talent_gated_effects")
    require(
        isinstance(gated, list) and sorted(gated) == TALENT_GATED_EFFECTS,
        "talents.json gated effects must equal the contract mirror",
    )
    grant_keys = data.get("grant_keys")
    require(isinstance(grant_keys, dict), "talents.json is missing grant_keys")
    require(
        set(grant_keys.get("int", [])) <= TALENT_INT_KEYS,
        "talents.json declares an int grant key outside the contract",
    )
    require(
        set(grant_keys.get("bool", [])) <= TALENT_BOOL_KEYS,
        "talents.json declares a bool grant key outside the contract",
    )
    branches = data.get("branches")
    require(isinstance(branches, list) and branches, "talents.json needs branches")
    nodes = {}
    for branch in branches:
        require(isinstance(branch, dict), "talents.json branches must be objects")
        for node in branch.get("nodes", []):
            require(isinstance(node, dict), "talents.json nodes must be objects")
            node_id = node.get("id")
            require(
                isinstance(node_id, str) and node_id and node_id not in nodes,
                "talents.json node ids must be unique non-empty strings",
            )
            require(
                node.get("kind") in ("grant", "shop_unlock"),
                f"talent {node_id} has an unknown kind",
            )
            require_int(node.get("cost"), f"talent {node_id} cost", minimum=1)
            if node.get("kind") == "shop_unlock":
                require(
                    node.get("shop_effect") in gated,
                    f"talent {node_id} unlocks an ungated shop effect",
                )
            else:
                for key, value in node.get("grants", {}).items():
                    pool = (
                        set(grant_keys.get("bool", []))
                        if isinstance(value, bool)
                        else set(grant_keys.get("int", []))
                    )
                    require(
                        key in pool,
                        f"talent {node_id} grants {key} outside the vocabulary",
                    )
            nodes[node_id] = node
    for node_id, node in nodes.items():
        for requirement in node.get("requires", []):
            require(
                requirement in nodes,
                f"talent {node_id} requires unknown node {requirement}",
            )
    peeled = set()
    progressed = True
    while progressed and len(peeled) < len(nodes):
        progressed = False
        for node_id, node in nodes.items():
            if node_id in peeled:
                continue
            if all(requirement in peeled for requirement in node.get("requires", [])):
                peeled.add(node_id)
                progressed = True
    require(len(peeled) == len(nodes), "talents.json contains a prerequisite cycle")


def validate_time_trial(data):
    require(data.get("version") == 1, "time_trial.json has unsupported version")
    require(
        data.get("schema") == "warblade.time-trial.v1",
        "time_trial.json has unsupported schema",
    )
    runtime = data.get("runtime")
    require(isinstance(runtime, dict), "time_trial.json is missing its runtime")
    require(
        runtime.get("retail_match_mode_id") == 6,
        "time_trial.json must declare retail match mode 6",
    )
    clock = runtime.get("clock")
    require(isinstance(clock, dict), "time_trial.json is missing its match clock")
    require(
        clock.get("match_milliseconds") == 181000
        and clock.get("grouped_best_extra_minute_milliseconds") == 241000
        and clock.get("missing_levels_milliseconds") == 10000,
        "time_trial.json clock diverges from the pinned retail bytes",
    )
    rules = runtime.get("rules")
    require(isinstance(rules, dict), "time_trial.json is missing its mode rules")
    for disabled in (
        "shops",
        "warp",
        "warp_malfunction",
        "bonus_modes",
        "rank_promotion",
        "credits",
        "hurry_up_special_ships",
        "death_resets_loadout",
    ):
        require(
            rules.get(disabled) is False,
            f"time_trial.json must disable {disabled}",
        )
    require(
        rules.get("starting_weapon_id") == 0 and rules.get("seats") == 1,
        "time_trial.json mode rules diverge from retail evidence",
    )
    levels = data.get("levels")
    require(isinstance(levels, list) and len(levels) == 15, "time_trial.json needs 15 levels")
    facts = load_json(FACTS)
    facts_by_id = {item["id"]: item for item in facts["time_trial_levels"]}
    for index, level in enumerate(levels):
        require(isinstance(level, dict), "Time Trial level entries must be objects")
        require(level.get("id") == index + 1, "Time Trial level IDs must run 1 through 15")
        fact = facts_by_id[level["id"]]
        require(
            level.get("raw_lvd_sha256") == fact["sha256"],
            f"Time Trial level hash diverges from evidence: {level['id']}",
        )
        require(
            level.get("title") == fact["title"]
            and level.get("author") == fact["author"]
            and level.get("enemy_resources") == fact["enemy_resources"],
            f"Time Trial level metadata diverges from evidence: {level['id']}",
        )
        require(
            level.get("shop_after") is False,
            f"Time Trial level {level['id']} must not declare a shop",
        )
        validate_authored_lvd(level.get("authored_lvd"), level["id"], 9)
        authored = level["authored_lvd"]
        require(
            authored.get("level_mode_id") in (1, 2),
            f"Time Trial level {level['id']} uses an unsupported level mode",
        )
        require(
            authored.get("mirror_x") is False,
            f"Time Trial level {level['id']} must not mirror the authored field",
        )


def sha256_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def validate_manifest():
    manifest = load_json(MANIFEST)
    require(manifest.get("format_version") == 1, "manifest has unsupported version")
    require(manifest["allowlist"]["sha256"] == sha256_file(ALLOWLIST), "manifest allowlist SHA-256 is stale")
    require(manifest["known_facts"]["sha256"] == sha256_file(FACTS), "manifest known-facts SHA-256 is stale")
    require(manifest["known_facts"]["data"] == load_json(FACTS), "manifest embedded facts are stale")
    outputs = set()
    for asset in manifest["assets"]:
        output = asset["output"]
        require(output not in outputs, f"duplicate manifest output: {output}")
        outputs.add(output)
        path = ASSETS / output
        require(path.is_file() and not path.is_symlink(), f"missing manifested asset: {output}")
        require(path.stat().st_size == asset["size"], f"asset size mismatch: {output}")
        require(sha256_file(path) == asset["output_sha256"], f"asset SHA-256 mismatch: {output}")
    actual = {
        path.relative_to(ASSETS).as_posix()
        for path in ASSETS.rglob("*")
        if path.is_file() and not path.name.endswith(".import")
    }
    require(actual == outputs, f"asset closure mismatch: extra={sorted(actual - outputs)}, missing={sorted(outputs - actual)}")
    return manifest


def validate_evidence_alignment(documents):
    facts = load_json(FACTS)
    weapon_facts = {item["id"]: item for item in facts["weapons"]["definitions"]}
    for weapon in documents["weapons.json"]["weapons"]:
        fact = weapon_facts[weapon["id"]]
        require(weapon["name"] == fact["name"], f"weapon name diverges from evidence: {weapon['id']}")
        require(weapon["damage_fp"] == fact["damage_fp"], f"weapon damage diverges from evidence: {weapon['id']}")
        prototypes = [projectile["prototype_id"] for projectile in weapon["projectiles"]]
        require(prototypes == fact["flattened_prototype_ids"], f"weapon graph diverges from evidence: {weapon['id']}")
        require(
            documents["weapons.json"]["fire_control"]["auto_fire_repeat_delay_ms"]
            == facts["weapons"]["base_fire_delay"]["milliseconds"],
            "auto-fire repeat delay diverges from evidence",
        )

    level_facts = {item["id"]: item for item in facts["levels"]}
    for level in documents["levels.json"]["levels"]:
        fact = level_facts[level["id"]]
        require(level["title"] == fact["title"], f"level title diverges from evidence: {level['id']}")
        require(level["author"] == fact["author"], f"level author diverges from evidence: {level['id']}")
        require(level["enemy_sprite"] == fact["packaged_enemy_id"], f"level enemy diverges from evidence: {level['id']}")
        if "enemy_resources" in fact:
            require(
                level.get("enemy_resources") == fact["enemy_resources"],
                f"level enemy resources diverge from evidence: {level['id']}",
            )
        require(level["shop_after"] == fact["shop_after"], f"shop placement diverges from evidence: {level['id']}")
        require(level["raw_lvd_sha256"] == fact["sha256"], f"level hash diverges from evidence: {level['id']}")

    shop_facts = facts["shop"]["items"]
    for item, fact in zip(documents["shop.json"]["items"], shop_facts, strict=True):
        require(item["id"] == fact["id"], f"shop ID diverges from evidence: {item['id']}")
        require(item["name"] == fact["name"], f"shop name diverges from evidence: {item['id']}")
        require(item["price"] == fact["price"], f"shop price diverges from evidence: {item['id']}")


def main():
    validators = {
        "weapons.json": validate_weapons,
        "bonuses.json": validate_bonuses,
        "levels.json": validate_levels,
        "shop.json": validate_shop,
        "difficulties.json": validate_difficulties,
        "sprites.json": validate_sprites,
        "sprite_frames.json": validate_sprite_frames,
        "swd_paths.json": validate_swd_paths,
        "bonus_modes.json": validate_bonus_modes,
        "bosses.json": validate_bosses,
        "ordnance.json": validate_ordnance,
        "time_trial.json": validate_time_trial,
        "talents.json": validate_talents,
    }
    documents = {}
    for name, validator in validators.items():
        data = load_json(CONTENT / name)
        if name not in {"bonus_modes.json", "bosses.json", "ordnance.json"}:
            reject_floats(data, name)
        validator(data)
        documents[name] = data
    compatibility = {
        1: {"bosses": None, "ordnance": None, "sprite_frames": 2},
        2: {"bosses": 1, "ordnance": None, "sprite_frames": 3},
        3: {"bosses": 2, "ordnance": 1, "sprite_frames": 4},
        4: {"bosses": 2, "ordnance": 1, "sprite_frames": 5},
        5: {"bosses": 2, "ordnance": 1, "sprite_frames": 6},
        6: {"bosses": 3, "ordnance": 1, "sprite_frames": 7},
        7: {"bosses": 3, "ordnance": 1, "sprite_frames": 8},
        8: {"bosses": 4, "ordnance": 1, "sprite_frames": 9},
        9: {"bosses": 5, "ordnance": 1, "sprite_frames": 10},
        10: {"bosses": 5, "ordnance": 1, "sprite_frames": 11},
    }
    levels_version = documents["levels.json"]["version"]
    expected = compatibility[levels_version]
    require(
        documents["sprite_frames.json"]["version"] == expected["sprite_frames"],
        f"levels.json v{levels_version} requires "
        f"sprite_frames.json v{expected['sprite_frames']}",
    )
    require(
        expected["bosses"] is None
        or documents["bosses.json"]["version"] == expected["bosses"],
        f"levels.json v{levels_version} requires bosses.json v{expected['bosses']}",
    )
    require(
        expected["ordnance"] is None
        or documents["ordnance.json"]["version"] == expected["ordnance"],
        f"levels.json v{levels_version} requires ordnance.json v{expected['ordnance']}",
    )
    validate_evidence_alignment(documents)
    manifest = validate_manifest()
    print(f"validated {len(validators)} content files and evidence alignment")
    print(f"validated {len(manifest['assets'])} assets and SHA-256 records")


if __name__ == "__main__":
    main()
