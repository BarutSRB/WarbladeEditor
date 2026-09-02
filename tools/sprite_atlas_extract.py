#!/usr/bin/env python3

from __future__ import annotations

import argparse
import hashlib
import json
import struct
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import lvd_decoder


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_EXE = PROJECT_ROOT / "Game" / "warblade.exe"
DEFAULT_ASSET_ROOT = PROJECT_ROOT / "assets" / "original" / "textures"
DEFAULT_LEVEL_ROOT = PROJECT_ROOT / "assets" / "original" / "levels"
KNOWN_FACTS_PATH = PROJECT_ROOT / "tools" / "known_facts.json"

PROJECTILE_TABLE_VAS = {
    "source_x": 0x007CD110,
    "source_y": 0x007CD228,
    "width": 0x007CD340,
    "height": 0x007CD458,
    "next_prototype_id": 0x007CDC00,
    "persistent": 0x007CDE30,
}
DIRECTION_RANGE_TABLE_VA = 0x007D01E0
MIRROR_INDEX_TABLE_VA = 0x007D0228
ENEMY_SOURCE_Y_TABLE_VA = 0x007D0268
ENEMY_SOURCE_X_TABLE_VA = 0x007D02C0
STATE_TEN_SOURCE_SELECTION_VA = 0x0060E5E9
STATE_TEN_SOURCE_SELECTION_SIZE = 114
STATE_TEN_SOURCE_SELECTION_SHA256 = (
    "2f84aa1f998b3af3688dc383fc80de79bfc1687bd3ffef7fa04fbd41abdca260"
)
STATE_TEN_PHASE_UPDATE_VA = 0x0060E65B
STATE_TEN_PHASE_UPDATE_SIZE = 464
STATE_TEN_PHASE_UPDATE_SHA256 = (
    "a31a962b37f247fe76840345231e70d1f41d19251e2a625af0693bebb0327701"
)
SUPPORTED_LEVEL_IDS = tuple(range(1, 101))
ENEMY_SHEET_IDS = (
    "alien001",
    "alien_2",
    "alien_3",
    "alien000",
    "alien_lilla",
    "alien003",
    "alien003_3",
    "alien_big1_1",
    "alien_big1_2",
    "alien_big1_3",
    "alien_big1_4",
    "alien_big1_5",
    "alien_big1_6",
    "alien_rakett",
    "alien_rakett_gronn",
    "alien_baller",
    "alien_baller2",
    "alien_green_lilla_t",
    "alien_cyan_lilla_t",
    "alien_raudkule",
    "alien_raudkule2",
    "alien_blavinger_gf",
    "alien_blavinger_gf2",
    "alien_rbille",
    "alien_big2_1",
    "alien_big2_2",
    "alien_big2_3",
    "alien_big2_4",
    "alien_big2_5",
    "alien_big2_6",
    "alien_gultop",
    "alien_lillatop",
    "alien_bluekreps",
    "alien_lbluekreps",
    "alien_brownkreps",
    "alien_brownkreps2",
    "alien_gulkreps",
    "alien_rvinggk",
    "alien_gvingbk",
    "alien_lila_royr",
    "alien_lblaa_royr",
    "alien_lilla_makk",
    "alien_lblaa_makk",
    "alien_rocktalien",
    "alien_rocktalieng",
    *tuple(f"alien_big3_{index}" for index in range(1, 7)),
    "alien_gspis",
    "alien_rspis",
    "alien001_gul",
    "alien001_raud",
    "alien001_blue",
    "alien002",
    "alien_lysper2",
    "alien_lysper",
    "alien_n1_bla",
    "alien_n1_gron",
    "alien_n1_lilla",
    "alien_n2_bla",
    "alien_n2_red",
    "alien_n2_green",
    "alien_metaballs",
    "alien_metaball2",
    "alien_metaball3",
    "alien_kuler",
    "alien_kuleg",
    "alien_kuleb",
    "alien_kuleo",
    "alien_kulel",
    "alien_mkuler",
    *tuple(f"alien_big4_{index}" for index in range(1, 7)),
)
TIME_TRIAL_LEVEL_IDS = tuple(range(1, 16))
# Retail Time Trial ships its own authored levels (timetrial_%02d.lvd) and pulls
# eighteen enemy sheets the classic campaign never binds. The order below is the
# first-appearance order across timetrial_01 through timetrial_15, resource slot
# order within each level, so the catalog stays deterministic.
TIME_TRIAL_ENEMY_SHEET_IDS = (
    "alien_timetrial_1",
    "alien_timetrial_3k",
    "alien_timetrial_2",
    "alien3",
    "alien_timetrial_3",
    "alien_timetrial_3b",
    "alien_timetrial_3c",
    "alien_10_green",
    "alien_10",
    "alien_10_lilla",
    "alien_12",
    "alien_12_blue",
    "alien_12_red",
    "alien_11",
    "alien_11_gul",
    "alien_13",
    "alien_13_orange",
    "alien002_cyan",
)
ALL_ENEMY_SHEET_IDS = ENEMY_SHEET_IDS + TIME_TRIAL_ENEMY_SHEET_IDS
# Sheet IDs are the case-folded LVD resource stems; the extracted asset files
# keep the original archive capitalization, so the divergent stems are pinned.
ENEMY_SHEET_ASSET_STEMS = {
    "alien_10": "Alien_10",
    "alien_10_green": "Alien_10_green",
    "alien_10_lilla": "Alien_10_lilla",
    "alien_11": "Alien_11",
    "alien_11_gul": "Alien_11_gul",
    "alien_12": "Alien_12",
    "alien_12_blue": "Alien_12_blue",
    "alien_12_red": "Alien_12_red",
    "alien_13": "Alien_13",
    "alien_13_orange": "Alien_13_orange",
}
# The type-6 supplemental projectile cells are blank on the sheets that only the
# Time Trial set binds; no Time Trial level carries a supplemental spawn record,
# so those rectangles are exactly empty rather than missing.
EXACT_EMPTY_PROJECTILE_PHASES = {
    "ordinary_type_7": frozenset({("alien_mkuler", 0), ("alien_mkuler", 1)}),
    "supplemental_state_6_type_6": frozenset(
        {
            ("alien_raudkule2", 1),
            *(
                (sheet_id, phase)
                for sheet_id in (
                    "alien_10",
                    "alien_10_lilla",
                    "alien_11",
                    "alien_11_gul",
                    "alien_12",
                    "alien_12_blue",
                    "alien_12_red",
                    "alien_13",
                    "alien_13_orange",
                )
                for phase in (0, 1)
            ),
            ("alien_10_green", 0),
        }
    ),
}
RAW_RESOURCE_SHEET_IDS = {
    "ALIEN001.bmp": "alien001",
    "ALIEN_2.bmp": "alien_2",
    "ALIEN_3.bmp": "alien_3",
    "ALIEN000.bmp": "alien000",
    "ALIEN_Lilla.bmp": "alien_lilla",
    "ALIEN003.bmp": "alien003",
    "ALIEN003_3.bmp": "alien003_3",
    **{
        f"ALIEN_BIG1_{index}.bmp": f"alien_big1_{index}"
        for index in range(1, 7)
    },
    "ALIEN_rakett.bmp": "alien_rakett",
    "ALIEN_rakett_gronn.bmp": "alien_rakett_gronn",
    "ALIEN_baller.bmp": "alien_baller",
    "ALIEN_baller2.bmp": "alien_baller2",
    "ALIEN_Green_lilla_t.bmp": "alien_green_lilla_t",
    "ALIEN_Cyan_lilla_t.bmp": "alien_cyan_lilla_t",
    "ALIEN_RaudKule.bmp": "alien_raudkule",
    "ALIEN_RaudKule2.bmp": "alien_raudkule2",
    "ALIEN_Blavinger_gf.bmp": "alien_blavinger_gf",
    "ALIEN_Blavinger_gf2.bmp": "alien_blavinger_gf2",
    "ALIEN_RBille.bmp": "alien_rbille",
    **{
        f"ALIEN_big2_{index}.bmp": f"alien_big2_{index}"
        for index in range(1, 7)
    },
    "ALIEN_gultop.bmp": "alien_gultop",
    "ALIEN_lillatop.bmp": "alien_lillatop",
    "ALIEN_bluekreps.bmp": "alien_bluekreps",
    "ALIEN_lbluekreps.bmp": "alien_lbluekreps",
    "ALIEN_brownkreps.bmp": "alien_brownkreps",
    "ALIEN_brownkreps2.bmp": "alien_brownkreps2",
    "ALIEN_gulkreps.bmp": "alien_gulkreps",
    "ALIEN_Rvinggk.bmp": "alien_rvinggk",
    "ALIEN_Gvingbk.bmp": "alien_gvingbk",
}
EXPECTED_SUPPLEMENTAL_RECORDS = {
    3: [{"record_index": 0, "raw_words": [1, 1, 12, 1200, 25]}],
    7: [{"record_index": 0, "raw_words": [1, 1, 15, 861, 13]}],
    11: [{"record_index": 0, "raw_words": [1, 1, 23, 600, 11]}],
    15: [{"record_index": 0, "raw_words": [2, 1, 20, 904, 16]}],
    19: [{"record_index": 0, "raw_words": [2, 1, 50, 968, 23]}],
    23: [{"record_index": 0, "raw_words": [2, 1, 60, 1312, 29]}],
    28: [{"record_index": 0, "raw_words": [2, 1, 30, 560, 7]}],
    32: [{"record_index": 0, "raw_words": [3, 1, 40, 1076, 30]}],
    36: [
        {"record_index": 0, "raw_words": [2, 2, 40, 818, 10]},
        {"record_index": 1, "raw_words": [1, 1, 59, 968, 14]},
    ],
    40: [{"record_index": 0, "raw_words": [4, 1, 40, 818, 10]}],
    44: [{"record_index": 0, "raw_words": [4, 2, 79, 968, 19]}],
    48: [{"record_index": 0, "raw_words": [4, 1, 50, 1054, 13]}],
    53: [
        {"record_index": 0, "raw_words": [2, 1, 59, 925, 8]},
        {"record_index": 1, "raw_words": [2, 1, 79, 1054, 22]},
    ],
    57: [{"record_index": 0, "raw_words": [4, 3, 98, 1441, 7]}],
    61: [{"record_index": 0, "raw_words": [4, 1, 88, 1162, 23]}],
    65: [
        {"record_index": 0, "raw_words": [2, 1, 110, 1484, 14]},
        {"record_index": 1, "raw_words": [2, 2, 110, 1570, 14]},
    ],
    69: [{"record_index": 0, "raw_words": [4, 1, 108, 1119, 17]}],
    73: [{"record_index": 0, "raw_words": [5, 1, 110, 1291, 10]}],
    78: [{"record_index": 0, "raw_words": [4, 1, 98, 1742, 26]}],
    82: [{"record_index": 0, "raw_words": [5, 1, 300, 1600, 5]}],
    86: [{"record_index": 0, "raw_words": [4, 1, 72, 710, 18]}],
    90: [{"record_index": 0, "raw_words": [3, 2, 118, 1398, 25]}],
    94: [{"record_index": 0, "raw_words": [4, 1, 118, 968, 23]}],
    98: [{"record_index": 0, "raw_words": [10, 3, 150, 2000, 10]}],
}
EXPECTED_NONZERO_RECORDS = {
    **EXPECTED_SUPPLEMENTAL_RECORDS,
    25: [{"record_index": 0, "raw_words": [1, 1, 300, 904, 10]}],
    50: [{"record_index": 0, "raw_words": [1, 1, 500, 1377, 8]}],
    75: [{"record_index": 0, "raw_words": [1, 1, 613, 904, 10]}],
    100: [{"record_index": 0, "raw_words": [1, 1, 500, 904, 10]}],
}


class SpriteAtlasError(ValueError):
    pass


@dataclass(frozen=True)
class PESection:
    name: str
    virtual_address: int
    virtual_size: int
    raw_offset: int
    raw_size: int


class PEImage:
    def __init__(self, data: bytes):
        self.data = data
        if len(data) < 0x40 or data[:2] != b"MZ":
            raise SpriteAtlasError("input is not a DOS/PE executable")
        pe_offset = struct.unpack_from("<I", data, 0x3C)[0]
        if pe_offset + 24 > len(data) or data[pe_offset : pe_offset + 4] != b"PE\0\0":
            raise SpriteAtlasError("missing PE signature")
        coff_offset = pe_offset + 4
        section_count = struct.unpack_from("<H", data, coff_offset + 2)[0]
        optional_size = struct.unpack_from("<H", data, coff_offset + 16)[0]
        optional_offset = coff_offset + 20
        if optional_offset + optional_size > len(data):
            raise SpriteAtlasError("truncated PE optional header")
        magic = struct.unpack_from("<H", data, optional_offset)[0]
        if magic != 0x10B:
            raise SpriteAtlasError(f"expected PE32 optional header, found 0x{magic:04x}")
        self.image_base = struct.unpack_from("<I", data, optional_offset + 28)[0]
        section_offset = optional_offset + optional_size
        self.sections: list[PESection] = []
        for index in range(section_count):
            offset = section_offset + index * 40
            if offset + 40 > len(data):
                raise SpriteAtlasError("truncated PE section table")
            raw_name = data[offset : offset + 8].split(b"\0", 1)[0]
            self.sections.append(
                PESection(
                    name=raw_name.decode("ascii", errors="replace"),
                    virtual_size=struct.unpack_from("<I", data, offset + 8)[0],
                    virtual_address=struct.unpack_from("<I", data, offset + 12)[0],
                    raw_size=struct.unpack_from("<I", data, offset + 16)[0],
                    raw_offset=struct.unpack_from("<I", data, offset + 20)[0],
                )
            )

    def va_to_offset(self, virtual_address: int, size: int = 1) -> int:
        rva = virtual_address - self.image_base
        if rva < 0:
            raise SpriteAtlasError(
                f"virtual address 0x{virtual_address:08x} precedes image base"
            )
        for section in self.sections:
            extent = max(section.virtual_size, section.raw_size)
            if section.virtual_address <= rva < section.virtual_address + extent:
                delta = rva - section.virtual_address
                if delta + size > section.raw_size:
                    raise SpriteAtlasError(
                        f"virtual address 0x{virtual_address:08x} is not file-backed"
                    )
                offset = section.raw_offset + delta
                if offset + size > len(self.data):
                    raise SpriteAtlasError(
                        f"virtual address 0x{virtual_address:08x} exceeds input"
                    )
                return offset
        raise SpriteAtlasError(f"unmapped virtual address 0x{virtual_address:08x}")

    def read_i32_table(self, virtual_address: int, count: int) -> list[int]:
        offset = self.va_to_offset(virtual_address, count * 4)
        return list(struct.unpack_from(f"<{count}i", self.data, offset))

    def read_u32_table(self, virtual_address: int, count: int) -> list[int]:
        offset = self.va_to_offset(virtual_address, count * 4)
        return list(struct.unpack_from(f"<{count}I", self.data, offset))


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _verified_instruction_region(
    image: PEImage,
    virtual_address: int,
    size: int,
    expected_sha256: str,
) -> dict[str, Any]:
    offset = image.va_to_offset(virtual_address, size)
    digest = _sha256(image.data[offset : offset + size])
    if digest != expected_sha256:
        raise SpriteAtlasError(
            f"instruction region 0x{virtual_address:08x} SHA-256 drift: "
            f"expected {expected_sha256}, found {digest}"
        )
    return {
        "virtual_address": f"0x{virtual_address:08x}",
        "size": size,
        "sha256": digest,
    }


def _load_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise SpriteAtlasError(f"{path} must contain a JSON object")
    return value


def _rect(x: int, y: int, width: int, height: int) -> dict[str, int]:
    return {"x": x, "y": y, "width": width, "height": height}


def _mask_rect(rect: dict[str, int]) -> dict[str, int]:
    return dict(rect)


def _res_path(path: Path) -> str:
    try:
        relative = path.resolve().relative_to(PROJECT_ROOT.resolve())
    except ValueError as error:
        raise SpriteAtlasError(f"{path} is outside project root {PROJECT_ROOT}") from error
    return f"res://{relative.as_posix()}"


def _decode_tga(path: Path) -> tuple[int, int, list[int]]:
    data = path.read_bytes()
    if len(data) < 18:
        raise SpriteAtlasError(f"{path}: truncated TGA header")
    (
        id_length,
        color_map_type,
        image_type,
        _color_map_origin,
        color_map_length,
        color_map_depth,
        _x_origin,
        _y_origin,
        width,
        height,
        pixel_depth,
        descriptor,
    ) = struct.unpack_from("<BBBHHBHHHHBB", data, 0)
    if color_map_type not in (0, 1):
        raise SpriteAtlasError(f"{path}: unsupported TGA color-map type")
    if image_type not in (2, 10):
        raise SpriteAtlasError(f"{path}: unsupported TGA image type {image_type}")
    if pixel_depth not in (24, 32):
        raise SpriteAtlasError(f"{path}: unsupported TGA pixel depth {pixel_depth}")
    bytes_per_pixel = pixel_depth // 8
    color_map_bytes = 0
    if color_map_type:
        color_map_bytes = color_map_length * ((color_map_depth + 7) // 8)
    offset = 18 + id_length + color_map_bytes
    pixel_count = width * height
    file_order: list[bytes] = []
    if image_type == 2:
        end = offset + pixel_count * bytes_per_pixel
        if end > len(data):
            raise SpriteAtlasError(f"{path}: truncated uncompressed TGA pixels")
        for cursor in range(offset, end, bytes_per_pixel):
            file_order.append(data[cursor : cursor + bytes_per_pixel])
    else:
        cursor = offset
        while len(file_order) < pixel_count:
            if cursor >= len(data):
                raise SpriteAtlasError(f"{path}: truncated RLE packet header")
            packet = data[cursor]
            cursor += 1
            count = (packet & 0x7F) + 1
            if packet & 0x80:
                end = cursor + bytes_per_pixel
                if end > len(data):
                    raise SpriteAtlasError(f"{path}: truncated RLE pixel")
                pixel = data[cursor:end]
                cursor = end
                file_order.extend([pixel] * count)
            else:
                end = cursor + count * bytes_per_pixel
                if end > len(data):
                    raise SpriteAtlasError(f"{path}: truncated raw TGA packet")
                for packet_cursor in range(cursor, end, bytes_per_pixel):
                    file_order.append(
                        data[packet_cursor : packet_cursor + bytes_per_pixel]
                    )
                cursor = end
        if len(file_order) != pixel_count:
            raise SpriteAtlasError(f"{path}: RLE packet exceeds image dimensions")
    alpha = [0] * pixel_count
    top_origin = bool(descriptor & 0x20)
    right_origin = bool(descriptor & 0x10)
    for index, pixel in enumerate(file_order):
        file_y, file_x = divmod(index, width)
        logical_x = width - 1 - file_x if right_origin else file_x
        logical_y = file_y if top_origin else height - 1 - file_y
        alpha[logical_y * width + logical_x] = pixel[3] if bytes_per_pixel == 4 else 255
    return width, height, alpha


def _mask_asset(asset_id: str, tga_path: Path, hma_path: Path) -> dict[str, Any]:
    width, height, alpha = _decode_tga(tga_path)
    tga = tga_path.read_bytes()
    hma = hma_path.read_bytes()
    expected_size = width * height
    if len(hma) != expected_size:
        raise SpriteAtlasError(
            f"{hma_path}: {len(hma)} bytes, expected {expected_size}"
        )
    values = sorted(set(hma))
    if values != [0, 1]:
        raise SpriteAtlasError(f"{hma_path}: expected both binary values 0 and 1")
    alpha_solid = [value != 0 for value in alpha]
    direct_matches = 0
    flipped_matches = 0
    for y in range(height):
        row = y * width
        flipped_row = (height - 1 - y) * width
        for x in range(width):
            occupied = hma[row + x] != 0
            direct_matches += occupied == alpha_solid[row + x]
            flipped_matches += occupied == alpha_solid[flipped_row + x]
    return {
        "id": asset_id,
        "texture": _res_path(tga_path),
        "hit_mask": _res_path(hma_path),
        "texture_sha256": _sha256(tga),
        "hit_mask_sha256": _sha256(hma),
        "width": width,
        "height": height,
        "hit_mask_byte_count": len(hma),
        "hit_mask_unique_values": values,
        "occupied_pixel_count": sum(hma),
        "alpha_alignment": {
            "comparison": "HMA occupancy byte != 0 versus decoded TGA alpha != 0",
            "same_top_left_orientation_match_ppm": (
                direct_matches * 1_000_000 + expected_size // 2
            )
            // expected_size,
            "vertical_flip_match_ppm": (
                flipped_matches * 1_000_000 + expected_size // 2
            )
            // expected_size,
            "interpretation": (
                "The same top-left orientation is strongly supported. Pixel "
                "differences are intentional hit-mask shaping; TGA alpha is not "
                "the collision authority."
            ),
        },
        "confidence": "proven",
    }


def _projectile_membership(facts: dict[str, Any]) -> dict[int, set[int]]:
    definitions = facts.get("weapons", {}).get("definitions", [])
    membership: dict[int, set[int]] = {}
    for definition in definitions:
        weapon_id = int(definition["id"])
        for field in ("flattened_prototype_ids", "captive_flattened_prototype_ids"):
            for prototype_id in definition.get(field, []):
                membership.setdefault(int(prototype_id), set()).add(weapon_id)
    if not membership:
        raise SpriteAtlasError("known_facts.json has no playable projectile graph")
    return membership


def _projectile_frames(
    image: PEImage, facts: dict[str, Any], sheet_width: int, sheet_height: int
) -> tuple[list[dict[str, Any]], list[list[int]]]:
    weapon_membership = _projectile_membership(facts)
    table_count = max(weapon_membership) + 1
    tables = {
        name: image.read_i32_table(virtual_address, table_count)
        for name, virtual_address in PROJECTILE_TABLE_VAS.items()
    }
    # The renderer and collision code consume the mutable prototype index, not
    # only the graph's spawn roots. Close every graph over the executable's
    # next-frame table and propagate its owning playable weapon IDs.
    queue = list(weapon_membership)
    while queue:
        prototype_id = queue.pop(0)
        next_id = tables["next_prototype_id"][prototype_id]
        if next_id < 0:
            continue
        if next_id >= table_count:
            raise SpriteAtlasError(
                f"projectile prototype {prototype_id} points outside the extracted table"
            )
        inherited = weapon_membership[prototype_id]
        if next_id not in weapon_membership:
            weapon_membership[next_id] = set(inherited)
            queue.append(next_id)
        else:
            before = len(weapon_membership[next_id])
            weapon_membership[next_id].update(inherited)
            if len(weapon_membership[next_id]) != before:
                queue.append(next_id)
    ids = sorted(weapon_membership)
    frames = []
    rect_to_ids: dict[tuple[int, int, int, int], list[int]] = {}
    for prototype_id in ids:
        rect = _rect(
            tables["source_x"][prototype_id],
            tables["source_y"][prototype_id],
            tables["width"][prototype_id],
            tables["height"][prototype_id],
        )
        if (
            rect["x"] < 0
            or rect["y"] < 0
            or rect["width"] <= 0
            or rect["height"] <= 0
            or rect["x"] + rect["width"] > sheet_width
            or rect["y"] + rect["height"] > sheet_height
        ):
            raise SpriteAtlasError(
                f"projectile prototype {prototype_id} rectangle is out of bounds"
            )
        frames.append(
            {
                "prototype_id": prototype_id,
                "weapon_ids": sorted(weapon_membership[prototype_id]),
                "next_prototype_id": tables["next_prototype_id"][prototype_id],
                "persistent": tables["persistent"][prototype_id] != 0,
                "source_rect": rect,
                "hit_mask_rect": _mask_rect(rect),
                "confidence": "proven",
            }
        )
        key = (rect["x"], rect["y"], rect["width"], rect["height"])
        rect_to_ids.setdefault(key, []).append(prototype_id)
    aliases = sorted(
        (sorted(group) for group in rect_to_ids.values() if len(group) > 1),
        key=lambda group: group[0],
    )
    return frames, aliases


def _direction_ranges(image: PEImage) -> list[dict[str, Any]]:
    words = image.read_u32_table(DIRECTION_RANGE_TABLE_VA, 18)
    ranges = []
    for index in range(9):
        low_bits = words[index * 2]
        high_bits = words[index * 2 + 1]
        low = struct.unpack("<f", struct.pack("<I", low_bits))[0]
        high = struct.unpack("<f", struct.pack("<I", high_bits))[0]
        ranges.append(
            {
                "bucket": index,
                "minimum_float32": format(low, ".9g"),
                "maximum_float32": format(high, ".9g"),
                "minimum_ieee754_bits": f"0x{low_bits:08x}",
                "maximum_ieee754_bits": f"0x{high_bits:08x}",
            }
        )
    return ranges


def _enemy_layout(image: PEImage) -> dict[str, Any]:
    mirror = image.read_i32_table(MIRROR_INDEX_TABLE_VA, 16)
    source_y = image.read_i32_table(ENEMY_SOURCE_Y_TABLE_VA, 22)
    source_x = image.read_i32_table(ENEMY_SOURCE_X_TABLE_VA, 22)
    directional = []
    for index in range(16):
        rect = _rect(source_x[index], source_y[index], 32, 32)
        directional.append(
            {
                "frame_index": index,
                "source_table_index": index,
                "source_rect": rect,
                "hit_mask_rect": _mask_rect(rect),
                "confidence": "proven",
            }
        )
    formation = []
    for frame_index, table_index in enumerate(range(16, 22)):
        rect = _rect(source_x[table_index], source_y[table_index], 32, 32)
        formation.append(
            {
                "frame_index": frame_index,
                "source_table_index": table_index,
                "source_rect": rect,
                "hit_mask_rect": _mask_rect(rect),
                "confidence": "proven",
            }
        )
    large = []
    for frame_index in range(7):
        rect = _rect(frame_index * 64, 0, 64, 64)
        large.append(
            {
                "frame_index": frame_index,
                "source_rect": rect,
                "hit_mask_rect": _mask_rect(rect),
                "rectangle_confidence": "proven",
                "frame_count_confidence": "supported",
            }
        )
    return {
        "direction_slope_ranges": _direction_ranges(image),
        "mirror_index_table": mirror,
        "families": {
            "directional_32": {
                "frame_width": 32,
                "frame_height": 32,
                "frames": directional,
                "confidence": "proven",
            },
            "formation_animation_32": {
                "frame_width": 32,
                "frame_height": 32,
                "frames": formation,
                "confidence": "proven",
                "semantic_name_confidence": "supported",
            },
            "supplemental_large_animation_64": {
                "frame_width": 64,
                "frame_height": 64,
                "frames": large,
                "confidence": "supported",
                "confidence_boundary": (
                    "The state-6 renderer's 64x64 rectangle formula and source "
                    "coordinates are proven. Seven addressable atlas cells support "
                    "the shared maximum; each supplemental linkage exports the "
                    "proven fixed-record runtime limit."
                ),
            },
        },
    }


def _level_usage(
    level_root: Path, facts: dict[str, Any]
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    facts_by_id = {level["id"]: level for level in facts["levels"]}
    if sorted(facts_by_id) != list(SUPPORTED_LEVEL_IDS):
        raise SpriteAtlasError("known_facts.json must contain exact level IDs 1 through 100")
    usage: list[dict[str, Any]] = []
    supplemental_linkages: list[dict[str, Any]] = []
    for level_id in SUPPORTED_LEVEL_IDS:
        path = level_root / f"classic_level_{level_id:03}.lvd"
        document = lvd_decoder.decode_file(path)
        known = facts_by_id[level_id]
        if document["source"]["sha256"] != known["sha256"]:
            raise SpriteAtlasError(f"{path}: SHA-256 differs from known_facts.json")
        group_modes = sorted(
            {group["group_mode_id"] for group in document["active_groups"]}
        )
        resource_slot_ids = sorted(
            {
                enemy["resource_slot_id"]
                for group in document["active_groups"]
                for enemy in group["enemies"]
            }
        )
        raw_resource = document["resource_slots"][0]["text_cp1252"]
        if raw_resource != known["raw_enemy_reference"]:
            raise SpriteAtlasError(f"{path}: resource slot 1 disagrees with facts")
        enemy_resources: list[dict[str, Any]] = []
        score_words = document["unresolved_tail_array_a"]["raw_words"]
        for slot_id, slot in enumerate(document["resource_slots"][:6], start=1):
            raw_name = slot["text_cp1252"]
            if not raw_name:
                continue
            normalized_sheet_id = Path(raw_name).stem.casefold()
            sheet_id = RAW_RESOURCE_SHEET_IDS.get(raw_name, normalized_sheet_id)
            if sheet_id != normalized_sheet_id or sheet_id not in ENEMY_SHEET_IDS:
                raise SpriteAtlasError(
                    f"{path}: unsupported enemy resource {raw_name!r} in slot {slot_id}"
                )
            enemy_resources.append(
                {
                    "resource_slot_id": slot_id,
                    "raw_name": raw_name,
                    "enemy_sheet_id": sheet_id,
                    "kill_score": score_words[slot_id - 1],
                }
            )
        known_resources = known.get("enemy_resources")
        if known_resources is not None and enemy_resources != known_resources:
            raise SpriteAtlasError(f"{path}: enemy resources disagree with facts")
        if not enemy_resources or enemy_resources[0]["enemy_sheet_id"] != known["packaged_enemy_id"]:
            raise SpriteAtlasError(f"{path}: slot-1 enemy sheet disagrees with facts")
        records = [
            {"record_index": index, "raw_words": words}
            for index, words in enumerate(
                document["global_header"]["supplemental_spawn_records_raw_words"]
            )
            if words[0] != 0
        ]
        snapshot_states = ["entry"]
        observed_opcodes = {
            point["opcode"]
            for group in document["active_groups"]
            for point in group["path_points"]
        }
        if 1 in observed_opcodes:
            snapshot_states.append("formation")
        if document["summary"]["level_mode_id"] == 2 and 6 in observed_opcodes:
            snapshot_states.append("kamikaze")
        if records and level_id in EXPECTED_SUPPLEMENTAL_RECORDS:
            snapshot_states.append("supplemental_large")
        usage.append(
            {
                "level_id": level_id,
                "raw_lvd": _res_path(path),
                "raw_lvd_sha256": document["source"]["sha256"],
                "level_mode_id": document["summary"]["level_mode_id"],
                "authored_enemy_count": document["summary"]["authored_enemy_count"],
                "active_group_count": document["summary"]["active_group_count"],
                "group_mode_ids": group_modes,
                "active_enemy_resource_slot_ids": resource_slot_ids,
                "resource_slot_1_raw_name": raw_resource,
                "enemy_sheet_id": known["packaged_enemy_id"],
                "enemy_resources": enemy_resources,
                "snapshot_authored_states": snapshot_states,
                "supplemental_spawn_records": records,
                "confidence": "proven",
            }
        )
        expected_records = EXPECTED_NONZERO_RECORDS.get(level_id, [])
        if records != expected_records:
            raise SpriteAtlasError(f"level {level_id} nonzero header records changed")
        if level_id not in EXPECTED_SUPPLEMENTAL_RECORDS:
            continue
        for record in records:
            words = record["raw_words"]
            resource_selector = words[1]
            fixed_words = document["unresolved_fixed_table"]["records"][
                record["record_index"]
            ]["raw_words"]
            animation_phase_count = fixed_words[0]
            if animation_phase_count < 1 or animation_phase_count > 7:
                raise SpriteAtlasError(
                    f"level {level_id} supplemental animation phase count is invalid"
                )
            selected_resource = next(
                (
                    resource
                    for resource in enemy_resources
                    if resource["resource_slot_id"] == resource_selector
                ),
                None,
            )
            if selected_resource is None:
                raise SpriteAtlasError(
                    f"level {level_id} supplemental record selects missing resource "
                    f"slot {resource_selector}"
                )
            supplemental_linkages.append({
                "level_id": level_id,
                "record_index": record["record_index"],
                "raw_words": words,
                "spawn_count": words[0],
                "resource_selector": resource_selector,
                "resource_selector_result": {
                    "enemy_sheet_id": selected_resource["enemy_sheet_id"],
                    "texture_global_va": "0x00e1108c",
                    "hit_mask_global_va": "0x00e10ff8",
                    "sheet_width": 576,
                    "sheet_height": 96,
                },
                "original_runtime_state_id": 6,
                "snapshot_authored_state": "supplemental_large",
                "frame_family": "supplemental_large_animation_64",
                "fixed_record_raw_words": fixed_words,
                "animation_phase_count": animation_phase_count,
                "valid_animation_phases": list(range(animation_phase_count)),
                "animation_phase_count_confidence": "proven",
                "field_interpretation": {
                    "word_0_spawn_count": "proven",
                    "word_1_resource_selector": "proven",
                    "word_2_base_health": "supported",
                    "word_3_timer_or_delay": "supported",
                    "word_4_timer_step": "supported",
                },
                "confidence": "supported",
                "confidence_boundary": (
                    "The raw record, spawn count, resource case, active level sheet "
                    "binding, state 6, 64x64 renderer, and fixed-record animation "
                    "bound are proven. Names for words 2-4 remain supported rather "
                    "than asserted as final semantics."
                ),
            })
    expected_linkage_keys = [
        (level_id, record["record_index"])
        for level_id, records in EXPECTED_SUPPLEMENTAL_RECORDS.items()
        for record in records
    ]
    if [
        (entry["level_id"], entry["record_index"])
        for entry in supplemental_linkages
    ] != expected_linkage_keys:
        raise SpriteAtlasError("supplemental linkage levels differ from retail evidence")
    return usage, supplemental_linkages


def _time_trial_level_usage(
    level_root: Path, facts: dict[str, Any]
) -> list[dict[str, Any]]:
    fact_levels = facts.get("time_trial_levels")
    if not isinstance(fact_levels, list):
        raise SpriteAtlasError("known_facts.json must declare time_trial_levels")
    facts_by_id = {level["id"]: level for level in fact_levels}
    if sorted(facts_by_id) != list(TIME_TRIAL_LEVEL_IDS):
        raise SpriteAtlasError(
            "known_facts.json must contain exact Time Trial level IDs 1 through 15"
        )
    usage: list[dict[str, Any]] = []
    for level_id in TIME_TRIAL_LEVEL_IDS:
        path = level_root / "timetrial" / f"timetrial_{level_id:02}.lvd"
        document = lvd_decoder.decode_file(path)
        known = facts_by_id[level_id]
        if document["source"]["sha256"] != known["sha256"]:
            raise SpriteAtlasError(f"{path}: SHA-256 differs from known_facts.json")
        group_modes = sorted(
            {group["group_mode_id"] for group in document["active_groups"]}
        )
        resource_slot_ids = sorted(
            {
                enemy["resource_slot_id"]
                for group in document["active_groups"]
                for enemy in group["enemies"]
            }
        )
        raw_resource = document["resource_slots"][0]["text_cp1252"]
        if raw_resource != known["raw_enemy_reference"]:
            raise SpriteAtlasError(f"{path}: resource slot 1 disagrees with facts")
        enemy_resources: list[dict[str, Any]] = []
        score_words = document["unresolved_tail_array_a"]["raw_words"]
        for slot_id, slot in enumerate(document["resource_slots"][:6], start=1):
            raw_name = slot["text_cp1252"]
            if not raw_name:
                continue
            normalized_sheet_id = Path(raw_name).stem.casefold()
            sheet_id = RAW_RESOURCE_SHEET_IDS.get(raw_name, normalized_sheet_id)
            if sheet_id != normalized_sheet_id or sheet_id not in ALL_ENEMY_SHEET_IDS:
                raise SpriteAtlasError(
                    f"{path}: unsupported enemy resource {raw_name!r} in slot {slot_id}"
                )
            enemy_resources.append(
                {
                    "resource_slot_id": slot_id,
                    "raw_name": raw_name,
                    "enemy_sheet_id": sheet_id,
                    "kill_score": score_words[slot_id - 1],
                }
            )
        known_resources = known.get("enemy_resources")
        if known_resources is not None and enemy_resources != known_resources:
            raise SpriteAtlasError(f"{path}: enemy resources disagree with facts")
        if (
            not enemy_resources
            or enemy_resources[0]["enemy_sheet_id"] != known["packaged_enemy_id"]
        ):
            raise SpriteAtlasError(f"{path}: slot-1 enemy sheet disagrees with facts")
        records = [
            words
            for words in document["global_header"][
                "supplemental_spawn_records_raw_words"
            ]
            if words[0] != 0
        ]
        if records:
            raise SpriteAtlasError(
                f"{path}: Time Trial levels must not carry supplemental spawn records"
            )
        snapshot_states = ["entry"]
        observed_opcodes = {
            point["opcode"]
            for group in document["active_groups"]
            for point in group["path_points"]
        }
        if 1 in observed_opcodes:
            snapshot_states.append("formation")
        if document["summary"]["level_mode_id"] == 2 and 6 in observed_opcodes:
            snapshot_states.append("kamikaze")
        usage.append(
            {
                "level_id": level_id,
                "raw_lvd": _res_path(path),
                "raw_lvd_sha256": document["source"]["sha256"],
                "level_mode_id": document["summary"]["level_mode_id"],
                "authored_enemy_count": document["summary"]["authored_enemy_count"],
                "active_group_count": document["summary"]["active_group_count"],
                "group_mode_ids": group_modes,
                "active_enemy_resource_slot_ids": resource_slot_ids,
                "resource_slot_1_raw_name": raw_resource,
                "enemy_sheet_id": known["packaged_enemy_id"],
                "enemy_resources": enemy_resources,
                "snapshot_authored_states": snapshot_states,
                "supplemental_spawn_records": [],
                "confidence": "proven",
            }
        )
    return usage


def _occupied_bounds(
    hma_path: Path,
    sheet_width: int,
    rect: dict[str, int],
    *,
    allow_empty: bool = False,
) -> dict[str, Any]:
    hma = hma_path.read_bytes()
    occupied: list[tuple[int, int]] = []
    for local_y in range(rect["height"]):
        for local_x in range(rect["width"]):
            source_x = rect["x"] + local_x
            source_y = rect["y"] + local_y
            if hma[source_y * sheet_width + source_x] != 0:
                occupied.append((local_x, local_y))
    if not occupied:
        if not allow_empty:
            raise SpriteAtlasError(f"{hma_path}: projectile rectangle is empty: {rect}")
        return {
            "local_inclusive_bounds": None,
            "occupied_pixel_count": 0,
        }
    xs = [point[0] for point in occupied]
    ys = [point[1] for point in occupied]
    return {
        "local_inclusive_bounds": [min(xs), min(ys), max(xs), max(ys)],
        "occupied_pixel_count": len(occupied),
    }


def _enemy_projectile_contracts(
    asset_paths: dict[str, tuple[Path, Path]],
    mask_assets: dict[str, Any],
    executable_sha256: str,
) -> dict[str, Any]:
    def sheet_masks(
        phase_rects: list[dict[str, int]],
        *,
        allowed_empty_phases: frozenset[tuple[str, int]] = frozenset(),
    ) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for asset_id in ALL_ENEMY_SHEET_IDS:
            asset = mask_assets[asset_id]
            phases = [
                {
                    "phase": phase,
                    "source_rect": rect,
                    **_occupied_bounds(
                        asset_paths[asset_id][1],
                        asset["width"],
                        rect,
                        allow_empty=(asset_id, phase) in allowed_empty_phases,
                    ),
                }
                for phase, rect in enumerate(phase_rects)
            ]
            result[asset_id] = {
                "texture": asset["texture"],
                "hit_mask": asset["hit_mask"],
                "texture_sha256": asset["texture_sha256"],
                "hit_mask_sha256": asset["hit_mask_sha256"],
                "retail_broad_phase_bounds": (
                    list(phases[0]["local_inclusive_bounds"])
                    if phases[0]["local_inclusive_bounds"] is not None
                    else None
                ),
                "phases": phases,
                "confidence": "proven",
            }
        return result

    def broad_phase_evidence(type_id: int) -> dict[str, Any]:
        if type_id == 7:
            spawn_copy_va = "0x0060788c-0x0060792e"
            entity_offsets = ["0x3fc", "0x400", "0x404", "0x408"]
        elif type_id == 6:
            spawn_copy_va = "0x0060f016-0x0060f0b8"
            entity_offsets = ["0x3ec", "0x3f0", "0x3f4", "0x3f8"]
        else:
            raise SpriteAtlasError(f"unsupported enemy projectile type {type_id}")
        return {
            "retail_executable_sha256": executable_sha256,
            "hma_metadata_capture_va": "0x00555a04-0x00555a94",
            "captured_metadata_int_count_per_resource_slot": 8,
            "resource_slot_metadata_table_base_va": "0x00803bd0",
            "entity_initialization_copy_vas": ["0x0056bed6", "0x0056d720"],
            "projectile_spawn_copy_va": spawn_copy_va,
            "projectile_entity_offsets": entity_offsets,
            "collision_consumer_va": "0x00584459-0x005844e2",
            "normalization": (
                "Bounds are sheet-specific and phase-independent; the retail "
                "metadata equals the phase-0 HMA local inclusive bounds."
            ),
            "confidence": "proven",
        }

    ordinary_rects = [_rect(480, 0, 32, 32), _rect(480, 32, 32, 32)]
    supplemental_rects = [_rect(448, 0, 32, 32), _rect(448, 32, 32, 32)]
    return {
        "ordinary_type_7": {
            "pool_capacity": 100,
            "pool_stride_bytes": 140,
            "type_id": 7,
            "spawn_top_left_offset": [13, 16],
            "source_rects": ordinary_rects,
            "sheet_selector": "firing_enemy_sheet",
            "sheet_masks": sheet_masks(
                ordinary_rects,
                allowed_empty_phases=EXACT_EMPTY_PROJECTILE_PHASES[
                    "ordinary_type_7"
                ],
            ),
            "retail_broad_phase_evidence": broad_phase_evidence(7),
            "sound_key": "alienshoot10",
            "sound_binding_va": "0x00607be3-0x00607c51",
            "suppressed_level_modes": [3],
            "spawn_gate_va": "0x006077d2-0x006077fe",
            "spawn_va": "0x0060782c-0x00607a43",
            "update_va": "0x00602d49-0x00602dea",
            "vertical_speed_by_difficulty": {
                "easy": "3.5",
                "normal": "4.300000190734863",
                "hard": "5.0",
                "ace": "5.5",
            },
            "vertical_speed_growth": {
                "factor": "1.024999976158142",
                "period_levels": 100,
                "levels_1_through_100_multiplier": "1.0",
            },
            "horizontal_velocity": {
                "levels_1_through_100_default": "mode-dependent; mode 6 uses aimed lateral velocity",
                "conditional_rule": "when the retail lateral-shot flag is set, choose a target-facing half-open random component in [-1.5,0) or [0,1.5), then multiply by tick scale",
            },
            "bottom_deactivation": "deactivate when projectile bottom is strictly greater than 600",
            "confidence": "proven",
        },
        "supplemental_state_6_type_6": {
            "reachable_levels": list(EXPECTED_SUPPLEMENTAL_RECORDS),
            "type_id": 6,
            "source_rects": supplemental_rects,
            "sheet_selector": "firing_enemy_sheet",
            "sheet_masks": sheet_masks(
                supplemental_rects,
                allowed_empty_phases=EXACT_EMPTY_PROJECTILE_PHASES[
                    "supplemental_state_6_type_6"
                ],
            ),
            "retail_broad_phase_evidence": broad_phase_evidence(6),
            "sound_key": "alienshoot2",
            "sound_binding_va": "0x0060f0be",
            "aimed_fire_va": "0x0060e830-0x0060ee2f",
            "confidence": "proven",
        },
    }


def _fighter_sheet(asset_id: str, asset: dict[str, Any]) -> dict[str, Any]:
    if asset["width"] != 440 or asset["height"] != 28:
        raise SpriteAtlasError(f"{asset_id}: expected a 440x28 atlas")
    frames = []
    for index in range(11):
        rect = _rect(index * 40, 0, 40, 27)
        frames.append(
            {
                "frame_index": index,
                "source_rect": rect,
                "hit_mask_rect": _mask_rect(rect),
                "confidence": "proven",
            }
        )
    return {
        "id": asset_id,
        "texture": asset["texture"],
        "hit_mask": asset["hit_mask"],
        "sheet_width": 440,
        "sheet_storage_height": 28,
        "effective_frame_height": 27,
        "blank_storage_rows": [27],
        "frames": frames,
        "renderer_selection": {
            "formula": (
                "source_x = signed_modulo_11(trunc_toward_zero(frame_value)) * 40; "
                "source_y = 0; width = 40; height = 27"
            ),
            "runtime_frame_field_offset": "player+0x700",
            "instruction_range_va": "0x005f0113-0x005f01a8",
            "confidence": "proven",
        },
        "producer_rule": {
            "initial_frame_value": "5.0",
            "neutral_frame_value": "5.0",
            "step_per_update": "0.5",
            "minimum_frame_value": "0.0",
            "maximum_transient_frame_value": "10.5",
            "maximum_rendered_frame_index": 10,
            "left_active": "frame_value = max(0.0, frame_value - 0.5)",
            "right_active": (
                "frame_value += 0.5; when frame_value reaches 11.0, "
                "reset it to 10.0"
            ),
            "no_horizontal_input": (
                "move frame_value toward 5.0 by 0.5 without overshoot"
            ),
            "simultaneous_branch_order": [
                "left input branch",
                "right input branch",
                "neutral return is skipped when either branch was active",
            ],
            "snapshot_field": "sprite_frame",
            "snapshot_value": "trunc_toward_zero(frame_value)",
            "instruction_ranges_va": [
                "0x005eb649-0x005eb6aa",
                "0x005eb935-0x005eb99a",
                "0x005ec978-0x005eca10",
            ],
            "confidence": "proven",
        },
        "confidence": "proven",
    }


def build_document(
    exe_path: Path = DEFAULT_EXE,
    asset_root: Path = DEFAULT_ASSET_ROOT,
    level_root: Path = DEFAULT_LEVEL_ROOT,
) -> dict[str, Any]:
    facts = _load_json(KNOWN_FACTS_PATH)
    exe_data = exe_path.read_bytes()
    exe_hash = _sha256(exe_data)
    expected_hash = facts["source_files"]["executable"]["sha256"]
    if exe_hash != expected_hash:
        raise SpriteAtlasError(
            f"{exe_path}: SHA-256 {exe_hash} does not match {expected_hash}"
        )
    image = PEImage(exe_data)
    state_ten_source_region = _verified_instruction_region(
        image,
        STATE_TEN_SOURCE_SELECTION_VA,
        STATE_TEN_SOURCE_SELECTION_SIZE,
        STATE_TEN_SOURCE_SELECTION_SHA256,
    )
    state_ten_phase_region = _verified_instruction_region(
        image,
        STATE_TEN_PHASE_UPDATE_VA,
        STATE_TEN_PHASE_UPDATE_SIZE,
        STATE_TEN_PHASE_UPDATE_SHA256,
    )
    asset_paths = {
        "alien001": (
            asset_root / "enemies" / "alien001.tga",
            asset_root / "enemies" / "alien001.hma",
        ),
        "alien_2": (
            asset_root / "enemies" / "alien_2.tga",
            asset_root / "enemies" / "alien_2.hma",
        ),
        "alien_3": (
            asset_root / "enemies" / "alien_3.tga",
            asset_root / "enemies" / "alien_3.hma",
        ),
        "alien000": (
            asset_root / "enemies" / "alien000.tga",
            asset_root / "enemies" / "alien000.hma",
        ),
        "alien_lilla": (
            asset_root / "enemies" / "alien_lilla.tga",
            asset_root / "enemies" / "alien_lilla.hma",
        ),
        "alien003": (
            asset_root / "enemies" / "alien003.tga",
            asset_root / "enemies" / "alien003.hma",
        ),
        "alien003_3": (
            asset_root / "enemies" / "alien003_3.tga",
            asset_root / "enemies" / "alien003_3.hma",
        ),
        **{
            f"alien_big1_{index}": (
                asset_root / "enemies" / f"alien_big1_{index}.tga",
                asset_root / "enemies" / f"alien_big1_{index}.hma",
            )
            for index in range(1, 7)
        },
        "alien_rakett": (
            asset_root / "enemies" / "alien_rakett.tga",
            asset_root / "enemies" / "alien_rakett.hma",
        ),
        "alien_rakett_gronn": (
            asset_root / "enemies" / "alien_rakett_gronn.tga",
            asset_root / "enemies" / "alien_rakett_gronn.hma",
        ),
        "alien_baller": (
            asset_root / "enemies" / "alien_baller.tga",
            asset_root / "enemies" / "alien_baller.hma",
        ),
        "alien_baller2": (
            asset_root / "enemies" / "alien_baller2.tga",
            asset_root / "enemies" / "alien_baller2.hma",
        ),
        "alien_green_lilla_t": (
            asset_root / "enemies" / "alien_green_lilla_t.tga",
            asset_root / "enemies" / "alien_green_lilla_t.hma",
        ),
        "alien_cyan_lilla_t": (
            asset_root / "enemies" / "alien_cyan_lilla_t.tga",
            asset_root / "enemies" / "alien_cyan_lilla_t.hma",
        ),
        "alien_raudkule": (
            asset_root / "enemies" / "alien_raudkule.tga",
            asset_root / "enemies" / "alien_raudkule.hma",
        ),
        "alien_raudkule2": (
            asset_root / "enemies" / "alien_raudkule2.tga",
            asset_root / "enemies" / "alien_raudkule2.hma",
        ),
        "alien_blavinger_gf": (
            asset_root / "enemies" / "alien_blavinger_gf.tga",
            asset_root / "enemies" / "alien_blavinger_gf.hma",
        ),
        "alien_blavinger_gf2": (
            asset_root / "enemies" / "alien_blavinger_gf2.tga",
            asset_root / "enemies" / "alien_blavinger_gf2.hma",
        ),
        "alien_rbille": (
            asset_root / "enemies" / "alien_rbille.tga",
            asset_root / "enemies" / "alien_rbille.hma",
        ),
        **{
            f"alien_big2_{index}": (
                asset_root / "enemies" / f"alien_big2_{index}.tga",
                asset_root / "enemies" / f"alien_big2_{index}.hma",
            )
            for index in range(1, 7)
        },
        **{
            asset_id: (
                asset_root / "enemies" / f"{asset_id}.tga",
                asset_root / "enemies" / f"{asset_id}.hma",
            )
            for asset_id in (
                "alien_gultop",
                "alien_lillatop",
                "alien_bluekreps",
                "alien_lbluekreps",
                "alien_brownkreps",
                "alien_brownkreps2",
                "alien_gulkreps",
                "alien_rvinggk",
                "alien_gvingbk",
            )
        },
        **{
            asset_id: (
                asset_root / "enemies" / f"{asset_id}.tga",
                asset_root / "enemies" / f"{asset_id}.hma",
            )
            for asset_id in ENEMY_SHEET_IDS[39:]
        },
        **{
            asset_id: (
                asset_root
                / "enemies"
                / f"{ENEMY_SHEET_ASSET_STEMS.get(asset_id, asset_id)}.tga",
                asset_root
                / "enemies"
                / f"{ENEMY_SHEET_ASSET_STEMS.get(asset_id, asset_id)}.hma",
            )
            for asset_id in TIME_TRIAL_ENEMY_SHEET_IDS
        },
        "fighter1": (
            asset_root / "player" / "fighter1.tga",
            asset_root / "player" / "fighter1.hma",
        ),
        "fighter2": (
            asset_root / "player" / "fighter2.tga",
            asset_root / "player" / "fighter2.hma",
        ),
        "weapons_big": (
            asset_root / "weapons" / "weapons_big.tga",
            asset_root / "weapons" / "weapons_big.hma",
        ),
    }
    mask_assets = {
        asset_id: _mask_asset(asset_id, paths[0], paths[1])
        for asset_id, paths in asset_paths.items()
    }
    enemy_layout = _enemy_layout(image)
    level_usage, supplemental_linkages = _level_usage(level_root, facts)
    time_trial_level_usage = _time_trial_level_usage(level_root, facts)
    projectile_frames, projectile_aliases = _projectile_frames(
        image,
        facts,
        mask_assets["weapons_big"]["width"],
        mask_assets["weapons_big"]["height"],
    )
    enemy_sheets = []
    for asset_id in ALL_ENEMY_SHEET_IDS:
        asset = mask_assets[asset_id]
        if asset["width"] != 576 or asset["height"] != 96:
            raise SpriteAtlasError(f"{asset_id}: expected a 576x96 atlas")
        enemy_sheets.append(
            {
                "id": asset_id,
                "texture": asset["texture"],
                "hit_mask": asset["hit_mask"],
                "sheet_width": asset["width"],
                "sheet_height": asset["height"],
                "frame_width": asset["width"],
                "frame_height": asset["height"],
                "shared_frame_families": [
                    "directional_32",
                    "formation_animation_32",
                    "supplemental_large_animation_64",
                ],
                "confidence": "proven",
            }
        )
    return {
        "version": 11,
        "schema": "warblade.sprite-frames.v11",
        "confidence_scale": {
            "proven": (
                "Confirmed by exact source bytes plus a traced executable producer "
                "and/or renderer consumer."
            ),
            "supported": (
                "The structure is strongly constrained by traced code and atlas "
                "contents, but a final semantic name or dynamic bound remains open."
            ),
            "unresolved": "No behavior is asserted beyond retained raw evidence.",
        },
        "source": {
            "warblade_exe": {
                "file_name": exe_path.name,
                "sha256": exe_hash,
                "preferred_image_base": f"0x{image.image_base:08x}",
            },
            "method": (
                "Deterministic PE table extraction, bounded static instruction "
                "traces, lossless LVD decoding, TGA header/RLE decoding, and direct "
                "HMA byte validation. Runtime screenshots are not source evidence."
            ),
            "table_virtual_addresses": {
                **{
                    f"projectile_{name}": f"0x{address:08x}"
                    for name, address in PROJECTILE_TABLE_VAS.items()
                },
                "direction_slope_ranges": f"0x{DIRECTION_RANGE_TABLE_VA:08x}",
                "direction_mirror_indices": f"0x{MIRROR_INDEX_TABLE_VA:08x}",
                "enemy_source_y": f"0x{ENEMY_SOURCE_Y_TABLE_VA:08x}",
                "enemy_source_x": f"0x{ENEMY_SOURCE_X_TABLE_VA:08x}",
            },
            "renderer_evidence": {
                "player_renderer": "fcn.005ef1b0",
                "enemy_renderer": "fcn.00618560",
                "projectile_renderer": "fcn.006211e0",
                "ordinary_enemy_selection_va": "0x0060939c-0x006095e8",
                "formation_enemy_selection_va": "0x006095ed-0x0060966c",
                "supplemental_state_6_renderer_va": "0x0061924d-0x006192c9",
                "supplemental_state_6_source_update_va": "0x0060f90b-0x0060f92f",
                "state_10_source_selection": state_ten_source_region,
                "state_10_phase_update": state_ten_phase_region,
            },
        },
        "hit_mask_format": {
            "encoding": "headerless unsigned 8-bit occupancy",
            "byte_count": "sheet_width * sheet_height",
            "storage_order": "row-major, top-left origin",
            "empty_value": 0,
            "occupied_value": 1,
            "index_formula": (
                "(source_y + local_y) * sheet_width + source_x + local_x"
            ),
            "source_rect_contract": (
                "Texture and HMA use the identical source rectangle; there is no "
                "vertical flip or separate mask atlas transform."
            ),
            "loader_evidence_va": "0x005300a0 (read at 0x00530189-0x0053019e)",
            "consumer_evidence_va": "0x00555230 (index at 0x00555289-0x005552a2)",
            "confidence": "proven",
            "assets": [mask_assets[key] for key in sorted(mask_assets)],
        },
        "level_usage": level_usage,
        "time_trial_level_usage": time_trial_level_usage,
        "enemy_sheets": enemy_sheets,
        "enemy_frame_layout": enemy_layout,
        "enemy_projectile_contracts": _enemy_projectile_contracts(
            asset_paths, mask_assets, exe_hash
        ),
        "renderer_state_contracts": [
            {
                "snapshot_match": {"authored_state": "entry"},
                "original_runtime_state_id": 1,
                "frame_family": "directional_32",
                "frame_selection": {
                    "inputs": ["velocity_x", "velocity_y", "mirror_x"],
                    "slope": (
                        "float32(velocity_y / velocity_x); when velocity_x is zero, "
                        "use +5000.0 if velocity_y > 0, otherwise -5000.0"
                    ),
                    "base_index": "0 when velocity_x >= 0, otherwise 8",
                    "bucket": (
                        "first strict-open interval minimum < slope < maximum "
                        "in direction_slope_ranges; index = (base_index + bucket) "
                        "modulo 16. If slope equals a boundary and no interval "
                        "matches, the initialized base index is retained."
                    ),
                    "mirror": (
                        "when mirror_x is nonzero, replace index through "
                        "mirror_index_table"
                    ),
                },
                "confidence": "proven",
            },
            {
                "snapshot_match": {"authored_state": "hold"},
                "original_runtime_state_id": 1,
                "frame_family": "directional_32",
                "frame_selection": (
                    "Preserve the last state-1 directional frame while velocity "
                    "and acceleration are cleared."
                ),
                "confidence": "supported",
            },
            {
                "snapshot_match": {"authored_state": "formation"},
                "original_runtime_state_id": 2,
                "frame_family": "formation_animation_32",
                "frame_selection": {
                    "snapshot_field": "authored_animation_frame",
                    "formula": "trunc_toward_zero(original animation phase)",
                    "valid_indices": [0, 1, 2, 3, 4, 5],
                },
                "confidence": "proven",
            },
            {
                "snapshot_match": {"authored_state": "supplemental_large"},
                "original_runtime_state_id": 6,
                "level_ids": list(EXPECTED_SUPPLEMENTAL_RECORDS),
                "frame_family": "supplemental_large_animation_64",
                "frame_selection": {
                    "snapshot_field": "authored_animation_frame",
                    "formula": "source_x = trunc_toward_zero(animation phase) * 64",
                    "source_y": 0,
                    "valid_indices": [0, 1, 2, 3, 4, 5, 6],
                },
                "confidence": "supported",
                "confidence_boundary": (
                    "The state, formula, size, and addressable rectangles are proven; "
                    "the seven-frame dynamic bound is supported."
                ),
            },
            {
                "snapshot_match": {"authored_state": "state_ten"},
                "original_runtime_state_id": 10,
                "frame_family": "formation_animation_32",
                "frame_selection": {
                    "snapshot_field": "authored_animation_frame",
                    "formula": "trunc_toward_zero(original animation phase)",
                    "valid_indices": [0, 1, 2, 3, 4, 5],
                    "source_y_table_va": "0x007d02a8",
                    "source_x_table_va": "0x007d0300",
                    "selection_instruction_region": state_ten_source_region,
                    "phase_update": {
                        "countdown_subtract": "retail tick scale",
                        "advance_when": "countdown is strictly below zero",
                        "countdown_reset": "4.0",
                        "direction_nonzero": "decrement and wrap below zero to 5",
                        "direction_zero": "increment and wrap above 5 to zero",
                        "instruction_region": state_ten_phase_region,
                    },
                },
                "confidence": "proven",
            },
        ],
        "supplemental_spawn_linkages": supplemental_linkages,
        "fighter_sheets": [
            _fighter_sheet("fighter1", mask_assets["fighter1"]),
            _fighter_sheet("fighter2", mask_assets["fighter2"]),
        ],
        "projectile_sheet": {
            "id": "weapons_big",
            "texture": mask_assets["weapons_big"]["texture"],
            "hit_mask": mask_assets["weapons_big"]["hit_mask"],
            "sheet_width": mask_assets["weapons_big"]["width"],
            "sheet_height": mask_assets["weapons_big"]["height"],
            "prototype_scope": (
                "All spawn and animation prototype IDs reachable from the nine "
                "playable fighter graphs and their Scoop-captive mappings in "
                "tools/known_facts.json."
            ),
            "frames": projectile_frames,
            "exact_alias_groups": projectile_aliases,
            "confidence": "proven",
        },
        "unresolved": [
            (
                "The human-readable pose names for directional indices 0-15 and "
                "formation animation indices 0-5 are not asserted."
            ),
            (
                "The shared supplemental state-6 family exposes seven addressable "
                "64x64 frames; each level linkage carries its proven fixed-record "
                "phase bound."
            ),
            (
                "Enemy-projectile graphics embedded at x=448 and x=480 use the "
                "separate enemy_projectile_contracts mapping rather than the "
                "player-weapon prototype table."
            ),
        ],
    }


def _write_document(document: dict[str, Any], output_path: Path | None) -> None:
    text = json.dumps(document, indent=2, ensure_ascii=False) + "\n"
    if output_path is None:
        sys.stdout.write(text)
    else:
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(text, encoding="utf-8")


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Extract exact first-one-hundred Warblade sprite rectangles and HMA mappings "
            "from the verified retail PE and copied original assets."
        )
    )
    parser.add_argument("--exe", type=Path, default=DEFAULT_EXE)
    parser.add_argument("--asset-root", type=Path, default=DEFAULT_ASSET_ROOT)
    parser.add_argument("--level-root", type=Path, default=DEFAULT_LEVEL_ROOT)
    parser.add_argument("-o", "--output", type=Path)
    return parser


def main() -> int:
    args = _build_parser().parse_args()
    try:
        _write_document(
            build_document(args.exe, args.asset_root, args.level_root),
            args.output,
        )
        return 0
    except (OSError, json.JSONDecodeError, SpriteAtlasError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
