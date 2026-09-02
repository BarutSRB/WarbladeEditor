#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import json
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "tools"
sys.path.insert(0, str(TOOLS))

import presentation_manifest


def _res_path(value: str) -> Path:
    prefix = "res://"
    if not value.startswith(prefix):
        raise ValueError(f"not a Godot resource path: {value}")
    return ROOT / value.removeprefix(prefix)


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


class PresentationManifestTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.generated = presentation_manifest.build_manifest()
        cls.committed = json.loads(presentation_manifest.DEFAULT_OUTPUT.read_text(encoding="utf-8"))

    def test_schema_and_selected_counts_are_strict(self) -> None:
        self.assertEqual(2, self.generated["version"])
        self.assertEqual("warblade.presentation.v2", self.generated["schema"])
        self.assertEqual(533, len(self.generated["textures"]))
        self.assertEqual(12, len(self.generated["music"]))
        self.assertEqual(116, len(self.generated["sfx"]))
        self.assertEqual(103, len(self.generated["voices"]))
        self.assertEqual(
            407,
            sum(
                entry["kind"] == "texture"
                for entry in self.generated["textures"].values()
            ),
        )
        self.assertEqual(
            126,
            sum(
                entry["kind"] == "hit_mask"
                for entry in self.generated["textures"].values()
            ),
        )
        self.assertEqual(
            {
                "textures": 533,
                "music": 12,
                "sfx": 116,
                "voices": 103,
                "voice_pack_2": 36,
            },
            self.generated["source_inventory"]["selected_counts"],
        )
        self.assertEqual(
            {"rasters": 407, "hit_masks": 127, "music": 13, "sfx": 112, "voices": 139},
            self.generated["source_inventory"]["retail_counts"],
        )
        self.assertEqual(
            ["mp3", "ogg"],
            self.generated["source_inventory"]["audio_formats"]["inventoried"],
        )

    def test_voice_packs_declare_the_retail_alternate_pack(self) -> None:
        packs = self.generated["voice_packs"]
        self.assertEqual({"1", "2"}, set(packs))
        self.assertEqual(103, packs["1"]["clip_count"])
        self.assertTrue(packs["1"]["complete"])
        self.assertEqual("voices", packs["1"]["source_section"])
        pack_2 = packs["2"]
        self.assertEqual(36, pack_2["clip_count"])
        self.assertFalse(pack_2["complete"])
        self.assertEqual(1, pack_2["fallback_pack"])
        self.assertEqual(36, len(pack_2["clips"]))
        for key, entry in pack_2["clips"].items():
            with self.subTest(clip=key):
                self.assertEqual(2, entry["voice_pack_id"])
                self.assertEqual("ogg", entry["format"])
                self.assertFalse(entry["required"])
                self.assertFalse(entry["loop"])
                self.assertTrue(
                    entry["path"].startswith("res://assets/original/voices/pack_2/")
                )
                self.assertEqual(
                    entry["pack_1_fallback_available"],
                    key in self.generated["voices"],
                )
        self.assertFalse(pack_2["clips"]["loser"]["pack_1_fallback_available"])
        self.assertTrue(pack_2["clips"]["gameover"]["pack_1_fallback_available"])

    def test_every_asset_has_exact_path_size_and_source_hash(self) -> None:
        for section_name in ("textures", "music", "sfx", "voices"):
            for key, entry in self.generated[section_name].items():
                with self.subTest(section=section_name, key=key):
                    self.assertRegex(entry["source_sha256"], r"^[0-9a-f]{64}$")
                    self.assertTrue(entry["path"].startswith("res://assets/original/"))
                    path = _res_path(entry["path"])
                    self.assertTrue(path.is_file(), path)
                    self.assertEqual(path.stat().st_size, entry["byte_size"])
                    self.assertEqual(_sha256_file(path), entry["source_sha256"])
                    self.assertIs(type(entry["required"]), bool)
        for key, entry in self.generated["textures"].items():
            with self.subTest(texture=key):
                self.assertGreater(entry["width"], 0)
                self.assertGreater(entry["height"], 0)
                self.assertIn(entry["kind"], {"texture", "hit_mask"})
        for key, entry in self.generated["music"].items():
            with self.subTest(music=key):
                self.assertIs(entry["loop"], True)
        required_sfx_fields = {
            "loop",
            "max_voices",
            "priority",
            "volume",
            "pitch_scale",
        }
        for key, entry in self.generated["sfx"].items():
            with self.subTest(sfx=key):
                self.assertTrue(required_sfx_fields <= entry.keys())
                self.assertIs(type(entry["loop"]), bool)
                self.assertGreater(entry["max_voices"], 0)
                self.assertGreater(entry["volume"], 0.0)
                self.assertGreater(entry["pitch_scale"], 0.0)
                self.assertEqual(
                    "intentional_runtime_mix_policy"
                    if key in presentation_manifest.REQUIRED_SFX
                    else "not_runtime_consumed",
                    entry["tuning_confidence"],
                )

    def test_texture_dimensions_and_mask_geometry_match_known_sources(self) -> None:
        expected = {
            "alien001": (576, 96),
            "alien_2": (576, 96),
            "alien_3": (576, 96),
            "alien000": (576, 96),
            "alien_lilla": (576, 96),
            "alien003": (576, 96),
            "alien003_3": (576, 96),
            "alien_big1_1": (576, 96),
            "alien_big1_2": (576, 96),
            "alien_big1_3": (576, 96),
            "alien_big1_4": (576, 96),
            "alien_big1_5": (576, 96),
            "alien_big1_6": (576, 96),
            "alien_big2_1": (576, 96),
            "alien_big2_2": (576, 96),
            "alien_big2_3": (576, 96),
            "alien_big2_4": (576, 96),
            "alien_big2_5": (576, 96),
            "alien_big2_6": (576, 96),
            "alien_rakett": (576, 96),
            "alien_rakett_gronn": (576, 96),
            "alien_baller": (576, 96),
            "alien_baller2": (576, 96),
            "alien_green_lilla_t": (576, 96),
            "alien_cyan_lilla_t": (576, 96),
            "alien_raudkule": (576, 96),
            "alien_raudkule2": (576, 96),
            "alien_blavinger_gf": (576, 96),
            "alien_blavinger_gf2": (576, 96),
            "alien_rbille": (576, 96),
            "alien_gultop": (576, 96),
            "alien_lillatop": (576, 96),
            "alien_bluekreps": (576, 96),
            "alien_lbluekreps": (576, 96),
            "alien_brownkreps": (576, 96),
            "alien_brownkreps2": (576, 96),
            "alien_gulkreps": (576, 96),
            "alien_rvinggk": (576, 96),
            "alien_gvingbk": (576, 96),
            "fighter1": (440, 28),
            "fighter2": (440, 28),
            "weapons_big": (672, 100),
            "bonuses": (200, 740),
            "stars1": (1024, 1024),
            "stars2": (1024, 1024),
            "butikk3": (800, 600),
            "memoryblocks": (256, 640),
            "meteors": (624, 717),
            "meteorbonuses": (384, 370),
            "meteormeter2": (64, 640),
        }
        textures = self.generated["textures"]
        for key, dimensions in expected.items():
            with self.subTest(texture=key):
                self.assertEqual(dimensions, (textures[key]["width"], textures[key]["height"]))
        for texture_key, mask_key in (
            ("alien001", "alien001_hma"),
            ("alien_2", "alien_2_hma"),
            ("alien_3", "alien_3_hma"),
            ("alien000", "alien000_hma"),
            ("alien_lilla", "alien_lilla_hma"),
            ("alien003", "alien003_hma"),
            ("alien003_3", "alien003_3_hma"),
            ("alien_big1_1", "alien_big1_1_hma"),
            ("alien_big1_2", "alien_big1_2_hma"),
            ("alien_big1_3", "alien_big1_3_hma"),
            ("alien_big1_4", "alien_big1_4_hma"),
            ("alien_big1_5", "alien_big1_5_hma"),
            ("alien_big1_6", "alien_big1_6_hma"),
            ("alien_big2_1", "alien_big2_1_hma"),
            ("alien_big2_2", "alien_big2_2_hma"),
            ("alien_big2_3", "alien_big2_3_hma"),
            ("alien_big2_4", "alien_big2_4_hma"),
            ("alien_big2_5", "alien_big2_5_hma"),
            ("alien_big2_6", "alien_big2_6_hma"),
            ("alien_rakett", "alien_rakett_hma"),
            ("alien_rakett_gronn", "alien_rakett_gronn_hma"),
            ("alien_baller", "alien_baller_hma"),
            ("alien_baller2", "alien_baller2_hma"),
            ("alien_green_lilla_t", "alien_green_lilla_t_hma"),
            ("alien_cyan_lilla_t", "alien_cyan_lilla_t_hma"),
            ("alien_raudkule", "alien_raudkule_hma"),
            ("alien_raudkule2", "alien_raudkule2_hma"),
            ("alien_blavinger_gf", "alien_blavinger_gf_hma"),
            ("alien_blavinger_gf2", "alien_blavinger_gf2_hma"),
            ("alien_rbille", "alien_rbille_hma"),
            ("alien_gultop", "alien_gultop_hma"),
            ("alien_lillatop", "alien_lillatop_hma"),
            ("alien_bluekreps", "alien_bluekreps_hma"),
            ("alien_lbluekreps", "alien_lbluekreps_hma"),
            ("alien_brownkreps", "alien_brownkreps_hma"),
            ("alien_brownkreps2", "alien_brownkreps2_hma"),
            ("alien_gulkreps", "alien_gulkreps_hma"),
            ("alien_rvinggk", "alien_rvinggk_hma"),
            ("alien_gvingbk", "alien_gvingbk_hma"),
            ("fighter1", "fighter1_hma"),
            ("fighter2", "fighter2_hma"),
            ("weapons_big", "weapons_big_hma"),
            ("bonuses", "bonuses_hma"),
            ("meteors", "meteors_hma"),
            ("meteorbonuses", "meteorbonuses_hma"),
        ):
            with self.subTest(mask=mask_key):
                texture = textures[texture_key]
                mask = textures[mask_key]
                self.assertEqual("hit_mask", mask["kind"])
                self.assertEqual("top_left_row_major", mask["orientation"])
                self.assertEqual(
                    (texture["width"], texture["height"]),
                    (mask["width"], mask["height"]),
                )
                self.assertEqual(mask["width"] * mask["height"], mask["byte_size"])

    def test_collision_safe_namespaces_preserve_original_underscores(self) -> None:
        textures = self.generated["textures"]
        music = self.generated["music"]
        sfx = self.generated["sfx"]
        voices = self.generated["voices"]
        for section in (textures, music, sfx, voices):
            self.assertEqual(len(section), len(set(section)))
            for key in section:
                self.assertRegex(key, r"^[a-z0-9_]+$")
        self.assertIn("alien_2", textures)
        self.assertIn("alien_2_hma", textures)
        self.assertIn("alien_3", textures)
        self.assertIn("alien_3_hma", textures)
        self.assertIn("alien000", textures)
        self.assertIn("alien000_hma", textures)
        self.assertIn("alien_lilla", textures)
        self.assertIn("alien_lilla_hma", textures)
        self.assertIn("alien003", textures)
        self.assertIn("alien003_3_hma", textures)
        self.assertIn("alien_big1_1", textures)
        self.assertIn("alien_big1_6_hma", textures)
        self.assertIn("alien_big2_1", textures)
        self.assertIn("alien_big2_6_hma", textures)
        self.assertIn("alien_rakett", textures)
        self.assertIn("alien_rakett_gronn_hma", textures)
        self.assertIn("alien_baller", textures)
        self.assertIn("alien_baller2_hma", textures)
        self.assertIn("alien_green_lilla_t", textures)
        self.assertIn("alien_cyan_lilla_t_hma", textures)
        self.assertIn("alien_raudkule", textures)
        self.assertIn("alien_raudkule2_hma", textures)
        self.assertIn("alien_blavinger_gf", textures)
        self.assertIn("alien_blavinger_gf2_hma", textures)
        self.assertIn("alien_rbille", textures)
        self.assertIn("alien_rbille_hma", textures)
        for sheet_id in (
            "alien_gultop", "alien_lillatop", "alien_bluekreps",
            "alien_lbluekreps", "alien_brownkreps", "alien_brownkreps2",
            "alien_gulkreps", "alien_rvinggk", "alien_gvingbk",
        ):
            self.assertIn(sheet_id, textures)
            self.assertIn(f"{sheet_id}_hma", textures)
        self.assertIn("alienshoot_2", sfx)
        self.assertIn("alienshoot12_2", sfx)
        self.assertIn("warpmalfunction", sfx)
        self.assertIn("boss", music)
        self.assertIn("gems", music)
        self.assertIn("boss", sfx)
        self.assertIn("memorystation", voices)
        self.assertIn("meteorstorm", voices)
        self.assertIn("bonus", voices)
        self.assertIn("gemdrop", voices)
        self.assertIn("grandmaster", voices)
        self.assertTrue(textures["newlogo3"]["path"].endswith("/newlogo3.tga"))
        self.assertTrue(textures["newlogo3_jpg"]["path"].endswith("/newlogo3.jpg"))
        self.assertEqual((800, 48), (textures["endfont"]["width"], textures["endfont"]["height"]))

    def test_required_resources_are_bounded_to_the_finite_product(self) -> None:
        required_textures = {
            key for key, entry in self.generated["textures"].items() if entry["required"]
        }
        required_music = {
            key for key, entry in self.generated["music"].items() if entry["required"]
        }
        required_sfx = {
            key for key, entry in self.generated["sfx"].items() if entry["required"]
        }
        required_voices = {
            key for key, entry in self.generated["voices"].items() if entry["required"]
        }
        self.assertEqual(presentation_manifest.REQUIRED_TEXTURES, required_textures)
        self.assertEqual(presentation_manifest.REQUIRED_MUSIC, required_music)
        self.assertEqual(presentation_manifest.REQUIRED_SFX, required_sfx)
        self.assertEqual(presentation_manifest.REQUIRED_VOICES, required_voices)
        self.assertEqual(188, len(required_textures))
        self.assertEqual(9, len(required_music))
        self.assertEqual(38, len(required_sfx))
        self.assertEqual(103, len(required_voices))
        self.assertFalse(
            any(
                entry["required"]
                for entry in self.generated["textures"].values()
                if entry["kind"] == "hit_mask"
            ),
            "HMA data must never be passed to ResourceLoader as a required Texture2D",
        )
        self.assertEqual(
            126,
            sum(
                entry["kind"] == "hit_mask"
                for entry in self.generated["textures"].values()
            ),
        )

    def test_first_one_hundred_bindings_are_complete_and_confidence_tagged(self) -> None:
        backgrounds = self.generated["backgrounds"]["levels"]
        self.assertEqual([str(level) for level in range(1, 101)], list(backgrounds))
        self.assertEqual(
            ["stars1"] * 25 + ["stars2"] * 25 + ["stars3"] * 25
            + ["stars4"] * 24 + ["stars1"],
            [backgrounds[str(level)]["texture"] for level in range(1, 101)],
        )
        self.assertTrue(
            all(entry["evidence_confidence"] == "proven" for entry in backgrounds.values())
        )
        motion = self.generated["backgrounds"]["motion_contracts"]["retail_warp_scroll_v1"]
        self.assertEqual([0, 0, 1024, 1024], motion["source_rect"])
        self.assertEqual(
            [[64, "offset-600", 672, 600], [64, "offset", 672, 600]],
            motion["destination_quads"],
        )
        self.assertEqual(["warp"], motion["phase_predicate"])
        self.assertEqual(
            "active warp scale / 20.0 at each authoritative 60 Hz update",
            motion["post_draw_step"],
        )
        self.assertEqual(
            ["warp.background_draw_offset", "warp.background_post_draw_offset"],
            motion["authoritative_snapshot_fields"],
        )
        self.assertEqual(
            "wrapped interpolation between authoritative draw offsets",
            motion["client_sampling"],
        )
        self.assertEqual("0x00551b10-0x00551b84", motion["post_draw_update_va"])
        self.assertEqual(
            "8dfe9604a62a68f8d14090526fc9cfccac7be90642476f31f837332135ff414c",
            motion["post_draw_update_sha256"],
        )
        self.assertEqual(
            {"retail_warp_scroll_v1"},
            {entry["motion_contract"] for entry in backgrounds.values()},
        )
        enemies = self.generated["enemy_sheets"]["by_level"]
        self.assertEqual([str(level) for level in range(1, 101)], list(enemies))
        self.assertEqual(
            ["alien001"] * 4
            + ["alien_2"] * 4
            + ["alien_3"] * 4
            + ["alien000"] * 4
            + ["alien_lilla"] * 4
            + ["alien003"] * 4
            + ["alien_big1_1"]
            + ["alien_rakett"] * 4
            + ["alien_baller"] * 4
            + ["alien_green_lilla_t"] * 4
            + ["alien_raudkule"] * 4
            + ["alien_blavinger_gf"] * 3
            + ["alien_blavinger_gf2"]
            + ["alien_rbille"] * 4
            + ["alien_big2_1"]
            + ["alien_gultop"] * 4
            + ["alien_bluekreps"] * 3
            + ["alien_brownkreps2"]
            + ["alien_rvinggk"] * 3
            + ["alien_gvingbk"],
            [enemies[str(level)]["texture"] for level in range(1, 63)],
        )
        self.assertTrue(
            all(entry["evidence_confidence"] == "proven" for entry in enemies.values())
        )
        resources = self.generated["enemy_sheets"]["resources_by_level"]
        self.assertEqual(
            ["alien003", "alien003_3"],
            [entry["enemy_sheet_id"] for entry in resources["21"]],
        )
        self.assertEqual(
            list(range(1, 7)),
            [entry["resource_slot_id"] for entry in resources["25"]],
        )
        self.assertEqual(
            [f"alien_big1_{index}" for index in range(1, 7)],
            [entry["enemy_sheet_id"] for entry in resources["25"]],
        )
        self.assertEqual(
            ["alien_rakett", "alien_rakett_gronn"],
            [entry["enemy_sheet_id"] for entry in resources["28"]],
        )
        self.assertEqual(
            ["alien_baller", "alien_baller2"],
            [entry["enemy_sheet_id"] for entry in resources["30"]],
        )
        self.assertEqual(
            ["alien_green_lilla_t", "alien_cyan_lilla_t"],
            [entry["enemy_sheet_id"] for entry in resources["35"]],
        )
        self.assertEqual(
            ["alien_green_lilla_t", "alien_cyan_lilla_t"],
            [entry["enemy_sheet_id"] for entry in resources["36"]],
        )
        self.assertEqual(
            ["alien_raudkule", "alien_raudkule2"],
            [entry["enemy_sheet_id"] for entry in resources["39"]],
        )
        self.assertEqual(
            ["alien_blavinger_gf", "alien_blavinger_gf2"],
            [entry["enemy_sheet_id"] for entry in resources["44"]],
        )

    def test_ending_slides_text_timing_controls_and_modes_are_exact(self) -> None:
        ending = self.generated["ending"]
        resources = self.generated["enemy_sheets"]["resources_by_level"]
        self.assertEqual(
            list(presentation_manifest.ENDING_SLIDE_IDS),
            [slide["texture"] for slide in ending["slides"]],
        )
        self.assertEqual([15.0] * 13, [slide["duration_seconds"] for slide in ending["slides"]])
        self.assertFalse(ending["loop"])
        self.assertEqual(30.0, ending["scroll_pixels_per_second"])
        self.assertEqual(8.0, ending["accelerated_multiplier"])
        self.assertEqual("endgame", ending["music"])
        self.assertFalse(ending["story_text"].startswith("|"))
        self.assertTrue(ending["credits_text"].startswith("- - -  CREDITS  - - -"))
        raw_display_text = ("|" + ending["story_text"] + ending["credits_text"]).encode("ascii")
        self.assertEqual(3823, len(raw_display_text))
        self.assertEqual(
            "b4fe7687257464e45094fec26f4c24d9eaf47449eeb9a4e367d2a9c42a63eb06",
            hashlib.sha256(raw_display_text).hexdigest(),
        )
        self.assertEqual(
            {
                "left_mouse": "LEFT MOUSEBUTTON TO PAUSE",
                "right_mouse": "RIGHT MOUSEBUTTON TO SPEED UP",
                "continue": "ESC, SPACE OR FIRE TO CONTINUE",
            },
            ending["controls"],
        )
        self.assertEqual({"0", "2"}, set(ending["modes"]))
        self.assertTrue(ending["evidence"]["text_loop"])
        for mode in ending["modes"].values():
            fireworks = mode["fireworks"]
            self.assertEqual("deterministic_clone_of_terminal_sim_rng", fireworks["sequence_policy"])
            self.assertEqual("intentional_deterministic_modernization", fireworks["fidelity_class"])
            self.assertEqual(60, fireworks["presentation_updates_per_second"])
            self.assertEqual(39, fireworks["interval_updates"])
            self.assertEqual(66, fireworks["duration_updates"])
        self.assertFalse(ending["modes"]["2"]["fireworks_on_draw"])
        self.assertEqual(
            ["alien_rbille"],
            [entry["enemy_sheet_id"] for entry in resources["49"]],
        )
        self.assertEqual(
            [f"alien_big2_{index}" for index in range(1, 7)],
            [entry["enemy_sheet_id"] for entry in resources["50"]],
        )
        self.assertEqual(
            ["alien_gultop", "alien_lillatop"],
            [entry["enemy_sheet_id"] for entry in resources["53"]],
        )
        self.assertEqual(
            ["alien_bluekreps", "alien_lbluekreps", "alien_brownkreps"],
            [entry["enemy_sheet_id"] for entry in resources["57"]],
        )
        self.assertEqual(
            ["alien_brownkreps2", "alien_gulkreps"],
            [entry["enemy_sheet_id"] for entry in resources["58"]],
        )
        self.assertEqual(
            ["alien_rvinggk", "alien_gvingbk"],
            [entry["enemy_sheet_id"] for entry in resources["61"]],
        )
        self.assertEqual("proven", self.generated["borders"]["evidence_confidence"])
        enemy_projectiles = self.generated["projectile_sheets"]["enemy_projectiles"]
        self.assertEqual("proven", enemy_projectiles["evidence_confidence"])
        self.assertIsNone(enemy_projectiles["texture"])
        self.assertEqual("firing_enemy_sheet", enemy_projectiles["texture_selector"])
        self.assertEqual("authoritative_per_projectile_two_state", enemy_projectiles["animation_phase"])
        self.assertEqual(
            [
                "alien001", "alien_2", "alien_3", "alien000", "alien_lilla",
                "alien003", "alien003_3", "alien_big1_1", "alien_big1_2",
                "alien_big1_3", "alien_big1_4", "alien_big1_5", "alien_big1_6",
                "alien_rakett", "alien_rakett_gronn", "alien_baller", "alien_baller2",
                "alien_green_lilla_t", "alien_cyan_lilla_t",
                "alien_raudkule", "alien_raudkule2", "alien_blavinger_gf",
                "alien_blavinger_gf2", "alien_rbille", "alien_big2_1",
                "alien_big2_2", "alien_big2_3", "alien_big2_4", "alien_big2_5",
                "alien_big2_6", "alien_gultop", "alien_lillatop",
                "alien_bluekreps", "alien_lbluekreps", "alien_brownkreps",
                "alien_brownkreps2", "alien_gulkreps", "alien_rvinggk",
                "alien_gvingbk",
            ],
            enemy_projectiles["texture_options"][:39],
        )
        self.assertEqual(
            list(presentation_manifest.EXPECTED_ENEMY_SHEET_IDS),
            enemy_projectiles["texture_options"],
        )
        self.assertEqual("alienshoot10", enemy_projectiles["sound"])
        self.assertEqual([3], enemy_projectiles["suppressed_level_modes"])
        self.assertEqual(
            [[480, 0, 32, 32], [480, 32, 32, 32]],
            enemy_projectiles["source_rects"],
        )
        self.assertEqual(
            "res://content/sprite_frames.json#enemy_projectile_contracts/ordinary_type_7",
            enemy_projectiles["hit_mask_contract"],
        )
        supplemental_projectiles = self.generated["projectile_sheets"][
            "supplemental_enemy_projectiles"
        ]
        self.assertEqual(6, supplemental_projectiles["type_id"])
        self.assertEqual("alienshoot2", supplemental_projectiles["sound"])
        self.assertEqual(
            [3, 7, 11, 15, 19, 23, 28, 32, 36, 40, 44, 48, 53, 57, 61,
             65, 69, 73, 78, 82, 86, 90, 94, 98],
            supplemental_projectiles["reachable_levels"],
        )
        self.assertEqual(
            [[448, 0, 32, 32], [448, 32, 32, 32]],
            supplemental_projectiles["source_rects"],
        )
        self.assertEqual(
            enemy_projectiles["texture_options"],
            supplemental_projectiles["texture_options"],
        )
        self.assertEqual(
            {"frame_size": [16, 25], "frame_count": 10, "frame_advance_ticks": 1},
            {
                key: self.generated["fighter_sheets"]["thruster"][key]
                for key in ("frame_size", "frame_count", "frame_advance_ticks")
            },
        )
        self.assertEqual("proven", self.generated["pickup_sheets"]["bonuses"]["evidence_confidence"])
        self.assertEqual([2, 6], self.generated["pickup_sheets"]["bonuses"]["initial_frame_range"])
        self.assertEqual(
            {"minimum_inclusive": 3.0, "maximum_exclusive": 7.0},
            self.generated["pickup_sheets"]["bonuses"]["frame_period_ticks"],
        )
        self.assertEqual("0123456789", self.generated["ui"]["numbers"]["digit_order"])
        self.assertEqual([8, 9], self.generated["ui"]["numbers"]["digit_cell_size"])
        self.assertEqual(
            {"white": 0, "green": 168, "orange": 336, "purple": 504},
            self.generated["ui"]["numbers"]["palette_offsets"],
        )
        self.assertEqual(
            "shop_autofire_super",
            self.generated["shop"]["item_cards"]["20"],
        )
        effects = self.generated["effects"]
        self.assertEqual(
            "proven_geometry_timing_anchor_and_call_site",
            effects["evidence_confidence"],
        )
        self.assertEqual(
            {
                "effect_type_10": "expl_small",
                "boss_retail_effect/FUN_005dfee0/boss_hit": "expl_small",
            },
            effects["bindings"],
        )
        self.assertEqual(13, effects["small_explosion"]["frame_count"])
        self.assertEqual([0, 1], effects["small_explosion"]["frame_period_values"])
        self.assertEqual([1, 2], effects["small_explosion"]["frame_hold_updates"])
        self.assertEqual([13, 26], effects["small_explosion"]["lifetime_updates"])
        self.assertEqual("center", effects["small_explosion"]["anchor"])
        self.assertEqual("proven", effects["small_explosion"]["anchor_confidence"])
        self.assertEqual("mix", effects["small_explosion"]["blend_mode"])
        self.assertEqual(
            "intentional_runtime_policy",
            effects["small_explosion"]["blend_mode_confidence"],
        )
        self.assertEqual(
            "intentional_runtime_policy",
            effects["small_explosion"]["draw_order_confidence"],
        )
        self.assertEqual("0x00585c15", effects["small_explosion"]["state_13_impact_call_site_va"])
        self.assertEqual(
            "ea40f903dc5bce682a07058e7fdede5de7f25e0a4c1d2517ced056af9bf52ae5",
            effects["small_explosion"]["state_13_branch_sha256"],
        )
        self.assertEqual(
            "state_13_player_projectile_impact_only",
            effects["effect_type_10_producer"]["retail_consumer"],
        )
        self.assertEqual(
            "allocated_count",
            effects["effect_type_10_producer"]["allocation_response_field"],
        )
        self.assertEqual(
            "frame_period",
            effects["effect_type_10_producer"]["authoritative_frame_period_field"],
        )
        self.assertIn(
            "authoritative retail effect pool allocates",
            effects["effect_type_10_producer"]["allocation_gate"],
        )
        self.assertEqual(
            {
                "status": "closed_authoritative_event_consumer",
                "authoritative_event": "boss_retail_effect",
                "authoritative_call": "FUN_005dfee0",
                "authoritative_payload_kind": "boss_hit",
            },
            {
                key: effects["effect_type_10_producer"][key]
                for key in (
                    "status",
                    "authoritative_event",
                    "authoritative_call",
                    "authoritative_payload_kind",
                )
            },
        )
        self.assertEqual("memory", self.generated["bonus_modes"]["memory_station"]["music"])
        self.assertEqual("meteorstorm", self.generated["bonus_modes"]["meteor_storm"]["voice"])
        self.assertEqual("bonus", self.generated["bonus_modes"]["meteor_storm"]["gem_voice"])
        self.assertEqual("gemdrop", self.generated["bonus_modes"]["meteor_storm"]["gem_drop_voice"])
        self.assertEqual("harpgliss1", self.generated["bonus_modes"]["memory_station"]["completion_sfx"])
        self.assertEqual("diamantbig", self.generated["bonus_modes"]["gem_drop"]["texture"])
        self.assertEqual("diamantbig_hma", self.generated["bonus_modes"]["gem_drop"]["hit_mask"])
        self.assertEqual("gems", self.generated["bonus_modes"]["gem_drop"]["music"])
        self.assertEqual("jingles", self.generated["bonus_modes"]["gem_drop"]["collection_sfx"])
        presentation_manifest._validate_declared_references(self.generated)

    def test_executable_fixed_bitmap_font_contracts_are_exact(self) -> None:
        fonts = self.generated["bitmap_fonts"]
        self.assertEqual({"abcd_2", "abcd_3", "abcd_4", "endfont"}, set(fonts))
        primary = fonts["abcd_2"]
        self.assertEqual("0x005d0660", primary["renderer_va"])
        self.assertEqual([8, 8], primary["cell_size"])
        self.assertEqual(8, primary["advance"])
        self.assertEqual({"1": 13, "2": 21, "3": 29, "4": 37}, primary["source_rows"])
        self.assertEqual(0, primary["glyph_indices"]["A"])
        self.assertEqual(25, primary["glyph_indices"]["Z"])
        self.assertEqual(26, primary["glyph_indices"]["0"])
        self.assertEqual(52, primary["glyph_indices"]["%"])
        self.assertEqual({}, primary["pair_kerning"])
        secondary = fonts["abcd_3"]
        self.assertEqual("0x005cfcd0", secondary["renderer_va"])
        self.assertEqual([12, 9], secondary["cell_size"])
        self.assertEqual(10, secondary["glyph_indices"]["A"])
        self.assertEqual(39, secondary["glyph_indices"]["-"])
        self.assertEqual(51, secondary["glyph_indices"][">"])
        large = fonts["abcd_4"]
        self.assertEqual("0x005d04a0", large["renderer_va"])
        self.assertEqual([32, 24], large["cell_size"])
        self.assertEqual(10, large["glyph_indices"][":"])
        ending = fonts["endfont"]
        self.assertEqual([800, 48], ending["atlas_size"])
        self.assertNotIn("glyph_indices", ending)
        self.assertIn("no manufactured names", ending["evidence_boundary"])

    def test_committed_artifacts_are_exact_regeneration(self) -> None:
        self.assertEqual(self.generated, self.committed)
        self.assertEqual(
            presentation_manifest.serialize_manifest(self.generated),
            presentation_manifest.DEFAULT_OUTPUT.read_bytes(),
        )
        self.assertEqual(
            presentation_manifest.build_evidence_markdown(self.generated),
            presentation_manifest.DEFAULT_EVIDENCE.read_bytes(),
        )
        evidence_text = presentation_manifest.DEFAULT_EVIDENCE.read_text(
            encoding="utf-8"
        )
        self.assertIn("## Campaign bindings", evidence_text)
        self.assertIn("## Finite-product inventory", evidence_text)
        self.assertIn("76–99 `stars4`; remainder level 100 `stars1`", evidence_text)
        self.assertIn("all eighty declared resource sheets", evidence_text)
        self.assertIn("## Ending sequence", evidence_text)
        self.assertNotIn("First-sixty-two bindings", evidence_text)
        self.assertNotRegex(
            evidence_text.lower(),
            r"\b(unresolved|provisional|supported approximation)\b",
        )
        result = subprocess.run(
            [sys.executable, str(TOOLS / "presentation_manifest.py"), "--check"],
            cwd=ROOT,
            text=True,
            capture_output=True,
            timeout=30,
            check=False,
        )
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

    def test_check_mode_rejects_stale_artifacts_without_writing(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary = Path(temporary_directory)
            output = temporary / "presentation.json"
            evidence = temporary / "PRESENTATION_ASSETS.md"
            output.write_text("{}\n", encoding="utf-8")
            evidence.write_text("stale\n", encoding="utf-8")
            result = subprocess.run(
                [
                    sys.executable,
                    str(TOOLS / "presentation_manifest.py"),
                    "--output",
                    str(output),
                    "--evidence",
                    str(evidence),
                    "--check",
                ],
                cwd=ROOT,
                text=True,
                capture_output=True,
                timeout=30,
                check=False,
            )
            self.assertEqual(1, result.returncode)
            self.assertEqual("{}\n", output.read_text(encoding="utf-8"))
            self.assertEqual("stale\n", evidence.read_text(encoding="utf-8"))
            self.assertRegex(result.stderr, r"stale generated presentation artifact")

    def test_godot_asset_library_loads_every_required_resource(self) -> None:
        godot = shutil.which("godot") or shutil.which("godot4")
        if godot is None:
            raise unittest.SkipTest("Godot executable is unavailable")
        result = subprocess.run(
            [godot, "--headless", "--path", str(ROOT), "--", "--presentation-smoke"],
            cwd=ROOT,
            text=True,
            capture_output=True,
            timeout=60,
            check=False,
        )
        output = result.stdout + result.stderr
        self.assertEqual(0, result.returncode, output)
        self.assertNotRegex(output, r"(?m)^(SCRIPT ERROR|ERROR):")
        self.assertRegex(output, re.compile(r'"ok":true'))
        self.assertRegex(output, re.compile(r'"hit_masks":126'))
        self.assertRegex(output, re.compile(r'"ending_slides":13'))

    def test_export_presets_package_all_raw_hit_mask_directories(self) -> None:
        presets = (ROOT / "export_presets.cfg").read_text(encoding="utf-8")
        for directory in ("player", "enemies", "weapons", "ui", "bonus_modes"):
            pattern = f"assets/original/textures/{directory}/*.hma"
            self.assertEqual(
                2,
                presets.count(pattern),
                f"both client and server exports must retain {directory} HMA files",
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
