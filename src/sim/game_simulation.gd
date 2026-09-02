class_name GameSimulation
extends RefCounted

const Fixed := preload("res://src/sim/fixed_point.gd")
const Rng := preload("res://src/sim/deterministic_rng.gd")
const Catalog := preload("res://src/sim/content_catalog.gd")
const HitMask := preload("res://src/sim/hit_mask_atlas.gd")
const SpriteFrameCatalogScript := preload("res://src/shared/sprite_frame_catalog.gd")
const MatchContract := preload("res://src/shared/match_contract.gd")
const MemoryStationScript := preload("res://src/sim/memory_station_simulation.gd")
const MeteorStormScript := preload("res://src/sim/meteor_storm_simulation.gd")
const GemDropScript := preload("res://src/sim/gem_drop_simulation.gd")
const RetailBigBossScript := preload("res://src/sim/retail_big_boss_simulation.gd")
const RetailBigBossEffectsScript := preload(
	"res://src/sim/retail_big_boss_effect_runtime.gd"
)
const ProtocolContract := preload("res://src/net/protocol_codec.gd")

const TICKS_PER_SECOND: int = 60
const FIELD_WIDTH: int = 800
const FIELD_HEIGHT: int = 600
const FP_ONE: int = 65536

const ACTION_LEFT: int = 1
const ACTION_RIGHT: int = 2
const ACTION_FIRE: int = 4
const ACTION_CONFIRM: int = 8
const ACTION_CANCEL: int = 16
const ACTION_READY: int = 32
const ACTION_UP: int = 64
const ACTION_DOWN: int = 128
const ACTION_SECONDARY: int = 256
const ACTION_MASK_ALL: int = 511

const BONUS_ACTION_SELECT_TILE: int = 1
const BONUS_ACTION_KILL_TIME: int = 2
const BONUS_ACTION_MAX_FUTURE_TICKS: int = 8
const BONUS_ACTION_MAX_OLD_TICKS: int = 120
const BONUS_ACTION_QUEUE_LIMIT: int = 128

const MODE_SOLO: String = "solo"
const MODE_COOP: String = "coop"
const MODE_TIME_TRIAL: String = "time_trial"

# Retail match mode 6 is Time Trial: 0x005bbd6a stores 6 into the mode global
# 0x008f20d8 on the same entry path that arms the match clock.
const TIME_TRIAL_LEVEL_COUNT: int = 15

const PHASE_LEVEL: String = "level"
const PHASE_GET_READY: String = "get_ready"
const PHASE_SHOP: String = "shop"
const PHASE_RANK_PROMOTION: String = "rank_promotion"
const PHASE_BONUS_MODE: String = "bonus_mode"
const PHASE_WARP: String = "warp"
const PHASE_WARP_MALFUNCTION: String = "warp_malfunction"
const PHASE_CREDITS: String = "credits"
const PHASE_COMPLETE: String = "complete"
const PHASE_GAME_OVER: String = "game_over"

# Endless campaign rules are executable-backed; see
# docs/evidence/ENDLESS_PROGRESSION.md and endless_progression.json.
const RETAIL_CREDITS_LEVEL: int = 100
const ENDLESS_STEP_LEVELS: int = 100
const ENDLESS_TIMER_STEP: int = 50
const ENDLESS_TIMER_FLOOR: int = -500
const ENDLESS_SCALE_STEP_NUMERATOR: int = 3
const ENDLESS_SCALE_STEP_DENOMINATOR: int = 25
const ENDLESS_PROJECTILE_STEP_NUMERATOR: int = 41
const ENDLESS_PROJECTILE_STEP_DENOMINATOR: int = 40
const ENDLESS_ORDINARY_HEALTH_STEP: int = 1
const ENDLESS_SUPPLEMENTAL_HEALTH_STEP: int = 5
const ENDLESS_UPDATE_TARGET_BASE: int = 60
const CREDITS_INTERSTITIAL_MIN_TICKS: int = 120

const BALANCE_CLASSIC: String = "classic"
const BALANCE_BALANCED: String = "balanced"

const RETAIL_BIG_BOSS_LEVEL_ID: int = 25
const RETAIL_BIG_BOSS_MODE_ID: int = 4
const RETAIL_BIG_BOSS_HUM_HANDLE: String = "boss:state13"
const RETAIL_BIG_BOSS_PROJECTILE_SHEET: String = "alien_big1_1"
const RETAIL_BIG_BOSS_PROJECTILE_RESOURCE_SLOT: int = 1
const RETAIL_BIG_BOSS_PROJECTILE_SIZE: int = 32
const RETAIL_BIG_BOSS_PROJECTILE_CENTER_OFFSET: int = 16
const RETAIL_BIG_BOSS_PROJECTILE_SURFACE_HEIGHT: int = 600
const ROCKET_PROJECTILE_KIND: String = "rocket_missile"
const ROCKET_SPRITE_SHEET: String = "rocket"
const ROCKET_POOL_CAPACITY: int = 100
const ROCKET_FRAME_SIZE: int = 24
const ROCKET_HEADING_COUNT: int = 32
const ROCKET_ANIMATION_ROWS: int = 3
const ROCKET_DAMAGE_FP: int = 200 * FP_ONE
const ROCKET_LIFETIME_FP: int = 300 * FP_ONE
const ROCKET_SPEED_FP: int = 10 * FP_ONE
# Canonical Q16 projections of the executable's two binary32 movement tables.
# The Y table deliberately preserves retail's duplicate value at headings 18
# and 19; replacing these with runtime trigonometry changes authoritative state.
const ROCKET_HEADING_X_Q16 := [
	0, 12785, 25080, 36410, 46341, 54491, 60547, 64277,
	65536, 64277, 60547, 54491, 46341, 36410, 25080, 12785,
	0, -12785, -25080, -36410, -46341, -54491, -60547, -64277,
	-65536, -64277, -60547, -54491, -46341, -36410, -25080, -12785,
]
const ROCKET_HEADING_Y_Q16 := [
	-65536, -64277, -60547, -54491, -46341, -36410, -25080, -12785,
	0, 12785, 25080, 36410, 46341, 54491, 60547, 64277,
	65536, 64277, 64277, 60547, 54491, 46341, 36410, 25080,
	12785, 0, -12785, -25080, -36410, -46341, -54491, -60547,
]
const RETAIL_BIG_BOSS_SOUND_KEYS := {
	"hit1": "hit1",
	"hit2": "hit2",
	"explo4": "explo4",
	"bigsmall": "bigsmall",
	"bigfire": "bigfire",
}
const RETAIL_BIG_BOSS_EVENT_KINDS: Array[String] = [
	"boss_burst_effect",
	"boss_defeated",
	"boss_deferred_sound",
	"boss_entered",
	"boss_hit",
	"boss_hum",
	"boss_level_complete_mark",
	"boss_music",
	"boss_projectile_effect",
	"boss_projectile_spawned",
	"boss_retail_effect",
	"boss_reward",
	"score_popup",
	"sound",
]
const RETAIL_GLOBAL_SOUND_GATE_INITIAL: int = 4

const PLAYER_WIDTH: int = 40
const PLAYER_HEIGHT: int = 28
const ENEMY_WIDTH: int = 32
const ENEMY_HEIGHT: int = 24
const AUTHORED_ENEMY_SIZE: int = 32
const PLAYER_Y_FP: int = 564 * FP_ONE
const PLAYER_MIN_X_FP: int = 84 * FP_ONE
const PLAYER_MAX_X_FP: int = 716 * FP_ONE
const RESPAWN_TICKS: int = 3 * TICKS_PER_SECOND + 1
const INVULNERABLE_TICKS: int = 3 * TICKS_PER_SECOND + 1
const MAX_FIGHTERS: int = 5
const SIMULATION_SCALE_DENOMINATOR: int = 6
const COMMON_PROJECTILE_SLOT_COUNT: int = 100
const PLAYER_PROJECTILE_SLOT_COUNT: int = 100
const MAX_ENEMY_PROJECTILES: int = COMMON_PROJECTILE_SLOT_COUNT
const BASE_PROJECTILE_CAPACITY: int = 5
const MAX_PROJECTILE_CAPACITY: int = 50
const MAX_ARMOUR_CHARGES: int = 2
const ARMOUR_PROJECTILE_SUPPRESSION_TICKS: int = 4 * TICKS_PER_SECOND + 1
const LEVEL_RESOLUTION_TICKS: int = 180
const GET_READY_TICKS: int = 120
const LEVEL_WATCHDOG_TICKS: int = 45 * TICKS_PER_SECOND
const LEVEL_LIVENESS_UPDATE_LIMIT: int = 600
const SHOP_WARP_TICKS: int = TICKS_PER_SECOND / 2
const RANK_PROMOTION_MINIMUM_TICKS: int = 4 * TICKS_PER_SECOND
const RANK_PROMOTION_TIMEOUT_TICKS: int = 20 * 60 * TICKS_PER_SECOND
const RANK_PROMOTION_PROMPT_BLINK_TICKS: int = 400 * TICKS_PER_SECOND / 1000
const WARP_STAGE_ONE_UPDATES: int = 100
const WARP_STAGE_TWO_UPDATES: int = 200
const WARP_STAGE_THREE_UPDATES: int = 100
const WARP_MALFUNCTION_RESOLUTION_TICKS: int = 3 * TICKS_PER_SECOND
const WARP_SHOP_MINIMUM_MONEY: int = 50
const DEFAULT_RANK_CAP: int = 20
const FULL_RANK_MASK_CASHOUT_SCORE: int = 1000000
const LEVEL_EIGHT_RESULT_HEADER: String = "B O N U S   L E V E L   R E S U L T S"
const LEVEL_EIGHT_PERFECT_REWARDS := [
	10000,
	25000,
	50000,
	100000,
	250000,
	500000,
	1000000,
	2500000,
	5000000,
	10000000,
]
const RANK_NAMES := [
	"ENSIGN",
	"LIEUTENANT",
	"COMMANDER",
	"CAPTAIN",
	"ADMIRAL",
	"ADMIRAL 1 BRONZE STAR",
	"ADMIRAL 2 BRONZE STARS",
	"ADMIRAL 3 BRONZE STARS",
	"ADMIRAL 1 SILVER STAR",
	"ADMIRAL 2 SILVER STARS",
	"ADMIRAL 3 SILVER STARS",
	"ADMIRAL 1 GOLD STAR",
	"ADMIRAL 2 GOLD STARS",
	"ADMIRAL 3 GOLD STARS",
	"WARBLADE KNIGHT",
	"WARBLADE LORD",
	"WARBLADE OVERLORD",
	"WARBLADE GRANDMASTER",
	"WARBLADE GRANDMASTER 1 GOLD STAR",
	"WARBLADE GRANDMASTER 2 GOLD STARS",
	"WARBLADE GRANDMASTER 3 GOLD STARS",
	"WARBLADE CHAMPION",
	"WARBLADE GOD",
]
const RANK_BADGE_Y := [
	0, 13, 26, 39, 52, 52, 52, 52, 52, 52, 52, 52, 52, 52,
	65, 78, 91, 104, 104, 104, 104, 117, 130,
]
const GROUP_COMPLETION_SCORE: int = 10000
const COHORT_INITIAL_COMPLETION_SCORE: int = 2000
# Letter awards (docs/evidence/LETTER_AWARDS.md, dispatcher 0x00571c60).
const LETTER_COLLECT_SCORE := 100
const LETTER_SEQUENCE_SUPER_SCORE := 5000000
const LETTER_ALL_COLLECTED_SCORE := 1000000
const LETTER_ALL_COLLECTED_BONUS_TIME := 10
const LETTER_FORWARD_SEQUENCE := ["E", "X", "T", "R", "A"]
# End-of-game tally (docs/evidence/GAME_BONUS_TALLY.md).
const TALLY_CASH_POINTS_PER_MONEY := 100
const TALLY_PERFECT_POINTS := 100000
const TALLY_HIT_PERCENT_POINTS := 1000
const TALLY_RANK_BONUS_TABLE := [
	10000, 20000, 30000, 40000, 50000, 60000, 70000, 80000, 90000, 100000,
	200000, 300000, 400000, 500000, 600000, 700000, 800000, 1000000,
	2000000, 3000000, 4000000, 5000000,
	10000000, 10000000, 10000000, 10000000, 10000000,
	10000000, 10000000, 10000000, 10000000, 10000000,
	50000000,
]
const BONUS_POOL_SLOT_COUNT: int = 150
const MAX_MONEY: int = 99990
const AUTO_FIRE_REPEAT_DELAY_MS: int = 100
const SUPER_AUTO_FIRE_REPEAT_DELAY_MS: int = 25
const LASER_ROOT_PROTOTYPE_ID: int = 22
const LASER_FRAME_CHAIN := [22, 23, 24, 50]
const MIRROR_PROJECTILE_CAPACITY: int = 100
# FUN_005e0ab0 maps the equipped fighter weapon through this second weapon
# table for each settled Scoop wingman. These are mapped weapon-table IDs,
# not projectile prototype IDs.
const CAPTIVE_WEAPON_DEFINITIONS := [
	{
		"mapped_weapon_id": 16,
		"damage_fp": 65536,
		"projectiles": [
			{"prototype_id": 48, "offset_x_fp": 0, "offset_y_fp": 0, "velocity_x_fp": 0, "velocity_y_fp": -262144, "width": 2, "height": 5},
		],
	},
	{
		"mapped_weapon_id": 15,
		"damage_fp": 65536,
		"projectiles": [
			{"prototype_id": 47, "offset_x_fp": 0, "offset_y_fp": 0, "velocity_x_fp": 0, "velocity_y_fp": -262144, "width": 12, "height": 5},
		],
	},
	{
		"mapped_weapon_id": 14,
		"damage_fp": 65536,
		"projectiles": [
			{"prototype_id": 45, "offset_x_fp": 0, "offset_y_fp": 0, "velocity_x_fp": -65536, "velocity_y_fp": -327680, "width": 4, "height": 5},
			{"prototype_id": 46, "offset_x_fp": 0, "offset_y_fp": 0, "velocity_x_fp": 65536, "velocity_y_fp": -327680, "width": 4, "height": 5},
		],
	},
	{
		"mapped_weapon_id": 3,
		"damage_fp": 163840,
		"projectiles": [
			{"prototype_id": 4, "offset_x_fp": 327680, "offset_y_fp": 0, "velocity_x_fp": 3932, "velocity_y_fp": -498074, "width": 6, "height": 10},
			{"prototype_id": 63, "offset_x_fp": 983040, "offset_y_fp": 131072, "velocity_x_fp": 13107, "velocity_y_fp": -491520, "width": 6, "height": 10},
			{"prototype_id": 65, "offset_x_fp": -983040, "offset_y_fp": 131072, "velocity_x_fp": -13107, "velocity_y_fp": -491520, "width": 6, "height": 10},
			{"prototype_id": 64, "offset_x_fp": -327680, "offset_y_fp": 0, "velocity_x_fp": -3932, "velocity_y_fp": -498074, "width": 6, "height": 10},
		],
	},
	{
		"mapped_weapon_id": 13,
		"damage_fp": 262144,
		"projectiles": [
			{"prototype_id": 42, "offset_x_fp": 0, "offset_y_fp": 0, "velocity_x_fp": 0, "velocity_y_fp": -393216, "width": 4, "height": 6},
			{"prototype_id": 43, "offset_x_fp": 0, "offset_y_fp": 0, "velocity_x_fp": -65536, "velocity_y_fp": -327680, "width": 5, "height": 6},
			{"prototype_id": 44, "offset_x_fp": 0, "offset_y_fp": 0, "velocity_x_fp": 65536, "velocity_y_fp": -327680, "width": 5, "height": 6},
		],
	},
	{
		"mapped_weapon_id": 11,
		"damage_fp": 196608,
		"projectiles": [
			{"prototype_id": 38, "offset_x_fp": 0, "offset_y_fp": -655360, "velocity_x_fp": 0, "velocity_y_fp": -1507328, "special_secondary_raw": 165, "width": 11, "height": 20},
		],
	},
	{
		"mapped_weapon_id": 17,
		"damage_fp": 196608,
		"projectiles": [
			{"prototype_id": 58, "offset_x_fp": 0, "offset_y_fp": -655360, "velocity_x_fp": 0, "velocity_y_fp": -524288, "special_secondary_raw": 200, "width": 11, "height": 25},
		],
	},
	{
		"mapped_weapon_id": 10,
		"damage_fp": 327680,
		"projectiles": [
			{"prototype_id": 35, "offset_x_fp": 0, "offset_y_fp": -3276800, "velocity_x_fp": 0, "velocity_y_fp": 0, "width": 8, "height": 50},
		],
	},
	{
		"mapped_weapon_id": 12,
		"damage_fp": 327680,
		"projectiles": [
			{"prototype_id": 39, "offset_x_fp": 0, "offset_y_fp": -196608, "velocity_x_fp": 0, "velocity_y_fp": -1572864, "special_secondary_raw": 165, "width": 16, "height": 39},
			{"prototype_id": 40, "offset_x_fp": 0, "offset_y_fp": -196608, "velocity_x_fp": 0, "velocity_y_fp": -1599078, "special_secondary_raw": 163, "width": 16, "height": 39},
			{"prototype_id": 41, "offset_x_fp": 0, "offset_y_fp": -196608, "velocity_x_fp": 0, "velocity_y_fp": -1592525, "special_secondary_raw": 163, "width": 16, "height": 39},
		],
	},
	{
		# The retail selector has a tenth entry even though the current public
		# first-five weapon catalog exposes fighter weapon IDs 0...8 only.
		"mapped_weapon_id": 9,
		"damage_fp": 196608,
		"projectiles": [
			{"prototype_id": 67, "offset_x_fp": 0, "offset_y_fp": 0, "velocity_x_fp": 0, "velocity_y_fp": -1310720, "width": 26, "height": 68},
		],
	},
]
const AUTHORED_ENTITY_SLOT_COUNT: int = 150
const WARP_MALFUNCTION_FILES := [
	["malfunction1", "malfunction4"],
	["malfunction3"],
	["malfunction4"],
	["alien_malfold_blue", "alien_malfold_green"],
]
const WARP_GEM_ROW_Y := [100, 80, 60, 40, 20, 0]
const WARP_GEM_VELOCITY_FP := [
	98304,
	196608,
	262144,
	327680,
	393216,
	458752,
]
const PLATFORM_INITIAL_VELOCITY_FP: int = 32768
const PLATFORM_ACCELERATION_FP: int = 655
const PLATFORM_MIN_X_FP: int = -9 * FP_ONE
const PLATFORM_MAX_X_FP: int = 9 * FP_ONE
const STATE_FOUR_MIN_HORIZONTAL_VELOCITY_FP: int = -4 * FP_ONE
const STATE_FOUR_MAX_HORIZONTAL_VELOCITY_FP: int = 4 * FP_ONE
const STATE_FOUR_ACCELERATION_MIN_FP: int = 655
const STATE_FOUR_ACCELERATION_MAX_FP: int = 13107
const SUPPLEMENTAL_DIRECTION_X_FP := [
	0, 10252, 20252, 29753, 38521, 46341, 53020, 58393, 62328, 64729,
	65536, 64729, 62328, 58393, 53020, 46341, 38521, 29753, 20252, 10252,
	0, -10252, -20252, -29753, -38521, -46341, -53020, -58393, -62328,
	-64729, -65536, -64729, -62328, -58393, -53020, -46341, -38521,
	-29753, -20252, -10252,
]
const SUPPLEMENTAL_DIRECTION_Y_FP := [
	-65536, -64729, -62328, -58393, -53020, -46341, -38521, -29753,
	-20252, -10252, 0, 10252, 20252, 29753, 38521, 46341, 53020, 58393,
	62328, 64729, 65536, 64729, 62328, 58393, 53020, 46341, 38521, 29753,
	20252, 10252, 0, -10252, -20252, -29753, -38521, -46341, -53020,
	-58393, -62328, -64729,
]
# Hurry-up secret ships (docs/evidence/HURRY_UP_SECRET_SHIPS.md). Retail arms a
# per-player deadline from the difficulty timed-effect interval and, once
# ordinary play runs past it, spawns a mothership plus — every eighth wave — the
# money ship. Both raise the level object total, so a level cannot finish while
# one is still on the surface.
const HURRY_UP_MOTHERSHIP_STATE_ID: int = 9
const HURRY_UP_RARE_STATE_ID: int = 12
const HURRY_UP_MOTHERSHIP_STATE: String = "hurry_up_mothership"
const HURRY_UP_RARE_STATE: String = "hurry_up_rare"
const HURRY_UP_BANNER_TEXT: String = "H U R R Y   U P"
const HURRY_UP_BANNER_MS: int = 1000
const HURRY_UP_REARM_MS: int = 10000
const HURRY_UP_ENTRY_COIN_RANGE: int = 100
const HURRY_UP_ENTRY_RIGHT_THRESHOLD: int = 50
const HURRY_UP_VOICE_KEYS: Array[String] = ["hurryup1", "hurryup2"]
const HURRY_UP_PLANET_LIMIT: int = 8
const HURRY_UP_PLANET_MARGIN: int = 128
const HURRY_UP_RARE_PERIOD: int = 8
const HURRY_UP_SPECIAL_SPEED_MINIMUM: float = 2.0
const MOTHERSHIP_SPRITE: String = "mothership2"
const MOTHERSHIP_FRAME_WIDTH: int = 96
const MOTHERSHIP_FRAME_HEIGHT: int = 57
const MOTHERSHIP_FRAME_COUNT: int = 20
const MOTHERSHIP_FRAME_ROWS: int = 8
const MOTHERSHIP_SHEET_WIDTH: int = 288
const MOTHERSHIP_SPAWN_Y: int = 20
const MOTHERSHIP_SCORE: int = 2500
const MOTHERSHIP_DESPAWN_MARGIN: int = 70
const MOTHERSHIP_ANIMATION_INTERVAL_MAXIMUM: float = 4.0
const MOTHERSHIP_HUM_KEY: String = "mothership"
const MONEYSHIP_HUM_KEY: String = "mshiphum"
const MONEYSHIP_SPRITE: String = "moneyship"
const MONEYSHIP_FRAME_SIZE: int = 128
const MONEYSHIP_FRAME_COUNT: int = 10
const MONEYSHIP_SPAWN_Y: int = -110
const MONEYSHIP_SPAWN_X_BASE: int = 100
const MONEYSHIP_SCORE: int = 25000
const MONEYSHIP_HITBOX_EXTENT: int = 100
const MONEYSHIP_WRAP_MARGIN: int = 120
const MONEYSHIP_WRAP_RETURN: int = 110
const MONEYSHIP_ANIMATION_INTERVAL: int = 3
const MONEYSHIP_HEADING_BASE: int = 18
const HURRY_UP_SECRET_ID_MOTHERSHIP: int = 3
const HURRY_UP_SECRET_ID_RARE: int = 6

# The two independently spawned secret ships (gap G20). They share the death
# dispatcher switch with the hurry-up family but have their own spawners, their
# own triggers, and no found-secret record. Both patrol horizontally at a random
# y, both raise the level object total, and both raise the difficulty health
# base they were built from when they die, so each one is tougher than the last.
const MONEY_SUCKER_STATE_ID: int = 11
const GUARD_SHIP_STATE_ID: int = 18
const MONEY_SUCKER_STATE: String = "money_sucker"
const GUARD_SHIP_STATE: String = "guard_ship"
const SECRET_SHIP_SPAWN_Y_BASE: int = 200
const SECRET_SHIP_SPAWN_Y_RANGE: int = 150
const SECRET_SHIP_ENTRY_MARGIN: int = 70
const SECRET_SHIP_DESPAWN_MARGIN: int = 100
const SECRET_SHIP_ENTRY_COIN_RANGE: int = 100
const SECRET_SHIP_ENTRY_RIGHT_THRESHOLD: int = 50
const MONEY_SUCKER_SPRITE: String = "moneysucker2"
const MONEY_SUCKER_FRAME_WIDTH: int = 128
const MONEY_SUCKER_FRAME_HEIGHT: int = 51
const MONEY_SUCKER_FRAME_COUNT: int = 11
const MONEY_SUCKER_HITBOX_HEIGHT: int = 50
const MONEY_SUCKER_CASH_THRESHOLD: int = 750
const MONEY_SUCKER_WEIGHT_DIVISOR: int = 1340
const MONEY_SUCKER_WEIGHT_BASE: int = 3
const MONEY_SUCKER_WEIGHT_RANGE: int = 7
const MONEY_SUCKER_TRIGGER_RANGE: int = 40000
const MONEY_SUCKER_FRAME_GATE_SCALE: float = 7.0
const MONEY_SUCKER_FRAME_GATE_RANGE: float = 200.0
const MONEY_SUCKER_COOLDOWN_MS: int = 120000
const MONEY_SUCKER_SPEED_MINIMUM: float = 0.5
const MONEY_SUCKER_SPEED_MAXIMUM: float = 1.5
const MONEY_SUCKER_HEALTH_STEP: int = 2
const MONEY_SUCKER_HEALTH_ESCALATION: int = 20
const MONEY_SUCKER_DRAIN_GATE_SCALE: float = 10.0
const MONEY_SUCKER_DRAIN_GATE_RANGE: float = 100.0
const MONEY_SUCKER_DRAIN_ANCHOR: int = 48
const MONEY_SUCKER_DRAIN_LEFT_LIMIT: int = 50
const MONEY_SUCKER_DRAIN_RIGHT_MARGIN: int = 50
const MONEY_SUCKER_RENDER_OFFSET_X: int = 60
const MONEY_SUCKER_RENDER_OFFSET_Y: int = 20
## Retail picks the drained coin with one draw whose range widens with the
## victim's cash, then subtracts the matching money pickup's value. The four
## retail bonus ids are 29/30/31/32, which `_apply_retail_bonus_type` already
## pays out as 10/50/100/200.
const MONEY_SUCKER_DRAIN_RANGE_STEPS: Array[int] = [50, 100, 200]
const MONEY_SUCKER_DRAIN_RANGES: Array[int] = [40, 68, 88, 100]
const MONEY_SUCKER_DRAIN_TIER_LIMITS: Array[int] = [40, 67, 87]
const MONEY_SUCKER_DRAIN_BONUS_IDS: Array[int] = [29, 30, 31, 32]
const MONEY_SUCKER_DRAIN_AMOUNTS: Array[int] = [10, 50, 100, 200]
const GUARD_SHIP_SPRITE: String = "guard"
const GUARD_SHIP_FRAME_WIDTH: int = 128
const GUARD_SHIP_FRAME_HEIGHT: int = 64
const GUARD_SHIP_FRAME_COUNT: int = 10
const GUARD_SHIP_MINIMUM_LEVEL: int = 15
const GUARD_SHIP_LEVEL_GAP: int = 10
const GUARD_SHIP_FRAME_GATE_SCALE: float = 20.0
const GUARD_SHIP_FRAME_GATE_RANGE: float = 60000.0
const GUARD_SHIP_TRIGGER_RANGE: int = 20000
const GUARD_SHIP_TRIGGER_THRESHOLD: int = 19500
const GUARD_SHIP_SPEED_MINIMUM: float = 0.30000001192092896
const GUARD_SHIP_SPEED_MAXIMUM: float = 1.0
const GUARD_SHIP_HEALTH_STEP: int = 10
const GUARD_SHIP_HEALTH_ESCALATION: int = 250
const GUARD_BEAM_WINDOW_RANGE: int = 1000
const GUARD_BEAM_WINDOW_THRESHOLD: int = 5
const GUARD_BEAM_WINDOW_MINIMUM: int = 50
const GUARD_BEAM_WINDOW_SPAN: int = 100
const GUARD_BEAM_FIRE_RANGE: int = 99
const GUARD_BEAM_FIRE_THRESHOLD: int = 10
const GUARD_BEAM_COLUMN_OFFSET_Y: int = 30
const GUARD_BEAM_COLUMN_OFFSET_X: int = 64
const GUARD_BEAM_COLUMN_INSET_X: int = 4

# The shared 100-slot effect pool at retail 0x00af7ea4, updated by FUN_00601cd0
# between the collision pass and the motion dispatcher. It is a hazard pool
# rather than a decoration: kind 9 (the mothership's planet debris) homes at the
# fighter on the same 32-direction circle the rockets use, and kind 18 (the
# guard ship's beam) is a static column of segments. Player shots destroy a pool
# object, and a pool object destroys a captive or the fighter it reaches.
const EFFECT_POOL_SLOT_COUNT: int = 100
const EFFECT_KIND_PLANET_DEBRIS: int = 9
const EFFECT_KIND_GUARD_BEAM: int = 18
const PLANET_DEBRIS_SIZE: int = 24
const PLANET_DEBRIS_SPAWN_OFFSET_X: int = 32
const PLANET_DEBRIS_SPAWN_OFFSET_Y: int = 25
const PLANET_DEBRIS_START_HEADING: int = 17
const PLANET_DEBRIS_STEERING_RANGE: int = 102
const PLANET_DEBRIS_WANDER_DOWN_LIMIT: int = 33
const PLANET_DEBRIS_WANDER_UP_LIMIT: int = 66
const PLANET_DEBRIS_HEADING_COUNT: int = 32
const PLANET_DEBRIS_SPRITE: String = "rocket"
const EFFECT_PROXIMITY_DIVISOR: int = 8
const EFFECT_PROXIMITY_BASE: int = 2
const EFFECT_PROXIMITY_CEILING: int = 500
# Retail's quadrant steering table at FUN_00601cd0. The index is a four-bit code
# built from the debris/fighter comparison, so only six entries are reachable.
const PLANET_DEBRIS_QUADRANT_HEADING := [
	0, 0, 0, 0, 0, 0x15, 0xd, 0, 0, 0x1d, 5,
]
const GUARD_BEAM_LIFETIME_FP: int = 5 * FP_ONE
const GUARD_BEAM_Y_OFFSET: int = 30
const GUARD_BEAM_Y_STEP: int = 70
const GUARD_BEAM_WIDTH: int = 64
const GUARD_BEAM_HEIGHT: int = 70
const GUARD_BEAM_SPRITE: String = "beam"

const SHOP_SAVE_VERSION: int = 1
const SHOP_SAVE_SCHEMA: String = "warblade.shop-save.v1"
const SNAPSHOT_VERSION: int = ProtocolContract.SNAPSHOT_VERSION
const REPLAY_VERSION: int = ProtocolContract.REPLAY_VERSION
const HASH_STATE_VERSION: int = ProtocolContract.HASH_STATE_VERSION

var last_error: String = ""

var _configured: bool = false
var _config: Dictionary = {}
var _catalog: Dictionary = {}
var _content_hash: String = ""
var _using_fallback_content: bool = false
# Content v12 talent gating: when a match is talent-enabled, the gated shop
# effects are visible only with the matching license in seat 0's contract.
# All three values are config-derived and immutable for the whole match, so
# replays and saves reproduce them through match_config alone.
var _talents_enabled: bool = false
var _talent_gated_effects: Array = []
var _talent_shop_unlocks: Array = []
var _level_eight_contract: Dictionary = {}
var _levels_by_id: Dictionary = {}
var _time_trial_levels_by_id: Dictionary = {}
var _time_trial_runtime: Dictionary = {}
var _time_trial_deadline_ms: int = 0
var _time_trial_expired: bool = false
var _hurry_up_interval_ms: int = 0
var _hurry_up_deadline_ms: int = 0
var _hurry_up_spawn_counter: int = 0
var _hurry_up_planet_count: int = 1
var _hurry_up_planet_x: Array[int] = []
var _money_sucker_deadline_ms: int = 0
var _guard_previous_level: int = 0
var _guard_beam_window: int = 0
## Retail escalates the difficulty health-base globals themselves, so the change
## outlives the ship that caused it and every later spawn is tougher.
var _special_health_base_b: int = 0
var _special_health_base_d: int = 0
var _effect_pool: Array = []
var _weapons_by_id: Dictionary = {}
var _shop_by_id: Dictionary = {}
var _ordnance_contract: Dictionary = {}
var _swd_paths: Array = []
var _difficulty: Dictionary = {}
var _rng := Rng.new(1)
var _initial_rng_snapshot: Dictionary = {}
var _hit_masks: Dictionary = {}
var _sprite_frames := SpriteFrameCatalogScript.new()
var _memory_station := MemoryStationScript.new()
var _meteor_storm := MeteorStormScript.new()
var _gem_drop := GemDropScript.new()
var _retail_big_boss := RetailBigBossScript.new()
var _retail_big_boss_effects := RetailBigBossEffectsScript.new()
var _boss_runtimes_by_level: Dictionary = {}

var _tick: int = 0
var _level_tick: int = 0
var _level_id: int = 1
var _end_level_id: int = MatchContract.MAX_END_LEVEL
var _base_difficulty: Dictionary = {}
var _endless_step_count: int = 0
var _credits_min_tick: int = 0
var _level_100_milestone_score: int = 0
var _retired := false
var _locked_out_bonus_types: Dictionary = {}
var _phase: String = PHASE_LEVEL
var _mode: String = MODE_SOLO
var _difficulty_id: String = "normal"
var _balance: String = BALANCE_CLASSIC
var _collision_mode: String = "pixel"
var _turn_seat: int = 0
var _input_masks: Array[int] = [0, 0]
var _previous_input_masks: Array[int] = [0, 0]
var _players: Array = []
var _enemies: Array = []
var _projectiles: Array = []
var _secondary_rocket_armed: Array[bool] = [true, true]
var _player_projectile_slot_stale_contributions: Array[int] = []
var _ordinary_projectile_counter_adjustment_by_seat: Array[int] = [0, 0]
var _rocket_effect_until_ms: int = 0
var _rocket_effect_active: bool = false
var _common_projectile_slots: Array = []
var _pickups: Array = []
var _spawned_waves: Dictionary = {}
var _next_entity_id: int = 1
var _shared: Dictionary = {}
var _seat_progression: Array[Dictionary] = []
var _profile_stats_by_seat: Array[Dictionary] = []
var _match_persistent_flags_by_seat: Array[Dictionary] = []
var _shop_ready: Array[bool] = [false, false]
var _purchased_nonces: Dictionary = {}
var _events: Array = []
var _result: Dictionary = {}
var _replay_frames: Array = []
var _record_replay: bool = true
# Hash cadence for recorded replay frames: 1 hashes every tick (the retail
# test contract); online matches use a sparse stride so multi-hour sessions
# stay affordable to record and upload. The frame that turns terminal is
# always hashed so the verifier gets a pinned endpoint.
var _replay_hash_stride: int = 1
var _replay_terminal_hash_recorded: bool = false
var _qualifying_kills_this_tick: int = 0
var _authored_slot_seeds: Array = []
var _authored_spawn_slot: int = 0
var _supplemental_spawned: bool = false
var _next_event_id: int = 1
var _platform_x_fp: int = 0
var _platform_y_fp: int = 0
var _platform_velocity_x_fp: int = PLATFORM_INITIAL_VELOCITY_FP
var _platform_acceleration_x_fp: int = PLATFORM_ACCELERATION_FP
var _tail_cutoff: int = 2
var _level_total_entities: int = 0
var _level_killed_entities: int = 0
var _level_escaped_entities: int = 0
var _level_resolved: bool = false
var _level_resolution_tick: int = 0
var _level_eight_result_initialized: bool = false
var _level_eight_result_deadline_ms: int = 0
var _level_eight_reveal_deadline_ms: int = 0
var _level_eight_reveal_countdown: int = 0
var _level_eight_result_players: Array = []
var _level_eight_perfect_indices: Array[int] = [0, 0]
var _get_ready_until_tick: int = 0
var _pending_level_id: int = 0
var _group_kill_counts: Dictionary = {}
var _group_totals: Dictionary = {}
var _cohort_kill_counts: Dictionary = {}
var _cohort_totals: Dictionary = {}
var _cohort_completion_score: int = COHORT_INITIAL_COMPLETION_SCORE
var _level_watchdog_start_tick: int = 0
var _enemy_liveness_idle_updates: int = 0
var _shop_warp_until_tick: int = 0
var _rank_promotion_seat_id: int = -1
var _rank_promotion_minimum_tick: int = 0
var _rank_promotion_timeout_tick: int = 0
var _rocket_fired_this_level: bool = false
var _alien_projectile_processed_this_level: bool = false
var _rank_full_reward_claimed: bool = false
var _last_secret_id: int = -1
var _previous_secret_id: int = -1
var _bonus_mode_until_tick: int = 0
var _bonus_mode_owner_seat_id: int = -1
var _bonus_action_queue: Array = []
var _bonus_actions_this_tick: Array = []
var _bonus_action_last_target_tick: Array[int] = [-1, -1]
var _bonus_mode_transition_until_ms: int = 0
var _bonus_mode_completion: Dictionary = {}
var _pending_gem_drop_transition: bool = false
var _gem_drop_source_mode: String = ""
var _gem_drop_super: bool = false
var _warp_stage: int = 0
var _warp_stage_updates_remaining: int = 0
var _warp_visual_fp: int = 0
var _warp_scale: float = 0.0
var _warp_velocity: float = 0.0
var _warp_effect: float = 0.0
var _warp_offset: float = 0.0
var _background_draw_offset: float = 0.0
var _background_post_draw_offset: float = 0.0
var _warp_owned_skip: bool = false
var _warp_malfunction_interval: int = 0
var _warp_malfunction_gate_calls: int = 0
var _warp_malfunction_file_id: int = 0
var _warp_malfunction_total: int = 0
var _warp_malfunction_killed: int = 0
var _warp_malfunction_missed: int = 0
var _warp_malfunction_resolution_tick: int = 0
var _warp_malfunction_transition_pending: bool = false
var _warp_malfunction_message_until_tick: int = 0
var _warp_malfunction_message_cadence_tick: int = 0
var _warp_malfunction_message_cadence_remaining: int = 0
var _warp_transition_requested: bool = false
var _warp_request_seat_id: int = 0
var _warp_request_cause: String = ""
var _warp_owner_seat_id: int = -1
var _boss_contract: Dictionary = {}
var _boss_entered: bool = false
var _boss_runtime_blocked: bool = false
var _boss_terminal_route_pending: bool = false
var _boss_completion_marked: bool = false
var _boss_reward_applied: bool = false
var _boss_last_reward_score: int = 0
var _boss_projectile_sheet: String = ""
var _boss_render_snapshot: Dictionary = {}
var _boss_deferred_entry_events: Array[Dictionary] = []
var _boss_destroyed_counts_by_seat: Array[int] = [0, 0]
var _retail_global_sound_gate: int = RETAIL_GLOBAL_SOUND_GATE_INITIAL
var _boss_pending_deferred_sound: Dictionary = {}


func configure(match_config: Dictionary) -> bool:
	last_error = ""
	var mode := String(match_config.get("mode", MODE_SOLO)).to_lower()
	if not [
		MODE_SOLO,
		MODE_COOP,
		MODE_TIME_TRIAL,
	].has(mode):
		return _set_error("unsupported mode")
	var difficulty_id := String(match_config.get("difficulty", "normal")).to_lower()
	var balance := String(match_config.get("coop_balance", BALANCE_CLASSIC)).to_lower()
	if not [BALANCE_CLASSIC, BALANCE_BALANCED].has(balance):
		return _set_error("unsupported co-op balance")
	var collision_mode := String(match_config.get("collision_mode", "pixel")).to_lower()
	if not ["simple", "pixel"].has(collision_mode):
		return _set_error("unsupported collision mode")
	var start_level := int(match_config.get("start_level", 1))

	var base_path := String(match_config.get("content_base_path", "res://content"))
	var expected_hash := String(match_config.get("content_hash", ""))
	var loaded := Catalog.load_catalog(
		base_path,
		expected_hash,
		bool(match_config.get("allow_fallback_content", false))
	)
	if not bool(loaded.get("ok", false)):
		return _set_error(String(loaded.get("error", "content loading failed")))

	_catalog = loaded
	_content_hash = String(loaded.content_hash)
	_using_fallback_content = bool(loaded.using_fallback)
	var talents_document: Dictionary = loaded.get("talents", {})
	_talent_gated_effects = (
		(talents_document.get("shop_migration", {}) as Dictionary).get(
			"talent_gated_effects", []
		) as Array
	).duplicate()
	_talents_enabled = bool(match_config.get("talents_enabled", false)) and mode != MODE_TIME_TRIAL
	_talent_shop_unlocks = []
	var configured_seats: Array = match_config.get("seats", [])
	if not configured_seats.is_empty() and configured_seats[0] is Dictionary:
		for unlock_value: Variant in (
			(configured_seats[0] as Dictionary).get("shop_unlocks", []) as Array
		):
			var unlock_effect := String(unlock_value)
			if unlock_effect in _talent_gated_effects:
				_talent_shop_unlocks.append(unlock_effect)
	_memory_station = MemoryStationScript.new()
	var bonus_modes: Dictionary = loaded.get("bonus_modes", {})
	var mode_three_contract: Variant = bonus_modes.get("mode_three_bonus", {})
	if (
		mode_three_contract is Dictionary
		and not (mode_three_contract as Dictionary).is_empty()
	):
		_level_eight_contract = (mode_three_contract as Dictionary).duplicate(true)
	else:
		_level_eight_contract = bonus_modes.get("level_8_bonus", {}).duplicate(true)
		if not _level_eight_contract.is_empty():
			_level_eight_contract["levels"] = [{
				"level_id": int(_level_eight_contract.get("level_id", 8)),
				"authored_target_count": int(
					_level_eight_contract.get("authored_target_count", 20)
				),
				"authored_enemy_score": int(
					_level_eight_contract.get("rewards", {}).get(
						"authored_enemy_score",
						200
					)
				),
			}]
	var memory_contract: Dictionary = bonus_modes.get(
		"memory_station",
		MemoryStationScript.retail_contract()
	)
	if not _memory_station.configure(memory_contract):
		return _set_error(_memory_station.get_last_error())
	_meteor_storm = MeteorStormScript.new()
	var meteor_contract: Dictionary = bonus_modes.get(
		"meteor_storm",
		MeteorStormScript.retail_contract()
	).duplicate(true)
	meteor_contract["difficulty"] = difficulty_id
	meteor_contract["collision_query"] = Callable(self, "_meteor_collision_query")
	meteor_contract["gem_drop_start_callback"] = Callable(
		self,
		"_meteor_gem_drop_start_callback"
	)
	if not _meteor_storm.configure(meteor_contract):
		return _set_error(_meteor_storm.get_last_error())
	_sprite_frames = SpriteFrameCatalogScript.new()
	var sprite_document: Dictionary = loaded.get("sprites", {})
	if not sprite_document.is_empty():
		if not _sprite_frames.configure(sprite_document):
			return _set_error(_sprite_frames.last_error)
	elif FileAccess.file_exists(SpriteFrameCatalogScript.DEFAULT_PATH):
		if not _sprite_frames.load_file():
			return _set_error(_sprite_frames.last_error)
	_levels_by_id.clear()
	_time_trial_levels_by_id.clear()
	_time_trial_runtime.clear()
	_weapons_by_id.clear()
	_shop_by_id.clear()
	for level in loaded.levels:
		_levels_by_id[int(level.id)] = level
	if mode == MODE_TIME_TRIAL:
		var time_trial_value: Variant = loaded.get("time_trial", {})
		if not time_trial_value is Dictionary or (time_trial_value as Dictionary).is_empty():
			return _set_error("Time Trial requires the mode-6 content catalog")
		var time_trial := time_trial_value as Dictionary
		for time_trial_level_value in time_trial.get("levels", []):
			var time_trial_level := time_trial_level_value as Dictionary
			_time_trial_levels_by_id[int(time_trial_level.id)] = time_trial_level
		if _time_trial_levels_by_id.size() != TIME_TRIAL_LEVEL_COUNT:
			return _set_error("Time Trial requires its fifteen authored levels")
		_time_trial_runtime = (time_trial.get("runtime", {}) as Dictionary).duplicate(true)
		if _time_trial_runtime.is_empty():
			return _set_error("Time Trial requires its runtime contract")
	var maximum_level_id := 0
	for level_id in _levels_by_id:
		maximum_level_id = maxi(maximum_level_id, int(level_id))
	# Levels beyond the authored set resolve through the retail endless cycling
	# rules, so the playable boundary is the retail clamp, not the catalog size.
	var end_level := int(match_config.get("end_level", MatchContract.MAX_END_LEVEL))
	if mode == MODE_TIME_TRIAL:
		# Retail Time Trial always starts on file 1 and only ends when its clock
		# expires, so the configured campaign boundary never applies.
		if start_level != 1:
			return _set_error("Time Trial always starts on its first authored level")
		end_level = MatchContract.MAX_END_LEVEL
	if start_level < 1 or start_level > MatchContract.MAX_END_LEVEL:
		return _set_error("start_level is outside the playable campaign range")
	if end_level < start_level or end_level > MatchContract.MAX_END_LEVEL:
		return _set_error("end_level is outside the playable campaign range")
	_retail_big_boss = RetailBigBossScript.new()
	_retail_big_boss_effects = RetailBigBossEffectsScript.new()
	_boss_runtimes_by_level.clear()
	_boss_contract.clear()
	var bosses: Dictionary = loaded.get("bosses", {})
	var bosses_version := int(loaded.get("bosses_version", 0))
	for contract_key in bosses:
		var contract_id := String(contract_key)
		if RetailBigBossScript.contract_for_id(contract_id).is_empty():
			continue
		var contract_value: Variant = bosses[contract_key]
		if not contract_value is Dictionary or (contract_value as Dictionary).is_empty():
			return _set_error("state-13 boss contract must be a non-empty object")
		var contract := (contract_value as Dictionary).duplicate(true)
		var boss_level_id := int(contract.get("level_id", 0))
		if not _levels_by_id.has(boss_level_id):
			return _set_error("state-13 boss contract references a missing authored level")
		if _boss_runtimes_by_level.has(boss_level_id):
			return _set_error("state-13 boss level is registered more than once")
		var controller := RetailBigBossScript.new()
		if not controller.configure(contract, bosses_version):
			return _set_error(controller.get_last_error())
		var effect_contract_value: Variant = contract.get("effect_runtime", {})
		if (
			not effect_contract_value is Dictionary
			or (effect_contract_value as Dictionary).is_empty()
		):
			return _set_error("retail boss contract is missing its exact effect runtime")
		var effects := RetailBigBossEffectsScript.new()
		if not effects.configure(effect_contract_value as Dictionary):
			return _set_error(effects.get_last_error())
		_boss_runtimes_by_level[boss_level_id] = {
			"contract": contract,
			"controller": controller,
			"effects": effects,
		}
	# Authored mode 4 is state 13 in the recovered level loader. Never let it
	# fall through to the generic enemy runtime without an exact controller.
	for level_value in loaded.levels:
		var authored_value: Variant = (level_value as Dictionary).get("authored_lvd", {})
		if (
			authored_value is Dictionary
			and int((authored_value as Dictionary).get("level_mode_id", 0))
			== RETAIL_BIG_BOSS_MODE_ID
			and not _boss_runtimes_by_level.has(int((level_value as Dictionary).id))
		):
			return _set_error("authored state-13 level requires an exact boss contract")
	_ordnance_contract.clear()
	if maximum_level_id > RETAIL_BIG_BOSS_LEVEL_ID:
		var ordnance_value: Variant = loaded.get("ordnance", {})
		if not ordnance_value is Dictionary:
			return _set_error("late campaign content requires ordnance.json")
		_ordnance_contract = (ordnance_value as Dictionary).duplicate(true)
		if not _validate_ordnance_contract():
			return false
	for weapon in loaded.weapons:
		_weapons_by_id[int(weapon.id)] = weapon
	for item in loaded.shop:
		_shop_by_id[int(item.id)] = item
	_swd_paths = loaded.get("swd_paths", [])
	var found_difficulty := false
	for candidate in loaded.difficulties:
		if String(candidate.id) == difficulty_id:
			_difficulty = candidate
			_base_difficulty = candidate
			found_difficulty = true
			break
	if not found_difficulty:
		return _set_error("unsupported difficulty")
	_gem_drop = GemDropScript.new()
	var gem_drop_contract: Dictionary = bonus_modes.get(
		"gem_drop",
		GemDropScript.retail_contract()
	).duplicate(true)
	gem_drop_contract["tick_scale"] = (
		float(int(_difficulty.simulation_scale_numerator))
		/ float(SIMULATION_SCALE_DENOMINATOR)
	)
	gem_drop_contract["collision_query"] = Callable(self, "_meteor_collision_query")
	gem_drop_contract["pool_reset_callback"] = Callable(
		self,
		"_gem_drop_pool_reset"
	)
	if not _gem_drop.configure(gem_drop_contract):
		return _set_error(_gem_drop.get_last_error())
	if not _weapons_by_id.has(0):
		return _set_error("content is missing the starting weapon")
	var starting_weapon := int(match_config.get("starting_weapon", 0))
	if not _weapons_by_id.has(starting_weapon):
		return _set_error("starting_weapon is unsupported")
	if mode == MODE_TIME_TRIAL and starting_weapon != 0:
		# The retail lock applier gates its weapon tiers on match mode != 6, so
		# Time Trial always begins on the Single Shot.
		return _set_error("Time Trial always starts on the first weapon")
	if collision_mode == "pixel" and not _load_proven_hit_masks():
		return false

	_config = match_config.duplicate(true)
	_config["start_level"] = start_level
	_config["end_level"] = end_level
	_mode = mode
	_difficulty_id = difficulty_id
	_balance = balance
	_collision_mode = collision_mode
	_level_eight_perfect_indices = [
		_level_eight_starting_perfect_index(match_config, 0),
		_level_eight_starting_perfect_index(match_config, 1),
	]
	_tick = 0
	_level_tick = 0
	_level_id = start_level
	_end_level_id = end_level
	_endless_step_count = 0
	_credits_min_tick = 0
	_level_100_milestone_score = 0
	_retired = false
	_time_trial_deadline_ms = 0
	_time_trial_expired = false
	_hurry_up_interval_ms = 0
	_hurry_up_deadline_ms = 0
	_hurry_up_spawn_counter = 0
	_hurry_up_planet_count = 1
	_hurry_up_planet_x = []
	_hurry_up_planet_x.resize(HURRY_UP_PLANET_LIMIT)
	_hurry_up_planet_x.fill(0)
	_money_sucker_deadline_ms = 0
	_guard_previous_level = 0
	_guard_beam_window = 0
	_special_health_base_b = int(_difficulty.get("special_health_base_b", 350))
	_special_health_base_d = int(_difficulty.get("special_health_base_d", 1750))
	_reset_effect_pool()
	_apply_endless_progression()
	_phase = PHASE_LEVEL
	_turn_seat = 0
	_input_masks = [0, 0]
	_previous_input_masks = [0, 0]
	_enemies.clear()
	_projectiles.clear()
	_secondary_rocket_armed = [true, true]
	_player_projectile_slot_stale_contributions.clear()
	_player_projectile_slot_stale_contributions.resize(ROCKET_POOL_CAPACITY)
	_player_projectile_slot_stale_contributions.fill(0)
	_ordinary_projectile_counter_adjustment_by_seat = [0, 0]
	_rocket_effect_until_ms = 0
	_rocket_effect_active = false
	_common_projectile_slots.clear()
	_pickups.clear()
	_spawned_waves.clear()
	_next_entity_id = 1
	_next_event_id = 1
	_shop_ready = [false, false]
	_purchased_nonces.clear()
	_events.clear()
	_result.clear()
	_replay_frames.clear()
	_last_secret_id = -1
	_previous_secret_id = -1
	_bonus_mode_until_tick = 0
	_bonus_mode_owner_seat_id = -1
	_bonus_action_queue.clear()
	_bonus_actions_this_tick.clear()
	_bonus_action_last_target_tick = [-1, -1]
	_bonus_mode_transition_until_ms = 0
	_bonus_mode_completion.clear()
	_pending_gem_drop_transition = false
	_gem_drop_source_mode = ""
	_gem_drop_super = false
	_level_eight_result_initialized = false
	_level_eight_result_deadline_ms = 0
	_level_eight_reveal_deadline_ms = 0
	_level_eight_reveal_countdown = 0
	_level_eight_result_players.clear()
	_reset_rank_promotion_state()
	_reset_warp_runtime_state()
	_record_replay = bool(match_config.get("record_replay", true))
	_replay_hash_stride = maxi(1, int(match_config.get("replay_hash_stride", 1)))
	_replay_terminal_hash_recorded = false
	_rng.seed(int(match_config.get("seed", 1)))
	_initial_rng_snapshot = _rng.snapshot()
	# FUN_005B2F40 seeds the first malfunction denominator before the level
	# loader consumes any common-shot or alien-slot initialization draws.
	_warp_malfunction_interval = 19000 + _random_int(8000)
	_initialize_common_projectile_slots()
	_initialize_level_behavior_state()
	_shared = _create_progression(match_config, starting_weapon, 0)
	_seat_progression = [_shared, _shared]
	_locked_out_bonus_types.clear()
	for progression_value in [_shared, _seat_progression[1]]:
		var start_state_value: Variant = (
			progression_value as Dictionary
		).get("start_state_pending", {})
		if start_state_value is Dictionary:
			for excluded_value in (start_state_value as Dictionary).get(
				"excluded_bonus_types", []
			):
				_locked_out_bonus_types[int(excluded_value)] = true
		_apply_profile_start_state(progression_value as Dictionary)
	_profile_stats_by_seat = [
		_create_profile_stats(match_config, 0),
		_create_profile_stats(match_config, 1),
	]
	_match_persistent_flags_by_seat = [
		_create_match_persistent_flags(match_config, 0),
		_create_match_persistent_flags(match_config, 1),
	]
	_boss_entered = false
	_boss_runtime_blocked = false
	_boss_terminal_route_pending = false
	_boss_completion_marked = false
	_boss_reward_applied = false
	_boss_last_reward_score = 0
	_boss_projectile_sheet = ""
	_boss_render_snapshot.clear()
	_boss_deferred_entry_events.clear()
	_boss_destroyed_counts_by_seat = [0, 0]
	_retail_global_sound_gate = RETAIL_GLOBAL_SOUND_GATE_INITIAL
	_boss_pending_deferred_sound.clear()
	_alien_projectile_processed_this_level = false
	_players = [
		_create_player(0, _player_spawn_x_fp(0)),
		_create_player(1, _player_spawn_x_fp(1)),
	]
	_apply_mode_activity()
	if _mode == MODE_TIME_TRIAL:
		_arm_time_trial_clock()
	if _is_retail_big_boss_level() and not _enter_retail_big_boss(true):
		return false
	_configured = true
	return true


## Retail arms the Time Trial deadline on the same entry path that stores match
## mode 6: `deadline = now + 181000` (0x005bbd74, seven byte-identical sites).
## The grouped-best "+1 minute" lock rewrites the same global with 241000
## (0x0054da6f), and a Time Trial install with no level files clamps the clock
## to `now + 10000` (0x00557115).
func _arm_time_trial_clock() -> void:
	var clock: Dictionary = _time_trial_runtime.get("clock", {})
	var duration_ms := int(clock.get("match_milliseconds", 181000))
	if _time_trial_levels_by_id.is_empty():
		duration_ms = int(clock.get("missing_levels_milliseconds", 10000))
	elif bool(_shared.get("time_trial_extra_minute", false)):
		duration_ms = int(clock.get("grouped_best_extra_minute_milliseconds", 241000))
	_time_trial_deadline_ms = _simulation_milliseconds() + duration_ms
	_time_trial_expired = false


func _time_trial_remaining_ms() -> int:
	if _mode != MODE_TIME_TRIAL:
		return 0
	return maxi(0, _time_trial_deadline_ms - _simulation_milliseconds())


func _step_time_trial_clock() -> void:
	if _mode != MODE_TIME_TRIAL or _time_trial_expired:
		return
	if _phase in [PHASE_COMPLETE, PHASE_GAME_OVER]:
		return
	if _simulation_milliseconds() < _time_trial_deadline_ms:
		return
	_time_trial_expired = true
	_emit_event("time_trial_expired", {
		"level_id": _level_id,
		"score": _result_score(),
	})
	# Clock expiry ends the run through the ordinary game-over path, which owns
	# the GAME BONUSES tally and the hall-of-fame handoff.
	_retire_all_fighters()
	_check_game_over()


func _validate_ordnance_contract() -> bool:
	if not Catalog.ordnance_contract_matches(_ordnance_contract):
		return _set_error("late campaign ordnance contract differs from its exact trace")
	if (
		int(_ordnance_contract.get("version", 0)) != 1
		or String(_ordnance_contract.get("schema", ""))
		!= "warblade.ordnance.v1"
	):
		return _set_error("late campaign ordnance contract version is unsupported")
	var source := _ordnance_contract.get("source", {}) as Dictionary
	var executable := source.get("executable", {}) as Dictionary
	if (
		source.get("exact_trace_complete") != true
		or not (source.get("gameplay_critical_unresolved", []) as Array).is_empty()
		or String(executable.get("sha256", ""))
		!= _state_13_executable_sha256()
	):
		return _set_error("late campaign ordnance trace is incomplete or unpinned")
	var runtime := _ordnance_contract.get("missile_runtime", {}) as Dictionary
	var integration := _ordnance_contract.get("integration", {}) as Dictionary
	var targeting := runtime.get("targeting", {}) as Dictionary
	var spawn := runtime.get("spawn", {}) as Dictionary
	var update := runtime.get("update", {}) as Dictionary
	var rendering := runtime.get("rendering", {}) as Dictionary
	var collision := runtime.get("collision", {}) as Dictionary
	var pool := runtime.get("pool", {}) as Dictionary
	var atlas := rendering.get("atlas", {}) as Dictionary
	var ordinary_collision := collision.get("ordinary_enemy", {}) as Dictionary
	var boss_collision := collision.get("state_13_boss", {}) as Dictionary
	var executable_tables := targeting.get("executable_tables", {}) as Dictionary
	var runtime_constants := executable_tables.get("constants", {}) as Dictionary
	var spawn_record := spawn.get("record", {}) as Dictionary
	var atlas_dimensions := atlas.get("dimensions", []) as Array
	var atlas_frame_size := atlas.get("frame_size", []) as Array
	var fail_closed := integration.get("fail_closed", {}) as Dictionary
	if (
		String(runtime.get("id", "")) != "retail_player_rocket_v1"
		or int(pool.get("capacity", 0)) != ROCKET_POOL_CAPACITY
		or int(runtime_constants.get("damage", 0)) != 200
		or int(spawn_record.get("lifetime_0x60", 0)) != 300
		or int(spawn_record.get("speed_0x54", 0)) != 10
		or atlas_dimensions.size() != 2
		or int(atlas_dimensions[0]) != 768
		or int(atlas_dimensions[1]) != 72
		or atlas_frame_size.size() != 2
		or int(atlas_frame_size[0]) != 24
		or int(atlas_frame_size[1]) != 24
		or int(atlas.get("headings", 0)) != ROCKET_HEADING_COUNT
		or int(atlas.get("animation_rows", 0)) != ROCKET_ANIMATION_ROWS
		or int(ordinary_collision.get("damage", 0)) != 200
		or int(boss_collision.get("rocket_damage", 0)) != 20
		or integration.get("exact_trace_complete") != true
		or fail_closed.get("requires_boss_contract_for_state_13") != true
	):
		return _set_error("late campaign ordnance runtime differs from its exact trace")
	# These two arrays are the executable's gameplay steering domains. Their
	# values are checked again when the pinned movement tables are consumed.
	var steering := update.get("steering", {}) as Dictionary
	var desired_headings := steering.get("quadrant_desired_headings", []) as Array
	var heading_domain := steering.get("heading_domain", []) as Array
	if (
		desired_headings.size() != 4
		or int(desired_headings[0]) != 5
		or int(desired_headings[1]) != 13
		or int(desired_headings[2]) != 21
		or int(desired_headings[3]) != 29
		or heading_domain.size() != 2
		or int(heading_domain[0]) != 1
		or int(heading_domain[1]) != 32
	):
		return _set_error("late campaign rocket steering contract is invalid")
	var movement := steering.get("movement", {}) as Dictionary
	var q16_projection := movement.get("canonical_q16_projection", {}) as Dictionary
	var movement_x := q16_projection.get("x", []) as Array
	var movement_y := q16_projection.get("y", []) as Array
	if (
		int(q16_projection.get("fraction_bits", 0)) != 16
		or movement_x.size() != ROCKET_HEADING_COUNT
		or movement_y.size() != ROCKET_HEADING_COUNT
	):
		return _set_error("late campaign rocket movement tables are missing")
	for heading_index in range(ROCKET_HEADING_COUNT):
		if (
			int(movement_x[heading_index]) != int(ROCKET_HEADING_X_Q16[heading_index])
			or int(movement_y[heading_index]) != int(ROCKET_HEADING_Y_Q16[heading_index])
		):
			return _set_error("late campaign rocket movement table differs from retail")
	var assets := _ordnance_contract.get("assets", {}) as Dictionary
	var texture_asset := assets.get("texture", {}) as Dictionary
	var texture_path := "res://%s" % String(texture_asset.get("path", ""))
	if OS.has_feature("editor"):
		# Source runs retain the original TGA bytes, so verify the extractor pin
		# directly before any imported-resource remapping can hide source drift.
		if (
			String(texture_asset.get("path", "")).is_empty()
			or not FileAccess.file_exists(texture_path)
			or FileAccess.get_sha256(texture_path)
			!= String(texture_asset.get("sha256", ""))
		):
			return _set_error("late campaign rocket texture asset is missing or changed")
	elif not OS.has_feature("server"):
		# Exported clients contain Godot's lossless imported texture rather than
		# the original TGA byte stream. The source gate above pins those bytes;
		# the signed package must expose the remap with the exact retail geometry.
		var texture_value: Variant = ResourceLoader.load(texture_path)
		var texture_dimensions := texture_asset.get("dimensions", []) as Array
		if (
			not texture_value is Texture2D
			or texture_dimensions.size() != 2
			or (texture_value as Texture2D).get_width() != int(texture_dimensions[0])
			or (texture_value as Texture2D).get_height() != int(texture_dimensions[1])
		):
			return _set_error("late campaign imported rocket texture is missing or changed")
	# Dedicated exports do not render textures; their authoritative collision
	# path still requires and byte-verifies the original rocket HMA below.
	var hit_mask_asset := assets.get("hit_mask", {}) as Dictionary
	var hit_mask_path := "res://%s" % String(hit_mask_asset.get("path", ""))
	if (
		String(hit_mask_asset.get("path", "")).is_empty()
		or not FileAccess.file_exists(hit_mask_path)
		or FileAccess.get_sha256(hit_mask_path)
		!= String(hit_mask_asset.get("sha256", ""))
	):
		return _set_error("late campaign rocket hit_mask asset is missing or changed")
	var hit_mask_file := FileAccess.open(hit_mask_path, FileAccess.READ)
	if hit_mask_file == null:
		return _set_error("cannot read the pinned rocket HMA")
	var hit_mask_bytes := hit_mask_file.get_buffer(hit_mask_file.get_length())
	if hit_mask_bytes.size() != 768 * 72:
		return _set_error("rocket HMA has the wrong binary dimensions")
	for mask_byte in hit_mask_bytes:
		if int(mask_byte) not in [0, 1]:
			return _set_error("rocket HMA contains a value outside the binary domain")
	return true


func _state_13_executable_sha256() -> String:
	var executable_sha256 := ""
	for bundle_value in _boss_runtimes_by_level.values():
		var bundle := bundle_value as Dictionary
		var contract := bundle.get("contract", {}) as Dictionary
		var candidate := String(contract.get("executable_sha256", ""))
		if candidate.is_empty():
			return ""
		if executable_sha256.is_empty():
			executable_sha256 = candidate
		elif candidate != executable_sha256:
			return ""
	return executable_sha256


func set_input(seat_id: int, action_mask: int) -> bool:
	if not _configured:
		return _set_error("simulation is not configured")
	if seat_id < 0 or seat_id >= _input_masks.size():
		return _set_error("seat_id is out of range")
	if action_mask < 0 or (action_mask & ~ACTION_MASK_ALL) != 0:
		return _set_error("action_mask contains unsupported actions")
	if not _seat_is_participating(seat_id):
		return _set_error("seat is not participating in this match")
	var normalized_mask := action_mask
	if (normalized_mask & ACTION_LEFT) != 0 and (normalized_mask & ACTION_RIGHT) != 0:
		normalized_mask &= ~(ACTION_LEFT | ACTION_RIGHT)
	if (normalized_mask & ACTION_UP) != 0 and (normalized_mask & ACTION_DOWN) != 0:
		normalized_mask &= ~(ACTION_UP | ACTION_DOWN)
	_input_masks[seat_id] = normalized_mask
	return true


func submit_bonus_action(
	seat_id: int,
	client_tick: int,
	action_kind: int,
	tile_index: int = -1
) -> Dictionary:
	if not _configured:
		return _bonus_action_result(false, "not_configured", action_kind, tile_index, seat_id)
	if _phase != PHASE_BONUS_MODE:
		return _bonus_action_result(false, "wrong_phase", action_kind, tile_index, seat_id)
	if seat_id < 0 or seat_id >= _input_masks.size() or not _seat_is_participating(seat_id):
		return _bonus_action_result(false, "seat_not_in_match", action_kind, tile_index, seat_id)
	if seat_id != _bonus_mode_owner_seat_id:
		return _bonus_action_result(false, "not_bonus_mode_owner", action_kind, tile_index, seat_id)
	if _active_bonus_mode_kind() != "memory_station":
		return _bonus_action_result(false, "bonus_action_not_supported", action_kind, tile_index, seat_id)
	if action_kind not in [BONUS_ACTION_SELECT_TILE, BONUS_ACTION_KILL_TIME]:
		return _bonus_action_result(false, "unsupported_bonus_action", action_kind, tile_index, seat_id)
	if action_kind == BONUS_ACTION_SELECT_TILE and (tile_index < 0 or tile_index > 63):
		return _bonus_action_result(false, "tile_out_of_range", action_kind, tile_index, seat_id)
	if action_kind == BONUS_ACTION_KILL_TIME and tile_index != -1:
		return _bonus_action_result(false, "kill_time_has_tile", action_kind, tile_index, seat_id)
	if client_tick > _tick + BONUS_ACTION_MAX_FUTURE_TICKS:
		return _bonus_action_result(false, "input_too_far_ahead", action_kind, tile_index, seat_id)
	if client_tick + BONUS_ACTION_MAX_OLD_TICKS < _tick:
		return _bonus_action_result(false, "input_too_old", action_kind, tile_index, seat_id)
	if client_tick <= _bonus_action_last_target_tick[seat_id]:
		return _bonus_action_result(false, "duplicate_action_tick", action_kind, tile_index, seat_id)
	if _bonus_action_queued_for_seat(seat_id):
		return _bonus_action_result(false, "bonus_action_rate_limited", action_kind, tile_index, seat_id)
	var controller_validation: Dictionary = _memory_station.validate_action(
		action_kind,
		tile_index,
		client_tick,
		_simulation_milliseconds()
	)
	if not bool(controller_validation.get("ok", false)):
		return _bonus_action_result(
			false,
			String(controller_validation.get("reason", "bonus_action_rejected")),
			action_kind,
			tile_index,
			seat_id
		)
	if _bonus_action_queue.size() >= BONUS_ACTION_QUEUE_LIMIT:
		return _bonus_action_result(false, "bonus_action_queue_full", action_kind, tile_index, seat_id)
	var action := {
		"seat_id": seat_id,
		"target_tick": client_tick,
		"action_kind": action_kind,
		"tile_index": tile_index,
	}
	_bonus_action_last_target_tick[seat_id] = client_tick
	_bonus_action_queue.append(action)
	return _bonus_action_result(true, "queued", action_kind, tile_index, seat_id)


func _bonus_action_result(
	accepted: bool,
	reason: String,
	action_kind: int,
	tile_index: int,
	seat_id: int
) -> Dictionary:
	return {
		"accepted": accepted,
		"reason": reason,
		"seat_id": seat_id,
		"action_kind": action_kind,
		"tile_index": tile_index,
		"server_tick": _tick,
	}


func _drain_bonus_actions_for_tick() -> void:
	_bonus_actions_this_tick.clear()
	if _bonus_action_queue.is_empty():
		return
	var pending: Array = []
	for action_value in _bonus_action_queue:
		var action: Dictionary = action_value
		if int(action.get("target_tick", 0)) <= _tick:
			var normalized := action.duplicate(true)
			# Replays describe the authoritative sampling boundary, not a client's
			# prediction. A queued action that arrives early therefore records the
			# tick on which it is actually consumed.
			normalized["target_tick"] = _tick
			_bonus_actions_this_tick.append(normalized)
			var normalized_seat := int(normalized.get("seat_id", -1))
			if normalized_seat >= 0 and normalized_seat < _bonus_action_last_target_tick.size():
				_bonus_action_last_target_tick[normalized_seat] = _tick
		else:
			pending.append(action)
	_bonus_action_queue = pending


func _bonus_action_queued_for_seat(seat_id: int) -> bool:
	for action_value in _bonus_action_queue:
		var action: Dictionary = action_value
		if int(action.get("seat_id", -1)) == seat_id:
			return true
	return false


func step() -> Dictionary:
	if not _configured:
		_set_error("simulation is not configured")
		return {}
	_events.clear()
	_tick += 1
	_drain_bonus_actions_for_tick()
	var retail_sound_gate_call := _retail_mode_calls_global_sound_gate()
	var boss_owns_sound_gate_call := (
		_phase == PHASE_LEVEL and _is_retail_big_boss_level()
	)
	match _phase:
		PHASE_LEVEL:
			_step_level()
		PHASE_GET_READY:
			_step_get_ready()
		PHASE_SHOP:
			_step_shop()
		PHASE_RANK_PROMOTION:
			_step_rank_promotion()
		PHASE_BONUS_MODE:
			_step_bonus_mode()
		PHASE_WARP:
			_step_warp()
		PHASE_WARP_MALFUNCTION:
			_step_warp_malfunction()
		PHASE_CREDITS:
			_step_credits()
	if retail_sound_gate_call and not boss_owns_sound_gate_call:
		_advance_retail_global_sound_gate()
	_step_time_trial_clock()
	_advance_background_scroll_presentation()
	for seat_id in range(2):
		_previous_input_masks[seat_id] = _input_masks[seat_id]
	var snapshot := get_snapshot()
	# Sparse-stride (online) recordings close at the terminal frame: the
	# verifier's endpoint is the tick the result appeared, and post-terminal
	# idling on the results screen must not grow the submission. Stride-1
	# recordings keep the historical every-tick behavior.
	var recording_closed := _replay_hash_stride > 1 and _replay_terminal_hash_recorded
	if _record_replay and not recording_closed:
		var frame := {
			"tick": _tick,
			"inputs": [_input_masks[0], _input_masks[1]],
			"bonus_actions": _bonus_actions_this_tick.duplicate(true),
		}
		var terminal_pending := not _result.is_empty() and not _replay_terminal_hash_recorded
		if _replay_hash_stride == 1 or _tick % _replay_hash_stride == 0 or terminal_pending:
			frame["state_hash"] = state_hash()
			if terminal_pending:
				_replay_terminal_hash_recorded = true
		_replay_frames.append(frame)
	return snapshot


func get_snapshot() -> Dictionary:
	if not _configured:
		return {}
	var level: Dictionary = _level_data_for(_level_id)
	var visible_shop_items: Array = []
	if _phase == PHASE_SHOP:
		for item in _catalog.shop:
			if _shop_item_is_unlocked(item, _turn_seat):
				visible_shop_items.append(item.duplicate(true))
	var players_snapshot: Array = []
	for player in _players:
		var seat_id := int(player.seat_id)
		var progression := _progression_for_seat(seat_id)
		var mirror_active := int(progression.get("mirror_ticks", 0)) > 0
		players_snapshot.append({
			"seat_id": seat_id,
			"x_fp": int(player.x_fp),
			"y_fp": int(player.y_fp),
			"width": int(player.width),
			"height": int(player.height),
			"active": bool(player.active),
			"alive": bool(player.alive),
			"invulnerable_ticks": int(player.invulnerable_ticks),
			"respawn_ticks": int(player.respawn_ticks),
			"death_accounted": bool(player.get("death_accounted", false)),
			"projectile_suppression_ticks": int(player.projectile_suppression_ticks),
			"cooldown_ticks": int(player.cooldown_ticks),
			"auto_fire_deadline_ms": int(player.auto_fire_deadline_ms),
			"frame": int(player.mask_frame),
			"sprite_frame": int(player.mask_frame),
			"mirror_active": mirror_active,
			"mirror_x_fp": _mirrored_x_fp(int(player.x_fp)),
			"mirror_anchor_x_fp": int(player.get("mirror_anchor_x_fp", player.x_fp)),
			"progression": _public_progression(progression),
		})
	var enemies_snapshot: Array = []
	for enemy in _enemies:
		var world_x_fp := _enemy_world_x_fp(enemy)
		var world_y_fp := _enemy_world_y_fp(enemy)
		var enemy_snapshot := {
			"id": int(enemy.id),
			"x_fp": world_x_fp,
			"y_fp": world_y_fp,
			"width": int(enemy.width),
			"height": int(enemy.height),
			"health_fp": int(enemy.health_fp),
			"max_health_fp": int(enemy.max_health_fp),
			"sprite": String(enemy.sprite),
		}
		for key in [
			"authored_state",
			"group_id",
			"enemy_index",
			"kill_cohort_id",
			"activation_delay_ticks",
			"activation_delay_sixths",
			"path_index",
			"path_progress_ticks",
			"path_progress_sixths",
			"velocity_x_fp",
			"velocity_y_fp",
			"acceleration_x_fp",
			"acceleration_y_fp",
			"formation_target_x_fp",
			"formation_target_y_fp",
			"mirror_x",
			"authored_sprite_frame",
			"authored_animation_frame",
			"behavior_timer_a",
			"behavior_timer_a_step",
			"behavior_timer_b",
			"behavior_timer_b_step",
			"behavior_state_id",
			"animation_countdown_sixths",
			"animation_direction",
			"animation_max_phase",
			"animation_metadata",
			"swd_runtime_index",
			"swd_point_index",
			"swd_progress_sixths",
			"swd_return_selector",
			"heading",
			"steering_countdown_fp",
			"steering_mode",
			"heading_step_countdown_sixths",
			"heading_step_countdown_fp",
			"heading_step_reset_fp",
			"supplemental_c54",
			"x_scale_fp",
			"y_scale_fp",
			"speed_fp",
			"horizontal_velocity_fp",
			"horizontal_acceleration_fp",
			"horizontal_flip_interval_sixths",
			"horizontal_flip_countdown_sixths",
			"vertical_velocity_fp",
			"vertical_acceleration_fp",
			"leader_has_followers",
			"follower_leader_slot",
			"saved_behavior_timer_a",
			"saved_health_fp",
			"state_four_turn_countdown",
			"state_four_velocity_x_fp",
			"state_four_acceleration_x_fp",
			"captured_owner_seat",
			"captured_side",
			"captured_latched",
			"capture_offset_fp",
			"captured_render_mirrored",
			"warp_malfunction",
			"warp_malfunction_file_id",
			"resource_slot_id",
			"animation_countdown_fp",
			"animation_interval_fp",
			"animation_divisor_fp",
			"heading_step_interval_fp",
			"hurry_up_enters_from_right",
			"collision_width",
			"collision_height",
			"source_rect",
		]:
			if enemy.has(key):
				enemy_snapshot[key] = enemy[key]
		if int(enemy.get("behavior_state_id", 0)) == 8:
			enemy_snapshot.render_x_fp = _captured_render_x_fp(
				enemy,
				bool(enemy.get("captured_render_mirrored", false))
			)
		enemies_snapshot.append(enemy_snapshot)
	var effect_objects_snapshot: Array = []
	for slot_value in _effect_pool:
		var slot := slot_value as Dictionary
		if slot.is_empty():
			continue
		var effect_snapshot := {
			"slot": int(slot.slot),
			"kind": int(slot.kind),
			"sprite": String(slot.sprite),
			"x_fp": int(slot.x_fp),
			"y_fp": int(slot.y_fp),
			"width": int(slot.width),
			"height": int(slot.height),
			"heading": int(slot.heading),
			"seat_id": int(slot.owner_seat),
		}
		if slot.has("source_rect"):
			effect_snapshot["source_rect"] = slot.source_rect
		effect_objects_snapshot.append(effect_snapshot)
	var projectiles_snapshot: Array = []
	for projectile in _projectiles:
		var projectile_snapshot := {
			"id": int(projectile.id),
			"owner_kind": String(projectile.owner_kind),
			"owner_id": int(projectile.owner_id),
			"pool_slot": int(
				projectile.get(
					"player_slot",
					projectile.get("common_slot", -1)
				)
			),
			"spawn_tick": int(projectile.get("spawn_tick", 0)),
			"x_fp": int(projectile.x_fp),
			"y_fp": int(projectile.y_fp),
			"width": int(projectile.width),
			"height": int(projectile.height),
			"damage_fp": int(projectile.damage_fp),
			"prototype_id": int(projectile.prototype_id),
			"capacity_contribution": int(projectile.get("capacity_contribution", 0)),
			"animation_frame": int(projectile.get("animation_frame", 0)),
			"velocity_x_fp": int(projectile.get("velocity_x_fp", 0)),
			"velocity_y_fp": int(projectile.get("velocity_y_fp", 0)),
			"enemy_projectile_type": int(projectile.get("enemy_projectile_type", -1)),
			"enemy_sheet": String(projectile.get("enemy_sheet", "")),
			"projectile_kind": _projectile_kind(projectile),
			"sprite_sheet_id": _projectile_sprite_sheet_id(projectile),
			"source_rect": _projectile_source_rect_values(projectile),
		}
		for key in [
			"broadphase_width",
			"broadphase_height",
			"broadphase_inset_x",
			"broadphase_inset_y",
			"phase_x",
			"phase_y",
			"sound_frequency",
			"retail_left_fp",
			"retail_top_fp",
			"resource_slot_id",
			"animation_period_fp",
			"animation_countdown_fp",
			"animation_frame_max",
			"mask_source_x",
			"mask_source_y",
			"mask_source_width",
			"mask_source_height",
			"source_rect",
			"damage_policy",
			"consume_on_player_hit",
			"retire_top_left_y_strictly_above",
			"target_entity_id",
			"target_kind",
			"target_state_id",
			"target_reserved",
			"heading",
			"lifetime_fp",
			"animation_row",
			"steering_period_fp",
			"steering_countdown_fp",
			"stale_capacity_contribution",
		]:
			if projectile.has(key):
				projectile_snapshot[key] = projectile[key]
		projectiles_snapshot.append(projectile_snapshot)
	var pickups_snapshot: Array = []
	for pickup in _pickups:
		var pickup_snapshot := {
			"id": int(pickup.id),
			"pool_slot": int(pickup.get("pickup_slot", -1)),
			"kind": String(pickup.kind),
			"variant": int(pickup.get("variant", 0)),
			"animation_frame": int(pickup.get("animation_frame", 0)),
			"x_fp": int(pickup.x_fp),
			"y_fp": int(pickup.y_fp),
			"width": int(pickup.get("width", 20)),
			"height": int(pickup.get("height", 20)),
		}
		for key in [
			"effect_key",
			"bonus_type",
			"source_y",
			"velocity_y_fp",
			"texture_key",
			"gem_color_bit",
		]:
			if pickup.has(key):
				pickup_snapshot[key] = pickup[key]
		pickups_snapshot.append(pickup_snapshot)
	var promotion_rank := 0
	var promotion_highest_rank := 0
	var promotion_rank_cap := DEFAULT_RANK_CAP
	if _rank_promotion_seat_id >= 0:
		var promotion_progression := _progression_for_seat(_rank_promotion_seat_id)
		promotion_rank = int(promotion_progression.get("rank", 0))
		promotion_highest_rank = int(
			promotion_progression.get("highest_rank", promotion_rank)
		)
		promotion_rank_cap = int(
			promotion_progression.get("rank_cap", DEFAULT_RANK_CAP)
		)
	var mode_three_bonus := _public_level_eight_bonus_snapshot()
	return {
		"version": SNAPSHOT_VERSION,
		"tick": _tick,
		"phase": _phase,
		"mode": _mode,
		"difficulty": _difficulty_id,
		"coop_balance": _balance,
		"collision_mode": _collision_mode,
		"start_level_id": int(_config.get("start_level", 1)),
		"level_id": _level_id,
		"end_level_id": _end_level_id,
		"level_title": String(level.get("title", "")),
		"level_tick": _level_tick,
		"turn_seat": _turn_seat,
		"time_trial": _public_time_trial_snapshot(),
		"content_hash": _content_hash,
		"credits": _public_credits_snapshot(),
		"using_fallback_content": _using_fallback_content,
		"rng": _rng.snapshot(),
		"platform": {
			"x_fp": _platform_x_fp,
			"y_fp": _platform_y_fp,
			"velocity_x_fp": _platform_velocity_x_fp,
			"acceleration_x_fp": _platform_acceleration_x_fp,
		},
		"tail_cutoff": _tail_cutoff,
		"level_resolution": {
			"total": _level_total_entities,
			"killed": _level_killed_entities,
			"escaped": _level_escaped_entities,
			"resolved": _level_resolved,
			"resolution_tick": _level_resolution_tick,
			"get_ready_until_tick": _get_ready_until_tick,
			"pending_level_id": _pending_level_id,			"watchdog_start_tick": _level_watchdog_start_tick,
			"liveness_idle_updates": _enemy_liveness_idle_updates,
			"shop_warp_until_tick": _shop_warp_until_tick,
			"rocket_fired_this_level": _rocket_fired_this_level,
			"any_player_projectile_allocated": _rocket_fired_this_level,
			"any_alien_projectile_processed": (
				_alien_projectile_processed_this_level
			),
			"rank_full_reward_claimed": _rank_full_reward_claimed,
			"boss_destroyed_counts_by_seat": (
				_boss_destroyed_counts_by_seat.duplicate()
			),
		},
		"ordnance": {
			"secondary_rocket_armed": _secondary_rocket_armed.duplicate(),
			"effect_active": _rocket_effect_active,
			"effect_until_ms": _rocket_effect_until_ms,
		},
		"boss": _public_boss_snapshot(),
		"mode_three_bonus": mode_three_bonus,
		"level_eight_bonus": mode_three_bonus.duplicate(true),
		"bonus_mode": _public_bonus_mode_snapshot(),
		"warp": {
			"stage": _warp_stage,
			"stage_updates_remaining": _warp_stage_updates_remaining,
			"visual_fp": _warp_visual_fp,
			"scale": _warp_scale,
			"velocity": _warp_velocity,
			"effect": _warp_effect,
			"offset": _warp_offset,
			# Additive snapshot-v9 presentation fields. Older readers ignore them;
			# current clients use them so a 20 Hz network cadence never has to
			# reconstruct three changing retail scale samples from one value.
			"background_draw_offset": _background_draw_offset,
			"background_post_draw_offset": _background_post_draw_offset,
			"owned_skip": _warp_owned_skip,
			"malfunction_interval": _warp_malfunction_interval,
			"malfunction_gate_calls": _warp_malfunction_gate_calls,
			"malfunction_file_id": _warp_malfunction_file_id,
			"malfunction_total": _warp_malfunction_total,
			"malfunction_killed": _warp_malfunction_killed,
			"malfunction_missed": _warp_malfunction_missed,
			"malfunction_resolution_tick": _warp_malfunction_resolution_tick,
			"malfunction_transition_pending": _warp_malfunction_transition_pending,
			"message_until_tick": _warp_malfunction_message_until_tick,
			"message_cadence_tick": _warp_malfunction_message_cadence_tick,
			"message_cadence_remaining": _warp_malfunction_message_cadence_remaining,
			"transition_requested": _warp_transition_requested,
			"request_seat_id": _warp_request_seat_id,
			"request_cause": _warp_request_cause,
			"owner_seat_id": _warp_owner_seat_id,
		},
		"players": players_snapshot,
		"enemies": enemies_snapshot,
		"effect_objects": effect_objects_snapshot,
		"projectiles": projectiles_snapshot,
		"pickups": pickups_snapshot,
		"shared": _public_shared_state(),
		"profile_stats": _public_profile_stats(),
		"shop": {
			"items": visible_shop_items,
			"ready": [_shop_ready[0], _shop_ready[1]],
			"active_seat_id": _turn_seat if _phase == PHASE_SHOP else -1,
			"sequential_owner": false,
			"input_guard_until_tick": _shop_warp_until_tick,
		},
		"rank_promotion": {
			"seat_id": _rank_promotion_seat_id,
			"rank": promotion_rank,
			"rank_name": _rank_name(promotion_rank),
			"badge_y": _rank_badge_y(promotion_rank),
			"highest_rank": promotion_highest_rank,
			"rank_cap": promotion_rank_cap,
			"minimum_tick": _rank_promotion_minimum_tick,
			"timeout_tick": _rank_promotion_timeout_tick,
			"can_continue": (
				_phase == PHASE_RANK_PROMOTION
				and _tick >= _rank_promotion_minimum_tick
			),
			"prompt_visible": _rank_promotion_prompt_is_visible(),
		},
		"events": _events.duplicate(true),
		"result": _result.duplicate(true),
	}


func _public_boss_snapshot() -> Dictionary:
	if _boss_entered and not _boss_render_snapshot.is_empty():
		return _boss_render_snapshot.duplicate(true)
	return {
		"active": false,
		"state": 0,
		"stage": 0,
		"health": 0,
		"max_health": 0,
		"sheet": "",
		"parts": [],
	}


func state_hash() -> String:
	if not _configured:
		return ""
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(JSON.stringify(_state_for_hash()).to_utf8_buffer())
	return context.finish().hex_encode()


func get_content_hash() -> String:
	return _content_hash


func get_last_error() -> String:
	return last_error


func get_replay() -> Dictionary:
	return {
		"version": REPLAY_VERSION,
		"match_config": _config.duplicate(true),
		"content_hash": _content_hash,
		"rng_algorithm": "warblade_1_34_five_word",
		"initial_rng": _initial_rng_snapshot.duplicate(true),
		"match_persistent_flags_by_seat": (
			_match_persistent_flags_by_seat.duplicate(true)
		),
		"frames": _replay_frames.duplicate(true),
	}


## Retail saves a run only from the shop (writer FUN_00537c80, loader
## FUN_005384f0, slot path `%s\warblade\profiles\profile%03d.svg`). Retail
## serializes a raw 694,296-byte image of its own state block, so the remake
## keeps the contract — shop-only, slot-addressed, resumable — while writing its
## own authoritative state instead of a foreign memory layout.
##
## The shop boundary is quiescent: no enemies, projectiles, pickups, or spawned
## waves survive it, and every level-local counter is rebuilt by `_begin_level`.
## Only the cross-level state below has to travel. Retail rebases its absolute
## timed deadlines against the wall clock at save and load; the remake derives
## simulation milliseconds from the tick counter, so restoring the tick restores
## every deadline with it.
func export_shop_save() -> Dictionary:
	if not _configured:
		_set_error("simulation is not configured")
		return {}
	if _phase != PHASE_SHOP:
		_set_error("a run can only be saved from the shop")
		return {}
	var seat_progression: Array = []
	for seat_id in range(2):
		seat_progression.append(_progression_for_seat(seat_id).duplicate(true))
	var match_config := _config.duplicate(true)
	# A resumed run carries its own save in the config; saving again must not
	# nest the previous save inside the new one.
	match_config.erase("resume_save")
	match_config.erase("resume_slot")
	return {
		"version": SHOP_SAVE_VERSION,
		"schema": SHOP_SAVE_SCHEMA,
		"protocol_version": ProtocolContract.VERSION,
		"content_version": MatchContract.CONTENT_VERSION,
		"content_hash": _content_hash,
		"match_config": match_config,
		"state": {
			"tick": _tick,
			"level_id": _level_id,
			"end_level_id": _end_level_id,
			"turn_seat": _turn_seat,
			"retired": _retired,
			"credits_min_tick": _credits_min_tick,
			"level_100_milestone_score": _level_100_milestone_score,
			"next_entity_id": _next_entity_id,
			"next_event_id": _next_event_id,
			"pending_level_id": _pending_level_id,
			"shop_warp_until_tick": _shop_warp_until_tick,
			"warp_owner_seat_id": _warp_owner_seat_id,
			"warp_malfunction_interval": _warp_malfunction_interval,
			"warp_malfunction_gate_calls": _warp_malfunction_gate_calls,
			"retail_global_sound_gate": _retail_global_sound_gate,
			"rocket_effect_until_ms": _rocket_effect_until_ms,
			"rocket_effect_active": _rocket_effect_active,
			"secondary_rocket_armed": _secondary_rocket_armed.duplicate(),
			"shop_ready": _shop_ready.duplicate(),
			"purchased_nonces": _purchased_nonces.duplicate(true),
			"locked_out_bonus_types": _sorted_int_keys(_locked_out_bonus_types),
			"level_eight_perfect_indices": _level_eight_perfect_indices.duplicate(),
			"level_tick": _level_tick,
			"players": _players.duplicate(true),
			"common_projectile_slots": _common_projectile_slots.duplicate(true),
			"spawned_waves": _sorted_int_keys(_spawned_waves),
			"authored_slot_seeds": _authored_slot_seeds.duplicate(true),
			"authored_spawn_slot": _authored_spawn_slot,
			"supplemental_spawned": _supplemental_spawned,
			"platform_x_fp": _platform_x_fp,
			"platform_y_fp": _platform_y_fp,
			"platform_velocity_x_fp": _platform_velocity_x_fp,
			"platform_acceleration_x_fp": _platform_acceleration_x_fp,
			"tail_cutoff": _tail_cutoff,
			"hurry_up_interval_ms": _hurry_up_interval_ms,
			"hurry_up_deadline_ms": _hurry_up_deadline_ms,
			"hurry_up_spawn_counter": _hurry_up_spawn_counter,
			"hurry_up_planet_count": _hurry_up_planet_count,
			"hurry_up_planet_x": _hurry_up_planet_x.duplicate(),
			"money_sucker_deadline_ms": _money_sucker_deadline_ms,
			"guard_previous_level": _guard_previous_level,
			"guard_beam_window": _guard_beam_window,
			"special_health_base_b": _special_health_base_b,
			"special_health_base_d": _special_health_base_d,
			"effect_pool": _effect_pool.duplicate(true),
			"level_total_entities": _level_total_entities,
			"level_killed_entities": _level_killed_entities,
			"level_escaped_entities": _level_escaped_entities,
			"level_resolved": _level_resolved,
			"level_resolution_tick": _level_resolution_tick,
			"group_kill_counts": _group_kill_counts.duplicate(true),
			"group_totals": _group_totals.duplicate(true),
			"cohort_kill_counts": _cohort_kill_counts.duplicate(true),
			"cohort_totals": _cohort_totals.duplicate(true),
			"cohort_completion_score": _cohort_completion_score,
			"level_watchdog_start_tick": _level_watchdog_start_tick,
			"enemy_liveness_idle_updates": _enemy_liveness_idle_updates,
			"rocket_fired_this_level": _rocket_fired_this_level,
			"alien_projectile_processed_this_level": (
				_alien_projectile_processed_this_level
			),
			"rank_full_reward_claimed": _rank_full_reward_claimed,
			"player_projectile_slot_stale_contributions": (
				_player_projectile_slot_stale_contributions.duplicate()
			),
			"ordinary_projectile_counter_adjustment_by_seat": (
				_ordinary_projectile_counter_adjustment_by_seat.duplicate()
			),
			"warp_stage": _warp_stage,
			"warp_visual_fp": _warp_visual_fp,
			"warp_scale": _warp_scale,
			"warp_velocity": _warp_velocity,
			"warp_effect": _warp_effect,
			"warp_offset": _warp_offset,
			"warp_owned_skip": _warp_owned_skip,
			"background_draw_offset": _background_draw_offset,
			"background_post_draw_offset": _background_post_draw_offset,
			"shared_progression": _shared.duplicate(true),
			"seat_progression": seat_progression,
			"profile_stats_by_seat": _profile_stats_by_seat.duplicate(true),
			"match_persistent_flags_by_seat": (
				_match_persistent_flags_by_seat.duplicate(true)
			),
			"rng": _rng.snapshot(),
		},
	}


## Rebuilds a saved run. The caller supplies a freshly constructed simulation;
## this reconfigures it from the saved match config and then reinstates the
## shop-boundary state, so leaving the shop rebuilds every level-local structure
## through the ordinary `_begin_level` path.
func restore_shop_save(save: Dictionary) -> bool:
	last_error = ""
	if int(save.get("version", 0)) != SHOP_SAVE_VERSION:
		return _set_error("saved run uses an unsupported save version")
	if String(save.get("schema", "")) != SHOP_SAVE_SCHEMA:
		return _set_error("saved run uses an unsupported save schema")
	if int(save.get("content_version", -1)) != MatchContract.CONTENT_VERSION:
		return _set_error("saved run was written for different content")
	var match_config_value: Variant = save.get("match_config")
	if not match_config_value is Dictionary:
		return _set_error("saved run is missing its match configuration")
	var state_value: Variant = save.get("state")
	if not state_value is Dictionary:
		return _set_error("saved run is missing its state")
	var match_config := (match_config_value as Dictionary).duplicate(true)
	var expected_hash := String(save.get("content_hash", ""))
	if not expected_hash.is_empty():
		match_config["content_hash"] = expected_hash
	if not configure(match_config):
		return false
	var state := state_value as Dictionary
	_tick = int(state.get("tick", 0))
	_level_id = int(state.get("level_id", 1))
	_end_level_id = int(state.get("end_level_id", _end_level_id))
	_turn_seat = clampi(int(state.get("turn_seat", 0)), 0, 1)
	_retired = bool(state.get("retired", false))
	_credits_min_tick = int(state.get("credits_min_tick", 0))
	_level_100_milestone_score = int(state.get("level_100_milestone_score", 0))
	_next_entity_id = maxi(1, int(state.get("next_entity_id", 1)))
	_next_event_id = maxi(1, int(state.get("next_event_id", 1)))
	_pending_level_id = int(state.get("pending_level_id", 0))
	_shop_warp_until_tick = int(state.get("shop_warp_until_tick", 0))
	_warp_owner_seat_id = int(state.get("warp_owner_seat_id", -1))
	_warp_malfunction_interval = int(state.get("warp_malfunction_interval", 0))
	_warp_malfunction_gate_calls = int(state.get("warp_malfunction_gate_calls", 0))
	_retail_global_sound_gate = int(
		state.get("retail_global_sound_gate", RETAIL_GLOBAL_SOUND_GATE_INITIAL)
	)
	_rocket_effect_until_ms = int(state.get("rocket_effect_until_ms", 0))
	_rocket_effect_active = bool(state.get("rocket_effect_active", false))
	_secondary_rocket_armed = [true, true]
	for seat_id in range((state.get("secondary_rocket_armed", []) as Array).size()):
		if seat_id < 2:
			_secondary_rocket_armed[seat_id] = bool(
				(state.get("secondary_rocket_armed", []) as Array)[seat_id]
			)
	_shop_ready = [false, false]
	for seat_id in range((state.get("shop_ready", []) as Array).size()):
		if seat_id < 2:
			_shop_ready[seat_id] = bool((state.get("shop_ready", []) as Array)[seat_id])
	_purchased_nonces = (state.get("purchased_nonces", {}) as Dictionary).duplicate(true)
	_locked_out_bonus_types.clear()
	for bonus_type in state.get("locked_out_bonus_types", []):
		_locked_out_bonus_types[int(bonus_type)] = true
	_level_eight_perfect_indices = [0, 0]
	var perfect_indices: Array = state.get("level_eight_perfect_indices", [])
	for seat_id in range(mini(2, perfect_indices.size())):
		_level_eight_perfect_indices[seat_id] = int(perfect_indices[seat_id])
	var shared_value: Variant = state.get("shared_progression")
	if not shared_value is Dictionary:
		return _set_error("saved run is missing its shared progression")
	_shared = (shared_value as Dictionary).duplicate(true)
	# Solo, co-op, and Time Trial share one progression object; seat lookups
	# must resolve to the same dictionary, not to a copy of it.
	_seat_progression = [_shared, _shared]
	_profile_stats_by_seat = [
		_create_profile_stats(match_config, 0),
		_create_profile_stats(match_config, 1),
	]
	var saved_stats: Array = state.get("profile_stats_by_seat", [])
	for seat_id in range(mini(2, saved_stats.size())):
		if saved_stats[seat_id] is Dictionary:
			_profile_stats_by_seat[seat_id] = (
				saved_stats[seat_id] as Dictionary
			).duplicate(true)
	var saved_flags: Array = state.get("match_persistent_flags_by_seat", [])
	for seat_id in range(mini(2, saved_flags.size())):
		if saved_flags[seat_id] is Dictionary:
			_match_persistent_flags_by_seat[seat_id] = (
				saved_flags[seat_id] as Dictionary
			).duplicate(true)
	var rng_value: Variant = state.get("rng")
	if not rng_value is Dictionary or not (rng_value as Dictionary).has("draw_count"):
		return _set_error("saved run has an unrestorable RNG state")
	_rng.restore(rng_value as Dictionary)
	_apply_endless_progression()
	_level_tick = 0
	_phase = PHASE_SHOP
	_enemies.clear()
	_projectiles.clear()
	_pickups.clear()
	_spawned_waves.clear()
	_reset_rank_promotion_state()
	_events.clear()
	_result.clear()
	_replay_frames.clear()
	_input_masks = [0, 0]
	_previous_input_masks = [0, 0]
	var saved_players: Array = state.get("players", [])
	for seat_id in range(mini(_players.size(), saved_players.size())):
		if saved_players[seat_id] is Dictionary:
			_players[seat_id] = (saved_players[seat_id] as Dictionary).duplicate(true)
	var saved_slots: Array = state.get("common_projectile_slots", [])
	if saved_slots.size() == COMMON_PROJECTILE_SLOT_COUNT:
		_common_projectile_slots = saved_slots.duplicate(true)
	else:
		_initialize_common_projectile_slots()
	_level_tick = int(state.get("level_tick", 0))
	_spawned_waves.clear()
	for wave_id in state.get("spawned_waves", []):
		_spawned_waves[int(wave_id)] = true
	_authored_slot_seeds = (state.get("authored_slot_seeds", []) as Array).duplicate(true)
	_authored_spawn_slot = int(state.get("authored_spawn_slot", 0))
	_supplemental_spawned = bool(state.get("supplemental_spawned", false))
	_platform_x_fp = int(state.get("platform_x_fp", 0))
	_platform_y_fp = int(state.get("platform_y_fp", 0))
	_platform_velocity_x_fp = int(
		state.get("platform_velocity_x_fp", PLATFORM_INITIAL_VELOCITY_FP)
	)
	_platform_acceleration_x_fp = int(
		state.get("platform_acceleration_x_fp", PLATFORM_ACCELERATION_FP)
	)
	_tail_cutoff = int(state.get("tail_cutoff", 2))
	_hurry_up_interval_ms = int(state.get("hurry_up_interval_ms", 0))
	_hurry_up_deadline_ms = int(state.get("hurry_up_deadline_ms", 0))
	_hurry_up_spawn_counter = int(state.get("hurry_up_spawn_counter", 0))
	_hurry_up_planet_count = int(state.get("hurry_up_planet_count", 1))
	_hurry_up_planet_x = []
	_hurry_up_planet_x.resize(HURRY_UP_PLANET_LIMIT)
	_hurry_up_planet_x.fill(0)
	_money_sucker_deadline_ms = int(state.get("money_sucker_deadline_ms", 0))
	_guard_previous_level = int(state.get("guard_previous_level", 0))
	_guard_beam_window = int(state.get("guard_beam_window", 0))
	_special_health_base_b = int(state.get(
		"special_health_base_b",
		int(_difficulty.get("special_health_base_b", 350))
	))
	_special_health_base_d = int(state.get(
		"special_health_base_d",
		int(_difficulty.get("special_health_base_d", 1750))
	))
	_reset_effect_pool()
	var restored_pool: Variant = state.get("effect_pool", [])
	if restored_pool is Array:
		for pool_index in range(
			mini((restored_pool as Array).size(), EFFECT_POOL_SLOT_COUNT)
		):
			var restored_slot: Variant = (restored_pool as Array)[pool_index]
			if restored_slot is Dictionary:
				_effect_pool[pool_index] = (restored_slot as Dictionary).duplicate(true)
	var restored_planets: Variant = state.get("hurry_up_planet_x", [])
	if restored_planets is Array:
		for planet_index in range(
			mini((restored_planets as Array).size(), HURRY_UP_PLANET_LIMIT)
		):
			_hurry_up_planet_x[planet_index] = int((restored_planets as Array)[planet_index])
	_level_total_entities = int(state.get("level_total_entities", 0))
	_level_killed_entities = int(state.get("level_killed_entities", 0))
	_level_escaped_entities = int(state.get("level_escaped_entities", 0))
	_level_resolved = bool(state.get("level_resolved", false))
	_level_resolution_tick = int(state.get("level_resolution_tick", 0))
	_group_kill_counts = (state.get("group_kill_counts", {}) as Dictionary).duplicate(true)
	_group_totals = (state.get("group_totals", {}) as Dictionary).duplicate(true)
	_cohort_kill_counts = (
		state.get("cohort_kill_counts", {}) as Dictionary
	).duplicate(true)
	_cohort_totals = (state.get("cohort_totals", {}) as Dictionary).duplicate(true)
	_cohort_completion_score = int(
		state.get("cohort_completion_score", COHORT_INITIAL_COMPLETION_SCORE)
	)
	_level_watchdog_start_tick = int(state.get("level_watchdog_start_tick", 0))
	_enemy_liveness_idle_updates = int(state.get("enemy_liveness_idle_updates", 0))
	_rocket_fired_this_level = bool(state.get("rocket_fired_this_level", false))
	_alien_projectile_processed_this_level = bool(
		state.get("alien_projectile_processed_this_level", false)
	)
	_rank_full_reward_claimed = bool(state.get("rank_full_reward_claimed", false))
	var saved_stale: Array = state.get("player_projectile_slot_stale_contributions", [])
	_player_projectile_slot_stale_contributions.fill(0)
	for slot_index in range(
		mini(_player_projectile_slot_stale_contributions.size(), saved_stale.size())
	):
		_player_projectile_slot_stale_contributions[slot_index] = int(
			saved_stale[slot_index]
		)
	var saved_adjustments: Array = state.get(
		"ordinary_projectile_counter_adjustment_by_seat",
		[]
	)
	for seat_id in range(mini(2, saved_adjustments.size())):
		_ordinary_projectile_counter_adjustment_by_seat[seat_id] = int(
			saved_adjustments[seat_id]
		)
	_warp_stage = int(state.get("warp_stage", 0))
	_warp_visual_fp = int(state.get("warp_visual_fp", 0))
	_warp_scale = float(state.get("warp_scale", 0.0))
	_warp_velocity = float(state.get("warp_velocity", 0.0))
	_warp_effect = float(state.get("warp_effect", 0.0))
	_warp_offset = float(state.get("warp_offset", 0.0))
	_warp_owned_skip = bool(state.get("warp_owned_skip", false))
	_background_draw_offset = float(state.get("background_draw_offset", 0.0))
	_background_post_draw_offset = float(
		state.get("background_post_draw_offset", 0.0)
	)
	return true


func submit_shop_purchase(seat_id: int, item_id: int, nonce: int) -> Dictionary:
	if not _configured:
		return _purchase_result(false, "not_configured", item_id, nonce, seat_id)
	if _phase != PHASE_SHOP:
		return _purchase_result(false, "wrong_phase", item_id, nonce, seat_id)
	if _shop_warp_until_tick > 0 and _tick <= _shop_warp_until_tick:
		return _purchase_result(false, "shop_input_guard", item_id, nonce, seat_id)
	if not _seat_is_participating(seat_id):
		return _purchase_result(false, "seat_not_in_match", item_id, nonce, seat_id)
	if seat_id != 0:
		return _purchase_result(false, "not_party_leader", item_id, nonce, seat_id)
	if nonce < 0:
		return _purchase_result(false, "invalid_nonce", item_id, nonce, seat_id)
	var nonce_key := "%d:%d" % [seat_id, nonce]
	if _purchased_nonces.has(nonce_key):
		return _purchased_nonces[nonce_key].duplicate(true)
	if not _shop_by_id.has(item_id):
		return _remember_purchase(
			nonce_key,
			_purchase_result(false, "unknown_item", item_id, nonce, seat_id)
		)
	var item: Dictionary = _shop_by_id[item_id]
	if not _shop_item_is_unlocked(item, seat_id):
		return _remember_purchase(
			nonce_key,
			_purchase_result(false, "locked_item", item_id, nonce, seat_id)
		)
	var progression := _progression_for_seat(seat_id)
	var price := int(item.price)
	if int(progression.money) < price:
		return _remember_purchase(
			nonce_key,
			_purchase_result(false, "insufficient_funds", item_id, nonce, seat_id)
		)
	if not _can_apply_shop_effect(item, seat_id):
		return _remember_purchase(
			nonce_key,
			_purchase_result(false, "upgrade_at_cap", item_id, nonce, seat_id)
		)
	progression.money = int(progression.money) - price
	_apply_shop_effect(item, seat_id)
	_emit_event("shop_purchase", {
		"seat_id": seat_id,
		"item_id": item_id,
		"x_fp": (FIELD_WIDTH >> 1) * FP_ONE,
		"y_fp": (FIELD_HEIGHT >> 1) * FP_ONE,
	})
	return _remember_purchase(
		nonce_key,
		_purchase_result(true, "accepted", item_id, nonce, seat_id)
	)


func set_shop_ready(seat_id: int, ready: bool) -> bool:
	if not _configured or _phase != PHASE_SHOP:
		return _set_error("shop readiness is only valid in the shop")
	if _shop_warp_until_tick > 0 and _tick <= _shop_warp_until_tick:
		return _set_error("shop input guard is still active")
	if not _seat_is_participating(seat_id):
		return _set_error("seat is not participating in this match")
	_shop_ready[seat_id] = ready
	_try_leave_shop()
	return true


func clear_transient_seat_state(seat_id: int) -> bool:
	if seat_id < 0 or seat_id >= _input_masks.size():
		return false
	_input_masks[seat_id] = 0
	_previous_input_masks[seat_id] = 0
	_secondary_rocket_armed[seat_id] = true
	_shop_ready[seat_id] = false
	var retained_bonus_actions: Array = []
	for action_value in _bonus_action_queue:
		var action: Dictionary = action_value
		if int(action.get("seat_id", -1)) != seat_id:
			retained_bonus_actions.append(action)
	_bonus_action_queue = retained_bonus_actions
	_bonus_action_last_target_tick[seat_id] = -1
	return true


func _step_level() -> void:
	_level_tick += 1
	if _is_retail_big_boss_level():
		_step_retail_big_boss_level()
		return
	if _level_eight_result_initialized:
		_step_level_eight_results()
		return
	_qualifying_kills_this_tick = 0
	_update_progression_timers()
	_spawn_due_waves()
	_resolve_pickup_collisions()
	_resolve_player_projectile_collisions()
	# Retail runs the three secret-ship spawners between the collision/death
	# dispatcher and the motion dispatcher (FUN_005afc50 at 0x005b1237), in this
	# exact order: money sucker, hurry-up, guard.
	_step_money_sucker_spawner()
	_step_hurry_up_spawner()
	_step_guard_spawner()
	_update_player_projectiles()
	_update_pickup_motion()
	_update_common_projectiles()
	# FUN_00601cd0 runs immediately before the motion dispatcher.
	_step_effect_pool()
	_resolve_effect_pool_collisions()
	_update_enemies()
	_update_players()
	_update_respawns()
	_resolve_enemy_player_collisions()
	_resolve_enemy_projectile_collisions()
	_tighten_enemy_behavior_timers(_qualifying_kills_this_tick)
	_remove_expired_entities()
	if _warp_transition_requested:
		_consume_warp_transition_request()
		_refresh_enemy_watchdog_timestamp_from_render()
		return
	_check_level_end()
	_refresh_enemy_watchdog_timestamp_from_render()


func _step_retail_big_boss_level() -> void:
	if not _boss_entered and not _enter_retail_big_boss(false):
		return
	# FUN_00605fe0 clears the single deferred alien-shot handle before scanning
	# state 13. A closed flush gate therefore leaves pending state visible in the
	# prior hash for exactly one tick, then discards it here.
	_boss_pending_deferred_sound.clear()
	_flush_deferred_boss_entry_events()
	_enemy_liveness_idle_updates = 0
	_qualifying_kills_this_tick = 0
	_update_progression_timers()
	if _boss_runtime_blocked:
		_update_players(false, false)
		_update_respawns()
		_remove_expired_entities()
		_advance_retail_global_sound_gate()
		return

	# FUN_00585840 owns state-13 damage before either projectile array moves.
	# This keeps shots spawned by the player dispatcher ineligible until the
	# following authoritative tick, matching the ordinary combat boundary.
	_resolve_boss_player_projectile_collisions()
	_update_player_projectiles()
	_update_pickup_motion()
	# Common shots that existed at tick entry move before state 13 may append new
	# shots. The controller's reserve/finalize pair publishes during its step, so
	# new boss shots do not move until the next tick.
	_update_common_projectiles()

	var tick_scale := _boss_tick_scale()
	_boss_projectile_sheet = _active_boss_projectile_sheet()
	var controller_result: Dictionary = _retail_big_boss.step(
		_tick,
		tick_scale,
		_players
	)
	_ingest_boss_controller_result(controller_result)
	# The retail main loop calls FUN_00567990 immediately after FUN_00605fe0:
	# direct bigfire is already published, then the process-global counter may
	# flush the final overwritten alienshoot2 handle.
	_advance_retail_global_sound_gate()
	if not _boss_runtime_blocked:
		var effects_result: Dictionary = _retail_big_boss_effects.step(
			tick_scale,
			_rng,
			{"paused": false}
		)
		if not bool(effects_result.get("ok", false)):
			_block_boss_runtime(String(effects_result.get(
				"error",
				_retail_big_boss_effects.get_last_error()
			)))

	_update_players()
	_update_respawns()
	_resolve_enemy_projectile_collisions()
	_remove_expired_entities()

	# The renderer consumes the pre-mutation projection. The executable then
	# decrements the shared flash counter once per rendered part even headlessly.
	var render_result: Dictionary = _retail_big_boss.complete_render_pass()
	if render_result.get("render_snapshot") is Dictionary:
		_boss_render_snapshot = (
			render_result.get("render_snapshot", {}) as Dictionary
		).duplicate(true)
	_ingest_boss_controller_result(render_result, false)
	if _boss_terminal_route_pending and not _boss_runtime_blocked:
		_finish_retail_big_boss_encounter()


func _boss_tick_scale() -> float:
	return Rng._float32(_simulation_scale_float())


func _is_retail_big_boss_level() -> bool:
	var authored_level_id := authored_level_id_for(_level_id)
	if not _boss_runtimes_by_level.has(authored_level_id):
		return false
	var level: Dictionary = _level_data_for(_level_id)
	var bundle := _boss_runtimes_by_level.get(authored_level_id, {}) as Dictionary
	var contract := bundle.get("contract", {}) as Dictionary
	return (
		level.has("authored_lvd")
		and int((level.authored_lvd as Dictionary).get("level_mode_id", 0))
		== int(contract.get("level_mode_id", 0))
	)


func _enter_retail_big_boss(defer_entry_events: bool) -> bool:
	if _boss_entered:
		return true
	var authored_level_id := authored_level_id_for(_level_id)
	var bundle_value: Variant = _boss_runtimes_by_level.get(authored_level_id, {})
	if not bundle_value is Dictionary or (bundle_value as Dictionary).is_empty():
		return _set_error("retail boss entry requires a validated catalog contract")
	var bundle := bundle_value as Dictionary
	_boss_contract = (bundle.get("contract", {}) as Dictionary).duplicate(true)
	_retail_big_boss = bundle.get("controller", RetailBigBossScript.new())
	_retail_big_boss_effects = bundle.get("effects", RetailBigBossEffectsScript.new())
	if _boss_contract.is_empty():
		return _set_error("retail boss registry contains an empty contract")
	_retail_big_boss_effects.reset()
	_boss_runtime_blocked = false
	_boss_terminal_route_pending = false
	_boss_completion_marked = false
	_boss_reward_applied = false
	_boss_last_reward_score = 0
	_boss_destroyed_counts_by_seat = [0, 0]
	_boss_deferred_entry_events.clear()
	var current_seat := clampi(_turn_seat, 0, 1)
	var current_flags := _match_persistent_flags_for_seat(current_seat)
	var result: Dictionary = _retail_big_boss.enter(
		_level_data_for(_level_id),
		_rng,
		{
			"allocate_common_projectile": Callable(
				self,
				"_allocate_retail_boss_common_projectile"
			),
			"finalize_common_projectile": Callable(
				self,
				"_finalize_retail_boss_common_projectile"
			),
			"dispatch_retail_effect": Callable(
				self,
				"_dispatch_retail_big_boss_effect"
			),
		},
		{
			"mode": _mode,
			"coop_balance": _balance,
			"difficulty": _difficulty_id,
			"tick": _tick,
			"now_ms": _simulation_milliseconds(),
			"tick_scale": _boss_tick_scale(),
			"only_blue_coins_active": bool(
				current_flags.only_blue_coins_active
			),
			# Retail derives the mirror from the display level number
			# ((level // 100) & 1); for authored levels this equals the
			# contract value, for wrapped endless levels it alternates.
			"mirror_x_override": endless_mirror_for_level(_level_id),
			"endless_steps": endless_steps_for_level(_level_id),
		}
	)
	if not bool(result.get("ok", false)):
		return _set_error(String(result.get(
			"error",
			_retail_big_boss.get_last_error()
		)))
	_boss_entered = true
	_boss_render_snapshot = (
		result.get("snapshot", _retail_big_boss.snapshot()) as Dictionary
	).duplicate(true)
	_boss_projectile_sheet = _active_boss_projectile_sheet()
	_ingest_boss_controller_result(result, true, defer_entry_events)
	return not _boss_runtime_blocked


func _active_boss_projectile_allocation() -> Dictionary:
	return _boss_contract.get("projectile_allocation", {}) as Dictionary


func _active_boss_attack_contract(projectile_type: int) -> Dictionary:
	if projectile_type == int((_boss_contract.get("aimed_fire", {}) as Dictionary).get(
		"projectile_type",
		15
	)):
		return _boss_contract.get("aimed_fire", {}) as Dictionary
	if projectile_type == int((_boss_contract.get("opcode_2", {}) as Dictionary).get(
		"projectile_type",
		14
	)):
		return _boss_contract.get("opcode_2", {}) as Dictionary
	return {}


func _active_boss_projectile_sheet() -> String:
	return String(_active_boss_projectile_allocation().get(
		"enemy_sheet_id",
		RETAIL_BIG_BOSS_PROJECTILE_SHEET
	))


func _ingest_boss_controller_result(
	result: Dictionary,
	update_render_snapshot: bool = true,
	defer_events: bool = false
) -> void:
	if typeof(result.get("ok")) != TYPE_BOOL:
		_block_boss_runtime("retail boss controller omitted its result status")
		return
	if typeof(result.get("error")) != TYPE_STRING:
		_block_boss_runtime("retail boss controller omitted its result error")
		return
	if not bool(result.ok):
		var controller_error := String(result.error)
		if controller_error.is_empty():
			controller_error = _retail_big_boss.get_last_error()
		if controller_error.is_empty():
			controller_error = "retail boss controller reported an unspecified failure"
		_block_boss_runtime(controller_error)
		return
	if not String(result.error).is_empty():
		_block_boss_runtime(
			"successful retail boss controller result contained an error"
		)
		return
	var events_value: Variant = result.get("events")
	if not events_value is Array:
		_block_boss_runtime("retail boss controller events must be an array")
		return
	var normalized_events: Array[Dictionary] = []
	for event_value in events_value as Array:
		if not event_value is Dictionary:
			_block_boss_runtime("retail boss controller emitted a non-object event")
			return
		var event := (event_value as Dictionary).duplicate(true)
		var kind := String(event.get("kind", ""))
		if not RETAIL_BIG_BOSS_EVENT_KINDS.has(kind):
			_block_boss_runtime(
				"retail boss controller emitted an unknown event: %s" % kind
			)
			return
		normalized_events.append(event)
	if update_render_snapshot and result.get("snapshot") is Dictionary:
		_boss_render_snapshot = (
			result.get("snapshot", {}) as Dictionary
		).duplicate(true)
	for event in normalized_events:
		if defer_events:
			_boss_deferred_entry_events.append(event)
		else:
			_handle_boss_controller_event(event)
			if _boss_runtime_blocked:
				return


func _flush_deferred_boss_entry_events() -> void:
	var deferred := _boss_deferred_entry_events.duplicate(true)
	_boss_deferred_entry_events.clear()
	for event_value in deferred:
		_handle_boss_controller_event(event_value as Dictionary)
		if _boss_runtime_blocked:
			return


func _handle_boss_controller_event(event: Dictionary) -> void:
	var kind := String(event.get("kind", ""))
	var sounds := _boss_contract.get("sounds", {}) as Dictionary
	if kind.is_empty():
		_block_boss_runtime("retail boss controller emitted an event without kind")
		return
	match kind:
		"boss_music":
			if String(event.get("key", "")) != String(sounds.get("music", "")):
				_block_boss_runtime("retail boss music event violates its contract")
				return
			_emit_boss_root_event("music_cue", {
				"key": String(event.get("key", "")),
				"action": "play",
			})
		"boss_hum":
			if String(event.get("key", "")) != String(sounds.get("hum", "")):
				_block_boss_runtime("retail boss hum event violates its contract")
				return
			var action := String(event.get("action", ""))
			if action == "start_loop":
				_emit_boss_root_event("audio_loop_started", {
					"sound_key": String(event.get("key", "boss")),
					"handle": RETAIL_BIG_BOSS_HUM_HANDLE,
					"frequency_hz": int(event.get("pitch", 0)),
					"pitch_delta": int(event.get("pitch_delta", 0)),
				})
			elif action == "stop":
				_emit_boss_root_event("audio_loop_stopped", {
					"sound_key": String(event.get("key", "boss")),
					"handle": RETAIL_BIG_BOSS_HUM_HANDLE,
				})
			elif action == "slide_pitch":
				_emit_boss_root_event("boss_hum_pitch", {
					"sound_key": String(event.get("key", "boss")),
					"handle": RETAIL_BIG_BOSS_HUM_HANDLE,
					"frequency_hz": int(event.get("pitch", 0)),
					"duration_ms": int(event.get("duration_ms", 0)),
				})
			else:
				_block_boss_runtime("retail boss hum event has an invalid action")
		"sound":
			var cue_reason := String(event.get("key", ""))
			var allowed_sound_keys := [
				String(sounds.get("hit", "")),
				String(sounds.get("terminal_hit", "")),
				String(sounds.get("death", "")),
				String(sounds.get("aimed_projectile", "")),
				String(sounds.get("opcode_2_direct", "")),
			]
			if not allowed_sound_keys.has(cue_reason):
				_block_boss_runtime(
					"retail boss sound event has an untraced sample: %s" % cue_reason
				)
				return
			var sound_fields := {
				"key": cue_reason,
				"cue_reason": cue_reason,
				"frequency_hz": int(event.get("frequency", 0)),
				"deadline_ms": int(event.get("deadline_ms", -1)),
				"retail_pan_bug": int(event.get("retail_pan_bug", 0)),
			}
			if event.has("volume"):
				sound_fields["volume_index"] = int(event.volume)
			_emit_boss_root_event("sound_cue", sound_fields)
		"boss_deferred_sound":
			var deferred_sound_key := String(sounds.get("opcode_2_deferred", ""))
			if (
				String(event.get("key", "")) != deferred_sound_key
				or String(event.get("overwrite", "")) != "last_allocated_wins"
				or String(event.get("flush_gate", ""))
				!= "alternating_global_sound_tick"
				or not bool(event.get("discard_if_gate_closed", false))
				or String(event.get("spatial_lookup", ""))
				!= "FUN_00627530_then_af6048"
				or not bool(event.get("x_clamp_uses_surface_height", false))
			):
				_block_boss_runtime("retail boss deferred sound violates its traced contract")
				return
			_boss_pending_deferred_sound = {
				"key": deferred_sound_key,
				"frequency": int(event.get("frequency", 0)),
				"retail_left": float(event.get("retail_left", 0.0)),
				"retail_top": float(event.get("retail_top", 0.0)),
				"spatial_lookup": String(event.get("spatial_lookup", "")),
				"x_clamp_uses_surface_height": bool(
					event.get("x_clamp_uses_surface_height", false)
				),
			}
		"boss_projectile_spawned":
			_update_boss_projectile_from_event(event)
			_emit_boss_root_event(kind, event)
		"boss_reward":
			_apply_boss_reward_event(event)
		"score_popup":
			var popup := event.duplicate(true)
			popup["score"] = _boss_last_reward_score
			_emit_boss_root_event(kind, popup)
		"boss_level_complete_mark":
			_apply_boss_completion_mark(event)
		"boss_defeated":
			_boss_terminal_route_pending = true
			_emit_boss_root_event(kind, event)
		"boss_burst_effect", "boss_entered", "boss_hit", "boss_projectile_effect", "boss_retail_effect":
			_emit_boss_root_event(kind, event)
		_:
			_block_boss_runtime(
				"retail boss controller emitted an unknown event: %s" % kind
			)


func _emit_boss_root_event(kind: String, source: Dictionary) -> void:
	var fields := source.duplicate(true)
	fields.erase("event_id")
	fields.erase("tick")
	fields.erase("kind")
	fields.erase("type")
	if fields.has("x") and not fields.has("x_fp"):
		fields["x_fp"] = roundi(float(fields.x) * FP_ONE)
	if fields.has("y") and not fields.has("y_fp"):
		fields["y_fp"] = roundi(float(fields.y) * FP_ONE)
	_emit_event(kind, fields)


func _advance_retail_global_sound_gate() -> void:
	var previous := _retail_global_sound_gate
	_retail_global_sound_gate = previous - 1
	if previous != 0:
		return
	_retail_global_sound_gate = 1
	if _boss_pending_deferred_sound.is_empty():
		return
	var pending := _boss_pending_deferred_sound.duplicate(true)
	_boss_pending_deferred_sound.clear()
	var sound_key := String(pending.get("key", ""))
	_emit_boss_root_event("sound_cue", {
		"key": sound_key,
		"cue_reason": sound_key,
		"frequency_hz": int(pending.get("frequency", 0)),
		"retail_left_fp": roundi(
			float(pending.get("retail_left", 0.0)) * FP_ONE
		),
		"retail_top_fp": roundi(
			float(pending.get("retail_top", 0.0)) * FP_ONE
		),
		"x_fp": roundi(float(pending.get("retail_left", 0.0)) * FP_ONE),
		"y_fp": roundi(float(pending.get("retail_top", 0.0)) * FP_ONE),
		"spatial_lookup": String(pending.get("spatial_lookup", "")),
		"x_clamp_uses_surface_height": bool(
			pending.get("x_clamp_uses_surface_height", false)
		),
	})


func _retail_mode_calls_global_sound_gate() -> bool:
	# FUN_00567990 has exactly five retail main-mode callers. Keep this mapping
	# at the pre-step boundary because a mode may transition during its update.
	match _phase:
		PHASE_LEVEL: # retail main mode 2
			return true
		PHASE_GET_READY: # retail modes 0x0c (standard) and 0x16 (turn/sequential)
			return true
		PHASE_WARP: # retail main mode 0x0d
			return true
		PHASE_WARP_MALFUNCTION: # retail main mode 0x10
			return true
		# Shop is mode 9. Memory, Meteor, and Gem Drop are modes 0x0b,
		# 0x0a, and 0x12. None of those dispatch FUN_00567990.
	return false


func _update_boss_projectile_from_event(event: Dictionary) -> void:
	var projectile_id := int(event.get("projectile_id", 0))
	for projectile_value in _projectiles:
		var projectile := projectile_value as Dictionary
		if int(projectile.get("id", 0)) != projectile_id:
			continue
		for key in ["phase_x", "phase_y", "sound_frequency", "source_record_index"]:
			if event.has(key):
				projectile[key] = event[key]
		return
	_block_boss_runtime("boss projectile event references an unallocated common slot")


func _apply_boss_reward_event(event: Dictionary) -> void:
	if _boss_reward_applied:
		_block_boss_runtime("retail boss reward was emitted more than once")
		return
	var owner_seat_id := clampi(int(event.get("owner_seat_id", 0)), 0, 1)
	var progression := _progression_for_seat(owner_seat_id)
	var multiplier := (
		int(progression.get("score_multiplier", 1))
		if bool(event.get("apply_active_score_multiplier", false))
		else 1
	)
	_boss_last_reward_score = int(event.get("base_score", 0)) * multiplier
	progression.score = int(progression.score) + _boss_last_reward_score
	_boss_reward_applied = true
	var forwarded := event.duplicate(true)
	forwarded["score"] = _boss_last_reward_score
	_emit_boss_root_event("boss_reward", forwarded)


func _apply_boss_completion_mark(event: Dictionary) -> void:
	if _boss_completion_marked:
		_block_boss_runtime("retail boss completion mark was emitted more than once")
		return
	if (
		int(event.get("level_id", 0)) != int(_boss_contract.get("level_id", 0))
		or not bool(event.get("rank_markers_unchanged", false))
		or not bool(event.get("ordinary_completion_bonus_and_rockets", false))
	):
		_block_boss_runtime("retail boss completion mark violates its catalog contract")
		return
	var owner_seat_id := clampi(int(event.get("owner_seat_id", 0)), 0, 1)
	_boss_destroyed_counts_by_seat[owner_seat_id] += int(
		event.get("increment_killer_destroyed_count", 0)
	)
	if _mode == MODE_COOP and _balance == BALANCE_CLASSIC:
		var partner := 1 - owner_seat_id
		_boss_destroyed_counts_by_seat[partner] += int(
			event.get("classic_coop_partner_delta", 0)
		)
	_level_total_entities = 1
	_level_killed_entities = 1
	_level_escaped_entities = 0
	_level_resolved = true
	_level_resolution_tick = _tick
	_boss_completion_marked = true
	_award_final_kill_rockets(owner_seat_id, true)
	_emit_boss_root_event("boss_level_complete_mark", event)
	_emit_event("level_resolved", {
		"level_id": _level_id,
		"killed": 1,
		"escaped": 0,
		"resolution_tick": _tick,
		"reason": "retail_big_boss_controller",
	})


func _finish_retail_big_boss_encounter() -> void:
	if not _boss_completion_marked or not _retail_big_boss.is_defeated():
		_block_boss_runtime("boss terminal routing requires the traced defeat mark")
		return
	_boss_terminal_route_pending = false
	_emit_event("level_completed", {"level_id": _level_id})
	if _level_id >= _end_level_id:
		_complete_campaign()
		return
	if _level_id == RETAIL_CREDITS_LEVEL:
		# Retail rolls the credits after the level-100 boss and then continues
		# the campaign; the credits are an interstitial, not an ending.
		_begin_credits_interstitial()
		return
	_begin_get_ready(_level_id + 1)


func _block_boss_runtime(message: String) -> void:
	if _boss_runtime_blocked:
		return
	_boss_runtime_blocked = true
	last_error = "retail boss runtime blocked: %s" % message
	_emit_event("boss_controller_error", {"reason": last_error})


func _step_shop() -> void:
	# Mode 13 arms this 500-ms fade/input guard only after the full warp has
	# finalized. The shop already owns the dispatcher while equality survives.
	if _shop_warp_until_tick > 0 and _tick <= _shop_warp_until_tick:
		return
	for seat_id in range(2):
		if not _seat_is_participating(seat_id):
			continue
		var confirm_pressed := _action_just_pressed(seat_id, ACTION_CONFIRM)
		var ready_pressed := _action_just_pressed(seat_id, ACTION_READY)
		if confirm_pressed or ready_pressed:
			_shop_ready[seat_id] = true
		if _action_just_pressed(seat_id, ACTION_CANCEL):
			_shop_ready[seat_id] = false
	_try_leave_shop()


func _step_rank_promotion() -> void:
	# Retail mode 0x14 performs its sparkle roll before polling the promotion
	# deadline and held fire state, including on the frame that exits the mode.
	_consume_rank_promotion_firework_rng()
	var minimum_elapsed := _tick >= _rank_promotion_minimum_tick
	var fire_held := (
		_rank_promotion_seat_id >= 0
		and (_input_masks[_rank_promotion_seat_id] & ACTION_FIRE) != 0
	)
	if _tick >= _rank_promotion_timeout_tick or (minimum_elapsed and fire_held):
		_finish_rank_promotion()


func _step_get_ready() -> void:
	if _pending_level_id <= 0 or _tick <= _get_ready_until_tick:
		return
	_begin_level(_pending_level_id)


func _step_bonus_mode() -> void:
	# Modes 0x0b/0x0a own the dispatcher. Nothing from the ordinary combat
	# pipeline is advanced here; only the selected deterministic controller and
	# its owning progression may change.
	match _active_bonus_mode_kind():
		"memory_station":
			_step_memory_station()
		"meteor_storm":
			_step_meteor_storm()
		"gem_drop":
			_step_gem_drop()
		_:
			_finish_bonus_mode_boundary("")


func _step_memory_station() -> void:
	var seat_id := _bonus_mode_owner_seat_id
	if seat_id < 0:
		_finish_bonus_mode_boundary("memory_station")
		return
	var now_ms := _simulation_milliseconds()
	var sampled_input_mask := _input_masks[seat_id]
	var semantic_actions := _normalized_memory_actions(seat_id, now_ms)
	# Retain the sampled Secondary bit only as the retail countdown-suppression
	# signal. The normalized semantic action remains the sole replay/hash input;
	# a duplicate controller attempt is rejected by the same 25-ms gate.
	var controller_mask := sampled_input_mask & ~ACTION_FIRE
	var result: Dictionary = _memory_station.step(
		_tick,
		now_ms,
		controller_mask,
		semantic_actions
	)
	if not bool(result.get("ok", false)):
		_emit_event("bonus_mode_controller_error", {
			"special_mode": "memory_station",
			"reason": String(result.get("error", _memory_station.get_last_error())),
		})
		return
	var progression := _progression_for_seat(seat_id)
	_apply_progression_deltas(progression, result.get("progression_deltas", {}))
	_forward_bonus_controller_events(result.get("events", []))
	for effect_value in result.get("bonus_actions", []):
		if effect_value is Dictionary:
			_resolve_memory_tile_effect(effect_value, progression, seat_id)
	if _pending_gem_drop_transition:
		_activate_pending_gem_drop_transition()
		return
	var controller_snapshot := _memory_station.snapshot()
	var remaining_ms := maxi(0, int(controller_snapshot.get("remaining_ms", 0)))
	progression.special_mode_ticks = _milliseconds_to_ticks_ceil(remaining_ms)
	_bonus_mode_until_tick = _tick + int(progression.special_mode_ticks)
	var completion: Dictionary = result.get("completion", {})
	if completion.is_empty():
		return
	_record_bonus_round_completion(seat_id, completion)
	_finish_bonus_mode_boundary("memory_station")


func _step_meteor_storm() -> void:
	var seat_id := _bonus_mode_owner_seat_id
	if seat_id < 0:
		_finish_bonus_mode_boundary("meteor_storm")
		return
	var now_ms := _simulation_milliseconds()
	if not _bonus_mode_completion.is_empty():
		var remaining_transition_ms := maxi(
			0,
			_bonus_mode_transition_until_ms - now_ms
		)
		var transition_progression := _progression_for_seat(seat_id)
		transition_progression.special_mode_ticks = _milliseconds_to_ticks_ceil(
			remaining_transition_ms
		)
		_bonus_mode_until_tick = _tick + int(
			transition_progression.special_mode_ticks
		)
		# Retail keeps the result screen at the exact deadline equality.
		if now_ms > _bonus_mode_transition_until_ms:
			_finish_bonus_mode_boundary("meteor_storm")
		return

	var action_mask := _input_masks[seat_id] & (
		ACTION_LEFT | ACTION_RIGHT | ACTION_FIRE
	)
	var result: Dictionary = _meteor_storm.step(_tick, now_ms, action_mask)
	if not bool(result.get("ok", false)):
		_emit_event("bonus_mode_controller_error", {
			"special_mode": "meteor_storm",
			"reason": String(result.get("error", _meteor_storm.get_last_error())),
		})
		return
	var progression := _progression_for_seat(seat_id)
	_apply_meteor_progression_deltas(
		progression,
		seat_id,
		result.get("profile_deltas", {})
	)
	var controller_snapshot := _meteor_storm.snapshot()
	progression.drunk_ticks = int(
		controller_snapshot.get("drunk_ticks_remaining", progression.get("drunk_ticks", 0))
	)
	_forward_bonus_controller_events(result.get("events", []))
	if _pending_gem_drop_transition:
		_activate_pending_gem_drop_transition()
		return
	var completion: Dictionary = result.get("completion", {})
	if completion.is_empty():
		return
	_bonus_mode_completion = completion.duplicate(true)
	_bonus_mode_transition_until_ms = now_ms + maxi(
		0,
		int(completion.get("retail_transition_ms", 0))
	)
	progression.special_mode_ticks = _milliseconds_to_ticks_ceil(
		maxi(0, _bonus_mode_transition_until_ms - now_ms)
	)
	_bonus_mode_until_tick = _tick + int(progression.special_mode_ticks)
	_record_bonus_round_completion(seat_id, completion)


func _step_gem_drop() -> void:
	var seat_id := _bonus_mode_owner_seat_id
	if seat_id < 0:
		_finish_gem_drop_boundary()
		return
	# State 18 invokes the ordinary primary player controller during both the
	# four-second introduction and active play. Its dispatcher does not advance
	# the projectiles that primary fire may allocate; the terminal pool reset
	# removes them. Secondary remains suppressed by the state-18 branch.
	_update_gem_drop_players()
	var result: Dictionary = _gem_drop.step(
		_tick,
		_simulation_milliseconds(),
		_gem_drop_player_states()
	)
	if not bool(result.get("ok", false)):
		_emit_event("bonus_mode_controller_error", {
			"special_mode": "gem_drop",
			"reason": String(result.get("error", _gem_drop.get_last_error())),
		})
		return
	for reward_value in result.get("rewards", []):
		if not reward_value is Dictionary:
			continue
		var reward: Dictionary = reward_value
		var reward_seat := clampi(int(reward.get("seat_id", seat_id)), 0, 1)
		var progression := _progression_for_seat(reward_seat)
		progression.score = mini(
			250000000,
			int(progression.get("score", 0)) + int(reward.get("score", 0))
		)
	_forward_bonus_controller_events(result.get("events", []))
	var controller_snapshot := _gem_drop.snapshot()
	var intro_ticks := _milliseconds_to_ticks_ceil(
		maxi(0, int(controller_snapshot.get("intro_remaining_ms", 0)))
	)
	var tick_scale := (
		_simulation_scale_float()
	)
	var active_ticks := int(ceil(
		maxf(0.0, float(controller_snapshot.get("remaining", 0.0)))
		/ maxf(tick_scale, 0.000001)
	))
	var owner_progression := _progression_for_seat(seat_id)
	owner_progression.special_mode_ticks = intro_ticks + active_ticks
	_bonus_mode_until_tick = _tick + int(owner_progression.special_mode_ticks)
	if bool(result.get("complete", false)):
		_finish_gem_drop_boundary()


func _apply_meteor_progression_deltas(
	progression: Dictionary,
	seat_id: int,
	deltas_value: Variant
) -> void:
	if not deltas_value is Dictionary:
		return
	var deltas := deltas_value as Dictionary
	for key_value in deltas:
		var key := String(key_value)
		var amount := int(deltas[key_value])
		match key:
			"money":
				progression.money = clampi(
					int(progression.get("money", 0)) + amount,
					0,
					MAX_MONEY
				)
			"gem_count":
				progression.gem_count = maxi(
					0,
					int(progression.get("gem_count", 0)) + amount
				)
			"meteor_score":
				if seat_id >= 0 and seat_id < _profile_stats_by_seat.size():
					var stats: Dictionary = _profile_stats_by_seat[seat_id]
					stats.meteor_current_score = maxi(
						0,
						int(stats.get("meteor_current_score", 0)) + amount
					)
					stats.meteor_score = maxi(
						int(stats.get("meteor_score", 0)),
						int(stats.meteor_current_score)
					)
			_:
				progression[key] = int(progression.get(key, 0)) + amount


func _normalized_memory_actions(seat_id: int, now_ms: int) -> Array:
	var actions: Array = []
	for action_value in _bonus_actions_this_tick:
		if not action_value is Dictionary:
			continue
		var action: Dictionary = action_value
		if int(action.get("seat_id", -1)) == seat_id:
			actions.append(action.duplicate(true))
	var has_device_action := not actions.is_empty()
	var action_kind := 0
	var tile_index := -1
	if not has_device_action and (_input_masks[seat_id] & ACTION_FIRE) != 0:
		var memory_snapshot := _memory_station.snapshot()
		tile_index = (
			int(memory_snapshot.get("cursor_col", 0)) * 8
			+ int(memory_snapshot.get("cursor_row", 0))
		)
		action_kind = BONUS_ACTION_SELECT_TILE
	elif not has_device_action and (_input_masks[seat_id] & ACTION_SECONDARY) != 0:
		action_kind = BONUS_ACTION_KILL_TIME
	if action_kind != 0:
		var validation: Dictionary = _memory_station.validate_action(
			action_kind,
			tile_index,
			_tick,
			now_ms
		)
		if bool(validation.get("ok", false)):
			var normalized := {
				"seat_id": seat_id,
				"target_tick": _tick,
				"action_kind": action_kind,
				"tile_index": tile_index,
			}
			actions.append(normalized)
			_bonus_actions_this_tick.append(normalized.duplicate(true))
			_bonus_action_last_target_tick[seat_id] = _tick
	# FIRE/SECONDARY are represented solely by the semantic action in state,
	# replay, and hash. Keyboard, gamepad, and mouse therefore converge after
	# this authoritative sampling boundary.
	_input_masks[seat_id] &= ~(ACTION_FIRE | ACTION_SECONDARY)
	return actions


func _apply_progression_deltas(
	progression: Dictionary,
	deltas_value: Variant
) -> void:
	if not deltas_value is Dictionary:
		return
	var deltas := deltas_value as Dictionary
	for key_value in deltas:
		var key := String(key_value)
		progression[key] = int(progression.get(key, 0)) + int(deltas[key_value])


func _forward_bonus_controller_events(events_value: Variant) -> void:
	if not events_value is Array:
		return
	for event_value in events_value:
		if not event_value is Dictionary:
			continue
		var source := (event_value as Dictionary).duplicate(true)
		var event_type := String(source.get("kind", "bonus_mode_event"))
		source["controller_event_id"] = int(
			source.get("event_id", source.get("id", 0))
		)
		for key in ["id", "event_id", "kind", "tick", "now_ms"]:
			source.erase(key)
		_emit_event(event_type, source)


func _resolve_memory_tile_effect(
	effect_value: Dictionary,
	progression: Dictionary,
	seat_id: int
) -> void:
	# Every settled numeric mutation is already represented by the controller's
	# additive progression_deltas. The parent owns only timers and dispatcher
	# transitions that cross the Memory Station boundary.
	match String(effect_value.get("effect_key", "")):
		"timed_score_multiplier":
			var expiry_ms := int(effect_value.get(
				"absolute_expiry_ms",
				_simulation_milliseconds() + int(effect_value.get("duration_ms", 0))
			))
			progression.score_multiplier_ticks = _milliseconds_to_ticks_ceil(
				maxi(0, expiry_ms - _simulation_milliseconds())
			)
		"gem_drop_progress_or_score":
			if String(effect_value.get("branch", "")) == "gem_drop_transition":
				var entered: Dictionary = _prepare_gem_drop(
					"memory_station",
					bool(effect_value.get("super_gem_drop", false)),
					seat_id,
					{}
				)
				_forward_bonus_controller_events(entered.get("events", []))
	_emit_event("memory_tile_effect", effect_value)


func _meteor_gem_drop_start_callback(payload: Dictionary) -> Dictionary:
	return _prepare_gem_drop(
		"meteor_storm",
		bool(payload.get("super_gem_drop", false)),
		int(payload.get("owner_seat_id", _bonus_mode_owner_seat_id)),
		payload
	)


func _prepare_gem_drop(
	source_mode: String,
	super_gem_drop: bool,
	seat_id: int,
	payload: Dictionary
) -> Dictionary:
	var players_for_entry := _gem_drop_player_states()
	var source_ship_value: Variant = payload.get("ship", {})
	if source_ship_value is Dictionary and seat_id >= 0 and seat_id < players_for_entry.size():
		var source_ship := source_ship_value as Dictionary
		var player: Dictionary = players_for_entry[seat_id]
		player.x_fp = int(source_ship.get("x_fp", player.x_fp))
		player.y_fp = int(source_ship.get("y_fp", player.y_fp))
		player.mask_frame = int(source_ship.get("frame_index", player.mask_frame))
	var progressions_for_entry: Array = []
	for progression_seat in range(2):
		progressions_for_entry.append(
			_progression_for_seat(progression_seat).duplicate(true)
		)
	# Meteor owns its progression deltas until its controller returns. Include
	# the already-awarded same-frame score in Gem Drop's 250M cap baseline.
	var pending_deltas_value: Variant = payload.get("progression_deltas", {})
	if pending_deltas_value is Dictionary and seat_id >= 0 and seat_id < 2:
		var pending_deltas := pending_deltas_value as Dictionary
		var pending_progression: Dictionary = progressions_for_entry[seat_id]
		pending_progression.score = (
			int(pending_progression.get("score", 0))
			+ int(pending_deltas.get("score", 0))
		)
	var restart_music := not _pending_gem_drop_transition
	var entered: Dictionary = _gem_drop.enter(
		clampi(seat_id, 0, 1),
		source_mode,
		super_gem_drop,
		players_for_entry,
		progressions_for_entry,
		_mode,
		_rng,
		_tick,
		_simulation_milliseconds(),
		restart_music
	)
	if not bool(entered.get("ok", false)):
		_emit_event("bonus_mode_controller_error", {
			"special_mode": "gem_drop",
			"reason": String(entered.get("error", _gem_drop.get_last_error())),
		})
		return entered
	_pending_gem_drop_transition = true
	_gem_drop_source_mode = source_mode
	_gem_drop_super = super_gem_drop
	return entered


func _activate_pending_gem_drop_transition() -> void:
	if not _pending_gem_drop_transition or _bonus_mode_owner_seat_id < 0:
		return
	var progression := _progression_for_seat(_bonus_mode_owner_seat_id)
	progression.special_mode = "gem_drop"
	var controller_snapshot := _gem_drop.snapshot()
	var intro_ticks := _milliseconds_to_ticks_ceil(
		maxi(0, int(controller_snapshot.get("intro_remaining_ms", 0)))
	)
	var tick_scale := (
		_simulation_scale_float()
	)
	var active_ticks := int(ceil(
		maxf(0.0, float(controller_snapshot.get("remaining", 0.0)))
		/ maxf(tick_scale, 0.000001)
	))
	progression.special_mode_ticks = intro_ticks + active_ticks
	_bonus_mode_until_tick = _tick + int(progression.special_mode_ticks)
	_bonus_mode_transition_until_ms = int(controller_snapshot.get("intro_until_ms", 0))
	_bonus_mode_completion.clear()
	_pending_gem_drop_transition = false
	_emit_event("gem_drop_boundary_started", {
		"seat_id": _bonus_mode_owner_seat_id,
		"source_mode": _gem_drop_source_mode,
		"super_gem_drop": _gem_drop_super,
		"intro_until_ms": int(controller_snapshot.get("intro_until_ms", 0)),
	})


func _gem_drop_player_states() -> Array:
	var result: Array = []
	for seat_id in range(2):
		var player: Dictionary = _players[seat_id]
		var progression := _progression_for_seat(seat_id)
		var state := player.duplicate(true)
		state["fighter_id"] = "fighter%d" % (seat_id + 1)
		state["drunk_active"] = int(progression.get("drunk_ticks", 0)) > 0
		result.append(state)
	return result


func _update_gem_drop_players() -> void:
	var controlled_seats: Array[int] = [_bonus_mode_owner_seat_id]
	if _mode == MODE_COOP:
		# Co-op is a remake-only simultaneous route. It retains the retail owner-
		# first collision order without an ownership RNG draw, while both human
		# fighters receive the same deterministic state-18 movement/fire callback.
		controlled_seats = [
			_bonus_mode_owner_seat_id,
			1 - _bonus_mode_owner_seat_id,
		]
	for seat_id in controlled_seats:
		if seat_id < 0 or seat_id >= _players.size():
			continue
		var player: Dictionary = _players[seat_id]
		if not bool(player.active) or not bool(player.alive):
			continue
		if int(player.invulnerable_ticks) > 0:
			player.invulnerable_ticks = int(player.invulnerable_ticks) - 1
		if int(player.projectile_suppression_ticks) > 0:
			player.projectile_suppression_ticks = (
				int(player.projectile_suppression_ticks) - 1
			)
		var progression := _progression_for_seat(seat_id)
		var mask := _input_masks[seat_id]
		var direction := 0
		var horizontal_active := false
		if (mask & ACTION_LEFT) != 0:
			direction = -1
			player.sprite_phase_half_steps = maxi(
				0,
				int(player.sprite_phase_half_steps) - 1
			)
			horizontal_active = true
		elif (mask & ACTION_RIGHT) != 0:
			direction = 1
			player.sprite_phase_half_steps = int(player.sprite_phase_half_steps) + 1
			if int(player.sprite_phase_half_steps) >= 22:
				player.sprite_phase_half_steps = 20
			horizontal_active = true
		if not horizontal_active:
			if int(player.sprite_phase_half_steps) < 10:
				player.sprite_phase_half_steps = int(player.sprite_phase_half_steps) + 1
			elif int(player.sprite_phase_half_steps) > 10:
				player.sprite_phase_half_steps = int(player.sprite_phase_half_steps) - 1
		player.mask_frame = mini(10, int(player.sprite_phase_half_steps) / 2)
		if int(progression.get("drunk_ticks", 0)) > 0:
			direction = -direction
		player.x_fp = Fixed.clamp_value(
			int(player.x_fp) + direction * _scaled_simulation_delta(
				mini(14 * FP_ONE, int(progression.speed_fp))
			),
			PLAYER_MIN_X_FP,
			PLAYER_MAX_X_FP
		)
		# Primary fire remains enabled in state 18. Secondary is intentionally
		# ignored because its later branch explicitly skips the weapon path.
		if _action_just_pressed(seat_id, ACTION_FIRE):
			_fire_player_weapon(player)
		if bool(progression.auto_fire) and (mask & ACTION_FIRE) != 0:
			var current_ms := _simulation_milliseconds()
			if current_ms > int(player.auto_fire_deadline_ms):
				_fire_player_weapon(player)
				player.auto_fire_deadline_ms = (
					current_ms + int(progression.auto_fire_delay_ms)
				)


func _gem_drop_pool_reset(reason: String, owner_seat_id: int) -> Dictionary:
	var draw_count_before := int(_rng.snapshot().get("draw_count", 0))
	var reset_seat := clampi(owner_seat_id, 0, 1)
	var captive_count := _captured_enemies_for_seat(reset_seat, false).size()
	var predicate_not_eight_count := maxi(
		0,
		AUTHORED_ENTITY_SLOT_COUNT - captive_count
	)
	var cleared_enemy_count := 0
	for enemy_value in _enemies:
		var enemy: Dictionary = enemy_value
		if (
			not bool(enemy.get("dead", false))
			and int(enemy.get("behavior_state_id", 0)) != 8
		):
			cleared_enemy_count += 1
	_clear_non_captured_enemies()
	_clear_projectiles()
	_pickups.clear()
	_authored_slot_seeds.clear()
	for _slot_index in range(predicate_not_eight_count):
		_authored_slot_seeds.append({
			"phase": _random_int(6),
			"countdown_sixths": 4 * SIMULATION_SCALE_DENOMINATOR,
			"direction": _random_int(2),
			"animation_step_fp": (
				_random_retail_float_fp(0.30000001192092896, 2.0) / 5
			),
		})
	_initialize_common_projectile_slots()
	if reason == "entry" and _level_total_entities > 0:
		# FUN_0059bb90 leaves every non-captive alien record inactive. The remake's
		# authored aggregate counter has no direct retail analogue, so outstanding
		# records become escapes to prevent a cleared level from deadlocking.
		_level_escaped_entities = maxi(
			_level_escaped_entities,
			maxi(0, _level_total_entities - _level_killed_entities)
		)
	var draw_count_after := int(_rng.snapshot().get("draw_count", 0))
	return {
		"reason": reason,
		"selected_seat_id": reset_seat,
		"predicate_not_eight_count": predicate_not_eight_count,
		"preserved_captive_count": captive_count,
		"cleared_enemy_count": cleared_enemy_count,
		"rng_draws": draw_count_after - draw_count_before,
	}


func _finish_gem_drop_boundary() -> void:
	var completed_source := _gem_drop_source_mode
	var completed_super := _gem_drop_super
	if _bonus_mode_owner_seat_id >= 0:
		var progression := _progression_for_seat(_bonus_mode_owner_seat_id)
		progression.special_mode = ""
		progression.special_mode_ticks = 0
	_phase = PHASE_LEVEL
	_bonus_mode_until_tick = 0
	_bonus_mode_transition_until_ms = _simulation_milliseconds() + 500
	_bonus_mode_owner_seat_id = -1
	_bonus_action_queue.clear()
	_bonus_actions_this_tick.clear()
	_bonus_action_last_target_tick = [-1, -1]
	_bonus_mode_completion.clear()
	_pending_gem_drop_transition = false
	_gem_drop_source_mode = ""
	_gem_drop_super = false
	# The state-18 completion tail has no stop/resume/open music call. The gems
	# track is left alone until a later ordinary transition changes it.
	_emit_event("bonus_mode_boundary_ended", {
		"special_mode": "gem_drop",
		"source_mode": completed_source,
		"super_gem_drop": completed_super,
		"return_phase": PHASE_LEVEL,
		"transition_guard_ms": 500,
		"music_unchanged": true,
		"x_fp": (FIELD_WIDTH >> 1) * FP_ONE,
		"y_fp": (FIELD_HEIGHT >> 1) * FP_ONE,
	})
	_try_resolve_level_counter("gem_drop_terminal")


func _record_bonus_round_completion(seat_id: int, completion: Dictionary) -> void:
	if seat_id < 0 or seat_id >= _profile_stats_by_seat.size():
		return
	var stats: Dictionary = _profile_stats_by_seat[seat_id]
	stats.bonus_rounds = int(stats.get("bonus_rounds", 0)) + 1
	var perfect := false
	if completion.has("mismatches"):
		perfect = int(completion.get("mismatches", 0)) == 0
	elif completion.has("tier"):
		perfect = String(completion.get("tier", "")) == "perfect"
	if bool(completion.get("success", false)) and perfect:
		stats.perfect_bonus_rounds = int(stats.get("perfect_bonus_rounds", 0)) + 1


func _milliseconds_to_ticks_ceil(milliseconds: int) -> int:
	if milliseconds <= 0:
		return 0
	return (milliseconds * TICKS_PER_SECOND + 999) / 1000


func _combat_state_hash() -> String:
	# Bonus controllers may advance their own shared-RNG stream and progression,
	# but none of the suspended ordinary-combat collections or counters.
	var frozen_state := {
		"level_tick": _level_tick,
		"players": _players,
		"enemies": _enemies,
		"projectiles": _projectiles,
		"common_projectile_slots": _common_projectile_slots,
		"pickups": _pickups,
		"spawned_waves": _spawned_waves,
		"authored_spawn_slot": _authored_spawn_slot,
		"supplemental_spawned": _supplemental_spawned,
		"platform_x_fp": _platform_x_fp,
		"platform_y_fp": _platform_y_fp,
		"platform_velocity_x_fp": _platform_velocity_x_fp,
		"platform_acceleration_x_fp": _platform_acceleration_x_fp,
		"level_total_entities": _level_total_entities,
		"level_killed_entities": _level_killed_entities,
		"level_escaped_entities": _level_escaped_entities,
		"level_resolved": _level_resolved,
		"level_resolution_tick": _level_resolution_tick,
		"level_eight_result_initialized": _level_eight_result_initialized,
		"level_eight_result_deadline_ms": _level_eight_result_deadline_ms,
		"level_eight_reveal_deadline_ms": _level_eight_reveal_deadline_ms,
		"level_eight_reveal_countdown": _level_eight_reveal_countdown,
		"level_eight_result_players": _level_eight_result_players,
		"level_eight_perfect_indices": _level_eight_perfect_indices,
		"group_kill_counts": _group_kill_counts,
		"cohort_kill_counts": _cohort_kill_counts,
	}
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(JSON.stringify(frozen_state).to_utf8_buffer())
	return context.finish().hex_encode()


func _finish_bonus_mode_boundary(completed_mode: String) -> void:
	if _bonus_mode_owner_seat_id >= 0:
		var progression := _progression_for_seat(_bonus_mode_owner_seat_id)
		progression.special_mode = ""
		progression.special_mode_ticks = 0
	_phase = PHASE_LEVEL
	_bonus_mode_until_tick = 0
	_bonus_mode_owner_seat_id = -1
	_bonus_action_queue.clear()
	_bonus_actions_this_tick.clear()
	_bonus_action_last_target_tick = [-1, -1]
	_bonus_mode_transition_until_ms = 0
	_bonus_mode_completion.clear()
	_pending_gem_drop_transition = false
	_gem_drop_source_mode = ""
	_gem_drop_super = false
	_emit_event("bonus_mode_boundary_ended", {
		"special_mode": completed_mode,
		"music_key": "warblade",
		"x_fp": (FIELD_WIDTH >> 1) * FP_ONE,
		"y_fp": (FIELD_HEIGHT >> 1) * FP_ONE,
	})


func _active_bonus_mode_kind() -> String:
	if _phase != PHASE_BONUS_MODE or _bonus_mode_owner_seat_id < 0:
		return ""
	return String(
		_progression_for_seat(_bonus_mode_owner_seat_id).get("special_mode", "")
	)


func _active_bonus_controller_hash_state() -> Dictionary:
	match _active_bonus_mode_kind():
		"memory_station":
			return _memory_station.state_for_hash()
		"meteor_storm":
			return _meteor_storm.state_for_hash()
		"gem_drop":
			return _gem_drop.state_for_hash()
	return {}


func _public_bonus_mode_snapshot() -> Dictionary:
	var kind := _active_bonus_mode_kind()
	var result := {
		"kind": kind,
		"owner_seat_id": _bonus_mode_owner_seat_id,
		"until_tick": _bonus_mode_until_tick,
		"transition_until_ms": _bonus_mode_transition_until_ms,
		"completion": _bonus_mode_completion.duplicate(true),
		"gem_drop_active": kind == "gem_drop",
		"gem_drop_source_mode": _gem_drop_source_mode,
		"super_gem_drop": _gem_drop_super,
		"suspended": _phase == PHASE_BONUS_MODE,
	}
	if _phase != PHASE_BONUS_MODE:
		return result
	var controller: Dictionary = {}
	if kind == "memory_station":
		controller = _memory_station.snapshot()
	elif kind == "meteor_storm":
		controller = _meteor_storm.snapshot()
	elif kind == "gem_drop":
		controller = _gem_drop.snapshot()
	for key in controller:
		result[key] = controller[key]
	# The route-visible discriminator cannot be overridden by controller data.
	result["kind"] = kind
	result["owner_seat_id"] = _bonus_mode_owner_seat_id
	result["until_tick"] = _bonus_mode_until_tick
	result["transition_until_ms"] = _bonus_mode_transition_until_ms
	result["completion"] = _bonus_mode_completion.duplicate(true)
	result["gem_drop_active"] = kind == "gem_drop"
	result["gem_drop_source_mode"] = _gem_drop_source_mode
	result["super_gem_drop"] = _gem_drop_super
	result["suspended"] = true
	return result


func _reset_warp_runtime_state() -> void:
	_warp_stage = 0
	_warp_stage_updates_remaining = 0
	_warp_visual_fp = 0
	_warp_scale = 0.0
	_warp_velocity = 0.0
	_warp_effect = 0.0
	_warp_offset = 0.0
	_background_draw_offset = 0.0
	_background_post_draw_offset = 0.0
	_warp_owned_skip = false
	# The executable keeps this gate denominator across warp entries and
	# replaces it after each malfunction. Its startup seed is assigned once the
	# exact initialization site is loaded below; zero safely disables the gate.
	_warp_malfunction_interval = 0
	_warp_malfunction_gate_calls = 0
	_warp_malfunction_file_id = 0
	_warp_malfunction_total = 0
	_warp_malfunction_killed = 0
	_warp_malfunction_missed = 0
	_warp_malfunction_resolution_tick = 0
	_warp_malfunction_transition_pending = false
	_warp_malfunction_message_until_tick = 0
	_warp_malfunction_message_cadence_tick = 0
	_warp_malfunction_message_cadence_remaining = 0
	_warp_transition_requested = false
	_warp_request_seat_id = 0
	_warp_request_cause = ""
	_warp_owner_seat_id = -1


func _request_warp_transition(cause: String, seat_id: int) -> void:
	_warp_transition_requested = true
	_warp_request_cause = cause
	_warp_request_seat_id = seat_id


func _consume_warp_transition_request() -> void:
	if not _warp_transition_requested:
		return
	var cause := _warp_request_cause
	var seat_id := _warp_request_seat_id
	_warp_transition_requested = false
	_warp_request_cause = ""
	_begin_warp(true, cause, seat_id)


func _begin_warp(owned_skip: bool, cause: String, seat_id: int = 0) -> void:
	_phase = PHASE_WARP
	_warp_owner_seat_id = clampi(seat_id, 0, _players.size() - 1)
	_warp_stage = 0
	_warp_stage_updates_remaining = WARP_STAGE_ONE_UPDATES
	_reset_warp_visuals()
	_warp_owned_skip = owned_skip
	_warp_malfunction_file_id = 0
	_warp_malfunction_total = 0
	_warp_malfunction_killed = 0
	_warp_malfunction_missed = 0
	_warp_malfunction_resolution_tick = 0
	_warp_malfunction_transition_pending = false
	_emit_event("warp_started", {
		"seat_id": seat_id,
		"cause": cause,
		"owned_skip": owned_skip,
		"level_id": _level_id,
		"x_fp": (FIELD_WIDTH >> 1) * FP_ONE,
		"y_fp": PLAYER_Y_FP,
	})


func _step_warp() -> void:
	# FUN_0061a... checks malfunction before every mode-13 subsystem update.
	# If it triggers, the new state-6 enemies still receive one movement/fire
	# update in this frame; mode-16 collision handling starts next frame.
	_update_progression_timers()
	var malfunction_started := _try_begin_warp_malfunction()
	_resolve_pickup_collisions()
	_update_player_projectiles()
	# The retail initializer zeroes all three stage counters before this same
	# frame reaches the visual callback, so that callback is a no-op on a hit.
	if not malfunction_started:
		_update_warp_player_animation()
	_update_pickup_motion()
	_update_common_projectiles()
	_update_enemies()
	# The gate changes retail's global mode immediately. Its entry frame reaches
	# the shared player callback as mode 16 (fire enabled); ordinary mode 13
	# frames keep the fire gate closed.
	_update_players(malfunction_started, true)
	_update_respawns()
	_remove_expired_entities()
	if _phase not in [PHASE_WARP, PHASE_WARP_MALFUNCTION]:
		_refresh_enemy_watchdog_timestamp_from_render()
		return
	if malfunction_started:
		_refresh_enemy_watchdog_timestamp_from_render()
		return
	_advance_warp_stage()
	_refresh_enemy_watchdog_timestamp_from_render()


func _update_warp_player_animation() -> void:
	if _warp_stage == 0:
		_warp_effect = Rng._float32(_warp_effect + Rng._float32(0.01))
		_warp_scale = Rng._float32(_warp_scale + Rng._float32(2.15))
		_warp_velocity = Rng._float32(_warp_velocity + Rng._float32(0.15))
		_warp_velocity = Rng._float32(
			_warp_velocity / Rng._float32(1.15)
		)
		_warp_offset = Rng._float32(_warp_offset + Rng._float32(0.25))
	elif _warp_stage == 1:
		_warp_velocity = Rng._float32(
			_warp_velocity / Rng._float32(1.15)
		)
		_warp_offset = Rng._float32(_warp_offset + Rng._float32(0.25))
	elif _warp_stage == 2:
		_warp_velocity = Rng._float32(
			_warp_velocity / Rng._float32(1.15)
		)
		_warp_scale = Rng._float32(_warp_scale - Rng._float32(2.15))
		_warp_velocity = Rng._float32(_warp_velocity - Rng._float32(0.15))
		_warp_effect = Rng._float32(_warp_effect - Rng._float32(0.01))
	_warp_visual_fp = roundi(_warp_scale * FP_ONE)


func _advance_background_scroll_presentation() -> void:
	# The retail renderer draws the current global offset, then stores one
	# float32 scale/20 update. Own both values at the authoritative 60 Hz step
	# so sparse network snapshots cannot multiply the newest scale by skipped
	# ticks. This state is presentation-only and never feeds gameplay decisions.
	_background_draw_offset = _background_post_draw_offset
	if _phase != PHASE_WARP:
		return
	var divisor := Rng._float32(20.0)
	var step := Rng._float32(_warp_scale / divisor)
	_background_post_draw_offset = Rng._float32(
		_background_post_draw_offset + step
	)
	if _background_post_draw_offset >= Rng._float32(600.0):
		_background_post_draw_offset = Rng._float32(
			_background_post_draw_offset - Rng._float32(600.0)
		)
	if _background_post_draw_offset <= Rng._float32(0.0):
		_background_post_draw_offset = Rng._float32(
			_background_post_draw_offset + Rng._float32(600.0)
		)


func _reset_warp_visuals() -> void:
	_warp_scale = Rng._float32(5.0)
	_warp_velocity = Rng._float32(0.0)
	_warp_effect = Rng._float32(0.0)
	_warp_offset = Rng._float32(0.0)
	_warp_visual_fp = 5 * FP_ONE


func _advance_warp_stage() -> void:
	_warp_stage_updates_remaining -= 1
	if _warp_stage_updates_remaining > 0:
		return
	if _warp_stage == 0:
		_warp_stage = 1
		_warp_stage_updates_remaining = WARP_STAGE_TWO_UPDATES
		return
	if _warp_stage == 1:
		_warp_stage = 2
		_warp_stage_updates_remaining = WARP_STAGE_THREE_UPDATES
		return
	_finalize_warp()


func _try_begin_warp_malfunction() -> bool:
	_warp_malfunction_gate_calls += 1
	if WARP_MALFUNCTION_FILES.is_empty() or _warp_malfunction_interval <= 0:
		return false
	# The gate draw is deliberately consumed before the visual >120 test.
	if _random_int(_warp_malfunction_interval) >= 4:
		return false
	if _warp_scale <= Rng._float32(120.0):
		return false
	var reset_class := _random_int(100)
	if reset_class <= 10:
		_warp_malfunction_interval = 6000 + _random_int(12000)
	else:
		_warp_malfunction_interval = 20000 + _random_int(8000)
	var presentation_pitch := 10000 + _random_int(4000)
	_begin_warp_malfunction(presentation_pitch)
	return true


func _begin_warp_malfunction(presentation_pitch: int) -> void:
	_phase = PHASE_WARP_MALFUNCTION
	# FUN_00582120 disables c0/c1/c2 and installs the exact visual tuple used
	# throughout mode 16. Natural return rearms c0 but preserves these values.
	_warp_stage = 0
	_warp_stage_updates_remaining = 0
	_warp_scale = Rng._float32(0.0)
	_warp_velocity = Rng._float32(-5.0)
	_warp_effect = Rng._float32(0.0)
	_warp_offset = Rng._float32(0.0)
	_warp_visual_fp = 0
	_warp_malfunction_message_until_tick = _tick + 2 * TICKS_PER_SECOND
	# E114B8 is armed for 300 ms, and mode 16 tests it strictly.
	_warp_malfunction_message_cadence_tick = _tick + 18
	_warp_malfunction_message_cadence_remaining = 1
	_warp_malfunction_file_id = 1 + _random_int(WARP_MALFUNCTION_FILES.size())
	_warp_malfunction_killed = 0
	_warp_malfunction_missed = 0
	_warp_malfunction_resolution_tick = 0
	_warp_malfunction_transition_pending = false
	_clear_non_captured_enemies()
	var scalar := maxi(2, _trunc_fp_to_int(int(_active_warp_progression().warp_fp)))
	var budget := 1 + _random_int(maxi(1, scalar - 1))
	var requested_total := budget + 1
	_warp_malfunction_total = _spawn_warp_malfunction_enemies(requested_total)
	_emit_event("warp_malfunction_started", {
		"file_id": _warp_malfunction_file_id,
		"enemy_total": _warp_malfunction_total,
		"presentation_pitch": presentation_pitch,
		"sfx_key": "alienshoot15",
		"frequency_hz": presentation_pitch,
		"source_hz": 32000,
		"message_until_tick": _warp_malfunction_message_until_tick,
		"x_fp": (FIELD_WIDTH >> 1) * FP_ONE,
		"y_fp": (FIELD_HEIGHT >> 1) * FP_ONE,
	})


func _step_warp_malfunction() -> void:
	var resume_after_updates := _warp_malfunction_transition_pending
	_qualifying_kills_this_tick = 0
	_update_warp_malfunction_message_cadence()
	_update_progression_timers()
	# Mode 16 scans the 150 pickup slots before player-shot collision. A gem
	# created by a kill below therefore cannot be collected until next frame.
	_resolve_pickup_collisions()
	_resolve_player_projectile_collisions()
	_update_player_projectiles()
	_update_pickup_motion()
	_update_common_projectiles()
	_update_enemies()
	_update_players()
	# FUN_005EB550 owns expiry/respawn at the end of the player callback, after
	# projectile/enemy updates and before the completion and collision tail.
	_update_respawns()
	_check_warp_malfunction_completion()
	_resolve_enemy_player_collisions()
	_resolve_enemy_projectile_collisions()
	_remove_expired_entities()
	if _phase != PHASE_WARP_MALFUNCTION:
		_refresh_enemy_watchdog_timestamp_from_render()
		return
	if resume_after_updates and _phase == PHASE_WARP_MALFUNCTION:
		_resume_warp_after_malfunction()
	_refresh_enemy_watchdog_timestamp_from_render()


func _update_warp_malfunction_message_cadence() -> void:
	if (
		_warp_malfunction_message_cadence_remaining <= 0
		or _tick <= _warp_malfunction_message_cadence_tick
	):
		return
	# Retail rearms the timer for 1.6 seconds even though its one-shot counter
	# reaches zero here. Keep that state observable for deterministic evidence.
	_warp_malfunction_message_cadence_tick = _tick + 96
	_warp_malfunction_message_cadence_remaining -= 1
	_emit_event("warp_malfunction_message_cue", {
		"sfx_key": "warpmalfunction",
		"x_fp": (FIELD_WIDTH >> 1) * FP_ONE,
		"y_fp": (FIELD_HEIGHT >> 1) * FP_ONE,
	})


func _check_warp_malfunction_completion() -> void:
	if (
		_warp_malfunction_resolution_tick == 0
		and _warp_malfunction_killed + _warp_malfunction_missed
		>= _warp_malfunction_total
	):
		_warp_malfunction_resolution_tick = (
			_tick + WARP_MALFUNCTION_RESOLUTION_TICKS
		)
		_emit_event("warp_malfunction_resolved", {
			"killed": _warp_malfunction_killed,
			"missed": _warp_malfunction_missed,
			"resolution_tick": _warp_malfunction_resolution_tick,
		})
	if (
		_warp_malfunction_resolution_tick == 0
		and _tick - _level_watchdog_start_tick > LEVEL_WATCHDOG_TICKS
	):
		# FUN_005566F0 force-arms the same three-second resolution deadline
		# after 45 seconds. It neither kills enemies nor increments "missed";
		# live state-6 objects survive into the resumed Warp until final cleanup.
		_warp_malfunction_resolution_tick = (
			_tick + WARP_MALFUNCTION_RESOLUTION_TICKS
		)
		_level_watchdog_start_tick = _tick
		_emit_event("warp_malfunction_watchdog", {
			"missed": _warp_malfunction_missed,
			"resolution_tick": _warp_malfunction_resolution_tick,
		})
	if (
		_warp_malfunction_resolution_tick > 0
		and _tick > _warp_malfunction_resolution_tick
	):
		# Retail latches the return now, then lets one more complete mode-16
		# dispatcher update execute before it re-enters mode 13.
		_warp_malfunction_transition_pending = true


func _resume_warp_after_malfunction() -> void:
	_phase = PHASE_WARP
	_warp_stage = 0
	_warp_stage_updates_remaining = WARP_STAGE_ONE_UPDATES
	# Retail rearms only c0 here. Scale 0, velocity -5, effect 0 and offset 0
	# remain from malfunction entry; the next mode-13 callback advances them.
	_warp_malfunction_transition_pending = false
	_warp_malfunction_resolution_tick = 0
	_warp_malfunction_file_id = 0
	_emit_event("warp_malfunction_ended", {
		"x_fp": (FIELD_WIDTH >> 1) * FP_ONE,
		"y_fp": PLAYER_Y_FP,
	})


func _active_warp_progression() -> Dictionary:
	return _shared


func _active_enemy_object_count() -> int:
	var count := 0
	for enemy_value in _enemies:
		var enemy: Dictionary = enemy_value
		if not bool(enemy.get("dead", false)):
			count += 1
	return count


func _spawn_warp_malfunction_enemies(requested_total: int) -> int:
	var file_index := clampi(
		_warp_malfunction_file_id - 1,
		0,
		WARP_MALFUNCTION_FILES.size() - 1
	)
	var resources: Array = WARP_MALFUNCTION_FILES[file_index]
	var progression := _active_warp_progression()
	var spawned := 0
	for enemy_index in range(requested_total):
		if _active_enemy_object_count() >= AUTHORED_ENTITY_SLOT_COUNT:
			break
		# The selector consumes a word even for one-resource malfunction files.
		var resource_index := _random_int(resources.size())
		var sprite := String(resources[resource_index])
		var spawn_left := 100 + _random_int(300)
		var heading := 18 + _random_int(5)
		var companion := maxi(1, int(progression.get("warp_companion", 8)))
		var health := 7 + _random_int(companion)
		var timer_probe := (
			400
			+ int(_difficulty.timer_a_initial_adjustment)
			+ _random_int(500)
		)
		var timer_a: int
		if timer_probe < int(_difficulty.timer_a_floor):
			timer_a = int(_difficulty.timer_a_floor)
		else:
			timer_a = (
				400
				+ int(_difficulty.timer_a_initial_adjustment)
				+ _random_int(500)
			)
		var timer_b := maxi(
			int(_difficulty.timer_b_floor),
			100 + int(_difficulty.timer_b_initial_adjustment)
		)
		var steering_countdown_fp := (
			50 * FP_ONE + _random_retail_float_fp(0.0, 100.0)
		)
		var animation_interval := 5 + _random_int(4)
		var animation_direction := _random_int(2)
		var speed_fp := _random_retail_float_fp(0.8, 3.0)
		var steering_mode := 2 + _random_int(3)
		var heading_step_reset_fp := (
			3 * FP_ONE + _random_retail_float_fp(0.0, 8.0)
		)
		var enemy := {
			"id": _allocate_entity_id(),
			"x_fp": (spawn_left + 32) * FP_ONE,
			"y_fp": -78 * FP_ONE,
			"width": 64,
			"height": 64,
			"health_fp": health * FP_ONE,
			"max_health_fp": health * FP_ONE,
			"speed_fp": speed_fp,
			"heading": heading,
			"x_scale_fp": FP_ONE,
			"y_scale_fp": FP_ONE,
			"steering_countdown_fp": steering_countdown_fp,
			"heading_step_countdown_fp": heading_step_reset_fp,
			"heading_step_reset_fp": heading_step_reset_fp,
			"heading_step_countdown_sixths": 0,
			"steering_mode": steering_mode,
			"supplemental_c54": 10,
			"behavior_timer_a": timer_a,
			"behavior_timer_a_step": 0,
			"behavior_timer_a_floor": int(_difficulty.timer_a_floor),
			"behavior_timer_b": timer_b,
			"behavior_timer_b_step": 10,
			"behavior_timer_b_floor": int(_difficulty.timer_b_floor),
			"projectile_speed_fp": int(_difficulty.alien_projectile_speed_fp),
			"score": 5000,
			"cash": 0,
			"sprite": sprite,
			"dead": false,
			"authored_lvd": true,
			"authored_state": "warp_malfunction",
			"behavior_state_id": 6,
			"warp_malfunction": true,
			"warp_malfunction_file_id": _warp_malfunction_file_id,
			"group_id": -1,
			"enemy_index": enemy_index,
			"kill_cohort_id": -1,
			"level_mode_id": 1,
			"mirror_x": false,
			"authored_animation_frame": 0,
			"animation_countdown_sixths": (
				animation_interval * SIMULATION_SCALE_DENOMINATOR
			),
			"animation_direction": animation_direction,
			"animation_max_phase": 3,
			"animation_metadata": 1,
			"base_health_divisor_numerator": 1,
			"base_health_divisor_denominator": 1,
			"mask_id": sprite,
		}
		_update_enemy_mask_rect(enemy)
		_enemies.append(enemy)
		spawned += 1
		_emit_event("warp_malfunction_enemy_spawned", {
			"entity_id": int(enemy.id),
			"file_id": _warp_malfunction_file_id,
			"enemy_sheet": sprite,
			"x_fp": int(enemy.x_fp),
			"y_fp": int(enemy.y_fp),
		})
	return spawned


func _clear_non_captured_enemies() -> void:
	var surviving: Array = []
	for enemy_value in _enemies:
		var enemy: Dictionary = enemy_value
		if (
			not bool(enemy.get("dead", false))
			and int(enemy.get("behavior_state_id", 0)) == 8
		):
			surviving.append(enemy)
	_enemies = surviving


func _apply_alien_lock_transition_policy(cause: String) -> void:
	if _ordnance_contract.is_empty():
		for enemy_value in _enemies:
			var legacy_enemy := enemy_value as Dictionary
			if (
				not bool(legacy_enemy.get("dead", false))
				and int(legacy_enemy.get("behavior_state_id", 0)) == 8
			):
				_destroy_captured_enemy(legacy_enemy, "%s_without_ordnance_contract" % cause)
		_enemies.clear()
		return
	var retained: Array = []
	for enemy_value in _enemies:
		var enemy := enemy_value as Dictionary
		if (
			not bool(enemy.get("dead", false))
			and int(enemy.get("behavior_state_id", 0)) == 8
		):
			var owner_seat_id := int(enemy.get("captured_owner_seat", -1))
			var lock_active := false
			if owner_seat_id >= 0 and owner_seat_id < _players.size():
				lock_active = int(
					_progression_for_seat(owner_seat_id).upgrades.get(
						"alien_lock",
						0
					)
				) != 0
			if not lock_active:
				_destroy_captured_enemy(enemy, cause)
				continue
		retained.append(enemy)
	_enemies = retained


func _level_is_retail_special(level_id: int) -> bool:
	var level: Dictionary = _level_data_for(level_id)
	if not level.has("authored_lvd"):
		return false
	return int(level.authored_lvd.level_mode_id) in [2, 3, 4]


func _adjust_malfunction_interval_for_warp_skip() -> void:
	_warp_malfunction_interval -= 100 + _random_int(1400)
	if _warp_malfunction_interval < 2000:
		_warp_malfunction_interval = 2300 + _random_int(1700)


func _load_warp_skip_level(level_id: int) -> void:
	_level_id = level_id
	_apply_endless_progression()
	_level_tick = 0
	_spawned_waves.clear()
	_clear_non_captured_enemies()
	# FUN_00569260 reinitializes all 100 common-shot records and every available
	# non-captive alien slot. Those initializers consume the shared RNG even
	# though the skipped level never receives an ordinary mode-2 frame.
	var surviving_player_projectiles: Array = []
	for projectile_value in _projectiles:
		var projectile: Dictionary = projectile_value
		if (
			String(projectile.get("owner_kind", "")) == "player"
			and not bool(projectile.get("expired", false))
		):
			surviving_player_projectiles.append(projectile)
	_projectiles = surviving_player_projectiles
	_initialize_common_projectile_slots()
	_initialize_level_behavior_state()
	_spawn_due_waves()


func _finalize_warp() -> void:
	_apply_alien_lock_transition_policy("warp_transition")
	_clear_non_captured_enemies()
	if _warp_owned_skip:
		for skip_index in range(4):
			if _level_is_retail_special(_level_id):
				continue
			if _level_id >= _end_level_id:
				# Stop at the declared campaign boundary; endless levels always
				# resolve content through the retail cycling rules.
				break
			_adjust_malfunction_interval_for_warp_skip()
			_load_warp_skip_level(_level_id + 1)
	_warp_owned_skip = false
	_clear_non_captured_enemies()
	_warp_stage_updates_remaining = 0
	_reset_warp_visuals()
	var terminal := _level_id >= _end_level_id
	_pending_level_id = 0 if terminal else _level_id + 1
	var shop_seat := _warp_shop_eligible_seat()
	if shop_seat >= 0:
		_turn_seat = shop_seat
		_phase = PHASE_SHOP
		_shop_ready = [false, false]
		_shop_warp_until_tick = _tick + SHOP_WARP_TICKS
		_emit_event("shop_started", {
			"level_id": _level_id,
			"next_level_id": _pending_level_id,
			"active_seat_id": _turn_seat,
			"input_guard_until_tick": _shop_warp_until_tick,
			"x_fp": (FIELD_WIDTH >> 1) * FP_ONE,
			"y_fp": (FIELD_HEIGHT >> 1) * FP_ONE,
		})
	else:
		_shop_warp_until_tick = 0
		_route_after_shop()


func _route_after_shop() -> void:
	_shop_ready = [false, false]
	_shop_warp_until_tick = 0
	_apply_shop_exit_auto_fire_reset()
	var next_level_id := _next_level_after_shop()
	if next_level_id == 0:
		_complete_campaign()
		return
	_begin_get_ready(next_level_id)


## Retail Auto Fire does not survive the shop: the 1,000-games profile lock
## ("AUTOFIRE WILL LAST THROUGH SHOP", docs/evidence/PROFILE_LOCKS.md) is the
## exception, and purchased Super Auto Fire always persists.
func _apply_shop_exit_auto_fire_reset() -> void:
	var seen: Array = []
	for seat_id in range(2):
		if not _seat_is_participating(seat_id):
			continue
		var progression := _progression_for_seat(seat_id)
		if progression in seen:
			continue
		seen.append(progression)
		if not bool(progression.get("auto_fire", false)):
			continue
		if int(progression.upgrades.get("super_autofire", 0)) > 0:
			continue
		if int(progression.upgrades.get("autofire_through_shop", 0)) > 0:
			continue
		progression.auto_fire = false


func _next_level_after_shop() -> int:
	if _pending_level_id > 0:
		return _pending_level_id
	if _level_id >= _end_level_id:
		return 0
	# A few bounded/test entry points begin promotion directly rather than via
	# Warp. Preserve the historical unset-pending fallback for those nonterminal
	# flows while keeping zero as the observable terminal-shop sentinel.
	return _level_id + 1


func _begin_credits_interstitial() -> void:
	# Retail rolls the credits after level 100 and continues the campaign on
	# input; the milestone score is the player's "level 100 score" stat.
	_clear_non_captured_enemies()
	_clear_projectiles()
	_pickups.clear()
	_shop_ready = [false, false]
	_shop_warp_until_tick = 0
	_get_ready_until_tick = 0
	_pending_level_id = 0
	_level_100_milestone_score = _result_score()
	_phase = PHASE_CREDITS
	_credits_min_tick = _tick + CREDITS_INTERSTITIAL_MIN_TICKS
	_emit_event("campaign_credits_started", {
		"level_id": _level_id,
		"score": _level_100_milestone_score,
		"x_fp": (FIELD_WIDTH >> 1) * FP_ONE,
		"y_fp": (FIELD_HEIGHT >> 1) * FP_ONE,
	})


func _step_credits() -> void:
	if _tick < _credits_min_tick:
		return
	for seat_id in range(2):
		if not _seat_is_participating(seat_id):
			continue
		if (
			_action_just_pressed(seat_id, ACTION_CONFIRM)
			or _action_just_pressed(seat_id, ACTION_FIRE)
		):
			_begin_get_ready(_level_id + 1)
			return


func _public_time_trial_snapshot() -> Dictionary:
	if _mode != MODE_TIME_TRIAL:
		return {}
	return {
		"active": true,
		"authored_level_id": time_trial_level_id_for(_level_id),
		"authored_level_count": TIME_TRIAL_LEVEL_COUNT,
		"remaining_ms": _time_trial_remaining_ms(),
		"deadline_ms": _time_trial_deadline_ms,
		"expired": _time_trial_expired,
	}


func _public_credits_snapshot() -> Dictionary:
	if _phase != PHASE_CREDITS:
		return {}
	return {
		"milestone": "level_%d" % RETAIL_CREDITS_LEVEL,
		"from_level_id": _level_id,
		"next_level_id": _level_id + 1,
		"score": _level_100_milestone_score,
		"min_tick": _credits_min_tick,
	}


func _complete_campaign() -> void:
	_clear_non_captured_enemies()
	_clear_projectiles()
	_pickups.clear()
	_shop_ready = [false, false]
	_shop_warp_until_tick = 0
	_get_ready_until_tick = 0
	_pending_level_id = 0
	_warp_owner_seat_id = -1
	_reset_rank_promotion_state()
	_phase = PHASE_COMPLETE
	var score := _result_score()
	var tally := _terminal_tally_by_seat()
	_result = {
		"completed": true,
		"mode": _mode,
		"level_reached": _end_level_id,
		"score": score,
		"money": _result_money(),
		"seat_progression": _public_seat_progression(),
		"profile_stats": _public_profile_stats(),
		"tally_by_seat": tally,
		"retired": _retired,
		"campaign_terminal": _campaign_terminal_result(score),
		"tick": _tick,
	}


func _campaign_terminal_result(score: int) -> Dictionary:
	# Bounded sessions ending exactly at level 100 keep the historical
	# level_100 terminal contract. The default endless session only terminates
	# at the retail level clamp (3999); its level-100 milestone score travels
	# with the result whenever the run crossed the credits interstitial.
	var reached_authored_terminal := (
		_level_id == RETAIL_CREDITS_LEVEL
		and _end_level_id == RETAIL_CREDITS_LEVEL
	)
	var reached_retail_clamp := _level_id >= MatchContract.MAX_END_LEVEL
	var terminal := reached_authored_terminal or reached_retail_clamp
	var milestone_score := _level_100_milestone_score
	if reached_authored_terminal and milestone_score == 0:
		milestone_score = score
	var kind := "configured_boundary"
	if reached_authored_terminal:
		kind = "level_100"
	elif reached_retail_clamp:
		kind = "level_clamp"
	return {
		"kind": kind,
		"full_campaign_completed": terminal,
		"credits_required": reached_authored_terminal,
		"ending_mode_id": 0,
		"winner_seat_id": -1,
		"level_100_score": milestone_score,
		"levels_beyond_authored": maxi(0, _level_id - RETAIL_CREDITS_LEVEL),
	}


func _warp_shop_eligible_seat() -> int:
	var seat_id := _warp_owner_seat_id
	if seat_id < 0 or seat_id >= _players.size():
		seat_id = _turn_seat
	return seat_id if _warp_shop_seat_is_eligible(seat_id) else -1


func _warp_shop_seat_is_eligible(seat_id: int) -> bool:
	if not _seat_is_participating(seat_id):
		return false
	var progression := _progression_for_seat(seat_id)
	return (
		int(progression.money) >= WARP_SHOP_MINIMUM_MONEY
		and int(progression.lives) > 0
	)


func _update_progression_timers() -> void:
	if _rocket_effect_active and _simulation_milliseconds() > _rocket_effect_until_ms:
		_rocket_effect_active = false
	var progressions: Array = [_shared]
	for progression_value in progressions:
		var progression: Dictionary = progression_value
		for key in [
			"score_multiplier_ticks",
			"shield_ticks",
			"scoop_ticks",
			"mirror_ticks",
			"drunk_ticks",
			"freeze_ticks",
			"special_mode_ticks",
			"super_autofire_message_ticks",
		]:
			if int(progression.get(key, 0)) > 0:
				progression[key] = int(progression[key]) - 1
		if int(progression.get("score_multiplier_ticks", 0)) <= 0:
			progression.score_multiplier = 1
		if int(progression.get("special_mode_ticks", 0)) <= 0:
			progression.special_mode = ""


func _spawn_due_waves() -> void:
	if _is_retail_big_boss_level():
		return
	var level: Dictionary = _level_data_for(_level_id)
	if level.has("authored_lvd"):
		_spawn_authored_groups(level)
		return
	var waves: Array = level.waves
	for wave_index in range(waves.size()):
		if _spawned_waves.has(wave_index):
			continue
		var wave: Dictionary = waves[wave_index]
		if _level_tick < int(wave.start_tick):
			continue
		_spawned_waves[wave_index] = true
		for enemy_index in range(int(wave.count)):
			_spawn_enemy(wave, enemy_index, String(level.enemy_sprite))
		_emit_event("wave_spawned", {
			"wave_index": wave_index,
			"x_fp": (FIELD_WIDTH >> 1) * FP_ONE,
			"y_fp": 0,
		})


func _spawn_authored_groups(level: Dictionary) -> void:
	var authored: Dictionary = level.authored_lvd
	var groups: Array = authored.groups
	# v9 authored content owns this value explicitly. The wave fallback is only
	# for predecessor catalogs whose public compatibility is still promised, and
	# Time Trial levels never carry the predecessor waves at all.
	var authored_runtime: Dictionary = level.get("authored_runtime", {})
	var ordinary_speed_fp := FP_ONE
	if authored_runtime.has("ordinary_speed_fp"):
		ordinary_speed_fp = int(authored_runtime.ordinary_speed_fp)
	elif level.has("waves") and not (level.waves as Array).is_empty():
		ordinary_speed_fp = int((level.waves[0] as Dictionary).speed_fp)
	for group_value in groups:
		var group: Dictionary = group_value
		var group_id := int(group.id)
		if _spawned_waves.has(group_id):
			continue
		_spawned_waves[group_id] = true
		var enemies: Array = group.enemies
		for enemy_value in enemies:
			var enemy_definition := enemy_value as Dictionary
			var resource_slot_id := int(
				enemy_definition.get("resource_slot_id", 0)
			)
			var resource := _enemy_resource_binding(level, resource_slot_id)
			if resource.is_empty():
				_set_error(
					"level %d enemy resource slot %d is not bound"
					% [int(level.id), resource_slot_id]
				)
				return
			_spawn_authored_enemy(
				group,
				enemy_definition,
				ordinary_speed_fp,
				String(resource.enemy_sheet_id),
				int(resource.kill_score),
				resource_slot_id,
				int(authored.level_mode_id),
				_mode != MODE_TIME_TRIAL and endless_mirror_for_level(_level_id)
			)
		_emit_event("wave_spawned", {
			"wave_index": group_id,
			"authored_group": true,
			"x_fp": (FIELD_WIDTH >> 1) * FP_ONE,
			"y_fp": 0,
		})
	_spawn_authored_supplemental(level)


func _enemy_resource_binding(level: Dictionary, resource_slot_id: int) -> Dictionary:
	for resource_value in level.get("enemy_resources", []):
		if not resource_value is Dictionary:
			continue
		var resource := resource_value as Dictionary
		if int(resource.get("resource_slot_id", -1)) == resource_slot_id:
			return resource
	return {}


func _initialize_level_behavior_state() -> void:
	_authored_slot_seeds.clear()
	_authored_spawn_slot = 0
	_supplemental_spawned = false
	var level: Dictionary = _level_data_for(_level_id)
	_initialize_level_resolution_state(level)
	if not level.has("authored_lvd"):
		return
	var preserved_captive_count := 0
	for enemy_value in _enemies:
		var preserved_enemy: Dictionary = enemy_value
		if (
			not bool(preserved_enemy.get("dead", false))
			and int(preserved_enemy.get("behavior_state_id", 0)) == 8
		):
			preserved_captive_count += 1
	for slot_index in range(maxi(
		0,
		AUTHORED_ENTITY_SLOT_COUNT - preserved_captive_count
	)):
		_authored_slot_seeds.append({
			"phase": _random_int(6),
			"countdown_sixths": 4 * SIMULATION_SCALE_DENOMINATOR,
			"direction": _random_int(2),
			# Retail initializes this per-slot animation rate even when the
			# authored entity slot is inactive. It is retained so the third draw
			# and its state are visible to replay/hash validation.
			"animation_step_fp": _random_retail_float_fp(0.3, 2.0) / 5,
		})
	# Retail chooses the state-4 tail size after all 150 ordinary slot
	# initializers. The value is shared by the whole level.
	if _mode == MODE_COOP:
		_tail_cutoff = 0
	else:
		_tail_cutoff = 2 + _random_int(4)
	_platform_x_fp = 0
	_platform_y_fp = 0
	_platform_velocity_x_fp = PLATFORM_INITIAL_VELOCITY_FP
	_platform_acceleration_x_fp = PLATFORM_ACCELERATION_FP


func _initialize_level_resolution_state(level: Dictionary) -> void:
	_level_total_entities = 0
	_level_killed_entities = 0
	_level_escaped_entities = 0
	_level_resolved = false
	_level_resolution_tick = 0
	_get_ready_until_tick = 0
	_pending_level_id = 0
	_group_kill_counts.clear()
	_group_totals.clear()
	_cohort_kill_counts.clear()
	_cohort_totals.clear()
	_cohort_completion_score = COHORT_INITIAL_COMPLETION_SCORE
	_level_watchdog_start_tick = _tick
	_enemy_liveness_idle_updates = 0
	_shop_warp_until_tick = 0
	_rocket_fired_this_level = false
	_alien_projectile_processed_this_level = false
	for stats_value in _profile_stats_by_seat:
		(stats_value as Dictionary).rocket_missiles_fired = 0
	_rank_full_reward_claimed = false
	# Retail re-arms the hurry-up deadline, resets the visible planet count, and
	# clears the shared effect pool on every ordinary-play entry (FUN_00569260).
	_arm_hurry_up_deadline()
	_hurry_up_planet_count = 1
	_reset_effect_pool()
	if not level.has("authored_lvd"):
		for wave_value in level.get("waves", []):
			_level_total_entities += int((wave_value as Dictionary).get("count", 0))
		_reset_level_eight_round_state(level)
		return
	var authored: Dictionary = level.authored_lvd
	var level_id := int(level.get("id", 0))
	var boss_bundle := _boss_runtimes_by_level.get(level_id, {}) as Dictionary
	var level_boss_contract := boss_bundle.get("contract", {}) as Dictionary
	if (
		not level_boss_contract.is_empty()
		and int(authored.get("level_mode_id", 0))
		== int(level_boss_contract.get("level_mode_id", 0))
	):
		# Mode 4's auxiliary LVD records are controller vectors/origins, not a
		# generic sixteen-enemy completion population.
		_level_total_entities = 1
		_reset_level_eight_round_state(level)
		return
	for group_value in authored.groups:
		var group: Dictionary = group_value
		var group_id := int(group.id)
		var cohort_id := int(group.kill_cohort_id)
		var count := int(group.enemies.size())
		_group_kill_counts[group_id] = 0
		_group_totals[group_id] = count
		_cohort_kill_counts[cohort_id] = 0
		_cohort_totals[cohort_id] = int(_cohort_totals.get(cohort_id, 0)) + count
		_level_total_entities += count
	var records: Array = authored.supplemental_spawn_records_raw_words
	for record_index in range(mini(4, records.size())):
		var record: Array = records[record_index]
		_level_total_entities += maxi(0, int(record[0]))
	_reset_level_eight_round_state(level)


func _level_is_mode_three_bonus(level: Dictionary) -> bool:
	return (
		level.has("authored_lvd")
		and int(level.authored_lvd.get("level_mode_id", 0))
		== int(_level_eight_contract.get("level_mode_id", 3))
		and not _mode_three_level_contract(int(level.get("id", 0))).is_empty()
	)


func _mode_three_level_contract(level_id: int) -> Dictionary:
	var levels: Array = _level_eight_contract.get("levels", [])
	for level_value in levels:
		if (
			level_value is Dictionary
			and int((level_value as Dictionary).get("level_id", 0)) == level_id
		):
			return (level_value as Dictionary).duplicate(true)
	return {}


func _is_mode_three_bonus() -> bool:
	return _level_is_mode_three_bonus(_level_data_for(_level_id))


func _is_level_eight_mode_three() -> bool:
	# Compatibility entry point retained for focused tests and hash fixtures.
	return _is_mode_three_bonus()


func _level_eight_reward_values() -> Array:
	var rewards_value: Variant = _level_eight_contract.get(
		"rewards",
		{}
	).get("perfect_reward_progression", LEVEL_EIGHT_PERFECT_REWARDS)
	if rewards_value is Array and not (rewards_value as Array).is_empty():
		return rewards_value as Array
	return LEVEL_EIGHT_PERFECT_REWARDS


func _level_eight_starting_perfect_index(
	match_config: Dictionary,
	seat_id: int
) -> int:
	var seat_config: Dictionary = {}
	var seats: Array = match_config.get("seats", [])
	if seat_id >= 0 and seat_id < seats.size() and seats[seat_id] is Dictionary:
		seat_config = seats[seat_id]
	var reward_count := maxi(1, _level_eight_reward_values().size())
	return clampi(
		int(seat_config.get(
			"mode_three_perfect_reward_index",
			seat_config.get(
				"level_eight_perfect_reward_index",
				match_config.get(
					"mode_three_perfect_reward_index",
					match_config.get("level_eight_perfect_reward_index", 0)
				)
			)
		)),
		0,
		reward_count - 1
	)


func _reset_level_eight_round_state(level: Dictionary) -> void:
	_level_eight_result_initialized = false
	_level_eight_result_deadline_ms = 0
	_level_eight_reveal_deadline_ms = 0
	_level_eight_reveal_countdown = 0
	_level_eight_result_players.clear()
	if not _level_is_mode_three_bonus(level):
		return
	var level_contract := _mode_three_level_contract(int(level.get("id", 0)))
	var target_count := int(level_contract.get(
		"authored_target_count",
		_level_total_entities
	))
	for seat_id in range(2):
		_level_eight_result_players.append({
			"seat_id": seat_id,
			"participating": _seat_is_participating(seat_id),
			"total_targets": target_count if _seat_is_participating(seat_id) else 0,
			"actual_hits": 0,
			"displayed_hits": 0,
			"perfect_awarded": false,
			"last_hit_score": 0,
			"perfect_reward": 0,
		})


func _spawn_authored_supplemental(level: Dictionary) -> void:
	if _supplemental_spawned:
		return
	_supplemental_spawned = true
	var records: Array = level.authored_lvd.supplemental_spawn_records_raw_words
	for record_index in range(mini(4, records.size())):
		var record: Array = records[record_index]
		var spawn_count := int(record[0])
		var resource_selector := int(record[1])
		if spawn_count <= 0:
			continue
		var resource := _enemy_resource_binding(level, resource_selector)
		if resource.is_empty():
			_set_error(
				"level %d supplemental resource slot %d is not bound"
				% [int(level.id), resource_selector]
			)
			return
		var sprite := String(resource.enemy_sheet_id)
		for supplemental_index in range(spawn_count):
			var health_fp := int(record[2]) * FP_ONE
			if _endless_step_count > 0:
				# Retail adds +5.0 special-class health per crossed hundred
				# (0x00e113fc, consumed on the supplemental record table).
				health_fp += (
					_endless_step_count * ENDLESS_SUPPLEMENTAL_HEALTH_STEP * FP_ONE
				)
			if _mode == MODE_COOP and _balance == BALANCE_BALANCED:
				health_fp *= 2
			var timer_a := maxi(
				int(record[3]) + int(_difficulty.timer_a_initial_adjustment),
				int(_difficulty.timer_a_floor)
			)
			var timer_b := maxi(
				100 + int(_difficulty.timer_b_initial_adjustment),
				int(_difficulty.timer_b_floor)
			)
			# Executable order: X, heading, steering chooser countdown,
			# animation interval, then the heading-step countdown.
			var spawn_x_fp := (
				(FIELD_WIDTH >> 2) + _random_int(FIELD_WIDTH >> 1)
			) * FP_ONE
			var heading := 18 + _random_int(5)
			var steering_countdown_fp := _random_retail_float_fp(200.0, 400.0)
			var animation_interval := 2 + _random_int(3)
			var supplemental_c54 := 6 + _random_int(10)
			var animation_max_phase := 3
			var animation_metadata := 1
			var fixed_records: Array = level.authored_lvd.get(
				"fixed_table_records_raw_words",
				[]
			)
			var fixed_index := record_index
			if fixed_index >= 0 and fixed_index < fixed_records.size():
				var fixed_value: Variant = fixed_records[fixed_index]
				if fixed_value is Array and (fixed_value as Array).size() >= 2:
					animation_max_phase = maxi(
						0,
						int((fixed_value as Array)[0]) - 1
					)
					animation_metadata = int((fixed_value as Array)[1])
			var enemy := {
				"id": _allocate_entity_id(),
				"x_fp": spawn_x_fp + 32 * FP_ONE,
				"y_fp": -78 * FP_ONE,
				"width": 64,
				"height": 64,
				"health_fp": health_fp,
				"max_health_fp": health_fp,
				"speed_fp": FP_ONE,
				"heading": heading,
				"x_scale_fp": FP_ONE,
				"y_scale_fp": FP_ONE,
				"steering_countdown_fp": steering_countdown_fp,
				"heading_step_countdown_sixths": 3 * SIMULATION_SCALE_DENOMINATOR,
				"steering_mode": 2,
				"supplemental_c54": supplemental_c54,
				"behavior_timer_a": timer_a,
				"behavior_timer_a_step": int(record[4]),
				"behavior_timer_a_floor": int(_difficulty.timer_a_floor),
				"behavior_timer_b": timer_b,
				"behavior_timer_b_step": 10,
				"behavior_timer_b_floor": int(_difficulty.timer_b_floor),
				"projectile_speed_fp": int(_difficulty.alien_projectile_speed_fp),
				"score": 0,
				"cash": 0,
				"sprite": sprite,
				"dead": false,
				"authored_lvd": true,
				"authored_state": "supplemental_large",
				"behavior_state_id": 6,
				"group_id": -1,
				"enemy_index": supplemental_index,
				"kill_cohort_id": -1,
				"level_mode_id": int(level.authored_lvd.level_mode_id),
				"resource_slot_id": resource_selector,
				"mirror_x": false,
				"authored_animation_frame": 0,
				"animation_countdown_sixths": animation_interval
				* SIMULATION_SCALE_DENOMINATOR,
				"animation_direction": 0,
				"animation_max_phase": animation_max_phase,
				"animation_metadata": animation_metadata,
				"base_health_divisor_numerator": maxi(1, int(record[2])),
				"base_health_divisor_denominator": 10,
				"mask_id": sprite,
			}
			_update_enemy_mask_rect(enemy)
			_enemies.append(enemy)
			_emit_event("supplemental_spawned", {
				"record_index": record_index,
				"entity_id": int(enemy.id),
				"enemy_sheet": sprite,
				"x_fp": int(enemy.x_fp),
				"y_fp": int(enemy.y_fp),
			})


# --- Hurry-up secret ships (docs/evidence/HURRY_UP_SECRET_SHIPS.md) -----------


## FUN_00552440. Every ordinary-play entry re-arms the deadline from the
## difficulty timed-effect interval; the getter at FUN_00552680 reads the same
## per-player pair back.
func _arm_hurry_up_deadline() -> void:
	_hurry_up_interval_ms = maxi(0, int(_difficulty.get("timed_effect_seconds", 0))) * 1000
	_hurry_up_deadline_ms = _simulation_milliseconds() + _hurry_up_interval_ms


func _hurry_up_is_enabled() -> bool:
	return _mode != MODE_TIME_TRIAL and _hurry_up_interval_ms > 0


## FUN_0058e350, called once per frame from the ordinary-level dispatcher
## between the collision pass and the motion pass. Every guard runs before any
## random draw, so a suppressed frame consumes no RNG at all.
func _step_hurry_up_spawner() -> void:
	if not _hurry_up_is_enabled():
		return
	if _phase != PHASE_LEVEL or _level_resolved or _level_eight_result_initialized:
		return
	if _is_retail_big_boss_level() or _is_mode_three_bonus():
		return
	if _simulation_milliseconds() <= _hurry_up_deadline_ms:
		return
	if _active_enemy_object_count() >= AUTHORED_ENTITY_SLOT_COUNT:
		return
	_spawn_hurry_up_mothership()
	_hurry_up_spawn_counter += 1
	if _hurry_up_spawn_counter >= HURRY_UP_RARE_PERIOD:
		_hurry_up_spawn_counter = 0
		if _active_enemy_object_count() < AUTHORED_ENTITY_SLOT_COUNT:
			_spawn_hurry_up_rare_ship()
	# The spawner tail replaces the interval with a flat ten seconds.
	_hurry_up_interval_ms = HURRY_UP_REARM_MS
	_hurry_up_deadline_ms = _simulation_milliseconds() + HURRY_UP_REARM_MS


func _spawn_hurry_up_mothership() -> void:
	# Draw order: entry coin, voice pick, one X per already-visible planet,
	# speed, animation interval.
	var enters_from_right := (
		_random_int(HURRY_UP_ENTRY_COIN_RANGE) < HURRY_UP_ENTRY_RIGHT_THRESHOLD
	)
	var spawn_left := (
		FIELD_WIDTH if enters_from_right else -MOTHERSHIP_SHEET_WIDTH
	)
	var voice_index := _random_int(HURRY_UP_VOICE_KEYS.size())
	_emit_event("hurry_up_banner", {
		"text": HURRY_UP_BANNER_TEXT,
		"duration_ms": HURRY_UP_BANNER_MS,
		"until_ms": _simulation_milliseconds() + HURRY_UP_BANNER_MS,
	})
	_emit_event("voice_cue", {
		"voice_key": String(HURRY_UP_VOICE_KEYS[
			clampi(voice_index, 0, HURRY_UP_VOICE_KEYS.size() - 1)
		]),
		"cause": "hurry_up",
	})
	for planet_index in range(mini(_hurry_up_planet_count, HURRY_UP_PLANET_LIMIT)):
		_hurry_up_planet_x[planet_index] = HURRY_UP_PLANET_MARGIN + _random_int(
			FIELD_WIDTH - 2 * HURRY_UP_PLANET_MARGIN
		)
	_hurry_up_planet_count = mini(_hurry_up_planet_count + 1, HURRY_UP_PLANET_LIMIT)
	var speed_fp := _random_retail_float_fp(
		HURRY_UP_SPECIAL_SPEED_MINIMUM,
		float(int(_difficulty.get("special_speed_maximum", 4)))
	)
	var animation_interval_fp := _random_retail_float_fp(
		HURRY_UP_SPECIAL_SPEED_MINIMUM,
		MOTHERSHIP_ANIMATION_INTERVAL_MAXIMUM
	)
	var health_fp := (
		_endless_step_count * ENDLESS_ORDINARY_HEALTH_STEP
		+ int(_difficulty.get("special_health_base_a", 16))
	) * FP_ONE
	var enemy := {
		"id": _allocate_entity_id(),
		# Retail keeps the sprite top-left; the remake centre-normalises every
		# entity, and the traced 96x57 box is the frame itself.
		"x_fp": spawn_left * FP_ONE + MOTHERSHIP_FRAME_WIDTH * FP_ONE / 2,
		"y_fp": MOTHERSHIP_SPAWN_Y * FP_ONE + MOTHERSHIP_FRAME_HEIGHT * FP_ONE / 2,
		"width": MOTHERSHIP_FRAME_WIDTH,
		"height": MOTHERSHIP_FRAME_HEIGHT,
		"collision_width": MOTHERSHIP_FRAME_WIDTH,
		"collision_height": MOTHERSHIP_FRAME_HEIGHT,
		"health_fp": health_fp,
		"max_health_fp": health_fp,
		"speed_fp": speed_fp,
		"score": MOTHERSHIP_SCORE,
		"cash": 0,
		"sprite": MOTHERSHIP_SPRITE,
		"dead": false,
		"authored_lvd": true,
		"authored_state": HURRY_UP_MOTHERSHIP_STATE,
		"behavior_state_id": HURRY_UP_MOTHERSHIP_STATE_ID,
		"hurry_up_enters_from_right": enters_from_right,
		"group_id": -1,
		"enemy_index": -1,
		"kill_cohort_id": -1,
		"mirror_x": false,
		# Retail leaves these three as entity-slot residue; the remake starts
		# them at the fresh-level values (see the deviations section of the
		# evidence document).
		"authored_animation_frame": 0,
		"animation_direction": 0,
		"animation_countdown_fp": animation_interval_fp,
		"animation_interval_fp": animation_interval_fp,
		"mask_id": MOTHERSHIP_SPRITE,
		"mask_required": true,
	}
	_enemies.append(enemy)
	_level_total_entities += 1
	_update_hurry_up_source_rect(enemy)
	_emit_event("hurry_up_spawned", {
		"entity_id": int(enemy.id),
		"enemy_sheet": MOTHERSHIP_SPRITE,
		"behavior_state_id": HURRY_UP_MOTHERSHIP_STATE_ID,
		"enters_from_right": enters_from_right,
		"x_fp": int(enemy.x_fp),
		"y_fp": int(enemy.y_fp),
	})
	_start_hurry_up_hum(enemy, MOTHERSHIP_HUM_KEY)


func _spawn_hurry_up_rare_ship() -> void:
	# Draw order: X, heading, turn countdown, animation direction, speed scalar,
	# heading-step interval, heading-step countdown.
	var spawn_left := MONEYSHIP_SPAWN_X_BASE + _random_int(
		(FIELD_WIDTH - 2 * MONEYSHIP_SPAWN_X_BASE) / 2
	)
	var heading := MONEYSHIP_HEADING_BASE + _random_int(5)
	var health_fp := (
		_endless_step_count * ENDLESS_ORDINARY_HEALTH_STEP
		+ int(_difficulty.get("special_health_base_c", 100))
	) * FP_ONE
	var steering_countdown_fp := _random_retail_float_fp(0.0, 100.0) + 50 * FP_ONE
	var animation_direction := _random_int(2)
	var speed_scalar_fp := _random_retail_float_fp(0.800000011920929, 3.0)
	var heading_step_interval := 2 + _random_int(3)
	var heading_step_countdown_fp := _random_retail_float_fp(0.0, 8.0) + 3 * FP_ONE
	# Retail derives the animation reload from the spawn health, so the ship
	# animates faster the more damage it has taken.
	var animation_divisor_fp := health_fp / 5
	var animation_countdown_fp := (
		health_fp / 4 if animation_divisor_fp == 0
		else (health_fp * FP_ONE / animation_divisor_fp) / 4
	)
	var enemy := {
		"id": _allocate_entity_id(),
		"x_fp": spawn_left * FP_ONE + MONEYSHIP_FRAME_SIZE * FP_ONE / 2,
		"y_fp": MONEYSHIP_SPAWN_Y * FP_ONE + MONEYSHIP_FRAME_SIZE * FP_ONE / 2,
		"width": MONEYSHIP_FRAME_SIZE,
		"height": MONEYSHIP_FRAME_SIZE,
		# The traced 100x100 box sits centred inside the 128x128 frame, and the
		# mask is then sampled across the whole frame.
		"collision_width": MONEYSHIP_HITBOX_EXTENT,
		"collision_height": MONEYSHIP_HITBOX_EXTENT,
		"mask_width": MONEYSHIP_FRAME_SIZE,
		"mask_height": MONEYSHIP_FRAME_SIZE,
		"health_fp": health_fp,
		"max_health_fp": health_fp,
		"speed_fp": speed_scalar_fp,
		"x_scale_fp": FP_ONE,
		"y_scale_fp": FP_ONE,
		"heading": heading,
		"steering_mode": 2,
		"steering_countdown_fp": steering_countdown_fp,
		"heading_step_interval_fp": heading_step_countdown_fp,
		"heading_step_countdown_fp": MONEYSHIP_ANIMATION_INTERVAL * FP_ONE,
		"score": MONEYSHIP_SCORE,
		"cash": 0,
		"sprite": MONEYSHIP_SPRITE,
		"dead": false,
		"authored_lvd": true,
		"authored_state": HURRY_UP_RARE_STATE,
		"behavior_state_id": HURRY_UP_RARE_STATE_ID,
		"group_id": -1,
		"enemy_index": -1,
		"kill_cohort_id": -1,
		"mirror_x": false,
		"authored_animation_frame": 0,
		"animation_direction": animation_direction,
		"animation_countdown_fp": animation_countdown_fp,
		"animation_divisor_fp": animation_divisor_fp,
		"animation_max_phase": MONEYSHIP_FRAME_COUNT - 1,
		"animation_metadata": 1,
		# Retail draws this into entity +0x208 but state 12 never reads it back.
		# It is retained so the draw stays visible to replay and hash validation.
		"supplemental_c54": heading_step_interval,
		"mask_id": MONEYSHIP_SPRITE,
		"mask_required": true,
	}
	_enemies.append(enemy)
	_level_total_entities += 1
	_update_hurry_up_source_rect(enemy)
	_emit_event("hurry_up_spawned", {
		"entity_id": int(enemy.id),
		"enemy_sheet": MONEYSHIP_SPRITE,
		"behavior_state_id": HURRY_UP_RARE_STATE_ID,
		"enters_from_right": false,
		"x_fp": int(enemy.x_fp),
		"y_fp": int(enemy.y_fp),
	})
	_start_hurry_up_hum(enemy, MONEYSHIP_HUM_KEY)


## Retail holds one looping hum channel per hurry-up entity slot and stops it
## when the ship dies or leaves.
func _start_hurry_up_hum(enemy: Dictionary, sound_key: String) -> void:
	enemy.hurry_up_hum_key = sound_key
	_emit_event("audio_loop_started", {
		"sound_key": sound_key,
		"handle": "hurry_up:%d" % int(enemy.id),
		"x_fp": int(enemy.x_fp),
		"y_fp": int(enemy.y_fp),
	})


func _stop_hurry_up_hum(enemy: Dictionary) -> void:
	var sound_key := String(enemy.get("hurry_up_hum_key", ""))
	if sound_key.is_empty():
		return
	enemy.hurry_up_hum_key = ""
	_emit_event("audio_loop_stopped", {
		"sound_key": sound_key,
		"handle": "hurry_up:%d" % int(enemy.id),
	})


## Retail writes the sheet source offsets straight onto the entity; the remake
## mirrors them so the snapshot can carry a renderer-ready rectangle.
func _update_hurry_up_source_rect(enemy: Dictionary) -> void:
	var frame := int(enemy.get("authored_animation_frame", 0))
	if String(enemy.get("authored_state", "")) == HURRY_UP_MOTHERSHIP_STATE:
		frame = clampi(frame, 0, MOTHERSHIP_FRAME_COUNT - 1)
		# The texture packs the twenty frames 3 columns by 8 rows while the hit
		# mask packs them in a single column, so the two rectangles differ.
		enemy.source_rect = [
			(frame / MOTHERSHIP_FRAME_ROWS) * MOTHERSHIP_FRAME_WIDTH,
			(frame % MOTHERSHIP_FRAME_ROWS) * MOTHERSHIP_FRAME_HEIGHT,
			MOTHERSHIP_FRAME_WIDTH,
			MOTHERSHIP_FRAME_HEIGHT,
		]
		_set_mask_source_rect(enemy, Rect2i(
			0,
			frame * MOTHERSHIP_FRAME_HEIGHT,
			MOTHERSHIP_FRAME_WIDTH,
			MOTHERSHIP_FRAME_HEIGHT
		))
	else:
		frame = clampi(frame, 0, MONEYSHIP_FRAME_COUNT - 1)
		var money_rect := Rect2i(
			0,
			frame * MONEYSHIP_FRAME_SIZE,
			MONEYSHIP_FRAME_SIZE,
			MONEYSHIP_FRAME_SIZE
		)
		enemy.source_rect = [
			money_rect.position.x,
			money_rect.position.y,
			money_rect.size.x,
			money_rect.size.y,
		]
		_set_mask_source_rect(enemy, money_rect)
	enemy.collision_x_fp = int(enemy.x_fp)
	enemy.collision_y_fp = int(enemy.y_fp)


## The state-9 branch of FUN_00605fe0.
func _update_hurry_up_mothership(enemy: Dictionary) -> void:
	_sweep_hurry_up_planets(enemy)
	var advance := _scaled_simulation_delta(int(enemy.speed_fp))
	var left_edge_fp := 0
	if bool(enemy.get("hurry_up_enters_from_right", false)):
		enemy.x_fp = int(enemy.x_fp) - advance
		left_edge_fp = int(enemy.x_fp) - MOTHERSHIP_FRAME_WIDTH * FP_ONE / 2
		if left_edge_fp < -MOTHERSHIP_DESPAWN_MARGIN * FP_ONE:
			_depart_hurry_up_mothership(enemy)
			return
	else:
		enemy.x_fp = int(enemy.x_fp) + advance
		left_edge_fp = int(enemy.x_fp) - MOTHERSHIP_FRAME_WIDTH * FP_ONE / 2
		if left_edge_fp > (FIELD_WIDTH + MOTHERSHIP_DESPAWN_MARGIN) * FP_ONE:
			_depart_hurry_up_mothership(enemy)
			return
	# Retail publishes the sheet offsets for the frame it is already showing and
	# only then advances the animation, so the rectangle trails by one step.
	_update_hurry_up_source_rect(enemy)
	enemy.animation_countdown_fp = int(
		enemy.animation_countdown_fp
	) - _scaled_simulation_delta(FP_ONE)
	if int(enemy.animation_countdown_fp) < 0:
		enemy.animation_countdown_fp = int(enemy.animation_interval_fp)
		var frame := int(enemy.authored_animation_frame)
		if int(enemy.get("animation_direction", 0)) == 0:
			frame += 1
			if frame >= MOTHERSHIP_FRAME_COUNT:
				frame = 0
		else:
			frame -= 1
			if frame < 0:
				frame = MOTHERSHIP_FRAME_COUNT - 1
		enemy.authored_animation_frame = frame


## Retail clears any parallax planet the mothership has swept past.
func _sweep_hurry_up_planets(enemy: Dictionary) -> void:
	var ship_left_fp := int(enemy.x_fp) - MOTHERSHIP_FRAME_WIDTH * FP_ONE / 2
	var enters_from_right := bool(enemy.get("hurry_up_enters_from_right", false))
	var cleared := false
	for planet_index in range(mini(_hurry_up_planet_count, HURRY_UP_PLANET_LIMIT)):
		var planet_x_fp := int(_hurry_up_planet_x[planet_index]) * FP_ONE
		if planet_x_fp == 0:
			continue
		var swept := (
			ship_left_fp < planet_x_fp if enters_from_right
			else planet_x_fp < ship_left_fp
		)
		if not swept:
			continue
		_hurry_up_planet_x[planet_index] = 0
		cleared = true
	if not cleared:
		return
	_emit_event("hurry_up_planet_destroyed", {
		"entity_id": int(enemy.id),
		"x_fp": int(enemy.x_fp),
		"y_fp": int(enemy.y_fp),
	})
	_spawn_planet_debris(enemy)


func _depart_hurry_up_mothership(enemy: Dictionary) -> void:
	enemy.dead = true
	_stop_hurry_up_hum(enemy)
	_level_escaped_entities += 1
	_hurry_up_deadline_ms = _simulation_milliseconds() + _hurry_up_interval_ms
	_emit_event("enemy_escaped", {
		"entity_id": int(enemy.id),
		"enemy_sheet": MOTHERSHIP_SPRITE,
		"cause": "hurry_up_departure",
		"x_fp": int(enemy.x_fp),
		"y_fp": int(enemy.y_fp),
	})
	_try_resolve_level_counter("hurry_up_departure")


## The state-12 branch of FUN_00605fe0: a wrapping drift along the same
## forty-entry heading circle supplemental state 6 uses.
func _update_hurry_up_rare_ship(enemy: Dictionary) -> void:
	var direction_index := posmod(int(enemy.heading), 40)
	var velocity_x_fp := Fixed.multiply(
		Fixed.multiply(
			int(enemy.x_scale_fp),
			int(SUPPLEMENTAL_DIRECTION_X_FP[direction_index])
		),
		int(enemy.speed_fp)
	)
	var velocity_y_fp := Fixed.multiply(
		Fixed.multiply(
			int(enemy.y_scale_fp),
			int(SUPPLEMENTAL_DIRECTION_Y_FP[direction_index])
		),
		int(enemy.speed_fp)
	)
	enemy.x_fp = int(enemy.x_fp) + _scaled_simulation_delta(velocity_x_fp)
	enemy.y_fp = int(enemy.y_fp) + _scaled_simulation_delta(velocity_y_fp)
	var half_frame_fp := MONEYSHIP_FRAME_SIZE * FP_ONE / 2
	var wrap_margin_fp := MONEYSHIP_WRAP_MARGIN * FP_ONE
	if int(enemy.x_fp) - half_frame_fp > FIELD_WIDTH * FP_ONE + wrap_margin_fp:
		enemy.x_fp = -wrap_margin_fp + half_frame_fp
	elif int(enemy.x_fp) - half_frame_fp < -wrap_margin_fp:
		enemy.x_fp = (FIELD_WIDTH + MONEYSHIP_WRAP_RETURN) * FP_ONE + half_frame_fp
	if int(enemy.y_fp) - half_frame_fp > FIELD_HEIGHT * FP_ONE + wrap_margin_fp:
		enemy.y_fp = -wrap_margin_fp + half_frame_fp
	elif int(enemy.y_fp) - half_frame_fp < -wrap_margin_fp:
		enemy.y_fp = (FIELD_HEIGHT + MONEYSHIP_WRAP_RETURN) * FP_ONE + half_frame_fp
	_update_hurry_up_rare_steering(enemy)
	# Same publish-then-advance order the mothership uses.
	_update_hurry_up_source_rect(enemy)
	_update_hurry_up_rare_animation(enemy)


func _update_hurry_up_rare_steering(enemy: Dictionary) -> void:
	var half_frame_fp := MONEYSHIP_FRAME_SIZE * FP_ONE / 2
	enemy.steering_countdown_fp = int(
		enemy.steering_countdown_fp
	) - _scaled_simulation_delta(FP_ONE)
	if int(enemy.steering_countdown_fp) < 0:
		var heading := posmod(int(enemy.heading), 40)
		var left_fp := int(enemy.x_fp) - half_frame_fp
		var top_fp := int(enemy.y_fp) - half_frame_fp
		enemy.steering_mode = 2
		enemy.steering_countdown_fp = 30 * FP_ONE
		if left_fp > 700 * FP_ONE and heading < 20:
			enemy.steering_mode = 1 if heading < 10 or heading > 29 else 3
			enemy.steering_countdown_fp = 40 * FP_ONE + _random_retail_float_fp(0.0, 160.0)
		if left_fp < 36 * FP_ONE and heading > 19:
			enemy.steering_mode = 3 if heading < 10 or heading > 29 else 1
			enemy.steering_countdown_fp = 40 * FP_ONE + _random_retail_float_fp(0.0, 160.0)
		if top_fp > 180 * FP_ONE and heading > 9 and heading < 30:
			enemy.steering_mode = 1 if heading < 20 else 3
			enemy.steering_countdown_fp = 40 * FP_ONE + _random_retail_float_fp(0.0, 160.0)
		if top_fp < 80 * FP_ONE and (heading < 10 or heading > 29):
			enemy.steering_mode = 3 if heading < 20 else 1
			enemy.steering_countdown_fp = 40 * FP_ONE + _random_retail_float_fp(0.0, 160.0)
	enemy.heading_step_countdown_fp = int(
		enemy.heading_step_countdown_fp
	) - _scaled_simulation_delta(FP_ONE)
	if int(enemy.heading_step_countdown_fp) >= 0:
		return
	enemy.heading_step_countdown_fp = int(enemy.heading_step_interval_fp)
	if int(enemy.steering_mode) == 3:
		enemy.heading = posmod(int(enemy.heading) + 1, 40)
	elif int(enemy.steering_mode) == 1:
		enemy.heading = posmod(int(enemy.heading) - 1, 40)


func _update_hurry_up_rare_animation(enemy: Dictionary) -> void:
	enemy.animation_countdown_fp = int(
		enemy.animation_countdown_fp
	) - _scaled_simulation_delta(FP_ONE)
	if int(enemy.animation_countdown_fp) >= 0:
		return
	var divisor_fp := int(enemy.get("animation_divisor_fp", 0))
	if divisor_fp == 0:
		divisor_fp = FP_ONE
	enemy.animation_countdown_fp = (
		int(enemy.health_fp) * FP_ONE / divisor_fp
	) / 4
	var frame := int(enemy.authored_animation_frame)
	var maximum := int(enemy.get("animation_max_phase", MONEYSHIP_FRAME_COUNT - 1))
	var ping_pong := int(enemy.get("animation_metadata", 1)) != 0
	if int(enemy.get("animation_direction", 0)) == 0:
		frame -= 1
		if frame < 0:
			if ping_pong:
				frame = 1
				enemy.animation_direction = 1
			else:
				frame = maximum
	else:
		frame += 1
		if frame > maximum:
			if ping_pong:
				frame = maximum - 1
				enemy.animation_direction = 0
			else:
				frame = 0
	enemy.authored_animation_frame = clampi(frame, 0, maximum)


## Both kills record a found secret through the shared session flags. Retail
## gates the write on a solo match with an attached profile outside attract
## mode; the remake's progression object carries the same information.
func _record_hurry_up_secret(enemy: Dictionary, killer_seat: int) -> void:
	_stop_hurry_up_hum(enemy)
	var state := String(enemy.get("authored_state", ""))
	var secret_id := (
		HURRY_UP_SECRET_ID_MOTHERSHIP if state == HURRY_UP_MOTHERSHIP_STATE
		else HURRY_UP_SECRET_ID_RARE
	)
	if state == HURRY_UP_MOTHERSHIP_STATE:
		# Retail also re-arms the deadline from the mothership death case.
		_hurry_up_deadline_ms = _simulation_milliseconds() + _hurry_up_interval_ms
	elif _has_active_hurry_up_rare_ship(enemy):
		# FUN_00585770: a surviving second money ship falls through into the
		# mothership death case, which pushes the deadline.
		_hurry_up_deadline_ms = _simulation_milliseconds() + _hurry_up_interval_ms
	if _mode != MODE_SOLO:
		return
	var progression := _progression_for_seat(killer_seat)
	if not bool(progression.get("secret_has_profile", true)):
		return
	var seen_value: Variant = progression.get("secret_session_seen", [])
	if not seen_value is Array or (seen_value as Array).size() <= secret_id:
		return
	(seen_value as Array)[secret_id] = 1
	_emit_event("secret_found", {
		"seat_id": killer_seat,
		"secret_id": secret_id,
		"entity_id": int(enemy.get("id", 0)),
		"enemy_sheet": String(enemy.get("sprite", "")),
	})


func _has_active_hurry_up_rare_ship(exclude: Dictionary) -> bool:
	for enemy_value in _enemies:
		var enemy := enemy_value as Dictionary
		if enemy == exclude or bool(enemy.get("dead", false)):
			continue
		if int(enemy.get("behavior_state_id", 0)) == HURRY_UP_RARE_STATE_ID:
			return true
	return false


# --- Money sucker and guard ship (gap G20, same evidence document) ------------


func _secret_ship_spawners_are_enabled() -> bool:
	if _phase != PHASE_LEVEL or _level_resolved or _level_eight_result_initialized:
		return false
	# Both retail spawners return on screen states 3 and 4. The remake also
	# suppresses them on the mode-three bonus and big-boss levels for the same
	# reason the hurry-up spawner is suppressed there: those levels run their own
	# dispatchers and completion accounting, and a ship added to their object
	# totals would have no way to leave them.
	return not (_is_retail_big_boss_level() or _is_mode_three_bonus())


## Both spawners open with the same shape: draw one float against a fixed range,
## then compare it against the simulation scale times a per-spawner multiplier.
## The draw always happens, so it consumes RNG even on a rejected frame.
func _passes_secret_ship_frame_gate(
	scale_multiplier: float,
	range_maximum: float
) -> bool:
	var draw_fp := _random_retail_float_fp(0.0, range_maximum)
	return _scaled_simulation_delta(roundi(scale_multiplier * FP_ONE)) > draw_fp


func _has_active_secret_ship(state_id: int) -> bool:
	for enemy_value in _enemies:
		var enemy := enemy_value as Dictionary
		if bool(enemy.get("dead", false)):
			continue
		if int(enemy.get("behavior_state_id", 0)) == state_id:
			return true
	return false


## FUN_00581250, dispatched immediately before the hurry-up spawner. Every guard
## runs in the traced order, so a frame that stops early consumes exactly the
## draws it reached and no more.
func _step_money_sucker_spawner() -> void:
	if not _secret_ship_spawners_are_enabled():
		return
	var progression := _progression_for_seat(_turn_seat)
	var cash := int(progression.get("money", 0))
	if cash <= MONEY_SUCKER_CASH_THRESHOLD:
		return
	# Richer players are hunted harder: the trigger weight rises with the cash on
	# hand, and the roll it beats is a fixed forty-thousand-wide range.
	var weight := (
		_trunc_div(cash, MONEY_SUCKER_WEIGHT_DIVISOR)
		+ MONEY_SUCKER_WEIGHT_BASE
		+ _random_int(MONEY_SUCKER_WEIGHT_RANGE)
	)
	if weight <= 0:
		return
	if _random_int(MONEY_SUCKER_TRIGGER_RANGE) >= weight:
		return
	if not _passes_secret_ship_frame_gate(
		MONEY_SUCKER_FRAME_GATE_SCALE,
		MONEY_SUCKER_FRAME_GATE_RANGE
	):
		return
	if _simulation_milliseconds() <= _money_sucker_deadline_ms:
		return
	if _has_active_secret_ship(MONEY_SUCKER_STATE_ID):
		return
	# Retail arms the cooldown before it looks for a slot, so a full entity array
	# still costs the full two-minute wait.
	_money_sucker_deadline_ms = _simulation_milliseconds() + MONEY_SUCKER_COOLDOWN_MS
	if _active_enemy_object_count() >= AUTHORED_ENTITY_SLOT_COUNT:
		return
	_spawn_secret_ship(MONEY_SUCKER_STATE)


## FUN_00581990, dispatched immediately after the hurry-up spawner.
func _step_guard_spawner() -> void:
	if not _secret_ship_spawners_are_enabled():
		return
	if _mode == MODE_TIME_TRIAL:
		return
	if _level_id <= GUARD_SHIP_MINIMUM_LEVEL:
		return
	if _level_id - _guard_previous_level < GUARD_SHIP_LEVEL_GAP:
		return
	if not _passes_secret_ship_frame_gate(
		GUARD_SHIP_FRAME_GATE_SCALE,
		GUARD_SHIP_FRAME_GATE_RANGE
	):
		return
	if _random_int(GUARD_SHIP_TRIGGER_RANGE) <= GUARD_SHIP_TRIGGER_THRESHOLD:
		return
	if _has_active_secret_ship(GUARD_SHIP_STATE_ID):
		return
	if _active_enemy_object_count() >= AUTHORED_ENTITY_SLOT_COUNT:
		return
	_spawn_secret_ship(GUARD_SHIP_STATE)


## Both ships share one spawn body: an entry coin, the level-object increment,
## a speed draw, a y draw, and an animation-interval draw, in that order.
func _spawn_secret_ship(state: String) -> void:
	var is_guard := state == GUARD_SHIP_STATE
	var frame_width := (
		GUARD_SHIP_FRAME_WIDTH if is_guard else MONEY_SUCKER_FRAME_WIDTH
	)
	var frame_height := (
		GUARD_SHIP_FRAME_HEIGHT if is_guard else MONEY_SUCKER_FRAME_HEIGHT
	)
	var enters_from_right := (
		_random_int(SECRET_SHIP_ENTRY_COIN_RANGE) < SECRET_SHIP_ENTRY_RIGHT_THRESHOLD
	)
	var spawn_left := (
		FIELD_WIDTH + SECRET_SHIP_ENTRY_MARGIN if enters_from_right
		else -SECRET_SHIP_ENTRY_MARGIN
	)
	if is_guard:
		# The guard records the level it appeared on, which is what its
		# ten-level gap is measured against.
		_guard_previous_level = _level_id
	_level_total_entities += 1
	# Retail folds the simulation scale into the guard's stored speed at spawn
	# and adds it unscaled every frame; the remake keeps the raw draw and scales
	# per frame, which is the same product under its fixed timestep.
	var speed_fp := (
		_random_retail_float_fp(GUARD_SHIP_SPEED_MINIMUM, GUARD_SHIP_SPEED_MAXIMUM)
		if is_guard
		else _random_retail_float_fp(
			MONEY_SUCKER_SPEED_MINIMUM,
			MONEY_SUCKER_SPEED_MAXIMUM
		)
	)
	var spawn_top := SECRET_SHIP_SPAWN_Y_BASE + _random_int(SECRET_SHIP_SPAWN_Y_RANGE)
	var animation_interval_fp := _random_retail_float_fp(
		HURRY_UP_SPECIAL_SPEED_MINIMUM,
		5.0
	)
	var endless_additive := _endless_step_count * ENDLESS_ORDINARY_HEALTH_STEP
	var health_fp := (
		(_special_health_base_d + GUARD_SHIP_HEALTH_STEP * endless_additive)
		if is_guard
		else (_special_health_base_b + MONEY_SUCKER_HEALTH_STEP * endless_additive)
	) * FP_ONE
	var sprite := GUARD_SHIP_SPRITE if is_guard else MONEY_SUCKER_SPRITE
	var enemy := {
		"id": _allocate_entity_id(),
		# Retail keeps the sprite top-left; the remake centre-normalises.
		"x_fp": spawn_left * FP_ONE + frame_width * FP_ONE / 2,
		"y_fp": spawn_top * FP_ONE + frame_height * FP_ONE / 2,
		"width": frame_width,
		"height": frame_height,
		"collision_width": frame_width,
		"collision_height": (
			frame_height if is_guard else MONEY_SUCKER_HITBOX_HEIGHT
		),
		"health_fp": health_fp,
		"max_health_fp": health_fp,
		"speed_fp": speed_fp,
		"score": 0,
		"cash": 0,
		"sprite": sprite,
		"dead": false,
		"authored_lvd": true,
		"authored_state": state,
		"behavior_state_id": (
			GUARD_SHIP_STATE_ID if is_guard else MONEY_SUCKER_STATE_ID
		),
		# Retail's shared direction field: 0 travels right, 1 travels left, and
		# 3 climbs off the top. No traced site puts either ship into mode 3, so
		# the remake carries the branch without a producer.
		"secret_ship_mode": 1 if enters_from_right else 0,
		"group_id": -1,
		"enemy_index": -1,
		"kill_cohort_id": -1,
		"mirror_x": false,
		"authored_animation_frame": 0,
		"animation_direction": 0,
		"animation_countdown_fp": animation_interval_fp,
		"animation_interval_fp": animation_interval_fp,
		"mask_id": sprite,
		"mask_required": true,
	}
	_enemies.append(enemy)
	_update_secret_ship_source_rect(enemy)
	_emit_event("secret_ship_spawned", {
		"entity_id": int(enemy.id),
		"enemy_sheet": sprite,
		"behavior_state_id": int(enemy.behavior_state_id),
		"enters_from_right": enters_from_right,
		"x_fp": int(enemy.x_fp),
		"y_fp": int(enemy.y_fp),
	})


func _update_secret_ship_source_rect(enemy: Dictionary) -> void:
	var frame := maxi(0, int(enemy.get("authored_animation_frame", 0)))
	var width := int(enemy.get("width", 0))
	var height := int(enemy.get("height", 0))
	var rect := Rect2i(0, frame * height, width, height)
	enemy.source_rect = [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
	_set_mask_source_rect(enemy, rect)
	enemy.collision_x_fp = int(enemy.x_fp)
	enemy.collision_y_fp = int(enemy.y_fp)


## The state-11 branch of FUN_00605fe0. The ship patrols across the surface and
## drains cash from the fighter while it is inside the traced window.
func _update_money_sucker(enemy: Dictionary) -> void:
	_drain_money_sucker_cash(enemy)
	if not _advance_secret_ship(enemy):
		return
	_update_secret_ship_source_rect(enemy)
	_advance_secret_ship_animation(enemy)


## The state-18 branch of FUN_00605fe0. The guard opens a firing window at
## random, walks a beam column down the surface while it is open, and stops
## moving until the window closes.
func _update_guard_ship(enemy: Dictionary) -> void:
	if _random_int(GUARD_BEAM_WINDOW_RANGE) < GUARD_BEAM_WINDOW_THRESHOLD:
		_guard_beam_window = GUARD_BEAM_WINDOW_MINIMUM + _random_int(
			GUARD_BEAM_WINDOW_SPAN
		)
	if _guard_beam_window > 0:
		_guard_beam_window -= 1
		if _random_int(GUARD_BEAM_FIRE_RANGE) < GUARD_BEAM_FIRE_THRESHOLD:
			_fire_guard_beam(enemy)
	if _guard_beam_window >= 1:
		# Retail skips the whole movement block while the window is open.
		_update_secret_ship_source_rect(enemy)
		_advance_secret_ship_animation(enemy)
		return
	if not _advance_secret_ship(enemy):
		return
	_update_secret_ship_source_rect(enemy)
	_advance_secret_ship_animation(enemy)


## The column of static 64x70 segments the guard drops from its own y. Retail
## walks it past the bottom of the surface and simply stops when the pool runs
## dry, so a busy pool shortens the beam instead of dropping it.
func _fire_guard_beam(enemy: Dictionary) -> void:
	var column_top_fp := (
		int(enemy.y_fp)
		- int(enemy.height) * FP_ONE / 2
		+ GUARD_BEAM_COLUMN_OFFSET_Y * FP_ONE
	)
	var column_left_fp := (
		int(enemy.x_fp)
		- int(enemy.width) * FP_ONE / 2
		+ (GUARD_BEAM_COLUMN_OFFSET_X - GUARD_BEAM_COLUMN_INSET_X) * FP_ONE
	)
	_emit_event("guard_beam_fired", {
		"entity_id": int(enemy.id),
		"x_fp": column_left_fp,
		"y_fp": column_top_fp,
	})
	var segment_top_fp := column_top_fp
	while segment_top_fp <= FIELD_HEIGHT * FP_ONE:
		if not _spawn_guard_beam_segment(enemy, column_left_fp, segment_top_fp):
			break
		segment_top_fp += GUARD_BEAM_HEIGHT * FP_ONE


## The shared patrol both states use. Returns false when the ship has left.
func _advance_secret_ship(enemy: Dictionary) -> bool:
	var advance := _scaled_simulation_delta(int(enemy.speed_fp))
	var half_width_fp := int(enemy.width) * FP_ONE / 2
	var half_height_fp := int(enemy.height) * FP_ONE / 2
	match int(enemy.get("secret_ship_mode", 0)):
		0:
			enemy.x_fp = int(enemy.x_fp) + advance
			if (
				int(enemy.x_fp) - half_width_fp
				> (FIELD_WIDTH + SECRET_SHIP_DESPAWN_MARGIN) * FP_ONE
			):
				if String(enemy.authored_state) == GUARD_SHIP_STATE:
					_depart_secret_ship(enemy)
					return false
				enemy.secret_ship_mode = 1
				_reseat_secret_ship(enemy)
		1:
			enemy.x_fp = int(enemy.x_fp) - advance
			if (
				int(enemy.x_fp) - half_width_fp
				< -SECRET_SHIP_DESPAWN_MARGIN * FP_ONE
			):
				if String(enemy.authored_state) == GUARD_SHIP_STATE:
					_depart_secret_ship(enemy)
					return false
				enemy.secret_ship_mode = 0
				_reseat_secret_ship(enemy)
		3:
			enemy.y_fp = int(enemy.y_fp) - advance
			if (
				int(enemy.y_fp) - half_height_fp
				< -SECRET_SHIP_DESPAWN_MARGIN * FP_ONE
			):
				_depart_secret_ship(enemy)
				return false
	return true


## The money sucker turns around rather than leaving, and picks a fresh lane
## every time it does.
func _reseat_secret_ship(enemy: Dictionary) -> void:
	var spawn_top := SECRET_SHIP_SPAWN_Y_BASE + _random_int(SECRET_SHIP_SPAWN_Y_RANGE)
	enemy.y_fp = spawn_top * FP_ONE + int(enemy.height) * FP_ONE / 2


func _depart_secret_ship(enemy: Dictionary) -> void:
	enemy.dead = true
	_level_escaped_entities += 1
	_emit_event("enemy_escaped", {
		"entity_id": int(enemy.id),
		"enemy_sheet": String(enemy.get("sprite", "")),
		"cause": "secret_ship_departure",
		"x_fp": int(enemy.x_fp),
		"y_fp": int(enemy.y_fp),
	})
	_try_resolve_level_counter("secret_ship_departure")


func _advance_secret_ship_animation(enemy: Dictionary) -> void:
	enemy.animation_countdown_fp = int(
		enemy.animation_countdown_fp
	) - _scaled_simulation_delta(FP_ONE)
	if int(enemy.animation_countdown_fp) >= 0:
		return
	enemy.animation_countdown_fp = int(enemy.animation_interval_fp)
	# Retail derives the sheet offset straight from the frame counter; the remake
	# wraps at the sheet's own frame count so the rectangle and the hit mask stay
	# inside the loaded image.
	var frame_count := (
		GUARD_SHIP_FRAME_COUNT
		if String(enemy.get("authored_state", "")) == GUARD_SHIP_STATE
		else MONEY_SUCKER_FRAME_COUNT
	)
	enemy.authored_animation_frame = posmod(
		int(enemy.authored_animation_frame) + 1,
		frame_count
	)


## The cash drain. Retail gates it on the ship being inside the visible band,
## then rolls one coin whose range widens with the victim's cash and subtracts
## the matching money pickup's value.
func _drain_money_sucker_cash(enemy: Dictionary) -> void:
	var left := _trunc_fp_to_int(
		int(enemy.x_fp) - int(enemy.width) * FP_ONE / 2
	) + MONEY_SUCKER_DRAIN_ANCHOR
	if left <= MONEY_SUCKER_DRAIN_LEFT_LIMIT:
		return
	if left >= FIELD_WIDTH - MONEY_SUCKER_DRAIN_RIGHT_MARGIN:
		return
	if not _passes_secret_ship_frame_gate(
		MONEY_SUCKER_DRAIN_GATE_SCALE,
		MONEY_SUCKER_DRAIN_GATE_RANGE
	):
		return
	var victim_seat := _turn_seat
	var progression := _progression_for_seat(victim_seat)
	var cash := int(progression.get("money", 0))
	if cash <= 0:
		return
	if int(enemy.get("secret_ship_mode", 0)) == 3:
		return
	var draw_range := int(MONEY_SUCKER_DRAIN_RANGES[0])
	for step_index in range(MONEY_SUCKER_DRAIN_RANGE_STEPS.size()):
		if cash > int(MONEY_SUCKER_DRAIN_RANGE_STEPS[step_index]):
			draw_range = int(MONEY_SUCKER_DRAIN_RANGES[step_index + 1])
	var draw := _random_int(draw_range)
	var tier := MONEY_SUCKER_DRAIN_TIER_LIMITS.size()
	for tier_index in range(MONEY_SUCKER_DRAIN_TIER_LIMITS.size()):
		if draw <= int(MONEY_SUCKER_DRAIN_TIER_LIMITS[tier_index]):
			tier = tier_index
			break
	var amount := int(MONEY_SUCKER_DRAIN_AMOUNTS[tier])
	progression.money = maxi(0, cash - amount)
	_emit_event("money_sucker_drained", {
		"entity_id": int(enemy.id),
		"seat_id": victim_seat,
		"bonus_id": int(MONEY_SUCKER_DRAIN_BONUS_IDS[tier]),
		"amount": amount,
		"x_fp": int(enemy.x_fp),
		"y_fp": int(enemy.y_fp),
	})


func _is_secret_ship(enemy: Dictionary) -> bool:
	return String(enemy.get("authored_state", "")) in [
		MONEY_SUCKER_STATE,
		GUARD_SHIP_STATE,
	]


## Retail raises the difficulty health base each ship was built from, so the
## next one of that kind is tougher for the rest of the match. Neither ship
## records a found secret.
func _escalate_secret_ship_health_base(enemy: Dictionary) -> void:
	var state := String(enemy.get("authored_state", ""))
	if state == MONEY_SUCKER_STATE:
		_special_health_base_b += MONEY_SUCKER_HEALTH_ESCALATION
	elif state == GUARD_SHIP_STATE:
		_special_health_base_d += GUARD_SHIP_HEALTH_ESCALATION
	else:
		return
	_emit_event("secret_ship_health_base_raised", {
		"entity_id": int(enemy.get("id", 0)),
		"behavior_state_id": int(enemy.get("behavior_state_id", 0)),
		"special_health_base_b": _special_health_base_b,
		"special_health_base_d": _special_health_base_d,
	})


# --- Shared effect pool (retail 0x00af7ea4, FUN_00601cd0) ---------------------


func _reset_effect_pool() -> void:
	_effect_pool = []
	_effect_pool.resize(EFFECT_POOL_SLOT_COUNT)
	for slot_index in range(EFFECT_POOL_SLOT_COUNT):
		_effect_pool[slot_index] = {}


## Retail scans ascending and takes the first inactive slot; a full pool means
## the caller emits nothing at all and consumes none of its random draws.
func _find_free_effect_slot() -> int:
	for slot_index in range(EFFECT_POOL_SLOT_COUNT):
		if (_effect_pool[slot_index] as Dictionary).is_empty():
			return slot_index
	return -1


func _active_effect_objects() -> Array:
	var result: Array = []
	for slot_value in _effect_pool:
		var slot := slot_value as Dictionary
		if not slot.is_empty():
			result.append(slot)
	return result


## The single burst the mothership emits on the frame it sweeps a planet.
func _spawn_planet_debris(enemy: Dictionary) -> void:
	var slot_index := _find_free_effect_slot()
	if slot_index < 0:
		return
	var animation_interval := 4 + _random_int(3)
	var animation_countdown := 3 + _random_int(3)
	var steering_reload := 3 + _random_int(5)
	var lifetime := int(_difficulty.get("debris_lifetime_base", 200)) + _random_int(
		int(_difficulty.get("debris_lifetime_range", 225))
	)
	var owner_seat := _turn_seat
	var speed_fp := _random_retail_float_fp(
		float(_difficulty.get("debris_speed_minimum_milli", 3100)) / 1000.0,
		float(_difficulty.get("debris_speed_maximum_milli", 3800)) / 1000.0
	)
	_effect_pool[slot_index] = {
		"slot": slot_index,
		"kind": EFFECT_KIND_PLANET_DEBRIS,
		"sprite": PLANET_DEBRIS_SPRITE,
		"owner_seat": owner_seat,
		# Retail keeps the top-left; the sim centre-normalises every entity.
		"x_fp": (
			int(enemy.x_fp) - MOTHERSHIP_FRAME_WIDTH * FP_ONE / 2
			+ PLANET_DEBRIS_SPAWN_OFFSET_X * FP_ONE
			+ PLANET_DEBRIS_SIZE * FP_ONE / 2
		),
		"y_fp": (
			int(enemy.y_fp) - MOTHERSHIP_FRAME_HEIGHT * FP_ONE / 2
			+ PLANET_DEBRIS_SPAWN_OFFSET_Y * FP_ONE
			+ PLANET_DEBRIS_SIZE * FP_ONE / 2
		),
		"width": PLANET_DEBRIS_SIZE,
		"height": PLANET_DEBRIS_SIZE,
		"heading": PLANET_DEBRIS_START_HEADING,
		"speed_fp": speed_fp,
		"lifetime_fp": lifetime * FP_ONE,
		"animation_frame": 0,
		"animation_interval_fp": animation_interval * FP_ONE,
		"animation_countdown_fp": animation_countdown * FP_ONE,
		"steering_reload_fp": steering_reload * FP_ONE,
		"steering_countdown_fp": steering_reload * FP_ONE,
		"proximity_reload_fp": FP_ONE,
		"proximity_countdown_fp": FP_ONE,
		"animation_row": 0,
		"mask_id": ROCKET_SPRITE_SHEET,
		"mask_required": true,
	}
	_set_rocket_source_rect(_effect_pool[slot_index] as Dictionary)
	_emit_event("effect_object_spawned", {
		"slot": slot_index,
		"kind": EFFECT_KIND_PLANET_DEBRIS,
		"seat_id": owner_seat,
		"x_fp": int((_effect_pool[slot_index] as Dictionary).x_fp),
		"y_fp": int((_effect_pool[slot_index] as Dictionary).y_fp),
	})


## One beam segment of the guard ship's column. Retail walks the column from the
## ship down past the surface and simply stops when the pool runs dry.
func _spawn_guard_beam_segment(
	enemy: Dictionary,
	left_fp: int,
	top_fp: int
) -> bool:
	var slot_index := _find_free_effect_slot()
	if slot_index < 0:
		return false
	_effect_pool[slot_index] = {
		"slot": slot_index,
		"kind": EFFECT_KIND_GUARD_BEAM,
		"sprite": GUARD_BEAM_SPRITE,
		"owner_seat": _turn_seat,
		"source_entity_id": int(enemy.get("id", 0)),
		"x_fp": left_fp + GUARD_BEAM_WIDTH * FP_ONE / 2,
		"y_fp": top_fp + GUARD_BEAM_HEIGHT * FP_ONE / 2,
		"width": GUARD_BEAM_WIDTH,
		"height": GUARD_BEAM_HEIGHT,
		"heading": 0,
		"speed_fp": 0,
		"lifetime_fp": GUARD_BEAM_LIFETIME_FP,
		"animation_frame": 0,
		"animation_interval_fp": 0,
		"animation_countdown_fp": 0,
		"steering_reload_fp": 0,
		"steering_countdown_fp": 0,
		"proximity_reload_fp": 0,
		"proximity_countdown_fp": 0,
		"collision_simple": true,
		"source_rect": [0, 0, GUARD_BEAM_WIDTH, GUARD_BEAM_HEIGHT],
	}
	return true


func _step_effect_pool() -> void:
	for slot_index in range(EFFECT_POOL_SLOT_COUNT):
		var slot := _effect_pool[slot_index] as Dictionary
		if slot.is_empty():
			continue
		match int(slot.kind):
			EFFECT_KIND_PLANET_DEBRIS:
				_update_planet_debris(slot)
			EFFECT_KIND_GUARD_BEAM:
				_update_guard_beam(slot)


func _update_guard_beam(slot: Dictionary) -> void:
	slot.lifetime_fp = int(slot.lifetime_fp) - _scaled_simulation_delta(FP_ONE)
	if int(slot.lifetime_fp) < FP_ONE:
		_release_effect_slot(slot, "expired")


func _update_planet_debris(slot: Dictionary) -> void:
	slot.lifetime_fp = int(slot.lifetime_fp) - _scaled_simulation_delta(FP_ONE)
	if int(slot.lifetime_fp) < 0:
		_release_effect_slot(slot, "expired")
		return
	var owner_seat := int(slot.owner_seat)
	if _seat_is_participating(owner_seat) and _seat_fighter_is_active(owner_seat):
		slot.steering_countdown_fp = int(
			slot.steering_countdown_fp
		) - _scaled_simulation_delta(FP_ONE)
		if int(slot.steering_countdown_fp) < 0:
			slot.steering_countdown_fp = int(slot.steering_reload_fp)
			_steer_planet_debris(slot, owner_seat)
		_update_planet_debris_proximity(slot, owner_seat)
	var heading_index := clampi(
		int(slot.heading),
		1,
		PLANET_DEBRIS_HEADING_COUNT
	) - 1
	slot.x_fp = int(slot.x_fp) + _scaled_simulation_delta(
		Fixed.multiply(int(ROCKET_HEADING_X_Q16[heading_index]), int(slot.speed_fp))
	)
	slot.y_fp = int(slot.y_fp) + _scaled_simulation_delta(
		Fixed.multiply(int(ROCKET_HEADING_Y_Q16[heading_index]), int(slot.speed_fp))
	)
	_set_rocket_source_rect(slot)


## Retail rolls one draw against the difficulty steering threshold. Below it the
## debris wanders, otherwise it turns toward the fighter along the shortest arc.
func _steer_planet_debris(slot: Dictionary, owner_seat: int) -> void:
	var wander := _random_int(PLANET_DEBRIS_STEERING_RANGE) < int(
		_difficulty.get("debris_steering_threshold", 40)
	)
	if wander:
		if _random_int(100) < PLANET_DEBRIS_WANDER_DOWN_LIMIT:
			slot.heading = int(slot.heading) - 1
		if _random_int(100) > PLANET_DEBRIS_WANDER_UP_LIMIT:
			slot.heading = int(slot.heading) + 1
		if int(slot.heading) < 1:
			slot.heading = PLANET_DEBRIS_HEADING_COUNT
		if int(slot.heading) > PLANET_DEBRIS_HEADING_COUNT:
			slot.heading = 1
		return
	var player: Dictionary = _players[owner_seat]
	var quadrant := 0
	if int(slot.x_fp) < int(player.x_fp):
		quadrant = 2
	if int(player.x_fp) < int(slot.x_fp):
		quadrant |= 1
	if int(player.y_fp) < int(slot.y_fp):
		quadrant |= 8
	if int(slot.y_fp) < int(player.y_fp):
		quadrant |= 4
	if quadrant >= PLANET_DEBRIS_QUADRANT_HEADING.size():
		return
	var target := int(PLANET_DEBRIS_QUADRANT_HEADING[quadrant])
	var heading := int(slot.heading)
	if target == heading:
		return
	var clockwise := posmod(target - heading, PLANET_DEBRIS_HEADING_COUNT)
	var counter := posmod(heading - target, PLANET_DEBRIS_HEADING_COUNT)
	var step := 0
	if clockwise == counter:
		step = -1 if _random_int(100) < 50 else 1
	elif clockwise < counter:
		step = 1
	else:
		step = -1
	heading += step
	if heading < 1:
		heading = PLANET_DEBRIS_HEADING_COUNT
	if heading > PLANET_DEBRIS_HEADING_COUNT:
		heading = 1
	slot.heading = heading


## The approach beep: the reload shrinks with the distance to the fighter, so a
## closing debris object ticks faster.
func _update_planet_debris_proximity(slot: Dictionary, owner_seat: int) -> void:
	slot.proximity_countdown_fp = int(
		slot.proximity_countdown_fp
	) - _scaled_simulation_delta(FP_ONE)
	if int(slot.proximity_countdown_fp) >= 0:
		return
	var player: Dictionary = _players[owner_seat]
	var distance := _effect_distance_to(slot, player)
	slot.proximity_countdown_fp = (
		distance * FP_ONE / EFFECT_PROXIMITY_DIVISOR + EFFECT_PROXIMITY_BASE * FP_ONE
	)
	var remaining := maxi(0, EFFECT_PROXIMITY_CEILING - distance)
	_emit_event("effect_object_proximity", {
		"slot": int(slot.slot),
		"seat_id": owner_seat,
		"key": "beep",
		"distance": distance,
		"volume_scalar_milli": remaining * 1000 / 3,
		"x_fp": int(slot.x_fp),
		"y_fp": int(slot.y_fp),
	})


func _effect_distance_to(slot: Dictionary, player: Dictionary) -> int:
	var delta_x := _trunc_fp_to_int(absi(int(slot.x_fp) - int(player.x_fp)))
	var delta_y := _trunc_fp_to_int(absi(int(slot.y_fp) - int(player.y_fp)))
	return int(sqrt(float(delta_x * delta_x + delta_y * delta_y)))


func _seat_fighter_is_active(seat_id: int) -> bool:
	if seat_id < 0 or seat_id >= _players.size():
		return false
	var player: Dictionary = _players[seat_id]
	return bool(player.get("active", false)) and bool(player.get("alive", false))


func _release_effect_slot(slot: Dictionary, cause: String) -> void:
	var slot_index := int(slot.get("slot", -1))
	_emit_event("effect_object_removed", {
		"slot": slot_index,
		"kind": int(slot.get("kind", 0)),
		"cause": cause,
		"x_fp": int(slot.get("x_fp", 0)),
		"y_fp": int(slot.get("y_fp", 0)),
	})
	if slot_index >= 0 and slot_index < EFFECT_POOL_SLOT_COUNT:
		_effect_pool[slot_index] = {}


## Retail's FUN_005842c0: a pool object that reaches a fighter destroys it, and
## the same pass lets player fire clear pool objects out of the air.
func _resolve_effect_pool_collisions() -> void:
	for slot_index in range(EFFECT_POOL_SLOT_COUNT):
		var slot := _effect_pool[slot_index] as Dictionary
		if slot.is_empty():
			continue
		var hit_player := false
		for player_value in _players:
			var player: Dictionary = player_value
			if not bool(player.active) or not bool(player.alive):
				continue
			if int(player.invulnerable_ticks) > 0:
				continue
			if not _objects_collide(slot, player):
				continue
			hit_player = true
			_damage_player(player, 1)
			break
		if hit_player:
			_release_effect_slot(slot, "fighter_impact")
			continue
		for projectile_value in _player_projectiles_in_slot_order():
			var projectile: Dictionary = projectile_value
			if (
				bool(projectile.get("expired", false))
				or String(projectile.get("owner_kind", "")) != "player"
			):
				continue
			if not _objects_collide(projectile, slot):
				continue
			if not bool(projectile.get("is_laser", false)):
				projectile.expired = true
			_record_player_projectile_hit(int(projectile.get("owner_id", 0)))
			_release_effect_slot(slot, "shot_down")
			break


func _is_hurry_up_ship(enemy: Dictionary) -> bool:
	return String(enemy.get("authored_state", "")) in [
		HURRY_UP_MOTHERSHIP_STATE,
		HURRY_UP_RARE_STATE,
	]


func _spawn_authored_enemy(
	group: Dictionary,
	enemy_definition: Dictionary,
	ordinary_speed_fp: int,
	sprite: String,
	resource_kill_score: int,
	resource_slot_id: int,
	level_mode_id: int,
	mirror_x: bool
) -> void:
	var enemy_index := int(enemy_definition.id)
	var entry_x := FIELD_WIDTH / 2
	var formation_x := FIELD_WIDTH / 2
	if mirror_x:
		entry_x -= int(group.entry_origin_x)
		formation_x -= int(enemy_definition.formation_target_x)
	else:
		entry_x += int(group.entry_origin_x)
		formation_x += int(enemy_definition.formation_target_x)
	var entry_y := int(group.entry_origin_y)
	var activation_delay := int(group.first_activation_delay_ticks)
	if level_mode_id != 2:
		activation_delay += enemy_index * int(group.activation_stagger_ticks)
	var velocity_x_fp := _milli_to_fp(int(group.initial_velocity_x_milli))
	if mirror_x:
		velocity_x_fp = -velocity_x_fp
	var velocity_y_fp := _milli_to_fp(int(group.initial_velocity_y_milli))
	var path_points: Array = group.path_points
	var first_point: Dictionary = path_points[0]
	var acceleration_x_fp := _milli_to_fp(int(first_point.acceleration_x_milli))
	if mirror_x:
		acceleration_x_fp = -acceleration_x_fp
	var acceleration_y_fp := _milli_to_fp(int(first_point.acceleration_y_milli))
	var health_fp := int(enemy_definition.base_health) * FP_ONE
	if _endless_step_count > 0:
		# Retail adds +1.0 enemy health per crossed hundred (0x00e113f8).
		health_fp += _endless_step_count * ENDLESS_ORDINARY_HEALTH_STEP * FP_ONE
	if _mode == MODE_COOP and _balance == BALANCE_BALANCED:
		health_fp *= 2
	var timer_a := maxi(
		int(enemy_definition.behavior_timer_a_initial)
		+ int(_difficulty.timer_a_initial_adjustment),
		int(_difficulty.timer_a_floor)
	)
	var timer_b := 0
	if (
		int(enemy_definition.behavior_timer_b_initial) != 0
		or int(enemy_definition.behavior_timer_b_step) != 0
	):
		timer_b = maxi(
			int(enemy_definition.behavior_timer_b_initial)
			+ int(_difficulty.timer_b_initial_adjustment),
			int(_difficulty.timer_b_floor)
		)
	var slot_seed: Dictionary = {
		"phase": 0,
		"countdown_sixths": 4 * SIMULATION_SCALE_DENOMINATOR,
		"direction": 0,
	}
	if _authored_spawn_slot < _authored_slot_seeds.size():
		slot_seed = _authored_slot_seeds[_authored_spawn_slot]
	_authored_spawn_slot += 1
	var enemy := {
		"id": _allocate_entity_id(),
		"x_fp": entry_x * FP_ONE,
		"y_fp": entry_y * FP_ONE,
		"anchor_x_fp": formation_x * FP_ONE,
		"target_y_fp": int(enemy_definition.formation_target_y) * FP_ONE,
		"formation_target_x_fp": formation_x * FP_ONE,
		"formation_target_y_fp": int(enemy_definition.formation_target_y) * FP_ONE,
		"width": AUTHORED_ENEMY_SIZE,
		"height": AUTHORED_ENEMY_SIZE,
		"health_fp": health_fp,
		"max_health_fp": health_fp,
		"speed_fp": ordinary_speed_fp,
		"path": "formation",
		"behavior_timer_a": timer_a,
		"behavior_timer_a_step": int(enemy_definition.behavior_timer_a_step),
		"behavior_timer_a_floor": int(_difficulty.timer_a_floor),
		"behavior_timer_b": timer_b,
		"behavior_timer_b_step": int(enemy_definition.behavior_timer_b_step),
		"behavior_timer_b_floor": int(_difficulty.timer_b_floor),
		"projectile_speed_fp": int(_difficulty.alien_projectile_speed_fp),
		# The per-resource LVD binding is the sole gameplay score authority.
		# Mode-three authored_enemy_score remains a catalog evidence alias only.
		"score": resource_kill_score,
		"cash": 0,
		"sprite": sprite,
		"dead": false,
		"authored_lvd": true,
		"authored_state": "delayed" if activation_delay > 0 else "entry",
		"behavior_state_id": 1,
		"group_id": int(group.id),
		"enemy_index": enemy_index,
		"kill_cohort_id": int(group.kill_cohort_id),
		"group_mode_id": int(group.group_mode_id),
		"level_mode_id": level_mode_id,
		"resource_slot_id": resource_slot_id,
		"mirror_x": mirror_x,
		"activation_delay_ticks": activation_delay,
		"activation_delay_sixths": activation_delay * SIMULATION_SCALE_DENOMINATOR,
		"velocity_x_fp": velocity_x_fp,
		"velocity_y_fp": velocity_y_fp,
		"acceleration_x_fp": acceleration_x_fp,
		"acceleration_y_fp": acceleration_y_fp,
		"path_points": path_points,
		"path_index": 0,
		"path_progress_ticks": 0,
		"path_progress_sixths": 0,
		"authored_sprite_frame": _sprite_frames.enemy_direction_frame(
			velocity_x_fp,
			velocity_y_fp,
			mirror_x
		),
		"authored_animation_frame": int(slot_seed.phase),
		"animation_countdown_sixths": int(slot_seed.countdown_sixths),
		"animation_direction": int(slot_seed.direction),
		"animation_max_phase": 5,
		"animation_metadata": 1 if _level_id == 3 else 0,
		"group_drift_x_fp": 0,
		"group_drift_y_fp": 0,
		"leader_has_followers": false,
		"follower_leader_slot": -1,
		"saved_behavior_timer_a": timer_a,
		"saved_health_fp": health_fp,
		"state_four_turn_countdown": 1,
		"state_four_velocity_x_fp": 0,
		"state_four_acceleration_x_fp": 0,
		"mask_id": sprite,
	}
	_update_enemy_mask_rect(enemy)
	_enemies.append(enemy)


func _spawn_enemy(wave: Dictionary, enemy_index: int, sprite: String) -> void:
	var columns: int = maxi(1, int(wave.columns))
	var column: int = enemy_index % columns
	var row: int = floori(float(enemy_index) / float(columns))
	var health_fp := int(wave.health_fp)
	if _mode == MODE_COOP and _balance == BALANCE_BALANCED:
		health_fp *= 2
	var speed_fp := int(wave.speed_fp)
	var fire_interval := int(wave.fire_interval_ticks)
	var spawn_x_fp: int = (int(wave.spawn_x) + column * int(wave.spacing_x)) * FP_ONE
	var spawn_y_fp: int = (int(wave.spawn_y) - row * 12) * FP_ONE
	var target_y_fp: int = (82 + row * int(wave.spacing_y)) * FP_ONE
	_enemies.append({
		"id": _allocate_entity_id(),
		"x_fp": spawn_x_fp,
		"y_fp": spawn_y_fp,
		"anchor_x_fp": spawn_x_fp,
		"target_y_fp": target_y_fp,
		"width": ENEMY_WIDTH,
		"height": ENEMY_HEIGHT,
		"health_fp": health_fp,
		"max_health_fp": health_fp,
		"speed_fp": speed_fp,
		"path": String(wave.path),
		"fire_interval_ticks": fire_interval,
		"next_fire_tick": _level_tick + fire_interval + enemy_index * 7,
		"projectile_speed_fp": int(wave.projectile_speed_fp),
		"score": int(wave.score),
		"cash": int(wave.cash),
		"sprite": sprite,
		"dead": false,
	})


func _update_players(
	allow_fire: bool = true,
	allow_secondary: bool = true
) -> void:
	for player_value in _players:
		var player: Dictionary = player_value
		if not bool(player.active) or not bool(player.alive):
			continue
		if int(player.invulnerable_ticks) > 0:
			player.invulnerable_ticks = int(player.invulnerable_ticks) - 1
		if int(player.projectile_suppression_ticks) > 0:
			player.projectile_suppression_ticks = (
				int(player.projectile_suppression_ticks) - 1
			)
		var seat_id := int(player.seat_id)
		var progression := _progression_for_seat(seat_id)
		var mask := _input_masks[seat_id]
		var direction := 0
		var horizontal_active := false
		if (mask & ACTION_LEFT) != 0:
			direction -= 1
			player.sprite_phase_half_steps = maxi(0, int(player.sprite_phase_half_steps) - 1)
			horizontal_active = true
		elif (mask & ACTION_RIGHT) != 0:
			direction += 1
			player.sprite_phase_half_steps = int(player.sprite_phase_half_steps) + 1
			if int(player.sprite_phase_half_steps) >= 22:
				player.sprite_phase_half_steps = 20
			horizontal_active = true
		if not horizontal_active:
			if int(player.sprite_phase_half_steps) < 10:
				player.sprite_phase_half_steps = int(player.sprite_phase_half_steps) + 1
			elif int(player.sprite_phase_half_steps) > 10:
				player.sprite_phase_half_steps = int(player.sprite_phase_half_steps) - 1
		player.mask_frame = mini(10, int(player.sprite_phase_half_steps) / 2)
		if int(progression.get("drunk_ticks", 0)) > 0:
			# FUN_005eb550 reads the live Drunk deadline in the normal player
			# controller and reverses horizontal travel for the whole effect.
			direction = -direction
		var movement_x_fp := int(player.x_fp)
		if int(progression.get("mirror_ticks", 0)) > 0:
			movement_x_fp = int(player.get("mirror_anchor_x_fp", player.x_fp))
		movement_x_fp = Fixed.clamp_value(
			movement_x_fp
			+ direction * _scaled_simulation_delta(
				mini(14 * FP_ONE, int(progression.speed_fp))
			),
			PLAYER_MIN_X_FP,
			PLAYER_MAX_X_FP
		)
		player.x_fp = movement_x_fp
		if int(progression.get("mirror_ticks", 0)) > 0:
			# Retail moves a separate top-left anchor because it temporarily
			# mutates the ordinary X while drawing/firing the reflected fighter.
			player.mirror_anchor_x_fp = movement_x_fp
		var fire_held := allow_fire and (mask & ACTION_FIRE) != 0
		var fire_pressed := allow_fire and _action_just_pressed(seat_id, ACTION_FIRE)
		if fire_pressed:
			_fire_player_weapon(player)
		if allow_fire and bool(progression.auto_fire) and fire_held:
			var current_ms := _simulation_milliseconds()
			if current_ms > int(player.auto_fire_deadline_ms):
				_fire_player_weapon(player)
				player.auto_fire_deadline_ms = (
					current_ms + int(progression.auto_fire_delay_ms)
				)
		_try_fire_rocket(player, allow_secondary)


func _try_fire_rocket(player: Dictionary, control_enabled: bool = true) -> bool:
	if _ordnance_contract.is_empty():
		return false
	var seat_id := int(player.get("seat_id", -1))
	if seat_id < 0 or seat_id >= _secondary_rocket_armed.size():
		return false
	var pressed := (_input_masks[seat_id] & ACTION_SECONDARY) != 0
	if not pressed:
		_secondary_rocket_armed[seat_id] = true
		return false
	if not control_enabled:
		return false
	var progression := _progression_for_seat(seat_id)
	# Retail leaves the edge armed when inventory is empty. Pool/target failures,
	# by contrast, happen after the edge is consumed and require a release.
	if (
		not bool(_secondary_rocket_armed[seat_id])
		or int(progression.get("rockets", 0)) <= 0
	):
		return false
	_secondary_rocket_armed[seat_id] = false
	var player_slot := _find_available_player_projectile_slot()
	if player_slot < 0:
		return false
	var target := _select_rocket_target()
	if target.is_empty():
		return false
	var target_kind := String(target.get("target_kind", "enemy"))
	var target_entity_id := int(target.get("target_entity_id", 0))
	var target_state_id := int(target.get("state_id", 0))
	var target_reserved := (
		target_kind == "enemy" and target_state_id not in [13, 18]
	)
	if target_reserved:
		var target_enemy := target.get("enemy", {}) as Dictionary
		target_enemy.rocket_reserved = true

	_rocket_effect_until_ms = _simulation_milliseconds() + 500
	_rocket_effect_active = true
	_rocket_fired_this_level = true
	progression.rockets = int(progression.get("rockets", 0)) - 1
	_record_rocket_missile_fired(seat_id)
	var animation_period_fp := (_random_int(3) + 4) * FP_ONE
	var animation_countdown_fp := (_random_int(3) + 3) * FP_ONE
	var stale_contribution := 0
	if player_slot < _player_projectile_slot_stale_contributions.size():
		stale_contribution = int(
			_player_projectile_slot_stale_contributions[player_slot]
		)
	var projectile := {
		"id": _allocate_entity_id(),
		"owner_kind": "player",
		"owner_id": seat_id,
		"player_slot": player_slot,
		"projectile_kind": ROCKET_PROJECTILE_KIND,
		"sprite_sheet_id": ROCKET_SPRITE_SHEET,
		"target_entity_id": target_entity_id,
		"target_kind": target_kind,
		"target_state_id": target_state_id,
		"target_reserved": target_reserved,
		"heading": 1,
		"lifetime_fp": ROCKET_LIFETIME_FP,
		"animation_row": 0,
		"animation_period_fp": animation_period_fp,
		"animation_countdown_fp": animation_countdown_fp,
		"steering_period_fp": FP_ONE,
		"steering_countdown_fp": FP_ONE,
		# The simulation's projectile contract stores centers. The retail record
		# stores a 24px missile top-left relative to the 40x28 fighter top-left.
		"x_fp": int(player.x_fp) + FP_ONE,
		"y_fp": int(player.y_fp) - 10 * FP_ONE,
		"velocity_x_fp": int(ROCKET_HEADING_X_Q16[0]) * 10,
		"velocity_y_fp": int(ROCKET_HEADING_Y_Q16[0]) * 10,
		"width": ROCKET_FRAME_SIZE,
		"height": ROCKET_FRAME_SIZE,
		"damage_fp": ROCKET_DAMAGE_FP,
		"prototype_id": 200,
		"capacity_contribution": 0,
		"stale_capacity_contribution": stale_contribution,
		"source_rect": [0, 0, ROCKET_FRAME_SIZE, ROCKET_FRAME_SIZE],
		"mask_id": ROCKET_SPRITE_SHEET,
		"mask_required": true,
		"spawn_tick": _tick,
		"expired": false,
	}
	_set_rocket_source_rect(projectile)
	_stamp_projectile_presentation(projectile)
	_projectiles.append(projectile)
	_emit_event("rocket_fired", {
		"seat_id": seat_id,
		"projectile_id": int(projectile.id),
		"target_entity_id": target_entity_id,
		"target_kind": target_kind,
		"x_fp": int(projectile.x_fp),
		"y_fp": int(projectile.y_fp),
	})
	_emit_event("sound_cue", {
		"key": "rocket",
		"frequency_hz": 32000,
		"source_hz": 32000,
		"volume_index": 255,
		"seat_id": seat_id,
		"projectile_id": int(projectile.id),
		"retail_left_fp": int(projectile.x_fp) - 12 * FP_ONE,
		"retail_top_fp": int(projectile.y_fp) - 12 * FP_ONE,
		"x_fp": int(projectile.x_fp) - 12 * FP_ONE,
		"y_fp": int(projectile.y_fp) - 12 * FP_ONE,
	})
	return true


func _select_rocket_target() -> Dictionary:
	var candidates: Array[Dictionary] = []
	var total_weight := 0
	for enemy_value in _enemies:
		var enemy := enemy_value as Dictionary
		if not _rocket_enemy_is_eligible(enemy):
			continue
		var state_id := int(enemy.get("behavior_state_id", 0))
		var weight := _rocket_target_weight(state_id)
		candidates.append({
			"target_kind": "enemy",
			"target_entity_id": int(enemy.get("id", 0)),
			"state_id": state_id,
			"weight": weight,
			"enemy": enemy,
		})
		total_weight += weight
	if _is_retail_big_boss_level() and _boss_entered and not _boss_runtime_blocked:
		var boss_snapshot := _retail_big_boss.snapshot()
		if bool(boss_snapshot.get("active", false)):
			candidates.append({
				"target_kind": "boss",
				"target_entity_id": 0,
				"state_id": int(_boss_contract.get("retail_state_id", 13)),
				"weight": 16,
			})
			total_weight += 16
	if candidates.is_empty() or total_weight <= 0:
		return {}
	var selected_bucket := _random_int(total_weight)
	for candidate_value in candidates:
		var candidate := candidate_value as Dictionary
		var weight := int(candidate.weight)
		if selected_bucket < weight:
			return candidate
		selected_bucket -= weight
	return candidates.back()


func _rocket_enemy_is_eligible(enemy: Dictionary) -> bool:
	if (
		not bool(enemy.get("active", true))
		or bool(enemy.get("dead", false))
		or int(enemy.get("behavior_state_id", 0)) in [5, 8]
		or bool(enemy.get("rocket_reserved", false))
	):
		return false
	var targetability := float(enemy.get(
		"targetability_scalar",
		float(int(enemy.get("targetability_fp", FP_ONE))) / float(FP_ONE)
	))
	return not is_nan(targetability) and targetability <= 1.0


func _rocket_target_weight(state_id: int) -> int:
	if state_id in [6, 9, 11, 12]:
		return 8
	if state_id in [13, 18]:
		return 16
	return 1


func _fire_player_weapon(player: Dictionary) -> void:
	var seat_id := int(player.seat_id)
	var progression := _progression_for_seat(seat_id)
	var mirror_active := int(progression.get("mirror_ticks", 0)) > 0
	var active_count := 0
	for projectile in _projectiles:
		if (
			String(projectile.owner_kind) == "player"
			and int(projectile.owner_id) == seat_id
			and not bool(projectile.expired)
		):
			active_count += int(projectile.get("capacity_contribution", 1))
	if seat_id < _ordinary_projectile_counter_adjustment_by_seat.size():
		active_count = maxi(
			0,
			active_count
			+ int(_ordinary_projectile_counter_adjustment_by_seat[seat_id])
		)
	# Mirror deliberately substitutes the retail alternate capacity of 100 and
	# passes contribution zero into both complete helper calls. This means a
	# counted total of 99 can emit repeated mirrored volleys; exactly 100 blocks.
	var capacity := (
		MIRROR_PROJECTILE_CAPACITY
		if mirror_active
		else int(progression.bullet_capacity)
	)
	if active_count >= capacity:
		return
	var weapon: Dictionary = _weapons_by_id.get(
		int(progression.weapon_id),
		_weapons_by_id[0]
	)
	var allocated := _spawn_player_side_graph(
		weapon,
		progression,
		player,
		false,
		0 if mirror_active else 1
	)
	if mirror_active:
		# Reflect the mutable fighter X, invoke the same complete helper with
		# non-counting shots, then restore it.
		allocated += _spawn_player_side_graph(weapon, progression, player, true, 0)
	if allocated <= 0:
		return
	_emit_event("weapon_fired", {
		"seat_id": seat_id,
		"weapon_id": int(weapon.id),
		"mirror_active": mirror_active,
		"mirror_x_fp": _mirrored_x_fp(int(player.x_fp)),
		"x_fp": int(player.x_fp),
		"y_fp": int(player.y_fp),
	})


func _spawn_player_side_graph(
	weapon: Dictionary,
	progression: Dictionary,
	player: Dictionary,
	mirrored: bool,
	capacity_contribution: int
) -> int:
	var seat_id := int(player.seat_id)
	var allocated := 0
	var fighter_x_fp := int(player.x_fp)
	if mirrored:
		fighter_x_fp = _mirrored_x_fp(fighter_x_fp)
	allocated += _spawn_player_weapon_graph(
		weapon,
		progression,
		seat_id,
		fighter_x_fp,
		int(player.y_fp),
		PLAYER_HEIGHT,
		capacity_contribution
	)
	# Settled Scoop captives do not fire their live alien graph. Retail maps the
	# equipped weapon through a hidden weapon table and invokes that graph at
	# fixed ship-relative X offsets, main -> left -> right. Captive objects are
	# always non-counting, including outside Mirror.
	var captive_weapon: Dictionary = CAPTIVE_WEAPON_DEFINITIONS[clampi(
		int(weapon.id),
		0,
		CAPTIVE_WEAPON_DEFINITIONS.size() - 1
	)]
	for captive_value in _captured_enemies_for_seat(seat_id, true):
		var captive: Dictionary = captive_value
		var side := int(captive.get("captured_side", 0))
		var captive_x_fp := fighter_x_fp + (-36 if side == 0 else 36) * FP_ONE
		allocated += _spawn_player_projectile_graph(
			captive_weapon.projectiles,
			int(captive_weapon.damage_fp),
			progression,
			seat_id,
			captive_x_fp,
			int(player.y_fp),
			PLAYER_HEIGHT,
			0
		)
	return allocated


func _spawn_player_weapon_graph(
	weapon: Dictionary,
	progression: Dictionary,
	seat_id: int,
	origin_x_fp: int,
	origin_y_fp: int,
	origin_height: int,
	capacity_contribution: int
) -> int:
	return _spawn_player_projectile_graph(
		weapon.projectiles,
		int(weapon.damage_fp),
		progression,
		seat_id,
		origin_x_fp,
		origin_y_fp,
		origin_height,
		capacity_contribution
	)


func _spawn_player_projectile_graph(
	definitions: Array,
	damage_fp: int,
	progression: Dictionary,
	seat_id: int,
	origin_x_fp: int,
	origin_y_fp: int,
	origin_height: int,
	capacity_contribution: int
) -> int:
	var allocated := 0
	for definition_value in definitions:
		# The retail player-projectile allocator owns exactly 100 objects. The
		# weighted weapon-capacity counter is a separate gate: Mirror and Scoop
		# shots contribute zero to that counter, but still occupy physical slots.
		# Allocation stops before any prototype-specific RNG is consumed.
		var player_slot := _find_available_player_projectile_slot()
		if player_slot < 0:
			return allocated
		var definition: Dictionary = definition_value
		var bullet_speed_fp := int(progression.get("bullet_speed_fp", FP_ONE))
		var velocity_x_fp := Fixed.multiply(
			int(definition.velocity_x_fp),
			bullet_speed_fp
		)
		var velocity_y_fp := Fixed.multiply(
			int(definition.velocity_y_fp),
			bullet_speed_fp
		)
		var projectile_x_fp := origin_x_fp + int(definition.offset_x_fp)
		var projectile_height := int(definition.height)
		var projectile_y_fp: int = (
			origin_y_fp
			- (origin_height * FP_ONE >> 1)
			+ int(definition.offset_y_fp)
			+ (projectile_height * FP_ONE >> 1)
		)
		var special_secondary := int(definition.get("special_secondary_raw", 0))
		if special_secondary > 160 and special_secondary < 170:
			velocity_x_fp = _random_centered_velocity_fp(special_secondary - 160)
		elif special_secondary > 170:
			projectile_x_fp += _scaled_simulation_delta(
				_random_centered_velocity_fp(special_secondary - 170)
			)
		var projectile := {
			"id": _allocate_entity_id(),
			"owner_kind": "player",
			"owner_id": seat_id,
			"player_slot": player_slot,
			"x_fp": projectile_x_fp,
			"y_fp": projectile_y_fp,
			"velocity_x_fp": velocity_x_fp,
			"velocity_y_fp": velocity_y_fp,
			"width": int(definition.width),
			"height": projectile_height,
			"damage_fp": damage_fp,
			"prototype_id": int(definition.prototype_id),
			"capacity_contribution": capacity_contribution,
			"animation_countdown_fp": FP_ONE,
			"spawn_tick": _tick,
			"expired": false,
			"mask_id": "weapons_big",
			"mask_required": true,
		}
		if _sprite_frames.projectile_is_persistent(int(definition.prototype_id)):
			projectile.is_laser = true
			projectile.collision_simple = true
			_refresh_laser_collision_geometry(projectile)
		var source_rect := _sprite_frames.projectile_source_rect(int(definition.prototype_id))
		if source_rect.size.x > 0 and source_rect.size.y > 0:
			_set_mask_source_rect(projectile, source_rect)
			projectile.source_rect = [
				source_rect.position.x,
				source_rect.position.y,
				source_rect.size.x,
				source_rect.size.y,
			]
		_stamp_projectile_presentation(projectile)
		_projectiles.append(projectile)
		if player_slot < _player_projectile_slot_stale_contributions.size():
			_player_projectile_slot_stale_contributions[player_slot] = (
				capacity_contribution
			)
		_rocket_fired_this_level = true
		_record_player_projectile_fired(seat_id)
		allocated += 1
	return allocated


func _active_player_projectile_object_count() -> int:
	var count := 0
	for projectile_value in _projectiles:
		var projectile: Dictionary = projectile_value
		if (
			String(projectile.get("owner_kind", "")) == "player"
			and not bool(projectile.get("expired", false))
		):
			count += 1
	return count


func _find_available_player_projectile_slot() -> int:
	# FUN_005df6e0 scans the fixed 100-record array from slot zero and claims
	# the first inactive record. Expired objects are already inactive even if
	# this frame's compacting cleanup has not removed their dictionaries yet.
	var occupied := PackedByteArray()
	occupied.resize(PLAYER_PROJECTILE_SLOT_COUNT)
	var unslotted_count := 0
	for projectile_value in _projectiles:
		var projectile: Dictionary = projectile_value
		if (
			String(projectile.get("owner_kind", "")) != "player"
			or bool(projectile.get("expired", false))
		):
			continue
		var slot_index := int(projectile.get("player_slot", -1))
		if slot_index >= 0 and slot_index < PLAYER_PROJECTILE_SLOT_COUNT:
			occupied[slot_index] = 1
		else:
			# Compatibility for hand-authored test/replay objects made before the
			# slot field existed: reserve an equivalent anonymous pool record.
			unslotted_count += 1
	for slot_index in range(PLAYER_PROJECTILE_SLOT_COUNT):
		if unslotted_count > 0 and occupied[slot_index] == 0:
			occupied[slot_index] = 1
			unslotted_count -= 1
	for slot_index in range(PLAYER_PROJECTILE_SLOT_COUNT):
		if occupied[slot_index] == 0:
			return slot_index
	return -1


func _player_projectiles_in_slot_order() -> Array:
	var ordered: Array = []
	for projectile_value in _projectiles:
		var projectile: Dictionary = projectile_value
		if String(projectile.get("owner_kind", "")) == "player":
			ordered.append(projectile)
	ordered.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_slot := int(left.get("player_slot", PLAYER_PROJECTILE_SLOT_COUNT))
		var right_slot := int(right.get("player_slot", PLAYER_PROJECTILE_SLOT_COUNT))
		if left_slot == right_slot:
			return int(left.get("id", 0)) < int(right.get("id", 0))
		return left_slot < right_slot
	)
	return ordered


func _update_enemies() -> void:
	if _is_retail_big_boss_level():
		_enemy_liveness_idle_updates = 0
		return
	_update_platform_oscillator()
	var enemies_frozen := _active_progression_has_freeze()
	var handler_claimed_activity := false
	for enemy_value in _enemies:
		var enemy: Dictionary = enemy_value
		if bool(enemy.dead):
			continue
		if bool(enemy.get("authored_lvd", false)):
			var authored_state := String(enemy.get("authored_state", ""))
			# Freeze wraps the complete retail handlers for the first-five active
			# states. Delayed activation bookkeeping is outside that gate.
			if (
				enemies_frozen
				and authored_state != "delayed"
				and int(enemy.get("behavior_state_id", 0)) in [
					1,
					2,
					3,
					4,
					5,
					6,
					10,
					# Both hurry-up handlers open on the same freeze gate.
					HURRY_UP_MOTHERSHIP_STATE_ID,
					HURRY_UP_RARE_STATE_ID,
				]
			):
				continue
			handler_claimed_activity = handler_claimed_activity or authored_state in [
				"delayed",
				"entry",
				"formation",
				"swd_attack",
				"return",
				"scoop_escape",
				"supplemental_large",
				"captured",
				"state_ten",
				"kamikaze",
				"hold",
				HURRY_UP_MOTHERSHIP_STATE,
				HURRY_UP_RARE_STATE,
			]
			_update_authored_enemy(enemy)
		else:
			handler_claimed_activity = true
			if int(enemy.y_fp) < int(enemy.target_y_fp):
				enemy.y_fp = min(
					int(enemy.target_y_fp),
					int(enemy.y_fp) + int(enemy.speed_fp)
				)
			else:
				_update_enemy_path(enemy)
				if _level_tick >= int(enemy.next_fire_tick):
					_fire_enemy_projectile(enemy)
					enemy.next_fire_tick = _level_tick + int(enemy.fire_interval_ticks)
	# The bounded remake-only ordinary-level deadlock guard must never mutate
	# authored counters while mode 13 or mode 16 owns the dispatcher.
	if _phase != PHASE_LEVEL:
		_enemy_liveness_idle_updates = 0
		return
	if enemies_frozen or _level_resolved:
		return
	if handler_claimed_activity:
		_enemy_liveness_idle_updates = 0
		return
	_enemy_liveness_idle_updates += 1
	if _enemy_liveness_idle_updates > LEVEL_LIVENESS_UPDATE_LIMIT:
		_level_killed_entities = maxi(
			0,
			_level_total_entities - _level_escaped_entities
		)
		_level_resolved = false
		_try_resolve_level_counter("liveness_guard")


func _refresh_enemy_watchdog_timestamp_from_render() -> void:
	if _is_retail_big_boss_level():
		return
	# FUN_00618560 runs after the gameplay dispatcher. It refreshes E114C0 only
	# when at least one qualifying alien's truncated top-left rectangle strictly
	# intersects the 800x600 viewport; state-8 captives never qualify.
	for enemy_value in _enemies:
		var enemy: Dictionary = enemy_value
		if bool(enemy.get("dead", false)):
			continue
		var state_id := int(enemy.get("behavior_state_id", 0))
		# The byte map at 0x0061ac3c gives states 9 and 12 their own qualifying
		# branches, so a hurry-up ship alone on the surface keeps the timestamp
		# fresh instead of letting the level force-resolve underneath it.
		if state_id not in [
			1,
			2,
			3,
			4,
			5,
			6,
			7,
			10,
			HURRY_UP_MOTHERSHIP_STATE_ID,
			HURRY_UP_RARE_STATE_ID,
		]:
			continue
		if (
			state_id == 1
			and (
				String(enemy.get("authored_state", "")) == "delayed"
				or int(enemy.get("activation_delay_sixths", 0)) > 0
			)
		):
			continue
		var width := int(enemy.get("width", 64 if state_id == 6 else 32))
		var height := int(enemy.get("height", 64 if state_id == 6 else 32))
		var left := _trunc_fp_to_int(
			_enemy_world_x_fp(enemy) - (width * FP_ONE >> 1)
		)
		var top := _trunc_fp_to_int(
			_enemy_world_y_fp(enemy) - (height * FP_ONE >> 1)
		)
		if (
			left < FIELD_WIDTH
			and top < FIELD_HEIGHT
			and left + width > 0
			and top + height > 0
		):
			_level_watchdog_start_tick = _tick
			return


func _update_platform_oscillator() -> void:
	_platform_x_fp += _scaled_simulation_delta(_platform_velocity_x_fp)
	_platform_velocity_x_fp += _scaled_simulation_delta(
		_platform_acceleration_x_fp
	)
	if _platform_x_fp > PLATFORM_MAX_X_FP:
		_platform_x_fp = PLATFORM_MAX_X_FP
		_platform_velocity_x_fp = -_platform_velocity_x_fp
	if _platform_x_fp < PLATFORM_MIN_X_FP:
		_platform_x_fp = PLATFORM_MIN_X_FP
		_platform_velocity_x_fp = -_platform_velocity_x_fp


func _update_authored_enemy(enemy: Dictionary) -> void:
	var state := String(enemy.authored_state)
	if state == "delayed":
		enemy.activation_delay_sixths = (
			int(enemy.activation_delay_sixths) - _simulation_scale_numerator()
		)
		enemy.activation_delay_ticks = maxi(
			0,
			(int(enemy.activation_delay_sixths) + SIMULATION_SCALE_DENOMINATOR - 1)
			/ SIMULATION_SCALE_DENOMINATOR
		)
		if int(enemy.activation_delay_sixths) <= 0:
			enemy.activation_delay_ticks = 0
			enemy.activation_delay_sixths = 0
			enemy.authored_state = "entry"
		return
	if state == "entry":
		enemy.x_fp = int(enemy.x_fp) + _scaled_simulation_delta(int(enemy.velocity_x_fp))
		enemy.y_fp = int(enemy.y_fp) + _scaled_simulation_delta(int(enemy.velocity_y_fp))
		enemy.velocity_x_fp = int(enemy.velocity_x_fp) + _scaled_simulation_delta(
			int(enemy.acceleration_x_fp)
		)
		enemy.velocity_y_fp = int(enemy.velocity_y_fp) + _scaled_simulation_delta(
			int(enemy.acceleration_y_fp)
		)
		enemy.authored_sprite_frame = _sprite_frames.enemy_direction_frame(
			int(enemy.velocity_x_fp),
			int(enemy.velocity_y_fp),
			bool(enemy.mirror_x)
		)
		_update_enemy_mask_rect(enemy)
		enemy.path_progress_sixths = (
			int(enemy.path_progress_sixths) + _simulation_scale_numerator()
		)
		enemy.path_progress_ticks = (
			int(enemy.path_progress_sixths) / SIMULATION_SCALE_DENOMINATOR
		)
		var path_points: Array = enemy.path_points
		var point: Dictionary = path_points[int(enemy.path_index)]
		if (
			int(enemy.path_progress_sixths)
			> int(point.duration_threshold_ticks) * SIMULATION_SCALE_DENOMINATOR
		):
			_advance_authored_path(enemy)
		if not bool(enemy.dead) and _authored_enemy_should_fire(enemy, false):
			_fire_enemy_projectile(enemy)
		return
	if state == "formation":
		_update_state_two(enemy)
		return
	if state == "swd_attack":
		if _authored_enemy_should_fire(enemy, true):
			_fire_enemy_projectile(enemy)
		_update_state_three(enemy)
		return
	if state == "return":
		if _authored_enemy_should_fire(enemy, true):
			_fire_enemy_projectile(enemy)
		_update_state_four(enemy)
		return
	if state == "scoop_escape":
		_update_state_five(enemy)
		return
	if state == "supplemental_large":
		_update_state_six(enemy)
		return
	if state == "captured":
		_update_captured_enemy(enemy)
		return
	if state == "state_ten":
		if _authored_enemy_should_fire(enemy, true):
			_fire_enemy_projectile(enemy)
		_update_state_ten(enemy)
		return
	if state == "kamikaze":
		_update_enemy_path(enemy)
		_update_enemy_mask_rect(enemy)
		if _authored_enemy_should_fire(enemy, false):
			_fire_enemy_projectile(enemy)
		return
	if state == "hold":
		if _authored_enemy_should_fire(enemy, false):
			_fire_enemy_projectile(enemy)
		return
	if state == HURRY_UP_MOTHERSHIP_STATE:
		_update_hurry_up_mothership(enemy)
		return
	if state == HURRY_UP_RARE_STATE:
		_update_hurry_up_rare_ship(enemy)
		return
	if state == MONEY_SUCKER_STATE:
		_update_money_sucker(enemy)
		return
	if state == GUARD_SHIP_STATE:
		_update_guard_ship(enemy)
		return


func _update_state_two(enemy: Dictionary) -> void:
	var delta_x := int(enemy.x_fp) - int(enemy.formation_target_x_fp)
	var delta_y := int(enemy.y_fp) - int(enemy.formation_target_y_fp)
	if delta_x != 0:
		var step_x := _scaled_simulation_delta(_trunc_div(delta_x, 20))
		if step_x == 0:
			enemy.x_fp = int(enemy.formation_target_x_fp)
		else:
			enemy.x_fp = int(enemy.x_fp) - step_x
	if delta_y != 0:
		var step_y := _scaled_simulation_delta(_trunc_div(delta_y, 20))
		if step_y == 0:
			enemy.y_fp = int(enemy.formation_target_y_fp)
		else:
			enemy.y_fp = int(enemy.y_fp) - step_y
	# Retail performs this test in 32-pixel top-left coordinates. These are
	# the exact center-coordinate equivalents of x > W+150 and x < -150.
	if (
		int(enemy.x_fp) > (FIELD_WIDTH + 166) * FP_ONE
		or int(enemy.x_fp) < -134 * FP_ONE
	):
		# Draw order is X, Y, then the state-4 downward velocity.
		enemy.x_fp = _random_retail_float_fp(0.0, float(FIELD_WIDTH)) + 16 * FP_ONE
		enemy.y_fp = 16 * FP_ONE - _random_retail_float_fp(50.0, 100.0)
		_enter_state_four(enemy, true, false)
		_update_enemy_mask_rect(enemy)
		return
	if (
		int(enemy.x_fp) == int(enemy.formation_target_x_fp)
		and int(enemy.y_fp) == int(enemy.formation_target_y_fp)
	):
		_advance_enemy_animation(enemy, false, true, false)
	_update_enemy_mask_rect(enemy)
	var timer_b := int(enemy.behavior_timer_b)
	if timer_b != 0 and _random_int(timer_b) == 1:
		_begin_swd_attack(enemy)
	# This late-level conversion is deliberately after the normal state-2
	# animation, Timer-B, selection, and follower draws.
	if _remaining_authored_entities() <= _tail_cutoff:
		var needs_platform_bake := String(enemy.authored_state) == "formation"
		_enter_state_four(enemy, true, needs_platform_bake)
		return


func _begin_swd_attack(enemy: Dictionary) -> void:
	if _swd_paths.is_empty():
		return
	var path_index := _random_int(_swd_paths.size())
	var followers: Array = []
	var leader_can_recruit := (
		not bool(enemy.get("leader_has_followers", false))
		and int(enemy.get("follower_leader_slot", -1)) < 0
	)
	var follower_roll := _random_int(100)
	if leader_can_recruit and follower_roll < _follower_recruitment_threshold():
		for follower_value in _enemies:
			var follower: Dictionary = follower_value
			if (
				follower == enemy
				or bool(follower.dead)
				or String(follower.get("authored_state", "")) != "formation"
				or bool(follower.get("leader_has_followers", false))
				or int(follower.get("follower_leader_slot", -1)) >= 0
			):
				continue
			var delta_y := int(follower.y_fp) - int(enemy.y_fp)
			var delta_x := int(follower.x_fp) - int(enemy.x_fp)
			if (
				delta_y > 16 * FP_ONE
				and delta_y < 60 * FP_ONE
				and delta_x > -60 * FP_ONE
				and delta_x < 60 * FP_ONE
			):
				followers.append(follower)
	# Retail always consumes a second recruitment pass draw. Its resource
	# condition can never match an ordinary enemy in levels 1-5.
	_random_int(10)
	_bake_platform_offset(enemy)
	_apply_swd_path(enemy, path_index)
	if not followers.is_empty():
		enemy.leader_has_followers = true
		enemy.saved_behavior_timer_a = int(enemy.behavior_timer_a)
		enemy.saved_health_fp = int(enemy.health_fp)
		enemy.behavior_timer_a = maxi(
			int(enemy.behavior_timer_a_floor),
			_trunc_div(int(enemy.behavior_timer_a), 2)
		)
		enemy.health_fp = int(enemy.health_fp) * 2
		for follower_value in followers:
			var follower: Dictionary = follower_value
			follower.follower_leader_slot = int(enemy.id)
			_bake_platform_offset(follower)
			_apply_swd_path(follower, path_index)


func _apply_swd_path(enemy: Dictionary, path_index: int) -> void:
	var path: Dictionary = _swd_paths[path_index]
	var points: Array = path.points
	enemy.authored_state = "swd_attack"
	enemy.behavior_state_id = 3
	enemy.swd_runtime_index = path_index
	enemy.swd_point_index = 0
	enemy.swd_progress_sixths = _simulation_scale_numerator()
	enemy.swd_return_selector = int(path.return_selector)
	enemy.velocity_x_fp = int(path.initial_velocity_x_fixed_256) * 256
	enemy.velocity_y_fp = int(path.initial_velocity_y_fixed_256) * 256
	if points.is_empty():
		_complete_swd_attack(enemy)
		return
	var point: Dictionary = points[0]
	enemy.acceleration_x_fp = int(point.acceleration_x_fixed_256) * 256
	enemy.acceleration_y_fp = int(point.acceleration_y_fixed_256) * 256
	_update_enemy_mask_rect(enemy)


func _update_state_three(enemy: Dictionary) -> void:
	enemy.x_fp = int(enemy.x_fp) + _scaled_simulation_delta(int(enemy.velocity_x_fp))
	enemy.y_fp = int(enemy.y_fp) + _scaled_simulation_delta(int(enemy.velocity_y_fp))
	enemy.velocity_x_fp = int(enemy.velocity_x_fp) + _scaled_simulation_delta(
		int(enemy.acceleration_x_fp)
	)
	enemy.velocity_y_fp = int(enemy.velocity_y_fp) + _scaled_simulation_delta(
		int(enemy.acceleration_y_fp)
	)
	enemy.swd_progress_sixths = (
		int(enemy.swd_progress_sixths) + _simulation_scale_numerator()
	)
	enemy.authored_sprite_frame = _sprite_frames.enemy_direction_frame(
		int(enemy.velocity_x_fp),
		int(enemy.velocity_y_fp),
		bool(enemy.mirror_x)
	)
	_update_enemy_mask_rect(enemy)
	var path: Dictionary = _swd_paths[int(enemy.swd_runtime_index)]
	var points: Array = path.points
	var point_index := int(enemy.swd_point_index)
	if point_index >= points.size():
		_complete_swd_attack(enemy)
		return
	var point: Dictionary = points[point_index]
	if (
		_trunc_div(int(enemy.swd_progress_sixths), SIMULATION_SCALE_DENOMINATOR)
		<= int(point.progress_threshold)
	):
		return
	var next_index := point_index + 1
	if next_index >= points.size():
		_complete_swd_attack(enemy)
		return
	var next_point: Dictionary = points[next_index]
	if int(next_point.progress_threshold) == 0:
		_complete_swd_attack(enemy)
		return
	enemy.swd_point_index = next_index
	enemy.swd_progress_sixths = _simulation_scale_numerator()
	enemy.acceleration_x_fp = int(next_point.acceleration_x_fixed_256) * 256
	enemy.acceleration_y_fp = int(next_point.acceleration_y_fixed_256) * 256
	match int(next_point.opcode):
		1:
			enemy.velocity_x_fp = 0
			enemy.velocity_y_fp = 0
			enemy.acceleration_x_fp = 0
			enemy.acceleration_y_fp = 0
		6:
			_escape_enemy(enemy)


func _complete_swd_attack(enemy: Dictionary) -> void:
	var selector := int(enemy.get("swd_return_selector", 1))
	if selector in [2, 3] and _remaining_authored_entities() <= _tail_cutoff:
		_enter_state_four(enemy, true, false)
		return
	_return_to_state_two(enemy)
	if selector == 2:
		enemy.selector2_flag = 1
	elif selector == 3:
		# This branch writes directly into state-2 numeric coordinate space.
		enemy.y_fp = -150 * FP_ONE
		_emit_event("swd_selector_three_return", {
			"entity_id": int(enemy.id),
			"x_fp": _enemy_world_x_fp(enemy),
			"y_fp": int(enemy.y_fp),
		})
	_update_enemy_mask_rect(enemy)


func _begin_state_four(enemy: Dictionary) -> void:
	# Compatibility entry used by focused tests and empty/corrupt paths.
	_enter_state_four(enemy, true, String(enemy.get("authored_state", "")) == "formation")


func _enter_state_four(
	enemy: Dictionary,
	draw_vertical_velocity: bool,
	bake_platform: bool
) -> void:
	if bake_platform:
		_bake_platform_offset(enemy)
	enemy.authored_state = "return"
	enemy.behavior_state_id = 4
	if draw_vertical_velocity:
		enemy.velocity_y_fp = _random_retail_float_fp(1.0, 3.0)
	enemy.group_drift_y_fp = 0
	_cleanup_swd_group(enemy)
	_update_enemy_mask_rect(enemy)


func _return_to_state_two(enemy: Dictionary) -> void:
	enemy.x_fp = int(enemy.x_fp) - _platform_x_fp
	enemy.y_fp = int(enemy.y_fp) - _platform_y_fp
	enemy.authored_state = "formation"
	enemy.behavior_state_id = 2
	_cleanup_swd_group(enemy)
	_update_enemy_mask_rect(enemy)


func _bake_platform_offset(enemy: Dictionary) -> void:
	enemy.x_fp = int(enemy.x_fp) + _platform_x_fp
	enemy.y_fp = int(enemy.y_fp) + _platform_y_fp


func _cleanup_swd_group(enemy: Dictionary) -> void:
	if bool(enemy.get("leader_has_followers", false)):
		enemy.behavior_timer_a = maxi(
			int(enemy.behavior_timer_a_floor),
			int(enemy.get("saved_behavior_timer_a", enemy.behavior_timer_a))
		)
		enemy.health_fp = int(enemy.get("saved_health_fp", enemy.health_fp))
	enemy.leader_has_followers = false
	enemy.follower_leader_slot = -1


func _remaining_authored_entities() -> int:
	var remaining := 0
	for candidate_value in _enemies:
		var candidate: Dictionary = candidate_value
		if bool(candidate.get("authored_lvd", false)) and not bool(candidate.dead):
			remaining += 1
	return remaining


func _follower_recruitment_threshold() -> int:
	match _difficulty_id:
		"easy":
			return 4
		"hard":
			return 10
		"ace":
			return 15
	return 6


func _state_four_turn(enemy: Dictionary, positive: bool) -> void:
	enemy.state_four_turn_countdown = 30 + _random_int(20)
	var magnitude := _random_retail_float_fp(0.01, 0.2)
	enemy.state_four_acceleration_x_fp = magnitude if positive else -magnitude


func _update_state_four(enemy: Dictionary) -> void:
	# Retail keeps state 4's roaming vector in dedicated enemy fields. Entry/SWD
	# velocity remains intact and must not leak into this state's first update.
	if not enemy.has("state_four_velocity_x_fp"):
		enemy.state_four_velocity_x_fp = 0
	if not enemy.has("state_four_acceleration_x_fp"):
		enemy.state_four_acceleration_x_fp = 0
	enemy.x_fp = int(enemy.x_fp) + _scaled_simulation_delta(
		int(enemy.state_four_velocity_x_fp)
	)
	# Strict, independent retail wrap tests converted from top-left to center.
	if int(enemy.x_fp) > (FIELD_WIDTH + 48) * FP_ONE:
		enemy.x_fp = -16 * FP_ONE
	if int(enemy.x_fp) < -16 * FP_ONE:
		enemy.x_fp = (FIELD_WIDTH + 48) * FP_ONE
	if (
		int(enemy.x_fp) > (FIELD_WIDTH - 116) * FP_ONE
		and int(enemy.state_four_acceleration_x_fp) > 0
	):
		_state_four_turn(enemy, false)
	if (
		int(enemy.x_fp) < 116 * FP_ONE
		and int(enemy.state_four_acceleration_x_fp) < 0
	):
		_state_four_turn(enemy, true)
	enemy.state_four_velocity_x_fp = (
		int(enemy.state_four_velocity_x_fp)
		+ _scaled_simulation_delta(int(enemy.state_four_acceleration_x_fp))
	)
	if (
		int(enemy.state_four_velocity_x_fp) > STATE_FOUR_MAX_HORIZONTAL_VELOCITY_FP
		and int(enemy.state_four_acceleration_x_fp) > 0
	):
		_state_four_turn(enemy, false)
	if (
		int(enemy.state_four_velocity_x_fp) < STATE_FOUR_MIN_HORIZONTAL_VELOCITY_FP
		and int(enemy.state_four_acceleration_x_fp) < 0
	):
		_state_four_turn(enemy, true)
	var old_countdown := int(enemy.get("state_four_turn_countdown", 1))
	enemy.state_four_turn_countdown = old_countdown - 1
	if old_countdown == 0:
		_state_four_turn(enemy, int(enemy.state_four_acceleration_x_fp) <= 0)
	enemy.y_fp = int(enemy.y_fp) + _scaled_simulation_delta(
		int(enemy.velocity_y_fp)
	)
	if int(enemy.y_fp) > (FIELD_HEIGHT + 31) * FP_ONE:
		enemy.y_fp = -34 * FP_ONE
	_update_state_four_animation(enemy)
	_update_enemy_mask_rect(enemy)


func _update_state_four_animation(enemy: Dictionary) -> void:
	enemy.animation_countdown_sixths = (
		int(enemy.animation_countdown_sixths) - _simulation_scale_numerator()
	)
	if int(enemy.animation_countdown_sixths) >= 0:
		return
	enemy.animation_countdown_sixths = 4 * SIMULATION_SCALE_DENOMINATOR
	var phase := int(enemy.authored_animation_frame)
	if int(enemy.animation_direction) == 0:
		phase += 1
		if phase >= 6:
			phase = 0
	else:
		phase -= 1
		if phase < 0:
			phase = 5
	enemy.authored_animation_frame = phase


func _update_state_five(enemy: Dictionary) -> void:
	enemy.x_fp = int(enemy.x_fp) + _scaled_simulation_delta(
		int(enemy.horizontal_velocity_fp)
	)
	enemy.y_fp = int(enemy.y_fp) + _scaled_simulation_delta(
		int(enemy.vertical_velocity_fp)
	)
	# Retail stores a 32px alien's top-left Y and removes it only below zero.
	# The center-coordinate equivalent is center_y < 16; equality survives.
	if int(enemy.y_fp) < 16 * FP_ONE:
		enemy.dead = true
		_emit_event("enemy_escaped", {
			"entity_id": int(enemy.id),
			"enemy_sheet": String(enemy.get("sprite", "alien001")),
			"cause": "scoop_overflow_departure",
			"x_fp": int(enemy.x_fp),
			"y_fp": int(enemy.y_fp),
		})
		return
	_update_enemy_mask_rect(enemy)


func _update_state_six(enemy: Dictionary) -> void:
	var direction_index := posmod(int(enemy.heading), 40)
	var velocity_x_fp := Fixed.multiply(
		Fixed.multiply(
			int(enemy.x_scale_fp),
			int(SUPPLEMENTAL_DIRECTION_X_FP[direction_index])
		),
		int(enemy.speed_fp)
	)
	var velocity_y_fp := Fixed.multiply(
		Fixed.multiply(
			int(enemy.y_scale_fp),
			int(SUPPLEMENTAL_DIRECTION_Y_FP[direction_index])
		),
		int(enemy.speed_fp)
	)
	enemy.x_fp = int(enemy.x_fp) + _scaled_simulation_delta(velocity_x_fp)
	enemy.y_fp = int(enemy.y_fp) + _scaled_simulation_delta(velocity_y_fp)
	if int(enemy.x_fp) > (FIELD_WIDTH + 152) * FP_ONE:
		enemy.x_fp = -88 * FP_ONE
	elif int(enemy.x_fp) < -88 * FP_ONE:
		enemy.x_fp = (FIELD_WIDTH + 142) * FP_ONE
	if int(enemy.y_fp) > (FIELD_HEIGHT + 152) * FP_ONE:
		enemy.y_fp = -88 * FP_ONE
	elif int(enemy.y_fp) < -88 * FP_ONE:
		enemy.y_fp = (FIELD_HEIGHT + 142) * FP_ONE
	# Retail fires between movement/wrap and the two steering timers.
	if not bool(enemy.dead) and _authored_enemy_should_fire(enemy, false):
		_fire_state_six_projectile(enemy)
	_update_state_six_steering(enemy)
	_advance_enemy_animation(enemy, false, true, true)
	_update_enemy_mask_rect(enemy)


func _update_state_six_steering(enemy: Dictionary) -> void:
	enemy.steering_countdown_fp = int(enemy.steering_countdown_fp) - (
		FP_ONE * _simulation_scale_numerator() / SIMULATION_SCALE_DENOMINATOR
	)
	if int(enemy.steering_countdown_fp) < 0:
		var heading := posmod(int(enemy.heading), 40)
		enemy.steering_mode = 2
		enemy.steering_countdown_fp = 30 * FP_ONE
		if int(enemy.x_fp) > (FIELD_WIDTH - 68) * FP_ONE and heading < 20:
			enemy.steering_mode = 1 if heading < 10 or heading > 29 else 3
			enemy.steering_countdown_fp = 40 * FP_ONE + _random_retail_float_fp(
				0.0,
				160.0
			)
		if int(enemy.x_fp) < 68 * FP_ONE and heading > 19:
			enemy.steering_mode = 3 if heading < 10 or heading > 29 else 1
			enemy.steering_countdown_fp = 40 * FP_ONE + _random_retail_float_fp(
				0.0,
				160.0
			)
		if int(enemy.y_fp) > 212 * FP_ONE and heading > 9 and heading < 30:
			enemy.steering_mode = 1 if heading < 20 else 3
			enemy.steering_countdown_fp = 40 * FP_ONE + _random_retail_float_fp(
				0.0,
				160.0
			)
		if int(enemy.y_fp) < 112 * FP_ONE and (heading < 10 or heading > 29):
			enemy.steering_mode = 3 if heading < 20 else 1
			enemy.steering_countdown_fp = 40 * FP_ONE + _random_retail_float_fp(
				0.0,
				160.0
			)
	var heading_step_underflow := false
	if bool(enemy.get("warp_malfunction", false)):
		enemy.heading_step_countdown_fp = int(
			enemy.get("heading_step_countdown_fp", 0)
		) - (FP_ONE * _simulation_scale_numerator() / SIMULATION_SCALE_DENOMINATOR)
		heading_step_underflow = int(enemy.heading_step_countdown_fp) < 0
		if heading_step_underflow:
			enemy.heading_step_countdown_fp = int(
				enemy.get("heading_step_reset_fp", 10 * FP_ONE)
			)
	else:
		enemy.heading_step_countdown_sixths = (
			int(enemy.heading_step_countdown_sixths) - _simulation_scale_numerator()
		)
		heading_step_underflow = int(enemy.heading_step_countdown_sixths) < 0
		if heading_step_underflow:
			enemy.heading_step_countdown_sixths = 10 * SIMULATION_SCALE_DENOMINATOR
	if heading_step_underflow:
		if int(enemy.steering_mode) == 3:
			enemy.heading = posmod(int(enemy.heading) + 1, 40)
		elif int(enemy.steering_mode) == 1:
			enemy.heading = posmod(int(enemy.heading) - 1, 40)


func _update_captured_enemy(enemy: Dictionary) -> void:
	var owner_seat := int(enemy.get("captured_owner_seat", -1))
	if owner_seat < 0 or owner_seat >= _players.size():
		enemy.dead = true
		return
	var player: Dictionary = _players[owner_seat]
	if not bool(player.active) or not bool(player.alive):
		var owner_progression := _progression_for_seat(owner_seat)
		if int(owner_progression.upgrades.get("alien_lock", 0)) == 0:
			_destroy_captured_enemy(enemy, "owner_lost")
		return
	var target_offset := -32 * FP_ONE if int(enemy.captured_side) == 0 else 40 * FP_ONE
	var offset := int(enemy.capture_offset_fp)
	var horizontal_settled := offset == target_offset
	if not horizontal_settled:
		offset += FP_ONE if offset < target_offset else -FP_ONE
		enemy.capture_offset_fp = offset
	var target_y_fp := int(player.y_fp) + 2 * FP_ONE
	var delta_y := int(enemy.y_fp) - target_y_fp
	var vertical_settled := absi(delta_y) <= FP_ONE
	if not vertical_settled:
		enemy.y_fp = int(enemy.y_fp) + (FP_ONE if delta_y < 0 else -FP_ONE)
	enemy.x_fp = int(player.x_fp) - 4 * FP_ONE + int(enemy.capture_offset_fp)
	if horizontal_settled and vertical_settled:
		enemy.captured_latched = true
	var progression := _progression_for_seat(owner_seat)
	if int(progression.get("mirror_ticks", 0)) > 0:
		# The original renderer consumes one independent seven-bit choice for
		# each visible state-8 wingman. Keep that draw authoritative so clients
		# neither duplicate the alien nor perturb the gameplay RNG differently.
		enemy.captured_render_mirrored = (_rng.next_u32() & 0x7f) < 64
	else:
		enemy.captured_render_mirrored = false
	_update_enemy_mask_rect(enemy)


func _captured_render_x_fp(enemy: Dictionary, mirrored: bool) -> int:
	var width := int(enemy.get("width", AUTHORED_ENEMY_SIZE))
	var left := _trunc_fp_to_int(
		_enemy_world_x_fp(enemy) - (width * FP_ONE >> 1)
	)
	if mirrored:
		left = FIELD_WIDTH - left - width
	return left * FP_ONE + (width * FP_ONE >> 1)


func _begin_state_ten(enemy: Dictionary) -> void:
	enemy.authored_state = "state_ten"
	enemy.behavior_state_id = 10
	enemy.vertical_velocity_fp = 0
	enemy.vertical_acceleration_fp = _random_retail_float_fp(0.2, 0.4)
	enemy.horizontal_velocity_fp = 0
	enemy.horizontal_acceleration_fp = _random_retail_float_fp(-0.1, 0.1)
	var flip_interval := 10 + _random_int(5)
	enemy.horizontal_flip_interval_sixths = (
		flip_interval * SIMULATION_SCALE_DENOMINATOR
	)
	enemy.horizontal_flip_countdown_sixths = int(
		enemy.horizontal_flip_interval_sixths
	)


func _update_state_ten(enemy: Dictionary) -> void:
	enemy.horizontal_flip_countdown_sixths = (
		int(enemy.horizontal_flip_countdown_sixths) - _simulation_scale_numerator()
	)
	if int(enemy.horizontal_flip_countdown_sixths) <= 0:
		enemy.horizontal_flip_countdown_sixths = int(
			enemy.horizontal_flip_interval_sixths
		)
		enemy.horizontal_acceleration_fp = -int(enemy.horizontal_acceleration_fp)
	enemy.x_fp = int(enemy.x_fp) + _scaled_simulation_delta(
		int(enemy.horizontal_velocity_fp)
	)
	enemy.horizontal_velocity_fp = int(
		enemy.horizontal_velocity_fp
	) + _scaled_simulation_delta(int(enemy.horizontal_acceleration_fp))
	enemy.y_fp = int(enemy.y_fp) - _scaled_simulation_delta(
		int(enemy.vertical_velocity_fp)
	)
	# Retail compares the 32-pixel top-left sprite bottom against viewport_top
	# minus 100. With center coordinates that is center_y + 16 < -100.
	if int(enemy.y_fp) + 16 * FP_ONE < -100 * FP_ONE:
		_escape_enemy(enemy)
		return
	enemy.vertical_velocity_fp = int(
		enemy.vertical_velocity_fp
	) + _scaled_simulation_delta(int(enemy.vertical_acceleration_fp))
	enemy.vertical_acceleration_fp = _trunc_div(
		int(enemy.vertical_acceleration_fp) * 120,
		120 + _simulation_scale_numerator()
	)
	_advance_enemy_animation(enemy, true, false, false)
	_update_enemy_mask_rect(enemy)


func _advance_enemy_animation(
	enemy: Dictionary,
	opposite_direction: bool,
	consult_metadata: bool,
	health_scaled_reset: bool
) -> void:
	enemy.animation_countdown_sixths = (
		int(enemy.animation_countdown_sixths) - _simulation_scale_numerator()
	)
	if int(enemy.animation_countdown_sixths) >= 0:
		return
	if health_scaled_reset:
		enemy.animation_countdown_sixths = maxi(
			1,
			_trunc_div(int(enemy.health_fp) * 5, FP_ONE)
		)
	else:
		enemy.animation_countdown_sixths = 4 * SIMULATION_SCALE_DENOMINATOR
	var phase := int(enemy.authored_animation_frame)
	var direction := int(enemy.animation_direction)
	var decrement := direction != 0 if opposite_direction else direction == 0
	var maximum := int(enemy.animation_max_phase)
	var bounce := consult_metadata and int(enemy.animation_metadata) != 0
	if decrement:
		phase -= 1
		if phase < 0:
			if bounce:
				phase = 1
				direction = 1
			else:
				phase = maximum
	else:
		phase += 1
		if phase > maximum:
			if bounce:
				phase = maximum
				direction = 0
			else:
				phase = 0
	enemy.authored_animation_frame = phase
	enemy.animation_direction = direction


func _advance_authored_path(enemy: Dictionary) -> void:
	var path_points: Array = enemy.path_points
	var next_index := int(enemy.path_index) + 1
	if next_index >= path_points.size():
		_finish_authored_entry(enemy)
		return
	enemy.path_index = next_index
	# LVD entry segments explicitly reset elapsed progress to float zero. SWD
	# segments use a distinct tick-scale reset and intentionally remain separate.
	enemy.path_progress_ticks = 0
	enemy.path_progress_sixths = 0
	var point: Dictionary = path_points[next_index]
	var acceleration_x_fp := _milli_to_fp(int(point.acceleration_x_milli))
	if bool(enemy.mirror_x):
		acceleration_x_fp = -acceleration_x_fp
	enemy.acceleration_x_fp = acceleration_x_fp
	enemy.acceleration_y_fp = _milli_to_fp(int(point.acceleration_y_milli))
	match int(point.opcode):
		0:
			return
		1:
			if int(point.duration_threshold_ticks) == 100:
				_finish_authored_entry(enemy)
			else:
				enemy.velocity_x_fp = 0
				enemy.velocity_y_fp = 0
				enemy.acceleration_x_fp = 0
				enemy.acceleration_y_fp = 0
				# Nonterminal opcode 1 is a timed zero-motion path segment, not
				# a new dispatcher state. Keeping state 1 active lets this point's
				# own strict progress threshold advance on N+1; switching to a
				# synthetic hold state strands later authored points forever.
				enemy.path_progress_ticks = 0
				enemy.path_progress_sixths = 0
		2:
			# Retail scans for active group-mode-6 records. The only ordinary
			# authored use is level 94, whose four groups are all mode 1, so the
			# bounded scan has no allocations, RNG, effects, sounds, or events.
			return
		6:
			if int(enemy.level_mode_id) == 2:
				_begin_state_ten(enemy)
			else:
				# Mode-3 bonus formations use opcode 6 as an authored escape.
				# Retail also clears this formation's group-total slot before the
				# ordinary deactivation counter is advanced.
				if int(enemy.level_mode_id) == 3:
					var group_id := int(enemy.get("group_id", -1))
					if group_id >= 0:
						_group_totals[group_id] = 0
				_escape_enemy(enemy)


func _finish_authored_entry(enemy: Dictionary) -> void:
	enemy.authored_state = "formation"
	enemy.behavior_state_id = 2
	_update_enemy_mask_rect(enemy)


func _update_enemy_path(enemy: Dictionary) -> void:
	var path := String(enemy.path)
	var wave_phase := (_level_tick + int(enemy.id) * 17) % 240
	var triangle_fp := _triangle_wave_fp(wave_phase, 240)
	match path:
		"sine_entry", "formation":
			enemy.x_fp = int(enemy.anchor_x_fp) + Fixed.multiply(triangle_fp, 40 * FP_ONE)
		"sweep_left":
			enemy.x_fp = int(enemy.x_fp) - _scaled_simulation_delta(int(enemy.speed_fp))
			if int(enemy.x_fp) < 24 * FP_ONE:
				enemy.x_fp = 776 * FP_ONE
		"sweep_right":
			enemy.x_fp = int(enemy.x_fp) + _scaled_simulation_delta(int(enemy.speed_fp))
			if int(enemy.x_fp) > 776 * FP_ONE:
				enemy.x_fp = 24 * FP_ONE
		"kamikaze":
			var target := _nearest_active_player(int(enemy.x_fp))
			if not target.is_empty():
				var direction := -1 if int(target.x_fp) < int(enemy.x_fp) else 1
				var delta := _scaled_simulation_delta(int(enemy.speed_fp))
				enemy.x_fp = int(enemy.x_fp) + direction * delta
				enemy.y_fp = int(enemy.y_fp) + delta
	enemy.x_fp = Fixed.clamp_value(int(enemy.x_fp), 16 * FP_ONE, 784 * FP_ONE)


func _milli_to_fp(value: int) -> int:
	var magnitude := absi(value) * FP_ONE
	var rounded: int = (magnitude + 500) / 1000
	return -rounded if value < 0 else rounded


func _simulation_scale_numerator() -> int:
	return int(_difficulty.simulation_scale_numerator)


# Endless campaign helpers. The rules are executable-backed (see
# docs/evidence/ENDLESS_PROGRESSION.md): content cycles with period 100, the
# mirror alternates per hundred, and a cumulative progression step fires at
# levels 101, 201, 301, ...
static func endless_steps_for_level(level_id: int) -> int:
	return maxi(0, (level_id - 1) / ENDLESS_STEP_LEVELS)


static func authored_level_id_for(level_id: int) -> int:
	return (level_id - 1) % ENDLESS_STEP_LEVELS + 1


static func endless_mirror_for_level(level_id: int) -> bool:
	return ((level_id / ENDLESS_STEP_LEVELS) & 1) == 1


func _level_data_for(level_id: int) -> Dictionary:
	if _mode == MODE_TIME_TRIAL:
		return _time_trial_levels_by_id.get(time_trial_level_id_for(level_id), {})
	return _levels_by_id.get(authored_level_id_for(level_id), {})


## Retail loads `timetrial_%02d.lvd` straight from the level counter and wraps
## back to file 1 after the fifteenth, so the counter is unbounded while the
## file selection is not.
static func time_trial_level_id_for(level_id: int) -> int:
	return posmod(level_id - 1, TIME_TRIAL_LEVEL_COUNT) + 1


func _update_target_step() -> int:
	# Retail global 0x008f2058: +2/+3/+3/+2 updates per second per hundred.
	match _difficulty_id:
		"easy":
			return 2
		"normal":
			return 3
		"hard":
			return 3
		"ace":
			return 2
	return 0


func _apply_endless_progression() -> void:
	# Recomputes the per-level difficulty state whenever a level begins. The
	# steps == 0 path restores the authored difficulty object untouched so the
	# authored campaign stays bit-identical to earlier versions.
	# Time Trial cycles its own fifteen files with no per-hundred difficulty
	# step, so the authored difficulty object stays untouched for the whole run.
	_endless_step_count = (
		0 if _mode == MODE_TIME_TRIAL else endless_steps_for_level(_level_id)
	)
	if _endless_step_count == 0:
		_difficulty = _base_difficulty
		return
	var steps := _endless_step_count
	var adjusted: Dictionary = _base_difficulty.duplicate()
	adjusted["timer_a_initial_adjustment"] = maxi(
		int(_base_difficulty.timer_a_initial_adjustment) - ENDLESS_TIMER_STEP * steps,
		ENDLESS_TIMER_FLOOR
	)
	adjusted["timer_b_initial_adjustment"] = maxi(
		int(_base_difficulty.timer_b_initial_adjustment) - ENDLESS_TIMER_STEP * steps,
		ENDLESS_TIMER_FLOOR
	)
	var projectile_speed_fp := int(_base_difficulty.alien_projectile_speed_fp)
	for _step in range(steps):
		projectile_speed_fp = (
			projectile_speed_fp
			* ENDLESS_PROJECTILE_STEP_NUMERATOR
			/ ENDLESS_PROJECTILE_STEP_DENOMINATOR
		)
	adjusted["alien_projectile_speed_fp"] = projectile_speed_fp
	_difficulty = adjusted


func _endless_simulation_scale_fp() -> int:
	# Retail raises the simulation scale source by 0.12 (float32) per hundred
	# and the per-player update target by 2/3/3/2 per hundred. Both effects are
	# linear in ticks-per-second times per-tick scale, so the deterministic
	# model folds them: (base + 3/25 * steps) * (60 + r * steps) / 60.
	var base_fp := (
		int(_difficulty.simulation_scale_numerator)
		* FP_ONE
		/ SIMULATION_SCALE_DENOMINATOR
	)
	if _endless_step_count == 0:
		return base_fp
	var steps := _endless_step_count
	var scale_fp := (
		base_fp
		+ FP_ONE * ENDLESS_SCALE_STEP_NUMERATOR / ENDLESS_SCALE_STEP_DENOMINATOR * steps
	)
	return (
		scale_fp
		* (ENDLESS_UPDATE_TARGET_BASE + _update_target_step() * steps)
		/ ENDLESS_UPDATE_TARGET_BASE
	)


func _simulation_scale_float() -> float:
	if _endless_step_count == 0:
		return (
			float(_simulation_scale_numerator())
			/ float(SIMULATION_SCALE_DENOMINATOR)
		)
	return float(_endless_simulation_scale_fp()) / float(FP_ONE)


func _scaled_simulation_delta(value: int) -> int:
	if _endless_step_count == 0:
		return value * _simulation_scale_numerator() / SIMULATION_SCALE_DENOMINATOR
	return value * _endless_simulation_scale_fp() / FP_ONE


func _simulation_milliseconds() -> int:
	return _tick * 1000 / TICKS_PER_SECOND


func _random_centered_velocity_fp(span: int) -> int:
	if span <= 0:
		return 0
	return _random_retail_float_fp(0.0, float(span)) - span * FP_ONE / 2


func _random_int(upper_exclusive: int) -> int:
	if upper_exclusive <= 0:
		return 0
	return _rng.next_range(upper_exclusive)


func _random_retail_float_fp(minimum: float, maximum: float) -> int:
	return roundi(_rng.next_float32(minimum, maximum) * FP_ONE)


func _trunc_div(numerator: int, denominator: int) -> int:
	if denominator <= 0:
		return 0
	return int(float(numerator) / float(denominator))


func _trunc_fp_to_int(value_fp: int) -> int:
	return _trunc_div(value_fp, FP_ONE)


func _authored_enemy_should_fire(
	enemy: Dictionary,
	use_proximity_adjustment: bool = false
) -> bool:
	if _active_progression_has_freeze():
		return false
	if (
		int(enemy.get("behavior_state_id", 1)) == 1
		and int(enemy.y_fp) <= -10 * FP_ONE
	):
		return false
	if int(enemy.level_mode_id) == 3:
		return false
	var timer_a := int(enemy.behavior_timer_a)
	if timer_a <= 0:
		return false
	if bool(enemy.get("warp_malfunction", false)):
		var tick_scale := Rng._float32(
			float(_simulation_scale_numerator()) / SIMULATION_SCALE_DENOMINATOR
		)
		return _rng.next_float32(0.0, float(timer_a)) < Rng._float32(
			tick_scale * 2.0
		)
	if use_proximity_adjustment:
		timer_a = _proximity_adjusted_timer_a(enemy, timer_a)
	return _fire_roll_passes(
		_rng.next_u32(),
		timer_a,
		_simulation_scale_numerator()
	)


func _proximity_adjusted_timer_a(enemy: Dictionary, timer_a: int) -> int:
	var enemy_world_x_fp := _enemy_world_x_fp(enemy)
	var target := _nearest_active_player(enemy_world_x_fp)
	if target.is_empty():
		return timer_a
	var shot_x := _trunc_fp_to_int(enemy_world_x_fp + 13 * FP_ONE)
	var player_x := _trunc_fp_to_int(int(target.x_fp))
	var distance := absi(player_x - shot_x)
	if distance >= 50 or (_rng.next_u32() & 0x7f) >= 10:
		return timer_a
	var quarter := _trunc_div(timer_a, 4)
	if distance < 10:
		return timer_a - 3 * quarter
	if distance < 30:
		return timer_a - 2 * quarter
	return timer_a - quarter


func _fire_roll_passes(random_u32: int, timer_a: int, scale_numerator: int) -> bool:
	return random_u32 * timer_a * 3 < 4294967296 * scale_numerator


func _initialize_common_projectile_slots() -> void:
	_common_projectile_slots.clear()
	for slot_index in range(COMMON_PROJECTILE_SLOT_COUNT):
		_common_projectile_slots.append({
			"active": false,
			"entity_id": 0,
			"animation_frame": _random_int(2),
			"animation_period_fp": FP_ONE,
			"animation_countdown_fp": FP_ONE,
		})


func _find_available_common_projectile_slot() -> int:
	for slot_index in range(_common_projectile_slots.size()):
		if not bool((_common_projectile_slots[slot_index] as Dictionary).active):
			return slot_index
	return -1


func _release_common_projectile_slot(projectile: Dictionary) -> void:
	var slot_index := int(projectile.get("common_slot", -1))
	if slot_index < 0 or slot_index >= _common_projectile_slots.size():
		return
	var slot: Dictionary = _common_projectile_slots[slot_index]
	if int(slot.get("entity_id", 0)) != int(projectile.get("id", 0)):
		return
	slot.active = false
	slot.entity_id = 0
	for field in [
		"reserved_projectile_type",
		"reserved_retail_left_fp",
		"reserved_retail_top_fp",
	]:
		slot.erase(field)


func _clear_projectiles() -> void:
	for projectile_value in _projectiles:
		var projectile := projectile_value as Dictionary
		_release_common_projectile_slot(projectile)
		if _is_rocket_missile(projectile):
			_release_rocket_target_reservation(projectile)
	_projectiles.clear()
	_ordinary_projectile_counter_adjustment_by_seat = [0, 0]


func _set_enemy_projectile_mask_rect(projectile: Dictionary) -> void:
	var projectile_type := int(projectile.get("enemy_projectile_type", 7))
	var source := Rect2i()
	if String(projectile.get("owner_kind", "")) == "boss":
		source = _retail_big_boss_projectile_source_rect(
			projectile_type,
			int(projectile.get("animation_frame", 0))
		)
	else:
		var source_x := 448 if projectile_type == 6 else 480
		source = Rect2i(
			source_x,
			(int(projectile.get("animation_frame", 0)) & 1) * 32,
			32,
			32
		)
	_set_mask_source_rect(projectile, source)
	projectile.source_rect = [
		source.position.x,
		source.position.y,
		source.size.x,
		source.size.y,
	]
	_stamp_projectile_presentation(projectile)


func _stamp_projectile_presentation(projectile: Dictionary) -> void:
	projectile.projectile_kind = _projectile_kind(projectile)
	projectile.sprite_sheet_id = _projectile_sprite_sheet_id(projectile)
	if not projectile.has("source_rect"):
		projectile.source_rect = _projectile_source_rect_values(projectile)


func _projectile_kind(projectile: Dictionary) -> String:
	var explicit_kind := String(projectile.get("projectile_kind", ""))
	if not explicit_kind.is_empty():
		return explicit_kind
	match String(projectile.get("owner_kind", "")):
		"player":
			return "player_weapon"
		"boss":
			return "boss_projectile"
	return "enemy_projectile"


func _projectile_sprite_sheet_id(projectile: Dictionary) -> String:
	var explicit_sheet := String(projectile.get("sprite_sheet_id", ""))
	if not explicit_sheet.is_empty():
		return explicit_sheet
	if String(projectile.get("owner_kind", "")) == "player":
		return "weapons_big"
	return String(projectile.get("enemy_sheet", projectile.get("mask_id", "")))


func _projectile_source_rect_values(projectile: Dictionary) -> Array:
	var explicit_source: Variant = projectile.get("source_rect", [])
	if explicit_source is Array and (explicit_source as Array).size() == 4:
		return (explicit_source as Array).duplicate()
	var width := int(projectile.get("mask_source_width", 0))
	var height := int(projectile.get("mask_source_height", 0))
	if width <= 0 or height <= 0:
		return [0, 0, 0, 0]
	return [
		int(projectile.get("mask_source_x", 0)),
		int(projectile.get("mask_source_y", 0)),
		width,
		height,
	]


func _retail_big_boss_projectile_source_rect(
	projectile_type: int,
	animation_frame: int
) -> Rect2i:
	var attack := _active_boss_attack_contract(projectile_type)
	var source_rects := attack.get("source_rects", []) as Array
	if source_rects.is_empty():
		return Rect2i()
	var aimed_fire := _boss_contract.get("aimed_fire", {}) as Dictionary
	if projectile_type != int(aimed_fire.get("projectile_type", 15)):
		var source := source_rects[posmod(animation_frame, source_rects.size())] as Array
		return Rect2i(int(source[0]), int(source[1]), int(source[2]), int(source[3]))
	var first_source := source_rects[0] as Array
	var projectile_size := int(first_source[2])
	return Rect2i(
		animation_frame * projectile_size,
		int(first_source[1]),
		projectile_size,
		int(first_source[3])
	)


func _allocate_retail_boss_common_projectile(request: Dictionary) -> Dictionary:
	var projectile_type := int(request.get("enemy_projectile_type", -1))
	var attack := _active_boss_attack_contract(projectile_type)
	var aimed_fire := _boss_contract.get("aimed_fire", {}) as Dictionary
	var aimed_projectile_type := int(aimed_fire.get("projectile_type", 15))
	if (
		String(request.get("owner_kind", "")) != "boss"
		or attack.is_empty()
		or typeof(request.get("retail_left", null)) not in [TYPE_INT, TYPE_FLOAT]
		or typeof(request.get("retail_top", null)) not in [TYPE_INT, TYPE_FLOAT]
		or (
			projectile_type == aimed_projectile_type
			and String(request.get("reservation_phase", ""))
			!= "active_and_top_left"
		)
	):
		return _reject_retail_boss_projectile_reservation(
			"retail boss projectile reservation violates its traced contract"
		)
	var slot_index := _find_available_common_projectile_slot()
	if slot_index < 0:
		return {
			"ok": true,
			"error": "",
			"allocated": false,
			"common_slot": -1,
			"projectile_id": 0,
		}
	var projectile_id := _allocate_entity_id()
	var slot := _common_projectile_slots[slot_index] as Dictionary
	slot.active = true
	slot.entity_id = projectile_id
	slot.reserved_projectile_type = projectile_type
	slot.reserved_retail_left_fp = roundi(float(request.retail_left) * FP_ONE)
	slot.reserved_retail_top_fp = roundi(float(request.retail_top) * FP_ONE)
	return {
		"ok": true,
		"error": "",
		"allocated": true,
		"common_slot": slot_index,
		"projectile_id": projectile_id,
		"retained_animation_frame": int(slot.get("animation_frame", 0)),
		"retained_animation_period": (
			float(int(slot.get("animation_period_fp", FP_ONE))) / FP_ONE
		),
		"retained_animation_countdown": (
			float(int(slot.get("animation_countdown_fp", FP_ONE))) / FP_ONE
		),
	}


func _reject_retail_boss_projectile_reservation(message: String) -> Dictionary:
	_block_boss_runtime(message)
	return {
		"ok": false,
		"error": message,
		"allocated": false,
		"common_slot": -1,
		"projectile_id": 0,
	}


func _reject_retail_boss_projectile_finalization(message: String) -> Dictionary:
	_block_boss_runtime(message)
	return {"ok": false, "error": message}


func _finalize_retail_boss_common_projectile(request: Dictionary) -> Dictionary:
	var slot_index := int(request.get("common_slot", -1))
	var projectile_id := int(request.get("projectile_id", 0))
	if slot_index < 0 or slot_index >= _common_projectile_slots.size():
		return _reject_retail_boss_projectile_finalization(
			"retail boss projectile finalizer has an invalid common slot"
		)
	var slot := _common_projectile_slots[slot_index] as Dictionary
	var projectile_type := int(request.get("enemy_projectile_type", -1))
	var attack := _active_boss_attack_contract(projectile_type)
	var allocation := _active_boss_projectile_allocation()
	var aimed_fire := _boss_contract.get("aimed_fire", {}) as Dictionary
	var aimed_projectile_type := int(aimed_fire.get("projectile_type", 15))
	var opcode_two := _boss_contract.get("opcode_2", {}) as Dictionary
	var opcode_two_projectile_type := int(opcode_two.get("projectile_type", 14))
	var size := attack.get("size", []) as Array
	var broadphase_inset := attack.get("broadphase_inset", []) as Array
	var broadphase := attack.get("broadphase", []) as Array
	var source_rects := attack.get("source_rects", []) as Array
	var center_offset := allocation.get("center_offset", []) as Array
	var retirement := allocation.get("retirement", {}) as Dictionary
	if (
		attack.is_empty()
		or size.size() != 2
		or broadphase_inset.size() != 2
		or broadphase.size() != 2
		or source_rects.is_empty()
		or center_offset.size() != 2
	):
		return _reject_retail_boss_projectile_finalization(
			"retail boss projectile contract is incomplete"
		)
	var projectile_width := int(size[0])
	var projectile_height := int(size[1])
	var expected_inset_x := int(broadphase_inset[0])
	var expected_inset_y := int(broadphase_inset[1])
	var expected_extent_x := int(broadphase[0])
	var expected_extent_y := int(broadphase[1])
	var expected_frame_max := source_rects.size() - 1
	var projectile_sheet := String(allocation.get("enemy_sheet_id", ""))
	var mask_id := String(allocation.get("mask_id", ""))
	var resource_slot_id := int(allocation.get("resource_slot_id", 0))
	var surface_height := int(retirement.get("default_surface_height", 0))
	if (
		not bool(slot.get("active", false))
		or int(slot.get("entity_id", 0)) != projectile_id
		or int(slot.get("reserved_projectile_type", -1)) != projectile_type
		or not bool(request.get("allocated", false))
		or String(request.get("owner_kind", "")) != "boss"
		or projectile_type not in [opcode_two_projectile_type, aimed_projectile_type]
		or int(request.get("width", 0)) != projectile_width
		or int(request.get("height", 0)) != projectile_height
		or int(request.get("resource_slot_id", 0))
		!= resource_slot_id
		or String(request.get("enemy_sheet_id", ""))
		!= projectile_sheet
		or String(request.get("mask_id", ""))
		!= mask_id
		or not bool(request.get("velocity_is_tick_scaled", false))
		or int(request.get("broadphase_inset_x", -1)) != expected_inset_x
		or int(request.get("broadphase_inset_y", -1)) != expected_inset_y
		or int(request.get("broadphase_width", 0)) != expected_extent_x
		or int(request.get("broadphase_height", 0)) != expected_extent_y
		or int(request.get("animation_frame_max", -1)) != expected_frame_max
		or bool(request.get("animation_source_unclamped", false))
		!= (projectile_type == aimed_projectile_type)
		or int(request.get("retire_top_left_y_strictly_above", -1))
		!= surface_height
		or int(request.get("damage_fp", 0)) != FP_ONE
		or String(request.get("damage_policy", "")) != "one_armour_step"
		or not bool(request.get("consume_on_player_hit", false))
	):
		return _reject_retail_boss_projectile_finalization(
			"retail boss projectile finalizer violates its traced contract"
		)
	for numeric_field in [
		"retail_left",
		"retail_top",
		"top_left_x",
		"top_left_y",
		"x",
		"y",
		"velocity_x",
		"velocity_y",
		"animation_period",
		"animation_countdown",
	]:
		if typeof(request.get(numeric_field, null)) not in [TYPE_INT, TYPE_FLOAT]:
			return _reject_retail_boss_projectile_finalization(
				"retail boss projectile finalizer omitted numeric %s" % numeric_field
			)
	var retail_left_fp := roundi(float(request.top_left_x) * FP_ONE)
	var retail_top_fp := roundi(float(request.top_left_y) * FP_ONE)
	var expected_center_x_fp := roundi(
		Rng._float32(
			float(request.top_left_x)
			+ float(center_offset[0])
		) * FP_ONE
	)
	var expected_center_y_fp := roundi(
		Rng._float32(
			float(request.top_left_y)
			+ float(center_offset[1])
		) * FP_ONE
	)
	if (
		retail_left_fp != int(slot.get("reserved_retail_left_fp", 0))
		or retail_top_fp != int(slot.get("reserved_retail_top_fp", 0))
		or roundi(float(request.retail_left) * FP_ONE) != retail_left_fp
		or roundi(float(request.retail_top) * FP_ONE) != retail_top_fp
		or roundi(float(request.x) * FP_ONE) != expected_center_x_fp
		or roundi(float(request.y) * FP_ONE) != expected_center_y_fp
	):
		return _reject_retail_boss_projectile_finalization(
			"retail boss projectile coordinates changed after reservation"
		)
	var animation_frame := int(request.get("animation_frame", -1))
	var animation_period_fp := roundi(float(request.animation_period) * FP_ONE)
	var animation_countdown_fp := roundi(float(request.animation_countdown) * FP_ONE)
	if projectile_type == opcode_two_projectile_type:
		var opcode_two_animation := opcode_two.get("animation", {}) as Dictionary
		var period_rng := opcode_two_animation.get("period_rng", []) as Array
		var countdown_rng := opcode_two_animation.get("countdown_rng", []) as Array
		if period_rng.size() != 2 or countdown_rng.size() != 2:
			return _reject_retail_boss_projectile_finalization(
				"type-14 projectile animation contract is incomplete"
			)
		if (
			animation_frame != 0
			or animation_period_fp < int(period_rng[0]) * FP_ONE
			or animation_period_fp >= int(period_rng[1]) * FP_ONE
			or animation_countdown_fp < int(countdown_rng[0]) * FP_ONE
			or animation_countdown_fp >= int(countdown_rng[1]) * FP_ONE
		):
			return _reject_retail_boss_projectile_finalization(
				"type-14 projectile animation initialization is invalid"
			)
	else:
		if (
			animation_frame != int(slot.get("animation_frame", 0))
			or animation_period_fp
			!= int(slot.get("animation_period_fp", FP_ONE))
			or animation_countdown_fp
			!= int(slot.get("animation_countdown_fp", FP_ONE))
		):
			return _reject_retail_boss_projectile_finalization(
				"type-15 projectile did not retain its common-slot animation"
			)
	var expected_source := _retail_big_boss_projectile_source_rect(
		projectile_type,
		animation_frame
	)
	var expected_source_values := [
		expected_source.position.x,
		expected_source.position.y,
		expected_source.size.x,
		expected_source.size.y,
	]
	if not request.get("source_rect", []) is Array or request.source_rect != expected_source_values:
		return _reject_retail_boss_projectile_finalization(
			"retail boss projectile source frame is invalid"
		)
	var projectile := {
		"id": projectile_id,
		"owner_kind": "boss",
		"owner_id": -1,
		"enemy_sheet": projectile_sheet,
		"common_slot": slot_index,
		"spawn_tick": _tick,
		"retail_left_fp": retail_left_fp,
		"retail_top_fp": retail_top_fp,
		"x_fp": expected_center_x_fp,
		"y_fp": expected_center_y_fp,
		"velocity_x_fp": roundi(float(request.velocity_x) * FP_ONE),
		"velocity_y_fp": roundi(float(request.velocity_y) * FP_ONE),
		"velocity_is_tick_scaled": true,
		"width": projectile_width,
		"height": projectile_height,
		"resource_slot_id": resource_slot_id,
		"broadphase_inset_x": expected_inset_x,
		"broadphase_inset_y": expected_inset_y,
		"broadphase_width": int(request.broadphase_width),
		"broadphase_height": int(request.broadphase_height),
		"damage_fp": FP_ONE,
		"damage_policy": "one_armour_step",
		"consume_on_player_hit": true,
		"prototype_id": -1,
		"enemy_projectile_type": projectile_type,
		"animation_frame": animation_frame,
		"animation_frame_max": expected_frame_max,
		"animation_period_fp": animation_period_fp,
		"animation_countdown_fp": animation_countdown_fp,
		"animation_source_unclamped": bool(
			request.get("animation_source_unclamped", false)
		),
		"retire_top_left_y_strictly_above": (
			surface_height
		),
		"expired": false,
		"mask_id": mask_id,
		"mask_required": true,
	}
	if request.has("source_record_index"):
		projectile.source_record_index = int(request.source_record_index)
	slot.animation_frame = animation_frame
	slot.animation_period_fp = animation_period_fp
	slot.animation_countdown_fp = animation_countdown_fp
	for field in [
		"reserved_projectile_type",
		"reserved_retail_left_fp",
		"reserved_retail_top_fp",
	]:
		slot.erase(field)
	_set_enemy_projectile_mask_rect(projectile)
	_projectiles.append(projectile)
	return {
		"ok": true,
		"error": "",
		"common_slot": slot_index,
		"projectile_id": projectile_id,
	}


func _dispatch_retail_big_boss_effect(
	call_name: String,
	payload: Dictionary,
	rng_source: Variant
) -> Dictionary:
	var result: Dictionary = _retail_big_boss_effects.dispatch_retail_effect(
		call_name,
		payload,
		rng_source
	)
	if not bool(result.get("ok", false)):
		_block_boss_runtime(String(result.get(
			"error",
			_retail_big_boss_effects.get_last_error()
		)))
	return result


func _fire_enemy_projectile(enemy: Dictionary) -> void:
	var slot_index := _find_available_common_projectile_slot()
	if slot_index < 0:
		return
	var speed_fp := _ordinary_enemy_projectile_vertical_speed_fp(enemy)
	var lateral_velocity_fp := _ordinary_enemy_projectile_lateral_velocity_fp(
		enemy
	)
	var projectile_id := _allocate_entity_id()
	var slot: Dictionary = _common_projectile_slots[slot_index]
	slot.active = true
	slot.entity_id = projectile_id
	slot.animation_countdown_fp = FP_ONE
	var projectile := {
		"id": projectile_id,
		"owner_kind": "enemy",
		"owner_id": int(enemy.id),
		"enemy_sheet": String(enemy.get("sprite", "alien001")),
		"common_slot": slot_index,
		"spawn_tick": _tick,
		"x_fp": _enemy_world_x_fp(enemy) + 13 * FP_ONE,
		"y_fp": _enemy_world_y_fp(enemy) + 16 * FP_ONE,
		"velocity_x_fp": lateral_velocity_fp,
		"velocity_y_fp": speed_fp,
		"width": 32,
		"height": 32,
		"damage_fp": FP_ONE,
		"prototype_id": -1,
		"enemy_projectile_type": 7,
		"animation_frame": int(slot.animation_frame),
		"animation_countdown_fp": FP_ONE,
		"expired": false,
		"mask_id": String(enemy.get("sprite", "alien001")),
		"mask_required": true,
	}
	_set_enemy_projectile_mask_rect(projectile)
	_projectiles.append(projectile)
	var fired_event := {
		"entity_id": int(enemy.id),
		"projectile_id": projectile_id,
		"enemy_sheet": String(enemy.get("sprite", "alien001")),
		"x_fp": int(projectile.x_fp),
		"y_fp": int(projectile.y_fp),
	}
	if String(enemy.get("sprite", "")) == "alien_3":
		fired_event.sfx_key = "alienshoot10"
	_emit_event("enemy_fired", fired_event)


func _ordinary_enemy_projectile_lateral_velocity_fp(enemy: Dictionary) -> int:
	if int(enemy.get("level_mode_id", 0)) != 6:
		return 0
	var level := _level_data_for(_level_id) as Dictionary
	var runtime := level.get("level_mode_runtime", {}) as Dictionary
	var aim := runtime.get("ordinary_projectile_aim", {}) as Dictionary
	if not bool(aim.get("enabled", false)):
		return 0
	var magnitude_rng_fp := aim.get(
		"horizontal_speed_magnitude_rng_fp",
		[0, 98304]
	) as Array
	var minimum := float(int(magnitude_rng_fp[0])) / FP_ONE
	var maximum := float(int(magnitude_rng_fp[1])) / FP_ONE
	var enemy_x_fp := _enemy_world_x_fp(enemy)
	var target := _mode_six_projectile_target(enemy_x_fp)
	# The pinned routine compares the fighter and alien records' retail top-left
	# X values. Runtime entities store centers, so preserve that asymmetric
	# 40px-vs-32px conversion instead of comparing centers directly.
	var enemy_left_fp := enemy_x_fp - (AUTHORED_ENEMY_SIZE * FP_ONE >> 1)
	var target_left_fp := (
		int(target.get("x_fp", enemy_x_fp)) - (PLAYER_WIDTH * FP_ONE >> 1)
	)
	var target_is_left := (
		not target.is_empty()
		and target_left_fp < enemy_left_fp
	)
	var component := (
		_rng.next_float32(-maximum, -minimum)
		if target_is_left
		else _rng.next_float32(minimum, maximum)
	)
	var tick_scale := Rng._float32(
		_simulation_scale_float()
	)
	return roundi(Rng._float32(component * tick_scale) * FP_ONE)


func _mode_six_projectile_target(enemy_x_fp: int) -> Dictionary:
	if _players.is_empty():
		return {}
	match _mode:
		MODE_SOLO:
			# Retail solo reads the current active owner's record directly,
			# including during its ordinary death/respawn lifecycle.
			return _players[clampi(_turn_seat, 0, _players.size() - 1)] as Dictionary
		MODE_COOP:
			# Simultaneous co-op is remake-owned; preserve its established nearest
			# active/alive target selection without changing retail seat semantics.
			return _nearest_active_player(enemy_x_fp)
	return {}


func _ordinary_enemy_projectile_vertical_speed_fp(enemy: Dictionary) -> int:
	var speed_fp := int(enemy.projectile_speed_fp)
	if int(enemy.get("level_mode_id", 0)) != 6:
		return speed_fp
	var level := _level_data_for(_level_id) as Dictionary
	var runtime := level.get("level_mode_runtime", {}) as Dictionary
	var speed_contract := runtime.get(
		"ordinary_projectile_vertical_speed",
		{}
	) as Dictionary
	var threshold := int(speed_contract.get(
		"accelerated_when_level_strictly_above",
		500
	))
	var multiplier_fp := int(speed_contract.get(
		(
			"accelerated_multiplier_fp"
			if _level_id > threshold
			else "base_multiplier_fp"
		),
		81920 if _level_id > threshold else FP_ONE
	))
	return roundi(float(speed_fp) * float(multiplier_fp) / FP_ONE)


func _state_six_aimed_shot_travel_multiplier() -> float:
	match _difficulty_id:
		"easy":
			return 3.0
		"hard":
			return 2.0
		"ace":
			return 1.8
	return 2.2


func _fire_state_six_projectile(enemy: Dictionary) -> void:
	# Retail resolves all aim randomness before it scans the 100 common slots,
	# so a full pool still consumes travel, X-jitter, and Y-jitter draws.
	var minimum_travel := 30.0 if bool(enemy.get("warp_malfunction", false)) else 45.0
	var maximum_travel := 60.0 if bool(enemy.get("warp_malfunction", false)) else 55.0
	var travel := Rng._float32(
		_rng.next_float32(minimum_travel, maximum_travel)
		* Rng._float32(_state_six_aimed_shot_travel_multiplier())
	)
	if travel == 0.0:
		travel = 1.0
	var target: Dictionary = {}
	if bool(enemy.get("warp_malfunction", false)) and _mode == MODE_COOP:
		# The target-seat draw precedes both X/Y aim jitter draws.
		var chosen_seat := _random_int(2)
		if (
			chosen_seat >= 0
			and chosen_seat < _players.size()
			and bool((_players[chosen_seat] as Dictionary).active)
			and bool((_players[chosen_seat] as Dictionary).alive)
		):
			target = _players[chosen_seat]
	if target.is_empty():
		target = _nearest_active_player(int(enemy.x_fp))
	if target.is_empty():
		target = _players[0]
	var target_x := Rng._float32(
		Rng._float32(float(int(target.x_fp)) / FP_ONE - 20.0)
		- _rng.next_float32(-40.0, 40.0)
	)
	var target_y := Rng._float32(
		Rng._float32(float(int(target.y_fp)) / FP_ONE - 14.0)
		- _rng.next_float32(-40.0, 40.0)
	)
	var enemy_center_x := Rng._float32(float(int(enemy.x_fp)) / FP_ONE)
	var enemy_center_y := Rng._float32(float(int(enemy.y_fp)) / FP_ONE)
	var enemy_left := Rng._float32(enemy_center_x - 32.0)
	var enemy_top := Rng._float32(enemy_center_y - 32.0)
	var velocity_x := Rng._float32((target_x - enemy_left) / travel)
	var velocity_y := Rng._float32((target_y - enemy_top) / travel)
	var tick_scale := Rng._float32(
		_simulation_scale_float()
	)
	var velocity_x_fp := roundi(Rng._float32(velocity_x * tick_scale) * FP_ONE)
	var velocity_y_fp := roundi(Rng._float32(velocity_y * tick_scale) * FP_ONE)
	var spawn_center_x_fp := roundi(Rng._float32(
		Rng._float32(enemy_left + 32.0) + 16.0
	) * FP_ONE)
	var spawn_center_y_fp := roundi(Rng._float32(
		Rng._float32(enemy_top + 25.0) + 16.0
	) * FP_ONE)
	var slot_index := _find_available_common_projectile_slot()
	if slot_index < 0:
		return
	var projectile_id := _allocate_entity_id()
	var slot: Dictionary = _common_projectile_slots[slot_index]
	slot.active = true
	slot.entity_id = projectile_id
	slot.animation_countdown_fp = FP_ONE
	var projectile := {
		"id": projectile_id,
		"owner_kind": "enemy",
		"owner_id": int(enemy.id),
		"enemy_sheet": String(enemy.get("sprite", "alien001")),
		"common_slot": slot_index,
		"spawn_tick": _tick,
		# Stored retail top-left is (enemy_left+32, enemy_top+25).
		# Add the 16px projectile half-size for this center contract.
		"x_fp": spawn_center_x_fp,
		"y_fp": spawn_center_y_fp,
		"velocity_x_fp": velocity_x_fp,
		"velocity_y_fp": velocity_y_fp,
		"width": 32,
		"height": 32,
		"damage_fp": FP_ONE,
		"prototype_id": -1,
		"enemy_projectile_type": 6,
		"animation_frame": int(slot.animation_frame),
		"animation_countdown_fp": FP_ONE,
		"expired": false,
		"mask_id": String(enemy.get("sprite", "alien001")),
		"mask_required": true,
	}
	_set_enemy_projectile_mask_rect(projectile)
	_projectiles.append(projectile)
	_emit_event("enemy_fired", {
		"entity_id": int(enemy.id),
		"projectile_id": projectile_id,
		"enemy_sheet": String(enemy.get("sprite", "alien001")),
		"enemy_projectile_type": 6,
		"x_fp": int(projectile.x_fp),
		"y_fp": int(projectile.y_fp),
	})


func _update_player_projectiles() -> void:
	# FUN_0061fff0 handles the fixed player-shot array in ascending slot order.
	for projectile_value in _player_projectiles_in_slot_order():
		var projectile: Dictionary = projectile_value
		if bool(projectile.expired) or String(projectile.owner_kind) != "player":
			continue
		if _is_rocket_missile(projectile):
			_update_rocket_missile(projectile)
			continue
		if _tick > int(projectile.spawn_tick):
			_advance_player_projectile_frame(projectile)
		if bool(projectile.expired):
			continue
		projectile.x_fp = int(projectile.x_fp) + _scaled_simulation_delta(
			int(projectile.velocity_x_fp)
		)
		projectile.y_fp = int(projectile.y_fp) + _scaled_simulation_delta(
			int(projectile.velocity_y_fp)
		)
		if _player_projectile_out_of_bounds(projectile):
			projectile.expired = true


func _update_rocket_missiles() -> void:
	for projectile_value in _player_projectiles_in_slot_order():
		var projectile := projectile_value as Dictionary
		if bool(projectile.get("expired", false)) or not _is_rocket_missile(projectile):
			continue
		_update_rocket_missile(projectile)


func _update_rocket_missile(projectile: Dictionary) -> void:
	var tick_delta_fp := _scaled_simulation_delta(FP_ONE)
	projectile.lifetime_fp = int(
		projectile.get("lifetime_fp", ROCKET_LIFETIME_FP)
	) - tick_delta_fp
	if int(projectile.lifetime_fp) <= 0:
		_expire_rocket_missile(projectile)
		return

	# Retail checks the old animation countdown, then performs the decrement.
	# Solo (retail mode zero) leaves row zero unchanged.
	if _mode != MODE_SOLO:
		var animation_countdown := int(projectile.get(
			"animation_countdown_fp",
			FP_ONE
		))
		projectile.animation_countdown_fp = animation_countdown - tick_delta_fp
		if animation_countdown == 0:
			projectile.animation_row = posmod(
				int(projectile.get("animation_row", 0)) + 1,
				ROCKET_ANIMATION_ROWS
			)
			projectile.animation_countdown_fp = int(projectile.get(
				"animation_period_fp",
				4 * FP_ONE
			))

	var steering_countdown := int(projectile.get("steering_countdown_fp", FP_ONE))
	projectile.steering_countdown_fp = steering_countdown - tick_delta_fp
	if int(projectile.steering_countdown_fp) <= 0:
		projectile.steering_countdown_fp = int(projectile.get(
			"steering_period_fp",
			FP_ONE
		))
		var target := _rocket_target_for_update(projectile)
		if not target.is_empty():
			_turn_rocket_toward_target(projectile, target)

	var heading_index := clampi(
		int(projectile.get("heading", 1)),
		1,
		ROCKET_HEADING_COUNT
	) - 1
	projectile.velocity_x_fp = int(ROCKET_HEADING_X_Q16[heading_index]) * 10
	projectile.velocity_y_fp = int(ROCKET_HEADING_Y_Q16[heading_index]) * 10
	projectile.x_fp = int(projectile.x_fp) + _trunc_div(
		int(projectile.velocity_x_fp) * _simulation_scale_numerator(),
		SIMULATION_SCALE_DENOMINATOR
	)
	projectile.y_fp = int(projectile.y_fp) + _trunc_div(
		int(projectile.velocity_y_fp) * _simulation_scale_numerator(),
		SIMULATION_SCALE_DENOMINATOR
	)
	_set_rocket_source_rect(projectile)


func _rocket_target_for_update(projectile: Dictionary) -> Dictionary:
	var target_kind := String(projectile.get("target_kind", "enemy"))
	if target_kind == "boss":
		if _boss_entered and not _boss_runtime_blocked:
			var boss_snapshot := _retail_big_boss.snapshot()
			if bool(boss_snapshot.get("active", false)):
				return {
					"target_kind": "boss",
					"x_fp": roundi(float(boss_snapshot.get("x", 0.0)) * FP_ONE),
					"y_fp": roundi(float(boss_snapshot.get("y", 0.0)) * FP_ONE),
				}
	else:
		var stored_target_id := int(projectile.get("target_entity_id", 0))
		for enemy_value in _enemies:
			var enemy := enemy_value as Dictionary
			if (
				int(enemy.get("id", 0)) == stored_target_id
				and bool(enemy.get("active", true))
				and not bool(enemy.get("dead", false))
			):
				# An active stored record is never replaced. Retail revalidates its
				# targetability/state at the steering boundary and simply skips this
				# turn if it no longer qualifies.
				var targetability := float(enemy.get(
					"targetability_scalar",
					float(int(enemy.get("targetability_fp", FP_ONE))) / float(FP_ONE)
				))
				if (
					is_nan(targetability)
					or targetability > 1.0
					or int(enemy.get("behavior_state_id", 0)) in [5, 8]
				):
					return {}
				return {
					"target_kind": "enemy",
					"enemy": enemy,
					"x_fp": _enemy_world_x_fp(enemy) - int(enemy.get("width", 32)) * FP_ONE / 2,
					"y_fp": _enemy_world_y_fp(enemy) - int(enemy.get("height", 32)) * FP_ONE / 2,
				}
	# If the stored target disappeared, retail steers toward the first currently
	# eligible record without reserving it or overwriting the stored target ID.
	for enemy_value in _enemies:
		var replacement := enemy_value as Dictionary
		if not _rocket_enemy_is_eligible(replacement):
			continue
		return {
			"target_kind": "enemy",
			"enemy": replacement,
			"x_fp": _enemy_world_x_fp(replacement) - int(replacement.get("width", 32)) * FP_ONE / 2,
			"y_fp": _enemy_world_y_fp(replacement) - int(replacement.get("height", 32)) * FP_ONE / 2,
		}
	if _is_retail_big_boss_level() and _boss_entered and not _boss_runtime_blocked:
		var replacement_boss := _retail_big_boss.snapshot()
		if bool(replacement_boss.get("active", false)):
			return {
				"target_kind": "boss",
				"x_fp": roundi(float(replacement_boss.get("x", 0.0)) * FP_ONE),
				"y_fp": roundi(float(replacement_boss.get("y", 0.0)) * FP_ONE),
			}
	return {}


func _turn_rocket_toward_target(projectile: Dictionary, target: Dictionary) -> void:
	var rocket_left_fp := int(projectile.x_fp) - ROCKET_FRAME_SIZE * FP_ONE / 2
	var rocket_top_fp := int(projectile.y_fp) - ROCKET_FRAME_SIZE * FP_ONE / 2
	var target_x_fp := int(target.get("x_fp", rocket_left_fp))
	var target_y_fp := int(target.get("y_fp", rocket_top_fp))
	var target_right := target_x_fp >= rocket_left_fp
	var target_below := target_y_fp >= rocket_top_fp
	var desired_heading := 5
	if target_right and target_below:
		desired_heading = 13
	elif not target_right and target_below:
		desired_heading = 21
	elif not target_right and not target_below:
		desired_heading = 29
	var heading := clampi(
		int(projectile.get("heading", 1)),
		1,
		ROCKET_HEADING_COUNT
	)
	if heading == desired_heading:
		return
	var increment_distance := posmod(desired_heading - heading, ROCKET_HEADING_COUNT)
	var decrement_distance := posmod(heading - desired_heading, ROCKET_HEADING_COUNT)
	if increment_distance == decrement_distance:
		heading += -1 if _random_int(100) < 50 else 1
	elif increment_distance < decrement_distance:
		heading += 1
	else:
		heading -= 1
	projectile.heading = posmod(heading - 1, ROCKET_HEADING_COUNT) + 1


func _set_rocket_source_rect(projectile: Dictionary) -> void:
	var heading := clampi(
		int(projectile.get("heading", 1)),
		1,
		ROCKET_HEADING_COUNT
	)
	var animation_row := clampi(
		int(projectile.get("animation_row", 0)),
		0,
		ROCKET_ANIMATION_ROWS - 1
	)
	var source_rect := Rect2i(
		(heading - 1) * ROCKET_FRAME_SIZE,
		animation_row * ROCKET_FRAME_SIZE,
		ROCKET_FRAME_SIZE,
		ROCKET_FRAME_SIZE
	)
	_set_mask_source_rect(projectile, source_rect)
	projectile.source_rect = [
		source_rect.position.x,
		source_rect.position.y,
		source_rect.size.x,
		source_rect.size.y,
	]


func _expire_rocket_missile(projectile: Dictionary) -> void:
	_release_rocket_target_reservation(projectile)
	var effect_x_fp := int(projectile.get("x_fp", 0))
	var effect_y_fp := int(projectile.get("y_fp", 0))
	var owner_seat_id := int(projectile.get("owner_id", 0))
	var projectile_id := int(projectile.get("id", 0))
	projectile.expired = true
	var frequency_hz := 35000 + _random_int(9100)
	_emit_event("sound_cue", {
		"key": "explo1",
		"frequency_hz": frequency_hz,
		"source_hz": 32000,
		"seat_id": owner_seat_id,
		"projectile_id": projectile_id,
		"retail_left_fp": effect_x_fp - 12 * FP_ONE,
		"retail_top_fp": effect_y_fp - 12 * FP_ONE,
		"x_fp": effect_x_fp - 12 * FP_ONE,
		"y_fp": effect_y_fp - 12 * FP_ONE,
	})
	var flare_red := 128 + _random_int(50)
	var flare_green := 128 + _random_int(50)
	var flare_angle := _rng.next_float32(0.0, 359.0)
	var flare_speed := _rng.next_float32(0.0, 5.0)
	_emit_event("rocket_expired", {
		"projectile_id": projectile_id,
		"seat_id": owner_seat_id,
		"effect_key": "flare4",
		"red": flare_red,
		"green": flare_green,
		"angle": flare_angle,
		"speed": flare_speed,
		"x_fp": effect_x_fp,
		"y_fp": effect_y_fp,
	})


func _is_rocket_missile(projectile: Dictionary) -> bool:
	return String(projectile.get("projectile_kind", "")) == ROCKET_PROJECTILE_KIND


func _advance_player_projectile_frame(projectile: Dictionary) -> void:
	var prototype_id := int(projectile.prototype_id)
	var should_advance := _sprite_frames.projectile_is_persistent(prototype_id)
	if not should_advance:
		var countdown := int(projectile.get("animation_countdown_fp", FP_ONE))
		countdown -= _scaled_simulation_delta(FP_ONE)
		projectile.animation_countdown_fp = countdown
		# The retail generic projectile animation advances only after strict
		# underflow; equality remains on the current atlas cell for one update.
		if countdown < 0:
			projectile.animation_countdown_fp = FP_ONE
			should_advance = true
	if not should_advance:
		return
	var next_prototype := _sprite_frames.projectile_next_prototype_id(prototype_id)
	if next_prototype < 0:
		projectile.expired = true
		return
	var old_width := int(projectile.width)
	var old_height := int(projectile.height)
	var source_rect := _sprite_frames.projectile_source_rect(next_prototype)
	projectile.prototype_id = next_prototype
	if source_rect.size.x <= 0 or source_rect.size.y <= 0:
		return
	# Retail stores projectile top-left coordinates while the remake stores
	# centers. Preserve that top-left when an animation cell changes size.
	var left_fp := int(projectile.x_fp) - (old_width * FP_ONE >> 1)
	var top_fp := int(projectile.y_fp) - (old_height * FP_ONE >> 1)
	projectile.width = source_rect.size.x
	projectile.height = source_rect.size.y
	projectile.x_fp = left_fp + (source_rect.size.x * FP_ONE >> 1)
	projectile.y_fp = top_fp + (source_rect.size.y * FP_ONE >> 1)
	_set_mask_source_rect(projectile, source_rect)
	projectile.source_rect = [
		source_rect.position.x,
		source_rect.position.y,
		source_rect.size.x,
		source_rect.size.y,
	]


func _update_common_projectiles() -> void:
	var tick_scale_fp := roundi(Rng._float32(
		_simulation_scale_float()
	) * FP_ONE)
	for projectile_value in _enemy_projectiles_in_slot_order():
		var projectile: Dictionary = projectile_value
		if bool(projectile.expired):
			continue
		_alien_projectile_processed_this_level = true
		if String(projectile.get("owner_kind", "")) == "boss":
			_update_retail_big_boss_common_projectile(projectile, tick_scale_fp)
			continue
		var animation_countdown_fp := (
			int(projectile.get("animation_countdown_fp", FP_ONE)) - tick_scale_fp
		)
		if animation_countdown_fp < 0:
			animation_countdown_fp = FP_ONE
			var animation_frame := int(projectile.get("animation_frame", 0)) - 1
			if animation_frame < 0:
				animation_frame = 1
			projectile.animation_frame = animation_frame
		projectile.animation_countdown_fp = animation_countdown_fp
		var slot_index := int(projectile.get("common_slot", -1))
		if slot_index >= 0 and slot_index < _common_projectile_slots.size():
			var slot: Dictionary = _common_projectile_slots[slot_index]
			if int(slot.get("entity_id", 0)) == int(projectile.id):
				slot.animation_frame = int(projectile.animation_frame)
				slot.animation_countdown_fp = animation_countdown_fp
		projectile.x_fp = int(projectile.x_fp) + int(projectile.velocity_x_fp)
		projectile.y_fp = int(projectile.y_fp) + int(projectile.velocity_y_fp)
		_set_enemy_projectile_mask_rect(projectile)
		var outside_bottom := int(projectile.y_fp) > 616 * FP_ONE
		if outside_bottom:
			projectile.expired = true
			_release_common_projectile_slot(projectile)


func _update_retail_big_boss_common_projectile(
	projectile: Dictionary,
	tick_scale_fp: int
) -> void:
	var allocation := _active_boss_projectile_allocation()
	var center_offset := allocation.get(
		"center_offset",
		[RETAIL_BIG_BOSS_PROJECTILE_CENTER_OFFSET, RETAIL_BIG_BOSS_PROJECTILE_CENTER_OFFSET]
	) as Array
	var retirement := allocation.get("retirement", {}) as Dictionary
	var animation_countdown_fp := (
		int(projectile.get("animation_countdown_fp", FP_ONE)) - tick_scale_fp
	)
	if animation_countdown_fp < 0:
		animation_countdown_fp = int(projectile.get("animation_period_fp", FP_ONE))
		var animation_frame := int(projectile.get("animation_frame", 0)) + 1
		if animation_frame > int(projectile.get("animation_frame_max", 0)):
			animation_frame = 0
		projectile.animation_frame = animation_frame
	projectile.animation_countdown_fp = animation_countdown_fp
	var slot_index := int(projectile.get("common_slot", -1))
	if slot_index >= 0 and slot_index < _common_projectile_slots.size():
		var slot := _common_projectile_slots[slot_index] as Dictionary
		if int(slot.get("entity_id", 0)) == int(projectile.id):
			slot.animation_frame = int(projectile.animation_frame)
			slot.animation_period_fp = int(
				projectile.get("animation_period_fp", FP_ONE)
			)
			slot.animation_countdown_fp = animation_countdown_fp
	projectile.retail_left_fp = (
		int(projectile.get("retail_left_fp", 0))
		+ int(projectile.get("velocity_x_fp", 0))
	)
	projectile.retail_top_fp = (
		int(projectile.get("retail_top_fp", 0))
		+ int(projectile.get("velocity_y_fp", 0))
	)
	projectile.x_fp = (
		int(projectile.retail_left_fp)
		+ int(center_offset[0]) * FP_ONE
	)
	projectile.y_fp = (
		int(projectile.retail_top_fp)
		+ int(center_offset[1]) * FP_ONE
	)
	_set_enemy_projectile_mask_rect(projectile)
	if (
		int(projectile.retail_top_fp)
		> int(projectile.get(
			"retire_top_left_y_strictly_above",
			retirement.get(
				"default_surface_height",
				RETAIL_BIG_BOSS_PROJECTILE_SURFACE_HEIGHT
			)
		)) * FP_ONE
	):
		projectile.expired = true
		_release_common_projectile_slot(projectile)


func _enemy_projectiles_in_slot_order() -> Array:
	var ordered: Array = []
	for projectile_value in _projectiles:
		var projectile: Dictionary = projectile_value
		if String(projectile.get("owner_kind", "")) != "player":
			ordered.append(projectile)
	ordered.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int(left.get("common_slot", -1)) < int(right.get("common_slot", -1))
	)
	return ordered


func _update_projectiles() -> void:
	_update_player_projectiles()
	_update_common_projectiles()


func _player_projectile_out_of_bounds(projectile: Dictionary) -> bool:
	var left_fp := int(projectile.x_fp) - (int(projectile.width) * FP_ONE >> 1)
	var top_fp := int(projectile.y_fp) - (int(projectile.height) * FP_ONE >> 1)
	var left := _trunc_fp_to_int(left_fp)
	var top := _trunc_fp_to_int(top_fp)
	return top < -50 or left < -50 or left > 850


func _resolve_boss_player_projectile_collisions() -> void:
	if not _boss_entered or _boss_runtime_blocked:
		return
	for projectile_value in _player_projectiles_in_slot_order():
		var projectile := projectile_value as Dictionary
		if (
			bool(projectile.get("expired", false))
			or String(projectile.get("owner_kind", "")) != "player"
		):
			continue
		var is_laser := bool(projectile.get("is_laser", false))
		if is_laser:
			_refresh_laser_collision_geometry(projectile)
		var owner_seat_id := int(projectile.get("owner_id", 0))
		var collision_projectile := projectile.duplicate(true)
		collision_projectile["midpoint_x_fp"] = int(projectile.x_fp)
		collision_projectile["midpoint_y_fp"] = int(projectile.y_fp)
		collision_projectile["surface_height"] = FIELD_HEIGHT
		collision_projectile["special_collision_y"] = is_laser
		collision_projectile["rank_ready"] = bool(
			_match_persistent_flags_for_seat(owner_seat_id).rank_ready
		)
		var result: Dictionary = _retail_big_boss.resolve_player_projectile(
			collision_projectile,
			_simulation_milliseconds()
		)
		_ingest_boss_controller_result(result)
		if _boss_runtime_blocked:
			return
		if not bool(result.get("hit", false)):
			continue
		if _is_rocket_missile(projectile):
			_complete_rocket_confirmed_hit(projectile, owner_seat_id)
			continue
		_record_player_projectile_hit(owner_seat_id)
		if bool(result.get("consume_projectile", true)):
			projectile.expired = true
		else:
			projectile.damage_fp = int(result.get(
				"remaining_damage_fp",
				int(projectile.get("damage_fp", 0))
			))


func _resolve_player_projectile_collisions() -> void:
	# FUN_00585840 uses the same ascending 100-slot order as allocation/update.
	for projectile_value in _player_projectiles_in_slot_order():
		var projectile: Dictionary = projectile_value
		if bool(projectile.expired) or String(projectile.owner_kind) != "player":
			continue
		if _is_rocket_missile(projectile):
			for rocket_enemy_value in _enemies:
				var rocket_enemy := rocket_enemy_value as Dictionary
				if (
					bool(rocket_enemy.get("dead", false))
					or String(rocket_enemy.get("authored_state", "")) == "delayed"
					or int(rocket_enemy.get("behavior_state_id", 0)) in [5, 8]
				):
					continue
				if _resolve_rocket_ordinary_collision(projectile, rocket_enemy):
					break
			continue
		var is_laser := bool(projectile.get("is_laser", false))
		if is_laser:
			_refresh_laser_collision_geometry(projectile)
		for enemy_value in _enemies:
			var enemy: Dictionary = enemy_value
			if (
				bool(enemy.dead)
				or String(enemy.get("authored_state", "")) == "delayed"
				or int(enemy.get("behavior_state_id", 0)) in [5, 8]
			):
				continue
			if _objects_collide(projectile, enemy):
				_record_player_projectile_hit(int(projectile.owner_id))
				enemy.health_fp = int(enemy.health_fp) - int(projectile.damage_fp)
				_emit_event("enemy_hit", {
					"entity_id": int(enemy.id),
					"projectile_id": int(projectile.id),
					"enemy_sheet": String(enemy.get("sprite", "alien001")),
					"x_fp": int(enemy.x_fp),
					"y_fp": int(enemy.y_fp),
				})
				if is_laser:
					projectile.damage_fp = int(projectile.damage_fp) >> 1
				else:
					projectile.expired = true
				if int(enemy.health_fp) <= 0:
					_kill_enemy(enemy, int(projectile.owner_id))
				if not is_laser:
					break


func _resolve_rocket_ordinary_collision(
	projectile: Dictionary,
	enemy: Dictionary
) -> bool:
	if (
		bool(projectile.get("expired", false))
		or not _is_rocket_missile(projectile)
		or bool(enemy.get("dead", false))
	):
		return false
	_set_rocket_source_rect(projectile)
	if not _objects_collide(projectile, enemy):
		return false
	var owner_seat_id := int(projectile.get("owner_id", 0))
	enemy.health_fp = int(enemy.get("health_fp", 0)) - int(
		projectile.get("damage_fp", ROCKET_DAMAGE_FP)
	)
	_emit_event("enemy_hit", {
		"entity_id": int(enemy.get("id", 0)),
		"projectile_id": int(projectile.get("id", 0)),
		"enemy_sheet": String(enemy.get("sprite", "alien001")),
		"projectile_kind": ROCKET_PROJECTILE_KIND,
		"x_fp": int(enemy.get("x_fp", 0)),
		"y_fp": int(enemy.get("y_fp", 0)),
	})
	_complete_rocket_confirmed_hit(projectile, owner_seat_id)
	if int(enemy.health_fp) <= 0:
		_kill_enemy(enemy, owner_seat_id)
	return true


func _complete_rocket_confirmed_hit(
	projectile: Dictionary,
	owner_seat_id: int
) -> void:
	if bool(projectile.get("expired", false)):
		return
	projectile.expired = true
	_release_rocket_target_reservation(projectile)
	_subtract_rocket_stale_capacity(projectile, owner_seat_id)
	_record_player_projectile_hit(owner_seat_id)


func _release_rocket_target_reservation(projectile: Dictionary) -> void:
	if not bool(projectile.get("target_reserved", false)):
		return
	var target_entity_id := int(projectile.get("target_entity_id", 0))
	for enemy_value in _enemies:
		var enemy := enemy_value as Dictionary
		if int(enemy.get("id", 0)) == target_entity_id:
			enemy.rocket_reserved = false
			break
	projectile.target_reserved = false


func _subtract_rocket_stale_capacity(
	projectile: Dictionary,
	owner_seat_id: int
) -> void:
	if (
		owner_seat_id < 0
		or owner_seat_id >= _ordinary_projectile_counter_adjustment_by_seat.size()
	):
		return
	var stale_contribution := maxi(
		0,
		int(projectile.get("stale_capacity_contribution", 0))
	)
	if stale_contribution == 0:
		return
	var raw_live_count := 0
	for projectile_value in _projectiles:
		var live_projectile := projectile_value as Dictionary
		if (
			String(live_projectile.get("owner_kind", "")) == "player"
			and int(live_projectile.get("owner_id", -1)) == owner_seat_id
			and not bool(live_projectile.get("expired", false))
			and not _is_rocket_missile(live_projectile)
		):
			raw_live_count += maxi(
				0,
				int(live_projectile.get("capacity_contribution", 1))
			)
	var old_adjustment := int(
		_ordinary_projectile_counter_adjustment_by_seat[owner_seat_id]
	)
	var retail_live_count := maxi(0, raw_live_count + old_adjustment)
	var adjusted_live_count := maxi(0, retail_live_count - stale_contribution)
	_ordinary_projectile_counter_adjustment_by_seat[owner_seat_id] = (
		adjusted_live_count - raw_live_count
	)


func _resolve_enemy_projectile_collisions() -> void:
	var player_targets: Array = []
	for player_value in _players:
		var player: Dictionary = player_value
		var seat_id := int(player.seat_id)
		var progression := _progression_for_seat(seat_id)
		if (
			not bool(player.active)
			or not bool(player.alive)
			or int(player.invulnerable_ticks) > 0
			or int(player.projectile_suppression_ticks) > 0
			or int(progression.get("shield_ticks", 0)) > 0
		):
			continue
		var mirrored := false
		if int(progression.get("mirror_ticks", 0)) > 0:
			# FUN_005842c0 consumes one raw word before scanning all 100
			# common-shot slots and makes exactly one fighter side hittable.
			mirrored = (_rng.next_u32() & 0x1ff) >= 256
		player_targets.append({
			"player": player,
			"seat_id": seat_id,
			"mirrored": mirrored,
			"target": _mirror_collision_proxy(player, mirrored),
		})
	for projectile_value in _enemy_projectiles_in_slot_order():
		var projectile: Dictionary = projectile_value
		if bool(projectile.expired):
			continue
		for target_value in player_targets:
			var target_context: Dictionary = target_value
			var player: Dictionary = target_context.player
			var seat_id := int(target_context.seat_id)
			var mirrored := bool(target_context.mirrored)
			var intercepted := false
			for captive_value in _captured_enemies_for_seat(seat_id, true):
				var captive: Dictionary = captive_value
				var captive_target := _mirror_collision_proxy(captive, mirrored)
				if _enemy_projectile_hits_object(projectile, captive_target):
					projectile.expired = true
					_release_common_projectile_slot(projectile)
					_destroy_captured_enemy(captive, "projectile_intercept")
					intercepted = true
					break
			if intercepted:
				break
			if _enemy_projectile_hits_object(projectile, target_context.target):
				projectile.expired = true
				_release_common_projectile_slot(projectile)
				var captives := _captured_enemies_for_seat(seat_id, false)
				if not captives.is_empty():
					_destroy_captured_enemy(captives[0], "fighter_sacrifice")
				else:
					_damage_player(player, int(projectile.damage_fp))
				break


func _active_progression_has_freeze() -> bool:
	for seat_id in range(2):
		if (
			_seat_is_participating(seat_id)
			and int(_progression_for_seat(seat_id).get("freeze_ticks", 0)) > 0
		):
			return true
	return false


func _resolve_projectile_collisions() -> void:
	_resolve_player_projectile_collisions()
	_resolve_enemy_projectile_collisions()


func _refresh_laser_collision_geometry(projectile: Dictionary) -> void:
	var owner_seat := int(projectile.owner_id)
	if owner_seat < 0 or owner_seat >= _players.size():
		return
	var owner: Dictionary = _players[owner_seat]
	var bottom_fp := maxi(0, int(owner.y_fp) - (PLAYER_HEIGHT * FP_ONE >> 1))
	projectile.collision_x_fp = int(projectile.x_fp)
	projectile.collision_y_fp = bottom_fp >> 1
	projectile.collision_width = int(projectile.width)
	projectile.collision_height = bottom_fp >> 16


func _enemy_projectile_hits_object(
	projectile: Dictionary,
	target: Dictionary
) -> bool:
	# FUN_005842c0 first uses each shot type's recovered narrow broad metadata;
	# the later pixel test still samples the full unscaled 32x32 HMA frame.
	var metadata := _enemy_projectile_broad_metadata(projectile)
	if metadata.size() != 4:
		return false
	var stored_left := _trunc_fp_to_int(int(projectile.x_fp) - 16 * FP_ONE)
	var stored_top := _trunc_fp_to_int(int(projectile.y_fp) - 16 * FP_ONE)
	var shot_left := stored_left + int(metadata[0])
	var shot_top := stored_top + int(metadata[1])
	var shot_right := shot_left + int(metadata[2])
	var shot_bottom := shot_top + int(metadata[3])
	var target_left: int
	var target_top: int
	var target_right: int
	var target_bottom: int
	if target.has("seat_id"):
		target_left = _trunc_fp_to_int(int(target.x_fp) - 20 * FP_ONE)
		target_top = _trunc_fp_to_int(int(target.y_fp) - 14 * FP_ONE)
		target_right = target_left + 40
		target_bottom = target_top + 27
	else:
		var target_width := int(target.get("width", 32))
		var target_height := int(target.get("height", 32))
		target_left = _trunc_fp_to_int(
			int(target.get("collision_x_fp", target.x_fp))
			- target_width * FP_ONE / 2
		)
		target_top = _trunc_fp_to_int(
			int(target.get("collision_y_fp", target.y_fp))
			- target_height * FP_ONE / 2
		)
		target_right = target_left + target_width
		target_bottom = target_top + target_height
	var broad_hit := (
		shot_top < target_bottom
		and shot_left < target_right
		and target_left < shot_right
		and target_top < shot_bottom
	)
	if not broad_hit or _collision_mode == "simple":
		return broad_hit
	var projectile_mask_id := String(projectile.get("mask_id", ""))
	var target_mask_id := String(target.get("mask_id", ""))
	if (
		projectile_mask_id.is_empty()
		or target_mask_id.is_empty()
		or not _hit_masks.has(projectile_mask_id)
		or not _hit_masks.has(target_mask_id)
	):
		# The state-13 common-shot branch falls back to the strict broad rect
		# when either runtime HMA pointer is null. Ordinary authored shots retain
		# the remake's existing fail-closed content invariant.
		return String(projectile.get("owner_kind", "")) == "boss"
	var projectile_mask: HitMaskAtlas = _hit_masks[projectile_mask_id]
	var target_mask: HitMaskAtlas = _hit_masks[target_mask_id]
	return projectile_mask.overlaps_source_rect(
		_mask_source_rect(projectile, projectile_mask),
		int(projectile.x_fp),
		int(projectile.y_fp),
		32,
		32,
		target_mask,
		_mask_source_rect(target, target_mask),
		int(target.get("collision_x_fp", target.x_fp)),
		int(target.get("collision_y_fp", target.y_fp)),
		int(target.get("width", 32)),
		int(target.get("height", 32))
	)


func _enemy_projectile_broad_metadata(projectile: Dictionary) -> Array:
	if String(projectile.get("owner_kind", "")) == "boss":
		var inset_x := int(projectile.get("broadphase_inset_x", -1))
		var inset_y := int(projectile.get("broadphase_inset_y", -1))
		var broad_width := int(projectile.get("broadphase_width", 0))
		var broad_height := int(projectile.get("broadphase_height", 0))
		if (
			inset_x < 0
			or inset_y < 0
			or broad_width <= 0
			or broad_height <= 0
		):
			return []
		return [
			inset_x,
			inset_y,
			broad_width,
			broad_height,
		]
	var projectile_type := int(projectile.get("enemy_projectile_type", 7))
	var sheet_id := String(projectile.get("enemy_sheet", "alien001"))
	return _sprite_frames.enemy_projectile_broad_bounds(
		projectile_type,
		sheet_id
	)


func _resolve_enemy_player_collisions() -> void:
	# Ordinary alien contact never damages the fighter. The only first-five
	# body-collision consumer is an active Scoop field.
	for player_value in _players:
		var player: Dictionary = player_value
		if not bool(player.active) or not bool(player.alive):
			continue
		var seat_id := int(player.seat_id)
		var progression := _progression_for_seat(seat_id)
		if int(progression.get("scoop_ticks", 0)) <= 0:
			continue
		for enemy_value in _enemies:
			var enemy: Dictionary = enemy_value
			if (
				bool(enemy.dead)
				or not bool(enemy.get("authored_lvd", false))
				or int(enemy.get("behavior_state_id", 0)) in [5, 6, 8]
			):
				continue
			if not _enemy_inside_scoop_field(enemy, player):
				continue
			var side := _first_free_capture_side(seat_id)
			if side >= 0:
				_capture_enemy(enemy, player, side)
			else:
				_destroy_scoop_overflow_enemy(enemy, progression, seat_id)


func _enemy_inside_scoop_field(enemy: Dictionary, player: Dictionary) -> bool:
	# FUN_0058d490 uses truncated top-left integer bounds instead of the normal
	# HMA overlap. Its strict 90px band widens by half the vertical distance.
	var player_top := _trunc_fp_to_int(
		int(player.y_fp) - (PLAYER_HEIGHT * FP_ONE >> 1)
	)
	var enemy_left := _trunc_fp_to_int(int(enemy.x_fp) - 16 * FP_ONE)
	var enemy_top := _trunc_fp_to_int(int(enemy.y_fp) - 16 * FP_ONE)
	var enemy_right := _trunc_fp_to_int(int(enemy.x_fp) + 16 * FP_ONE)
	var enemy_bottom := _trunc_fp_to_int(int(enemy.y_fp) + 16 * FP_ONE)
	var beam_top := player_top - 90
	if not (
		(beam_top < enemy_top and enemy_top < player_top)
		or (beam_top < enemy_bottom and enemy_bottom < player_top)
	):
		return false
	var distance := clampi(player_top - enemy_top, 0, 90)
	var half_width := _trunc_div(distance, 2) + 4
	var center_x := _trunc_fp_to_int(int(player.x_fp))
	var progression := _progression_for_seat(int(player.seat_id))
	if (
		int(progression.get("mirror_ticks", 0)) > 0
		and _random_int(128) >= 64
	):
		center_x = _trunc_fp_to_int(FIELD_WIDTH * FP_ONE - int(player.x_fp))
	var beam_left := center_x - half_width
	var beam_right := center_x + half_width
	return (
		(beam_left < enemy_left and enemy_left < beam_right)
		or (beam_left < enemy_right and enemy_right < beam_right)
	)


func _first_free_capture_side(seat_id: int) -> int:
	var occupied := [false, false]
	for captive_value in _captured_enemies_for_seat(seat_id, false):
		var captive: Dictionary = captive_value
		occupied[clampi(int(captive.captured_side), 0, 1)] = true
	if not occupied[0]:
		return 0
	if not occupied[1]:
		return 1
	return -1


func _captured_enemies_for_seat(seat_id: int, settled_only: bool) -> Array:
	var result: Array = []
	for enemy_value in _enemies:
		var enemy: Dictionary = enemy_value
		if (
			bool(enemy.dead)
			or int(enemy.get("behavior_state_id", 0)) != 8
			or int(enemy.get("captured_owner_seat", -1)) != seat_id
			or (settled_only and not bool(enemy.get("captured_latched", false)))
		):
			continue
		result.append(enemy)
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int(left.captured_side) < int(right.captured_side)
	)
	return result


func _capture_enemy(enemy: Dictionary, player: Dictionary, side: int) -> void:
	enemy.authored_state = "captured"
	enemy.behavior_state_id = 8
	enemy.captured_owner_seat = int(player.seat_id)
	enemy.captured_side = side
	enemy.captured_latched = false
	# Capture quantizes both alien axes exactly where retail converts its floats
	# to integers: top-left X becomes the stored player-relative offset and
	# top-left Y is snapped before state 8 begins converging.
	var enemy_left := _trunc_fp_to_int(int(enemy.x_fp) - 16 * FP_ONE)
	var player_left_fp := int(player.x_fp) - 20 * FP_ONE
	enemy.capture_offset_fp = _trunc_fp_to_int(
		enemy_left * FP_ONE - player_left_fp
	) * FP_ONE
	var enemy_top := _trunc_fp_to_int(int(enemy.y_fp) - 16 * FP_ONE)
	enemy.y_fp = (enemy_top + 16) * FP_ONE
	_cleanup_swd_group(enemy)
	_update_enemy_mask_rect(enemy)
	_level_escaped_entities += 1
	_try_resolve_level_counter()
	_emit_event("enemy_captured", {
		"entity_id": int(enemy.id),
		"seat_id": int(player.seat_id),
		"side": side,
		"enemy_sheet": String(enemy.get("sprite", "alien001")),
		"x_fp": int(enemy.x_fp),
		"y_fp": int(enemy.y_fp),
	})


func _destroy_scoop_overflow_enemy(
	enemy: Dictionary,
	progression: Dictionary,
	killer_seat: int
) -> void:
	# The third alien is scored/counted immediately, but retail keeps the object
	# alive in state 5 and visibly flings it upward instead of teleporting it out.
	enemy.authored_state = "scoop_escape"
	enemy.behavior_state_id = 5
	enemy.horizontal_velocity_fp = _random_retail_float_fp(-4.0, 4.0)
	enemy.vertical_velocity_fp = _random_retail_float_fp(-10.0, -6.0)
	_cleanup_swd_group(enemy)
	_qualifying_kills_this_tick += 1
	_record_enemy_killed(killer_seat)
	var score := 2500 * int(progression.get("score_multiplier", 1))
	progression.score = int(progression.score) + score
	_emit_event("enemy_destroyed", {
		"entity_id": int(enemy.id),
		"enemy_id": int(enemy.id),
		"enemy_sheet": String(enemy.get("sprite", "alien001")),
		"cause": "scoop_overflow",
		"score": score,
		"cash": 0,
		"x_fp": int(enemy.x_fp),
		"y_fp": int(enemy.y_fp),
	})
func _destroy_captured_enemy(enemy: Dictionary, cause: String) -> void:
	if bool(enemy.dead):
		return
	enemy.dead = true
	_emit_event("captured_enemy_destroyed", {
		"entity_id": int(enemy.id),
		"seat_id": int(enemy.get("captured_owner_seat", -1)),
		"side": int(enemy.get("captured_side", -1)),
		"enemy_sheet": String(enemy.get("sprite", "alien001")),
		"cause": cause,
		"x_fp": int(enemy.x_fp),
		"y_fp": int(enemy.y_fp),
	})


func _kill_enemy(enemy: Dictionary, killer_seat: int = 0) -> void:
	if bool(enemy.dead):
		return
	if bool(enemy.get("warp_malfunction", false)):
		# Mode 16 creates the gem before it mutates kill/completion accounting.
		_spawn_warp_malfunction_gem(enemy)
		enemy.dead = true
		_qualifying_kills_this_tick += 1
		_warp_malfunction_killed += 1
		var warp_progression := _progression_for_seat(killer_seat)
		var warp_score := 5000 * int(
			warp_progression.get("score_multiplier", 1)
		)
		warp_progression.score = int(warp_progression.score) + warp_score
		_emit_event("enemy_destroyed", {
			"entity_id": int(enemy.id),
			"enemy_id": int(enemy.id),
			"enemy_sheet": String(enemy.get("sprite", "malfunction1")),
			"cause": "warp_malfunction",
			"score": warp_score,
			"cash": 0,
			"x_fp": int(enemy.x_fp),
			"y_fp": int(enemy.y_fp),
		})
		return
	var killed_state := int(enemy.get("behavior_state_id", 0))
	enemy.dead = true
	_qualifying_kills_this_tick += 1
	_record_level_eight_hit(killer_seat, enemy)
	_record_enemy_killed(killer_seat)
	var progression := _progression_for_seat(killer_seat)
	var score_award := int(enemy.get("score", 0))
	var cash_award := 0
	if bool(enemy.get("authored_lvd", false)) and int(enemy.get("group_id", -1)) >= 0:
		if killed_state in [1, 10]:
			score_award += _award_group_or_cohort_completion(enemy)
		if bool(enemy.get("leader_has_followers", false)):
			score_award += _kill_recruited_followers(enemy, killer_seat)
		elif int(enemy.get("follower_leader_slot", -1)) >= 0:
			score_award += 2500
			enemy.follower_leader_slot = -1
	score_award *= int(progression.get("score_multiplier", 1))
	progression.score = int(progression.score) + score_award
	if _is_hurry_up_ship(enemy):
		_record_hurry_up_secret(enemy, killer_seat)
	elif _is_secret_ship(enemy):
		_escalate_secret_ship_health_base(enemy)
	_emit_event("enemy_destroyed", {
		"entity_id": int(enemy.id),
		"enemy_id": int(enemy.id),
		"enemy_sheet": String(enemy.get("sprite", "alien001")),
		"score": score_award,
		"cash": cash_award,
		"x_fp": int(enemy.x_fp),
		"y_fp": int(enemy.y_fp),
	})
	if (
		bool(enemy.get("authored_lvd", false))
		and int(enemy.get("group_id", -1)) >= 0
		and not _is_mode_three_bonus()
		and _find_available_pickup_slot() >= 0
		and _retail_bonus_drop_passes()
	):
		_spawn_retail_bonus(enemy)


func _spawn_warp_malfunction_gem(enemy: Dictionary) -> void:
	# Gems share the retail 150-slot pickup pool. A full pool returns before the
	# color draw, while every successful normal first-five spawn consumes one
	# RngInt(0, 6).
	var pickup_slot := _find_available_pickup_slot()
	if pickup_slot < 0:
		return
	var color_index := _random_int(6)
	var gem := {
		"id": _allocate_entity_id(),
		"pickup_slot": pickup_slot,
		"kind": "warp_gem",
		"effect_key": "warp_gem",
		"texture_key": "marks",
		"variant": color_index,
		"gem_color_bit": 1 << color_index,
		"source_y": int(WARP_GEM_ROW_Y[color_index]),
		"animation_frame": 0,
		"animation_period_fp": 6 * FP_ONE,
		"animation_countdown_fp": 6 * FP_ONE,
		# Retail top-left is (alien_left+22, alien_top). Both sprites are
		# center-normalized here: X is unchanged and Y becomes alien center-22.
		"x_fp": int(enemy.x_fp),
		"y_fp": int(enemy.y_fp) - 22 * FP_ONE,
		"velocity_x_fp": 0,
		"velocity_y_fp": int(WARP_GEM_VELOCITY_FP[color_index]),
		"width": 20,
		"height": 20,
		"expired": false,
		"mask_id": "marks",
		"mask_required": true,
	}
	_update_pickup_mask_rect(gem)
	_pickups.append(gem)
	_emit_event("warp_gem_spawned", {
		"entity_id": int(gem.id),
		"variant": color_index,
		"x_fp": int(gem.x_fp),
		"y_fp": int(gem.y_fp),
	})


func _record_enemy_killed(killer_seat: int = -1) -> void:
	_level_killed_entities += 1
	if _try_resolve_level_counter("kill") and killer_seat >= 0:
		_award_final_kill_rockets(killer_seat)


func _record_level_eight_hit(killer_seat: int, enemy: Dictionary) -> void:
	if (
		not _is_mode_three_bonus()
		or not bool(enemy.get("authored_lvd", false))
		or int(enemy.get("group_id", -1)) < 0
		or killer_seat < 0
		or killer_seat >= _level_eight_result_players.size()
		or not _seat_is_participating(killer_seat)
	):
		return
	var counters: Dictionary = _level_eight_result_players[killer_seat]
	counters.actual_hits = mini(
		int(counters.get("total_targets", _level_total_entities)),
		int(counters.get("actual_hits", 0)) + 1
	)
	_emit_event("level_eight_hit_recorded", {
		"seat_id": killer_seat,
		"entity_id": int(enemy.get("id", 0)),
		"actual_hits": int(counters.actual_hits),
		"total_targets": int(counters.total_targets),
		"x_fp": _enemy_world_x_fp(enemy),
		"y_fp": _enemy_world_y_fp(enemy),
	})


func _escape_enemy(enemy: Dictionary) -> void:
	if bool(enemy.dead):
		return
	enemy.dead = true
	_level_escaped_entities += 1
	_emit_event("enemy_escaped", {
		"entity_id": int(enemy.id),
		"enemy_sheet": String(enemy.get("sprite", "alien001")),
		"x_fp": int(enemy.x_fp),
		"y_fp": int(enemy.y_fp),
	})
	_try_resolve_level_counter("deactivation")


func _try_resolve_level_counter(reason: String = "counter") -> bool:
	if (
		_level_resolved
		or _level_total_entities <= 0
		or _level_killed_entities + _level_escaped_entities < _level_total_entities
	):
		return false
	return _begin_level_resolution(reason)


func _begin_level_resolution(reason: String) -> bool:
	if _level_resolved:
		return false
	_level_resolved = true
	var resolution_ticks := LEVEL_RESOLUTION_TICKS
	if _is_mode_three_bonus():
		var timing: Dictionary = _level_eight_contract.get("timing_and_flow", {})
		resolution_ticks = _milliseconds_to_ticks_ceil(
			int(timing.get("level_complete_hold_ms", 3000))
		)
	_level_resolution_tick = _tick + resolution_ticks
	if reason != "watchdog" and not _is_mode_three_bonus():
		# Retail statistics track the fastest ordinary level clear; the
		# liveness watchdog and mode-three results own their own flows.
		var clear_seat := clampi(_turn_seat, 0, 1)
		var clear_stats: Dictionary = _profile_stats_by_seat[clear_seat]
		var previous_fastest := int(clear_stats.get("fastest_level_clear_ticks", 0))
		if previous_fastest <= 0 or _level_tick < previous_fastest:
			clear_stats.fastest_level_clear_ticks = _level_tick
	_emit_event("level_resolved", {
		"level_id": _level_id,
		"killed": _level_killed_entities,
		"escaped": _level_escaped_entities,
		"resolution_tick": _level_resolution_tick,
		"reason": reason,
		"x_fp": (FIELD_WIDTH >> 1) * FP_ONE,
		"y_fp": (FIELD_HEIGHT >> 1) * FP_ONE,
	})
	return true


func _award_final_kill_rockets(
	killer_seat: int,
	allow_retail_big_boss: bool = false
) -> void:
	if _rocket_fired_this_level or not _alien_projectile_processed_this_level:
		return
	var level: Dictionary = _level_data_for(_level_id)
	if (
		not level.has("authored_lvd")
		or (
			int(level.authored_lvd.level_mode_id) not in [1, 2, 6]
			and not (
				allow_retail_big_boss
				and int(level.authored_lvd.level_mode_id)
				== RETAIL_BIG_BOSS_MODE_ID
			)
		)
	):
		return
	var progression := _progression_for_seat(killer_seat)
	var score := 0
	if int(progression.get("rockets", 0)) < 50:
		progression.rockets = mini(50, int(progression.get("rockets", 0)) + 10)
	else:
		score = 50000 * int(progression.get("score_multiplier", 1))
		progression.score = int(progression.score) + score
	_emit_event("final_kill_reward", {
		"seat_id": killer_seat,
		"rockets": int(progression.get("rockets", 0)),
		"score": score,
		"x_fp": (FIELD_WIDTH >> 1) * FP_ONE,
		"y_fp": (FIELD_HEIGHT >> 1) * FP_ONE,
	})


func _award_group_or_cohort_completion(enemy: Dictionary) -> int:
	var level: Dictionary = _level_data_for(_level_id)
	if not level.has("authored_lvd"):
		return 0
	var level_mode_id := int(level.authored_lvd.level_mode_id)
	if level_mode_id in [1, 6]:
		var group_id := int(enemy.group_id)
		var killed := int(_group_kill_counts.get(group_id, 0)) + 1
		_group_kill_counts[group_id] = killed
		if killed == int(_group_totals.get(group_id, -1)):
			_group_kill_counts[group_id] = 0
			_emit_event("group_completed", {
				"group_id": group_id,
				"score": GROUP_COMPLETION_SCORE,
				"x_fp": _enemy_world_x_fp(enemy),
				"y_fp": _enemy_world_y_fp(enemy),
			})
			return GROUP_COMPLETION_SCORE
		return 0
	if level_mode_id == 2:
		var cohort_id := int(enemy.kill_cohort_id)
		var killed := int(_cohort_kill_counts.get(cohort_id, 0)) + 1
		_cohort_kill_counts[cohort_id] = killed
		if killed == int(_cohort_totals.get(cohort_id, -1)):
			_cohort_kill_counts[cohort_id] = 0
			var award := _cohort_completion_score
			_cohort_completion_score *= 2
			_emit_event("cohort_completed", {
				"cohort_id": cohort_id,
				"score": award,
				"x_fp": _enemy_world_x_fp(enemy),
				"y_fp": _enemy_world_y_fp(enemy),
			})
			return award
	return 0


func _kill_recruited_followers(enemy: Dictionary, killer_seat: int) -> int:
	var score := 2500
	for follower_value in _enemies:
		var follower: Dictionary = follower_value
		if (
			bool(follower.dead)
			or int(follower.get("follower_leader_slot", -1)) != int(enemy.id)
		):
			continue
		follower.dead = true
		follower.follower_leader_slot = -1
		_qualifying_kills_this_tick += 1
		_record_enemy_killed(killer_seat)
		score = mini(50000, score * 2)
		_emit_event("enemy_destroyed", {
			"entity_id": int(follower.id),
			"enemy_id": int(follower.id),
			"enemy_sheet": String(follower.get("sprite", "alien001")),
			"cause": "swd_leader_destroyed",
			"score": 0,
			"cash": 0,
			"x_fp": int(follower.x_fp),
			"y_fp": int(follower.y_fp),
		})
	enemy.leader_has_followers = false
	return score


func _retail_bonus_drop_passes() -> bool:
	var denominator := int(_difficulty.bonus_drop_denominator)
	return 1 + _random_int(denominator - 1) < 4


func _spawn_retail_bonus(enemy: Dictionary) -> void:
	var pickup_slot := _find_available_pickup_slot()
	if pickup_slot < 0:
		return
	var jitter_x_fp := (_random_int(6) - 3) * FP_ONE
	var velocity_y_fp := _random_retail_float_fp(1.2, 1.8)
	var animation_period_fp := _random_retail_float_fp(3.0, 7.0)
	var bonus: Dictionary = _select_retail_bonus()
	var animation_frame := 2 + _random_int(5)
	var bonus_type := int(bonus.id)
	var presentation_kind := String(bonus.effect_key)
	var variant := 0
	if bonus_type >= 0 and bonus_type <= 4:
		presentation_kind = "letter"
		variant = bonus_type
	elif bonus_type == 21:
		presentation_kind = "armour"
	elif bonus_type == 28:
		presentation_kind = "bonus_time"
	elif bonus_type >= 29 and bonus_type <= 32:
		presentation_kind = "money"
		variant = bonus_type - 29
	var pickup := {
		"id": _allocate_entity_id(),
		"pickup_slot": pickup_slot,
		"kind": presentation_kind,
		"effect_key": String(bonus.effect_key),
		"texture_key": "bonuses",
		"bonus_type": bonus_type,
		"source_y": int(bonus.source_y),
		"variant": variant,
		"animation_frame": animation_frame,
		"animation_period_fp": animation_period_fp,
		"animation_countdown_fp": animation_period_fp,
		# Retail spawns the 20-pixel bonus at the 32-pixel alien's top-left
		# position. Convert that pair into the remake's center coordinates.
		"x_fp": _enemy_world_x_fp(enemy) - 6 * FP_ONE + jitter_x_fp,
		"y_fp": _enemy_world_y_fp(enemy) - 6 * FP_ONE,
		"velocity_x_fp": 0,
		"velocity_y_fp": velocity_y_fp,
		"width": int(bonus.width),
		"height": int(bonus.height),
		"expired": false,
		"mask_id": "bonuses",
		"mask_required": true,
	}
	_update_pickup_mask_rect(pickup)
	_pickups.append(pickup)


func _select_retail_bonus(excluded_type: int = -1) -> Dictionary:
	var bonuses: Array = _catalog.get("bonuses", [])
	if bonuses.size() != 37:
		return {"id": 29, "effect_key": "money_29", "source_y": 600, "width": 20, "height": 20}
	while true:
		var roll := _random_int(2251)
		var bonus_index := 0
		while bonus_index < bonuses.size() and int(bonuses[bonus_index].weight) < roll:
			roll -= int(bonuses[bonus_index].weight)
			bonus_index += 1
		if bonus_index >= bonuses.size():
			continue
		var candidate: Dictionary = bonuses[bonus_index]
		var bonus_type := int(candidate.id)
		if bonus_type == excluded_type:
			continue
		if _locked_out_bonus_types.has(bonus_type):
			# Profile locks remove the single/double/triple entries from the
			# drop selection (docs/evidence/PROFILE_LOCKS.md); the selector
			# re-rolls exactly like the level-gated rejections below.
			continue
		var reject := false
		if bonus_type == 12:
			reject = _random_int(50) < _level_id
		elif bonus_type == 13:
			reject = _random_int(150) < _level_id
		elif bonus_type == 14:
			reject = _random_int(300) < _level_id
		if not reject:
			return candidate
	return bonuses[0]


func _tighten_enemy_behavior_timers(qualifying_kills: int) -> void:
	if qualifying_kills <= 0:
		return
	for enemy_value in _enemies:
		var enemy: Dictionary = enemy_value
		if (
			bool(enemy.dead)
			or not bool(enemy.get("authored_lvd", false))
			or int(enemy.get("behavior_state_id", 0)) == 8
			or int(enemy.get("behavior_timer_b", 0)) == 0
		):
			continue
		enemy.behavior_timer_a = maxi(
			int(enemy.behavior_timer_a_floor),
			int(enemy.behavior_timer_a)
			- int(enemy.behavior_timer_a_step) * qualifying_kills
		)
		enemy.behavior_timer_b = maxi(
			int(enemy.behavior_timer_b_floor),
			int(enemy.behavior_timer_b)
			- int(enemy.behavior_timer_b_step) * qualifying_kills
		)


func _damage_player(player: Dictionary, damage_fp: int) -> void:
	var seat_id := int(player.seat_id)
	var progression := _progression_for_seat(seat_id)
	if int(progression.armour_fp) > 0:
		var absorbed: int = mini(int(progression.armour_fp), damage_fp)
		progression.armour_fp = int(progression.armour_fp) - absorbed
		damage_fp -= absorbed
		if damage_fp <= 0:
			player.projectile_suppression_ticks = ARMOUR_PROJECTILE_SUPPRESSION_TICKS
			_emit_event("armour_hit", {
				"seat_id": seat_id,
				"x_fp": int(player.x_fp),
				"y_fp": int(player.y_fp),
			})
			return
	_set_upgrade(progression, "alien_lock", 0)
	player.alive = false
	# The retail projectile-death block clears every fighter-bound temporary
	# effect; armour absorption returns before this point and keeps them.
	progression.drunk_ticks = 0
	progression.mirror_ticks = 0
	progression.scoop_ticks = 0
	player.invulnerable_ticks = 0
	player.respawn_ticks = RESPAWN_TICKS
	player.death_accounted = false
	_emit_event("player_destroyed", {
		"seat_id": seat_id,
		"x_fp": int(player.x_fp),
		"y_fp": int(player.y_fp),
	})


func _update_respawns() -> void:
	for player_value in _players:
		var player: Dictionary = player_value
		if (
			_mode == MODE_COOP
			and not bool(player.active)
			and not bool(player.alive)
			and _coop_has_fighter_for(player)
			and (
				_action_just_pressed(int(player.seat_id), ACTION_CONFIRM)
				or _action_just_pressed(int(player.seat_id), ACTION_FIRE)
			)
		):
			player.active = true
			player.respawn_ticks = 1
			_emit_event("player_reentry_requested", {
				"seat_id": int(player.seat_id),
				"x_fp": int(player.x_fp),
				"y_fp": int(player.y_fp),
			})
		if bool(player.alive) or int(player.respawn_ticks) <= 0:
			continue
		player.respawn_ticks = int(player.respawn_ticks) - 1
		if int(player.respawn_ticks) > 0:
			continue
		var progression := _progression_for_seat(int(player.seat_id))
		if not bool(player.get("death_accounted", false)):
			progression.lives = maxi(0, int(progression.lives) - 1)
			_reset_loadout_after_death(progression)
			player.death_accounted = true
		var can_respawn := int(progression.lives) > 0
		if _mode == MODE_COOP:
			can_respawn = _coop_has_fighter_for(player)
		if bool(player.active) and can_respawn:
			player.alive = true
			player.x_fp = _player_spawn_x_fp(int(player.seat_id))
			player.y_fp = PLAYER_Y_FP
			player.invulnerable_ticks = _respawn_invulnerability_ticks()
			_emit_event("player_respawned", {
				"seat_id": int(player.seat_id),
				"x_fp": int(player.x_fp),
				"y_fp": int(player.y_fp),
			})
		elif _mode == MODE_COOP:
			player.active = false
	_check_game_over()


func _reset_loadout_after_death(progression: Dictionary) -> void:
	if _mode == MODE_TIME_TRIAL:
		# Retail match mode 6 skips the entire loadout reset
		# (content/ordnance.json alien_lock.lifecycle.retail_mode_6_exception).
		return
	# The retail reset routine removes one projectile-capacity purchase while
	# preserving the equipped weapon and the rest of the player's profile.
	if int(progression.bullet_capacity) > BASE_PROJECTILE_CAPACITY:
		progression.bullet_capacity = int(progression.bullet_capacity) - 1
	_set_upgrade(progression, "alien_lock", 0)


func _respawn_invulnerability_ticks() -> int:
	return INVULNERABLE_TICKS


func _check_game_over() -> void:
	var any_alive := false
	var any_pending := false
	for player in _players:
		if not _seat_is_participating(int(player.seat_id)):
			continue
		any_alive = any_alive or (bool(player.active) and bool(player.alive))
		any_pending = any_pending or (bool(player.active) and int(player.respawn_ticks) > 0)
	if not any_alive and not any_pending and not _has_remaining_fighters():
		_phase = PHASE_GAME_OVER
		var tally := _terminal_tally_by_seat()
		_result = {
			"completed": false,
			"mode": _mode,
			"level_reached": _level_id,
			"score": _result_score(),
			"money": _result_money(),
			"seat_progression": _public_seat_progression(),
			"profile_stats": _public_profile_stats(),
			"tally_by_seat": tally,
			"retired": _retired,
			"winner_seat_id": -1,
			"level_100_score": _level_100_milestone_score,
			"tick": _tick,
		}


func _update_pickups() -> void:
	# Compatibility entry point for focused tests and non-dispatcher callers.
	# Retail dispatchers call these two passes at distinct positions.
	_resolve_pickup_collisions()
	_update_pickup_motion()


func _find_available_pickup_slot() -> int:
	# The retail bonus allocator scans its 150 fixed records from slot zero.
	# Collected/expired records are immediately reusable, before dictionary
	# compaction later in the dispatcher.
	var occupied := PackedByteArray()
	occupied.resize(BONUS_POOL_SLOT_COUNT)
	var unslotted_count := 0
	for pickup_value in _pickups:
		var pickup: Dictionary = pickup_value
		if bool(pickup.get("expired", false)):
			continue
		var slot_index := int(pickup.get("pickup_slot", -1))
		if slot_index >= 0 and slot_index < BONUS_POOL_SLOT_COUNT:
			occupied[slot_index] = 1
		else:
			# Compatibility for focused tests and pre-slot replay objects.
			unslotted_count += 1
	for slot_index in range(BONUS_POOL_SLOT_COUNT):
		if unslotted_count > 0 and occupied[slot_index] == 0:
			occupied[slot_index] = 1
			unslotted_count -= 1
	for slot_index in range(BONUS_POOL_SLOT_COUNT):
		if occupied[slot_index] == 0:
			return slot_index
	return -1


func _pickups_in_slot_order() -> Array:
	var ordered := _pickups.duplicate()
	ordered.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_slot := int(left.get("pickup_slot", BONUS_POOL_SLOT_COUNT))
		var right_slot := int(right.get("pickup_slot", BONUS_POOL_SLOT_COUNT))
		if left_slot == right_slot:
			return int(left.get("id", 0)) < int(right.get("id", 0))
		return left_slot < right_slot
	)
	return ordered


func _pickup_seat_scan_order() -> Array:
	if _mode == MODE_COOP:
		# Simultaneous co-op is a remake mode; retain its fair two-seat analogue.
		var first_seat := _random_int(2)
		return [first_seat, 1 - first_seat]
	return [0]


func _resolve_pickup_collisions() -> void:
	for seat_value in _pickup_seat_scan_order():
		var seat_id := int(seat_value)
		if seat_id < 0 or seat_id >= _players.size():
			continue
		var player: Dictionary = _players[seat_id]
		if not bool(player.active) or not bool(player.alive):
			continue
		var progression := _progression_for_seat(seat_id)
		var mirrored := false
		if int(progression.get("mirror_ticks", 0)) > 0:
			# FUN_005834B0 chooses once before this seat's complete pool scan.
			mirrored = (_rng.next_u32() & 0x1ff) >= 256
		var target := _mirror_collision_proxy(player, mirrored)
		for pickup_value in _pickups_in_slot_order():
			var pickup: Dictionary = pickup_value
			if bool(pickup.get("expired", false)):
				continue
			var pickup_rect := {
				"x_fp": int(pickup.x_fp),
				"y_fp": int(pickup.y_fp),
				"width": int(pickup.get("width", 20)),
				"height": int(pickup.get("height", 20)),
				"mask_id": String(pickup.get("mask_id", "")),
				"mask_required": bool(pickup.get("mask_required", false)),
			}
			for mask_key in [
				"mask_source_x",
				"mask_source_y",
				"mask_source_width",
				"mask_source_height",
			]:
				if pickup.has(mask_key):
					pickup_rect[mask_key] = pickup[mask_key]
			if _objects_collide(pickup_rect, target):
				pickup.expired = true
				_apply_pickup_dictionary(pickup, seat_id)
				_emit_event("pickup_collected", {
					"seat_id": seat_id,
					"pickup_kind": String(pickup.kind),
					"pickup_variant": int(pickup.get("variant", 0)),
					"entity_id": int(pickup.id),
					"x_fp": int(pickup.x_fp),
					"y_fp": int(pickup.y_fp),
				})
				if _phase == PHASE_BONUS_MODE:
					return


func _update_pickup_motion() -> void:
	for pickup_value in _pickups_in_slot_order():
		var pickup: Dictionary = pickup_value
		if bool(pickup.get("expired", false)):
			continue
		pickup.animation_countdown_fp = int(
			pickup.get("animation_countdown_fp", 3 * FP_ONE)
		) - _scaled_simulation_delta(FP_ONE)
		if int(pickup.animation_countdown_fp) < 0:
			pickup.animation_countdown_fp = int(
				pickup.get("animation_period_fp", 3 * FP_ONE)
			)
			pickup.animation_frame = posmod(
				int(pickup.get("animation_frame", 0)) + 1,
				10
			)
		_update_pickup_mask_rect(pickup)
		pickup.x_fp = int(pickup.x_fp) + _scaled_simulation_delta(
			int(pickup.get("velocity_x_fp", 0))
		)
		pickup.y_fp = int(pickup.y_fp) + _scaled_simulation_delta(
			int(pickup.get("velocity_y_fp", 0))
		)


func _apply_pickup(kind: String, seat_id: int = 0) -> void:
	_apply_pickup_dictionary({"kind": kind, "effect_key": kind}, seat_id)


func _apply_pickup_dictionary(pickup: Dictionary, seat_id: int = 0) -> void:
	var progression := _progression_for_seat(seat_id)
	if pickup.has("bonus_type"):
		_apply_retail_bonus_type(int(pickup.bonus_type), progression, seat_id)
		return
	var kind := String(pickup.get("effect_key", pickup.get("kind", "")))
	match kind:
		"warp_gem":
			progression.gem_count = int(progression.get("gem_count", 0)) + 1
			progression.rank_markers = int(progression.rank_markers) | int(
				pickup.get("gem_color_bit", 0)
			)
			var gem_score := 5000 * int(progression.get("score_multiplier", 1))
			progression.score = int(progression.score) + gem_score
			var pitch := 22000 + _random_int(10000)
			if int(progression.rank_markers) == 0x3f:
				progression.auto_fire = true
				progression.auto_fire_delay_ms = SUPER_AUTO_FIRE_REPEAT_DELAY_MS
				_set_upgrade(progression, "super_autofire", 1)
				progression.super_autofire_message_ticks = 3 * TICKS_PER_SECOND + 1
			_emit_event("warp_gem_collected", {
				"seat_id": seat_id,
				"variant": int(pickup.get("variant", 0)),
				"rank_markers": int(progression.rank_markers),
				"gem_count": int(progression.gem_count),
				"score": gem_score,
				"presentation_pitch": pitch,
			})
		"money":
			progression.money = int(progression.money) + 25
		"armour":
			progression.armour_fp = min(
				MAX_ARMOUR_CHARGES * FP_ONE,
				int(progression.armour_fp) + FP_ONE
			)
		"letter":
			var letters := "EXTRA"
			var current := String(progression.extra_letters)
			if current.length() < letters.length():
				progression.extra_letters = current + letters[current.length()]
			else:
				progression.lives = mini(MAX_FIGHTERS, int(progression.lives) + 1)
				progression.extra_letters = ""
		"bonus_time":
			progression.bonus_time = int(progression.bonus_time) + 5


func _apply_retail_bonus_type(
	bonus_type: int,
	progression: Dictionary,
	seat_id: int
) -> void:
	if bonus_type >= 0 and bonus_type <= 4:
		_apply_letter_bonus(bonus_type, progression, seat_id)
		return
	match bonus_type:
		5:
			var replacement := _select_retail_bonus(5)
			_apply_retail_bonus_type(int(replacement.id), progression, seat_id)
		6:
			_enter_bonus_mode_boundary("memory_station", progression, seat_id)
		7:
			progression.score_multiplier = 2
			progression.score_multiplier_ticks = _bonus_duration_ticks(progression)
		8:
			progression.score_multiplier = 5
			progression.score_multiplier_ticks = _bonus_duration_ticks(progression)
		9:
			_add_capacity_or_score(progression)
		10:
			if int(progression.speed_fp) < int(_difficulty.player_speed_cap_fp):
				progression.speed_fp = mini(
					int(_difficulty.player_speed_cap_fp),
					int(progression.speed_fp) + int(_difficulty.player_speed_upgrade_fp)
				)
			else:
				_add_bonus_score(progression, 25000)
		11:
			progression.shield_ticks = _bonus_duration_ticks(progression)
		12, 13, 14:
			_equip_bonus_weapon(progression, bonus_type - 12)
		15:
			_apply_warp_bonus(progression, seat_id)
		16:
			progression.scoop_ticks = _bonus_duration_ticks(progression)
			progression.scoop_slots = 2
		17:
			_equip_bonus_weapon(progression, 3)
		18:
			if (
				bool(progression.auto_fire)
				or int(progression.upgrades.get("super_autofire", 0)) > 0
			):
				_add_bonus_score(progression, 25000)
			else:
				if seat_id >= 0 and seat_id < _players.size():
					_players[seat_id].auto_fire_deadline_ms = _simulation_milliseconds()
				progression.auto_fire = true
				progression.auto_fire_delay_ms = AUTO_FIRE_REPEAT_DELAY_MS
		19:
			_bomb_clear_enemies("gem_bomb", seat_id)
		20:
			# Meteor Storm destroys every live falling bonus before optionally
			# creating its earned x2/x5 pickup.
			_pickups.clear()
			if int(progression.upgrades.get("meteor_storm_multiplier_enabled", 0)) > 0:
				_spawn_meteor_multiplier_bonus()
			_enter_bonus_mode_boundary("meteor_storm", progression, seat_id)
		21:
			_add_armour_or_score(progression, 25000)
		22, 23, 24:
			_apply_sucker_bonus(progression, bonus_type - 22, seat_id)
		25:
			progression.mirror_ticks = _bonus_duration_ticks(progression)
			if seat_id >= 0 and seat_id < _players.size():
				_players[seat_id].mirror_anchor_x_fp = int(_players[seat_id].x_fp)
		26:
			_bomb_clear_enemies("money_bomb", seat_id)
		27:
			_add_life_armour_or_score(progression, 1000000)
		28:
			var maximum := int(_difficulty.bonus_time_max)
			if int(progression.bonus_time) < maximum:
				progression.bonus_time = int(progression.bonus_time) + 5
			else:
				progression.bonus_time = maximum
				_add_bonus_score(progression, 25000)
		29:
			_add_money_bonus(progression, 10)
		30:
			_add_money_bonus(progression, 50)
		31:
			_add_money_bonus(progression, 100)
		32:
			_add_money_bonus(progression, 200)
		33:
			_apply_money_doubler(progression)
		34:
			progression.drunk_ticks = _bonus_duration_ticks(progression)
		35:
			# Freeze's absolute retail deadline remains live at equality.
			progression.freeze_ticks = 10 * TICKS_PER_SECOND + 1
		36:
			if int(progression.bullet_speed_fp) >= 2 * FP_ONE:
				progression.bullet_speed_fp = 2 * FP_ONE
				_add_bonus_score(progression, 25000)
			else:
				progression.bullet_speed_fp = int(progression.bullet_speed_fp) + 6554


func _bonus_duration_ticks(progression: Dictionary) -> int:
	# Retail deadlines remain active at exact equality.
	return maxi(0, int(progression.bonus_time)) * TICKS_PER_SECOND + 1


func _enter_bonus_mode_boundary(
	mode_id: String,
	progression: Dictionary,
	seat_id: int
) -> void:
	var suspended_combat_hash := _combat_state_hash()
	progression.special_mode = mode_id
	_bonus_mode_owner_seat_id = seat_id
	_bonus_action_queue.clear()
	_bonus_actions_this_tick.clear()
	_bonus_action_last_target_tick = [-1, -1]
	_bonus_mode_transition_until_ms = 0
	_bonus_mode_completion.clear()
	_pending_gem_drop_transition = false
	_gem_drop_source_mode = ""
	_gem_drop_super = false
	var controller_events: Array = []
	match mode_id:
		"memory_station":
			var entered: Dictionary = _memory_station.enter(
				seat_id,
				progression,
				_rng,
				_tick,
				_simulation_milliseconds()
			)
			if not bool(entered.get("ok", false)):
				progression.special_mode = ""
				_bonus_mode_owner_seat_id = -1
				_emit_event("bonus_mode_controller_error", {
					"special_mode": mode_id,
					"reason": String(entered.get("error", _memory_station.get_last_error())),
				})
				return
			controller_events = entered.get("events", [])
			var controller_snapshot := _memory_station.snapshot()
			progression.special_mode_ticks = _milliseconds_to_ticks_ceil(
				maxi(0, int(controller_snapshot.get("remaining_ms", 0)))
			)
		"meteor_storm":
			var player: Dictionary = _players[clampi(seat_id, 0, _players.size() - 1)]
			var meteor_progression := progression.duplicate(true)
			meteor_progression["ship_x"] = float(int(player.x_fp)) / FP_ONE
			meteor_progression["ship_y"] = float(int(player.y_fp)) / FP_ONE
			meteor_progression["fighter_id"] = "fighter%d" % (seat_id + 1)
			meteor_progression["fighter_frame_index"] = int(
				player.get("mask_frame", 0)
			)
			meteor_progression["player_move_speed"] = (
				float(int(progression.get("speed_fp", 4 * FP_ONE))) / FP_ONE
			)
			meteor_progression["max_money"] = MAX_MONEY
			meteor_progression["parent_state_hash"] = suspended_combat_hash
			var entered: Dictionary = _meteor_storm.enter(
				seat_id,
				meteor_progression,
				_rng,
				_tick,
				_simulation_milliseconds()
			)
			if not bool(entered.get("ok", false)):
				progression.special_mode = ""
				_bonus_mode_owner_seat_id = -1
				_emit_event("bonus_mode_controller_error", {
					"special_mode": mode_id,
					"reason": String(entered.get("error", _meteor_storm.get_last_error())),
				})
				return
			if seat_id >= 0 and seat_id < _profile_stats_by_seat.size():
				_profile_stats_by_seat[seat_id].meteor_current_score = 0
			controller_events = entered.get("events", [])
			var controller_snapshot := _meteor_storm.snapshot()
			progression.special_mode_ticks = _milliseconds_to_ticks_ceil(
				maxi(0, int(controller_snapshot.get("intro_remaining_ms", 0)))
			)
		_:
			progression.special_mode = ""
			_bonus_mode_owner_seat_id = -1
			return
	_bonus_mode_until_tick = _tick + int(progression.special_mode_ticks)
	_phase = PHASE_BONUS_MODE
	_forward_bonus_controller_events(controller_events)
	_emit_event("bonus_mode_boundary_started", {
		"seat_id": seat_id,
		"special_mode": mode_id,
		"until_tick": _bonus_mode_until_tick,
		"music_key": "memory" if mode_id == "memory_station" else "meteor",
		"voice_key": mode_id,
		"x_fp": (FIELD_WIDTH >> 1) * FP_ONE,
		"y_fp": (FIELD_HEIGHT >> 1) * FP_ONE,
	})


func _add_bonus_score(progression: Dictionary, base_score: int) -> void:
	progression.score = int(progression.score) + (
		base_score * int(progression.get("score_multiplier", 1))
	)


func _add_capacity_or_score(progression: Dictionary) -> void:
	if int(progression.bullet_capacity) < MAX_PROJECTILE_CAPACITY:
		progression.bullet_capacity = int(progression.bullet_capacity) + 1
	else:
		_add_bonus_score(progression, 25000)


func _add_armour_or_score(progression: Dictionary, fallback_score: int) -> void:
	if int(progression.armour_fp) < MAX_ARMOUR_CHARGES * FP_ONE:
		progression.armour_fp = int(progression.armour_fp) + FP_ONE
	else:
		_add_bonus_score(progression, fallback_score)


func _add_life_armour_or_score(progression: Dictionary, fallback_score: int) -> void:
	if int(progression.lives) < MAX_FIGHTERS:
		progression.lives = int(progression.lives) + 1
	elif int(progression.armour_fp) < MAX_ARMOUR_CHARGES * FP_ONE:
		progression.armour_fp = int(progression.armour_fp) + FP_ONE
	else:
		_add_bonus_score(progression, fallback_score)


func _apply_letter_bonus(letter_id: int, progression: Dictionary, seat_id: int = -1) -> void:
	# Retail letter case (dispatcher 0x00571c60): scoring the 100-point award
	# is gated on the letter flag already being set (a duplicate collect); a
	# fresh collect only sets the flag. Both paths advance the two
	# strict-consecutive chain registers and run the completion checks.
	var letter := String(LETTER_FORWARD_SEQUENCE[letter_id])
	if (int(progression.letter_bits) & (1 << letter_id)) != 0:
		_add_bonus_score(progression, LETTER_COLLECT_SCORE)
	progression.letter_bits = int(progression.letter_bits) | (1 << letter_id)
	progression.extra_letters = _letters_from_bits(int(progression.letter_bits))
	match letter_id:
		0:
			# E is the reverse-chain terminal, then seeds the forward chain.
			if String(progression.get("letter_reverse_chain", " ")) == "X":
				_award_letter_sequence(progression, "artxe", seat_id)
			progression.letter_reverse_chain = "E"
			progression.letter_forward_chain = "E"
		4:
			# A seeds the reverse chain, then terminates the forward chain.
			progression.letter_reverse_chain = "A"
			if String(progression.get("letter_forward_chain", " ")) == "R":
				_award_letter_sequence(progression, "extra", seat_id)
			progression.letter_forward_chain = "A"
		_:
			var reverse_predecessor := String({1: "T", 2: "R", 3: "A"}[letter_id])
			var forward_predecessor := String({1: "E", 2: "X", 3: "T"}[letter_id])
			progression.letter_reverse_chain = (
				letter
				if String(progression.get("letter_reverse_chain", " ")) == reverse_predecessor
				else " "
			)
			progression.letter_forward_chain = (
				letter
				if String(progression.get("letter_forward_chain", " ")) == forward_predecessor
				else " "
			)
	if int(progression.letter_bits) == 0x1f:
		# All five collected: the award repeats on every later letter because
		# retail never clears the five flags, only the chain registers.
		progression.letter_forward_chain = " "
		progression.letter_reverse_chain = " "
		if int(progression.lives) < MAX_FIGHTERS:
			progression.lives = int(progression.lives) + 1
			progression.bonus_time = mini(
				int(_difficulty.bonus_time_max),
				int(progression.bonus_time) + LETTER_ALL_COLLECTED_BONUS_TIME
			)
			_emit_letter_event("letters_all_collected", "fighter", seat_id)
		elif int(progression.armour_fp) < MAX_ARMOUR_CHARGES * FP_ONE:
			progression.armour_fp = int(progression.armour_fp) + FP_ONE
			_emit_letter_event("letters_all_collected", "armour", seat_id)
		else:
			_add_bonus_score(progression, LETTER_ALL_COLLECTED_SCORE)
			_emit_letter_event("letters_all_collected", "score", seat_id)


func _award_letter_sequence(
	progression: Dictionary,
	sequence_kind: String,
	seat_id: int
) -> void:
	# Completing a strict consecutive sequence fills fighters and armour to
	# their caps; when both are already capped the SUPER variant awards the
	# traced score instead (multiplier applies through _add_bonus_score).
	if (
		int(progression.lives) < MAX_FIGHTERS
		or int(progression.armour_fp) < MAX_ARMOUR_CHARGES * FP_ONE
	):
		progression.lives = MAX_FIGHTERS
		progression.armour_fp = MAX_ARMOUR_CHARGES * FP_ONE
		_emit_letter_event("letter_sequence_completed", sequence_kind, seat_id)
	else:
		_add_bonus_score(progression, LETTER_SEQUENCE_SUPER_SCORE)
		_emit_letter_event(
			"letter_sequence_completed", "super_" + sequence_kind, seat_id
		)


func _emit_letter_event(kind: String, award: String, seat_id: int) -> void:
	_emit_event(kind, {"award": award, "seat_id": seat_id})


func _letters_from_bits(bits: int) -> String:
	var result := ""
	var letters := "EXTRA"
	for letter_id in range(5):
		if (bits & (1 << letter_id)) != 0:
			result += letters[letter_id]
	return result


func _equip_bonus_weapon(progression: Dictionary, weapon_id: int) -> void:
	if int(progression.weapon_id) == weapon_id:
		_add_capacity_or_score(progression)
	else:
		progression.weapon_id = weapon_id


func _apply_warp_bonus(progression: Dictionary, seat_id: int = 0) -> void:
	_raise_warp_bonus_progression(progression)
	# Type 15 owns the four-pass skip flag. The ordinary level-4 completion
	# enters the same mode-13 warp without that flag.
	_request_warp_transition("bonus_type_15", seat_id)


func _raise_warp_bonus_progression(progression: Dictionary) -> void:
	progression.warp_fp = mini(8 * FP_ONE, int(progression.warp_fp) + (FP_ONE >> 1))
	progression.warp_companion = mini(75, int(progression.warp_companion) + 2)
	_set_upgrade(progression, "warp", 1)


func _apply_level_four_warp_upgrade(progression: Dictionary) -> void:
	progression.warp_fp = mini(8 * FP_ONE, int(progression.warp_fp) + (FP_ONE >> 1))
	progression.warp_companion = mini(60, int(progression.warp_companion) + 2)


func _apply_sucker_bonus(
	progression: Dictionary,
	subtype: int,
	seat_id: int = -1
) -> void:
	if int(progression.bullet_capacity) > 4:
		progression.bullet_capacity = int(progression.bullet_capacity) - 1
	if int(progression.weapon_id) > 0:
		progression.weapon_id = int(progression.weapon_id) - 1
	progression.speed_fp = maxi(
		int(_difficulty.player_base_speed_fp),
		int(progression.speed_fp) - int(_difficulty.player_speed_upgrade_fp)
	)
	progression.bonus_time = maxi(
		int(_difficulty.bonus_time_floor),
		int(progression.bonus_time) - 5
	)
	var bit := 1 << subtype
	progression.sucker_bits = int(progression.sucker_bits) | bit
	var count_key := "sucker_%d_count" % subtype
	var count := int(progression.upgrades.get(count_key, 0)) + 1
	_set_upgrade(progression, count_key, count)
	if count % 3 == 0:
		_set_upgrade(
			progression,
			["blue_money", "gem_counter", "meteor_storm_multiplier_enabled"][subtype],
			1
		)
		if subtype == 0 and seat_id >= 0:
			var seat_flags := _match_persistent_flags_for_seat(seat_id)
			seat_flags.only_blue_coins_active = true
	if int(progression.sucker_bits) == 7:
		progression.weapon_id = maxi(4, int(progression.weapon_id))
		progression.bullet_capacity = maxi(25, int(progression.bullet_capacity))
		progression.speed_fp = maxi(
			int(progression.speed_fp),
			int(_difficulty.player_base_speed_fp)
			+ 10 * int(_difficulty.player_speed_upgrade_fp)
		)
		progression.bonus_time = maxi(30, int(progression.bonus_time))
		progression.sucker_bits = 0


func _add_money_bonus(progression: Dictionary, amount: int) -> void:
	if int(progression.money) + amount > MAX_MONEY:
		progression.money = MAX_MONEY
		_add_bonus_score(progression, amount * 10)
	else:
		progression.money = int(progression.money) + amount


func _spawn_meteor_multiplier_bonus() -> void:
	var pickup_slot := _find_available_pickup_slot()
	if pickup_slot < 0:
		return
	var bonus_type := 7 if _random_int(100) < 50 else 8
	var bonuses: Array = _catalog.get("bonuses", [])
	if bonuses.size() != 37:
		return
	var bonus: Dictionary = bonuses[bonus_type]
	var retail_left := 64 + _random_int(FIELD_WIDTH - 80 - 64)
	var velocity_y_fp := _random_retail_float_fp(1.0, 2.0)
	var animation_period_fp := _random_retail_float_fp(3.0, 7.0)
	var animation_frame := _random_int(5)
	_pickups.append({
		"id": _allocate_entity_id(),
		"pickup_slot": pickup_slot,
		"kind": String(bonus.effect_key),
		"effect_key": String(bonus.effect_key),
		"bonus_type": bonus_type,
		"source_y": int(bonus.source_y),
		"variant": 0,
		"animation_frame": animation_frame,
		"animation_period_fp": animation_period_fp,
		"animation_countdown_fp": animation_period_fp,
		# Convert retail 20-pixel top-left coordinates to center coordinates.
		"x_fp": (retail_left + 10) * FP_ONE,
		"y_fp": -290 * FP_ONE,
		"velocity_x_fp": 0,
		"velocity_y_fp": velocity_y_fp,
		"width": int(bonus.width),
		"height": int(bonus.height),
		"expired": false,
	})


func _apply_money_doubler(progression: Dictionary) -> void:
	if int(progression.money) >= 450000:
		return
	var doubled := int(progression.money) * 2
	if doubled > MAX_MONEY:
		progression.money = MAX_MONEY
		_add_bonus_score(progression, 2 * MAX_MONEY)
	else:
		progression.money = doubled
	if doubled == 0:
		progression.bonus_time = mini(
			int(_difficulty.bonus_time_max),
			int(progression.bonus_time) + 30
		)


func _bomb_clear_enemies(cause: String, killer_seat: int) -> void:
	for enemy_value in _enemies:
		var enemy: Dictionary = enemy_value
		if bool(enemy.dead) or int(enemy.get("behavior_state_id", 0)) in [5, 8, 9, 12, 18]:
			continue
		enemy.dead = true
		_qualifying_kills_this_tick += 1
		_record_enemy_killed(killer_seat)
		_emit_event("enemy_destroyed", {
			"entity_id": int(enemy.id),
			"enemy_id": int(enemy.id),
			"enemy_sheet": String(enemy.get("sprite", "alien001")),
			"cause": cause,
			"score": 0,
			"cash": 0,
			"x_fp": int(enemy.x_fp),
			"y_fp": int(enemy.y_fp),
		})


func _remove_expired_entities() -> void:
	var surviving_enemies: Array = []
	for enemy in _enemies:
		if not bool(enemy.dead):
			surviving_enemies.append(enemy)
	_enemies = surviving_enemies
	_reconcile_ordinary_counter_for_expired_projectiles()
	var surviving_projectiles: Array = []
	for projectile in _projectiles:
		if not bool(projectile.expired):
			surviving_projectiles.append(projectile)
		else:
			_release_common_projectile_slot(projectile)
			if _is_rocket_missile(projectile):
				_release_rocket_target_reservation(projectile)
	_projectiles = surviving_projectiles
	var surviving_pickups: Array = []
	for pickup in _pickups:
		# Retail expires at top-left y > H+30. A 20-pixel center survives
		# equality at H+40.
		if not bool(pickup.expired) and int(pickup.y_fp) <= 640 * FP_ONE:
			surviving_pickups.append(pickup)
	_pickups = surviving_pickups


func _reconcile_ordinary_counter_for_expired_projectiles() -> void:
	for seat_id in range(_ordinary_projectile_counter_adjustment_by_seat.size()):
		var prior_raw_count := 0
		var surviving_raw_count := 0
		var expired_contributions: Array[int] = []
		for projectile_value in _player_projectiles_in_slot_order():
			var projectile := projectile_value as Dictionary
			if (
				int(projectile.get("owner_id", -1)) != seat_id
				or _is_rocket_missile(projectile)
			):
				continue
			var contribution := maxi(
				0,
				int(projectile.get("capacity_contribution", 1))
			)
			prior_raw_count += contribution
			if bool(projectile.get("expired", false)):
				expired_contributions.append(contribution)
			else:
				surviving_raw_count += contribution
		if expired_contributions.is_empty():
			continue
		var retail_count := maxi(
			0,
			prior_raw_count
			+ int(_ordinary_projectile_counter_adjustment_by_seat[seat_id])
		)
		for contribution in expired_contributions:
			retail_count = maxi(0, retail_count - contribution)
		_ordinary_projectile_counter_adjustment_by_seat[seat_id] = (
			retail_count - surviving_raw_count
		)


func _check_level_end() -> void:
	if _phase != PHASE_LEVEL:
		return
	if _is_retail_big_boss_level():
		return
	if (
		not _level_resolved
		and _tick - _level_watchdog_start_tick > LEVEL_WATCHDOG_TICKS
	):
		_begin_level_resolution("watchdog")
	if not _level_resolved or _tick <= _level_resolution_tick:
		return
	var level: Dictionary = _level_data_for(_level_id)
	if _level_is_mode_three_bonus(level):
		_begin_level_eight_results()
		return
	_emit_event("level_completed", {
		"level_id": _level_id,
		"x_fp": (FIELD_WIDTH >> 1) * FP_ONE,
		"y_fp": (FIELD_HEIGHT >> 1) * FP_ONE,
	})
	if _mode == MODE_TIME_TRIAL:
		# Time Trial has no shop, warp, or campaign terminal: the loader simply
		# advances to the next file and the clock decides when the run ends.
		_begin_get_ready(_level_id + 1)
		return
	if bool(level.shop_after):
		# The special-level completion raises the two warp progression fields and
		# enters full mode 13. It does not own the four-pass type-15 skip flag.
		_apply_level_four_warp_upgrade(_active_warp_progression())
		_begin_warp(false, "level_four_completion", _turn_seat)
		return
	if _level_id >= _end_level_id:
		_complete_campaign()
		return
	_begin_get_ready(_level_id + 1)


func _begin_level_eight_results() -> void:
	if _level_eight_result_initialized:
		return
	var timing: Dictionary = _level_eight_contract.get("timing_and_flow", {})
	var rewards: Dictionary = _level_eight_contract.get("rewards", {})
	var reveal: Dictionary = rewards.get("reveal_countdown", {})
	var now_ms := _simulation_milliseconds()
	_level_eight_result_initialized = true
	_level_eight_result_deadline_ms = now_ms + int(
		timing.get("result_initial_deadline_ms", 4000)
	)
	_level_eight_reveal_deadline_ms = now_ms
	_level_eight_reveal_countdown = int(reveal.get("initial", 3))
	for counters_value in _level_eight_result_players:
		var counters: Dictionary = counters_value
		counters.displayed_hits = 0
		counters.perfect_awarded = false
		counters.last_hit_score = 0
		counters.perfect_reward = 0
		var seat_id := int(counters.get("seat_id", -1))
		if (
			bool(counters.get("participating", false))
			and seat_id >= 0
			and seat_id < _profile_stats_by_seat.size()
		):
			var stats: Dictionary = _profile_stats_by_seat[seat_id]
			stats.bonus_rounds = int(stats.get("bonus_rounds", 0)) + 1
	_clear_projectiles()
	_pickups.clear()
	_emit_event("level_completed", {
		"level_id": _level_id,
		"x_fp": (FIELD_WIDTH >> 1) * FP_ONE,
		"y_fp": (FIELD_HEIGHT >> 1) * FP_ONE,
	})
	_emit_event("level_eight_results_started", {
		"header": String(timing.get("result_header", LEVEL_EIGHT_RESULT_HEADER)),
		"deadline_ms": _level_eight_result_deadline_ms,
		"reveal_deadline_ms": _level_eight_reveal_deadline_ms,
		"players": _public_level_eight_result_players(),
	})


func _step_level_eight_results() -> void:
	var rewards: Dictionary = _level_eight_contract.get("rewards", {})
	var reveal: Dictionary = rewards.get("reveal_countdown", {})
	var initial_countdown := int(reveal.get("initial", 3))
	var old_countdown := _level_eight_reveal_countdown
	_level_eight_reveal_countdown = old_countdown - 1
	var now_ms := _simulation_milliseconds()
	if old_countdown == 0:
		_level_eight_reveal_countdown = initial_countdown
		var revealed_any := false
		for seat_id in range(_level_eight_result_players.size()):
			var counters: Dictionary = _level_eight_result_players[seat_id]
			if (
				not bool(counters.get("participating", false))
				or int(counters.get("displayed_hits", 0))
				>= int(counters.get("actual_hits", 0))
			):
				continue
			counters.displayed_hits = int(counters.displayed_hits) + 1
			var progression := _progression_for_seat(seat_id)
			var score := int(rewards.get("hit_reveal_base_score", 500)) * int(
				progression.get("score_multiplier", 1)
			)
			progression.score = int(progression.score) + score
			counters.last_hit_score = score
			revealed_any = true
			_emit_event("level_eight_hit_revealed", {
				"seat_id": seat_id,
				"displayed_hits": int(counters.displayed_hits),
				"actual_hits": int(counters.actual_hits),
				"total_targets": int(counters.total_targets),
				"misses": maxi(0, int(counters.total_targets) - int(counters.actual_hits)),
				"score": score,
			})
		if revealed_any:
			_level_eight_reveal_deadline_ms = now_ms + int(
				rewards.get("reveal_deadline_extension_ms", 1000)
			)

	# The executable's scan retains the last eligible session. Therefore P1 is
	# selected on an update where both sessions become eligible, while P0's
	# independent one-shot remains available on the next update.
	var perfect_candidate := -1
	if now_ms > _level_eight_reveal_deadline_ms:
		for seat_id in range(_level_eight_result_players.size()):
			var counters: Dictionary = _level_eight_result_players[seat_id]
			if (
				bool(counters.get("participating", false))
				and not bool(counters.get("perfect_awarded", false))
				and int(counters.get("total_targets", 0)) > 0
				and int(counters.get("displayed_hits", 0))
				>= int(counters.get("total_targets", 0))
			):
				perfect_candidate = seat_id
	if perfect_candidate >= 0:
		_award_level_eight_perfect(perfect_candidate, now_ms)

	if now_ms > _level_eight_result_deadline_ms:
		_finish_level_eight_results()


func _award_level_eight_perfect(seat_id: int, now_ms: int) -> void:
	var rewards: Dictionary = _level_eight_contract.get("rewards", {})
	var reward_values := _level_eight_reward_values()
	var reward_index := clampi(
		int(_level_eight_perfect_indices[seat_id]),
		0,
		reward_values.size() - 1
	)
	var progression := _progression_for_seat(seat_id)
	var score := int(reward_values[reward_index]) * int(
		progression.get("score_multiplier", 1)
	)
	progression.score = int(progression.score) + score
	var counters: Dictionary = _level_eight_result_players[seat_id]
	counters.perfect_awarded = true
	counters.perfect_reward = score
	_level_eight_perfect_indices[seat_id] = mini(
		reward_values.size() - 1,
		reward_index + 1
	)
	_sync_level_eight_progression_state()
	if seat_id >= 0 and seat_id < _profile_stats_by_seat.size():
		var stats: Dictionary = _profile_stats_by_seat[seat_id]
		var perfect_delta := int(rewards.get("perfect_profile_counter_delta", 1))
		stats.perfect_bonus_rounds = int(
			stats.get("perfect_bonus_rounds", 0)
		) + perfect_delta
		stats.mode_three_perfects = int(
			stats.get("mode_three_perfects", 0)
		) + perfect_delta
		if _level_id == 8:
			stats.level_eight_perfects = int(
				stats.get("level_eight_perfects", 0)
			) + perfect_delta
	_level_eight_result_deadline_ms = now_ms + int(
		rewards.get("result_deadline_extension_ms", 4000)
	)
	_emit_event("level_eight_perfect_awarded", {
		"seat_id": seat_id,
		"reward_index": reward_index,
		"base_reward": int(reward_values[reward_index]),
		"score": score,
		"next_reward_index": int(_level_eight_perfect_indices[seat_id]),
		"deadline_ms": _level_eight_result_deadline_ms,
	})


func _finish_level_eight_results() -> void:
	for seat_id in range(_level_eight_result_players.size()):
		var counters: Dictionary = _level_eight_result_players[seat_id]
		if (
			not bool(counters.get("participating", false))
			or int(counters.get("actual_hits", 0))
			>= int(counters.get("total_targets", 0))
		):
			continue
		_level_eight_perfect_indices[seat_id] = 0
		_emit_event("level_eight_perfect_chain_reset", {
			"seat_id": seat_id,
			"actual_hits": int(counters.actual_hits),
			"total_targets": int(counters.total_targets),
			"next_reward_index": 0,
		})
	_sync_level_eight_progression_state()
	_level_eight_result_initialized = false
	_level_eight_result_deadline_ms = 0
	_level_eight_reveal_deadline_ms = 0
	_level_eight_reveal_countdown = 0
	_apply_level_four_warp_upgrade(_active_warp_progression())
	_begin_warp(false, "level_eight_bonus_results", _turn_seat)


func _sync_level_eight_progression_state() -> void:
	var next_rewards: Array = []
	var reward_values := _level_eight_reward_values()
	for seat_id in range(2):
		next_rewards.append(int(reward_values[clampi(
			int(_level_eight_perfect_indices[seat_id]),
			0,
			reward_values.size() - 1
		)]))
	var progressions: Array = [_shared]
	progressions.append_array(_seat_progression)
	for progression_value in progressions:
		var progression: Dictionary = progression_value
		if progression.is_empty():
			continue
		progression.mode_three_perfect_reward_indices = (
			_level_eight_perfect_indices.duplicate()
		)
		progression.mode_three_next_perfect_rewards = next_rewards.duplicate()
		progression.level_eight_perfect_reward_indices = (
			_level_eight_perfect_indices.duplicate()
		)
		progression.level_eight_next_perfect_rewards = next_rewards.duplicate()


func _begin_get_ready(next_level_id: int) -> void:
	_phase = PHASE_GET_READY
	_warp_owner_seat_id = -1
	_reset_rank_promotion_state()
	_pending_level_id = next_level_id
	_get_ready_until_tick = _tick + GET_READY_TICKS
	_apply_alien_lock_transition_policy("get_ready_transition")
	_clear_non_captured_enemies()
	_clear_projectiles()
	_pickups.clear()
	_emit_event("get_ready_started", {
		"level_id": next_level_id,
		"until_tick": _get_ready_until_tick,
		"x_fp": (FIELD_WIDTH >> 1) * FP_ONE,
		"y_fp": (FIELD_HEIGHT >> 1) * FP_ONE,
	})


func _try_leave_shop() -> void:
	if _phase != PHASE_SHOP:
		return
	if _shop_warp_until_tick > 0 and _tick <= _shop_warp_until_tick:
		return
	for seat_id in range(2):
		if _seat_is_participating(seat_id) and not _shop_ready[seat_id]:
			return
	var active_seat_id := 0
	if _cash_out_full_rank_mask_on_shop_exit(active_seat_id):
		_begin_rank_promotion(active_seat_id)
		return
	_route_after_shop()


func _cash_out_full_rank_mask_on_shop_exit(seat_id: int) -> bool:
	var progression := _progression_for_seat(seat_id)
	if int(progression.rank_markers) != 0x3f:
		return false
	var previous_rank := int(progression.get("rank", 0))
	var rank_cap := int(progression.get("rank_cap", DEFAULT_RANK_CAP))
	var promoted := previous_rank < rank_cap
	progression.rank_markers = 0
	progression.score = int(progression.score) + (
		FULL_RANK_MASK_CASHOUT_SCORE
		* int(progression.get("score_multiplier", 1))
	)
	if promoted:
		progression.rank = previous_rank + 1
		progression.highest_rank = maxi(
			int(progression.get("highest_rank", 0)),
			int(progression.rank)
		)
	_emit_event("shop_rank_mask_cashed_out", {
		"seat_id": seat_id,
		"previous_rank": previous_rank,
		"rank": int(progression.get("rank", previous_rank)),
		"highest_rank": int(progression.get("highest_rank", previous_rank)),
		"rank_cap": rank_cap,
		"promoted": promoted,
		"score_awarded": (
			FULL_RANK_MASK_CASHOUT_SCORE
			* int(progression.get("score_multiplier", 1))
		),
		"x_fp": (FIELD_WIDTH >> 1) * FP_ONE,
		"y_fp": (FIELD_HEIGHT >> 1) * FP_ONE,
	})
	return promoted


func _begin_rank_promotion(seat_id: int) -> void:
	var progression := _progression_for_seat(seat_id)
	var promoted_rank := int(progression.get("rank", 0))
	var bonus_modes: Dictionary = _catalog.get("bonus_modes", {})
	var promotion_contract: Dictionary = bonus_modes.get("rank_promotion", {})
	var rank_contract := _rank_promotion_contract(promoted_rank)
	_phase = PHASE_RANK_PROMOTION
	_rank_promotion_seat_id = seat_id
	_rank_promotion_minimum_tick = _tick + RANK_PROMOTION_MINIMUM_TICKS
	_rank_promotion_timeout_tick = _tick + RANK_PROMOTION_TIMEOUT_TICKS
	_shop_ready = [false, false]
	_emit_event("rank_promotion_started", {
		"seat_id": seat_id,
		"rank": promoted_rank,
		"rank_name": _rank_name(promoted_rank),
		"badge_y": _rank_badge_y(promoted_rank),
		"highest_rank": int(progression.get("highest_rank", 0)),
		"rank_cap": int(progression.get("rank_cap", DEFAULT_RANK_CAP)),
		"minimum_tick": _rank_promotion_minimum_tick,
		"timeout_tick": _rank_promotion_timeout_tick,
		"music_key": String(promotion_contract.get("common_music", "promoted")),
	})
	var voice_queue: Variant = rank_contract.get("queue", [])
	if voice_queue is Array:
		for queue_index in range((voice_queue as Array).size()):
			var cue_value: Variant = (voice_queue as Array)[queue_index]
			if not cue_value is Dictionary:
				continue
			var cue: Dictionary = cue_value
			_emit_event("rank_promotion_voice", {
				"seat_id": seat_id,
				"voice_key": String(cue.get("key", "")),
				"queue_padding_ms": int(cue.get("padding_ms", 0)),
				"queue_index": queue_index,
			})


func _rank_promotion_contract(rank: int) -> Dictionary:
	var bonus_modes_value: Variant = _catalog.get("bonus_modes", {})
	if not bonus_modes_value is Dictionary:
		return {}
	var promotion_value: Variant = (bonus_modes_value as Dictionary).get(
		"rank_promotion",
		{}
	)
	if not promotion_value is Dictionary:
		return {}
	var ranks_value: Variant = (promotion_value as Dictionary).get("ranks", [])
	if not ranks_value is Array or rank < 1 or rank > (ranks_value as Array).size():
		return {}
	var rank_value: Variant = (ranks_value as Array)[rank - 1]
	if not rank_value is Dictionary or int((rank_value as Dictionary).get("rank", 0)) != rank:
		return {}
	return (rank_value as Dictionary).duplicate(true)


func _consume_rank_promotion_firework_rng() -> void:
	if _random_int(100) >= 2:
		return
	var firework_x := 100 + _random_int(FIELD_WIDTH - 200)
	var firework_y := 100 + _random_int(FIELD_HEIGHT - 200)
	var color_rgb := [
		_random_int(255),
		_random_int(255),
		_random_int(255),
	]
	var particle_count := 10 + _random_int(40)
	var palette_index := _random_int(15)
	for particle_index in range(particle_count):
		# FUN_005547d0 consumes one float wrapper draw and five integer draws
		# for every primary particle even though rendering is client-owned.
		_rng.next_float32(0.0, 1.0)
		_random_int(360)
		_random_int(90)
		_random_int(10)
		_random_int(4)
		_random_int(40)
	var has_secondary := _random_int(10) < 2
	if has_secondary:
		# The secondary sparkle record consumes ten more shared-generator words.
		_random_int(255)
		_random_int(255)
		_random_int(255)
		_random_int(20)
		_random_int(15)
		_rng.next_float32(0.0, 1.0)
		_random_int(90)
		_random_int(10)
		_random_int(4)
		_random_int(40)
	var retail_pan_index := 30 + _random_int(70)
	_emit_event("rank_promotion_firework", {
		"seat_id": _rank_promotion_seat_id,
		"x_fp": firework_x * FP_ONE,
		"y_fp": firework_y * FP_ONE,
		"color_rgb": color_rgb,
		"particle_count": particle_count,
		"palette_index": palette_index,
		"secondary": has_secondary,
		"retail_pan_index": retail_pan_index,
		"sfx_key": "explo3",
	})


func _finish_rank_promotion() -> void:
	var promoted_seat_id := _rank_promotion_seat_id
	var next_level_id := _next_level_after_shop()
	_emit_event("rank_promotion_completed", {
		"seat_id": promoted_seat_id,
		"next_level_id": next_level_id,
	})
	_reset_rank_promotion_state()
	_shop_ready = [false, false]
	_route_after_shop()


func _rank_promotion_prompt_is_visible() -> bool:
	if (
		_phase != PHASE_RANK_PROMOTION
		or _rank_promotion_minimum_tick <= 0
		or _tick < _rank_promotion_minimum_tick
	):
		return false
	var elapsed_ticks := _tick - _rank_promotion_minimum_tick
	return int(elapsed_ticks / RANK_PROMOTION_PROMPT_BLINK_TICKS) % 2 == 0


func _reset_rank_promotion_state() -> void:
	_rank_promotion_seat_id = -1
	_rank_promotion_minimum_tick = 0
	_rank_promotion_timeout_tick = 0


func _rank_name(rank: int) -> String:
	if rank < 0 or rank >= RANK_NAMES.size():
		return "RANK %d" % rank
	return String(RANK_NAMES[rank])


func _rank_badge_y(rank: int) -> int:
	if rank < 0 or rank >= RANK_BADGE_Y.size():
		return 0
	return int(RANK_BADGE_Y[rank])


func _begin_level(next_level_id: int) -> void:
	_commit_accuracy_sample_for_level_entry(next_level_id)
	_level_id = next_level_id
	_apply_endless_progression()
	_boss_entered = false
	_boss_render_snapshot.clear()
	_boss_deferred_entry_events.clear()
	_level_tick = 0
	_phase = PHASE_LEVEL
	_reset_rank_promotion_state()
	_spawned_waves.clear()
	_apply_alien_lock_transition_policy("level_transition")
	_clear_non_captured_enemies()
	_clear_projectiles()
	_initialize_common_projectile_slots()
	_pickups.clear()
	_shop_ready = [false, false]
	_initialize_level_behavior_state()
	if _mode != MODE_COOP:
		_apply_mode_activity()
	for player_value in _players:
		var player: Dictionary = player_value
		if bool(player.active):
			player.alive = true
			player.auto_fire_deadline_ms = _simulation_milliseconds()
			player.invulnerable_ticks = _respawn_invulnerability_ticks()
			player.respawn_ticks = 0
	if _is_retail_big_boss_level() and not _enter_retail_big_boss(false):
		_block_boss_runtime(get_last_error())
	_emit_event("level_started", {
		"level_id": _level_id,
		"end_level_id": _end_level_id,
		"x_fp": (FIELD_WIDTH >> 1) * FP_ONE,
		"y_fp": (FIELD_HEIGHT >> 1) * FP_ONE,
	})


func _level_has_supplemental(level: Dictionary) -> bool:
	if not level.has("authored_lvd"):
		return false
	var records: Array = level.authored_lvd.supplemental_spawn_records_raw_words
	for record_index in range(mini(4, records.size())):
		var record: Array = records[record_index]
		if int(record[0]) > 0:
			return true
	return false


func _apply_mode_activity() -> void:
	for player_value in _players:
		var player: Dictionary = player_value
		var seat_id := int(player.seat_id)
		var progression := _progression_for_seat(seat_id)
		match _mode:
			MODE_SOLO, MODE_TIME_TRIAL:
				player.active = seat_id == 0 and int(progression.lives) > 0
			MODE_COOP:
				player.active = true
		if not bool(player.active):
			player.alive = false


func _can_apply_shop_effect(item: Dictionary, seat_id: int = 0) -> bool:
	var progression := _progression_for_seat(seat_id)
	match String(item.effect):
		"speed_up":
			return int(progression.speed_fp) < int(_difficulty.player_speed_cap_fp)
		"speed_down":
			return int(progression.speed_fp) > int(_difficulty.player_base_speed_fp)
		"bullet_capacity_up":
			return int(progression.bullet_capacity) < MAX_PROJECTILE_CAPACITY
		"equip_weapon":
			return (
				item.has("weapon_id")
				and _weapons_by_id.has(int(item.weapon_id))
				and int(progression.weapon_id) != int(item.weapon_id)
			)
		"enable_autofire":
			return (
				not bool(progression.auto_fire)
				and int(progression.upgrades.get("super_autofire", 0)) == 0
			)
		"armor_up":
			return int(progression.armour_fp) < MAX_ARMOUR_CHARGES * FP_ONE
		"life_up":
			return int(progression.lives) < MAX_FIGHTERS
		"rank_marker_up":
			return int(progression.rank_markers) != 0x3f or not _rank_full_reward_claimed
		"bonus_time_up":
			return int(progression.bonus_time) < int(_difficulty.bonus_time_max)
		"rocket_pack":
			return (
				not _ordnance_contract.is_empty()
				and int(progression.get("rockets", 0)) < 50
			)
		"enable_alien_lock":
			return (
				not _ordnance_contract.is_empty()
				and int(progression.upgrades.get("alien_lock", 0)) == 0
			)
	return true


func _apply_shop_effect(item: Dictionary, seat_id: int = 0) -> void:
	var progression := _progression_for_seat(seat_id)
	var effect := String(item.effect)
	match effect:
		"speed_up":
			progression.speed_fp = min(
				int(_difficulty.player_speed_cap_fp),
				int(progression.speed_fp) + int(_difficulty.player_speed_upgrade_fp)
			)
		"speed_down":
			progression.speed_fp = max(
				int(_difficulty.player_base_speed_fp),
				int(progression.speed_fp) - int(_difficulty.player_speed_upgrade_fp)
			)
		"bullet_capacity_up":
			progression.bullet_capacity = min(
				MAX_PROJECTILE_CAPACITY,
				int(progression.bullet_capacity) + 1
			)
		"equip_weapon":
			progression.weapon_id = int(item.weapon_id)
		"enable_autofire":
			progression.auto_fire = true
		"armor_up":
			progression.armour_fp = min(
				MAX_ARMOUR_CHARGES * FP_ONE,
				int(progression.armour_fp) + FP_ONE
			)
		"life_up":
			progression.lives = mini(MAX_FIGHTERS, int(progression.lives) + 1)
		"buy_secret":
			_apply_secret(progression)
		"rank_marker_up":
			var marker_mask := int(progression.rank_markers)
			if marker_mask == 0x3f:
				progression.score = int(progression.score) + (
					1000000 * int(progression.get("score_multiplier", 1))
				)
				_rank_full_reward_claimed = true
				var seat_flags := _match_persistent_flags_for_seat(seat_id)
				seat_flags.rank_ready = true
			else:
				for marker_bit in [0x20, 0x10, 0x08, 0x04, 0x02, 0x01]:
					if (marker_mask & marker_bit) == 0:
						progression.rank_markers = marker_mask | marker_bit
						break
		"bonus_time_up":
			# Retail pre-checks against 45 but does not clamp the result.
			progression.bonus_time = int(progression.bonus_time) + 5
		"rocket_pack":
			progression.rockets = mini(
				50,
				int(progression.get("rockets", 0)) + 10
			)
		"enable_alien_lock":
			_set_upgrade(progression, "alien_lock", 1)
		"enable_super_autofire":
			_set_upgrade(progression, "super_autofire", 1)
			progression.auto_fire = true
			progression.auto_fire_delay_ms = SUPER_AUTO_FIRE_REPEAT_DELAY_MS
		"clear_profile_shields":
			_set_upgrade(progression, "profile_shields_cleared", 1)
	_set_upgrade(
		progression,
		effect,
		int(progression.upgrades.get(effect, 0)) + 1
	)


func _apply_secret(progression: Dictionary = {}) -> void:
	if progression.is_empty():
		progression = _progression_for_seat(0)
	var secret_id := 30
	if int(progression.get("secret_profile_kind", 0)) != 2:
		var attempts := 0
		while true:
			secret_id = _rng.next_range(30)
			attempts += 1
			var accepted := false
			if bool(progression.get("secret_has_profile", true)):
				var earned: Array = progression.secret_session_earned
				var seen: Array = progression.secret_session_seen
				accepted = int(earned[secret_id]) == 0 or int(seen[secret_id]) == 0
			else:
				accepted = secret_id != _last_secret_id and secret_id != _previous_secret_id
			if accepted or attempts >= 251:
				break
		if bool(progression.get("secret_has_profile", true)):
			var seen: Array = progression.secret_session_seen
			seen[secret_id] = 1
	_previous_secret_id = _last_secret_id
	_last_secret_id = secret_id
	progression.selected_secret_id = secret_id
	_emit_event("shop_secret_selected", {
		"secret_id": secret_id,
		"asset_key": "secret_%02d" % (secret_id + 1),
		"x_fp": (FIELD_WIDTH >> 1) * FP_ONE,
		"y_fp": (FIELD_HEIGHT >> 1) * FP_ONE,
	})


func _set_upgrade(progression: Dictionary, key: String, value: int) -> void:
	var upgrades: Dictionary = progression.upgrades
	upgrades[key] = value


func _create_progression(
	match_config: Dictionary,
	starting_weapon: int,
	seat_id: int = 0
) -> Dictionary:
	var seat_config: Dictionary = {}
	var seats: Array = match_config.get("seats", [])
	if seat_id >= 0 and seat_id < seats.size() and seats[seat_id] is Dictionary:
		seat_config = seats[seat_id]
	var secret_earned: Array = []
	var secret_seen: Array = []
	var supplied_earned: Array = seat_config.get(
		"secret_session_earned",
		match_config.get("secret_session_earned", [])
	)
	for secret_id in range(30):
		secret_earned.append(
			1 if secret_id < supplied_earned.size() and int(supplied_earned[secret_id]) != 0 else 0
		)
		secret_seen.append(0)
	var has_profile := bool(match_config.get("has_profile", true))
	var profile_id := String(seat_config.get("profile_id", ""))
	if profile_id.begins_with("guest"):
		has_profile = false
	var rank_cap := clampi(
		int(seat_config.get("rank_cap", match_config.get("rank_cap", DEFAULT_RANK_CAP))),
		0,
		DEFAULT_RANK_CAP
	)
	var starting_rank := clampi(
		int(seat_config.get("rank", match_config.get("starting_rank", 0))),
		0,
		rank_cap
	)
	var highest_rank := clampi(
		maxi(
			starting_rank,
			int(seat_config.get(
				"highest_rank",
				match_config.get("starting_highest_rank", 0)
			))
		),
		0,
		rank_cap
	)
	var memory_contract: Dictionary = _catalog.get("bonus_modes", {}).get(
		"memory_station",
		{}
	)
	var memory_defaults: Dictionary = memory_contract.get("effect_defaults", {})
	var fighter_config_id := maxi(0, int(seat_config.get(
		"fighter_config_id",
		match_config.get("fighter_config_id", 0)
	)))
	var gem_progress_initial_key := "fighter_config_%d_gem_progress_initial" % fighter_config_id
	var gem_progress_step_key := "fighter_config_%d_gem_progress_step" % fighter_config_id
	var gem_progress_initial := int(seat_config.get(
		"gem_progress",
		match_config.get(
			"starting_gem_progress",
			memory_defaults.get(
				gem_progress_initial_key,
				memory_defaults.get("fighter_config_0_gem_progress_initial", 452)
			)
		)
	))
	var gem_progress_step := maxi(1, int(seat_config.get(
		"gem_progress_step",
		memory_defaults.get(
			gem_progress_step_key,
			memory_defaults.get("fighter_config_0_gem_progress_step", 8)
		)
	)))
	var level_eight_rewards := _level_eight_reward_values()
	var level_eight_next_rewards: Array = []
	for perfect_seat_id in range(2):
		level_eight_next_rewards.append(int(level_eight_rewards[clampi(
			int(_level_eight_perfect_indices[perfect_seat_id]),
			0,
			level_eight_rewards.size() - 1
		)]))
	return {
		"lives": max(0, int(match_config.get("starting_lives", 3))),
		"score": 0,
		"money": max(0, int(match_config.get("starting_money", 0))),
		"rockets": clampi(int(match_config.get("starting_rockets", 0)), 0, 50),
		"score_multiplier": 1,
		"score_multiplier_ticks": 0,
		"weapon_id": starting_weapon,
		"bullet_capacity": BASE_PROJECTILE_CAPACITY,
		"auto_fire": false,
		"auto_fire_delay_ms": AUTO_FIRE_REPEAT_DELAY_MS,
		"armour_fp": 0,
		"shield_ticks": 0,
		"speed_fp": int(_difficulty.player_base_speed_fp),
		"bullet_speed_fp": FP_ONE,
		"upgrades": {},
		"extra_letters": "",
		"letter_bits": 0,
		"letter_forward_chain": " ",
		"letter_reverse_chain": " ",
		"rank_markers": 0,
		"rank": starting_rank,
		"highest_rank": highest_rank,
		"rank_cap": rank_cap,
		"gem_count": 0,
		"bonus_time": int(_difficulty.bonus_time_start),
		"memory_columns": int(memory_contract.get("initial_columns", 4)),
		"memory_rows": int(memory_contract.get("initial_rows", 4)),
		"memory_success_streak": int(memory_contract.get("initial_success_streak", 0)),
		"memory_point_bonus": int(memory_contract.get("initial_point_bonus", 25000)),
		"memory_point_step": int(memory_contract.get("point_bonus_step", 25000)),
		"mode_three_perfect_reward_indices": _level_eight_perfect_indices.duplicate(),
		"mode_three_next_perfect_rewards": level_eight_next_rewards.duplicate(),
		"level_eight_perfect_reward_indices": _level_eight_perfect_indices.duplicate(),
		"level_eight_next_perfect_rewards": level_eight_next_rewards,
		"money_cap": int(memory_defaults.get("money_cap", MAX_MONEY)),
		"bonus_time_max": int(_difficulty.bonus_time_max),
		"lives_max": int(memory_defaults.get("lives_max", MAX_FIGHTERS)),
		"lives_step": int(memory_defaults.get("lives_step", 1)),
		"armour_max_fp": int(memory_defaults.get(
			"armour_max_fp",
			MAX_ARMOUR_CHARGES * FP_ONE
		)),
		"armour_step_fp": int(memory_defaults.get("armour_step_fp", FP_ONE)),
		"bullet_capacity_max": int(memory_defaults.get(
			"bullet_capacity_max",
			MAX_PROJECTILE_CAPACITY
		)),
		"speed_step_fp": int(_difficulty.player_speed_upgrade_fp),
		"speed_cap_fp": int(_difficulty.player_speed_cap_fp),
		"gem_progress": gem_progress_initial,
		"gem_progress_origin": gem_progress_initial,
		"gem_progress_step": gem_progress_step,
		"memory_money_stars": 0,
		"memory_star_floor": int(memory_defaults.get("memory_star_floor", 20)),
		"memory_star_cycle": int(memory_defaults.get("memory_star_cycle", 3)),
		"meteor_distance": int(seat_config.get(
			"meteor_distance",
			match_config.get("starting_meteor_distance", 0)
		)),
		"meteor_streak": int(seat_config.get(
			"meteor_streak",
			match_config.get("starting_meteor_streak", 0)
		)),
		"secret_profile_kind": int(seat_config.get(
			"profile_kind",
			match_config.get("profile_kind", 0)
		)),
		"secret_has_profile": has_profile,
		"secret_session_earned": secret_earned,
		"secret_session_seen": secret_seen,
		"selected_secret_id": -1,
		"start_state_pending": seat_config.get("start_state", {}),
		"scoop_ticks": 0,
		"scoop_slots": 0,
		# Retail starts the warp/malfunction progression at 3.0 with an
		# eight-point companion value; both are live before the first pickup.
		"warp_fp": 3 * FP_ONE,
		"warp_companion": 8,
		"mirror_ticks": 0,
		"drunk_ticks": 0,
		"freeze_ticks": 0,
		"sucker_bits": 0,
		"special_mode": "",
		"special_mode_ticks": 0,
		"super_autofire_message_ticks": 0,
	}


## Applies the profile lock start-state (docs/evidence/PROFILE_LOCKS.md,
## applier 0x0054d440) after the base progression is built. Ordered tier
## overrides are resolved by the evaluator; this consumes the merged result.
func _apply_profile_start_state(progression: Dictionary) -> void:
	var start_state_value: Variant = progression.get("start_state_pending", {})
	progression.erase("start_state_pending")
	if not start_state_value is Dictionary:
		return
	var start_state := start_state_value as Dictionary
	if start_state.is_empty():
		return
	if start_state.has("bullet_capacity"):
		progression.bullet_capacity = clampi(
			int(start_state.bullet_capacity),
			1,
			int(progression.bullet_capacity_max)
		)
	if start_state.has("speed_steps"):
		progression.speed_fp = mini(
			int(progression.speed_cap_fp),
			int(progression.speed_fp)
			+ int(start_state.speed_steps) * int(progression.speed_step_fp)
		)
	if bool(start_state.get("speed_half_max", false)):
		# The 100,000-games package: speed halfway between base and the cap.
		progression.speed_fp = maxi(
			int(progression.speed_fp),
			int(_difficulty.player_base_speed_fp)
			+ (int(progression.speed_cap_fp) - int(_difficulty.player_base_speed_fp)) / 2
		)
	if bool(start_state.get("speed_max", false)):
		# Grouped-best 17,000,000: the Time Trial branch starts at the cap.
		progression.speed_fp = int(progression.speed_cap_fp)
	if bool(start_state.get("auto_fire", false)):
		progression.auto_fire = true
		progression.auto_fire_delay_ms = AUTO_FIRE_REPEAT_DELAY_MS
	if bool(start_state.get("super_auto_fire", false)):
		progression.auto_fire = true
		progression.auto_fire_delay_ms = SUPER_AUTO_FIRE_REPEAT_DELAY_MS
		_set_upgrade(progression, "super_autofire", 1)
	if bool(start_state.get("alien_lock", false)):
		# The talent capstone mirrors the enable_alien_lock shop effect.
		_set_upgrade(progression, "alien_lock", 1)
	if start_state.has("weapon_at_least"):
		progression.weapon_id = maxi(
			int(progression.weapon_id),
			clampi(int(start_state.weapon_at_least), 0, 8)
		)
	if start_state.has("armour_charges"):
		progression.armour_fp = clampi(
			int(start_state.armour_charges) * FP_ONE,
			int(progression.armour_fp),
			int(progression.armour_max_fp)
		)
	if start_state.has("money"):
		progression.money = clampi(
			int(start_state.money),
			0,
			int(progression.money_cap)
		)
	if start_state.has("bonus_time"):
		progression.bonus_time = maxi(
			int(progression.bonus_time),
			int(start_state.bonus_time)
		)
	if bool(start_state.get("bonus_time_half_max", false)):
		progression.bonus_time = maxi(
			int(progression.bonus_time),
			int(progression.bonus_time_max) / 2
		)
	if bool(start_state.get("bonus_time_full_max", false)):
		progression.bonus_time = maxi(
			int(progression.bonus_time),
			int(progression.bonus_time_max)
		)
	if start_state.has("bonus_time_max"):
		# The fastest-Meteor-Storm locks raise the Extra Time ceiling.
		progression.bonus_time_max = maxi(
			int(progression.bonus_time_max),
			int(start_state.bonus_time_max)
		)
	if bool(start_state.get("bullet_speed_up", false)):
		# Lock value: bullet speed raised to the traced 1.25x (0x0077ad08).
		progression.bullet_speed_fp = maxi(
			int(progression.bullet_speed_fp),
			FP_ONE + (FP_ONE >> 2)
		)
	if bool(start_state.get("rank_32_bullet_speed", false)):
		# Terminal-rank package: bullet speed 1.5x (0x00778e88).
		progression.bullet_speed_fp = maxi(
			int(progression.bullet_speed_fp),
			FP_ONE + (FP_ONE >> 1)
		)
	for upgrade_flag in [
		"meteor_storm_multiplier_enabled",
		"gem_counter",
		"secret_counter",
		"missile_stealth",
		"autofire_through_shop",
	]:
		if bool(start_state.get(upgrade_flag, false)):
			_set_upgrade(progression, upgrade_flag, 1)
	# The Time Trial grouped-best branch arms two timed effects for the
	# bonus-time window instead of granting them outright.
	if start_state.has("timed_score_multiplier"):
		progression.score_multiplier = maxi(
			int(progression.get("score_multiplier", 1)),
			int(start_state.timed_score_multiplier)
		)
		progression.score_multiplier_ticks = _bonus_duration_ticks(progression)
	if bool(start_state.get("timed_scoop", false)):
		progression.scoop_ticks = _bonus_duration_ticks(progression)
	progression["time_trial_extra_minute"] = bool(
		start_state.get("time_trial_extra_minute", false)
	)


func _create_match_persistent_flags(
	match_config: Dictionary,
	seat_id: int
) -> Dictionary:
	var seat_config: Dictionary = {}
	var seats: Array = match_config.get("seats", [])
	if seat_id >= 0 and seat_id < seats.size() and seats[seat_id] is Dictionary:
		seat_config = seats[seat_id]
	var rank_ready_value: Variant = seat_config.get("rank_ready", false)
	var only_blue_value: Variant = seat_config.get("only_blue_coins_active", false)
	return {
		"rank_ready": (
			bool(rank_ready_value) if typeof(rank_ready_value) == TYPE_BOOL else false
		),
		"only_blue_coins_active": (
			bool(only_blue_value) if typeof(only_blue_value) == TYPE_BOOL else false
		),
	}


func _match_persistent_flags_for_seat(seat_id: int) -> Dictionary:
	if seat_id < 0 or seat_id >= _match_persistent_flags_by_seat.size():
		return {"rank_ready": false, "only_blue_coins_active": false}
	return _match_persistent_flags_by_seat[seat_id]


func _create_profile_stats(
	match_config: Dictionary = {},
	seat_id: int = -1
) -> Dictionary:
	var seat_config: Dictionary = {}
	var seats: Array = match_config.get("seats", [])
	if seat_id >= 0 and seat_id < seats.size() and seats[seat_id] is Dictionary:
		seat_config = seats[seat_id]
	return {
		"meteor_score": 0,
		"meteor_current_score": 0,
		"bonus_rounds": 0,
		"perfect_bonus_rounds": 0,
		"mode_three_perfects": 0,
		"level_eight_perfects": 0,
		"projectile_objects_fired": 0,
		"rocket_missiles_fired": 0,
		"successful_hits": 0,
		"fastest_level_clear_ticks": 0,
		"best_hit_percent_above_level_25": clampi(
			int(seat_config.get(
				"best_hit_percent_above_level_25",
				match_config.get("best_hit_percent_above_level_25", 0)
			)),
			0,
			100
		),
	}


func _record_player_projectile_fired(seat_id: int) -> void:
	if seat_id < 0 or seat_id >= _profile_stats_by_seat.size():
		return
	var stats: Dictionary = _profile_stats_by_seat[seat_id]
	stats.projectile_objects_fired = int(
		stats.get("projectile_objects_fired", 0)
	) + 1


func _record_rocket_missile_fired(seat_id: int) -> void:
	if seat_id < 0 or seat_id >= _profile_stats_by_seat.size():
		return
	var stats: Dictionary = _profile_stats_by_seat[seat_id]
	stats.rocket_missiles_fired = int(stats.get("rocket_missiles_fired", 0)) + 1


func _record_player_projectile_hit(seat_id: int) -> void:
	if seat_id < 0 or seat_id >= _profile_stats_by_seat.size():
		return
	var stats: Dictionary = _profile_stats_by_seat[seat_id]
	stats.successful_hits = int(stats.get("successful_hits", 0)) + 1


func _commit_accuracy_sample_for_level_entry(next_level_id: int) -> void:
	if next_level_id <= 25:
		return
	var sampled_seats: Array[int] = []
	if _mode == MODE_COOP:
		# Co-op has two simultaneously contributing projectile owners; its
		# cumulative accuracy samples are per seat.
		sampled_seats.assign([0, 1])
	else:
		sampled_seats.append(_turn_seat)
	for seat_id in sampled_seats:
		if not _seat_is_participating(seat_id):
			continue
		var stats: Dictionary = _profile_stats_by_seat[seat_id]
		var fired := int(stats.get("projectile_objects_fired", 0))
		if fired <= 0:
			continue
		var hit_percent := clampi(
			(int(stats.get("successful_hits", 0)) * 100) / fired,
			0,
			100
		)
		stats.best_hit_percent_above_level_25 = maxi(
			int(stats.get("best_hit_percent_above_level_25", 0)),
			hit_percent
		)


func _shop_item_is_unlocked(item: Dictionary, seat_id: int) -> bool:
	if (
		_ordnance_contract.is_empty()
		and String(item.get("effect", "")) in ["rocket_pack", "enable_alien_lock"]
	):
		return false
	# Talent-enabled matches replace the retail unlock rules of the gated
	# effects with license ownership; with talents disabled every branch below
	# is byte-identical to retail.
	if _talents_enabled and String(item.get("effect", "")) in _talent_gated_effects:
		return String(item.get("effect", "")) in _talent_shop_unlocks
	var unlock: Dictionary = item.get(
		"unlock",
		{"kind": "always", "threshold": 0}
	)
	var kind := String(unlock.get("kind", "always"))
	if kind == "always":
		return true
	if kind != "hit_percent_above_level_25":
		return false
	if seat_id < 0 or seat_id >= _profile_stats_by_seat.size():
		return false
	return int(_profile_stats_by_seat[seat_id].get(
		"best_hit_percent_above_level_25",
		0
	)) >= int(unlock.get("threshold", 0))


func _progression_for_seat(_seat_id: int) -> Dictionary:
	# Every remaining mode shares one progression object across seats.
	return _shared


func _coop_has_fighter_for(player: Dictionary) -> bool:
	var other_live_fighters := 0
	for candidate_value in _players:
		var candidate: Dictionary = candidate_value
		if (
			int(candidate.seat_id) != int(player.seat_id)
			and bool(candidate.active)
			and bool(candidate.alive)
		):
			other_live_fighters += 1
	return int(_shared.lives) > other_live_fighters


func _has_remaining_fighters() -> bool:
	return int(_shared.lives) > 0


func _result_score() -> int:
	return int(_shared.score)


## Retail GAME BONUSES tally (docs/evidence/GAME_BONUS_TALLY.md): cash x 100,
## the cumulative rank bonus table, perfects x 100000, and truncated hit
## percentage x 1000, summed and added to the raw score. Solo is exact;
## simultaneous co-op condenses the shared party into the seat-0 entry with
## combined accuracy (M04 modernization).
func _terminal_tally_by_seat() -> Array:
	var tallies: Array = [{}, {}]
	if _mode == MODE_COOP:
		var combined_stats := {
			"perfect_bonus_rounds": 0,
			"projectile_objects_fired": 0,
			"successful_hits": 0,
		}
		for seat_id in range(2):
			if not _seat_is_participating(seat_id):
				continue
			var stats: Dictionary = _profile_stats_by_seat[seat_id]
			for key in combined_stats:
				combined_stats[key] = int(combined_stats[key]) + int(stats.get(key, 0))
		# Shared party perfects live in the shared progression's stats stream;
		# per-seat counters cover individually owned rounds.
		tallies[0] = _tally_for(_shared, combined_stats, 0)
		return tallies
	for seat_id in range(2):
		if not _seat_is_participating(seat_id):
			continue
		tallies[seat_id] = _tally_for(
			_progression_for_seat(seat_id),
			_profile_stats_by_seat[seat_id],
			seat_id
		)
	return tallies


func _tally_for(progression: Dictionary, stats: Dictionary, seat_id: int) -> Dictionary:
	var money := int(progression.get("money", 0))
	var cash_left_points := money * TALLY_CASH_POINTS_PER_MONEY
	var rank_index := clampi(
		int(progression.get("rank", 0)),
		0,
		TALLY_RANK_BONUS_TABLE.size() - 1
	)
	var rank_bonus := 0
	for table_index in range(1, rank_index + 1):
		rank_bonus += int(TALLY_RANK_BONUS_TABLE[table_index])
	var perfects := int(stats.get("perfect_bonus_rounds", 0))
	var perfect_points := perfects * TALLY_PERFECT_POINTS
	var fired := maxi(1, int(stats.get("projectile_objects_fired", 0)))
	var hit_percent := clampi(
		(int(stats.get("successful_hits", 0)) * 100) / fired,
		0,
		100
	)
	var hit_percent_points := hit_percent * TALLY_HIT_PERCENT_POINTS
	var sum_bonus_points := (
		cash_left_points + rank_bonus + perfect_points + hit_percent_points
	)
	var base_score := int(progression.get("score", 0))
	return {
		"seat_id": seat_id,
		"money": money,
		"cash_left_points": cash_left_points,
		"rank_index": rank_index,
		"rank_bonus": rank_bonus,
		"perfects": perfects,
		"perfect_points": perfect_points,
		"hit_percent": hit_percent,
		"hit_percent_points": hit_percent_points,
		"sum_bonus_points": sum_bonus_points,
		"base_score": base_score,
		"total_score": base_score + sum_bonus_points,
	}


## Retail pause-menu retire (RETIRE FROM  GAME): the run ends exactly as if
## the last fighter was just lost, entering the standard game-over path with
## its tally and profile statistics.
func request_retire(seat_id: int) -> Dictionary:
	if not _seat_is_participating(seat_id):
		return {"accepted": false, "reason": "seat is not participating"}
	if _phase in [PHASE_COMPLETE, PHASE_GAME_OVER, PHASE_CREDITS]:
		return {"accepted": false, "reason": "match already terminal"}
	_retired = true
	_emit_event("match_retired", {"seat_id": seat_id})
	_retire_all_fighters()
	_check_game_over()
	return {"accepted": true, "reason": ""}


func _retire_all_fighters() -> void:
	for player in _players:
		if not _seat_is_participating(int(player.seat_id)):
			continue
		player.alive = false
		player.active = false
		player.respawn_ticks = 0
	_shared.lives = 0


func _result_money() -> int:
	return int(_shared.money)


func _create_player(seat_id: int, x_fp: int) -> Dictionary:
	return {
		"seat_id": seat_id,
		"x_fp": x_fp,
		"y_fp": PLAYER_Y_FP,
		"width": PLAYER_WIDTH,
		"height": PLAYER_HEIGHT,
		"collision_width": PLAYER_WIDTH,
		"collision_height": 27,
		"active": true,
		"alive": true,
		"invulnerable_ticks": 0,
		"projectile_suppression_ticks": 0,
		"cooldown_ticks": 0,
		"auto_fire_deadline_ms": 0,
		"respawn_ticks": 0,
		"death_accounted": false,
		"mask_id": "fighter1" if seat_id == 0 else "fighter2",
		"mask_frame": 5,
		"sprite_phase_half_steps": 10,
		"mirror_anchor_x_fp": x_fp,
	}


func _player_spawn_x_fp(seat_id: int) -> int:
	if _mode == MODE_COOP:
		return (330 if seat_id == 0 else 470) * FP_ONE
	return 400 * FP_ONE


func _mirrored_x_fp(x_fp: int) -> int:
	# Retail reflects a 40px top-left coordinate as (W - 40) - X. Center
	# coordinates reduce that to W - center X.
	return FIELD_WIDTH * FP_ONE - x_fp


func _mirror_collision_proxy(target: Dictionary, mirrored: bool) -> Dictionary:
	if not mirrored:
		return target
	var proxy := target.duplicate()
	proxy.x_fp = _mirrored_x_fp(int(target.x_fp))
	if target.has("collision_x_fp"):
		proxy.collision_x_fp = _mirrored_x_fp(int(target.collision_x_fp))
	return proxy


func _objects_collide(left: Dictionary, right: Dictionary) -> bool:
	var left_width := int(left.get("collision_width", left.width))
	var left_height := int(left.get("collision_height", left.height))
	var right_width := int(right.get("collision_width", right.width))
	var right_height := int(right.get("collision_height", right.height))
	var left_x_fp := int(left.get("collision_x_fp", left.x_fp))
	var left_y_fp := int(left.get("collision_y_fp", left.y_fp))
	var right_x_fp := int(right.get("collision_x_fp", right.x_fp))
	var right_y_fp := int(right.get("collision_y_fp", right.y_fp))
	var horizontal_limit := (left_width + right_width) * FP_ONE / 2
	var vertical_limit := (left_height + right_height) * FP_ONE / 2
	var broad_phase_hit := (
		Fixed.abs_value(left_x_fp - right_x_fp) < horizontal_limit
		and Fixed.abs_value(left_y_fp - right_y_fp) < vertical_limit
	)
	if (
		not broad_phase_hit
		or _collision_mode == "simple"
		or bool(left.get("collision_simple", false))
		or bool(right.get("collision_simple", false))
	):
		return broad_phase_hit
	var left_mask_id := String(left.get("mask_id", ""))
	var right_mask_id := String(right.get("mask_id", ""))
	if left_mask_id.is_empty() or right_mask_id.is_empty():
		return not (
			bool(left.get("mask_required", false))
			or bool(right.get("mask_required", false))
		)
	if not _hit_masks.has(left_mask_id) or not _hit_masks.has(right_mask_id):
		return not (
			bool(left.get("mask_required", false))
			or bool(right.get("mask_required", false))
		)
	var left_mask: HitMaskAtlas = _hit_masks[left_mask_id]
	var right_mask: HitMaskAtlas = _hit_masks[right_mask_id]
	# Retail tests its traced rectangle first and then samples the mask over the
	# sprite's own frame. The two agree for every ordinary entity, so the mask
	# geometry only diverges where a ship declares a hitbox smaller than its
	# frame (the hurry-up money ship).
	return left_mask.overlaps_source_rect(
		_mask_source_rect(left, left_mask),
		left_x_fp,
		left_y_fp,
		int(left.get("mask_width", left_width)),
		int(left.get("mask_height", left_height)),
		right_mask,
		_mask_source_rect(right, right_mask),
		right_x_fp,
		right_y_fp,
		int(right.get("mask_width", right_width)),
		int(right.get("mask_height", right_height))
	)


func _load_proven_hit_masks() -> bool:
	_hit_masks.clear()
	var definitions := {
		"fighter1": {
			"path": "res://assets/original/textures/player/fighter1.hma",
			"image_width": 440,
			"image_height": 28,
			"frame_width": 40,
			"frame_height": 28,
		},
		"fighter2": {
			"path": "res://assets/original/textures/player/fighter2.hma",
			"image_width": 440,
			"image_height": 28,
			"frame_width": 40,
			"frame_height": 28,
		},
		"malfunction1": {
			"path": "res://assets/original/textures/enemies/malfunction1.hma",
			"image_width": 576,
			"image_height": 96,
			"frame_width": 576,
			"frame_height": 96,
		},
		"malfunction3": {
			"path": "res://assets/original/textures/enemies/malfunction3.hma",
			"image_width": 576,
			"image_height": 96,
			"frame_width": 576,
			"frame_height": 96,
		},
		"malfunction4": {
			"path": "res://assets/original/textures/enemies/malfunction4.hma",
			"image_width": 576,
			"image_height": 96,
			"frame_width": 576,
			"frame_height": 96,
		},
		"alien_malfold_blue": {
			"path": "res://assets/original/textures/enemies/alien_malfold_blue.hma",
			"image_width": 576,
			"image_height": 96,
			"frame_width": 576,
			"frame_height": 96,
		},
		"alien_malfold_green": {
			"path": "res://assets/original/textures/enemies/alien_malfold_green.hma",
			"image_width": 576,
			"image_height": 96,
			"frame_width": 576,
			"frame_height": 96,
		},
		"weapons_big": {
			"path": "res://assets/original/textures/weapons/weapons_big.hma",
			"image_width": 672,
			"image_height": 100,
			"frame_width": 672,
			"frame_height": 100,
		},
		"rocket": {
			"path": "res://assets/original/textures/weapons/rocket.hma",
			"image_width": 768,
			"image_height": 72,
			"frame_width": 768,
			"frame_height": 72,
		},
		"bonuses": {
			"path": "res://assets/original/textures/ui/bonuses.hma",
			"image_width": 200,
			"image_height": 740,
			"frame_width": 200,
			"frame_height": 740,
		},
		"meteors": {
			"path": "res://assets/original/textures/bonus_modes/meteors.hma",
			"image_width": 624,
			"image_height": 717,
			"frame_width": 624,
			"frame_height": 717,
		},
		"meteorbonuses": {
			"path": "res://assets/original/textures/bonus_modes/meteorbonuses.hma",
			"image_width": 384,
			"image_height": 370,
			"frame_width": 384,
			"frame_height": 370,
		},
		"diamantbig": {
			"path": "res://assets/original/textures/ui/diamantbig.hma",
			"image_width": 240,
			"image_height": 561,
			"frame_width": 240,
			"frame_height": 561,
		},
		"marks": {
			"path": "res://assets/original/textures/ui/marks.hma",
			"image_width": 200,
			"image_height": 140,
			"frame_width": 200,
			"frame_height": 140,
		},
		# The hurry-up ships. The money ship's mask is a straight row-major copy
		# of its 128x1280 sheet, while the mothership's is packed as twenty
		# 96x57 frames in a single column rather than mirroring the 3x8 texture
		# layout, so its mask rectangle is derived from the frame index alone.
		MOTHERSHIP_SPRITE: {
			"path": "res://assets/original/evidence/enemies/mothership.hma",
			"image_width": MOTHERSHIP_FRAME_WIDTH,
			"image_height": MOTHERSHIP_FRAME_HEIGHT * MOTHERSHIP_FRAME_COUNT,
			"frame_width": MOTHERSHIP_FRAME_WIDTH,
			"frame_height": MOTHERSHIP_FRAME_HEIGHT,
			"frame_count": MOTHERSHIP_FRAME_COUNT,
			"sha256": (
				"59f4d1f1942e7190ac88b67563be1727a92ed787bff54f3dbc46bb3762302517"
			),
		},
		MONEYSHIP_SPRITE: {
			"path": "res://assets/original/textures/enemies/moneyship.hma",
			"image_width": MONEYSHIP_FRAME_SIZE,
			"image_height": MONEYSHIP_FRAME_SIZE * MONEYSHIP_FRAME_COUNT,
			"frame_width": MONEYSHIP_FRAME_SIZE,
			"frame_height": MONEYSHIP_FRAME_SIZE,
			"frame_count": MONEYSHIP_FRAME_COUNT,
			"sha256": (
				"f7e327b95385cb3996ab75e587732a9d990326384f0724aa29be839473887b09"
			),
		},
		# The two G20 secret ships. Both masks are row-major copies of their own
		# sheets, so one rectangle serves the texture and the mask.
		MONEY_SUCKER_SPRITE: {
			"path": "res://assets/original/textures/enemies/moneysucker2.hma",
			"image_width": MONEY_SUCKER_FRAME_WIDTH,
			"image_height": MONEY_SUCKER_FRAME_HEIGHT * MONEY_SUCKER_FRAME_COUNT,
			"frame_width": MONEY_SUCKER_FRAME_WIDTH,
			"frame_height": MONEY_SUCKER_FRAME_HEIGHT,
			"frame_count": MONEY_SUCKER_FRAME_COUNT,
			"sha256": (
				"76bafefe42340085429b15efe9f0e90e963cd40a1dcbb6417baceb1cb6e6e737"
			),
		},
		GUARD_SHIP_SPRITE: {
			"path": "res://assets/original/textures/weapons/guard.hma",
			"image_width": GUARD_SHIP_FRAME_WIDTH,
			"image_height": GUARD_SHIP_FRAME_HEIGHT * GUARD_SHIP_FRAME_COUNT,
			"frame_width": GUARD_SHIP_FRAME_WIDTH,
			"frame_height": GUARD_SHIP_FRAME_HEIGHT,
			"frame_count": GUARD_SHIP_FRAME_COUNT,
			"sha256": (
				"b0ebd7a0d1060e01b032d9fc717ead94691174a8f86555121f0aa349d9ff5725"
			),
		},
	}
	for enemy_definition_value in _sprite_frames.hit_mask_definitions():
		if not enemy_definition_value is Dictionary:
			return _set_error("enemy hit-mask definition must be an object")
		var enemy_definition := enemy_definition_value as Dictionary
		var enemy_mask_id := String(enemy_definition.get("id", ""))
		if enemy_mask_id.is_empty() or definitions.has(enemy_mask_id):
			return _set_error("enemy hit-mask definition ID is missing or duplicated")
		definitions[enemy_mask_id] = enemy_definition.duplicate(true)
	for mask_id in definitions:
		var definition: Dictionary = definitions[mask_id]
		var atlas := HitMask.new()
		if not atlas.load_file(
			String(definition.path),
			int(definition.image_width),
			int(definition.image_height),
			int(definition.frame_width),
			int(definition.frame_height),
			String(definition.get("sha256", ""))
		):
			return _set_error("cannot load %s hit mask: %s" % [mask_id, atlas.last_error])
		var expected_frames := int(definition.get(
			"frame_count",
			11 if String(mask_id).begins_with("fighter") else 1
		))
		if atlas.frame_count != expected_frames:
			return _set_error(
				"%s hit mask frame count differs: expected %d, got %d"
				% [mask_id, expected_frames, atlas.frame_count]
			)
		_hit_masks[mask_id] = atlas
	return true


func _update_enemy_mask_rect(enemy: Dictionary) -> void:
	enemy.collision_x_fp = _enemy_world_x_fp(enemy)
	enemy.collision_y_fp = _enemy_world_y_fp(enemy)
	var source_rect := _sprite_frames.enemy_source_rect(enemy, _tick)
	if source_rect.size.x <= 0 or source_rect.size.y <= 0:
		return
	_set_mask_source_rect(enemy, source_rect)


func _update_pickup_mask_rect(pickup: Dictionary) -> void:
	if not pickup.has("source_y"):
		return
	_set_mask_source_rect(
		pickup,
		Rect2i(
			posmod(int(pickup.get("animation_frame", 0)), 10) * 20,
			int(pickup.source_y),
			int(pickup.get("width", 20)),
			int(pickup.get("height", 20))
		)
	)


func _enemy_world_x_fp(enemy: Dictionary) -> int:
	if String(enemy.get("authored_state", "")) == "formation":
		return int(enemy.x_fp) + _platform_x_fp
	return int(enemy.x_fp)


func _enemy_world_y_fp(enemy: Dictionary) -> int:
	if String(enemy.get("authored_state", "")) == "formation":
		return int(enemy.y_fp) + _platform_y_fp
	return int(enemy.y_fp)


func _set_mask_source_rect(entity: Dictionary, source_rect: Rect2i) -> void:
	entity.mask_source_x = source_rect.position.x
	entity.mask_source_y = source_rect.position.y
	entity.mask_source_width = source_rect.size.x
	entity.mask_source_height = source_rect.size.y


func _mask_source_rect(entity: Dictionary, atlas: HitMaskAtlas) -> Rect2i:
	if (
		entity.has("mask_source_x")
		and entity.has("mask_source_y")
		and entity.has("mask_source_width")
		and entity.has("mask_source_height")
	):
		return Rect2i(
			int(entity.mask_source_x),
			int(entity.mask_source_y),
			int(entity.mask_source_width),
			int(entity.mask_source_height)
		)
	return atlas.frame_source_rect(int(entity.get("mask_frame", 0)))


func _meteor_collision_query(payload: Dictionary) -> bool:
	# MeteorStormSimulation already performed the retail strict AABB check.
	if _collision_mode == "simple":
		return true
	var slot_mask_id := String(payload.get("slot_mask_id", ""))
	var fighter_mask_id := String(payload.get("fighter_mask_id", ""))
	if not _hit_masks.has(slot_mask_id) or not _hit_masks.has(fighter_mask_id):
		return false
	var slot_source: Array = payload.get("slot_source_rect", [])
	var slot_destination: Array = payload.get("slot_destination_rect", [])
	var fighter_source: Array = payload.get("fighter_source_rect", [])
	var fighter_destination: Array = payload.get("fighter_destination_rect", [])
	if (
		slot_source.size() != 4
		or slot_destination.size() != 4
		or fighter_source.size() != 4
		or fighter_destination.size() != 4
	):
		return false
	var slot_mask: HitMaskAtlas = _hit_masks[slot_mask_id]
	var fighter_mask: HitMaskAtlas = _hit_masks[fighter_mask_id]
	var slot_width := int(slot_destination[2])
	var slot_height := int(slot_destination[3])
	var fighter_width := int(fighter_destination[2])
	var fighter_height := int(fighter_destination[3])
	return slot_mask.overlaps_source_rect(
		Rect2i(
			int(slot_source[0]),
			int(slot_source[1]),
			int(slot_source[2]),
			int(slot_source[3])
		),
		int(slot_destination[0]) * FP_ONE + slot_width * FP_ONE / 2,
		int(slot_destination[1]) * FP_ONE + slot_height * FP_ONE / 2,
		slot_width,
		slot_height,
		fighter_mask,
		Rect2i(
			int(fighter_source[0]),
			int(fighter_source[1]),
			int(fighter_source[2]),
			int(fighter_source[3])
		),
		int(fighter_destination[0]) * FP_ONE + fighter_width * FP_ONE / 2,
		int(fighter_destination[1]) * FP_ONE + fighter_height * FP_ONE / 2,
		fighter_width,
		fighter_height
	)


func _nearest_active_player(x_fp: int) -> Dictionary:
	var nearest: Dictionary = {}
	var best_distance := 9223372036854775807
	for player_value in _players:
		var player: Dictionary = player_value
		if not bool(player.active) or not bool(player.alive):
			continue
		var distance := Fixed.abs_value(int(player.x_fp) - x_fp)
		if distance < best_distance:
			best_distance = distance
			nearest = player
	return nearest


func _triangle_wave_fp(phase: int, period: int) -> int:
	var quarter: int = maxi(1, period / 4)
	var normalized: int = phase % period
	if normalized < quarter:
		return -FP_ONE + (normalized * 2 * FP_ONE / quarter)
	if normalized < quarter * 3:
		return FP_ONE - ((normalized - quarter) * 2 * FP_ONE / (quarter * 2))
	return -FP_ONE + ((normalized - quarter * 3) * 2 * FP_ONE / quarter)


func _seat_is_participating(seat_id: int) -> bool:
	if seat_id == 0:
		return true
	# Retail Time Trial is a single-seat match mode.
	return _mode not in [MODE_SOLO, MODE_TIME_TRIAL]


func _action_just_pressed(seat_id: int, action: int) -> bool:
	return (
		(_input_masks[seat_id] & action) != 0
		and (_previous_input_masks[seat_id] & action) == 0
	)


func _allocate_entity_id() -> int:
	var entity_id := _next_entity_id
	_next_entity_id += 1
	return entity_id


func _emit_event(event_type: String, fields: Dictionary = {}) -> void:
	var event := fields.duplicate(true)
	event["event_id"] = _next_event_id
	event["tick"] = _tick
	event["type"] = event_type
	event["kind"] = event_type
	if not event.has("x_fp"):
		event["x_fp"] = (FIELD_WIDTH >> 1) * FP_ONE
	if not event.has("y_fp"):
		event["y_fp"] = (FIELD_HEIGHT >> 1) * FP_ONE
	_next_event_id += 1
	_events.append(event)


func _public_shared_state() -> Dictionary:
	return _public_progression(_shared)


func _public_level_eight_result_players() -> Array:
	var result: Array = []
	var reward_values := _level_eight_reward_values()
	for seat_id in range(_level_eight_result_players.size()):
		var counters: Dictionary = _level_eight_result_players[seat_id]
		var total := int(counters.get("total_targets", 0))
		var actual := int(counters.get("actual_hits", 0))
		var displayed := int(counters.get("displayed_hits", 0))
		var reward_index := clampi(
			int(_level_eight_perfect_indices[seat_id]),
			0,
			reward_values.size() - 1
		)
		result.append({
			"seat_id": seat_id,
			"participating": bool(counters.get("participating", false)),
			"total_targets": total,
			"actual_hits": actual,
			"displayed_hits": displayed,
			"misses": maxi(0, total - actual),
			"hud_hits": displayed if _level_eight_result_initialized else actual,
			"hud_misses": maxi(0, total - actual),
			"perfect_awarded": bool(counters.get("perfect_awarded", false)),
			"perfect_reward": int(counters.get("perfect_reward", 0)),
			"perfect_reward_index": reward_index,
			"next_perfect_reward": int(reward_values[reward_index]),
		})
	return result


func _public_level_eight_bonus_snapshot() -> Dictionary:
	var timing: Dictionary = _level_eight_contract.get("timing_and_flow", {})
	return {
		"active": _phase == PHASE_LEVEL and _is_mode_three_bonus(),
		"result_initialized": _level_eight_result_initialized,
		"header": (
			String(timing.get("result_header", LEVEL_EIGHT_RESULT_HEADER))
			if _level_eight_result_initialized
			else ""
		),
		"result_deadline_ms": _level_eight_result_deadline_ms,
		"reveal_deadline_ms": _level_eight_reveal_deadline_ms,
		"reveal_countdown": _level_eight_reveal_countdown,
		"players": _public_level_eight_result_players(),
	}


func _public_progression(progression: Dictionary) -> Dictionary:
	var mode_three_perfect_reward_indices: Array = progression.get(
		"mode_three_perfect_reward_indices",
		progression.get(
			"level_eight_perfect_reward_indices",
			_level_eight_perfect_indices
		)
	)
	var mode_three_next_perfect_rewards: Array = progression.get(
		"mode_three_next_perfect_rewards",
		progression.get(
			"level_eight_next_perfect_rewards",
			[LEVEL_EIGHT_PERFECT_REWARDS[0], LEVEL_EIGHT_PERFECT_REWARDS[0]]
		)
	)
	return {
		"lives": int(progression.lives),
		"score": int(progression.score),
		"money": int(progression.money),
		"rockets": int(progression.get("rockets", 0)),
		"score_multiplier": int(progression.get("score_multiplier", 1)),
		"score_multiplier_ticks": int(progression.get("score_multiplier_ticks", 0)),
		"weapon_id": int(progression.weapon_id),
		"bullet_capacity": int(progression.bullet_capacity),
		"auto_fire": bool(progression.auto_fire),
		"auto_fire_delay_ms": int(progression.auto_fire_delay_ms),
		"armour_fp": int(progression.armour_fp),
		"shield_ticks": int(progression.get("shield_ticks", 0)),
		"speed_fp": int(progression.speed_fp),
		"bullet_speed_fp": int(progression.get("bullet_speed_fp", FP_ONE)),
		"upgrades": progression.upgrades.duplicate(true),
		"extra_letters": String(progression.extra_letters),
		"letter_bits": int(progression.get("letter_bits", 0)),
		"letter_forward_chain": String(progression.get("letter_forward_chain", " ")),
		"letter_reverse_chain": String(progression.get("letter_reverse_chain", " ")),
		"secret_session_seen": (
			progression.get("secret_session_seen", []) as Array
		).duplicate(),
		"rank_markers": int(progression.rank_markers),
		"rank": int(progression.get("rank", 0)),
		"highest_rank": int(progression.get("highest_rank", 0)),
		"rank_cap": int(progression.get("rank_cap", DEFAULT_RANK_CAP)),
		"gem_count": int(progression.get("gem_count", 0)),
		"bonus_time": int(progression.bonus_time),
		"memory_columns": int(progression.get("memory_columns", 4)),
		"memory_rows": int(progression.get("memory_rows", 4)),
		"memory_success_streak": int(progression.get("memory_success_streak", 0)),
		"memory_point_bonus": int(progression.get("memory_point_bonus", 0)),
		"memory_point_step": int(progression.get("memory_point_step", 0)),
		"mode_three_perfect_reward_indices": (
			mode_three_perfect_reward_indices.duplicate()
		),
		"mode_three_next_perfect_rewards": mode_three_next_perfect_rewards.duplicate(),
		"level_eight_perfect_reward_indices": (
			mode_three_perfect_reward_indices.duplicate()
		),
		"level_eight_next_perfect_rewards": mode_three_next_perfect_rewards.duplicate(),
		"meteor_distance": int(progression.get("meteor_distance", 0)),
		"meteor_streak": int(progression.get("meteor_streak", 0)),
		"selected_secret_id": int(progression.get("selected_secret_id", -1)),
		"scoop_ticks": int(progression.get("scoop_ticks", 0)),
		"warp_fp": int(progression.get("warp_fp", 0)),
		"warp_companion": int(progression.get("warp_companion", 0)),
		"mirror_ticks": int(progression.get("mirror_ticks", 0)),
		"drunk_ticks": int(progression.get("drunk_ticks", 0)),
		"freeze_ticks": int(progression.get("freeze_ticks", 0)),
		"sucker_bits": int(progression.get("sucker_bits", 0)),
		"special_mode": String(progression.get("special_mode", "")),
		"special_mode_ticks": int(progression.get("special_mode_ticks", 0)),
		"super_autofire_message_ticks": int(
			progression.get("super_autofire_message_ticks", 0)
		),
	}


func _public_seat_progression() -> Array:
	var result: Array = []
	for seat_id in range(2):
		result.append(_public_progression(_progression_for_seat(seat_id)))
	return result


func _public_profile_stats() -> Array:
	var result: Array = []
	for seat_id in range(2):
		var stats: Dictionary = (
			_profile_stats_by_seat[seat_id]
			if seat_id < _profile_stats_by_seat.size()
			else _create_profile_stats()
		)
		var public_stats := stats.duplicate(true)
		public_stats["mode_three_perfect_reward_index"] = int(
			_level_eight_perfect_indices[seat_id]
		)
		public_stats["level_eight_perfect_reward_index"] = int(
			_level_eight_perfect_indices[seat_id]
		)
		result.append(public_stats)
	return result


func _state_for_hash() -> Dictionary:
	var nonce_keys: Array = _purchased_nonces.keys()
	nonce_keys.sort()
	return {
		"version": HASH_STATE_VERSION,
		"tick": _tick,
		"level_tick": _level_tick,
		"start_level_id": int(_config.get("start_level", 1)),
		"level_id": _level_id,
		"end_level_id": _end_level_id,
		"phase": _phase,
		"mode": _mode,
		"difficulty": _difficulty_id,
		"balance": _balance,
		"collision_mode": _collision_mode,
		"turn_seat": _turn_seat,
		"time_trial_deadline_ms": _time_trial_deadline_ms,
		"time_trial_expired": _time_trial_expired,
		"hurry_up_interval_ms": _hurry_up_interval_ms,
		"hurry_up_deadline_ms": _hurry_up_deadline_ms,
		"hurry_up_spawn_counter": _hurry_up_spawn_counter,
		"hurry_up_planet_count": _hurry_up_planet_count,
		"hurry_up_planet_x": _hurry_up_planet_x,
		"money_sucker_deadline_ms": _money_sucker_deadline_ms,
		"guard_previous_level": _guard_previous_level,
		"guard_beam_window": _guard_beam_window,
		"special_health_base_b": _special_health_base_b,
		"special_health_base_d": _special_health_base_d,
		"effect_pool": _effect_pool,
		"rng": _rng.snapshot(),
		"next_entity_id": _next_entity_id,
		"next_event_id": _next_event_id,
		"inputs": [_input_masks[0], _input_masks[1]],
		"previous_inputs": [_previous_input_masks[0], _previous_input_masks[1]],
		"spawned_waves": _sorted_int_keys(_spawned_waves),
		"players": _players,
		"enemies": _enemies,
		"projectiles": _projectiles,
		"common_projectile_slots": _common_projectile_slots,
		"authored_slot_seeds": _authored_slot_seeds,
		"authored_spawn_slot": _authored_spawn_slot,
		"supplemental_spawned": _supplemental_spawned,
		"platform_x_fp": _platform_x_fp,
		"platform_y_fp": _platform_y_fp,
		"platform_velocity_x_fp": _platform_velocity_x_fp,
		"platform_acceleration_x_fp": _platform_acceleration_x_fp,
		"tail_cutoff": _tail_cutoff,
		"level_total_entities": _level_total_entities,
		"level_killed_entities": _level_killed_entities,
		"level_escaped_entities": _level_escaped_entities,
		"level_resolved": _level_resolved,
		"level_resolution_tick": _level_resolution_tick,
		"level_eight_result_initialized": _level_eight_result_initialized,
		"level_eight_result_deadline_ms": _level_eight_result_deadline_ms,
		"level_eight_reveal_deadline_ms": _level_eight_reveal_deadline_ms,
		"level_eight_reveal_countdown": _level_eight_reveal_countdown,
		"level_eight_result_players": _level_eight_result_players,
		"level_eight_perfect_indices": _level_eight_perfect_indices,
		"get_ready_until_tick": _get_ready_until_tick,
		"pending_level_id": _pending_level_id,
		"group_kill_counts": _group_kill_counts,
		"group_totals": _group_totals,
		"cohort_kill_counts": _cohort_kill_counts,
		"cohort_totals": _cohort_totals,
		"cohort_completion_score": _cohort_completion_score,
		"level_watchdog_start_tick": _level_watchdog_start_tick,
		"enemy_liveness_idle_updates": _enemy_liveness_idle_updates,
		"shop_warp_until_tick": _shop_warp_until_tick,
		"rank_promotion_seat_id": _rank_promotion_seat_id,
		"rank_promotion_minimum_tick": _rank_promotion_minimum_tick,
		"rank_promotion_timeout_tick": _rank_promotion_timeout_tick,
		"rocket_fired_this_level": _rocket_fired_this_level,
		"alien_projectile_processed_this_level": (
			_alien_projectile_processed_this_level
		),
		"secondary_rocket_armed": _secondary_rocket_armed,
		"player_projectile_slot_stale_contributions": (
			_player_projectile_slot_stale_contributions
		),
		"ordinary_projectile_counter_adjustment_by_seat": (
			_ordinary_projectile_counter_adjustment_by_seat
		),
		"rocket_effect_until_ms": _rocket_effect_until_ms,
		"rocket_effect_active": _rocket_effect_active,
		"rank_full_reward_claimed": _rank_full_reward_claimed,
		"bonus_mode_until_tick": _bonus_mode_until_tick,
		"bonus_mode_owner_seat_id": _bonus_mode_owner_seat_id,
		"bonus_mode_transition_until_ms": _bonus_mode_transition_until_ms,
		"bonus_mode_completion": _bonus_mode_completion,
		"pending_gem_drop_transition": _pending_gem_drop_transition,
		"gem_drop_source_mode": _gem_drop_source_mode,
		"gem_drop_super": _gem_drop_super,
		"bonus_action_queue": _bonus_action_queue,
		"bonus_actions_this_tick": _bonus_actions_this_tick,
		"bonus_action_last_target_tick": _bonus_action_last_target_tick,
		"bonus_controller": _active_bonus_controller_hash_state(),
		"warp_stage": _warp_stage,
		"warp_stage_updates_remaining": _warp_stage_updates_remaining,
		"warp_visual_fp": _warp_visual_fp,
		"warp_scale": _warp_scale,
		"warp_velocity": _warp_velocity,
		"warp_effect": _warp_effect,
		"warp_offset": _warp_offset,
		"background_draw_offset": _background_draw_offset,
		"background_post_draw_offset": _background_post_draw_offset,
		"warp_owned_skip": _warp_owned_skip,
		"warp_malfunction_interval": _warp_malfunction_interval,
		"warp_malfunction_gate_calls": _warp_malfunction_gate_calls,
		"warp_malfunction_file_id": _warp_malfunction_file_id,
		"warp_malfunction_total": _warp_malfunction_total,
		"warp_malfunction_killed": _warp_malfunction_killed,
		"warp_malfunction_missed": _warp_malfunction_missed,
		"warp_malfunction_resolution_tick": _warp_malfunction_resolution_tick,
		"warp_malfunction_transition_pending": _warp_malfunction_transition_pending,
		"warp_malfunction_message_until_tick": _warp_malfunction_message_until_tick,
		"warp_malfunction_message_cadence_tick": _warp_malfunction_message_cadence_tick,
		"warp_malfunction_message_cadence_remaining": _warp_malfunction_message_cadence_remaining,
		"warp_owner_seat_id": _warp_owner_seat_id,
		"warp_transition_requested": _warp_transition_requested,
		"warp_request_seat_id": _warp_request_seat_id,
		"warp_request_cause": _warp_request_cause,
		"last_secret_id": _last_secret_id,
		"previous_secret_id": _previous_secret_id,
		"pickups": _pickups,
		"shared": _shared,
		"seat_progression": _seat_progression,
		"profile_stats_by_seat": _profile_stats_by_seat,
		"match_persistent_flags_by_seat": _match_persistent_flags_by_seat,
		"boss_controller": (
			_retail_big_boss.state_hash_payload() if _boss_entered else {}
		),
		"boss_effect_runtime": (
			_retail_big_boss_effects.state_hash_payload() if _boss_entered else {}
		),
		"boss_runtime_blocked": _boss_runtime_blocked,
		"boss_terminal_route_pending": _boss_terminal_route_pending,
		"boss_completion_marked": _boss_completion_marked,
		"boss_reward_applied": _boss_reward_applied,
		"boss_last_reward_score": _boss_last_reward_score,
		"boss_projectile_sheet": _boss_projectile_sheet,
		"boss_render_snapshot": _boss_render_snapshot,
		"boss_deferred_entry_events": _boss_deferred_entry_events,
		"boss_destroyed_counts_by_seat": _boss_destroyed_counts_by_seat,
		"retail_global_sound_gate": _retail_global_sound_gate,
		"boss_pending_deferred_sound": _boss_pending_deferred_sound,
		"shop_ready": [_shop_ready[0], _shop_ready[1]],
		"purchase_nonces": nonce_keys,
		"retired": _retired,
		"locked_out_bonus_types": _sorted_int_keys(_locked_out_bonus_types),
		"result": _result,
		"content_hash": _content_hash,
	}


func _sorted_int_keys(dictionary: Dictionary) -> Array:
	var values: Array = dictionary.keys()
	values.sort()
	return values


func _purchase_result(
	accepted: bool,
	reason: String,
	item_id: int,
	nonce: int,
	seat_id: int = 0
) -> Dictionary:
	return {
		"accepted": accepted,
		"reason": reason,
		"item_id": item_id,
		"nonce": nonce,
		"money": int(_progression_for_seat(seat_id).get("money", 0)),
	}


func _remember_purchase(nonce_key: String, result: Dictionary) -> Dictionary:
	if _purchased_nonces.size() >= 256:
		var oldest_key: String = String(_purchased_nonces.keys()[0])
		_purchased_nonces.erase(oldest_key)
	_purchased_nonces[nonce_key] = result.duplicate(true)
	return result


func _set_error(message: String) -> bool:
	last_error = message
	return false
