class_name WBProfileStore
extends RefCounted

const DEFAULT_PATH := "user://profiles.json"
const MAX_PROFILES := 10
const PROFILE_VERSION := 5

var _path := DEFAULT_PATH
var _profiles: Array[Dictionary] = []
var last_save_error := ""


func configure_path(path: String) -> void:
	_path = path


func load_profiles() -> Array[Dictionary]:
	_profiles.clear()
	var stored_version := PROFILE_VERSION
	if FileAccess.file_exists(_path):
		var file := FileAccess.open(_path, FileAccess.READ)
		if file != null:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			if parsed is Dictionary:
				stored_version = int(parsed.get("version", 0))
				var stored: Variant = parsed.get("profiles", [])
				if stored is Array:
					for entry: Variant in stored:
						if entry is Dictionary and _is_valid(entry):
							_profiles.append(_sanitize(entry))
	if _profiles.is_empty():
		_profiles.append(_new_profile("PILOT 1"))
		save_profiles()
	elif stored_version < PROFILE_VERSION:
		# Persist additive migrations immediately so a successfully loaded legacy
		# profile cannot remain on disk without the current additive fields.
		save_profiles()
	return profiles()


func profiles() -> Array[Dictionary]:
	return _profiles.duplicate(true)


func add_profile(display_name: String) -> Dictionary:
	if _profiles.size() >= MAX_PROFILES:
		return {}
	var cleaned := display_name.strip_edges().to_upper()
	if cleaned.is_empty():
		cleaned = "PILOT %d" % (_profiles.size() + 1)
	cleaned = cleaned.substr(0, 16)
	var profile := _new_profile(cleaned)
	_profiles.append(profile)
	if not save_profiles():
		_profiles.pop_back()
		return {}
	return profile.duplicate(true)


## Finds the profile bound to an online account id, creating it when absent.
## Account binding bypasses MAX_PROFILES — the cap governs manual creation.
func ensure_profile(profile_id: String, display_name: String) -> Dictionary:
	for profile in _profiles:
		if str(profile.get("id", "")) == profile_id:
			return profile.duplicate(true)
	var cleaned := display_name.strip_edges().to_upper().substr(0, 16)
	if cleaned.is_empty():
		cleaned = "PILOT"
	var profile := _new_profile(cleaned)
	profile["id"] = profile_id
	_profiles.append(profile)
	if not save_profiles():
		_profiles.pop_back()
		return {}
	return profile.duplicate(true)


func record_result(profile_ids: Array, result: Dictionary) -> bool:
	var previous_profiles := _profiles.duplicate(true)
	var terminal_value: Variant = result.get("campaign_terminal", {})
	var terminal: Dictionary = (
		terminal_value as Dictionary if terminal_value is Dictionary else {}
	)
	var completed_full_campaign := (
		str(terminal.get("kind", "")) == "level_100"
		and bool(terminal.get("full_campaign_completed", false))
		and bool(terminal.get("credits_required", false))
	)
	# Endless sessions record the level-100 milestone whenever the run crossed
	# the credits interstitial, regardless of how the run later ended.
	var level_100_score := maxi(
		0,
		int(terminal.get("level_100_score", 0))
	)
	if level_100_score == 0 and completed_full_campaign:
		level_100_score = maxi(0, int(result.get("score", 0)))
	if level_100_score == 0:
		level_100_score = maxi(0, int(result.get("level_100_score", 0)))
	for index in range(_profiles.size()):
		var profile_id := str(_profiles[index].get("id", ""))
		var seat_indices: Array[int] = []
		for seat_index in range(profile_ids.size()):
			if str(profile_ids[seat_index]) == profile_id:
				seat_indices.append(seat_index)
		if seat_indices.is_empty():
			continue
		var history: Array = _profiles[index].get("history", [])
		history.append({
			"completed": bool(result.get("completed", false)),
			"level": int(result.get("level_id", 1)),
			"score": int(result.get("score", 0)),
			"mode": str(result.get("mode", "solo")),
			"difficulty": str(result.get("difficulty", "normal")),
			"at": int(Time.get_unix_time_from_system()),
		})
		while history.size() > 20:
			history.pop_front()
		_profiles[index]["history"] = history
		_profiles[index]["best_score"] = maxi(
			int(_profiles[index].get("best_score", 0)),
			int(result.get("score", 0))
		)
		var profile_stats: Array = result.get("profile_stats", [])
		var best_meteor_score := 0
		var bonus_rounds := 0
		var perfect_bonus_rounds := 0
		var stored_mode_three_perfect_reward_index := int(
			_profiles[index].get(
				"mode_three_perfect_reward_index",
				_profiles[index].get("level_eight_perfect_reward_index", 0)
			)
		)
		var best_hit_percent_above_level_25 := clampi(
			int(_profiles[index].get("best_hit_percent_above_level_25", 0)),
			0,
			100
		)
		var current_mode_three_indices: Array[int] = []
		for seat_index in seat_indices:
			if seat_index >= profile_stats.size() or not profile_stats[seat_index] is Dictionary:
				continue
			var seat_stats: Dictionary = profile_stats[seat_index]
			best_meteor_score = maxi(
				best_meteor_score,
				int(seat_stats.get("meteor_score", 0))
			)
			bonus_rounds += int(seat_stats.get("bonus_rounds", 0))
			perfect_bonus_rounds += int(seat_stats.get("perfect_bonus_rounds", 0))
			if (
				seat_stats.has("mode_three_perfect_reward_index")
				or seat_stats.has("level_eight_perfect_reward_index")
			):
				current_mode_three_indices.append(int(seat_stats.get(
					"mode_three_perfect_reward_index",
					seat_stats.get("level_eight_perfect_reward_index", 0)
				)))
			best_hit_percent_above_level_25 = maxi(
				best_hit_percent_above_level_25,
				clampi(
					int(seat_stats.get("best_hit_percent_above_level_25", 0)),
					0,
					100
				)
			)
		_profiles[index]["best_meteor_score"] = maxi(
			int(_profiles[index].get("best_meteor_score", 0)),
			best_meteor_score
		)
		_profiles[index]["bonus_rounds_total"] = maxi(
			0,
			int(_profiles[index].get("bonus_rounds_total", 0))
			+ bonus_rounds
		)
		_profiles[index]["perfect_bonus_rounds"] = maxi(
			0,
			int(_profiles[index].get("perfect_bonus_rounds", 0))
			+ perfect_bonus_rounds
		)
		var mode_three_perfect_reward_index := stored_mode_three_perfect_reward_index
		if not current_mode_three_indices.is_empty():
			# A result snapshot is authoritative, including a reset to zero after a
			# miss. When one profile owns multiple current seats, retain the furthest
			# chain among those seats without comparing against stale profile state.
			mode_three_perfect_reward_index = current_mode_three_indices.max()
		mode_three_perfect_reward_index = clampi(
			int(mode_three_perfect_reward_index),
			0,
			9
		)
		_profiles[index]["mode_three_perfect_reward_index"] = (
			mode_three_perfect_reward_index
		)
		_profiles[index]["level_eight_perfect_reward_index"] = (
			mode_three_perfect_reward_index
		)
		_profiles[index]["best_hit_percent_above_level_25"] = (
			best_hit_percent_above_level_25
		)
		if completed_full_campaign or level_100_score > 0:
			_profiles[index]["best_level_100_score"] = maxi(
				int(_profiles[index].get("best_level_100_score", 0)),
				level_100_score
			)
		if str(result.get("mode", "")) == "time_trial":
			# Retail match mode 6 keeps its own profile best, which feeds the
			# grouped-best lock tiers alongside the level-100 and Meteor Storm
			# bests (setter 0x005466b0, grouped getter 0x005465d0).
			_profiles[index]["best_time_trial_score"] = maxi(
				int(_profiles[index].get("best_time_trial_score", 0)),
				_time_trial_total_score(result, seat_indices)
			)
		_record_cumulative_statistics(index, seat_indices, result)
	if save_profiles():
		return true
	# A failed immediate write must remain retryable without duplicating history
	# or cumulative bonus totals in memory.
	_profiles = previous_profiles
	return false


## The Time Trial hall of fame and profile best both store the end-of-game
## total, which is the raw score plus the GAME BONUSES sum.
static func _time_trial_total_score(result: Dictionary, seat_indices: Array) -> int:
	var tallies: Array = result.get("tally_by_seat", [])
	var best := 0
	for seat_index in seat_indices:
		if seat_index >= tallies.size() or not tallies[seat_index] is Dictionary:
			continue
		best = maxi(best, int((tallies[seat_index] as Dictionary).get("total_score", 0)))
	if best == 0:
		best = maxi(0, int(result.get("score", 0)))
	return best


## Retail statistics accumulation (docs/evidence/PROFILE_LOCKS.md and the
## game-over sequencer 0x005aafa0): every run adds one game, its level
## reached, its shots/hits/time, unions the secrets seen, and keeps maxima.
func _record_cumulative_statistics(
	index: int,
	seat_indices: Array[int],
	result: Dictionary
) -> void:
	var profile := _profiles[index]
	profile["games_played"] = int(profile.get("games_played", 0)) + 1
	var level_reached := maxi(
		int(result.get("level_reached", result.get("level_id", 1))),
		1
	)
	profile["levels_played_total"] = (
		int(profile.get("levels_played_total", 0)) + level_reached
	)
	profile["highest_level"] = maxi(
		int(profile.get("highest_level", 0)),
		level_reached
	)
	profile["highest_money"] = maxi(
		int(profile.get("highest_money", 0)),
		int(result.get("money", 0))
	)
	profile["total_game_time_ticks"] = (
		int(profile.get("total_game_time_ticks", 0)) + maxi(0, int(result.get("tick", 0)))
	)
	var profile_stats: Array = result.get("profile_stats", [])
	var seat_progression: Array = result.get("seat_progression", [])
	var secrets_this_run := 0
	for seat_index in seat_indices:
		if seat_index < profile_stats.size() and profile_stats[seat_index] is Dictionary:
			var seat_stats: Dictionary = profile_stats[seat_index]
			profile["total_shots"] = (
				int(profile.get("total_shots", 0))
				+ int(seat_stats.get("projectile_objects_fired", 0))
			)
			profile["total_hits"] = (
				int(profile.get("total_hits", 0))
				+ int(seat_stats.get("successful_hits", 0))
			)
			var run_fastest := int(seat_stats.get("fastest_level_clear_ticks", 0))
			if run_fastest > 0:
				var stored_fastest := int(profile.get("fastest_level_clear_ticks", 0))
				if stored_fastest <= 0 or run_fastest < stored_fastest:
					profile["fastest_level_clear_ticks"] = run_fastest
		if (
			seat_index < seat_progression.size()
			and seat_progression[seat_index] is Dictionary
		):
			var progression: Dictionary = seat_progression[seat_index]
			profile["highest_rank"] = clampi(
				maxi(
					int(profile.get("highest_rank", 0)),
					int(progression.get("highest_rank", 0))
				),
				0,
				32
			)
			var seen_flags: Array = progression.get("secret_session_seen", [])
			var run_mask := 0
			for secret_id in range(mini(30, seen_flags.size())):
				if int(seen_flags[secret_id]) != 0:
					run_mask |= 1 << secret_id
			secrets_this_run += _bit_count(run_mask)
			profile["secrets_seen"] = (
				int(profile.get("secrets_seen", 0)) | run_mask
			) & 0x3fffffff
	profile["secrets_one_game_best"] = clampi(
		maxi(int(profile.get("secrets_one_game_best", 0)), secrets_this_run),
		0,
		30
	)


static func _bit_count(value: int) -> int:
	var count := 0
	var remaining := value
	while remaining != 0:
		count += remaining & 1
		remaining >>= 1
	return count


func rename_profile(profile_id: String, display_name: String) -> bool:
	var cleaned := display_name.strip_edges().to_upper().substr(0, 16)
	if cleaned.is_empty():
		return false
	for index in range(_profiles.size()):
		if str(_profiles[index].get("id", "")) == profile_id:
			var previous := str(_profiles[index].get("name", ""))
			_profiles[index]["name"] = cleaned
			if save_profiles():
				return true
			_profiles[index]["name"] = previous
			return false
	return false


func remove_profile(profile_id: String) -> bool:
	for index in range(_profiles.size()):
		if str(_profiles[index].get("id", "")) == profile_id:
			var removed: Dictionary = _profiles[index]
			_profiles.remove_at(index)
			if save_profiles():
				return true
			_profiles.insert(index, removed)
			return false
	return false


func reset_profile_statistics(profile_id: String) -> bool:
	for index in range(_profiles.size()):
		if str(_profiles[index].get("id", "")) == profile_id:
			var previous: Dictionary = _profiles[index].duplicate(true)
			var replacement := _new_profile(str(previous.get("name", "PILOT")))
			replacement["id"] = str(previous.get("id", ""))
			_profiles[index] = _sanitize(replacement)
			if save_profiles():
				return true
			_profiles[index] = previous
			return false
	return false


func save_profiles() -> bool:
	last_save_error = ""
	var temporary_path := _sibling_temporary_path()
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		last_save_error = "Unable to create a temporary profile file."
		return false
	file.store_string(JSON.stringify({
		"version": PROFILE_VERSION,
		"profiles": _profiles,
	}, "\t"))
	var write_error := file.get_error()
	if write_error == OK:
		file.flush()
		write_error = file.get_error()
	file.close()
	if write_error != OK:
		last_save_error = "Unable to flush the temporary profile file."
		_discard_temporary(temporary_path)
		return false

	# The temporary file is a sibling of the canonical file, so this publication
	# is one filesystem rename. The existing canonical profile remains in place
	# unless and until that atomic replacement succeeds.
	var publish_error := _publish_temporary(
		ProjectSettings.globalize_path(temporary_path),
		ProjectSettings.globalize_path(_path)
	)
	if publish_error != OK:
		last_save_error = "Unable to publish the saved profile."
		_discard_temporary(temporary_path)
		return false
	return true


func _sibling_temporary_path() -> String:
	return _path.get_base_dir().path_join(
		".%s.%d.%d.tmp" % [_path.get_file(), get_instance_id(), Time.get_ticks_usec()]
	)


func _publish_temporary(temporary_path: String, canonical_path: String) -> Error:
	return DirAccess.rename_absolute(temporary_path, canonical_path)


func _discard_temporary(path: String) -> void:
	var absolute_path := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(absolute_path):
		DirAccess.remove_absolute(absolute_path)


func _new_profile(display_name: String) -> Dictionary:
	var entropy := "%s:%s:%s" % [display_name, Time.get_ticks_usec(), randi()]
	return {
		"id": entropy.sha256_text().substr(0, 16),
		"name": display_name,
		"best_score": 0,
		"best_meteor_score": 0,
		"bonus_rounds_total": 0,
		"perfect_bonus_rounds": 0,
		"mode_three_perfect_reward_index": 0,
		"level_eight_perfect_reward_index": 0,
		"best_hit_percent_above_level_25": 0,
		"best_level_100_score": 0,
		"best_time_trial_score": 0,
		"highest_rank": 0,
		"games_played": 0,
		"levels_played_total": 0,
		"highest_level": 0,
		"highest_money": 0,
		"total_shots": 0,
		"total_hits": 0,
		"total_game_time_ticks": 0,
		"fastest_level_clear_ticks": 0,
		"fastest_meteor_ms": 0,
		"secrets_seen": 0,
		"secrets_one_game_best": 0,
		"profile_kind": 0,
		"history": [],
	}


func _is_valid(profile: Dictionary) -> bool:
	return not str(profile.get("id", "")).is_empty() and not str(profile.get("name", "")).is_empty()


func _sanitize(profile: Dictionary) -> Dictionary:
	var history: Array = profile.get("history", [])
	var mode_three_perfect_reward_index := clampi(
		int(profile.get(
			"mode_three_perfect_reward_index",
			profile.get("level_eight_perfect_reward_index", 0)
		)),
		0,
		9
	)
	return {
		"id": str(profile.get("id", "")).substr(0, 64),
		"name": str(profile.get("name", "PILOT")).substr(0, 16),
		"best_score": maxi(0, int(profile.get("best_score", 0))),
		"best_meteor_score": maxi(0, int(profile.get("best_meteor_score", 0))),
		"bonus_rounds_total": maxi(0, int(profile.get("bonus_rounds_total", 0))),
		"perfect_bonus_rounds": maxi(0, int(profile.get("perfect_bonus_rounds", 0))),
		"mode_three_perfect_reward_index": mode_three_perfect_reward_index,
		"level_eight_perfect_reward_index": mode_three_perfect_reward_index,
		"best_hit_percent_above_level_25": clampi(
			int(profile.get("best_hit_percent_above_level_25", 0)),
			0,
			100
		),
		"best_level_100_score": maxi(
			0,
			int(profile.get("best_level_100_score", 0))
		),
		"best_time_trial_score": maxi(0, int(profile.get("best_time_trial_score", 0))),
		"highest_rank": clampi(int(profile.get("highest_rank", 0)), 0, 32),
		"games_played": maxi(0, int(profile.get("games_played", 0))),
		"levels_played_total": maxi(0, int(profile.get("levels_played_total", 0))),
		"highest_level": clampi(int(profile.get("highest_level", 0)), 0, 3999),
		"highest_money": maxi(0, int(profile.get("highest_money", 0))),
		"total_shots": maxi(0, int(profile.get("total_shots", 0))),
		"total_hits": maxi(0, int(profile.get("total_hits", 0))),
		"total_game_time_ticks": maxi(0, int(profile.get("total_game_time_ticks", 0))),
		"fastest_level_clear_ticks": maxi(
			0, int(profile.get("fastest_level_clear_ticks", 0))
		),
		"fastest_meteor_ms": maxi(0, int(profile.get("fastest_meteor_ms", 0))),
		"secrets_seen": int(profile.get("secrets_seen", 0)) & 0x3fffffff,
		"secrets_one_game_best": clampi(
			int(profile.get("secrets_one_game_best", 0)), 0, 30
		),
		"profile_kind": clampi(int(profile.get("profile_kind", 0)), 0, 2),
		"history": history.slice(maxi(0, history.size() - 20)),
	}
