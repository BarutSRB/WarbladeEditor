#!/usr/bin/env python3
"""Interactive Warblade level editor workflow.

This CLI ties together the existing decoder (`parse_warblade_lvd.py`), the JSON
schema validator (`validate_warblade_lvd.py`), and the encoder so edits go
through a deterministic decode → edit → lint → encode pipeline.
"""

from __future__ import annotations

import argparse
import json
import os
import shlex
import subprocess
import sys
from pathlib import Path
from typing import Tuple

import parse_warblade_lvd
import validate_warblade_lvd

DEFAULT_REPORTS_DIR = Path("reports")
DEFAULT_EDITOR = os.environ.get("VISUAL") or os.environ.get("EDITOR") or "vi"


def _derive_json_path(entry: str | None, file_path: Path | None, explicit: Path | None) -> Path:
    if explicit is not None:
        return explicit
    if entry:
        base = Path(entry).with_suffix(".json").name
    elif file_path:
        base = file_path.with_suffix(".json").name
    else:
        raise SystemExit("edit: provide --json when no entry or --file is supplied")
    return DEFAULT_REPORTS_DIR / base


def _decode_descriptor(entry: str | None, file_path: Path | None, pac_path: Path) -> Tuple[dict, str]:
    if file_path is not None:
        blob = file_path.read_bytes()
        label = str(file_path)
    elif entry:
        blob = parse_warblade_lvd.extract_lvd_from_pac(pac_path, entry)
        label = f"{entry} ({pac_path})"
    else:
        raise SystemExit("edit: cannot decode without an entry name or --file path")
    descriptor = parse_warblade_lvd.parse_lvd_bytes(blob)
    return descriptor, label


def _ensure_descriptor_file(
    json_path: Path,
    entry: str | None,
    file_path: Path | None,
    pac_path: Path,
    refresh: bool,
) -> None:
    if json_path.exists() and not refresh:
        print(f"[editor] Reusing existing descriptor at {json_path}")
        return
    if not entry and not file_path:
        raise SystemExit("edit: --refresh requires an entry name or --file source to decode")
    descriptor, label = _decode_descriptor(entry, file_path, pac_path)
    json_path.parent.mkdir(parents=True, exist_ok=True)
    json_path.write_text(json.dumps(descriptor, indent=2))
    print(f"[editor] Decoded {label} -> {json_path}")


def _launch_editor(json_path: Path, command: str | None, skip: bool) -> None:
    if skip:
        print(f"[editor] Skipping editor launch for {json_path}")
        return
    editor_cmd = command or DEFAULT_EDITOR
    argv = shlex.split(editor_cmd)
    if not argv:
        raise SystemExit("edit: editor command resolved to an empty argv")
    argv.append(str(json_path))
    print(f"[editor] Launching {' '.join(argv)}")
    subprocess.run(argv, check=True)


def _lint_descriptor(descriptor: dict, source: Path) -> None:
    findings = validate_warblade_lvd.validate_descriptor(descriptor)
    errors = [msg for level, msg in findings if level == "error"]
    warnings = [msg for level, msg in findings if level == "warning"]
    for msg in warnings:
        print(f"[lint] warning: {msg}")
    if errors:
        for msg in errors:
            print(f"[lint] error: {msg}", file=sys.stderr)
        raise SystemExit(f"[lint] {source} failed validation ({len(errors)} errors)")
    print(f"[lint] {source} passed validation")


def edit_command(args: argparse.Namespace) -> None:
    if args.entry and args.file:
        raise SystemExit("edit: specify either an entry name or --file, not both")

    json_path = _derive_json_path(args.entry, args.file, args.json)
    _ensure_descriptor_file(
        json_path=json_path,
        entry=args.entry,
        file_path=args.file,
        pac_path=args.pac,
        refresh=args.refresh,
    )

    _launch_editor(json_path, args.editor, args.skip_editor)

    try:
        descriptor = json.loads(json_path.read_text())
    except Exception as exc:
        raise SystemExit(f"[editor] unable to load {json_path}: {exc}") from exc

    _lint_descriptor(descriptor, json_path)

    blob = parse_warblade_lvd.encode_lvd(descriptor)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_bytes(blob)
    print(f"[editor] wrote {args.out} ({len(blob)} bytes)")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    edit = subparsers.add_parser(
        "edit",
        help="Decode -> edit -> lint -> encode a Warblade .lvd descriptor",
    )
    edit.add_argument(
        "entry",
        nargs="?",
        help="Tar entry name inside warblade.pac (e.g., classic_level_001.lvd)",
    )
    edit.add_argument(
        "--file",
        type=Path,
        help="Path to a standalone .lvd blob (bypasses the tar archive)",
    )
    edit.add_argument(
        "--pac",
        type=Path,
        default=Path(parse_warblade_lvd.ARCHIVE_NAME),
        help="Path to warblade.pac when using entry names (default: data/warblade.pac)",
    )
    edit.add_argument(
        "--json",
        type=Path,
        help="Working descriptor path (default: reports/<entry>.json)",
    )
    edit.add_argument(
        "--refresh",
        action="store_true",
        help="Force a fresh decode even if the working JSON already exists",
    )
    edit.add_argument(
        "--editor",
        help=f"Editor command (default: $VISUAL/$EDITOR or {DEFAULT_EDITOR!r})",
    )
    edit.add_argument(
        "--skip-editor",
        action="store_true",
        help="Do not open the editor (useful when editing the JSON elsewhere)",
    )
    edit.add_argument(
        "--out",
        type=Path,
        required=True,
        help="Destination .lvd path written after linting succeeds",
    )
    edit.set_defaults(func=edit_command)

    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
