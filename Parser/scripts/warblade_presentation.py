#!/usr/bin/env python3

from __future__ import annotations

import argparse
import hashlib
import json
import os
import struct
import tarfile
import tempfile
from pathlib import Path, PurePosixPath
from typing import Any


DEFAULT_GAME_ROOT = Path(__file__).resolve().parents[2] / "Game"
EXPECTED_PAC_SHA256 = "5ee9195f48c22341b058e1f84afb7839b4b03a4ac0f01319714c905e05129bba"
RASTER_SUFFIXES = {".jpg", ".png", ".tga"}
HIT_MASK_SUFFIX = ".hma"
AUDIO_TREE_SUFFIXES = (".mp3", ".ogg")
AUDIO_FORMATS_POLICY = {
    "inventoried": ["mp3", "ogg"],
    "excluded_music_modules": (
        "The 12 data/music/*.mus tracker modules are not inventoried: "
        "tracker-module `.mus` playback is a permanent product non-goal and "
        "the extracted MP3 soundtrack is the final music system."
    ),
}
JPEG_START_OF_FRAME_MARKERS = {
    0xC0,
    0xC1,
    0xC2,
    0xC3,
    0xC5,
    0xC6,
    0xC7,
    0xC9,
    0xCA,
    0xCB,
    0xCD,
    0xCE,
    0xCF,
}


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _normalized_member_name(value: str) -> str:
    if not value or "\x00" in value or "\\" in value:
        raise ValueError(f"invalid PAC member name: {value!r}")
    path = PurePosixPath(value)
    if path.is_absolute() or any(part in ("", ".", "..") for part in path.parts):
        raise ValueError(f"invalid PAC member name: {value!r}")
    return path.as_posix()


def _tga_metadata(data: bytes, label: str) -> dict[str, Any]:
    if len(data) < 18:
        raise ValueError(f"truncated TGA header: {label}")
    (
        id_length,
        color_map_type,
        image_type,
        _color_map_origin,
        color_map_length,
        _color_map_depth,
        _origin_x,
        _origin_y,
        width,
        height,
        pixel_depth,
        descriptor,
    ) = struct.unpack_from("<BBBHHBHHHHBB", data)
    if color_map_type != 0 or color_map_length != 0:
        raise ValueError(f"indexed TGA is unsupported: {label}")
    if image_type not in (2, 10):
        raise ValueError(f"unsupported TGA image type {image_type}: {label}")
    if width <= 0 or height <= 0:
        raise ValueError(f"invalid TGA dimensions {width}x{height}: {label}")
    if pixel_depth not in (24, 32):
        raise ValueError(f"unsupported TGA pixel depth {pixel_depth}: {label}")
    bytes_per_pixel = pixel_depth // 8
    cursor = 18 + id_length
    if cursor > len(data):
        raise ValueError(f"truncated TGA image identifier: {label}")
    pixel_count = width * height
    if image_type == 2:
        required = cursor + pixel_count * bytes_per_pixel
        if required > len(data):
            raise ValueError(f"truncated uncompressed TGA pixels: {label}")
    else:
        decoded_pixels = 0
        while decoded_pixels < pixel_count:
            if cursor >= len(data):
                raise ValueError(f"truncated RLE TGA packet header: {label}")
            packet_header = data[cursor]
            cursor += 1
            packet_pixels = (packet_header & 0x7F) + 1
            if decoded_pixels + packet_pixels > pixel_count:
                raise ValueError(f"RLE TGA packet exceeds image bounds: {label}")
            packet_bytes = bytes_per_pixel if packet_header & 0x80 else packet_pixels * bytes_per_pixel
            if cursor + packet_bytes > len(data):
                raise ValueError(f"truncated RLE TGA packet: {label}")
            cursor += packet_bytes
            decoded_pixels += packet_pixels
    return {
        "format": "tga",
        "width": width,
        "height": height,
        "pixel_depth": pixel_depth,
        "alpha_bits": descriptor & 0x0F,
        "compression": "rle" if image_type == 10 else "none",
        "storage_origin": "top_left" if descriptor & 0x20 else "bottom_left",
    }


def _png_metadata(data: bytes, label: str) -> dict[str, Any]:
    if len(data) < 33 or data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        raise ValueError(f"invalid PNG header: {label}")
    width, height = struct.unpack_from(">II", data, 16)
    if width <= 0 or height <= 0:
        raise ValueError(f"invalid PNG dimensions {width}x{height}: {label}")
    return {
        "format": "png",
        "width": width,
        "height": height,
        "bit_depth": data[24],
        "color_type": data[25],
    }


def _jpeg_metadata(data: bytes, label: str) -> dict[str, Any]:
    if len(data) < 4 or data[:2] != b"\xff\xd8":
        raise ValueError(f"invalid JPEG header: {label}")
    cursor = 2
    while cursor < len(data):
        if data[cursor] != 0xFF:
            cursor += 1
            continue
        while cursor < len(data) and data[cursor] == 0xFF:
            cursor += 1
        if cursor >= len(data):
            break
        marker = data[cursor]
        cursor += 1
        if marker in {0x01, 0xD8, 0xD9} or 0xD0 <= marker <= 0xD7:
            continue
        if cursor + 2 > len(data):
            raise ValueError(f"truncated JPEG segment length: {label}")
        segment_length = struct.unpack_from(">H", data, cursor)[0]
        if segment_length < 2 or cursor + segment_length > len(data):
            raise ValueError(f"invalid JPEG segment length: {label}")
        if marker in JPEG_START_OF_FRAME_MARKERS:
            if segment_length < 8:
                raise ValueError(f"truncated JPEG frame header: {label}")
            height, width = struct.unpack_from(">HH", data, cursor + 3)
            if width <= 0 or height <= 0:
                raise ValueError(f"invalid JPEG dimensions {width}x{height}: {label}")
            return {
                "format": "jpg",
                "width": width,
                "height": height,
                "precision": data[cursor + 2],
                "components": data[cursor + 7],
            }
        cursor += segment_length
    raise ValueError(f"JPEG has no start-of-frame marker: {label}")


def raster_metadata(data: bytes, filename: str) -> dict[str, Any]:
    suffix = PurePosixPath(filename).suffix.lower()
    if suffix == ".tga":
        return _tga_metadata(data, filename)
    if suffix == ".png":
        return _png_metadata(data, filename)
    if suffix == ".jpg":
        return _jpeg_metadata(data, filename)
    raise ValueError(f"unsupported raster format: {filename}")


def validate_hma(data: bytes, label: str, width: int | None = None, height: int | None = None) -> None:
    if not data:
        raise ValueError(f"empty HMA collision mask: {label}")
    invalid = next((value for value in data if value not in (0, 1)), None)
    if invalid is not None:
        raise ValueError(f"HMA contains value {invalid}, expected only 0 or 1: {label}")
    if width is None or height is None:
        return
    expected_size = width * height
    if len(data) != expected_size:
        raise ValueError(
            f"HMA size mismatch for {label}: expected {expected_size}, found {len(data)}"
        )


def _pac_source_id(member: str) -> str:
    return f"warblade.pac:{member}"


def _external_source_id(relative_path: str) -> str:
    return f"external:{relative_path}"


def _inventory_audio_directory(game_root: Path, directory: str) -> dict[str, dict[str, Any]]:
    root = game_root / "data" / directory
    if not root.is_dir():
        raise FileNotFoundError(f"audio directory is missing: {root}")
    records: dict[str, dict[str, Any]] = {}
    for path in sorted(root.iterdir(), key=lambda item: item.name.encode("utf-8")):
        if path.suffix.lower() != ".mp3":
            continue
        if path.is_symlink() or not path.is_file():
            raise ValueError(f"audio source must be a regular non-symlink file: {path}")
        data = path.read_bytes()
        if not data:
            raise ValueError(f"audio source is empty: {path}")
        relative_path = path.relative_to(game_root).as_posix()
        records[path.name] = {
            "source_id": _external_source_id(relative_path),
            "source_kind": "external_file",
            "source_path": relative_path,
            "format": "mp3",
            "byte_size": len(data),
            "sha256": sha256_bytes(data),
        }
    return records


def _inventory_audio_tree(game_root: Path, directory: str) -> dict[str, dict[str, Any]]:
    root = game_root / "data" / directory
    if not root.is_dir():
        raise FileNotFoundError(f"audio directory is missing: {root}")
    records: dict[str, dict[str, Any]] = {}
    paths = sorted(
        root.rglob("*"),
        key=lambda item: item.relative_to(root).as_posix().encode("utf-8"),
    )
    for path in paths:
        suffix = path.suffix.lower()
        if suffix not in AUDIO_TREE_SUFFIXES:
            continue
        if path.is_symlink() or not path.is_file():
            raise ValueError(f"audio source must be a regular non-symlink file: {path}")
        data = path.read_bytes()
        if not data:
            raise ValueError(f"audio source is empty: {path}")
        relative_path = path.relative_to(game_root).as_posix()
        key = path.relative_to(root).as_posix()
        records[key] = {
            "source_id": _external_source_id(relative_path),
            "source_kind": "external_file",
            "source_path": relative_path,
            "format": suffix.removeprefix("."),
            "byte_size": len(data),
            "sha256": sha256_bytes(data),
        }
    return records


def build_inventory(
    game_root: Path = DEFAULT_GAME_ROOT,
    expected_pac_sha256: str | None = EXPECTED_PAC_SHA256,
) -> dict[str, Any]:
    game_root = game_root.resolve()
    pac_path = game_root / "data" / "warblade.pac"
    if pac_path.is_symlink() or not pac_path.is_file():
        raise FileNotFoundError(f"PAC source is missing or invalid: {pac_path}")
    pac_sha256 = sha256_file(pac_path)
    if expected_pac_sha256 is not None and pac_sha256 != expected_pac_sha256:
        raise ValueError(
            f"PAC SHA-256 mismatch: expected {expected_pac_sha256}, found {pac_sha256}"
        )

    raster_data: dict[str, bytes] = {}
    mask_data: dict[str, bytes] = {}
    with tarfile.open(pac_path, mode="r:*") as archive:
        seen: set[str] = set()
        for member in archive.getmembers():
            name = _normalized_member_name(member.name)
            if name in seen:
                raise ValueError(f"duplicate PAC member: {name}")
            seen.add(name)
            suffix = PurePosixPath(name).suffix.lower()
            if suffix not in RASTER_SUFFIXES and suffix != HIT_MASK_SUFFIX:
                continue
            if not member.isfile():
                raise ValueError(f"presentation PAC member is not a regular file: {name}")
            stream = archive.extractfile(member)
            if stream is None:
                raise ValueError(f"presentation PAC member cannot be read: {name}")
            data = stream.read()
            if len(data) != member.size:
                raise ValueError(f"truncated PAC member: {name}")
            if suffix == HIT_MASK_SUFFIX:
                mask_data[name] = data
            else:
                raster_data[name] = data

    rasters: dict[str, dict[str, Any]] = {}
    for name in sorted(raster_data, key=lambda value: value.encode("utf-8")):
        data = raster_data[name]
        rasters[name] = {
            "source_id": _pac_source_id(name),
            "source_kind": "warblade.pac",
            "source_member": name,
            "byte_size": len(data),
            "sha256": sha256_bytes(data),
            **raster_metadata(data, name),
        }

    hit_masks: dict[str, dict[str, Any]] = {}
    for name in sorted(mask_data, key=lambda value: value.encode("utf-8")):
        data = mask_data[name]
        source_path = PurePosixPath(name)
        peer_name = None
        peer = None
        for suffix in (".tga", ".png", ".jpg"):
            candidate = source_path.with_suffix(suffix).as_posix()
            if candidate in rasters:
                peer_name = candidate
                peer = rasters[candidate]
                break
        width = peer["width"] if peer is not None else None
        height = peer["height"] if peer is not None else None
        validate_hma(data, name, width, height)
        hit_masks[name] = {
            "source_id": _pac_source_id(name),
            "source_kind": "warblade.pac",
            "source_member": name,
            "format": "hma",
            "byte_size": len(data),
            "sha256": sha256_bytes(data),
            "width": width,
            "height": height,
            "paired_raster": peer_name,
            "orientation": "top_left_row_major",
            "value_domain": [0, 1],
        }

    music = _inventory_audio_directory(game_root, "music")
    sfx = _inventory_audio_directory(game_root, "samples")
    voices = _inventory_audio_tree(game_root, "samples/voices")
    return {
        "version": 1,
        "schema": "warblade.presentation.inventory.v1",
        "source": {
            "game_root": game_root.as_posix(),
            "pac": {
                "path": "data/warblade.pac",
                "byte_size": pac_path.stat().st_size,
                "sha256": pac_sha256,
            },
        },
        "counts": {
            "rasters": len(rasters),
            "hit_masks": len(hit_masks),
            "music": len(music),
            "sfx": len(sfx),
            "voices": len(voices),
        },
        "audio_formats": AUDIO_FORMATS_POLICY,
        "rasters": rasters,
        "hit_masks": hit_masks,
        "music": music,
        "sfx": sfx,
        "voices": voices,
    }


def source_record_index(inventory: dict[str, Any]) -> dict[str, dict[str, Any]]:
    records: dict[str, dict[str, Any]] = {}
    for section_name in ("rasters", "hit_masks", "music", "sfx", "voices"):
        for record in inventory[section_name].values():
            source_id = record["source_id"]
            if source_id in records:
                raise ValueError(f"duplicate presentation source ID: {source_id}")
            records[source_id] = record
    return records


def validate_source_hashes(inventory: dict[str, Any], expected: dict[str, str]) -> None:
    records = source_record_index(inventory)
    for source_id, expected_sha256 in sorted(expected.items()):
        record = records.get(source_id)
        if record is None:
            raise ValueError(f"presentation source is not inventoried: {source_id}")
        if record["sha256"] != expected_sha256:
            raise ValueError(
                f"presentation source SHA-256 mismatch for {source_id}: "
                f"expected {expected_sha256}, found {record['sha256']}"
            )


def _atomic_write(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary_name, path)
    except BaseException:
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass
        raise


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Inventory and validate Warblade presentation sources."
    )
    parser.add_argument("--game-root", type=Path, default=DEFAULT_GAME_ROOT)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--no-pinned-pac-hash", action="store_true")
    return parser.parse_args()


def main() -> None:
    arguments = parse_arguments()
    inventory = build_inventory(
        arguments.game_root,
        None if arguments.no_pinned_pac_hash else EXPECTED_PAC_SHA256,
    )
    serialized = (json.dumps(inventory, indent=2, sort_keys=True) + "\n").encode("utf-8")
    if arguments.output is None:
        print(serialized.decode("utf-8"), end="")
    else:
        _atomic_write(arguments.output.resolve(), serialized)


if __name__ == "__main__":
    main()
