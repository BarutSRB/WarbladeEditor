class_name RetailBigBossSimulation
extends RefCounted

const CatalogScript := preload("res://src/sim/content_catalog.gd")

# Dedicated WarBlade 1.34 state-13 controller. This controller deliberately
# owns only the boss record. The caller continues to own the root RNG, player
# records, projectile pool, score/progression, and level routing.

const RETAIL_EXECUTABLE_SHA256: String = (
	"ddf1778c307af1087ff9dcb512786111e665d972298aeaac3f1b4b2996d079ef"
)
const CONTRACT_ID: String = "retail_big_boss_v1"
const LEVEL_50_CONTRACT_ID: String = "retail_big_boss_level_50_v1"
const LEVEL_75_CONTRACT_ID: String = "retail_big_boss_level_75_v1"
const LEVEL_100_CONTRACT_ID: String = "retail_big_boss_level_100_v1"
const AUTHORED_PAYLOAD_CANONICALIZATION: String = "warblade_canonical_payload_v1"
const AUTHORED_LEVEL_PAYLOAD_SHA256: String = (
	"6ec7ac4f9f5eb5ea7a074d0315a2393acc37da1b0f1fd8f08f9b2c9032a6498f"
)
const LEVEL_50_AUTHORED_LEVEL_PAYLOAD_SHA256: String = (
	"c4ae166f52d970d2e099ae82edab819d24904473cec5f80cdfbc55917f3494bd"
)
const LEVEL_75_AUTHORED_LEVEL_PAYLOAD_SHA256: String = (
	"daa437aca2a5fe322fef8941a3632d2962da6c7d3d627eca9cae46887af4c64d"
)
const LEVEL_100_AUTHORED_LEVEL_PAYLOAD_SHA256: String = (
	"ccc5c188f1c4f4e1344d831c759d01590159ccb99b02ae935784a2283bb56f47"
)
const RETAIL_STATE_ID: int = 13
const LEVEL_ID: int = 25
const LEVEL_MODE_ID: int = 4
const U32_MASK: int = 0xffffffff
const FP_ONE: int = 65536

const GROUP_MODE_ENTRY: int = 4
const GROUP_MODE_LOOP: int = 5
const GROUP_MODE_BURST: int = 6
const GROUP_MODE_AIM_ORIGIN: int = 7
const OPCODE_ALLOWLIST: Array[int] = [0, 1, 2, 7]

const RESOURCE_SHEETS: Array[String] = [
	"alien_big1_1",
	"alien_big1_2",
	"alien_big1_3",
	"alien_big1_4",
	"alien_big1_5",
	"alien_big1_6",
]
const LEVEL_50_RESOURCE_SHEETS: Array[String] = [
	"alien_big2_1",
	"alien_big2_2",
	"alien_big2_3",
	"alien_big2_4",
	"alien_big2_5",
	"alien_big2_6",
]
const LEVEL_75_RESOURCE_SHEETS: Array[String] = [
	"alien_big3_1",
	"alien_big3_2",
	"alien_big3_3",
	"alien_big3_4",
	"alien_big3_5",
	"alien_big3_6",
]
const LEVEL_100_RESOURCE_SHEETS: Array[String] = [
	"alien_big4_1",
	"alien_big4_2",
	"alien_big4_3",
	"alien_big4_4",
	"alien_big4_5",
	"alien_big4_6",
]
const SHEET_WIDTH: int = 576
const SHEET_HEIGHT: int = 96
const RENDER_PART_COUNT: int = 2
const HIT_FLASH_INITIAL_COUNTDOWN: int = 5
const NORMAL_RENDER_HANDLES: Array[String] = [
	"alien_big1_1",
	"alien_big1_2",
	"alien_big1_3",
	"alien_big1_4",
	"alien_big1_5",
	"alien_big1_6",
]
const HIT_FLASH_RENDER_HANDLES: Array[String] = [
	"alien_big1_1_mask",
	"alien_big1_2_mask",
	"alien_big1_3_mask",
	"alien_big1_4_mask",
	"alien_big1_5_mask",
	"alien_big1_6_mask",
]
const RENDER_PARTS: Array[Dictionary] = [
	{
		"part_index": 0,
		"source_rect": [0, 0, 256, 64],
		"destination_offset": [-112, 0],
		"size": [256, 64],
	},
	{
		"part_index": 1,
		"source_rect": [256, 0, 256, 64],
		"destination_offset": [-112, 64],
		"size": [256, 64],
	},
]

const RETAIL_HEALTH: float = 300.0
const BALANCED_COOP_HEALTH_MULTIPLIER: int = 2
const DAMAGE_DIVISOR: float = 10.0
const MINIMUM_DAMAGE: float = 1.0
const TERMINAL_HIT_HEALTH_THRESHOLD: float = 0.0
const COLLISION_ANCHOR_X_OFFSET: float = -128.0
const COLLISION_LEFT: int = 16
const COLLISION_TOP: int = 16
const COLLISION_RIGHT: int = 240
const COLLISION_BOTTOM: int = 112
const SPECIAL_PROJECTILE_LOCAL_Y: int = 60

const COMMON_PROJECTILE_SLOT_COUNT: int = 100
const BOSS_PROJECTILE_SHEET: String = "alien_big1_1"
const BOSS_PROJECTILE_RESOURCE_SLOT: int = 1
const BOSS_PROJECTILE_SIZE: int = 32
const BOSS_PROJECTILE_CENTER_OFFSET: int = 16
const BOSS_PROJECTILE_SURFACE_HEIGHT: int = 600
const TYPE_14_BROADPHASE_INSET: int = 4
const TYPE_14_BROADPHASE_EXTENT: int = 28
const TYPE_14_SOURCE_RECTS: Array = [
	[512, 0, 32, 32],
	[512, 32, 32, 32],
	[512, 64, 32, 32],
	[544, 0, 32, 32],
	[544, 32, 32, 32],
	[544, 64, 32, 32],
]
const TYPE_15_BROADPHASE_INSET: int = 8
const TYPE_15_BROADPHASE_EXTENT: int = 24
const TYPE_15_SOURCE_RECTS: Array = [
	[0, 64, 32, 32],
	[32, 64, 32, 32],
	[64, 64, 32, 32],
	[96, 64, 32, 32],
]

const ANIMATION_FRAME_COUNT: int = 6
const LOOP_EASE: float = 0.9599999785423279
const AIM_TIMER: float = 904.0
const AIM_TRIGGER_MULTIPLIER: float = 3.0
const AIM_TRAVEL_MIN: float = 45.0
const AIM_TRAVEL_MAX: float = 55.0
const AIM_JITTER_MIN: float = -40.0
const AIM_JITTER_MAX: float = 40.0
const BURST_SPAWN_Y_OFFSET: float = 48.0

const BASE_REWARD_SCORE: int = 500000

const DIFFICULTY_AIM_SCALE: Dictionary = {
	"easy": 3.0,
	"normal": 2.200000047683716,
	"hard": 2.0,
	"ace": 1.7999999523162842,
}

var _configured: bool = false
var _entered: bool = false
var _active: bool = false
var _defeated: bool = false
var _blocked: bool = false
var _last_error: String = ""
var _contract: Dictionary = {}
var _level: Dictionary = {}
var _groups_by_mode: Dictionary = {}
var _groups_by_id: Dictionary = {}

var _rng_source: Variant = null
var _allocate_projectile: Callable = Callable()
var _finalize_projectile: Callable = Callable()
var _dispatch_effect: Callable = Callable()
var _mode: String = "solo"
var _coop_balance: String = "classic"
var _difficulty: String = "normal"
var _only_blue_coins_active: bool = false
var _tick: int = 0
var _now_ms: int = 0

var _x: float = 0.0
var _y: float = 0.0
var _velocity_x: float = 0.0
var _velocity_y: float = 0.0
var _acceleration_x: float = 0.0
var _acceleration_y: float = 0.0
var _anchor_x: float = 0.0
var _anchor_y: float = 0.0
var _path_progress: float = 0.0
var _current_group_id: int = 0
var _path_index: int = 0
var _interpolating: bool = false
var _mirror_x: bool = false

var _animation_frame: int = 0
var _animation_period: float = 0.0
var _animation_countdown: float = 0.0
var _animation_direction: int = 1
var _hit_flash_countdown: int = 0

var _health: float = RETAIL_HEALTH
var _maximum_health: float = RETAIL_HEALTH
var _aim_origins: Array[Vector2] = []
var _aim_enabled: bool = false

var _hum_active: bool = false
var _hum_pitch: int = 0
var _hum_pitch_delta: int = 0
var _hum_pitch_lower: int = 15000
var _hum_pitch_upper: int = 30000
var _hit_sound_deadline_ms: int = -1
var _terminal_hit_sound_deadline_ms: int = -1
var _death_sound_deadline_ms: int = -1

var _next_event_id: int = 1
var _pending_events: Array[Dictionary] = []


static func retail_contract() -> Dictionary:
	return {
		"id": CONTRACT_ID,
		"level_id": LEVEL_ID,
		"level_mode_id": LEVEL_MODE_ID,
		"retail_state_id": RETAIL_STATE_ID,
		"executable_sha256": RETAIL_EXECUTABLE_SHA256,
		"exact_trace_complete": true,
		"authored_level_payload": {
			"canonicalization": AUTHORED_PAYLOAD_CANONICALIZATION,
			"sha256": AUTHORED_LEVEL_PAYLOAD_SHA256,
		},
		"resources": {
			"slots": [1, 2, 3, 4, 5, 6],
			"sheet_ids": RESOURCE_SHEETS.duplicate(),
			"sheet_size": [SHEET_WIDTH, SHEET_HEIGHT],
		},
		"animation": {
			"stage_min": 0,
			"stage_max": 5,
			"stage_count": 6,
			"stage_to_resource_slot": [1, 2, 3, 4, 5, 6],
			"period_rng": [2, 5],
			"countdown_initial": "period",
			"countdown_step": "subtract_tick_scale",
			"advance_when": "countdown<0",
			"advance": 1,
			"wrap": "5_to_0",
			"bounce": false,
			"health_driven": false,
		},
		"rendering": {
			"part_count": RENDER_PART_COUNT,
			"position_rounding": "trunc_toward_zero",
			"normal_handles": NORMAL_RENDER_HANDLES.duplicate(),
			"hit_flash_handles": HIT_FLASH_RENDER_HANDLES.duplicate(),
			"hit_flash": {
				"successful_hit_countdown": HIT_FLASH_INITIAL_COUNTDOWN,
				"selection": "mask_when_nonzero_else_normal",
				"decrement": "after_each_part_render",
				"reset": "successful_hit_assigns_5",
			},
			"parts": RENDER_PARTS.duplicate(true),
		},
		"initialization": {
			"group_modes": [4, 5, 6, 7, 7],
			"mirror_x": false,
			"fixed_record_0_raw_words": [6, 0, 0, 0],
			"supplemental_record_0_raw_words": [1, 1, 300, 904, 10],
			"common_projectile_slots": 100,
			"authored_entity_slots": 150,
			"position_offset": [-16, -16],
			"hum_pitch_rng": [15000, 30000],
			"hum_delta_rng": [-100, 100],
		},
		"health": {
			"retail": 300,
			"endless_step_additive": 100,
			"endless_step_evidence": {
				"consumer_va_range": ["0x0056b52f", "0x0056b546"],
				"formula": "authored_base + int(step_additive_float * 20.0)",
				"step_additive_float_per_step": 5.0,
				"per_hundred_health": 100,
				"source": "docs/evidence/ENDLESS_PROGRESSION.md",
			},
			"balanced_coop_multiplier": 2,
			"damage_divisor": 10,
			"minimum_damage": 1,
			"terminal_hit_below": 0,
			"death_below": 0,
		},
		"collision": {
			"anchor_x_offset": -128,
			"strict_local_bounds": [16, 16, 240, 112],
			"special_projectile_local_y": 60,
			"hma_damage_test": false,
		},
		"projectile_allocation": {
			"common_projectile_slots": COMMON_PROJECTILE_SLOT_COUNT,
			"protocol": "reserve_then_finalize",
			"reserve_callback": "allocate_common_projectile",
			"finalize_callback": "finalize_common_projectile",
			"callback_response": {
				"ok": "required_boolean",
				"error": "required_string",
				"pool_full": "ok_true_allocated_false",
				"callback_failure": "ok_false_stops_encounter",
			},
			"retained_response_fields": [
				"retained_animation_frame",
				"retained_animation_period",
				"retained_animation_countdown",
			],
			"pool_full_rng": "none",
			"finalize_failure": "block_encounter",
			"position_storage": "32x32_sprite_top_left",
			"center_offset": [
				BOSS_PROJECTILE_CENTER_OFFSET,
				BOSS_PROJECTILE_CENTER_OFFSET,
			],
			"resource_slot_id": BOSS_PROJECTILE_RESOURCE_SLOT,
			"enemy_sheet_id": BOSS_PROJECTILE_SHEET,
			"mask_id": BOSS_PROJECTILE_SHEET,
			"update_order": ["animation", "movement", "retirement"],
			"animation_countdown_step": "subtract_tick_scale",
			"animation_advance_when": "countdown<0",
			"movement": "add_spawn_tick_scaled_velocity",
			"retirement": {
				"axis": "top_left_y",
				"comparison": ">surface_height",
				"default_surface_height": BOSS_PROJECTILE_SURFACE_HEIGHT,
				"x_bounds": false,
				"age_limit": false,
			},
			"player_collision": {
				"fighter_rect_size": [40, 27],
				"strict_broad_overlap": true,
				"pixel_policy": (
					"broad_hit_when_pixel_disabled_or_either_mask_null_else_hma"
				),
				"invalid_hma_bounds": "miss",
				"on_hit": "consume_and_one_armour_step",
			},
		},
		"aimed_fire": {
			"owning_group_mode": 5,
			"origin_group_mode": 7,
			"trigger_multiplier": 3,
			"timer": 904,
			"timer_a_step": 10,
			"timer_a_step_application": "kill_pass_tightening_only",
			"timer_a_step_active_effect": (
				"inert_state_13_is_sole_active_entity_and_deactivates_before_"
				+ "terminal_tightening"
			),
			"travel_rng": [45, 55],
			"jitter_rng": [-40, 40],
			"projectile_type": 15,
			"size": [BOSS_PROJECTILE_SIZE, BOSS_PROJECTILE_SIZE],
			"broadphase_inset": [
				TYPE_15_BROADPHASE_INSET,
				TYPE_15_BROADPHASE_INSET,
			],
			"broadphase": [24, 24],
			"source_rects": TYPE_15_SOURCE_RECTS.duplicate(true),
			"animation": {
				"initialization": "retain_common_slot_fields",
				"frame_wrap": "3_to_0",
				"source_rect": "[frame*32,64,32,32]_unclamped",
			},
			"hma_occupied_bounds": [
				[11, 12, 20, 21],
				[11, 12, 20, 21],
				[11, 12, 20, 20],
				null,
			],
			"hma_occupied_pixels": [92, 91, 90, 0],
			"sound_frequency_rng": [28000, 32000],
			"origin_groups": [
				{"group_id": 3, "path_opcodes": []},
				{"group_id": 4, "path_opcodes": []},
			],
		},
		"opcode_2": {
			"source_group_mode": 6,
			"reverse_records": true,
			"burst_groups": [{
				"group_id": 2,
				"group_mode_id": 6,
				"authored_record_count": 12,
				"record_order": "reverse",
				"reverse_records": true,
				"speed_from_first_health_divisor": 10,
				"speed": 4.6,
			}],
			"spawn_offset_y": 48,
			"speed_from_first_health_divisor": 10,
			"projectile_type": 14,
			"size": [BOSS_PROJECTILE_SIZE, BOSS_PROJECTILE_SIZE],
			"broadphase_inset": [
				TYPE_14_BROADPHASE_INSET,
				TYPE_14_BROADPHASE_INSET,
			],
			"broadphase": [28, 28],
			"source_rects": TYPE_14_SOURCE_RECTS.duplicate(true),
			"animation": {
				"initial_frame": 0,
				"period_rng": [1, 4],
				"countdown_rng": [1, 4],
				"independent_draws": true,
				"frame_wrap": "5_to_0",
			},
			"hma_occupied_bounds": [
				[1, 0, 30, 31],
				[0, 1, 31, 30],
				[0, 1, 31, 30],
				[0, 1, 31, 30],
				[1, 0, 30, 31],
				[1, 0, 30, 30],
			],
			"hma_occupied_pixels": [571, 573, 571, 568, 569, 571],
			"projectile_sound_frequency_rng": [24000, 30000],
			"deferred_projectile_sound": {
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
				"x_clamp_uses_surface_height": true,
			},
			"burst_sound_frequency_rng": [28000, 32000],
			"dynamic_record_count": 12,
			"speed": 4.6,
		},
		"path": {
			"opcode_allowlist": OPCODE_ALLOWLIST.duplicate(),
			"loop_ease": LOOP_EASE,
			"crossing": "trunc(progress)>duration",
			"opcode_7": "ease_to_anchor_then_restart_mode_5",
			"point_zero_opcode_dispatch": false,
			"group_opcode_sequences": {
				"0": [0, 0, 0, 0, 0, 0, 0],
				"1": [
					0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 0, 0, 0, 0, 0,
					0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2,
					0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 7,
				],
				"2": [],
				"3": [],
				"4": [],
			},
		},
		"death": {
			"explosion_count_rng": [8, 15],
			"explosion_y_rng": [-32, 32],
			"explosion_x_rng": [64, 192],
			"explosion_effect": "FUN_00570420",
			"post_effects": [
				"FUN_00571080",
				"FUN_005e0650",
				"FUN_005e0650",
				"FUN_0052f440",
			],
			"post_effect_count": 500,
			"plume_count": 2,
			"plume_y_float_rng": [0, 96],
			"plume_x_float_rng": [0, 224],
			"plume_particle_count_rng": [50, 100],
			"plume_effect": "FUN_005defe0",
			"sfx_cooldown_rng": [40, 200],
			"sfx_pair_fields": [
				"first_min_argument",
				"first_max_argument",
				"frequency_min_argument",
				"frequency_max_argument",
			],
			"first_pair_range_semantics": "unsigned_reversed_bound_retail_bug",
			"sfx_pairs": [
				[216, 190, 35000, 44100],
				[216, 190, 30000, 40000],
				[216, 190, 25000, 30000],
			],
		},
		"reward": {
			"tail_score": 500,
			"retail_scale": 1000,
			"base_score": BASE_REWARD_SCORE,
			"marks_level_complete": true,
			"stops_hum": true,
			"rank_markers_unchanged": true,
			"destroyed_count": {
				"killer_delta": 1,
				"classic_coop_partner_delta": 1,
				"completion_condition": "destroyed_plus_partner>=authored_total",
				"completion_timestamp": "set_if_zero",
			},
			"ordinary_completion_bonus_and_rockets": true,
		},
		"routing": {
			"completion_mark_timing": "inside FUN_00585840 collision",
			"dispatcher_poll_timing": "same tick after FUN_00605fe0 + render",
			"retail_next_level_intent": true,
			"campaign_wrapper_policy": "configured_end_level",
			"explicit_end_level_25_policy": "complete_without_requesting_level_26",
			"extended_campaign_policy": "request_get_ready_level_26_once",
		},
		"effects": {
			"policy": "synchronous_root_rng_callback",
			"callback_required": true,
			"progression_inputs": {
				"only_blue_coins_active": "selected_physical_player_persistent_boolean",
				"rank_ready": "projectile_owner_physical_seat_persistent_boolean",
			},
			"progression_producers": {
				"rank_ready": {
					"storage": "DAT_008487b4",
					"initialization": "0x006245a2",
					"set_function": "FUN_0055f650",
					"set_case": "0x0d",
					"set_address": "0x00565094",
					"set_condition": (
						"all_six_rank_bits_already_set_and_once_per_shop_"
						+ "reward_succeeds_and_DAT_00848ba8_is_false"
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
			"death_order": [
				"FUN_00570420_each",
				"deactivate_boss",
				"FUN_00571080",
				"FUN_005e0650_left",
				"FUN_005e0650_right",
				"FUN_0052f440",
				"FUN_005defe0_first",
				"FUN_005defe0_second",
				"death_sound_triple",
				"score_popup",
				"level_complete_mark",
				"stop_hum",
			],
		},
		"sounds": {
			"music": "boss",
			"hum": "boss",
			"hit": "hit1",
			"terminal_hit": "hit2",
			"death": "explo4",
			"aimed_projectile": "bigsmall",
			"opcode_2_deferred": "alienshoot2",
			"opcode_2_direct": "bigfire",
		},
		"evidence": {
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
			"global_sound_gate_dispatch_calls": (
				"0x005b0c72/0x005b0d96/0x005b10ac/0x005b1191/0x005b1280"
			),
			"get_ready_to_level_transitions": "0x005abac2/0x005abfc0",
			"warp_to_shop_transitions": "0x0061bce8/0x0061be78/0x0061c082",
			"rank_ready_storage_and_initialization": (
				"DAT_008487b4@0x006245a2"
			),
			"rank_ready_shop_producer": "0x00565094",
			"rank_ready_state_13_samples": (
				"0x005860a7/0x00588340/0x0058a2fc"
			),
			"only_blue_storage_and_initialization": (
				"DAT_008489d4@0x00624487"
			),
			"only_blue_persisted_hydration": "0x005495ec",
			"only_blue_runtime_producer": "0x00578b90",
			"only_blue_state_13_sample": "0x0057116e",
		},
	}


static func contract_for_id(contract_id: String) -> Dictionary:
	match contract_id:
		CONTRACT_ID:
			return retail_contract()
		LEVEL_50_CONTRACT_ID:
			return _level_fifty_contract()
		LEVEL_75_CONTRACT_ID:
			return _level_seventy_five_contract()
		LEVEL_100_CONTRACT_ID:
			return _level_one_hundred_contract()
	return {}


static func _level_fifty_contract() -> Dictionary:
	# Both encounters execute the same state-13 algorithms, but the generated
	# catalog publishes two complete exact contracts. Build a fresh independent
	# value and replace every traced encounter-specific field before it is used
	# for fail-closed comparison or runtime configuration.
	var contract := retail_contract()
	contract.id = LEVEL_50_CONTRACT_ID
	contract.level_id = 50
	contract.authored_level_payload.sha256 = (
		LEVEL_50_AUTHORED_LEVEL_PAYLOAD_SHA256
	)
	contract.resources.sheet_ids = LEVEL_50_RESOURCE_SHEETS.duplicate()
	contract.rendering.normal_handles = LEVEL_50_RESOURCE_SHEETS.duplicate()
	contract.rendering.hit_flash_handles = []
	for sheet_id in LEVEL_50_RESOURCE_SHEETS:
		contract.rendering.hit_flash_handles.append("%s_mask" % sheet_id)
	contract.health.retail = 500
	contract.health.damage_divisor = 10
	contract.initialization.supplemental_record_0_raw_words = [
		1, 1, 500, 1377, 8,
	]
	contract.projectile_allocation.enemy_sheet_id = LEVEL_50_RESOURCE_SHEETS[0]
	contract.projectile_allocation.mask_id = LEVEL_50_RESOURCE_SHEETS[0]
	contract.aimed_fire.timer = 1377
	contract.aimed_fire.authored_timer_initial = 1377
	contract.aimed_fire.runtime_timer_initial = 1377
	contract.aimed_fire.runtime_rng_upper = 1377
	contract.aimed_fire.timer_a_step = 8
	contract.aimed_fire.hma_occupied_bounds = [
		[11, 12, 20, 21],
		[2, 0, 20, 21],
		[5, 0, 20, 21],
		null,
	]
	contract.aimed_fire.hma_occupied_pixels = [92, 94, 97, 0]
	contract.opcode_2.hma_occupied_bounds = [
		[2, 2, 29, 29],
		[2, 2, 29, 29],
		[2, 2, 29, 29],
		[2, 2, 29, 29],
		[2, 2, 29, 29],
		[2, 2, 29, 29],
	]
	contract.opcode_2.hma_occupied_pixels = [646, 645, 645, 645, 645, 645]
	contract.opcode_2.dynamic_record_count = 10
	contract.opcode_2.speed = 5.0
	contract.opcode_2.burst_groups = [{
		"group_id": 2,
		"group_mode_id": 6,
		"authored_record_count": 10,
		"record_order": "reverse",
		"reverse_records": true,
		"speed_from_first_health_divisor": 10,
		"speed": 5.0,
	}]
	contract.path.opcode_allowlist = [0, 1, 2, 3, 7]
	contract.path.opcode_3 = {
		"effect": "set_mode_7_aim_enabled",
		"rng_draws": 0,
		"loads_acceleration": false,
		"resets_progress": false,
	}
	contract.path.group_opcode_sequences = {
		"0": [0, 0],
		"1": [
			2, 0, 0, 0, 0, 1, 2, 0, 0, 1, 0, 0, 0, 0, 1,
			2, 0, 0, 2, 7, 3,
		],
		"2": [],
		"3": [],
		"4": [],
	}
	contract.aimed_fire.origin_groups = [
		{"group_id": 3, "path_opcodes": []},
		{"group_id": 4, "path_opcodes": []},
	]
	contract.reward.tail_score = 1000
	contract.reward.base_score = 1000000
	contract.routing.erase("explicit_end_level_25_policy")
	contract.routing.explicit_end_level_50_policy = (
		"complete_without_requesting_level_51"
	)
	contract.routing.extended_campaign_policy = "request_get_ready_level_51_once"
	return contract


static func _level_seventy_five_contract() -> Dictionary:
	var contract := retail_contract()
	contract.id = LEVEL_75_CONTRACT_ID
	contract.level_id = 75
	contract.authored_level_payload.sha256 = LEVEL_75_AUTHORED_LEVEL_PAYLOAD_SHA256
	_apply_encounter_sheets(contract, LEVEL_75_RESOURCE_SHEETS)
	contract.initialization.supplemental_record_0_raw_words = [
		1, 1, 613, 904, 10,
	]
	contract.health.retail = 613
	contract.aimed_fire.authored_timer_initial = 904
	contract.aimed_fire.runtime_timer_initial = 904
	contract.aimed_fire.runtime_rng_upper = 904
	contract.aimed_fire.hma_occupied_bounds = [
		[9, 0, 20, 21],
		[9, 0, 20, 20],
		[11, 12, 21, 21],
		null,
	]
	contract.aimed_fire.hma_occupied_pixels = [95, 91, 100, 0]
	contract.opcode_2.hma_occupied_bounds = [
		[0, 0, 31, 31],
		[1, 1, 31, 31],
		[1, 1, 31, 30],
		[2, 0, 31, 31],
		[1, 1, 31, 31],
		[0, 0, 30, 30],
	]
	contract.opcode_2.hma_occupied_pixels = [441, 469, 487, 494, 496, 479]
	contract.opcode_2.burst_groups = [{
		"group_id": 2,
		"group_mode_id": 6,
		"authored_record_count": 16,
		"record_order": "reverse",
		"reverse_records": true,
		"speed_from_first_health_divisor": 10,
		"speed": 4.6,
	}]
	contract.opcode_2.dynamic_record_count = 16
	contract.opcode_2.speed = 4.6
	contract.path.opcode_allowlist = [0, 1, 2, 3, 7]
	contract.path.opcode_3 = {
		"effect": "set_mode_7_aim_enabled",
		"rng_draws": 0,
		"loads_acceleration": false,
		"resets_progress": false,
	}
	contract.path.group_opcode_sequences = {
		"0": [0, 0, 0, 0, 0, 0, 0],
		"1": [
			0, 0, 1, 2, 0, 0, 1, 2, 0, 0, 1, 2, 0, 0, 1,
			0, 0, 1, 0, 1, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0,
			0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 7,
		],
		"2": [],
		"3": [3],
		"4": [3],
	}
	contract.aimed_fire.origin_groups = [
		{"group_id": 3, "path_opcodes": [3]},
		{"group_id": 4, "path_opcodes": [3]},
	]
	contract.reward.tail_score = 5000
	contract.reward.base_score = 5000000
	contract.routing.erase("explicit_end_level_25_policy")
	contract.routing.explicit_end_level_75_policy = (
		"complete_without_requesting_level_76"
	)
	contract.routing.extended_campaign_policy = "request_get_ready_level_76_once"
	return contract


static func _level_one_hundred_contract() -> Dictionary:
	var contract := retail_contract()
	contract.id = LEVEL_100_CONTRACT_ID
	contract.level_id = 100
	contract.authored_level_payload.sha256 = LEVEL_100_AUTHORED_LEVEL_PAYLOAD_SHA256
	_apply_encounter_sheets(contract, LEVEL_100_RESOURCE_SHEETS)
	contract.initialization.group_modes = [4, 5, 6, 6, 7, 7]
	contract.initialization.mirror_x = true
	contract.initialization.fixed_record_0_raw_words = [6, 1, 0, 0]
	contract.initialization.supplemental_record_0_raw_words = [
		1, 1, 500, 904, 10,
	]
	contract.health.retail = 500
	contract.aimed_fire.authored_timer_initial = 904
	contract.aimed_fire.runtime_timer_initial = 904
	contract.aimed_fire.runtime_rng_upper = 904
	contract.aimed_fire.hma_occupied_bounds = [
		[11, 12, 20, 21],
		[11, 12, 20, 20],
		[11, 12, 20, 21],
		[7, 0, 20, 20],
	]
	contract.aimed_fire.hma_occupied_pixels = [91, 90, 97, 87]
	contract.opcode_2.hma_occupied_bounds = [
		[0, 0, 30, 31],
		[0, 0, 31, 31],
		[0, 0, 31, 31],
		[0, 0, 31, 31],
		[0, 0, 31, 31],
		[1, 0, 31, 31],
	]
	contract.opcode_2.hma_occupied_pixels = [671, 588, 773, 698, 659, 661]
	contract.opcode_2.burst_groups = [
		{
			"group_id": 2,
			"group_mode_id": 6,
			"authored_record_count": 4,
			"record_order": "reverse",
			"reverse_records": true,
			"speed_from_first_health_divisor": 10,
			"speed": 7.5,
		},
		{
			"group_id": 3,
			"group_mode_id": 6,
			"authored_record_count": 4,
			"record_order": "reverse",
			"reverse_records": true,
			"speed_from_first_health_divisor": 10,
			"speed": 7.5,
		},
	]
	contract.opcode_2.dynamic_record_count = 8
	contract.opcode_2.speed = 7.5
	contract.path.opcode_allowlist = [0, 1, 2, 6, 7]
	contract.path.opcode_6 = "deactivate"
	contract.path.group_opcode_sequences = {
		"0": [0, 0, 0, 0, 0, 0, 0],
		"1": [
			0, 0, 2, 0, 2, 0, 1, 0, 1, 0, 0, 2, 0, 0, 2,
			0, 2, 0, 1, 0, 1, 0, 0, 2, 0, 1, 0, 1, 0, 1,
			0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 7,
		],
		"2": [],
		"3": [6, 1],
		"4": [6, 1],
		"5": [6, 1],
	}
	contract.aimed_fire.origin_groups = [
		{"group_id": 4, "path_opcodes": [6, 1]},
		{"group_id": 5, "path_opcodes": [6, 1]},
	]
	contract.reward.tail_score = 10000
	contract.reward.base_score = 10000000
	contract.routing.erase("explicit_end_level_25_policy")
	contract.routing.explicit_end_level_100_policy = (
		"complete_without_requesting_level_101"
	)
	contract.routing.extended_campaign_policy = "reject_level_101_out_of_catalog"
	return contract


static func _apply_encounter_sheets(
	contract: Dictionary,
	sheets: Array[String]
) -> void:
	contract.resources.sheet_ids = sheets.duplicate()
	contract.rendering.normal_handles = sheets.duplicate()
	contract.rendering.hit_flash_handles = []
	for sheet_id in sheets:
		contract.rendering.hit_flash_handles.append("%s_mask" % sheet_id)
	contract.projectile_allocation.enemy_sheet_id = sheets[0]
	contract.projectile_allocation.mask_id = sheets[0]


func configure(contract: Dictionary, catalog_version: int = 0) -> bool:
	_last_error = ""
	_configured = false
	var contract_id := String(contract.get("id", ""))
	var expected_contract := contract_for_id(contract_id)
	if expected_contract.is_empty():
		return _set_error("boss contract id is not a supported exact state-13 encounter")
	if String(contract.get("executable_sha256", "")) != RETAIL_EXECUTABLE_SHA256:
		return _set_error("boss contract does not match the pinned retail executable")
	if (
		int(contract.get("level_id", 0)) != int(expected_contract.level_id)
		or int(contract.get("level_mode_id", 0)) != int(expected_contract.level_mode_id)
		or int(contract.get("retail_state_id", 0)) != int(expected_contract.retail_state_id)
	):
		return _set_error("boss contract encounter identity differs from its exact binding")
	if not bool(contract.get("exact_trace_complete", false)):
		return _set_error("boss contract is not marked exact-trace complete")
	var canonical_contract := contract.duplicate(true)
	var routing_value: Variant = canonical_contract.get("routing", {})
	if contract_id == CONTRACT_ID and routing_value is Dictionary:
		var routing := routing_value as Dictionary
		if (
			String(routing.get("terminal_level_25_policy", ""))
			== "wrapper completes campaign and never loads 26"
			and not routing.has("campaign_wrapper_policy")
		):
			routing.erase("terminal_level_25_policy")
			routing.campaign_wrapper_policy = "configured_end_level"
			routing.explicit_end_level_25_policy = (
				"complete_without_requesting_level_26"
			)
			routing.extended_campaign_policy = (
				"request_get_ready_level_26_once"
			)
	if contract_id == CONTRACT_ID and catalog_version in [1, 2]:
		_normalize_legacy_level_twenty_five_additions(
			canonical_contract,
			expected_contract
		)
	var initialization_for_version := canonical_contract.get(
		"initialization",
		{}
	) as Dictionary
	var opcode_two_for_version := canonical_contract.get("opcode_2", {}) as Dictionary
	var exact_pre_v4_shape := (
		not initialization_for_version.has("mirror_x")
		and not opcode_two_for_version.has("burst_groups")
	)
	if (
		(catalog_version > 0 and catalog_version < 4)
		or (catalog_version == 0 and exact_pre_v4_shape)
	):
		_normalize_pre_v4_boss_additions(canonical_contract, expected_contract)
	var health_for_version := canonical_contract.get("health", {}) as Dictionary
	if (
		(catalog_version > 0 and catalog_version < 5)
		or (catalog_version == 0 and not health_for_version.has("endless_step_additive"))
	):
		_normalize_pre_v5_boss_additions(canonical_contract, expected_contract)
	# The effect runtime owns and validates its own nested executable contract.
	# Every controller-owned field, including evidence and non-default branches,
	# must otherwise match the generated canonical contract exactly.
	canonical_contract.erase("effect_runtime")
	if not _contract_value_matches(canonical_contract, expected_contract):
		return _set_error("boss contract differs from the pinned state-13 trace")
	_contract = canonical_contract.duplicate(true)
	_configured = true
	return true


static func _normalize_pre_v4_boss_additions(
	contract: Dictionary,
	expected_contract: Dictionary
) -> void:
	var initialization_value: Variant = contract.get("initialization")
	var opcode_two_value: Variant = contract.get("opcode_2")
	var aimed_fire_value: Variant = contract.get("aimed_fire")
	var path_value: Variant = contract.get("path")
	if (
		not initialization_value is Dictionary
		or not opcode_two_value is Dictionary
		or not aimed_fire_value is Dictionary
		or not path_value is Dictionary
	):
		return
	var initialization := initialization_value as Dictionary
	var opcode_two := opcode_two_value as Dictionary
	var aimed_fire := aimed_fire_value as Dictionary
	var path := path_value as Dictionary
	var expected_initialization := expected_contract.get(
		"initialization",
		{}
	) as Dictionary
	var expected_opcode_two := expected_contract.get("opcode_2", {}) as Dictionary
	var expected_aimed_fire := expected_contract.get("aimed_fire", {}) as Dictionary
	var expected_path := expected_contract.get("path", {}) as Dictionary
	if not initialization.has("mirror_x"):
		initialization["mirror_x"] = bool(expected_initialization.get("mirror_x", false))
	for field_name in [
		"fixed_record_0_raw_words",
		"supplemental_record_0_raw_words",
	]:
		if not initialization.has(field_name):
			initialization[field_name] = (
				expected_initialization.get(field_name, []) as Array
			).duplicate(true)
	if not opcode_two.has("burst_groups"):
		opcode_two["burst_groups"] = (
			expected_opcode_two.get("burst_groups", []) as Array
		).duplicate(true)
	if not opcode_two.has("dynamic_record_count"):
		opcode_two["dynamic_record_count"] = int(
			expected_opcode_two.get("dynamic_record_count", 0)
		)
	if not opcode_two.has("speed"):
		opcode_two["speed"] = float(expected_opcode_two.get("speed", 0.0))
	if not aimed_fire.has("origin_groups"):
		aimed_fire["origin_groups"] = (
			expected_aimed_fire.get("origin_groups", []) as Array
		).duplicate(true)
	if not path.has("group_opcode_sequences"):
		path["group_opcode_sequences"] = (
			expected_path.get("group_opcode_sequences", {}) as Dictionary
		).duplicate(true)


static func _normalize_pre_v5_boss_additions(
	contract: Dictionary,
	expected_contract: Dictionary
) -> void:
	# Pre-v5 catalogs predate the endless per-hundred health additive; fill it
	# from the exact expected contract so exact comparison still holds. Steps
	# are zero throughout levels 1-100, so pre-v5 replays are unaffected.
	var health_value: Variant = contract.get("health")
	if not health_value is Dictionary:
		return
	var health := health_value as Dictionary
	var expected_health := expected_contract.get("health", {}) as Dictionary
	if not health.has("endless_step_additive"):
		health["endless_step_additive"] = int(
			expected_health.get("endless_step_additive", 0)
		)
	if not health.has("endless_step_evidence") and expected_health.has(
		"endless_step_evidence"
	):
		health["endless_step_evidence"] = (
			expected_health.get("endless_step_evidence", {}) as Dictionary
		).duplicate(true)


static func _normalize_legacy_level_twenty_five_additions(
	contract: Dictionary,
	expected_contract: Dictionary
) -> void:
	# bosses-v1/v2 predate four evidence-only fields recovered for v0.8.0.
	# Normalize only the exact all-missing historical shape. A partially missing
	# or changed contract still reaches the recursive comparison and fails closed.
	var aimed_fire_value: Variant = contract.get("aimed_fire")
	var path_value: Variant = contract.get("path")
	if not aimed_fire_value is Dictionary or not path_value is Dictionary:
		return
	var aimed_fire := aimed_fire_value as Dictionary
	var path := path_value as Dictionary
	var aimed_keys: Array[String] = [
		"timer_a_step",
		"timer_a_step_application",
		"timer_a_step_active_effect",
	]
	var all_historical_fields_missing := not path.has(
		"point_zero_opcode_dispatch"
	)
	for key in aimed_keys:
		all_historical_fields_missing = (
			all_historical_fields_missing and not aimed_fire.has(key)
		)
	if not all_historical_fields_missing:
		return
	var expected_aimed_fire := expected_contract.aimed_fire as Dictionary
	for key in aimed_keys:
		aimed_fire[key] = expected_aimed_fire[key]
	path["point_zero_opcode_dispatch"] = bool(
		(expected_contract.path as Dictionary).point_zero_opcode_dispatch
	)


func enter(
	level: Dictionary,
	rng_source: Variant,
	runtime: Dictionary,
	match_context: Dictionary = {}
) -> Dictionary:
	_last_error = ""
	if not _configured:
		return _error_result("boss controller is not configured")
	var contract_level_id := int(_contract.get("level_id", 0))
	if int(level.get("id", 0)) != contract_level_id:
		return _error_result(
			"boss controller can only enter its configured level %d" % contract_level_id
		)
	if not _is_rng_source_valid(rng_source):
		return _error_result("rng_source must expose next_u32(), next_float32(), and snapshot()")
	var allocator_value: Variant = runtime.get("allocate_common_projectile", Callable())
	var finalizer_value: Variant = runtime.get("finalize_common_projectile", Callable())
	var effect_value: Variant = runtime.get("dispatch_retail_effect", Callable())
	if not allocator_value is Callable or not (allocator_value as Callable).is_valid():
		return _error_result("allocate_common_projectile callback is required")
	if not finalizer_value is Callable or not (finalizer_value as Callable).is_valid():
		return _error_result("finalize_common_projectile callback is required")
	if not effect_value is Callable or not (effect_value as Callable).is_valid():
		return _error_result("dispatch_retail_effect callback is required")
	if not _validate_level(level):
		return _error_result(_last_error)

	_level = level.duplicate(true)
	_rng_source = rng_source
	_allocate_projectile = allocator_value as Callable
	_finalize_projectile = finalizer_value as Callable
	_dispatch_effect = effect_value as Callable
	_mode = String(match_context.get("mode", "solo")).to_lower()
	_coop_balance = String(match_context.get("coop_balance", "classic")).to_lower()
	_difficulty = String(match_context.get("difficulty", "normal")).to_lower()
	if (
		not match_context.has("only_blue_coins_active")
		or typeof(match_context.only_blue_coins_active) != TYPE_BOOL
	):
		return _error_result(
			"boss match context requires the current player's only-blue-coins boolean"
		)
	_only_blue_coins_active = bool(match_context.only_blue_coins_active)
	if not DIFFICULTY_AIM_SCALE.has(_difficulty):
		return _error_result("boss difficulty must be easy, normal, hard, or ace")
	_tick = maxi(0, int(match_context.get("tick", 0)))
	_now_ms = maxi(0, int(match_context.get("now_ms", 0)))
	var initial_tick_scale := _f32(float(match_context.get("tick_scale", 1.0)))
	if initial_tick_scale <= 0.0:
		return _error_result("boss tick_scale must be positive")

	var entry_group := _group_for_mode(GROUP_MODE_ENTRY)
	var logical_width := int((level.authored_lvd as Dictionary).get("logical_width", 800))
	var initialization := _contract.get("initialization", {}) as Dictionary
	# Endless wrapped levels pass the display-level mirror explicitly; authored
	# levels omit the override and keep the pinned contract value.
	_mirror_x = bool(match_context.get(
		"mirror_x_override",
		bool(initialization.get(
			"mirror_x",
			(level.authored_lvd as Dictionary).get("mirror_x", false)
		))
	))
	var position_offset := initialization.get("position_offset", [-16, -16]) as Array
	_x = _f32(
		float(logical_width) / 2.0
		+ (-float(entry_group.entry_origin_x) if _mirror_x else float(entry_group.entry_origin_x))
		+ float(position_offset[0])
	)
	_y = _f32(float(entry_group.entry_origin_y) + float(position_offset[1]))
	_velocity_x = _f32(
		(-1.0 if _mirror_x else 1.0)
		* float(entry_group.initial_velocity_x_milli) / 1000.0
	)
	_velocity_y = _f32(float(entry_group.initial_velocity_y_milli) / 1000.0)
	_current_group_id = int(entry_group.id)
	_path_index = 0
	_path_progress = initial_tick_scale
	_interpolating = false
	_anchor_x = _x
	_anchor_y = _y
	_set_acceleration_from_path_point(_path_point(entry_group, 0))

	var health_contract := _contract.get("health", {}) as Dictionary
	_maximum_health = float(health_contract.get("retail", RETAIL_HEALTH))
	# Endless wrapped encounters add the traced per-hundred state-13 health
	# additive (authored base + int(5.0 * steps * 20.0)) before the remake's
	# balanced-co-op multiplier; retail has no co-op, so the retail formula is
	# the pre-multiplier value.
	var endless_steps := maxi(0, int(match_context.get("endless_steps", 0)))
	if endless_steps > 0:
		_maximum_health += float(
			int(health_contract.get("endless_step_additive", 0)) * endless_steps
		)
	if _mode == "coop" and _coop_balance == "balanced":
		_maximum_health *= int(health_contract.get(
			"balanced_coop_multiplier",
			BALANCED_COOP_HEALTH_MULTIPLIER
		))
	_health = _maximum_health

	# These are the first three state-13-specific draws. The ordinary level
	# loader's 100 + 150 slot initializers and optional tail draw precede enter().
	_animation_period = float(_rng_int(2, 5))
	_animation_countdown = _animation_period
	_animation_frame = 0
	_animation_direction = 1
	_hit_flash_countdown = 0
	_hum_pitch = _rng_int(15000, 30000)
	_hum_pitch_delta = _rng_int(-100, 100)
	_hum_pitch_lower = 15000
	_hum_pitch_upper = 30000
	_hum_active = true
	_hit_sound_deadline_ms = -1
	_terminal_hit_sound_deadline_ms = -1
	_death_sound_deadline_ms = -1

	_aim_origins.clear()
	var aimed_fire := _contract.get("aimed_fire", {}) as Dictionary
	var origin_contracts := aimed_fire.get("origin_groups", []) as Array
	if origin_contracts.is_empty():
		for group_value in (level.authored_lvd as Dictionary).groups:
			var group := group_value as Dictionary
			if int(group.group_mode_id) == GROUP_MODE_AIM_ORIGIN:
				_append_aim_origin(group)
	else:
		for origin_value in origin_contracts:
			var origin := origin_value as Dictionary
			_append_aim_origin(
				_groups_by_id[int(origin.get("group_id", -1))] as Dictionary
			)
	_aim_enabled = _aim_origins.size() == 2

	_next_event_id = 1
	_pending_events = []
	_entered = true
	_active = true
	_defeated = false
	_blocked = false
	var sounds := _contract.get("sounds", {}) as Dictionary
	_emit("boss_music", {
		"key": String(sounds.get("music", "boss")),
		"action": "play_once",
	})
	_emit("boss_hum", {
		"key": String(sounds.get("hum", "boss")),
		"action": "start_loop",
		"pitch": _hum_pitch,
		"pitch_delta": _hum_pitch_delta,
	})
	_emit("boss_entered", {
		"state": int(_contract.get("retail_state_id", RETAIL_STATE_ID)),
		"health": _health,
		"maximum_health": _maximum_health,
		"x": _x,
		"y": _y,
	})
	return _result()


func step(tick: int, tick_scale: float, players: Array) -> Dictionary:
	_last_error = ""
	if not _entered:
		return _error_result("boss has not been entered")
	if tick <= _tick:
		return _error_result("boss step tick must increase monotonically")
	var scale := _f32(tick_scale)
	if scale <= 0.0:
		return _error_result("boss tick_scale must be positive")
	_tick = tick
	if not _active or _blocked:
		return _result()

	_update_hum_pitch()
	if _blocked:
		return _result()
	if _current_group_mode() == GROUP_MODE_LOOP and _aim_enabled:
		_update_aimed_fire(scale, players)
	if _blocked:
		return _result()
	_update_animation(scale)
	_update_path(scale)
	return _result()


func resolve_player_projectile(projectile: Dictionary, now_ms: int) -> Dictionary:
	_last_error = ""
	if not _entered:
		return _collision_error("boss has not been entered")
	if now_ms < _now_ms:
		return _collision_error("boss collision milliseconds must not move backwards")
	_now_ms = now_ms
	if not _active or _blocked:
		return _collision_result(false, 0.0, false)

	var midpoint_x := _projectile_coordinate(projectile, "midpoint_x", "x")
	var midpoint_y := _projectile_coordinate(projectile, "midpoint_y", "y")
	var collision_contract := _contract.get("collision", {}) as Dictionary
	var health_contract := _contract.get("health", {}) as Dictionary
	var sounds := _contract.get("sounds", {}) as Dictionary
	var anchor_x_offset := float(collision_contract.get(
		"anchor_x_offset",
		COLLISION_ANCHOR_X_OFFSET
	))
	var local_x := int(midpoint_x - (_x + anchor_x_offset))
	var local_y := int(midpoint_y - _y)
	if (
		bool(projectile.get("special_collision_y", false))
		and _y > 0.0
		and _y < float(projectile.get("surface_height", 600))
	):
		local_y = int(collision_contract.get(
			"special_projectile_local_y",
			SPECIAL_PROJECTILE_LOCAL_Y
		))
	var strict_bounds := collision_contract.get(
		"strict_local_bounds",
		[COLLISION_LEFT, COLLISION_TOP, COLLISION_RIGHT, COLLISION_BOTTOM]
	) as Array
	var hit := (
		int(strict_bounds[0]) < local_x
		and local_x < int(strict_bounds[2])
		and int(strict_bounds[1]) < local_y
		and local_y < int(strict_bounds[3])
	)
	if not hit:
		return _collision_result(false, 0.0, false)
	var rendering := _contract.get("rendering", {}) as Dictionary
	var hit_flash := rendering.get("hit_flash", {}) as Dictionary
	_hit_flash_countdown = int(hit_flash.get(
		"successful_hit_countdown",
		HIT_FLASH_INITIAL_COUNTDOWN
	))

	if not _call_effect("FUN_005dfee0", {
		"kind": "boss_hit",
		"x": _f32((_x + anchor_x_offset) + float(local_x)),
		"y": _f32(_y + float(local_y)),
	}):
		return _collision_error(_last_error)
	if _hit_sound_deadline_ms < now_ms:
		_hit_sound_deadline_ms = now_ms + _rng_int(100, 300)
		_emit("sound", {
			"key": String(sounds.get("hit", "hit1")),
			"frequency": _rng_int(25000, 44100),
			"deadline_ms": _hit_sound_deadline_ms,
			"volume": 250,
		})

	var damage_divisor := float(health_contract.get("damage_divisor", DAMAGE_DIVISOR))
	var damage := _f32(float(projectile.get("damage", projectile.get("damage_fp", FP_ONE))) / (
		damage_divisor if projectile.has("damage") else damage_divisor * FP_ONE
	))
	var minimum_damage := float(health_contract.get("minimum_damage", MINIMUM_DAMAGE))
	if damage < minimum_damage:
		damage = minimum_damage
	_health = _f32(_health - damage)
	var owner_seat_id := int(projectile.get("owner_id", projectile.get("owner_seat_id", 0)))
	_emit("boss_hit", {
		"owner_seat_id": owner_seat_id,
		"damage": damage,
		"health": _health,
	})

	if _health < float(health_contract.get(
		"terminal_hit_below",
		TERMINAL_HIT_HEALTH_THRESHOLD
	)):
		if not _emit_terminal_hit_effect(now_ms):
			return _collision_error(_last_error)
	if _health < float(health_contract.get("death_below", 0.0)):
		if (
			not projectile.has("rank_ready")
			or typeof(projectile.rank_ready) != TYPE_BOOL
		):
			_blocked = true
			_active = false
			return _collision_error(
				"killing projectile requires its owner's rank-ready boolean"
			)
		_defeat(owner_seat_id, bool(projectile.rank_ready))
	var is_laser := bool(projectile.get("is_laser", false))
	var collision := _collision_result(true, damage, _defeated)
	collision["consume_projectile"] = not is_laser
	if is_laser:
		collision["remaining_damage_fp"] = int(projectile.get("damage_fp", 0)) >> 1
	return collision


func snapshot() -> Dictionary:
	var runtime_contract := _contract if not _contract.is_empty() else retail_contract()
	var resources := runtime_contract.get("resources", {}) as Dictionary
	var sheets := resources.get("sheet_ids", RESOURCE_SHEETS) as Array
	var rendering := runtime_contract.get("rendering", {}) as Dictionary
	var normal_handles := rendering.get(
		"normal_handles",
		NORMAL_RENDER_HANDLES
	) as Array
	var hit_flash_handles := rendering.get(
		"hit_flash_handles",
		HIT_FLASH_RENDER_HANDLES
	) as Array
	var render_parts := rendering.get("parts", RENDER_PARTS) as Array
	var frame := clampi(_animation_frame, 0, sheets.size() - 1)
	var parts: Array[Dictionary] = []
	var projected_countdown := _hit_flash_countdown
	for part_value in render_parts:
		var part_definition := part_value as Dictionary
		var part_index := int(part_definition.part_index)
		var flash := projected_countdown != 0
		if flash:
			projected_countdown -= 1
		var destination_offset := part_definition.destination_offset as Array
		var part_size := part_definition.size as Array
		var source_rect := part_definition.source_rect as Array
		parts.append({
			"part_id": str(part_index),
			"part_index": part_index,
			"active": _active,
			"sheet": String(sheets[frame]),
			"render_handle": (
				String(hit_flash_handles[frame])
				if flash
				else String(normal_handles[frame])
			),
			"hit_flash": flash,
			"source_rect": [
				int(source_rect[0]),
				int(source_rect[1]),
				int(source_rect[2]),
				int(source_rect[3]),
			],
			"destination_rect": [
				int(_x) + int(destination_offset[0]),
				int(_y) + int(destination_offset[1]),
				int(part_size[0]),
				int(part_size[1]),
			],
		})
	return {
		"active": _active,
		"state": int(runtime_contract.get("retail_state_id", RETAIL_STATE_ID)) if _entered else 0,
		"stage": _animation_frame if _entered else 0,
		"defeated": _defeated,
		"blocked": _blocked,
		"health": _health,
		"max_health": _maximum_health,
		"sheet": String(sheets[frame]),
		"sheet_index": _animation_frame + 1,
		"animation_frame": _animation_frame,
		"animation_period": _animation_period,
		"animation_countdown": _animation_countdown,
		"animation_direction": _animation_direction,
		"hit_flash_countdown": _hit_flash_countdown,
		"x": _x,
		"y": _y,
		"velocity_x": _velocity_x,
		"velocity_y": _velocity_y,
		"path_group_id": _current_group_id,
		"path_mode": _current_group_mode() if _entered else 0,
		"path_index": _path_index,
		"path_progress": _path_progress,
		"interpolating": _interpolating,
		"mirror_x": _mirror_x,
		"parts": parts,
	}


# FUN_00618560 mutates the hit-flash countdown while drawing. The authoritative
# caller must invoke this exactly once at the retail render point, even in a
# headless run, so snapshot/hash state does not depend on whether a client is
# attached. snapshot() projects the two handles without mutating this state.
func complete_render_pass() -> Dictionary:
	if not _entered:
		return _error_result("boss has not been entered")
	# Capture the exact handles before reproducing renderer-owned countdown
	# mutation. Callers publish render_snapshot, then hash/store snapshot.
	var render_snapshot := snapshot()
	if _active:
		var rendering := _contract.get("rendering", {}) as Dictionary
		for _part_index in range(int(rendering.get(
			"part_count",
			RENDER_PART_COUNT
		))):
			if _hit_flash_countdown != 0:
				_hit_flash_countdown -= 1
	var result := _result()
	result["render_snapshot"] = render_snapshot
	return result


func state_hash_payload() -> Dictionary:
	return {
		"active": _active,
		"defeated": _defeated,
		"blocked": _blocked,
		"x": _x,
		"y": _y,
		"velocity_x": _velocity_x,
		"velocity_y": _velocity_y,
		"acceleration_x": _acceleration_x,
		"acceleration_y": _acceleration_y,
		"anchor_x": _anchor_x,
		"anchor_y": _anchor_y,
		"group_id": _current_group_id,
		"path_index": _path_index,
		"path_progress": _path_progress,
		"interpolating": _interpolating,
		"animation_frame": _animation_frame,
		"animation_period": _animation_period,
		"animation_countdown": _animation_countdown,
		"animation_direction": _animation_direction,
		"hit_flash_countdown": _hit_flash_countdown,
		"health": _health,
		"max_health": _maximum_health,
		"only_blue_coins_active": _only_blue_coins_active,
		"tick": _tick,
		"now_ms": _now_ms,
		"mode": _mode,
		"coop_balance": _coop_balance,
		"difficulty": _difficulty,
		"hum_active": _hum_active,
		"hum_pitch": _hum_pitch,
		"hum_pitch_delta": _hum_pitch_delta,
		"hum_pitch_lower": _hum_pitch_lower,
		"hum_pitch_upper": _hum_pitch_upper,
		"hit_sound_deadline_ms": _hit_sound_deadline_ms,
		"terminal_hit_sound_deadline_ms": _terminal_hit_sound_deadline_ms,
		"death_sound_deadline_ms": _death_sound_deadline_ms,
		"next_event_id": _next_event_id,
		"pending_events": _pending_events.duplicate(true),
		"rng": _rng_source.snapshot() if _rng_source != null else {},
	}


func get_last_error() -> String:
	return _last_error


func is_active() -> bool:
	return _active


func is_defeated() -> bool:
	return _defeated


func _validate_level(level: Dictionary) -> bool:
	var level_id := int(_contract.get("level_id", 0))
	if not level.has("authored_lvd") or not level.authored_lvd is Dictionary:
		return _set_error("state-13 level %d is missing authored_lvd" % level_id)
	var authored := level.authored_lvd as Dictionary
	var mode_id := int(_contract.get("level_mode_id", LEVEL_MODE_ID))
	if int(authored.get("level_mode_id", 0)) != mode_id:
		return _set_error("state-13 level %d has the wrong authored mode" % level_id)
	var payload_binding := _contract.get("authored_level_payload", {}) as Dictionary
	var payload_sha := String(payload_binding.get("sha256", ""))
	var path_contract := _contract.get("path", {}) as Dictionary
	var opcode_allowlist: Array[int] = []
	for opcode_value in path_contract.get("opcode_allowlist", []):
		opcode_allowlist.append(int(opcode_value))
	if (
		String(payload_binding.get("canonicalization", ""))
		!= AUTHORED_PAYLOAD_CANONICALIZATION
		or CatalogScript.canonical_authored_lvd_sha256(
			authored,
			level_id,
			true,
			opcode_allowlist
		)
		!= payload_sha
	):
		return _set_error(
			"authored payload does not match the pinned state-13 contract for level %d"
			% level_id
		)
	var resources: Array = level.get("enemy_resources", [])
	var resource_contract := _contract.get("resources", {}) as Dictionary
	var expected_sheets := resource_contract.get("sheet_ids", []) as Array
	var expected_slots := resource_contract.get("slots", []) as Array
	if resources.size() != expected_sheets.size():
		return _set_error("state-13 level must bind its exact boss sheet count")
	for resource_index in range(expected_sheets.size()):
		var resource := resources[resource_index] as Dictionary
		if (
			int(resource.get("resource_slot_id", 0)) != int(expected_slots[resource_index])
			or String(resource.get("enemy_sheet_id", ""))
			!= String(expected_sheets[resource_index])
		):
			return _set_error("state-13 boss sheet bindings are out of order")

	_groups_by_mode.clear()
	_groups_by_id.clear()
	var modes: Array[int] = []
	for group_value in authored.get("groups", []):
		if not group_value is Dictionary:
			return _set_error("state-13 level contains a non-object group")
		var group := group_value as Dictionary
		var mode := int(group.get("group_mode_id", 0))
		modes.append(mode)
		_groups_by_id[int(group.get("id", -1))] = group
		if not _groups_by_mode.has(mode):
			_groups_by_mode[mode] = []
		(_groups_by_mode[mode] as Array).append(group)
		if mode in [GROUP_MODE_ENTRY, GROUP_MODE_LOOP]:
			for point_value in group.get("path_points", []):
				var opcode := int((point_value as Dictionary).get("opcode", -1))
				if not opcode_allowlist.has(opcode):
					return _set_error("state-13 level uses an untraced boss path opcode")
	var initialization := _contract.get("initialization", {}) as Dictionary
	if bool(initialization.get("mirror_x", false)) != bool(authored.get("mirror_x", false)):
		return _set_error("state-13 mirror policy differs from its authored level")
	var expected_modes: Array[int] = []
	for mode_value in initialization.get("group_modes", [4, 5, 6, 7, 7]):
		expected_modes.append(int(mode_value))
	if modes != expected_modes:
		return _set_error("state-13 group mode signature differs from its contract")
	if (_groups_by_mode.get(GROUP_MODE_ENTRY, []) as Array).size() != 1:
		return _set_error("state-13 level must contain one mode-4 entry group")
	if (_groups_by_mode.get(GROUP_MODE_LOOP, []) as Array).size() != 1:
		return _set_error("state-13 level must contain one mode-5 loop group")
	if (_groups_by_mode.get(GROUP_MODE_AIM_ORIGIN, []) as Array).size() != 2:
		return _set_error("state-13 level must contain two mode-7 fire origins")
	var opcode_two := _contract.get("opcode_2", {}) as Dictionary
	var burst_contracts := opcode_two.get("burst_groups", []) as Array
	if burst_contracts.is_empty():
		return _set_error("state-13 opcode-2 contract has no ordered burst groups")
	if (
		(_groups_by_mode.get(GROUP_MODE_BURST, []) as Array).size()
		!= burst_contracts.size()
	):
		return _set_error("state-13 mode-6 burst group count differs from its contract")
	for burst_index in range(burst_contracts.size()):
		var burst_contract := burst_contracts[burst_index] as Dictionary
		var group_id := int(burst_contract.get("group_id", -1))
		if not _groups_by_id.has(group_id):
			return _set_error("state-13 burst contract references a missing group")
		var burst := _groups_by_id[group_id] as Dictionary
		if (
			int(burst.get("group_mode_id", 0)) != GROUP_MODE_BURST
			or int(burst_contract.get("group_mode_id", 0)) != GROUP_MODE_BURST
			or String(burst_contract.get("record_order", "")) != "reverse"
			or burst_contract.get("reverse_records") != true
			or (burst.get("enemies", []) as Array).size()
			!= int(burst_contract.get("authored_record_count", -1))
		):
			return _set_error("state-13 opcode-2 burst group differs from its contract")
		var authored_bursts := _groups_by_mode[GROUP_MODE_BURST] as Array
		if int((authored_bursts[burst_index] as Dictionary).id) != group_id:
			return _set_error("state-13 opcode-2 burst group order differs from authored order")
	var aimed_fire := _contract.get("aimed_fire", {}) as Dictionary
	var origin_contracts := aimed_fire.get("origin_groups", []) as Array
	if not origin_contracts.is_empty():
		if origin_contracts.size() != 2:
			return _set_error("state-13 aimed-fire origin contract must contain two groups")
		for origin_index in range(origin_contracts.size()):
			var origin_contract := origin_contracts[origin_index] as Dictionary
			var origin_group_id := int(origin_contract.get("group_id", -1))
			if not _groups_by_id.has(origin_group_id):
				return _set_error("state-13 aimed-fire contract references a missing group")
			var origin_group := _groups_by_id[origin_group_id] as Dictionary
			if int(origin_group.get("group_mode_id", 0)) != GROUP_MODE_AIM_ORIGIN:
				return _set_error("state-13 aimed-fire origin has the wrong group mode")
			var actual_opcodes: Array[int] = []
			for point_value in origin_group.get("path_points", []):
				actual_opcodes.append(int((point_value as Dictionary).get("opcode", -1)))
			var expected_opcodes: Array[int] = []
			for opcode_value in origin_contract.get("path_opcodes", []):
				expected_opcodes.append(int(opcode_value))
			if actual_opcodes != expected_opcodes:
				return _set_error("state-13 aimed-fire origin path differs from its contract")
	return true


func _update_hum_pitch() -> void:
	_hum_pitch += _hum_pitch_delta
	if _hum_pitch > _hum_pitch_upper:
		_hum_pitch_delta = -_rng_int(10, 100)
		_hum_pitch = _hum_pitch_upper
		_hum_pitch_lower = _rng_int(15000, _hum_pitch_upper)
	elif _hum_pitch < _hum_pitch_lower:
		_hum_pitch_delta = _rng_int(10, 100)
		_hum_pitch = _hum_pitch_lower
		_hum_pitch_upper = _rng_int(_hum_pitch_lower, 30000)
	var slide_roll := _rng_int(0, 1000)
	if slide_roll < 6 and _hum_active:
		var duration := _rng_int(1000, 2000)
		var sounds := _contract.get("sounds", {}) as Dictionary
		_emit("boss_hum", {
			"key": String(sounds.get("hum", "boss")),
			"action": "slide_pitch",
			"pitch": _hum_pitch,
			"duration_ms": duration,
		})


func _append_aim_origin(group: Dictionary) -> void:
	var origin_x := float(group.get("entry_origin_x", 0))
	if _mirror_x:
		origin_x = -origin_x
	_aim_origins.append(Vector2(
		origin_x,
		float(group.get("entry_origin_y", 0)) + 48.0
	))


func _update_aimed_fire(tick_scale: float, players: Array) -> void:
	var aimed_fire := _contract.get("aimed_fire", {}) as Dictionary
	var allocation_contract := _contract.get("projectile_allocation", {}) as Dictionary
	var sounds := _contract.get("sounds", {}) as Dictionary
	var timer := float(aimed_fire.get(
		"runtime_rng_upper",
		aimed_fire.get("timer", AIM_TIMER)
	))
	var trigger_multiplier := float(aimed_fire.get(
		"trigger_multiplier",
		AIM_TRIGGER_MULTIPLIER
	))
	var travel_rng := aimed_fire.get("travel_rng", [AIM_TRAVEL_MIN, AIM_TRAVEL_MAX]) as Array
	var jitter_rng := aimed_fire.get("jitter_rng", [AIM_JITTER_MIN, AIM_JITTER_MAX]) as Array
	var projectile_size := int((aimed_fire.get(
		"size",
		[BOSS_PROJECTILE_SIZE, BOSS_PROJECTILE_SIZE]
	) as Array)[0])
	var center_offset := allocation_contract.get(
		"center_offset",
		[BOSS_PROJECTILE_CENTER_OFFSET, BOSS_PROJECTILE_CENTER_OFFSET]
	) as Array
	var broadphase_inset := aimed_fire.get(
		"broadphase_inset",
		[TYPE_15_BROADPHASE_INSET, TYPE_15_BROADPHASE_INSET]
	) as Array
	var broadphase := aimed_fire.get(
		"broadphase",
		[TYPE_15_BROADPHASE_EXTENT, TYPE_15_BROADPHASE_EXTENT]
	) as Array
	var retirement := allocation_contract.get("retirement", {}) as Dictionary
	var projectile_type := int(aimed_fire.get("projectile_type", 15))
	for origin in _aim_origins:
		var eligibility := _rng_float(0.0, timer)
		if eligibility >= _f32(tick_scale * trigger_multiplier):
			continue
		var travel := _f32(
			_rng_float(float(travel_rng[0]), float(travel_rng[1]))
			* float(DIFFICULTY_AIM_SCALE[_difficulty])
		)
		if travel == 0.0:
			travel = 1.0
		var target := _select_target(players)
		var target_x := _player_coordinate(target, "retail_left", "x", 20.0) - _rng_float(
			float(jitter_rng[0]),
			float(jitter_rng[1])
		)
		var target_y := _player_coordinate(target, "retail_top", "y", 14.0) - _rng_float(
			float(jitter_rng[0]),
			float(jitter_rng[1])
		)
		var retail_left := _f32(_x + origin.x)
		var retail_top := _f32(_y + origin.y)
		# FUN_00612fc7 first reserves a common slot and writes only its active
		# marker/top-left. The visual effect RNG occurs before the remaining
		# projectile record is initialized.
		var allocation := _allocate({
			"owner_kind": "boss",
			"enemy_projectile_type": projectile_type,
			"retail_left": retail_left,
			"retail_top": retail_top,
			"reservation_phase": "active_and_top_left",
		})
		if _blocked:
			return
		if not bool(allocation.get("allocated", false)):
			continue
		var effect_angle := _rng_float(0.0, 359.0)
		var effect_speed := _rng_float(0.0, 5.0)
		_emit("boss_projectile_effect", {
			"x": retail_left,
			"y": retail_top,
			"angle": effect_angle,
			"speed": effect_speed,
		})
		var animation_frame := int(allocation.retained_animation_frame)
		var projectile := {
			"owner_kind": "boss",
			"enemy_projectile_type": projectile_type,
			"retail_left": retail_left,
			"retail_top": retail_top,
			"top_left_x": retail_left,
			"top_left_y": retail_top,
			"x": _f32(retail_left + float(center_offset[0])),
			"y": _f32(retail_top + float(center_offset[1])),
			# Retail aims from the state-13 record's base coordinate, then stores
			# the projectile at the mode-7 supplemental origin.
			"velocity_x": _f32(_f32((target_x - _x) / travel) * tick_scale),
			"velocity_y": _f32(_f32((target_y - _y) / travel) * tick_scale),
			"velocity_is_tick_scaled": true,
			"width": projectile_size,
			"height": projectile_size,
			"resource_slot_id": int(allocation_contract.get(
				"resource_slot_id",
				BOSS_PROJECTILE_RESOURCE_SLOT
			)),
			"enemy_sheet_id": String(allocation_contract.get(
				"enemy_sheet_id",
				BOSS_PROJECTILE_SHEET
			)),
			"mask_id": String(allocation_contract.get(
				"mask_id",
				BOSS_PROJECTILE_SHEET
			)),
			"source_rect": [
				animation_frame * projectile_size,
				64,
				projectile_size,
				projectile_size,
			],
			"animation_frame": animation_frame,
			"animation_period": float(allocation.retained_animation_period),
			"animation_countdown": float(allocation.retained_animation_countdown),
			"animation_frame_max": 3,
			"animation_source_unclamped": true,
			"broadphase_inset_x": int(broadphase_inset[0]),
			"broadphase_inset_y": int(broadphase_inset[1]),
			"broadphase_width": int(broadphase[0]),
			"broadphase_height": int(broadphase[1]),
			"retire_top_left_y_strictly_above": int(retirement.get(
				"default_surface_height",
				BOSS_PROJECTILE_SURFACE_HEIGHT
			)),
			"damage_fp": FP_ONE,
			"damage_policy": "one_armour_step",
			"consume_on_player_hit": true,
		}
		projectile.merge(_allocation_identity(allocation), true)
		if not _finalize(projectile):
			return
		var sound_frequency_rng := aimed_fire.get(
			"sound_frequency_rng",
			[28000, 32000]
		) as Array
		var frequency := _rng_int(
			int(sound_frequency_rng[0]),
			int(sound_frequency_rng[1])
		)
		_emit("boss_projectile_spawned", projectile)
		_emit("sound", {
			"key": String(sounds.get("aimed_projectile", "bigsmall")),
			"frequency": frequency,
		})


func _select_target(players: Array) -> Dictionary:
	if players.is_empty():
		return {
			"retail_left": 380.0,
			"retail_top": 550.0,
			"active": false,
			"alive": false,
		}
	var index := 0
	if _mode == "coop" and players.size() > 1:
		index = _rng_int(0, 2)
		if not _player_is_alive(players[index] as Dictionary):
			index = 1 - index
	return players[clampi(index, 0, players.size() - 1)] as Dictionary


func _update_animation(tick_scale: float) -> void:
	var animation := _contract.get("animation", {}) as Dictionary
	var frame_count := int(animation.get("stage_count", ANIMATION_FRAME_COUNT))
	_animation_countdown = _f32(_animation_countdown - tick_scale)
	if _animation_countdown < 0.0:
		_animation_countdown = _animation_period
		_animation_frame += _animation_direction
		if _animation_frame >= frame_count:
			_animation_frame = 0
		elif _animation_frame < 0:
			_animation_frame = frame_count - 1


func _update_path(tick_scale: float) -> void:
	if _interpolating:
		var path_contract := _contract.get("path", {}) as Dictionary
		var loop_ease := float(path_contract.get("loop_ease", LOOP_EASE))
		_x = _f32(_anchor_x + _f32((_x - _anchor_x) * loop_ease))
		_y = _f32(_anchor_y + _f32((_y - _anchor_y) * loop_ease))
		if (
			abs(int(_x - _anchor_x)) < tick_scale
			and abs(int(_y - _anchor_y)) < tick_scale
		):
			_x = _anchor_x
			_y = _anchor_y
			_interpolating = false
			_restart_loop_group()
		return

	_x = _f32(_x + _f32(_velocity_x * tick_scale))
	_y = _f32(_y + _f32(_velocity_y * tick_scale))
	_velocity_x = _f32(_velocity_x + _f32(_acceleration_x * tick_scale))
	_velocity_y = _f32(_velocity_y + _f32(_acceleration_y * tick_scale))
	_path_progress = _f32(_path_progress + tick_scale)
	var group := _groups_by_id[_current_group_id] as Dictionary
	var point := _path_point(group, _path_index)
	if int(_path_progress) <= int(point.get("duration_threshold_ticks", 0)):
		return
	_path_index += 1
	var next_point := _path_point(group, _path_index)
	if bool(next_point.get("sentinel", false)):
		if int(group.group_mode_id) == GROUP_MODE_ENTRY:
			_anchor_x = _x
			_anchor_y = _y
			_restart_loop_group()
		return
	var opcode := int(next_point.get("opcode", 0))
	match opcode:
		1:
			_velocity_x = 0.0
			_velocity_y = 0.0
			_acceleration_x = 0.0
			_acceleration_y = 0.0
			_path_progress = 0.0
			return
		2:
			_fire_opcode_two_burst(tick_scale)
			if _blocked:
				return
		3:
			# The authored level-50 opcode only enables mode-7 aimed fire. It
			# consumes no RNG, does not load this point's acceleration, and does
			# not reset path progress.
			_aim_enabled = true
			return
		7:
			_interpolating = true
			_velocity_x = absf(_velocity_x)
			_velocity_y = absf(_velocity_y)
			_acceleration_x = 0.0
			_acceleration_y = 0.0
			_path_progress = 0.0
			return
	_set_acceleration_from_path_point(next_point)
	_path_progress = 0.0


func _restart_loop_group() -> void:
	var loop_group := _group_for_mode(GROUP_MODE_LOOP)
	_current_group_id = int(loop_group.id)
	_path_index = 0
	_path_progress = 0.0
	_velocity_x = _f32(
		(-1.0 if _mirror_x else 1.0)
		* float(loop_group.initial_velocity_x_milli) / 1000.0
	)
	_velocity_y = _f32(float(loop_group.initial_velocity_y_milli) / 1000.0)
	_set_acceleration_from_path_point(_path_point(loop_group, 0))


func _fire_opcode_two_burst(tick_scale: float) -> void:
	var opcode_two := _contract.get("opcode_2", {}) as Dictionary
	for burst_value in opcode_two.get("burst_groups", []):
		var burst_contract := burst_value as Dictionary
		var group_id := int(burst_contract.get("group_id", -1))
		if not _groups_by_id.has(group_id):
			_blocked = true
			_active = false
			_set_error("opcode-2 burst contract references a missing authored group")
			return
		_fire_opcode_two_group(
			_groups_by_id[group_id] as Dictionary,
			burst_contract,
			opcode_two,
			tick_scale
		)
		if _blocked:
			return


func _fire_opcode_two_group(
	burst_group: Dictionary,
	burst_contract: Dictionary,
	opcode_two: Dictionary,
	tick_scale: float
) -> void:
	var records := burst_group.enemies as Array
	var allocation_contract := _contract.get("projectile_allocation", {}) as Dictionary
	var sounds := _contract.get("sounds", {}) as Dictionary
	var speed := _f32(float(burst_contract.get(
		"speed",
		float((records[0] as Dictionary).base_health)
		/ float(burst_contract.get("speed_from_first_health_divisor", 10))
	)))
	var spawn_offset_y := float(opcode_two.get("spawn_offset_y", BURST_SPAWN_Y_OFFSET))
	var projectile_size := int((opcode_two.get(
		"size",
		[BOSS_PROJECTILE_SIZE, BOSS_PROJECTILE_SIZE]
	) as Array)[0])
	var center_offset := allocation_contract.get(
		"center_offset",
		[BOSS_PROJECTILE_CENTER_OFFSET, BOSS_PROJECTILE_CENTER_OFFSET]
	) as Array
	var broadphase_inset := opcode_two.get(
		"broadphase_inset",
		[TYPE_14_BROADPHASE_INSET, TYPE_14_BROADPHASE_INSET]
	) as Array
	var broadphase := opcode_two.get(
		"broadphase",
		[TYPE_14_BROADPHASE_EXTENT, TYPE_14_BROADPHASE_EXTENT]
	) as Array
	var source_rects := opcode_two.get("source_rects", TYPE_14_SOURCE_RECTS) as Array
	var initial_source_rect := source_rects[0] as Array
	var retirement := allocation_contract.get("retirement", {}) as Dictionary
	var origin_x := float(burst_group.entry_origin_x)
	if _mirror_x:
		origin_x = -origin_x
	var retail_left := _f32(_x + origin_x)
	var retail_top := _f32(_y + float(burst_group.entry_origin_y) + spawn_offset_y)
	var pending_shot_frequency: Variant = null
	for record_index in range(records.size() - 1, -1, -1):
		var record := records[record_index] as Dictionary
		var vector_x := float(record.formation_target_x)
		if _mirror_x:
			vector_x = -vector_x
		var vector := Vector2(
			vector_x,
			float(record.formation_target_y)
		)
		var length := vector.length()
		if length <= 0.0:
			continue
		var projectile := {
			"owner_kind": "boss",
			"enemy_projectile_type": int(opcode_two.get("projectile_type", 14)),
			"source_group_id": int(burst_group.id),
			"source_record_index": record_index,
			"retail_left": retail_left,
			"retail_top": retail_top,
			"top_left_x": retail_left,
			"top_left_y": retail_top,
			"x": _f32(retail_left + float(center_offset[0])),
			"y": _f32(retail_top + float(center_offset[1])),
			"velocity_x": _f32(vector.x / length * speed * tick_scale),
			"velocity_y": _f32(vector.y / length * speed * tick_scale),
			"velocity_is_tick_scaled": true,
			"width": projectile_size,
			"height": projectile_size,
			"resource_slot_id": int(allocation_contract.get(
				"resource_slot_id",
				BOSS_PROJECTILE_RESOURCE_SLOT
			)),
			"enemy_sheet_id": String(allocation_contract.get(
				"enemy_sheet_id",
				BOSS_PROJECTILE_SHEET
			)),
			"mask_id": String(allocation_contract.get(
				"mask_id",
				BOSS_PROJECTILE_SHEET
			)),
			"source_rect": [
				int(initial_source_rect[0]),
				int(initial_source_rect[1]),
				int(initial_source_rect[2]),
				int(initial_source_rect[3]),
			],
			"animation_frame": 0,
			"animation_frame_max": 5,
			"animation_source_unclamped": false,
			"broadphase_inset_x": int(broadphase_inset[0]),
			"broadphase_inset_y": int(broadphase_inset[1]),
			"broadphase_width": int(broadphase[0]),
			"broadphase_height": int(broadphase[1]),
			"retire_top_left_y_strictly_above": int(retirement.get(
				"default_surface_height",
				BOSS_PROJECTILE_SURFACE_HEIGHT
			)),
			"damage_fp": FP_ONE,
			"damage_policy": "one_armour_step",
			"consume_on_player_hit": true,
		}
		var allocation := _allocate(projectile)
		if _blocked:
			return
		if not bool(allocation.get("allocated", false)):
			break
		var animation := opcode_two.get("animation", {}) as Dictionary
		var period_rng := animation.get("period_rng", [1, 4]) as Array
		var countdown_rng := animation.get("countdown_rng", [1, 4]) as Array
		projectile["animation_period"] = float(_rng_int(
			int(period_rng[0]) - 1,
			int(period_rng[1]) - 1
		) + 1)
		projectile["animation_countdown"] = float(_rng_int(
			int(countdown_rng[0]) - 1,
			int(countdown_rng[1]) - 1
		) + 1)
		var projectile_frequency_rng := opcode_two.get(
			"projectile_sound_frequency_rng",
			[24000, 30000]
		) as Array
		pending_shot_frequency = _rng_int(
			int(projectile_frequency_rng[0]),
			int(projectile_frequency_rng[1])
		)
		projectile.merge(_allocation_identity(allocation), true)
		if not _finalize(projectile):
			return
		_emit("boss_projectile_spawned", projectile)
	var effect_angle := _rng_float(0.0, 359.0)
	var effect_speed := _rng_float(0.0, 5.0)
	var burst_frequency_rng := opcode_two.get(
		"burst_sound_frequency_rng",
		[28000, 32000]
	) as Array
	var burst_frequency := _rng_int(
		int(burst_frequency_rng[0]),
		int(burst_frequency_rng[1])
	)
	_emit("boss_burst_effect", {
		"source_group_id": int(burst_group.id),
		"x": retail_left,
		"y": retail_top,
		"angle": effect_angle,
		"speed": effect_speed,
	})
	_emit("sound", {
		"key": String(sounds.get("opcode_2_direct", "bigfire")),
		"frequency": burst_frequency,
	})
	# FUN_00614031 overwrites one deferred global cue for every allocated shot.
	# The final cue reaches FUN_00567990 only later in the same main tick, after
	# bigfire, and that root-owned flush is gated to alternating updates.
	if pending_shot_frequency != null:
		_emit("boss_deferred_sound", {
			"source_group_id": int(burst_group.id),
			"key": String(sounds.get("opcode_2_deferred", "alienshoot2")),
			"frequency": int(pending_shot_frequency),
			"retail_left": retail_left,
			"retail_top": retail_top,
			"overwrite": "last_allocated_wins",
			"flush_gate": "alternating_global_sound_tick",
			"discard_if_gate_closed": true,
			"spatial_lookup": "FUN_00627530_then_af6048",
			"x_clamp_uses_surface_height": true,
		})


func _emit_terminal_hit_effect(now_ms: int) -> bool:
	if _terminal_hit_sound_deadline_ms < now_ms:
		_terminal_hit_sound_deadline_ms = now_ms + _rng_int(100, 300)
		var sounds := _contract.get("sounds", {}) as Dictionary
		_emit("sound", {
			"key": String(sounds.get("terminal_hit", "hit2")),
			"frequency": _rng_int(25000, 44100),
			"deadline_ms": _terminal_hit_sound_deadline_ms,
			"volume": 200,
		})
	var y := _f32(_y + 16.0 + float(_rng_int(0, 96)))
	var x := _f32(_x - 128.0 + float(_rng_int(0, 224)))
	var count := _rng_int(10, 20)
	return _call_effect("FUN_005defe0", {
		"kind": "boss_terminal_hit_smoke",
		"x": x,
		"y": y,
		"count": count,
	})


func _defeat(owner_seat_id: int, rank_ready: bool) -> void:
	var sounds := _contract.get("sounds", {}) as Dictionary
	var reward := _contract.get("reward", {}) as Dictionary
	var level_id := int(_contract.get("level_id", LEVEL_ID))
	var explosion_count := _rng_int(8, 15)
	for explosion_index in range(explosion_count):
		var y := _f32(_y + float(_rng_int(-32, 32)))
		var x := _f32(_x - 128.0 + float(_rng_int(64, 192)))
		if not _call_effect("FUN_00570420", {
			"kind": "boss_death_small_explosion",
			"index": explosion_index,
			"x": x,
			"y": y,
			"owner_seat_id": owner_seat_id,
			"rank_ready": rank_ready,
		}):
			return

	# Retail clears the state-13 alien record before the remaining large effects.
	_active = false
	_defeated = true
	if not _call_effect("FUN_00571080", {
		"kind": "boss_death_flash",
		"x": _x,
		"y": _y,
		"flags": [1, 1],
		"only_blue_coins_active": _only_blue_coins_active,
	}):
		return
	if not _call_effect("FUN_005e0650", {
		"kind": "boss_death_burst_left",
		"x": _x - 128.0,
		"y": _y,
		"size": [256, 128],
		"palette": [255, 200, 255],
		"variant": 1,
	}):
		return
	if not _call_effect("FUN_005e0650", {
		"kind": "boss_death_burst_right",
		"x": _x - 128.0,
		"y": _y - 32.0,
		"size": [256, 128],
		"palette": [255, 0, 0],
		"variant": 0,
	}):
		return
	if not _call_effect("FUN_0052f440", {
		"kind": "boss_death_particles",
		"x": _x,
		"y": _y + 64.0,
		"count": 500,
		"palette": [100, 255, 100],
	}):
		return
	for smoke_index in range(2):
		var smoke_y := _f32(_y + 16.0 + _rng_float(0.0, 96.0))
		var smoke_x := _f32(_x - 128.0 + _rng_float(0.0, 224.0))
		var smoke_count := _rng_int(50, 100)
		if not _call_effect("FUN_005defe0", {
			"kind": "boss_death_smoke",
			"index": smoke_index,
			"x": smoke_x,
			"y": smoke_y,
			"count": smoke_count,
		}):
			return

	if _death_sound_deadline_ms < _now_ms:
		_death_sound_deadline_ms = _now_ms + _rng_int(40, 200)
		for frequency_bounds in [[35000, 44100], [30000, 40000], [25000, 30000]]:
			var retail_pan_bug := _rng_int(216, 190)
			var frequency := _rng_int(int(frequency_bounds[0]), int(frequency_bounds[1]))
			_emit("sound", {
				"key": String(sounds.get("death", "explo4")),
				"retail_pan_bug": retail_pan_bug,
				"frequency": frequency,
			})
	_emit("boss_reward", {
		"owner_seat_id": owner_seat_id,
		"base_score": int(reward.get("base_score", BASE_REWARD_SCORE)),
		"apply_active_score_multiplier": true,
	})
	_emit("score_popup", {
		"owner_seat_id": owner_seat_id,
		"base_score": int(reward.get("base_score", BASE_REWARD_SCORE)),
		"x": 400,
		"y": 300,
	})
	_emit("boss_level_complete_mark", {
		"owner_seat_id": owner_seat_id,
		"level_id": level_id,
		"increment_killer_destroyed_count": 1,
		"classic_coop_partner_delta": 1,
		"completion_condition": "destroyed_plus_partner>=authored_total",
		"completion_timestamp": "set_if_zero",
		"ordinary_completion_bonus_and_rockets": true,
		"rank_markers_unchanged": true,
		"route_at_dispatcher_tail": true,
	})
	_hum_active = false
	_emit("boss_hum", {
		"key": String(sounds.get("hum", "boss")),
		"action": "stop",
	})
	_emit("boss_defeated", {
		"owner_seat_id": owner_seat_id,
		"level_id": level_id,
		"retail_next_level_intent": true,
		"campaign_wrapper_policy": "configured_end_level",
	})


func _call_effect(call_name: String, payload: Dictionary) -> bool:
	var response: Variant = _dispatch_effect.call(call_name, payload.duplicate(true), _rng_source)
	if response is Dictionary and bool((response as Dictionary).get("ok", false)):
		var normalized := response as Dictionary
		if typeof(normalized.get("allocated_count")) != TYPE_INT:
			_blocked = true
			_active = false
			return _set_error(
				"retail effect callback omitted its allocated_count response for %s" % call_name
			)
		var allocated_count := int(normalized.allocated_count)
		if allocated_count < 0:
			_blocked = true
			_active = false
			return _set_error(
				"retail effect callback returned a negative allocated_count for %s" % call_name
			)
		if allocated_count > 0:
			var event := {
				"call": call_name,
				"payload": payload.duplicate(true),
				"allocated_count": allocated_count,
			}
			if call_name == "FUN_005dfee0":
				if (
					typeof(normalized.get("frame_period")) != TYPE_INT
					or int(normalized.frame_period) not in [0, 1]
				):
					_blocked = true
					_active = false
					return _set_error(
						"retail type-10 effect callback omitted its exact frame_period"
					)
				event["frame_period"] = int(normalized.frame_period)
			_emit("boss_retail_effect", event)
		return true
	_blocked = true
	_active = false
	return _set_error("retail effect callback failed for %s" % call_name)


func _allocate(projectile: Dictionary) -> Dictionary:
	var response: Variant = _allocate_projectile.call(projectile.duplicate(true))
	if not response is Dictionary:
		return _allocation_error(
			"common projectile allocator returned a non-object response"
		)
	var normalized := (response as Dictionary).duplicate(true)
	if (
		typeof(normalized.get("ok")) != TYPE_BOOL
		or typeof(normalized.get("error")) != TYPE_STRING
	):
		return _allocation_error(
			"common projectile allocator omitted its explicit ok/error response"
		)
	if not bool(normalized.ok):
		var callback_error := String(normalized.error)
		if callback_error.is_empty():
			callback_error = "common projectile allocator reported an unspecified failure"
		return _allocation_error(callback_error)
	if not String(normalized.error).is_empty():
		return _allocation_error(
			"successful projectile allocation response contained an error"
		)
	if typeof(normalized.get("allocated")) != TYPE_BOOL:
		return _allocation_error("common projectile allocator omitted allocated")
	var allocated := bool(normalized.allocated)
	var common_slot := int(normalized.get("common_slot", -1))
	var projectile_id := int(normalized.get("projectile_id", 0))
	if (
		allocated
		and (
			common_slot < 0
			or common_slot >= COMMON_PROJECTILE_SLOT_COUNT
			or projectile_id <= 0
		)
	):
		return _allocation_error(
			"successful projectile allocation must return common_slot 0..99 and projectile_id > 0"
		)
	if not allocated and (common_slot != -1 or projectile_id != 0):
		return _allocation_error(
			"full projectile pool must return common_slot -1 and projectile_id 0"
		)
	if allocated:
		for field in [
			"retained_animation_frame",
			"retained_animation_period",
			"retained_animation_countdown",
		]:
			if (
				not normalized.has(field)
				or typeof(normalized[field]) not in [TYPE_INT, TYPE_FLOAT]
			):
				return _allocation_error(
					"successful projectile allocation omitted numeric %s" % field
				)
	normalized["ok"] = true
	normalized["error"] = ""
	normalized["allocated"] = allocated
	normalized["common_slot"] = common_slot
	normalized["projectile_id"] = projectile_id
	return normalized


func _allocation_error(message: String) -> Dictionary:
	_blocked = true
	_active = false
	_set_error(message)
	return {
		"ok": false,
		"error": message,
		"allocated": false,
		"common_slot": -1,
		"projectile_id": 0,
	}


func _allocation_identity(allocation: Dictionary) -> Dictionary:
	return {
		"allocated": true,
		"common_slot": int(allocation.common_slot),
		"projectile_id": int(allocation.projectile_id),
	}


func _finalize(projectile: Dictionary) -> bool:
	var response: Variant = _finalize_projectile.call(projectile.duplicate(true))
	if not response is Dictionary:
		_blocked = true
		_active = false
		return _set_error("common projectile finalizer returned a non-object response")
	var normalized := response as Dictionary
	if (
		typeof(normalized.get("ok")) != TYPE_BOOL
		or typeof(normalized.get("error")) != TYPE_STRING
	):
		_blocked = true
		_active = false
		return _set_error(
			"common projectile finalizer omitted its explicit ok/error response"
		)
	if not bool(normalized.ok):
		_blocked = true
		_active = false
		var callback_error := String(normalized.error)
		return _set_error(
			callback_error
			if not callback_error.is_empty()
			else "common projectile finalizer reported an unspecified failure"
		)
	if not String(normalized.error).is_empty():
		_blocked = true
		_active = false
		return _set_error(
			"successful projectile finalizer response contained an error"
		)
	return true


func _group_for_mode(mode: int) -> Dictionary:
	return ((_groups_by_mode[mode] as Array)[0] as Dictionary)


func _current_group_mode() -> int:
	if not _groups_by_id.has(_current_group_id):
		return 0
	return int((_groups_by_id[_current_group_id] as Dictionary).group_mode_id)


func _path_point(group: Dictionary, index: int) -> Dictionary:
	var points := group.get("path_points", []) as Array
	if index < 0 or index >= points.size():
		return {
			"sentinel": true,
			"opcode": 0,
			"duration_threshold_ticks": 0,
			"acceleration_x_milli": 0,
			"acceleration_y_milli": 0,
		}
	return points[index] as Dictionary


func _set_acceleration_from_path_point(point: Dictionary) -> void:
	_acceleration_x = _f32(
		(-1.0 if _mirror_x else 1.0)
		* float(point.get("acceleration_x_milli", 0)) / 1000.0
	)
	_acceleration_y = _f32(float(point.get("acceleration_y_milli", 0)) / 1000.0)


func _projectile_coordinate(projectile: Dictionary, preferred: String, fallback: String) -> float:
	if projectile.has(preferred):
		return float(projectile[preferred])
	if projectile.has(preferred + "_fp"):
		return float(projectile[preferred + "_fp"]) / FP_ONE
	if projectile.has(fallback):
		return float(projectile[fallback])
	if projectile.has(fallback + "_fp"):
		return float(projectile[fallback + "_fp"]) / FP_ONE
	return 0.0


func _player_coordinate(
	player: Dictionary,
	retail_key: String,
	center_axis: String,
	center_offset: float
) -> float:
	if player.has(retail_key):
		return float(player[retail_key])
	if player.has(retail_key + "_fp"):
		return float(player[retail_key + "_fp"]) / FP_ONE
	if player.has(center_axis):
		return float(player[center_axis]) - center_offset
	return float(player.get(center_axis + "_fp", 0)) / FP_ONE - center_offset


func _player_is_alive(player: Dictionary) -> bool:
	return bool(player.get("active", true)) and bool(player.get("alive", true))


func _rng_int(minimum: int, maximum: int) -> int:
	# FUN_0052f6e0 performs unsigned 32-bit subtraction and modulus. Keeping this
	# exact preserves the reversed (216,190) death-sound call instead of silently
	# normalizing its bounds.
	var span := (maximum - minimum) & U32_MASK
	if span == 0:
		return minimum
	var raw := int(_rng_source.next_u32()) & U32_MASK
	return _signed_i32((raw % span + minimum) & U32_MASK)


func _rng_float(minimum: float, maximum: float) -> float:
	return _f32(float(_rng_source.next_float32(minimum, maximum)))


func _signed_i32(value: int) -> int:
	var normalized := value & U32_MASK
	return normalized - 0x100000000 if normalized >= 0x80000000 else normalized


func _is_rng_source_valid(source: Variant) -> bool:
	return (
		source != null
		and source.has_method("next_u32")
		and source.has_method("next_float32")
		and source.has_method("snapshot")
	)


func _emit(kind: String, payload: Dictionary) -> void:
	var event := payload.duplicate(true)
	event["event_id"] = _next_event_id
	event["kind"] = kind
	event["tick"] = _tick
	_next_event_id += 1
	_pending_events.append(event)


func _result() -> Dictionary:
	var events := _pending_events.duplicate(true)
	_pending_events.clear()
	return {
		"ok": not _blocked,
		"error": _last_error,
		"events": events,
		"snapshot": snapshot(),
	}


func _error_result(message: String) -> Dictionary:
	_set_error(message)
	var events := _pending_events.duplicate(true)
	_pending_events.clear()
	return {
		"ok": false,
		"error": _last_error,
		"events": events,
		"snapshot": snapshot(),
	}


func _collision_result(hit: bool, damage: float, defeated: bool) -> Dictionary:
	var result := _result()
	result["hit"] = hit
	result["damage"] = damage
	result["defeated"] = defeated
	result["consume_projectile"] = hit
	var reward := _contract.get("reward", {}) as Dictionary
	result["base_reward_score"] = (
		int(reward.get("base_score", BASE_REWARD_SCORE)) if defeated else 0
	)
	result["completion_marked"] = defeated
	return result


func _collision_error(message: String) -> Dictionary:
	var result := _error_result(message)
	result["hit"] = false
	result["damage"] = 0.0
	result["defeated"] = false
	result["consume_projectile"] = false
	result["base_reward_score"] = 0
	result["completion_marked"] = false
	return result


func _set_error(message: String) -> bool:
	_last_error = message
	return false


static func _contract_value_matches(actual: Variant, expected: Variant) -> bool:
	if expected is Dictionary:
		if not actual is Dictionary:
			return false
		var actual_dictionary := actual as Dictionary
		var expected_dictionary := expected as Dictionary
		if actual_dictionary.size() != expected_dictionary.size():
			return false
		for key_value in expected_dictionary.keys():
			if (
				not actual_dictionary.has(key_value)
				or not _contract_value_matches(
					actual_dictionary[key_value],
					expected_dictionary[key_value]
				)
			):
				return false
		return true
	if expected is Array:
		if not actual is Array:
			return false
		var actual_array := actual as Array
		var expected_array := expected as Array
		if actual_array.size() != expected_array.size():
			return false
		for index in range(expected_array.size()):
			if not _contract_value_matches(actual_array[index], expected_array[index]):
				return false
		return true
	match typeof(expected):
		TYPE_INT, TYPE_FLOAT:
			return typeof(actual) in [TYPE_INT, TYPE_FLOAT] and float(actual) == float(expected)
		TYPE_BOOL:
			return typeof(actual) == TYPE_BOOL and bool(actual) == bool(expected)
		TYPE_STRING, TYPE_STRING_NAME:
			return typeof(actual) in [TYPE_STRING, TYPE_STRING_NAME] and str(actual) == str(expected)
		_:
			return actual == expected


static func _f32(value: float) -> float:
	var storage := PackedFloat32Array([value])
	return float(storage[0])
