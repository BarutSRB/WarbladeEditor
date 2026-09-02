#!/usr/bin/env python3
"""Extract the executable-backed profile lock contract.

Sources inside the pinned retail executable:

- ``FUN_0054d440`` applies the start-with lock effects when a new solo
  (mode 0) or Time Trial (mode 6) match starts with an open profile:
  the in-the-game score tiers, the grouped-best tiers (Time Trial matches
  read the grouped best through getter ``0x005465d0``), the 50,000 /
  75,000 / 100,000 games-played tiers, the find-all-secrets award (full
  armour, or 2,000 cash when armour is already full, plus Super Triple),
  the above-200,000,000 secret-counter display, the 70/80/90 hit-rate
  shop unlock values, and the undocumented rank-32 package granted at the
  terminal WARBLADE GOD SOL rank.
- ``FUN_0054a260`` is the USER PROFILES locks screen; it renders every
  lock label and evaluates the same thresholds for display, which pins
  the flag-style games-played tiers (1,000 through 35,000) and the
  meteor-storm fastest-time locks (values in milliseconds).
- Flag-style tiers are consumed at their behavior sites (shop exit for
  autofire-through-shop, the bonus drop selector for the shot-off flags,
  coin spawning for only-blue-coins, the Meteor Storm multiplier gate).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_EXE = PROJECT_ROOT / "Game" / "warblade.exe"
DEFAULT_OUTPUT = PROJECT_ROOT / "docs" / "evidence" / "profile_locks.json"
DEFAULT_DOCUMENT = PROJECT_ROOT / "docs" / "evidence" / "PROFILE_LOCKS.md"

EXPECTED_EXE_SHA256 = "ddf1778c307af1087ff9dcb512786111e665d972298aeaac3f1b4b2996d079ef"

FUNCTIONS = {
    "start_state_applier": "0x0054d440",
    "locks_screen": "0x0054a260",
    "grouped_best_getter": "0x005465d0",
}

# Label substrings pinned by byte comparison (substring -> its data VA).
LABEL_PINS = {
    "AUTOFIRE WILL LAST THROUGH SHOP": 0x0077A714,
    "START WITH MISSILE STEALTH": 0x0077A6E8,
    "START WITH GEM COUNTER ON": 0x0077A6C0,
    "START WITH SECRET COUNTER ON": 0x0077A957,
    "FIND ALL SECRETS": 0x0077A774,
    "MAX EXTRA TIME IS 60 SECONDS": 0x0077A86E,
}

CONTRACT = {
    "applies_to_modes": ["solo", "time_trial"],
    "score_tiers": [
        {"threshold": 5000000, "effect": "bullet_capacity", "value": 10},
        {"threshold": 7500000, "effect": "speed_steps", "value": 3},
        {"threshold": 10000000, "effect": "auto_fire", "value": 1},
        {"threshold": 20000000, "effect": "weapon_at_least", "value": 1},
        {"threshold": 50000000, "effect": "armour_charges", "value": 1},
        {"threshold": 100000000, "effect": "money", "value": 500},
        {"threshold": 250000000, "effect": "money", "value": 1000},
        {"threshold": 500000000, "effect": "armour_charges", "value": 2},
        {"threshold": 1000000000, "effect": "weapon_at_least", "value": 2},
    ],
    "grouped_best_tiers": [
        {"threshold": 5000000, "effect": "score_multiplier", "value": 2},
        {"threshold": 6000000, "effect": "scoop", "value": 1},
        {"threshold": 7000000, "effect": "score_multiplier", "value": 5},
        {"threshold": 8000000, "effect": "auto_fire", "value": 1},
        {"threshold": 9000000, "effect": "speed_steps", "value": 3},
        {"threshold": 10000000, "effect": "speed_steps", "value": 5},
        {"threshold": 15000000, "effect": "super_auto_fire", "value": 1},
        {"threshold": 17000000, "effect": "speed_steps_max", "value": 1},
        {"threshold": 20000000, "effect": "time_trial_extra_minute", "value": 1},
    ],
    "games_played_tiers": [
        {"threshold": 1000, "effect": "autofire_through_shop", "value": 1},
        {"threshold": 2500, "effect": "missile_stealth", "value": 1},
        {"threshold": 5000, "effect": "gem_counter_on", "value": 1},
        {"threshold": 10000, "effect": "single_shot_bonus_off", "value": 1},
        {"threshold": 15000, "effect": "double_shot_bonus_off", "value": 1},
        {"threshold": 20000, "effect": "only_blue_coins", "value": 1},
        {"threshold": 25000, "effect": "triple_shot_bonus_off", "value": 1},
        {"threshold": 35000, "effect": "meteor_multiplier_enabled", "value": 1},
        {"threshold": 50000, "effect": "weapon_at_least", "value": 3},
        {"threshold": 75000, "effect": "bullet_speed_up", "value": 1},
        {"threshold": 100000, "effect": "good_start_package", "value": 1},
    ],
    "good_start_package": {
        "speed_steps": "half_of_maximum",
        "bullet_capacity": 25,
        "bonus_time": "half_of_difficulty_maximum",
        "money": 5000,
    },
    "hit_percent_shop_unlocks": [
        {"threshold": 70, "shop_item": 18},
        {"threshold": 80, "shop_item": 19},
        {"threshold": 90, "shop_item": 20},
    ],
    "fastest_meteor_locks": [
        {"threshold_ms": 2000, "effect": "extra_time_max", "value": 60},
        {"threshold_ms": 1000, "effect": "extra_time_max", "value": 90},
    ],
    "find_all_secrets": {
        "secret_count": 30,
        "effects": [
            {"effect": "armour_full_or_money", "money_fallback": 2000},
            {"effect": "weapon_at_least", "value": 4},
        ],
    },
    "secret_counter_display": {"threshold": 200000000, "exclusive": True},
    "rank_32_package": {
        "highest_rank": 32,
        "effects": {
            "bonus_time": "difficulty_maximum",
            "money": 25000,
            "bullet_speed_up": 1,
            "weapon_at_least": 8,
            "super_auto_fire": 1,
            "auto_fire": 1,
            "bullet_capacity": 25,
        },
        "note": (
            "Undocumented terminal-rank award applied when the profile's "
            "highest rank equals the final WARBLADE GOD SOL index."
        ),
    },
    "notes": {
        "grouped_best_interpretation": (
            "The locks screen groups the level-100, Time Trial, and Meteor "
            "Storm bests under one tier list; the applier's Time Trial branch "
            "reads the grouped best through getter 0x005465d0. The remake "
            "evaluates the group against the maximum of the three stored "
            "bests."
        ),
        "flag_tier_consumers": (
            "Flag-style tiers apply at their behavior sites: shop exit keeps "
            "autofire, the drop selector skips excluded single/double/triple "
            "entries, coins spawn blue-only, and the Meteor Storm multiplier "
            "gate opens."
        ),
        "easy_profile": (
            "Easy profiles keep their reduced rank cap; ranks above the cap "
            "and their locks stay unreachable on that profile."
        ),
        "fastest_meteor_metric": (
            "The locks-screen thresholds are 2000 and 1000 milliseconds "
            "against a storm lasting far longer, so the measured quantity is "
            "not the full crossing time; its producer is untraced. The "
            "profile field stays unset until that producer is pinned, and "
            "the extra-time-max locks simply never fire from an unset value."
        ),
    },
}


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_sections(data: bytes) -> list[tuple[int, int, int, int]]:
    import struct

    pe_offset = struct.unpack_from("<I", data, 0x3C)[0]
    section_count = struct.unpack_from("<H", data, pe_offset + 6)[0]
    optional_size = struct.unpack_from("<H", data, pe_offset + 20)[0]
    image_base = struct.unpack_from("<I", data, pe_offset + 24 + 28)[0]
    table = pe_offset + 24 + optional_size
    sections = []
    for index in range(section_count):
        entry = table + index * 40
        virtual_size, virtual_address, raw_size, raw_pointer = struct.unpack_from(
            "<IIII", data, entry + 8
        )
        sections.append((image_base + virtual_address, virtual_size, raw_pointer, raw_size))
    return sections


def va_to_offset(sections: list[tuple[int, int, int, int]], va: int) -> int:
    for base, virtual_size, raw_pointer, raw_size in sections:
        if base <= va < base + max(virtual_size, raw_size):
            return raw_pointer + (va - base)
    raise ValueError(f"virtual address 0x{va:08x} is outside every section")


def build_document(exe_path: Path) -> dict:
    data = exe_path.read_bytes()
    exe_hash = sha256_file(exe_path)
    if exe_hash != EXPECTED_EXE_SHA256:
        raise ValueError(
            f"executable hash mismatch: expected {EXPECTED_EXE_SHA256}, found {exe_hash}"
        )
    sections = load_sections(data)
    labels = {}
    for text, va in LABEL_PINS.items():
        offset = va_to_offset(sections, va)
        raw = data[offset : offset + len(text)]
        if raw != text.encode("ascii"):
            raise ValueError(f"lock label drifted at 0x{va:08x}: {raw!r}")
        labels[text] = {"va": f"0x{va:08x}", "file_offset": f"0x{offset:08x}"}
    return {
        "version": 1,
        "schema": "warblade.profile-locks.v1",
        "source": {"executable_sha256": exe_hash},
        "functions": FUNCTIONS,
        "label_pins": labels,
        "contract": CONTRACT,
    }


def render_markdown(document: dict) -> str:
    contract = document["contract"]
    lines = [
        "# Profile locks",
        "",
        "Executable-backed contract for the retail profile lock system: the",
        "start-with awards evaluated when a solo or Time Trial match starts",
        "with an open profile. Extracted from the pinned retail executable",
        f"`{document['source']['executable_sha256']}`.",
        "",
        "| Role | VA |",
        "| --- | --- |",
    ]
    for role, va in document["functions"].items():
        lines.append(f"| {role} | `{va}` |")

    def tier_rows(title: str, tiers: list, key: str = "threshold") -> None:
        lines.extend(["", f"## {title}", "", "| Threshold | Effect | Value |", "| ---: | --- | ---: |"])
        for tier in tiers:
            lines.append(
                f"| {tier[key]} | {tier['effect']} | {tier.get('value', '')} |"
            )

    tier_rows("In-the-game score tiers", contract["score_tiers"])
    tier_rows(
        "Grouped best tiers (level-100 / Time Trial / Meteor Storm)",
        contract["grouped_best_tiers"],
    )
    tier_rows("Games-played tiers", contract["games_played_tiers"])
    tier_rows(
        "Fastest Meteor Storm locks (milliseconds)",
        contract["fastest_meteor_locks"],
        key="threshold_ms",
    )
    lines += [
        "",
        "## Other locks",
        "",
        "- Hit-rate shop unlocks: 70/80/90 percent above level 25 unlock shop",
        "  items 18/19/20 (already implemented and tested).",
        "- Find all secrets (30): full armour, or 2,000 cash when armour is",
        "  already full, plus at least Super Triple Shot.",
        "- Above 200,000,000: the secret counter display starts on.",
        "- Rank 32 (WARBLADE GOD SOL): the undocumented terminal package —",
        "  maximum bonus time, 25,000 cash, raised bullet speed, weapon 8,",
        "  Super Auto Fire, and 25 bullets.",
        "- The 100,000-games package: half-maximum speed steps, 25 bullets,",
        "  half-maximum bonus time, and 5,000 cash.",
        "",
        "## Interpretation notes",
        "",
        f"- {contract['notes']['grouped_best_interpretation']}",
        f"- {contract['notes']['flag_tier_consumers']}",
        f"- {contract['notes']['easy_profile']}",
        "",
        "## Reproduction",
        "",
        "```sh",
        "python3 tools/profile_lock_extract.py",
        "python3 tools/profile_lock_extract.py --check",
        "python3 tools/profile_lock_test.py",
        "```",
        "",
    ]
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--exe", type=Path, default=DEFAULT_EXE)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--document", type=Path, default=DEFAULT_DOCUMENT)
    parser.add_argument("--check", action="store_true")
    arguments = parser.parse_args()

    document = build_document(arguments.exe)
    serialized = json.dumps(document, indent=2) + "\n"
    markdown = render_markdown(document)

    if arguments.check:
        if (
            arguments.output.read_text(encoding="utf-8") != serialized
            or arguments.document.read_text(encoding="utf-8") != markdown
        ):
            print("profile lock evidence is stale", file=sys.stderr)
            return 1
        print(f"profile lock evidence is current: {arguments.output}")
        return 0

    arguments.output.write_text(serialized, encoding="utf-8")
    arguments.document.write_text(markdown, encoding="utf-8")
    print(f"generated profile lock evidence: {arguments.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
