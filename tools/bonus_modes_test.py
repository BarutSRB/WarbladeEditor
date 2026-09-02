#!/usr/bin/env python3

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

import bonus_modes_extract


ROOT = Path(__file__).resolve().parents[1]
COMMITTED = ROOT / "content" / "bonus_modes.json"


class BonusModeContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.generated = bonus_modes_extract.build_document()
        cls.committed_text = COMMITTED.read_text(encoding="utf-8")
        cls.committed = json.loads(cls.committed_text)

    def test_generated_contract_is_committed_exactly(self) -> None:
        self.assertEqual(bonus_modes_extract.serialize(self.generated), COMMITTED.read_bytes())
        self.assertEqual(self.generated, self.committed)

    def test_level_eight_counter_reward_and_flow_contract(self) -> None:
        level = self.generated["level_8_bonus"]
        self.assertEqual((8, 3, 20), (level["level_id"], level["level_mode_id"], level["authored_target_count"]))
        self.assertTrue(level["ordinary_enemy_projectiles_suppressed"])
        self.assertEqual(500, level["rewards"]["hit_reveal_base_score"])
        self.assertEqual(
            [10000, 25000, 50000, 100000, 250000, 500000, 1000000, 2500000, 5000000, 10000000],
            level["rewards"]["perfect_reward_progression"],
        )
        self.assertEqual(3000, level["timing_and_flow"]["level_complete_hold_ms"])
        self.assertEqual(4000, level["timing_and_flow"]["result_initial_deadline_ms"])
        self.assertTrue(level["timing_and_flow"]["shop_after_warp"])

    def test_mode_three_contract_generalizes_all_supported_recurring_levels(self) -> None:
        canonical = self.generated["mode_three_bonus"]
        legacy = self.generated["level_8_bonus"]
        self.assertNotIn("level_id", canonical)
        self.assertNotIn("authored_target_count", canonical)
        self.assertNotIn("background_texture", canonical)
        self.assertNotIn("authored_enemy_score", canonical["rewards"])
        self.assertNotIn("shop_rule", canonical["timing_and_flow"])
        self.assertEqual(
            [
                {"level_id": 8, "authored_target_count": 20, "authored_enemy_score": 200},
                {"level_id": 16, "authored_target_count": 30, "authored_enemy_score": 100},
                {"level_id": 24, "authored_target_count": 30, "authored_enemy_score": 200},
                {"level_id": 33, "authored_target_count": 30, "authored_enemy_score": 500},
                {"level_id": 41, "authored_target_count": 40, "authored_enemy_score": 500},
                {"level_id": 49, "authored_target_count": 40, "authored_enemy_score": 750},
                {"level_id": 58, "authored_target_count": 80, "authored_enemy_score": 500},
                {"level_id": 66, "authored_target_count": 60, "authored_enemy_score": 1000},
                {"level_id": 74, "authored_target_count": 84, "authored_enemy_score": 3000},
                {"level_id": 83, "authored_target_count": 90, "authored_enemy_score": 2000},
                {"level_id": 91, "authored_target_count": 20, "authored_enemy_score": 5000},
                {"level_id": 99, "authored_target_count": 80, "authored_enemy_score": 5000},
            ],
            canonical["levels"],
        )
        self.assertEqual(legacy["level_mode_id"], canonical["level_mode_id"])
        self.assertEqual(
            legacy["rewards"]["perfect_reward_progression"],
            canonical["rewards"]["perfect_reward_progression"],
        )
        self.assertEqual(
            {
                key: value
                for key, value in legacy["timing_and_flow"].items()
                if key != "shop_rule"
            },
            canonical["timing_and_flow"],
        )

    def test_mode_three_aliases_fail_closed_against_pinned_lvd_facts(self) -> None:
        self.assertEqual(
            self.generated["mode_three_bonus"]["levels"],
            bonus_modes_extract.mode_three_level_aliases(),
        )
        levels = json.loads(
            (ROOT / "content" / "levels.json").read_text(encoding="utf-8")
        )
        levels["levels"][40]["enemy_resources"][0]["kill_score"] = 501
        with tempfile.TemporaryDirectory() as temporary:
            changed_path = Path(temporary) / "levels.json"
            changed_path.write_text(json.dumps(levels), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "pinned LVD"):
                bonus_modes_extract.mode_three_level_aliases(changed_path)

    def test_levels_v5_predecessor_remains_readable(self) -> None:
        levels = json.loads(
            (ROOT / "content" / "levels.json").read_text(encoding="utf-8")
        )
        levels["version"] = 5
        levels["schema"] = "warblade.levels.v5"
        levels["levels"] = levels["levels"][:49]
        with tempfile.TemporaryDirectory() as temporary:
            predecessor_path = Path(temporary) / "levels.json"
            predecessor_path.write_text(json.dumps(levels), encoding="utf-8")
            predecessor_aliases = bonus_modes_extract.mode_three_level_aliases(
                predecessor_path
            )
        self.assertEqual(
            self.generated["mode_three_bonus"]["levels"][:6],
            predecessor_aliases,
        )

    def test_levels_v6_predecessor_remains_readable(self) -> None:
        levels = json.loads(
            (ROOT / "content" / "levels.json").read_text(encoding="utf-8")
        )
        levels["version"] = 6
        levels["schema"] = "warblade.levels.v6"
        levels["levels"] = levels["levels"][:50]
        with tempfile.TemporaryDirectory() as temporary:
            predecessor_path = Path(temporary) / "levels.json"
            predecessor_path.write_text(json.dumps(levels), encoding="utf-8")
            predecessor_aliases = bonus_modes_extract.mode_three_level_aliases(
                predecessor_path
            )
        self.assertEqual(
            self.generated["mode_three_bonus"]["levels"][:6],
            predecessor_aliases,
        )

    def test_rank_one_to_twenty_queues_are_closed_over_pinned_voices(self) -> None:
        promotion = self.generated["rank_promotion"]
        self.assertEqual(list(range(1, 21)), [entry["rank"] for entry in promotion["ranks"]])
        voices = promotion["voice_assets"]
        self.assertEqual(26, len(voices))
        for entry in promotion["ranks"]:
            self.assertEqual({"key": "congratulations", "padding_ms": 100}, entry["queue"][0])
            for cue in entry["queue"]:
                self.assertIn(cue["key"], voices)
                self.assertGreaterEqual(cue["padding_ms"], 0)
        self.assertEqual(
            [
                {"key": "warblade", "padding_ms": 20},
                {"key": "grandmaster", "padding_ms": 20},
                {"key": "rank", "padding_ms": 50},
                {"key": "three", "padding_ms": 5},
                {"key": "gold", "padding_ms": 5},
                {"key": "stars", "padding_ms": 0},
            ],
            promotion["ranks"][19]["queue"][1:],
        )

    def test_minigame_assets_and_core_constants_are_exact(self) -> None:
        memory = self.generated["memory_station"]
        self.assertEqual((35, 35), (len(memory["tile_types"]), len(memory["tile_weights"])))
        self.assertEqual(2000, memory["placement_iterations"])
        self.assertEqual(
            ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"],
            memory["presentation"]["countdown_voice_keys"],
        )
        self.assertEqual(list(range(24, 31)), memory["gem_tiles"]["tile_types"])
        self.assertEqual(2, memory["gem_tiles"]["shared_progress"]["increments_per_match"])
        self.assertEqual([22000, 32000], memory["gem_tiles"]["audio"]["bell"]["frequency_rng_half_open"])
        self.assertEqual("not queued by this shared case", memory["gem_tiles"]["audio"]["ordinary_bonus_voice"])
        self.assertEqual("harpgliss1_sfx", memory["completion_audio"]["sfx"])
        self.assertTrue(memory["completion_audio"]["gem_drop_threshold_bypasses_this_tail"])
        meteor = self.generated["meteor_storm"]
        self.assertEqual(30, meteor["slot_count"])
        self.assertEqual(30, len(meteor["spawn"]["flyby_volume_indices"]))
        self.assertEqual(15000, meteor["spawn"]["flyby_frequency_hz"])
        self.assertEqual([51, 30, 10, 150, 80, 38], meteor["bonus"]["effective_counts"])
        self.assertEqual(3000, meteor["result"]["transition_ms"])
        self.assertEqual("thumpbig", meteor["presentation"]["collision_sfx"])
        self.assertEqual("meteorpass", meteor["presentation"]["flyby_sfx"])
        self.assertEqual(5, meteor["gems"]["shared_progress"]["increments_per_pickup"])
        self.assertEqual(1000, meteor["gems"]["shared_progress"]["super_drop_minimum_quotient"])
        self.assertEqual(4000, meteor["gems"]["shared_progress"]["threshold_transition_ms"])
        self.assertEqual("G E M   D R O P", meteor["gems"]["shared_progress"]["threshold_display"])
        self.assertEqual("S U P E R   G E M   D R O P", meteor["gems"]["shared_progress"]["super_drop_display"])
        self.assertEqual("gemdrop_voice", meteor["gems"]["audio"]["gem_drop_voice"]["asset"])
        self.assertEqual("bonus_voice", meteor["gems"]["audio"]["ordinary_voice"]["asset"])
        self.assertEqual([22000, 32000], meteor["gems"]["audio"]["bell"]["frequency_rng_half_open"])
        self.assertEqual(255, meteor["gems"]["audio"]["bell"]["volume_index"])
        self.assertTrue(meteor["gems"]["audio"]["bell"]["rng_consumed_on_every_gem_pickup"])
        self.assertEqual(
            {"bonus_voice", "gemdrop_voice"},
            {key for key in self.generated["assets"] if key.endswith("_voice")} - {"memorystation_voice", "meteorstorm_voice"},
        )
        for asset in self.generated["assets"].values():
            path = ROOT / asset["path"].removeprefix("res://")
            self.assertTrue(path.is_file(), path)

    def test_gem_drop_is_a_complete_terminal_state_18_controller(self) -> None:
        gem_drop = self.generated["gem_drop"]
        self.assertEqual(18, gem_drop["intro"]["main_state"])
        self.assertEqual(4000, gem_drop["intro"]["deadline_ms"])
        self.assertEqual("expired", gem_drop["intro"]["deadline_equality"])
        self.assertEqual(10, gem_drop["pool"]["slot_count"])
        self.assertEqual(
            30,
            gem_drop["pool"]["initialization"]["gem_slot_rng_draws_after_shared_reset"],
        )
        self.assertEqual(2680.0, gem_drop["pool"]["initialization"]["remaining_scalar"])
        reset = gem_drop["shared_pool_reset"]
        self.assertEqual(
            "3 * count(selected-seat predicates != 8) + 100",
            reset["total_rng_calls"],
        )
        self.assertEqual(
            [[0, 6], [0, 2], [0.30000001192092896, 2.0]],
            [
                draw["half_open"]
                for draw in reset["conditional_record_loop"][
                    "rng_when_predicate_not_8_in_order"
                ]
            ],
        )
        self.assertFalse(gem_drop["player_controller"]["primary_fire"]["state_18_suppressed"])
        self.assertEqual(
            [9, 10, 11, 20, 17],
            gem_drop["player_controller"]["primary_fire"][
                "state_suppression_checks_in_order"
            ],
        )
        self.assertEqual([7.0, 14.0], gem_drop["spawn"]["rng_in_order"][3]["half_open"])
        self.assertEqual([6.0, 10.0], gem_drop["spawn"]["offscreen_respawn_difference"]["fall_speed_half_open"])
        self.assertIn("remaining_scalar > 0", gem_drop["spawn"]["capacity_rule"])
        self.assertIn("current < 0", gem_drop["update"]["animation"])
        self.assertIn("y > runtime_screen_height", gem_drop["update"]["offscreen_rule"])
        self.assertEqual("remaining_scalar < 0 after its update decrement", gem_drop["completion"]["condition"])
        self.assertEqual(2, gem_drop["completion"]["next_main_state"])
        self.assertFalse(gem_drop["completion"]["originating_bonus_mode_resumed"])
        self.assertEqual(
            {"0": 50000, "80": 100000, "160": 500000},
            gem_drop["rewards"]["ordinary_by_source_x"],
        )
        self.assertEqual(
            {"0": 1000000, "80": 5000000, "160": 10000000},
            gem_drop["rewards"]["super_by_source_x"],
        )
        self.assertEqual([30000, 45000], gem_drop["audio"]["jingles"]["frequency_rng_half_open"])
        self.assertEqual("diamantbig_hma versus the player's current HMA frame", gem_drop["collision"]["narrow_phase"])
        self.assertEqual(
            "the selected table float is passed unchanged as argument 4 and then unchanged to BASS_ChannelSetAttribute(channel, 3, value)",
            gem_drop["audio"]["jingles"]["pan"]["wrapper_behavior"],
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
