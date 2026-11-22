extends SceneTree

const GameEntry = preload(
	"res://Framework/Infrastructure/API/Runtime/game_entry.gd"
)
const EnvironmentSetup = preload(
	"res://Framework/Env/Setup/Bootstrap/game_setup.gd"
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
	var player_id: int = _entry.entity_ids[&"player"]
	var second_id: int = _entry.entity_ids[&"second_player"]

	var before := runtime.read_attribute(
		player_id, &"abilities", ["reflex"]
	)
	var precognition_before := runtime.read_attribute(
		player_id, &"abilities", ["precognition"]
	)
	_expect("Player starts without reflex", not before["ok"])
	_expect("Player starts with precognition 5", (
		precognition_before["ok"]
		and precognition_before["value"] == 5
	))

	var notified: Array[StringName] = []
	runtime.attribute_written.connect(
		func(entity_id: int, container_id: StringName, attribute_name: StringName):
			if entity_id == player_id and container_id == &"abilities":
				notified.append(attribute_name)
	)

	var added := runtime.add_attribute(
		player_id, &"abilities", &"reflex", 12
	)
	var reflex := runtime.read_attribute(
		player_id, &"abilities", ["reflex"]
	)
	var precognition := runtime.read_attribute(
		player_id, &"abilities", ["precognition"]
	)
	_expect("Reflex added and readable", (
		added["ok"] and added["value"] == true
		and reflex["ok"] and reflex["value"] == 12
	))
	_expect("Precognition is preserved", (
		precognition["ok"] and precognition["value"] == 5
	))
	_expect("Insertion notifies listeners once", notified == [&"reflex"])

	var duplicate := runtime.add_attribute(
		player_id, &"abilities", &"reflex", 999
	)
	var after_duplicate := runtime.read_attribute(
		player_id, &"abilities", ["reflex"]
	)
	_expect("Duplicate insertion preserves the value", (
		not duplicate["ok"]
		and after_duplicate["ok"]
		and after_duplicate["value"] == 12
	))
	_expect("Rejected insertion emits no notifications", notified.size() == 1)

	var updated := runtime.write_attribute(
		player_id, &"abilities", ["reflex"], 13
	)
	var after_update := runtime.read_attribute(
		player_id, &"abilities", ["reflex"]
	)
	_expect("Connector can update the inserted attribute", (
		updated["ok"] and after_update["ok"]
		and after_update["value"] == 13
	))

	var other_reflex := runtime.read_attribute(
		second_id, &"abilities", ["reflex"]
	)
	_expect("Second Player remains unchanged", not other_reflex["ok"])

	var fresh_id := runtime.spawn(&"player")
	var fresh_reflex := runtime.read_attribute(
		fresh_id, &"abilities", ["reflex"]
	)
	_expect("New Players still use the original definition", (
		fresh_id > 0 and not fresh_reflex["ok"]
	))

	var tracking := {
		"rank": 1,
		"milestones": [{"rank": 1}],
	}
	var tracking_added := runtime.add_attribute(
		player_id, &"skills", &"tracking", tracking
	)
	tracking["rank"] = 99
	tracking["milestones"][0]["rank"] = 99

	var stored_tracking := runtime.read_attribute(
		player_id, &"skills", ["tracking"]
	)
	_expect("Nested collections are copied", (
		tracking_added["ok"] and stored_tracking["ok"]
		and stored_tracking["value"] == {
			"rank": 1,
			"milestones": [{"rank": 1}],
		}
	))

	var missing_container := runtime.add_attribute(
		player_id, &"missing_container", &"value", 1
	)
	_expect("Missing container is rejected", not missing_container["ok"])

	var unknown := runtime.add_attribute(
		0, &"abilities", &"reflex", 1
	)
	_expect("Unknown entity is rejected", not unknown["ok"])

	_entry.stop()
	var closed := runtime.add_attribute(
		player_id, &"abilities", &"another_ability", 1
	)
	_expect("Closed runtime is rejected", not closed["ok"])

	print("[attribute-add] Checks passed: ", _passed)
	quit(0 if _passed else 1)


func _expect(label: String, condition: bool) -> void:
	print("[attribute-add] ", label, ": ", condition)
	_passed = _passed and condition


func _finalize() -> void:
	_entry.stop()