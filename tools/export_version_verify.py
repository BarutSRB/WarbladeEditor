#!/usr/bin/env python3
"""Fail closed when exported macOS bundles carry the wrong release version."""

from __future__ import annotations

import argparse
import plistlib
import sys
from pathlib import Path


class VersionVerificationError(RuntimeError):
    pass


def verify_bundle(app: Path, expected: str) -> None:
    info_path = app.resolve() / "Contents" / "Info.plist"
    if not info_path.is_file():
        raise VersionVerificationError(f"bundle is missing Info.plist: {app}")
    with info_path.open("rb") as stream:
        info = plistlib.load(stream)
    for key in ("CFBundleShortVersionString", "CFBundleVersion"):
        actual = str(info.get(key, ""))
        if actual != expected:
            raise VersionVerificationError(
                f"{app.name} {key} is {actual!r}; expected {expected!r}"
            )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--expected", required=True)
    parser.add_argument("--app", action="append", required=True, type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not args.expected.strip():
        print("expected version must not be empty", file=sys.stderr)
        return 2
    try:
        for app in args.app:
            verify_bundle(app, args.expected)
    except (OSError, plistlib.InvalidFileException, VersionVerificationError) as error:
        print(f"export version verification failed: {error}", file=sys.stderr)
        return 1
    print(
        f"verified {len(args.app)} exported bundle(s) at version {args.expected}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
