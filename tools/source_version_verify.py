#!/usr/bin/env python3
"""Verify the project and every export preset publish one release version.

The macOS presets carry MAJOR.MINOR.PATCH; the Windows preset carries the
four-part MAJOR.MINOR.PATCH.0 file and product versions.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


class SourceVersionError(RuntimeError):
    pass


def _single_project_version(path: Path) -> str:
    matches = re.findall(
        r'^config/version="([^"]+)"$',
        path.read_text(encoding="utf-8"),
        flags=re.MULTILINE,
    )
    if len(matches) != 1:
        raise SourceVersionError(
            f"{path} must contain exactly one application config/version"
        )
    return matches[0]


def _export_versions(path: Path) -> tuple[list[str], list[str]]:
    text = path.read_text(encoding="utf-8")
    short_versions = re.findall(
        r'^application/short_version="([^"]+)"$', text, flags=re.MULTILINE
    )
    bundle_versions = re.findall(
        r'^application/version="([^"]+)"$', text, flags=re.MULTILINE
    )
    if len(short_versions) != 2 or len(bundle_versions) != 2:
        raise SourceVersionError(
            f"{path} must version exactly the client and server export presets"
        )
    return short_versions, bundle_versions


def _windows_versions(path: Path) -> list[str]:
    text = path.read_text(encoding="utf-8")
    file_versions = re.findall(
        r'^application/file_version="([^"]+)"$', text, flags=re.MULTILINE
    )
    product_versions = re.findall(
        r'^application/product_version="([^"]+)"$', text, flags=re.MULTILINE
    )
    if len(file_versions) != 1 or len(product_versions) != 1:
        raise SourceVersionError(
            f"{path} must version exactly one Windows export preset"
        )
    return file_versions + product_versions


def verify(project: Path, presets: Path, expected: str) -> None:
    actual = [_single_project_version(project)]
    short_versions, bundle_versions = _export_versions(presets)
    actual.extend(short_versions)
    actual.extend(bundle_versions)
    mismatches = [version for version in actual if version != expected]
    if mismatches:
        raise SourceVersionError(
            f"source versions {actual!r} do not all match {expected!r}"
        )
    windows_expected = f"{expected}.0"
    windows_versions = _windows_versions(presets)
    windows_mismatches = [
        version for version in windows_versions if version != windows_expected
    ]
    if windows_mismatches:
        raise SourceVersionError(
            f"Windows versions {windows_versions!r} do not all match {windows_expected!r}"
        )


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--expected", required=True)
    parser.add_argument("--project", type=Path, default=root / "project.godot")
    parser.add_argument("--presets", type=Path, default=root / "export_presets.cfg")
    args = parser.parse_args()
    try:
        verify(args.project, args.presets, args.expected)
    except (OSError, SourceVersionError) as error:
        print(f"source version verification failed: {error}", file=sys.stderr)
        return 1
    print(f"verified project and export source versions at {args.expected}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
