extends SceneTree

## Covers the lobby client seam: WBIdentityStore persistence, WBTalentCache,
## WBTalentCatalog rules/composition, the WBFakeLobbyClient lifecycle and
## pushes, and the offline behaviour of the transport-less base client. No
## network access.

var _failures: Array[String] = []


func _initialize() -> void:
	_test_identity_store()
	_test_talent_cache()
	_test_talent_catalog_rules()
	_test_talent_catalog_composition()
	await _test_fake_lobby_lifecycle()
	await _test_fake_lobby_failures_and_pushes()
	await _test_offline_base_client()
	if _failures.is_empty():
		print("LOBBY CLIENT TESTS PASSED")
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


func _test_identity_store() -> void:
	var store := WBIdentityStore.new()
	store.configure_path("user://test_identity_store.json")
	store.clear()
	store.load_identity()
	var key := store.device_key()
	_expect(WBIdentityStore.is_valid_device_key(key), "a fresh store generates a 64-hex device key")
	_expect(not store.has_nickname(), "a fresh store has no nickname")
	var profile_id := store.profile_id()
	_expect(profile_id.begins_with("dev_"), "profile ids carry the dev_ prefix")
	_expect_equal(profile_id.length(), 4 + 16, "profile ids are the prefix plus 16 hex characters")
	_expect(not profile_id.contains(key.substr(0, 8)), "profile ids never expose the key")
	_expect(not store.set_nickname("no"), "short nicknames are rejected")
	_expect(not store.set_nickname("bad name"), "nicknames with spaces are rejected")
	_expect(store.set_nickname("PILOT_1"), "a valid nickname is stored")
	var reloaded := WBIdentityStore.new()
	reloaded.configure_path("user://test_identity_store.json")
	reloaded.load_identity()
	_expect_equal(reloaded.device_key(), key, "the device key survives a reload")
	_expect_equal(reloaded.nickname(), "PILOT_1", "the nickname survives a reload")
	_expect_equal(reloaded.profile_id(), profile_id, "the profile id is stable")
	_expect(reloaded.set_nickname(""), "the nickname can be cleared")
	_expect(reloaded.clear(), "clear removes the file")
	var regenerated := WBIdentityStore.new()
	regenerated.configure_path("user://test_identity_store.json")
	regenerated.load_identity()
	_expect(regenerated.device_key() != key, "a cleared store generates a new key")
	regenerated.clear()


func _test_talent_cache() -> void:
	var cache := WBTalentCache.new()
	cache.configure_path("user://test_talent_cache_store.json")
	cache.clear()
	_expect(cache.load_state().is_empty(), "a missing cache loads empty")
	var state := {"wallet": {"talent_points": 12}, "talents": {"nodes": {"gunnery_capacity_1": 1}}}
	_expect(cache.store_state(state), "the cache stores a state")
	var reloaded := WBTalentCache.new()
	reloaded.configure_path("user://test_talent_cache_store.json")
	var loaded := reloaded.load_state()
	_expect_equal(int((loaded.get("wallet", {}) as Dictionary).get("talent_points", 0)), 12, "the cached wallet survives a reload")
	_expect(reloaded.clear(), "clear removes the cache file")
	_expect(reloaded.load_state().is_empty(), "a cleared cache loads empty")


func _test_talent_catalog_rules() -> void:
	var catalog := WBTalentCatalog.new()
	_expect(catalog.load_catalog(), "catalog loads from content/talents.json")
	_expect(catalog.version() >= 1, "catalog reports a version")
	_expect_equal(catalog.branches().size(), 4, "four branches ship in v1")
	_expect(catalog.talent_gated_effects().has("enable_autofire"), "auto fire is talent-gated")
	_expect(catalog.applies_to_mode("solo"), "talents apply to solo")
	_expect(catalog.applies_to_mode("coop"), "talents apply to coop")
	_expect(not catalog.applies_to_mode("time_trial"), "time trial stays talent-free")
	var fresh: Dictionary = {}
	var root_node := catalog.validate_spend(fresh, "gunnery_capacity_1")
	_expect(bool(root_node["ok"]), "root node is purchasable")
	_expect_equal(int(root_node["cost"]), 10, "root node costs 10")
	var unknown := catalog.validate_spend(fresh, "no_such_node")
	_expect_equal(
		unknown["error"]["code"], WBLobbyContract.ERR_TALENT_UNKNOWN_NODE,
		"unknown node is rejected"
	)
	var gated := catalog.validate_spend(fresh, "gunnery_capacity_2")
	_expect_equal(
		gated["error"]["code"], WBLobbyContract.ERR_TALENT_PREREQ_MISSING,
		"missing prerequisite is rejected"
	)
	var owned := {"gunnery_capacity_1": 1}
	_expect(bool(catalog.validate_spend(owned, "gunnery_capacity_2")["ok"]), "chain unlocks")
	var repeat := catalog.validate_spend(owned, "gunnery_capacity_1")
	_expect_equal(
		repeat["error"]["code"], WBLobbyContract.ERR_TALENT_ALREADY_OWNED,
		"owned node cannot be re-bought"
	)


func _test_talent_catalog_composition() -> void:
	var catalog := WBTalentCatalog.new()
	catalog.load_catalog()
	var owned := {
		"gunnery_capacity_1": 1,
		"gunnery_capacity_2": 1,
		"gunnery_bullet_speed": 1,
		"gunnery_autofire_license": 1,
		"ordnance_rocket_license": 1,
		"ordnance_rockets_1": 1,
		"ordnance_rockets_2": 1,
		"vanished_node": 1,
	}
	var grants := catalog.compose_grants(owned)
	_expect_equal(
		int((grants["start_state"] as Dictionary)["bullet_capacity"]), 12,
		"int grants take the MAX"
	)
	_expect_equal(
		(grants["start_state"] as Dictionary).get("bullet_speed_up"), true,
		"bool grants OR in"
	)
	_expect_equal(int(grants["starting_rockets"]), 20, "rockets take the MAX")
	_expect_equal(
		grants["shop_unlocks"], ["enable_autofire", "rocket_pack"] as Array[String],
		"shop unlocks are collected sorted"
	)
	_expect_equal(catalog.spent_total(owned), 10 + 20 + 25 + 30 + 15 + 20 + 35,
		"spent total prices vanished nodes at zero")
	var empty := catalog.compose_grants({})
	_expect((empty["start_state"] as Dictionary).is_empty(), "no talents, no grants")


func _test_fake_lobby_lifecycle() -> void:
	var identity := WBIdentityStore.new()
	identity.configure_path("user://test_lobby_identity.json")
	identity.clear()
	identity.load_identity()
	var cache := WBTalentCache.new()
	cache.configure_path("user://test_lobby_cache.json")
	cache.clear()
	var client := WBFakeLobbyClient.new()
	client.taken_nicknames = ["ace"] as Array[String]
	client.configure(identity, "127.0.0.1", 7400, 7401, cache)
	var states: Array = []
	var profile_events: Array = []
	client.state_changed.connect(func(state: String) -> void: states.append(state))
	client.profile_state_updated.connect(func(state: Dictionary) -> void: profile_events.append(state))

	_expect(not client.is_online(), "the fake starts offline")
	var offline: Dictionary = await client.fetch_profile_state()
	_expect_equal(
		WBLobbyContract.error_code(offline), WBLobbyContract.ERR_OFFLINE,
		"requests fail with OFFLINE before connecting"
	)
	client.connect_now()
	_expect(client.is_online(), "connect_now brings the fake online")
	_expect(not client.is_registered(), "an identity without a nickname is not registered")
	_expect_equal(states, ["online"], "the state signal fired once")

	var taken: Dictionary = await client.register_nickname("ACE")
	_expect_equal(
		WBLobbyContract.error_code(taken), WBLobbyContract.ERR_NICKNAME_TAKEN,
		"a taken nickname is refused"
	)
	var invalid: Dictionary = await client.register_nickname("a b")
	_expect_equal(
		WBLobbyContract.error_code(invalid), WBLobbyContract.ERR_INVALID_NICKNAME,
		"an invalid nickname is refused locally"
	)
	var registered: Dictionary = await client.register_nickname("PILOT")
	_expect(bool(registered["ok"]), "a free nickname registers")
	_expect(client.is_registered(), "registration binds the session")
	_expect_equal(client.nickname(), "PILOT", "the client reports the nickname")
	_expect_equal(identity.nickname(), "PILOT", "registration stores the nickname in the identity")
	_expect(not cache.load_state().is_empty(), "registration caches the talent state")

	client.grant_points(35)
	var fetched: Dictionary = await client.fetch_profile_state()
	_expect(bool(fetched["ok"]), "profile fetch succeeds when registered")
	_expect_equal(client.current_points(), 35, "faucet points visible")

	var spend: Dictionary = await client.spend_talent("gunnery_capacity_1")
	_expect(bool(spend["ok"]), "spend succeeds")
	_expect_equal(client.current_points(), 25, "cost deducted")
	_expect_equal(client.owned_talents(), {"gunnery_capacity_1": 1}, "node owned")
	_expect_equal(
		int((client.current_grants()["start_state"] as Dictionary)["bullet_capacity"]), 8,
		"grants recomputed after spend"
	)
	var blocked: Dictionary = await client.spend_talent("gunnery_capacity_3")
	_expect_equal(
		WBLobbyContract.error_code(blocked), WBLobbyContract.ERR_TALENT_PREREQ_MISSING,
		"prerequisite enforcement mirrors the server"
	)
	var second: Dictionary = await client.spend_talent("gunnery_capacity_2")
	_expect(bool(second["ok"]), "second spend fits the remaining points")
	var broke: Dictionary = await client.spend_talent("gunnery_bullet_speed")
	_expect_equal(
		WBLobbyContract.error_code(broke), WBLobbyContract.ERR_INSUFFICIENT_POINTS,
		"insufficient points are rejected"
	)
	var respec: Dictionary = await client.respec()
	_expect(bool(respec["ok"]), "respec succeeds")
	_expect_equal(client.current_points(), 35, "respec refunds every point")
	_expect(client.owned_talents().is_empty(), "respec clears the tree")
	_expect(profile_events.size() >= 4, "profile updates emitted along the way")

	var chats: Array = []
	client.chat_message.connect(func(message: Dictionary) -> void: chats.append(message))
	var sent: Dictionary = await client.send_chat("  hello  ")
	_expect(bool(sent["ok"]), "chat sends")
	_expect_equal(chats.size(), 1, "the sender receives its own line as a push")
	_expect_equal(str((chats[0] as Dictionary).get("body", "")), "hello", "chat bodies are trimmed")
	var too_long: Dictionary = await client.send_chat("x".repeat(201))
	_expect(not bool(too_long["ok"]), "oversized chat is refused locally")
	var history: Dictionary = await client.chat_history()
	_expect_equal((history["messages"] as Array).size(), 1, "history returns the stored line")

	var credits: Array = []
	client.points_credited.connect(func(amount: int, reason: String) -> void: credits.append([amount, reason]))
	var ended: Dictionary = await client.report_match_end({"kind": "solo", "score": 1000})
	_expect(bool(ended["ok"]), "match reports succeed")
	_expect_equal(credits.size(), 1, "a credited match emits points_credited")
	_expect_equal(client.current_points(), 35 + client.credit_points_per_match, "the credit lands in the wallet")

	var listed: Dictionary = await client.list_lobbies()
	_expect((listed["lobbies"] as Array).is_empty(), "no lobbies exist yet")
	var created: Dictionary = await client.create_lobby({"name": "SMOKE", "mode": "coop"})
	_expect(bool(created["ok"]), "lobby creation succeeds")
	var lobby_id := str((created["lobby"] as Dictionary).get("lobby_id", ""))
	listed = await client.list_lobbies()
	_expect_equal((listed["lobbies"] as Array).size(), 1, "the created lobby is listed")
	var closed: Dictionary = await client.close_lobby(lobby_id)
	_expect(bool(closed["ok"]), "lobby close succeeds")
	listed = await client.list_lobbies()
	_expect((listed["lobbies"] as Array).is_empty(), "a closed lobby disappears")

	client.disconnect_now()
	_expect(not client.is_online() and not client.is_registered(), "disconnect drops the session")
	_expect_equal(client.current_points(), 35 + client.credit_points_per_match, "cached points survive disconnecting")
	client.free()
	identity.clear()
	cache.clear()


func _test_fake_lobby_failures_and_pushes() -> void:
	var identity := WBIdentityStore.new()
	identity.configure_path("user://test_lobby_identity_2.json")
	identity.clear()
	identity.load_identity()
	identity.set_nickname("PILOT")
	var client := WBFakeLobbyClient.new()
	client.configure(identity, "127.0.0.1", 7400)
	var failures: Array = []
	client.request_failed.connect(
		func(operation: String, error: Dictionary) -> void: failures.append([operation, error["code"]])
	)
	client.connect_now()
	_expect(client.is_registered(), "an identity with a nickname is registered on connect")
	client.fail_next_operation = WBLobbyContract.T_TALENT_STATE
	var failed: Dictionary = await client.fetch_profile_state()
	_expect_equal(
		WBLobbyContract.error_code(failed), WBLobbyContract.ERR_UNREACHABLE,
		"forced failure surfaces as unreachable"
	)
	var retry: Dictionary = await client.fetch_profile_state()
	_expect(bool(retry["ok"]), "failure is one-shot; retry succeeds")
	_expect_equal(failures.size(), 1, "request_failed emitted once")

	var offers: Array = []
	var closed: Array = []
	client.lobby_join_offer.connect(func(offer: Dictionary) -> void: offers.append(offer))
	client.lobby_closed.connect(func(info: Dictionary) -> void: closed.append(info))
	client.push_server_message({"t": WBLobbyContract.PUSH_LOBBY_JOIN_OFFER, "join_id": 7})
	client.push_server_message({"t": WBLobbyContract.PUSH_LOBBY_CLOSED, "lobby_id": "x"})
	client.push_server_message({"t": "unknown_push"})
	_expect_equal(offers.size(), 1, "a join offer push raises its signal")
	_expect_equal(int((offers[0] as Dictionary).get("join_id", 0)), 7, "the push payload rides the signal")
	_expect_equal(closed.size(), 1, "a lobby closed push raises its signal")
	var credited: Array = []
	client.points_credited.connect(func(amount: int, _reason: String) -> void: credited.append(amount))
	client.push_server_message({
		"t": WBLobbyContract.PUSH_POINTS_CREDITED,
		"points": 9,
		"state": {"wallet": {"talent_points": 9}},
	})
	_expect_equal(credited, [9], "a credit push emits points_credited")
	_expect_equal(client.current_points(), 9, "a credit push refreshes the cached state")
	client.free()
	identity.clear()


func _test_offline_base_client() -> void:
	var identity := WBIdentityStore.new()
	identity.configure_path("user://test_lobby_identity_3.json")
	identity.clear()
	identity.load_identity()
	var client := WBLobbyClient.new()
	client.configure(identity, "", 7400)
	_expect(not client.is_configured(), "an empty address is not configured")
	client.connect_now()
	_expect(not client.is_online(), "the transport-less base client stays offline")
	var result: Dictionary = await client.spend_talent("gunnery_capacity_1")
	_expect_equal(
		WBLobbyContract.error_code(result), WBLobbyContract.ERR_OFFLINE,
		"offline requests answer OFFLINE"
	)
	client.seed_profile_state({"wallet": {"talent_points": 4}, "grants": {"start_state": {"money": 5}}})
	_expect_equal(client.current_points(), 4, "seeded state answers points offline")
	_expect_equal(int((client.current_grants()["start_state"] as Dictionary)["money"]), 5, "seeded grants apply offline")
	_expect(WBLobbyContract.is_valid_nickname("Pilot_9"), "valid nicknames pass")
	_expect(not WBLobbyContract.is_valid_nickname("pi"), "short nicknames fail")
	_expect(not WBLobbyContract.is_valid_nickname("seventeen_chars__"), "long nicknames fail")
	_expect_equal(WBLobbyContract.ws_url("lobby.example.com", 7400), "ws://lobby.example.com:7400/ws", "the socket url is well formed")
	_expect_equal(WBLobbyContract.backoff_seconds(0), 1.0, "backoff starts at one second")
	_expect_equal(WBLobbyContract.backoff_seconds(99), 30.0, "backoff caps at thirty seconds")
	client.free()
	identity.clear()
