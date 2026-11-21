extends SceneTree

const GameEntry = preload(
	"res://Framework/Infrastructure/API/Runtime/game_entry.gd"
)
const EnvironmentSetup = preload(
	"res://Framework/Env/Setup/game_setup.gd"
)
const SessionCodec = preload(
	"res://Framework/Infrastructure/API/Persistence/session_codec.gd"
)

var _entry := GameEntry.new()
var _passed: bool = true


func _initialize() -> void:
	var started := _entry.start(EnvironmentSetup.new())
	if not started["ok"]:
		push_error(String(started["error"]))
		quit(1)
		return

	var runtime := _entry.runtime
	var guard_id := runtime.spawn(&"town_guard")
	_entry.entity_ids[&"town_guard_01"] = guard_id

	var player_id: int = _entry.entity_ids[&"player"]
	var health_changed := runtime.write_attribute(
		player_id, &"health", ["current"], 42
	)
	var probe_added := runtime.add_container(
		guard_id,
		&"codec_probe",
		{
			"id": &"ration",
			"text": "ration",
			"count": 2,
			"ratio": 1.25,
			"active": true,
			"optional": null,
			"nested": [{"id": &"ration", "count": 2}],
			"empty_array": [],
			"empty_dictionary": {},
		}
	)
	var empty_added := runtime.add_container(guard_id, &"empty_pack")

	var prepared: bool = (
		guard_id > 0
		and health_changed["ok"]
		and probe_added["ok"]
		and empty_added["ok"]
	)
	_expect("Session data prepared", prepared)
	if not prepared:
		quit(1)
		return

	var captured := _entry.snapshot_session()
	if not captured["ok"]:
		push_error(String(captured["error"]))
		quit(1)
		return

	var snapshot: Dictionary = captured["value"]
	var expected: Dictionary = snapshot.duplicate(true)

	var encoded := SessionCodec.encode(snapshot)
	_expect("Session encoded", encoded["ok"])
	if not encoded["ok"]:
		push_error(String(encoded["error"]))
		quit(1)
		return

	var bytes: PackedByteArray = encoded["value"]
	_expect("Encoded bytes are available", not bytes.is_empty())

	snapshot["entities"][&"town_guard_01"]["containers"][&"codec_probe"]["nested"][0]["count"] = 99
	_entry.stop()

	var decoded := SessionCodec.decode(bytes)
	_expect("Session decoded after source session closes", decoded["ok"])
	if not decoded["ok"]:
		push_error(String(decoded["error"]))
		quit(1)
		return

	var decoded_snapshot: Dictionary = decoded["value"]
	var entities: Dictionary = decoded_snapshot["entities"]
	var guard_record: Dictionary = entities[&"town_guard_01"]
	var containers: Dictionary = guard_record["containers"]
	var probe: Dictionary = containers[&"codec_probe"]

	_expect("Decoded values match the captured state", decoded_snapshot == expected)
	_expect("Entity keys remain StringName", _has_string_name_keys(entities))
	_expect("Container keys remain StringName", _has_string_name_keys(containers))
	_expect("StringName and String values retain their types", (
		typeof(guard_record["definition"]) == TYPE_STRING_NAME
		and typeof(probe["id"]) == TYPE_STRING_NAME
		and typeof(probe["text"]) == TYPE_STRING
	))
	_expect("Integer and float values retain their types", (
		typeof(probe["count"]) == TYPE_INT
		and typeof(probe["ratio"]) == TYPE_FLOAT
	))
	_expect("Boolean and null values retain their types", (
		typeof(probe["active"]) == TYPE_BOOL
		and typeof(probe["optional"]) == TYPE_NIL
	))
	_expect("Nested collections preserve types and values", (
		typeof(probe["nested"]) == TYPE_ARRAY
		and probe["nested"].size() == 1
		and typeof(probe["nested"][0]) == TYPE_DICTIONARY
		and typeof(probe["nested"][0]["id"]) == TYPE_STRING_NAME
		and probe["nested"][0]["count"] == 2
	))
	_expect("Empty collections and containers are preserved", (
		typeof(probe["empty_array"]) == TYPE_ARRAY
		and probe["empty_array"].is_empty()
		and typeof(probe["empty_dictionary"]) == TYPE_DICTIONARY
		and probe["empty_dictionary"].is_empty()
		and containers.has(&"empty_pack")
		and containers[&"empty_pack"].is_empty()
	))

	var restored := _entry.restore_session(
		EnvironmentSetup.new(), decoded_snapshot
	)
	_expect("Decoded snapshot restores successfully", restored["ok"])
	if not restored["ok"]:
		push_error(String(restored["error"]))
		quit(1)
		return

	var restored_snapshot := _entry.snapshot_session()
	_expect("Restored session matches the encoded state", (
		restored_snapshot["ok"]
		and restored_snapshot["value"] == expected
	))

	var decoded_again := SessionCodec.decode(bytes)
	probe["nested"][0]["count"] = 77
	decoded_snapshot["entities"].erase(&"enemy")

	_expect("Separate decodes own their collections", (
		decoded_again["ok"] and decoded_again["value"] == expected
	))

	var after_decoded_changes := _entry.snapshot_session()
	_expect("Decoded edits leave restored state unchanged", (
		after_decoded_changes["ok"]
		and after_decoded_changes["value"] == expected
	))

	_entry.stop()
	print("[codec] Checks passed: ", _passed)
	quit(0 if _passed else 1)


func _has_string_name_keys(data: Dictionary) -> bool:
	for key in data:
		if typeof(key) != TYPE_STRING_NAME:
			return false
	return true


func _expect(label: String, condition: bool) -> void:
	print("[codec] ", label, ": ", condition)
	_passed = _passed and condition


func _finalize() -> void:
	_entry.stop()