extends SceneTree

## Host/join over loopback with a real sidecar process: the host adapter
## spawns its game server bound publicly on a fixed port and authors a co-op
## match as seat 0; the joiner adapter dials the host's candidates from a
## fixed local port (a dead one first), joins as seat 1, both exchange party
## chat through the sidecar, and the host's PUNCH is acknowledged by the
## public bind. About ten seconds; no lobby server involved.

const HOST_PORT := 42111
const DEAD_PORT := 42112
const TOKEN := "lan-test-token"

var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _test_host_join_over_loopback()
	if _failures.is_empty():
		print("HOST/JOIN LAN TESTS PASSED")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _wait_until(adapters: Array, predicate: Callable, timeout_msec: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_msec
	while Time.get_ticks_msec() < deadline:
		for adapter_value in adapters:
			(adapter_value as WBNetworkSessionAdapter).poll()
		if bool(predicate.call()):
			return true
		await process_frame
	return bool(predicate.call())


func _test_host_join_over_loopback() -> void:
	var config := WBMatchConfig.make("coop", "normal", "classic", [], "pixel", 4242)
	var host := WBNetworkSessionAdapter.new()
	var host_failures: Array = []
	host.session_failed.connect(func(message: String) -> void: host_failures.append(message))
	var host_chat: Array = []
	host.chat_received.connect(
		func(seat_id: int, nickname: String, text: String) -> void:
			host_chat.append([seat_id, nickname, text])
	)
	var punches: Array = []
	host.punch_acknowledged.connect(
		func(accepted: bool, details: Dictionary) -> void: punches.append([accepted, details])
	)
	_expect(
		host.configure(config, {"kind": "host", "port": HOST_PORT, "token": TOKEN}),
		"the host adapter accepts the host connection kind (%s)" % host.last_error()
	)
	_expect(
		await _wait_until([host], func() -> bool: return host.is_ready(), 20000),
		"the host authenticates against its publicly bound sidecar (%s)" % host.last_error()
	)
	if not host.is_ready():
		host.close()
		return
	_expect(host.endpoint_description().begins_with("HOSTING ON UDP PORT"), "the host names its listening port")
	_expect(host.listen_port() == HOST_PORT, "the sidecar bound the requested host port")
	_expect(
		await _wait_until([host], func() -> bool: return bool(host.get_snapshot().get("waiting_for_seats", false)), 10000),
		"a hosted co-op match waits for its second seat"
	)

	var joiner := WBNetworkSessionAdapter.new()
	var joiner_failures: Array = []
	joiner.session_failed.connect(func(message: String) -> void: joiner_failures.append(message))
	var joiner_chat: Array = []
	joiner.chat_received.connect(
		func(seat_id: int, nickname: String, text: String) -> void:
			joiner_chat.append([seat_id, nickname, text])
	)
	var join_config := config.duplicate(true)
	_expect(
		joiner.configure(join_config, {
			"kind": "join",
			"candidates": [
				{"host": "127.0.0.1", "port": DEAD_PORT, "lan": true},
				{"host": "127.0.0.1", "port": HOST_PORT, "lan": true},
			],
			"token": TOKEN,
			"local_port": 0,
			"seat": 1,
		}),
		"the joiner adapter accepts the join connection kind (%s)" % joiner.last_error()
	)
	_expect(
		await _wait_until([host, joiner], func() -> bool: return joiner.is_ready(), 25000),
		"the joiner authenticates through the surviving candidate (%s)" % joiner.last_error()
	)
	_expect(joiner.dial_candidate_index() == 1, "the dialer fell through the dead candidate")
	_expect(
		await _wait_until([host, joiner], func() -> bool: return not bool(host.get_snapshot().get("waiting_for_seats", true)), 10000),
		"the joiner's seat fills the hosted match"
	)

	_expect(host.send_chat("welcome", "ALPHA"), "the host sends a party line")
	_expect(
		await _wait_until([host, joiner], func() -> bool: return joiner_chat.size() >= 1 and host_chat.size() >= 1, 5000),
		"the sidecar relays the host's line to both peers"
	)
	if not joiner_chat.is_empty():
		_expect(str((joiner_chat[0] as Array)[1]) == "ALPHA" and str((joiner_chat[0] as Array)[2]) == "welcome", "the joiner sees the host's nickname and text")
	_expect(joiner.send_chat("hello", "BRAVO"), "the joiner sends a party line")
	_expect(
		await _wait_until([host, joiner], func() -> bool: return host_chat.size() >= 2, 5000),
		"the sidecar relays the joiner's line to the host"
	)
	if host_chat.size() >= 2:
		_expect(int((host_chat[1] as Array)[0]) == 1 and str((host_chat[1] as Array)[1]) == "BRAVO", "the host sees the joiner's seat and nickname")

	_expect(host.punch_request("127.0.0.1", 40000), "the host may ask its sidecar to punch")
	_expect(
		await _wait_until([host, joiner], func() -> bool: return punches.size() >= 1, 5000),
		"the punch request is acknowledged"
	)
	if not punches.is_empty():
		_expect(bool((punches[0] as Array)[0]), "a publicly bound sidecar accepts the punch")
	_expect(not joiner.punch_request("127.0.0.1", 40000), "a joiner cannot ask for punches")
	_expect(host_failures.is_empty() and joiner_failures.is_empty(), "no session failed: %s %s" % [host_failures, joiner_failures])
	joiner.close()
	# Let the sidecar see the joiner leave before the host goes too.
	await _wait_until([host], func() -> bool: return bool(host.get_snapshot().get("waiting_for_seats", false)), 5000)
	_expect(bool(host.get_snapshot().get("waiting_for_seats", false)), "the host's match waits again after the joiner leaves")
	host.close()
	await process_frame
