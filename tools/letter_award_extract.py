#!/usr/bin/env python3
"""Extract the executable-backed E-X-T-R-A / A-R-T-X-E letter-award contract.

Sources (all inside the pinned retail executable):

- The bonus dispatcher ``FUN_00571c60`` owns letter cases 0-4 (E, X, T, R, A).
  Each case awards the 100-point letter score only when the letter's session
  flag is already set (a duplicate collect), then unconditionally sets the
  flag and updates two single-character chain registers:
  the forward register (player struct +0x7cc) tracks E->X->T->R->A and the
  reverse register (+0x7cd) tracks A->R->T->X->E.  A chain register only
  advances when it currently holds the exact predecessor; anything else
  clears it to a space.  Completing the forward chain on A prints
  ``*** E X T R A ***`` and completing the reverse chain on E prints
  ``*** A R T X E ***``.
- The completion award fills fighters and armour to their caps; when both are
  already full the SUPER variant awards the super score with a floating score
  text instead.
- After every letter collect, when all five session flags are set the
  all-collected award grants one fighter (plus ten bonus-time units), or one
  armour when fighters are capped, or the all-collected score when both are
  capped.  The five flags are not cleared by the award.
- The score table initializer ``FUN_00775150`` stores every award value
  multiplied by the 64-bit score scale.
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
DEFAULT_OUTPUT = PROJECT_ROOT / "docs" / "evidence" / "letter_awards.json"
DEFAULT_DOCUMENT = PROJECT_ROOT / "docs" / "evidence" / "LETTER_AWARDS.md"

EXPECTED_EXE_SHA256 = "ddf1778c307af1087ff9dcb512786111e665d972298aeaac3f1b4b2996d079ef"

BANNER_STRINGS = {
    "super_extra": ("*** S U P E R   E X T R A ***", 0x0077DB0C),
    "extra": ("*** E X T R A ***", 0x0077DB30),
    "super_artxe": ("*** S U P E R   A R T X E ***", 0x0077DB50),
    "artxe": ("*** A R T X E ***", 0x0077DB74),
}

# Code references from the dispatcher to the banner strings (Ghidra xrefs).
BANNER_CODE_REFERENCES = {
    "artxe": 0x0057209D,
    "super_artxe": 0x005720F7,
    "extra": 0x00574327,
    "super_extra": 0x00574554,
}

DISPATCHER_VA = 0x00571C60

CONTRACT = {
    "letter_collect_score": 100,
    "letter_collect_score_on_duplicate_only": True,
    "sequence_super_score": 5000000,
    "all_collected_score": 1000000,
    "all_collected_bonus_time_grant": 10,
    "score_multiplier_applies": True,
    "banner_milliseconds": 3000,
    "armour_banner_milliseconds": 1000,
    "forward_sequence": ["E", "X", "T", "R", "A"],
    "reverse_sequence": ["A", "R", "T", "X", "E"],
    "flags_cleared_by_completion": False,
    "voice_slot_extra": 0x14,
    "voice_slot_artxe": 0x15,
}

# Score-table initializer FUN_00775150 pushes these immediates for the
# letter-relevant entries (value, target slot).
SCORE_TABLE_PINS = [
    {"value": 100, "slot": "0x00e11e08", "role": "letter_collect_score"},
    {"value": 5000000, "slot": "0x00e11e28", "role": "sequence_super_score"},
    {"value": 1000000, "slot": "0x00e11da8", "role": "all_collected_score"},
]

EVIDENCE_ONLY = {
    "bonus_time_grant_global": {
        "address": "0x007d0b0c",
        "note": (
            "Initialized to 20 and matching the difficulty contract's "
            "bonus_time_start; the fighter branch of the all-collected award "
            "adds 10. The remake grants the ten units through its clamped "
            "bonus-time path."
        ),
    },
    "armour_branch_side_global": {
        "address": "0x007d1be0",
        "note": (
            "Initialized to 10; the armour branch adds 5. Its runtime meaning "
            "is unproven, so the remake mirrors no gameplay effect and keeps "
            "the observation as lossless evidence."
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

    banners = {}
    for key, (text, va) in BANNER_STRINGS.items():
        offset = va_to_offset(sections, va)
        raw = data[offset : offset + len(text)]
        if raw != text.encode("ascii"):
            raise ValueError(f"banner {key} bytes drifted at 0x{va:08x}: {raw!r}")
        banners[key] = {
            "text": text,
            "va": f"0x{va:08x}",
            "file_offset": f"0x{offset:08x}",
            "dispatcher_reference_va": f"0x{BANNER_CODE_REFERENCES[key]:08x}",
        }

    initializer_start = va_to_offset(sections, 0x00775150)
    initializer_end = va_to_offset(sections, 0x00775800)
    score_pins = []
    for pin in SCORE_TABLE_PINS:
        if -128 <= pin["value"] <= 127:
            needle = b"\x6a" + struct.pack("<b", pin["value"])
        else:
            needle = b"\x68" + struct.pack("<i", pin["value"])
        found = data.find(needle, initializer_start, initializer_end)
        if found < 0:
            raise ValueError(
                f"score-table push immediate {pin['value']} is missing in FUN_00775150"
            )
        score_pins.append({**pin, "push_file_offset": f"0x{found:08x}"})

    return {
        "version": 1,
        "schema": "warblade.letter-awards.v1",
        "source": {"executable_sha256": exe_hash},
        "dispatcher_va": f"0x{DISPATCHER_VA:08x}",
        "banners": banners,
        "contract": CONTRACT,
        "score_table_pins": score_pins,
        "chain_registers": {
            "forward_offset_in_player_struct": "0x7cc",
            "reverse_offset_in_player_struct": "0x7cd",
            "advance_rule": (
                "a register advances to the collected letter only when it holds "
                "that letter's exact predecessor in its sequence; E seeds the "
                "forward register and A seeds the reverse register "
                "unconditionally; every other mismatch clears to a space"
            ),
        },
        "evidence_only": EVIDENCE_ONLY,
    }


def render_markdown(document: dict) -> str:
    contract = document["contract"]
    lines = [
        "# Letter awards (E-X-T-R-A / A-R-T-X-E)",
        "",
        "Executable-backed contract for the retail letter pickups, the strict",
        "consecutive forward and reverse sequence awards, and the all-collected",
        "award. Extracted from the pinned retail executable "
        f"`{document['source']['executable_sha256']}`.",
        "",
        f"Dispatcher: `{document['dispatcher_va']}` (bonus cases 0-4 are the",
        "letters E, X, T, R, A).",
        "",
        "## Banners",
        "",
        "| Award | Banner | String VA | Dispatcher reference |",
        "| --- | --- | --- | --- |",
    ]
    for key in ("extra", "super_extra", "artxe", "super_artxe"):
        banner = document["banners"][key]
        lines.append(
            f"| {key} | `{banner['text']}` | `{banner['va']}` "
            f"| `{banner['dispatcher_reference_va']}` |"
        )
    lines += [
        "",
        "## Contract",
        "",
        f"- A letter collect awards {contract['letter_collect_score']} points",
        "  (score multiplier applies) only when the letter's flag is already",
        "  set — a duplicate collect. A fresh collect scores nothing; it just",
        "  sets the flag. Both paths update the two chain registers and run the",
        "  completion checks.",
        "- Two single-character chain registers per player (struct offsets",
        "  `0x7cc` forward, `0x7cd` reverse) advance only when they hold the",
        "  collected letter's exact predecessor: forward "
        f"{'-'.join(contract['forward_sequence'])}, reverse "
        f"{'-'.join(contract['reverse_sequence'])}. E seeds the forward register",
        "  and A seeds the reverse register unconditionally; any other mismatch",
        "  clears the register.",
        "- Completing a chain fills fighters and armour to their caps and shows",
        "  the banner for 3000 ms; when both are already capped the SUPER",
        f"  variant instead awards {contract['sequence_super_score']} points",
        "  (multiplied) with a floating score text. The forward and reverse",
        "  completions use distinct retail voice slots "
        f"(0x{contract['voice_slot_extra']:02x} / 0x{contract['voice_slot_artxe']:02x}).",
        "- After every collect, when all five flags are set: one fighter is",
        "  granted (plus ten bonus-time units through the clamped bonus-time",
        "  path), or one armour when fighters are capped (ARMOUR banner,",
        f"  1000 ms), or {contract['all_collected_score']} points (multiplied)",
        "  when both are capped. The five flags are not cleared by the award,",
        "  so later letters re-trigger it.",
        "",
        "## Evidence-only observations",
        "",
        f"- `{document['evidence_only']['bonus_time_grant_global']['address']}`: "
        + document["evidence_only"]["bonus_time_grant_global"]["note"],
        f"- `{document['evidence_only']['armour_branch_side_global']['address']}`: "
        + document["evidence_only"]["armour_branch_side_global"]["note"],
        "",
        "## Reproduction",
        "",
        "```sh",
        "python3 tools/letter_award_extract.py",
        "python3 tools/letter_award_extract.py --check",
        "python3 tools/letter_award_test.py",
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
            print("letter award evidence is stale", file=sys.stderr)
            return 1
        print(f"letter award evidence is current: {arguments.output}")
        return 0

    arguments.output.write_text(serialized, encoding="utf-8")
    arguments.document.write_text(markdown, encoding="utf-8")
    print(f"generated letter award evidence: {arguments.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
