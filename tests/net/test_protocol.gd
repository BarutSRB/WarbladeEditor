extends SceneTree

const Protocol := preload("res://src/net/protocol_codec.gd")
const Server := preload("res://src/server/authoritative_server.gd")
const Simulation := preload("res://src/sim/game_simulation.gd")
const MatchContract := preload("res://src/shared/match_contract.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_protocol_round_trips()
	_test_replay_export_round_trips()
	_test_malformed_packets()
	_test_server_match_version_boundary()
	_test_server_authority()
	_test_bonus_action_authority()
	_test_sequenced_stream_independence()
	_test_out_of_band_event_buffering()
	_test_couch_and_required_seat_ownership()
	_test_unauthenticated_peer_lifecycle()
	_test_two_seat_input_rate_headroom()
	_test_disconnect_clears_transient_state()
	_test_rate_budget_covers_malformed_packets()
	_test_loopback_binding()
	_test_party_chat_and_punch()
	_test_actual_enet_transport()
	if _failures.is_empty():
		print("NET TESTS PASSED")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _test_protocol_round_trips() -> void:
	_expect(Protocol.VERSION == 8, "transport framing is protocol version eight (party chat and hole punching)")
	_expect(Protocol.SNAPSHOT_VERSION == 12, "the campaign requires snapshot version twelve")
	_expect(Protocol.REPLAY_VERSION == 12, "authoritative replays require version twelve")
	_expect(Protocol.HASH_STATE_VERSION == 12, "deterministic hash state requires version twelve")
	_expect(MatchContract.CONTENT_VERSION == 12, "the talent content catalog requires match version twelve")
	_expect(MatchContract.MAX_END_LEVEL == 3999, "the authoritative campaign boundary is the retail level clamp")
	var hello := Protocol.decode_packet(Protocol.encode_hello("token", 1, "a".repeat(64), 7))
	_expect(hello.ok, "hello should decode")
	_expect(hello.type == Protocol.MessageType.HELLO, "hello type should round-trip")
	_expect(hello.sequence == 7, "hello sequence should round-trip")
	_expect(hello.payload.token == "token" and hello.payload.requested_seat == 1, "hello fields should round-trip")
	_expect(
		hello.payload.match_request is Dictionary and (hello.payload.match_request as Dictionary).is_empty(),
		"a hello without a match request decodes to an empty join request"
	)
	var request := MatchContract.network_match_request({"mode": "coop", "seed": 424_203})
	var hello_with_request := Protocol.decode_packet(
		Protocol.encode_hello("token", Protocol.SEAT_BOTH, "a".repeat(64), 9, request)
	)
	_expect(hello_with_request.ok, "a hello with a match request should decode")
	_expect(
		MatchContract.network_contract(
			hello_with_request.payload.match_request.get("contract", {})
		) == request.contract,
		"the hello match request survives its wire round-trip through the normalizer"
	)
	_expect(
		int(hello_with_request.payload.match_request.get("resume_slot", 0)) == -1,
		"the hello resume slot rides beside the contract"
	)
	var oversized_request := {"contract": {"mode": "x".repeat(Protocol.MAX_MATCH_REQUEST_BYTES)}}
	_expect(
		Protocol.encode_hello("token", 0, "a".repeat(64), 10, oversized_request).is_empty(),
		"an oversized match request refuses to encode"
	)
	var forged_hello := Protocol.encode_hello("token", 0, "a".repeat(64), 11, request)
	forged_hello.resize(forged_hello.size() - 4)
	_expect(
		not bool(Protocol.decode_packet(forged_hello).get("ok", false)),
		"a truncated hello match request is rejected"
	)
	var garbage_payload := StreamPeerBuffer.new()
	garbage_payload.big_endian = true
	garbage_payload.put_u8(5)
	garbage_payload.put_data("token".to_utf8_buffer())
	garbage_payload.put_u8(0)
	garbage_payload.put_u8(64)
	garbage_payload.put_data("a".repeat(64).to_utf8_buffer())
	garbage_payload.put_u16(9)
	garbage_payload.put_data("not-json!".to_utf8_buffer())
	var garbage_hello := Protocol.decode_packet(
		Protocol._frame(Protocol.MessageType.HELLO, 12, garbage_payload.data_array)
	)
	_expect(
		not bool(garbage_hello.get("ok", false))
		and str(garbage_hello.get("error", "")) == "malformed_hello_match_request",
		"a hello whose match request is not JSON is rejected by name"
	)
	var input := Protocol.decode_packet(Protocol.encode_input(0, 98, Simulation.ACTION_LEFT | Simulation.ACTION_FIRE, 8))
	_expect(input.ok, "input should decode")
	_expect(input.payload.client_tick == 98, "input tick should round-trip")
	_expect(input.payload.action_mask == 5, "input mask should round-trip")
	var shop := Protocol.decode_packet(Protocol.encode_shop(0, 17, 991, 9))
	_expect(shop.ok and shop.payload.item_id == 17 and shop.payload.nonce == 991, "shop should round-trip")
	var ready := Protocol.decode_packet(Protocol.encode_ready(1, true, 10))
	_expect(ready.ok and ready.payload.ready, "ready should round-trip")
	var pause := Protocol.decode_packet(Protocol.encode_pause(0, true, 11))
	_expect(pause.ok and pause.payload.paused, "pause should round-trip")
	var retire := Protocol.decode_packet(Protocol.encode_retire(1, 21))
	_expect(
		retire.ok
		and retire.type == Protocol.MessageType.RETIRE
		and retire.sequence == 21
		and retire.payload.seat_id == 1,
		"retire should round-trip its seat"
	)
	var save := Protocol.decode_packet(Protocol.encode_save(1, 4, 22))
	_expect(
		save.ok
		and save.type == Protocol.MessageType.SAVE
		and save.sequence == 22
		and save.payload.seat_id == 1
		and save.payload.slot == 4,
		"the in-shop save command should round-trip its seat and slot"
	)
	var bonus_action := Protocol.decode_packet(
		Protocol.encode_bonus_action(
			1,
			99,
			Protocol.BONUS_ACTION_SELECT_TILE,
			37,
			12
		)
	)
	_expect(
		bonus_action.ok
		and bonus_action.type == Protocol.MessageType.BONUS_ACTION
		and bonus_action.sequence == 12
		and bonus_action.payload.seat_id == 1
		and bonus_action.payload.client_tick == 99
		and bonus_action.payload.action_kind == Protocol.BONUS_ACTION_SELECT_TILE
		and bonus_action.payload.tile_index == 37,
		"semantic Memory Station selections should round-trip without pointer coordinates"
	)
	var kill_time := Protocol.decode_packet(
		Protocol.encode_bonus_action(
			0,
			100,
			Protocol.BONUS_ACTION_KILL_TIME,
			-1,
			13
		)
	)
	_expect(
		kill_time.ok and kill_time.payload.tile_index == -1,
		"kill-time actions should carry the canonical no-tile sentinel"
	)
	var snapshot := {
		"version": Protocol.SNAPSHOT_VERSION,
		"tick": 42,
		"shared": {"score": 100},
		"result": {
			"campaign_terminal": {
				"kind": "level_100",
				"full_campaign_completed": true,
				"credits_required": true,
				"ending_mode_id": 0,
				"winner_seat_id": -1,
				"level_100_score": 100,
			},
		},
		"events": [{
			"event_id": 7,
			"tick": 42,
			"type": "enemy_destroyed",
			"kind": "enemy_destroyed",
			"x_fp": 100 * Simulation.FP_ONE,
			"y_fp": 200 * Simulation.FP_ONE,
		}],
	}
	var decoded_snapshot := Protocol.decode_packet(Protocol.encode_snapshot(snapshot, 12))
	_expect(decoded_snapshot.ok and decoded_snapshot.payload.tick == 42, "snapshot should round-trip")
	_expect(
		decoded_snapshot.payload.version == Protocol.SNAPSHOT_VERSION
		and decoded_snapshot.payload.events[0].event_id == 7
		and decoded_snapshot.payload.result.campaign_terminal.credits_required,
		"authoritative events and terminal presentation data should survive snapshots"
	)
	var ack := Protocol.decode_packet(Protocol.encode_ack(Protocol.MessageType.SHOP, false, 42, {"reason": "wrong_phase"}, 13))
	_expect(ack.ok and not ack.payload.accepted, "negative acknowledgements should round-trip")


func _test_replay_export_round_trips() -> void:
	var request := Protocol.decode_packet(Protocol.encode_replay_request(1, 11))
	_expect(request.ok and request.type == Protocol.MessageType.REPLAY_REQUEST, "replay request decodes")
	_expect(int(request.payload.seat_id) == 1, "replay request seat round-trips")
	var chunk_bytes := PackedByteArray([9, 8, 7, 6])
	var data := Protocol.decode_packet(Protocol.encode_replay_data(2, 5, 999, chunk_bytes, 12))
	_expect(data.ok and data.type == Protocol.MessageType.REPLAY_DATA, "replay data decodes")
	_expect(
		int(data.payload.chunk_index) == 2
		and int(data.payload.chunk_count) == 5
		and int(data.payload.total_bytes) == 999
		and data.payload.bytes == chunk_bytes,
		"replay data fields round-trip"
	)
	_expect(
		Protocol.encode_replay_data(5, 5, 10, chunk_bytes, 13).is_empty(),
		"encoders refuse out-of-range chunk indices"
	)
	var unknown := Protocol.encode_replay_request(0, 14)
	unknown[6] = 18
	_expect(not Protocol.decode_packet(unknown).ok, "type eighteen stays unknown past the party pair")


func _test_malformed_packets() -> void:
	_expect(not Protocol.decode_packet(PackedByteArray([1, 2, 3])).ok, "short packets should be rejected")
	var valid := Protocol.encode_input(0, 1, 0, 1)
	var truncated := valid.slice(0, valid.size() - 1)
	_expect(not Protocol.decode_packet(truncated).ok, "payload size mismatches should be rejected")
	var bad_magic := valid.duplicate()
	bad_magic[0] = 0
	_expect(not Protocol.decode_packet(bad_magic).ok, "bad packet magic should be rejected")
	var invalid_mask_packet := Protocol.encode_input(0, 1, 65535, 2)
	_expect(Protocol.decode_packet(invalid_mask_packet).ok, "structurally valid masks should decode before authority validation")
	_expect(
		Protocol.encode_bonus_action(0, 1, 99, -1, 3).is_empty(),
		"encoders should refuse unknown bonus action kinds"
	)
	_expect(
		Protocol.encode_bonus_action(
			0,
			1,
			Protocol.BONUS_ACTION_SELECT_TILE,
			64,
			4
		).is_empty(),
		"encoders should refuse out-of-grid tile indices"
	)
	var malformed_tile := Protocol.encode_bonus_action(
		0,
		1,
		Protocol.BONUS_ACTION_SELECT_TILE,
		63,
		5
	)
	malformed_tile[malformed_tile.size() - 2] = 64
	malformed_tile[malformed_tile.size() - 1] = 0
	_expect(
		not Protocol.decode_packet(malformed_tile).ok,
		"decoders should reject forged out-of-grid tile indices"
	)


func _test_server_match_version_boundary() -> void:
	var server := Server.new()
	var current_config := {
		"protocol_version": Protocol.VERSION,
		"content_version": MatchContract.CONTENT_VERSION,
		"start_level": 1,
		"end_level": MatchContract.MAX_END_LEVEL,
		"mode": "solo",
		"difficulty": "normal",
		"record_replay": false,
	}
	var missing_versions := current_config.duplicate(true)
	missing_versions.erase("protocol_version")
	missing_versions.erase("content_version")
	_expect(
		not server.configure_only(missing_versions),
		"authoritative matches should require explicit protocol and content versions"
	)
	var stale_protocol := current_config.duplicate(true)
	stale_protocol.protocol_version = Protocol.VERSION - 1
	_expect(
		not server.configure_only(stale_protocol),
		"authoritative matches should reject stale protocol versions"
	)
	var stale_content := current_config.duplicate(true)
	stale_content.content_version = MatchContract.CONTENT_VERSION - 1
	_expect(
		not server.configure_only(stale_content),
		"authoritative matches should reject stale content versions"
	)
	var beyond_boundary := current_config.duplicate(true)
	beyond_boundary.end_level = 4000
	_expect(
		not server.configure_only(beyond_boundary),
		"authoritative matches should reject end levels beyond the retail clamp 3999"
	)
	var endless_boundary := current_config.duplicate(true)
	endless_boundary.end_level = 101
	_expect(
		server.configure_only(endless_boundary),
		"authoritative matches should accept endless play beyond level one hundred"
	)
	_expect(
		server.configure_only(current_config),
		"authoritative matches should accept protocol three with content eight through level one hundred"
	)
	server.free()
	var compatibility_server := Server.new()
	var compatibility_config := current_config.duplicate(true)
	compatibility_config.start_level = 63
	compatibility_config.end_level = 63
	_expect(
		compatibility_server.configure_only(compatibility_config),
		"authoritative matches should accept an explicit level-sixty-three boundary"
	)
	compatibility_server.free()


func _test_server_authority() -> void:
	var server := Server.new()
	_expect(server.configure_only({
		"protocol_version": Protocol.VERSION,
		"content_version": MatchContract.CONTENT_VERSION,
		"start_level": 1,
		"end_level": 49,
		"mode": "solo",
		"difficulty": "normal",
		"seed": 11,
		"record_replay": false,
	}), "test server should configure")
	server.session_token = "local-test-token"
	var content_hash := server.simulation.get_content_hash()
	var welcome_packet := server.process_packet_for_test(
		101,
		Protocol.encode_hello("local-test-token", 0, content_hash, 1)
	)
	var welcome := Protocol.decode_packet(welcome_packet)
	_expect(welcome.ok and welcome.type == Protocol.MessageType.WELCOME, "valid hello should receive welcome")
	var valid_input_response := server.process_packet_for_test(
		101,
		Protocol.encode_input(0, 0, Simulation.ACTION_FIRE, 2)
	)
	_expect(valid_input_response.is_empty(), "valid inputs should be accepted without trusting client state claims")
	var replay_reject := Protocol.decode_packet(server.process_packet_for_test(
		101,
		Protocol.encode_input(0, 0, 0, 2)
	))
	_expect(replay_reject.ok and replay_reject.type == Protocol.MessageType.REJECT, "replayed sequences should be rejected")
	var wrong_seat := Protocol.decode_packet(server.process_packet_for_test(
		101,
		Protocol.encode_input(1, 0, 0, 3)
	))
	_expect(wrong_seat.ok and wrong_seat.payload.reason == "wrong_seat", "peers should not control another seat")
	var contradictory_response := server.process_packet_for_test(
		101,
		Protocol.encode_input(
			0,
			0,
			Simulation.ACTION_LEFT
			| Simulation.ACTION_RIGHT
			| Simulation.ACTION_UP
			| Simulation.ACTION_DOWN,
			4
		)
	)
	_expect(
		contradictory_response.is_empty()
		and int(server.simulation._input_masks[0]) == 0,
		"the authority canonicalizes forged contradictory directions to neutral"
	)
	var shop_ack := Protocol.decode_packet(server.process_packet_for_test(
		101,
		Protocol.encode_shop(0, 1, 77, 4)
	))
	_expect(
		shop_ack.ok and shop_ack.type == Protocol.MessageType.ACK and not shop_ack.payload.accepted,
		"server should reject shop purchases outside the shop phase"
	)
	var pause_ack := Protocol.decode_packet(server.process_packet_for_test(
		101,
		Protocol.encode_pause(0, true, 5)
	))
	_expect(pause_ack.ok and pause_ack.payload.accepted and server.paused, "seat zero should control authoritative pause")
	server.running = true
	server._physics_process(1.0 / 60.0)
	_expect(server.simulation.get_snapshot().tick == 0, "authoritative pause should freeze simulation ticks")
	var resume_ack := Protocol.decode_packet(server.process_packet_for_test(
		101,
		Protocol.encode_pause(0, false, 6)
	))
	server._physics_process(1.0 / 60.0)
	_expect(resume_ack.ok and not server.paused, "seat zero should resume authoritative play")
	_expect(server.simulation.get_snapshot().tick == 1, "resumed authoritative simulation should advance")
	server.running = false
	var invalid_token := Protocol.decode_packet(server.process_packet_for_test(
		202,
		Protocol.encode_hello("wrong-token", 1, content_hash, 1)
	))
	_expect(invalid_token.ok and invalid_token.payload.reason == "invalid_session_token", "invalid tokens should be rejected")
	var counters := server.get_rejection_counters()
	_expect(counters.total >= 3, "packet rejection counters should include authority failures")
	_expect(counters.by_reason.has("stale_sequence"), "rejection counters should classify replay attempts")
	server._on_peer_disconnected(101)
	_expect(
		server.simulation._input_masks[0] == 0,
		"disconnecting an owning peer should clear its latched authoritative input"
	)
	server.free()


func _test_bonus_action_authority() -> void:
	var server := Server.new()
	_expect(server.configure_only({
		"protocol_version": Protocol.VERSION,
		"content_version": MatchContract.CONTENT_VERSION,
		"start_level": 1,
		"end_level": 49,
		"mode": "solo",
		"difficulty": "normal",
		"seed": 19,
		"record_replay": true,
	}), "bonus-action authority server should configure")
	server.session_token = "bonus-action-token"
	var content_hash := server.simulation.get_content_hash()
	server.process_packet_for_test(
		801,
		Protocol.encode_hello("bonus-action-token", 0, content_hash, 1)
	)
	server.simulation._enter_bonus_mode_boundary(
		"memory_station",
		server.simulation._shared,
		0
	)
	_expect(
		server.simulation.get_snapshot().phase == Simulation.PHASE_BONUS_MODE,
		"bonus-action authority should exercise an entered Memory controller"
	)
	var accepted := Protocol.decode_packet(server.process_packet_for_test(
		801,
		Protocol.encode_bonus_action(
			0,
			0,
			Protocol.BONUS_ACTION_SELECT_TILE,
			0,
			2
		)
	))
	_expect(
		accepted.ok
		and accepted.type == Protocol.MessageType.ACK
		and accepted.payload.request_type == Protocol.MessageType.BONUS_ACTION
		and accepted.payload.accepted,
		"the owning seat should queue one normalized selection for the authoritative tick"
	)
	var duplicate_tick := Protocol.decode_packet(server.process_packet_for_test(
		801,
		Protocol.encode_bonus_action(
			0,
			0,
			Protocol.BONUS_ACTION_SELECT_TILE,
			1,
			3
		)
	))
	_expect(
		duplicate_tick.ok
		and not duplicate_tick.payload.accepted
		and duplicate_tick.payload.details.reason == "duplicate_action_tick",
		"the server should reject a second semantic action targeting the same tick"
	)
	var future := Protocol.decode_packet(server.process_packet_for_test(
		801,
		Protocol.encode_bonus_action(
			0,
			Server.MAX_FUTURE_INPUT_TICKS + 1,
			Protocol.BONUS_ACTION_SELECT_TILE,
			8,
			4
		)
	))
	_expect(
		future.ok and future.type == Protocol.MessageType.REJECT
		and future.payload.reason == "input_too_far_ahead",
		"future bonus actions should be rejected before entering the simulation queue"
	)
	var wrong_seat := Protocol.decode_packet(server.process_packet_for_test(
		801,
		Protocol.encode_bonus_action(
			1,
			1,
			Protocol.BONUS_ACTION_SELECT_TILE,
			9,
			5
		)
	))
	_expect(
		wrong_seat.ok and wrong_seat.type == Protocol.MessageType.REJECT
		and wrong_seat.payload.reason == "wrong_seat",
		"a peer should not submit bonus actions for an unowned seat"
	)
	var replayed_sequence := Protocol.decode_packet(server.process_packet_for_test(
		801,
		Protocol.encode_bonus_action(
			0,
			1,
			Protocol.BONUS_ACTION_SELECT_TILE,
			10,
			5
		)
	))
	_expect(
		replayed_sequence.ok and replayed_sequence.type == Protocol.MessageType.REJECT
		and replayed_sequence.payload.reason == "stale_sequence",
		"bonus commands should share the reliable control stream's replay-resistant sequence space"
	)
	server.free()


func _test_sequenced_stream_independence() -> void:
	var server := Server.new()
	_expect(server.configure_only({
		"protocol_version": Protocol.VERSION,
		"content_version": MatchContract.CONTENT_VERSION,
		"start_level": 1,
		"end_level": 49,
		"mode": "solo",
		"difficulty": "normal",
		"seed": 23,
		"record_replay": true,
	}), "independent-sequence server should configure")
	server.session_token = "independent-sequence-token"
	var content_hash := server.simulation.get_content_hash()
	server.process_packet_for_test(
		823,
		Protocol.encode_hello("independent-sequence-token", 0, content_hash, 1)
	)
	server.simulation._enter_bonus_mode_boundary(
		"memory_station",
		server.simulation._shared,
		0
	)
	# Advance beyond the most recently published three-tick snapshot boundary.
	server.simulation.step()
	server.simulation.step()
	var overtaking_input := server.process_packet_for_test(
		823,
		Protocol.encode_input(0, 0, Simulation.ACTION_LEFT, 500)
	)
	_expect(
		overtaking_input.is_empty(),
		"a high unreliable-input sequence should be accepted in its own ordered stream"
	)
	var delayed_reliable := Protocol.decode_packet(server.process_packet_for_test(
		823,
		Protocol.encode_bonus_action(
			0,
			0,
			Protocol.BONUS_ACTION_SELECT_TILE,
			0,
			2
		)
	))
	_expect(
		delayed_reliable.ok
		and delayed_reliable.type == Protocol.MessageType.ACK
		and delayed_reliable.payload.accepted,
		"a delayed reliable bonus command must not be discarded by an overtaking input packet"
	)
	var connection: Dictionary = server.get_connection_state().peers[823]
	_expect(
		int(connection.last_input_sequence) == 500
		and int(connection.last_control_sequence) == 2,
		"input and reliable control traffic should retain independent replay high-water marks"
	)
	server.simulation.step()
	var replay: Dictionary = server.simulation.get_replay()
	var normalized_actions: Array = replay.frames[-1].bonus_actions
	_expect(
		normalized_actions.size() == 1
		and int(normalized_actions[0].target_tick) == int(replay.frames[-1].tick),
		"a stale snapshot tick should normalize to the authoritative execution tick"
	)
	server.paused = true
	var paused_action := Protocol.decode_packet(server.process_packet_for_test(
		823,
		Protocol.encode_bonus_action(
			0,
			int(server.simulation.get_snapshot().tick),
			Protocol.BONUS_ACTION_SELECT_TILE,
			8,
			3
		)
	))
	_expect(
		paused_action.ok
		and paused_action.type == Protocol.MessageType.ACK
		and not paused_action.payload.accepted
		and str(paused_action.payload.details.reason) == "paused",
		"paused authority should reject bonus actions without queuing future input"
	)
	server.free()


func _test_out_of_band_event_buffering() -> void:
	var server := Server.new()
	_expect(server.configure_only({
		"protocol_version": Protocol.VERSION,
		"content_version": MatchContract.CONTENT_VERSION,
		"start_level": 1,
		"end_level": 49,
		"mode": "solo",
		"difficulty": "normal",
		"record_replay": false,
		"starting_money": 100,
	}), "out-of-band presentation server should configure")
	server.session_token = "event-token"
	var content_hash := server.simulation.get_content_hash()
	server.process_packet_for_test(
		211,
		Protocol.encode_hello("event-token", 0, content_hash, 1)
	)
	server.simulation._phase = Simulation.PHASE_SHOP
	var purchase := Protocol.decode_packet(server.process_packet_for_test(
		211,
		Protocol.encode_shop(0, 1, 501, 2)
	))
	_expect(purchase.ok and purchase.payload.accepted, "authoritative shop purchase should succeed")
	_expect(server._snapshot_events.size() == 1, "command-generated presentation events should be buffered")
	server._buffer_snapshot_events(server.simulation.get_snapshot().events)
	_expect(server._snapshot_events.size() == 1, "buffering the same authoritative event should be idempotent")
	var ready := Protocol.decode_packet(server.process_packet_for_test(
		211,
		Protocol.encode_ready(0, true, 3)
	))
	_expect(ready.ok and ready.payload.accepted, "shop ready should advance the one-seat match")
	var published := server._broadcast_snapshot()
	var event_types: Array = published.events.map(
		func(event: Dictionary) -> String: return String(event.type)
	)
	_expect(
		event_types == ["shop_purchase", "get_ready_started"],
		"the next reliable snapshot should retain purchase and level-transition events"
	)
	server._buffer_snapshot_events(server.simulation.get_snapshot().events)
	_expect(server._snapshot_events.is_empty(), "published event IDs should not be buffered again")
	server.free()


func _test_couch_and_required_seat_ownership() -> void:
	var couch_server := Server.new()
	_expect(couch_server.configure_only({
		"protocol_version": Protocol.VERSION,
		"content_version": MatchContract.CONTENT_VERSION,
		"start_level": 1,
		"end_level": 49,
		"mode": "coop",
		"difficulty": "normal",
		"record_replay": false,
	}), "couch authority server should configure")
	couch_server.session_token = "couch-token"
	var couch_hash := couch_server.simulation.get_content_hash()
	var couch_welcome := Protocol.decode_packet(couch_server.process_packet_for_test(
		301,
		Protocol.encode_hello("couch-token", Protocol.SEAT_BOTH, couch_hash, 1)
	))
	_expect(
		couch_welcome.ok and couch_welcome.payload.seat_id == Protocol.SEAT_BOTH,
		"a couch peer should atomically own both seats"
	)
	_expect(not couch_server.get_connection_state().waiting_for_seats, "couch ownership should satisfy both required seats")
	var seat_one_input := couch_server.process_packet_for_test(
		301,
		Protocol.encode_input(1, 0, Simulation.ACTION_RIGHT, 2)
	)
	_expect(seat_one_input.is_empty(), "a couch peer should control its second owned seat")
	var claimed_seat_reject := Protocol.decode_packet(couch_server.process_packet_for_test(
		302,
		Protocol.encode_hello("couch-token", 0, couch_hash, 1)
	))
	_expect(claimed_seat_reject.payload.reason == "seat_already_owned", "couch seats cannot be claimed by another peer")
	couch_server.free()

	var two_peer_server := Server.new()
	_expect(two_peer_server.configure_only({
		"protocol_version": Protocol.VERSION,
		"content_version": MatchContract.CONTENT_VERSION,
		"start_level": 1,
		"end_level": 49,
		"mode": "coop",
		"difficulty": "normal",
		"record_replay": false,
	}), "two-peer authority server should configure")
	two_peer_server.session_token = "two-peer-token"
	var two_peer_hash := two_peer_server.simulation.get_content_hash()
	two_peer_server.process_packet_for_test(
		401,
		Protocol.encode_hello("two-peer-token", 0, two_peer_hash, 1)
	)
	two_peer_server.running = true
	two_peer_server._physics_process(1.0 / 60.0)
	_expect(two_peer_server.simulation.get_snapshot().tick == 0, "server should wait for every required seat")
	two_peer_server.process_packet_for_test(
		402,
		Protocol.encode_hello("two-peer-token", 1, two_peer_hash, 1)
	)
	two_peer_server._physics_process(1.0 / 60.0)
	_expect(two_peer_server.simulation.get_snapshot().tick == 1, "server should start after every required seat joins")
	var unauthorized_pause := Protocol.decode_packet(two_peer_server.process_packet_for_test(
		402,
		Protocol.encode_pause(1, true, 2)
	))
	_expect(
		unauthorized_pause.payload.reason == "pause_requires_seat_zero" and not two_peer_server.paused,
		"seat one should not control authoritative pause"
	)
	two_peer_server.running = false
	two_peer_server.free()


func _test_unauthenticated_peer_lifecycle() -> void:
	var server := Server.new()
	_expect(server.configure_only({
		"protocol_version": Protocol.VERSION,
		"content_version": MatchContract.CONTENT_VERSION,
		"start_level": 1,
		"end_level": 49,
		"mode": "solo",
		"difficulty": "normal",
		"record_replay": false,
	}), "handshake-lifecycle server should configure")
	server.session_token = "handshake-token"
	var content_hash := server.simulation.get_content_hash()
	server._ensure_peer(701)
	var deadline_msec := int(server._peers[701].handshake_deadline_msec)
	_expect(
		server._expire_unauthenticated_peers(deadline_msec - 1).is_empty(),
		"unauthenticated peers should retain their slot before the monotonic handshake deadline"
	)
	var expired_peer_ids := server._expire_unauthenticated_peers(deadline_msec)
	_expect(
		expired_peer_ids == [701] and not server.get_connection_state().peers.has(701),
		"unauthenticated peers should be dropped exactly at the handshake deadline"
	)
	var recovered_welcome := Protocol.decode_packet(server.process_packet_for_test(
		701,
		Protocol.encode_hello("handshake-token", 0, content_hash, 1)
	))
	_expect(
		recovered_welcome.ok and recovered_welcome.type == Protocol.MessageType.WELCOME,
		"an expired connection slot should recover with fresh handshake state"
	)
	server._on_peer_disconnected(701)
	for rejection_index in range(Server.MAX_UNAUTHENTICATED_REJECTIONS):
		var rejection_packet := server.process_packet_for_test(
			702,
			Protocol.encode_hello(
				"wrong-token",
				0,
				content_hash,
				rejection_index + 1
			)
		)
		if rejection_index + 1 < Server.MAX_UNAUTHENTICATED_REJECTIONS:
			var rejection := Protocol.decode_packet(rejection_packet)
			_expect(
				rejection.ok and rejection.payload.reason == "invalid_session_token",
				"pre-authentication failures below the bound should receive a rejection"
			)
		else:
			_expect(
				rejection_packet.is_empty(),
				"the rejection that exhausts the unauthenticated bound should not amplify traffic"
			)
	_expect(
		not server.get_connection_state().peers.has(702),
		"bounded unauthenticated authentication failures should drop the peer"
	)
	var retry_welcome := Protocol.decode_packet(server.process_packet_for_test(
		702,
		Protocol.encode_hello("handshake-token", 0, content_hash, 1)
	))
	_expect(
		retry_welcome.ok and retry_welcome.type == Protocol.MessageType.WELCOME,
		"dropping an abusive unauthenticated peer should release all peer state"
	)
	server._on_peer_disconnected(702)
	server._ensure_peer(703)
	server._peers[703].messages_in_window = Server.MAX_MESSAGES_PER_RATE_WINDOW
	for rejection_index in range(Server.MAX_UNAUTHENTICATED_REJECTIONS):
		var rate_response := server.process_packet_for_test(
			703,
			PackedByteArray([1, 2, 3])
		)
		_expect(
			rate_response.is_empty(),
			"unauthenticated rate-limit failures should be dropped without amplification"
		)
	_expect(
		not server.get_connection_state().peers.has(703),
		"bounded unauthenticated rate-limit failures should drop the peer"
	)
	var rate_retry_welcome := Protocol.decode_packet(server.process_packet_for_test(
		703,
		Protocol.encode_hello("handshake-token", 0, content_hash, 1)
	))
	_expect(
		rate_retry_welcome.ok and rate_retry_welcome.type == Protocol.MessageType.WELCOME,
		"rate-limited unauthenticated peer state should recover after the drop"
	)
	server.free()


func _test_two_seat_input_rate_headroom() -> void:
	var server := Server.new()
	_expect(server.configure_only({
		"protocol_version": Protocol.VERSION,
		"content_version": MatchContract.CONTENT_VERSION,
		"start_level": 1,
		"end_level": 49,
		"mode": "coop",
		"difficulty": "normal",
		"record_replay": false,
	}), "two-seat rate-headroom server should configure")
	server.session_token = "rate-headroom-token"
	var content_hash := server.simulation.get_content_hash()
	var sequence := 1
	var welcome := Protocol.decode_packet(server.process_packet_for_test(
		751,
		Protocol.encode_hello(
			"rate-headroom-token",
			Protocol.SEAT_BOTH,
			content_hash,
			sequence
		)
	))
	_expect(welcome.ok and welcome.type == Protocol.MessageType.WELCOME, "rate-headroom peer should authenticate")
	sequence += 1
	for control_index in range(8):
		var ping := Protocol.decode_packet(server.process_packet_for_test(
			751,
			Protocol.encode_ping(control_index, sequence)
		))
		_expect(
			ping.ok and ping.type == Protocol.MessageType.ACK and ping.payload.accepted,
			"control traffic inside the headroom should remain accepted"
		)
		sequence += 1
	var all_inputs_accepted := true
	for input_tick in range(59):
		var seat_zero_mask := (
			Simulation.ACTION_LEFT
			if input_tick % 2 == 0
			else Simulation.ACTION_RIGHT
		)
		var seat_one_mask := (
			Simulation.ACTION_RIGHT
			if input_tick % 2 == 0
			else Simulation.ACTION_LEFT
		)
		all_inputs_accepted = (
			all_inputs_accepted
			and server.process_packet_for_test(
				751,
				Protocol.encode_input(0, 0, seat_zero_mask, sequence)
			).is_empty()
		)
		sequence += 1
		all_inputs_accepted = (
			all_inputs_accepted
			and server.process_packet_for_test(
				751,
				Protocol.encode_input(1, 0, seat_one_mask, sequence)
			).is_empty()
		)
		sequence += 1
	all_inputs_accepted = (
		all_inputs_accepted
		and server.process_packet_for_test(
			751,
			Protocol.encode_input(0, 0, 0, sequence)
		).is_empty()
	)
	sequence += 1
	all_inputs_accepted = (
		all_inputs_accepted
		and server.process_packet_for_test(
			751,
			Protocol.encode_input(1, 0, 0, sequence)
		).is_empty()
	)
	var state: Dictionary = server.get_connection_state().peers[751]
	var counters := server.get_rejection_counters()
	_expect(
		all_inputs_accepted
		and int(state.last_sequence) == sequence
		and int(counters.by_reason.get("rate_limit", 0)) == 0,
		"60 Hz changing inputs for both seats plus control traffic should fit the coherent rate budget"
	)
	_expect(
		server.simulation._input_masks[0] == 0
		and server.simulation._input_masks[1] == 0,
		"the final two-seat input releases should be accepted at the rate boundary"
	)
	server.free()


func _test_disconnect_clears_transient_state() -> void:
	var server := Server.new()
	_expect(server.configure_only({
		"protocol_version": Protocol.VERSION,
		"content_version": MatchContract.CONTENT_VERSION,
		"start_level": 1,
		"end_level": 49,
		"mode": "coop",
		"difficulty": "normal",
		"record_replay": false,
	}), "disconnect-recovery server should configure")
	server.session_token = "disconnect-token"
	var content_hash := server.simulation.get_content_hash()
	server.process_packet_for_test(
		801,
		Protocol.encode_hello("disconnect-token", 0, content_hash, 1)
	)
	server.process_packet_for_test(
		802,
		Protocol.encode_hello("disconnect-token", 1, content_hash, 1)
	)
	server.simulation._phase = Simulation.PHASE_SHOP
	server.process_packet_for_test(
		802,
		Protocol.encode_input(1, 0, Simulation.ACTION_FIRE, 2)
	)
	var ready := Protocol.decode_packet(server.process_packet_for_test(
		802,
		Protocol.encode_ready(1, true, 3)
	))
	_expect(
		ready.ok
		and ready.payload.accepted
		and server.simulation.get_snapshot().shop.ready[1],
		"the disconnect test should establish transient seat input and readiness"
	)
	var disconnect_snapshot := server._on_peer_disconnected(802)
	var connection_state := server.get_connection_state()
	_expect(
		server.simulation._input_masks[1] == 0
		and not server.simulation.get_snapshot().shop.ready[1],
		"disconnect should clear both latched input and shop readiness through the simulation API"
	)
	_expect(
		bool(disconnect_snapshot.waiting_for_seats)
		and int(disconnect_snapshot.required_seats) == 2
		and bool(connection_state.waiting_for_seats)
		and int(connection_state.required_seats) == 2,
		"disconnect should immediately broadcast and expose authoritative waiting-seat metadata"
	)
	_expect(
		connection_state.peers.has(801) and not connection_state.peers.has(802),
		"disconnect should preserve the remaining authenticated peer while releasing the departed slot"
	)
	server.free()


func _test_rate_budget_covers_malformed_packets() -> void:
	var server := Server.new()
	_expect(server.configure_only({
		"protocol_version": Protocol.VERSION,
		"content_version": MatchContract.CONTENT_VERSION,
		"start_level": 1,
		"end_level": 49,
		"mode": "solo",
		"difficulty": "normal",
		"record_replay": false,
	}), "rate-budget server should configure")
	var last_response := PackedByteArray()
	for packet_index in range(Server.MAX_MESSAGES_PER_RATE_WINDOW + 1):
		last_response = server.process_packet_for_test(
			901,
			PackedByteArray([1, 2, 3])
		)
	_expect(
		last_response.is_empty(),
		"packets beyond the rate budget should be dropped without reliable amplification"
	)
	var counters := server.get_rejection_counters()
	_expect(
		int(counters.by_reason.get("rate_limit", 0)) == 1
		and int(counters.by_reason.get("packet_too_short", 0))
		== Server.MAX_MESSAGES_PER_RATE_WINDOW,
		"malformed packets should consume the same bounded rate budget as decoded packets"
	)
	server.free()


func _test_loopback_binding() -> void:
	var server := Server.new()
	root.add_child(server)
	var result := server.start_local({
		"protocol_version": Protocol.VERSION,
		"content_version": MatchContract.CONTENT_VERSION,
		"start_level": 1,
		"end_level": 49,
		"mode": "solo",
		"difficulty": "normal",
		"record_replay": false,
	}, "", 0, "binding-test-token")
	_expect(result.ok, "authoritative server should bind an ephemeral loopback port")
	_expect(result.port >= Server.MIN_DYNAMIC_PORT, "dynamic server port should be in the bounded range")
	_expect(result.token == "binding-test-token", "explicit sidecar tokens should be retained")
	server.stop()
	server.free()


func _test_party_chat_and_punch() -> void:
	var chat := Protocol.decode_packet(Protocol.encode_chat(1, "BRAVO", "hello there", 21))
	_expect(chat.ok and chat.type == Protocol.MessageType.CHAT, "chat decodes")
	_expect(
		int(chat.payload.seat_id) == 1
		and str(chat.payload.nickname) == "BRAVO"
		and str(chat.payload.text) == "hello there",
		"chat fields round-trip"
	)
	_expect(Protocol.encode_chat(0, "A", "", 1).is_empty(), "empty chat lines are refused")
	_expect(Protocol.encode_chat(0, "A", "x".repeat(201), 1).is_empty(), "oversized chat lines are refused")
	_expect(Protocol.encode_chat(0, "seventeen_chars__", "hi", 1).is_empty(), "oversized nicknames are refused")
	var truncated := Protocol.encode_chat(0, "A", "hi", 1)
	truncated.resize(truncated.size() - 1)
	truncated[12] = truncated[12] - 1
	_expect(not Protocol.decode_packet(truncated).ok, "a truncated chat payload is rejected")
	var punch := Protocol.decode_packet(Protocol.encode_punch(0, "203.0.113.9", 42000, 22))
	_expect(punch.ok and punch.type == Protocol.MessageType.PUNCH, "punch decodes")
	_expect(
		str(punch.payload.address) == "203.0.113.9" and int(punch.payload.port) == 42000,
		"punch fields round-trip"
	)
	_expect(Protocol.encode_punch(0, "not-an-ip", 42000, 1).is_empty(), "punch refuses hostnames")
	_expect(Protocol.encode_punch(0, "203.0.113.9", 0, 1).is_empty(), "punch refuses port zero")

	var server := Server.new()
	var config := {
		"protocol_version": Protocol.VERSION,
		"content_version": MatchContract.CONTENT_VERSION,
		"start_level": 1,
		"end_level": 3,
		"mode": "coop",
		"difficulty": "normal",
		"record_replay": false,
	}
	_expect(server.configure_only(config), "chat test server configures")
	server.session_token = "party-token"
	var host_welcome := Protocol.decode_packet(server.process_packet_for_test(1, Protocol.encode_hello(
		"party-token", 0, server.simulation.get_content_hash(), 1,
		MatchContract.network_match_request(config)
	)))
	_expect(host_welcome.ok and host_welcome.type == Protocol.MessageType.WELCOME, "host seat authenticates")
	var joiner_welcome := Protocol.decode_packet(server.process_packet_for_test(2, Protocol.encode_hello(
		"party-token", 1, server.simulation.get_content_hash(), 1
	)))
	_expect(joiner_welcome.ok and joiner_welcome.type == Protocol.MessageType.WELCOME, "joiner seat authenticates")
	var echoed := Protocol.decode_packet(server.process_packet_for_test(2, Protocol.encode_chat(1, "BRAVO", "gg", 2)))
	_expect(
		echoed.ok and echoed.type == Protocol.MessageType.CHAT and str(echoed.payload.text) == "gg",
		"a seat owner's chat comes back as a CHAT packet"
	)
	var wrong_seat := Protocol.decode_packet(server.process_packet_for_test(2, Protocol.encode_chat(0, "BRAVO", "spoof", 3)))
	_expect(
		wrong_seat.ok and wrong_seat.type == Protocol.MessageType.REJECT and str(wrong_seat.payload.reason) == "wrong_seat",
		"chat for an unowned seat is rejected"
	)
	var throttled := false
	for index in range(Server.MAX_CHAT_PER_WINDOW + 1):
		var reply := Protocol.decode_packet(server.process_packet_for_test(1, Protocol.encode_chat(0, "ALPHA", "spam %d" % index, 2 + index)))
		if reply.ok and reply.type == Protocol.MessageType.ACK and not bool(reply.payload.accepted):
			throttled = str(reply.payload.details.reason) == "chat_rate"
	_expect(throttled, "chat beyond the per-window budget answers a chat_rate ack")
	var joiner_punch := Protocol.decode_packet(server.process_packet_for_test(2, Protocol.encode_punch(1, "203.0.113.9", 42000, 20)))
	_expect(
		joiner_punch.ok and joiner_punch.type == Protocol.MessageType.REJECT
		and str(joiner_punch.payload.reason) == "punch_requires_seat_zero",
		"only the seat-zero owner may punch"
	)
	var loopback_punch := Protocol.decode_packet(server.process_packet_for_test(1, Protocol.encode_punch(0, "203.0.113.9", 42000, 40)))
	_expect(
		loopback_punch.ok and loopback_punch.type == Protocol.MessageType.ACK
		and not bool(loopback_punch.payload.accepted)
		and str(loopback_punch.payload.details.reason) == "not_public_bind",
		"a loopback server refuses to punch"
	)
	server._lobby = true
	server._bind_host = "*"
	var public_punch := Protocol.decode_packet(server.process_packet_for_test(1, Protocol.encode_punch(0, "203.0.113.9", 42000, 41)))
	_expect(
		public_punch.ok and public_punch.type == Protocol.MessageType.ACK and bool(public_punch.payload.accepted),
		"a publicly bound server queues the punch"
	)
	_expect(int(server.get_connection_state().punch_targets) == 1, "the punch target is queued")
	server._process_punch_queue(Time.get_ticks_msec() + Server.PUNCH_DURATION_MSEC + 1)
	_expect(int(server.get_connection_state().punch_targets) == 0, "an expired punch target drains without a socket")
	server.free()


func _test_actual_enet_transport() -> void:
	var server := Server.new()
	root.add_child(server)
	var result := server.start_local({
		"protocol_version": Protocol.VERSION,
		"content_version": MatchContract.CONTENT_VERSION,
		"start_level": 1,
		"end_level": 49,
		"mode": "solo",
		"difficulty": "normal",
		"record_replay": false,
	}, "", 0, "enet-test-token")
	if not bool(result.ok):
		_expect(false, "ENet integration server should bind")
		server.free()
		return
	var client := ENetMultiplayerPeer.new()
	var create_error := client.create_client("127.0.0.1", int(result.port))
	_expect(create_error == OK, "raw ENet client should start")
	for attempt in range(500):
		server.poll_network()
		client.poll()
		if client.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			break
		OS.delay_msec(1)
	_expect(client.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED, "raw ENet client should connect to loopback")
	client.set_target_peer(1)
	client.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
	client.put_packet(Protocol.encode_hello(
		"enet-test-token",
		0,
		String(result.content_hash),
		1
	))
	var received := PackedByteArray()
	for attempt in range(500):
		server.poll_network()
		client.poll()
		if client.get_available_packet_count() > 0:
			received = client.get_packet()
			break
		OS.delay_msec(1)
	var decoded := Protocol.decode_packet(received)
	_expect(
		bool(decoded.get("ok", false)) and int(decoded.get("type", 0)) == Protocol.MessageType.WELCOME,
		"raw ENet poll/get_packet should complete the authoritative handshake"
	)
	client.put_packet(Protocol.encode_input(0, 0, Simulation.ACTION_FIRE, 2))
	for attempt in range(500):
		server.poll_network()
		client.poll()
		var peers: Dictionary = server.get_connection_state().peers
		var input_received := false
		for state_value in peers.values():
			if state_value is Dictionary and int(state_value.get("last_sequence", -1)) >= 2:
				input_received = true
		if input_received:
			break
		OS.delay_msec(1)
	for tick in range(Server.SNAPSHOT_INTERVAL_TICKS):
		server._physics_process(1.0 / 60.0)
	# A successful HELLO immediately publishes the pre-input authoritative
	# state, so the first snapshot on the wire is the event-empty welcome
	# image; the cadence snapshot that buffered the fire arrives behind it.
	var snapshot_packet := PackedByteArray()
	for attempt in range(500):
		server.poll_network()
		client.poll()
		while client.get_available_packet_count() > 0:
			var candidate := client.get_packet()
			var candidate_decoded := Protocol.decode_packet(candidate)
			if (
				bool(candidate_decoded.get("ok", false))
				and int(candidate_decoded.get("type", 0)) == Protocol.MessageType.SNAPSHOT
				and not (candidate_decoded.payload.get("events", []) as Array).is_empty()
			):
				snapshot_packet = candidate
				break
		if not snapshot_packet.is_empty():
			break
		OS.delay_msec(1)
	var snapshot_decoded := Protocol.decode_packet(snapshot_packet)
	var buffered_weapon_event := false
	if bool(snapshot_decoded.get("ok", false)):
		for event_value in snapshot_decoded.payload.get("events", []):
			if event_value is Dictionary and str(event_value.get("type", "")) == "weapon_fired":
				buffered_weapon_event = true
	_expect(buffered_weapon_event, "20 Hz snapshots should retain 60 Hz authoritative gameplay events")
	client.put_packet(Protocol.encode_chat(0, "ALPHA", "over the wire", 3))
	var chat_packet := PackedByteArray()
	for attempt in range(500):
		server.poll_network()
		client.poll()
		while client.get_available_packet_count() > 0:
			var candidate := client.get_packet()
			var candidate_decoded := Protocol.decode_packet(candidate)
			if bool(candidate_decoded.get("ok", false)) and int(candidate_decoded.get("type", 0)) == Protocol.MessageType.CHAT:
				chat_packet = candidate
				break
		if not chat_packet.is_empty():
			break
		OS.delay_msec(1)
	var chat_decoded := Protocol.decode_packet(chat_packet)
	_expect(
		bool(chat_decoded.get("ok", false)) and str(chat_decoded.payload.text) == "over the wire",
		"a chat line sent over real ENet comes back as a CHAT packet"
	)
	client.close()
	server.stop()
	server.free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
