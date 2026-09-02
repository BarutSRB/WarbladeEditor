#!/usr/bin/env python3
"""Unit tests for the exported Windows/Linux artifact gate."""

from __future__ import annotations

import os
import struct
import tempfile
import unittest
from pathlib import Path

import export_artifact_verify as artifacts


def pe_header(
    machine: int = artifacts.PE_MACHINE_AMD64,
    characteristics: int = artifacts.PE_CHARACTERISTIC_EXECUTABLE_IMAGE,
    magic: int = artifacts.PE_MAGIC_PE32_PLUS,
    subsystem: int = artifacts.PE_SUBSYSTEM_WINDOWS_GUI,
) -> bytes:
    e_lfanew = 0x80
    head = bytearray(e_lfanew + 24 + 96)
    head[0:2] = b"MZ"
    struct.pack_into("<I", head, 0x3C, e_lfanew)
    head[e_lfanew : e_lfanew + 4] = b"PE\0\0"
    struct.pack_into("<H", head, e_lfanew + 4, machine)
    struct.pack_into("<H", head, e_lfanew + 22, characteristics)
    struct.pack_into("<H", head, e_lfanew + 24, magic)
    struct.pack_into("<H", head, e_lfanew + 24 + 68, subsystem)
    return bytes(head)


def elf_header(
    elf_class: int = artifacts.ELF_CLASS_64,
    data: int = artifacts.ELF_DATA_LITTLE_ENDIAN,
    e_type: int = artifacts.ELF_TYPE_DYN,
    e_machine: int = artifacts.ELF_MACHINE_X86_64,
) -> bytes:
    head = bytearray(64)
    head[0:4] = b"\x7fELF"
    head[4] = elf_class
    head[5] = data
    head[6] = 1
    struct.pack_into("<H", head, 16, e_type)
    struct.pack_into("<H", head, 18, e_machine)
    return bytes(head)


def embedded_pck(
    version: tuple[int, int, int] = (4, 7, 2),
    payload: bytes = b"\0" * 96,
    header_magic: bytes = artifacts.PCK_MAGIC,
) -> bytes:
    return header_magic + struct.pack("<IIII", 2, *version) + payload


def trailer(distance: int, magic: bytes = artifacts.PCK_MAGIC) -> bytes:
    return struct.pack("<Q", distance) + magic


class ExportArtifactVerifyTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def _write(self, name: str, header: bytes, pck: bytes | None = None, tail: bytes | None = None) -> Path:
        pck = embedded_pck() if pck is None else pck
        tail = trailer(len(pck)) if tail is None else tail
        path = self.root / name
        path.write_bytes(header + pck + tail)
        os.chmod(path, 0o755)
        return path

    def _verify(self, path: Path, kind: str, **overrides):
        options = {"min_bytes": 0, "min_pck_bytes": 0, "godot_version": "4.7.2"}
        options.update(overrides)
        return artifacts.verify_artifact(path, kind, **options)

    def test_accepts_a_pe32_plus_x86_64_gui_executable_with_embedded_pck(self) -> None:
        result = self._verify(self._write("Warblade.exe", pe_header()), "windows")
        self.assertEqual("PE32+", result["format"])
        self.assertEqual("4.7.2", result["godot_version"])
        self.assertEqual(len(embedded_pck()), result["pck_bytes"])
        self.assertEqual(len(pe_header()), result["pck_offset"])

    def test_rejects_wrong_pe_machine_magic_and_dll_flag(self) -> None:
        cases = (
            pe_header(machine=0x014C),
            pe_header(magic=0x10B),
            pe_header(characteristics=artifacts.PE_CHARACTERISTIC_EXECUTABLE_IMAGE | artifacts.PE_CHARACTERISTIC_DLL),
            pe_header(subsystem=3),
        )
        for index, header in enumerate(cases):
            with self.assertRaises(artifacts.ArtifactVerificationError, msg=f"case {index}"):
                self._verify(self._write(f"bad{index}.exe", header), "windows")

    def test_accepts_an_elf64_x86_64_executable_with_embedded_pck(self) -> None:
        result = self._verify(self._write("Warblade.x86_64", elf_header()), "linux")
        self.assertEqual("ELF64", result["format"])
        self.assertEqual(artifacts.ELF_TYPE_DYN, result["elf_type"])

    def test_rejects_wrong_elf_class_endianness_and_machine(self) -> None:
        cases = (
            elf_header(elf_class=1),
            elf_header(data=2),
            elf_header(e_machine=183),
            elf_header(e_type=1),
        )
        for index, header in enumerate(cases):
            with self.assertRaises(artifacts.ArtifactVerificationError, msg=f"case {index}"):
                self._verify(self._write(f"bad{index}.x86_64", header), "linux")

    def test_rejects_a_linux_binary_without_execute_permission(self) -> None:
        path = self._write("Warblade.x86_64", elf_header())
        os.chmod(path, 0o644)
        with self.assertRaises(artifacts.ArtifactVerificationError):
            self._verify(path, "linux")

    def test_rejects_missing_or_broken_pck_trailer(self) -> None:
        with self.assertRaises(artifacts.ArtifactVerificationError):
            self._verify(self._write("none.exe", pe_header(), tail=b""), "windows")
        with self.assertRaises(artifacts.ArtifactVerificationError):
            self._verify(self._write("wrong.exe", pe_header(), tail=trailer(len(embedded_pck()) + 8)), "windows")
        with self.assertRaises(artifacts.ArtifactVerificationError):
            self._verify(self._write("nohead.exe", pe_header(), pck=embedded_pck(header_magic=b"XXXX")), "windows")

    def test_rejects_wrong_godot_version_and_small_sizes(self) -> None:
        path = self._write("Warblade.exe", pe_header(), pck=embedded_pck(version=(4, 7, 1)))
        with self.assertRaises(artifacts.ArtifactVerificationError):
            self._verify(path, "windows")
        self._verify(path, "windows", godot_version="4.7.1")
        self._verify(path, "windows", godot_version=None)
        with self.assertRaises(artifacts.ArtifactVerificationError):
            self._verify(path, "windows", godot_version="4.7.1", min_bytes=10_000)
        with self.assertRaises(artifacts.ArtifactVerificationError):
            self._verify(path, "windows", godot_version="4.7.1", min_pck_bytes=10_000)

    def test_expected_utf16_strings(self) -> None:
        payload = b"\0" * 16 + "Warblade Remake".encode("utf-16-le") + b"\0" * 16
        path = self._write("Warblade.exe", pe_header(), pck=embedded_pck(payload=payload))
        result = self._verify(path, "windows", expect_utf16=("Warblade Remake",))
        self.assertEqual(["Warblade Remake"], result["utf16_strings"])
        with self.assertRaises(artifacts.ArtifactVerificationError):
            self._verify(path, "windows", expect_utf16=("0.1.0.0",))

    def test_parser_defaults(self) -> None:
        args = artifacts._parser().parse_args(["linux", "--path", "x"])
        self.assertEqual(artifacts.DEFAULT_MIN_BYTES, args.min_bytes)
        self.assertEqual([], args.expect_utf16)
        args = artifacts._parser().parse_args(
            ["windows", "--path", "x", "--expect-utf16", "a", "--expect-utf16", "b", "--godot-version", "4.7.2"]
        )
        self.assertEqual(["a", "b"], args.expect_utf16)


if __name__ == "__main__":
    unittest.main()
