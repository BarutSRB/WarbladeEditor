#!/usr/bin/env python3
"""Fail closed when closed product gaps drift back into milestone language."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


MATRIX_IDS = {
    *(f"G{index:02d}" for index in range(1, 21)),
    *(f"P{index:02d}" for index in range(1, 12)),
    *(f"E{index:02d}" for index in range(1, 17)),
    *(f"M{index:02d}" for index in range(1, 12)),
    *(f"N{index:02d}" for index in range(1, 5)),
    *(f"I{index:02d}" for index in range(1, 4)),
}
HIGH_LEVEL_DOCS = (
    "README.md",
    "docs/ARCHITECTURE.md",
    "docs/CONTENT_CONTRACT.md",
    "docs/evidence/README.md",
)
STALE_HEADINGS = (
    "still unresolved",
    "remaining confidence boundary",
    "still provisional",
    "future milestone",
    "later milestone",
)
STALE_EVIDENCE_PHRASES = (
    "an indirect executable-side mapping remains unresolved",
    "integer multipliers in difficulties.json are provisional",
    "special encodings, not direct horizontal velocities. they are retained here",
    "exact first-five per-wave attack-path assignment is unresolved",
    "legacy compatibility waves remain an explicitly provisional scaffold",
    "selected milestone inventory",
    "milestone semantics",
    "time trial is deferred",
    '"milestone_binding"',
)
SOURCE_TRACE_MARKERS = (
    "`README.md`",
    "`ARCHITECTURE.md`",
    "`CONTENT_CONTRACT.md`",
    "`DIFFICULTY_RULES.md`",
    "`ENEMY_BEHAVIOR_STATIC_TRACE.md`",
    "`FIRST_FIVE_FIDELITY_TRACE.md`",
    "`LVD_CLASSIC_LEVELS.md`",
    "`LVD_FIRST_FIVE.md`",
    "`LVD_STATIC_TRACE.md`",
    "`PRESENTATION_ASSETS.md`",
    "`docs/evidence/README.md`",
    "`SPRITE_ATLAS.md`",
    "`SWD_ATTACK_BEHAVIOR.md`",
    "`WEAPON_RUNTIME_TRACE.md`",
    "`classic_levels.json`",
    "`provenance_manifest.json`",
    "`BIG_BOSS_STATE_13.md`",
    "`BONUS_MODES.md`",
    "`ORDNANCE_RUNTIME_TRACE.md`",
    "`PRESENTATION_RUNTIME_STATIC_TRACE.md`",
)
SOURCE_VERSION_CONTRACTS = (
    (
        "src/shared/match_contract.gd",
        r"^const CONTENT_VERSION: int = (\d+)$",
        12,
        "match content",
    ),
    (
        "src/net/protocol_codec.gd",
        r"^const VERSION: int = (\d+)$",
        8,
        "transport protocol",
    ),
    (
        "src/net/protocol_codec.gd",
        r"^const SNAPSHOT_VERSION: int = (\d+)$",
        12,
        "snapshot",
    ),
    (
        "src/net/protocol_codec.gd",
        r"^const REPLAY_VERSION: int = (\d+)$",
        12,
        "replay",
    ),
    (
        "src/net/protocol_codec.gd",
        r"^const HASH_STATE_VERSION: int = (\d+)$",
        12,
        "hash state",
    ),
    (
        "src/sim/game_simulation.gd",
        r"^const SHOP_SAVE_VERSION: int = (\d+)$",
        1,
        "saved game",
    ),
)
JSON_VERSION_CONTRACTS = (
    ("content/levels.json", 10, "warblade.levels.v10", "levels"),
    (
        "content/sprite_frames.json",
        11,
        "warblade.sprite-frames.v11",
        "sprite frames",
    ),
    (
        "content/time_trial.json",
        1,
        "warblade.time-trial.v1",
        "time trial",
    ),
    (
        "content/talents.json",
        1,
        "warblade.talents.v1",
        "talents",
    ),
    (
        "content/presentation.json",
        2,
        "warblade.presentation.v2",
        "presentation",
    ),
)
DOC_VERSION_ROWS = (
    ("Transport protocol", 8),
    ("Match content", 12),
    ("Levels", 10),
    ("Sprite frames", 11),
    ("Time Trial", 1),
    ("Talents", 1),
    ("Snapshot", 12),
    ("Replay", 12),
    ("Hash state", 12),
    ("Saved game", 1),
    ("Presentation", 2),
)


def check_version_contracts(root: Path) -> list[str]:
    failures: list[str] = []
    for relative, pattern, expected, label in SOURCE_VERSION_CONTRACTS:
        path = root / relative
        try:
            text = path.read_text(encoding="utf-8")
        except OSError as error:
            failures.append(f"cannot read {relative} for {label} version: {error}")
            continue
        matches = re.findall(pattern, text, re.MULTILINE)
        if matches != [str(expected)]:
            failures.append(
                f"{relative} must publish {label} version {expected}; found {matches}"
            )

    for relative, expected_version, expected_schema, label in JSON_VERSION_CONTRACTS:
        path = root / relative
        try:
            document = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            failures.append(f"cannot read {relative} for {label} version: {error}")
            continue
        if (
            int(document.get("version", -1)) != expected_version
            or str(document.get("schema", "")) != expected_schema
        ):
            failures.append(
                f"{relative} must publish {label} v{expected_version} "
                f"schema {expected_schema}"
            )

    contract_path = root / "docs/CONTENT_CONTRACT.md"
    try:
        contract = contract_path.read_text(encoding="utf-8")
    except OSError as error:
        failures.append(f"cannot read docs/CONTENT_CONTRACT.md versions: {error}")
    else:
        for label, expected in DOC_VERSION_ROWS:
            if not re.search(
                rf"^\| {re.escape(label)} \| {expected} \|$",
                contract,
                re.MULTILINE,
            ):
                failures.append(
                    f"docs/CONTENT_CONTRACT.md must publish {label} version {expected}"
                )
    return failures


def pending_mus_policy(line: str) -> bool:
    lowered = line.lower()
    return ".mus" in lowered and any(
        token in lowered
        for token in ("unfinished", "unresolved", "deferred", "future", "later")
    )


def stale_evidence_phrases(text: str) -> list[str]:
    lowered = text.lower()
    return [phrase for phrase in STALE_EVIDENCE_PHRASES if phrase in lowered]


def missing_source_trace_markers(matrix: str) -> list[str]:
    return [marker for marker in SOURCE_TRACE_MARKERS if marker not in matrix]


def check_repo(root: Path) -> list[str]:
    failures: list[str] = []
    matrix_path = root / "docs/GAP_MATRIX.md"
    if not matrix_path.is_file():
        return ["docs/GAP_MATRIX.md is missing"]
    matrix = matrix_path.read_text(encoding="utf-8")
    found_ids = set(re.findall(r"^\| ([GPEMNI]\d{2}) \|", matrix, re.MULTILINE))
    missing = sorted(MATRIX_IDS - found_ids)
    extras = sorted(found_ids - MATRIX_IDS)
    if missing:
        failures.append("gap matrix is missing IDs: " + ", ".join(missing))
    if extras:
        failures.append("gap matrix has unexpected IDs: " + ", ".join(extras))

    required_matrix_phrases = (
        "tracker-module `.mus` playback is a permanent product non-goal",
        "the extracted mp3 soundtrack is the final music system",
        "simultaneous duel is retail behavior",
        "simultaneous co-op is an intentional modernization",
        "trusted online hosting",
        "cross-platform delivery",
        "time trial",
        # The secret-ship family rows must not silently disappear: G19 is
        # closed and G20 is the remaining open gameplay row.
        "hurry-up secret ships",
        "money-sucker and guard secret ships",
    )
    matrix_lower = matrix.lower()
    for phrase in required_matrix_phrases:
        if phrase not in matrix_lower:
            failures.append(f"gap matrix is missing required policy text: {phrase}")
    if "five actual gap/confidence sections" in matrix_lower:
        failures.append("gap matrix retains the superseded five-section inventory claim")
    for marker in missing_source_trace_markers(matrix):
        failures.append(
            f"gap matrix source-occurrence trace is missing baseline source: {marker}"
        )

    for relative in HIGH_LEVEL_DOCS:
        path = root / relative
        if not path.is_file():
            failures.append(f"{relative} is missing")
            continue
        text = path.read_text(encoding="utf-8")
        lowered = text.lower()
        for heading in STALE_HEADINGS:
            if heading in lowered:
                failures.append(f"{relative} retains stale heading/phrase: {heading}")
        for policy_term in (
            "gap_matrix.md",
            ".mus",
            "mp3",
            "permanent product non-goal",
            "evidence-only",
            "modernization",
            "trusted",
            "cross-platform",
            "time trial",
        ):
            if policy_term not in lowered:
                failures.append(
                    f"{relative} is missing closure policy term: {policy_term}"
                )
        if "duel" not in lowered or "simultaneous co-op" not in lowered:
            failures.append(
                f"{relative} must distinguish retail Duel from simultaneous co-op"
            )

    all_markdown = [root / "README.md", *(root / "docs").rglob("*.md")]
    for path in all_markdown:
        for line_number, line in enumerate(
            path.read_text(encoding="utf-8").splitlines(), start=1
        ):
            if pending_mus_policy(line):
                failures.append(
                    f"{path.relative_to(root)}:{line_number} treats .mus as pending work"
                )

    evidence_sources = [
        *all_markdown,
        root / "tools/known_facts.json",
        root / "docs/evidence/provenance_manifest.json",
        root / "content/presentation.json",
        root / "tools/lvd_decoder.py",
        *(root / "content/lvd_decoded").glob("*.json"),
    ]
    for path in evidence_sources:
        try:
            text = path.read_text(encoding="utf-8")
        except OSError as error:
            failures.append(f"cannot inspect stale evidence language in {path}: {error}")
            continue
        for phrase in stale_evidence_phrases(text):
            failures.append(
                f"{path.relative_to(root)} retains superseded evidence phrase: {phrase}"
            )

    failures.extend(check_version_contracts(root))
    return failures


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--versions-only",
        action="store_true",
        help="check only source, generated catalog, and documented contract versions",
    )
    args = parser.parse_args()
    failures = check_version_contracts(root) if args.versions_only else check_repo(root)
    if failures:
        for failure in failures:
            print(f"GAP LANGUAGE CHECK FAILED: {failure}", file=sys.stderr)
        return 1
    print(
        "CONTRACT VERSION CHECK PASSED"
        if args.versions_only
        else "GAP LANGUAGE CHECK PASSED"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
