class_name WBMatchConfig
extends RefCounted

const MatchContract := preload("res://src/shared/match_contract.gd")
const ProtocolContract := preload("res://src/net/protocol_codec.gd")
const MODES := ["solo", "coop", "time_trial"]
const MODE_TIME_TRIAL := "time_trial"
const DIFFICULTIES := ["easy", "normal", "hard", "ace"]
const COOP_BALANCE := ["classic", "balanced"]
const CONTENT_VERSION: int = MatchContract.CONTENT_VERSION
const MAX_END_LEVEL: int = MatchContract.MAX_END_LEVEL


## A fresh 63-bit match seed from the OS CSPRNG. Seeds ride the contract as
## strings, so the full int64 range survives the wire; the sign bit is
## cleared only so logs and JSON stay unsigned-looking, and zero is avoided
## because make() treats it as "pick one for me".
static func random_seed() -> int:
	var bytes := Crypto.new().generate_random_bytes(8)
	var value := 0
	for index in range(8):
		value = (value << 8) | int(bytes[index])
	value = value & 0x7FFFFFFFFFFFFFFF
	return value if value != 0 else 1


static func make(
	mode: String,
	difficulty: String,
	coop_balance: String,
	profiles: Array,
	collision_mode: String,
	seed: int = 0,
	talents: Dictionary = {}
) -> Dictionary:
	var valid_mode := mode if mode in MODES else "solo"
	var valid_difficulty := difficulty if difficulty in DIFFICULTIES else "normal"
	var valid_balance := coop_balance if coop_balance in COOP_BALANCE else "classic"
	var resolved_seed := seed
	if resolved_seed == 0:
		resolved_seed = int(Time.get_unix_time_from_system()) ^ int(Time.get_ticks_usec())
	# Talents apply to solo and co-op only; Time Trial stays seed-fair. The
	# grants dictionary is the backend's composed shape: per-seat start_state
	# additions, a top-level rocket grant, and the licensed shop effects.
	var talents_active := (
		bool(talents.get("enabled", false)) and valid_mode != MODE_TIME_TRIAL
	)
	var seats: Array[Dictionary] = []
	var seat_count := WBInputRouter.seats_for_mode(valid_mode)
	for seat in range(seat_count):
		var profile: Dictionary = profiles[seat] if seat < profiles.size() and profiles[seat] is Dictionary else {}
		var mode_three_perfect_reward_index := clampi(
			int(profile.get(
				"mode_three_perfect_reward_index",
				profile.get("level_eight_perfect_reward_index", 0)
			)),
			0,
			9
		)
		var start_state := compute_start_state(profile, valid_mode)
		if talents_active and seat == 0:
			start_state = merge_talent_grants(
				start_state, talents.get("start_state", {}) as Dictionary
			)
		seats.append({
			"seat": seat,
			"profile_id": str(profile.get("id", "guest_%d" % seat)),
			"display_name": str(profile.get("name", "GUEST %d" % (seat + 1))),
			"mode_three_perfect_reward_index": mode_three_perfect_reward_index,
			"level_eight_perfect_reward_index": mode_three_perfect_reward_index,
			"best_hit_percent_above_level_25": clampi(
				int(profile.get("best_hit_percent_above_level_25", 0)),
				0,
				100
			),
			# Rank readiness starts as session state and is earned through the
			# full-marker shop reward; the blue-only flag comes from the
			# 20,000-games profile lock inside the start state.
			"rank_ready": false,
			"only_blue_coins_active": bool(start_state.get("only_blue_coins", false)),
			# Retail runs always start at ENSIGN; the profile persists the
			# highest rank reached for statistics and the terminal-rank lock.
			"highest_rank": int(profile.get("highest_rank", 0)),
			"profile_kind": int(profile.get("profile_kind", 0)),
			"secret_session_earned": profile_secret_flags(profile),
			"start_state": start_state,
			"shop_unlocks": (
				(talents.get("shop_unlocks", []) as Array).duplicate()
				if talents_active and seat == 0
				else []
			),
			"local": true,
		})
	return {
		"protocol_version": ProtocolContract.VERSION,
		"content_version": CONTENT_VERSION,
		"mode": valid_mode,
		"difficulty": valid_difficulty,
		"coop_balance": valid_balance,
		"collision_mode": collision_mode if collision_mode in ["pixel", "simple"] else "pixel",
		"seed": resolved_seed,
		"seat_count": seat_count,
		"seats": seats,
		"start_level": 1,
		"end_level": MAX_END_LEVEL,
		"starting_rockets": (
			clampi(int(talents.get("starting_rockets", 0)), 0, 50)
			if talents_active
			else 0
		),
		"talents_enabled": talents_active,
	}


## Merges talent grants on top of the traced profile-lock start state: MAX
## for every int key, OR for every bool key, so a lock package always keeps
## its dominance (the 100,000-games 25-bullet magazine beats an 18-bullet
## talent). Talents never write excluded_bonus_types, and values are re-cast
## because they cross a JSON boundary as floats.
static func merge_talent_grants(start_state: Dictionary, grants: Dictionary) -> Dictionary:
	var result := start_state.duplicate(true)
	for key: Variant in grants.keys():
		var name := str(key)
		var value: Variant = grants[key]
		if name in MatchContract.START_STATE_BOOL_KEYS:
			if bool(value):
				result[name] = true
		elif name in MatchContract.START_STATE_INT_KEYS:
			result[name] = maxi(int(result.get(name, 0)), int(value))
	return result


## The persisted secrets-seen bitmask becomes the sim's 30-entry earned list.
static func profile_secret_flags(profile: Dictionary) -> Array:
	var mask := int(profile.get("secrets_seen", 0))
	var flags: Array = []
	for secret_id in range(30):
		flags.append(1 if (mask & (1 << secret_id)) != 0 else 0)
	return flags


## The locks screen groups the level-100, Time Trial, and Meteor Storm bests
## under one tier list, and the applier's match-mode-6 branch reads that group
## through getter 0x005465d0. The remake evaluates the group as the maximum of
## the three stored bests.
static func grouped_best_score(profile: Dictionary) -> int:
	return maxi(
		maxi(
			int(profile.get("best_level_100_score", 0)),
			int(profile.get("best_time_trial_score", 0))
		),
		int(profile.get("best_meteor_score", 0))
	)


## The match-mode-6 branch of the retail applier (0x0054d440) skips every
## in-the-game score tier and every weapon tier — those are gated on match mode
## != 6, which is why Time Trial always starts on weapon 0 — and applies only
## the grouped-best tiers. The timed effects run for the bonus-time value in
## seconds (retail multiplies the same global by 1000 for milliseconds).
static func compute_time_trial_start_state(profile: Dictionary) -> Dictionary:
	var start_state: Dictionary = {}
	var grouped_best := grouped_best_score(profile)
	if grouped_best >= 5000000:
		start_state["timed_score_multiplier"] = 2
	if grouped_best >= 6000000:
		start_state["timed_scoop"] = true
	if grouped_best >= 7000000:
		start_state["timed_score_multiplier"] = 5
	if grouped_best >= 8000000:
		start_state["auto_fire"] = true
	if grouped_best >= 9000000:
		start_state["speed_steps"] = 3
		start_state["bonus_time"] = 30
	if grouped_best >= 10000000:
		start_state["speed_steps"] = 5
		start_state["bonus_time"] = 30
	if grouped_best >= 15000000:
		start_state["super_auto_fire"] = true
	if grouped_best >= 17000000:
		start_state["speed_max"] = true
	if grouped_best >= 20000000:
		start_state["time_trial_extra_minute"] = true
	return start_state


## Evaluates the executable-backed profile lock table
## (docs/evidence/PROFILE_LOCKS.md) into the seat start state. Ordered tiers
## override earlier ones exactly like the retail applier at 0x0054d440.
## Locks apply only to solo and Time Trial matches with a profile.
static func compute_start_state(profile: Dictionary, mode: String) -> Dictionary:
	if profile.is_empty():
		return {}
	if mode == MODE_TIME_TRIAL:
		return compute_time_trial_start_state(profile)
	if mode != "solo":
		return {}
	var start_state: Dictionary = {}
	var best_score := int(profile.get("best_score", 0))
	var games_played := int(profile.get("games_played", 0))
	var secrets_seen := int(profile.get("secrets_seen", 0))
	var highest_rank := int(profile.get("highest_rank", 0))

	# In-the-game score tiers (ascending; later writes win).
	if best_score >= 5000000:
		start_state["bullet_capacity"] = 10
	if best_score >= 7500000:
		start_state["speed_steps"] = 3
	if best_score >= 10000000:
		start_state["auto_fire"] = true
	if best_score >= 20000000:
		start_state["weapon_at_least"] = 1
	if best_score >= 50000000:
		start_state["armour_charges"] = 1
	if best_score >= 100000000:
		start_state["money"] = 500
	if best_score >= 250000000:
		start_state["money"] = 1000
	if best_score >= 500000000:
		start_state["armour_charges"] = 2
	if best_score >= 1000000000:
		start_state["weapon_at_least"] = maxi(
			int(start_state.get("weapon_at_least", 0)), 2
		)

	# Games-played tiers.
	var excluded_bonus_types: Array = []
	if games_played >= 1000:
		start_state["autofire_through_shop"] = true
	if games_played >= 2500:
		start_state["missile_stealth"] = true
	if games_played >= 5000:
		start_state["gem_counter"] = true
	if games_played >= 10000:
		excluded_bonus_types.append(12)
	if games_played >= 15000:
		excluded_bonus_types.append(13)
	if games_played >= 20000:
		start_state["only_blue_coins"] = true
	if games_played >= 25000:
		excluded_bonus_types.append(14)
	if games_played >= 35000:
		start_state["meteor_storm_multiplier_enabled"] = true
	if games_played >= 50000:
		start_state["weapon_at_least"] = maxi(
			int(start_state.get("weapon_at_least", 0)), 3
		)
	if games_played >= 75000:
		start_state["bullet_speed_up"] = true
	if games_played >= 100000:
		# The traced good-start package: half-maximum speed, 25 bullets,
		# half of the difficulty bonus-time maximum, 5,000 cash.
		start_state["speed_half_max"] = true
		start_state["bullet_capacity"] = 25
		start_state["bonus_time_half_max"] = true
		start_state["money"] = 5000
	if not excluded_bonus_types.is_empty():
		start_state["excluded_bonus_types"] = excluded_bonus_types

	# Fastest Meteor Storm locks raise the Extra Time ceiling; the field
	# stays unset until its retail producer is traced.
	var fastest_meteor_ms := int(profile.get("fastest_meteor_ms", 0))
	if fastest_meteor_ms > 0 and fastest_meteor_ms <= 2000:
		start_state["bonus_time_max"] = 60
	if fastest_meteor_ms > 0 and fastest_meteor_ms <= 1000:
		start_state["bonus_time_max"] = 90

	# Find all 30 secrets: full armour (2,000 cash handled by the sim when
	# armour is already full is unreachable at start) and Super Triple.
	var secrets_found := 0
	for secret_id in range(30):
		if (secrets_seen & (1 << secret_id)) != 0:
			secrets_found += 1
	if secrets_found >= 30:
		start_state["armour_charges"] = 2
		start_state["weapon_at_least"] = maxi(
			int(start_state.get("weapon_at_least", 0)), 4
		)

	# Above 200,000,000: the secret counter display starts on.
	if best_score > 200000000:
		start_state["secret_counter"] = true

	# The undocumented terminal-rank package (WARBLADE GOD SOL, index 32).
	if highest_rank >= 32:
		start_state["bonus_time_full_max"] = true
		start_state["money"] = 25000
		start_state["rank_32_bullet_speed"] = true
		start_state["weapon_at_least"] = 8
		start_state["super_auto_fire"] = true
		start_state["auto_fire"] = true
		start_state["bullet_capacity"] = 25
	return start_state


static func validate(config: Dictionary) -> bool:
	if not MatchContract.has_current_versions(config):
		return false
	if str(config.get("mode", "")) not in MODES:
		return false
	if str(config.get("difficulty", "")) not in DIFFICULTIES:
		return false
	if str(config.get("coop_balance", "")) not in COOP_BALANCE:
		return false
	if not MatchContract.has_valid_level_range(config):
		return false
	var seat_count := int(config.get("seat_count", 0))
	return seat_count == WBInputRouter.seats_for_mode(str(config["mode"]))
