#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "tools"
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

import ordnance_contract_extract


CONTENT_PATH = ROOT / "content" / "ordnance.json"
EVIDENCE_PATH = ROOT / "docs" / "evidence" / "ORDNANCE_RUNTIME_TRACE.md"


def _contains_unresolved(value: object) -> bool:
    if isinstance(value, str):
        return value.strip().lower() == "unresolved"
    if isinstance(value, list):
        return any(_contains_unresolved(item) for item in value)
    if isinstance(value, dict):
        return any(_contains_unresolved(item) for item in value.values())
    return False


class OrdnanceContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.generated = ordnance_contract_extract.build_document()
        cls.committed_text = CONTENT_PATH.read_text(encoding="utf-8")
        cls.committed = json.loads(cls.committed_text)

    def test_generated_contract_and_evidence_are_current(self) -> None:
        self.assertEqual(
            json.dumps(self.generated, indent=2, ensure_ascii=False) + "\n",
            self.committed_text,
        )
        result = subprocess.run(
            [sys.executable, str(TOOLS / "ordnance_contract_extract.py"), "--check"],
            cwd=ROOT,
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(0, result.returncode, result.stderr)
        artifact_hash = hashlib.sha256(self.committed_text.encode("utf-8")).hexdigest()
        self.assertIn(artifact_hash, EVIDENCE_PATH.read_text(encoding="utf-8"))

    def test_identity_source_and_fail_closed_gate_are_exact(self) -> None:
        self.assertEqual(1, self.generated["version"])
        self.assertEqual("warblade.ordnance.v1", self.generated["schema"])
        source = self.generated["source"]
        self.assertEqual(
            ordnance_contract_extract.EXECUTABLE_SHA256,
            source["executable"]["sha256"],
        )
        self.assertEqual([], source["gameplay_critical_unresolved"])
        self.assertTrue(source["exact_trace_complete"])
        self.assertEqual(15, len(source["code_regions"]))
        self.assertEqual(
            {
                "pc_secondary_control",
                "mac_secondary_control",
                "alien_lock_savegame_fix",
                "player_two_rockets_fix",
                "rocket_particles",
                "post_death_input_fix",
                "meteor_storm_input_fix",
                "distance_audio",
            },
            set(source["manual"]["references"]),
        )
        self.assertFalse(_contains_unresolved(self.generated))
        self.assertTrue(self.generated["integration"]["exact_trace_complete"])
        self.assertEqual(
            {
                "requires_exact_trace_complete": True,
                "requires_assets_and_hma": True,
                "requires_boss_contract_for_state_13": True,
                "forbid_unresolved_gameplay_fields": True,
            },
            self.generated["integration"]["fail_closed"],
        )

    def test_wrong_executable_is_rejected_before_generation(self) -> None:
        executable = ordnance_contract_extract.DEFAULT_EXE.read_bytes()
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "warblade.exe"
            path.write_bytes(executable[:-1] + bytes([executable[-1] ^ 1]))
            with self.assertRaisesRegex(
                ordnance_contract_extract.OrdnanceContractError,
                "unexpected warblade.exe SHA-256",
            ):
                ordnance_contract_extract.build_document(path)

    def test_rocket_pack_purchase_cap_and_persistence_are_exact(self) -> None:
        pack = self.generated["rocket_pack"]
        self.assertEqual((18, 70, 5000), (
            pack["shop_item_id"],
            pack["unlock"]["historical_threshold"],
            pack["price"],
        ))
        self.assertEqual(">=", pack["unlock"]["comparison"])
        purchase = pack["purchase"]
        self.assertEqual(("<50", ">=50", 10, 50), (
            purchase["pre_count_accepts"],
            purchase["pre_count_rejects"],
            purchase["grant"],
            purchase["capacity"],
        ))
        self.assertEqual({"40": 50, "41": 50, "49": 50}, purchase["clamped_purchase_examples"])
        self.assertIn("cash_unchanged", purchase["rejected_result"])
        lifecycle = pack["lifecycle"]
        self.assertEqual("preserve_count", lifecycle["ordinary_death"])
        self.assertEqual("preserve_count", lifecycle["level_and_warp_transition"])
        saved = lifecycle["saved_game_persistence"]
        self.assertEqual((694808, "0x4b0", "0x988"), (
            saved["snapshot_size_bytes"],
            saved["seat_0_relative_offset"],
            saved["seat_1_relative_offset"],
        ))

    def test_alien_lock_is_one_shot_captive_retention_not_homing(self) -> None:
        lock = self.generated["alien_lock"]
        self.assertEqual((19, 80, 15000), (
            lock["shop_item_id"],
            lock["unlock"]["historical_threshold"],
            lock["price"],
        ))
        self.assertEqual(0, lock["purchase"]["pre_value_accepts"])
        self.assertEqual("nonzero", lock["purchase"]["pre_value_rejects"])
        self.assertIn("cash_unchanged", lock["purchase"]["rejected_result"])
        meaning = lock["meaning"]
        self.assertEqual("none", meaning["missile_targeting_effect"])
        self.assertEqual(
            [
                {
                    "slot": "a",
                    "occupied_base": "DAT_00848824",
                    "enemy_index_base": "DAT_00848828",
                },
                {
                    "slot": "b",
                    "occupied_base": "DAT_0084882c",
                    "enemy_index_base": "DAT_00848830",
                },
            ],
            meaning["preserves"],
        )
        lifecycle = lock["lifecycle"]
        self.assertEqual(
            "clear_to_0_for_all_currently_supported_match_modes",
            lifecycle["ordinary_death"],
        )
        self.assertEqual(
            {
                "identity": "time_trial_match_mode",
                "identity_evidence": "0x0059c8a7-0x0059c91d",
                "reset_behavior": "skip_entire_FUN_00571990_loadout_reset",
                "is_phase": False,
                "maps_to_current_remake_phase": False,
                "implementation_status": "implemented_match_mode",
                "supported_policy": "do_not_apply_exception_to_level_warp_or_warp_malfunction_phases",
            },
            lifecycle["retail_mode_6_exception"],
        )
        self.assertEqual(
            "test_and_apply_each_physical_seat_independently",
            lock["duel"]["ownership"],
        )
        saved = lock["lifecycle"]["saved_game_persistence"]
        self.assertEqual(("0x4b4", "0x98c"), (
            saved["seat_0_relative_offset"], saved["seat_1_relative_offset"]
        ))
        self.assertIn("reconstruct_both", saved["load_reconstruction"])

    def test_secondary_edge_pool_failure_and_target_weights_are_exact(self) -> None:
        runtime = self.generated["missile_runtime"]
        input_contract = runtime["input"]
        self.assertEqual("secondary_fire", input_contract["action"])
        self.assertEqual([9, 10, 11, 17, 20], input_contract["suppressed_game_modes"])
        self.assertEqual((1, 0, True, True), (
            input_contract["edge_latch"]["release_sets"],
            input_contract["edge_latch"]["armed_press_clears"],
            input_contract["edge_latch"]["press_consumed_before_pool_and_target_scan"],
            input_contract["edge_latch"]["failed_press_requires_release_before_retry"],
        ))
        pool = runtime["pool"]
        self.assertEqual((100, 160, "ascending_first_inactive_slot"), (
            pool["capacity"], pool["record_stride_bytes"], pool["allocation"]
        ))
        self.assertIn("no_ammo_decrement", pool["pool_full"])
        self.assertEqual("not_checked_or_incremented", pool["ordinary_live_projectile_capacity_counter"])

        targeting = runtime["targeting"]
        self.assertEqual((150, 500), (targeting["scan_count"], targeting["candidate_buffer_capacity"]))
        self.assertEqual([6, 9, 11, 12], targeting["weights"]["8"])
        self.assertEqual([13, 18], targeting["weights"]["16"])
        self.assertEqual([13, 18], targeting["reservation"]["leave_or_set_0_states"])
        self.assertEqual(
            "identical_candidates_weights_rng_and_reservation",
            targeting["alien_lock_on_off_equivalence"],
        )
        self.assertEqual(
            [0, 2, 2, 0, 2, 0, 0, 1, 2, 2, 2, 2, 1],
            targeting["executable_tables"]["state_class_map"],
        )
        self.assertEqual(0, targeting["enemy_world"]["duel_mode_2"])

    def test_spawn_rng_record_update_and_rendering_are_exact(self) -> None:
        runtime = self.generated["missile_runtime"]
        spawn = runtime["spawn"]
        self.assertEqual(
            [
                {"call": "RngInt", "arguments": [0, 3], "add": 4, "field": "animation_period", "result_range": [4, 6]},
                {"call": "RngInt", "arguments": [0, 3], "add": 3, "field": "animation_countdown", "result_range": [3, 5]},
            ],
            spawn["rng_order_after_weighted_target_draw"],
        )
        record = spawn["record"]
        self.assertEqual((200.0, 200, 24, 24, 10.0, 300.0), (
            record["damage_offset_0x14"],
            record["kind_offset_0x18"],
            record["width_0x38"],
            record["height_0x3c"],
            record["speed_0x54"],
            record["lifetime_0x60"],
        ))
        self.assertEqual("player_origin_x+9.0", record["x_0x40"])
        self.assertEqual("player_origin_y-8.0", record["y_0x44"])

        update = runtime["update"]
        self.assertEqual("updated_value<=0", update["lifetime"]["expire_when"])
        self.assertFalse(update["inactive_stored_target"]["weighted"])
        self.assertFalse(update["inactive_stored_target"]["stored_target_overwrite"])
        self.assertEqual([5, 13, 21, 29], update["steering"]["quadrant_desired_headings"])
        self.assertEqual([1, 32], update["steering"]["heading_domain"])
        self.assertEqual(
            [0, 1, 2], update["animation"]["frames"]
        )

        rendering = runtime["rendering"]
        self.assertEqual([768, 72], rendering["atlas"]["dimensions"])
        self.assertEqual([24, 24], rendering["atlas"]["frame_size"])
        self.assertEqual((32, 3), (
            rendering["atlas"]["headings"], rendering["atlas"]["animation_rows"]
        ))
        self.assertFalse(rendering["runtime_rotation"])
        self.assertEqual(
            "[(heading-1)*24,animation_row*24,24,24]",
            rendering["source_rect"],
        )

    def test_missile_movement_tables_and_q16_projection_are_exact(self) -> None:
        movement = self.generated["missile_runtime"]["update"]["steering"]["movement"]
        self.assertEqual([1, 32], movement["heading_domain"])
        self.assertEqual(
            "table_base_plus_heading_times_4_without_subtracting_1",
            movement["index_expression"],
        )
        x_table = movement["float32_tables"]["x"]
        y_table = movement["float32_tables"]["y"]
        self.assertEqual(("0x007d0454", "0x007d0458", "0x007d04d4"), (
            x_table["indexed_base_va"], x_table["first_used_va"], x_table["last_used_va"]
        ))
        self.assertEqual(("0x007d04d4", "0x007d04d8", "0x007d0554"), (
            y_table["indexed_base_va"], y_table["first_used_va"], y_table["last_used_va"]
        ))
        self.assertEqual(
            "1a8c81e2f605d5b8aae5235be63f1e9ad91892d3b12fa2f3ab0a9d309d37f35f",
            x_table["raw_sha256"],
        )
        self.assertEqual(
            "23215a2cde67659ddb17a6afc02fb0fed3f17f189ce8f95e565d6e4c9346ce3a",
            y_table["raw_sha256"],
        )
        self.assertEqual(
            [f"0x{word:08x}" for word in ordnance_contract_extract.MOVEMENT_X_FLOAT32_BITS],
            x_table["ieee754_words"],
        )
        self.assertEqual(
            [f"0x{word:08x}" for word in ordnance_contract_extract.MOVEMENT_Y_FLOAT32_BITS],
            y_table["ieee754_words"],
        )

        q16 = movement["canonical_q16_projection"]
        self.assertEqual(ordnance_contract_extract.MOVEMENT_X_Q16, q16["x"])
        self.assertEqual(ordnance_contract_extract.MOVEMENT_Y_Q16, q16["y"])
        self.assertEqual(
            [
                {"heading": heading, "x": q16["x"][heading - 1], "y": q16["y"][heading - 1]}
                for heading in range(1, 33)
            ],
            q16["vectors"],
        )
        self.assertEqual((0, -65536), (q16["x"][0], q16["y"][0]))
        self.assertEqual((65536, 0), (q16["x"][8], q16["y"][8]))
        self.assertEqual((0, 65536), (q16["x"][16], q16["y"][16]))
        self.assertEqual(q16["y"][17], q16["y"][18])
        self.assertTrue(movement["retail_y_table_irregularity"]["must_preserve"])
        self.assertIn(
            "do_not_replace_with_runtime_cos",
            movement["retail_y_table_irregularity"]["consequence"],
        )
        self.assertEqual(
            "trunc_toward_zero(velocity_x_fp*simulation_scale_numerator/6)",
            q16["speed_10_update"]["delta_x_fp"],
        )

    def test_collision_boss_stats_final_reward_and_assets_are_exact(self) -> None:
        runtime = self.generated["missile_runtime"]
        collision = runtime["collision"]
        self.assertEqual(200.0, collision["ordinary_enemy"]["damage"])
        boss = collision["state_13_boss"]
        self.assertEqual([16, 16, 240, 112], boss["strict_local_bounds"])
        self.assertFalse(boss["hma_damage_test"])
        self.assertEqual(("max(1,projectile_damage/10)", 20, "retail_big_boss_v1"), (
            boss["damage_formula"], boss["rocket_damage"], boss["boss_pipeline_owner"]
        ))

        accuracy = self.generated["integration"]["accuracy"]
        self.assertIn("not_ordinary_denominator", accuracy["successful_missile_spawn"])
        self.assertEqual(">25", accuracy["profile_sample"]["condition"].removeprefix("per_seat_level"))
        self.assertFalse(accuracy["profile_sample"]["level_25_end_creates_sample"])
        self.assertIn("clamp_100", accuracy["retail_percentage"])

        reward = self.generated["integration"]["final_kill_reward"]
        flag = reward["player_projectile_flag"]
        self.assertTrue(flag["not_rocket_only"])
        self.assertFalse(flag["failed_secondary_press_sets"])
        self.assertEqual("0x005df855", flag["set_by_generic_primary_allocation"])
        self.assertEqual("0x005ec1eb", flag["set_by_successful_missile_allocation"])
        self.assertIn("add_10_then_clamp_50", reward["reward"]["if_rocket_count_below_50"])
        self.assertIn("50000", reward["reward"]["if_rocket_count_at_least_50"])

        assets = self.generated["assets"]
        self.assertEqual([768, 72], assets["texture"]["dimensions"])
        self.assertEqual("run_length_encoded_true_color", assets["texture"]["image_type"])
        self.assertEqual([0, 1], assets["hit_mask"]["byte_domain"])
        self.assertEqual(768 * 72, assets["hit_mask"]["size"])


if __name__ == "__main__":
    unittest.main()
