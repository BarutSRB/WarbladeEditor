class_name ProtocolCodec
extends RefCounted

enum MessageType {
	HELLO = 1,
	WELCOME = 2,
	INPUT = 3,
	SHOP = 4,
	READY = 5,
	SNAPSHOT = 6,
	REJECT = 7,
	PING = 8,
	ACK = 9,
	PAUSE = 10,
	BONUS_ACTION = 11,
	RETIRE = 12,
	SAVE = 13,
	REPLAY_REQUEST = 14,
	REPLAY_DATA = 15,
	CHAT = 16,
	PUNCH = 17,
}

const MAGIC: int = 0x57425231
const VERSION: int = 8
const SNAPSHOT_VERSION: int = 12
const REPLAY_VERSION: int = 12
const HASH_STATE_VERSION: int = 12
const HEADER_SIZE: int = 16
const MAX_PACKET_SIZE: int = 524288
const MAX_SNAPSHOT_SIZE: int = MAX_PACKET_SIZE - HEADER_SIZE
const MAX_TOKEN_BYTES: int = 64
const CONTENT_HASH_BYTES: int = 64
const MAX_MATCH_REQUEST_BYTES: int = 16384
const MAX_CHAT_BYTES: int = 200
const MAX_NICKNAME_BYTES: int = 16
const MAX_ENDPOINT_BYTES: int = 45
const SEAT_BOTH: int = 255
const BONUS_ACTION_SELECT_TILE: int = 1
const BONUS_ACTION_KILL_TIME: int = 2
const BONUS_ACTION_NO_TILE: int = 0xffff


## The v6 HELLO carries the client's requested match contract as a bounded
## JSON document. An empty request joins whatever match the server is already
## running; a non-empty request either configures an idle server or must equal
## the running contract exactly.
static func encode_hello(
	token: String,
	requested_seat: int,
	content_hash: String,
	sequence: int,
	match_request: Dictionary = {}
) -> PackedByteArray:
	if token.to_utf8_buffer().size() > MAX_TOKEN_BYTES:
		return PackedByteArray()
	if content_hash.to_utf8_buffer().size() > CONTENT_HASH_BYTES:
		return PackedByteArray()
	var request_bytes := PackedByteArray()
	if not match_request.is_empty():
		request_bytes = JSON.stringify(match_request).to_utf8_buffer()
		if request_bytes.size() > MAX_MATCH_REQUEST_BYTES:
			return PackedByteArray()
	var payload := _new_buffer()
	_put_short_string(payload, token)
	payload.put_u8(requested_seat)
	_put_short_string(payload, content_hash)
	payload.put_u16(request_bytes.size())
	payload.put_data(request_bytes)
	return _frame(MessageType.HELLO, sequence, payload.data_array)


static func encode_welcome(seat_id: int, server_tick: int, port: int, content_hash: String, sequence: int) -> PackedByteArray:
	var payload := _new_buffer()
	payload.put_u8(seat_id)
	payload.put_u32(server_tick)
	payload.put_u16(port)
	_put_short_string(payload, content_hash)
	return _frame(MessageType.WELCOME, sequence, payload.data_array)


static func encode_input(seat_id: int, client_tick: int, action_mask: int, sequence: int) -> PackedByteArray:
	var payload := _new_buffer()
	payload.put_u8(seat_id)
	payload.put_u32(client_tick)
	payload.put_u16(action_mask)
	return _frame(MessageType.INPUT, sequence, payload.data_array)


static func encode_shop(seat_id: int, item_id: int, nonce: int, sequence: int) -> PackedByteArray:
	var payload := _new_buffer()
	payload.put_u8(seat_id)
	payload.put_u16(item_id)
	payload.put_u32(nonce)
	return _frame(MessageType.SHOP, sequence, payload.data_array)


static func encode_ready(seat_id: int, ready: bool, sequence: int) -> PackedByteArray:
	var payload := _new_buffer()
	payload.put_u8(seat_id)
	payload.put_u8(1 if ready else 0)
	return _frame(MessageType.READY, sequence, payload.data_array)


static func encode_pause(seat_id: int, paused: bool, sequence: int) -> PackedByteArray:
	var payload := _new_buffer()
	payload.put_u8(seat_id)
	payload.put_u8(1 if paused else 0)
	return _frame(MessageType.PAUSE, sequence, payload.data_array)


static func encode_retire(seat_id: int, sequence: int) -> PackedByteArray:
	var payload := _new_buffer()
	payload.put_u8(seat_id)
	return _frame(MessageType.RETIRE, sequence, payload.data_array)


## Retail only writes a saved game from the shop, and the authoritative
## simulation owns the state, so the client asks the server to write a slot.
static func encode_save(seat_id: int, slot: int, sequence: int) -> PackedByteArray:
	var payload := _new_buffer()
	payload.put_u8(seat_id)
	payload.put_u8(slot)
	return _frame(MessageType.SAVE, sequence, payload.data_array)


static func encode_bonus_action(
	seat_id: int,
	client_tick: int,
	action_kind: int,
	tile_index: int,
	sequence: int
) -> PackedByteArray:
	if action_kind not in [BONUS_ACTION_SELECT_TILE, BONUS_ACTION_KILL_TIME]:
		return PackedByteArray()
	if action_kind == BONUS_ACTION_SELECT_TILE and (tile_index < 0 or tile_index > 63):
		return PackedByteArray()
	var payload := _new_buffer()
	payload.put_u8(seat_id)
	payload.put_u32(client_tick)
	payload.put_u8(action_kind)
	payload.put_u16(tile_index if action_kind == BONUS_ACTION_SELECT_TILE else BONUS_ACTION_NO_TILE)
	return _frame(MessageType.BONUS_ACTION, sequence, payload.data_array)


## v7: a seat-owning peer asks for the finished match's replay so it can be
## submitted for talent-point verification. Only valid once the run is
## terminal; the server answers with gzip-compressed REPLAY_DATA chunks.
static func encode_replay_request(seat_id: int, sequence: int) -> PackedByteArray:
	var payload := _new_buffer()
	payload.put_u8(seat_id)
	return _frame(MessageType.REPLAY_REQUEST, sequence, payload.data_array)


static func encode_replay_data(
	chunk_index: int,
	chunk_count: int,
	total_bytes: int,
	bytes: PackedByteArray,
	sequence: int
) -> PackedByteArray:
	if chunk_count < 1 or chunk_index < 0 or chunk_index >= chunk_count:
		return PackedByteArray()
	var payload := _new_buffer()
	payload.put_u16(chunk_index)
	payload.put_u16(chunk_count)
	payload.put_u32(total_bytes)
	payload.put_data(bytes)
	return _frame(MessageType.REPLAY_DATA, sequence, payload.data_array)


static func encode_snapshot(snapshot: Dictionary, sequence: int) -> PackedByteArray:
	var json_bytes := JSON.stringify(snapshot).to_utf8_buffer()
	if json_bytes.size() > MAX_SNAPSHOT_SIZE:
		return PackedByteArray()
	return _frame(MessageType.SNAPSHOT, sequence, json_bytes)


static func encode_reject(code: int, reason: String, sequence: int) -> PackedByteArray:
	var payload := _new_buffer()
	payload.put_u8(code)
	_put_long_string(payload, reason.left(128))
	return _frame(MessageType.REJECT, sequence, payload.data_array)


static func encode_ping(client_tick: int, sequence: int) -> PackedByteArray:
	var payload := _new_buffer()
	payload.put_u32(client_tick)
	return _frame(MessageType.PING, sequence, payload.data_array)


static func encode_ack(request_type: int, accepted: bool, server_tick: int, details: Dictionary, sequence: int) -> PackedByteArray:
	var payload := _new_buffer()
	payload.put_u8(request_type)
	payload.put_u8(1 if accepted else 0)
	payload.put_u32(server_tick)
	var details_bytes := JSON.stringify(details).to_utf8_buffer()
	if details_bytes.size() > 4096:
		return PackedByteArray()
	payload.put_u16(details_bytes.size())
	payload.put_data(details_bytes)
	return _frame(MessageType.ACK, sequence, payload.data_array)


## v8: a party chat line. A seat owner sends it to the game server, which
## rebroadcasts the same layout to every authenticated peer (sender included).
static func encode_chat(seat_id: int, nickname: String, text: String, sequence: int) -> PackedByteArray:
	var text_bytes := text.to_utf8_buffer()
	if nickname.to_utf8_buffer().size() > MAX_NICKNAME_BYTES:
		return PackedByteArray()
	if text_bytes.is_empty() or text_bytes.size() > MAX_CHAT_BYTES:
		return PackedByteArray()
	var payload := _new_buffer()
	payload.put_u8(seat_id)
	_put_short_string(payload, nickname)
	_put_long_string(payload, text)
	return _frame(MessageType.CHAT, sequence, payload.data_array)


## v8: the seat-0 owner asks its publicly bound game server to send
## hole-punch datagrams toward a joiner's endpoint.
static func encode_punch(seat_id: int, address: String, port: int, sequence: int) -> PackedByteArray:
	if not address.is_valid_ip_address() or port < 1 or port > 65535:
		return PackedByteArray()
	var payload := _new_buffer()
	payload.put_u8(seat_id)
	_put_short_string(payload, address)
	payload.put_u16(port)
	return _frame(MessageType.PUNCH, sequence, payload.data_array)


static func decode_packet(packet: PackedByteArray) -> Dictionary:
	if packet.size() < HEADER_SIZE:
		return _error("packet_too_short")
	if packet.size() > MAX_PACKET_SIZE:
		return _error("packet_too_large")
	var stream := _new_buffer()
	stream.data_array = packet
	if stream.get_u32() != MAGIC:
		return _error("bad_magic")
	if stream.get_u16() != VERSION:
		return _error("bad_version")
	var message_type := stream.get_u8()
	stream.get_u8()
	var payload_size := stream.get_u32()
	var sequence := stream.get_u32()
	if payload_size > MAX_SNAPSHOT_SIZE:
		return _error("payload_too_large")
	if payload_size != packet.size() - HEADER_SIZE:
		return _error("size_mismatch")
	if not _is_known_type(message_type):
		return _error("unknown_type")
	var payload_bytes: PackedByteArray = stream.get_data(payload_size)[1]
	var decoded_payload := _decode_payload(message_type, payload_bytes)
	if not bool(decoded_payload.get("ok", false)):
		return decoded_payload
	return {
		"ok": true,
		"error": "",
		"type": message_type,
		"sequence": sequence,
		"payload": decoded_payload.payload,
	}


static func _decode_payload(message_type: int, bytes: PackedByteArray) -> Dictionary:
	var stream := _new_buffer()
	stream.data_array = bytes
	match message_type:
		MessageType.HELLO:
			var token_result := _get_short_string(stream, MAX_TOKEN_BYTES)
			if not token_result.ok or stream.get_available_bytes() < 2:
				return _error("malformed_hello")
			var requested_seat := stream.get_u8()
			var hash_result := _get_short_string(stream, CONTENT_HASH_BYTES)
			if not hash_result.ok or stream.get_available_bytes() < 2:
				return _error("malformed_hello")
			var request_size := stream.get_u16()
			if request_size > MAX_MATCH_REQUEST_BYTES or stream.get_available_bytes() != request_size:
				return _error("malformed_hello")
			var match_request: Dictionary = {}
			if request_size > 0:
				var request_bytes: PackedByteArray = stream.get_data(request_size)[1]
				var request_json := JSON.new()
				if (
					request_json.parse(request_bytes.get_string_from_utf8()) != OK
					or typeof(request_json.data) != TYPE_DICTIONARY
				):
					return _error("malformed_hello_match_request")
				match_request = request_json.data
			return _payload({
				"token": token_result.value,
				"requested_seat": requested_seat,
				"content_hash": hash_result.value,
				"match_request": match_request,
			})
		MessageType.WELCOME:
			if stream.get_available_bytes() < 8:
				return _error("malformed_welcome")
			var seat_id := stream.get_u8()
			var server_tick := stream.get_u32()
			var port := stream.get_u16()
			var hash_result := _get_short_string(stream, CONTENT_HASH_BYTES)
			if not hash_result.ok or stream.get_available_bytes() != 0:
				return _error("malformed_welcome")
			return _payload({
				"seat_id": seat_id,
				"server_tick": server_tick,
				"port": port,
				"content_hash": hash_result.value,
			})
		MessageType.INPUT:
			if bytes.size() != 7:
				return _error("malformed_input")
			return _payload({
				"seat_id": stream.get_u8(),
				"client_tick": stream.get_u32(),
				"action_mask": stream.get_u16(),
			})
		MessageType.SHOP:
			if bytes.size() != 7:
				return _error("malformed_shop")
			return _payload({
				"seat_id": stream.get_u8(),
				"item_id": stream.get_u16(),
				"nonce": stream.get_u32(),
			})
		MessageType.READY:
			if bytes.size() != 2:
				return _error("malformed_ready")
			var ready_value := stream.get_u8()
			var ready := stream.get_u8()
			if ready > 1:
				return _error("malformed_ready")
			return _payload({"seat_id": ready_value, "ready": ready == 1})
		MessageType.SNAPSHOT:
			if bytes.is_empty():
				return _error("malformed_snapshot")
			var json := JSON.new()
			if json.parse(bytes.get_string_from_utf8()) != OK or typeof(json.data) != TYPE_DICTIONARY:
				return _error("malformed_snapshot")
			return _payload(json.data)
		MessageType.REJECT:
			if stream.get_available_bytes() < 3:
				return _error("malformed_reject")
			var code := stream.get_u8()
			var reason_result := _get_long_string(stream, 128)
			if not reason_result.ok or stream.get_available_bytes() != 0:
				return _error("malformed_reject")
			return _payload({"code": code, "reason": reason_result.value})
		MessageType.PING:
			if bytes.size() != 4:
				return _error("malformed_ping")
			return _payload({"client_tick": stream.get_u32()})
		MessageType.ACK:
			if stream.get_available_bytes() < 8:
				return _error("malformed_ack")
			var request_type := stream.get_u8()
			var accepted_raw := stream.get_u8()
			var ack_server_tick := stream.get_u32()
			var details_size := stream.get_u16()
			if accepted_raw > 1 or details_size > 4096 or stream.get_available_bytes() != details_size:
				return _error("malformed_ack")
			var details_bytes: PackedByteArray = stream.get_data(details_size)[1]
			var details: Dictionary = {}
			if details_size > 0:
				var details_json := JSON.new()
				if details_json.parse(details_bytes.get_string_from_utf8()) != OK or typeof(details_json.data) != TYPE_DICTIONARY:
					return _error("malformed_ack")
				details = details_json.data
			return _payload({
				"request_type": request_type,
				"accepted": accepted_raw == 1,
				"server_tick": ack_server_tick,
				"details": details,
			})
		MessageType.PAUSE:
			if bytes.size() != 2:
				return _error("malformed_pause")
			var pause_seat := stream.get_u8()
			var paused := stream.get_u8()
			if paused > 1:
				return _error("malformed_pause")
			return _payload({"seat_id": pause_seat, "paused": paused == 1})
		MessageType.RETIRE:
			if bytes.size() != 1:
				return _error("malformed_retire")
			return _payload({"seat_id": stream.get_u8()})
		MessageType.SAVE:
			if bytes.size() != 2:
				return _error("malformed_save")
			var save_seat := stream.get_u8()
			return _payload({"seat_id": save_seat, "slot": stream.get_u8()})
		MessageType.BONUS_ACTION:
			if bytes.size() != 8:
				return _error("malformed_bonus_action")
			var bonus_seat := stream.get_u8()
			var client_tick := stream.get_u32()
			var action_kind := stream.get_u8()
			var tile_raw := stream.get_u16()
			if action_kind not in [BONUS_ACTION_SELECT_TILE, BONUS_ACTION_KILL_TIME]:
				return _error("malformed_bonus_action")
			if action_kind == BONUS_ACTION_SELECT_TILE and tile_raw > 63:
				return _error("malformed_bonus_action")
			if action_kind == BONUS_ACTION_KILL_TIME and tile_raw != BONUS_ACTION_NO_TILE:
				return _error("malformed_bonus_action")
			return _payload({
				"seat_id": bonus_seat,
				"client_tick": client_tick,
				"action_kind": action_kind,
				"tile_index": int(tile_raw) if action_kind == BONUS_ACTION_SELECT_TILE else -1,
			})
		MessageType.REPLAY_REQUEST:
			if bytes.size() != 1:
				return _error("malformed_replay_request")
			return _payload({"seat_id": stream.get_u8()})
		MessageType.REPLAY_DATA:
			if bytes.size() < 8:
				return _error("malformed_replay_data")
			var chunk_index := stream.get_u16()
			var chunk_count := stream.get_u16()
			var total_bytes := stream.get_u32()
			if chunk_count < 1 or chunk_index >= chunk_count:
				return _error("malformed_replay_data")
			var chunk_bytes: PackedByteArray = (
				stream.get_data(stream.get_available_bytes())[1]
				if stream.get_available_bytes() > 0
				else PackedByteArray()
			)
			return _payload({
				"chunk_index": chunk_index,
				"chunk_count": chunk_count,
				"total_bytes": total_bytes,
				"bytes": chunk_bytes,
			})
		MessageType.CHAT:
			if bytes.size() < 4:
				return _error("malformed_chat")
			var chat_seat := stream.get_u8()
			var nickname_result := _get_short_string(stream, MAX_NICKNAME_BYTES)
			if not nickname_result.ok:
				return _error("malformed_chat")
			var text_result := _get_long_string(stream, MAX_CHAT_BYTES)
			if (
				not text_result.ok
				or str(text_result.value).is_empty()
				or stream.get_available_bytes() != 0
			):
				return _error("malformed_chat")
			return _payload({
				"seat_id": chat_seat,
				"nickname": nickname_result.value,
				"text": text_result.value,
			})
		MessageType.PUNCH:
			if bytes.size() < 4:
				return _error("malformed_punch")
			var punch_seat := stream.get_u8()
			var address_result := _get_short_string(stream, MAX_ENDPOINT_BYTES)
			if (
				not address_result.ok
				or not str(address_result.value).is_valid_ip_address()
				or stream.get_available_bytes() != 2
			):
				return _error("malformed_punch")
			var punch_port := stream.get_u16()
			if punch_port == 0:
				return _error("malformed_punch")
			return _payload({
				"seat_id": punch_seat,
				"address": address_result.value,
				"port": punch_port,
			})
	return _error("unknown_type")


static func _frame(message_type: int, sequence: int, payload: PackedByteArray) -> PackedByteArray:
	if payload.size() > MAX_SNAPSHOT_SIZE:
		return PackedByteArray()
	var stream := _new_buffer()
	stream.put_u32(MAGIC)
	stream.put_u16(VERSION)
	stream.put_u8(message_type)
	stream.put_u8(0)
	stream.put_u32(payload.size())
	stream.put_u32(sequence)
	stream.put_data(payload)
	return stream.data_array


static func _new_buffer() -> StreamPeerBuffer:
	var stream := StreamPeerBuffer.new()
	stream.big_endian = true
	return stream


static func _put_short_string(stream: StreamPeerBuffer, value: String) -> void:
	var bytes := value.to_utf8_buffer()
	stream.put_u8(bytes.size())
	stream.put_data(bytes)


static func _put_long_string(stream: StreamPeerBuffer, value: String) -> void:
	var bytes := value.to_utf8_buffer()
	stream.put_u16(bytes.size())
	stream.put_data(bytes)


static func _get_short_string(stream: StreamPeerBuffer, maximum: int) -> Dictionary:
	if stream.get_available_bytes() < 1:
		return _error("missing_string")
	var size := stream.get_u8()
	if size > maximum or stream.get_available_bytes() < size:
		return _error("invalid_string")
	var bytes: PackedByteArray = stream.get_data(size)[1]
	return {"ok": true, "value": bytes.get_string_from_utf8()}


static func _get_long_string(stream: StreamPeerBuffer, maximum: int) -> Dictionary:
	if stream.get_available_bytes() < 2:
		return _error("missing_string")
	var size := stream.get_u16()
	if size > maximum or stream.get_available_bytes() < size:
		return _error("invalid_string")
	var bytes: PackedByteArray = stream.get_data(size)[1]
	return {"ok": true, "value": bytes.get_string_from_utf8()}


static func _is_known_type(message_type: int) -> bool:
	# An explicit set rather than a range: a new enum value must be added here
	# deliberately or its packets are rejected as unknown.
	return message_type in [
		MessageType.HELLO, MessageType.WELCOME, MessageType.INPUT,
		MessageType.SHOP, MessageType.READY, MessageType.SNAPSHOT,
		MessageType.REJECT, MessageType.PING, MessageType.ACK,
		MessageType.PAUSE, MessageType.BONUS_ACTION, MessageType.RETIRE,
		MessageType.SAVE, MessageType.REPLAY_REQUEST, MessageType.REPLAY_DATA,
		MessageType.CHAT, MessageType.PUNCH,
	]


static func _payload(value: Dictionary) -> Dictionary:
	return {"ok": true, "error": "", "payload": value}


static func _error(reason: String) -> Dictionary:
	return {"ok": false, "error": reason}
