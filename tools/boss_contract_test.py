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

import boss_contract_extract


CONTENT_PATH = ROOT / "content" / "bosses.json"
EVIDENCE_PATH = ROOT / "docs" / "evidence" / "BIG_BOSS_STATE_13.md"


def _contains_unresolved(value: object) -> bool:
    if isinstance(value, str):
        return value.strip().lower() == "unresolved"
    if isinstance(value, list):
        return any(_contains_unresolved(item) for item in value)
    if isinstance(value, dict):
        return any(_contains_unresolved(item) for item in value.values())
    return False


class BossContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.generated = boss_contract_extract.build_document()
        cls.committed_text = CONTENT_PATH.read_text(encoding="utf-8")
        cls.committed = json.loads(cls.committed_text)
        cls.contract = cls.generated["bosses"]["retail_big_boss_v1"]
        cls.level_50_contract = cls.generated["bosses"][
            "retail_big_boss_level_50_v1"
        ]
        cls.level_75_contract = cls.generated["bosses"][
            "retail_big_boss_level_75_v1"
        ]
        cls.level_100_contract = cls.generated["bosses"][
            "retail_big_boss_level_100_v1"
        ]

    def test_generated_contract_and_evidence_are_current(self) -> None:
        self.assertEqual(
            json.dumps(self.generated, indent=2, ensure_ascii=False) + "\n",
            self.committed_text,
        )
        result = subprocess.run(
            [sys.executable, str(TOOLS / "boss_contract_extract.py"), "--check"],
            cwd=ROOT,
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(0, result.returncode, result.stderr)
        artifact_hash = hashlib.sha256(self.committed_text.encode("utf-8")).hexdigest()
        evidence_text = EVIDENCE_PATH.read_text(encoding="utf-8")
        self.assertIn(artifact_hash, evidence_text)
        self.assertIn("Level-75 contract", evidence_text)
        self.assertIn("Level-100 contract", evidence_text)
        self.assertIn("Its v4 routing contracts", evidence_text)

    def test_identity_resources_and_initialization_are_exact(self) -> None:
        self.assertEqual(5, self.generated["version"])
        self.assertEqual("warblade.bosses.v5", self.generated["schema"])
        self.assertEqual(
            [
                "retail_big_boss_v1",
                "retail_big_boss_level_50_v1",
                "retail_big_boss_level_75_v1",
                "retail_big_boss_level_100_v1",
            ],
            list(self.generated["bosses"]),
        )
        self.assertEqual(
            4,
            len({boss["id"] for boss in self.generated["bosses"].values()}),
        )
        contract = self.contract
        self.assertEqual("retail_big_boss_v1", contract["id"])
        self.assertEqual((25, 4, 13), (
            contract["level_id"],
            contract["level_mode_id"],
            contract["retail_state_id"],
        ))
        self.assertTrue(contract["exact_trace_complete"])
        self.assertEqual(boss_contract_extract.EXECUTABLE_SHA256, contract["executable_sha256"])
        self.assertEqual(
            {
                "canonicalization": (
                    boss_contract_extract.AUTHORED_PAYLOAD_CANONICALIZATION
                ),
                "sha256": boss_contract_extract.AUTHORED_LEVEL_PAYLOAD_SHA256,
            },
            contract["authored_level_payload"],
        )
        self.assertEqual(list(range(1, 7)), contract["resources"]["slots"])
        self.assertEqual(boss_contract_extract.SHEET_IDS, contract["resources"]["sheet_ids"])
        self.assertEqual([576, 96], contract["resources"]["sheet_size"])
        initialization = contract["initialization"]
        self.assertEqual([4, 5, 6, 7, 7], initialization["group_modes"])
        self.assertEqual((100, 150), (
            initialization["common_projectile_slots"],
            initialization["authored_entity_slots"],
        ))
        self.assertEqual([-16, -16], initialization["position_offset"])
        self.assertEqual([15000, 30000], initialization["hum_pitch_rng"])
        self.assertEqual([-100, 100], initialization["hum_delta_rng"])
        self.assertEqual(
            {
                "stage_min": 0,
                "stage_max": 5,
                "stage_count": 6,
                "stage_to_resource_slot": list(range(1, 7)),
                "period_rng": [2, 5],
                "countdown_initial": "period",
                "countdown_step": "subtract_tick_scale",
                "advance_when": "countdown<0",
                "advance": 1,
                "wrap": "5_to_0",
                "bounce": False,
                "health_driven": False,
            },
            contract["animation"],
        )
        rendering = contract["rendering"]
        self.assertEqual(2, rendering["part_count"])
        self.assertEqual("trunc_toward_zero", rendering["position_rounding"])
        self.assertEqual(boss_contract_extract.SHEET_IDS, rendering["normal_handles"])
        self.assertEqual(
            [f"{sheet_id}_mask" for sheet_id in boss_contract_extract.SHEET_IDS],
            rendering["hit_flash_handles"],
        )
        self.assertEqual(
            [[0, 0, 256, 64], [256, 0, 256, 64]],
            [part["source_rect"] for part in rendering["parts"]],
        )
        self.assertEqual(
            [[-112, 0], [-112, 64]],
            [part["destination_offset"] for part in rendering["parts"]],
        )
        self.assertEqual(5, rendering["hit_flash"]["successful_hit_countdown"])

    def test_level_fifty_identity_resources_and_initialization_are_exact(self) -> None:
        contract = self.level_50_contract
        self.assertEqual("retail_big_boss_level_50_v1", contract["id"])
        self.assertEqual(
            (50, 4, 13),
            (
                contract["level_id"],
                contract["level_mode_id"],
                contract["retail_state_id"],
            ),
        )
        self.assertTrue(contract["exact_trace_complete"])
        self.assertEqual(
            {
                "canonicalization": (
                    boss_contract_extract.AUTHORED_PAYLOAD_CANONICALIZATION
                ),
                "sha256": (
                    boss_contract_extract.LEVEL_50_AUTHORED_LEVEL_PAYLOAD_SHA256
                ),
            },
            contract["authored_level_payload"],
        )
        self.assertEqual(
            boss_contract_extract.LEVEL_50_SHEET_IDS,
            contract["resources"]["sheet_ids"],
        )
        self.assertEqual(
            boss_contract_extract.LEVEL_50_SHEET_IDS,
            contract["rendering"]["normal_handles"],
        )
        self.assertEqual(
            [f"{sheet_id}_mask" for sheet_id in boss_contract_extract.LEVEL_50_SHEET_IDS],
            contract["rendering"]["hit_flash_handles"],
        )
        self.assertEqual([4, 5, 6, 7, 7], contract["initialization"]["group_modes"])
        self.assertEqual(500, contract["health"]["retail"])
        self.assertEqual(10, contract["health"]["damage_divisor"])
        self.assertEqual(
            ("alien_big2_1", "alien_big2_1"),
            (
                contract["projectile_allocation"]["enemy_sheet_id"],
                contract["projectile_allocation"]["mask_id"],
            ),
        )

    def test_combat_path_and_attacks_are_exact(self) -> None:
        contract = self.contract
        self.assertEqual(
            {
                "retail": 300,
                "balanced_coop_multiplier": 2,
                "damage_divisor": 10,
                "minimum_damage": 1,
                "terminal_hit_below": 0,
                "death_below": 0,
                "endless_step_additive": 100,
                "endless_step_evidence": {
                    "consumer_va_range": ["0x0056b52f", "0x0056b546"],
                    "formula": "authored_base + int(step_additive_float * 20.0)",
                    "step_additive_float_per_step": 5.0,
                    "per_hundred_health": 100,
                    "source": "docs/evidence/ENDLESS_PROGRESSION.md",
                },
            },
            contract["health"],
        )
        for boss in self.generated["bosses"].values():
            self.assertEqual(100, boss["health"]["endless_step_additive"])
        self.assertEqual([16, 16, 240, 112], contract["collision"]["strict_local_bounds"])
        self.assertFalse(contract["collision"]["hma_damage_test"])
        self.assertEqual((15, [32, 32], [8, 8], [24, 24]), (
            contract["aimed_fire"]["projectile_type"],
            contract["aimed_fire"]["size"],
            contract["aimed_fire"]["broadphase_inset"],
            contract["aimed_fire"]["broadphase"],
        ))
        self.assertEqual(10, contract["aimed_fire"]["timer_a_step"])
        self.assertEqual(
            "kill_pass_tightening_only",
            contract["aimed_fire"]["timer_a_step_application"],
        )
        self.assertEqual(
            (
                "inert_state_13_is_sole_active_entity_and_deactivates_before_"
                "terminal_tightening"
            ),
            contract["aimed_fire"]["timer_a_step_active_effect"],
        )
        self.assertEqual((14, [32, 32], [4, 4], [28, 28], [1, 4], [1, 4]), (
            contract["opcode_2"]["projectile_type"],
            contract["opcode_2"]["size"],
            contract["opcode_2"]["broadphase_inset"],
            contract["opcode_2"]["broadphase"],
            contract["opcode_2"]["animation"]["period_rng"],
            contract["opcode_2"]["animation"]["countdown_rng"],
        ))
        self.assertEqual(
            "reserve_then_finalize",
            contract["projectile_allocation"]["protocol"],
        )
        self.assertEqual(
            {
                "ok": "required_boolean",
                "error": "required_string",
                "pool_full": "ok_true_allocated_false",
                "callback_failure": "ok_false_stops_encounter",
            },
            contract["projectile_allocation"]["callback_response"],
        )
        self.assertEqual(
            ["animation", "movement", "retirement"],
            contract["projectile_allocation"]["update_order"],
        )
        self.assertEqual(
            ">surface_height",
            contract["projectile_allocation"]["retirement"]["comparison"],
        )
        self.assertEqual(
            "[frame*32,64,32,32]_unclamped",
            contract["aimed_fire"]["animation"]["source_rect"],
        )
        self.assertEqual(
            {
                "sample": "alienshoot2",
                "overwrite": "last_allocated_wins",
                "flush_order": "after_bigfire_later_same_main_tick",
                "flush_gate": "alternating_global_sound_tick",
                "flush_gate_initial": 4,
                "flush_gate_lifetime": "match_process_not_level",
                "flush_gate_step": "old_then_decrement;old==0_sets_1_and_flushes",
                "closed_gate": "discard_at_next_enemy_update",
                "spatial_source": "final_projectile_top_left",
                "spatial_lookup": "FUN_00627530_then_af6048",
                "x_clamp_uses_surface_height": True,
            },
            contract["opcode_2"]["deferred_projectile_sound"],
        )
        self.assertEqual(
            {
                "music": "boss",
                "hum": "boss",
                "hit": "hit1",
                "terminal_hit": "hit2",
                "death": "explo4",
                "aimed_projectile": "bigsmall",
                "opcode_2_deferred": "alienshoot2",
                "opcode_2_direct": "bigfire",
            },
            contract["sounds"],
        )
        self.assertEqual([0, 1, 2, 7], contract["path"]["opcode_allowlist"])
        self.assertEqual(0.9599999785423279, contract["path"]["loop_ease"])
        self.assertEqual("trunc(progress)>duration", contract["path"]["crossing"])
        self.assertFalse(contract["path"]["point_zero_opcode_dispatch"])

    def test_level_fifty_combat_path_and_attacks_are_exact(self) -> None:
        contract = self.level_50_contract
        aimed_fire = contract["aimed_fire"]
        self.assertEqual(
            (1377, 1377, 1377, 1377, 8),
            (
                aimed_fire["timer"],
                aimed_fire["authored_timer_initial"],
                aimed_fire["runtime_timer_initial"],
                aimed_fire["runtime_rng_upper"],
                aimed_fire["timer_a_step"],
            ),
        )
        self.assertEqual(
            [
                [11, 12, 20, 21],
                [2, 0, 20, 21],
                [5, 0, 20, 21],
                None,
            ],
            aimed_fire["hma_occupied_bounds"],
        )
        self.assertEqual([92, 94, 97, 0], aimed_fire["hma_occupied_pixels"])
        opcode_2 = contract["opcode_2"]
        self.assertEqual(10, opcode_2["dynamic_record_count"])
        self.assertEqual(5.0, opcode_2["speed"])
        self.assertEqual(10, opcode_2["speed_from_first_health_divisor"])
        self.assertEqual(
            [[2, 2, 29, 29]] * 6,
            opcode_2["hma_occupied_bounds"],
        )
        self.assertEqual(
            [646, 645, 645, 645, 645, 645],
            opcode_2["hma_occupied_pixels"],
        )
        path = contract["path"]
        self.assertEqual([0, 1, 2, 3, 7], path["opcode_allowlist"])
        self.assertFalse(path["point_zero_opcode_dispatch"])
        self.assertEqual(
            {
                "effect": "set_mode_7_aim_enabled",
                "rng_draws": 0,
                "loads_acceleration": False,
                "resets_progress": False,
            },
            path["opcode_3"],
        )

    def test_death_reward_routing_and_trace_addresses_are_exact(self) -> None:
        contract = self.contract
        death = contract["death"]
        self.assertEqual([8, 15], death["explosion_count_rng"])
        self.assertEqual(
            ["FUN_00571080", "FUN_005e0650", "FUN_005e0650", "FUN_0052f440"],
            death["post_effects"],
        )
        self.assertEqual(500, death["post_effect_count"])
        self.assertEqual(2, death["plume_count"])
        self.assertEqual(
            [
                [216, 190, 35000, 44100],
                [216, 190, 30000, 40000],
                [216, 190, 25000, 30000],
            ],
            death["sfx_pairs"],
        )
        self.assertEqual(
            "unsigned_reversed_bound_retail_bug",
            death["first_pair_range_semantics"],
        )
        self.assertEqual(500000, contract["reward"]["base_score"])
        self.assertTrue(contract["reward"]["marks_level_complete"])
        self.assertTrue(contract["reward"]["rank_markers_unchanged"])
        self.assertTrue(contract["reward"]["ordinary_completion_bonus_and_rockets"])
        self.assertEqual(
            "destroyed_plus_partner>=authored_total",
            contract["reward"]["destroyed_count"]["completion_condition"],
        )
        self.assertEqual("configured_end_level", contract["routing"]["campaign_wrapper_policy"])
        self.assertEqual(
            "complete_without_requesting_level_26",
            contract["routing"]["explicit_end_level_25_policy"],
        )
        self.assertEqual(
            "request_get_ready_level_26_once",
            contract["routing"]["extended_campaign_policy"],
        )
        self.assertEqual(
            {
                "only_blue_coins_active": "selected_physical_player_persistent_boolean",
                "rank_ready": "projectile_owner_physical_seat_persistent_boolean",
            },
            contract["effects"]["progression_inputs"],
        )
        self.assertEqual(
            {
                "rank_ready": {
                    "storage": "DAT_008487b4",
                    "initialization": "0x006245a2",
                    "set_function": "FUN_0055f650",
                    "set_case": "0x0d",
                    "set_address": "0x00565094",
                    "set_condition": (
                        "all_six_rank_bits_already_set_and_once_per_shop_"
                        "reward_succeeds_and_DAT_00848ba8_is_false"
                    ),
                    "state_13_samples": [
                        "0x005860a7",
                        "0x00588340",
                        "0x0058a2fc",
                    ],
                },
                "only_blue_coins_active": {
                    "storage": "DAT_008489d4",
                    "initialization": "0x00624487",
                    "persisted_hydration_function": "FUN_00549460",
                    "persisted_score_condition": ">19999",
                    "persisted_hydration_address": "0x005495ec",
                    "runtime_set_function": "FUN_00571c60",
                    "runtime_set_condition": (
                        "third_type_0_sucker_or_blue_money_pickup"
                    ),
                    "runtime_set_address": "0x00578b90",
                    "state_13_sample_function": "FUN_00571080",
                    "state_13_sample_address": "0x0057116e",
                },
            },
            contract["effects"]["progression_producers"],
        )
        effect_runtime = contract["effect_runtime"]
        self.assertTrue(effect_runtime["exact_trace_complete"])
        self.assertEqual("retail_big_boss_effects_v1", effect_runtime["id"])
        self.assertEqual(
            (True, 100),
            (
                effect_runtime["preset"]["high_effects"],
                effect_runtime["preset"]["particle_density"],
            ),
        )
        self.assertEqual(
            {"flash": 50, "debris": 150, "smoke": 500, "particle": 1000, "screen": 4},
            {
                pool_name: pool["capacity"]
                for pool_name, pool in effect_runtime["pools"].items()
            },
        )
        self.assertEqual(
            {
                "init": "0x00569260",
                "update": "0x00605fe0",
                "collision": "0x00585840",
                "mark": "0x00555c40",
                "dispatcher": "0x005afc50",
                "renderer": "0x00618560",
                "projectile_type_15_spawn": "0x00612fc7-0x006132bf",
                "projectile_type_14_spawn": "0x00614031-0x006143cf",
                "common_projectile_update": "0x006027e3-0x00602de0",
                "projectile_renderer": "0x00603808/0x00603b32",
                "projectile_player_collision": "0x005842c0",
                "projectile_hma_collision": "0x00625a50",
                "global_sound_gate_thunk": "0x00525924->0x00567990",
                "global_sound_gate_dispatch_calls": "0x005b0c72/0x005b0d96/0x005b10ac/0x005b1191/0x005b1280",
                "get_ready_to_level_transitions": "0x005abac2/0x005abfc0",
                "warp_to_shop_transitions": "0x0061bce8/0x0061be78/0x0061c082",
                "rank_ready_storage_and_initialization": "DAT_008487b4@0x006245a2",
                "rank_ready_shop_producer": "0x00565094",
                "rank_ready_state_13_samples": "0x005860a7/0x00588340/0x0058a2fc",
                "only_blue_storage_and_initialization": "DAT_008489d4@0x00624487",
                "only_blue_persisted_hydration": "0x005495ec",
                "only_blue_runtime_producer": "0x00578b90",
                "only_blue_state_13_sample": "0x0057116e",
            },
            contract["evidence"],
        )

    def test_level_fifty_reward_and_routing_are_exact(self) -> None:
        contract = self.level_50_contract
        self.assertEqual(1000, contract["reward"]["tail_score"])
        self.assertEqual(1000, contract["reward"]["retail_scale"])
        self.assertEqual(1000000, contract["reward"]["base_score"])
        self.assertTrue(contract["reward"]["marks_level_complete"])
        routing = contract["routing"]
        self.assertNotIn("explicit_end_level_25_policy", routing)
        self.assertEqual(
            "complete_without_requesting_level_51",
            routing["explicit_end_level_50_policy"],
        )
        self.assertEqual(
            "request_get_ready_level_51_once",
            routing["extended_campaign_policy"],
        )
        self.assertEqual(self.contract["death"], contract["death"])
        self.assertEqual(self.contract["effects"], contract["effects"])
        self.assertEqual(self.contract["evidence"], contract["evidence"])

    def test_level_seventy_five_source_contract_is_exact(self) -> None:
        contract = self.level_75_contract
        self.assertEqual(
            "daa437aca2a5fe322fef8941a3632d2962da6c7d3d627eca9cae46887af4c64d",
            contract["authored_level_payload"]["sha256"],
        )
        self.assertEqual(613, contract["health"]["retail"])
        self.assertEqual(5000000, contract["reward"]["base_score"])
        self.assertFalse(contract["initialization"]["mirror_x"])
        self.assertEqual([4, 5, 6, 7, 7], contract["initialization"]["group_modes"])
        burst = contract["opcode_2"]
        self.assertEqual((16, 4.6), (burst["dynamic_record_count"], burst["speed"]))
        self.assertEqual(
            [(2, 16, True, 4.6)],
            [
                (
                    group["group_id"],
                    group["authored_record_count"],
                    group["reverse_records"],
                    group["speed"],
                )
                for group in burst["burst_groups"]
            ],
        )
        self.assertEqual([441, 469, 487, 494, 496, 479], burst["hma_occupied_pixels"])
        self.assertEqual([3], contract["path"]["group_opcode_sequences"]["3"])
        self.assertEqual([3], contract["path"]["group_opcode_sequences"]["4"])
        self.assertEqual(
            [{"group_id": 3, "path_opcodes": [3]}, {"group_id": 4, "path_opcodes": [3]}],
            contract["aimed_fire"]["origin_groups"],
        )
        self.assertEqual([95, 91, 100, 0], contract["aimed_fire"]["hma_occupied_pixels"])

    def test_level_one_hundred_source_contract_is_exact(self) -> None:
        contract = self.level_100_contract
        self.assertEqual(
            "ccc5c188f1c4f4e1344d831c759d01590159ccb99b02ae935784a2283bb56f47",
            contract["authored_level_payload"]["sha256"],
        )
        self.assertEqual(500, contract["health"]["retail"])
        self.assertEqual(10000000, contract["reward"]["base_score"])
        self.assertTrue(contract["initialization"]["mirror_x"])
        self.assertEqual([4, 5, 6, 6, 7, 7], contract["initialization"]["group_modes"])
        burst = contract["opcode_2"]
        self.assertEqual((8, 7.5), (burst["dynamic_record_count"], burst["speed"]))
        self.assertEqual(
            [(2, 4, True, 7.5), (3, 4, True, 7.5)],
            [
                (
                    group["group_id"],
                    group["authored_record_count"],
                    group["reverse_records"],
                    group["speed"],
                )
                for group in burst["burst_groups"]
            ],
        )
        self.assertEqual([671, 588, 773, 698, 659, 661], burst["hma_occupied_pixels"])
        for group_id in ("3", "4", "5"):
            self.assertEqual([6, 1], contract["path"]["group_opcode_sequences"][group_id])
        self.assertEqual(
            [{"group_id": 4, "path_opcodes": [6, 1]}, {"group_id": 5, "path_opcodes": [6, 1]}],
            contract["aimed_fire"]["origin_groups"],
        )
        self.assertEqual([91, 90, 97, 87], contract["aimed_fire"]["hma_occupied_pixels"])
        self.assertEqual("deactivate", contract["path"]["opcode_6"])

    def test_contract_has_no_unresolved_gameplay_sentinel(self) -> None:
        self.assertFalse(_contains_unresolved(self.generated["bosses"]))

    def test_authored_payload_mutation_is_rejected(self) -> None:
        levels = json.loads(
            boss_contract_extract.DEFAULT_LEVELS.read_text(encoding="utf-8")
        )
        level_25 = levels["levels"][24]
        level_25["authored_lvd"]["groups"][1]["path_points"][0][
            "acceleration_x_milli"
        ] += 1
        with tempfile.TemporaryDirectory() as directory:
            changed_levels_path = Path(directory) / "levels.json"
            changed_levels_path.write_text(
                json.dumps(levels, indent=2, ensure_ascii=False) + "\n",
                encoding="utf-8",
            )
            with self.assertRaisesRegex(
                boss_contract_extract.BossContractError,
                "normalized authored payload changed",
            ):
                boss_contract_extract.build_document(
                    levels_path=changed_levels_path
                )

    def test_level_fifty_authored_payload_mutation_is_rejected(self) -> None:
        levels = json.loads(
            boss_contract_extract.DEFAULT_LEVELS.read_text(encoding="utf-8")
        )
        level_50 = levels["levels"][49]
        level_50["authored_lvd"]["groups"][1]["path_points"][0][
            "acceleration_x_milli"
        ] += 1
        with tempfile.TemporaryDirectory() as directory:
            changed_levels_path = Path(directory) / "levels.json"
            changed_levels_path.write_text(
                json.dumps(levels, indent=2, ensure_ascii=False) + "\n",
                encoding="utf-8",
            )
            with self.assertRaisesRegex(
                boss_contract_extract.BossContractError,
                "level 50 normalized authored payload changed",
            ):
                boss_contract_extract.build_document(
                    levels_path=changed_levels_path
                )

    def test_late_boss_authored_payload_mutations_are_rejected(self) -> None:
        for level_id in (75, 100):
            with self.subTest(level=level_id):
                levels = json.loads(
                    boss_contract_extract.DEFAULT_LEVELS.read_text(encoding="utf-8")
                )
                levels["levels"][level_id - 1]["authored_lvd"]["groups"][1][
                    "path_points"
                ][0]["acceleration_x_milli"] += 1
                with tempfile.TemporaryDirectory() as directory:
                    changed_levels_path = Path(directory) / "levels.json"
                    changed_levels_path.write_text(
                        json.dumps(levels, indent=2, ensure_ascii=False) + "\n",
                        encoding="utf-8",
                    )
                    with self.assertRaisesRegex(
                        boss_contract_extract.BossContractError,
                        f"level {level_id} normalized authored payload changed",
                    ):
                        boss_contract_extract.build_document(
                            levels_path=changed_levels_path
                        )

    def test_level_and_sprite_catalog_predecessors_remain_readable(self) -> None:
        levels = json.loads(
            boss_contract_extract.DEFAULT_LEVELS.read_text(encoding="utf-8")
        )
        levels["version"] = 7
        levels["schema"] = "warblade.levels.v7"
        levels["levels"] = levels["levels"][:62]
        levels.pop("level_mode_runtime", None)
        sprites = json.loads(
            boss_contract_extract.DEFAULT_SPRITES.read_text(encoding="utf-8")
        )
        sprites["version"] = 8
        sprites["schema"] = "warblade.sprite-frames.v8"
        sprites["enemy_sheets"] = sprites["enemy_sheets"][:39]
        sprites["level_usage"] = sprites["level_usage"][:62]
        sprites["supplemental_spawn_linkages"] = sprites[
            "supplemental_spawn_linkages"
        ][:17]
        retained_sheet_ids = {
            sheet["id"] for sheet in sprites["enemy_sheets"]
        }
        for contract in sprites["enemy_projectile_contracts"].values():
            contract["sheet_masks"] = {
                sheet_id: definition
                for sheet_id, definition in contract["sheet_masks"].items()
                if sheet_id in retained_sheet_ids
            }
        with tempfile.TemporaryDirectory() as directory:
            levels_path = Path(directory) / "levels.json"
            sprites_path = Path(directory) / "sprite_frames.json"
            levels_path.write_text(
                json.dumps(levels, indent=2, ensure_ascii=False) + "\n",
                encoding="utf-8",
            )
            sprites_path.write_text(
                json.dumps(sprites, indent=2, ensure_ascii=False) + "\n",
                encoding="utf-8",
            )
            predecessor = boss_contract_extract.build_document(
                levels_path=levels_path,
                sprites_path=sprites_path,
            )
        self.assertEqual(3, predecessor["version"])
        self.assertEqual("warblade.bosses.v3", predecessor["schema"])
        self.assertEqual(
            ["retail_big_boss_v1", "retail_big_boss_level_50_v1"],
            list(predecessor["bosses"]),
        )
        for contract_id, current_contract in (
            ("retail_big_boss_v1", self.contract),
            ("retail_big_boss_level_50_v1", self.level_50_contract),
        ):
            expected_predecessor_contract = json.loads(json.dumps(current_contract))
            for key in (
                "mirror_x",
                "fixed_record_0_raw_words",
                "supplemental_record_0_raw_words",
            ):
                expected_predecessor_contract["initialization"].pop(key)
            opcode_2_v4_keys = ["burst_groups"]
            if contract_id == "retail_big_boss_v1":
                opcode_2_v4_keys.extend(["dynamic_record_count", "speed"])
            for key in opcode_2_v4_keys:
                expected_predecessor_contract["opcode_2"].pop(key)
            expected_predecessor_contract["path"].pop("group_opcode_sequences")
            expected_predecessor_contract["aimed_fire"].pop("origin_groups")
            for key in ("endless_step_additive", "endless_step_evidence"):
                expected_predecessor_contract["health"].pop(key)
            self.assertEqual(
                expected_predecessor_contract,
                predecessor["bosses"][contract_id],
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
