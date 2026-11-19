extends SceneTree

const SessionCodec = preload(
	"res://Framework/Infrastructure/API/Persistence/session_codec.gd"
)

var _passed: bool = true


func _initialize() -> void:
	var valid_snapshot := {"entities": {}}
	var encoded := SessionCodec.encode(valid_snapshot)
	if not encoded["ok"]:
		push_error(String(encoded["error"]))
		quit(1)
		return

	var valid_bytes: PackedByteArray = encoded["value"]

	_expect_rejected(
		"Empty bytes rejected",
		SessionCodec.decode(PackedByteArray()),
		"Encoded session frame is incomplete."
	)
	_expect_rejected(
		"Truncated header rejected before Variant decoding",
		SessionCodec.decode(valid_bytes.slice(0, 43)),
		"Encoded session frame is incomplete."
	)
	_expect_rejected(
		"Truncated packet rejected",
		SessionCodec.decode(valid_bytes.slice(0, valid_bytes.size() - 1)),
		"Encoded session frame length does not match its payload."
	)
	_expect_rejected(
		"Four-byte truncation rejected before Variant decoding",
		SessionCodec.decode(valid_bytes.slice(0, valid_bytes.size() - 4)),
		"Encoded session frame length does not match its payload."
	)

	var trailing_bytes := valid_bytes.duplicate()
	trailing_bytes.append(0)
	_expect_rejected(
		"Trailing bytes rejected",
		SessionCodec.decode(trailing_bytes),
		"Encoded session frame length does not match its payload."
	)

	var wrong_identifier := valid_bytes.duplicate()
	wrong_identifier[0] = wrong_identifier[0] ^ 1
	_expect_rejected(
		"Wrong frame identifier rejected",
		SessionCodec.decode(wrong_identifier),
		"Encoded session frame identifier is invalid."
	)

	var wrong_length := valid_bytes.duplicate()
	wrong_length.encode_u64(4, valid_bytes.size())
	_expect_rejected(
		"Wrong recorded length rejected",
		SessionCodec.decode(wrong_length),
		"Encoded session frame length does not match its payload."
	)

	var wrong_checksum := valid_bytes.duplicate()
	wrong_checksum[12] = wrong_checksum[12] ^ 1
	_expect_rejected(
		"Changed checksum rejected",
		SessionCodec.decode(wrong_checksum),
		"Encoded session payload checksum does not match."
	)

	var changed_payload := valid_bytes.duplicate()
	var last_index := changed_payload.size() - 1
	changed_payload[last_index] = changed_payload[last_index] ^ 1
	_expect_rejected(
		"Changed payload rejected before Variant decoding",
		SessionCodec.decode(changed_payload),
		"Encoded session payload checksum does not match."
	)

	var payload_with_trailing_bytes := var_to_bytes({
		"format": "framework_session",
		"version": 1,
		"snapshot": valid_snapshot,
	})
	payload_with_trailing_bytes.append(0)
	_expect_rejected(
		"Trailing Variant payload rejected inside a valid frame",
		SessionCodec.decode(_frame_bytes(payload_with_trailing_bytes)),
		"Encoded session data contains trailing bytes."
	)

	# These have valid outer frames so the decoder must reach each inner check.
	var invalid_packets := {
		"Non-dictionary packet": {
			"bytes": _framed_value("not a packet"),
			"error": "Encoded session packet must be a dictionary.",
		},
		"Wrong format marker": {
			"bytes": _packet_bytes(valid_snapshot, "another_format"),
			"error": "Encoded data is not a framework session.",
		},
		"Non-text format marker": {
			"bytes": _packet_bytes(valid_snapshot, 7),
			"error": "Encoded data is not a framework session.",
		},
		"Unsupported version": {
			"bytes": _packet_bytes(valid_snapshot, "framework_session", 2),
			"error": "Unsupported session format version.",
		},
		"Non-integer version": {
			"bytes": _packet_bytes(valid_snapshot, "framework_session", 1.0),
			"error": "Unsupported session format version.",
		},
		"Missing version": {
			"bytes": _framed_value({
				"format": "framework_session",
				"snapshot": valid_snapshot,
			}),
			"error": "Unsupported session format version.",
		},
		"Missing snapshot": {
			"bytes": _framed_value({
				"format": "framework_session",
				"version": 1,
			}),
			"error": "Encoded session packet requires a snapshot dictionary.",
		},
		"Non-dictionary snapshot": {
			"bytes": _packet_bytes([]),
			"error": "Encoded session packet requires a snapshot dictionary.",
		},
		"Missing entities": {
			"bytes": _packet_bytes({}),
			"error": "Session snapshot requires an entities dictionary.",
		},
		"Non-dictionary entities": {
			"bytes": _packet_bytes({"entities": []}),
			"error": "Session snapshot requires an entities dictionary.",
		},
		"Runtime-only decoded value": {
			"bytes": _packet_bytes(_snapshot_with_value(RID())),
			"error": "Unsupported snapshot value type: RID",
		},
	}

	for description in invalid_packets:
		var case_data: Dictionary = invalid_packets[description]
		_expect_rejected(
			"%s rejected" % description,
			SessionCodec.decode(case_data["bytes"]),
			case_data["error"]
		)

	_expect_rejected("Encoding missing entities rejected", SessionCodec.encode({}))
	_expect_rejected(
		"Encoding non-dictionary entities rejected",
		SessionCodec.encode({"entities": []})
	)

	var live_node := Node.new()
	var unsupported_values := {
		"Object": live_node,
		"Callable": Callable(),
		"Signal": Signal(),
		"RID": RID(),
	}
	for description in unsupported_values:
		_expect_rejected(
			"Encoding %s rejected" % description,
			SessionCodec.encode(
				_snapshot_with_value(unsupported_values[description])
			)
		)

	var object_keys: Dictionary = {}
	object_keys[live_node] = "value"
	_expect_rejected(
		"Unsupported dictionary key rejected",
		SessionCodec.encode(_snapshot_with_value(object_keys))
	)
	object_keys.clear()
	live_node.free()

	var nested: Variant = 0
	for _index in range(256):
		nested = [nested]

	_expect_rejected(
		"Excessive nesting rejected",
		SessionCodec.encode(_snapshot_with_value(nested))
	)

	var recovered := SessionCodec.decode(valid_bytes)
	_expect("Valid packet still decodes after rejections", (
		recovered["ok"] and recovered["value"] == valid_snapshot
	))

	print("[codec-failure] Checks passed: ", _passed)
	quit(0 if _passed else 1)


func _packet_bytes(
	snapshot: Variant,
	format_id: Variant = "framework_session",
	version: Variant = 1
) -> PackedByteArray:
	return _framed_value({
		"format": format_id,
		"version": version,
		"snapshot": snapshot,
	})


func _framed_value(packet: Variant) -> PackedByteArray:
	return _frame_bytes(var_to_bytes(packet))


# Build fixtures independently of the implementation's private frame helper.
func _frame_bytes(payload: PackedByteArray) -> PackedByteArray:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		push_error("Could not start the diagnostic checksum.")
		return PackedByteArray()
	if context.update(payload) != OK:
		push_error("Could not calculate the diagnostic checksum.")
		return PackedByteArray()

	var checksum := context.finish()
	if checksum.size() != 32:
		push_error("Diagnostic checksum has the wrong size.")
		return PackedByteArray()

	var length_bytes := PackedByteArray()
	if length_bytes.resize(8) != OK:
		push_error("Could not allocate the diagnostic frame.")
		return PackedByteArray()
	length_bytes.encode_u64(0, payload.size())

	var frame := "FWSC".to_utf8_buffer()
	frame.append_array(length_bytes)
	frame.append_array(checksum)
	frame.append_array(payload)
	return frame


func _snapshot_with_value(value: Variant) -> Dictionary:
	return {
		"entities": {
			&"town_guard_01": {
				"definition": &"town_guard",
				"containers": {
					&"codec_probe": {"value": value},
				},
			},
		},
	}


func _expect_rejected(
	label: String,
	result: Dictionary,
	expected_error: String = ""
) -> void:
	var rejected: bool = (
		not result["ok"]
		and result["value"] == null
		and not String(result["error"]).is_empty()
	)
	if not expected_error.is_empty():
		rejected = rejected and result["error"] == expected_error
	if not rejected:
		print("[codec-failure] Expected error: ", expected_error, "; got: ", result)
	_expect(label, rejected)


func _expect(label: String, condition: bool) -> void:
	print("[codec-failure] ", label, ": ", condition)
	_passed = _passed and condition
