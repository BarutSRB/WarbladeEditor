extends SceneTree

const Server := preload("res://src/server/authoritative_server.gd")
const MatchContract := preload("res://src/shared/match_contract.gd")

var _failures: Array[String] = []
var _last_ack_type := 0
var _last_ack_accepted := false
var _last_ack_details: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _test_spawned_sidecar()
	await _test_session_process_keeps_sidecar_alive()
	await _test_couch_owns_both_seats()
	await _test_two_client_seat_ownership()
	await _test_invalid_token_rejected()
	await _test_match_contract_mismatch_rejected()
	await _test_lobby_hello_configures_match()
	await _test_lobby_time_trial_single_seat()
	await _test_lobby_rejects_conflicting_author()
	await _test_lobby_resume_rejects_missing_slot()
	await _test_lobby_non_loopback_bind_rules()
	await _test_session_online_endpoint_resolution()
	if _failures.is_empty():
		print("NETWORK INTEGRATION TESTS PASSED")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("NETWORK INTEGRATION TESTS FAILED: %d" % _failures.size())
	quit(1)


func _test_spawned_sidecar() -> void:
	var adapter := WBNetworkSessionAdapter.new()
	adapter.command_acknowledged.connect(_record_ack)
	var config := _config("solo", 1)
	config.seats = [{"best_hit_percent_above_level_25": 84}]
	_expect(adapter.configure(config), "normal client transport should launch its sidecar")
	_expect(await _wait_for_adapter(adapter), "spawned sidecar should authenticate and send a snapshot")
	var initial := adapter.get_snapshot()
	_expect(
		int(initial.get("tick", -1)) >= 0,
		"spawned sidecar should publish authoritative state from the welcome tick"
	)
	_expect(
		int(initial.get("end_level_id", 0)) == MatchContract.MAX_END_LEVEL,
		"spawned sidecar should use the complete level-one-hundred campaign boundary"
	)
	_expect(
		int(initial.get("profile_stats", [])[0].get(
			"best_hit_percent_above_level_25",
			0
		)) == 84,
		"spawned sidecar should hydrate the owning profile's accuracy history"
	)
	_expect(str(initial.get("state_hash", "")).length() == 64, "snapshot should carry the authoritative state hash")
	var initial_x := _player_x(initial, 0)
	for index in range(12):
		adapter.submit_input(0, WBInputRouter.INPUT_RIGHT)
		adapter.poll()
		await physics_frame
	_expect(
		await _wait_for_snapshot_after(adapter, int(initial.get("tick", 0))),
		"spawned sidecar should publish state after input"
	)
	_expect(_player_x(adapter.get_snapshot(), 0) > initial_x, "server should apply client input to its own state")

	_reset_ack()
	_expect(adapter.request_pause(true), "seat zero should be able to request authoritative pause")
	_expect(await _wait_for_ack(adapter, ProtocolCodec.MessageType.PAUSE), "pause should be acknowledged")
	_expect(_last_ack_accepted and bool(_last_ack_details.get("paused", false)), "pause acknowledgement should confirm paused state")
	var paused_tick := int(adapter.get_snapshot().get("tick", 0))
	for index in range(12):
		adapter.poll()
		await physics_frame
	_expect(
		int(adapter.get_snapshot().get("tick", 0)) == paused_tick,
		"authoritative simulation must not advance while paused"
	)

	_reset_ack()
	_expect(adapter.request_pause(false), "seat zero should be able to request resume")
	_expect(await _wait_for_ack(adapter, ProtocolCodec.MessageType.PAUSE), "resume should be acknowledged")
	_expect(_last_ack_accepted and not bool(_last_ack_details.get("paused", true)), "resume acknowledgement should clear pause")
	_expect(await _wait_for_snapshot_after(adapter, paused_tick), "authoritative simulation should resume after acknowledgement")
	var sidecar_pid := int(adapter._sidecar_pid)
	adapter.close()
	_expect(
		await _wait_for_process_exit(sidecar_pid),
		"explicit close should retire the exact sidecar through its private shutdown channel"
	)


func _test_session_process_keeps_sidecar_alive() -> void:
	var session := WBClientSession.new()
	root.add_child(session)
	_expect(
		session.begin(_config("solo", 1)),
		"client session should launch its authoritative sidecar"
	)
	for attempt in range(720):
		await process_frame
		if not session.snapshot().is_empty():
			break
	var initial := session.snapshot()
	_expect(
		not initial.is_empty(),
		"node processing alone should authenticate without gameplay advance calls"
	)
	var initial_tick := int(initial.get("tick", -1))
	var heartbeat_path := str(session._network._sidecar_heartbeat_path)
	var initial_heartbeat := _read_text(heartbeat_path)
	var observed_advance := false
	for frame_index in range(180):
		await physics_frame
		if int(session.snapshot().get("tick", -1)) > initial_tick:
			observed_advance = true
			break
	var later := session.snapshot()
	_expect(
		observed_advance and int(later.get("tick", -1)) > initial_tick,
		"results-style dwell should keep polling snapshots without advance_tick"
	)
	session._network._last_heartbeat_write_usec = (
		Time.get_ticks_usec() - WBNetworkSessionAdapter.HEARTBEAT_INTERVAL_USEC
	)
	for frame_index in range(3):
		await process_frame
	_expect(
		not initial_heartbeat.is_empty()
		and _read_text(heartbeat_path) != initial_heartbeat,
		"results-style dwell should continue refreshing the sidecar heartbeat"
	)
	var sidecar_pid := int(session._network._sidecar_pid)
	session.close()
	session.queue_free()
	await process_frame
	_expect(
		await _wait_for_process_exit(sidecar_pid),
		"session close should gracefully retire its sidecar without signaling a stale PID"
	)


func _test_couch_owns_both_seats() -> void:
	var server := Server.new()
	root.add_child(server)
	var config := _config("coop", 2)
	var started := server.start_local(config, "", 0, "couch-token")
	_expect(bool(started.get("ok", false)), "couch test server should start")
	if not bool(started.get("ok", false)):
		server.queue_free()
		await process_frame
		return
	var adapter := WBNetworkSessionAdapter.new()
	_expect(adapter.configure(config, {
		"host": "127.0.0.1",
		"port": int(started.get("port", 0)),
		"token": "couch-token",
	}), "couch client should begin loopback connection")
	_expect(await _wait_for_adapter(adapter), "couch client should authenticate both seats")
	var connection_state := server.get_connection_state()
	var peers: Dictionary = connection_state.get("peers", {})
	_expect(peers.size() == 1, "one couch process should use one authenticated peer")
	if peers.size() == 1:
		var peer_state: Dictionary = peers.values()[0]
		_expect(peer_state.get("seat_ids", []) == [0, 1], "couch peer should atomically own seats zero and one")
	var initial := adapter.get_snapshot()
	var player_zero_x := _player_x(initial, 0)
	var player_one_x := _player_x(initial, 1)
	for index in range(12):
		adapter.submit_input(0, WBInputRouter.INPUT_LEFT)
		adapter.submit_input(1, WBInputRouter.INPUT_RIGHT)
		adapter.poll()
		await physics_frame
	_expect(
		await _wait_for_snapshot_after(adapter, int(initial.get("tick", 0))),
		"couch server should publish both players after input"
	)
	var current := adapter.get_snapshot()
	_expect(_player_x(current, 0) < player_zero_x, "couch player one input should be authoritative")
	_expect(_player_x(current, 1) > player_one_x, "couch player two input should be authoritative")
	for index in range(72):
		adapter.submit_input(0, WBInputRouter.INPUT_LEFT)
		adapter.submit_input(1, WBInputRouter.INPUT_RIGHT)
		adapter.poll()
		await physics_frame
	_expect(
		int(server.get_rejection_counters().get("total", 0)) == 0,
		"normal two-seat input refresh must stay below the server rate limit"
	)
	adapter.close()
	server.stop()
	server.queue_free()
	await process_frame


func _test_two_client_seat_ownership() -> void:
	var server := Server.new()
	root.add_child(server)
	var config := _config("coop", 2)
	var started := server.start_local(config, "", 0, "two-client-token")
	_expect(bool(started.get("ok", false)), "two-client test server should start")
	if not bool(started.get("ok", false)):
		server.queue_free()
		await process_frame
		return
	var first := WBNetworkSessionAdapter.new()
	var second := WBNetworkSessionAdapter.new()
	var endpoint := {
		"host": "127.0.0.1",
		"port": int(started.get("port", 0)),
		"token": "two-client-token",
	}
	var first_options := endpoint.duplicate()
	first_options["seat"] = 0
	var second_options := endpoint.duplicate()
	second_options["seat"] = 1
	_expect(first.configure(config, first_options), "first process should request seat zero")
	_expect(second.configure(config, second_options), "second process should request seat one")
	_expect(await _wait_for_two_adapters(first, second), "two processes should authenticate independently")
	var state := server.get_connection_state()
	_expect(int(state.get("required_seats", 0)) == 2, "co-op server should require two seats")
	_expect(not bool(state.get("waiting_for_seats", true)), "server should start only after both clients authenticate")
	_expect((state.get("peers", {}) as Dictionary).size() == 2, "server should track two independent peers")
	_expect(first.request_pause(true), "seat-zero client should request a shared authoritative pause")
	_expect(
		await _wait_for_two_pause_states(first, second, true),
		"both independent clients should receive the same paused snapshot"
	)
	_expect(server.paused, "two-client pause should freeze the authoritative server")
	var paused_tick := int(first.get_snapshot().get("tick", -1))
	_expect(
		int(second.get_snapshot().get("tick", -2)) == paused_tick,
		"both clients should observe pause at the same authoritative tick"
	)
	_expect(first.request_pause(false), "seat-zero client should request a shared resume")
	_expect(
		await _wait_for_two_pause_states(first, second, false),
		"both independent clients should receive the same resumed snapshot"
	)
	_expect(not second.request_pause(true), "seat-one client should reject pause locally without damaging its session")
	_expect(second.is_ready(), "rejected seat-one pause must leave the client connected")
	second.close()
	_expect(
		await _wait_for_waiting_state(first),
		"the surviving peer should receive an immediate same-tick waiting snapshot"
	)
	first.close()
	server.stop()
	server.queue_free()
	await process_frame


func _test_invalid_token_rejected() -> void:
	var server := Server.new()
	root.add_child(server)
	var config := _config("solo", 1)
	var started := server.start_local(config, "", 0, "correct-token")
	_expect(bool(started.get("ok", false)), "rejection test server should start")
	if not bool(started.get("ok", false)):
		server.queue_free()
		await process_frame
		return
	var adapter := WBNetworkSessionAdapter.new()
	adapter.configure(config, {
		"host": "127.0.0.1",
		"port": int(started.get("port", 0)),
		"token": "wrong-token",
		"seat": 0,
	})
	for index in range(180):
		adapter.poll()
		await physics_frame
		if not adapter.last_error().is_empty():
			break
	_expect(
		adapter.last_error().contains("rejected"),
		"invalid sidecar token should be rejected before any state is accepted"
	)
	_expect(adapter.get_snapshot().is_empty(), "rejected client must not receive authoritative state")
	adapter.close()
	server.stop()
	server.queue_free()
	await process_frame


func _test_match_contract_mismatch_rejected() -> void:
	var server := Server.new()
	root.add_child(server)
	var server_config := _config("solo", 1)
	var started := server.start_local(server_config, "", 0, "contract-token")
	_expect(bool(started.get("ok", false)), "contract test server should start")
	if not bool(started.get("ok", false)):
		server.queue_free()
		await process_frame
		return
	var client_config := server_config.duplicate(true)
	client_config["difficulty"] = "ace"
	var adapter := WBNetworkSessionAdapter.new()
	_expect(adapter.configure(client_config, {
		"host": "127.0.0.1",
		"port": int(started.get("port", 0)),
		"token": "contract-token",
		"seat": 0,
	}), "mismatched client should reach the authenticated contract check")
	for index in range(240):
		adapter.poll()
		await physics_frame
		if not adapter.last_error().is_empty():
			break
	_expect(
		adapter.last_error().contains("already running a different match"),
		"the server should reject an authoring HELLO whose contract differs from the live match"
	)
	_expect(adapter.get_snapshot().is_empty(), "mismatched clients must not accept server state")
	adapter.close()
	server.stop()
	server.queue_free()
	await process_frame


## The online product path: an idle lobby server is configured by the first
## authenticated HELLO, including the per-seat profile-lock start state that
## the retired CLI bridge used to drop, and returns to the lobby for a
## different match once its peers leave.
func _test_lobby_hello_configures_match() -> void:
	var server := Server.new()
	root.add_child(server)
	var started := server.start_lobby("127.0.0.1", 0, "lobby-token")
	_expect(bool(started.get("ok", false)), "the lobby server should start with no configured match")
	if not bool(started.get("ok", false)):
		server.queue_free()
		await process_frame
		return
	var idle_state := server.get_connection_state()
	_expect(
		bool(idle_state.get("lobby", false)) and not bool(idle_state.get("match_configured", true)),
		"an idle lobby is running with no simulation"
	)
	var endpoint := {
		"host": "127.0.0.1",
		"port": int(started.get("port", 0)),
		"token": "lobby-token",
	}
	var config := _config("solo", 1)
	config["difficulty"] = "hard"
	config["seats"] = [{
		"profile_id": "locked_pilot",
		"start_state": {"money": 500, "weapon_at_least": 2, "auto_fire": true},
	}]
	var adapter := WBNetworkSessionAdapter.new()
	_expect(adapter.configure(config, endpoint), "an online client should connect to the lobby")
	_expect(await _wait_for_adapter(adapter), "the first HELLO should configure and start the match")
	var snapshot := adapter.get_snapshot()
	_expect(
		str(snapshot.get("difficulty", "")) == "hard",
		"the lobby runs the client-requested difficulty"
	)
	var shared: Dictionary = snapshot.get("shared", {})
	_expect(
		int(shared.get("money", -1)) == 500,
		"profile-lock start money reaches the networked simulation"
	)
	_expect(
		int(shared.get("weapon_id", -1)) >= 2,
		"profile-lock starting weapons reach the networked simulation"
	)
	adapter.close()
	var returned_to_lobby := false
	for index in range(240):
		await physics_frame
		if not bool(server.get_connection_state().get("match_configured", true)):
			returned_to_lobby = true
			break
	_expect(
		returned_to_lobby,
		"the lobby tears the match down when its last authenticated peer leaves"
	)
	var second_config := _config("solo", 1)
	second_config["seed"] = 777_001
	var second := WBNetworkSessionAdapter.new()
	_expect(second.configure(second_config, endpoint), "the lobby should accept a new client")
	_expect(
		await _wait_for_adapter(second),
		"the same lobby process should run a different follow-up match"
	)
	_expect(
		str(second.get_snapshot().get("difficulty", "")) == "normal",
		"the follow-up match uses its own requested contract"
	)
	second.close()
	server.stop()
	server.queue_free()
	await process_frame


## Time Trial is retail match mode 6 and single seat; the seat-count contract
## keeps a networked Time Trial from waiting forever for a second player.
func _test_lobby_time_trial_single_seat() -> void:
	var server := Server.new()
	root.add_child(server)
	var started := server.start_lobby("127.0.0.1", 0, "trial-token")
	_expect(bool(started.get("ok", false)), "the Time Trial lobby should start")
	if not bool(started.get("ok", false)):
		server.queue_free()
		await process_frame
		return
	var adapter := WBNetworkSessionAdapter.new()
	_expect(adapter.configure(_config("time_trial", 1), {
		"host": "127.0.0.1",
		"port": int(started.get("port", 0)),
		"token": "trial-token",
	}), "a Time Trial client should connect to the lobby")
	_expect(await _wait_for_adapter(adapter), "a networked Time Trial should authenticate and start")
	var state := server.get_connection_state()
	_expect(
		int(state.get("required_seats", 0)) == 1,
		"a networked Time Trial requires exactly one seat"
	)
	_expect(
		not bool(state.get("waiting_for_seats", true)),
		"a solo Time Trial seat starts the authoritative clock immediately"
	)
	var first_tick := int(adapter.get_snapshot().get("tick", -1))
	_expect(
		await _wait_for_snapshot_after(adapter, first_tick),
		"the authoritative Time Trial simulation advances for its single seat"
	)
	_expect(
		str(adapter.get_snapshot().get("mode", "")) == "time_trial",
		"the authoritative snapshot carries the Time Trial mode"
	)
	adapter.close()
	server.stop()
	server.queue_free()
	await process_frame


func _test_lobby_rejects_conflicting_author() -> void:
	var server := Server.new()
	root.add_child(server)
	var started := server.start_lobby("127.0.0.1", 0, "conflict-token")
	_expect(bool(started.get("ok", false)), "the conflict lobby should start")
	if not bool(started.get("ok", false)):
		server.queue_free()
		await process_frame
		return
	var endpoint := {
		"host": "127.0.0.1",
		"port": int(started.get("port", 0)),
		"token": "conflict-token",
	}
	var first_config := _config("solo", 1)
	var first := WBNetworkSessionAdapter.new()
	_expect(first.configure(first_config, endpoint), "the authoring client should connect")
	_expect(await _wait_for_adapter(first), "the authoring client should start its match")
	var second_config := _config("solo", 1)
	second_config["seed"] = 999_999
	var second_options := endpoint.duplicate()
	second_options["seat"] = 0
	var second := WBNetworkSessionAdapter.new()
	_expect(
		second.configure(second_config, second_options),
		"the conflicting author should reach the server"
	)
	for index in range(240):
		second.poll()
		await physics_frame
		if not second.last_error().is_empty():
			break
	_expect(
		second.last_error().contains("already running a different match"),
		"a second author with a different contract is rejected while the match runs"
	)
	_expect(
		first.is_ready() and first.last_error().is_empty(),
		"the running match is untouched by the rejected author"
	)
	first.close()
	second.close()
	server.stop()
	server.queue_free()
	await process_frame


func _test_lobby_resume_rejects_missing_slot() -> void:
	var server := Server.new()
	root.add_child(server)
	var started := server.start_lobby("127.0.0.1", 0, "resume-token")
	_expect(bool(started.get("ok", false)), "the resume lobby should start")
	if not bool(started.get("ok", false)):
		server.queue_free()
		await process_frame
		return
	var config := _config("solo", 1)
	config["resume_slot"] = 99
	var adapter := WBNetworkSessionAdapter.new()
	_expect(adapter.configure(config, {
		"host": "127.0.0.1",
		"port": int(started.get("port", 0)),
		"token": "resume-token",
	}), "the resuming client should reach the server")
	for index in range(240):
		adapter.poll()
		await physics_frame
		if not adapter.last_error().is_empty():
			break
	_expect(
		adapter.last_error().contains("could not resume the saved run"),
		"resuming a slot the server does not hold fails with a readable reason"
	)
	_expect(
		not bool(server.get_connection_state().get("match_configured", true)),
		"a failed resume leaves the lobby idle for the next match"
	)
	adapter.close()
	server.stop()
	server.queue_free()
	await process_frame


## The online deployment path: binding beyond loopback must be deliberate, and
## a wildcard-bound server accepts an ordinary loopback client.
func _test_lobby_non_loopback_bind_rules() -> void:
	var server := Server.new()
	root.add_child(server)
	var missing_port := server.start_lobby("0.0.0.0", 0, "wan-token")
	_expect(
		not bool(missing_port.get("ok", false))
		and str(missing_port.get("error", "")).contains("--port"),
		"a non-loopback server requires an explicit port"
	)
	var missing_token := server.start_lobby("0.0.0.0", 45911, "")
	_expect(
		not bool(missing_token.get("ok", false))
		and str(missing_token.get("error", "")).contains("--token"),
		"a non-loopback server requires an explicit session token"
	)
	var invalid_host := server.start_lobby("play.example.com", 45911, "wan-token")
	_expect(
		not bool(invalid_host.get("ok", false)),
		"the bind host must be a concrete IP or the wildcard, not a hostname"
	)
	var started := server.start_lobby("0.0.0.0", 45911, "wan-token")
	_expect(
		bool(started.get("ok", false)),
		"a wildcard bind with an explicit port and token starts"
	)
	if bool(started.get("ok", false)):
		var adapter := WBNetworkSessionAdapter.new()
		_expect(adapter.configure(_config("solo", 1), {
			"host": "127.0.0.1",
			"port": 45911,
			"token": "wan-token",
		}), "a client should reach the wildcard-bound server")
		_expect(
			await _wait_for_adapter(adapter),
			"the wildcard-bound lobby authenticates and starts the match"
		)
		adapter.close()
	server.stop()
	server.queue_free()
	await process_frame


## The client session resolves its game server from the match configuration:
## an incomplete direct endpoint fails fast with guidance instead of
## silently falling back to local play, and a complete one connects.
func _test_session_online_endpoint_resolution() -> void:
	var failures: Array[String] = []
	var unconfigured := WBClientSession.new()
	root.add_child(unconfigured)
	unconfigured.session_failed.connect(func(message: String) -> void:
		failures.append(message)
	)
	var config := _config("solo", 1)
	config["server"] = {"kind": "direct"}
	_expect(
		not unconfigured.begin(config),
		"an incomplete direct endpoint fails the session immediately"
	)
	_expect(
		not failures.is_empty() and failures.back().contains("address"),
		"the failure tells the player what the direct endpoint needs"
	)
	unconfigured.queue_free()
	await process_frame

	var server := Server.new()
	root.add_child(server)
	var started := server.start_lobby("127.0.0.1", 0, "online-token")
	_expect(bool(started.get("ok", false)), "the online-resolution lobby should start")
	if not bool(started.get("ok", false)):
		server.queue_free()
		await process_frame
		return
	var session := WBClientSession.new()
	root.add_child(session)
	var online_config := _config("solo", 1)
	online_config["server"] = {
		"kind": "direct",
		"host": "127.0.0.1",
		"port": int(started.get("port", 0)),
		"token": "online-token",
	}
	_expect(session.begin(online_config), "a configured online server accepts the session")
	var got_snapshot := false
	for index in range(720):
		await physics_frame
		if not session.snapshot().is_empty():
			got_snapshot = true
			break
	_expect(got_snapshot, "the online session plays through the configured game server")
	_expect(
		session.server_description() == "127.0.0.1:%d" % int(started.get("port", 0)),
		"the session names the online endpoint it is playing on"
	)
	_expect(
		not session.is_local_test_server(),
		"an online session never runs through the local test server"
	)
	session.close()
	session.queue_free()
	server.stop()
	server.queue_free()
	await process_frame


## The immediate post-welcome broadcast makes the first received snapshot the
## exact configure-time authoritative state; boss entry pins assert on it so
## snapshot cadence and physics catch-up cannot skew what they observe.
func _capture_first_snapshot(adapter: WBNetworkSessionAdapter) -> Array[Dictionary]:
	var captured: Array[Dictionary] = []
	adapter.snapshot_received.connect(func(received: Dictionary) -> void:
		if captured.is_empty():
			captured.append(received)
	)
	return captured


func _first_snapshot(captured: Array[Dictionary]) -> Dictionary:
	return captured[0] if not captured.is_empty() else {}


## Authored enemy projections exist once the level has stepped; the first
## cadence broadcast at tick three is the earliest deterministic observation.
func _snapshot_at_or_after(adapter: WBNetworkSessionAdapter, minimum_tick: int) -> Dictionary:
	for index in range(720):
		adapter.poll()
		await physics_frame
		var snapshot := adapter.get_snapshot()
		if int(snapshot.get("tick", -1)) >= minimum_tick:
			return snapshot
		if not adapter.last_error().is_empty():
			return {}
	return adapter.get_snapshot()


func _wait_for_adapter(adapter: WBNetworkSessionAdapter) -> bool:
	for index in range(720):
		adapter.poll()
		await physics_frame
		if adapter.is_ready() and not adapter.get_snapshot().is_empty():
			return true
		if not adapter.last_error().is_empty():
			return false
	return false


func _wait_for_two_adapters(first: WBNetworkSessionAdapter, second: WBNetworkSessionAdapter) -> bool:
	for index in range(360):
		first.poll()
		second.poll()
		await physics_frame
		if first.is_ready() and second.is_ready():
			return true
		if not first.last_error().is_empty() or not second.last_error().is_empty():
			return false
	return false


func _wait_for_two_pause_states(
	first: WBNetworkSessionAdapter,
	second: WBNetworkSessionAdapter,
	expected_paused: bool
) -> bool:
	for index in range(240):
		first.poll()
		second.poll()
		await physics_frame
		var first_snapshot := first.get_snapshot()
		var second_snapshot := second.get_snapshot()
		if (
			not first_snapshot.is_empty()
			and not second_snapshot.is_empty()
			and bool(first_snapshot.get("paused", false)) == expected_paused
			and bool(second_snapshot.get("paused", false)) == expected_paused
		):
			return true
		if not first.last_error().is_empty() or not second.last_error().is_empty():
			return false
	return false


func _wait_for_snapshot_after(adapter: WBNetworkSessionAdapter, tick: int) -> bool:
	for index in range(180):
		adapter.poll()
		await physics_frame
		if int(adapter.get_snapshot().get("tick", -1)) > tick:
			return true
	return false


func _wait_for_rocket_snapshot(
	adapter: WBNetworkSessionAdapter,
	after_tick: int,
	expected_rockets: int
) -> Dictionary:
	for index in range(360):
		# Re-submit while held so the adapter's bounded refresh cadence can recover
		# from an unreliable input datagram without creating another press edge.
		if not adapter.submit_input(0, WBInputRouter.INPUT_SECONDARY):
			return {}
		adapter.poll()
		await physics_frame
		var snapshot := adapter.get_snapshot()
		if (
			int(snapshot.get("tick", -1)) > after_tick
			and int((snapshot.get("shared", {}) as Dictionary).get(
				"rockets",
				-1
			)) == expected_rockets
			and not _rocket_projectile(snapshot).is_empty()
		):
			return snapshot
		if not adapter.last_error().is_empty():
			return {}
	return {}


func _rocket_projectile(snapshot: Dictionary) -> Dictionary:
	for projectile_value in snapshot.get("projectiles", []):
		if (
			projectile_value is Dictionary
			and String((projectile_value as Dictionary).get(
				"projectile_kind",
				""
			)) == "rocket_missile"
		):
			return projectile_value as Dictionary
	return {}


func _has_canonical_rocket_source_rect(projectile: Dictionary) -> bool:
	var source_rect := projectile.get("source_rect", []) as Array
	if source_rect.size() != 4:
		return false
	var source_x := int(source_rect[0])
	var source_y := int(source_rect[1])
	var heading := int(projectile.get("heading", 0))
	var animation_row := int(projectile.get("animation_row", -1))
	return (
		heading >= 1
		and heading <= 32
		and animation_row >= 0
		and animation_row <= 2
		and source_x == (heading - 1) * 24
		and source_y == animation_row * 24
		and int(source_rect[2]) == 24
		and int(source_rect[3]) == 24
	)


func _wait_for_waiting_state(adapter: WBNetworkSessionAdapter) -> bool:
	for index in range(180):
		adapter.poll()
		await physics_frame
		if bool(adapter.get_snapshot().get("waiting_for_seats", false)):
			return true
		if not adapter.last_error().is_empty():
			return false
	return false


func _wait_for_process_exit(process_id: int) -> bool:
	if process_id <= 0:
		return false
	for index in range(240):
		if not OS.is_process_running(process_id):
			return true
		await process_frame
	return not OS.is_process_running(process_id)


func _read_text(path: String) -> String:
	if path.is_empty() or not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var value := file.get_as_text()
	file.close()
	return value


func _wait_for_ack(adapter: WBNetworkSessionAdapter, request_type: int) -> bool:
	for index in range(120):
		adapter.poll()
		await physics_frame
		if _last_ack_type == request_type:
			return true
	return false


func _record_ack(request_type: int, accepted: bool, details: Dictionary) -> void:
	_last_ack_type = request_type
	_last_ack_accepted = accepted
	_last_ack_details = details.duplicate(true)


func _reset_ack() -> void:
	_last_ack_type = 0
	_last_ack_accepted = false
	_last_ack_details.clear()


func _config(mode: String, seat_count: int) -> Dictionary:
	return {
		"protocol_version": ProtocolCodec.VERSION,
		"content_version": MatchContract.CONTENT_VERSION,
		"mode": mode,
		"difficulty": "normal",
		"coop_balance": "classic",
		"collision_mode": "simple",
		"seed": 4242,
		"seat_count": seat_count,
		"seats": [],
		"start_level": 1,
		"end_level": MatchContract.MAX_END_LEVEL,
	}


func _player_x(snapshot: Dictionary, seat: int) -> int:
	for value in snapshot.get("players", []):
		if value is Dictionary and int(value.get("seat_id", -1)) == seat:
			return int(value.get("x_fp", 0))
	return 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
