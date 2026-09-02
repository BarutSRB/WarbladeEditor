#!/usr/bin/env python3
"""Unit tests for the source release-version gate."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import source_version_verify as source_versions


PROJECT_TEMPLATE = 'config/version="{version}"\n'
PRESETS_TEMPLATE = """[preset.0.options]
application/short_version="{version}"
application/version="{version}"
[preset.1.options]
application/short_version="{version}"
application/version="{version}"
[preset.2.options]
application/file_version="{windows_version}"
application/product_version="{windows_version}"
"""


class SourceVersionVerifyTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.project = self.root / "project.godot"
        self.presets = self.root / "export_presets.cfg"

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def _write(
        self,
        project_version: str,
        preset_version: str,
        windows_version: str | None = None,
    ) -> None:
        self.project.write_text(
            PROJECT_TEMPLATE.format(version=project_version), encoding="utf-8"
        )
        self.presets.write_text(
            PRESETS_TEMPLATE.format(
                version=preset_version,
                windows_version=(
                    f"{preset_version}.0" if windows_version is None else windows_version
                ),
            ),
            encoding="utf-8",
        )

    def test_accepts_one_matching_project_and_two_matching_exports(self) -> None:
        self._write("0.5.0", "0.5.0")
        source_versions.verify(self.project, self.presets, "0.5.0")

    def test_rejects_a_stale_export_version(self) -> None:
        self._write("0.5.0", "0.4.0")
        with self.assertRaises(source_versions.SourceVersionError):
            source_versions.verify(self.project, self.presets, "0.5.0")

    def test_rejects_missing_second_export_version(self) -> None:
        self.project.write_text(PROJECT_TEMPLATE.format(version="0.5.0"), encoding="utf-8")
        self.presets.write_text(
            '[preset.0.options]\napplication/short_version="0.5.0"\n'
            'application/version="0.5.0"\n'
            '[preset.2.options]\napplication/file_version="0.5.0.0"\n'
            'application/product_version="0.5.0.0"\n',
            encoding="utf-8",
        )
        with self.assertRaises(source_versions.SourceVersionError):
            source_versions.verify(self.project, self.presets, "0.5.0")

    def test_rejects_a_three_part_windows_version(self) -> None:
        self._write("0.5.0", "0.5.0", windows_version="0.5.0")
        with self.assertRaises(source_versions.SourceVersionError):
            source_versions.verify(self.project, self.presets, "0.5.0")

    def test_rejects_a_stale_windows_version(self) -> None:
        self._write("0.5.0", "0.5.0", windows_version="0.4.0.0")
        with self.assertRaises(source_versions.SourceVersionError):
            source_versions.verify(self.project, self.presets, "0.5.0")

    def test_rejects_missing_windows_versions(self) -> None:
        self.project.write_text(PROJECT_TEMPLATE.format(version="0.5.0"), encoding="utf-8")
        self.presets.write_text(
            '[preset.0.options]\napplication/short_version="0.5.0"\n'
            'application/version="0.5.0"\n'
            '[preset.1.options]\napplication/short_version="0.5.0"\n'
            'application/version="0.5.0"\n',
            encoding="utf-8",
        )
        with self.assertRaises(source_versions.SourceVersionError):
            source_versions.verify(self.project, self.presets, "0.5.0")


if __name__ == "__main__":
    unittest.main()
