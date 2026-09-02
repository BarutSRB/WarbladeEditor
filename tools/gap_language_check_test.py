#!/usr/bin/env python3
"""Focused contract tests for gap_language_check.py."""

from __future__ import annotations

import tempfile
import unittest
import json
from pathlib import Path

import gap_language_check


class GapLanguageCheckTest(unittest.TestCase):
    def test_current_repository_passes(self) -> None:
        root = Path(__file__).resolve().parents[1]
        self.assertEqual(gap_language_check.check_repo(root), [])

    def test_missing_matrix_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            failures = gap_language_check.check_repo(Path(temporary))
        self.assertIn("docs/GAP_MATRIX.md is missing", failures)

    def test_pending_mus_wording_fails(self) -> None:
        self.assertTrue(
            gap_language_check.pending_mus_policy(
                "Tracker .mus playback remains unresolved for a later milestone."
            )
        )
        self.assertFalse(
            gap_language_check.pending_mus_policy(
                "Tracker-module .mus playback is a permanent product non-goal."
            )
        )

    def test_superseded_evidence_wording_fails(self) -> None:
        self.assertEqual(
            gap_language_check.stale_evidence_phrases(
                "The exact first-five per-wave attack-path assignment is unresolved."
            ),
            ["exact first-five per-wave attack-path assignment is unresolved"],
        )
        self.assertEqual(
            gap_language_check.stale_evidence_phrases(
                "The executable uses one global compacted SWD catalog."
            ),
            [],
        )

    def test_source_occurrence_trace_fails_closed(self) -> None:
        complete_trace = "\n".join(gap_language_check.SOURCE_TRACE_MARKERS)
        self.assertEqual(
            gap_language_check.missing_source_trace_markers(complete_trace),
            [],
        )
        missing_one = complete_trace.replace("`WEAPON_RUNTIME_TRACE.md`", "")
        self.assertEqual(
            gap_language_check.missing_source_trace_markers(missing_one),
            ["`WEAPON_RUNTIME_TRACE.md`"],
        )

    def test_version_contracts_fail_on_drift(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "src/shared").mkdir(parents=True)
            (root / "src/net").mkdir(parents=True)
            (root / "content").mkdir()
            (root / "docs").mkdir()
            (root / "src/shared/match_contract.gd").write_text(
                "const CONTENT_VERSION: int = 8\n", encoding="utf-8"
            )
            (root / "src/net/protocol_codec.gd").write_text(
                "\n".join(
                    (
                        "const VERSION: int = 3",
                        "const SNAPSHOT_VERSION: int = 9",
                        "const REPLAY_VERSION: int = 9",
                        "const HASH_STATE_VERSION: int = 9",
                    )
                )
                + "\n",
                encoding="utf-8",
            )
            for relative, version, schema, _label in (
                gap_language_check.JSON_VERSION_CONTRACTS
            ):
                (root / relative).write_text(
                    json.dumps({"version": version, "schema": schema}),
                    encoding="utf-8",
                )
            (root / "docs/CONTENT_CONTRACT.md").write_text(
                "\n".join(
                    f"| {label} | {version} |"
                    for label, version in gap_language_check.DOC_VERSION_ROWS
                )
                + "\n",
                encoding="utf-8",
            )
            failures = gap_language_check.check_version_contracts(root)
        expected_content_version = next(
            expected
            for relative, _pattern, expected, label in (
                gap_language_check.SOURCE_VERSION_CONTRACTS
            )
            if relative == "src/shared/match_contract.gd" and label == "match content"
        )
        self.assertTrue(
            any(
                f"match content version {expected_content_version}" in failure
                for failure in failures
            ),
            failures,
        )


if __name__ == "__main__":
    unittest.main()
