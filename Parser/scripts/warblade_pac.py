#!/usr/bin/env python3
"""
Helper for manipulating Warblade's data/warblade.pac archive.

The game treats the PAC file as a straight POSIX tar. This script lets you:
  * list entries
  * extract all contents into a directory
  * replace a single entry (e.g., an edited .lvd) and rebuild the tar

Usage examples:
  ./scripts/warblade_pac.py list
  ./scripts/warblade_pac.py extract --out Warblade/data_extracted
  ./scripts/warblade_pac.py update classic_level_001.lvd --replacement ./tmp/level1.lvd
"""

from __future__ import annotations

import argparse
import io
import os
import shutil
import tarfile
from pathlib import Path

PAC_DEFAULT = Path("Warblade/data/warblade.pac")


def list_entries(pac: Path) -> None:
    with tarfile.open(pac, "r") as tar:
        for member in tar.getmembers():
            kind = "d" if member.isdir() else "f"
            size = member.size
            print(f"{member.name}\t{kind}\t{size}")


def extract_all(pac: Path, out_dir: Path) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    with tarfile.open(pac, "r") as tar:
        tar.extractall(out_dir)
    print(f"[pac] extracted {pac} -> {out_dir}")


def update_entry(pac: Path, name: str, replacement: Path, backup: bool) -> None:
    replacement_bytes = replacement.read_bytes()
    tmp_path = pac.with_suffix(pac.suffix + ".tmp")

    with tarfile.open(pac, "r") as src, tarfile.open(tmp_path, "w") as dst:
        members = src.getmembers()
        seen = False

        for member in members:
            data = None
            if member.isfile():
                data = src.extractfile(member).read()  # type: ignore[arg-type]

            if member.name == name:
                seen = True
                data = replacement_bytes
                member.size = len(data)
                member.mtime = int(os.path.getmtime(replacement))

            if member.isdir():
                dst.addfile(member)
            else:
                assert data is not None
                dst.addfile(member, io.BytesIO(data))

    if not seen:
        if tmp_path.exists():
            tmp_path.unlink()
        raise SystemExit(f"[pac] entry '{name}' not found in {pac}")

    if backup:
        backup_path = pac.with_suffix(pac.suffix + ".bak")
        shutil.move(pac, backup_path)
        shutil.move(tmp_path, pac)
        print(f"[pac] replaced '{name}', backup at {backup_path}")
    else:
        pac.unlink()
        shutil.move(tmp_path, pac)
        print(f"[pac] replaced '{name}' in {pac}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--pac",
        type=Path,
        default=PAC_DEFAULT,
        help=f"Path to warblade.pac (default: {PAC_DEFAULT})",
    )

    sub = parser.add_subparsers(dest="cmd", required=True)

    sub.add_parser("list", help="List entries")

    extract_parser = sub.add_parser("extract", help="Extract all entries")
    extract_parser.add_argument("--out", type=Path, required=True)

    update_parser = sub.add_parser("update", help="Replace a single entry")
    update_parser.add_argument("name", help="Entry inside the PAC (e.g., classic_level_001.lvd)")
    update_parser.add_argument(
        "--replacement",
        type=Path,
        required=True,
        help="Path to the file that should replace the PAC entry",
    )
    update_parser.add_argument(
        "--backup",
        action="store_true",
        help="Keep a .bak copy of the original PAC",
    )

    args = parser.parse_args()

    if args.cmd == "list":
        list_entries(args.pac)
    elif args.cmd == "extract":
        extract_all(args.pac, args.out)
    elif args.cmd == "update":
        update_entry(args.pac, args.name, args.replacement, args.backup)
    else:
        parser.error("unrecognized command")


if __name__ == "__main__":
    main()
