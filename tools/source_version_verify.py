#!/usr/bin/env python3
"""Verify the project and both export presets publish one release version."""

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
