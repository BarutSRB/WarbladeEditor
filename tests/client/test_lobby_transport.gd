extends SceneTree

## Drives the real WBLobbyClient WebSocket transport against a spawned
## lobby-server debug build on loopback: hello/auth, registration, chat, the
## duplicate-session kick, and going offline when the server dies. Skips
## cleanly when the binary has not been built (make lobby-build).

const BINARY := "res://lobby-server/target/debug/warblade-lobby"
const WS_PORT := 17420
const UDP_PORT := 17421

var _failures: Array[String] = []
var _pid := 0
var _db_path := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var binary := ProjectSettings.globalize_path(BINARY)
	if not FileAccess.file_exists(binary):
		print("LOBBY TRANSPORT TESTS SKIPPED: build the server first (make lobby-build)")
		quit(0)
		return
	_db_path = ProjectSettings.globalize_path(
		"user://test_lobby_transport_%d.db" % OS.get_process_id()
	)
	_pid = OS.create_process("/usr/bin/env", PackedStringArray([
		"WB_WS_BIND=127.0.0.1:%d" % WS_PORT,
		"WB_UDP_BIND=127.0.0.1:%d" % UDP_PORT,
		"WB_DB_PATH=%s" % _db_path,
		"WB_TALENTS_PATH=%s" % ProjectSettings.globalize_path("res://content/talents.json"),
		"WB_LOG=warn",
		binary,
	]))
	if _pid <= 0:
		push_error("could not spawn the lobby server")
		quit(1)
		return
	await _test_transport_round_trip()
	_stop_server()
	if _failures.is_empty():
		print("LOBBY TRANSPORT TESTS PASSED")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append("%s (expected %s, got %s)" % [message, str(expected), str(actual)])


func _wait_until(predicate: Callable, timeout_msec: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_msec
	while Time.get_ticks_msec() < deadline:
		if bool(predicate.call()):
			return true
		await process_frame
	return bool(predicate.call())


func _stop_server() -> void:
	if _pid > 0:
		OS.kill(_pid)
		_pid = 0
	for suffix: String in ["", "-wal", "-shm"]:
		var path: String = _db_path + suffix
		if not path.is_empty() and FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


## The whole NAT path on loopback through the real server: a hosting sidecar
## keeps the rendezvous socket informed, the lobby server tells the host
## client the endpoint it observed, a created lobby advertises it, and a
## joiner probe learns its own endpoint from the same socket.
func _test_rendezvous_path(client: WBLobbyClient) -> void:
	var observed: Array = []
	client.rendezvous_observed.connect(func(info: Dictionary) -> void: observed.append(info))
	var nonce := WBRendezvous.make_nonce_hex()
	var registered: Dictionary = await client.register_rendezvous(nonce)
	_expect(bool(registered.get("ok", false)), "the nonce registers")
	_expect(registered.get("observed") == null, "a fresh nonce has no observation")
	var host := WBNetworkSessionAdapter.new()
	var config := WBMatchConfig.make("coop", "normal", "classic", [], "pixel", 77)
	_expect(
		host.configure(config, {
			"kind": "host",
			"port": 42123,
			"token": "rv-token",
			"rendezvous": "127.0.0.1:%d" % UDP_PORT,
			"nonce": nonce,
		}),
		"the host adapter accepts rendezvous arguments"
	)
	var host_ready := await _wait_until(func() -> bool:
		host.poll()
		return host.is_ready()
	, 20000)
	_expect(host_ready, "the hosting sidecar starts with rendezvous arguments (%s)" % host.last_error())
	var seen := await _wait_until(func() -> bool:
		host.poll()
		return observed.size() >= 1
	, 10000)
	_expect(seen, "the lobby server reports the sidecar's observed endpoint")
	if seen:
		var public: Dictionary = (observed[0] as Dictionary).get("public", {})
		_expect(int(public.get("port", 0)) == 42123, "the observed port is the sidecar's UDP port")
		_expect(str(public.get("ip", "")) == "127.0.0.1", "the observed address is loopback here")
	var created: Dictionary = await client.create_lobby({
		"name": "RV",
		"mode": "coop",
		"difficulty": "normal",
		"coop_balance": "classic",
		"game_token": "rv-token",
		"port": 42123,
		"upnp_mapped": false,
	})
	_expect(bool(created.get("ok", false)), "a lobby lists while the sidecar keeps the rendezvous alive")
	if bool(created.get("ok", false)):
		var lobby: Dictionary = created.get("lobby", {})
		var public_value: Variant = lobby.get("public")
		_expect(
			public_value is Dictionary and int((public_value as Dictionary).get("port", 0)) == 42123,
			"the lobby advertises the observed endpoint"
		)
		_expect(bool(lobby.get("host_fresh", false)), "the lobby's host counts as reachable")
		await client.close_lobby(str(lobby.get("lobby_id", "")))
	host.close()
	var probe := WBRendezvous.new()
	root.add_child(probe)
	var probes: Array = []
	probe.probe_finished.connect(func(result: Dictionary) -> void: probes.append(result))
	var probe_nonce := WBRendezvous.make_nonce_hex()
	await client.register_rendezvous(probe_nonce)
	_expect(probe.begin_probe("127.0.0.1", UDP_PORT, probe_nonce), "the joiner probe starts")
	_expect(await _wait_until(func() -> bool: return not probes.is_empty(), 5000), "the probe finishes against the real server")
	if not probes.is_empty():
		var result: Dictionary = probes[0]
		_expect(bool(result.get("ok", false)), "the probe learns its endpoint")
		_expect(int(result.get("port", 0)) == int(result.get("local_port", -1)), "on loopback the observed port is the local port")
	probe.free()


func _test_transport_round_trip() -> void:
	var identity := WBIdentityStore.new()
	identity.configure_path("user://test_transport_identity.json")
	identity.clear()
	identity.load_identity()
	var cache := WBTalentCache.new()
	cache.configure_path("user://test_transport_cache.json")
	cache.clear()
	var client := WBLobbyClient.new()
	client.configure(identity, "127.0.0.1", WS_PORT, UDP_PORT, cache)
	client.set_content_hash("a".repeat(64))
	client.set_client_version("test")
	root.add_child(client)
	var states: Array = []
	client.state_changed.connect(func(state: String) -> void: states.append(state))
	client.connect_now()
	_expect(
		await _wait_until(func() -> bool: return client.is_online(), 15000),
		"the client comes online against the spawned server (%s)" % client.last_drop_reason()
	)
	if not client.is_online():
		client.free()
		return
	_expect(states.has("connecting") and states.back() == "online", "the state signal walks connecting -> online")
	_expect(not client.is_registered(), "a fresh device key is not registered")
	_expect(int(client.server_info().get("protocol", 0)) == 1, "hello returns the server's protocol version")
	var nick := "TR_" + Crypto.new().generate_random_bytes(3).hex_encode().to_upper()
	var registered: Dictionary = await client.register_nickname(nick)
	_expect(bool(registered.get("ok", false)), "registration succeeds over the wire")
	_expect(client.is_registered() and client.nickname() == nick, "the client is registered under its nickname")
	_expect_equal(identity.nickname(), nick, "the identity file stores the nickname")
	_expect(not cache.load_state().is_empty(), "registration caches the talent state")
	var chats: Array = []
	client.chat_message.connect(func(message: Dictionary) -> void: chats.append(message))
	var sent: Dictionary = await client.send_chat("hello wire")
	_expect(bool(sent.get("ok", false)), "chat sends over the wire")
	_expect(
		await _wait_until(func() -> bool: return chats.size() >= 1, 3000),
		"the sender receives its own chat push"
	)
	var history: Dictionary = await client.chat_history()
	_expect(
		bool(history.get("ok", false)) and (history.get("messages", []) as Array).size() >= 1,
		"history returns the stored line"
	)
	var state: Dictionary = await client.fetch_profile_state()
	_expect(bool(state.get("ok", false)), "the talent state fetches")
	var lobbies: Dictionary = await client.list_lobbies()
	_expect(bool(lobbies.get("ok", false)), "the lobby list answers")
	var taken: Dictionary = await client.set_nickname(nick)
	_expect(bool(taken.get("ok", false)), "renaming to your own nickname is allowed")
	await _test_rendezvous_path(client)

	var kicked: Array = []
	client.kicked.connect(func(reason: String) -> void: kicked.append(reason))
	var second := WBLobbyClient.new()
	second.configure(identity, "127.0.0.1", WS_PORT, UDP_PORT)
	second.set_content_hash("a".repeat(64))
	root.add_child(second)
	second.connect_now()
	_expect(
		await _wait_until(func() -> bool: return second.is_registered(), 15000),
		"a second session with the same key authenticates as the account"
	)
	_expect_equal(second.nickname(), nick, "the account nickname comes back from the server")
	_expect(
		await _wait_until(func() -> bool: return kicked.size() >= 1, 5000),
		"the first session is kicked"
	)
	_expect(
		await _wait_until(func() -> bool: return not client.is_online(), 5000),
		"the kicked session goes offline"
	)
	var offline: Dictionary = await client.send_chat("nobody")
	_expect_equal(
		WBLobbyContract.error_code(offline), WBLobbyContract.ERR_OFFLINE,
		"requests on the kicked session answer OFFLINE"
	)

	_stop_server()
	_expect(
		await _wait_until(func() -> bool: return not second.is_online(), 10000),
		"losing the server takes the client offline"
	)
	_expect(not second.last_drop_reason().is_empty(), "the client records why it dropped")
	client.free()
	second.free()
	identity.clear()
	cache.clear()
