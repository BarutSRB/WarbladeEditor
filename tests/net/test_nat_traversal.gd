extends SceneTree

## NAT traversal mechanics on loopback, in seconds: the sidecar's rendezvous
## keepalive leaves through its ENet socket, a foreign echo hitting that
## socket is harmless, a seat-zero PUNCH makes the sidecar emit datagrams to
## a listener, an ENet client can pin its local port, and the joiner probe
## learns its endpoint from a fake echo server.

const Protocol := preload("res://src/net/protocol_codec.gd")
const Server := preload("res://src/server/authoritative_server.gd")
const MatchContract := preload("res://src/shared/match_contract.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_codec()
	_test_sidecar_keepalive()
	_test_punch_datagrams()
	_test_client_local_port()
	await _test_probe_against_fake_echo()
	if _failures.is_empty():
		print("NAT TRAVERSAL TESTS PASSED")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _pump(server: AuthoritativeServer, listener: PacketPeerUDP, timeout_msec: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_msec
	while Time.get_ticks_msec() < deadline:
		if server != null:
			server.poll_network()
		if listener.get_available_packet_count() > 0:
			return true
		OS.delay_msec(2)
	return listener.get_available_packet_count() > 0


func _test_codec() -> void:
	var nonce_hex := WBRendezvousCodec.make_nonce_hex()
	_expect(WBRendezvousCodec.is_valid_nonce_hex(nonce_hex), "a fresh nonce is 32 hex characters")
	var nonce := WBRendezvousCodec.nonce_from_hex(nonce_hex)
	var ping := WBRendezvousCodec.encode_ping(nonce)
	_expect(ping.size() == WBRendezvousCodec.REQUEST_SIZE, "a ping is 22 bytes")
	_expect(ping.slice(0, 4).get_string_from_ascii() == "WBRZ" and int(ping[5]) == WBRendezvousCodec.KIND_PING, "a ping carries the magic and kind")
	var echo := WBRendezvousCodec.encode_echo(nonce, "203.0.113.9", 42000)
	var decoded := WBRendezvousCodec.decode_echo(echo)
	_expect(bool(decoded.ok) and str(decoded.ip) == "203.0.113.9" and int(decoded.port) == 42000, "an echo round-trips")
	_expect(str(decoded.nonce) == nonce_hex, "an echo carries the nonce")
	_expect(not bool(WBRendezvousCodec.decode_echo(ping).ok), "a ping is not an echo")
	_expect(not bool(WBRendezvousCodec.decode_echo(PackedByteArray([1, 2, 3])).ok), "garbage is not an echo")
	_expect(WBRendezvousCodec.nonce_from_hex("zz").is_empty(), "a bad nonce decodes to nothing")


func _test_sidecar_keepalive() -> void:
	var fake := PacketPeerUDP.new()
	_expect(fake.bind(0, "127.0.0.1") == OK, "the fake rendezvous binds")
	var fake_port := fake.get_local_port()
	var server := Server.new()
	root.add_child(server)
	var started := server.start_lobby("127.0.0.1", 0, "nat-token")
	_expect(bool(started.ok), "the keepalive test server starts")
	var rejected := server.configure_rendezvous("lobby.example.com", fake_port, WBRendezvousCodec.make_nonce_hex())
	_expect(not bool(rejected.ok), "the sidecar refuses a rendezvous host name")
	_expect(not bool(server.configure_rendezvous("127.0.0.1", 0, WBRendezvousCodec.make_nonce_hex()).ok), "the sidecar refuses port zero")
	_expect(not bool(server.configure_rendezvous("127.0.0.1", fake_port, "abc").ok), "the sidecar refuses a short nonce")
	var nonce_hex := WBRendezvousCodec.make_nonce_hex()
	var configured := server.configure_rendezvous("127.0.0.1", fake_port, nonce_hex)
	_expect(bool(configured.ok), "the sidecar accepts a valid rendezvous triple")
	_expect(_pump(server, fake, 1000), "the first keepalive leaves right away")
	var packet := fake.get_packet()
	_expect(packet == WBRendezvousCodec.encode_ping(WBRendezvousCodec.nonce_from_hex(nonce_hex)), "the keepalive is the nonce ping")
	_expect(fake.get_packet_port() == server.listen_port, "the keepalive leaves through the ENet socket's port")
	fake.set_dest_address(fake.get_packet_ip(), fake.get_packet_port())
	fake.put_packet(WBRendezvousCodec.encode_echo(WBRendezvousCodec.nonce_from_hex(nonce_hex), "127.0.0.1", server.listen_port))
	for index in range(20):
		server.poll_network()
		OS.delay_msec(2)
	_expect(server.running, "a foreign echo on the ENet socket does not stop the server")
	_expect((server.get_connection_state().peers as Dictionary).is_empty(), "a foreign echo never becomes a peer")
	_expect(server.send_rendezvous_keepalive(), "keepalives can be sent on demand")
	_expect(_pump(server, fake, 1000), "the on-demand keepalive arrives")
	var state: Dictionary = server.get_connection_state().rendezvous
	_expect(bool(state.configured) and int(state.keepalives_sent) >= 2, "the state reports the keepalives sent")
	server.stop()
	server.free()
	fake.close()


func _test_punch_datagrams() -> void:
	var listener := PacketPeerUDP.new()
	_expect(listener.bind(0, "127.0.0.1") == OK, "the punch listener binds")
	var server := Server.new()
	root.add_child(server)
	var config := {
		"protocol_version": Protocol.VERSION,
		"content_version": MatchContract.CONTENT_VERSION,
		"start_level": 1,
		"end_level": 3,
		"mode": "coop",
		"difficulty": "normal",
		"record_replay": false,
	}
	var started := server.start_local(config, "", 0, "punch-token")
	_expect(bool(started.ok), "the punch test server starts")
	var client := ENetMultiplayerPeer.new()
	_expect(client.create_client("127.0.0.1", int(started.port)) == OK, "the punch client starts")
	for attempt in range(500):
		server.poll_network()
		client.poll()
		if client.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			break
		OS.delay_msec(1)
	client.set_target_peer(1)
	client.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
	client.put_packet(Protocol.encode_hello("punch-token", 0, String(started.content_hash), 1))
	var welcomed := false
	for attempt in range(500):
		server.poll_network()
		client.poll()
		while client.get_available_packet_count() > 0:
			var decoded := Protocol.decode_packet(client.get_packet())
			if bool(decoded.get("ok", false)) and int(decoded.get("type", 0)) == Protocol.MessageType.WELCOME:
				welcomed = true
		if welcomed:
			break
		OS.delay_msec(1)
	_expect(welcomed, "the punch client authenticates as seat zero")
	server._lobby = true
	server._bind_host = "*"
	client.put_packet(Protocol.encode_punch(0, "127.0.0.1", listener.get_local_port(), 2))
	var acknowledged := false
	var accepted := false
	var datagrams := 0
	var deadline := Time.get_ticks_msec() + 1500
	while Time.get_ticks_msec() < deadline:
		server.poll_network()
		client.poll()
		while client.get_available_packet_count() > 0:
			var decoded := Protocol.decode_packet(client.get_packet())
			if (
				bool(decoded.get("ok", false))
				and int(decoded.get("type", 0)) == Protocol.MessageType.ACK
				and int(decoded.payload.get("request_type", 0)) == Protocol.MessageType.PUNCH
			):
				acknowledged = true
				accepted = bool(decoded.payload.get("accepted", false))
		while listener.get_available_packet_count() > 0:
			var datagram := listener.get_packet()
			if datagram.size() == WBRendezvousCodec.REQUEST_SIZE and int(datagram[5]) == WBRendezvousCodec.KIND_PUNCH:
				datagrams += 1
				_expect(listener.get_packet_port() == server.listen_port, "punch datagrams leave through the ENet socket")
		if acknowledged and datagrams >= Server.PUNCH_BURST_COUNT:
			break
		OS.delay_msec(2)
	_expect(acknowledged and accepted, "the punch is acknowledged as accepted")
	_expect(datagrams >= Server.PUNCH_BURST_COUNT, "the burst of punch datagrams reaches the listener (%d)" % datagrams)
	client.close()
	server.stop()
	server.free()
	listener.close()


func _test_client_local_port() -> void:
	var server := Server.new()
	root.add_child(server)
	var started := server.start_lobby("127.0.0.1", 0, "port-token")
	_expect(bool(started.ok), "the local-port test server starts")
	var reserve := PacketPeerUDP.new()
	_expect(reserve.bind(0, "*") == OK, "a temporary probe socket binds")
	var local_port := reserve.get_local_port()
	reserve.close()
	var client := ENetMultiplayerPeer.new()
	_expect(client.create_client("127.0.0.1", int(started.port), 0, 0, 0, local_port) == OK, "the client binds the probe's port")
	_expect(client.host != null and client.host.get_local_port() == local_port, "the ENet socket sits on the requested local port")
	for attempt in range(500):
		server.poll_network()
		client.poll()
		if client.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			break
		OS.delay_msec(1)
	_expect(client.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED, "the pinned client connects")
	var rebind := PacketPeerUDP.new()
	_expect(rebind.bind(local_port, "*") != OK, "the pinned port is busy while the client lives")
	rebind.close()
	# The server registers the peer on its own next poll.
	for attempt in range(500):
		server.poll_network()
		client.poll()
		if not (server.get_connection_state().peers as Dictionary).is_empty():
			break
		OS.delay_msec(1)
	var seen_remote_port := 0
	for peer_id_value in server.get_connection_state().peers.keys():
		var enet_peer: ENetPacketPeer = server._peer.get_peer(int(peer_id_value))
		if enet_peer != null:
			seen_remote_port = enet_peer.get_remote_port()
	_expect(seen_remote_port == local_port, "the server sees the client's pinned source port")
	client.close()
	server.stop()
	server.free()


func _test_probe_against_fake_echo() -> void:
	var fake := PacketPeerUDP.new()
	_expect(fake.bind(0, "127.0.0.1") == OK, "the fake echo server binds")
	var probe := WBRendezvous.new()
	root.add_child(probe)
	var results: Array = []
	probe.probe_finished.connect(func(result: Dictionary) -> void: results.append(result))
	var nonce_hex := WBRendezvousCodec.make_nonce_hex()
	_expect(probe.begin_probe("127.0.0.1", fake.get_local_port(), nonce_hex), "the probe starts")
	var local_port := probe.probe_local_port()
	_expect(local_port > 0, "the probe binds a local port")
	var deadline := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline and results.is_empty():
		while fake.get_available_packet_count() > 0:
			var packet := fake.get_packet()
			if packet == WBRendezvousCodec.encode_ping(WBRendezvousCodec.nonce_from_hex(nonce_hex)):
				fake.set_dest_address(fake.get_packet_ip(), fake.get_packet_port())
				fake.put_packet(WBRendezvousCodec.encode_echo(
					WBRendezvousCodec.nonce_from_hex(nonce_hex), "127.0.0.1", fake.get_packet_port()
				))
		await process_frame
	_expect(not results.is_empty(), "the probe finishes")
	if not results.is_empty():
		var result: Dictionary = results[0]
		_expect(bool(result.ok), "the probe succeeds against the fake echo")
		_expect(int(result.port) == local_port and int(result.local_port) == local_port, "the echo reports the probe's own port on loopback")
		_expect(str(result.ip) == "127.0.0.1", "the echo reports the loopback address")
	_expect(not probe.is_probing(), "the probe releases its port on completion")
	var reuse := ENetMultiplayerPeer.new()
	_expect(reuse.create_client("127.0.0.1", fake.get_local_port(), 0, 0, 0, local_port) == OK, "ENet can take over the probe's port")
	reuse.close()
	var silent := WBRendezvous.new()
	root.add_child(silent)
	var silent_results: Array = []
	silent.probe_finished.connect(func(result: Dictionary) -> void: silent_results.append(result))
	_expect(silent.begin_probe("127.0.0.1", 1, WBRendezvousCodec.make_nonce_hex()), "a probe toward a dead port starts")
	var silent_deadline := Time.get_ticks_msec() + WBRendezvous.PROBE_TIMEOUT_MSEC + 1000
	while Time.get_ticks_msec() < silent_deadline and silent_results.is_empty():
		await process_frame
	_expect(not silent_results.is_empty() and not bool((silent_results[0] as Dictionary).ok), "a silent rendezvous times out")
	probe.free()
	silent.free()
	fake.close()
