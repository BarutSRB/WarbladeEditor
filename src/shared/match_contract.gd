class_name WBMatchContract
extends RefCounted

const CONTENT_VERSION: int = 12
# Retail never ends the campaign: content cycles per hundred with a cumulative
# difficulty step and the level counter clamps at 3999 (executable-backed, see
# docs/evidence/ENDLESS_PROGRESSION.md). The configurable end-level boundary
# remains for bounded sessions and is validated against the retail clamp.
const MAX_END_LEVEL: int = 3999
const LAST_AUTHORED_LEVEL: int = 100

const CONTRACT_MODES := ["solo", "coop", "time_trial"]
# 600 ticks = one hash checkpoint every ten seconds in networked recordings.
const REPLAY_HASH_STRIDE_TICKS := 600
const CONTRACT_DIFFICULTIES := ["easy", "normal", "hard", "ace"]
const CONTRACT_COOP_BALANCE := ["classic", "balanced"]
const CONTRACT_COLLISION_MODES := ["pixel", "simple"]
const MAX_PROFILE_ID_BYTES := 64
const SECRET_FLAG_COUNT := 30

# The complete start-state vocabulary the simulation consumes
# (_apply_profile_start_state and the excluded-bonus filter). Anything outside
# these keys is dropped before the request can reach the authoritative
# simulation.
const START_STATE_INT_KEYS := [
	"bullet_capacity", "speed_steps", "weapon_at_least", "armour_charges",
	"money", "bonus_time", "bonus_time_max", "timed_score_multiplier",
]
const START_STATE_BOOL_KEYS := [
	"speed_half_max", "speed_max", "auto_fire", "super_auto_fire",
	"bonus_time_half_max", "bonus_time_full_max", "bullet_speed_up",
	"rank_32_bullet_speed", "meteor_storm_multiplier_enabled", "gem_counter",
	"secret_counter", "missile_stealth", "autofire_through_shop",
	"timed_scoop", "time_trial_extra_minute", "only_blue_coins",
	"alien_lock",
]

# The shop effects a talent license may unlock (content v12 talent gating).
# Mirrors content/talents.json shop_migration.talent_gated_effects — the
# content catalog validator enforces equality so the two cannot drift.
const TALENT_GATED_EFFECTS := [
	"enable_alien_lock", "enable_autofire", "enable_super_autofire",
	"rocket_pack",
]


static func has_current_versions(config: Dictionary) -> bool:
	return (
		int(config.get("protocol_version", -1)) == ProtocolCodec.VERSION
		and int(config.get("content_version", -1)) == CONTENT_VERSION
	)


static func has_valid_level_range(config: Dictionary) -> bool:
	var start_level := int(config.get("start_level", 0))
	var end_level := int(config.get("end_level", 0))
	return start_level >= 1 and end_level >= start_level and end_level <= MAX_END_LEVEL


static func seat_count_for_mode(mode: String) -> int:
	return 2 if mode == "coop" else 1


## The canonical match identity a client asks a game server to run. Both roles
## build it with this one normalizer: the client sends it inside HELLO, the
## server configures its simulation from it, and every later HELLO for the same
## match must produce an equal dictionary. It deliberately excludes transport
## and content versions (the packet framing and the content-hash handshake
## already pin those) and every client-only presentation field. The seed rides
## as a string because the request crosses a JSON boundary and 64-bit seeds do
## not survive float64 coercion.
static func network_contract(config: Dictionary) -> Dictionary:
	var mode := str(config.get("mode", "solo"))
	if mode not in CONTRACT_MODES:
		mode = "solo"
	var difficulty := str(config.get("difficulty", "normal"))
	if difficulty not in CONTRACT_DIFFICULTIES:
		difficulty = "normal"
	var coop_balance := str(config.get("coop_balance", "classic"))
	if coop_balance not in CONTRACT_COOP_BALANCE:
		coop_balance = "classic"
	var collision_mode := str(config.get("collision_mode", "pixel"))
	if collision_mode not in CONTRACT_COLLISION_MODES:
		collision_mode = "pixel"
	var start_level := clampi(int(config.get("start_level", 1)), 1, MAX_END_LEVEL)
	var end_level := clampi(int(config.get("end_level", MAX_END_LEVEL)), start_level, MAX_END_LEVEL)
	var seats_value: Variant = config.get("seats", [])
	var seats: Array = seats_value if seats_value is Array else []
	var contract_seats: Array = []
	for seat_id in range(seat_count_for_mode(mode)):
		var seat: Dictionary = {}
		if seat_id < seats.size() and seats[seat_id] is Dictionary:
			seat = seats[seat_id]
		contract_seats.append(_contract_seat(seat, seat_id))
	return {
		"mode": mode,
		"difficulty": difficulty,
		"coop_balance": coop_balance,
		"collision_mode": collision_mode,
		"seed": str(int(config.get("seed", 1))),
		"start_level": start_level,
		"end_level": end_level,
		"starting_rockets": clampi(int(config.get("starting_rockets", 0)), 0, 50),
		"talents_enabled": bool(config.get("talents_enabled", false)) and mode != "time_trial",
		"seats": contract_seats,
	}


## Contract equality is only meaningful in normalized form: a contract that
## crossed a JSON boundary carries floats where the normalizer emits ints,
## and GDScript dictionary equality is type-strict. Every comparison — the
## HELLO lobby check, the verifier's ticket gate — must go through here.
static func contracts_equal(left: Dictionary, right: Dictionary) -> bool:
	return network_contract(left) == network_contract(right)


## The complete HELLO match request: the match identity plus the slot entry
## action. Resuming a saved run must present the same identity the save was
## written under, so the slot rides beside the contract rather than inside it.
static func network_match_request(config: Dictionary) -> Dictionary:
	return {
		"contract": network_contract(config),
		"resume_slot": maxi(-1, int(config.get("resume_slot", -1))),
	}


## Expands a validated network contract back into the configuration dictionary
## the authoritative simulation consumes. The server is the only caller; the
## version fields are its own, never the remote peer's claim.
static func config_from_network_contract(contract: Dictionary) -> Dictionary:
	var config := contract.duplicate(true)
	config["protocol_version"] = ProtocolCodec.VERSION
	config["content_version"] = CONTENT_VERSION
	config["seed"] = int(str(contract.get("seed", "1")))
	config["seat_count"] = seat_count_for_mode(str(contract.get("mode", "solo")))
	# Networked matches record their replay so a finished run can be exported
	# (REPLAY_REQUEST) and submitted for verified talent crediting. The sparse
	# hash stride keeps multi-hour recordings affordable; the verifier
	# recomputes every hash itself.
	config["record_replay"] = true
	config["replay_hash_stride"] = REPLAY_HASH_STRIDE_TICKS
	return config


static func _contract_seat(seat: Dictionary, seat_id: int) -> Dictionary:
	var perfect_reward_index := clampi(
		int(seat.get(
			"mode_three_perfect_reward_index",
			seat.get("level_eight_perfect_reward_index", 0)
		)),
		0,
		9
	)
	var profile_id := str(seat.get("profile_id", ""))
	if profile_id.to_utf8_buffer().size() > MAX_PROFILE_ID_BYTES:
		profile_id = ""
	var supplied_secret_value: Variant = seat.get("secret_session_earned", [])
	var supplied_secrets: Array = (
		supplied_secret_value if supplied_secret_value is Array else []
	)
	var secret_flags: Array = []
	for secret_id in range(SECRET_FLAG_COUNT):
		secret_flags.append(
			1
			if secret_id < supplied_secrets.size() and int(supplied_secrets[secret_id]) != 0
			else 0
		)
	return {
		"seat": seat_id,
		"profile_id": profile_id,
		"mode_three_perfect_reward_index": perfect_reward_index,
		"level_eight_perfect_reward_index": perfect_reward_index,
		"best_hit_percent_above_level_25": clampi(
			int(seat.get("best_hit_percent_above_level_25", 0)), 0, 100
		),
		"rank_ready": bool(seat.get("rank_ready", false)),
		"only_blue_coins_active": bool(seat.get("only_blue_coins_active", false)),
		"highest_rank": clampi(int(seat.get("highest_rank", 0)), 0, 32),
		"profile_kind": clampi(int(seat.get("profile_kind", 0)), 0, 2),
		"secret_session_earned": secret_flags,
		"start_state": _contract_start_state(seat.get("start_state", {})),
		"shop_unlocks": _contract_shop_unlocks(seat.get("shop_unlocks", [])),
	}


static func _contract_shop_unlocks(value: Variant) -> Array:
	if not value is Array:
		return []
	var unlocks: Array = []
	for entry: Variant in (value as Array):
		var effect := str(entry)
		if effect in TALENT_GATED_EFFECTS and effect not in unlocks:
			unlocks.append(effect)
	unlocks.sort()
	return unlocks


static func _contract_start_state(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var start_state := value as Dictionary
	var result: Dictionary = {}
	for key in START_STATE_INT_KEYS:
		if start_state.has(key):
			result[key] = int(start_state[key])
	for key in START_STATE_BOOL_KEYS:
		if bool(start_state.get(key, false)):
			result[key] = true
	var excluded_value: Variant = start_state.get("excluded_bonus_types", [])
	if excluded_value is Array and not (excluded_value as Array).is_empty():
		var excluded: Array = []
		for entry: Variant in (excluded_value as Array):
			excluded.append(int(entry))
		excluded.sort()
		result["excluded_bonus_types"] = excluded
	return result
