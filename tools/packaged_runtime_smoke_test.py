#!/usr/bin/env python3

from __future__ import annotations

import io
import json
import unittest
from unittest import mock

import packaged_runtime_smoke


class PackagedRuntimeSmokeTests(unittest.TestCase):
    def test_parser_accepts_default_and_compatibility_campaign_boundaries(self) -> None:
        default_args = packaged_runtime_smoke._parser().parse_args(
            ["server", "--app", "unused"]
        )
        compatibility_args = packaged_runtime_smoke._parser().parse_args(
            ["client", "--app", "unused", "--end-level", "35"]
        )
        retained_args = packaged_runtime_smoke._parser().parse_args(
            ["server", "--app", "unused", "--end-level", "49"]
        )
        level_fifty_args = packaged_runtime_smoke._parser().parse_args(
            ["client", "--app", "unused", "--end-level", "50"]
        )
        level_sixty_two_args = packaged_runtime_smoke._parser().parse_args(
            ["client", "--app", "unused", "--end-level", "62"]
        )
        maximum_args = packaged_runtime_smoke._parser().parse_args(
            ["server", "--app", "unused", "--end-level", "3999"]
        )
        rejection_args = packaged_runtime_smoke._parser().parse_args(
            ["client-reject", "--app", "unused", "--end-level", "4000"]
        )
        endless_args = packaged_runtime_smoke._parser().parse_args(
            ["server", "--app", "unused", "--end-level", "101"]
        )
        self.assertIsNone(default_args.end_level)
        self.assertEqual(35, compatibility_args.end_level)
        self.assertEqual(49, retained_args.end_level)
        self.assertEqual(50, level_fifty_args.end_level)
        self.assertEqual(62, level_sixty_two_args.end_level)
        self.assertEqual(packaged_runtime_smoke.DEFAULT_END_LEVEL, maximum_args.end_level)
        self.assertEqual(4000, rejection_args.end_level)
        self.assertEqual(101, endless_args.end_level)

        with mock.patch("sys.stderr", new=io.StringIO()):
            with self.assertRaises(SystemExit):
                packaged_runtime_smoke._parser().parse_args(
                    ["server", "--app", "unused", "--end-level", "4000"]
                )

    def test_process_group_cleanup_does_not_signal_an_exited_process(self) -> None:
        process = mock.Mock()
        process.poll.return_value = 0
        with mock.patch.object(packaged_runtime_smoke.os, "killpg") as killpg:
            packaged_runtime_smoke._terminate_process_group(process)
        killpg.assert_not_called()

    def test_server_probe_result_requires_the_complete_network_contract(self) -> None:
        complete = {
            name: True
            for name in packaged_runtime_smoke.SERVER_PROBE_REQUIRED_CHECKS
        }
        self.assertEqual([], packaged_runtime_smoke.missing_server_probe_checks(complete))

        incomplete = complete | {
            "seat_claimed": False,
            "authoritative_input_applied": False,
        }
        self.assertEqual(
            ["seat_claimed", "authoritative_input_applied"],
            packaged_runtime_smoke.missing_server_probe_checks(incomplete),
        )

    def test_probe_json_selection_ignores_unrelated_process_output(self) -> None:
        expected = {
            "schema": packaged_runtime_smoke.SERVER_PROBE_SCHEMA,
            "ok": True,
        }
        output = "\n".join(
            [
                "Godot Engine v4.x",
                json.dumps({"schema": "unrelated", "ok": False}),
                json.dumps(expected),
            ]
        )
        self.assertEqual(
            expected,
            packaged_runtime_smoke._find_json_result(
                output,
                "schema",
                packaged_runtime_smoke.SERVER_PROBE_SCHEMA,
            ),
        )

    def test_probe_json_selection_fails_closed_without_contract_output(self) -> None:
        with self.assertRaises(packaged_runtime_smoke.SmokeFailure):
            packaged_runtime_smoke._find_json_result(
                '{"schema":"unrelated"}',
                "schema",
                packaged_runtime_smoke.SERVER_PROBE_SCHEMA,
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
