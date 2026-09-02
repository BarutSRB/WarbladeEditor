#!/usr/bin/env python3

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import tempfile
from pathlib import Path, PurePosixPath
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
PARSER_SCRIPTS = ROOT / "Parser" / "scripts"
sys.path.insert(0, str(PARSER_SCRIPTS))

import warblade_presentation
from classic_levels_extract import EXPECTED_ENEMY_SHEET_IDS


DEFAULT_GAME_ROOT = ROOT / "Game"
DEFAULT_PROVENANCE = ROOT / "docs" / "evidence" / "provenance_manifest.json"
DEFAULT_ASSET_ROOT = ROOT / "assets" / "original"
DEFAULT_OUTPUT = ROOT / "content" / "presentation.json"
DEFAULT_EVIDENCE = ROOT / "docs" / "evidence" / "PRESENTATION_ASSETS.md"
TEXTURE_SUFFIXES = {".hma", ".jpg", ".png", ".tga"}
EXPECTED_SELECTED_COUNTS = {
    "textures": 533,
    "music": 12,
    "sfx": 116,
    "voices": 103,
    "voice_pack_2": 36,
}
VOICE_PACK_IDS = {"voices": 1, "voice_pack_2": 2}
VOICE_PACK_2_FALLBACK = 1
WARBLADE_EXE_SHA256 = "ddf1778c307af1087ff9dcb512786111e665d972298aeaac3f1b4b2996d079ef"
ENDING_TEXT_FILE_OFFSET = 0x0025F570
ENDING_TEXT_VA = 0x00784170
ENDING_TEXT_BYTE_LENGTH = 3823
ENDING_TEXT_SHA256 = "b4fe7687257464e45094fec26f4c24d9eaf47449eeb9a4e367d2a9c42a63eb06"
ENDING_CREDITS_MARKER = "- - -  CREDITS  - - -"
ENDING_CREDITS_MARKER_INDEX = 848
ENDING_SLIDE_IDS = (
    "ending_5", "ending_4", "ending_6", "ending_3", "ending_0", "ending_1",
    "ending_9", "ending_7", "ending_8", "ending_2", "ending_10", "ending_11",
    "ending_12",
)
LEGACY_SFX_VOICE_KEYS = {
    "congratulations",
    "lieutenant",
    "rank",
    "warpmalfunction",
}

SHOP_ITEM_KEYS = {
    "1": "shop_speed",
    "2": "shop_bullet",
    "3": "shop_doubleshot",
    "4": "shop_lessspeed",
    "5": "shop_tripleshot",
    "6": "shop_quad",
    "7": "shop_autofire",
    "8": "shop_supertriple",
    "9": "shop_armour",
    "10": "shop_plasma",
    "11": "shop_extralife",
    "12": "shop_fireballs",
    "13": "shop_secret",
    "14": "shop_rank",
    "15": "shop_extratime",
    "16": "shop_laser",
    "17": "shop_wariplasma",
    "18": "shop_rocketpack",
    "19": "shop_alienlock",
    "20": "shop_autofire_super",
}

REQUIRED_TEXTURES = {
    "abcd_2",
    "abcd_3",
    "abcd_4",
    "alien001",
    "alien_2",
    "alien_3",
    "alien000",
    "alien_lilla",
    "alien003",
    "alien003_3",
    "alien_big1_1",
    "alien_big1_2",
    "alien_big1_3",
    "alien_big1_4",
    "alien_big1_5",
    "alien_big1_6",
    "alien_big2_1",
    "alien_big2_2",
    "alien_big2_3",
    "alien_big2_4",
    "alien_big2_5",
    "alien_big2_6",
    "alien_rakett",
    "alien_rakett_gronn",
    "alien_baller",
    "alien_baller2",
    "alien_green_lilla_t",
    "alien_cyan_lilla_t",
    "alien_raudkule",
    "alien_raudkule2",
    "alien_blavinger_gf",
    "alien_blavinger_gf2",
    "alien_rbille",
    "alien_gultop",
    "alien_lillatop",
    "alien_bluekreps",
    "alien_lbluekreps",
    "alien_brownkreps",
    "alien_brownkreps2",
    "alien_gulkreps",
    "alien_rvinggk",
    "alien_gvingbk",
    "alien_big1_1_mask",
    "alien_big1_2_mask",
    "alien_big1_3_mask",
    "alien_big1_4_mask",
    "alien_big1_5_mask",
    "alien_big1_6_mask",
    "alien_big2_1_mask",
    "alien_big2_2_mask",
    "alien_big2_3_mask",
    "alien_big2_4_mask",
    "alien_big2_5_mask",
    "alien_big2_6_mask",
    "alien_malfold_blue",
    "alien_malfold_green",
    "bonuses",
    "border",
    "border_ace",
    "border_easy",
    "border_hard",
    "butikk3",
    "diamantbig",
    "endfont",
    "expl_small",
    "explo",
    "fighter1",
    "fighter2",
    "figterfire2",
    "flare1",
    "flare2",
    "flare4",
    "flare_laser",
    "flare_line",
    "flare_streak",
    "flare_streak_big",
    "flarebomb",
    "gameover",
    "glow",
    "malfunction1",
    "malfunction3",
    "malfunction4",
    "marks",
    "memoryblocks",
    "meteorbonuses",
    "meteormeter2",
    "meteors",
    "newlogo3",
    "newscreen",
    "numbers",
    "numbers_256",
    "pause3",
    "pause4",
    "rocket",
    "sparks",
    "splashscreen",
    "stars1",
    "stars2",
    "stars3",
    "stars4",
    "stars5",
    "weapons_big",
    *SHOP_ITEM_KEYS.values(),
    *EXPECTED_ENEMY_SHEET_IDS,
    *(f"alien_big3_{index}_mask" for index in range(1, 7)),
    *(f"alien_big4_{index}_mask" for index in range(1, 7)),
    *ENDING_SLIDE_IDS,
}
REQUIRED_MUSIC = {
    "boss",
    "gems",
    "memory",
    "meteor",
    "promoted",
    "shop",
    "title",
    "warblade",
    "endgame",
}
REQUIRED_SFX = {
    "alienshoot1",
    "alienshoot2",
    "alienshoot10",
    "bell1",
    "bell2",
    "bigfire",
    "bigsmall",
    "bing",
    "birth",
    "boss",
    "buttonclick",
    "buzzer",
    "chaching",
    "coin",
    "coming",
    "congratulations",
    "explo1",
    "explo3",
    "explo4",
    "fanfare",
    "fire",
    "harpgliss1",
    "hit1",
    "hit2",
    "laser1",
    "laser2",
    "lieutenant",
    "jingles",
    "machine",
    "meteorpass",
    "over",
    "rollover",
    "rank",
    "shot1",
    "shot2",
    "singleshot",
    "thumpbig",
    "warpmalfunction",
}
REQUIRED_VOICES = {
    "admiral", "bonus", "bronze", "captain", "commander", "congratulations",
    "eight", "five", "four", "gold", "grandmaster", "knight", "lieutenant", "lord",
    "gemdrop", "memorystation", "meteorstorm", "one", "overlord", "rank",
    "nine", "seven", "silver", "six", "star", "stars", "ten", "three", "two", "warblade",
    "warpmalfunction", "secretfound",
    "getready", "getready2", "getready3", "gameover", "warning",
    "hurryup1", "hurryup2", "perfect", "scoop", "freeze",
    "ultimaterank", "welcome", "goodbye", "champion", "new", "rankmarker",
    "sucker", "sucker2", "sucker3", "ohno", "oops", "gotcha",
    "alright", "mirror", "bomb", "times2", "times5",
    "singleshot", "doubleshot", "tripleshot", "quadshot", "supertripleshot",
    "autofire", "extrabullet", "extraspeed", "extratime", "extralife",
    "armour", "shield", "money", "player", "player1", "player2", "players",
    "youarethe", "god", "ensign", "drunk", "available", "speed",
    "shop1", "shop2", "shop3", "shop4", "shop5",
    "a", "e", "r", "t", "x",
    "jupiter", "mars", "mercury", "neptune", "pluto", "saturn",
    "tellus", "uranus", "venus", "sol", "planet",
}


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as stream:
        value = json.load(stream)
    if not isinstance(value, dict):
        raise ValueError(f"expected a JSON object: {path}")
    return value


def _normalized_output(value: str) -> PurePosixPath:
    if not isinstance(value, str) or not value or "\x00" in value or "\\" in value:
        raise ValueError(f"invalid provenance output path: {value!r}")
    path = PurePosixPath(value)
    if path.is_absolute() or any(part in ("", ".", "..") for part in path.parts):
        raise ValueError(f"invalid provenance output path: {value!r}")
    return path


def _asset_path(asset_root: Path, output: str) -> Path:
    relative = _normalized_output(output)
    path = asset_root.joinpath(*relative.parts)
    resolved_root = asset_root.resolve()
    resolved_path = path.resolve()
    if resolved_path != resolved_root and resolved_root not in resolved_path.parents:
        raise ValueError(f"asset path escapes root: {output}")
    return path


def _source_id(record: dict[str, Any]) -> str:
    source_kind = record.get("source_kind")
    source_member = record.get("source_member")
    if source_kind == "warblade.pac":
        return f"warblade.pac:{source_member}"
    if source_kind == "external_file":
        return f"external:{source_member}"
    raise ValueError(f"unsupported provenance source kind: {source_kind!r}")


def _asset_key(stem: str) -> str:
    key = stem.lower()
    if not re.fullmatch(r"[a-z0-9_]+", key):
        raise ValueError(f"asset key would require lossy normalization: {stem!r}")
    return key


def _texture_key(output: str) -> str:
    path = PurePosixPath(output)
    stem = _asset_key(path.stem)
    suffix = path.suffix.lower()
    if suffix == ".hma":
        return f"{stem}_hma"
    if stem == "newlogo3" and suffix == ".jpg":
        return "newlogo3_jpg"
    return stem


def _audio_key(output: str) -> str:
    return _asset_key(PurePosixPath(output).stem)


def _selected_records(provenance: dict[str, Any]) -> dict[str, list[dict[str, Any]]]:
    selected = {"textures": [], "music": [], "sfx": [], "voices": [], "voice_pack_2": []}
    seen_outputs: set[str] = set()
    assets = provenance.get("assets")
    if not isinstance(assets, list):
        raise ValueError("provenance manifest has no asset list")
    for record in assets:
        if not isinstance(record, dict):
            raise ValueError("provenance asset is not an object")
        output = _normalized_output(record.get("output", "")).as_posix()
        if output in seen_outputs:
            raise ValueError(f"duplicate provenance output: {output}")
        seen_outputs.add(output)
        suffix = PurePosixPath(output).suffix.lower()
        category = record.get("category")
        if output.startswith("textures/") and suffix in TEXTURE_SUFFIXES:
            selected["textures"].append(record)
        elif category == "music" and suffix == ".mp3":
            selected["music"].append(record)
        elif category == "sound_effect" and suffix == ".mp3":
            selected["sfx"].append(record)
        elif category == "voice" and suffix == ".mp3":
            selected["voices"].append(record)
            if _audio_key(output) in LEGACY_SFX_VOICE_KEYS:
                selected["sfx"].append(record)
        elif category == "voice_pack_2" and suffix == ".ogg":
            selected["voice_pack_2"].append(record)
    for section_name, expected_count in EXPECTED_SELECTED_COUNTS.items():
        actual_count = len(selected[section_name])
        if actual_count != expected_count:
            raise ValueError(
                f"expected {expected_count} selected {section_name}, found {actual_count}"
            )
        selected[section_name].sort(key=lambda record: record["output"].encode("utf-8"))
    return selected


def _validate_record_source(
    record: dict[str, Any],
    inventory_index: dict[str, dict[str, Any]],
    asset_root: Path,
) -> dict[str, Any]:
    source_id = _source_id(record)
    source = inventory_index.get(source_id)
    if source is None:
        raise ValueError(f"provenance source is absent from parser inventory: {source_id}")
    expected_sha256 = record.get("source_sha256")
    if source["sha256"] != expected_sha256:
        raise ValueError(
            f"source SHA-256 mismatch for {source_id}: expected {expected_sha256}, "
            f"found {source['sha256']}"
        )
    expected_size = record.get("size")
    if source["byte_size"] != expected_size:
        raise ValueError(
            f"source size mismatch for {source_id}: expected {expected_size}, "
            f"found {source['byte_size']}"
        )
    output = record["output"]
    path = _asset_path(asset_root, output)
    if path.is_symlink() or not path.is_file():
        raise FileNotFoundError(f"extracted presentation asset is missing or invalid: {path}")
    actual_size = path.stat().st_size
    actual_sha256 = sha256_file(path)
    if actual_size != expected_size:
        raise ValueError(
            f"extracted asset size mismatch for {output}: expected {expected_size}, found {actual_size}"
        )
    if actual_sha256 != record.get("output_sha256") or actual_sha256 != expected_sha256:
        raise ValueError(f"extracted asset SHA-256 mismatch for {output}")
    return source


def _insert_unique(entries: dict[str, Any], key: str, value: dict[str, Any], section: str) -> None:
    if key in entries:
        raise ValueError(f"presentation {section} key collision: {key}")
    entries[key] = value


def _build_asset_dictionaries(
    selected: dict[str, list[dict[str, Any]]],
    inventory: dict[str, Any],
    asset_root: Path,
) -> tuple[dict[str, Any], dict[str, Any], dict[str, Any], dict[str, Any], dict[str, Any]]:
    inventory_index = warblade_presentation.source_record_index(inventory)
    textures: dict[str, Any] = {}
    music: dict[str, Any] = {}
    sfx: dict[str, Any] = {}
    voices: dict[str, Any] = {}
    voice_pack_2: dict[str, Any] = {}

    for record in selected["textures"]:
        source = _validate_record_source(record, inventory_index, asset_root)
        key = _texture_key(record["output"])
        width = source.get("width")
        height = source.get("height")
        if not isinstance(width, int) or width <= 0 or not isinstance(height, int) or height <= 0:
            raise ValueError(f"presentation texture has no exact dimensions: {record['output']}")
        kind = "hit_mask" if source["format"] == "hma" else "texture"
        entry = {
            "path": f"res://assets/original/{record['output']}",
            "source_sha256": source["sha256"],
            "byte_size": source["byte_size"],
            "width": width,
            "height": height,
            "format": source["format"],
            "kind": kind,
            "required": key in REQUIRED_TEXTURES if kind == "texture" else False,
            "evidence_confidence": "verified_source",
        }
        if kind == "hit_mask":
            entry["orientation"] = source["orientation"]
            entry["value_domain"] = source["value_domain"]
        _insert_unique(textures, key, entry, "texture")

    for record in selected["music"]:
        source = _validate_record_source(record, inventory_index, asset_root)
        key = _audio_key(record["output"])
        _insert_unique(
            music,
            key,
            {
                "path": f"res://assets/original/{record['output']}",
                "source_sha256": source["sha256"],
                "byte_size": source["byte_size"],
                "required": key in REQUIRED_MUSIC,
                "loop": True,
                "evidence_confidence": "verified_source",
            },
            "music",
        )

    for record in selected["sfx"]:
        source = _validate_record_source(record, inventory_index, asset_root)
        key = _audio_key(record["output"])
        _insert_unique(
            sfx,
            key,
            {
                "path": f"res://assets/original/{record['output']}",
                "source_sha256": source["sha256"],
                "byte_size": source["byte_size"],
                "required": key in REQUIRED_SFX,
                "loop": False,
                "max_voices": 4,
                "priority": 0,
                "volume": 1.0,
                "pitch_scale": 1.0,
                "evidence_confidence": "verified_source",
                "tuning_confidence": (
                    "intentional_runtime_mix_policy"
                    if key in REQUIRED_SFX
                    else "not_runtime_consumed"
                ),
            },
            "sfx",
        )
    for record in selected["voices"]:
        source = _validate_record_source(record, inventory_index, asset_root)
        key = _audio_key(record["output"])
        _insert_unique(
            voices,
            key,
            {
                "path": f"res://assets/original/{record['output']}",
                "source_sha256": source["sha256"],
                "byte_size": source["byte_size"],
                "voice_pack_id": VOICE_PACK_IDS["voices"],
                "required": key in REQUIRED_VOICES,
                "loop": False,
                "evidence_confidence": "verified_source",
            },
            "voice",
        )
    for record in selected["voice_pack_2"]:
        source = _validate_record_source(record, inventory_index, asset_root)
        key = _audio_key(record["output"])
        _insert_unique(
            voice_pack_2,
            key,
            {
                "path": f"res://assets/original/{record['output']}",
                "source_sha256": source["sha256"],
                "byte_size": source["byte_size"],
                "voice_pack_id": VOICE_PACK_IDS["voice_pack_2"],
                "format": source["format"],
                "pack_1_fallback_available": key in voices,
                "required": False,
                "loop": False,
                "evidence_confidence": "verified_source",
            },
            "voice_pack_2",
        )
    return textures, music, sfx, voices, voice_pack_2


def _presentation_sections(level_facts: Any) -> dict[str, Any]:
    if not isinstance(level_facts, list):
        raise ValueError("presentation level facts must be an array")
    facts_by_id = {fact.get("id"): fact for fact in level_facts if isinstance(fact, dict)}
    if sorted(facts_by_id) != list(range(1, 101)):
        raise ValueError("presentation requires exact level facts 1 through 100")
    enemy_sheet_by_level = {
        level_id: str(facts_by_id[level_id].get("packaged_enemy_id", ""))
        for level_id in range(1, 101)
    }
    if any(not sheet_id for sheet_id in enemy_sheet_by_level.values()):
        raise ValueError("presentation level facts contain an empty enemy sheet ID")
    resources_by_level: dict[int, list[dict[str, Any]]] = {}
    for level_id in range(1, 101):
        fact = facts_by_id[level_id]
        resources = fact.get("enemy_resources")
        if resources is None:
            resources = [{
                "resource_slot_id": 1,
                "raw_name": fact["raw_enemy_reference"],
                "enemy_sheet_id": fact["packaged_enemy_id"],
            }]
        if not isinstance(resources, list) or not resources:
            raise ValueError(f"level {level_id} enemy resources must be a nonempty array")
        if [entry.get("resource_slot_id") for entry in resources] != list(
            range(1, len(resources) + 1)
        ):
            raise ValueError(f"level {level_id} enemy resources must be slot ordered")
        if resources[0].get("enemy_sheet_id") != enemy_sheet_by_level[level_id]:
            raise ValueError(f"level {level_id} slot-1 enemy alias diverges")
        resources_by_level[level_id] = resources
    enemy_sheet_options = list(dict.fromkeys(
        str(resource["enemy_sheet_id"])
        for level_id in range(1, 101)
        for resource in resources_by_level[level_id]
    ))
    if enemy_sheet_options != list(EXPECTED_ENEMY_SHEET_IDS):
        raise ValueError("presentation enemy sheet order diverges from level facts")
    backgrounds = {
        "logical_canvas": {"width": 800, "height": 600},
        "motion_contracts": {
            "retail_warp_scroll_v1": {
                "evidence_confidence": "proven",
                "executable_function_va": "0x00550900",
                "draw_region_va": "0x00551a25-0x00551b0f",
                "draw_region_sha256": "f9885bf2ecd4df9da4cf0384f1c14230c3d4d7336a50f53dfc4bbaa259f0f370",
                "post_draw_update_va": "0x00551b10-0x00551b84",
                "post_draw_update_sha256": "8dfe9604a62a68f8d14090526fc9cfccac7be90642476f31f837332135ff414c",
                "source_rect": [0, 0, 1024, 1024],
                "destination_quads": [
                    [64, "offset-600", 672, 600],
                    [64, "offset", 672, 600],
                ],
                "phase_predicate": ["warp"],
                "post_draw_step": "active warp scale / 20.0 at each authoritative 60 Hz update",
                "authoritative_snapshot_fields": [
                    "warp.background_draw_offset",
                    "warp.background_post_draw_offset",
                ],
                "client_sampling": "wrapped interpolation between authoritative draw offsets",
                "wrap_interval": [0.0, 600.0],
                "wrap_comparisons": [">=600 subtract 600", "<=0 add 600"],
                "layers": 1,
                "parallax": "none_in_traced_draw_path",
            }
        },
        "levels": {
            str(level): {
                "texture": (
                    "stars1"
                    if level % 100 < 26
                    else "stars2"
                    if level % 100 < 51
                    else "stars3"
                    if level % 100 < 76
                    else "stars4"
                ),
                "evidence_confidence": "proven",
                "selection_rule": (
                    "positive level modulo 100 below 26 selects background id 1; "
                    "26 through 50 select background id 2; 51 through 75 "
                    "select background id 3; 76 through 99 select background "
                    "id 4; remainder zero selects background id 1"
                ),
                "selection_va": "0x00569d56-0x00569ddc",
                "motion_contract": "retail_warp_scroll_v1",
            }
            for level in range(1, 101)
        },
    }
    borders = {
        "by_difficulty": {
            "easy": "border_easy",
            "normal": "border",
            "hard": "border_hard",
            "ace": "border_ace",
        },
        "evidence_confidence": "proven",
        "layout": "two_64_pixel_rails_from_128_pixel_source",
    }
    fighter_sheets = {
        "players": {
            "1": {
                "texture": "fighter1",
                "hit_mask": "fighter1_hma",
                "evidence_confidence": "proven",
            },
            "2": {
                "texture": "fighter2",
                "hit_mask": "fighter2_hma",
                "evidence_confidence": "proven",
            },
        },
        "thruster": {
            "texture": "figterfire2",
            "evidence_confidence": "proven",
            "frame_size": [16, 25],
            "frame_count": 10,
            "frame_advance_ticks": 1,
            "retail_top_left_offset": [12, 21],
        },
    }
    enemy_sheets = {
        "by_level": {
            str(level): {
                "texture": enemy_sheet_by_level[level],
                "hit_mask": f"{enemy_sheet_by_level[level]}_hma",
                "evidence_confidence": "proven",
            }
            for level in range(1, 101)
        },
        "resources_by_level": {
            str(level): [
                {
                    "resource_slot_id": resource["resource_slot_id"],
                    "raw_name": resource["raw_name"],
                    "enemy_sheet_id": resource["enemy_sheet_id"],
                    "texture": resource["enemy_sheet_id"],
                    "hit_mask": f"{resource['enemy_sheet_id']}_hma",
                    "evidence_confidence": "proven",
                }
                for resource in resources_by_level[level]
            ]
            for level in range(1, 101)
        },
    }
    projectile_sheets = {
        "player_weapons": {
            "texture": "weapons_big",
            "hit_mask": "weapons_big_hma",
            "evidence_confidence": "proven",
        },
        "enemy_projectiles": {
            "texture": None,
            "texture_selector": "firing_enemy_sheet",
            "texture_options": enemy_sheet_options,
            "source_rects": [[480, 0, 32, 32], [480, 32, 32, 32]],
            "evidence_confidence": "proven",
            "animation_phase": "authoritative_per_projectile_two_state",
            "animation_phase_confidence": "proven_runtime_contract",
            "type_id": 7,
            "spawn_top_left_offset": [13, 16],
            "sound": "alienshoot10",
            "suppressed_level_modes": [3],
            "hit_mask_contract": "res://content/sprite_frames.json#enemy_projectile_contracts/ordinary_type_7",
        },
        "supplemental_enemy_projectiles": {
            "texture": None,
            "texture_selector": "firing_enemy_sheet",
            "texture_options": enemy_sheet_options,
            "source_rects": [[448, 0, 32, 32], [448, 32, 32, 32]],
            "evidence_confidence": "proven",
            "animation_phase": "authoritative_per_projectile_two_state",
            "animation_phase_confidence": "proven_runtime_contract",
            "type_id": 6,
            "sound": "alienshoot2",
            "reachable_levels": [
                3, 7, 11, 15, 19, 23, 28, 32, 36, 40, 44, 48, 53, 57, 61,
                65, 69, 73, 78, 82, 86, 90, 94, 98,
            ],
            "hit_mask_contract": "res://content/sprite_frames.json#enemy_projectile_contracts/supplemental_state_6_type_6",
        },
    }
    pickup_sheets = {
        "bonuses": {
            "texture": "bonuses",
            "hit_mask": "bonuses_hma",
            "evidence_confidence": "proven",
            "frame_size": [20, 20],
            "frame_count": 10,
            "initial_frame_range": [2, 6],
            "frame_period_ticks": {"minimum_inclusive": 3.0, "maximum_exclusive": 7.0},
            "rows": {
                "letters_extra": [60, 80, 100, 120, 140],
                "extra_time": 480,
                "armour": 500,
                "money": [600, 580, 620, 640],
            },
        }
    }
    ui = {
        "title_logo": {"texture": "newlogo3", "evidence_confidence": "supported"},
        "title_logo_jpg_reference": {
            "texture": "newlogo3_jpg",
            "evidence_confidence": "verified_source",
            "runtime_binding": "reference_only",
        },
        "title_screen": {"texture": "newscreen", "evidence_confidence": "supported"},
        "splash_screen": {"texture": "splashscreen", "evidence_confidence": "supported"},
        "font_primary": {"texture": "abcd_2", "evidence_confidence": "proven"},
        "font_secondary": {"texture": "abcd_3", "evidence_confidence": "proven"},
        "font_small": {"texture": "abcd_4", "evidence_confidence": "proven"},
        "font_ending": {"texture": "endfont", "evidence_confidence": "verified_source"},
        "numbers": {
            "texture": "numbers",
            "evidence_confidence": "verified_source",
            "digit_cell_size": [8, 9],
            "digit_order": "0123456789",
            "palette_offsets": {"white": 0, "green": 168, "orange": 336, "purple": 504},
            "compact_style_offset": 80,
        },
        "numbers_256": {"texture": "numbers_256", "evidence_confidence": "supported"},
        "pause_overlay": {"texture": "pause3", "evidence_confidence": "supported"},
        "pause_label": {"texture": "pause4", "evidence_confidence": "supported"},
        "game_over": {"texture": "gameover", "evidence_confidence": "supported"},
    }
    bitmap_fonts = {
        "abcd_2": {
            "texture": "abcd_2",
            "renderer_va": "0x005d0660",
            "evidence_confidence": "proven",
            "cell_size": [8, 8],
            "advance": 8,
            "space_advance": 8,
            "source_rows": {"1": 13, "2": 21, "3": 29, "4": 37},
            "glyph_indices": {
                **{chr(ord("A") + index): index for index in range(26)},
                **{str(index): 26 + index for index in range(10)},
                ".": 36, ",": 37, ":": 38, "?": 39, "!": 40,
                "*": 41, "=": 42, "$": 43, "-": 45, "+": 47,
                "<": 48, ">": 49, "_": 50, "#": 51, "%": 52,
            },
            "pair_kerning": {},
            "layout": "fixed_advance_with_newline_and_embedded_style_controls",
            "evidence_boundary": "indices 44 and 46 retain source bytes but are not assigned semantic characters",
        },
        "abcd_3": {
            "texture": "abcd_3",
            "renderer_va": "0x005cfcd0",
            "evidence_confidence": "proven",
            "cell_size": [12, 9],
            "advance": 12,
            "space_advance": 12,
            "source_rows": {
                "0": 0, "1": 9, "2": 18, "3": 27, "4": 36, "5": 45,
                "6": 54, "7": 63, "8": 72, "9": 81, "10": 90,
            },
            "glyph_indices": {
                **{str(index): index for index in range(10)},
                **{chr(ord("A") + index): 10 + index for index in range(26)},
                ".": 36, ",": 37, "$": 38, "?": 39, "-": 39,
                "=": 40, ":": 41, "!": 42, "*": 43, "+": 44,
                "/": 45, "#": 46, "_": 47, "~": 48, "<": 50, ">": 51,
            },
            "pair_kerning": {},
            "layout": "fixed_advance",
            "evidence_boundary": "index 49 retains source bytes but is not assigned a semantic character",
        },
        "abcd_4": {
            "texture": "abcd_4",
            "renderer_va": "0x005d04a0",
            "evidence_confidence": "proven",
            "cell_size": [32, 24],
            "advance": 32,
            "space_advance": 32,
            "glyph_indices": {**{str(index): index for index in range(10)}, ":": 10},
            "pair_kerning": {},
            "layout": "fixed_advance",
        },
        "endfont": {
            "texture": "endfont",
            "renderer_va": "0x005d2560",
            "evidence_confidence": "verified_source_and_executable_consumer",
            "atlas_size": [800, 48],
            "layout": "retail_variable_width_table_retained_in_executable",
            "runtime_policy": "ending controller keeps its accessible text renderer until the complete variable-width table is semantically mapped",
            "evidence_boundary": "the executable consumes source-local offset, width, advance, and pair-adjustment tables; unmapped entries have no manufactured names",
        },
    }
    effects = {
        "policy": "executable_proven_original_bindings_only",
        "bindings": {
            "effect_type_10": "expl_small",
            "boss_retail_effect/FUN_005dfee0/boss_hit": "expl_small",
        },
        "enhanced_mode_fallbacks": {
            "enemy_destroyed": "expl_small",
            "player_destroyed": "expl_small",
            "enemy_hit": "flare1",
            "enemy_fired": "flare1",
            "weapon_fired": "flare1",
            "armour_hit": "flare2",
            "pickup_collected": "flare2",
            "rocket_expired": "flare4",
        },
        "evidence_confidence": "proven_geometry_timing_anchor_and_call_site",
        "small_explosion": {
            "texture": "expl_small",
            "frame_size": [32, 32],
            "columns": 5,
            "frame_count": 13,
            "frame_period_values": [0, 1],
            "frame_hold_updates": [1, 2],
            "lifetime_updates": [13, 26],
            "anchor": "center",
            "anchor_confidence": "proven",
            "blend_mode": "mix",
            "blend_mode_confidence": "intentional_runtime_policy",
            "draw_order": "world_effect_layer_after_gameplay_renderer",
            "draw_order_confidence": "intentional_runtime_policy",
            "evidence_confidence": "proven",
            "producer_function_va": "0x005dfee0",
            "producer_xref_thunk_va": "0x00526829",
            "state_13_impact_call_site_va": "0x00585c15",
            "state_13_branch_region": "0x00585a57-0x00585c19",
            "state_13_branch_sha256": "ea40f903dc5bce682a07058e7fdede5de7f25e0a4c1d2517ced056af9bf52ae5",
        },
        "effect_type_10_producer": {
            "status": "closed_authoritative_event_consumer",
            "retail_consumer": "state_13_player_projectile_impact_only",
            "authoritative_event": "boss_retail_effect",
            "authoritative_call": "FUN_005dfee0",
            "authoritative_payload_kind": "boss_hit",
            "allocation_response_field": "allocated_count",
            "allocation_gate": "emit and render only when the authoritative retail effect pool allocates at least one record",
            "authoritative_frame_period_field": "frame_period",
            "frame_period_contract": "period 0 holds each frame for one update; period 1 holds each frame for two updates",
            "runtime_policy": "the exact allocated nested authoritative call event or explicit type-10 metadata selects expl_small in original mode; pool-full calls and generic destruction events never do",
        },
    }
    shop = {
        "background": {"texture": "butikk3", "evidence_confidence": "supported"},
        "item_cards": SHOP_ITEM_KEYS,
        "evidence_confidence": "supported",
        "layout": {
            "logical_canvas": [800, 600],
            "background_rect": [0, 0, 800, 600],
            "background_policy": "native_full_canvas",
            "interactive_controls": "intentional_accessible_modern_overlay",
        },
    }
    bonus_modes = {
        "memory_station": {
            "texture": "memoryblocks",
            "music": "memory",
            "voice": "memorystation",
            "completion_sfx": "harpgliss1",
            "evidence_confidence": "proven",
        },
        "meteor_storm": {
            "meteor_texture": "meteors",
            "meteor_hit_mask": "meteors_hma",
            "bonus_texture": "meteorbonuses",
            "bonus_hit_mask": "meteorbonuses_hma",
            "meter_texture": "meteormeter2",
            "music": "meteor",
            "voice": "meteorstorm",
            "gem_voice": "bonus",
            "gem_drop_voice": "gemdrop",
            "evidence_confidence": "proven",
        },
        "gem_drop": {
            "texture": "diamantbig",
            "hit_mask": "diamantbig_hma",
            "music": "gems",
            "collection_sfx": "jingles",
            "voice": "bonus",
            "evidence_confidence": "proven",
        },
    }
    return {
        "backgrounds": backgrounds,
        "borders": borders,
        "fighter_sheets": fighter_sheets,
        "enemy_sheets": enemy_sheets,
        "projectile_sheets": projectile_sheets,
        "pickup_sheets": pickup_sheets,
        "ui": ui,
        "bitmap_fonts": bitmap_fonts,
        "effects": effects,
        "shop": shop,
        "bonus_modes": bonus_modes,
    }


def _ending_contract(
    game_root: Path,
    textures: dict[str, Any],
    music: dict[str, Any],
) -> dict[str, Any]:
    exe_path = game_root / "warblade.exe"
    exe_payload = exe_path.read_bytes()
    if _sha256_bytes(exe_payload) != WARBLADE_EXE_SHA256:
        raise ValueError("retail executable SHA-256 drift while extracting ending text")
    raw_text = exe_payload[
        ENDING_TEXT_FILE_OFFSET : ENDING_TEXT_FILE_OFFSET + ENDING_TEXT_BYTE_LENGTH
    ]
    if len(raw_text) != ENDING_TEXT_BYTE_LENGTH or _sha256_bytes(raw_text) != (
        ENDING_TEXT_SHA256
    ):
        raise ValueError("retail ending text bytes drifted")
    text = raw_text.decode("ascii")
    marker_index = text.find(ENDING_CREDITS_MARKER)
    if marker_index != ENDING_CREDITS_MARKER_INDEX or not text.startswith("|"):
        raise ValueError("retail ending text controls or credits boundary drifted")
    story_text = text[1:marker_index]
    credits_text = text[marker_index:]
    for texture_id in ENDING_SLIDE_IDS:
        texture = textures.get(texture_id)
        if not isinstance(texture, dict) or (
            texture.get("width"), texture.get("height")
        ) != (800, 600):
            raise ValueError(f"ending slide geometry drift for {texture_id}")
    if "endgame" not in music:
        raise ValueError("ending music is missing")
    return {
        "slides": [
            {"texture": texture_id, "duration_seconds": 15.0}
            for texture_id in ENDING_SLIDE_IDS
        ],
        "story_text": story_text,
        "credits_text": credits_text,
        "scroll_pixels_per_second": 30.0,
        "accelerated_multiplier": 8.0,
        "loop": False,
        "music": "endgame",
        "controls": {
            "left_mouse": "LEFT MOUSEBUTTON TO PAUSE",
            "right_mouse": "RIGHT MOUSEBUTTON TO SPEED UP",
            "continue": "ESC, SPACE OR FIRE TO CONTINUE",
        },
        "modes": {
            "0": {
                "title": "Congratulations",
                "text": "Our mission has been a success!",
                "duel_winner_template": "",
                "duel_draw_text": "",
                "fireworks": {
                    "enabled": True,
                    "texture": "flare1",
                    "sfx": "explo1",
                    "interval_seconds": 0.65,
                    "duration_seconds": 1.1,
                    "particle_count": 16,
                    "presentation_updates_per_second": 60,
                    "interval_updates": 39,
                    "duration_updates": 66,
                    "sequence_policy": "deterministic_clone_of_terminal_sim_rng",
                    "fidelity_class": "intentional_deterministic_modernization",
                },
            },
            "2": {
                "title": "DUEL COMPLETE",
                "text": "",
                "duel_winner_template": "PLAYER {player} WINS",
                "duel_draw_text": "DUEL DRAW",
                "fireworks": {
                    "enabled": True,
                    "texture": "flare1",
                    "sfx": "explo1",
                    "interval_seconds": 0.65,
                    "duration_seconds": 1.1,
                    "particle_count": 16,
                    "presentation_updates_per_second": 60,
                    "interval_updates": 39,
                    "duration_updates": 66,
                    "sequence_policy": "deterministic_clone_of_terminal_sim_rng",
                    "fidelity_class": "intentional_deterministic_modernization",
                },
                "fireworks_on_draw": False,
            },
        },
        "evidence": {
            "executable_sha256": WARBLADE_EXE_SHA256,
            "raw_text_va": f"0x{ENDING_TEXT_VA:08x}",
            "raw_text_file_offset": f"0x{ENDING_TEXT_FILE_OFFSET:08x}",
            "raw_text_byte_length": ENDING_TEXT_BYTE_LENGTH,
            "raw_text_sha256": ENDING_TEXT_SHA256,
            "leading_format_control": "|",
            "leading_format_control_rendered": False,
            "credits_marker_index_raw": ENDING_CREDITS_MARKER_INDEX,
            "ending_function_va": "0x005c6940-0x005c78a2",
            "slide_duration_ms": 15000,
            "instruction_overlay_duration_ms": 8000,
            "normal_scroll_pixels_per_update": "0.5",
            "accelerated_scroll_pixels_per_update": "4.0",
            "nominal_updates_per_second": 60,
            "text_loop": True,
            "final_slide_holds_until_continue": True,
            "left_mouse_scope": "hold_to_pause_text_scroll_only",
            "right_mouse_scope": "hold_to_accelerate_text_scroll_only",
            "music_pause_on_left_mouse": False,
            "slide_clock_pause_on_left_mouse": False,
            "firework_cadence_status": "intentional_deterministic_modernization_not_retail_claim",
            "mode_routing_status": "remake_terminal_policy_not_an_executable_branch",
            "campaign_trigger": "positive_level_divisible_by_100",
            "campaign_trigger_va": "0x0061beb2-0x0061bf17",
        },
    }


def _sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def _validate_declared_references(manifest: dict[str, Any]) -> None:
    textures = manifest["textures"]

    def require_texture(key: str, expected_kind: str = "texture") -> None:
        entry = textures.get(key)
        if entry is None:
            raise ValueError(f"presentation mapping references undeclared texture key: {key}")
        if entry["kind"] != expected_kind:
            raise ValueError(
                f"presentation mapping expected {expected_kind} for {key}, found {entry['kind']}"
            )

    for mapping in manifest["backgrounds"]["levels"].values():
        require_texture(mapping["texture"])
    for key in manifest["borders"]["by_difficulty"].values():
        require_texture(key)
    for mapping in manifest["fighter_sheets"]["players"].values():
        require_texture(mapping["texture"])
        require_texture(mapping["hit_mask"], "hit_mask")
    require_texture(manifest["fighter_sheets"]["thruster"]["texture"])
    for mapping in manifest["enemy_sheets"]["by_level"].values():
        require_texture(mapping["texture"])
        require_texture(mapping["hit_mask"], "hit_mask")
    for resources in manifest["enemy_sheets"]["resources_by_level"].values():
        for mapping in resources:
            require_texture(mapping["texture"])
            require_texture(mapping["hit_mask"], "hit_mask")
    for mapping in manifest["projectile_sheets"].values():
        if mapping["texture"] is not None:
            require_texture(mapping["texture"])
        if "hit_mask" in mapping:
            require_texture(mapping["hit_mask"], "hit_mask")
        for key in mapping.get("texture_options", []):
            require_texture(key)
        sound_key = mapping.get("sound")
        if sound_key is not None and sound_key not in manifest["sfx"]:
            raise ValueError(
                f"projectile mapping references undeclared SFX key: {sound_key}"
            )
    for mapping in manifest["pickup_sheets"].values():
        require_texture(mapping["texture"])
        require_texture(mapping["hit_mask"], "hit_mask")
    for mapping in manifest["ui"].values():
        require_texture(mapping["texture"])
    for mapping in manifest["bitmap_fonts"].values():
        require_texture(mapping["texture"])
    for key in manifest["effects"]["bindings"].values():
        require_texture(key)
    require_texture(manifest["shop"]["background"]["texture"])
    for key in manifest["shop"]["item_cards"].values():
        require_texture(key)
    require_texture(manifest["bonus_modes"]["memory_station"]["texture"])
    meteor = manifest["bonus_modes"]["meteor_storm"]
    require_texture(meteor["meteor_texture"])
    require_texture(meteor["meteor_hit_mask"], "hit_mask")
    require_texture(meteor["bonus_texture"])
    require_texture(meteor["bonus_hit_mask"], "hit_mask")
    require_texture(meteor["meter_texture"])
    gem_drop = manifest["bonus_modes"]["gem_drop"]
    require_texture(gem_drop["texture"])
    require_texture(gem_drop["hit_mask"], "hit_mask")
    ending = manifest["ending"]
    for slide in ending["slides"]:
        require_texture(slide["texture"])
    for mode in ending["modes"].values():
        fireworks = mode.get("fireworks")
        if isinstance(fireworks, dict) and bool(fireworks.get("enabled", True)):
            require_texture(str(fireworks["texture"]))
            if str(fireworks.get("sfx", "")) not in manifest["sfx"]:
                raise ValueError("ending fireworks reference undeclared SFX")
    if ending["music"] not in manifest["music"]:
        raise ValueError("ending mapping references undeclared music")

    hit_masks = [entry for entry in textures.values() if entry["kind"] == "hit_mask"]
    if any(entry["required"] for entry in hit_masks):
        raise ValueError("HMA hit masks must never enter Texture2D required-resource validation")
    missing_required = REQUIRED_TEXTURES - set(textures)
    if missing_required:
        raise ValueError(f"required presentation textures are missing: {sorted(missing_required)}")
    if REQUIRED_MUSIC - set(manifest["music"]):
        raise ValueError("required presentation music is missing")
    if REQUIRED_SFX - set(manifest["sfx"]):
        raise ValueError("required presentation SFX is missing")
    if REQUIRED_VOICES - set(manifest["voices"]):
        raise ValueError("required presentation voices are missing")
    for key in (
        manifest["bonus_modes"]["memory_station"]["voice"],
        meteor["voice"],
        meteor["gem_voice"],
        meteor["gem_drop_voice"],
        gem_drop["voice"],
    ):
        if key not in manifest["voices"]:
            raise ValueError(f"bonus-mode mapping references undeclared voice key: {key}")


def build_manifest(
    game_root: Path = DEFAULT_GAME_ROOT,
    provenance_path: Path = DEFAULT_PROVENANCE,
    asset_root: Path = DEFAULT_ASSET_ROOT,
) -> dict[str, Any]:
    inventory = warblade_presentation.build_inventory(game_root)
    provenance = read_json(provenance_path)
    selected = _selected_records(provenance)
    expected_hashes = {
        _source_id(record): record["source_sha256"]
        for records in selected.values()
        for record in records
    }
    warblade_presentation.validate_source_hashes(inventory, expected_hashes)
    textures, music, sfx, voices, voice_pack_2 = _build_asset_dictionaries(
        selected, inventory, asset_root.resolve()
    )
    presentation_sections = _presentation_sections(
        provenance.get("known_facts", {}).get("data", {}).get("levels")
    )
    manifest = {
        "version": 2,
        "schema": "warblade.presentation.v2",
        "source_inventory": {
            "schema": inventory["schema"],
            "pac": inventory["source"]["pac"],
            "retail_counts": inventory["counts"],
            "audio_formats": inventory["audio_formats"],
            "selected_counts": EXPECTED_SELECTED_COUNTS,
            "provenance_manifest": {
                "path": "docs/evidence/provenance_manifest.json",
                "sha256": sha256_file(provenance_path),
            },
        },
        "textures": textures,
        "music": music,
        "sfx": sfx,
        "voices": voices,
        "voice_packs": {
            "1": {
                "clip_count": len(voices),
                "complete": True,
                "source_section": "voices",
            },
            "2": {
                "clip_count": len(voice_pack_2),
                "complete": False,
                "fallback_pack": VOICE_PACK_2_FALLBACK,
                "clips": voice_pack_2,
            },
        },
        **presentation_sections,
        "ending": _ending_contract(game_root, textures, music),
    }
    _validate_declared_references(manifest)
    return manifest


def serialize_manifest(manifest: dict[str, Any]) -> bytes:
    return (json.dumps(manifest, indent=2, sort_keys=True) + "\n").encode("utf-8")


def build_evidence_markdown(manifest: dict[str, Any]) -> bytes:
    required_counts = {
        section: sum(1 for entry in manifest[section].values() if entry["required"])
        for section in ("textures", "music", "sfx", "voices")
    }
    source = manifest["source_inventory"]
    raster_count = sum(
        entry["kind"] == "texture" for entry in manifest["textures"].values()
    )
    hit_mask_count = sum(
        entry["kind"] == "hit_mask" for entry in manifest["textures"].values()
    )
    ending = manifest["ending"]
    lines = [
        "# Presentation assets",
        "",
        "`content/presentation.json` is generated from the Parser's validated retail inventory and the byte-for-byte extraction provenance manifest.",
        "",
        "Regenerate:",
        "",
        "```sh",
        "python3 tools/presentation_manifest.py",
        "```",
        "",
        "Verify without writing:",
        "",
        "```sh",
        "python3 tools/presentation_manifest.py --check",
        "```",
        "",
        "## Source integrity",
        "",
        f"- PAC: `{source['pac']['path']}`",
        f"- PAC SHA-256: `{source['pac']['sha256']}`",
        f"- Provenance SHA-256: `{source['provenance_manifest']['sha256']}`",
        "- TGA packet bounds, dimensions, depth, compression, and storage origin are validated by the Parser.",
        "- HMA values, peer dimensions, byte length, and top-left row-major orientation are validated by the Parser.",
        "- Every selected source hash is compared with provenance and with the extracted `res://` file.",
        "",
        "## Finite-product inventory",
        "",
        "| Namespace | Entries | Required at startup |",
        "|---|---:|---:|",
        f"| Textures and HMA masks | {len(manifest['textures'])} | {required_counts['textures']} |",
        f"| Music | {len(manifest['music'])} | {required_counts['music']} |",
        f"| SFX | {len(manifest['sfx'])} | {required_counts['sfx']} |",
        f"| Voices (pack 1, rank-0) | {len(manifest['voices'])} | {required_counts['voices']} |",
        f"| Voice pack 2 clips | {len(manifest['voice_packs']['2']['clips'])} | 0 |",
        "",
        f"The texture namespace contains {raster_count} Godot-loadable rasters and {hit_mask_count} HMA collision masks. HMA entries use `kind: hit_mask` and are never marked `required`, so they cannot be sent through Texture2D resource validation.",
        "",
        "Voice pack 2 is the retail alternate pack: 36 OGG clips selectable at runtime with a per-clip fallback to pack 1 where a counterpart exists (`pack_1_fallback_available`); `loser` is pack-2-only. The retail pack is incomplete by design, matching the original product.",
        "",
        "## Campaign bindings",
        "",
        "| Binding | Asset keys | Confidence |",
        "|---|---|---|",
        "| Level backgrounds | Levels 1–25 `stars1`; 26–50 `stars2`; 51–75 `stars3`; 76–99 `stars4`; remainder level 100 `stars1` | Proven selector and Warp-only two-quad scrolling contract at `0x00550900` |",
        "| Difficulty borders | `border_easy`, `border`, `border_hard`, `border_ace` | Proven by executable difficulty table |",
        "| Enemy sheets | All 100 level bindings and every declared resource slot, including `alien_big1_*` at 25, `alien_big2_*` at 50, `alien_big3_*` at 75, and `alien_big4_*` at 100 | Proven by exact LVD resources and executable atlas evidence |",
        "| Fighter sheets | `fighter1`, `fighter2` | Proven atlas and HMA geometry |",
        "| Player projectiles | `weapons_big` | Proven atlas and HMA geometry |",
        "| Alien projectiles | Firing enemy atlas (all eighty declared resource sheets), type 7 at x=480 with `alienshoot10`; supplemental type 6 at x=448 with `alienshoot2` | Proven executable bindings and sounds; per-sheet HMA bounds live in `sprite_frames.json` |",
        "| Fighter thrust | `figterfire2`, ten 16x25 frames | Proven executable geometry and one-tick advance |",
        "| Pickups | `bonuses`, ten 20x20 horizontal frames with recovered type rows and per-object phase/period | Proven executable bindings |",
        "| Original-core effects | Allocated authoritative `boss_retail_effect` / `FUN_005dfee0` / `boss_hit` | Proven state-13 impact binding, retail pool-allocation gate, exact period-0/1 timing, 13-frame geometry, and center anchor; mix blend and the world-effect child layer are explicit runtime policy, and filename-only candidates are not bound in original mode |",
        "",
        "Memory Station, Meteor Storm, and the terminal Gem Drop controller have byte-pinned textures, hit masks, music, SFX, and rank-0 announcement cues in dedicated bonus-mode namespaces. Rank-promotion cues required by ranks 1–20 share the voice namespace.",
        "",
        "## Ending sequence",
        "",
        f"The terminal presentation uses {len(ending['slides'])} byte-pinned 800×600 JPEG slides in retail order (`ending_5`, `ending_4`, `ending_6`, `ending_3`, `ending_0`, `ending_1`, `ending_9`, `ending_7`, `ending_8`, `ending_2`, `ending_10`, `ending_11`, `ending_12`), each for 15 seconds, with `endgame` music. Story and credits text are extracted from the exact {ending['evidence']['raw_text_byte_length']}-byte executable region `{ending['evidence']['raw_text_sha256']}`; the leading `|` is a consumed format control and is not rendered. Text advances at 30 pixels/second or 8× while right mouse is held; left mouse pauses text only, and neither control pauses slide timing or music. The final slide holds until Escape, Space, or Fire.",
        "",
        "## Collision-safe keys",
        "",
        "Texture, music, SFX, and voice are separate namespaces. The four historically selected announcement cues remain addressable in SFX for compatibility while their provenance category and canonical entries are voice. Original underscores are retained. HMA keys receive `_hma`; `newlogo3.tga` owns `newlogo3`, while the reference JPG is `newlogo3_jpg`.",
        "",
        "## Closed runtime contracts and evidence-only boundaries",
        "",
        "- The background uses the whole 1024×1024 source in two 672×600 destination quads at x=64. The authoritative 60 Hz simulation captures the pre-update draw offset and then applies each float32 Warp `scale / 20` step with 0/600 wrapping; snapshots publish both values, and the client performs wrapped high-refresh interpolation between draw offsets. The traced path has one layer, so no parallax layer is manufactured.",
        "- Alien projectile atlas binding, source rectangles, and authoritative two-row phase are proven; snapshot state owns the phase, including reused simulation slots.",
        "- Original mode binds the 13-frame small explosion from an allocated authoritative state-13 `boss_retail_effect` whose exact call is `FUN_005dfee0` and nested kind is `boss_hit`; a pool-full dispatch emits no presentation event, and the client requires both a positive `allocated_count` and the authoritative `frame_period`. Period 0 advances every update for a 13-update lifetime; period 1 advances every second update for a 26-update lifetime. Explicit type-10 metadata remains accepted. Generic destruction fallbacks are an intentional enhanced-mode presentation and are not a retail claim.",
        "- Fixed metrics and glyph maps for `abcd_2`, `abcd_3`, and `abcd_4` are executable-proven. `endfont` is now losslessly packaged; its executable-local variable-width tables remain evidence-only until every index can be named without invention.",
        "- Title, pause, game-over, and shop retain native retail bitmap geometry where those whole assets are consumed. Accessible interactive labels, controls, and their timing are intentional macOS modernization; they are not presented as reconstructed retail composition.",
        "- Required SFX use an intentional runtime mix policy. Unreferenced sounds remain packaged source evidence and have no runtime tuning consumer.",
        "- Winner fireworks are deterministic from a clone of terminal simulation RNG. Their cadence and particle composition are intentional presentation modernization, not claimed retail reconstruction; Duel draws suppress them.",
        "",
    ]
    return "\n".join(lines).encode("utf-8")


def _atomic_write(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary_name, path)
    except BaseException:
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass
        raise


def _check_file(path: Path, expected: bytes) -> bool:
    if not path.is_file():
        print(f"missing generated presentation artifact: {path}", file=sys.stderr)
        return False
    actual = path.read_bytes()
    if actual != expected:
        print(f"stale generated presentation artifact: {path}", file=sys.stderr)
        return False
    return True


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate the strict Godot presentation manifest from Parser inventory."
    )
    parser.add_argument("--game-root", type=Path, default=DEFAULT_GAME_ROOT)
    parser.add_argument("--provenance", type=Path, default=DEFAULT_PROVENANCE)
    parser.add_argument("--asset-root", type=Path, default=DEFAULT_ASSET_ROOT)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--evidence", type=Path, default=DEFAULT_EVIDENCE)
    parser.add_argument("--check", action="store_true")
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    manifest = build_manifest(
        arguments.game_root.resolve(),
        arguments.provenance.resolve(),
        arguments.asset_root.resolve(),
    )
    manifest_bytes = serialize_manifest(manifest)
    evidence_bytes = build_evidence_markdown(manifest)
    output = arguments.output.resolve()
    evidence = arguments.evidence.resolve()
    if arguments.check:
        return 0 if _check_file(output, manifest_bytes) and _check_file(evidence, evidence_bytes) else 1
    _atomic_write(output, manifest_bytes)
    _atomic_write(evidence, evidence_bytes)
    print(
        f"generated {len(manifest['textures'])} textures, "
        f"{len(manifest['music'])} music tracks, {len(manifest['sfx'])} SFX, "
        f"and {len(manifest['voices'])} voices"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
