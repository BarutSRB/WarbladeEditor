#!/usr/bin/env python3
"""Fail closed when an exported Windows or Linux binary is not a release-ready build.

Checks the executable header for the expected platform and architecture, the
embedded Godot PCK trailer that a single-file export must end with, a minimum
size, and optionally UTF-16LE strings such as the Windows VERSIONINFO values.
"""

from __future__ import annotations

import argparse
import json
import mmap
import os
import struct
import sys
from pathlib import Path
from typing import Any

PCK_MAGIC = b"GDPC"
HEADER_PREFIX_BYTES = 4096
PE_MACHINE_AMD64 = 0x8664
PE_MAGIC_PE32_PLUS = 0x20B
PE_SUBSYSTEM_WINDOWS_GUI = 2
PE_CHARACTERISTIC_EXECUTABLE_IMAGE = 0x0002
PE_CHARACTERISTIC_DLL = 0x2000
ELF_CLASS_64 = 2
ELF_DATA_LITTLE_ENDIAN = 1
ELF_TYPE_EXEC = 2
ELF_TYPE_DYN = 3
ELF_MACHINE_X86_64 = 62
DEFAULT_MIN_BYTES = 100_000_000
DEFAULT_MIN_PCK_BYTES = 50_000_000
KINDS = ("windows", "linux")


class ArtifactVerificationError(RuntimeError):
    pass


def _u16(data: Any, offset: int) -> int:
    return struct.unpack_from("<H", data, offset)[0]


def _u32(data: Any, offset: int) -> int:
    return struct.unpack_from("<I", data, offset)[0]


def _u64(data: Any, offset: int) -> int:
    return struct.unpack_from("<Q", data, offset)[0]


def verify_windows_header(head: bytes) -> dict[str, Any]:
    """Require a PE32+ x86_64 GUI executable (not a DLL, not the console wrapper)."""
    if head[:2] != b"MZ":
        raise ArtifactVerificationError("missing MZ header")
    if len(head) < 0x40:
        raise ArtifactVerificationError("DOS header is truncated")
    e_lfanew = _u32(head, 0x3C)
    if e_lfanew + 24 + 70 > len(head):
        raise ArtifactVerificationError(f"PE header at 0x{e_lfanew:x} is beyond the inspected prefix")
    if head[e_lfanew : e_lfanew + 4] != b"PE\0\0":
        raise ArtifactVerificationError("missing PE signature")
    machine = _u16(head, e_lfanew + 4)
    if machine != PE_MACHINE_AMD64:
        raise ArtifactVerificationError(f"PE machine 0x{machine:04x} is not x86_64 (0x8664)")
    characteristics = _u16(head, e_lfanew + 22)
    if not characteristics & PE_CHARACTERISTIC_EXECUTABLE_IMAGE:
        raise ArtifactVerificationError("PE image is not marked executable")
    if characteristics & PE_CHARACTERISTIC_DLL:
        raise ArtifactVerificationError("PE image is a DLL")
    magic = _u16(head, e_lfanew + 24)
    if magic != PE_MAGIC_PE32_PLUS:
        raise ArtifactVerificationError(f"optional header magic 0x{magic:03x} is not PE32+ (0x20b)")
    subsystem = _u16(head, e_lfanew + 24 + 68)
    if subsystem != PE_SUBSYSTEM_WINDOWS_GUI:
        raise ArtifactVerificationError(f"PE subsystem {subsystem} is not the Windows GUI subsystem (2)")
    return {"format": "PE32+", "machine": "x86_64", "subsystem": "windows_gui"}


def verify_linux_header(head: bytes) -> dict[str, Any]:
    """Require a little-endian ELF64 x86-64 executable (EXEC or PIE)."""
    if head[:4] != b"\x7fELF":
        raise ArtifactVerificationError("missing ELF magic")
    if len(head) < 20:
        raise ArtifactVerificationError("ELF header is truncated")
    if head[4] != ELF_CLASS_64:
        raise ArtifactVerificationError(f"ELF class {head[4]} is not 64-bit")
    if head[5] != ELF_DATA_LITTLE_ENDIAN:
        raise ArtifactVerificationError(f"ELF data encoding {head[5]} is not little-endian")
    e_type = _u16(head, 16)
    if e_type not in (ELF_TYPE_EXEC, ELF_TYPE_DYN):
        raise ArtifactVerificationError(f"ELF type {e_type} is not an executable")
    e_machine = _u16(head, 18)
    if e_machine != ELF_MACHINE_X86_64:
        raise ArtifactVerificationError(f"ELF machine {e_machine} is not x86-64 (62)")
    return {"format": "ELF64", "machine": "x86_64", "elf_type": e_type}


def parse_godot_version(value: str) -> tuple[int, int, int]:
    parts = value.split(".")
    if len(parts) != 3 or not all(part.isdigit() for part in parts):
        raise ArtifactVerificationError(f"godot version {value!r} is not MAJOR.MINOR.PATCH")
    return int(parts[0]), int(parts[1]), int(parts[2])


def verify_embedded_pck(
    data: Any,
    size: int,
    min_pck_bytes: int,
    godot_version: str | None,
) -> dict[str, Any]:
    """Walk the embedded-PCK trailer back to the PCK header the runtime opens.

    Godot's embedded layout ends with a u64 distance followed by the ASCII
    magic GDPC; the runtime seeks size-12, reads the distance, and expects the
    PCK header (magic, pack format, Godot major/minor/patch) at size-12-distance.
    """
    if size < 12 + 20:
        raise ArtifactVerificationError("file is too small to hold an embedded PCK")
    if bytes(data[size - 4 : size]) != PCK_MAGIC:
        raise ArtifactVerificationError(
            "no embedded PCK trailer; the export did not embed the PCK (binary_format/embed_pck)"
        )
    distance = _u64(data, size - 12)
    pck_start = size - 12 - distance
    if distance <= 0 or pck_start < 0 or pck_start + 20 > size - 12:
        raise ArtifactVerificationError(f"embedded PCK trailer distance {distance} is out of range")
    if bytes(data[pck_start : pck_start + 4]) != PCK_MAGIC:
        raise ArtifactVerificationError("embedded PCK trailer does not point at a PCK header")
    pack_format = _u32(data, pck_start + 4)
    version = (_u32(data, pck_start + 8), _u32(data, pck_start + 12), _u32(data, pck_start + 16))
    if godot_version is not None and version != parse_godot_version(godot_version):
        raise ArtifactVerificationError(
            f"embedded PCK was written by Godot {'.'.join(map(str, version))}; expected {godot_version}"
        )
    if distance < min_pck_bytes:
        raise ArtifactVerificationError(
            f"embedded PCK holds {distance} bytes; expected at least {min_pck_bytes}"
        )
    return {
        "pck_offset": pck_start,
        "pck_bytes": distance,
        "pack_format": pack_format,
        "godot_version": ".".join(map(str, version)),
    }


def verify_artifact(
    path: Path,
    kind: str,
    min_bytes: int = DEFAULT_MIN_BYTES,
    min_pck_bytes: int = DEFAULT_MIN_PCK_BYTES,
    godot_version: str | None = None,
    expect_utf16: tuple[str, ...] = (),
) -> dict[str, Any]:
    if kind not in KINDS:
        raise ArtifactVerificationError(f"unknown artifact kind {kind!r}")
    if not path.is_file():
        raise ArtifactVerificationError(f"artifact does not exist: {path}")
    size = path.stat().st_size
    if size < min_bytes:
        raise ArtifactVerificationError(f"{path.name} is {size} bytes; expected at least {min_bytes}")
    if kind == "linux" and not os.access(path, os.X_OK):
        raise ArtifactVerificationError(f"{path.name} is not executable")
    result: dict[str, Any] = {"kind": kind, "path": str(path), "bytes": size}
    with path.open("rb") as stream:
        head = stream.read(HEADER_PREFIX_BYTES)
        result.update(verify_windows_header(head) if kind == "windows" else verify_linux_header(head))
        with mmap.mmap(stream.fileno(), 0, access=mmap.ACCESS_READ) as view:
            result.update(verify_embedded_pck(view, size, min_pck_bytes, godot_version))
            missing = [text for text in expect_utf16 if view.find(text.encode("utf-16-le")) < 0]
    if missing:
        raise ArtifactVerificationError(
            "missing UTF-16 strings (application/modify_resources not applied?): " + ", ".join(missing)
        )
    result["utf16_strings"] = list(expect_utf16)
    return result


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("kind", choices=KINDS)
    parser.add_argument("--path", required=True, type=Path)
    parser.add_argument("--min-bytes", type=int, default=DEFAULT_MIN_BYTES)
    parser.add_argument("--min-pck-bytes", type=int, default=DEFAULT_MIN_PCK_BYTES)
    parser.add_argument("--godot-version", help="MAJOR.MINOR.PATCH the embedded PCK must declare")
    parser.add_argument(
        "--expect-utf16",
        action="append",
        default=[],
        help="UTF-16LE string that must occur in the file (repeatable)",
    )
    return parser


def main() -> int:
    args = _parser().parse_args()
    try:
        result = verify_artifact(
            args.path,
            args.kind,
            args.min_bytes,
            args.min_pck_bytes,
            args.godot_version,
            tuple(args.expect_utf16),
        )
    except (OSError, ArtifactVerificationError) as error:
        print(f"export artifact verification failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
