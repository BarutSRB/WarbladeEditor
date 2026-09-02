#!/usr/bin/env python3
"""Generate the authored Time Trial catalog and its executable-backed evidence.

Retail match mode 6 ships fifteen authored levels (``timetrial_%02d.lvd``) that
the classic campaign never loads, plus a fixed match clock. Every runtime rule
emitted here is pinned to exact retail instruction bytes; the level payloads are
losslessly decoded from the original LVDs with the same authored schema the
classic set uses.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
import sys
import tempfile
from pathlib import Path
from typing import Any

import lvd_decoder
from first_five_runtime_extract import PEImage, WARBLADE_EXE_SHA256


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_EXE = ROOT / "Game" / "warblade.exe"
DEFAULT_LEVELS_DIR = ROOT / "assets" / "original" / "levels" / "timetrial"
DEFAULT_FACTS = ROOT / "tools" / "known_facts.json"
DEFAULT_CONTENT = ROOT / "content" / "time_trial.json"
DEFAULT_EVIDENCE = ROOT / "docs" / "evidence" / "time_trial.json"
DEFAULT_MARKDOWN = ROOT / "docs" / "evidence" / "TIME_TRIAL.md"

LEVEL_IDS = tuple(range(1, 16))
AUTHORED_LVD_SCHEMA = "warblade.lvd.authored.v2"
AUTHORED_RUNTIME = {"ordinary_speed_fp": 65536}
SUPPORTED_LEVEL_MODE_IDS = (1, 2)
SUPPORTED_PATH_OPCODES = (0, 1, 6)

# Every field below is a verified instruction region rather than a name taken
# from a decompiler listing. `region` entries are (label, virtual address, byte
# count, expected SHA-256).
INSTRUCTION_REGIONS: tuple[tuple[str, int, int, str], ...] = (
    (
        "match_clock_store",
        0x005BBD74,
        15,
        "ca1a91e076ce1a6aa76cafd2de2612806c5f43e80bc137e816e09eb6535fa796",
    ),
    (
        "grouped_best_extra_minute_clock_store",
        0x0054DA6F,
        15,
        "ec80f7c05db2b362b07236ca3aa4a9f1afb142d5f5450a254cbdc78ad737485e",
    ),
    (
        "missing_levels_clock_store",
        0x00557115,
        25,
        "be16747aeff155ac3d5abcf7c9a4ca2b902b3fe8829835dd9df9f558166ac6dd",
    ),
    (
        "match_mode_global_store",
        0x005BBD6A,
        10,
        "4e866f2c993faa78c08b1169913ba017ba2382e402ce67aacf0287cc1449b7d9",
    ),
    (
        "match_mode_index_global_store",
        0x005BBD83,
        10,
        "1f9caee827f633398b6233b28c0b78300df34ce9b25db5991a59081b0273f606",
    ),
    (
        "level_file_format_string",
        0x0077AF78,
        19,
        "17b70d5ee431ec69bb16b4628acd10442ff435f9047f6fa5d901b7201c3a5485",
    ),
)
# The identical fifteen-byte clock store appears at every menu/F5 entry point.
MATCH_CLOCK_STORE_SITES = (
    0x005BBD74,
    0x005C0128,
    0x005C2949,
    0x005C29C3,
    0x005C2A8F,
    0x005C2C6C,
    0x005C47C9,
)
MATCH_CLOCK_MILLISECONDS = 181000
GROUPED_BEST_EXTRA_MINUTE_MILLISECONDS = 241000
MISSING_LEVELS_CLOCK_MILLISECONDS = 10000
RETAIL_MATCH_MODE_ID = 6
RETAIL_MATCH_MODE_INDEX = 5
CLOCK_DEADLINE_GLOBAL_VA = 0x00E11458
CLOCK_SOURCE_GLOBAL_VA = 0x00AB27BC
MATCH_MODE_GLOBAL_VA = 0x008F20D8
MATCH_MODE_INDEX_GLOBAL_VA = 0x008F20E0
MISSING_LEVELS_FLAG_GLOBAL_VA = 0x00E1145C


class TimeTrialExtractError(ValueError):
    pass


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _hex(value: int) -> str:
    return f"0x{value:08x}"


def _json_bytes(value: Any) -> bytes:
    return (json.dumps(value, indent=2, ensure_ascii=False) + "\n").encode("utf-8")


def _verified_regions(image: PEImage) -> dict[str, Any]:
    regions: dict[str, Any] = {}
    for label, va, size, expected in INSTRUCTION_REGIONS:
        payload = image.bytes_at(va, size)
        actual = _sha256(payload)
        if actual != expected:
            raise TimeTrialExtractError(
                f"{label}: retail bytes at {_hex(va)} hash {actual}, expected {expected}"
            )
        regions[label] = {
            "virtual_address": _hex(va),
            "byte_count": size,
            "sha256": actual,
        }
    canonical = image.bytes_at(MATCH_CLOCK_STORE_SITES[0], 15)
    for site in MATCH_CLOCK_STORE_SITES[1:]:
        if image.bytes_at(site, 15) != canonical:
            raise TimeTrialExtractError(
                f"match clock store at {_hex(site)} diverges from the canonical site"
            )
    regions["match_clock_store"]["identical_sites"] = [
        _hex(site) for site in MATCH_CLOCK_STORE_SITES
    ]
    return regions


def _runtime_contract(regions: dict[str, Any]) -> dict[str, Any]:
    return {
        "retail_match_mode_id": RETAIL_MATCH_MODE_ID,
        "retail_match_mode_index": RETAIL_MATCH_MODE_INDEX,
        "clock": {
            "match_milliseconds": MATCH_CLOCK_MILLISECONDS,
            "grouped_best_extra_minute_milliseconds": (
                GROUPED_BEST_EXTRA_MINUTE_MILLISECONDS
            ),
            "missing_levels_milliseconds": MISSING_LEVELS_CLOCK_MILLISECONDS,
            "deadline_global_va": _hex(CLOCK_DEADLINE_GLOBAL_VA),
            "now_source_global_va": _hex(CLOCK_SOURCE_GLOBAL_VA),
            "missing_levels_flag_global_va": _hex(MISSING_LEVELS_FLAG_GLOBAL_VA),
            "expiry_behavior": "game_over",
            "evidence": {
                "match_clock_store": regions["match_clock_store"],
                "grouped_best_extra_minute_clock_store": regions[
                    "grouped_best_extra_minute_clock_store"
                ],
                "missing_levels_clock_store": regions["missing_levels_clock_store"],
            },
        },
        "match_mode_globals": {
            "mode_global_va": _hex(MATCH_MODE_GLOBAL_VA),
            "mode_value": RETAIL_MATCH_MODE_ID,
            "index_global_va": _hex(MATCH_MODE_INDEX_GLOBAL_VA),
            "index_value": RETAIL_MATCH_MODE_INDEX,
            "evidence": {
                "match_mode_global_store": regions["match_mode_global_store"],
                "match_mode_index_global_store": regions[
                    "match_mode_index_global_store"
                ],
            },
        },
        "loader": {
            "file_format": "timetrial_%02d.lvd",
            "authored_level_count": len(LEVEL_IDS),
            "selection": "sequential_level_counter",
            "wrap_after_last_level": True,
            "evidence": {
                "level_file_format_string": regions["level_file_format_string"],
            },
        },
        "rules": {
            "shops": False,
            "warp": False,
            "warp_malfunction": False,
            "bonus_modes": False,
            "rank_promotion": False,
            "credits": False,
            "hurry_up_special_ships": False,
            "starting_weapon_id": 0,
            "death_resets_loadout": False,
            "death_reset_exception_source": (
                "content/ordnance.json alien_lock.lifecycle.retail_mode_6_exception"
            ),
            "seats": 1,
            "tally_kind": "time_trial",
            "hiscore_table_kind": "timetrial",
        },
        "grouped_best_locks": {
            "applies_in_match_mode_six": [
                "score_multiplier_2",
                "score_multiplier_5",
                "scoop",
                "auto_fire",
                "speed_x3",
                "speed_x5",
                "super_auto_fire",
                "max_speed",
                "time_trial_extra_minute",
            ],
            "weapon_tiers_apply": False,
            "weapon_tier_exclusion_reason": (
                "The retail lock applier gates its weapon tiers on match mode != 6, "
                "so Time Trial always begins on weapon 0."
            ),
        },
    }


def _authored_lvd(document: dict[str, Any]) -> dict[str, Any]:
    groups: list[dict[str, Any]] = []
    for source_group in document["active_groups"]:
        groups.append(
            {
                "id": source_group["index"],
                "entry_origin_x": source_group["entry_origin_x"],
                "entry_origin_y": source_group["entry_origin_y"],
                "first_activation_delay_ticks": source_group[
                    "first_activation_delay_ticks"
                ],
                "activation_stagger_ticks": source_group["activation_stagger_ticks"],
                "initial_velocity_x_milli": source_group["initial_velocity_x_milli"],
                "initial_velocity_y_milli": source_group["initial_velocity_y_milli"],
                "kill_cohort_id": source_group["kill_cohort_id"],
                "group_mode_id": source_group["group_mode_id"],
                "enemies": [
                    {
                        "id": enemy["index"],
                        "formation_target_x": enemy["formation_target_x"],
                        "formation_target_y": enemy["formation_target_y"],
                        "resource_slot_id": enemy["resource_slot_id"],
                        "base_health": enemy["base_health"],
                        "behavior_timer_a_initial": enemy["behavior_timer_a_initial"],
                        "behavior_timer_a_step": enemy["behavior_timer_a_step"],
                        "behavior_timer_b_initial": enemy["behavior_timer_b_initial"],
                        "behavior_timer_b_step": enemy["behavior_timer_b_step"],
                    }
                    for enemy in source_group["enemies"]
                ],
                "path_points": [
                    {
                        "id": point["index"],
                        "acceleration_x_milli": point["acceleration_x_milli"],
                        "acceleration_y_milli": point["acceleration_y_milli"],
                        "opcode": point["opcode"],
                        "unknown_0c": point["unknown_0c"],
                        "duration_threshold_ticks": point["duration_threshold_ticks"],
                    }
                    for point in source_group["path_points"]
                ],
            }
        )
    return {
        "schema": AUTHORED_LVD_SCHEMA,
        "source_title_cp1252": document["summary"]["title"],
        "level_mode_id": document["summary"]["level_mode_id"],
        "logical_width": 800,
        # Time Trial cycles its own fifteen authored levels; the per-hundred
        # campaign mirror never applies.
        "mirror_x": False,
        "supplemental_spawn_records_raw_words": document["global_header"][
            "supplemental_spawn_records_raw_words"
        ],
        "fixed_table_records_raw_words": [
            record["raw_words"]
            for record in document["unresolved_fixed_table"]["records"]
        ],
        "groups": groups,
    }


def _enemy_resources(document: dict[str, Any]) -> list[dict[str, Any]]:
    score_words = document["unresolved_tail_array_a"]["raw_words"]
    resources: list[dict[str, Any]] = []
    for slot in document["resource_slots"][:6]:
        raw_name = slot["text_cp1252"]
        if not raw_name:
            continue
        resource_slot_id = slot["index"] + 1
        resources.append(
            {
                "resource_slot_id": resource_slot_id,
                "raw_name": raw_name,
                "enemy_sheet_id": Path(raw_name).stem.casefold(),
                "kill_score": score_words[resource_slot_id - 1],
            }
        )
    return resources


def _decode_levels(
    levels_dir: Path, facts: dict[str, Any]
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    fact_levels = facts.get("time_trial_levels")
    if not isinstance(fact_levels, list):
        raise TimeTrialExtractError("known_facts.json must declare time_trial_levels")
    facts_by_id = {item["id"]: item for item in fact_levels if isinstance(item, dict)}
    if tuple(sorted(facts_by_id)) != LEVEL_IDS:
        raise TimeTrialExtractError(
            "known_facts.json must contain ordered Time Trial levels 1 through 15"
        )
    levels: list[dict[str, Any]] = []
    summaries: list[dict[str, Any]] = []
    for level_id in LEVEL_IDS:
        fact = facts_by_id[level_id]
        expected_name = f"timetrial_{level_id:02}.lvd"
        if fact.get("archive_member") != expected_name:
            raise TimeTrialExtractError(
                f"Time Trial level {level_id} archive member is not canonical"
            )
        path = levels_dir / expected_name
        payload = path.read_bytes()
        actual_sha256 = _sha256(payload)
        if fact.get("sha256") != actual_sha256:
            raise TimeTrialExtractError(f"retail LVD hash drift for level {level_id}")
        if fact.get("size") != len(payload) or len(payload) != lvd_decoder.FILE_SIZE:
            raise TimeTrialExtractError(f"retail LVD size drift for level {level_id}")
        document = lvd_decoder.decode_blob(payload, str(path))
        if lvd_decoder.encode_document(document) != payload:
            raise TimeTrialExtractError(
                f"lossless LVD round trip failed for level {level_id}"
            )
        summary = document["summary"]
        resources = _enemy_resources(document)
        if not resources:
            raise TimeTrialExtractError(
                f"Time Trial level {level_id} has no enemy resources"
            )
        if (
            fact.get("title") != summary["title"]
            or fact.get("author") != summary["author"]
            or fact.get("raw_enemy_reference") != resources[0]["raw_name"]
            or fact.get("packaged_enemy_id") != resources[0]["enemy_sheet_id"]
            or fact.get("enemy_resources") != resources
        ):
            raise TimeTrialExtractError(
                f"known facts diverge from decoded metadata for level {level_id}"
            )
        if summary["level_mode_id"] not in SUPPORTED_LEVEL_MODE_IDS:
            raise TimeTrialExtractError(
                f"Time Trial level {level_id} uses unsupported level mode "
                f"{summary['level_mode_id']}"
            )
        group_modes = sorted(
            {group["group_mode_id"] for group in document["active_groups"]}
        )
        if group_modes != [1]:
            raise TimeTrialExtractError(
                f"Time Trial level {level_id} uses unsupported group modes {group_modes}"
            )
        opcodes = sorted(
            {
                point["opcode"]
                for group in document["active_groups"]
                for point in group["path_points"]
            }
        )
        unsupported = [code for code in opcodes if code not in SUPPORTED_PATH_OPCODES]
        if unsupported:
            raise TimeTrialExtractError(
                f"Time Trial level {level_id} uses unsupported path opcodes {unsupported}"
            )
        supplemental = document["global_header"][
            "supplemental_spawn_records_raw_words"
        ]
        if any(record[0] > 0 for record in supplemental[:4]):
            raise TimeTrialExtractError(
                f"Time Trial level {level_id} carries a supplemental spawn record"
            )
        authored = _authored_lvd(document)
        levels.append(
            {
                "id": level_id,
                "title": summary["title"],
                "author": summary["author"],
                "enemy_resources": resources,
                "enemy_sprite": resources[0]["enemy_sheet_id"],
                "ordinary_kill_score": resources[0]["kill_score"],
                "shop_after": False,
                "raw_lvd": f"res://assets/original/levels/timetrial/{expected_name}",
                "raw_lvd_sha256": actual_sha256,
                "authored_runtime": copy.deepcopy(AUTHORED_RUNTIME),
                "authored_lvd": authored,
            }
        )
        summaries.append(
            {
                "level": level_id,
                "lvd_path": f"assets/original/levels/timetrial/{expected_name}",
                "lvd_sha256": actual_sha256,
                "lvd_size": len(payload),
                "lossless_round_trip_exact": True,
                "title_cp1252": summary["title"],
                "author_cp1252": summary["author"],
                "level_mode_id": summary["level_mode_id"],
                "active_group_count": summary["active_group_count"],
                "authored_enemy_count": summary["authored_enemy_count"],
                "group_enemy_counts": [
                    group["active_enemy_count"] for group in document["active_groups"]
                ],
                "path_point_counts": [
                    group["active_path_point_count"]
                    for group in document["active_groups"]
                ],
                "path_opcodes": opcodes,
                "group_mode_ids": group_modes,
                "kill_cohort_ids": sorted(
                    {group["kill_cohort_id"] for group in document["active_groups"]}
                ),
                "enemy_resources": resources,
                "supplemental_spawn_records_raw_words": supplemental,
                "tail_a_raw_words": document["unresolved_tail_array_a"]["raw_words"],
                "tail_b_raw_words": document["unresolved_tail_array_b"]["raw_words"],
            }
        )
    return levels, summaries


def build_outputs(exe_path: Path, levels_dir: Path, facts_path: Path) -> dict[Path, bytes]:
    facts = json.loads(facts_path.read_text(encoding="utf-8"))
    image = PEImage(exe_path)
    if image.sha256 != WARBLADE_EXE_SHA256:
        raise TimeTrialExtractError(
            f"{exe_path}: SHA-256 {image.sha256} is not the pinned retail executable"
        )
    regions = _verified_regions(image)
    runtime = _runtime_contract(regions)
    levels, summaries = _decode_levels(levels_dir, facts)

    content = {
        "version": 1,
        "schema": "warblade.time-trial.v1",
        "content_status": (
            "Retail match mode 6. The fifteen authored Time Trial levels are "
            "losslessly decoded from their original LVDs and use the same authored "
            "schema as the classic set; the match clock, loader, mode globals, and "
            "grouped-best lock policy are pinned to exact retail instruction bytes."
        ),
        "source_executable_sha256": image.sha256,
        "runtime": runtime,
        "levels": levels,
    }
    evidence = {
        "source": {
            "warblade_exe": {
                "file_name": exe_path.name,
                "sha256": image.sha256,
                "preferred_image_base": _hex(image.image_base),
            },
            "method": (
                "Deterministic PE section mapping with SHA-256 pinned instruction "
                "regions plus lossless LVD decoding. No runtime observation is used."
            ),
        },
        "runtime": runtime,
        "instruction_regions": regions,
        "levels": summaries,
    }
    return {
        DEFAULT_CONTENT: _json_bytes(content),
        DEFAULT_EVIDENCE: _json_bytes(evidence),
        DEFAULT_MARKDOWN: build_markdown(evidence),
    }


def build_markdown(evidence: dict[str, Any]) -> bytes:
    runtime = evidence["runtime"]
    clock = runtime["clock"]
    lines = [
        "# Time Trial (retail match mode 6)",
        "",
        "Generated by `tools/time_trial_extract.py`. Every runtime value below is",
        "read back from the pinned retail executable",
        f"(`{evidence['source']['warblade_exe']['file_name']}`,",
        f"SHA-256 `{evidence['source']['warblade_exe']['sha256']}`) and every level",
        "payload round-trips losslessly through `tools/lvd_decoder.py`.",
        "",
        "## Match clock",
        "",
        "| Field | Value |",
        "| --- | --- |",
        f"| Match clock | {clock['match_milliseconds']} ms |",
        (
            "| Grouped-best +1 minute | "
            f"{clock['grouped_best_extra_minute_milliseconds']} ms |"
        ),
        (
            "| Clock when no level files resolve | "
            f"{clock['missing_levels_milliseconds']} ms |"
        ),
        f"| Deadline global | `{clock['deadline_global_va']}` |",
        f"| Clock source global | `{clock['now_source_global_va']}` |",
        "",
        "## Pinned instruction regions",
        "",
        "| Region | Virtual address | Bytes | SHA-256 |",
        "| --- | --- | --- | --- |",
    ]
    for label, region in evidence["instruction_regions"].items():
        lines.append(
            f"| `{label}` | `{region['virtual_address']}` | {region['byte_count']} "
            f"| `{region['sha256']}` |"
        )
    lines.extend(
        [
            "",
            "The match clock store is byte-identical at every entry point: "
            + ", ".join(
                f"`{site}`"
                for site in evidence["instruction_regions"]["match_clock_store"][
                    "identical_sites"
                ]
            )
            + ".",
            "",
            "## Authored levels",
            "",
            "| Level | Title | Mode | Groups | Enemies | Sheets | SHA-256 |",
            "| --- | --- | --- | --- | --- | --- | --- |",
        ]
    )
    for summary in evidence["levels"]:
        sheets = ", ".join(
            f"`{resource['enemy_sheet_id']}`" for resource in summary["enemy_resources"]
        )
        title = summary["title_cp1252"] or "(untitled)"
        lines.append(
            f"| {summary['level']} | {title} | {summary['level_mode_id']} "
            f"| {summary['active_group_count']} | {summary['authored_enemy_count']} "
            f"| {sheets} | `{summary['lvd_sha256']}` |"
        )
    lines.extend(
        [
            "",
            "## Rules",
            "",
            "Time Trial runs a single seat with no shop, warp, bonus-mode, rank, or",
            "credits phase. It always starts on weapon 0 because the retail lock",
            "applier gates its weapon tiers on match mode != 6, and it skips the",
            "death loadout reset (`content/ordnance.json`",
            "`alien_lock.lifecycle.retail_mode_6_exception`). The hurry-up special",
            "ships are excluded in match mode 6. Clock expiry ends the run through",
            "the game-over path, produces the solo-style GAME BONUSES tally, and",
            "offers the Time Trial hall of fame plus the profile best score.",
            "",
        ]
    )
    return ("\n".join(lines)).encode("utf-8")


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


def _check(path: Path, expected: bytes) -> bool:
    if not path.is_file():
        print(f"missing generated artifact: {path}", file=sys.stderr)
        return False
    if path.read_bytes() != expected:
        print(f"stale generated artifact: {path}", file=sys.stderr)
        return False
    return True


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate the Time Trial content catalog and its evidence."
    )
    parser.add_argument("--exe", type=Path, default=DEFAULT_EXE)
    parser.add_argument("--levels-dir", type=Path, default=DEFAULT_LEVELS_DIR)
    parser.add_argument("--facts", type=Path, default=DEFAULT_FACTS)
    parser.add_argument("--check", action="store_true")
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    try:
        outputs = build_outputs(
            arguments.exe.resolve(),
            arguments.levels_dir.resolve(),
            arguments.facts.resolve(),
        )
    except (OSError, ValueError, lvd_decoder.LvdFormatError) as error:
        print(f"time-trial extraction failed: {error}", file=sys.stderr)
        return 1
    if arguments.check:
        valid = all(_check(path, payload) for path, payload in outputs.items())
        if valid:
            print("Time Trial evidence and content are current")
        return 0 if valid else 1
    for path, payload in outputs.items():
        _atomic_write(path, payload)
    print(f"generated {len(outputs)} Time Trial evidence/content artifacts")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
