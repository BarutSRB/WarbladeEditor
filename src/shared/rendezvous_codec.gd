class_name WBRendezvousCodec
extends RefCounted

## The UDP rendezvous datagrams shared by the hosting sidecar, a joiner's
## probe, and the lobby server (lobby-server/src/rendezvous.rs). Fixed-size,
## big-endian:
##   request (22 B): "WBRZ" | version u8 | kind u8 | nonce[16]
##   echo    (28 B): "WBRZ" | version u8 | kind u8 | nonce[16] | ipv4[4] | port u16
## A PING asks the server to echo the sender's public endpoint; a PUNCH is
## what a host sends toward a joiner so its router opens the path. Any
## datagram that reaches an ENet socket is discarded by ENet, so hosts can
## send freely from the game socket.

const MAGIC := "WBRZ"
const VERSION := 1
const KIND_PING := 1
const KIND_ECHO := 2
const KIND_PUNCH := 3
const NONCE_BYTES := 16
const REQUEST_SIZE := 22
const ECHO_SIZE := 28


static func make_nonce_hex() -> String:
	return Crypto.new().generate_random_bytes(NONCE_BYTES).hex_encode()


static func is_valid_nonce_hex(value: String) -> bool:
	if value.length() != NONCE_BYTES * 2:
		return false
	for character in value:
		if not "0123456789abcdef".contains(character):
			return false
	return true


static func nonce_from_hex(value: String) -> PackedByteArray:
	if not is_valid_nonce_hex(value.to_lower()):
		return PackedByteArray()
	return value.to_lower().hex_decode()


static func encode_ping(nonce: PackedByteArray) -> PackedByteArray:
	return _encode_request(KIND_PING, nonce)


static func encode_punch(nonce: PackedByteArray) -> PackedByteArray:
	return _encode_request(KIND_PUNCH, nonce)


static func _encode_request(kind: int, nonce: PackedByteArray) -> PackedByteArray:
	var padded := nonce.duplicate()
	padded.resize(NONCE_BYTES)
	var stream := StreamPeerBuffer.new()
	stream.big_endian = true
	stream.put_data(MAGIC.to_ascii_buffer())
	stream.put_u8(VERSION)
	stream.put_u8(kind)
	stream.put_data(padded)
	return stream.data_array


## Decodes an echo into {ok, nonce (hex), ip, port}; anything that is not a
## well-formed echo answers {ok: false}.
static func decode_echo(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() != ECHO_SIZE:
		return {"ok": false}
	if bytes.slice(0, 4).get_string_from_ascii() != MAGIC:
		return {"ok": false}
	if int(bytes[4]) != VERSION or int(bytes[5]) != KIND_ECHO:
		return {"ok": false}
	var nonce := bytes.slice(6, 6 + NONCE_BYTES)
	var ip := "%d.%d.%d.%d" % [int(bytes[22]), int(bytes[23]), int(bytes[24]), int(bytes[25])]
	var port := (int(bytes[26]) << 8) | int(bytes[27])
	if port == 0:
		return {"ok": false}
	return {"ok": true, "nonce": nonce.hex_encode(), "ip": ip, "port": port}


## Builds an echo (used by the loopback fake server in tests).
static func encode_echo(nonce: PackedByteArray, ip: String, port: int) -> PackedByteArray:
	var padded := nonce.duplicate()
	padded.resize(NONCE_BYTES)
	var stream := StreamPeerBuffer.new()
	stream.big_endian = true
	stream.put_data(MAGIC.to_ascii_buffer())
	stream.put_u8(VERSION)
	stream.put_u8(KIND_ECHO)
	stream.put_data(padded)
	for part in ip.split("."):
		stream.put_u8(int(part) & 0xff)
	stream.put_u16(port)
	return stream.data_array
