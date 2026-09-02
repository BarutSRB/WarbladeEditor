class_name WBRendezvous
extends Node

## Client-side NAT helpers for online co-op:
## - the LAN address a host advertises,
## - the UDP probe a joiner sends to the lobby server from the local port it
##   will play on, learning its public endpoint from the echo,
## - the UPnP port mapping a host attempts on a background thread.
## Add it to the tree; the probe polls in _process and UPnP results arrive
## through call_deferred, so both signals fire on the main thread.

signal probe_finished(result: Dictionary)
signal upnp_finished(result: Dictionary)

const PROBE_RESEND_MSEC := 500
const PROBE_TIMEOUT_MSEC := 3000
const UPNP_DISCOVER_MSEC := 1000
const UPNP_DESCRIPTION := "Warblade Remake"

var _probe: PacketPeerUDP = null
var _probe_nonce := PackedByteArray()
var _probe_started_msec := 0
var _probe_last_send_msec := 0
var _probe_local_port := 0
var _upnp_thread: Thread = null


func _ready() -> void:
	set_process(false)


func _exit_tree() -> void:
	close_probe()
	if _upnp_thread != null:
		_upnp_thread.wait_to_finish()
		_upnp_thread = null


## The first private IPv4 address of this machine, or "" when none exists.
static func local_lan_ipv4() -> String:
	for address_value in IP.get_local_addresses():
		var address := str(address_value)
		if not address.is_valid_ip_address() or address.contains(":"):
			continue
		if is_private_ipv4(address):
			return address
	return ""


static func is_private_ipv4(address: String) -> bool:
	var parts := address.split(".")
	if parts.size() != 4:
		return false
	var first := int(parts[0])
	var second := int(parts[1])
	if first == 10:
		return true
	if first == 172 and second >= 16 and second <= 31:
		return true
	if first == 192 and second == 168:
		return true
	return false


static func make_nonce_hex() -> String:
	return WBRendezvousCodec.make_nonce_hex()


## Resolves a lobby host name to an IPv4 address (an IP passes through).
static func resolve_ipv4(host: String) -> String:
	var trimmed := host.strip_edges()
	if trimmed.is_valid_ip_address():
		return trimmed
	if trimmed.is_empty():
		return ""
	var resolved := IP.resolve_hostname(trimmed, IP.TYPE_IPV4)
	return resolved if resolved.is_valid_ip_address() else ""


## --- Probe -----------------------------------------------------------------

## Binds a fresh local UDP port and pings the rendezvous server with the
## nonce until it echoes the public endpoint (probe_finished) or the timeout
## passes. The local port is released on completion so ENet can take it.
func begin_probe(host: String, port: int, nonce_hex: String) -> bool:
	close_probe()
	_probe_nonce = WBRendezvousCodec.nonce_from_hex(nonce_hex)
	var address := resolve_ipv4(host)
	if _probe_nonce.is_empty() or address.is_empty() or port < 1 or port > 65535:
		return false
	_probe = PacketPeerUDP.new()
	if _probe.bind(0, "*") != OK:
		_probe = null
		return false
	_probe_local_port = _probe.get_local_port()
	if _probe.set_dest_address(address, port) != OK:
		close_probe()
		return false
	_probe_started_msec = Time.get_ticks_msec()
	_probe_last_send_msec = 0
	_send_probe()
	set_process(true)
	return true


func is_probing() -> bool:
	return _probe != null


func probe_local_port() -> int:
	return _probe_local_port


func close_probe() -> void:
	if _probe != null:
		_probe.close()
		_probe = null
	set_process(false)


func _process(_delta: float) -> void:
	if _probe == null:
		set_process(false)
		return
	var now := Time.get_ticks_msec()
	while _probe != null and _probe.get_available_packet_count() > 0:
		var packet := _probe.get_packet()
		var echo := WBRendezvousCodec.decode_echo(packet)
		if bool(echo.get("ok", false)) and str(echo.get("nonce", "")) == _probe_nonce.hex_encode():
			var result := {
				"ok": true,
				"ip": str(echo.get("ip", "")),
				"port": int(echo.get("port", 0)),
				"local_port": _probe_local_port,
			}
			close_probe()
			probe_finished.emit(result)
			return
	if now - _probe_started_msec > PROBE_TIMEOUT_MSEC:
		var local_port := _probe_local_port
		close_probe()
		probe_finished.emit({
			"ok": false,
			"error": "no echo from the rendezvous server",
			"local_port": local_port,
		})
		return
	if now - _probe_last_send_msec >= PROBE_RESEND_MSEC:
		_send_probe()


func _send_probe() -> void:
	_probe_last_send_msec = Time.get_ticks_msec()
	_probe.put_packet(WBRendezvousCodec.encode_ping(_probe_nonce))


## --- UPnP ------------------------------------------------------------------

## Maps the UDP port on the router (discovery blocks, so it runs on a
## thread); upnp_finished carries {ok, port, external_ip, error}.
func map_port_async(port: int) -> bool:
	return _start_upnp(port, true)


func unmap_port_async(port: int) -> bool:
	return _start_upnp(port, false)


func is_upnp_busy() -> bool:
	return _upnp_thread != null


func _start_upnp(port: int, map: bool) -> bool:
	if _upnp_thread != null or port < 1 or port > 65535:
		return false
	_upnp_thread = Thread.new()
	if _upnp_thread.start(_upnp_worker.bind(port, map)) != OK:
		_upnp_thread = null
		return false
	return true


func _upnp_worker(port: int, map: bool) -> void:
	var result := upnp_blocking(port, map)
	call_deferred("_on_upnp_done", result)


static func upnp_blocking(port: int, map: bool) -> Dictionary:
	var upnp := UPNP.new()
	var discovered := upnp.discover(UPNP_DISCOVER_MSEC, 2)
	if discovered != UPNP.UPNP_RESULT_SUCCESS:
		return {"ok": false, "action": "map" if map else "unmap", "port": port, "error": "no UPnP gateway (%d)" % discovered}
	var gateway := upnp.get_gateway()
	if gateway == null or not gateway.is_valid_gateway():
		return {"ok": false, "action": "map" if map else "unmap", "port": port, "error": "no valid UPnP gateway"}
	if not map:
		upnp.delete_port_mapping(port, "UDP")
		return {"ok": true, "action": "unmap", "port": port}
	var mapped := upnp.add_port_mapping(port, port, UPNP_DESCRIPTION, "UDP", 0)
	if mapped == UPNP.UPNP_RESULT_CONFLICT_WITH_OTHER_MAPPING:
		upnp.delete_port_mapping(port, "UDP")
		mapped = upnp.add_port_mapping(port, port, UPNP_DESCRIPTION, "UDP", 0)
	if mapped != UPNP.UPNP_RESULT_SUCCESS:
		return {"ok": false, "action": "map", "port": port, "error": "port mapping refused (%d)" % mapped}
	return {"ok": true, "action": "map", "port": port, "external_ip": upnp.query_external_address()}


func _on_upnp_done(result: Dictionary) -> void:
	if _upnp_thread != null:
		_upnp_thread.wait_to_finish()
		_upnp_thread = null
	upnp_finished.emit(result)
