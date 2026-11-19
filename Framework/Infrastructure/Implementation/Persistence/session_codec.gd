extends RefCounted

const FORMAT_ID := "framework_session"
const FORMAT_VERSION: int = 1
const MAX_DEPTH: int = 128
const FRAME_MAGIC := "FWSC"
const FRAME_HEADER_SIZE: int = 44
const FRAME_HASH_SIZE: int = 32


static func encode(snapshot: Dictionary) -> Dictionary:
	if not snapshot.get("entities") is Dictionary:
		return _failure("Session snapshot requires an entities dictionary.")

	var data_error := _data_error(snapshot)
	if not data_error.is_empty():
		return _failure(data_error)

	var packet := {
		"format": FORMAT_ID,
		"version": FORMAT_VERSION,
		"snapshot": snapshot,
	}

	var payload := var_to_bytes(packet)
	if payload.is_empty():
		return _failure("Session snapshot could not be encoded.")

	return _frame_payload(payload)

static func decode(bytes: PackedByteArray) -> Dictionary:
	var unframed := _unframe_payload(bytes)
	if not unframed["ok"]:
		return unframed

	var payload: PackedByteArray = unframed["value"]
	if not payload.has_encoded_var(0, false):
		return _failure("Encoded session data is incomplete or invalid.")

	if payload.decode_var_size(0, false) != payload.size():
		return _failure("Encoded session data contains trailing bytes.")

	var decoded: Variant = bytes_to_var(payload)
	if not decoded is Dictionary:
		return _failure("Encoded session packet must be a dictionary.")

	var packet: Dictionary = decoded

	var format_id: Variant = packet.get("format")
	if typeof(format_id) != TYPE_STRING or format_id != FORMAT_ID:
		return _failure("Encoded data is not a framework session.")

	var version: Variant = packet.get("version")
	if typeof(version) != TYPE_INT or version != FORMAT_VERSION:
		return _failure("Unsupported session format version.")

	var saved_snapshot: Variant = packet.get("snapshot")
	if not saved_snapshot is Dictionary:
		return _failure("Encoded session packet requires a snapshot dictionary.")

	var snapshot: Dictionary = saved_snapshot
	if not snapshot.get("entities") is Dictionary:
		return _failure("Session snapshot requires an entities dictionary.")

	var data_error := _data_error(snapshot)
	if not data_error.is_empty():
		return _failure(data_error)

	return {
		"ok": true,
		"value": snapshot,
		"error": "",
	}

static func _frame_payload(payload: PackedByteArray) -> Dictionary:
	if payload.is_empty():
		return _failure("Session payload is empty.")

	var checksum := _checksum(payload)
	if checksum.size() != FRAME_HASH_SIZE:
		return _failure("Session checksum could not be calculated.")

	var length_bytes := PackedByteArray()
	if length_bytes.resize(8) != OK:
		return _failure("Session frame could not be allocated.")
	length_bytes.encode_u64(0, payload.size())

	# Four magic bytes, eight length bytes, 32 checksum bytes, then the payload.
	var frame := FRAME_MAGIC.to_utf8_buffer()
	frame.append_array(length_bytes)
	frame.append_array(checksum)
	frame.append_array(payload)

	return {"ok": true, "value": frame, "error": ""}


static func _unframe_payload(frame: PackedByteArray) -> Dictionary:
	if frame.size() < FRAME_HEADER_SIZE:
		return _failure("Encoded session frame is incomplete.")

	if frame.slice(0, 4) != FRAME_MAGIC.to_utf8_buffer():
		return _failure("Encoded session frame identifier is invalid.")

	var payload_size: int = frame.decode_u64(4)
	if payload_size < 4 or payload_size != frame.size() - FRAME_HEADER_SIZE:
		return _failure("Encoded session frame length does not match its payload.")

	var payload := frame.slice(FRAME_HEADER_SIZE)
	var expected_checksum := frame.slice(12, FRAME_HEADER_SIZE)
	var checksum := _checksum(payload)
	if checksum.size() != FRAME_HASH_SIZE:
		return _failure("Session checksum could not be calculated.")
	if checksum != expected_checksum:
		return _failure("Encoded session payload checksum does not match.")

	return {"ok": true, "value": payload, "error": ""}


static func _checksum(payload: PackedByteArray) -> PackedByteArray:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return PackedByteArray()
	if context.update(payload) != OK:
		return PackedByteArray()
	return context.finish()


static func _data_error(value: Variant, depth: int = 0) -> String:
	if depth > MAX_DEPTH:
		return "Snapshot data exceeds the supported nesting depth."

	if typeof(value) in [TYPE_OBJECT, TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID]:
		return "Unsupported snapshot value type: %s" % type_string(typeof(value))

	if value is Dictionary:
		for key in value:
			var key_error := _data_error(key, depth + 1)
			if not key_error.is_empty():
				return key_error

			var value_error := _data_error(value[key], depth + 1)
			if not value_error.is_empty():
				return value_error

	elif value is Array:
		for item in value:
			var item_error := _data_error(item, depth + 1)
			if not item_error.is_empty():
				return item_error

	return ""


static func _failure(message: String) -> Dictionary:
	return {
		"ok": false,
		"value": null,
		"error": message,
	}
