#!/usr/bin/env python3
"""Extract the executable-backed end-of-game GAME BONUSES tally contract.

Sources inside the pinned retail executable:

- ``FUN_005aafa0`` is the game-over sequencer: it records the run's profile
  statistics from the raw score, serializes the per-level record, and seeds
  the per-seat tally blocks (``thunk_FUN_00568f00(seat, player)``) for every
  terminal path, including the pause-menu ``RETIRE FROM  GAME`` command
  (menu built by ``FUN_00549ed0``), which ends the run exactly like losing
  the last fighter.
- ``FUN_00568f00`` seeds each seat's tally: the cash counter from the
  player's money, the perfects counter from the per-player perfect-rounds
  float, the rank counter from the player's rank value, and the hit-rate
  target from ``round(hits * 100 / max(shots, 1))`` clamped to 100.
- ``FUN_005529b0`` animates the reveal and accumulates the values:
  cash contributes money x 100, each rank mark contributes the rank bonus
  table entry for its 1-based index, each perfect contributes 100000, and
  each hit-rate percent contributes 1000; every line also adds into the
  bonus sum.
- ``FUN_00596dd0`` renders the block and prints TOTAL SCORE as
  ``raw score + bonus sum``.
- ``FUN_00596a70`` decides the Duel winner by comparing the seats'
  ``raw score + bonus sum`` totals; equality is a draw.
- The MAX CASH BONUS branch (50,000,000) requires an arming counter the
  seed initializes to -1 and nothing in the retail build ever raises, so
  the branch is unreachable; it is preserved as evidence only.
- ``FUN_007757e0`` initializes the 33-entry rank bonus table at
  ``0x00e11f20``.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import struct
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_EXE = PROJECT_ROOT / "Game" / "warblade.exe"
DEFAULT_OUTPUT = PROJECT_ROOT / "docs" / "evidence" / "game_bonus_tally.json"
DEFAULT_DOCUMENT = PROJECT_ROOT / "docs" / "evidence" / "GAME_BONUS_TALLY.md"

EXPECTED_EXE_SHA256 = "ddf1778c307af1087ff9dcb512786111e665d972298aeaac3f1b4b2996d079ef"

LABEL_STRINGS = {
    "game_bonuses": ("GAME BONUSES", 0x007809BC),
    "cash_left": ("CASH LEFT", 0x0078092C),
    "max_cash_bonus": ("MAX CASH BONUS", 0x007808AC),
    "rank_bonus": ("RANK BONUS", 0x00780838),
    "perfects": ("PERFECTS", 0x0078027C),
    "sum_bonus_points": ("SUM BONUS POINTS", 0x00780148),
    "total_score": ("TOTAL SCORE", 0x00780108),
    "tip": ("A TIP FROM OUTER SPACE", 0x007800D4),
    "retire": ("RETIRE FROM  GAME", 0x0077A2A4),
}

FUNCTIONS = {
    "game_over_sequencer": "0x005aafa0",
    "tally_seed": "0x00568f00",
    "tally_accumulator": "0x005529b0",
    "tally_renderer": "0x00596dd0",
    "duel_winner_banner": "0x00596a70",
    "rank_table_initializer": "0x007757e0",
    "retire_menu_builder": "0x00549ed0",
}

# Rank bonus per mark, 1-based index into the 33-entry table at 0x00e11f20.
# Index 0 belongs to rank 0 (ENSIGN) and is never added because the
# accumulator increments the rank counter before indexing.
RANK_BONUS_TABLE = [
    10000, 20000, 30000, 40000, 50000, 60000, 70000, 80000, 90000, 100000,
    200000, 300000, 400000, 500000, 600000, 700000, 800000, 1000000,
    2000000, 3000000, 4000000, 5000000,
    10000000, 10000000, 10000000, 10000000, 10000000,
    10000000, 10000000, 10000000, 10000000, 10000000,
    50000000,
]

CONTRACT = {
    "cash_left_points_per_money_unit": 100,
    "perfect_points": 100000,
    "hit_percent_points": 1000,
    "hit_percent_formula": "round(hits * 100 / max(shots, 1)) clamped to 100",
    "hit_percent_clamp": 100,
    "rank_bonus_rule": "sum of RANK_BONUS_TABLE[1..rank_index]",
    "total_score_rule": "raw score + sum of bonus lines",
    "duel_winner_rule": "higher raw score + bonus sum wins; equality is a draw",
    "retire_rule": (
        "the pause-menu retire command ends the run through the same "
        "game-over sequencer: raw-score profile statistics, then the tally"
    ),
    "profile_statistics_use_raw_score": True,
    "max_cash_bonus": {
        "value": 50000000,
        "reachable": False,
        "reason": (
            "the arming counter is seeded to -1 and no retail code path "
            "raises it, so the branch never triggers"
        ),
    },
    "tip_rule": "a random tip string is shown under the tally (presentation)",
}

SEED_INSTRUCTION_PINS = [
    {
        "va": "0x00568f90",
        "bytes": "d980a0878400",
        "meaning": "FLD float [player+0x8487a0] - perfect rounds counter",
    },
    {
        "va": "0x00569024",
        "bytes": "db804c878400",
        "meaning": "FILD dword [player+0x84874c] - successful hits",
    },
    {
        "va": "0x00569033",
        "bytes": "dab148878400",
        "meaning": "FIDIV dword [player+0x848748] - shots fired (floored to 1)",
    },
    {
        "va": "0x00569039",
        "bytes": "dc0dd08f7700",
        "meaning": "FMUL double [0x00778fd0] - x100 for the percentage",
    },
]


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_sections(data: bytes) -> list[tuple[int, int, int, int]]:
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
    for key, (text, va) in LABEL_STRINGS.items():
        offset = va_to_offset(sections, va)
        raw = data[offset : offset + len(text)]
        if raw != text.encode("ascii"):
            raise ValueError(f"label {key} bytes drifted at 0x{va:08x}: {raw!r}")
        labels[key] = {"text": text, "va": f"0x{va:08x}", "file_offset": f"0x{offset:08x}"}

    for pin in SEED_INSTRUCTION_PINS:
        offset = va_to_offset(sections, int(pin["va"], 16))
        expected = bytes.fromhex(pin["bytes"])
        raw = data[offset : offset + len(expected)]
        if raw != expected:
            raise ValueError(
                f"seed instruction drifted at {pin['va']}: expected {expected.hex()}, "
                f"found {raw.hex()}"
            )

    # Rank bonus table constants pushed by FUN_007757e0.
    initializer_start = va_to_offset(sections, 0x007757E0)
    initializer_end = va_to_offset(sections, 0x00776200)
    cursor = initializer_start
    for value in RANK_BONUS_TABLE:
        if -128 <= value <= 127:
            needle = b"\x6a" + struct.pack("<b", value)
        else:
            needle = b"\x68" + struct.pack("<i", value)
        found = data.find(needle, cursor, initializer_end)
        if found < 0:
            raise ValueError(
                f"rank bonus push immediate {value} is missing in FUN_007757e0"
            )
        cursor = found + 1

    return {
        "version": 1,
        "schema": "warblade.game-bonus-tally.v1",
        "source": {"executable_sha256": exe_hash},
        "functions": FUNCTIONS,
        "labels": labels,
        "rank_bonus_table": RANK_BONUS_TABLE,
        "contract": CONTRACT,
        "seed_instruction_pins": SEED_INSTRUCTION_PINS,
    }


def render_markdown(document: dict) -> str:
    contract = document["contract"]
    table = document["rank_bonus_table"]
    lines = [
        "# End-of-game GAME BONUSES tally",
        "",
        "Executable-backed contract for the terminal bonus tally, the retire",
        "command, and the Duel winner rule. Extracted from the pinned retail",
        f"executable `{document['source']['executable_sha256']}`.",
        "",
        "## Owning functions",
        "",
        "| Role | VA |",
        "| --- | --- |",
    ]
    for role, va in document["functions"].items():
        lines.append(f"| {role} | `{va}` |")
    lines += [
        "",
        "## Contract",
        "",
        "- CASH LEFT contributes money x "
        f"{contract['cash_left_points_per_money_unit']} points.",
        f"- Each perfect bonus round contributes {contract['perfect_points']}",
        "  points; the perfects counter is the per-player perfect-rounds value.",
        f"- HIT PERCENTAGE is `{contract['hit_percent_formula']}` and",
        f"  contributes {contract['hit_percent_points']} points per percent.",
        "- RANK BONUS is the cumulative sum of the rank bonus table from index",
        "  1 through the player's rank index; the renderer prints the rank",
        "  name from the same 33-entry jumptable.",
        "- SUM BONUS POINTS is the sum of the lines above; TOTAL SCORE is",
        "  `raw score + SUM BONUS POINTS`.",
        "- Profile statistics record the raw score before the tally; the",
        "  hall-of-fame consumer sees the total.",
        f"- Duel: {contract['duel_winner_rule']}.",
        f"- Retire: {contract['retire_rule']}.",
        f"- MAX CASH BONUS ({contract['max_cash_bonus']['value']}) is",
        f"  unreachable: {contract['max_cash_bonus']['reason']}. It is",
        "  preserved as evidence and the remake implements no reachable path",
        "  for it.",
        "",
        "## Rank bonus table (index 1-32 consumed)",
        "",
        "| Index | Points |",
        "| ---: | ---: |",
    ]
    for index, value in enumerate(table):
        lines.append(f"| {index} | {value} |")
    lines += [
        "",
        "## Reproduction",
        "",
        "```sh",
        "python3 tools/game_bonus_tally_extract.py",
        "python3 tools/game_bonus_tally_extract.py --check",
        "python3 tools/game_bonus_tally_test.py",
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
        current = arguments.output.read_text(encoding="utf-8")
        current_markdown = arguments.document.read_text(encoding="utf-8")
        if current != serialized or current_markdown != markdown:
            print("game bonus tally evidence is stale", file=sys.stderr)
            return 1
        print(f"game bonus tally evidence is current: {arguments.output}")
        return 0

    arguments.output.write_text(serialized, encoding="utf-8")
    arguments.document.write_text(markdown, encoding="utf-8")
    print(f"generated game bonus tally evidence: {arguments.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
