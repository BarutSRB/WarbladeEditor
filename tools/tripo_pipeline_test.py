#!/usr/bin/env python3
"""Offline unit tests for tools/tripo_pipeline.py.

No network, no Godot, no credits: covers the pure image-finishing helpers and
the sheet composer against the real frozen layout contracts in content/.
Requires Pillow, like the pipeline itself.
"""
from __future__ import annotations

import argparse
import io
import json
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import tripo_pipeline as tp

from PIL import Image

FAILURES: list[str] = []


def expect(condition: bool, message: str) -> None:
    if not condition:
        FAILURES.append(message)


def solid(width: int, height: int, color: tuple[int, int, int, int]) -> Image.Image:
    return Image.new("RGBA", (width, height), color)


def test_premultiplied_downscale_kills_fringe() -> None:
    source = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    pixels = source.load()
    for y in range(64):
        for x in range(64):
            if (x - 32) ** 2 + (y - 32) ** 2 <= 20 ** 2:
                pixels[x, y] = (255, 255, 255, 255)
    small = tp.premultiplied_downscale(source, 16, 16)
    for red, green, blue, alpha in small.getdata():
        if alpha > 200:
            expect(
                min(red, green, blue) > 200,
                "premultiplied downscale must not bleed transparent black into edges "
                "(got %d,%d,%d,%d)" % (red, green, blue, alpha),
            )
    expect(small.size == (16, 16), "downscale hits the requested cell size")


def test_threshold_alpha_is_binary() -> None:
    source = Image.new("RGBA", (4, 1))
    source.putdata([(255, 0, 0, 10), (255, 0, 0, 95), (255, 0, 0, 96), (255, 0, 0, 240)])
    thresholded = tp.threshold_alpha(source, 96)
    alphas = [pixel[3] for pixel in thresholded.getdata()]
    expect(alphas == [0, 0, 255, 255], "alpha threshold is a hard binary cut at the threshold")


def test_quantize_shared_palette() -> None:
    import random
    generator = random.Random(7)
    frames = []
    for _ in range(2):
        frame = Image.new("RGBA", (16, 16))
        frame.putdata([
            (generator.randrange(256), generator.randrange(256), generator.randrange(256), 255)
            for _ in range(256)
        ])
        frames.append(frame)
    quantized = tp.quantize_shared(frames, 8, dither=False)
    palette: set[tuple[int, int, int]] = set()
    for frame in quantized:
        for red, green, blue, _alpha in frame.getdata():
            palette.add((red, green, blue))
    expect(len(palette) <= 8, "shared quantize uses one palette across frames (got %d)" % len(palette))
    passthrough = tp.quantize_shared(frames, 0, dither=False)
    expect(passthrough is frames, "palette_colors 0 keeps full color untouched")


def test_outline_ring() -> None:
    source = Image.new("RGBA", (8, 8), (0, 0, 0, 0))
    for y in (3, 4):
        for x in (3, 4):
            source.putpixel((x, y), (255, 0, 0, 255))
    outlined = tp.outline_sprite(source, (16, 16, 48, 255))
    ring = [
        (x, y)
        for y in range(8)
        for x in range(8)
        if outlined.getpixel((x, y)) == (16, 16, 48, 255)
    ]
    expect(len(ring) == 8, "a 2x2 block grows an 8-pixel 4-adjacent ink ring (got %d)" % len(ring))


def test_hue_rotate() -> None:
    red = solid(4, 4, (255, 0, 0, 255))
    rotated = tp.hue_rotate(red, 120.0)
    sample = rotated.getpixel((0, 0))
    expect(sample[1] > sample[0], "a 120-degree hue rotation moves red toward green")
    expect(sample[3] == 255, "hue rotation preserves alpha")


def test_silhouette_iou() -> None:
    a = solid(8, 8, (255, 255, 255, 255))
    expect(tp.silhouette_iou(a, a) == 1.0, "identical silhouettes give IoU 1.0")
    empty = Image.new("RGBA", (8, 8), (0, 0, 0, 0))
    half = Image.new("RGBA", (8, 8), (0, 0, 0, 0))
    for y in range(8):
        for x in range(4):
            half.putpixel((x, y), (255, 255, 255, 255))
    expect(abs(tp.silhouette_iou(half, a) - 0.5) < 1e-6, "half overlap gives IoU 0.5")
    expect(tp.silhouette_iou(empty, a) == 0.0, "disjoint silhouettes give IoU 0.0")


def test_compose_enemy_sheet_against_real_contracts() -> None:
    sprite_frames, presentation = tp.load_layout_contracts()
    directional = [solid(32, 32, (index * 10 + 10, 0, 0, 255)) for index in range(16)]
    formation = [solid(32, 32, (0, index * 20 + 20, 0, 255)) for index in range(6)]
    large = [solid(64, 64, (0, 0, index * 20 + 20, 255)) for index in range(7)]
    sheet = tp.compose_enemy_sheet(
        sprite_frames, presentation,
        {"directional": directional, "formation": formation, "large": large},
    )
    expect(sheet.size == (576, 96), "enemy sheets are exactly 576x96")
    rects = tp.family_rects(sprite_frames, "directional_32")
    expect(len(rects) == 16, "the directional family carries 16 heading frames")
    first = rects[0]
    expect(
        sheet.getpixel((int(first["x"]) + 16, int(first["y"]) + 16)) == (10, 0, 0, 255),
        "directional frame 0 lands in its contract rect",
    )
    last = rects[15]
    expect(
        sheet.getpixel((int(last["x"]) + 16, int(last["y"]) + 16)) == (160, 0, 0, 255),
        "directional frame 15 lands in its contract rect",
    )
    formation_rects = tp.family_rects(sprite_frames, "formation_animation_32")
    expect(len(formation_rects) == 6, "the formation family carries 6 frames")
    formation_first = formation_rects[0]
    expect(
        sheet.getpixel(
            (int(formation_first["x"]) + 16, int(formation_first["y"]) + 16)
        ) == (0, 20, 0, 255),
        "formation frame 0 lands in its contract rect",
    )
    large_rects = tp.family_rects(sprite_frames, "supplemental_large_animation_64")
    expect(len(large_rects) == 7, "the supplemental family carries 7 frames")
    shot_rects = presentation["projectile_sheets"]["enemy_projectiles"]["source_rects"]
    for rect in shot_rects:
        x, y = int(rect[0]), int(rect[1])
        expect(
            sheet.getpixel((x + 16, y + 16))[3] > 0,
            "shot cell at (%d,%d) is populated" % (x, y),
        )
        expect(
            sheet.getpixel((x - 32 + 16, y + 16))[3] > 0,
            "the 448-column shot cell mirror at (%d,%d) is populated" % (x - 32, y),
        )


def test_compose_fighter_sheet_against_real_contracts() -> None:
    sprite_frames, _presentation = tp.load_layout_contracts()
    frames = [solid(40, 27, (index * 20 + 15, 40, 90, 255)) for index in range(11)]
    sheet = tp.compose_fighter_sheet(sprite_frames, "fighter1", frames)
    expect(sheet.size == (440, 28), "fighter sheets are exactly 440x28")
    expect(
        sheet.getpixel((120 + 20, 13)) == (75, 40, 90, 255),
        "banking frame 3 lands at x=120",
    )
    bottom_row = [sheet.getpixel((x, 27))[3] for x in range(440)]
    expect(max(bottom_row) == 0, "storage row 27 stays fully transparent")


def test_mask_and_orb() -> None:
    sheet = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    sheet.putpixel((4, 4), (10, 20, 30, 255))
    mask = tp.derive_mask_sheet(sheet)
    expect(mask.getpixel((4, 4)) == (255, 255, 255, 255), "masks are white where art exists")
    expect(mask.getpixel((0, 0))[3] == 0, "masks are transparent elsewhere")
    orb = tp.draw_shot_orb(32, (255, 160, 60), 10.0)
    expect(orb.getpixel((16, 16))[3] == 255, "the shot orb has an opaque core")
    expect(orb.getpixel((0, 0))[3] == 0, "the shot orb corners stay transparent")


def test_pack_upsert_and_validate() -> None:
    original_root = tp.PACKS_ROOT
    with tempfile.TemporaryDirectory() as scratch:
        tp.PACKS_ROOT = Path(scratch)
        try:
            sheet = solid(576, 96, (200, 100, 40, 255))
            buffer = io.BytesIO()
            sheet.save(buffer, format="PNG")
            destination = tp.pack_dir("test") / "textures" / "alien001.png"
            tp.write_bytes_atomic(destination, buffer.getvalue())
            tp.upsert_pack_entries("test", {
                "alien001": {"path": "textures/alien001.png", "width": 576, "height": 96, "source": {}},
            })
            manifest = tp.load_pack_manifest("test")
            expect(
                manifest["schema"] == tp.PACK_SCHEMA and "alien001" in manifest["textures"],
                "upsert writes a schema-stamped manifest with the new entry",
            )
            code = tp.cmd_validate(argparse.Namespace(pack="test"))
            expect(code == 0, "a well-formed pack validates cleanly")
            tp.upsert_pack_entries("test", {
                "fighter1": {"path": "textures/missing.png", "width": 440, "height": 28, "source": {}},
                "not_a_retail_key": {"path": "textures/alien001.png", "width": 576, "height": 96, "source": {}},
            })
            code = tp.cmd_validate(argparse.Namespace(pack="test"))
            expect(code == 1, "missing files and unknown keys fail validation")
        finally:
            tp.PACKS_ROOT = original_root


def test_pixel_art_finish_flattens_and_outlines() -> None:
    import random
    generator = random.Random(3)
    frames = []
    for _ in range(2):
        frame = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
        pixels = frame.load()
        for y in range(32):
            for x in range(32):
                if (x - 16) ** 2 + (y - 16) ** 2 <= 13 ** 2:
                    pixels[x, y] = (
                        140 + generator.randrange(80),
                        70 + generator.randrange(60),
                        20 + generator.randrange(40),
                        255,
                    )
        frames.append(frame)
    cfg = {"base_colors": 8, "cleanup_passes": 2, "alpha_threshold": 96}
    finished = tp.pixel_art_finish(frames, (32, 32), cfg)
    colors: set[tuple[int, int, int]] = set()
    for frame in finished:
        for red, green, blue, alpha in frame.getdata():
            if alpha > 0:
                colors.add((red, green, blue))
    expect(
        len(colors) <= 12,
        "the pixel-art pass flattens photo noise into a small shared palette (got %d colors)"
        % len(colors),
    )
    sample = finished[0]
    edge_pixel = None
    for y in range(32):
        for x in range(32):
            if sample.getpixel((x, y))[3] > 0:
                edge_pixel = sample.getpixel((x, y))
                break
        if edge_pixel:
            break
    expect(
        edge_pixel is not None and _lum(edge_pixel) < 0.3,
        "silhouette edges carry a dark colored outline",
    )


def _lum(pixel) -> float:
    return (0.2126 * pixel[0] + 0.7152 * pixel[1] + 0.0722 * pixel[2]) / 255.0


def test_cache_key_and_prompt() -> None:
    key_one = tp.generation_cache_key("a", "b", 1, "v2.5")
    key_two = tp.generation_cache_key("a", "b", 1, "v2.5")
    key_three = tp.generation_cache_key("a", "b", 2, "v2.5")
    expect(key_one == key_two, "cache keys are deterministic")
    expect(key_one != key_three, "seed changes the cache key")
    style = tp.load_style("solstice")
    concept = tp.load_concept("alien001")
    prompt = tp.build_prompt(style, concept)
    expect("scarab" in prompt and "celestial fantasy" in prompt, "prompts join subject and style suffix")
    job = tp.build_render_job("alien001", concept, style)
    expect(job["schema"] == tp.RENDER_JOB_SCHEMA, "render jobs are schema-stamped")
    expect(len(job["shots"]) == 3, "enemy sheets plan directional, formation, and large shots")


def main() -> int:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    if FAILURES:
        for failure in FAILURES:
            print("FAIL: %s" % failure, file=sys.stderr)
        print("TRIPO PIPELINE TESTS FAILED: %d" % len(FAILURES))
        return 1
    print("TRIPO PIPELINE TESTS PASSED (%d tests)" % len(tests))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
