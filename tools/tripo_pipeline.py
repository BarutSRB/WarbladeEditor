#!/usr/bin/env python3
"""Tripo -> sprite-pack authoring pipeline.

Generates 3D models with the Tripo API (`gen`), renders them to frames with
the windowed Godot tool at tools/render/render_cli.gd (`render`), finishes
frames into cell-sized sprites (`post`), composes retail-geometry sheets into
a sprite pack (`sheet`), and validates a pack against the retail manifest
(`validate`).

This is an AUTHORING tool, deliberately outside `make verify`: `gen` needs
network access and spends Tripo credits, `render` needs a windowed Godot.
`post`, `sheet`, and `validate` are offline and deterministic. Requires
Pillow -- the one third-party exception in tools/, used only by this
authoring flow (tools/tripo_pipeline_test.py covers the pure functions).

Frame geometry is read from content/sprite_frames.json and
content/presentation.json; nothing is hardcoded. Retail rasters are NEVER
uploaded to Tripo (extracted assets carry redistribution restrictions) --
generation is text-prompt only.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

try:
    from PIL import Image
except ImportError:  # pragma: no cover - exercised only on hosts without Pillow
    Image = None

ROOT = Path(__file__).resolve().parents[1]
CONTENT_DIR = ROOT / "content"
BUILD_DIR = ROOT / "build" / "sprite_pipeline"
STYLES_DIR = ROOT / "tools" / "sprite_styles"
CONCEPTS_DIR = ROOT / "tools" / "sprite_concepts"
PACKS_ROOT = ROOT / "assets" / "packs"
RENDER_CLI = "res://tools/render/render_cli.gd"

API_BASE = "https://api.tripo3d.ai/v2/openapi"
API_KEY_FILE = Path.home() / ".config" / "tripo" / "api_key"
POLL_INTERVAL_SECONDS = 5.0
POLL_TIMEOUT_SECONDS = 900.0

STYLE_SCHEMA = "warblade.sprite-style.v1"
CONCEPT_SCHEMA = "warblade.sprite-concept.v1"
RENDER_JOB_SCHEMA = "warblade.render-job.v1"
PACK_SCHEMA = "warblade.sprite-pack.v1"

# Shot plans per concept kind. Cell sizes mirror the retail frame families the
# sheet step pastes into; the render tool only sees mode/frames/pose knobs.
KIND_SHOTS: dict[str, list[dict[str, Any]]] = {
    "fighter": [
        {
            "id": "banking",
            "mode": "banking_sweep",
            "frames": 11,
            "max_bank_degrees": 38.0,
            "cell": (40, 27),
        },
    ],
    "enemy_sheet": [
        {"id": "directional", "mode": "turntable16", "frames": 16, "cell": (32, 32)},
        {
            "id": "formation",
            "mode": "pose_wobble",
            "frames": 6,
            "wobble_degrees": 8.0,
            "scale_pulse": 0.04,
            "cell": (32, 32),
        },
        {
            "id": "large",
            "mode": "pose_wobble",
            "frames": 7,
            "wobble_degrees": 5.0,
            "scale_pulse": 0.03,
            "cell": (64, 64),
        },
    ],
    "static": [
        {"id": "static", "mode": "static", "frames": 1, "cell": (64, 64)},
    ],
    # Procedural kinds are composed directly by `sheet`; gen/render/post are
    # no-ops for them (drawn energy shapes and tokens, not Tripo models).
    "procedural_weapons": [],
    "procedural_pickups": [],
    "procedural_explosion": [],
}

SOLSTICE_INK = (19, 21, 48, 255)

WEAPON_COLORS: dict[int, tuple[int, int, int]] = {
    0: (255, 195, 87),   # Single -- sun gold
    1: (255, 195, 87),   # Double -- sun gold
    2: (111, 242, 255),  # Quad -- glow cyan
    3: (44, 232, 245),   # Triple -- teal
    4: (255, 93, 162),   # Plasma -- magenta
    5: (44, 232, 245),   # Super Triple -- teal
    6: (255, 122, 47),   # Fireballs -- ember
    7: (111, 242, 255),  # Laser -- cyan-white beam
    8: (255, 93, 162),   # War.I.Plasma -- magenta-gold
}

PICKUP_GLYPHS: dict[str, str] = {
    "letter_e": "E", "letter_x": "X", "letter_t": "T", "letter_r": "R", "letter_a": "A",
    "mystery": "?",
}

PICKUP_COLORS: dict[str, tuple[int, int, int]] = {
    "letter_e": (255, 195, 87), "letter_x": (255, 195, 87), "letter_t": (255, 195, 87),
    "letter_r": (255, 195, 87), "letter_a": (255, 195, 87),
    "money_10": (201, 209, 221), "money_50": (255, 195, 87),
    "money_100": (111, 242, 255), "money_200": (255, 93, 162),
    "shield": (142, 240, 255), "armour": (142, 240, 255),
    "extra_life": (255, 243, 214), "extra_time": (111, 242, 255),
    "score_x2": (255, 93, 162), "score_x5": (255, 93, 162),
    "money_doubler": (255, 179, 71), "warp": (141, 79, 230), "mystery": (141, 79, 230),
    "auto_fire": (44, 232, 245), "extra_bullet": (44, 232, 245),
    "extra_speed": (44, 232, 245), "extra_bullet_speed": (44, 232, 245),
    "double": (44, 232, 245), "single": (44, 232, 245), "triple": (44, 232, 245),
    "quad": (44, 232, 245), "scoop": (44, 232, 245),
    "gem_bomb": (82, 227, 154), "money_bomb": (255, 179, 71),
    "memory_station": (141, 79, 230), "meteor_storm": (255, 122, 47),
    "sucker_blue_money": (82, 227, 154), "sucker_gem_counter": (82, 227, 154),
    "sucker_meteor_multiplier": (82, 227, 154),
    "mirror": (201, 209, 221), "freeze": (142, 240, 255), "drunk_mode": (255, 93, 162),
}

GLYPH_3X5: dict[str, list[str]] = {
    "E": ["###", "#..", "###", "#..", "###"],
    "X": ["#.#", "#.#", ".#.", "#.#", "#.#"],
    "T": ["###", ".#.", ".#.", ".#.", ".#."],
    "R": ["##.", "#.#", "##.", "#.#", "#.#"],
    "A": [".#.", "#.#", "###", "#.#", "#.#"],
    "?": ["###", "..#", ".##", "...", ".#."],
}


def fail(message: str) -> int:
    print("ERROR: %s" % message, file=sys.stderr)
    return 1


def require_pillow() -> None:
    if Image is None:
        raise SystemExit(
            "Pillow is required for post/sheet/validate: PATH=/opt/homebrew/bin:$PATH "
            "python3 -m pip install --user pillow"
        )


def write_bytes_atomic(path: Path, payload: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    handle, temporary_name = tempfile.mkstemp(dir=str(path.parent), prefix=".%s." % path.name)
    try:
        with os.fdopen(handle, "wb") as stream:
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary_name, path)
    finally:
        if os.path.exists(temporary_name):
            os.unlink(temporary_name)


def write_json_atomic(path: Path, document: dict[str, Any]) -> None:
    write_bytes_atomic(path, (json.dumps(document, indent=2, sort_keys=True) + "\n").encode("utf-8"))


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as stream:
        document = json.load(stream)
    if not isinstance(document, dict):
        raise SystemExit("not a JSON object: %s" % path)
    return document


def load_style(name: str) -> dict[str, Any]:
    style = load_json(STYLES_DIR / ("%s.json" % name))
    if style.get("schema") != STYLE_SCHEMA:
        raise SystemExit("unsupported style schema in %s" % name)
    return style


def load_concept(name: str) -> dict[str, Any]:
    concept = load_json(CONCEPTS_DIR / ("%s.json" % name))
    if concept.get("schema") != CONCEPT_SCHEMA:
        raise SystemExit("unsupported concept schema in %s" % name)
    if concept.get("kind") not in KIND_SHOTS:
        raise SystemExit("unsupported concept kind: %s" % concept.get("kind"))
    return concept


def concept_work_dir(concept_name: str) -> Path:
    return BUILD_DIR / concept_name


def retail_texture_entry(presentation: dict[str, Any], key: str) -> dict[str, Any]:
    entry = presentation.get("textures", {}).get(key)
    if not isinstance(entry, dict):
        raise SystemExit("key is not in the retail presentation manifest: %s" % key)
    return entry


def retail_texture_path(entry: dict[str, Any]) -> Path:
    return ROOT / str(entry.get("path", "")).replace("res://", "")


def load_layout_contracts() -> tuple[dict[str, Any], dict[str, Any]]:
    return (
        load_json(CONTENT_DIR / "sprite_frames.json"),
        load_json(CONTENT_DIR / "presentation.json"),
    )


# ---------------------------------------------------------------------------
# Image finishing (pure helpers, covered by tripo_pipeline_test.py)
# ---------------------------------------------------------------------------

def premultiplied_downscale(image: "Image.Image", target_width: int, target_height: int) -> "Image.Image":
    """Stepped box downscale in premultiplied alpha.

    Straight-alpha downscales bleed the (usually black) RGB of transparent
    pixels into edges; premultiplying first keeps edge colors clean. The
    unpremultiply loop only touches the final cell-sized image.
    """
    from PIL import ImageChops

    source = image.convert("RGBA")
    alpha = source.getchannel("A")
    rgb = Image.merge("RGB", source.split()[:3])
    premultiplied_rgb = ImageChops.multiply(rgb, Image.merge("RGB", (alpha, alpha, alpha)))
    working = Image.merge("RGBA", (*premultiplied_rgb.split(), alpha))
    while working.width >= target_width * 4 and working.height >= target_height * 4:
        working = working.resize(
            (max(1, working.width // 2), max(1, working.height // 2)), Image.BOX
        )
    working = working.resize((target_width, target_height), Image.BOX)
    pixels = list(working.getdata())
    restored = []
    for red, green, blue, alpha_value in pixels:
        if alpha_value <= 0:
            restored.append((0, 0, 0, 0))
            continue
        restored.append((
            min(255, (red * 255) // alpha_value),
            min(255, (green * 255) // alpha_value),
            min(255, (blue * 255) // alpha_value),
            alpha_value,
        ))
    result = Image.new("RGBA", (target_width, target_height))
    result.putdata(restored)
    return result


def threshold_alpha(image: "Image.Image", threshold: int) -> "Image.Image":
    """Binary alpha edges, matching the retail TGA sheets' hard cutouts."""
    result = image.convert("RGBA")
    alpha = result.getchannel("A").point(lambda value: 255 if value >= threshold else 0)
    result.putalpha(alpha)
    return result


def quantize_shared(frames: list["Image.Image"], colors: int, dither: bool) -> list["Image.Image"]:
    """Quantizes all frames of one shot against ONE shared palette so
    animation cannot flicker between per-frame palettes. colors <= 0 keeps
    full color (the Solstice rev-2 setting)."""
    if colors <= 0 or not frames:
        return frames
    strip = Image.new("RGB", (sum(f.width for f in frames), max(f.height for f in frames)))
    offset = 0
    for frame in frames:
        strip.paste(frame.convert("RGB"), (offset, 0))
        offset += frame.width
    palette_image = strip.quantize(colors=colors, method=Image.MEDIANCUT)
    dither_mode = Image.FLOYDSTEINBERG if dither else Image.NONE
    quantized: list[Image.Image] = []
    for frame in frames:
        rgba = frame.convert("RGBA")
        rgb_quantized = rgba.convert("RGB").quantize(palette=palette_image, dither=dither_mode)
        result = rgb_quantized.convert("RGBA")
        result.putalpha(rgba.getchannel("A"))
        quantized.append(result)
    return quantized


def _luminance(red: int, green: int, blue: int) -> float:
    return (0.2126 * red + 0.7152 * green + 0.0722 * blue) / 255.0


def _shift_hue_toward(hue: float, target: float, amount: float) -> float:
    delta = ((target - hue + 0.5) % 1.0) - 0.5
    return (hue + delta * amount) % 1.0


def stylize_palette(palette: list[int], colors: int, cfg: dict[str, Any]) -> list[int]:
    """Sea of Stars ramp treatment applied at the PALETTE level: shadows hue-
    shift toward indigo, highlights toward warm gold, saturation swells in the
    mids, and near-white pops to cream. Palette-level edits keep clusters flat."""
    import colorsys

    shadow_hue = float(cfg.get("shadow_hue_deg", 255.0)) / 360.0
    highlight_hue = float(cfg.get("highlight_hue_deg", 48.0)) / 360.0
    shadow_shift = float(cfg.get("shadow_shift", 0.22))
    highlight_shift = float(cfg.get("highlight_shift", 0.12))
    sat_boost = float(cfg.get("sat_boost", 1.35))
    result = list(palette)
    for index in range(colors):
        red, green, blue = palette[index * 3], palette[index * 3 + 1], palette[index * 3 + 2]
        hue, lightness, saturation = colorsys.rgb_to_hls(red / 255.0, green / 255.0, blue / 255.0)
        if lightness < 0.38:
            hue = _shift_hue_toward(hue, shadow_hue, shadow_shift)
            saturation = min(1.0, saturation * 1.15 + 0.08)
            lightness *= 0.92
        elif lightness > 0.82:
            hue = _shift_hue_toward(hue, highlight_hue, highlight_shift * 2.0)
            lightness = min(1.0, lightness * 1.06 + 0.04)
        else:
            hue = _shift_hue_toward(hue, highlight_hue, highlight_shift * 0.5)
            saturation = min(1.0, saturation * sat_boost)
            lightness = min(1.0, lightness * 1.05)
        red_f, green_f, blue_f = colorsys.hls_to_rgb(hue, lightness, saturation)
        result[index * 3] = int(round(red_f * 255))
        result[index * 3 + 1] = int(round(green_f * 255))
        result[index * 3 + 2] = int(round(blue_f * 255))
    return result


def majority_filter(indices: list[int], mask: list[bool], width: int, height: int) -> list[int]:
    """Kills isolated single pixels so shapes read as hand-placed clusters."""
    result = list(indices)
    for y in range(height):
        for x in range(width):
            position = y * width + x
            if not mask[position]:
                continue
            votes: dict[int, int] = {}
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    if dx == 0 and dy == 0:
                        continue
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < width and 0 <= ny < height and mask[ny * width + nx]:
                        neighbor = indices[ny * width + nx]
                        votes[neighbor] = votes.get(neighbor, 0) + 1
            if not votes:
                continue
            best_index, best_votes = max(votes.items(), key=lambda item: item[1])
            if best_index != indices[position] and best_votes >= 5:
                result[position] = best_index
    return result


def sprite_outline_color(image: "Image.Image", cfg: dict[str, Any]) -> tuple[int, int, int, int]:
    """A deep shade of the sprite's own hue, leaned toward indigo -- Sea of
    Stars outlines are colored darks, never plain black."""
    import colorsys

    hues: list[float] = []
    for red, green, blue, alpha in image.convert("RGBA").getdata():
        if alpha == 0:
            continue
        hue, lightness, saturation = colorsys.rgb_to_hls(red / 255.0, green / 255.0, blue / 255.0)
        if saturation > 0.2 and 0.2 < lightness < 0.8:
            hues.append(hue)
    base_hue = sorted(hues)[len(hues) // 2] if hues else 0.68
    outline_hue = _shift_hue_toward(base_hue, float(cfg.get("shadow_hue_deg", 255.0)) / 360.0, 0.45)
    red_f, green_f, blue_f = colorsys.hls_to_rgb(outline_hue, 0.16, 0.5)
    return (int(red_f * 255), int(green_f * 255), int(blue_f * 255), 255)


def edge_outline(image: "Image.Image", color: tuple[int, int, int, int]) -> "Image.Image":
    """Replaces silhouette-edge pixels with the outline color (the outline is
    part of the sprite, as drawn pixel art does it -- no growth, no clipping)."""
    source = image.convert("RGBA")
    pixels = source.load()
    result = source.copy()
    result_pixels = result.load()
    for y in range(source.height):
        for x in range(source.width):
            if pixels[x, y][3] == 0:
                continue
            for dx, dy in ((0, -1), (0, 1), (-1, 0), (1, 0)):
                nx, ny = x + dx, y + dy
                if not (0 <= nx < source.width and 0 <= ny < source.height) or pixels[nx, ny][3] == 0:
                    result_pixels[x, y] = color
                    break
    return result


def pixel_art_finish(
    frames: list["Image.Image"], cell: tuple[int, int], cfg: dict[str, Any]
) -> list["Image.Image"]:
    """The Sea of Stars pass: grade -> shared flat-cluster palette -> ramp
    hue-shifts -> isolated-pixel cleanup -> colored outline. Turns a downscaled
    render into something that reads as deliberate pixel art."""
    from PIL import ImageEnhance

    base_colors = int(cfg.get("base_colors", 14))
    graded: list[Image.Image] = []
    masks: list[list[bool]] = []
    for frame in frames:
        rgba = frame.convert("RGBA")
        mask = [alpha >= int(cfg.get("alpha_threshold", 96)) for alpha in rgba.getchannel("A").getdata()]
        rgb = rgba.convert("RGB")
        rgb = ImageEnhance.Brightness(rgb).enhance(float(cfg.get("brightness", 1.12)))
        rgb = ImageEnhance.Color(rgb).enhance(float(cfg.get("sat_boost", 1.35)))
        rgb = ImageEnhance.Contrast(rgb).enhance(float(cfg.get("contrast", 1.22)))
        graded.append(rgb)
        masks.append(mask)
    strip = Image.new("RGB", (sum(f.width for f in graded), max(f.height for f in graded)))
    offset = 0
    for frame in graded:
        strip.paste(frame, (offset, 0))
        offset += frame.width
    palette_source = strip.quantize(colors=base_colors + 2, method=Image.MEDIANCUT)
    styled = stylize_palette(palette_source.getpalette(), base_colors + 2, cfg)
    finished: list[Image.Image] = []
    outline_color: tuple[int, int, int, int] | None = None
    for frame, mask in zip(graded, masks):
        quantized = frame.quantize(palette=palette_source, dither=Image.NONE)
        indices = list(quantized.getdata())
        for _ in range(int(cfg.get("cleanup_passes", 2))):
            indices = majority_filter(indices, mask, frame.width, frame.height)
        quantized.putdata(indices)
        quantized.putpalette(styled)
        rgba = quantized.convert("RGBA")
        alpha = Image.new("L", frame.size)
        alpha.putdata([255 if opaque else 0 for opaque in mask])
        rgba.putalpha(alpha)
        if outline_color is None:
            outline_color = sprite_outline_color(rgba, cfg)
        finished.append(edge_outline(rgba, outline_color))
    return finished


def outline_sprite(image: "Image.Image", color: tuple[int, int, int, int]) -> "Image.Image":
    """1px ink ring on transparent pixels 4-adjacent to the silhouette."""
    source = image.convert("RGBA")
    pixels = source.load()
    result = source.copy()
    result_pixels = result.load()
    for y in range(source.height):
        for x in range(source.width):
            if pixels[x, y][3] > 0:
                continue
            for dx, dy in ((0, -1), (0, 1), (-1, 0), (1, 0)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < source.width and 0 <= ny < source.height and pixels[nx, ny][3] > 0:
                    result_pixels[x, y] = color
                    break
    return result


def alpha_mask(image: "Image.Image") -> list[bool]:
    return [pixel > 0 for pixel in image.convert("RGBA").getchannel("A").getdata()]


def luminance_fallback_mask(image: "Image.Image") -> list[bool]:
    return [pixel > 16 for pixel in image.convert("L").getdata()]


def silhouette_iou(candidate: "Image.Image", reference: "Image.Image") -> float:
    """Alpha-silhouette IoU between a finished cell and its retail frame.

    Retail sheets without a usable alpha channel (fully opaque TGAs) fall
    back to a luminance mask. Low IoU means the new art drifts from the
    frozen .hma hitbox silhouette and will feel unfair in play.
    """
    if candidate.size != reference.size:
        reference = reference.resize(candidate.size, Image.NEAREST)
    candidate_mask = alpha_mask(candidate)
    reference_mask = alpha_mask(reference)
    if not any(reference_mask):
        reference_mask = luminance_fallback_mask(reference)
    intersection = sum(1 for a, b in zip(candidate_mask, reference_mask) if a and b)
    union = sum(1 for a, b in zip(candidate_mask, reference_mask) if a or b)
    return (intersection / union) if union else 0.0


def hue_rotate(image: "Image.Image", degrees: float) -> "Image.Image":
    """Recolor variants (retail's _gul/_raud/_blue... sheets) are hue-mapped
    copies, not fresh generations."""
    source = image.convert("RGBA")
    alpha = source.getchannel("A")
    hsv = source.convert("RGB").convert("HSV")
    hue, saturation, value = hsv.split()
    shift = int(round(degrees / 360.0 * 255.0)) % 255
    rotated = hue.point(lambda channel_value: (channel_value + shift) % 255)
    recolored = Image.merge("HSV", (rotated, saturation, value)).convert("RGB").convert("RGBA")
    recolored.putalpha(alpha)
    return recolored


def dominant_glow_color(image: "Image.Image") -> tuple[int, int, int]:
    """Brightest saturated color of a sprite -- used to tint its shot orb."""
    best = (255, 200, 90)
    best_score = -1.0
    small = image.convert("RGBA").resize((32, 32), Image.BOX)
    for red, green, blue, alpha_value in small.getdata():
        if alpha_value < 128:
            continue
        brightness = red + green + blue
        saturation = max(red, green, blue) - min(red, green, blue)
        score = brightness + saturation * 2.0
        if score > best_score:
            best_score = score
            best = (red, green, blue)
    return best


def draw_shot_orb(size: int, color: tuple[int, int, int], radius: float) -> "Image.Image":
    """A glowing energy bolt for the enemy-shot cells: BANDED like drawn pixel
    art (cream core, bright band, deep rim) rather than a smooth gradient."""
    core_band = (
        min(255, color[0] + 170),
        min(255, color[1] + 170),
        min(255, color[2] + 150),
        255,
    )
    bright_band = (
        min(255, int(color[0] * 1.1)),
        min(255, int(color[1] * 1.1)),
        min(255, int(color[2] * 1.1)),
        255,
    )
    rim_band = (int(color[0] * 0.45), int(color[1] * 0.45), int(color[2] * 0.55), 255)
    orb = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    pixels = orb.load()
    center = (size - 1) / 2.0
    for y in range(size):
        for x in range(size):
            distance = math.hypot(x - center, y - center)
            if distance > radius:
                continue
            if distance <= radius * 0.45:
                pixels[x, y] = core_band
            elif distance <= radius * 0.8:
                pixels[x, y] = bright_band
            else:
                pixels[x, y] = rim_band
    return orb


# ---------------------------------------------------------------------------
# Sheet composition against the frozen retail geometry
# ---------------------------------------------------------------------------

def family_rects(sprite_frames: dict[str, Any], family: str) -> list[dict[str, int]]:
    families = sprite_frames.get("enemy_frame_layout", {}).get("families", {})
    frames = families.get(family, {}).get("frames", [])
    ordered = sorted(frames, key=lambda frame: int(frame.get("frame_index", 0)))
    return [frame["source_rect"] for frame in ordered]


def fighter_frames(sprite_frames: dict[str, Any], fighter_id: str) -> dict[str, Any]:
    for sheet in sprite_frames.get("fighter_sheets", []):
        if sheet.get("id") == fighter_id:
            return sheet
    raise SystemExit("fighter sheet is not in sprite_frames.json: %s" % fighter_id)


def paste_frames(
    canvas: "Image.Image", frames: list["Image.Image"], rects: list[dict[str, int]]
) -> None:
    for index, rect in enumerate(rects):
        if index >= len(frames):
            break
        frame = frames[index]
        if frame.size != (int(rect["width"]), int(rect["height"])):
            raise SystemExit(
                "frame %d is %dx%d but its slot is %dx%d"
                % (index, frame.width, frame.height, int(rect["width"]), int(rect["height"]))
            )
        canvas.paste(frame, (int(rect["x"]), int(rect["y"])), frame)


def compose_enemy_sheet(
    sprite_frames: dict[str, Any],
    presentation: dict[str, Any],
    shots: dict[str, list["Image.Image"]],
) -> "Image.Image":
    canvas = Image.new("RGBA", (576, 96), (0, 0, 0, 0))
    paste_frames(canvas, shots.get("directional", []), family_rects(sprite_frames, "directional_32"))
    paste_frames(canvas, shots.get("formation", []), family_rects(sprite_frames, "formation_animation_32"))
    paste_frames(canvas, shots.get("large", []), family_rects(sprite_frames, "supplemental_large_animation_64"))
    shot_rects = presentation.get("projectile_sheets", {}).get("enemy_projectiles", {}).get(
        "source_rects", []
    )
    directional = shots.get("directional", [])
    glow = dominant_glow_color(directional[0]) if directional else (255, 200, 90)
    for index, rect in enumerate(shot_rects):
        x, y, width, height = (int(value) for value in rect)
        orb = draw_shot_orb(min(width, height), glow, 9.0 if index == 0 else 12.0)
        canvas.paste(orb, (x, y), orb)
        # The renderer reads a 448-column variant for one enemy type; mirror
        # the orb there so both source columns are always populated.
        mirrored_x = x - 32
        if mirrored_x >= 448:
            canvas.paste(orb, (mirrored_x, y), orb)
    return canvas


def compose_fighter_sheet(
    sprite_frames: dict[str, Any], fighter_id: str, frames: list["Image.Image"]
) -> "Image.Image":
    sheet = fighter_frames(sprite_frames, fighter_id)
    width = int(sheet.get("sheet_width", 440))
    height = int(sheet.get("sheet_storage_height", 28))
    canvas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    rects = [frame["source_rect"] for frame in sheet.get("frames", [])]
    paste_frames(canvas, frames, rects)
    return canvas


def derive_mask_sheet(sheet: "Image.Image") -> "Image.Image":
    """Boss hit-flash sheets (<name>_mask) are white silhouettes."""
    mask = Image.new("RGBA", sheet.size, (0, 0, 0, 0))
    alpha = sheet.convert("RGBA").getchannel("A")
    white = Image.new("RGBA", sheet.size, (255, 255, 255, 255))
    mask.paste(white, (0, 0), alpha)
    return mask


def contact_sheet(sheets: dict[str, "Image.Image"], scale: int = 3) -> "Image.Image":
    if not sheets:
        return Image.new("RGBA", (8, 8), (0, 0, 0, 255))
    gap = 8
    width = max(image.width for image in sheets.values()) * scale + gap * 2
    height = sum(image.height * scale + gap for image in sheets.values()) + gap
    board = Image.new("RGBA", (width, height), (10, 12, 23, 255))
    y = gap
    for key in sorted(sheets):
        scaled = sheets[key].resize(
            (sheets[key].width * scale, sheets[key].height * scale), Image.NEAREST
        )
        board.paste(scaled, (gap, y), scaled)
        y += scaled.height + gap
    return board


# ---------------------------------------------------------------------------
# Procedural sheets (weapons / pickups / explosion) -- drawn energy shapes in
# the same banded, outlined pixel language as the finished renders.
# ---------------------------------------------------------------------------

def _bands(color: tuple[int, int, int]) -> dict[str, tuple[int, int, int, int]]:
    return {
        "core": (
            min(255, color[0] + 170), min(255, color[1] + 170), min(255, color[2] + 150), 255,
        ),
        "bright": (color[0], color[1], color[2], 255),
        "deep": (int(color[0] * 0.55), int(color[1] * 0.55), int(color[2] * 0.62), 255),
        "rim": SOLSTICE_INK,
    }


def paint_bolt(canvas: "Image.Image", x: int, y: int, width: int, height: int, color: tuple[int, int, int]) -> None:
    """One weapon slot: thin slots become beams, tall slots become comets with
    an orb head, everything else a banded capsule. Deterministic, no rng."""
    bands = _bands(color)
    pixels = canvas.load()
    center_x = (width - 1) / 2.0
    aspect = height / max(1, width)
    orb_height = min(width, height) if aspect >= 2.2 else height
    for py in range(height):
        for px in range(width):
            dx = abs(px - center_x) / max(0.5, width / 2.0)
            if aspect >= 2.2 and py > orb_height:
                # trail: narrows toward the bottom
                taper = 1.0 - 0.6 * ((py - orb_height) / max(1, height - orb_height))
                if dx > taper:
                    continue
                band = "core" if dx < taper * 0.35 else ("bright" if dx < taper * 0.75 else "deep")
            else:
                # head / capsule: rounded ends
                tip = min(py, height - 1 - py) if aspect < 2.2 else min(py, max(0, orb_height - py))
                roundness = min(1.0, (tip + 1.5) / (min(width, height) / 2.0 + 0.5))
                if dx > roundness:
                    continue
                band = "core" if dx < roundness * 0.4 else ("bright" if dx < roundness * 0.8 else "deep")
            pixels[x + px, y + py] = bands[band]
    if width >= 6:
        for py in range(height):
            for px in range(width):
                if pixels[x + px, y + py][3] == 0:
                    continue
                edge = False
                for dx_offset, dy_offset in ((0, -1), (0, 1), (-1, 0), (1, 0)):
                    nx, ny = px + dx_offset, py + dy_offset
                    if not (0 <= nx < width and 0 <= ny < height) or pixels[x + nx, y + ny][3] == 0:
                        edge = True
                        break
                if edge:
                    pixels[x + px, y + py] = bands["rim"]


def compose_weapons_sheet(sprite_frames: dict[str, Any]) -> "Image.Image":
    sheet_meta = sprite_frames.get("projectile_sheet", {})
    canvas = Image.new(
        "RGBA",
        (int(sheet_meta.get("sheet_width", 672)), int(sheet_meta.get("sheet_height", 100))),
        (0, 0, 0, 0),
    )
    painted: set[tuple[int, int]] = set()
    for frame in sheet_meta.get("frames", []):
        rect = frame.get("source_rect", {})
        key = (int(rect.get("x", 0)), int(rect.get("y", 0)))
        if key in painted:
            continue
        painted.add(key)
        weapon_ids = frame.get("weapon_ids", [])
        color = WEAPON_COLORS.get(int(weapon_ids[0]) if weapon_ids else 0, (255, 195, 87))
        paint_bolt(canvas, key[0], key[1], int(rect.get("width", 4)), int(rect.get("height", 10)), color)
    return canvas


def paint_token(canvas: "Image.Image", x: int, y: int, size: int, phase: float, color: tuple[int, int, int], glyph: str) -> None:
    """A spinning jeweled token: gold ring, colored face, optional glyph.
    The spin is a horizontal squash cycle, like every coin flip ever drawn."""
    bands = _bands(color)
    gold = (255, 195, 87, 255)
    gold_deep = (163, 84, 31, 255)
    pixels = canvas.load()
    center = (size - 1) / 2.0
    width_factor = abs(math.cos(phase))
    half_width = max(1.5, (size / 2.0 - 1.5) * width_factor)
    half_height = size / 2.0 - 1.5
    for py in range(size):
        for px in range(size):
            dx = (px - center) / half_width
            dy = (py - center) / half_height
            distance = dx * dx + dy * dy
            if distance > 1.0:
                continue
            if distance > 0.62:
                pixels[x + px, y + py] = gold if (px + py) % 2 == 0 or width_factor < 0.5 else gold_deep
            else:
                pixels[x + px, y + py] = bands["bright"] if distance > 0.2 else bands["core"]
    for py in range(size):
        for px in range(size):
            if pixels[x + px, y + py][3] == 0:
                continue
            edge = False
            for dx_offset, dy_offset in ((0, -1), (0, 1), (-1, 0), (1, 0)):
                nx, ny = px + dx_offset, py + dy_offset
                if not (0 <= nx < size and 0 <= ny < size) or pixels[x + nx, y + ny][3] == 0:
                    edge = True
                    break
            if edge:
                pixels[x + px, y + py] = SOLSTICE_INK
    if glyph and width_factor > 0.55 and glyph in GLYPH_3X5:
        rows = GLYPH_3X5[glyph]
        glyph_x = x + (size - 3) // 2
        glyph_y = y + (size - 5) // 2
        for row_index, row in enumerate(rows):
            for column_index, cell in enumerate(row):
                if cell == "#":
                    pixels[glyph_x + column_index, glyph_y + row_index] = (26, 18, 8, 255)


def compose_pickups_sheet(bonuses_document: dict[str, Any], presentation: dict[str, Any]) -> "Image.Image":
    entry = retail_texture_entry(presentation, "bonuses")
    canvas = Image.new("RGBA", (int(entry["width"]), int(entry["height"])), (0, 0, 0, 0))
    for bonus in bonuses_document.get("bonuses", []):
        effect_key = str(bonus.get("effect_key", ""))
        color = PICKUP_COLORS.get(effect_key, (141, 79, 230))
        glyph = PICKUP_GLYPHS.get(effect_key, "")
        source_y = int(bonus.get("source_y", 0))
        frame_count = int(bonus.get("frame_count", 10))
        width = int(bonus.get("width", 20))
        for frame_index in range(frame_count):
            paint_token(
                canvas,
                int(bonus.get("source_x", 0)) + frame_index * width,
                source_y,
                width,
                math.pi * frame_index / float(frame_count),
                color,
                glyph,
            )
    return canvas


def compose_explosion_sheet(presentation: dict[str, Any]) -> "Image.Image":
    """13 banded frames: gold-white flash core swelling, magenta bloom ring,
    dissolving ember clusters. Deterministic layout, no rng."""
    meta = presentation.get("effects", {}).get("small_explosion", {})
    entry = retail_texture_entry(presentation, str(meta.get("texture", "expl_small")))
    canvas = Image.new("RGBA", (int(entry["width"]), int(entry["height"])), (0, 0, 0, 0))
    columns = int(meta.get("columns", 5))
    frame_width, frame_height = (int(value) for value in meta.get("frame_size", [32, 32]))
    frame_count = int(meta.get("frame_count", 13))
    pixels = canvas.load()
    cream = (255, 243, 214, 255)
    gold = (255, 195, 87, 255)
    ember = (255, 122, 47, 255)
    magenta = (255, 93, 162, 255)
    deep = (143, 36, 86, 255)
    for frame_index in range(frame_count):
        origin_x = (frame_index % columns) * frame_width
        origin_y = (frame_index // columns) * frame_height
        progress = frame_index / float(frame_count - 1)
        center = (frame_width - 1) / 2.0
        core_radius = 13.0 * (progress * 2.0) if progress < 0.5 else 13.0 * (1.0 - (progress - 0.5) * 1.6)
        ring_radius = 15.0 * progress
        for py in range(frame_height):
            for px in range(frame_width):
                distance = math.hypot(px - center, py - center)
                value = None
                if distance <= max(0.0, core_radius * 0.5):
                    value = cream
                elif distance <= core_radius:
                    value = gold if progress < 0.6 else ember
                elif progress > 0.3 and abs(distance - ring_radius) <= (2.5 if progress < 0.75 else 1.5):
                    value = magenta if progress < 0.8 else deep
                if value is not None:
                    # dissolve: drop pixels in a fixed checker as the burst dies
                    if progress > 0.7 and (px + py * 3 + frame_index) % 3 == 0:
                        continue
                    pixels[origin_x + px, origin_y + py] = value
    return canvas


# ---------------------------------------------------------------------------
# Pack manifest
# ---------------------------------------------------------------------------

def pack_dir(pack_name: str) -> Path:
    return PACKS_ROOT / pack_name


def load_pack_manifest(pack_name: str) -> dict[str, Any]:
    manifest_path = pack_dir(pack_name) / "pack.json"
    if manifest_path.exists():
        manifest = load_json(manifest_path)
        if manifest.get("schema") != PACK_SCHEMA:
            raise SystemExit("existing pack has an unsupported schema: %s" % manifest_path)
        return manifest
    return {
        "version": 1,
        "schema": PACK_SCHEMA,
        "name": pack_name,
        "display_name": pack_name.upper(),
        "generator": {"tool": "tripo_pipeline.py"},
        "textures": {},
    }


def upsert_pack_entries(
    pack_name: str, entries: dict[str, dict[str, Any]]
) -> Path:
    manifest = load_pack_manifest(pack_name)
    textures = manifest.setdefault("textures", {})
    for key, entry in entries.items():
        previous = textures.get(key, {})
        if isinstance(previous, dict) and "created_utc" in previous.get("source", {}):
            entry.setdefault("source", {}).setdefault(
                "created_utc", previous["source"]["created_utc"]
            )
        textures[key] = entry
    manifest_path = pack_dir(pack_name) / "pack.json"
    write_json_atomic(manifest_path, manifest)
    return manifest_path


# ---------------------------------------------------------------------------
# Tripo API (text prompts only -- retail rasters are never uploaded)
# ---------------------------------------------------------------------------

def api_key() -> str:
    key = os.environ.get("TRIPO_API_KEY", "").strip()
    if key:
        return key
    if API_KEY_FILE.exists():
        key = API_KEY_FILE.read_text(encoding="utf-8").strip()
        if key:
            return key
    raise SystemExit(
        "no Tripo API key: set TRIPO_API_KEY or write it to %s (chmod 600)" % API_KEY_FILE
    )


def api_request(path: str, payload: dict[str, Any] | None = None) -> dict[str, Any]:
    request = urllib.request.Request(
        "%s%s" % (API_BASE, path),
        data=json.dumps(payload).encode("utf-8") if payload is not None else None,
        headers={
            "Authorization": "Bearer %s" % api_key(),
            "Content-Type": "application/json",
            # Cloudflare in front of the API rejects urllib's default agent
            # signature (error 1010); identify as a regular HTTP client.
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) warblade-sprite-pipeline/1.0",
            "Accept": "application/json",
        },
        method="POST" if payload is not None else "GET",
    )
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            document = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        raise SystemExit(
            "Tripo API %s failed: HTTP %d %s" % (path, error.code, error.read().decode("utf-8", "replace")[:400])
        )
    if int(document.get("code", -1)) != 0:
        raise SystemExit("Tripo API %s failed: %s" % (path, json.dumps(document)[:400]))
    return document.get("data", {})


def download_file(url: str, destination: Path) -> None:
    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) warblade-sprite-pipeline/1.0",
        },
    )
    with urllib.request.urlopen(request, timeout=300) as response:
        write_bytes_atomic(destination, response.read())


def generation_cache_key(prompt: str, negative_prompt: str, seed: int, model_version: str) -> str:
    digest = hashlib.sha256()
    digest.update(
        ("%s|%s|%d|%s" % (prompt, negative_prompt, seed, model_version)).encode("utf-8")
    )
    return digest.hexdigest()


def build_prompt(style: dict[str, Any], concept: dict[str, Any]) -> str:
    return "%s, %s" % (str(concept.get("prompt_subject", "")).strip(), str(style.get("prompt_suffix", "")).strip())


def cmd_gen(args: argparse.Namespace) -> int:
    concept = load_concept(args.concept)
    if str(concept.get("kind", "")).startswith("procedural"):
        print("%s is procedural -- nothing to generate" % args.concept)
        return 0
    style = load_style(str(concept.get("style", "solstice")))
    work = concept_work_dir(args.concept)
    prompt = build_prompt(style, concept)
    negative = str(style.get("negative_prompt", ""))
    seed = int(concept.get("texture_seed", 0))
    model_version = str(style.get("model_version", "v2.5"))
    cache_key = generation_cache_key(prompt, negative, seed, model_version)
    meta_path = work / "meta.json"
    model_path = work / "model.glb"
    if model_path.exists() and meta_path.exists() and not args.force:
        meta = load_json(meta_path)
        if meta.get("cache_key") == cache_key:
            print("cached: %s (task %s)" % (model_path, meta.get("task_id", "?")))
            return 0
        print(
            "prompt/seed changed for %s -- rerun with --force to spend credits on a new "
            "generation" % args.concept,
            file=sys.stderr,
        )
        return 1
    payload = {
        "type": "text_to_model",
        "prompt": prompt,
        "negative_prompt": negative,
        "texture_seed": seed,
    }
    # "default" lets the service pick its current model; explicit values must
    # be full version strings (e.g. "v2.5-20250123") or the API rejects them.
    if model_version and model_version != "default":
        payload["model_version"] = model_version
    print("submitting text_to_model for %s (seed %d)..." % (args.concept, seed))
    task = api_request("/task", payload)
    task_id = str(task.get("task_id", ""))
    if not task_id:
        raise SystemExit("Tripo did not return a task id: %s" % json.dumps(task)[:200])
    print("task %s queued; polling..." % task_id)
    deadline = time.time() + POLL_TIMEOUT_SECONDS
    status = ""
    result: dict[str, Any] = {}
    while time.time() < deadline:
        result = api_request("/task/%s" % task_id)
        status = str(result.get("status", ""))
        if status in ("success", "failed", "cancelled", "banned", "expired"):
            break
        print("  %s... (%d%%)" % (status, int(result.get("progress", 0))))
        time.sleep(POLL_INTERVAL_SECONDS)
    if status != "success":
        raise SystemExit("Tripo task %s ended as %s" % (task_id, status or "timeout"))
    output = result.get("output", {})
    model_url = str(output.get("pbr_model") or output.get("model") or "")
    if not model_url:
        raise SystemExit("Tripo task %s has no model url: %s" % (task_id, json.dumps(output)[:300]))
    print("downloading model...")
    download_file(model_url, model_path)
    preview_url = str(output.get("rendered_image") or "")
    if preview_url:
        download_file(preview_url, work / "preview_tripo.png")
    write_json_atomic(meta_path, {
        "cache_key": cache_key,
        "task_id": task_id,
        "prompt": prompt,
        "negative_prompt": negative,
        "texture_seed": seed,
        "model_version": model_version,
    })
    print("model: %s" % model_path)
    return 0


# ---------------------------------------------------------------------------
# Render (drives the windowed Godot tool)
# ---------------------------------------------------------------------------

def build_render_job(
    concept_name: str, concept: dict[str, Any], style: dict[str, Any], glb_override: str = ""
) -> dict[str, Any]:
    work = concept_work_dir(concept_name)
    shots = []
    for shot in KIND_SHOTS[str(concept.get("kind"))]:
        entry = {key: value for key, value in shot.items() if key != "cell"}
        shots.append(entry)
    return {
        "version": 1,
        "schema": RENDER_JOB_SCHEMA,
        "glb": glb_override or str(work / "model.glb"),
        "out_dir": str(work / "frames"),
        "render_size": int(style.get("render_size", 512)),
        "msaa": int(style.get("msaa", 4)),
        "light_rig": str(style.get("light_rig", "key_fill_rim")),
        "camera": {
            "pitch_degrees": float(style.get("camera", {}).get("pitch_degrees", 75.0)),
            "framing_margin": float(style.get("camera", {}).get("framing_margin", 1.12)),
        },
        "model": {
            "yaw_offset_degrees": float(concept.get("yaw_offset_degrees", 0.0)),
            "clockwise": bool(concept.get("clockwise", True)),
            "model_rotation_degrees": list(concept.get("model_rotation_degrees", [0.0, 0.0, 0.0])),
            "recenter": True,
        },
        "shots": shots,
    }


def cmd_render(args: argparse.Namespace) -> int:
    concept = load_concept(args.concept)
    if str(concept.get("kind", "")).startswith("procedural"):
        print("%s is procedural -- nothing to render" % args.concept)
        return 0
    style = load_style(str(concept.get("style", "solstice")))
    work = concept_work_dir(args.concept)
    job = build_render_job(args.concept, concept, style, glb_override=args.glb)
    if not args.glb and not Path(job["glb"]).exists():
        return fail("no model.glb for %s -- run gen first (or pass --glb)" % args.concept)
    job_path = work / "job.json"
    write_json_atomic(job_path, job)
    godot = os.environ.get("GODOT", "godot")
    command = [
        godot,
        "--path", str(ROOT),
        "--script", RENDER_CLI,
        "--", "--job=%s" % job_path,
    ]
    print("rendering via %s..." % " ".join(command))
    completed = subprocess.run(command, capture_output=not args.verbose)
    report_path = work / "frames" / "render_report.json"
    if completed.returncode != 0 or not report_path.exists():
        if completed.stdout:
            sys.stderr.write(completed.stdout.decode("utf-8", "replace")[-2000:])
        if completed.stderr:
            sys.stderr.write(completed.stderr.decode("utf-8", "replace")[-2000:])
        return fail("render tool failed (exit %d)" % completed.returncode)
    report = load_json(report_path)
    if not bool(report.get("ok", False)):
        return fail("render report is not ok: %s" % json.dumps(report)[:400])
    for shot in job["shots"]:
        expected = int(shot.get("frames", 1))
        produced = len(list((work / "frames" / str(shot["id"])).glob("frame_*.png")))
        if produced != expected:
            return fail("shot %s produced %d/%d frames" % (shot["id"], produced, expected))
    print("frames: %s" % (work / "frames"))
    return 0


# ---------------------------------------------------------------------------
# Post
# ---------------------------------------------------------------------------

def union_crop(frames: list["Image.Image"], pad_ratio: float = 0.03) -> list["Image.Image"]:
    """Tight-crops every frame of a shot to the UNION of their alpha boxes.

    Retail sprites fill their cells; rendering leaves framing margin around
    the model, so without this crop sprites land undersized and squished.
    One shared box across the whole shot keeps animation registration stable.
    """
    boxes = [frame.getbbox() for frame in frames]
    boxes = [box for box in boxes if box is not None]
    if not boxes:
        return frames
    left = min(box[0] for box in boxes)
    top = min(box[1] for box in boxes)
    right = max(box[2] for box in boxes)
    bottom = max(box[3] for box in boxes)
    pad = int(max(right - left, bottom - top) * pad_ratio) + 1
    left = max(0, left - pad)
    top = max(0, top - pad)
    right = min(frames[0].width, right + pad)
    bottom = min(frames[0].height, bottom + pad)
    return [frame.crop((left, top, right, bottom)) for frame in frames]


def finish_shot_frames(
    frames: list["Image.Image"],
    cell: tuple[int, int],
    style: dict[str, Any],
) -> list["Image.Image"]:
    frames = union_crop(frames)
    downscaled = [premultiplied_downscale(frame, cell[0], cell[1]) for frame in frames]
    pixel_art = style.get("pixel_art", {})
    if bool(pixel_art.get("enabled", False)):
        cfg = dict(pixel_art)
        cfg.setdefault("alpha_threshold", int(style.get("alpha_threshold", 96)))
        return pixel_art_finish(downscaled, cell, cfg)
    threshold = int(style.get("alpha_threshold", 96))
    finished = [threshold_alpha(frame, threshold) for frame in downscaled]
    finished = quantize_shared(
        finished, int(style.get("palette_colors", 0)), bool(style.get("dither", False))
    )
    outline = style.get("outline", {})
    if bool(outline.get("enabled", False)):
        color_hex = str(outline.get("color", "#131530")).lstrip("#")
        color = tuple(int(color_hex[i:i + 2], 16) for i in (0, 2, 4)) + (255,)
        finished = [outline_sprite(frame, color) for frame in finished]
    return finished


def cmd_post(args: argparse.Namespace) -> int:
    require_pillow()
    concept = load_concept(args.concept)
    if str(concept.get("kind", "")).startswith("procedural"):
        print("%s is procedural -- nothing to post" % args.concept)
        return 0
    style = load_style(str(concept.get("style", "solstice")))
    work = concept_work_dir(args.concept)
    sprite_frames, presentation = load_layout_contracts()
    any_shot = False
    for shot in KIND_SHOTS[str(concept.get("kind"))]:
        shot_dir = work / "frames" / str(shot["id"])
        frame_paths = sorted(shot_dir.glob("frame_*.png"))
        if not frame_paths:
            continue
        any_shot = True
        frames = [Image.open(path).convert("RGBA") for path in frame_paths]
        finished = finish_shot_frames(frames, tuple(shot["cell"]), style)
        out_dir = work / "post" / str(shot["id"])
        out_dir.mkdir(parents=True, exist_ok=True)
        for index, frame in enumerate(finished):
            buffer = tempfile.SpooledTemporaryFile()
            frame.save(buffer, format="PNG")
            buffer.seek(0)
            write_bytes_atomic(out_dir / ("frame_%02d.png" % index), buffer.read())
        iou_report = report_shot_iou(
            concept, shot, finished, sprite_frames, presentation, float(style.get("iou_warn_threshold", 0.5))
        )
        print("post %s/%s: %d frames%s" % (args.concept, shot["id"], len(finished), iou_report))
    if not any_shot:
        return fail("no rendered frames for %s -- run render first" % args.concept)
    return 0


def report_shot_iou(
    concept: dict[str, Any],
    shot: dict[str, Any],
    frames: list["Image.Image"],
    sprite_frames: dict[str, Any],
    presentation: dict[str, Any],
    warn_threshold: float,
) -> str:
    """IoU vs the retail frames the pack will replace (first texture key)."""
    keys = concept.get("texture_keys", [])
    if not keys:
        return ""
    entry = presentation.get("textures", {}).get(str(keys[0]))
    if not isinstance(entry, dict):
        return ""
    retail_path = retail_texture_path(entry)
    if not retail_path.exists():
        return ""
    retail_sheet = Image.open(retail_path).convert("RGBA")
    kind = str(concept.get("kind"))
    if kind == "enemy_sheet":
        rect_lookup = {
            "directional": family_rects(sprite_frames, "directional_32"),
            "formation": family_rects(sprite_frames, "formation_animation_32"),
            "large": family_rects(sprite_frames, "supplemental_large_animation_64"),
        }
        rects = rect_lookup.get(str(shot["id"]), [])
    elif kind == "fighter":
        rects = [frame["source_rect"] for frame in fighter_frames(sprite_frames, str(keys[0])).get("frames", [])]
    else:
        return ""
    if not rects:
        return ""
    worst = 1.0
    compared = 0
    for index, frame in enumerate(frames[: len(rects)]):
        rect = rects[index]
        reference = retail_sheet.crop((
            int(rect["x"]),
            int(rect["y"]),
            int(rect["x"]) + int(rect["width"]),
            int(rect["y"]) + int(rect["height"]),
        ))
        reference_mask = alpha_mask(reference)
        if not any(reference_mask):
            reference_mask = luminance_fallback_mask(reference)
        if not any(reference_mask):
            # Retail leaves this frame empty (an unused family for this
            # sheet); nothing to compare against.
            continue
        compared += 1
        worst = min(worst, silhouette_iou(frame, reference))
    if compared == 0:
        return ", no retail frames to compare (family unused by this sheet)"
    marker = "  [!] below %.2f -- silhouette drifts from the frozen hitbox" % warn_threshold
    return ", worst silhouette IoU %.2f%s" % (worst, marker if worst < warn_threshold else "")


# ---------------------------------------------------------------------------
# Sheet
# ---------------------------------------------------------------------------

def load_post_frames(work: Path, shot_id: str) -> list["Image.Image"]:
    return [
        Image.open(path).convert("RGBA")
        for path in sorted((work / "post" / shot_id).glob("frame_*.png"))
    ]


def cmd_sheet(args: argparse.Namespace) -> int:
    require_pillow()
    concept = load_concept(args.concept)
    work = concept_work_dir(args.concept)
    sprite_frames, presentation = load_layout_contracts()
    kind = str(concept.get("kind"))
    keys = [str(key) for key in concept.get("texture_keys", [])]
    if not keys:
        return fail("concept %s declares no texture_keys" % args.concept)

    sheets: dict[str, Image.Image] = {}
    if kind == "enemy_sheet":
        shots = {
            "directional": load_post_frames(work, "directional"),
            "formation": load_post_frames(work, "formation"),
            "large": load_post_frames(work, "large"),
        }
        if not shots["directional"]:
            return fail("no post frames for %s -- run post first" % args.concept)
        sheets[keys[0]] = compose_enemy_sheet(sprite_frames, presentation, shots)
    elif kind == "fighter":
        frames = load_post_frames(work, "banking")
        if not frames:
            return fail("no post frames for %s -- run post first" % args.concept)
        sheets[keys[0]] = compose_fighter_sheet(sprite_frames, keys[0], frames)
    elif kind == "procedural_weapons":
        sheets[keys[0]] = compose_weapons_sheet(sprite_frames)
    elif kind == "procedural_pickups":
        sheets[keys[0]] = compose_pickups_sheet(load_json(CONTENT_DIR / "bonuses.json"), presentation)
    elif kind == "procedural_explosion":
        sheets[keys[0]] = compose_explosion_sheet(presentation)
    else:
        return fail("sheet composition for kind %s is not implemented yet" % kind)

    base_sheet = sheets[keys[0]]
    for variant_key, variant in dict(concept.get("recolor_variants", {})).items():
        sheets[str(variant_key)] = hue_rotate(
            base_sheet, float(dict(variant).get("hue_shift_degrees", 0.0))
        )
    for mask_key in concept.get("masks", []):
        source_key = str(mask_key).removesuffix("_mask")
        if source_key in sheets:
            sheets[str(mask_key)] = derive_mask_sheet(sheets[source_key])

    meta = load_json(work / "meta.json") if (work / "meta.json").exists() else {}
    entries: dict[str, dict[str, Any]] = {}
    for key, sheet in sheets.items():
        entry = retail_texture_entry(presentation, key)
        expected = (int(entry.get("width", 0)), int(entry.get("height", 0)))
        if sheet.size != expected:
            return fail(
                "composed sheet %s is %dx%d but retail expects %dx%d"
                % (key, sheet.width, sheet.height, expected[0], expected[1])
            )
        relative = "textures/%s.png" % key
        destination = pack_dir(args.pack) / relative
        buffer = tempfile.SpooledTemporaryFile()
        sheet.save(buffer, format="PNG")
        buffer.seek(0)
        write_bytes_atomic(destination, buffer.read())
        entries[key] = {
            "path": relative,
            "width": sheet.width,
            "height": sheet.height,
            "source": {
                "concept": args.concept,
                "style": str(concept.get("style", "")),
                "prompt": str(meta.get("prompt", "")),
                "texture_seed": int(meta.get("texture_seed", 0)),
                "tripo_task_id": str(meta.get("task_id", "")),
                "created_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            },
        }
    manifest_path = upsert_pack_entries(args.pack, entries)
    preview = contact_sheet(sheets)
    buffer = tempfile.SpooledTemporaryFile()
    preview.save(buffer, format="PNG")
    buffer.seek(0)
    write_bytes_atomic(work / "preview.png", buffer.read())
    print("pack %s <- %s (%s)" % (args.pack, ", ".join(sorted(sheets)), manifest_path))
    print("preview: %s" % (work / "preview.png"))
    return 0


# ---------------------------------------------------------------------------
# Validate
# ---------------------------------------------------------------------------

def cmd_validate(args: argparse.Namespace) -> int:
    require_pillow()
    directory = pack_dir(args.pack)
    manifest_path = directory / "pack.json"
    if not manifest_path.exists():
        return fail("pack has no manifest: %s" % manifest_path)
    manifest = load_json(manifest_path)
    errors: list[str] = []
    if manifest.get("schema") != PACK_SCHEMA or int(manifest.get("version", 0)) != 1:
        errors.append("unsupported pack schema/version")
    _, presentation = load_layout_contracts()
    textures = manifest.get("textures", {})
    overridden = 0
    for key, entry in sorted(textures.items()):
        if not isinstance(entry, dict):
            errors.append("entry is not an object: %s" % key)
            continue
        retail = presentation.get("textures", {}).get(key)
        if not isinstance(retail, dict):
            errors.append("pack key is not a retail texture: %s" % key)
            continue
        if str(retail.get("kind", "texture")) != "texture":
            errors.append("pack key targets a non-texture entry: %s" % key)
            continue
        relative = str(entry.get("path", ""))
        if not relative or relative.startswith("/") or ".." in relative:
            errors.append("entry path is invalid: %s" % key)
            continue
        image_path = directory / relative
        if not image_path.exists():
            errors.append("entry file is missing: %s" % key)
            continue
        with Image.open(image_path) as image:
            size = image.size
        expected = (int(retail.get("width", 0)), int(retail.get("height", 0)))
        if size != expected:
            errors.append(
                "entry %s is %dx%d but retail expects %dx%d"
                % (key, size[0], size[1], expected[0], expected[1])
            )
            continue
        overridden += 1
    report = {
        "ok": not errors,
        "pack": args.pack,
        "overridden": overridden,
        "errors": errors,
    }
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0 if not errors else 1


def cmd_all(args: argparse.Namespace) -> int:
    for step in (cmd_gen, cmd_render, cmd_post, cmd_sheet):
        code = step(args)
        if code != 0:
            return code
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)

    gen = commands.add_parser("gen", help="submit a Tripo generation (spends credits)")
    gen.add_argument("--concept", required=True)
    gen.add_argument("--force", action="store_true", help="respend credits on a changed prompt")
    gen.set_defaults(handler=cmd_gen)

    render = commands.add_parser("render", help="render the model to frames (windowed Godot)")
    render.add_argument("--concept", required=True)
    render.add_argument("--glb", default="", help="render this GLB instead of the concept's model")
    render.add_argument("--verbose", action="store_true")
    render.set_defaults(handler=cmd_render)

    post = commands.add_parser("post", help="finish frames into cell-sized sprites")
    post.add_argument("--concept", required=True)
    post.set_defaults(handler=cmd_post)

    sheet = commands.add_parser("sheet", help="compose retail-geometry sheets into a pack")
    sheet.add_argument("--concept", required=True)
    sheet.add_argument("--pack", required=True)
    sheet.set_defaults(handler=cmd_sheet)

    validate = commands.add_parser("validate", help="validate a pack against the retail manifest")
    validate.add_argument("--pack", required=True)
    validate.set_defaults(handler=cmd_validate)

    everything = commands.add_parser("all", help="gen -> render -> post -> sheet")
    everything.add_argument("--concept", required=True)
    everything.add_argument("--pack", required=True)
    everything.add_argument("--force", action="store_true")
    everything.add_argument("--glb", default="")
    everything.add_argument("--verbose", action="store_true")
    everything.set_defaults(handler=cmd_all)

    args = parser.parse_args()
    return int(args.handler(args))


if __name__ == "__main__":
    raise SystemExit(main())
